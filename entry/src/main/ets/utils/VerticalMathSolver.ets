// Vertical Math (竖式计算) solver skeleton + input validation.
// Phase A foundation: types and validation only — concrete add/sub/mul/div solvers
// arrive in later tasks (Phase B/C/D).

export enum VerticalMathOperation {
  ADD = 'add',
  SUBTRACT = 'subtract',
  MULTIPLY = 'multiply',
  DIVIDE = 'divide'
}

export interface VerticalMathHighlight {
  rowIndex: number
  columnIndex: number
  kind: 'active' | 'done' | 'carry' | 'borrow' | 'quotient'
}

export interface VerticalMathBoardRow {
  cells: string[]                 // length = columnCount; '' = blank cell
  operator?: string               // leading glyph ('+', '-', '×', '÷', '＋'), or undefined
  topMark?: string                // optional small glyph above the row ('•' for borrow, red 1 for add carry)
  topMarkColumn?: number          // which column the topMark belongs to
  topMarkRowIndex?: number        // visual row index used by carry row injection
}

export interface VerticalMathStep {
  title: string
  narration: string
  rows: VerticalMathBoardRow[]    // complete snapshot of board at this step
  highlights: VerticalMathHighlight[]
  showFinalLine?: boolean         // when true, render the second horizontal line
  showResultRow?: boolean         // when true, render the final result row
}

export interface VerticalMathSolution {
  operation: VerticalMathOperation
  operandA: number
  operandB: number
  result: number
  remainder: number
  columnCount: number             // total place-value columns in the widest row
  initialRows: VerticalMathBoardRow[]  // shown at visibleStepCount=0: A, operator, B, first line
  steps: VerticalMathStep[]       // empty array if no further work needed
  finalRow?: VerticalMathBoardRow
  errorMessage?: string
}

export class VerticalMathValidationError extends Error {}

/**
 * Validate the inputs of a vertical-math problem before the solver runs.
 *
 * Spec §2.2 / §8:
 * - A and B must be non-negative integers within 0–999 (0–999 inclusive).
 * - Subtraction requires A ≥ B (no negative results for 6–7 year-olds).
 * - Multiplication restricts B (multiplier) to 0–9 (1-digit multiplier only).
 * - Division: divisor B must be 1–9, non-zero. Dividend A may be up to 999.
 */
export function validateVerticalMathInputs(
  operation: VerticalMathOperation,
  operandA: number,
  operandB: number
): VerticalMathValidationError | null {
  if (!Number.isInteger(operandA) || operandA < 0 || operandA > 999) {
    return new VerticalMathValidationError('请输入 0–999 之间的整数')
  }
  if (!Number.isInteger(operandB) || operandB < 0 || operandB > 999) {
    return new VerticalMathValidationError('请输入 0–999 之间的整数')
  }
  if (operation === VerticalMathOperation.SUBTRACT && operandA < operandB) {
    return new VerticalMathValidationError('不够减，建议换一道题哦')
  }
  if (operation === VerticalMathOperation.MULTIPLY && operandB > 9) {
    return new VerticalMathValidationError('乘法的第二个数请输入 0–9')
  }
  if (operation === VerticalMathOperation.DIVIDE) {
    if (operandB === 0) {
      return new VerticalMathValidationError('除数不能为 0')
    }
    if (operandB > 9) {
      return new VerticalMathValidationError('除数请输入 1–9')
    }
  }
  return null
}

/** Left-pad a number to the given width with spaces, then split into single-char cells. */
function padCells(n: number, width: number): string[] {
  const raw: string = String(n)
  const cells: string[] = []
  const padLen: number = width - raw.length
  for (let i = 0; i < padLen; i++) {
    cells.push(' ')
  }
  for (let i = 0; i < raw.length; i++) {
    cells.push(raw.charAt(i))
  }
  return cells
}

/** Build a fresh row of `width` empty cells. */
function emptyCells(width: number): string[] {
  const cells: string[] = []
  for (let i = 0; i < width; i++) {
    cells.push('')
  }
  return cells
}

function cloneCells(src: string[]): string[] {
  const out: string[] = []
  for (let i = 0; i < src.length; i++) {
    out.push(src[i])
  }
  return out
}

/**
 * Solve A + B as a step-by-step vertical addition (竖式加法).
 *
 * Structure:
 * - initialRows: [A row, B row with '+' operator, line spacer]
 * - steps[0]: alignment narration ('数位对齐')
 * - steps[1..N]: one per column, right-to-left. When a column produces a carry
 *   (digitA + digitB + carryIn >= 10), the row for the NEXT column to the left
 *   carries a `topMark` of '1'. The active column is highlighted yellow ('active'),
 *   already-resolved result columns are mint ('done').
 * - final step: reveals the second line + result row.
 */
export function solveVerticalAdd(a: number, b: number): VerticalMathSolution {
  const digitsA: number = Math.max(1, String(a).length)
  const digitsB: number = Math.max(1, String(b).length)
  const total: number = a + b
  const digitsResult: number = Math.max(1, String(total).length)
  const columnCount: number = Math.max(digitsA, digitsB, digitsResult)

  const aCells: string[] = padCells(a, columnCount)
  const bCells: string[] = padCells(b, columnCount)

  const initialAlignRow: VerticalMathBoardRow = { cells: cloneCells(aCells) }
  const initialOperatorRow: VerticalMathBoardRow = { cells: cloneCells(bCells), operator: '+' }
  const initialLineRow: VerticalMathBoardRow = { cells: emptyCells(columnCount) }
  const initialRows: VerticalMathBoardRow[] = [initialAlignRow, initialOperatorRow, initialLineRow]

  const steps: VerticalMathStep[] = []

  // Step 1: alignment (no computation yet).
  const alignRowA: VerticalMathBoardRow = { cells: cloneCells(aCells) }
  const alignRowB: VerticalMathBoardRow = { cells: cloneCells(bCells), operator: '+' }
  const alignRowLine: VerticalMathBoardRow = { cells: emptyCells(columnCount) }
  const alignStep: VerticalMathStep = {
    title: '数位对齐',
    narration: '个位对个位，十位对十位。',
    rows: [alignRowA, alignRowB, alignRowLine],
    highlights: []
  }
  steps.push(alignStep)

  // Compute final result cells (padded to columnCount).
  const totalStr: string = String(total)
  const finalWidth: number = Math.max(columnCount, totalStr.length)
  const finalCells: string[] = padCells(total, finalWidth)

  // Digit-by-digit, right to left. Reveal one result digit per step and mark carries.
  const revealed: string[] = emptyCells(columnCount)
  let carryIn: number = 0
  for (let col = columnCount - 1; col >= 0; col--) {
    const dA: number = aCells[col] === ' ' ? 0 : Number(aCells[col])
    const dB: number = bCells[col] === ' ' ? 0 : Number(bCells[col])
    const sum: number = dA + dB + carryIn
    const resultDigit: number = sum % 10
    const carryOut: number = Math.floor(sum / 10)

    revealed[col] = String(resultDigit)

    const rowA: VerticalMathBoardRow = { cells: cloneCells(aCells) }
    const rowB: VerticalMathBoardRow = { cells: cloneCells(bCells), operator: '+' }
    // Carry mark sits above the operand rows, on the column to the LEFT (col - 1).
    if (carryOut > 0 && col - 1 >= 0) {
      rowA.topMark = '1'
      rowA.topMarkColumn = col - 1
      rowA.topMarkRowIndex = 0
    }
    const rowLine: VerticalMathBoardRow = { cells: emptyCells(columnCount) }
    const rowResult: VerticalMathBoardRow = { cells: cloneCells(revealed) }

    const highlights: VerticalMathHighlight[] = []
    const activeA: VerticalMathHighlight = { rowIndex: 0, columnIndex: col, kind: 'active' }
    const activeB: VerticalMathHighlight = { rowIndex: 1, columnIndex: col, kind: 'active' }
    highlights.push(activeA)
    highlights.push(activeB)
    if (carryOut > 0 && col - 1 >= 0) {
      const carryHl: VerticalMathHighlight = { rowIndex: 0, columnIndex: col - 1, kind: 'carry' }
      highlights.push(carryHl)
    }
    for (let prev = col + 1; prev < columnCount; prev++) {
      const doneHl: VerticalMathHighlight = { rowIndex: 3, columnIndex: prev, kind: 'done' }
      highlights.push(doneHl)
    }

    const narration: string = carryOut > 0
      ? `${dA} + ${dB} = ${sum}，写 ${resultDigit}，进 ${carryOut}。`
      : `${dA} + ${dB} = ${sum}，写 ${resultDigit}。`

    const step: VerticalMathStep = {
      title: `第 ${columnCount - col} 位相加`,
      narration: narration,
      rows: [rowA, rowB, rowLine, rowResult],
      highlights: highlights
    }
    steps.push(step)

    carryIn = carryOut
  }

  // Final step: full board with the answer row.
  const finalRowA: VerticalMathBoardRow = { cells: cloneCells(aCells) }
  const finalRowB: VerticalMathBoardRow = { cells: cloneCells(bCells), operator: '+' }
  const finalRowLine: VerticalMathBoardRow = { cells: emptyCells(columnCount) }
  const finalRowResult: VerticalMathBoardRow = { cells: cloneCells(finalCells) }
  const finalStep: VerticalMathStep = {
    title: '得到答案',
    narration: `答案是 ${String(total)}。`,
    rows: [finalRowA, finalRowB, finalRowLine, finalRowResult],
    highlights: [],
    showFinalLine: true,
    showResultRow: true
  }
  steps.push(finalStep)

  const finalRow: VerticalMathBoardRow = { cells: cloneCells(finalCells) }

  const solution: VerticalMathSolution = {
    operation: VerticalMathOperation.ADD,
    operandA: a,
    operandB: b,
    result: total,
    remainder: 0,
    columnCount: columnCount,
    initialRows: initialRows,
    steps: steps,
    finalRow: finalRow
  }
  return solution
}
