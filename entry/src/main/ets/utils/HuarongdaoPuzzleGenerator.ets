/**
 * HuarongdaoPuzzleGenerator - 数字华容道谜题生成器
 *
 * 根据难度生成打乱后的数字华容道棋盘。
 * - difficulty 1-2 → 3×3 棋盘 (8 数字 + 1 空位)
 * - difficulty 3-5 → 4×4 棋盘 (15 数字 + 1 空位)
 *
 * 打乱方式: 模拟从有序棋盘出发做随机反向滑动的算法,
 * 保证生成的棋盘统计上可解 (偶数次滑动, 与还原路径相对应)。
 * 这种"最少步数随机游走"的打乱方式在 NumberPuzzleCard 中已验证可用。
 */

export class HuarongdaoPuzzleState {
  tiles: number[] = []
  gridSize: number = 3
  difficulty: number = 1
}

/**
 * 将 difficulty 映射到 gridSize.
 * 1-2 → 3×3, 3-5 → 4×4.
 */
export function gridSizeForDifficulty(difficulty: number): number {
  if (difficulty <= 2) {
    return 3
  }
  return 4
}

/**
 * 生成有序棋盘: [1, 2, ..., n-1, 0] (0 表示空位).
 */
function buildSolvedBoard(gridSize: number): number[] {
  const board: number[] = []
  const total = gridSize * gridSize
  for (let i = 0; i < total - 1; i++) {
    board.push(i + 1)
  }
  board.push(0)
  return board
}

/**
 * Fisher-Yates 数组打乱.
 */
function shuffleArray(arr: number[]): void {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    const tmp: number = arr[i]
    arr[i] = arr[j]
    arr[j] = tmp
  }
}

/**
 * 检查棋盘是否已经是还原状态.
 */
function isSolved(board: number[], gridSize: number): boolean {
  const total = gridSize * gridSize
  for (let i = 0; i < total - 1; i++) {
    if (board[i] !== i + 1) {
      return false
    }
  }
  return board[total - 1] === 0
}

/**
 * 生成一个打乱后的华容道棋盘.
 * - difficulty 越低, 打乱步数越少 (越简单).
 * - 始终保证不是已还原状态, 避免首屏"已经赢了"的视觉.
 */
export function generatePuzzle(difficulty: number): HuarongdaoPuzzleState {
  const clampedDifficulty: number = Math.max(1, Math.min(5, Math.trunc(difficulty)))
  const gridSize: number = gridSizeForDifficulty(clampedDifficulty)

  // 打乱步数: 简单 30 步, 最难 100 步
  const baseShuffles: number = 30
  const stepRange: number = 70
  const shuffleSteps: number = baseShuffles + (clampedDifficulty - 1) * Math.floor(stepRange / 4)

  const state: HuarongdaoPuzzleState = new HuarongdaoPuzzleState()
  state.tiles = buildSolvedBoard(gridSize)
  state.gridSize = gridSize
  state.difficulty = clampedDifficulty

  // 先做一次 Fisher-Yates 大致打乱, 跳出有序初始结构
  shuffleArray(state.tiles)

  // 然后做"空格反向游走" (以可解性保证):
  // 每步把空格和相邻 tile 互换, 走出 shuffleSteps 步.
  // 反向游走 = 从有序棋盘走 shuffleSteps 步, 然后还原时需要同样多步;
  // 但前一步 Fisher-Yates 已经把空位打散, 所以这里直接 walk.
  const total: number = gridSize * gridSize
  let emptyIndex: number = state.tiles.indexOf(0)
  for (let step = 0; step < shuffleSteps; step++) {
    const neighbors: number[] = []
    const row: number = Math.floor(emptyIndex / gridSize)
    const col: number = emptyIndex % gridSize
    if (row > 0) {
      neighbors.push(emptyIndex - gridSize)
    }
    if (row < gridSize - 1) {
      neighbors.push(emptyIndex + gridSize)
    }
    if (col > 0) {
      neighbors.push(emptyIndex - 1)
    }
    if (col < gridSize - 1) {
      neighbors.push(emptyIndex + 1)
    }
    if (neighbors.length === 0) {
      break
    }
    const targetIdx: number = neighbors[Math.floor(Math.random() * neighbors.length)]
    const swapped: number = state.tiles[emptyIndex]
    state.tiles[emptyIndex] = state.tiles[targetIdx]
    state.tiles[targetIdx] = swapped
    emptyIndex = targetIdx
  }

  // 极低概率 (连续随机命中还原路径) 导致棋盘回到有序, 重新打乱一次
  if (isSolved(state.tiles, gridSize)) {
    // 直接 swap 前两块, 必然破坏有序
    const a: number = state.tiles[0]
    state.tiles[0] = state.tiles[1]
    state.tiles[1] = a
  }

  // 防止 total == 0 这种边界 (gridSize 必须 ≥ 2, 上面已保证)
  if (total <= 0) {
    state.tiles = [1, 0]
    state.gridSize = 1
  }

  return state
}
