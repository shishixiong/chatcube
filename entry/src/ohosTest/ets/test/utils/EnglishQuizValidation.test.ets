import { describe, it, expect } from '@ohos/hypium'
import { validateEnglishQuizArgs, resolveQuizMode } from '../../../../main/ets/utils/EnglishQuizValidation'

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

  describe('resolveQuizMode', () => {
    it('mode 合法 → 新路径', 0, () => {
      const r = resolveQuizMode(JSON.parse('{"mode":"read_aloud"}') as Record<string, Object>)
      expect(r.mode).assertEqual('read_aloud')
      expect(r.isLegacy).assertFalse()
    })
    it('mode 缺失 + question_type 合法 → legacy', 0, () => {
      const r = resolveQuizMode(JSON.parse('{"question_type":"phonics_choice"}') as Record<string, Object>)
      expect(r.mode).assertEqual('phonics_choice')
      expect(r.isLegacy).assertTrue()
    })
    it('mode 非法 + question_type 缺失 → 容错按 word (parseQuiz 同款)', 0, () => {
      const r = resolveQuizMode(JSON.parse('{"mode":"bogus"}') as Record<string, Object>)
      expect(r.mode).assertEqual('word')
      expect(r.isLegacy).assertTrue()
    })
    it('mode 非字符串 (数字) → 容错按 word (与 bogus 同款)', 0, () => {
      const r = resolveQuizMode(JSON.parse('{"mode":123}') as Record<string, Object>)
      expect(r.mode).assertEqual('word')
      expect(r.isLegacy).assertTrue()
    })
    it('mode 与 question_type 都空 → mode 为空串 (校验层 fail)', 0, () => {
      const r = resolveQuizMode(JSON.parse('{}') as Record<string, Object>)
      expect(r.mode).assertEqual('')
    })
  })
  describe('validateEnglishQuizArgs - 结果携带 mode/isLegacy', () => {
    it('legacy word 题回填 question_type + isLegacy=true', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        question: '苹果', image_prompt: 'an apple',
        correct_answer: 'apple', question_type: 'word'
      }))
      expect(r.ok).assertTrue()
      expect(r.mode).assertEqual('word')
      expect(r.isLegacy).assertTrue()
    })
    it('mode 与 question_type 都空 → 拒绝且提示 mode', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({ question: 'q', correct_answer: 'apple' }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('mode')).assertTrue()
    })
  })
  describe('listen_choice', () => {
    it('齐全合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'listen_choice', question: '听一听,选出你听到的单词', correct_answer: 'cat',
        options: ['cat', 'cap', 'can', 'hat'], tts_text: 'cat'
      }))
      expect(r.ok).assertTrue()
      expect(r.mode).assertEqual('listen_choice')
      expect(r.isLegacy).assertFalse()
    })
    it('options 缺正确答案, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'listen_choice', question: 'q', correct_answer: 'cat',
        options: ['cap', 'can', 'hat', 'hop'], tts_text: 'cat'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('正确答案')).assertTrue()
    })
    it('options 重复项 (去重后 <4), 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'listen_choice', question: 'q', correct_answer: 'cat',
        options: ['cat', 'cat', 'can', 'hat'], tts_text: 'cat'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('重复')).assertTrue()
    })
    it('options 大小写不敏感含答案, 通过', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'listen_choice', question: 'q', correct_answer: 'Apple',
        options: ['apple', 'banana', 'orange', 'pear'], tts_text: 'apple'
      }))
      expect(r.ok).assertTrue()
    })
    it('tts_text 缺失, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'listen_choice', question: 'q', correct_answer: 'cat',
        options: ['cat', 'cap', 'can', 'hat']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('tts_text')).assertTrue()
    })
  })
  describe('picture_word', () => {
    it('齐全合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'picture_word', question: '看图选词', correct_answer: 'apple',
        options: ['apple', 'banana', 'orange', 'pear'],
        image_prompt: 'A bright red apple, children illustration style'
      }))
      expect(r.ok).assertTrue()
    })
    it('image_prompt 缺失, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'picture_word', question: 'q', correct_answer: 'apple',
        options: ['apple', 'banana', 'orange', 'pear']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('image_prompt')).assertTrue()
    })
  })
  describe('phonics_blend', () => {
    it('short a 规则全 CVC 合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'phonics_blend', question: '拼一拼', correct_answer: 'cat',
        options: ['cat', 'ham', 'map', 'bat'], phonics_rule: 'short a'
      }))
      expect(r.ok).assertTrue()
    })
    it('correct_answer 不符合 short a (r-controlled car), 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'phonics_blend', question: 'q', correct_answer: 'car',
        options: ['car', 'ham', 'map', 'bat'], phonics_rule: 'short a'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('phonics_rule')).assertTrue()
    })
    it('干扰项违反规则, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'phonics_blend', question: 'q', correct_answer: 'cat',
        options: ['cat', 'ham', 'map', 'bed'], phonics_rule: 'short a'
      }))
      expect(r.ok).assertFalse()
    })
    it('不可解析的规则 (如 long vowel / digraph) 仅放行', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'phonics_blend', question: 'q', correct_answer: 'rain',
        options: ['rain', 'pain', 'main', 'train'], phonics_rule: 'long a (ai)'
      }))
      expect(r.ok).assertTrue()
    })
    it('phonics_rule 缺失, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'phonics_blend', question: 'q', correct_answer: 'cat',
        options: ['cat', 'ham', 'map', 'bat']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('phonics_rule')).assertTrue()
    })
  })
  describe('sentence_fill', () => {
    it('恰一个空合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'sentence_fill', question: '选词填空', correct_answer: 'apples',
        options: ['apples', 'banana', 'milk', 'eggs'], pattern: 'I like ___.'
      }))
      expect(r.ok).assertTrue()
    })
    it('0 个空, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'sentence_fill', question: 'q', correct_answer: 'apples',
        options: ['apples', 'banana', 'milk', 'eggs'], pattern: 'I like apples.'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('___')).assertTrue()
    })
    it('2 个空, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'sentence_fill', question: 'q', correct_answer: 'apples',
        options: ['apples', 'banana', 'milk', 'eggs'], pattern: '___ and ___.'
      }))
      expect(r.ok).assertFalse()
    })
  })
  describe('read_aloud', () => {
    it('短句合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'read_aloud', question: '跟我读', correct_answer: 'I like apples',
        target_text: 'I like apples', phonetic_hint: 'th → this'
      }))
      expect(r.ok).assertTrue()
    })
    it('超 8 词, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'read_aloud', question: 'q', correct_answer: 'a b c d e f g h i',
        target_text: 'a b c d e f g h i'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('8')).assertTrue()
    })
  })
  describe('letter_trace', () => {
    it('upper 合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'letter_trace', question: '描一描', correct_answer: 'A',
        letter: 'A', 'case': 'upper'
      }))
      expect(r.ok).assertTrue()
    })
    it('lower 合法', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'letter_trace', question: 'q', correct_answer: 'a', letter: 'a', 'case': 'lower'
      }))
      expect(r.ok).assertTrue()
    })
    it('letter 非单字符, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'letter_trace', question: 'q', correct_answer: 'ab', letter: 'ab', 'case': 'upper'
      }))
      expect(r.ok).assertFalse()
    })
    it('case 非法值, 拒绝', 0, () => {
      const r = validateEnglishQuizArgs(buildArgs({
        mode: 'letter_trace', question: 'q', correct_answer: 'a', letter: 'a', 'case': 'both'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('case')).assertTrue()
    })
  })
}
