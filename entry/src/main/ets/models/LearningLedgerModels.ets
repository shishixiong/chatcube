/**
 * LearningLedgerModels - 词汇台账数据模型 + Leitner 掌握度状态机 + 常量
 *
 * 设计: docs/superpowers/specs/2026-09-30-vocab-repetition-control-design.md
 * 全部为纯数据/纯函数, 不依赖 ArkUI 与数据库, 可被 hypium 直接单测。
 * 所有调参常量集中于此, 避免散落漂移。
 */

/** Leitner 复习间隔 (天), 下标 = mastery 0..5 */
export const LEDGER_INTERVAL_DAYS: number[] = [0, 1, 2, 4, 7, 15]

export const LEDGER_DAY_MS: number = 24 * 60 * 60 * 1000
/** 同词同题型冷却 30 分钟 */
export const SAME_MODE_COOLDOWN_MS: number = 30 * 60 * 1000
/** 同一会话内同词至少间隔 5 题 */
export const SESSION_GAP_ITEMS: number = 5
/** 已掌握词抽检周期 30 天 */
export const MASTERED_RECHECK_MS: number = 30 * LEDGER_DAY_MS
/** 近 7 天高频统计窗口 */
export const TOP_REPEATED_WINDOW_MS: number = 7 * LEDGER_DAY_MS
/** buildSummary 缓存 TTL 60s (门禁只读缓存, 避免每题查库) */
export const SUMMARY_CACHE_TTL_MS: number = 60 * 1000
/** 每 session 近期出题环形缓冲容量 */
export const RECENT_WINDOW_CAPACITY: number = 20
/** learning_item_events 保留 90 天 */
export const EVENT_RETENTION_MS: number = 90 * LEDGER_DAY_MS
/** 内存 session 环形缓冲最多保留的 session 数 */
export const RECENT_SESSION_PRUNE_MAX: number = 24

/** 科目代号: 地理 (map_card / map_quiz / map_puzzle 写入) */
export const LEDGER_SUBJECT_GEO: string = 'geo'
/** 条目类型: 省级行政区 */
export const LEDGER_ITEM_TYPE_PLACE: string = 'place'
/** 技能键: 认得这个省 (名称 / 位置 / 轮廓) */
export const LEDGER_SKILL_GEO_PLACE: string = 'geo_place'

/**
 * 四维掌握度 (2026-11-03): 每个词分别累积 认/听/读/写 的尝试与正确次数。
 * 内部代号用于计数列与 prompt, UI 展示走 dimensionLabel。
 */
export const LEDGER_DIM_RECOGNIZE: string = 'recognize'
export const LEDGER_DIM_LISTEN: string = 'listen'
export const LEDGER_DIM_READ: string = 'read'
export const LEDGER_DIM_WRITE: string = 'write'
/** 固定展示顺序: 认 → 听 → 读 → 写 */
export const LEDGER_DIMENSIONS: string[] = [
  LEDGER_DIM_RECOGNIZE, LEDGER_DIM_LISTEN, LEDGER_DIM_READ, LEDGER_DIM_WRITE
]

/** 维度代号 → 给家长/prompt 看的中文标签 */
export function dimensionLabel(dimension: string): string {
  switch (dimension) {
    case LEDGER_DIM_RECOGNIZE: return '认'
    case LEDGER_DIM_LISTEN: return '听'
    case LEDGER_DIM_READ: return '读'
    case LEDGER_DIM_WRITE: return '写'
    default: return dimension
  }
}

/** 重复检查原因码 */
export const REPEAT_REASON_SESSION_GAP: string = 'session_gap'
export const REPEAT_REASON_SAME_MODE_COOLDOWN: string = 'same_mode_cooldown'
export const REPEAT_REASON_MASTERED_RECHECK: string = 'mastered_recheck'

/** learning_items 一行的内存模型 */
export class LearningItem {
  itemKey: string = ''
  subject: string = ''
  itemType: string = ''
  display: string = ''
  skillKey: string = ''
  firstTaughtAt: number = 0
  lastSeenAt: number = 0
  exposureCount: number = 0
  correctCount: number = 0
  wrongCount: number = 0
  mastery: number = 0
  consecutiveCorrect: number = 0
  modesSeen: string[] = []
  lastMode: string = ''
  lastSessionId: string = ''
  nextReviewAt: number = 0
  masteredAt: number = 0
  source: string = 'session'
  createdAt: number = 0
  updatedAt: number = 0
  // 四维掌握度计数 (2026-11-03): 每次作答按题型维度累加; 教学曝光不计入
  recognizeTries: number = 0
  recognizeOk: number = 0
  listenTries: number = 0
  listenOk: number = 0
  readTries: number = 0
  readOk: number = 0
  writeTries: number = 0
  writeOk: number = 0
}

/** 待复习提示 */
export class DueReviewHint {
  display: string = ''
  lastMode: string = ''
  dueInMs: number = 0
  /** 弱项维度代号 (未测优先, 其次 level 最低); 空数组 = 无明显弱项 */
  weakDimensions: string[] = []
}

/** 近 7 天高频统计 */
export class RepeatStat {
  display: string = ''
  count: number = 0
}

/** 注入 prompt / 供门禁的台账摘要 */
export class LedgerSummary {
  newPool: string[] = []
  dueReview: DueReviewHint[] = []
  mastered: string[] = []
  cooling: string[] = []
  topRepeated: RepeatStat[] = []
}

export function createEmptyLedgerSummary(): LedgerSummary {
  return new LedgerSummary()
}

/** recordServed 输入 */
export interface LedgerRecord {
  itemKey: string
  subject: string
  itemType: string
  display: string
  skillKey: string
  mode: string
  toolId: string
  sessionId: string
  now: number
}

/** 备课计划种子 (只建行, 不改掌握度) */
export interface LedgerItemSeed {
  subject: string
  itemType: string
  display: string
  skillKey: string
}

/** 出题侧从工具参数提取的目标项 (不含 itemKey, 由服务经 normalizeItemKey 计算) */
export interface LedgerToolItem {
  subject: string
  itemType: string
  display: string
  mode: string
  skillKey: string
}

/** 作答侧对账项 */
export interface LedgerAnswerItem {
  itemKey: string
  isCorrect: boolean
  /**
   * 四维掌握度维度代号 (recognize/listen/read/write); '' = 不推进维度
   * (讲解型工具或未映射的题型)。由 utils/LedgerExtractUtils.skillDimensionFor 计算。
   */
  dimension: string
}

/** learning_item_events 插入 */
export interface LedgerEventInsert {
  id: string
  itemKey: string
  sessionId: string
  mode: string
  toolId: string
  servedAt: number
  display: string
}

/** 掌握度迁移结果 */
export interface MasteryTransition {
  mastery: number
  consecutiveCorrect: number
  nextReviewAt: number
  justMastered: boolean
}

/** 重复检查结论 (reason 为 REPEAT_REASON_* 之一, allowed=true 时为空串) */
export interface RepeatCheck {
  allowed: boolean
  reason: string
  itemKey: string
  display: string
}

/** evaluateRepeatPolicy 输入 (服务层收集 DB 行 + 会话环, 纯函数判定) */
export interface RepeatPolicyInput {
  purpose: string
  mode: string
  now: number
  found: boolean
  lastSeenAt: number
  lastMode: string
  mastery: number
  nextReviewAt: number
  inSessionGap: boolean
  itemKey: string
  display: string
}

/**
 * 单维掌握度 0-5 (纯函数, 2026-11-03)。
 * 0 = 未测; 1-5 = 从「常错」到「稳定掌握」。样本量门槛的设计目的:
 * 一次答对不应直接封顶 5, 至少 3 次且有高正确率才给 4-5。
 */
export function skillDimensionLevel(ok: number, tries: number): number {
  if (tries <= 0) {
    return 0
  }
  if (tries === 1) {
    return ok >= 1 ? 2 : 1
  }
  if (tries === 2) {
    return ok >= 2 ? 3 : (ok >= 1 ? 2 : 1)
  }
  const ratio = ok / tries
  if (ratio >= 0.9) {
    return 5
  }
  if (ratio >= 0.75) {
    return 4
  }
  if (ratio >= 0.5) {
    return 3
  }
  if (ratio >= 0.25) {
    return 2
  }
  return 1
}

/** 单维计数快照 */
export interface DimensionCounts {
  ok: number
  tries: number
}

function dimensionCounts(ok: number, tries: number): DimensionCounts {
  const counts: DimensionCounts = { ok: ok, tries: tries }
  return counts
}

/** 某维度在该词上的 (ok, tries); 未知维度返回 tries=0 */
export function dimensionCountsOf(item: LearningItem, dimension: string): DimensionCounts {
  switch (dimension) {
    case LEDGER_DIM_RECOGNIZE:
      return dimensionCounts(item.recognizeOk, item.recognizeTries)
    case LEDGER_DIM_LISTEN:
      return dimensionCounts(item.listenOk, item.listenTries)
    case LEDGER_DIM_READ:
      return dimensionCounts(item.readOk, item.readTries)
    case LEDGER_DIM_WRITE:
      return dimensionCounts(item.writeOk, item.writeTries)
    default:
      return dimensionCounts(0, 0)
  }
}

/**
 * 一个词当前最该练的维度 (最多 2 个):
 * 1. 未测维度优先 (按 认/听/读/写 固定顺序)
 * 2. 其次已测但 level ≤ 2 的维度, 按 level 升序 (同级按固定顺序)
 * 全部维度都 ≥ 3 时返回空数组 (无明显弱项)。
 */
export function weakDimensionsFor(item: LearningItem): string[] {
  const untested: string[] = []
  const weak: string[] = []
  const levels: number[] = []
  for (let i = 0; i < LEDGER_DIMENSIONS.length; i++) {
    const dim = LEDGER_DIMENSIONS[i]
    const counts = dimensionCountsOf(item, dim)
    if (counts.tries <= 0) {
      untested.push(dim)
      continue
    }
    const level = skillDimensionLevel(counts.ok, counts.tries)
    if (level <= 2) {
      // 插入排序保持 level 升序, 同级按 LEDGER_DIMENSIONS 顺序
      let insertAt = weak.length
      for (let j = 0; j < weak.length; j++) {
        if (level < levels[j]) {
          insertAt = j
          break
        }
      }
      weak.splice(insertAt, 0, dim)
      levels.splice(insertAt, 0, level)
    }
  }
  const out: string[] = []
  for (let i = 0; i < untested.length && out.length < 2; i++) {
    out.push(untested[i])
  }
  for (let i = 0; i < weak.length && out.length < 2; i++) {
    out.push(weak[i])
  }
  return out
}

/** mastery 对应的下次复习间隔 (毫秒)。mastery=5 走 30 天抽检, 其余走 INTERVAL_DAYS。 */
function nextIntervalMs(mastery: number): number {
  if (mastery >= 5) {
    return MASTERED_RECHECK_MS
  }
  const idx = Math.max(0, Math.min(5, mastery))
  return LEDGER_INTERVAL_DAYS[idx] * LEDGER_DAY_MS
}

/**
 * Leitner 掌握度状态机 (spec §5.3):
 * - 答对: streak+1; streak>=2 且 mastery<5 → mastery+1; nextReviewAt 按 INTERVAL 前移
 * - 答错: streak=0, mastery=max(0, mastery-1), nextReviewAt 提前
 * - mastery=5 已封顶时不再升, justMastered=false, 间隔走 30 天抽检
 */
export function computeMasteryTransition(mastery: number, consecutiveCorrect: number,
  isCorrect: boolean, now: number): MasteryTransition {
  const result: MasteryTransition = {
    mastery: mastery,
    consecutiveCorrect: consecutiveCorrect,
    nextReviewAt: now,
    justMastered: false
  }
  if (isCorrect) {
    const newStreak = consecutiveCorrect + 1
    const newMastery = (newStreak >= 2 && mastery < 5) ? mastery + 1 : mastery
    result.mastery = newMastery
    result.consecutiveCorrect = newStreak
    result.justMastered = newMastery === 5 && mastery < 5
    result.nextReviewAt = now + nextIntervalMs(newMastery)
  } else {
    result.mastery = Math.max(0, mastery - 1)
    result.consecutiveCorrect = 0
    result.nextReviewAt = now + nextIntervalMs(result.mastery)
  }
  return result
}
