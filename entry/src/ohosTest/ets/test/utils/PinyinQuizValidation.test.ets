import { describe, it, expect } from '@ohos/hypium'
import { validatePinyinQuizArgs } from '../../../../main/ets/utils/PinyinQuizValidation'

/**
 * PinyinQuizValidation 单元测试
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

function buildArgs(overrides: Record<string, Object>): string {
  return JSON.stringify(overrides)
}

export default function pinyinQuizValidationTest() {
  describe('validatePinyinQuizArgs - 合法路径', () => {
    it('齐全字段 (山 shān), 合法', 0, () => {
      const r = validatePinyinQuizArgs(buildArgs({
        character: '山', question: '这个字怎么读？', correct_answer: 'shān',
        options: ['shān', 'shàn', 'sān', 'shuān'], difficulty: 1, skill_key: 'pinyin'
      }))
      expect(r.ok).assertTrue()
    })

    it('question 缺省 (可选字段), 合法', 0, () => {
      const r = validatePinyinQuizArgs(buildArgs({
        character: '月', correct_answer: 'yuè',
        options: ['yuè', 'yuē', 'yúe', 'yuě'], difficulty: 2, skill_key: 'pinyin'
      }))
      expect(r.ok).assertTrue()
    })

    it('ü 元音字 (女 nǚ), 合法', 0, () => {
      const r = validatePinyinQuizArgs(buildArgs({
        character: '女', correct_answer: 'nǚ',
        options: ['nǚ', 'nù', 'nǔ', 'lǜ'], difficulty: 3, skill_key: 'pinyin'
      }))
      expect(r.ok).assertTrue()
    })
  })

  describe('validatePinyinQuizArgs - 字典校验', () => {
    it('character 不在字典内, 拒绝 (防字典外重试死循环)', 0, () => {
      const r = validatePinyinQuizArgs(buildArgs({
        character: '龘', correct_answer: 'dá',
        options: ['dá', 'dā', 'dà', 'tā'], difficulty: 1, skill_key: 'pinyin'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('字表')).assertTrue()
    })

    it('correct_answer 与字典读音不符, 拒绝 (不做静默修复)', 0, () => {
      const r = validatePinyinQuizArgs(buildArgs({
        character: '山', correct_answer: 'shàn',
        options: ['shàn', 'shān', 'sān', 'shuān'], difficulty: 1, skill_key: 'pinyin'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('shān')).assertTrue()
    })

    it('correct_answer 为空, 拒绝并提示正确读音', 0, () => {
      const r = validatePinyinQuizArgs(buildArgs({
        character: '水', correct_answer: '',
        options: ['shuǐ', 'shuì', 'suǐ', 'shuí'], difficulty: 1, skill_key: 'pinyin'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('shuǐ')).assertTrue()
    })
  })

  describe('validatePinyinQuizArgs - 失败路径', () => {
    it('character 为多字, 拒绝', 0, () => {
      const r = validatePinyinQuizArgs(buildArgs({
        character: '大山', correct_answer: 'shān',
        options: ['shān', 'shàn', 'sān', 'shuān'], difficulty: 1, skill_key: 'pinyin'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('单个汉字')).assertTrue()
    })

    it('只有 3 个选项, 拒绝', 0, () => {
      const r = validatePinyinQuizArgs(buildArgs({
        character: '山', correct_answer: 'shān',
        options: ['shān', 'shàn', 'sān'], difficulty: 1, skill_key: 'pinyin'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('4')).assertTrue()
    })

    it('5 个选项, 拒绝', 0, () => {
      const r = validatePinyinQuizArgs(buildArgs({
        character: '山', correct_answer: 'shān',
        options: ['shān', 'shàn', 'sān', 'shuān', 'shǎn'], difficulty: 1, skill_key: 'pinyin'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('4')).assertTrue()
    })

    it('选项重复, 拒绝', 0, () => {
      const r = validatePinyinQuizArgs(buildArgs({
        character: '山', correct_answer: 'shān',
        options: ['shān', 'shān', 'sān', 'shuān'], difficulty: 1, skill_key: 'pinyin'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('重复')).assertTrue()
    })

    it('正确答案不在选项里, 拒绝', 0, () => {
      const r = validatePinyinQuizArgs(buildArgs({
        character: '山', correct_answer: 'shān',
        options: ['shàn', 'sān', 'shuān', 'shǎn'], difficulty: 1, skill_key: 'pinyin'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('不在选项里')).assertTrue()
    })

    it('选项含空字符串, 拒绝', 0, () => {
      const r = validatePinyinQuizArgs(buildArgs({
        character: '山', correct_answer: 'shān',
        options: ['shān', '  ', 'sān', 'shuān'], difficulty: 1, skill_key: 'pinyin'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('为空')).assertTrue()
    })

    it('缺 options 数组, 拒绝', 0, () => {
      const r = validatePinyinQuizArgs(buildArgs({
        character: '山', correct_answer: 'shān'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('options')).assertTrue()
    })

    it('参数不是合法 JSON, 拒绝', 0, () => {
      const r = validatePinyinQuizArgs('{bad')
      expect(r.ok).assertFalse()
      expect(r.error.includes('JSON')).assertTrue()
    })
  })
}
