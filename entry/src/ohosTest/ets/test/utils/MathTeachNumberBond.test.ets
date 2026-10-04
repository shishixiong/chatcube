import { describe, it, expect } from '@ohos/hypium'
import {
  numberBondBestSplit, numberBondScaffold,
  numberBondStepTitles, numberBondStepTips, numberBondStepNarrations,
  NumberBondSplit, NumberBondScaffoldLine
} from '../../../../main/ets/utils/MathTeachNumberBond'

/**
 * MathTeachNumberBond 单元测试（v2 两步演示课）
 *
 * 覆盖推荐分法（整十+剩余 / 5 锚定 / 对半）/ 边界防御 / 脚手架 / 标题与口播稿。
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

export default function mathTeachNumberBondTest() {
  describe('mathTeachNumberBond', () => {
    it('bestSplit_两位数按整十加剩余', 0, () => {
      const a: NumberBondSplit = numberBondBestSplit(28)
      expect(a.left === 20 && a.right === 8).assertTrue()
      const b: NumberBondSplit = numberBondBestSplit(45)
      expect(b.left === 40 && b.right === 5).assertTrue()
      const c: NumberBondSplit = numberBondBestSplit(11)
      expect(c.left === 10 && c.right === 1).assertTrue()
      const d: NumberBondSplit = numberBondBestSplit(99)
      expect(d.left === 90 && d.right === 9).assertTrue()
    })

    it('bestSplit_整十数拆10和剩余', 0, () => {
      const a: NumberBondSplit = numberBondBestSplit(20)
      expect(a.left === 10 && a.right === 10).assertTrue()
      const b: NumberBondSplit = numberBondBestSplit(30)
      expect(b.left === 20 && b.right === 10).assertTrue()
    })

    it('bestSplit_6到10按5锚定', 0, () => {
      const a: NumberBondSplit = numberBondBestSplit(9)
      expect(a.left === 5 && a.right === 4).assertTrue()
      const b: NumberBondSplit = numberBondBestSplit(10)
      expect(b.left === 5 && b.right === 5).assertTrue()
      const c: NumberBondSplit = numberBondBestSplit(6)
      expect(c.left === 5 && c.right === 1).assertTrue()
      const d: NumberBondSplit = numberBondBestSplit(8)
      expect(d.left === 5 && d.right === 3).assertTrue()
    })

    it('bestSplit_2到5对半', 0, () => {
      const a: NumberBondSplit = numberBondBestSplit(2)
      expect(a.left === 1 && a.right === 1).assertTrue()
      const b: NumberBondSplit = numberBondBestSplit(3)
      expect(b.left === 1 && b.right === 2).assertTrue()
      const c: NumberBondSplit = numberBondBestSplit(4)
      expect(c.left === 2 && c.right === 2).assertTrue()
      const d: NumberBondSplit = numberBondBestSplit(5)
      expect(d.left === 2 && d.right === 3).assertTrue()
    })

    it('bestSplit_恒和为total且两边非空', 0, () => {
      for (let t = 2; t <= 99; t++) {
        const s: NumberBondSplit = numberBondBestSplit(t)
        expect(s.left + s.right === t).assertTrue()
        expect(s.left >= 1 && s.right >= 1).assertTrue()
      }
    })

    it('bestSplit_防御取界_小数截断小数取整', 0, () => {
      const low: NumberBondSplit = numberBondBestSplit(1)
      expect(low.left + low.right === 2).assertTrue()
      const high: NumberBondSplit = numberBondBestSplit(100)
      expect(high.left === 90 && high.right === 9).assertTrue()
      const frac: NumberBondSplit = numberBondBestSplit(28.7)
      expect(frac.left === 20 && frac.right === 8).assertTrue()
    })

    it('scaffold_3行_整体分合', 0, () => {
      const lines: NumberBondScaffoldLine[] = numberBondScaffold(28, 20, 8)
      expect(lines.length === 3).assertTrue()
      expect(lines[0].eq === '28' && lines[0].label === '整体').assertTrue()
      expect(lines[1].eq === '28 = 20 + 8' && lines[1].label === '分').assertTrue()
      expect(lines[2].eq === '20 + 8 = 28' && lines[2].label === '合').assertTrue()
    })

    it('titles与narrations_各2条_含推荐分法数字', 0, () => {
      const titles: string[] = numberBondStepTitles(28)
      const tips: string[] = numberBondStepTips(28)
      const narr: string[] = numberBondStepNarrations(28)
      expect(titles.length === 2).assertTrue()
      expect(tips.length === 2).assertTrue()
      expect(narr.length === 2).assertTrue()
      expect(titles[0] === '把 28 分一分').assertTrue()
      expect(titles[1] === '把 20 和 8 合起来').assertTrue()
      expect(tips[0].indexOf('20') >= 0 && tips[0].indexOf('8') >= 0).assertTrue()
      expect(narr[1].indexOf('20') >= 0 && narr[1].indexOf('28') >= 0).assertTrue()
    })
  })
}
