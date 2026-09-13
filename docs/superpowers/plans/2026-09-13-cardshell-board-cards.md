# CardShell v2 · 3 张棋盘卡迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 NumberPuzzleCard / SudokuCard / MazeCard 三张棋盘卡的外壳（头部/胜负横幅/放弃动作/外层样式）迁入 CardShell 统一渲染，棋盘与统计区留 slot 自绘，游戏逻辑零变化。

**Architecture:** CardShell 契约最小扩展（`feedbackAboveSlot` 庆祝横幅位 + `usesGiveUp`/`giveUpLabel`/`onGiveUp` 放弃动作 + `feedbackBadge`/`isFinished` 状态），三卡按「华容道 → 数独 → 迷宫」顺序逐张迁移，一卡一提交。棋盘渲染、手势、计时器、最佳成绩竞态守卫、恢复路径全部不动。

**Tech Stack:** ArkTS（HarmonyOS 6 / API 23，@ComponentV2 / @ObservedV2 / @BuilderParam / @Event）

**Spec:** `docs/superpowers/specs/2026-09-13-cardshell-board-cards-design.md`（本计划从 spec 出发，执行者需同时阅读 spec；前置 v1 spec `2026-09-12-cardshell-design.md` 已实施完成，分支 `carshell` @ e2e6e62）

## Global Constraints

- **构建验证命令**（每个任务都要跑，CLI 无 lint/test 可用，assembleHap 干净通过 = 验证通过）：
  ```bash
  DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
    /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
    --mode module -p product=default -p buildMode=debug
  ```
- **红线（spec §4 不动项清单）**：
  - `onAnswer` payload 结构零改动（`NumberPuzzleResult` / `SudokuResult` / `MazeResult` 的构造与字段一字不动）
  - `bestScoresLoaded` 竞态守卫、Preferences 读写、`isNewBest*` 异步置位语义不动（只在置位后追加 shellState 徽章写入）
  - 恢复路径不动：数独 `reconstructBoardFromPayload`、迷宫 give-up 恢复的 `revealHint()` 重放、华容道 solved 棋盘还原
  - 棋盘渲染、手势（`priorityGesture` + `onTouch stopPropagation`）、winPop 动画、NumberPad、冲突红格全部留 slot 内不动
  - `components/MessageBubble.ets` 不改；学写字/竖式/AskUser 不迁；`HandwritingCard.ets` 内私有 `SUCCESS_GREEN` 不动（避免无关文件入 diff）
- **已迁 7 卡零改动**：`@Event onGiveUp` 带默认值，7 卡不传即零影响。每张卡迁移后 `git diff --stat` 确认只有预期文件变更。
- **状态语义表（spec §3，迁移必须逐行对齐）**：

  | 事件 | submitted | isFinished | 效果 |
  |---|---|---|---|
  | 通关 | true | true | 庆祝横幅显示 + 放弃链隐藏 |
  | 放弃 | false | true | 无横幅 + 放弃链隐藏 + 药丸「已放弃」 |
  | 已答恢复（胜局） | true（= hasWon） | true | 庆祝横幅 + 药丸「已完成」 |
  | 已答恢复（放弃局） | false | true | 无横幅 + 药丸「已放弃」 |

  三卡统一落法：`syncShellState()` 内 `submitted = this.hasWon`、`isFinished = this.isCompleted`。
- **headPill 色值约定**（v1 CategorizationCard 先例，字符串形式）：胜 `'#4CAF50'`（= status_success hex）/ 弃 `'#FF9F43'`。
- **文案集中**：`放弃本局` 落在 `CardShellCopy.GIVE_UP`，卡片内不得再出现；迷宫用 `giveUpLabel: '走不出去了？换一局 →'` 覆写。
- **ArkTS 严格模式陷阱**（项目 MEMORY.md）：@Builder 体内不能写 `const`、不能提前 `return`；对象字面量必须显式类型标注；`Row.alignItems` 用 `VerticalAlign`、`Column.alignItems` 用 `HorizontalAlign`；@Local 普通对象必须整体重赋值才触发响应（shellConfig 用 rebuildShellConfig() 重赋值）。
- **每个任务一个 commit**，消息格式 `feat(cardshell): ...` / `refactor(cardshell): ...`。
- 图标只用现有代码已验证的 `sys.symbol.*` 名：`lightbulb`（NumberPuzzleCard.ets:537 现用）、`dot_grid_2x2`（SudokuCard.ets:605 现用）、`map`（MazeCard.ets:628 现用）。

---

### Task 1: Shell 契约扩展（庆祝横幅位 + 放弃动作 + 新纪录徽章）

**Files:**
- Modify: `entry/src/main/ets/components/cardshell/CardShellTypes.ets`
- Modify: `entry/src/main/ets/components/cardshell/CardShellState.ets`
- Modify: `entry/src/main/ets/components/cardshell/CardShell.ets`

**Interfaces:**
- Consumes: v1 既有契约（CardShellConfig 8 必填字段 / CardShellCopy 7 常量 / CardShellState 9 @Trace 字段 / CardShell 7 区）。
- Produces（Task 2/3/4 依赖）:
  - `CardShellConfig` 追加可选字段：`feedbackAboveSlot?: boolean` / `usesGiveUp?: boolean` / `giveUpLabel?: string`
  - `CardShellCopy` 追加常量：`GIVE_UP = '放弃本局'` / `SUCCESS_GREEN = '#22C55E'`
  - `CardShellState` 追加 @Trace 字段：`feedbackBadge: string`（'' 不渲染）/ `isFinished: boolean`
  - `CardShell` 追加 `@Event onGiveUp: () => void`（带默认值，已迁 7 卡不传零影响）
  - `feedbackAboveSlot === true` 时：feedback 区换为 CelebrationRegion，渲染在 HeadRegion 之后、StemRegion 之前，门控**仅** `state.submitted`（不含 isAnswered——放弃局恢复不显示横幅）
  - ActionsRegion 追加放弃文字链：`usesGiveUp === true && !state.isFinished && !isAnswered` 时右对齐渲染

- [ ] **Step 1: CardShellTypes.ets 追加 3 个可选字段 + 2 个常量**

在 `CardShellConfig` 接口末尾（`correctAnswerLabel: string` 之后、接口闭合 `}` 之前）追加：

```typescript
  /** true 时反馈横幅渲染在 head 之后、slot 之前(棋盘卡庆祝横幅位); 默认 false */
  feedbackAboveSlot?: boolean
  /** true 时 actions 区渲染放弃文字链; 默认 false */
  usesGiveUp?: boolean
  /** 放弃文字链文案覆写; '' 或不传用 CardShellCopy.GIVE_UP('放弃本局') */
  giveUpLabel?: string
```

在 `CardShellCopy` 类末尾（`FEEDBACK_CORRECT` 之后）追加：

```typescript
  static readonly GIVE_UP: string = '放弃本局'
  /** WinBanner / 新纪录 / best-stat 共用成功绿 (Tailwind green-500) */
  static readonly SUCCESS_GREEN: string = '#22C55E'
```

- [ ] **Step 2: CardShellState.ets 追加 2 个 @Trace 字段**

在 `headPillColor` 字段之后、类闭合 `}` 之前追加：

```typescript
  /** 反馈横幅右侧徽章, 如 '新纪录'; '' 不渲染 */
  @Trace feedbackBadge: string = ''
  /** 整局结束(胜或弃), 驱动放弃动作隐藏; 与 submitted 分离——放弃时不显示横幅 */
  @Trace isFinished: boolean = false
```

- [ ] **Step 3: CardShell.ets 加 onGiveUp 事件 + isDarkMode getter**

在 `@Event onRequestReplay` 之后追加：

```typescript
  /** 放弃本局(棋盘卡); 带默认值, 不传的卡片零影响 */
  @Event onGiveUp: () => void = () => {}
```

在 `themeAiBubble` getter 之后追加：

```typescript
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }
```

- [ ] **Step 4: CardShell.ets build() 区序分支**

把 build() 内的 Column 内容（现 :44-51 的 6 行区序）替换为：

```typescript
    Column({ space: 10 }) {
      this.HeadRegion()
      if (this.config.feedbackAboveSlot === true) {
        this.CelebrationRegion()
      }
      this.StemRegion()
      this.ReplayRegion()
      this.slot()
      if (this.config.feedbackAboveSlot !== true) {
        this.FeedbackRegion()
      }
      this.ActionsRegion()
    }
```

并把文件头注释（:4）`7 区固定顺序: head → stem → replay(可选) → slot(卡片自绘) → feedback → actions。` 改为：

```typescript
 * 7 区固定顺序: head → [feedbackAboveSlot 时: celebration] → stem → replay(可选)
 * → slot(卡片自绘) → [默认: feedback] → actions。
```

- [ ] **Step 5: CardShell.ets 新增 CelebrationRegion @Builder**

在 `FeedbackRegion` @Builder 之前插入。样式逐项照抄 NumberPuzzleCard 现行 WinBanner（`NumberPuzzleCard.ets:575-610`），仅做参数化替换（hasWon→state.submitted、isAnswered 三元→feedbackTitle 覆写、isNewBest→feedbackBadge）：

```typescript
  // ================ celebration: 棋盘卡庆祝横幅(feedbackAboveSlot) ====
  // 门控仅看 submitted(不含 isAnswered): 放弃局及放弃局的历史恢复都不显示横幅,
  // 与迁移前三卡的 if (hasWon) 门控一致; 恢复路径由卡片按 hasWon 写 submitted。
  @Builder
  CelebrationRegion() {
    if (this.state.submitted) {
      Row({ space: 10 }) {
        Text('🎉')
          .fontSize(26)
        Column() {
          Text(this.state.feedbackTitle !== '' ? this.state.feedbackTitle : this.config.feedbackTitleCorrect)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.status_success'))
          if (this.state.feedbackDetail !== '') {
            Text(this.state.feedbackDetail)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.state.feedbackBadge !== '') {
          Text(this.state.feedbackBadge)
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor(CardShellCopy.SUCCESS_GREEN)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(withColorAlpha(CardShellCopy.SUCCESS_GREEN, this.isDarkMode ? '18' : '0C'))
      .borderRadius(12)
      .border({
        width: 1,
        color: withColorAlpha(CardShellCopy.SUCCESS_GREEN, this.isDarkMode ? '38' : '28'),
        style: BorderStyle.Solid
      })
    }
  }
```

- [ ] **Step 6: CardShell.ets ActionsRegion 追加放弃文字链**

在 ActionsRegion 现有 confirm Row 块（`if (this.config.usesConfirm && ...)` 整块）之后、@Builder 闭合之前追加：

```typescript
    if (this.config.usesGiveUp === true && !this.state.isFinished && !this.isAnswered) {
      Row() {
        Blank()
        Text(this.config.giveUpLabel ?? CardShellCopy.GIVE_UP)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .padding(8)
          .onClick(() => {
            this.onGiveUp()
          })
      }
      .width('100%')
    }
```

- [ ] **Step 7: 构建验证**

Run: Global Constraints 的 assembleHap 命令。Expected: BUILD SUCCESSFUL（扩展均为可选字段 + 带默认值 @Event，已迁 7 卡与新分支互不引用，零破坏）。

- [ ] **Step 8: Commit**

```bash
git add entry/src/main/ets/components/cardshell/CardShellTypes.ets \
        entry/src/main/ets/components/cardshell/CardShellState.ets \
        entry/src/main/ets/components/cardshell/CardShell.ets
git commit -m "feat(cardshell): 契约扩展——庆祝横幅位/放弃动作/新纪录徽章/完成态"
```

---

### Task 2: NumberPuzzleCard 迁移（数字华容道）

**Files:**
- Modify: `entry/src/main/ets/components/NumberPuzzleCard.ets`

**Interfaces:**
- Consumes: Task 1 的全部产出（CardShellConfig 可选字段 / CardShellCopy.GIVE_UP+SUCCESS_GREEN / CardShellState.feedbackBadge+isFinished / CardShell.onGiveUp / CelebrationRegion / 放弃文字链）。
- Produces: 迁移后的 NumberPuzzleCard（对外 API `@Param toolCall/isAnswered/answeredPayload/largeSize` + `@Event onAnswer` 完全不变；MessageBubble 零改动）。

**迁移参照代码位置（迁移前行号）**：外层 build `:509-530`、HeaderRow `:532-573`、WinBanner `:575-610`、ActionRow `:780-793`、私有常量 `:55`、stat 边框 SUCCESS_GREEN `:486`、evaluateWin `:335-362`、handleGiveUp `:383-398`、parsePreviousResult `:155-170`、aboutToAppear `:123-131`、saveBestScoresIfImproved `:188-212`。

- [ ] **Step 1: 加 import 与 shell 字段**

文件头 import 区追加：

```typescript
import { CardShell } from './cardshell/CardShell'
import { CardShellConfig, CardShellCopy } from './cardshell/CardShellTypes'
import { CardShellState } from './cardshell/CardShellState'
```

在 `@Local bestScoresLoaded` 字段（:50）之后、`private timerId` 之前追加：

```typescript
  @Local shellConfig: CardShellConfig = {
    title: '数字华容道',
    subtitle: '',
    icon: $r('sys.symbol.lightbulb'),
    stem: '',
    hasAudio: false,
    usesConfirm: false,
    feedbackTitleCorrect: '太棒了！拼好了',
    correctAnswerLabel: '',
    feedbackAboveSlot: true,
    usesGiveUp: true,
    giveUpLabel: ''
  }
  private shellState: CardShellState = new CardShellState()
```

同时删除私有常量（:54-55 两行，含注释）：

```typescript
  // WinBanner / "新纪录" / best-stat 边框共用的成功绿 (Tailwind green-500, 与琥珀 tile 调色板协调)
  private readonly SUCCESS_GREEN: string = '#22C55E'
```

- [ ] **Step 2: 加 rebuildShellConfig + syncShellState 方法**

在 `aboutToAppear` 之前插入两个方法：

```typescript
  // subtitle 依赖 parseDifficulty/parsePreviousResult 之后才稳定的 gridSize, 必须整体重赋值触发响应
  private rebuildShellConfig(): void {
    this.shellConfig = {
      title: '数字华容道',
      subtitle: this.difficultyLabel,
      icon: $r('sys.symbol.lightbulb'),
      stem: '',
      hasAudio: false,
      usesConfirm: false,
      feedbackTitleCorrect: '太棒了！拼好了',
      correctAnswerLabel: '',
      feedbackAboveSlot: true,
      usesGiveUp: true,
      giveUpLabel: ''
    }
  }

  // 外壳状态同步: submitted=hasWon(胜才显示庆祝横幅), isFinished=isCompleted(隐藏放弃链)
  private syncShellState(): void {
    this.shellState.submitted = this.hasWon
    this.shellState.isFinished = this.isCompleted
    this.shellState.isCorrect = this.hasWon
    this.shellState.feedbackTitle = this.isAnswered ? '已完成' : ''
    this.shellState.feedbackDetail = `${this.formatTime(this.elapsedSeconds)} · ${this.moveCount} 步`
    this.shellState.feedbackBadge = this.isNewBest ? '新纪录' : ''
    if (this.isAnswered || this.isCompleted) {
      this.shellState.headPill = this.hasWon ? '已完成' : '已放弃'
      this.shellState.headPillColor = this.hasWon ? '#4CAF50' : '#FF9F43'
    } else {
      this.shellState.headPill = ''
    }
  }
```

- [ ] **Step 3: aboutToAppear 末尾接同步**

`aboutToAppear`（:123-131）在 `this.loadBestScores(this.gridSize)` 之前插入两行，改为：

```typescript
  aboutToAppear(): void {
    this.parseDifficulty()
    if (this.isAnswered) {
      this.parsePreviousResult()
    } else {
      this.shuffleGameBoard()
    }
    this.rebuildShellConfig()
    this.syncShellState()
    this.loadBestScores(this.gridSize)
  }
```

`parsePreviousResult`（:155-170）的 try/catch 之后**不追加任何代码**——syncShellState 已在 aboutToAppear 统一调用（payload 解析失败时 isCompleted=false、hasWon=false，sync 会正确产出无横幅 + `isAnswered` 门控的「已放弃」药丸，与迁移前 HeaderRow 的 `isAnswered || isCompleted` 门控逐行一致）。

- [ ] **Step 4: 三个事件处理器追加 syncShellState**

`evaluateWin`（:335-362）末尾 `this.saveBestScoresIfImproved()` 之后追加一行：

```typescript
    this.syncShellState()
```

`handleGiveUp`（:383-398）末尾 `this.onAnswer(...)` 之后追加一行：

```typescript
    this.syncShellState()
```

`saveBestScoresIfImproved`（:188-212）中 `this.isNewBest = isNewBestTime || isNewBestMoves`（:208）之后追加三行（isNewBest 异步置位后的响应式徽章升级——与迁移前 WinBanner 直接读 isNewBest 的效果等价）：

```typescript
      if (this.isNewBest) {
        this.shellState.feedbackBadge = '新纪录'
      }
```

**注意**：`bestScoresLoaded` 守卫、prefs 读写、isNewBest 置位逻辑一行不动，只做追加。

- [ ] **Step 5: 替换 build()**

把整个 build()（:509-530，含外层 Column 样式链）替换为：

```typescript
  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      largeSize: this.largeSize,
      onGiveUp: () => {
        this.handleGiveUp()
      }
    }) {
      this.BoardPanel()
      this.StatsGrid()
    }
  }
```

- [ ] **Step 6: 删除三个外壳 Builder + 收口 SUCCESS_GREEN 引用**

- 整体删除 `HeaderRow` @Builder（:532-573）
- 整体删除 `WinBanner` @Builder（:575-610）
- 整体删除 `ActionRow` @Builder（:780-793）
- `getStatCardBorderColor` 内 `withColorAlpha(this.SUCCESS_GREEN, '60')`（:486）改为 `withColorAlpha(CardShellCopy.SUCCESS_GREEN, '60')`
- 检查 `themeAiBubble` getter（:61-63）：迁移后若全文零引用（原唯一引用是 :525 外层背景）则删除该 getter；`themePrimary` / `isDarkMode` 仍被 tile 渐变 / 棋盘背景 / stat 边框使用，保留。用 grep 确认后再删。

**BoardPanel / StatsGrid / StatCard / Tile / EmptySlot / 手势 / winPop / 计时器全部不动。**

- [ ] **Step 7: 构建验证 + 引用核查**

Run: assembleHap 命令。Expected: BUILD SUCCESSFUL。
另跑（Expected 全部 0 命中）：

```bash
grep -n "HeaderRow\|WinBanner\|ActionRow\|this.SUCCESS_GREEN\|放弃本局" \
  entry/src/main/ets/components/NumberPuzzleCard.ets
```

- [ ] **Step 8: Commit**

```bash
git add entry/src/main/ets/components/NumberPuzzleCard.ets
git commit -m "refactor(cardshell): NumberPuzzleCard 迁移到 CardShell 外壳"
```

---

### Task 3: SudokuCard 迁移（数独）

**Files:**
- Modify: `entry/src/main/ets/components/SudokuCard.ets`

**Interfaces:**
- Consumes: Task 1 全部产出。
- Produces: 迁移后的 SudokuCard（对外 API 与 payload 不变）。

**与 Task 2 的差异点（本卡特有）**：
1. 头部药丸门控是 `isCompleted` **单条件**（迁移前 `:629`），不是 `isAnswered || isCompleted`——payload 解析失败时不显示药丸，保持现状。
2. WinBanner 标题是常量 `'太棒了！填好了'`，**无** isAnswered 变体——`feedbackTitle` 恒为 `''`。
3. 徽章条件是 `isNewBestTime || isNewBestMistakes` 双布尔。
4. 原药丸为「色底彩字」变体 → 统一为 Shell 标准药丸（白字 + 实色 headPillColor），这是 spec §5 第 3 处有意视觉统一。
5. 原横幅正文 13/11vp → 统一为 CelebrationRegion 的 15/12vp（随单一横幅实现而来的有意统一，同 spec §4「逐项照抄 + 单一实现」）。

**迁移参照代码位置（迁移前行号）**：私有常量 `:79`、build `:577-599`、HeaderRow `:601-643`、WinBanner `:645-681`、ActionRow `:913-926`、winPop 边框 SUCCESS_GREEN `:754`、stat 边框 `:907`、evaluateWin `:423-447`、handleGiveUp `:468-483`、parsePreviousResult `:194-217`、saveBestScoresIfImproved `:234-257`、aboutToAppear `:134-151`。

- [ ] **Step 1: 加 import 与 shell 字段，删私有常量**

import 区追加（与 Task 2 相同的三行）：

```typescript
import { CardShell } from './cardshell/CardShell'
import { CardShellConfig, CardShellCopy } from './cardshell/CardShellTypes'
import { CardShellState } from './cardshell/CardShellState'
```

在 `@Local pressedDigitKey`（:75）之后、`private timerId` 之前追加：

```typescript
  @Local shellConfig: CardShellConfig = {
    title: '数独',
    subtitle: '',
    icon: $r('sys.symbol.dot_grid_2x2'),
    stem: '',
    hasAudio: false,
    usesConfirm: false,
    feedbackTitleCorrect: '太棒了！填好了',
    correctAnswerLabel: '',
    feedbackAboveSlot: true,
    usesGiveUp: true,
    giveUpLabel: ''
  }
  private shellState: CardShellState = new CardShellState()
```

删除私有常量（:79，保留 `:80` 的 `CONFLICT_RED` 不动）：

```typescript
  private readonly SUCCESS_GREEN: string = '#22C55E'
```

- [ ] **Step 2: 加 rebuildShellConfig + syncShellState 方法**

在 `aboutToAppear` 之前插入：

```typescript
  // subtitle 依赖 parseArgs/parsePreviousResult 之后才稳定的 difficulty, 必须整体重赋值触发响应
  private rebuildShellConfig(): void {
    this.shellConfig = {
      title: '数独',
      subtitle: this.difficultyLabel,
      icon: $r('sys.symbol.dot_grid_2x2'),
      stem: '',
      hasAudio: false,
      usesConfirm: false,
      feedbackTitleCorrect: '太棒了！填好了',
      correctAnswerLabel: '',
      feedbackAboveSlot: true,
      usesGiveUp: true,
      giveUpLabel: ''
    }
  }

  // 外壳状态同步: 药丸门控 isCompleted 单条件(与迁移前 :629 一致, payload 解析失败不显示药丸);
  // 横幅标题无 isAnswered 变体, feedbackTitle 恒 ''
  private syncShellState(): void {
    this.shellState.submitted = this.hasWon
    this.shellState.isFinished = this.isCompleted
    this.shellState.isCorrect = this.hasWon
    this.shellState.feedbackTitle = ''
    this.shellState.feedbackDetail = `${this.formatTime(this.elapsedSeconds)} · ${this.mistakeCount} 失误`
    this.shellState.feedbackBadge = (this.isNewBestTime || this.isNewBestMistakes) ? '新纪录' : ''
    if (this.isCompleted) {
      this.shellState.headPill = this.hasWon ? '已完成' : '已放弃'
      this.shellState.headPillColor = this.hasWon ? '#4CAF50' : '#FF9F43'
    } else {
      this.shellState.headPill = ''
    }
  }
```

- [ ] **Step 3: aboutToAppear 末尾接同步**

`aboutToAppear`（:134-151）在 `this.loadBestScores(this.difficulty)` 之前插入两行：

```typescript
    this.rebuildShellConfig()
    this.syncShellState()
```

`parsePreviousResult`（:194-217，含 `reconstructBoardFromPayload` 棋盘还原）**一行不动**。

- [ ] **Step 4: 三个事件处理器追加 syncShellState / 徽章升级**

`evaluateWin`（:423-447）末尾 `this.saveBestScoresIfImproved()` 之后追加：

```typescript
    this.syncShellState()
```

`handleGiveUp`（:468-483）末尾 `this.onAnswer(...)` 之后追加：

```typescript
    this.syncShellState()
```

`saveBestScoresIfImproved`（:234-257）中 `this.isNewBestMistakes = isNewBestMistakes`（:253）之后追加三行：

```typescript
      if (isNewBestTime || isNewBestMistakes) {
        this.shellState.feedbackBadge = '新纪录'
      }
```

- [ ] **Step 5: 替换 build()**

把整个 build()（:577-599，含外层 Column 样式链）替换为：

```typescript
  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      largeSize: this.largeSize,
      onGiveUp: () => {
        this.handleGiveUp()
      }
    }) {
      this.BoardPanel()
      this.StatsGrid()
    }
  }
```

- [ ] **Step 6: 删除三个外壳 Builder + 收口 SUCCESS_GREEN 引用**

- 整体删除 `HeaderRow` @Builder（:601-643，含 `:629-638` 的色底彩字药丸变体）
- 整体删除 `WinBanner` @Builder（:645-681）
- 整体删除 `ActionRow` @Builder（:913-926）
- winPop 格边框 `this.SUCCESS_GREEN`（:754）→ `CardShellCopy.SUCCESS_GREEN`
- StatCard 边框 `this.SUCCESS_GREEN`（:907）→ `CardShellCopy.SUCCESS_GREEN`
- `CONFLICT_RED`（:80）及其全部使用**不动**（slot 内联冲突反馈）
- `themeAiBubble` getter 仍被 DigitKey 背景（:806/:829）使用，**保留**

**BoardPanel / CellView / NumberPad / DigitKey / 冲突红格 / winPop / 计时器全部不动。**

- [ ] **Step 7: 构建验证 + 引用核查**

Run: assembleHap 命令。Expected: BUILD SUCCESSFUL。
另跑（Expected 全部 0 命中）：

```bash
grep -n "HeaderRow\|WinBanner\|ActionRow\|this.SUCCESS_GREEN\|放弃本局" \
  entry/src/main/ets/components/SudokuCard.ets
```

- [ ] **Step 8: Commit**

```bash
git add entry/src/main/ets/components/SudokuCard.ets
git commit -m "refactor(cardshell): SudokuCard 迁移到 CardShell 外壳"
```

---

### Task 4: MazeCard 迁移（走迷宫）

**Files:**
- Modify: `entry/src/main/ets/components/MazeCard.ets`

**Interfaces:**
- Consumes: Task 1 全部产出。
- Produces: 迁移后的 MazeCard（对外 API 与 payload 不变）。

**与 Task 2 的差异点（本卡特有）**：
1. 头部徽章是硬编码橙 `#FF9F43`（:630/:635）→ 换 Shell 的 themePrimary 派生头部（spec §5 第 2 处有意视觉统一，随 HeaderRow 删除自动完成）。
2. 放弃文案 `走不出去了？换一局 →`（:1022）走 `giveUpLabel` 覆写。
3. ActionRow 是双态：放弃链 **或** 提示行 `💡 绿色格子就是正确路线`（:1029-1034，`!hasWon && hintKeys.size > 0` 门控）——提示行必须**移入 slot**（StatsGrid 之后），Shell actions 区只渲染放弃链。
4. feedbackDetail 带胡萝卜收集后缀。
5. `SUCCESS_GREEN` 是 `private static readonly`（:97），引用形式是 `MazeCard.SUCCESS_GREEN`。
6. give-up 时 `revealHint()` 揭示路线 + 历史放弃局恢复时 `revealHint()` 重放——全部不动。

**迁移参照代码位置（迁移前行号）**：静态常量 `:97`、build `:601-622`、HeaderRow `:624-664`、WinBanner `:666-701`、ActionRow `:1017-1037`、提示格背景 `:791`、stat 边框 `:945/:976/:1009`、handleWin `:549-569`、handleGiveUp `:571-590`、saveBestScoresIfImproved `:320-350`、parseAndInitialize `:207-240+`、aboutToAppear `:199-201`。

- [ ] **Step 1: 加 import 与 shell 字段，删静态常量**

import 区追加（与 Task 2 相同的三行）：

```typescript
import { CardShell } from './cardshell/CardShell'
import { CardShellConfig, CardShellCopy } from './cardshell/CardShellTypes'
import { CardShellState } from './cardshell/CardShellState'
```

在 `@Local hintKeys`（:94）之后、`private timerId` 之前追加：

```typescript
  @Local shellConfig: CardShellConfig = {
    title: '走迷宫',
    subtitle: '',
    icon: $r('sys.symbol.map'),
    stem: '',
    hasAudio: false,
    usesConfirm: false,
    feedbackTitleCorrect: '走出迷宫！',
    correctAnswerLabel: '',
    feedbackAboveSlot: true,
    usesGiveUp: true,
    giveUpLabel: '走不出去了？换一局 →'
  }
  private shellState: CardShellState = new CardShellState()
```

删除静态常量（:97）：

```typescript
  private static readonly SUCCESS_GREEN: string = '#22C55E'
```

- [ ] **Step 2: 加 rebuildShellConfig + syncShellState + HintCaption**

在 `aboutToAppear` 之前插入：

```typescript
  // subtitle 依赖 parseAndInitialize 之后才稳定的 difficulty, 必须整体重赋值触发响应
  private rebuildShellConfig(): void {
    this.shellConfig = {
      title: '走迷宫',
      subtitle: this.difficultyLabel,
      icon: $r('sys.symbol.map'),
      stem: '',
      hasAudio: false,
      usesConfirm: false,
      feedbackTitleCorrect: '走出迷宫！',
      correctAnswerLabel: '',
      feedbackAboveSlot: true,
      usesGiveUp: true,
      giveUpLabel: '走不出去了？换一局 →'
    }
  }

  // 外壳状态同步: submitted=hasWon, isFinished=isCompleted; 明细带胡萝卜收集后缀
  private syncShellState(): void {
    this.shellState.submitted = this.hasWon
    this.shellState.isFinished = this.isCompleted
    this.shellState.isCorrect = this.hasWon
    this.shellState.feedbackTitle = this.isAnswered ? '已完成' : ''
    let detail: string = `${this.formatTime(this.elapsedSeconds)} · ${this.moveCount} 步`
    if (this.maze !== null && this.maze.starsTotal > 0) {
      detail += ` · 🥕${this.starsCollected}/${this.maze.starsTotal}`
    }
    this.shellState.feedbackDetail = detail
    this.shellState.feedbackBadge = this.isNewBest ? '新纪录' : ''
    if (this.isAnswered || this.isCompleted) {
      this.shellState.headPill = this.hasWon ? '已完成' : '已放弃'
      this.shellState.headPillColor = this.hasWon ? '#4CAF50' : '#FF9F43'
    } else {
      this.shellState.headPill = ''
    }
  }
```

- [ ] **Step 3: aboutToAppear 末尾接同步**

`aboutToAppear`（:199-201）改为：

```typescript
  aboutToAppear(): void {
    this.parseAndInitialize()
    this.rebuildShellConfig()
    this.syncShellState()
  }
```

`parseAndInitialize`（:207 起，含历史放弃局 `revealHint()` 重放 :228-230）**一行不动**。

- [ ] **Step 4: 三个事件处理器追加 syncShellState / 徽章升级**

`handleWin`（:549-569）末尾 `this.onAnswer(...)` 之后追加：

```typescript
    this.syncShellState()
```

`handleGiveUp`（:571-590，含 `revealHint()` :579）末尾 `this.onAnswer(...)` 之后追加：

```typescript
    this.syncShellState()
```

`saveBestScoresIfImproved`（:320-350）的 `if (isNew) { ... }` 块内、`this.bestStars = Math.max(...)`（:348）之后追加一行：

```typescript
      this.shellState.feedbackBadge = '新纪录'
```

（追加后该块为：`this.isNewBest = true` / 三个 best 赋值 / 徽章行。守卫与 prefs 逻辑一行不动。）

- [ ] **Step 5: 替换 build() + 新增 HintCaption @Builder**

把整个 build()（:601-622，含外层 Column 样式链）替换为：

```typescript
  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      largeSize: this.largeSize,
      onGiveUp: () => {
        this.handleGiveUp()
      }
    }) {
      this.MazePanel()
      this.StatsGrid()
      this.HintCaption()
    }
  }

  // 放弃后的路线提示行 — 原 ActionRow 的 else 分支, 留 slot(Shell actions 区只渲染放弃链)
  @Builder
  HintCaption() {
    if (!this.hasWon && this.hintKeys.size > 0) {
      Row() {
        Blank()
        Text('💡 绿色格子就是正确路线')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .padding(8)
      }
      .width('100%')
    }
  }
```

- [ ] **Step 6: 删除三个外壳 Builder + 收口 SUCCESS_GREEN 引用**

- 整体删除 `HeaderRow` @Builder（:624-664，含 :630/:635 的橙色徽章与 themeAiBubble 字色 hack——themePrimary 头部由 Shell 提供）
- 整体删除 `WinBanner` @Builder（:666-701）
- 整体删除 `ActionRow` @Builder（:1017-1037，放弃链已入 Shell，提示行已入 HintCaption）
- 提示格背景 `MazeCard.SUCCESS_GREEN`（:791）→ `CardShellCopy.SUCCESS_GREEN`
- 三个 stat 边框 `MazeCard.SUCCESS_GREEN`（:945/:976/:1009）→ `CardShellCopy.SUCCESS_GREEN`
- 检查 `themeAiBubble` getter（:99-101）：迁移后若全文零引用（原引用是 :630 字色 hack；纸面调色板用的是自有 hex）则删除；grep 确认后再删。`isDarkMode` 仍被纸面调色板使用，保留。

**MazePanel / MazeCellView / 玩家 overlay / priorityGesture / onTouch stopPropagation / 纸面调色板 / 计时器全部不动。**

- [ ] **Step 7: 构建验证 + 引用核查**

Run: assembleHap 命令。Expected: BUILD SUCCESSFUL。
另跑（Expected：前两条 0 命中；第三条恰好 1 命中——giveUpLabel 字段本身）：

```bash
grep -n "HeaderRow\|WinBanner\|ActionRow\|MazeCard.SUCCESS_GREEN" \
  entry/src/main/ets/components/MazeCard.ets
grep -cn "放弃本局" entry/src/main/ets/components/MazeCard.ets
grep -n "走不出去了？换一局" entry/src/main/ets/components/MazeCard.ets
```

- [ ] **Step 8: Commit**

```bash
git add entry/src/main/ets/components/MazeCard.ets
git commit -m "refactor(cardshell): MazeCard 迁移到 CardShell 外壳"
```

---

### Task 5: 收尾核查（漂移 grep + 终验构建）

**Files:**
- 无新增改动（本任务是验证门；发现漂移才产生修复 commit）

**Interfaces:**
- Consumes: Task 1-4 全部产出。
- Produces: 分支级验证记录（漂移 grep 全绿 + 干净构建）。

- [ ] **Step 1: 漂移 grep 套件**

依次运行，Expected 逐条核对：

```bash
# 1. 三卡外壳 Builder 全部清除 → 0 命中
grep -n "HeaderRow\|WinBanner\|ActionRow" \
  entry/src/main/ets/components/NumberPuzzleCard.ets \
  entry/src/main/ets/components/SudokuCard.ets \
  entry/src/main/ets/components/MazeCard.ets

# 2. SUCCESS_GREEN 收口: components/ 下 '#22C55E' 字面量只允许出现在
#    cardshell/CardShellTypes.ets(常量定义) 与 HandwritingCard.ets(spec 红线: 不迁不动)
grep -rn "'#22C55E'" entry/src/main/ets/components/

# 3. '放弃本局' 只允许出现在 cardshell/(GIVE_UP 常量) → 0 命中于三卡
grep -n "放弃本局" \
  entry/src/main/ets/components/NumberPuzzleCard.ets \
  entry/src/main/ets/components/SudokuCard.ets \
  entry/src/main/ets/components/MazeCard.ets

# 4. 红线核查: 三卡 payload 接口与恢复路径仍在(每卡至少 1 命中)
grep -n "reconstructBoardFromPayload" entry/src/main/ets/components/SudokuCard.ets
grep -n "revealHint" entry/src/main/ets/components/MazeCard.ets
grep -n "solvedBoard" entry/src/main/ets/components/NumberPuzzleCard.ets

# 5. 竞态守卫仍在(每卡 1 命中)
grep -n "bestScoresLoaded" \
  entry/src/main/ets/components/NumberPuzzleCard.ets \
  entry/src/main/ets/components/SudokuCard.ets \
  entry/src/main/ets/components/MazeCard.ets

# 6. 已迁 7 卡零改动 → 只列出 cardshell 三文件 + 三卡
git diff --stat e2e6e62..HEAD
```

- [ ] **Step 2: 终验构建**

Run: assembleHap 命令。Expected: BUILD SUCCESSFUL。

- [ ] **Step 3: 汇总人工回归清单（spec §6，交给用户在 DevEco/真机执行）**

向用户输出（不阻塞）：
1. 正常游玩 → 通关 → 庆祝横幅（棋盘**上方**）+ 新纪录徽章 + 药丸「已完成」
2. 放弃 → 无横幅 + 药丸「已放弃」+ 放弃链消失（迷宫：绿色路线揭示 + 提示行）
3. 历史会话已答恢复（含数独中途棋盘、迷宫放弃局路线重放）
4. 深色模式 + 主题切换（含迷宫新 themePrimary 徽章、数独标准药丸）
5. 最佳成绩显示与新纪录判定（含竞态守卫路径）

若 Step 1/2 发现漂移：修复后单独 commit `fix(cardshell): 收尾漂移修复` 并重跑本步。

---

## Self-Review 记录（计划完成后已核对）

- **Spec 覆盖**：§3 契约扩展 → Task 1（含状态表语义逐行落法）；§4 迁移映射三卡 → Task 2/3/4（顺序 华容道→数独→迷宫 与 spec 一致）；§4 红线 → Global Constraints + Task 5 grep 4/5；§5 四处视觉统一 → Task 2 Step 5(12/12)、Task 4 Step 6(徽章 themePrimary)、Task 3 Step 6(标准药丸)、Task 1 Step 1 + 各卡收口(SUCCESS_GREEN)；§6 验证 → 各任务 assembleHap + Task 5 清单。
- **额外有意统一（spec §5 之外的必然结果，已在任务内标注）**：数独横幅正文 13/11vp→15/12vp、数独新纪录药丸 radius 10→6（Task 1 单一 CelebrationRegion 实现）；largeSize 外层 padding 20→24 与卡内 space 14/10→10（Task 2/3/4 Step 5 换 Shell 容器）；数独横幅 emoji margin-right 8→Row space 10。
- **类型一致性**：`feedbackAboveSlot?/usesGiveUp?/giveUpLabel?`（Types）↔ `=== true` / `?? CardShellCopy.GIVE_UP`（CardShell）↔ 三卡 config 字面量（Task 2/3/4）；`feedbackBadge/isFinished`（State）↔ CelebrationRegion/ActionsRegion 门控 ↔ syncShellState 写入；`onGiveUp` @Event ↔ 三卡 `onGiveUp: () => { this.handleGiveUp() }`。
- **门控等价性**（迁移前 → 后）：`if (hasWon) WinBanner` → `submitted = hasWon` ✓；`!hasWon && !isAnswered && !isCompleted` 放弃链 → `!isFinished && !isAnswered`（isFinished = isCompleted）✓；三卡药丸门控逐一保留（华容道/迷宫 `isAnswered || isCompleted`，数独 `isCompleted`）✓。
