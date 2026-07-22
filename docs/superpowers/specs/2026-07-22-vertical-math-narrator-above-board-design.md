# 竖式计算旁白改为单行置于竖式上方

**日期：** 2026-07-22
**范围：** `VerticalMathStepNarrator` 单行化 + `VerticalMathCard` 布局调整为旁白在上
**状态：** approved for implementation

## 1. 目标

把当前 `VerticalMathStepNarrator` 渲染的可滚动步骤列表收敛为单行文字，显示当前步骤的 `title` 与 `narration`；该行在 board 上方显示。`visibleStepCount` 变化时使用平滑过渡，文字随之更新。

## 2. 现有数据关系

`VerticalMathStepNarrator` 接收 `@Param steps`、`@Param visibleStepCount`、`@Param operationLabel`，根据这两者渲染可滚动列表与当前步骤高亮。它在 `VerticalMathCard` 内位于 board 之下、`Controls` 之上。

## 3. 实现方案

修改两个文件：

1. `entry/src/main/ets/components/verticalMath/VerticalMathStepNarrator.ets`
   - 去除 `List` / `Scroller` / `StepCard` / `renderStepCard` / `aboutToUpdate` 的滚动逻辑。
   - 计算 `currentStep = steps[Math.max(0, Math.min(visibleStepCount - 1, steps.length - 1))]`，将 `title` 与 `narration` 拼成一行文本：
     - 当 `title` 与 `narration` 都有内容：`${title}：${narration}`（用中文全角冒号）。
     - 仅 `title` 有内容：只显示 `title`。
     - 仅 `narration` 有内容：只显示 `narration`。
   - `visibleStepCount === 0`（未进入步骤）或 `steps` 为空时显示空态文案，例如"点击下方"开始计算"开始查看"。
   - 给该 `Text` 添加 `TransitionEffect.OPACITY.combine(TransitionEffect.move(TransitionEdge.START))` + `animation({ duration: 180, curve: Curve.EaseInOut })`，使 `visibleStepCount` 改变时新文字淡入并轻微右移。
   - 保留顶部小标题 `operationLabel`（如"加法"）作为不动元素。

2. `entry/src/main/ets/components/VerticalMathCard.ets`
   - 在布局中把 `VerticalMathStepNarrator` 移到 `VerticalMathBoard` 之上。两种 `largeSize` 模式都生效。
   - 不修改 `regenerateSolution` / `parseToolCallArguments` / `Controls` / `isAnswered` 行为。

不动：求解器、工具协议、卡片状态机、`onAnswer`、星星奖励。

## 4. 验证

- 源码断言：`VerticalMathStepNarrator.ets` 内无 `Scroller` / `ForEach` / `StepCard` 引用；`VerticalMathCard.ets` 的 `build()` 顺序为 narrator → board → controls。
- 手工追踪：步骤切换时单行文字随 `visibleStepCount` 更新；初始态显示空态；最终步骤显示"得到答案"那一行。
- `assembleHap` clean 通过。
- DevEco Studio 内手测体验过渡动画（Hypium CLI 仍受项目既有 scaffold 限制不可用）。

## 5. 非目标

不动工具协议、不动 `MessageBubble` 挂载、不动求解器、不动 `auto-solve` 与"answered timeline"两条已有路径。
