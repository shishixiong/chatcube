import { http } from '@kit.NetworkKit'
import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { ITtsEngine, TTSCallback } from './ITtsEngine'
import { AudioPlayerHelper, AudioPlayerCallback } from './AudioPlayerHelper'
import {
  DEEPSEEK_TTS_CONFIG,
  DEEPSEEK_TTS_PROVIDER_ID,
  DEEPSEEK_MAX_INPUT_CHARS
} from '../../config/TtsConfig'
import { getAppSettingsState } from '../../state/AppSettingsState'
import { splitTextForTts } from '../../utils/TtsTextChunkUtils'
import { findProviderApiKey } from '../../utils/TtsProviderKeyUtils'
import { TtsSessionGuard } from '../../utils/TtsSessionGuard'

const DEEPSEEK_ENGINE_ID: string = 'deepseek'

// DeepSeek 语音合成引擎 (HTTP 非流式 /v1/tools/tts, 缓冲整播)
// 与 StepFunTtsEngine 的差异:
//   1. 请求体是 { text, voice_id, format, filter_markdown }
//   2. 默认 wav (24kHz / 16-bit / 单声道), 直接交给 AVPlayer
//   3. 不支持语速调节, speak 的 speed 参数忽略
//   4. 单次上限 10000 计费字符 (汉字算 2), 按 2000 UTF-16 单元切段
export class DeepSeekTtsEngine implements ITtsEngine {
  private baseUrl: string = DEEPSEEK_TTS_CONFIG.apiUrl
  private speaking: boolean = false
  private currentCallback: TTSCallback | null = null
  private audioPlayer: AudioPlayerHelper = new AudioPlayerHelper()
  private inited: boolean = false
  private httpRequest: http.HttpRequest | null = null
  // 超长文本切段队列: 每段"合成→播放"完成后取下一段, 全部完成才回 onComplete
  private pendingChunks: string[] = []
  private chunkIndex: number = 0
  private startNotified: boolean = false
  // 会话守卫: 每次 speak 换新 token, stop 后迟到的网络/播放回调自动失效
  private guard: TtsSessionGuard = new TtsSessionGuard()

  async init(context: common.Context): Promise<void> {
    this.audioPlayer.init(context)
    this.inited = true
  }

  async speak(text: string, callback: TTSCallback, speed?: number): Promise<void> {
    if (!this.inited) {
      callback.onError('DeepSeek 朗读引擎未初始化')
      return
    }

    const apiKey = this.resolveApiKey()
    if (apiKey === '') {
      callback.onError('DeepSeek TTS 缺少 API Key，请先在服务商中配置 DeepSeek')
      return
    }

    if (this.speaking) {
      this.stop()
    }

    const seq = this.guard.begin()
    this.currentCallback = callback
    this.startNotified = false
    this.pendingChunks = splitTextForTts(text, DEEPSEEK_MAX_INPUT_CHARS)
    this.chunkIndex = 0

    if (this.pendingChunks.length === 0) {
      // TTSService 已拦截空文本, 此处防御
      this.guard.invalidate()
      callback.onError('没有可朗读的内容')
      return
    }

    this.fetchChunkAndPlay(apiKey, seq)
  }

  // 合成 pendingChunks[chunkIndex] 并播放; 播放完成由 playChunk 的回调驱动下一段
  private fetchChunkAndPlay(apiKey: string, seq: number): void {
    if (!this.guard.isActive(seq)) {
      return
    }
    const chunk = this.pendingChunks[this.chunkIndex]
    const requestBody = JSON.stringify({
      text: chunk,
      voice_id: this.resolveVoice(),
      format: DEEPSEEK_TTS_CONFIG.audioFormat,
      filter_markdown: true
    } as DeepSeekTtsRequestBody)

    const httpReq = http.createHttp()
    this.httpRequest = httpReq

    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      },
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      extraData: requestBody,
      connectTimeout: 15000,
      readTimeout: 120000
    }

    httpReq.request(this.baseUrl, options).then((resp: http.HttpResponse) => {
      if (this.httpRequest === httpReq) {
        this.httpRequest = null
      }
      if (!this.guard.isActive(seq)) {
        // 主动 stop / 已被新会话取代后到达的响应, 直接丢弃
        return
      }
      if (resp.responseCode !== 200) {
        this.finishWithError(seq, this.describeHttpError(resp.responseCode, this.decodeErrorBody(resp.result)))
        return
      }
      const audioBuffer = resp.result as ArrayBuffer
      if (audioBuffer.byteLength === 0) {
        this.finishWithError(seq, 'DeepSeek TTS 返回空音频数据')
        return
      }
      this.playChunk(audioBuffer, seq)
    }).catch((error: Error) => {
      if (this.httpRequest === httpReq) {
        this.httpRequest = null
      }
      // 主动 stop 触发的请求失败不报错
      if (!this.guard.isActive(seq)) {
        return
      }
      this.finishWithError(seq, `DeepSeek 朗读失败: ${error.message}`)
    })
  }

  private playChunk(audioBuffer: ArrayBuffer, seq: number): void {
    const audioCallback: AudioPlayerCallback = {
      onStart: () => {
        if (!this.guard.isActive(seq)) {
          return
        }
        // 多段场景只在第一段起播时上报一次 onStart
        if (!this.startNotified) {
          this.startNotified = true
          this.speaking = true
          const cb = this.currentCallback
          if (cb !== null) {
            cb.onStart()
          }
        }
      },
      onComplete: () => {
        if (!this.guard.isActive(seq)) {
          return
        }
        this.chunkIndex++
        if (this.chunkIndex < this.pendingChunks.length) {
          const apiKey = this.resolveApiKey()
          if (apiKey === '') {
            this.finishWithError(seq, 'DeepSeek TTS 缺少 API Key，请先在服务商中配置 DeepSeek')
            return
          }
          this.fetchChunkAndPlay(apiKey, seq)
        } else {
          this.finishWithComplete(seq)
        }
      },
      onError: (error: string) => {
        if (!this.guard.isActive(seq)) {
          return
        }
        this.finishWithError(seq, error)
      }
    }
    try {
      this.audioPlayer.playFromBuffer(audioBuffer, audioCallback, DEEPSEEK_TTS_CONFIG.audioFormat)
    } catch (syncErr) {
      this.finishWithError(seq, `音频播放器启动失败: ${JSON.stringify(syncErr)}`)
    }
  }

  private finishWithComplete(seq: number): void {
    if (!this.guard.isActive(seq)) {
      return
    }
    this.guard.invalidate()
    this.speaking = false
    this.pendingChunks = []
    const cb = this.currentCallback
    this.currentCallback = null
    if (cb !== null) {
      cb.onComplete()
    }
  }

  private finishWithError(seq: number, message: string): void {
    if (!this.guard.isActive(seq)) {
      return
    }
    console.error('DeepSeekTtsEngine', message)
    this.guard.invalidate()
    if (this.httpRequest !== null) {
      try {
        this.httpRequest.destroy()
      } catch (_err) {
        // ignore
      }
      this.httpRequest = null
    }
    this.speaking = false
    this.pendingChunks = []
    const cb = this.currentCallback
    this.currentCallback = null
    if (cb !== null) {
      cb.onError(message)
    }
  }

  stop(): void {
    this.guard.invalidate()
    if (this.httpRequest !== null) {
      try {
        this.httpRequest.destroy()
      } catch (_err) {
        // ignore
      }
      this.httpRequest = null
    }
    this.audioPlayer.stop()
    this.speaking = false
    this.currentCallback = null
    this.pendingChunks = []
    this.chunkIndex = 0
  }

  isSpeaking(): boolean {
    return this.speaking
  }

  destroy(): void {
    this.stop()
    this.audioPlayer.destroy()
    this.inited = false
  }

  // 解析 API key: 使用用户配置的 deepseek provider, 未配置返回空串 (speak 报错)
  private resolveApiKey(): string {
    return findProviderApiKey(getAppSettingsState().providers, DEEPSEEK_TTS_PROVIDER_ID)
  }

  // 解析当前应使用的音色: 优先读取用户在设置中保存的音色, 未配置则回退到默认配置
  private resolveVoice(): string {
    try {
      const map = getAppSettingsState().ttsVoiceByEngine
      const saved = map[DEEPSEEK_ENGINE_ID]
      if (saved !== undefined && saved !== '') {
        return saved
      }
    } catch (_e) {
      // ignore, fall back to default
    }
    return DEEPSEEK_TTS_CONFIG.voice
  }

  // 非 200 响应映射为可读中文错误
  private describeHttpError(code: number, detail: string): string {
    const suffix = detail !== '' ? `, 响应: ${detail}` : ''
    if (code === 400) {
      return `DeepSeek TTS 返回 400：文本为空或未通过内容审核${suffix}`
    }
    if (code === 429) {
      return `DeepSeek TTS 并发请求超过上限，请稍后重试${suffix}`
    }
    if (code === 503) {
      return `DeepSeek TTS 服务繁忙，请稍后重试${suffix}`
    }
    if (code === 504) {
      return `DeepSeek TTS 合成超时${suffix}`
    }
    return `DeepSeek TTS API 返回状态码: ${code}${suffix}`
  }

  // 非 200 响应体解码 (期望 JSON 错误信息)
  private decodeErrorBody(result: string | Object | ArrayBuffer): string {
    if (result instanceof ArrayBuffer) {
      try {
        const decoder = util.TextDecoder.create('utf-8')
        return decoder.decodeToString(new Uint8Array(result), { stream: false })
      } catch (_err) {
        return ''
      }
    }
    if (typeof result === 'string') {
      return result
    }
    return ''
  }
}

// 请求体类型 (/v1/tools/tts)
interface DeepSeekTtsRequestBody {
  text: string
  voice_id: string
  format: string
  filter_markdown: boolean
}
