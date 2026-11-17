/**
 * fraction_intro 分数初步认识演示课纯函数（ArkUI-free，hypium 覆盖率）。
 *
 * 「平均分」是分数概念的唯一算理根基：先把整体平均分成 parts 份（分母），
 * 再取 shaded 份（分子），读作「parts 分之 shaded」。
 *
 * 只到真分数初步认识：分母 2–8、分子 1..分母−1（共 28 种组合）。
 * 取满全部份数（shaded = parts）即整体 1，属 P1 边界课，本课截断。
 *
 * 扇形 / 分数条几何全部在这里算清，组件与 quiz 卡片共用（跨 import 先例：
 * MathQuizCard 已 import mathTeach/ClockFaceView）。
 * 防御取界：越界参数一律 clamp 到合法区间，不抛异常。
 */

export interface FractionIntroStep {
  title: string
  chip: string
  narration: string
  hint: string
  action: string
}

export interface BarSegment {
  x: number
  w: number
}

export const FRACTION_MIN_PARTS: number = 2
export const FRACTION_MAX_PARTS: number = 8

const ZH_NUMBERS: string[] = ['零', '一', '二', '三', '四', '五', '六', '七', '八']

export function normalizeFractionForm(raw: string): string {
  return raw === 'bar' ? 'bar' : 'pizza'
}

export function clampFractionParts(raw: number): number {
  if (!Number.isFinite(raw)) {
    return FRACTION_MIN_PARTS
  }
  const n: number = Math.floor(raw)
  if (n < FRACTION_MIN_PARTS) {
    return FRACTION_MIN_PARTS
  }
  if (n > FRACTION_MAX_PARTS) {
    return FRACTION_MAX_PARTS
  }
  return n
}

export function clampFractionShaded(parts: number, raw: number): number {
  const p: number = clampFractionParts(parts)
  if (!Number.isFinite(raw)) {
    return 1
  }
  const n: number = Math.floor(raw)
  if (n < 1) {
    return 1
  }
  if (n > p - 1) {
    return p - 1
  }
  return n
}

/** 「3/4」 */
export function fractionReadout(parts: number, shaded: number): string {
  const p: number = clampFractionParts(parts)
  const s: number = clampFractionShaded(p, shaded)
  return `${s}/${p}`
}

function zhNum(n: number): string {
  if (n >= 0 && n < ZH_NUMBERS.length) {
    return ZH_NUMBERS[n]
  }
  return `${n}`
}

/** 「四分之三」：分母在前 + 分之 + 分子 */
export function fractionReadoutZh(parts: number, shaded: number): string {
  const p: number = clampFractionParts(parts)
  const s: number = clampFractionShaded(p, shaded)
  return `${zhNum(p)}分之${zhNum(s)}`
}

function formUnit(form: string): string {
  return normalizeFractionForm(form) === 'bar' ? '长条' : '披萨'
}

export function fractionIntroSteps(parts: number, shaded: number, form: string): FractionIntroStep[] {
  const p: number = clampFractionParts(parts)
  const s: number = clampFractionShaded(p, shaded)
  const unit: string = formUnit(form)
  const steps: FractionIntroStep[] = [
    {
      title: '平均分',
      chip: `${p} 份一样大`,
      narration: `把${unit}平均分成 ${p} 份，每份同样大——只有平均分才能用分数`,
      hint: `点一下，把${unit}平均分成 ${p} 份`,
      action: `平均分成 ${p} 份`
    },
    {
      title: '取几份',
      chip: `${fractionReadout(p, s)} 读作${fractionReadoutZh(p, s)}`,
      narration: `平均分成 ${p} 份取 ${s} 份，写成 ${s}/${p}，读作${fractionReadoutZh(p, s)}；` +
        `分母 ${p} 是分的份数，分子 ${s} 是取的份数`,
      hint: `点一下，取 ${s} 份涂色`,
      action: `取 ${s} 份`
    }
  ]
  return steps
}

export function fractionIntroStepNarrations(parts: number, shaded: number, form: string): string[] {
  const steps: FractionIntroStep[] = fractionIntroSteps(parts, shaded, form)
  const narrations: string[] = []
  for (let i = 0; i < steps.length; i++) {
    narrations.push(steps[i].narration)
  }
  return narrations
}

function fmt(v: number): string {
  return v.toFixed(2)
}

/**
 * 第 index 份扇形 Path 命令（box 为正方形边长）：
 * M cx cy L x1 y1 A r r 0 largeArc 1 x2 y2 Z
 * 起点 12 点方向（-90°），顺时针每份 360/parts；parts=2 时半圆 largeArc=0。
 */
export function fractionSectorCommands(parts: number, index: number, box: number): string {
  const p: number = clampFractionParts(parts)
  const size: number = Number.isFinite(box) && box > 0 ? box : 1
  const c: number = size / 2
  const r: number = size * 0.46
  const slice: number = 360 / p
  const startDeg: number = index * slice
  const endDeg: number = startDeg + slice
  const startRad: number = startDeg * Math.PI / 180
  const endRad: number = endDeg * Math.PI / 180
  const x1: number = c + r * Math.sin(startRad)
  const y1: number = c - r * Math.cos(startRad)
  const x2: number = c + r * Math.sin(endRad)
  const y2: number = c - r * Math.cos(endRad)
  const largeArc: number = slice > 180 ? 1 : 0
  return 'M ' + fmt(c) + ' ' + fmt(c) +
    ' L ' + fmt(x1) + ' ' + fmt(y1) +
    ' A ' + fmt(r) + ' ' + fmt(r) + ' 0 ' + largeArc + ' 1 ' + fmt(x2) + ' ' + fmt(y2) + ' Z'
}

/** 分数条等分：{x, w}[]，份与份之间无缝隙（描边由组件画） */
export function fractionBarSegments(parts: number, width: number): BarSegment[] {
  const p: number = clampFractionParts(parts)
  const total: number = Number.isFinite(width) && width > 0 ? width : 1
  const w: number = total / p
  const segments: BarSegment[] = []
  for (let i = 0; i < p; i++) {
    const segment: BarSegment = { x: w * i, w: w }
    segments.push(segment)
  }
  return segments
}