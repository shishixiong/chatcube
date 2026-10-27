/**
 * ChinaMapMetrics - 中国地图度量纯函数（面积 / 中心点 / 方位）
 *
 * 设计: docs/superpowers/specs/2026-10-21-china-map-teaching-tools-design.md §17
 * 只吃 rawfile 里的省份 path（1000×870.2 的经纬投影网格），不引入任何新数据，
 * 因此 map_quiz 的「面积比较 / 方位比较」两个新题型可以直接复用现成地图数据。
 *
 * 投影保真度实测（2026-10-27，34 省对照官方面积）:
 *  - 投影面积排序在「官方面积比值 ≥ 1.25」的 485 对里与真实大小 **100% 一致**；
 *    只有 河北/吉林(1.007)、河南/江西(1.0006)、江苏/浙江(1.016) 这类近乎同大的
 *    相邻对会翻，所以面积题用 AREA_MIN_RATIO 把近似对挡在门外。
 *  - 单省偏差：大省 ±3% 内（黑龙江 -3%、青海 -2%），小省失真大（上海 +28%、
 *    澳门 +41%、宁夏 -21%），故一律不做「多少平方公里」的绝对值题，只做大小比较。
 *
 * 方位用「最大环的面积重心」而非 bbox 中心：河北这种环抱北京的月牙形，bbox 中心
 * 会跑到北京身上，重心更稳。Y 轴向下（地图坐标系），所以「北」= y 更小。
 */

import { ChinaProvince } from './ChinaMapData'
import { parseProvincePolygons } from './ChinaMapGeometry'
import { MapPoint } from './ChinaMapTransform'

/** 面积比较题的最小面积比：小于它就是「差不多的两个省」，不出题（实测 1.25 处零错误） */
export const AREA_MIN_RATIO: number = 1.25

/**
 * 方位比较题的最小主轴优势比：|dx| ≥ 1.6|dy| 才算「东/西」，反之算「南/北」。
 * 实测 34 省 1122 个有序对里 73% 能给出无争议的四方位，其余（如广东→香港）
 * 中心点几乎重叠或斜 45°，一律不出题。
 */
export const DIRECTION_MIN_DOMINANCE: number = 1.6

export const DIRECTION_NORTH: string = '北'
export const DIRECTION_SOUTH: string = '南'
export const DIRECTION_EAST: string = '东'
export const DIRECTION_WEST: string = '西'

/** 四方位选项（固定顺序，卡片按此渲染按钮） */
export const MAP_DIRECTIONS: string[] = [DIRECTION_EAST, DIRECTION_SOUTH, DIRECTION_WEST, DIRECTION_NORTH]

/** 单个环的有向面积（signed，用于环面积和重心） */
function ringSignedArea(ring: number[][]): number {
  let sum = 0
  for (let i = 0; i < ring.length; i++) {
    const cur = ring[i]
    const next = ring[(i + 1) % ring.length]
    sum += cur[0] * next[1] - next[0] * cur[1]
  }
  return sum / 2
}

/** 环面积（取绝对值，不区分方向） */
function ringArea(ring: number[][]): number {
  return Math.abs(ringSignedArea(ring))
}

/**
 * 省份投影面积（地图单位²）。多环求和（广东群岛、河北的洞），
 * 洞在 evenodd 渲染下不参与填充，但面积题只比大小，量级差远大于洞的误差。
 */
export function provinceArea(province: ChinaProvince): number {
  const rings = parseProvincePolygons(province.path)
  let total = 0
  for (let i = 0; i < rings.length; i++) {
    total += ringArea(rings[i])
  }
  return total
}

/** 省份中心点：面积最大那个环的面积重心（CJK 无重心 → 回落到 bbox 中心） */
export function provinceCenter(province: ChinaProvince): MapPoint {
  const rings = parseProvincePolygons(province.path)
  const fallback: MapPoint = { x: 0, y: 0 }
  if (rings.length === 0) {
    return fallback
  }
  let biggest: number[][] = rings[0]
  let biggestArea = -1
  for (let i = 0; i < rings.length; i++) {
    const area = ringArea(rings[i])
    if (area > biggestArea) {
      biggestArea = area
      biggest = rings[i]
    }
  }
  let cx = 0
  let cy = 0
  let signedTwice = 0
  for (let i = 0; i < biggest.length; i++) {
    const cur = biggest[i]
    const next = biggest[(i + 1) % biggest.length]
    const cross = cur[0] * next[1] - next[0] * cur[1]
    signedTwice += cross
    cx += (cur[0] + next[0]) * cross
    cy += (cur[1] + next[1]) * cross
  }
  if (signedTwice === 0) {
    return fallback
  }
  const point: MapPoint = { x: cx / (3 * signedTwice), y: cy / (3 * signedTwice) }
  return point
}

/**
 * 方位：from 看 to 在哪个方向，返回 北/东/南/西；主轴优势不足或两点重合返回 ''。
 * Y 轴向下：dy > 0 表示 to 在 from 的南边。
 */
export function dominantDirection(from: ChinaProvince, to: ChinaProvince): string {
  const a = provinceCenter(from)
  const b = provinceCenter(to)
  const dx = b.x - a.x
  const dy = b.y - a.y
  const ax = Math.abs(dx)
  const ay = Math.abs(dy)
  if (ax === 0 && ay === 0) {
    return ''
  }
  if (ax >= DIRECTION_MIN_DOMINANCE * ay) {
    return dx > 0 ? DIRECTION_EAST : DIRECTION_WEST
  }
  if (ay >= DIRECTION_MIN_DOMINANCE * ax) {
    return dy > 0 ? DIRECTION_SOUTH : DIRECTION_NORTH
  }
  return ''
}

/** 面积比：大的比小的（恒 ≥ 1；相等返回 1） */
export function areaRatio(a: ChinaProvince, b: ChinaProvince): number {
  const areaA = provinceArea(a)
  const areaB = provinceArea(b)
  if (areaA <= 0 || areaB <= 0) {
    return 1
  }
  return areaA >= areaB ? areaA / areaB : areaB / areaA
}

/** 面积更大的一方；相等时返回 null（调用方应判为不可出题） */
export function largerProvince(a: ChinaProvince, b: ChinaProvince): ChinaProvince | null {
  const areaA = provinceArea(a)
  const areaB = provinceArea(b)
  if (areaA === areaB) {
    return null
  }
  return areaA > areaB ? a : b
}
