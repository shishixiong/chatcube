import {
  AttachmentType,
  MessageAttachment,
  ModelProvider,
  ToolApprovalPolicy,
  ToolCall,
  ToolPermissionLevel,
  ToolResult,
  ToolSourceType
} from '../models/ChatModels'
import { getToolRegistry, RegisteredTool, ToolRegistry } from './ToolRegistry'
import {
  ASK_USER_TOOL_ID,
  LEGACY_WEB_SEARCH_TOOL_ID,
  SCRAPE_WEB_TOOL_ID,
  SEARCH_WEB_TOOL_ID,
  MATH_QUIZ_TOOL_ID,
  ENGLISH_QUIZ_TOOL_ID,
  NUMBER_PUZZLE_TOOL_ID,
  HANDWRITING_PRACTICE_TOOL_ID,
  CATEGORIZATION_TOOL_ID,
  VERTICAL_MATH_TOOL_ID,
  MAZE_TOOL_ID,
  SUDOKU_TOOL_ID,
  PICTURE_VOCAB_TOOL_ID,
  LISTENING_QUIZ_TOOL_ID,
  isAskUserFunctionName,
  isMathQuizFunctionName,
  isEnglishQuizFunctionName,
  isHuarongdaoFunctionName,
  isNumberPuzzleFunctionName,
  isHandwritingPracticeFunctionName,
  isCategorizationFunctionName,
  isVerticalMathFunctionName,
  isMazeFunctionName,
  isSudokuFunctionName,
  isPictureVocabFunctionName,
  isListeningQuizFunctionName,
  isScrapeWebFunctionName,
  isSearchWebFunctionName,
  isGrantStarFunctionName
} from '../utils/SearchToolIdentityUtils'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { setAppUiStateValue } from '../state/AppUiState'
import { getImageIndexService, ImageIndexService } from './ImageIndexService'
import { ImageSource } from '../models/ImageIndexModels'
import { generateMaze } from '../utils/MazeGame'
import { generateSudoku, getDifficultyConfig } from '../utils/SudokuGenerator'
import { validateAndNormalizeCategorization } from '../utils/CategorizationValidation'
import { validateMathQuizArgs } from '../utils/MathQuizValidation'
import { validateEnglishQuizArgs } from '../utils/EnglishQuizValidation'
import { validatePictureVocabArgs } from '../utils/PictureVocabValidation'
import { validateListeningQuizArgs } from '../utils/ListeningQuizValidation'
import { ServiceRegistry } from './ServiceRegistry'
import { modelSupportsVision } from './registry/ModelAbilityRegistry'
import { RequestMessage, AIApiConfig } from './AIApiService'
import { getProviderViewModel } from '../viewmodels/ProviderViewModel'
import { getEffectiveApiKey } from '../config/PresetProviders'
import { getStarRewardService } from './StarRewardService'
import { StarActivityType } from '../models/StarEventModels'


// 取消检查回调类型
type CancelCheckCallback = () => boolean
export type PendingToolInteractionChangeCallback = () => void

export enum PendingToolInteractionKind {
  APPROVAL = 'approval',
  ASK_USER = 'ask_user'
}

export class ToolExecutionContext {
  sessionId: string
  sessionTitle: string

  constructor(sessionId: string = '', sessionTitle: string = '') {
    this.sessionId = sessionId
    this.sessionTitle = sessionTitle
  }
}

// 待确认/待答复的工具交互快照。
//
// 注意:
// - 这些快照只存在内存里 (pendingApprovals / pendingAnswers Map)。
// - App 进程被系统杀死或主动 kill 后, 内存里的 Promise resolver 与 HTTP 流都会一起丢失,
//   下次冷启动只能依赖 ChatPage.fixInconsistentState + RUNNING_CHAT_TASK_COUNT 把残留的
//   isGenerating / isSearching 状态重置, 从用户视角等同于"任务中断"。
// - 不要试图用 Preferences 持久化这里的 resolver, resolver 跨进程没有意义。
// - sourceType / permissionLevel 之所以写成 string 而不是 enum, 是因为 ChatModels.ToolCall /
//   ToolConfig 里这两个字段就是 string 类型(历史选择, 整改要触及全工程, 这里跟随上游)。
//   通过 ToolSourceType / ToolPermissionLevel 比较时仍然是字符串相等, 不影响语义。
export class PendingToolInteractionSnapshot {
  id: string = ''
  kind: PendingToolInteractionKind = PendingToolInteractionKind.APPROVAL
  sessionId: string = ''
  sessionTitle: string = ''
  toolId: string = ''
  toolName: string = ''
  sourceLabel: string = ''
  sourceType: string = ToolSourceType.BUILTIN
  sourceId: string = ''
  permissionLevel: string = ToolPermissionLevel.READ
  argumentsJson: string = ''
  createdAt: number = 0
}

// 工具结果是否被取消的语义化判定结果, 取代裸 JSON 检查。
export class CancelledToolResultInfo {
  cancelled: boolean = false
  // 取消时希望透传给用户的简短文案, 取消标志为 false 时无意义。
  reason: string = ''
}

// 解析单条 ToolResult 是否被取消, 取消时同时透出原因字符串。
//
// 之前是用 `content.includes('"cancelled":true')` 这种字符串子串匹配, 模型把 cancelled 拼到
// 普通业务字段里就会误判。这里改走 JSON.parse + Object 索引访问, 失败时按"未取消"处理。
export function isCancelledToolResult(result: ToolResult): CancelledToolResultInfo {
  const info = new CancelledToolResultInfo()
  const content = result.content.trim()
  if (content === '') {
    return info
  }
  let parsed: Object | null = null
  try {
    parsed = JSON.parse(content) as Object
  } catch (_error) {
    return info
  }
  if (parsed === null || typeof parsed !== 'object') {
    return info
  }
  const record = parsed as Record<string, Object>
  const cancelledRaw = record['cancelled']
  if (cancelledRaw !== true) {
    return info
  }
  info.cancelled = true
  const errorRaw = record['error']
  if (typeof errorRaw === 'string') {
    info.reason = (errorRaw as string).trim()
  }
  return info
}

class PendingToolApprovalRuntime {
  snapshot: PendingToolInteractionSnapshot
  resolve: (approved: boolean) => void

  constructor(snapshot: PendingToolInteractionSnapshot, resolve: (approved: boolean) => void) {
    this.snapshot = snapshot
    this.resolve = resolve
  }
}

class PendingToolAnswerRuntime {
  snapshot: PendingToolInteractionSnapshot
  resolve: (answerJson: string | null) => void

  constructor(snapshot: PendingToolInteractionSnapshot, resolve: (answerJson: string | null) => void) {
    this.snapshot = snapshot
    this.resolve = resolve
  }
}

// 工具执行服务 - 负责执行工具调用
export class ToolExecutionService {
  private static instance: ToolExecutionService | null = null
  private registry: ToolRegistry
  // 当前取消检查回调
  private cancelCheckCallback: CancelCheckCallback | null = null
  private pendingApprovals: Map<string, PendingToolApprovalRuntime> = new Map()
  private pendingAnswers: Map<string, PendingToolAnswerRuntime> = new Map()
  private pendingInteractionChangeCallbacks: PendingToolInteractionChangeCallback[] = []

  private constructor() {
    this.registry = getToolRegistry()
  }

  static getInstance(): ToolExecutionService {
    if (ToolExecutionService.instance === null) {
      ToolExecutionService.instance = new ToolExecutionService()
    }
    return ToolExecutionService.instance
  }

  // 设置取消检查回调
  setCancelCheckCallback(callback: CancelCheckCallback | null): void {
    this.cancelCheckCallback = callback
  }

  // 清除取消检查回调
  clearCancelCheckCallback(): void {
    this.cancelCheckCallback = null
  }

  // 检查是否已取消
  private isCancelled(): boolean {
    if (this.cancelCheckCallback !== null) {
      return this.cancelCheckCallback()
    }
    return false
  }

  private publishPendingInteractionChanged(): void {
    setAppUiStateValue(AppStorageKeys.PENDING_TOOL_INTERACTION_TICK, Date.now())
    const callbacks = this.pendingInteractionChangeCallbacks.slice()
    for (let i = 0; i < callbacks.length; i++) {
      callbacks[i]()
    }
  }

  addPendingInteractionChangeCallback(callback: PendingToolInteractionChangeCallback): () => void {
    this.pendingInteractionChangeCallbacks.push(callback)
    return (): void => {
      const index = this.pendingInteractionChangeCallbacks.indexOf(callback)
      if (index >= 0) {
        this.pendingInteractionChangeCallbacks.splice(index, 1)
      }
    }
  }

  private clonePendingSnapshot(snapshot: PendingToolInteractionSnapshot): PendingToolInteractionSnapshot {
    const cloned = new PendingToolInteractionSnapshot()
    cloned.id = snapshot.id
    cloned.kind = snapshot.kind
    cloned.sessionId = snapshot.sessionId
    cloned.sessionTitle = snapshot.sessionTitle
    cloned.toolId = snapshot.toolId
    cloned.toolName = snapshot.toolName
    cloned.sourceLabel = snapshot.sourceLabel
    cloned.sourceType = snapshot.sourceType
    cloned.sourceId = snapshot.sourceId
    cloned.permissionLevel = snapshot.permissionLevel
    cloned.argumentsJson = snapshot.argumentsJson
    cloned.createdAt = snapshot.createdAt
    return cloned
  }

  private buildApprovalSnapshot(
    toolCall: ToolCall,
    tool: RegisteredTool,
    context: ToolExecutionContext
  ): PendingToolInteractionSnapshot {
    const snapshot = new PendingToolInteractionSnapshot()
    snapshot.id = toolCall.id
    snapshot.kind = PendingToolInteractionKind.APPROVAL
    snapshot.sessionId = context.sessionId
    snapshot.sessionTitle = context.sessionTitle
    snapshot.toolId = tool.config.id
    snapshot.toolName = tool.config.name
    snapshot.sourceLabel = tool.config.sourceLabel
    snapshot.sourceType = tool.config.sourceType
    snapshot.sourceId = tool.config.sourceId
    snapshot.permissionLevel = tool.config.permissionLevel
    snapshot.argumentsJson = toolCall.arguments
    snapshot.createdAt = Date.now()
    return snapshot
  }

  private buildAskUserSnapshot(toolCall: ToolCall, context: ToolExecutionContext): PendingToolInteractionSnapshot {
    const snapshot = new PendingToolInteractionSnapshot()
    snapshot.id = toolCall.id
    snapshot.kind = PendingToolInteractionKind.ASK_USER
    snapshot.sessionId = context.sessionId
    snapshot.sessionTitle = context.sessionTitle
    snapshot.toolId = ASK_USER_TOOL_ID
    snapshot.toolName = toolCall.displayName
    snapshot.sourceLabel = toolCall.sourceLabel
    snapshot.sourceType = toolCall.sourceType
    snapshot.sourceId = ''
    snapshot.permissionLevel = toolCall.permissionLevel
    snapshot.argumentsJson = toolCall.arguments
    snapshot.createdAt = Date.now()
    return snapshot
  }

  getPendingInteractionForSession(sessionId: string): PendingToolInteractionSnapshot | null {
    if (sessionId === '') {
      return null
    }
    let found: PendingToolInteractionSnapshot | null = null
    this.pendingApprovals.forEach((runtime: PendingToolApprovalRuntime) => {
      if (found === null && runtime.snapshot.sessionId === sessionId) {
        found = this.clonePendingSnapshot(runtime.snapshot)
      }
    })
    if (found !== null) {
      return found
    }
    this.pendingAnswers.forEach((runtime: PendingToolAnswerRuntime) => {
      if (found === null && runtime.snapshot.sessionId === sessionId) {
        found = this.clonePendingSnapshot(runtime.snapshot)
      }
    })
    return found
  }

  getFirstPendingInteraction(): PendingToolInteractionSnapshot | null {
    const snapshots = this.getPendingInteractions()
    return snapshots.length > 0 ? snapshots[0] : null
  }

  getPendingInteractions(): PendingToolInteractionSnapshot[] {
    const interactions: PendingToolInteractionSnapshot[] = []
    this.pendingApprovals.forEach((runtime: PendingToolApprovalRuntime) => {
      interactions.push(this.clonePendingSnapshot(runtime.snapshot))
    })
    this.pendingAnswers.forEach((runtime: PendingToolAnswerRuntime) => {
      interactions.push(this.clonePendingSnapshot(runtime.snapshot))
    })
    return interactions
  }

  hasPendingInteractionForSession(sessionId: string): boolean {
    return this.getPendingInteractionForSession(sessionId) !== null
  }

  resolvePendingApproval(toolCallId: string, approved: boolean): boolean {
    const runtime = this.pendingApprovals.get(toolCallId)
    if (runtime === undefined) {
      return false
    }
    this.pendingApprovals.delete(toolCallId)
    runtime.resolve(approved)
    this.publishPendingInteractionChanged()
    return true
  }

  resolvePendingAnswer(toolCallId: string, answerJson: string | null): boolean {
    const runtime = this.pendingAnswers.get(toolCallId)
    if (runtime === undefined) {
      return false
    }
    this.pendingAnswers.delete(toolCallId)
    runtime.resolve(answerJson)
    this.publishPendingInteractionChanged()
    return true
  }

  cancelPendingInteractionsForSession(sessionId: string): void {
    if (sessionId === '') {
      return
    }
    const approvalIds: string[] = []
    this.pendingApprovals.forEach((runtime: PendingToolApprovalRuntime, key: string) => {
      if (runtime.snapshot.sessionId === sessionId) {
        approvalIds.push(key)
      }
    })
    for (let i = 0; i < approvalIds.length; i++) {
      this.resolvePendingApproval(approvalIds[i], false)
    }

    const answerIds: string[] = []
    this.pendingAnswers.forEach((runtime: PendingToolAnswerRuntime, key: string) => {
      if (runtime.snapshot.sessionId === sessionId) {
        answerIds.push(key)
      }
    })
    for (let i = 0; i < answerIds.length; i++) {
      this.resolvePendingAnswer(answerIds[i], null)
    }
  }

  // 全局拒绝并清空所有 pending 工具交互。
  // 仅在 ChatViewModel.stopGeneration() 全局停止路径里调用, 与逐 session 调用相比少一次
  // 通过 activeRequests 反推 sessionId 的间接路径, 也避免漏掉 activeRequests 已被清空但
  // pending 还在的边界场景。
  cancelAllPendingInteractions(): void {
    const approvalIds: string[] = []
    this.pendingApprovals.forEach((_runtime: PendingToolApprovalRuntime, key: string) => {
      approvalIds.push(key)
    })
    for (let i = 0; i < approvalIds.length; i++) {
      this.resolvePendingApproval(approvalIds[i], false)
    }

    const answerIds: string[] = []
    this.pendingAnswers.forEach((_runtime: PendingToolAnswerRuntime, key: string) => {
      answerIds.push(key)
    })
    for (let i = 0; i < answerIds.length; i++) {
      this.resolvePendingAnswer(answerIds[i], null)
    }
  }

  private normalizeFunctionName(functionName: string): string {
    const rawName = functionName as string | null | undefined
    if (rawName === undefined || rawName === null) {
      return ''
    }
    return rawName.trim()
  }

  private resolveToolId(functionName: string): string | undefined {
    if (functionName !== '') {
      const direct = this.registry.getToolIdByFunctionName(functionName)
      if (direct !== undefined) {
        return direct
      }
    }

    if (isScrapeWebFunctionName(functionName) && this.registry.isToolRegistered(SCRAPE_WEB_TOOL_ID)) {
      return SCRAPE_WEB_TOOL_ID
    }

    if (isSearchWebFunctionName(functionName)) {
      if (this.registry.isToolRegistered(SEARCH_WEB_TOOL_ID)) {
        return SEARCH_WEB_TOOL_ID
      }
      if (this.registry.isToolRegistered(LEGACY_WEB_SEARCH_TOOL_ID)) {
        return LEGACY_WEB_SEARCH_TOOL_ID
      }
    }
    return undefined
  }

  private recordStarEvent(
    activityType: StarActivityType,
    toolCall: ToolCall,
    context: ToolExecutionContext,
    answerJson: string
  ): void {
    void getStarRewardService().recordEvent({
      activityType: activityType,
      payloadJson: answerJson,
      toolCallId: toolCall.id,
      sessionId: context.sessionId
    })
  }

  private buildCancelledResult(toolCall: ToolCall, displayName: string, sourceLabel: string): ToolResult {
    return new ToolResult(
      toolCall.id,
      JSON.stringify({ error: '工具执行已取消', cancelled: true }),
      true,
      displayName,
      sourceLabel
    )
  }

  private async requestApprovalIfNeeded(
    toolCall: ToolCall,
    tool: RegisteredTool,
    context: ToolExecutionContext
  ): Promise<boolean> {
    if (tool.config.sourceType === ToolSourceType.MCP) {
      if (tool.config.approvalPolicy === ToolApprovalPolicy.ALWAYS_ALLOW) {
        toolCall.approvalState = 'auto'
        toolCall.approvalReason = 'always_allow'
        return true
      }
      return await this.requestManualApproval(toolCall, tool, context)
    }

    if (tool.config.permissionLevel !== 'write') {
      toolCall.approvalState = 'auto'
      return true
    }

    return await this.requestManualApproval(toolCall, tool, context)
  }

  private async requestManualApproval(
    toolCall: ToolCall,
    tool: RegisteredTool,
    context: ToolExecutionContext
  ): Promise<boolean> {
    toolCall.approvalState = 'pending'
    try {
      const approved = await new Promise<boolean>((resolve) => {
        const existing = this.pendingApprovals.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(false)
          this.pendingApprovals.delete(toolCall.id)
        }
        const snapshot = this.buildApprovalSnapshot(toolCall, tool, context)
        this.pendingApprovals.set(toolCall.id, new PendingToolApprovalRuntime(snapshot, resolve))
        this.publishPendingInteractionChanged()
      })
      toolCall.approvalState = approved ? 'approved' : 'denied'
      return approved
    } catch (error) {
      console.error('ToolExecutionService', `Approval callback failed: ${JSON.stringify(error)}`)
      toolCall.approvalState = 'denied'
      return false
    }
  }

  // ask_user 特殊路径: 不走通用 executor, 挂起等待 UI 层 (AskUserCard) 的回答,
  // 拿到 answerJson 后直接作为 ToolResult 返回; 用户取消/页面销毁则按 denied 处理。
  private async handleAskUser(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult> {
    // 用 ASK_USER_TOOL_ID 回填, 保证工具卡片/消息事件按统一 id 识别
    toolCall.toolId = ASK_USER_TOOL_ID
    if (toolCall.displayName.trim() === '') {
      toolCall.displayName = '向用户提问'
    }
    toolCall.sourceType = ToolSourceType.BUILTIN
    if (toolCall.sourceLabel.trim() === '') {
      toolCall.sourceLabel = '内置工具'
    }
    toolCall.permissionLevel = ToolPermissionLevel.READ

    // 标记为 pending, UI (AskUserCard) 据此判断是否可交互
    toolCall.approvalState = 'pending'

    let answerJson: string | null = null
    try {
      answerJson = await new Promise<string | null>((resolve) => {
        const existing = this.pendingAnswers.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(null)
          this.pendingAnswers.delete(toolCall.id)
        }
        const snapshot = this.buildAskUserSnapshot(toolCall, context)
        this.pendingAnswers.set(toolCall.id, new PendingToolAnswerRuntime(snapshot, resolve))
        this.publishPendingInteractionChanged()
      })
    } catch (error) {
      console.error('ToolExecutionService', `ask_user answer callback failed: ${JSON.stringify(error)}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `ask_user 失败: ${JSON.stringify(error)}`, cancelled: true }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    // 执行期间被取消 (例如用户在 AskUserCard 外按了停止)
    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'ask_user cancelled by external stop')
      toolCall.approvalState = 'denied'
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    if (answerJson === null) {
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ cancelled: true, error: '用户未回答该问题' }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    // 标记为已回答, 答案 JSON 既写入 approvalReason (UI 显示)也作为 tool_result 回传给模型
    toolCall.approvalState = 'answered'
    toolCall.approvalReason = answerJson
    console.info('ToolExecutionService', `ask_user answered: ${toolCall.id}`)
    return new ToolResult(
      toolCall.id,
      answerJson,
      false,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  // math_quiz 特殊路径: 与 ask_user 类似, 挂起等待 UI 层 (MathQuizCard) 的回答。
  private async handleMathQuiz(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult> {
    toolCall.toolId = MATH_QUIZ_TOOL_ID
    if (toolCall.displayName.trim() === '') {
      toolCall.displayName = '数学游戏'
    }
    toolCall.sourceType = ToolSourceType.BUILTIN
    if (toolCall.sourceLabel.trim() === '') {
      toolCall.sourceLabel = '内置工具'
    }
    toolCall.permissionLevel = ToolPermissionLevel.READ

    // 预校验 (categorization 同款模式): 阻止「答案不在选项 / comparison 方向反 /
    // time 答案与钟面不一致」等坏题进入 pending 态渲染给孩子,
    // 失败直接回 error ToolResult, AI 据 message 自我修正重出。
    const mathValidation = validateMathQuizArgs(toolCall.arguments)
    if (!mathValidation.ok) {
      console.warn('ToolExecutionService', `math_quiz validation failed: ${mathValidation.error}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({
          error: 'validation_failed',
          message: mathValidation.error,
          should_retry: true
        }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    toolCall.approvalState = 'pending'

    let answerJson: string | null = null
    try {
      answerJson = await new Promise<string | null>((resolve) => {
        const existing = this.pendingAnswers.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(null)
          this.pendingAnswers.delete(toolCall.id)
        }
        const snapshot = this.buildAskUserSnapshot(toolCall, context)
        snapshot.kind = PendingToolInteractionKind.ASK_USER
        snapshot.toolId = MATH_QUIZ_TOOL_ID
        this.pendingAnswers.set(toolCall.id, new PendingToolAnswerRuntime(snapshot, resolve))
        this.publishPendingInteractionChanged()
      })
    } catch (error) {
      console.error('ToolExecutionService', `math_quiz answer callback failed: ${JSON.stringify(error)}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `math_quiz 失败: ${JSON.stringify(error)}`, cancelled: true }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'math_quiz cancelled by external stop')
      toolCall.approvalState = 'denied'
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    if (answerJson === null) {
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ cancelled: true, error: '小朋友未回答该题目' }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    toolCall.approvalState = 'answered'
    toolCall.approvalReason = answerJson
    console.info('ToolExecutionService', `math_quiz answered: ${toolCall.id}`)
    this.recordStarEvent('math_quiz', toolCall, context, answerJson)
    return new ToolResult(
      toolCall.id,
      answerJson,
      false,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  // english_quiz 特殊路径: 与 math_quiz 类似, 挂起等待 EnglishQuizCard 回答。
  // 图片解析 (缓存查询 + API 生成) 在后台完成并注入 toolCall.arguments,
  // 卡片自身只做轻量的缓存查询作为首帧优化。
  private async handleEnglishQuiz(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult> {
    toolCall.toolId = ENGLISH_QUIZ_TOOL_ID
    if (toolCall.displayName.trim() === '') {
      toolCall.displayName = '英语看图说话'
    }
    toolCall.sourceType = ToolSourceType.BUILTIN
    if (toolCall.sourceLabel.trim() === '') {
      toolCall.sourceLabel = '内置工具'
    }
    toolCall.permissionLevel = ToolPermissionLevel.READ

    // 0. 预校验 (categorization 同款模式): phonics 的 letter_options 缺正确字母 /
    //    word/sentence 缺 image_prompt 等坏题在进入 pending 态和图片管线之前拦截,
    //    失败直接回 error ToolResult, AI 据 message 自我修正重出。
    const englishValidation = validateEnglishQuizArgs(toolCall.arguments)
    if (!englishValidation.ok) {
      console.warn('ToolExecutionService', `english_quiz validation failed: ${englishValidation.error}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({
          error: 'validation_failed',
          message: englishValidation.error,
          should_retry: true
        }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    // 1. 立即设置 pending 状态, 让卡片立即出现
    toolCall.approvalState = 'pending'

    // 2. 后台解析图片: 缓存查询 + API 生成, 完成后注入 image_path
    //    phonics_choice 题型不需要图片 (字母音 + 字母选项即可), 跳过整个管线
    try {
      const parsed = JSON.parse(toolCall.arguments) as Record<string, Object>
      const questionType = (parsed['question_type'] as string) ?? 'word'

      if (questionType === 'phonics_choice') {
        console.info('ToolExecutionService',
          `english_quiz phonics_choice: skip image pipeline, letter_options=${JSON.stringify(parsed['letter_options'] ?? [])}, sound_text="${(parsed['sound_text'] as string) ?? ''}"`)
      } else {
        const question = (parsed['question'] as string) ?? ''
        const answer = (parsed['correct_answer'] as string) ?? ''
        let word = ''
        let sentence = ''
        if (questionType === 'sentence') {
          sentence = answer
        } else {
          word = answer
        }
        const imagePrompt = (parsed['image_prompt'] as string) ?? ''

        console.info('ToolExecutionService',
          `english_quiz image resolution start: question="${question}", questionType="${questionType}", answer="${answer}", imagePrompt="${imagePrompt.substring(0, 80)}..."`)

        // 三层查找：英语题本地缓存 → 备课预生成图 → 现生图
        const imageIndex = getImageIndexService()
        const quizKey = ImageIndexService.buildEnglishQuizKey(word, sentence)
        let imagePath = ''

        // Tier 1: 英语题本地缓存（包含过去的现生图 + 写回后的备课图）
        const quizHit = await imageIndex.findByKey(ImageSource.ENGLISH_QUIZ, quizKey)
        if (quizHit !== null && quizHit.filePath !== '') {
          imagePath = quizHit.filePath
          console.info('ToolExecutionService',
            `english_quiz tier1 quizCache HIT: key="${quizKey}"`)
        } else if (questionType !== 'sentence' && word !== '' && imagePrompt !== '') {
          // Tier 2: 备课预生成图（仅单词题有干净映射；句子题走 Tier 3 兜底）
          const topicKey = `vocab.${word.toLowerCase().trim()}`
          console.info('ToolExecutionService',
            `english_quiz tier1 miss, checking lesson_plan: topicKey="${topicKey}"`)
          try {
            const planHit = await imageIndex.findByKey(ImageSource.LESSON_PLAN, topicKey)
            if (planHit !== null && planHit.filePath !== '') {
              imagePath = planHit.filePath
              // 写回 Tier 1，下次同词秒开
              await imageIndex.putEntry(ImageSource.ENGLISH_QUIZ, quizKey, planHit.filePath,
                planHit.prompt !== '' ? planHit.prompt : imagePrompt,
                planHit.mimeType,
                { revisedPrompt: planHit.revisedPrompt })
              await imageIndex.markConsumed(planHit.id)
              console.info('ToolExecutionService',
                `english_quiz tier2 lessonPlan HIT: topicKey="${topicKey}", id="${planHit.id}"`)
            } else {
              console.info('ToolExecutionService',
                `english_quiz tier2 lessonPlan MISS: topicKey="${topicKey}"`)
            }
          } catch (e) {
            console.error('ToolExecutionService',
              `english_quiz tier2 error: ${JSON.stringify(e)}`)
          }
        }

        // Tier 3: 现生图（兜底）
        if (imagePath === '' && imagePrompt !== '') {
          console.info('ToolExecutionService',
            `english_quiz tiers 1+2 miss, generating: key="${quizKey}"`)
          const generated = await imageIndex.generateAndStore(ImageSource.ENGLISH_QUIZ, quizKey, imagePrompt)
          if (generated !== null) {
            imagePath = generated.filePath
            console.info('ToolExecutionService',
              `english_quiz tier3 generation SUCCESS: path="${imagePath}"`)
          } else {
            console.error('ToolExecutionService', 'english_quiz tier3 generation FAILED')
          }
        } else if (imagePath === '' && imagePrompt === '') {
          console.warn('ToolExecutionService',
            'english_quiz: no cache hit and imagePrompt empty, cannot generate')
        }

        if (imagePath !== '') {
          parsed['image_path'] = imagePath as Object
          toolCall.arguments = JSON.stringify(parsed)
        } else {
          console.warn('ToolExecutionService', 'english_quiz: imagePath still empty after resolution, card will show loading')
        }
      }
    } catch (error) {
      console.error('ToolExecutionService', `english_quiz image resolution exception: ${JSON.stringify(error)}`)
    }

    let answerJson: string | null = null
    try {
      answerJson = await new Promise<string | null>((resolve) => {
        const existing = this.pendingAnswers.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(null)
          this.pendingAnswers.delete(toolCall.id)
        }
        const snapshot = this.buildAskUserSnapshot(toolCall, context)
        snapshot.kind = PendingToolInteractionKind.ASK_USER
        snapshot.toolId = ENGLISH_QUIZ_TOOL_ID
        this.pendingAnswers.set(toolCall.id, new PendingToolAnswerRuntime(snapshot, resolve))
        this.publishPendingInteractionChanged()
      })
    } catch (error) {
      console.error('ToolExecutionService', `english_quiz answer callback failed: ${JSON.stringify(error)}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `english_quiz 失败: ${JSON.stringify(error)}`, cancelled: true }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'english_quiz cancelled by external stop')
      toolCall.approvalState = 'denied'
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    if (answerJson === null) {
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ cancelled: true, error: '小朋友未回答该题目' }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    toolCall.approvalState = 'answered'
    toolCall.approvalReason = answerJson
    console.info('ToolExecutionService', `english_quiz answered: ${toolCall.id}`)
    this.recordStarEvent('english_quiz', toolCall, context, answerJson)
    return new ToolResult(
      toolCall.id,
      answerJson,
      false,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  // picture_vocab 特殊路径: 看图识词互动工具, 由 PictureVocabCard 收集小朋友的选择。
  // 图片优先用 AI 传入的 image 字段 (base64 或 file_path), 未传时用 image_prompt 兜底生成。
  private async handlePictureVocab(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult> {
    toolCall.toolId = PICTURE_VOCAB_TOOL_ID
    if (toolCall.displayName.trim() === '') {
      toolCall.displayName = '看图识词'
    }
    toolCall.sourceType = ToolSourceType.BUILTIN
    if (toolCall.sourceLabel.trim() === '') {
      toolCall.sourceLabel = '内置工具'
    }
    toolCall.permissionLevel = ToolPermissionLevel.READ

    // 0. 预校验 (categorization 同款模式): options 数量不对 / 缺正确答案等坏题
    //    在进入 pending 态和图片生成之前拦截, 失败直接回 error ToolResult,
    //    AI 据 message 自我修正重出。
    const pvValidation = validatePictureVocabArgs(toolCall.arguments)
    if (!pvValidation.ok) {
      console.warn('ToolExecutionService', `picture_vocab validation failed: ${pvValidation.error}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({
          error: 'validation_failed',
          message: pvValidation.error,
          should_retry: true
        }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    // 1. 立即设置 pending 状态, 让卡片立即出现
    toolCall.approvalState = 'pending'

    // 2. 后台解析图片: 优先用 AI 传入的 image, 未传时用 image_prompt 兜底生成
    try {
      const parsed = JSON.parse(toolCall.arguments) as Record<string, Object>
      const imageField = (parsed['image'] as string) ?? ''
      const imagePrompt = (parsed['image_prompt'] as string) ?? ''
      const correctAnswer = (parsed['correct_answer'] as string) ?? ''
      const mode = (parsed['mode'] as string) ?? 'en'

      if (imageField !== '') {
        parsed['image_path'] = imageField as Object
        toolCall.arguments = JSON.stringify(parsed)
        console.info('ToolExecutionService', `picture_vocab: using AI-provided image for "${correctAnswer}"`)
      } else if (imagePrompt !== '') {
        const imageIndex = getImageIndexService()
        const pvKey = `pv:${mode}:${correctAnswer.toLowerCase().trim()}`
        console.info('ToolExecutionService', `picture_vocab: generating image for key="${pvKey}"`)
        const generated = await imageIndex.generateAndStore(ImageSource.ENGLISH_QUIZ, pvKey, imagePrompt)
        if (generated !== null && generated.filePath !== '') {
          parsed['image_path'] = generated.filePath as Object
          toolCall.arguments = JSON.stringify(parsed)
          console.info('ToolExecutionService', `picture_vocab: image generation SUCCESS: path="${generated.filePath}"`)
        } else {
          console.error('ToolExecutionService', 'picture_vocab: image generation FAILED')
        }
      } else {
        console.warn('ToolExecutionService', 'picture_vocab: no image and no image_prompt, card will show loading')
      }
    } catch (error) {
      console.error('ToolExecutionService', `picture_vocab image resolution exception: ${JSON.stringify(error)}`)
    }

    let answerJson: string | null = null
    try {
      answerJson = await new Promise<string | null>((resolve) => {
        const existing = this.pendingAnswers.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(null)
          this.pendingAnswers.delete(toolCall.id)
        }
        const snapshot = this.buildAskUserSnapshot(toolCall, context)
        snapshot.kind = PendingToolInteractionKind.ASK_USER
        snapshot.toolId = PICTURE_VOCAB_TOOL_ID
        this.pendingAnswers.set(toolCall.id, new PendingToolAnswerRuntime(snapshot, resolve))
        this.publishPendingInteractionChanged()
      })
    } catch (error) {
      console.error('ToolExecutionService', `picture_vocab answer callback failed: ${JSON.stringify(error)}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `picture_vocab 失败: ${JSON.stringify(error)}`, cancelled: true }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'picture_vocab cancelled by external stop')
      toolCall.approvalState = 'denied'
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    if (answerJson === null) {
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ cancelled: true, error: '小朋友未回答该题目' }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    toolCall.approvalState = 'answered'
    toolCall.approvalReason = answerJson
    console.info('ToolExecutionService', `picture_vocab answered: ${toolCall.id}`)
    this.recordStarEvent('picture_vocab', toolCall, context, answerJson)
    return new ToolResult(
      toolCall.id,
      answerJson,
      false,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  // listening_quiz 特殊路径: 与 english_quiz 类似但无图片管线。
  // TTS 朗读由前端 ListeningQuizCard 自行调用, 这里只挂起等待回答。
  private async handleListeningQuiz(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult> {
    toolCall.toolId = LISTENING_QUIZ_TOOL_ID
    if (toolCall.displayName.trim() === '') {
      toolCall.displayName = '听力题'
    }
    toolCall.sourceType = ToolSourceType.BUILTIN
    if (toolCall.sourceLabel.trim() === '') {
      toolCall.sourceLabel = '内置工具'
    }
    toolCall.permissionLevel = ToolPermissionLevel.READ

    // 0. 预校验 (categorization 同款模式): word 空 / options 数量不对 / 缺正确答案等坏题
    //    在进入 pending 态之前拦截, 失败直接回 error ToolResult, AI 据 message 自我修正重出。
    const listeningValidation = validateListeningQuizArgs(toolCall.arguments)
    if (!listeningValidation.ok) {
      console.warn('ToolExecutionService', `listening_quiz validation failed: ${listeningValidation.error}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({
          error: 'validation_failed',
          message: listeningValidation.error,
          should_retry: true
        }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    // 1. 立即设置 pending 状态, 让卡片立即出现
    toolCall.approvalState = 'pending'

    let answerJson: string | null = null
    try {
      answerJson = await new Promise<string | null>((resolve) => {
        const existing = this.pendingAnswers.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(null)
          this.pendingAnswers.delete(toolCall.id)
        }
        const snapshot = this.buildAskUserSnapshot(toolCall, context)
        snapshot.kind = PendingToolInteractionKind.ASK_USER
        snapshot.toolId = LISTENING_QUIZ_TOOL_ID
        this.pendingAnswers.set(toolCall.id, new PendingToolAnswerRuntime(snapshot, resolve))
        this.publishPendingInteractionChanged()
      })
    } catch (error) {
      console.error('ToolExecutionService', `listening_quiz answer callback failed: ${JSON.stringify(error)}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `listening_quiz 失败: ${JSON.stringify(error)}`, cancelled: true }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'listening_quiz cancelled by external stop')
      toolCall.approvalState = 'denied'
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    if (answerJson === null) {
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ cancelled: true, error: '小朋友未回答该题目' }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    toolCall.approvalState = 'answered'
    toolCall.approvalReason = answerJson
    console.info('ToolExecutionService', `listening_quiz answered: ${toolCall.id}`)
    this.recordStarEvent('listening_quiz', toolCall, context, answerJson)
    return new ToolResult(
      toolCall.id,
      answerJson,
      false,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  // number_puzzle 特殊路径: 与 math_quiz/english_quiz 类似, 挂起等待 NumberPuzzleCard 回答。
  // 卡片在 aboutToAppear 按 difficulty 自行洗牌, 这里不注入棋盘。
  // 历史会话的 legacy 工具名 huarongdao 由分发层兼容路由到这里。
  private async handleNumberPuzzle(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult> {
    toolCall.toolId = NUMBER_PUZZLE_TOOL_ID
    if (toolCall.displayName.trim() === '') {
      toolCall.displayName = '数字华容道'
    }
    toolCall.sourceType = ToolSourceType.BUILTIN
    if (toolCall.sourceLabel.trim() === '') {
      toolCall.sourceLabel = '内置工具'
    }
    toolCall.permissionLevel = ToolPermissionLevel.READ

    // 立即设置 pending 状态, 让卡片立即出现
    toolCall.approvalState = 'pending'

    let answerJson: string | null = null
    try {
      answerJson = await new Promise<string | null>((resolve) => {
        const existing = this.pendingAnswers.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(null)
          this.pendingAnswers.delete(toolCall.id)
        }
        const snapshot = this.buildAskUserSnapshot(toolCall, context)
        snapshot.kind = PendingToolInteractionKind.ASK_USER
        snapshot.toolId = NUMBER_PUZZLE_TOOL_ID
        this.pendingAnswers.set(toolCall.id, new PendingToolAnswerRuntime(snapshot, resolve))
        this.publishPendingInteractionChanged()
      })
    } catch (error) {
      console.error('ToolExecutionService', `number_puzzle answer callback failed: ${JSON.stringify(error)}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `number_puzzle 失败: ${JSON.stringify(error)}`, cancelled: true }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'number_puzzle cancelled by external stop')
      toolCall.approvalState = 'denied'
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    if (answerJson === null) {
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ cancelled: true, error: '小朋友未完成该谜题' }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    toolCall.approvalState = 'answered'
    toolCall.approvalReason = answerJson
    console.info('ToolExecutionService', `number_puzzle answered: ${toolCall.id}`)
    this.recordStarEvent('number_puzzle', toolCall, context, answerJson)
    return new ToolResult(
      toolCall.id,
      answerJson,
      false,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  // maze 特殊路径: 与 number_puzzle 类似, 挂起等待 MazeCard 回答。
  // 迷宫生成在后台完成并注入 toolCall.arguments (cells 网格 + 起点终点 + 收藏星)。
  private async handleMaze(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult> {
    toolCall.toolId = MAZE_TOOL_ID
    if (toolCall.displayName.trim() === '') {
      toolCall.displayName = '走迷宫'
    }
    toolCall.sourceType = ToolSourceType.BUILTIN
    if (toolCall.sourceLabel.trim() === '') {
      toolCall.sourceLabel = '内置工具'
    }
    toolCall.permissionLevel = ToolPermissionLevel.READ

    // 1. 立即设置 pending 状态, 让卡片立即出现
    toolCall.approvalState = 'pending'

    // 2. 后台生成迷宫并注入到 toolCall.arguments
    try {
      const parsed = JSON.parse(toolCall.arguments) as Record<string, Object>
      const difficulty = (parsed['difficulty'] as number) ?? 1
      const clampedDifficulty = Math.max(1, Math.min(3, difficulty))

      console.info('ToolExecutionService',
        `maze generation start: difficulty=${clampedDifficulty}`)

      const maze = generateMaze(
        clampedDifficulty === 1 ? 4 : (clampedDifficulty === 2 ? 6 : 8),
        clampedDifficulty === 1 ? 4 : (clampedDifficulty === 2 ? 6 : 8),
        2
      )

      // 序列化 cells(供 MazeCard 在 aboutToAppear 还原)
      parsed['cells'] = maze.cells as Object
      parsed['rows'] = maze.rows as Object
      parsed['cols'] = maze.cols as Object
      parsed['stars_total'] = maze.starsTotal as Object
      parsed['difficulty'] = clampedDifficulty as Object
      parsed['grid_size'] = (clampedDifficulty === 1 ? '4×4' : (clampedDifficulty === 2 ? '6×6' : '8×8')) as Object
      toolCall.arguments = JSON.stringify(parsed)

      console.info('ToolExecutionService',
        `maze generated: rows=${maze.rows}, cols=${maze.cols}, stars=${maze.starsTotal}`)
    } catch (error) {
      console.error('ToolExecutionService', `maze generation exception: ${JSON.stringify(error)}`)
    }

    let answerJson: string | null = null
    try {
      answerJson = await new Promise<string | null>((resolve) => {
        const existing = this.pendingAnswers.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(null)
          this.pendingAnswers.delete(toolCall.id)
        }
        const snapshot = this.buildAskUserSnapshot(toolCall, context)
        snapshot.kind = PendingToolInteractionKind.ASK_USER
        snapshot.toolId = MAZE_TOOL_ID
        this.pendingAnswers.set(toolCall.id, new PendingToolAnswerRuntime(snapshot, resolve))
        this.publishPendingInteractionChanged()
      })
    } catch (error) {
      console.error('ToolExecutionService', `maze answer callback failed: ${JSON.stringify(error)}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `maze 失败: ${JSON.stringify(error)}`, cancelled: true }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'maze cancelled by external stop')
      toolCall.approvalState = 'denied'
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    if (answerJson === null) {
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ cancelled: true, error: '小朋友未完成该迷宫' }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    toolCall.approvalState = 'answered'
    toolCall.approvalReason = answerJson
    console.info('ToolExecutionService', `maze answered: ${toolCall.id}`)
    this.recordStarEvent('maze', toolCall, context, answerJson)
    return new ToolResult(
      toolCall.id,
      answerJson,
      false,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  // sudoku 特殊路径: 与 maze 类似, 挂起等待 SudokuCard 回答。
  // 数独盘面在后台生成并注入 toolCall.arguments (givens / solution / size / boxRows / boxCols)。
  private async handleSudoku(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult> {
    toolCall.toolId = SUDOKU_TOOL_ID
    if (toolCall.displayName.trim() === '') {
      toolCall.displayName = '数独'
    }
    toolCall.sourceType = ToolSourceType.BUILTIN
    if (toolCall.sourceLabel.trim() === '') {
      toolCall.sourceLabel = '内置工具'
    }
    toolCall.permissionLevel = ToolPermissionLevel.READ

    // 1. 立即设置 pending 状态, 让卡片立即出现 (卡片先显示「生成中」占位)
    toolCall.approvalState = 'pending'

    // 2. 后台生成数独并注入到 toolCall.arguments
    try {
      const parsed = JSON.parse(toolCall.arguments) as Record<string, Object>
      const difficulty = (parsed['difficulty'] as number) ?? 1
      const clampedDifficulty = Math.max(1, Math.min(5, difficulty))

      console.info('ToolExecutionService',
        `sudoku generation start: difficulty=${clampedDifficulty}`)

      const board = generateSudoku(clampedDifficulty)
      const cfg = getDifficultyConfig(clampedDifficulty)

      // 序列化盘面 (供 SudokuCard 在 aboutToAppear 还原)
      parsed['size'] = board.size as Object
      parsed['box_rows'] = board.boxRows as Object
      parsed['box_cols'] = board.boxCols as Object
      parsed['difficulty'] = clampedDifficulty as Object
      parsed['grid_size'] = `${cfg.size}×${cfg.size}` as Object
      parsed['givens'] = board.givens as Object
      parsed['solution'] = board.solution as Object
      toolCall.arguments = JSON.stringify(parsed)

      console.info('ToolExecutionService',
        `sudoku generated: size=${board.size}, givens=${board.givens.filter(v => v !== 0).length}`)
    } catch (error) {
      console.error('ToolExecutionService', `sudoku generation exception: ${JSON.stringify(error)}`)
    }

    let answerJson: string | null = null
    try {
      answerJson = await new Promise<string | null>((resolve) => {
        const existing = this.pendingAnswers.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(null)
          this.pendingAnswers.delete(toolCall.id)
        }
        const snapshot = this.buildAskUserSnapshot(toolCall, context)
        snapshot.kind = PendingToolInteractionKind.ASK_USER
        snapshot.toolId = SUDOKU_TOOL_ID
        this.pendingAnswers.set(toolCall.id, new PendingToolAnswerRuntime(snapshot, resolve))
        this.publishPendingInteractionChanged()
      })
    } catch (error) {
      console.error('ToolExecutionService', `sudoku answer callback failed: ${JSON.stringify(error)}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `sudoku 失败: ${JSON.stringify(error)}`, cancelled: true }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'sudoku cancelled by external stop')
      toolCall.approvalState = 'denied'
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    if (answerJson === null) {
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ cancelled: true, error: '小朋友未完成该数独' }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    toolCall.approvalState = 'answered'
    toolCall.approvalReason = answerJson
    console.info('ToolExecutionService', `sudoku answered: ${toolCall.id}`)
    this.recordStarEvent('sudoku', toolCall, context, answerJson)
    return new ToolResult(
      toolCall.id,
      answerJson,
      false,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  // categorization 特殊路径: 与 math_quiz 类似, 挂起等待 CategorizationCard 回答。
  private async handleCategorization(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult> {
    toolCall.toolId = CATEGORIZATION_TOOL_ID
    if (toolCall.displayName.trim() === '') {
      toolCall.displayName = '分类小管家'
    }
    toolCall.sourceType = ToolSourceType.BUILTIN
    if (toolCall.sourceLabel.trim() === '') {
      toolCall.sourceLabel = '内置工具'
    }
    toolCall.permissionLevel = ToolPermissionLevel.READ

    // 预校验: AI 偶发会发出「某桶 0 件物品」等非法分布, 若进入 pending 态,
    // 卡片只渲染 ErrorPlaceholder 且永不调 onAnswer → handleCategorization 的 Promise
    // 永不 resolve → 会话卡死。这里提前用纯函数校验, 失败直接回 error ToolResult,
    // AI 收到错误后可据 message 自我修正并重新调用 categorization。
    const validation = validateAndNormalizeCategorization(toolCall.arguments)
    if (!validation.ok) {
      console.warn('ToolExecutionService', `categorization validation failed: ${validation.error}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({
          error: 'validation_failed',
          message: validation.error,
          should_retry: true
        }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    toolCall.approvalState = 'pending'

    let answerJson: string | null = null
    try {
      answerJson = await new Promise<string | null>((resolve) => {
        const existing = this.pendingAnswers.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(null)
          this.pendingAnswers.delete(toolCall.id)
        }
        const snapshot = this.buildAskUserSnapshot(toolCall, context)
        snapshot.kind = PendingToolInteractionKind.ASK_USER
        snapshot.toolId = CATEGORIZATION_TOOL_ID
        this.pendingAnswers.set(toolCall.id, new PendingToolAnswerRuntime(snapshot, resolve))
        this.publishPendingInteractionChanged()
      })
    } catch (error) {
      console.error('ToolExecutionService', `categorization answer callback failed: ${JSON.stringify(error)}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `categorization 失败: ${JSON.stringify(error)}`, cancelled: true }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'categorization cancelled by external stop')
      toolCall.approvalState = 'denied'
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    if (answerJson === null) {
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ cancelled: true, error: '小朋友未完成分类' }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    toolCall.approvalState = 'answered'
    toolCall.approvalReason = answerJson
    console.info('ToolExecutionService', `categorization answered: ${toolCall.id}`)
    this.recordStarEvent('categorization', toolCall, context, answerJson)
    return new ToolResult(
      toolCall.id,
      answerJson,
      false,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  // handwriting_practice 特殊路径: 与 number_puzzle 类似, 挂起等待 HandwritingCard 回答。
  // 孩子完成书写后调用 AI vision 评价, 将评价文字作为 ToolResult 返回。
  private async handleHandwriting(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult> {
    toolCall.toolId = HANDWRITING_PRACTICE_TOOL_ID
    if (toolCall.displayName.trim() === '') {
      toolCall.displayName = '学写字'
    }
    toolCall.sourceType = ToolSourceType.BUILTIN
    if (toolCall.sourceLabel.trim() === '') {
      toolCall.sourceLabel = '内置工具'
    }
    toolCall.permissionLevel = ToolPermissionLevel.READ

    toolCall.approvalState = 'pending'

    let answerJson: string | null = null
    try {
      answerJson = await new Promise<string | null>((resolve) => {
        const existing = this.pendingAnswers.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(null)
          this.pendingAnswers.delete(toolCall.id)
        }
        const snapshot = this.buildAskUserSnapshot(toolCall, context)
        snapshot.kind = PendingToolInteractionKind.ASK_USER
        snapshot.toolId = HANDWRITING_PRACTICE_TOOL_ID
        this.pendingAnswers.set(toolCall.id, new PendingToolAnswerRuntime(snapshot, resolve))
        this.publishPendingInteractionChanged()
      })
    } catch (error) {
      console.error('ToolExecutionService', `handwriting_practice answer callback failed: ${JSON.stringify(error)}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `handwriting_practice 失败: ${JSON.stringify(error)}`, cancelled: true }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'handwriting_practice cancelled by external stop')
      toolCall.approvalState = 'denied'
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    if (answerJson === null) {
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ cancelled: true, error: '小朋友未完成书写练习' }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    // 解析结果生成反馈
    let evalText: string = ''
    try {
      const answer = JSON.parse(answerJson) as Record<string, Object>
      const handwritingBase64 = (answer['handwriting_base64'] as string) ?? ''
      const character = (answer['character'] as string) ?? '字'
      const charType = (answer['type'] as string) ?? 'letter'
      const completed = (answer['completed'] as boolean) ?? true

      if (!completed || handwritingBase64 === '') {
        // 放弃: 返回简单提示
        evalText = `小朋友这次没有完成${character}的书写，没关系，下次再来！`
      } else {
        // 调用 AI vision 评价
        evalText = await this.evaluateHandwriting(handwritingBase64, character, charType)
      }
    } catch (error) {
      console.error('ToolExecutionService', `Failed to evaluate handwriting: ${JSON.stringify(error)}`)
      evalText = '写得真棒！继续加油！'
    }

    const resultContent = JSON.stringify({ evaluation: evalText })
    toolCall.approvalState = 'answered'
    toolCall.approvalReason = answerJson
    console.info('ToolExecutionService', `handwriting_practice answered: ${toolCall.id}`)
    this.recordStarEvent('handwriting_practice', toolCall, context, answerJson)
    return new ToolResult(
      toolCall.id,
      resultContent,
      false,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  // vertical_math 特殊路径: 与 categorization 类似, 挂起等待 VerticalMathCard 回答。
  // 孩子走完所有步骤后由卡片 onAnswer 回传 {completed, operation, operand_a, operand_b, result, remainder, step_count} JSON。
  // 注意: 本期不接入星星奖励系统 (spec §2.1), 不调用 recordStarEvent, 避免 StarEventModels.ets 联合类型扩散。
  private async handleVerticalMath(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult> {
    toolCall.toolId = VERTICAL_MATH_TOOL_ID
    if (toolCall.displayName.trim() === '') {
      toolCall.displayName = '小小数学家'
    }
    toolCall.sourceType = ToolSourceType.BUILTIN
    if (toolCall.sourceLabel.trim() === '') {
      toolCall.sourceLabel = '内置工具'
    }
    toolCall.permissionLevel = ToolPermissionLevel.READ

    toolCall.approvalState = 'pending'

    let answerJson: string | null = null
    try {
      answerJson = await new Promise<string | null>((resolve) => {
        const existing = this.pendingAnswers.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(null)
          this.pendingAnswers.delete(toolCall.id)
        }
        const snapshot = this.buildAskUserSnapshot(toolCall, context)
        snapshot.kind = PendingToolInteractionKind.ASK_USER
        snapshot.toolId = VERTICAL_MATH_TOOL_ID
        this.pendingAnswers.set(toolCall.id, new PendingToolAnswerRuntime(snapshot, resolve))
        this.publishPendingInteractionChanged()
      })
    } catch (error) {
      console.error('ToolExecutionService', `vertical_math answer callback failed: ${JSON.stringify(error)}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `vertical_math 失败: ${JSON.stringify(error)}`, cancelled: true }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'vertical_math cancelled by external stop')
      toolCall.approvalState = 'denied'
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    if (answerJson === null) {
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ cancelled: true, error: '小朋友未完成竖式计算' }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    toolCall.approvalState = 'answered'
    toolCall.approvalReason = answerJson
    console.info('ToolExecutionService', `vertical_math answered: ${toolCall.id}`)
    // 注: 不调用 recordStarEvent — 本期不接入星星奖励系统。
    return new ToolResult(
      toolCall.id,
      answerJson,
      false,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  // 调用 AI vision 模型评价书写
  private async evaluateHandwriting(
    base64Image: string,
    character: string,
    charType: string
  ): Promise<string> {
    try {
      // 遍历所有启用的 provider，找到第一个支持 vision 的模型
      const providerViewModel = getProviderViewModel()
      const providers: ModelProvider[] = await providerViewModel.loadProviders()

      let chosenProvider: ModelProvider | null = null
      let chosenModelId: string = ''

      for (let pi = 0; pi < providers.length; pi++) {
        const provider = providers[pi]
        if (provider === null) {
          continue
        }
        const models = provider.models
        for (let mi = 0; mi < models.length; mi++) {
          const model = models[mi]
          if (model === null) {
            continue
          }
          if (!model.isEnabled) {
            continue
          }
          if (!modelSupportsVision(model.id)) {
            continue
          }
          chosenProvider = provider
          chosenModelId = model.id
          break
        }
        if (chosenProvider !== null) {
          break
        }
      }

      if (chosenProvider === null || chosenModelId === '') {
        console.info('ToolExecutionService', 'no provider find')
        return '写得真不错！继续练习会越来越好的！'
      }

      const effectiveApiKey: string = getEffectiveApiKey(chosenProvider.id, chosenProvider.apiKey)
      if (effectiveApiKey === '') {
        return '写得很好，下次一定会更棒！'
      }

      // 构建 API 配置
      const apiConfig: AIApiConfig = {
        providerId: chosenProvider.id,
        providerType: chosenProvider.type,
        apiStyle: chosenProvider.apiStyle,
        apiKey: effectiveApiKey,
        baseUrl: chosenProvider.baseUrl
      }
      // 构造评价请求消息
      const typeLabel: string = charType === 'letter' ? '英文字母' : charType === 'number' ? '数字' : '汉字'
      const prompt: string = `请用鼓励的语气评价小朋友写的"${character}"（${typeLabel}）。

注意观察：
- 笔画方向是否正确
- 字形大小是否合适
- 整体是否端正

请给出1-2句鼓励性反馈，语气要温暖，像幼儿园老师对小朋友说话。用中文回复。`

      const attachment: MessageAttachment = new MessageAttachment(
        'handwriting_eval',
        AttachmentType.IMAGE,
        'handwriting.jpg',
        '',
        'image/jpeg',
        0
      )
      attachment.base64Data = base64Image

      const msg: RequestMessage = new RequestMessage('user', prompt)
      console.info('ToolExecutionService', `prompt, ${prompt}`)
      msg.attachments = [attachment]

      const apiResult = await ServiceRegistry.aiApi().sendChatRequest(
        apiConfig,
        [msg],
        chosenModelId
      )

      if (apiResult.success && apiResult.content.trim() !== '') {
        return apiResult.content.trim()
      }
      return '写得真好，继续练习会越来越棒！'
    } catch (error) {
      console.error('ToolExecutionService', `evaluateHandwriting failed: ${JSON.stringify(error)}`)
      return '写得很认真哦，下次一定会更好的！'
    }
  }

  // 执行单个工具调用
  async executeToolCall(
    toolCall: ToolCall,
    context: ToolExecutionContext = new ToolExecutionContext()
  ): Promise<ToolResult> {
    console.info('ToolExecutionService', `Executing tool call: ${toolCall.functionName} (${toolCall.id})`)

    // 检查是否已取消
    if (this.isCancelled()) {
      console.info('ToolExecutionService', `Tool execution cancelled: ${toolCall.functionName}`)
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    const normalizedFunctionName = this.normalizeFunctionName(toolCall.functionName)

    // === ask_user 特殊路径 ===
    // 人机交互工具, 不走通用 executor 和 write 审批 sheet, 由 AskUserCard 直接收集答案。
    if (isAskUserFunctionName(normalizedFunctionName)) {
      return await this.handleAskUser(toolCall, context)
    }

    // === math_quiz 特殊路径 ===
    // 数学游戏互动工具, 由 MathQuizCard 收集小朋友的答案。
    if (isMathQuizFunctionName(normalizedFunctionName)) {
      return await this.handleMathQuiz(toolCall, context)
    }

    // === english_quiz 特殊路径 ===
    // 英语看图说话互动工具, 由 EnglishQuizCard 收集小朋友的答案。
    if (isEnglishQuizFunctionName(normalizedFunctionName)) {
      return await this.handleEnglishQuiz(toolCall, context)
    }

    // === number_puzzle 特殊路径 ===
    // 数字华容道游戏互动工具, 由 NumberPuzzleCard 收集小朋友的答案。
    // isHuarongdaoFunctionName 是历史会话的 legacy 消息分发臂, 保留兼容。
    if (isNumberPuzzleFunctionName(normalizedFunctionName) ||
      isHuarongdaoFunctionName(normalizedFunctionName)) {
      return await this.handleNumberPuzzle(toolCall, context)
    }

    // === categorization 特殊路径 ===
    // 分类小管家互动工具, 由 CategorizationCard 收集小朋友的分类结果。
    if (isCategorizationFunctionName(normalizedFunctionName)) {
      return await this.handleCategorization(toolCall, context)
    }

    // === handwriting_practice 特殊路径 ===
    // 学写字互动工具, 由 HandwritingCard 收集小朋友的书写, 然后调用 AI vision 评价。
    if (isHandwritingPracticeFunctionName(normalizedFunctionName)) {
      return await this.handleHandwriting(toolCall, context)
    }

    // === vertical_math 特殊路径 ===
    // 竖式数学互动工具, 由 VerticalMathCard 收集孩子的计算结果。
    if (isVerticalMathFunctionName(normalizedFunctionName)) {
      return await this.handleVerticalMath(toolCall, context)
    }

    // === maze 特殊路径 ===
    // 走迷宫互动工具, 由 MazeCard 收集小朋友的移动 / 完成结果。
    if (isMazeFunctionName(normalizedFunctionName)) {
      return await this.handleMaze(toolCall, context)
    }

    // === sudoku 特殊路径 ===
    // 数独互动工具, 由 SudokuCard 收集孩子的填数 / 完成结果。
    if (isSudokuFunctionName(normalizedFunctionName)) {
      return await this.handleSudoku(toolCall, context)
    }

    // === picture_vocab 特殊路径 ===
    // 看图识词互动工具, 由 PictureVocabCard 收集小朋友的选项。
    if (isPictureVocabFunctionName(normalizedFunctionName)) {
      return await this.handlePictureVocab(toolCall, context)
    }

    // === listening_quiz 特殊路径 ===
    // 听力题互动工具, 由 ListeningQuizCard 收集小朋友的选项。
    if (isListeningQuizFunctionName(normalizedFunctionName)) {
      return await this.handleListeningQuiz(toolCall, context)
    }

    // 通过函数名获取工具 ID
    const toolId = this.resolveToolId(normalizedFunctionName)
    if (toolId === undefined) {
      const displayName = normalizedFunctionName !== '' ? normalizedFunctionName : 'null'
      console.error('ToolExecutionService', `Tool not found: ${displayName}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `未知工具: ${displayName}` }),
        true,
        displayName,
        toolCall.sourceLabel
      )
    }

    const registeredTool = this.registry.getTool(toolId)
    if (registeredTool === undefined) {
      console.error('ToolExecutionService', `Registered tool not found: ${toolId}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `工具未注册: ${toolId}` }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    toolCall.toolId = registeredTool.id
    toolCall.displayName = registeredTool.config.name
    toolCall.sourceType = registeredTool.config.sourceType
    toolCall.sourceLabel = registeredTool.config.sourceLabel
    toolCall.permissionLevel = registeredTool.config.permissionLevel
    toolCall.approvalPolicy = registeredTool.config.approvalPolicy

    const approved = await this.requestApprovalIfNeeded(toolCall, registeredTool, context)
    if (!approved) {
      const denialMessage = toolCall.approvalReason.trim() !== '' ? toolCall.approvalReason : '用户拒绝了工具调用'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: denialMessage, cancelled: true }),
        true,
        registeredTool.config.name,
        registeredTool.config.sourceLabel
      )
    }

    // 获取工具执行器
    const executor = this.registry.getToolExecutor(toolId)
    if (executor === undefined) {
      console.error('ToolExecutionService', `Executor not found for tool: ${toolId}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `工具执行器未找到: ${toolId}` }),
        true,
        registeredTool.config.name,
        registeredTool.config.sourceLabel
      )
    }

    try {
      // 执行工具
      const startTime = Date.now()
      const result = await executor.execute(toolCall.arguments)

      // 执行完成后再次检查是否取消（避免返回已取消的结果）
      if (this.isCancelled()) {
        console.info('ToolExecutionService', `Tool execution cancelled after completion: ${toolCall.functionName}`)
        return this.buildCancelledResult(toolCall, registeredTool.config.name, registeredTool.config.sourceLabel)
      }

      const duration = Date.now() - startTime
      console.info('ToolExecutionService', `Tool ${toolCall.functionName} completed in ${duration}ms`)

      // grant_star 后置星星记录
      // executor 只返回 JSON 结果, 真正的 StarRewardService.recordEvent 需要真实的 toolCall.id 和 sessionId
      if (isGrantStarFunctionName(normalizedFunctionName)) {
        this.recordStarEvent('chat_correct', toolCall, context, result)
      }

      let isError = false
      try {
        const parsed = JSON.parse(result) as Record<string, Object>
        isError = parsed.isError === true || parsed.error !== undefined
      } catch (_error) {}

      return new ToolResult(
        toolCall.id,
        result,
        isError,
        registeredTool.config.name,
        registeredTool.config.sourceLabel
      )
    } catch (error) {
      console.error('ToolExecutionService', `Tool execution error: ${JSON.stringify(error)}`)
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `工具执行失败: ${JSON.stringify(error)}` }),
        true,
        registeredTool.config.name,
        registeredTool.config.sourceLabel
      )
    }
  }

  // 批量执行工具调用（串行，避免多个确认框并发弹出）
  async executeToolCalls(
    toolCalls: ToolCall[],
    context: ToolExecutionContext = new ToolExecutionContext()
  ): Promise<ToolResult[]> {
    console.info('ToolExecutionService', `Executing ${toolCalls.length} tool calls`)

    // 检查是否已取消
    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'Tool execution cancelled before batch execution')
      return toolCalls.map(tc => new ToolResult(
        tc.id,
        JSON.stringify({ error: '工具执行已取消', cancelled: true }),
        true,
        tc.displayName,
        tc.sourceLabel
      ))
    }

    const results: ToolResult[] = []
    for (let i = 0; i < toolCalls.length; i++) {
      results.push(await this.executeToolCall(toolCalls[i], context))
    }
    return results
  }

  // 检查工具是否可用
  isToolAvailable(functionName: string): boolean {
    const normalizedFunctionName = this.normalizeFunctionName(functionName)
    const toolId = this.resolveToolId(normalizedFunctionName)
    return toolId !== undefined
  }
}

// 导出单例实例获取方法
export function getToolExecutionService(): ToolExecutionService {
  return ToolExecutionService.getInstance()
}
