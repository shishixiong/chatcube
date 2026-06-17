/**
 * 教学反思 / 教学风格调整 / 周级趋势 数据模型
 *
 * 多 Agent 教学系统（主 agent 小星老师 + 评估老师 + 备课老师）新增的数据契约。
 * - 评估老师：消费 4 指标周级趋势 + childProfile → 产出 4 维度 TeachingStyleAdjustment
 * - 备课老师：消费 TeachingStyleAdjustment（currentStyleAdjustment）→ 生成明日 plan
 * - 主 agent：消费 TeachingStyleAdjustment 注入 systemPrompt 动态段
 *
 * 写入位置:
 * - TeachingStyleAdjustment → SQLite 表 teaching_style_adjustments
 * - WeeklyTrend (整列 JSON) → SQLite 表 weekly_trends
 *
 * 4 维度字段采用 string literal union（不用 enum），避免反序列化时 type↔string 转换坑；
 * 写入前用 inXxx() 类型守卫白名单校验。
 */

// =================== 教学风格调整: 4 维度 type + 白名单 ===================

export type DifficultyTendency = 'easier' | 'current' | 'harder'
export type FeedbackTone = 'gentle' | 'neutral' | 'playful'
export type WeakStrongBalance = 'weak_focus' | 'balanced' | 'strong_focus'
export type LearningPace = 'minimal' | 'standard' | 'extensive'

/** 4 维度默认值集合（fallback 用） */
export const DEFAULT_DIFFICULTY_TENDENCY: DifficultyTendency = 'current'
export const DEFAULT_FEEDBACK_TONE: FeedbackTone = 'gentle'
export const DEFAULT_WEAK_STRONG_BALANCE: WeakStrongBalance = 'balanced'
export const DEFAULT_LEARNING_PACE: LearningPace = 'standard'

/**
 * 评估老师每日触发时间（24h 本地时区）。
 * - EvaluationService.startIntervalCheck 降级路径在此小时首分钟起检查；
 * - LearningDailyEvaluationPage.EmptyState 据此切"今日未到"/"今日已过"子态。
 * - 改一处必须同步另一处。
 */
export const EVALUATION_TRIGGER_HOUR: number = 21

/**
 * 评估老师触发窗口（分钟），仅用于 setInterval 降级路径的尾段截断。
 * WorkScheduler 路径（OS 主路径）由系统自行决定时间窗。
 */
export const EVALUATION_TRIGGER_WINDOW_MINUTES: number = 30

/** 白名单常量数组（写入前校验用） */
const DIFFICULTY_TENDENCIES: DifficultyTendency[] = ['easier', 'current', 'harder']
const FEEDBACK_TONES: FeedbackTone[] = ['gentle', 'neutral', 'playful']
const WEAK_STRONG_BALANCES: WeakStrongBalance[] = ['weak_focus', 'balanced', 'strong_focus']
const LEARNING_PACES: LearningPace[] = ['minimal', 'standard', 'extensive']

export function inDifficultyTendency(x: string): boolean {
  return DIFFICULTY_TENDENCIES.indexOf(x as DifficultyTendency) >= 0
}

export function inFeedbackTone(x: string): boolean {
  return FEEDBACK_TONES.indexOf(x as FeedbackTone) >= 0
}

export function inWeakStrongBalance(x: string): boolean {
  return WEAK_STRONG_BALANCES.indexOf(x as WeakStrongBalance) >= 0
}

export function inLearningPace(x: string): boolean {
  return LEARNING_PACES.indexOf(x as LearningPace) >= 0
}

// =================== 教学风格调整: 完整对象 + 摘要 ===================

/**
 * 单条教学风格调整记录。
 * 由评估老师（EvaluationService）每日产出，注入小星老师 systemPrompt 末尾。
 */
export class TeachingStyleAdjustment {
  id: string = ''
  effectiveDate: string = ''          // 'YYYY-MM-DD' 生效日期
  expiresAt: number = 0               // 过期时间戳（默认 +14 天）
  sourceWeeklyTrendId: string = ''    // 关联 weekly_trends.id（弱引用）
  sourceSessionCount: number = 0      // 评估时使用了多少个 session

  // 4 维度
  difficultyTendency: DifficultyTendency = DEFAULT_DIFFICULTY_TENDENCY
  feedbackTone: FeedbackTone = DEFAULT_FEEDBACK_TONE
  weakStrongBalance: WeakStrongBalance = DEFAULT_WEAK_STRONG_BALANCE
  learningPace: LearningPace = DEFAULT_LEARNING_PACE

  // 4 维度的 rationale（注入 prompt 用，由 EvaluationService 生成）
  difficultyRationale: string = ''
  feedbackRationale: string = ''
  balanceRationale: string = ''
  paceRationale: string = ''

  // 元信息
  evaluatorProviderId: string = ''
  evaluatorModelId: string = ''
  evaluatorModelName: string = ''
  confidence: number = 0              // 0-1
  status: string = TeachingStyleAdjustmentStatus.DONE  // 'done' | 'failed' (区别于 done/failed 行)
  createdAt: number = 0
}

/**
 * 教学风格调整的精简版（不包含元信息）。
 * 用于 LessonPlanningService 接收 style adjustment 上下文。
 */
export class TeachingStyleAdjustmentSummary {
  effectiveDate: string = ''
  difficultyTendency: DifficultyTendency = DEFAULT_DIFFICULTY_TENDENCY
  feedbackTone: FeedbackTone = DEFAULT_FEEDBACK_TONE
  weakStrongBalance: WeakStrongBalance = DEFAULT_WEAK_STRONG_BALANCE
  learningPace: LearningPace = DEFAULT_LEARNING_PACE

  difficultyRationale: string = ''
  feedbackRationale: string = ''
  balanceRationale: string = ''
  paceRationale: string = ''
}

/** DB 行（DB 原生列名） */
export class TeachingStyleAdjustmentRow {
  id: string = ''
  effective_date: string = ''
  expires_at: number = 0
  source_weekly_trend_id: string = ''
  source_session_count: number = 0

  difficulty_tendency: string = DEFAULT_DIFFICULTY_TENDENCY
  feedback_tone: string = DEFAULT_FEEDBACK_TONE
  weak_strong_balance: string = DEFAULT_WEAK_STRONG_BALANCE
  learning_pace: string = DEFAULT_LEARNING_PACE

  difficulty_rationale: string = ''
  feedback_rationale: string = ''
  balance_rationale: string = ''
  pace_rationale: string = ''

  evaluator_provider_id: string = ''
  evaluator_model_id: string = ''
  evaluator_model_name: string = ''
  confidence: number = 0
  status: string = TeachingStyleAdjustmentStatus.DONE
  created_at: number = 0
}

/** TeachingStyleAdjustment 状态枚举（mirror LessonPlanStatus 风格，string 而非 enum） */
export class TeachingStyleAdjustmentStatus {
  static readonly DONE: string = 'done'
  static readonly FAILED: string = 'failed'
}

// =================== 周级趋势: 4 指标 ===================

/** 技能进步速度（per-skill velocity） */
export class SkillVelocity {
  key: string = ''                    // skill_key
  label: string = ''                  // 中文标签
  levelBefore: number = 0             // 7 天前快照 level
  levelAfter: number = 0              // 当前 level
  velocity: number = 0                // delta = levelAfter - levelBefore
  starCount7d: number = 0             // 近 7 天星星数
  correctRate: number = 0             // 近 7 天正确率 (0-1)
}

/** 反复出错点（recurring mistakes） */
export class RecurringMistake {
  skillKey: string = ''
  topicKey: string = ''               // 'math.add.basic' / 'vocab.apple' 等
  topicLabel: string = ''             // '苹果' / '基础加法'
  errorCount7d: number = 0            // 近 7 天错误次数
  lastErrorAt: number = 0             // 最近错误时间戳
  suggestion: string = ''             // '降低难度 / 换题型 / 加强讲解'
}

export type InterestTrend = 'rising' | 'falling' | 'stable'

/** 兴趣主题变化（topic interest shifts） */
export class TopicInterest {
  topicKey: string = ''               // 'vocab.apple' / 'general_nature.cat'
  topicLabel: string = ''
  averageTurnsPerSession: number = 0  // 该主题平均会话轮次
  sessionCount7d: number = 0          // 近 7 天出现会话数
  trend: InterestTrend = 'stable'
}

/** 参与度与注意力（attention/engagement） */
export class AttentionMetric {
  averageTurnsPerSession: number = 0        // 平均轮次
  medianSessionDurationSec: number = 0      // 中位时长（秒）
  earlyExitRate: number = 0                 // < 5 轮就退出的会话占比
  averageInterSessionGapHours: number = 0  // 平均会话间隔（小时）
  trend: InterestTrend = 'stable'
}

/** 周级趋势根结构 */
export class WeeklyTrend {
  weekStartYMD: string = ''           // 'YYYY-MM-DD' 本周一开始（含评估当天向前推 6 天）
  weekEndYMD: string = ''             // 'YYYY-MM-DD' 本周日结束
  computedAt: number = 0              // 评估时间戳
  sourceWindowDays: number = 7

  skillVelocities: SkillVelocity[] = []
  recurringMistakes: RecurringMistake[] = []
  topicInterests: TopicInterest[] = []
  attention: AttentionMetric = new AttentionMetric()

  // 顶层信号：给评估老师看的"一句话摘要"
  topImprovements: string[] = []      // 进步最大的 3 个 skill_key
  topRegressions: string[] = []       // 退步 / 停滞的 3 个 skill_key
  topStruggling: string[] = []        // 反复出错的 3 个 topic_key
}

/** DB 行（整列 JSON blob，trend_json 字段存 WeeklyTrend 序列化结果） */
export class WeeklyTrendRow {
  id: string = ''                     // 'wt_YYYYMMDD'
  week_start_ymd: string = ''
  week_end_ymd: string = ''
  computed_at: number = 0
  source_window_days: number = 7
  trend_json: string = ''
}

// =================== 解析/序列化 工具函数 ===================

/** 安全序列化 WeeklyTrend。出错时返回空字符串。 */
export function serializeWeeklyTrend(trend: WeeklyTrend): string {
  try {
    return JSON.stringify(trend)
  } catch (_e) {
    return ''
  }
}

/**
 * 安全解析 weekly_trend JSON。
 * - 失败返回 null（与 parseLessonPlan 的 fallback-to-empty 不同，因为周级趋势失败时不应让评估老师继续用空数据）。
 * - 字段缺省时按类型默认。
 */
export function parseWeeklyTrend(json: string): WeeklyTrend | null {
  if (json === '') {
    return null
  }
  let raw: Object
  try {
    raw = JSON.parse(json) as Object
  } catch (_e) {
    return null
  }
  const r = raw as Record<string, Object>
  if (r === null || typeof r !== 'object' || Array.isArray(r)) {
    return null
  }
  return hydrateWeeklyTrend(r)
}

function hydrateWeeklyTrend(r: Record<string, Object>): WeeklyTrend {
  const trend = new WeeklyTrend()
  if (typeof r['weekStartYMD'] === 'string') {
    trend.weekStartYMD = r['weekStartYMD'] as string
  }
  if (typeof r['weekEndYMD'] === 'string') {
    trend.weekEndYMD = r['weekEndYMD'] as string
  }
  if (typeof r['computedAt'] === 'number') {
    trend.computedAt = r['computedAt'] as number
  }
  if (typeof r['sourceWindowDays'] === 'number') {
    trend.sourceWindowDays = r['sourceWindowDays'] as number
  }

  if (Array.isArray(r['skillVelocities'])) {
    trend.skillVelocities = (r['skillVelocities'] as Object[]).map(hydrateSkillVelocity)
  }
  if (Array.isArray(r['recurringMistakes'])) {
    trend.recurringMistakes = (r['recurringMistakes'] as Object[]).map(hydrateRecurringMistake)
  }
  if (Array.isArray(r['topicInterests'])) {
    trend.topicInterests = (r['topicInterests'] as Object[]).map(hydrateTopicInterest)
  }
  if (r['attention'] !== undefined && typeof r['attention'] === 'object' && r['attention'] !== null) {
    trend.attention = hydrateAttentionMetric(r['attention'] as Object)
  }

  if (Array.isArray(r['topImprovements'])) {
    trend.topImprovements = (r['topImprovements'] as Object[]).map(s => String(s))
  }
  if (Array.isArray(r['topRegressions'])) {
    trend.topRegressions = (r['topRegressions'] as Object[]).map(s => String(s))
  }
  if (Array.isArray(r['topStruggling'])) {
    trend.topStruggling = (r['topStruggling'] as Object[]).map(s => String(s))
  }
  return trend
}

function hydrateSkillVelocity(raw: Object): SkillVelocity {
  const r = raw as Record<string, Object>
  const v = new SkillVelocity()
  v.key = stringField(r, 'key')
  v.label = stringField(r, 'label')
  if (typeof r['levelBefore'] === 'number') v.levelBefore = r['levelBefore'] as number
  if (typeof r['levelAfter'] === 'number') v.levelAfter = r['levelAfter'] as number
  if (typeof r['velocity'] === 'number') v.velocity = r['velocity'] as number
  if (typeof r['starCount7d'] === 'number') v.starCount7d = r['starCount7d'] as number
  if (typeof r['correctRate'] === 'number') v.correctRate = r['correctRate'] as number
  return v
}

function hydrateRecurringMistake(raw: Object): RecurringMistake {
  const r = raw as Record<string, Object>
  const m = new RecurringMistake()
  m.skillKey = stringField(r, 'skillKey')
  m.topicKey = stringField(r, 'topicKey')
  m.topicLabel = stringField(r, 'topicLabel')
  if (typeof r['errorCount7d'] === 'number') m.errorCount7d = r['errorCount7d'] as number
  if (typeof r['lastErrorAt'] === 'number') m.lastErrorAt = r['lastErrorAt'] as number
  m.suggestion = stringField(r, 'suggestion')
  return m
}

function hydrateTopicInterest(raw: Object): TopicInterest {
  const r = raw as Record<string, Object>
  const t = new TopicInterest()
  t.topicKey = stringField(r, 'topicKey')
  t.topicLabel = stringField(r, 'topicLabel')
  if (typeof r['averageTurnsPerSession'] === 'number') t.averageTurnsPerSession = r['averageTurnsPerSession'] as number
  if (typeof r['sessionCount7d'] === 'number') t.sessionCount7d = r['sessionCount7d'] as number
  const trend = stringField(r, 'trend')
  if (trend === 'rising' || trend === 'falling' || trend === 'stable') {
    t.trend = trend
  }
  return t
}

function hydrateAttentionMetric(raw: Object): AttentionMetric {
  const r = raw as Record<string, Object>
  const a = new AttentionMetric()
  if (typeof r['averageTurnsPerSession'] === 'number') a.averageTurnsPerSession = r['averageTurnsPerSession'] as number
  if (typeof r['medianSessionDurationSec'] === 'number') a.medianSessionDurationSec = r['medianSessionDurationSec'] as number
  if (typeof r['earlyExitRate'] === 'number') a.earlyExitRate = r['earlyExitRate'] as number
  if (typeof r['averageInterSessionGapHours'] === 'number') a.averageInterSessionGapHours = r['averageInterSessionGapHours'] as number
  const trend = stringField(r, 'trend')
  if (trend === 'rising' || trend === 'falling' || trend === 'stable') {
    a.trend = trend
  }
  return a
}

function stringField(r: Record<string, Object>, key: string): string {
  const v = r[key]
  return typeof v === 'string' ? v : ''
}

// =================== 工厂方法 ===================

/** 创建默认 4 维度的 TeachingStyleAdjustment（fallback 用） */
export function createDefaultTeachingStyleAdjustment(): TeachingStyleAdjustment {
  return new TeachingStyleAdjustment()
}

/** 评估老师 JSON 输出 → 校验 + 包装为 TeachingStyleAdjustment。
 *  4 维度不在白名单时降级到默认值（不让单个 LLM 错误导致整个 evaluation 失败）。
 *  返回 null 表示输入 JSON 整体不可解析。
 */
export function hydrateTeachingStyleAdjustmentFromLlm(
  raw: Object,
  fallbackDate: string,
  sourceWeeklyTrendId: string = '',
  sourceSessionCount: number = 0
): TeachingStyleAdjustment | null {
  const r = raw as Record<string, Object>
  if (r === null || typeof r !== 'object' || Array.isArray(r)) {
    return null
  }
  const adj = new TeachingStyleAdjustment()
  adj.id = 'tsa_' + fallbackDate.replace(/-/g, '')
  adj.effectiveDate = fallbackDate
  adj.expiresAt = Date.now() + 14 * 24 * 60 * 60 * 1000  // 14 天
  adj.sourceWeeklyTrendId = sourceWeeklyTrendId
  adj.sourceSessionCount = sourceSessionCount
  adj.createdAt = Date.now()

  const dT = stringField(r, 'difficultyTendency')
  if (inDifficultyTendency(dT)) {
    adj.difficultyTendency = dT as DifficultyTendency
  }
  const fT = stringField(r, 'feedbackTone')
  if (inFeedbackTone(fT)) {
    adj.feedbackTone = fT as FeedbackTone
  }
  const wB = stringField(r, 'weakStrongBalance')
  if (inWeakStrongBalance(wB)) {
    adj.weakStrongBalance = wB as WeakStrongBalance
  }
  const lP = stringField(r, 'learningPace')
  if (inLearningPace(lP)) {
    adj.learningPace = lP as LearningPace
  }

  adj.difficultyRationale = stringField(r, 'difficultyRationale')
  adj.feedbackRationale = stringField(r, 'feedbackRationale')
  adj.balanceRationale = stringField(r, 'balanceRationale')
  adj.paceRationale = stringField(r, 'paceRationale')

  if (typeof r['confidence'] === 'number') {
    const c = r['confidence'] as number
    adj.confidence = c < 0 ? 0 : (c > 1 ? 1 : c)
  }

  return adj
}
