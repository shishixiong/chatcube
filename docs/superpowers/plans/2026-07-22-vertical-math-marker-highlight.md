# Vertical Math Marker Highlight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Highlight the carry `1` or borrow `•` marker when the current vertical-math step is using that marker's column.

**Architecture:** Keep solver output and tool contracts unchanged. `VerticalMathBoard` derives the active operand column from the current step's row-0 `active` highlight, intersects it with the rendered row's persistent `carryColumns`/`borrowColumns`, and passes an `isActive` flag to the existing marker builder. The marker keeps its carry/borrow text color and receives the existing yellow active background only while relevant.

**Tech Stack:** ArkTS, HarmonyOS ArkUI `@ComponentV2`, Hypium source-level tests, hvigor `assembleHap`.

## Global Constraints

- Support both addition carry markers (`1`) and subtraction borrow markers (`•`).
- Do not add solver fields, highlight kinds, tool parameters, or card state-machine changes.
- Do not highlight a marker merely because it was produced in the current lower-digit step; highlight it when the current active operand column matches the persistent marker column.
- The final `得到答案` step has no row-0 active column and must render markers without active highlighting.
- Preserve `VERTICAL_MATH_CARRY_TEXT` and `VERTICAL_MATH_BORROW_TEXT` for marker text.
- Keep the production implementation scoped to `entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets`; test assertions may update `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets`.
- Verify with a clean `assembleHap`; Hypium CLI is known to fail on the repository's pre-existing generated-test path mismatch, so report DevEco GUI testing as pending when unavailable.

---

### Task 1: Highlight active carry and borrow markers

**Files:**
- Modify: `entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets:21-108`
- Test: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets:82-184`

**Interfaces:**
- Consumes: `VerticalMathSolution.steps`, `VerticalMathStep.highlights`, `VerticalMathBoardRow.carryColumns`, and `VerticalMathBoardRow.borrowColumns` from `utils/VerticalMathSolver.ets`.
- Produces: private board helpers that identify the current row-0 active column and pass a boolean active state to `TopMarkAt(mark, column, isActive)`.

- [ ] **Step 1: Add failing solver assertions for active-column relationships**

  In the existing `solveVerticalAdd` tests, add an assertion after the carry persistence test that uses `solveVerticalAdd(47, 28)`:

  ```typescript
  it('uses the persistent carry marker on the next higher-column step', 0, () => {
    const s = solveVerticalAdd(47, 28)
    const lowStep: VerticalMathStep = s.steps[0]
    const highStep: VerticalMathStep = s.steps[1]
    const lowActive: VerticalMathHighlight[] = lowStep.highlights.filter(
      (highlight: VerticalMathHighlight): boolean =>
        highlight.rowIndex === 0 && highlight.kind === 'active'
    )
    const highActive: VerticalMathHighlight[] = highStep.highlights.filter(
      (highlight: VerticalMathHighlight): boolean =>
        highlight.rowIndex === 0 && highlight.kind === 'active'
    )
    expect(lowActive[0].columnIndex).assertEqual(1)
    expect(highActive[0].columnIndex).assertEqual(0)
    expect(highStep.rows[0].carryColumns?.includes(highActive[0].columnIndex) ?? false)
      .assertEqual(true)
    expect(lowStep.rows[0].carryColumns?.includes(lowActive[0].columnIndex) ?? false)
      .assertEqual(false)
  })
  ```

  In the subtraction tests, add an assertion after the cascade test using `solveVerticalSubtract(503, 278)`:

  ```typescript
  it('uses a persistent borrow marker on the active borrow column', 0, () => {
    const s = solveVerticalSubtract(503, 278)
    const activeStep: VerticalMathStep = s.steps[0]
    const activeA: VerticalMathHighlight[] = activeStep.highlights.filter(
      (highlight: VerticalMathHighlight): boolean =>
        highlight.rowIndex === 0 && highlight.kind === 'active'
    )
    expect(activeA.length).assertEqual(1)
    expect(activeStep.rows[0].borrowColumns?.includes(activeA[0].columnIndex) ?? false)
      .assertEqual(true)
    const finalStep: VerticalMathStep = s.steps[s.steps.length - 1]
    expect(finalStep.highlights.some(
      (highlight: VerticalMathHighlight): boolean =>
        highlight.rowIndex === 0 && highlight.kind === 'active'
    )).assertEqual(false)
  })
  ```

- [ ] **Step 2: Run the focused source assertion before implementation**

  Run the repository's existing source-assertion command for `VerticalMathSolver.test.ets` used by the vertical-math follow-up work. Expected: the new assertions pass against the existing solver data, while the visual behavior remains unimplemented. If no focused command is available in the environment, hand-trace these assertions and record Hypium as DevEco-only; do not change solver code to make them pass.

- [ ] **Step 3: Add helpers for the current operand column**

  In `VerticalMathBoard.ets`, add a private helper near `getCurrentHighlights()` that returns the row-0 active column or `-1`:

  ```typescript
  private getActiveOperandColumn(): number {
    const active: VerticalMathHighlight | undefined = this.getCurrentHighlights().find(
      (highlight: VerticalMathHighlight): boolean =>
        highlight.rowIndex === 0 && highlight.kind === 'active'
    )
    return active === undefined ? -1 : active.columnIndex
  }
  ```

  Add a private helper near the carry/borrow getters:

  ```typescript
  private isActiveTopMark(column: number): boolean {
    return column === this.getActiveOperandColumn()
  }
  ```

  The `-1` result ensures the final step and initial board cannot activate a marker.

- [ ] **Step 4: Render the active marker background without changing alignment**

  Change `TopMarkAt` to accept `isActive: boolean`, and apply the existing active background only to the marker `Text`:

  ```typescript
  @Builder
  private TopMarkAt(mark: string, column: number, isActive: boolean = false) {
    Row() {
      Text(mark)
        .fontSize(this.compact ? 15 : 18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getTopMarkColor(mark))
        .width(this.getCellSize())
        .height(this.getCellSize())
        .borderRadius(this.getCellSize() / 2)
        .backgroundColor(isActive ? VERTICAL_MATH_ACTIVE_BG : Color.Transparent)
        .textAlign(TextAlign.Center)
    }
    .width(this.getCellSize() * (this.solution.columnCount + 1))
    .padding({ left: this.getTopMarkOffset(column) })
    .justifyContent(FlexAlign.Start)
  }
  ```

  Update every `TopMarkAt` call in `TopMark`:

  ```typescript
  this.TopMarkAt('1', column, this.isActiveTopMark(column))
  this.TopMarkAt('•', column, this.isActiveTopMark(column))
  this.TopMarkAt(row.topMark, row.topMarkColumn === undefined ? 0 : row.topMarkColumn,
    this.isActiveTopMark(row.topMarkColumn === undefined ? 0 : row.topMarkColumn))
  ```

  Preserve the existing `Stack`, `ForEach`, and column padding. Do not infer active state from `kind === 'carry'` or `kind === 'borrow'`.

- [ ] **Step 5: Run focused assertions and build**

  Re-run the focused vertical-math source assertions and hand-trace the visual cases:

  - `47 + 28`: step 0's carry at column 0 is ordinary; step 1's active column 0 carry is yellow; final step is ordinary.
  - `303 - 178`: the active row-0 column intersects the persistent borrow set and is yellow; other persistent dots remain purple; final step is ordinary.
  - `100 + 200` and `100 - 50`: no marker is rendered or highlighted.

  Run:

  ```bash
  DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
    /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
    --mode module -p product=default -p buildMode=debug
  ```

  Expected: `BUILD SUCCESSFUL` and regenerated `entry/build/default/outputs/default/entry-default-signed.hap`.

- [ ] **Step 6: Review the diff and commit**

  Confirm only the board renderer and focused solver test assertions changed for implementation, then commit:

  ```bash
  git add entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets \
    entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets
  git commit -m "feat(vertical-math): highlight active carry and borrow markers"
  ```

---

## Self-review checklist

- Spec coverage: active-column intersection, both marker types, final-step reset, preserved text colors, no solver/model/tool changes, focused assertions, and clean build are all covered by Task 1.
- Placeholder scan: no TBD/TODO or unspecified test commands are used; the known Hypium limitation is explicit.
- Type consistency: `VerticalMathHighlight` and `VerticalMathStep` are imported types already used by the test file; `TopMarkAt` receives a boolean at every call site; `getActiveOperandColumn()` returns a number and uses `-1` as the sentinel.
