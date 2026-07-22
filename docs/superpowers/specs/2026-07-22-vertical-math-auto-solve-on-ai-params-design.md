# 竖式计算 AI 参数齐全时自动进入展示

**日期：** 2026-07-22
**范围：** `VerticalMathCard` 解析 AI 工具参数后直接进入竖式展示，跳过手动输入面板
**状态：** approved for implementation

## 1. 目标

当小星老师通过 `vertical_math` 工具传齐 `operation` / `operand_a` / `operand_b` 三个参数时，竖式卡片应直接进入计算展示，而不是先显示 28+33 这种占位输入面板、让用户再点一次“开始计算”。当参数缺失或非法时，仍保留原输入面板作为兜底。

## 2. 现有数据关系

`VerticalMathCard.aboutToAppear` 已经调用 `parseToolCallArguments()` 把工具参数解析到局部状态，并在 `isAnswered === true` 时提前 `regenerateSolution()`。`regenerateSolution` 走 `solveVerticalMath(operation, a, b)`，非法输入会得到带 `errorMessage` 的 solution，由组件渲染错误条；合法输入则进入竖式展示。

现在的问题是：当 `isAnswered === false`（交互态）且 `solution === null`（尚未求解）时，`build()` 永远渲染 `InputForm()`，不论 AI 参数是否齐备。

## 3. 实现方案

只修改 `entry/src/main/ets/components/VerticalMathCard.ets`：

1. 新增一个纯函数（文件私有），检查当前解析后的 `operation` / `operand_a` / `operand_b` 是否齐全且 `operand_a`、`operand_b` 是 0–999 的整数。`operation` 接受 `add` / `subtract` / `multiply` / `divide`。
2. 在 `aboutToAppear` 解析参数之后，若 `isAnswered === false` 且参数齐全，立刻调 `regenerateSolution()`；这样 `solution` 非空，`build()` 直接渲染竖式展示。
3. 若参数缺失或非法，行为不变：仍渲染输入面板。
4. 错误处理：求解器返回的 `errorMessage` 仍按现有错误条路径显示（不当作参数缺失的兜底）。
5. 不引入新工具字段、不修改 schema、不修改挂载点、不影响 `isAnswered === true` 的已有回归修复路径。

## 4. 验证

- 单元层：纯函数 `hasCompleteOperands` 可单独测试；Hypium CLI 仍受项目既有 scaffold 限制，需在 DevEco Studio 内运行；source assertion 与手工追踪覆盖以下用例：
  - AI 传 `{operation:'add', operand_a:28, operand_b:33}` → 直接进入展示。
  - AI 只传 `{operation:'add'}` → 仍显示输入面板。
  - AI 传 `{operation:'add', operand_a:2000, operand_b:33}` → operand 越界，保留输入面板（不调 `regenerateSolution`）。
  - `isAnswered === true` 路径行为不变。
- 构建：`assembleHap` clean 通过。

## 5. 非目标

不修改 `MessageBubble`、工具协议、工具分发、星星奖励、`onAnswer` 协议、求解器、nav 路由。仅 `VerticalMathCard.ets` 内自洽改造。
