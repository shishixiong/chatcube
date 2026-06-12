import { ITtsEngine } from '../services/tts/ITtsEngine'

// 单个 TTS 音色选项
export interface TtsVoice {
  id: string                    // 音色 id, 传给引擎 API (如 'cartoon_pig', '冰糖')
  name: string                  // 显示名 (如 '卡通猪小琪', '冰糖')
  language: string              // '中文' / '英文'
  gender: string                // '女性' / '男性'
}

// TTS 引擎的元数据, 用于 TtsEngineRegistry 和 UI 列表
export interface TtsEngineProfile {
  id: string                    // 'system' | 'mimo' | 未来 'elevenlabs' ...
  displayName: string           // '系统朗读' / 'MiMo 语音'
  description: string           // 长描述, 1-2 句
  requiresApiKey: boolean       // 标识是否需要外部 API key
  iconSymbol: string            // sys.symbol.* 名称
  voices: TtsVoice[]            // 引擎支持的音色列表, system 引擎为空数组
  defaultVoiceId: string        // 引擎默认音色 id (从 voices 中挑, 用户未配时使用)
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
