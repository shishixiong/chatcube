/**
 * PinyinCardValidation - pinyin_card（拼音小课堂）讲解参数预校验纯逻辑层
 *
 * 在 ToolExecutionService.handlePinyinCard 进入 pending 态之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true), AI 据此自我修正重讲。
 *
 * 设计参考 utils/PinyinQuizValidation.ets (预校验 + should_retry 范式)。
 *
 * 校验规则 (对照 config/BuiltinTools.ets 的 pinyin_card schema / docs/chinese-teaching-prompt-v2.md §3.2):
 *  - final 非空; initial 可为空串 (零声母, 如「安 ān」)
 *  - tone 0-4 (0=轻声)
 *  - syllable 必须等于 initial + final + 调号 (调号位置按汉语拼音标调规则程序推导)
 *  - examples 至少 2 条四声示范, 每条 {tone 0-4, syllable 非空, char 单个汉字, word 非空}
 *  - mnemonic 口诀非空
 *  - contrast 可选, 每条 {a, b, tip} 非空
 */

export interface PinyinCardValidationResult {
  ok: boolean
  error: string
}

function fail(msg: string): PinyinCardValidationResult {
  return { ok: false, error: msg }
}

function pass(): PinyinCardValidationResult {
  return { ok: true, error: '' }
}

// 带调字母表: TONE_MARKS[vowel][tone] (tone 1-4; 0=轻声不加调号)
const TONE_MARKS: Record<string, string> = {
  'a1': 'ā', 'a2': 'á', 'a3': 'ǎ', 'a4': 'à',
  'o1': 'ō', 'o2': 'ó', 'o3': 'ǒ', 'o4': 'ò',
  'e1': 'ē', 'e2': 'é', 'e3': 'ě', 'e4': 'è',
  'i1': 'ī', 'i2': 'í', 'i3': 'ǐ', 'i4': 'ì',
  'u1': 'ū', 'u2': 'ú', 'u3': 'ǔ', 'u4': 'ù',
  'ü1': 'ǖ', 'ü2': 'ǘ', 'ü3': 'ǚ', 'ü4': 'ǜ'
}

const VOWELS: string[] = ['a', 'o', 'e', 'i', 'u', 'ü']

/**
 * 按「a 优先, 其次 o e, iu/ui 标在后」的标准规则把调号标到 final 的元音上,
 * 返回带调韵母。无法标调 (final 无元音) 返回原串。
 */
export function applyToneMark(final: string, tone: number): string {
  if (tone < 1 || tone > 4) {
    return final
  }
  const lower = final.toLowerCase()
  // 标调优先级: a > o > e > (i/u 并存时标在后) > 其余首个元音
  let target = -1
  for (let v = 0; v < 3 && target < 0; v++) {
    target = lower.indexOf(VOWELS[v])
  }
  if (target < 0) {
    const iPos = lower.indexOf('i')
    const uPos = lower.indexOf('u')
    if (iPos >= 0 && uPos >= 0) {
      target = Math.max(iPos, uPos)
    } else {
      for (let v = 3; v < VOWELS.length && target < 0; v++) {
        target = lower.indexOf(VOWELS[v])
      }
    }
  }
  if (target < 0) {
    return final
  }
  const vowel = lower.charAt(target)
  const mark = TONE_MARKS[`${vowel}${tone}`]
  if (mark === undefined) {
    return final
  }
  return final.substring(0, target) + mark + final.substring(target + 1)
}

/** 拼合 syllable = initial + 带调 final。tone 0 (轻声) 不加调号。 */
export function composeSyllable(initial: string, final: string, tone: number): string {
  return initial + applyToneMark(final, tone)
}

function isCJKChar(value: string): boolean {
  if (value.length !== 1) {
    return false
  }
  const code = value.charCodeAt(0)
  return code >= 0x4E00 && code <= 0x9FFF
}

/**
 * 解析并校验 AI 传来的 pinyin_card 工具调用参数。
 *
 * @param args 工具调用的 arguments JSON 字符串
 * @returns 校验结果。ok=false 时 error 字段含写给 LLM 的中文修正提示。
 */
export function validatePinyinCardArgs(args: string): PinyinCardValidationResult {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('pinyin_card 参数不是合法 JSON, 请检查后重新讲解')
  }

  const initial = ((parsed['initial'] as string) ?? '').trim()
  const final = ((parsed['final'] as string) ?? '').trim()
  if (final === '') {
    return fail('pinyin_card 缺少 final (韵母)')
  }

  const toneRaw = parsed['tone']
  if (typeof toneRaw !== 'number' || (toneRaw as number) < 0 || (toneRaw as number) > 4) {
    return fail('pinyin_card 的 tone 必须是 0-4 (0=轻声, 1-4=四声)')
  }
  const tone = toneRaw as number

  const syllable = ((parsed['syllable'] as string) ?? '').trim()
  if (syllable === '') {
    return fail('pinyin_card 缺少 syllable (带调音节)')
  }
  const expected = composeSyllable(initial, final, tone)
  if (syllable !== expected) {
    return fail(`pinyin_card 的 syllable「${syllable}」与 initial+final+调号 拼合结果不符, 应为「${expected}」, 请修正`)
  }

  const examplesRaw = parsed['examples']
  if (!Array.isArray(examplesRaw)) {
    return fail('pinyin_card 必须提供 examples 四声示范数组 (至少 2 条)')
  }
  const examples = examplesRaw as Object[]
  if (examples.length < 2) {
    return fail(`pinyin_card 的 examples 只有 ${examples.length} 条, 至少 2 条四声示范`)
  }
  for (let i = 0; i < examples.length; i++) {
    const item = examples[i] as Record<string, Object>
    const exTone = item['tone']
    if (typeof exTone !== 'number' || (exTone as number) < 0 || (exTone as number) > 4) {
      return fail(`pinyin_card 的第 ${i + 1} 条示范 tone 必须是 0-4`)
    }
    const exSyllable = ((item['syllable'] as string) ?? '').trim()
    if (exSyllable === '') {
      return fail(`pinyin_card 的第 ${i + 1} 条示范缺少 syllable`)
    }
    const exChar = ((item['char'] as string) ?? '').trim()
    if (!isCJKChar(exChar)) {
      return fail(`pinyin_card 的第 ${i + 1} 条示范 char 必须是单个汉字, 收到「${exChar}」`)
    }
    const exWord = ((item['word'] as string) ?? '').trim()
    if (exWord === '') {
      return fail(`pinyin_card 的第 ${i + 1} 条示范缺少 word (含例字的词)`)
    }
  }

  const mnemonic = ((parsed['mnemonic'] as string) ?? '').trim()
  if (mnemonic === '') {
    return fail('pinyin_card 缺少 mnemonic (拼读/记忆口诀)')
  }

  const contrastRaw = parsed['contrast']
  if (contrastRaw !== undefined && contrastRaw !== null) {
    if (!Array.isArray(contrastRaw)) {
      return fail('pinyin_card 的 contrast 必须是数组 [{a, b, tip}]')
    }
    const pairs = contrastRaw as Object[]
    for (let i = 0; i < pairs.length; i++) {
      const item = pairs[i] as Record<string, Object>
      const a = ((item['a'] as string) ?? '').trim()
      const b = ((item['b'] as string) ?? '').trim()
      const tip = ((item['tip'] as string) ?? '').trim()
      if (a === '' || b === '' || tip === '') {
        return fail(`pinyin_card 的第 ${i + 1} 条易混对比缺少 a / b / tip`)
      }
    }
  }

  const difficulty = parsed['difficulty']
  if (typeof difficulty !== 'number' || (difficulty as number) < 1 || (difficulty as number) > 3) {
    return fail('pinyin_card 的 difficulty 必须是 1-3')
  }
  return pass()
}
