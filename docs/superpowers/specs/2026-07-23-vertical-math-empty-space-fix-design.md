# Vertical Math Empty Space Fix Design

**日期：** 2026-07-23
**范围：** `VerticalMathBoard` 垂直居中 + `VerticalMathCard` 新增 `StepProgressDots` 步骤指示器 + 控件位置调整
**状态：** approved for implementation

## 1. 目标

当前 `VerticalMathCard` 在初始态（`visibleStepCount === 0`）和短步骤中间态（1-2 行已展开）下，棋盘下方有大块未使用的空白。即使最终态（所有步骤展开 + 答案行），棋盘仍只占卡片可用高度的 70-80%，剩余空间显得突兀。

修复后：
- 棋盘内容在可用高度内**垂直居中**，无论步骤多少都感觉平衡
- 卡片底部新增**步骤进度点**指示器（`● ● ◉ ○ ○`），让用户一眼看到当前进度
- **控件按钮**从卡片顶部移到底部，与步骤进度点相邻——视觉上形成"看完进度→行动" 的自然链路

## 2. 现有数据关系

`VerticalMathCard.build()` 当前顺序：
```
Column() {
  Header Row
  if error: Error banner
  if solution == null: InputForm
  if solution != null:
    Controls()        // ← 顶部
    if isCompact():
      Column() { narrator, board } .layoutWeight(1)  // 主内容
    else:
      Column() { narrator; Row { board } } .layoutWeight(1)
}
```

`VerticalMathBoard` 外层 Column 有 `.height('100%')`、`.alignItems(HorizontalAlign.Start)`（仅水平方向），没有垂直对齐 → 内容贴顶。

## 3. 实现方案

### 3.1 `VerticalMathBoard.ets`：垂直居中

外层 Column 新增 `.justifyContent(FlexAlign.Center)`。当前棋盘内容是 `ForEach` 渲染的若干 `Column`（每个含 TopMark + RowView + 可选 Line）。这些 Column 在外层 Column 内自然堆叠；加 `justifyContent: Center` 后，整个堆叠居中。

不动：cellSize、ForEach key、RowView 子组件、layout。

### 3.2 `VerticalMathCard.ets`：步骤进度点 + 布局重排

#### 3.2.1 新增 `@Builder private StepProgressDots()`

渲染一个水平 Row，含 `solution.steps.length` 个圆点。每个圆点的视觉状态：

| 索引 vs `visibleStepCount` | 状态 | 样式 |
|---|---|---|
| `index >= visibleStepCount` | pending | 直径 8vp，1.5vp 边框 `$r('app.color.divider')`，透明填充 |
| `index === visibleStepCount - 1` | current | 直径 12vp，实心填充 `VERTICAL_MATH_ACTIVE_BG`，描边 `VERTICAL_MATH_ACTIVE_TEXT` |
| `index < visibleStepCount - 1` | done | 直径 8vp，实心填充 `VERTICAL_MATH_DONE_TEXT` |

Row 容器：8vp 间距水平居中，外加 `margin({ top: 12, bottom: 12 })`。

边界处理：
- `solution.steps.length === 0`（不应该发生，因为 regenerateSolution 会构造至少 1 步）：渲染空 Row（fallback，无 dot）
- `visibleStepCount === 0`：所有 dot 都是 pending
- `visibleStepCount === solution.steps.length`：最后一个 dot 是 current，其余都是 done

不引入任何新状态字段——dot 状态完全派生自 `solution.steps.length` 和 `visibleStepCount`。

#### 3.2.2 紧凑布局（`isCompact()`）重排

```
Column() {                      // 外层
  Header Row
  if error: Error banner
  if solution != null:
    Column() {                  // 主内容
      VerticalMathStepNarrator({...})
      VerticalMathBoard({...})
        .layoutWeight(1)
      this.StepProgressDots()
    }
    .layoutWeight(1)
    .padding({ left: 12, right: 12, top: 12, bottom: 8 })
    this.Controls()            // ← 移到主内容下方
}
```

棋盘加 `.layoutWeight(1)` 让它填满 narrator 和 dots 之间的空间（这样棋盘本身有充分高度），配合 board 内部的 `.justifyContent(Center)` 让内容在该高度内居中。

#### 3.2.3 `largeSize` 布局重排

保持 narrator → board 的现有结构，但在 board Row 下方插入 dots Row；Controls 同样从顶部移到底部：

```
Column() {                      // 外层
  Header Row
  if solution != null:
    Column() {                  // 主内容
      VerticalMathStepNarrator({...})
      Column() {
        VerticalMathBoard({...}).layoutWeight(1)
        this.StepProgressDots()
      }
      .layoutWeight(1)
      .padding(12)
    }
    .layoutWeight(1)
    this.Controls()
}
```

#### 3.2.4 控件（Controls）位置

`Controls()` 从 Header 下方移到主内容（narrator/board/dots）下方。新位置紧贴卡片底部，**这是有意的视觉层级**：用户在阅读完数学后立即看到行动按钮。

如果未来用户反馈"控件放顶部更顺手"，可回滚。但当前假设放底部更符合"先看 → 再行动"的心智模型。

## 4. 不动

- `solveVerticalMath` 求解器
- 工具协议（`ToolRegistry`、`BuiltinTools.ets`、`ToolExecutionService`）
- 卡片状态机（`visibleStepCount` 的递增/递减/重置）
- `aboutToAppear` 自动解题 + `isAnswered` 回放最终步
- `onAnswer` 回写 + 星星奖励
- `parseToolCallArguments`、`regenerateSolution`、`isCompleteVerticalMathArgs`
- 标记高亮（commit `06a4bb6`）
- Narrator 单行 + 过渡动画（commit `34c1d1f` + `1722ac3`）
- 任何其他组件（`MessageBubble`、`VerticalMathBoardRow`、`MathQuizCard` 等）

## 5. 验证

### 5.1 源码断言（Node one-liner）

```js
narrator_no_scroller       // VerticalMathBoard.ets 不引入滚动
board_justify_center       // VerticalMathBoard.ets 含 `justifyContent(FlexAlign.Center)`
card_has_step_progress     // VerticalMathCard.ets 含 `StepProgressDots`
card_compact_order         // 紧凑布局 build 顺序为 narrator → board → dots → Controls
card_large_order           // largeSize 布局 build 顺序为 narrator → board → dots → Controls
controls_below_main        // VerticalMathCard.ets 中 Controls 调用位于主内容 Column 之后
```

### 5.2 视觉验证（手工追踪）

| 状态 | `visibleStepCount` | 期望效果 |
|---|---|---|
| 初始 | 0 | 棋盘内容（5 6 / + 7 8 / 横线）垂直居中于卡片；dots 全 pending |
| 第 1 步 | 1 | 棋盘新增第 1 步结果行；dots[0] current，其余 pending |
| 第 N 步（中间） | k | 棋盘含 k 行结果；dots[k-1] current，前 k-1 done，后 N-k pending |
| 最终 | N | 棋盘含答案行；dots[N-1] current，其余 done |

### 5.3 构建

`assembleHap` clean → `BUILD SUCCESSFUL`。Hypium CLI 受项目既有 scaffold 限制不可用（见 MEMORY.md），DevEco Studio 手测体验。

## 6. 非目标

- 不重写求解器
- 不引入新状态字段
- 不改 `MessageBubble` 挂载点
- 不改工具协议
- 不改星星奖励逻辑