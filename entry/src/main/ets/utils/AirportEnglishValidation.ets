/**
 * AirportEnglishValidation - airport_english 参数预校验纯逻辑层（2026-11-20）
 *
 * 在 ToolExecutionService.handleAirportEnglish 进入 pending 态之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true)，AI 据此自行修正。
 *
 * 设计参考 utils/FarmEnglishValidation.ets（预校验 + should_retry 范式），
 * 但没有 time_of_day / weather（机场 v1 不做昼夜/天气）。
 *
 * 校验规则（对照 config/BuiltinTools.ets 的 airport_english schema）：
 *  - skill_key 必须恰为 english_vocab
 *  - focus 可选，枚举 overview / terminal_zone / apron_zone / runway_zone / hangar_zone，
 *    兼容别名 all（归一化为 overview）
 *  - words 可选，最多 8 个，且必须命中机场词表（表可增长）
 */

export interface AirportEnglishValidationResult {
  ok: boolean
  error: string
  focus: string
  words: string[]
}

/** 机场里可点击单词的 id，与 rawfile/airport3d/assets/airport-data.js 一一对应
 *  （地点 14 + 飞机 6 + 车辆 12 + 人物 5 + 设施 13 = 50）。 */
export const AIRPORT_WORD_IDS: string[] = [
  // places（14）
  'terminal',
  'control_tower',
  'runway',
  'taxiway',
  'apron',
  'hangar',
  'cargo_shed',
  'fire_station',
  'airport_hotel',
  'car_park',
  'jet_bridge',
  'gate',
  'check_in',
  'baggage_carousel',
  // aircraft（6）
  'airplane',
  'jet',
  'turboprop',
  'private_jet',
  'cargo_plane',
  'helicopter',
  // vehicles（12）
  'pushback_tug',
  'baggage_tug',
  'baggage_cart',
  'container_loader',
  'belt_loader',
  'fuel_truck',
  'catering_truck',
  'airstairs_truck',
  'airport_bus',
  'follow_me_car',
  'fire_truck',
  'sweeper',
  // people（5）
  'pilot',
  'flight_attendant',
  'traveller',
  'security_officer',
  'baggage_handler',
  // facilities（13）
  'windsock',
  'radar',
  'beacon',
  'runway_lights',
  'papi',
  'sign',
  'fuel_tank',
  'floodlight',
  'passport_control',
  'x_ray',
  'departures_board',
  'moving_walkway',
  'escalator'
]

const FOCUS_MODES: string[] = ['overview', 'terminal_zone', 'apron_zone', 'runway_zone', 'hangar_zone']
const FOCUS_HINT: string = 'overview / terminal_zone / apron_zone / runway_zone / hangar_zone'
const MAX_WORDS: number = 8

/** focus → 页面视图：all 与缺省都打开全机场。 */
export function resolveAirportEnglishView(focus: string): string {
  const value: string = focus ? focus.trim() : ''
  if (value === 'terminal_zone' || value === 'apron_zone' || value === 'runway_zone' ||
    value === 'hangar_zone') {
    return value
  }
  return 'overview'
}

function fail(msg: string): AirportEnglishValidationResult {
  const r: AirportEnglishValidationResult = {
    ok: false,
    error: msg,
    focus: 'overview',
    words: []
  }
  return r
}

export function validateAirportEnglishArgs(args: string): AirportEnglishValidationResult {
  let parsedAny: Object
  try {
    parsedAny = JSON.parse(args) as Object
  } catch (_e) {
    return fail('airport_english 参数不是合法 JSON, 请检查后重新开课')
  }
  // JSON.parse('null'/'[]'/'123') 不抛错，必须挡住非对象文档，否则读字段时抛 TypeError 绕过 should_retry。
  if (parsedAny === null || typeof parsedAny !== 'object' || Array.isArray(parsedAny)) {
    return fail('airport_english 参数必须是 JSON 对象, 例如 {"skill_key":"english_vocab"}')
  }
  const parsed = parsedAny as Record<string, Object>

  const skillRaw = parsed['skill_key']
  if (typeof skillRaw !== 'string') {
    return fail('airport_english 的 skill_key 必须固定传 english_vocab（英语词汇）')
  }
  const skillKey = (skillRaw as string).trim()
  if (skillKey !== 'english_vocab') {
    return fail(`airport_english 的 skill_key 必须固定传 english_vocab（英语词汇），收到「${skillKey}」`)
  }

  let focus = 'overview'
  const focusRaw = parsed['focus']
  if (focusRaw !== undefined && focusRaw !== null) {
    if (typeof focusRaw !== 'string') {
      return fail(`airport_english 的 focus 必须是字符串：${FOCUS_HINT}`)
    }
    focus = (focusRaw as string).trim()
    if (focus === 'all' || focus === '') {
      focus = 'overview'
    }
    if (FOCUS_MODES.indexOf(focus) < 0) {
      return fail(`airport_english 的 focus「${focus}」无效，只能是 ${FOCUS_HINT}`)
    }
  }

  const words: string[] = []
  const wordsRaw = parsed['words']
  if (wordsRaw !== undefined && wordsRaw !== null) {
    if (!Array.isArray(wordsRaw)) {
      return fail('airport_english 的 words 必须是字符串数组，例如 ["airplane","pilot","runway"]')
    }
    const list = wordsRaw as Object[]
    if (list.length > MAX_WORDS) {
      return fail(`airport_english 一次最多重点讲 ${MAX_WORDS} 个单词，收到 ${list.length} 个`)
    }
    for (let i = 0; i < list.length; i++) {
      const item = list[i]
      if (typeof item !== 'string') {
        return fail('airport_english 的 words 数组里只能放字符串 id')
      }
      const id = (item as string).trim()
      if (id === '') {
        continue
      }
      if (AIRPORT_WORD_IDS.indexOf(id) < 0) {
        return fail(`airport_english 的 words 里「${id}」不是机场里的单词 id，合法 id：${AIRPORT_WORD_IDS.join(' ')}`)
      }
      if (words.indexOf(id) < 0) {
        words.push(id)
      }
    }
  }

  const result: AirportEnglishValidationResult = {
    ok: true,
    error: '',
    focus: focus,
    words: words
  }
  return result
}
