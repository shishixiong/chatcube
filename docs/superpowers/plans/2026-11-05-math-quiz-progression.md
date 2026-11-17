# math_quiz 难度渐进 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record every `math_quiz` answer, gate the next question against the child's current level, and advance/downgrade after 10 first-try corrects / 2 two-wrong questions.

**Architecture:** A pure classifier (`utils/MathQuizProgression.ets`) turns a quiz's structure into `(track, level)`, a pure state machine updates a per-track progress row, and a thin `MathQuizHistoryService` connects them to two new SQLite tables. `ToolExecutionService.handleMathQuiz` validates, gates, then records; the answer hint is appended only to `ToolResult.content`, never to `toolCall.approvalReason`.

**Tech Stack:** ArkTS (HarmonyOS 6 / API 23), `@ohos/hypium`, relamStore `relationalStore`, `PreferencesService`-backed child profile.

**Spec:** `docs/superpowers/specs/2026-11-05-math-quiz-progression-design.md`

## Global Constraints

- ArkTS strict mode: no array/object destructuring (`10605074`); no inline object literals in `.map()` without an explicit return type (`10605038`); `Record<string, V>` literals must use quoted keys (`10605034`); no `const` declarations directly inside `@Builder` bodies (not relevant here, but do not introduce them).
- Do not modify `MathQuizCard.ets`, `MessageBubble.ets`, `MathQuizGame.ets`, `MathQuizValidation.ets`, `StarRewardService.ets`, `StarEventModels.ets`, `ChildProfileService.ets`, or the lesson-planning/evaluation services.
- `validateMathQuizArgs()` stays first in `handleMathQuiz`; the new gate runs after it and before `approvalState = 'pending'`.
- `toolCall.approvalReason` stays the pure `answerJson`. `math_progress` is merged only into `ToolResult.content`.
- Every DB write failure is logged and swallowed; it must never block the card or the tool result.
- Max 3 binary operators; all arithmetic operands, intermediates, and results must be `<= 99999` and non-negative.
- `child_profile` output keeps camelCase outer keys (`mathProgress`), and `nextTarget` uses the same snake_case inner keys as the gate `target`.
- Test verification: hypium files run in DevEco Studio (right-click → Run); CLI verification is a clean `assembleHap` build. `hvigorw test` is known-broken in this repo.
- Build command:
  ```bash
  DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
    /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
    --mode module -p product=default -p buildMode=debug
  ```

## Review Focus

These are the inputs the spec implies but does not pin down; each has a test in the owning task.

1. **U+2212 minus / full-width operators** — `sanitizeExpression` drops `−` (U+2212); normalize it to ASCII `-` before tokenizing, keying, or evaluating, or the expression silently becomes `4728`. The same mangling happens in the existing validator, so `handleMathQuiz` must normalize `toolCall.arguments` before `validateMathQuizArgs` runs (Task 2 tests the pure normalizer; Task 6 normalizes the tool-call arguments).
2. **Decimal operands** — `1.5 + 2` must be `track='none'`, `gate=false`, not a structural error (Task 2 test).
3. **Unary / negative operands** — `-3 + 5` and `3 + -2` must reject with a `difficulty_gate` error; the existing validator only checks the final value (Task 2 tests).
4. **Division with a remainder** — `7 ÷ 2`, `10 ÷ 3`, `12 ÷ 5 × 3` must reject for all purposes, not fall through to a level (Task 2 tests).
5. **Gated arithmetic with no `expression`** — a word problem or `math_addition` question without a hidden expression must reject with an executable target, while `math_counting` with no expression is allowed as `track='none'` (Task 2/3 tests).

---

### Task 1: Progression models, normalizers, spec table, target builder

**Files:**
- Create: `entry/src/main/ets/models/MathQuizProgressionModels.ets`
- Create: `entry/src/main/ets/utils/MathQuizProgression.ets`
- Test: `entry/src/ohosTest/ets/test/utils/MathQuizProgression.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

**Interfaces:**
- Consumes: `sanitizeExpression`, `normalizeQuizType`, `tryEvaluateExpression`, `tokenizeExpression` from `utils/MathQuizGame.ets`.
- Produces:
  - `MathQuizTrack = 'add' | 'sub' | 'muldiv' | 'compare' | 'clock' | 'elapsed' | 'shape' | 'none'`
  - `MathQuizPurpose = 'practice' | 'warm_up' | 'review'`
  - `MathQuizProgressStatus = 'in_progress' | 'level_up' | 'level_down' | 'max_level' | 'not_counted'`
  - `MathQuizProgressReason = 'first_try_correct' | 'second_try' | 'two_wrong' | 'warm_up' | 'review' | 'stale_level'`
  - `normalizePurpose(raw: string): MathQuizPurpose`
  - `normalizeSkillKey(raw: string): string`
  - `normalizeExpressionKey(input: MathQuizLevelInput): string`
  - `buildMathQuizRecordExpression(input: MathQuizLevelInput): string`
  - `getMaxLevel(track: MathQuizTrack): number`
  - `getLevelSpec(track: MathQuizTrack, level: number): MathQuizLevelSpec | null`
  - `getTrackLabel(track: MathQuizTrack): string`
  - `buildTarget(spec: MathQuizLevelSpec): MathQuizTarget`
  - `initialLevelForTrack(track: MathQuizTrack, levels: Record<string, number>): number`
  - `MATH_QUIZ_NEEDED_CORRECT = 10`, `MATH_QUIZ_RECENT_LIMIT = 20`, `MATH_QUIZ_WARM_UP_LIMIT = 5`, `MATH_QUIZ_REVIEW_LIMIT = 3`, `MATH_QUIZ_WRONG_RESET_MS = 24 * 60 * 60 * 1000`

- [ ] **Step 1: Write the failing tests for normalizers, spec table, target, and initial levels**

Create `entry/src/ohosTest/ets/test/utils/MathQuizProgression.test.ets`:

```ts
import { describe, it, expect } from '@ohos/hypium'
import {
  buildMathQuizRecordExpression, buildTarget, getLevelSpec, getMaxLevel, getTrackLabel,
  initialLevelForTrack, normalizeExpressionKey, normalizePurpose, normalizeSkillKey
} from '../../../../main/ets/utils/MathQuizProgression'
import { MathQuizLevelInput, MathQuizLevelSpec } from '../../../../main/ets/models/MathQuizProgressionModels'

function arithmetic(expression: string, skillKey: string = ''): MathQuizLevelInput {
  const input: MathQuizLevelInput = {
    quizType: 'arithmetic', expression: expression, wordProblem: false, skillKey: skillKey,
    leftValue: 0, rightValue: 0, clockHour: 0, clockMinute: 0,
    startHour: 0, startMinute: 0, endHour: 0, endMinute: 0
  }
  return input
}

function comparison(left: number, right: number): MathQuizLevelInput {
  const input: MathQuizLevelInput = {
    quizType: 'comparison', expression: '', wordProblem: false, skillKey: '',
    leftValue: left, rightValue: right, clockHour: 0, clockMinute: 0,
    startHour: 0, startMinute: 0, endHour: 0, endMinute: 0
  }
  return input
}

function clock(hour: number, minute: number): MathQuizLevelInput {
  const input: MathQuizLevelInput = {
    quizType: 'time', expression: '', wordProblem: false, skillKey: '',
    leftValue: 0, rightValue: 0, clockHour: hour, clockMinute: minute,
    startHour: 0, startMinute: 0, endHour: 0, endMinute: 0
  }
  return input
}

function elapsed(sh: number, sm: number, eh: number, em: number): MathQuizLevelInput {
  const input: MathQuizLevelInput = {
    quizType: 'elapsed_time', expression: '', wordProblem: false, skillKey: '',
    leftValue: 0, rightValue: 0, clockHour: 0, clockMinute: 0,
    startHour: sh, startMinute: sm, endHour: eh, endMinute: em
  }
  return input
}

export default function mathQuizProgressionTest() {
  describe('normalizePurpose', () => {
    it('maps warmup variants and defaults invalid values to practice', 0, () => {
      expect(normalizePurpose('warm_up')).assertEqual('warm_up')
      expect(normalizePurpose('warmup')).assertEqual('warm_up')
      expect(normalizePurpose('warm-up')).assertEqual('warm_up')
      expect(normalizePurpose('review')).assertEqual('review')
      expect(normalizePurpose('')).assertEqual('practice')
      expect(normalizePurpose('foo')).assertEqual('practice')
    })
  })

  describe('normalizeSkillKey', () => {
    it('maps legacy short names and leaves canonical names intact', 0, () => {
      expect(normalizeSkillKey('addition')).assertEqual('math_addition')
      expect(normalizeSkillKey('subtraction')).assertEqual('math_subtraction')
      expect(normalizeSkillKey('multiply')).assertEqual('math_multiply')
      expect(normalizeSkillKey('divide')).assertEqual('math_divide')
      expect(normalizeSkillKey('word_problem')).assertEqual('math_word_problem')
      expect(normalizeSkillKey('math_addition')).assertEqual('math_addition')
      expect(normalizeSkillKey('foo')).assertEqual('')
    })
  })

  describe('normalizeExpressionKey', () => {
    it('normalizes whitespace, U+2212, and full-width operators', 0, () => {
      expect(normalizeExpressionKey(arithmetic('47 + 28'))).assertEqual('47+28')
      expect(normalizeExpressionKey(arithmetic('47+28'))).assertEqual('47+28')
      expect(normalizeExpressionKey(arithmetic('47 + 28 − 15'))).assertEqual('47+28-15')
      expect(normalizeExpressionKey(arithmetic('6 × 7'))).assertEqual('6*7')
      expect(normalizeExpressionKey(arithmetic('6 ÷ 2'))).assertEqual('6/2')
      expect(normalizeExpressionKey(arithmetic('47 + 28')) === normalizeExpressionKey(arithmetic('47 + 29'))).assertFalse()
    })

    it('builds stable keys for comparison, clock, and elapsed', 0, () => {
      expect(normalizeExpressionKey(comparison(5, 3))).assertEqual('cmp:5:3')
      expect(normalizeExpressionKey(clock(3, 30))).assertEqual('clock:3:30')
      expect(normalizeExpressionKey(elapsed(3, 10, 3, 40))).assertEqual('elapsed:3:10-3:40')
    })

    it('builds readable record expressions for non-arithmetic questions', 0, () => {
      expect(buildMathQuizRecordExpression(arithmetic('47 + 28'))).assertEqual('47 + 28')
      expect(buildMathQuizRecordExpression(comparison(5, 3))).assertEqual('5 ? 3')
      expect(buildMathQuizRecordExpression(clock(3, 5))).assertEqual('3:05')
      expect(buildMathQuizRecordExpression(elapsed(3, 10, 3, 40))).assertEqual('3:10 → 3:40')
    })
  })

  describe('spec table and target', () => {
    it('returns the add L7 spec and target', 0, () => {
      const spec: MathQuizLevelSpec = getLevelSpec('add', 7) as MathQuizLevelSpec
      expect(spec.maxOperand).assertEqual(999)
      expect(spec.minSteps).assertEqual(1)
      expect(spec.maxSteps).assertEqual(1)
      expect(spec.carryRule).assertEqual('none')
      const target = buildTarget(spec)
      expect(target.level).assertEqual(7)
      expect(target.max_operand).assertEqual(999)
      expect(target.steps).assertEqual('1')
      expect(target.carry).assertEqual('none')
      expect(target.example).assertEqual('213 + 124')
    })

    it('returns a clock target with constraint and no arithmetic fields', 0, () => {
      const spec: MathQuizLevelSpec = getLevelSpec('clock', 3) as MathQuizLevelSpec
      const target = buildTarget(spec)
      expect(target.constraint).assertEqual('分钟为 10/15/20/25/35/40/45/50 之一')
      expect(target.max_operand === undefined).assertTrue()
      expect(target.steps === undefined).assertTrue()
    })

    it('caps max levels and returns null outside the table', 0, () => {
      expect(getMaxLevel('add')).assertEqual(15)
      expect(getMaxLevel('muldiv')).assertEqual(10)
      expect(getMaxLevel('compare')).assertEqual(6)
      expect(getMaxLevel('clock')).assertEqual(4)
      expect(getMaxLevel('elapsed')).assertEqual(4)
      expect(getLevelSpec('add', 16) === null).assertTrue()
      expect(getTrackLabel('add')).assertEqual('加法')
      expect(getTrackLabel('muldiv')).assertEqual('乘除')
    })
  })

  describe('initialLevelForTrack', () => {
    it('maps add/sub profile levels with sibling fallback', 0, () => {
      const add4: Record<string, number> = { 'math_addition': 4 }
      expect(initialLevelForTrack('add', add4)).assertEqual(8)
      const empty: Record<string, number> = {}
      expect(initialLevelForTrack('add', empty)).assertEqual(1)
      expect(initialLevelForTrack('sub', add4)).assertEqual(7)
      const sub5: Record<string, number> = { 'math_subtraction': 5 }
      expect(initialLevelForTrack('sub', sub5)).assertEqual(11)
      expect(initialLevelForTrack('add', sub5)).assertEqual(10)
    })

    it('takes max(mul, div) for muldiv and maps compare/time', 0, () => {
      const mulDiv: Record<string, number> = { 'math_multiply': 5, 'math_divide': 3 }
      expect(initialLevelForTrack('muldiv', mulDiv)).assertEqual(9)
      const mulOnly: Record<string, number> = { 'math_multiply': 2, 'math_divide': 0 }
      expect(initialLevelForTrack('muldiv', mulOnly)).assertEqual(3)
      const compare4: Record<string, number> = { 'math_comparison': 4 }
      expect(initialLevelForTrack('compare', compare4)).assertEqual(5)
      const time5: Record<string, number> = { 'math_time': 5 }
      expect(initialLevelForTrack('clock', time5)).assertEqual(4)
      expect(initialLevelForTrack('elapsed', time5)).assertEqual(4)
      const none: Record<string, number> = {}
      expect(initialLevelForTrack('clock', none)).assertEqual(1)
    })
  })
}
```

- [ ] **Step 2: Run the test to verify it fails**

In DevEco Studio, right-click `MathQuizProgression.test.ets` → Run.
Expected: compile failure — `MathQuizProgression` / `MathQuizProgressionModels` not found.

- [ ] **Step 3: Create `models/MathQuizProgressionModels.ets`**

Define the exported types and interfaces exactly as named in the Interfaces block above, plus:

```ts
export interface MathQuizLevelSpec {
  track: MathQuizTrack
  level: number
  label: string
  maxOperand: number
  minSteps: number
  maxSteps: number
  carryRule: 'none' | 'required' | 'any'
  constraint: string
  example: string
}

export interface MathQuizLevelInput {
  quizType: string
  expression: string
  wordProblem: boolean
  skillKey: string
  leftValue: number
  rightValue: number
  clockHour: number
  clockMinute: number
  startHour: number
  startMinute: number
  endHour: number
  endMinute: number
}

export interface MathQuizLevelInfo {
  track: MathQuizTrack
  level: number
  gate: boolean
  spec: MathQuizLevelSpec | null
  expressionKey: string
  error: string
}

export interface MathQuizTarget {
  track: string
  level: number
  label: string
  max_operand?: number
  steps?: string
  carry?: string
  constraint?: string
  example: string
}
```

Also declare `MathQuizRecordInsert`, `MathQuizRecordRow`, `MathQuizProgressRow`, `MathQuizProgressUpdate`, `MathQuizProgressHint`, `MathQuizGateInput`, `MathQuizGateDecision`, `MathQuizGateResult`, `MathQuizProgressSnapshot`, and `ChildProfileMathProgress` with the field names already fixed in this plan's Task 3–Task 7 Interfaces blocks. Use camelCase for internal record/progress fields and snake_case only for JSON-facing snapshots/hints/targets. `MathQuizProgressRow.track` is a plain `string` (DB row); `MathQuizProgressHint.next_target` is a non-null `MathQuizTarget` (the hint is only built when a spec exists). `ChildProfileMathProgress` is `{ track: string; level: number; label: string; correct_at_level: number; needed: number; nextTarget: MathQuizTarget }` (outer `nextTarget` camelCase, its inner fields snake_case).

- [ ] **Step 4: Create `utils/MathQuizProgression.ets` with the spec table and normalizers**

Add:
- `SKILL_ALIASES: Record<string, string>` with quoted keys: `'addition'`, `'subtraction'`, `'multiply'`, `'divide'`, `'shapes'`, `'comparison'`, `'time'`, `'counting'`, `'number_sense'`, `'word_problem'`, plus each canonical `'math_*'` mapping to itself.
- `ADD_SUB_INIT = [1, 2, 3, 5, 8, 11]`, `MUL_INIT = [1, 1, 3, 5, 6, 7]`, `DIV_INIT = [1, 1, 8, 9, 10, 10]`, `COMPARE_INIT = [1, 2, 3, 4, 5, 6]`, `TIME_INIT = [1, 1, 2, 2, 3, 4]` — each array is indexed by the 0–5 profile level directly (index `level`, not `level+1`).
- `LevelRow` (level, label, maxOperand, minSteps, maxSteps, carryRule, constraint, example) and the four row tables copied from spec §4.2–§4.4. Add/sub rows:

| level | label | max | steps | carry | example |
|---|---|---|---|---|---|
| 1 | 10 以内一步 | 10 | 1 | any | `7 + 2` / `9 − 3` |
| 2 | 20 以内不进位/不退位 | 20 | 1 | none | `12 + 5` / `18 − 6` |
| 3 | 20 以内进位/退位或两步混合 | 20 | 1–3 | any | `8 + 7` / `15 − 8` / `10 − 3 + 5` |
| 4 | 100 以内不进位/不退位 | 100 | 1 | none | `23 + 14` / `68 − 25` |
| 5 | 100 以内进位/退位 | 100 | 1 | required | `47 + 28` / `63 − 27` |
| 6 | 100 以内两步混合 | 100 | 2–3 | any | `47 + 28 − 15` |
| 7 | 1000 以内不进位/不退位 | 999 | 1 | none | `213 + 124` / `568 − 235` |
| 8 | 1000 以内进位/退位 | 999 | 1 | required | `487 + 265` / `503 − 178` |
| 9 | 1000 以内两步混合 | 999 | 2–3 | any | `487 + 265 − 130` |
| 10 | 10000 以内不进位/不退位 | 9999 | 1 | none | `2134 + 1243` |
| 11 | 10000 以内进位/退位 | 9999 | 1 | required | `4876 + 2657` |
| 12 | 10000 以内两步混合 | 9999 | 2–3 | any | `4876 + 2657 − 1304` |
| 13 | 100000 以内不进位/不退位 | 99999 | 1 | none | `21345 + 12432` |
| 14 | 100000 以内进位/退位 | 99999 | 1 | required | `48765 + 26578` |
| 15 | 100000 以内两步混合 | 99999 | 2–3 | any | `48765 + 26578 − 13042` |

Where the spec row lists two examples, store the **first** in `MathQuizLevelSpec.example` (`7 + 2`, `213 + 124`, …); the second is illustrative only. The target contract expects a single expression, and the Task 1 test asserts `getLevelSpec('add', 7).example === '213 + 124'`.

Muldiv rows: MD1 2/5/10 表内乘法 (`2 × 2`), MD2 3/4/6 表内乘法 (`2 × 3`), MD3 7/8/9 表内乘法 (`7 × 8`), MD4 整十数 × 一位数 (`20 × 3`), MD5 两位数 × 一位数不进位 (`23 × 3`), MD6 两位数 × 一位数含进位 (`27 × 3`), MD7 三位数 × 一位数 (`213 × 3`), MD8 表内除法 (`15 ÷ 5`), MD9 两位数 ÷ 一位数 (`84 ÷ 4`), MD10 三位数 ÷ 一位数或两步混合 (`369 ÷ 3`). All `maxOperand = 0`, `carryRule = 'any'`, `constraint = ''`; MD1–MD9 `minSteps = maxSteps = 1`, MD10 `minSteps = 1, maxSteps = 3`.
Compare rows P1–P6: labels `比较两个数的大小`, max 10/20/100/999/9999/99999, constraint `比较两个数的大小，数值不超过 <max>`; clock rows C1–C4 and elapsed rows E1–E4 use the labels and constraints exactly from spec §4.4. Non-arithmetic rows use `maxOperand = 0`, `minSteps = maxSteps = 0`, `carryRule = 'any'`.

Implement the normalizers:
- `normalizePurpose` — trim/lowercase; `warm_up`/`warmup`/`warm-up` → `warm_up`; `review` → `review`; everything else → `practice`.
- `normalizeSkillKey` — trim; return the alias map value or `''`.
- `normalizeExpressionKey` — arithmetic: `sanitizeExpression(input.expression.replace(/−/g, '-'))` then replace `×`→`*`, `÷`→`/`; comparison: `cmp:<left>:<right>`; clock: `clock:<h>:<m>`; elapsed: `elapsed:<sh>:<sm>-<eh>:<em>`; shape/none: `''`.
- `buildMathQuizRecordExpression` — arithmetic: `input.expression` (raw, including the hidden word-problem expression); comparison: `${leftValue} ? ${rightValue}`; clock: `${clockHour}:${pad2(clockMinute)}`; elapsed: `${startHour}:${pad2(startMinute)} → ${endHour}:${pad2(endMinute)}`; shape/none: `''`. Add a private `pad2(n)` returning a two-digit string.
- `getMaxLevel` — add/sub 15, muldiv 10, compare 6, clock 4, elapsed 4, shape/none 0.
- `getLevelSpec` — choose the row table by track, return `null` for shape/none or out-of-range, and construct a `MathQuizLevelSpec` with the requested track.
- `getTrackLabel` — `add`→`加法`, `sub`→`减法`, `muldiv`→`乘除`, `compare`→`比较`, `clock`→`认钟`, `elapsed`→`经过时间`, `shape`→`图形`, `none`→`数数`.
- `buildTarget` — `add`/`sub` return `{ track, level, label, max_operand, steps: minSteps===maxSteps ? String(minSteps) : `${minSteps}-${maxSteps}`, carry: carryRule, example }`; `muldiv` returns the same but **omits `max_operand`** because that ladder is shape-based, not range-based; compare/clock/elapsed return `{ track, level, label, constraint, example }` (no arithmetic fields).
- `initialLevelForTrack` — clamp profile level to 0–5 and use it as the array index. For add/sub: own dimension `>0` → mapped; own `0` and sibling `>0` → `max(1, siblingMapped - 1)`; both `0` → 1. For muldiv: `max(MUL_INIT[mul], DIV_INIT[div])`; both 0 → 1. For compare/clock/elapsed: mapped with missing/0 → 1. For shape/none: 0.

- [ ] **Step 5: Register the test suite**

In `entry/src/ohosTest/ets/test/List.test.ets`, add:

```ts
import mathQuizProgressionTest from './utils/MathQuizProgression.test';
```

and inside `testsuite()`:

```ts
mathQuizProgressionTest();
```

- [ ] **Step 6: Run the test and the build**

DevEco Studio: right-click `MathQuizProgression.test.ets` → Run. Expected: PASS.
Then run the build command from Global Constraints. Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 7: Commit**

```bash
git add entry/src/main/ets/models/MathQuizProgressionModels.ets \
  entry/src/main/ets/utils/MathQuizProgression.ets \
  entry/src/ohosTest/ets/test/utils/MathQuizProgression.test.ets \
  entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat: add math quiz progression models, spec table, and normalizers"
```

---

### Task 2: Quiz-level resolver (add/sub, mul/div, compare, clock, elapsed)

**Files:**
- Modify: `entry/src/main/ets/utils/MathQuizProgression.ets`
- Test: `entry/src/ohosTest/ets/test/utils/MathQuizProgression.test.ets`

**Interfaces:**
- Consumes: Task 1's `MathQuizLevelInput`, `MathQuizLevelInfo`, `MathQuizLevelSpec`, `getLevelSpec`, `normalizeSkillKey`, `normalizeExpressionKey`.
- Produces:
  - `MathQuizGatingArgs` — `{ input: MathQuizLevelInput; purpose: MathQuizPurpose }`
  - `parseMathQuizGatingArgs(argsJson: string): MathQuizGatingArgs | null`
  - `buildMathQuizLevelInput(raw: Record<string, Object>): MathQuizLevelInput`
  - `resolveMathQuizLevel(input: MathQuizLevelInput): MathQuizLevelInfo`

**Resolver order (implement exactly):**

1. Normalize the skill key. Reject skill/type mismatches: `math_shapes` only `shape`; `math_comparison` only `comparison`; `math_time` only `time`/`elapsed_time`; `math_addition`/`math_subtraction`/`math_multiply`/`math_divide`/`math_word_problem` only `arithmetic`. A mismatch returns `gate=true`, `error` naming the mismatch, and a best-effort `track` (`add`/`sub`/`muldiv` for arithmetic, else `none`).
2. `shape` → `track='shape', level=0, gate=false, spec=null, expressionKey='', error=''`.
3. `comparison` → require finite `leftValue`/`rightValue`; `max(left,right) <= 99999`; P1–P6 by `<=10/20/100/999/9999/99999`; otherwise `gate=true, track='compare', error='比较的两个数不能超过 99999'`.
4. `time` → require integer hour 1–12 and integer minute 0–55 with `%5===0`; C1 for 0, C2 for 30, C4 for 5/55, C3 otherwise; otherwise `gate=true, track='clock', error='认钟的分钟必须是 0–55 的 5 的倍数（如 0/5/…/55），小时 1–12'`.
5. `elapsed_time` → validate both clock faces like step 4. Same hour with `endMinute <= startMinute` → error `时长必须大于 0，且不能倒着走`. Use `computeElapsedDuration`; `total = hours*60+minutes`; `total <= 0` → error. Same hour → E1; otherwise E4 if `total >= 120` or `endTotal < startTotal` (cross 12); else E2 when `startMinute === endMinute`; else E3.
6. Arithmetic:
   - `expr = input.expression.replace(/−/g, '-')`; `sanitized = sanitizeExpression(expr)`.
   - Empty `sanitized`: if skill is `math_counting`/`math_number_sense` → `track='none', gate=false`; otherwise `gate=true, track='none', error='算术题必须填 expression（应用题也要填隐藏算式，如 「3 + 2」；卡片只显示 question）'`.
   - Tokenize. If any number token contains `.` → `track='none', gate=false` (decimals are recorded, not gated).
   - If a `-` token is at index 0 or follows another op/`(` → `gate=true, track='none', error='算式不能包含负数的操作数，请换成两个非负数的加减'`.
   - `ops` = `+ - * / × ÷` tokens. `steps = ops.length`. `0` ops → `track='none', gate=false`. `steps > 3` → `gate=true, track='none', error='最多 3 个运算符'`. If any of `× ÷ * /` → mul/div classifier; otherwise add/sub classifier.
7. `expressionKey = normalizeExpressionKey(input)` for every gated result; `''` for `shape`/`none`.
8. On success: `spec = getLevelSpec(track, level)`, `gate=true`.

**Add/sub classifier details:**

- `hasPlus` / `hasMinus` from ops.
- Skill consistency: `math_addition` requires at least one `+`; `math_subtraction` requires at least one `-`; mixed chains may use either; a pure-`-` expression with `math_addition` or pure-`+` with `math_subtraction` → error.
- Track: `math_subtraction` → `sub`; `math_addition` → `add`; otherwise pure `-` → `sub`, mixed/`+` → `add`.
- `final = tryEvaluateExpression(expr)`; `null` → error. `final < 0` → error `中间结果不能为负数`.
- If no parentheses: walk `values`/`ops` left-to-right from `values[0]`; any intermediate `< 0` → error. Track `maxAbs` over all number tokens and intermediates. If parentheses are present, skip the intermediate walk and use the max of numbers + final.
- `steps === 1` → `carry = hasCarry(a,b)` for `+` or `hasBorrow(a,b)` for `-`; `steps >= 2` → `carry = false`.
- `maxAbs > 99999` → error `最高到 5 位数，中间结果也不能超过 99999`.
- Level: `maxAbs<=10 && steps===1 && final<=10` → L1; else `<=20` → L3 if `steps>=2 || carry`, else L2; `<=100` → L6 if `steps>=2`, else L5 if carry, else L4; `<=999` → L9 / L8 / L7; `<=9999` → L12 / L11 / L10; `<=99999` → L15 / L14 / L13.
- `hasCarry(a,b)` and `hasBorrow(a,b)` are column-wise loops over base 10; return true at the first column whose sum exceeds 9 / whose digit needs a borrow.

**Mul/div classifier details:**

- Single operator:
  - `×`/`*`: two integer factors. Any factor `0` → MD1. If both 1–10 and either is 1 → MD1. If both 1–10 → group by `max(a,b)`: `{2,5,10}`→MD1, `{3,4,6}`→MD2, `{7,8,9}`→MD3. If one factor is a multiple of 10 in 20–90 and the other 2–9 → MD4. If one factor 10–99 and other 2–9 → MD5/MD6 by digit carry (`hasMulCarry`). If one factor 100–999 and other 2–9 → MD7. Otherwise error: multi-digit × multi-digit, or a multiplier of 1 on a multi-digit number (`23 × 1`, `213 × 1`, `20 × 1`), or any other shape.
  - `÷`/`/`: divisor must be 2–10. `a % b !== 0` → error `除法必须整除，不能有余数`. `q = a/b`; `q` 1–10 → MD8; `a` 10–99 and `b` 2–9 → MD9; `a` 100–999 and `b` 2–9 → MD10; otherwise error (`5 ÷ 1`, `1000 ÷ 10`).
- `steps >= 2` with any `×`/`÷` → MD10. Check every adjacent `number ÷ number` pair for an integer quotient; a remainder → error. `tryEvaluateExpression` must return a finite number; otherwise error.

- [ ] **Step 1: Add the failing resolver tests**

Append to the test file (inside `mathQuizProgressionTest`, after the initial-level describe):

```ts
describe('resolveMathQuizLevel arithmetic add/sub', () => {
  it('classifies the spec add/sub ladder', 0, () => {
    expect(resolveMathQuizLevel(arithmetic('7 + 2')).level).assertEqual(1)
    expect(resolveMathQuizLevel(arithmetic('9 − 3')).level).assertEqual(1)
    expect(resolveMathQuizLevel(arithmetic('12 + 5')).level).assertEqual(2)
    expect(resolveMathQuizLevel(arithmetic('8 + 7')).level).assertEqual(3)
    expect(resolveMathQuizLevel(arithmetic('9 + 9')).level).assertEqual(3)
    expect(resolveMathQuizLevel(arithmetic('47 + 28')).level).assertEqual(5)
    expect(resolveMathQuizLevel(arithmetic('63 − 27')).level).assertEqual(5)
    expect(resolveMathQuizLevel(arithmetic('47 + 28 − 15')).level).assertEqual(6)
    expect(resolveMathQuizLevel(arithmetic('213 + 124')).level).assertEqual(7)
    expect(resolveMathQuizLevel(arithmetic('568 − 235')).level).assertEqual(7)
    expect(resolveMathQuizLevel(arithmetic('487 + 265')).level).assertEqual(8)
    expect(resolveMathQuizLevel(arithmetic('503 − 178')).level).assertEqual(8)
    expect(resolveMathQuizLevel(arithmetic('4876 + 2657')).level).assertEqual(11)
    expect(resolveMathQuizLevel(arithmetic('21345 + 12432')).level).assertEqual(13)
    expect(resolveMathQuizLevel(arithmetic('48765 + 26578 − 13042')).level).assertEqual(15)
    expect(resolveMathQuizLevel(arithmetic('10 − 3 + 5')).level).assertEqual(3)
  })

  it('rejects negative intermediates, negative operands, and >5 digits', 0, () => {
    const negativeMiddle = resolveMathQuizLevel(arithmetic('3 − 5 + 10'))
    expect(negativeMiddle.gate).assertTrue()
    expect(negativeMiddle.error.length > 0).assertTrue()
    const negativeOperand = resolveMathQuizLevel(arithmetic('-3 + 5'))
    expect(negativeOperand.gate).assertTrue()
    expect(negativeOperand.error.length > 0).assertTrue()
    const tooBig = resolveMathQuizLevel(arithmetic('99999 + 1'))
    expect(tooBig.gate).assertTrue()
    expect(tooBig.error.length > 0).assertTrue()
  })

  it('routes decimal operands to none without a gate', 0, () => {
    const decimal = resolveMathQuizLevel(arithmetic('1.5 + 2'))
    expect(decimal.track).assertEqual('none')
    expect(decimal.gate).assertFalse()
    expect(decimal.error).assertEqual('')
  })

  it('enforces skill_key and expression consistency', 0, () => {
    expect(resolveMathQuizLevel(arithmetic('3 − 2', 'math_addition')).error.length > 0).assertTrue()
    expect(resolveMathQuizLevel(arithmetic('3 + 2', 'math_subtraction')).error.length > 0).assertTrue()
    expect(resolveMathQuizLevel(arithmetic('3 + 2', 'math_multiply')).error.length > 0).assertTrue()
    expect(resolveMathQuizLevel(arithmetic('3 × 2', 'math_divide')).error.length > 0).assertTrue()
    expect(resolveMathQuizLevel(arithmetic('3 + 2', 'addition')).track).assertEqual('add')
    expect(resolveMathQuizLevel(arithmetic('3 × 2', 'multiply')).track).assertEqual('muldiv')
    expect(resolveMathQuizLevel(arithmetic('3 + 2', 'foo')).track).assertEqual('add')
    expect(resolveMathQuizLevel(arithmetic('3 + 2', 'math_word_problem')).track).assertEqual('add')
    expect(resolveMathQuizLevel(arithmetic('', 'math_counting')).track).assertEqual('none')
    expect(resolveMathQuizLevel(arithmetic('', 'math_counting')).gate).assertFalse()
    const missing = resolveMathQuizLevel(arithmetic('', 'math_addition'))
    expect(missing.gate).assertTrue()
    expect(missing.error.length > 0).assertTrue()
  })
})

describe('resolveMathQuizLevel mul/div', () => {
  it('classifies the mul/div ladder', 0, () => {
    expect(resolveMathQuizLevel(arithmetic('2 × 2')).level).assertEqual(1)
    expect(resolveMathQuizLevel(arithmetic('10 × 3')).level).assertEqual(1)
    expect(resolveMathQuizLevel(arithmetic('1 × 7')).level).assertEqual(1)
    expect(resolveMathQuizLevel(arithmetic('2 × 3')).level).assertEqual(2)
    expect(resolveMathQuizLevel(arithmetic('4 × 6')).level).assertEqual(2)
    expect(resolveMathQuizLevel(arithmetic('7 × 8')).level).assertEqual(3)
    expect(resolveMathQuizLevel(arithmetic('3 × 7')).level).assertEqual(3)
    expect(resolveMathQuizLevel(arithmetic('20 × 3')).level).assertEqual(4)
    expect(resolveMathQuizLevel(arithmetic('23 × 3')).level).assertEqual(5)
    expect(resolveMathQuizLevel(arithmetic('27 × 3')).level).assertEqual(6)
    expect(resolveMathQuizLevel(arithmetic('23 × 4')).level).assertEqual(6)
    expect(resolveMathQuizLevel(arithmetic('213 × 3')).level).assertEqual(7)
    expect(resolveMathQuizLevel(arithmetic('12 ÷ 3')).level).assertEqual(8)
    expect(resolveMathQuizLevel(arithmetic('15 ÷ 5')).level).assertEqual(8)
    expect(resolveMathQuizLevel(arithmetic('24 ÷ 4')).level).assertEqual(8)
    expect(resolveMathQuizLevel(arithmetic('84 ÷ 4')).level).assertEqual(9)
    expect(resolveMathQuizLevel(arithmetic('369 ÷ 3')).level).assertEqual(10)
    expect(resolveMathQuizLevel(arithmetic('12 × 3 + 8')).level).assertEqual(10)
    expect(resolveMathQuizLevel(arithmetic('12 ÷ 3 + 8')).level).assertEqual(10)
  })

  it('rejects remainders and unsupported multiplication shapes', 0, () => {
    expect(resolveMathQuizLevel(arithmetic('10 ÷ 3')).error.length > 0).assertTrue()
    expect(resolveMathQuizLevel(arithmetic('7 ÷ 2')).error.length > 0).assertTrue()
    expect(resolveMathQuizLevel(arithmetic('12 ÷ 5 × 3')).error.length > 0).assertTrue()
    expect(resolveMathQuizLevel(arithmetic('20 × 30')).error.length > 0).assertTrue()
    expect(resolveMathQuizLevel(arithmetic('213 × 1')).error.length > 0).assertTrue()
    expect(resolveMathQuizLevel(arithmetic('23 × 1')).error.length > 0).assertTrue()
    expect(resolveMathQuizLevel(arithmetic('5 ÷ 1')).error.length > 0).assertTrue()
  })
})

describe('resolveMathQuizLevel compare/clock/elapsed', () => {
  it('classifies comparison and clock levels', 0, () => {
    expect(resolveMathQuizLevel(comparison(5, 3)).level).assertEqual(1)
    expect(resolveMathQuizLevel(comparison(15, 3)).level).assertEqual(2)
    expect(resolveMathQuizLevel(comparison(999, 3)).level).assertEqual(4)
    expect(resolveMathQuizLevel(comparison(99999, 3)).level).assertEqual(6)
    expect(resolveMathQuizLevel(clock(3, 0)).level).assertEqual(1)
    expect(resolveMathQuizLevel(clock(3, 30)).level).assertEqual(2)
    expect(resolveMathQuizLevel(clock(3, 15)).level).assertEqual(3)
    expect(resolveMathQuizLevel(clock(3, 55)).level).assertEqual(4)
    expect(resolveMathQuizLevel(clock(3, 12)).error.length > 0).assertTrue()
  })

  it('classifies elapsed time levels and rejects invalid durations', 0, () => {
    expect(resolveMathQuizLevel(elapsed(3, 10, 3, 40)).level).assertEqual(1)
    expect(resolveMathQuizLevel(elapsed(3, 0, 4, 0)).level).assertEqual(2)
    expect(resolveMathQuizLevel(elapsed(3, 30, 4, 15)).level).assertEqual(3)
    expect(resolveMathQuizLevel(elapsed(11, 30, 1, 15)).level).assertEqual(4)
    expect(resolveMathQuizLevel(elapsed(3, 10, 3, 10)).error.length > 0).assertTrue()
    expect(resolveMathQuizLevel(elapsed(3, 40, 3, 10)).error.length > 0).assertTrue()
    expect(resolveMathQuizLevel(elapsed(3, 10, 3, 12)).error.length > 0).assertTrue()
  })

  it('handles shape and skill/type mismatches', 0, () => {
    const shape = resolveMathQuizLevel(arithmetic('', 'math_shapes'))
    expect(shape.gate).assertTrue()
    expect(shape.error.length > 0).assertTrue()
    const shapeInput: MathQuizLevelInput = {
      quizType: 'shape', expression: '', wordProblem: false, skillKey: 'math_shapes',
      leftValue: 0, rightValue: 0, clockHour: 0, clockMinute: 0,
      startHour: 0, startMinute: 0, endHour: 0, endMinute: 0
    }
    const shapeOk = resolveMathQuizLevel(shapeInput)
    expect(shapeOk.track).assertEqual('shape')
    expect(shapeOk.gate).assertFalse()
    expect(resolveMathQuizLevel(arithmetic('3 + 2', 'math_shapes')).error.length > 0).assertTrue()
  })
})
```

Add `resolveMathQuizLevel` to the import list at the top of the test file.

- [ ] **Step 2: Run the test to verify it fails**

DevEco Studio → run `MathQuizProgression.test.ets`.
Expected: compile failure — `resolveMathQuizLevel` not exported.

- [ ] **Step 3: Implement `parseMathQuizGatingArgs`, `buildMathQuizLevelInput`, and `resolveMathQuizLevel`**

`parseMathQuizGatingArgs`:
```ts
export interface MathQuizGatingArgs {
  input: MathQuizLevelInput
  purpose: MathQuizPurpose
}

export function parseMathQuizGatingArgs(argsJson: string): MathQuizGatingArgs | null {
  try {
    const raw = JSON.parse(argsJson) as Record<string, Object>
    if (raw === null) return null
    const result: MathQuizGatingArgs = {
      input: buildMathQuizLevelInput(raw),
      purpose: normalizePurpose(raw['purpose'] !== undefined ? String(raw['purpose']) : '')
    }
    return result
  } catch (_e) {
    return null
  }
}
```

`buildMathQuizLevelInput` uses `normalizeQuizType(String(raw['type'] ?? 'arithmetic'))`, `String(raw['expression'] ?? '')`, `raw['word_problem'] === true || raw['word_problem'] === 'true'`, `String(raw['skill_key'] ?? '')`, and `Number(raw[key] ?? 0)` for the eight numeric fields.

Implement `resolveMathQuizLevel` and private helpers `classifyAddSub`, `classifyMulDiv`, `hasCarry`, `hasBorrow`, `hasMulCarry`, `errorInfo(track, message)`. Keep all helpers module-private (no `export`). Use `Math.abs`, `Math.max`, `Number.isInteger`, `Number.isFinite`.

- [ ] **Step 4: Run the test and the build**

DevEco Studio → run the file. Expected: PASS.
Run the build command. Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/utils/MathQuizProgression.ets \
  entry/src/ohosTest/ets/test/utils/MathQuizProgression.test.ets
git commit -m "feat: classify math quiz difficulty levels"
```

---

### Task 3: Progress state machine, hint builder, and pure gate decision

**Files:**
- Modify: `entry/src/main/ets/utils/MathQuizProgression.ets`
- Test: `entry/src/ohosTest/ets/test/utils/MathQuizProgression.test.ets`

**Interfaces:**
- Consumes: Task 1/2 types and `getLevelSpec`, `buildTarget`, `getTrackLabel`.
- Produces:
  - `applyMathQuizProgress(current: MathQuizProgressRow, questionLevel: number, purpose: MathQuizPurpose, correct: boolean, attempts: number, now: number): MathQuizProgressUpdate`
  - `buildMathQuizProgressHint(update: MathQuizProgressUpdate, track: MathQuizTrack, needed: number): MathQuizProgressHint | null`
  - `evaluateMathQuizGate(input: MathQuizGateInput): MathQuizGateDecision`

`MathQuizProgressUpdate` fields: `row: MathQuizProgressRow`, `counted: boolean`, `status: MathQuizProgressStatus`, `reason: MathQuizProgressReason`.

`MathQuizGateInput` fields: `info: MathQuizLevelInfo`, `purpose: MathQuizPurpose`, `progressLevel: number`, `recentExpressionKeys: string[]`, `purposeCountInSession: number`, `sessionId: string`.

`MathQuizGateDecision` fields: `allowed: boolean`, `error: string`, `message: string`, `target: MathQuizTarget | null`.

**State machine (implement exactly):**

- `counted = purpose === 'practice' && questionLevel === current.currentLevel`.
- Not counted → return the current row unchanged, `status='not_counted'`, `reason` = `warm_up` / `review` / `stale_level`.
- Counted:
  - If `now - current.updatedAt > 24*60*60*1000`, reset `consecutiveWrong` to 0 before applying this answer.
  - `firstTry = correct && attempts === 1`; `attempts` is already normalized by the caller (`undefined` → `correct ? 1 : 2`).
  - First-try correct: `correctAtLevel = min(10, +1)`, `consecutiveWrong=0`; if it reaches 10 and `currentLevel < maxLevel` → level+1, count 0, `status='level_up'`; if it reaches 10 at max → `status='max_level'`; otherwise `status='in_progress'`.
  - Second-try correct: `correctAtLevel` unchanged, `consecutiveWrong=0`, `status='in_progress'`, `reason='second_try'`.
  - Two-wrong: `consecutiveWrong += 1`, `reason='two_wrong'`; at 2 and `currentLevel > 1` → level−1, count 0, wrong 0, `status='level_down'`; at 2 and level 1 → level 1, wrong 0, `status='in_progress'`; otherwise wrong stays, `status='in_progress'`.
  - Return a new row with `updatedAt=now`.

**Hint:** `level`/`level_label`/`next_target` describe the *current target* after the update. Return `null` only when `getLevelSpec(track, row.currentLevel)` is null.

**Gate decision:**

- Compute `currentSpec` / `currentTarget` from `input.info.track` and `input.progressLevel`.
- `input.info.error !== ''` → reject with `error='difficulty_gate'`, `message=input.info.error`, `target=currentTarget`.
- `!input.info.gate` → allow.
- `practice`: level `<` progress → `difficulty_gate` (too easy); level `>` progress → `difficulty_gate` (too hard); `expressionKey !== ''` and found in `recentExpressionKeys` (use `indexOf(...) >= 0`) → `duplicate_question`.
- `warm_up`/`review`: level `>` progress → `difficulty_gate`; if `sessionId !== ''` and `purposeCountInSession >= (warm_up ? 5 : 3)` → `purpose_quota_exceeded`.
- Messages must be three-part: current target + the submitted level + the next action. Use `getTrackLabel`, `currentSpec.label`, `currentSpec.example`. Exact templates:
  - too easy: `当前${trackLabel}目标 L${progressLevel}（${label}，如 ${example}）。你出的题是 L${info.level}，太简单了。请按 target 重新出题，不要降低难度。如果这是热身/复习，请把 purpose 设为 warm_up 或 review（有每会话配额）。`
  - too hard: `当前${trackLabel}目标 L${progressLevel}（${label}，如 ${example}）。你出的题是 L${info.level}，太难了。请按 target 重新出题。`
  - duplicate: `这道题在最近 20 道同轨题里做过了。请保持 L${progressLevel} 难度，换一组数字。`
  - quota: `本会话 ${purpose} 已用 ${limit} 道，不能再用了。请改用 purpose='practice'，按 target 出正式练习。`
  - If `currentSpec` is null, omit the parenthetical target details.

- [ ] **Step 1: Add the failing state-machine and gate tests**

Append to the test file:

```ts
function row(level: number, correct: number, wrong: number, updatedAt: number = Date.now()): MathQuizProgressRow {
  const r: MathQuizProgressRow = {
    track: 'add', currentLevel: level, correctAtLevel: correct,
    consecutiveWrong: wrong, updatedAt: updatedAt
  }
  return r
}

function gateInput(info: MathQuizLevelInfo, purpose: MathQuizPurpose, progressLevel: number,
  keys: string[], count: number, sessionId: string): MathQuizGateInput {
  const input: MathQuizGateInput = {
    info: info, purpose: purpose, progressLevel: progressLevel,
    recentExpressionKeys: keys, purposeCountInSession: count, sessionId: sessionId
  }
  return input
}

describe('applyMathQuizProgress', () => {
  it('levels up on the 10th first-try correct', 0, () => {
    const up = applyMathQuizProgress(row(7, 9, 0), 7, 'practice', true, 1, Date.now())
    expect(up.counted).assertTrue()
    expect(up.row.currentLevel).assertEqual(8)
    expect(up.row.correctAtLevel).assertEqual(0)
    expect(up.row.consecutiveWrong).assertEqual(0)
    expect(up.status).assertEqual('level_up')
    expect(up.reason).assertEqual('first_try_correct')
  })

  it('keeps the level on a second-try correct but resets wrongs', 0, () => {
    const second = applyMathQuizProgress(row(7, 5, 1), 7, 'practice', true, 2, Date.now())
    expect(second.row.currentLevel).assertEqual(7)
    expect(second.row.correctAtLevel).assertEqual(5)
    expect(second.row.consecutiveWrong).assertEqual(0)
    expect(second.status).assertEqual('in_progress')
    expect(second.reason).assertEqual('second_try')
  })

  it('downgrades on the second two-wrong question and floors at 1', 0, () => {
    const wrong1 = applyMathQuizProgress(row(7, 5, 0), 7, 'practice', false, 2, Date.now())
    expect(wrong1.row.currentLevel).assertEqual(7)
    expect(wrong1.row.consecutiveWrong).assertEqual(1)
    const wrong2 = applyMathQuizProgress(row(7, 5, 1), 7, 'practice', false, 2, Date.now())
    expect(wrong2.row.currentLevel).assertEqual(6)
    expect(wrong2.row.correctAtLevel).assertEqual(0)
    expect(wrong2.row.consecutiveWrong).assertEqual(0)
    expect(wrong2.status).assertEqual('level_down')
    const floor = applyMathQuizProgress(row(1, 0, 1), 1, 'practice', false, 2, Date.now())
    expect(floor.row.currentLevel).assertEqual(1)
    expect(floor.row.consecutiveWrong).assertEqual(0)
  })

  it('caps at max level and downgrades from max on two wrongs', 0, () => {
    const max = applyMathQuizProgress(row(15, 9, 0), 15, 'practice', true, 1, Date.now())
    expect(max.row.currentLevel).assertEqual(15)
    expect(max.row.correctAtLevel).assertEqual(10)
    expect(max.status).assertEqual('max_level')
    const down = applyMathQuizProgress(row(15, 10, 1), 15, 'practice', false, 2, Date.now())
    expect(down.row.currentLevel).assertEqual(14)
    expect(down.status).assertEqual('level_down')
  })

  it('does not count warm_up, review, or stale-level answers', 0, () => {
    const warm = applyMathQuizProgress(row(7, 5, 0), 6, 'warm_up', true, 1, Date.now())
    expect(warm.counted).assertFalse()
    expect(warm.row.currentLevel).assertEqual(7)
    expect(warm.status).assertEqual('not_counted')
    expect(warm.reason).assertEqual('warm_up')
    const review = applyMathQuizProgress(row(7, 5, 0), 7, 'review', true, 1, Date.now())
    expect(review.reason).assertEqual('review')
    const stale = applyMathQuizProgress(row(7, 5, 0), 6, 'practice', true, 1, Date.now())
    expect(stale.reason).assertEqual('stale_level')
  })

  it('resets consecutive_wrong after 24 hours', 0, () => {
    const now = Date.now()
    const old = now - 25 * 60 * 60 * 1000
    const reset = applyMathQuizProgress(row(7, 5, 1, old), 7, 'practice', false, 2, now)
    expect(reset.row.currentLevel).assertEqual(7)
    expect(reset.row.consecutiveWrong).assertEqual(1)
  })

  it('builds a hint with the current target', 0, () => {
    const up = applyMathQuizProgress(row(7, 9, 0), 7, 'practice', true, 1, Date.now())
    const hint = buildMathQuizProgressHint(up, 'add', 10)
    expect(hint !== null).assertTrue()
    const h = hint as MathQuizProgressHint
    expect(h.level).assertEqual(8)
    expect(h.level_label).assertEqual('1000 以内不进位/不退位')
    expect(h.needed).assertEqual(10)
    expect(h.next_target.level).assertEqual(8)
  })
})

describe('evaluateMathQuizGate', () => {
  it('rejects practice below and above the target level', 0, () => {
    const info5 = resolveMathQuizLevel(arithmetic('47 + 28'))
    const info9 = resolveMathQuizLevel(arithmetic('487 + 265 − 130'))
    const easy = evaluateMathQuizGate(gateInput(info5, 'practice', 7, [], 0, 's1'))
    expect(easy.allowed).assertFalse()
    expect(easy.error).assertEqual('difficulty_gate')
    expect(easy.target !== null).assertTrue()
    const hard = evaluateMathQuizGate(gateInput(info9, 'practice', 7, [], 0, 's1'))
    expect(hard.error).assertEqual('difficulty_gate')
  })

  it('rejects a recent duplicate only for practice', 0, () => {
    const info7 = resolveMathQuizLevel(arithmetic('213 + 124'))
    const dup = evaluateMathQuizGate(gateInput(info7, 'practice', 7, [info7.expressionKey], 0, 's1'))
    expect(dup.error).assertEqual('duplicate_question')
    const review = evaluateMathQuizGate(gateInput(info7, 'review', 7, [info7.expressionKey], 0, 's1'))
    expect(review.allowed).assertTrue()
  })

  it('allows lower warm_up/review within quota and rejects over quota', 0, () => {
    const info5 = resolveMathQuizLevel(arithmetic('47 + 28'))
    expect(evaluateMathQuizGate(gateInput(info5, 'warm_up', 7, [], 0, 's1')).allowed).assertTrue()
    expect(evaluateMathQuizGate(gateInput(info5, 'warm_up', 7, [], 5, 's1')).error).assertEqual('purpose_quota_exceeded')
    expect(evaluateMathQuizGate(gateInput(info5, 'review', 7, [], 3, 's1')).error).assertEqual('purpose_quota_exceeded')
    expect(evaluateMathQuizGate(gateInput(info5, 'warm_up', 7, [], 99, '')).allowed).assertTrue()
  })

  it('rejects warm_up above the target and surfaces structural errors', 0, () => {
    const info8 = resolveMathQuizLevel(arithmetic('487 + 265'))
    expect(evaluateMathQuizGate(gateInput(info8, 'warm_up', 7, [], 0, 's1')).error).assertEqual('difficulty_gate')
    const bad = resolveMathQuizLevel(arithmetic('', 'math_addition'))
    const decision = evaluateMathQuizGate(gateInput(bad, 'practice', 4, [], 0, 's1'))
    expect(decision.allowed).assertFalse()
    expect(decision.error).assertEqual('difficulty_gate')
    expect(decision.message.length > 0).assertTrue()
  })
})
```

Add `applyMathQuizProgress`, `buildMathQuizProgressHint`, `evaluateMathQuizGate` and the model types `MathQuizProgressRow`, `MathQuizProgressHint`, `MathQuizLevelInfo`, `MathQuizPurpose`, `MathQuizGateInput` to the test imports.

- [ ] **Step 2: Run the test to verify it fails**

DevEco Studio → run the file. Expected: compile failure — the three new exports are missing.

- [ ] **Step 3: Implement the state machine, hint builder, and gate decision**

Implement `applyMathQuizProgress`, `buildMathQuizProgressHint`, and `evaluateMathQuizGate` in `utils/MathQuizProgression.ets` exactly as specified above. Use a private `rejectDecision(error, message, target)` helper and a private `currentTargetFor(track, level)` helper. Do not import any service or model with side effects; this file must stay pure.

- [ ] **Step 4: Run the test and the build**

DevEco Studio → run the file. Expected: PASS.
Build command. Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/utils/MathQuizProgression.ets \
  entry/src/ohosTest/ets/test/utils/MathQuizProgression.test.ets
git commit -m "feat: add math quiz progress state machine and difficulty gate"
```

---

### Task 4: SQLite tables and persistence methods

**Files:**
- Modify: `entry/src/main/ets/services/DatabaseService.ets`

**Interfaces:**
- Consumes: `MathQuizRecordInsert`, `MathQuizRecordRow`, `MathQuizProgressRow` from `models/MathQuizProgressionModels.ets`.
- Produces:
  - `TableNames.MATH_QUIZ_RECORDS = 'math_quiz_records'`
  - `TableNames.MATH_QUIZ_PROGRESS = 'math_quiz_progress'`
  - `insertMathQuizRecord(record: MathQuizRecordInsert): Promise<number>`
  - `getRecentMathQuizRecords(track: string, limit: number): Promise<MathQuizRecordRow[]>`
  - `countMathQuizPurposeInSession(sessionId: string, purpose: string): Promise<number>`
  - `getMathQuizProgress(track: string): Promise<MathQuizProgressRow | null>`
  - `upsertMathQuizProgress(row: MathQuizProgressRow): Promise<boolean>`
  - `recordMathQuizAnswer(record: MathQuizRecordInsert, progress: MathQuizProgressRow | null): Promise<number>`

- [ ] **Step 1: Add the table names and create-table SQL**

Add the two constants to `TableNames`. Add `createMathQuizRecordsTable` and `createMathQuizProgressTable` constants next to `createStarEventsTable`, with the exact columns from spec §6.1/§6.2. Execute both after `createStarEventsTable` in `createTables`. Add the two indexes with the other `executeSql` index statements:

```sql
CREATE INDEX IF NOT EXISTS idx_math_quiz_records_track_time
  ON math_quiz_records(track, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_math_quiz_records_session_purpose
  ON math_quiz_records(session_id, purpose);
```

- [ ] **Step 2: Implement the insert/query methods**

Follow the existing `insertStarEvent` / `getStarEventsSince` patterns (`waitForInitialization`, null `rdbStore` guard, `ValuesBucket`, try/catch returning `-1`/`[]`).

- `insertMathQuizRecord`: map booleans `correct` / `firstTry` / `counted` to `1`/`0`, all other fields directly.
- `getRecentMathQuizRecords`: `equalTo('track', track)`, `orderByDesc('created_at')`, then `orderByDesc('id')`, `limitAs(limit)`; map each row with a private `readMathQuizRecordRow(resultSet)`.
- `countMathQuizPurposeInSession`: `equalTo('session_id', sessionId)`, `equalTo('purpose', purpose)`, `greaterThan('level', 0)`; return `resultSet.rowCount` (or count rows in a loop) and close.
- `getMathQuizProgress`: `equalTo('track', track)` + `limitAs(1)`; return `null` when no row. Read `current_level`, `correct_at_level`, `consecutive_wrong`, `updated_at`.
- `upsertMathQuizProgress`: `rdbStore.insert(TableNames.MATH_QUIZ_PROGRESS, bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE)`; return `true` on success, `false` and log on failure.
- `recordMathQuizAnswer`: `await this.waitForInitialization()`, null check; `this.rdbStore.beginTransaction()`, `const rowId = await this.insertMathQuizRecord(record)`; if `rowId < 0` roll back and return `-1`; if `progress !== null`, `const ok = await this.upsertMathQuizProgress(progress)`, and if `!ok` roll back and return `-1`; `this.rdbStore.commit()` and return `rowId`. Wrap in `try/catch`, call `rollBack()` defensively, log, return `-1`.

- [ ] **Step 3: Verify the schema and build**

```bash
grep -n "MATH_QUIZ_RECORDS\|MATH_QUIZ_PROGRESS\|math_quiz_records\|math_quiz_progress" entry/src/main/ets/services/DatabaseService.ets
```

Expected: the two `TableNames` constants, the two create SQL constants, the two `executeSql` calls, the two index SQL strings, and the method bodies. Then run the build command. Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/services/DatabaseService.ets
git commit -m "feat: persist math quiz records and per-track progress"
```

---

### Task 5: `MathQuizHistoryService` (gate and answer orchestration)

**Files:**
- Create: `entry/src/main/ets/services/MathQuizHistoryService.ets`

**Interfaces:**
- Consumes: `getDatabaseService`, `getChildProfileService`, `parseMathQuizAnswer`, all Task 1–3 pure functions/types.
- Produces:
  - `class MathQuizHistoryService`
  - `getMathQuizHistoryService(): MathQuizHistoryService`
  - `evaluateGate(argsJson: string, sessionId: string): Promise<MathQuizGateResult>`
  - `recordAnswer(argsJson: string, answerJson: string, sessionId: string, toolCallId: string): Promise<MathQuizProgressHint | null>`
  - `getEffectiveProgress(track: MathQuizTrack): Promise<MathQuizProgressRow>`
  - `getProgressSummary(): Promise<ChildProfileMathProgress[]>`

`MathQuizGateResult` fields: `ok: boolean`, `error: string`, `message: string`, `target: MathQuizTarget | null`, `progress: MathQuizProgressSnapshot | null`.
`MathQuizProgressSnapshot` fields: `correct_at_level: number`, `needed: number`, `consecutive_wrong: number`.

- [ ] **Step 1: Implement the service**

- Singleton: `private static instance`, private constructor sets `this.database = getDatabaseService()`; `getInstance()` and the module-level `getMathQuizHistoryService()`.
- `getEffectiveProgress(track)`: try `database.getMathQuizProgress(track)`; if a row exists return it. Otherwise read `getChildProfileService().getProfile()`, build `Record<string, number>` from `profile.skills[key].level`, call `initialLevelForTrack`, and return `{ track, currentLevel: level, correctAtLevel: 0, consecutiveWrong: 0, updatedAt: 0 }`. Any failure → level 1. Never write.
- `evaluateGate(argsJson, sessionId)`:
  - `const gating = parseMathQuizGatingArgs(argsJson)`; `null` → `{ ok:false, error:'difficulty_gate', message:'math_quiz 参数解析失败，请检查 JSON 后重试', target:null, progress:null }`.
  - `const info = resolveMathQuizLevel(gating.input)`; `!info.gate && info.error === ''` → `{ ok:true, error:'', message:'', target:null, progress:null }` (a `gate=false + error` combination should still reach the gate and be rejected).
  - `const progress = await this.getEffectiveProgress(info.track)`.
  - For `practice` with a non-empty `expressionKey`: query `getRecentMathQuizRecords(info.track, 20)` and collect `expressionKey`s; on failure log and use `[]`.
  - For `warm_up`/`review` with a non-empty `sessionId`: query `countMathQuizPurposeInSession`; on failure use `0`.
  - `const decision = evaluateMathQuizGate({...})`.
  - Return `{ ok: decision.allowed, error: decision.error, message: decision.message, target: decision.target, progress: snapshot }`, where `snapshot` is `{ correct_at_level: progress.correctAtLevel, needed: 10, consecutive_wrong: progress.consecutiveWrong }`.
- `recordAnswer(argsJson, answerJson, sessionId, toolCallId)`:
  - `parseMathQuizGatingArgs` / `parseMathQuizAnswer`; a `null` gating result, a null answer, or `answer.answered !== true` → return `null` (no record, no hint).
  - Parse the raw args defensively (`try { raw = JSON.parse(argsJson) as Record<string, Object> } catch { return null }`), resolve the level, and map `attempts` as `answer.attempts > 0 ? answer.attempts : (answer.correct ? 1 : 2)`.
  - Build the record with exactly these fields:

```ts
const record: MathQuizRecordInsert = {
  createdAt: Date.now(),
  sessionId: sessionId,
  toolCallId: toolCallId,
  quizType: gating.input.quizType,
  track: info.track,
  level: info.level,
  purpose: gating.purpose,
  skillKey: normalizeSkillKey(gating.input.skillKey),
  expressionKey: info.expressionKey,
  expression: buildMathQuizRecordExpression(gating.input),
  question: String(raw['question'] ?? ''),
  correct: answer.correct === true,
  firstTry: answer.correct === true && attempts === 1,
  attempts: attempts,
  childAnswer: String(answer.child_answer ?? ''),
  correctAnswer: String(answer.correct_answer ?? ''),
  counted: false,
  metadataJson: ''
}
```

  - If `!info.gate || info.error !== ''`: `await this.database.insertMathQuizRecord(record)` with `counted=false`; return `null`.
  - Else: `progress = await this.getEffectiveProgress(info.track)`; `update = applyMathQuizProgress(progress, info.level, gating.purpose, answer.correct === true, attempts, Date.now())`; set `record.counted = update.counted`; `const rowId = await this.database.recordMathQuizAnswer(record, update.counted ? update.row : null)`; if `rowId < 0` return `null`; return `buildMathQuizProgressHint(update, info.track, 10)`.
- `getProgressSummary()`: use `const tracks: MathQuizTrack[] = ['add', 'sub', 'muldiv', 'compare', 'clock', 'elapsed']`; for each `getEffectiveProgress` + `getLevelSpec`; push `{ track, level: row.currentLevel, label: spec.label, correct_at_level: row.correctAtLevel, needed: 10, nextTarget: buildTarget(spec) }`. Wrap the whole method in `try/catch` returning `[]`.

Do not import `BuiltinTools`, `ToolExecutionService`, or any UI module.

- [ ] **Step 2: Verify the service has no import cycle and compiles**

```bash
grep -n "import" entry/src/main/ets/services/MathQuizHistoryService.ets
```

Expected imports only from `../models/...`, `../utils/...`, `./DatabaseService`, `./ChildProfileService`, and `../utils/MathQuizGame`. Then run the build command. Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3: Commit**

```bash
git add entry/src/main/ets/services/MathQuizHistoryService.ets
git commit -m "feat: add math quiz history service with difficulty gate"
```

---

### Task 6: Hook the gate and answer recording into `handleMathQuiz`

**Files:**
- Modify: `entry/src/main/ets/services/ToolExecutionService.ets`

**Interfaces:**
- Consumes: `getMathQuizHistoryService()` from Task 5; `MathQuizProgressHint` from Task 1.
- Produces: no new public API; `handleMathQuiz` gains the gate, the answer record, and the merged `math_progress`.

- [ ] **Step 1: Normalize U+2212, then add the gate after `validateMathQuizArgs`**

At the very start of `handleMathQuiz`, **before** `validateMathQuizArgs` runs, call a normalization helper. This is required because `MathQuizValidation`'s `sanitizeExpression` drops `−` (U+2212), so `47 + 28 − 15` would otherwise be validated as `47+2815` and rejected as an answer inconsistency before the gate ever sees it.

```ts
private normalizeMathQuizMinus(toolCall: ToolCall): void {
  try {
    const args: Record<string, Object> = JSON.parse(toolCall.arguments) as Record<string, Object>
    const expression = args['expression']
    if (typeof expression !== 'string') {
      return
    }
    const text = expression as string
    const normalized = text.replace(/−/g, '-')
    if (normalized !== text) {
      args['expression'] = normalized as Object
      toolCall.arguments = JSON.stringify(args)
    }
  } catch (error) {
    console.warn('ToolExecutionService', `math_quiz arg normalization skipped: ${String(error)}`)
  }
}
```

Call it at the top of `handleMathQuiz`:

```ts
this.normalizeMathQuizMinus(toolCall)
```

Then, after the existing `if (!mathValidation.ok) { ... }` block and before `toolCall.approvalState = 'pending'`:

```ts
const gate = await getMathQuizHistoryService().evaluateGate(toolCall.arguments, context.sessionId)
if (!gate.ok) {
  console.warn('ToolExecutionService', `math_quiz gate rejected: ${gate.error} ${gate.message}`)
  toolCall.approvalState = 'denied'
  return new ToolResult(
    toolCall.id,
    JSON.stringify({
      error: gate.error,
      should_retry: true,
      message: gate.message,
      target: gate.target,
      progress: gate.progress
    }),
    true,
    toolCall.displayName,
    toolCall.sourceLabel
  )
}
```

Add the import:
```ts
import { getMathQuizHistoryService } from './MathQuizHistoryService'
import { MathQuizProgressHint } from '../models/MathQuizProgressionModels'
```

- [ ] **Step 2: Record the answer and merge the hint**

Replace the answered branch's tail:

```ts
toolCall.approvalState = 'answered'
toolCall.approvalReason = answerJson
```

with:

```ts
let progressHint: MathQuizProgressHint | null = null
try {
  progressHint = await getMathQuizHistoryService().recordAnswer(
    toolCall.arguments, answerJson, context.sessionId, toolCall.id
  )
} catch (error) {
  console.warn('ToolExecutionService', `math_quiz record failed: ${String(error)}`)
}
this.recordStarEvent('math_quiz', toolCall, context, answerJson)
toolCall.approvalState = 'answered'
toolCall.approvalReason = answerJson
console.info('ToolExecutionService', `math_quiz answered: ${toolCall.id}`)
return new ToolResult(
  toolCall.id,
  this.mergeMathProgressHint(answerJson, progressHint),
  false,
  toolCall.displayName,
  toolCall.sourceLabel
)
```

Delete the old `console.info` + `return new ToolResult(... answerJson ...)` lines that followed (keep exactly one return).

- [ ] **Step 3: Add the private merge helper**

```ts
private mergeMathProgressHint(answerJson: string, hint: MathQuizProgressHint | null): string {
  if (hint === null) {
    return answerJson
  }
  try {
    const parsed: Record<string, Object> = JSON.parse(answerJson) as Record<string, Object>
    parsed['math_progress'] = hint as Object
    return JSON.stringify(parsed)
  } catch (error) {
    console.warn('ToolExecutionService', `Failed to merge math_progress: ${String(error)}`)
    return answerJson
  }
}
```

- [ ] **Step 4: Verify the tool result paths and build**

```bash
grep -n "normalizeMathQuizMinus\|evaluateGate\|recordAnswer\|mergeMathProgressHint\|approvalReason = answerJson" entry/src/main/ets/services/ToolExecutionService.ets
```

Expected: one `normalizeMathQuizMinus` call before `validateMathQuizArgs`, one `evaluateGate` call after `validateMathQuizArgs`, one `recordAnswer` call, one `mergeMathProgressHint` method and call, and `approvalReason = answerJson` still present. Then run the build. Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/services/ToolExecutionService.ets
git commit -m "feat: gate and record math_quiz answers"
```

---

### Task 7: Tool schema, `purpose`, and `child_profile.mathProgress`

**Files:**
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`

**Interfaces:**
- Consumes: `getMathQuizHistoryService()` and `MathQuizProgressHint` from Task 5.
- Produces:
  - `MathQuizArgs.purpose?: 'practice' | 'warm_up' | 'review'`
  - `ChildProfileSummary.mathProgress: ChildProfileMathProgress[]`
  - `child_profile(action:"read")` and `update` responses include `mathProgress`.

- [ ] **Step 1: Update `MathQuizArgs` and the schema**

Add to `MathQuizArgs`:
```ts
purpose?: 'practice' | 'warm_up' | 'review'
```

Add to `rawSchemaJson` after `skill_key`:
```json
"purpose": {
  "type": "string",
  "enum": ["practice", "warm_up", "review"],
  "description": "practice=正式练习（默认，必须匹配当前目标难度，计入掌握进度）；warm_up=热身（可低于当前难度，不计入进度，每会话最多 5 题）；review=复习（可低于当前难度，不计入进度，每会话最多 3 题）。"
}
```

Change the `expression` description to:
```
"arithmetic 专用: 算式字符串, e.g. 「3 + 2」 或多步连加连减链式 「47 + 28 - 15」. 显示为 「47 + 28 - 15 = ?」. 链式最多 3 个运算符, 中间过程与最终结果都不能为负数. 应用题 (word_problem=true) 也必须填隐藏算式 (如 「3 + 2」), 卡片只显示 question, 不会把算式显示给孩子. 其他 type 不用填."
```

Change the `skill_key` description to:
```
"强烈建议填写; 决定难度轨与画像维度; 优先用 math_addition / math_subtraction / math_multiply / math_divide / math_comparison / math_time / math_word_problem / math_counting / math_number_sense / math_shapes. 历史短名 (addition / subtraction / multiply / divide / shapes / comparison / time / counting / number_sense / word_problem) 会被自动归一; 未知值按空处理并由算式推断."
```

Append to the tool function description (single-quoted TS string — do not use an apostrophe in `child's`):
`' Set purpose (default practice) and skill_key; practice questions must match the child current target level returned by child_profile.mathProgress or the difficulty_gate retry payload.'`

> JSON-in-template-literal: the new description strings contain no ASCII `"`. After editing, extract `rawSchemaJson` and run a `JSON.parse` check with `node -e` before trusting the build.

- [ ] **Step 2: Add `mathProgress` to `ChildProfileSummary`**

Add the field and constructor parameter at the end:
```ts
mathProgress: ChildProfileMathProgress[] = []
```
and in the constructor `this.mathProgress = mathProgress`. `new ChildProfileSummary(...)` has exactly one call site (`formatProfileForAI`); update it there.

Change `formatProfileForAI(profile)` to `formatProfileForAI(profile, mathProgress: ChildProfileMathProgress[])` and pass the new array to the constructor. Add a private loader:

```ts
private async loadMathProgress(): Promise<ChildProfileMathProgress[]> {
  try {
    return await getMathQuizHistoryService().getProgressSummary()
  } catch (error) {
    console.warn('ChildProfileExecutor', `Failed to load math progress: ${String(error)}`)
    return []
  }
}
```

In the `read` branch:
```ts
const profile = await service.getProfile()
const mathProgress = await this.loadMathProgress()
return JSON.stringify(this.formatProfileForAI(profile, mathProgress))
```

In `handleUpdate`, before the final return:
```ts
const mathProgress = await this.loadMathProgress()
return JSON.stringify(this.formatProfileForAI(profile, mathProgress))
```

Import:
```ts
import { getMathQuizHistoryService } from '../services/MathQuizHistoryService'
import { ChildProfileMathProgress } from '../models/MathQuizProgressionModels'
```

- [ ] **Step 3: Verify the schema JSON and build**

Run the JSON-in-template-literal check from the project notes (extract the `rawSchemaJson` template literal and `JSON.parse` it with `node -e`). Expected: parse succeeds. Then run the build. Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/config/BuiltinTools.ets
git commit -m "feat: add math_quiz purpose and child_profile mathProgress"
```

---

### Task 8: Prompt contract updates

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets`

- [ ] **Step 1: Fix the base prompt's math dimension list**

Replace the line beginning `'【数学】8 维:` with:

```ts
'【数学】10 维:math_counting / math_number_sense / math_addition / math_subtraction / math_multiply / math_divide / math_shapes / math_comparison / math_time / math_word_problem。出题必带 type 字段(arithmetic / shape / comparison / time / elapsed_time),用 math_quiz + math_verify。',
```

Removing `word_problem` from the `type` list is required — it is a boolean flag on `arithmetic`, not a sixth type.

- [ ] **Step 2: Add the progression contract to the default prompt**

Immediately after the existing `'【数学题型契约】...'` line, add:

```ts
'【难度进度】正式练习 math_quiz 必带 skill_key 与 purpose(默认 practice)。practice 严格按 child_profile 的 mathProgress[].nextTarget 出题,不要低于目标级;五步课热身用 purpose:"warm_up"(每会话最多 5 题),单元复习用 purpose:"review"(最多 3 题),二者不计入掌握。收到 difficulty_gate / duplicate_question 时按 target 的 label / example / max_operand(若有)重出,不要争辩、不要保持原题。应用题 word_problem=true 也要填隐藏 expression。孩子第二次才答对不算掌握;两题都两次错系统会自动降级,按新的 next_target 出题。不要把难度级别 / L7 / 进度说给孩子听。',
```

- [ ] **Step 3: Add the progression contract to `KIDS_MATH_SYSTEM_PROMPT`**

After its `'【出题契约】...'` line, add:

```ts
'【难度进度契约】每次正式练习 math_quiz 必带 skill_key 与 purpose(默认 practice)。practice 严格按 child_profile.mathProgress[].nextTarget 出题,不得低于目标级;五步课热身用 purpose:"warm_up"(每会话最多 5 题),单元复习用 purpose:"review"(最多 3 题),二者不计入掌握。收到 difficulty_gate / duplicate_question 时按 target 的 label / example / max_operand(若有)重出,不要保持原题。应用题 word_problem=true 也要填隐藏 expression。第二次才答对不算掌握;两题都两次错系统会自动降级,按新的 next_target 出题。不要向孩子解释难度级别 / L7 / 进度。',
```

Then change the same prompt's phrase `只用 question 讲场景、expression 留空` to `question 讲场景,expression 填隐藏算式（卡片仍只显示 question）`.

- [ ] **Step 4: Verify no stale instructions remain**

```bash
grep -n "expression 留空\|8 维\|word_problem)," entry/src/main/ets/models/AssistantModels.ets
```

Expected: no output (or only legitimate text that does not instruct leaving `expression` empty for word problems). Then run the build. Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/models/AssistantModels.ets
git commit -m "docs: teach assistants the math quiz progression contract"
```

---

### Task 9: Full verification and architecture-rule update

**Files:**
- Modify: `.claude/rules/teaching-architecture.md`

- [ ] **Step 1: Run the full build**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

Expected: `BUILD SUCCESSFUL` and `entry/build/default/outputs/default/entry-default-signed.hap` exists.

- [ ] **Step 2: Run the new hypium suite in DevEco Studio**

Right-click `entry/src/ohosTest/ets/test/utils/MathQuizProgression.test.ets` → Run. Expected: all cases PASS.

- [ ] **Step 3: Update `.claude/rules/teaching-architecture.md`**

In the `math_quiz` row of §4's tool table, append:

`；2026-11 起带难度闸门：按 track 维护进度，最近 20 道同轨题去重，首答正确累计 10 次升级、两次都错连续 2 题降级；warm_up/review 不计进度（每会话 5/3 题配额）。详见 docs/superpowers/specs/2026-11-05-math-quiz-progression-design.md`

Add one short paragraph after the tool table:

`math_quiz 的难度由 utils/MathQuizProgression.ets 从算式结构判定（加减 15 级 / 乘除 10 级 / 比较 6 级 / 认钟与经过时间各 4 级），services/MathQuizHistoryService.ets 负责闸门与作答记录（math_quiz_records / math_quiz_progress 两表）。child_profile 读取时额外返回 mathProgress（每轨当前级与 nextTarget），AI 应据此出题。`

- [ ] **Step 4: Commit**

```bash
git add .claude/rules/teaching-architecture.md
git commit -m "docs: document math quiz progression in teaching architecture"
```

---

## Self-Review Notes

- **Spec coverage:** §4.1–4.6 → Tasks 1–2; §5 → Task 3; §6 → Task 4; §7 → Tasks 3/5/6; §8 → Tasks 3/6/7; §9 → Task 7; §10–11 → Tasks 1–9.
- **Spec inconsistency fixed in this pass:** spec §11.1 originally said `10 − 3 + 5` → L2, contradicting §4.2's "20 以内的 2–3 步混合落到 L3". The spec's L3 row and §11.1 test line are now corrected to L3 (and L3's carry rule to `any`, steps 1–3); this plan implements **L3** and the Task 2 test asserts L3.
- **Skill-key order:** `math_shapes`/`math_comparison`/`math_time` type mismatches are checked before the shape/comparison/time branches, so a `math_shapes` + arithmetic question returns an error instead of being silently routed to `shape`.
- **Muldiv target omits `max_operand`:** the spec's `buildTarget` rule names compare/clock/elapsed as the omission cases, but the muldiv ladder is shape-based, so emitting `max_operand: 0` would actively mislead the LLM. `label` + `example` carry the instruction; this is the one deliberate deviation from the literal target rule.
- **Method names are consistent:** `evaluateGate` / `recordAnswer` / `getEffectiveProgress` / `getProgressSummary` are used identically in Tasks 5–7; `mergeMathProgressHint` is the only merge helper.
- **No UI changes:** the card still reads `approvalReason`; only the LLM channel (`ToolResult.content`) sees `math_progress`.
