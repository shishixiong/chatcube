// entry/src/main/ets/utils/ShanghaiMapData.ets
/**
 * 上海区级地图数据加载与查询（rawfile/map/shanghai_districts.json）
 *
 * 数据由设计工程的 scripts/build-shanghai-districts.py 从 DataV「310000_full.json」生成：
 * 16 个区的真实边界，M/L/Z 纯多边形、Y-down、1000×1007.4 坐标系，
 * 与 china_provinces.json 完全同构——所以几何函数（parseProvincePolygons /
 * pointInProvince / provinceBBox）直接复用，不再造第二条几何管线。
 *
 * center 取 GeoJSON 的 centroid（面积质心），全部 16 个都验证过落回本区，
 * 用作区名标签的锚点；标签画在质心上，比「bbox 中点」更不容易压到邻区。
 *
 * places 是区内小地名（外滩、陆家嘴、佘山……）：经纬度放在 assets/shanghai-places.json，
 * 由设计工程的 scripts/build-place-layer.py 投影成地图坐标、逐点校验落在本区后写进来。
 * 一个区 3–7 个（全市 78 个），tier 决定放大到几倍才出现（1 始终显示 / 2 ≥1.7× / 3 ≥2.6×），
 * 这样「先认识区、再认识区里有什么」是两级，而不是一次把一张地名大全糊上去。
 *
 * context 必须由调用方组件传入（util 层拿不到 getContext()，先例 ChinaMapData）。
 */

import common from '@ohos.app.ability.common'
import util from '@ohos.util'
import { MapBBox } from './ChinaMapGeometry'

/** 区内小地名：tier 1 始终显示，2 / 3 分别要到 1.7× / 2.6× 才出现 */
export interface ShanghaiPlace {
  name: string
  /** 地图坐标（与 district.path 同一坐标系） */
  x: number
  y: number
  tier: number
}

export interface ShanghaiDistrict {
  id: string
  /** 全名，如「黄浦区」「浦东新区」 */
  name: string
  /** 简称（去掉「区」/「新区」），印章与地图标签用它 */
  short: string
  /** 面积质心 [x, y]（地图坐标） */
  center: number[]
  path: string
  /** 区内小地名，坐标为地图坐标；旧数据没有该字段时按空数组处理 */
  places: ShanghaiPlace[]
}

export interface ShanghaiMapData {
  code: string
  name: string
  viewBox: string
  width: number
  height: number
  minLng: number
  maxLng: number
  minLat: number
  maxLat: number
  districts: ShanghaiDistrict[]
}

/** 上海市省级行政区划码：全国图里「点它就下钻」的那一个 */
export const SHANGHAI_PROVINCE_ID: string = '310000'

const RAWFILE_PATH = 'map/shanghai_districts.json'

let cached: ShanghaiMapData | null = null

/**
 * 小地名分级出现的放大倍率：tier 1 默认就显示，2 到 1.7×，3 到 2.6×。
 * 不用 Record<number, number>：ArkTS 对数字键的映射类型支持不完整，写成纯函数最稳。
 */
export function placeTierZoom(tier: number): number {
  if (tier === 1) {
    return 1
  }
  if (tier === 3) {
    return 2.6
  }
  return 1.7
}

export async function loadShanghaiMapData(context: common.UIAbilityContext): Promise<ShanghaiMapData | null> {
  const hit = getCachedShanghaiMapData()
  if (hit !== null) {
    return hit
  }
  try {
    const bytes = context.resourceManager.getRawFileContentSync(RAWFILE_PATH)
    const json = new util.TextDecoder('utf-8').decodeToString(bytes)
    const parsed = JSON.parse(json) as ShanghaiMapData
    if (!parsed || !Array.isArray(parsed.districts) || parsed.districts.length === 0) {
      return null
    }
    cached = parsed
    return cached
  } catch (error) {
    console.error('ShanghaiMapData', `Failed to load shanghai map data: ${JSON.stringify(error)}`)
    return null
  }
}

export function getCachedShanghaiMapData(): ShanghaiMapData | null {
  return cached
}

/** 按 id / 全名 / 简称匹配；未命中返回 null（trim 后再比较） */
export function findDistrictByRef(districts: ShanghaiDistrict[], ref: string): ShanghaiDistrict | null {
  const needle = ref.trim()
  if (needle.length === 0) {
    return null
  }
  for (const d of districts) {
    if (d.id === needle || d.name === needle || d.short === needle) {
      return d
    }
  }
  return null
}

/** 区在官方排序里的序号（1 起），「上海的第 N 个区」用它；未命中返回 0 */
export function districtOrder(districts: ShanghaiDistrict[], districtId: string): number {
  for (let i = 0; i < districts.length; i++) {
    if (districts[i].id === districtId) {
      return i + 1
    }
  }
  return 0
}

/**
 * 当前倍率下这个区该显示哪些小地名。
 * 与设计稿 design/chunks/30-maps.js 的 visiblePlaces 同一判定，两边结论必须一致。
 */
export function visiblePlaces(district: ShanghaiDistrict | null, zoom: number): ShanghaiPlace[] {
  const out: ShanghaiPlace[] = []
  if (district === null || !Array.isArray(district.places)) {
    return out
  }
  for (const p of district.places) {
    if (placeTierZoom(p.tier) <= zoom + 0.000001) {
      out.push(p)
    }
  }
  return out
}

/**
 * 标签锚点：优先用数据里的面积质心；center 缺失或不是两个有限数时退回 bbox 中点。
 * 质心已由数据生成阶段验证落在本区内（设计工程的 build-shanghai-districts.py），
 * 这里不再重复做点包含判断，标签渲染每帧都要用它。
 */
export function districtLabelAnchor(district: ShanghaiDistrict, bbox: MapBBox): number[] {
  const c = district.center
  if (Array.isArray(c) && c.length === 2 && isFinite(c[0]) && isFinite(c[1])) {
    return c
  }
  const out: number[] = [(bbox.minX + bbox.maxX) / 2, (bbox.minY + bbox.maxY) / 2]
  return out
}
