# 竖式计算:首步直达计算 — 设计

**日期:** 2026-07-21
**版本:** v1
**范围:** `entry/src/main/ets/utils/VerticalMathSolver.ets` 的四种运算求解器,以及 `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets` 的相关测试。
**目标:** 消除"数位对齐"独立步骤,使首次"下一步"直接进入个位/最高位的计算,降低小星老师数学题的认知开销。

---

## 1. 背景

当前所有四种运算(add/sub/mul/div)都会在 `steps[0]` 推入一个 `title: '数位对齐'` 的独立步骤,只展示对齐好的题目和横线,不进行任何计算。用户从"开始计算"进入后,第一次"下一步"只会看到与初始棋盘完全相同的画面,需要再点一次才能开始真正的计算,体验冗余。

教学目标(已有):加、减、乘从个位开始算,除法从最高位开始算。**首步就是第一步计算**。对齐是隐含前提,不需要单独成步。

## 2. 目标

- **G1.** 求解器不再产生任何 `title: '数位对齐'` 的步骤。
- **G2.** "开始计算"后棋盘仍显示对齐好的题目与第一道横线(沿用现有 `initialRows` 行为)。
- **G3.** 加/减/乘:首次"下一步"展示个位计算(进位/借位标记按既有规则显示)。
- **G4.** 除法:首次"下一步"展示最高位的"试商"或"不够除"步骤。
- **G5.** `0 ÷ n` 的特殊路径首次"下一步"直接展示结果 `0`,不再插入任何中间步骤。
- **G6.** 不修改算术逻辑、视觉样式、卡片导航、`VerticalMathBoard.ets` 渲染器、结果 payload 结构或 `StarRewardService` 等周边。
- **G7.** 不动其他卡片、其他文件,不留孤儿测试。

## 3. 非目标

- 不重命名、合并或重排 `initialRows`。
- 不调整 `result` payload 中的 `step_count` 字段含义 — 它就是求解器返回的步骤数,自然少 1。
- 不改 `VerticalMathStep`/`VerticalMathBoardRow` 数据模型。
- 不改 `StepNarrator` 文案顺序,只是少一段。

## 4. 设计

### 4.1 数据层

四种求解器(`solveVerticalAdd`、`solveVerticalSubtract`、`solveVerticalMultiply`、`solveVerticalDivide`)中:

- 删除 `alignStep` 局部变量和 `steps.push(alignStep)`。
- 删除对应的 `alignRowA`/`alignRowB`/`alignRowLine` 中间变量。
- 删除函数顶部的 `// Step 1: alignment (no computation yet).` 注释。
- 文件头注释中"steps[0]: alignment narration"一句改为"steps[0]: first digit computation"或直接删去(按上下文;乘法/除法函数注释若不再准确就更新)。

**乘法特殊处理:** 当前 `solveVerticalMultiply` 用了 `steps: VerticalMathStep[] = [{...}]` 列表内联构造首个对齐步骤。改为以空数组初始化,然后 `for` 循环开始追加第一个部分积计算步骤即可。

**除法特殊处理:**

- 通用路径:删除 `alignStep` 与 `steps.push(alignStep)`,`for` 循环直接追加每个最高位的"不够除"或"试商"步骤。
- `a === 0` 特例:删除 `alignStep` 与 `steps.push(alignStep)`,让 `steps[0]` 直接是 `finalStep`(即首次"下一步"直接展示答案 `0`)。

### 4.2 步骤计数

| 题型 | 当前 `steps.length` | 修改后 `steps.length` | 修改后 `steps[0].title` |
|------|---------------------|-----------------------|-------------------------|
| `47 + 28` | 4 (对齐 + 个位 + 十位 + 答案) | 3 | "第 2 位相加" |
| `503 - 278` | 5 (对齐 + 个位 + 十位 + 百位 + 答案) | 4 | "第 3 位相减" |
| `988 × 6` | 5 (对齐 + 3 个部分积 + 答案) | 4 | "个:8×6=48" |
| `84 ÷ 4` | 4 (对齐 + 2 个试商 + 答案) | 3 | "第 1 位:试商 2" |
| `3 ÷ 7` | 4 (对齐 + 不够除 + 试商 0 + 答案) | 3 | "第 1 位:不够除" |
| `0 ÷ 5` | 2 (对齐 + 答案) | 1 | "得到答案" |

### 4.3 渲染器

`VerticalMathBoard.ets` 不变。`getCurrentRows()` 在 `visibleStepCount === 0` 时仍返回 `initialRows`,首次"下一步"进入 `steps[0]`,与现有 `getRowHighlights`/`shouldShowLine` 逻辑一致。

### 4.4 卡片层

`VerticalMathCard.ets` 不变。`handleNext` 仍按 `visibleStepCount` 推进;`step_count` 字段(从 `steps.length` 取)自动反映新长度。

## 5. 测试

`entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets`:

- `solveVerticalAdd` "47 + 28 = 75 with one carry":删除 `expect(s.steps[0].title).assertEqual('数位对齐')`,改为 `expect(s.steps[0].title).assertEqual('第 2 位相加')` 并相应调整后续索引断言。
- "marks each newly written addition result digit active": `for (let index = 1; index < s.steps.length - 1; index++)` 改为 `for (let index = 0; index < s.steps.length - 1; index++)`(原 index=1 现为 index=0,代表个位步)。
- "keeps carry columns on later snapshots": 索引从 `1/2/.../last` 改为 `0/1/.../last`。
- `solveVerticalSubtract` "503 - 278 = 225 with cascading borrow": 删除 `borrowSteps.length >= 2` 改为 `>= 1`(少了 1 步,等于触发数)。
- "keeps cascade borrow columns and marks each new result active": `for (let index = 1; ...)` 改为 `for (let index = 0; ...)`。
- `solveVerticalMultiply` "988 × 6 = 5928 with three aligned partial products": `expectedRows` 数量是 3,索引从 `index + 1` 改为 `index`。
- "marks every non-empty current partial-product cell active": `for (let index = 1; index <= 3; index++)` 改为 `for (let index = 0; index < 3; index++)`(或 `< partialRows.length`,由实现风格选择;取静态 `3` 与字段对应)。
- "marks each written quotient digit with the active quotient semantic": `for (let index = 0; index < quotientSteps.length; index++)` 内 `columnIndex === index` 在 `84 ÷ 4` 上仍然成立,无需改动;但总 `quotientSteps.length` 从 2 仍为 2,无变化。
- "84 ÷ 4 = 21 remainder 0": 不需索引改动。
- "0 ÷ 5 = 0 remainder 0": `s.steps.length` 断言(如存在)从 2 改为 1。

每个改动的索引断言必须用 `node -e` 一次性验证:`grep -n "s.steps\[" VerticalMathSolver.test.ets` + 索引一致性。

## 6. 验收

- [ ] 4 个求解器不再生成任何 `title: '数位对齐'` 步骤:`grep "数位对齐" entry/src/main/ets/utils/VerticalMathSolver.ets` 返回 0 匹配。
- [ ] 4 个求解器的 `steps[0]` 标题是"第 N 位..."/"个:..."/试商或不够除/得到答案。
- [ ] 所有现有 Hypium 测试在 DevEco Studio 跑通 37/37(本地仍 NOT RUN,DevEco-only)。
- [ ] `assembleHap` `BUILD SUCCESSFUL`。
- [ ] "开始计算"后棋盘与现有 `initialRows` 一致(肉眼检查或源对比)。
- [ ] 22 + 33、47 + 28、503 - 278、988 × 6、84 ÷ 4、0 ÷ 5 设备/模拟器 smoke 行为如 §4.2 表格。

## 7. 相关文件

| 路径 | 角色 |
|------|------|
| `entry/src/main/ets/utils/VerticalMathSolver.ets` | 唯一源改动 |
| `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets` | 测试索引/断言改动 |
| `docs/superpowers/specs/2026-07-19-vertical-math-calculator-design.md` | 前置 spec,需要回看其"先对齐再算"假设 |
| `docs/superpowers/specs/2026-07-20-vertical-math-card-visual-fixes.md` | 视觉修复 spec(无冲突) |
| `docs/superpowers/plans/2026-07-19-vertical-math-calculator.md` | 前置 plan,需要更新"对齐步骤"叙述(本任务外) |
