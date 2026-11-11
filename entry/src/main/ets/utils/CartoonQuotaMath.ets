/**
 * 儿童动画片额度纯函数（spec 2026-11-10 §5）。
 * 无 ArkUI / 无 I/O，可直接 hypium 单测。
 */

import {
  CARTOON_SESSION_LIMIT_MS,
  CARTOON_DAILY_LIMIT_MS,
  CARTOON_SESSION_IDLE_RESET_MS,
  CartoonEntry,
  CartoonQuotaState,
  CartoonQuotaSnapshot,
  CartoonStartDecision,
  CartoonPlaybackResult
} from '../models/CartoonModels'

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`
}

/** 本地日期键 YYYY-MM-DD */
export function formatDayKey(nowMs: number): string {
  const date = new Date(nowMs)
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`
}

/**
 * 归一化额度状态：
 * - 跨天：今日与本次同时清零
 * - 闲置超过 30 分钟：只清本次（今日保留）
 */
export function refreshQuota(state: CartoonQuotaState, nowMs: number): CartoonQuotaState {
  const today = formatDayKey(nowMs)
  if (state.dayKey !== today) {
    const reset: CartoonQuotaState = {
      dayKey: today,
      dayMs: 0,
      sessionMs: 0,
      lastActivityMs: 0
    }
    return reset
  }
  if (state.lastActivityMs > 0 && nowMs - state.lastActivityMs > CARTOON_SESSION_IDLE_RESET_MS) {
    const idleReset: CartoonQuotaState = {
      dayKey: state.dayKey,
      dayMs: state.dayMs,
      sessionMs: 0,
      lastActivityMs: 0
    }
    return idleReset
  }
  return state
}

export function buildQuotaSnapshot(state: CartoonQuotaState, nowMs: number): CartoonQuotaSnapshot {
  const fresh = refreshQuota(state, nowMs)
  const snapshot: CartoonQuotaSnapshot = {
    dayKey: fresh.dayKey,
    dayMs: fresh.dayMs,
    sessionMs: fresh.sessionMs,
    lastActivityMs: fresh.lastActivityMs,
    dayLimitMs: CARTOON_DAILY_LIMIT_MS,
    sessionLimitMs: CARTOON_SESSION_LIMIT_MS
  }
  return snapshot
}

/**
 * 开播判定。顺序与错误码见 spec §5.4。
 * 注意用 `>=`：6 分钟 × 4 集在 24 分钟结束，第 5 集才被拒。
 */
export function decideCartoonStart(durationMs: number, snapshot: CartoonQuotaSnapshot): CartoonStartDecision {
  if (durationMs <= 0) {
    const unavailable: CartoonStartDecision = { allowed: false, errorCode: 'video_unavailable' }
    return unavailable
  }
  if (durationMs > CARTOON_SESSION_LIMIT_MS) {
    const tooLong: CartoonStartDecision = { allowed: false, errorCode: 'video_too_long' }
    return tooLong
  }
  if (snapshot.dayMs >= CARTOON_DAILY_LIMIT_MS) {
    const daily: CartoonStartDecision = { allowed: false, errorCode: 'daily_limit_reached' }
    return daily
  }
  if (snapshot.sessionMs >= CARTOON_SESSION_LIMIT_MS) {
    const session: CartoonStartDecision = { allowed: false, errorCode: 'session_limit_reached' }
    return session
  }
  const allowed: CartoonStartDecision = { allowed: true, errorCode: '' }
  return allowed
}

/** snapshot 必须是「已把本次观看时长累加进去」之后的快照 */
export function buildPlaybackResult(
  entry: CartoonEntry,
  watchedMs: number,
  completed: boolean,
  endedBy: string,
  snapshot: CartoonQuotaSnapshot
): CartoonPlaybackResult {
  const sessionLeftMs = snapshot.sessionLimitMs - snapshot.sessionMs
  const dailyLeftMs = snapshot.dayLimitMs - snapshot.dayMs
  const result: CartoonPlaybackResult = {
    video_id: entry.id,
    title: entry.title,
    duration_seconds: Math.round(entry.durationMs / 1000),
    watched_seconds: Math.round(watchedMs / 1000),
    completed: completed,
    ended_by: endedBy,
    session_watched_seconds: Math.round(snapshot.sessionMs / 1000),
    session_limit_seconds: Math.round(snapshot.sessionLimitMs / 1000),
    session_budget_left_seconds: sessionLeftMs > 0 ? Math.round(sessionLeftMs / 1000) : 0,
    today_watched_seconds: Math.round(snapshot.dayMs / 1000),
    daily_limit_seconds: Math.round(snapshot.dayLimitMs / 1000),
    daily_budget_left_seconds: dailyLeftMs > 0 ? Math.round(dailyLeftMs / 1000) : 0
  }
  return result
}

/** 播放器 prepared 后对实际时长的二次判定 */
export interface CartoonPreparedDecision {
  abort: boolean
  errorCode: string
  effectiveDurationMs: number
  shouldUpdateEntry: boolean
}

/** 372 → '06:12' */
export function formatDurationSeconds(totalSeconds: number): string {
  const safe = totalSeconds > 0 ? Math.floor(totalSeconds) : 0
  return `${pad2(Math.floor(safe / 60))}:${pad2(safe % 60)}`
}

/**
 * prepared 时长是权威值（spec §10.3）：
 * - 实际超过 20 分钟 → 不播，回写条目
 * - 与条目时长差 > 2 秒 → 回写条目
 * - prepared 时长缺失（<= 0）→ 用条目时长，不回写
 */
export function evaluatePreparedDuration(
  preparedDurationMs: number,
  entryDurationMs: number
): CartoonPreparedDecision {
  const effective = preparedDurationMs > 0 ? preparedDurationMs : entryDurationMs
  if (effective > CARTOON_SESSION_LIMIT_MS) {
    const tooLong: CartoonPreparedDecision = {
      abort: true,
      errorCode: 'video_too_long',
      effectiveDurationMs: effective,
      shouldUpdateEntry: true
    }
    return tooLong
  }
  const shouldUpdate = preparedDurationMs > 0 && Math.abs(preparedDurationMs - entryDurationMs) > 2000
  const ok: CartoonPreparedDecision = {
    abort: false,
    errorCode: '',
    effectiveDurationMs: effective,
    shouldUpdateEntry: shouldUpdate
  }
  return ok
}
