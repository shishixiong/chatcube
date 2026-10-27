// entry/src/main/ets/components/map/MapPuzzleCard.ets
/**
 * MapPuzzleCard - 中国地图拼图（map_puzzle, spec 2026-10-26 §9.2）
 *
 * 一局 3-8 块省份碎片：从托盘拖到地图上（或「点碎片 → 点地图」）拼回中国。
 * 棋盘自动聚焦本局省份；拼对朗读「省名 / 简称 / 省会」，拼错回弹并计数；
 * 全部拼完按错误次数授 1-3 星并回执（不进讲解课那种「我学会了」，拼完即完成）。
 *
 * 大尺寸（全屏 sheet）：表头 + 棋盘卡 + 托盘卡 + 页脚；拖拽层压在整卡之上。
 * 小尺寸（时间线内联复原）：紧凑棋盘 + 成绩行，不可交互。
 */

import common from '@ohos.app.ability.common'
import { getAppUiState } from '../../state/AppUiState'
import { ToolCall } from '../../models/ChatModels'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { ChinaMapData, ChinaProvince, loadChinaMapData } from '../../utils/ChinaMapData'
import { parseProvincePolygons, provinceBBox } from '../../utils/ChinaMapGeometry'
import { createFitTransform, MapTransform } from '../../utils/ChinaMapTransform'
import {
  computePuzzleTransform,
  layoutTray,
  resolveDrop,
  trayRows
} from '../../utils/MapPuzzleLayout'
import {
  MapPuzzleArgsView,
  parseMapPuzzleArgs,
  resolvePuzzleProvinces
} from '../../utils/MapPuzzleValidation'
import { CardShell } from '../cardshell/CardShell'
import { CardShellConfig } from '../cardshell/CardShellTypes'
import { CardShellState } from '../cardshell/CardShellState'
import { getMapAtlasPalette, MapAtlasPalette } from './MapAtlasTokens'
import { MapPuzzleBoard } from './MapPuzzleBoard'

export interface MapPuzzleResult {
  completed: boolean
  mode: string
  region: string
  total: number
  placed: number
  mistakes: number
  hints: number
  time_seconds: number
  stars: number
  provinces: string[]
  /** 错放过的省份简称（去重）：台账按省对账，拼图一局多省必须分开记 */
  wrong_provinces: string[]
  skill_key: string
  cancelled?: boolean
}

/** 碎片边长与间距（vp） */
const PIECE_SIZE: number = 56
const PIECE_GAP: number = 8
const TRAY_PAD_X: number = 12
const TRAY_PAD_Y: number = 10
/** 拖动中的浮层比托盘碎片略大，跟手时更明显 */
const DRAG_PIECE_SIZE: number = 64
/** 完成后再等一小会儿，让最后一块的吸附动画播完 */
const COMPLETE_DELAY_MS: number = 620

@ComponentV2
export struct MapPuzzleCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
  @Event onRequestClose: () => void = () => {}

  @Local data: ChinaMapData | null = null
  @Local targets: ChinaProvince[] = []
  @Local placedIds: string[] = []
  @Local selectedId: string = ''
  @Local hintId: string = ''
  @Local hintSeq: number = 0
  @Local mistakes: number = 0
  @Local hints: number = 0
  @Local elapsed: number = 0
  @Local started: boolean = false
  @Local submitted: boolean = false
  @Local restoredResult: string = ''
  @Local trayWidth: number = 0
  @Local shakeX: number = 0
  @Local statusText: string = ''
  @Local dragActive: boolean = false
  @Local dragX: number = 0
  @Local dragY: number = 0

  private argsView: MapPuzzleArgsView = parseMapPuzzleArgs('')
  private timerId: number = -1
  private speakSeq: number = 0
  private pieceContexts: Map<string, CanvasRenderingContext2D> = new Map()
  private dragProvince: ChinaProvince | null = null
  /** 长按提示计时器（600ms 未移动 = 想看这块在哪儿） */
  private hintTimerId: number = -1
  /** 错放过的省份（简称，去重）：进回执 wrong_provinces */
  private wrongShorts: string[] = []
  private grabX: number = 0
  private grabY: number = 0
  private dragStartX: number = 0
  private dragStartY: number = 0
  private rootOffsetX: number = 0
  private rootOffsetY: number = 0
  private boardOffsetX: number = 0
  private boardOffsetY: number = 0
  private boardW: number = 0
  private boardH: number = 0
  private shellState: CardShellState = new CardShellState()
  private shellConfig: CardShellConfig = {
    title: '中国地图拼图', subtitle: '把省份拼回地图', icon: $r('sys.symbol.puzzle'),
    stem: '', hasAudio: false, usesConfirm: false,
    feedbackTitleCorrect: '拼好啦！', correctAnswerLabel: ''
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get palette(): MapAtlasPalette {
    return getMapAtlasPalette(this.isDarkMode)
  }

  private get total(): number {
    return this.targets.length
  }

  private get placedCount(): number {
    return this.placedIds.length
  }

  private get isFinished(): boolean {
    return this.total > 0 && this.placedCount >= this.total
  }

  /** 托盘每行几块：按实测宽度自适应，最少 2 块一行 */
  private get perRow(): number {
    if (this.trayWidth <= 0) {
      return 4
    }
    const usable = this.trayWidth - TRAY_PAD_X * 2
    const fit = Math.floor((usable + PIECE_GAP) / (PIECE_SIZE + PIECE_GAP))
    return Math.max(2, fit)
  }

  private get trayHeight(): number {
    const rows = trayRows(this.targets.length, this.perRow)
    return rows * PIECE_SIZE + (rows - 1) * PIECE_GAP
  }

  private get stars(): number {
    if (!this.isFinished) {
      return 0
    }
    return this.mistakes <= 1 ? 3 : (this.mistakes <= 3 ? 2 : 1)
  }

  aboutToAppear(): void {
    this.argsView = parseMapPuzzleArgs(this.toolCall.arguments)
    this.shellState.feedbackSuppressed = true
    if (this.argsView.region !== '') {
      this.shellConfig.subtitle = `拼一拼${this.argsView.region}`
    }
    if (this.isAnswered) {
      this.restoreFromPayload()
    }
    const ctx = getContext(this) as common.UIAbilityContext
    loadChinaMapData(ctx).then((loaded: ChinaMapData | null) => {
      if (loaded === null) {
        return
      }
      this.data = loaded
      this.targets = resolvePuzzleProvinces(loaded.provinces, this.argsView)
      this.applyRestoredProgress()
      if (this.largeSize && !this.isAnswered && this.targets.length > 0) {
        this.startTimer()
      }
    }).catch((_e: Error) => {
    })
  }

  aboutToDisappear(): void {
    this.stopTimer()
    this.cancelHintTimer()
    this.stopSpeech()
  }

  // ====== 状态 ======

  private restoreFromPayload(): void {
    if (this.answeredPayload.trim() === '') {
      return
    }
    this.restoredResult = this.answeredPayload
  }

  private applyRestoredProgress(): void {
    if (this.restoredResult === '') {
      return
    }
    try {
      const obj = JSON.parse(this.restoredResult) as Record<string, Object>
      const placed: Object | undefined = obj['placed']
      if (typeof placed === 'number') {
        const count = placed as number
        const ids: string[] = []
        for (let i = 0; i < this.targets.length && i < count; i++) {
          ids.push(this.targets[i].id)
        }
        this.placedIds = ids
      }
      const mistakes: Object | undefined = obj['mistakes']
      if (typeof mistakes === 'number') {
        this.mistakes = mistakes as number
      }
      const seconds: Object | undefined = obj['time_seconds']
      if (typeof seconds === 'number') {
        this.elapsed = seconds as number
      }
    } catch (_e) {
      this.restoredResult = ''
    }
  }

  private startTimer(): void {
    if (this.timerId >= 0) {
      return
    }
    this.started = true
    this.timerId = setInterval(() => {
      if (this.isFinished || this.submitted) {
        return
      }
      this.elapsed += 1
    }, 1000)
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  private formatTime(seconds: number): string {
    const m = Math.floor(seconds / 60)
    const s = seconds % 60
    const ss = s < 10 ? `0${s}` : `${s}`
    return `${m}:${ss}`
  }

  // ====== 朗读 ======

  private speak(text: string): void {
    this.speakSeq = this.speakSeq + 1
    const seq = this.speakSeq
    try {
      ServiceRegistry.tts().speak(text, {
        onStart: () => {},
        onComplete: () => {},
        onError: (error: string) => {
          if (seq !== this.speakSeq) {
            return
          }
          console.error('MapPuzzleCard', `tts error: ${error}`)
        }
      }).catch((e: Error) => {
        console.error('MapPuzzleCard', `tts speak failed: ${e.message}`)
      })
    } catch (_e) {
    }
  }

  private stopSpeech(): void {
    try {
      ServiceRegistry.tts().stop()
    } catch (_e) {
    }
  }

  // ====== 玩法 ======

  private attemptPlace(province: ChinaProvince, boardX: number, boardY: number): void {
    if (this.isFinished || this.submitted) {
      return
    }
    if (this.placedIds.indexOf(province.id) >= 0) {
      return
    }
    const transform = computePuzzleTransform(this.targets, this.boardW, this.boardH)
    const result = resolveDrop(province, this.targets, transform, boardX, boardY)
    if (result.correct) {
      this.markPlaced(province)
    } else {
      this.registerMistake(province)
    }
  }

  private markPlaced(province: ChinaProvince): void {
    if (this.selectedId === province.id) {
      this.selectedId = ''
    }
    this.hintId = ''
    const next: string[] = this.placedIds.slice()
    next.push(province.id)
    this.placedIds = next
    this.statusText = `${province.short} 拼好啦`
    this.speak(`${province.name}，简称${province.abbr}，行政中心${province.capital}。`)
    if (next.length >= this.total && this.total > 0) {
      this.finishRound()
    }
  }

  private registerMistake(province: ChinaProvince): void {
    this.mistakes += 1
    if (this.wrongShorts.indexOf(province.short) < 0) {
      this.wrongShorts.push(province.short)
    }
    this.statusText = `再找找，「${province.short}」不在那儿`
    this.speak(`再找找看，${province.short}在哪儿呢？`)
    this.playShake()
  }

  private playShake(): void {
    const uiContext = this.getUIContext()
    const steps: number[] = [6, -6, 4, -4, 0]
    for (let i = 0; i < steps.length; i++) {
      setTimeout(() => {
        try {
          uiContext.animateTo({ duration: 70, curve: Curve.Sharp }, () => {
            this.shakeX = steps[i]
          })
        } catch (_e) {
        }
      }, i * 70)
    }
  }

  private finishRound(): void {
    this.stopTimer()
    this.submitted = true
    this.statusText = '全部拼好啦！'
    this.speak('都拼好啦！你真棒。')
    setTimeout(() => {
      try {
        this.onAnswer(this.toolCall.id, JSON.stringify(this.buildResult(true)))
      } catch (_e) {
      }
    }, COMPLETE_DELAY_MS)
  }

  private buildResult(completed: boolean): MapPuzzleResult {
    const names: string[] = []
    for (const p of this.targets) {
      names.push(p.short)
    }
    const result: MapPuzzleResult = {
      completed: completed,
      mode: this.argsView.mode,
      region: this.argsView.region,
      total: this.total,
      placed: this.placedCount,
      mistakes: this.mistakes,
      hints: this.hints,
      time_seconds: this.elapsed,
      stars: completed ? this.stars : 0,
      provinces: names,
      wrong_provinces: this.wrongShorts,
      skill_key: this.argsView.skillKey
    }
    return result
  }

  private restart(): void {
    this.placedIds = []
    this.selectedId = ''
    this.hintId = ''
    this.cancelHintTimer()
    this.wrongShorts = []
    this.mistakes = 0
    this.hints = 0
    this.elapsed = 0
    this.statusText = ''
    this.submitted = false
    this.stopSpeech()
    this.startTimer()
  }

  // ====== 点击 / 拖拽 ======

  private measureRects(): void {
    try {
      const uiContext = this.getUIContext()
      const root = uiContext.getComponentUtils().getRectangleById('mapPuzzleRoot')
      const board = uiContext.getComponentUtils().getRectangleById('mapPuzzleBoard')
      this.rootOffsetX = uiContext.px2vp(root.windowOffset.x)
      this.rootOffsetY = uiContext.px2vp(root.windowOffset.y)
      this.boardOffsetX = uiContext.px2vp(board.windowOffset.x) - this.rootOffsetX
      this.boardOffsetY = uiContext.px2vp(board.windowOffset.y) - this.rootOffsetY
      this.boardW = uiContext.px2vp(board.size.width)
      this.boardH = uiContext.px2vp(board.size.height)
    } catch (_e) {
      this.boardW = 0
      this.boardH = 0
    }
  }

  private handlePieceDown(province: ChinaProvince, event: TouchEvent): void {
    if (this.isFinished || this.isAnswered) {
      return
    }
    if (this.placedIds.indexOf(province.id) >= 0 || event.touches.length === 0) {
      return
    }
    const touch = event.touches[0]
    this.measureRects()
    this.dragProvince = province
    this.grabX = touch.x
    this.grabY = touch.y
    this.dragStartX = touch.windowX
    this.dragStartY = touch.windowY
    this.dragActive = true
    this.selectedId = province.id
    this.updateDragPosition(touch.windowX, touch.windowY)
    this.scheduleHint(province)
  }

  /** 长按 600ms 没移动：把这块的凹槽呼吸三下（记一次提示） */
  private scheduleHint(province: ChinaProvince): void {
    this.cancelHintTimer()
    this.hintTimerId = setTimeout(() => {
      this.hintTimerId = -1
      if (!this.dragActive || this.dragProvince === null) {
        return
      }
      if (this.dragProvince.id !== province.id) {
        return
      }
      this.hints += 1
      this.hintId = province.id
      this.hintSeq += 1
      this.statusText = `「${province.short}」在这附近，看棋盘高亮`
      this.speak(`${province.short}在这附近，看这里。`)
    }, 600)
  }

  private cancelHintTimer(): void {
    if (this.hintTimerId >= 0) {
      clearTimeout(this.hintTimerId)
      this.hintTimerId = -1
    }
  }

  private updateDragPosition(windowX: number, windowY: number): void {
    this.dragX = windowX - this.rootOffsetX - this.grabX
    this.dragY = windowY - this.rootOffsetY - this.grabY
  }

  private handlePieceMove(event: TouchEvent): void {
    if (!this.dragActive || event.touches.length === 0) {
      return
    }
    const touch = event.touches[0]
    this.cancelHintTimer()
    this.updateDragPosition(touch.windowX, touch.windowY)
  }

  private handlePieceUp(event: TouchEvent): void {
    this.cancelHintTimer()
    const province = this.dragProvince
    this.dragActive = false
    this.dragProvince = null
    if (province === null || event.changedTouches.length === 0) {
      return
    }
    const touch = event.changedTouches[0]
    const moved = Math.abs(touch.windowX - this.dragStartX) + Math.abs(touch.windowY - this.dragStartY)
    if (moved < 12) {
      // 视为轻点：选中，等孩子点地图
      this.selectedId = province.id
      this.statusText = `把「${province.short}」放到地图上`
      return
    }
    if (this.boardW <= 0 || this.boardH <= 0) {
      return
    }
    const boardX = touch.windowX - this.rootOffsetX - this.boardOffsetX
    const boardY = touch.windowY - this.rootOffsetY - this.boardOffsetY
    if (boardX < 0 || boardY < 0 || boardX > this.boardW || boardY > this.boardH) {
      // 丢到棋盘外：直接回弹，不算错
      this.statusText = ''
      return
    }
    this.attemptPlace(province, boardX, boardY)
  }

  private handleBoardTap(boardX: number, boardY: number): void {
    if (this.selectedId === '') {
      return
    }
    if (this.boardW <= 0 || this.boardH <= 0) {
      this.measureRects()
    }
    const picked = this.provinceById(this.selectedId)
    if (picked === null) {
      return
    }
    this.attemptPlace(picked, boardX, boardY)
  }

  private provinceById(id: string): ChinaProvince | null {
    for (const p of this.targets) {
      if (p.id === id) {
        return p
      }
    }
    return null
  }

  // ====== 碎片绘制 ======

  private contextFor(id: string): CanvasRenderingContext2D {
    const existing = this.pieceContexts.get(id)
    if (existing !== undefined) {
      return existing
    }
    const created = new CanvasRenderingContext2D(new RenderingContextSettings(true))
    this.pieceContexts.set(id, created)
    return created
  }

  private drawPiece(province: ChinaProvince, size: number): void {
    const ctx = this.contextFor(province.id)
    const palette = this.palette
    const pad = size * 0.09
    ctx.clearRect(0, 0, size, size)
    const transform = createFitTransform(provinceBBox(province.path), size, size, pad)
    // 复用棋盘同一套 path 解析：MapPuzzleBoard 内已缓存，这里按需重算（每块只画一次）
    const rings = provinceRings(province.path)
    if (rings.length === 0) {
      return
    }
    ctx.beginPath()
    for (const ring of rings) {
      for (let i = 0; i < ring.length; i++) {
        const x = ring[i][0] * transform.scale + transform.offsetX
        const y = ring[i][1] * transform.scale + transform.offsetY
        if (i === 0) {
          ctx.moveTo(x, y)
        } else {
          ctx.lineTo(x, y)
        }
      }
      ctx.closePath()
    }
    ctx.fillStyle = palette.land
    ctx.fill('evenodd')
    ctx.strokeStyle = palette.line
    ctx.lineWidth = 1.2
    ctx.stroke()
  }

  private drawDragPiece(): void {
    const province = this.dragProvince
    if (province === null) {
      return
    }
    this.drawPiece(province, DRAG_PIECE_SIZE)
  }

  // ====== UI ======

  @Builder
  LessonHeader() {
    Row() {
      Row({ space: 6 }) {
        Text('地理 · 拼一拼')
          .fontSize(11)
          .fontColor(this.palette.muted)
          .letterSpacing(0.4)
      }
      .layoutWeight(1)

      Text(this.total > 0 ? `已拼 ${this.placedCount}/${this.total}` : '准备中…')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.fg)
    }
    .width('100%')
    // 右侧给 sheet 自带的关闭 X 留位，避免压字
    .padding({ left: 4, right: 40, top: 6, bottom: 2 })
  }

  @Builder
  BoardRegion() {
    Stack() {
      MapPuzzleBoard({
        data: this.data,
        targets: this.targets,
        placedIds: this.placedIds,
        hintId: this.hintId,
        hintSeq: this.hintSeq,
        completed: this.isFinished,
        onBoardTap: (boardX: number, boardY: number): void => {
          this.handleBoardTap(boardX, boardY)
        }
      })
      if (this.isFinished) {
        this.Seal()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.surface)
    .borderRadius(22)
    .clip(true)
    .border({ width: 1, color: this.palette.border })
    .translate({ x: this.shakeX })
  }

  @Builder
  Seal() {
    Column() {
      Text('✓')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.selectedLine)
    }
    .width(62)
    .height(62)
    .borderRadius(31)
    .backgroundColor(withColorAlpha(this.palette.surface, 'E6'))
    .border({ width: 2.5, color: this.palette.selectedLine })
    .justifyContent(FlexAlign.Center)
    .rotate({ angle: -8 })
  }

  @Builder
  TrayRegion() {
    Column() {
      Stack() {
        ForEach(this.targets, (province: ChinaProvince) => {
          this.TrayPiece(province)
        }, (province: ChinaProvince) => province.id)
      }
      .width('100%')
      .height(this.trayHeight)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.trayWidth = Number(newValue.width)
      })
    }
    .width('100%')
    .padding({ left: TRAY_PAD_X, right: TRAY_PAD_X, top: TRAY_PAD_Y, bottom: TRAY_PAD_Y })
    .backgroundColor(this.palette.water)
    .borderRadius(18)
    .border({ width: 1, color: this.palette.border })
  }

  @Builder
  TrayPiece(province: ChinaProvince) {
    Stack() {
      Canvas(this.contextFor(province.id))
        .width(PIECE_SIZE)
        .height(PIECE_SIZE)
        .onReady(() => {
          this.drawPiece(province, PIECE_SIZE)
        })
      Column()
        .width(PIECE_SIZE)
        .height(PIECE_SIZE)
        .borderRadius(14)
        .backgroundColor(this.selectedId === province.id
          ? withColorAlpha(this.palette.selected, '55')
          : Color.Transparent)
        .border({
          width: this.selectedId === province.id ? 1.6 : 0,
          color: this.selectedId === province.id ? this.palette.selectedLine : Color.Transparent
        })
    }
    .width(PIECE_SIZE)
    .height(PIECE_SIZE)
    .position(this.slotPosition(province))
    .visibility(this.placedIds.indexOf(province.id) >= 0 ? Visibility.None : Visibility.Visible)
    .scale({
      x: this.dragActive && this.dragProvince !== null && this.dragProvince.id === province.id ? 0.6 : 1,
      y: this.dragActive && this.dragProvince !== null && this.dragProvince.id === province.id ? 0.6 : 1
    })
    .opacity(this.dragActive && this.dragProvince !== null && this.dragProvince.id === province.id ? 0.35 : 1)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.handlePieceDown(province, event)
      } else if (event.type === TouchType.Move) {
        this.handlePieceMove(event)
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.handlePieceUp(event)
      }
    })
  }

  /** 托盘槽位（按未拼数量顺序排，拼掉的自动补位） */
  private slotPosition(province: ChinaProvince): Position {
    const remaining: ChinaProvince[] = []
    for (const p of this.targets) {
      if (this.placedIds.indexOf(p.id) < 0) {
        remaining.push(p)
      }
    }
    let index = 0
    for (let i = 0; i < remaining.length; i++) {
      if (remaining[i].id === province.id) {
        index = i
        break
      }
    }
    const slots = layoutTray(remaining.length, this.perRow, PIECE_SIZE, PIECE_GAP, 0, 0)
    if (index >= slots.length) {
      const pos: Position = { x: 0, y: 0 }
      return pos
    }
    const pos: Position = { x: slots[index].x, y: slots[index].y }
    return pos
  }

  @Builder
  DragLayer() {
    if (this.dragActive && this.dragProvince !== null) {
      Canvas(this.contextFor(this.dragProvince.id))
        .width(DRAG_PIECE_SIZE)
        .height(DRAG_PIECE_SIZE)
        .position({ x: this.dragX, y: this.dragY })
        .shadow({ radius: 12, color: '#33000000', offsetY: 4 })
        .scale({ x: 1.06, y: 1.06 })
        .onReady(() => {
          this.drawDragPiece()
        })
        .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  StatusLine() {
    Row({ space: 8 }) {
      Text(this.statusText !== '' ? this.statusText
        : (this.isFinished ? '全部拼好啦！' : `还剩 ${this.total - this.placedCount} 块`))
        .fontSize(12)
        .fontColor(this.statusText !== '' ? this.palette.fg : this.palette.muted)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.formatTime(this.elapsed))
        .fontSize(12)
        .fontColor(this.palette.muted)
    }
    .width('100%')
  }

  @Builder
  FooterRegion() {
    Row({ space: 10 }) {
      if (this.isFinished) {
        Row({ space: 4 }) {
          ForEach([1, 2, 3], (star: number) => {
            Text(star <= this.stars ? '⭐️' : '☆')
              .fontSize(14)
          }, (star: number) => `${star}`)
        }
        .layoutWeight(1)
      } else {
        Column() {
          this.StatusLine()
        }
        .layoutWeight(1)
      }

      Row({ space: 4 }) {
        Text('重新开始')
          .fontSize(12)
          .fontColor(this.palette.muted)
        SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
          .fontSize(13)
          .fontColor([this.palette.muted])
      }
      .padding({ left: 10, right: 10, top: 7, bottom: 7 })
      .borderRadius(14)
      .backgroundColor(this.palette.water)
      .onClick(() => {
        this.restart()
      })
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
  }

  @Builder
  InvalidState() {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(28)
        .fontColor([this.palette.muted])
      Text('这一局拼图没能开局')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.fg)
      Text('换个地方再开一局吧')
        .fontSize(12)
        .fontColor(this.palette.muted)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  CompactResult() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.puzzle'))
        .fontSize(15)
        .fontColor([this.palette.muted])
      Text(this.isFinished
        ? `拼好了 ${this.placedCount}/${this.total} · 用时 ${this.formatTime(this.elapsed)}`
        : `这一局没拼完 ${this.placedCount}/${this.total}`)
        .fontSize(12)
        .fontColor(this.palette.fg)
        .layoutWeight(1)
      if (this.isFinished) {
        Text(this.stars >= 3 ? '⭐️⭐️⭐️' : (this.stars === 2 ? '⭐️⭐️' : '⭐️'))
          .fontSize(12)
      }
    }
    .width('100%')
  }

  build() {
    if (!this.argsView.valid) {
      this.InvalidState()
    } else if (this.largeSize) {
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: 10 }) {
          this.LessonHeader()

          Column() {
            this.BoardRegion()
          }
          .width('100%')
          .layoutWeight(1)

          if (!this.isFinished) {
            this.TrayRegion()
          }
          this.FooterRegion()
        }
        .width('100%')
        .height('100%')
        .padding({ left: 2, right: 2, top: 2 })

        this.DragLayer()
      }
      .id('mapPuzzleRoot')
      .width('100%')
      .height('100%')
      .clip(false)
    } else {
      CardShell({
        config: this.shellConfig,
        state: this.shellState,
        isAnswered: this.isAnswered,
        correctAnswerText: '',
        onConfirm: (): void => {},
        onRetry: (): void => {}
      }) {
        Column({ space: 10 }) {
          Column() {
            MapPuzzleBoard({
              data: this.data,
              targets: this.targets,
              placedIds: this.placedIds,
              hintId: '',
              hintSeq: 0,
              completed: this.isFinished,
              onBoardTap: (_x: number, _y: number): void => {}
            })
          }
          .width('100%')
          .height(180)
          .borderRadius(14)
          .clip(true)
          .border({ width: 1, color: this.palette.border })

          this.CompactResult()
        }
        .width('100%')
      }
    }
  }
}

/** 碎片绘制用的环缓存（每块只解析一次） */
const pieceRingCache: Map<string, number[][][]> = new Map()

function provinceRings(path: string): number[][][] {
  const cached = pieceRingCache.get(path)
  if (cached !== undefined) {
    return cached
  }
  const rings = parseProvincePolygons(path)
  pieceRingCache.set(path, rings)
  return rings
}
