/**
 * number_bond 数的分与合两步演示课纯函数（ArkUI-free，hypium 全覆盖）。
 * v2（2026-10-03）：原 4 步引导课（数一数→分一分→合一合→找全部）精简为
 * 两步演示课（分一分→合起来）——删全枚举（total+1 种对两位数不可行），
 * 改为「推荐最佳分法」演示 + 从大数往后数的合并过程。校验层保证 2-99。
 *
 * 记号：total = 整体数。推荐分法规则：
 * - 11-99 → 整十 + 剩余（28→20+8、45→40+5）；整十数 → (total-10)+10（20→10+10）
 * - 6-10  → 5 锚定（9→5+4、10→5+5）
 * - 2-5   → 对半（4→2+2、3→1+2、5→2+3）
 * 所有返回值强制类型注解（ArkTS 10605038）；防御性输入取界，不抛异常。
 */

export interface NumberBondSplit {
  left: number
  right: number
}

export interface NumberBondScaffoldLine {
  eq: string
  label: string
}

/** 推荐最佳分法（两边都非空；left 按上述规则取大边）。 */
export function numberBondBestSplit(total: number): NumberBondSplit {
  let t: number = Math.floor(total)
  if (t < 2) {
    t = 2
  }
  if (t > 99) {
    t = 99
  }
  const s: NumberBondSplit = { left: 0, right: 0 }
  if (t >= 11) {
    const ones: number = t % 10
    if (ones === 0) {
      s.left = t - 10
      s.right = 10
    } else {
      s.left = t - ones
      s.right = ones
    }
    return s
  }
  if (t >= 6) {
    s.left = 5
    s.right = t - 5
    return s
  }
  s.left = Math.floor(t / 2)
  s.right = t - s.left
  return s
}

/** 「分合记录」脚手架 3 行：整体 → 分 → 合（跟着步骤点亮）。 */
export function numberBondScaffold(total: number, left: number, right: number): NumberBondScaffoldLine[] {
  let t: number = Math.floor(total)
  if (t < 2) {
    t = 2
  }
  if (t > 99) {
    t = 99
  }
  let l: number = Math.floor(left)
  if (l < 0) {
    l = 0
  }
  if (l > t) {
    l = t
  }
  const lines: NumberBondScaffoldLine[] = [
    { eq: `${t}`, label: '整体' },
    { eq: `${t} = ${l} + ${t - l}`, label: '分' },
    { eq: `${l} + ${t - l} = ${t}`, label: '合' }
  ]
  return lines
}

/** 两步标题（卡片头部主句）。 */
export function numberBondStepTitles(total: number): string[] {
  const s: NumberBondSplit = numberBondBestSplit(total)
  return [
    `把 ${s.left + s.right} 分一分`,
    `把 ${s.left} 和 ${s.right} 合起来`
  ]
}

/** 两步「小星老师说」提示（每步正文顶部的教学要点）。 */
export function numberBondStepTips(total: number): string[] {
  const s: NumberBondSplit = numberBondBestSplit(total)
  const t: number = s.left + s.right
  const big: number = s.left >= s.right ? s.left : s.right
  const small: number = t - big
  return [
    `老师推荐一种分法：把 ${t} 分成 ${s.left} 和 ${s.right}。点一点，看点子分成两组。`,
    `从大的数 ${big} 往后数 ${small} 个，一直数到 ${t}。分与合是一对好朋友。`
  ]
}

/** 两步口播稿（语音模式逐步朗读，符号已按中文读法转写后再交给 TTS）。 */
export function numberBondStepNarrations(total: number): string[] {
  const s: NumberBondSplit = numberBondBestSplit(total)
  const t: number = s.left + s.right
  const big: number = s.left >= s.right ? s.left : s.right
  const small: number = t - big
  return [
    `我们把 ${t} 分一分。推荐的分法是：${t} 分成 ${s.left} 和 ${s.right}。`,
    `把 ${s.left} 和 ${s.right} 合起来。从 ${big} 往后数 ${small} 个，合起来就是 ${t}。`
  ]
}
