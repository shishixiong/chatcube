/**
 * 通用时间格式化工具
 *
 * 纯函数, 跨页面复用。
 *
 * 用法:
 *   import { formatRelativeTime } from '../utils/TimeFormatUtils'
 *   Text(`生成于 ${formatRelativeTime(planRow.completedAt)}`)
 */

const MAX_RELATIVE_MS: number = 60 * 1000
const MAX_HOUR_MS: number = 60 * MAX_RELATIVE_MS
const MAX_DAY_MS: number = 24 * MAX_HOUR_MS

/**
 * 把时间戳格式化为相对时间字符串。
 * < 1 分钟 → "刚刚"
 * < 1 小时 → "X 分钟前"
 * < 1 天   → "X 小时前"
 * ≥ 1 天   → "X 天前"
 */
export function formatRelativeTime(ts: number): string {
  if (ts <= 0) {
    return ''
  }
  const delta = Date.now() - ts
  if (delta < 0) {
    // 未来时间（时钟漂移）兜底
    return '刚刚'
  }
  if (delta < MAX_RELATIVE_MS) {
    return '刚刚'
  }
  if (delta < MAX_HOUR_MS) {
    const minutes = Math.floor(delta / MAX_RELATIVE_MS)
    return `${minutes} 分钟前`
  }
  if (delta < MAX_DAY_MS) {
    const hours = Math.floor(delta / MAX_HOUR_MS)
    return `${hours} 小时前`
  }
  const days = Math.floor(delta / MAX_DAY_MS)
  return `${days} 天前`
}
