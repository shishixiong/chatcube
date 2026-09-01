/**
 * ListeningQuizValidation - listening_quiz 出题参数预校验纯逻辑层
 *
 * 在 ToolExecutionService.handleListeningQuiz 进入 pending 态之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true), AI 据此自我修正重出。
 *
 * 设计参考 utils/PictureVocabValidation.ets (预校验 + should_retry 范式)。
 *
 * 校验规则 (对照 config/BuiltinTools.ets 的 listening_quiz schema):
 *  - word / question 非空 (word 供 TTS 朗读, 空则题不可听)
 *  - options 恰好 4 个非空字符串
 *  - correct_answer 非空且在 options 里 (精确匹配)
 */

export interface ListeningQuizValidationResult {
  ok: boolean
  error: string
}

function fail(msg: string): ListeningQuizValidationResult {
  return { ok: false, error: msg }
}

function pass(): ListeningQuizValidationResult {
  return { ok: true, error: '' }
}

/**
 * 解析并校验 AI 传来的 listening_quiz 工具调用参数。
 *
 * @param args 工具调用的 arguments JSON 字符串
 * @returns 校验结果。ok=false 时 error 字段含写给 LLM 的中文修正提示。
 */
export function validateListeningQuizArgs(args: string): ListeningQuizValidationResult {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('listening_quiz 参数不是合法 JSON, 请检查后重新出题')
  }

  const word = ((parsed['word'] as string) ?? '').trim()
  if (word === '') {
    return fail('listening_quiz 题缺少 word (要朗读的英文单词/字母), 没有 word 卡片无法播放听力')
  }

  const question = ((parsed['question'] as string) ?? '').trim()
  if (question === '') {
    return fail('listening_quiz 题缺少 question (给孩子的题目提示语)')
  }

  const correct = ((parsed['correct_answer'] as string) ?? '').trim()
  if (correct === '') {
    return fail('listening_quiz 题缺少 correct_answer (正确答案)')
  }

  const optionsRaw = parsed['options']
  if (!Array.isArray(optionsRaw)) {
    return fail('listening_quiz 题必须提供 options 选项数组 (恰好 4 个, 含正确答案)')
  }
  const arr = optionsRaw as Object[]
  if (arr.length !== 4) {
    return fail(`listening_quiz 题的选项数量是 ${arr.length}, 必须恰好 4 个 (含正确答案), 请修正后重新出题`)
  }
  const options: string[] = []
  for (let i = 0; i < arr.length; i++) {
    const v = arr[i]
    if (typeof v !== 'string') {
      return fail(`listening_quiz 题的第 ${i + 1} 个选项不是字符串`)
    }
    const s = (v as string).trim()
    if (s === '') {
      return fail(`listening_quiz 题的第 ${i + 1} 个选项为空`)
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
    return fail(`listening_quiz 题的正确答案「${correct}」不在选项里, 请把正确答案放进 options 后重新出题`)
  }
  return pass()
}
