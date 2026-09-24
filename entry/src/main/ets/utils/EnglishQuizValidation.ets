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
  // typeof 守卫: mode/question_type 为非字符串 (如 {"mode":123}) 时按空串处理, 避免 .trim() 运行时崩溃
  const modeRaw = parsed['mode']
  const modeIsString = typeof modeRaw === 'string'
  const mode = (modeIsString ? (modeRaw as string) : '').trim()
  if (NEW_MODES.indexOf(mode) >= 0) {
    const r: ResolvedQuizMode = { mode: mode, isLegacy: false }
    return r
  }
  const legacyTypeRaw = parsed['question_type']
  const legacyType = (typeof legacyTypeRaw === 'string' ? (legacyTypeRaw as string) : '').trim()
  // mode 键存在但不是字符串 → 与 mode 非法字符串 (bogus) 同款容错, 走 legacy word
  if (legacyType !== '' || mode !== '' || (!modeIsString && modeRaw !== undefined)) {
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
      return validateListenChoice(parsed, resolved.mode)
    case 'picture_word':
      return validatePictureWord(parsed, resolved.mode)
    case 'phonics_blend':
      return validatePhonicsBlend(parsed, resolved.mode)
    case 'sentence_fill':
      return validateSentenceFill(parsed, resolved.mode)
    case 'read_aloud':
      return validateReadAloud(parsed, resolved.mode)
    case 'letter_trace':
      return validateLetterTrace(parsed, resolved.mode)
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

const VOWELS: string[] = ['a', 'e', 'i', 'o', 'u']

function readString(parsed: Record<string, Object>, key: string): string {
  return ((parsed[key] as string) ?? '').trim()
}

/**
 * 校验 options: 恰 4 个非空字符串, 去重后仍 4, 大小写不敏感含 correct。
 * 返回 '' = 通过; 否则返回写给 LLM 的错误信息。
 */
function validateOptions4(optionsRaw: Object | undefined, correct: string, modeLabel: string): string {
  if (!Array.isArray(optionsRaw)) {
    return `${modeLabel} 题缺少 options (恰好 4 个英文选项, 必须包含 correct_answer)`
  }
  const arr = optionsRaw as Object[]
  if (arr.length !== 4) {
    return `${modeLabel} 题 options 必须恰好 4 个 (当前 ${arr.length} 个)`
  }
  const seen: Set<string> = new Set()
  const lower: string[] = []
  for (let i = 0; i < arr.length; i++) {
    const s = typeof arr[i] === 'string' ? (arr[i] as string).trim() : ''
    if (s === '') {
      return `${modeLabel} 题 options 含空项, 请补全后重新出题`
    }
    const k = s.toLowerCase()
    if (seen.has(k)) {
      return `${modeLabel} 题 options 有重复项「${s}」, 4 个选项必须互不相同`
    }
    seen.add(k)
    lower.push(k)
  }
  const correctLower = correct.toLowerCase()
  if (lower.indexOf(correctLower) < 0) {
    return `${modeLabel} 题 options 里没有正确答案「${correct}」, 请把它放进选项后重新出题`
  }
  return ''
}

/**
 * 解析 short 元音规则 (如 "short a") → 返回元音字母; 不可解析返回 '' (调用方仅警告不拦)。
 */
function parseShortVowelRule(rule: string): string {
  const parts = rule.toLowerCase().trim().split(/\s+/)
  if (parts.length === 2 && parts[0] === 'short' && VOWELS.indexOf(parts[1]) >= 0) {
    return parts[1]
  }
  return ''
}

/** CVC 结构且元音位 == vowel (如 short a → cat ✓, car ✗) */
function isCvcWithVowel(word: string, vowel: string): boolean {
  const w = word.toLowerCase().trim()
  if (w.length !== 3) {
    return false
  }
  // 末位 r 与元音构成 r-controlled (ar/er/ir/or/ur), 不再是短元音 → 拒绝 (如 car)
  return w[1] === vowel && VOWELS.indexOf(w[0]) < 0 && VOWELS.indexOf(w[2]) < 0 && w[2] !== 'r'
}

function validateListenChoice(parsed: Record<string, Object>, mode: string): EnglishQuizValidationResult {
  const correct = readString(parsed, 'correct_answer')
  if (correct === '') {
    return fail('listen_choice 题缺少 correct_answer (听到的那个词)', mode, false)
  }
  const optionsErr = validateOptions4(parsed['options'], correct, 'listen_choice')
  if (optionsErr !== '') {
    return fail(optionsErr, mode, false)
  }
  if (readString(parsed, 'tts_text') === '') {
    return fail('listen_choice 题缺少 tts_text (TTS 要朗读的英文词), 没有它小朋友听不到题目, 请补上后重新出题', mode, false)
  }
  return pass(mode, false)
}

function validatePictureWord(parsed: Record<string, Object>, mode: string): EnglishQuizValidationResult {
  const correct = readString(parsed, 'correct_answer')
  if (correct === '') {
    return fail('picture_word 题缺少 correct_answer (图对应的词)', mode, false)
  }
  const optionsErr = validateOptions4(parsed['options'], correct, 'picture_word')
  if (optionsErr !== '') {
    return fail(optionsErr, mode, false)
  }
  if (readString(parsed, 'image_prompt') === '') {
    return fail('picture_word 题缺少 image_prompt — 没有图片描述卡片无法出图, 请补上后重新出题', mode, false)
  }
  return pass(mode, false)
}

function validatePhonicsBlend(parsed: Record<string, Object>, mode: string): EnglishQuizValidationResult {
  const correct = readString(parsed, 'correct_answer')
  if (correct === '') {
    return fail('phonics_blend 题缺少 correct_answer', mode, false)
  }
  const optionsErr = validateOptions4(parsed['options'], correct, 'phonics_blend')
  if (optionsErr !== '') {
    return fail(optionsErr, mode, false)
  }
  const rule = readString(parsed, 'phonics_rule')
  if (rule === '') {
    return fail('phonics_blend 题缺少 phonics_rule (如「short a」), 请声明拼读规则后重新出题', mode, false)
  }
  const vowel = parseShortVowelRule(rule)
  if (vowel !== '') {
    // 可解析的 short 元音规则: correct_answer 与全部选项都必须是该元音的 CVC 词
    if (!isCvcWithVowel(correct, vowel)) {
      return fail(`phonics_blend 题的 correct_answer「${correct}」不符合 phonics_rule「${rule}」(需为 3 字母辅-元-辅且元音是 ${vowel}); 严禁混入违反规则的词 (如 r-controlled 的 car), 请重新出题`, mode, false)
    }
    const arr = parsed['options'] as Object[]
    for (let i = 0; i < arr.length; i++) {
      const s = (arr[i] as string).trim()
      if (!isCvcWithVowel(s, vowel)) {
        return fail(`phonics_blend 题的选项「${s}」不符合 phonics_rule「${rule}」, 4 个选项都必须是 ${vowel} 的短元音 CVC 词, 请重新出题`, mode, false)
      }
    }
  } else {
    console.warn('EnglishQuizValidation', `phonics_blend rule not parseable, skip structure check: "${rule}"`)
  }
  return pass(mode, false)
}

function validateSentenceFill(parsed: Record<string, Object>, mode: string): EnglishQuizValidationResult {
  const correct = readString(parsed, 'correct_answer')
  if (correct === '') {
    return fail('sentence_fill 题缺少 correct_answer (空格处的词)', mode, false)
  }
  const optionsErr = validateOptions4(parsed['options'], correct, 'sentence_fill')
  if (optionsErr !== '') {
    return fail(optionsErr, mode, false)
  }
  const pattern = readString(parsed, 'pattern')
  const blanks = pattern === '' ? 0 : pattern.split('___').length - 1
  if (pattern === '' || blanks !== 1) {
    return fail(`sentence_fill 题的 pattern 必须恰好含一个 ___ 空格 (当前 ${blanks} 个), 如「I like ___.」; 严禁 0 个或多个空, 请修正后重新出题`, mode, false)
  }
  return pass(mode, false)
}

function validateReadAloud(parsed: Record<string, Object>, mode: string): EnglishQuizValidationResult {
  const target = readString(parsed, 'target_text')
  if (target === '') {
    return fail('read_aloud 题缺少 target_text (孩子要跟读的目标句)', mode, false)
  }
  const words = target.split(/\s+/).filter((w: string): boolean => w.length > 0)
  if (words.length > 8) {
    return fail(`read_aloud 题的 target_text 共 ${words.length} 个词, 上限 8 词 (level 0-1→3 词, 2-3→5 词, 4-5→8 词), 请缩短后重新出题`, mode, false)
  }
  return pass(mode, false)
}

function validateLetterTrace(parsed: Record<string, Object>, mode: string): EnglishQuizValidationResult {
  const letter = readString(parsed, 'letter')
  const isSingleAsciiLetter = letter.length === 1 &&
    ((letter >= 'a' && letter <= 'z') || (letter >= 'A' && letter <= 'Z'))
  if (!isSingleAsciiLetter) {
    return fail(`letter_trace 题的 letter「${letter}」必须是单个英文字母 (a-z 或 A-Z)`, mode, false)
  }
  const letterCase = readString(parsed, 'case')
  if (letterCase !== 'upper' && letterCase !== 'lower') {
    return fail(`letter_trace 题的 case 必须是「upper」或「lower」(当前「${letterCase}」)`, mode, false)
  }
  return pass(mode, false)
}
