import { TtsEngineProfile, TtsEngineAvailability } from '../models/TtsEngineProfile'
import { ModelProvider } from '../models/ChatModels'
import { MIMO_TTS_PROVIDER_ID, STEPFUN_TTS_PROVIDER_ID } from '../config/TtsConfig'

// 纯函数: 给一个 profile + 当前 providers, 评估运行时可用性
export function evaluateTtsEngineAvailability(
  profile: TtsEngineProfile,
  providers: ModelProvider[]
): TtsEngineAvailability {
  if (!profile.requiresApiKey) {
    return { profile, isEnabled: true, unavailableReason: '' }
  }

  // mimo 与 minimax 都复用 MiniMax provider
  if (profile.id === 'mimo' || profile.id === 'minimax') {
    const matched = providers.find(
      (p) => p.id === MIMO_TTS_PROVIDER_ID && p.apiKey !== ''
    )
    if (matched === undefined) {
      return {
        profile,
        isEnabled: false,
        unavailableReason: '未配置 MiniMax API Key, 不可用'
      }
    }
  }

  // stepfun 复用 StepFun provider
  if (profile.id === 'stepfun') {
    const matched = providers.find(
      (p) => p.id === STEPFUN_TTS_PROVIDER_ID && p.apiKey !== ''
    )
    if (matched === undefined) {
      return {
        profile,
        isEnabled: false,
        unavailableReason: '未配置 StepFun API Key, 不可用'
      }
    }
  }

  return { profile, isEnabled: true, unavailableReason: '' }
}
