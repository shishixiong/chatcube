import { describe, it, expect } from '@ohos/hypium'
import {
  CARTOON_SESSION_LIMIT_MS, CARTOON_DAILY_LIMIT_MS, CARTOON_SESSION_IDLE_RESET_MS,
  CartoonEntry, CartoonQuotaState
} from '../../../../main/ets/models/CartoonModels'
import {
  formatDayKey, refreshQuota, buildQuotaSnapshot, decideCartoonStart,
  buildPlaybackResult, formatDurationSeconds, evaluatePreparedDuration
} from '../../../../main/ets/utils/CartoonQuotaMath'

const NOW = new Date(2026, 10, 10, 10, 0, 0).getTime()
const SIX_MIN = 6 * 60 * 1000

function state(dayMs: number, sessionMs: number, dayKey: string, lastActivityMs: number): CartoonQuotaState {
  const s: CartoonQuotaState = {
    dayKey: dayKey, dayMs: dayMs, sessionMs: sessionMs, lastActivityMs: lastActivityMs
  }
  return s
}

function entry(durationMs: number): CartoonEntry {
  const e: CartoonEntry = {
    id: 'ct_1', uri: 'file://docs/a.mp4', title: 'A', tags: '',
    durationMs: durationMs, addedAt: 0, status: 'ok',
    seriesTitle: 'A', season: 1, episode: 1, lastWatchedAt: 0
  }
  return e
}

export default function cartoonQuotaMathTest() {
  describe('CartoonQuotaMath', () => {
    it('format_day_key_uses_local_date', 0, () => {
      expect(formatDayKey(NOW)).assertEqual('2026-11-10')
    })

    it('day_rollover_clears_day_and_session', 0, () => {
      const next = refreshQuota(state(600000, 300000, '2026-11-09', NOW - 60000), NOW)
      expect(next.dayKey).assertEqual('2026-11-10')
      expect(next.dayMs).assertEqual(0)
      expect(next.sessionMs).assertEqual(0)
      expect(next.lastActivityMs).assertEqual(0)
    })

    it('idle_30min_clears_session_only', 0, () => {
      const next = refreshQuota(state(600000, 300000, '2026-11-10', NOW - CARTOON_SESSION_IDLE_RESET_MS - 1), NOW)
      expect(next.dayMs).assertEqual(600000)
      expect(next.sessionMs).assertEqual(0)
    })

    it('idle_29min_keeps_session', 0, () => {
      const next = refreshQuota(state(600000, 300000, '2026-11-10', NOW - 29 * 60 * 1000), NOW)
      expect(next.sessionMs).assertEqual(300000)
    })

    it('four_six_minute_episodes_allowed_fifth_rejected', 0, () => {
      let s = state(0, 0, '2026-11-10', 0)
      for (let i = 0; i < 4; i++) {
        const snap = buildQuotaSnapshot(s, NOW + i * SIX_MIN)
        expect(decideCartoonStart(SIX_MIN, snap).allowed).assertTrue()
        s = state(snap.dayMs + SIX_MIN, snap.sessionMs + SIX_MIN, snap.dayKey, NOW + i * SIX_MIN)
      }
      const after = buildQuotaSnapshot(s, NOW + 4 * SIX_MIN)
      const decision = decideCartoonStart(SIX_MIN, after)
      expect(decision.allowed).assertFalse()
      expect(decision.errorCode).assertEqual('session_limit_reached')
    })

    it('daily_58min_still_allows_one_more_episode', 0, () => {
      const snap = buildQuotaSnapshot(state(58 * 60 * 1000, 0, '2026-11-10', 0), NOW)
      expect(decideCartoonStart(SIX_MIN, snap).allowed).assertTrue()
    })

    it('over_20min_video_is_too_long', 0, () => {
      const snap = buildQuotaSnapshot(state(0, 0, '2026-11-10', 0), NOW)
      expect(decideCartoonStart(CARTOON_SESSION_LIMIT_MS + 1, snap).errorCode).assertEqual('video_too_long')
      expect(decideCartoonStart(0, snap).errorCode).assertEqual('video_unavailable')
    })

    it('daily_limit_reached_blocks', 0, () => {
      const snap = buildQuotaSnapshot(state(CARTOON_DAILY_LIMIT_MS, 0, '2026-11-10', NOW), NOW)
      expect(decideCartoonStart(SIX_MIN, snap).errorCode).assertEqual('daily_limit_reached')
    })

    it('playback_result_clamps_and_converts', 0, () => {
      const snap = buildQuotaSnapshot(state(CARTOON_DAILY_LIMIT_MS + 5000, CARTOON_SESSION_LIMIT_MS + 5000,
        '2026-11-10', NOW), NOW)
      const result = buildPlaybackResult(entry(SIX_MIN), 372500, true, 'finished', snap)
      expect(result.duration_seconds).assertEqual(360)
      expect(result.watched_seconds).assertEqual(373)
      expect(result.session_budget_left_seconds).assertEqual(0)
      expect(result.daily_budget_left_seconds).assertEqual(0)
      expect(result.completed).assertTrue()
    })

    it('format_duration_pads', 0, () => {
      expect(formatDurationSeconds(372)).assertEqual('06:12')
      expect(formatDurationSeconds(59)).assertEqual('00:59')
    })

    it('prepared_duration_over_limit_aborts', 0, () => {
      const decision = evaluatePreparedDuration(25 * 60 * 1000, SIX_MIN)
      expect(decision.abort).assertTrue()
      expect(decision.errorCode).assertEqual('video_too_long')
      expect(decision.shouldUpdateEntry).assertTrue()
    })

    it('prepared_duration_drift_updates_entry', 0, () => {
      const decision = evaluatePreparedDuration(372000, 300000)
      expect(decision.abort).assertFalse()
      expect(decision.shouldUpdateEntry).assertTrue()
      expect(decision.effectiveDurationMs).assertEqual(372000)
    })

    it('prepared_duration_equal_no_update', 0, () => {
      const decision = evaluatePreparedDuration(372000, 372000)
      expect(decision.shouldUpdateEntry).assertFalse()
      expect(decision.effectiveDurationMs).assertEqual(372000)
    })

    it('prepared_duration_missing_uses_entry', 0, () => {
      const decision = evaluatePreparedDuration(0, 372000)
      expect(decision.abort).assertFalse()
      expect(decision.effectiveDurationMs).assertEqual(372000)
      expect(decision.shouldUpdateEntry).assertFalse()
    })
  })
}
