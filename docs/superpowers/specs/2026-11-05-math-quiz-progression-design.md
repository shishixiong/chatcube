# math_quiz 出题历史与难度渐进 — 设计文档

**日期：** 2026-11-05
**状态：** 待用户批准
**范围：** `math_quiz` 每次作答落库、按「最近 20 次同轨题目」去重、按掌握度逐步升/降难度；涉及 `ToolExecutionService`、`BuiltinTools`、`DatabaseService`、`AssistantModels`，不改 `MathQuizCard` UI。
**前置文档：** `.claude/rules/teaching-architecture.md`（教学体系）、`CLAUDE.md`（math_quiz 工具与互动卡片总览）

---

## 1. 背景与目标

### 1.1 现在的问题

小星数学老师（`kids_math`）/ 小星老师（`default`）调用 `math_quiz` 时，没有任何「孩子已经会什么」的持久记忆。模型每轮都可能从最简单的题开始，孩子反复做已经会的题，难度不前进。

现有数据只能证明「发生过一次 math_quiz」：

- `star_events` 有 `activity_type='math_quiz'`、`correct` 折算的星星、`tool_call_id`、`skill_key`，但**没有题目、难度、第几次答对**；
- `tool_events` 存了 `tool_arguments` 和 `tool_result`，理论上可解析，但没有难度字段，也不适合做高频难度查询；
- `child_profile` 的 `math_addition` 等只有 0–5 的粗粒度等级，没有「当前练到哪一级、这一级做对几次」。

### 1.2 目标

1. 每次 `math_quiz` 作答后，把题目、难度级别、答对/答错、是否首答对写进一张**专用于难度推进**的表。
2. 下一次 `math_quiz`（`purpose='practice'`）进入卡片前先过难度闸门：
   - 查询**同一难度轨最近 20 条**记录；
   - 拒绝「低于当前目标」的题、拒绝跳级题、拒绝最近 20 条里刚做过的同算式；
   - 回传一个可执行的 `target`（级别、数字范围、步骤、示例），让模型一次改对。
3. 同一级累计 **10 次首答正确** → 升一级；**连续 2 道「两次都错」** → 降一级；二级答对不计入掌握。
4. 热身/复习（`purpose='warm_up' | 'review'`）允许低于当前目标，但不计入掌握、不触发降级，并设每会话配额，防止用「热身」绕过闸门。
5. 每次作答后把 `math_progress` 追加到工具结果（只给 LLM 看），并让 `child_profile(action:"read")` 返回当前各轨目标，模型开局就知道该出什么难度。

### 1.3 成功标准

- 孩子在某一级首答对 10 题后，下一题如果仍是同一级，`math_quiz` 返回 `difficulty_gate` 且 `target.level` 已是下一级；模型按 `target` 重出后卡片正常渲染。
- 连续 2 道两次都错后，下一题目标降一级。
- 应用题（`word_problem=true`）即使卡片不显示算式，也能被正确判级；未填隐藏 `expression` 的应用题（三种 purpose）被拒绝。
- 重启 App 后进度不丢；同一 `skill_key` 在 `kids_math` 与 `default` 会话间共享进度。
- `MathQuizCard`、`MessageBubble`、星星规则、备课/评估管线**零改动**。

---

## 2. 非目标（本期不做）

- 不做题库/预生成题目；题目仍由 LLM 现场生成。
- 不做 IRT / 贝叶斯知识追踪；规则是确定性的计数状态机。
- 不支持分数、带余数除法、多位数 × 多位数、被乘数超过 3 位的乘法、操作数或中间结果超过 99,999；这些题**三种 purpose 都拒绝**（热身/复习的例外只针对「低于目标级」，不针对不支持的题型）。小数题例外：`track='none'` 只记录、不闸门（见 §4.5）。
- 不改 `MathQuizCard` 的任何 UI（不显示级别徽章、不做历史列表）。
- 不改星星规则：`math_quiz` 答对仍授 1 星，warm-up/review 答对也照常授星（见 §12 取舍）。
- 不改备课老师 / 评估老师：`kids_math` 会话仍不进备课管线。
- 新表不纳入 WebDAV / 导入导出（与 `star_events`、`puzzle_records` 现状一致）；换机后进度从画像重新初始化。
- 不做家长端「重置进度」入口（后续可加）。

---

## 3. 用户已拍板的规则

| 决策 | 内容 |
|------|------|
| 难度三轴 | 数字范围、运算类型、步骤数（另加进位/借位作为范围内的细分） |
| 掌握门槛 | 同一级 **10 次首答正确** |
| 降级门槛 | **连续 2 道题两次都错** → 降一级 |
| 加减范围 | 最高到**万位**（≤99,999），即 15 级阶梯 |
| 热身/复习 | 新增 `purpose` 字段：`practice`（默认）/ `warm_up` / `review`；后两者可低于目标，不计掌握、不降级 |

---

## 4. 难度模型

### 4.1 轨道（track）

进度按「轨道」独立维护。轨道决定用哪张阶梯、从画像哪个维度取初始等级。

| track | 适用题型 | 阶梯 | 画像初始维度 |
|-------|----------|------|--------------|
| `add` | `type=arithmetic`，含 `+`（可含 `−`，由 skill_key 指定） | 加减 15 级 | `math_addition` |
| `sub` | `type=arithmetic`，只含 `−`（或 skill_key 指定减法） | 加减 15 级 | `math_subtraction` |
| `muldiv` | `type=arithmetic`，含 `×` 或 `÷` | 乘除 10 级 | `math_multiply` / `math_divide`（见 §5.4） |
| `compare` | `type=comparison` | 比较 6 级 | `math_comparison` |
| `clock` | `type=time` | 认钟 4 级 | `math_time` |
| `elapsed` | `type=elapsed_time` | 经过时间 4 级 | `math_time` |
| `shape` | `type=shape` | 无（记录用） | `math_shapes` |
| `none` | 无法判级的算术/数数题 | 无（记录用） | `math_counting` / `math_number_sense` |

**应用题**（`word_problem=true`）不单独设轨：按隐藏 `expression` 的运算落到 `add` / `sub` / `muldiv`。应用题的语言难度不在本期度量范围内。

**skill_key 与轨道一致性**：先把 `skill_key` 归一（见下），再校验。`math_shapes` 只能配 `type=shape`；`math_comparison` 只能配 `comparison`；`math_time` 只能配 `time`/`elapsed_time`；`math_addition`/`math_subtraction` 只能配算术，且纯 `+` 只配 `math_addition`、纯 `−` 只配 `math_subtraction`（同时含 `+` 和 `−` 的混合链两者皆可，由 `skill_key` 决定轨道）；`math_multiply`/`math_divide` 只能配含 ×/÷ 的算术。`math_word_problem` 是例外，可配任意可判级算术算式。不符 → 三种 purpose 都拒绝（`difficulty_gate` + `should_retry`）。

**skill_key 归一与未知值**：历史上 `AssistantModels.ets` 的基础提示词用过短名（`addition` / `subtraction` / `multiply` / `divide` / `shapes` / `comparison` / `time` / `counting` / `number_sense`），schema 与 `kids_math` 提示词用 `math_*`。判定前统一映射：

| 输入 | 归一 |
|------|------|
| `addition` / `math_addition` | `math_addition` |
| `subtraction` / `math_subtraction` | `math_subtraction` |
| `multiply` / `math_multiply` | `math_multiply` |
| `divide` / `math_divide` | `math_divide` |
| `shapes` / `math_shapes` | `math_shapes` |
| `comparison` / `math_comparison` | `math_comparison` |
| `time` / `math_time` | `math_time` |
| `counting` / `math_counting` | `math_counting` |
| `number_sense` / `math_number_sense` | `math_number_sense` |
| `word_problem` / `math_word_problem` | `math_word_problem` |

**无法识别的值按空处理**（不拒绝），由算式推断轨道；空值同样按算式推断。这样自定义助手/旧提示词不会因 `skill_key` 拼写被闸门挡住。

**混合加减链**（同时有 `+` 和 `−`）：由归一后的 `skill_key` 决定落 `add` 还是 `sub`；未填时默认 `add`。只含 `−` 且 `skill_key` 未填 → `sub`。混合乘除表达式落 `muldiv`。

### 4.2 加减轨（15 级）

`max_operand` 指算式中所有操作数与中间结果的最大绝对值（减法结果非负由现有校验保证）。

| 级 | 标签 | 数字范围 | 步骤 | 进位/借位 | 示例 |
|----|------|----------|------|-----------|------|
| L1 | 10 以内一步 | ≤10（结果也 ≤10） | 1 | 不限 | `7 + 2` / `9 − 3` |
| L2 | 20 以内不进位/不退位 | ≤20 | 1 | 无 | `12 + 5` / `18 − 6` |
| L3 | 20 以内进位/退位或两步混合 | ≤20 | 1–3 | 不限 | `8 + 7` / `15 − 8` / `10 − 3 + 5` |
| L4 | 100 以内不进位/不退位 | ≤100 | 1 | 无 | `23 + 14` / `68 − 25` |
| L5 | 100 以内进位/退位 | ≤100 | 1 | 有 | `47 + 28` / `63 − 27` |
| L6 | 100 以内两步混合 | ≤100 | 2–3 | 不限 | `47 + 28 − 15` |
| L7 | 1000 以内不进位/不退位 | ≤999 | 1 | 无 | `213 + 124` / `568 − 235` |
| L8 | 1000 以内进位/退位 | ≤999 | 1 | 有 | `487 + 265` / `503 − 178` |
| L9 | 1000 以内两步混合 | ≤999 | 2–3 | 不限 | `487 + 265 − 130` |
| L10 | 10000 以内不进位/不退位 | ≤9999 | 1 | 无 | `2134 + 1243` |
| L11 | 10000 以内进位/退位 | ≤9999 | 1 | 有 | `4876 + 2657` |
| L12 | 10000 以内两步混合 | ≤9999 | 2–3 | 不限 | `4876 + 2657 − 1304` |
| L13 | 100000 以内不进位/不退位 | ≤99999 | 1 | 无 | `21345 + 12432` |
| L14 | 100000 以内进位/退位 | ≤99999 | 1 | 有 | `48765 + 26578` |
| L15 | 100000 以内两步混合 | ≤99999 | 2–3 | 不限 | `48765 + 26578 − 13042` |

判定规则：

- **步数** = 二元运算符个数（`47 + 28 − 15` 是 2 步）。现有 `validateMathQuizArgs` 最多 3 个运算符，所以最多 3 步。
- **进位/借位**：加法按列对齐，任一位 `digit_sum + carry > 9` 即「有进位」；减法任一位需要借位即「有借位」。多位数列都要检查。
- **L1** 除操作数 ≤10 外，要求结果也 ≤10（`7+8=15` 属于 L3，不是 L1）。
- **中间结果非负**：从左到右逐步计算；任一步结果为负（如 `3 − 5 + 10`，中间 −2）→ `gate=true + error`，三种 purpose 都拒绝。现有 `validateMathQuizArgs` 只检查最终值，不拦这个。
- 混合级（L6/L9/L12/L15）不区分进位/借位，2–3 步均可；`max_operand` 取所有操作数与中间结果的最大值。
- 20 以内的 2–3 步混合没有独立级别：落到 L3（20 以内最难级），避免新增用户未批准的级别。
- 操作数或中间结果超过 99,999 的算式：practice/warm-up/review 都拒绝，回 `should_retry`，提示「最高到 5 位数，中间结果也不能超过 99999」。
- 小数题（**操作数**含小数点）：不进入加减轨（`track='none'`，只记录，不闸门，三种 purpose 都可出）。整数除法的非整数商按 §4.3 的「带余数」拒绝，不算小数题。

### 4.3 乘除轨（10 级）

用户批准的 10 级是**一条合并课程序列**：先乘后除，除法从 MD8 开始。

| 级 | 标签 | 判定要点 | 示例 |
|----|------|----------|------|
| MD1 | 2/5/10 表内乘法 | 两个因数都在 1–10，**较大因数**属于 {1,2,5,10} | `2 × 2` / `10 × 3` |
| MD2 | 3/4/6 表内乘法 | 较大因数属于 {3,4,6} | `2 × 3` / `4 × 6` |
| MD3 | 7/8/9 表内乘法 | 较大因数属于 {7,8,9} | `7 × 8` / `3 × 7` |
| MD4 | 整十数 × 一位数 | 一个因数是 20–90 的整十，另一个 2–9 | `20 × 3` / `90 × 4` |
| MD5 | 两位数 × 一位数，不进位 | 十位/个位乘完都不产生进位，乘数 2–9 | `23 × 3` |
| MD6 | 两位数 × 一位数，含进位 | 任一位产生进位，乘数 2–9 | `27 × 3` |
| MD7 | 三位数 × 一位数 | 含进位或不进位均可，乘数 2–9 | `213 × 3` / `487 × 5` |
| MD8 | 表内除法 | 除数 2–10、商 1–10，整除 | `15 ÷ 5` / `63 ÷ 7` |
| MD9 | 两位数 ÷ 一位数（整除） | 被除数 10–99，除数 2–9，整除 | `84 ÷ 4` |
| MD10 | 三位数 ÷ 一位数（整除）或两步混合 | 被除数 100–999 ÷ 2–9 整除；或含 ×/÷ 的 2–3 步混合 | `369 ÷ 3` / `12 × 3 + 8` / `12 ÷ 3 + 8` |

判定规则：

- **MD1–MD3 只用于乘法**：按两个因数中**较大者**的所在口诀组取——`{1,2,5,10}` = 1 组，`{3,4,6}` = 2 组，`{7,8,9}` = 3 组。任一因数为 1 → MD1（避免用 `1 × n` 刷高年级）。`10 × 3` 较大因数是 10 → MD1；`2 × 3` 较大因数是 3 → **MD2**，不是 MD1。
- **MD4 整十数 × 一位数**只认「20–90 的整十」×「2–9」；`20 × 30` 不支持。
- 两位数/三位数 × 一位数要求乘数为 **2–9**；两位乘数 × 两位乘数本期不支持 → 三种 purpose 都拒绝。
- **MD8 只用于表内除法**：除数 2–10、商 1–10，整除；不再按口诀组细分。除法**不会**落 MD1–MD3。
- 除法判级顺序：先判 MD8 表内（除数 2–10 且商 1–10）；否则 2 位数被除数 → MD9；3 位数被除数 → MD10。`24 ÷ 4` 是 MD8，`84 ÷ 4` 是 MD9。
- MD9/MD10 除数 **2–9**。除法必须整除；带余数（含 `7 ÷ 2` 这种商为小数的整数除法）→ 三种 purpose 都拒绝。
- 含 `×`/`÷` 且运算符数 ≥2 → MD10（不再细分）。
- **小数题**（操作数含小数点）→ `none` 记录，不闸门。

### 4.4 比较 / 认钟 / 经过时间

**比较（`compare`，6 级）**：按 `max(left_value, right_value)`。

| 级 | 范围 |
|----|------|
| P1 | ≤10 |
| P2 | ≤20 |
| P3 | ≤100 |
| P4 | ≤999 |
| P5 | ≤9999 |
| P6 | ≤99999 |

超过 99,999 → 拒绝。

**认钟（`clock`，4 级）**：按 `clock_minute`。`clock_minute` 必须是 0–55 的 5 的倍数；否则 `gate=true + error`。

| 级 | 标签 | 分钟 | target 示例 |
|----|------|------|-------------|
| C1 | 整点 | 0 | `3:00` |
| C2 | 半点 | 30 | `3:30` |
| C3 | 5 分刻度（非临近整点） | 10/15/20/25/35/40/45/50 | `3:15` |
| C4 | 临近整点（差几分） | 5/55 | `3:55` |

**经过时间（`elapsed`，4 级）**：起止分钟也必须是 5 的倍数。

| 级 | 标签 | 条件 | target 示例 |
|----|------|------|-------------|
| E1 | 同一小时内 | 起止小时相同，分钟差为 5–55 的 5 的倍数 | `3:10 → 3:40` |
| E2 | 跨整点、分钟相同 | 跨一个整点，起止分钟相同 | `3:00 → 4:00` |
| E3 | 跨整点、分钟不同 | 跨一个整点，起止分钟不同 | `3:30 → 4:15` |
| E4 | 跨 2 小时以上或跨 12 点 | 跨 ≥2 小时，或跨 12 点 | `11:30 → 1:15` |

起止相同（时长 0）、时长为负（未跨 12 点）或时长 >12 小时 → `gate=true + error`。

### 4.5 不计难度的题型

- `type=shape`：`track='shape'`，`level=0`，只记录，不闸门、不推进。
- `type=arithmetic` 且**操作数含小数点**：`track='none'`，`level=0`，只记录。
- `type=arithmetic` 且 `skill_key` 归一后是 `math_counting`/`math_number_sense` 且**没有 `expression`**：`track='none'`，`level=0`，只记录。
- `math_counting`/`math_number_sense` **带**可判级算式 → 按算式落 `add`/`sub`/`muldiv`，正常闸门。
- `skill_key` 是 `math_addition`/`math_subtraction`/`math_multiply`/`math_divide`/`math_word_problem` 但算术题为空 `expression` → `gate=true + error`，三种 purpose 都拒绝（不能靠 `none` 绕过闸门）。
- 这些题的 `purpose` 仍保存；`counted=0`。

### 4.6 级别判定纯函数契约

新增 `utils/MathQuizProgression.ets`，全部无副作用、可在 hypium 直接测：

```ts
export interface MathQuizLevelInput {
  quizType: string            // 'arithmetic' | 'shape' | 'comparison' | 'time' | 'elapsed_time'
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
  level: number               // 0 = 不闸门
  gate: boolean               // true = 必须匹配当前进度
  spec: MathQuizLevelSpec | null
  expressionKey: string       // 去重键；不闸门时可为 ''
  error: string               // 非空 = 三种 purpose 都拒绝；消息直接回给 LLM
}

export function resolveMathQuizLevel(input: MathQuizLevelInput): MathQuizLevelInfo
```

`error` 只覆盖「无法进入难度轨」的结构性问题（如 gated 算术算式为空、带余数、中间结果为负、超过 5 位数、skill_key 与运算不符）。题目本身答案错仍由现有 `validateMathQuizArgs` 先拦。

**`gate` 与 `error` 的组合约定：** 结构性错误必须返回 `gate=true + error`，否则 `evaluateGate` 的 `if (!info.gate) return ok` 会把它当「不闸门题型」放过去。只有真正不该闸门的题（`type=shape`、小数、`math_counting`/`math_number_sense` 的无算式数数题）才返回 `gate=false + error=''`。

`MathQuizLevelSpec` 字段：

```ts
export interface MathQuizLevelSpec {
  track: MathQuizTrack
  level: number
  label: string
  maxOperand: number          // 非算术轨为 0
  minSteps: number            // 非算术轨为 0
  maxSteps: number            // 非算术轨为 0
  carryRule: 'none' | 'required' | 'any'
  constraint: string          // 非算术轨的可执行约束（见下）；算术轨写 ''
  example: string
}
```

`buildTarget(spec)` 把 spec 转成闸门回传的 `target`（字段名 snake_case，与工具参数一致）。`compare` / `clock` / `elapsed` 的 target 输出 `track / level / label / constraint / example`，省略 `max_operand / steps / carry`，避免 LLM 把「认识钟表」误当成算术范围。`constraint` 的取值：

| track | level | constraint |
|-------|-------|------------|
| `compare` | P1–P6 | `比较两个数的大小，数值不超过 10/20/100/999/9999/99999` |
| `clock` | C1 | `整点，分钟为 0` |
| `clock` | C2 | `半点，分钟为 30` |
| `clock` | C3 | `分钟为 10/15/20/25/35/40/45/50 之一` |
| `clock` | C4 | `分钟为 5 或 55（临近整点）` |
| `elapsed` | E1 | `起止在同一小时，分钟差为 5–55 的 5 的倍数` |
| `elapsed` | E2 | `跨一个整点，起止分钟相同` |
| `elapsed` | E3 | `跨一个整点，起止分钟不同` |
| `elapsed` | E4 | `跨 ≥2 小时，或跨 12 点` |

---

## 5. 进度状态机

### 5.1 状态

每个 `track` 一行 `math_quiz_progress`：

| 字段 | 含义 |
|------|------|
| `track` | 主键 |
| `current_level` | 当前目标级别（1 起，最大为该轨最高级） |
| `correct_at_level` | 当前级累计**首答正确**次数（0–10） |
| `consecutive_wrong` | 当前级连续「两次都错」的题数（0–1；到 2 即降级并清零） |
| `updated_at` | 最后一次**计入进度**的作答时间（warm_up/review 不更新） |

### 5.2 单次作答的推进规则

只有 `purpose='practice'` **且**题目级别 === 作答时的 `current_level` 才计入（`counted=1`）。其余记录 `counted=0`，只落历史。

| 作答结果 | `correct_at_level` | `consecutive_wrong` | 级别 |
|----------|--------------------|---------------------|------|
| 首答正确（`attempts=1 && correct=true`） | +1 | 归零 | +1 到 10 且未到最高级 → 升一级，计数归零；已到最高级 → 保持 10 |
| 第二次答对（`attempts=2 && correct=true`） | 不变 | 归零 | 不变 |
| 两次都错（`correct=false`） | 不变 | +1 | 到 2 且 >1 级 → 降一级，计数归零、连续错归零；到 2 且已在 1 级 → 保持 1 级、连续错归零 |

说明：

- 「10 次首答正确」是**累计**，不要求连续；单次两次都错不清零累计正确数。
- `attempts` 缺失时按 `correct ? 1 : 2` 兜底（兼容旧会话恢复的 payload）；`first_try = correct && attempts === 1`。
- 第二次答对不算掌握，但也不算「连续错」——孩子最终做对了，连续错计数归零。
- 降到 1 级后继续两次都错，不再降，只把连续错归零。
- 最高级继续 10 次首答正确，`correct_at_level` 封顶 10；两次都错会降到最高级 -1（见 §12 取舍）。
- 已作答题目的级别与当前 `current_level` 不一致（并发/排队卡片、升级后旧卡）→ `counted=0`，不推进、不降级。举例：两张 L5 卡片同时发出，第一张答对升到 L6，第二张答对时级别仍是 L5，不计入 L6。
- `consecutive_wrong` 跨会话保留，但距上次计入进度的作答 >24 小时时先归零（用 `updated_at` 判断），避免把昨天的一次两错和今天的一次两错算成「连续」。

### 5.3 `purpose` 语义

| purpose | 默认 | 级别限制 | 计入进度 | 每会话配额 |
|---------|------|----------|----------|------------|
| `practice` | 是 | 必须**等于**当前目标级 | 是 | 无 |
| `warm_up` | 否 | 可**低于**当前目标级；高于目标级拒绝 | 否 | 最多 5 题 |
| `review` | 否 | 可**低于**当前目标级；高于目标级拒绝 | 否 | 最多 3 题 |

- 缺省/非法值按 `practice`；`warmup` / `warm-up` 归一为 `warm_up`（模型偶尔会漏下划线）。
- 配额按 `session_id + purpose` 数 `math_quiz_records`，只统计进入难度轨的记录（`level > 0`）；shape/数数题不占配额。超限返回 `should_retry`，提示改用 `practice`。
- `session_id` 为空（非会话执行）时不强制配额，但仍不计进度。
- warm-up/review 不做「最近 20 条同算式」去重——复习就是要重做旧题。

### 5.4 初始等级（画像 → 轨道）

新用户/升级后第一次用到某轨时，按 `child_profile` 的 0–5 级映射。**首次作答计入进度时**写一行进度（`getEffectiveProgress` 读到无行只按画像算、不写）；之后**不再因画像更新而回写**。

**加减轨（15 级）**：

| 画像 level | 0 未评估 | 1 入门 | 2 初步 | 3 中等 | 4 良好 | 5 精通 |
|------------|----------|--------|--------|--------|--------|--------|
| 初始级 | 1 | 2 | 3 | 5 | 8 | 11 |

加减轨若本维度为 0 而兄弟维度 >0：取兄弟维度映射级 -1（不低于 1）。例如加法画像 level 4（映射 L8）、减法未评估 → 减法初始 L7；反之亦然。兄弟维度也为 0 → L1。这样避免孩子加法已到 L8、减法却从 L1 重新开始的「假装初学」。

**乘除轨（10 级）**：分别映射乘法、除法画像，再按课程顺序取：

| 画像 level | 0 | 1 | 2 | 3 | 4 | 5 |
|------------|---|---|---|---|---|---|
| 乘法映射 | 1 | 1 | 3 | 5 | 6 | 7 |
| 除法映射 | 1 | 1 | 8 | 9 | 10 | 10 |

- 初始 = **max(乘法映射级, 除法映射级)**；两者都为 0 → 1。
- 理由：避免「乘法强、除法刚起步」的孩子被卡在低乘法级重复刷题；MD8 表内除法只依赖乘法口诀，不依赖多位数乘法，所以跳过 MD5–MD7 不会造成知识断层。
- 若 max 让首题偏难，两次都错会按 §5.2 降一级，状态机自校正。

**比较**：`0→1, 1→2, 2→3, 3→4, 4→5, 5→6`。
**认钟 / 经过时间**：都用 `math_time`，`0→1, 1→1, 2→2, 3→2, 4→3, 5→4`。

画像读不到时默认 1 级；读画像失败不阻塞出题（静默降级到 1 级）。

### 5.5 与画像的关系

- 进度表是**细粒度权威**；画像 0–5 是**粗粒度摘要**。
- AI 通过 `child_profile(action:"update")` 改画像，**不会**改进度表；反之进度推进也不自动改画像（画像仍由 AI 观察更新）。
- 家长清空画像不应清空进度（本期无重置入口）。

---

## 6. 数据存储

### 6.1 `math_quiz_records`

```sql
CREATE TABLE IF NOT EXISTS math_quiz_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at INTEGER NOT NULL,
  session_id TEXT DEFAULT '',
  tool_call_id TEXT DEFAULT '',
  quiz_type TEXT NOT NULL,
  track TEXT NOT NULL,
  level INTEGER NOT NULL DEFAULT 0,
  purpose TEXT NOT NULL DEFAULT 'practice',
  skill_key TEXT DEFAULT '',
  expression_key TEXT NOT NULL DEFAULT '',
  expression TEXT DEFAULT '',
  question TEXT DEFAULT '',
  correct INTEGER NOT NULL DEFAULT 0,
  first_try INTEGER NOT NULL DEFAULT 0,
  attempts INTEGER NOT NULL DEFAULT 0,
  child_answer TEXT DEFAULT '',
  correct_answer TEXT DEFAULT '',
  counted INTEGER NOT NULL DEFAULT 0,
  metadata_json TEXT DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_math_quiz_records_track_time
  ON math_quiz_records(track, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_math_quiz_records_session_purpose
  ON math_quiz_records(session_id, purpose);
```

- `expression_key`：去重键。算术 = `sanitizeExpression` 后去空白、`×→*`、`÷→/`；比较 = `cmp:<left>:<right>`；认钟 = `clock:<h>:<m>`；经过 = `elapsed:<sh>:<sm>-<eh>:<em>`；其他 = `''`。
- `expression`：原始算式（应用题也存隐藏算式）；非算术题存规范化可读串。
- `child_answer` / `correct_answer` 一律存字符串（数字也 `String()`），避免 SQLite 类型混杂。
- `counted`：本次是否推进了进度（practice + 级别匹配 + 已写入进度）。
- `metadata_json`：预留（`current_streak`、选项数等），本期写 `''`。

### 6.2 `math_quiz_progress`

```sql
CREATE TABLE IF NOT EXISTS math_quiz_progress (
  track TEXT PRIMARY KEY,
  current_level INTEGER NOT NULL DEFAULT 1,
  correct_at_level INTEGER NOT NULL DEFAULT 0,
  consecutive_wrong INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL
);
```

写入用 `relationalStore.ConflictResolution.ON_CONFLICT_REPLACE`（项目已在 `gifts` 种子写入用过），或先查后 update。

### 6.3 查询

- `getRecentMathQuizRecords(track, 20)`：`track = ? ORDER BY created_at DESC, id DESC LIMIT 20`，走 `(track, created_at DESC)` 索引；`id` 作同毫秒并列时的稳定次序。
- `countMathQuizPurposeInSession(sessionId, purpose)`：`session_id = ? AND purpose = ? AND level > 0`。
- `getMathQuizProgress(track)`：主键查。
- 作答写入用 `DatabaseService.recordMathQuizAnswer(record, progress | null)`：同一 `beginTransaction()` 里 insert 记录 + upsert 进度，失败 `rollBack()`。若 SDK 的 RdbStore 事务接口不可用，退化为顺序写（记录先、进度后）并打日志。
- 所有写失败都**不阻塞**工具结果：卡片照常回传，只是进度可能滞后；下一次闸门用旧进度。

### 6.4 生命周期

- 表随 `DatabaseService.createTables` 的 `CREATE TABLE IF NOT EXISTS` 自动创建，无需版本迁移。
- 不设过期清理；记录量 = 每次 math_quiz 一行，单儿童使用可接受。
- 不纳入 WebDAV/导出（§2）。

---

## 7. 出题闸门

### 7.1 调用位置

`ToolExecutionService.handleMathQuiz`（当前约 725–812 行）：

1. 保留现有 `validateMathQuizArgs(toolCall.arguments)`。坏题仍回 `validation_failed`。
2. **新增** `const gate = await getMathQuizHistoryService().evaluateGate(toolCall.arguments, context.sessionId)`。
3. `gate.ok === false` → `toolCall.approvalState='denied'`，返回 `MathQuizGateError` 的 `ToolResult`（`should_retry: true`），**不进 pending**。
4. `gate.ok === true` → 照旧进 pending、等待 `onAnswer`。
5. 收到答案后：
   - `const hint = await getMathQuizHistoryService().recordAnswer(toolCall.arguments, answerJson, context.sessionId)`；
   - `this.recordStarEvent('math_quiz', toolCall, context, answerJson)`（保持原样，answerJson 不含 hint）；
   - `toolCall.approvalReason = answerJson`（保持纯答案，UI 恢复依赖它）；
   - 返回的 `ToolResult.content` = `answerJson` 合并 `{"math_progress": hint}`（hint 为 null 时不合并；`JSON.parse(answerJson)` 失败时原样返回，不影响作答）。

现有工具调用是**串行**的（`ToolExecutionService.executeToolCalls` 用 `for` + `await`），同一轮的第二道 math_quiz 会在第一道作答后才进闸门，因此「最近 20 条」能查到第一道。若未来改成并行，需补内存 pending 去重（§12）。

### 7.2 闸门决策

`evaluateGate` 流程：

```
parse args → purpose = normalizePurpose(args.purpose)
info = resolveMathQuizLevel(args)
if !info.gate:
    return ok（shape / 无法判级的数数题）
if info.error != '':
    return reject('difficulty_gate', info.error)
progress = await getEffectiveProgress(info.track)   // 无行则按画像算，不写
if purpose == 'practice':
    if info.level < progress.current_level: reject(too_easy)
    if info.level > progress.current_level: reject(too_hard)
    if info.expressionKey != '':
        recent = await db.getRecentMathQuizRecords(info.track, 20)
        if recent 中存在相同 expression_key: reject(duplicate)
else:
    if info.level > progress.current_level: reject(too_hard_for_purpose)
    count = await db.countMathQuizPurposeInSession(sessionId, purpose)
    if count >= quota(purpose): reject(quota_exhausted)
return ok
```

- 闸门只做**难度**判断；题目答案正确性、选项是否含答案等仍由 `validateMathQuizArgs` 负责，顺序不能反（先校验坏题，再查难度）。
- `warm_up` / `review` 允许同算式重复；`practice` 不允许。
- 若 `getRecentMathQuizRecords` 查询失败，降级为「不做去重，仍做级别判断」并打日志——不因 DB 异常阻断出题。

### 7.3 拒绝返回体

**太简单：**

```json
{
  "error": "difficulty_gate",
  "should_retry": true,
  "message": "当前加法目标难度 L7（1000 以内不进位/不退位，如 213 + 124）。你出的题是 L5，太简单了。请按 target 重新出题，不要降低难度。如果这是热身/复习，请把 purpose 设为 warm_up 或 review（有每会话配额）。",
  "target": {
    "track": "add",
    "level": 7,
    "label": "1000 以内不进位/不退位",
    "max_operand": 999,
    "steps": "1",
    "carry": "none",
    "example": "213 + 124"
  },
  "progress": {
    "correct_at_level": 3,
    "needed": 10,
    "consecutive_wrong": 0
  }
}
```

**太难：**

```json
{
  "error": "difficulty_gate",
  "should_retry": true,
  "message": "当前目标 L5（100 以内进位/退位），你出的 L9 太难了。请按 target 重新出题。",
  "target": { "...": "同上结构" },
  "progress": { "...": "同上" }
}
```

**同算式重复：**

```json
{
  "error": "duplicate_question",
  "should_retry": true,
  "message": "这道题（47 + 28）在最近 20 道加法题里做过了。请保持 L5 难度，换一组数字。",
  "target": { "...": "L5 spec" }
}
```

**配额用完：**

```json
{
  "error": "purpose_quota_exceeded",
  "should_retry": true,
  "message": "本会话 warm_up 已用 5 道，不能再热身了。请改用 purpose='practice'，按 target 出正式练习。",
  "target": { "...": "当前目标 spec" }
}
```

**应用题缺隐藏算式：**

```json
{
  "error": "difficulty_gate",
  "should_retry": true,
  "message": "应用题（word_problem=true）也必须填 expression（如「3 + 2」）用于难度判定和答案复算；卡片仍然只显示 question，不会把算式显示给孩子。",
  "target": { "...": "当前目标 spec" }
}
```

**skill_key 与运算不符：**

```json
{
  "error": "difficulty_gate",
  "should_retry": true,
  "message": "skill_key=math_multiply，但算式是加法。请修正 skill_key 或把算式改成乘法。",
  "target": { "...": "当前目标 spec" }
}
```

所有 `message` 都保持「当前目标 + 你出的级别 + 下一步怎么做」三段式；`target` 必须可执行。

---

## 8. 回传给 LLM 的进度提示

### 8.1 作答后的 `math_progress`

`ToolResult.content` 在纯 `answerJson` 后附加：

```json
{
  "answered": true,
  "correct": true,
  "attempts": 1,
  "...": "原有 MathQuizAnswerPayload 字段不变",
  "math_progress": {
    "track": "add",
    "level": 7,
    "level_label": "1000 以内不进位/不退位",
    "correct_at_level": 4,
    "needed": 10,
    "consecutive_wrong": 0,
    "status": "in_progress",
    "reason": "first_try_correct",
    "next_target": {
      "track": "add",
      "level": 7,
      "label": "1000 以内不进位/不退位",
      "max_operand": 999,
      "steps": "1",
      "carry": "none",
      "example": "213 + 124"
    }
  }
}
```

`status` 取值：

| status | 含义 |
|--------|------|
| `in_progress` | 同一级继续（含第二次答对、单次两错未降级） |
| `level_up` | 刚升一级；`level`/`next_target` 已是新级 |
| `level_down` | 刚降一级 |
| `max_level` | 已在最高级，继续累计 |
| `not_counted` | warm_up / review / 作答级别与当前级不匹配 |

`reason`：`first_try_correct` / `second_try` / `two_wrong` / `warm_up` / `review` / `stale_level`。

warm_up/review 的 `math_progress.level` 回的是**当前目标级**（不是热身题的较低级），`next_target` 也是当前正式练习目标。不闸门题型（shape / 小数 / 无算式数数题）返回 `null`，不合并 `math_progress`。

UI 安全：`MathQuizCard` 已答题恢复读 `toolCall.approvalReason`（纯 `answerJson`）；`resolveStepAnswerPayload` 优先 `toolApprovalReason`。`ToolResult.content` 里的 `math_progress` **不会**被卡片读取，也不会造成「再试一次」误判。

### 8.2 `child_profile` 读取时返回 `mathProgress`

`ChildProfileExecutor` 的 `read` 分支在现有 `ChildProfileSummary` 上增加一个 `mathProgress` 字段（数组，每轨一项）：

```json
{
  "childName": "小明",
  "skills": [ "..." ],
  "mathProgress": [
    {
      "track": "add",
      "level": 7,
      "label": "1000 以内不进位/不退位",
      "correct_at_level": 4,
      "needed": 10,
      "nextTarget": { "...": "同 §8.1 的 next_target" }
    },
    { "track": "muldiv", "...": "..." }
  ]
}
```

- 只读，失败返回 `[]`，不影响画像读取。
- 模型开局 `child_profile(action:"read")` 即可知道该出什么难度，减少第一次闸门拒绝。
- 现有 camelCase 输出风格不变（`mathProgress`，不是 `math_progress`）。`nextTarget` 的**外层键**沿用 camelCase，内部字段与闸门 `target` 相同（snake_case），避免两套 target 结构。

### 8.3 提示词契约

在 `KIDS_MATH_SYSTEM_PROMPT` 的「出题契约」段追加（`DEFAULT_ASSISTANT_SYSTEM_PROMPT` 数学段加精简版）：

1. 每次正式练习 `math_quiz` 必带 `skill_key` 与 `purpose`（默认 `practice`）。
2. `practice` 必须严格按 `child_profile` 里的 `mathProgress[].nextTarget` 出题；不要低于目标级。
3. 五步课的复习/热身用 `purpose:"warm_up"`（每会话最多 5 题）；单元复习用 `purpose:"review"`（最多 3 题）；二者不计入掌握。
4. 收到 `error:"difficulty_gate"` / `"duplicate_question"` 时，按 `target` 的 `label` / `example` / `max_operand` 重出，不要争辩、不要保持原题。
5. 应用题 `word_problem=true` 也要填隐藏 `expression`。
6. 孩子第二次才答对，不算掌握；继续同级。两题都两次错，系统会自动降级，按新的 `next_target` 出题。
7. 不要在文本里向孩子解释「难度级别 / L7 / 进度」——这些是给老师看的内部状态。

---

## 9. 工具 schema 变更

`config/BuiltinTools.ets` 的 `MathQuizArgs` 与 `rawSchemaJson`：

```json
"purpose": {
  "type": "string",
  "enum": ["practice", "warm_up", "review"],
  "description": "practice=正式练习（默认，必须匹配当前目标难度，计入掌握进度）；warm_up=热身（可低于当前难度，不计入进度，每会话最多 5 题）；review=复习（可低于当前难度，不计入进度，每会话最多 3 题）。"
}
```

同时修改：

- `expression` 描述：去掉「应用题 expression 留空」，改为「应用题也必须填隐藏算式，卡片不会显示」。
- `skill_key` 描述：改为「强烈建议填写；决定难度轨与画像维度；优先用 math_addition / math_subtraction / math_multiply / math_divide / math_comparison / math_time / math_word_problem / math_counting / math_number_sense / math_shapes。历史短名（addition / subtraction / multiply / divide / shapes / comparison / time / counting / number_sense / word_problem）会被自动归一；未知值按空处理并由算式推断。」
- `AssistantModels.ets` 基础提示词第 62 行的数学维度列表同步改成 canonical `math_*`（当前是短名，且漏了 `math_word_problem`）；同时把 type 列表里的 `word_problem` 去掉（它是 arithmetic 上的布尔字段，不是第六种 type）。
- 工具 `description` 末尾加一句：`Set purpose (default practice) and skill_key; practice questions must match the child's current target level returned by child_profile.mathProgress or the difficulty_gate retry payload.`

`MathQuizExecutor.execute` 仍是 stub，不需要改逻辑；`MathQuizResult` 不需要加字段。

---

## 10. 触点文件

| 文件 | 改动 |
|------|------|
| `models/MathQuizProgressionModels.ets`（新建） | `MathQuizTrack` / `MathQuizPurpose` / `MathQuizLevelSpec` / `MathQuizRecordInsert` / `MathQuizRecordRow` / `MathQuizProgressRow` / `MathQuizTarget` / `MathQuizProgressHint` |
| `utils/MathQuizProgression.ets`（新建） | 级别判定、spec 表、`applyMathQuizProgress`、`initialLevelForTrack`、`normalizeExpressionKey`、`buildTarget`、`normalizePurpose` |
| `services/MathQuizHistoryService.ets`（新建） | `evaluateGate` / `recordAnswer` / `getEffectiveProgress` / `getProgressSummary`；单例 `getMathQuizHistoryService()` |
| `services/DatabaseService.ets` | `TableNames` 加两表；建表 SQL + 索引；`insertMathQuizRecord` / `getRecentMathQuizRecords` / `countMathQuizPurposeInSession` / `getMathQuizProgress` / `upsertMathQuizProgress` / `recordMathQuizAnswer`（事务） |
| `services/ToolExecutionService.ets` | `handleMathQuiz` 闸门 + 作答记录 + `math_progress` 合并；`recordStarEvent` 不变 |
| `config/BuiltinTools.ets` | `MathQuizArgs.purpose`；schema 描述；`ChildProfileSummary.mathProgress` + read 分支填充 |
| `models/AssistantModels.ets` | `KIDS_MATH_SYSTEM_PROMPT` 出题契约；`DEFAULT_ASSISTANT_SYSTEM_PROMPT` 数学段精简版 |
| `services/ServiceRegistry.ets` | 可选：`static mathQuizHistory()` 门面（若其他服务需要；`handleMathQuiz` 直接 import 也可） |
| `entry/src/ohosTest/ets/test/utils/MathQuizProgression.test.ets`（新建） | 纯函数单测 |
| `.claude/rules/teaching-architecture.md` | 实现后补 math_quiz 进度段（§4 工具生态） |

**不需要改：** `MathQuizCard.ets`、`MessageBubble.ets`、`MathQuizGame.ets`、`MathQuizValidation.ets`、`StarRewardService.ets`、`StarEventModels.ets`、`ChildProfileService.ets`、备课/评估服务。

---

## 11. 测试

### 11.1 纯函数（hypium，`entry/src/ohosTest/ets/test/utils/MathQuizProgression.test.ets`）

**加减判级：**

- `7 + 2` → L1；`8 + 7` → L3；`12 + 5` → L2；`47 + 28` → L5；`47 + 28 − 15` → L6；`213 + 124` → L7；`487 + 265` → L8；`4876 + 2657` → L11；`21345 + 12432` → L13；`48765 + 26578 − 13042` → L15。
- `63 − 27` → L5（退位）；`503 − 178` → L8（退位）；`568 − 235` → L7（不退位）。
- `9 + 9` → L3（结果 18 > 10，不是 L1）。
- `3 − 5 + 10` → error（中间 −2）；`10 − 3 + 5` → L3（中间 7、结果 12，≤20 的两步混合按 §4.2 落 L3）。
- `99999 + 1` → error（结果 100000 超范围）。
- `1.5 + 2` → `track='none'`，不闸门。

**乘除判级：**

- `2 × 2` → MD1；`10 × 3` → MD1（较大因数 10）；`2 × 3` → MD2（较大因数 3）；`1 × 7` → MD1（含 1 特判）；`4 × 6` → MD2；`7 × 8` → MD3；`3 × 7` → MD3。
- `20 × 3` → MD4；`23 × 3` → MD5；`27 × 3` → MD6；`213 × 3` → MD7。
- `12 ÷ 3` → MD8；`15 ÷ 5` → MD8；`24 ÷ 4` → MD8；`84 ÷ 4` → MD9；`369 ÷ 3` → MD10；`12 × 3 + 8` → MD10；`12 ÷ 3 + 8` → MD10。
- `23 × 4` → MD6（4×3=12 进位）；`7 × 6` → MD3（较大因数 7）。
- `20 × 30` → error；`10 ÷ 3` → error（不整除）；`7 ÷ 2` → error（商 3.5，带余数）。
- `213 × 1` / `23 × 1` / `20 × 1` → error（乘数必须 2–9）；`5 ÷ 1` → error（除数必须 2–10）。

**比较 / 时间：**

- `5 vs 3` → P1；`15 vs 3` → P2；`999 vs 3` → P4；`99999 vs 3` → P6。
- `3:00` → C1；`3:30` → C2；`3:15` → C3；`3:55` → C4；`3:12` → error（非 5 分钟刻度）。
- `3:10→3:40` → E1；`3:00→4:00` → E2；`3:30→4:15` → E3；`11:30→1:15` → E4；`3:10→3:10` → error；`3:40→3:10` → error（负时长）；`3:10→3:12` → error（非 5 分钟刻度）。

**轨道/技能匹配：**

- `skill_key=math_addition` + `3 − 2` → error。
- `skill_key=math_subtraction` + `3 + 2` → error。
- `skill_key=math_multiply` + `3 + 2` → error。
- `skill_key=math_divide` + `3 × 2` → error。
- `skill_key=addition` + `3 + 2` → `add`（短名归一）。
- `skill_key=multiply` + `3 × 2` → `muldiv`（短名归一）。
- `skill_key=foo` + `3 + 2` → `add`（未知值按空，由算式推断，不拒绝）。
- `skill_key=math_word_problem` + `3 + 2` + `word_problem=true` → `add`。
- `skill_key=math_time` + `type=elapsed_time` → `elapsed`。
- `skill_key=math_shapes` + `type=shape` → `shape`，不闸门。
- `skill_key=math_shapes` + `type=arithmetic` + `3 + 2` → error（题型不符）。

**进度状态机：**

- 9 次首答对 + 第 10 次首答对 → 升级、`correct_at_level=0`。
- 9 次首答对 + 第二次答对 → 不升级、`correct_at_level` 不变、`consecutive_wrong=0`。
- 两次都错 → `consecutive_wrong=1`；再来一次两次都错 → 降级、两个计数归零。
- 单次两次都错 + 首答对 → `consecutive_wrong=0`、`correct_at_level+1`。
- 最高级 10 次首答对 → 不越界；两次都错 → 降一级。
- `counted=false`（warm_up / review / 级别不匹配）→ 状态不变。
- 1 级两次都错 → 等级仍 1、`consecutive_wrong=0`。

**初始化：**

- 画像加法 level 0/1/2/3/4/5 → 1/2/3/5/8/11。
- 乘法/除法画像组合 → MD 初始级（含「乘法 MD7 + 除法 MD9 → 9」）。
- 缺失画像 → 1。

**去重键：**

- `47 + 28` ≡ `47+28`；`47 + 28` vs `47 + 29` 不同；`6 × 7` ≡ `6×7`。
- `×`/`÷` 归一为 `*`/`/`。
- 比较/时钟/经过的 canonical key 稳定。

### 11.2 手动验收

1. 新会话 → `child_profile read` → `mathProgress` 有 6 条（add/sub/muldiv/compare/clock/elapsed），级别符合画像。
2. 出低于目标的 practice → 卡片不出现，模型收到 `difficulty_gate`，按 target 重出后卡片出现。
3. 同一算式 practice 连出两次 → 第二次被 `duplicate_question` 拒绝。
4. 首答对 10 次 → 第 11 题目标升一级；第二次答对不计；两次都错两次 → 降一级。
5. `purpose=warm_up` 出低难度 → 卡片出现，答对后 `math_progress.status='not_counted'`，进度不变；第 6 道 warm_up 被配额拒绝。
6. 应用题不填 expression → 拒绝；填了隐藏 expression → 卡片只显示 question，判级正确。
7. `7 ÷ 2` / `20 × 30` / `3 − 5 + 10` → 拒绝，卡片不出现；`1.5 + 2` → 卡片出现，`track='none'` 记录。
8. `skill_key=addition`（短名）→ 正常判 `add`；`skill_key=foo` → 由算式推断，不拒绝。
9. 杀掉 App 重开 → 进度与最近记录仍在；同一 skill 在 `default` 与 `kids_math` 会话间连续。
10. 答完题后旧会话重开 → 卡片正常恢复为已答态，不出现「再试一次」。
11. `type=shape` / 小数题 → 可出，记录 `level=0`，不闸门。

---

## 12. 边界与已知取舍

| 取舍 | 说明 | 理由 |
|------|------|------|
| 最近 20 条按**同轨**而不是全局 | 加减/乘除/比较各自查询 | 全局 20 条会被单一轨道刷满，跨轨比较无意义 |
| 进度表 + 最近 20 条双轨 | 进度表记掌握，最近 20 条做去重/上下文 | 只靠最近 20 条会在降级后因旧的高级别正确记录立刻再升级；进度表避免这个回弹 |
| 最高级两次都错会降一级 | 允许降级 | 与「连续错就退回」一致；避免卡在最高级空耗 |
| warm-up/review 仍授星 | 不改 `recordStarEvent` | 避免改动星星规则引发「答对没星」体验回退 |
| warm-up/review 配额 5/3 | 每会话 | 防止用热身绕过闸门；同时够五步课开场复习 |
| 应用题语言难度不计 | 只用隐藏算式判级 | 本期不引入文本难度模型 |
| 乘除合并一条轨 | 按用户批准的 10 级课程序列 | 画像仍分乘法/除法，初始级按 §5.4 的课程顺序映射 |
| 乘除混合 MD10 不再细分 | 2–3 步含 ×/÷ 都归 MD10 | 用户批准的阶梯只有一个混合级 |
| 不回溯 `tool_events` 历史 | 上线后从画像初始化 | 旧记录无级别、解析成本高；首次使用会从画像级起步 |
| 并发/排队旧卡不计进度 | 作答时级别 ≠ 当前级 → `counted=0` | 防止旧卡把新级计数打乱 |
| 新表不进备份 | 与 `star_events` 一致 | 换机后从画像重新初始化 |
| 闸门对所有助手生效 | 不只 `kids_math` | `math_quiz` 本就是儿童教学工具；自定义助手若启用也应有难度约束 |

---

## 13. 验收清单

- [ ] `math_quiz_records` / `math_quiz_progress` 建表成功，索引存在
- [ ] 每次作答（含 warm-up/review/不闸门题型）都落一行记录
- [ ] practice 低于目标 → `difficulty_gate`，卡片不渲染
- [ ] practice 高于目标 → `difficulty_gate`
- [ ] practice 同轨最近 20 条同 `expression_key` → `duplicate_question`
- [ ] warm-up/review 可低于目标、不计进度、不降级
- [ ] warm-up 第 6 题 / review 第 4 题 → `purpose_quota_exceeded`
- [ ] 首答对 10 次 → 升级；第二次答对不计；两次都错 ×2 → 降级
- [ ] 升级后旧卡作答 → `counted=0`，不污染新级
- [ ] 应用题缺隐藏 expression → 拒绝；有则判级正确
- [ ] 带余数 / 多位数 × 多位数 / >99,999 / 负数中间结果 → 拒绝，卡片不渲染
- [ ] 小数题（操作数含小数点）→ `track='none'` 记录，不闸门
- [ ] 短名 `skill_key`（如 `addition`）归一后正常判轨；未知值由算式推断
- [ ] compare / clock / elapsed 的拒绝回传 `target.constraint`，按 target 重出能过闸门
- [ ] `child_profile read` 返回 `mathProgress`，开局首题即可命中目标
- [ ] 作答后 `ToolResult.content` 含 `math_progress`；`approvalReason` 仍为纯答案
- [ ] 旧会话重开卡片正常，不误判「再试一次」
- [ ] `MathQuizCard` / `MessageBubble` / 星星规则 / 备课评估无改动
- [ ] 纯函数测试全部通过

---

## 14. 我的判断（实现时可按此落地，用户可推翻）

1. **轨道拆法**：加减分 `add` / `sub` 两轨，乘除合并 `muldiv` 一轨——用户批准的 15 级加减和 10 级乘除序列原样保留；加减分轨是因为画像本来就分加/减，乘除合并是因为批准的阶梯是一条「先乘后除」课程线。
2. **最近 20 条按同轨**：不是全局 20 条。
3. **进度表是权威，最近 20 条只做去重/上下文**：避免降级后旧记录导致立即回弹。
4. **初始级映射表**：§5.4 的 0–5 → 级别映射是校准值，不是用户逐项确认的；第一周若发现偏高/偏低，只改映射表，不改状态机。
5. **乘除初始级取 max**：乘法/除法画像各自映射后取较高者，优先避免「已经会了还从低处刷」；偏难由两次都错降级自校正。
6. **`purpose` 配额 5/3**：warm_up 5、review 3，按会话。
7. **`child_profile` 增加 `mathProgress`**：这是减少首次闸门拒绝的关键，改动小、只读、失败降级。
8. **MD1–MD3 按较大因数的口诀组**：`2 × 3` 属 MD2（3 的口诀），`10 × 3` 属 MD1；含 1 的乘法一律 MD1，避免刷高年级。除法只从 MD8 开始。
9. **结构性错误三种 purpose 都拒绝**：带余数、多位数 × 多位数、>99,999、负数中间结果、gated 算术缺 expression。热身/复习的例外只放宽「低于目标级」，不放宽题型。小数题（操作数含小数点）走 `track='none'`，不闸门。
10. **非算术轨的 target 带 `constraint`**：compare/clock/elapsed 的 spec 用 `constraint` 描述级别规则，target 输出 `label` / `constraint` / `example`，避免模型重出仍然不合规。
11. **skill_key 归一**：短名（`addition` 等）映射到 `math_*`；未知值按空并由算式推断，不拒绝。
12. **负数中间结果在 resolver 拦**：`validateMathQuizArgs` 只查最终值，`3 − 5 + 10` 会被漏掉。
13. **不做历史回填**：上线后从画像级起步。
14. **闸门对所有助手生效**：不按 assistantId 白名单。
15. **最高级允许降级**：不设「最高级只升不降」。

---

**前置文档：** `.claude/rules/teaching-architecture.md`
**相关文档：** `.claude/rules/vertical-math-help-sheet.md`（草稿纸与竖式帮助）、`docs/superpowers/specs/2026-09-26-math-teach-suite-design.md`（数学讲解套件）
