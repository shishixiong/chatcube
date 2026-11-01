/**
 * ten_frame 凑十讲解纯函数（ArkUI-free，hypium 全覆盖）。
 *
 * 对齐 docs 原型「凑十小队 · 方块小人的十格课堂」：
 * - 讲解 4 步：看大数 → 拆小数 → 凑成十 → 十加几
 * - 练习 5 题：从 7-9 + 4-8 题库里换数字迁移
 * - 数字用 Numberblocks 风格彩色方块表示，1-10 各有固定色
 *
 * 记号：a = 十格框内的大数（5-9），b = 框外小数（1-10），
 * a+b > 10 且 ≤ 20。friend = 10 - a（凑十朋友），rest = b - friend（余数）。
 * 所有返回值强制类型注解（ArkTS 10605038）；防御性输入取界，不抛异常。
 */

export interface MakeTenPair {
  x: number
  y: number
}

export interface MakeTenLessonStep {
  title: string      // 看大数 / 拆小数 / 凑成十 / 十加几
  chip: string       // 第 1 步 · 看大数
  desc: string       // 步骤条副标题
  narration: string  // 引导卡正文 + TTS 口播
  hint: string       // 算式下方提示
  action: string     // 主按钮文案
}

export interface MakeTenProblem {
  a: number
  b: number
  need: number      // 要从 b 里拆出、送进框里的块数 = 10 - a
  rest: number      // 送完之后框外剩下的块数
  options: number[] // 3 个唯一选项（含 need），顺序确定
}

// 1-10 的方块色（对齐原型 COLORS；10 用深红，与 1 区分）
const BLOCK_COLORS: string[] = [
  '#E24B45', // 1
  '#F08A2C', // 2
  '#F4C63D', // 3
  '#47A85B', // 4
  '#3B82D8', // 5
  '#8C63D6', // 6
  '#DE5C9C', // 7
  '#2AA79B', // 8
  '#64748B', // 9
  '#B33636'  // 10
]

export function makeTenFriend(a: number): number {
  const v: number = 10 - a
  if (v < 1) { return 1 }
  if (v > 5) { return 5 }
  return v
}

export function makeTenRemain(b: number, friend: number): number {
  const r: number = b - friend
  if (r < 0) { return 0 }
  return r
}

/** 数字 1-10 对应的方块色；越界回退灰色。 */
export function makeTenBlockColor(n: number): string {
  if (n < 1 || n > BLOCK_COLORS.length) {
    return '#64748B'
  }
  return BLOCK_COLORS[n - 1]
}

/** 颜色变暗/变亮（factor < 1 变暗），用于方块底部阴影渐变。 */
export function makeTenShade(color: string, factor: number): string {
  if (!color.startsWith('#') || color.length !== 7) {
    return color
  }
  const r: number = parseInt(color.substring(1, 3), 16)
  const g: number = parseInt(color.substring(3, 5), 16)
  const b: number = parseInt(color.substring(5, 7), 16)
  return '#' + hexPair(Math.max(0, Math.min(255, Math.floor(r * factor)))) +
    hexPair(Math.max(0, Math.min(255, Math.floor(g * factor)))) +
    hexPair(Math.max(0, Math.min(255, Math.floor(b * factor))))
}

function hexPair(n: number): string {
  const h: string = n.toString(16)
  return h.length === 1 ? '0' + h : h
}

/** 方块色是否偏亮——亮色块上的嘴巴用深色，深色块上用白色。 */
export function makeTenIsLight(color: string): boolean {
  if (!color.startsWith('#') || color.length !== 7) {
    return false
  }
  const r: number = parseInt(color.substring(1, 3), 16) / 255
  const g: number = parseInt(color.substring(3, 5), 16) / 255
  const b: number = parseInt(color.substring(5, 7), 16) / 255
  const lum: number = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
  return lum > 0.42
}

function lin(v: number): number {
  return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
}

/** 凑十好朋友：1+9 … 5+5。 */
export function makeTenFriendPairs(): MakeTenPair[] {
  const pairs: MakeTenPair[] = [
    { x: 1, y: 9 },
    { x: 2, y: 8 },
    { x: 3, y: 7 },
    { x: 4, y: 6 },
    { x: 5, y: 5 }
  ]
  return pairs
}

/** 讲解 4 步（看大数 → 拆小数 → 凑成十 → 十加几）。 */
export function makeTenLessonSteps(a: number, b: number): MakeTenLessonStep[] {
  const friend: number = makeTenFriend(a)
  const rest: number = makeTenRemain(b, friend)
  const sum: number = a + b
  const steps: MakeTenLessonStep[] = [
    {
      title: '看大数',
      chip: '第 1 步 · 看大数',
      desc: `${a} 离十差 ${friend} 格`,
      narration: `先看大数 ${a}。十格框里已经住了 ${a} 块，还空 ${friend} 格。`,
      hint: `${a} 和 ${friend} 是凑十好朋友。`,
      action: `拆开 ${b}`
    },
    {
      title: '拆小数',
      chip: '第 2 步 · 拆小数',
      desc: `${b} = ${friend} + ${rest}`,
      narration: `${a} 离 10 还差 ${friend}，所以把 ${b} 拆成 ${friend} 和 ${rest}。`,
      hint: `${a} 先凑十，剩下 ${rest} 块留到最后。`,
      action: `送 ${friend} 块进框`
    },
    {
      title: '凑成十',
      chip: '第 3 步 · 凑成十',
      desc: `${a} + ${friend} = 10`,
      narration: `把 ${friend} 块送进空格——${a} 和 ${friend} 正好凑成 10！`,
      hint: '十格框满了，就是 10。',
      action: '算一算'
    },
    {
      title: '十加几',
      chip: '第 4 步 · 十加几',
      desc: `10 + ${rest} = ${sum}`,
      narration: `十格框满了就是 10，再加上剩下的 ${rest}，10 + ${rest} = ${sum}。`,
      hint: `十加 ${rest}，就是 ${sum}。`,
      action: '去练一练'
    }
  ]
  return steps
}

/** 4 步 TTS 口播稿（进入该步时朗读）。 */
export function makeTenStepNarrations(a: number, b: number): string[] {
  const steps: MakeTenLessonStep[] = makeTenLessonSteps(a, b)
  const narrations: string[] = []
  for (let i = 0; i < steps.length; i++) {
    narrations.push(steps[i].narration)
  }
  return narrations
}

/** 练习题库：a ∈ 7-9、b ∈ 4-8、b < a、a+b > 10（共 12 题）。 */
export function makeTenPracticePool(): MakeTenProblem[] {
  const pool: MakeTenProblem[] = []
  for (let a = 7; a <= 9; a++) {
    for (let b = 4; b <= 8; b++) {
      if (b >= a) {
        continue
      }
      if (a + b <= 10) {
        continue
      }
      pool.push(makeTenProblem(a, b))
    }
  }
  return pool
}

/** 单个练习题（含 3 个确定性选项）。 */
export function makeTenProblem(a: number, b: number): MakeTenProblem {
  const need: number = makeTenFriend(a)
  const rest: number = makeTenRemain(b, need)
  const problem: MakeTenProblem = {
    a: a,
    b: b,
    need: need,
    rest: rest,
    options: makeTenOptions(need, b, a * 10 + b)
  }
  return problem
}

/**
 * 3 个唯一选项：正确值 + 相邻干扰项，均落在 [1, b-1]（一定拿得出来）。
 * 用 seed 做确定性轮转，避免正确项总在第一位。
 */
export function makeTenOptions(need: number, b: number, seed: number): number[] {
  const base: number[] = [need]
  const candidates: number[] = [need - 1, need + 1, need - 2, need + 2, need + 3, need - 3]
  for (let i = 0; i < candidates.length; i++) {
    if (base.length >= 3) {
      break
    }
    const v: number = candidates[i]
    if (v >= 1 && v <= b - 1 && base.indexOf(v) < 0) {
      base.push(v)
    }
  }
  let v: number = 1
  while (base.length < 3 && v <= b) {
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
 */
export function makeTenPracticeRound(a: number, b: number, count: number): MakeTenProblem[] {
  const all: MakeTenProblem[] = makeTenPracticePool()
  const filtered: MakeTenProblem[] = []
  for (let i = 0; i < all.length; i++) {
    const p: MakeTenProblem = all[i]
    if (p.a !== a || p.b !== b) {
      filtered.push(p)
    }
  }
  const source: MakeTenProblem[] = filtered.length >= count ? filtered : all
  const randomOffset: number = (a * 7 + b * 3) % source.length
  const out: MakeTenProblem[] = []
  // 步长 5 与 11/12 都互质，连续 5 题不会撞题
  for (let i = 0; i < count; i++) {
    out.push(source[(randomOffset + i * 5) % source.length])
  }
  return out
}
