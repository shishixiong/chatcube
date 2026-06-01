// TTS 引擎类型
export type TtsEngineType = 'system' | 'mimo'

// 当前使用的 TTS 引擎（改为 'mimo' 即可切换小米 MiMo 引擎）
export const TTS_ENGINE: TtsEngineType = 'mimo'

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
