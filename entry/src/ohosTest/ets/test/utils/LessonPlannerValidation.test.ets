import { describe, it, expect } from '@ohos/hypium'
import {
  validatePlannerOutput,
  MIN_PLANNER_COUNTS,
  VALID_MATH_DIMENSIONS,
  VALID_CHINESE_DIMENSIONS
} from '../../../../main/ets/utils/LessonPlannerValidation'
import {
  LessonPlan,
  LessonPlanVocabItem,
  LessonPlanMathItem,
  LessonPlanWritingItem,
  LessonPlanGeneralItem,
  LessonPlanChineseItem
} from '../../../../main/ets/models/LessonPlanModels'

/**
 * LessonPlannerValidation 单元测试
 *
 * 覆盖 spec docs/superpowers/specs/2026-06-22-...-design.md §4.1 全部校验分支。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

function emptyPlan(): LessonPlan {
  return new LessonPlan()
}

function filledPlan(): LessonPlan {
  const p = new LessonPlan()
  for (let i = 0; i < 4; i++) {
    const v = new LessonPlanVocabItem()
    v.topicKey = `vocab.word${i}`
    v.word = `word${i}`
    p.vocab.push(v)
  }
  for (let i = 0; i < 4; i++) {
    const m = new LessonPlanMathItem()
    m.topicKey = `math.addition.q${i}`
    m.dimension = 'math_addition'
    m.targetSkillLevel = 2
    p.math.push(m)
  }
  for (let i = 0; i < 2; i++) {
    const w = new LessonPlanWritingItem()
    w.topicKey = `writing.char${i}`
    w.characterOrWord = `字${i}`
    w.subject = 'chinese'
    p.writing.push(w)
  }
  for (let i = 0; i < 2; i++) {
    const c = new LessonPlanChineseItem()
    c.topicKey = `chinese.chinese_vocab.zi${i}`
    c.dimension = 'chinese_vocab'
    c.character = `字${i}`
    c.targetSkillLevel = 2
    p.chinese.push(c)
  }
  for (let i = 0; i < 2; i++) {
    const g = new LessonPlanGeneralItem()
    g.topicKey = `general_nature.item${i}`
    g.dimension = 'general_nature'
    p.generalKnowledge.push(g)
  }
  return p
}

export default function lessonPlannerValidationTest() {
  describe('MIN_PLANNER_COUNTS 常量', () => {
    it('下限为 vocab=4 / math=4 / writing=2 / general=2 / chinese=2', 0, () => {
      expect(MIN_PLANNER_COUNTS.vocab).assertEqual(4)
      expect(MIN_PLANNER_COUNTS.math).assertEqual(4)
      expect(MIN_PLANNER_COUNTS.writing).assertEqual(2)
      expect(MIN_PLANNER_COUNTS.general).assertEqual(2)
      expect(MIN_PLANNER_COUNTS.chinese).assertEqual(2)
    })
  })

  describe('VALID_CHINESE_DIMENSIONS 常量', () => {
    it('白名单 3 个语文维度, 与语文 3 维画像一致', 0, () => {
      expect(VALID_CHINESE_DIMENSIONS.length).assertEqual(3)
      const expected = ['pinyin', 'chinese_vocab', 'chinese_reading']
      for (let i = 0; i < expected.length; i++) {
        expect(VALID_CHINESE_DIMENSIONS.indexOf(expected[i]) >= 0).assertTrue()
      }
    })
  })

  describe('VALID_MATH_DIMENSIONS 常量', () => {
    it('白名单 10 个 math 维度, 与 SKILL_DEFINITIONS 一致', 0, () => {
      expect(VALID_MATH_DIMENSIONS.length).assertEqual(10)
      const expected = [
        'math_counting', 'math_number_sense', 'math_addition', 'math_subtraction', 'math_multiply',
        'math_divide', 'math_shapes', 'math_comparison', 'math_time', 'math_word_problem'
      ]
      for (let i = 0; i < expected.length; i++) {
        expect(VALID_MATH_DIMENSIONS.indexOf(expected[i]) >= 0).assertTrue()
      }
    })
  })

  describe('validatePlannerOutput - 合法路径', () => {
    it('最小合规 plan (vocab=4/math=4/writing=2/general=2) → ok=true', 0, () => {
      const r = validatePlannerOutput(filledPlan())
      expect(r.ok).assertTrue()
      expect(r.issues.length).assertEqual(0)
    })

    it('所有字段填齐 (vocab=5/math=5/chinese=3/writing=3/general=3) → ok=true', 0, () => {
      const p = filledPlan()
      p.vocab.push(new LessonPlanVocabItem())
      p.math.push(new LessonPlanMathItem())
      const wNew = new LessonPlanWritingItem()
      wNew.subject = 'english'
      p.writing.push(wNew)
      const cNew = new LessonPlanChineseItem()
      cNew.dimension = 'pinyin'
      cNew.character = 'mā'
      cNew.targetSkillLevel = 1
      p.chinese.push(cNew)
      p.generalKnowledge.push(new LessonPlanGeneralItem())
      const r = validatePlannerOutput(p)
      expect(r.ok).assertTrue()
    })
  })

  describe('validatePlannerOutput - 模块数量不足', () => {
    it('vocab=3 → ok=false, issues 包含 vocab 数量', 0, () => {
      const p = filledPlan()
      p.vocab.pop()
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues.length).assertEqual(1)
      expect(r.issues[0]).assertContain('vocab=3')
      expect(r.issues[0]).assertContain('< min 4')
    })

    it('math=3 → ok=false', 0, () => {
      const p = filledPlan()
      p.math.pop()
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('math=3')
    })

    it('writing=1 → ok=false', 0, () => {
      const p = filledPlan()
      p.writing.pop()
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('writing=1')
    })

    it('generalKnowledge=1 → ok=false', 0, () => {
      const p = filledPlan()
      p.generalKnowledge.pop()
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('generalKnowledge=1')
    })

    it('chinese=1 → ok=false', 0, () => {
      const p = filledPlan()
      p.chinese.pop()
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('chinese=1')
    })

    it('空 plan → ok=false, 5 个 issues', 0, () => {
      const r = validatePlannerOutput(emptyPlan())
      expect(r.ok).assertFalse()
      expect(r.issues.length).assertEqual(5)
    })
  })

  describe('validatePlannerOutput - math 必填字段', () => {
    it('math 项 dimension="" → ok=false, issues 包含 invalid dimension', 0, () => {
      const p = filledPlan()
      p.math[0].dimension = ''
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('invalid dimension')
    })

    it('math 项 dimension="math_logic" (不在白名单) → ok=false', 0, () => {
      const p = filledPlan()
      p.math[0].dimension = 'math_logic'
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('invalid dimension')
      expect(r.issues[0]).assertContain('math_logic')
    })

    it('math 项 dimension="math_shapes" (白名单内) → ok=true', 0, () => {
      const p = filledPlan()
      p.math[0].dimension = 'math_shapes'
      const r = validatePlannerOutput(p)
      expect(r.ok).assertTrue()
    })

    it('math 项 targetSkillLevel=0 → ok=false, issues 包含 out of [1,5]', 0, () => {
      const p = filledPlan()
      p.math[0].targetSkillLevel = 0
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('targetSkillLevel=0')
      expect(r.issues[0]).assertContain('out of [1,5]')
    })

    it('math 项 targetSkillLevel=6 → ok=false', 0, () => {
      const p = filledPlan()
      p.math[0].targetSkillLevel = 6
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('targetSkillLevel=6')
    })

    it('math 项 targetSkillLevel=1 (合法下限) → ok=true', 0, () => {
      const p = filledPlan()
      p.math[0].targetSkillLevel = 1
      const r = validatePlannerOutput(p)
      expect(r.ok).assertTrue()
    })

    it('math 项 targetSkillLevel=5 (合法上限) → ok=true', 0, () => {
      const p = filledPlan()
      p.math[0].targetSkillLevel = 5
      const r = validatePlannerOutput(p)
      expect(r.ok).assertTrue()
    })
  })

  describe('validatePlannerOutput - 多重 issues 累积', () => {
    it('vocab=3 + math 缺 dimension → 2 个 issues 都列出', 0, () => {
      const p = filledPlan()
      p.vocab.pop()
      p.math[0].dimension = ''
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues.length).assertEqual(2)
    })
  })

  describe('validatePlannerOutput - chinese 必填字段', () => {
    it('chinese 项 dimension="" → ok=false', 0, () => {
      const p = filledPlan()
      p.chinese[0].dimension = ''
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('invalid dimension')
    })
    it('chinese 项 dimension="math_addition" (串科) → ok=false', 0, () => {
      const p = filledPlan()
      p.chinese[0].dimension = 'math_addition'
      const r = validatePlannerOutput(p)
      expect(r.issues[0]).assertContain('math_addition')
    })
    it('chinese 项 targetSkillLevel=0 → ok=false, 含 out of [1,5]', 0, () => {
      const p = filledPlan()
      p.chinese[0].targetSkillLevel = 0
      const r = validatePlannerOutput(p)
      expect(r.issues[0]).assertContain('targetSkillLevel=0')
    })
    it('chinese 项 targetSkillLevel=6 → ok=false', 0, () => {
      const p = filledPlan()
      p.chinese[0].targetSkillLevel = 6
      const r = validatePlannerOutput(p)
      expect(r.issues[0]).assertContain('targetSkillLevel=6')
    })
  })

  describe('validatePlannerOutput - writing subject 白名单', () => {
    it('writing 项 subject="" → ok=false', 0, () => {
      const p = filledPlan()
      p.writing[0].subject = ''
      const r = validatePlannerOutput(p)
      expect(r.ok).assertFalse()
      expect(r.issues[0]).assertContain('invalid subject')
    })
    it('writing 项 subject="french" (白名单外) → ok=false', 0, () => {
      const p = filledPlan()
      p.writing[0].subject = 'french'
      const r = validatePlannerOutput(p)
      expect(r.issues[0]).assertContain('french')
    })
    it('writing 项 subject="math" (白名单内) → ok=true', 0, () => {
      const p = filledPlan()
      p.writing[0].subject = 'math'
      const r = validatePlannerOutput(p)
      expect(r.ok).assertTrue()
    })
  })
}
