/**
 * 预设供应商配置
 * 定义内置的模型供应商，这些供应商不可删除
 */

import { ProviderType, ApiStyle, OpenAITransport, ProviderIconType, ModelProvider } from '../models/ChatModels'
import { DEFAULT_PRIMARY_COLOR } from './ThemeDefaults'
import { DEFAULT_MODELS_DEV_BASE_URL } from '../services/PreferencesService'

export interface BalanceOption {
  apiPath: string
  resultPath: string
  currency?: string
}

// 预设供应商声明。预设的内置字段集中在这里，启动补齐只读取这张表。
export interface PresetProviderDef {
  id: string
  name: string
  type: ProviderType
  apiStyle: ApiStyle
  openaiTransport?: OpenAITransport
  baseUrl: string
  requiresApiKey?: boolean
  iconPath: string      // SVG 图标路径（已弃用，置空）
  brandColorHex: string // 品牌色（十六进制）
  presetApiKey?: string // 预设 API Key（可选，用户不填时使用）
  textIcon: string      // 文字图标内容（也作为远程 logo 加载失败的兜底显示）
  textIconBgColor: string // 文字图标背景色
  // models.dev 上对应的 provider key，用于拉取远程 SVG logo（${baseUrl}/logos/{key}.svg）。
  // 留空则不使用远程 logo，仅显示文字图标。
  logoProviderKey?: string
  balance?: BalanceOption
  // 只影响首次补齐。既有用户配置不会被覆盖。
  defaultEnabled?: boolean
  // 允许保留在预设选择列表里，但不参与启动自动补齐。
  autoInstall?: boolean
}

export type PresetProviderConfig = PresetProviderDef

// 预设供应商列表（主流厂商，不可删除）
const PRESET_PROVIDERS: PresetProviderDef[] = [
  {
    id: 'deepseek',
    name: 'DeepSeek',
    type: ProviderType.DEEPSEEK,
    apiStyle: ApiStyle.OPENAI,
    openaiTransport: OpenAITransport.CHAT_COMPLETIONS,
    baseUrl: 'https://api.deepseek.com/v1',
    iconPath: '',
    brandColorHex: '#4D6BFE',
    textIcon: 'DS',
    textIconBgColor: '#4D6BFE',
    logoProviderKey: 'deepseek',
    balance: {
      apiPath: '/user/balance',
      resultPath: 'balance_infos[0].total_balance',
      currency: 'CNY'
    }
  },
  {
    id: 'minimax',
    name: 'MiniMax',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://api.minimaxi.com/v1',
    iconPath: '',
    brandColorHex: '#00A876',
    textIcon: 'M',
    textIconBgColor: '#00A876',
    logoProviderKey: 'minimax'
  },
  {
    id: 'mimo',
    name: 'MiMo',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    openaiTransport: OpenAITransport.CHAT_COMPLETIONS,
    baseUrl: 'https://api.xiaomimimo.com/v1',
    iconPath: '',
    brandColorHex: '#FF6900',
    textIcon: 'Mi',
    textIconBgColor: '#FF6900',
    logoProviderKey: 'xiaomi'
  },
  {
    id: 'openai',
    name: 'OpenAI',
    type: ProviderType.OPENAI,
    apiStyle: ApiStyle.OPENAI,
    openaiTransport: OpenAITransport.CHAT_COMPLETIONS,
    baseUrl: 'https://api.openai.com/v1',
    iconPath: '',
    brandColorHex: '#202123',
    textIcon: 'AI',
    textIconBgColor: '#202123',
    logoProviderKey: 'openai'
  },
  {
    id: 'anthropic',
    name: 'Claude',
    type: ProviderType.ANTHROPIC,
    apiStyle: ApiStyle.ANTHROPIC,
    openaiTransport: OpenAITransport.CHAT_COMPLETIONS,
    baseUrl: 'https://api.anthropic.com',
    iconPath: '',
    brandColorHex: '#C45C3A',
    textIcon: 'C',
    textIconBgColor: '#C45C3A',
    logoProviderKey: 'anthropic'
  },
  {
    id: 'gemini',
    name: 'Gemini',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.GOOGLE,
    openaiTransport: OpenAITransport.CHAT_COMPLETIONS,
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    iconPath: '',
    brandColorHex: '#4285F4',
    textIcon: 'G',
    textIconBgColor: '#4285F4',
    logoProviderKey: 'google'
  },
  {
    id: 'openrouter',
    name: 'OpenRouter',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://openrouter.ai/api/v1',
    iconPath: '',
    brandColorHex: '#6366F1',
    textIcon: 'OR',
    textIconBgColor: '#6366F1',
    logoProviderKey: 'openrouter',
    balance: {
      apiPath: '/credits',
      resultPath: 'data.total_credits - data.total_usage',
      currency: 'USD'
    }
  },
  {
    id: 'siliconflow',
    name: '硅基流动',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://api.siliconflow.cn/v1',
    iconPath: '',
    brandColorHex: '#7C3AED',
    textIcon: 'SF',
    textIconBgColor: '#7C3AED',
    logoProviderKey: 'siliconflow',
    defaultEnabled: true,
    balance: {
      apiPath: '/user/info',
      resultPath: 'data.totalBalance',
      currency: 'CNY'
    }
  },
  {
    id: 'qwen',
    name: '阿里云百炼',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    iconPath: '',
    brandColorHex: '#615CED',
    textIcon: 'Q',
    textIconBgColor: '#615CED',
    logoProviderKey: 'alibaba'
  },
  {
    id: 'kimi',
    name: 'Kimi',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://api.moonshot.cn/v1',
    iconPath: '',
    brandColorHex: '#0F172A',
    textIcon: 'K',
    textIconBgColor: '#0F172A',
    logoProviderKey: 'moonshotai',
    balance: {
      apiPath: '/users/me/balance',
      resultPath: 'data.available_balance',
      currency: 'CNY'
    }
  },
  {
    id: 'zhipu',
    name: '智谱 AI',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    iconPath: '',
    brandColorHex: '#3B82F6',
    textIcon: 'Z',
    textIconBgColor: '#3B82F6',
    logoProviderKey: 'zhipuai'
  },
  {
    id: 'doubao',
    name: '火山引擎',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    iconPath: '',
    brandColorHex: '#3370FF',
    textIcon: 'D',
    textIconBgColor: '#3370FF'
  },
  {
    id: 'aihubmix',
    name: 'AiHubMix',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://aihubmix.com/v1',
    iconPath: '',
    brandColorHex: '#D97706',
    textIcon: 'AH',
    textIconBgColor: '#D97706',
    logoProviderKey: 'aihubmix'
  },
  {
    id: 'grok',
    name: 'Grok',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://api.x.ai/v1',
    iconPath: '',
    brandColorHex: '#000000',
    textIcon: 'G',
    textIconBgColor: '#000000',
    logoProviderKey: 'xai'
  },
  {
    id: 'aiping',
    name: 'AIPing',
    type: ProviderType.CUSTOM,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'https://aiping.cn/api/v1',
    iconPath: '',
    brandColorHex: '#6C5CE7',
    textIcon: 'AP',
    textIconBgColor: '#6C5CE7',
    autoInstall: false
  },
  {
    id: 'ollama',
    name: 'Ollama',
    type: ProviderType.OLLAMA,
    apiStyle: ApiStyle.OPENAI,
    baseUrl: 'http://localhost:11434/v1',
    requiresApiKey: false,
    iconPath: '',
    brandColorHex: '#FFFFFF',
    textIcon: '🦙',
    textIconBgColor: '',
    logoProviderKey: 'ollama-cloud'
  }
]

// 预设供应商 ID 集合（用于快速判断）
const PRESET_PROVIDER_IDS: Set<string> = new Set(PRESET_PROVIDERS.map(p => p.id))

/**
 * 获取所有预设供应商配置
 */
export function getPresetProviders(): PresetProviderDef[] {
  return PRESET_PROVIDERS
}

export function getAutoInstallPresetProviders(): PresetProviderDef[] {
  const result: PresetProviderDef[] = []
  for (let i = 0; i < PRESET_PROVIDERS.length; i++) {
    const preset = PRESET_PROVIDERS[i]
    if (preset.autoInstall !== false) {
      result.push(preset)
    }
  }
  return result
}

/**
 * 根据 ID 获取预设供应商配置
 */
export function getPresetProviderById(id: string): PresetProviderDef | null {
  for (let i = 0; i < PRESET_PROVIDERS.length; i++) {
    if (PRESET_PROVIDERS[i].id === id) {
      return PRESET_PROVIDERS[i]
    }
  }
  return null
}

/**
 * 判断是否为预设供应商
 */
export function isPresetProvider(providerId: string): boolean {
  return PRESET_PROVIDER_IDS.has(providerId)
}

/**
 * 获取供应商图标路径
 * @param providerId 供应商 ID
 * @returns 图标文件路径，如果不是预设供应商则返回空字符串
 */
export function getPresetProviderIconPath(providerId: string): string {
  const preset = getPresetProviderById(providerId)
  if (preset !== null) {
    return preset.iconPath
  }
  return ''
}

/**
 * 获取供应商品牌色
 * @param providerId 供应商 ID
 * @returns 品牌色十六进制值，如果不是预设供应商则返回默认色
 */
export function getPresetProviderBrandColor(providerId: string): string {
  const preset = getPresetProviderById(providerId)
  if (preset !== null) {
    return preset.brandColorHex
  }
  return DEFAULT_PRIMARY_COLOR
}

/**
 * 获取供应商的有效 API Key
 * 如果用户配置了 API Key 则使用用户的，否则使用预设的
 * @param providerId 供应商 ID
 * @param userApiKey 用户配置的 API Key
 * @returns 有效的 API Key
 */
export function getEffectiveApiKey(providerId: string, userApiKey: string): string {
  // 如果用户配置了 API Key，优先使用
  if (userApiKey !== '') {
    return userApiKey
  }
  // 否则尝试使用预设的 API Key
  const preset = getPresetProviderById(providerId)
  if (preset !== null && preset.presetApiKey !== undefined) {
    return preset.presetApiKey
  }
  return ''
}

export function isPresetProviderApiKeyRequired(providerId: string): boolean {
  const preset = getPresetProviderById(providerId)
  if (preset !== null && preset.requiresApiKey !== undefined) {
    return preset.requiresApiKey
  }
  return true
}

/**
 * 由 logoProviderKey 拼接 models.dev 远程 logo URL。
 * 没有 logoProviderKey 返回空字符串。
 */
export function getPresetProviderLogoUrl(providerId: string): string {
  const preset = getPresetProviderById(providerId)
  if (preset === null || preset.logoProviderKey === undefined || preset.logoProviderKey === '') {
    return ''
  }
  return `${DEFAULT_MODELS_DEV_BASE_URL}/logos/${preset.logoProviderKey}.svg`
}

/**
 * 把预设服务商的默认图标配置写入 ModelProvider：
 * 有远程 logo 用 IMAGE+URL，否则用 TEXT；textIcon/bg 总是写入预设值作为兜底。
 * 返回 true 表示已应用，false 表示 providerId 不是预设服务商。
 */
export function applyPresetIconDefaults(provider: ModelProvider, providerId: string): boolean {
  const preset = getPresetProviderById(providerId)
  if (preset === null) {
    return false
  }
  provider.iconPath = ''
  provider.textIcon = preset.textIcon
  provider.textIconBgColor = preset.textIconBgColor
  const logoUrl = getPresetProviderLogoUrl(providerId)
  if (logoUrl !== '') {
    provider.iconType = ProviderIconType.IMAGE
    provider.customImagePath = logoUrl
  } else {
    provider.iconType = ProviderIconType.TEXT
    provider.customImagePath = ''
  }
  return true
}

/**
 * 获取未配置的预置服务商列表
 * @param configuredIds 已配置的服务商 ID 列表
 * @returns 未配置的预置服务商配置列表
 */
export function getUnconfiguredPresetProviders(configuredIds: string[]): PresetProviderDef[] {
  const configuredSet = new Set<string>(configuredIds)
  const result: PresetProviderDef[] = []
  for (let i = 0; i < PRESET_PROVIDERS.length; i++) {
    const preset = PRESET_PROVIDERS[i]
    if (!configuredSet.has(preset.id)) {
      result.push(preset)
    }
  }
  return result
}
