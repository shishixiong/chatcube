import { ModelInfo, ModelProvider } from '../models/ChatModels'
import { getEffectiveCapabilities } from './ModelCapabilityDeriver'

export interface ReasoningModelPick {
  provider: ModelProvider
  reasoningModel: ModelInfo
}

/**
 * 纯函数: 在 providers 列表中找第一个 isEnabled 且 supportsReasoning 的模型。
 * 按 provider 在数组中的顺序遍历, provider 内按 model 数组顺序遍历。
 * 返回 null 表示找不到。
 */
export function filterReasoningModels(
  providers: ModelProvider[]
): ReasoningModelPick | null {
  for (let i = 0; i < providers.length; i++) {
    const provider = providers[i]
    for (let j = 0; j < provider.models.length; j++) {
      const model = provider.models[j]
      if (!model.isEnabled) {
        continue
      }
      if (!getEffectiveCapabilities(model).supportsReasoning) {
        continue
      }
      return { provider, reasoningModel: model }
    }
  }
  return null
}
