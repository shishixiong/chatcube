// Vertical Math (竖式计算) solver.
// v2 黑板重设计（docs/vertical_math_refine.html）：
// - 行模型支持标记行（进位 1 / 借位 -1）、划线列、厂字形除法左区与横竖规则线
// - 乘法限一位数乘数：被乘数每位 × 乘数 = 一个部分积行（蓝，按位左移），末步按位相加
// - 除法限一位数除数，采用课本「厂」字形布局：商在横线上方、除数在左、逐步乘积/差分色
// - 校验：乘数须 0–9；除数须 1–9；加减操作数 0–99999（减法 a ≥ b）

export enum VerticalMathOperation {
  ADD = 'add',
  SUBTRACT = 'subtract',
  MULTIPLY = 'multiply',
  DIVIDE = 'divide'
}

export class VerticalMathHighlight {
  rowIndex: number = 0
  columnIndex: number = 0
  // 'product' = 部分积/除法逐步乘积（蓝）；'final' = 最终答案/余数（绿）
  kind: 'active' | 'done' | 'carry' | 'borrow' | 'quotient' | 'product' | 'final' = 'active'
}

export class VerticalMathBoardRow {
  cells: string[] = []            // length = columnCount; '' = blank cell
  operator?: string               // leading glyph ('+', '-', '×'), or undefined
  markRow?: boolean               // 小号黄色标记行（加法进位 1 / 减法借位调整数）
  crossedColumns?: number[]       // 划线列（减法借位时的原数字）
  leftCells?: string[]            // 厂字形除法左区（除数），窄列；其余行为空占位
  ruleUnder?: boolean             // 本行下方画横线（商顶杠 / 算前横线 / 第二条横线）
  barRight?: boolean              // 左区与主区之间画竖线（除法「厂」竖笔画）
}

export class VerticalMathStep {
  title: string = ''
  narration: string = ''
  placeLabel: string = ''
  actionLabel: string = ''
  rows: VerticalMathBoardRow[] = []    // complete snapshot of board at this step
  highlights: VerticalMathHighlight[] = []
}

export class VerticalMathSolution {
  operation: VerticalMathOperation = VerticalMathOperation.ADD
  operandA: number = 0
  operandB: number = 0
  result: number = 0
  remainder: number = 0
  columnCount: number = 1         // total place-value columns in the widest row
  initialRows: VerticalMathBoardRow[] = []  // shown at visibleStepCount=0
  steps: VerticalMathStep[] = []  // empty array if no further work needed
  finalRow?: VerticalMathBoardRow
  errorMessage?: string
}

export class VerticalMathValidationError extends Error {}

/**
 * Validate the inputs of a vertical-math problem before the solver runs.
 *
 * v2 约束（2026-10-04 收窄）：
 * - A and B must be non-negative integers within 0–99999.
 * - Subtraction requires A ≥ B (no negative results for 6–7 year-olds).
 * - Multiplication: multiplier B limited to a single digit (0–9) —
 *   板书按"被乘数每位 × 乘数 = 部分积"多步展开（参考设计稿「每一位相乘」版式）。
 * - Division: divisor B limited to a single digit (1–9) —
 *   厂字形长除多步版式按一位数除数设计。
 */
export function validateVerticalMathInputs(
  operation: VerticalMathOperation,
  operandA: number,
  operandB: number
): VerticalMathValidationError | null {
  if (!Number.isInteger(operandA) || operandA < 0 || operandA > 99999) {
    return new VerticalMathValidationError('请输入 0 到 99999 的数字')
  }
  if (!Number.isInteger(operandB) || operandB < 0 || operandB > 99999) {
    return new VerticalMathValidationError('请输入 0 到 99999 的数字')
  }
  if (operation === VerticalMathOperation.SUBTRACT && operandA < operandB) {
    return new VerticalMathValidationError('不够减，建议换一道题哦')
  }
  if (operation === VerticalMathOperation.MULTIPLY && operandB > 9) {
    return new VerticalMathValidationError('乘数请填一位数（0–9）')
  }
  if (operation === VerticalMathOperation.DIVIDE) {
    if (operandB === 0) {
      return new VerticalMathValidationError('0 不能做除数，换一个数字吧')
    }
    if (operandB > 9) {
      return new VerticalMathValidationError('除数请填一位数（1–9）')
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
 * Place `value` so its last digit lands on `endCol`, right-aligned
 * (设计稿 placeEndingAt：部分积/乘积随位次左移).
 */
function placeEndingAt(value: string, endCol: number, cols: number): string[] {
  const arr: string[] = emptyCells(cols)
  const ds: string = String(value)
  const start: number = endCol - ds.length + 1
  for (let k = 0; k < ds.length; k++) {
    const idx: number = start + k
    if (idx >= 0 && idx < cols) {
      arr[idx] = ds.charAt(k)
    }
  }
  return arr
}

const PLACE_VALUE_LABELS: string[] = ['个位', '十位', '百位', '千位', '万位']

function getPlaceValueLabel(columnCount: number, column: number): string {
  const placeIndex: number = columnCount - 1 - column
  if (placeIndex >= 0 && placeIndex < PLACE_VALUE_LABELS.length) {
    return PLACE_VALUE_LABELS[placeIndex]
  }
  return `第 ${placeIndex + 1} 位`
}

/**
 * Solve A + B as a step-by-step vertical addition (竖式加法).
 *
 * Structure (v2):
 * - initialRows: [进位标记行(空), A row, B row with '+', 横线行]
 * - steps[0..N-1]: one per column, right-to-left. When a column produces a carry,
 *   the column to the LEFT gets a small yellow '1' in the mark row (设计稿 mark 行),
 *   accumulated and persistent through later snapshots.
 * - final step: full board + celebrate.
 */
export function solveVerticalAdd(a: number, b: number): VerticalMathSolution {
  const digitsA: number = Math.max(1, String(a).length)
  const digitsB: number = Math.max(1, String(b).length)
  const total: number = a + b
  const digitsResult: number = Math.max(1, String(total).length)
  const columnCount: number = Math.max(digitsA, digitsB, digitsResult)

  const aCells: string[] = padCells(a, columnCount)
  const bCells: string[] = padCells(b, columnCount)

  const initialRows: VerticalMathBoardRow[] = [
    { cells: cloneCells(aCells) },
    { cells: cloneCells(bCells), operator: '+' },
    { cells: emptyCells(columnCount), markRow: true },
    { cells: emptyCells(columnCount), ruleUnder: true }
  ]

  const steps: VerticalMathStep[] = []
  const carryMarkColumns: Set<number> = new Set<number>()

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
    if (carryOut > 0 && col - 1 >= 0) {
      carryMarkColumns.add(col - 1)
    }

    const markCells: string[] = emptyCells(columnCount)
    carryMarkColumns.forEach((marked: number) => {
      markCells[marked] = '1'
    })

    const rowA: VerticalMathBoardRow = { cells: cloneCells(aCells) }
    const rowB: VerticalMathBoardRow = { cells: cloneCells(bCells), operator: '+' }
    const rowLine: VerticalMathBoardRow = { cells: emptyCells(columnCount), ruleUnder: true }
    const rowResult: VerticalMathBoardRow = { cells: cloneCells(revealed) }

    const highlights: VerticalMathHighlight[] = []
    highlights.push({ rowIndex: 0, columnIndex: col, kind: 'active' })
    highlights.push({ rowIndex: 1, columnIndex: col, kind: 'active' })
    highlights.push({ rowIndex: 4, columnIndex: col, kind: 'active' })
    if (carryIn > 0) {
      // 本位有进位参与计算：高亮上一列送来的进位 "1" 标记
      highlights.push({ rowIndex: 2, columnIndex: col, kind: 'active' })
    }
    for (let prev = col + 1; prev < columnCount; prev++) {
      highlights.push({ rowIndex: 4, columnIndex: prev, kind: 'done' })
    }

    const placeLabel: string = getPlaceValueLabel(columnCount, col)

    const formula: string = carryIn > 0
      ? `${dA} ＋ ${dB} ＋ ${carryIn} ＝ ${sum}`
      : `${dA} ＋ ${dB} ＝ ${sum}`
    const tail: string = carryOut > 0
      ? `${placeLabel}写 ${resultDigit}，把 ${carryOut} 送到${getPlaceValueLabel(columnCount, col - 1)}。`
      : `${placeLabel}写 ${resultDigit}，没有新进位。`
    const narration: string = `${formula}，${tail}`

    const step: VerticalMathStep = new VerticalMathStep()
    step.title = `${placeLabel}相加`
    step.narration = narration
    step.placeLabel = placeLabel
    step.actionLabel = `算${placeLabel}`
    step.rows = [
      rowA,
      rowB,
      { cells: markCells, markRow: true },
      rowLine,
      rowResult
    ]
    step.highlights = highlights
    steps.push(step)

    carryIn = carryOut
  }

  // Final step: full board with the answer row.
  const finalMarkCells: string[] = emptyCells(columnCount)
  carryMarkColumns.forEach((marked: number) => {
    finalMarkCells[marked] = '1'
  })
  const finalStep: VerticalMathStep = new VerticalMathStep()
  finalStep.title = '得到答案'
  finalStep.narration = `答案是 ${String(total)}。`
  finalStep.placeLabel = '完成'
  finalStep.actionLabel = '完成竖式'
  finalStep.rows = [
    { cells: cloneCells(aCells) },
    { cells: cloneCells(bCells), operator: '+' },
    { cells: finalMarkCells, markRow: true },
    { cells: emptyCells(columnCount), ruleUnder: true },
    { cells: cloneCells(finalCells) }
  ]
  finalStep.highlights = []
  steps.push(finalStep)

  const solution: VerticalMathSolution = {
    operation: VerticalMathOperation.ADD,
    operandA: a,
    operandB: b,
    result: total,
    remainder: 0,
    columnCount: columnCount,
    initialRows: initialRows,
    steps: steps,
    finalRow: { cells: cloneCells(finalCells) }
  }
  return solution
}

/**
 * Solve A − B as a step-by-step vertical subtraction (竖式减法).
 *
 * Assumes A ≥ B (validated by validateVerticalMathInputs for SUBTRACT).
 *
 * v2 借位可视化（与加法同款标记行布局）：
 * - 标记行在操作数下方、横线上方；被借位的列（donor）标小号 "-1"，
 *   连续借位跨 0 的中间列标调整后的数（0→9）
 * - 操作数行保持原样，不再划线；+10 语义由叙述（"从十位借 1，13 − 8"）承载
 * - 借位发生的那一步高亮 "-1" 标记
 */
export function solveVerticalSubtract(a: number, b: number): VerticalMathSolution {
  const digitsA: number = Math.max(1, String(a).length)
  const digitsB: number = Math.max(1, String(b).length)
  const columnCount: number = Math.max(digitsA, digitsB)
  const diff: number = a - b

  const aCells: string[] = padCells(a, columnCount)
  const bCells: string[] = padCells(b, columnCount)

  const initialRows: VerticalMathBoardRow[] = [
    { cells: cloneCells(aCells) },
    { cells: cloneCells(bCells), operator: '-' },
    { cells: emptyCells(columnCount), markRow: true },
    { cells: emptyCells(columnCount), ruleUnder: true }
  ]

  const steps: VerticalMathStep[] = []
  const finalCells: string[] = padCells(diff, columnCount)

  // aBorrowed tracks "what A looks like now" after borrow decrements — internal
  // math state only; the board shows original digits plus "-1" borrow marks.
  const aBorrowed: string[] = cloneCells(aCells)
  const donorColumns: Set<number> = new Set<number>()   // 直接被借走 1 的列 → 标 "-1"
  const chainColumns: Set<number> = new Set<number>()   // 跨 0 连续借位的中间列（0→9）→ 标调整值
  const resultCells: string[] = emptyCells(columnCount)

  for (let col = columnCount - 1; col >= 0; col--) {
    const originalDA: number = aCells[col] === ' ' ? 0 : Number(aCells[col])
    const wasLent: boolean = aBorrowed[col] !== aCells[col]
    const dA: number = aBorrowed[col] === ' ' ? 0 : Number(aBorrowed[col])
    const dB: number = bCells[col] === ' ' ? 0 : Number(bCells[col])
    let localDA: number = dA
    let donorColumn: number = -1
    if (localDA < dB) {
      let donor: number = col - 1
      while (donor >= 0 && (aBorrowed[donor] === ' ' || Number(aBorrowed[donor]) === 0)) {
        if (aBorrowed[donor] !== ' ') {
          aBorrowed[donor] = '9'
          chainColumns.add(donor)
        }
        donor--
      }
      if (donor >= 0) {
        donorColumn = donor
        aBorrowed[donor] = String(Number(aBorrowed[donor]) - 1)
        donorColumns.add(donor)
        localDA += 10
      }
    }
    const resultDigit: number = localDA - dB
    resultCells[col] = String(resultDigit)

    // Left-trim leading '0's with spaces so per-step result rows match the final
    // answer row's padding (which uses padCells(diff, columnCount)).
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
      for (let trim = col; trim < columnCount - 1; trim++) {
        resultCells[trim] = ' '
      }
    }

    // 标记行：被借走 1 的列标小号 "-1"；跨 0 连续借位的中间列标调整后的数（0→9）。
    // 当前被借位的列（+10 语义）不显示标记，由叙述承载（"13 − 8"）。
    const markCells: string[] = emptyCells(columnCount)
    donorColumns.forEach((donor: number) => {
      markCells[donor] = '-1'
    })
    chainColumns.forEach((chained: number) => {
      markCells[chained] = aBorrowed[chained]
    })

    const rowA: VerticalMathBoardRow = { cells: cloneCells(aCells) }
    const rowB: VerticalMathBoardRow = { cells: cloneCells(bCells), operator: '-' }
    const rowLine: VerticalMathBoardRow = { cells: emptyCells(columnCount), ruleUnder: true }
    const rowResult: VerticalMathBoardRow = { cells: cloneCells(resultCells) }

    const highlights: VerticalMathHighlight[] = []
    highlights.push({ rowIndex: 0, columnIndex: col, kind: 'active' })
    highlights.push({ rowIndex: 1, columnIndex: col, kind: 'active' })
    highlights.push({ rowIndex: 4, columnIndex: col, kind: 'active' })
    if (donorColumn >= 0) {
      // 本轮发生借位：高亮刚落下的 "-1" 标记（参与当前位计算）
      highlights.push({ rowIndex: 2, columnIndex: donorColumn, kind: 'active' })
    }
    for (let prev = col + 1; prev < columnCount; prev++) {
      highlights.push({ rowIndex: 4, columnIndex: prev, kind: 'done' })
    }

    const placeLabel: string = getPlaceValueLabel(columnCount, col)

    let narration: string
    if (donorColumn >= 0 && wasLent) {
      narration = `${originalDA} − 1 ＝ ${dA}，不够减 ${dB}，` +
        `从${getPlaceValueLabel(columnCount, donorColumn)}借 1，${localDA} − ${dB} ＝ ${resultDigit}。`
    } else if (donorColumn >= 0) {
      narration = `${dA} 不够减 ${dB}，` +
        `从${getPlaceValueLabel(columnCount, donorColumn)}借 1，${localDA} − ${dB} ＝ ${resultDigit}。`
    } else if (wasLent) {
      narration = `${originalDA} − 1 − ${dB} ＝ ${resultDigit}（先减去借走的 1）。`
    } else {
      narration = `${localDA} − ${dB} ＝ ${resultDigit}，没有借位。`
    }

    const step: VerticalMathStep = new VerticalMathStep()
    step.title = `第 ${columnCount - col} 位相减`
    step.narration = narration
    step.placeLabel = placeLabel
    step.actionLabel = `算${placeLabel}`
    step.rows = [
      rowA,
      rowB,
      { cells: markCells, markRow: true },
      rowLine,
      rowResult
    ]
    step.highlights = highlights
    steps.push(step)
  }

  // Final step: full board with the answer row and accumulated borrow marks.
  const finalMarkCells: string[] = emptyCells(columnCount)
  donorColumns.forEach((donor: number) => {
    finalMarkCells[donor] = '-1'
  })
  chainColumns.forEach((chained: number) => {
    finalMarkCells[chained] = aBorrowed[chained]
  })
  const finalStep: VerticalMathStep = new VerticalMathStep()
  finalStep.title = '得到答案'
  finalStep.narration = `答案是 ${String(diff)}。`
  finalStep.placeLabel = '完成'
  finalStep.actionLabel = '完成竖式'
  finalStep.rows = [
    { cells: cloneCells(aCells) },
    { cells: cloneCells(bCells), operator: '-' },
    { cells: finalMarkCells, markRow: true },
    { cells: emptyCells(columnCount), ruleUnder: true },
    { cells: cloneCells(finalCells) }
  ]
  finalStep.highlights = []
  steps.push(finalStep)

  const solution: VerticalMathSolution = {
    operation: VerticalMathOperation.SUBTRACT,
    operandA: a,
    operandB: b,
    result: diff,
    remainder: 0,
    columnCount: columnCount,
    initialRows: initialRows,
    steps: steps,
    finalRow: { cells: cloneCells(finalCells) }
  }
  return solution
}

/**
 * Solve A × B (竖式乘法, v2「每一位相乘」多步实现).
 *
 * 乘数 B 限一位数（validateVerticalMathInputs 保证 B ≤ 9）。板书对齐设计稿
 * 「每一位相乘」版式：被乘数每一位 × 乘数各得一个部分积行（蓝，末位对齐本位、
 * 随位次左移），最后一个部分积行带 '＋'，最终步第二条横线 + 按位相加结果。
 * 例如 988×6：部分积 48（个位）、48（十位）、54（百位）→ 按位相加得 5928。
 */
export function solveVerticalMultiply(a: number, b: number): VerticalMathSolution {
  const aStr: string = String(a)
  const digitsA: number = aStr.length
  const columnCount: number = digitsA + 1

  const aCells: string[] = padCells(a, columnCount)
  const bCells: string[] = emptyCells(columnCount)
  bCells[columnCount - 1] = String(b)

  const initialRows: VerticalMathBoardRow[] = [
    { cells: cloneCells(aCells) },
    { cells: cloneCells(bCells), operator: '×' },
    { cells: emptyCells(columnCount), ruleUnder: true }
  ]

  const result: number = a * b
  const resultCells: string[] = padCells(result, columnCount)

  // 被乘数每位 × 乘数 = 部分积（末位对齐本位，向左依次移位；一位被乘数即单部分积）
  const partialRows: VerticalMathBoardRow[] = []
  const partialValues: string[] = []
  const placeNames: string[] = ['个位', '十位', '百位', '千位', '万位']
  for (let j = 0; j < digitsA; j++) {
    const d: number = Number(aStr.charAt(digitsA - 1 - j))
    const prod: number = d * b
    partialValues.push(String(prod))
    partialRows.push({ cells: placeEndingAt(String(prod), columnCount - 1 - j, columnCount) })
  }

  const steps: VerticalMathStep[] = []

  for (let index = 0; index < partialRows.length; index++) {
    const snapshot: VerticalMathBoardRow[] = [
      { cells: cloneCells(aCells) },
      { cells: cloneCells(bCells), operator: '×' },
      { cells: emptyCells(columnCount), ruleUnder: true }
    ]
    for (let partialIndex = 0; partialIndex <= index; partialIndex++) {
      const partialSnapshot: VerticalMathBoardRow = { cells: cloneCells(partialRows[partialIndex].cells) }
      if (partialIndex === partialRows.length - 1 && partialRows.length > 1) {
        partialSnapshot.operator = '＋'
      }
      snapshot.push(partialSnapshot)
    }
    // 当前步 + 已露出的先前部分积行全部保持蓝色 product 高亮
    const highlights: VerticalMathHighlight[] = []
    for (let partialIndex = 0; partialIndex <= index; partialIndex++) {
      const partialRowIndex: number = 3 + partialIndex
      for (let column = 0; column < columnCount; column++) {
        const cell: string = snapshot[partialRowIndex].cells[column]
        if (cell !== '' && cell !== ' ') {
          highlights.push({ rowIndex: partialRowIndex, columnIndex: column, kind: 'product' })
        }
      }
    }

    const d: number = Number(aStr.charAt(digitsA - 1 - index))
    const placeName: string = index < placeNames.length ? placeNames[index] : `第${index + 1}位`
    const shiftText: string = index === 0
      ? `从${placeName}写起`
      : `从${placeName}写起（向左移 ${index} 格）`
    const narration: string = `用${placeName}上的 ${d} 去乘：${d}×${b}＝${partialValues[index]}，${shiftText}。`

    const mulStep: VerticalMathStep = new VerticalMathStep()
    mulStep.title = `${placeName}：${d}×${b}＝${partialValues[index]}`
    mulStep.narration = narration
    mulStep.placeLabel = placeName
    mulStep.actionLabel = `算${placeName}`
    mulStep.rows = snapshot
    mulStep.highlights = highlights
    steps.push(mulStep)
  }

  // 最终步：第二条横线 + 按位相加结果
  const finalRows: VerticalMathBoardRow[] = [
    { cells: cloneCells(aCells) },
    { cells: cloneCells(bCells), operator: '×' },
    { cells: emptyCells(columnCount), ruleUnder: true }
  ]
  for (let index = 0; index < partialRows.length; index++) {
    const finalPartialRow: VerticalMathBoardRow = { cells: cloneCells(partialRows[index].cells) }
    if (index === partialRows.length - 1 && partialRows.length > 1) {
      finalPartialRow.operator = '＋'
    }
    finalRows.push(finalPartialRow)
  }
  finalRows.push({ cells: emptyCells(columnCount), ruleUnder: true })
  finalRows.push({ cells: cloneCells(resultCells) })

  const mulFinalStep: VerticalMathStep = new VerticalMathStep()
  mulFinalStep.title = '按位相加'
  mulFinalStep.narration = partialRows.length > 1
    ? `把 ${partialRows.length} 个部分积按位相加：${partialValues.join('＋')}，得到 ${result}。`
    : `答案是 ${result}。`
  mulFinalStep.placeLabel = '完成'
  mulFinalStep.actionLabel = '完成竖式'
  mulFinalStep.rows = finalRows
  mulFinalStep.highlights = []
  steps.push(mulFinalStep)

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

/** 厂字形除法行公共骨架：左区（除数位）+ 竖线 + 主区格子。 */
function divisionRow(cells: string[], leftCells: string[], ruleUnder: boolean): VerticalMathBoardRow {
  const row: VerticalMathBoardRow = { cells: cells }
  row.leftCells = leftCells
  row.barRight = true
  if (ruleUnder) {
    row.ruleUnder = true
  }
  return row
}

function emptyDivisionLeftCells(divisorLength: number): string[] {
  const cells: string[] = []
  for (let i = 0; i < divisorLength; i++) {
    cells.push('')
  }
  return cells
}

/** 左区末位放除数本身（厂字形除数行用）。 */
function divisionLeftWithDivisor(b: number, divisorLength: number): string[] {
  const left: string[] = emptyDivisionLeftCells(divisorLength)
  left[divisorLength - 1] = String(b)
  return left
}

/** 厂字形除法步骤快照基础行：商行（顶杠）+ 被除数行 + 已完成组的乘积/差行。 */
function buildDivisionBaseRows(
  quotientDigits: string[],
  aCells: string[],
  divisorLeft: string[],
  emptyLeft: string[],
  groupProductCells: string[][],
  groupDiffCells: string[][]
): VerticalMathBoardRow[] {
  const rows: VerticalMathBoardRow[] = [
    divisionRow(cloneCells(quotientDigits), emptyLeft, true),
    divisionRow(cloneCells(aCells), divisorLeft, false)
  ]
  for (let g = 0; g < groupProductCells.length; g++) {
    rows.push(divisionRow(cloneCells(groupProductCells[g]), emptyLeft, true))
    rows.push(divisionRow(cloneCells(groupDiffCells[g]), emptyLeft, false))
  }
  return rows
}

const CN_DIGITS: string[] = ['', '一', '二', '三', '四', '五', '六', '七', '八', '九']

/**
 * 生成九九乘法口诀（课本小九九，较小数在前），如 4×2 →「二四得八」。
 * 规则：积 <10 用「得」（二四得八）；积 =10 用「一十」（二五一十）；
 * 11–19 用「十X」（三五十五）；整十用「X十」（四五二十）；其余「X十Y」（六七四十二）。
 */
export function multiplicationTablePhrase(b: number, q: number): string {
  const x: number = Math.min(b, q)
  const y: number = Math.max(b, q)
  const p: number = b * q
  if (x < 1 || x > 9 || y < 1 || y > 9) {
    return `${b} × ${q}`   // 防御兜底（输入已由校验限制在 1–9）
  }
  if (p < 10) {
    return `${CN_DIGITS[x]}${CN_DIGITS[y]}得${CN_DIGITS[p]}`
  }
  if (p === 10) {
    return `${CN_DIGITS[x]}${CN_DIGITS[y]}一十`
  }
  const tens: number = Math.floor(p / 10)
  const units: number = p % 10
  const tensPart: string = tens === 1 ? '十' : `${CN_DIGITS[tens]}十`
  if (units === 0) {
    return `${CN_DIGITS[x]}${CN_DIGITS[y]}${tensPart}`
  }
  return `${CN_DIGITS[x]}${CN_DIGITS[y]}${tensPart}${CN_DIGITS[units]}`
}

/**
 * Solve A ÷ B as step-by-step long division (竖式除法, v2 厂字形布局).
 *
 * Assumes B ∈ [1, 9] (validated by validateVerticalMathInputs for DIVIDE —
 * 一位数除数，多位除数版式已下线).
 * 课本布局：商在横线上方（顶杠），除数在竖线左侧，被除数在竖线右侧。
 * v3 逐步讲解：每组（一位商）拆成 试商 → 相乘 → 相减 三个子步骤，
 * 逐步揭示乘积行（蓝，带下横线）与差行（末组的差即余数，绿色）；
 * 旁白带九九口诀与"落下一位"的来龙去脉。
 * 不够除分两种：首位不够除（narration-only，商位留空）；中间位不够除
 * （商位写 0——课本规则，修复历史 bug：515÷5 曾错拼成 13）。
 */
export function solveVerticalDivide(a: number, b: number): VerticalMathSolution {
  const divStr: string = String(b)
  const divisorLength: number = divStr.length

  // Special case: 0 ÷ B = 0. Produces a single final step with the quotient '0'.
  if (a === 0) {
    const columnCount: number = 1
    const aCells: string[] = ['0']
    const emptyLeft: string[] = emptyDivisionLeftCells(divisorLength)

    const initialRows: VerticalMathBoardRow[] = [
      divisionRow(emptyCells(columnCount), emptyLeft, true),
      divisionRow(cloneCells(aCells), divisionLeftWithDivisor(b, divisorLength), false)
    ]

    const finalStep: VerticalMathStep = new VerticalMathStep()
    finalStep.title = '得到答案'
    finalStep.narration = `0 除以任何数都得 0。0 ÷ ${b} ＝ 0。`
    finalStep.placeLabel = '完成'
    finalStep.actionLabel = '完成竖式'
    finalStep.rows = [
      divisionRow(['0'], emptyLeft, true),
      divisionRow(cloneCells(aCells), divisionLeftWithDivisor(b, divisorLength), false)
    ]
    finalStep.highlights = [
      { rowIndex: 0, columnIndex: 0, kind: 'final' }
    ]

    return {
      operation: VerticalMathOperation.DIVIDE,
      operandA: a,
      operandB: b,
      result: 0,
      remainder: 0,
      columnCount: columnCount,
      initialRows: initialRows,
      steps: [finalStep],
      finalRow: { cells: ['0'] }
    }
  }

  const aStr: string = String(a)
  const columnCount: number = aStr.length
  const aCells: string[] = aStr.split('')
  const emptyLeft: string[] = emptyDivisionLeftCells(divisorLength)
  const divisorLeft: string[] = emptyDivisionLeftCells(divisorLength)
  divisorLeft[divisorLength - 1] = String(b)

  const initialRows: VerticalMathBoardRow[] = [
    divisionRow(emptyCells(columnCount), emptyLeft, true),
    divisionRow(cloneCells(aCells), divisorLeft, false)
  ]

  const steps: VerticalMathStep[] = []

  // Simulate long division left-to-right
  let remainder: number = 0
  const quotientDigits: string[] = emptyCells(columnCount)
  let anyQuotientDigit: boolean = false

  // 每组一行乘积（蓝，下横线）+ 一行差；差按课本习惯落下一位
  const groupProductCells: string[][] = []
  const groupDiffCells: string[][] = []
  const groupFinalFlag: boolean[] = []

  for (let i = 0; i < columnCount; i++) {
    const digit: number = Number(aCells[i])
    const window: number = remainder * 10 + digit
    if (window < b) {
      // 不够除。首位（还没写过商）只提示看下一位；中间位必须商 0。
      if (!anyQuotientDigit) {
        const notEnoughStep: VerticalMathStep = new VerticalMathStep()
        notEnoughStep.title = `第 ${i + 1} 位：不够除`
        notEnoughStep.narration = `首位 ${digit} 比 ${b} 小，不够除，再看下一位。`
        notEnoughStep.placeLabel = `第 ${i + 1} 位`
        notEnoughStep.actionLabel = '看下一位'
        notEnoughStep.rows = buildDivisionBaseRows(
          quotientDigits, aCells, divisorLeft, emptyLeft, groupProductCells, groupDiffCells
        )
        notEnoughStep.highlights = [
          { rowIndex: 1, columnIndex: i, kind: 'active' }
        ]
        steps.push(notEnoughStep)
      } else {
        // 课本规则：中间位不够除，商在这一位写 0（再落一位一起除）。
        quotientDigits[i] = '0'
        const zeroStep: VerticalMathStep = new VerticalMathStep()
        zeroStep.title = `第 ${i + 1} 位：商写 0`
        zeroStep.narration =
          `把 ${digit} 落下来，${digit} 不够除 ${b}，商的${getPlaceValueLabel(columnCount, i)}写 0。`
        zeroStep.placeLabel = `第 ${i + 1} 位`
        zeroStep.actionLabel = '写 0'
        zeroStep.rows = buildDivisionBaseRows(
          quotientDigits, aCells, divisorLeft, emptyLeft, groupProductCells, groupDiffCells
        )
        zeroStep.highlights = [
          { rowIndex: 1, columnIndex: i, kind: 'active' },
          { rowIndex: 0, columnIndex: i, kind: 'quotient' }
        ]
        steps.push(zeroStep)
      }
      remainder = window
      continue
    }
    const firstQuotient: boolean = !anyQuotientDigit
    const remainderBefore: number = remainder
    const q: number = Math.floor(window / b)
    const prod: number = q * b
    remainder = window - prod
    anyQuotientDigit = true
    quotientDigits[i] = String(q)
    const phrase: string = multiplicationTablePhrase(b, q)

    // --- 子步骤 1：试商（商位写出 q，讲清"看哪些数 + 想哪句口诀"） ---
    let tryNarration: string
    if (firstQuotient) {
      tryNarration = i === 0
        ? `先看第 1 位：${window} ÷ ${b}，想口诀：${phrase}，商 ${q}。`
        : `前 ${i + 1} 位 ${window} ÷ ${b}，想口诀：${phrase}，商 ${q}。`
    } else if (remainderBefore > 0) {
      tryNarration = `${remainderBefore} 和落下来的 ${digit} 拼成 ${window}。想口诀：${phrase}，商 ${q}。`
    } else {
      tryNarration = `把 ${digit} 落下来，${window} ÷ ${b}，想口诀：${phrase}，商 ${q}。`
    }
    const tryStep: VerticalMathStep = new VerticalMathStep()
    tryStep.title = `第 ${i + 1} 位：试商 ${q}`
    tryStep.narration = tryNarration
    tryStep.placeLabel = `第 ${i + 1} 位`
    tryStep.actionLabel = '试商'
    tryStep.rows = buildDivisionBaseRows(
      quotientDigits, aCells, divisorLeft, emptyLeft, groupProductCells, groupDiffCells
    )
    tryStep.highlights = [
      { rowIndex: 1, columnIndex: i, kind: 'active' },
      { rowIndex: 0, columnIndex: i, kind: 'quotient' }
    ]
    steps.push(tryStep)

    // --- 子步骤 2：相乘（除数 × 商，揭示乘积行） ---
    const productCells: string[] = placeEndingAt(String(prod), i, columnCount)
    let diffStr: string
    let diffEnd: number
    let isFinalGroup: boolean = false
    if (i < columnCount - 1) {
      diffStr = String(remainder * 10 + Number(aCells[i + 1]))
      diffEnd = i + 1
    } else {
      diffStr = String(remainder)
      diffEnd = i
      isFinalGroup = true
    }
    const diffCells: string[] = placeEndingAt(diffStr, diffEnd, columnCount)

    const productRowIndex: number = 2 + groupProductCells.length * 2
    const mulStep: VerticalMathStep = new VerticalMathStep()
    mulStep.title = `第 ${i + 1} 位：相乘`
    mulStep.narration = `${b} × ${q} ＝ ${prod}，写在 ${window} 下面。`
    mulStep.placeLabel = `第 ${i + 1} 位`
    mulStep.actionLabel = '相乘'
    mulStep.rows = buildDivisionBaseRows(
      quotientDigits, aCells, divisorLeft, emptyLeft, groupProductCells, groupDiffCells
    )
    mulStep.rows.push(divisionRow(cloneCells(productCells), emptyLeft, true))
    mulStep.highlights = [
      { rowIndex: 1, columnIndex: i, kind: 'active' }
    ]
    for (let column = 0; column < columnCount; column++) {
      if (productCells[column] !== '' && productCells[column] !== ' ') {
        mulStep.highlights.push({ rowIndex: productRowIndex, columnIndex: column, kind: 'product' })
      }
    }
    steps.push(mulStep)

    // --- 子步骤 3：相减（揭示差行；中间组顺势落下一位） ---
    const diffRowIndex: number = productRowIndex + 1
    let subNarration: string
    if (!isFinalGroup) {
      const nextDigit: number = Number(aCells[i + 1])
      subNarration = `${window} − ${prod} ＝ ${remainder}，把下一位 ${nextDigit} 落下来接着除。`
    } else if (remainder === 0) {
      subNarration = `${window} − ${prod} ＝ ${remainder}，正好除完！`
    } else {
      subNarration = `${window} − ${prod} ＝ ${remainder}，剩下的 ${remainder} 就是余数。`
    }
    const subStep: VerticalMathStep = new VerticalMathStep()
    subStep.title = `第 ${i + 1} 位：相减`
    subStep.narration = subNarration
    subStep.placeLabel = `第 ${i + 1} 位`
    subStep.actionLabel = '相减'
    subStep.rows = buildDivisionBaseRows(
      quotientDigits, aCells, divisorLeft, emptyLeft, groupProductCells, groupDiffCells
    )
    subStep.rows.push(divisionRow(cloneCells(productCells), emptyLeft, true))
    subStep.rows.push(divisionRow(cloneCells(diffCells), emptyLeft, false))
    subStep.highlights = [
      { rowIndex: 1, columnIndex: i, kind: 'active' }
    ]
    for (let column = 0; column < columnCount; column++) {
      const cell: string = diffCells[column]
      if (cell !== '' && cell !== ' ') {
        subStep.highlights.push({
          rowIndex: diffRowIndex,
          columnIndex: column,
          kind: isFinalGroup ? 'final' : 'active'
        })
      }
    }
    steps.push(subStep)

    groupProductCells.push(productCells)
    groupDiffCells.push(diffCells)
    groupFinalFlag.push(isFinalGroup)
  }

  const finalQuotient: string = anyQuotientDigit
    ? quotientDigits.join('').replace(/^0+/, '') || '0'
    : '0'

  const finalRows: VerticalMathBoardRow[] = buildDivisionBaseRows(
    quotientDigits, aCells, divisorLeft, emptyLeft, groupProductCells, groupDiffCells
  )
  const finalHighlights: VerticalMathHighlight[] = []
  for (let column = 0; column < columnCount; column++) {
    if (quotientDigits[column] !== '' && quotientDigits[column] !== ' ') {
      finalHighlights.push({ rowIndex: 0, columnIndex: column, kind: 'final' })
    }
  }
  for (let g = 0; g < groupDiffCells.length; g++) {
    if (groupFinalFlag[g]) {
      for (let column = 0; column < columnCount; column++) {
        const cell: string = groupDiffCells[g][column]
        if (cell !== '' && cell !== ' ') {
          finalHighlights.push({ rowIndex: 2 + g * 2 + 1, columnIndex: column, kind: 'final' })
        }
      }
    }
  }

  const finalStep: VerticalMathStep = new VerticalMathStep()
  finalStep.title = '得到答案'
  finalStep.narration = remainder === 0
    ? `${a} ÷ ${b} ＝ ${finalQuotient}。验算：${finalQuotient} × ${b} ＝ ${a}，正好除尽。`
    : `${a} ÷ ${b} ＝ ${finalQuotient}，余数 ${remainder}。验算：${finalQuotient} × ${b} ＋ ${remainder} ＝ ${a}。`
  finalStep.placeLabel = '完成'
  finalStep.actionLabel = '完成竖式'
  finalStep.rows = finalRows
  finalStep.highlights = finalHighlights
  steps.push(finalStep)

  return {
    operation: VerticalMathOperation.DIVIDE,
    operandA: a,
    operandB: b,
    result: Number(finalQuotient),
    remainder: remainder,
    columnCount: columnCount,
    initialRows: initialRows,
    steps: steps,
    finalRow: { cells: cloneCells(quotientDigits) }
  }
}
