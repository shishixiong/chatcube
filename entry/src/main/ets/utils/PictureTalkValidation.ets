/**
 * PictureTalkValidation - picture_talk（看图说话）表达参数预校验纯逻辑层
 *
 * 在 ToolExecutionService.handlePictureTalk 进入 pending 态与生图之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true), AI 据此自我修正重出。
 *
 * 设计参考 utils/PinyinQuizValidation.ets (预校验 + should_retry 范式)。
 *
 * 校验规则 (对照 config/BuiltinTools.ets 的 picture_talk schema / docs/chinese-teaching-prompt-v2.md §3.3):
 *  - image_prompt 非空 (英文单场景图像描述, 交 image_generation 生图)
 *  - scene 非空 (给孩子看的一句话场景说明)
 *  - questions 1-3 个且各有非空 q (谁 / 在哪里 / 在做什么 / 怎么样)
 *  - words 2-6 个可用词提示 (推荐 3-5)
 *  - sample 示范完整句非空
 */

export interface PictureTalkValidationResult {
  ok: boolean
  error: string
}

function fail(msg: string): PictureTalkValidationResult {
  return { ok: false, error: msg }
}

function pass(): PictureTalkValidationResult {
  return { ok: true, error: '' }
}

/**
 * 解析并校验 AI 传来的 picture_talk 工具调用参数。
 *
 * @param args 工具调用的 arguments JSON 字符串
 * @returns 校验结果。ok=false 时 error 字段含写给 LLM 的中文修正提示。
 */
export function validatePictureTalkArgs(args: string): PictureTalkValidationResult {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('picture_talk 参数不是合法 JSON, 请检查后重新出卡')
  }

  const imagePrompt = ((parsed['image_prompt'] as string) ?? '').trim()
  if (imagePrompt === '') {
    return fail('picture_talk 缺少 image_prompt (英文单场景图像描述, 用于生成图片)')
  }
  if (imagePrompt.length > 500) {
    return fail('picture_talk 的 image_prompt 过长 (超 500 字符), 请精简为单场景描述')
  }

  const scene = ((parsed['scene'] as string) ?? '').trim()
  if (scene === '') {
    return fail('picture_talk 缺少 scene (给孩子看的一句话场景说明)')
  }

  const questionsRaw = parsed['questions']
  if (!Array.isArray(questionsRaw)) {
    return fail('picture_talk 必须提供 questions 引导问题数组 (1-3 个)')
  }
  const questions = questionsRaw as Object[]
  if (questions.length < 1 || questions.length > 3) {
    return fail(`picture_talk 的 questions 数量是 ${questions.length}, 必须 1-3 个 (谁 / 在哪里 / 在做什么)`)
  }
  for (let i = 0; i < questions.length; i++) {
    const item = questions[i] as Record<string, Object>
    const q = ((item['q'] as string) ?? '').trim()
    if (q === '') {
      return fail(`picture_talk 的第 ${i + 1} 个引导问题缺少 q 文本`)
    }
  }

  const wordsRaw = parsed['words']
  if (!Array.isArray(wordsRaw)) {
    return fail('picture_talk 必须提供 words 可用词提示数组 (3-5 个)')
  }
  const words = wordsRaw as Object[]
  if (words.length < 2 || words.length > 6) {
    return fail(`picture_talk 的 words 数量是 ${words.length}, 应为 3-5 个 (2-6 可接受)`)
  }
  for (let i = 0; i < words.length; i++) {
    const w = words[i]
    if (typeof w !== 'string' || (w as string).trim() === '') {
      return fail(`picture_talk 的第 ${i + 1} 个可用词不是非空字符串`)
    }
  }

  const sample = ((parsed['sample'] as string) ?? '').trim()
  if (sample === '') {
    return fail('picture_talk 缺少 sample (示范完整句)')
  }

  const difficulty = parsed['difficulty']
  if (typeof difficulty !== 'number' || (difficulty as number) < 1 || (difficulty as number) > 3) {
    return fail('picture_talk 的 difficulty 必须是 1-3')
  }
  return pass()
}
