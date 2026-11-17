/**
 * number_line 数轴跳一跳讲解纯函数（ArkUI-free，hypium 全覆盖）。
 *
 * spec 2026-11-17 P0 三板 §4.4：两步演示课，op 加减双向——
 * - add 凑十跳：start∈[6,9]，先跳到 10（+firstHop）再跳余数（+secondHop）
 * - sub 破十跳：start∈[11,18]，先跳回 10（-firstHop）再跳回余数（-secondHop）
 * 10 是中转站；两跳都必须存在（firstHop≥1、secondHop≥1，由预校验保证）。
 *
 * 几何全部在此算清（v1 §4.3 约定）：0-20 数轴映射到 320vp viewBox，
 * token 三个落点 x1/x2/x3 + 两段二次贝塞尔弧线控制点。
 * 所有返回值强制类型注解（ArkTS 10605038）；防御性输入取界，不抛异常。
 */

export const NUMBER_LINE_WIDTH: number = 320
export const NUMBER_LINE_PAD: number = 16
export const NUMBER_LINE_BASE_Y: number = 84
export const NUMBER_LINE_MAX: number = 20

export interface NumberLineHops {
  firstHop: number   // 第一跳幅度（到 10）
  secondHop: number  // 第二跳幅度（10 到终点）
  end: number        // 终点值
  dir: number        // 1 向右（add）/ -1 向左（sub）
  x1: number         // 起点 token 中心 x
  x2: number         // 中转站 10 的 x
  x3: number         // 终点 token 中心 x
  arc1X: number      // 弧线①控制点 x（两落点中点）
  arc1Y: number      // 弧线①控制点 y（越高弧越大）
  arc2X: number
  arc2Y: number
}

export interface NumberLineStep {
  title: string      // 先跳到 10 / 再跳余数 / 先跳回 10 / 再跳回余数
  chip: string
  narration: string
  hint: string
  action: string
}

function clampInt(v: number, min: number, max: number): number {
  if (Number.isNaN(v)) { return min }
  const n: number = Math.floor(v)
  if (n < min) { return min }
  if (n > max) { return max }
  return n
}

/** 数轴值 → viewBox x 坐标（0-20 线性映射，两侧留 PAD）。 */
export function numberLineX(v: number): number {
  const value: number = clampInt(v, 0, NUMBER_LINE_MAX)
  return NUMBER_LINE_PAD + value * (NUMBER_LINE_WIDTH - NUMBER_LINE_PAD * 2) / NUMBER_LINE_MAX
}

/** 弧线控制点 y：跳得越远弧顶越高，基准线上方 16 + 每格 5。 */
function arcY(hop: number): number {
  return NUMBER_LINE_BASE_Y - 16 - hop * 5
}

/** 两跳几何：add 向右凑十跳 / sub 向左破十跳。 */
export function numberLineHops(start: number, step: number, op: string): NumberLineHops {
  if (op === 'sub') {
    const s: number = clampInt(start, 11, 18)
    const k: number = clampInt(step, 2, 9)
    const firstHop: number = s - 10
    const end: number = s - k
    const secondHop: number = 10 - end
    const x1: number = numberLineX(s)
    const x2: number = numberLineX(10)
    const x3: number = numberLineX(end)
    return {
      firstHop: firstHop, secondHop: secondHop, end: end, dir: -1,
      x1: x1, x2: x2, x3: x3,
      arc1X: (x1 + x2) / 2, arc1Y: arcY(firstHop),
      arc2X: (x2 + x3) / 2, arc2Y: arcY(secondHop)
    }
  }
  const s: number = clampInt(start, 6, 9)
  const k: number = clampInt(step, 1, 10)
  const firstHop: number = 10 - s
  const end: number = s + k
  const secondHop: number = end - 10
  const x1: number = numberLineX(s)
  const x2: number = numberLineX(10)
  const x3: number = numberLineX(end)
  return {
    firstHop: firstHop, secondHop: secondHop, end: end, dir: 1,
    x1: x1, x2: x2, x3: x3,
    arc1X: (x1 + x2) / 2, arc1Y: arcY(firstHop),
    arc2X: (x2 + x3) / 2, arc2Y: arcY(secondHop)
  }
}

/** 两步演示课步骤数据（第 1 步跳到 10，第 2 步跳到终点）。 */
export function numberLineSteps(start: number, step: number, op: string): NumberLineStep[] {
  const hops: NumberLineHops = numberLineHops(start, step, op)
  if (op === 'sub') {
    const s: number = clampInt(start, 11, 18)
    const k: number = clampInt(step, 2, 9)
    const steps: NumberLineStep[] = [
      {
        title: '先跳回 10',
        chip: '第 1 步 · 先跳回 10',
        narration: `从 ${s} 出发，先往回跳 ${hops.firstHop} 格到 10：${s} - ${hops.firstHop} = 10。10 是中转站。`,
        hint: `${s} - ${hops.firstHop} = 10`,
        action: `再跳回 ${hops.secondHop}`
      },
      {
        title: '再跳回余数',
        chip: '第 2 步 · 再跳回余数',
        narration: `从 10 再往回跳 ${hops.secondHop} 格：10 - ${hops.secondHop} = ${hops.end}。所以 ${s} - ${k} = ${hops.end}。`,
        hint: `10 - ${hops.secondHop} = ${hops.end}`,
        action: '本课完成'
      }
    ]
    return steps
  }
  const s: number = clampInt(start, 6, 9)
  const k: number = clampInt(step, 1, 10)
  const steps: NumberLineStep[] = [
    {
      title: '先跳到 10',
      chip: '第 1 步 · 先跳到 10',
      narration: `从 ${s} 出发，先往前跳 ${hops.firstHop} 格到 10：${s} + ${hops.firstHop} = 10。10 是中转站。`,
      hint: `${s} + ${hops.firstHop} = 10`,
      action: `再跳 ${hops.secondHop}`
    },
    {
      title: '再跳余数',
      chip: '第 2 步 · 再跳余数',
      narration: `从 10 再往前跳 ${hops.secondHop} 格：10 + ${hops.secondHop} = ${hops.end}。所以 ${s} + ${k} = ${hops.end}。`,
      hint: `10 + ${hops.secondHop} = ${hops.end}`,
      action: '本课完成'
    }
  ]
  return steps
}

/** 2 步 TTS 口播稿。 */
export function numberLineStepNarrations(start: number, step: number, op: string): string[] {
  const steps: NumberLineStep[] = numberLineSteps(start, step, op)
  const narrations: string[] = []
  for (let i = 0; i < steps.length; i++) {
    narrations.push(steps[i].narration)
  }
  return narrations
}