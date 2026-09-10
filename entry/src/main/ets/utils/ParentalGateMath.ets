/**
 * 家长门算术题 — 纯函数（无 ArkUI 依赖，hypium 可测）。
 *
 * 题目两类随机混合:
 * - 两位数 × 一位数(3-9): 积 ≤ 891
 * - 三位数 ± 两位数: 和 ≤ 1098; 差保证 > 0
 * 目标用户 5 岁左右幼儿算不出来; 答错即换新题, 防同一题穷举。
 */

export interface GateQuestion {
  text: string
  answer: number
}

const MUL_MIN_A: number = 11
const MUL_MAX_A: number = 99
const MUL_MIN_B: number = 3
const MUL_MAX_B: number = 9
const ADDSUB_MIN_A: number = 100
const ADDSUB_MAX_A: number = 999
const ADDSUB_MIN_B: number = 10
const ADDSUB_MAX_B: number = 99
const MAX_ANSWER_INPUT_LENGTH: number = 4

function randomInt(min: number, max: number): number {
  return min + Math.floor(Math.random() * (max - min + 1))
}

export function generateGateQuestion(): GateQuestion {
  const kind: number = randomInt(0, 2)
  if (kind === 0) {
    const a: number = randomInt(MUL_MIN_A, MUL_MAX_A)
    const b: number = randomInt(MUL_MIN_B, MUL_MAX_B)
    return { text: `${a} × ${b}`, answer: a * b } as GateQuestion
  }
  if (kind === 1) {
    const a: number = randomInt(ADDSUB_MIN_A, ADDSUB_MAX_A)
    const b: number = randomInt(ADDSUB_MIN_B, ADDSUB_MAX_B)
    return { text: `${a} + ${b}`, answer: a + b } as GateQuestion
  }
  // 减法: b ≤ min(99, a-1), a ≥ 100 → 差恒 > 0
  const a: number = randomInt(ADDSUB_MIN_A, ADDSUB_MAX_A)
  const b: number = randomInt(ADDSUB_MIN_B, Math.min(ADDSUB_MAX_B, a - 1))
  return { text: `${a} − ${b}`, answer: a - b } as GateQuestion
}

export function checkGateAnswer(question: GateQuestion, input: string): boolean {
  const trimmed: string = input.trim()
  if (trimmed === '' || trimmed.length > MAX_ANSWER_INPUT_LENGTH) {
    return false
  }
  for (let i = 0; i < trimmed.length; i++) {
    const code: number = trimmed.charCodeAt(i)
    if (code < 48 || code > 57) {
      return false
    }
  }
  return Number.parseInt(trimmed, 10) === question.answer
}
