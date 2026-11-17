/**
 * shape_props 图形特征演示课纯函数（ArkUI-free，hypium 全覆盖）。
 *
 * 只数「直边凸多边形」的边与角：triangle / square / rectangle / pentagon。
 * circle 的「边」定义有争议（0/1 条曲线边），star / heart 是非凸图形（星形 10 条边），
 * 都超出一二年级认知，白名单在 teach 校验与 quiz 校验两侧共用一份。
 *
 * 派生值（边数 / 角数 / 顶点 / 口播）全部在这里算清，组件只负责画；
 * 防御取界：未知图形一律返回 0 / 空数组，不抛异常。
 */

export interface ShapePropsStep {
  title: string
  chip: string
  desc: string
  narration: string
  hint: string
  action: string
}

export interface ShapePropsEdge {
  x1: number
  y1: number
  x2: number
  y2: number
}

/** 可数边角的图形白名单（teach / quiz 共用） */
export const SHAPE_COUNTABLE: string[] = ['triangle', 'square', 'rectangle', 'pentagon']

const SHAPE_NAMES_ZH: Record<string, string> = {
  'triangle': '三角形',
  'square': '正方形',
  'rectangle': '长方形',
  'pentagon': '五边形'
}

const SIDE_COUNTS: Record<string, number> = {
  'triangle': 3,
  'square': 4,
  'rectangle': 4,
  'pentagon': 5
}

export function isCountableShape(shape: string): boolean {
  return SHAPE_COUNTABLE.indexOf(shape) >= 0
}

export function shapePropsNameZh(shape: string): string {
  const z: string | undefined = SHAPE_NAMES_ZH[shape]
  return z === undefined ? '' : z
}

export function shapePropsSides(shape: string): number {
  const n: number | undefined = SIDE_COUNTS[shape]
  return n === undefined ? 0 : n
}

/** 凸多边形边角等数：正方形 4 个角、五边形 5 个角 */
export function shapePropsCorners(shape: string): number {
  return shapePropsSides(shape)
}

function clampBox(box: number): number {
  if (!Number.isFinite(box) || box <= 0) {
    return 1
  }
  return box
}

function regularVertices(count: number, box: number): number[][] {
  const size: number = clampBox(box)
  const c: number = size / 2
  const r: number = size * 0.46
  const points: number[][] = []
  for (let i = 0; i < count; i++) {
    // 12 点方向为第一个顶点，顺时针均分
    const rad: number = (i * 360 / count - 90) * Math.PI / 180
    const p: number[] = [c + r * Math.cos(rad), c + r * Math.sin(rad)]
    points.push(p)
  }
  return points
}

/**
 * 顶点坐标（居中，落在 [0, box] 内）。
 * square 取正四边形，rectangle 宽高比 1.6:1，其余按正多边形外接圆。
 */
export function shapePropsVertices(shape: string, box: number): number[][] {
  const size: number = clampBox(box)
  const c: number = size / 2
  if (shape === 'triangle') {
    return regularVertices(3, size)
  }
  if (shape === 'pentagon') {
    return regularVertices(5, size)
  }
  if (shape === 'square') {
    const half: number = size * 0.4
    const points: number[][] = [
      [c - half, c - half], [c + half, c - half], [c + half, c + half], [c - half, c + half]
    ]
    return points
  }
  if (shape === 'rectangle') {
    const halfW: number = size * 0.46
    const halfH: number = halfW / 1.6
    const points: number[][] = [
      [c - halfW, c - halfH], [c + halfW, c - halfH], [c + halfW, c + halfH], [c - halfW, c + halfH]
    ]
    return points
  }
  return []
}

/** 逐条边（首尾相连闭合），供数边逐条高亮 */
export function shapePropsEdges(shape: string, box: number): ShapePropsEdge[] {
  const vertices: number[][] = shapePropsVertices(shape, box)
  const edges: ShapePropsEdge[] = []
  for (let i = 0; i < vertices.length; i++) {
    const a: number[] = vertices[i]
    const b: number[] = vertices[(i + 1) % vertices.length]
    const edge: ShapePropsEdge = { x1: a[0], y1: a[1], x2: b[0], y2: b[1] }
    edges.push(edge)
  }
  return edges
}

function sideRemark(shape: string, sides: number): string {
  if (shape === 'square') {
    return `${sides} 条边同样长`
  }
  if (shape === 'rectangle') {
    return `${sides} 条边，对边同样长`
  }
  return `${sides} 条边`
}

export function shapePropsSummary(shape: string): string {
  const sides: number = shapePropsSides(shape)
  if (sides === 0) {
    return ''
  }
  return `${sides} 条边 · ${sides} 个角`
}

export function shapePropsSteps(shape: string): ShapePropsStep[] {
  const sides: number = shapePropsSides(shape)
  const name: string = shapePropsNameZh(shape)
  if (sides === 0 || name === '') {
    return []
  }
  const steps: ShapePropsStep[] = [
    {
      title: '认一认',
      chip: name,
      desc: `这是${name}`,
      narration: `这是${name}，摸摸它的边和角`,
      hint: `点一下，听听它叫什么名字`,
      action: '认一认'
    },
    {
      title: '数边',
      chip: `${sides} 条边`,
      desc: sideRemark(shape, sides),
      narration: `${name}有 ${sides} 条边，${sideRemark(shape, sides)}`,
      hint: `点一下，一条一条数出它的边`,
      action: `数一数边`
    },
    {
      title: '数角',
      chip: `${sides} 个角`,
      desc: `${sides} 个角`,
      narration: `${name}有 ${sides} 个角，边和角一样多`,
      hint: `点一下，一个一个数出它的角`,
      action: `数一数角`
    }
  ]
  return steps
}

export function shapePropsStepNarrations(shape: string): string[] {
  const steps: ShapePropsStep[] = shapePropsSteps(shape)
  const narrations: string[] = []
  for (let i = 0; i < steps.length; i++) {
    narrations.push(steps[i].narration)
  }
  return narrations
}