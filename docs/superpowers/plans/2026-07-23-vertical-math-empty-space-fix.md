# Vertical Math Empty Space Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the large empty area below the operands in the vertical-math card by vertically centering the math board and adding a step progress dot indicator between the board and the controls.

**Architecture:** Two surgical edits in two files. `VerticalMathBoard` gains `.justifyContent(FlexAlign.Center)` on its outer Column so its row stack sits centered in the allocated height. `VerticalMathCard` gains a new `StepProgressDots` `@Builder` rendering one circle per step (pending/current/done) and reorders the compact + largeSize layouts to `narrator → board → dots → Controls`, moving `Controls()` from above the main content to below it.

**Tech Stack:** ArkTS, HarmonyOS ArkUI V2 (`@ComponentV2`, `@Builder`, `Row`, `Column`, `ForEach`), Hypium source-level tests, hvigor `assembleHap`.

## Global Constraints

- Only two files change: `entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets` and `entry/src/main/ets/components/VerticalMathCard.ets`.
- `VerticalMathBoard.ets` outer Column must include `.justifyContent(FlexAlign.Center)` after the existing `.alignItems(HorizontalAlign.Start)`.
- `VerticalMathCard.ets` must include a new `@Builder private StepProgressDots()` that uses `VERTICAL_MATH_ACTIVE_BG`, `VERTICAL_MATH_ACTIVE_TEXT`, `VERTICAL_MATH_DONE_TEXT` from `entry/src/main/ets/utils/VerticalMathColors.ets`, plus `$r('app.color.divider')` for the pending border.
- In both `isCompact()` and largeSize branches, the build order must be `narrator → board → dots → Controls`. `this.Controls()` invocation must move from above the main-content Column to below it.
- Dot sizes: pending 8vp, current 12vp, done 8vp. Pending border width 1.5vp. Dots Row horizontal layout, 8vp spacing, centered.
- Solver, tool protocol, card state machine (`visibleStepCount`), `aboutToAppear` auto-solve + `isAnswered` final-step jump, `onAnswer`, star reward, `parseToolCallArguments`, `regenerateSolution`, `isCompleteVerticalMathArgs`, marker highlight (commit `06a4bb6`), narrator redesign (`34c1d1f` + `1722ac3`) all stay untouched.
- Hypium CLI is known broken on this project (see MEMORY.md). Verification = source assertions + clean `assembleHap`. DevEco Studio GUI verification is pending the user.
- Do not create a worktree — edit in place on `math_teacher`.

---

### Task 1: Center board + step progress dots + Controls relocated

**Files:**
- Modify: `entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets:127-158` (add `.justifyContent(FlexAlign.Center)` to outer Column)
- Modify: `entry/src/main/ets/components/VerticalMathCard.ets` (add `StepProgressDots` builder + restructure both layout branches + move `Controls()`)

**Interfaces:**
- Consumes: existing `VerticalMathSolution.steps` and `VerticalMathStep` types from `entry/src/main/ets/utils/VerticalMathSolver.ets`; existing color constants from `entry/src/main/ets/utils/VerticalMathColors.ets`.
- Produces: a new `@Builder private StepProgressDots()` method on `VerticalMathCard` that takes no parameters (reads `this.solution.steps.length` and `this.visibleStepCount` directly).

- [ ] **Step 1: Center the board's outer Column in `VerticalMathBoard.ets`**

  In `entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets`, the outer Column at lines 128-158 currently is:

  ```typescript
  build() {
    Column() {
      ForEach(this.getCurrentRows(), (row: VerticalMathBoardRow, rowIndex: number) => {
        Column() {
          this.TopMark(row)
          VerticalMathBoardRowView({...})
          if (this.shouldShowLine(rowIndex)) {
            Row() {...}
          }
        }
        .alignItems(HorizontalAlign.Start)
      }, (_row: VerticalMathBoardRow, rowIndex: number) => `${this.visibleStepCount}_${rowIndex}`)
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

  Add `.justifyContent(FlexAlign.Center)` between `.padding(this.compact ? 14 : 20)` and `.alignItems(HorizontalAlign.Start)`. The resulting outer Column ends with:

  ```typescript
    .padding(this.compact ? 14 : 20)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .backgroundColor(VERTICAL_MATH_NARRATOR_BG)
    .border({ width: 1, color: $r('app.color.divider') })
    .borderRadius(14)
  ```

  No other change to this file. The `.height('100%')` stays — the caller (`VerticalMathCard` after Step 2) gives the board a real height via `.layoutWeight(1)`, and the justifyContent makes the row stack sit centered inside that height.

- [ ] **Step 2: Add the `StepProgressDots` builder to `VerticalMathCard.ets`**

  In `entry/src/main/ets/components/VerticalMathCard.ets`, add this `@Builder` immediately after the existing `Controls()` builder (around line 286, before `build()`):

  ```typescript
  @Builder
  private StepProgressDots() {
    Row() {
      ForEach(this.solution.steps, (_step: VerticalMathStep, index: number) => {
        if (index < this.visibleStepCount - 1) {
          // done
          Circle()
            .width(8)
            .height(8)
            .fill(VERTICAL_MATH_DONE_TEXT)
        } else if (index === this.visibleStepCount - 1) {
          // current
          Circle()
            .width(12)
            .height(12)
            .fill(VERTICAL_MATH_ACTIVE_BG)
            .stroke(VERTICAL_MATH_ACTIVE_TEXT)
            .strokeWidth(1.5)
        } else {
          // pending
          Circle()
            .width(8)
            .height(8)
            .fill(Color.Transparent)
            .stroke($r('app.color.divider'))
            .strokeWidth(1.5)
        }
      }, (_step: VerticalMathStep, index: number) => `step_dot_${index}`)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .margin({ top: 12, bottom: 12 })
  }
  ```

  Then update the imports at the top of the file: replace the existing import block:

  ```typescript
  import {
    VERTICAL_MATH_ERROR_BG,
    VERTICAL_MATH_ERROR_TEXT
  } from '../utils/VerticalMathColors'
  ```

  with:

  ```typescript
  import {
    VERTICAL_MATH_ACTIVE_BG,
    VERTICAL_MATH_ACTIVE_TEXT,
    VERTICAL_MATH_DONE_TEXT,
    VERTICAL_MATH_ERROR_BG,
    VERTICAL_MATH_ERROR_TEXT
  } from '../utils/VerticalMathColors'
  import { VerticalMathStep } from '../utils/VerticalMathSolver'
  ```

  (Add `VERTICAL_MATH_ACTIVE_BG`, `VERTICAL_MATH_ACTIVE_TEXT`, `VERTICAL_MATH_DONE_TEXT` for the dot colors; add `VerticalMathStep` import to type the `_step` parameter inside `ForEach`. The other solver types are already imported.)

- [ ] **Step 3: Reorder the compact layout and move `Controls()`**

  In `build()` (around lines 287-369), the current `if (this.solution !== null) { ... }` block renders `this.Controls()` first, then the `isCompact()`/`else` branch with the main content. Replace that whole `if (this.solution !== null) { ... }` block with:

  ```typescript
      // Controls (always visible when solution exists) — MOVED to bottom; see below.
      if (this.solution !== null) {
        // Board + narrator + step dots
        if (this.isCompact()) {
          // Stacked layout (mobile)
          Column() {
            VerticalMathStepNarrator({
              steps: this.solution.steps,
              visibleStepCount: this.visibleStepCount,
              operationLabel: `第 ${this.visibleStepCount} / ${this.solution.steps.length} 步`
            })
            .margin({ bottom: 8 })
            VerticalMathBoard({
              solution: this.solution,
              visibleStepCount: this.visibleStepCount,
              compact: true
            })
            .layoutWeight(1)
            this.StepProgressDots()
          }
          .layoutWeight(1)
          .padding({ left: 12, right: 12, top: 12, bottom: 8 })
        } else {
          // Narrator header above full-width board (tablet / largeSize)
          Column() {
            VerticalMathStepNarrator({
              steps: this.solution.steps,
              visibleStepCount: this.visibleStepCount,
              operationLabel: `第 ${this.visibleStepCount} / ${this.solution.steps.length} 步`
            })
            .margin({ bottom: 10 })
            VerticalMathBoard({
              solution: this.solution,
              visibleStepCount: this.visibleStepCount,
              compact: false
            })
            .layoutWeight(1)
            this.StepProgressDots()
          }
          .layoutWeight(1)
          .padding(12)
        }
        // Controls now sit below the main content (see spec §3.2.4 rationale).
        this.Controls()
      }
  ```

  Changes from the current code:
  - `this.Controls()` invocation removed from its previous position (above the layout branches) and appended after the layout branches.
  - In the compact branch, `VerticalMathBoard(...)` gains `.layoutWeight(1)` so it fills the space between the narrator and the dots row.
  - Both branches append `this.StepProgressDots()` after the board.
  - The compact branch's outer padding changes from `{ left: 12, right: 12, bottom: 12 }` to `{ left: 12, right: 12, top: 12, bottom: 8 }` so the dots row has breathing room above and the Controls (now below) has its own padding from `Controls()`'s `.padding(12)`.
  - The largeSize branch's outer padding stays `12` (Controls has its own padding).
  - All other call sites, builders, and lifecycle methods are unchanged.

- [ ] **Step 4: Run focused source assertions**

  Verify the six invariants from spec §5.1. Write the assertion script to a file (the template-literal backticks break bash heredocs) and run it. Expected: all checks PASS.

  Write `/Users/mac/mygame/HarmonyOS-app/chatcube/.superpowers/sdd/verify-empty-space-fix.js`:

  ```javascript
  const fs = require('fs');
  const board = fs.readFileSync('entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets', 'utf8');
  const card = fs.readFileSync('entry/src/main/ets/components/VerticalMathCard.ets', 'utf8');

  const checks = {
    board_justify_center: board.includes('.justifyContent(FlexAlign.Center)'),
    board_no_scroll_added: !board.includes('Scroller') && !board.includes('List({'),
    card_has_step_progress: card.includes('private StepProgressDots'),
    card_imports_active_bg: card.includes('VERTICAL_MATH_ACTIVE_BG'),
    card_imports_active_text: card.includes('VERTICAL_MATH_ACTIVE_TEXT'),
    card_imports_done_text: card.includes('VERTICAL_MATH_DONE_TEXT'),
    card_compact_order: (() => {
      const m = card.match(/if \(this\.isCompact\(\)\) \{[\s\S]*?\} else \{/);
      if (!m) return false;
      const block = m[0];
      const narrator = block.indexOf('VerticalMathStepNarrator({');
      const board = block.indexOf('VerticalMathBoard({');
      const dots = block.indexOf('this.StepProgressDots()');
      return narrator !== -1 && board !== -1 && dots !== -1
        && narrator < board && board < dots;
    })(),
    card_large_order: (() => {
      const m = card.match(/\} else \{[\s\S]*?\n        \/\/ Controls now sit/);
      if (!m) return false;
      const block = m[0];
      const narrator = block.indexOf('VerticalMathStepNarrator({');
      const board = block.indexOf('VerticalMathBoard({');
      const dots = block.indexOf('this.StepProgressDots()');
      return narrator !== -1 && board !== -1 && dots !== -1
        && narrator < board && board < dots;
    })(),
    card_controls_below_main: (() => {
      const mainIdx = card.indexOf('if (this.solution !== null)');
      const controlsIdx = card.lastIndexOf('this.Controls()');
      // The build() body has exactly ONE `this.Controls()` invocation (inside `if solution`),
      // and it must come after the layout branches (i.e., be the last meaningful call).
      const occurrences = card.split('this.Controls()').length - 1;
      return occurrences === 1 && controlsIdx > mainIdx;
    })(),
    card_dots_use_active_bg: card.includes('.fill(VERTICAL_MATH_ACTIVE_BG)'),
    card_dots_use_done_text: card.includes('.fill(VERTICAL_MATH_DONE_TEXT)'),
    card_dots_use_divider: card.includes("stroke($r('app.color.divider'))"),
  };

  const fails = Object.entries(checks).filter(([k, v]) => !v);
  if (fails.length) {
    console.error('FAIL:', fails.map(f => f[0]).join(', '));
    process.exit(1);
  }
  for (const [k, v] of Object.entries(checks)) console.log(k, '=', v);
  console.log('PASS: all', Object.keys(checks).length, 'source assertions');
  ```

  Run:

  ```bash
  node .superpowers/sdd/verify-empty-space-fix.js
  ```

  Expected (all `= true`):

  ```
  board_justify_center = true
  board_no_scroll_added = true
  card_has_step_progress = true
  card_imports_active_bg = true
  card_imports_active_text = true
  card_imports_done_text = true
  card_compact_order = true
  card_large_order = true
  card_controls_below_main = true
  card_dots_use_active_bg = true
  card_dots_use_done_text = true
  card_dots_use_divider = true
  PASS: all 12 source assertions
  ```

- [ ] **Step 5: Hand-trace the dot states per `visibleStepCount`**

  Walk through the 4 state cases from spec §5.2. No code to run — read the `StepProgressDots` builder logic and confirm each case produces the expected dot pattern. Expected: all 4 cases match.

  | State | `visibleStepCount` | `steps.length` | Expected pattern (using ○=pending, ◉=current, ●=done) |
  |---|---|---|---|
  | Initial | 0 | 5 | ○ ○ ○ ○ ○ |
  | Step 1 | 1 | 5 | ◉ ○ ○ ○ ○ |
  | Mid (step 3) | 3 | 5 | ● ● ◉ ○ ○ |
  | Final | 5 | 5 | ● ● ● ● ◉ |

  Trace each row through the dot branches:
  - Initial: `visibleStepCount - 1 === -1`, so the `index === -1` branch never fires; every dot falls into the else (pending) branch → ○ ○ ○ ○ ○.
  - Step 1: `visibleStepCount - 1 === 0`. index=0 → current. index=1..4 → pending → ◉ ○ ○ ○ ○.
  - Mid: `visibleStepCount - 1 === 2`. index=0,1 → done; index=2 → current; index=3,4 → pending → ● ● ◉ ○ ○.
  - Final: `visibleStepCount - 1 === 4`. index=0..3 → done; index=4 → current → ● ● ● ● ◉.

  All 4 cases produce the expected pattern.

- [ ] **Step 6: Build and verify**

  Run a clean `assembleHap` and verify the production HAP is regenerated. Expected: `BUILD SUCCESSFUL`.

  ```bash
  DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
    /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
    --mode module -p product=default -p buildMode=debug
  ```

  Confirm the artifact exists and is newer than the source files:

  ```bash
  ls -la entry/build/default/outputs/default/entry-default-signed.hap
  ```

  Expected: file present, mtime newer than `VerticalMathBoard.ets` and `VerticalMathCard.ets`. Record Hypium as DevEco-only per the documented MEMORY.md limitation.

- [ ] **Step 7: Commit**

  ```bash
  git add entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets \
          entry/src/main/ets/components/VerticalMathCard.ets
  git commit -m "feat(vertical-math): center board + add step progress dots"
  ```

  Body: explain the layout reorder and the new dots builder; reference commit `b3aaa84` (spec) and `1f5c205` (color tweak).

---

## Self-review checklist

- Spec coverage:
  - Spec §3.1 (board vertical center) — Task 1 Step 1.
  - Spec §3.2.1 (StepProgressDots builder with 3 states using existing constants) — Task 1 Step 2.
  - Spec §3.2.2 (compact layout reorder with `layoutWeight(1)` on board) — Task 1 Step 3.
  - Spec §3.2.3 (largeSize layout reorder, board gets `layoutWeight(1)`, dots row appended) — Task 1 Step 3.
  - Spec §3.2.4 (Controls moved to bottom) — Task 1 Step 3.
  - Spec §5.1 (6 source-assertion invariants) — Task 1 Step 4 (expanded to 12 assertions covering all edge cases).
  - Spec §5.2 (4-case hand-trace) — Task 1 Step 5.
  - Spec §5.3 (`assembleHap` clean) — Task 1 Step 6.
- Placeholder scan: no TBD/TODO. Step 1 contains the exact one-line addition. Step 2 contains the full `@Builder` body and the updated import block. Step 3 contains the full replacement block for the `if (this.solution !== null)` region. Step 4 contains the full assertion script.
- Type consistency: `VerticalMathStep` is imported in Step 2 to type the `ForEach` `_step` parameter (matches the solver's exported type). `VerticalMathSolution` (already imported) carries `steps: VerticalMathStep[]`. No new types introduced.
- Scope discipline: only 2 files modified; solver/tool/protocol/MathQuiz/EnglishQuiz/MessageBubble/star/narrator/marker-highlight/auto-solve untouched.
- The 12 source assertions in Step 4 match the spec's 6 invariants plus 6 additional edge-case guards (no scroll introduced, exact import presence, exact color usages, exact single `Controls()` call site).