/**
 * MazeCard - 走迷宫互动卡片 (Paper Map v1)
 *
 * 设计语言: 儿童绘本纸面地图
 * - 纸面背景 (#F5EFE3 暖米黄), 深墨蓝墙线 (#1F3A52)
 * - 金色小星星玩家 (玩家位置), 紫色小屋锚点 (终点)
 * - 死胡同藏星星 (呼吸动画 + 收集旋转)
 * - 撞墙抖动 + 玩家移动弹簧动画
 *
 * 公共 API 保持家族一致: toolCall / isAnswered / answeredPayload / largeSize / onAnswer
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { getPreferencesService, PreferenceKeys } from '../services/PreferencesService'
import {
  MazeData,
  MazeCell,
  MazePosition,
  MazeDifficulty,
  Direction,
  generateMaze,
  canMove as mazeCanMove,
  movePlayer as mazeMovePlayer,
  isAtGoal,
  collectStar as mazeCollectStar,
  getDifficultyLabel,
  getGridSizeLabel,
  getGridDimensions
} from '../utils/MazeGame'

export interface MazeResult {
  difficulty: number
  grid_size: string
  time_seconds: number
  move_count: number
  stars_collected: number
  stars_total: number
  completed: boolean
}

@ComponentV2
export struct MazeCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  // 迷宫状态
  @Local maze: MazeData | null = null
  @Local playerPos: MazePosition = { row: 0, col: 0 }
  @Local difficulty: MazeDifficulty = 1

  // 计时与步数
  @Local moveCount: number = 0
  @Local startTime: number = 0
  @Local elapsedSeconds: number = 0
  @Local starsCollected: number = 0

  // 状态机
  @Local isCompleted: boolean = false
  @Local hasWon: boolean = false
  // 玩家移动入场动画: 首次渲染期间为 false, 之后开启
  @Local shouldAnimate: boolean = false
  @Local bestTimeSeconds: number = -1
  @Local bestMoves: number = -1
  @Local bestStars: number = -1
  @Local isNewBest: boolean = false
  @Local bestScoresLoaded: boolean = false

  // 触碰反馈
  @Local pressedCellKey: string = ''       // 当前按下的格子 (格式 "r,c")
  @Local wallBumpKey: string = ''          // 撞墙抖动键 (格式 "r,c")
  @Local wallBumpAxis: 'h' | 'v' = 'h'     // 抖动方向
  @Local wallBumpStep: number = 0          // 抖动阶段 (0=静止, 1-4=抖动幅度)
  @Local collectedKey: string = ''         // 刚被收集的星位置 (用于旋转动画)

  private timerId: number = -1
  private static readonly SUCCESS_GREEN: string = '#22C55E'

  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  // 纸面调色板
  private get paperBackground(): string {
    return this.isDarkMode ? '#2A2520' : '#F5EFE3'
  }

  private get cellPathColor(): string {
    return this.isDarkMode ? '#332E27' : '#FBF7EE'
  }

  private get wallColor(): string {
    return this.isDarkMode ? '#7FA8C9' : '#1F3A52'
  }

  private get boardBackground(): string {
    return withColorAlpha(this.wallColor, this.isDarkMode ? '0C' : '06')
  }

  // 单元格尺寸: 根据网格大小动态调整,8×8 自动缩小以适应聊天气泡宽度
  private get cellSize(): number {
    const rows: number = this.maze?.rows ?? this.difficultyToRows(this.difficulty)
    if (this.largeSize) {
      if (rows >= 8) return 52
      if (rows >= 6) return 60
      return 70
    }
    if (rows >= 8) return 40
    if (rows >= 6) return 42
    return 48
  }

  private get cellGap(): number {
    // 内联模式大格(cellSize≥40)用 0vp 间隙节省宽度, 小格保持 1vp 让墙条更明显
    if (this.largeSize) return 2
    return this.cellSize >= 40 ? 0 : 1
  }

  private get wallThickness(): number {
    return this.largeSize ? 4 : 3
  }

  private get playerSize(): number {
    // 玩家尺寸相对单元格缩放,8×8 自动适配更小的格子
    const rows: number = this.maze?.rows ?? this.difficultyToRows(this.difficulty)
    if (this.largeSize) {
      if (rows >= 8) return 26
      return 32
    }
    if (rows >= 8) return 20
    if (rows >= 6) return 22
    return 24
  }

  private get starSize(): number {
    const rows: number = this.maze?.rows ?? this.difficultyToRows(this.difficulty)
    if (this.largeSize) {
      if (rows >= 8) return 18
      return 22
    }
    if (rows >= 8) return 14
    if (rows >= 6) return 15
    return 16
  }

  private get goalSize(): number {
    const rows: number = this.maze?.rows ?? this.difficultyToRows(this.difficulty)
    if (this.largeSize) {
      if (rows >= 8) return 26
      return 32
    }
    if (rows >= 8) return 20
    if (rows >= 6) return 22
    return 24
  }

  private difficultyToRows(d: number): number {
    if (d >= 3) return 8
    if (d >= 2) return 6
    return 4
  }

  // 派生标签
  private get difficultyLabel(): string {
    const diffLabel: string = getDifficultyLabel(this.difficulty)
    const sizeLabel: string = getGridSizeLabel(this.difficulty)
    return `${diffLabel} · ${sizeLabel}`
  }

  private get totalMazeSize(): number {
    const dims = getGridDimensions(this.difficulty)
    return dims.rows * (this.cellSize + this.cellGap * 2) + this.cellGap * 2
  }

  aboutToAppear(): void {
    this.parseAndInitialize()
  }

  aboutToDisappear(): void {
    this.stopTimer()
  }

  private parseAndInitialize(): void {
    try {
      const args = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      const rawDiff = (args['difficulty'] as number) ?? 1
      const clamped: MazeDifficulty = (rawDiff >= 1 && rawDiff <= 3 ? rawDiff : 1) as MazeDifficulty
      this.difficulty = clamped

      if (this.isAnswered && this.answeredPayload !== '') {
        // 还原历史结果
        try {
          const result = JSON.parse(this.answeredPayload) as MazeResult
          this.elapsedSeconds = result.time_seconds ?? 0
          this.moveCount = result.move_count ?? 0
          this.starsCollected = result.stars_collected ?? 0
          this.hasWon = result.completed === true
          this.isCompleted = true
          // 尝试从 args 还原迷宫布局
          const cellsRaw = args['cells']
          if (cellsRaw !== undefined && cellsRaw !== null) {
            this.maze = this.deserializeMaze(args)
          }
        } catch (_e) {
          // 还原失败,使用空状态
        }
      } else if (this.isAnswered) {
        this.isCompleted = true
      } else {
        // 新游戏: 使用后端注入的 maze cells (如有), 否则现场生成
        const cellsRaw = args['cells']
        if (cellsRaw !== undefined && cellsRaw !== null) {
          this.maze = this.deserializeMaze(args)
        } else {
          const dims = getGridDimensions(clamped)
          this.maze = generateMaze(dims.rows, dims.cols, 2)
        }
        this.startTimer()
        // 初次渲染后开启入场动画, 避免首次出现玩家就有滑入效果
        this.shouldAnimate = true
      }

      // 异步加载最佳成绩(无论新游戏还是还原都需要)
      void this.loadBestScores(clamped)
    } catch (error) {
      console.error('MazeCard', `Failed to parse toolCall.arguments: ${String(error)}`)
      // 降级: 生成一个最小可玩迷宫
      this.maze = generateMaze(4, 4, 1)
    }
  }

  private deserializeMaze(args: Record<string, Object>): MazeData | null {
    try {
      const cellsRaw = args['cells'] as Record<string, Object>[]
      const rows = (args['rows'] as number) ?? 4
      const cols = (args['cols'] as number) ?? 4
      const starsTotal = (args['stars_total'] as number) ?? 0
      const cells: MazeCell[][] = []
      for (let r = 0; r < rows; r++) {
        const rowCells: MazeCell[] = []
        const srcRow = cellsRaw[r]
        if (srcRow === undefined) {
          return null
        }
        for (let c = 0; c < cols; c++) {
          const srcCell = srcRow[c] as Record<string, Object>
          if (srcCell === undefined) {
            return null
          }
          const wallsRaw = srcCell['walls'] as Record<string, Object>
          const cell: MazeCell = {
            walls: {
              top: (wallsRaw['top'] as boolean) === true,
              right: (wallsRaw['right'] as boolean) === true,
              bottom: (wallsRaw['bottom'] as boolean) === true,
              left: (wallsRaw['left'] as boolean) === true
            },
            hasStar: (srcCell['hasStar'] as boolean) === true,
            isStart: (srcCell['isStart'] as boolean) === true,
            isGoal: (srcCell['isGoal'] as boolean) === true
          }
          rowCells.push(cell)
        }
        cells.push(rowCells)
      }
      return { rows: rows, cols: cols, cells: cells, starsTotal: starsTotal }
    } catch (_e) {
      return null
    }
  }

  private async loadBestScores(difficulty: MazeDifficulty): Promise<void> {
    const prefs = getPreferencesService()
    try {
      this.bestTimeSeconds = await prefs.getNumber(
        PreferenceKeys.MAZE_BEST_TIME_PREFIX + difficulty.toString(), -1)
      this.bestMoves = await prefs.getNumber(
        PreferenceKeys.MAZE_BEST_MOVES_PREFIX + difficulty.toString(), -1)
      this.bestStars = await prefs.getNumber(
        PreferenceKeys.MAZE_BEST_STARS_PREFIX + difficulty.toString(), -1)
    } catch (_e) {
      this.bestTimeSeconds = -1
      this.bestMoves = -1
      this.bestStars = -1
    } finally {
      this.bestScoresLoaded = true
    }
  }

  private async saveBestScoresIfImproved(timeSec: number, moves: number, stars: number): Promise<void> {
    if (!this.bestScoresLoaded) {
      // 异步竞态守卫: 最佳成绩未加载完则放弃本次保存(避免 stale -1 覆盖真实最佳)
      return
    }
    const prefs = getPreferencesService()
    const key = this.difficulty.toString()
    const timeKey = PreferenceKeys.MAZE_BEST_TIME_PREFIX + key
    const movesKey = PreferenceKeys.MAZE_BEST_MOVES_PREFIX + key
    const starsKey = PreferenceKeys.MAZE_BEST_STARS_PREFIX + key

    let isNew = false
    if (this.bestTimeSeconds < 0 || timeSec < this.bestTimeSeconds) {
      await prefs.setNumber(timeKey, timeSec)
      isNew = true
    }
    if (this.bestMoves < 0 || moves < this.bestMoves) {
      await prefs.setNumber(movesKey, moves)
      isNew = true
    }
    if (this.bestStars < 0 || stars > this.bestStars) {
      await prefs.setNumber(starsKey, stars)
      isNew = true
    }
    if (isNew) {
      this.isNewBest = true
      this.bestTimeSeconds = Math.min(this.bestTimeSeconds < 0 ? timeSec : this.bestTimeSeconds, timeSec)
      this.bestMoves = Math.min(this.bestMoves < 0 ? moves : this.bestMoves, moves)
      this.bestStars = Math.max(this.bestStars < 0 ? stars : this.bestStars, stars)
    }
  }

  private startTimer(): void {
    this.stopTimer()
    this.startTime = Date.now()
    this.timerId = setInterval((): void => {
      if (!this.isCompleted && this.startTime > 0) {
        this.elapsedSeconds = Math.floor((Date.now() - this.startTime) / 1000)
      }
    }, 500)
  }

  private stopTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  private handleCellPress(row: number, col: number): void {
    if (this.isCompleted || this.maze === null) {
      return
    }
    if (row === this.playerPos.row && col === this.playerPos.col) {
      return
    }
    const dr = row - this.playerPos.row
    const dc = col - this.playerPos.col
    if (Math.abs(dr) + Math.abs(dc) !== 1) {
      // 非相邻: 拒绝(无视觉反馈,保持简单)
      return
    }
    const direction: Direction = dr === -1 ? 'top' : (dr === 1 ? 'bottom' : (dc === -1 ? 'left' : 'right'))
    const currentCell: MazeCell = this.maze.cells[this.playerPos.row][this.playerPos.col]
    if (!mazeCanMove(currentCell, direction)) {
      // 撞墙: 抖动反馈
      this.triggerWallBump(row, col, (direction === 'top' || direction === 'bottom') ? 'v' : 'h')
      return
    }
    const newPos = mazeMovePlayer(this.maze.cells, this.playerPos, direction)
    if (newPos === null) {
      return
    }
    this.moveCount += 1
    this.movePlayerVisually(newPos)
    // 检查收集星
    const landedCell: MazeCell = this.maze.cells[newPos.row][newPos.col]
    if (landedCell.hasStar && mazeCollectStar(landedCell)) {
      this.starsCollected += 1
      this.collectedKey = newPos.row + ',' + newPos.col
      setTimeout((): void => {
        this.collectedKey = ''
      }, 350)
    }
    // 检查终点
    if (isAtGoal(landedCell)) {
      this.handleWin()
    }
  }

  private handleCellTouchDown(row: number, col: number): void {
    if (this.isCompleted) {
      return
    }
    this.pressedCellKey = row + ',' + col
  }

  private handleCellTouchUp(): void {
    this.pressedCellKey = ''
  }

  private movePlayerVisually(newPos: MazePosition): void {
    // 初始渲染期间 shouldAnimate=false: 同步赋值, 不开启动画 (避免首屏兔子飞入)
    // 之后 shouldAnimate=true: 用 animateTo 包裹状态变化, 让 overlay 平滑滑动到新格子
    if (!this.shouldAnimate) {
      this.playerPos = newPos
      return
    }
    animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
      this.playerPos = newPos
    })
  }

  private triggerWallBump(row: number, col: number, axis: 'h' | 'v'): void {
    this.wallBumpKey = `${row},${col}`
    this.wallBumpAxis = axis
    this.wallBumpStep = 1
    setTimeout((): void => { this.wallBumpStep = 2 }, 50)
    setTimeout((): void => { this.wallBumpStep = 3 }, 100)
    setTimeout((): void => { this.wallBumpStep = 4 }, 150)
    setTimeout((): void => { this.wallBumpStep = 0 }, 220)
  }

  private getBumpOffset(row: number, col: number, axis: 'h' | 'v'): number {
    const cellKey: string = `${row},${col}`
    if (this.wallBumpKey !== cellKey) {
      return 0
    }
    if (axis !== this.wallBumpAxis) {
      return 0
    }
    if (this.wallBumpStep <= 0) {
      return 0
    }
    const offsets: number[] = [0, 3, -3, 1, -1]
    return offsets[this.wallBumpStep] ?? 0
  }

  private handleWin(): void {
    if (this.hasWon) {
      return
    }
    this.hasWon = true
    this.isCompleted = true
    this.stopTimer()
    const result: MazeResult = {
      difficulty: this.difficulty,
      grid_size: getGridSizeLabel(this.difficulty),
      time_seconds: this.elapsedSeconds,
      move_count: this.moveCount,
      stars_collected: this.starsCollected,
      stars_total: this.maze?.starsTotal ?? 0,
      completed: true
    }
    void this.saveBestScoresIfImproved(
      this.elapsedSeconds, this.moveCount, this.starsCollected
    )
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
  }

  private handleGiveUp(): void {
    if (this.isCompleted) {
      return
    }
    this.isCompleted = true
    this.hasWon = false
    this.stopTimer()
    const result: MazeResult = {
      difficulty: this.difficulty,
      grid_size: getGridSizeLabel(this.difficulty),
      time_seconds: this.elapsedSeconds,
      move_count: this.moveCount,
      stars_collected: this.starsCollected,
      stars_total: this.maze?.starsTotal ?? 0,
      completed: false
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
  }

  private formatTime(seconds: number): string {
    const m: number = Math.floor(seconds / 60)
    const s: number = seconds % 60
    if (m === 0) {
      return `0:${s.toString().padStart(2, '0')}`
    }
    return `${m}:${s.toString().padStart(2, '0')}`
  }

  build() {
    Column({ space: this.largeSize ? 14 : 10 }) {
      this.HeaderRow()

      if (this.hasWon) {
        this.WinBanner()
      }

      this.MazePanel()

      this.StatsGrid()

      this.ActionRow()
    }
    .width('100%')
    .padding(this.largeSize ? 20 : 14)
    .backgroundColor(this.largeSize ? Color.Transparent : this.themeAiBubble)
    .borderRadius(this.largeSize ? 0 : 14)
    .border(this.largeSize
      ? { width: 0, color: Color.Transparent, style: BorderStyle.Solid }
      : { width: 1, color: $r('app.color.divider'), style: BorderStyle.Solid })
  }

  @Builder
  HeaderRow() {
    Row() {
      Column() {
        SymbolGlyph($r('sys.symbol.map'))
          .fontSize(15)
          .fontColor([this.themeAiBubble === '#FFFDF8' ? '#FF9F43' : this.themeAiBubble])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(withColorAlpha('#FF9F43', '18'))
      .justifyContent(FlexAlign.Center)

      Column() {
        Text('走迷宫')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.difficultyLabel)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })

      Blank()

      if (this.isAnswered || this.isCompleted) {
        Text(this.hasWon ? '已完成' : '已放弃')
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor(this.hasWon ? $r('app.color.status_success') : '#FF9F43')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  WinBanner() {
    Row({ space: 10 }) {
      Text('🎉')
        .fontSize(26)
      Column() {
        Text(this.isAnswered ? '已完成' : '走出迷宫！')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.status_success'))
        Text(`${this.formatTime(this.elapsedSeconds)} · ${this.moveCount} 步${this.maze !== null && this.maze.starsTotal > 0 ? ' · 🥕' + this.starsCollected + '/' + this.maze.starsTotal : ''}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.isNewBest) {
        Text('新纪录')
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.status_success'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(withColorAlpha(MazeCard.SUCCESS_GREEN, this.isDarkMode ? '18' : '0C'))
    .borderRadius(12)
    .border({
      width: 1,
      color: withColorAlpha(MazeCard.SUCCESS_GREEN, this.isDarkMode ? '38' : '28'),
      style: BorderStyle.Solid
    })
  }

  @Builder
  MazePanel() {
    Column() {
      if (this.maze !== null) {
        Stack() {
          // 背景层: 单元格网格(不含玩家)
          Column() {
            ForEach(this.maze.cells, (row: MazeCell[], rowIndex: number) => {
              Row() {
                ForEach(row, (cell: MazeCell, colIndex: number) => {
                  this.MazeCellView(cell, rowIndex, colIndex)
                }, (cell: MazeCell, colIndex: number) => `cell_${rowIndex}_${colIndex}`)
              }
              .width('100%')
            }, (row: MazeCell[], rowIndex: number) => `row_${rowIndex}`)
          }
          .width('100%')

          // 前景层: 玩家 overlay(绝对定位, 通过 .position() 滑动)
          if (this.shouldShowPlayer) {
            Column() {
              Text('🐰')
                .fontSize(this.playerSize)
            }
            .width(this.cellSize)
            .height(this.cellSize)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .position({
              x: this.cellGap + this.playerPos.col * (this.cellSize + this.cellGap * 2),
              y: this.cellGap + this.playerPos.row * (this.cellSize + this.cellGap * 2)
            })
            .animation({ duration: 200, curve: Curve.EaseOut })
          }
        }
        .width('100%')
        .padding(this.cellGap * 2)
        .backgroundColor(this.boardBackground)
        .borderRadius(14)
        .border({
          width: 0.5,
          color: withColorAlpha(this.wallColor, this.isDarkMode ? '20' : '14'),
          style: BorderStyle.Solid
        })
      }
    }
    .width('100%')
    .onTouch((e: TouchEvent) => {
      // 阻止事件冒泡到外层 List(scroll)
      e.stopPropagation()
    })
  }

  private get shouldShowPlayer(): boolean {
    if (this.maze === null) {
      return false
    }
    if (this.isCompleted && this.hasWon) {
      return false
    }
    const cell: MazeCell = this.maze.cells[this.playerPos.row][this.playerPos.col]
    return !cell.isGoal
  }

  @Builder
  MazeCellView(cell: MazeCell, row: number, col: number) {
    Stack() {
      // path 背景
      Column()
        .width(this.cellSize)
        .height(this.cellSize)
        .backgroundColor(this.cellPathColor)

      // 墙条: 上、右、下、左(只在有墙时绘制)
      if (cell.walls.top) {
        Column()
          .width(this.cellSize)
          .height(this.wallThickness)
          .backgroundColor(this.wallColor)
          .position({ x: 0, y: 0 })
      }
      if (cell.walls.right) {
        Column()
          .width(this.wallThickness)
          .height(this.cellSize)
          .backgroundColor(this.wallColor)
          .position({ x: this.cellSize - this.wallThickness, y: 0 })
      }
      if (cell.walls.bottom) {
        Column()
          .width(this.cellSize)
          .height(this.wallThickness)
          .backgroundColor(this.wallColor)
          .position({ x: 0, y: this.cellSize - this.wallThickness })
      }
      if (cell.walls.left) {
        Column()
          .width(this.wallThickness)
          .height(this.cellSize)
          .backgroundColor(this.wallColor)
          .position({ x: 0, y: 0 })
      }

      // 中心图标: 终点(小屋) / 隐藏胡萝卜 (玩家已提升为 MazePanel 顶层 overlay, 避免 transition 残影)
      if (cell.isGoal) {
        // 目的地印章: 虚线圆角包裹, 强化"纸面地图 + 终点标记"语义
        Column()
          .width(this.cellSize - 6)
          .height(this.cellSize - 6)
          .border({
            width: 1.5,
            color: withColorAlpha(this.wallColor, this.isDarkMode ? '50' : '38'),
            style: BorderStyle.Dashed
          })
          .borderRadius(this.cellSize * 0.22)
          .position({ x: 3, y: 3 })
        Column() {
          Text('🏠')
            .fontSize(this.goalSize)
        }
        .width(this.cellSize)
        .height(this.cellSize)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (cell.hasStar && this.collectedKey !== row + ',' + col) {
        Column() {
          Text('🥕')
            .fontSize(this.starSize)
        }
        .width(this.cellSize)
        .height(this.cellSize)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width(this.cellSize)
    .height(this.cellSize)
    .margin(this.cellGap)
    .translate({
      x: this.getBumpOffset(row, col, 'h'),
      y: this.getBumpOffset(row, col, 'v')
    })
    .animation({ duration: 50, curve: Curve.EaseOut })
    .scale({
      x: this.pressedCellKey === `${row},${col}` ? 0.94 : 1,
      y: this.pressedCellKey === `${row},${col}` ? 0.94 : 1
    })
    .animation({ duration: 80, curve: Curve.EaseOut })
    .onClick((): void => {
      this.handleCellPress(row, col)
    })
    .onTouch((e: TouchEvent) => {
      e.stopPropagation()
    })
  }

  @Builder
  StatsGrid() {
    Row({ space: 8 }) {
      // 时间卡片
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text('⏱')
            .fontSize(11)
          Text('时间')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        Text(this.formatTime(this.elapsedSeconds))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        if (this.bestTimeSeconds >= 0) {
          Text(`最佳 ${this.formatTime(this.bestTimeSeconds)}`)
            .fontSize(10)
            .fontColor(this.isNewBest ? $r('app.color.status_success') : $r('app.color.text_tertiary'))
        }
      }
      .layoutWeight(1)
      .padding(10)
      .borderRadius(10)
      .backgroundColor(withColorAlpha(this.wallColor, this.isDarkMode ? '12' : '08'))
      .border({
        width: 1,
        color: this.isNewBest
          ? withColorAlpha(MazeCard.SUCCESS_GREEN, '60')
          : withColorAlpha(this.wallColor, this.isDarkMode ? '28' : '1C'),
        style: BorderStyle.Solid
      })

      // 步数卡片
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text('👆')
            .fontSize(11)
          Text('步数')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        Text(this.moveCount.toString())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        if (this.bestMoves >= 0) {
          Text(`最佳 ${this.bestMoves}`)
            .fontSize(10)
            .fontColor(this.isNewBest ? $r('app.color.status_success') : $r('app.color.text_tertiary'))
        }
      }
      .layoutWeight(1)
      .padding(10)
      .borderRadius(10)
      .backgroundColor(withColorAlpha('#B45309', this.isDarkMode ? '12' : '08'))
      .border({
        width: 1,
        color: this.isNewBest
          ? withColorAlpha(MazeCard.SUCCESS_GREEN, '60')
          : withColorAlpha('#B45309', this.isDarkMode ? '28' : '1C'),
        style: BorderStyle.Solid
      })

      // 收藏卡片(胡萝卜)
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text('🥕')
            .fontSize(11)
          Text('胡萝卜')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        Text(this.maze !== null
          ? `${this.starsCollected}/${this.maze.starsTotal}`
          : '0/0')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        if (this.bestStars >= 0) {
          Text(`最佳 ${this.bestStars}`)
            .fontSize(10)
            .fontColor(this.isNewBest ? $r('app.color.status_success') : $r('app.color.text_tertiary'))
        }
      }
      .layoutWeight(1)
      .padding(10)
      .borderRadius(10)
      .backgroundColor(withColorAlpha('#FF9F43', this.isDarkMode ? '10' : '08'))
      .border({
        width: 1,
        color: this.isNewBest
          ? withColorAlpha(MazeCard.SUCCESS_GREEN, '60')
          : withColorAlpha('#FF9F43', this.isDarkMode ? '22' : '18'),
        style: BorderStyle.Solid
      })
    }
    .width('100%')
  }

  @Builder
  ActionRow() {
    Row() {
      Blank()
      if (!this.hasWon && !this.isAnswered && !this.isCompleted) {
        Text('走不出去了？换一局 →')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .padding(8)
          .onClick((): void => {
            this.handleGiveUp()
          })
      }
    }
    .width('100%')
  }
}