/**
 * MathScratchDrawBoard - 草稿纸「手写草稿」面板
 *
 * Canvas 自由绘制 + 横线格底, 纯工作区: 不判分、不持久化、不回传。
 * 绘图模式复用 HandwritingCard 先例 (TouchEvent + strokes 数组 + redrawAll);
 * 横线格底每次重绘时先画线再画笔迹, 清空/撤销后格底不丢。
 *
 * 清空由父层 (MathScratchSheet) 通过 clearTick 递增触发 (@Monitor), 避免跨组件引用。
 */

import { getAppUiState } from '../../state/AppUiState'

interface ScratchPoint {
  x: number
  y: number
}

const RULED_INTERVAL: number = 36
const STROKE_WIDTH: number = 3

@ComponentV2
export struct MathScratchDrawBoard {
  @Param clearTick: number = 0

  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  )
  private canvasWidth: number = 0
  private canvasHeight: number = 0
  private strokes: ScratchPoint[][] = []
  private currentPoints: ScratchPoint[] = []
  @Local hasContent: boolean = false

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get pencilColor(): string {
    return this.isDarkMode ? '#CCCCCC' : '#333333'
  }

  private get ruledColor(): string {
    return this.isDarkMode ? '#2E3850' : '#E3EAF6'
  }

  private get canvasBg(): string {
    return this.isDarkMode ? '#20283A' : '#FBFCFF'
  }

  private get canvasBorderColor(): string {
    return this.isDarkMode ? '#44506B' : '#D9E2F2'
  }

  @Monitor('clearTick')
  onClearTickChange(): void {
    this.handleClear()
  }

  // ====== 绘图 ======

  private handleTouchDown(event: TouchEvent): void {
    event.stopPropagation()
    const touch = event.touches[0]
    const point: ScratchPoint = { x: touch.x, y: touch.y }
    this.currentPoints = [point]
    this.canvasContext.beginPath()
    this.canvasContext.moveTo(point.x, point.y)
  }

  private handleTouchMove(event: TouchEvent): void {
    if (this.currentPoints.length === 0) {
      return
    }
    event.stopPropagation()
    const touch = event.touches[0]
    const point: ScratchPoint = { x: touch.x, y: touch.y }
    this.currentPoints.push(point)
    this.canvasContext.lineTo(point.x, point.y)
    this.canvasContext.stroke()
    this.hasContent = true
  }

  private handleTouchUp(event: TouchEvent): void {
    event.stopPropagation()
    if (this.currentPoints.length > 0) {
      this.strokes.push(this.currentPoints)
      this.currentPoints = []
    }
    this.hasContent = this.strokes.length > 0
  }

  // 先画横线格底再画笔迹, 保证清空/重绘后格底不丢
  private drawRuledLines(): void {
    if (this.canvasWidth <= 0 || this.canvasHeight <= 0) {
      return
    }
    this.canvasContext.strokeStyle = this.ruledColor
    this.canvasContext.lineWidth = 1
    for (let y = RULED_INTERVAL; y < this.canvasHeight; y += RULED_INTERVAL) {
      this.canvasContext.beginPath()
      this.canvasContext.moveTo(0, y)
      this.canvasContext.lineTo(this.canvasWidth, y)
      this.canvasContext.stroke()
    }
    this.canvasContext.strokeStyle = this.pencilColor
    this.canvasContext.lineWidth = STROKE_WIDTH
  }

  private redrawAll(): void {
    this.canvasContext.clearRect(0, 0, this.canvasWidth, this.canvasHeight)
    this.drawRuledLines()
    for (const stroke of this.strokes) {
      if (stroke.length === 0) {
        continue
      }
      this.canvasContext.beginPath()
      this.canvasContext.moveTo(stroke[0].x, stroke[0].y)
      for (let i = 1; i < stroke.length; i++) {
        this.canvasContext.lineTo(stroke[i].x, stroke[i].y)
      }
      this.canvasContext.stroke()
    }
  }

  private handleClear(): void {
    this.strokes = []
    this.currentPoints = []
    this.redrawAll()
    this.hasContent = false
  }

  build() {
    Column() {
      Canvas(this.canvasContext)
        .width('100%')
        .height('100%')
        .backgroundColor(this.canvasBg)
        .borderRadius(14)
        .border({ width: 1, color: this.canvasBorderColor, style: BorderStyle.Solid })
        .onReady(() => {
          this.canvasContext.lineCap = 'round'
          this.canvasContext.lineJoin = 'round'
          this.canvasContext.strokeStyle = this.pencilColor
          this.canvasContext.lineWidth = STROKE_WIDTH
          this.drawRuledLines()
        })
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.canvasWidth = newArea.width as number
          this.canvasHeight = newArea.height as number
        })
        .onTouch((event: TouchEvent) => {
          switch (event.type) {
            case TouchType.Down:
              this.handleTouchDown(event)
              break
            case TouchType.Move:
              this.handleTouchMove(event)
              break
            case TouchType.Up:
              this.handleTouchUp(event)
              break
            default:
              break
          }
          event.stopPropagation()
        })
        .hitTestBehavior(HitTestMode.Block)
    }
    .width('100%')
    .height('100%')
  }
}
