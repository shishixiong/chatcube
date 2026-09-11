import { describe, it, expect } from '@ohos/hypium'
import { getStartOfWeekMs } from '../../../../main/ets/utils/DateFormatUtils'

/**
 * getStartOfWeekMs 单元测试
 *
 * 语义: 返回 timestamp 所在自然周（ISO, 周一为一周之始）的本地 00:00:00.000 时间戳。
 * 供儿童主屏「本周 +N 星星」徽章查询周一起点。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

export default function dateFormatUtilsTest() {
  describe('getStartOfWeekMs', () => {
    it('wednesday midday rolls back to monday 00:00 same week', 0, () => {
      // 2026-09-09 是周三
      const wed = new Date(2026, 8, 9, 14, 30, 15, 500).getTime()
      const expected = new Date(2026, 8, 7, 0, 0, 0, 0).getTime()
      expect(getStartOfWeekMs(wed)).assertEqual(expected)
    })

    it('monday 00:00:00.000 returns itself', 0, () => {
      // 2026-09-07 是周一
      const mon = new Date(2026, 8, 7, 0, 0, 0, 0).getTime()
      expect(getStartOfWeekMs(mon)).assertEqual(mon)
    })

    it('monday early morning stays on same monday', 0, () => {
      const mon = new Date(2026, 8, 7, 6, 15, 0, 0).getTime()
      const expected = new Date(2026, 8, 7, 0, 0, 0, 0).getTime()
      expect(getStartOfWeekMs(mon)).assertEqual(expected)
    })

    it('sunday rolls back 6 days to monday', 0, () => {
      // 2026-09-13 是周日, 所在周周一为 09-07
      const sun = new Date(2026, 8, 13, 23, 59, 59, 999).getTime()
      const expected = new Date(2026, 8, 7, 0, 0, 0, 0).getTime()
      expect(getStartOfWeekMs(sun)).assertEqual(expected)
    })

    it('crosses month boundary correctly (friday 2026-10-02 → monday 2026-09-28)', 0, () => {
      const fri = new Date(2026, 9, 2, 9, 0, 0, 0).getTime()
      const expected = new Date(2026, 8, 28, 0, 0, 0, 0).getTime()
      expect(getStartOfWeekMs(fri)).assertEqual(expected)
    })

    it('crosses year boundary correctly (thursday 2026-01-01 → monday 2025-12-29)', 0, () => {
      const thu = new Date(2026, 0, 1, 12, 0, 0, 0).getTime()
      const expected = new Date(2025, 11, 29, 0, 0, 0, 0).getTime()
      expect(getStartOfWeekMs(thu)).assertEqual(expected)
    })

    it('result is always local midnight (hours/min/sec/ms all zero)', 0, () => {
      const sat = new Date(2026, 8, 12, 18, 42, 7, 123).getTime()
      const result = new Date(getStartOfWeekMs(sat))
      expect(result.getHours()).assertEqual(0)
      expect(result.getMinutes()).assertEqual(0)
      expect(result.getSeconds()).assertEqual(0)
      expect(result.getMilliseconds()).assertEqual(0)
    })
  })
}
