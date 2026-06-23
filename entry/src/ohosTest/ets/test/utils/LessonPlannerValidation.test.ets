import { describe, it, expect } from '@ohos/hypium'
import {
  validatePlannerOutput,
  MIN_PLANNER_COUNTS,
  VALID_MATH_DIMENSIONS
} from '../../../../main/ets/utils/LessonPlannerValidation'
import {
  LessonPlan,
  LessonPlanVocabItem,
  LessonPlanMathItem,
  LessonPlanWritingItem,
  LessonPlanGeneralItem
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
    p.writing.push(w)
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
    it('下限为 vocab=4 / math=4 / writing=2 / generalKnowledge=2', 0, () => {
      expect(MIN_PLANNER_COUNTS.vocab).assertEqual(4)
      expect(MIN_PLANNER_COUNTS.math).assertEqual(4)
      expect(MIN_PLANNER_COUNTS.writing).assertEqual(2)
      expect(MIN_PLANNER_COUNTS.general).assertEqual(2)
    })
  })

  describe('VALID_MATH_DIMENSIONS 常量', () => {
    it('白名单 8 个 math 维度, 与 SKILL_DEFINITIONS 一致', 0, () => {
      expect(VALID_MATH_DIMENSIONS.length).assertEqual(8)
      const expected = [
        'math_counting', 'math_addition', 'math_subtraction', 'math_multiply',
        'math_divide', 'math_shapes', 'math_comparison', 'math_time'
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

    it('所有字段填齐 (vocab=5/math=5/writing=3/general=3) → ok=true', 0, () => {
      const p = filledPlan()
      p.vocab.push(new LessonPlanVocabItem())
      p.math.push(new LessonPlanMathItem())
      p.writing.push(new LessonPlanWritingItem())
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

    it('空 plan → ok=false, 4 个 issues', 0, () => {
      const r = validatePlannerOutput(emptyPlan())
      expect(r.ok).assertFalse()
      expect(r.issues.length).assertEqual(4)
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
}
