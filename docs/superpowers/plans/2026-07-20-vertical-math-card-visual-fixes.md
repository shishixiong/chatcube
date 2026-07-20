# Vertical Math Card Visual Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the deployed `VerticalMathCard` board visually match the chat bubble system, emphasize each newly written result digit, and keep carry/borrow marks visible through later steps.

**Architecture:** Keep the existing Solver → Board → Narrator → Card boundaries. Extend `VerticalMathBoardRow` with optional multi-column carry/borrow arrays, populate them in the pure solver, and let `VerticalMathBoard` render those arrays while retaining the existing single-marker fields as a fallback. Change only shared visual constants and the board shell; `VerticalMathBoardRow.ets`, tool contracts, solver arithmetic, narrator behavior, and star rewards remain unchanged.

**Tech Stack:** HarmonyOS 6 / API 23, ArkTS strict mode, ArkUI V2, Hypium (`@ohos/hypium`), hvigor.

## Global Constraints

- Pure frontend adjustment: do not change the `vertical_math` tool schema, `onAnswer` payload, tool execution flow, or star reward behavior.
- Do not change arithmetic results, narration, input validation, operation ranges, or the `solveVerticalMath` dispatch contract.
- Keep `topMark`, `topMarkColumn`, and `topMarkRowIndex` for backward compatibility; add `carryColumns?: number[]` and `borrowColumns?: number[]` to `VerticalMathBoardRow`.
- `active` remains `#ffe66d` with `#3a2d0c`; `done` remains `rgba(185, 242, 208, 0.18)` but uses `#15803d` text.
- Board background must be `VERTICAL_MATH_NARRATOR_BG` (`rgba(255, 250, 240, 0.86)`), with a 1px `app.color.divider` border and 14vp radius.
- Board text must be fixed warm ink `#3a3320`; board line must be `rgba(58, 51, 32, 0.55)`.
- Carry marks must be `#dc2626`; borrow marks must use a new `VERTICAL_MATH_BORROW_TEXT = '#7c3aed'` constant.
- A newly written addition or subtraction result cell must be `kind: 'active'`; previously written result cells stay `kind: 'done'`.
- Carry and borrow arrays must persist on every later computation snapshot and the final snapshot.
- Multiplication already highlights every non-empty cell in the current partial-product row; division already uses `kind: 'quotient'`, which `VerticalMathBoardRowView` renders with the active palette. Preserve these behaviors and add regression tests rather than rewriting them.
- `VerticalMathBoardRow.ets` needs no source change: it already reads the shared board/highlight constants.
- CLI `hvigorw test` is not usable in this repository because of the pre-existing testability scaffold mismatch. Run Hypium tests in DevEco Studio; CLI verification is a clean `assembleHap` plus focused source checks.

---

## File Structure

| File | Responsibility in this change |
|---|---|
| `entry/src/main/ets/utils/VerticalMathColors.ets` | Own the cream-board text, line, done, carry, and borrow palette; remove obsolete gradient tokens. |
| `entry/src/main/ets/utils/VerticalMathSolver.ets` | Extend row snapshots and persist result/carry/borrow visual semantics without changing arithmetic. |
| `entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets` | Render multiple persistent marks and replace the purple gradient shell with the cream bubble shell. |
| `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets` | Add six regressions for palette values and all four operations' active/persistent semantics. |
| `entry/src/main/ets/components/verticalMath/VerticalMathBoardRow.ets` | No edit; shared constant changes automatically update ordinary digits and operator glyphs. |

---

### Task 1: Lock the cream-board palette with a regression test

**Files:**
- Modify: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets:1-15, before the orchestrator describe block`
- Modify: `entry/src/main/ets/utils/VerticalMathColors.ets:1-24`

**Interfaces:**
- Consumes: existing exported color constants from `VerticalMathColors.ets`.
- Produces: `VERTICAL_MATH_BORROW_TEXT: string`; updated values consumed by `VerticalMathBoard.ets` and `VerticalMathBoardRow.ets`.

- [ ] **Step 1: Add the failing palette test**

Add this import after the solver import:

```ts
import {
  VERTICAL_MATH_BOARD_TEXT,
  VERTICAL_MATH_BOARD_LINE,
  VERTICAL_MATH_DONE_TEXT,
  VERTICAL_MATH_CARRY_TEXT,
  VERTICAL_MATH_BORROW_TEXT
} from '../../../main/ets/utils/VerticalMathColors'
```

Add this `describe` block inside `verticalMathSolverTest()`, before `describe('solveVerticalMath orchestrator', ...)`:

```ts
  describe('VerticalMathColors', () => {
    it('uses readable cream-board colors', 0, () => {
      expect(VERTICAL_MATH_BOARD_TEXT).assertEqual('#3a3320')
      expect(VERTICAL_MATH_BOARD_LINE).assertEqual('rgba(58, 51, 32, 0.55)')
      expect(VERTICAL_MATH_DONE_TEXT).assertEqual('#15803d')
      expect(VERTICAL_MATH_CARRY_TEXT).assertEqual('#dc2626')
      expect(VERTICAL_MATH_BORROW_TEXT).assertEqual('#7c3aed')
    })
  })
```

- [ ] **Step 2: Verify the test is red**

In DevEco Studio, right-click `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets` and run it.

Expected: compilation/test failure because `VERTICAL_MATH_BORROW_TEXT` is not exported and the four existing constants still have the old values.

If GUI execution is unavailable, record the test as **NOT RUN (DevEco-only)** and continue; do not use the broken CLI `hvigorw test` task.

- [ ] **Step 3: Replace the color file with the minimal palette change**

Replace `VerticalMathColors.ets` with:

```ts
// utils/VerticalMathColors.ets
// Retain these three exports until Task 3 removes the gradient consumer and tokens together.
export const VERTICAL_MATH_BOARD_BG_START: string = '#6448b5'
export const VERTICAL_MATH_BOARD_BG_MID: string = '#3a2877'
export const VERTICAL_MATH_BOARD_BG_END: string = '#27194f'

export const VERTICAL_MATH_BOARD_TEXT: string = '#3a3320'
export const VERTICAL_MATH_BOARD_LINE: string = 'rgba(58, 51, 32, 0.55)'

export const VERTICAL_MATH_ACTIVE_BG: string = '#ffe66d'
export const VERTICAL_MATH_ACTIVE_TEXT: string = '#3a2d0c'

export const VERTICAL_MATH_DONE_TEXT: string = '#15803d'
export const VERTICAL_MATH_DONE_BG: string = 'rgba(185, 242, 208, 0.18)'

export const VERTICAL_MATH_CARRY_TEXT: string = '#dc2626'
export const VERTICAL_MATH_BORROW_TEXT: string = '#7c3aed'

export const VERTICAL_MATH_ERROR_BG: string = '#ffe3dc'
export const VERTICAL_MATH_ERROR_TEXT: string = '#89564b'

export const VERTICAL_MATH_NARRATOR_BG: string = 'rgba(255, 250, 240, 0.86)'
export const VERTICAL_MATH_NARRATOR_ACTIVE_BG: string = '#fff1a5'
export const VERTICAL_MATH_NARRATOR_ACTIVE_TEXT: string = '#5b4811'
export const VERTICAL_MATH_NARRATOR_DONE_BG: string = '#e2f8e9'
export const VERTICAL_MATH_NARRATOR_DONE_TEXT: string = '#27764b'
```

The obsolete `VERTICAL_MATH_BOARD_BG_START`, `VERTICAL_MATH_BOARD_BG_MID`, and `VERTICAL_MATH_BOARD_BG_END` remain temporarily so this task is independently buildable. Task 3 deletes them in the same commit that removes their only consumer.

- [ ] **Step 4: Verify the palette values**

Run this focused source assertion:

```bash
node -e "const fs=require('fs');const s=fs.readFileSync('entry/src/main/ets/utils/VerticalMathColors.ets','utf8');for(const x of [\"VERTICAL_MATH_BOARD_TEXT: string = '#3a3320'\",\"VERTICAL_MATH_BOARD_LINE: string = 'rgba(58, 51, 32, 0.55)'\",\"VERTICAL_MATH_DONE_TEXT: string = '#15803d'\",\"VERTICAL_MATH_CARRY_TEXT: string = '#dc2626'\",\"VERTICAL_MATH_BORROW_TEXT: string = '#7c3aed'\"]){if(!s.includes(x))throw new Error('missing '+x)}"
```

Expected: exit code 0 with no output.

Run the module build to confirm this task is independently compilable:

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/utils/VerticalMathColors.ets entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets
git commit -m "style(vertical-math): adopt cream board palette"
```

---

### Task 2: Persist solver marks and emphasize newly written results

**Files:**
- Modify: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets:1-13, solveVerticalAdd/solveVerticalSubtract/solveVerticalMultiply/solveVerticalDivide describe blocks`
- Modify: `entry/src/main/ets/utils/VerticalMathSolver.ets:18-24, 170-285, 306-535`

**Interfaces:**
- Consumes: existing `VerticalMathStep.rows`, `VerticalMathStep.highlights`, and `VerticalMathHighlight` kinds.
- Produces: `VerticalMathBoardRow.carryColumns?: number[]`, `VerticalMathBoardRow.borrowColumns?: number[]`; persistent snapshots consumed by Task 3's `TopMark` renderer.
- Preserves: legacy `topMark*` fields, row order `[rowA, rowB, rowLine, rowResult]`, solver results, narration, and the multiplication/division output structure.

- [ ] **Step 1: Import the highlight model in the test file**

Add `VerticalMathHighlight` to the existing solver import:

```ts
import {
  VerticalMathOperation,
  VerticalMathValidationError,
  VerticalMathStep,
  VerticalMathBoardRow,
  VerticalMathHighlight,
  validateVerticalMathInputs,
  solveVerticalAdd,
  solveVerticalSubtract,
  solveVerticalMultiply,
  solveVerticalDivide,
  solveVerticalMath
} from '../../../main/ets/utils/VerticalMathSolver'
```

- [ ] **Step 2: Add five failing solver regressions**

Append this test to `describe('solveVerticalAdd', ...)`:

```ts
    it('marks each newly written addition result digit active', 0, () => {
      const s = solveVerticalAdd(22, 33)
      for (let index = 1; index < s.steps.length - 1; index++) {
        const expectedColumn: number = s.columnCount - index
        const resultActive: VerticalMathHighlight[] = s.steps[index].highlights.filter(
          (highlight: VerticalMathHighlight): boolean =>
            highlight.rowIndex === 3 && highlight.kind === 'active'
        )
        expect(resultActive.length).assertEqual(1)
        expect(resultActive[0].columnIndex).assertEqual(expectedColumn)
      }
    })

    it('keeps carry columns on later snapshots', 0, () => {
      const s = solveVerticalAdd(47, 28)
      expect(s.steps[1].rows[0].carryColumns?.includes(0) ?? false).assertEqual(true)
      expect(s.steps[2].rows[0].carryColumns?.includes(0) ?? false).assertEqual(true)
      expect(s.steps[s.steps.length - 1].rows[0].carryColumns?.includes(0) ?? false).assertEqual(true)
    })
```

Append this test to `describe('solveVerticalSubtract', ...)`:

```ts
    it('keeps cascade borrow columns and marks each new result active', 0, () => {
      const s = solveVerticalSubtract(303, 178)
      for (let index = 1; index < s.steps.length - 1; index++) {
        const marks: number[] = s.steps[index].rows[0].borrowColumns ?? []
        expect(marks.includes(0)).assertEqual(true)
        expect(marks.includes(1)).assertEqual(true)
        expect(marks.includes(2)).assertEqual(true)

        const expectedColumn: number = s.columnCount - index
        const resultActive: VerticalMathHighlight[] = s.steps[index].highlights.filter(
          (highlight: VerticalMathHighlight): boolean =>
            highlight.rowIndex === 3 && highlight.columnIndex === expectedColumn &&
              highlight.kind === 'active'
        )
        expect(resultActive.length).assertEqual(1)
      }
      const finalMarks: number[] = s.steps[s.steps.length - 1].rows[0].borrowColumns ?? []
      expect(finalMarks.includes(0)).assertEqual(true)
      expect(finalMarks.includes(1)).assertEqual(true)
      expect(finalMarks.includes(2)).assertEqual(true)
    })
```

Append this test to `describe('solveVerticalMultiply', ...)`:

```ts
    it('marks every non-empty current partial-product cell active', 0, () => {
      const s = solveVerticalMultiply(988, 6)
      for (let index = 1; index <= 3; index++) {
        const partialRowIndex: number = s.steps[index].rows.length - 1
        const partialCells: string[] = s.steps[index].rows[partialRowIndex].cells
        for (let column = 0; column < partialCells.length; column++) {
          if (partialCells[column] !== '') {
            expect(s.steps[index].highlights.some(
              (highlight: VerticalMathHighlight): boolean =>
                highlight.rowIndex === partialRowIndex && highlight.columnIndex === column &&
                  highlight.kind === 'active'
            )).assertEqual(true)
          }
        }
      }
    })
```

Append this test to `describe('solveVerticalDivide', ...)`:

```ts
    it('marks each written quotient digit with the active quotient semantic', 0, () => {
      const s = solveVerticalDivide(84, 4)
      const quotientSteps: VerticalMathStep[] = s.steps.filter(
        (step: VerticalMathStep): boolean =>
          step.highlights.some((highlight: VerticalMathHighlight): boolean => highlight.kind === 'quotient')
      )
      expect(quotientSteps.length).assertEqual(2)
      for (let index = 0; index < quotientSteps.length; index++) {
        expect(quotientSteps[index].highlights.some(
          (highlight: VerticalMathHighlight): boolean =>
            highlight.rowIndex === 3 && highlight.columnIndex === index && highlight.kind === 'quotient'
        )).assertEqual(true)
      }
    })
```

Together with Task 1's palette test, this adds six tests (31 → 37).

- [ ] **Step 3: Verify the new solver tests are red**

Run `VerticalMathSolver.test.ets` in DevEco Studio.

Expected:
- Addition result-active and carry persistence tests fail.
- Subtraction persistence/result-active test fails.
- Multiplication and division regression tests pass because those semantics already exist.

If GUI execution is unavailable, record the run as **NOT RUN (DevEco-only)**. The expected mixed red/pass result is intentional; do not weaken the already-passing multiplication/division assertions.

- [ ] **Step 4: Extend `VerticalMathBoardRow`**

Replace the class with:

```ts
export class VerticalMathBoardRow {
  cells: string[] = []            // length = columnCount; '' = blank cell
  operator?: string               // leading glyph ('+', '-', '×', '÷', '＋'), or undefined
  topMark?: string                // optional small glyph above the row ('•' for borrow, red 1 for add carry)
  topMarkColumn?: number          // which column the topMark belongs to
  topMarkRowIndex?: number        // visual row index used by carry row injection
  carryColumns?: number[]         // all carry columns accumulated through this snapshot
  borrowColumns?: number[]        // all borrow columns accumulated through this snapshot
}
```

- [ ] **Step 5: Persist addition carries and add result-active highlights**

Immediately before `let carryIn: number = 0`, add:

```ts
  const carryColumns: Set<number> = new Set<number>()
```

Replace the `rowA` / carry block inside the addition loop with:

```ts
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
```

After pushing `activeA` and `activeB`, add the current result highlight:

```ts
    const activeResult: VerticalMathHighlight = { rowIndex: 3, columnIndex: col, kind: 'active' }
    highlights.push(activeResult)
```

Replace final `rowA` construction with:

```ts
  const finalRowA: VerticalMathBoardRow = { cells: cloneCells(aCells) }
  if (carryColumns.size > 0) {
    finalRowA.carryColumns = Array.from(carryColumns)
  }
```

Keep the rest of the final step unchanged.

- [ ] **Step 6: Persist subtraction borrow chains and add result-active highlights**

After `const cascadeColumns...`, add the persistent set:

```ts
  const persistentBorrowColumns: Set<number> = new Set<number>()
```

After the borrow walk and before calculating `resultDigit`, accumulate the trigger column plus every intermediate/donor column:

```ts
    if (borrowColumns.length > 0) {
      persistentBorrowColumns.add(col)
      for (let bi = 0; bi < borrowColumns.length; bi++) {
        persistentBorrowColumns.add(borrowColumns[bi])
      }
    }
```

Replace the block from `const rowA` through the derived row-index declarations with the stable four-row snapshot below. The persistent arrays supersede the injected extra rows; the legacy single `topMark` remains on steps where the old solver emitted it, so existing consumers/tests remain compatible.

```ts
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
```

Delete the unused `rowLineIndex` declaration. Replace the borrow-highlight loop with a stable row-A mapping:

```ts
    for (let bi = 0; bi < stepBorrowColumns.length; bi++) {
      const borrowHl: VerticalMathHighlight = {
        rowIndex: rowAIndex,
        columnIndex: stepBorrowColumns[bi],
        kind: 'borrow'
      }
      highlights.push(borrowHl)
    }
```

After pushing `activeA` and `activeB`, add:

```ts
    const activeResult: VerticalMathHighlight = {
      rowIndex: rowResultIndex,
      columnIndex: col,
      kind: 'active'
    }
    highlights.push(activeResult)
```

Replace final `rowA` construction with:

```ts
  const finalRowA: VerticalMathBoardRow = { cells: cloneCells(aCells) }
  if (persistentBorrowColumns.size > 0) {
    finalRowA.borrowColumns = Array.from(persistentBorrowColumns)
  }
```

Keep `finalRowB`, `finalRowLine`, `finalRowResult`, the narration, arithmetic, and returned solution unchanged.

- [ ] **Step 7: Re-run the solver test file and compile**

Run `VerticalMathSolver.test.ets` in DevEco Studio.

Expected: 37/37 pass.

If GUI execution is unavailable, explicitly report **NOT RUN (DevEco-only)**. Do not claim the Hypium suite passed without GUI output.

In either case, compile the production ArkTS source:

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 8: Commit**

```bash
git add entry/src/main/ets/utils/VerticalMathSolver.ets entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets
git commit -m "fix(vertical-math): persist marks and highlight results"
```

---

### Task 3: Render persistent marks on the cream board

**Files:**
- Modify: `entry/src/main/ets/utils/VerticalMathColors.ets:1-5`
- Modify: `entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets:1-131`
- Verify unchanged: `entry/src/main/ets/components/verticalMath/VerticalMathBoardRow.ets`

**Interfaces:**
- Consumes: `VerticalMathBoardRow.carryColumns`, `VerticalMathBoardRow.borrowColumns`, legacy `topMark*`, `VERTICAL_MATH_NARRATOR_BG`, and `VERTICAL_MATH_BORROW_TEXT`.
- Produces: a cream, bordered board that overlays all carry/borrow glyphs at their columns.
- Preserves: current row/highlight selection, compact cell sizing, horizontal-line rules, board dimensions, and legacy single-marker rendering.

- [ ] **Step 1: Delete the obsolete gradient tokens and replace their imports**

Delete these three exports from `VerticalMathColors.ets`:

```ts
export const VERTICAL_MATH_BOARD_BG_START: string = '#6448b5'
export const VERTICAL_MATH_BOARD_BG_MID: string = '#3a2877'
export const VERTICAL_MATH_BOARD_BG_END: string = '#27194f'
```

Replace the color import in `VerticalMathBoard.ets` with:

```ts
import {
  VERTICAL_MATH_BOARD_LINE,
  VERTICAL_MATH_CARRY_TEXT,
  VERTICAL_MATH_BORROW_TEXT,
  VERTICAL_MATH_NARRATOR_BG
} from '../../utils/VerticalMathColors'
```

- [ ] **Step 2: Replace single-marker positioning helpers**

Replace `getTopMarkOffset` and `getTopMarkColor` with:

```ts
  private getTopMarkOffset(column: number): number {
    return this.getCellSize() + column * this.getCellSize()
  }

  private getTopMarkColor(mark: string): string {
    return mark === '•' ? VERTICAL_MATH_BORROW_TEXT : VERTICAL_MATH_CARRY_TEXT
  }

  private getCarryColumns(row: VerticalMathBoardRow): number[] {
    return row.carryColumns ?? []
  }

  private getBorrowColumns(row: VerticalMathBoardRow): number[] {
    return row.borrowColumns ?? []
  }

  private hasPersistentTopMarks(row: VerticalMathBoardRow): boolean {
    return this.getCarryColumns(row).length > 0 || this.getBorrowColumns(row).length > 0
  }
```

- [ ] **Step 3: Render one overlaid glyph per persisted column**

Add this builder before `TopMark`:

```ts
  @Builder
  private TopMarkAt(mark: string, column: number) {
    Row() {
      Text(mark)
        .fontSize(this.compact ? 15 : 18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getTopMarkColor(mark))
        .width(this.getCellSize())
        .textAlign(TextAlign.Center)
    }
    .width(this.getCellSize() * (this.solution.columnCount + 1))
    .padding({ left: this.getTopMarkOffset(column) })
    .justifyContent(FlexAlign.Start)
  }
```

Replace `TopMark` with:

```ts
  @Builder
  private TopMark(row: VerticalMathBoardRow) {
    if (this.hasPersistentTopMarks(row)) {
      Stack() {
        ForEach(this.getCarryColumns(row), (column: number) => {
          this.TopMarkAt('1', column)
        }, (column: number) => `carry_${column}`)
        ForEach(this.getBorrowColumns(row), (column: number) => {
          this.TopMarkAt('•', column)
        }, (column: number) => `borrow_${column}`)
      }
    } else if (row.topMark !== undefined && row.topMark !== '') {
      this.TopMarkAt(row.topMark, row.topMarkColumn === undefined ? 0 : row.topMarkColumn)
    }
  }
```

The `Stack` overlays marks horizontally instead of adding one vertical row per mark. The fallback branch keeps older single-marker snapshots renderable.

- [ ] **Step 4: Replace the gradient `Stack` with the cream `Column` shell**

Replace the complete `build()` method with:

```ts
  build() {
    Column() {
      ForEach(this.getCurrentRows(), (row: VerticalMathBoardRow, rowIndex: number) => {
        Column() {
          this.TopMark(row)
          VerticalMathBoardRowView({
            row: row,
            rowIndex: rowIndex,
            highlights: this.getRowHighlights(rowIndex),
            cellSize: this.getCellSize(),
            columnCount: this.solution.columnCount
          })
          if (this.shouldShowLine(rowIndex)) {
            Row()
              .width(this.getCellSize() * this.solution.columnCount)
              .height(4)
              .margin({ left: this.getCellSize(), top: 4, bottom: 4 })
              .backgroundColor(VERTICAL_MATH_BOARD_LINE)
              .borderRadius(2)
          }
        }
        .alignItems(HorizontalAlign.Start)
      }, (_row: VerticalMathBoardRow, rowIndex: number) => `row_${rowIndex}`)
    }
    .padding(this.compact ? 14 : 20)
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .backgroundColor(VERTICAL_MATH_NARRATOR_BG)
    .border({ width: 1, color: $r('app.color.divider') })
    .borderRadius(14)
  }
```

Do not edit `VerticalMathBoardRow.ets`; ordinary digits and operator glyphs already consume `VERTICAL_MATH_BOARD_TEXT`, while active/done cells consume the shared highlight constants.

- [ ] **Step 5: Verify source wiring**

Use content search to verify:

1. `VERTICAL_MATH_BOARD_BG_START`, `VERTICAL_MATH_BOARD_BG_MID`, and `VERTICAL_MATH_BOARD_BG_END` have zero matches under `entry/src/main/ets/`.
2. `VerticalMathBoard.ets` imports and uses both `VERTICAL_MATH_BORROW_TEXT` and `VERTICAL_MATH_NARRATOR_BG`.
3. `VerticalMathBoard.ets` contains no `.linearGradient(` call.
4. `VerticalMathBoardRow.ets` still imports `VERTICAL_MATH_BOARD_TEXT`, `VERTICAL_MATH_ACTIVE_*`, and `VERTICAL_MATH_DONE_*` without source edits.

Expected: all four checks match the statements above.

- [ ] **Step 6: Compile the ArkTS changes**

Run:

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

Expected: `BUILD SUCCESSFUL` and `entry/build/default/outputs/default/entry-default-signed.hap` exists.

- [ ] **Step 7: Commit**

```bash
git add entry/src/main/ets/utils/VerticalMathColors.ets entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets
git commit -m "style(vertical-math): render persistent marks on cream board"
```

---

### Task 4: Final verification and acceptance handoff

**Files:**
- Verify: `entry/src/main/ets/utils/VerticalMathColors.ets`
- Verify: `entry/src/main/ets/utils/VerticalMathSolver.ets`
- Verify: `entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets`
- Verify: `entry/src/main/ets/components/verticalMath/VerticalMathBoardRow.ets`
- Verify: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets`

**Interfaces:**
- Consumes: all three implementation commits.
- Produces: fresh build evidence and a manual acceptance checklist; no source changes.

- [ ] **Step 1: Review the scoped diff**

Run:

```bash
git diff e990d45..HEAD -- entry/src/main/ets/utils/VerticalMathColors.ets entry/src/main/ets/utils/VerticalMathSolver.ets entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets entry/src/main/ets/components/verticalMath/VerticalMathBoardRow.ets entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets
```

Verify there are no changes to tool schema/execution files, result payloads, narrator source, assistant prompt, or star reward files. Verify `VerticalMathBoardRow.ets` is unchanged.

- [ ] **Step 2: Run the full clean build**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw clean --mode module -p product=default
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

Expected: `BUILD SUCCESSFUL`; `entry/build/default/outputs/default/entry-default-signed.hap` is regenerated.

- [ ] **Step 3: Run all 37 Hypium tests in DevEco Studio**

Right-click `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets` → Run.

Expected: 37/37 pass. If this environment cannot open DevEco Studio, report **NOT RUN** rather than inferring success from the build.

- [ ] **Step 4: Perform the device/preview smoke checklist**

In chat, verify:

- `22 + 33`: cream board, deep ink digits, dark horizontal line, and each newly written result digit is yellow on its computation step.
- `47 + 28`: the carry `1` is red and stays visible through the tens step and final result.
- `503 - 278` or `303 - 178`: donor, intermediate zero, and trigger columns show persistent purple `•` marks without adding stacked blank rows.
- `988 × 6`: every non-empty cell of the current partial-product row is yellow; completed partial rows are mint; no carry markers appear.
- `84 ÷ 4`: each quotient digit is yellow when written.
- Narrator appearance, step navigation, arithmetic answers, result payload, and completion behavior are unchanged.

If no preview/device is available, report this checklist as **NOT PERFORMED** and hand it to the user.

- [ ] **Step 5: Confirm repository state**

```bash
git status --short
git log -5 --oneline
```

Expected: no unintended tracked changes; the three implementation commits follow the two visual-fix spec commits.

---

## Spec Coverage Map

| Spec requirement | Plan coverage |
|---|---|
| Cream board shell, divider border, 14vp radius | Task 3 Steps 1 and 4 |
| Deep board text and dark line | Task 1 Steps 1–4; Task 3 build verification |
| Active/done/carry/borrow palette | Task 1 |
| Addition result-active | Task 2 Steps 2 and 5 |
| Subtraction result-active | Task 2 Steps 2 and 6 |
| Persistent addition carry | Task 2 Steps 2 and 5; Task 3 Step 3 |
| Persistent cascade/direct borrow columns | Task 2 Steps 2 and 6; Task 3 Step 3 |
| Multiplication partial-product active | Task 2 Steps 2–3 regression only |
| Division quotient active | Task 2 Steps 2–3 regression only |
| Legacy topMark compatibility | Task 2 Steps 4–6; Task 3 Step 3 |
| No tool/solver arithmetic/star/narrator changes | Global constraints; Task 4 Steps 1 and 4 |
| Build, Hypium, manual acceptance | Task 3 Step 6; Task 4 |
