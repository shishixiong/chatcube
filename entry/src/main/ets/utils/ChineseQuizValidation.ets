/**
 * ChineseQuizValidation - chinese_quiz（语文小练习）出题参数预校验纯逻辑层
 *
 * 一个工具承载四种 mode (word_build / sentence_order / lookalike / antonym),
 * 校验按 mode 分派; 在 ToolExecutionService.handleChineseQuiz 进入 pending 态之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true), AI 据此自我修正重出。
 *
 * 设计参考 utils/PinyinQuizValidation.ets (预校验 + should_retry 范式) 与
 * utils/EnglishQuizValidation.ets (mode 路由器校验)。
 *
 * 校验规则 (对照 config/BuiltinTools.ets 的 chinese_quiz schema / docs/chinese-teaching-prompt-v2.md §3.4):
 *  公共: mode 四选一; difficulty 1-3
 *  - word_build 组词造句: character 单个汉字; options 恰 4 个互异; answer 在 options 内且含 character
 *  - sentence_order 连词成句: words 2-6 个互异; answer 去掉空白/标点后必须是 words 的某种排列
 *    (字符多重集相等 ⇒ 可还原为唯一通顺句, 防多解/漏词)
 *  - lookalike 形近字辨析: stem 恰含一个 ___; options 恰 4 个互异单字; answer 在 options 内
 *  - antonym 近反义词: character 单个汉字; options 恰 4 个互异; answer 在 options 内且不等于 character
 *  语义正确性 (反义词是否成立 / 组词是否成词) 无法程序判定, 交 prompt 契约约束。
 */

export interface ChineseQuizValidationResult {
  ok: boolean
  error: string
}

export type ChineseQuizMode = 'word_build' | 'sentence_order' | 'lookalike' | 'antonym'

export const CHINESE_QUIZ_MODES: string[] = ['word_build', 'sentence_order', 'lookalike', 'antonym']

function fail(msg: string): ChineseQuizValidationResult {
  return { ok: false, error: msg }
}

function pass(): ChineseQuizValidationResult {
  return { ok: true, error: '' }
}

function isCJKChar(value: string): boolean {
  if (value.length !== 1) {
    return false
  }
  const code = value.charCodeAt(0)
  return code >= 0x4E00 && code <= 0x9FFF
}

/** 去掉空白与常见中英文标点, 只留实义字符 (连词成句答案归一化用) */
function stripPunctAndSpace(value: string): string {
  return value.replace(/[\s，。！？、,.!?;；:：「」『』()（）""'']/g, '')
}

function sortedChars(value: string): string[] {
  const chars: string[] = []
  for (let i = 0; i < value.length; i++) {
    chars.push(value.charAt(i))
  }
  return chars.sort()
}

function checkChoiceOptions(parsed: Record<string, Object>): ChineseQuizValidationResult {
  const optionsRaw = parsed['options']
  if (!Array.isArray(optionsRaw)) {
    return fail('chinese_quiz 必须提供 options 选项数组 (恰好 4 个, 含正确答案)')
  }
  const arr = optionsRaw as Object[]
  if (arr.length !== 4) {
    return fail(`chinese_quiz 的选项数量是 ${arr.length}, 必须恰好 4 个 (含正确答案)`)
  }
  const seen: string[] = []
  for (let i = 0; i < arr.length; i++) {
    const v = arr[i]
    if (typeof v !== 'string' || (v as string).trim() === '') {
      return fail(`chinese_quiz 的第 ${i + 1} 个选项不是非空字符串`)
    }
    const s = (v as string).trim()
    if (seen.indexOf(s) >= 0) {
      return fail(`chinese_quiz 的选项「${s}」重复, 4 个选项必须互不相同`)
    }
    seen.push(s)
  }
  const answer = ((parsed['answer'] as string) ?? '').trim()
  if (answer === '') {
    return fail('chinese_quiz 缺少 answer (正确答案)')
  }
  if (seen.indexOf(answer) < 0) {
    return fail(`chinese_quiz 的正确答案「${answer}」不在选项里, 请把正确答案放进 options 后重新出题`)
  }
  return pass()
}

/**
 * 解析并校验 AI 传来的 chinese_quiz 工具调用参数。
 *
 * @param args 工具调用的 arguments JSON 字符串
 * @returns 校验结果。ok=false 时 error 字段含写给 LLM 的中文修正提示。
 */
export function validateChineseQuizArgs(args: string): ChineseQuizValidationResult {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('chinese_quiz 参数不是合法 JSON, 请检查后重新出题')
  }

  const mode = ((parsed['mode'] as string) ?? '').trim()
  if (CHINESE_QUIZ_MODES.indexOf(mode) < 0) {
    return fail(`chinese_quiz 的 mode「${mode}」不合法, 只能是: ${CHINESE_QUIZ_MODES.join(' / ')}`)
  }

  if (mode === 'sentence_order') {
    const wordsRaw = parsed['words']
    if (!Array.isArray(wordsRaw)) {
      return fail('chinese_quiz(mode:sentence_order) 必须提供 words 打乱词卡数组 (2-6 个)')
    }
    const words = wordsRaw as Object[]
    if (words.length < 2 || words.length > 6) {
      return fail(`chinese_quiz(mode:sentence_order) 的 words 数量是 ${words.length}, 必须 2-6 个`)
    }
    const seen: string[] = []
    for (let i = 0; i < words.length; i++) {
      const w = words[i]
      if (typeof w !== 'string' || (w as string).trim() === '') {
        return fail(`chinese_quiz(mode:sentence_order) 的第 ${i + 1} 个词卡不是非空字符串`)
      }
      const s = (w as string).trim()
      if (seen.indexOf(s) >= 0) {
        return fail(`chinese_quiz(mode:sentence_order) 的词卡「${s}」重复`)
      }
      seen.push(s)
    }
    const answer = ((parsed['answer'] as string) ?? '').trim()
    if (answer === '') {
      return fail('chinese_quiz(mode:sentence_order) 缺少 answer (正确顺序拼接的句子)')
    }
    const normalizedAnswer = stripPunctAndSpace(answer)
    const normalizedWords = stripPunctAndSpace(seen.join(''))
    if (normalizedAnswer === '') {
      return fail('chinese_quiz(mode:sentence_order) 的 answer 去掉标点后为空, 请给通顺完整句')
    }
    // 字符多重集相等 ⇒ answer 可由 words 还原 (防多解/漏词/错字)
    const answerSorted = sortedChars(normalizedAnswer).join('')
    const wordsSorted = sortedChars(normalizedWords).join('')
    if (answerSorted !== wordsSorted) {
      return fail(`chinese_quiz(mode:sentence_order) 的 answer「${answer}」无法由词卡 [${seen.join('、')}] 排列还原, 请保证词序打乱但答案可拼出且唯一通顺`)
    }
  } else if (mode === 'word_build') {
    const character = ((parsed['character'] as string) ?? '').trim()
    if (!isCJKChar(character)) {
      return fail(`chinese_quiz(mode:word_build) 的 character 必须是单个汉字, 收到「${character}」`)
    }
    const optionsCheck = checkChoiceOptions(parsed)
    if (!optionsCheck.ok) {
      return optionsCheck
    }
    const answer = ((parsed['answer'] as string) ?? '').trim()
    if (answer.indexOf(character) < 0) {
      return fail(`chinese_quiz(mode:word_build) 的正确答案「${answer}」不含本字「${character}」, 请给能跟它组词的词`)
    }
  } else if (mode === 'lookalike') {
    const stem = ((parsed['stem'] as string) ?? '').trim()
    if (stem === '') {
      return fail('chinese_quiz(mode:lookalike) 缺少 stem (含 ___ 空位的句子)')
    }
    const firstBlank = stem.indexOf('___')
    if (firstBlank < 0) {
      return fail('chinese_quiz(mode:lookalike) 的 stem 必须恰含一个 ___ 空位')
    }
    if (stem.indexOf('___', firstBlank + 1) >= 0) {
      return fail('chinese_quiz(mode:lookalike) 的 stem 只能有 1 个 ___ 空位')
    }
    const optionsRaw = parsed['options']
    if (Array.isArray(optionsRaw)) {
      const arr = optionsRaw as Object[]
      for (let i = 0; i < arr.length; i++) {
        const v = arr[i]
        if (typeof v === 'string' && !isCJKChar((v as string).trim())) {
          return fail(`chinese_quiz(mode:lookalike) 的选项「${typeof v === 'string' ? (v as string).trim() : ''}」必须是单个汉字`)
        }
      }
    }
    const optionsCheck = checkChoiceOptions(parsed)
    if (!optionsCheck.ok) {
      return optionsCheck
    }
  } else {
    // antonym
    const character = ((parsed['character'] as string) ?? '').trim()
    if (!isCJKChar(character)) {
      return fail(`chinese_quiz(mode:antonym) 的 character 必须是单个汉字, 收到「${character}」`)
    }
    const optionsCheck = checkChoiceOptions(parsed)
    if (!optionsCheck.ok) {
      return optionsCheck
    }
    const answer = ((parsed['answer'] as string) ?? '').trim()
    if (answer === character) {
      return fail(`chinese_quiz(mode:antonym) 的答案与 character 相同 (${character}), 请给意思相反的词`)
    }
  }

  const difficulty = parsed['difficulty']
  if (typeof difficulty !== 'number' || (difficulty as number) < 1 || (difficulty as number) > 3) {
    return fail('chinese_quiz 的 difficulty 必须是 1-3')
  }
  return pass()
}
