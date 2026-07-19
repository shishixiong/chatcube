# Vertical Math Calculator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `vertical_math` interactive card to Cube Chat that teaches 6–12 year-olds standard primary-school vertical arithmetic (加/减/×/÷) one step at a time.

**Architecture:** Pure-function solver (`utils/VerticalMathSolver.ets`) generates a complete step-by-step snapshot; UI components (`components/VerticalMathCard.ets` + `components/verticalMath/`) are stateless renderers that read the solver output and walk the user through each step. Integrates with the existing `ToolExecutionService` / `MessageBubble` pipeline as a new AI-callable tool. Reuses the 9-file mini-game-tool recipe (skill: `adding-mini-game-tool`) but does NOT add a new `StarActivityType` (per spec §2.1) — completion is reported only via the tool-result payload.

**Tech Stack:** HarmonyOS 6 (API 23), ArkTS strict mode, ArkUI V2 (`@ComponentV2` / `@Param` / `@Event` / `@Local`), `@ohos/hypium` for solver unit tests.

---

## Global Constraints

These constraints come from `docs/superpowers/specs/2026-07-19-vertical-math-calculator-design.md` and the project `CLAUDE.md`. Every task's requirements implicitly include this section.

- **Operation ranges:** A and B are integers in `[0, 999]`. Subtract requires `A >= B`. Multiply requires `B ∈ [0, 9]` (multi-digit × single-digit). Divide requires `B ∈ [1, 9]` (single-digit divisor). Both integer and remainder division are supported.
- **Initial render after "开始计算":** only show operands, operator, and the first horizontal line — NO calculation steps. `visibleStepCount` starts at 0; first "下一步" reveals the alignment step.
- **Step-by-step is fully reversible:** 上一步 / 下一步 are mirrors. No step may have hidden side effects (no `onAnswer` until `visibleStepCount === steps.length`).
- **Multiplication image-style partial products:** each partial product is bound to explicit place-value columns (units→十位/个位, tens→百位/十位, hundreds→千位/百位). NO separate red carry marker — the 10s digit of each partial product already carries. Multiplier highlights together with the current multiplicand digit at every step.
- **Subtraction borrow marks:** a small `•` above the column being borrowed from, strikethrough on the old digit, and the new digit written in its place.
- **Division 厂字形:** 看首位 → 试商 → 乘 → 减 → 落位. When the first digit is smaller than the divisor, narration says "首位不够除，先看下一位" and no leading 0 quotient digit is rendered.
- **Input UX:** numeric keyboard, filter non-digits, hard-cap at 3 digits. Empty input → "请先输入两个数字".
- **Visual style (探险游戏):** purple gradient board `#6448b5 → #27194f`, current digit in yellow `#ffe66d`, completed in mint `#b9f2d0`, error in coral `#ff8f7a`. Round, large, monospace digits.
- **Layout:** 70/30 (board / narrator) on tablet/desktop; stacked vertically on `<780vp`. All tappable controls ≥ 44vp.
- **Tool contract:** `vertical_math({operation, operand_a?, operand_b?})` — all three may be omitted (render full input). `onAnswer` fires only on full completion, payload = `{completed, operation, operand_a, operand_b, result, remainder, step_count}`. Illegal inputs do NOT call `onAnswer`.
- **Tool ID format:** snake_case (`vertical_math`). Tool function name check via `isVerticalMathFunctionName(name)`. Constant exported as `VERTICAL_MATH_TOOL_ID`.
- **Per-project ArkTS rules** (from `CLAUDE.md` "已知踩坑"): no inline `{...}` literals inside `arr.map(p => ({...}))` (annotate return type), no `const x: Foo = {...}` inside ForEach (use method returning constructed object), no destructuring `const [a, b] = ...`, JSON schema description strings must use 「」not ASCII `"`, `Row.alignItems` = `VerticalAlign` / `Column.alignItems` = `HorizontalAlign`.
- **Per-project integration surface (skill: `adding-mini-game-tool`):** register tool ID in `SearchToolIdentityUtils.ets`, schema + executor in `config/BuiltinTools.ets`, dispatch handler in `services/ToolExecutionService.ets` BEFORE the `resolveToolId` fallback, mount in `components/MessageBubble.ets` at the 7 known surface sites. DO NOT touch `models/StarEventModels.ets` or `models/AssistantModels.ets` this iteration.
- **Build verification:** `DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug` must succeed. Tests run in DevEco Studio (right-click test file → Run) — CLI `hvigorw test` is broken on this project.
- **Commit cadence:** one commit per task after verification. Use Conventional Commits (`feat: ...`, `test: ...`, `fix: ...`).

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `entry/src/main/ets/utils/VerticalMathSolver.ets` | Pure logic: validation, four solvers, step generation. No ArkUI imports. |
| `entry/src/main/ets/utils/VerticalMathColors.ets` | Color constants for the adventure theme (board bg, yellow active, mint done, coral error). |
| `entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets` | Renders the blackboard: rows of equal-width digit cells, operator column, horizontal lines, carry dots, borrow marks. Stateless: takes `solution` + `visibleStepCount`. |
| `entry/src/main/ets/components/verticalMath/VerticalMathStepNarrator.ets` | Renders the step narration list with active/done states and auto-scroll. |
| `entry/src/main/ets/components/verticalMath/VerticalMathBoardRow.ets` | Helper component used by `VerticalMathBoard` for a single row of cells. (Split out per writing-plans skill: files that change together live together.) |
| `entry/src/main/ets/components/VerticalMathCard.ets` | Shell component: input form, operator chooser, control buttons, hosts Board + Narrator. Owns local state (`operandA`, `operandB`, `selectedOperation`, `solution`, `visibleStepCount`, `errorMessage`). Emits `onAnswer`. |
| `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets` | Hypium unit tests for the solver (validation + four operations + edge cases). |

### Modified files

| Path | Change |
|---|---|
| `entry/src/main/ets/utils/SearchToolIdentityUtils.ets` | Add `VERTICAL_MATH_TOOL_ID` constant + `isVerticalMathFunctionName(name)` + `isVerticalMathToolId(id)`. |
| `entry/src/main/ets/config/BuiltinTools.ets` | Register `vertical_math` schema (name, description, rawSchemaJson), executor handler (returns pending `ToolCall`), `registerTool(...)` call, add to a `getIds()` array if one exists. |
| `entry/src/main/ets/services/ToolExecutionService.ets` | Add `handleVerticalMath(toolCall)` private method that mirrors `handleMathQuiz` / `handleHandwriting` shape: create `MathQuizCard`-style result JSON, dispatch as pending answer, return without immediate resolution. Wire into the dispatch chain BEFORE the `resolveToolId` fallback. |
| `entry/src/main/ets/components/MessageBubble.ets` | (1) Import `VerticalMathCard` and `isVerticalMathFunctionName`; (2) add `isVerticalMathFunctionName` to the import line; (3) extend the tool-card render chain (~L2030) to call a new `shouldRenderVerticalMathInteractionCard`; (4) extend the 7 existing `isXxxFunctionName(...)` chains at L2548, L2619, L2629, L2692, L3069, L3510–3511, L3766, L3932 to include `isVerticalMathFunctionName`. |

### NOT modified (explicit per spec §2.1)

- `models/StarEventModels.ets` — no new `StarActivityType`. Solver only writes a `step_count` field; no star event recorded.
- `models/AssistantModels.ets` — `vertical_math` is NOT in `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` this iteration. LLM/parent can enable it per-assistant.
- `entry/src/main/resources/base/profile/{main_pages,router_map}.json` — no new page; tool opens the card inline in chat.

---

## Task 1: Solver skeleton + input validation

**Files:**
- Create: `entry/src/main/ets/utils/VerticalMathSolver.ets`
- Create: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets`

**Interfaces (Phase A prerequisite for every later task):**

```ts
// utils/VerticalMathSolver.ets
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
```

- [ ] **Step 1.1: Create the solver skeleton file with only types and a stub `validateVerticalMathInputs`.**

```ts
// utils/VerticalMathSolver.ets
// (paste interfaces above, then add:)

export function validateVerticalMathInputs(
  operation: VerticalMathOperation,
  operandA: number,
  operandB: number
): VerticalMathValidationError | null {
  // Implementation lives in step 1.2.
  return null
}
```

- [ ] **Step 1.2: Implement `validateVerticalMathInputs` with the rules from spec §2.2 and §8.**

```ts
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
```

- [ ] **Step 1.3: Create the test file with one passing test for `null` return on valid input.**

```ts
// ohosTest/ets/test/VerticalMathSolver.test.ets
import { describe, it, expect } from '@ohos/hypium'
import {
  VerticalMathOperation,
  VerticalMathValidationError,
  validateVerticalMathInputs
} from '../../../main/ets/utils/VerticalMathSolver'

export default function verticalMathSolverTest() {
  describe('validateVerticalMathInputs', () => {
    it('returns null for valid addition', 0, () => {
      const err: VerticalMathValidationError | null = validateVerticalMathInputs(
        VerticalMathOperation.ADD, 47, 28
      )
      expect(err === null).assertEqual(true)
    })

    it('rejects A > 999', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.ADD, 1000, 1)
      expect(err instanceof VerticalMathValidationError).assertEqual(true)
    })

    it('rejects negative B', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.SUBTRACT, 50, -1)
      expect(err instanceof VerticalMathValidationError).assertEqual(true)
    })

    it('rejects non-integer A', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.ADD, 1.5, 2)
      expect(err instanceof VerticalMathValidationError).assertEqual(true)
    })

    it('rejects subtract when A < B', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.SUBTRACT, 10, 50)
      expect((err?.message ?? '')).assertEqual('不够减，建议换一道题哦')
    })

    it('rejects multiply when B > 9', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.MULTIPLY, 100, 10)
      expect((err?.message ?? '')).assertEqual('乘法的第二个数请输入 0–9')
    })

    it('rejects divide when B = 0', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.DIVIDE, 50, 0)
      expect((err?.message ?? '')).assertEqual('除数不能为 0')
    })

    it('rejects divide when B > 9', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.DIVIDE, 50, 12)
      expect((err?.message ?? '')).assertEqual('除数请输入 1–9')
    })

    it('accepts boundary A = 0', 0, () => {
      const err = validateVerticalMathInputs(VerticalMathOperation.ADD, 0, 0)
      expect(err === null).assertEqual(true)
    })

    it('accepts boundary A = 999', 0, {
      let err: VerticalMathValidationError | null = validateVerticalMathInputs(
        VerticalMathOperation.ADD, 999, 999
      )
      expect(err === null).assertEqual(true)
      err = validateVerticalMathInputs(VerticalMathOperation.MULTIPLY, 999, 9)
      expect(err === null).assertEqual(true)
    })
  })
}
```

- [ ] **Step 1.4: Verify tests pass.**

Run in DevEco Studio: right-click `VerticalMathSolver.test.ets` → Run 'vertical_math_...' .
Expected: 10/10 pass. If any fail, fix `validateVerticalMathInputs` until green.

- [ ] **Step 1.5: Commit.**

```bash
git add entry/src/main/ets/utils/VerticalMathSolver.ets \
        entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets
git commit -m "feat(vertical-math): add solver skeleton + input validation"
```

---

## Task 2: Addition solver (with carry marks)

**Files:**
- Modify: `entry/src/main/ets/utils/VerticalMathSolver.ets`
- Modify: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets`

**Produces:** `solveVerticalAdd(a: number, b: number): VerticalMathSolution` — pure function. Builds `initialRows` (A, '+' operator, B, line) plus N `steps` where N = `max(digitsA, digitsB)` (alignment step + one per digit processed). Each step appends a topMark carry when `digitA + digitB + carryIn >= 10`, highlights the active column in yellow, and previous columns in mint.

- [ ] **Step 2.1: Write failing tests for `solveVerticalAdd`.**

Append to the test file (still inside `describe('validateVerticalMathInputs', ...)` is fine; or add a sibling `describe('solveVerticalAdd', ...)` block — the implementer picks the structure, both are acceptable):

```ts
import { solveVerticalAdd } from '../../../main/ets/utils/VerticalMathSolver'

// Inside the default-exported function, add:

describe('solveVerticalAdd', () => {
  it('47 + 28 = 75 with one carry', 0, () => {
    const s = solveVerticalAdd(47, 28)
    expect(s.result).assertEqual(75)
    expect(s.remainder).assertEqual(0)
    expect(s.columnCount).assertEqual(2)
    // alignment step first
    expect(s.steps[0].title).assertEqual('数位对齐')
    // exactly one step should carry (units: 7+8=15)
    const carrySteps = s.steps.filter(step => step.rows.some(row => row.topMark === '1'))
    expect(carrySteps.length).assertEqual(1)
    // last step is the result
    expect(s.steps[s.steps.length - 1].showResultRow).assertEqual(true)
    expect(s.finalRow?.cells.join('')).assertEqual('75')
  })

  it('100 + 200 = 300 with no carry', 0, () => {
    const s = solveVerticalAdd(100, 200)
    expect(s.result).assertEqual(300)
    expect(s.steps.every(step => !step.rows.some(row => row.topMark === '1'))).assertEqual(true)
  })

  it('999 + 1 = 1000 (carry cascades)', 0, () => {
    const s = solveVerticalAdd(999, 1)
    expect(s.result).assertEqual(1000)
    expect(s.columnCount).assertEqual(4)
    const carrySteps = s.steps.filter(step => step.rows.some(row => row.topMark === '1'))
    expect(carrySteps.length >= 3).assertEqual(true)
  })

  it('0 + 0 = 0', 0, () => {
    const s = solveVerticalAdd(0, 0)
    expect(s.result).assertEqual(0)
    expect(s.columnCount).assertEqual(1)
  })
})
```

- [ ] **Step 2.2: Run tests to verify they fail.**

In DevEco Studio: Run the test file.
Expected: `solveVerticalAdd` not exported → compile error → tests do not run. Confirms the test is genuinely failing.

- [ ] **Step 2.3: Implement `solveVerticalAdd`.**

```ts
export function solveVerticalAdd(a: number, b: number): VerticalMathSolution {
  const digitsA = Math.max(1, String(a).length)
  const digitsB = Math.max(1, String(b).length)
  const columnCount = Math.max(digitsA, digitsB)
  const leftPad = (n: number, width: number): string[] => {
    const s = String(n).padStart(width, ' ')
    return s.split('')
  }
  const aCells = leftPad(a, columnCount)
  const bCells = leftPad(b, columnCount)

  const initialRows: VerticalMathBoardRow[] = [
    { cells: aCells },
    { cells: bCells, operator: '+' },
    { cells: new Array<string>(columnCount).fill('') }  // line spacer (renderer draws the line)
  ]

  const steps: VerticalMathStep[] = []

  // Step 1: alignment
  steps.push({
    title: '数位对齐',
    narration: '个位对个位，十位对十位。',
    rows: [
      { cells: aCells },
      { cells: bCells, operator: '+' },
      { cells: new Array<string>(columnCount).fill('') }
    ],
    highlights: []
  })

  // Compute digit-by-digit from right to left, but only one step per digit (snapshot).
  let carry = 0
  const digitResults: number[] = []
  for (let col = columnCount - 1; col >= 0; col--) {
    const dA = aCells[col] === ' ' ? 0 : Number(aCells[col])
    const dB = bCells[col] === ' ' ? 0 : Number(bCells[col])
    const sum = dA + dB + carry
    digitResults.unshift(sum % 10)
    carry = Math.floor(sum / 10)
  }
  const finalCells = (digitResults.join('') === '' ? '0' : digitResults.join('')).padStart(columnCount, ' ').split('')

  // Build intermediate steps: for each column from right to left, reveal one result digit.
  // Note: the carry row sits visually above the column it carries INTO (left of the current col).
  const working = aCells.slice()
  const currentSumDigits: string[] = new Array<string>(columnCount).fill('')
  let carryIn = 0
  for (let col = columnCount - 1; col >= 0; col--) {
    const dA = aCells[col] === ' ' ? 0 : Number(aCells[col])
    const dB = bCells[col] === ' ' ? 0 : Number(bCells[col])
    const sum = dA + dB + carryIn
    const resultDigit = sum % 10
    carryIn = Math.floor(sum / 10)
    const newSumDigits = currentSumDigits.slice()
    newSumDigits[col] = String(resultDigit)
    const topMarkRow: VerticalMathBoardRow = {
      cells: new Array<string>(columnCount).fill('')
    }
    if (carryIn > 0 && col - 1 >= 0) {
      topMarkRow.cells[col - 1] = String(carryIn)
    }
    const rowSnapshots: VerticalMathBoardRow[] = [
      { cells: aCells.slice() },
      { cells: bCells.slice(), operator: '+' },
      { cells: new Array<string>(columnCount).fill('') },  // first line
      ...(carryIn > 0 ? [topMarkRow] : []),
      { cells: newSumDigits }
    ]
    const highlights: VerticalMathHighlight[] = [
      { rowIndex: 0, columnIndex: col, kind: 'active' },
      { rowIndex: 1, columnIndex: col, kind: 'active' }
    ]
    if (carryIn > 0 && col - 1 >= 0) {
      highlights.push({ rowIndex: 3, columnIndex: col - 1, kind: 'carry' })
    }
    // Mark all already-revealed result columns as done (mint)
    for (let prev = col + 1; prev < columnCount; prev++) {
      highlights.push({ rowIndex: rowSnapshots.length - 1, columnIndex: prev, kind: 'done' })
    }
    steps.push({
      title: `第 ${columnCount - col} 位相加`,
      narration: carryIn > 0
        ? `${dA} + ${dB} = ${sum}，写 ${resultDigit}，进 ${carryIn}。`
        : `${dA} + ${dB} = ${sum}，写 ${resultDigit}。`,
      rows: rowSnapshots,
      highlights
    })
    currentSumDigits[col] = String(resultDigit)
  }

  // Final step: reveal second line + final result row.
  steps.push({
    title: '得到答案',
    narration: `答案是 ${finalCells.join('').trim()}。`,
    rows: [
      { cells: aCells.slice() },
      { cells: bCells.slice(), operator: '+' },
      { cells: new Array<string>(columnCount).fill('') },
      { cells: finalCells.slice() }
    ],
    highlights: [],
    showFinalLine: true,
    showResultRow: true
  })

  return {
    operation: VerticalMathOperation.ADD,
    operandA: a,
    operandB: b,
    result: a + b,
    remainder: 0,
    columnCount,
    initialRows,
    steps,
    finalRow: { cells: finalCells.slice() }
  }
}
```

- [ ] **Step 2.4: Run tests in DevEco Studio — expect 4 add tests green + 10 validation tests still green.**

If a carry-row index drifts (e.g. `rowIndex: 3` vs `rowSnapshots.length - 1`), update the highlight entry accordingly. Keep iterating until green.

- [ ] **Step 2.5: Commit.**

```bash
git add entry/src/main/ets/utils/VerticalMathSolver.ets \
        entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets
git commit -m "feat(vertical-math): add addition solver with carry marks"
```

---

## Task 3: Subtraction solver (with borrow marks)

**Files:**
- Modify: `entry/src/main/ets/utils/VerticalMathSolver.ets`
- Modify: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets`

**Produces:** `solveVerticalSubtract(a: number, b: number): VerticalMathSolution` — assumes `a >= b`. For each column from right to left, if `digitA < digitB + carry` then we borrow: add a `•` topMark above `col - 1`, strikethrough the old `digitA` at `col - 1` (renderer reads `cells[col-1]` marked with kind `borrow`), and write the new value `(10 + digitA - carry)` at col. Highlight active column yellow, completed columns mint.

- [ ] **Step 3.1: Write failing tests.**

```ts
import { solveVerticalSubtract } from '../../../main/ets/utils/VerticalMathSolver'

// add inside the default export:

describe('solveVerticalSubtract', () => {
  it('503 - 278 = 225 with cascading borrow', 0, () => {
    const s = solveVerticalSubtract(503, 278)
    expect(s.result).assertEqual(225)
    // expect at least one step with a '•' topMark (borrow marker)
    const borrowSteps = s.steps.filter(step => step.rows.some(row => row.topMark === '•'))
    expect(borrowSteps.length >= 2).assertEqual(true)
  })

  it('100 - 50 = 50 with no borrow', 0, () => {
    const s = solveVerticalSubtract(100, 50)
    expect(s.result).assertEqual(50)
    const borrowSteps = s.steps.filter(step => step.rows.some(row => row.topMark === '•'))
    expect(borrowSteps.length).assertEqual(0)
  })

  it('999 - 999 = 0', 0, () => {
    const s = solveVerticalSubtract(999, 999)
    expect(s.result).assertEqual(0)
    expect(s.columnCount).assertEqual(3)
  })
})
```

- [ ] **Step 3.2: Run tests — expect compile error (`solveVerticalSubtract` not exported).**

- [ ] **Step 3.3: Implement `solveVerticalSubtract`.**

```ts
export function solveVerticalSubtract(a: number, b: number): VerticalMathSolution {
  const digitsA = Math.max(1, String(a).length)
  const digitsB = Math.max(1, String(b).length)
  const columnCount = Math.max(digitsA, digitsB)
  const leftPad = (n: number, width: number): string[] => String(n).padStart(width, ' ').split('')
  const aCells = leftPad(a, columnCount)
  const bCells = leftPad(b, columnCount)

  const initialRows: VerticalMathBoardRow[] = [
    { cells: aCells.slice() },
    { cells: bCells.slice(), operator: '-' },
    { cells: new Array<string>(columnCount).fill('') }
  ]

  const steps: VerticalMathStep[] = []
  steps.push({
    title: '数位对齐',
    narration: '个位对个位，十位对十位。',
    rows: [
      { cells: aCells.slice() },
      { cells: bCells.slice(), operator: '-' },
      { cells: new Array<string>(columnCount).fill('') }
    ],
    highlights: []
  })

  // Snapshot cells as we mutate for borrow: aCellsBorrowed tracks the "what A looks like now" view.
  const aBorrowed: string[] = aCells.slice()
  const resultCells: string[] = new Array<string>(columnCount).fill('')
  let carried = 0

  for (let col = columnCount - 1; col >= 0; col--) {
    let dA = aBorrowed[col] === ' ' ? 0 : Number(aBorrowed[col])
    const dB = bCells[col] === ' ' ? 0 : Number(bCells[col])
    let borrowRow: VerticalMathBoardRow | null = null
    if (dA < dB + carried) {
      // borrow from col-1
      let donor = col - 1
      while (donor >= 0 && (aBorrowed[donor] === ' ' || Number(aBorrowed[donor]) === 0)) {
        donor--
      }
      if (donor >= 0) {
        aBorrowed[donor] = String(Number(aBorrowed[donor]) - 1)
        dA += 10
        borrowRow = {
          cells: new Array<string>(columnCount).fill(''),
          topMark: '•',
          topMarkColumn: donor
        }
      }
    }
    const diff = dA - dB - carried
    carried = 0
    resultCells[col] = String(diff)

    const snap: VerticalMathBoardRow[] = [
      { cells: aBorrowed.slice() },
      { cells: bCells.slice(), operator: '-' },
      { cells: new Array<string>(columnCount).fill('') }
    ]
    if (borrowRow !== null) snap.push(borrowRow)
    snap.push({ cells: resultCells.slice() })

    const highlights: VerticalMathHighlight[] = [
      { rowIndex: 0, columnIndex: col, kind: 'active' },
      { rowIndex: 1, columnIndex: col, kind: 'active' }
    ]
    if (borrowRow !== null && borrowRow.topMarkColumn !== undefined) {
      highlights.push({ rowIndex: snap.length - 2, columnIndex: borrowRow.topMarkColumn, kind: 'borrow' })
    }
    for (let prev = col + 1; prev < columnCount; prev++) {
      highlights.push({ rowIndex: snap.length - 1, columnIndex: prev, kind: 'done' })
    }
    steps.push({
      title: `第 ${columnCount - col} 位相减`,
      narration: borrowRow !== null
        ? `${dB} 不够减，向左借 1，${dA} - ${dB} = ${diff}。`
        : `${dA} - ${dB} = ${diff}。`,
      rows: snap,
      highlights
    })
  }

  const finalTrimmed = (resultCells.join('').replace(/^\s+/, '') || '0')
  steps.push({
    title: '得到答案',
    narration: `答案是 ${finalTrimmed}。`,
    rows: [
      { cells: aCells.slice() },
      { cells: bCells.slice(), operator: '-' },
      { cells: new Array<string>(columnCount).fill('') },
      { cells: resultCells.slice() }
    ],
    highlights: [],
    showFinalLine: true,
    showResultRow: true
  })

  return {
    operation: VerticalMathOperation.SUBTRACT,
    operandA: a,
    operandB: b,
    result: a - b,
    remainder: 0,
    columnCount,
    initialRows,
    steps,
    finalRow: { cells: resultCells.slice() }
  }
}
```

- [ ] **Step 3.4: Run tests in DevEco Studio — expect new 3 tests green; total 17/17 green.**

- [ ] **Step 3.5: Commit.**

```bash
git add entry/src/main/ets/utils/VerticalMathSolver.ets \
        entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets
git commit -m "feat(vertical-math): add subtraction solver with borrow marks"
```

---

## Task 4: Multiplication solver (image-style partial products)

**Files:**
- Modify: `entry/src/main/ets/utils/VerticalMathSolver.ets`
- Modify: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets`

**Produces:** `solveVerticalMultiply(a: number, b: number): VerticalMathSolution` — assumes `b ∈ [0, 9]`. Output structure:

- Initial rows: `A`, `×` operator row (with B right-aligned in units column), first line.
- Step 0 (alignment): same as initial, no narration highlights.
- Steps 1..N (one per digit of A from right to left): each step adds one partial-product row, aligned such that the units partial product occupies `[col_units, col_tens]`, the tens partial product occupies `[col_tens, col_hundreds]`, etc. NO red carry markers — the partial product's own 10s digit is the carry information. Multiplier (`B`) highlights in yellow together with the current multiplicand digit.
- Final step: second horizontal line + result row.

For `988 × 6`:
- A digits right-to-left: 8 (units), 8 (tens), 9 (hundreds).
- Partial product 1 (units × 6): `8×6=48` → cells `[col_tens='4', col_units='8']`.
- Partial product 2 (tens × 6): `8×6=48` → cells `[col_hundreds='4', col_tens='8']`, the other two cells are blank.
- Partial product 3 (hundreds × 6): `9×6=54` → cells `[col_thousands='5', col_hundreds='4']`, the other two cells are blank.
- Final result: `5 9 2 8` across four columns.

The number of columns = `digitsA + digitsB_result` where `digitsB_result` = digits of (max partial product). For `988 × 6`, `max(48, 48, 54)` = 2 digits, so columns = 3 + 2 - 1 = 4.

- [ ] **Step 4.1: Write failing tests.**

```ts
import { solveVerticalMultiply } from '../../../main/ets/utils/VerticalMathSolver'

// add inside the default export:

describe('solveVerticalMultiply', () => {
  it('988 × 6 = 5928 with three aligned partial products', 0, () => {
    const s = solveVerticalMultiply(988, 6)
    expect(s.result).assertEqual(5928)
    expect(s.columnCount).assertEqual(4)
    // Three intermediate rows (one per digit of 988). The final step adds the result.
    // Intermediate rows after first line should be at steps[1], [2], [3]
    const intermediateRows: string[] = []
    for (let i = 1; i <= 3; i++) {
      const lastDataRow = s.steps[i].rows[s.steps[i].rows.length - 1]
      intermediateRows.push(lastDataRow.cells.map(c => c === '' ? ' ' : c).join('').trimEnd())
    }
    expect(intermediateRows[0]).assertEqual('48')    // units
    expect(intermediateRows[1]).assertEqual('48')    // tens, shifted left
    expect(intermediateRows[2]).assertEqual('54')    // hundreds, shifted left twice
    // No separate red carry markers anywhere
    expect(s.steps.every(step => !step.rows.some(row => row.topMark === '1'))).assertEqual(true)
  })

  it('5 × 3 = 15 (single digit × single digit)', 0, () => {
    const s = solveVerticalMultiply(5, 3)
    expect(s.result).assertEqual(15)
    expect(s.columnCount).assertEqual(2)
  })

  it('123 × 0 = 0', 0, () => {
    const s = solveVerticalMultiply(123, 0)
    expect(s.result).assertEqual(0)
  })

  it('multiplier highlights pair with current multiplicand digit', 0, () => {
    const s = solveVerticalMultiply(988, 6)
    // For each non-alignment step, there should be exactly one highlight with kind='active'
    // pointing at the current digit of A (not B), AND the multiplier column also has an active highlight.
    const operatorRowIndex = 1
    for (let i = 1; i <= 3; i++) {
      const step = s.steps[i]
      const activeHighlights = step.highlights.filter(h => h.kind === 'active')
      // At least two actives: one for the multiplicand digit at row 0, one for multiplier at row 1.
      expect(activeHighlights.length >= 2).assertEqual(true)
      const onOperator = activeHighlights.some(h => h.rowIndex === operatorRowIndex)
      expect(onOperator).assertEqual(true)
    }
  })
})
```

- [ ] **Step 4.2: Run tests — expect compile error.**

- [ ] **Step 4.3: Implement `solveVerticalMultiply`.**

```ts
export function solveVerticalMultiply(a: number, b: number): VerticalMathSolution {
  const aStr = String(a)
  const digitsA = aStr.length
  const bStr = String(b)
  const digitsB = bStr.length

  // Pre-compute partial products (right to left). For 988 × 6: digits=[8,8,9], products=[48,48,54].
  const digits = aStr.split('').map(d => Number(d)).reverse()
  const products: number[] = digits.map(d => d * b)
  const maxProductDigits = Math.max(1, ...products.map(p => String(p).length))
  const columnCount = digitsA + maxProductDigits - 1
  // Place B in the rightmost columns of its row so it visually aligns with A's units.
  const bRowCells = new Array<string>(columnCount).fill('')
  for (let i = 0; i < digitsB; i++) {
    bRowCells[columnCount - digitsB + i] = bStr[i]
  }

  const aCells = aStr.padStart(columnCount, ' ').split('')
  const initialRows: VerticalMathBoardRow[] = [
    { cells: aCells.slice() },
    { cells: bRowCells.slice(), operator: '×' },
    { cells: new Array<string>(columnCount).fill('') }
  ]

  const steps: VerticalMathStep[] = []
  steps.push({
    title: '数位对齐',
    narration: `${a} 和 ${b} 各就各位，准备出发。`,
    rows: [
      { cells: aCells.slice() },
      { cells: bRowCells.slice(), operator: '×' },
      { cells: new Array<string>(columnCount).fill('') }
    ],
    highlights: []
  })

  const partialRows: VerticalMathBoardRow[] = []
  const labelForDigit = ['个', '十', '百', '千', '万']  // up to 5 digits, sufficient for 0–999
  for (let i = 0; i < digits.length; i++) {
    const product = products[i]
    const productStr = String(product).padStart(maxProductDigits, ' ')
    const cells = new Array<string>(columnCount).fill('')
    const shift = i  // shift left by i columns
    const startCol = columnCount - maxProductDigits - shift
    for (let j = 0; j < maxProductDigits; j++) {
      if (startCol + j >= 0 && startCol + j < columnCount) {
        cells[startCol + j] = productStr[j]
      }
    }
    const operator: string | undefined = i === digits.length - 1 ? '＋' : undefined
    partialRows.push({ cells, operator })
  }

  for (let i = 0; i < partialRows.length; i++) {
    const partial = partialRows[i]
    const snap: VerticalMathBoardRow[] = [
      { cells: aCells.slice() },
      { cells: bRowCells.slice(), operator: '×' },
      { cells: new Array<string>(columnCount).fill('') }
    ]
    for (let k = 0; k <= i; k++) snap.push(partialRows[k])
    const multiplicandCol = columnCount - 1 - i  // rightmost = units, then tens, etc.
    const multiplierCol = columnCount - digitsB
    const highlights: VerticalMathHighlight[] = [
      { rowIndex: 0, columnIndex: multiplicandCol, kind: 'active' },
      { rowIndex: 1, columnIndex: multiplierCol, kind: 'active' },
      { rowIndex: snap.length - 1, columnIndex: multiplicandCol, kind: 'active' }
    ]
    // Mark previous partials as done.
    for (let k = 0; k < i; k++) {
      for (let c = 0; c < columnCount; c++) {
        if (partialRows[k].cells[c] !== '') {
          highlights.push({ rowIndex: 3 + k, columnIndex: c, kind: 'done' })
        }
      }
    }
    const positionLabel = labelForDigit[i] ?? `第${i + 1}位`
    steps.push({
      title: `${positionLabel}：${digits[i]}×${b}=${products[i]}`,
      narration: i === 0
        ? `${positionLabel}：${digits[i]}×${b}=${products[i]}，部分积放在${i === 0 ? '十位和个位' : '对应位值格'}。`
        : `${positionLabel}：${digits[i]}×${b}=${products[i]}，部分积向左移动${i}格。`,
      rows: snap,
      highlights
    })
  }

  const resultStr = String(a * b).padStart(columnCount, ' ').split('')
  steps.push({
    title: '按位相加',
    narration: `把各位部分积按位相加，得到 ${a * b}。`,
    rows: [
      { cells: aCells.slice() },
      { cells: bRowCells.slice(), operator: '×' },
      { cells: new Array<string>(columnCount).fill('') },
      ...partialRows.map(r => ({ cells: r.cells.slice(), operator: r.operator })),
      { cells: resultStr.slice() }
    ],
    highlights: [],
    showFinalLine: true,
    showResultRow: true
  })

  return {
    operation: VerticalMathOperation.MULTIPLY,
    operandA: a,
    operandB: b,
    result: a * b,
    remainder: 0,
    columnCount,
    initialRows,
    steps,
    finalRow: { cells: resultStr }
  }
}
```

- [ ] **Step 4.4: Run tests in DevEco Studio — expect 4 new tests green; total 21/21.**

- [ ] **Step 4.5: Commit.**

```bash
git add entry/src/main/ets/utils/VerticalMathSolver.ets \
        entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets
git commit -m "feat(vertical-math): add multiplication solver with image-style partial products"
```

---

## Task 5: Division solver (long division 厂字形)

**Files:**
- Modify: `entry/src/main/ets/utils/VerticalMathSolver.ets`
- Modify: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets`

**Produces:** `solveVerticalDivide(a: number, b: number): VerticalMathSolution` — assumes `b ∈ [1, 9]`. Long division with one-digit divisor. Step sequence per "看首位 / 试商 / 乘 / 减 / 落位":

- `initialRows`: `A` on top, `÷` operator row with `B` right-aligned, 厂字形 left bracket (rendered as a tall `┐` glyph in column 0 covering A's row).
- Step 0 (alignment): A + 厂形 + first line.
- For each digit position `i` from leftmost of A:
  - "看首位": highlight the current partial-dividend window (cells `[start..i]`). If it is smaller than B, narration "首位不够除，先看下一位", no quotient digit rendered, skip to next i.
  - Else: "试商": quotient digit = floor(window / B). Add a row above the line showing the current quotient digit at column `i`.
  - "乘": product = quotient × B. Render below the dividend in columns `[start..i]`.
  - "减": subtract product from window. Render the new remainder in those columns.
  - "落位": move to `i+1`.

For `0 ÷ B`, quotient is `0`, remainder is `0`, single-digit result.

- [ ] **Step 5.1: Write failing tests.**

```ts
import { solveVerticalDivide } from '../../../main/ets/utils/VerticalMathSolver'

// add inside the default export:

describe('solveVerticalDivide', () => {
  it('84 ÷ 4 = 21 remainder 0', 0, () => {
    const s = solveVerticalDivide(84, 4)
    expect(s.result).assertEqual(21)
    expect(s.remainder).assertEqual(0)
  })

  it('85 ÷ 4 = 21 remainder 1', 0, () => {
    const s = solveVerticalDivide(85, 4)
    expect(s.result).assertEqual(21)
    expect(s.remainder).assertEqual(1)
  })

  it('3 ÷ 7 first digit < divisor (no leading zero)', 0, () => {
    const s = solveVerticalDivide(3, 7)
    expect(s.result).assertEqual(0)
    expect(s.remainder).assertEqual(3)
    // The narration should mention "首位不够除" at least once.
    expect(s.steps.some(step => step.narration.includes('首位不够除'))).assertEqual(true)
  })

  it('0 ÷ 5 = 0 remainder 0', 0, () => {
    const s = solveVerticalDivide(0, 5)
    expect(s.result).assertEqual(0)
    expect(s.remainder).assertEqual(0)
  })

  it('999 ÷ 9 = 111 remainder 0', 0, () => {
    const s = solveVerticalDivide(999, 9)
    expect(s.result).assertEqual(111)
    expect(s.remainder).assertEqual(0)
  })
})
```

- [ ] **Step 5.2: Run tests — expect compile error.**

- [ ] **Step 5.3: Implement `solveVerticalDivide`.**

```ts
export function solveVerticalDivide(a: number, b: number): VerticalMathSolution {
  const aStr = String(a)
  const digitsA = aStr.length
  const columnCount = digitsA  // dividend sets the column width
  const aCells = aStr.split('')
  const bRowCells = new Array<string>(columnCount).fill('')
  bRowCells[columnCount - 1] = String(b)  // single-digit divisor in units column

  const initialRows: VerticalMathBoardRow[] = [
    { cells: aCells.slice() },
    { cells: bRowCells.slice(), operator: '÷' },
    { cells: new Array<string>(columnCount).fill('') }
  ]

  const steps: VerticalMathStep[] = []
  steps.push({
    title: '数位对齐',
    narration: '用除数去除被除数，从最高位开始。',
    rows: [
      { cells: aCells.slice() },
      { cells: bRowCells.slice(), operator: '÷' },
      { cells: new Array<string>(columnCount).fill('') }
    ],
    highlights: []
  })

  // Simulate long division left-to-right. Track current remainder, current quotient digits, step rows.
  let remainder = 0
  const quotientDigits: string[] = new Array<string>(columnCount).fill('')
  const stepRows: VerticalMathBoardRow[] = []
  let anyQuotientDigit = false

  for (let i = 0; i < columnCount; i++) {
    const digit = Number(aCells[i])
    const window = remainder * 10 + digit
    if (window < b) {
      // "首位不够除，先看下一位" — render narration only (no quotient digit)
      stepRows.push({ cells: aCells.slice() })   // dividend row (unchanged)
      stepRows.push({ cells: bRowCells.slice(), operator: '÷' })
      stepRows.push({ cells: new Array<string>(columnCount).fill('') })
      stepRows.push({ cells: new Array<string>(columnCount).fill('') })  // product row (empty)
      stepRows.push({ cells: new Array<string>(columnCount).fill('') })  // remainder row (empty)
      steps.push({
        title: `第 ${i + 1} 位：不够除`,
        narration: '首位不够除，先看下一位。',
        rows: stepRows.slice(),
        highlights: [
          { rowIndex: 0, columnIndex: i, kind: 'active' },
          { rowIndex: 1, columnIndex: columnCount - 1, kind: 'active' }
        ]
      })
      // Pop the empty rows we just added so subsequent steps don't duplicate them.
      stepRows.length -= 4
      remainder = window
      continue
    }
    const q = Math.floor(window / b)
    const prod = q * b
    remainder = window - prod
    anyQuotientDigit = true
    quotientDigits[i] = String(q)

    // Build the quotient row snapshot (what's been written so far).
    const quotientRow: VerticalMathBoardRow = { cells: quotientDigits.slice() }
    // Product row aligned at columns [0..i] left-justified.
    const productCells = new Array<string>(columnCount).fill('')
    const prodStr = String(prod)
    for (let k = 0; k < prodStr.length; k++) productCells[i - prodStr.length + 1 + k] = prodStr[k]
    // Remainder row — after subtraction, only columns [0..i] may be non-zero.
    const remainderCells = new Array<string>(columnCount).fill('')
    if (remainder > 0) {
      const remStr = String(remainder)
      for (let k = 0; k < remStr.length; k++) remainderCells[i - remStr.length + 1 + k] = remStr[k]
    } else {
      remainderCells[i] = '0'
    }

    const snap: VerticalMathBoardRow[] = [
      { cells: aCells.slice() },
      { cells: bRowCells.slice(), operator: '÷' },
      { cells: new Array<string>(columnCount).fill('') },
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
      highlights
    })
  }

  const finalQuotient = anyQuotientDigit ? quotientDigits.join('').replace(/^0+/, '') || '0' : '0'
  steps.push({
    title: '得到答案',
    narration: remainder === 0
      ? `${a} ÷ ${b} = ${finalQuotient}。`
      : `${a} ÷ ${b} = ${finalQuotient}，余数 ${remainder}。`,
    rows: [
      { cells: aCells.slice() },
      { cells: bRowCells.slice(), operator: '÷' },
      { cells: new Array<string>(columnCount).fill('') },
      { cells: quotientDigits.slice() }
    ],
    highlights: [],
    showFinalLine: true,
    showResultRow: true
  })

  return {
    operation: VerticalMathOperation.DIVIDE,
    operandA: a,
    operandB: b,
    result: Number(finalQuotient),
    remainder,
    columnCount,
    initialRows,
    steps,
    finalRow: { cells: quotientDigits.slice() }
  }
}
```

- [ ] **Step 5.4: Run tests — expect 26/26 green.**

If `3 ÷ 7` fails because the step pushes duplicate rows: re-check the `stepRows.length -= 4` reset (only the "not enough" path mutates `stepRows`, the successful path rebuilds `snap` from scratch).

- [ ] **Step 5.5: Commit.**

```bash
git add entry/src/main/ets/utils/VerticalMathSolver.ets \
        entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets
git commit -m "feat(vertical-math): add division solver with long-division steps"
```

---

## Task 6: Solver orchestrator `solveVerticalMath`

**Files:**
- Modify: `entry/src/main/ets/utils/VerticalMathSolver.ets`
- Modify: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets`

**Produces:** `solveVerticalMath(operation, operandA, operandB): VerticalMathSolution`. Validates inputs first; on validation error returns a solution whose `errorMessage` is set and whose `steps` is empty (caller renders the error message instead of the board). On valid inputs, dispatches to the four operation-specific solvers.

- [ ] **Step 6.1: Write failing tests.**

```ts
import { solveVerticalMath } from '../../../main/ets/utils/VerticalMathSolver'

// add inside the default export:

describe('solveVerticalMath orchestrator', () => {
  it('dispatches to addition', 0, () => {
    const s = solveVerticalMath(VerticalMathOperation.ADD, 47, 28)
    expect(s.operation).assertEqual(VerticalMathOperation.ADD)
    expect(s.result).assertEqual(75)
    expect(s.errorMessage === undefined).assertEqual(true)
  })

  it('dispatches to subtraction', 0, () => {
    const s = solveVerticalMath(VerticalMathOperation.SUBTRACT, 503, 278)
    expect(s.result).assertEqual(225)
  })

  it('dispatches to multiplication', 0, () => {
    const s = solveVerticalMath(VerticalMathOperation.MULTIPLY, 988, 6)
    expect(s.result).assertEqual(5928)
  })

  it('dispatches to division', 0, () => {
    const s = solveVerticalMath(VerticalMathOperation.DIVIDE, 85, 4)
    expect(s.result).assertEqual(21)
    expect(s.remainder).assertEqual(1)
  })

  it('returns a validation-error solution on illegal inputs', 0, () => {
    const s = solveVerticalMath(VerticalMathOperation.SUBTRACT, 5, 50)
    expect(s.errorMessage !== undefined).assertEqual(true)
    expect(s.steps.length).assertEqual(0)
  })
})
```

- [ ] **Step 6.2: Run tests — expect compile error.**

- [ ] **Step 6.3: Implement `solveVerticalMath`.**

```ts
export function solveVerticalMath(
  operation: VerticalMathOperation,
  operandA: number,
  operandB: number
): VerticalMathSolution {
  const validationError = validateVerticalMathInputs(operation, operandA, operandB)
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
    case VerticalMathOperation.ADD:      return solveVerticalAdd(operandA, operandB)
    case VerticalMathOperation.SUBTRACT: return solveVerticalSubtract(operandA, operandB)
    case VerticalMathOperation.MULTIPLY: return solveVerticalMultiply(operandA, operandB)
    case VerticalMathOperation.DIVIDE:   return solveVerticalDivide(operandA, operandB)
  }
}
```

- [ ] **Step 6.4: Run tests — expect 31/31 green (10 validation + 4 add + 3 sub + 4 mul + 5 div + 5 orchestrator).**

- [ ] **Step 6.5: Commit.**

```bash
git add entry/src/main/ets/utils/VerticalMathSolver.ets \
        entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets
git commit -m "feat(vertical-math): add solveVerticalMath orchestrator"
```

---

## Task 7: Color constants for the adventure theme

**Files:**
- Create: `entry/src/main/ets/utils/VerticalMathColors.ets`

Pure constant file — no logic, no UI. Keeps theme palette colocated with the solver output it will style.

- [ ] **Step 7.1: Create the file.**

```ts
// utils/VerticalMathColors.ets
export const VERTICAL_MATH_BOARD_BG_START: string = '#6448b5'
export const VERTICAL_MATH_BOARD_BG_MID: string = '#3a2877'
export const VERTICAL_MATH_BOARD_BG_END: string = '#27194f'

export const VERTICAL_MATH_BOARD_TEXT: string = '#ffffff'
export const VERTICAL_MATH_BOARD_LINE: string = 'rgba(255, 255, 255, 0.9)'

export const VERTICAL_MATH_ACTIVE_BG: string = '#ffe66d'
export const VERTICAL_MATH_ACTIVE_TEXT: string = '#3a2d0c'

export const VERTICAL_MATH_DONE_TEXT: string = '#b9f2d0'
export const VERTICAL_MATH_DONE_BG: string = 'rgba(185, 242, 208, 0.18)'

export const VERTICAL_MATH_CARRY_TEXT: string = '#ff6b6b'

export const VERTICAL_MATH_ERROR_BG: string = '#ffe3dc'
export const VERTICAL_MATH_ERROR_TEXT: string = '#89564b'

export const VERTICAL_MATH_NARRATOR_BG: string = 'rgba(255, 250, 240, 0.86)'
export const VERTICAL_MATH_NARRATOR_ACTIVE_BG: string = '#fff1a5'
export const VERTICAL_MATH_NARRATOR_ACTIVE_TEXT: string = '#5b4811'
export const VERTICAL_MATH_NARRATOR_DONE_BG: string = '#e2f8e9'
export const VERTICAL_MATH_NARRATOR_DONE_TEXT: string = '#27764b'
```

- [ ] **Step 7.2: Build verification (catches typos before they ripple into the UI).**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```
Expected: build succeeds.

- [ ] **Step 7.3: Commit.**

```bash
git add entry/src/main/ets/utils/VerticalMathColors.ets
git commit -m "feat(vertical-math): add adventure theme color constants"
```

---

## Task 8: VerticalMathBoardRow cell component

**Files:**
- Create: `entry/src/main/ets/components/verticalMath/VerticalMathBoardRow.ets`

Stateless renderer for a single row of digit cells. Used by `VerticalMathBoard` (Task 9) to avoid duplicating the cell-rendering loop. Per ArkUI V2 reactivity rule, this component reads `highlight.kind` directly in its `@Builder` — no string-snapshot pass-through.

- [ ] **Step 8.1: Create the component.**

```ts
// components/verticalMath/VerticalMathBoardRow.ets
import {
  VERTICAL_MATH_BOARD_TEXT,
  VERTICAL_MATH_ACTIVE_BG,
  VERTICAL_MATH_ACTIVE_TEXT,
  VERTICAL_MATH_DONE_TEXT,
  VERTICAL_MATH_DONE_BG,
  VERTICAL_MATH_CARRY_TEXT
} from '../../utils/VerticalMathColors'
import {
  VerticalMathBoardRow as RowModel,
  VerticalMathHighlight
} from '../../utils/VerticalMathSolver'

@ComponentV2
export struct VerticalMathBoardRowView {
  @Param row: RowModel = new RowModel()
  @Param rowIndex: number = 0
  @Param highlights: VerticalMathHighlight[] = []
  @Param cellSize: number = 36
  @Param columnCount: number = 1

  @Builder
  private CellGlyph(text: string, colIndex: number) {
    Stack() {
      if (text === ' ') {
        Text('').width(this.cellSize)
      } else {
        Text(text)
          .fontSize(this.cellSize * 0.62)
          .fontWeight(FontWeight.Bold)
          .fontFamily('ui-monospace, SFMono-Regular, Menlo, monospace')
          .fontColor(VERTICAL_MATH_BOARD_TEXT)
          .width(this.cellSize)
          .textAlign(TextAlign.Center)
      }
    }
    .width(this.cellSize)
    .height(this.cellSize)
    .borderRadius(8)
  }

  build() {
    Row() {
      if (this.row.operator !== undefined && this.row.operator !== '') {
        Text(this.row.operator)
          .fontSize(this.cellSize * 0.62)
          .fontWeight(FontWeight.Bold)
          .fontColor(VERTICAL_MATH_BOARD_TEXT)
          .width(this.cellSize)
          .height(this.cellSize)
          .textAlign(TextAlign.Center)
      } else {
        Text('').width(this.cellSize).height(this.cellSize)
      }
      ForEach(this.row.cells, (cell: string, idx: number) => {
        this.CellGlyph(cell, idx)
      }, (cell: string, idx: number) => `${this.rowIndex}_${idx}_${cell}`)
    }
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Start)
  }
}
```

- [ ] **Step 8.2: Build verification.**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```
Expected: build succeeds. If ArkTS complains about the inline `this.CellGlyph(...)` call, move the inner `@Builder` to a module-private `@Builder function` (no closures needed) — pattern is used elsewhere in `NumberPuzzleCard.ets`.

- [ ] **Step 8.3: Commit.**

```bash
git add entry/src/main/ets/components/verticalMath/VerticalMathBoardRow.ets
git commit -m "feat(vertical-math): add VerticalMathBoardRow cell component"
```

---

## Task 9: VerticalMathBoard blackboard component

**Files:**
- Create: `entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets`

Renders the full blackboard given a `VerticalMathSolution` and a `visibleStepCount`. At `visibleStepCount === 0`, shows `initialRows`. At `visibleStepCount > 0`, shows `steps[visibleStepCount - 1].rows`. Highlights come from the active step. Applies yellow background to active cells, mint color to done cells, red to carry topMarks, and shows borrow `•` above the row.

- [ ] **Step 9.1: Create the board component.**

```ts
// components/verticalMath/VerticalMathBoard.ets
import {
  VERTICAL_MATH_BOARD_BG_START,
  VERTICAL_MATH_BOARD_BG_MID,
  VERTICAL_MATH_BOARD_BG_END,
  VERTICAL_MATH_BOARD_TEXT,
  VERTICAL_MATH_BOARD_LINE,
  VERTICAL_MATH_ACTIVE_BG,
  VERTICAL_MATH_ACTIVE_TEXT,
  VERTICAL_MATH_DONE_TEXT,
  VERTICAL_MATH_DONE_BG,
  VERTICAL_MATH_CARRY_TEXT
} from '../../utils/VerticalMathColors'
import {
  VerticalMathSolution,
  VerticalMathBoardRow,
  VerticalMathHighlight
} from '../../utils/VerticalMathSolver'
import { VerticalMathBoardRowView } from './VerticalMathBoardRow'

@ComponentV2
export struct VerticalMathBoard {
  @Param solution: VerticalMathSolution = new VerticalMathSolution()
  @Param visibleStepCount: number = 0
  @Param compact: boolean = false

  private getCurrentRows(): VerticalMathBoardRow[] {
    if (this.solution.steps.length === 0 || this.visibleStepCount === 0) {
      return this.solution.initialRows
    }
    const idx = Math.min(this.visibleStepCount - 1, this.solution.steps.length - 1)
    return this.solution.steps[idx].rows
  }

  private getCurrentHighlights(): VerticalMathHighlight[] {
    if (this.solution.steps.length === 0 || this.visibleStepCount === 0) return []
    const idx = Math.min(this.visibleStepCount - 1, this.solution.steps.length - 1)
    return this.solution.steps[idx].highlights
  }

  private getShowFinalLine(): boolean {
    if (this.solution.steps.length === 0 || this.visibleStepCount === 0) return false
    const idx = Math.min(this.visibleStepCount - 1, this.solution.steps.length - 1)
    return this.solution.steps[idx].showFinalLine === true
  }

  build() {
    Stack() {
      // Background gradient
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 145,
          colors: [
            [VERTICAL_MATH_BOARD_BG_START, 0.0],
            [VERTICAL_MATH_BOARD_BG_MID, 0.66],
            [VERTICAL_MATH_BOARD_BG_END, 1.0]
          ]
        })
        .borderRadius(20)
        .opacity(1)

      // Board content
      Column() {
        const rows = this.getCurrentRows()
        const highlights = this.getCurrentHighlights()
        ForEach(rows, (row: VerticalMathBoardRow, rowIndex: number) => {
          Column() {
            // Top mark (carry or borrow) row, if any
            if (row.topMark !== undefined && row.topMark !== '') {
              Row() {
                Text('').width(36)
                Text(row.topMark)
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(row.topMark === '•' ? VERTICAL_MATH_BOARD_TEXT : VERTICAL_MATH_CARRY_TEXT)
                  .width(36)
              }
              .justifyContent(FlexAlign.Start)
            }
            VerticalMathBoardRowView({
              row: row,
              rowIndex: rowIndex,
              highlights: highlights.filter(h => h.rowIndex === rowIndex),
              cellSize: this.compact ? 32 : 40,
              columnCount: this.solution.columnCount
            })
            // Horizontal line under the row when this is the "first line" (initialRows[2]) OR when showFinalLine applies at the end.
            if (rowIndex === 2 || (this.getShowFinalLine() && rowIndex === rows.length - 2)) {
              Row()
                .height(4)
                .margin({ left: 36, right: 8, top: 4, bottom: 4 })
                .backgroundColor(VERTICAL_MATH_BOARD_LINE)
                .borderRadius(2)
            }
          }
        }, (row: VerticalMathBoardRow, rowIndex: number) => `row_${rowIndex}`)
      }
      .padding(20)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
  }
}
```

- [ ] **Step 9.2: Build verification.**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

If ArkTS complains that `let` is not allowed inside `Column` builder, replace with `const` and rewrap the `getCurrentRows()` call in a private method. Iterate until build is green.

- [ ] **Step 9.3: Commit.**

```bash
git add entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets
git commit -m "feat(vertical-math): add VerticalMathBoard blackboard renderer"
```

---

## Task 10: VerticalMathStepNarrator component

**Files:**
- Create: `entry/src/main/ets/components/verticalMath/VerticalMathStepNarrator.ets`

Renders the right-side (or below-board, on mobile) step list. Each step has a "n / total" badge, a title, and the narration text. Steps ≤ `visibleStepCount` are marked done (mint); the step at `visibleStepCount` (if any) is marked active (yellow). The list auto-scrolls to the latest active step via `Scroller.scrollToIndex`.

- [ ] **Step 10.1: Create the narrator component.**

```ts
// components/verticalMath/VerticalMathStepNarrator.ets
import {
  VERTICAL_MATH_NARRATOR_BG,
  VERTICAL_MATH_NARRATOR_ACTIVE_BG,
  VERTICAL_MATH_NARRATOR_ACTIVE_TEXT,
  VERTICAL_MATH_NARRATOR_DONE_BG,
  VERTICAL_MATH_NARRATOR_DONE_TEXT
} from '../../utils/VerticalMathColors'
import { VerticalMathStep } from '../../utils/VerticalMathSolver'

@ComponentV2
export struct VerticalMathStepNarrator {
  @Param steps: VerticalMathStep[] = []
  @Param visibleStepCount: number = 0
  @Param operationLabel: string = ''

  private listScroller: Scroller = new Scroller()

  aboutToAppear() {
    // Scroll to active step after layout settles.
    setTimeout(() => {
      const active = Math.max(0, Math.min(this.visibleStepCount - 1, this.steps.length - 1))
      this.listScroller.scrollToIndex(active, true, ScrollAlign.CENTER)
    }, 50)
  }

  aboutToUpdate() {
    const active = Math.max(0, Math.min(this.visibleStepCount - 1, this.steps.length - 1))
    this.listScroller.scrollToIndex(active, true, ScrollAlign.CENTER)
  }

  @Builder
  private StepCard(step: VerticalMathStep, index: number) {
    const isDone = index < this.visibleStepCount
    const isActive = index === this.visibleStepCount - 1
    Row() {
      Text(isDone ? '✓' : `${index + 1}`)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(isDone ? VERTICAL_MATH_NARRATOR_DONE_TEXT : '#6954a5')
        .width(22)
        .height(22)
        .borderRadius(11)
        .backgroundColor(isDone ? VERTICAL_MATH_NARRATOR_DONE_BG : '#dcd0ff')
        .textAlign(TextAlign.Center)
      Column() {
        Text(step.title)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(isActive ? VERTICAL_MATH_NARRATOR_ACTIVE_TEXT : (isDone ? VERTICAL_MATH_NARRATOR_DONE_TEXT : '#62577d'))
        if (step.narration !== '') {
          Text(step.narration)
            .fontSize(12)
            .fontColor(isActive ? VERTICAL_MATH_NARRATOR_ACTIVE_TEXT : (isDone ? VERTICAL_MATH_NARRATOR_DONE_TEXT : '#62577d'))
            .margin({ top: 4 })
            .lineHeight(16)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 8 })
    }
    .padding(11)
    .borderRadius(13)
    .backgroundColor(isActive ? VERTICAL_MATH_NARRATOR_ACTIVE_BG : (isDone ? VERTICAL_MATH_NARRATOR_DONE_BG : '#f1ecff'))
    .margin({ bottom: 8 })
  }

  build() {
    Column() {
      Text(this.operationLabel)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#21153f')
        .margin({ bottom: 12 })
      List({ scroller: this.listScroller }) {
        ForEach(this.steps, (step: VerticalMathStep, index: number) => {
          ListItem() {
            this.StepCard(step, index)
          }
        }, (step: VerticalMathStep, index: number) => `step_${index}`)
      }
      .width('100%')
      .layoutWeight(1)
      .listDirection(Axis.Vertical)
      .scrollBar(BarState.Off)
    }
    .padding(16)
    .backgroundColor(VERTICAL_MATH_NARRATOR_BG)
    .borderRadius(20)
    .height('100%')
  }
}
```

- [ ] **Step 10.2: Build verification (catches ArkUI strict-mode mistakes).**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```
Expected: build succeeds. If `ForEach` complains about returning a constructed `ListItem` object (no inline `{...}` allowed), move into a method.

- [ ] **Step 10.3: Commit.**

```bash
git add entry/src/main/ets/components/verticalMath/VerticalMathStepNarrator.ets
git commit -m "feat(vertical-math): add step narrator with active/done states"
```

---

## Task 11: VerticalMathCard shell

**Files:**
- Create: `entry/src/main/ets/components/VerticalMathCard.ets`

Owns all interactive state: `operandA`, `operandB`, `selectedOperation`, `solution`, `visibleStepCount`, `errorMessage`, `isCompleted`. Renders input form (numeric text fields + operation chooser + 开始计算 button), control row (上一步 / 下一步 / 重置), then Board + Narrator. On full completion, calls `onAnswer(toolCallId, JSON.stringify(result))` exactly once.

- [ ] **Step 11.1: Create the card component — contract MUST mirror `MathQuizCard` (Task 15 expects `@Param toolCall: ToolCall`).**

```ts
// components/VerticalMathCard.ets
import { ToolCall } from '../models/ChatModels'
import {
  solveVerticalMath,
  VerticalMathOperation,
  VerticalMathSolution,
  VerticalMathValidationError
} from '../utils/VerticalMathSolver'
import {
  VERTICAL_MATH_ERROR_BG,
  VERTICAL_MATH_ERROR_TEXT
} from '../utils/VerticalMathColors'
import { VerticalMathBoard } from './verticalMath/VerticalMathBoard'
import { VerticalMathStepNarrator } from './verticalMath/VerticalMathStepNarrator'

interface VerticalMathResultPayload {
  completed: boolean
  operation: string
  operand_a: number
  operand_b: number
  result: number
  remainder: number
  step_count: number
}

@ComponentV2
export struct VerticalMathCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false

  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local operandA: string = ''
  @Local operandB: string = ''
  @Local selectedOperation: VerticalMathOperation = VerticalMathOperation.ADD
  @Local solution: VerticalMathSolution | null = null
  @Local visibleStepCount: number = 0
  @Local errorMessage: string = ''
  @Local hasAnswered: boolean = false

  aboutToAppear() {
    this.parseToolCallArguments()
    if (this.isAnswered) {
      // Pre-compute solution so the user can walk through it again.
      this.regenerateSolution()
    }
  }

  private parseToolCallArguments() {
    try {
      const args: Record<string, Object> = JSON.parse(this.toolCall.arguments ?? '{}') as Record<string, Object>
      const op = args['operation']
      if (typeof op === 'string') {
        switch (op) {
          case 'add': this.selectedOperation = VerticalMathOperation.ADD; break
          case 'subtract': this.selectedOperation = VerticalMathOperation.SUBTRACT; break
          case 'multiply': this.selectedOperation = VerticalMathOperation.MULTIPLY; break
          case 'divide': this.selectedOperation = VerticalMathOperation.DIVIDE; break
        }
      }
      const a = args['operand_a']
      if (typeof a === 'number' && a >= 0) this.operandA = String(a)
      const b = args['operand_b']
      if (typeof b === 'number' && b >= 0) this.operandB = String(b)
    } catch (_e) {
      // Malformed arguments → leave defaults (empty inputs, ADD).
    }
  }

  private regenerateSolution() {
    const a = Number(this.operandA)
    const b = Number(this.operandB)
    const sol = solveVerticalMath(this.selectedOperation, a, b)
    if (sol.errorMessage !== undefined && sol.errorMessage !== '') {
      this.errorMessage = sol.errorMessage
      this.solution = null
      this.visibleStepCount = 0
      return
    }
    this.errorMessage = ''
    this.solution = sol
    this.visibleStepCount = 0
  }

  private handleStart() {
    this.regenerateSolution()
  }

  private handleNext() {
    if (this.solution === null) return
    if (this.visibleStepCount < this.solution.steps.length) {
      this.visibleStepCount++
    }
    if (this.solution !== null && this.visibleStepCount === this.solution.steps.length && !this.hasAnswered) {
      this.hasAnswered = true
      const payload: VerticalMathResultPayload = {
        completed: true,
        operation: this.selectedOperation,
        operand_a: Number(this.operandA),
        operand_b: Number(this.operandB),
        result: this.solution.result,
        remainder: this.solution.remainder,
        step_count: this.visibleStepCount
      }
      this.onAnswer(this.toolCall.id, JSON.stringify(payload))
    }
  }

  private handlePrev() {
    if (this.visibleStepCount > 0) {
      this.visibleStepCount--
    }
  }

  private handleReset() {
    this.visibleStepCount = 0
  }

  private handleInputA(value: string) {
    const filtered = value.replace(/[^0-9]/g, '').slice(0, 3)
    this.operandA = filtered
  }

  private handleInputB(value: string) {
    const filtered = value.replace(/[^0-9]/g, '').slice(0, 3)
    this.operandB = filtered
  }

  private operationSymbol(op: VerticalMathOperation): string {
    switch (op) {
      case VerticalMathOperation.ADD: return '＋'
      case VerticalMathOperation.SUBTRACT: return '－'
      case VerticalMathOperation.MULTIPLY: return '×'
      case VerticalMathOperation.DIVIDE: return '÷'
    }
  }

  private canStart(): boolean {
    return this.operandA.length > 0 && this.operandB.length > 0
  }

  private isCompact(): boolean {
    // Phone-narrow detection is delegated to the parent; largeSize==false means inline.
    return !this.largeSize
  }

  @Builder
  private InputForm() {
    Column() {
      Row() {
        TextInput({ text: this.operandA, placeholder: 'A' })
          .type(InputType.Number)
          .width(80)
          .height(44)
          .onChange((v: string) => this.handleInputA(v))
        Text(this.operationSymbol(this.selectedOperation))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 8, right: 8 })
        TextInput({ text: this.operandB, placeholder: 'B' })
          .type(InputType.Number)
          .width(80)
          .height(44)
          .onChange((v: string) => this.handleInputB(v))
      }
      .alignItems(VerticalAlign.Center)

      Row() {
        ForEach([
          { label: '＋', op: VerticalMathOperation.ADD },
          { label: '－', op: VerticalMathOperation.SUBTRACT },
          { label: '×', op: VerticalMathOperation.MULTIPLY },
          { label: '÷', op: VerticalMathOperation.DIVIDE }
        ], (item: { label: string; op: VerticalMathOperation }) => {
          Button(item.label)
            .height(44)
            .padding({ left: 12, right: 12 })
            .margin({ right: 6 })
            .backgroundColor(this.selectedOperation === item.op ? '#ffe66d' : '#eee8ff')
            .fontColor(this.selectedOperation === item.op ? '#3a2d0c' : '#30205f')
            .onClick(() => { this.selectedOperation = item.op })
        }, (item: { label: string; op: VerticalMathOperation }) => item.label)
      }
      .margin({ top: 12 })

      Button('开始计算')
        .height(44)
        .width('100%')
        .margin({ top: 12 })
        .backgroundColor('#ffe66d')
        .fontColor('#3a2d0c')
        .enabled(this.canStart())
        .onClick(() => this.handleStart())
    }
    .padding(12)
    .backgroundColor(this.largeSize ? Color.Transparent : '#fffaf0')
    .borderRadius(14)
  }

  @Builder
  private Controls() {
    Row() {
      Button('← 上一步')
        .height(44)
        .layoutWeight(1)
        .margin({ right: 8 })
        .backgroundColor('#eee8ff')
        .fontColor('#30205f')
        .enabled(this.visibleStepCount > 0)
        .onClick(() => this.handlePrev())
      Button('下一步 →')
        .height(44)
        .layoutWeight(1)
        .margin({ right: 8 })
        .backgroundColor('#ffe66d')
        .fontColor('#3a2d0c')
        .enabled(this.solution !== null && this.visibleStepCount < this.solution.steps.length)
        .onClick(() => this.handleNext())
      Button('重置')
        .height(44)
        .layoutWeight(1)
        .backgroundColor('#ffe3dc')
        .fontColor('#89564b')
        .onClick(() => this.handleReset())
    }
    .padding(12)
  }

  build() {
    Column() {
      // Header
      Row() {
        Text('🧮 小小数学家 · 竖式闯关')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#21153f')
          .layoutWeight(1)
        if (this.solution !== null && this.solution.steps.length > 0) {
          Text(this.visibleStepCount === this.solution.steps.length
            ? `闯关完成 · ${this.visibleStepCount} / ${this.solution.steps.length}`
            : `第 ${this.visibleStepCount} / ${this.solution.steps.length} 步`)
            .fontSize(12)
            .fontColor('#665b84')
        }
      }
      .padding({ left: 14, right: 14, top: 12, bottom: 8 })

      // Error banner
      if (this.errorMessage !== '') {
        Row() {
          Text(this.errorMessage)
            .fontSize(13)
            .fontColor(VERTICAL_MATH_ERROR_TEXT)
            .layoutWeight(1)
        }
        .padding(11)
        .backgroundColor(VERTICAL_MATH_ERROR_BG)
        .borderRadius(12)
        .margin({ left: 14, right: 14, bottom: 8 })
      }

      // Input form (always visible when no solution)
      if (this.solution === null) {
        this.InputForm()
      }

      // Controls (always visible when solution exists)
      if (this.solution !== null) {
        this.Controls()
        // Board + narrator
        if (this.isCompact()) {
          // Stacked layout (mobile)
          Column() {
            VerticalMathBoard({
              solution: this.solution,
              visibleStepCount: this.visibleStepCount,
              compact: true
            })
            .height('60%')
            VerticalMathStepNarrator({
              steps: this.solution.steps,
              visibleStepCount: this.visibleStepCount,
              operationLabel: `第 ${this.visibleStepCount} / ${this.solution.steps.length} 步`
            })
            .height('40%')
          }
          .layoutWeight(1)
          .padding({ left: 12, right: 12, bottom: 12 })
        } else {
          // 70/30 layout (tablet / largeSize)
          Row() {
            VerticalMathBoard({
              solution: this.solution,
              visibleStepCount: this.visibleStepCount,
              compact: false
            })
            .layoutWeight(7)
            VerticalMathStepNarrator({
              steps: this.solution.steps,
              visibleStepCount: this.visibleStepCount,
              operationLabel: `第 ${this.visibleStepCount} / ${this.solution.steps.length} 步`
            })
            .layoutWeight(3)
          }
          .layoutWeight(1)
          .padding(12)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.largeSize ? Color.Transparent : '#f4efff')
  }
}
```

- [ ] **Step 11.2: Build verification.**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

Iterate until green. Likely failure modes (from `CLAUDE.md` "已知踩坑"):
- Inline `{ label, op }` object inside `ForEach` callback — wrap in a method returning a typed object.
- `Row.alignItems` set to `HorizontalAlign` instead of `VerticalAlign` — fix per project rule.
- `@Builder` body returning a constructed object literal — use a private method instead.

- [ ] **Step 11.3: Commit.**

```bash
git add entry/src/main/ets/components/VerticalMathCard.ets
git commit -m "feat(vertical-math): add VerticalMathCard shell with state and input form"
```

---

## Task 12: Tool ID constant + identity functions

**Files:**
- Modify: `entry/src/main/ets/utils/SearchToolIdentityUtils.ets`

- [ ] **Step 12.1: Add the constant next to the existing tool IDs.**

Find the existing constant block (around line 14 — `CATEGORIZATION_TOOL_ID: string = 'categorization'`). Add directly after it:

```ts
export const VERTICAL_MATH_TOOL_ID: string = 'vertical_math'
```

- [ ] **Step 12.2: Add the function-name matcher next to `isCategorizationFunctionName`.**

After the closing `}` of `isCategorizationFunctionName` (around line 105):

```ts
export function isVerticalMathFunctionName(functionName: string): boolean {
  const normalized = normalizeToolFunctionName(functionName)
  return normalized === VERTICAL_MATH_TOOL_ID
}

export function isVerticalMathToolId(toolId: string): boolean {
  const normalized = normalizeToolFunctionName(toolId)
  return normalized === VERTICAL_MATH_TOOL_ID
}
```

- [ ] **Step 12.3: Build verification.**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

- [ ] **Step 12.4: Commit.**

```bash
git add entry/src/main/ets/utils/SearchToolIdentityUtils.ets
git commit -m "feat(vertical-math): register VERTICAL_MATH_TOOL_ID + identity functions"
```

---

## Task 13: Register `vertical_math` in BuiltinTools

**Files:**
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`

The tool schema mirrors `categorization_helper` (compare to its block around line 1676 in the existing file). Use Chinese corner brackets `「」` in description strings, NOT ASCII `"`.

- [ ] **Step 13.1: Find the `categorization` tool block.**

```bash
grep -n "categorization" /Users/mac/mygame/HarmonyOS-app/chatcube/entry/src/main/ets/config/BuiltinTools.ets | head -10
```
Identify the full block (schema registration + `registerTool(...)` call).

- [ ] **Step 13.2: Add the `vertical_math` tool block right after the categorization registration.**

Copy the full categorization schema + registerTool call as a template, then modify:

```ts
{
  name: 'vertical_math',
  description: '「小学竖式闯关」：输入两个 0–999 之间的整数和孩子选择的加减乘除，AI 引导孩子按位算出标准小学竖式。Use this tool INSTEAD of writing math problems in plain text whenever the child is practicing vertical arithmetic.',
  rawSchemaJson: `{
    "type": "object",
    "properties": {
      "operation": {
        "type": "string",
        "enum": ["add", "subtract", "multiply", "divide"],
        "description": "运算类型：add=加法、subtract=减法、multiply=乘法、divide=除法。"
      },
      "operand_a": {
        "type": "integer",
        "minimum": 0,
        "maximum": 999,
        "description": "第一个数（被加数/被减数/被乘数/被除数），0–999。允许省略让孩子自行填入。"
      },
      "operand_b": {
        "type": "integer",
        "minimum": 0,
        "maximum": 999,
        "description": "第二个数（加数/减数/乘数/除数），0–999。乘法限制 0–9、除法限制 1–9。允许省略。"
      }
    },
    "required": [],
    "additionalProperties": false
  }`
}
```

Then add a `registerTool(...)` call that mirrors the categorization one, pointing at `VERTICAL_MATH_TOOL_ID`. The executor function inside the call should be a thin shim that records the call as pending (the heavy lifting is done in `ToolExecutionService.handleVerticalMath` — Task 14).

- [ ] **Step 13.3: Verify the schema parses.**

```bash
node -e "
const fs = require('fs');
const src = fs.readFileSync('entry/src/main/ets/config/BuiltinTools.ets', 'utf-8');
const i = src.indexOf(\"'vertical_math'\");
const j = src.indexOf('\`{', i);
const k = src.indexOf('\`}', j) + 2;
const schemaText = src.substring(j + 1, k - 1);
console.log('Parsed:', JSON.parse(schemaText));
"
```

Expected: prints a JSON object with `operation`/`operand_a`/`operand_b` properties. If parse fails, the description strings contain an unescaped `"` — replace with `「」` per project rule.

- [ ] **Step 13.4: Build verification.**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

- [ ] **Step 13.5: Commit.**

```bash
git add entry/src/main/ets/config/BuiltinTools.ets
git commit -m "feat(vertical-math): register vertical_math tool schema"
```

---

## Task 14: Tool dispatch handler in ToolExecutionService

**Files:**
- Modify: `entry/src/main/ets/services/ToolExecutionService.ets`

Add a `handleVerticalMath(toolCall)` method (mirrors `handleHandwriting` shape: build a placeholder result JSON, mark the call as pending, wait for the card to call `resolvePendingAnswer`). Then wire it into the dispatch chain BEFORE the `resolveToolId` fallback so it gets priority.

- [ ] **Step 14.1: Locate the `handleHandwriting` and `handleCategorization` definitions.**

```bash
grep -n "handleHandwriting\|handleCategorization" /Users/mac/mygame/HarmonyOS-app/chatcube/entry/src/main/ets/services/ToolExecutionService.ets
```

- [ ] **Step 14.2: Add `handleVerticalMath` immediately after `handleHandwriting`.**

```ts
private handleVerticalMath(toolCall: ToolCall): ToolExecutionResult {
  // Vertical math is an interactive card: do NOT resolve immediately. The card calls
  // resolvePendingAnswer(toolCallId, ...) when the child finishes walking through steps.
  const pendingResult: string = JSON.stringify({
    status: 'pending',
    reason: 'vertical_math_interactive_card'
  })
  // Mirror handleHandwriting pattern: mark call as pending and emit completion with pendingResult.
  this.markPendingAndPublish(toolCall, pendingResult)
  return { resolved: true, result: pendingResult }
}
```

If `markPendingAndPublish` does not exist with that exact name in this file, copy the corresponding private helper used by `handleHandwriting` — the implementer must verify by reading the handler before writing this code.

- [ ] **Step 14.3: Wire into the dispatch chain (BEFORE the `resolveToolId` fallback).**

Find the existing dispatch block (around L1159-1210). Add a new branch:

```ts
if (isVerticalMathFunctionName(toolCall.functionName)) {
  return this.handleVerticalMath(toolCall)
}
```

Place this branch immediately after the existing `isCategorizationFunctionName` check (NOT after the `resolveToolId` fallback — that's the trap called out in the adding-mini-game-tool skill).

- [ ] **Step 14.4: Build verification.**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

- [ ] **Step 14.5: Commit.**

```bash
git add entry/src/main/ets/services/ToolExecutionService.ets
git commit -m "feat(vertical-math): add handleVerticalMath dispatch + wire into dispatch chain"
```

---

## Task 15: Mount `VerticalMathCard` in MessageBubble

**Files:**
- Modify: `entry/src/main/ets/components/MessageBubble.ets`

There are 7 surface sites per the adding-mini-game-tool skill. Do them in this order so each intermediate build is green:

- [ ] **Step 15.1: Add imports (top of file).**

Find the existing import line (around L40 — see summary above):
```ts
import { isSearchToolFunctionName, ..., isCategorizationFunctionName, isMusicGenerationFunctionName } from '../utils/SearchToolIdentityUtils'
```
Replace with (adding `isVerticalMathFunctionName`):
```ts
import { isSearchToolFunctionName, ..., isCategorizationFunctionName, isVerticalMathFunctionName, isMusicGenerationFunctionName } from '../utils/SearchToolIdentityUtils'
```

Find the `MathQuizCard` import (around L16):
```ts
import { MathQuizCard } from './MathQuizCard'
```
Add a new line below it:
```ts
import { VerticalMathCard } from './VerticalMathCard'
```

- [ ] **Step 15.2: Add the render branch (around L2030, sibling to MathQuizCard).**

```ts
if (this.shouldRenderVerticalMathInteractionCard(toolCall, index)) {
  VerticalMathCard({
    toolCall: toolCall,
    isAnswered: this.isToolCallAnswered(toolCall),
    answeredPayload: this.getAnsweredPayload(toolCall),
    largeSize: this.shouldUseLargeSize(),
    onAnswer: (id: string, json: string) => this.handleToolAnswer(id, json)
  })
}
```

Add the predicate method (near `shouldRenderMathQuizInteractionCard` at L2692):

```ts
private shouldRenderVerticalMathInteractionCard(toolCall: ToolCall, index: number): boolean {
  if (!isVerticalMathFunctionName(toolCall.functionName) || this.shouldHideToolCallCard(toolCall)) {
    return false
  }
  return true
}
```

(`handleToolAnswer`, `isToolCallAnswered`, `getAnsweredPayload`, `shouldUseLargeSize`, `shouldHideToolCallCard` already exist in this file — read the surrounding methods to confirm the exact signatures before calling them.)

- [ ] **Step 15.3: Extend the 6 remaining surface sites — append `isVerticalMathFunctionName(...)` to every existing chain.**

Use grep to find them:

```bash
grep -n "isCategorizationFunctionName" /Users/mac/mygame/HarmonyOS-app/chatcube/entry/src/main/ets/components/MessageBubble.ets
```

Each occurrence that sits inside an `if` or `&&` chain (lines 2548, 2619, 2629, 3069, 3510-3511, 3932 from the summary — confirm by reading the file) gets `|| isVerticalMathFunctionName(part.toolName)` appended at the end of its `||` chain. Do NOT add to comments or string literals.

- [ ] **Step 15.4: Build verification.**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

Expected: green. If a site needs `isVerticalMathFunctionName(step.toolName)` instead of `part.toolName`, follow the pattern of the surrounding lines.

- [ ] **Step 15.5: Commit.**

```bash
git add entry/src/main/ets/components/MessageBubble.ets
git commit -m "feat(vertical-math): mount VerticalMathCard in MessageBubble at 7 surface sites"
```

---

## Task 16: End-to-end build + manual smoke test

**Files:** (no source changes — verification only)

- [ ] **Step 16.1: Final clean build.**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw clean --mode module -p product=default
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```
Expected: `BUILD SUCCESSFUL`, `entry/build/default/outputs/default/entry-default-signed.hap` exists.

- [ ] **Step 16.2: Re-run all unit tests in DevEco Studio.**

Right-click `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets` → Run 'vertical_math_...' .
Expected: 31/31 tests pass.

- [ ] **Step 16.3: Manual smoke checklist (in DevEco Studio preview or on a device).**

Acceptance per spec §9:
- [ ] 开始计算后初始不显示步骤
- [ ] 第一次下一步显示「数位对齐」
- [ ] 上一步/下一步状态完全可逆
- [ ] 加法 47 + 28 显示进位 1 + 最终 75
- [ ] 减法 503 - 278 显示连续退位圆点和划线 + 最终 225
- [ ] 乘法 988 × 6 三行部分积按位值格对齐 + 最终 5928（无单独进位标记）
- [ ] 除法 85 ÷ 4 显示厂字形 + 商 21 余 1
- [ ] 除法 3 ÷ 7 显示「首位不够除，先看下一位」
- [ ] 步骤列表自动跟随最新步骤
- [ ] 减法 10 - 50 显示错误「不够减」
- [ ] 完成后只回传一次结果

- [ ] **Step 16.4: Commit the plan doc if not already committed.**

```bash
git add docs/superpowers/plans/2026-07-19-vertical-math-calculator.md
git commit -m "docs(vertical-math): add implementation plan"
```

---

## Self-review checklist

Before declaring the plan complete, the implementer verifies:

- [ ] Each task has exact file paths, complete code blocks, and verification commands.
- [ ] No "TBD" / "TODO" / "fill in details" / "similar to Task N" placeholders.
- [ ] Type / field names match across tasks (e.g., `VerticalMathSolution.errorMessage: string`, `onAnswer(toolCallId, answerJson)`).
- [ ] All 4 operations have solver tests with at least one carry/borrow/alignment edge case.
- [ ] The 7 MessageBubble surface sites are explicit (per the adding-mini-game-tool skill).
- [ ] `StarEventModels.ets` is NOT touched (per spec §2.1).
- [ ] Build command and test runner match the project's actual infrastructure (no `hvigorw lint`, no `hvigorw test` from CLI).

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-19-vertical-math-calculator.md`. Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, two-stage review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session with `superpowers:executing-plans`, batched execution with review checkpoints.

Which approach?