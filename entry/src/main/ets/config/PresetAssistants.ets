/**
 * 预设助手配置
 * 定义内置的助手，这些助手在首次启动时自动创建，不可删除
 */

export interface PresetAssistantDef {
  id: string
  name: string
  avatarSymbol: string
  color: string
  systemPrompt: string
  enabledToolIds?: string[]
  contextMessageCount?: number
  maxOutputTokens?: number
  // 只影响首次补齐。既有用户配置不会被覆盖。
  autoInstall?: boolean
}

const PRESET_ASSISTANTS: PresetAssistantDef[] = [
  // 小星老师 现已成为默认助手，不再作为预设自动安装
]

const PRESET_ASSISTANT_IDS: Set<string> = new Set(PRESET_ASSISTANTS.map((p: PresetAssistantDef): string => p.id))

export function getPresetAssistants(): PresetAssistantDef[] {
  return PRESET_ASSISTANTS
}

export function getAutoInstallPresetAssistants(): PresetAssistantDef[] {
  const result: PresetAssistantDef[] = []
  for (let i = 0; i < PRESET_ASSISTANTS.length; i++) {
    const preset = PRESET_ASSISTANTS[i]
    if (preset.autoInstall !== false) {
      result.push(preset)
    }
  }
  return result
}

export function getPresetAssistantById(id: string): PresetAssistantDef | null {
  for (let i = 0; i < PRESET_ASSISTANTS.length; i++) {
    if (PRESET_ASSISTANTS[i].id === id) {
      return PRESET_ASSISTANTS[i]
    }
  }
  return null
}

export function isPresetAssistant(id: string): boolean {
  return PRESET_ASSISTANT_IDS.has(id)
}
