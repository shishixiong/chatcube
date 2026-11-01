/**
 * CityEnglishValidation - city_english 参数预校验纯逻辑层（2026-11-01）
 *
 * 在 ToolExecutionService.handleCityEnglish 进入 pending 态之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true)，AI 据此自行修正。
 *
 * 设计参考 utils/RoomEnglishValidation.ets（预校验 + should_retry 范式）。
 *
 * 校验规则（对照 config/BuiltinTools.ets 的 city_english schema）：
 *  - skill_key 必须恰为 english_vocab
 *  - focus 可选，枚举 overview / main_street / school_zone / park_zone / hospital_zone，
 *    兼容别名 all（归一化为 overview）
 *  - words 可选，最多 8 个，且必须命中城市里的 50 个单词 id
 */

export interface CityEnglishValidationResult {
  ok: boolean
  error: string
  focus: string
  words: string[]
}

/** 小词城里 50 个可点击单词的 id，与 rawfile/city3d/assets/city-data.js 一一对应
 *  （地点 12 + 交通 10 + 街道 9 + 人物 8 + 自然 8 + 动物 3）。 */
export const CITY_OBJECT_IDS: string[] = [
  // places（12）
  'hospital',
  'school',
  'park',
  'supermarket',
  'bus_stop',
  'police_station',
  'fire_station',
  'library',
  'bakery',
  'cafe',
  'post_office',
  'cinema',
  // transport（10）
  'bus',
  'car',
  'taxi',
  'bicycle',
  'ambulance',
  'fire_truck',
  'school_bus',
  'truck',
  'scooter',
  'boat',
  // street（9）
  'road',
  'crosswalk',
  'traffic_light',
  'streetlight',
  'bench',
  'trash_can',
  'mailbox',
  'bridge',
  'fountain',
  // people（8）
  'teacher',
  'doctor',
  'nurse',
  'police_officer',
  'firefighter',
  'driver',
  'baker',
  'student',
  // nature（8）
  'tree',
  'flower',
  'grass',
  'pond',
  'swing',
  'slide',
  'seesaw',
  'kite',
  // animals（3）
  'duck',
  'dog',
  'bird'
]

const FOCUS_MODES: string[] = ['overview', 'main_street', 'school_zone', 'park_zone', 'hospital_zone']
const FOCUS_HINT: string = 'overview / main_street / school_zone / park_zone / hospital_zone'
const MAX_WORDS: number = 8

/** focus → 页面视图：all 与缺省都打开全城。 */
export function resolveCityEnglishView(focus: string): string {
  const value: string = focus ? focus.trim() : ''
  if (value === 'main_street' || value === 'school_zone' || value === 'park_zone' || value === 'hospital_zone') {
    return value
  }
  return 'overview'
}

function fail(msg: string): CityEnglishValidationResult {
  const r: CityEnglishValidationResult = { ok: false, error: msg, focus: 'overview', words: [] }
  return r
}

export function validateCityEnglishArgs(args: string): CityEnglishValidationResult {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('city_english 参数不是合法 JSON, 请检查后重新开课')
  }

  const skillRaw = parsed['skill_key']
  if (typeof skillRaw !== 'string') {
    return fail('city_english 的 skill_key 必须固定传 english_vocab（英语词汇）')
  }
  const skillKey = (skillRaw as string).trim()
  if (skillKey !== 'english_vocab') {
    return fail(`city_english 的 skill_key 必须固定传 english_vocab（英语词汇），收到「${skillKey}」`)
  }

  let focus = 'overview'
  const focusRaw = parsed['focus']
  if (focusRaw !== undefined && focusRaw !== null) {
    if (typeof focusRaw !== 'string') {
      return fail(`city_english 的 focus 必须是字符串：${FOCUS_HINT}`)
    }
    focus = (focusRaw as string).trim()
    if (focus === 'all' || focus === '') {
      focus = 'overview'
    }
    if (FOCUS_MODES.indexOf(focus) < 0) {
      return fail(`city_english 的 focus「${focus}」无效，只能是 ${FOCUS_HINT}`)
    }
  }

  const words: string[] = []
  const wordsRaw = parsed['words']
  if (wordsRaw !== undefined && wordsRaw !== null) {
    if (!Array.isArray(wordsRaw)) {
      return fail('city_english 的 words 必须是字符串数组，例如 ["hospital","bus","park"]')
    }
    const list = wordsRaw as Object[]
    if (list.length > MAX_WORDS) {
      return fail(`city_english 一次最多重点讲 ${MAX_WORDS} 个单词，收到 ${list.length} 个`)
    }
    for (let i = 0; i < list.length; i++) {
      const item = list[i]
      if (typeof item !== 'string') {
        return fail('city_english 的 words 数组里只能放字符串 id')
      }
      const id = (item as string).trim()
      if (id === '') {
        continue
      }
      if (CITY_OBJECT_IDS.indexOf(id) < 0) {
        return fail(`city_english 的 words 里「${id}」不是小词城里的单词 id，合法 id：${CITY_OBJECT_IDS.join(' ')}`)
      }
      if (words.indexOf(id) < 0) {
        words.push(id)
      }
    }
  }

  const result: CityEnglishValidationResult = { ok: true, error: '', focus: focus, words: words }
  return result
}
