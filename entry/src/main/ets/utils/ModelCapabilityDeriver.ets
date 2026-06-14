/**
 * 模型能力派生工具
 * - capabilitiesUserModified === false:从 ModelAbilityRegistry 实时派生(规则升级自动跟随)
 * - capabilitiesUserModified === true:返回 model.capabilities 持久化值(用户手动覆盖)
 *
 * 单独成文件而非挂在 ModelInfo 上,避免 ChatModels → registry/types → ChatModels 的循环依赖
 */

import { InputMode, ModelInfo, ModelCapabilities, OutputMode } from '../models/ChatModels'
import { lookupModelAbilities, ModelAbility, ModelModality } from '../services/registry/ModelAbilityRegistry'

export function deriveModelCapabilities(modelId: string): ModelCapabilities {
  const result = lookupModelAbilities(modelId)
  const cap = new ModelCapabilities()
  cap.supportsTools = result.abilities.includes(ModelAbility.TOOL)
  cap.supportsReasoning = result.abilities.includes(ModelAbility.REASONING)
  cap.supportsVision = result.inputModalities.includes(ModelModality.IMAGE)
  cap.supportsWebSearch = false
  cap.supportsStreaming = true
  cap.supportsMusicGeneration = result.abilities.includes(ModelAbility.MUSIC_GENERATION)
  cap.supportsVideoGeneration = result.abilities.includes(ModelAbility.VIDEO_GENERATION)
  return cap
}

export function getEffectiveCapabilities(model: ModelInfo): ModelCapabilities {
  if (model.capabilitiesUserModified) {
    return model.capabilities
  }
  return deriveModelCapabilities(model.id)
}

export function deriveModelInputMode(modelId: string): InputMode {
  const result = lookupModelAbilities(modelId)
  return result.inputModalities.includes(ModelModality.IMAGE) ? InputMode.VISION : InputMode.TEXT
}

export function deriveModelOutputMode(modelId: string): OutputMode {
  const result = lookupModelAbilities(modelId)
  // 优先级: 音乐/视频专属能力 > 图像能力 > 文本。
  // 顺序很重要: 优先识别 MUSIC/VIDEO 这两个具体能力, 再回退到 IMAGE (含 image output modality), 最后 TEXT。
  if (result.abilities.includes(ModelAbility.MUSIC_GENERATION)) {
    return OutputMode.MUSIC
  }
  if (result.abilities.includes(ModelAbility.VIDEO_GENERATION)) {
    return OutputMode.VIDEO
  }
  if (result.abilities.includes(ModelAbility.IMAGE_GENERATION) ||
    result.outputModalities.includes(ModelModality.IMAGE)) {
    return OutputMode.IMAGE
  }
  return OutputMode.TEXT
}

export function getEffectiveOutputMode(model: ModelInfo): OutputMode {
  if (model.capabilitiesUserModified) {
    return model.outputMode
  }
  const derived = deriveModelOutputMode(model.id)
  // 用户未手动修改时, 若派生 output mode 是 IMAGE/MUSIC/VIDEO 这三种生媒体模式,
  // 用派生值覆盖默认 TEXT; 否则保持 model.outputMode (通常是 TEXT)。
  if (derived === OutputMode.IMAGE || derived === OutputMode.MUSIC || derived === OutputMode.VIDEO) {
    return derived
  }
  return model.outputMode
}

export function applyDerivedModelDefaults(model: ModelInfo): void {
  if (model.capabilitiesUserModified) {
    return
  }
  model.capabilities = deriveModelCapabilities(model.id)
  const derivedInputMode = deriveModelInputMode(model.id)
  if (derivedInputMode === InputMode.VISION) {
    model.inputMode = InputMode.VISION
  }
  const derivedOutputMode = deriveModelOutputMode(model.id)
  if (derivedOutputMode === OutputMode.IMAGE ||
    derivedOutputMode === OutputMode.MUSIC ||
    derivedOutputMode === OutputMode.VIDEO) {
    model.outputMode = derivedOutputMode
  }
}
