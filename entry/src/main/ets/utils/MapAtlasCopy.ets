// entry/src/main/ets/utils/MapAtlasCopy.ets
/**
 * 地图小课堂（map_card 讲解型）文案生成
 *
 * 老师留言按省份稳定轮换三套模板——同一个省每次都说同一句（可复习），
 * 不同省轮换着说，避免整节课重复「记住简称 X」。
 * 纯函数放在 utils 层，便于 hypium 单测（组件层无 ArkUI 测试基建）。
 */

import { ChinaProvince } from './ChinaMapData'

const NOTE_VARIANT_COUNT: number = 3

/** 按 id 末位字符稳定散列到 3 套模板之一 */
export function teacherNoteVariant(provinceId: string): number {
  if (provinceId.length === 0) {
    return 0
  }
  return provinceId.charCodeAt(provinceId.length - 1) % NOTE_VARIANT_COUNT
}

/**
 * 「小星老师说」留言：
 * 0 简称记忆 / 1 行政中心记忆 / 2 大区 + 简称组合记忆
 */
export function buildTeacherNote(province: ChinaProvince): string {
  const variant = teacherNoteVariant(province.id)
  if (variant === 1) {
    return `${province.short}的行政中心在${province.capital}，别记混啦。`
  }
  if (variant === 2) {
    return `${province.region}的${province.short}，简称「${province.abbr}」，一起记住它。`
  }
  return `记住简称「${province.abbr}」，下次一眼就能认出来。`
}

/** 页脚进度句：「已认识 3 个地方」 */
export function buildExploreProgressText(count: number): string {
  return `已认识 ${Math.max(0, count)} 个地方`
}
