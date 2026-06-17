/**
 * 日期范围工具 — 每日评估页用
 * 14 天历史滚动范围判断 + YMD 字符串位移
 */

const MS_PER_DAY: number = 24 * 60 * 60 * 1000
const MAX_HISTORY_DAYS: number = 14

/**
 * 把 epoch ms 转为 'YYYY-MM-DD' (本地时区)
 */
export function todayYMD(nowMs: number = Date.now()): string {
  const d: Date = new Date(nowMs)
  const y: number = d.getFullYear()
  const m: string = String(d.getMonth() + 1).padStart(2, '0')
  const day: string = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

/**
 * 把 'YYYY-MM-DD' 解析为本地时区 0 点的 epoch ms
 */
function ymdToMs(ymd: string): number {
  const parts: string[] = ymd.split('-')
  if (parts.length !== 3) {
    return NaN
  }
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])).getTime()
}

/**
 * 距今不超过 14 天的历史范围内。
 * - 14 天前的当天: true
 * - 15 天前: false
 * - 未来: false
 */
export function isWithinHistoryRange(ymd: string, nowMs: number = Date.now()): boolean {
  const targetMs: number = ymdToMs(ymd)
  if (isNaN(targetMs)) {
    return false
  }
  const todayMs: number = ymdToMs(todayYMD(nowMs))
  const diffDays: number = Math.floor((todayMs - targetMs) / MS_PER_DAY)
  return diffDays >= 0 && diffDays <= MAX_HISTORY_DAYS
}

/**
 * 能否再向回切一天（还有更早的历史可看）
 * - 选中"今天" → false（已是最新）
 * - 选中早于今天 → true
 */
export function canGoBack(selectedYMD: string, nowMs: number = Date.now()): boolean {
  const today: string = todayYMD(nowMs)
  return selectedYMD < today
}

/**
 * 能否再向前切一天（还没到今天）
 */
export function canGoForward(selectedYMD: string, nowMs: number = Date.now()): boolean {
  const oneDayLater: string = shiftYMD(selectedYMD, 1)
  const today: string = todayYMD(nowMs)
  return oneDayLater <= today
}

/**
 * YMD 字符串位移 N 天（可为负）
 * - 跨月/跨年正确处理
 * - 输入非法时返回原字符串
 */
export function shiftYMD(ymd: string, days: number): string {
  const ms: number = ymdToMs(ymd)
  if (isNaN(ms)) {
    return ymd
  }
  return todayYMD(ms + days * MS_PER_DAY)
}