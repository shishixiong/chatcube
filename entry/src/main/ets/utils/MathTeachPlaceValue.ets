/**
 * place_value 小棒与数位讲解纯函数（ArkUI-free，hypium 全覆盖）。
 *
 * spec 2026-11-17 P0 三板 §4.3：两步演示课，action 二选一——
 * - bundle 捆扎课（进位算理）：数一数 → 添棒满十捆一捆（tens+1, ones=0）
 * - unbundle 拆捆课（退位算理）：数一数 → 拆一捆变十根（tens-1, ones+10，总数不变）
 *
 * 记号：tens = 十位捆数，ones = 个位散棒数。
 * bundle：tens ∈ [0,8]、ones ∈ [1,9]（捆完 ≤9 捆，不引入百位）；
 * unbundle：tens ∈ [1,9]、ones ∈ [0,9]。
 * 所有返回值强制类型注解（ArkTS 10605038）；防御性输入取界，不抛异常。
 */

export interface PlaceValueState {
  tens: number
  ones: number
}

export interface PlaceValueStep {
  title: string      // 数一数 / 满十捆一捆 / 拆一捆
  chip: string       // 第 1 步 · 数一数
  narration: string  // 引导卡正文 + TTS 口播
  hint: string       // 板面提示
  action: string     // 主按钮文案
}

function clampInt(v: number, min: number, max: number): number {
  if (Number.isNaN(v)) { return min }
  const n: number = Math.floor(v)
  if (n < min) { return min }
  if (n > max) { return max }
  return n
}

/** 读数：tens*10 + ones。 */
export function placeValueRead(tens: number, ones: number): number {
  return clampInt(tens, 0, 9) * 10 + clampInt(ones, 0, 19)
}

/** bundle 课要添的散棒数：10 - ones（ones 防御取界 [1,9]）。 */
export function placeValueAddToTen(ones: number): number {
  return 10 - clampInt(ones, 1, 9)
}

/** 个位是否满十可捆扎。 */
export function canBundle(ones: number): boolean {
  return ones >= 10
}

/** 演示后的板面状态：bundle → {tens+1, 0}；unbundle → {tens-1, ones+10}。 */
export function placeValueAfter(tens: number, ones: number, action: string): PlaceValueState {
  if (action === 'unbundle') {
    const t: number = clampInt(tens, 1, 9)
    const o: number = clampInt(ones, 0, 9)
    return { tens: t - 1, ones: o + 10 }
  }
  const t: number = clampInt(tens, 0, 8)
  return { tens: t + 1, ones: 0 }
}

/** 两步演示课步骤数据（第 1 步数一数，第 2 步捆扎/拆捆动画）。 */
export function placeValueSteps(tens: number, ones: number, action: string): PlaceValueStep[] {
  if (action === 'unbundle') {
    const t: number = clampInt(tens, 1, 9)
    const o: number = clampInt(ones, 0, 9)
    const read: number = t * 10 + o
    const steps: PlaceValueStep[] = [
      {
        title: '数一数',
        chip: '第 1 步 · 数一数',
        narration: `${t} 捆小棒和 ${o} 根小棒，合起来是 ${read}。要是拆开一捆，会发生什么呢？`,
        hint: `${read} = ${t} 个十和 ${o} 个一`,
        action: '拆一捆'
      },
      {
        title: '拆一捆',
        chip: '第 2 步 · 拆一捆',
        narration: `拆开 1 捆，变成 10 根散棒。现在是 ${t - 1} 捆和 ${o + 10} 根，还是 ${read}，总数没有变。竖式退位「借 1 当 10」，就是拆开这一捆。`,
        hint: '1 捆 = 10 根，总数不变',
        action: '本课完成'
      }
    ]
    return steps
  }
  const t: number = clampInt(tens, 0, 8)
  const o: number = clampInt(ones, 1, 9)
  const read: number = t * 10 + o
  const add: number = 10 - o
  const steps: PlaceValueStep[] = [
    {
      title: '数一数',
      chip: '第 1 步 · 数一数',
      narration: `${t} 捆小棒和 ${o} 根小棒，合起来是 ${read}。个位再添几根，就能凑满 10 根呢？`,
      hint: `${read} = ${t} 个十和 ${o} 个一`,
      action: '添棒凑十'
    },
    {
      title: '满十捆一捆',
      chip: '第 2 步 · 满十捆一捆',
      narration: `${o} 根添上 ${add} 根，正好 10 根。捆成 1 捆放进十位——现在是 ${t + 1} 捆和 0 根，是 ${read + add}。竖式进位「进 1」，就是这一捆。`,
      hint: `${o} + ${add} = 10，捆成 1 捆`,
      action: '本课完成'
    }
  ]
  return steps
}

/** 2 步 TTS 口播稿。 */
export function placeValueStepNarrations(tens: number, ones: number, action: string): string[] {
  const steps: PlaceValueStep[] = placeValueSteps(tens, ones, action)
  const narrations: string[] = []
  for (let i = 0; i < steps.length; i++) {
    narrations.push(steps[i].narration)
  }
  return narrations
}