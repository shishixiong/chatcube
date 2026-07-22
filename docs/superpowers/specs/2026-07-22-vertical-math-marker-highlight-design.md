# 竖式计算当前进位/借位标记高亮设计

**日期：** 2026-07-22
**范围：** `VerticalMathBoard` 中加法进位 `1` 与减法借位 `•` 的当前步骤视觉反馈
**状态：** approved for implementation

## 1. 目标

当孩子正在计算一个高位、且该列使用了之前产生的进位或借位时，高亮对应的顶部 `1` 或 `•` 标记。加法和减法都支持。刚产生但尚未被下一列使用的标记不应提前高亮；“得到答案”最终步骤没有当前计算列，不显示高亮。

## 2. 现有数据关系

`VerticalMathStep.highlights` 为当前步骤的单元格高亮，行 0 是被减数/被加数行。`VerticalMathBoardRow.carryColumns` 和 `borrowColumns` 是当前快照中已经存在的顶部标记列。

因此，当前顶部标记是否活跃由以下条件决定：

- 当前步骤的行 0 `kind === 'active'` 高亮提供当前计算列。
- 该列存在于当前行的 `carryColumns` 或 `borrowColumns` 中。
- 仅对应类型的顶部标记进入高亮状态。

不直接使用当前步骤的 `kind === 'carry'`/`'borrow'` 高亮来判断，因为这些高亮表示本步骤产生的进位/借位目的列；加法中它们出现在低位产生进位的步骤，而不是下一步真正使用进位的高位步骤。

## 3. 实现方案

只修改 `entry/src/main/ets/components/verticalMath/VerticalMathBoard.ets`：

1. 从 `getCurrentHighlights()` 找到行 0 的 active 列；没有 active 列时返回无效列。
2. `TopMark` 渲染 carry/borrow 数组时，为每个 marker 计算是否为当前列。
3. 扩展 `TopMarkAt` 接收 `isActive` 参数。
4. 活跃 marker 使用 `VERTICAL_MATH_ACTIVE_BG` 作为背景，并保留原有 `VERTICAL_MATH_CARRY_TEXT`/`VERTICAL_MATH_BORROW_TEXT` 文字色；非活跃 marker 的外观保持不变。背景使用小圆角和固定 marker 尺寸，避免改变列对齐。
5. legacy 单个 `topMark` 路径也复用同一 active 判断，保持兼容。

不新增 solver 字段、不新增 highlight kind、不修改工具协议或卡片状态机。

## 4. 验证

- 增加/更新纯 solver 断言，确认 `47 + 28` 的低位步骤产生 carry marker，但高位步骤的 active 列与持久 marker 列重合；最终步骤没有 active 列。
- 确认 `303 - 178` 的借位链在当前处理列与持久 `borrowColumns` 重合时满足同一关系。
- 通过 ArkTS 编译构建 `assembleHap`。
- Hypium CLI 当前因项目既有测试工程路径问题不可用；测试结果继续记录为 DevEco Studio GUI 待运行，并进行源码断言/手工追踪。

## 5. 非目标

不改变进位/借位的生成算法、步骤数量、叙述文字、结果回传、卡片重挂载行为或其他竖式运算类型的视觉规则。
