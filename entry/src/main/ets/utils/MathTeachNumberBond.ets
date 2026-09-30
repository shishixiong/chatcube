/**
 * number_bond 数的分与合引导课纯函数（ArkUI-free，hypium 全覆盖）。
 * 参考 docs/number-bond-lesson.html（数的分与合 4 步深度课原型），按
 * number_bond 工具参数 total 泛化。四步：数一数 → 分一分 → 合一合 → 找全部。
 *
 * 记号：total = 整体数（校验层保证 2-10）。分法共 total+1 种，按
 * 「左边每次多 1、右边每次少 1」有序枚举，不重不漏。
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

/** 分好了吗：堆里空了，且两个盘子都不空（两边都要有才算分好）。 */
export function numberBondSplitReady(pileCount: number, leftCount: number, rightCount: number): boolean {
  return pileCount <= 0 && leftCount >= 1 && rightCount >= 1
}

/** 有序分法全表：left 从 0 到 total，right = total - left，共 total+1 种。 */
export function numberBondSplits(total: number): NumberBondSplit[] {
  let t: number = Math.floor(total)
  if (t < 1) {
    t = 1
  }
  if (t > 10) {
    t = 10
  }
  const arr: NumberBondSplit[] = []
  for (let i = 0; i <= t; i++) {
    const s: NumberBondSplit = { left: i, right: t - i }
    arr.push(s)
  }
  return arr
}

/** 「分合记录」脚手架 4 行：整体 → 分 → 合 → 有序（跟着步骤点亮）。 */
export function numberBondScaffold(total: number, left: number, right: number): NumberBondScaffoldLine[] {
  let t: number = Math.floor(total)
  if (t < 1) {
    t = 1
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
    { eq: `${l} + ${t - l} = ${t}`, label: '合' },
    { eq: `${t} 的 ${t + 1} 种分法`, label: '有序' }
  ]
  return lines
}

/** 四步标题（卡片头部主句）。 */
export function numberBondStepTitles(total: number): string[] {
  let t: number = Math.floor(total)
  if (t < 1) {
    t = 1
  }
  return [
    '一共有几个？先数一数',
    `把 ${t} 分成两堆`,
    '合起来看看',
    `${t} 一共有几种分法？`
  ]
}

/** 四步「小星老师说」提示（每步正文顶部的教学要点）。 */
export function numberBondStepTips(total: number): string[] {
  let t: number = Math.floor(total)
  if (t < 1) {
    t = 1
  }
  return [
    '先看清整体。一个一个数，最后数到的数就是一共有几个。',
    `把 ${t} 个小球分到两个盘子里，每个盘子都要有。分完就有分合式。`,
    `把分开的两部分合起来，看看还是不是 ${t}。分与合是一对好朋友。`,
    '有序地想：左边每次多 1，右边就每次少 1，这样不重不漏。'
  ]
}

/** 四步口播稿（语音模式逐步朗读，符号已按中文读法转写后再交给 TTS）。 */
export function numberBondStepNarrations(total: number): string[] {
  let t: number = Math.floor(total)
  if (t < 1) {
    t = 1
  }
  return [
    '盘子里一共有几个？一个一个点出来，最后数到的数就是一共有几个。',
    `把 ${t} 个小球拖进两个盘子里，每个盘子都要有。`,
    `把分开的两部分合起来，数一数还是不是 ${t}。`,
    `从左边 0 个开始，左边每次多 1，右边就每次少 1，把 ${t} 的分法全部找出来。`
  ]
}
