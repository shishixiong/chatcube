/**
 * 中国地图几何纯函数（中国地图教学工具, spec 2026-10-21 §4.4）
 *
 * 数据特性：34 省 path 全部为 M/L/Z 纯多边形、Y-down、1000×870 坐标系（无 Q/C 弧段）。
 * 多子路径省份（如广东 20 环含岛屿、河北 4 环环抱北京为洞）的洞/岛语义靠
 * 跨全部环的射线穿越奇偶判定实现，与 Canvas 端 ctx.fill('evenodd') 一致。
 *
 * 算法先经 node 原型对真实数据全部钉定坐标验证通过（2026-10-21，见 plan Task 2），
 * 本文件为该原型的 ArkTS 转录。
 */

export interface MapBBox {
  minX: number
  minY: number
  maxX: number
  maxY: number
}

/**
 * 解析 M/L/Z path 为环数组；每环为 [x, y] 点数组。
 * M 开新环；Z 闭合当前环并落盘；连续 ZM… 自然拆分为多环；
 * 数字对（含 L 后隐式连排）按序配对；未知命令忽略。
 */
export function parseProvincePolygons(path: string): number[][][] {
  const rings: number[][][] = []
  let cur: number[][] | null = null
  let pendingX: number | null = null
  let i = 0
  const n = path.length
  while (i < n) {
    const ch = path.charAt(i)
    if (ch === 'M') {
      if (cur !== null && cur.length > 0) {
        rings.push(cur)
      }
      cur = []
      pendingX = null
      i++
    } else if (ch === 'Z') {
      if (cur !== null && cur.length > 0) {
        rings.push(cur)
        cur = null
      }
      pendingX = null
      i++
    } else if (ch === 'L') {
      pendingX = null
      i++
    } else if (ch === ' ' || ch === ',' || ch === '\n' || ch === '\r' || ch === '\t') {
      i++
    } else if ((ch >= '0' && ch <= '9') || ch === '-' || ch === '.') {
      // 读一个数字 token
      let j = i
      while (j < n) {
        const c = path.charAt(j)
        if ((c >= '0' && c <= '9') || c === '-' || c === '.' || c === 'e' || c === 'E') {
          j++
        } else {
          break
        }
      }
      const value = parseFloat(path.substring(i, j))
      if (isNaN(value)) {
        i = j
        continue
      }
      if (pendingX === null) {
        pendingX = value
      } else {
        if (cur === null) {
          cur = []
        }
        const pt: number[] = [pendingX, value]
        cur.push(pt)
        pendingX = null
      }
      i = j
    } else {
      // 未知命令（数据已验证只有 M/L/Z，防御性跳过）
      pendingX = null
      i++
    }
  }
  if (cur !== null && cur.length > 0) {
    rings.push(cur)
  }
  return rings
}

/**
 * 点是否落在 path 表示的省份内。
 * 射线法（ crossings 奇偶）跨全部环累计——等价于 evenodd 填充规则，
 * 洞（河北环抱北京）内点判 false、岛环内点判 true。
 * 空 path / 无数字 → false。
 */
export function pointInProvince(path: string, x: number, y: number): boolean {
  const rings = parseProvincePolygons(path)
  let inside = false
  for (const ring of rings) {
    const m = ring.length
    for (let i = 0, j = m - 1; i < m; j = i++) {
      const yi = ring[i][1]
      const yj = ring[j][1]
      if ((yi > y) !== (yj > y)) {
        const xi = ring[i][0]
        const xj = ring[j][0]
        const xCross = (xj - xi) * (y - yi) / (yj - yi) + xi
        if (x < xCross) {
          inside = !inside
        }
      }
    }
  }
  return inside
}

/**
 * 全环顶点包围盒（点击粗筛 + 聚焦环计算）。
 * 空 path 返回全零 bbox。
 */
export function provinceBBox(path: string): MapBBox {
  let minX = Infinity
  let minY = Infinity
  let maxX = -Infinity
  let maxY = -Infinity
  const rings = parseProvincePolygons(path)
  for (const ring of rings) {
    for (const pt of ring) {
      const x = pt[0]
      const y = pt[1]
      if (x < minX) {
        minX = x
      }
      if (x > maxX) {
        maxX = x
      }
      if (y < minY) {
        minY = y
      }
      if (y > maxY) {
        maxY = y
      }
    }
  }
  if (rings.length === 0 || minX === Infinity) {
    const zero: MapBBox = { minX: 0, minY: 0, maxX: 0, maxY: 0 }
    return zero
  }
  const b: MapBBox = { minX: minX, minY: minY, maxX: maxX, maxY: maxY }
  return b
}
