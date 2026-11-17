import { describe, it, expect } from '@ohos/hypium'
import {
  hashSeedFromString,
  shuffleQuizOptions,
  shuffleStringOptions
} from '../../../../main/ets/utils/QuizOptionShuffle'

/**
 * QuizOptionShuffle 单元测试（选择题选项顺序确定性洗牌）
 *
 * 背景: math_quiz / chinese_quiz 的选项由 LLM 生成, 即使 schema 要求「打乱顺序」,
 * 模型仍习惯把正确答案放第一个。渲染层按 toolCall.id 种子确定性洗牌修正。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */

function positionOf(values: Array<string | number>, target: string | number): number {
  for (let i = 0; i < values.length; i++) {
    if (values[i] === target) {
      return i
    }
  }
  return -1
}

function sameOrder(a: Array<string | number>, b: Array<string | number>): boolean {
  if (a.length !== b.length) {
    return false
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      return false
    }
  }
  return true
}

export default function quizOptionShuffleTest() {
  describe('QuizOptionShuffle', () => {
    it('hashSeedFromString_is_deterministic_and_nonzero', 0, () => {
      expect(hashSeedFromString('tool-call-1')).assertEqual(hashSeedFromString('tool-call-1'))
      expect(hashSeedFromString('tool-call-1') !== 0).assertTrue()
      expect(hashSeedFromString('')).assertEqual(1)
    })

    it('shuffle_preserves_elements_as_permutation', 0, () => {
      const input: Array<string | number> = ['A', 'B', 'C', 'D']
      const output = shuffleQuizOptions(input, hashSeedFromString('abc'))
      expect(output.length).assertEqual(4)
      // 每个元素恰好出现一次
      expect(positionOf(output, 'A') >= 0).assertTrue()
      expect(positionOf(output, 'B') >= 0).assertTrue()
      expect(positionOf(output, 'C') >= 0).assertTrue()
      expect(positionOf(output, 'D') >= 0).assertTrue()
    })

    it('same_seed_yields_same_order', 0, () => {
      const input: Array<string | number> = [1, 2, 3, 4]
      const a = shuffleQuizOptions(input, hashSeedFromString('same-tool-call'))
      const b = shuffleQuizOptions(input, hashSeedFromString('same-tool-call'))
      expect(sameOrder(a, b)).assertTrue()
    })

    it('different_seeds_vary_correct_answer_position', 0, () => {
      const input: Array<string | number> = ['right', 'w1', 'w2', 'w3']
      const seeds: string[] = ['q-1', 'q-2', 'q-3', 'q-4', 'q-5', 'q-6', 'q-7', 'q-8']
      let correctFirst = 0
      for (let i = 0; i < seeds.length; i++) {
        const out = shuffleQuizOptions(input, hashSeedFromString(seeds[i]))
        if (out[0] === 'right') {
          correctFirst += 1
        }
      }
      // 不能再出现「永远第一个是正确答案」; 8 个种子全都命中第一个的概率 (1/4)^8 可忽略
      expect(correctFirst < seeds.length).assertTrue()
    })

    it('never_returns_identical_order_for_multi_item_lists', 0, () => {
      const input: Array<string | number> = ['A', 'B', 'C', 'D']
      for (let i = 0; i < 50; i++) {
        const out = shuffleQuizOptions(input, hashSeedFromString(`seed-${i}`))
        expect(sameOrder(out, input)).assertFalse()
      }
    })

    it('handles_empty_and_single_element_inputs', 0, () => {
      const empty: Array<string | number> = []
      expect(shuffleQuizOptions(empty, 42).length).assertEqual(0)
      const single: Array<string | number> = ['only']
      const out = shuffleQuizOptions(single, 42)
      expect(out.length).assertEqual(1)
      expect(out[0]).assertEqual('only')
    })

    it('does_not_mutate_input_array', 0, () => {
      const input: Array<string | number> = ['A', 'B', 'C', 'D']
      shuffleQuizOptions(input, hashSeedFromString('mutate-check'))
      expect(sameOrder(input, ['A', 'B', 'C', 'D'])).assertTrue()
    })

    it('string_wrapper_matches_generic_shuffle', 0, () => {
      const input: string[] = ['x', 'y', 'z']
      const seed = hashSeedFromString('str-wrap')
      const wrapped = shuffleStringOptions(input, seed)
      const generic = shuffleQuizOptions(input, seed)
      expect(wrapped.length).assertEqual(3)
      for (let i = 0; i < wrapped.length; i++) {
        expect(wrapped[i]).assertEqual(String(generic[i]))
      }
    })
  })
}
