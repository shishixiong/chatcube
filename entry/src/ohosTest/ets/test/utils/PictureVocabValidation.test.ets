import { describe, it, expect } from '@ohos/hypium'
import { validatePictureVocabArgs } from '../../../../main/ets/utils/PictureVocabValidation'

/**
 * PictureVocabValidation 单元测试
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

function buildArgs(overrides: Record<string, Object>): string {
  return JSON.stringify(overrides)
}

export default function pictureVocabValidationTest() {
  describe('validatePictureVocabArgs - 合法路径', () => {
    it('mode=en: 4 个英文选项含答案, 合法', 0, () => {
      const r = validatePictureVocabArgs(buildArgs({
        mode: 'en', image_prompt: 'a red apple',
        correct_answer: 'apple', options: ['apple', 'banana', 'orange', 'pear'],
        difficulty: 1, skill_key: 'english_vocab'
      }))
      expect(r.ok).assertTrue()
    })

    it('mode=zh: 4 个汉字选项含答案, 合法', 0, () => {
      const r = validatePictureVocabArgs(buildArgs({
        mode: 'zh', image_prompt: 'a red apple',
        correct_answer: '苹', options: ['苹', '蕉', '葡', '梨'],
        difficulty: 1, skill_key: 'chinese_writing'
      }))
      expect(r.ok).assertTrue()
    })
  })

  describe('validatePictureVocabArgs - 失败路径', () => {
    it('mode 非法, 拒绝', 0, () => {
      const r = validatePictureVocabArgs(buildArgs({
        mode: 'fr', correct_answer: 'apple',
        options: ['apple', 'banana', 'orange', 'pear']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('mode')).assertTrue()
    })

    it('只有 3 个选项, 拒绝', 0, () => {
      const r = validatePictureVocabArgs(buildArgs({
        mode: 'en', correct_answer: 'apple',
        options: ['apple', 'banana', 'orange']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('4')).assertTrue()
    })

    it('5 个选项, 拒绝', 0, () => {
      const r = validatePictureVocabArgs(buildArgs({
        mode: 'en', correct_answer: 'apple',
        options: ['apple', 'banana', 'orange', 'pear', 'grape']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('4')).assertTrue()
    })

    it('正确答案不在选项里, 拒绝', 0, () => {
      const r = validatePictureVocabArgs(buildArgs({
        mode: 'en', correct_answer: 'kiwi',
        options: ['apple', 'banana', 'orange', 'pear']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('不在选项里')).assertTrue()
    })

    it('correct_answer 为空, 拒绝', 0, () => {
      const r = validatePictureVocabArgs(buildArgs({
        mode: 'en', correct_answer: '',
        options: ['apple', 'banana', 'orange', 'pear']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('correct_answer')).assertTrue()
    })

    it('选项含空字符串, 拒绝', 0, () => {
      const r = validatePictureVocabArgs(buildArgs({
        mode: 'en', correct_answer: 'apple',
        options: ['apple', 'banana', '  ', 'pear']
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('为空')).assertTrue()
    })

    it('缺 options 数组, 拒绝', 0, () => {
      const r = validatePictureVocabArgs(buildArgs({
        mode: 'en', correct_answer: 'apple'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('options')).assertTrue()
    })

    it('参数不是合法 JSON, 拒绝', 0, () => {
      const r = validatePictureVocabArgs('{bad')
      expect(r.ok).assertFalse()
      expect(r.error.includes('JSON')).assertTrue()
    })
  })
}
