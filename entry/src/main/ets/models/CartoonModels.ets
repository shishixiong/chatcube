/**
 * 儿童动画片播放（play_cartoon）数据模型与常量。
 *
 * 时间口径（spec 2026-11-10）：
 * - 单次连续观看 20 分钟：只在集与集之间拦，不切断正在播的一集
 * - 每天 60 分钟：同上
 * - 闲置 30 分钟无播放 → 本次连续观看重新计
 */

export const CARTOON_SESSION_LIMIT_MS: number = 20 * 60 * 1000
export const CARTOON_DAILY_LIMIT_MS: number = 60 * 60 * 1000
export const CARTOON_SESSION_IDLE_RESET_MS: number = 30 * 60 * 1000
export const CARTOON_PERSIST_INTERVAL_MS: number = 10 * 1000
export const CARTOON_PROMPT_MAX_ENTRIES: number = 60
export const CARTOON_MIN_GAP_MS: number = 3000

export type CartoonEntryStatus = 'ok' | 'unavailable'

/** 片库条目（持久化到 Preferences JSON） */
export interface CartoonEntry {
  id: string
  uri: string
  title: string
  tags: string
  durationMs: number
  addedAt: number
  status: CartoonEntryStatus
  /** 动画片名（系列），如 Numberblocks */
  seriesTitle: string
  /** 第几季；0 = 未标注 */
  season: number
  /** 第几集；0 = 未标注 */
  episode: number
  /** 最近一次完整看完的时间戳；0 = 没看过 */
  lastWatchedAt: number
}

/** 额度内部状态（Preferences 四个键） */
export interface CartoonQuotaState {
  dayKey: string
  dayMs: number
  sessionMs: number
  lastActivityMs: number
}

/** 对外额度快照（判定 / 提示词 / 管理页共用） */
export interface CartoonQuotaSnapshot {
  dayKey: string
  dayMs: number
  sessionMs: number
  lastActivityMs: number
  dayLimitMs: number
  sessionLimitMs: number
}

/** 开播判定结果 */
export interface CartoonStartDecision {
  allowed: boolean
  errorCode: string
}

/** 播放结束回传给 LLM 的结果 */
export interface CartoonPlaybackResult {
  video_id: string
  title: string
  duration_seconds: number
  watched_seconds: number
  completed: boolean
  ended_by: string
  session_watched_seconds: number
  session_limit_seconds: number
  session_budget_left_seconds: number
  today_watched_seconds: number
  daily_limit_seconds: number
  daily_budget_left_seconds: number
}

/** 播放页路由参数 */
export interface CartoonPlayerRouteParams {
  toolCallId: string
  videoId: string
  title: string
  durationMs: number
  uri: string
}

/** 工具失败时回传给 LLM 的备选条目 */
export interface CartoonAvailableItem {
  id: string
  title: string
  duration_seconds: number
}
