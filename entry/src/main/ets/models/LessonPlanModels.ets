/**
 * 每日教学计划数据模型
 *
 * 由"备课老师"后台服务每日生成，供小星老师 system prompt 注入使用。
 * - 持久化: SQLite 表 daily_lesson_plans.plan_json（整列 JSON blob）
 * - 读取: 注入 ChatViewModel.buildRequestSystemPrompt
 * - 扩展性: 4 个强类型核心模块（vocab/math/writing/generalKnowledge）+ freeform Record 容纳未来新课程点
 */

// =================== Item 基础结构 ===================

/** 教学项通用字段。所有 Item 都带 topicKey（语义键）用于精确匹配预生成图 */
export class LessonPlanItemBase {
  topicKey: string = ''         // 语义键：'vocab.apple' / 'math.shape.triangle' / 'writing.山'
  imagePrompt: string = ''      // 备课老师优化的图像 prompt（英文），空字符串表示不需要图
}

/** 英语词汇项 */
export class LessonPlanVocabItem extends LessonPlanItemBase {
  word: string = ''             // 目标词
  translation: string = ''      // 中文释义
  exampleSentence: string = ''  // 教学例句（中文）
  imagePrompt: string = ''      // 备课老师优化的图像 prompt（英文）
  difficultyHint: string = ''   // '幼儿' | '入门' | '进阶'
}

/** 数学项 */
export class LessonPlanMathItem extends LessonPlanItemBase {
  dimension: string = ''       // 对应 ChildProfile skill_key（如 'math_shapes'）
  description: string = ''     // 教学描述（中文）
  targetSkillLevel: number = 0 // 目标 level (0-5)
  imagePrompt: string = ''     // 几何图形等可视化提示词
}

/** 写字项 */
export class LessonPlanWritingItem extends LessonPlanItemBase {
  characterOrWord: string = '' // 写字/组词
  description: string = ''
  imagePrompt: string = ''     // 写字插图
}

/** 常识项 */
export class LessonPlanGeneralItem extends LessonPlanItemBase {
  dimension: string = ''       // 关联 skill_key
  description: string = ''
  imagePrompt: string = ''
}

// =================== ChildProfile 快照 ===================

/** 备课时的 child_profile 摘要快照，便于家长回看教学决策 */
export class ChildSnapshot {
  childName: string = ''
  ageYears: number = 0
  weakSkills: string[] = []    // 备课老师重点关注的薄弱项 skill_key
  strongSkills: string[] = []
  overallNote: string = ''
  sessionCount: number = 0
}

// =================== LessonPlan 根 ===================

/**
 * 每日教学计划根结构。
 *
 * 4 个强类型模块：vocab / math / writing / generalKnowledge（小星老师 prompt 显式引用）
 * 1 个 freeform Record：未来扩展 reading / music / science 等模块直接加 key，解析时容错
 */
export class LessonPlan {
  schemaVersion: number = 1
  planDate: string = ''        // 'YYYY-MM-DD'
  themeTitle: string = ''      // 例："今天和苹果做朋友"
  themeDescription: string = ''// 给小星老师的简短说明
  teacherNotes: string = ''    // 3-5 句人话提示

  vocab: LessonPlanVocabItem[] = []
  math: LessonPlanMathItem[] = []
  writing: LessonPlanWritingItem[] = []
  generalKnowledge: LessonPlanGeneralItem[] = []

  // 自由扩展：未来加 'reading' / 'music' / 'science' 直接放这里
  freeform: Record<string, Object> = {}

  childSnapshot: ChildSnapshot = new ChildSnapshot()
}

// =================== 解析/序列化 工具函数 ===================

/**
 * 安全解析 lesson_plan JSON 字符串。容错策略：
 * 1. 解析失败返回空 LessonPlan（不抛错）
 * 2. 缺字段给默认值（空字符串/空数组/0）
 * 3. 数组字段不是数组时降级为空数组
 * 4. 未识别字段保留（不影响核心）
 */
export function parseLessonPlan(json: string): LessonPlan {
  const fallback = new LessonPlan()
  if (json === '') {
    return fallback
  }
  let raw: Object
  try {
    raw = JSON.parse(json) as Object
  } catch (_e) {
    return fallback
  }
  return hydrateLessonPlan(raw)
}

function hydrateLessonPlan(raw: Object): LessonPlan {
  const plan = new LessonPlan()
  const r = raw as Record<string, Object>
  if (typeof r['schemaVersion'] === 'number') {
    plan.schemaVersion = r['schemaVersion'] as number
  }
  if (typeof r['planDate'] === 'string') {
    plan.planDate = r['planDate'] as string
  }
  if (typeof r['themeTitle'] === 'string') {
    plan.themeTitle = r['themeTitle'] as string
  }
  if (typeof r['themeDescription'] === 'string') {
    plan.themeDescription = r['themeDescription'] as string
  }
  if (typeof r['teacherNotes'] === 'string') {
    plan.teacherNotes = r['teacherNotes'] as string
  }
  if (Array.isArray(r['vocab'])) {
    plan.vocab = (r['vocab'] as Object[]).map(hydrateVocabItem)
  }
  if (Array.isArray(r['math'])) {
    plan.math = (r['math'] as Object[]).map(hydrateMathItem)
  }
  if (Array.isArray(r['writing'])) {
    plan.writing = (r['writing'] as Object[]).map(hydrateWritingItem)
  }
  if (Array.isArray(r['generalKnowledge'])) {
    plan.generalKnowledge = (r['generalKnowledge'] as Object[]).map(hydrateGeneralItem)
  }
  if (r['freeform'] !== undefined && typeof r['freeform'] === 'object' && r['freeform'] !== null) {
    plan.freeform = r['freeform'] as Record<string, Object>
  }
  if (r['childSnapshot'] !== undefined && typeof r['childSnapshot'] === 'object' && r['childSnapshot'] !== null) {
    plan.childSnapshot = hydrateChildSnapshot(r['childSnapshot'] as Object)
  }
  return plan
}

function hydrateVocabItem(raw: Object): LessonPlanVocabItem {
  const r = raw as Record<string, Object>
  const item = new LessonPlanVocabItem()
  item.topicKey = stringField(r, 'topicKey')
  item.word = stringField(r, 'word')
  item.translation = stringField(r, 'translation')
  item.exampleSentence = stringField(r, 'exampleSentence')
  item.imagePrompt = stringField(r, 'imagePrompt')
  item.difficultyHint = stringField(r, 'difficultyHint')
  return item
}

function hydrateMathItem(raw: Object): LessonPlanMathItem {
  const r = raw as Record<string, Object>
  const item = new LessonPlanMathItem()
  item.topicKey = stringField(r, 'topicKey')
  item.dimension = stringField(r, 'dimension')
  item.description = stringField(r, 'description')
  if (typeof r['targetSkillLevel'] === 'number') {
    item.targetSkillLevel = r['targetSkillLevel'] as number
  }
  item.imagePrompt = stringField(r, 'imagePrompt')
  return item
}

function hydrateWritingItem(raw: Object): LessonPlanWritingItem {
  const r = raw as Record<string, Object>
  const item = new LessonPlanWritingItem()
  item.topicKey = stringField(r, 'topicKey')
  item.characterOrWord = stringField(r, 'characterOrWord')
  item.description = stringField(r, 'description')
  item.imagePrompt = stringField(r, 'imagePrompt')
  return item
}

function hydrateGeneralItem(raw: Object): LessonPlanGeneralItem {
  const r = raw as Record<string, Object>
  const item = new LessonPlanGeneralItem()
  item.topicKey = stringField(r, 'topicKey')
  item.dimension = stringField(r, 'dimension')
  item.description = stringField(r, 'description')
  item.imagePrompt = stringField(r, 'imagePrompt')
  return item
}

function hydrateChildSnapshot(raw: Object): ChildSnapshot {
  const r = raw as Record<string, Object>
  const snap = new ChildSnapshot()
  snap.childName = stringField(r, 'childName')
  if (typeof r['ageYears'] === 'number') {
    snap.ageYears = r['ageYears'] as number
  }
  if (Array.isArray(r['weakSkills'])) {
    snap.weakSkills = (r['weakSkills'] as Object[]).map(s => String(s))
  }
  if (Array.isArray(r['strongSkills'])) {
    snap.strongSkills = (r['strongSkills'] as Object[]).map(s => String(s))
  }
  snap.overallNote = stringField(r, 'overallNote')
  if (typeof r['sessionCount'] === 'number') {
    snap.sessionCount = r['sessionCount'] as number
  }
  return snap
}

function stringField(r: Record<string, Object>, key: string): string {
  const v = r[key]
  return typeof v === 'string' ? v : ''
}

/** 序列化 LessonPlan 为 JSON 字符串。出错时返回空字符串。 */
export function serializeLessonPlan(plan: LessonPlan): string {
  try {
    return JSON.stringify(plan)
  } catch (_e) {
    return ''
  }
}

// =================== DB Row 类型 ===================

/** daily_lesson_plans 表的一行（DB 原生） */
export class DailyLessonPlanRow {
  id: string = ''
  planDate: string = ''
  planJson: string = ''
  planVersion: number = 1
  status: string = 'pending'         // 'pending' | 'running' | 'done' | 'failed'
  errorMessage: string = ''
  plannerProviderId: string = ''
  plannerModelId: string = ''
  plannerModelName: string = ''
  sessionIdsJson: string = '[]'
  messageCount: number = 0
  createdAt: number = 0
  updatedAt: number = 0
  completedAt: number = 0
}

/** daily_lesson_plans 的运行时包装：DB 行 + 解析后的 plan 对象 */
export class DailyLessonPlan {
  row: DailyLessonPlanRow = new DailyLessonPlanRow()
  plan: LessonPlan = new LessonPlan()
}

/** prepared_media 表的一行（DB 原生） */
export class PreparedMediaRow {
  id: string = ''
  planId: string = ''
  topicKey: string = ''
  topicModule: string = ''
  prompt: string = ''
  revisedPrompt: string = ''
  providerId: string = ''
  providerName: string = ''
  modelId: string = ''
  modelName: string = ''
  filePath: string = ''
  mimeType: string = 'image/png'
  aspectRatio: string = 'square'
  status: string = 'ready'           // 'pending' | 'ready' | 'failed'
  errorMessage: string = ''
  consumedCount: number = 0
  lastConsumedAt: number = 0
  createdAt: number = 0
  expiresAt: number = 0
}

// =================== 状态枚举 ===================

export class LessonPlanStatus {
  static readonly PENDING: string = 'pending'
  static readonly RUNNING: string = 'running'
  static readonly DONE: string = 'done'
  static readonly FAILED: string = 'failed'
}

export class PreparedMediaStatus {
  static readonly PENDING: string = 'pending'
  static readonly READY: string = 'ready'
  static readonly FAILED: string = 'failed'
}

// =================== 工具函数 ===================

/** 把本地 Date 转 'YYYY-MM-DD' 字符串（本地时区） */
export function formatLocalYMD(date: Date): string {
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, '0')
  const d = String(date.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

/** 'YYYYMMDD'（无分隔符）用于生成 plan_id 前缀 */
export function formatLocalYMDCompact(date: Date): string {
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, '0')
  const d = String(date.getDate()).padStart(2, '0')
  return `${y}${m}${d}`
}

/** 从 topicKey 推断 module（'vocab.apple' → 'vocab'）。空字符串返回 'unknown'。 */
export function inferModuleFromTopicKey(topicKey: string): string {
  if (topicKey === '') {
    return 'unknown'
  }
  const idx = topicKey.indexOf('.')
  if (idx <= 0) {
    return 'unknown'
  }
  return topicKey.substring(0, idx)
}
