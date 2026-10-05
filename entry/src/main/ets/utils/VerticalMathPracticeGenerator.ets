// utils/VerticalMathPracticeGenerator.ets
// 竖式练习出题纯函数（docs/vertical_math_refine.html 练习页出题范围）。
// 随机源通过参数注入，hypium 测试可用确定性序列覆盖。
// 除法练习全部整除（商×除数=被除数），与设计稿 genPractice 一致。

import { VerticalMathOperation } from './VerticalMathSolver'

export interface VerticalMathPracticeProblem {
  operation: VerticalMathOperation
  a: number
  b: number
  answer: number
}

export type RandomSource = () => number

function randIntFrom(rand: RandomSource, min: number, max: number): number {
  const span: number = max - min + 1
  return min + Math.floor(rand() * span)
}

/** 生成指定位数（1-5）的随机自然数；digits ≤ 1 时返回 1-9。 */
function nDigitsValue(rand: RandomSource, digits: number): number {
  if (digits <= 1) {
    return randIntFrom(rand, 1, 9)
  }
  const min: number = Math.pow(10, digits - 1)
  const max: number = Math.pow(10, digits) - 1
  return randIntFrom(rand, min, max)
}

function problemKey(operation: VerticalMathOperation, a: number, b: number): string {
  return `${operation}_${a}_${b}`
}

/**
 * 按运算类型 + 难度（1 入门 / 2 进阶 / 3 挑战）生成一道题。
 * 非法 operation / difficulty 返回 null（调用方兜底）。
 *
 * 出题范围（2026-10-04 收窄：乘法固定一位数乘数、除法固定一位数除数）：
 * - add/sub: 入门 1-2位 × 1-2位；进阶 2位 × 2位；挑战 2-3位 × 2-3位（减法自动换序保证 a ≥ b）
 * - mul:     入门 a 1位 × b 1位；进阶 a 2位 × b 1位；挑战 a 2-3位 × b 1位
 * - div:     全整除。入门 除数2-9 商2-9；进阶 除数2-9 商11-99；挑战 除数2-9 商101-999
 */
export function generatePracticeProblem(
  operation: VerticalMathOperation,
  difficulty: number,
  rand: RandomSource
): VerticalMathPracticeProblem | null {
  const level: number = Math.floor(difficulty)
  if (level < 1 || level > 3) {
    return null
  }
  if (operation === VerticalMathOperation.ADD || operation === VerticalMathOperation.SUBTRACT) {
    const aDigits: number = level === 1 ? randIntFrom(rand, 1, 2) : level === 2 ? 2 : randIntFrom(rand, 2, 3)
    const bDigits: number = level === 1 ? randIntFrom(rand, 1, 2) : level === 2 ? 2 : randIntFrom(rand, 2, 3)
    let a: number = nDigitsValue(rand, aDigits)
    let b: number = nDigitsValue(rand, bDigits)
    if (operation === VerticalMathOperation.SUBTRACT && a < b) {
      const t: number = a
      a = b
      b = t
    }
    const answer: number = operation === VerticalMathOperation.ADD ? a + b : a - b
    const problem: VerticalMathPracticeProblem = { operation: operation, a: a, b: b, answer: answer }
    return problem
  }
  if (operation === VerticalMathOperation.MULTIPLY) {
    const aDigits: number = level === 1 ? 1 : level === 2 ? 2 : randIntFrom(rand, 2, 3)
    const a: number = nDigitsValue(rand, aDigits)
    const b: number = randIntFrom(rand, 2, 9)
    const problem: VerticalMathPracticeProblem = { operation: operation, a: a, b: b, answer: a * b }
    return problem
  }
  if (operation === VerticalMathOperation.DIVIDE) {
    const divisor: number = randIntFrom(rand, 2, 9)
    let quotient: number
    if (level === 1) {
      quotient = randIntFrom(rand, 2, 9)
    } else if (level === 2) {
      quotient = randIntFrom(rand, 11, 99)
    } else {
      quotient = randIntFrom(rand, 101, 999)
    }
    const a: number = divisor * quotient
    const problem: VerticalMathPracticeProblem = { operation: operation, a: a, b: divisor, answer: quotient }
    return problem
  }
  return null
}

/**
 * 生成一套 count 道不重复的练习题（按 "op_a_b" 键去重；重试后仍重复则接受）。
 * count 会被夹到 1..10；difficulty 夹到 1..3。
 */
export function generatePracticeSet(
  operation: VerticalMathOperation,
  difficulty: number,
  count: number,
  rand: RandomSource
): VerticalMathPracticeProblem[] {
  const clampedCount: number = Math.min(10, Math.max(1, Math.floor(count)))
  const clampedLevel: number = Math.min(3, Math.max(1, Math.floor(difficulty)))
  const problems: VerticalMathPracticeProblem[] = []
  const seen: Set<string> = new Set<string>()
  for (let i = 0; i < clampedCount; i++) {
    let problem: VerticalMathPracticeProblem | null = null
    for (let attempt = 0; attempt < 20; attempt++) {
      const candidate: VerticalMathPracticeProblem | null =
        generatePracticeProblem(operation, clampedLevel, rand)
      if (candidate === null) {
        continue
      }
      const key: string = problemKey(candidate.operation, candidate.a, candidate.b)
      if (!seen.has(key)) {
        problem = candidate
        break
      }
    }
    if (problem === null) {
      // 20 次都撞 key（范围极小的极端情况）——接受最后一题，保证套题完整
      const fallback: VerticalMathPracticeProblem | null =
        generatePracticeProblem(operation, clampedLevel, rand)
      if (fallback === null) {
        break
      }
      problem = fallback
    }
    seen.add(problemKey(problem.operation, problem.a, problem.b))
    problems.push(problem)
  }
  return problems
}
