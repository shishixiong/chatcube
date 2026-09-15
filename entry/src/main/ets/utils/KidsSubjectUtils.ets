import { ChatSession } from '../models/ChatModels'
import { StarActivityType, StarEventRow, getActivityMeta } from '../models/StarEventModels'
import { formatYMD } from './DateFormatUtils'
import { KIDS_SUBJECTS, KidsSubjectItem } from '../components/kids/KidsSubjectCatalog'
import { KIDS_ACCENT } from '../components/kids/KidsBrandTokens'

/**
 * 儿童主屏 v2 纯函数集（spec 2026-09-15 §6）。
 * ArkUI-free，hypium 可测。utils/ → components/kids/ 的 import 仅为
 * 纯数据目录（KidsSubjectCatalog 无 ArkUI 依赖），不构成 UI 耦合。
 */

/** 学习乐园按天分组的一天（class：供 @Param 默认值） */
export class KidsDayGroup {
  dayKey: string = ''
  /** 今天 / 昨天 / 9月10日 */
  label: string = ''
  /** 今天/昨天 → 「9月15日 周二」；更早 → 「周二」 */
  subLabel: string = ''
  sessions: ChatSession[] = []
}

/** 今日星星明细 sheet 的分类汇总行 */
export interface KidsTodayCategoryRow {
  iconPath: string
  /** 图标块 15% 淡底基色 */
  tint: string
  name: string
  /** 答对 N 题 / 完成 N 局 */
  detail: string
  stars: number
}

/** 今日星星明细 sheet 的单条事件行 */
export interface KidsTodayEventRow {
  timeLabel: string
  description: string
  stars: number
}

const WEEKDAY_NAMES: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']

/** 学科今日计数：events 已由调用方限定为今日 */
export function countTodayBySubject(events: StarEventRow[], activityTypes: string[]): number {
  let count = 0
  for (let i = 0; i < events.length; i++) {
    if (activityTypes.includes(events[i].activityType)) {
      count++
    }
  }
  return count
}

/** hero 一天一会话判定：今日（updatedAt >= startOfDayMs）最近更新的一条 */
export function findTodaySession(sessions: ChatSession[], startOfDayMs: number): ChatSession | null {
  let found: ChatSession | null = null
  for (let i = 0; i < sessions.length; i++) {
    const session: ChatSession = sessions[i]
    if (session.updatedAt >= startOfDayMs) {
      if (found === null || session.updatedAt > found.updatedAt) {
        found = session
      }
    }
  }
  return found
}

/** M月D日 */
export function formatDateLabel(timestamp: number): string {
  const date = new Date(timestamp)
  return `${date.getMonth() + 1}月${date.getDate()}日`
}

/** 周二 */
export function formatWeekday(timestamp: number): string {
  return WEEKDAY_NAMES[new Date(timestamp).getDay()]
}

/** HH:mm（补零） */
export function formatHourMinute(timestamp: number): string {
  const date = new Date(timestamp)
  const hour: string = date.getHours() < 10 ? `0${date.getHours()}` : `${date.getHours()}`
  const minute: string = date.getMinutes() < 10 ? `0${date.getMinutes()}` : `${date.getMinutes()}`
  return `${hour}:${minute}`
}

/**
 * 按本地自然日分组：入参 sessions 已按 updatedAt 降序（调用方保证），
 * 输出天组降序（今天在前）、组内保持降序、最多 dayLimit 个有记录的天。
 */
export function groupSessionsByDay(sessions: ChatSession[], nowMs: number, dayLimit: number): KidsDayGroup[] {
  const groups: KidsDayGroup[] = []
  const groupByDayKey: Map<string, KidsDayGroup> = new Map()
  const todayKey: string = formatYMD(nowMs)
  const yesterdayKey: string = formatYMD(nowMs - 24 * 60 * 60 * 1000)
  for (let i = 0; i < sessions.length; i++) {
    const session: ChatSession = sessions[i]
    const dayKey: string = formatYMD(session.updatedAt)
    let group: KidsDayGroup | undefined = groupByDayKey.get(dayKey)
    if (group === undefined) {
      if (groups.length >= dayLimit) {
        continue
      }
      group = new KidsDayGroup()
      group.dayKey = dayKey
      if (dayKey === todayKey) {
        group.label = '今天'
        group.subLabel = `${formatDateLabel(session.updatedAt)} ${formatWeekday(session.updatedAt)}`
      } else if (dayKey === yesterdayKey) {
        group.label = '昨天'
        group.subLabel = `${formatDateLabel(session.updatedAt)} ${formatWeekday(session.updatedAt)}`
      } else {
        group.label = formatDateLabel(session.updatedAt)
        group.subLabel = formatWeekday(session.updatedAt)
      }
      group.sessions = []
      groups.push(group)
      groupByDayKey.set(dayKey, group)
    }
    group.sessions.push(session)
  }
  return groups
}

/**
 * 今日星星分类汇总：按学科聚合（chat_correct 归「聊天问答」行，小星老师样式）。
 * 输出顺序固定：数学 → 英语 → 语文 → 游戏 → 聊天问答，无事件的类别省略。
 */
export function buildTodayCategoryRows(events: StarEventRow[]): KidsTodayCategoryRow[] {
  const rows: KidsTodayCategoryRow[] = []
  for (let s = 0; s < KIDS_SUBJECTS.length; s++) {
    const subject: KidsSubjectItem = KIDS_SUBJECTS[s]
    let count = 0
    let stars = 0
    for (let i = 0; i < events.length; i++) {
      if (subject.activityTypes.includes(events[i].activityType)) {
        count++
        stars += events[i].stars
      }
    }
    if (count === 0) {
      continue
    }
    const verb: string = subject.id === 'games' ? '完成' : '答对'
    const row: KidsTodayCategoryRow = {
      iconPath: subject.iconPath,
      tint: subject.color,
      name: subject.id === 'games' ? '小游戏' : `${subject.label.slice(1)}题`,
      detail: `${verb} ${count} ${subject.countUnit}`,
      stars: stars
    }
    rows.push(row)
  }
  let chatCount = 0
  let chatStars = 0
  for (let i = 0; i < events.length; i++) {
    if (events[i].activityType === 'chat_correct') {
      chatCount++
      chatStars += events[i].stars
    }
  }
  if (chatCount > 0) {
    const chatRow: KidsTodayCategoryRow = {
      iconPath: 'kids/star.svg',
      tint: KIDS_ACCENT,
      name: '聊天问答',
      detail: `答对 ${chatCount} 题`,
      stars: chatStars
    }
    rows.push(chatRow)
  }
  return rows
}

/** 今日明细行：时间 + 活动描述（getActivityMeta.grantedHint）+ 星星，最新在前 */
export function buildTodayEventRows(events: StarEventRow[]): KidsTodayEventRow[] {
  const sorted: StarEventRow[] = [...events]
  sorted.sort((a: StarEventRow, b: StarEventRow): number => b.createdAt - a.createdAt)
  const rows: KidsTodayEventRow[] = []
  for (let i = 0; i < sorted.length; i++) {
    const row: KidsTodayEventRow = {
      timeLabel: formatHourMinute(sorted[i].createdAt),
      description: getActivityMeta(sorted[i].activityType as StarActivityType).grantedHint,
      stars: sorted[i].stars
    }
    rows.push(row)
  }
  return rows
}
