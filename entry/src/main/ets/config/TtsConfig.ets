import { TtsVoice } from '../models/TtsEngineProfile'

// TTS 引擎 ID 联合, 与 TtsEngineRegistry 共享
export type TtsEngineId = 'system' | 'mimo' | 'minimax'

// 注册表都 miss 时的 fallback 引擎
export const TTS_FALLBACK_ENGINE_ID: TtsEngineId = 'system'

// mimo 引擎绑定的 provider id (用于 evaluateTtsEngineAvailability 查 api key)
export const MIMO_TTS_PROVIDER_ID: string = 'minimax'

// MiMo 引擎支持的音色列表
export const MIMO_TTS_VOICES: TtsVoice[] = [
  { id: '冰糖', name: '冰糖', language: '中文', gender: '女性' },
  { id: '茉莉', name: '茉莉', language: '中文', gender: '女性' },
  { id: '苏打', name: '苏打', language: '中文', gender: '男性' },
  { id: '白桦', name: '白桦', language: '中文', gender: '男性' },
  { id: 'Mia', name: 'Mia', language: '英文', gender: '女性' },
  { id: 'Chloe', name: 'Chloe', language: '英文', gender: '女性' },
  { id: 'Milo', name: 'Milo', language: '英文', gender: '男性' },
  { id: 'Dean', name: 'Dean', language: '英文', gender: '男性' }
]

// MiniMax 引擎支持的音色列表
export const MINIMAX_TTS_VOICES: TtsVoice[] = [
  { id: 'clever_boy', name: '聪明男童', language: '中文', gender: '男性' },
  { id: 'cute_boy', name: '可爱男童', language: '中文', gender: '男性' },
  { id: 'lovely_girl', name: '萌萌女童', language: '中文', gender: '女性' },
  { id: 'cartoon_pig', name: '卡通猪小琪', language: '中文', gender: '女性' },
  { id: 'Santa_Claus', name: 'Santa Claus', language: '英文', gender: '男性' },
  { id: 'Grinch', name: 'Grinch', language: '英文', gender: '男性' },
  { id: 'Rudolph', name: 'Rudolph', language: '英文', gender: '男性' },
  { id: 'Arnold', name: 'Arnold', language: '英文', gender: '男性' },
  { id: 'English_Gentle-voiced_man', name: 'Gentle-voiced man', language: '英文', gender: '男性' }
]

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
  voice: 'cartoon_pig',
  audioFormat: 'mp3',
  sampleRate: 32000,
  bitrate: 128000,
  speed: 1.0,
  pitch: 0
}
