import { speechRecognizer } from '@kit.CoreSpeechKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { abilityAccessCtrl, PermissionRequestResult, common } from '@kit.AbilityKit'

export interface SpeechRecognitionCallback {
  onStart: () => void
  onResult: (text: string, isFinal: boolean) => void
  onComplete: (finalText: string) => void
  onCancel: () => void
  onError: (code: number, message: string) => void
}

const TAG = 'SpeechRecognitionService'

export class SpeechRecognitionService {
  private engine: speechRecognizer.SpeechRecognitionEngine | null = null
  private currentCallback: SpeechRecognitionCallback | null = null
  private currentSessionId: string = ''
  private isListening: boolean = false
  private isInitialized: boolean = false
  private finalText: string = ''

  async init(): Promise<void> {
    if (this.isInitialized) {
      return
    }

    const initParams: speechRecognizer.CreateEngineParams = {
      language: 'zh-CN',
      online: 1,
      extraParams: {
        "locate": "CN",
        "recognizerMode": "short"
      }
    }

    try {
      this.engine = await speechRecognizer.createEngine(initParams)
      this.isInitialized = true
      console.info(TAG, 'Engine created successfully')
    } catch (err) {
      const e = err as BusinessError
      console.error(TAG, `createEngine failed: ${e.code} ${e.message}`)
      throw new Error(`语音识别引擎初始化失败: ${e.message}`)
    }
  }

  async checkPermission(context: common.Context): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager()
    const tokenId = context.applicationInfo.accessTokenId
    const result = await atManager.checkAccessToken(tokenId, 'ohos.permission.MICROPHONE')
    if (result === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      return true
    }
    return new Promise<boolean>((resolve) => {
      atManager.requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE'])
        .then((res: PermissionRequestResult) => {
          resolve(res.authResults[0] === 0)
        })
        .catch(() => resolve(false))
    })
  }

  startListening(callback: SpeechRecognitionCallback): void {
    if (!this.isInitialized || this.engine === null) {
      callback.onError(-1, '语音识别服务未初始化')
      return
    }
    if (this.isListening) {
      this.cancelListening()
    }

    this.currentCallback = callback
    this.currentSessionId = `voice_${Date.now()}`
    this.finalText = ''

    const listener: speechRecognizer.RecognitionListener = {
      onStart: (_sessionId: string, _eventMessage: string) => {
        this.isListening = true
        callback.onStart()
      },
      onResult: (_sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
        const text = result.result ?? ''
        const isFinal = result.isFinal ?? false
        if (isFinal) {
          this.finalText = text
        }
        callback.onResult(text, isFinal)
      },
      onComplete: (_sessionId: string, _eventMessage: string) => {
        this.isListening = false
        const text = this.finalText
        // 始终回调，即使识别结果为空（ChatPage 需要重置 isRecording 状态）
        callback.onComplete(text)
      },
      onError: (_sessionId: string, errorCode: number, errorMessage: string) => {
        this.isListening = false
        callback.onError(errorCode, errorMessage)
      },
      onEvent: (_sessionId: string, _eventId: number, _eventMessage: string) => {
        // 事件回调，暂不处理
      }
    }

    this.engine.setListener(listener)

    const params: speechRecognizer.StartParams = {
      sessionId: this.currentSessionId,
      audioInfo: {
        audioType: 'pcm',
        sampleRate: 16000,
        soundChannel: 1,
        sampleBit: 16
      },
      extraParams: {
        "recognitionMode": 0,
        "vadBegin": 1500,
        "vadEnd": 2000,
        "maxAudioDuration": 60000
      }
    }

    this.engine.startListening(params)
  }

  finishListening(): void {
    if (!this.isListening || this.engine === null) {
      return
    }
    this.engine.finish(this.currentSessionId)
  }

  cancelListening(): void {
    if (!this.isListening || this.engine === null) {
      return
    }
    this.engine.cancel(this.currentSessionId)
    this.isListening = false
    if (this.currentCallback) {
      this.currentCallback.onCancel()
      this.currentCallback = null
    }
  }

  shutdown(): void {
    if (this.engine !== null) {
      try {
        this.engine.shutdown()
      } catch (err) {
        console.error(TAG, `shutdown failed: ${err}`)
      }
      this.engine = null
    }
    this.isInitialized = false
    this.isListening = false
  }
}

let instance: SpeechRecognitionService | null = null

export function getSpeechRecognitionService(): SpeechRecognitionService {
  if (instance === null) {
    instance = new SpeechRecognitionService()
  }
  return instance
}
