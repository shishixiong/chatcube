/**
 * math_teach 讲解板几何纯函数（ArkUI-free，hypium 全覆盖）。
 * 所有返回值强制类型注解；防御性输入取界，不抛异常。
 */

export interface ClockAngles {
  hourDeg: number
  minuteDeg: number
}

export interface BarPercents {
  aPct: number
  bPct: number
}

export interface NumberLineHops {
  firstHop: number   // 10 - start（凑十第一跳）
  secondHop: number  // 剩余跳数；start+step=10 时为 0（校验层已拒 ≤10，此为兜底）
  sum: number
}

export function clockAngles(hour: number, minute: number): ClockAngles {
  const h: number = ((hour % 12) + 12) % 12
  return { hourDeg: (h + minute / 60) * 30, minuteDeg: minute * 6 }
}

export function balanceTilt(left: number, right: number): number {
  const raw: number = (right - left) * 4
  if (raw > 12) { return 12 }
  if (raw < -12) { return -12 }
  return raw
}

export function barPercents(a: number, b: number): BarPercents {
  const total: number = a + b
  if (total <= 0) {
    const zero: BarPercents = { aPct: 0, bPct: 0 }
    return zero
  }
  // bPct 取补数（100 - aPct），保证两侧百分比恒和为 100——
  // 独立四舍五入在 x.5 边界会出 38+63=101，下游 100% 宽容器会裁切。
  const aPct: number = Math.round(a / total * 100)
  const p: BarPercents = { aPct: aPct, bPct: 100 - aPct }
  return p
}

export function numberLineHops(start: number, step: number): NumberLineHops {
  const firstHop: number = 10 - start
  let secondHop: number = step - firstHop
  if (secondHop < 0) { secondHop = 0 }
  const hops: NumberLineHops = { firstHop: firstHop, secondHop: secondHop, sum: start + step }
  return hops
}

export function bondSplit(total: number, left: number): number {
  let l: number = left
  if (l < 0) { l = 0 }
  if (l > total) { l = total }
  return total - l
}

export function canBundle(ones: number): boolean {
  return ones >= 10
}
