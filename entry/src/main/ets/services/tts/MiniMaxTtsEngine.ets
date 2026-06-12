import { http } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { ITtsEngine, TTSCallback } from './ITtsEngine'
import { AudioPlayerHelper, AudioPlayerCallback } from './AudioPlayerHelper'
import { MINIMAX_TTS_CONFIG, MIMO_TTS_PROVIDER_ID } from '../../config/TtsConfig'
import { getAppSettingsState } from '../../state/AppSettingsState'

const MINIMAX_ENGINE_ID: string = 'minimax'

// MiniMax 同步/流式语音合成引擎（T2A v2 接口）
// 与 MiMoTtsEngine 的差异：
//   1. 鉴权用 Authorization: Bearer <token>
//   2. 请求体是扁平 { model, text, voice_setting, audio_setting }
//   3. 音频是 hex 编码（不是 base64）
//   4. 结束条件是 data.status === 2（不是 SSE 流自然结束）
export class MiniMaxTtsEngine implements ITtsEngine {
  // 项目内置 fallback key, 仅供开发测试; 生产环境应通过 minimax provider 配置用户 key
  private static readonly FALLBACK_API_KEY: string =
    'sk-cwidkyxovc7trbn06hbp4y4uvvtembyouazogcrdixm15xke'
  private baseUrl: string = MINIMAX_TTS_CONFIG.apiUrl
  private speaking: boolean = false
  private currentCallback: TTSCallback | null = null
  private audioPlayer: AudioPlayerHelper = new AudioPlayerHelper()
  private inited: boolean = false
  private httpRequest: http.HttpRequest | null = null
  // 跨 chunk 的不完整行缓冲
  private streamBuffer: string = ''

  async init(context: common.Context): Promise<void> {
    this.audioPlayer.init(context)
    this.inited = true
  }

  async speak(text: string, callback: TTSCallback): Promise<void> {

    if (!this.inited) {
      callback.onError('MiniMax 朗读引擎未初始化')
      return
    }

    const apiKey = this.resolveApiKey()
    if (apiKey === '') {
      callback.onError('MiniMax TTS 缺少 API Key，请先在服务商中配置 MiniMax')
      return
    }

    if (this.speaking) {
      this.stop()
    }

    this.currentCallback = callback
    this.streamBuffer = ''

    try {
      const requestBody = JSON.stringify({
        model: MINIMAX_TTS_CONFIG.model,
        text: text,
        stream: true,
        stream_options: {
          // 默认 false 时, status: 2 的最后一个 chunk 包含完整累积音频, 拼接会导致播放两遍
          exclude_aggregated_audio: true
        },
        voice_setting: {
          voice_id: this.resolveVoice(),
          speed: MINIMAX_TTS_CONFIG.speed,
          vol: 1.0,
          pitch: MINIMAX_TTS_CONFIG.pitch
        },
        audio_setting: {
          sample_rate: MINIMAX_TTS_CONFIG.sampleRate,
          bitrate: MINIMAX_TTS_CONFIG.bitrate,
          format: MINIMAX_TTS_CONFIG.audioFormat,
          channel: 1
        }
      } as TtsRequestBody)

      const httpReq = http.createHttp()
      this.httpRequest = httpReq

      const audioChunks: Uint8Array[] = []
      let totalLength: number = 0
      let streamError: string = ''
      let streamFinished: boolean = false
      let lastChunk: ArrayBuffer | null = null
      let chunkCount: number = 0
      let parsedLineCount: number = 0

      httpReq.on('dataReceive', (data: ArrayBuffer) => {
        chunkCount++
        lastChunk = data
        try {
          const chunkText = this.arrayBufferToString(data)
          this.streamBuffer += chunkText

          let linesParsed = 0
          while (true) {
            const newlineIdx = this.streamBuffer.indexOf('\n')
            if (newlineIdx < 0) {
              break
            }
            const line = this.streamBuffer.substring(0, newlineIdx).trim()
            this.streamBuffer = this.streamBuffer.substring(newlineIdx + 1)
            linesParsed++

            if (line === '') {
              continue
            }
            // 兼容 SSE data: 前缀（流式 content-type 可能是 text/event-stream）
            const jsonStr: string = line.startsWith('data: ') ? line.substring(6) : line
            if (jsonStr === '' || jsonStr === '[DONE]') {
              continue
            }

            try {
              const json: ESObject = JSON.parse(jsonStr)
              if (parsedLineCount === 0) {
                console.info('MiniMaxTtsEngine', `SSE line #1 FULL: ${line}`)
              }
              const dataObj: ESObject = json['data'] as ESObject
              if (dataObj === undefined || dataObj === null) {
                continue
              }
              const status: number = dataObj['status'] as number
              if (status === 2) {
                // 末尾 chunk 只用作结束信号, 音频已在前面 status=1 的 chunk 里完整累积
                // (即使请求里加了 exclude_aggregated_audio, 防御性再确认一次)
                streamFinished = true
                continue
              }
              const audioHex: string = dataObj['audio'] as string
              if (audioHex !== undefined && audioHex !== '') {
                const audioBytes = this.hexToBytes(audioHex)
                if (audioBytes.byteLength > 0) {
                  audioChunks.push(audioBytes)
                  totalLength += audioBytes.byteLength
                  if (parsedLineCount === 0) {
                    console.info('MiniMaxTtsEngine', `首个音频 chunk, hex len: ${audioHex.length}, bytes: ${audioBytes.byteLength}`)
                  }
                }
              }
            } catch (_parseErr) {
              // 跳过无法解析的行
            }
          }
          if (linesParsed > 0) {
            parsedLineCount += linesParsed
            console.info('MiniMaxTtsEngine', `#${chunkCount} 解析 ${linesParsed} 行, 总计 ${parsedLineCount} 行, 累积音频: ${totalLength} bytes, finished: ${streamFinished}`)
          }
        } catch (err) {
          console.error('MiniMaxTtsEngine', `dataReceive #${chunkCount} error: ${JSON.stringify(err)}`)
        }
      })

      httpReq.on('dataEnd', () => {
        console.info('MiniMaxTtsEngine', `dataEnd, chunks: ${chunkCount}, parsed lines: ${parsedLineCount}, audio bytes: ${totalLength}, finished: ${streamFinished}`)
        // 处理缓冲区中剩余的不完整行
        const remaining = this.streamBuffer.trim()
        this.streamBuffer = ''
        if (remaining !== '') {
          const jsonStr: string = remaining.startsWith('data: ') ? remaining.substring(6) : remaining
          try {
            const json: ESObject = JSON.parse(jsonStr)
            const dataObj: ESObject = json['data'] as ESObject
            if (dataObj !== undefined && dataObj !== null) {
              const status: number = dataObj['status'] as number
              if (status === 2) {
                streamFinished = true
              } else {
                const audioHex: string = dataObj['audio'] as string
                if (audioHex !== undefined && audioHex !== '') {
                  const audioBytes = this.hexToBytes(audioHex)
                  if (audioBytes.byteLength > 0) {
                    audioChunks.push(audioBytes)
                    totalLength += audioBytes.byteLength
                  }
                }
              }
            }
          } catch (_parseErr) {
            // skip
          }
        }

        if (streamError !== '') {
          return
        }

        if (!streamFinished) {
          streamError = 'MiniMax TTS 流式响应未收到结束帧 (status: 2)'
          console.error('MiniMaxTtsEngine', streamError)
          this.httpRequest = null
          const cb = this.currentCallback
          this.currentCallback = null
          this.speaking = false
          if (cb !== null) {
            cb.onError(streamError)
          }
          return
        }

        this.playAudioChunks(audioChunks, totalLength)
      })

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`
        },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        extraData: requestBody
      }

      httpReq.requestInStream(this.baseUrl, options).then((code: number) => {
        if (code !== 200) {
          let errorDetail = ''
          if (lastChunk !== null) {
            try {
              const decoder = util.TextDecoder.create('utf-8')
              errorDetail = decoder.decodeToString(new Uint8Array(lastChunk), { stream: false })
            } catch (_decodeErr) {
              // ignore
            }
          }
          streamError = `MiniMax TTS API 返回状态码: ${code}${errorDetail !== '' ? `, 响应: ${errorDetail}` : ''}`
          console.error('MiniMaxTtsEngine', streamError)
          this.httpRequest = null
          const cb = this.currentCallback
          this.currentCallback = null
          this.speaking = false
          if (cb !== null) {
            cb.onError(streamError)
          }
        }
      }).catch((error: Error) => {
        // 如果是主动 stop 触发的 destroy，不报错
        if (this.httpRequest === null) {
          return
        }
        streamError = `MiniMax 流式请求失败: ${error.message}`
        console.error('MiniMaxTtsEngine', streamError)
        this.httpRequest = null
        const cb = this.currentCallback
        this.currentCallback = null
        this.speaking = false
        if (cb !== null) {
          cb.onError(streamError)
        }
      })
    } catch (error) {
      const err = error as BusinessError
      console.error('MiniMaxTtsEngine', `speak failed: ${err.code}, ${err.message}`)
      this.speaking = false
      this.httpRequest = null
      const cb = this.currentCallback
      this.currentCallback = null
      if (cb !== null) {
        cb.onError(`MiniMax 朗读失败: ${err.message}`)
      }
    }
  }

  stop(): void {
    if (this.httpRequest !== null) {
      try {
        this.httpRequest.off('dataReceive')
        this.httpRequest.off('dataEnd')
        this.httpRequest.destroy()
      } catch (_err) {
        // ignore
      }
      this.httpRequest = null
    }
    this.audioPlayer.stop()
    this.speaking = false
    this.currentCallback = null
    this.streamBuffer = ''
  }

  isSpeaking(): boolean {
    return this.speaking
  }

  destroy(): void {
    this.stop()
    this.audioPlayer.destroy()
    this.inited = false
  }

  // 合并音频分片并通过 AVPlayer 播放
  private playAudioChunks(chunks: Uint8Array[], totalLength: number): void {

    if (totalLength === 0) {
      console.error('MiniMaxTtsEngine', '空音频数据')
      this.httpRequest = null
      this.speaking = false
      const cb = this.currentCallback
      this.currentCallback = null
      if (cb !== null) {
        cb.onError('MiniMax TTS 返回空音频数据')
      }
      return
    }

    const audioData = new Uint8Array(totalLength)
    let offset: number = 0
    for (let i = 0; i < chunks.length; i++) {
      audioData.set(chunks[i], offset)
      offset += chunks[i].byteLength
    }

    this.httpRequest = null

    const audioCallback: AudioPlayerCallback = {
      onStart: () => {
        console.info('MiniMaxTtsEngine', 'AudioPlayer onStart 回调')
        this.speaking = true
        if (this.currentCallback !== null) {
          this.currentCallback.onStart()
        }
      },
      onComplete: () => {
        console.info('MiniMaxTtsEngine', 'AudioPlayer onComplete 回调')
        this.speaking = false
        const cb = this.currentCallback
        this.currentCallback = null
        if (cb !== null) {
          cb.onComplete()
        }
      },
      onError: (error: string) => {
        console.error('MiniMaxTtsEngine', `AudioPlayer onError 回调: ${error}`)
        this.speaking = false
        const cb = this.currentCallback
        this.currentCallback = null
        if (cb !== null) {
          cb.onError(error)
        }
      }
    }

    const audioBuffer: ArrayBuffer = audioData.buffer.slice(0) as ArrayBuffer
    try {
      this.audioPlayer.playFromBuffer(audioBuffer, audioCallback)
    } catch (syncErr) {
      console.error('MiniMaxTtsEngine', `playFromBuffer 同步异常: ${JSON.stringify(syncErr)}`)
    }
  }

  // ArrayBuffer → UTF-8 字符串
  private arrayBufferToString(buffer: ArrayBuffer): string {
    const textDecoder = util.TextDecoder.create('utf-8')
    const uint8Array = new Uint8Array(buffer)
    return textDecoder.decodeToString(uint8Array, { stream: false })
  }

  // 解析 API key: 优先用用户配置的 minimax provider, 回退到项目内置 key
  // 每次 speak() 重新解析, 避免用户中途改 key 后用了陈旧值
  private resolveApiKey(): string {
    const matched = getAppSettingsState().providers.find(
      (p) => p.id === MIMO_TTS_PROVIDER_ID && p.apiKey !== ''
    )
    if (matched !== undefined) {
      return matched.apiKey
    }
    return MiniMaxTtsEngine.FALLBACK_API_KEY
  }

  // 解析当前应使用的音色: 优先读取用户在设置中保存的音色, 未配置则回退到默认配置
  private resolveVoice(): string {
    try {
      const map = getAppSettingsState().ttsVoiceByEngine
      const saved = map[MINIMAX_ENGINE_ID]
      if (saved !== undefined && saved !== '') {
        return saved
      }
    } catch (_e) {
      // ignore, fall back to default
    }
    return MINIMAX_TTS_CONFIG.voice
  }

  // Hex 字符串 → Uint8Array
  // 输入允许包含空白字符；长度不是 2 的倍数或非 hex 字符返回空数组
  private hexToBytes(hex: string): Uint8Array {
    const cleanHex = hex.replace(/\s/g, '')
    if (cleanHex.length === 0 || cleanHex.length % 2 !== 0) {
      return new Uint8Array(0)
    }
    const len = cleanHex.length / 2
    const bytes = new Uint8Array(len)
    for (let i = 0; i < len; i++) {
      const byte = parseInt(cleanHex.substring(i * 2, i * 2 + 2), 16)
      bytes[i] = isNaN(byte) ? 0 : byte
    }
    return bytes
  }
}

// 请求体类型
interface TtsRequestBody {
  model: string
  text: string
  stream: boolean
  stream_options: StreamOptions
  voice_setting: VoiceSetting
  audio_setting: AudioSetting
}

interface StreamOptions {
  exclude_aggregated_audio: boolean
}

interface VoiceSetting {
  voice_id: string
  speed: number
  vol: number
  pitch: number
}

interface AudioSetting {
  sample_rate: number
  bitrate: number
  format: string
  channel: number
}
