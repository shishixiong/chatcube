import { describe, it, expect } from '@ohos/hypium'
import { validateListeningQuizArgs } from '../../../../main/ets/utils/ListeningQuizValidation'

/**
 * ListeningQuizValidation 单元测试
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

function buildArgs(overrides: Record<string, Object>): string {
  return JSON.stringify(overrides)
}

export default function listeningQuizValidationTest() {
  describe('validateListeningQuizArgs - 合法路径', () => {
    it('齐全字段, 合法', 0, () => {
      const r = validateListeningQuizArgs(buildArgs({
        word: 'cat', question: '听一听，是哪个单词？',
        correct_answer: 'cat', options: ['cat', 'car', 'cap', 'can'],
        difficulty: 1, skill_key: 'english_vocab'
      }))
      expect(r.ok).assertTrue()
    })

    it('含可选 sound_text, 合法', 0, () => {
      const r = validateListeningQuizArgs(buildArgs({
        word: 'b', question: '哪个字母的音？', sound_text: 'buh',
        correct_answer: 'b', options: ['b', 'd', 'p', 'e'],
        difficulty: 1, skill_key: 'english_phonics'
      }))
      expect(r.ok).assertTrue()
    })
  })

  describe('validateListeningQuizArgs - 失败路径', () => {
    it('word 为空, 拒绝 (TTS 无从朗读)', 0, () => {
      const r = validateListeningQuizArgs(buildArgs({
        word: '', question: 'q', correct_answer: 'cat',
        options: ['cat', 'car', 'cap', 'can']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('word')).assertTrue()
    })

    it('question 为空, 拒绝', 0, () => {
      const r = validateListeningQuizArgs(buildArgs({
        word: 'cat', question: '', correct_answer: 'cat',
        options: ['cat', 'car', 'cap', 'can']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('question')).assertTrue()
    })

    it('只有 3 个选项, 拒绝', 0, () => {
      const r = validateListeningQuizArgs(buildArgs({
        word: 'cat', question: 'q', correct_answer: 'cat',
        options: ['cat', 'car', 'cap']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('4')).assertTrue()
    })

    it('5 个选项, 拒绝', 0, () => {
      const r = validateListeningQuizArgs(buildArgs({
        word: 'cat', question: 'q', correct_answer: 'cat',
        options: ['cat', 'car', 'cap', 'can', 'cow']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('4')).assertTrue()
    })

    it('正确答案不在选项里, 拒绝', 0, () => {
      const r = validateListeningQuizArgs(buildArgs({
        word: 'dog', question: 'q', correct_answer: 'dog',
        options: ['cat', 'car', 'cap', 'can']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('不在选项里')).assertTrue()
    })

    it('correct_answer 为空, 拒绝', 0, () => {
      const r = validateListeningQuizArgs(buildArgs({
        word: 'cat', question: 'q', correct_answer: '',
        options: ['cat', 'car', 'cap', 'can']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('correct_answer')).assertTrue()
    })

    it('选项含空字符串, 拒绝', 0, () => {
      const r = validateListeningQuizArgs(buildArgs({
        word: 'cat', question: 'q', correct_answer: 'cat',
        options: ['cat', 'car', '  ', 'can']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('为空')).assertTrue()
    })

    it('缺 options 数组, 拒绝', 0, () => {
      const r = validateListeningQuizArgs(buildArgs({
        word: 'cat', question: 'q', correct_answer: 'cat'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('options')).assertTrue()
    })

    it('参数不是合法 JSON, 拒绝', 0, () => {
      const r = validateListeningQuizArgs('{bad')
      expect(r.ok).assertFalse()
      expect(r.error.includes('JSON')).assertTrue()
    })
  })
}
