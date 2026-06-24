import { describe, it, expect } from '@ohos/hypium'
import {
  generateBaselinePlan
} from '../../../../main/ets/utils/LessonPlannerBaseline'
import {
  LessonPlan,
  LessonPlanVocabItem,
  LessonPlanMathItem,
  LessonPlanWritingItem,
  LessonPlanGeneralItem,
  ChildSnapshot
} from '../../../../main/ets/models/LessonPlanModels'
import {
  validatePlannerOutput,
  MIN_PLANNER_COUNTS
} from '../../../../main/ets/utils/LessonPlannerValidation'

/**
 * LessonPlannerBaseline 单元测试
 *
 * 覆盖 generateBaselinePlan 的全部路径，确保 baseline 计划始终通过
 * validatePlannerOutput（与 LessonPlannerValidation.test.ets 形成闭环）。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */

function emptySnapshot(): ChildSnapshot {
  return new ChildSnapshot()
}

function snapshotWithWeakMath(weakSkills: string[]): ChildSnapshot {
  const s = new ChildSnapshot()
  s.childName = '小明'
  s.ageYears = 6
  s.weakSkills = weakSkills
  s.overallNote = '加法基础较弱'
  return s
}

function filledYesterdayPlan(): LessonPlan {
  const p = new LessonPlan()
  p.themeTitle = '昨天的水果主题'
  for (let i = 0; i < 4; i++) {
    const v = new LessonPlanVocabItem()
    v.topicKey = `vocab.fruit${i}`
    v.word = `fruit${i}`
    p.vocab.push(v)
  }
  for (let i = 0; i < 4; i++) {
    const m = new LessonPlanMathItem()
    m.topicKey = `math.shape.q${i}`
    m.dimension = 'math_shapes'
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

export default function lessonPlannerBaselineTest() {
  describe('generateBaselinePlan - 基本密度', () => {
    it('空 childSnapshot → 4 个 vocab / 4 个 math / 2 个 writing / 2 个 generalKnowledge', 0, () => {
      const plan = generateBaselinePlan('2026-06-24', emptySnapshot(), null)
      expect(plan.vocab.length >= MIN_PLANNER_COUNTS.vocab).assertTrue()
      expect(plan.math.length >= MIN_PLANNER_COUNTS.math).assertTrue()
      expect(plan.writing.length >= MIN_PLANNER_COUNTS.writing).assertTrue()
      expect(plan.generalKnowledge.length >= MIN_PLANNER_COUNTS.general).assertTrue()
    })

    it('空 childSnapshot → 输出通过 validatePlannerOutput (ok=true)', 0, () => {
      const plan = generateBaselinePlan('2026-06-24', emptySnapshot(), null)
      const r = validatePlannerOutput(plan)
      expect(r.ok).assertTrue()
      expect(r.issues.length).assertEqual(0)
    })

    it('planDate 字段同步为入参', 0, () => {
      const plan = generateBaselinePlan('2026-06-24', emptySnapshot(), null)
      expect(plan.planDate).assertEqual('2026-06-24')
    })

    it('childSnapshot 字段同步为入参', 0, () => {
      const snap = snapshotWithWeakMath(['math_addition', 'math_shapes'])
      const plan = generateBaselinePlan('2026-06-24', snap, null)
      expect(plan.childSnapshot.childName).assertEqual('小明')
      expect(plan.childSnapshot.weakSkills.length).assertEqual(2)
    })

    it('themeTitle / themeDescription / teacherNotes 非空 (用户看到的页面有内容)', 0, () => {
      const plan = generateBaselinePlan('2026-06-24', emptySnapshot(), null)
      expect(plan.themeTitle !== '').assertTrue()
      expect(plan.themeDescription !== '').assertTrue()
      expect(plan.teacherNotes !== '').assertTrue()
    })
  })

  describe('generateBaselinePlan - math 字段合规', () => {
    it('每个 math 项的 dimension 在白名单内', 0, () => {
      const plan = generateBaselinePlan('2026-06-24', emptySnapshot(), null)
      const validSet = ['math_counting', 'math_addition', 'math_subtraction', 'math_multiply',
        'math_divide', 'math_shapes', 'math_comparison', 'math_time']
      for (let i = 0; i < plan.math.length; i++) {
        expect(validSet.indexOf(plan.math[i].dimension) >= 0).assertTrue()
      }
    })

    it('每个 math 项的 targetSkillLevel 在 [1,5]', 0, () => {
      const plan = generateBaselinePlan('2026-06-24', emptySnapshot(), null)
      for (let i = 0; i < plan.math.length; i++) {
        const lv = plan.math[i].targetSkillLevel
        expect(lv >= 1 && lv <= 5).assertTrue()
      }
    })

    it('child weakSkills 含 math → 优先从弱项维度出题', 0, () => {
      const snap = snapshotWithWeakMath(['math_addition', 'math_subtraction'])
      const plan = generateBaselinePlan('2026-06-24', snap, null)
      // 至少前 2 个 math 项应该是弱项维度
      const weakDim0 = plan.math[0].dimension
      const weakDim1 = plan.math[1].dimension
      expect(weakDim0 === 'math_addition' || weakDim0 === 'math_subtraction').assertTrue()
      expect(weakDim1 === 'math_addition' || weakDim1 === 'math_subtraction').assertTrue()
    })

    it('child weakSkills 非 math → 使用默认 math 维度集 (counting/shapes/comparison/addition)', 0, () => {
      const snap = snapshotWithWeakMath(['general_nature', 'fine_motor'])
      const plan = generateBaselinePlan('2026-06-24', snap, null)
      // 弱项不涉及 math 时, math 默认覆盖 4 个核心维度
      const dims: string[] = []
      for (let i = 0; i < plan.math.length; i++) {
        dims.push(plan.math[i].dimension)
      }
      expect(dims.indexOf('math_counting') >= 0).assertTrue()
      expect(dims.indexOf('math_shapes') >= 0).assertTrue()
      expect(dims.indexOf('math_comparison') >= 0).assertTrue()
      expect(dims.indexOf('math_addition') >= 0).assertTrue()
    })
  })

  describe('generateBaselinePlan - yesterday 复用', () => {
    it('yesterday plan 提供 vocab → baseline 复用其 vocab 项', 0, () => {
      const plan = generateBaselinePlan('2026-06-24', emptySnapshot(), filledYesterdayPlan())
      // 至少 1 个 vocab topicKey 与 yesterday 一致
      let matched = false
      for (let i = 0; i < plan.vocab.length; i++) {
        if (plan.vocab[i].topicKey.indexOf('vocab.fruit') === 0) {
          matched = true
          break
        }
      }
      expect(matched).assertTrue()
    })

    it('yesterday plan 提供 writing → baseline 复用其 writing 项', 0, () => {
      const plan = generateBaselinePlan('2026-06-24', emptySnapshot(), filledYesterdayPlan())
      let matched = false
      for (let i = 0; i < plan.writing.length; i++) {
        if (plan.writing[i].topicKey.indexOf('writing.char') === 0) {
          matched = true
          break
        }
      }
      expect(matched).assertTrue()
    })

    it('yesterday plan = null → 不崩溃, 用默认内容', 0, () => {
      const plan = generateBaselinePlan('2026-06-24', emptySnapshot(), null)
      const r = validatePlannerOutput(plan)
      expect(r.ok).assertTrue()
    })

    it('yesterday plan 残缺 (只有 vocab) → 只复用 vocab, 其他用默认', 0, () => {
      const partial = new LessonPlan()
      const v = new LessonPlanVocabItem()
      v.topicKey = 'vocab.apple'
      v.word = 'apple'
      partial.vocab.push(v)
      const plan = generateBaselinePlan('2026-06-24', emptySnapshot(), partial)
      // vocab 有 apple 项
      let foundApple = false
      for (let i = 0; i < plan.vocab.length; i++) {
        if (plan.vocab[i].topicKey === 'vocab.apple') {
          foundApple = true
          break
        }
      }
      expect(foundApple).assertTrue()
      // math 仍满足下限
      expect(plan.math.length >= MIN_PLANNER_COUNTS.math).assertTrue()
      // overall 仍 ok
      const r = validatePlannerOutput(plan)
      expect(r.ok).assertTrue()
    })
  })

  describe('generateBaselinePlan - topicKey 唯一性', () => {
    it('baseline 内部 topicKey 不重复 (避免预生成图冲突)', 0, () => {
      const plan = generateBaselinePlan('2026-06-24', emptySnapshot(), null)
      const seen: string[] = []
      for (let i = 0; i < plan.vocab.length; i++) {
        seen.push(plan.vocab[i].topicKey)
      }
      for (let i = 0; i < plan.math.length; i++) {
        seen.push(plan.math[i].topicKey)
      }
      for (let i = 0; i < plan.writing.length; i++) {
        seen.push(plan.writing[i].topicKey)
      }
      for (let i = 0; i < plan.generalKnowledge.length; i++) {
        seen.push(plan.generalKnowledge[i].topicKey)
      }
      const set = new Set<string>(seen)
      expect(set.size).assertEqual(seen.length)
    })
  })
}