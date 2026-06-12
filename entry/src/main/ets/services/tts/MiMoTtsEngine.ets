import { http } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { util } from '@kit.ArkTS'
import { ITtsEngine, TTSCallback } from './ITtsEngine'
import { AudioPlayerHelper, AudioPlayerCallback } from './AudioPlayerHelper'
import { MIMO_TTS_CONFIG } from '../../config/TtsConfig'
import { getAppSettingsState } from '../../state/AppSettingsState'

const MIMO_ENGINE_ID: string = 'mimo'

export class MiMoTtsEngine implements ITtsEngine {
  private apiKey: string = 'sk-cwidkyxovc7trbn06hbp4y4uvvtembyouazogcrdixm15xke'
  private baseUrl: string = MIMO_TTS_CONFIG.apiUrl
  private speaking: boolean = false
  private currentCallback: TTSCallback | null = null
  private audioPlayer: AudioPlayerHelper = new AudioPlayerHelper()
  private inited: boolean = false
  private httpRequest: http.HttpRequest | null = null
  // SSE 文本缓冲区，处理跨 chunk 的不完整行
  private sseBuffer: string = ''

  async init(context: common.Context): Promise<void> {
    this.audioPlayer.init(context)
    this.inited = true
  }

  async speak(text: string, callback: TTSCallback): Promise<void> {

    if (!this.inited) {
      callback.onError('MiMo 朗读引擎未初始化')
      return
    }

    if (this.apiKey === '') {
      callback.onError('MiMo TTS 缺少 API Key，请先在设置中配置 MiniMax 服务商')
      return
    }

    // 如果正在播放，先停止
    if (this.speaking) {
      this.stop()
    }

    this.currentCallback = callback
    this.sseBuffer = ''

    try {
      const requestBody = JSON.stringify({
        model: MIMO_TTS_CONFIG.model,
        messages: [
          {
            role: 'user',
            content: '请用自然清晰的语速朗读以下文本。'
          },
          {
            role: 'assistant',
            content: text
          }
        ],
        audio: {
          format: MIMO_TTS_CONFIG.audioFormat,
          voice: this.resolveVoice()
        },
        stream: true
      } as TtsRequestBody)

      const httpReq = http.createHttp()
      this.httpRequest = httpReq

      const audioChunks: Uint8Array[] = []
      let totalLength: number = 0
      let streamCompleted: boolean = false
      let streamError: string = ''
      let lastChunk: ArrayBuffer | null = null
      let chunkCount: number = 0
      let sseDataLineCount: number = 0

      // 接收流式数据
      httpReq.on('dataReceive', (data: ArrayBuffer) => {
        chunkCount++
        lastChunk = data
        try {
          const chunkText = this.arrayBufferToString(data)
          this.sseBuffer += chunkText

          let linesParsed = 0
          // 按行解析 SSE
          while (true) {
            const newlineIdx = this.sseBuffer.indexOf('\n')
            if (newlineIdx < 0) {
              break
            }
            const line = this.sseBuffer.substring(0, newlineIdx).trim()
            this.sseBuffer = this.sseBuffer.substring(newlineIdx + 1)
            linesParsed++

            if (line === '' || line === 'data: [DONE]') {
              continue
            }
            if (!line.startsWith('data: ')) {
              continue
            }

            const jsonStr = line.substring(6)
            if (jsonStr === '[DONE]') {
              continue
            }

            try {
              const json: ESObject = JSON.parse(jsonStr)
              if (sseDataLineCount === 0) {
                // 打印第一条完整 SSE 数据（不截断），看完整 JSON 结构
                console.info('MiMoTtsEngine', `SSE line #1 FULL: ${line}`)
              }
              const choices: ESObject[] = json['choices'] as ESObject[]
              if (choices !== undefined && choices !== null && choices.length > 0) {
                const delta: ESObject = choices[0]['delta'] as ESObject
                if (delta !== undefined && delta !== null) {
                  const audio: ESObject = delta['audio'] as ESObject
                  if (audio !== undefined && audio !== null) {
                    const dataStr: string = audio['data'] as string
                    if (dataStr !== undefined && dataStr !== '') {
                      const audioBytes = this.decodeBase64(dataStr)
                      audioChunks.push(audioBytes)
                      totalLength += audioBytes.byteLength
                      if (sseDataLineCount === 0) {
                        console.info('MiMoTtsEngine', `首个音频 chunk, base64 len: ${dataStr.length}, bytes: ${audioBytes.byteLength}`)
                      }
                      sseDataLineCount++
                    }
                  }
                }
              }
            } catch (_parseErr) {
              // 跳过无法解析的行
            }
          }
          if (linesParsed > 0) {
            console.info('MiMoTtsEngine', `#${chunkCount} 解析 ${linesParsed} 行, 累积音频: ${sseDataLineCount} chunk`)
          }
        } catch (err) {
          console.error('MiMoTtsEngine', `dataReceive #${chunkCount} error: ${JSON.stringify(err)}`)
        }
      })

      // 流结束
      httpReq.on('dataEnd', () => {
        streamCompleted = true
        console.info('MiMoTtsEngine', `dataEnd, chunks: ${chunkCount}, sse lines: ${sseDataLineCount}, audio bytes: ${totalLength}`)
        // 处理缓冲区中剩余的不完整行
        const remaining = this.sseBuffer.trim()
        if (remaining !== '' && remaining !== 'data: [DONE]' && remaining.startsWith('data: ')) {
          const jsonStr = remaining.substring(6)
          try {
            const json: ESObject = JSON.parse(jsonStr)
            const choices: ESObject[] = json['choices'] as ESObject[]
            if (choices !== undefined && choices !== null && choices.length > 0) {
              const delta: ESObject = choices[0]['delta'] as ESObject
              if (delta !== undefined && delta !== null) {
                const audio: ESObject = delta['audio'] as ESObject
                if (audio !== undefined && audio !== null) {
                  const dataStr: string = audio['data'] as string
                  if (dataStr !== undefined && dataStr !== '') {
                    const pcmBytes = this.decodeBase64(dataStr)
                    audioChunks.push(pcmBytes)
                    totalLength += pcmBytes.byteLength
                  }
                }
              }
            }
          } catch (_parseErr) {
            // skip
          }
        }
        this.sseBuffer = ''

        if (!streamCompleted || streamError !== '') {
          return
        }

        // 合并所有音频数据并播放
        this.playAudioChunks(audioChunks, totalLength)
      })

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'api-key': this.apiKey
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
          streamError = `MiMo TTS API 返回状态码: ${code}${errorDetail !== '' ? `, 响应: ${errorDetail}` : ''}`
          console.error('MiMoTtsEngine', streamError)
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
        streamError = `MiMo 流式请求失败: ${error.message}`
        console.error('MiMoTtsEngine', streamError)
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
      console.error('MiMoTtsEngine', `speak failed: ${err.code}, ${err.message}`)
      this.speaking = false
      this.httpRequest = null
      const cb = this.currentCallback
      this.currentCallback = null
      if (cb !== null) {
        cb.onError(`MiMo 朗读失败: ${err.message}`)
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
    this.sseBuffer = ''
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
      console.error('MiMoTtsEngine', '空音频数据')
      this.httpRequest = null
      this.speaking = false
      const cb = this.currentCallback
      this.currentCallback = null
      if (cb !== null) {
        cb.onError('MiMo TTS 返回空音频数据')
      }
      return
    }

    // 拼接所有音频分片
    const audioData = new Uint8Array(totalLength)
    let offset: number = 0
    for (let i = 0; i < chunks.length; i++) {
      audioData.set(chunks[i], offset)
      offset += chunks[i].byteLength
    }

    this.httpRequest = null

    const audioCallback: AudioPlayerCallback = {
      onStart: () => {
        console.info('MiMoTtsEngine', 'AudioPlayer onStart 回调')
        this.speaking = true
        if (this.currentCallback !== null) {
          this.currentCallback.onStart()
        }
      },
      onComplete: () => {
        console.info('MiMoTtsEngine', 'AudioPlayer onComplete 回调')
        this.speaking = false
        const cb = this.currentCallback
        this.currentCallback = null
        if (cb !== null) {
          cb.onComplete()
        }
      },
      onError: (error: string) => {
        console.error('MiMoTtsEngine', `AudioPlayer onError 回调: ${error}`)
        this.speaking = false
        const cb = this.currentCallback
        this.currentCallback = null
        if (cb !== null) {
          cb.onError(error)
        }
      }
    }

    // MP3 格式直接播放
    const audioBuffer: ArrayBuffer = audioData.buffer.slice(0) as ArrayBuffer
    try {
      this.audioPlayer.playFromBuffer(audioBuffer, audioCallback)
    } catch (syncErr) {
      console.error('MiMoTtsEngine', `playFromBuffer 同步异常: ${JSON.stringify(syncErr)}`)
    }
  }

  // ArrayBuffer → UTF-8 字符串
  private arrayBufferToString(buffer: ArrayBuffer): string {
    const textDecoder = util.TextDecoder.create('utf-8')
    const uint8Array = new Uint8Array(buffer)
    return textDecoder.decodeToString(uint8Array, { stream: false })
  }

  // Base64 → Uint8Array
  private decodeBase64(base64Str: string): Uint8Array {
    const base64 = new util.Base64Helper()
    return base64.decodeSync(base64Str)
  }

  // 解析当前应使用的音色: 优先读取用户在设置中保存的音色, 未配置则回退到默认配置
  private resolveVoice(): string {
    try {
      const map = getAppSettingsState().ttsVoiceByEngine
      const saved = map[MIMO_ENGINE_ID]
      if (saved !== undefined && saved !== '') {
        return saved
      }
    } catch (_e) {
      // ignore, fall back to default
    }
    return MIMO_TTS_CONFIG.voice
  }
}

// 请求体类型
interface TtsRequestBody {
  model: string
  messages: TtsMessage[]
  audio: TtsAudioConfig
  stream: boolean
}

interface TtsMessage {
  role: string
  content: string
}

interface TtsAudioConfig {
  format: string
  voice: string
}
