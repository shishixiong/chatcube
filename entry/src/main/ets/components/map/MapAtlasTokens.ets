// entry/src/main/ets/components/map/MapAtlasTokens.ets
/**
 * MapAtlasTokens - 地图小课堂「纸质地图册」配色令牌
 *
 * 来源：map-card-redesign.html 的 :root 变量（与 KidsBrandTokens 同源暖色）。
 * light 模式逐值复刻设计稿；dark 模式只压暗明度、保留同一色相——
 * 地图是「纸」，深色下也该是暖褐纸而不是纯黑，否则卡片会从聊天流里跳出来。
 */

export interface MapAtlasPalette {
  /** 卡片表面（地图册 / 资料卡） */
  surface: string
  /** 次级表面（缩放簇 / 印章 / 标签底） */
  surfaceAlt: string
  /** 主文字 */
  fg: string
  /** 次级文字 */
  muted: string
  /** 三级文字 */
  subtle: string
  /** 描边 */
  border: string
  /** 主按钮 / 强调橙 */
  accent: string
  /** 强调色上的墨字（深棕） */
  onAccent: string
  /** 强调色墨字（标签文字） */
  accentInk: string
  /** 学科墨色（地理用小星老师暖橙系里偏红的一档） */
  chineseInk: string
  success: string
  /** 地图水域底色 */
  water: string
  /** 纸张网格线（8 位 ARGB，带透明度） */
  grid: string
  /** 未探索陆地 */
  land: string
  /** 已探索陆地 */
  visited: string
  /** 正在认识（选中）陆地 */
  selected: string
  /** 选中省界线 */
  selectedLine: string
  /** 已探索省界线 */
  visitedLine: string
  /** 普通省界线 */
  line: string
  /** 南海诸岛附图陆地 */
  insetFill: string
  /** 附图描边 / 虚线框 */
  insetLine: string
  /** 附图底板（半透明） */
  insetBg: string
  /** 指北针底盘 */
  compassBg: string
  /** 图例底盘（半透明） */
  legendBg: string
  /** 印章底 */
  sealBg: string
  /** 印章描边 */
  sealBorder: string
  /** 老师留言上方的虚线分隔 */
  noteLine: string
  /** 主按钮投影（8 位 ARGB） */
  ctaShadow: string
}

const LIGHT_PALETTE: MapAtlasPalette = {
  surface: '#FFFDF8',
  surfaceAlt: '#F4EDDF',
  fg: '#24211C',
  muted: '#6F6A60',
  subtle: '#746E64',
  border: '#DED8CC',
  accent: '#FF9F43',
  onAccent: '#3A2506',
  accentInk: '#5A2F04',
  chineseInk: '#B53917',
  success: '#22735D',
  water: '#F7F1E4',
  grid: '#126E4A1C',
  land: '#EADCC5',
  visited: '#F8E4CB',
  selected: '#FFCB92',
  selectedLine: '#6E4A1C',
  visitedLine: '#A9855A',
  line: '#947A58',
  insetFill: '#E4D2B8',
  insetLine: '#947A58',
  insetBg: '#B3FFFDF8',
  compassBg: '#A8FFFDF8',
  legendBg: '#DFFFFDF8',
  sealBg: '#F4EDDF',
  sealBorder: '#D8C2A5',
  noteLine: '#E7E0D4',
  ctaShadow: '#42FF9F43'
}

const DARK_PALETTE: MapAtlasPalette = {
  surface: '#2A251F',
  surfaceAlt: '#342D24',
  fg: '#F2ECE1',
  muted: '#BFB5A4',
  subtle: '#A29785',
  border: '#443B2E',
  accent: '#FF9F43',
  onAccent: '#2B1A02',
  accentInk: '#FFC490',
  chineseInk: '#FF9E7C',
  success: '#7AD3B4',
  water: '#221E18',
  grid: '#14C8A063',
  land: '#3B3226',
  visited: '#4A3A24',
  selected: '#7A5324',
  selectedLine: '#F0BE84',
  visitedLine: '#9C8154',
  line: '#7C6647',
  insetFill: '#4A3F2D',
  insetLine: '#8C7654',
  insetBg: '#B32A251F',
  compassBg: '#A82A251F',
  legendBg: '#DF2A251F',
  sealBg: '#342D24',
  sealBorder: '#5C4B33',
  noteLine: '#3D3529',
  ctaShadow: '#4D000000'
}

export function getMapAtlasPalette(isDarkMode: boolean): MapAtlasPalette {
  return isDarkMode ? DARK_PALETTE : LIGHT_PALETTE
}
