/**
 * NumberPuzzleCard - 数字华容道互动卡片 (Premium Tactile v2)
 *
 * 设计升级:
 * - 拼图块: 暖色琥珀渐变 + 软投影 + 圆角, 呈现精致木质 token 质感
 * - 空位: 虚线轮廓 + 极淡填充, 引导孩子发现"洞"
 * - 计时/步数: 双卡片网格 + 最佳成绩 (持久化到 PreferencesService)
 * - 完成态: 庆祝横幅 + 错位高亮 + 新纪录徽章
 * - 操作: 精简为"放弃本局"文字链, 不再占据 50% 宽度
 *
 * 公共 API 保持稳定: toolCall / isAnswered / answeredPayload / largeSize / onAnswer,
 * 以及导出的 NumberPuzzleResult 接口. 内部行为增强, 调用方零改动.
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { getPreferencesService, PreferenceKeys } from '../services/PreferencesService'

export interface NumberPuzzleResult {
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
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local gameBoard: number[] = []
  @Local gridSize: number = 3
  @Local moveCount: number = 0
  @Local startTime: number = 0
  @Local elapsedSeconds: number = 0
  @Local isCompleted: boolean = false
  @Local shouldAnimate: boolean = true
  @Local hasWon: boolean = false
  @Local bestTimeSeconds: number = -1
  @Local bestMoves: number = -1
  @Local isNewBest: boolean = false
  @Local tilePressedIndex: number = -1
  @Local winPopIndex: number = -1

  private timerId: number = -1
  private winPopTimerId: number = -1

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
    if (this.largeSize) {
      switch (this.gridSize) {
        case 2: return 112
        case 3: return 88
        case 4: return 70
        case 5: return 58
        default: return 88
      }
    }
    switch (this.gridSize) {
      case 2: return 68
      case 3: return 60
      case 4: return 48
      case 5: return 42
      default: return 60
    }
  }

  private get cellMargin(): number {
    if (this.largeSize) {
      return this.gridSize <= 3 ? 6 : 5
    }
    return this.gridSize <= 3 ? 5 : 4
  }

  private get totalWidth(): number {
    return (this.cellSize + this.cellMargin * 2) * this.gridSize
  }

  private get maxFontSize(): number {
    return Math.floor(this.cellSize * 0.6)
  }

  private get difficultyLabel(): string {
    switch (this.gridSize) {
      case 2: return '幼儿 · 2×2'
      case 3: return '简单 · 3×3'
      case 4: return '进阶 · 4×4'
      case 5: return '挑战 · 5×5'
      default: return `${this.gridSize}×${this.gridSize}`
    }
  }

  aboutToAppear(): void {
    this.parseDifficulty()
    if (this.isAnswered) {
      this.parsePreviousResult()
    } else {
      this.shuffleGameBoard()
    }
    this.loadBestScores(this.gridSize)
  }

  aboutToDisappear(): void {
    this.stopTimer()
    if (this.winPopTimerId >= 0) {
      clearTimeout(this.winPopTimerId)
      this.winPopTimerId = -1
    }
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
      this.hasWon = result.completed
      this.gameBoard = this.solvedBoard
      this.moveCount = result.move_count
      this.elapsedSeconds = Math.floor(result.time_seconds)
    } catch (_e) {
      // ignore parse failure
    }
  }

  private async loadBestScores(difficulty: number): Promise<void> {
    try {
      const prefs = getPreferencesService()
      const timeKey = `${PreferenceKeys.NUMBER_PUZZLE_BEST_TIME_PREFIX}${difficulty}`
      const movesKey = `${PreferenceKeys.NUMBER_PUZZLE_BEST_MOVES_PREFIX}${difficulty}`
      this.bestTimeSeconds = await prefs.getNumber(timeKey, -1)
      this.bestMoves = await prefs.getNumber(movesKey, -1)
    } catch (_e) {
      this.bestTimeSeconds = -1
      this.bestMoves = -1
    }
  }

  private async saveBestScoresIfImproved(): Promise<void> {
    try {
      const prefs = getPreferencesService()
      const timeKey = `${PreferenceKeys.NUMBER_PUZZLE_BEST_TIME_PREFIX}${this.gridSize}`
      const movesKey = `${PreferenceKeys.NUMBER_PUZZLE_BEST_MOVES_PREFIX}${this.gridSize}`
      const isNewBestTime = this.bestTimeSeconds < 0 || this.elapsedSeconds < this.bestTimeSeconds
      const isNewBestMoves = this.bestMoves < 0 || this.moveCount < this.bestMoves
      if (isNewBestTime) {
        await prefs.setNumber(timeKey, this.elapsedSeconds)
        this.bestTimeSeconds = this.elapsedSeconds
      }
      if (isNewBestMoves) {
        await prefs.setNumber(movesKey, this.moveCount)
        this.bestMoves = this.moveCount
      }
      this.isNewBest = isNewBestTime || isNewBestMoves
    } catch (_e) {
      // ignore persistence errors
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
    this.hasWon = false
    this.isNewBest = false
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
      case 'up': return blankIndex - this.gridSize
      case 'down': return blankIndex + this.gridSize
      case 'left': return blankIndex - 1
      case 'right': return blankIndex + 1
      default: return blankIndex
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
    this.evaluateWin()
  }

  private evaluateWin(): void {
    const winState = this.solvedBoard
    const isWin = this.gameBoard.join(',') === winState.join(',')
    if (!isWin) {
      return
    }

    this.isCompleted = true
    this.hasWon = true
    this.stopTimer()
    const timeMs = Date.now() - this.startTime
    const timeSeconds = Number((timeMs / 1000).toFixed(1))
    this.elapsedSeconds = Math.floor(timeSeconds)

    this.triggerWinPop()

    const result: NumberPuzzleResult = {
      difficulty: this.gridSize,
      grid_size: `${this.gridSize}×${this.gridSize}`,
      time_seconds: timeSeconds,
      move_count: this.moveCount,
      completed: true
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(result))

    // Fire-and-forget: persist best scores in background
    this.saveBestScoresIfImproved()
  }

  private triggerWinPop(): void {
    if (this.winPopTimerId >= 0) {
      clearTimeout(this.winPopTimerId)
      this.winPopTimerId = -1
    }
    const total = this.gameBoard.length
    let i = 0
    const pop = (): void => {
      if (i >= total || !this.hasWon || this.isAnswered) {
        this.winPopIndex = -1
        return
      }
      this.winPopIndex = i
      i++
      this.winPopTimerId = setTimeout(pop, 30)
    }
    pop()
  }

  private handleGiveUp(): void {
    if (this.isCompleted || this.isAnswered) {
      return
    }
    this.stopTimer()
    this.isCompleted = true
    this.hasWon = false
    const result: NumberPuzzleResult = {
      difficulty: this.gridSize,
      grid_size: `${this.gridSize}×${this.gridSize}`,
      time_seconds: 0,
      move_count: this.moveCount,
      completed: false
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
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
        }).animation({ duration: 200, curve: Curve.EaseOut })
      } else if (diff === this.gridSize) {
        const dir = index > blankIndex ? -1 : 1
        return TransitionEffect.translate({
          y: `${dir * step}lpx`
        }).animation({ duration: 200, curve: Curve.EaseOut })
      }
    }
    return undefined
  }

  private isValidIndex(index: number): boolean {
    return index >= 0 && index < this.gameBoard.length
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
    // 浅色模式: 琥珀光谱, 按 value 分布 3 种深浅, 让拼图块有视觉节奏
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
    const newR = Math.max(0, Math.min(255, Math.floor(r * factor)))
    const newG = Math.max(0, Math.min(255, Math.floor(g * factor)))
    const newB = Math.max(0, Math.min(255, Math.floor(b * factor)))
    const toHex = (n: number): string => {
      const h = n.toString(16)
      return h.length === 1 ? '0' + h : h
    }
    return `#${toHex(newR)}${toHex(newG)}${toHex(newB)}`
  }

  private getTileShadow(): ShadowOptions {
    if (this.tilePressedIndex >= 0) {
      return { radius: 4, color: '#14000000', offsetY: 1 }
    }
    return { radius: 8, color: '#1F000000', offsetY: 2 }
  }

  private getBoardBackgroundColor(): string {
    return this.isDarkMode
      ? withColorAlpha(this.themePrimary, '14')
      : withColorAlpha(this.themePrimary, '0C')
  }

  private getEmptySlotBackgroundColor(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '08' : '05')
  }

  private getEmptySlotBorderColor(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '38' : '2C')
  }

  private getStatCardBorderColor(): ResourceColor {
    if (this.isNewBest) {
      return withColorAlpha('#22C55E', '60')
    }
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '22' : '18')
  }

  private getStatCardBackgroundColor(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '10' : '08')
  }

  private formatTime(seconds: number): string {
    const m = Math.floor(seconds / 60)
    const s = seconds % 60
    const sStr = s < 10 ? `0${s}` : `${s}`
    return `${m}:${sStr}`
  }

  private formatBestSubline(isTime: boolean): string {
    if (isTime) {
      return this.bestTimeSeconds < 0 ? ' ' : `最佳 ${this.formatTime(this.bestTimeSeconds)}`
    }
    return this.bestMoves < 0 ? ' ' : `最佳 ${this.bestMoves}`
  }

  build() {
    Column({ space: this.largeSize ? 14 : 10 }) {
      this.HeaderRow()

      if (this.hasWon) {
        this.WinBanner()
      }

      this.BoardPanel()

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
      // 圆形徽章里的灯泡
      Column() {
        SymbolGlyph($r('sys.symbol.lightbulb'))
          .fontSize(15)
          .fontColor([this.themePrimary])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(withColorAlpha(this.themePrimary, '18'))
      .justifyContent(FlexAlign.Center)

      Column() {
        Text('数字华容道')
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
        Text(this.isAnswered ? '已完成' : '太棒了！拼好了')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.status_success'))
        Text(`${this.formatTime(this.elapsedSeconds)} · ${this.moveCount} 步`)
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
    .backgroundColor(withColorAlpha('#22C55E', this.isDarkMode ? '18' : '0C'))
    .borderRadius(12)
    .border({
      width: 1,
      color: withColorAlpha('#22C55E', this.isDarkMode ? '38' : '28'),
      style: BorderStyle.Solid
    })
  }

  @Builder
  BoardPanel() {
    Column() {
      Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
        ForEach(this.gameBoard, (item: number, index: number) => {
          if (item === 0) {
            this.EmptySlot()
          } else {
            this.Tile(item, index)
          }
        }, (item: number, index: number) => `tile_${index}_${item}`)
      }
      .width(`${this.totalWidth}lpx`)
    }
    .width('100%')
    .padding(this.gridSize <= 3 ? 12 : 10)
    .backgroundColor(this.getBoardBackgroundColor())
    .borderRadius(14)
    .border({
      width: 0.5,
      color: withColorAlpha(this.themePrimary, this.isDarkMode ? '20' : '14'),
      style: BorderStyle.Solid
    })
    .onTouch((e: TouchEvent) => {
      e.stopPropagation()
    })
    .priorityGesture(
      PanGesture({ direction: PanDirection.All, distance: 10 })
        .onActionEnd((event: GestureEvent) => {
          if (this.isAnswered || this.isCompleted) {
            return
          }
          const offsetX = event.offsetX as number
          const offsetY = event.offsetY as number
          if (Math.abs(offsetX) < 10 && Math.abs(offsetY) < 10) {
            return
          }
          const blankIndex = this.gameBoard.indexOf(0)
          let targetIdx = blankIndex
          if (Math.abs(offsetX) > Math.abs(offsetY)) {
            targetIdx = offsetX > 0 ? blankIndex - 1 : blankIndex + 1
          } else {
            targetIdx = offsetY > 0 ? blankIndex - this.gridSize : blankIndex + this.gridSize
          }
          if (this.isValidIndex(targetIdx)) {
            this.moveTile(targetIdx)
          }
        })
    )
  }

  @Builder
  EmptySlot() {
    Column() {
      // 极小的指示点, 让空位有"等待落子"的暗示
      Column()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(withColorAlpha(this.themePrimary, '30'))
    }
    .width(`${this.cellSize}lpx`)
    .height(`${this.cellSize}lpx`)
    .margin(`${this.cellMargin}lpx`)
    .borderRadius(10)
    .backgroundColor(this.getEmptySlotBackgroundColor())
    .border({
      width: 1.5,
      style: BorderStyle.Dashed,
      color: this.getEmptySlotBorderColor()
    })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  Tile(value: number, index: number) {
    Stack() {
      // 渐变背景
      Column()
        .width('100%')
        .height('100%')
        .linearGradient(this.getTileGradient(value))
        .borderRadius(10)
      // 数字
      Text(`${value}`)
        .fontSize(`${this.maxFontSize}lpx`)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .textShadow({ radius: 1.5, color: '#40000000', offsetX: 0, offsetY: 1 })
    }
    .width(`${this.cellSize}lpx`)
    .height(`${this.cellSize}lpx`)
    .margin(`${this.cellMargin}lpx`)
    .borderRadius(10)
    .shadow(this.getTileShadow())
    .scale({
      x: this.tilePressedIndex === index ? 0.94 : 1,
      y: this.tilePressedIndex === index ? 0.94 : 1
    })
    .animation({ duration: 80, curve: Curve.EaseOut })
    .border(this.winPopIndex >= 0 && !this.isAnswered && index <= this.winPopIndex
      ? { width: 2, color: $r('app.color.status_success'), style: BorderStyle.Solid }
      : { width: 0, color: Color.Transparent, style: BorderStyle.Solid })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.tilePressedIndex = index
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.tilePressedIndex = -1
      }
    })
    .onClick(() => {
      if (this.canMove(index) && !this.isCompleted) {
        this.moveTile(index)
      }
    })
    .transition(this.updateAnim(index))
  }

  @Builder
  StatsGrid() {
    Row({ space: 8 }) {
      this.StatCard($r('sys.symbol.clock'), '时间', true)
      this.StatCard($r('sys.symbol.hand_draw'), '步数', false)
    }
    .width('100%')
  }

  @Builder
  StatCard(icon: Resource, label: string, isTime: boolean) {
    Column({ space: 4 }) {
      Row({ space: 4 }) {
        SymbolGlyph(icon)
          .fontSize(11)
          .fontColor([$r('app.color.text_tertiary')])
        Text(label)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')

      Text(isTime ? this.formatTime(this.elapsedSeconds) : `${this.moveCount}`)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ top: 2 })

      Text(this.formatBestSubline(isTime))
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
    }
    .layoutWeight(1)
    .padding(10)
    .backgroundColor(this.getStatCardBackgroundColor())
    .borderRadius(10)
    .border({
      width: 1,
      color: this.getStatCardBorderColor(),
      style: BorderStyle.Solid
    })
    .animation({ duration: 600, curve: Curve.EaseInOut })
  }

  @Builder
  ActionRow() {
    Row() {
      Blank()
      if (!this.hasWon && !this.isAnswered && !this.isCompleted) {
        Text('放弃本局')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .padding(8)
          .onClick(() => this.handleGiveUp())
      }
    }
    .width('100%')
  }
}
