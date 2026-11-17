import { describe, it, expect } from '@ohos/hypium'
import {
  fractionIntroSteps, fractionIntroStepNarrations, fractionSectorCommands, fractionBarSegments,
  fractionReadout, fractionReadoutZh, clampFractionParts, clampFractionShaded, normalizeFractionForm,
  FractionIntroStep, BarSegment
} from '../../../../main/ets/utils/MathTeachFractionIntro'

/**
 * MathTeachFractionIntro 单元测试
 *
 * 覆盖 28 种真分数组合（分母 2–8 × 分子 1..分母−1）、扇形/分数条几何、
 * 分数读法与防御取界。
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * 本文件按 MathTeach* 惯例不注册进 List.test.ets（由人工在 IDE 中执行）
 */
export default function mathTeachFractionIntroTest() {
  describe('mathTeachFractionIntro', () => {
    it('28 种真分数组合全部 shaded 小于 parts', 0, () => {
      let combos: number = 0
      for (let parts = 2; parts <= 8; parts++) {
        for (let shaded = 1; shaded < parts; shaded++) {
          combos += 1
          expect(shaded < parts).assertTrue()
          const steps: FractionIntroStep[] = fractionIntroSteps(parts, shaded, 'pizza')
          expect(steps.length).assertEqual(2)
          expect(steps[0].title).assertEqual('平均分')
          expect(steps[1].title).assertEqual('取几份')
          expect(steps[1].chip.includes(`${shaded}/${parts}`)).assertTrue()
          expect(fractionIntroStepNarrations(parts, shaded, 'pizza').length).assertEqual(2)
          expect(fractionReadout(parts, shaded)).assertEqual(`${shaded}/${parts}`)
        }
      }
      expect(combos).assertEqual(28)
    })

    it('分数读法中文数字 1-8', 0, () => {
      expect(fractionReadoutZh(4, 3)).assertEqual('四分之三')
      expect(fractionReadoutZh(2, 1)).assertEqual('二分之一')
      expect(fractionReadoutZh(8, 7)).assertEqual('八分之七')
      expect(fractionReadoutZh(6, 5)).assertEqual('六分之五')
      expect(fractionReadoutZh(3, 1)).assertEqual('三分之一')
    })

    it('扇形命令份数与坐标落在 box 内', 0, () => {
      const box: number = 168
      for (let parts = 2; parts <= 8; parts++) {
        for (let i = 0; i < parts; i++) {
          const cmd: string = fractionSectorCommands(parts, i, box)
          expect(cmd.startsWith('M ')).assertTrue()
          expect(cmd.endsWith('Z')).assertTrue()
          expect(cmd.includes(' A ')).assertTrue()
          const matches = cmd.match(/-?\d+(\.\d+)?/g)
          expect(matches !== null).assertTrue()
          if (matches !== null) {
            for (let k = 0; k < matches.length; k++) {
              const v: number = parseFloat(matches[k])
              // 半径 / 圆心 / 端点都在 [0, box] 内（角度参数 0/1 也在范围内）
              expect(v >= -0.01 && v <= box + 0.01).assertTrue()
            }
          }
        }
      }
    })

    it('parts=2 时扇形是半圆 largeArc=0', 0, () => {
      const cmd: string = fractionSectorCommands(2, 0, 160)
      expect(cmd.includes(' 0 0 1 ')).assertTrue()
    })

    it('分数条等分数量与总宽正确', 0, () => {
      const width: number = 260
      const segs: BarSegment[] = fractionBarSegments(4, width)
      expect(segs.length).assertEqual(4)
      let sum: number = 0
      for (let i = 0; i < segs.length; i++) {
        expect(segs[i].w).assertEqual(65)
        expect(segs[i].x).assertEqual(65 * i)
        sum += segs[i].w
      }
      expect(Math.abs(sum - width) < 0.001).assertTrue()
      expect(fractionBarSegments(8, 240).length).assertEqual(8)
    })

    it('form 白名单与防御取界', 0, () => {
      expect(normalizeFractionForm('bar')).assertEqual('bar')
      expect(normalizeFractionForm('pizza')).assertEqual('pizza')
      expect(normalizeFractionForm('cake')).assertEqual('pizza')
      expect(clampFractionParts(1)).assertEqual(2)
      expect(clampFractionParts(9)).assertEqual(8)
      expect(clampFractionParts(5)).assertEqual(5)
      expect(clampFractionShaded(4, 0)).assertEqual(1)
      expect(clampFractionShaded(4, 9)).assertEqual(3)
      expect(clampFractionShaded(4, 2)).assertEqual(2)
      // 越界输入也不抛异常，读法退回合法边界
      expect(fractionReadout(1, 5)).assertEqual('1/2')
      expect(fractionReadoutZh(9, 1)).assertEqual('八分之一')
    })
  })
}