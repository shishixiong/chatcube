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
    result.push(0)
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
      this.moveCount = result.move_count
      this.elapsedSeconds = Math.floor(result.time_seconds)
    } catch (_e) {
      // ignore parse failure
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

  private shuffleGameBoard(): void {
    this.isCompleted = false
    this.moveCount = 0
    this.shouldAnimate = false

    let board = [...this.solvedBoard]

    let minMoves = 30
    switch (this.gridSize) {
      case 2: minMoves = 10; break
      case 3: minMoves = 30; break
      case 4: minMoves = 60; break
      case 5: minMoves = 100; break
    }
    const extra = Math.floor(Math.random() * minMoves)
    const totalMoves = minMoves + extra

    const findBlank = (): number => board.indexOf(0)

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

    let prevDirection = ''
    const opposite: Record<string, string> = { 'up': 'down', 'down': 'up', 'left': 'right', 'right': 'left' }
    for (let i = 0; i < totalMoves; i++) {
      const blankIdx = findBlank()
      const directions = validDirections(blankIdx)
      const filtered = directions.filter((d: string) => d !== opposite[prevDirection])
      const pool = filtered.length > 0 ? filtered : directions
      const direction = pool[Math.floor(Math.random() * pool.length)]
      prevDirection = direction
      const newIdx = this.getMoveTargetIndex(blankIdx, direction)
      const temp = board[newIdx]
      board[newIdx] = board[blankIdx]
      board[blankIdx] = temp
    }

    // Ensure the board is not already solved after shuffle
    if (board.join(',') === this.solvedBoard.join(',')) {
      // Swap two adjacent tiles to break the solved state
      const blankIdx = board.indexOf(0)
      const swapIdx = blankIdx === 0 ? 1 : blankIdx - 1
      const temp = board[swapIdx]
      board[swapIdx] = board[blankIdx]
      board[blankIdx] = temp
    }

    this.gameBoard = board
    this.shouldAnimate = true
    this.startTime = Date.now()
    this.elapsedSeconds = 0
    this.startTimer()
  }

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

  private updateAnim(index: number): TransitionEffect | undefined {
    if (!this.shouldAnimate) {
      return undefined
    }
    if (this.canMove(index) && !this.isCompleted) {
      const blankIndex = this.gameBoard.indexOf(0)
      const diff = Math.abs(index - blankIndex)
      const step = this.cellSize + this.cellMargin * 2
      if (diff === 1) {
        const dir = index > blankIndex ? -1 : 1
        return TransitionEffect.translate({
          x: `${dir * step}lpx`
        }).animation({ duration: 100, curve: Curve.EaseOut })
      } else if (diff === this.gridSize) {
        const dir = index > blankIndex ? -1 : 1
        return TransitionEffect.translate({
          y: `${dir * step}lpx`
        }).animation({ duration: 100, curve: Curve.EaseOut })
      }
    }
    return undefined
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

  private getTileBackgroundColor(value: number): ResourceColor {
    if (value === 0) {
      return Color.Transparent
    }
    if (this.isDarkMode) {
      return this.themePrimary
    }
    return Color.Orange
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
      // Title row
      Row() {
        SymbolGlyph($r('sys.symbol.lightbulb'))
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

      // Game board
      Column() {
        Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
          ForEach(this.gameBoard, (item: number, index: number) => {
            Text(item === 0 ? '' : `${item}`)
              .width(`${this.cellSize}lpx`)
              .height(`${this.cellSize}lpx`)
              .margin(`${this.cellMargin}lpx`)
              .fontSize(`${this.maxFontSize}lpx`)
              .textAlign(TextAlign.Center)
              .fontColor(Color.White)
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
      .priorityGesture(
        SwipeGesture({ direction: SwipeDirection.All })
          .onAction((_event: GestureEvent) => {
            if (this.isAnswered || this.isCompleted) {
              return
            }
            const direction = this.getSwipeDirection()
            const blankIndex = this.gameBoard.indexOf(0)
            let targetIdx = blankIndex
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

      // Status bar: timer + move count
      Row() {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(12)
          .fontColor([$r('app.color.text_tertiary')])
        Text(this.formatTime(this.elapsedSeconds))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 4 })
        Blank()
        Text(`步数: ${this.moveCount}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 4 })
      }
      .width('100%')

      // Cancel button (only shown when not completed)
      if (!this.isCompleted && !this.isAnswered) {
        Button('取消')
          .width('50%')
          .height(32)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface'))
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.divider') })
          .onClick(() => {
            this.stopTimer()
            this.isCompleted = true
            const result: NumberPuzzleResult = {
              difficulty: this.gridSize,
              grid_size: `${this.gridSize}×${this.gridSize}`,
              time_seconds: 0,
              move_count: this.moveCount,
              completed: false
            }
            this.onAnswer(this.toolCall.id, JSON.stringify(result))
          })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.themeAiBubble)
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.divider') })
  }
}
