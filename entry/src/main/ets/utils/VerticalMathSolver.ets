// Vertical Math (竖式计算) solver skeleton + input validation.
// Phase A foundation: types and validation only — concrete add/sub/mul/div solvers
// arrive in later tasks (Phase B/C/D).

export enum VerticalMathOperation {
  ADD = 'add',
  SUBTRACT = 'subtract',
  MULTIPLY = 'multiply',
  DIVIDE = 'divide'
}

export class VerticalMathHighlight {
  rowIndex: number = 0
  columnIndex: number = 0
  kind: 'active' | 'done' | 'carry' | 'borrow' | 'quotient' = 'active'
}

export class VerticalMathBoardRow {
  cells: string[] = []            // length = columnCount; '' = blank cell
  operator?: string               // leading glyph ('+', '-', '×', '÷', '＋'), or undefined
  topMark?: string                // optional small glyph above the row ('•' for borrow, red 1 for add carry)
  topMarkColumn?: number          // which column the topMark belongs to
  topMarkRowIndex?: number        // visual row index used by carry row injection
  carryColumns?: number[]         // all carry columns accumulated through this snapshot
  borrowColumns?: number[]        // all borrow columns accumulated through this snapshot
}

export class VerticalMathStep {
  title: string = ''
  narration: string = ''
  rows: VerticalMathBoardRow[] = []    // complete snapshot of board at this step
  highlights: VerticalMathHighlight[] = []
  showFinalLine?: boolean         // when true, render the second horizontal line
  showResultRow?: boolean         // when true, render the final result row
}

export class VerticalMathSolution {
  operation: VerticalMathOperation = VerticalMathOperation.ADD
  operandA: number = 0
  operandB: number = 0
  result: number = 0
  remainder: number = 0
  columnCount: number = 1         // total place-value columns in the widest row
  initialRows: VerticalMathBoardRow[] = []  // shown at visibleStepCount=0: A, operator, B, first line
  steps: VerticalMathStep[] = []  // empty array if no further work needed
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

/**
 * Orchestrator: validate inputs and dispatch to one of the four operation solvers.
 *
 * On validation error: returns a VerticalMathSolution whose `errorMessage` is set
 * and whose `steps` is empty. The caller (UI) renders the error message instead
 * of the board. On valid inputs, dispatches to the operation-specific solver.
 */
export function solveVerticalMath(
  operation: VerticalMathOperation,
  operandA: number,
  operandB: number
): VerticalMathSolution {
  const validationError: VerticalMathValidationError | null = validateVerticalMathInputs(
    operation, operandA, operandB
  )
  if (validationError !== null) {
    return {
      operation,
      operandA,
      operandB,
      result: 0,
      remainder: 0,
      columnCount: 1,
      initialRows: [],
      steps: [],
      errorMessage: validationError.message
    }
  }
  switch (operation) {
    case VerticalMathOperation.ADD:
      return solveVerticalAdd(operandA, operandB)
    case VerticalMathOperation.SUBTRACT:
      return solveVerticalSubtract(operandA, operandB)
    case VerticalMathOperation.MULTIPLY:
      return solveVerticalMultiply(operandA, operandB)
    case VerticalMathOperation.DIVIDE:
      return solveVerticalDivide(operandA, operandB)
  }
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
  const carryColumns: Set<number> = new Set<number>()
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
    // Keep the legacy single mark on the generation step, while carryColumns
    // retains every carry for this and all later snapshots.
    if (carryOut > 0 && col - 1 >= 0) {
      carryColumns.add(col - 1)
      rowA.topMark = '1'
      rowA.topMarkColumn = col - 1
      rowA.topMarkRowIndex = 0
    }
    if (carryColumns.size > 0) {
      rowA.carryColumns = Array.from(carryColumns)
    }
    const rowLine: VerticalMathBoardRow = { cells: emptyCells(columnCount) }
    const rowResult: VerticalMathBoardRow = { cells: cloneCells(revealed) }

    const highlights: VerticalMathHighlight[] = []
    const activeA: VerticalMathHighlight = { rowIndex: 0, columnIndex: col, kind: 'active' }
    const activeB: VerticalMathHighlight = { rowIndex: 1, columnIndex: col, kind: 'active' }
    highlights.push(activeA)
    highlights.push(activeB)
    const activeResult: VerticalMathHighlight = { rowIndex: 3, columnIndex: col, kind: 'active' }
    highlights.push(activeResult)
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
  if (carryColumns.size > 0) {
    finalRowA.carryColumns = Array.from(carryColumns)
  }
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

/**
 * Solve A − B as a step-by-step vertical subtraction (竖式减法).
 *
 * Assumes A ≥ B (validated by validateVerticalMathInputs for SUBTRACT).
 *
 * Structure:
 * - initialRows: [A row, B row with '-' operator, line spacer]
 * - steps[0]: alignment narration ('数位对齐')
 * - steps[1..N]: one per column, right-to-left. When a column needs to borrow
 *   (digitA < digitB + carryIn), the row for the column to the LEFT (col − 1)
 *   carries a `topMark` of '•' on the operand-A row. The active column is
 *   highlighted yellow ('active'), already-resolved result columns are mint ('done').
 * - final step: reveals the second line + result row.
 *
 * Borrow convention: When a borrow is needed, walk left to find a non-zero donor
 * digit in aCellsBorrowed, decrement it by 1, and add 10 to dA. For 503 − 278
 * the borrow chain can cascade (0,0 → 5 becomes 4), which is why we walk donors
 * rather than always borrowing from col−1.
 */
export function solveVerticalSubtract(a: number, b: number): VerticalMathSolution {
  const digitsA: number = Math.max(1, String(a).length)
  const digitsB: number = Math.max(1, String(b).length)
  const columnCount: number = Math.max(digitsA, digitsB)
  const diff: number = a - b

  const aCells: string[] = padCells(a, columnCount)
  const bCells: string[] = padCells(b, columnCount)

  const initialAlignRow: VerticalMathBoardRow = { cells: cloneCells(aCells) }
  const initialOperatorRow: VerticalMathBoardRow = { cells: cloneCells(bCells), operator: '-' }
  const initialLineRow: VerticalMathBoardRow = { cells: emptyCells(columnCount) }
  const initialRows: VerticalMathBoardRow[] = [initialAlignRow, initialOperatorRow, initialLineRow]

  const steps: VerticalMathStep[] = []

  // Step 1: alignment (no computation yet).
  const alignRowA: VerticalMathBoardRow = { cells: cloneCells(aCells) }
  const alignRowB: VerticalMathBoardRow = { cells: cloneCells(bCells), operator: '-' }
  const alignRowLine: VerticalMathBoardRow = { cells: emptyCells(columnCount) }
  const alignStep: VerticalMathStep = {
    title: '数位对齐',
    narration: '个位对个位，十位对十位。',
    rows: [alignRowA, alignRowB, alignRowLine],
    highlights: []
  }
  steps.push(alignStep)

  // Result cells (padded to columnCount).
  const finalCells: string[] = padCells(diff, columnCount)

  // Digit-by-digit, right to left. aBorrowed tracks "what A looks like now"
  // after borrow decrements have been applied to the higher-order digits.
  // cascadeColumns tracks columns whose digit was turned to '9' by walking past
  // a zero during a borrow chain — these are the columns that should display
  // a borrow marker in subsequent steps so the cascade is visible column-by-column.
  // Direct borrows (donor immediately adjacent, no zeros walked) do NOT add
  // cascade markers — they only affect the trigger step.
  const aBorrowed: string[] = cloneCells(aCells)
  const resultCells: string[] = emptyCells(columnCount)
  const cascadeColumns: Set<number> = new Set<number>()
  const persistentBorrowColumns: Set<number> = new Set<number>()
  let carryIn: number = 0

  for (let col = columnCount - 1; col >= 0; col--) {
    const dA: number = aBorrowed[col] === ' ' ? 0 : Number(aBorrowed[col])
    const dB: number = bCells[col] === ' ' ? 0 : Number(bCells[col])
    let localDA: number = dA
    const borrowColumns: number[] = []
    if (localDA < dB + carryIn) {
      // Walk left to find a non-zero digit in aBorrowed to borrow from.
      // Intermediate zero digits become 9 (they lent 1 to their left neighbor),
      // and each such column (plus the donor) is recorded as a borrow point so
      // the renderer can mark the full borrow chain with a '•' marker.
      let donor: number = col - 1
      while (donor >= 0 && (aBorrowed[donor] === ' ' || Number(aBorrowed[donor]) === 0)) {
        if (aBorrowed[donor] !== ' ') {
          aBorrowed[donor] = '9'
          borrowColumns.push(donor)
          cascadeColumns.add(donor)
        }
        donor--
      }
      if (donor >= 0) {
        aBorrowed[donor] = String(Number(aBorrowed[donor]) - 1)
        localDA += 10
        borrowColumns.push(donor)
      }
    }
    if (borrowColumns.length > 0) {
      persistentBorrowColumns.add(col)
      for (let bi = 0; bi < borrowColumns.length; bi++) {
        persistentBorrowColumns.add(borrowColumns[bi])
      }
    }
    const resultDigit: number = localDA - dB - carryIn
    carryIn = 0
    resultCells[col] = String(resultDigit)

    // Left-trim leading '0's with spaces so per-step result rows match the final
    // answer row's padding (which uses padCells(diff, columnCount)). Without this,
    // e.g. 100 - 50 shows '050' in the final per-step row but ' 50' in the reveal.
    // Rule: find the rightmost revealed non-zero digit; everything strictly to
    // its left among revealed cells becomes ' '. If all revealed digits are '0'
    // (zero-answer case), trim everything except the rightmost revealed cell.
    let rightmostNonZero: number = -1
    for (let scan = columnCount - 1; scan >= col; scan--) {
      if (resultCells[scan] !== '0') {
        rightmostNonZero = scan
        break
      }
    }
    if (rightmostNonZero >= 0) {
      for (let trim = col; trim < rightmostNonZero; trim++) {
        if (resultCells[trim] === '0') {
          resultCells[trim] = ' '
        }
      }
    } else {
      // All revealed digits are '0' (zero answer) — trim all but the rightmost.
      for (let trim = col; trim < columnCount - 1; trim++) {
        resultCells[trim] = ' '
      }
    }

    // Borrow markers for THIS step:
    // - Only emitted when the borrow CASCADED (walked past at least one zero).
    //   Direct borrows (donor immediately adjacent) produce no visualization
    //   markers — the math still works, but the child just sees a normal step.
    // - If a borrow just happened with cascade, mark all chain columns.
    // - If this column was previously touched by a cascade (digit now differs
    //   from aCells due to a prior borrow chain), also show a marker here.
    const isCascaded: boolean = cascadeColumns.has(col)
    const hadCascade: boolean = borrowColumns.length > 1 ||
      (borrowColumns.length === 1 && cascadeColumns.has(borrowColumns[0]))
    const stepBorrowColumns: number[] = []
    if (hadCascade) {
      // Trigger step with cascade: mark all chain columns.
      for (let bi = 0; bi < borrowColumns.length; bi++) {
        stepBorrowColumns.push(borrowColumns[bi])
      }
    } else if (isCascaded && aBorrowed[col] !== aCells[col]) {
      // Cascade-touched column being processed in a later step.
      stepBorrowColumns.push(col)
    }

    const rowA: VerticalMathBoardRow = { cells: cloneCells(aBorrowed) }
    if (stepBorrowColumns.length > 0) {
      rowA.topMark = '•'
      rowA.topMarkColumn = stepBorrowColumns[0]
      rowA.topMarkRowIndex = 0
    }
    if (persistentBorrowColumns.size > 0) {
      rowA.borrowColumns = Array.from(persistentBorrowColumns)
    }
    const rowB: VerticalMathBoardRow = { cells: cloneCells(bCells), operator: '-' }
    const rowLine: VerticalMathBoardRow = { cells: emptyCells(columnCount) }
    const rowResult: VerticalMathBoardRow = { cells: cloneCells(resultCells) }
    const stepRows: VerticalMathBoardRow[] = [rowA, rowB, rowLine, rowResult]

    const rowAIndex: number = 0
    const rowBIndex: number = 1
    const rowResultIndex: number = 3

    const highlights: VerticalMathHighlight[] = []
    const activeA: VerticalMathHighlight = { rowIndex: rowAIndex, columnIndex: col, kind: 'active' }
    const activeB: VerticalMathHighlight = { rowIndex: rowBIndex, columnIndex: col, kind: 'active' }
    highlights.push(activeA)
    highlights.push(activeB)
    for (let bi = 0; bi < stepBorrowColumns.length; bi++) {
      const borrowHl: VerticalMathHighlight = {
        rowIndex: rowAIndex,
        columnIndex: stepBorrowColumns[bi],
        kind: 'borrow'
      }
      highlights.push(borrowHl)
    }
    const activeResult: VerticalMathHighlight = {
      rowIndex: rowResultIndex,
      columnIndex: col,
      kind: 'active'
    }
    highlights.push(activeResult)
    for (let prev = col + 1; prev < columnCount; prev++) {
      const doneHl: VerticalMathHighlight = {
        rowIndex: rowResultIndex,
        columnIndex: prev,
        kind: 'done'
      }
      highlights.push(doneHl)
    }

    const narration: string = borrowColumns.length > 0
      ? `${dB} 不够减，向左借 1，${localDA} − ${dB} = ${resultDigit}。`
      : `${localDA} − ${dB} = ${resultDigit}。`
    // Note: narration still mentions the borrow for direct borrows even though
    // no '•' marker is emitted — the math and explanation are correct, only
    // the visual highlight is suppressed for non-cascading borrows.

    const step: VerticalMathStep = {
      title: `第 ${columnCount - col} 位相减`,
      narration: narration,
      rows: stepRows,
      highlights: highlights
    }
    steps.push(step)
  }

  // Final step: full board with the answer row.
  const finalRowA: VerticalMathBoardRow = { cells: cloneCells(aCells) }
  if (persistentBorrowColumns.size > 0) {
    finalRowA.borrowColumns = Array.from(persistentBorrowColumns)
  }
  const finalRowB: VerticalMathBoardRow = { cells: cloneCells(bCells), operator: '-' }
  const finalRowLine: VerticalMathBoardRow = { cells: emptyCells(columnCount) }
  const finalRowResult: VerticalMathBoardRow = { cells: cloneCells(finalCells) }
  const finalStep: VerticalMathStep = {
    title: '得到答案',
    narration: `答案是 ${String(diff)}。`,
    rows: [finalRowA, finalRowB, finalRowLine, finalRowResult],
    highlights: [],
    showFinalLine: true,
    showResultRow: true
  }
  steps.push(finalStep)

  const finalRow: VerticalMathBoardRow = { cells: cloneCells(finalCells) }

  const solution: VerticalMathSolution = {
    operation: VerticalMathOperation.SUBTRACT,
    operandA: a,
    operandB: b,
    result: diff,
    remainder: 0,
    columnCount: columnCount,
    initialRows: initialRows,
    steps: steps,
    finalRow: finalRow
  }
  return solution
}

/** Solve A × B with one shifted partial-product row per digit of A. */
export function solveVerticalMultiply(a: number, b: number): VerticalMathSolution {
  const aStr: string = String(a)
  const bStr: string = String(b)
  const digits: number[] = []
  const products: number[] = []
  let maxProductDigits: number = 1
  for (let index = aStr.length - 1; index >= 0; index--) {
    const digit: number = Number(aStr.charAt(index))
    const product: number = digit * b
    digits.push(digit)
    products.push(product)
    maxProductDigits = Math.max(maxProductDigits, String(product).length)
  }
  const columnCount: number = aStr.length + maxProductDigits - 1
  const aCells: string[] = padCells(a, columnCount)
  const bCells: string[] = emptyCells(columnCount)
  for (let index = 0; index < bStr.length; index++) {
    bCells[columnCount - bStr.length + index] = bStr.charAt(index)
  }
  const initialRows: VerticalMathBoardRow[] = [
    { cells: cloneCells(aCells) },
    { cells: cloneCells(bCells), operator: '×' },
    { cells: emptyCells(columnCount) }
  ]
  const steps: VerticalMathStep[] = [{
    title: '数位对齐',
    narration: `${a} 和 ${b} 各就各位，准备出发。`,
    rows: [
      { cells: cloneCells(aCells) },
      { cells: cloneCells(bCells), operator: '×' },
      { cells: emptyCells(columnCount) }
    ],
    highlights: []
  }]
  const partialRows: VerticalMathBoardRow[] = []
  for (let index = 0; index < digits.length; index++) {
    const cells: string[] = emptyCells(columnCount)
    const productStr: string = String(products[index])
    const startColumn: number = columnCount - index - productStr.length
    for (let productIndex = 0; productIndex < productStr.length; productIndex++) {
      cells[startColumn + productIndex] = productStr.charAt(productIndex)
    }
    const partialRow: VerticalMathBoardRow = { cells: cells }
    if (index === digits.length - 1) {
      partialRow.operator = '＋'
    }
    partialRows.push(partialRow)
  }
  const labels: string[] = ['个', '十', '百', '千', '万']
  for (let index = 0; index < partialRows.length; index++) {
    const snapshot: VerticalMathBoardRow[] = [
      { cells: cloneCells(aCells) },
      { cells: cloneCells(bCells), operator: '×' },
      { cells: emptyCells(columnCount) }
    ]
    for (let partialIndex = 0; partialIndex <= index; partialIndex++) {
      const partialSnapshot: VerticalMathBoardRow = { cells: cloneCells(partialRows[partialIndex].cells) }
      if (partialRows[partialIndex].operator !== undefined) {
        partialSnapshot.operator = partialRows[partialIndex].operator
      }
      snapshot.push(partialSnapshot)
    }
    const multiplicandColumn: number = columnCount - 1 - index
    const currentPartialRowIndex: number = snapshot.length - 1
    const highlights: VerticalMathHighlight[] = [
      { rowIndex: 0, columnIndex: multiplicandColumn, kind: 'active' },
      { rowIndex: 1, columnIndex: columnCount - 1, kind: 'active' }
    ]
    for (let column = 0; column < columnCount; column++) {
      if (snapshot[currentPartialRowIndex].cells[column] !== '') {
        highlights.push({ rowIndex: currentPartialRowIndex, columnIndex: column, kind: 'active' })
      }
    }
    for (let partialIndex = 0; partialIndex < index; partialIndex++) {
      const previousPartialRowIndex: number = 3 + partialIndex
      for (let column = 0; column < columnCount; column++) {
        if (snapshot[previousPartialRowIndex].cells[column] !== '') {
          highlights.push({ rowIndex: previousPartialRowIndex, columnIndex: column, kind: 'done' })
        }
      }
    }
    const positionLabel: string = index < labels.length ? labels[index] : `第${index + 1}位`
    const narration: string = index === 0
      ? `${positionLabel}：${digits[index]}×${b}=${products[index]}，部分积放在十位和个位。`
      : `${positionLabel}：${digits[index]}×${b}=${products[index]}，部分积向左移动${index}格。`
    steps.push({
      title: `${positionLabel}：${digits[index]}×${b}=${products[index]}`,
      narration: narration,
      rows: snapshot,
      highlights: highlights
    })
  }
  const result: number = a * b
  const resultCells: string[] = padCells(result, columnCount)
  const finalRows: VerticalMathBoardRow[] = [
    { cells: cloneCells(aCells) },
    { cells: cloneCells(bCells), operator: '×' },
    { cells: emptyCells(columnCount) }
  ]
  for (let index = 0; index < partialRows.length; index++) {
    const finalPartialRow: VerticalMathBoardRow = { cells: cloneCells(partialRows[index].cells) }
    if (partialRows[index].operator !== undefined) {
      finalPartialRow.operator = partialRows[index].operator
    }
    finalRows.push(finalPartialRow)
  }
  finalRows.push({ cells: cloneCells(resultCells) })
  steps.push({
    title: '按位相加',
    narration: `把各位部分积按位相加，得到 ${result}。`,
    rows: finalRows,
    highlights: [],
    showFinalLine: true,
    showResultRow: true
  })
  return {
    operation: VerticalMathOperation.MULTIPLY,
    operandA: a,
    operandB: b,
    result: result,
    remainder: 0,
    columnCount: columnCount,
    initialRows: initialRows,
    steps: steps,
    finalRow: { cells: cloneCells(resultCells) }
  }
}

/**
 * Solve A ÷ B as step-by-step long division (竖式除法).
 *
 * Assumes B ∈ [1, 9] (validated by validateVerticalMathInputs for DIVIDE).
 * Uses the 厂字形 layout: dividend A on top, divisor B right-aligned in row 1
 * with a '÷' operator, first horizontal line as row 2. The quotient grows above
 * the dividend row; intermediate products and remainders appear below it.
 *
 * Algorithm per digit position (left-to-right):
 * - "看首位": Examine window (previous remainder × 10 + current digit).
 * - If window < B: emit "首位不够除" narration, NO quotient digit rendered.
 * - Else: "试商" = floor(window / B). "乘" = q × B. "减" = window − product.
 *   Append product row and remainder row below the line.
 *
 * Special cases:
 * - A = 0: quotient is 0, remainder is 0, single digit column.
 */
export function solveVerticalDivide(a: number, b: number): VerticalMathSolution {
  // Special case: 0 ÷ B = 0. Per spec, this should NOT narrate "首位不够除";
  // 0 divided by anything nonzero is trivially 0, not "the first digit can't be divided".
  // Produces a clean 2-step solution (alignment + final) with the quotient shown as '0'.
  if (a === 0) {
    const columnCount: number = 1
    const aCells: string[] = ['0']
    const bRowCells: string[] = emptyCells(columnCount)
    bRowCells[columnCount - 1] = String(b)

    const initialAlignRow: VerticalMathBoardRow = { cells: cloneCells(aCells) }
    const initialOperatorRow: VerticalMathBoardRow = { cells: cloneCells(bRowCells), operator: '÷' }
    const initialLineRow: VerticalMathBoardRow = { cells: emptyCells(columnCount) }
    const initialRows: VerticalMathBoardRow[] = [initialAlignRow, initialOperatorRow, initialLineRow]

    const steps: VerticalMathStep[] = []

    // Step 1: alignment (no computation yet).
    const alignRowA: VerticalMathBoardRow = { cells: cloneCells(aCells) }
    const alignRowB: VerticalMathBoardRow = { cells: cloneCells(bRowCells), operator: '÷' }
    const alignRowLine: VerticalMathBoardRow = { cells: emptyCells(columnCount) }
    const alignStep: VerticalMathStep = {
      title: '数位对齐',
      narration: '用除数去除被除数，从最高位开始。',
      rows: [alignRowA, alignRowB, alignRowLine],
      highlights: []
    }
    steps.push(alignStep)

    // Final step: reveal the result '0'.
    const finalRowCells: string[] = ['0']
    const finalStep: VerticalMathStep = {
      title: '得到答案',
      narration: `0 ÷ ${b} = 0。`,
      rows: [
        { cells: cloneCells(aCells) },
        { cells: cloneCells(bRowCells), operator: '÷' },
        { cells: emptyCells(columnCount) },
        { cells: cloneCells(finalRowCells) }
      ],
      highlights: [],
      showFinalLine: true,
      showResultRow: true
    }
    steps.push(finalStep)

    return {
      operation: VerticalMathOperation.DIVIDE,
      operandA: a,
      operandB: b,
      result: 0,
      remainder: 0,
      columnCount: columnCount,
      initialRows: initialRows,
      steps: steps,
      finalRow: { cells: cloneCells(finalRowCells) }
    }
  }

  const aStr: string = String(a)
  const digitsA: number = aStr.length
  const columnCount: number = digitsA
  const aCells: string[] = aStr.split('')
  const bRowCells: string[] = emptyCells(columnCount)
  bRowCells[columnCount - 1] = String(b)

  const initialAlignRow: VerticalMathBoardRow = { cells: cloneCells(aCells) }
  const initialOperatorRow: VerticalMathBoardRow = { cells: cloneCells(bRowCells), operator: '÷' }
  const initialLineRow: VerticalMathBoardRow = { cells: emptyCells(columnCount) }
  const initialRows: VerticalMathBoardRow[] = [initialAlignRow, initialOperatorRow, initialLineRow]

  const steps: VerticalMathStep[] = []

  // Step 0: alignment
  const alignRowA: VerticalMathBoardRow = { cells: cloneCells(aCells) }
  const alignRowB: VerticalMathBoardRow = { cells: cloneCells(bRowCells), operator: '÷' }
  const alignRowLine: VerticalMathBoardRow = { cells: emptyCells(columnCount) }
  const alignStep: VerticalMathStep = {
    title: '数位对齐',
    narration: '用除数去除被除数，从最高位开始。',
    rows: [alignRowA, alignRowB, alignRowLine],
    highlights: []
  }
  steps.push(alignStep)

  // Simulate long division left-to-right
  let remainder: number = 0
  const quotientDigits: string[] = emptyCells(columnCount)
  let anyQuotientDigit: boolean = false

  for (let i = 0; i < columnCount; i++) {
    const digit: number = Number(aCells[i])
    const window: number = remainder * 10 + digit
    if (window < b) {
      // "首位不够除，先看下一位" — render narration only
      const notEnoughRows: VerticalMathBoardRow[] = [
        { cells: cloneCells(aCells) },
        { cells: cloneCells(bRowCells), operator: '÷' },
        { cells: emptyCells(columnCount) }
      ]
      steps.push({
        title: `第 ${i + 1} 位：不够除`,
        narration: '首位不够除，先看下一位。',
        rows: notEnoughRows,
        highlights: [
          { rowIndex: 0, columnIndex: i, kind: 'active' },
          { rowIndex: 1, columnIndex: columnCount - 1, kind: 'active' }
        ]
      })
      remainder = window
      continue
    }
    const q: number = Math.floor(window / b)
    const prod: number = q * b
    remainder = window - prod
    anyQuotientDigit = true
    quotientDigits[i] = String(q)

    const quotientRow: VerticalMathBoardRow = { cells: cloneCells(quotientDigits) }
    const productCells: string[] = emptyCells(columnCount)
    const prodStr: string = String(prod)
    for (let k = 0; k < prodStr.length; k++) {
      productCells[i - prodStr.length + 1 + k] = prodStr.charAt(k)
    }
    const remainderCells: string[] = emptyCells(columnCount)
    if (remainder > 0) {
      const remStr: string = String(remainder)
      for (let k = 0; k < remStr.length; k++) {
        remainderCells[i - remStr.length + 1 + k] = remStr.charAt(k)
      }
    } else {
      remainderCells[i] = '0'
    }

    const snap: VerticalMathBoardRow[] = [
      { cells: cloneCells(aCells) },
      { cells: cloneCells(bRowCells), operator: '÷' },
      { cells: emptyCells(columnCount) },
      quotientRow,
      { cells: productCells },
      { cells: remainderCells }
    ]
    const highlights: VerticalMathHighlight[] = [
      { rowIndex: 0, columnIndex: i, kind: 'active' },
      { rowIndex: 1, columnIndex: columnCount - 1, kind: 'active' },
      { rowIndex: 3, columnIndex: i, kind: 'quotient' }
    ]
    steps.push({
      title: `第 ${i + 1} 位：试商 ${q}`,
      narration: `${window} ÷ ${b} = ${q} …… ${remainder}。`,
      rows: snap,
      highlights: highlights
    })
  }

  const finalQuotient: string = anyQuotientDigit
    ? quotientDigits.join('').replace(/^0+/, '') || '0'
    : '0'

  // For cases where no quotient digit was emitted (e.g. 3 ÷ 7), ensure finalRow
  // displays a visible '0' at the rightmost column so the renderer shows the
  // quotient digit rather than a blank cell. The result is still 0.
  let finalRowCells: string[]
  if (anyQuotientDigit) {
    finalRowCells = cloneCells(quotientDigits)
  } else {
    finalRowCells = emptyCells(columnCount)
    finalRowCells[columnCount - 1] = '0'
  }

  const finalStep: VerticalMathStep = {
    title: '得到答案',
    narration: remainder === 0
      ? `${a} ÷ ${b} = ${finalQuotient}。`
      : `${a} ÷ ${b} = ${finalQuotient}，余数 ${remainder}。`,
    rows: [
      { cells: cloneCells(aCells) },
      { cells: cloneCells(bRowCells), operator: '÷' },
      { cells: emptyCells(columnCount) },
      { cells: cloneCells(finalRowCells) }
    ],
    highlights: [],
    showFinalLine: true,
    showResultRow: true
  }
  steps.push(finalStep)

  const finalRow: VerticalMathBoardRow = { cells: cloneCells(finalRowCells) }

  return {
    operation: VerticalMathOperation.DIVIDE,
    operandA: a,
    operandB: b,
    result: Number(finalQuotient),
    remainder: remainder,
    columnCount: columnCount,
    initialRows: initialRows,
    steps: steps,
    finalRow: finalRow
  }
}
