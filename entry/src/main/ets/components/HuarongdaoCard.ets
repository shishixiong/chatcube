/**
 * HuarongdaoCard - 数字华容道互动卡片
 *
 * 与 MathQuizCard / EnglishQuizCard 同模式的 @ComponentV2 卡片:
 * - 解析 toolCall.arguments 中的打乱棋盘 (tiles + grid_size + difficulty)
 * - 渲染 3×3 / 4×4 数字方块
 * - 点击相邻方块进入空位
 * - 计时 + 步数
 * - 完成或放弃时通过 onAnswer 回调提交结果 JSON
 *
 * 谜题由 ToolExecutionService.handleHuarongdao 后台生成并注入 toolCall.arguments,
 * 此处只做前端渲染与交互, 不再重复生成 (避免与后端不同步).
 *
 * 与 NumberPuzzleCard 的关系: 本卡片是 huarongdao 工具专用, 始终内联在聊天气泡中,
 * 不支持 largeSize sheet 模式, 也不持久化最佳成绩. NumberPuzzleCard 独立保留.
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { generatePuzzle, HuarongdaoPuzzleState } from '../utils/HuarongdaoPuzzleGenerator'

export interface HuarongdaoPuzzleResult {
  difficulty: number
  grid_size: string
  time_seconds: number
  move_count: number
  completed: boolean
}

interface HuarongdaoCardArgs {
  difficulty: number
  tiles: number[]
  grid_size: number
}

@ComponentV2
export struct HuarongdaoCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local gameBoard: number[] = []
  @Local gridSize: number = 3
  @Local difficulty: number = 1
  @Local moveCount: number = 0
  @Local startTime: number = 0
  @Local elapsedSeconds: number = 0
  @Local isCompleted: boolean = false
  @Local hasWon: boolean = false
  @Local tilePressedIndex: number = -1

  private timerId: number = -1
  // WinBanner / 完成态共用的成功绿
  private readonly SUCCESS_GREEN: string = '#22C55E'
  private readonly GIVE_UP_ORANGE: string = '#FF9F43'

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
    if (this.gridSize <= 3) {
      return 56
    }
    return 44
  }

  private get cellMargin(): number {
    if (this.gridSize <= 3) {
      return 5
    }
    return 4
  }

  private get boardWidth(): number {
    return (this.cellSize + this.cellMargin * 2) * this.gridSize
  }

  private get maxFontSize(): number {
    return Math.floor(this.cellSize * 0.55)
  }

  private get difficultyLabel(): string {
    if (this.gridSize === 3) {
      return '简单 · 3×3'
    }
    if (this.gridSize === 4) {
      return '进阶 · 4×4'
    }
    return `${this.gridSize}×${this.gridSize}`
  }

  aboutToAppear(): void {
    if (this.isAnswered) {
      this.parsePreviousResult()
    } else {
      this.loadInitialBoard()
    }
  }

  aboutToDisappear(): void {
    this.stopTimer()
  }

  private loadInitialBoard(): void {
    // 优先使用 ToolExecutionService 注入的棋盘 (与后端保持一致);
    // 注入缺失时降级到本地生成 (避免显示空棋盘)
    const loaded: HuarongdaoCardArgs | null = this.parseToolCallArgs()
    if (loaded === null || loaded.tiles.length !== loaded.grid_size * loaded.grid_size) {
      const fallback: HuarongdaoPuzzleState = generatePuzzle(this.difficulty)
      this.gameBoard = [...fallback.tiles]
      this.gridSize = fallback.gridSize
      this.difficulty = fallback.difficulty
    } else {
      this.gameBoard = [...loaded.tiles]
      this.gridSize = loaded.grid_size
      this.difficulty = loaded.difficulty
    }
    this.isCompleted = false
    this.hasWon = false
    this.moveCount = 0
    this.startTime = Date.now()
    this.elapsedSeconds = 0
    this.startTimer()
  }

  private parseToolCallArgs(): HuarongdaoCardArgs | null {
    try {
      const parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      const tilesRaw = parsed['tiles']
      const gridSizeRaw = parsed['grid_size']
      const difficultyRaw = parsed['difficulty']
      if (!Array.isArray(tilesRaw) || typeof gridSizeRaw !== 'number') {
        return null
      }
      const tiles: number[] = []
      for (let i = 0; i < tilesRaw.length; i++) {
        tiles.push(tilesRaw[i] as number)
      }
      return {
        difficulty: typeof difficultyRaw === 'number' ? difficultyRaw : 1,
        tiles,
        grid_size: gridSizeRaw
      }
    } catch (_e) {
      return null
    }
  }

  private parsePreviousResult(): void {
    if (this.answeredPayload === '') {
      return
    }
    try {
      const result = JSON.parse(this.answeredPayload) as HuarongdaoPuzzleResult
      this.gridSize = result.difficulty
      this.isCompleted = true
      this.hasWon = result.completed
      this.gameBoard = this.solvedBoard
      this.moveCount = result.move_count
      this.elapsedSeconds = Math.floor(result.time_seconds)
    } catch (_e) {
      // ignore
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
    const newBoard: number[] = [...this.gameBoard]
    const temp: number = newBoard[tileIndex]
    newBoard[tileIndex] = newBoard[blankIndex]
    newBoard[blankIndex] = temp
    this.gameBoard = newBoard
    this.moveCount++
    this.evaluateWin()
  }

  private evaluateWin(): void {
    const isWin = this.gameBoard.join(',') === this.solvedBoard.join(',')
    if (!isWin) {
      return
    }
    this.isCompleted = true
    this.hasWon = true
    this.stopTimer()
    const timeMs = Date.now() - this.startTime
    const timeSeconds = Number((timeMs / 1000).toFixed(1))
    this.elapsedSeconds = Math.floor(timeSeconds)

    const result: HuarongdaoPuzzleResult = {
      difficulty: this.gridSize,
      grid_size: `${this.gridSize}×${this.gridSize}`,
      time_seconds: timeSeconds,
      move_count: this.moveCount,
      completed: true
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
  }

  private handleGiveUp(): void {
    if (this.isCompleted) {
      return
    }
    this.isCompleted = true
    this.hasWon = false
    this.stopTimer()
    const timeMs = Date.now() - this.startTime
    const timeSeconds = Number((timeMs / 1000).toFixed(1))
    this.elapsedSeconds = Math.floor(timeSeconds)

    const result: HuarongdaoPuzzleResult = {
      difficulty: this.gridSize,
      grid_size: `${this.gridSize}×${this.gridSize}`,
      time_seconds: timeSeconds,
      move_count: this.moveCount,
      completed: false
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
  }

  private getTileGradient(value: number): LinearGradient {
    if (this.isDarkMode) {
      const top = this.themePrimary
      const bottom = this.shadeHex(top, 0.78)
      return {
        angle: 180,
        colors: [[top, 0.0], [bottom, 1.0]]
      }
    }
    // 浅色模式: 3 阶琥珀渐变, 按 value % 3 分布
    const variant = ((value - 1) % 3 + 3) % 3
    if (variant === 1) {
      return { angle: 180, colors: [['#FCD34D', 0.0], ['#D97706', 1.0]] }
    } else if (variant === 2) {
      return { angle: 180, colors: [['#FBBF24', 0.0], ['#B45309', 1.0]] }
    }
    return { angle: 180, colors: [['#F59E0B', 0.0], ['#92400E', 1.0]] }
  }

  private shadeHex(color: string, factor: number): string {
    if (!color.startsWith('#') || color.length !== 7) {
      return color
    }
    const r = parseInt(color.substring(1, 3), 16)
    const g = parseInt(color.substring(3, 5), 16)
    const b = parseInt(color.substring(5, 7), 16)
    const nr = Math.max(0, Math.min(255, Math.floor(r * factor)))
    const ng = Math.max(0, Math.min(255, Math.floor(g * factor)))
    const nb = Math.max(0, Math.min(255, Math.floor(b * factor)))
    const toHex = (n: number): string => {
      const s = n.toString(16)
      return s.length === 1 ? `0${s}` : s
    }
    return `#${toHex(nr)}${toHex(ng)}${toHex(nb)}`
  }

  @Builder
  private EmptySlotBlock() {
    Column() {
    }
    .width(this.cellSize)
    .height(this.cellSize)
    .margin(this.cellMargin)
    .borderRadius(10)
    .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '14' : '08'))
    .border({
      width: 1.5,
      color: withColorAlpha(this.themePrimary, this.isDarkMode ? '38' : '28'),
      style: BorderStyle.Dashed
    })
  }

  @Builder
  private TileBlock(value: number, index: number) {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient(this.getTileGradient(value))
        .borderRadius(10)
      Text(`${value}`)
        .fontSize(this.maxFontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
    }
    .width(this.cellSize)
    .height(this.cellSize)
    .margin(this.cellMargin)
    .borderRadius(10)
    .shadow({
      radius: 6,
      color: '#1F000000',
      offsetY: 2
    })
    .scale({
      x: this.tilePressedIndex === index ? 0.94 : 1,
      y: this.tilePressedIndex === index ? 0.94 : 1
    })
    .animation({ duration: 80, curve: Curve.EaseOut })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.tilePressedIndex = index
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.tilePressedIndex = -1
      }
    })
    .onClick(() => {
      this.moveTile(index)
    })
  }

  @Builder
  private Board() {
    Column() {
      Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
        ForEach(this.gameBoard, (item: number, index: number) => {
          if (item === 0) {
            this.EmptySlotBlock()
          } else {
            this.TileBlock(item, index)
          }
        }, (item: number, index: number) => `tile_${index}_${item}`)
      }
      .width(this.boardWidth)
    }
    .width('100%')
    .padding(this.gridSize <= 3 ? 10 : 8)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(14)
    .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '14' : '0C'))
    .border({
      width: 0.5,
      color: withColorAlpha(this.themePrimary, this.isDarkMode ? '28' : '18'),
      style: BorderStyle.Solid
    })
  }

  @Builder
  private StatusBanner() {
    if (this.hasWon) {
      Row({ space: 8 }) {
        Text('🎉')
          .fontSize(22)
        Text(this.isAnswered ? '已完成' : '太棒了！拼好了')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.SUCCESS_GREEN)
        Blank()
        Text(`${this.elapsedSeconds}s · ${this.moveCount} 步`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .borderRadius(12)
      .backgroundColor(withColorAlpha(this.SUCCESS_GREEN, this.isDarkMode ? '18' : '0C'))
      .border({
        width: 1,
        color: withColorAlpha(this.SUCCESS_GREEN, this.isDarkMode ? '38' : '28'),
        style: BorderStyle.Solid
      })
    } else if (this.isAnswered) {
      Row({ space: 8 }) {
        Text('已放弃')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.GIVE_UP_ORANGE)
        Blank()
        Text(`${this.elapsedSeconds}s · ${this.moveCount} 步`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .borderRadius(12)
      .backgroundColor(withColorAlpha(this.GIVE_UP_ORANGE, this.isDarkMode ? '18' : '0C'))
      .border({
        width: 1,
        color: withColorAlpha(this.GIVE_UP_ORANGE, this.isDarkMode ? '38' : '28'),
        style: BorderStyle.Solid
      })
    }
  }

  @Builder
  private StatsRow() {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text('用时')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text(`${this.elapsedSeconds}s`)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding(10)
      .borderRadius(10)
      .backgroundColor(this.themeAiBubble)

      Column({ space: 2 }) {
        Text('步数')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text(`${this.moveCount}`)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding(10)
      .borderRadius(10)
      .backgroundColor(this.themeAiBubble)
    }
    .width('100%')
  }

  build() {
    Column({ space: 10 }) {
      // 标题行
      Row({ space: 8 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.puzzle'))
            .fontSize(14)
            .fontColor([this.themePrimary])
        }
        .width(28)
        .height(28)
        .borderRadius(14)
        .backgroundColor(withColorAlpha(this.themePrimary, '18'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Text('数字华容道')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Text(this.difficultyLabel)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      this.StatusBanner()

      this.Board()

      this.StatsRow()

      if (!this.isAnswered && !this.isCompleted) {
        Row() {
          Blank()
          Text('放弃本局')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .padding(8)
            .onClick(() => {
              this.handleGiveUp()
            })
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor(this.themeAiBubble)
    .border({ width: 1, color: $r('app.color.divider') })
    .alignItems(HorizontalAlign.Start)
  }
}
