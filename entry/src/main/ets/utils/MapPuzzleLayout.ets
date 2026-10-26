// entry/src/main/ets/utils/MapPuzzleLayout.ets
/**
 * 中国地图拼图的布局与落点判定（spec 2026-10-26 §5.4）
 *
 * 三件事，全纯函数（hypium 可测、无 ArkUI 依赖）：
 *  1. 本局省份的并集 bbox → 棋盘自动聚焦到这片区域（东北 3 省不该只有全国图 1/8 大）；
 *  2. 托盘里每块碎片的 x/y（按行 wrap，不做横向滚动）；
 *  3. 落点判定：只看「这块碎片自己的省份」，命中省域算对，离省界一个指头宽也算对，
 *     落在别省算错、落在空白算错——绝不会因为「离某个省最近」就判对（会把山西丢到河北也判对）。
 */

import { ChinaProvince } from './ChinaMapData'
import { MapBBox, pointInProvince, provinceBBox, provinceEdgeDistance } from './ChinaMapGeometry'
import { createFitTransform, MapTransform, screenLengthToMap, screenToMap } from './ChinaMapTransform'

/** 棋盘四周留白（vp） */
export const PUZZLE_FIT_PADDING: number = 26
/** 落点容差：碎片中心离省界一个指头宽（14vp ≈ 2.2mm）仍算对 */
export const PUZZLE_DROP_TOLERANCE_VP: number = 14

export interface PuzzleSlot {
  x: number
  y: number
}

export interface PuzzleDropResult {
  correct: boolean
  /** 'hit' 落在省内 / 'tolerance' 空白处离省界一个指头宽 / 'occupied' 明确落在别省 / 'miss' 其它 */
  reason: string
}

/** 一组省份的并集包围盒；空数组返回全零 */
export function unionBBox(provinces: ChinaProvince[]): MapBBox {
  let minX = Infinity
  let minY = Infinity
  let maxX = -Infinity
  let maxY = -Infinity
  for (const p of provinces) {
    const b = provinceBBox(p.path)
    if (b.minX < minX) {
      minX = b.minX
    }
    if (b.minY < minY) {
      minY = b.minY
    }
    if (b.maxX > maxX) {
      maxX = b.maxX
    }
    if (b.maxY > maxY) {
      maxY = b.maxY
    }
  }
  if (provinces.length === 0 || minX === Infinity) {
    const zero: MapBBox = { minX: 0, minY: 0, maxX: 0, maxY: 0 }
    return zero
  }
  const out: MapBBox = { minX: minX, minY: minY, maxX: maxX, maxY: maxY }
  return out
}

/** 棋盘变换：本局省份并集等比填满棋盘 */
export function computePuzzleTransform(provinces: ChinaProvince[], boardW: number,
  boardH: number): MapTransform {
  return createFitTransform(unionBBox(provinces), boardW, boardH, PUZZLE_FIT_PADDING)
}

/** 托盘槽位：每行 perRow 个，行内横排，超出换行 */
export function layoutTray(count: number, perRow: number, slot: number, gap: number,
  padX: number, padY: number): PuzzleSlot[] {
  const out: PuzzleSlot[] = []
  const cols = perRow > 0 ? perRow : 1
  for (let i = 0; i < count; i++) {
    const row = Math.floor(i / cols)
    const col = i % cols
    const s: PuzzleSlot = {
      x: padX + col * (slot + gap),
      y: padY + row * (slot + gap)
    }
    out.push(s)
  }
  return out
}

/** 托盘行数（供卡片算托盘高度） */
export function trayRows(count: number, perRow: number): number {
  const cols = perRow > 0 ? perRow : 1
  return Math.max(1, Math.ceil(count / cols))
}

/**
 * 落点判定（只判这一块自己的省份）。
 * 先用省域命中，再放宽到「离省界 ≤ 14vp」；两条都不中 → 错。
 */
export function resolveDrop(province: ChinaProvince, siblings: ChinaProvince[],
  t: MapTransform, dropX: number, dropY: number): PuzzleDropResult {
  const m = screenToMap(t, dropX, dropY)
  if (pointInProvince(province.path, m.x, m.y)) {
    const hit: PuzzleDropResult = { correct: true, reason: 'hit' }
    return hit
  }
  // 明确落在同局别的省份里 = 错：容差只服务于「指头粗」和「小省/海岸线」，
  // 不能拿来把「丢在邻省身上」判对（0.58 缩放下京津只隔 8vp，容差环会整个盖住对方）。
  if (isInsideSibling(siblings, province.id, m.x, m.y)) {
    const occupied: PuzzleDropResult = { correct: false, reason: 'occupied' }
    return occupied
  }
  const tolerance = screenLengthToMap(t, PUZZLE_DROP_TOLERANCE_VP)
  if (provinceEdgeDistance(province.path, m.x, m.y) <= tolerance) {
    const near: PuzzleDropResult = { correct: true, reason: 'tolerance' }
    return near
  }
  const miss: PuzzleDropResult = { correct: false, reason: 'miss' }
  return miss
}

/** 落点是否明确落在同局另一块省份里（不含自己） */
function isInsideSibling(siblings: ChinaProvince[], selfId: string,
  x: number, y: number): boolean {
  for (let i = 0; i < siblings.length; i++) {
    const s = siblings[i]
    if (s.id === selfId) {
      continue
    }
    if (pointInProvince(s.path, x, y)) {
      return true
    }
  }
  return false
}
