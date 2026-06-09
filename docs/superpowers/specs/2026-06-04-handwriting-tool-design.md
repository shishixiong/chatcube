# HandwritingCard — 学写字工具设计文档

**日期：** 2026-06-04
**版本：** v1
**范围：** 新增 `HandwritingCard` 组件，AI 驱动的学写字教学工具，教小朋友学写英文字母、数字、基础汉字

---

## 1. 概述

### 1.1 目标

为小星老师新增 `handwriting_practice` 工具，教小朋友学写字。AI 指定要写的字，展示笔顺动画，提供空白 Canvas 让小朋友自由书写，完成后导出笔画图片发给 AI vision 模型进行评价反馈。

### 1.2 设计哲学

- **复刻 NumberPuzzleCard 双视图模式**：内联横幅 + 全屏 Sheet，保持卡片族一致性
- **自由书写，AI 鼓励**：不给机器评分，用 AI 的语言反馈替代冰冷的分数
- **本地笔顺库优先**：预置常见字符的精确笔顺数据，AI 传参兜底
- **视觉与 MathQuizCard/EnglishQuizCard 同一卡片外壳**：themeAiBubble 背景 + 1px divider 边框 + 12vp 圆角

---

## 2. 交互流程

```
AI 发起 handwriting_practice(character="A", type="letter", strokes=[...])
  → ToolExecutionService.handleHandwriting() 阻塞等待
  → MessageBubble 显示内联横幅：
      "✏️ 学写字 · A" + "点击开始写字"
  → 用户点击 → ChatPage 弹出全屏 Sheet (SheetSize.LARGE)
  → Sheet 内:
      ┌─────────────────────────────┐
      │ ✏️ 学写字   字母 · Letter      │  ← HeaderRow
      │ 笔顺: / \ —                  │
      ├─────────────────────────────┤
      │       A  (大字)             │  ← DemoPanel（示范动画区）
      │  3笔 · 先左斜再右斜最后横    │
      │                      [▶ 重播]│
      ├─────────────────────────────┤
      │                             │
      │    空白 Canvas 书写区        │  ← CanvasPanel（触控绘图）
      │    (380 × 220 vp)           │
      │                             │
      ├─────────────────────────────┤
      │  [↩ 撤销] [✕ 清除]  [提交评价]│  ← ActionRow
      └─────────────────────────────┘
  → 用户书写完点 [提交评价]
  → Canvas 导出 base64 JPEG
  → 发送图片 + 评价提示词给 AI vision 模型
  → AI 返回鼓励性文字反馈，显示在对话流中
  → Sheet 关闭
```

### 2.1 已答状态（时间线内联）

- 折叠状态：✏️ icon + "学写字 - A" + 完成标记
- 展开状态：显示字符 + 完成标记，无 Canvas（只读回顾）

---

## 3. 组件 API

```typescript
export interface HandwritingResult {
  character: string       // 写的字
  type: string            // letter | number | chinese
  completed: boolean      // true = 提交了；false = 放弃
  stroke_count: number    // 用户画了多少笔
}

@ComponentV2
export struct HandwritingCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
}
```

### 3.1 导出接口

仅 `HandwritingResult` (interface) 和 `HandwritingCard` (@ComponentV2)。

---

## 4. 数据结构

### 4.1 工具调用参数

```json
{
  "character": "A",
  "type": "letter",
  "strokes": [
    {"x1": 0.3, "y1": 0.2, "x2": 0.7, "y2": 0.8, "label": "/"},
    {"x1": 0.7, "y1": 0.2, "x2": 0.3, "y2": 0.8, "label": "\\"},
    {"x1": 0.2, "y1": 0.5, "x2": 0.8, "y2": 0.5, "label": "—"}
  ]
}
```

- `character` (string, required): 要写的字
- `type` (string, required): `letter` | `number` | `chinese`
- `strokes` (array, optional): 笔顺定义，坐标用相对值 (0.0-1.0)。缺省时从本地笔顺库查询

### 4.2 本地笔顺数据

文件：`config/StrokeOrderData.ets`

```typescript
interface Stroke {
  x1: number, y1: number, x2: number, y2: number, label: string
}

// Map<character, Stroke[]>
const STROKE_ORDER_DATA: Map<string, Stroke[]> = new Map([
  ["A", [{x1:0.3,y1:0.8,x2:0.5,y2:0.1,label:"/"}, {x1:0.5,y1:0.1,x2:0.7,y2:0.8,label:"\\"}, {x1:0.35,y1:0.5,x2:0.65,y2:0.5,label:"—"}]],
  // ... A-Z, a-z, 0-9, 基础汉字约50个
])
```

覆盖范围：
- 大写字母 A-Z
- 小写字母 a-z
- 数字 0-9
- 基础汉字约 50 个（人、大、山、水、日、月、口、手、上、下...）

笔顺数据使用相对坐标（0-1 范围），渲染时按 Canvas 实际尺寸缩放。

### 4.3 Canvas 绘图数据

```typescript
interface StrokePoint { x: number, y: number, timestamp: number }
interface DrawnStroke {
  points: StrokePoint[]
  color: string
  width: number
}
```

---

## 5. 组件状态管理

### 5.1 @Local 响应式字段

| 字段 | 类型 | 用途 |
|------|------|------|
| `character` | `string` | 当前写的字 |
| `charType` | `string` | letter / number / chinese |
| `strokes` | `Stroke[]` | 笔顺数据 |
| `drawnStrokes` | `DrawnStroke[]` | 用户画的笔画 |
| `isSubmitting` | `boolean` | 提交中状态 |
| `showAnimation` | `boolean` | 是否正在播放笔顺动画 |
| `currentAnimStroke` | `number` | 动画当前笔画索引 |
| `isCompleted` | `boolean` | 是否已完成 |
| `hasContent` | `boolean` | Canvas 上是否有笔画 |

### 5.2 私有字段

| 字段 | 用途 |
|------|------|
| `canvasContext` | CanvasRenderingContext2D 引用 |
| `animTimerId` | 笔顺动画 setInterval 句柄 |
| `submittedImageBase64` | 提交时的 base64 图片数据 |

---

## 6. 视觉结构

### 6.1 全屏 Sheet 模式 (largeSize = true)

5 区块垂直布局（与 NumberPuzzleCard 对齐）：

1. **HeaderRow** — ✏️ SymbolGlyph 圆徽章 + "学写字" 标题 + 类型标签 + 笔顺文字
2. **DemoPanel** — 大字示范 + 笔画描述 + [▶ 重播] 按钮
3. **CanvasPanel** — 大面积 Canvas 书写区（约 380×220vp）
4. **ActionRow** — [↩ 撤销] [✕ 清除] 靠左 + [提交评价] 靠右

外层 `.padding(20)` + `backgroundColor(Transparent)` — 让 Sheet 自带的背景接管

### 6.2 内联模式 (largeSize = false)

仅显示紧凑横幅：
- ✏️ icon + "学写字 · A" + "点击开始写字" subtitle + ">" chevron
- 点击触发 ChatPage 打开 Sheet

### 6.3 已答模式 (isAnswered = true, largeSize = false)

在 `answeredPayload` 中解析 `HandwritingResult`，显示：
- ✏️ icon + "学写字 - A" + 完成标记（绿色 "已完成" / 橙色 "已放弃"）

### 6.4 颜色规格

| 用途 | 取值 |
|------|------|
| 主题主色 | `themePrimary` (from AppUiState) |
| 示范底色 | `withColorAlpha(themePrimary, '08')` |
| 示范边框 | 1.5vp Dashed `withColorAlpha(themePrimary, '38')` |
| Canvas 背景 | `#FAFAF9` (仿田字格纸色) |
| Canvas 边框 | 2vp Dashed `#DDD` |
| 画笔颜色 | `#333333` (仿铅笔深灰) |
| 画笔粗细 | 6vp |
| 示范字颜色 | `#92400E` (琥珀深色) |
| 成功绿 | `#22C55E` (与 NumberPuzzleCard 共用 SUCCESS_GREEN) |
| 卡片外壳 | `themeAiBubble` (inline 模式) |

---

## 7. Canvas 技术方案

### 7.1 绘图流程

1. `CanvasRenderingContext2D.attachToCanvas(canvasRef)` 获取上下文
2. `.onTouch(TouchType.Down)` → `beginPath()`, `moveTo()`
3. `.onTouch(TouchType.Move)` → `lineTo()`, `stroke()`, 同时记录 `StrokePoint`
4. `.onTouch(TouchType.Up)` → 结束当前 DrawnStroke，存入 `drawnStrokes[]`
5. 撤销 → `drawnStrokes.pop()`, 全量重绘（`clearRect()` + 重绘所有笔画）
6. 清除 → `drawnStrokes = []`, `clearRect()`

### 7.2 笔顺动画

- DemoPanel 使用第二个 Canvas 或 Stack 叠加线条
- `setInterval(500ms)` 逐笔画线
- 当前笔画用绿色 `#22C55E` 高亮，已画完的保留深色
- 重播按钮重置动画索引 + 清空重画

### 7.3 图片导出与 AI 评价

```typescript
// 步骤 1: Canvas → PixelMap
const pixelMap = canvasContext.getPixelMap(0, 0, width, height)

// 步骤 2: PixelMap → ArrayBuffer (JPEG)
const imagePacker = image.createImagePacker()
const buffer = await imagePacker.packing(pixelMap, { format: 'image/jpeg', quality: 80 })

// 步骤 3: ArrayBuffer → base64
const base64 = bufferToBase64(buffer)

// 步骤 4: 构造带附件的消息发送给 AI
// 复用现有的 prepareOutgoingAttachments / ensureAttachmentBase64Data 流程
```

### 7.4 手势隔离

- Canvas 的 `.onTouch()` 使用 `.stopPropagation()` 阻止冒泡
- Sheet 的 dismiss 手势在 Canvas 区域内被禁用（通过 `SheetInfo.disableSwipe` 或 `PanGesture` 抢占）

---

## 8. 工具注册

### 8.1 工具定义

| 字段 | 值 |
|------|------|
| toolId | `handwriting_practice` |
| functionName | `handwriting_practice` |
| permissionLevel | `READ` |
| approavalPolicy | `UNCONFIGURED` (直接 auto approve) |

### 8.2 ToolExecutionService 特殊路径

在 `executeToolCall()` 中新增：
```typescript
if (isHandwritingPracticeFunctionName(normalizedFunctionName)) {
  return await this.handleHandwriting(toolCall, context)
}
```

`handleHandwriting()` — **内聚流**（评价在工具内部完成）：

1. backfill toolCall 元数据
2. 设置 `approvalState = 'pending'`
3. 创建 Promise 存入 `pendingAnswers`，await 用户提交
4. 收到 answerJson（包含 `handwriting_base64` + `HandwritingResult`）后：
   - 使用当前会话的模型调用 AIApidService.sendChatRequest()
   - 传入一张 image 附件 + 评价 prompt（见 8.3）
   - 阻塞等待 AI 返回评价文字
   - 将评价文字作为 `ToolResult.content` 返回
5. 返回的 ToolResult 进入 tool loop，作为工具结果展示在对话中

> **设计要点：** 评价调用复用当前会话的 modelId 和 apiConfig，确保用支持 vision 的模型。如果会话模型不支持 vision，记录警告并返回纯文本鼓励语。

### 8.3 AI 评价提示词

```
请用鼓励的语气评价小朋友写的"{character}"（类型：{type}）。
注意观察：
- 笔画方向是否正确
- 字形大小是否合适
- 整体是否端正

请给出 1-2 句鼓励性反馈，语气要温暖，像幼儿园老师对小朋友说话。
反馈语言用中文，可以适当使用 emoji 增添亲切感。
```

---

## 9. 文件变更清单

| 文件 | 变更类型 | 内容 |
|------|---------|------|
| `components/HandwritingCard.ets` | **新建** | 核心组件 (~500 行) |
| `config/StrokeOrderData.ets` | **新建** | 本地笔顺数据 (~200 行) |
| `utils/SearchToolIdentityUtils.ets` | 修改 | +`HANDWRITING_PRACTICE_TOOL_ID` + `isHandwritingPracticeFunctionName()` |
| `config/BuiltinTools.ets` | 修改 | +`HandwritingPracticeExecutor` + `createHandwritingPracticeToolDefinition()` + `createHandwritingPracticeToolConfig()` + register |
| `services/ToolExecutionService.ets` | 修改 | +`handleHandwriting()` (~70行) + executeToolCall 调度 |
| `models/AssistantModels.ets` | 修改 | `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` 中 +`HANDWRITING_PRACTICE_TOOL_ID` |
| `components/MessageBubble.ets` | 修改 | +内联横幅渲染 (~20行) + `shouldRenderHandwritingInteractionCard()` + `HandwritingStepContent` Builder (~30行) + 路由 |
| `pages/ChatPage.ets` | 修改 | +`showHandwritingSheet` 状态 + `HandwritingSheetBuilder` + `bindSheet` + `onOpenHandwritingSheet` 回调 (~40行) |
| `components/chat/ChatMessageListSection.ets` | 修改 | +`onOpenHandwritingSheet` `@Event` 回调传递 (~5行) |
| `models/ChatModels.ets` | 确认 | `InputMode.VISION` 和 `ModelCapabilities.supportsVision` 已存在，无需修改 |

---

## 10. 与现有卡片族的一致性

| 特性 | HandwritingCard | NumberPuzzleCard | MathQuizCard |
|------|----------------|-----------------|-------------|
| 双视图 (inline + sheet) | Yes | Yes | No |
| @Param API 合约 | Yes | Yes | Yes |
| @Event onAnswer | Yes | Yes | Yes |
| isAnswered 只读恢复 | Yes | Yes | Yes |
| 卡片外壳 | themeAiBubble + divider | themeAiBubble + divider | themeAiBubble + divider |
| 特殊路径 (ToolExecutionService) | handleHandwriting | handleNumberPuzzle | handleMathQuiz |
| 最佳成绩持久化 | No (v1 不做) | Yes (PreferencesService) | No |
| 放弃本局 | 关闭 Sheet | "放弃本局" 链接 | N/A |

---

## 11. 已知取舍

| 限制 | 原因 | 缓解 |
|------|------|------|
| AI vision 评价延迟 2-5s | 图片编码 + API 调用 | 提交按钮显示 loading 状态 |
| 不支持手指以外的输入工具 | HarmonyOS 触控限制 | 接受，目标用户为儿童 |
| 笔顺动画无缓动 | Canvas 逐笔画线用 setInterval | 500ms 间隔保证可见性 |
| 无压感 | HarmonyOS TouchEvent 不提供 pressure | 使用固定 6vp 线宽 |
| v1 不做评分持久化 | 优先级低于核心功能 | 后续可加 handwriting_records 表 |
| 中文笔顺数据只覆盖约 50 个基础字 | 手写数据工作量大 | AI 可提供 strokes 参数兜底 |
| 仅支持全屏 Sheet + 内联横幅，不做纯内联 Canvas | 内联 Canvas 空间太小 | 与 NumberPuzzleCard 一致，复用模式 |

---

## 12. 后续可优化

- 压感支持（如果可以获取到 touch force）
- 田字格/米字格背景切换
- 笔顺数据社区共建（更多的汉字）
- 震动反馈（写错时轻震）
- 撤销重做栈（多步撤销）
- 书历史录持久化到 handwriting_records 表
- 支持颜色/画笔大小选择

---

## 13. 验收清单

- [ ] handwriting_practice 工具注册成功，AI 能调用
- [ ] 内联横幅在 MessageBubble 中正确显示，"点击开始写字"可点击
- [ ] 全屏 Sheet 打开后示范区和 Canvas 正常渲染
- [ ] 笔顺动画可播放，重播功能正常
- [ ] Canvas 触控书写流畅，无卡顿
- [ ] 撤销清除当前笔画，清除按钮清空所有
- [ ] 提交后 Canvas 导出图片，发给 AI vision 评价
- [ ] AI 评价文字出现在对话流中
- [ ] 关闭 Sheet 后 correctly resolves pending Promise
- [ ] 已答模式下显示完成标记
- [ ] 暗色模式下 Canvas 背景、画笔颜色、主题色适配
- [ ] Sheet dismiss 手势在 Canvas 区域不误触
- [ ] 本地笔顺库覆盖全部字母 A-Z a-z 和数字 0-9
- [ ] AI 传入 strokes 参数时可正确渲染自定义笔顺
