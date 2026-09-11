/**
 * 日期格式化工具函数
 * 提取日期分隔符相关逻辑
 */

/**
 * 格式化日期分隔符显示文本
 * @param timestamp 时间戳
 * @returns 格式化后的日期文本（今天、昨天、具体日期）
 */
export function formatDateDivider(timestamp: number): string {
  const date = new Date(timestamp)
  const now = new Date()
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const yesterday = new Date(today.getTime() - 24 * 60 * 60 * 1000)
  const messageDate = new Date(date.getFullYear(), date.getMonth(), date.getDate())

  if (messageDate.getTime() === today.getTime()) {
    return '今天'
  } else if (messageDate.getTime() === yesterday.getTime()) {
    return '昨天'
  } else if (date.getFullYear() === now.getFullYear()) {
    // 同年，显示月日
    return `${date.getMonth() + 1}月${date.getDate()}日`
  } else {
    // 不同年，显示年月日
    return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`
  }
}

/**
 * 判断是否需要显示日期分隔符
 * @param currentTimestamp 当前消息时间戳
 * @param previousTimestamp 上一条消息时间戳（如果是首条消息则为 null）
 * @returns 是否需要显示日期分隔符
 */
export function shouldShowDateDivider(
  currentTimestamp: number,
  previousTimestamp: number | null
): boolean {
  // 首条消息显示日期
  if (previousTimestamp === null) {
    return true
  }

  // 比较日期（只比较年月日）
  const currentDate = new Date(currentTimestamp)
  const prevDate = new Date(previousTimestamp)

  return currentDate.getFullYear() !== prevDate.getFullYear() ||
         currentDate.getMonth() !== prevDate.getMonth() ||
         currentDate.getDate() !== prevDate.getDate()
}

/**
 * 判断两个时间戳是否在同一天
 * @param timestamp1 时间戳1
 * @param timestamp2 时间戳2
 * @returns 是否在同一天
 */
export function isSameDay(timestamp1: number, timestamp2: number): boolean {
  const date1 = new Date(timestamp1)
  const date2 = new Date(timestamp2)

  return date1.getFullYear() === date2.getFullYear() &&
         date1.getMonth() === date2.getMonth() &&
         date1.getDate() === date2.getDate()
}

/**
 * 取指定年月初的 00:00:00 时间戳 (本地时区)
 * @param year 年份 (e.g., 2026)
 * @param month 月份, 1-12 (13 自动回卷到次年 1 月)
 * @returns 月初时间戳 (ms)
 */
export function getStartOfMonthMs(year: number, month: number): number {
  const d = new Date(year, month - 1, 1, 0, 0, 0, 0)
  return d.getTime()
}

/**
 * 格式化为 YYYY-MM-DD (本地时区)
 * @param timestamp 时间戳 (ms)
 * @returns YYYY-MM-DD 字符串
 */
export function formatYMD(timestamp: number): string {
  const d = new Date(timestamp)
  const y = d.getFullYear()
  const m = (d.getMonth() + 1).toString().padStart(2, '0')
  const day = d.getDate().toString().padStart(2, '0')
  return `${y}-${m}-${day}`
}

/**
 * 取 ISO 8601 周几索引 (周一=0, 周日=6)
 * 与项目内 getTimeInfo 工具对齐,日历列序保持一致
 * @param timestamp 时间戳 (ms)
 * @returns 0-6 之间的整数
 */
export function getIsoWeekday(timestamp: number): number {
  const d = new Date(timestamp)
  const js = d.getDay() // Sun=0, Mon=1, ..., Sat=6
  return js === 0 ? 6 : js - 1
}

/**
 * 周一为第一列的短标签 (与 getIsoWeekday 索引对齐)
 * 索引 0='一', 1='二', ..., 6='日'
 */
export const WEEKDAY_SHORT_LABELS_ZH: string[] = ['一', '二', '三', '四', '五', '六', '日']

/**
 * 取 timestamp 所在自然周（ISO, 周一为一周之始）的本地 00:00:00.000 时间戳
 * 供儿童主屏「本周 +N 星星」徽章查询周一起点
 * @param timestamp 时间戳 (ms)
 * @returns 本周一 0 点时间戳 (ms)
 */
export function getStartOfWeekMs(timestamp: number): number {
  const d = new Date(timestamp)
  d.setHours(0, 0, 0, 0)
  d.setDate(d.getDate() - getIsoWeekday(timestamp))
  return d.getTime()
}
