import { describe, it, expect } from '@ohos/hypium'
import { normalizeMathSymbolsForTts } from '../../../../main/ets/utils/TtsTextUtils'

/**
 * normalizeMathSymbolsForTts 单元测试
 *
 * 数学符号 → 中文读法, 数字邻接才转。
 * 核心消费方: 竖式步进旁白 (U+2212 − / 全角 ＝) 与 math_quiz 题面 (ASCII 符号)。
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

export default function ttsTextUtilsTest() {
  describe('normalizeMathSymbolsForTts - 竖式旁白场景', () => {
    it('借位链: U+2212 − 与全角 ＝ 连续替换', 0, () => {
      expect(normalizeMathSymbolsForTts('5 − 1 − 1 ＝ 3')).assertEqual('5 减 1 减 1 等于 3')
    })
    it('普通减法步: 14 − 7 ＝ 7', 0, () => {
      expect(normalizeMathSymbolsForTts('14 − 7 ＝ 7')).assertEqual('14 减 7 等于 7')
    })
    it('全角 ＋ 与全角 －', 0, () => {
      expect(normalizeMathSymbolsForTts('7 ＋ 8')).assertEqual('7 加 8')
      expect(normalizeMathSymbolsForTts('9 － 4')).assertEqual('9 减 4')
    })
    it('纯文字旁白原样返回', 0, () => {
      expect(normalizeMathSymbolsForTts('从百位借 1，本位不够减。')).assertEqual('从百位借 1，本位不够减。')
    })
  })

  describe('normalizeMathSymbolsForTts - math_quiz 题面场景', () => {
    it('47 + 28 等于几？', 0, () => {
      expect(normalizeMathSymbolsForTts('47 + 28 等于几？')).assertEqual('47 加 28 等于几？')
    })
    it('无空格紧写 3+5=8', 0, () => {
      expect(normalizeMathSymbolsForTts('3+5=8')).assertEqual('3 加 5 等于 8')
    })
    it('乘除: 12×3 与 14 ÷ 7 ＝ 2', 0, () => {
      expect(normalizeMathSymbolsForTts('12×3')).assertEqual('12 乘 3')
      expect(normalizeMathSymbolsForTts('14 ÷ 7 ＝ 2')).assertEqual('14 除以 7 等于 2')
    })
  })

  describe('normalizeMathSymbolsForTts - 不该转的场景', () => {
    it('字母邻接的连字符不转 (T-shirt / well-known)', 0, () => {
      expect(normalizeMathSymbolsForTts('T-shirt')).assertEqual('T-shirt')
      expect(normalizeMathSymbolsForTts('well-known')).assertEqual('well-known')
    })
    it('斜杠不转 (日期 / 分数)', 0, () => {
      expect(normalizeMathSymbolsForTts('2026/09/04')).assertEqual('2026/09/04')
      expect(normalizeMathSymbolsForTts('6/2')).assertEqual('6/2')
    })
    it('非数字邻接的 × 不转', 0, () => {
      expect(normalizeMathSymbolsForTts('a × b')).assertEqual('a × b')
    })
    it('空字符串', 0, () => {
      expect(normalizeMathSymbolsForTts('')).assertEqual('')
    })
  })
}
