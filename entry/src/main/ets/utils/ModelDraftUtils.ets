import {
  InputMode,
  ModelCapabilities,
  ModelInfo,
  ModelInfoExtendedJson,
  ModelType,
  OutputMode
} from '../models/ChatModels'

function toModelType(raw?: string): ModelType {
  return raw === 'embedding' ? ModelType.EMBEDDING : ModelType.CHAT
}

function toInputMode(raw?: string): InputMode {
  return raw === InputMode.VISION ? InputMode.VISION : InputMode.TEXT
}

function toOutputMode(raw?: string): OutputMode {
  switch (raw) {
    case OutputMode.IMAGE:
      return OutputMode.IMAGE
    case OutputMode.MUSIC:
      return OutputMode.MUSIC
    case OutputMode.VIDEO:
      return OutputMode.VIDEO
    case OutputMode.TEXT:
    default:
      return OutputMode.TEXT
  }
}

export function applyModelDraft(target: ModelInfo, draft: ModelInfoExtendedJson): void {
  target.name = draft.name
  target.contextLength = draft.contextLength
  target.isEnabled = draft.isEnabled
  target.isRecommended = draft.isRecommended

  if (draft.modelType !== undefined) {
    target.modelType = toModelType(draft.modelType)
  }
  if (draft.inputMode !== undefined) {
    target.inputMode = toInputMode(draft.inputMode)
  }
  if (draft.outputMode !== undefined) {
    target.outputMode = toOutputMode(draft.outputMode)
  }
  if (draft.capabilities !== undefined) {
    target.capabilities = ModelCapabilities.fromJson(draft.capabilities)
  }
  // 覆盖标志:draft 缺失视为 false(派生轨道)
  target.capabilitiesUserModified = draft.capabilitiesUserModified ?? false
}
