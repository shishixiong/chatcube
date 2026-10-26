/**
 * RoomEnglishValidation - room_english 参数预校验纯逻辑层（spec 2026-10-24 §5）
 *
 * 在 ToolExecutionService.handleRoomEnglish 进入 pending 态之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true)，AI 据此自行修正。
 *
 * 设计参考 utils/MapToolValidation.ets（预校验 + should_retry 范式）。
 *
 * 校验规则（对照 config/BuiltinTools.ets 的 room_english schema）：
 *  - skill_key 必须恰为 english_vocab
 *  - focus 可选，枚举 living / dining / kitchen / child / master / all（默认 all）
 *    living / dining / kitchen 都是客餐厅这一间，child / master 会直接切到对应卧室
 *  - words 可选，最多 8 个，且必须命中三间房里的 61 个物品 id
 */

export interface RoomEnglishValidationResult {
  ok: boolean
  error: string
  focus: string
  words: string[]
}

/** 三间房里 61 件可点击物品的 id，与 rawfile/room3d/assets/scene-data.js 一一对应
 *  （客厅 15 + 餐厅 10 + 厨房 12 + 儿童房 12 + 主卧 12）。 */
export const ROOM_OBJECT_IDS: string[] = [
  'sofa',
  'coffee_table',
  'tv',
  'tv_stand',
  'remote_control',
  'rug',
  'cushion',
  'floor_lamp',
  'bookshelf',
  'book',
  'plant',
  'curtain',
  'window',
  'picture',
  'clock',
  'air_conditioner',
  'trash_can',
  'dining_table',
  'dining_chair',
  'plate',
  'bowl',
  'cup',
  'spoon',
  'fork',
  'kettle',
  'fridge',
  'stove',
  'oven',
  'sink',
  'pot',
  'pan',
  'toaster',
  'microwave',
  'dishwasher',
  'cabinet',
  'knife',
  'stool',
  // 儿童房（12）
  'bed',
  'desk',
  'chair',
  'wardrobe',
  'toy_box',
  'round_rug',
  'bookcase',
  'shelf',
  'basket',
  'poster',
  'blanket',
  'toy_car',
  // 主卧（12）
  'double_bed',
  'nightstand',
  'lamp',
  'pillow',
  'closet',
  'dresser',
  'mirror',
  'stool_master',
  'bench',
  'rug_master',
  'heater',
  'photo_frame'
]

const FOCUS_MODES: string[] = ['living', 'dining', 'kitchen', 'child', 'master', 'all']
const FOCUS_HINT: string = 'living / dining / kitchen / child / master / all'
const MAX_WORDS: number = 8

function fail(msg: string): RoomEnglishValidationResult {
  const r: RoomEnglishValidationResult = { ok: false, error: msg, focus: 'all', words: [] }
  return r
}

export function validateRoomEnglishArgs(args: string): RoomEnglishValidationResult {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('room_english 参数不是合法 JSON, 请检查后重新开课')
  }

  const skillKey = ((parsed['skill_key'] as string) ?? '').trim()
  if (skillKey !== 'english_vocab') {
    return fail(`room_english 的 skill_key 必须固定传 english_vocab（英语词汇），收到「${skillKey}」`)
  }

  let focus = 'all'
  const focusRaw = parsed['focus']
  if (focusRaw !== undefined && focusRaw !== null) {
    if (typeof focusRaw !== 'string') {
      return fail(`room_english 的 focus 必须是字符串：${FOCUS_HINT}`)
    }
    focus = (focusRaw as string).trim()
    if (FOCUS_MODES.indexOf(focus) < 0) {
      return fail(`room_english 的 focus「${focus}」无效，只能是 ${FOCUS_HINT}`)
    }
  }

  const words: string[] = []
  const wordsRaw = parsed['words']
  if (wordsRaw !== undefined && wordsRaw !== null) {
    if (!Array.isArray(wordsRaw)) {
      return fail('room_english 的 words 必须是字符串数组，例如 ["sofa","tv","rug"]')
    }
    const list = wordsRaw as Object[]
    if (list.length > MAX_WORDS) {
      return fail(`room_english 一次最多重点讲 ${MAX_WORDS} 个单词，收到 ${list.length} 个`)
    }
    for (let i = 0; i < list.length; i++) {
      const item = list[i]
      if (typeof item !== 'string') {
        return fail('room_english 的 words 数组里只能放字符串 id')
      }
      const id = (item as string).trim()
      if (id === '') {
        continue
      }
      if (ROOM_OBJECT_IDS.indexOf(id) < 0) {
        return fail(`room_english 的 words 里「${id}」不是房间里的物品 id，合法 id：${ROOM_OBJECT_IDS.join(' ')}`)
      }
      if (words.indexOf(id) < 0) {
        words.push(id)
      }
    }
  }

  const result: RoomEnglishValidationResult = { ok: true, error: '', focus: focus, words: words }
  return result
}
