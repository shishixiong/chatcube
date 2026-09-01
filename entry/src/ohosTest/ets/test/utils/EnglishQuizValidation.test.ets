import { describe, it, expect } from '@ohos/hypium'
import { validateEnglishQuizArgs } from '../../../../main/ets/utils/EnglishQuizValidation'

/**
 * EnglishQuizValidation 单元测试
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

function buildArgs(overrides: Record<string, Object>): string {
  return JSON.stringify(overrides)
}

export default function englishQuizValidationTest() {
  describe('validateEnglishQuizArgs - 合法路径', () => {
    it('word: 齐全, 合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        question: '苹果', image_prompt: 'A bright red apple, children illustration style',
        correct_answer: 'apple', question_type: 'word', difficulty: 1, skill_key: 'english_vocab'
      }))
      expect(r.ok).assertTrue()
    })

    it('sentence: 齐全, 合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        question: '我喜欢吃苹果', image_prompt: 'A happy child eating an apple',
        correct_answer: 'I like apples', question_type: 'sentence',
        difficulty: 3, skill_key: 'english_sentence'
      }))
      expect(r.ok).assertTrue()
    })

    it('phonics_choice: 字母选项含答案 + sound_text, 合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        question: '听一听是哪个字母的音?', correct_answer: 'k',
        question_type: 'phonics_choice', difficulty: 1, skill_key: 'english_phonics',
        letter_options: ['k', 'c', 's', 'p'], sound_text: 'kuh'
      }))
      expect(r.ok).assertTrue()
    })

    it('phonics_choice: 大小写不敏感匹配, 合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        question: 'q', correct_answer: 'K',
        question_type: 'phonics_choice',
        letter_options: ['k', 'c', 's'], sound_text: 'kuh'
      }))
      expect(r.ok).assertTrue()
    })
  })

  describe('validateEnglishQuizArgs - phonics_choice 失败路径', () => {
    it('letter_options 缺正确字母, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        question: 'q', correct_answer: 'k', question_type: 'phonics_choice',
        letter_options: ['c', 's', 'p'], sound_text: 'kuh'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('没有正确答案')).assertTrue()
    })

    it('sound_text 为空, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        question: 'q', correct_answer: 'k', question_type: 'phonics_choice',
        letter_options: ['k', 'c', 's'], sound_text: ''
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('sound_text')).assertTrue()
    })

    it('correct_answer 不是单字母, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        question: 'q', correct_answer: 'kk', question_type: 'phonics_choice',
        letter_options: ['kk', 'c', 's'], sound_text: 'kuh'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('单个字母')).assertTrue()
    })

    it('缺 letter_options 数组, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        question: 'q', correct_answer: 'k', question_type: 'phonics_choice',
        sound_text: 'kuh'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('letter_options')).assertTrue()
    })
  })

  describe('validateEnglishQuizArgs - word/sentence 失败路径', () => {
    it('word: 缺 image_prompt, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        question: '苹果', correct_answer: 'apple',
        question_type: 'word', difficulty: 1, skill_key: 'english_vocab'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('image_prompt')).assertTrue()
    })

    it('word: correct_answer 为空, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        question: '苹果', image_prompt: 'an apple',
        correct_answer: '', question_type: 'word'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('correct_answer')).assertTrue()
    })

    it('word: question 为空, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        question: '', image_prompt: 'an apple',
        correct_answer: 'apple', question_type: 'word'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('question')).assertTrue()
    })

    it('参数不是合法 JSON, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs('{bad')
      expect(r.ok).assertFalse()
      expect(r.error.includes('JSON')).assertTrue()
    })
  })
}
