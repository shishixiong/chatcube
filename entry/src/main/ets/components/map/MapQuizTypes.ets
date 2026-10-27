// entry/src/main/ets/components/map/MapQuizTypes.ets
/**
 * MapQuizTypes - map_quiz 三 body 共享的参数/回执类型与解析
 *
 * 参数契约（spec 2026-10-21 §5.2 / 2026-10-27 §17 扩展）:
 *   choice / locate / write : { mode, province, clue?, skill_key }
 *   shape（形状猜省）      : { mode: 'shape', province, skill_key }
 *   compare（面积/方位）   : { mode: 'compare', compare: area|direction, province, province_b, skill_key }
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
  /** compare 才有：对比的另一省与比较维度（area / direction） */
  province_b?: string
  compare?: string
}

export interface MapQuizArgsView {
  valid: boolean
  mode: string
  province: string
  /** compare 的另一省原始 ref（名称/简称/id） */
  provinceB: string
  /** compare 的比较维度：area / direction */
  compare: string
  clue: string
  skillKey: string
}

function createDefaultArgsView(): MapQuizArgsView {
  const view: MapQuizArgsView = {
    valid: false, mode: 'choice', province: '', provinceB: '', compare: 'area',
    clue: 'name', skillKey: 'general_social'
  }
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
    if (m !== 'choice' && m !== 'locate' && m !== 'write' && m !== 'shape' && m !== 'compare') {
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
    const provinceBRaw: Object | undefined = obj['province_b']
    if (typeof provinceBRaw === 'string' && (provinceBRaw as string).trim() !== '') {
      view.provinceB = (provinceBRaw as string).trim()
    }
    const compareRaw: Object | undefined = obj['compare']
    if (typeof compareRaw === 'string' && (compareRaw as string).trim() === 'direction') {
      view.compare = 'direction'
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
