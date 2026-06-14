/**
 * HuarongdaoPuzzleGenerator - 数字华容道谜题生成器
 *
 * 根据难度生成打乱后的数字华容道棋盘。
 * - difficulty 1 → 3×3 棋盘 (fallback, 与 NumberPuzzleCard 对齐)
 * - difficulty 2 → 2×2 棋盘 (3 数字 + 1 空位, 幼儿)
 * - difficulty 3 → 3×3 棋盘 (8 数字 + 1 空位, 简单)
 * - difficulty 4 → 4×4 棋盘 (15 数字 + 1 空位, 进阶)
 * - difficulty 5 → 5×5 棋盘 (24 数字 + 1 空位, 挑战)
 *
 * difficulty 1 默认走 3×3, 与 NumberPuzzleCard (largeSize sheet 视图) 和
 * ChatPage 内联引导文案的 difficulty→gridSize 直映射语义一致。
 *
 * 打乱方式: 从有序棋盘出发,做 N 步"空格反向游走" (每步把空格和相邻 tile
 * 互换)。每一步都是合法解谜动作,所以生成的棋盘 100% 可解 (15-puzzle 可解
 * 性定理:任何从 solved 出发经合法 move 到达的状态都 reachable→solvable)。
 *
 * 绝对不能用 Fisher-Yates 先打乱再走——Fisher-Yates 产生均匀随机排列,约
 * 50% 是不可解状态,后续 walk 只能到达同奇偶类状态,无法修复。已修复于
 * 2026-06-14,见 commit 历史。
 */

export class HuarongdaoPuzzleState {
  tiles: number[] = []
  gridSize: number = 3
  difficulty: number = 1
}

/**
 * 将 difficulty 映射到 gridSize (与 NumberPuzzleCard 档位语义一致).
 * 1 → 3×3 (fallback, 与 ChatPage.ets:4704-4705 一致);
 * 2 → 2×2 (幼儿); 3 → 3×3 (简单); 4 → 4×4 (进阶); 5 → 5×5 (挑战).
 */
export function gridSizeForDifficulty(difficulty: number): number {
  if (difficulty <= 1) {
    return 3
  }
  if (difficulty === 2) {
    return 2
  }
  if (difficulty === 3) {
    return 3
  }
  if (difficulty === 4) {
    return 4
  }
  return 5
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

  // 从有序状态出发做"空格反向游走", 每步都是合法解谜动作, 100% 可解.
  // 之前的 Fisher-Yates 起点会让 ~50% 状态不可解, 已删除.
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

  // 极低概率 (reverse walk 恰好回到有序) 下做一次额外的合法 move 打破.
  // 注意:不能简单 swap 任意两块——交换两块可能产生不可解状态 (如 2×2 的
  // [1,2,3,0] swap 前两块后变 [2,1,3,0], 验证:inv=1奇,空行1奇, XOR=0
  // 不可解)。这里用合法 move 保证结果仍可解。
  if (isSolved(state.tiles, gridSize)) {
    const row: number = Math.floor(emptyIndex / gridSize)
    const col: number = emptyIndex % gridSize
    // 优先选横向邻居 (corner 时只有 2 个邻居, edge 有 3 个, center 有 4 个)
    const neighborIdx: number = (col > 0) ? emptyIndex - 1 : emptyIndex + 1
    const swapped: number = state.tiles[emptyIndex]
    state.tiles[emptyIndex] = state.tiles[neighborIdx]
    state.tiles[neighborIdx] = swapped
  }

  // 防止 total == 0 这种边界 (gridSize 必须 ≥ 2, 上面已保证)
  if (total <= 0) {
    state.tiles = [1, 0]
    state.gridSize = 1
  }

  return state
}
