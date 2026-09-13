# CardShell 棋盘卡迁移 · 设计 Spec

**日期：** 2026-09-13
**版本：** v2（CardShell 第二波：3 张棋盘卡）
**前置：** `docs/superpowers/specs/2026-09-12-cardshell-design.md`（v1，7 张 quiz 卡已实施完成，分支 `carshell` @ 42112a3）
**范围：** NumberPuzzleCard / MazeCard / SudokuCard 三张 direct 类棋盘卡迁移到 CardShell 外壳；学写字 / 竖式 / AskUser 明确不在本期（结构不适配：启动器模式 / 演示步进 / 表单卡）

---

## 1. 背景

v1 已统一 7 张 quiz 类卡片。剩余三张棋盘卡（华容道/迷宫/数独）共享同一骨架（HeaderRow → WinBanner → 棋盘 → StatsGrid → 放弃/换一局），与 CardShell 的差异点：

| 差异点 | 现状（已核实） |
|---|---|
| 胜负横幅位置 | 在头部与棋盘**之间**（Shell 的 feedback 固定在 slot 之后） |
| 放弃动作 | 右对齐文字链 `放弃本局`（华容道 `:785` / 数独 `:917`）、`走不出去了？换一局 →`（迷宫 `:1022`）；Shell actions 区只会渲染「确认」 |
| 新纪录徽章 | 横幅内右侧药丸（三卡均有）；Shell feedback 无徽章位 |
| 外层尺寸 | `padding(14) + radius(14)`（inline）/ `padding(20) + radius(0)`（largeSize）；Shell 为 `12/12` |
| 头部徽章色 | 迷宫硬编码 `#FF9F43` 橙（`MazeCard.ets:627-636`）；Shell 用 themePrimary |
| 药丸样式 | 数独为「色底彩字」变体且仅 `isCompleted` 门控；Shell 为标准药丸 |
| SUCCESS_GREEN | `#22C55E` 私有常量在 4 个文件重复定义 |

## 2. 目标与非目标

**目标**
1. 三卡头部/胜负横幅/放弃动作/外层样式由 CardShell 统一渲染；棋盘 + 统计区留 slot 自绘。
2. Shell 契约最小扩展：横幅位置开关、放弃动作、新纪录徽章位。
3. 行为零变化：onAnswer payload、计时器、最佳成绩竞态守卫、恢复路径全部不动。

**非目标（本期明确不做）**
- 不做通用 stats/progress 区（三卡统计内容各异，抽象是过度设计；留 slot 自绘）。
- 不迁学写字 / 竖式 / AskUser。
- 不改三卡的棋盘渲染、手势（`priorityGesture` + `onTouch stopPropagation` 留 slot 内）、动画（winPop 行扫描等）。
- 不改 MessageBubble 挂载方式。

## 3. Shell 契约扩展（cardshell/ 三文件）

```typescript
// CardShellTypes.ets 追加
export interface CardShellConfig {
  // ...v1 既有字段全部不变...
  /** true 时反馈横幅渲染在 head 之后、slot 之前(棋盘卡庆祝横幅位); 默认 false */
  feedbackAboveSlot?: boolean
  /** true 时 actions 区渲染放弃文字链; 默认 false */
  usesGiveUp?: boolean
  /** 放弃文字链文案覆写; 默认 CardShellCopy.GIVE_UP('放弃本局') */
  giveUpLabel?: string
}

export class CardShellCopy {
  // ...v1 既有常量不变...
  static readonly GIVE_UP: string = '放弃本局'
  /** WinBanner / 新纪录 / best-stat 共用成功绿 (Tailwind green-500) */
  static readonly SUCCESS_GREEN: string = '#22C55E'
}

// CardShellState.ets 追加
@ObservedV2
export class CardShellState {
  // ...v1 既有字段全部不变...
  /** 反馈横幅右侧徽章, 如 '新纪录'; '' 不渲染 */
  @Trace feedbackBadge: string = ''
  /** 整局结束(胜或弃), 驱动放弃动作隐藏; 与 submitted 分离——放弃时不显示横幅 */
  @Trace isFinished: boolean = false
}

// CardShell.ets 追加
@Event onGiveUp: () => void = () => {}
```

**关键语义——`submitted` 与 `isFinished` 分离**：

| 事件 | submitted | isFinished | 效果 |
|---|---|---|---|
| 通关 | true | true | 庆祝横幅显示 + 放弃链隐藏 |
| 放弃 | **false** | true | 无横幅（与现状一致）+ 放弃链隐藏 + 头部药丸「已放弃」 |
| 已答恢复（胜局） | true（卡片按 hasWon 写入） | true | 庆祝横幅（标题 `已完成`）+ 药丸「已完成」 |
| 已答恢复（放弃局） | false | true | 无横幅 + 药丸「已放弃」（与现卡 `if (this.hasWon)` 门控一致） |

**feedback 区双形态**（与 `feedbackAboveSlot` 共变，本期仅棋盘卡开）：
- `feedbackAboveSlot: true` → **庆祝横幅**：门控仅看 `state.submitted`（**不含** isAnswered——与现三卡 `if (this.hasWon)` 门控一致：放弃局及放弃局的历史恢复都不显示横幅；恢复路径由卡片按 hasWon 写 `submitted`）。样式：`SUCCESS_GREEN` alpha 底（dark `'18'` / light `'0C'`）+ 1px 同色 alpha 边框 + 🎉 26vp + 标题（`state.feedbackTitle` 覆写，如 `太棒了！拼好了`）+ 次要行（`state.feedbackDetail`）+ 右侧徽章（`state.feedbackBadge`）。逐项照抄现三卡 WinBanner。
- 默认 → v1 反馈横幅（门控 `state.submitted || isAnswered`，success/error 1A alpha 底），已迁 7 卡零改动。

**actions 区**：`usesGiveUp && !state.isFinished && !isAnswered` 时渲染右对齐文字链（12vp `text_tertiary`，样式照抄现卡）；`usesConfirm` 逻辑不变。

**头部徽章**：统一 themePrimary 派生（`withColorAlpha(themePrimary, '18')` 底 + themePrimary 着色图标）——迷宫橙色徽章改此样式。

**外层**：三卡统一到 Shell 现行 12/12（inline）；largeSize 透明无边框路径与 v1 相同。

## 4. 三卡迁移映射

迁移顺序：**华容道 → 数独 → 迷宫**（复杂度递增），一卡一提交，可停在任意步。

| 卡 | head | feedback（above） | slot（卡片自绘，整体不动） | actions |
|---|---|---|---|---|
| NumberPuzzle | lightbulb 徽章 + `数字华容道` + 难度标签；药丸 `已完成`/`已放弃`（绿/橙，卡片写 state） | 胜：`太棒了！拼好了`（在线视图 `已完成`）+ `${time} · ${moves} 步` + `新纪录` | tile Flex 棋盘（PanGesture/priorityGesture/onTouch 全不动）+ StatsGrid 双卡 + winPop 动画 | 放弃本局 |
| Sudoku | dot_grid 徽章 + `数独` + 难度标签；药丸改**标准样式**，门控仍卡片自控（`isCompleted` 才写 headPill） | 胜：`太棒了！填好了` + `${time} · ${mistakes} 失误` + `新纪录` | 棋盘（冲突红格 #F87171 内联反馈不动）+ NumberPad | 放弃本局 |
| Maze | map 徽章**橙→themePrimary** + `走迷宫` + 难度标签 | 胜：`走出迷宫！`（在线视图 `已完成`）+ 用时/步数/🥕 n/N + `新纪录` | 纸质棋盘 + 3 StatCards + 放弃后绿色路线 overlay + `💡 绿色格子就是正确路线` 提示行 | `走不出去了？换一局 →`（giveUpLabel 覆写） |

**不动项清单（红线）**：
- onAnswer payload（`NumberPuzzleResult` / maze / sudoku 各自 JSON）结构零改动
- `bestScoresLoaded` 竞态守卫、Preferences 读写、`isNewBest` 异步置位语义
- 恢复路径：数独 `reconstructBoardFromPayload` 中途棋盘还原、迷宫 give-up 后 `revealHint()` 重放、华容道 solved 棋盘还原
- `largeSize` 双视图、`reduceMotion`（三卡无此参数）
- `SUCCESS_GREEN` 收口后，华容道/迷宫/数独改引 `CardShellCopy.SUCCESS_GREEN`；学写字文件内私有常量本期不动（卡不迁移，避免无关文件入 diff）

## 5. 有意的视觉统一（仅 4 处，其余逐项照抄）

1. 外层 inline `padding(14)→12`、`radius(14)→12`（2vp 微调）
2. 迷宫头部徽章 `#FF9F43` → themePrimary 派生
3. 数独头部药丸变体 → Shell 标准药丸
4. `SUCCESS_GREEN` 收口为 `CardShellCopy.SUCCESS_GREEN` 单一定义

## 6. 测试与验证

- 每卡迁移后 `hvigorw assembleHap` 编译验证（CLI 无 lint/test，按项目惯例）。
- 每卡人工回归清单：
  1. 正常游玩 → 通关 → 庆祝横幅（棋盘**上方**）+ 新纪录徽章 + 药丸「已完成」
  2. 放弃 → 无横幅 + 药丸「已放弃」+ 放弃链消失（迷宫：绿色路线揭示 + 提示行）
  3. 历史会话已答恢复（isAnswered + answeredPayload，含数独中途棋盘）
  4. 深色模式 + 主题切换，外壳颜色跟随（含迷宫徽章新 themePrimary）
  5. largeSize 视图（若该卡有全屏路径）
  6. 最佳成绩显示与新纪录判定（含竞态守卫路径）

## 7. 风险与回滚

| 风险 | 缓解 |
|---|---|
| `isFinished`/`submitted` 分离引入动作区显隐回归 | 状态表（§3）逐行对应现卡门控；一卡一提交可单独 revert |
| 庆祝横幅上移到 head 之后导致头部间距/视觉回归 | 横幅样式逐项照抄现卡；人工回归清单第 1 项覆盖 |
| 迷宫 3 StatCards + 路线 overlay 留 slot 后与 shell 间距叠加 | slot 内布局不动，仅外层容器换；间距用 space 与现卡一致 |
| @Event onGiveUp 新增对已迁 7 卡的影响 | 带默认值的 @Event，7 卡不传即零影响 |

## 8. 后续方向（不阻塞本期）

- 学写字 / 竖式 / AskUser 的外壳化（需先解决启动器模式、步进控制、表单语义——契约改动大）
- 通用 stats/progress 区（若 direct 卡数量继续增长）
- 三卡 StatsGrid 的统一新纪录边框样式（现各自实现）
