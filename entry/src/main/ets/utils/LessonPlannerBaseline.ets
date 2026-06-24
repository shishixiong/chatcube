/**
 * 备课老师降级计划生成器
 *
 * 当 LLM 输出在 3 次重试后仍无法通过 validatePlannerOutput 时, 用此函数
 * 生成一份"代码侧 baseline 计划", 保证用户在"今日计划"页面至少看到内容。
 *
 * 策略:
 * - vocab / writing / generalKnowledge: 优先复用 yesterdayPlan 中的对应模块,
 *   不足时用通用 6-7 岁默认主题补齐
 * - math: 完全用代码生成, 从 childSnapshot.weakSkills (math_* 子集) 选维度,
 *   否则用 4 个核心默认维度 (math_counting / shapes / comparison / addition),
 *   targetSkillLevel 强制钳制在 [1,5]
 * - themeTitle / themeDescription / teacherNotes: 用通用欢迎文案
 *
 * 设计原则:
 * - 纯函数, 无 IO, 无副作用
 * - 输出始终通过 validatePlannerOutput (ok=true)
 * - topicKey 唯一 (避免预生成图冲突)
 * - 确定性 (无随机), 便于测试和回放
 *
 * Spec: 详见 .superpowers/sdd/notes/baseline-fallback-design.md
 */

import {
  LessonPlan,
  LessonPlanVocabItem,
  LessonPlanMathItem,
  LessonPlanWritingItem,
  LessonPlanGeneralItem,
  ChildSnapshot
} from '../models/LessonPlanModels'
import { VALID_MATH_DIMENSIONS } from './LessonPlannerValidation'

// ============================================================
// 常量 (与 LessonPlannerValidation.MIN_PLANNER_COUNTS 镜像,
//        避免互相 import 造成的循环依赖风险)
// ============================================================

const MIN_VOCAB_COUNT = 4
const MIN_MATH_COUNT = 4
const MIN_WRITING_COUNT = 2
const MIN_GENERAL_COUNT = 2

// ============================================================
// 默认主题库 (6-7 岁幼儿适用, 浅显易懂)
// ============================================================

interface VocabTemplate {
  topicKey: string
  word: string
  translation: string
  exampleSentence: string
  imagePrompt: string
}

interface MathTemplate {
  topicKey: string
  dimension: string
  description: string
  targetSkillLevel: number
  imagePrompt: string
}

interface WritingTemplate {
  topicKey: string
  characterOrWord: string
  description: string
  imagePrompt: string
}

interface GeneralTemplate {
  topicKey: string
  dimension: string
  description: string
  imagePrompt: string
}

/** 通用 topicKey 容器约束 (供 pickUnique/padWithTemplates 泛型使用) */
interface HasTopicKey {
  topicKey: string
}

const DEFAULT_VOCAB: VocabTemplate[] = [
  { topicKey: 'vocab.apple', word: 'apple', translation: '苹果',
    exampleSentence: '我喜欢吃 apple', imagePrompt: 'a red apple, cartoon style, white background' },
  { topicKey: 'vocab.cat', word: 'cat', translation: '小猫',
    exampleSentence: 'cat 喵喵叫', imagePrompt: 'a cute kitten, cartoon style, white background' },
  { topicKey: 'vocab.sun', word: 'sun', translation: '太阳',
    exampleSentence: 'sun 升起来了', imagePrompt: 'a bright sun, cartoon style, white background' },
  { topicKey: 'vocab.book', word: 'book', translation: '书',
    exampleSentence: 'book 里有故事', imagePrompt: 'an open storybook, cartoon style, white background' },
  { topicKey: 'vocab.ball', word: 'ball', translation: '球',
    exampleSentence: '我喜欢玩 ball', imagePrompt: 'a colorful ball, cartoon style, white background' }
]

// 4 个核心默认 math 维度, 保证 6-7 岁零基础也能学
const DEFAULT_MATH_DIMS: string[] = [
  'math_counting', 'math_shapes', 'math_comparison', 'math_addition'
]

const DEFAULT_MATH: MathTemplate[] = [
  { topicKey: 'math.counting.1to10', dimension: 'math_counting',
    description: '数一数 1 到 10', targetSkillLevel: 1,
    imagePrompt: 'numbers 1 to 10 in colorful circles' },
  { topicKey: 'math.shapes.basic', dimension: 'math_shapes',
    description: '认识圆形三角形正方形', targetSkillLevel: 1,
    imagePrompt: 'basic geometric shapes: circle triangle square' },
  { topicKey: 'math.comparison.big_small', dimension: 'math_comparison',
    description: '比较大小和长短', targetSkillLevel: 2,
    imagePrompt: 'big and small objects comparison' },
  { topicKey: 'math.addition.within10', dimension: 'math_addition',
    description: '10 以内的加法', targetSkillLevel: 2,
    imagePrompt: 'simple addition within 10 with apples' }
]

const DEFAULT_WRITING: WritingTemplate[] = [
  { topicKey: 'writing.cn.yi', characterOrWord: '一', description: '横',
    imagePrompt: 'Chinese character 一 stroke order' },
  { topicKey: 'writing.cn.er', characterOrWord: '二', description: '两横',
    imagePrompt: 'Chinese character 二 stroke order' },
  { topicKey: 'writing.en.A', characterOrWord: 'A', description: '大写字母 A',
    imagePrompt: 'uppercase letter A stroke order' },
  { topicKey: 'writing.en.B', characterOrWord: 'B', description: '大写字母 B',
    imagePrompt: 'uppercase letter B stroke order' }
]

const DEFAULT_GENERAL: GeneralTemplate[] = [
  { topicKey: 'general.nature.seasons', dimension: 'general_nature',
    description: '认识春夏秋冬',
    imagePrompt: 'four seasons of a tree' },
  { topicKey: 'general.life.hygiene', dimension: 'general_life',
    description: '饭前便后要洗手',
    imagePrompt: 'child washing hands cartoon' },
  { topicKey: 'general.social.greetings', dimension: 'general_social',
    description: '学会打招呼说你好',
    imagePrompt: 'children greeting each other' }
]

// ============================================================
// 工具函数
// ============================================================

/** 钳制 targetSkillLevel 到 [1, 5] (默认值 0 → 2 = 初步) */
function clampSkillLevel(level: number): number {
  if (level < 1) {
    return 2
  }
  if (level > 5) {
    return 5
  }
  return level
}

/** 判断 skill_key 是否是 math 维度 (用于过滤 childSnapshot.weakSkills) */
function isMathDimension(skillKey: string): boolean {
  return VALID_MATH_DIMENSIONS.indexOf(skillKey) >= 0
}

/** 从 childSnapshot.weakSkills 中抽出所有 math_* 维度, 去重保序 */
function extractWeakMathSkills(weakSkills: string[]): string[] {
  const out: string[] = []
  const seen: string[] = []
  for (let i = 0; i < weakSkills.length; i++) {
    const k = weakSkills[i]
    if (isMathDimension(k) && seen.indexOf(k) < 0) {
      seen.push(k)
      out.push(k)
    }
  }
  return out
}

/**
 * 把 VocabTemplate 转 LessonPlanVocabItem
 */
function makeVocabItem(t: VocabTemplate): LessonPlanVocabItem {
  const v = new LessonPlanVocabItem()
  v.topicKey = t.topicKey
  v.word = t.word
  v.translation = t.translation
  v.exampleSentence = t.exampleSentence
  v.imagePrompt = t.imagePrompt
  v.difficultyHint = '幼儿'
  return v
}

/**
 * 把 MathTemplate 转 LessonPlanMathItem (level 自动钳制)
 */
function makeMathItem(t: MathTemplate): LessonPlanMathItem {
  const m = new LessonPlanMathItem()
  m.topicKey = t.topicKey
  m.dimension = t.dimension
  m.description = t.description
  m.targetSkillLevel = clampSkillLevel(t.targetSkillLevel)
  m.imagePrompt = t.imagePrompt
  return m
}

function makeWritingItem(t: WritingTemplate): LessonPlanWritingItem {
  const w = new LessonPlanWritingItem()
  w.topicKey = t.topicKey
  w.characterOrWord = t.characterOrWord
  w.description = t.description
  w.imagePrompt = t.imagePrompt
  return w
}

function makeGeneralItem(t: GeneralTemplate): LessonPlanGeneralItem {
  const g = new LessonPlanGeneralItem()
  g.topicKey = t.topicKey
  g.dimension = t.dimension
  g.description = t.description
  g.imagePrompt = t.imagePrompt
  return g
}

/**
 * 从已有列表里抽可用 item, 跳过 topicKey 已存在的, 直到取够 count 条。
 * 返回新数组 (不修改原列表)。
 */
function pickUnique<T extends HasTopicKey>(source: T[], usedKeys: string[],
  count: number): T[] {
  const out: T[] = []
  const localUsed: string[] = []
  for (let i = 0; i < source.length && out.length < count; i++) {
    const item = source[i]
    if (item.topicKey === '') {
      continue
    }
    if (usedKeys.indexOf(item.topicKey) >= 0) {
      continue
    }
    if (localUsed.indexOf(item.topicKey) >= 0) {
      continue
    }
    out.push(item)
    localUsed.push(item.topicKey)
  }
  return out
}

/**
 * 用模板补齐到 count 条, 跳过 topicKey 已在 usedKeys 中的模板。
 * 模板表整体用完仍不够 (极端情况) 时, 用占位 topicKey 续命。
 */
function padWithTemplates<T extends HasTopicKey>(templates: T[],
  usedKeys: string[], count: number, makeFromIndex: (i: number) => T): T[] {
  const out: T[] = []
  for (let i = 0; i < templates.length && out.length < count; i++) {
    const t = templates[i]
    if (usedKeys.indexOf(t.topicKey) >= 0) {
      continue
    }
    out.push(t)
    usedKeys.push(t.topicKey)
  }
  // 仍不够 → 用 placeholder 续命 (确保通过 validatePlannerOutput)
  let placeholderIdx = 0
  while (out.length < count) {
    const p = makeFromIndex(placeholderIdx)
    out.push(p)
    placeholderIdx++
  }
  return out
}

// ============================================================
// 主入口
// ============================================================

/**
 * 生成 baseline 教学计划。
 *
 * @param planDate YYYY-MM-DD 字符串
 * @param childSnapshot 备课时的 child 摘要 (允许字段全部为空)
 * @param yesterdayPlan 昨日计划 (允许为 null; 用于复用各模块内容)
 * @returns LessonPlan 必通过 validatePlannerOutput (ok=true, issues.length=0)
 */
export function generateBaselinePlan(planDate: string,
  childSnapshot: ChildSnapshot, yesterdayPlan: LessonPlan | null): LessonPlan {
  const plan = new LessonPlan()
  plan.planDate = planDate
  plan.themeTitle = '今天我们一起来探索吧'
  plan.themeDescription = '这是一份由系统自动准备的入门计划, 老师会带你慢慢学习。'
  plan.teacherNotes = '今天先用最简单的例子熟悉每个模块; 如果小朋友觉得太简单, ' +
    '可以让老师再调整难度。每完成一项都给小朋友一句鼓励。'
  plan.childSnapshot = childSnapshot

  // ---- vocab: 复用 yesterday + 默认 ----
  const usedKeys: string[] = []
  const yesterdayVocab: LessonPlanVocabItem[] =
    yesterdayPlan !== null ? yesterdayPlan.vocab : []
  const reusedVocab = pickUnique(yesterdayVocab, usedKeys, MIN_VOCAB_COUNT)
  for (let i = 0; i < reusedVocab.length; i++) {
    usedKeys.push(reusedVocab[i].topicKey)
  }
  const vocabTemplates: VocabTemplate[] = DEFAULT_VOCAB.slice()
  const paddedVocabTemplates = padWithTemplates(vocabTemplates, usedKeys, MIN_VOCAB_COUNT,
    (i): VocabTemplate => {
      const base = DEFAULT_VOCAB[i % DEFAULT_VOCAB.length]
      return {
        topicKey: `vocab.placeholder${i}`,
        word: base.word,
        translation: base.translation,
        exampleSentence: base.exampleSentence,
        imagePrompt: base.imagePrompt
      }
    })
  for (let i = 0; i < reusedVocab.length; i++) {
    plan.vocab.push(reusedVocab[i])
  }
  for (let i = 0; i < paddedVocabTemplates.length; i++) {
    plan.vocab.push(makeVocabItem(paddedVocabTemplates[i]))
  }

  // ---- math: 弱项维度优先, 否则 4 个核心默认, level 强制钳制 ----
  const weakMath = extractWeakMathSkills(childSnapshot.weakSkills)
  const mathDims: string[] = []
  // 弱项维度 (最多 4 个)
  for (let i = 0; i < weakMath.length && mathDims.length < MIN_MATH_COUNT; i++) {
    mathDims.push(weakMath[i])
  }
  // 用默认维度补齐到 MIN_MATH_COUNT, 跳过已用
  for (let i = 0; i < DEFAULT_MATH_DIMS.length && mathDims.length < MIN_MATH_COUNT; i++) {
    const d = DEFAULT_MATH_DIMS[i]
    if (mathDims.indexOf(d) < 0) {
      mathDims.push(d)
    }
  }
  // 兜底: 如果 weakMath 把 4 个都填满了但某些是弱项不在默认集, 也保证 MIN_MATH_COUNT
  while (mathDims.length < MIN_MATH_COUNT) {
    mathDims.push(DEFAULT_MATH_DIMS[mathDims.length % DEFAULT_MATH_DIMS.length])
  }
  // 为每个维度找一个对应 template; 缺则合成一个 (避免 dimension/topicKey 错配)
  for (let i = 0; i < mathDims.length; i++) {
    const dim = mathDims[i]
    const matched = DEFAULT_MATH.find((t) => t.dimension === dim)
    if (matched !== undefined) {
      plan.math.push(makeMathItem(matched))
    } else {
      const synth: MathTemplate = {
        topicKey: `math.${dim}.baseline`,
        dimension: dim,
        description: `针对${dim}维度的练习`,
        targetSkillLevel: 2,
        imagePrompt: `${dim} illustration for kids`
      }
      plan.math.push(makeMathItem(synth))
    }
  }

  // ---- writing: 复用 yesterday + 默认 ----
  const yesterdayWriting: LessonPlanWritingItem[] =
    yesterdayPlan !== null ? yesterdayPlan.writing : []
  const reusedWriting = pickUnique(yesterdayWriting, usedKeys, MIN_WRITING_COUNT)
  for (let i = 0; i < reusedWriting.length; i++) {
    usedKeys.push(reusedWriting[i].topicKey)
  }
  const writingTemplates: WritingTemplate[] = DEFAULT_WRITING.slice()
  const paddedWritingTemplates = padWithTemplates(writingTemplates, usedKeys, MIN_WRITING_COUNT,
    (i): WritingTemplate => {
      const base = DEFAULT_WRITING[i % DEFAULT_WRITING.length]
      return {
        topicKey: `writing.placeholder${i}`,
        characterOrWord: base.characterOrWord,
        description: base.description,
        imagePrompt: base.imagePrompt
      }
    })
  for (let i = 0; i < reusedWriting.length; i++) {
    plan.writing.push(reusedWriting[i])
  }
  for (let i = 0; i < paddedWritingTemplates.length; i++) {
    plan.writing.push(makeWritingItem(paddedWritingTemplates[i]))
  }

  // ---- generalKnowledge: 复用 yesterday + 默认 ----
  const yesterdayGeneral: LessonPlanGeneralItem[] =
    yesterdayPlan !== null ? yesterdayPlan.generalKnowledge : []
  const reusedGeneral = pickUnique(yesterdayGeneral, usedKeys, MIN_GENERAL_COUNT)
  for (let i = 0; i < reusedGeneral.length; i++) {
    usedKeys.push(reusedGeneral[i].topicKey)
  }
  const generalTemplates: GeneralTemplate[] = DEFAULT_GENERAL.slice()
  const paddedGeneralTemplates = padWithTemplates(generalTemplates, usedKeys, MIN_GENERAL_COUNT,
    (i): GeneralTemplate => {
      const base = DEFAULT_GENERAL[i % DEFAULT_GENERAL.length]
      return {
        topicKey: `general.placeholder${i}`,
        dimension: base.dimension,
        description: base.description,
        imagePrompt: base.imagePrompt
      }
    })
  for (let i = 0; i < reusedGeneral.length; i++) {
    plan.generalKnowledge.push(reusedGeneral[i])
  }
  for (let i = 0; i < paddedGeneralTemplates.length; i++) {
    plan.generalKnowledge.push(makeGeneralItem(paddedGeneralTemplates[i]))
  }

  return plan
}