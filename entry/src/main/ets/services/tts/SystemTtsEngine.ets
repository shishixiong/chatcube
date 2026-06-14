import { textToSpeech } from '@kit.CoreSpeechKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { ITtsEngine, TTSCallback } from './ITtsEngine'


export class SystemTtsEngine implements ITtsEngine {
  private engine: textToSpeech.TextToSpeechEngine | null = null
  private isInitDone: boolean = false
  // 缓存 in-flight init 任务: textToSpeech.createEngine 是 callback 异步 API,
  // 必须用 Promise 包裹才能对外表现为 await 完成后引擎就绪。
  // 并发 init() 复用同一 Promise,避免重复 createEngine。
  private initPromise: Promise<void> | null = null
  private speaking: boolean = false
  private currentCallback: TTSCallback | null = null
  private currentRequestId: string = '';

  async init(context: common.Context): Promise<void> {
    if (this.isInitDone) {
      return
    }
    // 幂等: 已有 in-flight 初始化 → 复用同一 Promise
    if (this.initPromise !== null) {
      return this.initPromise
    }

    this.initPromise = new Promise<void>((resolve: () => void, reject: (err: Error) => void) => {
      try {
        const params: textToSpeech.CreateEngineParams = {
          language: 'zh-CN',  // 设置语言为中文
          person: 0,          // 设置发音人（0为默认发音人）
          online: 1           // 设置为在线模式（1为在线，0为离线）
        }

        textToSpeech.createEngine(params, (err: BusinessError, engine: textToSpeech.TextToSpeechEngine) => {
          if (err) {
            console.error('SystemTtsEngine',
              `createEngine failed: code=${err.code}, message=${err.message}`)
            // 失败时不置 isInitDone, 下次 init() 可重试
            // (callback 内抛错不会冒泡,必须显式 reject)
            reject(new Error(`系统朗读引擎初始化失败: code=${err.code}, message=${err.message}`))
            return
          }
          this.engine = engine
          this.isInitDone = true
          console.info('SystemTtsEngine', 'initialized')
          resolve()
        })
      } catch (error) {
        // createEngine 同步抛异常的兜底（如参数非法、设备能力不支持）
        const err = error as BusinessError
        console.error('SystemTtsEngine',
          `init threw synchronously: code=${err.code}, message=${err.message}`)
        reject(new Error(`系统朗读引擎初始化失败: code=${err.code}, message=${err.message}`))
      }
    })

    try {
      await this.initPromise
    } finally {
      this.initPromise = null
    }
  }

  async speak(text: string, callback: TTSCallback): Promise<void> {
    if (this.speaking) {
      await this.stop();
    }

    if (!this.engine) {
      console.error('TTS engine not initialized');
      if (callback?.onError) {
        callback.onError('TTS引擎未初始化');
      }
      return;
    }

    try {
      this.speaking = true;
      this.currentCallback = callback;
      this.currentRequestId = Date.now().toString(36) + Math.random().toString(36).substring(2);
      console.info('Speaking: %{public}s', text.substring(0, 50));

      const speakListener: textToSpeech.SpeakListener = {
        onStart: (requestId: string) => {
          console.info('TTS onStart: %{public}s', requestId);
          if (this.currentCallback?.onStart) {
            this.currentCallback.onStart();
          }
        },
        onComplete: (requestId: string) => {
          console.info('TTS onComplete: %{public}s', requestId);
          this.speaking = false;
          this.currentRequestId = '';
          if (this.currentCallback?.onComplete) {
            this.currentCallback.onComplete();
          }
        },
        onStop: (requestId: string, response: textToSpeech.StopResponse) => {
          console.info('TTS onStop: %{public}s, response: %{public}d', requestId, response);
          this.speaking = false;
          this.currentRequestId = '';
          if (this.currentCallback?.onComplete) {
            this.currentCallback.onComplete();
          }
        },
        onError: (requestId: string, errorCode: number, errorMessage: string) => {
          console.error('TTS onError: %{public}s, code: %{public}d, msg: %{public}s',
            requestId, errorCode, errorMessage);
          this.speaking = false;
          this.currentRequestId = '';
          if (this.currentCallback?.onError) {
            this.currentCallback.onError(`语音合成错误(${errorCode}): ${errorMessage}`);
          }
        }
      };
      let extraParam: Record<string, Object> = {
        'queueMode': 0,
        'speed': 1,
        'volume': 2,
        'pitch': 1,
        'languageContext': 'zh-CN',
        'audioType': 'pcm',
        'soundChannel': 3,
        'playType':1
      };

      const speakParams: textToSpeech.SpeakParams = {
        requestId: this.currentRequestId,
        extraParams: extraParam
      };

      // 必须在 speak() 之前调用 setListener()，否则 SpeakListener 不会触发
      // 参考 HarmonyOS API 文档："the setListener method must be invoked first"
      this.engine.setListener(speakListener);
      this.engine.speak(text, speakParams);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      console.error('Failed to speak: %{public}d, %{public}s', error.code, error.message);
      this.speaking = false;
      this.currentRequestId= '';
      if (this.currentCallback?.onError) {
        this.currentCallback.onError('语音播放失败');
      }
    }
  }

  stop(): void {
    if (this.speaking && this.engine) {
      try {
        this.engine.stop();
        console.info('TTS stopped');
      } catch (err) {
        const error: BusinessError = err as BusinessError;
        console.error('Failed to stop TTS: %{public}d, %{public}s', error.code, error.message);
      }
    }
    this.speaking = false;
    this.currentRequestId = '';
    this.currentCallback = null
  }

  isSpeaking(): boolean {
    return this.speaking
  }

  destroy(): void {
    if (this.engine !== null) {
      try {
        this.engine.shutdown()
        this.engine = null;
      } catch (error) {
        console.error('SystemTtsEngine', `release failed: ${JSON.stringify(error)}`)
      }
      this.engine = null
    }
    this.isInitDone = false
    this.speaking = false
    this.currentRequestId = '';
  }
}
