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
