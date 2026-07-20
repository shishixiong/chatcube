# 竖式计算器卡片视觉修复

**日期：** 2026-07-20
**状态：** 已确认设计，待实施
**范围：** 已经上线的 `VerticalMathCard` 棋盘视觉与高亮语义修复；纯前端调整，不改动工具契约、不动求解器算法、不动星星奖励
**前置文档：** `docs/superpowers/specs/2026-07-19-vertical-math-calculator-design.md`（v1 设计）

---

## 1. 背景与目标

竖式计算器卡片已在聊天中跑通,但用户实测 22 + 33 时反馈三个具体体验问题:

1. **风格与 chat 页面难以融合** — 棋盘深紫渐变 (`#6448b5 → #27194f`) 跟项目其他卡片 (`NumberPuzzleCard`、`MathQuizCard`) 的浅米色气泡风格冲突,像被扔进另一套设计系统
2. **十位结果看上去写在个位位置** — 第二步算十位时,结果行的「新写入」格子没有视觉强调,跟空位看上去一模一样;只有第一步算好的个位结果因为 `done` 高亮可读
3. **进位/借位标记跨步消失** — 规范要求 carry/borrow 标记持续可见,但当前每个 step 重建 `rowA`/`rowB` 时不会继承历史标记,只有生成那一帧能看到

本期目标:

- 棋盘视觉语言回归项目「气泡」体系
- 高亮语义统一:四则运算的「新写入」格子用与正在计算的列相同的 active 强调
- Carry/Borrow 标记跨步骤持续显示

非目标:

- 不动求解器算法逻辑(数值正确性保持)
- 不动工具契约 / `onAnswer` 协议
- 不动星星奖励系统(仍然不接入)
- 不动 Narrator 组件(已经是奶油气泡,与新棋盘天然成对)
- 不改 `VerticalMathStep` 数据结构(只改 `solver` 输出内容,不改模型)

---

## 2. 已确认的设计决策

### 2.1 视觉方向

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 棋盘背景 | 与 Narrator 同奶油色 `VERTICAL_MATH_NARRATOR_BG` (`rgba(255, 250, 240, 0.86)`) | 两块合起来是一张卡片,拆开看仍然像同一个组件 |
| 棋盘边框 | `app.color.divider` 1px | 项目其他卡片通用边框 |
| 棋盘圆角 | 14vp | 匹配 `NumberPuzzleCard` 12-14vp 半径 |
| 删除原渐变 | 是 — `Board.ets` 的 `Stack { Column().linearGradient(...) }` 背景层整段删除,`build()` 顶层由 `Stack` 改为直接 `Column` | 不再需要深紫背景作为视觉锚点 |
| 棋盘文字色 | `VERTICAL_MATH_BOARD_TEXT` 常量由 `#ffffff` 改为深墨色 `#3a3320`(暖调深色,在奶油底上清晰) | `Board`/`BoardRow` 都是无主题依赖的纯色串组件,改常量即可同时修正普通格子文字 + operator 符号;不引入 `getAppUiState()` 依赖,深色模式作为 §6 遗留风险 |
| 横线颜色 | `VERTICAL_MATH_BOARD_LINE` 常量由 `rgba(255,255,255,0.9)` 改为半透明深色 `rgba(58, 51, 32, 0.55)` | 白线在奶油底不可见 |
| 棋盘内边距 | 14vp (compact) / 20vp (大尺寸) | 同原值,不变 |

### 2.2 高亮语义

四则运算统一使用 4 种 highlight kind,语义不变,渲染适配浅底:

| kind | 背景 | 文字 | 含义 |
|------|------|------|------|
| `active` | `#ffe66d`(荧光黄) | `#3a2d0c`(深褐) | 当前正在算的位 / 新写入的结果 |
| `done` | `rgba(185, 242, 208, 0.18)`(薄荷绿 18% 透) | `#15803d`(深绿) | 已算完的位 |
| `carry` | 透明 | `#dc2626`(红) | 进位 1 |
| `borrow` | 透明 | `#7c3aed`(紫) | 退位点 • |

> **渲染分工(自审修正)**:`active` / `done` 是**格子高亮**,由 `VerticalMathBoardRow.ets` 的 `getCellBackgroundColor` / `getCellTextColor` 按 `highlight.kind` 渲染;`carry` / `borrow` 不是格子高亮,而是**列上方的 topMark 标记**,由 `VerticalMathBoard.ets` 的 `TopMark` builder + `getTopMarkColor` 渲染。
>
> **颜色常量变更**(`VerticalMathColors.ets`):
> - `VERTICAL_MATH_DONE_TEXT`: `#b9f2d0`(浅薄荷,奶油底不可读)→ `#15803d`(深绿)
> - `VERTICAL_MATH_CARRY_TEXT`: `#ff6b6b`(浅珊瑚)→ `#dc2626`(深红)
> - **新增** `VERTICAL_MATH_BORROW_TEXT`: `#7c3aed`(紫)—— 当前 borrow `•` 复用 `VERTICAL_MATH_BOARD_TEXT`(白),改奶油底后会不可见,必须拆出独立紫色常量并在 `Board.getTopMarkColor` 中 `topMark === '•'` 分支引用它。

**关键修复**:每个 solver 在写入「当前列的结果」之后,给 `rowResult`(结果行)在 `columnIndex=col` 新增一条 `kind: 'active'` 的 highlight,与正在计算的 operand 列同色。这样十位结果写入时,会从空位变成黄色高亮的 `5`,视觉上立即可辨。

**新增 highlight 但保持现有结构**:

```ts
// 例: solveVerticalAdd 中 col=N 处理结果后
highlights.push({ rowIndex: 3, columnIndex: col, kind: 'active' })  // 新增
```

### 2.3 Carry / Borrow 跨步骤持续显示

**当前 bug 根因**:每个 step 都从求解器内部新建 `rowA` / `rowB` 对象(每次 `cloneCells(aCells)`),`topMark` 是当前帧的属性,不带历史。

**修复方案 — 用集合保存所有历史标记位**,然后在每帧 rowA 重建时把集合里所有列的 `topMark` 都继承下来:

```ts
// 加法
const carryColumns: Set<number> = new Set<number>()  // 整个求解过程中产生 carryOut 的所有 col

for (let col = columnCount - 1; col >= 0; col--) {
  // ...
  if (carryOut > 0 && col - 1 >= 0) carryColumns.add(col - 1)

  const rowA: VerticalMathBoardRow = {
    cells: cloneCells(aCells),
    // 关键：把历史 carry 全量拷贝到当前 rowA
    ...(carryColumns.size > 0 ? {
      topMark: '1',
      topMarkColumn: /* 继承来源 */,
      topMarkRowIndex: 0
    } : {})
  }
}
```

由于 `rowA.topMark` 当前只能存一个 column,需要扩展模型:

```ts
export class VerticalMathBoardRow {
  // 现有字段保留 (topMark / topMarkColumn / topMarkRowIndex) — 兼容单标记
  carryColumns?: number[]  // 新增：持久化 carry 的所有列
  borrowColumns?: number[] // 新增：持久化 borrow 的所有列
}
```

渲染时,`Board.getTopMark*` 看 `carryColumns` / `borrowColumns` 多列,循环渲染多个 topMark(每个独立一个小 `Text` 按列定位)。

**减法级联规则**:减法 borrow 级联时,`borrowColumns` 包含:
- 最终 donor(提供借位的非零高位)
- 中间被「扫过」的零位(被改成 `9` 的列)
- 当步触发 borrow 的列本身(`col`)

### 2.4 修复范围

| 运算 | 新增 result-active | 新增 carry/borrow 持续 |
|------|------------------|--------------------|
| 加法 | ✅ (每步 col) | ✅ (carryColumns) |
| 减法 | ✅ (每步 col) | ✅ (borrowColumns,含级联) |
| 乘法 | ✅ (整行 partial product) | N/A(无进位标记) |
| 除法 | ✅ (商的当前位 + 余数当前位) | N/A |

> 乘法的「整行 partial product 高亮」让当前乘数位运算时整行 partial 黄色显示,与规范 §5.3 「当前数字位和对应部分积使用荧光黄/绿色状态切换」一致。
> 除法的「商当前位」处理时给结果行 `finalRow` 那一列 active;余数高亮按现有规则。

---

## 3. 文件改动清单

| 文件 | 改动类型 | 估计行数 |
|------|---------|---------|
| `entry/src/main/ets/utils/VerticalMathColors.ets` | (1) 删 `VERTICAL_MATH_BOARD_BG_START/MID/END`(渐变不再使用)<br>(2) `VERTICAL_MATH_BOARD_TEXT` `#ffffff` → `#3a3320`<br>(3) `VERTICAL_MATH_BOARD_LINE` 白 → `rgba(58, 51, 32, 0.55)`<br>(4) `VERTICAL_MATH_DONE_TEXT` → `#15803d`<br>(5) `VERTICAL_MATH_CARRY_TEXT` → `#dc2626`<br>(6) 新增 `VERTICAL_MATH_BORROW_TEXT = '#7c3aed'` | -3 / 改 |
| `entry/src/main/ets/utils/VerticalMathSolver.ets` | (1) `VerticalMathBoardRow` 加 `carryColumns?: number[]` + `borrowColumns?: number[]`<br>(2) `solveVerticalAdd`:集合 + result-active + 持久化<br>(3) `solveVerticalSubtract`:同上加 borrow 级联持久<br>(4) `solveVerticalMultiply`:partial product 整行 active<br>(5) `solveVerticalDivide`:商的当前位 active<br>(6) `solveVerticalMath` 同样受影响(透传) | +50 / 改 |
| `entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets` | (1) `build()` 顶层由 `Stack{ Column().linearGradient(...) + Column{...} }` 改为直接 `Column{...}` + `.backgroundColor(VERTICAL_MATH_NARRATOR_BG)` + `.border({ width: 1, color: $r('app.color.divider') })` + `.borderRadius(14)`<br>(2) `getTopMarkOffset(column)` / `getTopMarkColor(row, mark)` 改:接收 `column` / `mark` 参数<br>(3) `getTopMarkColor` 的 borrow 分支引用新 `VERTICAL_MATH_BORROW_TEXT`(替代原 `VERTICAL_MATH_BOARD_TEXT`)<br>(4) `TopMark` builder 循环 `row.carryColumns` / `row.borrowColumns` 渲染多列(向后兼容原单 `topMark`) | ±20 |
| `entry/src/main/ets/components/verticalMath/VerticalMathBoardRow.ets` | 无代码逻辑改动 —— 普通格子文字 + operator 符号均已读 `VERTICAL_MATH_BOARD_TEXT`,随常量变深色自动修正 | 0 |
| `entry/src/main/ets/ohosTest/ets/test/VerticalMathSolver.test.ets` | 加 6 个测试覆盖:<br>• result-active 位置正确<br>• carry 跨步骤持续<br>• borrow 级联跨步骤持续<br>• multiplication partial-active<br>• division quotient-active | +50 行 |

**总计**:改动 4 个源文件 + 1 个测试文件,新增约 80 测试行、调整约 30 实现行。`VerticalMathBoardRow.ets` 无需改代码(靠常量变更生效)。

---

## 4. 验收清单

### 4.1 视觉

- [ ] 棋盘背景与 Narrator 同色(奶油色),两块合起来像一张卡
- [ ] 棋盘 1px divider 边框 + 14vp 圆角 + 14/20vp 内边距
- [ ] 棋盘数字深色,在奶油底上清晰可读
- [ ] 横线 `VERTICAL_MATH_BOARD_LINE` 半透明深色 `rgba(58,51,32,0.55)`(非纯白)
- [ ] 数字深色背景不再出现
- [ ] Narrator 视觉不变

### 4.2 高亮语义

- [ ] active = 荧光黄 + 深褐(列 + 新写入的结果同色)
- [ ] done = 薄荷绿 18% 半透底 + 深绿字
- [ ] carry = 红字(#dc2626)
- [ ] borrow = 紫字(#7c3aed)
- [ ] 加法 22+33:十位结果显示黄色 active,与正在计算的 2 / 3 列同色
- [ ] 加法 47+28:生成 `1` 的步骤,以及之后所有步骤都能看到 `1`
- [ ] 减法 503-278:级联的 0→9 列在后续步骤都标 `•`
- [ ] 乘法 988×6:某一步计算的 partial product 整行 active,与当前乘数位 active 同色
- [ ] 除法 84÷4:商的每一位写入时 active

### 4.3 数据契约

- [ ] `VerticalMathBoardRow` 加 `carryColumns?: number[]` 和 `borrowColumns?: number[]`,向后兼容原 `topMark*` 单列字段
- [ ] `solveVerticalAdd/Subtract/Multiply/Divide` 输出结构增加 `kind: 'active'` highlight 到 result 行
- [ ] 测试 JSON snap 不破坏旧断言(兼容旧测试)

### 4.4 测试

- [ ] 31 个旧测试全部通过(数值/位置/carry-out 等不变)
- [ ] ≥ 6 个新测试通过:
  - `solveVerticalAdd`:every result step has exactly one `kind='active'` highlight at `columnIndex=col`
  - `solveVerticalAdd carry case`:第二步 `rowA.carryColumns` 包含 col=0(从 col=1 的 carry 继承)
  - `solveVerticalSubtract cascade`:303-178 的级联中点(0→9)后续步骤仍标 borrow
  - `solveVerticalMultiply`:每步 partial product 行所有非空格 cell 都标 active
  - `solveVerticalDivide`:每步 `resultCells` 当前位 active
  - `Board` 渲染层:`VERTICAL_MATH_BOARD_TEXT` 常量值为深墨色 `#3a3320`(不再是 `#ffffff`);`getTopMarkColor` 的 borrow 分支引用 `VERTICAL_MATH_BORROW_TEXT`(紫)

- [ ] CLI `assembleHap` BUILD SUCCESSFUL
- [ ] DevEco Studio Hypium 测试全绿(仅能在 GUI 内运行)

---

## 5. 测试策略

**纯函数测试优先**(沿用现有约定):
- `VerticalMathSolver.ets` 的 4 个 `solveVertical*` 是纯函数,可直接 hypium 测试
- 新测试位于 `entry/src/ohosTest/ets/test/VerticalMathSolver.test.ets`,与现有 31 个测试并列

**集成测试(组件层)**:
- 与现有项目约定一致——组件层人工验收(在聊天中实测 22+33 / 47+28 / 503-278 / 988×6 / 84÷4),不再加组件自动化测试

**测试基础设施提示**:CLI `hvigorw test` 在本项目坏(参见 `MEMORY.md`),只能 DevEco Studio 内右键运行测试。如不能上 GUI,以 `assembleHap` BUILD SUCCESSFUL + 求解器单元测试的 `grep` 完整性验证为充分证据。

---

## 6. 风险与回退

| 风险 | 缓解 |
|------|------|
| `Board` 改 `Stack → Column` 可能影响手势穿透 | 现有版本没有手势捕获,纯视觉,无影响 |
| 多 topMark 渲染性能 (carry/borrow 跨多列) | 最多 3 列 × 1 行 × 1 step = 3 个 Text,无压力 |
| 改 `DONE_TEXT` 颜色值影响 Narrator 视觉 | Narrator 用 `VERTICAL_MATH_NARRATOR_DONE_TEXT`,与 `VERTICAL_MATH_DONE_TEXT` 是两个常量 — 不影响 |
| 奶油底棋盘在深色模式下对比度差 | 本期用固定深墨色常量 `#3a3320`(不跟随主题),深色模式下奶油底 + 深字仍可读但与深色 chat 页略有割裂;若后续需要,再引入 `getAppUiState().textPrimary` 主题 token(需给 `Board`/`BoardRow` 传主题),列为 §7 遗留项 |
| 改 borrow 复用 `BOARD_TEXT` → 独立紫常量遗漏 | 必须同步:新增 `VERTICAL_MATH_BORROW_TEXT` 常量 + `Board.getTopMarkColor` 的 `•` 分支切换引用,否则 borrow 会随 `BOARD_TEXT` 变深墨色而非紫色 |
| Solver 测试 snapshot 大改破坏旧测试 | 新断言只 ADD,不删/改;旧断言保持数值不变 |

**回退方案**:所有改动 commit 化(`utils/Color` 单独 commit、`Solver` 单独 commit、组件分别 commit),任意一处可独立 `git revert`。本期不发布到主分支,先在 `math_teacher` 合入验证。

---

## 7. 后续可优化(不阻塞本期)

- 多 carry 同时显示可加缓动动画(数字从上方落入)
- 数字 hover/focus 效果(移动端无意义,先不做)
- 高对比度模式(a11y)— 与项目统一约定后做
- 深色模式主题联动:棋盘文字改用 `getAppUiState().textPrimary` 而非固定深墨常量(需给 `Board`/`BoardRow` 组件传入主题)
