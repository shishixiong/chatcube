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
}

/** 待复习提示 */
export class DueReviewHint {
  display: string = ''
  lastMode: string = ''
  dueInMs: number = 0
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
