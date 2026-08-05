/**
 * SudokuCard - 数独互动卡片
 *
 * 设计升级 (镜像 NumberPuzzleCard v2 Premium Tactile):
 * - 棋盘: givens 加粗主题色 / 用户填入常规色 / 冲突格红色高亮
 * - 子盒分隔: 跨子盒边界用加粗 divider, 同盒内用细 divider
 * - 软实时验证: 填入即检查行/列/盒冲突 (规则层, 不泄底解)
 * - 数字键盘: 1-N + 擦除, 按下 scale(0.94) 反馈
 * - 计时/错误: 双卡片网格 + 最佳成绩 (持久化到 PreferencesService)
 * - 完成态: 庆祝横幅 + 行扫描高亮 + 新纪录徽章
 *
 * 公共 API 与 NumberPuzzleCard 一致: toolCall / isAnswered / answeredPayload / largeSize / onAnswer.
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { getPreferencesService, PreferenceKeys } from '../services/PreferencesService'
import {
  SudokuBoard,
  getDifficultyConfig,
  getConflicts,
  isBoardComplete,
  mergeBoard,
  reconstructBoardFromPayload,
  gridSizeLabel
} from '../utils/SudokuGenerator'

export interface SudokuResult {
  difficulty: number
  grid_size: string
  time_seconds: number
  mistake_count: number
  completed: boolean
}

interface SudokuArgsParsed {
  difficulty: number
  size: number
  boxRows: number
  boxCols: number
  givens: number[]
  solution: number[]
}

@ComponentV2
export struct SudokuCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local difficulty: number = 1
  @Local gridSize: number = 4
  @Local boxRows: number = 2
  @Local boxCols: number = 2
  @Local givens: number[] = []
  @Local solution: number[] = []
  @Local userInputs: number[] = []
  @Local conflicts: number[] = []
  @Local selectedCellIndex: number = -1
  @Local mistakeCount: number = 0
  @Local startTime: number = 0
  @Local elapsedSeconds: number = 0
  @Local isCompleted: boolean = false
  @Local hasWon: boolean = false
  @Local bestTimeSeconds: number = -1
  @Local bestMistakes: number = -1
  @Local isNewBest: boolean = false
  @Local bestScoresLoaded: boolean = false
  @Local winPopIndex: number = -1
  @Local isGenerating: boolean = true

  private timerId: number = -1
  private winPopTimerId: number = -1
  private readonly SUCCESS_GREEN: string = '#22C55E'
  private readonly CONFLICT_RED: string = '#EF4444'

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get cellSize(): number {
    if (this.largeSize) {
      switch (this.gridSize) {
        case 4: return 76
        case 6: return 54
        case 9: return 38
        default: return 54
      }
    }
    switch (this.gridSize) {
      case 4: return 60
      case 6: return 42
      case 9: return 28
      default: return 42
    }
  }

  private get cellGap(): number {
    return 0
  }

  private get totalWidth(): number {
    return this.cellSize * this.gridSize
  }

  private get digitFontSize(): number {
    return Math.floor(this.cellSize * 0.5)
  }

  private get difficultyLabel(): string {
    switch (this.difficulty) {
      case 1: return '幼儿 · 4×4'
      case 2: return '进阶 · 6×6'
      case 3: return '简单 · 9×9'
      case 4: return '中等 · 9×9'
      case 5: return '挑战 · 9×9'
      default: return gridSizeLabel(this.difficulty)
    }
  }

  aboutToAppear(): void {
    const parsed = this.parseArgs()
    if (parsed !== null) {
      this.difficulty = parsed.difficulty
      this.gridSize = parsed.size
      this.boxRows = parsed.boxRows
      this.boxCols = parsed.boxCols
      this.givens = parsed.givens
      this.solution = parsed.solution
      this.isGenerating = false
    }
    if (this.isAnswered) {
      this.parsePreviousResult()
    } else if (parsed !== null) {
      this.startGame()
    }
    this.loadBestScores(this.difficulty)
  }

  aboutToDisappear(): void {
    this.stopTimer()
    if (this.winPopTimerId >= 0) {
      clearTimeout(this.winPopTimerId)
      this.winPopTimerId = -1
    }
  }

  private parseArgs(): SudokuArgsParsed | null {
    try {
      const parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      const difficulty = Math.max(1, Math.min(5, (parsed['difficulty'] as number) ?? 1))
      const cfg = getDifficultyConfig(difficulty)
      const size = (parsed['size'] as number) ?? cfg.size
      const boxRows = (parsed['box_rows'] as number) ?? cfg.boxRows
      const boxCols = (parsed['box_cols'] as number) ?? cfg.boxCols
      const givensRaw = parsed['givens']
      const solutionRaw = parsed['solution']
      const givens: number[] = []
      const solution: number[] = []
      const total = size * size
      if (givensRaw instanceof Array) {
        for (let i = 0; i < total; i++) {
          const v = (givensRaw as Object[])[i]
          givens.push(typeof v === 'number' ? v as number : 0)
        }
      } else {
        return null
      }
      if (solutionRaw instanceof Array) {
        for (let i = 0; i < total; i++) {
          const v = (solutionRaw as Object[])[i]
          solution.push(typeof v === 'number' ? v as number : 0)
        }
      }
      return { difficulty, size, boxRows, boxCols, givens, solution }
    } catch (_e) {
      return null
    }
  }

  private parsePreviousResult(): void {
    if (this.answeredPayload === '') {
      return
    }
    try {
      const result = JSON.parse(this.answeredPayload) as SudokuResult
      this.difficulty = Math.max(1, Math.min(5, result.difficulty))
      this.isCompleted = true
      this.hasWon = result.completed
      this.mistakeCount = result.mistake_count
      this.elapsedSeconds = Math.floor(result.time_seconds)
      // 还原棋盘 (只读视图)
      const restored = reconstructBoardFromPayload(this.answeredPayload, this.toolCall.arguments)
      if (restored !== null) {
        this.givens = restored.givens
        this.userInputs = restored.userInputs
        this.gridSize = restored.size
        this.boxRows = restored.boxRows
        this.boxCols = restored.boxCols
      }
    } catch (_e) {
      // ignore parse failure
    }
  }

  private async loadBestScores(difficulty: number): Promise<void> {
    try {
      const prefs = getPreferencesService()
      const timeKey = `${PreferenceKeys.SUDOKU_BEST_TIME_PREFIX}${difficulty}`
      const mistakesKey = `${PreferenceKeys.SUDOKU_BEST_MISTAKES_PREFIX}${difficulty}`
      this.bestTimeSeconds = await prefs.getNumber(timeKey, -1)
      this.bestMistakes = await prefs.getNumber(mistakesKey, -1)
      this.bestScoresLoaded = true
    } catch (_e) {
      this.bestTimeSeconds = -1
      this.bestMistakes = -1
      this.bestScoresLoaded = true
    }
  }

  private async saveBestScoresIfImproved(): Promise<void> {
    if (!this.bestScoresLoaded) {
      return
    }
    try {
      const prefs = getPreferencesService()
      const timeKey = `${PreferenceKeys.SUDOKU_BEST_TIME_PREFIX}${this.difficulty}`
      const mistakesKey = `${PreferenceKeys.SUDOKU_BEST_MISTAKES_PREFIX}${this.difficulty}`
      const isNewBestTime = this.bestTimeSeconds < 0 || this.elapsedSeconds < this.bestTimeSeconds
      const isNewBestMistakes = this.bestMistakes < 0 || this.mistakeCount < this.bestMistakes
      if (isNewBestTime) {
        await prefs.setNumber(timeKey, this.elapsedSeconds)
        this.bestTimeSeconds = this.elapsedSeconds
      }
      if (isNewBestMistakes) {
        await prefs.setNumber(mistakesKey, this.mistakeCount)
        this.bestMistakes = this.mistakeCount
      }
      this.isNewBest = isNewBestTime || isNewBestMistakes
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

  private startGame(): void {
    this.isCompleted = false
    this.hasWon = false
    this.isNewBest = false
    this.mistakeCount = 0
    this.selectedCellIndex = -1
    this.conflicts = []
    const total = this.gridSize * this.gridSize
    const inputs: number[] = []
    for (let i = 0; i < total; i++) {
      inputs.push(0)
    }
    this.userInputs = inputs
    this.startTime = Date.now()
    this.elapsedSeconds = 0
    this.startTimer()
  }

  private isGiven(index: number): boolean {
    return this.givens.length > index && this.givens[index] !== 0
  }

  private getCellValue(index: number): number {
    if (this.isGiven(index)) {
      return this.givens[index]
    }
    return this.userInputs.length > index ? this.userInputs[index] : 0
  }

  private isConflict(index: number): boolean {
    for (let i = 0; i < this.conflicts.length; i++) {
      if (this.conflicts[i] === index) {
        return true
      }
    }
    return false
  }

  private isSelected(index: number): boolean {
    return this.selectedCellIndex === index
  }

  private mergedView(): number[] {
    return mergeBoard({
      size: this.gridSize,
      boxRows: this.boxRows,
      boxCols: this.boxCols,
      difficulty: this.difficulty,
      givens: this.givens,
      solution: this.solution,
      userInputs: this.userInputs
    })
  }

  private recomputeConflicts(): void {
    this.conflicts = getConflicts(this.mergedView(), this.gridSize, this.boxRows, this.boxCols)
  }

  private handleCellTap(index: number): void {
    if (this.isCompleted || this.isAnswered) {
      return
    }
    if (this.isGiven(index)) {
      // 已知格不可编辑, 点选仅作高亮提示
      this.selectedCellIndex = -1
      return
    }
    this.selectedCellIndex = index
  }

  private handleDigit(digit: number): void {
    if (this.isCompleted || this.isAnswered) {
      return
    }
    if (this.selectedCellIndex < 0) {
      return
    }
    const idx = this.selectedCellIndex
    if (this.isGiven(idx)) {
      return
    }
    if (digit < 1 || digit > this.gridSize) {
      return
    }
    const old = this.userInputs.length > idx ? this.userInputs[idx] : 0
    if (old === digit) {
      // 同值再按 = 擦除
      const inputs: number[] = [...this.userInputs]
      inputs[idx] = 0
      this.userInputs = inputs
      this.recomputeConflicts()
      this.advanceSelection()
      return
    }
    const inputs: number[] = [...this.userInputs]
    inputs[idx] = digit
    this.userInputs = inputs
    // 检查本次填入是否引入冲突; 若该格在冲突列表中, mistake +1
    const beforeConflicts = this.conflicts.length
    this.recomputeConflicts()
    if (this.isConflict(idx) && beforeConflicts !== this.conflicts.length) {
      // 新冲突出现 — 仅当该格现在在冲突列表中且之前不在 (粗略 mistake 计数)
      this.mistakeCount += 1
    } else if (this.isConflict(idx)) {
      // 该格仍冲突 (原来也冲突) — 不重复计数, 避免同一格多次扣
      // no-op
    }
    this.evaluateWin()
    if (!this.isCompleted) {
      this.advanceSelection()
    }
  }

  private handleErase(): void {
    if (this.isCompleted || this.isAnswered) {
      return
    }
    if (this.selectedCellIndex < 0) {
      return
    }
    const idx = this.selectedCellIndex
    if (this.isGiven(idx)) {
      return
    }
    const inputs: number[] = [...this.userInputs]
    inputs[idx] = 0
    this.userInputs = inputs
    this.recomputeConflicts()
  }

  private advanceSelection(): void {
    // 自动跳到下一个空格 (优先同行右侧, 再下一行)
    const start = this.selectedCellIndex
    if (start < 0) {
      return
    }
    const total = this.gridSize * this.gridSize
    for (let step = 1; step <= total; step++) {
      const next = (start + step) % total
      if (!this.isGiven(next) && this.getCellValue(next) === 0) {
        this.selectedCellIndex = next
        return
      }
    }
    // 没有空格了, 保持当前选中
  }

  private evaluateWin(): void {
    const merged = this.mergedView()
    if (!isBoardComplete(merged, this.gridSize, this.boxRows, this.boxCols)) {
      return
    }
    this.isCompleted = true
    this.hasWon = true
    this.stopTimer()
    const timeMs = Date.now() - this.startTime
    const timeSeconds = Number((timeMs / 1000).toFixed(1))
    this.elapsedSeconds = Math.floor(timeSeconds)
    this.selectedCellIndex = -1

    this.triggerWinPop()

    const result: SudokuResult = {
      difficulty: this.difficulty,
      grid_size: `${this.gridSize}×${this.gridSize}`,
      time_seconds: timeSeconds,
      mistake_count: this.mistakeCount,
      completed: true
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
    this.saveBestScoresIfImproved()
  }

  private triggerWinPop(): void {
    if (this.winPopTimerId >= 0) {
      clearTimeout(this.winPopTimerId)
      this.winPopTimerId = -1
    }
    const total = this.gridSize * this.gridSize
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
    const result: SudokuResult = {
      difficulty: this.difficulty,
      grid_size: `${this.gridSize}×${this.gridSize}`,
      time_seconds: 0,
      mistake_count: this.mistakeCount,
      completed: false
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
  }

  private formatTime(seconds: number): string {
    const m = Math.floor(seconds / 60)
    const s = seconds % 60
    const sStr = s < 10 ? `0${s}` : `${s}`
    return `${m}:${sStr}`
  }

  private formatBestTime(): string {
    return this.bestTimeSeconds < 0 ? ' ' : `最佳 ${this.formatTime(this.bestTimeSeconds)}`
  }

  private formatBestMistakes(): string {
    return this.bestMistakes < 0 ? ' ' : `最佳 ${this.bestMistakes}`
  }

  private getCellBackground(index: number): string {
    if (this.isConflict(index)) {
      return withColorAlpha(this.CONFLICT_RED, '20')
    }
    if (this.isSelected(index)) {
      return withColorAlpha(this.themePrimary, '30')
    }
    if (this.isGiven(index)) {
      return withColorAlpha(this.themePrimary, this.isDarkMode ? '10' : '08')
    }
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '06' : '04')
  }

  private getCellTextColor(index: number): string {
    if (this.isConflict(index)) {
      return this.CONFLICT_RED
    }
    if (this.isGiven(index)) {
      return this.themePrimary
    }
    return this.isDarkMode ? '#F5F5F5' : '#1F1F1F'
  }

  // 子盒边界: 该格是否在子盒右边缘 (需要加粗右边框)
  private isBoxRightEdge(index: number): boolean {
    const col = index % this.gridSize
    return (col + 1) % this.boxCols === 0 && col !== this.gridSize - 1
  }

  private isBoxBottomEdge(index: number): boolean {
    const row = Math.floor(index / this.gridSize)
    return (row + 1) % this.boxRows === 0 && row !== this.gridSize - 1
  }

  private isExternalRightEdge(index: number): boolean {
    const col = index % this.gridSize
    return col === this.gridSize - 1
  }

  private isExternalBottomEdge(index: number): boolean {
    const row = Math.floor(index / this.gridSize)
    return row === this.gridSize - 1
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
      Column() {
        SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
          .fontSize(15)
          .fontColor([this.themePrimary])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(withColorAlpha(this.themePrimary, '18'))
      .justifyContent(FlexAlign.Center)

      Column() {
        Text('数独')
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
      .layoutWeight(1)

      if (this.isCompleted) {
        Text(this.hasWon ? '已完成' : '已放弃')
          .fontSize(10)
          .fontColor(this.hasWon ? $r('app.color.status_success') : Color.White)
          .backgroundColor(this.hasWon
            ? withColorAlpha(this.SUCCESS_GREEN, this.isDarkMode ? '20' : '14')
            : withColorAlpha('#FF9F43', this.isDarkMode ? '20' : '14'))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(10)
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  WinBanner() {
    Row() {
      Text('🎉')
        .fontSize(26)
        .margin({ right: 8 })

      Column() {
        Text('太棒了！填好了')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.status_success'))
        Text(`${this.formatTime(this.elapsedSeconds)} · ${this.mistakeCount} 错`)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.isNewBest) {
        Text('新纪录')
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor(this.SUCCESS_GREEN)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(10)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(withColorAlpha(this.SUCCESS_GREEN, this.isDarkMode ? '18' : '0C'))
    .borderRadius(12)
    .border({ width: 1, color: withColorAlpha(this.SUCCESS_GREEN, this.isDarkMode ? '38' : '28'), style: BorderStyle.Solid })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  BoardPanel() {
    Column({ space: 12 }) {
      if (this.isGenerating) {
        // 生成中占位 (handleSudoku 同步生成, 正常路径不会停留; 仅防御性兜底)
        Column() {
          Text('数独生成中...')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width(this.totalWidth)
        .height(this.totalWidth)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        // 棋盘
        Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row }) {
          ForEach(this.cellIndices(), (index: number) => {
            this.CellView(index)
          }, (index: number) => `${index}`)
        }
        .width(this.totalWidth)
        .padding(0)
        .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '0A' : '06'))
        .borderRadius(8)

        // 数字键盘
        this.NumberPad()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  private cellIndices(): number[] {
    const total = this.gridSize * this.gridSize
    const arr: number[] = []
    for (let i = 0; i < total; i++) {
      arr.push(i)
    }
    return arr
  }

  @Builder
  CellView(index: number) {
    Stack() {
      if (this.getCellValue(index) !== 0) {
        Text(`${this.getCellValue(index)}`)
          .fontSize(this.digitFontSize)
          .fontWeight(this.isGiven(index) ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.getCellTextColor(index))
      }
      // Win Pop 边框
      if (this.hasWon && !this.isAnswered && this.winPopIndex >= 0 && index <= this.winPopIndex) {
        Column()
          .width('100%')
          .height('100%')
          .borderRadius(4)
          .border({ width: 2, color: this.SUCCESS_GREEN, style: BorderStyle.Solid })
      }
    }
    .width(this.cellSize)
    .height(this.cellSize)
    .backgroundColor(this.getCellBackground(index))
    .borderRadius(0)
    .border({
      width: {
        top: 0.5,
        bottom: this.isExternalBottomEdge(index) ? 1.5 : (this.isBoxBottomEdge(index) ? 1.5 : 0.5),
        left: 0.5,
        right: this.isExternalRightEdge(index) ? 1.5 : (this.isBoxRightEdge(index) ? 1.5 : 0.5)
      },
      color: this.isDarkMode ? '#5A5A5A' : '#B5B5B5',
      style: BorderStyle.Solid
    })
    .onClick(() => this.handleCellTap(index))
  }

  @Builder
  NumberPad() {
    Flex({ wrap: FlexWrap.Wrap, direction: FlexDirection.Row, justifyContent: FlexAlign.SpaceEvenly }) {
      ForEach(this.padDigits(), (d: number) => {
        this.DigitKey(d)
      }, (d: number) => `${d}`)
    }
    .width(this.totalWidth)
  }

  private padDigits(): number[] {
    // 1..size, 最后一个值 -1 表示「擦除」键
    const arr: number[] = []
    for (let i = 1; i <= this.gridSize; i++) {
      arr.push(i)
    }
    arr.push(-1)
    return arr
  }

  @Builder
  DigitKey(digit: number) {
    if (digit === -1) {
      // 擦除键
      Column() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(20)
          .fontColor([$r('app.color.text_primary')])
      }
      .width(this.padKeySize())
      .height(this.padKeySize())
      .borderRadius(8)
      .backgroundColor(this.themeAiBubble)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => this.handleErase())
    } else {
      Column() {
        Text(`${digit}`)
          .fontSize(Math.floor(this.padKeySize() * 0.45))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
      .width(this.padKeySize())
      .height(this.padKeySize())
      .borderRadius(8)
      .backgroundColor(this.themeAiBubble)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => this.handleDigit(digit))
    }
  }

  private padKeySize(): number {
    const count = this.gridSize + 1 // 1..size + 擦除
    const gap = 6
    const total = this.totalWidth - gap * (count - 1)
    return Math.max(32, Math.floor(total / count))
  }

  @Builder
  StatsGrid() {
    Row({ space: 8 }) {
      Column() {
        this.StatCard(true)
      }
      .layoutWeight(1)

      Column() {
        this.StatCard(false)
      }
      .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  StatCard(isTime: boolean) {
    Column() {
      Row() {
        Text(isTime ? '⏱' : '✗')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text(isTime ? ' 时间' : ' 错误')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }

      Text(isTime ? this.formatTime(this.elapsedSeconds) : `${this.mistakeCount}`)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 4 })

      Text(isTime ? this.formatBestTime() : this.formatBestMistakes())
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 2 })
    }
    .width('100%')
    .padding(10)
    .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '10' : '08'))
    .borderRadius(10)
    .border({
      width: 1,
      color: this.isNewBest
        ? withColorAlpha(this.SUCCESS_GREEN, '60')
        : withColorAlpha(this.themePrimary, this.isDarkMode ? '22' : '18'),
      style: BorderStyle.Solid
    })
    .animation({ duration: 600, curve: Curve.EaseInOut })
  }

  @Builder
  ActionRow() {
    Row() {
      if (!this.hasWon && !this.isAnswered && !this.isCompleted) {
        Text('放弃本局')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .padding({ left: 8, right: 8, top: 8, bottom: 8 })
          .onClick(() => this.handleGiveUp())
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
  }
}
