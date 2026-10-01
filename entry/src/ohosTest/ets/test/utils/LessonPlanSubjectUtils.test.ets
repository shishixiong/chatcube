import { describe, it, expect } from '@ohos/hypium'
import {
  planSubjectForAssistant,
  collectPlanItemsForSubject
} from '../../../../main/ets/utils/LessonPlanSubjectUtils'
import {
  LessonPlan,
  LessonPlanChineseItem,
  LessonPlanVocabItem,
  LessonPlanMathItem,
  LessonPlanWritingItem
} from '../../../../main/ets/models/LessonPlanModels'

function buildMixedPlan(): LessonPlan {
  const p = new LessonPlan()
  const c1 = new LessonPlanChineseItem()
  c1.topicKey = 'chinese.chinese_vocab.shan'
  c1.dimension = 'chinese_vocab'
  c1.character = '山'
  p.chinese.push(c1)
  const v1 = new LessonPlanVocabItem()
  v1.topicKey = 'vocab.apple'
  v1.word = 'apple'
  p.vocab.push(v1)
  const m1 = new LessonPlanMathItem()
  m1.topicKey = 'math.addition.q1'
  m1.dimension = 'math_addition'
  m1.targetSkillLevel = 2
  p.math.push(m1)
  const wc = new LessonPlanWritingItem()
  wc.topicKey = 'writing.山'
  wc.characterOrWord = '山'
  wc.subject = 'chinese'
  p.writing.push(wc)
  const we = new LessonPlanWritingItem()
  we.topicKey = 'writing.A'
  we.characterOrWord = 'A'
  we.subject = 'english'
  p.writing.push(we)
  const wn = new LessonPlanWritingItem()
  wn.topicKey = 'writing.3'
  wn.characterOrWord = '3'
  wn.subject = 'math'
  p.writing.push(wn)
  const wu = new LessonPlanWritingItem()
  wu.topicKey = 'writing.old'
  wu.characterOrWord = '旧'
  wu.subject = ''
  p.writing.push(wu)
  return p
}

export default function lessonPlanSubjectUtilsTest() {
  describe('planSubjectForAssistant', () => {
    it('3 个学科助手正确映射', 0, () => {
      expect(planSubjectForAssistant('kids_math')).assertEqual('math')
      expect(planSubjectForAssistant('kids_english')).assertEqual('english')
      expect(planSubjectForAssistant('kids_chinese')).assertEqual('chinese')
    })
    it('default / kids_games / 未知 id → null', 0, () => {
      expect(planSubjectForAssistant('default')).assertNull()
      expect(planSubjectForAssistant('kids_games')).assertNull()
      expect(planSubjectForAssistant('custom_x')).assertNull()
    })
  })

  describe('collectPlanItemsForSubject', () => {
    it('math → math 模块 + writing[math]', 0, () => {
      const out = collectPlanItemsForSubject(buildMixedPlan(), 'math')
      expect(out.math.length).assertEqual(1)
      expect(out.vocab.length).assertEqual(0)
      expect(out.chinese.length).assertEqual(0)
      expect(out.writing.length).assertEqual(1)
      expect(out.writing[0].characterOrWord).assertEqual('3')
    })
    it('english → vocab 模块 + writing[english]', 0, () => {
      const out = collectPlanItemsForSubject(buildMixedPlan(), 'english')
      expect(out.vocab.length).assertEqual(1)
      expect(out.vocab[0].word).assertEqual('apple')
      expect(out.writing.length).assertEqual(1)
      expect(out.writing[0].characterOrWord).assertEqual('A')
    })
    it('chinese → chinese 模块 + writing[chinese]', 0, () => {
      const out = collectPlanItemsForSubject(buildMixedPlan(), 'chinese')
      expect(out.chinese.length).assertEqual(1)
      expect(out.chinese[0].character).assertEqual('山')
      expect(out.writing.length).assertEqual(1)
      expect(out.writing[0].characterOrWord).assertEqual('山')
    })
    it('未打标签 writing 对任何学科不可见 (Review Focus #1 兜底)', 0, () => {
      const outM = collectPlanItemsForSubject(buildMixedPlan(), 'math')
      const outE = collectPlanItemsForSubject(buildMixedPlan(), 'english')
      const outC = collectPlanItemsForSubject(buildMixedPlan(), 'chinese')
      const all = outM.writing.concat(outE.writing).concat(outC.writing)
      for (let i = 0; i < all.length; i++) {
        expect(all[i].characterOrWord !== '旧').assertTrue()
      }
    })
    it('空 plan → 全空数组', 0, () => {
      const out = collectPlanItemsForSubject(new LessonPlan(), 'chinese')
      expect(out.chinese.length).assertEqual(0)
      expect(out.writing.length).assertEqual(0)
    })
  })
}
