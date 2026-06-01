import { http } from '@kit.NetworkKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { ITtsEngine, TTSCallback } from './ITtsEngine'
import { AudioPlayerHelper, AudioPlayerCallback } from './AudioPlayerHelper'
import { MIMO_TTS_CONFIG } from '../../config/TtsConfig'

interface VoiceSetting {
  voice_id: string
  speed: number
  vol: number
}

interface AudioSetting {
  sample_rate: number
  format: string
}

export class MiMoTtsEngine implements ITtsEngine {
  private apiKey: string = ''
  private baseUrl: string = MIMO_TTS_CONFIG.apiUrl
  private speaking: boolean = false
  private currentCallback: TTSCallback | null = null
  private audioPlayer: AudioPlayerHelper = new AudioPlayerHelper()
  private inited: boolean = false

  async init(context: common.Context, apiKey?: string): Promise<void> {
    if (apiKey !== undefined && apiKey !== '') {
      this.apiKey = apiKey
    }
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

    try {
      const requestBody = JSON.stringify({
        model: MIMO_TTS_CONFIG.model,
        text: text,
        stream: false,
        voice_setting: {
          voice_id: MIMO_TTS_CONFIG.voice,
          speed: MIMO_TTS_CONFIG.speed,
          vol: 1.0
        } as VoiceSetting,
        audio_setting: {
          sample_rate: 32000,
          format: 'mp3'
        } as AudioSetting
      })

      const httpRequest = http.createHttp()

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`
        },
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        extraData: requestBody
      }

      const response = await httpRequest.request(this.baseUrl, options)

      httpRequest.destroy()

      const audioBuffer = response.result as ArrayBuffer

      if (audioBuffer === undefined || audioBuffer.byteLength === 0) {
        this.speaking = false
        callback.onError('MiMo TTS 返回空音频数据')
        return
      }

      // 用 AVPlayer 播放音频
      const audioCallback: AudioPlayerCallback = {
        onStart: () => {
          this.speaking = true
          if (this.currentCallback !== null) {
            this.currentCallback.onStart()
          }
        },
        onComplete: () => {
          this.speaking = false
          const cb = this.currentCallback
          this.currentCallback = null
          if (cb !== null) {
            cb.onComplete()
          }
        },
        onError: (error: string) => {
          this.speaking = false
          const cb = this.currentCallback
          this.currentCallback = null
          if (cb !== null) {
            cb.onError(error)
          }
        }
      }

      await this.audioPlayer.playFromBuffer(audioBuffer, audioCallback)
    } catch (error) {
      const err = error as BusinessError
      console.error('MiMoTtsEngine', `speak failed: ${err.code}, ${err.message}`)
      this.speaking = false
      const cb = this.currentCallback
      this.currentCallback = null
      if (cb !== null) {
        cb.onError(`MiMo 朗读失败: ${err.message}`)
      }
    }
  }

  stop(): void {
    this.audioPlayer.stop()
    this.speaking = false
    this.currentCallback = null
  }

  isSpeaking(): boolean {
    return this.speaking
  }

  destroy(): void {
    this.stop()
    this.audioPlayer.destroy()
    this.inited = false
  }
}
