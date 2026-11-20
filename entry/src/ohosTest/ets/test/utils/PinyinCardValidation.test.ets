import { describe, it, expect } from '@ohos/hypium'
import {
  composeSyllable,
  applyToneMark,
  validatePinyinCardArgs
} from '../../../../main/ets/utils/PinyinCardValidation'

/**
 * PinyinCardValidation 单元测试
 *
 * 重点覆盖 2026-11-19 修正的 ü 行韵母省写规则:
 *   j/q/x/y 后省两点 (jū 而非 jǖ)、零声母前加 y (yú)、n/l 后保留两点 (nǚ / lǜ)。
 * 修正前一律拼成 jǖ/qǘ/xǚ/yǜ, 会把规范拼音判为错误并要求模型改成错拼。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */

export default function pinyinCardValidationTest() {
  describe('applyToneMark - 标调位置', () => {
    it('a 优先: shan → shān', 0, () => {
      expect(applyToneMark('an', 1)).assertEqual('ān')
    })

    it('a 优先于 e/o: hai → hái', 0, () => {
      expect(applyToneMark('ai', 2)).assertEqual('ái')
    })

    it('iu 标在后: liu → liú', 0, () => {
      expect(applyToneMark('iu', 2)).assertEqual('iú')
    })

    it('ui 标在后: gui → guì', 0, () => {
      expect(applyToneMark('ui', 4)).assertEqual('uì')
    })

    it('单韵母: a → ā', 0, () => {
      expect(applyToneMark('a', 1)).assertEqual('ā')
    })

    it('ü 可标调: ü → ǚ', 0, () => {
      expect(applyToneMark('ü', 3)).assertEqual('ǚ')
    })

    it('轻声 (tone 0) 不加调号', 0, () => {
      expect(applyToneMark('an', 0)).assertEqual('an')
    })
  })

  describe('composeSyllable - j/q/x/y 后 ü 省写两点', () => {
    it('j + ü(1) → jū (居), 不是 jǖ', 0, () => {
      expect(composeSyllable('j', 'ü', 1)).assertEqual('jū')
    })

    it('q + ü(2) → qú (渠), 不是 qǘ', 0, () => {
      expect(composeSyllable('q', 'ü', 2)).assertEqual('qú')
    })

    it('x + ü(3) → xǔ (许), 不是 xǚ', 0, () => {
      expect(composeSyllable('x', 'ü', 3)).assertEqual('xǔ')
    })

    it('y + ü(4) → yù (玉), 不是 yǜ', 0, () => {
      expect(composeSyllable('y', 'ü', 4)).assertEqual('yù')
    })

    it('x + üan(1) → xuān (宣)', 0, () => {
      expect(composeSyllable('x', 'üan', 1)).assertEqual('xuān')
    })

    it('q + ün(2) → qún (群)', 0, () => {
      expect(composeSyllable('q', 'ün', 2)).assertEqual('qún')
    })

    it('j + üe(4) → juè (倔)', 0, () => {
      expect(composeSyllable('j', 'üe', 4)).assertEqual('juè')
    })
  })

  describe('composeSyllable - n/l 后保留两点', () => {
    it('n + ü(3) → nǚ (女)', 0, () => {
      expect(composeSyllable('n', 'ü', 3)).assertEqual('nǚ')
    })

    it('l + ü(4) → lǜ (绿)', 0, () => {
      expect(composeSyllable('l', 'ü', 4)).assertEqual('lǜ')
    })

    it('l + üe(4) → lüè (略)', 0, () => {
      expect(composeSyllable('l', 'üe', 4)).assertEqual('lüè')
    })
  })

  describe('composeSyllable - 零声母 ü 行加 y', () => {
    it('零声母 + ü(2) → yú (鱼)', 0, () => {
      expect(composeSyllable('', 'ü', 2)).assertEqual('yú')
    })

    it('零声母 + ü(4) → yù (玉)', 0, () => {
      expect(composeSyllable('', 'ü', 4)).assertEqual('yù')
    })

    it('零声母 + üe(4) → yuè (月)', 0, () => {
      expect(composeSyllable('', 'üe', 4)).assertEqual('yuè')
    })
  })

  describe('composeSyllable - 非 ü 韵母不受影响', () => {
    it('sh + an(1) → shān', 0, () => {
      expect(composeSyllable('sh', 'an', 1)).assertEqual('shān')
    })

    it('b + a(1) → bā', 0, () => {
      expect(composeSyllable('b', 'a', 1)).assertEqual('bā')
    })

    it('零声母 + an(1) → ān (安)', 0, () => {
      expect(composeSyllable('', 'an', 1)).assertEqual('ān')
    })
  })

  describe('validatePinyinCardArgs - 拼合一致性', () => {
    function base(): Record<string, Object> {
      return {
        initial: 'sh',
        final: 'an',
        tone: 1,
        syllable: 'shān',
        examples: [
          { tone: 1, syllable: 'shān', char: '山', word: '高山' },
          { tone: 4, syllable: 'shàn', char: '扇', word: '扇子' }
        ],
        mnemonic: 'sh 像小蛇，an 是安',
        difficulty: 1,
        skill_key: 'pinyin'
      }
    }

    it('合法基线通过', 0, () => {
      const r = validatePinyinCardArgs(JSON.stringify(base()))
      expect(r.ok).assertTrue()
    })

    it('jū 不再被判为拼合错误 (回归: 修正前会要求改成 jǖ)', 0, () => {
      const r = validatePinyinCardArgs(JSON.stringify({
        initial: 'j',
        final: 'ü',
        tone: 1,
        syllable: 'jū',
        examples: [
          { tone: 1, syllable: 'jū', char: '居', word: '居住' },
          { tone: 4, syllable: 'jù', char: '句', word: '句子' }
        ],
        mnemonic: 'j 和 ü 相拼，ü 要去掉两点',
        difficulty: 2,
        skill_key: 'pinyin'
      }))
      expect(r.ok).assertTrue()
    })

    it('错拼 jǖ 被拒绝并提示应为 jū', 0, () => {
      const r = validatePinyinCardArgs(JSON.stringify({
        initial: 'j',
        final: 'ü',
        tone: 1,
        syllable: 'jǖ',
        examples: [
          { tone: 1, syllable: 'jū', char: '居', word: '居住' },
          { tone: 4, syllable: 'jù', char: '句', word: '句子' }
        ],
        mnemonic: 'j 和 ü 相拼',
        difficulty: 2,
        skill_key: 'pinyin'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('jū')).assertTrue()
    })

    it('syllable 与拼合结果不符被拒绝', 0, () => {
      const args = base()
      args['syllable'] = 'shàn'
      const r = validatePinyinCardArgs(JSON.stringify(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('不符')).assertTrue()
    })

    it('examples 少于 2 条被拒绝', 0, () => {
      const args = base()
      args['examples'] = [{ tone: 1, syllable: 'shān', char: '山', word: '高山' }]
      const r = validatePinyinCardArgs(JSON.stringify(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('2')).assertTrue()
    })

    it('final 为空被拒绝', 0, () => {
      const args = base()
      args['final'] = ''
      const r = validatePinyinCardArgs(JSON.stringify(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('final')).assertTrue()
    })
  })
}
