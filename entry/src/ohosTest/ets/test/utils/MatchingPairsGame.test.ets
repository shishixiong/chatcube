/**
 * MatchingPairsGame 单元测试
 *
 * 覆盖 validateAndNormalizeMatchingPairs (校验/normalize) 与
 * shuffleRightColumn (种子化洗牌) 两个纯函数。
 */

import { describe, it, expect } from '@ohos/hypium'
import {
  MatchingPair,
  NormalizedMatchingPairsData,
  shuffleRightColumn,
  validateAndNormalizeMatchingPairs
} from '../../../../main/ets/utils/MatchingPairsGame'

function buildPairs(count: number): MatchingPair[] {
  const lefts: string[] = ['山', '水', '日', '月', '火']
  const rights: string[] = ['shān', 'shuǐ', 'rì', 'yuè', 'huǒ']
  const pairs: MatchingPair[] = []
  for (let i = 0; i < count; i++) {
    pairs.push({
      left: lefts[i],
      right: rights[i],
      leftEmoji: '',
      rightEmoji: ''
    })
  }
  return pairs
}

function buildArgsJson(pairsCount: number, extra: string): string {
  const pairs = buildPairs(pairsCount)
  const items: string[] = []
  for (let i = 0; i < pairs.length; i++) {
    items.push(`{"left": "${pairs[i].left}", "right": "${pairs[i].right}"}`)
  }
  const pairsJson = '[' + items.join(', ') + ']'
  if (extra !== '') {
    return `{"theme": "字和拼音", "pairs": ${pairsJson}, ${extra}}`
  }
  return `{"theme": "字和拼音", "pairs": ${pairsJson}}`
}

export default function MatchingPairsGameTest() {
  describe('MatchingPairsGameTest', () => {
    // ===== validateAndNormalizeMatchingPairs =====

    it('validates_4_pairs_happy_path', 0, () => {
      const result: NormalizedMatchingPairsData = validateAndNormalizeMatchingPairs(buildArgsJson(4, ''))
      expect(result.ok).assertTrue()
      expect(result.pairs.length).assertEqual(4)
      expect(result.difficulty).assertEqual(1)
      expect(result.theme).assertEqual('字和拼音')
      expect(result.skillKey).assertEqual('observation')
      expect(result.pairs[0].left).assertEqual('山')
      expect(result.pairs[0].right).assertEqual('shān')
    })

    it('validates_5_pairs_defaults_to_difficulty_2', 0, () => {
      const result: NormalizedMatchingPairsData = validateAndNormalizeMatchingPairs(buildArgsJson(5, ''))
      expect(result.ok).assertTrue()
      expect(result.difficulty).assertEqual(2)
    })

    it('validates_5_pairs_with_declared_3_keeps_3', 0, () => {
      const result: NormalizedMatchingPairsData = validateAndNormalizeMatchingPairs(buildArgsJson(5, '"difficulty": 3'))
      expect(result.ok).assertTrue()
      expect(result.difficulty).assertEqual(3)
    })

    it('rejects_3_pairs', 0, () => {
      const result: NormalizedMatchingPairsData = validateAndNormalizeMatchingPairs(buildArgsJson(3, ''))
      expect(result.ok).assertFalse()
      expect(result.error.includes('4 或 5')).assertTrue()
    })

    it('rejects_6_pairs', 0, () => {
      const result: NormalizedMatchingPairsData = validateAndNormalizeMatchingPairs(buildArgsJson(6, ''))
      expect(result.ok).assertFalse()
      expect(result.error.includes('4 或 5')).assertTrue()
    })

    it('rejects_duplicate_left', 0, () => {
      const json = `{"theme": "t", "pairs": [
        {"left": "山", "right": "a"}, {"left": "水", "right": "b"},
        {"left": "山", "right": "c"}, {"left": "日", "right": "d"}]}`
      const result: NormalizedMatchingPairsData = validateAndNormalizeMatchingPairs(json)
      expect(result.ok).assertFalse()
      expect(result.error.includes('重复')).assertTrue()
    })

    it('rejects_duplicate_right', 0, () => {
      const json = `{"theme": "t", "pairs": [
        {"left": "山", "right": "a"}, {"left": "水", "right": "a"},
        {"left": "日", "right": "c"}, {"left": "月", "right": "d"}]}`
      const result: NormalizedMatchingPairsData = validateAndNormalizeMatchingPairs(json)
      expect(result.ok).assertFalse()
      expect(result.error.includes('重复')).assertTrue()
    })

    it('rejects_empty_left', 0, () => {
      const json = `{"theme": "t", "pairs": [
        {"left": "", "right": "a"}, {"left": "水", "right": "b"},
        {"left": "日", "right": "c"}, {"left": "月", "right": "d"}]}`
      const result: NormalizedMatchingPairsData = validateAndNormalizeMatchingPairs(json)
      expect(result.ok).assertFalse()
      expect(result.error.includes('left 为空')).assertTrue()
    })

    it('rejects_missing_theme', 0, () => {
      const pairs = buildPairs(4)
      const items: string[] = []
      for (let i = 0; i < pairs.length; i++) {
        items.push(`{"left": "${pairs[i].left}", "right": "${pairs[i].right}"}`)
      }
      const json = `{"pairs": [${items.join(', ')}]}`
      const result: NormalizedMatchingPairsData = validateAndNormalizeMatchingPairs(json)
      expect(result.ok).assertFalse()
      expect(result.error.includes('theme')).assertTrue()
    })

    it('rejects_missing_pairs', 0, () => {
      const result: NormalizedMatchingPairsData = validateAndNormalizeMatchingPairs('{"theme": "t"}')
      expect(result.ok).assertFalse()
      expect(result.error.includes('pairs')).assertTrue()
    })

    it('rejects_bad_json', 0, () => {
      const result: NormalizedMatchingPairsData = validateAndNormalizeMatchingPairs('{not json')
      expect(result.ok).assertFalse()
      expect(result.error.includes('JSON')).assertTrue()
    })

    it('preserves_optional_labels_and_emojis', 0, () => {
      const json = `{"theme": "动物和家", "instruction": "帮动物找家", "left_label": "动物", "right_label": "家",
        "skill_key": "observation", "pairs": [
        {"left": "鸟", "right": "巢", "left_emoji": "🐦", "right_emoji": "🪺"},
        {"left": "鱼", "right": "水"},
        {"left": "马", "right": "厩"},
        {"left": "蜂", "right": "巢2"}]}`
      const result: NormalizedMatchingPairsData = validateAndNormalizeMatchingPairs(json)
      expect(result.ok).assertTrue()
      expect(result.instruction).assertEqual('帮动物找家')
      expect(result.leftLabel).assertEqual('动物')
      expect(result.rightLabel).assertEqual('家')
      expect(result.pairs[0].leftEmoji).assertEqual('🐦')
      expect(result.pairs[0].rightEmoji).assertEqual('🪺')
      expect(result.pairs[1].leftEmoji).assertEqual('')
    })

    // ===== shuffleRightColumn =====

    it('shuffle_is_deterministic_per_seed', 0, () => {
      const pairs = buildPairs(5)
      const a = shuffleRightColumn(pairs, 12345)
      const b = shuffleRightColumn(pairs, 12345)
      expect(a.length).assertEqual(b.length)
      for (let i = 0; i < a.length; i++) {
        expect(a[i].right).assertEqual(b[i].right)
      }
    })

    it('shuffle_is_a_permutation', 0, () => {
      const pairs = buildPairs(5)
      const shuffled = shuffleRightColumn(pairs, 42)
      expect(shuffled.length).assertEqual(5)
      // 洗牌后右列的每一项都来自原集合, 无增无减
      const originals: string[] = []
      for (let i = 0; i < pairs.length; i++) {
        originals.push(pairs[i].right)
      }
      for (let i = 0; i < shuffled.length; i++) {
        expect(originals.includes(shuffled[i].right)).assertTrue()
      }
      const set = new Set<string>()
      for (let i = 0; i < shuffled.length; i++) {
        set.add(shuffled[i].right)
      }
      expect(set.size).assertEqual(5)
    })

    it('shuffle_does_not_mutate_input', 0, () => {
      const pairs = buildPairs(4)
      shuffleRightColumn(pairs, 999)
      expect(pairs[0].right).assertEqual('shān')
      expect(pairs[1].right).assertEqual('shuǐ')
      expect(pairs[2].right).assertEqual('rì')
      expect(pairs[3].right).assertEqual('yuè')
    })

    it('shuffle_never_returns_identical_order', 0, () => {
      // 试多个种子: 即使某个种子的 Fisher-Yates 恰好产出原序, 防退化交换也应打散
      const pairs = buildPairs(4)
      for (let seed = 1; seed <= 200; seed++) {
        const shuffled = shuffleRightColumn(pairs, seed)
        let identical = true
        for (let i = 0; i < shuffled.length; i++) {
          if (shuffled[i].right !== pairs[i].right) {
            identical = false
            break
          }
        }
        expect(identical).assertFalse()
      }
    })
  })
}
