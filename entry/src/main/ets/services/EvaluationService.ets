/**
 * 评估老师后台服务
 *
 * 职责:
 * - 每日 23:00 WorkScheduler 触发 (or appStart 补跑 / manual 按钮 / setInterval 降级)
 * - 收集近 7 天周级趋势 (skillVelocities / recurringMistakes / topicInterests / attention) +
 *   今日 sessions 摘要 + child profile
 * - 调 LLM (EVALUATOR_SYSTEM_PROMPT) 生成 4 维度教学风格调整
 * - 持久化到 teaching_style_adjustments 表 (14 天滚动)
 * - 写后**同步**触发 LessonPlanningService.triggerPlanningForToday (评估→备课 串行)
 * - 失败容忍: 失败写 failed 行 + 增 evaluator_fail_count_YYYYMMDD, 不阻塞备课 (备课用 fallback tsa)
 *
 * 9 步 pipeline (对比备课 12 步, 少 4 步: 无 prefetchImages):
 *   1. 全局开关
 *   2. 幂等检查 (12h 内已 done → 跳过; failed 距离上次更新已过 30min → 重试; 同日失败 ≥ 3 → 跳过)
 *   3. 写 running 行
 *   4. 准备输入: weeklyTrend (4 指标) + child profile + 今日 sessions 摘要
 *   5. 调用 LLM (EVALUATOR_SYSTEM_PROMPT + userInput)
 *   6. 解析 + 校验 LLM 输出 (4 维度白名单 + JSON 合法性)
 *   7. 持久化 (status='done' 或 'failed')
 *   8. 成功 → 重置失败计数 + pulse TEACHING_STYLE_ADJUSTMENT_REFRESH_TICK
 *        + **同步**触发 LessonPlanningService.triggerPlanningForToday
 *   9. 异常兜底: 顶层 catch 写 failed 行
 */

import { Context } from '@kit.AbilityKit'
import { getAIApiService, AIApiService, AIApiConfig, RequestMessage } from './AIApiService'
import { getDefaultModelService, DefaultModelService } from './DefaultModelService'
import { getProviderViewModel, ProviderViewModel } from '../viewmodels/ProviderViewModel'
import { getDatabaseService, DatabaseService } from './DatabaseService'
import { getPreferencesService, PreferencesService, PreferenceKeys } from './PreferencesService'
import { getChildProfileService, ChildProfileService, ChildKnowledgeProfile, SkillDimension } from './ChildProfileService'
import { getWeeklyTrendService, WeeklyTrendService } from './WeeklyTrendService'
import { getTeachingStyleAdjustmentService, TeachingStyleAdjustmentService } from './TeachingStyleAdjustmentService'
import { getLessonPlanningService, LessonPlanningService } from './LessonPlanningService'
import { ModelInfo, ModelProvider, ModelRole, ReasoningLevel, ChatMessage, ChatSession } from '../models/ChatModels'
import { ReasoningRequestStrategy } from './registry/CompatibilityResolver'
import { getEffectiveApiKey } from '../config/PresetProviders'
import { getEffectiveCapabilities } from '../utils/ModelCapabilityDeriver'
import {
  TeachingStyleAdjustment,
  TeachingStyleAdjustmentSummary,
  TeachingStyleAdjustmentStatus,
  WeeklyTrend,
  parseWeeklyTrend,
  hydrateTeachingStyleAdjustmentFromLlm,
  EVALUATION_TRIGGER_HOUR,
  EVALUATION_TRIGGER_WINDOW_MINUTES
} from '../models/TeachingReflectionModels'
import { formatLocalYMD, formatLocalYMDCompact } from '../models/LessonPlanModels'
import {
  EVALUATOR_SYSTEM_PROMPT,
  cleanEvaluatorJsonOutput,
  isValidEvaluatorJson
} from '../utils/TeachingStyleAdjustmentPromptUtils'
import {
  PlannerSessionSummary,
  summarizeSessionForPlanner
} from '../utils/SessionSummaryUtils'
import { setAppUiStateValue } from '../state/AppUiState'
import { AppStorageKeys } from '../config/AppStorageKeys'

/** 同日评估失败上限 */
const MAX_FAILS_PER_DAY: number = 3

/** failed/running 进入 retry 模式的最小更新间隔 (防止紧循环) */
const RETRY_MIN_INTERVAL_MS: number = 30 * 60 * 1000

/** 评估老师 LLM 调用最大输出 token*/
const EVALUATOR_MAX_TOKENS: number = 4096

/** 评估老师 LLM 调用温度 (低温度,稳定输出) */
const EVALUATOR_TEMPERATURE: number = 0.3

/** 默认助手 ID */
const DEFAULT_ASSISTANT_ID_VALUE: string = 'default'

/** 触发来源 (用于日志/调试) */
type EvaluatorTriggerSource = 'workScheduler' | 'appStart' | 'manual' | 'intervalCheck'

/** 当前内部状态机 */
type EvaluatorState = 'IDLE' | 'RUNNING'

/** 评估老师 LLM 调用结果 (ArkTS 严格模式禁止内联对象类型) */
class EvaluatorLlmResult {
  success: boolean = false
  content: string = ''
  errorMessage: string = ''
  providerId: string = ''
  modelId: string = ''
  modelName: string = ''
}

/** 评估老师输入侧的 child skill 快照 */
class EvaluatorSkillSnapshot {
  key: string = ''
  label: string = ''
  level: number = 0
  lastAssessed: number = 0
  notes: string = ''
}

class EvaluatorChildProfileSnapshot {
  childName: string = ''
  ageYears: number = 0
  overallNote: string = ''
  sessionCount: number = 0
  weakSkills: string[] = []
  strongSkills: string[] = []
  skills: EvaluatorSkillSnapshot[] = []
}

export class EvaluationService {
  private static instance: EvaluationService | null = null
  private aiApiService: AIApiService
  private defaultModelService: DefaultModelService
  private providerViewModel: ProviderViewModel
  private databaseService: DatabaseService
  private preferencesService: PreferencesService
  private childProfileService: ChildProfileService
  private weeklyTrendService: WeeklyTrendService
  private teachingStyleAdjustmentService: TeachingStyleAdjustmentService
  private lessonPlanningService: LessonPlanningService

  private context: Context | null = null
  private inFlight: boolean = false
  private runningPromise: Promise<void> | null = null
  private intervalCheckId: number = -1

  private constructor() {
    this.aiApiService = getAIApiService()
    this.defaultModelService = getDefaultModelService()
    this.providerViewModel = getProviderViewModel()
    this.databaseService = getDatabaseService()
    this.preferencesService = getPreferencesService()
    this.childProfileService = getChildProfileService()
    this.weeklyTrendService = getWeeklyTrendService()
    this.teachingStyleAdjustmentService = getTeachingStyleAdjustmentService()
    this.lessonPlanningService = getLessonPlanningService()
  }

  static getInstance(): EvaluationService {
    if (EvaluationService.instance === null) {
      EvaluationService.instance = new EvaluationService()
    }
    return EvaluationService.instance
  }

  // ============================================================
  // 生命周期
  // ============================================================

  /**
   * 初始化: 保存 context + 启动时尝试补跑一次今日评估
   *
   * - 不阻塞调用方
   * - 启动补跑: 若今日无 tsa 行 或 tsa 已 failed, 触发一次
   * - 启动 setInterval 降级检查 (WorkScheduler 不可用时使用)
   */
  initialize(context: Context): void {
    this.context = context
    void this.onInitialized()
  }

  private async onInitialized(): Promise<void> {
    try {
      // 启动补跑: fire-and-forget
      await this.triggerEvaluationForToday(false, 'appStart')
    } catch (error) {
      console.error('EvaluationService', `onInitialized error: ${JSON.stringify(error)}`)
    }
    // 启动 setInterval 降级检查 (每分钟一次, 比对 evaluator_last_run_date_YYYYMMDD)
    this.startIntervalCheck()
  }

  /**
   * 启动 setInterval 降级 (WorkScheduler 不可用时使用)。
   * - 每 60s 检查一次
   * - 当日 21:00~21:30 之间首次发现 evaluator_last_run_date !== 今日 → 触发评估
   * - 21:30 之后即使没跑也不再补 (避免深夜噪声)
   */
  private startIntervalCheck(): void {
    if (this.intervalCheckId !== -1) {
      return
    }
    this.intervalCheckId = setInterval(() => {
      this.tryIntervalTrigger()
    }, 60 * 1000)
  }

  /**
   * 停止 setInterval 降级 (用于关闭/退出)。
   */
  stopIntervalCheck(): void {
    if (this.intervalCheckId !== -1) {
      clearInterval(this.intervalCheckId)
      this.intervalCheckId = -1
    }
  }

  private async tryIntervalTrigger(): Promise<void> {
    try {
      const now = new Date()
      const hour = now.getHours()
      // 只在 EVALUATION_TRIGGER_HOUR:00 ~ :30 之间尝试补跑（与 TeachingReflectionModels 中的常量同步）
      if (hour !== EVALUATION_TRIGGER_HOUR) {
        return
      }
      const minute = now.getMinutes()
      if (minute > EVALUATION_TRIGGER_WINDOW_MINUTES) {
        return
      }
      const todayYMDCompact = formatLocalYMDCompact(now)
      const lastRunDate = await this.preferencesService.getString(
        PreferenceKeys.EVALUATOR_LAST_RUN_DATE, ''
      )
      if (lastRunDate === todayYMDCompact) {
        return  // 今日已跑过
      }
      console.info('EvaluationService', `intervalCheck triggering evaluation for ${todayYMDCompact}`)
      await this.triggerEvaluationForToday(false, 'intervalCheck')
    } catch (e) {
      console.warn('EvaluationService', `tryIntervalTrigger error: ${JSON.stringify(e)}`)
    }
  }

  // ============================================================
  // 公共 API: 触发入口
  // ============================================================

  /**
   * 主动触发一次评估 (WorkScheduler / appStart 补跑 / 手动按钮 / setInterval 降级)。
   *
   * - force=true: 跳过幂等检查, 强制重跑
   * - 默认 false: 今日已有 done → 跳过; failed 距离上次更新已过 30min → 重试; 同日失败 ≥ 3 → 跳过
   */
  async triggerEvaluationForToday(force: boolean = false, source: EvaluatorTriggerSource = 'manual'): Promise<void> {
    if (this.context === null) {
      console.warn('EvaluationService', 'triggerEvaluationForToday: context not initialized')
      return
    }
    // 防并发: 复用同一 promise
    if (this.runningPromise !== null) {
      console.info('EvaluationService', 'triggerEvaluationForToday: already running, reuse promise')
      return this.runningPromise
    }
    this.runningPromise = this.runEvaluationPipeline(force, source)
    try {
      await this.runningPromise
    } finally {
      this.runningPromise = null
    }
  }

  // ============================================================
  // 公共 API: 读侧
  // ============================================================

  /**
   * 获取当前生效的 tsa (一般给 ChatViewModel 注入 prompt 用)。
   * - asOfYMD: '' = 今天
   * - 返回 null 表示无当前调整
   */
  async getCurrentAdjustment(asOfYMD: string = ''): Promise<TeachingStyleAdjustment | null> {
    return await this.teachingStyleAdjustmentService.getCurrentAdjustment(asOfYMD)
  }

  // ============================================================
  // 内部: 主流程
  // ============================================================

  private async runEvaluationPipeline(force: boolean, source: EvaluatorTriggerSource): Promise<void> {
    if (this.inFlight && !force) {
      console.info('EvaluationService', 'runEvaluationPipeline: in flight, skip')
      return
    }
    this.inFlight = true
    const today = new Date()
    const evaluationDate = formatLocalYMD(today)
    const tsaId = 'tsa_' + formatLocalYMDCompact(today)
    const trendId = 'wt_' + formatLocalYMDCompact(today)

    try {
      // 1. 全局开关
      const enabled = await this.preferencesService.getBoolean(PreferenceKeys.EVALUATOR_ENABLED, true)
      if (!enabled) {
        console.info('EvaluationService', `evaluator disabled by user preference. source=${source}`)
        return
      }

      // 2. 幂等检查（按 status 区分 done vs failed，failed 行需等 30min 重试窗口）
      const existing = await this.databaseService.getCurrentTeachingStyleAdjustment(
        evaluationDate, Date.now()
      )
      if (!force && existing !== null) {
        if (existing.effective_date === evaluationDate) {
          if (existing.status === TeachingStyleAdjustmentStatus.DONE) {
            // 今日已有成功行 → 跳过（避免 23:00 多次重跑）
            console.info('EvaluationService',
              `TSA for ${evaluationDate} already done, skip. source=${source}`)
            return
          }
          // status === 'failed'：检查 30min 重试窗口
          const lastFailedAtMs = await this.getTodayLastFailedAt()
          const elapsedMs = Date.now() - lastFailedAtMs
          if (lastFailedAtMs > 0 && elapsedMs < RETRY_MIN_INTERVAL_MS) {
            console.info('EvaluationService',
              `TSA for ${evaluationDate} failed ${elapsedMs}ms ago, within retry window (${RETRY_MIN_INTERVAL_MS}ms), skip. source=${source}`)
            return
          }
          // 距离上次失败 > 30min 或从未失败过 → 允许重试（受 MAX_FAILS_PER_DAY 限制）
          console.info('EvaluationService',
            `TSA for ${evaluationDate} is '${existing.status}', retrying. source=${source}`)
        }
        // 老 tsa (非今日) → 允许重新评估
      }

      // 3. 检查失败次数
      const failCount = await this.getTodayFailCount()
      if (!force && failCount >= MAX_FAILS_PER_DAY) {
        console.info('EvaluationService',
          `evaluator failed ${failCount} times today, skip. source=${source}`)
        return
      }

      // 4. 计算/补算周级趋势 (12h 幂等)
      let trend: WeeklyTrend | null = null
      try {
        const weekStartYMD = WeeklyTrendService.currentWeekStartYMD(today)
        trend = await this.weeklyTrendService.computeAndStoreWeeklyTrend(weekStartYMD, false)
        if (trend === null) {
          console.warn('EvaluationService', 'weeklyTrend compute returned null, evaluation may be degraded')
        }
      } catch (e) {
        console.error('EvaluationService', `weeklyTrend compute failed: ${JSON.stringify(e)}`)
      }

      // 5. 准备输入: child profile + 今日 sessions
      const profile = await this.childProfileService.getProfile()
      const childSnapshot = this.buildChildProfileSnapshot(profile)

      // 取今日 sessions (与备课同口径)
      const dayStart = this.startOfDay(today).getTime()
      const dayEnd = dayStart + 24 * 60 * 60 * 1000
      const sessions = await this.databaseService.getSessionsByAssistantAndDate(
        DEFAULT_ASSISTANT_ID_VALUE, dayStart, dayEnd
      )
      const summaries: PlannerSessionSummary[] = []
      let messageCount = 0
      for (let i = 0; i < sessions.length; i++) {
        const session: ChatSession = sessions[i]
        const messages: ChatMessage[] = await this.databaseService.getMessages(session.id)
        messageCount += messages.length
        if (messages.length === 0) {
          continue
        }
        summaries.push(summarizeSessionForPlanner(session.id, messages, 600))
      }

      // 6. 构造 LLM 输入 JSON
      const userInput = JSON.stringify({
        weeklyTrend: trend !== null ? serializeTrendForLlm(trend) : null,
        childProfile: childSnapshot,
        todaysSessions: summaries,
        evaluationDate: evaluationDate,
        sessionCount: sessions.length
      })

      // 7. 调用 LLM
      const llmResult = await this.callEvaluatorLLM(userInput)
      if (!llmResult.success) {
        await this.markFailed(tsaId, evaluationDate, trendId, llmResult.errorMessage,
          sessions.length, messageCount)
        return
      }

      // 8. 解析 + 校验 LLM 输出
      const cleaned = cleanEvaluatorJsonOutput(llmResult.content)
      if (cleaned === '' || !isValidEvaluatorJson(cleaned)) {
        // 诊断日志: 捕获清洗后内容 + 原始内容前缀, 用于排查
        const cleanedPreview = cleaned.length > 500
          ? cleaned.substring(0, 500) + `...(+${cleaned.length - 500} chars)`
          : cleaned
        const rawPreview = llmResult.content.length > 500
          ? llmResult.content.substring(0, 500) + `...(+${llmResult.content.length - 500} chars)`
          : llmResult.content
        console.warn('EvaluationService',
          `JSON validation failed. cleanedLen=${cleaned.length}, rawLen=${llmResult.content.length}`)
        console.warn('EvaluationService', `cleaned preview: ${cleanedPreview}`)
        console.warn('EvaluationService', `raw content preview: ${rawPreview}`)
        await this.markFailed(tsaId, evaluationDate, trendId,
          'LLM 输出非合法 JSON', sessions.length, messageCount)
        return
      }
      let parsedRaw: Object
      try {
        parsedRaw = JSON.parse(cleaned) as Object
      } catch (_e) {
        await this.markFailed(tsaId, evaluationDate, trendId,
          'JSON.parse 失败', sessions.length, messageCount)
        return
      }
      const adj = hydrateTeachingStyleAdjustmentFromLlm(
        parsedRaw, evaluationDate, trendId, sessions.length
      )
      if (adj === null) {
        await this.markFailed(tsaId, evaluationDate, trendId,
          'hydrateTeachingStyleAdjustmentFromLlm 失败', sessions.length, messageCount)
        return
      }
      // 补 evaluator 元信息
      adj.evaluatorProviderId = llmResult.providerId
      adj.evaluatorModelId = llmResult.modelId
      adj.evaluatorModelName = llmResult.modelName

      // 9. 持久化 (成功 done 行)
      const saved = await this.teachingStyleAdjustmentService.saveAdjustment(adj)
      if (!saved) {
        await this.markFailed(tsaId, evaluationDate, trendId,
          'teaching_style_adjustments 持久化失败', sessions.length, messageCount)
        return
      }

      // 10. 成功 → 重置失败计数 + 写 last_run_date
      await this.resetTodayFailCount()
      await this.preferencesService.setString(
        PreferenceKeys.EVALUATOR_LAST_RUN_DATE, formatLocalYMDCompact(today)
      )

      // 11. pulse tick (TEACHING_STYLE_ADJUSTMENT_REFRESH_TICK)
      // 已在 saveAdjustment 内部 pulse, 这里只打日志
      console.info('EvaluationService',
        `Evaluation for ${evaluationDate} done. sessions=${sessions.length}, messages=${messageCount}, ` +
        `difficultyTendency=${adj.difficultyTendency}, feedbackTone=${adj.feedbackTone}, ` +
        `weakStrongBalance=${adj.weakStrongBalance}, learningPace=${adj.learningPace}, ` +
        `confidence=${adj.confidence}`)

      // 12. **同步**触发备课 (评估完成 → 立即进入备课链路, 不要再走 5min debounce)
      //     注意: 备课使用刚生成的 tsa 作为 userInput.currentStyleAdjustment
      try {
        await this.lessonPlanningService.triggerPlanningForToday(false, 'workScheduler')
      } catch (e) {
        console.error('EvaluationService',
          `post-evaluation planning trigger failed (non-fatal): ${JSON.stringify(e)}`)
      }
    } catch (error) {
      console.error('EvaluationService', `runEvaluationPipeline error: ${JSON.stringify(error)}`)
      // 顶层 catch: 写一行 failed
      await this.markFailed(tsaId, evaluationDate, trendId,
        `pipeline 异常: ${JSON.stringify(error)}`, 0, 0)
    } finally {
      this.inFlight = false
    }
  }

  // ============================================================
  // 内部: 失败状态写入
  // ============================================================

  private async markFailed(tsaId: string, evaluationDate: string, trendId: string,
    errorMessage: string, sessionCount: number, messageCount: number): Promise<void> {
    // 写一行 tsa (status='failed' 显式标注，便于 30min 后重试窗口判断)
    const adj = new TeachingStyleAdjustment()
    adj.id = tsaId
    adj.effectiveDate = evaluationDate
    adj.expiresAt = Date.now() + 14 * 24 * 60 * 60 * 1000
    adj.sourceWeeklyTrendId = trendId
    adj.sourceSessionCount = sessionCount
    adj.confidence = 0  // 失败 → confidence=0
    adj.status = TeachingStyleAdjustmentStatus.FAILED
    // 4 个 rationale 用 errorMessage 填入 difficultyRationale (供调试)
    adj.difficultyRationale = `[failed] ${errorMessage}`
    adj.feedbackRationale = ''
    adj.balanceRationale = ''
    adj.paceRationale = ''
    // 默认 4 维度 (让 LLM 即使失败也保留默认风格, 不让前端出现 null)
    const saved = await this.teachingStyleAdjustmentService.saveAdjustment(adj)
    if (!saved) {
      console.error('EvaluationService', 'markFailed: save failed')
    }
    // 记录最后一次失败时间戳（幂等检查用）
    await this.setTodayLastFailedAt()
    await this.incrementTodayFailCount()
    console.warn('EvaluationService',
      `Evaluation for ${evaluationDate} failed: ${errorMessage}. sessions=${sessionCount}, messages=${messageCount}`)
  }

  // ============================================================
  // 内部: LLM 调用
  // ============================================================

  private async callEvaluatorLLM(userInput: string): Promise<EvaluatorLlmResult> {
    const evaluatorModel = this.defaultModelService.getModel(ModelRole.CHAT)
    if (!evaluatorModel.isConfigured()) {
      return this.makeLlmError('请先配置默认聊天模型', '', '', '')
    }
    const provider = await this.providerViewModel.getProviderByIdAsync(evaluatorModel.providerId)
    if (provider === null) {
      return this.makeLlmError(`未找到服务商: ${evaluatorModel.providerId}`,
        evaluatorModel.providerId, evaluatorModel.modelId, evaluatorModel.modelName)
    }
    const apiKey = getEffectiveApiKey(provider.id, provider.apiKey)
    if (apiKey === '' && provider.requiresApiKey) {
      return this.makeLlmError(`服务商 ${provider.name} 缺少 API Key`,
        provider.id, evaluatorModel.modelId, evaluatorModel.modelName)
    }

    const apiConfig: AIApiConfig = {
      providerId: provider.id,
      providerType: provider.type,
      apiStyle: provider.apiStyle,
      apiKey: apiKey,
      baseUrl: provider.baseUrl,
      apiPath: provider.apiPath !== '' ? provider.apiPath : undefined,
      openaiTransport: provider.openaiTransport,
      customHeadersJson: provider.customHeadersJson || undefined
    }
    // 评估老师禁用推理 (避免 JSON 输出被 <think> 污染)
    for (let i = 0; i < provider.models.length; i++) {
      if (provider.models[i].id === evaluatorModel.modelId) {
        apiConfig.modelReasoningStrategyOverride = ReasoningRequestStrategy.NONE
        apiConfig.modelSupportsReasoning = getEffectiveCapabilities(provider.models[i]).supportsReasoning
        break
      }
    }

    const messages: RequestMessage[] = [
      new RequestMessage('system', EVALUATOR_SYSTEM_PROMPT),
      new RequestMessage('user', userInput)
    ]

    try {
      const result = await this.aiApiService.sendChatRequest(
        apiConfig,
        messages,
        evaluatorModel.modelId,
        EVALUATOR_TEMPERATURE,
        EVALUATOR_MAX_TOKENS,
        ReasoningLevel.OFF
      )
      if (!result.success) {
        console.warn('EvaluationService',
          `callEvaluatorLLM failed: ${result.errorMessage}, ` +
          `provider=${provider.id}, model=${evaluatorModel.modelId}`)
        return this.makeLlmError(result.errorMessage, provider.id,
          evaluatorModel.modelId, evaluatorModel.modelName)
      }
      // 诊断日志: 捕获 LLM 原始输出元信息, 用于排查 JSON 解析失败
      const usageInfo = result.usage !== null ? result.usage : null
      console.info('EvaluationService',
        `callEvaluatorLLM ok: contentLen=${result.content.length}, ` +
        `reasoningLen=${result.reasoningContent.length}, ` +
        `finishReason=${result.finishReason ?? 'unset'}, ` +
        `promptTokens=${usageInfo !== null ? usageInfo.prompt_tokens : 'null'}, ` +
        `completionTokens=${usageInfo !== null ? usageInfo.completion_tokens : 'null'}, ` +
        `totalTokens=${usageInfo !== null ? usageInfo.total_tokens : 'null'}, ` +
        `provider=${provider.id}, model=${evaluatorModel.modelId}`)
      // 内容前 500 字 (截断, 避免日志爆炸)
      const contentPreview = result.content.length > 500
        ? result.content.substring(0, 500) + `...(+${result.content.length - 500} chars)`
        : result.content
      console.info('EvaluationService', `raw content preview: ${contentPreview}`)
      if (result.reasoningContent.length > 0) {
        const reasoningPreview = result.reasoningContent.length > 300
          ? result.reasoningContent.substring(0, 300) + `...(+${result.reasoningContent.length - 300} chars)`
          : result.reasoningContent
        console.info('EvaluationService', `raw reasoning preview: ${reasoningPreview}`)
      }
      const ok = new EvaluatorLlmResult()
      ok.success = true
      ok.content = result.content
      ok.errorMessage = ''
      ok.providerId = provider.id
      ok.modelId = evaluatorModel.modelId
      ok.modelName = evaluatorModel.modelName
      return ok
    } catch (error) {
      return this.makeLlmError(`LLM 调用异常: ${JSON.stringify(error)}`,
        provider.id, evaluatorModel.modelId, evaluatorModel.modelName)
    }
  }

  private makeLlmError(message: string, providerId: string, modelId: string, modelName: string): EvaluatorLlmResult {
    const err = new EvaluatorLlmResult()
    err.success = false
    err.content = ''
    err.errorMessage = message
    err.providerId = providerId
    err.modelId = modelId
    err.modelName = modelName
    return err
  }

  // ============================================================
  // 内部: 输入构造
  // ============================================================

  private buildChildProfileSnapshot(profile: ChildKnowledgeProfile): EvaluatorChildProfileSnapshot {
    const snap = new EvaluatorChildProfileSnapshot()
    snap.childName = profile.childName
    snap.ageYears = profile.ageYears
    snap.overallNote = profile.overallNote
    snap.sessionCount = profile.sessionCount
    snap.weakSkills = profile.weakAreas.slice()
    snap.strongSkills = profile.strengths.slice()
    const skillKeys = Object.keys(profile.skills)
    for (let i = 0; i < skillKeys.length; i++) {
      const dim: SkillDimension = profile.skills[skillKeys[i]]
      const item = new EvaluatorSkillSnapshot()
      item.key = dim.key
      item.label = dim.label
      item.level = dim.level
      item.lastAssessed = dim.lastAssessed
      item.notes = dim.notes
      snap.skills.push(item)
    }
    return snap
  }

  // ============================================================
  // 内部: 工具
  // ============================================================

  private startOfDay(d: Date): Date {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0)
  }

  private async getTodayFailCount(): Promise<number> {
    const today = new Date()
    const key = `${PreferenceKeys.EVALUATOR_FAIL_COUNT_PREFIX}${formatLocalYMDCompact(today)}`
    return await this.preferencesService.getNumber(key, 0)
  }

  private async incrementTodayFailCount(): Promise<void> {
    const today = new Date()
    const key = `${PreferenceKeys.EVALUATOR_FAIL_COUNT_PREFIX}${formatLocalYMDCompact(today)}`
    const cur = await this.preferencesService.getNumber(key, 0)
    await this.preferencesService.setNumber(key, cur + 1)
  }

  private async resetTodayFailCount(): Promise<void> {
    const today = new Date()
    const key = `${PreferenceKeys.EVALUATOR_FAIL_COUNT_PREFIX}${formatLocalYMDCompact(today)}`
    await this.preferencesService.setNumber(key, 0)
  }

  /**
   * 取今日最后一次评估失败时间戳（毫秒），用于 30min 重试窗口判断。
   * 返回 0 表示今日尚未失败过。
   */
  private async getTodayLastFailedAt(): Promise<number> {
    const today = new Date()
    const key = `${PreferenceKeys.EVALUATOR_LAST_FAILED_AT_PREFIX}${formatLocalYMDCompact(today)}`
    return await this.preferencesService.getNumber(key, 0)
  }

  /** 记录今日评估失败时间戳（幂等检查用）。 */
  private async setTodayLastFailedAt(): Promise<void> {
    const today = new Date()
    const key = `${PreferenceKeys.EVALUATOR_LAST_FAILED_AT_PREFIX}${formatLocalYMDCompact(today)}`
    await this.preferencesService.setNumber(key, Date.now())
  }
}

// ============================================================
// 模块级辅助函数
// ============================================================

/** LLM 序列化用 — skill velocity 快照（ArkTS 严格模式要求 class，不能用 inline 对象） */
class LlmskillVelocityRow {
  key: string = ''
  label: string = ''
  levelBefore: number = 0
  levelAfter: number = 0
  velocity: number = 0
  starCount7d: number = 0
  correctRate: number = 0
}

/** LLM 序列化用 — recurring mistake 快照 */
class LlmmistakeRow {
  skillKey: string = ''
  topicKey: string = ''
  topicLabel: string = ''
  errorCount7d: number = 0
  lastErrorAt: number = 0
}

/** LLM 序列化用 — topic interest 快照 */
class LlmtopicInterestRow {
  topicKey: string = ''
  topicLabel: string = ''
  averageTurnsPerSession: number = 0
  sessionCount7d: number = 0
  trend: string = 'stable'
}

/** LLM 序列化用 — attention 快照 */
class LlmaattentionRow {
  averageTurnsPerSession: number = 0
  medianSessionDurationSec: number = 0
  earlyExitRate: number = 0
  averageInterSessionGapHours: number = 0
  trend: string = 'stable'
}

/** LLM 序列化用 — trend 整体 */
class LlmmtrendSnapshot {
  weekStartYMD: string = ''
  weekEndYMD: string = ''
  computedAt: number = 0
  sourceWindowDays: number = 7
  skillVelocities: LlmskillVelocityRow[] = []
  recurringMistakes: LlmmistakeRow[] = []
  topicInterests: LlmtopicInterestRow[] = []
  attention: LlmaattentionRow = new LlmaattentionRow()
  topImprovements: string[] = []
  topRegressions: string[] = []
  topStruggling: string[] = []
}

/**
 * 把 WeeklyTrend 序列化为 LLM 友好的形态 (剔除元信息, 突出 4 指标)
 */
function serializeTrendForLlm(trend: WeeklyTrend): LlmmtrendSnapshot {
  const out = new LlmmtrendSnapshot()
  out.weekStartYMD = trend.weekStartYMD
  out.weekEndYMD = trend.weekEndYMD
  out.computedAt = trend.computedAt
  out.sourceWindowDays = trend.sourceWindowDays
  for (let i = 0; i < trend.skillVelocities.length; i++) {
    const v = trend.skillVelocities[i]
    const r = new LlmskillVelocityRow()
    r.key = v.key
    r.label = v.label
    r.levelBefore = v.levelBefore
    r.levelAfter = v.levelAfter
    r.velocity = v.velocity
    r.starCount7d = v.starCount7d
    r.correctRate = v.correctRate
    out.skillVelocities.push(r)
  }
  for (let i = 0; i < trend.recurringMistakes.length; i++) {
    const m = trend.recurringMistakes[i]
    const r = new LlmmistakeRow()
    r.skillKey = m.skillKey
    r.topicKey = m.topicKey
    r.topicLabel = m.topicLabel
    r.errorCount7d = m.errorCount7d
    r.lastErrorAt = m.lastErrorAt
    out.recurringMistakes.push(r)
  }
  for (let i = 0; i < trend.topicInterests.length; i++) {
    const t = trend.topicInterests[i]
    const r = new LlmtopicInterestRow()
    r.topicKey = t.topicKey
    r.topicLabel = t.topicLabel
    r.averageTurnsPerSession = t.averageTurnsPerSession
    r.sessionCount7d = t.sessionCount7d
    r.trend = t.trend
    out.topicInterests.push(r)
  }
  out.attention.averageTurnsPerSession = trend.attention.averageTurnsPerSession
  out.attention.medianSessionDurationSec = trend.attention.medianSessionDurationSec
  out.attention.earlyExitRate = trend.attention.earlyExitRate
  out.attention.averageInterSessionGapHours = trend.attention.averageInterSessionGapHours
  out.attention.trend = trend.attention.trend
  out.topImprovements = trend.topImprovements.slice()
  out.topRegressions = trend.topRegressions.slice()
  out.topStruggling = trend.topStruggling.slice()
  return out
}

export function getEvaluationService(): EvaluationService {
  return EvaluationService.getInstance()
}
