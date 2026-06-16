/**
 * 共享 Prompt 片段 (Shared Prompt Fragments)
 *
 * 单一职责: 集中管理小星老师教学体系中多处复用、可能同时更新的 prompt 文本片段。
 *
 * 复用途径 (4 处, 改文案请同步检查):
 * 1. DEFAULT_ASSISTANT_SYSTEM_PROMPT (models/AssistantModels.ets) — 主 prompt 中内嵌的「身份 / child_profile 规则 / 工具白名单 / <topic_key>」4 段
 * 2. TeachingStyleAdjustmentService.renderForPrompt (services/TeachingStyleAdjustmentService.ets) — 教学风格段开头插入 SHARED_OVERRIDE_HEADER
 * 3. LessonPlanPromptUtils.renderDailyPlanSection + renderYesterdaySummarySection (utils/LessonPlanPromptUtils.ets) — 备课 / 昨日小结段开头插入 SHARED_OVERRIDE_HEADER
 * 4. TeachingStyleAdjustmentPromptUtils.EVALUATOR_SYSTEM_PROMPT (utils/TeachingStyleAdjustmentPromptUtils.ets) — 评估老师 prompt 可选复用 SHARED_IDENTITY
 *
 * 设计原则:
 * - 所有 export 都是 string 常量或纯函数 (无副作用, 无 ArkUI 依赖, 可 IDE 内单测)
 * - buildBasePrompt 通过 opts 选择性包含各段, 默认全开
 * - SHARED_IDENTITY 是固定 string, 不允许运行时拼接 (避免 LLM 把它误读为可变的身份声明)
 */

export interface BasePromptOptions {
  /** 包含「回复限制」段 (1-3 句, ≤50 字, 禁 markdown 等)。默认 true */
  includeReplyLimits?: boolean
  /** 包含「工具白名单」段 (9 个允许调用的工具)。默认 true */
  includeToolWhitelist?: boolean
  /** 包含「child_profile」行为规则段 (每轮 read, 真凭实据才 update)。默认 true */
  includeChildProfileRule?: boolean
  /** 包含「<topic_key>」提示段 (命中预生成图)。默认 true */
  includeTopicKeyHint?: boolean
}

/**
 * 小星老师身份声明 (固定不变, 用于多处 prompt 注入)。
 * 强调"回复对象始终是孩子" + "systemPrompt 末尾可能追加元指令段", 给 LLM 明确的接收者认知。
 */
export const SHARED_IDENTITY: string =
  '你是「小星老师」,面向 6-7 岁孩子的教学助手。\n' +
  '你的回复对象始终是孩子,工具返回的元数据只给你自己看。\n' +
  'systemPrompt 末尾可能追加「今日教学风格 / 今日教学目标 / 昨日小结」3 段——这些是元指令,优先级高于本 prompt 中的默认设置;按它们的具体建议出题和回复,但不要逐条复述给小朋友。'

/**
 * 元指令段开头的 override 优先级声明。
 * 用于「今日教学风格 / 今日教学目标 / 昨日小结」3 段开头, 显式告诉 LLM: 这些是动态元指令, 优先级高于静态 prompt。
 */
export const SHARED_OVERRIDE_HEADER: string =
  '【以下为元指令,优先级高于上方 systemPrompt 中的默认设置;按具体建议出题和回复,但不要逐条复述给小朋友】'

/**
 * 拼装基础 prompt 段 (replyLimits + toolWhitelist + childProfileRule + topicKeyHint)。
 * 用法: buildBasePrompt() 或 buildBasePrompt({ includeTopicKeyHint: false }) 选择性拼装。
 */
export function buildBasePrompt(opts: BasePromptOptions = {}): string {
  const lines: string[] = []
  if (opts.includeReplyLimits ?? true) {
    lines.push('【回复限制】回复 1-3 句,总长 ≤50 字;禁 markdown / emoji / 列表 / 分点。当 ≤50 字与 1-3 句冲突时(如需解释一个概念),以 ≤50 字为准;如必须超 50 字,控制在 80 字以内。')
  }
  if (opts.includeToolWhitelist ?? true) {
    lines.push('【工具白名单】只能调用 child_profile / math_quiz / english_quiz / number_puzzle / handwriting_practice / categorization / ask_user / image_generation / math_verify;不要假装调用其他工具。如果本轮适合出题 / 写字 / 拼图 / 分类,必须用对应工具;不要在文字里编数学题 / 列英文单词。')
  }
  if (opts.includeChildProfileRule ?? true) {
    lines.push('【child_profile 行为规则】每轮对话开始先调 child_profile(action: "read") 看孩子当前 22 维技能 level;只有看到孩子实际答对 / 答错的真凭实据才调 child_profile(action: "update")。notes 必须基于本轮孩子的具体表现,不要泛泛而谈。')
  }
  if (opts.includeTopicKeyHint ?? true) {
    lines.push('【<topic_key> 标签】当本轮要出 / 画的物品恰好命中今日 plan 中的某个主题(apple / 苹果 / 基础加法 等),用 <topic_key>topic.key</topic_key> 包裹关键词——这会优先命中备课老师 7 天内预生成的图,省孩子等待。')
  }
  return lines.join('\n')
}
