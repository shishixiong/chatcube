import { describe, it, expect } from '@ohos/hypium'
import {
  numberBondSplitReady, numberBondSplits,
  numberBondScaffold, numberBondStepTitles, numberBondStepNarrations,
  NumberBondSplit, NumberBondScaffoldLine
} from '../../../../main/ets/utils/MathTeachNumberBond'

/**
 * MathTeachNumberBond 单元测试
 *
 * 覆盖分好判定 / 有序分法枚举 / 脚手架 / 标题与口播稿。
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

export default function mathTeachNumberBondTest() {
  describe('mathTeachNumberBond', () => {
    it('splitReady_堆空且两盘非空才成立', 0, () => {
      expect(numberBondSplitReady(0, 2, 3)).assertTrue()
      expect(numberBondSplitReady(1, 2, 2) === false).assertTrue()
      expect(numberBondSplitReady(0, 0, 5) === false).assertTrue()
      expect(numberBondSplitReady(0, 5, 0) === false).assertTrue()
      expect(numberBondSplitReady(0, 0, 0) === false).assertTrue()
    })

    it('splits_5共6种_有序且恒和为total', 0, () => {
      const arr: NumberBondSplit[] = numberBondSplits(5)
      expect(arr.length === 6).assertTrue()
      expect(arr[0].left === 0 && arr[0].right === 5).assertTrue()
      expect(arr[2].left === 2 && arr[2].right === 3).assertTrue()
      expect(arr[5].left === 5 && arr[5].right === 0).assertTrue()
      for (let i = 0; i < arr.length; i++) {
        expect(arr[i].left + arr[i].right === 5).assertTrue()
      }
    })

    it('splits_边界防御_1与越界', 0, () => {
      const one: NumberBondSplit[] = numberBondSplits(1)
      expect(one.length === 2).assertTrue()
      const big: NumberBondSplit[] = numberBondSplits(99)
      expect(big.length === 11).assertTrue()
      expect(big[10].left === 10 && big[10].right === 0).assertTrue()
    })

    it('scaffold_4行_分合两行取左右盘', 0, () => {
      const lines: NumberBondScaffoldLine[] = numberBondScaffold(5, 2, 3)
      expect(lines.length === 4).assertTrue()
      expect(lines[0].eq === '5' && lines[0].label === '整体').assertTrue()
      expect(lines[1].eq === '5 = 2 + 3' && lines[1].label === '分').assertTrue()
      expect(lines[2].eq === '2 + 3 = 5' && lines[2].label === '合').assertTrue()
      expect(lines[3].eq === '5 的 6 种分法' && lines[3].label === '有序').assertTrue()
    })

    it('titles与narrations_各4条_含total', 0, () => {
      const titles: string[] = numberBondStepTitles(5)
      const narr: string[] = numberBondStepNarrations(5)
      expect(titles.length === 4).assertTrue()
      expect(narr.length === 4).assertTrue()
      expect(titles[1] === '把 5 分成两堆').assertTrue()
      expect(titles[3] === '5 一共有几种分法？').assertTrue()
      expect(narr[1].indexOf('5') >= 0).assertTrue()
      expect(narr[3].indexOf('5') >= 0).assertTrue()
    })
  })
}
