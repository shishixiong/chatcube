import { describe, it, expect } from '@ohos/hypium'
import { splitTextForStepFun } from '../../../../main/ets/utils/StepFunTtsTextUtils'

/**
 * splitTextForStepFun 单元测试
 *
 * 语义: 把文本切分为每段 ≤ maxChars 的数组, 供 StepFunTtsEngine 逐段
 * "合成→播放"串联 (/v1/audio/speech 的 input 上限 1000 字符)。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

const MAX: number = 1000

export default function stepFunTtsTextUtilsTest() {
  describe('splitTextForStepFun', () => {
    it('empty string returns empty array', 0, () => {
      expect(splitTextForStepFun('', MAX)).assertEqual([])
    })

    it('whitespace-only returns empty array', 0, () => {
      expect(splitTextForStepFun('   \n  ', MAX)).assertEqual([])
    })

    it('short text returns single unchanged chunk', 0, () => {
      expect(splitTextForStepFun('你好，小星老师。', MAX)).assertEqual(['你好，小星老师。'])
    })

    it('text exactly maxChars stays single chunk', 0, () => {
      const text = 'a'.repeat(MAX)
      const result = splitTextForStepFun(text, MAX)
      expect(result.length).assertEqual(1)
      expect(result[0]).assertEqual(text)
    })

    it('maxChars+1 splits into two chunks within limit', 0, () => {
      // 500 个 a + 句号 + 501 个 b: 第二句 501 > 剩余 500, 拆两段
      const text = 'a'.repeat(500) + '。' + 'b'.repeat(501)
      const result = splitTextForStepFun(text, MAX)
      expect(result.length).assertEqual(2)
      for (let i = 0; i < result.length; i++) {
        expect(result[i].length <= MAX).assertTrue()
      }
    })

    it('adjacent short sentences pack into one chunk', 0, () => {
      const text = '第一句。第二句。第三句。'
      const result = splitTextForStepFun(text, 100)
      expect(result.length).assertEqual(1)
      expect(result[0]).assertEqual(text)
    })

    it('newline acts as sentence boundary', 0, () => {
      // 600 + \n + 600 > 1000, 应在 \n 处拆分; 块尾换行被 trim 剥掉
      const text = 'a'.repeat(600) + '\n' + 'b'.repeat(600)
      const result = splitTextForStepFun(text, MAX)
      expect(result.length).assertEqual(2)
      expect(result[0].length).assertEqual(600) // 含换行 601, trim 后 600
      expect(result[1].length).assertEqual(600)
    })

    it('punctuation-free long text is hard-split at maxChars', 0, () => {
      const text = 'x'.repeat(2500)
      const result = splitTextForStepFun(text, MAX)
      expect(result.length).assertEqual(3)
      expect(result[0].length).assertEqual(MAX)
      expect(result[1].length).assertEqual(MAX)
      expect(result[2].length).assertEqual(500)
    })

    it('oversized sentence with emoji is not split mid-surrogate', 0, () => {
      // 😀 是代理对 (2 个 UTF-16 单元); 999 个 a + 😀 = 1001 单元, 需硬切
      const text = 'a'.repeat(999) + '\u{1F600}'
      const result = splitTextForStepFun(text, MAX)
      expect(result.length).assertEqual(2)
      // 切点回退 1, 第一段 999 单元, 😀 完整落在第二段
      expect(result[0].length).assertEqual(999)
      expect(result[1]).assertEqual('\u{1F600}')
      // 第二段可正常被 JSON.stringify / 字符串处理, 无孤立代理
      expect(result[1].charCodeAt(0) >= 0xD800 && result[1].charCodeAt(0) <= 0xDBFF).assertTrue()
    })

    it('all chunks within limit for mixed long text', 0, () => {
      let text = ''
      for (let i = 0; i < 100; i++) {
        text = text + `这是第${i}句测试内容，用于验证切分逻辑。`
      }
      const result = splitTextForStepFun(text, MAX)
      expect(result.length > 1).assertTrue()
      let joined = ''
      for (let i = 0; i < result.length; i++) {
        expect(result[i].length <= MAX).assertTrue()
        expect(result[i].length > 0).assertTrue()
        joined = joined + result[i]
      }
      expect(joined).assertEqual(text)
    })

    it('invalid maxChars returns whole text as single chunk', 0, () => {
      const text = 'abc'
      expect(splitTextForStepFun(text, 0)).assertEqual(['abc'])
      expect(splitTextForStepFun(text, -5)).assertEqual(['abc'])
    })

    it('mixed chinese and latin punctuation boundaries', 0, () => {
      const text = 'Hello! How are you? 我很好。'
      const result = splitTextForStepFun(text, 100)
      expect(result.length).assertEqual(1)
      expect(result[0]).assertEqual(text)
    })
  })
}
