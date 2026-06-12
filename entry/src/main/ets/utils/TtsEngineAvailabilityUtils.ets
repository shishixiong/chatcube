import { TtsEngineProfile, TtsEngineAvailability } from '../models/TtsEngineProfile'
import { ModelProvider } from '../models/ChatModels'
import { MIMO_TTS_PROVIDER_ID } from '../config/TtsConfig'

// 纯函数: 给一个 profile + 当前 providers, 评估运行时可用性
export function evaluateTtsEngineAvailability(
  profile: TtsEngineProfile,
  providers: ModelProvider[]
): TtsEngineAvailability {
  if (!profile.requiresApiKey) {
    return { profile, isEnabled: true, unavailableReason: '' }
  }

  // 当前唯一需要 key 的引擎是 mimo, 复用 MiniMax provider
  // 未来若需绑其他 provider, 在这里加 case
  if (profile.id === 'mimo') {
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

  return { profile, isEnabled: true, unavailableReason: '' }
}
