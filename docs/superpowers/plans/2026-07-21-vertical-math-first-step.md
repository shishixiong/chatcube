# 竖式计算:首步直达计算 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在四种竖式运算求解器中移除独立的"数位对齐"步骤,使首次"下一步"直接进入个位/最高位计算。

**Architecture:** 求解器删去 `alignStep` 局部变量、`steps.push(alignStep)` 和对应的中间 row 变量;`initialRows` 保持不变(继续承担"开始计算"后的对齐显示);测试文件相应下调 step 索引并补充新的 `steps[0].title` 断言。

**Tech Stack:** ArkTS 严格模式,`@ohos/hypium` 单元测试(`hvigorw test` 在本机 broken,见 `MEMORY.md`;DevEco Studio GUI 验证由用户执行)。`assembleHap` 验证编译。

## Global Constraints

- 仅修改 `entry/src/main/ets/utils/VerticalMathSolver.ets` 与 `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets` 两个文件。
- 不修改 `VerticalMathBoard.ets`、`VerticalMathCard.ets`、`StepNarrator.ets`、颜色 token、payload、星星奖励、工具注册、AI 提示词。
- 不得在四个求解器之外的源码里保留 `title: '数位对齐'` 字面量。
- 测试索引必须与新步骤长度精确一致;每个受影响的测试用 `node -e` 静态断言做最终回归。
- ArkTS 严格模式:不允许在 `@Builder` 内 `const` 声明、不允许解构赋值、不允许未注解的 inline 对象字面量返回类型。
- 提交:每个 task 一个 commit,commit subject 形如 `fix(vertical-math): remove alignment step from <op>`。
- 不动其他模块;不引入新文件。

---

## File Map

| 路径 | 角色 |
|------|------|
| `entry/src/main/ets/utils/VerticalMathSolver.ets` | 唯一源改动:删除四个求解器中的对齐步骤 |
| `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets` | 测试索引/断言改动;补充"无对齐步骤"断言 |
| `docs/superpowers/specs/2026-07-21-vertical-math-first-step-design.md` | 设计依据(已审) |

---

### Task 1: Addition solver — drop alignment step

**Files:**
- Modify: `entry/src/main/ets/utils/VerticalMathSolver.ets:189-199`
- Test: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets:82-140`

**Interfaces:**
- Consumes: existing `solveVerticalAdd(a, b): VerticalMathSolution`,`verticalMathSolverTest()`.
- Produces: `solveVerticalAdd` returns solution with `steps[0].title === '第 N 位相加'`(N = columnCount).

- [ ] **Step 1: Write the failing test (solver assertion via node)**

Run:
```bash
node -e 'const s=require("fs").readFileSync("entry/src/main/ets/utils/VerticalMathSolver.ets","utf8");if(s.includes("title: '\''数位对齐'\''")){console.error("FAIL: addition alignment title still present");process.exit(1)}'
```
Expected: exit code 1 with "FAIL: addition alignment title still present".

- [ ] **Step 2: Update the existing addition tests to the new step layout**

In `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets`, replace the `solveVerticalAdd` describe block (lines 82-140) with the assertions below. Each `it(...)` keeps the same numeric parameters; only step indices and title text change:

```typescript
  describe('solveVerticalAdd', () => {
    it('47 + 28 = 75 with one carry', 0, () => {
      const s = solveVerticalAdd(47, 28)
      expect(s.result).assertEqual(75)
      expect(s.remainder).assertEqual(0)
      expect(s.columnCount).assertEqual(2)
      // no standalone alignment step — first step is units computation
      expect(s.steps[0].title).assertEqual('第 2 位相加')
      const carrySteps = s.steps.filter((step: VerticalMathStep) =>
        step.rows.some((row: VerticalMathBoardRow) => row.topMark === '1'))
      expect(carrySteps.length).assertEqual(1)
      expect(s.steps[s.steps.length - 1].showResultRow).assertEqual(true)
      expect(s.finalRow?.cells.join('')).assertEqual('75')
    })

    it('100 + 200 = 300 with no carry', 0, () => {
      const s = solveVerticalAdd(100, 200)
      expect(s.result).assertEqual(300)
      expect(s.steps.every((step: VerticalMathStep) =>
        !step.rows.some((row: VerticalMathBoardRow) => row.topMark === '1'))).assertEqual(true)
    })

    it('999 + 1 = 1000 (carry cascades)', 0, () => {
      const s = solveVerticalAdd(999, 1)
      expect(s.result).assertEqual(1000)
      expect(s.columnCount).assertEqual(4)
      const carrySteps = s.steps.filter((step: VerticalMathStep) =>
        step.rows.some((row: VerticalMathBoardRow) => row.topMark === '1'))
      expect(carrySteps.length >= 3).assertEqual(true)
    })

    it('0 + 0 = 0', 0, () => {
      const s = solveVerticalAdd(0, 0)
      expect(s.result).assertEqual(0)
      expect(s.columnCount).assertEqual(1)
    })

    it('marks each newly written addition result digit active', 0, () => {
      const s = solveVerticalAdd(22, 33)
      for (let index = 0; index < s.steps.length - 1; index++) {
        const expectedColumn: number = s.columnCount - 1 - index
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
      expect(s.steps[0].rows[0].carryColumns?.includes(0) ?? false).assertEqual(true)
      expect(s.steps[1].rows[0].carryColumns?.includes(0) ?? false).assertEqual(true)
      expect(s.steps[s.steps.length - 1].rows[0].carryColumns?.includes(0) ?? false).assertEqual(true)
    })
  })
```

- [ ] **Step 3: Drop the alignment step in `solveVerticalAdd`**

In `entry/src/main/ets/utils/VerticalMathSolver.ets` (lines 189-199), delete the entire block from `// Step 1: alignment (no computation yet).` through `steps.push(alignStep)`, including the three `alignRow*` const declarations. The function should go straight from `const steps: VerticalMathStep[] = []` into the per-column loop. Also delete the obsolete `// Step 1: alignment (no computation yet).` comment.

Resulting code (the deletion target is everything between the two highlighted lines):
```typescript
  const steps: VerticalMathStep[] = []

  // Digit-by-digit, right to left. Reveal one result digit per step and mark carries.
  const revealed: string[] = emptyCells(columnCount)
  const carryColumns: Set<number> = new Set<number>()
  let carryIn: number = 0
  for (let col = columnCount - 1; col >= 0; col--) {
```

Also update the JSDoc on the function (line 165) from:
```typescript
 * - steps[0]: alignment narration ('数位对齐')
```
to:
```typescript
 * - steps[0..N-1]: per-column computation right-to-left (first step is units, no alignment step)
```

- [ ] **Step 4: Verify red → green source assertion**

Run:
```bash
node -e 'const s=require("fs").readFileSync("entry/src/main/ets/utils/VerticalMathSolver.ets","utf8");if(s.includes("title: '\''数位对齐'\''")){console.error("FAIL: addition alignment title still present");process.exit(1)}console.log("PASS: addition alignment removed")'
```
Expected: `PASS: addition alignment removed` and exit 0.

- [ ] **Step 5: Build the HAP**

Run:
```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug
```
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/utils/VerticalMathSolver.ets entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets
git commit -m "fix(vertical-math): remove alignment step from addition"
```

---

### Task 2: Subtraction solver — drop alignment step

**Files:**
- Modify: `entry/src/main/ets/utils/VerticalMathSolver.ets:335-345`
- Test: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets:142-187`

**Interfaces:**
- Consumes: `solveVerticalSubtract(a, b)`, `verticalMathSolverTest()`.
- Produces: `steps[0].title === '第 N 位相减'` (N = columnCount).

- [ ] **Step 1: Write the failing test (solver assertion via node)**

Run:
```bash
node -e 'const s=require("fs").readFileSync("entry/src/main/ets/utils/VerticalMathSolver.ets","utf8");if(s.includes("title: '\''数位对齐'\''")){console.error("FAIL: subtraction alignment title still present");process.exit(1)}'
```
Expected: exit code 1 with "FAIL: subtraction alignment title still present".

- [ ] **Step 2: Update the existing subtraction tests**

In `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets`, replace the `solveVerticalSubtract` describe block (lines 142-187) with:

```typescript
  describe('solveVerticalSubtract', () => {
    it('503 - 278 = 225 with cascading borrow', 0, () => {
      const s = solveVerticalSubtract(503, 278)
      expect(s.result).assertEqual(225)
      const borrowSteps = s.steps.filter((step: VerticalMathStep) =>
        step.rows.some((row: VerticalMathBoardRow) => row.topMark === '•'))
      expect(borrowSteps.length >= 1).assertEqual(true)
    })

    it('100 - 50 = 50 with no borrow', 0, () => {
      const s = solveVerticalSubtract(100, 50)
      expect(s.result).assertEqual(50)
      const borrowSteps = s.steps.filter((step: VerticalMathStep) =>
        step.rows.some((row: VerticalMathBoardRow) => row.topMark === '•'))
      expect(borrowSteps.length).assertEqual(0)
    })

    it('999 - 999 = 0', 0, () => {
      const s = solveVerticalSubtract(999, 999)
      expect(s.result).assertEqual(0)
      expect(s.columnCount).assertEqual(3)
    })

    it('keeps cascade borrow columns and marks each new result active', 0, () => {
      const s = solveVerticalSubtract(303, 178)
      for (let index = 0; index < s.steps.length - 1; index++) {
        const marks: number[] = s.steps[index].rows[0].borrowColumns ?? []
        expect(marks.includes(0)).assertEqual(true)
        expect(marks.includes(1)).assertEqual(true)
        expect(marks.includes(2)).assertEqual(true)

        const expectedColumn: number = s.columnCount - 1 - index
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
  })
```

- [ ] **Step 3: Drop the alignment step in `solveVerticalSubtract`**

In `entry/src/main/ets/utils/VerticalMathSolver.ets` (lines 335-345), delete the same alignment block: comment `// Step 1: alignment (no computation yet).`, three `alignRow*` consts, the `alignStep` const, and `steps.push(alignStep)`. The function should go straight from `const steps: VerticalMathStep[] = []` into the per-column loop. Also delete the obsolete alignment comment.

Update the JSDoc on `solveVerticalSubtract` (line 307) from:
```typescript
 * - steps[0]: alignment narration ('数位对齐')
```
to:
```typescript
 * - steps[0..N-1]: per-column computation right-to-left (first step is units, no alignment step)
```

- [ ] **Step 4: Verify red → green source assertion**

Run:
```bash
node -e 'const s=require("fs").readFileSync("entry/src/main/ets/utils/VerticalMathSolver.ets","utf8");if(s.includes("title: '\''数位对齐'\''")){console.error("FAIL: subtraction alignment title still present");process.exit(1)}console.log("PASS: subtraction alignment removed")'
```
Expected: `PASS: subtraction alignment removed` and exit 0.

- [ ] **Step 5: Build the HAP**

Run:
```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug
```
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/utils/VerticalMathSolver.ets entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets
git commit -m "fix(vertical-math): remove alignment step from subtraction"
```

---

### Task 3: Multiplication solver — drop alignment step

**Files:**
- Modify: `entry/src/main/ets/utils/VerticalMathSolver.ets:566-575`
- Test: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets:189-240`

**Interfaces:**
- Consumes: `solveVerticalMultiply(a, b)`, `verticalMathSolverTest()`.
- Produces: `steps[0].title === '个：...'` (first partial-product step).

- [ ] **Step 1: Write the failing test (solver assertion via node)**

Run:
```bash
node -e 'const s=require("fs").readFileSync("entry/src/main/ets/utils/VerticalMathSolver.ets","utf8");if(s.includes("title: '\''数位对齐'\''")){console.error("FAIL: multiplication alignment title still present");process.exit(1)}'
```
Expected: exit code 1 with "FAIL: multiplication alignment title still present".

- [ ] **Step 2: Update the existing multiplication tests**

In `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets`, replace the `solveVerticalMultiply` describe block (lines 189-240) with:

```typescript
  describe('solveVerticalMultiply', () => {
    it('988 × 6 = 5928 with three aligned partial products', 0, () => {
      const s = solveVerticalMultiply(988, 6)
      expect(s.result).assertEqual(5928)
      expect(s.columnCount).assertEqual(4)
      const expectedRows: string[] = ['  48', ' 48 ', '54  ']
      for (let index = 0; index < expectedRows.length; index++) {
        expect(s.steps[index].rows[s.steps[index].rows.length - 1].cells.join(''))
          .assertEqual(expectedRows[index])
      }
      expect(s.steps.every((step: VerticalMathStep) =>
        !step.rows.some((row: VerticalMathBoardRow) => row.topMark === '1'))).assertEqual(true)
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
      for (let index = 0; index < 3; index++) {
        const activeHighlights = s.steps[index].highlights.filter(highlight => highlight.kind === 'active')
        expect(activeHighlights.length >= 2).assertEqual(true)
        expect(activeHighlights.some(highlight => highlight.rowIndex === 1)).assertEqual(true)
        expect(activeHighlights.some(highlight => highlight.rowIndex === 0)).assertEqual(true)
      }
    })

    it('marks every non-empty current partial-product cell active', 0, () => {
      const s = solveVerticalMultiply(988, 6)
      for (let index = 0; index < 3; index++) {
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
  })
```

- [ ] **Step 3: Drop the alignment step in `solveVerticalMultiply`**

In `entry/src/main/ets/utils/VerticalMathSolver.ets` (lines 566-575), replace the inlined alignment step:
```typescript
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
```
with:
```typescript
  const steps: VerticalMathStep[] = []
```

The function should now go from `const steps: VerticalMathStep[] = []` directly into the `partialRows` loop. The JSDoc on the function is at line 540 area — there is no separate `steps[0]` comment to update, but the file-level description of multiplication flow stays accurate.

- [ ] **Step 4: Verify red → green source assertion**

Run:
```bash
node -e 'const s=require("fs").readFileSync("entry/src/main/ets/utils/VerticalMathSolver.ets","utf8");if(s.includes("title: '\''数位对齐'\''")){console.error("FAIL: multiplication alignment title still present");process.exit(1)}console.log("PASS: multiplication alignment removed")'
```
Expected: `PASS: multiplication alignment removed` and exit 0.

- [ ] **Step 5: Build the HAP**

Run:
```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug
```
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/utils/VerticalMathSolver.ets entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets
git commit -m "fix(vertical-math): remove alignment step from multiplication"
```

---

### Task 4: Division solver — drop alignment step (main path + a=0 special)

**Files:**
- Modify: `entry/src/main/ets/utils/VerticalMathSolver.ets:704-714` and `760-770`
- Test: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets:242-289`

**Interfaces:**
- Consumes: `solveVerticalDivide(a, b)`, `verticalMathSolverTest()`.
- Produces: in the main path, `steps[0]` is the first "第 1 位：..." step (试商 or 不够除);in the `a === 0` special path, `steps.length === 1` and `steps[0].title === '得到答案'`.

- [ ] **Step 1: Write the failing test (solver assertion via node)**

Run:
```bash
node -e 'const s=require("fs").readFileSync("entry/src/main/ets/utils/VerticalMathSolver.ets","utf8");if(s.includes("title: '\''数位对齐'\''")){console.error("FAIL: division alignment title still present");process.exit(1)}'
```
Expected: exit code 1 with "FAIL: division alignment title still present".

- [ ] **Step 2: Update the existing division tests**

In `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets`, replace the `solveVerticalDivide` describe block (lines 242-289) with:

```typescript
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
      expect(s.steps.some((step: VerticalMathStep) => step.narration.includes('首位不够除'))).assertEqual(true)
    })

    it('0 ÷ 5 = 0 remainder 0', 0, () => {
      const s = solveVerticalDivide(0, 5)
      expect(s.result).assertEqual(0)
      expect(s.remainder).assertEqual(0)
      // No alignment step: only the final answer step remains.
      expect(s.steps.length).assertEqual(1)
      expect(s.steps[0].title).assertEqual('得到答案')
    })

    it('999 ÷ 9 = 111 remainder 0', 0, () => {
      const s = solveVerticalDivide(999, 9)
      expect(s.result).assertEqual(111)
      expect(s.remainder).assertEqual(0)
    })

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
  })
```

- [ ] **Step 3: Drop the alignment step in `solveVerticalDivide`**

Two sites:

a) **a === 0 special path (lines 704-714):** delete the comment `// Step 1: alignment (no computation yet).`, the three `alignRow*` consts, the `alignStep` const, and `steps.push(alignStep)`. The function should go from `const steps: VerticalMathStep[] = []` directly to the `finalStep` block.

b) **Main path (lines 760-770):** delete the comment `// Step 0: alignment`, the three `alignRow*` consts, the `alignStep` const, and `steps.push(alignStep)`. The function should go from `const steps: VerticalMathStep[] = []` directly to the long-division `for` loop. Also delete the stale comment `// Step 0: alignment` only (do not delete the surrounding per-digit loop comments).

The surrounding comments inside the `for` loop that narrate "不够除，先看下一位" stay untouched.

- [ ] **Step 4: Verify red → green source assertion**

Run:
```bash
node -e 'const s=require("fs").readFileSync("entry/src/main/ets/utils/VerticalMathSolver.ets","utf8");if(s.includes("title: '\''数位对齐'\''")){console.error("FAIL: division alignment title still present");process.exit(1)}console.log("PASS: division alignment removed")'
```
Expected: `PASS: division alignment removed` and exit 0.

- [ ] **Step 5: Build the HAP**

Run:
```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug
```
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/utils/VerticalMathSolver.ets entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets
git commit -m "fix(vertical-math): remove alignment step from division"
```

---

### Task 5: Final verification — full gauntlet + whole-branch review

**Files:**
- Verify: `entry/src/main/ets/utils/VerticalMathSolver.ets`
- Verify: `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets`

**Interfaces:**
- Consumes: 4 implementation commits from Tasks 1-4.
- Produces: whole-branch review record; no source changes.

- [ ] **Step 1: Run the full source-assertion gauntlet**

Run:
```bash
node -e '
const fs = require("fs");
const path = require("path");
const root = "entry/src";
function walk(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(p));
    else if (entry.isFile() && p.endsWith(".ets")) out.push(p);
  }
  return out;
}
const files = walk(root);
let bad = 0;
for (const f of files) {
  const s = fs.readFileSync(f, "utf8");
  if (s.includes("title: '\''数位对齐'\''")) {
    console.error("FAIL: alignment title still present in " + f);
    bad++;
  }
}
if (bad > 0) process.exit(1);
console.log("PASS: no alignment title in " + files.length + " ets files under entry/src");
'
```
Expected: `PASS: no alignment title in N ets files under entry/src` with N > 0 and exit 0.

- [ ] **Step 2: Confirm 4 commits on `math_teacher`**

Run:
```bash
git log -4 --oneline
```
Expected output (order newest first):
```
<task4 commit> fix(vertical-math): remove alignment step from division
<task3 commit> fix(vertical-math): remove alignment step from multiplication
<task2 commit> fix(vertical-math): remove alignment step from subtraction
<task1 commit> fix(vertical-math): remove alignment step from addition
```

- [ ] **Step 3: Run a final clean `assembleHap`**

Run:
```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw clean --mode module -p product=default
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug
```
Expected: `BUILD SUCCESSFUL` and `entry/build/default/outputs/default/entry-default-signed.hap` regenerated.

- [ ] **Step 4: Hand off to user for DevEco Studio test + device smoke**

The 4/4 source changes are in place. The user runs `VerticalMathSolver.test.ets` in DevEco Studio (37/37 expected) and confirms in the chat UI:
- 22 + 33: first 下一步 shows units step, second 下一步 shows tens step (yellow 5 in tens result cell, mint 5 in ones).
- 503 - 278: first 下一步 shows units step, borrow markers carry through.
- 988 × 6: first 下一步 shows 个:8×6=48 partial product.
- 84 ÷ 4: first 下一步 shows 第 1 位:试商 2.
- 0 ÷ 5: first 下一步 shows 0 directly.
- Result payload `step_count` reflects the reduced step count (e.g. 3 for 22+33 instead of 4).
