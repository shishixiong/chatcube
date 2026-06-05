# CategorizationCard — 分类小管家工具设计文档

**日期：** 2026-06-06
**版本：** v1
**范围：** 新增 `CategorizationCard` 组件 + `categorization` 工具，AI 驱动的分类归纳训练游戏，帮 6-7 岁小朋友发展"具体运算阶段"的核心认知能力

---

## 1. 概述

### 1.1 目标

为小星老师新增 `categorization` 工具，补足当前生态在"概念逻辑"维度上的空白。AI 出题（主题/桶/物品/难度），孩子在卡片里通过拖拽或点击完成分类。

### 1.2 为什么做

当前 5 个互动卡片（math_quiz / english_quiz / number_puzzle / handwriting_practice / ask_user）覆盖了"算术/英语/空间逻辑/写字/通用问答"。**皮亚杰的"具体运算阶段"理论指出，6-7 岁是分类归纳能力的关键发展期**，对应 `child_profile` 中的 `logic_puzzle` 技能维度，目前只有 number_puzzle 覆盖了"空间逻辑"，缺"概念逻辑"。

### 1.3 设计哲学

- **AI 出题，本地渲染**：内容由 AI 动态生成（灵活性），卡片只做渲染+校验（一致性）
- **复刻 NumberPuzzleCard 双视图模式**：内联横幅 + 全屏 Sheet，保持卡片族一致性
- **拖拽 + 点击双向**：适配 6-7 岁精细动作发展差异
- **无压力试错**：错误不阻止继续，鼓励反复尝试
- **视觉与 NumberPuzzleCard / HandwritingCard 同卡片外壳**：themeAiBubble 背景 + 1px divider 边框 + 12-14vp 圆角

---

## 2. 交互流程

```
AI 发起 categorization(theme="动物的家", bins=[...], items=[...], difficulty=2)
  → ToolExecutionService.handleCategorization() 挂起 Promise 等回答
  → MessageBubble 渲染内联横幅：
      "📦 分类小管家 · 动物的家" + "点击开始分类"
  → 用户点击 → ChatPage 弹出全屏 Sheet (SheetSize.LARGE)
  → Sheet 内:
      ┌─────────────────────────────┐
      │ 📦 分类小管家    动物的家 [已完成]│  ← HeaderRow
      │      进阶 · 6 件 · 3 桶        │
      ├─────────────────────────────┤
      │ 🎉 分类完成！ 0:42 · 6/6 [新]  │  ← WinBanner (条件渲染)
      ├─────────────────────────────┤
      │ ┌────┐ ┌────┐ ┌────┐          │
      │ │ 🦁 │ │ 🐟 │ │ 🦅 │          │  ← BinRow (3 桶)
      │ │陆地│ │水里│ │天上│          │
      │ └────┘ └────┘ └────┘          │
      ├─────────────────────────────┤
      │  散落物品卡（拖动或点击归位）   │  ← ItemsLayer
      │  🍎 🍌 🐶 🐱 🥕 🌽           │
      ├─────────────────────────────┤
      │ ⏱ 时间        ✅ 进度          │  ← StatsGrid
      │ 0:42          6/6              │
      │ 最佳 -          最佳 -          │
      ├─────────────────────────────┤
      │                  放弃本局 →    │  ← ActionRow
      └─────────────────────────────┘
  → 用户拖拽/点击全部归位 → 自动 onAnswer
  → 或用户点"放弃本局" → 提交 completed:false
  → AI 收到 ToolResult，用于对话反馈或更新 child_profile
```

### 2.1 已答状态（时间线内联）

- 折叠状态：📦 icon + 主题名 + "已完成"/"已放弃"药丸
- 展开状态：显示桶 + 物品归位快照 + 双卡片统计（只读回顾）

---

## 3. 组件 API

```typescript
// 结果接口
export interface CategorizationResult {
  theme: string              // 主题名
  difficulty: 1 | 2 | 3      // 难度
  correct: number            // 正确归类数
  total: number              // 总物品数
  time_seconds: number       // 用时（秒，1 位小数）
  wrong_attempts: number     // 拖错次数
  completed: boolean         // true=全对提交；false=放弃
}

// 桶（输入）
export interface CategorizationBin {
  name: string               // 桶名（中文）
  emoji?: string             // 桶标识 emoji（可选）
}

// 物品（输入）
export interface CategorizationItem {
  name: string               // 物品名
  emoji: string              // 物品 emoji
  bin_index: number          // 所属桶的索引（从 0 开始）
}

@ComponentV2
export struct CategorizationCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
}
```

---

## 4. 工具签名（AI 侧）

```typescript
{
  name: 'categorization',
  description: '让孩子把物品拖拽/点击到对应的分类桶里，训练分类归纳能力。',
  parameters: {
    type: 'object',
    properties: {
      theme: {
        type: 'string',
        description: '主题名称，如"动物的家"、"水果与蔬菜"。2-12 字。'
      },
      instruction: {
        type: 'string',
        description: '可选，给孩子的开场白，如"帮小动物回家吧！"'
      },
      difficulty: {
        type: 'integer',
        enum: [1, 2, 3],
        description: '难度：1=4件2桶，2=6件3桶，3=9件3桶'
      },
      bins: {
        type: 'array',
        minItems: 2,
        maxItems: 3,
        items: {
          type: 'object',
          properties: {
            name: { type: 'string', description: '桶名（中文）' },
            emoji: { type: 'string', description: '桶标识 emoji，可选' }
          },
          required: ['name']
        }
      },
      items: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            name: { type: 'string' },
            emoji: { type: 'string' },
            bin_index: { type: 'integer', description: '所属桶的索引（从 0 开始）' }
          },
          required: ['name', 'bin_index']
        }
      }
    },
    required: ['theme', 'bins', 'items']
  }
}
```

**结果回传：**
```typescript
{
  theme: string,
  difficulty: 1 | 2 | 3,
  correct: number,
  total: number,
  time_seconds: number,
  wrong_attempts: number,
  completed: boolean
}
```

---

## 5. 难度规格

| Level | 桶数 | 物品数 | 主题举例 |
|-------|------|--------|---------|
| **1** | 2 | 4 | 水果 vs 蔬菜；陆地 vs 水里 |
| **2** | 3 | 6 | 红/黄/绿；天上/水里/陆地 |
| **3** | 3 | 9 | 哺乳/鸟类/鱼类（更细的语义类别） |

**约束：每个桶里的物品数 >= 2**（避免"独占类"无意义分类）。

---

## 6. 视觉设计

### 6.1 卡片外壳

复用 `NumberPuzzleCard` Premium Tactile v2 的视觉语言：
- **inline 模式**：`themeAiBubble` 背景 + 1px divider 边框 + 14vp 圆角 + 14vp padding
- **largeSize 模式**：背景透明、20vp padding、0 边框
- **HeaderRow**：32vp 圆形徽章 + `themePrimary` 18% alpha 背景 + 15vp `box` SymbolGlyph
- **状态药丸**：`已完成`（绿 #4CAF50）/ `已放弃`（橙 #FF9F43）

### 6.2 桶（BinRow）

- **布局**：3 桶横向 Row，间距 10vp
- **形态**：圆角矩形 60vp 高，`borderRadius(12)`，背景 `withColorAlpha(themePrimary, '08')`，1.5vp dashed 边框 `withColorAlpha(themePrimary, '30')`
- **内容**：上层 32vp emoji，下层 12vp 中文名，居中
- **桶色差**：3 个桶使用同一主题色的不同透明度（`18` / `28` / `38`）做视觉区分，**不引入新色板**

### 6.3 物品卡（ItemCard）

- 圆形 56vp 直径，`borderRadius(28)`，背景 `themeAiBubble` + 0.5vp `divider` 边框
- 中央 28vp emoji + （可选）12vp 名称
- 选中态：3vp `themePrimary` 边框 + scale 1.1
- 拖动态：scale 1.15 + `shadow(radius: 12, color: '#40000000', offsetY: 4)`
- 落入桶内后：1.5vp `status_success` 绿色边框 + 透明度 0.6

### 6.4 WinBanner

- 12vp padding + 12vp radius + `withColorAlpha(SUCCESS_GREEN, dark ? '18' : '0C')` 背景
- 左侧 🎉 emoji + 文本"分类完成！" + `${correct}/${total} · ${time}秒` 次要信息
- 右侧"新纪录"药丸：v1 **预留位置但隐藏**（v2 才实现 best 持久化）

### 6.5 StatsGrid

- 8vp space 双卡片 Row
- 左卡：⏱ `elapsedSeconds`
- 右卡：✅ `correct / total` 进度
- 卡片内**直接读 `@Local` 字段**（ArkUI V2 响应式正确性，与 NumberPuzzleCard 一致）

---

## 7. 交互模型

### 7.1 拖拽

每个物品 `PanGesture({ direction: All, distance: 5 })`：
- 累计位移 >5vp 才触发（避免误触）
- 拖动期间持续计算落点：检查落点是否在某个桶的 bbox 内
- 落点合法 → 桶发光 + 缩放 1.05×（`@Local hoveredBinIndex`）
- 释放时落点合法 → 调 `handleDrop(itemIndex, binIndex)`
- 释放时落点非法 → 弹回原位

### 7.2 点击

每个物品 `.onClick()`：
- 当前未选中任何物品 → 选中该物品（高亮 + scale 1.1）
- 当前已选中该物品 → 取消选中
- 当前已选中其他物品 → 切换选中

每个桶 `.onClick()`：
- 当前已选中物品 → `handleDrop(selectedItemIndex, thisBinIndex)`
- 当前未选中物品 → 无操作

### 7.3 手势隔离

两处：
1. `.onTouch(e => e.stopPropagation())` 阻止 ItemsLayer 内部事件冒泡到外层 List
2. `.priorityGesture(PanGesture...)` 抢占手势，确保拖动不触发 ChatPage sheet dismiss

### 7.4 计时器

`startTimer`：`setInterval(500ms)`，每次 tick 检查 `!isCompleted && startTime > 0`，更新 `elapsedSeconds`。
`stopTimer` / `aboutToDisappear`：清理 timerId，避免内存泄漏。

---

## 8. 动画体系

| 事件 | 视觉 | 动画时长 |
|------|------|----------|
| 物品选中 | scale 1.1 + 主题色描边 | 80ms EaseOut |
| 物品拖动 | scale 1.15 + 阴影加深 | 实时 |
| 拖到合法桶上方 | 桶发光 + 缩放 1.05× | 100ms |
| 拖到桶内（正确） | 物品飞入桶内 + 弹簧回弹 | 300ms EaseOut |
| 拖到桶内（错误） | 物品红色震动 + 弹回原位 | 400ms |
| 全完成 | WinBanner 滑入 + 桶依次脉冲 | 600ms |

> 关键设计：拖动 → 桶高亮 100ms、落入 300ms、WinBanner 600ms 形成连贯的视觉反馈链，孩子能从动作直接感知"对/错/完成"。

---

## 9. 状态机

### 9.1 @Local 字段

| 字段 | 类型 | 用途 |
|------|------|------|
| `bins` | `CategorizationBin[]` | 桶（来自 toolCall.arguments） |
| `items` | `CategorizationItem[]` | 物品（来自 toolCall.arguments，已随机化顺序） |
| `difficulty` | `1 \| 2 \| 3` | 难度 |
| `theme` | `string` | 主题名 |
| `correctCount` | `number` | 正确归类数 |
| `wrongAttempts` | `number` | 拖错次数 |
| `elapsedSeconds` | `number` | 当前用时（setInterval 500ms tick） |
| `isCompleted` | `boolean` | 已结束（赢或放弃） |
| `hasWon` | `boolean` | 全对完成，触发 WinBanner |
| `placedItems` | `Map<itemIndex, binIndex>` | 已归位物品的桶位置 |
| `selectedItemIndex` | `number` | 当前点击选中的物品 index（-1 = 无） |
| `draggedItemIndex` | `number` | 当前拖动的物品 index（-1 = 无） |
| `hoveredBinIndex` | `number` | 当前拖动悬停的桶 index（-1 = 无） |
| `validationError` | `string` | 校验失败消息（空 = 通过） |

### 9.2 私有字段（非响应式）

| 字段 | 用途 |
|------|------|
| `timerId` | `setInterval` 句柄 |
| `shakingItemIndex` | 当前震动中的物品 index（-1 = 无） |

### 9.3 状态机

```
aboutToAppear
  ├─ validateAndNormalize()
  │    ├─ [失败] → validationError = 错误消息 → renderErrorPlaceholder
  │    └─ [通过] → 进入游戏初始化
  └─ [通过]
       ├─ isAnswered: parseAnsweredPayload (还原 placedItems + 显示已完成)
       └─ !isAnswered: shuffleItems() (随机物品顺序) + startTimer

handleDrop(itemIndex, binIndex)
  ├─ isCompleted: 无操作
  ├─ binIndex < 0 || binIndex >= bins.length: 无操作
  ├─ placedItems.has(itemIndex): 允许从桶里移出 → 撤回
  ├─ items[itemIndex].bin_index === binIndex: 正确
  │    └─ placedItems.set(itemIndex, binIndex) + correctCount++ + animate(飞入桶)
  │         └─ 全部归位? → stopTimer + showWinBanner + onAnswer
  └─ 其他: 错误
       └─ wrongAttempts++ + animate(震动 + 弹回)
```

**与 NumberPuzzleCard 的关键差异：**
- 物品**不放回原位**——一旦归位就停在桶内（进度可见，不重复尝试）
- 错误尝试**不阻止**继续玩，孩子可以拖回别的桶试
- **不重置归位**：可以从桶里移出（长按拖出或点击桶内物品）

---

## 10. 内容校验（卡片侧防御）

`aboutToAppear` 中执行 `validateAndNormalize()`，校验失败时**整体不渲染游戏**，只显示"题目出错了，提示小星老师再出一题吧 💡"占位卡：

| 规则 | 失败行为 |
|------|---------|
| `bins.length < 2 \|\| > 3` | 错误占位 |
| `bins[].name` 为空 | 错误占位 |
| `items.length` 与 `difficulty` 不匹配（4/6/9） | 错误占位 |
| 任意 `item.bin_index` 越界 | 错误占位 |
| 任一桶的物品数 < 2 | 错误占位 |
| `difficulty` 字段缺失 | 由 items.length 自动推断（4→1 / 6→2 / 9→3） |
| `theme` 为空 | 错误占位 |
| `items[].emoji` 全空 | 不报错，但视觉降级为"纯文字卡片" |

**不**做 AI 内容润色/纠错——卡片是纯渲染器，内容质量完全由 AI 端 system prompt 把控。

---

## 11. 持久化

**v1 不新建表**。仅：
1. `recordStarEvent('categorization', ...)` 写 `star_events`（与 math/english/puzzle/handwriting 一致）
2. 最佳成绩**v1 不做**——NumberPuzzleCard v2 才加，预留给本游戏的 v2

---

## 12. 接入点（实现清单）

| 文件 | 改动 |
|------|------|
| `entry/src/main/ets/utils/SearchToolIdentityUtils.ets` | 新增 `CATEGORIZATION_TOOL_ID = 'categorization'` 常量 + `isCategorizationFunctionName` 判定（接受别名 `classify` / `categorize`） |
| `entry/src/main/ets/config/BuiltinTools.ets` | 新增 3 个函数：`getCategorizationToolDefinition` / `getCategorizationToolConfig` / `executeCategorizationTool`，在 `registerBuiltinTools` 注册 |
| `entry/src/main/ets/services/ToolExecutionService.ets` | 在 `executeToolCall` 分流新增 `case 'categorization':` → `handleCategorization(toolCall)`；handler 复用 `pendingAnswers` Promise + `resolvePendingAnswer` 模式 |
| `entry/src/main/ets/components/CategorizationCard.ets` | **新建** @ComponentV2，参考 `NumberPuzzleCard.ets` 的双视图模式 |
| `entry/src/main/ets/components/MessageBubble.ets` | import `CategorizationCard`；新增 `shouldRenderCategorizationInteractionCard` 判断；内联 + 已答折叠两处渲染分支 |
| `entry/src/main/ets/models/AssistantModels.ets` | `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` 数组中追加 `'categorization'` |

**预计新增/修改行数：**
- 新建文件 1 个：CategorizationCard.ets (~600-800 行，类比 NumberPuzzleCard)
- 修改文件 5 个，共约 150-200 行

---

## 13. 视觉风格一致性检查表

- [ ] 外壳：themeAiBubble 背景 + 1px divider 边框 + 14vp 圆角（inline 模式）
- [ ] 主题色：完全使用 `themePrimary` 派生（桶色、选中态、徽章背景）
- [ ] 状态色：成功 `#4CAF50`、已放弃 `#FF9F43`、暗色模式自适应
- [ ] SymbolGlyph：HeaderRow 用 `box` 图标
- [ ] 触控目标：所有可点击区域 ≥ 44vp
- [ ] 手势隔离：`.priorityGesture(PanGesture)` + `.onTouch(e => e.stopPropagation())`

---

## 14. 验收清单

### 功能验证
- [ ] AI 在 3 个不同主题（动物/水果/颜色）下能成功调用 `categorization` 工具
- [ ] 难度 1/2/3 三档均能正常渲染与操作
- [ ] 拖拽 + 点击两种方式都能完成分类
- [ ] 全部正确归类后自动调用 `onAnswer` 并触发 WinBanner
- [ ] 点"放弃本局"提交 `completed: false`
- [ ] 已答状态下重新加载（MessageBubble 在线视图）正确显示
- [ ] inline + largeSize 两种模式均工作

### 异常路径
- [ ] AI 传来 `bins.length = 1` 时显示"题目出错了"占位卡
- [ ] AI 传来 `items.length = 3`（与 difficulty=2 不匹配）时显示占位卡
- [ ] AI 传来某 `item.bin_index = 5`（越界）时显示占位卡
- [ ] AI 传来 `theme` 为空字符串时显示占位卡

### 视觉/交互
- [ ] 浅色 + 深色模式视觉均无错位
- [ ] 拖动时不触发 ChatPage 列表滚动或 sheet dismiss
- [ ] 选中态/拖动态/落入桶内三态切换有平滑动画

### 数据
- [ ] 完成后 `star_events` 表新增一条 `activity_type='categorization'` 记录
- [ ] 结果 JSON 正确回传给 AI

### 性能
- [ ] 难度 3（9 件 3 桶）下拖动帧率 ≥ 50fps
- [ ] 卡片在 ChatPage 中首次渲染 < 200ms

---

## 15. 关键复用参考

- **@ComponentV2 + @Param/@Event 模式**：`MathQuizCard.ets:1-50`
- **双视图（inline + largeSize）模式**：`NumberPuzzleCard.ets` + `.claude/rules/number-puzzle-card.md` 全文
- **挂起-Promise 工具流**：`ToolExecutionService.ets:1028-1058` + `:544-611`（handleMathQuiz 完整流程）
- **内容校验占位模式**：`EnglishQuizCard.ets` 的图片解析失败降级
- **stat 卡片响应式模式**：`NumberPuzzleCard.ets` 的 StatsGrid（直接读 @Local 字段）
- **统一色板**：`utils/ColorAlphaUtils.ets` 的 `withColorAlpha`
- **状态对象**：`state/AppUiState.ets` 的 `themePrimary` / `themeAiBubble` / `isDarkMode`

---

## 16. 后续可优化（不阻塞 v1）

- 难度 4 引入"二级分类"（桶内有子桶）
- 主题引导模式：AI 端 system prompt 提供 5-8 个推荐主题
- 最佳成绩持久化（参考 NumberPuzzleCard v2 的 bestScoresLoaded 守卫）
- 音效反馈（拖对/拖错/完成的轻音效）
- "提示"按钮：高亮一个未归位物品的所属桶
- 多语言支持（英文物品名）
