import common from '@ohos.app.ability.common'
import util from '@ohos.util'

/**
 * 中国地图数据加载与查询（rawfile/map/china_provinces.json）
 *
 * 数据源：docs/map-learning/assets_china-provinces.js 的 window.CHINA_MAP（2026-10-21 转换落盘）。
 * 34 个省级行政区，path 全部为 M/L/Z 纯多边形、Y-down、1000×870 坐标系。
 * context 必须由调用方组件传入（util 层拿不到 getContext()，先例 RawfileImageSaveUtil）。
 */

export interface ChinaProvince {
  id: string
  name: string
  short: string
  abbr: string
  capital: string
  region: string
  path: string
}

export interface ChinaMapInset {
  path: string
  width: number
  height: number
}

export interface ChinaMapData {
  viewBox: string
  width: number
  height: number
  provinces: ChinaProvince[]
  inset: ChinaMapInset
}

const RAWFILE_PATH = 'map/china_provinces.json'

let cached: ChinaMapData | null = null

export async function loadChinaMapData(context: common.UIAbilityContext): Promise<ChinaMapData | null> {
  if (cached !== null) {
    return cached
  }
  try {
    const bytes = context.resourceManager.getRawFileContentSync(RAWFILE_PATH)
    const json = new util.TextDecoder('utf-8').decodeToString(bytes)
    const parsed = JSON.parse(json) as ChinaMapData
    if (!parsed || !Array.isArray(parsed.provinces) || parsed.provinces.length === 0) {
      return null
    }
    cached = parsed
    return cached
  } catch (error) {
    console.error('ChinaMapData', `Failed to load china map data: ${JSON.stringify(error)}`)
    return null
  }
}

export function getCachedChinaMapData(): ChinaMapData | null {
  return cached
}

/**
 * 按常用名（short）/ 全名（name）/ 行政区划 id 依次匹配。
 * 大小写敏感，前后空白 trim。未命中返回 null。
 */
export function findProvinceByRef(provinces: ChinaProvince[], ref: string): ChinaProvince | null {
  const needle = ref.trim()
  if (needle.length === 0) {
    return null
  }
  for (const p of provinces) {
    if (p.short === needle || p.name === needle || p.id === needle) {
      return p
    }
  }
  return null
}
