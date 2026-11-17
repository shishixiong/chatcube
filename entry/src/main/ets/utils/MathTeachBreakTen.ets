/**
 * break_ten 破十减法讲解纯函数（ArkUI-free，hypium 全覆盖）。
 *
 * 镜像 MathTeachMakeTen 凑十课结构（spec 2026-11-17 P0 三板 §4.2）：
 * - 讲解 4 步：看个位 → 拆成十和几 → 十里减 → 加回来
 * - 练习 5 题：从 a∈11-18、b∈2-9、b>a-10 题库（36 题）里换数字迁移，
 *   每题问关键步「10 - b = ?」，答对由板面动画揭示最终差
 *
 * 记号：a = 被减数（十几，11-18），b = 减数（2-9 且大于 a 的个位）。
 * ones = a - 10（个位），fromTen = 10 - b（十里减的结果），
 * result = fromTen + ones（加回来的最终差）。
 * 所有返回值强制类型注解（ArkTS 10605038）；防御性输入取界，不抛异常。
 * 方块色/明暗函数复用 MathTeachMakeTen，不复制。
 */

export interface BreakTenLessonStep {
  title: string      // 看个位 / 拆成十和几 / 十里减 / 加回来
  chip: string       // 第 1 步 · 看个位
  desc: string       // 步骤条副标题
  narration: string  // 引导卡正文 + TTS 口播
  hint: string       // 算式下方提示
  action: string     // 主按钮文案
}

export interface BreakTenProblem {
  a: number
  b: number
  ones: number      // 被减数个位 = a - 10
  fromTen: number   // 十里减结果 = 10 - b（练习问的就是它）
  result: number    // 最终差 = fromTen + ones
  options: number[] // 3 个唯一选项（含 fromTen），顺序确定
}

function clampInt(v: number, min: number, max: number): number {
  if (Number.isNaN(v)) { return min }
  const n: number = Math.floor(v)
  if (n < min) { return min }
  if (n > max) { return max }
  return n
}

/** 被减数个位（十几拆出的「几」），防御取界 [1,8]。 */
export function breakTenOnes(a: number): number {
  return clampInt(a, 11, 18) - 10
}

/** 十里减：10 - b，防御取界 [1,8]。 */
export function breakTenFromTen(b: number): number {
  return 10 - clampInt(b, 2, 9)
}

/** 最终差：(10 - b) + (a - 10)。 */
export function breakTenResult(a: number, b: number): number {
  return breakTenFromTen(b) + breakTenOnes(a)
}

/** 讲解 4 步（看个位 → 拆成十和几 → 十里减 → 加回来）。 */
export function breakTenLessonSteps(a: number, b: number): BreakTenLessonStep[] {
  const aa: number = clampInt(a, 11, 18)
  const bb: number = clampInt(b, 2, 9)
  const ones: number = aa - 10
  const fromTen: number = 10 - bb
  const result: number = fromTen + ones
  const steps: BreakTenLessonStep[] = [
    {
      title: '看个位',
      chip: '第 1 步 · 看个位',
      desc: `${ones} 减 ${bb} 不够减`,
      narration: `先看个位。${aa} 的个位是 ${ones}，${ones} 减 ${bb} 不够减，怎么办呢？`,
      hint: '个位不够减，可以请 10 来帮忙。',
      action: `拆开 ${aa}`
    },
    {
      title: '拆成十和几',
      chip: '第 2 步 · 拆成十和几',
      desc: `${aa} = 10 + ${ones}`,
      narration: `把 ${aa} 拆成 10 和 ${ones}。整整齐齐的 10 最好减，先用它来减 ${bb}。`,
      hint: `${aa} = 10 + ${ones}`,
      action: '用 10 来减'
    },
    {
      title: '十里减',
      chip: '第 3 步 · 十里减',
      desc: `10 - ${bb} = ${fromTen}`,
      narration: `从 10 里面减去 ${bb}：10 减 ${bb} 等于 ${fromTen}。`,
      hint: '满十的框里划掉，最好算。',
      action: '加回来'
    },
    {
      title: '加回来',
      chip: '第 4 步 · 加回来',
      desc: `${fromTen} + ${ones} = ${result}`,
      narration: `把剩下的 ${fromTen} 和个位原来的 ${ones} 加回来：${fromTen} + ${ones} = ${result}。所以 ${aa} - ${bb} = ${result}。`,
      hint: `${fromTen} + ${ones} = ${result}`,
      action: '去练一练'
    }
  ]
  return steps
}

/** 4 步 TTS 口播稿（进入该步时朗读）。 */
export function breakTenStepNarrations(a: number, b: number): string[] {
  const steps: BreakTenLessonStep[] = breakTenLessonSteps(a, b)
  const narrations: string[] = []
  for (let i = 0; i < steps.length; i++) {
    narrations.push(steps[i].narration)
  }
  return narrations
}

/** 练习题库：a ∈ 11-18、b ∈ 2-9、b > a-10（退位限定，共 36 题）。 */
export function breakTenPracticePool(): BreakTenProblem[] {
  const pool: BreakTenProblem[] = []
  for (let a = 11; a <= 18; a++) {
    for (let b = 2; b <= 9; b++) {
      if (b <= a - 10) {
        continue
      }
      pool.push(breakTenProblem(a, b))
    }
  }
  return pool
}

/** 单个练习题（含 3 个确定性选项，问「10 - b = ?」）。 */
export function breakTenProblem(a: number, b: number): BreakTenProblem {
  const aa: number = clampInt(a, 11, 18)
  const bb: number = clampInt(b, 2, 9)
  const fromTen: number = 10 - bb
  const ones: number = aa - 10
  const problem: BreakTenProblem = {
    a: aa,
    b: bb,
    ones: ones,
    fromTen: fromTen,
    result: fromTen + ones,
    options: breakTenOptions(fromTen, aa * 10 + bb)
  }
  return problem
}

/**
 * 3 个唯一选项：正确值 + 相邻干扰项，均落在 [1,9]。
 * 用 seed 做确定性轮转，避免正确项总在第一位。
 */
export function breakTenOptions(fromTen: number, seed: number): number[] {
  const base: number[] = [fromTen]
  const candidates: number[] = [fromTen - 1, fromTen + 1, fromTen - 2, fromTen + 2, fromTen + 3, fromTen - 3]
  for (let i = 0; i < candidates.length; i++) {
    if (base.length >= 3) {
      break
    }
    const v: number = candidates[i]
    if (v >= 1 && v <= 9 && base.indexOf(v) < 0) {
      base.push(v)
    }
  }
  let v: number = 1
  while (base.length < 3 && v <= 9) {
    if (base.indexOf(v) < 0) {
      base.push(v)
    }
    v++
  }
  const offset: number = ((seed % 3) + 3) % 3
  const options: number[] = []
  for (let i = 0; i < 3; i++) {
    options.push(base[(i + offset) % 3])
  }
  return options
}

/**
 * 5 题练习轮次：从题库里按确定性步长取题，优先避开本课 a+b，
 * 让「换个数字，方法不变」真正换数字。
 * 步长 11 与过滤后 35 题、兜底 36 题都互质，连续 5 题不会撞题。
 */
export function breakTenPracticeRound(a: number, b: number, count: number): BreakTenProblem[] {
  const all: BreakTenProblem[] = breakTenPracticePool()
  const filtered: BreakTenProblem[] = []
  for (let i = 0; i < all.length; i++) {
    const p: BreakTenProblem = all[i]
    if (p.a !== a || p.b !== b) {
      filtered.push(p)
    }
  }
  const source: BreakTenProblem[] = filtered.length >= count ? filtered : all
  const randomOffset: number = (a * 7 + b * 3) % source.length
  const out: BreakTenProblem[] = []
  for (let i = 0; i < count; i++) {
    out.push(source[(randomOffset + i * 11) % source.length])
  }
  return out
}