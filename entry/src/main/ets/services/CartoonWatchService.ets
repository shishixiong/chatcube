/**
 * 动画片观看额度服务（spec 2026-11-10 §5）。
 *
 * - 今日/本次秒数存 Preferences，每 10 秒节流落盘
 * - 单次 pending 守卫 + 3 秒冷却守卫（防 LLM 同一轮发两个 play_cartoon 自动连播）
 */

import {
  CARTOON_PERSIST_INTERVAL_MS,
  CARTOON_MIN_GAP_MS,
  CartoonQuotaState,
  CartoonQuotaSnapshot,
  CartoonStartDecision
} from '../models/CartoonModels'
import {
  buildQuotaSnapshot,
  decideCartoonStart,
  refreshQuota
} from '../utils/CartoonQuotaMath'
import { getPreferencesService, PreferenceKeys } from './PreferencesService'

export class CartoonWatchService {
  private static instance: CartoonWatchService | null = null
  private state: CartoonQuotaState = {
    dayKey: '',
    dayMs: 0,
    sessionMs: 0,
    lastActivityMs: 0
  }
  private initialized: boolean = false
  private lastPersistMs: number = 0
  private pendingToolCallId: string = ''
  private lastPlaybackEndedAtMs: number = 0

  static getInstance(): CartoonWatchService {
    if (CartoonWatchService.instance === null) {
      CartoonWatchService.instance = new CartoonWatchService()
    }
    return CartoonWatchService.instance
  }

  async initialize(): Promise<void> {
    if (this.initialized) {
      return
    }
    try {
      const prefs = getPreferencesService()
      const dayKey = await prefs.getString(PreferenceKeys.CARTOON_WATCH_DAY, '')
      const dayMs = await prefs.getNumber(PreferenceKeys.CARTOON_WATCH_DAY_MS, 0)
      const sessionMs = await prefs.getNumber(PreferenceKeys.CARTOON_WATCH_SESSION_MS, 0)
      const lastActivityMs = await prefs.getNumber(PreferenceKeys.CARTOON_WATCH_LAST_ACTIVITY_MS, 0)
      const loaded: CartoonQuotaState = {
        dayKey: dayKey,
        dayMs: dayMs > 0 ? dayMs : 0,
        sessionMs: sessionMs > 0 ? sessionMs : 0,
        lastActivityMs: lastActivityMs > 0 ? lastActivityMs : 0
      }
      this.state = loaded
    } catch (error) {
      console.error('CartoonWatchService', `initialize failed: ${JSON.stringify(error)}`)
      this.state = { dayKey: '', dayMs: 0, sessionMs: 0, lastActivityMs: 0 }
    }
    this.initialized = true
  }

  private async ensureInitialized(): Promise<void> {
    if (!this.initialized) {
      await this.initialize()
    }
  }

  async snapshot(nowMs?: number): Promise<CartoonQuotaSnapshot> {
    await this.ensureInitialized()
    const now = nowMs !== undefined ? nowMs : Date.now()
    const fresh = refreshQuota(this.state, now)
    if (fresh !== this.state) {
      this.state = fresh
      await this.persist()
    }
    return buildQuotaSnapshot(this.state, now)
  }

  async decideStart(durationMs: number): Promise<CartoonStartDecision> {
    const snapshot = await this.snapshot()
    return decideCartoonStart(durationMs, snapshot)
  }

  async addWatched(deltaMs: number): Promise<void> {
    if (deltaMs <= 0) {
      return
    }
    await this.ensureInitialized()
    const now = Date.now()
    const fresh = refreshQuota(this.state, now)
    const next: CartoonQuotaState = {
      dayKey: fresh.dayKey,
      dayMs: fresh.dayMs + deltaMs,
      sessionMs: fresh.sessionMs + deltaMs,
      lastActivityMs: now
    }
    this.state = next
    if (now - this.lastPersistMs >= CARTOON_PERSIST_INTERVAL_MS) {
      this.lastPersistMs = now
      await this.persist()
    }
  }

  async flush(): Promise<void> {
    await this.ensureInitialized()
    this.lastPersistMs = Date.now()
    await this.persist()
  }

  private async persist(): Promise<void> {
    try {
      const prefs = getPreferencesService()
      await prefs.setString(PreferenceKeys.CARTOON_WATCH_DAY, this.state.dayKey)
      await prefs.setNumber(PreferenceKeys.CARTOON_WATCH_DAY_MS, this.state.dayMs)
      await prefs.setNumber(PreferenceKeys.CARTOON_WATCH_SESSION_MS, this.state.sessionMs)
      await prefs.setNumber(PreferenceKeys.CARTOON_WATCH_LAST_ACTIVITY_MS, this.state.lastActivityMs)
    } catch (error) {
      console.error('CartoonWatchService', `persist failed: ${JSON.stringify(error)}`)
    }
  }

  beginPending(toolCallId: string): boolean {
    if (this.pendingToolCallId !== '') {
      return false
    }
    this.pendingToolCallId = toolCallId
    return true
  }

  endPending(toolCallId: string): void {
    if (this.pendingToolCallId === toolCallId) {
      this.pendingToolCallId = ''
    }
  }

  hasPendingPlayback(): boolean {
    return this.pendingToolCallId !== ''
  }

  canStartNewEpisode(nowMs?: number): boolean {
    const now = nowMs !== undefined ? nowMs : Date.now()
    return now - this.lastPlaybackEndedAtMs >= CARTOON_MIN_GAP_MS
  }

  markPlaybackEnded(nowMs?: number): void {
    this.lastPlaybackEndedAtMs = nowMs !== undefined ? nowMs : Date.now()
  }
}

export function getCartoonWatchService(): CartoonWatchService {
  return CartoonWatchService.getInstance()
}
