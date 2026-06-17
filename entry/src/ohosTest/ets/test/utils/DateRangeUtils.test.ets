import { describe, it, expect } from '@ohos/hypium'
import {
  isWithinHistoryRange,
  canGoBack,
  canGoForward,
  todayYMD,
  shiftYMD
} from '../../../../main/ets/utils/DateRangeUtils'

const NOW_MS: number = new Date('2026-06-17T10:00:00').getTime()
const TODAY: string = '2026-06-17'

export default function dateRangeUtilsTest() {
  describe('isWithinHistoryRange', () => {
    it('returns true for today', 0, () => {
      expect(isWithinHistoryRange(TODAY, NOW_MS)).assertTrue()
    })
    it('returns true for 14 days ago', 0, () => {
      expect(isWithinHistoryRange('2026-06-03', NOW_MS)).assertTrue()
    })
    it('returns false for 15 days ago', 0, () => {
      expect(isWithinHistoryRange('2026-06-02', NOW_MS)).assertFalse()
    })
    it('returns false for future date', 0, () => {
      expect(isWithinHistoryRange('2026-06-18', NOW_MS)).assertFalse()
    })
  })

  describe('canGoBack', () => {
    it('true when more than 14 days old', 0, () => {
      expect(canGoBack('2026-06-03', NOW_MS)).assertTrue()
    })
    it('false when today', 0, () => {
      expect(canGoBack(TODAY, NOW_MS)).assertFalse()
    })
  })

  describe('canGoForward', () => {
    it('true when before today', 0, () => {
      expect(canGoForward('2026-06-16', NOW_MS)).assertTrue()
    })
    it('false when today', 0, () => {
      expect(canGoForward(TODAY, NOW_MS)).assertFalse()
    })
    it('false when future', 0, () => {
      expect(canGoForward('2026-06-18', NOW_MS)).assertFalse()
    })
  })

  describe('todayYMD', () => {
    it('returns YYYY-MM-DD format', 0, () => {
      const ymd = todayYMD(NOW_MS)
      expect(ymd).assertEqual('2026-06-17')
    })
  })

  describe('shiftYMD', () => {
    it('shifts forward by 1 day', 0, () => {
      expect(shiftYMD('2026-06-17', 1)).assertEqual('2026-06-18')
    })
    it('shifts backward by 1 day', 0, () => {
      expect(shiftYMD('2026-06-17', -1)).assertEqual('2026-06-16')
    })
    it('crosses month boundary', 0, () => {
      expect(shiftYMD('2026-06-01', -1)).assertEqual('2026-05-31')
    })
    it('crosses year boundary', 0, () => {
      expect(shiftYMD('2026-01-01', -1)).assertEqual('2025-12-31')
    })
  })
}