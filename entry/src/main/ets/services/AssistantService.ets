import { Assistant, DEFAULT_ASSISTANT_ID, DEFAULT_ASSISTANT_SYSTEM_PROMPT, DEFAULT_ASSISTANT_LOCKED_TOOL_IDS } from '../models/AssistantModels'
import { ReasoningLevel } from '../models/ChatModels'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { DEFAULT_PRIMARY_COLOR } from '../config/ThemeDefaults'
import { PreferenceKeys } from './PreferencesService'
import { getPreferencesService } from './PreferencesService'
import { isPresetAssistant } from '../config/PresetAssistants'
import { getAppUiState, setAppUiStateValue } from '../state/AppUiState'
import { getAppSettingsStore, AppSettingsStore } from '../state/AppSettingsStore'
import { getDatabaseService, DatabaseService } from './DatabaseService'

export class AssistantRuntimeConfig {
  assistantId: string = DEFAULT_ASSISTANT_ID
  systemPrompt: string = ''
  temperatureEnabled: boolean = false
  temperature: number = 0.7
  topPEnabled: boolean = false
  topP: number = 1.0
  presencePenaltyEnabled: boolean = false
  presencePenalty: number = 0
  frequencyPenaltyEnabled: boolean = false
  frequencyPenalty: number = 0
  contextMessageCount: number = 0
  // 最大输出 token 数。0 = "无限制"(不下发字段,Anthropic 兜底 64_000),>0 = 显式下发该值。
  // 详见 Assistant.maxOutputTokens 注释。
  maxOutputTokens: number = 0
  enabledToolIds: string[] = []
  // 推理级别(per-assistant)。默认 OFF;切助手时 ChatPage 读取该字段。
  reasoningLevel: ReasoningLevel = ReasoningLevel.OFF
}

/**
 * Assistant 视图模型：对外公开 API 保持不变，作为 AppSettingsStore 的 facade。
 *
 * 拆分原则与 ProviderViewModel 一致：
 * - 持久化 / 内存态 / currentAssistantId 同步 → AppSettingsStore 统一管理
 * - 数据规整（normalizeAssistant）、头像变更推断、session list 刷新脉冲 → 留在本服务
 *
 * 保留的脉冲字段（订阅端暂不改造）：
 * - SESSION_LIST_REFRESH_AT：任何 assistant 写操作后打一次时间戳，让首页会话列表刷新
 * - ASSISTANT_AVATAR_REFRESH_AT：avatarSymbol 或 color 变更时触发，让 avatar cache 失效
 */
export class AssistantService {
  private static instance: AssistantService | null = null
  private store: AppSettingsStore
  private db: DatabaseService

  private constructor() {
    this.store = getAppSettingsStore()
    this.db = getDatabaseService()
  }

  static getInstance(): AssistantService {
    if (AssistantService.instance === null) {
      AssistantService.instance = new AssistantService()
    }
    return AssistantService.instance
  }

  /**
   * 应用启动时调用，保证 assistants 列表和 currentAssistantId 都被加载到内存，
   * 并把当前 id 校正到一个在 DB 里实际存在的 assistant（若当前引用已失效则回落默认）
   */
  async initialize(): Promise<void> {
    await this.store.ensureAssistantsInitialized()
    await this.ensureValidCurrentAssistant()
    await this.migrateLegacyReasoningPreferenceIfNeeded()
  }

  /**
   * 一次性迁移：把旧全局 CHAT_REASONING_LEVEL 写入默认助手(小星老师)的 reasoningLevel,
   * 然后删全局 key,避免双源。仅当默认助手当前 reasoningLevel 仍为默认 OFF 时迁移;
   * 已经手动设过(非 OFF)的默认助手保持不动。
   */
  private async migrateLegacyReasoningPreferenceIfNeeded(): Promise<void> {
    try {
      const preferencesService = getPreferencesService()
      const legacyLevel = await preferencesService.getString(PreferenceKeys.CHAT_REASONING_LEVEL, '')
      if (legacyLevel === '') {
        return
      }
      const normalized = this.normalizeReasoningLevelString(legacyLevel)
      const defaultAssistant = this.store.getAssistantById(DEFAULT_ASSISTANT_ID)
      if (defaultAssistant !== null && defaultAssistant.reasoningLevel === ReasoningLevel.OFF) {
        defaultAssistant.reasoningLevel = normalized
        defaultAssistant.updatedAt = Date.now()
        await this.store.upsertAssistant(defaultAssistant, false)
        console.info('AssistantService',
          `Migrated legacy CHAT_REASONING_LEVEL=${legacyLevel} -> default assistant reasoningLevel=${normalized}`)
      }
      await preferencesService.remove(PreferenceKeys.CHAT_REASONING_LEVEL)
    } catch (error) {
      console.error('AssistantService',
        `migrateLegacyReasoningPreferenceIfNeeded failed: ${JSON.stringify(error)}`)
    }
  }

  private normalizeReasoningLevelString(value: string): ReasoningLevel {
    const lower = value.trim().toLowerCase()
    if (lower === ReasoningLevel.AUTO) {
      return ReasoningLevel.AUTO
    }
    if (lower === ReasoningLevel.LOW) {
      return ReasoningLevel.LOW
    }
    if (lower === ReasoningLevel.MEDIUM) {
      return ReasoningLevel.MEDIUM
    }
    if (lower === ReasoningLevel.HIGH) {
      return ReasoningLevel.HIGH
    }
    if (lower === ReasoningLevel.XHIGH) {
      return ReasoningLevel.XHIGH
    }
    return ReasoningLevel.OFF
  }

  // ============================================================================
  // 数据规整 & UI 脉冲 helpers
  // ============================================================================

  private normalizeAssistant(assistant: Assistant): Assistant {
    assistant.name = assistant.name.trim() !== '' ? assistant.name.trim() : '未命名助手'
    assistant.avatarSymbol = assistant.avatarSymbol.trim() !== '' ? assistant.avatarSymbol.trim() : 'AI'
    assistant.color = assistant.color.trim() !== '' ? assistant.color.trim() : DEFAULT_PRIMARY_COLOR
    if (assistant.id === DEFAULT_ASSISTANT_ID) {
      assistant.isDefault = true
      // 锁定系统提示词和工具白名单：默认助手（小星老师）的值不可被覆盖
      assistant.systemPrompt = DEFAULT_ASSISTANT_SYSTEM_PROMPT
      assistant.enabledToolIds = [...DEFAULT_ASSISTANT_LOCKED_TOOL_IDS]
    }
    if (assistant.temperature < 0) {
      assistant.temperature = 0
    } else if (assistant.temperature > 2) {
      assistant.temperature = 2
    }
    return assistant
  }

  private notifyAssistantAvatarChanged(): void {
    const current = getAppUiState().assistantAvatarRefreshAt
    const now = Date.now()
    setAppUiStateValue(AppStorageKeys.ASSISTANT_AVATAR_REFRESH_AT, now > current ? now : current + 1)
  }

  // 助手保存/创建后通知 ChatPage 等订阅方重新读取 enabledToolIds / reasoningLevel。
  // 与 avatar 脉冲并行触发,但走不同 key,避免 avatar 未变时漏触发 runtime 重读。
  private notifyAssistantRuntimeChanged(): void {
    const current = getAppUiState().assistantRuntimeRefreshAt
    const now = Date.now()
    setAppUiStateValue(AppStorageKeys.ASSISTANT_RUNTIME_REFRESH_AT, now > current ? now : current + 1)
  }

  private hasAvatarPresentationChanged(previous: Assistant | null, next: Assistant): boolean {
    if (previous === null) {
      return true
    }
    return previous.avatarSymbol !== next.avatarSymbol || previous.color !== next.color
  }

  private pulseSessionList(): void {
    setAppUiStateValue(AppStorageKeys.SESSION_LIST_REFRESH_AT, Date.now())
  }

  // ============================================================================
  // 查询（内存优先，必要时 ensure）
  // ============================================================================

  async getAllAssistants(): Promise<Assistant[]> {
    await this.store.ensureAssistantsInitialized()
    return this.store.getAssistants()
  }

  async getAssistant(assistantId: string): Promise<Assistant | null> {
    await this.store.ensureAssistantsInitialized()
    const id = assistantId.trim() !== '' ? assistantId.trim() : DEFAULT_ASSISTANT_ID
    const cached = this.store.getAssistantById(id)
    if (cached !== null) {
      return cached
    }
    // 降级：如果内存里没有（可能是外部直写 DB），走一次回源
    return await this.store.getAssistantByIdAsync(id)
  }

  async getCurrentAssistantId(): Promise<string> {
    await this.store.ensureAssistantsInitialized()
    const id = this.store.getCurrentAssistantIdInMemory()
    return id.trim() !== '' ? id.trim() : DEFAULT_ASSISTANT_ID
  }

  async getCurrentAssistant(): Promise<Assistant> {
    await this.store.ensureAssistantsInitialized()
    const assistantId = await this.getCurrentAssistantId()
    const assistant = this.store.getAssistantById(assistantId)
    if (assistant !== null) {
      return assistant
    }
    // 当前 id 失效：回落默认，并把 Preferences 修正
    await this.store.setCurrentAssistantIdPersisted(DEFAULT_ASSISTANT_ID)
    const fallback = this.store.getAssistantById(DEFAULT_ASSISTANT_ID)
    if (fallback !== null) {
      return fallback
    }
    const all = this.store.getAssistants()
    return all.length > 0 ? all[0] : new Assistant(DEFAULT_ASSISTANT_ID, '小星老师')
  }

  /**
   * 专门给“发起新会话”用：跟 getCurrentAssistant 的主体一致，
   * 但额外会把兜底选择写回 Preferences，保证下次进入 new chat 时状态一致
   */
  async getCurrentAssistantForNewChat(): Promise<Assistant> {
    await this.store.ensureAssistantsInitialized()
    const assistantId = await this.getCurrentAssistantId()
    const assistant = this.store.getAssistantById(assistantId)
    if (assistant !== null) {
      return assistant
    }
    const fallback = this.store.getAssistantById(DEFAULT_ASSISTANT_ID)
    if (fallback !== null) {
      await this.store.setCurrentAssistantIdPersisted(fallback.id)
      return fallback
    }
    const all = this.store.getAssistants()
    if (all.length > 0) {
      await this.store.setCurrentAssistantIdPersisted(all[0].id)
      return all[0]
    }
    return new Assistant(DEFAULT_ASSISTANT_ID, '小星老师')
  }

  async ensureValidCurrentAssistant(): Promise<Assistant> {
    await this.store.ensureAssistantsInitialized()
    const currentId = this.store.getCurrentAssistantIdInMemory()
    const assistant = this.store.getAssistantById(currentId)
    if (assistant !== null) {
      return assistant
    }
    await this.store.setCurrentAssistantIdPersisted(DEFAULT_ASSISTANT_ID)
    const fallback = this.store.getAssistantById(DEFAULT_ASSISTANT_ID)
    if (fallback !== null) {
      return fallback
    }
    const all = this.store.getAssistants()
    return all.length > 0 ? all[0] : new Assistant(DEFAULT_ASSISTANT_ID, '小星老师')
  }

  /**
   * 把当前助手 id 切到目标 id。如果目标 id 在 DB/缓存里不存在则回落到 DEFAULT，
   * 再从回落后的状态读出 Assistant 返回（保证返回值可用）
   */
  async setCurrentAssistantId(assistantId: string): Promise<Assistant> {
    await this.store.ensureAssistantsInitialized()
    const id = assistantId.trim() !== '' ? assistantId.trim() : DEFAULT_ASSISTANT_ID
    const candidate = this.store.getAssistantById(id)
    const effectiveAssistant = candidate !== null ? candidate : await this.getCurrentAssistant()
    const effectiveId = candidate !== null ? id : DEFAULT_ASSISTANT_ID
    await this.store.setCurrentAssistantIdPersisted(effectiveId)
    this.pulseSessionList()
    return effectiveAssistant
  }

  // ============================================================================
  // 写操作
  // ============================================================================

  async createAssistant(assistant: Assistant): Promise<Assistant> {
    await this.store.ensureAssistantsInitialized()
    this.normalizeAssistant(assistant)
    if (assistant.id === '') {
      assistant.id = `assistant_${Date.now()}_${Math.random().toString(36).substring(2, 8)}`
    }
    await this.store.upsertAssistant(assistant, true)
    this.pulseSessionList()
    this.notifyAssistantAvatarChanged()
    return assistant
  }

  async saveAssistant(assistant: Assistant): Promise<void> {
    await this.store.ensureAssistantsInitialized()
    this.normalizeAssistant(assistant)
    const previous = this.store.getAssistantById(assistant.id)
    const avatarChanged = this.hasAvatarPresentationChanged(previous, assistant)
    await this.store.upsertAssistant(assistant, false)
    this.pulseSessionList()
    if (avatarChanged) {
      this.notifyAssistantAvatarChanged()
    }
    this.notifyAssistantRuntimeChanged()
  }

  async reorderAssistants(assistants: Assistant[]): Promise<void> {
    if (assistants.length === 0) {
      return
    }
    await this.store.ensureAssistantsInitialized()
    await this.store.reorderAssistants(assistants)
    this.pulseSessionList()
  }

  async deleteAssistant(assistantId: string): Promise<boolean> {
    if (assistantId === DEFAULT_ASSISTANT_ID || isPresetAssistant(assistantId)) {
      return false
    }
    await this.store.ensureAssistantsInitialized()
    const deleted = await this.store.removeAssistant(assistantId)
    if (deleted) {
      const currentId = this.store.getCurrentAssistantIdInMemory()
      if (currentId === assistantId) {
        await this.store.setCurrentAssistantIdPersisted(DEFAULT_ASSISTANT_ID)
      }
      this.pulseSessionList()
    }
    return deleted
  }

  /**
   * 某助手关联的会话数。跟 assistant 本身无缓存关系，直接透传 DB
   */
  async getAssistantSessionCount(assistantId: string): Promise<number> {
    return await this.db.getAssistantSessionCount(assistantId)
  }

  // ============================================================================
  // 派生配置
  // ============================================================================

  async getRuntimeConfig(assistantId: string): Promise<AssistantRuntimeConfig> {
    await this.store.ensureAssistantsInitialized()
    const config = new AssistantRuntimeConfig()
    const id = assistantId.trim() !== '' ? assistantId.trim() : DEFAULT_ASSISTANT_ID
    let assistant = this.store.getAssistantById(id)
    if (assistant === null) {
      assistant = this.store.getAssistantById(DEFAULT_ASSISTANT_ID)
    }
    if (assistant === null) {
      return config
    }
    config.assistantId = assistant.id
    config.systemPrompt = assistant.systemPrompt.trim()
    config.temperatureEnabled = assistant.temperatureEnabled
    config.temperature = assistant.temperature
    config.topPEnabled = assistant.topPEnabled
    config.topP = assistant.topP
    config.presencePenaltyEnabled = assistant.presencePenaltyEnabled
    config.presencePenalty = assistant.presencePenalty
    config.frequencyPenaltyEnabled = assistant.frequencyPenaltyEnabled
    config.frequencyPenalty = assistant.frequencyPenalty
    config.contextMessageCount = assistant.contextMessageCount
    config.maxOutputTokens = assistant.maxOutputTokens
    config.enabledToolIds = assistant.enabledToolIds.slice()
    config.reasoningLevel = assistant.reasoningLevel
    return config
  }

  combineSystemPrompts(globalPrompt: string, assistantPrompt: string): string {
    const parts: string[] = []
    if (globalPrompt.trim() !== '') {
      parts.push(globalPrompt.trim())
    }
    if (assistantPrompt.trim() !== '') {
      parts.push(assistantPrompt.trim())
    }
    return parts.join('\n\n')
  }
}

export function getAssistantService(): AssistantService {
  return AssistantService.getInstance()
}
