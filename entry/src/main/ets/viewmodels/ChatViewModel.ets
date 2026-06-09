import { getDatabaseService, DatabaseService } from '../services/DatabaseService'
import { MessagePart, MessagePartKind, ToolPartStatus } from '../models/MessageParts'
import { createToolPart, ensureMessageParts } from '../utils/ChatMessagePartsHelper'
import { getEffectiveCapabilities } from '../utils/ModelCapabilityDeriver'
import {
  getAIApiService,
  AIApiService,
  AIApiConfig,
  RequestMessage,
  ToolCallDelta,
  BuiltInResponsesToolSpec,
  HostedResponsesToolEvent,
  HostedResponsesToolEventKind,
  AIGeneratedImageFileCallbacks,
  OpenAIResponsesToolChoice
} from '../services/AIApiService'
import { getAppStateManager, AppStateManager } from './AppStateManager'
import { getAITaskService, AITaskService } from '../services/AITaskService'
import { getAttachmentStorageService, AttachmentStorageService } from '../services/AttachmentStorageService'
import { getToolExecutionService, ToolExecutionService, ToolExecutionContext, isCancelledToolResult, CancelledToolResultInfo } from '../services/ToolExecutionService'
import { getProviderViewModel, ProviderViewModel } from './ProviderViewModel'
import { getAssistantService, AssistantService, AssistantRuntimeConfig } from '../services/AssistantService'
import { DEFAULT_ASSISTANT_ID } from '../models/AssistantModels'
import { getLessonPlanningService } from '../services/LessonPlanningService'
import {
  renderDailyPlanSection,
  renderYesterdaySummarySection
} from '../utils/LessonPlanPromptUtils'
import { ChatMessage, ChatSession, MessageRole, ProviderType, ApiStyle, MessageAttachment, AttachmentType, ReasoningLevel, ToolDefinition, ToolCall, ToolResult, SearchReference, OpenAITransport, ToolSourceType, ToolPermissionLevel } from '../models/ChatModels'
import { AIGeneratedImageFileResult, AIGeneratedImageFileSink } from '../models/AIGeneratedImageFileModels'
import { WebSearchResult, SearchResult } from '../services/WebSearchService'
import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { getEffectiveApiKey } from '../config/PresetProviders'
import { getPreferencesService } from '../services/PreferencesService'
import { PreferenceKeys } from '../services/PreferencesService'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { setAppUiStateValue } from '../state/AppUiState'
import { ChatSessionStore } from './ChatSessionStore'
import { createThrottle, StreamFlusher } from '../utils/ThrottleUtil'
import { TypewriterFlusher } from '../utils/DisplaySyncTypewriter'
import { UIContext } from '@kit.ArkUI'
import {
  buildCurrentTimeContext,
  renderSystemPromptTemplate,
  SystemPromptTemplateDefaults
} from '../utils/SystemPromptTemplateUtils'
import {
  cleanSearchQuery as cleanSearchQueryShared,
  normalizeRelativeTimeForSearchQuery as normalizeRelativeTimeForSearchQueryShared
} from '../utils/SearchQueryUtils'
import {
  isScrapeWebFunctionName,
  isAskUserFunctionName,
  isSearchToolFunctionName
} from '../utils/SearchToolIdentityUtils'

// 标题生成状态
export interface TitleGenerationCallbacks {
  onTitleUpdated?: (title: string) => void
  onTitleGenerating?: (isGenerating: boolean) => void
  onTitleFailed?: () => void
}

// 工具调用回调
export interface ToolCallCallbacks {
  onToolCallStarted?: (toolCalls: ToolCall[]) => void
  onToolCallCompleted?: (results: ToolResult[]) => void
  onSearching?: (query: string) => void
}

// 单轮 streamChat 完成时回传的结果, 让外层 while 循环决定继续/终结/报错
interface ToolStreamRoundOutcome {
  toolCalls: ToolCall[]
  toolContinuationContent: string
  toolContinuationReasoningContent: string
  hasError: boolean
  error: string
}

// 搜索工具参数接口
interface WebSearchArgs {
  query?: string
  url?: string
}

// 搜索结果数据接口
interface SearchResultItem {
  title: string
  url: string
  snippet: string
}

interface SearchResultData {
  query: string
  searchEngine: string
  results: SearchResultItem[]
  summary: string
}

// 待持久化 AI 消息信息（每请求独立）
interface PendingAIMessageInfo {
  message: ChatMessage
  sessionId: string
  persisted: boolean
}

// 活跃请求信息（每请求独立，用于 stopGeneration 时取消）
interface ActiveRequestInfo {
  httpRequest: http.HttpRequest
  cancelCallback: () => void
  sessionId: string
}

interface ImageDownloadResult {
  base64Data: string
  mimeType: string
}

const OPENAI_RESPONSES_PART_SOURCE = 'openai_responses'
const OPENAI_RESPONSES_WEB_SEARCH_LABEL = 'OpenAI Web Search'
const OPENAI_RESPONSES_IMAGE_GENERATION_LABEL = 'OpenAI Image Generation'
const OPENAI_RESPONSES_WEB_SEARCH_PREFIX = 'hws'
const OPENAI_RESPONSES_IMAGE_GENERATION_PREFIX = 'hig'
const OPENAI_RESPONSES_TOOL_SEQUENCE_OFFSET = 0
const OPENAI_RESPONSES_IMAGE_SEQUENCE_OFFSET = 1

// 每次请求保留的历史消息上限（最近 N 条）。超过部分丢弃。
// 设计动机：长会话的 token 浪费在用户已经忘记的旧对话上，截断到最近 30 条
// 既能保留上下文连贯性，又能显著降低 prompt token 与首字延迟。
const MAX_HISTORY_MESSAGES_FOR_REQUEST: number = 30

// 聊天状态管理
export class ChatViewModel {
  private databaseService: DatabaseService
  private aiApiService: AIApiService
  private appStateManager: AppStateManager
  private aiTaskService: AITaskService
  private attachmentStorageService: AttachmentStorageService
  private toolExecutionService: ToolExecutionService
  private providerViewModel: ProviderViewModel
  private assistantService: AssistantService
  private sessionStore: ChatSessionStore

  // 当前会话
  private currentSession: ChatSession | null = null
  // 活跃请求 Map（key = requestId，支持多个并发请求）
  private activeRequests: Map<string, ActiveRequestInfo> = new Map()
  // 待持久化 AI 消息 Map（key = messageId，支持多个并发请求）
  private pendingAIMessages: Map<string, PendingAIMessageInfo> = new Map()
  // OpenAI Responses 内置搜索 in-flight 调用集合 (key = aiMessage.id, value = 当前未结束的 item.id 集合)。
  // OpenAI 在一次会话里会自主触发多轮 web_search, 用计数器去抖避免 isSearching 在卡片上反复 true/false 闪烁。
  private inflightHostedSearchCalls: Map<string, Set<string>> = new Map()
  // hosted web_search open_page action (模型读取具体 URL, 区别于 search query) 的 itemId 记忆集合。
  // open_page 在用户感知里更像 reasoning 段内部的"参考 URL", 而非独立"搜索步骤";
  // 命中即 (a) 不创建独立 hws_ part (b) 不入 inflight (c) 不封口当前 reasoning,
  // 让 reasoning 不被 open_page 切断。STARTED 阶段拿到 url 入集合, SEARCHING/COMPLETED 阶段查集合走快速 return。
  private openPageHostedItemIds: Map<string, Set<string>> = new Map()
  // hosted image_generation_call 同样按 aiMessage.id -> Set<itemKey> 去抖,
  // 让多张图生成时 parts 上每张图各占一条 timeline 记录, 也避免重复 emit started 时 part 反复重建。
  private inflightHostedImageGenCalls: Map<string, Set<string>> = new Map()
  // 标题生成回调
  private titleCallbacks: TitleGenerationCallbacks | null = null
  // 最大重试次数
  private readonly MAX_TITLE_RETRY = 3
  // 最大工具步骤数，仅作为防无限循环兜底，不限制单个工具的调用次数
  private readonly MAX_TOOL_STEPS = 256
  // 取消令牌：用于停止”尚未开始发送的请求”（例如退出页面时）
  private cancelToken: number = 0
  // V2 流式渲染: 由 ChatPage 在 aboutToAppear 时通过 setStreamingUIContext 注入
  // DisplaySyncTypewriter.start() 必须包在 UIContext.runScopedTask 内, 所以 ChatViewModel 自己拿不到 ctx
  // 拿不到 ctx 时 createStreamFlusher 自动降级到 createThrottle(150), 保证兜底可用
  private streamingUIContext: UIContext | null = null

  setStreamingUIContext(uiContext: UIContext | null): void {
    this.streamingUIContext = uiContext
  }

  private createStreamFlusher(): StreamFlusher {
    if (this.streamingUIContext !== null) {
      return new TypewriterFlusher(this.streamingUIContext)
    }
    return createThrottle(150)
  }

  private resetStreamFlushers(
    localFirstChunkThrottle: StreamFlusher,
    localContentThrottle: StreamFlusher,
    localReasoningThrottle: StreamFlusher
  ): void {
    localFirstChunkThrottle.reset()
    if (localContentThrottle !== localFirstChunkThrottle) {
      localContentThrottle.reset()
    }
    localReasoningThrottle.reset()
  }

  private throttleStreamContentChunk(
    contentChunk: string,
    localFirstChunkThrottle: StreamFlusher,
    localContentThrottle: StreamFlusher,
    getHasReceivedFirstChunk: () => boolean,
    setHasReceivedFirstChunk: (value: boolean) => void,
    shouldSkip: () => boolean,
    appendContent: (content: string) => void
  ): void {
    if (shouldSkip()) {
      return
    }
    const isFirstChunk = !getHasReceivedFirstChunk()
    const flusher = isFirstChunk ? localFirstChunkThrottle : localContentThrottle
    flusher.throttle(contentChunk, (throttledContent: string) => {
      if (shouldSkip()) {
        return
      }
      appendContent(throttledContent)
      if (isFirstChunk) {
        setHasReceivedFirstChunk(true)
      }
    })
  }

  private flushStreamContentFlushers(
    localFirstChunkThrottle: StreamFlusher,
    localContentThrottle: StreamFlusher,
    shouldSkip: () => boolean,
    appendContent: (content: string) => void
  ): void {
    localFirstChunkThrottle.flush((throttledContent: string) => {
      if (shouldSkip()) {
        return
      }
      appendContent(throttledContent)
    })
    if (localContentThrottle === localFirstChunkThrottle) {
      return
    }
    localContentThrottle.flush((throttledContent: string) => {
      if (shouldSkip()) {
        return
      }
      appendContent(throttledContent)
    })
  }

  constructor() {
    this.databaseService = getDatabaseService()
    this.aiApiService = getAIApiService()
    this.appStateManager = getAppStateManager()
    this.aiTaskService = getAITaskService()
    this.attachmentStorageService = getAttachmentStorageService()
    this.toolExecutionService = getToolExecutionService()
    this.providerViewModel = getProviderViewModel()
    this.assistantService = getAssistantService()
    this.sessionStore = new ChatSessionStore(
      this.databaseService,
      this.appStateManager,
      () => this.generateId(),
      () => this.notifySessionListChanged()
    )
  }

	  private async getRenderedSystemPrompt(): Promise<string> {
	    const prefsService = getPreferencesService()
	    const enabled = await prefsService.getBoolean(PreferenceKeys.SYSTEM_PROMPT_ENABLED, true)
    if (!enabled) {
      return ''
    }
    const template = await prefsService.getString(
      PreferenceKeys.CUSTOM_SYSTEM_PROMPT,
      SystemPromptTemplateDefaults.DEFAULT_TEMPLATE
	    )
	    return renderSystemPromptTemplate(template)
	  }

	  private getCurrentAssistantIdForRequest(): string {
	    const session = this.sessionStore.getCurrentSession()
	    if (session !== null && session.assistantId !== '') {
	      return session.assistantId
	    }
	    return 'default'
	  }

	  private async getAssistantRuntimeConfig(): Promise<AssistantRuntimeConfig> {
	    return await this.assistantService.getRuntimeConfig(this.getCurrentAssistantIdForRequest())
	  }

	  // 当前助手的工具白名单。空数组 = 不设边界(继承全局);非空 = 仅这些 toolId 可用。
	  // 用于运行时收窄 enabledToolIds(搜索工具走独立通道,不受此影响)。
	  async getCurrentAssistantEnabledToolIds(): Promise<string[]> {
	    const config = await this.getAssistantRuntimeConfig()
	    return config.enabledToolIds.slice()
	  }

	  // 当前助手的推理级别。取代旧的全局 CHAT_REASONING_LEVEL 偏好。
	  // 默认 OFF。ChatPage 在切助手/保存助手后调此方法拿最新值,不再自己维护 @Local 状态。
	  async getCurrentAssistantReasoningLevel(): Promise<ReasoningLevel> {
	    const config = await this.getAssistantRuntimeConfig()
	    return config.reasoningLevel
	  }

	  private async buildRequestSystemPrompt(extraPrompt: string = ''): Promise<string> {
	    let globalPrompt = ''
	    const assistantConfig = await this.getAssistantRuntimeConfig()
      if (assistantConfig.assistantId !== DEFAULT_ASSISTANT_ID) {
        globalPrompt = await this.getRenderedSystemPrompt()
      }
	    const basePrompt = this.assistantService.combineSystemPrompts(globalPrompt, assistantConfig.systemPrompt)
	    const withExtra = this.assistantService.combineSystemPrompts(basePrompt, extraPrompt)
	    // 动态教学计划注入：仅当助手是小星老师时生效（其他助手保持原 prompt 纯净）
	    if (assistantConfig.assistantId !== DEFAULT_ASSISTANT_ID) {
	      return withExtra
	    }
	    return await this.injectDailyPlanSections(withExtra)
	  }

	  /**
	   * 把"今日教学目标"和"昨日小结"section 拼到小星老师 system prompt 末尾。
	   * - 仅当今日/昨日 plan 存在且 status='done' 时才注入
	   * - plan 缺失时静默降级,不报错
	   */
	  private async injectDailyPlanSections(basePrompt: string): Promise<string> {
	    try {
	      const planner = getLessonPlanningService()
	      const today = await planner.getTodayPlan()
	      const yesterday = await planner.getYesterdaySummary()
	      let composed = basePrompt
	      if (today !== null) {
	        const planDate = today.plan.planDate
	        const weekday = this.weekdayLabel(planDate)
	        const section = renderDailyPlanSection(today.plan, planDate, weekday)
	        if (section !== '') {
	          composed = this.assistantService.combineSystemPrompts(composed, section)
	        }
	      }
	      if (yesterday !== null) {
	        const planDate = yesterday.plan.planDate
	        const section = renderYesterdaySummarySection(yesterday.plan, planDate)
	        if (section !== '') {
	          composed = this.assistantService.combineSystemPrompts(composed, section)
	        }
	      }
	      return composed
	    } catch (error) {
	      console.error('ChatViewModel', `injectDailyPlanSections failed: ${JSON.stringify(error)}`)
	      return basePrompt
	    }
	  }

	  /**
	   * 把 'YYYY-MM-DD' 转成 "星期X" 标签
	   */
	  private weekdayLabel(ymd: string): string {
	    if (ymd === '') {
	      return ''
	    }
	    const parts = ymd.split('-')
	    if (parts.length !== 3) {
	      return ''
	    }
	    const year = parseInt(parts[0], 10)
	    const month = parseInt(parts[1], 10) - 1
	    const day = parseInt(parts[2], 10)
	    if (isNaN(year) || isNaN(month) || isNaN(day)) {
	      return ''
	    }
	    const d = new Date(year, month, day)
	    const labels = ['日', '一', '二', '三', '四', '五', '六']
	    const idx = d.getDay()
	    if (idx < 0 || idx > 6) {
	      return ''
	    }
	    return labels[idx]
	  }

	  private async getRequestTemperature(): Promise<number | undefined> {
	    const assistantConfig = await this.getAssistantRuntimeConfig()
	    if (assistantConfig.temperatureEnabled) {
	      return assistantConfig.temperature
	    }
	    return undefined
	  }

	  // 助手未启用相应开关时返回 undefined,让 AIApiService 不下发对应采样参数。
	  // 显式打开覆盖时即使是 1.0 / 0 这类默认值也保留用户意图。
	  private async getRequestTopP(): Promise<number | undefined> {
	    const assistantConfig = await this.getAssistantRuntimeConfig()
	    return assistantConfig.topPEnabled ? assistantConfig.topP : undefined
	  }

	  private async getRequestPresencePenalty(): Promise<number | undefined> {
	    const assistantConfig = await this.getAssistantRuntimeConfig()
	    return assistantConfig.presencePenaltyEnabled ? assistantConfig.presencePenalty : undefined
	  }

	  private async getRequestFrequencyPenalty(): Promise<number | undefined> {
	    const assistantConfig = await this.getAssistantRuntimeConfig()
	    return assistantConfig.frequencyPenaltyEnabled ? assistantConfig.frequencyPenalty : undefined
	  }

  async getContextMessageCount(): Promise<number> {
    const config = await this.getAssistantRuntimeConfig()
    return config.contextMessageCount
  }

  async getMaxOutputTokens(): Promise<number> {
    const config = await this.getAssistantRuntimeConfig()
    return config.maxOutputTokens
  }

  // 解析"本次请求要发的 max output tokens", 0 / undefined 一律返回 undefined,
  // 让 AIApiService 在各 provider 路径里决定是否下发字段(只有 Claude 必传时会兜底 64_000)。
  // override 优先于助手配置, 用于 sendMessage 这种从 ChatSendFlow 传入显式覆盖值的入口。
  private async resolveEffectiveMaxOutputTokens(override?: number): Promise<number | undefined> {
    if (override !== undefined && override > 0) {
      return override
    }
    const fromAssistant = await this.getMaxOutputTokens()
    return fromAssistant > 0 ? fromAssistant : undefined
  }

  private notifySessionListChanged(): void {
    setAppUiStateValue(AppStorageKeys.SESSION_LIST_REFRESH_AT, Date.now())
  }

  private cloneAttachments(attachments: MessageAttachment[]): MessageAttachment[] {
    const cloned: MessageAttachment[] = []
    for (let i = 0; i < attachments.length; i++) {
      const attachment = new MessageAttachment(
        attachments[i].id,
        attachments[i].type,
        attachments[i].name,
        attachments[i].filePath,
        attachments[i].mimeType,
        attachments[i].size
      )
      attachment.base64Data = attachments[i].base64Data
      attachment.processState = attachments[i].processState
      attachment.parseEngine = attachments[i].parseEngine
      attachment.parsedText = attachments[i].parsedText
      attachment.parseError = attachments[i].parseError
      cloned.push(attachment)
    }
    return cloned
  }

  private cloneAttachmentsForStoredMessage(attachments: MessageAttachment[]): MessageAttachment[] {
    const cloned = this.cloneAttachments(attachments)
    for (let i = 0; i < cloned.length; i++) {
      if (cloned[i].filePath !== '') {
        cloned[i].base64Data = ''
      }
    }
    return cloned
  }

  private cloneAttachmentsForRequestHistory(
    attachments: MessageAttachment[],
    includeAttachmentPayloads: boolean
  ): MessageAttachment[] {
    const cloned = this.cloneAttachments(attachments)
    if (includeAttachmentPayloads) {
      return cloned
    }
    for (let i = 0; i < cloned.length; i++) {
      cloned[i].base64Data = ''
      cloned[i].parsedText = ''
    }
    return cloned
  }

  private async ensureAttachmentBase64Data(attachment: MessageAttachment): Promise<boolean> {
    if (attachment.parsedText !== '') {
      return true
    }
    if (attachment.base64Data !== '') {
      return true
    }
    if (attachment.filePath === '') {
      console.warn('ChatViewModel', `Attachment missing file path: ${attachment.id}`)
      return false
    }
    try {
      const base64Data = await this.attachmentStorageService.readAsBase64(attachment.filePath)
      if (base64Data === '') {
        console.warn('ChatViewModel', `Attachment base64 empty after read: ${attachment.id}`)
        return false
      }
      attachment.base64Data = base64Data
      console.info('ChatViewModel', `Prepared attachment for request: ${attachment.id}`)
      return true
    } catch (error) {
      console.error('ChatViewModel', `Failed to prepare attachment ${attachment.id}: ${JSON.stringify(error)}`)
      return false
    }
  }

  private async prepareOutgoingAttachments(attachments: MessageAttachment[]): Promise<MessageAttachment[]> {
    const clonedAttachments = this.cloneAttachments(attachments)
    for (let i = 0; i < clonedAttachments.length; i++) {
      await this.ensureAttachmentBase64Data(clonedAttachments[i])
    }
    return clonedAttachments
  }

  private buildDraftTitle(content: string): string {
    const normalized = content.replace(/\s+/g, ' ').trim()
    if (normalized.length === 0) {
      return '新对话'
    }
    if (normalized.length <= 20) {
      return normalized
    }
    return normalized.substring(0, 20) + '...'
  }

  private buildDraftPreview(content: string, attachments: MessageAttachment[]): string {
    const normalized = content.replace(/\s+/g, ' ').trim()
    if (normalized !== '') {
      if (normalized.length <= 48) {
        return normalized
      }
      return normalized.substring(0, 48) + '...'
    }
    if (attachments.length === 0) {
      return ''
    }
    return attachments[0].name !== '' ? attachments[0].name : ''
  }

  private isFirstRoundSession(session: ChatSession | null): boolean {
    return session !== null && session.messages.length === 0
  }

  private appendMessageToSessionIfMissing(session: ChatSession | null, message: ChatMessage): void {
    if (session === null) {
      return
    }
    for (let i = 0; i < session.messages.length; i++) {
      if (session.messages[i].id === message.id) {
        return
      }
    }
    session.messages.push(message)
    if (session.messageCount < session.messages.length) {
      session.messageCount = session.messages.length
      return
    }
    session.messageCount = session.messageCount + 1
  }

  private mergePendingAIMessagesIntoMessages(sessionId: string, messages: ChatMessage[]): ChatMessage[] {
    this.pendingAIMessages.forEach((info: PendingAIMessageInfo) => {
      if (info.sessionId !== sessionId) {
        return
      }
      let exists = false
      for (let i = 0; i < messages.length; i++) {
        if (messages[i].id === info.message.id) {
          exists = true
          break
        }
      }
      if (!exists) {
        messages.push(info.message)
      }
    })
    return messages
  }

  private finalizeLoadedSession(sessionId: string, session: ChatSession | null): ChatSession | null {
    if (session === null) {
      return null
    }
    session.messages = this.mergePendingAIMessagesIntoMessages(sessionId, session.messages)
    if (session.messageCount < session.messages.length) {
      session.messageCount = session.messages.length
    }
    this.currentSession = session
    this.sessionStore.setCurrentSession(session)
    return session
  }

  private isCancelled(snapshot: number): boolean {
    return snapshot !== this.cancelToken
  }

  private addPendingAIMessage(message: ChatMessage, sessionId: string): void {
    this.pendingAIMessages.set(message.id, {
      message: message,
      sessionId: sessionId,
      persisted: false
    } as PendingAIMessageInfo)
  }

  private clearPendingAIMessageIfMatches(messageId: string): void {
    this.pendingAIMessages.delete(messageId)
    // hosted 搜索去抖集合在请求结束时一并释放, 避免泄漏
    this.inflightHostedSearchCalls.delete(messageId)
    this.openPageHostedItemIds.delete(messageId)
    this.inflightHostedImageGenCalls.delete(messageId)
  }

  private markPendingAIMessagePersisted(messageId: string): void {
    const info = this.pendingAIMessages.get(messageId)
    if (info !== undefined) {
      info.persisted = true
    }
  }

  // 当 AI 消息内容完全为空时，填充一条兜底提示，避免出现空气泡
  private fillEmptyAIContentPlaceholder(aiMessage: ChatMessage, errorHint: string = ''): void {
    // 流式完成时顺便把本轮 Responses reasoning 原文持久化到消息上。
    // 对非官方 Responses 路径来说 blob 始终为空,不影响其他模型。
    this.harvestResponsesReasoningSignature(aiMessage)
    // 若本轮流式期间没 push 过 parts(例如非 function-calling 路径),按旧字段一次合成 parts,
    // 保证数据持久化和下游渲染都有一致的 parts 视图。
    this.ensurePartsBackfill(aiMessage)

    if (aiMessage.content.trim() !== '') {
      return
    }
    if (aiMessage.reasoningContent.trim() !== '') {
      return
    }
    if (aiMessage.attachments.length > 0) {
      return
    }
    if (aiMessage.toolCalls.length > 0 || aiMessage.toolResults.length > 0) {
      return
    }
    if (errorHint !== '') {
      aiMessage.content = errorHint
    } else {
      aiMessage.content = '[模型未返回内容]'
    }
  }

  // 流式完成时把 AIApiService 本轮累积的 OpenAI Responses reasoning items 持久化到消息上
  // 仅官方 Responses API + include=reasoning.encrypted_content 时 AIApiService 里才会有累积,
  // 普通 Chat Completions 拿到的始终是空串,不影响其他路径。
  private harvestResponsesReasoningSignature(aiMessage: ChatMessage): void {
    const blob = this.aiApiService.consumeLastStreamResponsesReasoningBlob()
    if (blob !== '') {
      aiMessage.reasoningSignatureBlob = blob
    }
  }

  // 按到达顺序把一段 reasoning 文本合并到 aiMessage.parts。
  // 若最后一个 part 就是尚未完成的 REASONING,则追加;否则 push 一个新的 reasoning part。
  // 这是支持 DeepSeek V4 等 thinking↔tool 交错的核心:
  // 每次出现 tool 后再回来的 reasoning 会被归为新 part, UI 可按顺序渲染。
  private pushPartReasoning(aiMessage: ChatMessage, delta: string): void {
    if (delta === '') {
      return
    }
    const last = aiMessage.parts.length > 0 ? aiMessage.parts[aiMessage.parts.length - 1] : null
    if (last !== null && last.kind === MessagePartKind.REASONING && last.reasoningFinishedAt === 0) {
      last.text = last.text + delta
      return
    }
    const part = MessagePart.reasoning(delta)
    aiMessage.parts = aiMessage.parts.concat([part])
  }

  // 追加一段 content 文本到最后一个 text part, 或新建 text part。
  // 通常只在 "已确认不会退回 buffer" 的路径上调用(直接 flush 到 aiMessage.content 时)。
  private pushPartText(aiMessage: ChatMessage, delta: string): void {
    if (delta === '') {
      return
    }
    const last = aiMessage.parts.length > 0 ? aiMessage.parts[aiMessage.parts.length - 1] : null
    if (last !== null && last.kind === MessagePartKind.TEXT) {
      last.text = last.text + delta
      return
    }
    // 切换到最终文本前, 先把未 finish 的 reasoning 段封口, 否则 UI 会一直显示 "思考中 xxx s"
    // 并在 Date.now() - reasoningCreatedAt 基础上持续累加,产生几万秒的离谱计时
    this.finishTrailingReasoningPart(aiMessage)
    const part = MessagePart.text(delta)
    aiMessage.parts = aiMessage.parts.concat([part])
  }

  // 标记当前最后一个 reasoning part 为已完成(被工具调用 / 最终文本打断),
  // 便于 UI 显示总用时并让后续新的 reasoning 独立分段。
  private finishTrailingReasoningPart(aiMessage: ChatMessage): void {
    for (let i = aiMessage.parts.length - 1; i >= 0; i--) {
      const p = aiMessage.parts[i]
      if (p.kind === MessagePartKind.REASONING) {
        if (p.reasoningFinishedAt === 0) {
          p.reasoningFinishedAt = Date.now()
        }
        return
      }
      if (p.kind === MessagePartKind.TOOL || p.kind === MessagePartKind.TEXT) {
        return
      }
    }
  }

  // 新收到一个 tool call 时向 parts 追加 ToolPart(尚无结果)
  private pushToolPart(aiMessage: ChatMessage, toolCall: ToolCall): void {
    this.finishTrailingReasoningPart(aiMessage)
    const part = createToolPart(toolCall, null)
    aiMessage.parts = aiMessage.parts.concat([part])
  }

  private insertPartBeforeActiveOutputOrAppend(aiMessage: ChatMessage, part: MessagePart): void {
    const activeOutputIndex = this.getTrailingActiveOutputIndex(aiMessage)
    if (activeOutputIndex >= 0) {
      const nextParts = aiMessage.parts.slice()
      nextParts.splice(activeOutputIndex, 0, part)
      aiMessage.parts = nextParts
      return
    }
    this.finishTrailingReasoningPart(aiMessage)
    aiMessage.parts = aiMessage.parts.concat([part])
  }

  private getTrailingActiveReasoningIndex(aiMessage: ChatMessage): number {
    if (aiMessage.parts.length === 0) {
      return -1
    }
    const lastIndex = aiMessage.parts.length - 1
    const last = aiMessage.parts[lastIndex]
    if (last.kind === MessagePartKind.REASONING && last.reasoningFinishedAt === 0) {
      return lastIndex
    }
    return -1
  }

  private getTrailingActiveOutputIndex(aiMessage: ChatMessage): number {
    const activeReasoningIndex = this.getTrailingActiveReasoningIndex(aiMessage)
    if (activeReasoningIndex >= 0) {
      return activeReasoningIndex
    }
    if (!aiMessage.isGenerating || aiMessage.parts.length === 0) {
      return -1
    }
    const lastIndex = aiMessage.parts.length - 1
    const last = aiMessage.parts[lastIndex]
    return last.kind === MessagePartKind.TEXT ? lastIndex : -1
  }

  private buildOpenAIResponsesItemKey(itemId: string, outputIndex: number): string {
    if (itemId !== '') {
      return itemId
    }
    if (outputIndex >= 0) {
      return 'idx:' + outputIndex.toString()
    }
    return 'anonymous'
  }

  private buildOpenAIResponsesHostedPartId(prefix: string, itemKey: string): string {
    return prefix + '_' + itemKey
  }

  private nextOpenAIResponsesFallbackSequence(aiMessage: ChatMessage): number {
    let maxSequence = -10
    for (let i = 0; i < aiMessage.parts.length; i++) {
      const part = aiMessage.parts[i]
      if (part.sourceType === OPENAI_RESPONSES_PART_SOURCE && part.sourceSequence > maxSequence) {
        maxSequence = part.sourceSequence
      }
    }
    return maxSequence + 10
  }

  private buildOpenAIResponsesSourceSequence(
    outputIndex: number,
    sequenceOffset: number,
    fallbackSequence: number
  ): number {
    if (outputIndex >= 0) {
      return outputIndex * 10 + sequenceOffset
    }
    return fallbackSequence + sequenceOffset
  }

  private syncOpenAIResponsesPartSource(
    part: MessagePart,
    itemKey: string,
    outputIndex: number,
    contentIndex: number,
    sequence: number
  ): boolean {
    let changed = false
    if (part.sourceType !== OPENAI_RESPONSES_PART_SOURCE) {
      part.sourceType = OPENAI_RESPONSES_PART_SOURCE
      changed = true
    }
    if (part.sourceItemId !== itemKey) {
      part.sourceItemId = itemKey
      changed = true
    }
    if (part.sourceOutputIndex !== outputIndex) {
      part.sourceOutputIndex = outputIndex
      changed = true
    }
    if (part.sourceContentIndex !== contentIndex) {
      part.sourceContentIndex = contentIndex
      changed = true
    }
    if (part.sourceSequence !== sequence) {
      part.sourceSequence = sequence
      changed = true
    }
    return changed
  }

  private insertOpenAIResponsesTimelinePart(aiMessage: ChatMessage, part: MessagePart): void {
    const insertIndex = this.findOpenAIResponsesTimelineInsertIndex(aiMessage.parts, part)
    if (insertIndex >= 0) {
      const nextParts = aiMessage.parts.slice()
      nextParts.splice(insertIndex, 0, part)
      aiMessage.parts = nextParts
      return
    }
    this.insertPartBeforeActiveOutputOrAppend(aiMessage, part)
  }

  private repositionOpenAIResponsesTimelinePart(aiMessage: ChatMessage, part: MessagePart): void {
    let currentIndex = -1
    for (let i = 0; i < aiMessage.parts.length; i++) {
      if (aiMessage.parts[i] === part) {
        currentIndex = i
        break
      }
    }
    if (currentIndex < 0) {
      return
    }
    const nextParts = aiMessage.parts.slice()
    nextParts.splice(currentIndex, 1)
    const insertIndex = this.findOpenAIResponsesTimelineInsertIndex(nextParts, part)
    if (insertIndex < 0 || insertIndex === currentIndex) {
      return
    }
    nextParts.splice(insertIndex, 0, part)
    aiMessage.parts = nextParts
  }

  private findOpenAIResponsesTimelineInsertIndex(parts: MessagePart[], incoming: MessagePart): number {
    if (incoming.sourceType !== OPENAI_RESPONSES_PART_SOURCE || incoming.sourceSequence < 0) {
      return -1
    }
    for (let i = 0; i < parts.length; i++) {
      const existing = parts[i]
      if (existing.sourceType !== OPENAI_RESPONSES_PART_SOURCE || existing.sourceSequence < 0) {
        continue
      }
      if (existing.sourceSequence > incoming.sourceSequence) {
        return i
      }
      if (existing.sourceSequence === incoming.sourceSequence &&
        existing.kind === MessagePartKind.IMAGE &&
        incoming.kind === MessagePartKind.TOOL) {
        return i
      }
    }
    return -1
  }

  private findOpenAIResponsesHostedToolPartIndex(
    aiMessage: ChatMessage,
    partId: string,
    itemKey: string,
    outputIndex: number,
    sourceLabel: string
  ): number {
    for (let i = 0; i < aiMessage.parts.length; i++) {
      const part = aiMessage.parts[i]
      if (part.kind === MessagePartKind.TOOL && part.toolCallId === partId) {
        return i
      }
    }
    for (let i = 0; i < aiMessage.parts.length; i++) {
      const part = aiMessage.parts[i]
      if (part.kind !== MessagePartKind.TOOL) {
        continue
      }
      if (part.sourceType !== OPENAI_RESPONSES_PART_SOURCE) {
        continue
      }
      if (part.sourceItemId === itemKey && part.toolSourceLabel === sourceLabel) {
        return i
      }
      if (outputIndex >= 0 && part.sourceOutputIndex === outputIndex && part.toolSourceLabel === sourceLabel) {
        return i
      }
    }
    return -1
  }

  private syncOpenAIResponsesImagePartSourceFromTool(part: MessagePart, toolPart: MessagePart): boolean {
    if (toolPart.sourceType !== OPENAI_RESPONSES_PART_SOURCE) {
      return false
    }
    const sequence = toolPart.sourceSequence >= 0 ?
      toolPart.sourceSequence + OPENAI_RESPONSES_IMAGE_SEQUENCE_OFFSET : OPENAI_RESPONSES_IMAGE_SEQUENCE_OFFSET
    return this.syncOpenAIResponsesPartSource(
      part,
      toolPart.sourceItemId,
      toolPart.sourceOutputIndex,
      -1,
      sequence
    )
  }

  private mergeToolFunctionNameFragment(previousName: string, incomingName: string): string {
    const prev = previousName.trim()
    const next = incomingName.trim()
    if (next === '') {
      return prev
    }
    if (prev === '') {
      return next
    }
    if (next.startsWith(prev)) {
      return next
    }
    if (prev.endsWith(next)) {
      return prev
    }
    return prev + next
  }

  private mergeToolArgumentsFragment(previousArgs: string, incomingArgs: string): string {
    if (incomingArgs === '') {
      return previousArgs
    }
    if (previousArgs === '') {
      return incomingArgs
    }
    // OpenAI Responses 的 arguments.done 会给完整参数；普通 Chat Completions 给增量片段。
    if (incomingArgs.startsWith(previousArgs)) {
      return incomingArgs
    }
    return previousArgs + incomingArgs
  }

  private applyToolCallDelta(toolCall: ToolCall, delta: ToolCallDelta): void {
    const incomingId = delta.id !== undefined ? delta.id.trim() : ''
    if (incomingId !== '') {
      toolCall.id = incomingId
    }

    const incomingName = delta.functionName !== undefined ? delta.functionName.trim() : ''
    if (incomingName !== '') {
      const previousName = toolCall.functionName
      const mergedName = this.mergeToolFunctionNameFragment(previousName, incomingName)
      toolCall.functionName = mergedName
      if (toolCall.toolId === '' || toolCall.toolId === previousName) {
        toolCall.toolId = mergedName
      }
      if (toolCall.displayName === '' || toolCall.displayName === previousName) {
        toolCall.displayName = mergedName
      }
    }

    const incomingArgs = delta.arguments !== undefined ? delta.arguments : ''
    if (incomingArgs !== '') {
      toolCall.arguments = this.mergeToolArgumentsFragment(toolCall.arguments, incomingArgs)
    }
  }

  private syncToolPartFromToolCall(part: MessagePart, toolCall: ToolCall): void {
    part.toolCallId = toolCall.id
    part.toolName = toolCall.functionName
    part.toolDisplayName = toolCall.displayName
    part.toolArguments = toolCall.arguments
    part.toolSourceType = toolCall.sourceType
    part.toolSourceLabel = toolCall.sourceLabel
    part.toolPermissionLevel = toolCall.permissionLevel
    part.toolApprovalReason = toolCall.approvalReason
  }

  private syncToolPartByCall(aiMessage: ChatMessage, toolCall: ToolCall): void {
    for (let i = 0; i < aiMessage.parts.length; i++) {
      const part = aiMessage.parts[i]
      if (part.kind === MessagePartKind.TOOL && part.toolCallId === toolCall.id) {
        this.syncToolPartFromToolCall(part, toolCall)
        return
      }
    }
  }

  private markToolPartRunningByCall(aiMessage: ChatMessage, toolCall: ToolCall): void {
    for (let i = 0; i < aiMessage.parts.length; i++) {
      const part = aiMessage.parts[i]
      if (part.kind !== MessagePartKind.TOOL) {
        continue
      }
      if (part.toolCallId !== toolCall.id) {
        continue
      }
      if (part.toolStatus === ToolPartStatus.PENDING) {
        part.toolStatus = ToolPartStatus.RUNNING
      }
      return
    }
  }

  // 工具结果到达时, 按 toolCallId 回写到对应 ToolPart
  private attachToolResultPart(aiMessage: ChatMessage, result: ToolResult): void {
    for (let i = 0; i < aiMessage.parts.length; i++) {
      const p = aiMessage.parts[i]
      if (p.kind === MessagePartKind.TOOL && p.toolCallId === result.toolCallId) {
        p.toolResult = result.content
        p.toolIsError = result.isError
        p.toolStatus = result.isError ? ToolPartStatus.FAILED :
          (isAskUserFunctionName(p.toolName) ? ToolPartStatus.ANSWERED : ToolPartStatus.SUCCEEDED)
        return
      }
    }
  }

  // 兜底: 流式完成时, 若 parts 仍为空但旧字段有内容, 按保守顺序(reasoning→tools→text)合成 parts。
  // 用于非 tools 路径或流式期间没有调用 push* helper 的边界情况, 保证下游 UI 可走 parts 分支。
  // 无论 parts 是否原本就有内容, 结尾统一把未 finish 的 reasoning 封口, 避免 UI 继续按 Date.now() 刷秒数
  private ensurePartsBackfill(aiMessage: ChatMessage): void {
    if (aiMessage.parts.length === 0) {
      if (aiMessage.content === '' && aiMessage.reasoningContent === '' &&
        aiMessage.toolCalls.length === 0 && aiMessage.toolResults.length === 0) {
        return
      }
      ensureMessageParts(aiMessage, false)
    }
    const now = Date.now()
    for (let i = 0; i < aiMessage.parts.length; i++) {
      const p = aiMessage.parts[i]
      if (p.kind === MessagePartKind.REASONING && p.reasoningFinishedAt === 0) {
        p.reasoningFinishedAt = now
      }
    }
  }

  private appendStreamedContent(
    aiMessage: ChatMessage,
    content: string,
    onAIMessageUpdated: (message: ChatMessage) => void
  ): void {
    if (content === '') {
      return
    }
    aiMessage.content += content
    this.pushPartText(aiMessage, content)
    onAIMessageUpdated(aiMessage)
  }

  private appendStreamedReasoning(
    aiMessage: ChatMessage,
    reasoning: string,
    onAIMessageUpdated: (message: ChatMessage) => void
  ): void {
    if (reasoning === '') {
      return
    }
    aiMessage.reasoningContent += reasoning
    this.pushPartReasoning(aiMessage, reasoning)
    onAIMessageUpdated(aiMessage)
  }

  private flushPendingReasoningBeforeContent(
    localReasoningThrottle: StreamFlusher,
    shouldSkip: () => boolean,
    aiMessage: ChatMessage,
    onAIMessageUpdated: (message: ChatMessage) => void
  ): void {
    localReasoningThrottle.flush((throttledReasoning: string) => {
      if (shouldSkip()) {
        return
      }
      this.appendStreamedReasoning(aiMessage, throttledReasoning, onAIMessageUpdated)
    })
  }

  private appendFlatRequestHistoryMessage(
    historyMessages: RequestMessage[],
    msg: ChatMessage,
    includeAttachmentPayloads: boolean
  ): void {
    const requestMessage = new RequestMessage(
      msg.role,
      msg.content,
      this.cloneAttachmentsForRequestHistory(msg.attachments, includeAttachmentPayloads)
    )
    requestMessage.reasoningContent = msg.reasoningContent
    requestMessage.reasoningSignatureBlob = msg.reasoningSignatureBlob
    historyMessages.push(requestMessage)
  }

  private hasCompletedToolPart(parts: MessagePart[]): boolean {
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i]
      if (part.kind === MessagePartKind.TOOL && part.toolCallId !== '' && part.toolName !== '' && part.toolResult !== '') {
        return true
      }
    }
    return false
  }

  private buildToolCallFromPart(part: MessagePart): ToolCall {
    const toolCall = new ToolCall(
      part.toolCallId,
      part.toolName,
      part.toolArguments,
      part.toolName,
      part.toolDisplayName,
      part.toolSourceType,
      part.toolSourceLabel,
      part.toolPermissionLevel
    )
    toolCall.approvalReason = part.toolApprovalReason
    return toolCall
  }

  private appendPartsRequestHistory(historyMessages: RequestMessage[], msg: ChatMessage): boolean {
    if (msg.role !== MessageRole.ASSISTANT || msg.parts.length === 0 || !this.hasCompletedToolPart(msg.parts)) {
      return false
    }

    let contentBuffer = ''
    let reasoningBuffer = ''
    let pendingToolParts: MessagePart[] = []

    const flushToolGroup = (): void => {
      if (pendingToolParts.length === 0) {
        return
      }

      const toolCalls: ToolCall[] = []
      for (let i = 0; i < pendingToolParts.length; i++) {
        toolCalls.push(this.buildToolCallFromPart(pendingToolParts[i]))
      }

      const assistantMsg = RequestMessage.createAssistantWithToolCalls(contentBuffer, toolCalls)
      assistantMsg.reasoningContent = reasoningBuffer
      historyMessages.push(assistantMsg)

      for (let i = 0; i < pendingToolParts.length; i++) {
        const part = pendingToolParts[i]
        historyMessages.push(RequestMessage.createToolResultMessage(part.toolCallId, part.toolResult))
      }

      contentBuffer = ''
      reasoningBuffer = ''
      pendingToolParts = []
    }

    for (let i = 0; i < msg.parts.length; i++) {
      const part = msg.parts[i]
      if (part.kind === MessagePartKind.TOOL) {
        if (part.toolCallId !== '' && part.toolName !== '' && part.toolResult !== '') {
          pendingToolParts.push(part)
        }
        continue
      }

      if (pendingToolParts.length > 0) {
        flushToolGroup()
      }

      if (part.kind === MessagePartKind.TEXT) {
        contentBuffer += part.text
      } else if (part.kind === MessagePartKind.REASONING) {
        reasoningBuffer += part.text
      }
    }

    flushToolGroup()

    if (contentBuffer !== '' || reasoningBuffer !== '') {
      const finalAssistantMsg = new RequestMessage(MessageRole.ASSISTANT, contentBuffer)
      finalAssistantMsg.reasoningContent = reasoningBuffer
      finalAssistantMsg.reasoningSignatureBlob = msg.reasoningSignatureBlob
      historyMessages.push(finalAssistantMsg)
    }

    return true
  }

  private buildConversationRequestHistory(
    messages: ChatMessage[],
    contextStartIndex: number,
    preserveToolPartOrder: boolean = false,
    includeAttachmentPayloads: boolean = true,
    maxHistoryMessages: number = MAX_HISTORY_MESSAGES_FOR_REQUEST
  ): RequestMessage[] {
    const historyMessages: RequestMessage[] = []
    for (let i = contextStartIndex; i < messages.length; i++) {
      const msg = messages[i]
      if (msg.role === MessageRole.SYSTEM) {
        continue
      }
      if (preserveToolPartOrder && this.appendPartsRequestHistory(historyMessages, msg)) {
        continue
      }
      this.appendFlatRequestHistoryMessage(historyMessages, msg, includeAttachmentPayloads)
    }
    // 截断到最近 maxHistoryMessages 条。maxHistoryMessages<=0 表示不截断
    if (maxHistoryMessages > 0 && historyMessages.length > maxHistoryMessages) {
      const dropped = historyMessages.length - maxHistoryMessages
      const truncated = historyMessages.slice(historyMessages.length - maxHistoryMessages)
      console.info('ChatViewModel',
        `History truncated: kept ${truncated.length} of ${historyMessages.length} messages (dropped ${dropped})`)
      return truncated
    }
    return historyMessages
  }

  // 判断待持久化消息是否包含有效内容（空占位消息不应跨会话残留）
  private hasMeaningfulPendingMessageContent(message: ChatMessage): boolean {
    if (message.content.trim() !== '') {
      return true
    }
    if (message.reasoningContent.trim() !== '') {
      return true
    }
    if (message.attachments.length > 0) {
      return true
    }
    if (message.searchReferences.length > 0) {
      return true
    }
    if (message.toolCalls.length > 0) {
      return true
    }
    if (message.toolResults.length > 0) {
      return true
    }
    return false
  }

  // 丢弃指定待持久化 AI 消息（用于 stop 后清理空占位）
  discardPendingAIMessage(messageId: string): void {
    this.clearPendingAIMessageIfMatches(messageId)
  }

  private persistPendingAIMessageIfNeeded(sessionIdScope?: string): void {
    const scoped = sessionIdScope !== undefined && sessionIdScope !== ''
    const entries: PendingAIMessageInfo[] = []
    const discardMessageIds: string[] = []
    this.pendingAIMessages.forEach((info: PendingAIMessageInfo) => {
      if (info.persisted || info.sessionId === '') {
        return
      }
      if (scoped && info.sessionId !== sessionIdScope) {
        return
      }
      if (!this.hasMeaningfulPendingMessageContent(info.message)) {
        discardMessageIds.push(info.message.id)
        return
      }
      // stop 后持久化的消息应结束生成/搜索状态
      info.message.isGenerating = false
      info.message.isSearching = false
      entries.push(info)
    })

    for (let i = 0; i < discardMessageIds.length; i++) {
      this.clearPendingAIMessageIfMatches(discardMessageIds[i])
      console.info('ChatViewModel', `Discard empty pending AI message on stop: ${discardMessageIds[i]}`)
    }

    for (let i = 0; i < entries.length; i++) {
      const info = entries[i]
      // 避免重复插入
      info.persisted = true

      const msgToSave = info.message
      const sessionId = info.sessionId
      const messageId = msgToSave.id
      ;(async () => {
        try {
          await this.databaseService.addMessage(sessionId, msgToSave)
          this.clearPendingAIMessageIfMatches(messageId)
          console.info('ChatViewModel', `Pending AI message persisted on stop: ${messageId}`)
        } catch (e) {
          console.error('ChatViewModel', `Failed to persist pending AI message: ${JSON.stringify(e)}`)
          // 失败时允许后续再尝试
          const failedInfo = this.pendingAIMessages.get(messageId)
          if (failedInfo !== undefined) {
            failedInfo.persisted = false
          }
        }
      })()
    }
  }

  private discardPendingAIMessagesForScope(sessionIdScope?: string): void {
    const scoped = sessionIdScope !== undefined && sessionIdScope !== ''
    const discardMessageIds: string[] = []
    this.pendingAIMessages.forEach((info: PendingAIMessageInfo) => {
      if (scoped && info.sessionId !== sessionIdScope) {
        return
      }
      discardMessageIds.push(info.message.id)
    })
    for (let i = 0; i < discardMessageIds.length; i++) {
      this.clearPendingAIMessageIfMatches(discardMessageIds[i])
      console.info('ChatViewModel', `Discard pending AI message before rewrite: ${discardMessageIds[i]}`)
    }
  }

  private registerActiveRequest(
    requestId: string,
    httpRequest: http.HttpRequest,
    cancelCallback: () => void,
    sessionId: string
  ): void {
    // 多轮工具调用每轮会重新调 registerActiveRequest 覆盖同一个 requestId, 上一轮的 httpRequest
    // 必须显式 destroy。HttpService.streamPost 内部正常完成时已经 destroy 过, 这里是兜底:
    // 防止流式未触发 dataEnd / 中间态被覆盖时 native 资源累积导致 OOM 闪退。
    const existing = this.activeRequests.get(requestId)
    if (existing !== undefined && existing.httpRequest !== httpRequest) {
      try {
        existing.httpRequest.destroy()
      } catch (_e) {
        // ignore destroy errors (already destroyed by streamPost / stopGeneration)
      }
    }
    this.activeRequests.set(requestId, {
      httpRequest: httpRequest,
      cancelCallback: cancelCallback,
      sessionId: sessionId
    } as ActiveRequestInfo)
  }

  private unregisterActiveRequest(requestId: string): void {
    // unregister 同时 destroy 是防御性兜底, 应对 HttpService.streamPost 漏 destroy 的极端路径
    // (如 onComplete 未触发就走 cancel 流程)。已 destroy 的 native 句柄重复 destroy 由 try/catch 兜住。
    const info = this.activeRequests.get(requestId)
    if (info !== undefined) {
      try {
        info.httpRequest.destroy()
      } catch (_e) {
        // ignore
      }
    }
    this.activeRequests.delete(requestId)
  }

  // 创建新会话
	  async createNewSession(
	    title: string = '',
	    assistantId: string = 'default',
	    modelIdSeed: string = '',
	    providerIdSeed: string = ''
	  ): Promise<ChatSession> {
	    const session = await this.sessionStore.createNewSession(title, assistantId, modelIdSeed, providerIdSeed)
	    this.currentSession = this.sessionStore.getCurrentSession()
	    return session
	  }

	  // 创建待持久化的会话（仅内存中，不保存到数据库）
	  createPendingSession(
	    title: string = '',
	    assistantId: string = 'default',
	    modelIdSeed: string = '',
	    providerIdSeed: string = ''
	  ): ChatSession {
	    const session = this.sessionStore.createPendingSession(title, assistantId, modelIdSeed, providerIdSeed)
	    this.currentSession = this.sessionStore.getCurrentSession()
	    return session
	  }

  // 持久化待处理的会话
  private async persistPendingSession(): Promise<void> {
    await this.sessionStore.persistPendingSession()
    this.currentSession = this.sessionStore.getCurrentSession()
  }

  async saveSessionDraft(content: string, attachments: MessageAttachment[]): Promise<ChatSession | null> {
    const hasDraftContent = content.trim() !== '' || attachments.length > 0
	    if (this.currentSession === null) {
	      if (!hasDraftContent) {
	        return null
	      }
	      const assistant = await this.assistantService.getCurrentAssistantForNewChat()
	      this.createPendingSession('', assistant.id, assistant.defaultModelId, assistant.defaultProviderId)
	    }
    if (hasDraftContent && this.sessionStore.isCurrentSessionPending()) {
      await this.persistPendingSession()
    }

    this.currentSession = this.sessionStore.getCurrentSession()
    if (this.currentSession === null) {
      return null
    }

    this.currentSession.draftText = content
    this.currentSession.draftAttachments = this.cloneAttachments(attachments)
    if (this.currentSession.messages.length === 0) {
      this.currentSession.title = this.buildDraftTitle(content)
      this.currentSession.lastMessagePreview = this.buildDraftPreview(content, attachments)
      this.currentSession.updatedAt = Date.now()
    }

    if (this.sessionStore.isCurrentSessionPending()) {
      return this.currentSession
    }

    await this.databaseService.updateSessionDraft(this.currentSession.id, content, attachments)
    return this.currentSession
  }

  // 加载会话
  async loadSession(sessionId: string): Promise<ChatSession | null> {
    return this.finalizeLoadedSession(sessionId, await this.sessionStore.loadSession(sessionId))
  }

  // 获取所有会话
  async getAllSessions(): Promise<ChatSession[]> {
    return await this.sessionStore.getAllSessions()
  }

  // 删除会话
  async deleteSession(sessionId: string): Promise<void> {
    this.cancelGenerationForMessageRewrite(sessionId)
    this.toolExecutionService.cancelPendingInteractionsForSession(sessionId)
    await this.sessionStore.deleteSession(sessionId)
    this.currentSession = this.sessionStore.getCurrentSession()
  }

  // 获取当前会话
  getCurrentSession(): ChatSession | null {
    this.currentSession = this.sessionStore.getCurrentSession()
    return this.currentSession
  }

  async toggleSessionFavorite(sessionId: string): Promise<boolean> {
    const isFavorite = await this.sessionStore.toggleSessionFavorite(sessionId)
    this.currentSession = this.sessionStore.getCurrentSession()
    return isFavorite
  }

  async updateCurrentSessionModelSelection(modelId: string, providerId: string): Promise<boolean> {
    const updated = await this.sessionStore.updateCurrentSessionModelSelection(modelId, providerId)
    this.currentSession = this.sessionStore.getCurrentSession()
    return updated
  }

  // 发送消息并获取 AI 回复
  async sendMessage(
    content: string,
    providerId: string,
    providerType: ProviderType,
    apiStyle: ApiStyle,
    apiKey: string,
    baseUrl: string,
    modelId: string,
    modelName: string,
    messages: ChatMessage[],
    onUserMessageAdded: (message: ChatMessage) => void,
    onAIMessageAdded: (message: ChatMessage) => void,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    onError: (error: string) => void,
    attachments: MessageAttachment[] = [],
    contextStartIndex: number = 0,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF,
    apiPath?: string,  // 可选的自定义 API 路径
    customHeadersJson?: string,
    openaiTransport?: OpenAITransport,
    maxOutputTokens?: number,
    // OpenAI Responses 内置工具 (web_search / image_generation), 仅在 transport=responses 时下发
    builtInResponsesTools?: BuiltInResponsesToolSpec[]
  ): Promise<void> {
    const cancelSnapshot = this.cancelToken
    // 首次发送消息时，先持久化待处理的会话
    await this.persistPendingSession()
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 如果仍然没有当前会话，创建新的
	    if (this.currentSession === null) {
	      const assistant = await this.assistantService.getCurrentAssistantForNewChat()
	      await this.createNewSession('', assistant.id, assistant.defaultModelId, assistant.defaultProviderId)
	    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 快照会话信息，后续所有异步回调中使用快照而非 this.currentSession，避免并发请求时会话被覆盖
    const snapshotSessionId = this.currentSession?.id ?? ''
    const snapshotSession = this.currentSession
    const shouldAutoGenerateTitle = this.isFirstRoundSession(snapshotSession)
    const includeHistoryAttachmentPayloads = attachments.length === 0
    const historyMessages = this.buildConversationRequestHistory(
      messages,
      contextStartIndex,
      false,
      includeHistoryAttachmentPayloads
    )
    const requestAttachments = await this.prepareOutgoingAttachments(attachments)
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 创建用户消息
    const userMessage = new ChatMessage(
      this.generateId(),
      MessageRole.USER,
      content,
      ''
    )
    userMessage.attachments = this.cloneAttachmentsForStoredMessage(attachments)

    // 通知 UI 添加用户消息（优先渲染，避免”返回再进来只剩用户消息/无模型信息”）
    onUserMessageAdded(userMessage)

    // 提前创建 AI 消息占位符：如果用户在模型响应前退出页面，stopGeneration 仍能持久化该消息
    const aiMessage = new ChatMessage(
      this.generateId(),
      MessageRole.ASSISTANT,
      '',
      modelName,
      modelId
    )
    aiMessage.isGenerating = true
    onAIMessageAdded(aiMessage)
    this.addPendingAIMessage(aiMessage, snapshotSessionId)

    // 保存用户消息到数据库
    if (snapshotSession !== null) {
      await this.databaseService.addMessage(snapshotSessionId, userMessage)
      this.appendMessageToSessionIfMissing(snapshotSession, userMessage)
      if (shouldAutoGenerateTitle) {
        const title = content.length > 20 ? content.substring(0, 20) + '...' : content
        snapshotSession.title = title
        await this.databaseService.updateSessionTitle(snapshotSessionId, title)
        this.notifySessionListChanged()
      }
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

	    // 构建请求消息列表（从上下文起始位置开始，过滤掉上下文清空标记）
	    const requestMessages: RequestMessage[] = []
	    const renderedSystemPrompt = await this.buildRequestSystemPrompt()
	    if (renderedSystemPrompt !== '') {
	      requestMessages.push(new RequestMessage('system', renderedSystemPrompt))
	    }
    for (let i = 0; i < historyMessages.length; i++) {
      requestMessages.push(historyMessages[i])
    }
    requestMessages.push(new RequestMessage('user', content, requestAttachments))

    await this.prepareRequestHistoryAttachmentsIfNeeded(
      requestMessages,
      includeHistoryAttachmentPayloads,
      attachments.length
    )
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 构建 API 配置
    const apiConfig: AIApiConfig = {
      providerId: providerId,
      providerType: providerType,
      apiStyle: apiStyle,
      apiKey: getEffectiveApiKey(providerId, apiKey),
      baseUrl: baseUrl,
      apiPath: apiPath,
      openaiTransport: openaiTransport,
      customHeadersJson: customHeadersJson
    }

    const overrideTopP = await this.getRequestTopP()
    if (overrideTopP !== undefined) {
      apiConfig.topP = overrideTopP
    }
    const overridePresencePenalty = await this.getRequestPresencePenalty()
    if (overridePresencePenalty !== undefined) {
      apiConfig.presencePenalty = overridePresencePenalty
    }
    const overrideFrequencyPenalty = await this.getRequestFrequencyPenalty()
    if (overrideFrequencyPenalty !== undefined) {
      apiConfig.frequencyPenalty = overrideFrequencyPenalty
    }
    apiConfig.modelReasoningStrategyOverride = ''
    apiConfig.modelSupportsReasoning = this.getCurrentModelSupportsReasoning(providerId, modelId)

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 每请求独立的状态（通过闭包隔离）
    let cancelled = false
    let userCancelled = false
    let hasReceivedFirstChunk = false
    const localContentThrottle = this.createStreamFlusher()
    const localFirstChunkThrottle = localContentThrottle
    const localReasoningThrottle = this.createStreamFlusher()
    const requestId = this.generateId()
    const pendingImageSaves: Promise<void>[] = []

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 发送流式请求
	    const requestTemperature = await this.getRequestTemperature()
	    const effectiveMaxOutputTokens = await this.resolveEffectiveMaxOutputTokens(maxOutputTokens)
	    const httpRequest = this.aiApiService.streamChatRequest(
      apiConfig,
      requestMessages,
      modelId,
      (contentChunk: string) => {
        this.throttleStreamContentChunk(
          contentChunk,
          localFirstChunkThrottle,
          localContentThrottle,
          () => hasReceivedFirstChunk,
          (value: boolean) => { hasReceivedFirstChunk = value },
          () => cancelled,
          (throttledContent: string) => {
            this.flushPendingReasoningBeforeContent(
              localReasoningThrottle,
              () => cancelled,
              aiMessage,
              onAIMessageUpdated
            )
            this.appendStreamedContent(aiMessage, throttledContent, onAIMessageUpdated)
          }
        )
      },
      async () => {
        if (cancelled) {
          return
        }
        // 刷新节流器
        this.flushPendingReasoningBeforeContent(
          localReasoningThrottle,
          () => cancelled,
          aiMessage,
          onAIMessageUpdated
        )
        this.flushStreamContentFlushers(
          localFirstChunkThrottle,
          localContentThrottle,
          () => cancelled,
          (throttledContent: string) => {
            this.flushPendingReasoningBeforeContent(
              localReasoningThrottle,
              () => cancelled,
              aiMessage,
              onAIMessageUpdated
            )
            this.appendStreamedContent(aiMessage, throttledContent, onAIMessageUpdated)
          }
        )

        await this.waitForAIGeneratedImageSaves(pendingImageSaves)
        this.fillEmptyAIContentPlaceholder(aiMessage)
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)

        try {
          if (snapshotSession !== null) {
            await this.databaseService.addMessage(snapshotSessionId, aiMessage)
            this.appendMessageToSessionIfMissing(snapshotSession, aiMessage)
            this.markPendingAIMessagePersisted(aiMessage.id)
            this.clearPendingAIMessageIfMatches(aiMessage.id)

            if (shouldAutoGenerateTitle) {
              this.generateSmartTitle(snapshotSession)
            }
          }
        } catch (persistError) {
          console.error('ChatViewModel', `Failed to persist AI message on complete: ${JSON.stringify(persistError)}`)
        } finally {
          this.resetStreamFlushers(localFirstChunkThrottle, localContentThrottle, localReasoningThrottle)
          this.unregisterActiveRequest(requestId)
          onComplete()
        }
      },
      (error: string) => {
        if (cancelled) {
          return
        }
        this.flushPendingReasoningBeforeContent(
          localReasoningThrottle,
          () => cancelled,
          aiMessage,
          onAIMessageUpdated
        )
        this.flushStreamContentFlushers(
          localFirstChunkThrottle,
          localContentThrottle,
          () => cancelled,
          (throttledContent: string) => {
            this.flushPendingReasoningBeforeContent(
              localReasoningThrottle,
              () => cancelled,
              aiMessage,
              onAIMessageUpdated
            )
            this.appendStreamedContent(aiMessage, throttledContent, onAIMessageUpdated)
          }
        )
        this.fillEmptyAIContentPlaceholder(aiMessage, error)
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)

        try {
          if (userCancelled) {
            console.info('ChatViewModel', 'Request cancelled by user')
            onComplete()
          } else {
            onError(error)
          }
        } finally {
          this.resetStreamFlushers(localFirstChunkThrottle, localContentThrottle, localReasoningThrottle)
          this.clearPendingAIMessageIfMatches(aiMessage.id)
          this.unregisterActiveRequest(requestId)
        }
      },
	      requestTemperature,
      effectiveMaxOutputTokens,
      (reasoningContent: string) => {
        if (cancelled) {
          return
        }
        localReasoningThrottle.throttle(reasoningContent, (throttledContent: string) => {
          if (cancelled) {
            return
          }
          this.appendStreamedReasoning(aiMessage, throttledContent, onAIMessageUpdated)
        })
      },
      (base64Data: string, mimeType: string, isPartial: boolean) => {
        if (cancelled) {
          return
        }
        // P0: 渐进图(partial)先不落盘以免污染相册，等最终图; P2 再补 UI 预览。
        if (isPartial) {
          return
        }
        this.trackAIGeneratedImageSave(pendingImageSaves, base64Data, mimeType, aiMessage, onAIMessageUpdated)
      },
      reasoningLevel,
      builtInResponsesTools,
      (refs: SearchReference[]) => {
        if (cancelled) {
          return
        }
        this.appendBuiltinSearchReferences(aiMessage, refs, onAIMessageUpdated)
      },
      (event: HostedResponsesToolEvent) => {
        if (cancelled) {
          return
        }
        this.handleHostedResponsesToolEvent(aiMessage, event, onAIMessageUpdated)
      },
      this.createAIGeneratedImageFileCallbacks(
        pendingImageSaves,
        aiMessage,
        onAIMessageUpdated,
        () => cancelled
      )
    )

    // 注册到活跃请求 Map
    this.registerActiveRequest(requestId, httpRequest, () => {
      cancelled = true
      userCancelled = true
      this.resetStreamFlushers(localFirstChunkThrottle, localContentThrottle, localReasoningThrottle)
    }, snapshotSessionId)
  }

  // 带网页上下文发送消息
  async sendMessageWithWebContext(
    content: string,
    webContext: WebSearchResult,
    providerId: string,
    providerType: ProviderType,
    apiStyle: ApiStyle,
    apiKey: string,
    baseUrl: string,
    modelId: string,
    modelName: string,
    messages: ChatMessage[],
    attachments: MessageAttachment[],
    contextStartIndex: number,
    onUserMessageAdded: (message: ChatMessage) => void,
    onAIMessageAdded: (message: ChatMessage) => void,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    onError: (error: string) => void,
    apiPath?: string,
    customHeadersJson?: string,
    openaiTransport?: OpenAITransport
  ): Promise<void> {
    const cancelSnapshot = this.cancelToken
    await this.persistPendingSession()
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

	    if (this.currentSession === null) {
	      const assistant = await this.assistantService.getCurrentAssistantForNewChat()
	      await this.createNewSession('', assistant.id, assistant.defaultModelId, assistant.defaultProviderId)
	    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 快照会话信息，后续所有异步回调中使用快照而非 this.currentSession
    const snapshotSessionId = this.currentSession?.id ?? ''
    const snapshotSession = this.currentSession
    const shouldAutoGenerateTitle = this.isFirstRoundSession(snapshotSession)
    const includeHistoryAttachmentPayloads = attachments.length === 0
    const historyMessages = this.buildConversationRequestHistory(
      messages,
      contextStartIndex,
      false,
      includeHistoryAttachmentPayloads
    )
    const requestAttachments = await this.prepareOutgoingAttachments(attachments)
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 构建系统提示（包含网页内容）
    const systemPrompt = `用户提供了以下网页内容供参考：

标题：${webContext.title}
来源：${webContext.url}
正文：
${webContext.content}

请基于以上网页内容回答用户的问题。如果网页内容不完整或无法回答，请告知用户。`

    // 创建用户消息
    const userMessage = new ChatMessage(
      this.generateId(),
      MessageRole.USER,
      content,
      ''
    )
    userMessage.attachments = this.cloneAttachmentsForStoredMessage(attachments)

    onUserMessageAdded(userMessage)

    const aiMessage = new ChatMessage(
      this.generateId(),
      MessageRole.ASSISTANT,
      '',
      modelName,
      modelId
    )
    aiMessage.isGenerating = true
    onAIMessageAdded(aiMessage)
    this.addPendingAIMessage(aiMessage, snapshotSessionId)

    if (snapshotSession !== null) {
      await this.databaseService.addMessage(snapshotSessionId, userMessage)
      this.appendMessageToSessionIfMissing(snapshotSession, userMessage)
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

	    // 构建请求消息列表
	    const requestMessages: RequestMessage[] = []
	    const finalSystemPromptWeb = await this.buildRequestSystemPrompt(systemPrompt)
	    requestMessages.push(new RequestMessage('system', finalSystemPromptWeb))
    for (let i = 0; i < historyMessages.length; i++) {
      requestMessages.push(historyMessages[i])
    }
    requestMessages.push(new RequestMessage('user', content, requestAttachments))

    await this.prepareRequestHistoryAttachmentsIfNeeded(
      requestMessages,
      includeHistoryAttachmentPayloads,
      attachments.length
    )
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    const apiConfig: AIApiConfig = {
      providerId: providerId,
      providerType: providerType,
      apiStyle: apiStyle,
      apiKey: apiKey,
      baseUrl: baseUrl,
      apiPath: apiPath,
      openaiTransport: openaiTransport,
      customHeadersJson: customHeadersJson
    }
    apiConfig.modelReasoningStrategyOverride = ''
    apiConfig.modelSupportsReasoning = this.getCurrentModelSupportsReasoning(providerId, modelId)

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 每请求独立的状态（通过闭包隔离）
    let cancelled = false
    let userCancelled = false
    let hasReceivedFirstChunk = false
    const localContentThrottle = this.createStreamFlusher()
    const localFirstChunkThrottle = localContentThrottle
    const localReasoningThrottle = this.createStreamFlusher()
    const requestId = this.generateId()
    const pendingImageSaves: Promise<void>[] = []

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

	    const requestTemperature = await this.getRequestTemperature()
	    const httpRequest = this.aiApiService.streamChatRequest(
      apiConfig,
      requestMessages,
      modelId,
      (contentChunk: string) => {
        this.throttleStreamContentChunk(
          contentChunk,
          localFirstChunkThrottle,
          localContentThrottle,
          () => hasReceivedFirstChunk,
          (value: boolean) => { hasReceivedFirstChunk = value },
          () => cancelled,
          (throttledContent: string) => {
            this.flushPendingReasoningBeforeContent(
              localReasoningThrottle,
              () => cancelled,
              aiMessage,
              onAIMessageUpdated
            )
            this.appendStreamedContent(aiMessage, throttledContent, onAIMessageUpdated)
          }
        )
      },
      async () => {
        if (cancelled) {
          return
        }
        this.flushPendingReasoningBeforeContent(
          localReasoningThrottle,
          () => cancelled,
          aiMessage,
          onAIMessageUpdated
        )
        this.flushStreamContentFlushers(
          localFirstChunkThrottle,
          localContentThrottle,
          () => cancelled,
          (throttledContent: string) => {
            this.flushPendingReasoningBeforeContent(
              localReasoningThrottle,
              () => cancelled,
              aiMessage,
              onAIMessageUpdated
            )
            this.appendStreamedContent(aiMessage, throttledContent, onAIMessageUpdated)
          }
        )
        await this.waitForAIGeneratedImageSaves(pendingImageSaves)
        this.fillEmptyAIContentPlaceholder(aiMessage)
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)
        try {
          if (snapshotSession !== null) {
            await this.databaseService.addMessage(snapshotSessionId, aiMessage)
            this.appendMessageToSessionIfMissing(snapshotSession, aiMessage)
            this.markPendingAIMessagePersisted(aiMessage.id)
            this.clearPendingAIMessageIfMatches(aiMessage.id)
            if (shouldAutoGenerateTitle) {
              this.generateSmartTitle(snapshotSession)
            }
          }
        } catch (persistError) {
          console.error('ChatViewModel', `Failed to persist AI message on complete: ${JSON.stringify(persistError)}`)
        } finally {
          this.resetStreamFlushers(localFirstChunkThrottle, localContentThrottle, localReasoningThrottle)
          this.unregisterActiveRequest(requestId)
          onComplete()
        }
      },
      (error: string) => {
        if (cancelled) {
          return
        }
        this.flushPendingReasoningBeforeContent(
          localReasoningThrottle,
          () => cancelled,
          aiMessage,
          onAIMessageUpdated
        )
        this.flushStreamContentFlushers(
          localFirstChunkThrottle,
          localContentThrottle,
          () => cancelled,
          (throttledContent: string) => {
            this.flushPendingReasoningBeforeContent(
              localReasoningThrottle,
              () => cancelled,
              aiMessage,
              onAIMessageUpdated
            )
            this.appendStreamedContent(aiMessage, throttledContent, onAIMessageUpdated)
          }
        )
        this.fillEmptyAIContentPlaceholder(aiMessage, error)
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)

        try {
          if (userCancelled) {
            console.info('ChatViewModel', 'Request cancelled by user')
            onComplete()
          } else {
            onError(error)
          }
        } finally {
          this.resetStreamFlushers(localFirstChunkThrottle, localContentThrottle, localReasoningThrottle)
          this.clearPendingAIMessageIfMatches(aiMessage.id)
          this.unregisterActiveRequest(requestId)
        }
      },
	      requestTemperature,
      await this.resolveEffectiveMaxOutputTokens(),
      (reasoningContent: string) => {
        if (cancelled) {
          return
        }
        localReasoningThrottle.throttle(reasoningContent, (throttledContent: string) => {
          if (cancelled) {
            return
          }
          this.appendStreamedReasoning(aiMessage, throttledContent, onAIMessageUpdated)
        })
      },
      (base64Data: string, mimeType: string, isPartial: boolean) => {
        if (cancelled) {
          return
        }
        if (isPartial) {
          return
        }
        this.trackAIGeneratedImageSave(pendingImageSaves, base64Data, mimeType, aiMessage, onAIMessageUpdated)
      }
    )

    // 注册到活跃请求 Map
    this.registerActiveRequest(requestId, httpRequest, () => {
      cancelled = true
      userCancelled = true
      this.resetStreamFlushers(localFirstChunkThrottle, localContentThrottle, localReasoningThrottle)
    }, snapshotSessionId)
  }

  // 带搜索结果上下文发送消息（新版）
  async sendMessageWithSearchResult(
    content: string,
    searchResult: SearchResult,
    providerId: string,
    providerType: ProviderType,
    apiStyle: ApiStyle,
    apiKey: string,
    baseUrl: string,
    modelId: string,
    modelName: string,
    messages: ChatMessage[],
    attachments: MessageAttachment[],
    contextStartIndex: number,
    onUserMessageAdded: (message: ChatMessage) => void,
    onAIMessageAdded: (message: ChatMessage) => void,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    onError: (error: string) => void,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF,
    apiPath?: string,
    customHeadersJson?: string,
    openaiTransport?: OpenAITransport
  ): Promise<void> {
    const cancelSnapshot = this.cancelToken
    await this.persistPendingSession()
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

	    if (this.currentSession === null) {
	      const assistant = await this.assistantService.getCurrentAssistantForNewChat()
	      await this.createNewSession('', assistant.id, assistant.defaultModelId, assistant.defaultProviderId)
	    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 快照会话信息，后续所有异步回调中使用快照而非 this.currentSession
    const snapshotSessionId = this.currentSession?.id ?? ''
    const snapshotSession = this.currentSession
    const shouldAutoGenerateTitle = this.isFirstRoundSession(snapshotSession)
    const includeHistoryAttachmentPayloads = attachments.length === 0
    const historyMessages = this.buildConversationRequestHistory(
      messages,
      contextStartIndex,
      false,
      includeHistoryAttachmentPayloads
    )
    const requestAttachments = await this.prepareOutgoingAttachments(attachments)
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 构建系统提示（包含搜索内容和当前时间）
    const currentTime = this.getCurrentTimeContext()
    const limitedSearchContext = this.limitSearchContextForPrompt(searchResult.contentForAI, 5000)
    const systemPrompt = `当前时间: ${currentTime}

用户进行了联网搜索,以下是搜索结果供参考:

${limitedSearchContext}

回答规则(非常重要):
1. 如果搜索结果/抓取正文中已经包含回答所需的信息(例如天气的温度/风力/AQI等具体数值),请直接整理并回答,不要再让用户去别的网站查询。
2. 只有当搜索结果中确实缺少关键数据时,才说明"未找到"并建议进一步查询。
3. 如果用户询问"今天"、"现在"等相对时间,请使用上述当前时间作为参考。
4. 若回答中需要写出"今天是X年X月X日",必须与"当前时间"保持一致,不得改成其他日期。
5. 如果搜索上下文显示 URL 读取失败或网页正文为空,请明确说明未读取到页面正文和错误原因。
6. 引用搜索结果时必须使用标准 Markdown 链接格式,例如 [新闻标题](https://example.com),不要只写 [1]、[2] 这种不可点击编号。`

    console.info('ChatViewModel', `[搜索上下文] 当前时间: ${currentTime}`)
    console.info('ChatViewModel', `[搜索上下文] 搜索查询: ${searchResult.query}`)
    console.info('ChatViewModel', `[搜索上下文] 系统提示长度: ${systemPrompt.length} 字符`)
    console.info('ChatViewModel', `[搜索上下文] 预览: ${systemPrompt.substring(0, 240)}...`)

    // 创建用户消息
    const userMessage = new ChatMessage(
      this.generateId(),
      MessageRole.USER,
      content,
      ''
    )
    userMessage.attachments = this.cloneAttachmentsForStoredMessage(attachments)

    // 添加搜索引用数据和查询内容
    userMessage.searchQuery = searchResult.query
    userMessage.searchEngine = searchResult.searchEngine || 'Web'
    userMessage.searchSource = 'manual'
    userMessage.isSearching = false  // 搜索已完成
    for (let i = 0; i < searchResult.references.length; i++) {
      userMessage.searchReferences.push(searchResult.references[i])
    }

    onUserMessageAdded(userMessage)

    const aiMessage = new ChatMessage(
      this.generateId(),
      MessageRole.ASSISTANT,
      '',
      modelName,
      modelId
    )
    aiMessage.isGenerating = true

    // 将搜索引用数据复制到 AI 消息，timeline 工具步骤的折叠列表会读这些字段渲染来源
    aiMessage.searchQuery = searchResult.query
    aiMessage.searchEngine = searchResult.searchEngine || 'Web'
    aiMessage.searchSource = 'manual'
    for (let i = 0; i < searchResult.references.length; i++) {
      aiMessage.searchReferences.push(searchResult.references[i])
    }

    onAIMessageAdded(aiMessage)
    this.addPendingAIMessage(aiMessage, snapshotSessionId)

    if (snapshotSession !== null) {
      await this.databaseService.addMessage(snapshotSessionId, userMessage)
      this.appendMessageToSessionIfMissing(snapshotSession, userMessage)
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

	    // 构建请求消息列表
	    const requestMessages: RequestMessage[] = []
	    const finalSystemPromptSearch = await this.buildRequestSystemPrompt(systemPrompt)
	    requestMessages.push(new RequestMessage('system', finalSystemPromptSearch))
    for (let i = 0; i < historyMessages.length; i++) {
      requestMessages.push(historyMessages[i])
    }
    requestMessages.push(new RequestMessage('user',
      this.buildSearchResultRequestContent(content, searchResult),
      requestAttachments))

    await this.prepareRequestHistoryAttachmentsIfNeeded(
      requestMessages,
      includeHistoryAttachmentPayloads,
      attachments.length
    )
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    const apiConfig: AIApiConfig = {
      providerId: providerId,
      providerType: providerType,
      apiStyle: apiStyle,
      apiKey: apiKey,
      baseUrl: baseUrl,
      apiPath: apiPath,
      openaiTransport: openaiTransport,
      customHeadersJson: customHeadersJson
    }
    apiConfig.modelReasoningStrategyOverride = ''
    apiConfig.modelSupportsReasoning = this.getCurrentModelSupportsReasoning(providerId, modelId)

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 每请求独立的状态（通过闭包隔离）
    let cancelled = false
    let userCancelled = false
    let hasReceivedFirstChunk = false
    const localContentThrottle = this.createStreamFlusher()
    const localFirstChunkThrottle = localContentThrottle
    const localReasoningThrottle = this.createStreamFlusher()
    const requestId = this.generateId()
    const pendingImageSaves: Promise<void>[] = []

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

	    const requestTemperature = await this.getRequestTemperature()
	    const httpRequest = this.aiApiService.streamChatRequest(
      apiConfig,
      requestMessages,
      modelId,
      (contentChunk: string) => {
        this.throttleStreamContentChunk(
          contentChunk,
          localFirstChunkThrottle,
          localContentThrottle,
          () => hasReceivedFirstChunk,
          (value: boolean) => { hasReceivedFirstChunk = value },
          () => cancelled,
          (throttledContent: string) => {
            this.flushPendingReasoningBeforeContent(
              localReasoningThrottle,
              () => cancelled,
              aiMessage,
              onAIMessageUpdated
            )
            this.appendStreamedContent(aiMessage, throttledContent, onAIMessageUpdated)
          }
        )
      },
      async () => {
        if (cancelled) {
          return
        }
        this.flushPendingReasoningBeforeContent(
          localReasoningThrottle,
          () => cancelled,
          aiMessage,
          onAIMessageUpdated
        )
        this.flushStreamContentFlushers(
          localFirstChunkThrottle,
          localContentThrottle,
          () => cancelled,
          (throttledContent: string) => {
            this.flushPendingReasoningBeforeContent(
              localReasoningThrottle,
              () => cancelled,
              aiMessage,
              onAIMessageUpdated
            )
            this.appendStreamedContent(aiMessage, throttledContent, onAIMessageUpdated)
          }
        )
        await this.waitForAIGeneratedImageSaves(pendingImageSaves)
        this.fillEmptyAIContentPlaceholder(aiMessage)
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)
        try {
          if (snapshotSession !== null) {
            await this.databaseService.addMessage(snapshotSessionId, aiMessage)
            this.appendMessageToSessionIfMissing(snapshotSession, aiMessage)
            this.markPendingAIMessagePersisted(aiMessage.id)
            this.clearPendingAIMessageIfMatches(aiMessage.id)
            if (shouldAutoGenerateTitle) {
              this.generateSmartTitle(snapshotSession)
            }
          }
        } catch (persistError) {
          console.error('ChatViewModel', `Failed to persist AI message on complete: ${JSON.stringify(persistError)}`)
        } finally {
          this.resetStreamFlushers(localFirstChunkThrottle, localContentThrottle, localReasoningThrottle)
          this.unregisterActiveRequest(requestId)
          onComplete()
        }
      },
      (error: string) => {
        if (cancelled) {
          return
        }
        this.flushPendingReasoningBeforeContent(
          localReasoningThrottle,
          () => cancelled,
          aiMessage,
          onAIMessageUpdated
        )
        this.flushStreamContentFlushers(
          localFirstChunkThrottle,
          localContentThrottle,
          () => cancelled,
          (throttledContent: string) => {
            this.flushPendingReasoningBeforeContent(
              localReasoningThrottle,
              () => cancelled,
              aiMessage,
              onAIMessageUpdated
            )
            this.appendStreamedContent(aiMessage, throttledContent, onAIMessageUpdated)
          }
        )
        this.fillEmptyAIContentPlaceholder(aiMessage, error)
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)

        try {
          if (userCancelled) {
            console.info('ChatViewModel', 'Request cancelled by user')
            onComplete()
          } else {
            onError(error)
          }
        } finally {
          this.resetStreamFlushers(localFirstChunkThrottle, localContentThrottle, localReasoningThrottle)
          this.clearPendingAIMessageIfMatches(aiMessage.id)
          this.unregisterActiveRequest(requestId)
        }
      },
	      requestTemperature,
      await this.resolveEffectiveMaxOutputTokens(),
      (reasoningContent: string) => {
        if (cancelled) {
          return
        }
        localReasoningThrottle.throttle(reasoningContent, (throttledContent: string) => {
          if (cancelled) {
            return
          }
          this.appendStreamedReasoning(aiMessage, throttledContent, onAIMessageUpdated)
        })
      },
      (base64Data: string, mimeType: string, isPartial: boolean) => {
        if (cancelled) {
          return
        }
        // P0: 渐进图(partial)先不落盘以免污染相册，等最终图; P2 再补 UI 预览。
        if (isPartial) {
          return
        }
        this.trackAIGeneratedImageSave(pendingImageSaves, base64Data, mimeType, aiMessage, onAIMessageUpdated)
      },
      reasoningLevel
    )

    // 注册到活跃请求 Map
    this.registerActiveRequest(requestId, httpRequest, () => {
      cancelled = true
      userCancelled = true
      this.resetStreamFlushers(localFirstChunkThrottle, localContentThrottle, localReasoningThrottle)
    }, snapshotSessionId)
  }

  // 发送消息并使用 Function Calling 工具
  async sendMessageWithTools(
    content: string,
    providerId: string,
    providerType: ProviderType,
    apiStyle: ApiStyle,
    apiKey: string,
    baseUrl: string,
    modelId: string,
    modelName: string,
    messages: ChatMessage[],
    onUserMessageAdded: (message: ChatMessage) => void,
    onAIMessageAdded: (message: ChatMessage) => void,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    onError: (error: string) => void | Promise<void>,
    attachments: MessageAttachment[] = [],
    contextStartIndex: number = 0,
    reasoningLevel: ReasoningLevel = ReasoningLevel.OFF,
    tools: ToolDefinition[] = [],
    toolCallbacks?: ToolCallCallbacks,
    apiPath?: string,
    customHeadersJson?: string,
    openaiTransport?: OpenAITransport,
    // OpenAI Responses 内置工具 (web_search / image_generation), 与 function tools 可并存
    builtInResponsesTools?: BuiltInResponsesToolSpec[],
    builtInResponsesToolChoice?: OpenAIResponsesToolChoice
  ): Promise<void> {
    const cancelSnapshot = this.cancelToken
    // 首次发送消息时，先持久化待处理的会话
    await this.persistPendingSession()
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 如果仍然没有当前会话，创建新的
	    if (this.currentSession === null) {
	      const assistant = await this.assistantService.getCurrentAssistantForNewChat()
	      await this.createNewSession('', assistant.id, assistant.defaultModelId, assistant.defaultProviderId)
	    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 快照会话信息，后续所有异步回调中使用快照而非 this.currentSession
    const snapshotSessionId = this.currentSession?.id ?? ''
    const snapshotSession = this.currentSession
    const shouldAutoGenerateTitle = this.isFirstRoundSession(snapshotSession)
    const includeHistoryAttachmentPayloads = attachments.length === 0
    const historyMessages = this.buildConversationRequestHistory(
      messages,
      contextStartIndex,
      true,
      includeHistoryAttachmentPayloads
    )
    const requestAttachments = await this.prepareOutgoingAttachments(attachments)
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 创建用户消息
    const userMessage = new ChatMessage(
      this.generateId(),
      MessageRole.USER,
      content,
      ''
    )
    userMessage.attachments = this.cloneAttachmentsForStoredMessage(attachments)

    // 通知 UI 添加用户消息（优先渲染）
    onUserMessageAdded(userMessage)

    // 提前创建 AI 消息占位符，确保中途退出页面也能恢复模型信息/重新生成
    const aiMessage = new ChatMessage(
      this.generateId(),
      MessageRole.ASSISTANT,
      '',
      modelName,
      modelId
    )
    aiMessage.isGenerating = true

    onAIMessageAdded(aiMessage)
    this.addPendingAIMessage(aiMessage, snapshotSessionId)

    // 保存用户消息到数据库
    if (snapshotSession !== null) {
      await this.databaseService.addMessage(snapshotSessionId, userMessage)
      this.appendMessageToSessionIfMissing(snapshotSession, userMessage)
      if (shouldAutoGenerateTitle) {
        const title = content.length > 20 ? content.substring(0, 20) + '...' : content
        snapshotSession.title = title
        await this.databaseService.updateSessionTitle(snapshotSessionId, title)
        this.notifySessionListChanged()
      }
    }
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 构建请求消息列表
    const requestMessages: RequestMessage[] = []
    const currentTime = this.getCurrentTimeContext()
    // 工具使用规则只保留与具体工具无关的通用约束。
    // 工具特定的细节（如 search_web 怎么用关键词、scrape_web URL 原样传入、引用 Markdown 链接）
    // 都已经写在 BuiltinTools.ets 的 ToolFunction.description 里，模型在 function calling 时直接看到，
    // 不需要在 system 中再复述一遍，避免与 description 冲突或重复消耗 token。
    const toolUsageSystemPrompt = `当前时间: ${currentTime}

你的首要任务是直接完成用户请求，只在确实需要访问外部信息或外部系统时才调用工具。

工具使用规则(非常重要):
- 绝大多数普通问答不需要调用工具，请优先用自身知识直接回答。
- 只有在用户请求明确依赖外部实时信息、外部文档、外部仓库、外部笔记或其他外部系统状态时才调用工具。
- 对外部系统有副作用的工具（例如创建、修改、删除、提交、上传）必须先确认用户意图与目标对象，不要擅自操作。
- 编程、写作、翻译、数学、创意等纯生成任务，若不依赖外部状态，绝对不要调用任何工具。
- 若用户提到“今天/昨天/明天/现在/最新”等相对时间，请以当前时间为基准理解，不要编造不一致的绝对日期。
- 工具返回后必须给出最终回答，不要在没有必要的情况下重复调用工具。`
    const finalToolUsageSystemPrompt = await this.buildRequestSystemPrompt(toolUsageSystemPrompt)
    requestMessages.push(new RequestMessage('system', finalToolUsageSystemPrompt))
    for (let i = 0; i < historyMessages.length; i++) {
      requestMessages.push(historyMessages[i])
    }
    requestMessages.push(new RequestMessage('user', content, requestAttachments))

    await this.prepareRequestHistoryAttachmentsIfNeeded(
      requestMessages,
      includeHistoryAttachmentPayloads,
      attachments.length
    )
    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 构建 API 配置
    const apiConfig: AIApiConfig = {
      providerId: providerId,
      providerType: providerType,
      apiStyle: apiStyle,
      apiKey: getEffectiveApiKey(providerId, apiKey),
      baseUrl: baseUrl,
      apiPath: apiPath,
      openaiTransport: openaiTransport,
      customHeadersJson: customHeadersJson
    }

    const overrideTopP = await this.getRequestTopP()
    if (overrideTopP !== undefined) {
      apiConfig.topP = overrideTopP
    }
    const overridePresencePenalty = await this.getRequestPresencePenalty()
    if (overridePresencePenalty !== undefined) {
      apiConfig.presencePenalty = overridePresencePenalty
    }
    const overrideFrequencyPenalty = await this.getRequestFrequencyPenalty()
    if (overrideFrequencyPenalty !== undefined) {
      apiConfig.frequencyPenalty = overrideFrequencyPenalty
    }
    apiConfig.modelReasoningStrategyOverride = ''
    apiConfig.modelSupportsReasoning = this.getCurrentModelSupportsReasoning(providerId, modelId)

    if (this.isCancelled(cancelSnapshot)) {
      return
    }

    // 每请求独立的状态（通过闭包隔离）
    let cancelled = false
    let userCancelled = false
    let toolExecutionCancelled = false
    let hasReceivedFirstChunk = false
    const localContentThrottle = this.createStreamFlusher()
    const localFirstChunkThrottle = localContentThrottle
    const localReasoningThrottle = this.createStreamFlusher()
    const requestId = this.generateId()

	    if (this.isCancelled(cancelSnapshot)) {
	      return
	    }
	    const requestTemperature = await this.getRequestTemperature()

	    // 先注册到活跃请求 Map（使用占位 httpRequest，executeToolCallLoop 内部会更新实际引用）
    // 必须在 await 之前注册，否则 stopGeneration 无法取消正在执行的请求。
    // 占位 httpRequest 不会发请求, 但 native 句柄已分配; executeToolCallLoop 拿到真实 httpRequest
    // 后会通过 registerActiveRequest 内部逻辑把它 destroy 掉, 不会泄漏。
    const placeholderHttp = http.createHttp()
    this.registerActiveRequest(requestId, placeholderHttp, () => {
      cancelled = true
      userCancelled = true
      toolExecutionCancelled = true
      this.resetStreamFlushers(localFirstChunkThrottle, localContentThrottle, localReasoningThrottle)
    }, snapshotSessionId)

    // 开始工具调用循环
    await this.executeToolCallLoop(
      apiConfig,
      requestMessages,
      modelId,
      aiMessage,
      onAIMessageUpdated,
      onComplete,
      onError,
      tools,
      toolCallbacks,
      reasoningLevel,
      requestTemperature,
      0,  // 初始工具步骤
      snapshotSessionId,
      snapshotSession,
      shouldAutoGenerateTitle,
      requestId,
      () => cancelled,
      () => userCancelled,
      () => toolExecutionCancelled,
      (v: boolean) => { userCancelled = v },
      () => hasReceivedFirstChunk,
      (v: boolean) => { hasReceivedFirstChunk = v },
      localFirstChunkThrottle,
      localContentThrottle,
      localReasoningThrottle,
      builtInResponsesTools,
      builtInResponsesToolChoice
    )
  }

  private fillFallbackFromSearchSummaryIfNeeded(aiMessage: ChatMessage): void {
    if (aiMessage.content.trim() !== '' || aiMessage.toolResults.length === 0) {
      return
    }

    for (let i = aiMessage.toolResults.length - 1; i >= 0; i--) {
      try {
        const data = JSON.parse(aiMessage.toolResults[i].content) as Record<string, Object>
        if (data !== undefined && data.summary !== undefined && `${data.summary}`.trim() !== '') {
          let preview = `${data.summary}`.trim()
          const maxLen = 1200
          if (preview.length > maxLen) {
            preview = preview.substring(0, maxLen) + '...'
          }
          aiMessage.content = `已完成联网搜索，但模型未返回最终回答。以下为搜索结果摘要（可用于人工查看/再次提问）：\n\n${preview}`
          return
        }
      } catch (e) {
        // ignore
      }
    }
  }

  private async finalizeAIMessage(
    aiMessage: ChatMessage,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    snapshotSessionId: string,
    snapshotSession: ChatSession | null,
    shouldAutoGenerateTitle: boolean,
    requestId: string,
    pendingImageSaves: Promise<void>[] = []
  ): Promise<void> {
    await this.waitForAIGeneratedImageSaves(pendingImageSaves)
    this.fillFallbackFromSearchSummaryIfNeeded(aiMessage)
    this.fillEmptyAIContentPlaceholder(aiMessage)
    aiMessage.isGenerating = false
    aiMessage.isSearching = false
    onAIMessageUpdated(aiMessage)

    try {
      if (snapshotSession !== null) {
        await this.databaseService.addMessage(snapshotSessionId, aiMessage)
        this.appendMessageToSessionIfMissing(snapshotSession, aiMessage)
        this.markPendingAIMessagePersisted(aiMessage.id)
        this.clearPendingAIMessageIfMatches(aiMessage.id)
        if (shouldAutoGenerateTitle) {
          this.generateSmartTitle(snapshotSession)
        }
        // 备课老师：会话成功结束后通知一次（仅小星老师助手）
        // 5min 静默 debounce 合并多次,失败/取消路径不会触发
        this.notifyPlannerSessionEnd(snapshotSessionId, snapshotSession.assistantId)
      }
    } catch (persistError) {
      console.error('ChatViewModel', `Failed to persist AI message in finalizeAIMessage: ${JSON.stringify(persistError)}`)
    } finally {
      this.unregisterActiveRequest(requestId)
      onComplete()
    }
  }

  /**
   * 通知备课老师：会话成功结束。
   * - 仅当 assistantId === DEFAULT_ASSISTANT_ID 时才触发
   * - 失败/取消的会话不会进入 finalizeAIMessage 的成功路径,天然不触发
   */
  private notifyPlannerSessionEnd(sessionId: string, assistantId: string): void {
    try {
      getLessonPlanningService().notifySessionEnd(sessionId, assistantId)
    } catch (error) {
      console.error('ChatViewModel', `notifyPlannerSessionEnd failed: ${JSON.stringify(error)}`)
    }
  }

  private trackAIGeneratedImageSave(
    pendingImageSaves: Promise<void>[],
    imageData: string,
    mimeType: string,
    aiMessage: ChatMessage,
    onAIMessageUpdated: (message: ChatMessage) => void
  ): void {
    const task = this.saveAIGeneratedImage(imageData, mimeType, aiMessage, onAIMessageUpdated)
      .catch((error: Object): void => {
        console.error('ChatViewModel', `Failed to save AI generated image: ${JSON.stringify(error)}`)
    })
    pendingImageSaves.push(task)
  }

  private createAIGeneratedImageFileCallbacks(
    pendingImageSaves: Promise<void>[],
    aiMessage: ChatMessage,
    onAIMessageUpdated: (message: ChatMessage) => void,
    shouldIgnore: () => boolean
  ): AIGeneratedImageFileCallbacks {
    return {
      createSink: (mimeType: string): AIGeneratedImageFileSink | null => {
        return this.attachmentStorageService.createAIGeneratedImageFileSink(mimeType)
      },
      onFile: (result: AIGeneratedImageFileResult): void => {
        const task = this.saveAIGeneratedImageFile(result, aiMessage, onAIMessageUpdated, shouldIgnore)
          .catch((error: Object): void => {
            console.error('ChatViewModel', `Failed to attach AI generated image file: ${JSON.stringify(error)}`)
          })
        pendingImageSaves.push(task)
      }
    }
  }

  private async saveAIGeneratedImageFile(
    result: AIGeneratedImageFileResult,
    aiMessage: ChatMessage,
    onAIMessageUpdated: (message: ChatMessage) => void,
    shouldIgnore: () => boolean
  ): Promise<void> {
    if (shouldIgnore()) {
      await this.attachmentStorageService.deleteAttachment(result.filePath)
      return
    }
    if (result.filePath === '' || result.attachmentId === '') {
      return
    }
    const attachment = new MessageAttachment(
      result.attachmentId,
      AttachmentType.IMAGE,
      result.fileName,
      result.filePath,
      result.mimeType,
      result.size
    )
    attachment.base64Data = ''
    aiMessage.addAttachment(attachment)
    this.upsertGeneratedImagePart(aiMessage, attachment, result.itemId, result.outputIndex)
    onAIMessageUpdated(aiMessage)
  }

  private upsertGeneratedImagePart(
    aiMessage: ChatMessage,
    attachment: MessageAttachment,
    itemId: string,
    outputIndex: number
  ): boolean {
    if (attachment.filePath === '') {
      return false
    }

    const source = attachment.filePath
    if (aiMessage.parts.length === 0) {
      this.ensurePartsBackfill(aiMessage)
    }
    const itemKey = this.buildOpenAIResponsesItemKey(itemId, outputIndex)
    const toolPartIndex = this.findHostedImageGenerationToolPartIndex(aiMessage, itemKey, outputIndex)
    for (let i = 0; i < aiMessage.parts.length; i++) {
      const existing = aiMessage.parts[i]
      if (existing.kind === MessagePartKind.IMAGE && this.isSameGeneratedImagePart(existing, source)) {
        let changed = false
        if (existing.mediaMime !== attachment.mimeType) {
          existing.mediaMime = attachment.mimeType
          changed = true
        }
        if (existing.mediaName !== attachment.name) {
          existing.mediaName = attachment.name
          changed = true
        }
        if (toolPartIndex >= 0) {
          if (this.syncOpenAIResponsesImagePartSourceFromTool(existing, aiMessage.parts[toolPartIndex])) {
            changed = true
          }
        }
        return changed
      }
    }

    const part = new MessagePart(MessagePartKind.IMAGE)
    part.mediaUrl = source
    part.mediaMime = attachment.mimeType
    part.mediaName = attachment.name
    if (toolPartIndex >= 0) {
      this.syncOpenAIResponsesImagePartSourceFromTool(part, aiMessage.parts[toolPartIndex])
      const nextParts = aiMessage.parts.slice()
      const insertIndex = this.getGeneratedImageInsertionIndexAfterTool(nextParts, toolPartIndex)
      nextParts.splice(insertIndex, 0, part)
      aiMessage.parts = nextParts
      return true
    }

    return false
  }

  private isSameGeneratedImagePart(part: MessagePart, filePath: string): boolean {
    if (part.mediaUrl === filePath) {
      return true
    }
    return part.mediaUrl === 'file://' + filePath
  }

  private findHostedImageGenerationToolPartIndex(
    aiMessage: ChatMessage,
    itemKey: string,
    outputIndex: number
  ): number {
    const preferredPartId = this.buildOpenAIResponsesHostedPartId(
      OPENAI_RESPONSES_IMAGE_GENERATION_PREFIX,
      itemKey
    )
    const exactIndex = this.findOpenAIResponsesHostedToolPartIndex(
      aiMessage,
      preferredPartId,
      itemKey,
      outputIndex,
      OPENAI_RESPONSES_IMAGE_GENERATION_LABEL
    )
    if (exactIndex >= 0) {
      return exactIndex
    }

    let latestToolIndex = -1
    for (let i = aiMessage.parts.length - 1; i >= 0; i--) {
      const candidate = aiMessage.parts[i]
      if (!this.isHostedImageGenerationToolPart(candidate)) {
        continue
      }
      if (latestToolIndex < 0) {
        latestToolIndex = i
      }
      if (!this.hasGeneratedImageImmediatelyAfterTool(aiMessage.parts, i)) {
        return i
      }
    }
    return latestToolIndex
  }

  private isHostedImageGenerationToolPart(part: MessagePart): boolean {
    if (part.kind !== MessagePartKind.TOOL) {
      return false
    }
    if (part.sourceType === OPENAI_RESPONSES_PART_SOURCE &&
      part.toolSourceLabel === OPENAI_RESPONSES_IMAGE_GENERATION_LABEL) {
      return true
    }
    return part.toolCallId.startsWith(OPENAI_RESPONSES_IMAGE_GENERATION_PREFIX + '_') ||
      part.toolSourceLabel === OPENAI_RESPONSES_IMAGE_GENERATION_LABEL
  }

  private hasGeneratedImageImmediatelyAfterTool(parts: MessagePart[], toolIndex: number): boolean {
    const nextIndex = toolIndex + 1
    return nextIndex < parts.length && parts[nextIndex].kind === MessagePartKind.IMAGE
  }

  private getGeneratedImageInsertionIndexAfterTool(parts: MessagePart[], toolIndex: number): number {
    let insertIndex = toolIndex + 1
    while (insertIndex < parts.length && parts[insertIndex].kind === MessagePartKind.IMAGE) {
      insertIndex++
    }
    return insertIndex
  }

  // OpenAI Responses 内置搜索引用累积:
  // url_citation 流式按 annotation 增量到达, 这里按 url 去重 push 到 aiMessage.searchReferences。
  // 来源标记 'openai_builtin', 引擎名固定为 'OpenAI Web Search', 让 SearchReferenceCard 走现有展示。
  private appendBuiltinSearchReferences(
    aiMessage: ChatMessage,
    refs: SearchReference[],
    onAIMessageUpdated: (message: ChatMessage) => void
  ): void {
    if (refs.length === 0) {
      return
    }
    let changed = false
    for (let i = 0; i < refs.length; i++) {
      const ref = refs[i]
      let exists = false
      for (let j = 0; j < aiMessage.searchReferences.length; j++) {
        if (aiMessage.searchReferences[j].url === ref.url) {
          exists = true
          break
        }
      }
      if (exists) {
        continue
      }
      aiMessage.searchReferences.push(ref)
      changed = true
    }
    if (!changed) {
      return
    }
    if (aiMessage.searchSource === '') {
      aiMessage.searchSource = 'openai_builtin'
    }
    if (aiMessage.searchEngine === '') {
      aiMessage.searchEngine = 'OpenAI Web Search'
    }
    // isSearching 开关由 handleHostedResponsesToolEvent 通过 in-flight 计数器统一管理,
    // 引用累积阶段不要主动关; 否则 OpenAI 在两次搜索之间下发首批 annotation 会导致卡片瞬时关闭。
    onAIMessageUpdated(aiMessage)
  }

  // OpenAI Responses 内置工具 (web_search / image_generation) 状态事件处理。
  //
  // 设计要点:
  // - 每次 web_search_call 创建一个独立的 TOOL part 写入 aiMessage.parts (toolCallId='hws_<itemId>'),
  //   后续 in_progress / searching / completed 只更新这一个 part. 保证 "新一轮搜索 ≠ 覆盖老结果",
  //   timeline 上能逐条看到每一次搜索的 query/状态, 不再使用 message.searchQuery 字符串拼接的低质量呈现。
  // - aiMessage.isSearching 通过 in-flight itemId 集合做计数: 第一次 STARTED 才置 true, 最后一次
  //   COMPLETED 才置 false, 避免多轮搜索时顶层 "searching" 标记反复闪烁。
  // - aiMessage.searchSource / searchEngine 只在首次置入, 不会被 query 覆盖; searchQuery 字段保持为空,
  //   让 SearchingIndicatorInline 不再走 fallback 文案 (parts 非空时也不显示该 indicator).
  // - 生图事件先打日志, P2 再串 timeline / partial 预览。
  private handleHostedResponsesToolEvent(
    aiMessage: ChatMessage,
    event: HostedResponsesToolEvent,
    onAIMessageUpdated: (message: ChatMessage) => void
  ): void {
    const kind = event.kind
    if (kind === HostedResponsesToolEventKind.WEB_SEARCH_STARTED ||
      kind === HostedResponsesToolEventKind.WEB_SEARCH_SEARCHING) {
      // itemId 可能为空 (旧版兜底), 用 outputIndex 拼接保持唯一; 若都缺则单次性 fallback
      const key = this.buildOpenAIResponsesItemKey(event.itemId, event.outputIndex)
      // open_page action 识别: action.type='open_page' 时 SSE 给的是 url 不是 query。
      // 这种调用在用户感知里更像 reasoning 段内的参考 URL, 单独 timeline 行会把 reasoning 切断,
      // 改为只追加到 searchReferences 让顶部引用卡片可见, parts 不动 → reasoning 自然合并。
      const url = event.url.trim()
      const query = event.query.trim()
      const isOpenPage = event.actionType === 'open_page' || (query === '' && url !== '')
      if (isOpenPage || this.isOpenPageRecorded(aiMessage.id, key)) {
        if (isOpenPage) {
          this.rememberOpenPageItem(aiMessage.id, key)
          const ref = new SearchReference(`hosted_openpage_${key}`, '', url, '')
          this.appendBuiltinSearchReferences(aiMessage, [ref], onAIMessageUpdated)
          console.info('ChatViewModel',
            `[ResponsesHostedTool] ${kind} open_page item=${event.itemId} url=${url}`)
        }
        return
      }
      let inflight = this.inflightHostedSearchCalls.get(aiMessage.id)
      if (inflight === undefined) {
        inflight = new Set<string>()
        this.inflightHostedSearchCalls.set(aiMessage.id, inflight)
      }
      const wasEmpty = inflight.size === 0
      inflight.add(key)
      let needUpdate = false
      if (wasEmpty && !aiMessage.isSearching) {
        aiMessage.isSearching = true
        if (aiMessage.searchSource === '') {
          aiMessage.searchSource = 'openai_builtin'
        }
        if (aiMessage.searchEngine === '') {
          aiMessage.searchEngine = OPENAI_RESPONSES_WEB_SEARCH_LABEL
        }
        needUpdate = true
      }
      // 每次 web_search_call 落一个独立 TOOL part, 状态置 RUNNING
      if (this.upsertHostedWebSearchPart(
        aiMessage, key, event.outputIndex, event.query, event.url, event.actionType, event.queries,
        ToolPartStatus.RUNNING
      )) {
        needUpdate = true
      }
      if (needUpdate) {
        onAIMessageUpdated(aiMessage)
      }
    } else if (kind === HostedResponsesToolEventKind.WEB_SEARCH_COMPLETED) {
      const key = this.buildOpenAIResponsesItemKey(event.itemId, event.outputIndex)
      // COMPLETED 阶段也按 open_page 识别一次, 兜底 STARTED 里 url 漏掉的情况 (有些版本 action 只在 done 上挂)
      const url = event.url.trim()
      const query = event.query.trim()
      const isOpenPageNow = event.actionType === 'open_page' || (query === '' && url !== '')
      if (isOpenPageNow || this.isOpenPageRecorded(aiMessage.id, key)) {
        if (isOpenPageNow) {
          this.rememberOpenPageItem(aiMessage.id, key)
          const ref = new SearchReference(`hosted_openpage_${key}`, '', url, '')
          this.appendBuiltinSearchReferences(aiMessage, [ref], onAIMessageUpdated)
        }
        console.info('ChatViewModel',
          `[ResponsesHostedTool] ${kind} open_page item=${event.itemId} url=${url}`)
        this.forgetOpenPageItem(aiMessage.id, key)
        return
      }
      // done 阶段补一次 query/url, 兜底 added 阶段没有挂载 action 的情况; 同时把状态置 SUCCEEDED
      const partChanged = this.upsertHostedWebSearchPart(
        aiMessage, key, event.outputIndex, event.query, event.url, event.actionType, event.queries,
        ToolPartStatus.SUCCEEDED
      )
      const inflight = this.inflightHostedSearchCalls.get(aiMessage.id)
      if (inflight !== undefined) {
        inflight.delete(key)
        if (inflight.size === 0) {
          this.inflightHostedSearchCalls.delete(aiMessage.id)
          if (aiMessage.isSearching) {
            aiMessage.isSearching = false
            onAIMessageUpdated(aiMessage)
          } else if (partChanged) {
            onAIMessageUpdated(aiMessage)
          }
        } else if (partChanged) {
          onAIMessageUpdated(aiMessage)
        }
      } else if (aiMessage.isSearching) {
        // 兜底: 没有 in-flight 记录但状态仍是 searching, 直接关闭
        aiMessage.isSearching = false
        onAIMessageUpdated(aiMessage)
      } else if (partChanged) {
        onAIMessageUpdated(aiMessage)
      }
    } else if (kind === HostedResponsesToolEventKind.IMAGE_GENERATION_STARTED ||
      kind === HostedResponsesToolEventKind.IMAGE_GENERATION_PARTIAL) {
      // 生图 STARTED / PARTIAL: 落一个独立 TOOL part (toolCallId='hig_<itemId>') 让 timeline 显示 "生成图片中",
      // 同时把 parts 撑非空, 把 MessageBubble TypingIndicator (Bubble Dots) 自然顶掉; 否则模型在该轮里若
      // 不出 reasoning/text, parts 会一直空, Bubble Dots 会从生图开始一直转到 stream completed (复盘
      // 2026-05-23 gpt-5.5 生图后 5 秒空转就是这条路径)。
      const key = this.buildOpenAIResponsesItemKey(event.itemId, event.outputIndex)
      let inflight = this.inflightHostedImageGenCalls.get(aiMessage.id)
      if (inflight === undefined) {
        inflight = new Set<string>()
        this.inflightHostedImageGenCalls.set(aiMessage.id, inflight)
      }
      inflight.add(key)
      const changed = this.upsertHostedImageGenPart(
        aiMessage,
        key,
        event.outputIndex,
        ToolPartStatus.RUNNING,
        event.partialIndex
      )
      console.info('ChatViewModel',
        `[ResponsesHostedTool] ${kind} item=${event.itemId} output=${event.outputIndex} ` +
        `partial=${event.partialIndex} inflight=${inflight.size} partChanged=${changed}`)
      if (changed) {
        onAIMessageUpdated(aiMessage)
      }
    } else if (kind === HostedResponsesToolEventKind.IMAGE_GENERATION_COMPLETED) {
      // 生图 COMPLETED: 把 TOOL part 置 SUCCEEDED, 清掉 inflight 记录。
      // 注意: 这里不动 aiMessage.isGenerating, 让 finalizeAIMessage 在 stream completed 时统一收;
      // 但 parts 已经非空, Bubble Dots 不会再出现, 哪怕后续服务端继续 echo 几 MB base64 也不影响 UX。
      const key = this.buildOpenAIResponsesItemKey(event.itemId, event.outputIndex)
      const partChanged = this.upsertHostedImageGenPart(
        aiMessage,
        key,
        event.outputIndex,
        ToolPartStatus.SUCCEEDED,
        -1
      )
      const inflight = this.inflightHostedImageGenCalls.get(aiMessage.id)
      let inflightSize = -1
      if (inflight !== undefined) {
        inflight.delete(key)
        inflightSize = inflight.size
        if (inflight.size === 0) {
          this.inflightHostedImageGenCalls.delete(aiMessage.id)
        }
      }
      console.info('ChatViewModel',
        `[ResponsesHostedTool] ${kind} item=${event.itemId} output=${event.outputIndex} ` +
        `inflight=${inflightSize} partChanged=${partChanged}`)
      if (partChanged) {
        onAIMessageUpdated(aiMessage)
      }
    } else {
      console.info('ChatViewModel',
        `[ResponsesHostedTool] ${kind} item=${event.itemId} output=${event.outputIndex} partial=${event.partialIndex}`)
    }
  }

  // 每次 hosted web_search_call 占用一个独立的 TOOL part, key=hws_<itemId>。
  // - 首次出现: 插到当前活跃 reasoning/text 之前, 不复用任何已有 part
  // - 后续事件: 仅在 part 上覆盖 query/url/status, 不影响其它 part
  // 返回 true 表示真的有改动, 调用方可据此决定是否触发 UI 刷新。
  private upsertHostedWebSearchPart(
    aiMessage: ChatMessage,
    itemKey: string,
    outputIndex: number,
    query: string,
    url: string,
    actionType: string,
    queries: string[],
    status: string
  ): boolean {
    const partId = this.buildOpenAIResponsesHostedPartId(OPENAI_RESPONSES_WEB_SEARCH_PREFIX, itemKey)
    const trimmedQuery = query.trim()
    const trimmedUrl = url.trim()
    const trimmedActionType = actionType.trim()

    let part: MessagePart | null = null
    const partIndex = this.findOpenAIResponsesHostedToolPartIndex(
      aiMessage,
      partId,
      itemKey,
      outputIndex,
      OPENAI_RESPONSES_WEB_SEARCH_LABEL
    )
    if (partIndex >= 0) {
      part = aiMessage.parts[partIndex]
    }

    let changed = false
    const fallbackSequence = part !== null && part.sourceSequence >= 0 ?
      part.sourceSequence : this.nextOpenAIResponsesFallbackSequence(aiMessage)
    const sourceSequence = this.buildOpenAIResponsesSourceSequence(
      outputIndex,
      OPENAI_RESPONSES_TOOL_SEQUENCE_OFFSET,
      fallbackSequence
    )
    if (part === null) {
      part = new MessagePart(MessagePartKind.TOOL)
      part.toolCallId = partId
      // 'web_search' 已经被 isSearchWebFunctionName 识别为搜索类工具, 复用 timeline 已有搜索 step 渲染
      part.toolName = 'web_search'
      part.toolDisplayName = OPENAI_RESPONSES_WEB_SEARCH_LABEL
      part.toolArguments = this.buildHostedWebSearchArguments(trimmedQuery, trimmedUrl, trimmedActionType, queries)
      part.toolSourceType = ToolSourceType.BUILTIN
      part.toolSourceLabel = OPENAI_RESPONSES_WEB_SEARCH_LABEL
      part.toolPermissionLevel = ToolPermissionLevel.READ
      part.toolStatus = status
      this.syncOpenAIResponsesPartSource(part, itemKey, outputIndex, -1, sourceSequence)
      // 注意: hosted url_citation 没有 search_call_id 归属, 这里不写 toolSearchReferences,
      // 让 message.searchReferences 聚合卡片兜底展示全部引用。
      this.insertOpenAIResponsesTimelinePart(aiMessage, part)
      changed = true
    } else {
      if (this.syncOpenAIResponsesPartSource(part, itemKey, outputIndex, -1, sourceSequence)) {
        changed = true
      }
      if (part.toolCallId !== partId) {
        part.toolCallId = partId
        changed = true
      }
      if (part.toolName !== 'web_search') {
        part.toolName = 'web_search'
        changed = true
      }
      // 已有 part: 标题保持工具名, query / url / action 只写入 arguments, 供展开态查看。
      if (part.toolDisplayName !== OPENAI_RESPONSES_WEB_SEARCH_LABEL) {
        part.toolDisplayName = OPENAI_RESPONSES_WEB_SEARCH_LABEL
        changed = true
      }
      if (part.toolSourceType !== ToolSourceType.BUILTIN) {
        part.toolSourceType = ToolSourceType.BUILTIN
        changed = true
      }
      if (part.toolSourceLabel !== OPENAI_RESPONSES_WEB_SEARCH_LABEL) {
        part.toolSourceLabel = OPENAI_RESPONSES_WEB_SEARCH_LABEL
        changed = true
      }
      if (part.toolPermissionLevel !== ToolPermissionLevel.READ) {
        part.toolPermissionLevel = ToolPermissionLevel.READ
        changed = true
      }
      if (trimmedQuery !== '' || trimmedUrl !== '') {
        const nextArguments = this.buildHostedWebSearchArguments(trimmedQuery, trimmedUrl, trimmedActionType, queries)
        if (nextArguments !== part.toolArguments) {
          part.toolArguments = nextArguments
          changed = true
        }
      } else if (trimmedActionType !== '' || queries.length > 0) {
        const nextArguments = this.buildHostedWebSearchArguments(trimmedQuery, trimmedUrl, trimmedActionType, queries)
        if (nextArguments !== part.toolArguments) {
          part.toolArguments = nextArguments
          changed = true
        }
      }
      if (part.toolStatus !== status) {
        part.toolStatus = status
        changed = true
      }
      if (changed) {
        this.repositionOpenAIResponsesTimelinePart(aiMessage, part)
      }
    }
    return changed
  }

  // open_page itemId 跨事件阶段记忆: STARTED 阶段判定后入集合, SEARCHING/COMPLETED 阶段查集合走快路径。
  // 这里只做"记/查/忘"三个 primitive, 业务策略在 handleHostedResponsesToolEvent 里。
  private isOpenPageRecorded(messageId: string, itemKey: string): boolean {
    const set = this.openPageHostedItemIds.get(messageId)
    return set !== undefined && set.has(itemKey)
  }

  private rememberOpenPageItem(messageId: string, itemKey: string): void {
    let set = this.openPageHostedItemIds.get(messageId)
    if (set === undefined) {
      set = new Set<string>()
      this.openPageHostedItemIds.set(messageId, set)
    }
    set.add(itemKey)
  }

  private forgetOpenPageItem(messageId: string, itemKey: string): void {
    const set = this.openPageHostedItemIds.get(messageId)
    if (set === undefined) {
      return
    }
    set.delete(itemKey)
    if (set.size === 0) {
      this.openPageHostedItemIds.delete(messageId)
    }
  }

  // 每个 hosted image_generation_call 占一个独立 TOOL part, key=hig_<itemId>。
  // - 首次出现: 插到当前活跃 reasoning/text 之前, status=RUNNING, 避免正文流式块把工具行夹在中间
  // - 后续 partial / completed: 仅更新 toolStatus 与 partial 序号; 不重建 part
  // 关键作用: 把 aiMessage.parts 撑非空, 顶掉 MessageBubble 的 Bubble Dots 等待动画。
  // 返回 true 表示有改动, 调用方据此决定是否触发 UI 刷新。
  private upsertHostedImageGenPart(
    aiMessage: ChatMessage,
    itemKey: string,
    outputIndex: number,
    status: string,
    partialIndex: number
  ): boolean {
    const partId = this.buildOpenAIResponsesHostedPartId(OPENAI_RESPONSES_IMAGE_GENERATION_PREFIX, itemKey)

    let part: MessagePart | null = null
    const partIndex = this.findOpenAIResponsesHostedToolPartIndex(
      aiMessage,
      partId,
      itemKey,
      outputIndex,
      OPENAI_RESPONSES_IMAGE_GENERATION_LABEL
    )
    if (partIndex >= 0) {
      part = aiMessage.parts[partIndex]
    }

    let changed = false
    const fallbackSequence = part !== null && part.sourceSequence >= 0 ?
      part.sourceSequence : this.nextOpenAIResponsesFallbackSequence(aiMessage)
    const sourceSequence = this.buildOpenAIResponsesSourceSequence(
      outputIndex,
      OPENAI_RESPONSES_TOOL_SEQUENCE_OFFSET,
      fallbackSequence
    )
    const nextArguments = partialIndex >= 0 ? `{"partial":${partialIndex}}` : '{}'
    if (part === null) {
      part = new MessagePart(MessagePartKind.TOOL)
      part.toolCallId = partId
      part.toolName = 'image_generation'
      part.toolDisplayName = OPENAI_RESPONSES_IMAGE_GENERATION_LABEL
      part.toolArguments = nextArguments
      part.toolSourceType = ToolSourceType.BUILTIN
      part.toolSourceLabel = OPENAI_RESPONSES_IMAGE_GENERATION_LABEL
      part.toolPermissionLevel = ToolPermissionLevel.READ
      part.toolStatus = status
      this.syncOpenAIResponsesPartSource(part, itemKey, outputIndex, -1, sourceSequence)
      this.insertOpenAIResponsesTimelinePart(aiMessage, part)
      changed = true
    } else {
      if (this.syncOpenAIResponsesPartSource(part, itemKey, outputIndex, -1, sourceSequence)) {
        changed = true
      }
      if (part.toolCallId !== partId) {
        part.toolCallId = partId
        changed = true
      }
      if (part.toolName !== 'image_generation') {
        part.toolName = 'image_generation'
        changed = true
      }
      if (part.toolDisplayName !== OPENAI_RESPONSES_IMAGE_GENERATION_LABEL) {
        part.toolDisplayName = OPENAI_RESPONSES_IMAGE_GENERATION_LABEL
        changed = true
      }
      if (part.toolSourceType !== ToolSourceType.BUILTIN) {
        part.toolSourceType = ToolSourceType.BUILTIN
        changed = true
      }
      if (part.toolSourceLabel !== OPENAI_RESPONSES_IMAGE_GENERATION_LABEL) {
        part.toolSourceLabel = OPENAI_RESPONSES_IMAGE_GENERATION_LABEL
        changed = true
      }
      if (part.toolPermissionLevel !== ToolPermissionLevel.READ) {
        part.toolPermissionLevel = ToolPermissionLevel.READ
        changed = true
      }
      if (nextArguments !== part.toolArguments) {
        part.toolArguments = nextArguments
        changed = true
      }
      if (part.toolStatus !== status) {
        part.toolStatus = status
        changed = true
      }
      if (changed) {
        this.repositionOpenAIResponsesTimelinePart(aiMessage, part)
      }
    }
    return changed
  }

  // 构造 hosted web_search part 的 toolArguments JSON, 让 MessageBubble 展示本次 OpenAI action/request。
  private buildHostedWebSearchArguments(query: string, url: string, actionType: string, queries: string[]): string {
    if (query === '' && url === '' && actionType === '' && queries.length === 0) {
      return '{}'
    }
    interface HostedSearchArgs {
      tool?: string
      action?: string
      query?: string
      queries?: string[]
      url?: string
    }
    const payload: HostedSearchArgs = { tool: 'web_search' }
    if (actionType !== '') {
      payload.action = actionType
    }
    if (query !== '') {
      payload.query = query
    }
    if (queries.length > 0) {
      payload.queries = queries.slice()
    }
    if (url !== '') {
      payload.url = url
    }
    return JSON.stringify(payload)
  }

  private async waitForAIGeneratedImageSaves(pendingImageSaves: Promise<void>[]): Promise<void> {
    for (let i = 0; i < pendingImageSaves.length; i++) {
      await pendingImageSaves[i]
    }
  }

  private getCancelledToolResultMessage(toolResults: ToolResult[]): string {
    for (let i = 0; i < toolResults.length; i++) {
      const info: CancelledToolResultInfo = isCancelledToolResult(toolResults[i])
      if (!info.cancelled) {
        continue
      }
      if (info.reason !== '') {
        return `工具调用已取消：${info.reason}`
      }
      return '工具调用已取消，未生成最终回复'
    }
    return ''
  }

  private appendInterruptionTextIfNeeded(aiMessage: ChatMessage, message: string): void {
    if (message.trim() === '' || aiMessage.content.trim() !== '') {
      return
    }
    aiMessage.content = message
    this.pushPartText(aiMessage, message)
  }

  private async persistToolEvents(
    snapshotSessionId: string,
    snapshotSession: ChatSession | null,
    aiMessage: ChatMessage,
    toolCalls: ToolCall[],
    toolResults: ToolResult[]
  ): Promise<void> {
    if (snapshotSession === null) {
      return
    }
    for (let i = 0; i < toolCalls.length; i++) {
      const result = i < toolResults.length ? toolResults[i] : null
      const status = result !== null ? (result.isError ? 'failed' : 'completed') : 'pending'
      await this.databaseService.saveToolEvent(
        snapshotSessionId,
        aiMessage.id,
        toolCalls[i].id,
        toolCalls[i].functionName,
        toolCalls[i].displayName,
        toolCalls[i].sourceLabel,
        toolCalls[i].sourceType,
        toolCalls[i].permissionLevel,
        toolCalls[i].arguments,
        result !== null ? result.content : '',
        status
      )
    }
  }

  private async failAIMessage(
    aiMessage: ChatMessage,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onError: (error: string) => void | Promise<void>,
    snapshotSessionId: string,
    snapshotSession: ChatSession | null,
    requestId: string,
    errorMessage: string
  ): Promise<void> {
    this.appendInterruptionTextIfNeeded(aiMessage, errorMessage)
    this.fillEmptyAIContentPlaceholder(aiMessage, errorMessage)
    aiMessage.isGenerating = false
    aiMessage.isSearching = false
    onAIMessageUpdated(aiMessage)

    try {
      if (snapshotSession !== null) {
        await this.databaseService.addMessage(snapshotSessionId, aiMessage)
        this.appendMessageToSessionIfMissing(snapshotSession, aiMessage)
        this.markPendingAIMessagePersisted(aiMessage.id)
      }
    } catch (persistError) {
      console.error('ChatViewModel', `Failed to persist AI message in failAIMessage: ${JSON.stringify(persistError)}`)
    } finally {
      this.clearPendingAIMessageIfMatches(aiMessage.id)
      this.unregisterActiveRequest(requestId)
      await onError(errorMessage)
    }
  }

  // 工具调用循环
  //
  // 重要: 这里曾经是"onComplete 内 await this.executeToolCallLoop(...)"的递归实现,
  // 每多一轮工具调用就多一层 await + 一份闭包(roundStreamingToolCalls/upsertRoundToolPart 等),
  // 20+ 轮时栈和闭包累积可导致 native OOM kill(无日志的应用闪退)以及 UI 刷新调度阻塞。
  // 现在改成 while 迭代: 把每轮 streamChatRequestWithTools 的 callback 包装成
  // Promise<ToolStreamRoundOutcome>, 上层根据 outcome 决定继续工具/finalize/报错,
  // 每轮闭包在迭代结束后即可 GC, 栈深度保持常数。
  private async executeToolCallLoop(
    apiConfig: AIApiConfig,
    requestMessages: RequestMessage[],
    modelId: string,
    aiMessage: ChatMessage,
    onAIMessageUpdated: (message: ChatMessage) => void,
    onComplete: () => void,
    onError: (error: string) => void | Promise<void>,
    tools: ToolDefinition[],
    toolCallbacks: ToolCallCallbacks | undefined,
    reasoningLevel: ReasoningLevel,
    requestTemperature: number | undefined,
    initialToolStepIndex: number,
    snapshotSessionId: string,
    snapshotSession: ChatSession | null,
    shouldAutoGenerateTitle: boolean,
    requestId: string,
    isCancelledFn: () => boolean,
    isUserCancelledFn: () => boolean,
    isToolCancelledFn: () => boolean,
    setUserCancelled: (v: boolean) => void,
    getHasReceivedFirstChunk: () => boolean,
    setHasReceivedFirstChunk: (v: boolean) => void,
    localFirstChunkThrottle: StreamFlusher,
    localContentThrottle: StreamFlusher,
    localReasoningThrottle: StreamFlusher,
    builtInResponsesTools?: BuiltInResponsesToolSpec[],
    builtInResponsesToolChoice?: OpenAIResponsesToolChoice
  ): Promise<void> {
    let toolStepIndex = initialToolStepIndex
    const pendingImageSaves: Promise<void>[] = []
    while (true) {
      if (isCancelledFn()) {
        return
      }

      const toolsEnabledInThisRound = toolStepIndex < this.MAX_TOOL_STEPS
      if (!toolsEnabledInThisRound) {
        console.warn('ChatViewModel', `Max tool steps (${this.MAX_TOOL_STEPS}) reached, forcing final answer without tools`)
      }
      console.info('ChatViewModel', `Tool step ${toolStepIndex + 1}`)

      // 每轮独立闭包变量 (while 迭代结束自动 GC, 不会像递归那样跨轮累积)
      let toolContinuationContent = ''
      let toolContinuationReasoningContent = ''
      let roundHasToolCallDelta = false
      let streamedContentLength = 0
      let streamedReasoningLength = 0
      const roundStreamingToolCalls: Map<number, ToolCall> = new Map()
      const roundToolPartIndexes: Map<number, number> = new Map()

      const markCurrentRoundAsToolCall = (): void => {
        if (roundHasToolCallDelta) {
          return
        }
        roundHasToolCallDelta = true
        if (streamedContentLength > 0 && aiMessage.content.length >= streamedContentLength) {
          toolContinuationContent = aiMessage.content.substring(aiMessage.content.length - streamedContentLength)
        }
        if (streamedReasoningLength > 0 && aiMessage.reasoningContent.length >= streamedReasoningLength) {
          toolContinuationReasoningContent = aiMessage.reasoningContent.substring(
            aiMessage.reasoningContent.length - streamedReasoningLength
          )
        }
        this.finishTrailingReasoningPart(aiMessage)
        onAIMessageUpdated(aiMessage)
      }

      const upsertRoundToolPart = (delta: ToolCallDelta): void => {
        let toolCall = roundStreamingToolCalls.get(delta.index)
        if (toolCall === undefined) {
          toolCall = new ToolCall('', '', '')
          roundStreamingToolCalls.set(delta.index, toolCall)
        }
        this.applyToolCallDelta(toolCall, delta)

        const existingPartIndex = roundToolPartIndexes.get(delta.index)
        if (existingPartIndex !== undefined && existingPartIndex >= 0 && existingPartIndex < aiMessage.parts.length) {
          const existingPart = aiMessage.parts[existingPartIndex]
          if (existingPart.kind === MessagePartKind.TOOL) {
            this.syncToolPartFromToolCall(existingPart, toolCall)
            return
          }
        }

        this.finishTrailingReasoningPart(aiMessage)
        const part = createToolPart(toolCall, null)
        aiMessage.parts = aiMessage.parts.concat([part])
        roundToolPartIndexes.set(delta.index, aiMessage.parts.length - 1)
      }

      const appendRoundReasoning = (content: string): void => {
        if (content === '') {
          return
        }
        aiMessage.reasoningContent += content
        this.pushPartReasoning(aiMessage, content)
        if (!roundHasToolCallDelta) {
          streamedReasoningLength += content.length
        }
        onAIMessageUpdated(aiMessage)
      }

      const flushPendingRoundReasoning = (): void => {
        localReasoningThrottle.flush((throttledReasoning: string) => {
          if (isCancelledFn()) {
            return
          }
          appendRoundReasoning(throttledReasoning)
        })
      }

      const appendRoundContent = (content: string): void => {
        if (content === '') {
          return
        }
        flushPendingRoundReasoning()
        aiMessage.content += content
        this.pushPartText(aiMessage, content)
        if (!roundHasToolCallDelta) {
          streamedContentLength += content.length
        }
        onAIMessageUpdated(aiMessage)
      }

      const flushPendingRoundContent = (): void => {
        this.flushStreamContentFlushers(
          localFirstChunkThrottle,
          localContentThrottle,
          isCancelledFn,
          appendRoundContent
        )
      }

      if (isToolCancelledFn()) {
        console.info('ChatViewModel', 'Tool execution cancelled by user')
        aiMessage.isGenerating = false
        onAIMessageUpdated(aiMessage)
        this.resetStreamFlushers(localFirstChunkThrottle, localContentThrottle, localReasoningThrottle)
        onComplete()
        // 必须释放占位 / 上一轮残留的 httpRequest, 否则取消后 native 句柄留挂在 activeRequests
        this.unregisterActiveRequest(requestId)
        return
      }

      this.toolExecutionService.setCancelCheckCallback(isToolCancelledFn)

      // 把单轮 streamChat 的 callback 化接口包成 Promise:
      // - onComplete(toolCalls) → resolve({toolCalls, ...})
      // - onError(error)        → resolve({hasError: true, error, ...})
      // 之后外层根据 outcome 在 while 迭代里做 finalize / 工具执行 / 错误处理。
      // Promise executor 是同步的, 不能在里面 await, 所以在循环每轮开始前先解析一次 effective
      // max output tokens 再传进 streamChatRequestWithTools。
      const roundMaxOutputTokens = await this.resolveEffectiveMaxOutputTokens()
      const outcome: ToolStreamRoundOutcome = await new Promise<ToolStreamRoundOutcome>((resolve) => {
        const httpRequest = this.aiApiService.streamChatRequestWithTools(
          apiConfig,
          requestMessages,
          modelId,
          (contentChunk: string) => {
            this.throttleStreamContentChunk(
              contentChunk,
              localFirstChunkThrottle,
              localContentThrottle,
              getHasReceivedFirstChunk,
              setHasReceivedFirstChunk,
              isCancelledFn,
              appendRoundContent
            )
          },
          (toolCalls: ToolCall[]) => {
            if (isCancelledFn()) {
              resolve({
                toolCalls: [],
                toolContinuationContent: '',
                toolContinuationReasoningContent: '',
                hasError: false,
                error: ''
              })
              return
            }
            flushPendingRoundReasoning()
            flushPendingRoundContent()
            setHasReceivedFirstChunk(false)
            if (toolCalls.length > 0 && toolsEnabledInThisRound) {
              markCurrentRoundAsToolCall()
            }
            resolve({
              toolCalls: toolCalls,
              toolContinuationContent: toolContinuationContent,
              toolContinuationReasoningContent: toolContinuationReasoningContent,
              hasError: false,
              error: ''
            })
          },
          (error: string) => {
            if (isCancelledFn()) {
              resolve({
                toolCalls: [],
                toolContinuationContent: '',
                toolContinuationReasoningContent: '',
                hasError: false,
                error: ''
              })
              return
            }
            flushPendingRoundReasoning()
            flushPendingRoundContent()
            resolve({
              toolCalls: [],
              toolContinuationContent: '',
              toolContinuationReasoningContent: '',
              hasError: true,
              error: error
            })
          },
          requestTemperature,
          roundMaxOutputTokens,
          (reasoningContent: string) => {
            if (isCancelledFn()) {
              return
            }
            localReasoningThrottle.throttle(reasoningContent, (throttledContent: string) => {
              if (isCancelledFn()) {
                return
              }
              appendRoundReasoning(throttledContent)
            })
          },
          (base64Data: string, mimeType: string, isPartial: boolean) => {
            if (isCancelledFn()) {
              return
            }
            if (isPartial) {
              return
            }
            this.trackAIGeneratedImageSave(pendingImageSaves, base64Data, mimeType, aiMessage, onAIMessageUpdated)
          },
          reasoningLevel,
          toolsEnabledInThisRound ? tools : undefined,
          builtInResponsesToolChoice,
          (toolCallDeltas: ToolCallDelta[]) => {
            if (isCancelledFn() || !toolsEnabledInThisRound || toolCallDeltas.length <= 0) {
              return
            }
            flushPendingRoundReasoning()
            flushPendingRoundContent()
            markCurrentRoundAsToolCall()
            for (let i = 0; i < toolCallDeltas.length; i++) {
              upsertRoundToolPart(toolCallDeltas[i])
            }
            onAIMessageUpdated(aiMessage)
          },
          builtInResponsesTools,
          (refs: SearchReference[]) => {
            if (isCancelledFn()) {
              return
            }
            this.appendBuiltinSearchReferences(aiMessage, refs, onAIMessageUpdated)
          },
          (event: HostedResponsesToolEvent) => {
            if (isCancelledFn()) {
              return
            }
            this.handleHostedResponsesToolEvent(aiMessage, event, onAIMessageUpdated)
          },
          this.createAIGeneratedImageFileCallbacks(
            pendingImageSaves,
            aiMessage,
            onAIMessageUpdated,
            isCancelledFn
          )
        )

        // 更新活跃请求中的 httpRequest 引用(每轮 stream 可能创建新的 httpRequest)。
        // 必须 destroy 上一轮的 httpRequest (sendMessageWithTools 创建的 placeholderHttp,
        // 或上一轮工具循环里的真实 httpRequest), 否则每轮泄漏一个 native HttpRequest 实例,
        // 多轮工具调用 + 深度推理会累积到触发 native OOM kill。
        // registerActiveRequest 内部已经做了 destroy 覆盖, 这里走它统一入口避免遗漏。
        const existingInfo = this.activeRequests.get(requestId)
        if (existingInfo !== undefined) {
          if (existingInfo.httpRequest !== httpRequest) {
            try {
              existingInfo.httpRequest.destroy()
            } catch (_e) {
              // ignore: 已被 streamPost 内部 destroy 或被 stopGeneration 提前 destroy
            }
          }
          existingInfo.httpRequest = httpRequest
        } else {
          this.registerActiveRequest(requestId, httpRequest, () => {
            // cancel 回调由 sendMessageWithTools 中注册的回调处理
          }, snapshotSessionId)
        }
      })

      // ===== 处理 outcome =====
      if (isCancelledFn()) {
        return
      }

      if (outcome.hasError) {
        this.fillEmptyAIContentPlaceholder(aiMessage, outcome.error)
        aiMessage.isGenerating = false
        aiMessage.isSearching = false
        onAIMessageUpdated(aiMessage)
        this.resetStreamFlushers(localFirstChunkThrottle, localContentThrottle, localReasoningThrottle)
        this.clearPendingAIMessageIfMatches(aiMessage.id)
        this.unregisterActiveRequest(requestId)
        if (isUserCancelledFn()) {
          setUserCancelled(false)
          console.info('ChatViewModel', 'Request cancelled by user')
          onComplete()
        } else {
          await onError(outcome.error)
        }
        return
      }

      const toolCalls = outcome.toolCalls

      if (toolCalls.length === 0 || !toolsEnabledInThisRound) {
        if (toolCalls.length > 0) {
          console.warn('ChatViewModel', `Ignored ${toolCalls.length} tool calls because tool round limit is reached`)
        }
        this.resetStreamFlushers(localFirstChunkThrottle, localContentThrottle, localReasoningThrottle)
        await this.finalizeAIMessage(
          aiMessage,
          onAIMessageUpdated,
          onComplete,
          snapshotSessionId,
          snapshotSession,
          shouldAutoGenerateTitle,
          requestId,
          pendingImageSaves
        )
        return
      }

      // 有工具调用要执行
      console.info('ChatViewModel', `[Function Calling] Received ${toolCalls.length} tool calls`)
      const latestUserQuery = this.getLatestUserQueryFromRequestMessages(requestMessages)

      // 同步 toolCalls 到 aiMessage.toolCalls 和 parts
      for (let i = 0; i < toolCalls.length; i++) {
        if (this.isWebSearchFunction(toolCalls[i].functionName)) {
          const normalizedSearchQuery = this.normalizeSearchToolCallArguments(toolCalls[i], latestUserQuery)
          if (normalizedSearchQuery !== '') {
            console.info('ChatViewModel',
              `[Function Calling] normalized search tool request="${normalizedSearchQuery}"`)
          }
        }
        aiMessage.toolCalls.push(toolCalls[i])

        let synced = false
        const partIndex = roundToolPartIndexes.get(i)
        if (partIndex !== undefined && partIndex >= 0 && partIndex < aiMessage.parts.length) {
          const part = aiMessage.parts[partIndex]
          if (part.kind === MessagePartKind.TOOL) {
            this.syncToolPartFromToolCall(part, toolCalls[i])
            synced = true
          }
        }
        if (!synced && toolCalls[i].id !== '') {
          for (let j = 0; j < aiMessage.parts.length; j++) {
            const part = aiMessage.parts[j]
            if (part.kind === MessagePartKind.TOOL && part.toolCallId === toolCalls[i].id) {
              this.syncToolPartFromToolCall(part, toolCalls[i])
              synced = true
              break
            }
          }
        }
        if (!synced) {
          this.pushToolPart(aiMessage, toolCalls[i])
        }
      }
      onAIMessageUpdated(aiMessage)

      if (toolCallbacks !== undefined && toolCallbacks.onToolCallStarted !== undefined) {
        toolCallbacks.onToolCallStarted(toolCalls)
      }

      // 搜索工具状态
      for (let i = 0; i < toolCalls.length; i++) {
        if (this.isWebSearchFunction(toolCalls[i].functionName)) {
          aiMessage.searchSource = 'tool'
          aiMessage.isSearching = true
          this.markToolPartRunningByCall(aiMessage, toolCalls[i])
          try {
            const searchRequestText = this.extractSearchToolRequestText(toolCalls[i])
            aiMessage.searchQuery = searchRequestText
            console.info('ChatViewModel',
              `[Function Calling] ${toolCalls[i].functionName}(request="${searchRequestText}")`)
            if (toolCallbacks !== undefined && toolCallbacks.onSearching !== undefined) {
              toolCallbacks.onSearching(searchRequestText)
            }
          } catch (e) {
            console.warn('ChatViewModel', `Failed to parse search tool args: ${JSON.stringify(e)}`)
          }
          onAIMessageUpdated(aiMessage)
          break
        }
      }

      // 执行工具调用
      const toolResults = await this.toolExecutionService.executeToolCalls(
        toolCalls,
        new ToolExecutionContext(snapshotSessionId, snapshotSession !== null ? snapshotSession.title : '')
      )
      if (isCancelledFn()) {
        // stopGeneration 已经触发, 它内部会 destroy + unregister, 这里直接 return
        return
      }

      const cancelledToolMessage = this.getCancelledToolResultMessage(toolResults)
      if (cancelledToolMessage !== '') {
        console.info('ChatViewModel', 'Tool execution was cancelled')
        for (let i = 0; i < toolCalls.length; i++) {
          this.syncToolPartByCall(aiMessage, toolCalls[i])
        }
        for (let i = 0; i < toolResults.length; i++) {
          aiMessage.toolResults.push(toolResults[i])
          this.attachToolResultPart(aiMessage, toolResults[i])
        }
        onAIMessageUpdated(aiMessage)
        await this.persistToolEvents(snapshotSessionId, snapshotSession, aiMessage, toolCalls, toolResults)
        this.resetStreamFlushers(localFirstChunkThrottle, localContentThrottle, localReasoningThrottle)
        await this.failAIMessage(
          aiMessage,
          onAIMessageUpdated,
          onError,
          snapshotSessionId,
          snapshotSession,
          requestId,
          cancelledToolMessage
        )
        this.toolExecutionService.clearCancelCheckCallback()
        return
      }

      // 写入结果到 aiMessage
      for (let i = 0; i < toolCalls.length; i++) {
        this.syncToolPartByCall(aiMessage, toolCalls[i])
      }
      for (let i = 0; i < toolResults.length; i++) {
        aiMessage.toolResults.push(toolResults[i])
        this.attachToolResultPart(aiMessage, toolResults[i])
      }
      // 工具结果到达后立刻通知 UI 把 step 状态切到 succeeded/failed,
      // 不要等下面 saveToolEvent (await 持久化) 完才刷新 timeline
      onAIMessageUpdated(aiMessage)

      // 持久化工具事件
      if (isCancelledFn()) {
        return
      }
      await this.persistToolEvents(snapshotSessionId, snapshotSession, aiMessage, toolCalls, toolResults)

      // 处理搜索结果引用
      for (let i = 0; i < toolCalls.length; i++) {
        if (this.isWebSearchFunction(toolCalls[i].functionName)) {
          const result = toolResults[i]
          try {
            const searchData = JSON.parse(result.content) as SearchResultData
            if (searchData.results !== undefined) {
              if (searchData.query !== undefined && searchData.query !== '') {
                aiMessage.searchQuery = searchData.query
              }
              aiMessage.searchEngine = searchData.searchEngine || 'Web'
              aiMessage.searchSource = 'tool'
              if (searchData.query !== undefined && searchData.query !== '') {
                console.info('ChatViewModel', `[Function Calling] search tool result query="${searchData.query}"`)
              }
              const refsForThisCall: SearchReference[] = []
              for (let j = 0; j < searchData.results.length; j++) {
                const item = searchData.results[j]
                const ref = new SearchReference(
                  `ref_${Date.now()}_${j}`,
                  item.title,
                  item.url,
                  item.snippet
                )
                aiMessage.searchReferences.push(ref)
                refsForThisCall.push(ref)
              }
              if (refsForThisCall.length > 0) {
                for (let k = 0; k < aiMessage.parts.length; k++) {
                  const p = aiMessage.parts[k]
                  if (p.kind === MessagePartKind.TOOL && p.toolCallId === toolCalls[i].id) {
                    p.toolSearchReferences = refsForThisCall
                    break
                  }
                }
              }
            }
          } catch (e) {
            console.warn('ChatViewModel', `Failed to parse search result: ${JSON.stringify(e)}`)
          }
          aiMessage.isSearching = false
          break
        }
      }
      onAIMessageUpdated(aiMessage)

      if (toolCallbacks !== undefined && toolCallbacks.onToolCallCompleted !== undefined) {
        toolCallbacks.onToolCallCompleted(toolResults)
      }

      // 准备下一轮 requestMessages
      const assistantMsg = RequestMessage.createAssistantWithToolCalls(outcome.toolContinuationContent, toolCalls)
      assistantMsg.reasoningContent = outcome.toolContinuationReasoningContent
      requestMessages.push(assistantMsg)
      for (let i = 0; i < toolResults.length; i++) {
        const toolResultMsg = RequestMessage.createToolResultMessage(
          toolResults[i].toolCallId,
          toolResults[i].content
        )
        requestMessages.push(toolResultMsg)
      }

      toolStepIndex++
    }
  }

  // 根据 MIME 类型获取文件扩展名
  private getExtensionFromMimeType(mimeType: string): string {
    const mimeToExt: Record<string, string> = {
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'image/gif': '.gif',
      'image/webp': '.webp',
      'image/bmp': '.bmp'
    }
    return mimeToExt[mimeType] || '.png'
  }

  private isImageUrl(data: string): boolean {
    return data.startsWith('http://') || data.startsWith('https://')
  }

  private async downloadImageAsBase64(url: string): Promise<ImageDownloadResult> {
    const httpRequest = http.createHttp()
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 60000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      })
      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}`)
      }

      const buffer = response.result as ArrayBuffer
      const bytes = new Uint8Array(buffer)
      const base64Helper = new util.Base64Helper()
      const base64 = base64Helper.encodeToStringSync(bytes)

      let mimeType = 'image/png'
      const contentType = response.header?.['content-type'] as string | undefined
      if (contentType !== undefined && contentType !== '') {
        const semi = contentType.indexOf(';')
        mimeType = semi >= 0 ? contentType.substring(0, semi).trim() : contentType.trim()
      } else {
        const lowerUrl = url.toLowerCase()
        if (lowerUrl.includes('.jpg') || lowerUrl.includes('.jpeg')) {
          mimeType = 'image/jpeg'
        } else if (lowerUrl.includes('.webp')) {
          mimeType = 'image/webp'
        } else if (lowerUrl.includes('.gif')) {
          mimeType = 'image/gif'
        }
      }

      const result: ImageDownloadResult = { base64Data: base64, mimeType: mimeType }
      return result
    } catch (error) {
      console.error('ChatViewModel', `Download image failed: ${JSON.stringify(error)}`)
      throw new Error(`Download image failed: ${JSON.stringify(error)}`)
    } finally {
      httpRequest.destroy()
    }
  }

  async saveAIGeneratedImage(
    imageData: string,
    mimeType: string,
    aiMessage: ChatMessage,
    onAIMessageUpdated: (message: ChatMessage) => void
  ): Promise<void> {
    let finalBase64 = imageData
    let finalMimeType = mimeType

    if (this.isImageUrl(imageData)) {
      console.info('ChatViewModel', `Downloading image from URL: ${imageData.substring(0, 100)}...`)
      const downloaded = await this.downloadImageAsBase64(imageData)
      finalBase64 = downloaded.base64Data
      finalMimeType = downloaded.mimeType
    }

    console.info('ChatViewModel', `Saving AI generated image: ${finalMimeType}, size: ${finalBase64.length}`)

    const attachmentId = `ai_img_${Date.now()}`
    const ext = this.getExtensionFromMimeType(finalMimeType)
    const fileName = `generated_${Date.now()}${ext}`

    const attachment = new MessageAttachment(
      attachmentId,
      AttachmentType.IMAGE,
      fileName,
      '',
      finalMimeType,
      Math.floor(finalBase64.length * 0.75)
    )
    attachment.base64Data = finalBase64

    if (this.attachmentStorageService.isReady()) {
      const filePath = await this.attachmentStorageService.saveAttachment(attachment)
      attachment.filePath = filePath
      if (filePath !== '') {
        attachment.base64Data = ''
      }
      console.info('ChatViewModel', `AI generated image saved to: ${filePath}`)
    } else {
      console.warn('ChatViewModel', 'AttachmentStorageService not ready, image not persisted to file')
    }

    aiMessage.addAttachment(attachment)
    this.upsertGeneratedImagePart(aiMessage, attachment, '', -1)
    onAIMessageUpdated(aiMessage)
  }

  // 删除消息
  async deleteMessage(messageId: string): Promise<void> {
    await this.databaseService.deleteMessage(messageId)
    if (this.currentSession !== null) {
      const index = this.currentSession.messages.findIndex((m: ChatMessage) => m.id === messageId)
      if (index >= 0) {
        this.currentSession.messages.splice(index, 1)
        this.currentSession.messageCount = Math.max(0, this.currentSession.messageCount - 1)
      }
    }
  }

  // 批量删除消息（用于重新生成功能）
  async deleteMessagesFromIndex(messageIds: string[]): Promise<void> {
    await this.databaseService.deleteMessagesByIds(messageIds)
    if (this.currentSession !== null) {
      // 从 currentSession.messages 中移除这些消息
      for (let i = 0; i < messageIds.length; i++) {
        this.clearPendingAIMessageIfMatches(messageIds[i])
        const index = this.currentSession.messages.findIndex((m: ChatMessage) => m.id === messageIds[i])
        if (index >= 0) {
          this.currentSession.messages.splice(index, 1)
          this.currentSession.messageCount = Math.max(0, this.currentSession.messageCount - 1)
        }
      }
    }
  }

  // 更新消息内容
  async updateMessageContent(messageId: string, content: string): Promise<void> {
    await this.databaseService.updateMessageContent(messageId, content)
    if (this.currentSession !== null) {
      const index = this.currentSession.messages.findIndex((m: ChatMessage) => m.id === messageId)
      if (index >= 0) {
        this.currentSession.messages[index].content = content
      }
    }
  }

  // 更新消息内容和附件
  async updateMessageContentAndAttachments(
    messageId: string,
    content: string,
    attachments: MessageAttachment[]
  ): Promise<void> {
    // 更新数据库
    await this.databaseService.updateMessageContent(messageId, content)
    await this.databaseService.updateMessageAttachments(messageId, attachments)

    // 更新内存中的会话
    if (this.currentSession !== null) {
      const index = this.currentSession.messages.findIndex((m: ChatMessage) => m.id === messageId)
      if (index >= 0) {
        this.currentSession.messages[index].content = content
        this.currentSession.messages[index].attachments = attachments.slice()
      }
    }
  }

  // 添加消息到数据库
  async addMessage(message: ChatMessage): Promise<void> {
    if (this.currentSession === null) {
      console.error('ChatViewModel', 'Cannot add message: no current session')
      return
    }
    await this.databaseService.addMessage(this.currentSession.id, message)
  }

  // 取消活跃请求 + pending 工具交互的统一入口。scopedToSession=false 时清掉全部, 为 true 时
  // 只清匹配 sessionId 的, 这样 stopGeneration / cancelGenerationForMessageRewrite 全局/局部
  // 两条路径可以共用同一份 destroy + cancel 逻辑。
  private cancelActiveRequestsForScope(scopedToSession: boolean, sessionId?: string): void {
    if (!scopedToSession) {
      this.activeRequests.forEach((info: ActiveRequestInfo) => {
        info.cancelCallback()
        try {
          info.httpRequest.destroy()
        } catch (e) {
          // ignore destroy errors
        }
      })
      this.activeRequests.clear()
      // 全局停止: 直接拒绝所有 pending 工具交互, 不再绕一圈通过 activeRequests 反推 sessionId,
      // 避免漏掉 activeRequests 已被清空但 pending 还在的边界场景(例如工具一直在等用户授权,
      // 此时 stream 已完成 destroy 出 activeRequests, 但 pending Map 里还挂着)。
      this.toolExecutionService.cancelAllPendingInteractions()
      // 重置 AIApiService 的解析状态（MiniMax 缓冲区等）；per-session 不重置避免影响其它会话
      this.aiApiService.resetThinkingState()
    } else {
      const targetRequestIds: string[] = []
      this.activeRequests.forEach((info: ActiveRequestInfo, requestId: string) => {
        if (info.sessionId !== sessionId) {
          return
        }
        info.cancelCallback()
        try {
          info.httpRequest.destroy()
        } catch (e) {
          // ignore destroy errors
        }
        targetRequestIds.push(requestId)
      })
      for (let i = 0; i < targetRequestIds.length; i++) {
        this.activeRequests.delete(targetRequestIds[i])
      }
      if (sessionId !== undefined && sessionId !== '') {
        this.toolExecutionService.cancelPendingInteractionsForSession(sessionId)
      }
    }
  }

  // 停止生成。
  //
  // 调用语义:
  // - sessionId 为空/undefined 时全局停止, 推进 cancelToken, 清掉所有会话的请求/pending 工具交互;
  // - 指定 sessionId 时只取消该会话的请求与 pending 工具交互, 不动 cancelToken, 多会话并发时
  //   不会因为停止 B 把 A 一起干掉。
  //
  // 与 cancelGenerationForMessageRewrite 的差异:
  // - 本方法会先 persistPendingAIMessageIfNeeded(sessionId) 把已经累积的 AI 文本/工具事件
  //   存进 DB, 用户能在历史里看到"已生成的部分 + 中断"。
  // - cancelGenerationForMessageRewrite 不持久化, 因为编辑/重新生成立刻会把这条消息从 UI
  //   尾部删掉, 半截内容落库会变成"幽灵消息"。
  stopGeneration(sessionId?: string): void {
    const scopedToSession = sessionId !== undefined && sessionId !== ''

    // 取消令牌仅在全局停止时推进，否则会让其它会话尚未进入 registerActiveRequest 的请求被误判为已取消
    if (!scopedToSession) {
      this.cancelToken = this.cancelToken + 1
    }

    // 停止前持久化匹配作用域内的待处理 AI 消息
    this.persistPendingAIMessageIfNeeded(sessionId)
    this.cancelActiveRequestsForScope(scopedToSession, sessionId)

    console.info('ChatViewModel', `Generation stopped (scope=${scopedToSession ? sessionId : 'all'})`)
  }

  // 编辑 / 重新生成 / 删除会话前的取消生成路径, 不持久化半截 AI 消息。
  //
  // 与 stopGeneration 共用 cancelActiveRequestsForScope, 但走的是 discard 分支:
  // - discardPendingAIMessagesForScope 把 pendingAIMessages 中匹配会话直接丢弃,
  //   不会触发 databaseService.addMessage, 也不会让用户看到一条空 AI 消息;
  // - 之后 ChatPage 会立即从 UI 尾部删掉旧消息, 写入新 prompt, 不需要任何"中断态"展示。
  //
  // 不要在普通 stop 按钮场景调用这个方法, 否则用户会丢失工具事件 / 部分回复。
  cancelGenerationForMessageRewrite(sessionId?: string): void {
    const scopedToSession = sessionId !== undefined && sessionId !== ''
    if (!scopedToSession) {
      this.cancelToken = this.cancelToken + 1
    }
    this.discardPendingAIMessagesForScope(sessionId)
    this.cancelActiveRequestsForScope(scopedToSession, sessionId)
    console.info('ChatViewModel', `Generation cancelled for message rewrite (scope=${scopedToSession ? sessionId : 'all'})`)
  }

  // 检查是否有活跃的请求
  hasActiveRequest(): boolean {
    return this.activeRequests.size > 0
  }

  // 检查指定会话是否存在活跃请求（用于页面恢复后还原发送/停止按钮状态）
  hasActiveRequestForSession(sessionId: string): boolean {
    if (sessionId === '') {
      return false
    }
    let found = false
    this.pendingAIMessages.forEach((info: PendingAIMessageInfo) => {
      if (info.sessionId === sessionId && (info.message.isGenerating || info.message.isSearching)) {
        found = true
      }
    })
    return found
  }

  // 生成唯一ID
  private generateId(): string {
    return Date.now().toString() + Math.random().toString(36).substring(2, 9)
  }

  // 获取格式化的当前时间信息
  private getCurrentTimeContext(): string {
    return buildCurrentTimeContext()
  }

  private limitSearchContextForPrompt(content: string, maxChars: number): string {
    const trimmed = content.trim()
    if (trimmed.length <= maxChars) {
      return trimmed
    }
    return trimmed.substring(0, maxChars) + '\n\n[搜索上下文已截断]'
  }

  private isUrlLikeText(text: string): boolean {
    const trimmed = text.trim()
    if (trimmed === '' || /\s/.test(trimmed)) {
      return false
    }
    return /^https?:\/\/[^\s]+$/i.test(trimmed) ||
      /^[\w\-]+\.[\w\-]+(:\d+)?(\/[\w\-._~:/?#[\]@!$&'()*+,;=]*)?$/i.test(trimmed)
  }

  private buildSearchResultRequestContent(content: string, searchResult: SearchResult): string {
    if (this.isUrlLikeText(content) || this.isUrlLikeText(searchResult.query)) {
      const targetUrl = content.trim() !== '' ? content.trim() : searchResult.query.trim()
      if (this.isUrlFetchFailureContext(searchResult.contentForAI)) {
        return `请说明这个链接的读取结果：${targetUrl}`
      }
      return `请基于已抓取的网页内容分析这个链接：${targetUrl}`
    }
    return content
  }

  private isUrlFetchFailureContext(contentForAI: string): boolean {
    return contentForAI.includes('URL 读取结果:') && contentForAI.includes('状态: 失败')
  }

  private isWebSearchFunction(functionName: string): boolean {
    return isSearchToolFunctionName(functionName)
  }

  private getLatestUserQueryFromRequestMessages(requestMessages: RequestMessage[]): string {
    for (let i = requestMessages.length - 1; i >= 0; i--) {
      const msg = requestMessages[i]
      if (msg.role === 'user' && msg.content.trim() !== '') {
        return msg.content
      }
    }
    return ''
  }

  private extractSearchToolRequestText(toolCall: ToolCall): string {
    try {
      const args = JSON.parse(toolCall.arguments) as WebSearchArgs
      if (isScrapeWebFunctionName(toolCall.functionName)) {
        if (args.url !== undefined) {
          return args.url.trim()
        }
        if (args.query !== undefined) {
          return args.query.trim()
        }
        return ''
      }
      if (args.query !== undefined) {
        return args.query.trim()
      }
      if (args.url !== undefined) {
        return args.url.trim()
      }
      return ''
    } catch (error) {
      console.warn('ChatViewModel', `Failed to parse search tool args: ${JSON.stringify(error)}`)
      return ''
    }
  }

  private normalizeSearchToolCallArguments(toolCall: ToolCall, latestUserQuery: string): string {
    if (isScrapeWebFunctionName(toolCall.functionName)) {
      let parsedUrl = ''
      try {
        const args = JSON.parse(toolCall.arguments) as WebSearchArgs
        if (args.url !== undefined) {
          parsedUrl = args.url.trim()
        } else if (args.query !== undefined) {
          parsedUrl = args.query.trim()
        }
      } catch (error) {
        parsedUrl = ''
        console.warn('ChatViewModel', `Failed to parse scrape_web args before normalize: ${JSON.stringify(error)}`)
      }

      let finalUrl = parsedUrl
      if (finalUrl === '' && this.isUrlLikeText(latestUserQuery)) {
        finalUrl = latestUserQuery.trim()
      }
      toolCall.arguments = JSON.stringify({ url: finalUrl })
      return finalUrl
    }

    let parsedQuery = ''
    try {
      const args = JSON.parse(toolCall.arguments) as WebSearchArgs
      if (args.query !== undefined) {
        parsedQuery = this.cleanSearchQuery(args.query)
      } else if (args.url !== undefined) {
        parsedQuery = args.url.trim()
      }
    } catch (error) {
      parsedQuery = ''
      console.warn('ChatViewModel', `Failed to parse search tool args before normalize: ${JSON.stringify(error)}`)
    }

    let finalQuery = parsedQuery
    if (latestUserQuery !== '') {
      finalQuery = this.normalizeRelativeTimeForSearchQuery(latestUserQuery, parsedQuery)
    }
    if (finalQuery === '' && latestUserQuery !== '') {
      finalQuery = this.cleanSearchQuery(latestUserQuery)
    }

    toolCall.arguments = JSON.stringify({ query: finalQuery })
    return finalQuery
  }

  // 简单清洗搜索查询（去除口语化前缀、多余空格）
  cleanSearchQuery(query: string): string {
    return cleanSearchQueryShared(query)
  }

  normalizeRelativeTimeForSearchQuery(userQuery: string, candidateQuery: string): string {
    return normalizeRelativeTimeForSearchQueryShared(userQuery, candidateQuery)
  }

  // 设置标题生成回调
  setTitleCallbacks(callbacks: TitleGenerationCallbacks | null): void {
    this.titleCallbacks = callbacks
  }

  // 生成智能标题（带重试机制）
  private async generateSmartTitle(session: ChatSession, retryCount: number = 0): Promise<void> {
    // 通知开始生成
    if (this.titleCallbacks !== null && this.titleCallbacks.onTitleGenerating !== undefined) {
      this.titleCallbacks.onTitleGenerating(true)
    }

    try {
      // 构建对话内容
      let content = ''
      for (let i = 0; i < session.messages.length; i++) {
        const msg = session.messages[i]
        content += `${msg.role}: ${msg.content}\n`
      }

      // 调用 AI 任务服务生成标题（自动检测语言）
      const title = await this.aiTaskService.generateTitle(content)
      if (title !== '' && this.currentSession !== null && this.currentSession.id === session.id) {
        this.currentSession.title = title
        await this.databaseService.updateSessionTitle(this.currentSession.id, title)
        this.notifySessionListChanged()
        console.info('ChatViewModel', 'Smart title generated: ' + title)

        // 通知标题更新成功
        if (this.titleCallbacks !== null && this.titleCallbacks.onTitleUpdated !== undefined) {
          this.titleCallbacks.onTitleUpdated(title)
        }
      } else if (title === '') {
        // 生成失败（配置问题或 API 返回空），通知失败
        console.warn('ChatViewModel', 'Title generation returned empty string')
        if (this.titleCallbacks !== null && this.titleCallbacks.onTitleFailed !== undefined) {
          this.titleCallbacks.onTitleFailed()
        }
      }

      // 通知生成结束
      if (this.titleCallbacks !== null && this.titleCallbacks.onTitleGenerating !== undefined) {
        this.titleCallbacks.onTitleGenerating(false)
      }
    } catch (error) {
      console.error('ChatViewModel', 'Failed to generate smart title: ' + JSON.stringify(error))

      // 检查是否可以重试（网络错误等可重试，配置错误不重试）
      const errorStr = JSON.stringify(error)
      const isConfigError = errorStr.includes('API Key') || errorStr.includes('未配置') || errorStr.includes('not configured')

      if (!isConfigError && retryCount < this.MAX_TITLE_RETRY) {
        // 指数退避重试：2秒、4秒、8秒
        const delayMs = Math.pow(2, retryCount + 1) * 1000
        console.info('ChatViewModel', `Retrying title generation in ${delayMs}ms (attempt ${retryCount + 1}/${this.MAX_TITLE_RETRY})`)

        setTimeout(() => {
          this.generateSmartTitle(session, retryCount + 1)
        }, delayMs)
      } else {
        // 重试次数用尽或配置错误，通知失败
        if (this.titleCallbacks !== null && this.titleCallbacks.onTitleGenerating !== undefined) {
          this.titleCallbacks.onTitleGenerating(false)
        }
        if (this.titleCallbacks !== null && this.titleCallbacks.onTitleFailed !== undefined) {
          this.titleCallbacks.onTitleFailed()
        }
      }
    }
  }

  // 手动重新生成标题
  async regenerateTitle(): Promise<void> {
    if (this.currentSession === null) {
      return
    }
    if (this.currentSession.messages.length === 0) {
      console.warn('ChatViewModel', 'Cannot generate title: no messages in session')
      return
    }
    await this.generateSmartTitle(this.currentSession, 0)
  }

  // 手动更新会话标题
  async updateSessionTitle(title: string): Promise<void> {
    const updated = await this.sessionStore.updateCurrentSessionTitle(title)
    this.currentSession = this.sessionStore.getCurrentSession()
    if (!updated) {
      return
    }

    // 通知标题更新
    if (this.titleCallbacks !== null && this.titleCallbacks.onTitleUpdated !== undefined) {
      this.titleCallbacks.onTitleUpdated(title)
    }
  }

  // 获取当前会话标题
  getCurrentSessionTitle(): string {
    return this.sessionStore.getCurrentSessionTitle()
  }

  private getCurrentModelSupportsReasoning(providerId: string, modelId: string): boolean {
    const provider = this.providerViewModel.getProviderById(providerId)
    if (provider === null) {
      return false
    }

    for (let i = 0; i < provider.models.length; i++) {
      if (provider.models[i].id === modelId) {
        return getEffectiveCapabilities(provider.models[i]).supportsReasoning
      }
    }

    return false
  }

  private async prepareRequestHistoryAttachmentsIfNeeded(
    messages: RequestMessage[],
    includeHistoryAttachmentPayloads: boolean,
    currentAttachmentCount: number
  ): Promise<void> {
    if (!includeHistoryAttachmentPayloads) {
      console.info('ChatViewModel',
        `Skipped history attachment payloads because current request has ${currentAttachmentCount} attachment(s)`)
      return
    }
    await this.prepareHistoryAttachments(messages)
  }

  // 懒加载历史附件：请求上下文里保留哪些历史消息由助手上下文配置控制。
  // 附件大小/数量不在客户端额外截断，交给模型服务端按自身限制处理。
  private async prepareHistoryAttachments(messages: RequestMessage[]): Promise<void> {
    let loadedCount = 0
    let totalSize = 0

    // 从后向前扫描，优先补齐最近消息；不做客户端大小截断。
    for (let i = messages.length - 1; i >= 0; i--) {
      const msg = messages[i]
      if (msg.role === 'user' && msg.attachments.length > 0) {
        for (let j = 0; j < msg.attachments.length; j++) {
          const att = msg.attachments[j]
          if (att.parsedText !== '') {
            continue
          }
          const estimatedSize = att.size > 0 ? att.size : (1024 * 1024)
          if (att.base64Data !== '') {
            totalSize += estimatedSize
            continue
          }

          if (await this.ensureAttachmentBase64Data(att)) {
            totalSize += estimatedSize
          }
        }
        loadedCount++
      }
    }

    console.info('ChatViewModel', `Prepared history attachments: ${loadedCount} messages, ${totalSize} bytes`)
  }
}

let chatViewModelInstance: ChatViewModel | null = null

// 导出创建实例方法
export function createChatViewModel(): ChatViewModel {
  if (chatViewModelInstance === null) {
    chatViewModelInstance = new ChatViewModel()
  }
  return chatViewModelInstance
}
