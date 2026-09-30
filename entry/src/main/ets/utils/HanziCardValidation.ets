/**
 * HanziCardValidation - hanzi_card（汉字小课堂）讲解参数预校验纯逻辑层
 *
 * 在 ToolExecutionService.handleHanziCard 进入 pending 态之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true), AI 据此自我修正重讲。
 *
 * 设计参考 utils/PinyinQuizValidation.ets (预校验 + should_retry 范式)。
 *
 * 校验规则 (对照 config/BuiltinTools.ets 的 hanzi_card schema / docs/chinese-teaching-prompt-v2.md §3.1):
 *  - character 是单个汉字且在 StrokeOrderData 笔顺字典内 (保证笔顺动画可播放)
 *  - pinyin 非空; 若该字命中 PinyinData 字典, 必须与字典读音一致 (防止教错读音)
 *  - radical / structure / meaning 非空; structure 在固定枚举内
 *  - stroke_count 必须等于笔顺条数 (防止笔画数讲错)
 *  - words 2-3 个且每个都含该字 (组词不跑题)
 *  - sentence 非空且含该字
 *  - lookalikes 可选, 最多 2 组, 每组 char 为单个汉字且不等于 character
 */

import { getStrokeOrder, hasStrokeOrder } from '../config/StrokeOrderData'
import { getPinyin } from '../config/PinyinData'

export interface HanziCardValidationResult {
  ok: boolean
  error: string
}

export const HANZI_STRUCTURES: string[] = ['独体字', '上下', '左右', '左中右', '上中下', '半包围', '全包围']

function fail(msg: string): HanziCardValidationResult {
  return { ok: false, error: msg }
}

function pass(): HanziCardValidationResult {
  return { ok: true, error: '' }
}

function isCJKChar(value: string): boolean {
  if (value.length !== 1) {
    return false
  }
  const code = value.charCodeAt(0)
  return code >= 0x4E00 && code <= 0x9FFF
}

/**
 * 解析并校验 AI 传来的 hanzi_card 工具调用参数。
 *
 * @param args 工具调用的 arguments JSON 字符串
 * @returns 校验结果。ok=false 时 error 字段含写给 LLM 的中文修正提示。
 */
export function validateHanziCardArgs(args: string): HanziCardValidationResult {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('hanzi_card 参数不是合法 JSON, 请检查后重新讲解')
  }

  const character = ((parsed['character'] as string) ?? '').trim()
  if (character === '') {
    return fail('hanzi_card 缺少 character (要讲的汉字)')
  }
  if (!isCJKChar(character)) {
    return fail(`hanzi_card 的 character 必须是单个汉字, 收到「${character}」`)
  }
  if (!hasStrokeOrder(character)) {
    return fail(`hanzi_card 的 character「${character}」没有笔顺数据, 请改讲笔顺字典内的字`)
  }

  const pinyin = ((parsed['pinyin'] as string) ?? '').trim()
  if (pinyin === '') {
    return fail(`hanzi_card 缺少 pinyin,「${character}」的带调拼音必须给出`)
  }
  const dictPinyin = getPinyin(character)
  if (dictPinyin !== null && pinyin !== dictPinyin) {
    return fail(`hanzi_card 的 pinyin「${pinyin}」与字典读音不符,「${character}」的正确拼音是「${dictPinyin}」, 请修正后重新讲解`)
  }

  const radical = ((parsed['radical'] as string) ?? '').trim()
  if (radical === '') {
    return fail('hanzi_card 缺少 radical (部首)')
  }

  const structure = ((parsed['structure'] as string) ?? '').trim()
  if (structure === '') {
    return fail('hanzi_card 缺少 structure (字结构)')
  }
  if (HANZI_STRUCTURES.indexOf(structure) < 0) {
    return fail(`hanzi_card 的 structure「${structure}」不在枚举内, 只能是: ${HANZI_STRUCTURES.join(' / ')}`)
  }

  const strokes = getStrokeOrder(character)
  const strokeCount = strokes !== null ? strokes.length : 0
  const declaredCount = parsed['stroke_count']
  if (typeof declaredCount !== 'number') {
    return fail('hanzi_card 缺少 stroke_count (笔画数, 数字)')
  }
  if ((declaredCount as number) !== strokeCount) {
    return fail(`hanzi_card 的 stroke_count 是 ${declaredCount}, 但「${character}」的笔顺数据是 ${strokeCount} 笔, 请修正`)
  }

  const meaning = ((parsed['meaning'] as string) ?? '').trim()
  if (meaning === '') {
    return fail('hanzi_card 缺少 meaning (一句话字义)')
  }

  const wordsRaw = parsed['words']
  if (!Array.isArray(wordsRaw)) {
    return fail('hanzi_card 必须提供 words 组词数组 (2-3 个, 每个都含该字)')
  }
  const words = wordsRaw as Object[]
  if (words.length < 2 || words.length > 3) {
    return fail(`hanzi_card 的 words 数量是 ${words.length}, 必须 2-3 个`)
  }
  for (let i = 0; i < words.length; i++) {
    const w = words[i]
    if (typeof w !== 'string' || (w as string).trim() === '') {
      return fail(`hanzi_card 的第 ${i + 1} 个组词不是非空字符串`)
    }
    if (((w as string).indexOf(character)) < 0) {
      return fail(`hanzi_card 的组词「${w as string}」不含本字「${character}」, 组词必须都含该字`)
    }
  }

  const sentence = ((parsed['sentence'] as string) ?? '').trim()
  if (sentence === '') {
    return fail('hanzi_card 缺少 sentence (例句)')
  }
  if (sentence.indexOf(character) < 0) {
    return fail(`hanzi_card 的例句「${sentence}」不含本字「${character}」`)
  }

  const lookalikesRaw = parsed['lookalikes']
  if (lookalikesRaw !== undefined && lookalikesRaw !== null) {
    if (!Array.isArray(lookalikesRaw)) {
      return fail('hanzi_card 的 lookalikes 必须是数组 [{char, pinyin, note}], 最多 2 组')
    }
    const pairs = lookalikesRaw as Object[]
    if (pairs.length > 2) {
      return fail(`hanzi_card 的 lookalikes 有 ${pairs.length} 组, 最多 2 组`)
    }
    for (let i = 0; i < pairs.length; i++) {
      const item = pairs[i] as Record<string, Object>
      const c = ((item['char'] as string) ?? '').trim()
      if (!isCJKChar(c)) {
        return fail(`hanzi_card 的第 ${i + 1} 组形近字 char 必须是单个汉字, 收到「${c}」`)
      }
      if (c === character) {
        return fail(`hanzi_card 的形近字与本体相同 (${c}), 请换成真正易混的字`)
      }
    }
  }

  const difficulty = parsed['difficulty']
  if (typeof difficulty !== 'number' || (difficulty as number) < 1 || (difficulty as number) > 3) {
    return fail('hanzi_card 的 difficulty 必须是 1-3')
  }
  return pass()
}
