import { ITtsEngine } from '../services/tts/ITtsEngine'

// TTS 引擎的元数据, 用于 TtsEngineRegistry 和 UI 列表
export interface TtsEngineProfile {
  id: string                    // 'system' | 'mimo' | 未来 'elevenlabs' ...
  displayName: string           // '系统朗读' / 'MiMo 语音'
  description: string           // 长描述, 1-2 句
  requiresApiKey: boolean       // 标识是否需要外部 API key
  iconSymbol: string            // sys.symbol.* 名称
}

// 运行时注册的完整条目, profile + 工厂闭包
// factory 不接受 context: 引擎的 init() 由 TTSService 显式调用, 这样 registry
// 不依赖全局 context, 也避免 TtsEngineRegistration 在不同注册时机拿不到 context
export interface TtsEngineRegistration {
  profile: TtsEngineProfile
  factory: () => ITtsEngine
}

// 引擎当前是否在当前环境下可用 (例如 mimo 缺 api key 时 isEnabled: false)
export interface TtsEngineAvailability {
  profile: TtsEngineProfile
  isEnabled: boolean
  unavailableReason: string    // 空串 = 可用; 非空 = 原因
}
