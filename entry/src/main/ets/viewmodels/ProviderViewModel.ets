import { getAIApiService, AIApiService, AIApiConfig, ModelsListResult, AIApiResult } from '../services/AIApiService'
import {
  ModelProvider,
  ProviderType,
  ApiStyle,
  OpenAITransport
} from '../models/ChatModels'
import {
  getEffectiveApiKey,
  isPresetProviderApiKeyRequired,
  applyPresetIconDefaults
} from '../config/PresetProviders'
import {
  CompatibilityProviderInfo,
  ModelDiscoveryStrategy,
  resolveProviderCompatibilityProfile
} from '../services/registry/CompatibilityResolver'
import { getAppSettingsStore, AppSettingsStore, BalanceResult } from '../state/AppSettingsStore'

/**
 * Provider 视图模型：对外公开 API 保持不变，作为 AppSettingsStore 的 facade。
 *
 * 本类拆分原则：
 * - 持久化 / 内存态 / 预设补齐 → AppSettingsStore 统一管理
 * - 纯业务（连接测试、模型列表刷新、兼容性决策）→ 留在本 VM
 *
 * 历史上本类还持有 cachedProviders + syncProviderProperties，已全部迁到 Store
 */
export class ProviderViewModel {
  private static instance: ProviderViewModel | null = null
  private aiApiService: AIApiService
  private store: AppSettingsStore

  private constructor() {
    this.aiApiService = getAIApiService()
    this.store = getAppSettingsStore()
  }

  static getInstance(): ProviderViewModel {
    if (ProviderViewModel.instance === null) {
      ProviderViewModel.instance = new ProviderViewModel()
    }
    return ProviderViewModel.instance
  }

  // ============================================================================
  // 列表加载（委托 Store）
  // ============================================================================

  /** 仅返回启用的服务商，用于模型选择器 */
  async loadProviders(): Promise<ModelProvider[]> {
    await this.store.loadAll()
    return this.store.getEnabledProviders()
  }

  /** 返回全部（含未启用），用于模型管理页面 */
  async loadAllProviders(): Promise<ModelProvider[]> {
    return await this.store.loadAll()
  }

  /** 从内存缓存取 provider；未命中返回 null */
  getProviderById(providerId: string): ModelProvider | null {
    return this.store.getProviderById(providerId)
  }

  /** 缓存未命中时自动回源 DB */
  async getProviderByIdAsync(providerId: string): Promise<ModelProvider | null> {
    return await this.store.getProviderByIdAsync(providerId)
  }

  /** 获取当前内存中的 provider 列表（快速 UI 同步用） */
  getCachedProviders(): ModelProvider[] {
    return this.store.getProviders()
  }

  // ============================================================================
  // 写操作（委托 Store）
  // ============================================================================

  async saveProvider(provider: ModelProvider, insertAtFront: boolean = false): Promise<void> {
    await this.store.upsertProvider(provider, insertAtFront)
  }

  async deleteProvider(providerId: string): Promise<void> {
    await this.store.removeProvider(providerId)
  }

  async updateProviderEnabled(providerId: string, isEnabled: boolean): Promise<void> {
    await this.store.setProviderEnabled(providerId, isEnabled)
  }

  async saveProvidersOrder(providerIds: string[]): Promise<void> {
    await this.store.reorderProviders(providerIds)
  }

  /**
   * 把 source 的所有字段浅拷贝到 target。保留为 stateless helper：
   * UI 层（ModelManagePage）通过它把 Store 新返的 provider 字段刷到
   * 已绑定到子组件 @Param 的旧实例上，保证子组件引用稳定、不触发重建
   */
  syncProviderProperties(target: ModelProvider, source: ModelProvider): void {
    target.name = source.name
    target.isConnected = source.isConnected
    target.apiKey = source.apiKey
    target.requiresApiKey = source.requiresApiKey
    target.baseUrl = source.baseUrl
    target.apiPath = source.apiPath
    target.openaiTransport = source.openaiTransport
    target.customHeadersJson = source.customHeadersJson
    target.apiStyle = source.apiStyle
    target.type = source.type
    target.models = source.models
    target.iconType = source.iconType
    target.iconPath = source.iconPath
    target.textIcon = source.textIcon
    target.textIconBgColor = source.textIconBgColor
    target.customImagePath = source.customImagePath
    target.brandColor = source.brandColor
    target.isPreset = source.isPreset
    target.iconSymbol = source.iconSymbol
  }

  /** 预设补齐 + 历史 URL 修复 + 加载到内存（幂等） */
  async initializeAllPresetProviders(): Promise<void> {
    await this.store.ensureInitialized()
  }

  // ============================================================================
  // 业务：连接测试 / 模型列表
  // ============================================================================

  async testConnection(provider: ModelProvider): Promise<AIApiResult> {
    const config = this.providerToApiConfig(provider)
    let testModelId = this.getPreferredModelId(provider)

    if (testModelId === '') {
      const modelsResult = await this.aiApiService.getModels(config)
      if (!modelsResult.success) {
        return {
          success: false,
          content: '',
          errorMessage: modelsResult.errorMessage,
          usage: null,
          reasoningContent: ''
        }
      }
      if (modelsResult.models.length === 0) {
        return {
          success: false,
          content: '',
          errorMessage: '请先添加一个模型后再测试连接',
          usage: null,
          reasoningContent: ''
        }
      }
      testModelId = this.selectConnectionTestModel(provider, modelsResult.models)
    }

    return await this.aiApiService.testConnection(config, testModelId)
  }

  async refreshModels(provider: ModelProvider): Promise<ModelsListResult> {
    const config = this.providerToApiConfig(provider)
    const modelsResult = await this.aiApiService.getModels(config)
    if (!modelsResult.success || !this.shouldVerifyStaticModelCatalog(provider) || modelsResult.models.length === 0) {
      return modelsResult
    }

    const testModelId = this.selectConnectionTestModel(provider, modelsResult.models)
    if (testModelId === '') {
      return modelsResult
    }

    const testResult = await this.aiApiService.testConnection(config, testModelId)
    if (!testResult.success) {
      return {
        success: false,
        models: [],
        errorMessage: testResult.errorMessage
      }
    }

    return modelsResult
  }

  async queryProviderBalance(providerId: string): Promise<BalanceResult | null> {
    return await this.store.queryProviderBalance(providerId)
  }

  // ============================================================================
  // 业务 helpers
  // ============================================================================

  /** 把运行时 Provider 转成一次请求所需的最小 AIApiConfig */
  private providerToApiConfig(provider: ModelProvider): AIApiConfig {
    return {
      providerId: provider.id,
      providerType: provider.type,
      apiStyle: provider.apiStyle,
      apiKey: getEffectiveApiKey(provider.id, provider.apiKey),
      baseUrl: provider.baseUrl,
      apiPath: provider.apiPath || undefined,
      openaiTransport: provider.openaiTransport,
      customHeadersJson: provider.customHeadersJson || undefined
    }
  }

  private getPreferredModelId(provider: ModelProvider): string {
    for (let i = 0; i < provider.models.length; i++) {
      const model = provider.models[i]
      if (model.isEnabled) {
        return model.id
      }
    }
    if (provider.models.length > 0) {
      return provider.models[0].id
    }
    return ''
  }

  private toCompatibilityInfo(provider: ModelProvider): CompatibilityProviderInfo {
    return {
      providerId: provider.id,
      baseUrl: provider.baseUrl,
      apiStyle: provider.apiStyle
    }
  }

  private selectConnectionTestModel(provider: ModelProvider, modelIds: string[]): string {
    if (modelIds.length === 0) {
      return ''
    }

    const compatibilityProfile = resolveProviderCompatibilityProfile(this.toCompatibilityInfo(provider))
    if (compatibilityProfile.modelDiscoveryStrategy === ModelDiscoveryStrategy.STATIC_CATALOG) {
      return modelIds[0]
    }

    const preferredKeywords = this.getPreferredConnectionModelKeywords(provider.apiStyle)
    for (let i = 0; i < modelIds.length; i++) {
      const modelId = modelIds[i]
      const normalizedModelId = modelId.toLowerCase()
      for (let j = 0; j < preferredKeywords.length; j++) {
        if (normalizedModelId.includes(preferredKeywords[j])) {
          return modelId
        }
      }
    }

    for (let i = 0; i < modelIds.length; i++) {
      const normalizedModelId = modelIds[i].toLowerCase()
      if (!normalizedModelId.includes('embedding') &&
        !normalizedModelId.includes('rerank') &&
        !normalizedModelId.includes('tts') &&
        !normalizedModelId.includes('speech') &&
        !normalizedModelId.includes('audio')) {
        return modelIds[i]
      }
    }

    return modelIds[0]
  }

  private shouldVerifyStaticModelCatalog(provider: ModelProvider): boolean {
    const compatibilityProfile = resolveProviderCompatibilityProfile(this.toCompatibilityInfo(provider))
    return compatibilityProfile.modelDiscoveryStrategy === ModelDiscoveryStrategy.STATIC_CATALOG
  }

  private getPreferredConnectionModelKeywords(apiStyle: ApiStyle): string[] {
    if (apiStyle === ApiStyle.OPENAI) {
      return ['gpt', 'chat']
    }
    if (apiStyle === ApiStyle.ANTHROPIC) {
      return ['claude']
    }
    if (apiStyle === ApiStyle.GOOGLE) {
      return ['gemini']
    }
    return []
  }

  // ============================================================================
  // 首次启动的默认 provider（UI 层在 DB 空时短暂展示用）
  // ============================================================================

  getDefaultProviders(): ModelProvider[] {
    const providers: ModelProvider[] = []

    const deepseek = new ModelProvider(
      'deepseek',
      'DeepSeek',
      ProviderType.DEEPSEEK,
      'message',
      $r('app.color.brand_custom'),
      'https://api.deepseek.com/v1',
      ApiStyle.OPENAI
    )
    deepseek.apiKey = ''
    deepseek.requiresApiKey = isPresetProviderApiKeyRequired(deepseek.id)
    deepseek.isConnected = true
    deepseek.isPreset = true
    deepseek.iconPath = ''
    deepseek.apiPath = ''
    deepseek.openaiTransport = OpenAITransport.CHAT_COMPLETIONS
    applyPresetIconDefaults(deepseek, deepseek.id)
    providers.push(deepseek)

    return providers
  }
}

export function createProviderViewModel(): ProviderViewModel {
  return ProviderViewModel.getInstance()
}

export function getProviderViewModel(): ProviderViewModel {
  return ProviderViewModel.getInstance()
}
