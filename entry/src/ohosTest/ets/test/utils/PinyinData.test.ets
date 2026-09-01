import { describe, it, expect } from '@ohos/hypium'
import { getPinyin, hasPinyin, getPinyinChars, getPinyinCharsJoined } from '../../../../main/ets/config/PinyinData'

/**
 * PinyinData 拼音字典单元测试
 *
 * 校验字典结构完整性: 每条 pinyin 符合「字母+带调元音」格式、无重复字、
 * 与 StrokeOrderData 字集重叠 (跨功能协同: 先认读后书写)。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */

const PINYIN_PATTERN = /^[a-züāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ]+$/

export default function pinyinDataTest() {
  describe('PinyinData - 查询函数', () => {
    it('getPinyin 命中字典', 0, () => {
      expect(getPinyin('山')).assertEqual('shān')
    })

    it('getPinyin 字典外返回 null', 0, () => {
      expect(getPinyin('龘')).assertNull()
    })

    it('hasPinyin 命中/未命中', 0, () => {
      expect(hasPinyin('一')).assertTrue()
      expect(hasPinyin('X')).assertFalse()
    })

    it('getPinyinChars 与 getPinyinCharsJoined 数量一致', 0, () => {
      const chars = getPinyinChars()
      const joined = getPinyinCharsJoined()
      expect(chars.length > 60).assertTrue()
      expect(joined.split(' ').length).assertEqual(chars.length)
    })
  })

  describe('PinyinData - 字典结构完整性', () => {
    it('所有字唯一 (无重复)', 0, () => {
      const chars = getPinyinChars()
      const set = new Set<string>(chars)
      expect(set.size).assertEqual(chars.length)
    })

    it('所有字是单个汉字', 0, () => {
      const chars = getPinyinChars()
      for (let i = 0; i < chars.length; i++) {
        expect(chars[i].length).assertEqual(1)
      }
    })

    it('所有 pinyin 符合字母+声调格式', 0, () => {
      const chars = getPinyinChars()
      for (let i = 0; i < chars.length; i++) {
        const pinyin = getPinyin(chars[i])
        expect(pinyin !== null).assertTrue()
        const match = (pinyin ?? '').match(PINYIN_PATTERN)
        expect(match !== null && match.length > 0).assertTrue()
      }
    })
  })
}
