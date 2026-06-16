/**
 * 周级趋势（4 指标）聚合纯函数
 *
 * WeeklyTrendService 把从 DB 取到的"原始聚合数据"传入这些纯函数，输出 WeeklyTrend 的 4 个部分。
 * 纯函数无 DB / 无 LLM 依赖，可在 DevEco Studio 内用 hypium 单测（CLI hvigorw test 不可用，详见 MEMORY.md）。
 *
 * 输入数据契约（service 端负责从 DB 取）:
 * - StarEventAggregate[]: 近 7 天所有 star_events（按 skillKey/topicKey 拆好）
 * - SessionAggregate[]: 近 7 天所有 chat_sessions（带 topicKey 集合）
 * - SkillSnapshot: child_profile 中各 skill 的 (levelBefore, levelAfter) 快照
 *
 * 输出: WeeklyTrend
 */

import {
  WeeklyTrend,
  SkillVelocity,
  RecurringMistake,
  TopicInterest,
  AttentionMetric,
  InterestTrend,
  serializeWeeklyTrend
} from '../models/TeachingReflectionModels'

// =================== 输入数据契约 ===================

/** 单次会话的聚合（service 从 chat_sessions + chat_messages + tool_events 汇总） */
export class SessionAggregate {
  sessionId: string = ''
  assistantId: string = ''    // 用于过滤非小星老师 session
  createdAtMs: number = 0
  updatedAtMs: number = 0
  messageCount: number = 0    // 总消息数（user + assistant）
  topicKeys: string[] = []     // 该 session 涉及到的 topicKey 集合（从 tool_call.metadata 提取）
}

/** 单条 star_event 聚合 */
export class StarEventAggregate {
  skillKey: string = ''
  topicKey: string = ''       // 空字符串表示无 topicKey 信息
  topicLabel: string = ''     // 可选：人类可读标签
  activityType: string = ''
  stars: number = 0           // 0 或 1（computeStars 的输出）
  createdAtMs: number = 0
}

/** child_profile 中各 skill 的快照（before/after 对比） */
export class SkillSnapshot {
  key: string = ''
  levelBefore: number = 0
  levelAfter: number = 0
  label: string = ''          // 中文标签
  starCount7d: number = 0     // 7 天内该 skill 收到的星星数
  correctCount7d: number = 0  // 7 天内该 skill 答对次数
  totalCount7d: number = 0    // 7 天内该 skill 总题数
}

// =================== 4 指标聚合 ===================

/** 计算各 skill 的进步速度（per-skill velocity） */
export function aggregateSkillVelocities(snapshots: SkillSnapshot[]): SkillVelocity[] {
  const result: SkillVelocity[] = []
  for (let i = 0; i < snapshots.length; i++) {
    const s = snapshots[i]
    const v = new SkillVelocity()
    v.key = s.key
    v.label = s.label
    v.levelBefore = s.levelBefore
    v.levelAfter = s.levelAfter
    v.velocity = s.levelAfter - s.levelBefore
    v.starCount7d = s.starCount7d
    v.correctRate = s.totalCount7d > 0 ? s.correctCount7d / s.totalCount7d : 0
    result.push(v)
  }
  // 按 velocity desc 排序（进步最大的在前）
  result.sort((a, b) => b.velocity - a.velocity)
  return result
}

/** 计算反复出错点（同 topicKey 7 天内错 ≥ 3 次） */
export function aggregateRecurringMistakes(
  starEvents: StarEventAggregate[],
  errorThreshold: number = 3
): RecurringMistake[] {
  // 按 (skillKey, topicKey) 聚合
  const buckets: Map<string, RecurringMistake> = new Map()
  for (let i = 0; i < starEvents.length; i++) {
    const e = starEvents[i]
    // stars === 0 视为答错；topicKey 为空的忽略（无法归因）
    if (e.stars !== 0 || e.topicKey === '') {
      continue
    }
    const k = e.skillKey + '|' + e.topicKey
    const existing = buckets.get(k)
    if (existing) {
      existing.errorCount7d = existing.errorCount7d + 1
      if (e.createdAtMs > existing.lastErrorAt) {
        existing.lastErrorAt = e.createdAtMs
      }
    } else {
      const m = new RecurringMistake()
      m.skillKey = e.skillKey
      m.topicKey = e.topicKey
      m.topicLabel = e.topicLabel
      m.errorCount7d = 1
      m.lastErrorAt = e.createdAtMs
      m.suggestion = ''
      buckets.set(k, m)
    }
  }
  const result: RecurringMistake[] = []
  buckets.forEach((v) => {
    if (v.errorCount7d >= errorThreshold) {
      result.push(v)
    }
  })
  // 按 errorCount7d desc 排序
  result.sort((a, b) => b.errorCount7d - a.errorCount7d)
  return result
}

/** 计算主题兴趣（per-topic 平均轮次 + 趋势） */
export function aggregateTopicInterests(sessions: SessionAggregate[]): TopicInterest[] {
  // 按 topicKey 聚合
  interface TopicAcc {
    topicLabel: string
    totalTurns: number
    sessionCount: number
    timestamps: number[]   // session updatedAtMs
  }
  const buckets: Map<string, TopicAcc> = new Map()
  for (let i = 0; i < sessions.length; i++) {
    const s = sessions[i]
    for (let j = 0; j < s.topicKeys.length; j++) {
      const tk = s.topicKeys[j]
      if (tk === '') {
        continue
      }
      const existing = buckets.get(tk)
      const turns = s.messageCount
      if (existing) {
        existing.totalTurns = existing.totalTurns + turns
        existing.sessionCount = existing.sessionCount + 1
        existing.timestamps.push(s.updatedAtMs)
      } else {
        const acc: TopicAcc = {
          topicLabel: '',
          totalTurns: turns,
          sessionCount: 1,
          timestamps: [s.updatedAtMs]
        }
        buckets.set(tk, acc)
      }
    }
  }
  // 计算 trend: 后半段平均轮次 vs 前半段
  const result: TopicInterest[] = []
  buckets.forEach((v, k) => {
    const t = new TopicInterest()
    t.topicKey = k
    t.topicLabel = v.topicLabel
    t.averageTurnsPerSession = v.sessionCount > 0 ? v.totalTurns / v.sessionCount : 0
    t.sessionCount7d = v.sessionCount
    t.trend = inferTrendFromTimestamps(v.timestamps)
    result.push(t)
  })
  result.sort((a, b) => b.averageTurnsPerSession - a.averageTurnsPerSession)
  return result
}

/** 计算参与度与注意力 */
export function aggregateAttention(sessions: SessionAggregate[]): AttentionMetric {
  const a = new AttentionMetric()
  if (sessions.length === 0) {
    return a
  }

  let totalTurns = 0
  const durations: number[] = []
  const gaps: number[] = []
  let earlyExitCount = 0
  const EARLY_EXIT_THRESHOLD = 5

  for (let i = 0; i < sessions.length; i++) {
    const s = sessions[i]
    totalTurns = totalTurns + s.messageCount
    const durationSec = Math.max(0, Math.round((s.updatedAtMs - s.createdAtMs) / 1000))
    durations.push(durationSec)
    if (s.messageCount < EARLY_EXIT_THRESHOLD) {
      earlyExitCount = earlyExitCount + 1
    }
  }

  // 计算相邻 session 间隔
  const sortedByTime = sessions.slice().sort((x, y) => x.createdAtMs - y.createdAtMs)
  for (let i = 1; i < sortedByTime.length; i++) {
    const gap = sortedByTime[i].createdAtMs - sortedByTime[i - 1].updatedAtMs
    if (gap > 0) {
      gaps.push(gap / (1000 * 60 * 60))  // 转换为小时
    }
  }

  a.averageTurnsPerSession = totalTurns / sessions.length
  a.medianSessionDurationSec = median(durations)
  a.earlyExitRate = earlyExitCount / sessions.length
  a.averageInterSessionGapHours = gaps.length > 0 ? sum(gaps) / gaps.length : 0

  // trend: 整体 averageTurns 趋势
  const firstHalfTurns = average(sessions.slice(0, Math.floor(sessions.length / 2)).map(s => s.messageCount))
  const secondHalfTurns = average(sessions.slice(Math.floor(sessions.length / 2)).map(s => s.messageCount))
  a.trend = compareTrend(firstHalfTurns, secondHalfTurns)

  return a
}

// =================== 顶层信号：top 3 ===================

export class WeeklyTrendTopSignals {
  topImprovements: string[] = []
  topRegressions: string[] = []
  topStruggling: string[] = []
}

/** 提取 top 3 信号：进步 / 退步 / 反复出错 */
export function summarizeTopSignals(
  velocities: SkillVelocity[],
  mistakes: RecurringMistake[],
  limit: number = 3
): WeeklyTrendTopSignals {
  const out = new WeeklyTrendTopSignals()
  // top 进步：velocity > 0 的，按 velocity desc 取前 limit
  const positive = velocities.filter(v => v.velocity > 0).slice(0, limit)
  for (let i = 0; i < positive.length; i++) {
    out.topImprovements.push(positive[i].key)
  }
  // top 退步：velocity < 0 的，按 velocity asc 取前 limit
  const negative = velocities.filter(v => v.velocity < 0).slice().sort((a, b) => a.velocity - b.velocity).slice(0, limit)
  for (let i = 0; i < negative.length; i++) {
    out.topRegressions.push(negative[i].key)
  }
  // top 反复出错：按 errorCount7d desc 已排序的 mistakes 取前 limit
  for (let i = 0; i < mistakes.length && i < limit; i++) {
    out.topStruggling.push(mistakes[i].topicKey)
  }
  return out
}

// =================== 顶层组装：service 直接调 ===================

export class BuildWeeklyTrendInput {
  weekStartYMD: string = ''
  weekEndYMD: string = ''
  computedAtMs: number = 0
  sourceWindowDays: number = 7
  snapshots: SkillSnapshot[] = []
  starEvents: StarEventAggregate[] = []
  sessions: SessionAggregate[] = []
}

/** 一次调完，组装完整 WeeklyTrend（service 入口用） */
export function buildWeeklyTrend(input: BuildWeeklyTrendInput): WeeklyTrend {
  const trend = new WeeklyTrend()
  trend.weekStartYMD = input.weekStartYMD
  trend.weekEndYMD = input.weekEndYMD
  trend.computedAt = input.computedAtMs
  trend.sourceWindowDays = input.sourceWindowDays

  trend.skillVelocities = aggregateSkillVelocities(input.snapshots)
  trend.recurringMistakes = aggregateRecurringMistakes(input.starEvents, 3)
  trend.topicInterests = aggregateTopicInterests(input.sessions)
  trend.attention = aggregateAttention(input.sessions)

  const topSignals = summarizeTopSignals(trend.skillVelocities, trend.recurringMistakes, 3)
  trend.topImprovements = topSignals.topImprovements
  trend.topRegressions = topSignals.topRegressions
  trend.topStruggling = topSignals.topStruggling

  return trend
}

/** 序列化的便捷 wrapper */
export function buildWeeklyTrendJson(input: BuildWeeklyTrendInput): string {
  return serializeWeeklyTrend(buildWeeklyTrend(input))
}

// =================== 内部工具函数 ===================

function inferTrendFromTimestamps(timestamps: number[]): InterestTrend {
  if (timestamps.length < 2) {
    return 'stable'
  }
  const sorted = timestamps.slice().sort((a, b) => a - b)
  const mid = Math.floor(sorted.length / 2)
  // 比较"前半段时间内该主题出现次数"vs"后半段时间内该主题出现次数"
  // session 数上升 → 主题升温 → 'rising'; 反之 → 'falling'
  const firstHalfCount = mid
  const secondHalfCount = sorted.length - mid
  return compareTrend(firstHalfCount, secondHalfCount)
}

function compareTrend(first: number, second: number): InterestTrend {
  if (second > first * 1.2) {
    return 'rising'
  } else if (second < first * 0.8) {
    return 'falling'
  } else {
    return 'stable'
  }
}

function median(arr: number[]): number {
  if (arr.length === 0) {
    return 0
  }
  const sorted = arr.slice().sort((a, b) => a - b)
  const mid = Math.floor(sorted.length / 2)
  if (sorted.length % 2 === 0) {
    return (sorted[mid - 1] + sorted[mid]) / 2
  }
  return sorted[mid]
}

function sum(arr: number[]): number {
  let total = 0
  for (let i = 0; i < arr.length; i++) {
    total = total + arr[i]
  }
  return total
}

function average(arr: number[]): number {
  if (arr.length === 0) {
    return 0
  }
  return sum(arr) / arr.length
}
