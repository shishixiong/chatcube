import { SymbolGlyphModifier } from '@kit.ArkUI'
import { util } from '@kit.ArkTS'
import { image } from '@kit.ImageKit'
import { getAppUiState } from '../state/AppUiState'
import { ToolCall } from '../models/ChatModels'
import { getStrokeOrder, HandwritingStroke } from '../config/StrokeOrderData'
import { withColorAlpha } from '../utils/ColorAlphaUtils'

// 用户写的笔画点
interface StrokePoint {
  x: number
  y: number
  timestamp: number
}

// 完成的一笔
interface DrawnStroke {
  points: StrokePoint[]
}

// 结果接口（与组件导出对齐）
export interface HandwritingResult {
  character: string
  type: string
  completed: boolean
  stroke_count: number
}

const SUCCESS_GREEN: string = '#22C55E'
const STROKE_WIDTH: number = 6

@ComponentV2
export struct HandwritingCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  // 字符信息
  @Local character: string = ''
  @Local charType: string = 'letter'
  @Local strokes: HandwritingStroke[] = []

  // 绘图状态
  @Local drawnStrokes: DrawnStroke[] = []
  @Local isSubmitting: boolean = false
  @Local showAnimation: boolean = false
  @Local currentAnimStroke: number = -1
  @Local isCompleted: boolean = false
  @Local hasContent: boolean = false

  // 私有
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  )
  private animTimerId: number = -1
  private canvasWidth: number = 0
  private canvasHeight: number = 0
  private currentPoints: StrokePoint[] = []

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themeAiBubble(): ResourceColor {
    return getAppUiState().themeAiBubble
  }
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get pencilColor(): string {
    return this.isDarkMode ? '#CCCCCC' : '#333333'
  }
  private get canvasBg(): string {
    return this.isDarkMode ? '#2A2A2A' : '#FAFAF9'
  }
  private get canvasBorderColor(): string {
    return this.isDarkMode ? '#555555' : '#DDDDDD'
  }
  private get demoCharColor(): string {
    return this.isDarkMode ? '#FCD34D' : '#92400E'
  }
  private get demoStrokeDescColor(): string {
    return this.isDarkMode ? '#FBBF24' : '#b45309'
  }

  // 难度标签
  private get typeLabel(): string {
    switch (this.charType) {
      case 'letter': return '字母 · Letter'
      case 'number': return '数字 · Number'
      case 'chinese': return '汉字 · 中文'
      default: return '书写'
    }
  }

  // 笔顺描述
  private get strokeLabels(): string {
    return this.strokes.map((s: HandwritingStroke) => s.label).join(' ')
  }

  aboutToAppear(): void {
    this.parseArguments()
    if (this.isAnswered) {
      this.parsePreviousResult()
    }
  }

  aboutToDisappear(): void {
    if (this.animTimerId !== -1) {
      clearTimeout(this.animTimerId)
      this.animTimerId = -1
    }
  }

  private parseArguments(): void {
    try {
      const args = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      this.character = (args['character'] as string) ?? 'A'
      this.charType = (args['type'] as string) ?? 'letter'

      // 优先使用本地笔顺数据
      const localStrokes = getStrokeOrder(this.character)
      if (localStrokes !== null) {
        this.strokes = localStrokes
      } else {
        // 使用 AI 提供的笔顺
        const rawStrokes = args['strokes'] as Array<Record<string, Object>> | undefined
        if (rawStrokes !== undefined) {
          this.strokes = rawStrokes.map((s: Record<string, Object>) => ({
            x1: (s['x1'] as number) ?? 0,
            y1: (s['y1'] as number) ?? 0,
            x2: (s['x2'] as number) ?? 0,
            y2: (s['y2'] as number) ?? 0,
            label: (s['label'] as string) ?? ''
          }))
        }
      }
    } catch (_e) {
      this.character = 'A'
      this.charType = 'letter'
    }
  }

  private parsePreviousResult(): void {
    try {
      const result = JSON.parse(this.answeredPayload) as Record<string, Object>
      this.isCompleted = (result['completed'] as boolean) ?? true
    } catch (_e) {
      this.isCompleted = true
    }
  }

  // ====== 笔顺动画 ======

  private playStrokeAnimation(): void {
    if (this.strokes.length === 0) {
      return
    }
    this.showAnimation = true
    this.currentAnimStroke = -1
    this.animateNextStroke()
  }

  private animateNextStroke(): void {
    this.currentAnimStroke++
    if (this.currentAnimStroke >= this.strokes.length) {
      this.showAnimation = false
      this.currentAnimStroke = -1
      return
    }
    this.animTimerId = setTimeout(() => {
      this.animateNextStroke()
    }, 600)
  }

  private resetAnimation(): void {
    if (this.animTimerId !== -1) {
      clearTimeout(this.animTimerId)
      this.animTimerId = -1
    }
    this.showAnimation = false
    this.currentAnimStroke = -1
  }

  // ====== Canvas 绘图 ======

  private handleTouchDown(event: TouchEvent): void {
    if (this.isCompleted || this.isSubmitting) {
      return
    }
    event.stopPropagation()
    const touch = event.touches[0]
    const point: StrokePoint = { x: touch.x, y: touch.y, timestamp: Date.now() }
    this.currentPoints = [point]
    this.canvasContext.beginPath()
    this.canvasContext.moveTo(point.x, point.y)
  }

  private handleTouchMove(event: TouchEvent): void {
    if (this.isCompleted || this.isSubmitting || this.currentPoints.length === 0) {
      return
    }
    event.stopPropagation()
    const touch = event.touches[0]
    const point: StrokePoint = { x: touch.x, y: touch.y, timestamp: Date.now() }
    this.currentPoints.push(point)
    this.canvasContext.lineTo(point.x, point.y)
    this.canvasContext.stroke()
    this.hasContent = true
  }

  private handleTouchUp(event: TouchEvent): void {
    if (this.isCompleted || this.isSubmitting) {
      return
    }
    event.stopPropagation()
    if (this.currentPoints.length > 0) {
      this.drawnStrokes.push({ points: [...this.currentPoints] })
      this.currentPoints = []
    }
    this.hasContent = this.drawnStrokes.length > 0
  }

  private redrawAll(): void {
    this.canvasContext.clearRect(0, 0, this.canvasWidth, this.canvasHeight)
    for (const stroke of this.drawnStrokes) {
      if (stroke.points.length === 0) {
        continue
      }
      this.canvasContext.beginPath()
      this.canvasContext.moveTo(stroke.points[0].x, stroke.points[0].y)
      for (let i = 1; i < stroke.points.length; i++) {
        this.canvasContext.lineTo(stroke.points[i].x, stroke.points[i].y)
      }
      this.canvasContext.stroke()
    }
  }

  private handleUndo(): void {
    this.drawnStrokes.pop()
    this.redrawAll()
    this.hasContent = this.drawnStrokes.length > 0
  }

  private handleClear(): void {
    this.drawnStrokes = []
    this.currentPoints = []
    this.canvasContext.clearRect(0, 0, this.canvasWidth, this.canvasHeight)
    this.hasContent = false
  }

  // ====== 提交 ======

  private async handleSubmit(): Promise<void> {
    if (this.isSubmitting || this.isCompleted) {
      return
    }
    this.isSubmitting = true

    try {
      // 导出 Canvas 为 base64 JPEG
      const handwritingBase64 = await this.exportCanvasAsBase64()

      const result: HandwritingResult = {
        character: this.character,
        type: this.charType,
        completed: true,
        stroke_count: this.drawnStrokes.length
      }

      const answerJson = JSON.stringify({
        ...result,
        handwriting_base64: handwritingBase64
      })

      this.isCompleted = true
      this.onAnswer(this.toolCall.id, answerJson)
    } catch (error) {
      console.error('HandwritingCard', `Failed to export canvas: ${JSON.stringify(error)}`)
      // Fallback: 提交无图片的结果
      const result: HandwritingResult = {
        character: this.character,
        type: this.charType,
        completed: true,
        stroke_count: this.drawnStrokes.length
      }
      this.isCompleted = true
      this.onAnswer(this.toolCall.id, JSON.stringify(result))
    } finally {
      this.isSubmitting = false
    }
  }

  private async exportCanvasAsBase64(): Promise<string> {
    // 使用 Canvas 的 toDataURL 导出
    try {
      const pixelMap = this.canvasContext.getPixelMap(0, 0, this.canvasWidth, this.canvasHeight)
      const imagePacker = image.createImagePacker()
      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: 80
      }
      const buffer = await imagePacker.packing(pixelMap, packOpts)
      imagePacker.release()
      pixelMap.release()
      return this.arrayBufferToBase64(buffer)
    } catch (error) {
      console.error('HandwritingCard', `Canvas export failed: ${JSON.stringify(error)}`)
      return ''
    }
  }

  private arrayBufferToBase64(buffer: ArrayBuffer): string {
    const base64Helper = new util.Base64Helper()
    return base64Helper.encodeToStringSync(new Uint8Array(buffer))
  }

  // ====== 放弃 ======

  private handleGiveUp(): void {
    const result: HandwritingResult = {
      character: this.character,
      type: this.charType,
      completed: false,
      stroke_count: 0
    }
    this.isCompleted = true
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
  }

  // ====== UI Builders ======

  build() {
    if (this.isAnswered && !this.largeSize) {
      // 已答内联：只读回顾
      this.AnsweredView()
    } else if (!this.largeSize) {
      // 内联横幅
      this.InlineBanner()
    } else {
      // 全屏书写模式
      this.FullScreenSheet()
    }
  }

  @Builder
  AnsweredView() {
    Row() {
      Column() {
        SymbolGlyph($r('sys.symbol.pencil'))
          .fontSize(15)
          .fontColor([this.themePrimary])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(withColorAlpha(this.themePrimary, '18'))
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)

      Column({ space: 2 }) {
        Text(`学写字 - ${this.character}`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.isCompleted ? '已完成' : '已放弃')
          .fontSize(10)
          .fontColor(this.isCompleted ? SUCCESS_GREEN : '#FF9F43')
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 8 })
      .layoutWeight(1)

      Column()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(this.isCompleted ? SUCCESS_GREEN : '#FF9F43')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.themeAiBubble)
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  InlineBanner() {
    Row() {
      Column() {
        SymbolGlyph($r('sys.symbol.pencil'))
          .fontSize(15)
          .fontColor([this.themePrimary])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(withColorAlpha(this.themePrimary, '18'))
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)

      Column({ space: 2 }) {
        Text(`学写字 · ${this.character}`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text('点击开始写字')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 8 })
      .layoutWeight(1)

      Text('>')
        .fontSize(14)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.themeAiBubble)
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  FullScreenSheet() {
    Column({ space: 14 }) {
      // 1. HeaderRow
      this.HeaderRow()

      // 2. DemoPanel
      this.DemoPanel()

      // 3. CanvasPanel
      this.CanvasPanel()

      // 4. ActionRow
      this.ActionRow()
    }
    .width('100%')
    .padding(20)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  HeaderRow() {
    Row({ space: 10 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.pencil'))
          .fontSize(15)
          .fontColor([this.themePrimary])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(withColorAlpha(this.themePrimary, '18'))
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)

      Column({ space: 2 }) {
        Text('学写字')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.typeLabel)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.strokeLabels !== '') {
        Text(`笔顺: ${this.strokeLabels}`)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
  }

  @Builder
  DemoPanel() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        // 大字示范
        Text(this.character)
          .fontSize(72)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.demoCharColor)

        // 笔顺描述
        if (this.strokes.length > 0) {
          Text(`${this.strokes.length}笔 · ${this.strokeLabels}`)
            .fontSize(11)
            .fontColor(this.demoStrokeDescColor)
            .margin({ top: 4 })
        }

        // 动画状态
        if (this.showAnimation) {
          Text(`播放第 ${this.currentAnimStroke + 1}/${this.strokes.length} 笔`)
            .fontSize(10)
            .fontColor('#22C55E')
            .margin({ top: 2 })
        }
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Center)

      Button('▶ 重播')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .backgroundColor(withColorAlpha(this.themePrimary, '10'))
        .borderRadius(8)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .onClick(() => {
          this.resetAnimation()
          this.playStrokeAnimation()
        })
    }
    .width('100%')
    .backgroundColor(withColorAlpha(this.themePrimary, '08'))
    .borderRadius(12)
    .border({ width: 1.5, color: withColorAlpha(this.themePrimary, '38'), style: BorderStyle.Dashed })
    .onClick(() => {
      this.resetAnimation()
      this.playStrokeAnimation()
    })
  }

  @Builder
  CanvasPanel() {
    Column() {
      Canvas(this.canvasContext)
        .width('100%')
        .height(220)
        .backgroundColor(this.canvasBg)
        .borderRadius(12)
        .border({ width: 2, color: this.canvasBorderColor, style: BorderStyle.Dashed })
        .onReady(() => {
          this.canvasContext.strokeStyle = this.pencilColor
          this.canvasContext.lineWidth = STROKE_WIDTH
          this.canvasContext.lineCap = 'round'
          this.canvasContext.lineJoin = 'round'
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
          }
          event.stopPropagation()
        })
        .hitTestBehavior(HitTestMode.Block)
    }
    .width('100%')
  }

  @Builder
  ActionRow() {
    Row() {
      // 撤销
      Button('↩ 撤销')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .enabled(this.drawnStrokes.length > 0 && !this.isSubmitting && !this.isCompleted)
        .opacity(this.drawnStrokes.length > 0 && !this.isSubmitting && !this.isCompleted ? 1 : 0.4)
        .onClick(() => {
          this.handleUndo()
        })

      // 清除
      Button('✕ 清除')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .enabled(this.hasContent && !this.isSubmitting && !this.isCompleted)
        .opacity(this.hasContent && !this.isSubmitting && !this.isCompleted ? 1 : 0.4)
        .onClick(() => {
          this.handleClear()
        })

      Blank()

      // 提交
      Button(this.isSubmitting ? '小星老师正在看...' : '提交评价')
        .fontSize(13)
        .fontColor(Color.White)
        .backgroundColor(SUCCESS_GREEN)
        .borderRadius(8)
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
        .enabled(this.hasContent && !this.isSubmitting && !this.isCompleted)
        .opacity(this.hasContent && !this.isSubmitting && !this.isCompleted ? 1 : 0.5)
        .onClick(() => {
          this.handleSubmit()
        })
    }
    .width('100%')
  }
}
