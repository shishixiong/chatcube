import { describe, it, expect } from '@ohos/hypium'
import {
  generatePracticeProblem,
  generatePracticeSet,
  RandomSource,
  VerticalMathPracticeProblem
} from '../../../../main/ets/utils/VerticalMathPracticeGenerator'
import { VerticalMathOperation } from '../../../../main/ets/utils/VerticalMathSolver'

/**
 * VerticalMathPracticeGenerator 单元测试
 *
 * 随机源注入确定性 LCG 序列, 覆盖加减乘除 3 难度出题范围 + 整除不变式 + 非法输入 + 套题去重/夹取。
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

// 确定性伪随机 (经典 LCG): 同种子序列完全可复现, 替代 Math.random
function buildLcg(seed: number): RandomSource {
  let state: number = seed
  return (): number => {
    state = (state * 9301 + 49297) % 233280
    return state / 233280
  }
}

function digitCount(n: number): number {
  return String(n).length
}

// 采样 60 道 (确定性序列), 谓词全真
function allProblemsSatisfy(
  operation: VerticalMathOperation,
  difficulty: number,
  seed: number,
  predicate: (p: VerticalMathPracticeProblem) => boolean
): boolean {
  const rand: RandomSource = buildLcg(seed)
  for (let i = 0; i < 60; i++) {
    const problem = generatePracticeProblem(operation, difficulty, rand)
    if (problem === null) {
      return false
    }
    if (problem.operation !== operation) {
      return false
    }
    if (!predicate(problem)) {
      return false
    }
  }
  return true
}

export default function verticalMathPracticeGeneratorTest() {
  describe('generatePracticeProblem - 加减法范围', () => {
    it('add 入门: 1-2 位操作数, 答案 = a+b', 0, () => {
      const ok = allProblemsSatisfy(VerticalMathOperation.ADD, 1, 42, (p: VerticalMathPracticeProblem): boolean =>
        digitCount(p.a) <= 2 && digitCount(p.b) <= 2 && p.a >= 1 && p.b >= 1 && p.answer === p.a + p.b)
      expect(ok).assertTrue()
    })
    it('add 进阶: 均为 2 位, 答案 = a+b', 0, () => {
      const ok = allProblemsSatisfy(VerticalMathOperation.ADD, 2, 7, (p: VerticalMathPracticeProblem): boolean =>
        digitCount(p.a) === 2 && digitCount(p.b) === 2 && p.answer === p.a + p.b)
      expect(ok).assertTrue()
    })
    it('add 挑战: 2-3 位, 答案 = a+b', 0, () => {
      const ok = allProblemsSatisfy(VerticalMathOperation.ADD, 3, 123, (p: VerticalMathPracticeProblem): boolean =>
        digitCount(p.a) >= 2 && digitCount(p.a) <= 3 && digitCount(p.b) >= 2 && digitCount(p.b) <= 3
        && p.answer === p.a + p.b)
      expect(ok).assertTrue()
    })
    it('subtract: 恒有 a ≥ b (自动换序) 且答案 = a-b', 0, () => {
      const ok = (p: VerticalMathPracticeProblem): boolean => p.a >= p.b && p.answer === p.a - p.b
      expect(allProblemsSatisfy(VerticalMathOperation.SUBTRACT, 1, 9, ok)).assertTrue()
      expect(allProblemsSatisfy(VerticalMathOperation.SUBTRACT, 3, 19, ok)).assertTrue()
    })
  })

  describe('generatePracticeProblem - 乘法范围（乘数固定一位）', () => {
    it('mul 入门: a 1 位, b 2-9, 答案 = a×b', 0, () => {
      const ok = allProblemsSatisfy(VerticalMathOperation.MULTIPLY, 1, 33, (p: VerticalMathPracticeProblem): boolean =>
        digitCount(p.a) === 1 && p.b >= 2 && p.b <= 9 && p.answer === p.a * p.b)
      expect(ok).assertTrue()
    })
    it('mul 进阶: a 2 位, b 2-9', 0, () => {
      const ok = allProblemsSatisfy(VerticalMathOperation.MULTIPLY, 2, 44, (p: VerticalMathPracticeProblem): boolean =>
        digitCount(p.a) === 2 && p.b >= 2 && p.b <= 9 && p.answer === p.a * p.b)
      expect(ok).assertTrue()
    })
    it('mul 挑战: a 2-3 位, b 2-9（恒一位乘数）', 0, () => {
      const ok = allProblemsSatisfy(VerticalMathOperation.MULTIPLY, 3, 55, (p: VerticalMathPracticeProblem): boolean =>
        digitCount(p.a) >= 2 && digitCount(p.a) <= 3 && p.b >= 2 && p.b <= 9 && p.answer === p.a * p.b)
      expect(ok).assertTrue()
    })
  })

  describe('generatePracticeProblem - 除法整除不变式（除数固定一位）', () => {
    it('div 入门: 除数 2-9, 商 2-9, 全整除', 0, () => {
      const ok = allProblemsSatisfy(VerticalMathOperation.DIVIDE, 1, 77, (p: VerticalMathPracticeProblem): boolean =>
        p.b >= 2 && p.b <= 9 && p.answer >= 2 && p.answer <= 9 && p.a % p.b === 0 && p.a === p.b * p.answer)
      expect(ok).assertTrue()
    })
    it('div 进阶: 除数 2-9, 商 11-99, 全整除', 0, () => {
      const ok = allProblemsSatisfy(VerticalMathOperation.DIVIDE, 2, 88, (p: VerticalMathPracticeProblem): boolean =>
        p.b >= 2 && p.b <= 9 && p.answer >= 11 && p.answer <= 99 && p.a % p.b === 0 && p.a === p.b * p.answer)
      expect(ok).assertTrue()
    })
    it('div 挑战: 除数 2-9, 商 101-999, 全整除', 0, () => {
      const ok = allProblemsSatisfy(VerticalMathOperation.DIVIDE, 3, 99, (p: VerticalMathPracticeProblem): boolean =>
        p.b >= 2 && p.b <= 9 && p.answer >= 101 && p.answer <= 999 && p.a % p.b === 0 && p.a === p.b * p.answer)
      expect(ok).assertTrue()
    })
  })

  describe('generatePracticeProblem - 非法输入', () => {
    it('difficulty 0 / 4 返回 null', 0, () => {
      const rand: RandomSource = buildLcg(1)
      expect(generatePracticeProblem(VerticalMathOperation.ADD, 0, rand)).assertNull()
      expect(generatePracticeProblem(VerticalMathOperation.ADD, 4, rand)).assertNull()
    })
  })

  describe('generatePracticeSet - 夹取 / 去重 / 可复现', () => {
    it('count 0 → 1 题, count 99 → 10 题', 0, () => {
      const setA: VerticalMathPracticeProblem[] =
        generatePracticeSet(VerticalMathOperation.ADD, 1, 0, buildLcg(5))
      const setB: VerticalMathPracticeProblem[] =
        generatePracticeSet(VerticalMathOperation.ADD, 1, 99, buildLcg(6))
      expect(setA.length).assertEqual(1)
      expect(setB.length).assertEqual(10)
    })
    it('同种子序列完全可复现', 0, () => {
      const setA: VerticalMathPracticeProblem[] =
        generatePracticeSet(VerticalMathOperation.SUBTRACT, 2, 5, buildLcg(2024))
      const setB: VerticalMathPracticeProblem[] =
        generatePracticeSet(VerticalMathOperation.SUBTRACT, 2, 5, buildLcg(2024))
      expect(setA.length).assertEqual(setB.length)
      let same: boolean = setA.length === setB.length
      for (let i = 0; same && i < setA.length; i++) {
        same = setA[i].a === setB[i].a && setA[i].b === setB[i].b && setA[i].answer === setB[i].answer
      }
      expect(same).assertTrue()
    })
    it('套题夹取为 10 题且互不重复 (add 进阶)', 0, () => {
      const set: VerticalMathPracticeProblem[] =
        generatePracticeSet(VerticalMathOperation.ADD, 2, 60, buildLcg(31))
      expect(set.length).assertEqual(10)
      let duplicate: boolean = false
      for (let i = 0; i < set.length; i++) {
        for (let j = i + 1; j < set.length; j++) {
          if (set[i].a === set[j].a && set[i].b === set[j].b) {
            duplicate = true
          }
        }
      }
      expect(duplicate).assertFalse()
    })
  })
}
