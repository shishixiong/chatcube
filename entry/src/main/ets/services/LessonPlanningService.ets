/**
 * 备课老师后台服务
 *
 * 职责：
 * - 监听小星老师会话结束事件，5min 静默 debounce 后触发备课
 * - 收集今日 default 助手的对话摘要 + 儿童学习画像 + 昨日计划
 * - 调用 LLM 生成明日教学计划（plan_json）
 * - 持久化到 daily_lesson_plans 表
 * - 提供读侧 API 给 ChatViewModel 注入 system prompt
 * - 提供命中侧 API 给 ImageGenerationExecutor 复用预生成图
 *
 * 状态机（内部）：
 *   IDLE ──notifySessionEnd──► PENDING ──5min 静默──► PLANNING_AI
 *                                                          │
 *                                                    success / 失败 < 3 次
 *                                                          │
 *                                                          ▼
 *                                                        DONE / FAILED
 *
 * 幂等策略：
 * - 触发前查 daily_lesson_plans WHERE plan_date=?
 *   - status='done' → 跳过
 *   - status='pending'/'running' AND updated_at < now-30min → 重试
 *   - 不存在 → 写 'pending' 行
 * - 同日 3 次失败后不再重试（PLANNER_FAIL_COUNT_<YYYYMMDD> 偏好）
 */

import { Context } from '@kit.AbilityKit'
import { getAIApiService, AIApiService, AIApiConfig, RequestMessage } from './AIApiService'
import { getDefaultModelService, DefaultModelService } from './DefaultModelService'
import { getProviderViewModel, ProviderViewModel } from '../viewmodels/ProviderViewModel'
import { getDatabaseService, DatabaseService } from './DatabaseService'
import { getPreferencesService, PreferencesService, PreferenceKeys } from './PreferencesService'
import { getChildProfileService, ChildProfileService, ChildKnowledgeProfile, SkillDimension } from './ChildProfileService'
import { getImageGenerationService, ImageGenerationService } from './ImageGenerationService'
import { getAttachmentStorageService, AttachmentStorageService } from './AttachmentStorageService'
import {
  AttachmentType,
  MessageAttachment,
  ModelInfo,
  ModelProvider,
  ModelRole,
  ReasoningLevel,
  ChatMessage,
  ChatSession,
  OutputMode
} from '../models/ChatModels'
import {
  ImageAspectRatio,
  ImageGenerationRequest
} from '../models/ImageGenerationModels'
import { ReasoningRequestStrategy } from './registry/CompatibilityResolver'
import { getEffectiveApiKey } from '../config/PresetProviders'
import { getEffectiveCapabilities, getEffectiveOutputMode } from '../utils/ModelCapabilityDeriver'
import { getAppSettingsState } from '../state/AppSettingsState'
import { getImageIndexService, ImageIndexService } from './ImageIndexService'
import { ImageIndexMetadata, ImageSource } from '../models/ImageIndexModels'
import {
  ChildSnapshot,
  DailyLessonPlan,
  DailyLessonPlanRow,
  LessonPlan,
  LessonPlanItemBase,
  LessonPlanStatus,
  PlannerStats,
  PreparedMediaStatus,
  formatLocalYMD,
  formatLocalYMDCompact,
  inferModuleFromTopicKey,
  parseLessonPlan,
  serializeLessonPlan
} from '../models/LessonPlanModels'
import {
  PLANNER_SYSTEM_PROMPT,
  cleanPlannerJsonOutput,
  isValidJson
} from '../utils/LessonPlanPromptUtils'
import {
  PlannerSessionSummary,
  summarizeSessionForPlanner
} from '../utils/SessionSummaryUtils'
import { getTeachingStyleAdjustmentService } from './TeachingStyleAdjustmentService'
import { TeachingStyleAdjustmentSummary } from '../models/TeachingReflectionModels'
import { setAppUiStateValue } from '../state/AppUiState'
import { AppStorageKeys } from '../config/AppStorageKeys'

/** 触发后 5min 静默窗口：合并多次会话结束 */
const DEBOUNCE_MS: number = 5 * 60 * 1000

/** 同一 plan 进入 retry 模式的最小更新间隔（防止紧循环） */
const RETRY_MIN_INTERVAL_MS: number = 30 * 60 * 1000

/** 同日备课失败上限 */
const MAX_FAILS_PER_DAY: number = 3

/** 备课老师 LLM 调用最大输出 token */
const PLANNER_MAX_TOKENS: number = 4096

/** 备课老师 LLM 调用温度 */
const PLANNER_TEMPERATURE: number = 0.4

/** 预生成图并发数（与 ChatTaskOrchestratorService.MAX_CONCURRENT_TASKS 一致） */
const PREFETCH_CONCURRENCY: number = 3

/** 预生成图有效期（毫秒）：7 天 */
const PREFETCH_TTL_MS: number = 7 * 24 * 60 * 60 * 1000

/** 提示词中标记 topic_key 的格式：<topic_key>vocab.apple</topic_key> */
const TOPIC_KEY_TAG_OPEN: string = '<topic_key>'
const TOPIC_KEY_TAG_CLOSE: string = '</topic_key>'

/** 默认助手 ID（与 AssistantModels.DEFAULT_ASSISTANT_ID 保持一致，避免循环依赖） */
const DEFAULT_ASSISTANT_ID_VALUE: string = 'default'

/** 触发来源（用于日志/调试） */
type TriggerSource = 'sessionEnd' | 'workScheduler' | 'manual' | 'appStart'

/** 当前内部状态机 */
type PlannerState = 'IDLE' | 'PENDING' | 'PLANNING_AI'

/** 备课老师 LLM 调用结果（ArkTS 严格模式禁止内联对象类型） */
class PlannerLlmResult {
  success: boolean = false
  content: string = ''
  errorMessage: string = ''
  providerId: string = ''
  modelId: string = ''
  modelName: string = ''
}

/** 单个 skill 维度的快照（供 LLM 输入） */
class PlannerSkillSnapshot {
  key: string = ''
  label: string = ''
  level: number = 0
  lastAssessed: number = 0
  notes: string = ''
}

/** 儿童画像快照（供 LLM 输入） */
class PlannerChildProfileSnapshot {
  childName: string = ''
  ageYears: number = 0
  overallNote: string = ''
  sessionCount: number = 0
  weakSkills: string[] = []
  strongSkills: string[] = []
  skills: PlannerSkillSnapshot[] = []
}

/** 单张预生成任务（ArkTS 严格模式禁止内联对象类型） */
class PrefetchRequest {
  topicKey: string = ''
  topicModule: string = ''
  prompt: string = ''
}

/** 单张预生成结果 */
class PrefetchResult {
  topicKey: string = ''
  status: string = PreparedMediaStatus.READY // 'ready' | 'failed'
  filePath: string = ''
  mimeType: string = 'image/png'
  aspectRatio: string = 'square'
  revisedPrompt: string = ''
  providerId: string = ''
  providerName: string = ''
  modelId: string = ''
  modelName: string = ''
  errorMessage: string = ''
}

/** 预生成批次汇总，供 pipeline 完成日志使用 */
class PrefetchStats {
  processed: number = 0
  ready: number = 0
  failed: number = 0
}

/** 图片模型解析结果 */
class ImageModelResolution {
  found: boolean = false
  provider: ModelProvider | null = null
  model: ModelInfo | null = null
  reason: string = ''
}

export class LessonPlanningService {
  private static instance: LessonPlanningService | null = null
  private aiApiService: AIApiService
  private defaultModelService: DefaultModelService
  private providerViewModel: ProviderViewModel
  private databaseService: DatabaseService
  private preferencesService: PreferencesService
  private childProfileService: ChildProfileService
  private imageGenerationService: ImageGenerationService
  private attachmentStorageService: AttachmentStorageService

  private context: Context | null = null
  private debounceTimerId: number = -1
  private state: PlannerState = 'IDLE'
  private runningPromise: Promise<void> | null = null
  private inFlight: boolean = false

  private constructor() {
    this.aiApiService = getAIApiService()
    this.defaultModelService = getDefaultModelService()
    this.providerViewModel = getProviderViewModel()
    this.databaseService = getDatabaseService()
    this.preferencesService = getPreferencesService()
    this.childProfileService = getChildProfileService()
    this.imageGenerationService = getImageGenerationService()
    this.attachmentStorageService = getAttachmentStorageService()
  }

  static getInstance(): LessonPlanningService {
    if (LessonPlanningService.instance === null) {
      LessonPlanningService.instance = new LessonPlanningService()
    }
    return LessonPlanningService.instance
  }

  // ============================================================
  // 生命周期
  // ============================================================

  /**
   * 初始化：保存 context + 启动时清理过期 prepared_media + 主动补跑一次。
   *
   * - 不阻塞调用方
   * - 启动补跑：若今日 plan 缺失或 failed 距离上次更新已过 30min，触发一次
   */
  initialize(context: Context): void {
    this.context = context
    // 异步执行不阻塞 initialize 调用方
    void this.onInitialized()
  }

  private async onInitialized(): Promise<void> {
    try {
      // 清理过期 image_index：统一在 ImageIndexService.cleanupExpired 里
      // 串联"列过期行 → 删沙箱文件 → 删行"，避免老 prepared_media 残留孤儿文件。
      await getImageIndexService().cleanupExpired()
      // 启动补跑：交给 WorkScheduler 也可，但用户首次启动可能未注册
      await this.triggerPlanningForToday(false, 'appStart')
    } catch (error) {
      console.error('LessonPlanningService', `onInitialized error: ${JSON.stringify(error)}`)
    }
  }

  // ============================================================
  // 公共 API：触发入口
  // ============================================================

  /**
   * 通知"会话结束"事件。5min 静默 debounce 合并多次调用。
   * 仅当 assistantId === 'default' 时才生效。
   */
  notifySessionEnd(sessionId: string, assistantId: string): void {
    if (assistantId !== DEFAULT_ASSISTANT_ID_VALUE) {
      return
    }
    if (sessionId === '') {
      return
    }
    console.info('LessonPlanningService',
      `notifySessionEnd received. sessionId=${sessionId}, state=${this.state}`)
    this.schedulePlanning('sessionEnd')
  }

  /**
   * 主动触发一次备课（WorkScheduler / 设置页"立即备课一次" / 启动补跑）。
   *
   * - force=true：跳过幂等检查，强制重跑（慎用，会覆盖今日已有 plan）
   * - 默认 false：若今日已有 done 计划则跳过；pending/running 超过 30min 才重试
   */
  async triggerPlanningForToday(force: boolean = false, source: TriggerSource = 'manual'): Promise<void> {
    if (this.context === null) {
      console.warn('LessonPlanningService', 'triggerPlanningForToday: context not initialized')
      return
    }
    // 防并发：若已经在跑，复用同一个 promise
    if (this.runningPromise !== null) {
      console.info('LessonPlanningService', 'triggerPlanningForToday: already running, reuse promise')
      return this.runningPromise
    }
    // 计划日期 = 明日（本地时区）
    const tomorrow = new Date()
    tomorrow.setDate(tomorrow.getDate() + 1)
    const planDate = formatLocalYMD(tomorrow)
    this.runningPromise = this.runPlanningPipeline(planDate, force, source)
    try {
      await this.runningPromise
    } finally {
      this.runningPromise = null
    }
  }

  /**
   * 手动触发生成指定日期的备课计划。
   * 主要供设置页"立即生成今日计划"按钮使用 — 用户希望立即给当天备课
   * 而不是等明天才生效 (默认 triggerPlanningForToday 永远生成明日)。
   *
   * 幂等性: 与 triggerPlanningForToday 一致, force=true 会跳过幂等检查并覆盖。
   *
   * 注意: 输入数据 (今日会话/child profile/昨日 plan) 与 planDate 无关,
   * 始终是"今天"的视角 — 老师想基于刚发生的内容来备课, 不论 planDate 是哪天。
   */
  async triggerPlanningForDate(planDate: string, force: boolean = true, source: TriggerSource = 'manual'): Promise<void> {
    if (this.context === null) {
      console.warn('LessonPlanningService', 'triggerPlanningForDate: context not initialized')
      return
    }
    if (planDate === '') {
      console.warn('LessonPlanningService', 'triggerPlanningForDate: empty planDate, skip')
      return
    }
    if (this.runningPromise !== null) {
      console.info('LessonPlanningService',
        `triggerPlanningForDate(${planDate}): already running, reuse promise`)
      return this.runningPromise
    }
    this.runningPromise = this.runPlanningPipeline(planDate, force, source)
    try {
      await this.runningPromise
    } finally {
      this.runningPromise = null
    }
  }

  /**
   * 取消挂起的 debounce 计时器（用于设置页关闭开关）。
   */
  cancelPendingTrigger(): void {
    if (this.debounceTimerId !== -1) {
      clearTimeout(this.debounceTimerId)
      this.debounceTimerId = -1
    }
    this.state = 'IDLE'
  }

  // ============================================================
  // 公共 API：读侧（被 ChatViewModel.buildRequestSystemPrompt 用）
  // ============================================================

  /**
   * 获取今日教学计划（即昨天 21:00 备课老师生成、今天使用的 plan）。
   * - 备课老师在 21:00 跑 runPlanningPipeline(planDate=明天), 所以 DB 里 plan_date = 今日
   * - 仅返回 status='done' 的行
   * - 解析后的 LessonPlan 由 plan_json 反序列化
   */
  async getTodayPlan(): Promise<DailyLessonPlan | null> {
    const todayYMD = formatLocalYMD(new Date())
    return this.getPlanByDate(todayYMD)
  }

  /**
   * 获取任意日期的教学计划（已解析）。
   */
  async getPlanByDate(planDate: string): Promise<DailyLessonPlan | null> {
    if (planDate === '') {
      return null
    }
    const row = await this.databaseService.getDailyLessonPlanByDate(planDate)
    if (row === null || row.status !== LessonPlanStatus.DONE) {
      return null
    }
    const plan = parseLessonPlan(row.planJson)
    const result: DailyLessonPlan = new DailyLessonPlan()
    result.row = row
    result.plan = plan
    return result
  }

  /**
   * 获取昨日教学计划（已解析），用于"昨日小结"section。
   */
  async getYesterdaySummary(): Promise<DailyLessonPlan | null> {
    const yesterday = new Date()
    yesterday.setDate(yesterday.getDate() - 1)
    return this.getPlanByDate(formatLocalYMD(yesterday))
  }

  // ============================================================
  // 公共 API：命中侧（被 ImageGenerationExecutor 用）
  // ============================================================

  /**
   * 命中一张预生成图后调用：递增 consumed_count + 更新 last_consumed_at。
   * 由 ImageGenerationExecutor 在确认复用预生成图后调用。
   *
   * 现已统一走 image_index 表：内部转调 imageIndexService.markConsumed。
   * 老 prepared_media 表保留仅作 getPlannerStats 兜底统计用，不再接受外部 mark。
   *
   * （说明：tryConsumePreparedMedia / findPreparedMediaByTopicKey 已废弃；
   * image_generation 工具 executor 未来 PR 会直接调 imageIndexService.findByKey）
   */
  async markPreparedMediaConsumed(id: string): Promise<void> {
    if (id === '') {
      return
    }
    await getImageIndexService().markConsumed(id)
  }

  // ============================================================
  // 公共 API：统计（命中/总量/状态）
  // ============================================================

  /**
   * 获取备课老师运行时统计摘要。
   * - 包含 totalPlans / todayPlanStatus / preparedCount / consumedCount / hitRate / lastPlanAt
   * - 调试用，调用方应捕获异常（返回全零 stats）
   */
  async getPlannerStats(): Promise<PlannerStats> {
    const now = Date.now()
    const todayYMD = formatLocalYMD(new Date())
    return await this.databaseService.getPlannerStats(now, todayYMD)
  }

  // ============================================================
  // 内部：debounce 调度
  // ============================================================

  private schedulePlanning(source: TriggerSource): void {
    if (this.debounceTimerId !== -1) {
      clearTimeout(this.debounceTimerId)
    }
    this.state = 'PENDING'
    this.debounceTimerId = setTimeout(() => {
      this.debounceTimerId = -1
      this.state = 'PLANNING_AI'
      void this.triggerPlanningForToday(false, source)
        .catch((err: Object) => {
          console.error('LessonPlanningService', `Scheduled planning failed: ${JSON.stringify(err)}`)
        })
        .finally(() => {
          this.state = 'IDLE'
        })
    }, DEBOUNCE_MS)
  }

  // ============================================================
  // 内部：主流程
  // ============================================================

  private async runPlanningPipeline(planDate: string, force: boolean, source: TriggerSource): Promise<void> {
    if (this.inFlight && !force) {
      console.info('LessonPlanningService', 'runPlanningPipeline: in flight, skip')
      return
    }
    this.inFlight = true
    const planId = `plan_${planDate.replace(/-/g, '')}`
    try {
      // 1. 全局开关
      const enabled = await this.preferencesService.getBoolean(PreferenceKeys.PLANNER_ENABLED, true)
      if (!enabled) {
        console.info('LessonPlanningService', `planner disabled by user preference. source=${source}`)
        return
      }

      // 2. 幂等检查

      // 3. 幂等检查
      const existing = await this.databaseService.getDailyLessonPlanByDate(planDate)
      if (!force && existing !== null) {
        if (existing.status === LessonPlanStatus.DONE) {
          console.info('LessonPlanningService',
            `Plan for ${planDate} already done, skip. source=${source}`)
          return
        }
        if (existing.status === LessonPlanStatus.PENDING ||
          existing.status === LessonPlanStatus.RUNNING) {
          const ageMs = Date.now() - existing.updatedAt
          if (ageMs < RETRY_MIN_INTERVAL_MS) {
            console.info('LessonPlanningService',
              `Plan for ${planDate} is ${existing.status} and age ${ageMs}ms < ${RETRY_MIN_INTERVAL_MS}, skip`)
            return
          }
          // age >= 30min → 允许重试
          console.info('LessonPlanningService',
            `Plan for ${planDate} is ${existing.status} and stale (age ${ageMs}ms), retry`)
        }
        if (existing.status === LessonPlanStatus.FAILED) {
          // 检查同日失败次数
          const failCount = await this.getTodayFailCount()
          if (failCount >= MAX_FAILS_PER_DAY) {
            console.info('LessonPlanningService',
              `Plan for ${planDate} already failed ${failCount} times, skip`)
            return
          }
        }
      }

      // 4. 写 running 行（首次创建 / 状态转换）
      await this.writeRunning(planId, planDate, existing)

      // 5. 准备输入：今日 sessions + child profile + 昨日 plan
      // (注意: 不论 planDate 是今天还是明天, 输入都是今天的会话,
      // 因为老师想基于"刚刚发生"的内容来备课)
      const todayDate = new Date()
      const todayYMD = formatLocalYMD(todayDate)
      const dayStart = this.startOfDay(todayDate).getTime()
      // 真实明天 00:00 = 今日结束 (与 planDate 无关)
      const realTomorrow = new Date()
      realTomorrow.setDate(realTomorrow.getDate() + 1)
      const dayEnd = this.startOfDay(realTomorrow).getTime()

      const sessions = await this.databaseService.getSessionsByAssistantAndDate(
        DEFAULT_ASSISTANT_ID_VALUE,
        dayStart,
        dayEnd
      )

      // 取每个 session 的 messages
      const summaries: PlannerSessionSummary[] = []
      let messageCount = 0
      for (let i = 0; i < sessions.length; i++) {
        const session: ChatSession = sessions[i]
        const messages: ChatMessage[] = await this.databaseService.getMessages(session.id)
        messageCount += messages.length
        if (messages.length === 0) {
          continue
        }
        const summary = summarizeSessionForPlanner(session.id, messages, 600)
        summaries.push(summary)
      }
      const sessionIdsJson = JSON.stringify(sessions.map(s => s.id))

      const profile = await this.childProfileService.getProfile()
      const childSnapshot = this.buildChildSnapshot(profile, sessions.length)

      const yesterday = new Date()
      yesterday.setDate(yesterday.getDate() - 1)
      const yesterdayYMD = formatLocalYMD(yesterday)
      const yesterdayRow = await this.databaseService.getDailyLessonPlanByDate(yesterdayYMD)
      const yesterdayPlanJson = (yesterdayRow !== null && yesterdayRow.status === LessonPlanStatus.DONE)
        ? yesterdayRow.planJson
        : ''

      // 6. 调用 LLM 生成 plan
      // 先读当前 tsa (评估老师产出, 可能为 null)
      const currentAdj = await getTeachingStyleAdjustmentService().getCurrentAdjustment('', Date.now())
      const currentStyleSummary: TeachingStyleAdjustmentSummary | null =
        currentAdj !== null ? getTeachingStyleAdjustmentService().toSummary(currentAdj) : null
      const userInput = JSON.stringify({
        todaysSessions: summaries,
        childProfile: this.buildChildProfileForPlanner(profile),
        yesterdayPlan: yesterdayPlanJson === '' ? null : JSON.parse(yesterdayPlanJson),
        currentStyleAdjustment: currentStyleSummary,
        planDate: planDate,
        sessionCount: sessions.length,
        todayDate: todayYMD
      })

      const llmResult = await this.callPlannerLLM(userInput)
      if (!llmResult.success) {
        await this.markFailed(planId, planDate, llmResult.errorMessage, sessions.length, messageCount, sessionIdsJson)
        return
      }

      // 7. 解析 + 校验 LLM 输出
      const cleaned = cleanPlannerJsonOutput(llmResult.content)
      if (cleaned === '' || !isValidJson(cleaned)) {
        await this.markFailed(planId, planDate, 'LLM 输出非合法 JSON', sessions.length, messageCount, sessionIdsJson)
        return
      }
      let plan = parseLessonPlan(cleaned)
      // 强制 planDate 同步为本地时区（防止 LLM 写出错误日期）
      plan.planDate = planDate
      plan.childSnapshot = childSnapshot

      // 校验: 4 个模块数组全空 + themeTitle/teacherNotes 非空 = LLM 把所有内容
      // 写成叙述文字塞进 theme, 没有按 schema 填入结构化模块。视为无效输出, 失败重试
      const hasAnyModuleItem = plan.vocab.length > 0 || plan.math.length > 0 ||
        plan.writing.length > 0 || plan.generalKnowledge.length > 0
      const hasNarrative = plan.themeTitle !== '' || plan.teacherNotes !== ''
      if (!hasAnyModuleItem && hasNarrative) {
        console.warn('LessonPlanningService',
          `LLM output for ${planDate} has all 4 module arrays empty (theme/notes only) — ` +
          `vocab=${plan.vocab.length} math=${plan.math.length} writing=${plan.writing.length} ` +
          `general=${plan.generalKnowledge.length} themeLen=${plan.themeTitle.length} ` +
          `notesLen=${plan.teacherNotes.length}. Marking failed.`)
        await this.markFailed(planId, planDate,
          'LLM 输出未遵循 schema: 4 个模块数组全空, 仅有 theme/teacherNotes 叙述',
          sessions.length, messageCount, sessionIdsJson)
        return
      }

      // 8. 持久化
      const row = this.buildRow(planId, planDate, plan, llmResult.modelName, llmResult.providerId,
        llmResult.modelId, messageCount, sessionIdsJson)
      const ok = await this.databaseService.upsertDailyLessonPlan(row)
      if (!ok) {
        await this.markFailed(planId, planDate, 'plan 持久化失败', sessions.length, messageCount, sessionIdsJson)
        return
      }

      // 9. 成功 → 重置失败计数
      await this.resetTodayFailCount()

      // 10. 通知 UI 刷新（已关注 LESSON_PLAN_REFRESH_TICK 的页面会重建 prompt）
      setAppUiStateValue(AppStorageKeys.LESSON_PLAN_REFRESH_TICK, Date.now())

      console.info('LessonPlanningService',
        `Plan for ${planDate} generated successfully. sessions=${sessions.length}, messages=${messageCount}, ` +
        `vocab=${plan.vocab.length}, math=${plan.math.length}, writing=${plan.writing.length}, ` +
        `general=${plan.generalKnowledge.length}, freeform=${Object.keys(plan.freeform).length}`)

      // 11. 预生成图片（best-effort，失败不影响 plan 状态）
      const prefetchStats = new PrefetchStats()
      try {
        const result = await this.prefetchImages(plan, planId)
        prefetchStats.processed = result.processed
        prefetchStats.ready = result.ready
        prefetchStats.failed = result.failed
      } catch (error) {
        console.error('LessonPlanningService',
          `prefetchImages failed (non-fatal): ${JSON.stringify(error)}`)
      }

      // 12. 统计摘要日志（命中率 + 计划完成时间）
      try {
        const stats = await this.getPlannerStats()
        console.info('LessonPlanningService',
          `Pipeline done: plan=${planDate}, prefetched=${prefetchStats.processed}, ` +
          `ready=${prefetchStats.ready}, failed=${prefetchStats.failed}, ` +
          `totalHitRate=${stats.hitRate.toFixed(2)}`)
      } catch (error) {
        console.warn('LessonPlanningService',
          `Failed to collect planner stats (non-fatal): ${JSON.stringify(error)}`)
      }
    } catch (error) {
      console.error('LessonPlanningService', `runPlanningPipeline error: ${JSON.stringify(error)}`)
      // 顶层 catch：写一行 failed 记录（如果还没写）
      await this.markFailed(planId, planDate, `pipeline 异常: ${JSON.stringify(error)}`, 0, 0, '[]')
    } finally {
      this.inFlight = false
    }
  }

  // ============================================================
  // 内部：状态写入
  // ============================================================

  private async writeRunning(planId: string, planDate: string, existing: DailyLessonPlanRow | null): Promise<void> {
    const now = Date.now()
    const row = new DailyLessonPlanRow()
    row.id = planId
    row.planDate = planDate
    row.planJson = existing?.planJson ?? ''
    row.planVersion = existing?.planVersion ?? 1
    row.status = LessonPlanStatus.RUNNING
    row.errorMessage = ''
    row.plannerProviderId = existing?.plannerProviderId ?? ''
    row.plannerModelId = existing?.plannerModelId ?? ''
    row.plannerModelName = existing?.plannerModelName ?? ''
    row.sessionIdsJson = existing?.sessionIdsJson ?? '[]'
    row.messageCount = existing?.messageCount ?? 0
    row.createdAt = existing?.createdAt ?? now
    row.updatedAt = now
    row.completedAt = 0
    await this.databaseService.upsertDailyLessonPlan(row)
  }

  private async markFailed(planId: string, planDate: string, errorMessage: string,
    sessionCount: number, messageCount: number, sessionIdsJson: string): Promise<void> {
    const now = Date.now()
    const existing = await this.databaseService.getDailyLessonPlanByDate(planDate)
    const row = new DailyLessonPlanRow()
    row.id = planId
    row.planDate = planDate
    row.planJson = existing?.planJson ?? ''
    row.planVersion = existing?.planVersion ?? 1
    row.status = LessonPlanStatus.FAILED
    row.errorMessage = errorMessage
    row.plannerProviderId = existing?.plannerProviderId ?? ''
    row.plannerModelId = existing?.plannerModelId ?? ''
    row.plannerModelName = existing?.plannerModelName ?? ''
    row.sessionIdsJson = sessionIdsJson
    row.messageCount = messageCount
    row.createdAt = existing?.createdAt ?? now
    row.updatedAt = now
    row.completedAt = 0
    await this.databaseService.upsertDailyLessonPlan(row)
    // 递增同日失败计数
    await this.incrementTodayFailCount()
    console.warn('LessonPlanningService',
      `Plan for ${planDate} failed: ${errorMessage}. sessions=${sessionCount}, messages=${messageCount}`)
  }

  private buildRow(planId: string, planDate: string, plan: LessonPlan,
    modelName: string, providerId: string, modelId: string,
    messageCount: number, sessionIdsJson: string): DailyLessonPlanRow {
    const now = Date.now()
    const row = new DailyLessonPlanRow()
    row.id = planId
    row.planDate = planDate
    row.planJson = serializeLessonPlan(plan)
    row.planVersion = plan.schemaVersion
    row.status = LessonPlanStatus.DONE
    row.errorMessage = ''
    row.plannerProviderId = providerId
    row.plannerModelId = modelId
    row.plannerModelName = modelName
    row.sessionIdsJson = sessionIdsJson
    row.messageCount = messageCount
    row.createdAt = now
    row.updatedAt = now
    row.completedAt = now
    return row
  }

  // ============================================================
  // 内部：LLM 调用
  // ============================================================

  private async callPlannerLLM(userInput: string): Promise<PlannerLlmResult> {
    const plannerModel = this.defaultModelService.getModel(ModelRole.CHAT)
    if (!plannerModel.isConfigured()) {
      return this.makeLlmError('请先配置默认聊天模型', '', '', '')
    }
    const provider = await this.providerViewModel.getProviderByIdAsync(plannerModel.providerId)
    if (provider === null) {
      return this.makeLlmError(`未找到服务商: ${plannerModel.providerId}`, plannerModel.providerId, plannerModel.modelId, plannerModel.modelName)
    }
    const apiKey = getEffectiveApiKey(provider.id, provider.apiKey)
    if (apiKey === '' && provider.requiresApiKey) {
      return this.makeLlmError(`服务商 ${provider.name} 缺少 API Key`, provider.id, plannerModel.modelId, plannerModel.modelName)
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
    // 备课老师禁用推理（避免 JSON 输出被 <think> 污染）
    for (let i = 0; i < provider.models.length; i++) {
      if (provider.models[i].id === plannerModel.modelId) {
        apiConfig.modelReasoningStrategyOverride = ReasoningRequestStrategy.NONE
        apiConfig.modelSupportsReasoning = getEffectiveCapabilities(provider.models[i]).supportsReasoning
        break
      }
    }

    const messages: RequestMessage[] = [
      new RequestMessage('system', PLANNER_SYSTEM_PROMPT),
      new RequestMessage('user', userInput)
    ]

    try {
      const result = await this.aiApiService.sendChatRequest(
        apiConfig,
        messages,
        plannerModel.modelId,
        PLANNER_TEMPERATURE,
        PLANNER_MAX_TOKENS,
        ReasoningLevel.OFF
      )
      if (!result.success) {
        return this.makeLlmError(result.errorMessage, provider.id, plannerModel.modelId, plannerModel.modelName)
      }
      const ok = new PlannerLlmResult()
      ok.success = true
      ok.content = result.content
      ok.errorMessage = ''
      ok.providerId = provider.id
      ok.modelId = plannerModel.modelId
      ok.modelName = plannerModel.modelName
      return ok
    } catch (error) {
      return this.makeLlmError(`LLM 调用异常: ${JSON.stringify(error)}`, provider.id, plannerModel.modelId, plannerModel.modelName)
    }
  }

  private makeLlmError(message: string, providerId: string, modelId: string, modelName: string): PlannerLlmResult {
    const err = new PlannerLlmResult()
    err.success = false
    err.content = ''
    err.errorMessage = message
    err.providerId = providerId
    err.modelId = modelId
    err.modelName = modelName
    return err
  }

  // ============================================================
  // 内部：输入构造
  // ============================================================

  private buildChildProfileForPlanner(profile: ChildKnowledgeProfile): PlannerChildProfileSnapshot {
    const snap = new PlannerChildProfileSnapshot()
    snap.childName = profile.childName
    snap.ageYears = profile.ageYears
    snap.overallNote = profile.overallNote
    snap.sessionCount = profile.sessionCount
    snap.weakSkills = profile.weakAreas.slice()
    snap.strongSkills = profile.strengths.slice()
    const skillKeys = Object.keys(profile.skills)
    for (let i = 0; i < skillKeys.length; i++) {
      const dim: SkillDimension = profile.skills[skillKeys[i]]
      const item = new PlannerSkillSnapshot()
      item.key = dim.key
      item.label = dim.label
      item.level = dim.level
      item.lastAssessed = dim.lastAssessed
      item.notes = dim.notes
      snap.skills.push(item)
    }
    return snap
  }

  private buildChildSnapshot(profile: ChildKnowledgeProfile, sessionCount: number): ChildSnapshot {
    const snap = new ChildSnapshot()
    snap.childName = profile.childName
    snap.ageYears = profile.ageYears
    snap.weakSkills = profile.weakAreas.slice()
    snap.strongSkills = profile.strengths.slice()
    snap.overallNote = profile.overallNote
    snap.sessionCount = sessionCount
    return snap
  }

  // ============================================================
  // 内部：图片预生成
  // ============================================================

  /**
   * 解析 LLM prompt 中的 `<topic_key>...</topic_key>` 标记。
   * 找到则返回内部 key；找不到则返回 ''。
   */
  private extractTopicKeyFromPrompt(prompt: string): string {
    if (prompt === '') {
      return ''
    }
    const start = prompt.indexOf(TOPIC_KEY_TAG_OPEN)
    if (start < 0) {
      return ''
    }
    const valueStart = start + TOPIC_KEY_TAG_OPEN.length
    const end = prompt.indexOf(TOPIC_KEY_TAG_CLOSE, valueStart)
    if (end <= valueStart) {
      return ''
    }
    return prompt.substring(valueStart, end).trim()
  }

  /**
   * 解析默认图片生成模型（从 AppSettingsState.defaultImageModel 取，回退扫描所有 provider）。
   * 与 BuiltinTools.ets 的 ImageGenerationExecutor 解析逻辑保持一致。
   */
  private resolveImageModelForPlanner(): ImageModelResolution {
    const resolution = new ImageModelResolution()
    const state = getAppSettingsState()
    const defaultImage = state.defaultImageModel

    // 1) 从默认图片模型配置中查找
    if (defaultImage.providerId !== '' && defaultImage.modelId !== '') {
      for (let i = 0; i < state.providers.length; i++) {
        const p: ModelProvider = state.providers[i]
        if (p.id === defaultImage.providerId) {
          for (let j = 0; j < p.models.length; j++) {
            const m: ModelInfo = p.models[j]
            if (m.id === defaultImage.modelId && getEffectiveOutputMode(m) === OutputMode.IMAGE) {
              resolution.found = true
              resolution.provider = p
              resolution.model = m
              return resolution
            }
          }
          break
        }
      }
    }

    // 2) 回退：扫描所有 provider 找第一个可用的图片模型
    for (let i = 0; i < state.providers.length; i++) {
      const p: ModelProvider = state.providers[i]
      for (let j = 0; j < p.models.length; j++) {
        const m: ModelInfo = p.models[j]
        if (m.isEnabled && getEffectiveOutputMode(m) === OutputMode.IMAGE) {
          resolution.found = true
          resolution.provider = p
          resolution.model = m
          return resolution
        }
      }
    }

    resolution.reason = '未找到可用的图片生成模型'
    return resolution
  }

  /**
   * 从 plan 提取所有需要预生成图片的项（vocab / math / writing / generalKnowledge）。
   * 跳过空 imagePrompt 和空 topicKey 的项。
   */
  private extractPrefetchRequests(plan: LessonPlan): PrefetchRequest[] {
    const requests: PrefetchRequest[] = []
    const sources: LessonPlanItemBase[] = []
    for (let i = 0; i < plan.vocab.length; i++) {
      sources.push(plan.vocab[i])
    }
    for (let i = 0; i < plan.math.length; i++) {
      sources.push(plan.math[i])
    }
    for (let i = 0; i < plan.writing.length; i++) {
      sources.push(plan.writing[i])
    }
    for (let i = 0; i < plan.generalKnowledge.length; i++) {
      sources.push(plan.generalKnowledge[i])
    }
    for (let i = 0; i < sources.length; i++) {
      const item = sources[i]
      if (item.topicKey === '' || item.imagePrompt === '') {
        continue
      }
      const req = new PrefetchRequest()
      req.topicKey = item.topicKey
      req.topicModule = inferModuleFromTopicKey(item.topicKey)
      req.prompt = item.imagePrompt
      requests.push(req)
    }
    return requests
  }

  /**
   * 主入口：plan 持久化后，预生成所有需要图片的项。
   * - 跳过已存在 prepared_media 行（幂等）
   * - 3 并发生成，单张失败不影响其他
   * - 全失败 best-effort：仅记录日志，不影响 plan 状态
   * - 返回 PrefetchStats：processed=处理的请求数，ready=成功数，failed=失败数
   */
  async prefetchImages(plan: LessonPlan, planId: string): Promise<PrefetchStats> {
    const stats = new PrefetchStats()
    const requests = this.extractPrefetchRequests(plan)
    if (requests.length === 0) {
      console.info('LessonPlanningService', 'prefetchImages: no requests extracted')
      return stats
    }
    const resolution = this.resolveImageModelForPlanner()
    if (!resolution.found || resolution.provider === null || resolution.model === null) {
      console.warn('LessonPlanningService',
        `prefetchImages skipped: ${resolution.reason}. requests=${requests.length}`)
      return stats
    }
    console.info('LessonPlanningService',
      `prefetchImages starting: ${requests.length} requests, ` +
      `provider=${resolution.provider.id}, model=${resolution.model.id}`)

    // 幂等：跳过已存在的 topic_key
    const filtered: PrefetchRequest[] = []
    for (let i = 0; i < requests.length; i++) {
      const existing = await getImageIndexService().findByKey(ImageSource.LESSON_PLAN, requests[i].topicKey)
      if (existing === null) {
        filtered.push(requests[i])
      }
    }
    if (filtered.length === 0) {
      console.info('LessonPlanningService', 'prefetchImages: all topic_keys already prepared')
      return stats
    }

    // 3 并发生成
    let cursor = 0
    const workers: Promise<void>[] = []
    for (let w = 0; w < PREFETCH_CONCURRENCY; w++) {
      workers.push(this.prefetchWorker(filtered, resolution.provider, resolution.model, planId,
        stats,
        () => {
          const idx = cursor
          cursor += 1
          return idx < filtered.length ? filtered[idx] : null
        }))
    }
    await Promise.allSettled(workers)
    console.info('LessonPlanningService',
      `prefetchImages completed: processed=${stats.processed}, ready=${stats.ready}, ` +
      `failed=${stats.failed}, total=${requests.length}`)
    return stats
  }

  private async prefetchWorker(requests: PrefetchRequest[], provider: ModelProvider,
    model: ModelInfo, planId: string, stats: PrefetchStats,
    next: () => PrefetchRequest | null): Promise<void> {
    while (true) {
      const req = next()
      if (req === null) {
        return
      }
      const result = await this.prefetchOne(req, provider, model, planId)
      stats.processed += 1
      if (result.status === PreparedMediaStatus.READY) {
        stats.ready += 1
      } else {
        stats.failed += 1
      }
      console.info('LessonPlanningService',
        `prefetchOne: topicKey=${req.topicKey}, status=${result.status}, ` +
        `filePath=${result.filePath === '' ? '(empty)' : 'ok'}, ` +
        `error=${result.errorMessage === '' ? 'none' : result.errorMessage}`)
    }
  }

  /**
   * 预生成单张图片：调底层 ImageGenerationService → 保存到沙箱 → 写 prepared_media 行。
   * - 失败 status='failed'，记录 error_message
   * - 成功 status='ready'
   */
  private async prefetchOne(req: PrefetchRequest, provider: ModelProvider,
    model: ModelInfo, planId: string): Promise<PrefetchResult> {
    const result = new PrefetchResult()
    result.topicKey = req.topicKey

    try {
      const request = new ImageGenerationRequest()
      request.providerId = provider.id
      request.modelId = model.id
      request.prompt = req.prompt
      request.numberOfImages = 1
      request.aspectRatio = ImageAspectRatio.SQUARE

      const imageResult = await this.imageGenerationService.generateImage(provider, model, request)
      if (imageResult.items.length === 0) {
        result.status = PreparedMediaStatus.FAILED
        result.errorMessage = '图片生成接口未返回图片'
        await this.persistPrefetchResult(req, planId, result, provider, model)
        return result
      }

      const item = imageResult.items[0]
      const id = `pm_${planId.replace(/^plan_/, '')}_${req.topicKey.replace(/\./g, '_')}`
      const ext = item.mimeType === 'image/jpeg' ? '.jpg'
        : (item.mimeType === 'image/webp' ? '.webp' : '.png')
      const attachment = new MessageAttachment(
        id,
        AttachmentType.IMAGE,
        `${id}${ext}`,
        '',
        item.mimeType,
        0
      )
      attachment.base64Data = item.base64Data
      const filePath = await this.attachmentStorageService.saveAttachment(attachment)
      if (filePath === '') {
        result.status = PreparedMediaStatus.FAILED
        result.errorMessage = '沙箱文件保存失败'
        await this.persistPrefetchResult(req, planId, result, provider, model)
        return result
      }

      result.status = PreparedMediaStatus.READY
      result.filePath = filePath
      result.mimeType = item.mimeType
      result.aspectRatio = 'square'
      result.revisedPrompt = item.revisedPrompt
      result.providerId = provider.id
      result.providerName = provider.name
      result.modelId = model.id
      result.modelName = model.name !== '' ? model.name : model.id
      await this.persistPrefetchResult(req, planId, result, provider, model)
      return result
    } catch (error) {
      result.status = PreparedMediaStatus.FAILED
      result.errorMessage = `图片生成异常: ${JSON.stringify(error)}`
      await this.persistPrefetchResult(req, planId, result, provider, model)
      return result
    }
  }

  private async persistPrefetchResult(req: PrefetchRequest, planId: string,
    result: PrefetchResult, provider: ModelProvider, model: ModelInfo): Promise<void> {
    // 失败时不写索引（image_index 只缓存 ready 行；findByKey 内部就过滤了 status!='ready'）
    if (result.status !== PreparedMediaStatus.READY || result.filePath === '') {
      return
    }
    // 统一走 image_index 表（ImageSource.LESSON_PLAN）；TTL 由 putEntry 内部按 source 决定（7 天）
    const metadata: ImageIndexMetadata = {
      revisedPrompt: result.revisedPrompt,
      providerId: result.providerId !== '' ? result.providerId : provider.id,
      providerName: result.providerName !== '' ? result.providerName : provider.name,
      modelId: result.modelId !== '' ? result.modelId : model.id,
      modelName: result.modelName !== '' ? result.modelName : (model.name !== '' ? model.name : model.id),
      aspectRatio: result.aspectRatio,
      planId
    }
    await getImageIndexService().putEntry(
      ImageSource.LESSON_PLAN,
      req.topicKey,
      result.filePath,
      req.prompt,
      result.mimeType,
      metadata
    )
  }

  // ============================================================
  // 内部：日期工具
  // ============================================================

  private startOfDay(date: Date): Date {
    const d = new Date(date.getTime())
    d.setHours(0, 0, 0, 0)
    return d
  }

  // ============================================================
  // 内部：失败计数（按 YYYYMMDD 区分）
  // ============================================================

  private async getTodayFailCount(): Promise<number> {
    const today = new Date()
    const key = `${PreferenceKeys.PLANNER_FAIL_COUNT_PREFIX}${formatLocalYMDCompact(today)}`
    return await this.preferencesService.getNumber(key, 0)
  }

  private async incrementTodayFailCount(): Promise<void> {
    const today = new Date()
    const key = `${PreferenceKeys.PLANNER_FAIL_COUNT_PREFIX}${formatLocalYMDCompact(today)}`
    const cur = await this.preferencesService.getNumber(key, 0)
    await this.preferencesService.setNumber(key, cur + 1)
  }

  private async resetTodayFailCount(): Promise<void> {
    const today = new Date()
    const key = `${PreferenceKeys.PLANNER_FAIL_COUNT_PREFIX}${formatLocalYMDCompact(today)}`
    await this.preferencesService.setNumber(key, 0)
  }
}

export function getLessonPlanningService(): LessonPlanningService {
  return LessonPlanningService.getInstance()
}
