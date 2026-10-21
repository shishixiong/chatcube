/**
 * MapToolValidation - map_card / map_quiz 参数预校验纯逻辑层（spec 2026-10-21 §6）
 *
 * 在 ToolExecutionService.handleMapCard / handleMapQuiz 进入 pending 态之前调用。
 * 失败时 handler 返回 error ToolResult (should_retry: true)，AI 据此自行修正。
 *
 * 设计参考 utils/HanziCardValidation.ets（预校验 + should_retry 范式）。
 *
 * 校验规则（对照 config/BuiltinTools.ets 的 map_card / map_quiz schema）：
 *  - 两工具: skill_key 必须恰为 general_social
 *  - map_card: focus_province 可选；存在时必须命中省份表（short/name/id 三口径）
 *  - map_quiz: mode 枚举 choice/locate/write；province 必填且命中省份表；
 *    clue 仅 locate 可传且枚举 name/capital；
 *    locate + clue:capital 且省的 capital === short（北京/天津/上海/重庆/香港/澳门
 *    这类自答省）→ 硬拒，提示改用 clue:name（原型 capitalQuestion 守卫移植）
 *
 * provinces 由调用方传入（ChinaMapData.getCachedChinaMapData()），null = 数据未就绪。
 */

import { ChinaProvince, findProvinceByRef } from './ChinaMapData'

export interface MapToolValidationResult {
  ok: boolean
  error: string
}

const QUIZ_MODES: string[] = ['choice', 'locate', 'write']
const CLUES: string[] = ['name', 'capital']

function fail(msg: string): MapToolValidationResult {
  const r: MapToolValidationResult = { ok: false, error: msg }
  return r
}

function pass(): MapToolValidationResult {
  const r: MapToolValidationResult = { ok: true, error: '' }
  return r
}

function checkSkillKey(parsed: Record<string, Object>, toolName: string): MapToolValidationResult | null {
  const skillKey = ((parsed['skill_key'] as string) ?? '').trim()
  if (skillKey !== 'general_social') {
    return fail(`${toolName} 的 skill_key 必须固定传 general_social（地理常识），收到「${skillKey}」`)
  }
  return null
}

export function validateMapCardArgs(args: string, provinces: ChinaProvince[] | null): MapToolValidationResult {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('map_card 参数不是合法 JSON, 请检查后重新开课')
  }
  if (provinces === null || provinces.length === 0) {
    return fail('map_card 地图数据未就绪, 请稍后重试')
  }

  const skillResult = checkSkillKey(parsed, 'map_card')
  if (skillResult !== null) {
    return skillResult
  }

  const focusRaw = parsed['focus_province']
  if (focusRaw !== undefined && focusRaw !== null) {
    if (typeof focusRaw !== 'string') {
      return fail('map_card 的 focus_province 必须是字符串（省份常用名, 如「山西」）')
    }
    const focus = (focusRaw as string).trim()
    if (focus !== '' && findProvinceByRef(provinces, focus) === null) {
      return fail(`map_card 的 focus_province「${focus}」不是有效省份名, 请从以下列表选择: 北京 天津 河北 山西 内蒙古 辽宁 吉林 黑龙江 上海 江苏 浙江 安徽 福建 江西 山东 河南 湖北 湖南 广东 广西 海南 重庆 四川 贵州 云南 西藏 陕西 甘肃 青海 宁夏 新疆 台湾 香港 澳门`)
    }
  }
  return pass()
}

export function validateMapQuizArgs(args: string, provinces: ChinaProvince[] | null): MapToolValidationResult {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('map_quiz 参数不是合法 JSON, 请检查后重新出题')
  }
  if (provinces === null || provinces.length === 0) {
    return fail('map_quiz 地图数据未就绪, 请稍后重试')
  }

  const skillResult = checkSkillKey(parsed, 'map_quiz')
  if (skillResult !== null) {
    return skillResult
  }

  const mode = ((parsed['mode'] as string) ?? '').trim()
  if (QUIZ_MODES.indexOf(mode) < 0) {
    return fail(`map_quiz 的 mode「${mode}」不在枚举内, 只能是: choice / locate / write`)
  }

  const provinceRef = ((parsed['province'] as string) ?? '').trim()
  if (provinceRef === '') {
    return fail('map_quiz 缺少 province (目标省份常用名)')
  }
  const province = findProvinceByRef(provinces, provinceRef)
  if (province === null) {
    return fail(`map_quiz 的 province「${provinceRef}」不是有效省份名, 请从以下列表选择: 北京 天津 河北 山西 内蒙古 辽宁 吉林 黑龙江 上海 江苏 浙江 安徽 福建 江西 山东 河南 湖北 湖南 广东 广西 海南 重庆 四川 贵州 云南 西藏 陕西 甘肃 青海 宁夏 新疆 台湾 香港 澳门`)
  }

  const clueRaw = parsed['clue']
  if (clueRaw !== undefined && clueRaw !== null) {
    if (typeof clueRaw !== 'string') {
      return fail('map_quiz 的 clue 必须是字符串: name 或 capital')
    }
    if (mode !== 'locate') {
      return fail(`map_quiz 的 clue 仅 locate 模式可用, mode=${mode} 时请不要传 clue`)
    }
    const clue = (clueRaw as string).trim()
    if (CLUES.indexOf(clue) < 0) {
      return fail(`map_quiz 的 clue「${clue}」不在枚举内, 只能是: name / capital`)
    }
    if (clue === 'capital' && province.capital === province.short) {
      return fail(`map_quiz 的 province「${province.short}」行政中心与省名相同, 用 clue:capital 出题等于把答案告诉孩子, 请改用 clue:「name」或换一个省`)
    }
  }
  return pass()
}
