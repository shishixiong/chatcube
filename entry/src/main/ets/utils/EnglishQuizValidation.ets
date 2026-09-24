/**
 * EnglishQuizValidation - english_quiz 出题参数预校验纯逻辑层
 *
 * 在 ToolExecutionService.handleEnglishQuiz 进入 pending 态 / 启动图片管线之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true), AI 据此自我修正重出。
 *
 * 设计参考 utils/CategorizationValidation.ets (预校验 + should_retry 范式)。
 *
 * mode 解析 (v2):
 *  - mode 字段合法 (六个新 mode 之一) → 新契约路径
 *  - 否则 question_type 非空 → legacy 路径 (未知 question_type 值仍按 parseQuiz
 *    同款容错视作 word); mode 非法但 question_type 缺失时同样容错按 legacy word
 *  - mode 与 question_type 都空 → fail
 *
 * legacy 校验规则 (与 v1 行为完全一致):
 *  - phonics_choice: correct_answer 是单个字母且在 letter_options 里 (大小写不敏感);
 *                    sound_text 非空 (TTS 播它, 空则孩子听不到题目)
 *  - word / sentence: correct_answer / question / image_prompt 非空
 *    (word 模式无 image_prompt → 图片管线生成失败 → 卡片卡 loading →
 *     pendingAnswer 永不 resolve → 会话死锁, 正是预校验要防的模式)
 */

export interface EnglishQuizValidationResult {
  ok: boolean
  error: string
  mode: string      // 六个新 mode 之一, 或 legacy 'word'/'sentence'/'phonics_choice'; 解析失败为 ''
  isLegacy: boolean
}

export interface ResolvedQuizMode {
  mode: string
  isLegacy: boolean
}

const NEW_MODES: string[] = ['listen_choice', 'picture_word', 'phonics_blend', 'sentence_fill', 'read_aloud', 'letter_trace']
const LEGACY_TYPES: string[] = ['word', 'sentence', 'phonics_choice']

/**
 * 解析出题 mode:
 * - mode 字段合法 → 新契约路径
 * - 否则 question_type 非空 → legacy 路径 (未知值容错按 word, 与 parseQuiz 默认行为一致)
 * - mode 非法且 question_type 缺失 → 也容错按 legacy word (原校验对缺 question_type 默认 word)
 * - 两者都空 → mode='' (调用方 fail)
 */
export function resolveQuizMode(parsed: Record<string, Object>): ResolvedQuizMode {
  const mode = ((parsed['mode'] as string) ?? '').trim()
  if (NEW_MODES.indexOf(mode) >= 0) {
    const r: ResolvedQuizMode = { mode: mode, isLegacy: false }
    return r
  }
  const legacyType = ((parsed['question_type'] as string) ?? '').trim()
  if (legacyType !== '' || mode !== '') {
    const effective = LEGACY_TYPES.indexOf(legacyType) >= 0 ? legacyType : 'word'
    const r: ResolvedQuizMode = { mode: effective, isLegacy: true }
    return r
  }
  const r: ResolvedQuizMode = { mode: '', isLegacy: false }
  return r
}

function fail(msg: string, mode: string, isLegacy: boolean): EnglishQuizValidationResult {
  return { ok: false, error: msg, mode: mode, isLegacy: isLegacy }
}

function pass(mode: string, isLegacy: boolean): EnglishQuizValidationResult {
  return { ok: true, error: '', mode: mode, isLegacy: isLegacy }
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
    return fail('english_quiz 参数不是合法 JSON, 请检查后重新出题', '', false)
  }
  const resolved = resolveQuizMode(parsed)
  if (resolved.mode === '') {
    return fail('english_quiz 缺少 mode 字段 (listen_choice/picture_word/phonics_blend/sentence_fill/read_aloud/letter_trace 六选一); 历史兼容的 question_type 也不再接受空值', '', false)
  }
  if (resolved.isLegacy) {
    return validateLegacyArgs(parsed, resolved.mode)
  }
  switch (resolved.mode) {
    case 'listen_choice':
    case 'picture_word':
    case 'phonics_blend':
    case 'sentence_fill':
    case 'read_aloud':
    case 'letter_trace':
      // 占位: 新 mode 校验器由 Task 3 逐个接入, 当前统一 fail 让 LLM 自行修正
      return fail(`mode「${resolved.mode}」的校验规则将在后续任务实现`, resolved.mode, false)
    default:
      return fail(`未知的 mode「${resolved.mode}」`, '', false)
  }
}

function validateLegacyArgs(parsed: Record<string, Object>, mode: string): EnglishQuizValidationResult {
  // ===== 原 validateEnglishQuizArgs 的 question_type 分支逻辑逐字搬入, 行为不变 =====
  const questionType = ((parsed['question_type'] as string) ?? 'word').trim()
  const correct = ((parsed['correct_answer'] as string) ?? '').trim()

  if (questionType === 'phonics_choice') {
    if (correct === '') {
      return fail('phonics_choice 题缺少 correct_answer (正确字母)', mode, true)
    }
    if (correct.length !== 1) {
      return fail(`phonics_choice 题的 correct_answer「${correct}」必须是单个字母`, mode, true)
    }
    const sound = ((parsed['sound_text'] as string) ?? '').trim()
    if (sound === '') {
      return fail('phonics_choice 题缺少 sound_text (TTS 要朗读的字母音), 没有它小朋友听不到题目, 请补上后重新出题', mode, true)
    }
    const lettersRaw = parsed['letter_options']
    if (!Array.isArray(lettersRaw)) {
      return fail('phonics_choice 题必须提供 letter_options 字母选项数组 (3-4 个字母, 含正确答案)', mode, true)
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
      return fail('phonics_choice 题的 letter_options 至少要有 2 个合法单字母选项, 请补充后重新出题', mode, true)
    }
    const correctLower = correct.toLowerCase()
    let found = false
    for (let i = 0; i < letters.length; i++) {
      if (letters[i] === correctLower) {
        found = true
      }
    }
    if (!found) {
      return fail(`phonics_choice 题的 letter_options 里没有正确答案「${correct}」, 请把正确字母放进选项后重新出题`, mode, true)
    }
    return pass(mode, true)
  }

  // word / sentence (未知 question_type 按 parseQuiz 的默认行为视作 word)
  if (correct === '') {
    return fail(`${questionType} 题缺少 correct_answer (正确的英文单词/句子)`, mode, true)
  }
  const question = ((parsed['question'] as string) ?? '').trim()
  if (question === '') {
    return fail(`${questionType} 题缺少 question (给小朋友看的中文提示语)`, mode, true)
  }
  const imagePrompt = ((parsed['image_prompt'] as string) ?? '').trim()
  if (imagePrompt === '') {
    return fail(`${questionType} 题缺少 image_prompt — 没有图片描述, 卡片会一直停在加载占位上无法作答, 请补上后重新出题`, mode, true)
  }
  return pass(mode, true)
}
