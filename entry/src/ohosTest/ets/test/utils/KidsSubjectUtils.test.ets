import { describe, it, expect } from '@ohos/hypium'
import { ChatSession } from '../../../../main/ets/models/ChatModels'
import { StarEventRow } from '../../../../main/ets/models/StarEventModels'
import { getStartOfDayMs } from '../../../../main/ets/utils/DateFormatUtils'
import {
  countTodayBySubject,
  groupSessionsByDay,
  findTodaySession,
  formatDateLabel,
  formatWeekday,
  formatHourMinute,
  buildTodayCategoryRows,
  buildTodayEventRows,
  KidsDayGroup
} from '../../../../main/ets/utils/KidsSubjectUtils'

/**
 * KidsSubjectUtils 纯函数单元测试（儿童主屏 v2, spec 2026-09-15 §6）
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

function makeSession(id: string, assistantId: string, updatedAt: number): ChatSession {
  const session: ChatSession = new ChatSession(id, `会话${id}`, '')
  session.assistantId = assistantId
  session.updatedAt = updatedAt
  return session
}

function makeEvent(activityType: string, stars: number, createdAt: number): StarEventRow {
  const event: StarEventRow = {
    id: createdAt,
    createdAt: createdAt,
    activityType: activityType,
    stars: stars,
    toolCallId: '',
    sessionId: '',
    skillKey: '',
    metadataJson: ''
  }
  return event
}

export default function kidsSubjectUtilsTest() {
  describe('countTodayBySubject', () => {
    it('counts only events whose activityType is in the subject set', 0, () => {
      const now = new Date(2026, 8, 15, 12, 0, 0, 0).getTime()
      const events: StarEventRow[] = [
        makeEvent('math_quiz', 1, now),
        makeEvent('math_quiz', 0, now),
        makeEvent('english_quiz', 1, now),
        makeEvent('chat_correct', 1, now)
      ]
      expect(countTodayBySubject(events, ['math_quiz'])).assertEqual(2)
      expect(countTodayBySubject(events, ['english_quiz', 'picture_vocab', 'listening_quiz'])).assertEqual(1)
    })

    it('chat_correct never counts into any subject', 0, () => {
      const now = new Date(2026, 8, 15, 12, 0, 0, 0).getTime()
      const events: StarEventRow[] = [makeEvent('chat_correct', 1, now)]
      expect(countTodayBySubject(events, ['math_quiz'])).assertEqual(0)
      expect(countTodayBySubject(events, ['number_puzzle', 'maze', 'sudoku', 'matching_pairs', 'categorization']))
        .assertEqual(0)
    })
  })

  describe('groupSessionsByDay', () => {
    it('groups today and yesterday with correct labels, newest day first', 0, () => {
      const now = new Date(2026, 8, 15, 14, 0, 0, 0).getTime()
      const sessions: ChatSession[] = [
        makeSession('a', 'default', new Date(2026, 8, 15, 9, 20, 0, 0).getTime()),
        makeSession('b', 'kids_math', new Date(2026, 8, 14, 18, 0, 0, 0).getTime()),
        makeSession('c', 'default', new Date(2026, 8, 15, 11, 0, 0, 0).getTime())
      ]
      const groups: KidsDayGroup[] = groupSessionsByDay(sessions, now, 7)
      expect(groups.length).assertEqual(2)
      expect(groups[0].label).assertEqual('今天')
      expect(groups[0].sessions.length).assertEqual(2)
      // 组内按 updatedAt 降序（入参已降序，函数保持顺序）
      expect(groups[0].sessions[0].id).assertEqual('c')
      expect(groups[1].label).assertEqual('昨天')
      expect(groups[1].subLabel).assertEqual('9月14日 周一')
    })

    it('cross-day boundary: 23:59 and 00:01 fall into different days', 0, () => {
      const now = new Date(2026, 8, 16, 8, 0, 0, 0).getTime()
      const sessions: ChatSession[] = [
        makeSession('early', 'default', new Date(2026, 8, 16, 0, 1, 0, 0).getTime()),
        makeSession('late', 'default', new Date(2026, 8, 15, 23, 59, 0, 0).getTime())
      ]
      const groups: KidsDayGroup[] = groupSessionsByDay(sessions, now, 7)
      expect(groups.length).assertEqual(2)
      expect(groups[0].label).assertEqual('今天')
      expect(groups[0].sessions[0].id).assertEqual('early')
      expect(groups[1].label).assertEqual('昨天')
      expect(groups[1].sessions[0].id).assertEqual('late')
    })

    it('dayLimit truncates to the most recent N days with records', 0, () => {
      const now = new Date(2026, 8, 15, 12, 0, 0, 0).getTime()
      const sessions: ChatSession[] = [
        makeSession('d0', 'default', new Date(2026, 8, 15, 9, 0, 0, 0).getTime()),
        makeSession('d1', 'default', new Date(2026, 8, 14, 9, 0, 0, 0).getTime()),
        makeSession('d2', 'default', new Date(2026, 8, 13, 9, 0, 0, 0).getTime()),
        makeSession('d3', 'default', new Date(2026, 8, 12, 9, 0, 0, 0).getTime())
      ]
      const groups: KidsDayGroup[] = groupSessionsByDay(sessions, now, 3)
      expect(groups.length).assertEqual(3)
      expect(groups[2].sessions[0].id).assertEqual('d2')
    })

    it('older than yesterday uses plain date label', 0, () => {
      const now = new Date(2026, 8, 15, 12, 0, 0, 0).getTime()
      const sessions: ChatSession[] = [
        makeSession('x', 'default', new Date(2026, 8, 10, 9, 0, 0, 0).getTime())
      ]
      const groups: KidsDayGroup[] = groupSessionsByDay(sessions, now, 7)
      expect(groups[0].label).assertEqual('9月10日')
      expect(groups[0].subLabel).assertEqual('周四')
    })
  })

  describe('findTodaySession', () => {
    it('returns null when no session updated today', 0, () => {
      const startOfDay = getStartOfDayMs(new Date(2026, 8, 15, 12, 0, 0, 0).getTime())
      const sessions: ChatSession[] = [
        makeSession('old', 'default', new Date(2026, 8, 14, 23, 0, 0, 0).getTime())
      ]
      expect(findTodaySession(sessions, startOfDay)).assertNull()
    })

    it('returns the most recently updated session of today', 0, () => {
      const startOfDay = getStartOfDayMs(new Date(2026, 8, 15, 12, 0, 0, 0).getTime())
      const sessions: ChatSession[] = [
        makeSession('morning', 'default', new Date(2026, 8, 15, 8, 0, 0, 0).getTime()),
        makeSession('noon', 'default', new Date(2026, 8, 15, 12, 30, 0, 0).getTime())
      ]
      const found = findTodaySession(sessions, startOfDay)
      expect(found !== null).assertTrue()
      expect(found?.id).assertEqual('noon')
    })
  })

  describe('date formatters', () => {
    it('formatDateLabel renders M月D日', 0, () => {
      expect(formatDateLabel(new Date(2026, 8, 15, 12, 0, 0, 0).getTime())).assertEqual('9月15日')
      expect(formatDateLabel(new Date(2026, 11, 1, 12, 0, 0, 0).getTime())).assertEqual('12月1日')
    })

    it('formatWeekday renders 周X', 0, () => {
      // 2026-09-15 是周二
      expect(formatWeekday(new Date(2026, 8, 15, 12, 0, 0, 0).getTime())).assertEqual('周二')
      // 2026-09-13 是周日
      expect(formatWeekday(new Date(2026, 8, 13, 12, 0, 0, 0).getTime())).assertEqual('周日')
    })

    it('formatHourMinute renders HH:mm with zero padding', 0, () => {
      expect(formatHourMinute(new Date(2026, 8, 15, 9, 5, 0, 0).getTime())).assertEqual('09:05')
      expect(formatHourMinute(new Date(2026, 8, 15, 23, 59, 0, 0).getTime())).assertEqual('23:59')
    })
  })

  describe('buildTodayCategoryRows', () => {
    it('aggregates by subject with count and stars, chat_correct as 聊天问答', 0, () => {
      const now = new Date(2026, 8, 15, 12, 0, 0, 0).getTime()
      const events: StarEventRow[] = [
        makeEvent('math_quiz', 1, now),
        makeEvent('math_quiz', 1, now),
        makeEvent('sudoku', 3, now),
        makeEvent('chat_correct', 1, now)
      ]
      const rows = buildTodayCategoryRows(events)
      expect(rows.length).assertEqual(3)
      expect(rows[0].name).assertEqual('数学题')
      expect(rows[0].detail).assertEqual('答对 2 题')
      expect(rows[0].stars).assertEqual(2)
      expect(rows[1].name).assertEqual('小游戏')
      expect(rows[1].detail).assertEqual('完成 1 局')
      expect(rows[1].stars).assertEqual(3)
      expect(rows[2].name).assertEqual('聊天问答')
      expect(rows[2].stars).assertEqual(1)
    })

    it('subjects without events are omitted', 0, () => {
      const rows = buildTodayCategoryRows([])
      expect(rows.length).assertEqual(0)
    })
  })

  describe('buildTodayEventRows', () => {
    it('renders time + grantedHint description + stars, newest first', 0, () => {
      const morning = new Date(2026, 8, 15, 9, 20, 0, 0).getTime()
      const noon = new Date(2026, 8, 15, 12, 0, 0, 0).getTime()
      const events: StarEventRow[] = [
        makeEvent('math_quiz', 1, morning),
        makeEvent('maze', 0, noon)
      ]
      const rows = buildTodayEventRows(events)
      expect(rows.length).assertEqual(2)
      expect(rows[0].timeLabel).assertEqual('12:00')
      expect(rows[0].stars).assertEqual(0)
      expect(rows[1].timeLabel).assertEqual('09:20')
      expect(rows[1].stars).assertEqual(1)
    })
  })
}
