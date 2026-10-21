// entry/src/main/ets/components/map/MapQuizTypes.ets
/**
 * MapQuizTypes - map_quiz 三 body 共享的参数/回执类型与解析
 *
 * 参数契约（spec 2026-10-21 §5.2）: { mode: choice|locate|write, province, clue?, skill_key }
 * 预校验已在 ToolExecutionService 分发前完成（validateMapQuizArgs + should_retry），
 * 这里只做 JSON.parse 守卫与字符串收窄，坏参数走 invalid 兜底。
 */

export interface MapQuizAnswerPayload {
  answered: boolean
  mode: string
  province: string
  province_id: string
  clue: string
  child_answer: string
  correct: boolean
  cancelled?: boolean
  skill_key: string
}

export interface MapQuizArgsView {
  valid: boolean
  mode: string
  province: string
  clue: string
  skillKey: string
}

function createDefaultArgsView(): MapQuizArgsView {
  const view: MapQuizArgsView = { valid: false, mode: 'choice', province: '', clue: 'name', skillKey: 'general_social' }
  return view
}

export function parseMapQuizArgs(raw: string): MapQuizArgsView {
  const view: MapQuizArgsView = createDefaultArgsView()
  try {
    const obj = JSON.parse(raw) as Record<string, Object>
    const mode: Object | undefined = obj['mode']
    if (typeof mode !== 'string') {
      return createDefaultArgsView()
    }
    const m = (mode as string).trim()
    if (m !== 'choice' && m !== 'locate' && m !== 'write') {
      return createDefaultArgsView()
    }
    const province: Object | undefined = obj['province']
    if (typeof province !== 'string' || (province as string).trim() === '') {
      return createDefaultArgsView()
    }
    view.valid = true
    view.mode = m
    view.province = (province as string).trim()
    const clue: Object | undefined = obj['clue']
    if (typeof clue === 'string' && (clue as string).trim() === 'capital') {
      view.clue = 'capital'
    } else {
      view.clue = 'name'
    }
    const skill: Object | undefined = obj['skill_key']
    if (typeof skill === 'string' && (skill as string).trim() !== '') {
      view.skillKey = (skill as string).trim()
    }
  } catch (_e) {
    return createDefaultArgsView()
  }
  return view
}
