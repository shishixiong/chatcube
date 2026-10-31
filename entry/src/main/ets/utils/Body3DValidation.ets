/**
 * Body3DValidation - body_3d 参数预校验纯逻辑层（spec 2026-10-31 §5）
 *
 * 在 ToolExecutionService.handleBody3D 进入 pending 态之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true)，AI 据此自行修正。
 *
 * 校验规则（对照 config/BuiltinTools.ets 的 body_3d schema）：
 *  - skill_key 必须恰为 english_vocab
 *  - focus 可选，枚举 head / body / legs / whole / all（默认 all）
 *  - words 可选，最多 8 个，且必须命中 25 个身体部位 id
 */

export interface Body3DValidationResult {
  ok: boolean
  error: string
  focus: string
  words: string[]
}

/** 25 个可点击身体部位 id，与 rawfile/body3d/assets/body-data.js 一一对应。 */
export const BODY_PART_IDS: string[] = [
  // 头部（8）
  'head',
  'hair',
  'face',
  'ear',
  'eye',
  'nose',
  'mouth',
  'teeth',
  // 身体（10）
  'neck',
  'shoulder',
  'arm',
  'elbow',
  'hand',
  'finger',
  'thumb',
  'chest',
  'belly',
  'back',
  // 下肢（4）
  'leg',
  'knee',
  'foot',
  'toe',
  // 整体（3）
  'body',
  'skin',
  'tummy'
]

const FOCUS_MODES: string[] = ['head', 'body', 'legs', 'whole', 'all']
const FOCUS_HINT: string = 'head / body / legs / whole / all'
const MAX_WORDS: number = 8


/** 部位 id 所属分组（与 body-data.js 的 grp 一致）；focus=legs 时对应 leg。 */
function bodyPartGroup(id: string): string {
  if (['head', 'hair', 'face', 'ear', 'eye', 'nose', 'mouth', 'teeth'].indexOf(id) >= 0) {
    return 'head'
  }
  if (['neck', 'shoulder', 'arm', 'elbow', 'hand', 'finger', 'thumb', 'chest', 'belly', 'back'].indexOf(id) >= 0) {
    return 'body'
  }
  if (['leg', 'knee', 'foot', 'toe'].indexOf(id) >= 0) {
    return 'leg'
  }
  return 'whole'
}

/** focus → 网页里的分组 key（legs 在数据里叫 leg）。 */
export function resolveBody3DFocusGroup(focus: string): string {
  const value: string = focus ? focus.trim().toLowerCase() : ''
  if (value === 'head' || value === 'body' || value === 'whole') {
    return value
  }
  if (value === 'legs') {
    return 'leg'
  }
  return 'all'
}

function fail(message: string): Body3DValidationResult {
  return { ok: false, error: message, focus: 'all', words: [] }
}

export function validateBody3DArgs(raw: string): Body3DValidationResult {
  let parsed: Object
  try {
    parsed = JSON.parse(raw) as Object
  } catch (_e) {
    return fail('body_3d 参数不是合法 JSON, 请检查后重新开课')
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return fail('body_3d 参数必须是 JSON 对象')
  }
  const args = parsed as Record<string, Object>

  const skillKey = args['skill_key']
  if (typeof skillKey !== 'string' || (skillKey as string).trim() !== 'english_vocab') {
    return fail('body_3d 的 skill_key 必须固定传 english_vocab（英语词汇）')
  }

  let focus: string = 'all'
  const focusValue = args['focus']
  if (focusValue !== undefined && focusValue !== null) {
    if (typeof focusValue !== 'string') {
      return fail(`body_3d 的 focus 必须是字符串：${FOCUS_HINT}`)
    }
    const normalizedFocus = (focusValue as string).trim().toLowerCase()
    if (normalizedFocus !== '') {
      if (FOCUS_MODES.indexOf(normalizedFocus) < 0) {
        return fail(`body_3d 的 focus「${normalizedFocus}」无效，只能是 ${FOCUS_HINT}`)
      }
      focus = normalizedFocus
    }
  }

  const words: string[] = []
  const wordsValue = args['words']
  if (wordsValue !== undefined && wordsValue !== null) {
    if (!Array.isArray(wordsValue)) {
      return fail('body_3d 的 words 必须是字符串数组，例如 ["head","eye","nose"]（id 用单数）')
    }
    const list = wordsValue as Object[]
    if (list.length > MAX_WORDS) {
      return fail(`body_3d 一次最多重点讲 ${MAX_WORDS} 个部位，收到 ${list.length} 个`)
    }
    for (let i = 0; i < list.length; i++) {
      const item = list[i]
      if (typeof item !== 'string') {
        return fail('body_3d 的 words 数组里只能放字符串 id')
      }
      const id = (item as string).trim().toLowerCase()
      if (BODY_PART_IDS.indexOf(id) < 0) {
        return fail(`body_3d 的 words 里「${id}」不是身体部位 id，合法 id（单数）：${BODY_PART_IDS.join(' ')}`)
      }
      if (words.indexOf(id) < 0) {
        words.push(id)
      }
    }
    // words 必须落在本次 focus 的分组里，避免「focus=legs 却先选中 head」的错位课堂。
    if (focus !== 'all') {
      const expectedGroup: string = focus === 'legs' ? 'leg' : focus
      for (let i = 0; i < words.length; i++) {
        if (bodyPartGroup(words[i]) !== expectedGroup) {
          return fail(`body_3d 的 words「${words[i]}」不属于 focus「${focus}」分组，请改 words 或把 focus 设为 all`)
        }
      }
    }
  }

  return { ok: true, error: '', focus: focus, words: words }
}
