import { describe, it, expect } from '@ohos/hypium'
import {
  clockAngles, balanceTilt, barPercents, numberLineHops, bondSplit, canBundle,
  ClockAngles, BarPercents, NumberLineHops
} from '../../../../main/ets/utils/MathTeachBoards'

/**
 * MathTeachBoards 单元测试
 *
 * 覆盖钟面角度 / 天平倾角 / 条形图百分比 / 数线凑十跳 / 数的分解 / 捆绑判定。
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
    it('barPercents_按和归一', 0, () => {
      const p: BarPercents = barPercents(9, 5)
      expect(p.aPct === 64).assertTrue()
      expect(p.bPct === 36).assertTrue()
    })
    it('barPercents_零和防御', 0, () => {
      const p: BarPercents = barPercents(0, 0)
      expect(p.aPct === 0 && p.bPct === 0).assertTrue()
    })
    it('numberLineHops_9加5先跳1再跳4', 0, () => {
      const h: NumberLineHops = numberLineHops(9, 5)
      expect(h.firstHop === 1 && h.secondHop === 4 && h.sum === 14).assertTrue()
    })
    it('numberLineHops_6加7先跳4再跳3', 0, () => {
      const h: NumberLineHops = numberLineHops(6, 7)
      expect(h.firstHop === 4 && h.secondHop === 3 && h.sum === 13).assertTrue()
    })
    it('numberLineHops_secondHop负数取0兜底', 0, () => {
      const h: NumberLineHops = numberLineHops(9, 1)
      expect(h.firstHop === 1 && h.secondHop === 0 && h.sum === 10).assertTrue()
    })
    it('bondSplit_越界取0或total', 0, () => {
      expect(bondSplit(9, 4) === 5).assertTrue()
      expect(bondSplit(9, -1) === 9).assertTrue()
      expect(bondSplit(9, 12) === 0).assertTrue()
    })
    it('canBundle_满10才捆', 0, () => {
      expect(canBundle(10)).assertTrue()
      expect(canBundle(9) === false).assertTrue()
    })
  })
}
