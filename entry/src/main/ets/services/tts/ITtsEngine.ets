import { common } from '@kit.AbilityKit'

// TTS 事件回调接口
export interface TTSCallback {
  onStart: () => void
  onComplete: () => void
  onError: (error: string) => void
}

// TTS 引擎统一接口
export interface ITtsEngine {
  // 初始化引擎
  init(context: common.Context): Promise<void>

  // 朗读文本；speed 为可选语速（0.5–2.0，1 为正常，<1 慢速），不传用引擎默认值。
  // 引擎不支持语速时忽略（如 mimo 提示词式合成）。
  speak(text: string, callback: TTSCallback, speed?: number): Promise<void>

  // 停止朗读
  stop(): void

  // 是否正在播放
  isSpeaking(): boolean

  // 释放资源
  destroy(): void
}
