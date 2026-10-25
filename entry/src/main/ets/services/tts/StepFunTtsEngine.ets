import { http } from '@kit.NetworkKit'
import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { ITtsEngine, TTSCallback } from './ITtsEngine'
import { AudioPlayerHelper, AudioPlayerCallback } from './AudioPlayerHelper'
import {
  STEPFUN_TTS_CONFIG,
  STEPFUN_TTS_PROVIDER_ID,
  STEPFUN_MAX_INPUT_CHARS
} from '../../config/TtsConfig'
import { getAppSettingsState } from '../../state/AppSettingsState'
import { splitTextForStepFun } from '../../utils/StepFunTtsTextUtils'

const STEPFUN_ENGINE_ID: string = 'stepfun'

// StepFun 语音合成引擎 (HTTP 非流式 /v1/audio/speech, 缓冲整播)
// 与 MiniMaxTtsEngine 的差异:
//   1. 响应是原始二进制音频 (默认 stream_format=audio), 无 SSE 行解析
//   2. input 上限 1000 字符, 超长文本按句切分后逐段"合成→播放"串联
//   3. 无内置 fallback key, 必须在服务商中配置 StepFun 的 API Key
export class StepFunTtsEngine implements ITtsEngine {
  private baseUrl: string = STEPFUN_TTS_CONFIG.apiUrl
  private speaking: boolean = false
  private currentCallback: TTSCallback | null = null
  private audioPlayer: AudioPlayerHelper = new AudioPlayerHelper()
  private inited: boolean = false
  private httpRequest: http.HttpRequest | null = null
  // 超长文本切段队列: 每段"合成→播放"完成后取下一段, 全部完成才回 onComplete
  private pendingChunks: string[] = []
  private chunkIndex: number = 0
  private startNotified: boolean = false
  // 本轮 speak 会话的语速（跨切段续播保持一致）
  private currentSpeed: number | undefined = undefined
  // 本轮 speak 会话是否已关闭 (完成/出错/主动 stop), 用于丢弃迟到的网络回调
  private sessionClosed: boolean = false

  async init(context: common.Context): Promise<void> {
    this.audioPlayer.init(context)
    this.inited = true
  }

  async speak(text: string, callback: TTSCallback, speed?: number): Promise<void> {
    if (!this.inited) {
      callback.onError('StepFun 朗读引擎未初始化')
      return
    }

    const apiKey = this.resolveApiKey()
    if (apiKey === '') {
      callback.onError('StepFun TTS 缺少 API Key，请先在服务商中配置 StepFun')
      return
    }

    if (this.speaking) {
      this.stop()
    }

    this.currentCallback = callback
    this.startNotified = false
    this.sessionClosed = false
    this.currentSpeed = speed
    this.pendingChunks = splitTextForStepFun(text, STEPFUN_MAX_INPUT_CHARS)
    this.chunkIndex = 0

    if (this.pendingChunks.length === 0) {
      // TTSService 已拦截空文本, 此处防御
      this.sessionClosed = true
      callback.onError('没有可朗读的内容')
      return
    }

    this.fetchChunkAndPlay(apiKey)
  }

  // 合成 pendingChunks[chunkIndex] 并播放; 播放完成由 playChunk 的回调驱动下一段
  private fetchChunkAndPlay(apiKey: string): void {
    const chunk = this.pendingChunks[this.chunkIndex]
    const requestBody = JSON.stringify({
      model: STEPFUN_TTS_CONFIG.model,
      input: chunk,
      voice: this.resolveVoice(),
      response_format: STEPFUN_TTS_CONFIG.audioFormat,
      sample_rate: STEPFUN_TTS_CONFIG.sampleRate,
      // 语速范围 [0.5, 2]；未传时用 TtsConfig 默认 1.0
      speed: this.currentSpeed !== undefined && this.currentSpeed >= 0.5 && this.currentSpeed <= 2
        ? this.currentSpeed : STEPFUN_TTS_CONFIG.speed,
      volume: STEPFUN_TTS_CONFIG.volume,
      text_normalization: STEPFUN_TTS_CONFIG.textNormalization
    } as StepFunTtsRequestBody)

    const httpReq = http.createHttp()
    this.httpRequest = httpReq

    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      },
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      extraData: requestBody
    }

    httpReq.request(this.baseUrl, options).then((resp: http.HttpResponse) => {
      if (this.httpRequest === httpReq) {
        this.httpRequest = null
      }
      if (this.sessionClosed) {
        // 主动 stop 后到达的响应, 直接丢弃
        return
      }
      if (resp.responseCode !== 200) {
        const detail = this.decodeErrorBody(resp.result)
        this.finishWithError(`StepFun TTS API 返回状态码: ${resp.responseCode}${detail !== '' ? `, 响应: ${detail}` : ''}`)
        return
      }
      const audioBuffer = resp.result as ArrayBuffer
      if (audioBuffer.byteLength === 0) {
        this.finishWithError('StepFun TTS 返回空音频数据')
        return
      }
      this.playChunk(audioBuffer)
    }).catch((error: Error) => {
      if (this.httpRequest === httpReq) {
        this.httpRequest = null
      }
      // 主动 stop 触发的请求失败不报错
      if (this.sessionClosed) {
        return
      }
      this.finishWithError(`StepFun 朗读失败: ${error.message}`)
    })
  }

  private playChunk(audioBuffer: ArrayBuffer): void {
    const audioCallback: AudioPlayerCallback = {
      onStart: () => {
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
        this.chunkIndex++
        if (this.chunkIndex < this.pendingChunks.length) {
          const apiKey = this.resolveApiKey()
          if (apiKey === '') {
            this.finishWithError('StepFun TTS 缺少 API Key，请先在服务商中配置 StepFun')
            return
          }
          this.fetchChunkAndPlay(apiKey)
        } else {
          this.finishWithComplete()
        }
      },
      onError: (error: string) => {
        this.finishWithError(error)
      }
    }
    try {
      this.audioPlayer.playFromBuffer(audioBuffer, audioCallback, STEPFUN_TTS_CONFIG.audioFormat)
    } catch (syncErr) {
      this.finishWithError(`音频播放器启动失败: ${JSON.stringify(syncErr)}`)
    }
  }

  private finishWithComplete(): void {
    this.sessionClosed = true
    this.speaking = false
    this.pendingChunks = []
    const cb = this.currentCallback
    this.currentCallback = null
    if (cb !== null) {
      cb.onComplete()
    }
  }

  private finishWithError(message: string): void {
    if (this.sessionClosed) {
      return
    }
    console.error('StepFunTtsEngine', message)
    this.sessionClosed = true
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
    this.sessionClosed = true
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

  // 解析 API key: 使用用户配置的 stepfun provider, 未配置返回空串 (speak 报错)
  private resolveApiKey(): string {
    const matched = getAppSettingsState().providers.find(
      (p) => p.id === STEPFUN_TTS_PROVIDER_ID && p.apiKey !== ''
    )
    return matched === undefined ? '' : matched.apiKey
  }

  // 解析当前应使用的音色: 优先读取用户在设置中保存的音色, 未配置则回退到默认配置
  private resolveVoice(): string {
    try {
      const map = getAppSettingsState().ttsVoiceByEngine
      const saved = map[STEPFUN_ENGINE_ID]
      if (saved !== undefined && saved !== '') {
        return saved
      }
    } catch (_e) {
      // ignore, fall back to default
    }
    return STEPFUN_TTS_CONFIG.voice
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

// 请求体类型 (/v1/audio/speech)
interface StepFunTtsRequestBody {
  model: string
  input: string
  voice: string
  response_format: string
  sample_rate: number
  speed: number
  volume: number
  text_normalization: string
}
