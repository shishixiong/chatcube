import { describe, it, expect } from '@ohos/hypium'
import { normalizeEnglishText, isReadAloudMatch } from '../../../../main/ets/utils/ReadAloudMatcher'

/**
 * ReadAloudMatcher 单元测试
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */
export default function readAloudMatcherTest() {
  describe('normalizeEnglishText', () => {
    it('小写 + 去标点 + 折叠空格', 0, () => {
      expect(normalizeEnglishText('  I like Apples.  ')).assertEqual('i like apples')
    })
    it('撇号保留 (don\'t)', 0, () => {
      expect(normalizeEnglishText("Don't stop!")).assertEqual("don't stop")
    })
  })
  describe('isReadAloudMatch', () => {
    it('全等命中', 0, () => {
      expect(isReadAloudMatch('I like apples', 'I like apples.')).assertTrue()
    })
    it('大小写标点差异命中', 0, () => {
      expect(isReadAloudMatch('I LIKE APPLES!', 'I like apples')).assertTrue()
    })
    it('前后粘词 (子串包含) 命中', 0, () => {
      expect(isReadAloudMatch('Well, I like apples very much', 'I like apples')).assertTrue()
    })
    it('漏词不命中', 0, () => {
      expect(isReadAloudMatch('I like', 'I like apples')).assertFalse()
    })
    it('完全不同不命中', 0, () => {
      expect(isReadAloudMatch('red bus', 'I like apples')).assertFalse()
    })
    it('空串不命中', 0, () => {
      expect(isReadAloudMatch('', 'I like apples')).assertFalse()
      expect(isReadAloudMatch('I like apples', '')).assertFalse()
    })
  })
}
