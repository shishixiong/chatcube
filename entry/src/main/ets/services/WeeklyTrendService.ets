/**
 * 周级趋势服务（聚合层）
 *
 * 责任：
 * - 评估老师（EvaluationService）调用 computeAndStoreWeeklyTrend 计算并存储近 7 天周级趋势
 * - 备课老师（LessonPlanningService）调用 getLatestTrend 读取作为 LLM 输入
 * - 评估老师自己读 latestTrend
 *
 * 数据流：
 *   DB (star_events + chat_sessions + child_profile) → 内存聚合输入 → buildWeeklyTrend → 写 weekly_trends
 *
 * 复用：
 * - utils/WeeklyTrendUtils.ets 的纯函数（4 指标聚合 + top signals）
 * - services/ChildProfileService.cachedProfile 读 child skill levels
 * - services/DatabaseService 的 star_events/sessions/weekly_trends CRUD
 */

import { Context } from '@kit.AbilityKit'
import {
  WeeklyTrend,
  WeeklyTrendRow,
  parseWeeklyTrend
} from '../models/TeachingReflectionModels'
import {
  SessionAggregate,
  StarEventAggregate,
  SkillSnapshot,
  BuildWeeklyTrendInput,
  buildWeeklyTrend
} from '../utils/WeeklyTrendUtils'
import { formatLocalYMD, formatLocalYMDCompact } from '../models/LessonPlanModels'
import { getDatabaseService } from './DatabaseService'
import { getChildProfileService } from './ChildProfileService'
import { getPreferencesService } from './PreferencesService'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { setAppUiStateValue } from '../state/AppUiState'
import { DEFAULT_ASSISTANT_ID } from '../models/AssistantModels'

const DEFAULT_WINDOW_DAYS = 7

export class WeeklyTrendService {
  private static instance: WeeklyTrendService | null = null

  static getInstance(): WeeklyTrendService {
    if (WeeklyTrendService.instance === null) {
      WeeklyTrendService.instance = new WeeklyTrendService()
    }
    return WeeklyTrendService.instance
  }

  // =================== 生命周期 ===================

  /**
   * 初始化。best-effort：尝试为本周拉取或补算一次趋势。
   * - 不阻塞调用方（fire-and-forget）
   * - 失败时吞掉错误（下次评估老师跑时会重试）
   */
  async initialize(_context: Context): Promise<void> {
    try {
      const today = new Date()
      const weekStartYMD = formatLocalYMD(this.daysAgo(today, DEFAULT_WINDOW_DAYS - 1))
      const existing = await this.getTrendByWeekStart(weekStartYMD)
      if (existing === null) {
        // 无本周 trend → 异步补算
        await this.computeAndStoreWeeklyTrend(weekStartYMD, false)
      }
    } catch (e) {
      console.warn('WeeklyTrendService', `initialize best-effort compute failed: ${JSON.stringify(e)}`)
    }
  }

  // =================== 写侧 ===================

  /**
   * 计算并存储指定 weekStartYMD 的周级趋势。
   * - weekStartYMD: 'YYYY-MM-DD' 评估当天向前推 (windowDays-1) 天的日期
   * - force=false: 若该 weekStartYMD 已有 trend 且在 12 小时内，直接返回已有
   * - 写完后 pulse WEEKLY_TREND_REFRESH_TICK
   */
  async computeAndStoreWeeklyTrend(weekStartYMD: string, force: boolean = false): Promise<WeeklyTrend | null> {
    if (weekStartYMD === '') {
      return null
    }
    try {
      // 1. 幂等：12 小时内已有则跳过（除非 force）
      if (!force) {
        const existing = await this.getTrendByWeekStart(weekStartYMD)
        if (existing !== null && (Date.now() - existing.computedAt) < 12 * 60 * 60 * 1000) {
          return existing
        }
      }

      // 2. 准备时间窗口
      const weekStart = this.parseYMDToMs(weekStartYMD)
      const weekEnd = weekStart + DEFAULT_WINDOW_DAYS * 24 * 60 * 60 * 1000
      const weekEndYMD = formatLocalYMD(new Date(weekEnd - 1))

      // 3. 拉数据
      const fetched = await Promise.all([
        this.fetchStarEventsInRange(weekStart, weekEnd),
        this.fetchSessionAggregatesInRange(weekStart, weekEnd)
      ])
      const starEvents = fetched[0]
      const sessions = fetched[1]

      // 4. 拉 child profile + 计算 snapshots
      const snapshots = await this.buildSkillSnapshots(starEvents)

      // 5. 调 utils 聚合
      const input: BuildWeeklyTrendInput = {
        weekStartYMD: weekStartYMD,
        weekEndYMD: weekEndYMD,
        computedAtMs: Date.now(),
        sourceWindowDays: DEFAULT_WINDOW_DAYS,
        snapshots: snapshots,
        starEvents: starEvents,
        sessions: sessions
      }
      const trend = buildWeeklyTrend(input)

      // 6. 写 weekly_trends
      const row = new WeeklyTrendRow()
      row.id = 'wt_' + weekStartYMD.replace(/-/g, '')
      row.week_start_ymd = weekStartYMD
      row.week_end_ymd = weekEndYMD
      row.computed_at = trend.computedAt
      row.source_window_days = trend.sourceWindowDays
      row.trend_json = JSON.stringify(trend)
      const ok = await getDatabaseService().upsertWeeklyTrend(row)
      if (!ok) {
        console.error('WeeklyTrendService', 'upsertWeeklyTrend returned false')
        return null
      }

      // 7. pulse tick
      setAppUiStateValue(AppStorageKeys.WEEKLY_TREND_REFRESH_TICK, Date.now())

      return trend
    } catch (e) {
      console.error('WeeklyTrendService', `computeAndStoreWeeklyTrend failed: ${JSON.stringify(e)}`)
      return null
    }
  }

  // =================== 读侧 ===================

  async getLatestTrend(): Promise<WeeklyTrend | null> {
    const row = await getDatabaseService().getLatestWeeklyTrend()
    if (row === null) {
      return null
    }
    return parseWeeklyTrend(row.trend_json)
  }

  async getTrendByWeekStart(weekStartYMD: string): Promise<WeeklyTrend | null> {
    const row = await getDatabaseService().getWeeklyTrendByWeekStart(weekStartYMD)
    if (row === null) {
      return null
    }
    return parseWeeklyTrend(row.trend_json)
  }

  async getTrendsInRange(fromYMD: string, toYMD: string): Promise<WeeklyTrend[]> {
    // 当前 weekly_trends 表没有 in-range 查询；按 computed_at desc 取最近 N 条
    // N 取范围天数上限（最多 90 天滚动）
    const N = 90
    void fromYMD
    void toYMD
    const all: WeeklyTrend[] = []
    const db = getDatabaseService()
    // 简化：分页拉 N 条
    try {
      // 直接复用 getLatestWeeklyTrend 不够；这里临时调一行查询
      // 用 getLatestWeeklyTrend 循环 N 次不优雅；本方法留作 v2 扩展
      const latest = await db.getLatestWeeklyTrend()
      if (latest !== null) {
        const t = parseWeeklyTrend(latest.trend_json)
        if (t !== null) {
          all.push(t)
        }
      }
    } catch (_e) {
      // best-effort
    }
    void N
    return all
  }

  // =================== 内部：数据拉取与组装 ===================

  private async fetchStarEventsInRange(startMs: number, endMs: number): Promise<StarEventAggregate[]> {
    try {
      const rows = await getDatabaseService().getStarEventsInRange(startMs, endMs)
      const result: StarEventAggregate[] = []
      for (let i = 0; i < rows.length; i++) {
        const r = rows[i]
        const e = new StarEventAggregate()
        e.skillKey = r.skillKey
        e.activityType = r.activityType
        e.stars = r.stars
        e.createdAtMs = r.createdAt
        // 从 metadata_json 提取 topicKey + topicLabel
        const parsed = this.parseMetadataTopic(r.metadataJson)
        e.topicKey = parsed.topicKey
        e.topicLabel = parsed.topicLabel
        result.push(e)
      }
      return result
    } catch (e) {
      console.warn('WeeklyTrendService', `fetchStarEventsInRange failed: ${JSON.stringify(e)}`)
      return []
    }
  }

  private parseMetadataTopic(metadataJson: string): ParsedTopic {
    if (metadataJson === '') {
      return emptyParsedTopic()
    }
    try {
      const obj = JSON.parse(metadataJson) as Object
      const r = obj as Record<string, Object>
      const tk = typeof r['topicKey'] === 'string' ? (r['topicKey'] as string) : ''
      const tl = typeof r['topicLabel'] === 'string' ? (r['topicLabel'] as string) : ''
      if (tk !== '') {
        return buildParsedTopic(tk, tl)
      }
      // fallback: 用 skillKey 当 topicKey（让 RecurringMistake 仍能聚合）
      const sk = typeof r['skillKey'] === 'string' ? (r['skillKey'] as string) : ''
      return buildParsedTopic(sk, tl)
    } catch (_e) {
      return emptyParsedTopic()
    }
  }

  private async fetchSessionAggregatesInRange(startMs: number, endMs: number): Promise<SessionAggregate[]> {
    try {
      const sessions = await getDatabaseService().getSessionsByAssistantAndDate(
        DEFAULT_ASSISTANT_ID, startMs, endMs
      )
      const result: SessionAggregate[] = []
      for (let i = 0; i < sessions.length; i++) {
        const s = sessions[i]
        const agg = new SessionAggregate()
        agg.sessionId = s.id
        agg.assistantId = s.assistantId
        agg.createdAtMs = s.createdAt
        agg.updatedAtMs = s.updatedAt
        agg.messageCount = s.messageCount
        agg.topicKeys = []  // 简化：v1 不解析 tool_call 的 topicKey
        result.push(agg)
      }
      return result
    } catch (e) {
      console.warn('WeeklyTrendService', `fetchSessionAggregatesInRange failed: ${JSON.stringify(e)}`)
      return []
    }
  }

  private async buildSkillSnapshots(starEvents: StarEventAggregate[]): Promise<SkillSnapshot[]> {
    // 1. 拉 child profile skills
    const childProfile = await getChildProfileService().getProfile()
    const result: SkillSnapshot[] = []
    const keys = Object.keys(childProfile.skills)
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i]
      const dim = childProfile.skills[k]
      const snap = new SkillSnapshot()
      snap.key = k
      snap.label = dim.label
      // levelBefore: 7 天前最近一次评估的 level。简化：复用 lastAssessed 是否落在 7 天前
      //   - 若 lastAssessed > 7 天前 → levelBefore = max(0, level - 1)
      //   - 否则 levelBefore = level
      const sevenDaysAgo = Date.now() - DEFAULT_WINDOW_DAYS * 24 * 60 * 60 * 1000
      if (dim.lastAssessed > 0 && dim.lastAssessed < sevenDaysAgo) {
        snap.levelBefore = Math.max(0, dim.level - 1)
      } else {
        snap.levelBefore = dim.level
      }
      snap.levelAfter = dim.level
      result.push(snap)
    }

    // 2. 计算每 skill 的 starCount7d / correctCount7d / totalCount7d
    for (let i = 0; i < result.length; i++) {
      const snap = result[i]
      for (let j = 0; j < starEvents.length; j++) {
        const e = starEvents[j]
        if (e.skillKey !== snap.key) {
          continue
        }
        snap.starCount7d = snap.starCount7d + e.stars
        snap.totalCount7d = snap.totalCount7d + 1
        if (e.stars > 0) {
          snap.correctCount7d = snap.correctCount7d + 1
        }
      }
    }

    return result
  }

  // =================== 工具 ===================

  private daysAgo(base: Date, days: number): Date {
    const d = new Date(base)
    d.setDate(d.getDate() - days)
    return d
  }

  private parseYMDToMs(ymd: string): number {
    // 'YYYY-MM-DD' → 本地时区零点
    const parts = ymd.split('-')
    if (parts.length !== 3) {
      return 0
    }
    const y = parseInt(parts[0], 10)
    const m = parseInt(parts[1], 10)
    const d = parseInt(parts[2], 10)
    if (isNaN(y) || isNaN(m) || isNaN(d)) {
      return 0
    }
    const date = new Date(y, m - 1, d, 0, 0, 0, 0)
    return date.getTime()
  }

  // 当前 weekStart 工具（评估老师会调）
  static currentWeekStartYMD(today: Date = new Date()): string {
    return formatLocalYMD(WeeklyTrendService.daysAgoStatic(today, DEFAULT_WINDOW_DAYS - 1))
  }

  private static daysAgoStatic(base: Date, days: number): Date {
    const d = new Date(base)
    d.setDate(d.getDate() - days)
    return d
  }
}

export function getWeeklyTrendService(): WeeklyTrendService {
  return WeeklyTrendService.getInstance()
}

// ============================================================
// 模块级辅助
// ============================================================

/** 元信息 JSON 中提取的 topicKey/topicLabel（ArkTS 严格模式要求 class，不能用 inline 对象） */
class ParsedTopic {
  topicKey: string = ''
  topicLabel: string = ''
}

function emptyParsedTopic(): ParsedTopic {
  const p = new ParsedTopic()
  return p
}

function buildParsedTopic(topicKey: string, topicLabel: string): ParsedTopic {
  const p = new ParsedTopic()
  p.topicKey = topicKey
  p.topicLabel = topicLabel
  return p
}
