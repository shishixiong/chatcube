import { describe, it, expect } from '@ohos/hypium'
import { generateGateQuestion, checkGateAnswer, GateQuestion } from '../../../../main/ets/utils/ParentalGateMath'

/**
 * ParentalGateMath 单元测试
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */
export default function parentalGateMathTest() {
  describe('generateGateQuestion', () => {
    it('answer is always positive and within 4 digits', 0, () => {
      for (let i = 0; i < 300; i++) {
        const q: GateQuestion = generateGateQuestion()
        expect(q.answer > 0).assertTrue()
        expect(q.answer <= 1098).assertTrue()
        expect(q.text.length > 0).assertTrue()
      }
    })

    it('produces varied questions across draws', 0, () => {
      const seen: Set<string> = new Set()
      for (let i = 0; i < 40; i++) {
        seen.add(generateGateQuestion().text)
      }
      expect(seen.size > 5).assertTrue()
    })

    it('subtraction never yields zero or negative answer', 0, () => {
      for (let i = 0; i < 300; i++) {
        const q: GateQuestion = generateGateQuestion()
        if (q.text.includes('−')) {
          expect(q.answer > 0).assertTrue()
        }
      }
    })
  })

  describe('checkGateAnswer', () => {
    const q: GateQuestion = { text: '17 × 6', answer: 102 }

    it('accepts exact correct answer', 0, () => {
      expect(checkGateAnswer(q, '102')).assertTrue()
    })

    it('accepts answer with surrounding whitespace', 0, () => {
      expect(checkGateAnswer(q, ' 102 ')).assertTrue()
    })

    it('rejects wrong answer', 0, () => {
      expect(checkGateAnswer(q, '103')).assertFalse()
    })

    it('rejects empty and whitespace-only input', 0, () => {
      expect(checkGateAnswer(q, '')).assertFalse()
      expect(checkGateAnswer(q, '   ')).assertFalse()
    })

    it('rejects non-digit input', 0, () => {
      expect(checkGateAnswer(q, '10a')).assertFalse()
      expect(checkGateAnswer(q, '-102')).assertFalse()
      expect(checkGateAnswer(q, '1.5')).assertFalse()
    })

    it('rejects overlong input (> 4 digits)', 0, () => {
      expect(checkGateAnswer(q, '00102')).assertFalse()
    })
  })
}
