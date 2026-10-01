/**
 * 备课老师 LLM 输出验证器
 *
 * 集中定义每日 lesson plan 的密度下限 + math/chinese 必填字段校验 + writing subject 白名单。
 * - MIN_PLANNER_COUNTS: 每模块最小 item 数量（vocab/math/writing/general/chinese）
 * - VALID_MATH_DIMENSIONS: math 项 dimension 白名单（必须与 ChildProfileService.SKILL_DEFINITIONS 一致）
 * - VALID_CHINESE_DIMENSIONS: chinese 项 dimension 白名单（对齐语文 3 维画像: pinyin/chinese_vocab/chinese_reading）
 * - VALID_WRITING_SUBJECTS: writing 项 subject 白名单（english/chinese/math，2026-10-01 学科拆分）
 * - validatePlannerOutput: 主入口, 返回 { ok, issues }
 *
 * 纯函数, 无副作用, 无 IO。可被 LessonPlanningService.runPlanningPipeline 在
 * 3 次内部重试循环中反复调用。
 *
 * Spec: docs/superpowers/specs/2026-06-22-lesson-plan-density-and-skill-alignment-design.md §4.1
 */

import {
  LessonPlan
} from '../models/LessonPlanModels'

/** 每模块最小 item 数量（用户选"中等"目标 5/5/3/3 的下限） */
export interface MinPlannerCounts {
  vocab: number
  math: number
  writing: number
  general: number
  chinese: number
}

export const MIN_PLANNER_COUNTS: MinPlannerCounts = {
  vocab: 4,
  math: 4,
  writing: 2,
  general: 2,
  chinese: 2
}

/** math 项 dimension 白名单（10 个, 必须与 ChildProfileService.SKILL_DEFINITIONS 一致） */
export const VALID_MATH_DIMENSIONS: ReadonlyArray<string> = [
  'math_counting',
  'math_number_sense',
  'math_addition',
  'math_subtraction',
  'math_multiply',
  'math_divide',
  'math_shapes',
  'math_comparison',
  'math_time',
  'math_word_problem'
]

/** chinese 项 dimension 白名单 (3 个, 对齐语文 3 维画像: pinyin/chinese_vocab/chinese_reading) */
export const VALID_CHINESE_DIMENSIONS: ReadonlyArray<string> = [
  'pinyin',
  'chinese_vocab',
  'chinese_reading'
]

/** writing 项 subject 白名单 */
const VALID_WRITING_SUBJECTS: ReadonlyArray<string> = ['english', 'chinese', 'math']

export interface PlannerValidationResult {
  ok: boolean
  issues: string[]
}

/**
 * 验证备课老师 LLM 输出的 plan。
 * 返回 { ok: boolean, issues: string[] }。
 * - 任一模块数量低于下限 → issues 加一条
 * - 任一 math 项 dimension 不在白名单 → issues 加一条
 * - 任一 math 项 targetSkillLevel 不在 [1, 5] 区间 → issues 加一条
 * - 任一 chinese 项 dimension 不在白名单 / targetSkillLevel 不在 [1, 5] → issues 加一条
 * - 任一 writing 项 subject 不在白名单 → issues 加一条
 * - 全部通过 → ok=true, issues 为空数组
 */
export function validatePlannerOutput(plan: LessonPlan): PlannerValidationResult {
  const issues: string[] = []

  if (plan.vocab.length < MIN_PLANNER_COUNTS.vocab) {
    issues.push(`vocab=${plan.vocab.length} < min ${MIN_PLANNER_COUNTS.vocab}`)
  }
  if (plan.math.length < MIN_PLANNER_COUNTS.math) {
    issues.push(`math=${plan.math.length} < min ${MIN_PLANNER_COUNTS.math}`)
  }
  if (plan.writing.length < MIN_PLANNER_COUNTS.writing) {
    issues.push(`writing=${plan.writing.length} < min ${MIN_PLANNER_COUNTS.writing}`)
  }
  if (plan.generalKnowledge.length < MIN_PLANNER_COUNTS.general) {
    issues.push(`generalKnowledge=${plan.generalKnowledge.length} < min ${MIN_PLANNER_COUNTS.general}`)
  }
  if (plan.chinese.length < MIN_PLANNER_COUNTS.chinese) {
    issues.push(`chinese=${plan.chinese.length} < min ${MIN_PLANNER_COUNTS.chinese}`)
  }

  for (let i = 0; i < plan.math.length; i++) {
    const item = plan.math[i]
    if (item.dimension === '' || VALID_MATH_DIMENSIONS.indexOf(item.dimension) < 0) {
      issues.push(`math item "${item.topicKey}" has invalid dimension="${item.dimension}"`)
    }
    if (item.targetSkillLevel < 1 || item.targetSkillLevel > 5) {
      issues.push(`math item "${item.topicKey}" has targetSkillLevel=${item.targetSkillLevel} (out of [1,5])`)
    }
  }

  for (let i = 0; i < plan.chinese.length; i++) {
    const item = plan.chinese[i]
    if (item.dimension === '' || VALID_CHINESE_DIMENSIONS.indexOf(item.dimension) < 0) {
      issues.push(`chinese item "${item.topicKey}" has invalid dimension="${item.dimension}"`)
    }
    if (item.targetSkillLevel < 1 || item.targetSkillLevel > 5) {
      issues.push(`chinese item "${item.topicKey}" has targetSkillLevel=${item.targetSkillLevel} (out of [1,5])`)
    }
  }

  for (let i = 0; i < plan.writing.length; i++) {
    const item = plan.writing[i]
    if (VALID_WRITING_SUBJECTS.indexOf(item.subject) < 0) {
      issues.push(`writing item "${item.topicKey}" has invalid subject="${item.subject}"`)
    }
  }

  return { ok: issues.length === 0, issues }
}
