import { describe, it, expect } from '@ohos/hypium'
import {
  makeTenFriend, makeTenRemain, makeTenScaffold, makeTenChain, makeTenChips,
  makeTenPractice, makeTenStepTitles, makeTenStepNarrations,
  MakeTenScaffoldLine, MakeTenChainLine, MakeTenChips, MakeTenPractice
} from '../../../../main/ets/utils/MathTeachMakeTen'

/**
 * MathTeachMakeTen 单元测试（ten_frame 凑十引导课纯函数）
 *
 * 覆盖：朋友/余数边界、脚手架 5 行、算式链 4 行、讲一讲 chips（canonical
 * 与 display 置换）、练一练迁移题（题库选择/三选项唯一/确定性轮转）、
 * 8 步标题与口播稿长度。
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
    it('scaffold_5行且文案正确', 0, () => {
      const lines: MakeTenScaffoldLine[] = makeTenScaffold(9, 5)
      expect(lines.length === 5).assertTrue()
      expect(lines[0].eq === '9 + 5 = ?' && lines[0].label === '题目').assertTrue()
      expect(lines[1].eq === '9 + 1 = 10' && lines[1].label === '找朋友').assertTrue()
      expect(lines[2].eq === '5 = 1 + 4' && lines[2].label === '拆小数').assertTrue()
      expect(lines[3].eq === '10 + 4 = 14' && lines[3].label === '十加几').assertTrue()
      expect(lines[4].eq === '9 + 5 = 14' && lines[4].label === '答案').assertTrue()
    })
    it('scaffold_6加7泛化', 0, () => {
      const lines: MakeTenScaffoldLine[] = makeTenScaffold(6, 7)
      expect(lines[2].eq === '7 = 4 + 3').assertTrue()
      expect(lines[3].eq === '10 + 3 = 13').assertTrue()
    })
    it('chain_4行逐行推进', 0, () => {
      const lines: MakeTenChainLine[] = makeTenChain(9, 5)
      expect(lines.length === 4).assertTrue()
      expect(lines[0].eq === '9 + 5 = 9 + 1 + 4').assertTrue()
      expect(lines[1].eq === '9 + 1 + 4 = 10 + 4').assertTrue()
      expect(lines[2].eq === '10 + 4 = 14').assertTrue()
      expect(lines[3].eq === '所以 9 + 5 = 14').assertTrue()
    })
    it('chips_canonical与原型四句一致', 0, () => {
      const chips: MakeTenChips = makeTenChips(9, 5)
      expect(chips.canonical.length === 4).assertTrue()
      expect(chips.canonical[0] === '9 差 1 凑成 10').assertTrue()
      expect(chips.canonical[1] === '把 5 拆成 1 和 4').assertTrue()
      expect(chips.canonical[2] === '9 + 1 = 10').assertTrue()
      expect(chips.canonical[3] === '10 + 4 = 14').assertTrue()
    })
    it('chips_display是canonical的固定乱序且不丢句', 0, () => {
      const chips: MakeTenChips = makeTenChips(9, 5)
      expect(chips.display.length === 4).assertTrue()
      // 固定置换 [1,3,0,2]
      expect(chips.display[0] === chips.canonical[1]).assertTrue()
      expect(chips.display[1] === chips.canonical[3]).assertTrue()
      expect(chips.display[2] === chips.canonical[0]).assertTrue()
      expect(chips.display[3] === chips.canonical[2]).assertTrue()
    })
    it('practice_9加5的课练8加7（与原型一致）', 0, () => {
      const p: MakeTenPractice = makeTenPractice(9, 5)
      expect(p.big === 8 && p.small === 7).assertTrue()
      expect(p.answer === 2).assertTrue()
    })
    it('practice_本题大数为8时换7加5', 0, () => {
      const p: MakeTenPractice = makeTenPractice(8, 6)
      expect(p.big === 7 && p.small === 5).assertTrue()
      expect(p.answer === 3).assertTrue()
    })
    it('practice_三选项唯一且含正确项', 0, () => {
      const p1: MakeTenPractice = makeTenPractice(9, 5)
      expect(p1.choices.length === 3).assertTrue()
      expect(p1.choices[0] !== p1.choices[1] && p1.choices[1] !== p1.choices[2]
        && p1.choices[0] !== p1.choices[2]).assertTrue()
      let hasAnswer1: boolean = false
      for (let i = 0; i < p1.choices.length; i++) {
        if (p1.choices[i] === p1.answer) { hasAnswer1 = true }
      }
      expect(hasAnswer1).assertTrue()
      const p2: MakeTenPractice = makeTenPractice(8, 5)
      let hasAnswer2: boolean = false
      for (let j = 0; j < p2.choices.length; j++) {
        if (p2.choices[j] === p2.answer) { hasAnswer2 = true }
      }
      expect(hasAnswer2).assertTrue()
    })
    it('practice_选项顺序确定性（big=8 轮转 offset 2）', 0, () => {
      const p: MakeTenPractice = makeTenPractice(9, 5)
      // base [2,5,7] 轮转 offset=2 → choices[i]=base[(i+2)%3] = [7,2,5]
      expect(p.choices[0] === 7 && p.choices[1] === 2 && p.choices[2] === 5).assertTrue()
    })
    it('titles_8步且第3步含拆分文案', 0, () => {
      const titles: string[] = makeTenStepTitles(9, 5)
      expect(titles.length === 8).assertTrue()
      expect(titles[2] === '把 5 拆成 1 和 4').assertTrue()
      expect(titles[3] === '把 1 送进十格阵').assertTrue()
    })
    it('narrations_8步且迁移步含练习题参数', 0, () => {
      const narrations: string[] = makeTenStepNarrations(9, 5)
      expect(narrations.length === 8).assertTrue()
      expect(narrations[3] === '把 1 送进十格阵，看看会发生什么。').assertTrue()
      expect(narrations[7].indexOf('8') >= 0 && narrations[7].indexOf('7') >= 0).assertTrue()
    })
  })
}
