/**
 * 星星奖励服务
 *
 * 为数学题/英语题/数字华容道三块可评分卡片提供星星奖励:
 * - 计算公式集中在 computeStars (纯函数, 易测试)
 * - 写入 SQLite star_events 表
 * - 同步 AppUiState.todayStarSummary (顶层小卡) 与 lastStarGrant (即时浮层)
 * - 递增 starEarnedTick 触发 ChatPage 浮层
 *
 * 与 ChildProfileService / child_profile 工具完全正交——本服务不参与 AI 推理。
 */

import { getDatabaseService, DatabaseService } from './DatabaseService'
import {
  LastStarGrant,
  RecordStarEventResult,
  StarActivityType,
  StarEventInsert,
  StarEventRow,
  StarTypeBucket,
  TodayStarSummary,
  createEmptyTodayStarSummary,
  getBucketFromSummary,
  STAR_ACTIVITY_TYPES
} from '../models/StarEventModels'
import { getAppUiState, setAppUiStateValue } from '../state/AppUiState'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { getStartOfMonthMs } from '../utils/DateFormatUtils'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN = 0x0000
const TAG = 'StarRewardService'

const DIFFICULTY_STARS: Record<number, number> = {
  2: 1,
  3: 2,
  4: 3,
  5: 5
}

function getStartOfTodayMs(): number {
  const now = new Date()
  now.setHours(0, 0, 0, 0)
  return now.getTime()
}

export interface RecordStarEventInput {
  activityType: StarActivityType
  payloadJson: string
  toolCallId: string
  sessionId: string
}

export class StarRewardService {
  private static instance: StarRewardService | null = null
  private database: DatabaseService

  private constructor() {
    this.database = getDatabaseService()
  }

  static getInstance(): StarRewardService {
    if (StarRewardService.instance === null) {
      StarRewardService.instance = new StarRewardService()
    }
    return StarRewardService.instance
  }

  /**
   * 纯计算: 根据 activityType 与 payload 计算应得星星数
   * - math_quiz / english_quiz: correct=true → 1, 否则 0
   * - number_puzzle: completed=false → 0; 否则按 difficulty 2→1, 3→2, 4→3, 5→5
   * - handwriting_practice: completed=true → 1, 否则 0
   * - 任何解析失败 / 边界外值 → 0
   */
  computeStars(activityType: string, payload: Record<string, Object>): number {
    if (activityType === 'math_quiz' || activityType === 'english_quiz') {
      const correct = payload['correct']
      return correct === true ? 1 : 0
    }
    if (activityType === 'number_puzzle') {
      const completed = payload['completed']
      if (completed !== true) {
        return 0
      }
      const difficulty = (payload['difficulty'] as number) ?? 0
      return DIFFICULTY_STARS[difficulty] ?? 0
    }
    if (activityType === 'handwriting_practice') {
      const completed = payload['completed']
      return completed === true ? 1 : 0
    }
    if (activityType === 'categorization') {
      const completed = payload['completed']
      if (completed !== true) {
        return 0
      }
      const correct = (payload['correct'] as number) ?? 0
      const total = (payload['total'] as number) ?? 0
      if (total <= 0 || correct < total) {
        return 1
      }
      const difficulty = (payload['difficulty'] as number) ?? 0
      return DIFFICULTY_STARS[difficulty] ?? 1
    }
    if (activityType === 'maze') {
      const completed = payload['completed']
      if (completed !== true) {
        return 0
      }
      // 走迷宫: 完成 1 颗基础星 + 每个胡萝卜 1 颗奖励星
      // 例: 收集 2 根胡萝卜并完成迷宫 → 1 + 2 = 3 颗星
      const starsCollected = (payload['stars_collected'] as number) ?? 0
      return 1 + Math.max(0, starsCollected)
    }
    if (activityType === 'sudoku') {
      const completed = payload['completed']
      if (completed !== true) {
        return 0
      }
      // 数独: 按难度授予 milestone 星 (镜像 number_puzzle 的 1/2/3/5 体系, 5 级梯度版)
      const difficulty = (payload['difficulty'] as number) ?? 0
      const SUDOKU_DIFFICULTY_STARS: Record<number, number> = {
        1: 1,
        2: 2,
        3: 3,
        4: 5,
        5: 7
      }
      return SUDOKU_DIFFICULTY_STARS[difficulty] ?? 1
    }
    if (activityType === 'chat_correct') {
      return 1
    }
    if (activityType === 'picture_vocab') {
      const correct = payload['correct']
      return correct === true ? 1 : 0
    }
    if (activityType === 'listening_quiz') {
      const correct = payload['correct']
      return correct === true ? 1 : 0
    }
    if (activityType === 'pinyin_quiz') {
      const correct = payload['correct']
      return correct === true ? 1 : 0
    }
    return 0
  }

  /**
   * 核心入口: 被 ToolExecutionService 在 math/english/puzzle 三个 handler 末尾调用
   *
   * 副作用:
   * 1. 写一行 star_events (含 0 颗事件)
   * 2. 更新 AppUiState.todayStarSummary (UI 顶层小卡自动响应)
   * 3. 设置 AppUiState.lastStarGrant 并递增 starEarnedTick (ChatPage 浮层)
   *
   * 失败策略: 写库失败时静默 + log, 不影响主流程 (AI 拿到 result 后继续对话)
   */
  async recordEvent(input: RecordStarEventInput): Promise<RecordStarEventResult> {
    let payload: Record<string, Object> = {}
    let parseError = ''
    try {
      payload = JSON.parse(input.payloadJson) as Record<string, Object>
    } catch (error) {
      parseError = String(error)
      hilog.warn(DOMAIN, TAG, `Failed to parse payload JSON: ${parseError}`)
    }

    const stars = this.computeStars(input.activityType, payload)
    const now = Date.now()
    const skillKey = (payload['skill_key'] as string) ?? ''

    const insert: StarEventInsert = {
      createdAt: now,
      activityType: input.activityType,
      stars: stars,
      toolCallId: input.toolCallId,
      sessionId: input.sessionId,
      skillKey: skillKey,
      metadataJson: parseError !== '' ? `parse_error: ${parseError}` : ''
    }
    const rowId = await this.database.insertStarEvent(insert)
    if (rowId < 0) {
      hilog.warn(DOMAIN, TAG, `insertStarEvent returned -1, skipping UI update`)
      const failResult: RecordStarEventResult = { stars: stars }
      return failResult
    }

    // 同步顶层状态 (顶层小卡响应式更新)
    const updated = await this.refreshTodaySummaryInState()
    // 即时浮层信号
    const grant: LastStarGrant = {
      stars: stars,
      activityType: input.activityType,
      createdAt: now
    }
    setAppUiStateValue(AppStorageKeys.STAR_LAST_GRANT, JSON.stringify(grant))
    // 用递增 tick 触发 ChatPage 观察器
    const currentTick = getAppUiState().starEarnedTick
    setAppUiStateValue(AppStorageKeys.STAR_EARNED_TICK, currentTick + 1)
    hilog.info(DOMAIN, TAG, `Recorded star event: type=${input.activityType}, stars=${stars}, total=${updated.total}`)
    const successResult: RecordStarEventResult = { stars: stars }
    return successResult
  }

  /**
   * 启动时预热: 把今日 summary 一次性算好写入 AppUiState
   * 调用时机: EntryAbility.initializeServices 末尾
   */
  async ensureLoaded(): Promise<void> {
    try {
      await this.refreshTodaySummaryInState()
      hilog.info(DOMAIN, TAG, 'ensureLoaded completed')
    } catch (error) {
      hilog.error(DOMAIN, TAG, `ensureLoaded failed: ${JSON.stringify(error)}`)
    }
  }

  /**
   * 拉取今日所有事件 + 聚合, 同时把结果回写 AppUiState.todayStarSummary
   */
  async refreshTodaySummaryInState(): Promise<TodayStarSummary> {
    const summary = await this.getTodaySummary()
    setAppUiStateValue(AppStorageKeys.STAR_TODAY_SUMMARY, JSON.stringify(summary))
    setAppUiStateValue(AppStorageKeys.STAR_TODAY_LOADED, true)
    return summary
  }

  /**
   * 从 DB 拉今日事件, 在内存中聚合 (不写状态, 纯查询)
   */
  async getTodaySummary(): Promise<TodayStarSummary> {
    const startMs = getStartOfTodayMs()
    const events = await this.database.getStarEventsSince(startMs)
    return this.aggregateEvents(events)
  }

  /**
   * 取今日事件列表 (按 createdAt 升序, 供明细页渲染)
   */
  async getTodayEvents(): Promise<StarEventRow[]> {
    const startMs = getStartOfTodayMs()
    return await this.database.getStarEventsSince(startMs)
  }

  /**
   * 取指定年月的所有星事件 (1≤month≤12, 含 startMs 不含 endMs)
   * - 用于日历视图按月分页; month=13 自动回卷到次年 1 月
   * - 走 idx_star_events_created_at 索引, 性能优于 getStarEventsSince(0) + 客户端过滤
   */
  async getMonthStarEvents(year: number, month: number): Promise<StarEventRow[]> {
    const startMs = getStartOfMonthMs(year, month)
    const endMs = getStartOfMonthMs(year, month + 1)
    return await this.database.getStarEventsInRange(startMs, endMs)
  }

  /**
   * 取全部历史星事件的累计星星总数
   * - MVP 阶段走 client-side 聚合: getStarEventsSince(0) + aggregateEvents
   * - 长生命周期用户后续可切 SQL SUM(stars) 单值查询
   */
  async getAllTimeStarTotal(): Promise<number> {
    const events = await this.database.getStarEventsSince(0)
    const summary = this.aggregateEvents(events)
    return summary.total
  }

  private aggregateEvents(events: StarEventRow[]): TodayStarSummary {
    const summary = createEmptyTodayStarSummary()
    for (let i = 0; i < events.length; i++) {
      const event = events[i]
      const type = event.activityType as StarActivityType
      // 跳过非 StarActivityType 联合的未知类型（如旧版本数据库中的脏数据）
      if (STAR_ACTIVITY_TYPES.indexOf(type) < 0) {
        continue
      }
      const bucket: StarTypeBucket = getBucketFromSummary(summary, type)
      bucket.count += 1
      if (event.stars > 0) {
        bucket.stars += event.stars
        summary.total += event.stars
      }
    }
    return summary
  }
}

export function getStarRewardService(): StarRewardService {
  return StarRewardService.getInstance()
}
