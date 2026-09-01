/**
 * EnglishQuizValidation - english_quiz 出题参数预校验纯逻辑层
 *
 * 在 ToolExecutionService.handleEnglishQuiz 进入 pending 态 / 启动图片管线之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true), AI 据此自我修正重出。
 *
 * 设计参考 utils/CategorizationValidation.ets (预校验 + should_retry 范式)。
 *
 * 校验规则:
 *  - phonics_choice: correct_answer 是单个字母且在 letter_options 里 (大小写不敏感);
 *                    sound_text 非空 (TTS 播它, 空则孩子听不到题目)
 *  - word / sentence: correct_answer / question / image_prompt 非空
 *    (word 模式无 image_prompt → 图片管线生成失败 → 卡片卡 loading →
 *     pendingAnswer 永不 resolve → 会话死锁, 正是预校验要防的模式)
 */

export interface EnglishQuizValidationResult {
  ok: boolean
  error: string
}

function fail(msg: string): EnglishQuizValidationResult {
  return { ok: false, error: msg }
}

function pass(): EnglishQuizValidationResult {
  return { ok: true, error: '' }
}

/**
 * 解析并校验 AI 传来的 english_quiz 工具调用参数。
 *
 * @param args 工具调用的 arguments JSON 字符串
 * @returns 校验结果。ok=false 时 error 字段含写给 LLM 的中文修正提示。
 */
export function validateEnglishQuizArgs(args: string): EnglishQuizValidationResult {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('english_quiz 参数不是合法 JSON, 请检查后重新出题')
  }

  const questionType = ((parsed['question_type'] as string) ?? 'word').trim()
  const correct = ((parsed['correct_answer'] as string) ?? '').trim()

  if (questionType === 'phonics_choice') {
    if (correct === '') {
      return fail('phonics_choice 题缺少 correct_answer (正确字母)')
    }
    if (correct.length !== 1) {
      return fail(`phonics_choice 题的 correct_answer「${correct}」必须是单个字母`)
    }
    const sound = ((parsed['sound_text'] as string) ?? '').trim()
    if (sound === '') {
      return fail('phonics_choice 题缺少 sound_text (TTS 要朗读的字母音), 没有它小朋友听不到题目, 请补上后重新出题')
    }
    const lettersRaw = parsed['letter_options']
    if (!Array.isArray(lettersRaw)) {
      return fail('phonics_choice 题必须提供 letter_options 字母选项数组 (3-4 个字母, 含正确答案)')
    }
    const arr = lettersRaw as Object[]
    const letters: string[] = []
    for (let i = 0; i < arr.length; i++) {
      const v = arr[i]
      if (typeof v === 'string') {
        const s = (v as string).trim()
        if (s.length === 1) {
          letters.push(s.toLowerCase())
        }
      }
    }
    if (letters.length < 2) {
      return fail('phonics_choice 题的 letter_options 至少要有 2 个合法单字母选项, 请补充后重新出题')
    }
    const correctLower = correct.toLowerCase()
    let found = false
    for (let i = 0; i < letters.length; i++) {
      if (letters[i] === correctLower) {
        found = true
      }
    }
    if (!found) {
      return fail(`phonics_choice 题的 letter_options 里没有正确答案「${correct}」, 请把正确字母放进选项后重新出题`)
    }
    return pass()
  }

  // word / sentence (未知 question_type 按 parseQuiz 的默认行为视作 word)
  if (correct === '') {
    return fail(`${questionType} 题缺少 correct_answer (正确的英文单词/句子)`)
  }
  const question = ((parsed['question'] as string) ?? '').trim()
  if (question === '') {
    return fail(`${questionType} 题缺少 question (给小朋友看的中文提示语)`)
  }
  const imagePrompt = ((parsed['image_prompt'] as string) ?? '').trim()
  if (imagePrompt === '') {
    return fail(`${questionType} 题缺少 image_prompt — 没有图片描述, 卡片会一直停在加载占位上无法作答, 请补上后重新出题`)
  }
  return pass()
}
