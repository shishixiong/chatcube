/**
 * 走迷宫 - 纯逻辑层
 *
 * 不依赖 ArkUI,可单独 hypium 单元测试
 * - generateMaze: 递归回溯 DFS 生成完美迷宫(无环、唯一解)
 * - canMove: 检测玩家能否向某方向移动
 * - movePlayer: 计算新位置
 * - getNeighborPosition: 计算某方向的相邻格坐标(仅边界校验, 不校验墙)
 * - solveMaze: BFS 求任意两格间最短路径(完美迷宫中即唯一路径), 用于放弃后揭示正确路线
 * - findDeadEnds: 找出死胡同(3 面墙)用于放收藏星
 * - getDifficultyLabel: 难度档位标签
 * - getGridSizeLabel: 网格尺寸标签
 * - collectStar: 标记某格星已被收集
 */

export interface MazeCellWalls {
  top: boolean
  right: boolean
  bottom: boolean
  left: boolean
}

export interface MazeCell {
  walls: MazeCellWalls
  hasStar: boolean
  isStart: boolean
  isGoal: boolean
}

export interface MazePosition {
  row: number
  col: number
}

export interface MazeData {
  rows: number
  cols: number
  cells: MazeCell[][]
  starsTotal: number
}

export type Direction = 'top' | 'right' | 'bottom' | 'left'

export type MazeDifficulty = 1 | 2 | 3

interface MazeNeighbor {
  pos: MazePosition
  dir: Direction
}

export interface MazeDimensions {
  rows: number
  cols: number
}

type WallName = 'top' | 'right' | 'bottom' | 'left'

// 用于种子的简单 LCG 随机数生成器(避免依赖外部 Math.random)
// 让 generateMaze 在测试时可复现
function createRng(seed: number): () => number {
  let state: number = seed === 0 ? 1 : seed
  return (): number => {
    state = (state * 1664525 + 1013904223) % 4294967296
    return state / 4294967296
  }
}

function createEmptyCell(): MazeCell {
  return {
    walls: { top: true, right: true, bottom: true, left: true },
    hasStar: false,
    isStart: false,
    isGoal: false
  }
}

function directionDelta(direction: Direction): MazePosition {
  if (direction === 'top') {
    return { row: -1, col: 0 }
  }
  if (direction === 'right') {
    return { row: 0, col: 1 }
  }
  if (direction === 'bottom') {
    return { row: 1, col: 0 }
  }
  return { row: 0, col: -1 }
}

function oppositeDirection(direction: Direction): Direction {
  if (direction === 'top') {
    return 'bottom'
  }
  if (direction === 'bottom') {
    return 'top'
  }
  if (direction === 'left') {
    return 'right'
  }
  return 'left'
}

// ArkTS 严格模式不允许对 union 类型字段做 indexed access,
// 这里抽出显式 helper,避免 walls[dir] / walls.dir 这种动态查找
function getWall(walls: MazeCellWalls, dir: WallName): boolean {
  if (dir === 'top') {
    return walls.top
  }
  if (dir === 'right') {
    return walls.right
  }
  if (dir === 'bottom') {
    return walls.bottom
  }
  return walls.left
}

function setWall(walls: MazeCellWalls, dir: WallName, value: boolean): void {
  if (dir === 'top') {
    walls.top = value
    return
  }
  if (dir === 'right') {
    walls.right = value
    return
  }
  if (dir === 'bottom') {
    walls.bottom = value
    return
  }
  walls.left = value
}

function countWalls(walls: MazeCellWalls): number {
  let count: number = 0
  if (walls.top) {
    count += 1
  }
  if (walls.right) {
    count += 1
  }
  if (walls.bottom) {
    count += 1
  }
  if (walls.left) {
    count += 1
  }
  return count
}

/**
 * 递归回溯 DFS 生成完美迷宫
 * - 每格初始化 4 面墙
 * - 从 (0,0) 起随机挑未访问邻居打通墙、压栈,直到栈空
 * - 结果:无环、任意两格唯一路径
 *
 * @param rows 行数(2-10)
 * @param cols 列数(2-10)
 * @param starCount 收藏星数量(0-3,会在死胡同里随机放置)
 * @param seed 可选种子(同种子产生同迷宫,便于测试)
 */
export function generateMaze(
  rows: number,
  cols: number,
  starCount: number = 2,
  seed: number = Math.floor(Math.random() * 4294967296) || 1
): MazeData {
  if (rows < 2 || cols < 2) {
    throw new Error(`Maze size must be at least 2x2, got ${rows}x${cols}`)
  }
  if (rows > 10 || cols > 10) {
    throw new Error(`Maze size must be at most 10x10, got ${rows}x${cols}`)
  }
  if (starCount < 0) {
    starCount = 0
  }

  const rng: () => number = createRng(seed)
  const cells: MazeCell[][] = []
  for (let r = 0; r < rows; r++) {
    const row: MazeCell[] = []
    for (let c = 0; c < cols; c++) {
      row.push(createEmptyCell())
    }
    cells.push(row)
  }

  // DFS 迷宫生成
  const visited: boolean[][] = []
  for (let r = 0; r < rows; r++) {
    visited.push(new Array<boolean>(cols).fill(false))
  }

  const stack: MazePosition[] = [{ row: 0, col: 0 }]
  visited[0][0] = true

  while (stack.length > 0) {
    const current: MazePosition = stack[stack.length - 1]
    const currentCell: MazeCell = cells[current.row][current.col]
    const neighbors: MazeNeighbor[] = []

    if (current.row > 0 && !visited[current.row - 1][current.col]) {
      neighbors.push({ pos: { row: current.row - 1, col: current.col }, dir: 'top' })
    }
    if (current.col < cols - 1 && !visited[current.row][current.col + 1]) {
      neighbors.push({ pos: { row: current.row, col: current.col + 1 }, dir: 'right' })
    }
    if (current.row < rows - 1 && !visited[current.row + 1][current.col]) {
      neighbors.push({ pos: { row: current.row + 1, col: current.col }, dir: 'bottom' })
    }
    if (current.col > 0 && !visited[current.row][current.col - 1]) {
      neighbors.push({ pos: { row: current.row, col: current.col - 1 }, dir: 'left' })
    }

    if (neighbors.length === 0) {
      stack.pop()
      continue
    }

    // 随机挑一个邻居打通
    const pickIndex: number = Math.floor(rng() * neighbors.length)
    const pick: MazeNeighbor = neighbors[pickIndex]
    const pickedCell: MazeCell = cells[pick.pos.row][pick.pos.col]

    // 打通两面墙
    setWall(currentCell.walls, pick.dir, false)
    setWall(pickedCell.walls, oppositeDirection(pick.dir), false)

    visited[pick.pos.row][pick.pos.col] = true
    stack.push(pick.pos)
  }

  // 标记起点和终点
  cells[0][0].isStart = true
  cells[rows - 1][cols - 1].isGoal = true

  // 在死胡同(3 面墙)里随机放星星,排除起点终点
  let actualStarCount: number = 0
  if (starCount > 0) {
    const deadEnds: MazePosition[] = findDeadEnds(cells)
    // 排除起点和终点
    const eligible: MazePosition[] = []
    for (let i = 0; i < deadEnds.length; i++) {
      const p: MazePosition = deadEnds[i]
      const cell: MazeCell = cells[p.row][p.col]
      if (!cell.isStart && !cell.isGoal) {
        eligible.push(p)
      }
    }

    // 洗牌(Fisher-Yates,使用 rng)
    for (let i = eligible.length - 1; i > 0; i--) {
      const j: number = Math.floor(rng() * (i + 1))
      const tmp: MazePosition = eligible[i]
      eligible[i] = eligible[j]
      eligible[j] = tmp
    }

    const limit: number = Math.min(starCount, eligible.length)
    for (let i = 0; i < limit; i++) {
      const p: MazePosition = eligible[i]
      cells[p.row][p.col].hasStar = true
      actualStarCount += 1
    }
  }

  const result: MazeData = {
    rows: rows,
    cols: cols,
    cells: cells,
    starsTotal: actualStarCount
  }
  return result
}

/**
 * 检测玩家能否从某格向 direction 方向移动
 * - 不超界
 * - 中间无墙
 */
export function canMove(cell: MazeCell, direction: Direction): boolean {
  return !getWall(cell.walls, direction)
}

/**
 * 计算玩家新位置(若可移动),否则返回 null
 */
export function movePlayer(
  cells: MazeCell[][],
  from: MazePosition,
  direction: Direction
): MazePosition | null {
  const delta: MazePosition = directionDelta(direction)
  const newRow: number = from.row + delta.row
  const newCol: number = from.col + delta.col
  if (newRow < 0 || newCol < 0) {
    return null
  }
  if (newRow >= cells.length || newCol >= cells[0].length) {
    return null
  }
  if (!canMove(cells[from.row][from.col], direction)) {
    return null
  }
  return { row: newRow, col: newCol }
}

/**
 * BFS 求从 from 到 to 的最短路径(完美迷宫中任意两格路径唯一)
 * - 返回包含起点与终点的位置数组
 * - 不可达或参数越界返回 null
 */
export function solveMaze(
  cells: MazeCell[][],
  from: MazePosition,
  to: MazePosition
): MazePosition[] | null {
  const rows: number = cells.length
  if (rows === 0) {
    return null
  }
  const cols: number = cells[0].length
  if (cols === 0) {
    return null
  }
  if (from.row < 0 || from.col < 0 || to.row < 0 || to.col < 0) {
    return null
  }
  if (from.row >= rows || from.col >= cols || to.row >= rows || to.col >= cols) {
    return null
  }

  // prev[i] = 前驱格的一维索引 (r * cols + c); -1 表示未访问, 起点指向自身
  const total: number = rows * cols
  const prev: number[] = new Array<number>(total).fill(-1)
  const fromIndex: number = from.row * cols + from.col
  const toIndex: number = to.row * cols + to.col
  prev[fromIndex] = fromIndex

  const queue: number[] = [fromIndex]
  let head: number = 0
  while (head < queue.length) {
    const current: number = queue[head]
    head += 1
    if (current === toIndex) {
      break
    }
    const r: number = Math.floor(current / cols)
    const c: number = current % cols
    const cell: MazeCell = cells[r][c]
    // 四方向显式展开(ArkTS 严格模式不允许 walls[dir] 动态查找)
    if (!cell.walls.top && r > 0 && prev[current - cols] === -1) {
      prev[current - cols] = current
      queue.push(current - cols)
    }
    if (!cell.walls.right && c < cols - 1 && prev[current + 1] === -1) {
      prev[current + 1] = current
      queue.push(current + 1)
    }
    if (!cell.walls.bottom && r < rows - 1 && prev[current + cols] === -1) {
      prev[current + cols] = current
      queue.push(current + cols)
    }
    if (!cell.walls.left && c > 0 && prev[current - 1] === -1) {
      prev[current - 1] = current
      queue.push(current - 1)
    }
  }

  if (prev[toIndex] === -1) {
    return null
  }

  // 从终点回溯到起点, 再反转
  const reversed: number[] = []
  let cursor: number = toIndex
  while (cursor !== fromIndex) {
    reversed.push(cursor)
    cursor = prev[cursor]
  }
  reversed.push(fromIndex)

  const path: MazePosition[] = []
  for (let i = reversed.length - 1; i >= 0; i--) {
    const idx: number = reversed[i]
    path.push({ row: Math.floor(idx / cols), col: idx % cols })
  }
  return path
}

/**
 * 计算从 from 朝 direction 方向的相邻格坐标
 * - 仅做边界校验, 不校验中间是否有墙(供撞墙反馈等 UI 用途)
 * - 越界返回 null
 */
export function getNeighborPosition(
  from: MazePosition,
  direction: Direction,
  rows: number,
  cols: number
): MazePosition | null {
  const delta: MazePosition = directionDelta(direction)
  const newRow: number = from.row + delta.row
  const newCol: number = from.col + delta.col
  if (newRow < 0 || newRow >= rows || newCol < 0 || newCol >= cols) {
    return null
  }
  return { row: newRow, col: newCol }
}

/**
 * 找出所有死胡同(3 面墙的格子)
 */
export function findDeadEnds(cells: MazeCell[][]): MazePosition[] {
  const result: MazePosition[] = []
  const rows: number = cells.length
  const cols: number = cells[0].length
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const walls: MazeCellWalls = cells[r][c].walls
      if (countWalls(walls) === 3) {
        result.push({ row: r, col: c })
      }
    }
  }
  return result
}

/**
 * 是否到达终点
 */
export function isAtGoal(cell: MazeCell): boolean {
  return cell.isGoal
}

/**
 * 收集星星(标记 hasStar = false),返回是否成功
 */
export function collectStar(cell: MazeCell): boolean {
  if (!cell.hasStar) {
    return false
  }
  cell.hasStar = false
  return true
}

/**
 * 难度档位 → 中文标签
 */
export function getDifficultyLabel(difficulty: MazeDifficulty): string {
  if (difficulty === 1) {
    return '简单'
  }
  if (difficulty === 2) {
    return '进阶'
  }
  return '挑战'
}

/**
 * 难度档位 → 网格尺寸标签
 */
export function getGridSizeLabel(difficulty: MazeDifficulty): string {
  if (difficulty === 1) {
    return '4×4'
  }
  if (difficulty === 2) {
    return '6×6'
  }
  return '8×8'
}

/**
 * 难度档位 → 行/列数
 */
export function getGridDimensions(difficulty: MazeDifficulty): MazeDimensions {
  if (difficulty === 1) {
    return { rows: 4, cols: 4 }
  }
  if (difficulty === 2) {
    return { rows: 6, cols: 6 }
  }
  return { rows: 8, cols: 8 }
}

/**
 * 校验两个迷宫布局是否完全一致(用于 parsePreviousResult 时校验还原)
 */
export function isMazeLayoutEqual(a: MazeData, b: MazeData): boolean {
  if (a.rows !== b.rows || a.cols !== b.cols) {
    return false
  }
  const wallNames: WallName[] = ['top', 'right', 'bottom', 'left']
  for (let r = 0; r < a.rows; r++) {
    for (let c = 0; c < a.cols; c++) {
      const ca: MazeCell = a.cells[r][c]
      const cb: MazeCell = b.cells[r][c]
      for (let i = 0; i < wallNames.length; i++) {
        const wall: WallName = wallNames[i]
        if (getWall(ca.walls, wall) !== getWall(cb.walls, wall)) {
          return false
        }
      }
      if (ca.hasStar !== cb.hasStar) {
        return false
      }
      if (ca.isStart !== cb.isStart) {
        return false
      }
      if (ca.isGoal !== cb.isGoal) {
        return false
      }
    }
  }
  return true
}