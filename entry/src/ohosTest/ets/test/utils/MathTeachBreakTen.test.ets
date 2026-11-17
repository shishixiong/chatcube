import { describe, it, expect } from '@ohos/hypium'
import {
  breakTenOnes, breakTenFromTen, breakTenResult, breakTenLessonSteps,
  breakTenStepNarrations, breakTenPracticePool, breakTenProblem,
  breakTenOptions, breakTenPracticeRound, BreakTenProblem, BreakTenLessonStep
} from '../../../../main/ets/utils/MathTeachBreakTen'

export default function mathTeachBreakTenTest() {
  describe('mathTeachBreakTen', () => {
    it('15减9_个位5_十里减1_差6', 0, () => {
      expect(breakTenOnes(15)).assertEqual(5)
      expect(breakTenFromTen(9)).assertEqual(1)
      expect(breakTenResult(15, 9)).assertEqual(6)
    })
    it('边界_a11_b2与a18_b9', 0, () => {
      expect(breakTenResult(11, 2)).assertEqual(9)
      expect(breakTenResult(18, 9)).assertEqual(9)
      expect(breakTenOnes(11)).assertEqual(1)
      expect(breakTenOnes(18)).assertEqual(8)
    })
    it('防御取界不抛异常', 0, () => {
      expect(breakTenOnes(10)).assertEqual(1)
      expect(breakTenOnes(19)).assertEqual(8)
      expect(breakTenFromTen(1)).assertEqual(8)
      expect(breakTenFromTen(10)).assertEqual(1)
      expect(breakTenResult(15, 9)).assertEqual(6)
    })
    it('讲解4步标题与口播稿一致', 0, () => {
      const steps: BreakTenLessonStep[] = breakTenLessonSteps(15, 9)
      expect(steps.length).assertEqual(4)
      expect(steps[0].title).assertEqual('看个位')
      expect(steps[1].title).assertEqual('拆成十和几')
      expect(steps[2].title).assertEqual('十里减')
      expect(steps[3].title).assertEqual('加回来')
      const narrations: string[] = breakTenStepNarrations(15, 9)
      expect(narrations.length).assertEqual(4)
      for (let i = 0; i < steps.length; i++) {
        expect(narrations[i]).assertEqual(steps[i].narration)
        expect(steps[i].chip.length > 0).assertTrue()
        expect(steps[i].action.length > 0).assertTrue()
      }
    })
    it('题库36题且全部退位', 0, () => {
      const pool: BreakTenProblem[] = breakTenPracticePool()
      expect(pool.length).assertEqual(36)
      for (let i = 0; i < pool.length; i++) {
        const p: BreakTenProblem = pool[i]
        expect(p.a >= 11 && p.a <= 18).assertTrue()
        expect(p.b >= 2 && p.b <= 9).assertTrue()
        expect(p.b > p.a - 10).assertTrue()
        expect(p.result).assertEqual(p.a - p.b)
        expect(p.fromTen).assertEqual(10 - p.b)
        expect(p.ones).assertEqual(p.a - 10)
      }
    })
    it('选项3唯一含正确值且落在1到9', 0, () => {
      const pool: BreakTenProblem[] = breakTenPracticePool()
      for (let i = 0; i < pool.length; i++) {
        const p: BreakTenProblem = pool[i]
        expect(p.options.length).assertEqual(3)
        expect(p.options.indexOf(p.fromTen) >= 0).assertTrue()
        for (let j = 0; j < p.options.length; j++) {
          expect(p.options[j] >= 1 && p.options[j] <= 9).assertTrue()
          for (let k = j + 1; k < p.options.length; k++) {
            expect(p.options[j] !== p.options[k]).assertTrue()
          }
        }
      }
    })
    it('选项确定性_同seed同序', 0, () => {
      const o1: number[] = breakTenOptions(3, 159)
      const o2: number[] = breakTenOptions(3, 159)
      expect(o1.length).assertEqual(3)
      for (let i = 0; i < 3; i++) {
        expect(o1[i]).assertEqual(o2[i])
      }
    })
    it('练习轮次5题_避开本课_不撞题_确定性', 0, () => {
      const round: BreakTenProblem[] = breakTenPracticeRound(15, 9, 5)
      expect(round.length).assertEqual(5)
      for (let i = 0; i < round.length; i++) {
        expect(round[i].a !== 15 || round[i].b !== 9).assertTrue()
        for (let j = i + 1; j < round.length; j++) {
          expect(round[i].a !== round[j].a || round[i].b !== round[j].b).assertTrue()
        }
      }
      const again: BreakTenProblem[] = breakTenPracticeRound(15, 9, 5)
      for (let i = 0; i < 5; i++) {
        expect(round[i].a).assertEqual(again[i].a)
        expect(round[i].b).assertEqual(again[i].b)
      }
    })
    it('单题构造与题库一致', 0, () => {
      const p: BreakTenProblem = breakTenProblem(13, 7)
      expect(p.fromTen).assertEqual(3)
      expect(p.ones).assertEqual(3)
      expect(p.result).assertEqual(6)
      expect(p.options.indexOf(3) >= 0).assertTrue()
    })
  })
}