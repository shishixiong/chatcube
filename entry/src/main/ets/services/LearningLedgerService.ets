/**
 * LearningLedgerService - 词汇台账核心服务 (spec §5)
 *
 * 单例, 与 ImageIndexService 同构: 薄服务层 + CRUD 全在 DatabaseService。
 * 铁律: 任何失败都静默降级 (record/check 失败 → 放行/忽略), 绝不阻断出题与教学。
 *
 * 写入: recordServed (出题曝光) / recordAnswer (作答→掌握度) / upsertPlanItems (计划种子)
 * 读取: buildSummary (三名单+高频, 60s 缓存) / checkRepeat (门禁探针) / getTopRepeated / getMasteredCount
 * 会话内环形缓冲: 每 session 最近 20 条 {itemKey, mode}, 供 SESSION_GAP_ITEMS=5 间隔判定 (内存, 随进程销毁)
 */
import { hilog } from '@kit.PerformanceAnalysisKit'
import { getDatabaseService, DatabaseService } from './DatabaseService'
import {
  LearningItem,
  LedgerAnswerItem,
  LedgerEventInsert,
  LedgerItemSeed,
  LedgerRecord,
  LedgerSummary,
  DueReviewHint,
  RepeatCheck,
  RepeatPolicyInput,
  RepeatStat,
  createEmptyLedgerSummary,
  computeMasteryTransition,
  SUMMARY_CACHE_TTL_MS,
  SAME_MODE_COOLDOWN_MS,
  SESSION_GAP_ITEMS,
  TOP_REPEATED_WINDOW_MS,
  EVENT_RETENTION_MS,
  RECENT_WINDOW_CAPACITY,
  RECENT_SESSION_PRUNE_MAX
} from '../models/LearningLedgerModels'
import { normalizeItemKey } from '../utils/LedgerExtractUtils'
import { evaluateRepeatPolicy } from '../utils/VocabRepeatValidation'

const DOMAIN = 0x0000
const TAG = 'LearningLedgerService'

interface CachedSummary {
  summary: LedgerSummary
  expiresAt: number
}

interface LedgerRecentEntry {
  itemKey: string
  mode: string
  servedAt: number
}

export class LearningLedgerService {
  private static instance: LearningLedgerService | null = null
  private summaryCache: Map<string, CachedSummary> = new Map()
  private recentServedBySession: Map<string, LedgerRecentEntry[]> = new Map()
  private recentSessionOrder: string[] = []

  private constructor() {
  }

  static getInstance(): LearningLedgerService {
    if (LearningLedgerService.instance === null) {
      LearningLedgerService.instance = new LearningLedgerService()
    }
    return LearningLedgerService.instance
  }

  private get databaseService(): DatabaseService {
    return getDatabaseService()
  }

  /** 启动清理 >90 天事件流水 (spec §7.1 跨会话统计窗口), 失败静默 */
  async initialize(): Promise<void> {
    try {
      const cutoff = Date.now() - EVENT_RETENTION_MS
      await this.databaseService.deleteLedgerEventsBefore(cutoff)
      hilog.info(DOMAIN, TAG, 'initialized (events pruned)')
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `initialize failed (ignored): ${String(error)}`)
    }
  }

  /**
   * 出题曝光登记 (spec §6): 主表 upsert + 事件流水 + 会话环。
   * recordServed 累加 exposureCount / 更新 lastSeenAt / lastMode / modesSeen; 不动掌握度。
   */
  async recordServed(input: LedgerRecord): Promise<void> {
    this.pushRecentServed(input.sessionId, input.itemKey, input.mode, input.now)
    try {
      const existing = await this.databaseService.findLearningItemByKey(input.itemKey)
      let item: LearningItem
      if (existing === null) {
        item = new LearningItem()
        item.itemKey = input.itemKey
        item.subject = input.subject
        item.itemType = input.itemType
        item.display = input.display
        item.skillKey = input.skillKey
        item.firstTaughtAt = input.now
        item.lastSeenAt = input.now
        item.exposureCount = 1
        item.modesSeen = [input.mode]
        item.lastMode = input.mode
        item.lastSessionId = input.sessionId
        item.source = 'session'
        item.createdAt = input.now
        item.updatedAt = input.now
      } else {
        item = existing
        item.lastSeenAt = input.now
        item.exposureCount = item.exposureCount + 1
        item.lastMode = input.mode
        item.lastSessionId = input.sessionId
        if (item.display === '') {
          item.display = input.display
        }
        if (item.modesSeen.indexOf(input.mode) < 0) {
          item.modesSeen.push(input.mode)
        }
        item.updatedAt = input.now
      }
      await this.databaseService.upsertLearningItem(item)
      const event: LedgerEventInsert = {
        id: `lie_${input.now}_${Math.floor(Math.random() * 100000)}`,
        itemKey: input.itemKey,
        sessionId: input.sessionId,
        mode: input.mode,
        toolId: input.toolId,
        servedAt: input.now,
        display: input.display
      }
      await this.databaseService.insertLearningItemEvent(event)
      this.invalidateSummaryCache(input.subject)
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `recordServed failed (ignored): ${String(error)}`)
    }
  }

  /**
   * 作答对账 (spec §5.3): 每项走 computeMasteryTransition, 更新主表 + 回填最近一条未答事件。
   * 多项 (matching_pairs) 一次传入。台账无此行时跳过 (计划 seed 未被考过属正常)。
   */
  async recordAnswer(items: LedgerAnswerItem[], now: number): Promise<void> {
    try {
      for (let i = 0; i < items.length; i++) {
        const answer = items[i]
        const row = await this.databaseService.findLearningItemByKey(answer.itemKey)
        if (row === null) {
          continue
        }
        const transition = computeMasteryTransition(row.mastery, row.consecutiveCorrect, answer.isCorrect, now)
        if (answer.isCorrect) {
          row.correctCount = row.correctCount + 1
        } else {
          row.wrongCount = row.wrongCount + 1
        }
        row.mastery = transition.mastery
        row.consecutiveCorrect = transition.consecutiveCorrect
        row.nextReviewAt = transition.nextReviewAt
        if (transition.justMastered) {
          row.masteredAt = now
        }
        row.updatedAt = now
        await this.databaseService.upsertLearningItem(row)
        await this.databaseService.updateLatestOpenLedgerEvent(answer.itemKey, now, answer.isCorrect)
        this.invalidateSummaryCache(row.subject)
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `recordAnswer failed (ignored): ${String(error)}`)
    }
  }

  /** 计划侧种子 (spec §6.1): 只建缺失行 (source=plan), 不改已有行的掌握度/曝光 */
  async upsertPlanItems(items: LedgerItemSeed[], now: number): Promise<void> {
    try {
      for (let i = 0; i < items.length; i++) {
        const seed = items[i]
        const key = normalizeItemKey(seed.subject, seed.itemType, seed.display)
        if (key === '') {
          continue
        }
        const existing = await this.databaseService.findLearningItemByKey(key)
        if (existing !== null) {
          continue
        }
        const item = new LearningItem()
        item.itemKey = key
        item.subject = seed.subject
        item.itemType = seed.itemType
        item.display = seed.display
        item.skillKey = seed.skillKey
        item.firstTaughtAt = now
        item.lastSeenAt = now
        item.source = 'plan'
        item.createdAt = now
        item.updatedAt = now
        await this.databaseService.insertLearningItem(item)
        this.invalidateSummaryCache(seed.subject)
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `upsertPlanItems failed (ignored): ${String(error)}`)
    }
  }

  /** 三名单 + 近 7 天高频 (spec §7), 60s 缓存; 失败返回空 summary (prompt 段自动省略) */
  async buildSummary(subject: string, now: number): Promise<LedgerSummary> {
    const cached = this.summaryCache.get(subject)
    if (cached !== undefined && cached.expiresAt > now) {
      return cached.summary
    }
    try {
      const summary = createEmptyLedgerSummary()
      const newItems = await this.databaseService.queryLedgerNewPool(subject, 12)
      summary.newPool = newItems.map((item: LearningItem) => item.display)
      const dueItems = await this.databaseService.queryLedgerDueReview(subject, now, 12)
      const hints: DueReviewHint[] = []
      for (let i = 0; i < dueItems.length; i++) {
        const row = dueItems[i]
        const hint: DueReviewHint = {
          display: row.display,
          lastMode: row.lastMode,
          dueInMs: Math.max(0, row.nextReviewAt - now)
        }
        hints.push(hint)
      }
      summary.dueReview = hints
      const masteredItems = await this.databaseService.queryLedgerMastered(subject, 12)
      summary.mastered = masteredItems.map((item: LearningItem) => item.display)
      const coolingItems = await this.databaseService.queryLedgerCooling(subject, now - SAME_MODE_COOLDOWN_MS, 12)
      summary.cooling = coolingItems.map((item: LearningItem) => item.display)
      summary.topRepeated =
        await this.databaseService.getTopRepeatedEvents(`${subject}:%`, now - TOP_REPEATED_WINDOW_MS, 8)
      const entry: CachedSummary = { summary: summary, expiresAt: now + SUMMARY_CACHE_TTL_MS }
      this.summaryCache.set(subject, entry)
      hilog.info(DOMAIN, TAG, `Ledger stats: subject=${subject}, new=${summary.newPool.length}, ` +
        `due=${summary.dueReview.length}, cooling=${summary.cooling.length}, ` +
        `mastered=${summary.mastered.length}, topRepeat=${summary.topRepeated.length}`)
      return summary
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `buildSummary failed (empty): ${String(error)}`)
      return createEmptyLedgerSummary()
    }
  }

  /**
   * 门禁探针 (spec §9): 收集 DB 行状态 + 会话环, 交给 evaluateRepeatPolicy 纯函数判定。
   * 任何异常 → 放行 (allowed), 台账故障绝不拦题。
   */
  async checkRepeat(sessionId: string, itemKey: string, mode: string, purpose: string,
    now: number, display: string): Promise<RepeatCheck> {
    const allowed: RepeatCheck = { allowed: true, reason: '', itemKey: itemKey, display: display }
    try {
      const row = await this.databaseService.findLearningItemByKey(itemKey)
      const input: RepeatPolicyInput = {
        purpose: purpose,
        mode: mode,
        now: now,
        found: row !== null,
        lastSeenAt: row !== null ? row.lastSeenAt : 0,
        lastMode: row !== null ? row.lastMode : '',
        mastery: row !== null ? row.mastery : 0,
        nextReviewAt: row !== null ? row.nextReviewAt : 0,
        inSessionGap: this.isInSessionGap(sessionId, itemKey),
        itemKey: itemKey,
        display: display
      }
      return evaluateRepeatPolicy(input)
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `checkRepeat failed (allow): ${String(error)}`)
      return allowed
    }
  }

  async getTopRepeated(subject: string, sinceMs: number, limit: number): Promise<RepeatStat[]> {
    try {
      return await this.databaseService.getTopRepeatedEvents(`${subject}:%`, sinceMs, limit)
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `getTopRepeated failed: ${String(error)}`)
      const empty: RepeatStat[] = []
      return empty
    }
  }

  async getMasteredCount(subject: string): Promise<number> {
    try {
      return await this.databaseService.countLedgerMastered(subject)
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `getMasteredCount failed: ${String(error)}`)
      return 0
    }
  }

  // ---------- 会话内近期出题环形缓冲 (内存) ----------

  private pushRecentServed(sessionId: string, itemKey: string, mode: string, servedAt: number): void {
    if (sessionId === '') {
      return
    }
    let ring = this.recentServedBySession.get(sessionId)
    if (ring === undefined) {
      ring = []
      this.recentServedBySession.set(sessionId, ring)
      this.recentSessionOrder.push(sessionId)
      if (this.recentSessionOrder.length > RECENT_SESSION_PRUNE_MAX) {
        const oldest = this.recentSessionOrder.shift()
        if (oldest !== undefined) {
          this.recentServedBySession.delete(oldest)
        }
      }
    }
    const entry: LedgerRecentEntry = { itemKey: itemKey, mode: mode, servedAt: servedAt }
    ring.push(entry)
    if (ring.length > RECENT_WINDOW_CAPACITY) {
      ring.shift()
    }
  }

  /** 最近 SESSION_GAP_ITEMS(5) 题内是否出现过该 item (spec §7.1 会话间隔, 任何 purpose 生效) */
  private isInSessionGap(sessionId: string, itemKey: string): boolean {
    if (sessionId === '') {
      return false
    }
    const ring = this.recentServedBySession.get(sessionId)
    if (ring === undefined || ring.length === 0) {
      return false
    }
    const checkCount = Math.min(SESSION_GAP_ITEMS, ring.length)
    for (let i = 0; i < checkCount; i++) {
      const entry = ring[ring.length - 1 - i]
      if (entry.itemKey === itemKey) {
        return true
      }
    }
    return false
  }

  private invalidateSummaryCache(subject: string): void {
    this.summaryCache.delete(subject)
  }
}

export function getLearningLedgerService(): LearningLedgerService {
  return LearningLedgerService.getInstance()
}
