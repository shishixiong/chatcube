# Vertical Math Auto-Solve on AI Params Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When AI supplies a complete `vertical_math` tool call, render the vertical-math display directly without the manual "28 + 33 / operator / 开始计算" form.

**Architecture:** `VerticalMathCard` already parses `toolCall.arguments` into local state and `regenerateSolution()` already drives the display. Add a private completeness check after parsing; in `aboutToAppear`, if the card is interactive and the operands are complete, call `regenerateSolution()` so the build path renders the board. Incomplete or invalid operands fall back to the existing input form. No tool/schema/mount changes.

**Tech Stack:** ArkTS, HarmonyOS ArkUI `@ComponentV2`, Hypium source-level tests, hvigor `assembleHap`.

## Global Constraints

- Auto-solve triggers only when `isAnswered === false` and all three params (`operation`, `operand_a`, `operand_b`) are present with `operand_a` and `operand_b` in 0–999.
- `operation` must be one of `add` / `subtract` / `multiply` / `divide` (the enum in `utils/VerticalMathSolver.ets`).
- Fall back to the input form for any other case (missing operand, out-of-range operand, unknown operation).
- Do not modify `MessageBubble`, tool protocol, `ToolExecutionService`, `onAnswer`, star reward, or `VerticalMathSolver` math.
- The `isAnswered === true` regression-fix path remains untouched.
- Verify with a clean `assembleHap`; Hypium CLI is known broken on the repository's pre-existing generated-test path mismatch, so record DevEco GUI testing as pending when CLI is unavailable.

---

### Task 1: Auto-solve when AI params are complete

**Files:**
- Modify: `entry/src/main/ets/components/VerticalMathCard.ets:61-94, 99-114`
- Test: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets:1-30` (only as scaffolding reference; no test changes required because the auto-solve lives in a UI component, and the existing tests cover the math)

**Interfaces:**
- Consumes: `toolCall.arguments` JSON string, the `VerticalMathOperation` enum, and the existing local fields populated by `parseToolCallArguments()`.
- Produces: a new private helper `hasCompleteOperands(): boolean` and an auto-solve call in `aboutToAppear()` when interactive and complete.

- [ ] **Step 1: Add the completeness check helper**

  In `VerticalMathCard.ets`, add a file-private helper near the existing top-level constants (after `OPERATION_BUTTONS`):

  ```typescript
  function isCompleteVerticalMathArgs(
    operation: string,
    operandA: number,
    operandB: number
  ): boolean {
    if (operation !== VerticalMathOperation.ADD &&
      operation !== VerticalMathOperation.SUBTRACT &&
      operation !== VerticalMathOperation.MULTIPLY &&
      operation !== VerticalMathOperation.DIVIDE) {
      return false
    }
    if (!Number.isInteger(operandA) || operandA < 0 || operandA > 999) {
      return false
    }
    if (!Number.isInteger(operandB) || operandB < 0 || operandB > 999) {
      return false
    }
    return true
  }
  ```

  The function lives outside the `@ComponentV2` so the static TS checker treats it as a pure function; reuse the same enum as the solver to keep the accepted operations in lock-step.

- [ ] **Step 2: Use the helper in `aboutToAppear` after parsing**

  In `aboutToAppear()`, after the existing `parseToolCallArguments()` call and the existing `isAnswered` branch, add the auto-solve trigger. The current local fields for parsed values are `this.operation`, `this.operandA`, `this.operandB` (verify by reading `parseToolCallArguments` first; if the implementation keeps the values in a different shape, adjust the call sites below to use the existing local fields). The final shape of the change inside `aboutToAppear` is:

  ```typescript
  aboutToAppear() {
    this.parseToolCallArguments()
    if (this.isAnswered) {
      this.regenerateSolution()
      if (this.solution !== null && this.solution.steps.length > 0) {
        this.visibleStepCount = this.solution.steps.length
      }
    } else if (isCompleteVerticalMathArgs(this.operation, this.operandA, this.operandB)) {
      this.regenerateSolution()
    }
  }
  ```

  Do not touch `regenerateSolution()` itself, the `isAnswered` branch, or any other lifecycle method.

- [ ] **Step 3: Run focused source assertions**

  Run the existing source-assertion command used for vertical-math work (the same one that exercised the marker highlight task). Expected: PASS — the helper is a pure function over already-typed values; no new code paths touch the solver. If the command is unavailable in this environment, hand-trace the four spec cases:

  1. `{operation:'add', operand_a:28, operand_b:33}` → helper returns true → `regenerateSolution()` runs → display renders.
  2. `{operation:'add'}` (missing operands) → helper returns false → input form renders.
  3. `{operation:'add', operand_a:2000, operand_b:33}` → helper returns false (operandA out of range) → input form renders.
  4. `isAnswered === true` → no change to the existing branch.

  Record Hypium as DevEco-only per the documented repository limitation.

- [ ] **Step 4: Build and verify**

  Run:

  ```bash
  DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
    /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
    --mode module -p product=default -p buildMode=debug
  ```

  Expected: `BUILD SUCCESSFUL` and a regenerated `entry/build/default/outputs/default/entry-default-signed.hap`.

- [ ] **Step 5: Commit**

  ```bash
  git add entry/src/main/ets/components/VerticalMathCard.ets
  git commit -m "feat(vertical-math): auto-solve when AI supplies full operands"
  ```

---

## Self-review checklist

- Spec coverage: auto-solve on complete params (Step 2), fallback for missing/out-of-range/unknown operation (Step 1), preserved `isAnswered` branch (Step 2), no tool/mount/nav changes (Step 2 explicitly only touches `aboutToAppear`), clean build (Step 4) are all covered by Task 1.
- Placeholder scan: no TBD/TODO; the helper body is complete; the build command is concrete.
- Type consistency: `VerticalMathOperation` is the same enum the solver uses; the helper signature is `function isCompleteVerticalMathArgs(operation: string, operandA: number, operandB: number): boolean`; `aboutToAppear` only references `this.operation` / `this.operandA` / `this.operandB` (existing local fields) plus the new helper.
