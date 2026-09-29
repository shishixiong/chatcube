/**
 * math_teach 讲解板几何纯函数（ArkUI-free，hypium 全覆盖）。
 * 所有返回值强制类型注解；防御性输入取界，不抛异常。
 */

export interface ClockAngles {
  hourDeg: number
  minuteDeg: number
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

export function bondSplit(total: number, left: number): number {
  let l: number = left
  if (l < 0) { l = 0 }
  if (l > total) { l = total }
  return total - l
}
