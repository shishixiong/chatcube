import { describe, it, expect } from '@ohos/hypium'
import { splitTextForTts } from '../../../../main/ets/utils/TtsTextChunkUtils'
import { splitTextForStepFun } from '../../../../main/ets/utils/StepFunTtsTextUtils'

// 与 DEEPSEEK_MAX_INPUT_CHARS 一致
const MAX: number = 2000

export default function ttsTextChunkUtilsTest() {
  describe('splitTextForTts', () => {
    it('empty string returns empty array', 0, () => {
      expect(splitTextForTts('', MAX).length).assertEqual(0)
    })

    it('whitespace-only returns empty array', 0, () => {
      expect(splitTextForTts('   \n  ', MAX).length).assertEqual(0)
    })

    it('short text returns single unchanged chunk', 0, () => {
      const result = splitTextForTts('你好，小星老师。', MAX)
      expect(result.length).assertEqual(1)
      expect(result[0]).assertEqual('你好，小星老师。')
    })

    it('text exactly maxChars stays single chunk', 0, () => {
      const text = 'a'.repeat(MAX)
      const result = splitTextForTts(text, MAX)
      expect(result.length).assertEqual(1)
      expect(result[0]).assertEqual(text)
    })

    it('2001 ascii chars splits into two chunks within limit', 0, () => {
      const result = splitTextForTts('a'.repeat(2001), MAX)
      expect(result.length).assertEqual(2)
      expect(result[0].length).assertEqual(2000)
      expect(result[1].length).assertEqual(1)
    })

    it('full-width chinese respects the same limit and loses no chars', 0, () => {
      const text = '中'.repeat(2001)
      const result = splitTextForTts(text, MAX)
      expect(result.length).assertEqual(2)
      expect(result[0].length <= MAX).assertTrue()
      expect(result[1].length <= MAX).assertTrue()
      expect(result[0] + result[1]).assertEqual(text)
    })

    it('adjacent short sentences pack into one chunk', 0, () => {
      const text = '第一句。第二句。第三句。'
      const result = splitTextForTts(text, 100)
      expect(result.length).assertEqual(1)
      expect(result[0]).assertEqual(text)
    })

    it('oversized sentence with emoji is not split mid-surrogate', 0, () => {
      const text = 'a'.repeat(1999) + '\u{1F600}'
      const result = splitTextForTts(text, MAX)
      expect(result.length).assertEqual(2)
      expect(result[0].length).assertEqual(1999)
      expect(result[1]).assertEqual('\u{1F600}')
    })

    it('invalid maxChars returns whole text as single chunk', 0, () => {
      const result = splitTextForTts('abc', 0)
      expect(result.length).assertEqual(1)
      expect(result[0]).assertEqual('abc')
      const negative = splitTextForTts('abc', -5)
      expect(negative.length).assertEqual(1)
      expect(negative[0]).assertEqual('abc')
    })

    it('never emits an empty chunk around blank lines', 0, () => {
      const result = splitTextForTts('abcde\n\nfghij', 5)
      expect(result.length > 0).assertTrue()
      for (let i = 0; i < result.length; i++) {
        expect(result[i].length > 0).assertTrue()
      }
      expect(result[0]).assertEqual('abcde')
      expect(result[result.length - 1]).assertEqual('fghij')
    })

    it('stepfun wrapper delegates to the generic splitter', 0, () => {
      let text = ''
      for (let i = 0; i < 100; i++) {
        text = text + `这是第${i}句测试内容，用于验证切分逻辑。`
      }
      const generic = splitTextForTts(text, 1000)
      const wrapped = splitTextForStepFun(text, 1000)
      expect(wrapped.length).assertEqual(generic.length)
      for (let i = 0; i < generic.length; i++) {
        expect(wrapped[i]).assertEqual(generic[i])
      }
    })
  })
}
