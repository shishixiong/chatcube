/**
 * SudokuGenerator - 数独生成与校验纯逻辑层
 *
 * 与 SudokuCard 解耦: 只有生成、求解、冲突检测等无副作用函数,
 * 组件聚焦 UI 渲染, 也方便将来补 .ets 单测。
 *
 * 难度配置:
 * - 1: 4×4 (2×2 盒), 6-8 givens (共 16 格, ~50%)
 * - 2: 6×6 (2×3 盒), 18-22 givens (共 36 格, ~55%)
 * - 3: 9×9 (3×3 盒), 40-45 givens (共 81 格, ~50%) — 简单
 * - 4: 9×9 (3×3 盒), 30-34 givens (~38%) — 中等
 * - 5: 9×9 (3×3 盒), 24-28 givens (~30%) — 挑战
 */

export interface SudokuBoard {
  size: number        // 4 | 6 | 9
  boxRows: number     // 2 | 2 | 3 (子盒行数)
  boxCols: number     // 2 | 3 | 3 (子盒列数)
  difficulty: number // 1-5
  givens: number[]    // 长度 = size², 0 = 空, 1..size = 已知数字 (不可改)
  solution: number[]  // 长度 = size², 完整解 (内部用, 不暴露给卡片 UI)
  userInputs: number[] // 长度 = size², 0 = 未填, 1..size = 用户填入
}

interface DifficultyConfig {
  size: number
  boxRows: number
  boxCols: number
  givensMin: number
  givensMax: number
}

export function getDifficultyConfig(difficulty: number): DifficultyConfig {
  const d: number = Math.max(1, Math.min(5, difficulty))
  if (d === 1) {
    return { size: 4, boxRows: 2, boxCols: 2, givensMin: 6, givensMax: 8 }
  }
  if (d === 2) {
    return { size: 6, boxRows: 2, boxCols: 3, givensMin: 18, givensMax: 22 }
  }
  if (d === 3) {
    return { size: 9, boxRows: 3, boxCols: 3, givensMin: 40, givensMax: 45 }
  }
  if (d === 4) {
    return { size: 9, boxRows: 3, boxCols: 3, givensMin: 30, givensMax: 34 }
  }
  return { size: 9, boxRows: 3, boxCols: 3, givensMin: 24, givensMax: 28 }
}

export function gridSizeLabel(difficulty: number): string {
  const cfg: DifficultyConfig = getDifficultyConfig(difficulty)
  return `${cfg.size}×${cfg.size}`
}

function randomInt(min: number, max: number): number {
  if (max < min) return min
  return min + Math.floor(Math.random() * (max - min + 1))
}

function shuffledRange(n: number): number[] {
  const arr: number[] = []
  for (let i = 0; i < n; i++) {
    arr.push(i)
  }
  // Fisher-Yates
  for (let i = n - 1; i > 0; i--) {
    const j: number = Math.floor(Math.random() * (i + 1))
    const tmp: number = arr[i]
    arr[i] = arr[j]
    arr[j] = tmp
  }
  return arr
}

function rowOf(index: number, size: number): number {
  return Math.floor(index / size)
}

function colOf(index: number, size: number): number {
  return index % size
}

function boxIndex(row: number, col: number, size: number, boxRows: number, boxCols: number): number {
  const boxR: number = Math.floor(row / boxRows)
  const boxC: number = Math.floor(col / boxCols)
  return boxR * (size / boxRows) + boxC
}

/**
 * 检查在 index 处放置 value 是否合法 (不与同行/列/盒的其他格冲突)
 * 注意: 此函数扫描同 row/col/box 的其他格子, 不看 index 自身。
 */
export function isValidPlacement(board: number[], index: number, value: number,
  size: number, boxRows: number, boxCols: number): boolean {
  if (value === 0) {
    return true
  }
  const row: number = rowOf(index, size)
  const col: number = colOf(index, size)
  const box: number = boxIndex(row, col, size, boxRows, boxCols)
  for (let i = 0; i < board.length; i++) {
    if (i === index) continue
    const v: number = board[i]
    if (v === 0) continue
    const r: number = rowOf(i, size)
    const c: number = colOf(i, size)
    const b: number = boxIndex(r, c, size, boxRows, boxCols)
    if (r === row && v === value) return false
    if (c === col && v === value) return false
    if (b === box && v === value) return false
  }
  return true
}

function findEmpty(board: number[]): number {
  for (let i = 0; i < board.length; i++) {
    if (board[i] === 0) return i
  }
  return -1
}

/**
 * 回溯求解: 返回完整解 (长度 = size²) 或 null
 * 用于 (1) 生成空盘的随机完整解, (2) 唯一性校验时计数解的数量
 * randomize=true 时打乱候选数字顺序 (生成阶段); false 时按 1..size 顺序 (计数阶段)
 */
function solveBacktrack(board: number[], size: number, boxRows: number, boxCols: number,
  randomize: boolean, solutionOut: number[]): boolean {
  const idx: number = findEmpty(board)
  if (idx === -1) {
    for (let i = 0; i < board.length; i++) {
      solutionOut[i] = board[i]
    }
    return true
  }
  const candidates: number[] = []
  for (let v = 1; v <= size; v++) {
    candidates.push(v)
  }
  if (randomize) {
    const shuffled: number[] = shuffledRange(size)
    const rearranged: number[] = []
    for (let i = 0; i < size; i++) {
      rearranged.push(candidates[shuffled[i]])
    }
    for (let i = 0; i < size; i++) {
      candidates[i] = rearranged[i]
    }
  }
  for (let i = 0; i < candidates.length; i++) {
    const v: number = candidates[i]
    if (isValidPlacement(board, idx, v, size, boxRows, boxCols)) {
      board[idx] = v
      if (solveBacktrack(board, size, boxRows, boxCols, randomize, solutionOut)) {
        return true
      }
      board[idx] = 0
    }
  }
  return false
}

/**
 * 生成一个随机的完整解 (用于后续挖洞)
 * 从对角线几个互不冲突的盒开始随机填, 再回溯填满, 加速生成
 */
function generateFullSolution(size: number, boxRows: number, boxCols: number): number[] {
  const total: number = size * size
  const board: number[] = []
  for (let i = 0; i < total; i++) {
    board.push(0)
  }
  const solution: number[] = []
  for (let i = 0; i < total; i++) {
    solution.push(0)
  }
  // 先填对角线盒 (互不冲突), 加速回溯
  const boxesPerRow: number = size / boxCols
  for (let b = 0; b < boxesPerRow; b++) {
    const startRow: number = b * boxRows
    const startCol: number = b * boxCols
    const nums: number[] = shuffledRange(size)
    let cursor = 0
    for (let r = 0; r < boxRows; r++) {
      for (let c = 0; c < boxCols; c++) {
        const idx: number = (startRow + r) * size + (startCol + c)
        board[idx] = nums[cursor] + 1
        cursor++
      }
    }
  }
  // 回溯填满 (randomize=true 保证整体随机)
  if (solveBacktrack(board, size, boxRows, boxCols, true, solution)) {
    return solution
  }
  // 极罕见情况下回溯失败 (对角线盒初填冲突), 重置后纯回溯再试一次
  for (let i = 0; i < total; i++) {
    board[i] = 0
  }
  if (solveBacktrack(board, size, boxRows, boxCols, true, solution)) {
    return solution
  }
  // 兜底: 返回全零 (上游会拒绝), 实际不会到达
  return solution
}

/**
 * 计数解的数量 (最多统计到 limit, 用于唯一性校验)
 * randomize=false, 按 1..size 顺序遍历
 */
export function countSolutions(board: number[], size: number, boxRows: number, boxCols: number,
  limit: number): number {
  const work: number[] = []
  for (let i = 0; i < board.length; i++) {
    work.push(board[i])
  }
  return countSolutionsInternal(work, size, boxRows, boxCols, limit, 0)
}

function countSolutionsInternal(board: number[], size: number, boxRows: number, boxCols: number,
  limit: number, count: number): number {
  if (count >= limit) {
    return count
  }
  const idx: number = findEmpty(board)
  if (idx === -1) {
    return count + 1
  }
  for (let v = 1; v <= size; v++) {
    if (isValidPlacement(board, idx, v, size, boxRows, boxCols)) {
      board[idx] = v
      const next: number = countSolutionsInternal(board, size, boxRows, boxCols, limit, count)
      if (next >= limit) {
        board[idx] = 0
        return next
      }
      count = next
      board[idx] = 0
    }
  }
  return count
}

/**
 * 从完整解挖洞到 target givens 数, 保持唯一解
 * 使用 180° 旋转对称挖洞 (视觉对称, 同时减少挖洞成本)
 */
export function digPuzzle(solution: number[], givensTarget: number, size: number,
  boxRows: number, boxCols: number): number[] {
  const total: number = size * size
  const givens: number[] = []
  for (let i = 0; i < total; i++) {
    givens.push(solution[i])
  }
  // 待挖洞位置列表 (按 180° 旋转对称配对)
  const positions: number[] = shuffledRange(total)
  let removed = 0
  const toRemove: number = total - givensTarget
  for (let i = 0; i < positions.length; i++) {
    if (removed >= toRemove) break
    const idx: number = positions[i]
    if (givens[idx] === 0) continue
    const symIdx: number = total - 1 - idx
    const savedIdx: number = givens[idx]
    const savedSym: number = givens[symIdx]
    // 挖当前格 (以及其对称格, 如果不同)
    givens[idx] = 0
    let removedSym = false
    if (symIdx !== idx && givens[symIdx] !== 0) {
      givens[symIdx] = 0
      removedSym = true
    }
    // 唯一性校验: 解的数量必须 === 1
    const cnt: number = countSolutions(givens, size, boxRows, boxCols, 2)
    if (cnt === 1) {
      removed += removedSym ? 2 : 1
    } else {
      // 还原
      givens[idx] = savedIdx
      if (removedSym) {
        givens[symIdx] = savedSym
      }
    }
  }
  return givens
}

/**
 * 合并 givens + userInputs 为单一视图 (供冲突检测用)
 * givens 优先, 用户不能改 given 格
 */
export function mergeBoard(board: SudokuBoard): number[] {
  const merged: number[] = []
  for (let i = 0; i < board.givens.length; i++) {
    const g: number = board.givens[i]
    if (g !== 0) {
      merged.push(g)
    } else {
      merged.push(board.userInputs[i])
    }
  }
  return merged
}

/**
 * 软实时验证: 返回所有冲突格的 index 数组
 * 冲突 = 该格的值与同 row/col/box 的其他格重复 (不比对隐藏解, 只检查数独规则)
 */
export function getConflicts(board: number[], size: number, boxRows: number, boxCols: number): number[] {
  const conflicts: number[] = []
  for (let i = 0; i < board.length; i++) {
    const v: number = board[i]
    if (v === 0) continue
    if (!isValidPlacement(board, i, v, size, boxRows, boxCols)) {
      conflicts.push(i)
    }
  }
  return conflicts
}

/**
 * 是否所有格已填满且无冲突 (通关条件)
 */
export function isBoardComplete(board: number[], size: number, boxRows: number, boxCols: number): boolean {
  for (let i = 0; i < board.length; i++) {
    if (board[i] === 0) return false
  }
  return getConflicts(board, size, boxRows, boxCols).length === 0
}

/**
 * 主入口: 生成指定难度的数独盘
 * 返回 SudokuBoard (含 givens / solution / userInputs 全零数组)
 */
export function generateSudoku(difficulty: number): SudokuBoard {
  const cfg: DifficultyConfig = getDifficultyConfig(difficulty)
  const total: number = cfg.size * cfg.size
  const solution: number[] = generateFullSolution(cfg.size, cfg.boxRows, cfg.boxCols)
  const givensTarget: number = randomInt(cfg.givensMin, cfg.givensMax)
  const givens: number[] = digPuzzle(solution, givensTarget, cfg.size, cfg.boxRows, cfg.boxCols)
  const userInputs: number[] = []
  for (let i = 0; i < total; i++) {
    userInputs.push(0)
  }
  return {
    size: cfg.size,
    boxRows: cfg.boxRows,
    boxCols: cfg.boxCols,
    difficulty,
    givens,
    solution,
    userInputs
  }
}

/**
 * 从已保存的 payload (JSON) 还原棋盘到只读视图
 * 用于 isAnswered=true 时显示已通关 / 已放弃的最终状态
 */
export function reconstructBoardFromPayload(payload: string, toolCallArgs: string): SudokuBoard | null {
  try {
    const args = JSON.parse(toolCallArgs) as Record<string, Object>
    const difficulty: number = (args['difficulty'] as number) ?? 1
    const cfg: DifficultyConfig = getDifficultyConfig(difficulty)
    const total: number = cfg.size * cfg.size
    const parsed = JSON.parse(payload) as Record<string, Object>
    const givensRaw = parsed['givens']
    const userInputsRaw = parsed['user_inputs']
    const givens: number[] = []
    const userInputs: number[] = []
    if (givensRaw instanceof Array) {
      for (let i = 0; i < total; i++) {
        const v = (givensRaw as Object[])[i]
        givens.push(typeof v === 'number' ? v as number : 0)
      }
    } else {
      for (let i = 0; i < total; i++) givens.push(0)
    }
    if (userInputsRaw instanceof Array) {
      for (let i = 0; i < total; i++) {
        const v = (userInputsRaw as Object[])[i]
        userInputs.push(typeof v === 'number' ? v as number : 0)
      }
    } else {
      for (let i = 0; i < total; i++) userInputs.push(0)
    }
    return {
      size: cfg.size,
      boxRows: cfg.boxRows,
      boxCols: cfg.boxCols,
      difficulty,
      givens,
      solution: [],
      userInputs
    }
  } catch (_e) {
    return null
  }
}
