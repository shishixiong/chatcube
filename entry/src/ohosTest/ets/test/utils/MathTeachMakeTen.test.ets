import { describe, it, expect } from '@ohos/hypium'
import {
  makeTenFriend, makeTenRemain, makeTenBlockColor, makeTenShade, makeTenIsLight,
  makeTenFriendPairs, makeTenLessonSteps, makeTenStepNarrations,
  makeTenPracticePool, makeTenProblem, makeTenOptions, makeTenPracticeRound,
  MakeTenPair, MakeTenLessonStep, MakeTenProblem
} from '../../../../main/ets/utils/MathTeachMakeTen'

/**
 * MathTeachMakeTen 单元测试（ten_frame 凑十讲解纯函数）
 *
 * 覆盖：朋友/余数边界、方块色与明暗、好朋友配对、4 步讲解文案与口播稿、
 * 练习题库（12 题且全部合法）、选项唯一且含正确项、5 题轮次确定性且不撞题。
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

export default function mathTeachMakeTenTest() {
  describe('mathTeachMakeTen', () => {
    it('friend_9的朋友是1', 0, () => {
      expect(makeTenFriend(9) === 1).assertTrue()
    })
    it('friend_5的朋友是5', 0, () => {
      expect(makeTenFriend(5) === 5).assertTrue()
    })
    it('friend_越界防御', 0, () => {
      expect(makeTenFriend(10) === 1).assertTrue()
      expect(makeTenFriend(4) === 5).assertTrue()
    })
    it('remain_9加5剩4', 0, () => {
      expect(makeTenRemain(5, 1) === 4).assertTrue()
    })
    it('remain_负数取0兜底', 0, () => {
      expect(makeTenRemain(1, 5) === 0).assertTrue()
    })
    it('color_1到10有固定色且越界兜底', 0, () => {
      expect(makeTenBlockColor(1) === '#E24B45').assertTrue()
      expect(makeTenBlockColor(9) === '#64748B').assertTrue()
      expect(makeTenBlockColor(10) === '#B33636').assertTrue()
      expect(makeTenBlockColor(0) === '#64748B').assertTrue()
      expect(makeTenBlockColor(11) === '#64748B').assertTrue()
    })
    it('shade_按比例变暗', 0, () => {
      expect(makeTenShade('#3B82D8', 0.5) === '#1D416C').assertTrue()
      expect(makeTenShade('bad', 0.5) === 'bad').assertTrue()
    })
    it('isLight_黄色亮蓝色暗', 0, () => {
      expect(makeTenIsLight('#F4C63D')).assertTrue()
      expect(makeTenIsLight('#3B82D8')).assertFalse()
    })
    it('pairs_五对好朋友都凑十', 0, () => {
      const pairs: MakeTenPair[] = makeTenFriendPairs()
      expect(pairs.length === 5).assertTrue()
      for (let i = 0; i < pairs.length; i++) {
        expect(pairs[i].x + pairs[i].y === 10).assertTrue()
      }
      expect(pairs[4].x === 5 && pairs[4].y === 5).assertTrue()
    })
    it('lesson_4步标题顺序', 0, () => {
      const steps: MakeTenLessonStep[] = makeTenLessonSteps(9, 5)
      expect(steps.length === 4).assertTrue()
      expect(steps[0].title === '看大数').assertTrue()
      expect(steps[1].title === '拆小数').assertTrue()
      expect(steps[2].title === '凑成十').assertTrue()
      expect(steps[3].title === '十加几').assertTrue()
    })
    it('lesson_9加5四步文案', 0, () => {
      const steps: MakeTenLessonStep[] = makeTenLessonSteps(9, 5)
      expect(steps[0].desc === '9 离十差 1 格').assertTrue()
      expect(steps[0].hint === '9 和 1 是凑十好朋友。').assertTrue()
      expect(steps[0].action === '拆开 5').assertTrue()
      expect(steps[1].desc === '5 = 1 + 4').assertTrue()
      expect(steps[1].action === '送 1 块进框').assertTrue()
      expect(steps[2].desc === '9 + 1 = 10').assertTrue()
      expect(steps[2].action === '算一算').assertTrue()
      expect(steps[3].desc === '10 + 4 = 14').assertTrue()
      expect(steps[3].action === '去练一练').assertTrue()
    })
    it('lesson_6加7泛化', 0, () => {
      const steps: MakeTenLessonStep[] = makeTenLessonSteps(6, 7)
      expect(steps[0].desc === '6 离十差 4 格').assertTrue()
      expect(steps[1].desc === '7 = 4 + 3').assertTrue()
      expect(steps[3].desc === '10 + 3 = 13').assertTrue()
    })
    it('narrations_与4步正文一致', 0, () => {
      const narrations: string[] = makeTenStepNarrations(9, 5)
      const steps: MakeTenLessonStep[] = makeTenLessonSteps(9, 5)
      expect(narrations.length === 4).assertTrue()
      for (let i = 0; i < steps.length; i++) {
        expect(narrations[i] === steps[i].narration).assertTrue()
      }
      expect(narrations[3].indexOf('10 + 4 = 14') >= 0).assertTrue()
    })
    it('pool_12题且全部满足凑十条件', 0, () => {
      const pool: MakeTenProblem[] = makeTenPracticePool()
      expect(pool.length === 12).assertTrue()
      for (let i = 0; i < pool.length; i++) {
        const p: MakeTenProblem = pool[i]
        expect(p.b < p.a).assertTrue()
        expect(p.a + p.b > 10).assertTrue()
        expect(p.need === 10 - p.a).assertTrue()
        expect(p.rest === p.b - p.need).assertTrue()
        expect(p.rest >= 1).assertTrue()
      }
    })
    it('problem_9加5的选项唯一且含正确项', 0, () => {
      const p: MakeTenProblem = makeTenProblem(9, 5)
      expect(p.need === 1 && p.rest === 4).assertTrue()
      expect(p.options.length === 3).assertTrue()
      expect(p.options[0] !== p.options[1] && p.options[1] !== p.options[2]
        && p.options[0] !== p.options[2]).assertTrue()
      expect(p.options.indexOf(1) >= 0).assertTrue()
      for (let i = 0; i < p.options.length; i++) {
        expect(p.options[i] >= 1 && p.options[i] <= 4).assertTrue()
      }
    })
    it('options_确定性轮转不总把正确项放第一位', 0, () => {
      const o1: number[] = makeTenOptions(1, 5, 95)
      const o2: number[] = makeTenOptions(1, 5, 95)
      expect(o1[0] === o2[0] && o1[1] === o2[1] && o1[2] === o2[2]).assertTrue()
      // seed 95 → offset 2，正确项 1 落在中间
      expect(o1[0] === 3 && o1[1] === 1 && o1[2] === 2).assertTrue()
    })
    it('round_5题确定性且不重复', 0, () => {
      const r1: MakeTenProblem[] = makeTenPracticeRound(9, 5, 5)
      const r2: MakeTenProblem[] = makeTenPracticeRound(9, 5, 5)
      expect(r1.length === 5).assertTrue()
      const seen: string[] = []
      for (let i = 0; i < r1.length; i++) {
        const key: string = r1[i].a + '+' + r1[i].b
        expect(seen.indexOf(key) < 0).assertTrue()
        expect(key === '9+5').assertFalse()
        expect(r1[i].a === r2[i].a && r1[i].b === r2[i].b).assertTrue()
        seen.push(key)
      }
    })
    it('round_参数不在题库时也能出满5题', 0, () => {
      const round: MakeTenProblem[] = makeTenPracticeRound(5, 10, 5)
      expect(round.length === 5).assertTrue()
      for (let i = 0; i < round.length; i++) {
        expect(round[i].options.length === 3).assertTrue()
      }
    })
  })
}
