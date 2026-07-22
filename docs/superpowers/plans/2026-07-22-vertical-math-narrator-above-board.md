# Vertical Math Single-Line Narrator Above Board Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the multi-row step list inside `VerticalMathStepNarrator` with a single-line title+narration row that sits above `VerticalMathBoard` in `VerticalMathCard`. The line updates with a smooth fade + slide animation when `visibleStepCount` changes.

**Architecture:** Single small change in two files. The narrator stops being a scrolling list and becomes a header strip (operation label + single-line current-step text). The card layout swaps the order of narrator/board in both `largeSize` and compact layouts. All other behavior (`regenerateSolution`, `parseToolCallArguments`, `Controls`, `isAnswered` re-mount handling, auto-solve, marker highlight, star reward) is untouched.

**Tech Stack:** ArkTS, HarmonyOS ArkUI `@ComponentV2`, `TransitionEffect`, `Curve`, Hypium source-level tests, hvigor `assembleHap`.

## Global Constraints

- Only two files change: `entry/src/main/ets/components/verticalMath/VerticalMathStepNarrator.ets` and `entry/src/main/ets/components/VerticalMathCard.ets`.
- The narrator must never use `Scroller` / `List` / `ForEach` / `StepCard` / `renderStepCard` / `aboutToUpdate` (per spec §4 source assertion).
- `VerticalMathCard.build()` must render narrator → board → controls in both `isCompact()` and largeSize branches (per spec §4 source assertion).
- Solver, tool protocol, card state machine, `onAnswer`, star reward, `regenerateSolution`, `parseToolCallArguments`, and `isAnswered` re-mount logic stay intact.
- Single-line text format: `${title}：${narration}` using full-width Chinese colon `：` (U+FF1A) when both are non-empty; only `title` if `narration` is empty; only `narration` if `title` is empty.
- Empty state when `visibleStepCount === 0` (or `steps.length === 0`): show a placeholder like `点击下方"下一步 →"开始查看`.
- Animation: `TransitionEffect.OPACITY.combine(TransitionEffect.move(TransitionEdge.START))` + `animation({ duration: 180, curve: Curve.EaseInOut })`.
- `operationLabel` (`第 N / M 步` etc.) remains the static small title at the top of the narrator — it does NOT animate and does NOT change.
- Hypium CLI is known broken on this project (see MEMORY.md). Verification = source assertions + clean `assembleHap`. DevEco Studio GUI verification is pending the user.

---

### Task 1: Single-line narrator above board

**Files:**
- Modify: `entry/src/main/ets/components/verticalMath/VerticalMathStepNarrator.ets` (full rewrite — keep imports/exports but replace build + helpers)
- Modify: `entry/src/main/ets/components/VerticalMathCard.ets:330-366` (swap narrator/board in both layout branches)
- Test: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets` (no new test needed — only solver change set was previously added; this task is pure UI)

**Interfaces:**
- Consumes: `VerticalMathStep` (existing import from `utils/VerticalMathSolver`).
- Produces: A `build()` that renders `operationLabel` as a static title and a single `Text` below it that combines `title + '：' + narration` (with empty-state fallback) with transition animation.

- [ ] **Step 1: Rewrite `VerticalMathStepNarrator.ets`**

  Replace the entire file contents with the following (preserve the existing imports for `VerticalMathStep` + `VERTICAL_MATH_NARRATOR_BG`; drop the imports that are no longer referenced — `VERTICAL_MATH_NARRATOR_ACTIVE_BG`, `VERTICAL_MATH_NARRATOR_ACTIVE_TEXT`, `VERTICAL_MATH_NARRATOR_DONE_BG`, `VERTICAL_MATH_NARRATOR_DONE_TEXT`):

  ```typescript
  // components/verticalMath/VerticalMathStepNarrator.ets
  // Single-line step narrator for vertical-math walk-through.
  // Renders the operation label as a static small title and a single
  // animated line below it showing the current step's title + narration.
  // Sits above VerticalMathBoard in VerticalMathCard's layout.

  import { VERTICAL_MATH_NARRATOR_BG } from '../../utils/VerticalMathColors'
  import { VerticalMathStep } from '../../utils/VerticalMathSolver'

  @ComponentV2
  export struct VerticalMathStepNarrator {
    @Param steps: VerticalMathStep[] = []
    @Param visibleStepCount: number = 0
    @Param operationLabel: string = ''

    private getCurrentStep(): VerticalMathStep | null {
      if (this.steps.length === 0) return null
      const idx = Math.max(0, Math.min(this.visibleStepCount - 1, this.steps.length - 1))
      return this.steps[idx]
    }

    private getNarrationLine(): string {
      if (this.visibleStepCount <= 0 || this.steps.length === 0) {
        return '点击下方"下一步 →"开始查看'
      }
      const step = this.getCurrentStep()
      if (step === null) {
        return '点击下方"下一步 →"开始查看'
      }
      const title = step.title.trim()
      const narration = step.narration.trim()
      if (title !== '' && narration !== '') {
        return `${title}：${narration}`
      }
      if (title !== '') return title
      if (narration !== '') return narration
      return '点击下方"下一步 →"开始查看'
    }

    build() {
      Column() {
        Text(this.operationLabel)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#665b84')
          .margin({ bottom: 6 })
        Text(this.getNarrationLine())
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#21153f')
          .lineHeight(22)
          .width('100%')
          .transition(
            TransitionEffect.OPACITY
              .combine(TransitionEffect.move(TransitionEdge.START))
              .animation({ duration: 180, curve: Curve.EaseInOut })
          )
      }
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(VERTICAL_MATH_NARRATOR_BG)
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }
  ```

  Notes:
  - Removed: `listScroller`, `aboutToAppear`, `aboutToUpdate`, all `isStepDone`/`isStepActive`/`getBadge*`/`getCardBg`/`getTextColor` helpers, the `StepCard` and `renderStepCard` @Builders, the `List`/`ForEach` from `build()`.
  - Kept: `@Param` surface (`steps`, `visibleStepCount`, `operationLabel`), the `VERTICAL_MATH_NARRATOR_BG` background, `VerticalMathStep` type import.
  - Animation: applied via `.transition()` on the changing `Text` so ArkUI fades + slides whenever the content swaps (i.e., when `visibleStepCount` changes).

- [ ] **Step 2: Swap narrator above board in `VerticalMathCard.ets`**

  In `build()`, the layout order in both branches is currently board → narrator. Swap to narrator → board. Keep the relative sizing (`.height('60%')`/`.height('40%')` for compact, `.layoutWeight(7)`/`.layoutWeight(3)` for largeSize) — only the order changes.

  In the `isCompact()` branch (currently around lines 330-345), replace:

  ```typescript
  Column() {
    VerticalMathBoard({...})
      .height('60%')
    VerticalMathStepNarrator({...})
      .height('40%')
  }
  ```

  with:

  ```typescript
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
  }
  ```

  Notes:
  - Drop the explicit `.height('60%')` / `.height('40%')` on the two children — let the outer `Column` (which already has `.layoutWeight(1)`) distribute naturally. The narrator is now a compact strip, so its intrinsic height suffices; the board expands to fill the rest.
  - Keep the outer `.padding({ left: 12, right: 12, bottom: 12 })` and `.layoutWeight(1)` unchanged.

  In the largeSize branch (currently around lines 348-365), replace:

  ```typescript
  Row() {
    VerticalMathBoard({...})
      .layoutWeight(7)
    VerticalMathStepNarrator({...})
      .layoutWeight(3)
  }
  ```

  with:

  ```typescript
  Column() {
    VerticalMathStepNarrator({
      steps: this.solution.steps,
      visibleStepCount: this.visibleStepCount,
      operationLabel: `第 ${this.visibleStepCount} / ${this.solution.steps.length} 步`
    })
    .margin({ bottom: 10 })
    Row() {
      VerticalMathBoard({
        solution: this.solution,
        visibleStepCount: this.visibleStepCount,
        compact: false
      })
      .layoutWeight(1)
    }
    .layoutWeight(1)
  }
  ```

  Notes:
  - The largeSize branch becomes a top-level Column: narrator strip on top, board below filling the rest. This was previously a `Row` splitting board/narrator 70/30 — now the narrator is a header strip and the board takes the full width below.
  - Keep the outer `.layoutWeight(1)` and `.padding(12)` unchanged.

  Do NOT modify:
  - `regenerateSolution()` / `parseToolCallArguments()` / `handleStart` / `handleNext` / `handlePrev` / `handleReset`
  - `InputForm()` / `Controls()` builders
  - `isCompleteVerticalMathArgs()` helper
  - `aboutToAppear()` (including the `isAnswered` re-mount jump to final step)
  - Imports (both `VerticalMathBoard` and `VerticalMathStepNarrator` are already imported)

- [ ] **Step 3: Run focused source assertions**

  Verify the four spec §4 source-level invariants from a single Node one-liner. Expected: PASS.

  ```bash
  node -e "
  const fs = require('fs');
  const narrator = fs.readFileSync('entry/src/main/ets/components/verticalMath/VerticalMathStepNarrator.ets', 'utf8');
  const card = fs.readFileSync('entry/src/main/ets/components/VerticalMathCard.ets', 'utf8');

  const checks = {
    narrator_no_scroller: !narrator.includes('Scroller'),
    narrator_no_list: !narrator.includes('List({') && !narrator.includes('List()'),
    narrator_no_foreach: !narrator.includes('ForEach('),
    narrator_no_stepcard: !narrator.includes('StepCard'),
    narrator_no_render_step_card: !narrator.includes('renderStepCard'),
    narrator_no_about_to_update: !narrator.includes('aboutToUpdate'),
    narrator_has_transition: narrator.includes('TransitionEffect.OPACITY') &&
      narrator.includes('TransitionEffect.move(TransitionEdge.START)') &&
      narrator.includes('animation({ duration: 180, curve: Curve.EaseInOut })'),
    narrator_has_empty_state: narrator.includes('点击下方'),
    narrator_has_chinese_colon: narrator.includes('：'),

    card_compact_order: (() => {
      const compact = card.match(/if \\(this\\.isCompact\\(\\)\\) \\{[\\s\\S]*?\\} else/);
      if (!compact) return false;
      const block = compact[0];
      const narratorIdx = block.indexOf('VerticalMathStepNarrator({');
      const boardIdx = block.indexOf('VerticalMathBoard({');
      return narratorIdx !== -1 && boardIdx !== -1 && narratorIdx < boardIdx;
    })(),
    card_large_order: (() => {
      const large = card.match(/\\} else \\{[\\s\\S]*?\\n      \\}/);
      if (!large) return false;
      const block = large[0];
      const narratorIdx = block.indexOf('VerticalMathStepNarrator({');
      const boardIdx = block.indexOf('VerticalMathBoard({');
      return narratorIdx !== -1 && boardIdx !== -1 && narratorIdx < boardIdx;
    })(),
  };

  const fails = Object.entries(checks).filter(([k, v]) => !v);
  if (fails.length) {
    console.error('FAIL:', fails.map(f => f[0]).join(', '));
    process.exit(1);
  }
  for (const [k, v] of Object.entries(checks)) console.log(k, '=', v);
  console.log('PASS: all source assertions');
  "
  ```

  Output (post-edit):
  ```
  narrator_no_scroller = true
  narrator_no_list = true
  narrator_no_foreach = true
  narrator_no_stepcard = true
  narrator_no_render_step_card = true
  narrator_no_about_to_update = true
  narrator_has_transition = true
  narrator_has_empty_state = true
  narrator_has_chinese_colon = true
  card_compact_order = true
  card_large_order = true
  PASS: all source assertions
  ```

- [ ] **Step 4: Hand-trace the narration line per `visibleStepCount`**

  Walk through the visible-state matrix for the combined text format. No code to run — read the helper logic and confirm each case produces the expected string. Expected: all cases match.

  | `visibleStepCount` | `steps.length` | `steps[idx].title` | `steps[idx].narration` | Expected line |
  |---|---|---|---|---|
  | 0 | 3 | n/a | n/a | `点击下方"下一步 →"开始查看` |
  | 1 | 3 | `'第 1 位相加'` | `'3 + 8 = 11'` | `第 1 位相加：3 + 8 = 11` |
  | 1 | 3 | `'第 1 位相加'` | `''` | `第 1 位相加` |
  | 2 | 3 | `'得到结果'` | `''` | `得到结果` |
  | 2 | 3 | `''` | `'合并得到答案'` | `合并得到答案` |
  | 3 (final) | 3 | `'得到答案'` | `'75'` | `得到答案：75` |
  | 1 | 0 | n/a | n/a | `点击下方"下一步 →"开始查看` |
  | 5 (over-clamp) | 3 | `'得到答案'` | `'75'` | `得到答案：75` (idx clamped to 2) |

  Trace each row through `getNarrationLine()`:
  - Row 1: `visibleStepCount <= 0` → return empty state.
  - Row 2: idx = max(0, min(0, 2)) = 0; both non-empty → title + ： + narration.
  - Row 3: idx = 0; narration empty → only title.
  - Row 4: idx = 1; narration empty → only title.
  - Row 5: idx = 1; title empty → only narration.
  - Row 6: idx = max(0, min(2, 2)) = 2; both non-empty → combined.
  - Row 7: `steps.length === 0` → empty state.
  - Row 8: idx = max(0, min(4, 2)) = 2 (clamped to length-1) → combined.

  All 8 cases produce the expected line.

- [ ] **Step 5: Build and verify**

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

  Expected: file present, mtime newer than `VerticalMathStepNarrator.ets` and `VerticalMathCard.ets`.

  Record Hypium as DevEco-only per the documented MEMORY.md limitation.

- [ ] **Step 6: Commit**

  ```bash
  git add entry/src/main/ets/components/verticalMath/VerticalMathStepNarrator.ets \
          entry/src/main/ets/components/VerticalMathCard.ets
  git commit -m "feat(vertical-math): single-line step narrator above board"
  ```

---

## Self-review checklist

- Spec coverage:
  - Spec §3.1 (narrator: remove scroll scaffolding, compute current step, combine title+narration with full-width colon, handle three cases title/narration/both, empty state, transition animation, keep `operationLabel`) — Task 1 Step 1.
  - Spec §3.2 (card: move narrator above board in both `largeSize` branches, don't touch other behavior) — Task 1 Step 2.
  - Spec §4 source assertions (no Scroller/List/ForEach/StepCard in narrator; narrator→board→controls order in card) — Task 1 Step 3.
  - Spec §4 hand-trace of step transitions — Task 1 Step 4.
  - Spec §4 `assembleHap` clean — Task 1 Step 5.
- Placeholder scan: no TBD/TODO; Step 1 contains the full file body; Step 2 contains the exact replacement blocks; the source-assertion script is concrete.
- Type consistency: `VerticalMathStep` import preserved; `getCurrentStep` return type `VerticalMathStep | null` matches the `null` check inside `getNarrationLine`; no other types change.
- Scope discipline: only two files modified; no solver/tool/protocol/MathQuiz/EnglishQuiz/MessageBubble/star changes.