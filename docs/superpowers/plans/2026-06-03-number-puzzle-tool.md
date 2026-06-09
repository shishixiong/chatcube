# 数字华容道工具 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为小星老师新增数字华容道交互工具 (number_puzzle)，支持 4 级难度 (2×2/3×3/4×4/5×5)，聊天内操作，完成后 AI 给予评价并记录到学习画像和游戏记录表。

**Architecture:** 遵循现有 math_quiz 交互工具模式：ToolRegistry 注册 → ToolExecutionService handleNumberPuzzle 挂起 → NumberPuzzleCard UI 交互 → onAnswer 回调恢复 → AI 处理结果 → child_profile 更新。

**Tech Stack:** ArkTS, HarmonyOS 6 (API 23), @ObservedV2/@Trace 状态管理, relationalStore (SQLite), PreferencesService (KV)

**Files Changed:** 7 modified, 1 created

---

### Task 1: 添加工具 ID 常量和判断函数

**Files:**
- Modify: `entry/src/main/ets/utils/SearchToolIdentityUtils.ets`

- [ ] **Step 1: 在工具 ID 常量区域添加 `NUMBER_PUZZLE_TOOL_ID`**

在 `ENGLISH_QUIZ_TOOL_ID` 下方添加：

```typescript
export const NUMBER_PUZZLE_TOOL_ID: string = 'number_puzzle'
```

- [ ] **Step 2: 添加 `isNumberPuzzleFunctionName` 判断函数**

在 `isEnglishQuizFunctionName` 下方添加：

```typescript
export function isNumberPuzzleFunctionName(functionName: string): boolean {
  return normalizeToolFunctionName(functionName) === NUMBER_PUZZLE_TOOL_ID
}
```

- [ ] **Step 3: 提交**

```bash
git add entry/src/main/ets/utils/SearchToolIdentityUtils.ets
git commit -m "feat: add NUMBER_PUZZLE_TOOL_ID and identity check function"
```

---

### Task 2: 扩展 DatabaseService（puzzle_records 表）

**Files:**
- Modify: `entry/src/main/ets/services/DatabaseService.ets`

- [ ] **Step 1: 在 TableNames 类中新增表名常量**

在 `GENERATED_MEDIA` 行下方添加：

```typescript
static readonly PUZZLE_RECORDS: string = 'puzzle_records'
```

- [ ] **Step 2: 添加 PuzzleRecord 接口**

在 DatabaseService.ets 文件顶部附近的接口定义区域（class TableNames 下方）添加：

```typescript
export interface PuzzleRecord {
  id: number
  sessionId: string
  difficulty: number
  timeSeconds: number
  moveCount: number
  completed: number
  createdAt: number
}
```

- [ ] **Step 3: 在 createTables() 中添加建表语句**

在 `createGeneratedMediaTable` 的 SQL 定义之后，`try {` 块之前添加：

```typescript
const createPuzzleRecordsTable = `
  CREATE TABLE IF NOT EXISTS ${TableNames.PUZZLE_RECORDS} (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    difficulty INTEGER NOT NULL,
    time_seconds REAL NOT NULL,
    move_count INTEGER NOT NULL,
    completed INTEGER NOT NULL DEFAULT 1,
    created_at INTEGER NOT NULL
  )
`
```

然后在 `try` 块中，在 `await this.rdbStore.executeSql(createGeneratedMediaTable)` 之后添加：

```typescript
await this.rdbStore.executeSql(createPuzzleRecordsTable)
```

- [ ] **Step 4: 在 DatabaseService 类中添加 `insertPuzzleRecord` 方法**

在类中找到合适的位置（与其他 insert 方法相邻），添加：

```typescript
async insertPuzzleRecord(
  sessionId: string,
  difficulty: number,
  timeSeconds: number,
  moveCount: number,
  completed: boolean
): Promise<number> {
  await this.waitForInitialization()
  if (this.rdbStore === null) {
    return -1
  }
  const now = Date.now()
  const valueBucket: relationalStore.ValuesBucket = {
    session_id: sessionId,
    difficulty: difficulty,
    time_seconds: timeSeconds,
    move_count: moveCount,
    completed: completed ? 1 : 0,
    created_at: now
  }
  try {
    const rowId = await this.rdbStore.insert(TableNames.PUZZLE_RECORDS, valueBucket)
    console.info('DatabaseService', `Puzzle record saved: rowId=${rowId}`)
    return rowId
  } catch (error) {
    console.error('DatabaseService', `Failed to insert puzzle record: ${JSON.stringify(error)}`)
    return -1
  }
}
```

- [ ] **Step 5: 添加 `getPuzzleRecordsBySession` 查询方法**

```typescript
async getPuzzleRecordsBySession(sessionId: string): Promise<PuzzleRecord[]> {
  await this.waitForInitialization()
  if (this.rdbStore === null) {
    return []
  }
  const records: PuzzleRecord[] = []
  const predicates = new relationalStore.RdbPredicates(TableNames.PUZZLE_RECORDS)
  predicates.equalTo('session_id', sessionId)
  predicates.orderByDesc('created_at')
  try {
    const resultSet = await this.rdbStore.query(predicates)
    while (resultSet.goToNextRow()) {
      records.push({
        id: resultSet.getLong(resultSet.getColumnIndex('id')),
        sessionId: resultSet.getString(resultSet.getColumnIndex('session_id')),
        difficulty: resultSet.getLong(resultSet.getColumnIndex('difficulty')),
        timeSeconds: resultSet.getDouble(resultSet.getColumnIndex('time_seconds')),
        moveCount: resultSet.getLong(resultSet.getColumnIndex('move_count')),
        completed: resultSet.getLong(resultSet.getColumnIndex('completed')),
        createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at'))
      })
    }
    resultSet.close()
  } catch (error) {
    console.error('DatabaseService', `Failed to query puzzle records: ${JSON.stringify(error)}`)
  }
  return records
}
```

- [ ] **Step 6: 添加 `getAllPuzzleRecords` 查询方法**

```typescript
async getAllPuzzleRecords(): Promise<PuzzleRecord[]> {
  await this.waitForInitialization()
  if (this.rdbStore === null) {
    return []
  }
  const records: PuzzleRecord[] = []
  const predicates = new relationalStore.RdbPredicates(TableNames.PUZZLE_RECORDS)
  predicates.orderByDesc('created_at')
  try {
    const resultSet = await this.rdbStore.query(predicates)
    while (resultSet.goToNextRow()) {
      records.push({
        id: resultSet.getLong(resultSet.getColumnIndex('id')),
        sessionId: resultSet.getString(resultSet.getColumnIndex('session_id')),
        difficulty: resultSet.getLong(resultSet.getColumnIndex('difficulty')),
        timeSeconds: resultSet.getDouble(resultSet.getColumnIndex('time_seconds')),
        moveCount: resultSet.getLong(resultSet.getColumnIndex('move_count')),
        completed: resultSet.getLong(resultSet.getColumnIndex('completed')),
        createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at'))
      })
    }
    resultSet.close()
  } catch (error) {
    console.error('DatabaseService', `Failed to query all puzzle records: ${JSON.stringify(error)}`)
  }
  return records
}
```

- [ ] **Step 7: 提交**

```bash
git add entry/src/main/ets/services/DatabaseService.ets
git commit -m "feat: add puzzle_records table with CRUD methods"
```

---

### Task 3: 扩展 ChildProfileService（新增技能维度）

**Files:**
- Modify: `entry/src/main/ets/services/ChildProfileService.ets`

- [ ] **Step 1: 在 SKILL_DEFINITIONS 数组中添加 2 个新维度**

在第 51 行 `['general_life', '生活常识']` 之后添加：

```typescript
['logic_puzzle', '逻辑思维'],
['observation', '观察力']
```

- [ ] **Step 2: 提交**

```bash
git add entry/src/main/ets/services/ChildProfileService.ets
git commit -m "feat: add logic_puzzle and observation skill dimensions"
```

---

### Task 4: 创建 NumberPuzzleCard 组件

**Files:**
- Create: `entry/src/main/ets/components/NumberPuzzleCard.ets`

- [ ] **Step 1: 创建组件文件骨架**

```typescript
/**
 * NumberPuzzleCard - 数字华容道互动卡片
 *
 * 解析 toolCall.arguments 中的 difficulty 参数, 在聊天气泡内渲染可交互的数字华容道棋盘。
 * 支持点击和滑动两种操作方式, 孩子还原拼图后自动提交结果给 AI。
 *
 * 参考 MathQuizCard 模式: @ComponentV2 + @Event onAnswer 回调
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'

interface NumberPuzzleResult {
  difficulty: number
  grid_size: string
  time_seconds: number
  move_count: number
  completed: boolean
}

@ComponentV2
export struct NumberPuzzleCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local gameBoard: number[] = []
  @Local gridSize: number = 3
  @Local moveCount: number = 0
  @Local startTime: number = 0
  @Local elapsedSeconds: number = 0
  @Local isCompleted: boolean = false
  @Local shouldAnimate: boolean = true
  @Local screenStartX: number = 0
  @Local screenStartY: number = 0
  @Local lastScreenX: number = 0
  @Local lastScreenY: number = 0
  private timerId: number = -1

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get solvedBoard(): number[] {
    const result: number[] = []
    const total = this.gridSize * this.gridSize
    for (let i = 0; i < total - 1; i++) {
      result.push(i + 1)
    }
    result.push(0) // 0 表示空格
    return result
  }

  private get cellSize(): number {
    switch (this.gridSize) {
      case 2:
        return 72
      case 3:
        return 64
      case 4:
        return 52
      case 5:
        return 44
      default:
        return 64
    }
  }

  private get cellMargin(): number {
    return this.gridSize <= 3 ? 4 : 3
  }

  private get totalWidth(): number {
    return (this.cellSize + this.cellMargin * 2) * this.gridSize
  }

  private get maxFontSize(): number {
    return Math.floor(this.cellSize * 0.45)
  }

  private get difficultyLabel(): string {
    switch (this.gridSize) {
      case 2:
        return '幼儿 (2×2)'
      case 3:
        return '简单 (3×3)'
      case 4:
        return '进阶 (4×4)'
      case 5:
        return '挑战 (5×5)'
      default:
        return `${this.gridSize}×${this.gridSize}`
    }
  }

  aboutToAppear(): void {
    this.parseDifficulty()
    if (this.isAnswered) {
      this.parsePreviousResult()
    } else {
      this.shuffleGameBoard()
    }
  }

  aboutToDisappear(): void {
    this.stopTimer()
  }

  private parseDifficulty(): void {
    try {
      const parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      const difficulty = (parsed['difficulty'] as number) ?? 3
      if (difficulty >= 2 && difficulty <= 5) {
        this.gridSize = Math.floor(difficulty)
      } else {
        this.gridSize = 3
      }
    } catch (_e) {
      this.gridSize = 3
    }
  }

  private parsePreviousResult(): void {
    if (this.answeredPayload === '') {
      return
    }
    try {
      const result = JSON.parse(this.answeredPayload) as NumberPuzzleResult
      this.gridSize = result.difficulty
      this.isCompleted = true
      this.gameBoard = this.solvedBoard
    } catch (_e) {
      // 解析失败, 保持默认
    }
  }

  private startTimer(): void {
    this.stopTimer()
    this.timerId = setInterval(() => {
      if (!this.isCompleted && this.startTime > 0) {
        this.elapsedSeconds = Math.floor((Date.now() - this.startTime) / 1000)
      }
    }, 500)
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }
}
```

- [ ] **Step 2: 实现打乱算法**

在类中添加：

```typescript
  private shuffleGameBoard(): void {
    this.isCompleted = false
    this.moveCount = 0
    this.shouldAnimate = false

    // 从目标状态开始
    let board = [...this.solvedBoard]

    // 最小移动次数按难度递增
    const minMoves: Record<number, number> = { 2: 10, 3: 30, 4: 60, 5: 100 }
    const min = minMoves[this.gridSize] ?? 30
    const extra = Math.floor(Math.random() * min)
    const totalMoves = min + extra

    // 找出空格索引
    const findBlank = () => board.indexOf(0)

    // 获取合法方向列表
    const validDirections = (index: number): string[] => {
      const valid: string[] = []
      const row = Math.floor(index / this.gridSize)
      const col = index % this.gridSize
      if (row > 0) {
        valid.push('up')
      }
      if (row < this.gridSize - 1) {
        valid.push('down')
      }
      if (col > 0) {
        valid.push('left')
      }
      if (col < this.gridSize - 1) {
        valid.push('right')
      }
      return valid
    }

    // 执行随机移动
    let prevDirection = '' // 避免来回移动
    for (let i = 0; i < totalMoves; i++) {
      const blankIdx = findBlank()
      const directions = validDirections(blankIdx)

      // 过滤掉与上一步相反的方向, 增加随机性
      const opposite: Record<string, string> = { 'up': 'down', 'down': 'up', 'left': 'right', 'right': 'left' }
      const filtered = directions.filter(d => d !== opposite[prevDirection])
      const pool = filtered.length > 0 ? filtered : directions

      const direction = pool[Math.floor(Math.random() * pool.length)]
      prevDirection = direction

      const newIdx = this.getMoveTargetIndex(blankIdx, direction)
      const temp = board[newIdx]
      board[newIdx] = board[blankIdx]
      board[blankIdx] = temp
    }

    this.gameBoard = board
    this.shouldAnimate = true
    this.startTime = Date.now()
    this.elapsedSeconds = 0
    this.startTimer()
  }
```

- [ ] **Step 3: 实现核心游戏逻辑方法**

```typescript
  private getMoveTargetIndex(blankIndex: number, direction: string): number {
    switch (direction) {
      case 'up':
        return blankIndex - this.gridSize
      case 'down':
        return blankIndex + this.gridSize
      case 'left':
        return blankIndex - 1
      case 'right':
        return blankIndex + 1
      default:
        return blankIndex
    }
  }

  private canMove(tileIndex: number): boolean {
    const blankIndex = this.gameBoard.indexOf(0)
    const blankRow = Math.floor(blankIndex / this.gridSize)
    const blankCol = blankIndex % this.gridSize
    const tileRow = Math.floor(tileIndex / this.gridSize)
    const tileCol = tileIndex % this.gridSize
    return (
      (tileRow === blankRow && Math.abs(tileCol - blankCol) === 1) ||
      (tileCol === blankCol && Math.abs(tileRow - blankRow) === 1)
    )
  }

  private moveTile(tileIndex: number): void {
    if (this.isCompleted || !this.canMove(tileIndex)) {
      return
    }
    const blankIndex = this.gameBoard.indexOf(0)
    const temp = this.gameBoard[tileIndex]
    this.gameBoard[tileIndex] = this.gameBoard[blankIndex]
    this.gameBoard[blankIndex] = temp
    this.moveCount++
    this.checkForWin()
  }

  private checkForWin(): void {
    const winState = this.solvedBoard
    const isWin = this.gameBoard.join(',') === winState.join(',')
    if (isWin) {
      this.isCompleted = true
      this.stopTimer()
      const timeMs = Date.now() - this.startTime
      const timeSeconds = Number((timeMs / 1000).toFixed(1))
      this.elapsedSeconds = Math.floor(timeSeconds)

      const result: NumberPuzzleResult = {
        difficulty: this.gridSize,
        grid_size: `${this.gridSize}×${this.gridSize}`,
        time_seconds: timeSeconds,
        move_count: this.moveCount,
        completed: true
      }
      this.onAnswer(this.toolCall.id, JSON.stringify(result))
    }
  }
```

- [ ] **Step 4: 实现动画方法**

```typescript
  private updateAnim(index: number): TransitionEffect | undefined {
    if (!this.shouldAnimate) {
      return undefined
    }
    if (this.canMove(index) && !this.isCompleted) {
      const blankIndex = this.gameBoard.indexOf(0)
      const diff = Math.abs(index - blankIndex)
      const step = this.cellSize + this.cellMargin * 2
      if (diff === 1) {
        // 左右移动
        const dir = index > blankIndex ? -1 : 1
        return TransitionEffect.translate({
          x: `${dir * step}lpx`
        }).animation({ duration: 100, curve: Curve.EaseOut })
      } else if (diff === this.gridSize) {
        // 上下移动
        const dir = index > blankIndex ? -1 : 1
        return TransitionEffect.translate({
          y: `${dir * step}lpx`
        }).animation({ duration: 100, curve: Curve.EaseOut })
      }
    }
    return undefined
  }
```

- [ ] **Step 5: 实现滑动处理**

```typescript
  private moveOnSwipe(direction: string): void {
    if (this.isCompleted) {
      return
    }
    const blankIndex = this.gameBoard.indexOf(0)
    const newIndex = this.getMoveTargetIndex(blankIndex, direction)
    if (this.isValidIndex(newIndex)) {
      this.moveTile(newIndex)
    }
  }

  private isValidIndex(index: number): boolean {
    return index >= 0 && index < this.gameBoard.length
  }

  private getSwipeDirection(): string {
    const swipeX = this.lastScreenX - this.screenStartX
    const swipeY = this.lastScreenY - this.screenStartY
    if (Math.abs(swipeX) > Math.abs(swipeY)) {
      return swipeX > 0 ? 'right' : 'left'
    } else {
      return swipeY > 0 ? 'down' : 'up'
    }
  }
```

- [ ] **Step 6: 实现 build() 和布局**

```typescript
  private getTileBackgroundColor(value: number): ResourceColor {
    if (value === 0) {
      return Color.Transparent
    }
    if (this.isDarkMode) {
      return this.themePrimary
    }
    return Color.Orange
  }

  private getTileFontColor(_value: number): ResourceColor {
    return Color.White
  }

  private formatTime(seconds: number): string {
    const m = Math.floor(seconds / 60)
    const s = seconds % 60
    const sStr = s < 10 ? `0${s}` : `${s}`
    return `${m}:${sStr}`
  }

  private getCardBackgroundColor(): string {
    return this.isDarkMode
      ? withColorAlpha(this.themePrimary, '18')
      : withColorAlpha(this.themePrimary, '12')
  }

  build() {
    Column({ space: 8 }) {
      // 标题行
      Row() {
        SymbolGlyph($r('sys.symbol.puzzlepiece'))
          .fontSize(14)
          .fontColor([this.themePrimary])
        Text(`数字华容道 · ${this.difficultyLabel}`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 6 })
        Blank()
        if (this.isAnswered || this.isCompleted) {
          Text('已完成')
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.status_success'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
        }
      }
      .width('100%')

      // 棋盘区域
      Column() {
        Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
          ForEach(this.gameBoard, (item: number, index: number) => {
            Text(item === 0 ? '' : `${item}`)
              .width(`${this.cellSize}lpx`)
              .height(`${this.cellSize}lpx`)
              .margin(`${this.cellMargin}lpx`)
              .fontSize(`${this.maxFontSize}lpx`)
              .textAlign(TextAlign.Center)
              .fontColor(this.getTileFontColor(item))
              .backgroundColor(this.getTileBackgroundColor(item))
              .borderRadius(6)
              .visibility(item === 0 ? Visibility.Hidden : Visibility.Visible)
              .transition(this.updateAnim(index))
              .onClick(() => {
                if (this.canMove(index) && !this.isCompleted) {
                  this.moveTile(index)
                }
              })
          }, (item: number, index: number) => `tile_${index}_${item}`)
        }
        .width(`${this.totalWidth}lpx`)
      }
      .width('100%')
      .padding(this.gridSize <= 3 ? 8 : 6)
      .backgroundColor(this.getCardBackgroundColor())
      .borderRadius(10)
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down && e.touches.length > 0) {
          this.screenStartX = e.touches[0].x
          this.screenStartY = e.touches[0].y
        } else if (e.type === TouchType.Up && e.changedTouches.length > 0) {
          this.lastScreenX = e.changedTouches[0].x
          this.lastScreenY = e.changedTouches[0].y
        }
      })
      .gesture(
        SwipeGesture({ direction: SwipeDirection.All })
          .onAction((_event: GestureEvent) => {
            const direction = this.getSwipeDirection()
            const blankIndex = this.gameBoard.indexOf(0)
            let targetIdx = blankIndex
            // 滑动方向与方块移动方向相反:
            // 向右滑动 → 空格左边的方块向右移 → 移动 blankIndex - 1
            // 向左滑动 → 空格右边的方块向左移 → 移动 blankIndex + 1
            // 向上滑动 → 空格下边的方块向上移 → 移动 blankIndex + gridSize
            // 向下滑动 → 空格上边的方块向下移 → 移动 blankIndex - gridSize
            switch (direction) {
              case 'up':
                targetIdx = blankIndex + this.gridSize
                break
              case 'down':
                targetIdx = blankIndex - this.gridSize
                break
              case 'left':
                targetIdx = blankIndex + 1
                break
              case 'right':
                targetIdx = blankIndex - 1
                break
            }
            this.screenStartX = 0
            this.screenStartY = 0
            if (this.isValidIndex(targetIdx)) {
              this.moveTile(targetIdx)
            }
          })
      )

      // 状态栏
      Row() {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(12)
          .fontColor([$r('app.color.text_tertiary')])
        Text(this.formatTime(this.elapsedSeconds))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 4 })
        Blank()
        SymbolGlyph($r('sys.symbol.hand_point_up'))
          .fontSize(12)
          .fontColor([$r('app.color.text_tertiary')])
        Text(`步数: ${this.moveCount}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 4 })
      }
      .width('100%')

      // 重新开始按钮（只在未完成时显示）
      if (!this.isCompleted && !this.isAnswered) {
        Button('重新开始')
          .width('50%')
          .height(32)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface'))
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.divider') })
          .onClick(() => {
            this.shuffleGameBoard()
          })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.themeAiBubble)
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.divider') })
  }
```

- [ ] **Step 7: 提交**

```bash
git add entry/src/main/ets/components/NumberPuzzleCard.ets
git commit -m "feat: add NumberPuzzleCard interactive component"
```

---

### Task 5: 在 BuiltinTools 中注册 number_puzzle 工具

**Files:**
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`

- [ ] **Step 1: 在文件顶部 import 中添加 NUMBER_PUZZLE_TOOL_ID**

找到 `ENGLISH_QUIZ_TOOL_ID` 的 import 行，在其后添加：

```typescript
import { ..., ENGLISH_QUIZ_TOOL_ID, NUMBER_PUZZLE_TOOL_ID } from '../utils/SearchToolIdentityUtils'
```

- [ ] **Step 2: 在 english_quiz 执行器定义之后（第 1262 行附近），注册函数之前，添加 number_puzzle 的定义**

```typescript
// ===== number_puzzle 工具 =====
// 数字华容道游戏：让小星老师发起数字华容道挑战，孩子在屏幕上滑动或点击完成拼图。

interface NumberPuzzleArgs {
  difficulty: number
}

class NumberPuzzleExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    try {
      const params = JSON.parse(_args) as NumberPuzzleArgs
      return JSON.stringify({
        difficulty: params.difficulty ?? 3,
        grid_size: `${params.difficulty ?? 3}×${params.difficulty ?? 3}`,
        time_seconds: 0,
        move_count: 0,
        completed: false
      })
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`number_puzzle error: ${JSON.stringify(error)}`))
    }
  }
}

function createNumberPuzzleToolDefinition(): ToolDefinition {
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "difficulty": {
        "type": "integer",
        "description": "Difficulty level: 2=2×2 toddler (3 tiles + blank), 3=3×3 easy (8 tiles + blank), 4=4×4 medium (15 tiles + blank), 5=5×5 hard (24 tiles + blank). Choose based on the child's age and puzzle experience. Start with 3 for first-timers.",
        "enum": [2, 3, 4, 5]
      }
    },
    "required": ["difficulty"]
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    NUMBER_PUZZLE_TOOL_ID,
    'Launch a number sliding puzzle game for the child. The child rearranges scrambled numbers back to order by sliding tiles into the empty space. This trains logical thinking and observation skills. Choose difficulty based on child profile: 2 for very young (2×2), 3 for beginners (3×3), 4 for intermediate (4×4), 5 for advanced (5×5).',
    parameters
  )

  return new ToolDefinition(func)
}

function createNumberPuzzleToolConfig(): ToolConfig {
  return new ToolConfig(
    NUMBER_PUZZLE_TOOL_ID,
    '数字华容道',
    '数字华容道益智游戏, 通过滑动或点击将打乱的数字按顺序还原, 锻炼逻辑思维和观察力。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    NUMBER_PUZZLE_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}
```

- [ ] **Step 3: 在 registerBuiltinTools() 中注册工具**

在 english_quiz 的注册块之后（第 1377 行 `registeredNow += 1` 之后，`console.info` 之前），添加：

```typescript
if (!registry.isToolRegistered(NUMBER_PUZZLE_TOOL_ID)) {
  const numberPuzzleTool = new RegisteredTool(
    NUMBER_PUZZLE_TOOL_ID,
    createNumberPuzzleToolConfig(),
    createNumberPuzzleToolDefinition(),
    new NumberPuzzleExecutor()
  )
  registry.registerTool(numberPuzzleTool)
  registeredNow += 1
}
```

- [ ] **Step 4: 在 getBuiltinToolIds() 中添加**

在返回数组中，`ENGLISH_QUIZ_TOOL_ID` 之后添加 `NUMBER_PUZZLE_TOOL_ID`：

```typescript
export function getBuiltinToolIds(): string[] {
  return [LEGACY_WEB_SEARCH_TOOL_ID, SEARCH_WEB_TOOL_ID, SCRAPE_WEB_TOOL_ID, ASK_USER_TOOL_ID, GET_TIME_INFO_TOOL_ID, IMAGE_GENERATION_TOOL_ID, CHILD_PROFILE_TOOL_ID, MATH_VERIFY_TOOL_ID, MATH_QUIZ_TOOL_ID, ENGLISH_QUIZ_TOOL_ID, NUMBER_PUZZLE_TOOL_ID]
}
```

- [ ] **Step 5: 提交**

```bash
git add entry/src/main/ets/config/BuiltinTools.ets
git commit -m "feat: register number_puzzle tool in builtin tools"
```

---

### Task 6: 在 ToolExecutionService 中添加 handleNumberPuzzle 处理路径

**Files:**
- Modify: `entry/src/main/ets/services/ToolExecutionService.ets`

- [ ] **Step 1: 在 import 中添加新的依赖**

在 `ENGLISH_QUIZ_TOOL_ID` 和 `isEnglishQuizFunctionName` 后面添加：

```typescript
import {
  ...,
  ENGLISH_QUIZ_TOOL_ID,
  NUMBER_PUZZLE_TOOL_ID,
  isAskUserFunctionName,
  isMathQuizFunctionName,
  isEnglishQuizFunctionName,
  isNumberPuzzleFunctionName,
  ...
} from '../utils/SearchToolIdentityUtils'
```

同时添加 DatabaseService 的 import（如果还没引入）：

```typescript
import { getDatabaseService } from './DatabaseService'
```

- [ ] **Step 2: 在 executeToolCall 方法中添加 number_puzzle 分发**

在 `isEnglishQuizFunctionName` 判断块之后（第 734 行之后），通用工具查找之前添加：

```typescript
// === number_puzzle 特殊路径 ===
// 数字华容道互动工具, 由 NumberPuzzleCard 收集小朋友的游戏结果。
if (isNumberPuzzleFunctionName(normalizedFunctionName)) {
  return await this.handleNumberPuzzle(toolCall, context)
}
```

- [ ] **Step 3: 在 handleEnglishQuiz 方法之后添加 handleNumberPuzzle 方法**

在类中 `handleEnglishQuiz` 方法结束后（约第 700 行），添加：

```typescript
// number_puzzle 特殊路径: 与 math_quiz 类似, 挂起等待 NumberPuzzleCard 回答。
// 孩子完成拼图后结果写入 puzzle_records 表, 再返回给 AI 用于学习画像更新。
private async handleNumberPuzzle(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult> {
  toolCall.toolId = NUMBER_PUZZLE_TOOL_ID
  if (toolCall.displayName.trim() === '') {
    toolCall.displayName = '数字华容道'
  }
  toolCall.sourceType = ToolSourceType.BUILTIN
  if (toolCall.sourceLabel.trim() === '') {
    toolCall.sourceLabel = '内置工具'
  }
  toolCall.permissionLevel = ToolPermissionLevel.READ

  toolCall.approvalState = 'pending'

  let answerJson: string | null = null
  try {
    answerJson = await new Promise<string | null>((resolve) => {
      const existing = this.pendingAnswers.get(toolCall.id)
      if (existing !== undefined) {
        existing.resolve(null)
        this.pendingAnswers.delete(toolCall.id)
      }
      const snapshot = this.buildAskUserSnapshot(toolCall, context)
      snapshot.kind = PendingToolInteractionKind.ASK_USER
      snapshot.toolId = NUMBER_PUZZLE_TOOL_ID
      this.pendingAnswers.set(toolCall.id, new PendingToolAnswerRuntime(snapshot, resolve))
      this.publishPendingInteractionChanged()
    })
  } catch (error) {
    console.error('ToolExecutionService', `number_puzzle answer callback failed: ${JSON.stringify(error)}`)
    toolCall.approvalState = 'denied'
    return new ToolResult(
      toolCall.id,
      JSON.stringify({ error: `number_puzzle 失败: ${JSON.stringify(error)}`, cancelled: true }),
      true,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  if (this.isCancelled()) {
    console.info('ToolExecutionService', 'number_puzzle cancelled by external stop')
    toolCall.approvalState = 'denied'
    return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
  }

  if (answerJson === null) {
    toolCall.approvalState = 'denied'
    return new ToolResult(
      toolCall.id,
      JSON.stringify({ cancelled: true, error: '小朋友未完成该华容道游戏' }),
      true,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  // 将游戏记录持久化到 puzzle_records 表
  try {
    const result = JSON.parse(answerJson) as Record<string, Object>
    const difficulty = (result['difficulty'] as number) ?? 3
    const timeSeconds = (result['time_seconds'] as number) ?? 0
    const moveCount = (result['move_count'] as number) ?? 0
    const completed = (result['completed'] as boolean) ?? true
    await getDatabaseService().insertPuzzleRecord(
      context.sessionId,
      difficulty,
      timeSeconds,
      moveCount,
      completed
    )
  } catch (error) {
    console.error('ToolExecutionService', `Failed to persist puzzle record: ${JSON.stringify(error)}`)
  }

  toolCall.approvalState = 'answered'
  toolCall.approvalReason = answerJson
  console.info('ToolExecutionService', `number_puzzle answered: ${toolCall.id}`)
  return new ToolResult(
    toolCall.id,
    answerJson,
    false,
    toolCall.displayName,
    toolCall.sourceLabel
  )
}
```

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/services/ToolExecutionService.ets
git commit -m "feat: add handleNumberPuzzle execution path with puzzle_records persistence"
```

---

### Task 7: 在 MessageBubble 中添加 NumberPuzzleCard 渲染

**Files:**
- Modify: `entry/src/main/ets/components/MessageBubble.ets`

- [ ] **Step 1: 在 import 中添加新依赖**

在 `isMathQuizFunctionName, isEnglishQuizFunctionName` 之后添加 `isNumberPuzzleFunctionName`：

```typescript
import { ..., isMathQuizFunctionName, isEnglishQuizFunctionName, isNumberPuzzleFunctionName } from '../utils/SearchToolIdentityUtils'
```

添加组件 import：

```typescript
import { NumberPuzzleCard } from './NumberPuzzleCard'
```

- [ ] **Step 2: 添加 shouldRenderNumberPuzzleInteractionCard 方法**

在 `shouldRenderEnglishQuizInteractionCard` 方法之后（约第 2599 行）添加：

```typescript
private shouldRenderNumberPuzzleInteractionCard(toolCall: ToolCall, index: number): boolean {
  if (!isNumberPuzzleFunctionName(toolCall.functionName) || this.shouldHideToolCallCard(toolCall)) {
    return false
  }
  return !this.isAskUserToolCallAnswered(toolCall, index)
}
```

- [ ] **Step 3: 在 build() 方法中添加待处理状态下的独立交互卡片渲染**

在 english_quiz 的独立卡片 ForEach 块之后（第 2049 行之后），添加：

```typescript
// number_puzzle 待答时保留独立互动卡片; 提交后收缩到 timeline step 内。
if (this.message.hasToolCalls()) {
  ForEach(this.message.toolCalls, (toolCall: ToolCall, index: number) => {
    if (this.shouldRenderNumberPuzzleInteractionCard(toolCall, index)) {
      NumberPuzzleCard({
        toolCall: toolCall,
        isAnswered: false,
        answeredPayload: toolCall.approvalReason,
        onAnswer: (toolCallId: string, answerJson: string): void => {
          this.onAskUserAnswer(toolCallId, answerJson)
        }
      })
        .margin({ bottom: 6 })
    }
  }, (toolCall: ToolCall, index: number) => 'number_puzzle_' + toolCall.id + '_' + index.toString())
}
```

- [ ] **Step 4: 在 ToolStepContent @Builder 中添加 number_puzzle 分支**

在 `else if (isEnglishQuizFunctionName(step.toolName))` 之后添加：

```typescript
} else if (isNumberPuzzleFunctionName(step.toolName)) {
  this.NumberPuzzleStepContent(step)
```

- [ ] **Step 5: 添加 NumberPuzzleStepContent @Builder 方法**

在 `EnglishQuizStepContent` 之后添加：

```typescript
// number_puzzle 工具步骤: 已完成的华容道游戏, 在 timeline 中显示简化结果, 可展开查看详情
@Builder
NumberPuzzleStepContent(step: MessagePart) {
  Column() {
    Row({ space: 6 }) {
      if (step.toolStatus === 'succeeded') {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(13)
          .fontColor([$r('app.color.status_success')])
      } else if (step.toolStatus === 'failed' || step.toolStatus === 'denied') {
        SymbolGlyph($r('sys.symbol.xmark_circle'))
          .fontSize(13)
          .fontColor([$r('app.color.status_error')])
      } else {
        Column()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.themePrimary)
      }

      Text(this.buildToolStepTitle(step))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)

      if (this.isToolStepClickable(step)) {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([$r('app.color.text_tertiary')])
          .rotate({ angle: this.isToolStepExpanded(step) ? 0 : -90 })
          .animation({ duration: 200, curve: Curve.EaseOut })
      }
    }
    .width('100%')
    .onClick(() => {
      if (this.isToolStepClickable(step)) {
        this.handleToolStepClick(step)
      }
    })

    // 展开时显示游戏结果摘要
    if (this.isToolStepExpanded(step) && step.toolResult !== '') {
      NumberPuzzleCard({
        toolCall: this.buildToolCallFromStep(step),
        isAnswered: true,
        answeredPayload: step.toolResult,
        onAnswer: (_toolCallId: string, _answerJson: string): void => {}
      })
      .margin({ top: 8 })
    }
  }
  .width('100%')
}
```

- [ ] **Step 6: 在 `isToolStepClickable` 方法中添加 number_puzzle 的判断**

找到 `isEnglishQuizFunctionName(part.toolName)` 的条件判断区域，确保 number_puzzle 也被加入展开判断。在 `isToolStepClickable` 返回逻辑中（约 2463 行），在 `isMathQuizFunctionName` 和 `isEnglishQuizFunctionName` 的判断之后添加 number_puzzle：

在 `isSuccessfulToolStep(part)` 条件的那些地方加入 number_puzzle。找到两处与展开相关的判断：

1. 在 `shouldAutoExpandToolStep` 中的条件（约 2516 行）：

```typescript
if (isImageGenerationFunctionName(part.toolName) || isMathQuizFunctionName(part.toolName) || isEnglishQuizFunctionName(part.toolName) || isNumberPuzzleFunctionName(part.toolName)) {
  return this.isSuccessfulToolStep(part)
}
```

2. 在 `buildInitialExpandedToolSteps` 中的条件（约 2526 行）：

```typescript
const isDefaultExpanded = this.isSuccessfulToolStep(part) &&
  (isImageGenerationFunctionName(part.toolName) || isMathQuizFunctionName(part.toolName) || isEnglishQuizFunctionName(part.toolName) || isNumberPuzzleFunctionName(part.toolName))
```

3. 在 `handleToolStepClick` 中（约 2924 行），在 `isMathQuizFunctionName` 之后添加：

```typescript
if (isNumberPuzzleFunctionName(part.toolName)) {
  this.toggleToolStep(part)
  return
}
```

- [ ] **Step 7: 提交**

```bash
git add entry/src/main/ets/components/MessageBubble.ets
git commit -m "feat: add NumberPuzzleCard rendering in MessageBubble timeline"
```

---

### Task 8: 将 number_puzzle 加入小星老师助手白名单

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets`

- [ ] **Step 1: 在 import 中添加 NUMBER_PUZZLE_TOOL_ID**

```typescript
import {
  ...,
  ENGLISH_QUIZ_TOOL_ID,
  NUMBER_PUZZLE_TOOL_ID
} from '../utils/SearchToolIdentityUtils'
```

- [ ] **Step 2: 在 DEFAULT_ASSISTANT_LOCKED_TOOL_IDS 数组中添加**

在 `ENGLISH_QUIZ_TOOL_ID` 之后添加 `NUMBER_PUZZLE_TOOL_ID`：

```typescript
export const DEFAULT_ASSISTANT_LOCKED_TOOL_IDS: string[] = [
  CHILD_PROFILE_TOOL_ID,
  GET_TIME_INFO_TOOL_ID,
  IMAGE_GENERATION_TOOL_ID,
  MATH_VERIFY_TOOL_ID,
  MATH_QUIZ_TOOL_ID,
  ENGLISH_QUIZ_TOOL_ID,
  NUMBER_PUZZLE_TOOL_ID
]
```

- [ ] **Step 3: 在小星老师系统提示词中添加数字华容道的使用指引**

在 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 的系统提示词末尾（英语教学相关区域之后，"## 常识教学"之前）添加：

```
## 数字华容道游戏

当想锻炼孩子的逻辑思维和观察力时, 使用 number_puzzle 工具发起数字华容道游戏。
根据孩子的年龄和 puzzle 经验选择合适的难度: 2=2×2 (幼儿刚刚接触), 3=3×3 (适合大多数小朋友初次体验), 4=4×4 (有一定经验后尝试), 5=5×5 (非常大的挑战)。
建议先让孩子尝试一次简单的, 完成后再根据用时和步数评价。
孩子完成游戏后, 根据用时和步数给出具体的鼓励和评价。用时短步数少说明逻辑思维和观察力很好。
游戏完成后, 根据整体表现调用 child_profile(action:"update") 更新 logic_puzzle 和 observation 技能维度。
```

- [ ] **Step 4: 提交**

```bash
git add entry/src/main/ets/models/AssistantModels.ets
git commit -m "feat: add number_puzzle to default assistant locked tools and system prompt"
```

---

### 验证检查清单

- [ ] `number_puzzle` 工具在 "小星老师" 工具列表中可见
- [ ] AI 可调用 `number_puzzle(difficulty: 3)` 发起游戏
- [ ] NumberPuzzleCard 在聊天气泡内渲染正确，各难度棋盘尺寸适配
- [ ] 点击移动和滑动操作均正常
- [ ] 计时器和步数计数器正常工作
- [ ] 拼图还原后自动提交，AI 收到结果
- [ ] 游戏记录写入 `puzzle_records` 表
- [ ] `child_profile` 包含 `logic_puzzle` 和 `observation` 维度
- [ ] 重新开始功能有效
- [ ] 打乱无闪烁，移动有动画
- [ ] 黑暗模式下棋盘颜色正常
- [ ] 已完成棋盘不可再操作
