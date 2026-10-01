/**
 * LessonPlanSubjectUtils - 今日计划学科拆分纯函数
 *
 * Spec: docs/superpowers/specs/2026-10-01-lesson-plan-subject-split-design.md §3.4
 * - PlanSubject: 计划学科三元组（常识 generalKnowledge 不在其中, 仅小星老师消费）
 * - planSubjectForAssistant: 学科助手 id → 学科; kids_games / default / 自定义 → null
 * - collectPlanItemsForSubject: 按学科收集计划条目; 未打标签的 writing 项对学科老师不可见
 *
 * 纯函数, 无 ArkUI 依赖, 可被 hypium 覆盖。
 */
import {
  LessonPlan,
  LessonPlanChineseItem,
  LessonPlanVocabItem,
  LessonPlanMathItem,
  LessonPlanWritingItem
} from '../models/LessonPlanModels'
import {
  KIDS_MATH_ASSISTANT_ID,
  KIDS_ENGLISH_ASSISTANT_ID,
  KIDS_CHINESE_ASSISTANT_ID
} from '../models/AssistantModels'

export type PlanSubject = 'chinese' | 'math' | 'english'

/** 单学科计划视图: 仅与 subject 相关的模块数组非空 */
export interface SubjectPlanItems {
  chinese: LessonPlanChineseItem[]
  vocab: LessonPlanVocabItem[]
  math: LessonPlanMathItem[]
  writing: LessonPlanWritingItem[]
}

export function planSubjectForAssistant(assistantId: string): PlanSubject | null {
  if (assistantId === KIDS_MATH_ASSISTANT_ID) {
    return 'math'
  }
  if (assistantId === KIDS_ENGLISH_ASSISTANT_ID) {
    return 'english'
  }
  if (assistantId === KIDS_CHINESE_ASSISTANT_ID) {
    return 'chinese'
  }
  return null
}

export function collectPlanItemsForSubject(plan: LessonPlan, subject: PlanSubject): SubjectPlanItems {
  const out: SubjectPlanItems = { chinese: [], vocab: [], math: [], writing: [] }
  for (let i = 0; i < plan.writing.length; i++) {
    if (plan.writing[i].subject === subject) {
      out.writing.push(plan.writing[i])
    }
  }
  if (subject === 'math') {
    for (let i = 0; i < plan.math.length; i++) {
      out.math.push(plan.math[i])
    }
  } else if (subject === 'english') {
    for (let i = 0; i < plan.vocab.length; i++) {
      out.vocab.push(plan.vocab[i])
    }
  } else {
    for (let i = 0; i < plan.chinese.length; i++) {
      out.chinese.push(plan.chinese[i])
    }
  }
  return out
}
