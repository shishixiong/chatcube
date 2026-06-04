import { KeyboardAvoidMode, SymbolGlyphModifier } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import {
  DefaultMediaModel,
  DefaultMediaType,
  MediaPreview,
  MediaPreviewOptions,
  PromptActionTool
} from '@lyb/media-preview'
import {
  HdsNavigationBackButtonItemOptions,
  HdsNavigationMenuItemOptions,
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsNavigationTitleBarOptions
} from '@kit.UIDesignKit'
import {
  ApiStyle,
  ChatMessage,
  ChatSearchMode,
  MessageRole,
  ModelProvider,
  ModelInfo,
  ModelInfoExtendedJson,
  MessageAttachment,
  AttachmentProcessState,
  OpenAITransport,
  OPENAI_BUILTIN_SEARCH_ENGINE_ID,
  ReasoningLevel,
  ModelRole,
  ToolCall,
  ToolConfig,
  ToolApprovalPolicy,
  ToolPermissionLevel,
  ToolSourceType,
  SearchEngine
} from '../models/ChatModels'
import { Assistant, DEFAULT_ASSISTANT_ID } from '../models/AssistantModels'
import { AttachmentPicker } from '../components/AttachmentPicker'
import { ScrollToBottomButton } from '../components/ScrollToBottomButton'
import { ScrollToBottomLoadingButton } from '../components/ScrollToBottomLoadingButton'
import { SharePreviewSheet } from '../components/SharePreviewSheet'
import { MessageMapSheet } from '../components/MessageMapSheet'
import { NumberPuzzleCard, NumberPuzzleResult } from '../components/NumberPuzzleCard'
import { ChatViewModel, TitleGenerationCallbacks } from '../viewmodels/ChatViewModel'
import { ProviderViewModel } from '../viewmodels/ProviderViewModel'
import { AppStateManager } from '../viewmodels/AppStateManager'
import { AITaskService } from '../services/AITaskService'
import { WebSearchService } from '../services/WebSearchService'
import { DefaultModelService } from '../services/DefaultModelService'
import { PreferenceKeys, PreferencesService } from '../services/PreferencesService'
import { McpService } from '../services/McpService'
import { ToolRegistry } from '../services/ToolRegistry'
import {
  getToolExecutionService,
  PendingToolInteractionKind,
  PendingToolInteractionSnapshot
} from '../services/ToolExecutionService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { registerBuiltinTools } from '../config/BuiltinTools'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { inputMethod } from '@kit.IMEKit'
import { webview } from '@kit.ArkWeb'
import { dismissActiveSnackBarOnBack, showSnackBar, showToast, SnackBarDisplayOptions, SnackBarTone } from '../utils/ToastUtil'
import { getEffectiveCapabilities } from '../utils/ModelCapabilityDeriver'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { ChatModelSelectorSheetContent } from '../components/chat/ChatModelSelectorSheetContent'
import { ChatInputAreaSection } from '../components/chat/ChatInputAreaSection'
import { ChatMultiSelectToolbar } from '../components/chat/ChatMultiSelectToolbar'
import { ChatMessageListSection } from '../components/chat/ChatMessageListSection'
import { ChatToolPickerSheetContent } from '../components/chat/ChatToolPickerSheetContent'
import { ChatToolExecutionApprovalSheetContent } from '../components/chat/ChatToolExecutionApprovalSheetContent'
import { TodayStarSummaryCard } from '../components/chat/TodayStarSummaryCard'
import { TodayStarDetailSheet } from '../components/chat/TodayStarDetailSheet'
import { StarActivityType, getActivityMeta } from '../models/StarEventModels'
import { SearchEngineMenuOption } from '../components/ChatToolbar'
import { getSearchEngineRegistry, registerAllSearchEngines, SearchEngineDescriptor } from '../services/search/Index'
import { parseSearchEngineIdListJson } from '../utils/SearchEnginePreferenceUtils'
import {
  ChatNavigationTitleContent
} from '../components/ChatNavigationTitleContent'
import {
  ReasoningControlMode,
  normalizeReasoningLevelForControl,
  resolveReasoningControlMode,
  supportsReasoningXhighControl
} from '../services/registry/CompatibilityResolver'
import { modelSupportsImageGenerationTool } from '../services/registry/ModelAbilityRegistry'
import {
  getListBottomPaddingForChat,
  getPreviewTimeTextForChat,
  shouldShowToolSelectionChipForChat
} from './chat/ChatPageUiHelper'
import { parseToolIdsFromRouteRaw } from './chat/ChatToolIdHelper'
import { ChatSendFlow, ChatSendFlowDependencies } from './chat/ChatSendFlow'
import { ChatStopFlow, ChatStopFlowDependencies } from './chat/ChatStopFlow'
import { ChatInlineEditFlow, ChatInlineEditFlowDependencies } from './chat/ChatInlineEditFlow'
import { ChatSelectionFlow, ChatSelectionFlowDependencies } from './chat/ChatSelectionFlow'
import { ChatPageLoadFlow, ChatPageLoadFlowDependencies, ChatPageLoadResult } from './chat/ChatPageLoadFlow'
import { ChatTaskAlertFlow, ChatTaskAlertFlowDependencies } from './chat/ChatTaskAlertFlow'
import { ChatScrollUiFlow, ChatScrollUiFlowDependencies } from './chat/ChatScrollUiFlow'
import { buildHdsTopNavigationTitleBarOptions, getHdsTopNavigationMaskExtraHeight, HdsTopNavigationBlurOptions } from '../utils/HdsVisualEffectUtil'
import {
  collectTailMessageIds,
  findMessageIndexById,
  resolveUserMessageIndexForRegenerate,
  toListScrollIndexForMessage
} from './chat/ChatMessageActionHelper'
import { ChatPageRouteParams } from './chat/ChatPageRouteTypes'
import { resolveModelSwitchReasoningLevel } from './chat/ChatReasoningStateHelper'
import { getChatContentMaxWidth, LayoutSizeClass, shouldUseIndexChatSplitLayout } from '../config/LayoutProfile'
import { getAppUiState, observeAppUiState, setAppUiStateValue } from '../state/AppUiState'
import { applyModelDraft } from '../utils/ModelDraftUtils'
import { ToolPreviewEntry, buildToolArgumentsPreview } from '../utils/ToolPayloadSummaryUtils'
import { DEFAULT_PRIMARY_COLOR } from '../config/ThemeDefaults'
import { pickLocalizedText } from '../utils/LocalizedTextUtils'
import { getSearchToolIds, isSearchToolId, MATH_QUIZ_TOOL_ID, ENGLISH_QUIZ_TOOL_ID } from '../utils/SearchToolIdentityUtils'
import { MessagePartKind } from '../models/MessageParts'
import { normalizeAssistantAvatarValue } from '../components/AssistantAvatar'
import {
  preparePreviewImageForShare,
  savePreviewImageToAlbum,
  savePreviewImageToAlbumAuthorized
} from '../utils/ImagePreviewSaveUtil'
import { DocumentParsePolicy, DocumentParseResult, WebDocumentParserService } from '../services/DocumentParseService'
import { shouldUseLeftHandAdaptiveLayout } from '../utils/HandAdaptiveUtils'

const DOMAIN = 0x0003
const TAG = 'ChatPage'

class ProviderModelSelection {
  provider: ModelProvider
  model: ModelInfo

  constructor(provider: ModelProvider, model: ModelInfo) {
    this.provider = provider
    this.model = model
  }
}

const HDS_NAV_DESTINATION_MINI_TITLE_BAR_HEIGHT: number = 56
const MESSAGE_MAP_JUMP_EXTRA_TOP_CLEARANCE: number = 36
const HDS_NAV_TITLE_NATIVE_START_INSET: number = 56
const HDS_NAV_TITLE_NATIVE_MENU_BUTTON_WIDTH: number = 56
const HDS_NAV_TITLE_NATIVE_MENU_EDGE_INSET: number = 16
const HDS_NAV_SPLIT_TITLE_BAR_MASK_EXTRA_HEIGHT: number = 20
// 今日小明星小卡片高度 (padding 12*2 + 两行内容 18+6+13 = 73) + 8vp 顶部安全间距 ≈ 88vp
const TODAY_STAR_SUMMARY_CARD_HEIGHT: number = 88

@ComponentV2
export struct ChatPage {
  @Local navPathStack: NavPathStack = new NavPathStack()
  @Param routeParamsSeed: ChatPageRouteParams | null = null
  @Local routeParams: ChatPageRouteParams | null = null
  @Local messages: ChatMessage[] = []
  @Local inputText: string = ''
  @Local currentModel: string = ''
  @Local currentModelId: string = ''
  @Local currentAssistantId: string = DEFAULT_ASSISTANT_ID
  @Local currentAssistantAvatarSymbol: string = 'AI'
  @Local currentAssistantColor: string = DEFAULT_PRIMARY_COLOR
  @Local assistantAvatarRenderTick: number = 0
  @Local isModelSelectorVisible: boolean = false
  @Local modelSheetActivePanel: string = 'selector'
  @Local editingModel: ModelInfo | null = null
  @Local editingModelProvider: ModelProvider | null = null
  @Local isLoading: boolean = false
  @Local isSending: boolean = false
  // 应用是否退到后台（用于处理生成中返回桌面/关闭应用）
  private get appInBackground(): boolean {
    return getAppUiState().appInBackground
  }
  private get inAppTaskAlertPayload(): string {
    return getAppUiState().inAppTaskAlertPayload
  }
  private get openSessionPayload(): string {
    return getAppUiState().openSessionPayload
  }
  private get pendingToolInteractionTick(): number {
    return getAppUiState().pendingToolInteractionTick
  }
  @Local providers: ModelProvider[] = []
  // 附件相关状态
  @Local pendingAttachments: MessageAttachment[] = []
  @Local showAttachmentPicker: boolean = false
  @Local attachmentPanelHeightVp: number = 0
  private readonly ATTACHMENT_PANEL_EXPANDED_HEIGHT: number = 130
  private documentParserWebController: webview.WebviewController = new webview.WebviewController()
  private documentParserService: WebDocumentParserService = new WebDocumentParserService()
  private documentParseQueue: MessageAttachment[] = []
  private isDocumentParseQueueRunning: boolean = false
  private documentParseEpoch: number = 0
  private documentParseRunnerId: number = 0
  @Local shouldMountDocumentParserWeb: boolean = false
  // 是否在列表底部
  @Local isAtBottom: boolean = false
  // 是否在列表顶部
  @Local isAtTop: boolean = false
  @Local isGeneratingScrollTipVisible: boolean = false
  @Local currentScrollOffsetVp: number = 0
  private firstVisibleListIndex: number = 0
  private lastVisibleListIndex: number = 0
  // 输入框显示状态（true=显示，false=隐藏）
  @Local isInputBarVisible: boolean = true
  @Local inputAreaHeightVp: number = 0
  @Local multiSelectToolbarHeightVp: number = 0
  // 输入框是否处于焦点状态（用于控制预览气泡显示）
  @Local isInputFocused: boolean = false
  // 语音输入模式状态
  @Local isVoiceMode: boolean = false
  @Local isRecording: boolean = false
  @Local isRecordingCancelZone: boolean = false
  private waveformTimerId: number = -1
  // 录音安全超时：超过 65 秒自动取消（引擎 maxAudioDuration=60s + 5s 余量）
  private recordingSafetyTimerId: number = -1
  // 语音模式自动 TTS：追踪 isSending 变化以检测回复完成
  private previousIsSending: boolean = false
  // 语音模式：quiz 工具自动 TTS 去重追踪（防止同一 quiz 重复朗读）
  private lastAutoTtsQuizToolCallId: string = ''
  // quiz TTS 朗读完成后记录当时消息 content 长度，用于 onSendingCompleted 仅朗读新增的验证内容
  private lastAutoTtsQuizMessageContentLength: number = 0
  // 记录 quiz TTS 对应的消息 ID，跨会话时防止误用旧长度值
  private lastAutoTtsQuizMessageId: string = ''
  // 计算滚动偏移
  private lastScrollOffset: number = 0
  private readonly inputBarShowThreshold: number = 6
  private readonly inputBarHideThreshold: number = 18
  // 会话标题相关状态
  @Local sessionTitle: string = ''
  @Local isTitleGenerating: boolean = false
  @Local titleGenerateFailed: boolean = false
  @Local titleEditRequestTick: number = 0
  // 图片预览状态
  @Local showImagePreview: boolean = false
  @Local previewImages: Array<string> = []
  @Local previewImageIndex: number = 0
  @Local isImagePreviewSaving: boolean = false
  @Local isImagePreviewSharing: boolean = false
  private previewImageSourceIds: Array<string> = []
  private imagePreviewDialogId: string = ''
  private imagePreviewOptions: MediaPreviewOptions<DefaultMediaModel> | null = null
  @Local showMessageWebSheet: boolean = false
  @Local messageWebSheetUrl: string = ''
  @Local messageWebSheetTitle: string = ''
  private messageSheetWebController: webview.WebviewController = new webview.WebviewController()
  private hasInitializedRoute: boolean = false
  // 当前正在朗读的消息ID
  private get speakingMessageId(): string {
    return getAppUiState().speakingMessageId
  }
  // 是否为通过"新建对话"创建的空会话（返回时需要删除）
  private isNewEmptySession: boolean = false
  // 联网查询全局可用状态（工具中心控制）
  @Local webSearchAvailable: boolean = false
  @Local webSearchConversationEnabled: boolean = false
  // 联网搜索模式: external_engine(默认) / openai_builtin
  // 与外部 SEARCH_ENGINE 解耦, openai_builtin 走 Responses hosted web_search hosted tool。
  @Local searchMode: ChatSearchMode = ChatSearchMode.EXTERNAL_ENGINE
  // OpenAI Responses 内置生图偏好。运行时仍按当前 provider/model 能力收敛, 不支持时不展示也不下发。
  @Local builtinImageGenEnabled: boolean = false
  // 联网菜单内可选的引擎列表(Bing 永远在内, 其它引擎填了 API Key 才出现)
  // 当 currentProvider 满足 OpenAI Responses 条件时, 末尾追加 OPENAI_BUILTIN_SEARCH_ENGINE_ID 哨兵项
  @Local availableSearchEngines: SearchEngineMenuOption[] = []
  // 当前选中的引擎 id(SearchEngine 枚举字符串或 OPENAI_BUILTIN_SEARCH_ENGINE_ID)。
  // 普通引擎与 PreferenceKeys.SEARCH_ENGINE 同步; 哨兵 id 与 PreferenceKeys.SEARCH_MODE 同步。
  @Local activeSearchEngineId: string = SearchEngine.BING
  @Local selectedToolIds: string[] = []
  @Local availableChatTools: ToolConfig[] = []
  @Local isRefreshingMcpToolAvailability: boolean = false
  @Local showToolPickerSheet: boolean = false
  @Local showToolExecutionApprovalSheet: boolean = false
  @Local pendingToolExecutionApprovalToolCallId: string = ''
  private isResolvingToolExecutionApproval: boolean = false
  // 用户主动下滑关闭 sheet 后,记录当前 pending toolCallId,避免立即重弹形成"按死了甩不掉"。
  // 在 sync 时如果 service 里的 pending 仍是这个 id,保持折叠态(不弹 sheet);
  // 用户离开会话再回来 / 切到列表页 / 点 SnackBar "展开"时清掉,重新弹出。
  private dismissedPendingToolCallId: string = ''
  @Local toolExecutionApprovalToolId: string = ''
  @Local toolExecutionApprovalIsWriteTool: boolean = false
  @Local showNumberPuzzleSheet: boolean = false
  @Local numberPuzzleSheetToolCall: ToolCall = new ToolCall()
  @Local numberPuzzleAnswered: boolean = false
  @Local toolExecutionApprovalSourceLabel: string = ''
  @Local toolExecutionApprovalName: string = ''
  @Local showStarSheet: boolean = false
  @Local toolExecutionApprovalSourceId: string = ''
  @Local toolExecutionApprovalArgumentSummary: string = ''
  @Local toolExecutionApprovalArgumentEntries: ToolPreviewEntry[] = []
  @Local toolExecutionApprovalArgumentsPreview: string = '{}'
  @Local toolExecutionApprovalArgumentsTruncated: boolean = false
  @Local showRawToolExecutionApprovalArguments: boolean = false
  // 推理级别状态
  @Local reasoningLevel: ReasoningLevel = ReasoningLevel.OFF
  // 最近截图检测状态（由 ChatInputBar 回调设置，ScreenshotBanner 独立渲染）
  @Local hasRecentScreenshot: boolean = false
  // 是否为新建对话（用于加载和自动发送策略）
  @Local isNewChatTransition: boolean = false
  // 是否自动聚焦输入框
  @Local autoFocusInput: boolean = false
  // 避让区域高度
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get bottomAvoidHeight(): number {
    return getAppUiState().bottomAvoidHeight
  }
  private get layoutSizeClass(): string {
    return getAppUiState().layoutSizeClass
  }
  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }
  private get windowHeightVp(): number {
    return getAppUiState().windowHeightVp
  }
  private get handAdaptiveEnabled(): boolean {
    return getAppUiState().settingHandAdaptiveEnabled
  }
  private get handAdaptiveUnsupported(): boolean {
    return getAppUiState().settingHandAdaptiveUnsupported
  }
  private get holdingHandStatus(): number {
    return getAppUiState().holdingHandStatus
  }
  private shouldUseLeftHandLayout(): boolean {
    return shouldUseLeftHandAdaptiveLayout(this.handAdaptiveEnabled, this.handAdaptiveUnsupported,
      this.holdingHandStatus)
  }
  // 主题颜色
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }
  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
  private get chatFontSize(): number {
    return getAppUiState().chatFontSize
  }
  private get materialType(): number {
    return getAppUiState().materialType
  }
  private get materialLevel(): number {
    return getAppUiState().materialLevel
  }
  private get messageThemeRenderKey(): string {
    const uiState = getAppUiState()
    return `${uiState.colorTheme}_${uiState.isDarkMode ? '1' : '0'}`
  }
  // 多选模式状态
  @Local isMultiSelectMode: boolean = false
  @Local selectedMessageIds: Array<string> = []
  // 分享预览弹窗状态
  @Local showSharePreview: boolean = false
  @Local shareMessages: ChatMessage[] = []
  // 消息地图弹窗状态
  @Local showMessageMapSheet: boolean = false
  private pendingMessageMapJumpMessageId: string = ''
  // 编辑消息相关状态（内联编辑模式）
  @Local isEditingMessage: boolean = false // 是否处于消息编辑模式
  @Local editingMessageId: string = '' // 正在编辑的消息ID
  @Local editingOriginalContent: string = '' // 原始内容（用于取消编辑）
  @Local editingOriginalAttachments: MessageAttachment[] = [] // 原始附件
  @Local editingMessageIsUser: boolean = true // 是否为用户消息（决定是否显示"保存并发送"）
  @Local messageListSyncVersion: number = 0
  @Local messageListSyncMessageId: string = ''
  private scroller: Scroller = new Scroller()
  private maxScrollOffset: number = 0
  // 浮动按钮"左上角距屏幕底"基线兜底,首屏 inputAreaHeightVp 尚未实测时使用
  // 兜底值需含按钮自身高度(loading 圆环 48 + 间隙 8)否则首屏按钮会压在输入区里
  private readonly floatingScrollButtonFallbackVp: number = 172
  // 浮动按钮基线上限,避免被推到手指难以触达的高度
  // 极端场景(banner + 多行输入)实测可达 240+,放宽到 300 让按钮始终在输入区上方
  private readonly floatingScrollButtonMaxBaselineVp: number = 300
  private readonly scrollOffsetUiSyncStepVp: number = 96
  private mcpToolAvailabilityRefreshTask: Promise<void> | null = null
  private chatViewModel: ChatViewModel = ServiceRegistry.chat()
  private providerViewModel: ProviderViewModel = ServiceRegistry.provider()
  private appStateManager: AppStateManager = ServiceRegistry.appState()
  private webSearchService: WebSearchService = ServiceRegistry.webSearch()
  private defaultModelService: DefaultModelService = ServiceRegistry.defaultModel()
  private preferencesService: PreferencesService = ServiceRegistry.preferences()
  private aiTaskService: AITaskService = ServiceRegistry.aiTask()
  private toolRegistry: ToolRegistry = ServiceRegistry.toolRegistry()
  private mcpService: McpService = ServiceRegistry.mcp()
  private chatTaskOrchestrator = ServiceRegistry.chatTaskOrchestrator()
  // 当前服务商配置
  private currentProvider: ModelProvider | null = null
  private sessionId: string = ''
  private pendingInitialPrompt: string = ''
  private pendingInitialToolIds: string[] = []
  private initialPromptAutoSent: boolean = false
  private forcedToolIdsOnce: string[] = []
  private currentTaskId: string = ''
  private isSendDispatching: boolean = false
  private lastHandledAlertTimestamp: number = 0
  private isPageVisible: boolean = false
  // 兜底 watcher：页面切换时可能错过一次任务完成事件，这里只负责回收发送态，不碰消息内容同步
  private runtimeStateWatchdogTimerId: number = -1
  private sendFlow: ChatSendFlow | null = null
  private stopFlow: ChatStopFlow | null = null
  private inlineEditFlow: ChatInlineEditFlow | null = null
  private selectionFlow: ChatSelectionFlow | null = null
  private loadFlow: ChatPageLoadFlow | null = null
  private taskAlertFlow: ChatTaskAlertFlow | null = null
  private scrollUiFlow: ChatScrollUiFlow | null = null
  private draftAutosaveTimerId: number = -1
  private readonly draftAutosaveDelayMs: number = 400
  private appUiStateDisposers: Array<() => void> = []
  // 加载会话后, 让 List 后台做 scrollEdge(Bottom) 兜底对齐, 期间 isLoading 仍为 true 用 spinner 罩住,
  // 用户不会看到列表从顶部滚到底部的过渡
  private initialAlignmentTimerIds: number[] = []
  private assistantAvatarReloadToken: number = 0
  private pendingToolInteractionSyncTimerId: number = -1

  private showChatSnack(message: string | Resource, duration: number = 2000,
    tone: SnackBarTone = SnackBarTone.DEFAULT): void {
    const options: SnackBarDisplayOptions = new SnackBarDisplayOptions()
    options.message = message
    options.duration = duration
    options.tone = tone
    showSnackBar(this.getUIContext(), options)
  }

  aboutToAppear(): void {
    if (this.routeParams === null && this.routeParamsSeed !== null) {
      this.routeParams = this.routeParamsSeed
      this.applyRouteDisplaySeed(this.routeParamsSeed)
    }
    if (this.sessionTitle === '') {
      this.sessionTitle = this.getDefaultSessionTitle()
    }
    if (this.toolExecutionApprovalArgumentSummary === '') {
      this.toolExecutionApprovalArgumentSummary = this.getNoToolArgumentsText()
    }
    // V2 流式渲染需要 UIContext 在 displaySync 帧回调中正确启动;
    // ChatViewModel 是数据层拿不到 UIContext, 通过 setter 注入。
    this.chatViewModel.setStreamingUIContext(this.getUIContext())
    this.registerAppUiStateObservers()
    // 设置键盘避让模式
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)

    // 注册内置工具
    registerBuiltinTools()

    // 设置标题生成回调
    const titleCallbacks: TitleGenerationCallbacks = {
      onTitleUpdated: (title: string): void => {
        this.sessionTitle = title
        this.titleGenerateFailed = false
      },
      onTitleGenerating: (isGenerating: boolean): void => {
        this.isTitleGenerating = isGenerating
      },
      onTitleFailed: (): void => {
        this.titleGenerateFailed = true
        this.showChatSnack($r('app.string.title_generate_failed_config'), 2000, SnackBarTone.ERROR)
      }
    }
    this.chatViewModel.setTitleCallbacks(titleCallbacks)

    // 初始化TTS服务
    this.initTTSService()

    // 如果通过 navDestination builder 传入了 routeParams，直接初始化
    // 否则等 onReady 回调设置 routeParams 后再初始化
    if (this.routeParams !== null) {
      this.tryInitWithParams(this.routeParams)
    }
  }

  private tryInitWithParams(params: ChatPageRouteParams | null): void {
    if (this.hasInitializedRoute) {
      return
    }
    this.hasInitializedRoute = true
    this.initWithParams(params)
  }

  // 从路由参数初始化页面（aboutToAppear 或 onReady 触发）
  private initWithParams(params: ChatPageRouteParams | null): void {
    this.applyRouteDisplaySeed(params)
    if (params !== null && params !== undefined) {
      console.info('ChatPage', `[initWithParams] sessionId=${params.sessionId ?? ''}`)
      if (params.sessionId !== undefined && params.sessionId !== '') {
        this.isNewChatTransition = false
      } else {
        this.isNewChatTransition = true
      }
    } else {
      console.info('ChatPage', '[initWithParams] params is null, treating as new chat')
      this.isNewChatTransition = true
    }
    this.loadData()
  }

  private applyRouteDisplaySeed(params: ChatPageRouteParams | null): void {
    if (params === null || params === undefined) {
      return
    }
    if (params.sessionTitle !== undefined && params.sessionTitle.trim() !== '') {
      this.sessionTitle = params.sessionTitle.trim()
    }
    if (this.currentModel === '' && params.modelId !== undefined && params.modelId.trim() !== '') {
      this.currentModelId = params.modelId.trim()
      this.currentModel = params.modelId.trim()
    }
  }

  // 修复页面恢复时可能的不一致状态。
  //
  // 这个方法承担"进程被杀 / App 后台清理后冷启动"的兜底语义:
  // - ToolExecutionService.pendingApprovals / pendingAnswers 都是内存 Map, 进程死了一起没;
  // - ChatViewModel.activeRequests / pendingAIMessages 也是内存里的, 同样进程死了就丢;
  // - 但已经 addMessage 进 DB 的 AI 消息可能带着 isGenerating=true / isSearching=true 残留,
  //   冷启动后没人 stream 那条消息, 这里发现"DB 标志开着 + activeRequests 没有匹配会话"就把
  //   isGenerating/isSearching/isSending 全部归位, 视觉上等同于"任务中断"。
  // - RUNNING_CHAT_TASK_COUNT 在 ChatTaskOrchestratorService 维护, 也是进程内 AppStorage,
  //   重启后默认从 0 起步, 不会出现"显示有 N 个在跑但其实没有"的鬼影。
  private fixInconsistentState(): void {
    const hasActiveRequestForCurrentSession = this.sessionId !== '' &&
      this.chatViewModel.hasActiveRequestForSession(this.sessionId)

    // 如果 isSending 为 true 但没有活跃请求，重置状态
    if (this.isSending && !hasActiveRequestForCurrentSession) {
      this.isSending = false
      this.currentTaskId = ''
      this.setGeneratingScrollTipVisible(false)
      // 同步清理 orchestrator 中该 session 的孤立 RUNNING 任务，
      // 避免全局并行任务计数不下降导致「并行任务已达上限」。
      this.chatTaskOrchestrator.failOrphanedTasksForSession(this.sessionId)
      console.info('ChatPage', '[fixInconsistentState] 重置 isSending 状态并清理孤立任务')
    }

    // 检查最后一条消息的 isGenerating 和 isSearching 状态
    if (this.messages.length > 0) {
      const lastMessage = this.messages[this.messages.length - 1]
      if (lastMessage.role === MessageRole.ASSISTANT) {
        // 如果没有活跃请求，重置生成状态
        if (lastMessage.isGenerating && !hasActiveRequestForCurrentSession) {
          lastMessage.isGenerating = false
          console.info('ChatPage', '[fixInconsistentState] 重置最后一条消息的 isGenerating 状态')
        }
        // 如果没有活跃请求，重置搜索状态
        if (lastMessage.isSearching && !hasActiveRequestForCurrentSession) {
          lastMessage.isSearching = false
          console.info('ChatPage', '[fixInconsistentState] 重置最后一条消息的 isSearching 状态')
        }
      }
    }
  }

  private updateStatusBar(): void {
    this.setChatStatusBarVisible(true)
  }

  private setChatStatusBarVisible(visible: boolean): void {
    const hostContext = this.getUIContext().getHostContext()
    if (hostContext === undefined || hostContext === null) {
      return
    }
    const context = hostContext as common.UIAbilityContext
    try {
      const mainWindow = context.windowStage.getMainWindowSync()
      mainWindow.setSpecificSystemBarEnabled('status', visible).catch((): void => {})
    } catch (error) {
      console.error('ChatPage', `Failed to update status bar visibility: ${JSON.stringify(error)}`)
    }
  }

  aboutToDisappear(): void {
    this.isPageVisible = false
    this.closeActiveChatImagePreview(false)
    this.resetDocumentParseQueue()
    // 释放TTS资源
    ServiceRegistry.tts().destroy()
    // 释放语音识别资源
    this.stopWaveformAnimation()
    this.stopRecordingSafetyTimer()
    ServiceRegistry.speechRecognition().shutdown()
    // 解绑 UIContext 防止 ChatPage 销毁后 typewriter 仍持有过期引用
    this.chatViewModel.setStreamingUIContext(null)
    this.clearInitialAlignmentTimers()
    this.clearPendingToolInteractionSyncTimer()
    this.clearRuntimeStateWatchdog()
    this.flushDraftAutosave(true).catch((error: Error): void => {
      console.error('ChatPage', `Failed to flush draft on disappear: ${JSON.stringify(error)}`)
    })
    this.unregisterAppUiStateObservers()
    this.syncActiveSessionBinding()
    // 离开页面时确保状态栏恢复
    this.setChatStatusBarVisible(true)

    if (this.shouldDeleteEmptySessionOnDisappear()) {
      this.chatViewModel.deleteSession(this.sessionId)
      console.info('ChatPage', '删除空会话: ' + this.sessionId)
    }
  }

  // 初始化TTS服务
  private async initTTSService(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      await ServiceRegistry.tts().init(context)
    } catch (error) {
      console.error('ChatPage', 'TTS初始化失败: ' + error)
    }
  }

  async loadData(): Promise<void> {
    const startTime = Date.now()
    hilog.info(DOMAIN, TAG, '📂 开始加载聊天页面数据...')
    this.resetScrollStateForSessionLoad()

    // 新建对话时不显示加载动画，让用户无感
    // 只有打开现有对话时才显示加载动画
    if (!this.isNewChatTransition) {
      this.isLoading = true
    }

    const loadResult = await this.getLoadFlow().loadPageData(this.routeParams, this.sessionTitle)

    this.applyLoadedSessionData(loadResult)
    await this.applyLoadedProviders(loadResult.providers)
    await this.syncToolAvailabilityFromPreferences()
    console.info(
      'ChatPage',
      `[loadData] 联网可用=${this.webSearchAvailable}, 联网查询=${this.webSearchConversationEnabled}, 已选工具=${this.selectedToolIds.join(',')}`
    )

    // 历史会话: 让 List 在 spinner 后面静默对齐到底部, 完成后再撤 spinner;
    // 新会话或空会话: 直接撤 spinner
    if (!this.isNewChatTransition && this.messages.length > 0) {
      this.performInitialBottomAlignmentBehindSpinner()
    } else {
      this.isLoading = false
    }

    const elapsed = Date.now() - startTime
    hilog.info(DOMAIN, TAG, '✅ 聊天页面数据加载完成 (耗时: %{public}dms)', elapsed)

    this.triggerPostLoadActions()
    this.activateCurrentSessionRuntimeState()
    this.refreshMcpToolAvailabilityInBackground(false)
  }

  private async applyLoadedProviders(providers: ModelProvider[]): Promise<void> {
    this.providers = providers
    console.info('ChatPage', `[loadData] Loaded ${this.providers.length} providers`)

    if (this.providers.length === 0) {
      this.currentModel = ''
      this.currentModelId = ''
      this.currentProvider = null
      return
    }
    await this.validateAndSetCurrentModel()
  }

  private replaceMessages(nextMessages: ChatMessage[]): void {
    this.messages.splice(0, this.messages.length, ...nextMessages)
    this.markMessageListChanged()
  }

  private clearMessages(): void {
    this.messages.splice(0, this.messages.length)
    this.markMessageListChanged()
  }

  private markMessageListChanged(changedMessageId: string = ''): void {
    this.messageListSyncMessageId = changedMessageId
    this.messageListSyncVersion = this.messageListSyncVersion + 1
  }

  private applyLoadedSessionData(loadResult: ChatPageLoadResult): void {
    this.pendingInitialPrompt = loadResult.pendingInitialPrompt
    this.pendingInitialToolIds = loadResult.pendingInitialToolIds
    this.initialPromptAutoSent = loadResult.initialPromptAutoSent
    this.sessionId = loadResult.sessionId
    this.sessionTitle = loadResult.sessionTitle
    this.webSearchAvailable = loadResult.webSearchEnabled
    this.webSearchConversationEnabled = loadResult.webSearchEnabled && loadResult.webSearchConversationEnabled
    // 这里仅回填已保存的模式, 不做 provider 可用性降级。
    // currentProvider 要等 applyLoadedProviders() 后才准确; 真正的可用性修正交给 refreshAvailableSearchEngines()。
    this.searchMode = loadResult.searchMode
    if (this.searchMode === ChatSearchMode.OPENAI_BUILTIN) {
      this.activeSearchEngineId = OPENAI_BUILTIN_SEARCH_ENGINE_ID
    }
    this.builtinImageGenEnabled = loadResult.builtinImageGenEnabled
    this.reasoningLevel = loadResult.reasoningLevel
    // initialDraft(来自推荐提示词点击)优先于持久化 draftText, 仅 prefill 不自动发送
    this.inputText = loadResult.pendingInitialDraft !== '' ? loadResult.pendingInitialDraft : loadResult.draftText
    this.resetDocumentParseQueue()
    this.pendingAttachments = [...loadResult.draftAttachments]
    this.preparePendingDocumentAttachments()
    this.isNewChatTransition = loadResult.isNewChatTransition
    this.isNewEmptySession = loadResult.isNewEmptySession
    this.applyAssistantSnapshot(loadResult.assistantId, loadResult.assistantAvatarSymbol, loadResult.assistantColor)

    if (!this.isNewChatTransition) {
      this.replaceMessages(loadResult.messages)
      hilog.info(DOMAIN, TAG, '📨 加载会话消息: %{public}d 条', this.messages.length)
      return
    }

    this.clearMessages()
  }

  private applyAssistantSnapshot(assistantId: string, avatarSymbol: string, color: string): void {
    this.currentAssistantId = assistantId.trim() !== '' ? assistantId.trim() : DEFAULT_ASSISTANT_ID
    this.currentAssistantAvatarSymbol = normalizeAssistantAvatarValue(avatarSymbol)
    this.currentAssistantColor = color.trim() !== '' ? color.trim() : DEFAULT_PRIMARY_COLOR
    this.bumpAssistantAvatarRenderTick()
  }

  private bumpAssistantAvatarRenderTick(): void {
    this.assistantAvatarRenderTick += 1
  }

  private getCurrentSessionAssistantId(): string {
    const currentSession = this.chatViewModel.getCurrentSession()
    if (currentSession !== null && currentSession.id === this.sessionId && currentSession.assistantId !== '') {
      return currentSession.assistantId
    }
    return this.currentAssistantId !== '' ? this.currentAssistantId : DEFAULT_ASSISTANT_ID
  }

  private async reloadCurrentAssistantAvatarSnapshot(): Promise<void> {
    const token = this.assistantAvatarReloadToken + 1
    this.assistantAvatarReloadToken = token
    const assistantId = this.getCurrentSessionAssistantId()
    let assistant: Assistant | null = await ServiceRegistry.assistant().getAssistant(assistantId)
    if (assistant === null && assistantId !== DEFAULT_ASSISTANT_ID) {
      assistant = await ServiceRegistry.assistant().getAssistant(DEFAULT_ASSISTANT_ID)
    }
    if (token !== this.assistantAvatarReloadToken) {
      return
    }
    if (assistant === null) {
      this.applyAssistantSnapshot(DEFAULT_ASSISTANT_ID, 'AI', DEFAULT_PRIMARY_COLOR)
      return
    }
    this.applyAssistantSnapshot(assistant.id, assistant.avatarSymbol, assistant.color)
  }

  private triggerPostLoadActions(): void {
    if (this.isNewChatTransition) {
      setTimeout(() => {
        this.autoFocusInput = true
      }, 50)
    }

    if (this.isNewChatTransition && this.pendingInitialPrompt !== '' && !this.initialPromptAutoSent) {
      setTimeout(() => {
        this.autoSendInitialPrompt()
      }, 120)
    }
  }

  onInAppTaskAlertPayloadChanged(): void {
    this.getTaskAlertFlow().handleInAppTaskAlertPayload(this.inAppTaskAlertPayload)
  }

  onOpenSessionPayloadChanged(): void {
    this.getTaskAlertFlow().handleOpenSessionPayload(this.openSessionPayload)
  }

  onTaskEventTickChanged(): void {
    if (!this.isPageVisible || this.sessionId === '') {
      return
    }
    this.syncSendingStateFromRuntime()
    this.fixInconsistentState()
    this.updateRuntimeStateWatchdog()
  }

  private onPendingToolInteractionChanged(): void {
    if (this.pendingToolInteractionTick <= 0) {
      return
    }
    this.schedulePendingToolInteractionSync()
  }

  private schedulePendingToolInteractionSync(): void {
    if (this.pendingToolInteractionSyncTimerId !== -1) {
      clearTimeout(this.pendingToolInteractionSyncTimerId)
    }
    this.pendingToolInteractionSyncTimerId = setTimeout((): void => {
      this.pendingToolInteractionSyncTimerId = -1
      if (!this.isPageVisible || this.sessionId === '') {
        return
      }
      this.markMessageListChanged()
      this.syncPendingToolInteractionFromService()
    }, 0)
  }

  private registerAppUiStateObservers(): void {
    if (this.appUiStateDisposers.length > 0) {
      return
    }
    this.appUiStateDisposers = [
      observeAppUiState(AppStorageKeys.IN_APP_TASK_ALERT_PAYLOAD, (): void => this.onInAppTaskAlertPayloadChanged()),
      observeAppUiState(AppStorageKeys.OPEN_SESSION_PAYLOAD, (): void => this.onOpenSessionPayloadChanged()),
      observeAppUiState(AppStorageKeys.TASK_EVENT_TICK, (): void => this.onTaskEventTickChanged()),
      observeAppUiState(AppStorageKeys.PENDING_TOOL_INTERACTION_TICK,
        (): void => this.onPendingToolInteractionChanged()),
      observeAppUiState(AppStorageKeys.ASSISTANT_AVATAR_REFRESH_AT, (): void => this.onAssistantAvatarRefreshChanged()),
      observeAppUiState(AppStorageKeys.APP_IN_BACKGROUND, (): void => this.onAppBackgroundChanged()),
      observeAppUiState(AppStorageKeys.STAR_EARNED_TICK, (): void => this.onStarEarnedTickChanged()),
      getToolExecutionService().addPendingInteractionChangeCallback((): void => {
        this.schedulePendingToolInteractionSync()
      })
    ]
  }

  private onStarEarnedTickChanged(): void {
    const grantJson = getAppUiState().starLastGrant
    if (grantJson === '') {
      return
    }
    try {
      const grant = JSON.parse(grantJson) as Record<string, Object>
      const stars = (grant['stars'] as number) ?? 0
      const type = (grant['activityType'] as string) ?? ''
      if (stars <= 0) {
        return
      }
      const tip = this.formatStarGrantTip(type, stars)
      showToast(this.getUIContext(), tip, 1500)
    } catch (error) {
      console.error('ChatPage', `Failed to parse starLastGrant: ${JSON.stringify(error)}`)
    }
  }

  private formatStarGrantTip(activityType: string, stars: number): string {
    if (activityType !== 'math_quiz' && activityType !== 'english_quiz' && activityType !== 'number_puzzle') {
      return `+${stars} ⭐`
    }
    const meta = getActivityMeta(activityType as StarActivityType)
    return `+${stars} ⭐ ${meta.grantedHint}`
  }

  private onAssistantAvatarRefreshChanged(): void {
    this.reloadCurrentAssistantAvatarSnapshot().catch((error: Error): void => {
      console.error('ChatPage', `Failed to reload assistant avatar snapshot: ${JSON.stringify(error)}`)
    })
  }

  private unregisterAppUiStateObservers(): void {
    for (let i = 0; i < this.appUiStateDisposers.length; i++) {
      this.appUiStateDisposers[i]()
    }
    this.appUiStateDisposers = []
  }

  private clearPendingToolInteractionSyncTimer(): void {
    if (this.pendingToolInteractionSyncTimerId === -1) {
      return
    }
    clearTimeout(this.pendingToolInteractionSyncTimerId)
    this.pendingToolInteractionSyncTimerId = -1
  }

  private syncActiveSessionBinding(): void {
    const activeSessionId = this.isPageVisible && this.sessionId !== '' ? this.sessionId : ''
    setAppUiStateValue(AppStorageKeys.ACTIVE_CHAT_SESSION_ID, activeSessionId)
  }

  private onAppBackgroundChanged(): void {
    if (this.appInBackground) {
      if (this.isMultiSelectMode) {
        this.handleExitMultiSelectMode()
      }
    }
  }

  private handlePageShown(): void {
    this.isPageVisible = true
    this.syncActiveSessionBinding()
    if (this.isLoading || this.sessionId === '') {
      return
    }
    this.preparePendingDocumentAttachments()
    this.refreshToolAvailabilityOnShown()
    this.syncSendingStateFromRuntime()
    this.fixInconsistentState()
    this.refreshProviders()
    this.updateRuntimeStateWatchdog()
    // 重新进入页面视为"再次提醒",清掉折叠态让待确认 sheet 重新弹一次,
    // 满足"返回会话继续弹出原来的授权框"的产品语义。
    this.expandPendingToolApproval()
    // 检查在页面切换间隙到达的 in-app alert
    this.getTaskAlertFlow().handleInAppTaskAlertPayload(this.inAppTaskAlertPayload)
  }

  private activateCurrentSessionRuntimeState(): void {
    this.syncActiveSessionBinding()
    this.syncSendingStateFromRuntime()
    this.fixInconsistentState()
    this.getTaskAlertFlow().handleOpenSessionPayload(this.openSessionPayload)
    this.getTaskAlertFlow().handleInAppTaskAlertPayload(this.inAppTaskAlertPayload)
    this.updateRuntimeStateWatchdog()
    this.expandPendingToolApproval()
  }

  private clearInitialAlignmentTimers(): void {
    for (let i = 0; i < this.initialAlignmentTimerIds.length; i++) {
      clearTimeout(this.initialAlignmentTimerIds[i])
    }
    this.initialAlignmentTimerIds.splice(0, this.initialAlignmentTimerIds.length)
  }

  private resetScrollStateForSessionLoad(): void {
    this.clearInitialAlignmentTimers()
    this.lastScrollOffset = 0
    this.currentScrollOffsetVp = 0
    this.isAtTop = false
    this.isAtBottom = false
    this.isGeneratingScrollTipVisible = false
    this.firstVisibleListIndex = 0
    this.lastVisibleListIndex = 0
    this.maxScrollOffset = 0
    this.scroller = new Scroller()
    this.scrollUiFlow = null
  }

  private shouldSyncScrollOffsetToUi(value: number): boolean {
    if (this.isAtTop || this.isAtBottom) {
      return true
    }
    return Math.abs(this.currentScrollOffsetVp - value) >= this.scrollOffsetUiSyncStepVp
  }

  private handleMessageLinkOpen(title: string, url: string): void {
    this.messageWebSheetTitle = title
    this.messageWebSheetUrl = url
    this.showMessageWebSheet = true
  }

  @Builder
  private MessageWebSheetBuilder() {
    Column() {
      if (this.messageWebSheetUrl !== '') {
        Web({ src: this.messageWebSheetUrl, controller: this.messageSheetWebController })
          .width('100%')
          .layoutWeight(1)
      } else {
        Column() {
          Text($r('app.string.common_invalid_link'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }

  private performInitialBottomAlignmentBehindSpinner(): void {
    // 时序: 此刻 isLoading 仍为 true, ChatMessageListSection 内 List 已经开始渲染(被 spinner 罩住)。
    // LazyForEach 异步加载首屏 item, scroller 在加载未稳定期间不可靠 ——
    // 必须等 lastVisibleListIndex 真到达 bottomAnchor 才撤 spinner, 否则用户看到的不是真底部,
    // 且后续 scrollEdge(Top) 会被 LazyForEach 的"维持视觉位置"调整抵消, 跳到顶部按钮点击失效。
    this.clearInitialAlignmentTimers()
    const flow = this.getScrollUiFlow()
    flow.setIsAtBottom(true)
    flow.setIsAtTop(false)
    const startedAt = Date.now()
    const maxWaitMs = 1500
    const pollIntervalMs = 60
    const tick = (): void => {
      const anchor = this.getBottomAnchorListIndex()
      // scrollToIndex 让 LazyForEach 主动加载末尾 item, 比 scrollEdge(Bottom) 精确
      this.scroller.scrollToIndex(anchor, false, ScrollAlign.END)
      const reachedBottom = this.lastVisibleListIndex >= anchor - 1 && this.lastVisibleListIndex > 0
      const timedOut = Date.now() - startedAt >= maxWaitMs
      if (reachedBottom || timedOut) {
        this.initialAlignmentTimerIds.push(setTimeout((): void => {
          this.isLoading = false
        }, 40))
        return
      }
      this.initialAlignmentTimerIds.push(setTimeout(tick, pollIntervalMs))
    }
    this.initialAlignmentTimerIds.push(setTimeout(tick, 0))
  }

  private refreshToolAvailabilityOnShown(): void {
    this.syncToolAvailabilityFromPreferences().then(() => {
      this.refreshMcpToolAvailabilityInBackground(false)
    }).catch((error: Object) => {
      console.warn('ChatPage', `[refreshToolAvailabilityOnShown] Failed: ${JSON.stringify(error)}`)
    })
  }

  private getBottomAnchorListIndex(): number {
    const draftItemCount = !this.isEditingMessage && this.hasDraftContent() ? 1 : 0
    return this.messages.length + 1 + draftItemCount
  }

  private getTotalListItemCount(): number {
    // 1 (top padding) + messages + draft preview (0 or 1) + 1 (bottom padding)
    const draftItemCount = !this.isEditingMessage && this.hasDraftContent() ? 1 : 0
    return 1 + this.messages.length + draftItemCount + 1
  }

  private getCurrentModelInfo(): ModelInfo | null {
    if (this.currentProvider === null || this.currentModelId === '') {
      return null
    }
    for (let i = 0; i < this.currentProvider.models.length; i++) {
      const model = this.currentProvider.models[i]
      if (model.id === this.currentModelId) {
        return model
      }
    }
    return null
  }

  private supportsReasoningForCurrentModel(): boolean {
    const model = this.getCurrentModelInfo()
    return model !== null && getEffectiveCapabilities(model).supportsReasoning
  }

  private supportsReasoningXhighForCurrentModel(): boolean {
    const model = this.getCurrentModelInfo()
    if (this.currentProvider === null || model === null) {
      return false
    }
    return supportsReasoningXhighControl(
      {
        providerId: this.currentProvider.id,
        baseUrl: this.currentProvider.baseUrl,
        apiStyle: this.currentProvider.apiStyle
      },
      model.id,
      getEffectiveCapabilities(model).supportsReasoning,
      this.getCurrentReasoningStrategyOverride()
    )
  }

  private getReasoningControlModeForCurrentModel(): ReasoningControlMode {
    const model = this.getCurrentModelInfo()
    if (this.currentProvider === null || model === null) {
      return ReasoningControlMode.NONE
    }
    return this.getReasoningControlModeForModel(this.currentProvider, model)
  }

  private getReasoningControlModeForModel(provider: ModelProvider, model: ModelInfo): ReasoningControlMode {
    return resolveReasoningControlMode(
      {
        providerId: provider.id,
        baseUrl: provider.baseUrl,
        apiStyle: provider.apiStyle
      },
      model.id,
      getEffectiveCapabilities(model).supportsReasoning,
      this.getCurrentReasoningStrategyOverride()
    )
  }

  private getCurrentReasoningStrategyOverride(): string {
    return ''
  }

  private syncReasoningAvailabilityWithCurrentModel(): void {
    const controlMode = this.getReasoningControlModeForCurrentModel()
    if (controlMode === ReasoningControlMode.NONE) {
      this.reasoningLevel = ReasoningLevel.OFF
      return
    }
    this.reasoningLevel = this.normalizeReasoningLevelForCurrentModel(this.reasoningLevel)
  }

  private resetReasoningForSelectedModel(provider: ModelProvider, model: ModelInfo): void {
    const controlMode = this.getReasoningControlModeForModel(provider, model)
    const resetLevel = resolveModelSwitchReasoningLevel(controlMode)
    if (resetLevel === ReasoningLevel.OFF) {
      this.reasoningLevel = ReasoningLevel.OFF
    } else {
      this.reasoningLevel = this.normalizeReasoningLevelForControlMode(
        ReasoningLevel.AUTO,
        controlMode,
        provider,
        model
      )
    }
    this.persistReasoningPreference(this.reasoningLevel)
  }

  private normalizeReasoningLevelForCurrentModel(value: ReasoningLevel): ReasoningLevel {
    const model = this.getCurrentModelInfo()
    if (this.currentProvider === null || model === null) {
      return ReasoningLevel.OFF
    }
    return this.normalizeReasoningLevelForControlMode(
      value,
      this.getReasoningControlModeForModel(this.currentProvider, model),
      this.currentProvider,
      model
    )
  }

  private normalizeReasoningLevelForControlMode(
    value: ReasoningLevel,
    controlMode: ReasoningControlMode,
    provider: ModelProvider,
    model: ModelInfo
  ): ReasoningLevel {
    const normalized = normalizeReasoningLevelForControl(value, controlMode)
    if (normalized === ReasoningLevel.XHIGH && !supportsReasoningXhighControl(
      {
        providerId: provider.id,
        baseUrl: provider.baseUrl,
        apiStyle: provider.apiStyle
      },
      model.id,
      getEffectiveCapabilities(model).supportsReasoning,
      this.getCurrentReasoningStrategyOverride()
    )) {
      return ReasoningLevel.HIGH
    }
    return normalized
  }

  private applySelectedToolIdsInMemory(toolIds: string[], enabledMcpServerIds?: Set<string>): void {
    this.selectedToolIds = [...this.normalizeSelectedToolIdsForPicker(toolIds, enabledMcpServerIds)]
  }

  private async setSelectedToolIds(toolIds: string[]): Promise<void> {
    const normalizedToolIds = this.normalizeSelectedToolIdsForPicker(toolIds)
    const savedToolIds = await this.mcpService.saveSelectedToolIds(normalizedToolIds)
    const enabledMcpServerIds = await this.loadEnabledMcpServerIds()
    this.applySelectedToolIdsInMemory(savedToolIds, enabledMcpServerIds)
  }

  private isWebSearchReady(): boolean {
    return this.webSearchAvailable && this.availableSearchEngines.length > 0
  }

  // 当前 provider 是否能走 OpenAI Responses 内置 web_search hosted tool。
  // 判定: apiStyle === OPENAI && openaiTransport === RESPONSES。
  // 模型层面的 supportsWebSearch 不卡, 让 OpenAI 路径自然 fallback (官方支持的 GPT 全系都能用)。
  private isOpenAIBuiltinSearchAvailableForCurrentProvider(): boolean {
    const provider = this.currentProvider
    if (provider === null) {
      return false
    }
    if (provider.apiStyle !== ApiStyle.OPENAI) {
      return false
    }
    return provider.openaiTransport === OpenAITransport.RESPONSES
  }

  // hosted image_generation 走 Responses, transport 与 web_search 同口径; 模型层面卡 IMAGE_GEN_TOOL 白名单
  // (GPT-5 全系, 详见 ModelAbilityRegistry), 不在白名单内的模型不展示该 chip, 避免请求被 OpenAI 端拒绝。
  private isOpenAIBuiltinImageGenAvailableForCurrentProvider(): boolean {
    if (!this.isOpenAIBuiltinSearchAvailableForCurrentProvider()) {
      return false
    }
    if (this.currentModelId === '') {
      return false
    }
    return modelSupportsImageGenerationTool(this.currentModelId)
  }

  private resolveEffectiveSearchModeForCurrentProvider(mode: ChatSearchMode): ChatSearchMode {
    if (mode === ChatSearchMode.OPENAI_BUILTIN && !this.isOpenAIBuiltinSearchAvailableForCurrentProvider()) {
      return ChatSearchMode.EXTERNAL_ENGINE
    }
    return mode
  }

  private getActiveComposerBuiltinImageGenEnabled(): boolean {
    return this.builtinImageGenEnabled
  }

  private handleComposerImageGenToggle(): void {
    if (!this.isOpenAIBuiltinImageGenAvailableForCurrentProvider()) {
      return
    }
    const enabled = !this.builtinImageGenEnabled
    this.builtinImageGenEnabled = enabled
    this.persistBuiltinImageGenPreference(enabled)
  }

  private persistBuiltinImageGenPreference(enabled: boolean): void {
    this.preferencesService.setBoolean(PreferenceKeys.CHAT_BUILTIN_IMAGE_GEN_ENABLED, enabled).catch((error: Object) => {
      console.error('ChatPage', `Failed to persist built-in image generation: ${JSON.stringify(error)}`)
    })
  }

  // 切换搜索模式持久化 (external_engine / openai_builtin)。
  private persistSearchModePreference(mode: ChatSearchMode): void {
    this.preferencesService.setString(PreferenceKeys.SEARCH_MODE, mode).catch((error: Object) => {
      console.error('ChatPage', `Failed to persist search mode: ${JSON.stringify(error)}`)
    })
  }

  private async setWebSearchConversationEnabled(enabled: boolean): Promise<void> {
    const normalized = this.isWebSearchReady() && enabled
    await this.preferencesService.setBoolean(PreferenceKeys.SEARCH_CONVERSATION_ENABLED, normalized)
    this.webSearchConversationEnabled = normalized
  }

  private rebuildAvailableChatTools(): void {
    const configs = this.toolRegistry.getAllToolConfigs()
    const tools: ToolConfig[] = []
    for (let i = 0; i < configs.length; i++) {
      if (configs[i].enabled && !isSearchToolId(configs[i].id)) {
        tools.push(configs[i])
      }
    }
    this.availableChatTools = tools
  }

  private async loadEnabledMcpServerIds(): Promise<Set<string>> {
    const configs = await this.mcpService.loadServerConfigs()
    const enabledServerIds: Set<string> = new Set<string>()
    for (let i = 0; i < configs.length; i++) {
      if (configs[i].enabled) {
        enabledServerIds.add(configs[i].id)
      }
    }
    return enabledServerIds
  }

  private normalizeStoredSelectedToolIdsLocally(toolIds: string[]): string[] {
    const normalizedToolIds: string[] = []
    for (let i = 0; i < toolIds.length; i++) {
      const toolId = toolIds[i].trim()
      if (toolId === '' || isSearchToolId(toolId)) {
        continue
      }
      if (!normalizedToolIds.includes(toolId)) {
        normalizedToolIds.push(toolId)
      }
    }
    return normalizedToolIds
  }

  private extractMcpSourceIdFromToolId(toolId: string): string {
    if (!toolId.startsWith('mcp:')) {
      return ''
    }
    const raw = toolId.substring(4)
    const separatorIndex = raw.indexOf(':')
    if (separatorIndex <= 0) {
      return ''
    }
    return raw.substring(0, separatorIndex)
  }

  private async syncToolAvailabilityFromPreferences(): Promise<void> {
    const webSearchAvailable = await this.preferencesService.getBoolean(PreferenceKeys.SEARCH_SERVICE_ENABLED, false)
    this.webSearchAvailable = webSearchAvailable
    this.webSearchConversationEnabled = webSearchAvailable && await this.preferencesService.getBoolean(
      PreferenceKeys.SEARCH_CONVERSATION_ENABLED,
      webSearchAvailable
    )
    const searchToolIds = getSearchToolIds()
    for (let i = 0; i < searchToolIds.length; i++) {
      const searchTool = this.toolRegistry.getTool(searchToolIds[i])
      if (searchTool !== undefined) {
        searchTool.config.enabled = webSearchAvailable
      }
    }
    this.rebuildAvailableChatTools()
    await this.refreshAvailableSearchEngines()
    if (this.availableSearchEngines.length === 0 && this.webSearchConversationEnabled) {
      this.webSearchConversationEnabled = false
      await this.preferencesService.setBoolean(PreferenceKeys.SEARCH_CONVERSATION_ENABLED, false)
    }
    const enabledMcpServerIds = await this.loadEnabledMcpServerIds()
    const selectedToolIds = await this.mcpService.loadSelectedToolIds()
    this.applySelectedToolIdsInMemory(selectedToolIds, enabledMcpServerIds)
  }

  // 重建联网菜单的引擎列表 + 当前活跃引擎。
  // 可用 = 在工具中心启用，并且引擎没有需要密码的配置项(Bing) 或至少一个密码字段非空。
  // 末尾若 currentProvider 满足 OpenAI Responses 条件, 自动追加 OPENAI_BUILTIN_SEARCH_ENGINE_ID 哨兵项,
  // 让用户在同一个菜单内切换"外部引擎 / OpenAI 内置搜索"。
  private async refreshAvailableSearchEngines(): Promise<void> {
    registerAllSearchEngines()
    const registry = getSearchEngineRegistry()
    const descriptors = registry.getAll()
    const storedEngineRaw = await this.preferencesService.getString(PreferenceKeys.SEARCH_ENGINE, SearchEngine.BING)
    const storedEngine = registry.parseEngine(storedEngineRaw)
    const enabledEngineIds = await this.loadEnabledSearchEngineIds(storedEngine)
    const next: SearchEngineMenuOption[] = []
    for (let i = 0; i < descriptors.length; i++) {
      if (enabledEngineIds.includes(descriptors[i].id) && await this.isSearchEngineConfigured(descriptors[i])) {
        next.push({ id: descriptors[i].id as string, label: descriptors[i].label })
      }
    }
    if (this.isOpenAIBuiltinSearchAvailableForCurrentProvider()) {
      next.push({
        id: OPENAI_BUILTIN_SEARCH_ENGINE_ID,
        label: pickLocalizedText('OpenAI 内置搜索', 'OpenAI built-in search')
      })
    }
    this.availableSearchEngines = next

    // 优先级:
    // 1) searchMode === OPENAI_BUILTIN 且菜单仍有哨兵 → 哨兵 id
    // 2) 已存的外部引擎 id 仍可用 → 沿用
    // 3) 退化到列表第一项 (持久化到 SEARCH_ENGINE)
    if (this.searchMode === ChatSearchMode.OPENAI_BUILTIN &&
      this.isSearchEngineMenuOptionAvailable(OPENAI_BUILTIN_SEARCH_ENGINE_ID)) {
      this.activeSearchEngineId = OPENAI_BUILTIN_SEARCH_ENGINE_ID
      return
    }
    // mode 是 builtin 但菜单已不含哨兵时, 只临时显示外部引擎。
    // 不覆盖 SEARCH_MODE, 否则用户切回支持 Responses hosted search 的模型后会丢失上次选择。
    if (this.isSearchEngineMenuOptionAvailable(storedEngine)) {
      this.activeSearchEngineId = storedEngine
      return
    }
    if (next.length > 0) {
      // 不能把哨兵当默认引擎写到 SEARCH_ENGINE; 选第一个真正的外部引擎
      let fallbackEngineId: string = ''
      for (let i = 0; i < next.length; i++) {
        if (next[i].id !== OPENAI_BUILTIN_SEARCH_ENGINE_ID) {
          fallbackEngineId = next[i].id
          break
        }
      }
      if (fallbackEngineId !== '') {
        this.activeSearchEngineId = fallbackEngineId
        await this.preferencesService.setString(PreferenceKeys.SEARCH_ENGINE, fallbackEngineId)
        return
      }
    }
    this.activeSearchEngineId = storedEngine
  }

  private async loadEnabledSearchEngineIds(storedEngine: SearchEngine): Promise<string[]> {
    const raw = await this.preferencesService.getString(PreferenceKeys.SEARCH_ENABLED_ENGINE_IDS_JSON, '')
    if (raw.trim() !== '') {
      return parseSearchEngineIdListJson(raw)
    }

    const defaults: string[] = [SearchEngine.BING]
    const descriptors = getSearchEngineRegistry().getAll()
    for (let i = 0; i < descriptors.length; i++) {
      const engineId = descriptors[i].id
      if (engineId !== SearchEngine.BING && await this.isSearchEngineConfigured(descriptors[i]) &&
        !defaults.includes(engineId)) {
        defaults.push(engineId)
      }
    }
    const storedDesc = getSearchEngineRegistry().getById(storedEngine)
    if (storedEngine !== SearchEngine.BING && storedDesc !== undefined &&
      await this.isSearchEngineConfigured(storedDesc) && !defaults.includes(storedEngine)) {
      defaults.push(storedEngine)
    }
    return defaults
  }

  private isSearchEngineMenuOptionAvailable(engineId: string): boolean {
    for (let i = 0; i < this.availableSearchEngines.length; i++) {
      if (this.availableSearchEngines[i].id === engineId) {
        return true
      }
    }
    return false
  }

  private async isSearchEngineConfigured(desc: SearchEngineDescriptor): Promise<boolean> {
    let hasPasswordField = false
    for (let i = 0; i < desc.configFields.length; i++) {
      if (desc.configFields[i].isPassword) {
        hasPasswordField = true
        const value = await this.preferencesService.getString(desc.configFields[i].key, '')
        if (value.trim() !== '') {
          return true
        }
      }
    }
    // 无密码字段(Bing 这种零配置引擎) -> 始终可用
    return !hasPasswordField
  }

  private async refreshMcpToolAvailability(showError: boolean): Promise<void> {
    let refreshError: Object | null = null
    try {
      await this.mcpService.refreshAllServers()
    } catch (error) {
      refreshError = error
      console.warn('ChatPage', `[refreshMcpToolAvailability] MCP refresh failed: ${JSON.stringify(error)}`)
    }
    this.rebuildAvailableChatTools()
    const enabledMcpServerIds = await this.loadEnabledMcpServerIds()
    const selectedToolIds = await this.mcpService.loadSelectedToolIds()
    this.applySelectedToolIdsInMemory(selectedToolIds, enabledMcpServerIds)
    if (showError && refreshError !== null) {
      this.showError(pickLocalizedText('刷新工具失败', 'Failed to refresh tools'))
    }
  }

  private runMcpToolAvailabilityRefresh(showError: boolean): Promise<void> {
    if (this.mcpToolAvailabilityRefreshTask !== null) {
      return this.mcpToolAvailabilityRefreshTask
    }
    this.isRefreshingMcpToolAvailability = true
    const task = this.refreshMcpToolAvailability(showError).catch((error: Object) => {
      console.error('ChatPage', `[runMcpToolAvailabilityRefresh] Failed: ${JSON.stringify(error)}`)
      if (showError) {
        this.showError(pickLocalizedText('刷新工具失败', 'Failed to refresh tools'))
      }
    }).finally(() => {
      this.isRefreshingMcpToolAvailability = false
      if (this.mcpToolAvailabilityRefreshTask === task) {
        this.mcpToolAvailabilityRefreshTask = null
      }
    })
    this.mcpToolAvailabilityRefreshTask = task
    return task
  }

  private refreshMcpToolAvailabilityInBackground(showError: boolean): void {
    this.runMcpToolAvailabilityRefresh(showError)
  }

  private collectPendingEnabledMcpToolIds(toolIds: string[], enabledMcpServerIds: Set<string>): string[] {
    const pendingToolIds: string[] = []
    const normalizedToolIds = this.normalizeStoredSelectedToolIdsLocally(toolIds)
    for (let i = 0; i < normalizedToolIds.length; i++) {
      const toolId = normalizedToolIds[i]
      const sourceId = this.extractMcpSourceIdFromToolId(toolId)
      if (sourceId === '' || !enabledMcpServerIds.has(sourceId)) {
        continue
      }
      if (!this.toolRegistry.isToolRegistered(toolId)) {
        pendingToolIds.push(toolId)
      }
    }
    return pendingToolIds
  }

  private isMcpChatTool(tool: ToolConfig): boolean {
    return tool.sourceType === ToolSourceType.MCP && tool.sourceId.trim() !== ''
  }

  private normalizeSelectedToolIdsForPicker(toolIds: string[], enabledMcpServerIds?: Set<string>): string[] {
    const normalizedToolIds = this.normalizeStoredSelectedToolIdsLocally(toolIds)
    const selectedBuiltinToolIds: Set<string> = new Set<string>()
    const selectedMcpSourceIds: Set<string> = new Set<string>()
    const availableMcpSourceIds: Set<string> = new Set<string>()
    for (let i = 0; i < this.availableChatTools.length; i++) {
      const tool = this.availableChatTools[i]
      if (this.isMcpChatTool(tool)) {
        availableMcpSourceIds.add(tool.sourceId)
      }
    }
    for (let i = 0; i < normalizedToolIds.length; i++) {
      const toolId = normalizedToolIds[i]
      const registeredTool = this.toolRegistry.getTool(toolId)
      if (registeredTool !== undefined && registeredTool.config.enabled) {
        if (this.isMcpChatTool(registeredTool.config)) {
          selectedMcpSourceIds.add(registeredTool.config.sourceId)
          continue
        }
        selectedBuiltinToolIds.add(toolId)
        continue
      }
      const sourceId = this.extractMcpSourceIdFromToolId(toolId)
      if (sourceId !== '' && (enabledMcpServerIds === undefined || enabledMcpServerIds.has(sourceId))) {
        selectedMcpSourceIds.add(sourceId)
      }
    }
    for (let i = 0; i < this.availableChatTools.length; i++) {
      const tool = this.availableChatTools[i]
      if (this.isMcpChatTool(tool)) {
        if (selectedMcpSourceIds.has(tool.sourceId)) {
          selectedBuiltinToolIds.add(tool.id)
        }
        continue
      }
      if (!selectedBuiltinToolIds.has(tool.id)) {
        continue
      }
    }

    const pickerToolIds: string[] = []
    for (let i = 0; i < this.availableChatTools.length; i++) {
      const tool = this.availableChatTools[i]
      if (this.isMcpChatTool(tool)) {
        if (selectedMcpSourceIds.has(tool.sourceId)) {
          pickerToolIds.push(tool.id)
        }
        continue
      }
      if (selectedBuiltinToolIds.has(tool.id)) {
        pickerToolIds.push(tool.id)
      }
    }
    for (let i = 0; i < normalizedToolIds.length; i++) {
      const toolId = normalizedToolIds[i]
      const sourceId = this.extractMcpSourceIdFromToolId(toolId)
      if (sourceId === '' || !selectedMcpSourceIds.has(sourceId) || availableMcpSourceIds.has(sourceId)) {
        continue
      }
      if (!pickerToolIds.includes(toolId)) {
        pickerToolIds.push(toolId)
      }
    }
    return pickerToolIds
  }

  private getActiveComposerWebSearchEnabled(): boolean {
    return this.webSearchConversationEnabled
  }

  private getActiveComposerSelectedToolIds(): string[] {
    return this.selectedToolIds
  }

  private getActiveComposerReasoningLevel(): ReasoningLevel {
    return this.reasoningLevel
  }

  private updateActiveComposerSelectedToolIds(toolIds: string[]): Promise<void> {
    const normalizedToolIds = this.normalizeSelectedToolIdsForPicker(toolIds)
    return this.setSelectedToolIds(normalizedToolIds)
  }

  private updateActiveComposerReasoningLevel(value: ReasoningLevel): void {
    const normalizedLevel = this.normalizeReasoningLevelForCurrentModel(value)
    this.reasoningLevel = normalizedLevel
    this.persistReasoningPreference(normalizedLevel)
  }

  private persistReasoningPreference(level: ReasoningLevel): void {
    this.persistReasoningPreferenceAsync(level).catch((error: Object) => {
      console.error('ChatPage', `[persistReasoningPreference] Failed: ${JSON.stringify(error)}`)
    })
  }

  private async persistReasoningPreferenceAsync(level: ReasoningLevel): Promise<void> {
    await this.preferencesService.setString(PreferenceKeys.CHAT_REASONING_LEVEL, level)
  }

  private handleComposerWebSearchSelect(engineId: string): void {
    // engineId 非空 = 选择某个引擎并启用联网; 空串 = "禁用联网"项。
    // 'openai_builtin' 哨兵 → 切到 hosted 搜索模式 (不写 SEARCH_ENGINE), 其它 → 外部引擎模式。
    if (engineId !== '') {
      if (!this.isSearchEngineMenuOptionAvailable(engineId)) {
        this.showError(pickLocalizedText('该搜索服务不可用，请先在工具中心启用并完成配置',
          'This search service is unavailable. Enable and configure it in Tools first.'))
        return
      }
      this.activeSearchEngineId = engineId
      if (engineId === OPENAI_BUILTIN_SEARCH_ENGINE_ID) {
        // hosted 搜索: 持久化 mode, 不要写 SEARCH_ENGINE 避免污染下次外部引擎切换
        this.searchMode = ChatSearchMode.OPENAI_BUILTIN
        this.persistSearchModePreference(ChatSearchMode.OPENAI_BUILTIN)
      } else {
        this.searchMode = ChatSearchMode.EXTERNAL_ENGINE
        this.persistSearchModePreference(ChatSearchMode.EXTERNAL_ENGINE)
        this.persistSearchEnginePreference(engineId)
      }
    }
    const enableSearch = engineId !== ''
    this.setWebSearchConversationEnabled(enableSearch).catch((error: Object) => {
      console.error('ChatPage', `Failed to update chat search setting: ${JSON.stringify(error)}`)
      this.showError(pickLocalizedText('联网查询开关保存失败', 'Failed to save web search toggle'))
    })
  }

  private persistSearchEnginePreference(engineId: string): void {
    this.preferencesService.setString(PreferenceKeys.SEARCH_ENGINE, engineId).catch((error: Object) => {
      console.error('ChatPage', `Failed to persist search engine: ${JSON.stringify(error)}`)
    })
  }

  private handleMcpToolGroupSelectionToggle(toolIds: string[], enabled: boolean): void {
    const nextToolIds = [...this.getActiveComposerSelectedToolIds()]
    for (let i = 0; i < toolIds.length; i++) {
      const toolId = toolIds[i]
      const index = nextToolIds.indexOf(toolId)
      if (enabled && index < 0) {
        nextToolIds.push(toolId)
      }
      if (!enabled && index >= 0) {
        nextToolIds.splice(index, 1)
      }
    }
    this.updateActiveComposerSelectedToolIds(nextToolIds).catch((error: Object) => {
      console.error('ChatPage', `Failed to update selected MCP tool group: ${JSON.stringify(error)}`)
      this.showError(pickLocalizedText('工具选择保存失败', 'Failed to save tool selection'))
    })
  }

  private hasSelectedTools(): boolean {
    return this.getActiveComposerSelectedToolIds().length > 0
  }

  private getDefaultSessionTitle(): string {
    return pickLocalizedText('新对话', 'New Chat')
  }

  private getNoToolArgumentsText(): string {
    return pickLocalizedText('无参数', 'No arguments')
  }

  private syncSendingStateFromRuntime(): void {
    if (this.sessionId === '') {
      this.isSending = false
      this.currentTaskId = ''
      this.setGeneratingScrollTipVisible(false)
      return
    }
    this.isSending = this.chatViewModel.hasActiveRequestForSession(this.sessionId)
    if (!this.isSending) {
      this.currentTaskId = ''
      this.setGeneratingScrollTipVisible(false)
      return
    }
    if (this.shouldRevealGeneratingScrollTipFromCurrentPosition()) {
      this.setGeneratingScrollTipVisible(true)
    }
  }

  private updateRuntimeStateWatchdog(): void {
    const hasActiveRequestForCurrentSession = this.sessionId !== '' &&
      this.chatViewModel.hasActiveRequestForSession(this.sessionId)
    if (!this.isPageVisible || !hasActiveRequestForCurrentSession) {
      this.clearRuntimeStateWatchdog()
      return
    }
    if (this.runtimeStateWatchdogTimerId !== -1) {
      return
    }
    this.runtimeStateWatchdogTimerId = setInterval(() => {
      if (!this.isPageVisible || this.sessionId === '') {
        this.clearRuntimeStateWatchdog()
        return
      }
      this.syncPendingToolInteractionFromService()
      if (this.chatViewModel.hasActiveRequestForSession(this.sessionId)) {
        return
      }
      this.syncSendingStateFromRuntime()
      this.fixInconsistentState()
      this.clearRuntimeStateWatchdog()
    }, 220)
  }

  private clearRuntimeStateWatchdog(): void {
    if (this.runtimeStateWatchdogTimerId === -1) {
      return
    }
    clearInterval(this.runtimeStateWatchdogTimerId)
    this.runtimeStateWatchdogTimerId = -1
  }

  private parseToolIdsFromRoute(raw: string): string[] {
    return parseToolIdsFromRouteRaw(raw)
  }

  private getSendFlow(): ChatSendFlow {
    if (this.sendFlow !== null) {
      return this.sendFlow
    }
    const deps: ChatSendFlowDependencies = {
      chatViewModel: this.chatViewModel,
      messages: this.messages,
      chatTaskOrchestrator: this.chatTaskOrchestrator,
      toolRegistry: this.toolRegistry,
      webSearchService: this.webSearchService,
      getSessionId: (): string => this.sessionId,
      getSessionTitle: (): string => this.sessionTitle,
      getCurrentTaskId: (): string => this.currentTaskId,
      getCurrentModelId: (): string => this.currentModelId,
      getCurrentModelName: (): string => this.currentModel,
      getMessages: (): ChatMessage[] => this.messages,
      getReasoningLevel: (): ReasoningLevel => this.reasoningLevel,
      onClearComposer: (): void => {
        this.clearDraftAutosaveTimer()
        this.inputText = ''
        this.resetDocumentParseQueue()
        this.pendingAttachments = []
      },
      onBeforeSend: (): void => {
        this.safeStopInputSession()
        this.getScrollUiFlow().scrollToBottomWithAnimation()
      },
      onSetSending: (value: boolean): void => {
        this.isSending = value
        this.syncGeneratingScrollTipAfterSendingChange(value)
      },
      onSetCurrentTaskId: (taskId: string): void => {
        this.currentTaskId = taskId
      },
      onSyncMessages: (changedMessageId?: string): void => {
        this.markMessageListChanged(changedMessageId ?? '')
      },
      onScrollBottom: (): void => {
        this.getScrollUiFlow().alignToBottomIfPinned()
      },
      onSetNewEmptySession: (value: boolean): void => {
        this.isNewEmptySession = value
      },
      onDraftCommitted: (): void => {
        this.persistCurrentDraftState('', []).catch((error: Error): void => {
          console.error('ChatPage', `Failed to clear draft after send: ${JSON.stringify(error)}`)
        })
      },
      onMarkAutoTaskCompleted: (): void => {
        // no-op
      },
      onMarkAutoTaskFailed: (_message: string): void => {
        // no-op
      },
      onShowError: (message: string | Resource): void => {
        this.showError(message)
      },
      onShowToast: (message: string | Resource): void => {
        this.showChatSnack(message)
      },
      onConfirmModelSupportsTools: async (providerId: string, modelId: string): Promise<void> => {
        await this.confirmModelSupportsTools(providerId, modelId)
      }
    }
    this.sendFlow = new ChatSendFlow(deps)
    return this.sendFlow
  }

  private getStopFlow(): ChatStopFlow {
    if (this.stopFlow !== null) {
      return this.stopFlow
    }
    const deps: ChatStopFlowDependencies = {
      chatViewModel: this.chatViewModel,
      chatTaskOrchestrator: this.chatTaskOrchestrator,
      messages: this.messages,
      getCurrentTaskId: (): string => this.currentTaskId,
      onSetCurrentTaskId: (taskId: string): void => {
        this.currentTaskId = taskId
      },
      onCancelWebSearchRequests: (): void => {
        this.webSearchService.cancelAllRequests()
      },
      onSyncMessages: (changedMessageId?: string): void => {
        this.markMessageListChanged(changedMessageId ?? '')
      },
      onSetSending: (value: boolean): void => {
        this.isSending = value
        this.syncGeneratingScrollTipAfterSendingChange(value)
      },
      onSetLoading: (value: boolean): void => {
        this.isLoading = value
      },
      onClearForcedToolIds: (): void => {
        this.forcedToolIdsOnce = []
      },
      onMarkAutoTaskFailed: (_message: string): void => {
        // no-op
      }
    }
    this.stopFlow = new ChatStopFlow(deps)
    return this.stopFlow
  }

  private getInlineEditFlow(): ChatInlineEditFlow {
    if (this.inlineEditFlow !== null) {
      return this.inlineEditFlow
    }
    const deps: ChatInlineEditFlowDependencies = {
      chatViewModel: this.chatViewModel,
      getMessages: (): ChatMessage[] => this.messages,
      onValidateBeforeCommit: (
        content: string,
        attachments: MessageAttachment[],
        _webSearchEnabled: boolean,
        _selectedToolIds: string[],
        _reasoningLevel: ReasoningLevel
      ): boolean => {
        const prepareResult = this.getSendFlow().prepareSendRequest(
          content,
          attachments.length,
          this.isSending,
          this.currentProvider,
          this.currentModelId,
          this.chatTaskOrchestrator.canStartNewTask()
        )
        return prepareResult.shouldSend
      },
      onSyncMessages: (): void => {
        this.markMessageListChanged()
      },
      onResetEditState: (): void => {
        this.isEditingMessage = false
        this.editingMessageId = ''
        this.editingOriginalContent = ''
        this.editingOriginalAttachments = []
      },
      onApplySavedDraft: (
        content: string,
        attachments: MessageAttachment[],
        webSearchEnabled: boolean,
        selectedToolIds: string[],
        reasoningLevel: ReasoningLevel
      ): void => {
        this.inputText = content
        this.resetDocumentParseQueue()
        this.pendingAttachments = [...attachments]
        this.preparePendingDocumentAttachments()
        this.webSearchConversationEnabled = this.isWebSearchReady() && webSearchEnabled
        this.applySelectedToolIdsInMemory(selectedToolIds)
        this.reasoningLevel = this.normalizeReasoningLevelForCurrentModel(reasoningLevel)
      },
      onTriggerSend: async (
        content: string,
        attachments: MessageAttachment[],
        webSearchEnabled: boolean,
        selectedToolIds: string[],
        reasoningLevel: ReasoningLevel
      ): Promise<void> => {
        this.inputText = content
        this.resetDocumentParseQueue()
        this.pendingAttachments = [...attachments]
        this.preparePendingDocumentAttachments()
        this.webSearchConversationEnabled = this.isWebSearchReady() && webSearchEnabled
        this.applySelectedToolIdsInMemory(selectedToolIds)
        this.reasoningLevel = this.normalizeReasoningLevelForCurrentModel(reasoningLevel)
        await this.sendMessage()
      },
      onShowToast: (message: string | Resource): void => {
        this.showChatSnack(message)
      }
    }
    this.inlineEditFlow = new ChatInlineEditFlow(deps)
    return this.inlineEditFlow
  }

  private getSelectionFlow(): ChatSelectionFlow {
    if (this.selectionFlow !== null) {
      return this.selectionFlow
    }
    const deps: ChatSelectionFlowDependencies = {
      chatViewModel: this.chatViewModel,
      messages: this.messages,
      onSyncMessages: (): void => {
        this.markMessageListChanged()
      },
      onSetMultiSelectMode: (value: boolean): void => {
        this.isMultiSelectMode = value
      },
      onSetSelectedMessageIds: (ids: string[]): void => {
        this.selectedMessageIds = ids
      },
      onSetInputBarVisible: (value: boolean): void => {
        this.getScrollUiFlow().setInputBarVisible(value)
      },
      onSetShareMessages: (messages: ChatMessage[]): void => {
        this.shareMessages = messages
      },
      onSetShowSharePreview: (value: boolean): void => {
        this.showSharePreview = value
      },
      onShowToast: (message: string | Resource): void => {
        this.showChatSnack(message)
      }
    }
    this.selectionFlow = new ChatSelectionFlow(deps)
    return this.selectionFlow
  }

  private getLoadFlow(): ChatPageLoadFlow {
    if (this.loadFlow !== null) {
      return this.loadFlow
    }
    const deps: ChatPageLoadFlowDependencies = {
      appStateManager: this.appStateManager,
      preferencesService: this.preferencesService,
      assistantService: ServiceRegistry.assistant(),
      providerViewModel: this.providerViewModel,
      chatViewModel: this.chatViewModel,
      parseToolIdsFromRoute: (raw: string): string[] => {
        return this.parseToolIdsFromRoute(raw)
      }
    }
    this.loadFlow = new ChatPageLoadFlow(deps)
    return this.loadFlow
  }

  private getTaskAlertFlow(): ChatTaskAlertFlow {
    if (this.taskAlertFlow !== null) {
      return this.taskAlertFlow
    }
    const deps: ChatTaskAlertFlowDependencies = {
      getCurrentSessionId: (): string => this.sessionId,
      getLastHandledAlertTimestamp: (): number => this.lastHandledAlertTimestamp,
      onSetLastHandledAlertTimestamp: (value: number): void => {
        this.lastHandledAlertTimestamp = value
      },
      onNavigateToSession: (sessionId: string): void => {
        this.navPathStack.replacePath({ name: 'ChatPage', param: { sessionId: sessionId } as ChatPageRouteParams })
      },
      onClearOpenSessionPayloadStorage: (): void => {
        setAppUiStateValue(AppStorageKeys.OPEN_SESSION_PAYLOAD, '')
      },
      onClearInAppTaskAlertPayloadStorage: (): void => {
        setAppUiStateValue(AppStorageKeys.IN_APP_TASK_ALERT_PAYLOAD, '')
      },
      getUIContext: (): UIContext => {
        return this.getUIContext()
      }
    }
    this.taskAlertFlow = new ChatTaskAlertFlow(deps)
    return this.taskAlertFlow
  }

  private getScrollUiFlow(): ChatScrollUiFlow {
    if (this.scrollUiFlow !== null) {
      return this.scrollUiFlow
    }
    const deps: ChatScrollUiFlowDependencies = {
      scroller: this.scroller,
      messages: this.messages,
        getBottomAnchorIndex: (): number => this.getBottomAnchorListIndex(),
        getCurrentScrollOffset: (): number => this.currentScrollOffsetVp,
        syncCurrentScrollOffset: (): number => this.syncCurrentScrollOffsetFromScroller(),
        syncIsAtBottomBoundary: (): boolean => this.syncIsAtBottomBoundaryFromScroller(),
        getLastScrollOffset: (): number => this.lastScrollOffset,
        setLastScrollOffset: (value: number): void => {
          this.lastScrollOffset = value
        },
      getMaxScrollOffset: (): number => this.maxScrollOffset,
      setMaxScrollOffset: (value: number): void => {
        this.maxScrollOffset = value
      },
      getFirstVisibleIndex: (): number => this.firstVisibleListIndex,
      getLastVisibleIndex: (): number => this.lastVisibleListIndex,
      getTotalListItemCount: (): number => this.getTotalListItemCount(),
      getInputBarShowThreshold: (): number => this.inputBarShowThreshold,
      getInputBarHideThreshold: (): number => this.inputBarHideThreshold,
      getIsAtTop: (): boolean => this.isAtTop,
      getIsAtBottom: (): boolean => this.isAtBottom,
      getIsInputBarVisible: (): boolean => this.isInputBarVisible,
      getIsSending: (): boolean => this.isSending,
      getIsEditingMessage: (): boolean => this.isEditingMessage,
      getEditingMessageId: (): string => this.editingMessageId,
      hasDraftContent: (): boolean => this.inputText.trim() !== '' || this.pendingAttachments.length > 0,
      onSetIsAtTopState: (value: boolean): void => {
        this.isAtTop = value
      },
      onSetIsAtBottomState: (value: boolean): void => {
        this.isAtBottom = value
      },
      onSetInputBarVisibleState: (_value: boolean): void => {
        // 输入框始终显示，不再响应滚动隐藏/显示
      },
      onSetCurrentScrollOffsetState: (value: number): void => {
        if (this.shouldSyncScrollOffsetToUi(value)) {
          this.currentScrollOffsetVp = value
        }
      },
      onAnimate: (duration: number, curve: Curve, updater: () => void): void => {
        this.getUIContext().animateTo({
          duration: duration,
          curve: curve
        }, updater)
      }
    }
    this.scrollUiFlow = new ChatScrollUiFlow(deps)
    return this.scrollUiFlow
  }

  private async autoSendInitialPrompt(): Promise<void> {
    if (this.initialPromptAutoSent || this.pendingInitialPrompt === '') {
      return
    }
    if (this.isSending) {
      return
    }

    this.initialPromptAutoSent = true
    this.inputText = this.pendingInitialPrompt
    this.pendingInitialPrompt = ''
    this.forcedToolIdsOnce = [...this.pendingInitialToolIds]

    await this.sendMessage()
  }

  private findProviderModelSelection(
    providerId: string,
    modelId: string
  ): ProviderModelSelection | null {
    if (providerId === '' || modelId === '') {
      return null
    }
    for (let i = 0; i < this.providers.length; i++) {
      const provider = this.providers[i]
      if (provider.id !== providerId) {
        continue
      }
      for (let j = 0; j < provider.models.length; j++) {
        const model = provider.models[j]
        if (model.id === modelId) {
          return new ProviderModelSelection(provider, model)
        }
      }
      break
    }
    return null
  }

  private findEnabledProviderModelSelection(
    providerId: string,
    modelId: string
  ): ProviderModelSelection | null {
    const selection = this.findProviderModelSelection(providerId, modelId)
    if (selection === null || !selection.model.isEnabled) {
      return null
    }
    return selection
  }

  private async applyModelSelection(
    provider: ModelProvider,
    model: ModelInfo,
    preferredName: string = '',
    syncGlobalModel: boolean = true,
    resetReasoning: boolean = false
  ): Promise<void> {
    const modelName = model.name !== '' ? model.name : (preferredName !== '' ? preferredName : model.id)
    this.currentProvider = provider
    this.currentModelId = model.id
    this.currentModel = modelName
    if (resetReasoning) {
      this.resetReasoningForSelectedModel(provider, model)
    } else {
      this.syncReasoningAvailabilityWithCurrentModel()
    }
    if (syncGlobalModel) {
      await this.appStateManager.setCurrentModel(model.id, modelName, provider.id)
    }
    await this.chatViewModel.updateCurrentSessionModelSelection(model.id, provider.id)
    // 模型/服务商变更后, 联网菜单里的 "OpenAI 内置搜索" 项可能要出现或消失, 触发一次刷新。
    // 内部还会按 searchMode/storedEngine 决定 activeSearchEngineId 的最终值, 失效模式自动降级到 external_engine。
    await this.refreshAvailableSearchEngines()
    // 内置生图偏好不跟模型切换互相覆盖; 不支持时不展示,发送层仍会按能力过滤。
  }

  // 验证当前模型是否有效，如果无效则自动选择第一个可用模型
  private async validateAndSetCurrentModel(): Promise<void> {
    const currentSession = this.chatViewModel.getCurrentSession()
    if (currentSession !== null && currentSession.id === this.sessionId) {
      const sessionSelection = this.findEnabledProviderModelSelection(currentSession.providerId, currentSession.modelId)
      if (sessionSelection !== null) {
        await this.applyModelSelection(sessionSelection.provider, sessionSelection.model, '', !this.isNewEmptySession)
        return
      }
    }

    const savedSelection = this.findEnabledProviderModelSelection(
      this.appStateManager.getCurrentProviderId(),
      this.appStateManager.getCurrentModelId()
    )
    if (savedSelection !== null) {
      await this.applyModelSelection(savedSelection.provider, savedSelection.model)
      return
    }

    await this.selectFirstAvailableModel()
  }

  // 选择第一个可用的模型（优先使用默认聊天模型）
  private async selectFirstAvailableModel(): Promise<void> {
    // 先尝试使用默认聊天模型配置
    await this.defaultModelService.initialize()
    const defaultChatModel = this.defaultModelService.getModel(ModelRole.CHAT)

    if (defaultChatModel.isConfigured()) {
      // 检查默认模型是否仍然可用
      for (let i = 0; i < this.providers.length; i++) {
        const provider = this.providers[i]
        if (provider.id === defaultChatModel.providerId) {
          for (let j = 0; j < provider.models.length; j++) {
            const model = provider.models[j]
            if (model.id === defaultChatModel.modelId && model.isEnabled) {
              // 默认模型可用，使用它
              await this.applyModelSelection(provider, model)
              console.info('ChatPage', `Using default chat model: ${model.name} from ${provider.name}`)
              return
            }
          }
          break
        }
      }
      console.warn('ChatPage',
        `Default chat model configured but not available: ${defaultChatModel.modelName} from ${defaultChatModel.providerName}`)
    }

    // 默认模型未配置或不可用，回退到第一个可用模型
    for (let i = 0; i < this.providers.length; i++) {
      const provider = this.providers[i]
      for (let j = 0; j < provider.models.length; j++) {
        const model = provider.models[j]
        if (model.isEnabled) {
          await this.applyModelSelection(provider, model)
          console.info('ChatPage', `Auto-selected fallback model: ${model.name} from ${provider.name}`)
          return
        }
      }
    }

    // 没有可用模型
    this.currentProvider = null
    this.currentModelId = ''
    this.currentModel = ''
    this.syncReasoningAvailabilityWithCurrentModel()
  }

  private async refreshProviders(): Promise<void> {
    await this.appStateManager.loadState()

    const providers = await this.providerViewModel.loadProviders()
    console.info('ChatPage', `[refreshProviders] Loaded ${providers.length} providers`)

    if (providers.length > 0) {
      this.providers = providers
    }

    if (this.providers.length === 0) {
      this.currentModel = ''
      this.currentModelId = ''
      this.currentProvider = null
      this.syncReasoningAvailabilityWithCurrentModel()
    } else {
      // 验证并设置当前模型
      await this.validateAndSetCurrentModel()
    }
  }

  private getChatContentMaxWidth(): number {
    if (this.layoutSizeClass !== LayoutSizeClass.EXPANDED) {
      return 0
    }
    return getChatContentMaxWidth(this.windowWidthVp)
  }

  private getPageTopAvoidHeight(): number {
    if (this.layoutSizeClass === LayoutSizeClass.EXPANDED) {
      return 0
    }
    return this.px2vp(this.topAvoidHeight)
  }

  private getMessageListTopSpacerHeight(): number {
    // titleBar 下沿模糊蒙版会向下渐变 maskExtraHeight，列表第一条消息需让出这一段，
    // 否则会落在半透明渐变带上、视觉被压暗。算法与 Index.ets 左栏 getChatListTopSpacerHeight 对齐。
    // 额外加 TODAY_STAR_SUMMARY_CARD_HEIGHT 把今日小明星小卡 (position overlay) 的空间也保留出来。
    return HDS_NAV_DESTINATION_MINI_TITLE_BAR_HEIGHT + this.getPageTopAvoidHeight() +
      this.getChatTitleBarMaskExtraHeight() + TODAY_STAR_SUMMARY_CARD_HEIGHT
  }

  private getMessageMapJumpTopClearance(): number {
    // scrollToIndex extraOffset 使用 VP；在 HDS mini titleBar 下方再留出 20vp 视觉余量。
    return HDS_NAV_DESTINATION_MINI_TITLE_BAR_HEIGHT + MESSAGE_MAP_JUMP_EXTRA_TOP_CLEARANCE
  }

  private getStatusBarContentColor(): string {
    return this.isDarkMode ? '#F5F7FA' : '#1F2329'
  }

  private isExistingSessionSeeded(): boolean {
    const seededSessionId = this.routeParams?.sessionId ?? this.routeParamsSeed?.sessionId ?? ''
    return seededSessionId.trim() !== ''
  }

  private shouldShowTitleBarNewChatAction(): boolean {
    if (!this.hasInitializedRoute) {
      return this.isExistingSessionSeeded()
    }
    if (this.messages.length > 0) {
      return true
    }
    return !this.isNewChatTransition && this.sessionId.trim() !== ''
  }

  private getTitleBarOptions(): HdsNavigationTitleBarOptions {
    const options = new HdsTopNavigationBlurOptions()
    options.startPaddingVp = 16
    options.endPaddingVp = 16
    options.materialType = this.materialType
    options.materialLevel = this.materialLevel
    options.windowWidthVp = this.windowWidthVp
    options.windowHeightVp = this.windowHeightVp
    options.maskExtraHeightVp = this.getChatTitleBarMaskExtraHeight()
    options.blurEffectiveEndOffsetVp = this.windowWidthVp > this.windowHeightVp ? 20 : 28
    options.stackBuilder = (): void => this.ChatTitleStackBuilder()
    const titleBarOptions = buildHdsTopNavigationTitleBarOptions(options)
    titleBarOptions.content = {
      title: {
        mainTitle: ' '
      },
      backIcon: this.getTitleBarBackIcon(),
      menu: {
        maxCount: this.getTitleBarDirectMenuCount(),
        value: this.getTitleBarMenuItems()
      },
      stackBuilder: options.stackBuilder
    }
    return titleBarOptions
  }

  // 平板分栏复用 Index.ets 外层宽度判定，避免右栏按旧阈值保留分栏态。
  private isChatSplitLayout(): boolean {
    return shouldUseIndexChatSplitLayout(this.windowWidthVp, this.windowHeightVp, this.layoutSizeClass)
  }

  // 平板分栏下需要更长的下沿渐变模糊，避免滚动内容贴近 titleBar 时干扰标题可读性。
  // 手机/非分栏维持 HDS 推荐值（横屏 16 / 竖屏 20）。
  private getChatTitleBarMaskExtraHeight(): number {
    if (this.isChatSplitLayout()) {
      return HDS_NAV_SPLIT_TITLE_BAR_MASK_EXTRA_HEIGHT
    }
    return getHdsTopNavigationMaskExtraHeight(this.windowWidthVp, this.windowHeightVp)
  }

  private createTitleBarSymbolIcon(symbol: Resource, fontSize: number = 20): SymbolGlyphModifier {
    const icon = new SymbolGlyphModifier(symbol)
    icon.fontSize(fontSize)
    icon.fontColor([$r('app.color.text_primary')])
    return icon
  }

  private getTitleBarBackIcon(): HdsNavigationBackButtonItemOptions {
    return {
      icon: this.createTitleBarSymbolIcon($r('sys.symbol.chevron_left'), 20),
      action: () => {
        this.handleBack()
      }
    }
  }

  private getTitleStackContentStartInset(): number {
    return HDS_NAV_TITLE_NATIVE_START_INSET
  }

  private getTitleBarDirectMenuCount(): number {
    if (this.isChatSplitLayout()) {
      return 1
    }
    return this.shouldShowTitleBarNewChatAction() ? 2 : 1
  }

  private getTitleBarMenuItemCount(): number {
    return this.shouldShowTitleBarNewChatAction() ? 5 : 4
  }

  private getTitleBarVisibleActionSlotCount(): number {
    return Math.min(this.getTitleBarDirectMenuCount(), this.getTitleBarMenuItemCount())
  }

  private getTitleStackContentEndInset(): number {
    return HDS_NAV_TITLE_NATIVE_MENU_EDGE_INSET +
      HDS_NAV_TITLE_NATIVE_MENU_BUTTON_WIDTH * this.getTitleBarVisibleActionSlotCount()
  }

  private getTitleBarMenuItems(): Array<HdsNavigationMenuItemOptions> {
    const menus: Array<HdsNavigationMenuItemOptions> = []
    if (this.shouldShowTitleBarNewChatAction()) {
      menus.push({
        content: {
          label: $r('app.string.new_chat'),
          icon: this.createTitleBarSymbolIcon($r('sys.symbol.message_badge_plus'), 20),
          action: () => {
            void this.handleNewChat()
          }
        }
      })
    }

    menus.push({
      content: {
        label: $r('app.string.message_map_menu_entry'),
        icon: this.createTitleBarSymbolIcon($r('sys.symbol.map'), 20),
        action: () => {
          this.handleOpenMessageMap()
        }
      }
    })
    menus.push({
      content: {
        label: $r('app.string.edit_chat_title'),
        icon: this.createTitleBarSymbolIcon($r('sys.symbol.square_and_pencil'), 20),
        action: () => {
          this.requestTitleEditFromMenu()
        }
      }
    })
    menus.push({
      content: {
        label: $r('app.string.regenerate_title'),
        icon: this.createTitleBarSymbolIcon($r('sys.symbol.arrow_clockwise'), 20),
        isEnabled: !this.isTitleGenerating && !this.isSending,
        action: () => {
          void this.handleRegenerateTitle()
        }
      }
    })
    menus.push({
      content: {
        label: $r('app.string.delete_chat'),
        icon: this.createTitleBarSymbolIcon($r('sys.symbol.trash'), 20),
        action: () => {
          this.handleDeleteChat()
        }
      }
    })
    return menus
  }

  private requestTitleEditFromMenu(): void {
    this.safeStopInputSession()
    this.titleEditRequestTick += 1
  }

  @Builder
  private ChatTitleStackBuilder() {
    ChatNavigationTitleContent({
      sessionTitle: this.sessionTitle !== '' ? this.sessionTitle : this.getDefaultSessionTitle(),
      currentModelId: this.currentModelId,
      currentProviderId: this.currentProvider?.id ?? '',
      currentModelName: this.currentModel,
      currentProviderName: this.currentProvider?.name ?? '',
      currentProviderIconType: this.currentProvider?.iconType ?? 'svg',
      currentProviderIconPath: this.currentProvider?.iconPath ?? '',
      currentProviderTextIcon: this.currentProvider?.textIcon ?? '',
      currentProviderTextIconBgColor: this.currentProvider?.textIconBgColor ?? '',
      currentProviderCustomImagePath: this.currentProvider?.customImagePath ?? '',
      currentProviderBrandColor: this.currentProvider?.brandColor ?? '',
      isTitleGenerating: this.isTitleGenerating,
      titleGenerateFailed: this.titleGenerateFailed,
      editTitleRequestTick: this.titleEditRequestTick,
      contentStartInset: this.getTitleStackContentStartInset(),
      contentEndInset: this.getTitleStackContentEndInset(),
      onModelSelect: (): void => {
        this.safeStopInputSession()
        this.isModelSelectorVisible = true
        this.modelSheetActivePanel = 'selector'
      },
      onRegenerateTitle: (): void => {
        void this.handleRegenerateTitle()
      },
      onWillEditTitle: (): void => {
        this.safeStopInputSession()
      },
      onTitleChanged: (newTitle: string): void => {
        this.handleSaveTitle(newTitle).catch((error: Object) => {
          console.error('ChatPage', `Failed to save inline title: ${JSON.stringify(error)}`)
          this.showError($r('app.string.action_failed_retry'))
        })
      }
    })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 今日小明星小卡片 - 顶部悬浮, 不阻挡消息列表
        TodayStarSummaryCard({
          onOpenDetail: (): void => {
            this.showStarSheet = true
          }
        })
          .width('100%')
          .padding({ left: 12, right: 12, top: 0, bottom: 0 })
          .position({
            x: 0,
            y: HDS_NAV_DESTINATION_MINI_TITLE_BAR_HEIGHT + this.getPageTopAvoidHeight() + 8
          })
          .zIndex(1)
          .hitTestBehavior(HitTestMode.Default)

        // 消息列表 - 占满全屏
        ChatMessageListSection({
          isLoading: this.isLoading,
          loadingColor: this.themePrimary,
          scroller: this.scroller,
          messages: this.messages,
          syncVersion: this.messageListSyncVersion,
          isEditingMessage: this.isEditingMessage,
          editingMessageId: this.editingMessageId,
          selectedMessageIds: this.selectedMessageIds,
          isMultiSelectMode: this.isMultiSelectMode,
          inputText: this.inputText,
          pendingAttachments: this.pendingAttachments,
          showDraftPreview: this.hasDraftContent(),
          draftPreviewTimeText: this.getPreviewTimeText(),
          bottomPadding: this.getListBottomPadding(),
          topInsetHeight: this.getMessageListTopSpacerHeight(),
          currentModelId: this.currentModelId,
          assistantAvatarSymbol: this.currentAssistantAvatarSymbol,
          assistantAvatarColor: this.currentAssistantColor,
          assistantAvatarCacheKey: this.assistantAvatarRenderTick,
          chatFontSize: this.chatFontSize,
          themeRenderKey: this.messageThemeRenderKey,
          contentMaxWidth: this.getChatContentMaxWidth(),
          syncMessageId: this.messageListSyncMessageId,
          onRegenerate: (message: ChatMessage): void => {
            this.handleRegenerate(message)
          },
          onDelete: (message: ChatMessage): void => {
            this.handleDeleteMessage(message)
          },
          onEdit: (message: ChatMessage): void => {
            this.handleEditMessage(message)
          },
          onCancelEdit: (): void => {
            this.handleCancelEdit()
          },
          onShareMessage: (message: ChatMessage): void => {
            this.handleShareSingleMessage(message)
          },
          onTranslate: (content: string, targetLang: string,
            callback: (result: string, errorMessage: string) => void): void => {
            this.handleTranslate(content, targetLang, callback)
          },
          onImageClick: (images: Array<string>, imageIndex: number, sourceIds: Array<string>): void => {
            this.handleImagePreview(images, imageIndex, sourceIds)
          },
          onOpenLink: (title: string, url: string): void => {
            this.handleMessageLinkOpen(title, url)
          },
          onTTS: (messageId: string, content: string): void => {
            this.handleTTS(messageId, content)
          },
          onTTSStop: (): void => {
            this.handleTTSStop()
          },
          onSelect: (messageId: string): void => {
            this.handleToggleMessageSelection(messageId)
          },
          onEnterMultiSelect: (messageId: string): void => {
            this.handleEnterMultiSelectMode(messageId)
          },
          onAskUserAnswer: (toolCallId: string, answerJson: string): void => {
            this.handleAskUserAnswer(toolCallId, answerJson)
          },
          onOpenNumberPuzzleSheet: (toolCall: ToolCall): void => {
            this.numberPuzzleSheetToolCall = toolCall
            this.numberPuzzleAnswered = false
            this.showNumberPuzzleSheet = true
          },
          onReachStart: (): void => {
            this.handleMessageListReachStart()
          },
          onReachEnd: (): void => {
            this.handleMessageListReachEnd()
          },
          onScrollStart: (): void => {
            this.handleMessageListScrollStart()
          },
          onScrollStop: (): void => {
            this.handleMessageListScrollStop()
          },
          onContentLayoutChange: (): void => {
            this.handleMessageListContentLayoutChanged()
          },
          onInteractiveContentResize: (): void => {
            this.handleMessageListInteractiveContentResize()
          },
          onMessageItemAppear: (listIndex: number): void => {
            this.getScrollUiFlow().handleIndexedTargetItemReady(listIndex)
          },
          onMessageItemLayoutChange: (listIndex: number, measuredHeight: number): void => {
            this.getScrollUiFlow().handleIndexedTargetItemMeasured(listIndex, measuredHeight)
          },
          onDidScroll: (scrollOffset: number, scrollState: ScrollState): void => {
            this.handleMessageListDidScroll(scrollOffset, scrollState)
          },
          onScrollIndex: (firstIndex: number, lastIndex: number): void => {
            this.firstVisibleListIndex = firstIndex
            this.lastVisibleListIndex = lastIndex
            this.getScrollUiFlow().handleScrollIndexChanged()
          }
        })
          .width('100%')
          .height('100%')
          .backgroundColor(this.themeBackground)

        if (this.shouldMountDocumentParserWeb) {
          Web({ src: DocumentParsePolicy.WEB_PARSER_URL, controller: this.documentParserWebController })
            .width(1)
            .height(1)
            .opacity(0)
            .position({ x: -2, y: -2 })
            .hitTestBehavior(HitTestMode.None)
            .onControllerAttached(() => {
              this.documentParserService.attachController(this.documentParserWebController)
            })
            .onPageEnd(() => {
              this.documentParserService.markReady()
              if (this.isPageVisible) {
                this.preparePendingDocumentAttachments()
              }
            })
            .javaScriptAccess(true)
            .fileAccess(false)
            .backgroundColor(Color.Transparent)
        }

        // 编辑模式覆盖层 - 点击/滑动空白处都取消编辑
        // 滑动不再传透给 List,List 不会跟随滚动(已与产品确认)
        if (this.isEditingMessage) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Transparent)
            .gesture(
              GestureGroup(GestureMode.Exclusive,
                // PanGesture 在前: 手指移动超过阈值时胜出, TapGesture 被取消
                PanGesture({ fingers: 1, distance: 8 })
                  .onActionStart(() => {
                    this.handleCancelEdit()
                  }),
                TapGesture({ count: 1 })
                  .onAction(() => {
                    this.handleCancelEdit()
                  })
              )
            )
        }

        // AI 生成中的底部中间 loading 回到底部按钮
        ScrollToBottomLoadingButton({
          isVisible: this.shouldShowScrollToBottomLoadingButton(),
          fixedBottomOffset: this.getScrollButtonBaselineVp(),
          bottomAvoidHeight: this.getFloatingOverlayBottomAvoidHeightVp(),
          onScrollToBottom: () => {
            this.scrollToBottomWithAnimation()
          }
        })

        if (!this.shouldShowScrollToBottomLoadingButton()) {
          this.ScrollQuickJumpButtons()
        }

        // 底部输入栏容器（非多选模式时显示）
        if (!this.isMultiSelectMode) {
          Column() {
            ChatInputAreaSection({
              inputText: this.inputText,
              onInputTextChange: (value: string): void => {
                this.inputText = value
              },
              attachments: this.pendingAttachments,
              onAttachmentsChange: (value: MessageAttachment[]): void => {
                this.handleComposerAttachmentsChange(value)
              },
              isSending: this.isSending,
              isAwaitingResponse: this.calcIsAwaitingAiOutput(),
              isVoiceMode: this.isVoiceMode,
              isVoiceSpeaking: this.isVoiceMode && this.speakingMessageId !== '',
              onVoiceModeToggle: (): void => {
                this.handleVoiceModeToggle()
              },
              onVoiceSpeakingStop: (): void => {
                this.handleTTSStop()
              },
              onVoiceRecordStart: (): void => {
                this.handleVoiceRecordStart()
              },
              onVoiceRecordCancel: (): void => {
                this.handleVoiceRecordCancel()
              },
              onVoiceRecordFinish: (): void => {
                this.handleVoiceRecordFinish()
              },
              onVoiceCancelZoneChange: (isCancel: boolean): void => {
                this.isRecordingCancelZone = isCancel
              },
              autoFocus: this.autoFocusInput,
              isEditing: this.isEditingMessage,
              isAttachmentPanelOpen: this.showAttachmentPicker,
              webSearchAvailable: this.webSearchAvailable,
              webSearchEnabled: this.getActiveComposerWebSearchEnabled(),
              availableSearchEngines: this.availableSearchEngines,
              activeSearchEngineId: this.activeSearchEngineId,
              onSearchEngineSelect: (engineId: string): void => {
                this.handleComposerWebSearchSelect(engineId)
              },
              toolSelectionAvailable: shouldShowToolSelectionChipForChat(
                this.availableChatTools.length,
                this.getActiveComposerSelectedToolIds().length
              ),
              hasSelectedTools: this.hasSelectedTools(),
              imageGenAvailable: this.isOpenAIBuiltinImageGenAvailableForCurrentProvider(),
              imageGenEnabled: this.getActiveComposerBuiltinImageGenEnabled(),
              onImageGenToggle: (): void => {
                this.handleComposerImageGenToggle()
              },
              reasoningAvailable: this.supportsReasoningForCurrentModel(),
              reasoningControlMode: this.getReasoningControlModeForCurrentModel(),
              reasoningXhighAvailable: this.supportsReasoningXhighForCurrentModel(),
              onOpenTools: (): void => {
                this.showToolPickerSheet = true
              },
              reasoningLevel: this.getActiveComposerReasoningLevel(),
              onReasoningLevelChange: (value: ReasoningLevel): void => {
                this.updateActiveComposerReasoningLevel(value)
              },
              hasRecentScreenshot: this.hasRecentScreenshot,
              bottomAvoidHeight: this.getComposerBottomAvoidHeightVp(),
              contentMaxWidth: this.getChatContentMaxWidth(),
              sendButtonOnLeft: this.shouldUseLeftHandLayout(),
              onCancelEdit: (): void => {
                this.handleCancelEdit()
              },
              onSend: (): void => {
                if (this.isEditingMessage) {
                  this.handleSaveAndSendInline()
                } else {
                  this.handleSend()
                }
              },
              onStop: (): void => {
                this.handleStop()
              },
              onAttachmentClick: (): void => {
                this.toggleAttachmentPanel()
              },
              onInputFocus: (): void => {
                if (!this.isEditingMessage) {
                  if (this.showAttachmentPicker) {
                    this.closeAttachmentPanel()
                  }
                  this.isInputFocused = true
                  setTimeout(() => {
                    this.getScrollUiFlow().alignToBottomAfterLayout()
                  }, 200)
                }
              },
              onInputBlur: (): void => {
                this.isInputFocused = false
              },
              onComposerContentChanged: (): void => {
                this.handleComposerContentChanged()
              },
              onRecentPhotoDetected: (detected: boolean): void => {
                this.hasRecentScreenshot = detected
              },
              onImageClick: (images: Array<string>, imageIndex: number, sourceIds: Array<string>): void => {
                this.handleImagePreview(images, imageIndex, sourceIds)
              }
            })
              .onAreaChange((_oldArea: Area, newArea: Area) => {
                this.handleInputAreaHeightChange(newArea)
              })
              .animation({
                duration: 220,
                curve: Curve.EaseOut
              })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ bottom: this.attachmentPanelHeightVp })
          .animation({
            duration: 260,
            curve: Curve.FastOutSlowIn
          })
          .position({ x: 0, y: '100%' })
          .translate({ y: '-100%', x: 0 })

          // 附件面板（与输入区分离定位，避免动态子布局只抬高输入区却不绘制面板内容）
          Column() {
            this.AttachmentPanelContentBuilder()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .height(this.attachmentPanelHeightVp)
          .opacity(this.showAttachmentPicker ? 1 : 0)
          .backgroundColor(this.themeSurface)
          .clip(true)
          .enabled(this.showAttachmentPicker)
          .animation({
            duration: 260,
            curve: Curve.FastOutSlowIn
          })
          .position({ x: 0, y: '100%' })
          .translate({ y: '-100%', x: 0 })
        }

        // 分享预览 Sheet 宿主（bindContentCover 和 bindSheet 不能在同一组件上，否则会冲突）
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showStarSheet, this.StarDetailSheetBuilder(), {
          height: SheetSize.LARGE,
          detents: [SheetSize.LARGE],
          dragBar: true,
          showClose: true,
          backgroundColor: this.themeBackground,
          blurStyle: BlurStyle.Thick,
          preferType: SheetType.BOTTOM,
          maskColor: '#66000000',
          onDisappear: (): void => {
            this.showStarSheet = false
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.isModelSelectorVisible, this.ModelSelectorSheetBuilder(), {
          height: SheetSize.LARGE,
          dragBar: true,
          showClose: false,
          blurStyle: BlurStyle.Thick,
          backgroundColor: this.themeBackground,
          preferType: SheetType.BOTTOM,
          onDisappear: () => {
            this.isModelSelectorVisible = false
            this.modelSheetActivePanel = 'selector'
            this.editingModel = null
            this.editingModelProvider = null
          }
        })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showMessageWebSheet, this.MessageWebSheetBuilder(), {
          height: SheetSize.LARGE,
          detents: [SheetSize.LARGE],
          dragBar: true,
          showClose: true,
          title: { title: this.messageWebSheetTitle !== '' ? this.messageWebSheetTitle : $r('app.string.common_web_page') },
          onDisappear: () => {
            this.messageWebSheetUrl = ''
            this.messageWebSheetTitle = ''
            this.showMessageWebSheet = false
          }
        })
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showSharePreview, this.SharePreviewBuilder(), {
          height: SheetSize.LARGE,
          dragBar: true,
            showClose: false,
            backgroundColor: this.themeBackground,
            blurStyle: BlurStyle.Thick,
            preferType: SheetType.BOTTOM,
            onDisappear: () => {
              this.showSharePreview = false
            }
          })

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showMessageMapSheet, this.MessageMapBuilder(), {
          height: SheetSize.LARGE,
          detents: [SheetSize.LARGE],
          dragBar: true,
          showClose: false,
          backgroundColor: this.themeBackground,
          blurStyle: BlurStyle.Thick,
          preferType: SheetType.BOTTOM,
          onDisappear: () => {
            this.showMessageMapSheet = false
            this.performPendingMessageMapJump()
          }
        })

        Column()
          .width(0)
          .height(0)
          .bindSheet($$this.showToolPickerSheet, this.ToolPickerBuilder(), {
            height: SheetSize.FIT_CONTENT,
            dragBar: true,
            showClose: false,
            backgroundColor: this.themeBackground,
            blurStyle: BlurStyle.Thick,
            preferType: SheetType.BOTTOM,
            onDisappear: () => {
              this.showToolPickerSheet = false
            }
          })

        Column()
          .width(0)
          .height(0)
          .bindSheet($$this.showToolExecutionApprovalSheet, this.ToolExecutionApprovalSheetBuilder(), {
            height: SheetSize.FIT_CONTENT,
            dragBar: true,
            showClose: false,
            backgroundColor: this.themeBackground,
            blurStyle: BlurStyle.Thick,
            preferType: SheetType.BOTTOM,
            maskColor: '#66000000',
            onDisappear: () => {
              this.handleToolExecutionApprovalSheetDisappear()
            }
          })

        Column()
          .width(0)
          .height(0)
          .bindSheet($$this.showNumberPuzzleSheet, this.NumberPuzzleSheetBuilder(), {
            height: SheetSize.LARGE,
            dragBar: true,
            showClose: true,
            blurStyle: BlurStyle.Thick,
            backgroundColor: this.themeBackground,
            preferType: SheetType.BOTTOM,
            onDisappear: () => {
              if (this.showNumberPuzzleSheet && !this.numberPuzzleAnswered) {
                // Sheet dismissed without completing — send cancel result
                const cancelResult: NumberPuzzleResult = {
                  difficulty: 0,
                  grid_size: '',
                  time_seconds: 0,
                  move_count: 0,
                  completed: false
                }
                try {
                  const parsed = JSON.parse(this.numberPuzzleSheetToolCall.arguments) as Record<string, Object>
                  cancelResult.difficulty = (parsed['difficulty'] as number) ?? 0
                } catch (_e) {
                  // ignore
                }
                this.handleAskUserAnswer(this.numberPuzzleSheetToolCall.id, JSON.stringify(cancelResult))
              }
              this.showNumberPuzzleSheet = false
            }
          })

        // 多选工具栏（多选模式时显示）
        if (this.isMultiSelectMode) {
          Column() {
            ChatMultiSelectToolbar({
              selectedCount: this.selectedMessageIds.length,
              totalCount: this.messages.length,
              onSelectAll: () => {
                this.handleSelectAllMessages()
              },
              onDelete: () => {
                this.handleDeleteSelectedMessages()
              },
              onShare: () => {
                this.handleShareSelectedMessages()
              },
              onCancel: () => {
                this.handleExitMultiSelectMode()
              }
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 12, right: 12, bottom: this.getMultiSelectToolbarBottomInsetVp() })
          .position({ x: 0, y: '100%' })
          .translate({ y: '-100%', x: 0 })
          .hitTestBehavior(HitTestMode.Default)
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.handleMultiSelectToolbarHeightChange(newArea)
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
        }

        // 录音全屏遮罩
        if (this.isRecording) {
          this.RecordingOverlay()
        }
      }
      .width('100%')
      .height('100%')
      .clip(true)
      .backgroundColor(this.themeBackground)
    }
    .titleBar(this.getTitleBarOptions())
    .bindToScrollable([this.scroller])
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .hideTitleBar(false, true)
    .systemBarStyle(
      { statusBarContentColor: this.getStatusBarContentColor() },
      { statusBarContentColor: this.getStatusBarContentColor() }
    )
    .hideBackButton(false)
    // 注意：不要在 NavDestination 上设置 ignoreLayoutSafeArea([SYSTEM], [TOP])。
    // HdsNavigation 容器（Index.ets）已经处理了顶部 SafeArea，这里再设一次会被叠加，
    // 导致分栏右栏 titleBar 顶部出现额外留白。SafeArea 由 Navigation 容器统一管。
    .backgroundColor(this.themeBackground)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack
      const param = context.pathInfo.param as ChatPageRouteParams
      if (param !== null && param !== undefined) {
        this.routeParams = param
      }
      // 如果 aboutToAppear 时 routeParams 还没设置，这里触发初始化
      if (!this.hasInitializedRoute) {
        this.tryInitWithParams(this.routeParams)
      }
    })
    .onShown(() => {
      this.handlePageShown()
    })
    .onHidden(() => {
      this.isPageVisible = false
      this.resetDocumentParseQueue()
      if (!this.isImagePreviewSharing) {
        this.closeActiveChatImagePreview(false)
      }
      if (this.isMultiSelectMode) {
        this.handleExitMultiSelectMode()
      }
      this.syncActiveSessionBinding()
    })
    .onBackPressed((): boolean => {
      if (this.showImagePreview) {
        this.closeActiveChatImagePreview(true)
        return true
      }
      if (this.showAttachmentPicker) {
        this.closeAttachmentPanel()
        return true
      }
      if (dismissActiveSnackBarOnBack()) {
        return true
      }
      this.handleBack()
      return true
    })
  }

  pageTransition() {
    PageTransitionEnter({
      type: RouteType.Push,
      duration: 350,
      curve: Curve.EaseOut
    })
      .slide(SlideEffect.Right)

    PageTransitionExit({
      type: RouteType.Pop,
      duration: 300,
      curve: Curve.EaseIn
    })
      .slide(SlideEffect.Right)

    // 被新页面覆盖时的退出动画
    PageTransitionExit({
      type: RouteType.Push,
      duration: 350,
      curve: Curve.EaseOut
    })
      .opacity(0.8)
      .translate({ x: '-20%' })

    // 返回时的进入动画
    PageTransitionEnter({
      type: RouteType.Pop,
      duration: 300,
      curve: Curve.EaseOut
    })
      .opacity(1)
      .translate({ x: 0 })
  }

  private normalizePreviewIndex(index: number, imageCount: number): number {
    if (imageCount <= 0 || index < 0) {
      return 0
    }
    if (index >= imageCount) {
      return imageCount - 1
    }
    return index
  }

  private getChatImagePreviewSourceId(sourceIds: Array<string>, index: number): string {
    if (index >= 0 && index < sourceIds.length && sourceIds[index] !== '') {
      return sourceIds[index]
    }
    return `chat_image_preview_${index}`
  }

  private buildChatImagePreviewModels(images: Array<string>): DefaultMediaModel[] {
    const mediaModels: DefaultMediaModel[] = []
    for (let i = 0; i < images.length; i++) {
      mediaModels.push(new DefaultMediaModel(images[i], images[i], DefaultMediaType.IMAGE))
    }
    return mediaModels
  }

  private handleImagePreview(images: Array<string>, index: number, sourceIds: Array<string>): void {
    hilog.info(DOMAIN, TAG, '🖼️ ChatPage.handleImagePreview (images: %{public}d, index: %{public}d)', images.length,
      index)
    const previewImages: Array<string> = []
    const previewSourceIds: Array<string> = []
    let initialIndex = 0
    for (let i = 0; i < images.length; i++) {
      if (images[i] !== '') {
        if (i === index) {
          initialIndex = previewImages.length
        }
        previewImages.push(images[i])
        previewSourceIds.push(i < sourceIds.length ? sourceIds[i] : '')
      }
    }

    const mediaModels = this.buildChatImagePreviewModels(previewImages)
    if (mediaModels.length === 0) {
      return
    }

    initialIndex = this.normalizePreviewIndex(initialIndex, mediaModels.length)
    this.previewImages = previewImages
    this.previewImageIndex = initialIndex
    this.previewImageSourceIds = previewSourceIds
    this.showImagePreview = true
    const options = new MediaPreviewOptions<DefaultMediaModel>()
      .setMedias(mediaModels)
      .setInitIndex(initialIndex)
      .setIdBuilder((_item: DefaultMediaModel, mediaIndex: number): string => {
        return this.getChatImagePreviewSourceId(this.previewImageSourceIds, mediaIndex)
      })
      .setPageChangedListener((_item: DefaultMediaModel, mediaIndex: number): void => {
        this.previewImageIndex = mediaIndex
      })
      .setBackListener((): void => {
        this.handleChatImagePreviewClosed()
      })
      .setToolBuilder((): void => {
        this.ChatImagePreviewToolBuilder()
      })
      .setShowPageText(mediaModels.length > 1)
      .setIndicator(false)
      .setBackgroundColor(Color.Black)
      .setDismissOnTap(true)
      .setDismissOnDrag(true)
      .setMaxScale(4)
      .setDuration(260)
    this.imagePreviewDialogId = MediaPreview.open(this.getUIContext(), options)
    options.dialogId = this.imagePreviewDialogId
    this.imagePreviewOptions = options
  }

  private closeActiveChatImagePreview(animated: boolean): void {
    if (this.imagePreviewDialogId !== '') {
      MediaPreview.close({ dialogId: this.imagePreviewDialogId, animated: animated })
    } else {
      this.handleChatImagePreviewClosed()
      return
    }
    if (!animated) {
      this.handleChatImagePreviewClosed()
    }
  }

  private handleChatImagePreviewClosed(): void {
    this.showImagePreview = false
    this.previewImages = []
    this.previewImageIndex = 0
    this.previewImageSourceIds = []
    this.imagePreviewDialogId = ''
    this.imagePreviewOptions = null
    this.isImagePreviewSaving = false
    this.isImagePreviewSharing = false
    this.updateStatusBar()
  }

  private hasCurrentChatPreviewImage(): boolean {
    return this.previewImageIndex >= 0 && this.previewImageIndex < this.previewImages.length &&
      this.previewImages[this.previewImageIndex] !== ''
  }

  private async saveCurrentChatPreviewImage(authorized: boolean): Promise<void> {
    if (this.isImagePreviewSaving || !this.hasCurrentChatPreviewImage()) {
      return
    }
    const hostContext = this.getUIContext().getHostContext()
    if (hostContext === undefined || hostContext === null) {
      this.showChatSnack($r('app.string.image_save_failed'), 2000, SnackBarTone.ERROR)
      return
    }

    this.isImagePreviewSaving = true
    try {
      const imageUri = this.previewImages[this.previewImageIndex]
      if (authorized) {
        await savePreviewImageToAlbumAuthorized(hostContext as common.UIAbilityContext, imageUri)
      } else {
        await savePreviewImageToAlbum(hostContext as common.UIAbilityContext, imageUri)
      }
      this.showChatSnack($r('app.string.image_saved_to_album'), 2000, SnackBarTone.SUCCESS)
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Save preview image failed: %{public}s', JSON.stringify(error))
      this.showChatSnack($r('app.string.image_save_failed'), 2000, SnackBarTone.ERROR)
    } finally {
      this.isImagePreviewSaving = false
    }
  }

  private async shareCurrentChatPreviewImage(): Promise<void> {
    if (this.isImagePreviewSharing || !this.hasCurrentChatPreviewImage()) {
      return
    }
    const hostContext = this.getUIContext().getHostContext()
    if (hostContext === undefined || hostContext === null) {
      this.showChatSnack($r('app.string.share_failed'), 2000, SnackBarTone.ERROR)
      return
    }

    this.isImagePreviewSharing = true
    this.setChatImagePreviewSystemBackEnabled(false)
    try {
      const imagePath = await preparePreviewImageForShare(
        hostContext as common.UIAbilityContext,
        this.previewImages[this.previewImageIndex]
      )
      const shareService = ServiceRegistry.share()
      shareService.init(hostContext as common.UIAbilityContext)
      const result = await shareService.shareImage(imagePath, 'image')
      if (!result.success) {
        this.showChatSnack($r('app.string.share_failed'), 2000, SnackBarTone.ERROR)
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Share preview image failed: %{public}s', JSON.stringify(error))
      this.showChatSnack($r('app.string.share_failed'), 2000, SnackBarTone.ERROR)
    } finally {
      this.setChatImagePreviewSystemBackEnabled(true)
      this.isImagePreviewSharing = false
    }
  }

  private setChatImagePreviewSystemBackEnabled(enabled: boolean): void {
    if (this.imagePreviewOptions === null || this.imagePreviewDialogId === '') {
      return
    }
    try {
      this.imagePreviewOptions.dialogId = this.imagePreviewDialogId
      this.imagePreviewOptions.setDismissOnSystemBack(enabled)
      PromptActionTool.updateCustomDialog(this.imagePreviewOptions)
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Update preview system back failed: %{public}s', JSON.stringify(error))
    }
  }

  @Builder
  private ChatImagePreviewToolBuilder() {
    Stack({ alignContent: Alignment.Bottom }) {
      Row({ space: 12 }) {
        Button({ type: ButtonType.Circle, stateEffect: false }) {
          if (this.isImagePreviewSharing) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color('rgba(255, 255, 255, 0.86)')
          } else {
            SymbolGlyph($r('sys.symbol.share'))
              .fontSize(20)
              .fontColor(['rgba(255, 255, 255, 0.9)'])
          }
        }
        .width(48)
        .height(48)
        .backgroundColor('rgba(8, 12, 18, 0.62)')
        .accessibilityText($r('app.string.menu_share'))
        .enabled(!this.isImagePreviewSharing && this.hasCurrentChatPreviewImage())
        .onClick(() => {
          this.shareCurrentChatPreviewImage()
        })

        if (this.isImagePreviewSaving) {
          Button({ type: ButtonType.Circle, stateEffect: false }) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color('rgba(255, 255, 255, 0.86)')
          }
          .width(48)
          .height(48)
          .backgroundColor('rgba(8, 12, 18, 0.62)')
        } else {
          SaveButton({ icon: SaveIconStyle.FULL_FILLED, buttonType: ButtonType.Circle })
            .width(48)
            .height(48)
            .backgroundColor('rgba(8, 12, 18, 0.62)')
            .onClick((_event: ClickEvent, result: SaveButtonOnClickResult): void => {
              if (result !== SaveButtonOnClickResult.SUCCESS) {
                this.showChatSnack($r('app.string.image_save_failed'), 2000, SnackBarTone.ERROR)
                return
              }
              this.saveCurrentChatPreviewImage(true)
            })
        }
      }
      .margin({ bottom: 24 + this.px2vp(this.bottomAvoidHeight) })
      .hitTestBehavior(HitTestMode.Default)
      .onTouch((event: TouchEvent): void => {
        event.stopPropagation()
      })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  StarDetailSheetBuilder() {
    TodayStarDetailSheet()
  }

  @Builder
  ModelSelectorSheetBuilder() {
    ChatModelSelectorSheetContent({
      providers: this.providers,
      currentModelId: this.currentModelId,
      currentProviderId: this.currentProvider?.id ?? '',
      activePanel: this.modelSheetActivePanel,
      editingModel: this.editingModel!!,
      onSelectModel: (providerId: string, modelId: string, modelName: string): void => {
        this.handleModelSelect(providerId, modelId, modelName)
        this.isModelSelectorVisible = false
      },
      onStartEdit: (model: ModelInfo, provider: ModelProvider): void => {
        this.editingModel = model
        this.editingModelProvider = provider
        this.modelSheetActivePanel = 'edit'
      },
      onSaveEdit: async (draft: ModelInfoExtendedJson): Promise<void> => {
        await this.saveModelEdit(draft)
      },
      onCancelEdit: (): void => {
        this.modelSheetActivePanel = 'selector'
        this.editingModel = null
        this.editingModelProvider = null
      }
    })
  }

  private async saveModelEdit(draft: ModelInfoExtendedJson): Promise<void> {
    const modelToSave = this.editingModel
    const providerToSave = this.editingModelProvider
    if (modelToSave === null || providerToSave === null) {
      return
    }

    applyModelDraft(modelToSave, draft)
    await this.providerViewModel.saveProvider(providerToSave)
    const refreshedProviders = await this.providerViewModel.loadProviders()
    this.providers = refreshedProviders

    for (let i = 0; i < refreshedProviders.length; i++) {
      const provider = refreshedProviders[i]
      if (this.currentProvider !== null && provider.id === this.currentProvider.id) {
        for (let j = 0; j < provider.models.length; j++) {
          const model = provider.models[j]
          if (model.id === this.currentModelId) {
            await this.applyModelSelection(provider, model)
            break
          }
        }
        break
      }
    }

    this.modelSheetActivePanel = 'selector'
    this.editingModel = null
    this.editingModelProvider = null
  }

  private async confirmModelSupportsTools(providerId: string, modelId: string): Promise<void> {
    const selection = this.findProviderModelSelection(providerId, modelId)
    if (selection === null) {
      return
    }
    const effective = getEffectiveCapabilities(selection.model)
    if (effective.supportsTools && selection.model.capabilitiesUserModified) {
      return
    }

    selection.model.capabilities.supportsTools = true
    selection.model.capabilities.supportsReasoning = effective.supportsReasoning
    selection.model.capabilities.supportsWebSearch = effective.supportsWebSearch
    selection.model.capabilities.supportsVision = effective.supportsVision
    selection.model.capabilities.supportsStreaming = effective.supportsStreaming
    selection.model.capabilitiesUserModified = true

    try {
      await this.providerViewModel.saveProvider(selection.provider)
      const refreshedProviders = await this.providerViewModel.loadProviders()
      this.providers = refreshedProviders
      const refreshedSelection = this.findProviderModelSelection(providerId, modelId)
      if (refreshedSelection !== null && this.currentProvider !== null &&
        this.currentProvider.id === providerId && this.currentModelId === modelId) {
        await this.applyModelSelection(refreshedSelection.provider, refreshedSelection.model, '', false)
      }
      this.showChatSnack(pickLocalizedText(
        '已识别当前模型支持工具调用',
        'Detected tool calling support for this model'
      ), 2200, SnackBarTone.SUCCESS)
    } catch (error) {
      console.error('ChatPage', `[confirmModelSupportsTools] Failed: ${JSON.stringify(error)}`)
    }
  }

  @Builder
  SharePreviewBuilder() {
    SharePreviewSheet({
      messages: this.shareMessages,
      currentModelId: this.currentModelId,
      assistantAvatarValue: this.currentAssistantAvatarSymbol,
      assistantAvatarColor: this.currentAssistantColor,
      assistantAvatarCacheKey: this.assistantAvatarRenderTick,
      onClose: () => {
        this.showSharePreview = false
      }
    })
  }

  @Builder
  NumberPuzzleSheetBuilder() {
    NumberPuzzleCard({
      toolCall: this.numberPuzzleSheetToolCall,
      isAnswered: false,
      answeredPayload: '',
      largeSize: true,
      onAnswer: (toolCallId: string, answerJson: string): void => {
        this.numberPuzzleAnswered = true
        this.handleAskUserAnswer(toolCallId, answerJson)
        this.showNumberPuzzleSheet = false
      }
    })
  }

  @Builder
  MessageMapBuilder() {
    MessageMapSheet({
      messages: this.messages,
      currentMessageIndex: this.computeCurrentVisibleMessageIndex(),
      onClose: () => {
        this.showMessageMapSheet = false
      },
      onJumpToMessage: (messageIndex: number) => {
        this.handleJumpToMessageFromMap(messageIndex)
      }
    })
  }

  // 估算用户当前正在阅读的 message index: 取顶部可见消息,与消息地图"跳到消息开头"语义一致。
  // 用于消息地图 Sheet 打开时定位"我在哪"。messages 为空或 list index 异常返回 -1。
  private computeCurrentVisibleMessageIndex(): number {
    if (this.messages.length === 0) {
      return -1
    }
    const first = this.firstVisibleListIndex
    const last = this.lastVisibleListIndex
    const hasVisibleRange = first >= 0 && last > 0 && last >= first
    if (!hasVisibleRange) {
      if (this.isAtBottom || this.syncIsAtBottomBoundaryFromScroller()) {
        return this.messages.length - 1
      }
      if (this.isAtTop || this.readCurrentScrollOffset() <= 0) {
        return 0
      }
      return -1
    }
    const msgIdx = first - 1 // toListScrollIndexForMessage = idx + 1 的反函数
    if (msgIdx < 0) {
      return 0
    }
    if (msgIdx >= this.messages.length) {
      return this.messages.length - 1
    }
    return msgIdx
  }

  private handleOpenMessageMap(): void {
    this.safeStopInputSession()
    this.showMessageMapSheet = true
  }

  private handleJumpToMessageFromMap(messageIndex: number): void {
    if (messageIndex < 0 || messageIndex >= this.messages.length) {
      this.pendingMessageMapJumpMessageId = ''
      this.showMessageMapSheet = false
      return
    }
    this.pendingMessageMapJumpMessageId = this.messages[messageIndex].id
    this.showMessageMapSheet = false
  }

  private performPendingMessageMapJump(): void {
    if (this.pendingMessageMapJumpMessageId === '') {
      return
    }
    const targetMessageId = this.pendingMessageMapJumpMessageId
    this.pendingMessageMapJumpMessageId = ''
    const currentIndex = findMessageIndexById(this.messages, targetMessageId)
    if (currentIndex < 0) {
      return
    }
    this.getScrollUiFlow().scrollToIndexWithStabilization(
      toListScrollIndexForMessage(currentIndex),
      ScrollAlign.START,
      this.getMessageMapJumpTopClearance()
    )
  }

  private handleToolSelectionToggle(toolId: string, enabled: boolean): void {
    const nextToolIds = [...this.getActiveComposerSelectedToolIds()]
    const index = nextToolIds.indexOf(toolId)
    if (enabled && index < 0) {
      nextToolIds.push(toolId)
    }
    if (!enabled && index >= 0) {
      nextToolIds.splice(index, 1)
    }
    this.updateActiveComposerSelectedToolIds(nextToolIds).catch((error: Object) => {
      console.error('ChatPage', `Failed to update selected tools: ${JSON.stringify(error)}`)
      this.showError(pickLocalizedText('工具选择保存失败', 'Failed to save tool selection'))
    })
  }

  @Builder
  ToolPickerBuilder() {
    ChatToolPickerSheetContent({
      availableChatTools: this.availableChatTools,
      selectedToolIds: this.getActiveComposerSelectedToolIds(),
      isRefreshingMcpToolAvailability: this.isRefreshingMcpToolAvailability,
      themePrimary: this.themePrimary,
      isDarkMode: this.isDarkMode,
      onClose: (): void => {
        this.showToolPickerSheet = false
      },
      onRefresh: (): void => {
        this.refreshMcpToolAvailabilityInBackground(true)
      },
      onToggleTool: (toolId: string, enabled: boolean): void => {
        this.handleToolSelectionToggle(toolId, enabled)
      },
      onToggleMcpGroup: (toolIds: string[], enabled: boolean): void => {
        this.handleMcpToolGroupSelectionToggle(toolIds, enabled)
      }
    })
  }

  @Builder
  ToolExecutionApprovalSheetBuilder() {
    ChatToolExecutionApprovalSheetContent({
      sourceLabel: this.toolExecutionApprovalSourceLabel,
      toolName: this.toolExecutionApprovalName,
      argumentSummary: this.toolExecutionApprovalArgumentSummary,
      argumentEntries: this.toolExecutionApprovalArgumentEntries,
      argumentsPreview: this.toolExecutionApprovalArgumentsPreview,
      argumentsTruncated: this.toolExecutionApprovalArgumentsTruncated,
      showRawArguments: this.showRawToolExecutionApprovalArguments,
      alwaysAllowAvailable: this.toolExecutionApprovalSourceId.trim() !== '',
      isWriteTool: this.toolExecutionApprovalIsWriteTool,
      themePrimary: this.themePrimary,
      isDarkMode: this.isDarkMode,
      onToggleShowRaw: (): void => {
        this.showRawToolExecutionApprovalArguments = !this.showRawToolExecutionApprovalArguments
      },
      onCancel: (): void => {
        this.resolveToolExecutionApproval(false)
      },
      onAlwaysAllow: (): void => {
        this.approveCurrentMcpServerAlways()
      },
      onApprove: (): void => {
        this.resolveToolExecutionApproval(true)
      }
    })
  }

  // 处理附件选择
  private handleAttachmentsSelected(attachments: MessageAttachment[]): void {
    // 普通输入模式：添加到输入框的附件列表
    for (let i = 0; i < attachments.length; i++) {
      this.pendingAttachments.push(attachments[i])
    }
    // 触发数组更新，便于子组件监听并驱动发送按钮动效
    this.pendingAttachments = [...this.pendingAttachments]
    this.preparePendingDocumentAttachments()
    this.closeAttachmentPanel()
  }

  private handleComposerAttachmentsChange(attachments: MessageAttachment[]): void {
    this.resetDocumentParseQueue()
    this.pendingAttachments = [...attachments]
    this.preparePendingDocumentAttachments()
  }

  private resetDocumentParseQueue(): void {
    this.documentParseEpoch = this.documentParseEpoch + 1
    this.documentParseQueue.splice(0, this.documentParseQueue.length)
    this.documentParserService.cancelCurrentParse().catch((error: Error): void => {
      console.warn('ChatPage', `Cancel document parse failed: ${JSON.stringify(error)}`)
    })
    let changed = false
    for (let i = 0; i < this.pendingAttachments.length; i++) {
      const attachment = this.pendingAttachments[i]
      if (attachment.parsedText !== '') {
        continue
      }
      if (attachment.processState === AttachmentProcessState.QUEUED ||
        attachment.processState === AttachmentProcessState.PARSING ||
        attachment.processState === AttachmentProcessState.COPYING) {
        attachment.processState = AttachmentProcessState.IDLE
        attachment.parseError = ''
        changed = true
      }
    }
    if (changed) {
      this.refreshPendingAttachments()
    }
    this.teardownDocumentParserWebIfIdle()
  }

  private preparePendingDocumentAttachments(): void {
    if (!this.isPageVisible) {
      return
    }
    for (let i = 0; i < this.pendingAttachments.length; i++) {
      this.prepareAttachmentForParsing(this.pendingAttachments[i])
    }
  }

  private prepareAttachmentForParsing(attachment: MessageAttachment): void {
    if (!DocumentParsePolicy.isWebParseCandidate(attachment)) {
      return
    }
    if (attachment.parsedText !== '') {
      if (attachment.processState !== AttachmentProcessState.PARSED) {
        attachment.processState = AttachmentProcessState.PARSED
        this.refreshPendingAttachments()
      }
      return
    }
    const hardLimit = DocumentParsePolicy.getHardLimitBytes(attachment)
    if (hardLimit > 0 && attachment.size > hardLimit) {
      attachment.processState = AttachmentProcessState.TOO_LARGE
      attachment.parseError = `文件大小超过 ${Math.floor(hardLimit / 1024 / 1024)}MB`
      this.refreshPendingAttachments()
      return
    }
    if (attachment.processState === AttachmentProcessState.QUEUED ||
      attachment.processState === AttachmentProcessState.PARSING ||
      attachment.processState === AttachmentProcessState.PARSED ||
      attachment.processState === AttachmentProcessState.PARSE_FAILED ||
      attachment.processState === AttachmentProcessState.PASSWORD_REQUIRED ||
      attachment.processState === AttachmentProcessState.TOO_LARGE) {
      return
    }
    attachment.processState = AttachmentProcessState.QUEUED
    attachment.parseEngine = ''
    attachment.parseError = ''
    this.refreshPendingAttachments()
    this.enqueueDocumentParse(attachment)
  }

  private enqueueDocumentParse(attachment: MessageAttachment): void {
    for (let i = 0; i < this.documentParseQueue.length; i++) {
      if (this.isSamePendingAttachment(this.documentParseQueue[i], attachment)) {
        return
      }
    }
    this.documentParseQueue.push(attachment)
    this.ensureDocumentParserWebMounted()
    this.runDocumentParseQueue()
  }

  private async runDocumentParseQueue(): Promise<void> {
    if (this.isDocumentParseQueueRunning) {
      return
    }
    this.isDocumentParseQueueRunning = true
    this.documentParseRunnerId = this.documentParseRunnerId + 1
    const runnerId = this.documentParseRunnerId
    const epoch = this.documentParseEpoch
    this.ensureDocumentParserWebMounted()
    try {
      while (this.documentParseQueue.length > 0) {
        if (runnerId !== this.documentParseRunnerId || epoch !== this.documentParseEpoch) {
          break
        }
        const attachment = this.documentParseQueue.shift()
        if (attachment === undefined || !this.isPendingAttachmentActive(attachment)) {
          continue
        }
        await this.parsePendingAttachment(attachment, epoch)
      }
    } finally {
      if (runnerId === this.documentParseRunnerId) {
        this.isDocumentParseQueueRunning = false
        if (this.documentParseQueue.length > 0) {
          this.runDocumentParseQueue()
        } else {
          this.teardownDocumentParserWebIfIdle()
        }
      }
    }
  }

  private ensureDocumentParserWebMounted(): void {
    if (!this.shouldMountDocumentParserWeb) {
      this.documentParserService.markNotReady()
      this.shouldMountDocumentParserWeb = true
    }
  }

  private teardownDocumentParserWebIfIdle(): void {
    if (this.isDocumentParseQueueRunning || this.hasActiveDocumentParseWork()) {
      return
    }
    if (!this.shouldMountDocumentParserWeb) {
      this.documentParserService.markNotReady()
      return
    }
    this.documentParserService.markNotReady()
    this.shouldMountDocumentParserWeb = false
  }

  private async parsePendingAttachment(attachment: MessageAttachment, epoch: number): Promise<void> {
    if (epoch !== this.documentParseEpoch || !this.isPendingAttachmentActive(attachment)) {
      return
    }
    attachment.processState = AttachmentProcessState.PARSING
    attachment.parseError = ''
    this.refreshPendingAttachments()

    const cancelChecker = (): boolean => {
      return epoch !== this.documentParseEpoch || !this.isPendingAttachmentActive(attachment)
    }
    try {
      this.documentParserService.cancelChecker = cancelChecker
      const result = await this.documentParserService.parseAttachment(attachment)
      if (epoch !== this.documentParseEpoch || !this.isPendingAttachmentActive(attachment)) {
        return
      }
      this.applyDocumentParseResult(attachment, result)
    } catch (error) {
      if (epoch !== this.documentParseEpoch || !this.isPendingAttachmentActive(attachment)) {
        return
      }
      attachment.processState = AttachmentProcessState.PARSE_FAILED
      attachment.parseError = this.normalizeDocumentParseError(this.stringifyDocumentParseError(error))
      this.refreshPendingAttachments()
    } finally {
      if (this.documentParserService.cancelChecker === cancelChecker) {
        this.documentParserService.cancelChecker = null
      }
    }
  }

  private applyDocumentParseResult(attachment: MessageAttachment, result: DocumentParseResult): void {
    if (result.success && result.text.trim() !== '') {
      attachment.processState = AttachmentProcessState.PARSED
      attachment.parsedText = result.text
      attachment.parseEngine = result.engine
      attachment.parseError = result.warning
      this.refreshPendingAttachments()
      return
    }
    const error = result.success ? '未提取到可用文本' : result.error
    if (this.isPasswordProtectedParseError(error)) {
      attachment.processState = AttachmentProcessState.PASSWORD_REQUIRED
      attachment.parseError = '文件可能已加密'
    } else {
      attachment.processState = AttachmentProcessState.PARSE_FAILED
      attachment.parseError = this.normalizeDocumentParseError(error)
    }
    this.refreshPendingAttachments()
  }

  private isPendingAttachmentActive(attachment: MessageAttachment): boolean {
    for (let i = 0; i < this.pendingAttachments.length; i++) {
      if (this.isSamePendingAttachment(this.pendingAttachments[i], attachment)) {
        return true
      }
    }
    return false
  }

  private isSamePendingAttachment(left: MessageAttachment, right: MessageAttachment): boolean {
    if (left === right) {
      return true
    }
    return left.id === right.id &&
      left.filePath === right.filePath &&
      left.name === right.name
  }

  private hasActiveDocumentParseWork(): boolean {
    if (this.documentParseQueue.length > 0) {
      return true
    }
    for (let i = 0; i < this.pendingAttachments.length; i++) {
      const attachment = this.pendingAttachments[i]
      if (!DocumentParsePolicy.isWebParseCandidate(attachment) || attachment.parsedText !== '') {
        continue
      }
      if (attachment.processState === AttachmentProcessState.QUEUED ||
        attachment.processState === AttachmentProcessState.PARSING ||
        attachment.processState === AttachmentProcessState.COPYING) {
        return true
      }
    }
    return false
  }

  private refreshPendingAttachments(): void {
    this.pendingAttachments = [...this.pendingAttachments]
  }

  private isPasswordProtectedParseError(error: string): boolean {
    const normalized = error.toLowerCase()
    return normalized.includes('password') ||
      normalized.includes('encrypted') ||
      normalized.includes('加密')
  }

  private normalizeDocumentParseError(error: string): string {
    const normalized = error.trim()
    if (normalized === '' || normalized === 'undefined' || normalized === 'null') {
      return '未知错误'
    }
    if (normalized.includes('document_parser_not_ready')) {
      return '解析沙箱未就绪'
    }
    if (normalized.includes('empty_file_data')) {
      return '文件内容为空'
    }
    if (normalized.includes('unsupported_file_type')) {
      return '暂不支持该文件类型'
    }
    if (normalized.length > 80) {
      return normalized.substring(0, 80)
    }
    return normalized
  }

  private stringifyDocumentParseError(error: Object): string {
    const text = `${error}`.trim()
    if (text !== '' && text !== '[object Object]') {
      return text
    }
    try {
      return JSON.stringify(error)
    } catch (_error) {
      return ''
    }
  }

  private getAttachmentBlockingReason(): string {
    this.preparePendingDocumentAttachments()
    return DocumentParsePolicy.getBlockingReason(this.pendingAttachments)
  }

  private guardAttachmentReadyForSend(): boolean {
    const blockingReason = this.getAttachmentBlockingReason()
    if (blockingReason === '') {
      return true
    }
    this.showChatSnack(blockingReason, 2500, SnackBarTone.DEFAULT)
    return false
  }

  // 切换附件面板
  private toggleAttachmentPanel(): void {
    if (this.showAttachmentPicker) {
      this.closeAttachmentPanel()
    } else {
      this.openAttachmentPanel()
    }
  }

  private openAttachmentPanel(): void {
    this.safeStopInputSession()
    this.getUIContext().animateTo({
      duration: 260,
      curve: Curve.FastOutSlowIn
    }, () => {
      this.showAttachmentPicker = true
      this.attachmentPanelHeightVp = this.ATTACHMENT_PANEL_EXPANDED_HEIGHT
    })
  }

  private closeAttachmentPanel(): void {
    this.getUIContext().animateTo({
      duration: 220,
      curve: Curve.FastOutSlowIn
    }, () => {
      this.attachmentPanelHeightVp = 0
      this.showAttachmentPicker = false
    })
  }

  onAppInBackgroundChanged(): void {
    // 后台切换由任务调度器与后台守护服务处理，这里只保留日志
    console.info('ChatPage', `[onAppInBackgroundChanged] appInBackground=${this.appInBackground}`)
  }

  private calcIsAwaitingAiOutput(): boolean {
    if (!this.isSending) {
      return false
    }

    const total = this.messages.length
    if (total <= 0) {
      return true
    }

    // 从尾部向前找最近一条 AI 消息；若 AI 还没开始输出（内容为空），则认为处于等待态
    for (let i = total - 1; i >= 0; i--) {
      const msg = this.messages[i]
      if (msg.role === MessageRole.ASSISTANT) {
        return msg.isGenerating && msg.content.length === 0 && msg.reasoningContent.length === 0
      }
      if (msg.role === MessageRole.USER) {
        break
      }
    }

    return true
  }

  // 处理返回按钮点击
  private handleBack(): void {
    if (this.isMultiSelectMode) {
      this.handleExitMultiSelectMode()
      return
    }
    this.handleBackAsync().catch((error: Error): void => {
      console.error('ChatPage', `Failed to prepare chat before back: ${JSON.stringify(error)}`)
      this.navPathStack.pop()
    })
  }

  private async handleBackAsync(): Promise<void> {
    this.isPageVisible = false
    this.syncActiveSessionBinding()
    await this.prepareCurrentSessionForTransition()
    this.navPathStack.pop()
  }

  private safeStopInputSession(): void {
    this.isInputFocused = false
    try {
      this.getUIContext().getFocusController().clearFocus()
    } catch (error) {
      console.error('ChatPage', `Clear focus failed: ${JSON.stringify(error)}`)
    }
    try {
      const inputMethodController = inputMethod.getController()
      inputMethodController.stopInputSession().catch((error: Error): void => {
        console.error('ChatPage', `Stop input session failed: ${JSON.stringify(error)}`)
      })
    } catch (error) {
      console.error('ChatPage', `Stop input session failed: ${JSON.stringify(error)}`)
    }
  }

  // px 转 vp
  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) *
      160
  }

  private getComposerBottomAvoidHeightVp(): number {
    if (this.showAttachmentPicker) {
      return 0
    }
    const systemBottomInset = this.px2vp(this.bottomAvoidHeight)
    if (this.isChatSplitLayout()) {
      return Math.min(Math.max(systemBottomInset, 0), 8)
    }
    return Math.max(systemBottomInset, 8)
  }

  private getFloatingOverlayBottomAvoidHeightVp(): number {
    // 按钮"距屏幕底"语义已下沉到 getScrollButtonBaselineVp 兜底里,
    // 这里只剩附件面板高度(系统安全区已包含在 baseline fallback / inputAreaHeightVp 内)
    return this.attachmentPanelHeightVp
  }

  // 浮动按钮的"左上角距屏幕底"基线
  // baseline = inputAreaHeightVp + 56(按钮自身 48 + 视觉间隙 8): 按钮 left-top 锚点距屏幕底
  //   = 输入区高度 + 56, 等价于按钮底部刚好高出输入区顶 8vp, 不再与工具栏 chip 重叠
  // 首屏 inputAreaHeightVp=0 时用 fallback 兜底,
  // 极端场景(banner + 编辑提示 + 多行 + 附件叠加)封顶到 maxBaseline 避免按钮上漂过头
  private getScrollButtonBaselineVp(): number {
    const measured = this.inputAreaHeightVp + 56
    const fallback = this.floatingScrollButtonFallbackVp + this.px2vp(this.bottomAvoidHeight)
    return Math.min(Math.max(measured, fallback), this.floatingScrollButtonMaxBaselineVp)
  }

  private getMultiSelectToolbarBottomInsetVp(): number {
    return Math.max(this.px2vp(this.bottomAvoidHeight) + 10, 20)
  }

  @Builder
  private AttachmentPanelContentBuilder() {
    if (this.layoutSizeClass === LayoutSizeClass.EXPANDED) {
      Column() {
        AttachmentPicker({
          showDragBar: false,
          onSelectAttachments: (attachments: MessageAttachment[]): void => {
            this.handleAttachmentsSelected(attachments)
          },
          onClose: (): void => {
            this.closeAttachmentPanel()
          }
        })
      }
      .width('100%')
      .constraintSize({ maxWidth: this.getChatContentMaxWidth() })
    } else {
      AttachmentPicker({
        showDragBar: false,
        onSelectAttachments: (attachments: MessageAttachment[]): void => {
          this.handleAttachmentsSelected(attachments)
        },
        onClose: (): void => {
          this.closeAttachmentPanel()
        }
      })
    }
  }

  private shouldShowScrollToBottomLoadingButton(): boolean {
    return !this.isEditingMessage && !this.hasDraftContent() && !this.showImagePreview &&
      !this.isMultiSelectMode && this.isSending && this.isGeneratingScrollTipVisible
  }

  private setGeneratingScrollTipVisible(value: boolean): void {
    if (this.isGeneratingScrollTipVisible === value) {
      return
    }
    this.isGeneratingScrollTipVisible = value
  }

  private shouldRevealGeneratingScrollTipFromCurrentPosition(): boolean {
    return this.isSending && !this.isAtBottom && !this.syncIsAtBottomBoundaryFromScroller()
  }

  private syncGeneratingScrollTipAfterSendingChange(value: boolean): void {
    if (!value) {
      this.setGeneratingScrollTipVisible(false)
      return
    }
    if (this.shouldRevealGeneratingScrollTipFromCurrentPosition()) {
      this.setGeneratingScrollTipVisible(true)
    }
  }

  @Builder
  private ScrollQuickJumpButtons() {
    ScrollToBottomButton({
      isVisible: this.shouldShowStandardScrollToBottomButton(),
      fixedBottomOffset: this.getScrollButtonBaselineVp(),
      bottomAvoidHeight: this.getFloatingOverlayBottomAvoidHeightVp(),
      placeOnLeft: this.shouldUseLeftHandLayout(),
      icon: $r('sys.symbol.arrow_down_to_line'),
      onClickAction: (): void => {
        this.scrollToBottomWithAnimation()
      }
    })
  }

  @Builder
  private RecordingOverlay() {
    Column() {
      // 顶部取消按钮（安全出口：当语音识别异常时可手动取消）
      Row() {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([Color.White])
        }
        .width(40)
        .height(40)
        .backgroundColor('rgba(255,255,255,0.2)')
        .onClick(() => {
          ServiceRegistry.speechRecognition().cancelListening()
          this.stopWaveformAnimation()
          this.isRecording = false
          this.isRecordingCancelZone = false
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 60 })

      Row() {
        Text(this.isRecordingCancelZone ? $r('app.string.voice_release_cancel') : $r('app.string.voice_release_to_send'))
          .fontSize(18)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 20 })

      Blank()

      // 声波动画指示器
      Row() {
        ForEach(Array.from({ length: 5 }, (_: undefined, i: number) => i), (index: number) => {
          Column()
            .width(4)
            .height(16 + (index % 2 === 0 ? 12 : -4))
            .borderRadius(2)
            .backgroundColor(this.isRecordingCancelZone ? '#FF4444' : Color.White)
            .margin({ left: 3, right: 3 })
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ bottom: 12 })

      Row() {
        Text($r('app.string.voice_slide_up_cancel'))
          .fontSize(14)
          .fontColor(this.isRecordingCancelZone ? '#FF4444' : '#CCCCCC')
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ bottom: 60 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isRecordingCancelZone ? 'rgba(0,0,0,0.85)' : 'rgba(0,0,0,0.7)')
    .onClick(() => {
      // 点击遮罩不做任何事，录音由 VoiceRecordButton 的 touch 事件控制
    })
  }

  private canShowStandardScrollButton(): boolean {
    return !this.isEditingMessage && !this.hasDraftContent() && !this.showImagePreview &&
      !this.isMultiSelectMode && !this.isLoading && this.getTotalListItemCount() > 2
  }

  private shouldShowStandardScrollToBottomButton(): boolean {
    return this.canShowStandardScrollButton() && !this.isAtBottom &&
      !this.shouldShowScrollToBottomLoadingButton()
  }

  private handleMessageListScrollStart(): void {
    this.getScrollUiFlow().handleScrollStart()
  }

  private handleMessageListScrollStop(): void {
    if (this.getScrollUiFlow().handleScrollStop()) {
      if (this.isSending && (this.isAtBottom || this.syncIsAtBottomBoundaryFromScroller())) {
        this.setGeneratingScrollTipVisible(false)
      }
      return
    }
    if (this.isSending && (this.isAtBottom || this.syncIsAtBottomBoundaryFromScroller())) {
      this.setGeneratingScrollTipVisible(false)
    }
  }

  private handleMessageListDidScroll(scrollOffset: number, scrollState: ScrollState): void {
    const isActiveScroll = scrollState === ScrollState.Scroll || scrollState === ScrollState.Fling
    if (this.showAttachmentPicker && isActiveScroll) {
      this.closeAttachmentPanel()
    }
    const userScrolledAwayFromBottom = this.getScrollUiFlow().handleMessageListDidScroll(scrollOffset, scrollState)
    if (this.isSending && userScrolledAwayFromBottom) {
      this.setGeneratingScrollTipVisible(true)
    } else if (this.isSending && isActiveScroll && this.syncIsAtBottomBoundaryFromScroller()) {
      this.setGeneratingScrollTipVisible(false)
    }
  }

  private handleMessageListContentLayoutChanged(): void {
    this.getScrollUiFlow().handleContentLayoutChanged()
  }

  private handleMessageListInteractiveContentResize(): void {
    this.getScrollUiFlow().prepareForInteractiveContentResize()
  }

  private handleMessageListReachStart(): void {
    this.getScrollUiFlow().handleReachStart()
  }

  private handleMessageListReachEnd(): void {
    this.getScrollUiFlow().handleReachEnd()
    this.setGeneratingScrollTipVisible(false)
  }

  private hasDraftContent(): boolean {
    return this.inputText.trim() !== '' || this.pendingAttachments.length > 0
  }

  private readMeasuredAreaHeight(area: Area): number {
    const height = area.height
    if (typeof height !== 'number' || Number.isNaN(height)) {
      return 0
    }
    return height
  }

  private readCurrentScrollOffset(): number {
    try {
      const offset = this.scroller.currentOffset()
      if (typeof offset.yOffset !== 'number' || Number.isNaN(offset.yOffset) || offset.yOffset <= 0) {
        return 0
      }
      return offset.yOffset
    } catch (_error) {
      return 0
    }
  }

  private syncCurrentScrollOffsetFromScroller(): number {
    const offset = this.readCurrentScrollOffset()
    this.currentScrollOffsetVp = offset
    return offset
  }

  private syncIsAtBottomBoundaryFromScroller(): boolean {
    try {
      return this.scroller.isAtEnd()
    } catch (_error) {
      return false
    }
  }

  private alignListToBottomAfterLayout(): void {
    this.getScrollUiFlow().alignToBottomAfterLayout()
  }

  private syncBottomAlignmentAfterOverlayHeightChange(previousHeight: number, nextHeight: number, isActive: boolean): void {
    if (!isActive || !this.isAtBottom || Math.abs(previousHeight - nextHeight) < 0.5) {
      return
    }
    this.alignListToBottomAfterLayout()
  }

  private handleInputAreaHeightChange(area: Area): void {
    const nextHeight = this.readMeasuredAreaHeight(area)
    const previousHeight = this.inputAreaHeightVp
    this.inputAreaHeightVp = nextHeight
    this.syncBottomAlignmentAfterOverlayHeightChange(previousHeight, nextHeight,
      !this.isMultiSelectMode)
  }

  private handleMultiSelectToolbarHeightChange(area: Area): void {
    const nextHeight = this.readMeasuredAreaHeight(area)
    const previousHeight = this.multiSelectToolbarHeightVp
    this.multiSelectToolbarHeightVp = nextHeight
    this.syncBottomAlignmentAfterOverlayHeightChange(previousHeight, nextHeight, this.isMultiSelectMode)
  }

  private getActiveBottomOverlayHeight(): number {
    if (this.isMultiSelectMode) {
      return this.multiSelectToolbarHeightVp
    }
    return this.inputAreaHeightVp + this.attachmentPanelHeightVp
  }

  // 计算列表底部留白高度：优先跟随底部遮挡层的实测高度，避免和输入区布局漂移
  private getListBottomPadding(): number {
    const measuredHeight = this.getActiveBottomOverlayHeight()
    if (measuredHeight > 0) {
      return measuredHeight
    }
    return getListBottomPaddingForChat(this.pendingAttachments.length, this.isEditingMessage,
      this.getComposerBottomAvoidHeightVp())
  }

  // 获取预览气泡的时间文本
  private getPreviewTimeText(): string {
    return getPreviewTimeTextForChat(new Date())
  }

  // 输入内容变化时，自动滚动到底部显示预览气泡
  @Monitor('inputText')
  onDraftContentChanged(): void {
    this.getScrollUiFlow().onDraftContentChanged()
  }

  private handleComposerContentChanged(): void {
    this.scheduleDraftAutosave()
  }

  private clearDraftAutosaveTimer(): void {
    if (this.draftAutosaveTimerId < 0) {
      return
    }
    clearTimeout(this.draftAutosaveTimerId)
    this.draftAutosaveTimerId = -1
  }

  private scheduleDraftAutosave(): void {
    if (this.isLoading || this.isEditingMessage) {
      return
    }
    this.clearDraftAutosaveTimer()
    this.draftAutosaveTimerId = setTimeout(() => {
      this.draftAutosaveTimerId = -1
      this.persistCurrentDraftState(this.inputText, this.pendingAttachments).catch((error: Error): void => {
        console.error('ChatPage', `Failed to autosave draft: ${JSON.stringify(error)}`)
      })
    }, this.draftAutosaveDelayMs)
  }

  private async flushDraftAutosave(immediate: boolean): Promise<void> {
    this.clearDraftAutosaveTimer()
    if (!immediate || this.isLoading || this.isEditingMessage) {
      return
    }
    await this.persistCurrentDraftState(this.inputText, this.pendingAttachments)
  }

  private async persistCurrentDraftState(content: string, attachments: MessageAttachment[]): Promise<void> {
    if (this.isLoading || this.isEditingMessage) {
      return
    }
    const session = await this.chatViewModel.saveSessionDraft(content, attachments)
    if (session === null) {
      return
    }
    this.sessionId = session.id
    this.sessionTitle = session.title
    this.syncActiveSessionBinding()
  }

  private async prepareCurrentSessionForTransition(): Promise<void> {
    try {
      await this.flushDraftAutosave(true)
    } catch (error) {
      console.error('ChatPage', `Failed to flush draft before session transition: ${JSON.stringify(error)}`)
    }
    if (!this.shouldDeleteEmptySessionOnDisappear()) {
      return
    }
    const deletingSessionId = this.sessionId
    await this.chatViewModel.deleteSession(deletingSessionId)
    console.info('ChatPage', '删除空会话: ' + deletingSessionId)
    if (this.sessionId === deletingSessionId) {
      this.sessionId = ''
      this.sessionTitle = ''
      this.isNewEmptySession = false
      this.syncActiveSessionBinding()
    }
  }

  private shouldDeleteEmptySessionOnDisappear(): boolean {
    return this.isNewEmptySession &&
      !this.isSending &&
      this.currentTaskId === '' &&
      this.messages.length === 0 &&
      !this.hasDraftContent() &&
      this.sessionId !== ''
  }

  // 滚动到底部（带动画过渡）
  private scrollToBottomWithAnimation(): void {
    this.setGeneratingScrollTipVisible(false)
    this.getScrollUiFlow().scrollToBottomWithAnimation()
  }

  // 同步包装方法，用于 onSend 回调
  handleSend(): void {
    if (this.showAttachmentPicker) {
      this.closeAttachmentPanel()
    }
    this.sendMessage()
  }

  // 处理停止生成
  handleStop(): void {
    this.getStopFlow().stopCurrentTask()
  }

  // 语音模式切换
  handleVoiceModeToggle(): void {
    if (this.isSending || this.isRecording || this.isEditingMessage) {
      return
    }
    if (!this.isVoiceMode) {
      // 切换到语音模式前检查麦克风权限
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      ServiceRegistry.speechRecognition().checkPermission(context).then((granted: boolean) => {
        if (granted) {
          this.isVoiceMode = !this.isVoiceMode
        } else {
          this.showChatSnack($r('app.string.voice_permission_denied'), 2000, SnackBarTone.WARNING)
        }
      })
    } else {
      // 退出语音模式时停止朗读
      if (this.speakingMessageId !== '') {
        this.handleTTSStop()
      }
      this.isVoiceMode = false
    }
  }

  // 开始录音
  handleVoiceRecordStart(): void {
    if (this.isRecording) {
      return
    }
    // 停止正在进行的自动朗读
    if (this.speakingMessageId !== '') {
      this.handleTTSStop()
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    ServiceRegistry.speechRecognition().checkPermission(context).then((granted: boolean) => {
      if (!granted) {
        this.showChatSnack($r('app.string.voice_permission_denied'), 2000, SnackBarTone.WARNING)
        return
      }
      ServiceRegistry.speechRecognition().init().then(() => {
        this.isRecording = true
        this.isRecordingCancelZone = false
        this.startWaveformAnimation()
        ServiceRegistry.speechRecognition().startListening({
          onStart: () => {
            console.info('ChatPage', 'Voice recording started')
          },
          onResult: (_text: string, _isFinal: boolean) => {
            // 中间结果不处理，等待 onComplete
          },
          onComplete: (finalText: string) => {
            this.stopWaveformAnimation()
            this.isRecording = false
            this.isRecordingCancelZone = false
            this.handleRecordingComplete(finalText)
          },
          onCancel: () => {
            this.stopWaveformAnimation()
            this.isRecording = false
            this.isRecordingCancelZone = false
          },
          onError: (code: number, message: string) => {
            this.stopWaveformAnimation()
            this.isRecording = false
            this.isRecordingCancelZone = false
            console.error('ChatPage', `Voice recognition error: ${code} ${message}`)
            this.showChatSnack($r('app.string.voice_network_error'), 2000, SnackBarTone.ERROR)
          }
        })
      }).catch((err: Error) => {
        console.error('ChatPage', `Failed to init speech recognition: ${err.message}`)
        this.showChatSnack($r('app.string.voice_network_error'), 2000, SnackBarTone.ERROR)
      })
    })
  }

  // 取消录音（上滑取消）
  handleVoiceRecordCancel(): void {
    ServiceRegistry.speechRecognition().cancelListening()
  }

  // 结束录音（松开发送）
  handleVoiceRecordFinish(): void {
    ServiceRegistry.speechRecognition().finishListening()
  }

  // 录音完成，发送消息
  private handleRecordingComplete(text: string): void {
    if (text.trim() === '') {
      this.showChatSnack($r('app.string.voice_empty_result'), 2000, SnackBarTone.WARNING)
      return
    }
    this.inputText = text
    if (!this.isSending && this.inputText.trim() !== '') {
      this.handleSend()
    }
  }

  // 声波动画
  private startWaveformAnimation(): void {
    this.waveformTimerId = 0
  }

  private stopWaveformAnimation(): void {
    this.waveformTimerId = -1
  }

  // 录音安全超时管理：isRecording 变化时自动启停计时器
  @Monitor('isRecording')
  onRecordingStateChanged(): void {
    if (this.isRecording) {
      this.startRecordingSafetyTimer()
    } else {
      this.stopRecordingSafetyTimer()
    }
  }

  private startRecordingSafetyTimer(): void {
    this.stopRecordingSafetyTimer()
    this.recordingSafetyTimerId = setTimeout(() => {
      this.recordingSafetyTimerId = -1
      if (this.isRecording) {
        console.warn('ChatPage', 'Recording safety timeout: auto-cancelling after 65s')
        ServiceRegistry.speechRecognition().cancelListening()
        this.stopWaveformAnimation()
        this.isRecording = false
        this.isRecordingCancelZone = false
        this.showChatSnack($r('app.string.voice_too_short'), 2000, SnackBarTone.WARNING)
      }
    }, 65000)
  }

  private stopRecordingSafetyTimer(): void {
    if (this.recordingSafetyTimerId >= 0) {
      clearTimeout(this.recordingSafetyTimerId)
      this.recordingSafetyTimerId = -1
    }
  }

  // 语音模式：AI 回复完成后自动触发 TTS 朗读
  @Monitor('isSending')
  onSendingCompleted(): void {
    const wasSending = this.previousIsSending
    this.previousIsSending = this.isSending
    if (!wasSending || this.isSending) {
      return // 不是 true→false 转换
    }
    // AI 回复完成，在语音模式下自动朗读最后一条 assistant 消息
    if (!this.isVoiceMode || this.isRecording || this.isEditingMessage) {
      this.lastAutoTtsQuizMessageContentLength = 0
      this.lastAutoTtsQuizMessageId = ''
      return
    }
    const lastMsg = this.findLastAssistantMessage()
    if (lastMsg !== null && lastMsg.content.trim() !== '') {
      let content = lastMsg.content
      // quiz 工具场景：仅朗读验证回复部分，跳过已读的题目文本
      if (this.lastAutoTtsQuizMessageContentLength > 0 &&
          this.lastAutoTtsQuizMessageId === lastMsg.id) {
        const start = this.lastAutoTtsQuizMessageContentLength
        this.lastAutoTtsQuizMessageContentLength = 0
        this.lastAutoTtsQuizMessageId = ''
        if (start < content.length) {
          content = content.substring(start)
        }
      }
      if (content.trim() !== '') {
        this.handleTTS(lastMsg.id, content)
      }
    }
  }

  private findLastAssistantMessage(): ChatMessage | null {
    for (let i = this.messages.length - 1; i >= 0; i--) {
      if (this.messages[i].role === MessageRole.ASSISTANT) {
        return this.messages[i]
      }
    }
    return null
  }

  // 处理模型选择
  handleModelSelect(providerId: string, modelId: string, modelName: string): void {
    const selection = this.findProviderModelSelection(providerId, modelId)
    if (selection === null) {
      console.warn('ChatPage', `[handleModelSelect] Model not found: ${providerId}/${modelId}`)
      return
    }
    this.applyModelSelection(selection.provider, selection.model, modelName, true, true).catch((error: Object) => {
      console.error('ChatPage', `[handleModelSelect] Failed to persist model selection: ${JSON.stringify(error)}`)
    })

    // 关闭模型选择器
    this.isModelSelectorVisible = false

    this.showChatSnack($r('app.string.model_switched'), 2000, SnackBarTone.SUCCESS)
  }

  async sendMessage(): Promise<void> {
    if (this.isSendDispatching || this.isSending) {
      return
    }
    if (!this.guardAttachmentReadyForSend()) {
      return
    }
    this.isSendDispatching = true
    try {
      const prepareResult = this.getSendFlow().prepareSendRequest(
        this.inputText,
        this.pendingAttachments.length,
        this.isSending,
        this.currentProvider,
        this.currentModelId,
        this.chatTaskOrchestrator.canStartNewTask()
      )
      if (!prepareResult.shouldSend || prepareResult.currentProvider === null) {
        return
      }
      const messageContent = prepareResult.messageContent
      const currentProvider = prepareResult.currentProvider
      const effectiveApiKey = prepareResult.effectiveApiKey

      await this.syncToolAvailabilityFromPreferences()
      const requestedToolIds = [
        ...this.selectedToolIds,
        ...this.forcedToolIdsOnce
      ]
      const enabledMcpServerIds = await this.loadEnabledMcpServerIds()
      if (this.collectPendingEnabledMcpToolIds(requestedToolIds, enabledMcpServerIds).length > 0) {
        this.refreshMcpToolAvailabilityInBackground(false)
      }

      const attachmentsToSend = [...this.pendingAttachments]
      const searchEnabled = this.isWebSearchReady() && this.webSearchConversationEnabled
      const selectedToolIds = [...this.selectedToolIds]
      const forcedToolIds = [...this.forcedToolIdsOnce]
      // SEARCH_MODE 是用户偏好,发送时再按当前 provider 收敛为实际可执行模式。
      const activeSearchMode: ChatSearchMode = this.resolveEffectiveSearchModeForCurrentProvider(this.searchMode)
      const activeBuiltinImageGen = this.getActiveComposerBuiltinImageGenEnabled() &&
        this.isOpenAIBuiltinImageGenAvailableForCurrentProvider()
      await this.getSendFlow().executeSend(
        messageContent,
        currentProvider,
        effectiveApiKey,
        attachmentsToSend,
        searchEnabled,
        selectedToolIds,
        forcedToolIds,
        this.currentModelId,
        activeSearchMode,
        activeBuiltinImageGen
      )
      this.forcedToolIdsOnce = []
    } catch (error) {
      console.error('ChatPage', `sendMessage failed: ${JSON.stringify(error)}`)
      this.forcedToolIdsOnce = []
      this.showError($r('app.string.action_failed_retry'))
    } finally {
      this.isSendDispatching = false
    }
  }

  // 处理重新生成（支持非最后一条消息，支持用户消息和 AI 消息）
  async handleRegenerate(message: ChatMessage): Promise<void> {
    const ok = await this.stopActiveGenerationBeforeMessageRewrite()
    if (!ok) {
      return
    }
    const userMsgIndex = resolveUserMessageIndexForRegenerate(this.messages, message)
    if (userMsgIndex < 0) {
      return
    }
    const userMsg = this.messages[userMsgIndex]
    const savedContent = userMsg.content
    const savedAttachments = userMsg.attachments.slice()
    const isFirstRound = userMsgIndex === 0
    const messageIdsToDelete = collectTailMessageIds(this.messages, userMsgIndex)
    await this.chatViewModel.deleteMessagesFromIndex(messageIdsToDelete)
    this.messages.splice(userMsgIndex)
    this.markMessageListChanged()
    if (isFirstRound) {
      this.titleGenerateFailed = false
    }
    this.inputText = savedContent
    this.resetDocumentParseQueue()
    this.pendingAttachments = savedAttachments
    this.handleSend()
  }

  showError(message: string | Resource): void {
    this.showChatSnack(message, 3000, SnackBarTone.ERROR)
  }

  private resetToolExecutionApprovalState(): void {
    this.pendingToolExecutionApprovalToolCallId = ''
    this.toolExecutionApprovalToolId = ''
    this.toolExecutionApprovalIsWriteTool = false
    this.toolExecutionApprovalSourceLabel = ''
    this.toolExecutionApprovalName = ''
    this.toolExecutionApprovalSourceId = ''
    this.toolExecutionApprovalArgumentSummary = this.getNoToolArgumentsText()
    this.toolExecutionApprovalArgumentEntries = []
    this.toolExecutionApprovalArgumentsPreview = '{}'
    this.toolExecutionApprovalArgumentsTruncated = false
    this.showRawToolExecutionApprovalArguments = false
  }

  private applyPendingToolExecutionApproval(interaction: PendingToolInteractionSnapshot): void {
    const preview = buildToolArgumentsPreview(interaction.argumentsJson, 4, 800)
    this.pendingToolExecutionApprovalToolCallId = interaction.id
    this.toolExecutionApprovalToolId = interaction.toolId.trim()
    this.toolExecutionApprovalIsWriteTool = interaction.permissionLevel === ToolPermissionLevel.WRITE
    this.toolExecutionApprovalSourceLabel = interaction.sourceLabel.trim()
    this.toolExecutionApprovalName = interaction.toolName.trim() !== ''
      ? interaction.toolName.trim()
      : pickLocalizedText('未知工具', 'Unknown tool')
    this.toolExecutionApprovalSourceId = interaction.sourceType === ToolSourceType.MCP ? interaction.sourceId.trim() : ''
    this.toolExecutionApprovalArgumentSummary = preview.summary
    this.toolExecutionApprovalArgumentEntries = [...preview.entries]
    this.toolExecutionApprovalArgumentsPreview = preview.rawPreview
    this.toolExecutionApprovalArgumentsTruncated = preview.rawTruncated
    this.showRawToolExecutionApprovalArguments = false
    this.showToolExecutionApprovalSheet = true
  }

  private syncPendingToolInteractionFromService(): void {
    if (this.sessionId === '') {
      return
    }
    const interaction = ServiceRegistry.toolExecution().getPendingInteractionForSession(this.sessionId)
    if (interaction === null) {
      // service 里已经没有 pending 了, 一并清掉折叠态记录, 下次出现新 pending 再重新弹。
      this.dismissedPendingToolCallId = ''
      this.lastAutoTtsQuizToolCallId = ''
      if (this.pendingToolExecutionApprovalToolCallId !== '') {
        this.showToolExecutionApprovalSheet = false
        this.resetToolExecutionApprovalState()
      }
      return
    }
    if (interaction.kind !== PendingToolInteractionKind.APPROVAL) {
      // ASK_USER 走 AskUserCard, 这里不弹 sheet。残留 sheet 状态清掉避免脏 UI。
      if (this.pendingToolExecutionApprovalToolCallId !== '') {
        this.showToolExecutionApprovalSheet = false
        this.resetToolExecutionApprovalState()
      }
      // 语音模式：quiz 工具出现时自动 TTS 朗读题目
      this.tryAutoTtsForQuizInteraction(interaction)
      return
    }
    if (this.dismissedPendingToolCallId === interaction.id) {
      // 用户刚下滑过这个 toolCall 的 sheet, 保持折叠态, 不立即重弹。
      // 用户回到列表页再进来 / 点 SnackBar 的"展开"按钮时会通过 expandPendingToolApproval 清掉。
      return
    }
    if (this.showToolExecutionApprovalSheet &&
      this.pendingToolExecutionApprovalToolCallId === interaction.id) {
      return
    }
    this.applyPendingToolExecutionApproval(interaction)
  }

  // 语音模式：quiz 工具（math_quiz / english_quiz）出现 pending 交互时自动朗读题目
  private tryAutoTtsForQuizInteraction(interaction: PendingToolInteractionSnapshot): void {
    if (!this.isVoiceMode || this.isRecording) {
      return
    }
    const isQuiz = interaction.toolId === MATH_QUIZ_TOOL_ID ||
      interaction.toolId === ENGLISH_QUIZ_TOOL_ID
    if (!isQuiz) {
      return
    }
    // 避免 this.lastAutoTtsQuizToolCallId 与 interaction.id 重复触发
    if (this.lastAutoTtsQuizToolCallId === interaction.id) {
      return
    }
    this.lastAutoTtsQuizToolCallId = interaction.id

    const ttsText = this.buildQuizTtsText(interaction)
    if (ttsText === '') {
      return
    }

    // 延迟 800ms 等待流式内容最终化
    const capturedId = interaction.id
    setTimeout(() => {
      if (this.lastAutoTtsQuizToolCallId !== capturedId) {
        return
      }
      const lastMsg = this.findLastAssistantMessage()
      const msgId = lastMsg !== null ? lastMsg.id : ''
      // 记录当前消息 content 长度及消息 ID，后续 onSendingCompleted 仅朗读新增的验证内容
      if (lastMsg !== null) {
        this.lastAutoTtsQuizMessageId = lastMsg.id
        this.lastAutoTtsQuizMessageContentLength = lastMsg.content.length
      }
      this.handleTTS(msgId, ttsText)
    }, 800)
  }

  // 构造 quiz 工具的 TTS 朗读文本：AI 消息正文 + 题目内容
  private buildQuizTtsText(interaction: PendingToolInteractionSnapshot): string {
    let aiText = ''
    const lastMsg = this.findLastAssistantMessage()
    if (lastMsg !== null) {
      for (let i = 0; i < lastMsg.parts.length; i++) {
        const part = lastMsg.parts[i]
        if (part.kind === MessagePartKind.TEXT && part.text.trim() !== '') {
          aiText += part.text.trim() + ' '
        }
      }
      if (aiText === '' && lastMsg.content.trim() !== '') {
        aiText = lastMsg.content.trim()
      }
    }

    let quizText = ''
    try {
      const parsed = JSON.parse(interaction.argumentsJson) as Record<string, Object>
      if (interaction.toolId === MATH_QUIZ_TOOL_ID) {
        quizText = (parsed['question'] as string) ?? ''
        const expression = (parsed['expression'] as string) ?? ''
        if (expression !== '') {
          quizText += ' ' + expression + ' 等于几？'
        }
      } else if (interaction.toolId === ENGLISH_QUIZ_TOOL_ID) {
        const questionType = (parsed['question_type'] as string) ?? 'word'
        let question = (parsed['question'] as string) ?? ''
        if (question === '') {
          // 兼容旧格式
          if (questionType === 'sentence') {
            question = (parsed['sentence'] as string) ?? ''
          } else {
            question = (parsed['word'] as string) ?? ''
          }
        }
        if (question !== '') {
          quizText = questionType === 'sentence' ? ('请说出英语句子: ' + question) : ('请说出英语单词: ' + question)
        }
      }
    } catch (_e) {}

    return (aiText.trim() + ' ' + quizText.trim()).trim()
  }

  // 提供给 SnackBar action 调用: 用户主动展开折叠的待确认工具调用。
  expandPendingToolApproval(): void {
    this.dismissedPendingToolCallId = ''
    this.syncPendingToolInteractionFromService()
  }

  private resolveToolExecutionApproval(approved: boolean): void {
    const toolCallId = this.pendingToolExecutionApprovalToolCallId
    this.isResolvingToolExecutionApproval = true
    this.showToolExecutionApprovalSheet = false
    this.resetToolExecutionApprovalState()
    if (toolCallId !== '') {
      const resolved = ServiceRegistry.toolExecution().resolvePendingApproval(toolCallId, approved)
      if (!resolved) {
        console.warn('ChatPage', `resolveToolExecutionApproval: no pending approval for ${toolCallId}`)
      }
    }
  }

  // AskUserCard 提交回调: 把答案 JSON 喂给 ToolExecutionService.handleAskUser 的 await
  handleAskUserAnswer(toolCallId: string, answerJson: string): void {
    const resolved = ServiceRegistry.toolExecution().resolvePendingAnswer(toolCallId, answerJson)
    if (!resolved) {
      console.warn('ChatPage', `handleAskUserAnswer: no pending resolver for ${toolCallId}`)
      return
    }
  }

  private handleToolExecutionApprovalSheetDisappear(): void {
    this.showToolExecutionApprovalSheet = false
    const dismissedToolCallId = this.pendingToolExecutionApprovalToolCallId
    this.resetToolExecutionApprovalState()
    if (this.isResolvingToolExecutionApproval) {
      this.isResolvingToolExecutionApproval = false
      return
    }
    if (dismissedToolCallId === '' || !this.isPageVisible || this.sessionId === '') {
      return
    }
    // 仅当 service 里这个 toolCall 仍然 pending 时才提示折叠;
    // 已被外部 cancel 的话直接放过,不要给用户看一个废弃的 banner。
    if (!ServiceRegistry.toolExecution().hasPendingInteractionForSession(this.sessionId)) {
      return
    }
    this.dismissedPendingToolCallId = dismissedToolCallId
    const opts = new SnackBarDisplayOptions()
    opts.message = pickLocalizedText(
      '工具调用待确认,可点击展开继续',
      'Tool call pending, tap to expand'
    )
    opts.duration = 4000
    opts.tone = SnackBarTone.DEFAULT
    opts.actionText = pickLocalizedText('展开', 'Expand')
    opts.onAction = (): void => {
      this.expandPendingToolApproval()
    }
    showSnackBar(this.getUIContext(), opts)
  }

  private async approveCurrentMcpServerAlways(): Promise<void> {
    const toolId = this.toolExecutionApprovalToolId.trim()
    if (toolId === '') {
      this.resolveToolExecutionApproval(true)
      return
    }
    try {
      await this.mcpService.updateToolApprovalPolicy(toolId, ToolApprovalPolicy.ALWAYS_ALLOW)
      this.showChatSnack(pickLocalizedText('已设为始终允许', 'Always allow enabled'), 2000, SnackBarTone.SUCCESS)
    } catch (error) {
      console.error('ChatPage', `Failed to persist tool approval policy: ${JSON.stringify(error)}`)
      this.showChatSnack(
        pickLocalizedText('保存始终允许失败，本次继续执行', 'Failed to save always allow; continuing once'),
        2500,
        SnackBarTone.ERROR
      )
    }
    this.resolveToolExecutionApproval(true)
  }

  // 处理删除消息
  async handleDeleteMessage(message: ChatMessage): Promise<void> {
    const index = findMessageIndexById(this.messages, message.id)
    if (index < 0) {
      return
    }
    this.messages.splice(index, 1)
    this.markMessageListChanged()
    await this.chatViewModel.deleteMessage(message.id)
    this.showChatSnack($r('app.string.message_deleted'), 2000, SnackBarTone.SUCCESS)
  }

  // 处理翻译请求
  handleTranslate(content: string, targetLang: string, callback: (result: string, errorMessage: string) => void): void {
    this.aiTaskService.translateText(content, targetLang).then((result) => {
      if (result.success) {
        callback(result.content, '')
      } else {
        callback('', result.errorMessage)
      }
    }).catch((error: Error) => {
      callback('', `${pickLocalizedText('翻译失败：', 'Translation failed: ')}${error.message}`)
    })
  }

  // 处理TTS朗读
  private handleTTS(messageId: string, content: string): void {
    // 如果正在朗读其他消息，先停止
    if (this.speakingMessageId !== '') {
      ServiceRegistry.tts().stop()
    }

    this.setSpeakingMessageId(messageId)

    ServiceRegistry.tts().speak(content, {
      onStart: () => {
        // 朗读开始
      },
      onComplete: () => {
        // 朗读完成
        this.setSpeakingMessageId('')
      },
      onError: (error: string) => {
        this.setSpeakingMessageId('')
        this.showChatSnack(error, 3000, SnackBarTone.ERROR)
      }
    })
  }

  // 处理停止TTS朗读
  private handleTTSStop(): void {
    ServiceRegistry.tts().stop()
    this.setSpeakingMessageId('')
  }

  private setSpeakingMessageId(messageId: string): void {
    setAppUiStateValue(AppStorageKeys.SPEAKING_MESSAGE_ID, messageId)
  }

  // 处理新建对话
  private async handleNewChat(): Promise<void> {
    await this.prepareCurrentSessionForTransition()
    this.clearDraftAutosaveTimer()
    // 创建新会话
    const assistant = await ServiceRegistry.assistant().getCurrentAssistantForNewChat()
    const session = await this.chatViewModel.createNewSession(
      '',
      assistant.id,
      assistant.defaultModelId,
      assistant.defaultProviderId
    )
    this.isNewChatTransition = true
    this.routeParams = {} as ChatPageRouteParams
    this.inputText = ''
    this.resetDocumentParseQueue()
    this.pendingAttachments = []
    // 清空当前消息
    this.clearMessages()
    // 更新会话ID和标题
    this.sessionId = session.id
    this.sessionTitle = session.title
    this.applyAssistantSnapshot(assistant.id, assistant.avatarSymbol, assistant.color)
    // 重置标题状态
    this.isTitleGenerating = false
    this.titleGenerateFailed = false
    // 标记为新建的空会话（返回时需要删除）
    this.isNewEmptySession = true
    this.syncActiveSessionBinding()
    // 切到新会话后，按新会话的活跃请求状态重置 isSending / currentTaskId，
    // 避免上一会话(可能仍在后台生成中)的状态串台到新会话。
    this.syncSendingStateFromRuntime()
    await this.validateAndSetCurrentModel()

    this.showChatSnack($r('app.string.chat_created'), 2000, SnackBarTone.SUCCESS)
  }

  // 处理重新生成标题
  private async handleRegenerateTitle(): Promise<void> {
    if (this.messages.length === 0) {
      this.showChatSnack($r('app.string.chat_empty'), 2000, SnackBarTone.ERROR)
      return
    }
    this.titleGenerateFailed = false
    this.showChatSnack($r('app.string.generating_title'), 2000)
    this.chatViewModel.regenerateTitle()
  }

  // 处理删除对话
  private handleDeleteChat(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.delete_chat'),
      message: $r('app.string.delete_session_confirm'),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
          // 取消
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: $r('app.color.status_error'),
        action: async () => {
          await this.chatViewModel.deleteSession(this.sessionId)
          this.navPathStack.pop()
        }
      }
    })
  }

  // 处理保存编辑的标题
  private async handleSaveTitle(newTitle: string): Promise<void> {
    if (newTitle.trim() === '') {
      return
    }
    await this.chatViewModel.updateSessionTitle(newTitle.trim())
    this.sessionTitle = newTitle.trim()
    this.showChatSnack($r('app.string.title_updated'), 2000, SnackBarTone.SUCCESS)
  }

  // ========== 多选模式相关方法 ==========

  // 点击防抖标志
  private isProcessingMessageClick: boolean = false

  // 编辑消息：进入内联编辑模式
  private async handleEditMessage(message: ChatMessage): Promise<void> {
    const ok = await this.stopActiveGenerationBeforeMessageRewrite()
    if (!ok) {
      return
    }
    this.editingOriginalContent = message.content
    this.editingOriginalAttachments = [...message.attachments]
    this.editingMessageId = message.id
    this.editingMessageIsUser = message.role === MessageRole.USER
    this.inputText = message.content
    this.resetDocumentParseQueue()
    this.pendingAttachments = [...message.attachments]
    this.preparePendingDocumentAttachments()
    const messageIndex = findMessageIndexById(this.messages, message.id)
    this.isEditingMessage = true
    this.getScrollUiFlow().setInputBarVisible(true)
    this.autoFocusInput = true
    await new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve()
      }, 100)
    })
    if (messageIndex >= 0) {
      this.scroller.scrollToIndex(
        toListScrollIndexForMessage(messageIndex),
        true,
        ScrollAlign.CENTER
      )
    }
  }

  // ========== 内联编辑模式相关方法 ==========

  // 取消编辑
  private handleCancelEdit(): void {
    // 恢复原始内容
    this.inputText = ''
    this.resetDocumentParseQueue()
    this.pendingAttachments = []

    // 退出编辑模式
    this.isEditingMessage = false
    this.editingMessageId = ''
    this.editingOriginalContent = ''
    this.editingOriginalAttachments = []
    // 允许下次进入编辑时 ChatInputBar @Monitor('autoFocus') 重新触发
    this.autoFocusInput = false
    // 收键盘 + clearFocus + stopInputSession, 避免 textarea 残留焦点引发键盘异常弹起
    this.safeStopInputSession()
  }

  // 内联编辑模式：保存并发送
  private async handleSaveAndSendInline(): Promise<void> {
    if (!this.guardAttachmentReadyForSend()) {
      return
    }
    this.stopActiveGenerationBeforeMessageRewrite()
    await this.getInlineEditFlow().saveAndSendInline(
      this.editingMessageId,
      this.inputText,
      this.pendingAttachments,
      this.getActiveComposerWebSearchEnabled(),
      this.getActiveComposerSelectedToolIds(),
      this.getActiveComposerReasoningLevel()
    )
  }

  private async stopActiveGenerationBeforeMessageRewrite(): Promise<boolean> {
    const hasPendingToolInteraction = this.sessionId !== '' &&
      ServiceRegistry.toolExecution().hasPendingInteractionForSession(this.sessionId)
    if (!this.isSending && this.currentTaskId === '' && !this.showToolExecutionApprovalSheet &&
      !hasPendingToolInteraction) {
      return true
    }

    // 有 pending 工具交互 / sheet 弹出中时,编辑或重新生成会丢弃用户正在审批的工具调用,
    // 必须给一次显式确认,避免静默吞掉用户操作。仅有"普通流式生成中"则继续保留默认覆盖行为
    // (用户已经知道点编辑/重新生成会替换当前回复)。
    if (hasPendingToolInteraction || this.showToolExecutionApprovalSheet) {
      const confirmed = await this.confirmCancelPendingToolForRewrite()
      if (!confirmed) {
        return false
      }
    }

    if (this.showToolExecutionApprovalSheet) {
      this.showToolExecutionApprovalSheet = false
      this.resetToolExecutionApprovalState()
    }
    if (hasPendingToolInteraction) {
      ServiceRegistry.toolExecution().cancelPendingInteractionsForSession(this.sessionId)
    }
    this.dismissedPendingToolCallId = ''
    this.webSearchService.cancelAllRequests()
    if (this.isSending || this.currentTaskId !== '') {
      this.chatViewModel.cancelGenerationForMessageRewrite(this.sessionId)
      if (this.currentTaskId !== '') {
        this.chatTaskOrchestrator.cancelTask(this.currentTaskId)
        this.currentTaskId = ''
      }
      this.isSending = false
      this.isLoading = false
      this.forcedToolIdsOnce = []
    }
    return true
  }

  private confirmCancelPendingToolForRewrite(): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      let settled = false
      const settle = (value: boolean): void => {
        if (settled) {
          return
        }
        settled = true
        resolve(value)
      }
      this.getUIContext().showAlertDialog({
        title: pickLocalizedText('取消待确认的工具调用?', 'Cancel pending tool call?'),
        message: pickLocalizedText(
          '当前会话有工具调用待确认,继续编辑或重新生成会取消该工具调用。',
          'A tool call is pending confirmation in this chat. Continuing will cancel it.'
        ),
        primaryButton: {
          value: pickLocalizedText('返回', 'Back'),
          action: (): void => {
            settle(false)
          }
        },
        secondaryButton: {
          value: pickLocalizedText('继续', 'Continue'),
          fontColor: $r('app.color.status_error'),
          action: (): void => {
            settle(true)
          }
        },
        cancel: (): void => {
          // 点遮罩 / 返回键关闭对话框 = 不要继续, 维持当前 pending 工具调用
          settle(false)
        }
      })
    })
  }

  // 分享单条消息：进入多选模式并触发分享
  private handleShareSingleMessage(message: ChatMessage): void {
    this.getSelectionFlow().enterModeWithMessage(message.id)
    this.handleShareSelectedMessages()
  }

  // 进入多选模式
  private handleEnterMultiSelectMode(messageId: string): void {
    this.getSelectionFlow().enterModeWithMessage(messageId)
  }

  // 退出多选模式
  private handleExitMultiSelectMode(): void {
    this.getSelectionFlow().exitMode()
  }

  // 切换消息选中状态（带防抖）
  private handleToggleMessageSelection(messageId: string): void {
    // 防止重复点击
    if (this.isProcessingMessageClick) {
      return
    }
    this.isProcessingMessageClick = true

    this.selectedMessageIds = this.getSelectionFlow().toggleSelection(this.selectedMessageIds, messageId)

    // 100ms 后重置标志
    setTimeout(() => {
      this.isProcessingMessageClick = false
    }, 100)
  }

  // 全选/取消全选
  private handleSelectAllMessages(): void {
    this.selectedMessageIds = this.getSelectionFlow().toggleSelectAll(this.selectedMessageIds)
  }

  // 删除选中的消息
  private async handleDeleteSelectedMessages(): Promise<void> {
    if (this.selectedMessageIds.length === 0) {
      return
    }

    this.getUIContext().showAlertDialog({
      title: $r('app.string.delete_messages'),
      message: $r('app.string.delete_selected_messages_confirm'),
      primaryButton: {
        value: $r('app.string.cancel'),
        action: () => {
          // 取消
        }
      },
      secondaryButton: {
        value: $r('app.string.delete'),
        fontColor: '#FF3B30',
        action: async () => {
          await this.getSelectionFlow().deleteSelectedMessages(this.selectedMessageIds)
        }
      }
    })
  }

  // 分享选中的消息
  private handleShareSelectedMessages(): void {
    this.getSelectionFlow().openSharePreview(this.selectedMessageIds)
  }
}

@Builder
export function ChatPageBuilder(_name: string, param: Object) {
  ChatPage({
    routeParamsSeed: param as ChatPageRouteParams
  })
}
