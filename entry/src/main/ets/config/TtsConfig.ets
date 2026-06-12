// TTS 引擎 ID 联合, 与 TtsEngineRegistry 共享
export type TtsEngineId = 'system' | 'mimo'

// 注册表都 miss 时的 fallback 引擎
export const TTS_FALLBACK_ENGINE_ID: TtsEngineId = 'system'

// mimo 引擎绑定的 provider id (用于 evaluateTtsEngineAvailability 查 api key)
export const MIMO_TTS_PROVIDER_ID: string = 'minimax'

// MiMo 流式 TTS 配置（Chat Completions 格式）
interface MiMoTtsConfig {
  apiUrl: string
  model: string
  voice: string
  audioFormat: string
}

export const MIMO_TTS_CONFIG: MiMoTtsConfig = {
  apiUrl: 'https://api.xiaomimimo.com/v1/chat/completions',
  model: 'mimo-v2.5-tts',
  voice: '冰糖',
  audioFormat: 'mp3'
}

// MiniMax 同步/流式 TTS 配置（T2A v2 接口）
interface MiniMaxTtsConfig {
  apiUrl: string
  model: string
  voice: string
  audioFormat: string
  sampleRate: number
  bitrate: number
  speed: number
  pitch: number
}

export const MINIMAX_TTS_CONFIG: MiniMaxTtsConfig = {
  apiUrl: 'https://api-bj.minimaxi.com/v1/t2a_v2',
  model: 'speech-2.8-hd',
  voice: 'male-qn-qingse',
  audioFormat: 'mp3',
  sampleRate: 32000,
  bitrate: 128000,
  speed: 1.0,
  pitch: 0
}
