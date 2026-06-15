import {
  ApiStyle,
  AttachmentType,
  ChatMessage,
  ChatSearchMode,
  MessageAttachment,
  ModelProvider,
  OpenAITransport,
  ReasoningLevel,
  ToolCall,
  ToolResult
} from '../../models/ChatModels'
import { ChatViewModel, ToolCallCallbacks } from '../../viewmodels/ChatViewModel'
import { ChatTaskOrchestratorService } from '../../services/ChatTaskOrchestratorService'
import { ToolRegistry } from '../../services/ToolRegistry'
import { WebSearchService } from '../../services/WebSearchService'
import {
  BuiltInResponsesToolKind,
  BuiltInResponsesToolSpec,
  OpenAIResponsesToolChoice
} from '../../services/AIApiService'
import { appendUniqueToolId } from './ChatToolIdHelper'
import { syncChatMessageFromSource } from './ChatMessageActionHelper'
import { validateProviderConfig } from '../../utils/ProviderValidationUtils'
import { getEffectiveCapabilities } from '../../utils/ModelCapabilityDeriver'
import {
  getCurrentModelVisionSupport,
  hasImageAttachment,
  isImageCapabilityError
} from '../../utils/VisionCompat'
import {
  LEGACY_WEB_SEARCH_TOOL_ID,
  SCRAPE_WEB_TOOL_ID,
  SEARCH_WEB_TOOL_ID,
  isSearchToolId
} from '../../utils/SearchToolIdentityUtils'

export class ChatSendPrepareResult {
  shouldSend: boolean = false
  messageContent: string = ''
  effectiveApiKey: string = ''
  currentProvider: ModelProvider | null = null
}

enum ChatExecutionPlanKind {
  PLAIN_DIRECT = 'plain_direct',
  TOOLS = 'tools',
  UNSUPPORTED_TOOLS = 'unsupported_tools'
}

class ChatExecutionPlan {
  kind: ChatExecutionPlanKind
  enabledToolIds: string[]
  learnToolsOnSuccess: boolean
  // OpenAI Responses 内置工具 (web_search / image_generation), 仅在 transport=responses 时下发
  builtInResponsesTools: BuiltInResponsesToolSpec[]
  builtInResponsesToolChoice?: OpenAIResponsesToolChoice
  // 函数调用工具的 tool_choice (Chat Completions / Responses API 均支持 string 形式),
  // 例: "required" = 强制至少一个函数调用。设 undefined 时走默认 auto。
  // 与 builtInResponsesToolChoice 互斥使用 (前者管函数工具, 后者管 hosted 工具), 由 ChatViewModel 合并。
  functionToolChoice?: string

  constructor(
    kind: ChatExecutionPlanKind,
    enabledToolIds: string[] = [],
    learnToolsOnSuccess: boolean = false,
    builtInResponsesTools: BuiltInResponsesToolSpec[] = [],
    builtInResponsesToolChoice?: OpenAIResponsesToolChoice,
    functionToolChoice?: string
  ) {
    this.kind = kind
    this.enabledToolIds = enabledToolIds
    this.learnToolsOnSuccess = learnToolsOnSuccess
    this.builtInResponsesTools = builtInResponsesTools
    this.builtInResponsesToolChoice = builtInResponsesToolChoice
    this.functionToolChoice = functionToolChoice
  }
}

export interface ChatSendFlowDependencies {
  chatViewModel: ChatViewModel
  messages: ChatMessage[]
  chatTaskOrchestrator: ChatTaskOrchestratorService
  toolRegistry: ToolRegistry
  webSearchService: WebSearchService
  getSessionId: () => string
  getSessionTitle: () => string
  getCurrentTaskId: () => string
  getCurrentModelId: () => string
  getCurrentModelName: () => string
  getMessages: () => ChatMessage[]
  getReasoningLevel: () => ReasoningLevel
  onClearComposer: () => void
  onBeforeSend: () => void
  onSetSending: (value: boolean) => void
  onSetCurrentTaskId: (taskId: string) => void
  onSyncMessages: (changedMessageId?: string) => void
  onScrollBottom: () => void
  onSetNewEmptySession: (value: boolean) => void
  onDraftCommitted: () => void
  onMarkAutoTaskCompleted: () => void
  onMarkAutoTaskFailed: (message: string) => void
  onShowError: (message: string | Resource) => void
  onShowToast: (message: string | Resource) => void
  onConfirmModelSupportsTools: (providerId: string, modelId: string) => Promise<void>
}

export class ChatSendFlow {
  private deps: ChatSendFlowDependencies

  constructor(deps: ChatSendFlowDependencies) {
    this.deps = deps
  }

  prepareSendRequest(
    inputText: string,
    pendingAttachmentCount: number,
    isSending: boolean,
    currentProvider: ModelProvider | null,
    currentModelId: string,
    canStartNewTask: boolean
  ): ChatSendPrepareResult {
    const result = new ChatSendPrepareResult()
    const messageContent = inputText.trim()
    if (messageContent === '' && pendingAttachmentCount === 0) {
      return result
    }
    if (isSending) {
      return result
    }

    const providerValidation = validateProviderConfig(currentProvider)
    if (!providerValidation.isValid || currentProvider === null) {
      if (currentProvider === null) {
        this.deps.onShowError($r('app.string.provider_required_before_chat'))
        this.deps.onMarkAutoTaskFailed('未配置可用服务商')
      } else if (currentProvider.requiresApiKey && providerValidation.effectiveApiKey === '') {
        this.deps.onShowError($r('app.string.api_key_required'))
        this.deps.onMarkAutoTaskFailed('缺少 API Key')
      } else {
        this.deps.onShowError(providerValidation.errorMessage)
        this.deps.onMarkAutoTaskFailed(providerValidation.errorMessage)
      }
      return result
    }

    if (!this.isCurrentModelAvailable(currentProvider, currentModelId)) {
      this.deps.onShowError('当前模型不可用，请重新选择模型')
      this.deps.onMarkAutoTaskFailed('当前模型不可用')
      return result
    }

    if (!canStartNewTask) {
      this.deps.onShowToast($r('app.string.task_parallel_limit_reached'))
      this.deps.onMarkAutoTaskFailed('并行任务已达上限')
      return result
    }

    result.shouldSend = true
    result.messageContent = messageContent
    result.effectiveApiKey = providerValidation.effectiveApiKey
    result.currentProvider = currentProvider
    return result
  }

  private isCurrentModelAvailable(currentProvider: ModelProvider, currentModelId: string): boolean {
    if (currentModelId === '') {
      return false
    }
    for (let i = 0; i < currentProvider.models.length; i++) {
      const model = currentProvider.models[i]
      if (model.id === currentModelId && model.isEnabled) {
        return true
      }
    }
    return false
  }

  async executeSend(
    messageContent: string,
    currentProvider: ModelProvider,
    effectiveApiKey: string,
    attachmentsToSend: MessageAttachment[],
    webSearchConversationEnabled: boolean,
    selectedToolIds: string[],
    forcedToolIds: string[],
    currentModelId: string,
    // 联网模式: external_engine 走本地 search_web 工具; openai_builtin 走 Responses hosted web_search
    searchMode: ChatSearchMode = ChatSearchMode.EXTERNAL_ENGINE,
    // OpenAI Responses 内置生图开关 (hosted image_generation tool)
    builtinImageGenEnabled: boolean = false,
    // 函数调用 tool_choice: undefined = 默认 auto; "required" = 强制至少一个函数调用。
    // 调用方按"是否首轮 + 是否教学助手"判定;非教学助手传 undefined 行为完全不变。
    functionToolChoice?: string
  ): Promise<void> {
    // Pre-send 守门: 当 pending 附件含图片且当前模型不支持视觉时, 阻断发送并提示。
    // 解决"用户给非视觉模型发图→API 400→图片残留历史→后续轮持续 400"的循环错误。
    if (hasImageAttachment(attachmentsToSend) &&
      !getCurrentModelVisionSupport(currentProvider, currentModelId)) {
      this.deps.onShowError($r('app.string.chat_vision_unsupported_block'))
      this.deps.onMarkAutoTaskFailed('当前模型不支持图片')
      return
    }
    const plan = await this.buildExecutionPlan(
      currentProvider,
      webSearchConversationEnabled,
      selectedToolIds,
      forcedToolIds,
      currentModelId,
      searchMode,
      builtinImageGenEnabled,
      functionToolChoice
    )
    console.info(
      'ChatSendFlow',
      `[executeSend] plan=${plan.kind}, search=${webSearchConversationEnabled}, mode=${searchMode}, imageGen=${builtinImageGenEnabled}, selected=${selectedToolIds.join(',')}, forced=${forcedToolIds.join(',')}, tools=${plan.enabledToolIds.join(',')}, builtin=${plan.builtInResponsesTools.length}`
    )

    if (plan.kind === ChatExecutionPlanKind.TOOLS) {
      await this.sendMessageWithTools(
        messageContent,
        currentProvider,
        effectiveApiKey,
        attachmentsToSend,
        plan.enabledToolIds,
        plan.learnToolsOnSuccess,
        plan.builtInResponsesTools,
        plan.builtInResponsesToolChoice,
        plan.functionToolChoice
      )
      return
    }

    if (plan.kind === ChatExecutionPlanKind.UNSUPPORTED_TOOLS) {
      const message = '当前模型或接口不支持工具调用，请切换到支持 tools 的模型后再使用联网搜索、MCP 等工具'
      this.deps.onShowError(message)
      this.deps.onMarkAutoTaskFailed(message)
      return
    }

    await this.sendPlainMessage(
      messageContent,
      currentProvider,
      effectiveApiKey,
      attachmentsToSend,
      plan.builtInResponsesTools
    )
  }

  isCurrentModelSupportsTools(currentProvider: ModelProvider | null, currentModelId: string): boolean {
    if (currentProvider === null) {
      return false
    }
    if (currentProvider.apiStyle !== ApiStyle.OPENAI) {
      console.info('ChatSendFlow', `[Function Calling] 当前 API 风格不支持 tools: ${currentProvider.apiStyle}`)
      return false
    }
    for (let i = 0; i < currentProvider.models.length; i++) {
      const model = currentProvider.models[i]
      if (model.id === currentModelId) {
        const supportsTools = getEffectiveCapabilities(model).supportsTools
        console.info('ChatSendFlow',
          `[Function Calling] 当前模型 supportsTools=${supportsTools}, modelId=${model.id}`)
        return supportsTools
      }
    }
    console.info('ChatSendFlow',
      `[Function Calling] 未在 provider.models 中找到当前模型: currentModelId=${currentModelId}, provider=${currentProvider.id}`)
    return false
  }

  private shouldProbeToolsForCurrentModel(currentProvider: ModelProvider | null): boolean {
    if (currentProvider === null) {
      return false
    }
    if (currentProvider.apiStyle !== ApiStyle.OPENAI) {
      return false
    }
    return true
  }

  buildEnabledToolIds(selectedToolIds: string[] = [], forcedToolIds: string[] = []): string[] {
    const ids: string[] = []
    const allToolIds = [...selectedToolIds, ...forcedToolIds]
    for (let i = 0; i < allToolIds.length; i++) {
      const toolId = allToolIds[i]
      if (this.deps.toolRegistry.isToolRegistered(toolId)) {
        appendUniqueToolId(ids, toolId)
      }
    }
    return ids
  }

  private shouldEnableWebSearch(
    webSearchConversationEnabled: boolean,
    forcedToolIds: string[]
  ): boolean {
    if (webSearchConversationEnabled) {
      return true
    }
    for (let i = 0; i < forcedToolIds.length; i++) {
      if (isSearchToolId(forcedToolIds[i])) {
        return true
      }
    }
    return false
  }

  private filterNonSearchToolIds(toolIds: string[]): string[] {
    const ids: string[] = []
    for (let i = 0; i < toolIds.length; i++) {
      if (!isSearchToolId(toolIds[i])) {
        ids.push(toolIds[i])
      }
    }
    return ids
  }

  // 判断当前 provider 是否允许走 OpenAI Responses 内置 (hosted) 工具。
  // 必要条件: apiStyle === OPENAI && openaiTransport === RESPONSES。
  private isOpenAIResponsesHostedToolEligible(currentProvider: ModelProvider): boolean {
    if (currentProvider.apiStyle !== ApiStyle.OPENAI) {
      return false
    }
    return currentProvider.openaiTransport === OpenAITransport.RESPONSES
  }

  private async buildExecutionPlan(
    currentProvider: ModelProvider,
    webSearchConversationEnabled: boolean,
    selectedToolIds: string[],
    forcedToolIds: string[],
    currentModelId: string,
    searchMode: ChatSearchMode,
    builtinImageGenEnabled: boolean,
    // 函数调用 tool_choice: undefined = 走默认 auto;
    // "required" = 强制至少一个函数调用 (OpenAI Chat Completions / Responses 均支持)。
    // 与 builtinImageGenEnabled 路径互斥 (hosted 工具已走 builtInResponsesToolChoice)。
    functionToolChoice?: string
  ): Promise<ChatExecutionPlan> {
    const searchEnabled = this.shouldEnableWebSearch(webSearchConversationEnabled, forcedToolIds)
    const enabledToolIds = this.buildEnabledToolIds(
      this.filterNonSearchToolIds(selectedToolIds),
      this.filterNonSearchToolIds(forcedToolIds)
    )
    // 助手工具白名单收窄(只过滤非搜索工具;搜索走 shouldEnableWebSearch 独立通道)
    const assistantWhitelist = await this.deps.chatViewModel.getCurrentAssistantEnabledToolIds()
    if (assistantWhitelist.length > 0) {
      for (let i = enabledToolIds.length - 1; i >= 0; i--) {
        if (!assistantWhitelist.includes(enabledToolIds[i])) {
          enabledToolIds.splice(i, 1)
        }
      }
    }

    // 搜索路径分流:
    //   openai_builtin: 不注入本地 search_web/scrape_web function tool, 改为 hosted web_search
    //   external_engine (默认): 走原有 function tool 路径
    const builtInResponsesTools: BuiltInResponsesToolSpec[] = []
    let builtInResponsesToolChoice: OpenAIResponsesToolChoice | undefined = undefined
    const hostedEligible = this.isOpenAIResponsesHostedToolEligible(currentProvider)
    const useBuiltinSearch = searchEnabled &&
      searchMode === ChatSearchMode.OPENAI_BUILTIN &&
      hostedEligible
    if (useBuiltinSearch) {
      builtInResponsesTools.push(new BuiltInResponsesToolSpec(BuiltInResponsesToolKind.WEB_SEARCH))
    }
    // 内置生图: 与 hosted 搜索独立, 只要开关打开 + provider 满足 transport=RESPONSES 就注入。
    // 默认不传 partial_images, 与 RikkaHub 一样走 OpenAI 默认值; 解析侧会丢弃 partial 大行兜底防 OOM。
    if (builtinImageGenEnabled && hostedEligible) {
      builtInResponsesTools.push(new BuiltInResponsesToolSpec(BuiltInResponsesToolKind.IMAGE_GENERATION))
    }
    if (!useBuiltinSearch) {
      if (searchEnabled && this.deps.toolRegistry.isToolRegistered(SEARCH_WEB_TOOL_ID)) {
        appendUniqueToolId(enabledToolIds, SEARCH_WEB_TOOL_ID)
      } else if (searchEnabled && this.deps.toolRegistry.isToolRegistered(LEGACY_WEB_SEARCH_TOOL_ID)) {
        appendUniqueToolId(enabledToolIds, LEGACY_WEB_SEARCH_TOOL_ID)
      }
      if (searchEnabled &&
        this.deps.toolRegistry.isToolRegistered(SCRAPE_WEB_TOOL_ID) &&
        await this.deps.webSearchService.canExposeScrapeWebToModel()) {
        appendUniqueToolId(enabledToolIds, SCRAPE_WEB_TOOL_ID)
      }
    }
    // 纯生图意图要强制 image_generation tool call, 避免模型只返回一段提示词。
    // 如果同轮还启用了 hosted 搜索或本地 function tools, 暂时保留 auto;
    // 单次 Responses 请求无法表达"先搜索再生图"的强顺序, 这个场景应升级为两段式编排。
    if (builtinImageGenEnabled && hostedEligible && !useBuiltinSearch && enabledToolIds.length === 0) {
      builtInResponsesToolChoice = { type: BuiltInResponsesToolKind.IMAGE_GENERATION }
    }

    if (enabledToolIds.length === 0 && builtInResponsesTools.length === 0) {
      return new ChatExecutionPlan(ChatExecutionPlanKind.PLAIN_DIRECT)
    }
    // 仅 hosted 工具时, 不必要求模型 supportsTools (hosted 不走 function calling)
    if (builtInResponsesTools.length > 0 && enabledToolIds.length === 0) {
      return new ChatExecutionPlan(
        ChatExecutionPlanKind.TOOLS,
        enabledToolIds,
        false,
        builtInResponsesTools,
        builtInResponsesToolChoice,
        functionToolChoice
      )
    }

    if (this.isCurrentModelSupportsTools(currentProvider, currentModelId)) {
      return new ChatExecutionPlan(
        ChatExecutionPlanKind.TOOLS,
        enabledToolIds,
        false,
        builtInResponsesTools,
        builtInResponsesToolChoice,
        functionToolChoice
      )
    }

    if (this.shouldProbeToolsForCurrentModel(currentProvider)) {
      console.info('ChatSendFlow',
        `[Function Calling] 当前模型未标记 supportsTools, 先尝试 tools 请求: modelId=${currentModelId}`)
      return new ChatExecutionPlan(
        ChatExecutionPlanKind.TOOLS,
        enabledToolIds,
        true,
        builtInResponsesTools,
        builtInResponsesToolChoice,
        functionToolChoice
      )
    }

    return new ChatExecutionPlan(
      ChatExecutionPlanKind.UNSUPPORTED_TOOLS,
      enabledToolIds,
      false,
      builtInResponsesTools,
      builtInResponsesToolChoice,
      functionToolChoice
    )
  }

  private includesAny(text: string, keywords: string[]): boolean {
    for (let i = 0; i < keywords.length; i++) {
      if (text.includes(keywords[i])) {
        return true
      }
    }
    return false
  }

  private isToolCapabilityError(error: string): boolean {
    const normalized = error.toLowerCase()
    const toolKeywords = [
      'tool',
      'tools',
      'tool_choice',
      'tool calls',
      'function calling',
      'function_call',
      'functions',
      '函数调用',
      '工具调用'
    ]
    if (!this.includesAny(normalized, toolKeywords)) {
      return false
    }

    const capabilityKeywords = [
      'not support',
      'not supported',
      'does not support',
      'do not support',
      'unsupported',
      'unknown parameter',
      'unknown field',
      'unrecognized request argument',
      'unrecognized field',
      'extra_forbidden',
      'extra inputs are not permitted',
      'invalid parameter',
      'invalid_request_error',
      'not allowed',
      'is not permitted',
      '不支持',
      '未知参数',
      '不允许'
    ]
    return this.includesAny(normalized, capabilityKeywords)
  }

  private startTaskOrFail(messageContent: string): string {
    const taskId = this.deps.chatTaskOrchestrator.startTask(
      this.deps.getSessionId(),
      this.deps.getSessionTitle(),
      messageContent,
      this.deps.chatViewModel
    )
    if (taskId === '') {
      this.deps.onShowToast($r('app.string.task_parallel_limit_reached'))
      this.deps.onMarkAutoTaskFailed('并行任务已达上限')
      return ''
    }
    return taskId
  }

  private prepareSendState(taskId: string): void {
    this.deps.onSetCurrentTaskId(taskId)
    this.deps.onSetSending(true)
    this.deps.onBeforeSend()
  }

  private handleUserMessageAdded(userMessage: ChatMessage, senderSessionId: string): void {
    if (this.deps.getSessionId() !== senderSessionId) {
      console.info('ChatSendFlow',
        `[handleUserMessageAdded] dropped: session changed (sender=${senderSessionId}, current=${this.deps.getSessionId()})`)
      return
    }
    this.deps.onClearComposer()
    this.deps.messages.push(userMessage)
    this.deps.onSyncMessages()
    this.deps.onSetNewEmptySession(false)
    this.deps.onDraftCommitted()
    this.deps.onScrollBottom()
  }

  private handleAIMessageAdded(aiMessage: ChatMessage, senderSessionId: string): void {
    if (this.deps.getSessionId() !== senderSessionId) {
      return
    }
    this.deps.messages.push(aiMessage)
    this.deps.onSyncMessages()
    this.deps.onScrollBottom()
  }

  private handleAIMessageUpdated(aiMessage: ChatMessage, senderSessionId: string): void {
    if (this.deps.getSessionId() !== senderSessionId) {
      return
    }
    const index = this.deps.messages.findIndex((message: ChatMessage) => message.id === aiMessage.id)
    if (index < 0) {
      console.warn('ChatSendFlow', `[handleAIMessageUpdated] message not found: ${aiMessage.id}`)
      return
    }
    syncChatMessageFromSource(this.deps.messages[index], aiMessage)
    // 流式增量必须递增 syncVersion 触发 ChatMessageListSection 重算 renderSignature,
    // 否则 LazyForEach 数据源不会下发变更通知, 即使 ChatMessage 是 @ObservedV2 + @Trace,
    // 在 LazyForEach 嵌套场景下也无法精确刷新 item 内部 - 第一轮 reasoning 之后 timeline
    // 看似"卡住"就是这条路径漏掉导致的(handleAIMessageAdded 调过一次 onSyncMessages,
    // 之后 streaming 全程只走 sync 不递增 version)。
    this.deps.onSyncMessages(aiMessage.id)
    this.deps.onScrollBottom()
  }

  private handleTaskCompleted(taskId: string, senderSessionId: string): void {
    this.deps.chatTaskOrchestrator.completeTask(taskId)
    if (this.deps.getSessionId() === senderSessionId) {
      if (this.deps.getCurrentTaskId() === taskId) {
        this.deps.onSetCurrentTaskId('')
      }
      this.deps.onSetSending(false)
    }
    this.deps.onMarkAutoTaskCompleted()
  }

  private handleTaskFailed(taskId: string, error: string, showError: boolean, senderSessionId: string): void {
    this.deps.chatTaskOrchestrator.failTask(taskId, error)
    const stillActive = this.deps.getSessionId() === senderSessionId
    if (stillActive) {
      if (this.deps.getCurrentTaskId() === taskId) {
        this.deps.onSetCurrentTaskId('')
      }
      this.deps.onSetSending(false)
    }
    this.deps.onMarkAutoTaskFailed(error)
    if (showError && stillActive) {
      this.deps.onShowError(error)
    }
  }

  private completeTaskForFallback(taskId: string, senderSessionId: string): void {
    this.deps.chatTaskOrchestrator.completeTaskSilently(taskId)
    if (this.deps.getSessionId() !== senderSessionId) {
      return
    }
    if (this.deps.getCurrentTaskId() === taskId) {
      this.deps.onSetCurrentTaskId('')
    }
    this.deps.onSetSending(false)
  }

  private appendUniqueMessageId(messageIds: string[], messageId: string): void {
    if (messageId === '' || messageIds.includes(messageId)) {
      return
    }
    messageIds.push(messageId)
  }

  private async removeProbeMessages(messageIds: string[], senderSessionId: string): Promise<void> {
    if (messageIds.length === 0) {
      return
    }
    if (this.deps.getSessionId() === senderSessionId) {
      for (let i = 0; i < messageIds.length; i++) {
        const index = this.deps.messages.findIndex((message: ChatMessage) => message.id === messageIds[i])
        if (index >= 0) {
          this.deps.messages.splice(index, 1)
        }
      }
      this.deps.onSyncMessages()
    }
    await this.deps.chatViewModel.deleteMessagesFromIndex(messageIds)
  }

  private hasBuiltInImageGenerationTool(builtInResponsesTools: BuiltInResponsesToolSpec[]): boolean {
    for (let i = 0; i < builtInResponsesTools.length; i++) {
      if (builtInResponsesTools[i].kind === BuiltInResponsesToolKind.IMAGE_GENERATION) {
        return true
      }
    }
    return false
  }

  private async fallbackToPlainMessageAfterToolFailure(
    taskId: string,
    senderSessionId: string,
    messageIds: string[],
    messageContent: string,
    currentProvider: ModelProvider,
    effectiveApiKey: string,
    attachmentsToSend: MessageAttachment[],
    error: string
  ): Promise<void> {
    console.warn('ChatSendFlow', `[Function Calling] tools request failed, fallback to plain message: ${error}`)
    this.completeTaskForFallback(taskId, senderSessionId)
    await this.removeProbeMessages(messageIds, senderSessionId)
    if (this.deps.getSessionId() === senderSessionId) {
      this.deps.onShowToast('当前模型未接受工具调用，已关闭工具重试本次发送')
    }
    await this.sendPlainMessage(
      messageContent,
      currentProvider,
      effectiveApiKey,
      attachmentsToSend
    )
  }

  // Post-error 兜底: 当 API 返回图片能力错误（pre-send 漏过）时, 剥离本轮图片附件并重试。
  // 仅剥离 IMAGE 类型, 保留 FILE (PDF/Word), 因为部分模型对文档输入的支持独立于视觉。
  private async fallbackAfterImageCapabilityError(
    taskId: string,
    senderSessionId: string,
    messageIds: string[],
    messageContent: string,
    currentProvider: ModelProvider,
    effectiveApiKey: string,
    attachmentsToSend: MessageAttachment[],
    error: string
  ): Promise<void> {
    console.warn('ChatSendFlow', `[Vision] image capability error, stripping images and retrying: ${error}`)
    this.completeTaskForFallback(taskId, senderSessionId)
    await this.removeProbeMessages(messageIds, senderSessionId)
    const stripped: MessageAttachment[] = []
    for (let i = 0; i < attachmentsToSend.length; i++) {
      if (attachmentsToSend[i].type !== AttachmentType.IMAGE) {
        stripped.push(attachmentsToSend[i])
      }
    }
    if (this.deps.getSessionId() === senderSessionId) {
      this.deps.onShowToast($r('app.string.chat_vision_fallback_success'))
    }
    await this.sendPlainMessage(
      messageContent,
      currentProvider,
      effectiveApiKey,
      stripped
    )
  }

  async sendPlainMessage(
    messageContent: string,
    currentProvider: ModelProvider,
    effectiveApiKey: string,
    attachmentsToSend: MessageAttachment[] = [],
    builtInResponsesTools: BuiltInResponsesToolSpec[] = []
  ): Promise<void> {
    const taskId = this.startTaskOrFail(messageContent)
    if (taskId === '') {
      return
    }

    this.prepareSendState(taskId)
    const senderSessionId = this.deps.getSessionId()
    const modelId = this.deps.getCurrentModelId()
    const contextMessageCount = await this.deps.chatViewModel.getContextMessageCount()
    const maxOutputTokens = await this.deps.chatViewModel.getMaxOutputTokens()
    const messages = this.deps.getMessages()
    const contextStartIndex = contextMessageCount > 0 ? Math.max(0, messages.length - contextMessageCount) : 0
    const createdMessageIds: string[] = []
    let imageFallbackStarted = false

    try {
      await this.deps.chatViewModel.sendMessage(
        messageContent,
        currentProvider.id,
        currentProvider.type,
        currentProvider.apiStyle,
        effectiveApiKey,
        currentProvider.baseUrl,
        modelId,
        this.deps.getCurrentModelName(),
        messages,
        (userMessage: ChatMessage): void => {
          this.appendUniqueMessageId(createdMessageIds, userMessage.id)
          this.handleUserMessageAdded(userMessage, senderSessionId)
        },
        (aiMessage: ChatMessage): void => {
          this.appendUniqueMessageId(createdMessageIds, aiMessage.id)
          this.handleAIMessageAdded(aiMessage, senderSessionId)
        },
        (aiMessage: ChatMessage): void => {
          this.handleAIMessageUpdated(aiMessage, senderSessionId)
        },
        (): void => {
          this.handleTaskCompleted(taskId, senderSessionId)
        },
        async (error: string): Promise<void> => {
          // Post-error 兜底: 仅当首轮 send 失败 (completedSuccessfully 未置 true) 时进入。
          // imageFallbackStarted 守卫避免"剥离后还报图像错"时无限重试。
          if (!imageFallbackStarted && isImageCapabilityError(error)) {
            imageFallbackStarted = true
            await this.fallbackAfterImageCapabilityError(
              taskId,
              senderSessionId,
              createdMessageIds,
              messageContent,
              currentProvider,
              effectiveApiKey,
              attachmentsToSend,
              error
            )
            return
          }
          this.handleTaskFailed(taskId, error, true, senderSessionId)
        },
        attachmentsToSend,
        contextStartIndex,
        this.deps.getReasoningLevel(),
        currentProvider.apiPath || undefined,
        currentProvider.customHeadersJson || undefined,
        currentProvider.openaiTransport,
        maxOutputTokens > 0 ? maxOutputTokens : undefined,
        builtInResponsesTools.length > 0 ? builtInResponsesTools : undefined
      )
    } catch (error) {
      const message = `发送失败: ${JSON.stringify(error)}`
      this.handleTaskFailed(taskId, message, true, senderSessionId)
    }
  }

  async sendMessageWithTools(
    messageContent: string,
    currentProvider: ModelProvider,
    effectiveApiKey: string,
    attachmentsToSend: MessageAttachment[] = [],
    enabledToolIds: string[] = [],
    learnToolsOnSuccess: boolean = false,
    builtInResponsesTools: BuiltInResponsesToolSpec[] = [],
    builtInResponsesToolChoice?: OpenAIResponsesToolChoice,
    // 函数调用 tool_choice: undefined = 默认 auto; "required" = 强制至少一个函数调用。
    // 由 ChatViewModel 在 executeToolCallLoop 内合并到 aiApiService.streamChatRequestWithTools 的 toolChoice 参数。
    functionToolChoice?: string
  ): Promise<void> {
    const taskId = this.startTaskOrFail(messageContent)
    if (taskId === '') {
      return
    }

    this.prepareSendState(taskId)
    const senderSessionId = this.deps.getSessionId()
    const modelId = this.deps.getCurrentModelId()
    const tools = this.deps.toolRegistry.getEnabledToolDefinitions(enabledToolIds)
    const createdMessageIds: string[] = []
    let completedSuccessfully = false
    let fallbackStarted = false
    let imageFallbackStarted = false

    console.info('ChatSendFlow', `[Function Calling] 启用工具: ${enabledToolIds.join(', ')}`)

    const toolCallbacks: ToolCallCallbacks = {
      onToolCallStarted: (toolCalls: ToolCall[]): void => {
        console.info('ChatSendFlow', `[Function Calling] 工具调用开始: ${toolCalls.length} 个`)
        for (let i = 0; i < toolCalls.length; i++) {
          console.info('ChatSendFlow', `  - ${toolCalls[i].functionName}: ${toolCalls[i].arguments}`)
        }
      },
      onToolCallCompleted: (results: ToolResult[]): void => {
        console.info('ChatSendFlow', `[Function Calling] 工具调用完成: ${results.length} 个结果`)
      },
      onSearching: (query: string): void => {
        console.info('ChatSendFlow', `[Function Calling] 正在搜索: ${query}`)
      }
    }

    try {
      await this.deps.chatViewModel.sendMessageWithTools(
        messageContent,
        currentProvider.id,
        currentProvider.type,
        currentProvider.apiStyle,
        effectiveApiKey,
        currentProvider.baseUrl,
        modelId,
        this.deps.getCurrentModelName(),
        this.deps.getMessages(),
        (userMessage: ChatMessage): void => {
          this.appendUniqueMessageId(createdMessageIds, userMessage.id)
          this.handleUserMessageAdded(userMessage, senderSessionId)
        },
        (aiMessage: ChatMessage): void => {
          this.appendUniqueMessageId(createdMessageIds, aiMessage.id)
          this.handleAIMessageAdded(aiMessage, senderSessionId)
        },
        (aiMessage: ChatMessage): void => {
          this.handleAIMessageUpdated(aiMessage, senderSessionId)
        },
        (): void => {
          completedSuccessfully = true
          this.handleTaskCompleted(taskId, senderSessionId)
        },
        async (error: string): Promise<void> => {
          // Post-error 兜底: 图片能力错误优先级高于工具调用错误 (避免先误判为 tool 错误)。
          // 同样用 imageFallbackStarted 守卫, 不嵌套重试。
          if (!imageFallbackStarted && isImageCapabilityError(error)) {
            imageFallbackStarted = true
            await this.fallbackAfterImageCapabilityError(
              taskId,
              senderSessionId,
              createdMessageIds,
              messageContent,
              currentProvider,
              effectiveApiKey,
              attachmentsToSend,
              error
            )
            return
          }
          if (this.isToolCapabilityError(error) && !this.hasBuiltInImageGenerationTool(builtInResponsesTools)) {
            fallbackStarted = true
            await this.fallbackToPlainMessageAfterToolFailure(
              taskId,
              senderSessionId,
              createdMessageIds,
              messageContent,
              currentProvider,
              effectiveApiKey,
              attachmentsToSend,
              error
            )
            return
          }
          this.handleTaskFailed(taskId, error, true, senderSessionId)
        },
        attachmentsToSend,
        0,
        this.deps.getReasoningLevel(),
        tools,
        toolCallbacks,
        currentProvider.apiPath || undefined,
        currentProvider.customHeadersJson || undefined,
        currentProvider.openaiTransport,
        builtInResponsesTools.length > 0 ? builtInResponsesTools : undefined,
        builtInResponsesToolChoice,
        functionToolChoice
      )
      if (completedSuccessfully && learnToolsOnSuccess && !fallbackStarted) {
        await this.deps.onConfirmModelSupportsTools(currentProvider.id, modelId)
      }
    } catch (error) {
      const message = `发送失败: ${JSON.stringify(error)}`
      this.handleTaskFailed(taskId, message, true, senderSessionId)
    }
  }
}
