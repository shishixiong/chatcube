// entry/src/main/ets/utils/ChinaMapTransform.ets
/**
 * 地图视口变换（中国地图拼图, spec 2026-10-26 §5.2）
 *
 * 把「地图坐标系里的某个矩形区域」（通常是一局拼图省份的并集 bbox）等比放进
 * 一个屏幕视口，居中并留 padding。等比 = 不变形（省份形状是教学信息，不能拉伸）。
 *
 * 与 ChinaMapStage 内部自带的 zoom/pan 变换互不相干：舞台那份还要处理手势与缩放，
 * 拼图只需要「一次算好、落点反算」，所以单独抽一个小而纯的模块，代价是两处各有一份
 * 拟合公式（v2 做世界地图泛化时再合并）。
 */

import { MapBBox } from './ChinaMapGeometry'

export interface MapPoint {
  x: number
  y: number
}

export interface MapTransform {
  scale: number
  offsetX: number
  offsetY: number
}

/**
 * 让 bbox 区域等比填满视口（四周留 padding），整体居中。
 * 退化输入（bbox 宽或高为 0）回 identity，避免除零产生 NaN 污染整局。
 */
export function createFitTransform(bbox: MapBBox, viewW: number, viewH: number,
  padding: number): MapTransform {
  const contentW = bbox.maxX - bbox.minX
  const contentH = bbox.maxY - bbox.minY
  if (contentW <= 0 || contentH <= 0 || viewW <= 0 || viewH <= 0) {
    const identity: MapTransform = { scale: 1, offsetX: 0, offsetY: 0 }
    return identity
  }
  const availW = Math.max(1, viewW - padding * 2)
  const availH = Math.max(1, viewH - padding * 2)
  const scale = Math.min(availW / contentW, availH / contentH)
  const offsetX = (viewW - contentW * scale) / 2 - bbox.minX * scale
  const offsetY = (viewH - contentH * scale) / 2 - bbox.minY * scale
  const t: MapTransform = { scale: scale, offsetX: offsetX, offsetY: offsetY }
  return t
}

/** 地图坐标 → 视口坐标 */
export function mapToScreen(t: MapTransform, x: number, y: number): MapPoint {
  const p: MapPoint = { x: x * t.scale + t.offsetX, y: y * t.scale + t.offsetY }
  return p
}

/** 视口坐标 → 地图坐标（落点判定用） */
export function screenToMap(t: MapTransform, x: number, y: number): MapPoint {
  const s = t.scale > 0 ? t.scale : 1
  const p: MapPoint = { x: (x - t.offsetX) / s, y: (y - t.offsetY) / s }
  return p
}

/** 视口上的 N vp 对应多少地图单位（容差换算） */
export function screenLengthToMap(t: MapTransform, vp: number): number {
  const s = t.scale > 0 ? t.scale : 1
  return vp / s
}
