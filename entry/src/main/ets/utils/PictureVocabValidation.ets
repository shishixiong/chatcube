/**
 * PictureVocabValidation - picture_vocab 出题参数预校验纯逻辑层
 *
 * 在 ToolExecutionService.handlePictureVocab 进入 pending 态 / 启动图片管线之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true), AI 据此自我修正重出。
 *
 * 设计参考 utils/CategorizationValidation.ets (预校验 + should_retry 范式)。
 *
 * 校验规则 (对照 config/BuiltinTools.ets 的 picture_vocab schema):
 *  - mode ∈ {en, zh}
 *  - options 恰好 4 个非空字符串
 *  - correct_answer 非空且在 options 里 (精确匹配)
 */

export interface PictureVocabValidationResult {
  ok: boolean
  error: string
}

function fail(msg: string): PictureVocabValidationResult {
  return { ok: false, error: msg }
}

function pass(): PictureVocabValidationResult {
  return { ok: true, error: '' }
}

/**
 * 解析并校验 AI 传来的 picture_vocab 工具调用参数。
 *
 * @param args 工具调用的 arguments JSON 字符串
 * @returns 校验结果。ok=false 时 error 字段含写给 LLM 的中文修正提示。
 */
export function validatePictureVocabArgs(args: string): PictureVocabValidationResult {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('picture_vocab 参数不是合法 JSON, 请检查后重新出题')
  }

  const mode = ((parsed['mode'] as string) ?? '').trim()
  if (mode !== 'en' && mode !== 'zh') {
    return fail(`picture_vocab 的 mode「${mode}」不合法, 必须是 en (看图选英文单词) 或 zh (看图选汉字)`)
  }

  const correct = ((parsed['correct_answer'] as string) ?? '').trim()
  if (correct === '') {
    return fail('picture_vocab 题缺少 correct_answer (正确答案)')
  }

  const optionsRaw = parsed['options']
  if (!Array.isArray(optionsRaw)) {
    return fail('picture_vocab 题必须提供 options 选项数组 (恰好 4 个, 含正确答案)')
  }
  const arr = optionsRaw as Object[]
  if (arr.length !== 4) {
    return fail(`picture_vocab 题的选项数量是 ${arr.length}, 必须恰好 4 个 (含正确答案), 请修正后重新出题`)
  }
  const options: string[] = []
  for (let i = 0; i < arr.length; i++) {
    const v = arr[i]
    if (typeof v !== 'string') {
      return fail(`picture_vocab 题的第 ${i + 1} 个选项不是字符串`)
    }
    const s = (v as string).trim()
    if (s === '') {
      return fail(`picture_vocab 题的第 ${i + 1} 个选项为空`)
    }
    options.push(s)
  }

  let found = false
  for (let i = 0; i < options.length; i++) {
    if (options[i] === correct) {
      found = true
    }
  }
  if (!found) {
    return fail(`picture_vocab 题的正确答案「${correct}」不在选项里, 请把正确答案放进 options 后重新出题`)
  }
  return pass()
}
