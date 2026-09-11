import { describe, it, expect } from '@ohos/hypium'
import {
  shouldAutoGreetToday,
  getDayPartGreeting,
  GREETING_SYSTEM_HINT
} from '../../../../main/ets/utils/GreetingUtils'

/**
 * GreetingUtils 单元测试
 *
 * 覆盖 shouldAutoGreetToday 的 5 个短路条件 + 边界场景,
 * 以及 GREETING_SYSTEM_HINT 元指令的基本健全性 (无 emoji / 含招呼意图)。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

export default function greetingUtilsTest() {
  // 基础参数: 全部满足时 shouldAutoGreetToday === true
  const baseArgs = {
    isNewChatTransition: true,
    currentAssistantId: 'default',
    messagesLength: 0,
    inputText: '',
    lastGreetDate: '',
    todayYmd: '2026-06-17'
  }

  describe('shouldAutoGreetToday', () => {
    it('returns true on fresh new-chat with default assistant and empty greet log', 0, () => {
      expect(shouldAutoGreetToday(baseArgs)).assertTrue()
    })

    it('returns false when not a new chat transition (existing session reopened)', 0, () => {
      expect(shouldAutoGreetToday({ ...baseArgs, isNewChatTransition: false })).assertFalse()
    })

    it('returns false when assistant is not default (custom assistant selected)', 0, () => {
      expect(shouldAutoGreetToday({ ...baseArgs, currentAssistantId: 'custom-coach' })).assertFalse()
    })

    it('returns false when messages already exist in session', 0, () => {
      expect(shouldAutoGreetToday({ ...baseArgs, messagesLength: 1 })).assertFalse()
    })

    it('returns false when input has whitespace only (child typed spaces)', 0, () => {
      expect(shouldAutoGreetToday({ ...baseArgs, inputText: '   ' })).assertFalse()
    })

    it('returns false when input has real text (child already typing)', 0, () => {
      expect(shouldAutoGreetToday({ ...baseArgs, inputText: 'hi' })).assertFalse()
    })

    it('returns false when lastGreetDate equals today (per-day guard)', 0, () => {
      expect(shouldAutoGreetToday({ ...baseArgs, lastGreetDate: '2026-06-17' })).assertFalse()
    })

    it('returns true when lastGreetDate is yesterday (next day allowed)', 0, () => {
      expect(shouldAutoGreetToday({ ...baseArgs, lastGreetDate: '2026-06-16' })).assertTrue()
    })

    it('returns true when lastGreetDate is empty (never greeted)', 0, () => {
      expect(shouldAutoGreetToday({ ...baseArgs, lastGreetDate: '' })).assertTrue()
    })

    it('returns false when all conditions fail (compound case)', 0, () => {
      expect(shouldAutoGreetToday({
        isNewChatTransition: false,
        currentAssistantId: 'other',
        messagesLength: 3,
        inputText: 'x',
        lastGreetDate: '2026-06-17',
        todayYmd: '2026-06-17'
      })).assertFalse()
    })
  })

  describe('getDayPartGreeting', () => {
    it('morning returns 早上好', 0, () => {
      expect(getDayPartGreeting(7)).assertEqual('早上好')
    })

    it('noon returns 中午好', 0, () => {
      expect(getDayPartGreeting(12)).assertEqual('中午好')
    })

    it('afternoon returns 下午好', 0, () => {
      expect(getDayPartGreeting(15)).assertEqual('下午好')
    })

    it('evening returns 晚上好', 0, () => {
      expect(getDayPartGreeting(20)).assertEqual('晚上好')
    })

    it('early morning (3) falls back to 早上好', 0, () => {
      expect(getDayPartGreeting(3)).assertEqual('早上好')
    })

    it('boundary hour 11 is 上午 (早上好)', 0, () => {
      expect(getDayPartGreeting(11)).assertEqual('早上好')
    })

    it('boundary hour 18 is 晚上好', 0, () => {
      expect(getDayPartGreeting(18)).assertEqual('晚上好')
    })
  })

  describe('GREETING_SYSTEM_HINT', () => {
    it('is a non-empty string', 0, () => {
      expect(GREETING_SYSTEM_HINT.length > 0).assertTrue()
    })

    it('contains greeting intent keyword 打招呼', 0, () => {
      expect(GREETING_SYSTEM_HINT.includes('打招呼')).assertTrue()
    })

    it('mentions waiting for child reply (避免 AI 主动调工具)', 0, () => {
      expect(GREETING_SYSTEM_HINT.includes('等孩子回复')).assertTrue()
    })

    it('does not contain forbidden user-facing emoji (range U+1F300-U+1FAFF)', 0, () => {
      // 教学 prompt 禁 emoji, 招呼 hint 也不该污染
      expect(/[\u{1F300}-\u{1FAFF}]/u.test(GREETING_SYSTEM_HINT)).assertFalse()
    })
  })
}
