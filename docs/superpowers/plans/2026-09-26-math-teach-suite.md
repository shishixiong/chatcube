# math_teach 讲解工具 + 五步课协议 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 小星数学老师（kids_math）从"只出题、不讲算理"升级为五步课协议——新增 `math_teach` 讲解工具（8 块交互讲解板）、画像 2 新维度 + 2 新字段、预校验 5 规则、KIDS_MATH 提示词重写。

**Architecture:** 一个工具八块板（mode 八选一）。调用链镜像 math_quiz：AI 调 math_teach → ToolExecutionService 特殊路径（读画像 level 注入校验 → 预校验失败 should_retry → pending Promise → 卡片回执，**不授星**）→ MessageBubble 内联渲染 MathTeachCard → mode 分发到 components/mathTeach/ 对应板 → 孩子完成关键交互 → onAnswer 回执。板几何/预校验全部下沉 utils 纯函数（hypium 可测），组件组织跟随 verticalMath/ 先例。

**Tech Stack:** ArkTS stage 模型（@ComponentV2/@Local/@Param/@Event）、hypium（IDE 运行）、KidsBrandTokens、CardShell。

**Spec:** `docs/superpowers/specs/2026-09-26-math-teach-suite-design.md`（决策记录 §0、schema §3、板交互 §4、校验 §5、提示词 §6、画像同步 §7、触点 §8）

## Global Constraints

- 构建验证命令（每个任务结束跑一次）：`DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug`
- **CLI `hvigorw test` 不可用**（MEMORY：脚手架损坏）——hypium 测试在 DevEco Studio 中右键测试文件 Run，由人执行（Task 11）。代理验证 = 干净 assembleHap。测试文件**不注册**进 List.test.ets。
- **严禁**在 handleMathTeach 中调 `recordStarEvent`（用户决策：讲解不授星；StarEventModels 10 处漂移点整段不动）。
- **严禁**给 ChatPage 加 largeSize sheet（Decision step 8 = NO；板按气泡宽度设计，仅内联渲染）。
- 只改 kids_math：`DEFAULT_ASSISTANT_SYSTEM_PROMPT`、`DEFAULT_ASSISTANT_LOCKED_TOOL_IDS`、kids_english/chinese/games 三个学科助手均不动。
- matching_pairs 的 schema 一字不改（复用现有 `{left,right}` 模型出算式配对）。
- rawSchemaJson 模板字符串中的**描述字段一律用「」引号，禁止裸 ASCII `"`**（启动时 JSON.parse 炸裂陷阱）；改完 BuiltinTools 后跑对应任务的 node 验证命令。
- ArkTS 严格模式：内联对象字面量必须显式标注类型（10605038）；ForEach 回调体内禁止 const 声明（10905209，抽成方法）；禁止解构 `const [a,b]`（10605074）；`Row.alignItems` 用 `VerticalAlign`、`Column.alignItems` 用 `HorizontalAlign`；`.rotate({centerX:'50%'})` 的 % 相对自身尺寸（数字则相对父容器）。
- @Local Map/数组修改后必须整体重新赋值或以新数组触发响应式（`this.x = new Map(this.x)`）。
- @Builder 体内禁止 const 声明与提前 return；响应式数据读 `this.xxx` 有效，传字符串快照会断响应式。
- 所有新文件遵循 verticalMath/ 先例：纯函数文件 ArkUI-free、一板一文件、hypium 测试放 `entry/src/ohosTest/ets/test/utils/`。
- 每个任务独立 commit，信息前缀 `feat(math-teach):` / `test(math-teach):`。
- 本计划所有 `Record<string, Object>` 取值用 typeof 窄化 + as 断言的私有 helper（见 Task 2/8 代码），不裸取。

## Review Focus

（spec 隐含但无任务测试直接覆盖、最可能咬人的五类输入——每行附钉住它的测试）

1. **旧画像 JSON 兼容**：升级前用户 Preferences 里是 24 维旧 JSON——parse 后必须 26 维齐全、strategy/misconceptions=''，绝不能 undefined 导致 LearningProfilePage 崩溃。→ Task 3 的 ChildProfileParse.test 钉住。
2. **handleUpdate 局部更新清空历史**：AI 只传 `{key, level}` 不传 strategy 时，历史 strategy/misconceptions 必须保留（非空才写）。→ Task 3 Step 2 代码 + ChildProfileParse.test 钉住。
3. **坏参不崩溃只占位**：toolCall.arguments JSON.parse 失败 / mode 越界 / 数值 NaN 时 MathTeachCard 必须渲染占位文案「这道讲解出错了」，绝不能抛异常白屏聊天页。→ Task 8 parseMathTeachArgs valid=false 路径 + MathTeachValidation.test 的坏 JSON 用例钉住。
4. **完成门防误触**：interactions 未达阈值时「我学会了 · 继续」必须 disabled——孩子乱点一下就回执会让 AI 误判讲解完成。→ Task 8 代码 + Task 11 真机清单钉住。
5. **数轴凑十边界**：start+step 恰好 =10（无第二跳）或 ≤10（不该用凑十板）——校验必须把 ≤10 全拒；numberLineHops 纯函数对 secondHop<0 取 0 兜底。→ Task 1 + Task 2 的边界用例钉住。

## File Structure

```
entry/src/main/ets/
├── utils/
│   ├── SearchToolIdentityUtils.ets      [改] MATH_TEACH_TOOL_ID 常量 + isMathTeachFunctionName
│   ├── MathTeachBoards.ets              [新] 板几何纯函数（clockAngles/balanceTilt/barPercents/numberLineHops/bondSplit/canBundle）
│   ├── MathTeachValidation.ets          [新] 预校验 5 规则（validateMathTeachArgs）
│   ├── LessonPlannerValidation.ets      [改] 合法维度表 +2
│   └── LessonPlanPromptUtils.ets        [改] 维度清单 +2、进阶表 +2 行
├── services/
│   ├── ToolExecutionService.ets         [改] handleMathTeach（镜像 handleMathQuiz，无授星）+ dispatch 分支
│   └── ChildProfileService.ets          [改] SkillDimension +2 字段；SKILL_DEFINITIONS 24→26；parseProfile 兼容
├── config/BuiltinTools.ets              [改] math_teach 注册全套 + child_profile schema/handleUpdate 扩展
├── models/AssistantModels.ets           [改] KIDS_MATH_LOCKED_TOOL_IDS +2；KIDS_MATH_SYSTEM_PROMPT 数学段重写
├── components/
│   ├── MathTeachCard.ets                [新] shell：mode 分发 + 完成门 + 回执 + 已答态
│   ├── mathTeach/                       [新] TeachStepper + 8 块板（一板一文件）
│   └── MessageBubble.ets                [改] 9 个挂载点（spec §8 的 7 站点，or 链算 2 处）
└── pages/LearningProfilePage.ets        [改] math 组 +2 维；strategy/misconceptions 标签行
entry/src/ohosTest/ets/test/
├── utils/MathTeachBoards.test.ets       [新]
├── utils/MathTeachValidation.test.ets   [新]
└── utils/ChildProfileParse.test.ets     [新]（视 parseProfile 可测性，见 Task 3）
```

---

### Task 1: 工具 ID + 板几何纯函数（SearchToolIdentityUtils + MathTeachBoards）

**Files:**
- Modify: `entry/src/main/ets/utils/SearchToolIdentityUtils.ets`（MATH_QUIZ_TOOL_ID 常量区 L10 / isMathQuizFunctionName L91-93 区域）
- Create: `entry/src/main/ets/utils/MathTeachBoards.ets`
- Test: `entry/src/ohosTest/ets/test/utils/MathTeachBoards.test.ets`

**Interfaces:**
- Consumes: 无（纯函数 + 常量）
- Produces（后续任务依赖的精确签名）:
  - `export const MATH_TEACH_TOOL_ID: string`（= `'math_teach'`）
  - `export function isMathTeachFunctionName(functionName: string): boolean`
  - `interface ClockAngles { hourDeg: number; minuteDeg: number }`；`clockAngles(hour: number, minute: number): ClockAngles`
  - `balanceTilt(left: number, right: number): number`
  - `interface BarPercents { aPct: number; bPct: number }`；`barPercents(a: number, b: number): BarPercents`
  - `interface NumberLineHops { firstHop: number; secondHop: number; sum: number }`；`numberLineHops(start: number, step: number): NumberLineHops`
  - `bondSplit(total: number, left: number): number`
  - `canBundle(ones: number): boolean`

- [ ] **Step 1: 写工具 ID 与判定函数**

在 `SearchToolIdentityUtils.ets` 的 `MATH_QUIZ_TOOL_ID` 常量（L10）之后插入：

```typescript
export const MATH_TEACH_TOOL_ID: string = 'math_teach'
```

在 `isMathQuizFunctionName`（L91-93）之后插入：

```typescript
export function isMathTeachFunctionName(functionName: string): boolean {
  return normalizeToolFunctionName(functionName) === MATH_TEACH_TOOL_ID
}
```

- [ ] **Step 2: 写 MathTeachBoards.ets（全部纯函数，强制返回类型注解）**

```typescript
/**
 * math_teach 讲解板几何纯函数（ArkUI-free，hypium 全覆盖）。
 * 所有返回值强制类型注解；防御性输入取界，不抛异常。
 */

export interface ClockAngles {
  hourDeg: number
  minuteDeg: number
}

export interface BarPercents {
  aPct: number
  bPct: number
}

export interface NumberLineHops {
  firstHop: number   // 10 - start（凑十第一跳）
  secondHop: number  // 剩余跳数；start+step=10 时为 0（校验层已拒 ≤10，此为兜底）
  sum: number
}

export function clockAngles(hour: number, minute: number): ClockAngles {
  const h: number = ((hour % 12) + 12) % 12
  return { hourDeg: (h + minute / 60) * 30, minuteDeg: minute * 6 }
}

export function balanceTilt(left: number, right: number): number {
  const raw: number = (right - left) * 4
  if (raw > 12) { return 12 }
  if (raw < -12) { return -12 }
  return raw
}

export function barPercents(a: number, b: number): BarPercents {
  const total: number = a + b
  if (total <= 0) {
    const zero: BarPercents = { aPct: 0, bPct: 0 }
    return zero
  }
  const p: BarPercents = { aPct: Math.round(a / total * 100), bPct: Math.round(b / total * 100) }
  return p
}

export function numberLineHops(start: number, step: number): NumberLineHops {
  const firstHop: number = 10 - start
  let secondHop: number = step - firstHop
  if (secondHop < 0) { secondHop = 0 }
  const hops: NumberLineHops = { firstHop: firstHop, secondHop: secondHop, sum: start + step }
  return hops
}

export function bondSplit(total: number, left: number): number {
  let l: number = left
  if (l < 0) { l = 0 }
  if (l > total) { l = total }
  return total - l
}

export function canBundle(ones: number): boolean {
  return ones >= 10
}
```

- [ ] **Step 3: 写 hypium 测试**

```typescript
import { describe, it, expect } from '@ohos/hypium'
import {
  clockAngles, balanceTilt, barPercents, numberLineHops, bondSplit, canBundle,
  ClockAngles, BarPercents, NumberLineHops
} from '../../../../main/ets/utils/MathTeachBoards'

export default function mathTeachBoardsTest() {
  describe('mathTeachBoards', () => {
    it('clockAngles_9点30分', 0, () => {
      const a: ClockAngles = clockAngles(9, 30)
      expect(a.hourDeg === 285).assertTrue()
      expect(a.minuteDeg === 180).assertTrue()
    })
    it('clockAngles_12点整归零', 0, () => {
      const a: ClockAngles = clockAngles(12, 0)
      expect(a.hourDeg === 0).assertTrue()
      expect(a.minuteDeg === 0).assertTrue()
    })
    it('balanceTilt_±12截断', 0, () => {
      expect(balanceTilt(9, 5) === -12).assertTrue()
      expect(balanceTilt(5, 9) === 12).assertTrue()
      expect(balanceTilt(5, 6) === 4).assertTrue()
      expect(balanceTilt(5, 5) === 0).assertTrue()
    })
    it('barPercents_按和归一', 0, () => {
      const p: BarPercents = barPercents(9, 5)
      expect(p.aPct === 64).assertTrue()
      expect(p.bPct === 36).assertTrue()
    })
    it('barPercents_零和防御', 0, () => {
      const p: BarPercents = barPercents(0, 0)
      expect(p.aPct === 0 && p.bPct === 0).assertTrue()
    })
    it('numberLineHops_9加5先跳1再跳4', 0, () => {
      const h: NumberLineHops = numberLineHops(9, 5)
      expect(h.firstHop === 1 && h.secondHop === 4 && h.sum === 14).assertTrue()
    })
    it('numberLineHops_6加7先跳4再跳3', 0, () => {
      const h: NumberLineHops = numberLineHops(6, 7)
      expect(h.firstHop === 4 && h.secondHop === 3 && h.sum === 13).assertTrue()
    })
    it('numberLineHops_secondHop负数取0兜底', 0, () => {
      const h: NumberLineHops = numberLineHops(9, 1)
      expect(h.firstHop === 1 && h.secondHop === 0 && h.sum === 10).assertTrue()
    })
    it('bondSplit_越界取0或total', 0, () => {
      expect(bondSplit(9, 4) === 5).assertTrue()
      expect(bondSplit(9, -1) === 9).assertTrue()
      expect(bondSplit(9, 12) === 0).assertTrue()
    })
    it('canBundle_满10才捆', 0, () => {
      expect(canBundle(10)).assertTrue()
      expect(canBundle(9) === false).assertTrue()
    })
  })
}
```

- [ ] **Step 4: 构建验证**

Run: `DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug`
Expected: BUILD SUCCESSFUL（测试文件是否可运行由人在 Task 11 IDE 执行）

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/utils/SearchToolIdentityUtils.ets entry/src/main/ets/utils/MathTeachBoards.ets entry/src/ohosTest/ets/test/utils/MathTeachBoards.test.ets
git commit -m "feat(math-teach): add MATH_TEACH_TOOL_ID and board geometry pure functions"
```

---

### Task 2: 预校验 5 规则（MathTeachValidation）

**Files:**
- Create: `entry/src/main/ets/utils/MathTeachValidation.ets`
- Test: `entry/src/ohosTest/ets/test/utils/MathTeachValidation.test.ets`

**Interfaces:**
- Consumes: 无（纯函数）
- Produces:
  - `export interface MathTeachValidationResult { ok: boolean; error: string }`
  - `export function validateMathTeachArgs(rawArgs: string, profileLevels: Record<string, number> | null): MathTeachValidationResult`
  - 签名较 spec §5 细化：args 收原始 JSON 字符串、函数内部 parse（镜像 `validateMathQuizArgs` 的 parse-inside 模式，测试直接喂 JSON 字符串）；`profileLevels` 注入语义与 spec 一致（null = 跳过规则 4）。

- [ ] **Step 1: 写 MathTeachValidation.ets**

```typescript
/**
 * math_teach 预校验（镜像 MathQuizValidation 范式：只拒绝「算理可证明矛盾」
 * 或「板不可玩」的课，纯外观问题不拦）。
 * 5 规则（spec §5）：mode 白名单 / 凑十一致性 / 概念-模式匹配 / 难度-画像一致 /
 * 演示后必练（规则 5 是 prompt 契约，此处不机器校验）。
 */

export interface MathTeachValidationResult {
  ok: boolean
  error: string
}

const TEACH_MODES: string[] = ['number_bond', 'number_line', 'ten_frame', 'place_value',
  'balance', 'shape', 'clock', 'bar_model']
const SHAPE_FOCUS: string[] = ['circle', 'square', 'triangle', 'rectangle']
const SKILL_KEYS: string[] = ['math_number_sense', 'math_counting', 'math_addition',
  'math_subtraction', 'math_multiply', 'math_divide', 'math_shapes', 'math_comparison',
  'math_time', 'math_word_problem']
const STAGES: string[] = ['warm_up', 'presentation', 'practice', 'production', 'review']

function fail(msg: string): MathTeachValidationResult {
  return { ok: false, error: msg }
}

function pass(): MathTeachValidationResult {
  return { ok: true, error: '' }
}

function getNumber(args: Record<string, Object>, key: string): number {
  const v: Object | undefined = args[key]
  if (typeof v === 'number') { return v as number }
  return NaN
}

function getString(args: Record<string, Object>, key: string): string {
  const v: Object | undefined = args[key]
  if (typeof v === 'string') { return v as string }
  return ''
}

function inRange(v: number, min: number, max: number): boolean {
  return !Number.isNaN(v) && Number.isInteger(v) && v >= min && v <= max
}

export function validateMathTeachArgs(rawArgs: string,
                                      profileLevels: Record<string, number> | null): MathTeachValidationResult {
  let args: Record<string, Object>
  try {
    args = JSON.parse(rawArgs) as Record<string, Object>
  } catch (_e) {
    return fail('math_teach 参数不是合法 JSON')
  }

  // 规则 1a：mode 白名单
  const mode: string = getString(args, 'mode')
  if (TEACH_MODES.indexOf(mode) < 0) {
    return fail('mode 必须是 ' + TEACH_MODES.join('/') + ' 之一，收到「' + mode + '」')
  }

  // 共享参数（规则 1b/3）
  const difficulty: number = getNumber(args, 'difficulty')
  if (!inRange(difficulty, 1, 5)) {
    return fail('difficulty 必须是 1-5 的整数')
  }
  const concept: string = getString(args, 'concept')
  if (concept === '') {
    return fail('concept 必须是一句给孩子看的知识点标题，不能为空')
  }
  const skillKey: string = getString(args, 'skill_key')
  if (SKILL_KEYS.indexOf(skillKey) < 0) {
    return fail('skill_key 必须是数学画像 10 维之一（math_ 开头），收到「' + skillKey + '」')
  }
  const stage: string = getString(args, 'stage')
  if (stage !== '' && STAGES.indexOf(stage) < 0) {
    return fail('stage 只能是 warm_up/presentation/practice/production/review')
  }

  // 规则 1c + 规则 2/3：mode 专属约束
  const modeCheck: MathTeachValidationResult = validateModeArgs(mode, args)
  if (!modeCheck.ok) { return modeCheck }

  // 规则 4：难度-画像一致（|difficulty - level| ≤ 1；level 0 = 未评估跳过；null 跳过）
  if (profileLevels !== null) {
    const lv: Object | undefined = profileLevels[skillKey]
    if (typeof lv === 'number') {
      const level: number = lv as number
      if (level >= 1 && Math.abs(difficulty - level) > 1) {
        return fail('difficulty=' + difficulty + ' 与画像等级 ' + skillKey + '=' + level +
          ' 偏差超过 1 级，请按画像调整难度')
      }
    }
  }

  return pass()
}

function validateModeArgs(mode: string, args: Record<string, Object>): MathTeachValidationResult {
  if (mode === 'number_bond') {
    const total: number = getNumber(args, 'total')
    if (!inRange(total, 2, 20)) { return fail('number_bond 的 total 必须是 2-20 的整数') }
  } else if (mode === 'number_line') {
    const start: number = getNumber(args, 'start')
    const step: number = getNumber(args, 'step')
    if (!inRange(start, 6, 9)) { return fail('number_line 的 start 必须是 6-9（保证能先跳到 10）') }
    if (!inRange(step, 1, 10)) { return fail('number_line 的 step 必须是 1-10 的整数') }
    const sum: number = start + step
    if (sum > 20) { return fail('number_line 的 start+step 不能超过 20') }
    if (sum <= 10) {
      return fail('number_line 只讲 20 以内进位加法：start+step 必须大于 10' +
        '（不进位的加法不需要凑十，用 math_quiz 或 vertical_math）')
    }
  } else if (mode === 'ten_frame') {
    const a: number = getNumber(args, 'a')
    const b: number = getNumber(args, 'b')
    if (!inRange(a, 5, 9)) { return fail('ten_frame 的 a 必须是 5-9（框内已有个数）') }
    if (!inRange(b, 1, 10)) { return fail('ten_frame 的 b 必须是 1-10 的整数') }
    const sum: number = a + b
    if (sum > 20) { return fail('ten_frame 的 a+b 不能超过 20') }
    if (sum <= 10) {
      return fail('ten_frame 只讲 20 以内进位加法：a+b 必须大于 10' +
        '（⚠️ 严禁 a+b 不超过 10 时使用 ten_frame，那样的题不需要凑十）')
    }
  } else if (mode === 'place_value') {
    const tens: number = getNumber(args, 'tens')
    const ones: number = getNumber(args, 'ones')
    if (!inRange(tens, 0, 8)) { return fail('place_value 的 tens 必须是 0-8 的整数') }
    if (!inRange(ones, 0, 9)) { return fail('place_value 的 ones 必须是 0-9 的整数') }
    if (tens === 0 && ones === 0) { return fail('place_value 的 tens 和 ones 不能同时为 0') }
  } else if (mode === 'balance') {
    const left: number = getNumber(args, 'left')
    const right: number = getNumber(args, 'right')
    if (!inRange(left, 1, 20)) { return fail('balance 的 left 必须是 1-20 的整数') }
    if (!inRange(right, 1, 20)) { return fail('balance 的 right 必须是 1-20 的整数') }
  } else if (mode === 'shape') {
    const focus: string = getString(args, 'focus')
    if (SHAPE_FOCUS.indexOf(focus) < 0) {
      return fail('shape 的 focus 必须是 circle/square/triangle/rectangle 之一')
    }
  } else if (mode === 'clock') {
    const hour: number = getNumber(args, 'hour')
    const minute: number = getNumber(args, 'minute')
    if (!inRange(hour, 1, 12)) { return fail('clock 的 hour 必须是 1-12 的整数') }
    if (minute !== 0 && minute !== 30) {
      return fail('clock 的 minute 只能是 0（整点）或 30（半点）')
    }
  } else if (mode === 'bar_model') {
    const pa: number = getNumber(args, 'part_a')
    const pb: number = getNumber(args, 'part_b')
    if (!inRange(pa, 1, 9)) { return fail('bar_model 的 part_a 必须是 1-9 的整数') }
    if (!inRange(pb, 1, 9)) { return fail('bar_model 的 part_b 必须是 1-9 的整数') }
  }
  return pass()
}
```

- [ ] **Step 2: 写 hypium 测试**

（边界数值说明：spec §9 写的「a+b=20 收、=21 拒」在参数界 a∈[5,9]、b∈[1,10] 下不可达（最大和 19）；本测试按实际可达边界改为 =19 收，越界路径由 b 越界用例覆盖。）

```typescript
import { describe, it, expect } from '@ohos/hypium'
import { validateMathTeachArgs } from '../../../../main/ets/utils/MathTeachValidation'

function baseArgs(mode: string): Record<string, Object> {
  const a: Record<string, Object> = {}
  a['mode'] = mode
  a['difficulty'] = 2
  a['concept'] = '测试知识点'
  a['skill_key'] = 'math_addition'
  return a
}

function asJson(a: Record<string, Object>): string {
  return JSON.stringify(a)
}

export default function mathTeachValidationTest() {
  describe('mathTeachValidation', () => {
    it('八个mode合法参数通过', 0, () => {
      const c1: Record<string, Object> = baseArgs('number_bond'); c1['total'] = 9
      const c2: Record<string, Object> = baseArgs('number_line'); c2['start'] = 9; c2['step'] = 5
      const c3: Record<string, Object> = baseArgs('ten_frame'); c3['a'] = 9; c3['b'] = 5
      const c4: Record<string, Object> = baseArgs('place_value'); c4['tens'] = 1; c4['ones'] = 7
      const c5: Record<string, Object> = baseArgs('balance'); c5['left'] = 9; c5['right'] = 5
      const c6: Record<string, Object> = baseArgs('shape'); c6['focus'] = 'circle'
      const c7: Record<string, Object> = baseArgs('clock'); c7['hour'] = 9; c7['minute'] = 30
      const c8: Record<string, Object> = baseArgs('bar_model'); c8['part_a'] = 3; c8['part_b'] = 4
      expect(validateMathTeachArgs(asJson(c1), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c2), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c3), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c4), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c5), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c6), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c7), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c8), null).ok).assertTrue()
    })
    it('mode越界或缺失拒绝', 0, () => {
      expect(validateMathTeachArgs(asJson(baseArgs('huarongdao')), null).ok).assertFalse()
      expect(validateMathTeachArgs('{}', null).ok).assertFalse()
    })
    it('坏JSON拒绝', 0, () => {
      expect(validateMathTeachArgs('not-json', null).ok).assertFalse()
    })
    it('凑十边界_number_line_sum10拒_11收_19收', 0, () => {
      const r1: Record<string, Object> = baseArgs('number_line'); r1['start'] = 9; r1['step'] = 1
      expect(validateMathTeachArgs(asJson(r1), null).ok).assertFalse()
      const r2: Record<string, Object> = baseArgs('number_line'); r2['start'] = 6; r2['step'] = 5
      expect(validateMathTeachArgs(asJson(r2), null).ok).assertTrue()
      const r3: Record<string, Object> = baseArgs('number_line'); r3['start'] = 9; r3['step'] = 10
      expect(validateMathTeachArgs(asJson(r3), null).ok).assertTrue()
    })
    it('凑十边界_ten_frame_sum10拒_11收_19收', 0, () => {
      const t1: Record<string, Object> = baseArgs('ten_frame'); t1['a'] = 5; t1['b'] = 5
      expect(validateMathTeachArgs(asJson(t1), null).ok).assertFalse()
      const t2: Record<string, Object> = baseArgs('ten_frame'); t2['a'] = 5; t2['b'] = 6
      expect(validateMathTeachArgs(asJson(t2), null).ok).assertTrue()
      const t3: Record<string, Object> = baseArgs('ten_frame'); t3['a'] = 9; t3['b'] = 10
      expect(validateMathTeachArgs(asJson(t3), null).ok).assertTrue()
    })
    it('number_line_start越界拒绝', 0, () => {
      const r: Record<string, Object> = baseArgs('number_line'); r['start'] = 5; r['step'] = 7
      expect(validateMathTeachArgs(asJson(r), null).ok).assertFalse()
    })
    it('难度偏差±1收_2拒', 0, () => {
      const lv: Record<string, number> = {}
      lv['math_addition'] = 3
      const ok1: Record<string, Object> = baseArgs('number_bond'); ok1['total'] = 9; ok1['difficulty'] = 2
      const ok2: Record<string, Object> = baseArgs('number_bond'); ok2['total'] = 9; ok2['difficulty'] = 4
      const bad1: Record<string, Object> = baseArgs('number_bond'); bad1['total'] = 9; bad1['difficulty'] = 1
      const bad2: Record<string, Object> = baseArgs('number_bond'); bad2['total'] = 9; bad2['difficulty'] = 5
      expect(validateMathTeachArgs(asJson(ok1), lv).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(ok2), lv).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(bad1), lv).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(bad2), lv).ok).assertFalse()
    })
    it('level0未评估跳过规则4', 0, () => {
      const lv: Record<string, number> = {}
      lv['math_addition'] = 0
      const c: Record<string, Object> = baseArgs('number_bond'); c['total'] = 9; c['difficulty'] = 5
      expect(validateMathTeachArgs(asJson(c), lv).ok).assertTrue()
    })
    it('profileLevels_null跳过规则4', 0, () => {
      const c: Record<string, Object> = baseArgs('number_bond'); c['total'] = 9; c['difficulty'] = 5
      expect(validateMathTeachArgs(asJson(c), null).ok).assertTrue()
    })
    it('skill_key越界与concept空拒绝', 0, () => {
      const s: Record<string, Object> = baseArgs('number_bond'); s['total'] = 9; s['skill_key'] = 'english_vocab'
      expect(validateMathTeachArgs(asJson(s), null).ok).assertFalse()
      const c: Record<string, Object> = baseArgs('number_bond'); c['total'] = 9; c['concept'] = ''
      expect(validateMathTeachArgs(asJson(c), null).ok).assertFalse()
    })
    it('clock_minute只收0和30', 0, () => {
      const c1: Record<string, Object> = baseArgs('clock'); c1['hour'] = 9; c1['minute'] = 15
      expect(validateMathTeachArgs(asJson(c1), null).ok).assertFalse()
      const c2: Record<string, Object> = baseArgs('clock'); c2['hour'] = 9; c2['minute'] = 0
      expect(validateMathTeachArgs(asJson(c2), null).ok).assertTrue()
    })
    it('shape_focus白名单', 0, () => {
      const s: Record<string, Object> = baseArgs('shape'); s['focus'] = 'hexagon'
      expect(validateMathTeachArgs(asJson(s), null).ok).assertFalse()
    })
    it('place_value双零拒绝', 0, () => {
      const p: Record<string, Object> = baseArgs('place_value'); p['tens'] = 0; p['ones'] = 0
      expect(validateMathTeachArgs(asJson(p), null).ok).assertFalse()
    })
  })
}
```

- [ ] **Step 3: 构建验证**

Run: 同 Global Constraints 的 assembleHap 命令。Expected: BUILD SUCCESSFUL

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/utils/MathTeachValidation.ets entry/src/ohosTest/ets/test/utils/MathTeachValidation.test.ets
git commit -m "feat(math-teach): add 5-rule pre-validation with should_retry contract"
```

---

### Task 3: 画像扩展（2 维 + 2 字段，7 处同步）

**Files:**
- Modify: `entry/src/main/ets/services/ChildProfileService.ets`（SkillDimension L6-17、SKILL_DEFINITIONS L36-61、parseProfile L143+）
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`（child_profile schema L1239-1265、key 枚举描述 L1247、工具描述 L1284、handleUpdate L1150-1203）
- Modify: `entry/src/main/ets/pages/LearningProfilePage.ets`（SKILL_GROUPS L33-52、SkillRow L413-432）
- Modify: `entry/src/main/ets/utils/LessonPlannerValidation.ets`（L36 合法维度表）
- Modify: `entry/src/main/ets/utils/LessonPlanPromptUtils.ets`（L67 维度清单、L135 进阶表）
- Test: `entry/src/ohosTest/ets/test/utils/ChildProfileParse.test.ets`

**Interfaces:**
- Consumes: Task 1 无依赖；本任务独立
- Produces:
  - `SkillDimension` 新增字段 `strategy: string` / `misconceptions: string`（默认 `''`，构造尾参带默认值，旧调用点不破）
  - `SKILL_DEFINITIONS` 26 维（新增 `math_number_sense` 数感与数的组成、`math_word_problem` 解决问题）
  - BuiltinTools handleUpdate 支持透传 `strategy` / `misconceptions`（非空才写）

- [ ] **Step 1: ChildProfileService——SkillDimension + SKILL_DEFINITIONS + parseProfile**

SkillDimension（L6-17）追加 2 字段与构造尾参（以文件内现有构造签名为准，只追加带默认值的尾参）：

```typescript
export class SkillDimension {
  key: string
  label: string
  level: number
  lastAssessed: number
  notes: string
  strategy: string          // 新增：孩子解题用的方法（凑十/数数/掰手指）
  misconceptions: string    // 新增：常错点（忘记进位/方向反/数位没对齐）

  constructor(key: string, label: string, level: number = 0, lastAssessed: number = 0,
              notes: string = '', strategy: string = '', misconceptions: string = '') {
    this.key = key
    this.label = label
    this.level = level
    this.lastAssessed = lastAssessed
    this.notes = notes
    this.strategy = strategy
    this.misconceptions = misconceptions
  }
}
```

SKILL_DEFINITIONS（L36-61）：`math_counting` 条目后插入 `new SkillDimension('math_number_sense', '数感与数的组成')`；`math_time` 条目后插入 `new SkillDimension('math_word_problem', '解决问题')`（24→26）。

parseProfile：每维解析处（跟随现有 notes 解析写法）补：

```typescript
strategy: typeof raw.strategy === 'string' ? raw.strategy as string : '',
misconceptions: typeof raw.misconceptions === 'string' ? raw.misconceptions as string : '',
```

`saveProfile` 用原始 `JSON.stringify(profile)` 序列化（L111-115），新字段自动写入——验证无手工挑字段，有则补。

- [ ] **Step 2: BuiltinTools——child_profile schema + handleUpdate**

`skill_updates.items.properties`（L1239-1265）在 notes 后追加两项（描述用「」）：

```json
"strategy": {"type": "string", "description": "孩子解题用的方法，如「凑十」「数数」「掰手指」。没有新证据时不要传此字段，避免覆盖历史记录"},
"misconceptions": {"type": "string", "description": "孩子常错点，如「忘记进位」「方向反」「数位没对齐」。没有新证据时不要传此字段"}
```

`required` 保持 `["key", "level"]`。

L1247 key 枚举 description 与 L1284 工具描述：维度清单改为与 SKILL_DEFINITIONS 完全一致的 **26 个 key**——加 `math_number_sense` / `math_word_problem`，**并顺手补上历史遗漏的 `pinyin`**（现有描述少列了它，pre-existing drift）。

handleUpdate（L1150-1203）在 notes 透传之后镜像追加（非空才写，防 AI 局部更新清空历史）：

```typescript
const strategyVal: Object | undefined = item['strategy']
if (typeof strategyVal === 'string' && (strategyVal as string) !== '') {
  profile.skills[key].strategy = strategyVal as string
}
const miscVal: Object | undefined = item['misconceptions']
if (typeof miscVal === 'string' && (miscVal as string) !== '') {
  profile.skills[key].misconceptions = miscVal as string
}
```

（以 handleUpdate 现有 `item['notes']` 写法为准同构；`item` 的实际类型若非 `Record<string, Object>` 则按现有类型窄化。）

- [ ] **Step 3: LearningProfilePage——分组 + 标签行**

SKILL_GROUPS math 组（L33-52）keys 数组：`math_counting` 后插 `'math_number_sense'`，末尾（`math_time` 后）加 `'math_word_problem'`。

新增两个私有 helper（挂在类上，与 `getSkillLevel` 并列）：

```typescript
private strategyOf(key: string): string {
  const dim = this.findSkillByKey(key)
  if (dim === null) { return '' }
  return dim.strategy
}

private misconceptionsOf(key: string): string {
  const dim = this.findSkillByKey(key)
  if (dim === null) { return '' }
  return dim.misconceptions
}
```

SkillRow builder（L413-432）notes 行之后追加（@Builder 内可用 if，禁止提前 return）：

```typescript
if (this.strategyOf(key) !== '') {
  Text('方法：' + this.strategyOf(key)).fontSize(11).fontColor($r('app.color.text_secondary'))
    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
    .borderRadius(6)
    .backgroundColor($r('app.color.background_secondary'))
}
if (this.misconceptionsOf(key) !== '') {
  Text('易错：' + this.misconceptionsOf(key)).fontSize(11).fontColor($r('app.color.status_error'))
    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
    .borderRadius(6)
    .backgroundColor($r('app.color.background_secondary'))
}
```

（颜色资源名以页面内既有用法为准，缺资源则改用页面内已有的次要背景/文字色。）

- [ ] **Step 4: 备课管线维度同步**

- `utils/LessonPlannerValidation.ets` L36 合法维度数组 + `'math_number_sense'`、`'math_word_problem'`
- `utils/LessonPlanPromptUtils.ets` L67 维度清单 + 同样 2 项；L135 进阶表加 2 行：
  - `math_number_sense`：L1 分与合 → L2 凑十朋友 → L3 拆 10 → L4 灵活拆 → L5 多种拆法
  - `math_word_problem`：L1 听题摆图 → L2 看图列式 → L3 加减应用题 → L4 两步题 → L5 自编题
- `LessonPlannerBaseline.ets` CORE_DIMS **不动**（4 核心默认维度不变）

- [ ] **Step 5: 写画像兼容测试**

若 parseProfile 可直接调用（实例方法仅依赖已加载状态），将解析逻辑抽为模块级纯函数 `parseProfileJson(json: string): ChildKnowledgeProfile`（原 parseProfile 改为调用它），测试针对纯函数：

```typescript
import { describe, it, expect } from '@ohos/hypium'
import { parseProfileJson } from '../../../../main/ets/services/ChildProfileService'

export default function childProfileParseTest() {
  describe('childProfileParse', () => {
    it('旧JSON_24维无新字段_兼容', 0, () => {
      const old: Record<string, Object> = {}
      const dim: Record<string, Object> = {}
      dim['level'] = 2
      dim['lastAssessed'] = 0
      dim['notes'] = '会凑十'
      const skills: Record<string, Object> = {}
      skills['math_addition'] = dim
      old['skills'] = skills
      old['strengths'] = []
      old['weaknesses'] = []
      const p = parseProfileJson(JSON.stringify(old))
      expect(p.skills['math_number_sense'] !== undefined).assertTrue()
      expect(p.skills['math_word_problem'] !== undefined).assertTrue()
      expect(p.skills['math_addition'].strategy === '').assertTrue()
      expect(p.skills['math_addition'].misconceptions === '').assertTrue()
      expect(p.skills['math_addition'].notes === '会凑十').assertTrue()
      expect(p.skills['math_addition'].level === 2).assertTrue()
    })
    it('新JSON_新字段透传', 0, () => {
      const raw: Record<string, Object> = {}
      const dim: Record<string, Object> = {}
      dim['level'] = 3
      dim['lastAssessed'] = 0
      dim['notes'] = ''
      dim['strategy'] = '凑十'
      dim['misconceptions'] = '忘记进位'
      const skills: Record<string, Object> = {}
      skills['math_addition'] = dim
      raw['skills'] = skills
      raw['strengths'] = []
      raw['weaknesses'] = []
      const p = parseProfileJson(JSON.stringify(raw))
      expect(p.skills['math_addition'].strategy === '凑十').assertTrue()
      expect(p.skills['math_addition'].misconceptions === '忘记进位').assertTrue()
    })
  })
}
```

（若 parseProfile 强依赖 preferences 上下文无法抽纯函数，则此测试文件跳过创建，兼容性转由 Task 11 真机清单第 5 条人工验证——二选一，不要硬造 hook。）

- [ ] **Step 6: 构建验证 + Commit**

Run: 同 Global Constraints 的 assembleHap 命令。Expected: BUILD SUCCESSFUL

```bash
git add entry/src/main/ets/services/ChildProfileService.ets entry/src/main/ets/config/BuiltinTools.ets entry/src/main/ets/pages/LearningProfilePage.ets entry/src/main/ets/utils/LessonPlannerValidation.ets entry/src/main/ets/utils/LessonPlanPromptUtils.ets
git commit -m "feat(math-teach): extend child profile with 2 math dims + strategy/misconceptions fields"
```

---

### Task 4: BuiltinTools math_teach 注册

**Files:**
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`（import 区、MathQuizExecutor 附近 L1440、createMathQuizToolDefinition 附近 L1461、register block L2870-2879、getBuiltinToolIds L3020-3022）

**Interfaces:**
- Consumes: Task 1 的 `MATH_TEACH_TOOL_ID`
- Produces: 注册中心内名为 `math_teach`（展示名「数学讲解板」）的内置工具；Task 5 的 dispatch 依赖其已注册身份

- [ ] **Step 1: import MATH_TEACH_TOOL_ID**

在 import 块的 `MATH_QUIZ_TOOL_ID` 之后加 `MATH_TEACH_TOOL_ID`（与 Task 1 产出的常量同源）。

- [ ] **Step 2: MathTeachExecutor stub（放 MathQuizExecutor 附近）**

```typescript
class MathTeachExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    // math_teach 真实交互在 ToolExecutionService.handleMathTeach 特殊路径；
    // 此 executor 仅注册兜底（正常不会走到）。
    return '{"mode":"","skill_key":"","stage":"presentation","completed":false,"interactions":0}'
  }
}
```

- [ ] **Step 3: createMathTeachToolConfig（放 createMathQuizToolConfig 附近，同构）**

镜像 `createMathQuizToolConfig()`（L1563-1577）的 `new ToolConfig(...)` 参数列，仅改：第 2 参（toolId）→ `MATH_TEACH_TOOL_ID`、第 3 参（显示名）→ `'数学讲解板'`、第 4 参（描述）→ `'先摆一摆再讲算理的交互教具讲解板, 小朋友在讲解板上动手操作。'`。其余参数（null / true / false / ToolSourceType.BUILTIN / 'builtin' / toolId / '内置工具' / ToolPermissionLevel.READ）与 math_quiz 完全一致。

- [ ] **Step 4: createMathTeachToolDefinition（rawSchemaJson，描述全用「」）**

```typescript
function createMathTeachToolDefinition(): string {
  const rawSchemaJson: string = `{
    "name": "math_teach",
    "description": "数学讲解板：先摆一摆再讲算理的交互教具。孩子先在讲解板上动手操作看懂算理，之后你再出操练题。八种 mode 八选一，每种 mode 有专属参数。调用前必须先 child_profile(action:read) 读画像，difficulty 与对应 skill_key 的画像等级偏差不超过 1 级。讲解完成后孩子会按「我学会了」回传 {mode, skill_key, stage, completed, interactions}，收到回执后按五步课协议继续出操练题（math_quiz）。⚠️ 严禁连续出题不讲解；⚠️ 严禁讲解参数与算理矛盾（声明凑十却出不用凑十的题）；⚠️ 严禁在 ten_frame/number_line 里讲不进位加法（和必须大于 10 才用这两块板）。",
    "inputSchema": {
      "type": "object",
      "properties": {
        "mode": {"type": "string", "enum": ["number_bond","number_line","ten_frame","place_value","balance","shape","clock","bar_model"], "description": "讲解板类型八选一。number_bond 数的分与合（skill_key 配 math_number_sense）/ number_line 数轴凑十跳（math_addition）/ ten_frame 十格阵凑十（math_addition）/ place_value 小棒数位捆十（math_counting）/ balance 天平比大小（math_comparison）/ shape 图形数边角（math_shapes）/ clock 时钟整点半点（math_time）/ bar_model 应用题图解（math_word_problem）"},
        "stage": {"type": "string", "enum": ["warm_up","presentation","practice","production","review"], "description": "五步课当前环节标签，缺省 presentation。只影响卡片头部显示，不影响玩法"},
        "difficulty": {"type": "number", "description": "难度 1-5 整数，须与画像等级偏差不超过 1；画像该维度 level 为 0（未评估）时可自选"},
        "concept": {"type": "string", "description": "给孩子看的一句话知识点标题，如「凑十法：先凑成 10 再加」。bar_model 模式下此参数兼作应用题题干，如「小明有 9 个苹果，妈妈又给了 5 个，一共几个？」"},
        "skill_key": {"type": "string", "description": "对应画像维度，与 mode 的映射见 mode 描述。用于难度校验与画像更新提示"},
        "total": {"type": "number", "description": "number_bond 专用：分成两部分的合数，2-20 整数"},
        "start": {"type": "number", "description": "number_line 专用：数轴起点，6-9 整数（保证能先跳到 10）"},
        "step": {"type": "number", "description": "number_line 专用：从 start 跳的总步数，1-10 整数。start+step 必须大于 10（凑十只讲进位加法）且不超过 20"},
        "a": {"type": "number", "description": "ten_frame 专用：十格阵里已有的个数，5-9 整数"},
        "b": {"type": "number", "description": "ten_frame 专用：框外散点个数，1-10 整数。a+b 必须大于 10 且不超过 20（⚠️ 严禁 a+b 不超过 10 时使用 ten_frame）"},
        "tens": {"type": "number", "description": "place_value 专用：十位捆数，0-8 整数"},
        "ones": {"type": "number", "description": "place_value 专用：个位散棒数，0-9 整数，板内可调到 10 触发捆扎；tens 与 ones 不同时为 0"},
        "left": {"type": "number", "description": "balance 专用：天平左盘数，1-20 整数"},
        "right": {"type": "number", "description": "balance 专用：天平右盘数，1-20 整数"},
        "focus": {"type": "string", "enum": ["circle","square","triangle","rectangle"], "description": "shape 专用：重点认识的图形"},
        "hour": {"type": "number", "description": "clock 专用：时针位置，1-12 整数"},
        "minute": {"type": "number", "description": "clock 专用：分针位置，只能 0（整点）或 30（半点）"},
        "part_a": {"type": "number", "description": "bar_model 专用：应用题第一部分数量，1-9 整数"},
        "part_b": {"type": "number", "description": "bar_model 专用：应用题第二部分数量，1-9 整数"}
      },
      "required": ["mode", "difficulty", "concept", "skill_key"]
    }
  }`
  return rawSchemaJson
}
```

- [ ] **Step 5: 注册块 + getBuiltinToolIds**

register block 在 math_quiz 块（L2870-2879）之后插入：

```typescript
if (!registry.isToolRegistered(MATH_TEACH_TOOL_ID)) {
  const mathTeachTool = new RegisteredTool(
    MATH_TEACH_TOOL_ID,
    createMathTeachToolConfig(),
    createMathTeachToolDefinition(),
    new MathTeachExecutor()
  )
  registry.registerTool(mathTeachTool)
  registeredNow += 1
}
```

`getBuiltinToolIds()`（L3020-3022）数组中 `MATH_QUIZ_TOOL_ID` 之后插入 `MATH_TEACH_TOOL_ID`。

- [ ] **Step 6: JSON.parse gauntlet（全文件所有 rawSchemaJson）**

```bash
node -e "const s=require('fs').readFileSync('entry/src/main/ets/config/BuiltinTools.ets','utf-8');const re=/const rawSchemaJson: string = \`([\s\S]*?)\`/g;let m,n=0,bad=0;while((m=re.exec(s))!==null){n++;try{JSON.parse(m[1])}catch(e){bad++;console.log('SCHEMA '+n+' FAIL: '+e.message)}}console.log('schemas: '+n+', failures: '+bad);process.exit(bad>0?1:0)"
```

Expected: `failures: 0`。若文件内个别 schema 用了别的变量名导致 regex 漏检，先 `grep -c "rawSchemaJson" entry/src/main/ets/config/BuiltinTools.ets` 对齐数量再补 regex。

- [ ] **Step 7: 构建验证 + Commit**

Run: assembleHap。Expected: BUILD SUCCESSFUL

```bash
git add entry/src/main/ets/config/BuiltinTools.ets
git commit -m "feat(math-teach): register math_teach builtin tool with mode-specific schema"
```

---

### Task 5: ToolExecutionService 特殊路径（handleMathTeach）

**Files:**
- Modify: `entry/src/main/ets/services/ToolExecutionService.ets`（import 区、handleMathQuiz L571-658 之后、dispatch 链 L1892-1895）

**Interfaces:**
- Consumes: Task 1 `MATH_TEACH_TOOL_ID` / `isMathTeachFunctionName`；Task 2 `validateMathTeachArgs`；Task 4 注册身份
- Produces: math_teach 完整 pending→回执链路；回执 payload `{mode, skill_key, stage, completed, interactions}`

- [ ] **Step 1: import**

```typescript
import { MATH_TEACH_TOOL_ID, isMathTeachFunctionName } from '../utils/SearchToolIdentityUtils'
import { validateMathTeachArgs } from '../utils/MathTeachValidation'
import { getChildProfileService } from './ChildProfileService'
```

（getChildProfileService 的实际导出名以 ChildProfileService.ets 头部为准——它是单例，取其既有获取函数/getInstance 形式；与 ToolExecutionService 同在 services/ 目录，故路径为 `./ChildProfileService`。）

- [ ] **Step 2: handleMathTeach（放在 handleMathQuiz 之后，逐段镜像 L571-658）**

```typescript
// math_teach 特殊路径: 与 math_quiz 同款 pending 挂起, 等待 MathTeachCard 完成。
// 讲解不授星（spec §0 决策）——本函数严禁调用 recordStarEvent。
private async handleMathTeach(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult> {
  toolCall.toolId = MATH_TEACH_TOOL_ID
  if (toolCall.displayName.trim() === '') {
    toolCall.displayName = '数学讲解板'
  }
  toolCall.sourceType = ToolSourceType.BUILTIN
  if (toolCall.sourceLabel.trim() === '') {
    toolCall.sourceLabel = '内置工具'
  }
  toolCall.permissionLevel = ToolPermissionLevel.READ

  // 读画像各维 level 注入难度校验（规则 4）；读取失败降级 null 跳过，不阻塞讲解
  let profileLevels: Record<string, number> | null = null
  try {
    const profile = await getChildProfileService().getProfile()
    const levels: Record<string, number> = {}
    const keys: string[] = Object.keys(profile.skills)
    for (let i = 0; i < keys.length; i++) {
      levels[keys[i]] = profile.skills[keys[i]].level
    }
    profileLevels = levels
  } catch (_e) {
    profileLevels = null
  }

  const teachValidation = validateMathTeachArgs(toolCall.arguments, profileLevels)
  if (!teachValidation.ok) {
    console.warn('ToolExecutionService', `math_teach validation failed: ${teachValidation.error}`)
    toolCall.approvalState = 'denied'
    return new ToolResult(
      toolCall.id,
      JSON.stringify({
        error: 'validation_failed',
        message: teachValidation.error,
        should_retry: true
      }),
      true,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  toolCall.approvalState = 'pending'

  let answerJson: string | null = null
  try {
    answerJson = await new Promise<string | null>((resolve) => {
      const existing = this.pendingAnswers.get(toolCall.id)
      if (existing !== undefined) {
        existing.resolve(null)
        this.pendingAnswers.delete(toolCall.id)
      }
      const snapshot = this.buildAskUserSnapshot(toolCall, context)
      snapshot.kind = PendingToolInteractionKind.ASK_USER
      snapshot.toolId = MATH_TEACH_TOOL_ID
      this.pendingAnswers.set(toolCall.id, new PendingToolAnswerRuntime(snapshot, resolve))
      this.publishPendingInteractionChanged()
    })
  } catch (error) {
    console.error('ToolExecutionService', `math_teach answer callback failed: ${JSON.stringify(error)}`)
    toolCall.approvalState = 'denied'
    return new ToolResult(
      toolCall.id,
      JSON.stringify({ error: `math_teach 失败: ${JSON.stringify(error)}`, cancelled: true }),
      true,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  if (this.isCancelled()) {
    console.info('ToolExecutionService', 'math_teach cancelled by external stop')
    toolCall.approvalState = 'denied'
    return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
  }

  if (answerJson === null) {
    toolCall.approvalState = 'denied'
    return new ToolResult(
      toolCall.id,
      JSON.stringify({ cancelled: true, error: '小朋友未完成本次讲解' }),
      true,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  toolCall.approvalState = 'answered'
  toolCall.approvalReason = answerJson
  console.info('ToolExecutionService', `math_teach answered: ${toolCall.id}`)
  // 注意：与 handleMathQuiz 不同，这里不调 recordStarEvent（讲解不授星）
  return new ToolResult(
    toolCall.id,
    answerJson,
    false,
    toolCall.displayName,
    toolCall.sourceLabel
  )
}
```

- [ ] **Step 3: dispatch 分支（math_quiz 分支之后、resolveToolId 兜底之前）**

在 L1892-1895 的 `if (isMathQuizFunctionName(normalizedFunctionName)) { return await this.handleMathQuiz(toolCall, context) }` 之后插入：

```typescript
if (isMathTeachFunctionName(normalizedFunctionName)) {
  return await this.handleMathTeach(toolCall, context)
}
```

- [ ] **Step 4: 验证无授星 + 构建**

```bash
grep -A 90 "private async handleMathTeach" entry/src/main/ets/services/ToolExecutionService.ets | grep -c recordStarEvent
```
Expected: `0`

Run: assembleHap。Expected: BUILD SUCCESSFUL

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/services/ToolExecutionService.ets
git commit -m "feat(math-teach): add handleMathTeach special path with profile-aware validation (no stars)"
```

---

### Task 6: 共享步进器 + 前四块板（number_bond / number_line / ten_frame / place_value）

**Files:**
- Create: `entry/src/main/ets/components/mathTeach/TeachStepper.ets`
- Create: `entry/src/main/ets/components/mathTeach/NumberBondBoard.ets`
- Create: `entry/src/main/ets/components/mathTeach/NumberLineBoard.ets`
- Create: `entry/src/main/ets/components/mathTeach/TenFrameBoard.ets`
- Create: `entry/src/main/ets/components/mathTeach/PlaceValueBoard.ets`

**Interfaces:**
- Consumes: Task 1 的 `numberLineHops` / `bondSplit` / `canBundle`；KidsBrandTokens（`KIDS_MATH` L47 淡底用 / `KIDS_MATH_INK` L49 文字用 / `KIDS_ACCENT` / `KIDS_MUTED` / `KIDS_BORDER`，以文件内命名为准）；`withColorAlpha`（`utils/ColorAlphaUtils.ets`）
- Produces（Task 8 依赖的精确 props）: 每板均为
  ```
  NumberBondBoard({ total: number, readonly: boolean, onInteract: () => void })
  NumberLineBoard({ start: number, step: number, readonly: boolean, onInteract: () => void })
  TenFrameBoard({ a: number, b: number, readonly: boolean, onInteract: () => void })
  PlaceValueBoard({ tens: number, ones: number, readonly: boolean, onInteract: () => void })
  ```
- 板公共约定：`aboutToAppear` 用初始参数重置 @Local；`readonly=true` 时隐藏全部控制区（已答回看态）；关键交互真实变化时才调 `onInteract`。

- [ ] **Step 1: TeachStepper（共享 ± 步进器，44vp 触控目标）**

```typescript
import { KIDS_MATH, KIDS_MATH_INK, KIDS_MUTED } from '../kids/KidsBrandTokens'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'

@ComponentV2
export struct TeachStepper {
  @Param label: string = ''
  @Param value: number = 0
  @Param minValue: number = 0
  @Param maxValue: number = 20
  @Event onChange: (v: number) => void = (_v: number) => {}

  private tap(delta: number): void {
    const next: number = Math.min(this.maxValue, Math.max(this.minValue, this.value + delta))
    if (next !== this.value) {
      this.onChange(next)
    }
  }

  build() {
    Row({ space: 10 }) {
      Text(this.label).fontSize(14).fontColor(KIDS_MUTED)
      Button('-')
        .width(44).height(44)
        .type(ButtonType.Capsule)
        .backgroundColor(withColorAlpha(KIDS_MATH, '26')).fontColor(KIDS_MATH_INK).fontSize(20)
        .onClick(() => { this.tap(-1) })
      Text(this.value.toString())
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
        .minWidth(28).textAlign(TextAlign.Center)
      Button('+')
        .width(44).height(44)
        .type(ButtonType.Capsule)
        .backgroundColor(withColorAlpha(KIDS_MATH, '26')).fontColor(KIDS_MATH_INK).fontSize(20)
        .onClick(() => { this.tap(1) })
    }
    .padding(4)
    .borderRadius(24)
    .backgroundColor(withColorAlpha(KIDS_MATH, '15'))
    .alignItems(VerticalAlign.Center)
  }
}
```

（用真 Button 而非可点击 Row——MEMORY：Scroll 内可点击 Row 会被吞点击。）

- [ ] **Step 2: NumberBondBoard**

```typescript
import { bondSplit } from '../../utils/MathTeachBoards'
import { KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED } from '../kids/KidsBrandTokens'
import { TeachStepper } from './TeachStepper'

@ComponentV2
export struct NumberBondBoard {
  @Param total: number = 9
  @Param readonly: boolean = false
  @Local left: number = 4
  @Event onInteract: () => void = () => {}

  aboutToAppear(): void {
    this.left = Math.floor(this.total / 2)
  }

  private right(): number {
    return bondSplit(this.total, this.left)
  }

  private seq(n: number): number[] {
    const arr: number[] = []
    for (let i = 0; i < n; i++) { arr.push(i) }
    return arr
  }

  @Builder
  Dot(color: string) {
    Circle().width(18).height(18).fill(color)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 6 }) {
        ForEach(this.seq(this.left), (i: number) => {
          this.Dot(KIDS_MATH_INK)
        }, (i: number) => 'l' + i.toString())
        ForEach(this.seq(this.right()), (i: number) => {
          this.Dot(KIDS_ACCENT)
        }, (i: number) => 'r' + i.toString())
        if (this.total < 10) {
          Column() {
            Text('+').fontSize(12).fontColor(KIDS_MUTED)
          }
          .width(18).height(18)
          .justifyContent(FlexAlign.Center)
          .border({ width: 1.5, style: BorderStyle.Dashed, color: KIDS_MUTED, radius: 9 })
        }
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')

      Text(this.left + ' 和 ' + this.right() + ' 合起来是 ' + this.total)
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
      if (this.total < 10) {
        Text(this.total + ' 再和 ' + (10 - this.total) + ' 做朋友，就能凑成十')
          .fontSize(13).fontColor(KIDS_MUTED)
      }

      if (!this.readonly) {
        TeachStepper({
          label: '左边圆点', value: this.left, minValue: 0, maxValue: this.total,
          onChange: (v: number): void => {
            if (v !== this.left) {
              this.left = v
              this.onInteract()
            }
          }
        })
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
```

- [ ] **Step 3: NumberLineBoard（280vp 固定舞台 + 两段弧线 staging）**

```typescript
import { numberLineHops, NumberLineHops } from '../../utils/MathTeachBoards'
import { KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED } from '../kids/KidsBrandTokens'

const NL_W: number = 280
const NL_X0: number = 14
const NL_GAP: number = (NL_W - 28) / 20
const NL_Y: number = 120

@ComponentV2
export struct NumberLineBoard {
  @Param start: number = 9
  @Param step: number = 5
  @Param readonly: boolean = false
  @Local hopStage: number = 0
  @Event onInteract: () => void = () => {}
  private timerId: number = -1

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId)
      this.timerId = -1
    }
  }

  private hops(): NumberLineHops {
    return numberLineHops(this.start, this.step)
  }

  private x(idx: number): number {
    return NL_X0 + idx * NL_GAP
  }

  private arcPath(fromIdx: number, toIdx: number): string {
    const x0: number = this.x(fromIdx)
    const x1: number = this.x(toIdx)
    const cx: number = (x0 + x1) / 2
    return `M ${x0} ${NL_Y} Q ${cx} 58 ${x1} ${NL_Y}`
  }

  private tokenX(): number {
    if (this.hopStage === 0) { return this.x(this.start) }
    if (this.hopStage === 1) { return this.x(10) }
    return this.x(this.hops().sum)
  }

  private eqText(): string {
    const h: NumberLineHops = this.hops()
    if (this.hopStage === 0) {
      return `${this.start} + ${this.step}：先跳到 10 还差 ${h.firstHop}`
    }
    if (this.hopStage === 1) {
      return `${this.start} + ${h.firstHop} = 10`
    }
    return `${this.start} + ${h.firstHop} = 10，10 + ${h.secondHop} = ${h.sum}`
  }

  private tickSeq(): number[] {
    const arr: number[] = []
    for (let i = 0; i <= 20; i++) { arr.push(i) }
    return arr
  }

  private startHop(): void {
    if (this.readonly || this.hopStage > 0) { return }
    this.onInteract()
    this.hopStage = 1
    this.timerId = setTimeout(() => {
      this.hopStage = 2
    }, 600)
  }

  build() {
    Column({ space: 12 }) {
      Stack() {
        Rect({ width: NL_W - 28, height: 2 }).fill(KIDS_MUTED)
          .position({ x: NL_X0, y: NL_Y })
        ForEach(this.tickSeq(), (i: number) => {
          Column() {
            if (i % 5 === 0) {
              Text(i.toString()).fontSize(10).fontColor(KIDS_MUTED)
            }
            Rect({ width: i % 5 === 0 ? 2 : 1, height: i % 5 === 0 ? 10 : 6 })
              .fill(i === 10 ? KIDS_ACCENT : KIDS_MUTED)
          }
          .position({ x: this.x(i) - 1, y: NL_Y - (i % 5 === 0 ? 26 : 12) })
        }, (i: number) => 't' + i.toString())

        if (this.hopStage >= 1) {
          Path().commands(this.arcPath(this.start, 10))
            .stroke(KIDS_MATH_INK).strokeWidth(2.5).fillOpacity(0)
            .width(NL_W).height(170)
          Text('+' + this.hops().firstHop)
            .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
            .position({ x: (this.x(this.start) + this.x(10)) / 2 - 8, y: 66 })
        }
        if (this.hopStage >= 2) {
          Path().commands(this.arcPath(10, this.hops().sum))
            .stroke(KIDS_ACCENT).strokeWidth(2.5).fillOpacity(0)
            .width(NL_W).height(170)
          Text('+' + this.hops().secondHop)
            .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_ACCENT)
            .position({ x: (this.x(10) + this.x(this.hops().sum)) / 2 - 10, y: 66 })
        }

        Rect({ width: 22, height: 22 }).fill(KIDS_MATH_INK).borderRadius(6)
          .position({ x: this.tokenX() - 11, y: NL_Y + 12 })
          .animation({ duration: 500, curve: Curve.EaseInOut })
      }
      .width(NL_W).height(170)

      Text(this.eqText())
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
        .textAlign(TextAlign.Center).width('100%')

      if (this.hopStage === 0 && !this.readonly) {
        Button('凑十跳')
          .width(140).height(44)
          .backgroundColor(KIDS_MATH_INK).fontSize(15)
          .onClick(() => { this.startHop() })
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
```

- [ ] **Step 4: TenFrameBoard（借一个进框 + 飞入 transition）**

```typescript
import { KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED, KIDS_BORDER } from '../kids/KidsBrandTokens'

@ComponentV2
export struct TenFrameBoard {
  @Param a: number = 9
  @Param b: number = 5
  @Param readonly: boolean = false
  @Local frameDots: number = 0
  @Local outside: number = 0
  @Event onInteract: () => void = () => {}

  aboutToAppear(): void {
    this.frameDots = this.a
    this.outside = this.b
  }

  private seq(n: number): number[] {
    const arr: number[] = []
    for (let i = 0; i < n; i++) { arr.push(i) }
    return arr
  }

  private borrow(): void {
    if (this.readonly || this.outside < 1 || this.frameDots >= 10) { return }
    this.onInteract()
    this.frameDots += 1
    this.outside -= 1
  }

  private eqText(): string {
    if (this.frameDots < 10) {
      return `${this.a} + ${this.b}：框里还差 ${10 - this.frameDots} 个凑满 10`
    }
    return `${this.a} + ${10 - this.a} = 10，10 + ${this.outside} = ${10 + this.outside}`
  }

  @Builder
  Cell(occupied: boolean) {
    Stack() {
      if (occupied) {
        Circle().width(26).height(26).fill(KIDS_MATH_INK)
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.2, y: 0.2 }))
            .animation({ duration: 300, curve: Curve.EaseOut }))
      }
    }
    .width(40).height(40)
    .border({ width: 1.5, style: BorderStyle.Dashed, color: KIDS_BORDER, radius: 8 })
  }

  build() {
    Column({ space: 12 }) {
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          ForEach(this.seq(5), (i: number) => {
            this.Cell(i < this.frameDots)
          }, (i: number) => 'c1_' + i.toString())
        }
        Row({ space: 6 }) {
          ForEach(this.seq(5), (i: number) => {
            this.Cell(i + 5 < this.frameDots)
          }, (i: number) => 'c2_' + i.toString())
        }
      }

      Row({ space: 6 }) {
        ForEach(this.seq(this.outside), (i: number) => {
          Circle().width(16).height(16).fill(KIDS_ACCENT)
        }, (i: number) => 'o' + i.toString())
        Text(this.outside > 0 ? '框外还有 ' + this.outside + ' 个' : '框外空了')
          .fontSize(12).fontColor(KIDS_MUTED)
      }

      Text(this.eqText())
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
        .textAlign(TextAlign.Center).width('100%')

      if (!this.readonly && this.frameDots < 10) {
        Button('借一个进框')
          .width(140).height(44)
          .backgroundColor(KIDS_MATH_INK).fontSize(15)
          .onClick(() => { this.borrow() })
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
```

- [ ] **Step 5: PlaceValueBoard（满十捆一捆）**

```typescript
import { canBundle } from '../../utils/MathTeachBoards'
import { KIDS_MATH, KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED } from '../kids/KidsBrandTokens'
import { TeachStepper } from './TeachStepper'

@ComponentV2
export struct PlaceValueBoard {
  @Param tens: number = 1
  @Param ones: number = 7
  @Param readonly: boolean = false
  @Local curTens: number = 0
  @Local curOnes: number = 0
  @Event onInteract: () => void = () => {}

  aboutToAppear(): void {
    this.curTens = this.tens
    this.curOnes = this.ones
  }

  private seq(n: number): number[] {
    const arr: number[] = []
    for (let i = 0; i < n; i++) { arr.push(i) }
    return arr
  }

  private bundle(): void {
    if (this.readonly || !canBundle(this.curOnes)) { return }
    this.onInteract()
    this.curTens += 1
    this.curOnes -= 10
  }

  @Builder
  Bundle() {
    Stack() {
      Rect({ width: 36, height: 46 }).fill(KIDS_MATH).borderRadius(6)
      Text('10').fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.White)
    }
  }

  @Builder
  Stick() {
    Rect({ width: 5, height: 46 }).fill(KIDS_MATH_INK).borderRadius(2)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 28 }) {
        Column({ space: 8 }) {
          Text('十位 · 捆').fontSize(12).fontColor(KIDS_MUTED)
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            ForEach(this.seq(this.curTens), (i: number) => {
              this.Bundle()
            }, (i: number) => 'b' + i.toString())
          }.width(160)
          Text(this.curTens + ' 捆').fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
        }
        .alignItems(HorizontalAlign.Center)

        Column({ space: 8 }) {
          Text('个位 · 根').fontSize(12).fontColor(KIDS_MUTED)
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            ForEach(this.seq(this.curOnes), (i: number) => {
              this.Stick()
            }, (i: number) => 's' + i.toString())
          }.width(160)
          Text(this.curOnes + ' 根').fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
        }
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      if (canBundle(this.curOnes) && !this.readonly) {
        Button('10 根捆成一捆')
          .width(160).height(44)
          .backgroundColor(KIDS_ACCENT).fontSize(15)
          .onClick(() => { this.bundle() })
      }

      Text(this.curTens + ' 捆 ' + this.curOnes + ' 根 = ' + (this.curTens * 10 + this.curOnes))
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)

      if (!this.readonly) {
        TeachStepper({
          label: '个位加一根', value: this.curOnes, minValue: 0, maxValue: 19,
          onChange: (v: number): void => {
            if (v !== this.curOnes) {
              this.curOnes = v
              this.onInteract()
            }
          }
        })
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
```

- [ ] **Step 6: 构建验证 + Commit**

Run: assembleHap。Expected: BUILD SUCCESSFUL

```bash
git add entry/src/main/ets/components/mathTeach/
git commit -m "feat(math-teach): add TeachStepper + number_bond/number_line/ten_frame/place_value boards"
```

---

### Task 7: 后四块板（balance / shape / clock / bar_model）

**Files:**
- Create: `entry/src/main/ets/components/mathTeach/BalanceBoard.ets`
- Create: `entry/src/main/ets/components/mathTeach/ShapeBoard.ets`
- Create: `entry/src/main/ets/components/mathTeach/ClockBoard.ets`
- Create: `entry/src/main/ets/components/mathTeach/BarModelBoard.ets`

**Interfaces:**
- Consumes: Task 1 的 `balanceTilt` / `clockAngles` / `barPercents`；Task 6 的板公共约定（readonly/onInteract）
- Produces（Task 8 依赖的精确 props）:
  ```
  BalanceBoard({ left: number, right: number, readonly: boolean, onInteract: () => void })
  ShapeBoard({ focus: string, readonly: boolean, onInteract: () => void })
  ClockBoard({ hour: number, minute: number, readonly: boolean, onInteract: () => void })
  BarModelBoard({ partA: number, partB: number, readonly: boolean, onInteract: () => void })
  ```

- [ ] **Step 1: BalanceBoard（梁倾斜 spring 动画）**

```typescript
import { balanceTilt } from '../../utils/MathTeachBoards'
import { curves } from '@kit.ArkUI'
import { KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED } from '../kids/KidsBrandTokens'
import { TeachStepper } from './TeachStepper'

@ComponentV2
export struct BalanceBoard {
  @Param left: number = 9
  @Param right: number = 5
  @Param readonly: boolean = false
  @Local curLeft: number = 0
  @Local curRight: number = 0
  @Event onInteract: () => void = () => {}

  aboutToAppear(): void {
    this.curLeft = this.left
    this.curRight = this.right
  }

  private tilt(): number {
    return balanceTilt(this.curLeft, this.curRight)
  }

  private symbol(): string {
    if (this.curLeft > this.curRight) { return '>' }
    if (this.curLeft < this.curRight) { return '<' }
    return '='
  }

  @Builder
  Pan(count: number, color: string) {
    Column({ space: 4 }) {
      Text(count + ' 个').fontSize(13).fontWeight(FontWeight.Bold).fontColor(color)
      Column()
        .width(56).height(4).borderRadius(2).backgroundColor(color)
    }
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column({ space: 12 }) {
      Stack() {
        Polygon({ width: 28, height: 20 })
          .points([[14, 0], [28, 20], [0, 20]])
          .fill(KIDS_MUTED)
          .position({ x: 106, y: 78 })

        Row() {
          this.Pan(this.curLeft, KIDS_MATH_INK)
          Rect({ width: 130, height: 5 }).fill(KIDS_MATH_INK).borderRadius(2)
          this.Pan(this.curRight, KIDS_ACCENT)
        }
        .alignItems(VerticalAlign.Center)
        .rotate({ angle: this.tilt(), centerX: '50%', centerY: '50%' })
        .animation({ curve: curves.springMotion(0.35, 0.85) })
      }
      .width(240).height(110)

      Text(this.curLeft + ' ' + this.symbol() + ' ' + this.curRight)
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)

      if (!this.readonly) {
        Column({ space: 8 }) {
          TeachStepper({
            label: '左盘', value: this.curLeft, minValue: 1, maxValue: 20,
            onChange: (v: number): void => {
              if (v !== this.curLeft) { this.curLeft = v; this.onInteract() }
            }
          })
          TeachStepper({
            label: '右盘', value: this.curRight, minValue: 1, maxValue: 20,
            onChange: (v: number): void => {
              if (v !== this.curRight) { this.curRight = v; this.onInteract() }
            }
          })
        }
        .alignItems(HorizontalAlign.Center)
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
```

- [ ] **Step 2: ShapeBoard（四形 tile 点选，圆形 0 边 0 角对比）**

```typescript
import { KIDS_MATH_INK, KIDS_MUTED, KIDS_BORDER } from '../kids/KidsBrandTokens'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'

interface ShapeTileInfo {
  key: string
  name: string
  sides: number
  corners: number
}

const SHAPE_TILES: ShapeTileInfo[] = [
  { key: 'circle', name: '圆形', sides: 0, corners: 0 },
  { key: 'square', name: '正方形', sides: 4, corners: 4 },
  { key: 'triangle', name: '三角形', sides: 3, corners: 3 },
  { key: 'rectangle', name: '长方形', sides: 4, corners: 4 }
]

@ComponentV2
export struct ShapeBoard {
  @Param focus: string = 'circle'
  @Param readonly: boolean = false
  @Local selectedKey: string = ''
  @Event onInteract: () => void = () => {}

  aboutToAppear(): void {
    this.selectedKey = this.focus
  }

  private infoOf(key: string): ShapeTileInfo {
    for (let i = 0; i < SHAPE_TILES.length; i++) {
      if (SHAPE_TILES[i].key === key) { return SHAPE_TILES[i] }
    }
    return SHAPE_TILES[0]
  }

  private statText(): string {
    const info: ShapeTileInfo = this.infoOf(this.selectedKey)
    return info.name + '：' + info.sides + ' 条边、' + info.corners + ' 个角'
  }

  private isCircleSelected(): boolean {
    return this.selectedKey === 'circle'
  }

  @Builder
  Tile(info: ShapeTileInfo) {
    Column({ space: 6 }) {
      if (info.key === 'circle') {
        Circle().width(46).height(46)
          .fill(withColorAlpha(KIDS_MATH_INK, '22')).stroke(KIDS_MATH_INK).strokeWidth(2)
      } else if (info.key === 'square') {
        Rect().width(42).height(42)
          .fill(withColorAlpha(KIDS_MATH_INK, '22')).stroke(KIDS_MATH_INK).strokeWidth(2).radius(4)
      } else if (info.key === 'triangle') {
        Polygon().width(48).height(44).points([[24, 2], [46, 42], [2, 42]])
          .fill(withColorAlpha(KIDS_MATH_INK, '22')).stroke(KIDS_MATH_INK).strokeWidth(2)
      } else {
        Rect().width(56).height(34)
          .fill(withColorAlpha(KIDS_MATH_INK, '22')).stroke(KIDS_MATH_INK).strokeWidth(2).radius(4)
      }
      Text(info.name).fontSize(12).fontColor(KIDS_MATH_INK)
    }
    .width(84).height(84)
    .justifyContent(FlexAlign.Center)
    .border({
      width: this.selectedKey === info.key ? 2.5 : 1.5,
      style: BorderStyle.Dashed,
      color: this.selectedKey === info.key ? KIDS_MATH_INK : KIDS_BORDER,
      radius: 12
    })
    .onClick(() => {
      if (this.readonly || this.selectedKey === info.key) { return }
      this.selectedKey = info.key
      this.onInteract()
    })
  }

  build() {
    Column({ space: 12 }) {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(SHAPE_TILES, (info: ShapeTileInfo) => {
          this.Tile(info)
        }, (info: ShapeTileInfo) => info.key)
      }.width('100%')

      Text(this.statText())
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)

      if (this.isCircleSelected()) {
        Text('圆形没有直边和角，这是它和方、三角最大的不同')
          .fontSize(13).fontColor(KIDS_MUTED)
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
```

- [ ] **Step 3: ClockBoard（指针 Rect + rotate '50%'/'100%'）**

```typescript
import { clockAngles, ClockAngles } from '../../utils/MathTeachBoards'
import { curves } from '@kit.ArkUI'
import { KIDS_MATH_INK, KIDS_ACCENT, KIDS_MATH } from '../kids/KidsBrandTokens'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'

@ComponentV2
export struct ClockBoard {
  @Param hour: number = 9
  @Param minute: number = 30
  @Param readonly: boolean = false
  @Local curH: number = 9
  @Local curM: number = 0
  @Event onInteract: () => void = () => {}

  aboutToAppear(): void {
    this.curH = this.hour
    this.curM = this.minute
  }

  private angles(): ClockAngles {
    return clockAngles(this.curH, this.curM)
  }

  private hourSeq(): number[] {
    const arr: number[] = []
    for (let h = 1; h <= 12; h++) { arr.push(h) }
    return arr
  }

  private numX(h: number): number {
    const rad: number = (h * 30 - 90) * Math.PI / 180
    return 84 + 60 * Math.cos(rad) - 8
  }

  private numY(h: number): number {
    const rad: number = (h * 30 - 90) * Math.PI / 180
    return 84 + 60 * Math.sin(rad) - 9
  }

  private stepHour(delta: number): void {
    if (this.readonly) { return }
    const next: number = delta > 0 ? this.curH % 12 + 1 : (this.curH + 10) % 12 + 1
    if (next !== this.curH) {
      this.curH = next
      this.onInteract()
    }
  }

  private setHalf(half: boolean): void {
    if (this.readonly) { return }
    const m: number = half ? 30 : 0
    if (m !== this.curM) {
      this.curM = m
      this.onInteract()
    }
  }

  private timeText(): string {
    if (this.curM === 0) {
      return this.curH + ' 时整 · 短针指 ' + this.curH + '、长针指 12'
    }
    return this.curH + ' 时 30 分（半点）· 短针在两个数中间、长针指 6'
  }

  build() {
    Column({ space: 12 }) {
      Stack() {
        Circle().width(168).height(168).fill(Color.White).stroke(KIDS_MATH_INK).strokeWidth(3)
        ForEach(this.hourSeq(), (h: number) => {
          Text(h.toString()).fontSize(13).fontWeight(FontWeight.Medium).fontColor(KIDS_MATH_INK)
            .position({ x: this.numX(h), y: this.numY(h) })
        }, (h: number) => 'h' + h.toString())
        Rect({ width: 8, height: 48 }).fill(KIDS_MATH_INK).borderRadius(4)
          .position({ x: 80, y: 36 })
          .rotate({ angle: this.angles().hourDeg, centerX: '50%', centerY: '100%' })
          .animation({ curve: curves.springMotion(0.35, 0.85) })
        Rect({ width: 6, height: 64 }).fill(KIDS_ACCENT).borderRadius(3)
          .position({ x: 81, y: 20 })
          .rotate({ angle: this.angles().minuteDeg, centerX: '50%', centerY: '100%' })
          .animation({ curve: curves.springMotion(0.35, 0.85) })
        Circle().width(10).height(10).fill(KIDS_MATH_INK).position({ x: 79, y: 79 })
      }
      .width(168).height(168)

      Text(this.timeText())
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
        .textAlign(TextAlign.Center).width('100%')

      if (!this.readonly) {
        Row({ space: 10 }) {
          Button('时 −').width(60).height(40)
            .backgroundColor(withColorAlpha(KIDS_MATH, '26')).fontColor(KIDS_MATH_INK)
            .onClick(() => { this.stepHour(-1) })
          Button('时 +').width(60).height(40)
            .backgroundColor(withColorAlpha(KIDS_MATH, '26')).fontColor(KIDS_MATH_INK)
            .onClick(() => { this.stepHour(1) })
          Button('整点').width(64).height(40)
            .backgroundColor(withColorAlpha(KIDS_MATH, '26')).fontColor(KIDS_MATH_INK)
            .onClick(() => { this.setHalf(false) })
          Button('半点').width(64).height(40)
            .backgroundColor(withColorAlpha(KIDS_MATH, '26')).fontColor(KIDS_MATH_INK)
            .onClick(() => { this.setHalf(true) })
        }
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
```

（指针 rotate 说明：Rect 底边中点在钟心，`centerY:'100%'` 相对自身高度——MEMORY gotcha 的 % = 自身尺寸约定。）

- [ ] **Step 4: BarModelBoard（三行长条 + 宽度过渡动画）**

```typescript
import { barPercents, BarPercents } from '../../utils/MathTeachBoards'
import { KIDS_MATH_INK, KIDS_ACCENT, KIDS_MATH } from '../kids/KidsBrandTokens'
import { TeachStepper } from './TeachStepper'

@ComponentV2
export struct BarModelBoard {
  @Param partA: number = 9
  @Param partB: number = 5
  @Param readonly: boolean = false
  @Local curA: number = 0
  @Local curB: number = 0
  @Event onInteract: () => void = () => {}

  aboutToAppear(): void {
    this.curA = this.partA
    this.curB = this.partB
  }

  private pcts(): BarPercents {
    return barPercents(this.curA, this.curB)
  }

  @Builder
  Bar(label: string, pct: number, color: string) {
    Row() {
      Text(label).fontSize(11).fontColor(Color.White).maxLines(1)
    }
    .width(pct * 2.2)
    .height(30)
    .borderRadius(6)
    .backgroundColor(color)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .animation({ duration: 350, curve: Curve.EaseInOut })
  }

  build() {
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Row() {
          this.Bar('部分 A', this.pcts().aPct, KIDS_MATH_INK)
        }.width('100%')
        Row() {
          this.Bar('部分 B', this.pcts().bPct, KIDS_ACCENT)
        }.width('100%')
        Row() {
          this.Bar('一共 ' + (this.curA + this.curB), 100, KIDS_MATH)
        }.width('100%')
      }
      .width('100%')

      Text(this.curA + ' + ' + this.curB + ' = ' + (this.curA + this.curB) + '：两条长条拼成的全长就是一共')
        .fontSize(14).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
        .textAlign(TextAlign.Center).width('100%')

      if (!this.readonly) {
        Column({ space: 8 }) {
          TeachStepper({
            label: '部分 A', value: this.curA, minValue: 1, maxValue: 9,
            onChange: (v: number): void => {
              if (v !== this.curA) { this.curA = v; this.onInteract() }
            }
          })
          TeachStepper({
            label: '部分 B', value: this.curB, minValue: 1, maxValue: 9,
            onChange: (v: number): void => {
              if (v !== this.curB) { this.curB = v; this.onInteract() }
            }
          })
        }
        .alignItems(HorizontalAlign.Center)
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
```

（concept 题干由 CardShell 的 stem 区展示，板内只用泛化标签「部分 A/B/一共」——spec §4.2。）

- [ ] **Step 5: 构建验证 + Commit**

Run: assembleHap。Expected: BUILD SUCCESSFUL

```bash
git add entry/src/main/ets/components/mathTeach/
git commit -m "feat(math-teach): add balance/shape/clock/bar_model boards"
```

---

### Task 8: MathTeachCard shell（mode 分发 + 完成门 + 回执 + 已答态）

**Files:**
- Create: `entry/src/main/ets/components/MathTeachCard.ets`

**Interfaces:**
- Consumes: Task 6/7 全部 8 板（props 见各任务 Produces）；CardShell（import 路径与调用签名以 `MathQuizCard.ets` L16-18 import 与 L473-490 调用为准）；`ToolCall`（`../models/ChatModels`）；`withColorAlpha`
- Produces:
  - `export interface MathTeachResult { mode: string; skill_key: string; stage: string; completed: boolean; interactions: number }`
  - `export function parseMathTeachArgs(raw: string): MathTeachArgsView`（防御性解析，valid=false 表示坏参占位）
  - `MathTeachCard({ toolCall, isAnswered, answeredPayload, onAnswer })` —— Task 9 MessageBubble 挂载用

- [ ] **Step 1: 写 MathTeachCard.ets**

```typescript
import { CardShell } from './cardshell/CardShell'
import { CardShellConfig } from './cardshell/CardShellTypes'
import { CardShellState } from './cardshell/CardShellState'
import { ToolCall } from '../models/ChatModels'
import { KIDS_MATH_INK, KIDS_MUTED } from './kids/KidsBrandTokens'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { NumberBondBoard } from './mathTeach/NumberBondBoard'
import { NumberLineBoard } from './mathTeach/NumberLineBoard'
import { TenFrameBoard } from './mathTeach/TenFrameBoard'
import { PlaceValueBoard } from './mathTeach/PlaceValueBoard'
import { BalanceBoard } from './mathTeach/BalanceBoard'
import { ShapeBoard } from './mathTeach/ShapeBoard'
import { ClockBoard } from './mathTeach/ClockBoard'
import { BarModelBoard } from './mathTeach/BarModelBoard'

export interface MathTeachResult {
  mode: string
  skill_key: string
  stage: string
  completed: boolean
  interactions: number
}

interface MathTeachArgsView {
  valid: boolean
  mode: string
  stage: string
  difficulty: number
  concept: string
  skill_key: string
  total: number
  start: number
  step: number
  a: number
  b: number
  tens: number
  ones: number
  left: number
  right: number
  focus: string
  hour: number
  minute: number
  part_a: number
  part_b: number
}

const TEACH_MODES_ZH: Record<string, string> = {
  'number_bond': '数的分与合',
  'number_line': '数轴凑十跳',
  'ten_frame': '十格阵凑十',
  'place_value': '小棒与数位',
  'balance': '天平比大小',
  'shape': '图形数一数',
  'clock': '时钟拨一拨',
  'bar_model': '应用题图解'
}

const STAGE_ZH: Record<string, string> = {
  'warm_up': '热身',
  'presentation': '讲解',
  'practice': '操练',
  'production': '输出',
  'review': '复习'
}

function getNum(obj: Record<string, Object>, key: string, dflt: number): number {
  const v: Object | undefined = obj[key]
  if (typeof v === 'number') {
    const n: number = v as number
    if (!Number.isNaN(n)) { return n }
  }
  return dflt
}

function getStr(obj: Record<string, Object>, key: string, dflt: string): string {
  const v: Object | undefined = obj[key]
  if (typeof v === 'string') { return v as string }
  return dflt
}

function createDefaultArgsView(): MathTeachArgsView {
  const view: MathTeachArgsView = {
    valid: false, mode: '', stage: 'presentation', difficulty: 1, concept: '', skill_key: '',
    total: 9, start: 9, step: 5, a: 9, b: 5, tens: 1, ones: 5, left: 9, right: 5,
    focus: 'circle', hour: 9, minute: 0, part_a: 5, part_b: 5
  }
  return view
}

export function parseMathTeachArgs(raw: string): MathTeachArgsView {
  const view: MathTeachArgsView = createDefaultArgsView()
  try {
    const obj = JSON.parse(raw) as Record<string, Object>
    const mode: string = getStr(obj, 'mode', '')
    const stageRaw: string = getStr(obj, 'stage', 'presentation')
    if (TEACH_MODES_ZH[mode] === undefined) {
      return view
    }
    view.valid = true
    view.mode = mode
    view.stage = STAGE_ZH[stageRaw] !== undefined ? stageRaw : 'presentation'
    view.difficulty = getNum(obj, 'difficulty', 1)
    view.concept = getStr(obj, 'concept', '')
    view.skill_key = getStr(obj, 'skill_key', '')
    view.total = getNum(obj, 'total', 9)
    view.start = getNum(obj, 'start', 9)
    view.step = getNum(obj, 'step', 5)
    view.a = getNum(obj, 'a', 9)
    view.b = getNum(obj, 'b', 5)
    view.tens = getNum(obj, 'tens', 1)
    view.ones = getNum(obj, 'ones', 5)
    view.left = getNum(obj, 'left', 9)
    view.right = getNum(obj, 'right', 5)
    view.focus = getStr(obj, 'focus', 'circle')
    view.hour = getNum(obj, 'hour', 9)
    view.minute = getNum(obj, 'minute', 0)
    view.part_a = getNum(obj, 'part_a', 5)
    view.part_b = getNum(obj, 'part_b', 5)
  } catch (_e) {
    return view
  }
  return view
}

function modeZhOf(mode: string): string {
  const z: string | undefined = TEACH_MODES_ZH[mode]
  if (z === undefined) { return '讲解板' }
  return z
}

function stageZhOf(stage: string): string {
  const z: string | undefined = STAGE_ZH[stage]
  if (z === undefined) { return '讲解' }
  return z
}

@ComponentV2
export struct MathTeachCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = (_id: string, _a: string) => {}

  @Local interactions: number = 0
  @Local submitted: boolean = false
  private shellState: CardShellState = new CardShellState()
  private argsView: MathTeachArgsView = createDefaultArgsView()

  aboutToAppear(): void {
    this.argsView = parseMathTeachArgs(this.toolCall.arguments)
  }

  private interactionThreshold(): number {
    return this.argsView.mode === 'shape' ? 2 : 1
  }

  private canSubmit(): boolean {
    return this.interactions >= this.interactionThreshold()
  }

  private submit(): void {
    if (this.submitted || !this.canSubmit()) { return }
    this.submitted = true
    const result: MathTeachResult = {
      mode: this.argsView.mode,
      skill_key: this.argsView.skill_key,
      stage: this.argsView.stage,
      completed: true,
      interactions: this.interactions
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
  }

  private answeredTail(): string {
    try {
      const obj = JSON.parse(this.answeredPayload) as Record<string, Object>
      const n: Object | undefined = obj['interactions']
      if (typeof n === 'number' && (n as number) > 0) {
        return ' · 动手 ' + (n as number) + ' 次'
      }
    } catch (_e) {
    }
    return ''
  }

  private shellConfig(): CardShellConfig {
    const config: CardShellConfig = {
      title: '数学讲解板',
      subtitle: modeZhOf(this.argsView.mode) + ' · ' + stageZhOf(this.argsView.stage),
      icon: $r('sys.symbol.lightbulb'),
      stem: this.argsView.concept === '' ? '这道讲解出错了，老师马上换一张' : this.argsView.concept,
      hasAudio: false,
      usesConfirm: false,
      feedbackTitleCorrect: '',
      correctAnswerLabel: ''
    }
    return config
  }

  private countInteract(): void {
    this.interactions += 1
  }

  @Builder
  BoardArea() {
    if (!this.argsView.valid) {
      Text('这道讲解出错了，老师马上换一张')
        .fontSize(14).fontColor(KIDS_MUTED)
        .padding({ top: 8, bottom: 8 })
    } else if (this.argsView.mode === 'number_bond') {
      NumberBondBoard({ total: this.argsView.total, readonly: this.isAnswered, onInteract: () => { this.countInteract() } })
    } else if (this.argsView.mode === 'number_line') {
      NumberLineBoard({ start: this.argsView.start, step: this.argsView.step, readonly: this.isAnswered, onInteract: () => { this.countInteract() } })
    } else if (this.argsView.mode === 'ten_frame') {
      TenFrameBoard({ a: this.argsView.a, b: this.argsView.b, readonly: this.isAnswered, onInteract: () => { this.countInteract() } })
    } else if (this.argsView.mode === 'place_value') {
      PlaceValueBoard({ tens: this.argsView.tens, ones: this.argsView.ones, readonly: this.isAnswered, onInteract: () => { this.countInteract() } })
    } else if (this.argsView.mode === 'balance') {
      BalanceBoard({ left: this.argsView.left, right: this.argsView.right, readonly: this.isAnswered, onInteract: () => { this.countInteract() } })
    } else if (this.argsView.mode === 'shape') {
      ShapeBoard({ focus: this.argsView.focus, readonly: this.isAnswered, onInteract: () => { this.countInteract() } })
    } else if (this.argsView.mode === 'clock') {
      ClockBoard({ hour: this.argsView.hour, minute: this.argsView.minute, readonly: this.isAnswered, onInteract: () => { this.countInteract() } })
    } else if (this.argsView.mode === 'bar_model') {
      BarModelBoard({ partA: this.argsView.part_a, partB: this.argsView.part_b, readonly: this.isAnswered, onInteract: () => { this.countInteract() } })
    }
  }

  @Builder
  ControlArea() {
    if (this.isAnswered) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(14)
          .fontColor([$r('app.color.status_success')])
        Text('已学会' + this.answeredTail())
          .fontSize(13)
          .fontColor($r('app.color.status_success'))
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    } else if (this.argsView.valid) {
      Button('我学会了 · 继续')
        .width('100%').height(44)
        .fontSize(15)
        .backgroundColor(this.canSubmit() ? KIDS_MATH_INK : withColorAlpha(KIDS_MATH_INK, '33'))
        .fontColor(Color.White)
        .enabled(this.canSubmit())
        .opacity(this.canSubmit() ? 1 : 0.55)
        .onClick(() => { this.submit() })
    }
  }

  build() {
    CardShell({
      config: this.shellConfig(),
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: '',
      onConfirm: () => {},
      onRetry: () => {}
    }) {
      Column({ space: 12 }) {
        this.BoardArea()
        this.ControlArea()
      }
      .width('100%')
    }
  }
}
```

（CardShell 的参数名以 MathQuizCard.ets L473-490 实际调用为准——`correctAnswerText` / `onConfirm` / `onRetry` 若名称不同照实际改；usesConfirm=false 时 confirm/retry 回调不会被触发。）

- [ ] **Step 2: 防御性验证（坏参占位路径）**

人工核对三处：
1. `parseMathTeachArgs('not-json')` → valid=false → 占位文案（try/catch 兜底）
2. `parseMathTeachArgs('{"mode":"xxx"}')` → mode 越界 → valid=false
3. `parseMathTeachArgs('{"mode":"clock"}')`（缺 hour/minute）→ 走默认值 9/0，板可玩不崩溃

Run: assembleHap。Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
git add entry/src/main/ets/components/MathTeachCard.ets
git commit -m "feat(math-teach): add MathTeachCard shell with mode dispatch and completion gate"
```

---

### Task 9: MessageBubble 挂载（9 个编辑点 = spec §8 的 7 站点）

**Files:**
- Modify: `entry/src/main/ets/components/MessageBubble.ets`

**Interfaces:**
- Consumes: Task 8 的 `MathTeachCard` props（toolCall/isAnswered/answeredPayload/onAnswer）、Task 1 的 `isMathTeachFunctionName`
- Produces: math_teach 工具调用的完整气泡渲染（待答内联卡 + timeline step 展开回看）

- [ ] **Step 1: import 区（站点 1，两行）**

在 L47 附近的 SearchToolIdentityUtils import 中追加 `isMathTeachFunctionName`（与 isMathQuizFunctionName 同一条 import）；紧随 `MathQuizCard` import 之后加：

```typescript
import { MathTeachCard } from './MathTeachCard'
```

- [ ] **Step 2: isToolStepClickable 分支（站点 2，L2669 math_quiz 分支之后）**

在 `if (isMathQuizFunctionName(part.toolName)) { return this.isSuccessfulToolStep(part) }` 之后插入：

```typescript
    if (isMathTeachFunctionName(part.toolName)) {
      return this.isSuccessfulToolStep(part)
    }
```

- [ ] **Step 3: isAutoExpandable or 链（站点 3，L2762 附近）**

定位命令：`grep -n "isAutoExpandable" entry/src/main/ets/components/MessageBubble.ets`。在链内 `isMathQuizFunctionName(part.toolName)` 之后插入 `|| isMathTeachFunctionName(part.toolName)`。

- [ ] **Step 4: isDefaultExpanded or 链（站点 4，L2772 附近）**

同 Step 3 的插入方式，目标链在 `isDefaultExpanded` 内。

- [ ] **Step 5: shouldRender 守卫（站点 5，L2835-2840 shouldRenderMathQuizInteractionCard 之后）**

```typescript
  private shouldRenderMathTeachInteractionCard(toolCall: ToolCall, index: number): boolean {
    if (!isMathTeachFunctionName(toolCall.functionName) || this.shouldHideToolCallCard(toolCall)) {
      return false
    }
    return !this.isAskUserToolCallAnswered(toolCall, index)
  }
```

- [ ] **Step 6: 内联待答渲染块（站点 6，L2032-2047 math_quiz ForEach 块之后）**

```typescript
              // math_teach 待答时保留独立互动卡片;提交后收缩到 timeline step 内。
              if (this.message.hasToolCalls()) {
                ForEach(this.message.toolCalls, (toolCall: ToolCall, index: number) => {
                  if (this.shouldRenderMathTeachInteractionCard(toolCall, index)) {
                    MathTeachCard({
                      toolCall: toolCall,
                      isAnswered: false,
                      answeredPayload: toolCall.approvalReason,
                      onAnswer: (toolCallId: string, answerJson: string): void => {
                        this.onAskUserAnswer(toolCallId, answerJson)
                      }
                    })
                      .margin({ bottom: 6 })
                  }
                }, (toolCall: ToolCall, index: number) => 'teach_' + toolCall.id + '_' + index.toString())
              }
```

- [ ] **Step 7: handleToolStepClick 分支（站点 7，L3263 math_quiz 分支之后）**

```typescript
    if (isMathTeachFunctionName(part.toolName)) {
      this.toggleToolStep(part)
      return
    }
```

- [ ] **Step 8: ToolStepContent 分发臂（站点 8，L3737-3738 math_quiz 臂之后）**

```typescript
      } else if (isMathTeachFunctionName(step.toolName)) {
        this.MathTeachStepContent(step)
```

- [ ] **Step 9: MathTeachStepContent builder（站点 9，MathQuizStepContent L4005-4059 之后，逐行镜像）**

```typescript
  // math_teach 工具步骤: 已完成的数学讲解板, 在 timeline 中显示简化结果, 可展开回看板面
  @Builder
  MathTeachStepContent(step: MessagePart) {
    Column() {
      Row({ space: 6 }) {
        if (step.toolStatus === 'succeeded') {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(13)
            .fontColor([$r('app.color.status_success')])
        } else if (step.toolStatus === 'failed' || step.toolStatus === 'denied') {
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(13)
            .fontColor([$r('app.color.status_error')])
        } else {
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.themePrimary)
        }

        Text(this.buildToolStepTitle(step))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        if (this.isToolStepClickable(step)) {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(12)
            .fontColor([$r('app.color.text_tertiary')])
            .rotate({ angle: this.isToolStepExpanded(step) ? 0 : -90 })
            .animation({ duration: 200, curve: Curve.EaseOut })
        }
      }
      .width('100%')
      .onClick(() => {
        if (this.isToolStepClickable(step)) {
          this.handleToolStepClick(step)
        }
      })

      // 展开时回看讲解板（只读态：板以初始参数渲染、控制区隐藏、「已学会」药丸）
      if (this.isToolStepExpanded(step) && step.toolResult !== '') {
        MathTeachCard({
          toolCall: this.buildToolCallFromStep(step),
          isAnswered: true,
          answeredPayload: step.toolResult,
          onAnswer: (_toolCallId: string, _answerJson: string): void => {}
        })
        .margin({ top: 8 })
      }
    }
    .width('100%')
  }
```

- [ ] **Step 10: 精确行校验 + 构建验证**

```bash
grep -c "isMathTeachFunctionName" entry/src/main/ets/components/MessageBubble.ets   # expect ≥ 8
grep -c "MathTeachCard" entry/src/main/ets/components/MessageBubble.ets             # expect ≥ 3
grep -c "'teach_'" entry/src/main/ets/components/MessageBubble.ets                  # expect 1
```

Run: assembleHap。Expected: BUILD SUCCESSFUL

- [ ] **Step 11: Commit**

```bash
git add entry/src/main/ets/components/MessageBubble.ets
git commit -m "feat(math-teach): mount MathTeachCard in MessageBubble (9 sites)"
```

---

### Task 10: kids_math 锁定工具 +2 与提示词五步课协议重写

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets`（KIDS_MATH_LOCKED_TOOL_IDS L144-147、KIDS_MATH_SYSTEM_PROMPT L257-264）

**Interfaces:**
- Consumes: Task 1 `MATH_TEACH_TOOL_ID`；既有 `MATCHING_PAIRS_TOOL_ID`（该文件 L20 已 import，无需新增 import）
- Produces: 注册表锁定的 kids_math 新工具集与新提示词（`getBuiltInAssistantSpec` / `normalizeAssistant` 自动对老用户生效，无需迁移代码）

- [ ] **Step 1: import MATH_TEACH_TOOL_ID**

在该文件头部从 SearchToolIdentityUtils 的 import 列表里（L20 区域，`MATCHING_PAIRS_TOOL_ID` 所在行）追加 `MATH_TEACH_TOOL_ID`。

- [ ] **Step 2: KIDS_MATH_LOCKED_TOOL_IDS 追加 2 项**

将 L144-147 整块替换为：

```typescript
export const KIDS_MATH_LOCKED_TOOL_IDS: string[] = [
  ASK_USER_TOOL_ID, CHILD_PROFILE_TOOL_ID, GET_TIME_INFO_TOOL_ID, GRANT_STAR_TOOL_ID,
  MATH_VERIFY_TOOL_ID, MATH_QUIZ_TOOL_ID, VERTICAL_MATH_TOOL_ID,
  MATH_TEACH_TOOL_ID, MATCHING_PAIRS_TOOL_ID
]
```

（其余 4 个内置助手的 lockedToolIds 与 DEFAULT_ASSISTANT_LOCKED_TOOL_IDS 一律不动。）

- [ ] **Step 3: KIDS_MATH_SYSTEM_PROMPT「数学教学策略」段重写**

将数组内以下 8 行（L257-264）：

```
  '## 数学教学策略',
  '- 聚焦 8 个数学维度:math_counting / math_addition / math_subtraction / math_multiply / math_divide / math_shapes / math_comparison / math_time。',
  '- 根据 child_profile 各维度 level 选难度:level 0-1 从最基础开始(实物 + 数数),level 2-3 巩固练习,level 4-5 挑战更高阶。',
  '- 由易到难:一次只出 1 道题,答对再升一点难度,连错 2 次就降难度并鼓励。',
  '- 出题必须用 math_quiz 工具(带 type 字段:arithmetic / shape / comparison / time / elapsed_time / word_problem),不要在文字里编数学题。',
  '- 题型要轮换:口算、认图形、比大小、看时钟、应用题换着出,不要连续都是同一种题型。',
  '- 教「怎么算」用 vertical_math 演示竖式(数位对齐、进位、退位),演示后用 math_quiz 出 1-2 题巩固。',
  '- child_profile(action: "update") 只更新 math_ 开头的技能维度,notes 必须基于本轮具体表现。',
```

替换为以下 14 行（spec §6.1 原文）：

```
  '## 数学教学策略 · 五步课协议',
  '- 聚焦 10 个数学维度:math_number_sense / math_counting / math_addition / math_subtraction / math_multiply / math_divide / math_shapes / math_comparison / math_time / math_word_problem。',
  '- 每节课按五步推进,讲解必须先发生,不让孩子在没看懂算理前刷题:',
  '  ① 热身 warm_up:math_quiz(type:arithmetic) 口算接龙 2-3 道,唤醒旧知;',
  '  ② 讲解 presentation:math_teach 先摆一摆再讲算理——数的分与合 number_bond / 数轴跳 number_line / 十格阵凑十 ten_frame / 小棒数位 place_value / 天平比大小 balance / 图形 shape / 时钟 clock / 应用题图解 bar_model,按今日知识点八选一;',
  '  ③ 操练 practice:math_quiz / vertical_math 巩固 1-2 题;',
  '  ④ 输出 production:ask_user 让孩子用自己的话讲算理,或 math_verify 验算;',
  '  ⑤ 复习 review:matching_pairs 出算式↔结果配对(left 填「9+5」,right 填「14」),留一个明天验证的钩子。',
  '- mode 与 skill_key 对应:number_bond→math_number_sense,number_line/ten_frame→math_addition,place_value→math_counting,balance→math_comparison,shape→math_shapes,clock→math_time,bar_model→math_word_problem。',
  '- 讲解板约束:ten_frame/number_line 只讲 20 以内进位加法(和不大于 10 的不用凑十,直接口算);讲解参数必须与算理一致,算式是几就摆几。',
  '- 难度跟随画像:各维度 level 决定 math_teach 的 difficulty 与 math_quiz 难度,偏差不超过 1 级;level 0-1 从实物+数数开始,不给三位数进位。',
  '- 三类禁止:连续出题不讲解;讲解参数与算理矛盾;超龄难度。',
  '- child_profile(action: "update") 只更新 math_ 开头的技能维度,notes 必须基于本轮具体表现;把孩子解题用的方法(凑十/数数/掰手指)记入 strategy 字段,常错点(忘记进位/方向反/数位没对齐)记入 misconceptions 字段。',
```

「## 授星规则」段（L266-267）与「## 边界」段（L269-271）**保持原样不动**。

- [ ] **Step 4: 锁定语义验证 + 构建**

```bash
grep -n "MATH_TEACH_TOOL_ID\|MATCHING_PAIRS_TOOL_ID" entry/src/main/ets/models/AssistantModels.ets | head -10
```
Expected: import 行 2 条 + KIDS_MATH_LOCKED_TOOL_IDS 内 2 条 + kids_games 行原有 1 条。

Run: assembleHap。Expected: BUILD SUCCESSFUL

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/models/AssistantModels.ets
git commit -m "feat(math-teach): lock math_teach+matching_pairs for kids_math and rewrite five-step lesson prompt"
```

---

### Task 11: 全量验证（gauntlet + 构建 + IDE 测试 + 真机清单）

**Files:**
- 无新改动；验证全部 10 个任务的产出

- [ ] **Step 1: JSON.parse gauntlet（回归）**

```bash
node -e "const s=require('fs').readFileSync('entry/src/main/ets/config/BuiltinTools.ets','utf-8');const re=/const rawSchemaJson: string = \`([\s\S]*?)\`/g;let m,n=0,bad=0;while((m=re.exec(s))!==null){n++;try{JSON.parse(m[1])}catch(e){bad++;console.log('SCHEMA '+n+' FAIL: '+e.message)}}console.log('schemas: '+n+', failures: '+bad);process.exit(bad>0?1:0)"
```
Expected: `failures: 0`

- [ ] **Step 2: 身份与触点 grep**

```bash
grep -rln "MATH_TEACH_TOOL_ID" entry/src/main/ets --include="*.ets" | wc -l        # expect ≥ 4（SearchToolIdentityUtils/BuiltinTools/ToolExecutionService/AssistantModels）
grep -c "isMathTeachFunctionName" entry/src/main/ets/components/MessageBubble.ets  # expect ≥ 8
grep -A 90 "private async handleMathTeach" entry/src/main/ets/services/ToolExecutionService.ets | grep -c recordStarEvent  # expect 0
grep -c "math_number_sense\|math_word_problem" entry/src/main/ets/services/ChildProfileService.ets  # expect ≥ 2
grep -c "五步课协议" entry/src/main/ets/models/AssistantModels.ets                  # expect 1
```

- [ ] **Step 3: 干净构建**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw clean --mode module -p product=default
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug
```
Expected: BUILD SUCCESSFUL（若遇 SignHap "Invalid CEN header" 报错是 hvigor 守护进程 stale bug——直接重跑，非代码问题）

- [ ] **Step 4: IDE 单元测试（人工执行）**

在 DevEco Studio 中逐个右键 Run（CLI hvigorw test 不可用）：
1. `entry/src/ohosTest/ets/test/utils/MathTeachBoards.test.ets` —— 10 用例全绿
2. `entry/src/ohosTest/ets/test/utils/MathTeachValidation.test.ets` —— 14 用例全绿
3. `entry/src/ohosTest/ets/test/utils/ChildProfileParse.test.ets`（若 Task 3 Step 5 创建）—— 2 用例全绿

- [ ] **Step 5: 真机验证清单（人工执行，来自 spec §8）**

1. 小星数学老师会话里说「给我讲讲凑十法」→ AI 调起 math_teach，板面正确渲染、头部显示「数学讲解板 · 数轴凑十跳 · 讲解」样式标签
2. 8 块板逐一验证：关键交互生效（凑十跳两段弧线 / 借一个进框飞入 / 满 10 捆扎 / 天平倾斜 / 图形切换 / 时针分针步进 / 长条宽度过渡 / 分合圆点步进）
3. 完成门：未交互时「我学会了 · 继续」置灰；交互达标后点亮；按下后 AI 收到回执并继续出操练题（math_quiz）
4. 坏参拦截：诱导 AI 出 9+1 的 ten_frame → 被校验拒绝、AI 收到 should_retry 自行修正（观察 AI 重调，无卡片崩溃）
5. 数学画像页显示 10 维（新增「数感与数的组成」「解决问题」）；讲过课后维度卡出现「方法：…」「易错：…」标签
6. 工具中心出现「数学讲解板」（READ 权限、BUILTIN 来源）
7. 默认小星老师（default）会话行为不变：无 math_teach 工具、无五步课协议；其他 3 学科助手不变
8. 老会话回看：历史 kids_math 会话正常渲染（无 math_teach 历史数据）；升级后首次启动无崩溃（画像 24→26 维兼容）

- [ ] **Step 6: 收尾 Commit（如有零星修复）**

```bash
git add -A
git commit -m "fix(math-teach): address findings from full verification pass"
```
（无修复则跳过。）

