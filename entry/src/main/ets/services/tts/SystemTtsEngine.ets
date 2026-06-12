import { textToSpeech } from '@kit.CoreSpeechKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { ITtsEngine, TTSCallback } from './ITtsEngine'


export class SystemTtsEngine implements ITtsEngine {
  private engine: textToSpeech.TextToSpeechEngine | null = null
  private isInitDone: boolean = false
  private speaking: boolean = false
  private currentCallback: TTSCallback | null = null
  private currentRequestId: string = '';

  async init(context: common.Context): Promise<void> {
    if (this.isInitDone) {
      return
    }

    try {
      const params: textToSpeech.CreateEngineParams = {
        language: 'zh-CN',  // 设置语言为中文
        person: 0,          // 设置发音人（0为默认发音人）
        online: 1           // 设置为在线模式（1为在线，0为离线）
      }

      textToSpeech.createEngine(params, (err: BusinessError, engine: textToSpeech.TextToSpeechEngine) => {
        if (!err) {
          console.info('Succeeded in creating engine.');
          // 获得引擎实例
          this.engine = engine;
        } else {
          console.error(`Failed to create engine. Code: ${err.code}, message: ${err.message}.`);
        }
      })

      // // 监听播放开始
      // this.engine.('speakStart', () => {
      //   console.info('SystemTtsEngine', 'speakStart')
      //   this.speaking = true
      //   if (this.currentCallback !== null) {
      //     this.currentCallback.onStart()
      //   }
      // })
      //
      // // 监听播放结束
      // this.engine.on('speakFinish', () => {
      //   console.info('SystemTtsEngine', 'speakFinish')
      //   this.speaking = false
      //   const cb = this.currentCallback
      //   this.currentCallback = null
      //   if (cb !== null) {
      //     cb.onComplete()
      //   }
      // })
      //
      // // 监听错误
      // this.engine.on('error', (err: BusinessError) => {
      //   console.error('SystemTtsEngine', `error: ${err.code}, ${err.message}`)
      //   this.speaking = false
      //   const cb = this.currentCallback
      //   this.currentCallback = null
      //   if (cb !== null) {
      //     cb.onError(`朗读失败: ${err.message}`)
      //   }
      // })

      this.isInitDone = true
      console.info('SystemTtsEngine', 'initialized')
    } catch (error) {
      const err = error as BusinessError
      console.error('SystemTtsEngine', `init failed: ${err.code}, ${err.message}`)
      throw new Error(`系统朗读引擎初始化失败: ${err.message}`)
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
