import { describe, it, expect } from '@ohos/hypium'
import { getWeeklyTrendService } from '../../../../main/ets/services/ServiceRegistry'
import { WeeklyTrend } from '../../../../main/ets/models/TeachingReflectionModels'

export default function weeklyTrendGetByIdTest() {
  describe('WeeklyTrendService.getTrendById', () => {
    it('returns null for empty id', 0, async () => {
      const result = await getWeeklyTrendService().getTrendById('')
      expect(result).assertNull()
    })

    it('returns null for malformed id (not wt_ prefix)', 0, async () => {
      const result = await getWeeklyTrendService().getTrendById('xx_20260616')
      expect(result).assertNull()
    })

    it('returns null for short id', 0, async () => {
      const result = await getWeeklyTrendService().getTrendById('wt_2026')
      expect(result).assertNull()
    })

    it('returns null when DB has no row for parsed weekStartYMD', 0, async () => {
      // wt_20260101 → 2026-01-01
      const result = await getWeeklyTrendService().getTrendById('wt_20260101')
      expect(result).assertNull()
    })
  })
}
