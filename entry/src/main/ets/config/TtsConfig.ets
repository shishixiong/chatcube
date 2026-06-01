// TTS 引擎类型
export type TtsEngineType = 'system' | 'mimo'

// 当前使用的 TTS 引擎（改为 'mimo' 即可切换小米 MiMo 引擎）
export const TTS_ENGINE: TtsEngineType = 'system'

// MiMo TTS 配置
interface GeneratedObjectLiteralInterface {
  // API 地址
  apiUrl: string;

  // 模型
  model: string;

  // 默认音色
  voice: string;

  // 默认语速
  speed: number;
}

export const MIMO_TTS_CONFIG: GeneratedObjectLiteralInterface = {
  // API 地址
  apiUrl: 'https://api.minimax.chat/v1/t2a_v2',
  // 模型
  model: 'speech-01',
  // 默认音色
  voice: 'male-qn-qingse',
  // 默认语速
  speed: 1.0
}
