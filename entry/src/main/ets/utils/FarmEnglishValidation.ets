/**
 * FarmEnglishValidation - farm_english 参数预校验纯逻辑层（2026-11-06）
 *
 * 在 ToolExecutionService.handleFarmEnglish 进入 pending 态之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true)，AI 据此自行修正。
 *
 * 设计参考 utils/CityEnglishValidation.ets（预校验 + should_retry 范式）。
 *
 * 校验规则（对照 config/BuiltinTools.ets 的 farm_english schema）：
 *  - skill_key 必须恰为 english_vocab
 *  - focus 可选，枚举 overview / farmyard_zone / field_zone / pasture_zone / orchard_pond_zone，
 *    兼容别名 all（归一化为 overview）
 *  - words 可选，最多 8 个，且必须命中阳光农场里的 50 个单词 id
 */

export interface FarmEnglishValidationResult {
  ok: boolean
  error: string
  focus: string
  words: string[]
}

/** 阳光农场里 50 个可点击单词的 id，与 rawfile/farm3d/assets/farm-data.js 一一对应
 *  （地点 10 + 动物 14 + 农作物 10 + 农机 8 + 自然 5 + 人物 3）。 */
export const FARM_OBJECT_IDS: string[] = [
  // places（10）
  'farmhouse',
  'barn',
  'chicken_coop',
  'stable',
  'silo',
  'windmill',
  'greenhouse',
  'well',
  'gate',
  'fence',
  // animals（14）
  'cow',
  'pig',
  'sheep',
  'horse',
  'goat',
  'chicken',
  'rooster',
  'duck',
  'goose',
  'rabbit',
  'cat',
  'dog',
  'bee',
  'bird',
  // crops（10）
  'wheat',
  'corn',
  'potato',
  'carrot',
  'tomato',
  'pumpkin',
  'apple',
  'strawberry',
  'sunflower',
  'hay',
  // machines（8）
  'tractor',
  'trailer',
  'plow',
  'harvester',
  'wheelbarrow',
  'watering_can',
  'shovel',
  'pitchfork',
  // nature（5）
  'tree',
  'grass',
  'flower',
  'pond',
  'hill',
  // people（3）
  'farmer',
  'child',
  'grandma'
]

const FOCUS_MODES: string[] = ['overview', 'farmyard_zone', 'field_zone', 'pasture_zone', 'orchard_pond_zone']
const FOCUS_HINT: string = 'overview / farmyard_zone / field_zone / pasture_zone / orchard_pond_zone'
const MAX_WORDS: number = 8

/** focus → 页面视图：all 与缺省都打开全农场。 */
export function resolveFarmEnglishView(focus: string): string {
  const value: string = focus ? focus.trim() : ''
  if (value === 'farmyard_zone' || value === 'field_zone' || value === 'pasture_zone' ||
    value === 'orchard_pond_zone') {
    return value
  }
  return 'overview'
}

function fail(msg: string): FarmEnglishValidationResult {
  const r: FarmEnglishValidationResult = { ok: false, error: msg, focus: 'overview', words: [] }
  return r
}

export function validateFarmEnglishArgs(args: string): FarmEnglishValidationResult {
  let parsedAny: Object
  try {
    parsedAny = JSON.parse(args) as Object
  } catch (_e) {
    return fail('farm_english 参数不是合法 JSON, 请检查后重新开课')
  }
  // JSON.parse('null'/'[]'/'123') 不抛错，必须挡住非对象文档，否则读字段时抛 TypeError 绕过 should_retry。
  if (parsedAny === null || typeof parsedAny !== 'object' || Array.isArray(parsedAny)) {
    return fail('farm_english 参数必须是 JSON 对象, 例如 {"skill_key":"english_vocab"}')
  }
  const parsed = parsedAny as Record<string, Object>

  const skillRaw = parsed['skill_key']
  if (typeof skillRaw !== 'string') {
    return fail('farm_english 的 skill_key 必须固定传 english_vocab（英语词汇）')
  }
  const skillKey = (skillRaw as string).trim()
  if (skillKey !== 'english_vocab') {
    return fail(`farm_english 的 skill_key 必须固定传 english_vocab（英语词汇），收到「${skillKey}」`)
  }

  let focus = 'overview'
  const focusRaw = parsed['focus']
  if (focusRaw !== undefined && focusRaw !== null) {
    if (typeof focusRaw !== 'string') {
      return fail(`farm_english 的 focus 必须是字符串：${FOCUS_HINT}`)
    }
    focus = (focusRaw as string).trim()
    if (focus === 'all' || focus === '') {
      focus = 'overview'
    }
    if (FOCUS_MODES.indexOf(focus) < 0) {
      return fail(`farm_english 的 focus「${focus}」无效，只能是 ${FOCUS_HINT}`)
    }
  }

  const words: string[] = []
  const wordsRaw = parsed['words']
  if (wordsRaw !== undefined && wordsRaw !== null) {
    if (!Array.isArray(wordsRaw)) {
      return fail('farm_english 的 words 必须是字符串数组，例如 ["cow","wheat","tractor"]')
    }
    const list = wordsRaw as Object[]
    if (list.length > MAX_WORDS) {
      return fail(`farm_english 一次最多重点讲 ${MAX_WORDS} 个单词，收到 ${list.length} 个`)
    }
    for (let i = 0; i < list.length; i++) {
      const item = list[i]
      if (typeof item !== 'string') {
        return fail('farm_english 的 words 数组里只能放字符串 id')
      }
      const id = (item as string).trim()
      if (id === '') {
        continue
      }
      if (FARM_OBJECT_IDS.indexOf(id) < 0) {
        return fail(`farm_english 的 words 里「${id}」不是阳光农场里的单词 id，合法 id：${FARM_OBJECT_IDS.join(' ')}`)
      }
      if (words.indexOf(id) < 0) {
        words.push(id)
      }
    }
  }

  const result: FarmEnglishValidationResult = { ok: true, error: '', focus: focus, words: words }
  return result
}
