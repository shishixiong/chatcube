// entry/src/main/ets/utils/MapPuzzleValidation.ets
/**
 * map_puzzle 参数预校验（spec 2026-10-26 §7）
 *
 * 与 MapToolValidation 同一范式：在 ToolExecutionService.handleMapPuzzle 进入 pending 之前调用，
 * 失败时 handler 返回 error ToolResult（should_retry: true），AI 据此自行改参数重发。
 *
 * 两套入口：
 *  - validateMapPuzzleArgs：AI 侧硬校验（含文案），只有 handler 用；
 *  - parseMapPuzzleArgs + resolvePuzzleProvinces：卡片侧宽松解析（历史恢复时参数可能不全，
 *    不许抛异常，坏参数走 invalid 兜底卡）。
 */

import { ChinaProvince, findProvinceByRef } from './ChinaMapData'
import { MapToolValidationResult } from './MapToolValidation'

/** 七大区（与 china_provinces.json 的 region 字段逐字一致） */
export const PUZZLE_REGIONS: string[] = ['华北', '东北', '华东', '华中', '华南', '西南', '西北']
export const PUZZLE_MIN_PIECES: number = 2
export const PUZZLE_MAX_PIECES: number = 8

export interface MapPuzzleArgsView {
  valid: boolean
  mode: string
  region: string
  provinceRefs: string[]
  skillKey: string
}

function createDefaultArgsView(): MapPuzzleArgsView {
  const view: MapPuzzleArgsView = {
    valid: false, mode: 'district', region: '', provinceRefs: [], skillKey: 'general_social'
  }
  return view
}

function fail(msg: string): MapToolValidationResult {
  const r: MapToolValidationResult = { ok: false, error: msg }
  return r
}

function pass(): MapToolValidationResult {
  const r: MapToolValidationResult = { ok: true, error: '' }
  return r
}

/** 卡片侧宽松解析：坏 JSON / 缺字段都不抛，valid=false 交给兜底卡 */
export function parseMapPuzzleArgs(raw: string): MapPuzzleArgsView {
  const view = createDefaultArgsView()
  try {
    const obj = JSON.parse(raw) as Record<string, Object>
    const mode = obj['mode']
    if (typeof mode === 'string') {
      const m = (mode as string).trim()
      if (m === 'district' || m === 'custom') {
        view.mode = m
      }
    }
    const region = obj['region']
    if (typeof region === 'string') {
      view.region = (region as string).trim()
    }
    const list = obj['provinces']
    if (Array.isArray(list)) {
      const refs: string[] = []
      const rawList = list as Object[]
      for (const item of rawList) {
        if (typeof item === 'string') {
          const s = (item as string).trim()
          if (s.length > 0) {
            refs.push(s)
          }
        }
      }
      view.provinceRefs = refs
    }
    const skill = obj['skill_key']
    if (typeof skill === 'string' && (skill as string).trim() !== '') {
      view.skillKey = (skill as string).trim()
    }
    if (view.mode === 'district') {
      view.valid = PUZZLE_REGIONS.indexOf(view.region) >= 0
    } else {
      view.valid = view.provinceRefs.length >= PUZZLE_MIN_PIECES
    }
  } catch (_e) {
    return createDefaultArgsView()
  }
  return view
}

/** 某大区的全部省份（保持数据顺序：由北向南） */
export function provincesInRegion(provinces: ChinaProvince[], region: string): ChinaProvince[] {
  const out: ChinaProvince[] = []
  for (const p of provinces) {
    if (p.region === region) {
      out.push(p)
    }
  }
  return out
}

/**
 * 解析出本局要拼的省份（去重、保序）。
 * 卡片与 handler 共用：handler 校验通过后再用它落 inc 目标集合。
 */
export function resolvePuzzleProvinces(provinces: ChinaProvince[],
  view: MapPuzzleArgsView): ChinaProvince[] {
  if (view.mode === 'district') {
    return provincesInRegion(provinces, view.region)
  }
  const out: ChinaProvince[] = []
  const seen: string[] = []
  for (const ref of view.provinceRefs) {
    const hit = findProvinceByRef(provinces, ref)
    if (hit !== null && seen.indexOf(hit.id) < 0) {
      seen.push(hit.id)
      out.push(hit)
    }
  }
  return out
}

/** AI 侧硬校验（文案直接回给模型，要求可执行） */
export function validateMapPuzzleArgs(args: string,
  provinces: ChinaProvince[] | null): MapToolValidationResult {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(args) as Record<string, Object>
  } catch (_e) {
    return fail('map_puzzle 参数不是合法 JSON, 请检查后重新开局')
  }
  if (provinces === null || provinces.length === 0) {
    return fail('map_puzzle 地图数据未就绪, 请稍后重试')
  }

  const skillKey = ((parsed['skill_key'] as string) ?? '').trim()
  if (skillKey !== 'general_social') {
    return fail(`map_puzzle 的 skill_key 必须固定传 general_social（地理常识），收到「${skillKey}」`)
  }

  const mode = ((parsed['mode'] as string) ?? '').trim()
  if (mode !== 'district' && mode !== 'custom') {
    return fail(`map_puzzle 的 mode 只能是 district（按大区）或 custom（指定省份），收到「${mode}」`)
  }

  if (mode === 'district') {
    const region = ((parsed['region'] as string) ?? '').trim()
    if (PUZZLE_REGIONS.indexOf(region) < 0) {
      return fail('map_puzzle 的 region 必须是 华北/东北/华东/华中/华南/西南/西北 之一')
    }
    const members = provincesInRegion(provinces, region)
    if (members.length < 3) {
      return fail(`「${region}」的省份只有 ${members.length} 个，拼不起来，请改用 custom 指定省份`)
    }
    const ok = pass()
    return ok
  }

  const listObj = parsed['provinces']
  if (!Array.isArray(listObj)) {
    return fail('map_puzzle 的 mode=custom 时必须传 provinces 数组（2-8 个省名）')
  }
  const refs: string[] = []
  const rawList = listObj as Object[]
  for (const item of rawList) {
    if (typeof item === 'string') {
      const s = (item as string).trim()
      if (s.length > 0) {
        refs.push(s)
      }
    }
  }
  if (refs.length < PUZZLE_MIN_PIECES || refs.length > PUZZLE_MAX_PIECES) {
    return fail(`map_puzzle 的 provinces 需要 ${PUZZLE_MIN_PIECES}-${PUZZLE_MAX_PIECES} 个省名，收到 ${refs.length} 个`)
  }
  const seen: string[] = []
  for (const ref of refs) {
    const hit = findProvinceByRef(provinces, ref)
    if (hit === null) {
      return fail(`「${ref}」不是有效的省份名（只能用 34 个省级行政区，见工具描述里的列表）`)
    }
    if (seen.indexOf(hit.id) >= 0) {
      return fail(`map_puzzle 的 provinces 里「${ref}」重复了，去重后不足 ${PUZZLE_MIN_PIECES} 个省`)
    }
    seen.push(hit.id)
  }
  const ok = pass()
  return ok
}
