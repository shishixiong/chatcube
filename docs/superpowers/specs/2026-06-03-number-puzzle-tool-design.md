# 数字华容道工具 — 设计规格

**日期：** 2026-06-03
**状态：** 已批准
**范围：** 为小星老师新增数字华容道交互工具，包含 4 级难度、学习画像集成和游戏记录存储

---

## 1. 功能概述

新增 `number_puzzle` 内置工具，让 AI 助手"小星老师"可以向孩子发起数字华容道挑战。孩子在聊天界面内通过点击或滑动操作完成拼图，结果自动回传给 AI，AI 根据完成情况更新学习画像中的逻辑思维和观察力评估。

### 难度级别

| 级别 | 棋盘尺寸 | 数字块数 | 描述 |
|------|----------|----------|------|
| 2 | 2×2 | 3 + 空格 | 幼儿 |
| 3 | 3×3 | 8 + 空格 | 简单 |
| 4 | 4×4 | 15 + 空格 | 进阶 |
| 5 | 5×5 | 24 + 空格 | 挑战 |

---

## 2. 架构流程

```
AI 调用 number_puzzle(difficulty: 2|3|4|5)
       │
       ▼
ToolExecutionService.handleNumberPuzzle()
  - 解析 difficulty 参数
  - 设置 toolCall.approvalState = 'pending'
  - 创建挂起的 Promise，注册到 pendingAnswers
  - 发布 pendingToolInteractionTick 触发 UI 刷新
       │
       ▼
MessageBubble 检测到待处理的 number_puzzle 交互
  → 渲染 NumberPuzzleCard（未回答状态）
       │
       ▼
孩子在 NumberPuzzleCard 中操作
  - 点击或滑动移动方块
  - 实时计时器和步数计数
  - 检测到还原完成状态时自动提交
       │
       ▼
NumberPuzzleCard.onAnswer(toolCallId, resultJson)
  → ToolExecutionService.resolvePendingAnswer()
  → 将游戏记录写入 puzzle_records 表
  → 返回 resultJson 给 AI
       │
       ▼
AI 收到结果 → 给予鼓励/评价
  → 可选调用 child_profile(action:"update") 更新技能等级
```

---

## 3. 实现清单

### 3.1 新增文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/components/NumberPuzzleCard.ets` | 游戏交互卡片组件 |

### 3.2 修改文件

| 文件 | 修改内容 |
|------|----------|
| `entry/src/main/ets/utils/SearchToolIdentityUtils.ets` | 添加 `NUMBER_PUZZLE_TOOL_ID` 常量和 `isNumberPuzzleFunctionName()` 判断函数 |
| `entry/src/main/ets/config/BuiltinTools.ets` | 注册 `number_puzzle` 工具（定义 + 配置 + 执行器），添加到 `getBuiltinToolIds()` |
| `entry/src/main/ets/services/ToolExecutionService.ets` | 添加 `handleNumberPuzzle()` 特殊处理路径，游戏结束后写入 `puzzle_records` 表 |
| `entry/src/main/ets/services/DatabaseService.ets` | 添加 `puzzle_records` 表的建表语句和 CRUD 方法 |
| `entry/src/main/ets/services/ChildProfileService.ets` | 添加 `logic_puzzle` 和 `observation` 两个技能维度 |
| `entry/src/main/ets/components/MessageBubble.ets` | 导入 NumberPuzzleCard，添加待处理/已完成两种渲染路径 |
| `entry/src/main/ets/models/AssistantModels.ets` | 将 `NUMBER_PUZZLE_TOOL_ID` 加入小星老师助手的 `lockedToolIds` |

---

## 4. 工具定义（AI 侧接口）

### 4.1 ToolDefinition

```json
{
  "name": "number_puzzle",
  "description": "发起数字华容道游戏，锻炼孩子的逻辑思维和观察力。孩子通过滑动或点击将打乱的数字按顺序排列还原。根据孩子年龄和能力选择合适的难度：2=2×2幼儿(3块)，3=3×3简单(8块)，4=4×4进阶(15块)，5=5×5挑战(24块)。建议初次使用从3开始。",
  "parameters": {
    "type": "object",
    "properties": {
      "difficulty": {
        "type": "integer",
        "description": "难度级别：2=2×2幼儿，3=3×3简单，4=4×4进阶，5=5×5挑战",
        "enum": [2, 3, 4, 5]
      }
    },
    "required": ["difficulty"]
  }
}
```

### 4.2 结果 Payload（onAnswer 返回给 AI）

```json
{
  "difficulty": 3,
  "grid_size": "3×3",
  "time_seconds": 45.2,
  "move_count": 28,
  "completed": true
}
```

**`completed: false`** 仅当孩子点击"重新开始"放弃当前局时发生。正常完成一律为 `true`。

---

## 5. NumberPuzzleCard 组件规格

### 5.1 Props

```typescript
@ComponentV2
export struct NumberPuzzleCard {
  @Param toolCall: ToolCall
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Event onAnswer: (toolCallId: string, answerJson: string) => void
}
```

### 5.2 布局

```
┌──────────────────────────────────────┐
│  🧩 数字华容道 · 进阶 (4×4)          │
│                                      │
│  ┌────┬────┬────┬────┐              │
│  │ 1  │ 2  │ 3  │ 4  │              │
│  ├────┼────┼────┼────┤              │
│  │ 5  │ 6  │ 7  │ 8  │              │
│  ├────┼────┼────┼────┤              │
│  │ 9  │ 10 │ 11 │ 12 │              │
│  ├────┼────┼────┼────┤              │
│  │ 13 │ 14 │    │ 15 │  ← 空格隐藏 │
│  └────┴────┴────┴────┘              │
│                                      │
│  ⏱ 00:12            👆 步数: 28     │
│  🔄 重新开始                        │
└──────────────────────────────────────┘
```

### 5.3 格子尺寸

由 `difficulty` 决定，确保总宽度约 260vp 适配聊天气泡：

| difficulty | 格子尺寸 | 间距 |
|------------|----------|------|
| 2 | 72vp | 4vp |
| 3 | 64vp | 4vp |
| 4 | 52vp | 3vp |
| 5 | 44vp | 3vp |

### 5.4 交互

- **点击**：点击空格相邻方块 → 方块滑入空格
- **滑动**：`SwipeGesture` 全方向 → 判断方向后将对应方块移入空格
- 动画：`TransitionEffect.translate`，时长 100ms
- 完成检测：每次移动后比对目标状态数组 `[1, 2, ..., 0]`

### 5.5 状态

```typescript
@Local gameBoard: number[]       // 当前棋盘（打乱后）
@Local moveCount: number = 0     // 步数
@Local startTime: number = 0     // 开始时间戳
@Local elapsedSeconds: number    // 已用秒数（定时器更新显示）
@Local isCompleted: boolean       // 是否已完成
@Local shouldAnimate: boolean    // 打乱时关闭动画
```

### 5.6 打乱算法

从目标状态开始，执行 `minMoves + randomExtra` 次随机合法移动。`minMoves` 按难度递增（2: 10, 3: 30, 4: 60, 5: 100），确保有足够挑战性。打乱时关闭动画。

### 5.7 完成后的显示

- 暂停计时器
- 棋盘不可再操作
- 显示"完成！"标记
- 自动触发 `onAnswer` 回调

---

## 6. 数据库扩展

### 6.1 puzzle_records 表

```sql
CREATE TABLE IF NOT EXISTS puzzle_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  difficulty INTEGER NOT NULL,
  time_seconds REAL NOT NULL,
  move_count INTEGER NOT NULL,
  completed INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
);
```

### 6.2 DatabaseService 新增方法

```typescript
// 插入游戏记录
insertPuzzleRecord(sessionId: string, difficulty: number, timeSeconds: number, moveCount: number, completed: boolean): Promise<number>

// 查询某会话的游戏记录
getPuzzleRecordsBySession(sessionId: string): Promise<PuzzleRecord[]>

// 查询所有游戏记录（供学习报告使用）
getAllPuzzleRecords(): Promise<PuzzleRecord[]>
```

---

## 7. 学习画像扩展

### 7.1 新增技能维度（ChildProfileService）

```typescript
{ key: 'logic_puzzle', label: '逻辑思维', level: 0, lastAssessed: 0, notes: '' }
{ key: 'observation', label: '观察力',   level: 0, lastAssessed: 0, notes: '' }
```

### 7.2 评估方式

不硬编码评估规则。AI 收到游戏结果（难度、用时、步数）后，在对话上下文中判断孩子表现，并通过 `child_profile(action:"update")` 自主调整技能等级。

---

## 8. 主题与无障碍

- 棋盘背景：`themeBackground`（聊天气泡色）
- 方块颜色：`themePrimary`，文字白色
- 空格：透明或 `themeSurface`
- 文字大小：格子尺寸的 45%
- 圆角：6vp
- 所有触控区域 ≥ 44vp（满足无障碍最低触摸目标）

---

## 9. 验收标准

1. 小星老师在对话中可发起数字华容道，孩子看到交互棋盘
2. 4 个难度级别棋盘均可正常打乱、操作、完成
3. 点击和滑动两种操作方式均有效
4. 拼图还原后自动提交结果，AI 给予反馈
5. 游戏记录写入 `puzzle_records` 表
6. `child_profile` 包含 `logic_puzzle` 和 `observation` 维度
7. 重新开始功能正常，已完成的棋盘不可再操作
8. 打乱时无动画闪烁，操作时有平滑过渡动画
