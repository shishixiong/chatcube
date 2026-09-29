import { describe, it, expect } from '@ohos/hypium'
import { clockAngles, balanceTilt, bondSplit, ClockAngles } from '../../../../main/ets/utils/MathTeachBoards'

/**
 * MathTeachBoards 单元测试
 *
 * 覆盖钟面角度 / 天平倾角 / 数的分解。
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

export default function mathTeachBoardsTest() {
  describe('mathTeachBoards', () => {
    it('clockAngles_9点30分', 0, () => {
      const a: ClockAngles = clockAngles(9, 30)
      expect(a.hourDeg === 285).assertTrue()
      expect(a.minuteDeg === 180).assertTrue()
    })
    it('clockAngles_12点整归零', 0, () => {
      const a: ClockAngles = clockAngles(12, 0)
      expect(a.hourDeg === 0).assertTrue()
      expect(a.minuteDeg === 0).assertTrue()
    })
    it('balanceTilt_±12截断', 0, () => {
      expect(balanceTilt(9, 5) === -12).assertTrue()
      expect(balanceTilt(5, 9) === 12).assertTrue()
      expect(balanceTilt(5, 6) === 4).assertTrue()
      expect(balanceTilt(5, 5) === 0).assertTrue()
    })
    it('bondSplit_越界取0或total', 0, () => {
      expect(bondSplit(9, 4) === 5).assertTrue()
      expect(bondSplit(9, -1) === 9).assertTrue()
      expect(bondSplit(9, 12) === 0).assertTrue()
    })
  })
}
