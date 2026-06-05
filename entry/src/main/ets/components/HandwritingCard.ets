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
  handwriting_base64?: string
}

const SUCCESS_GREEN: string = '#22C55E'
const STROKE_WIDTH: number = 6

// 笔顺动画时序
const ANIM_PER_STROKE_MS: number = 450
const ANIM_FRAME_MS: number = 16
const ANIM_INTER_STROKE_PAUSE_MS: number = 200
const ANIM_FINAL_PAUSE_MS: number = 600
const PEN_TIP_RADIUS_VP: number = 7
const PEN_TIP_HIGHLIGHT_RADIUS_VP: number = 2.5
const ANIM_STROKE_WIDTH: number = 6
const ANIM_COMPLETED_STROKE_WIDTH: number = 4
const ANIM_REFERENCE_LINE_WIDTH: number = 2
const ANIM_REFERENCE_DASH: number[] = [3, 4]

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
  @Local currentStrokeProgress: number = 0
  @Local animActive: boolean = false
  @Local hasAutoPlayed: boolean = false
  @Local pendingAutoPlay: boolean = false
  @Local isCompleted: boolean = false
  @Local hasContent: boolean = false

  // 私有
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  )
  private animCanvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  )
  private animTimerId: number = -1
  private animFrameTimerId: number = -1
  private canvasWidth: number = 0
  private canvasHeight: number = 0
  private animCanvasWidth: number = 0
  private animCanvasHeight: number = 0
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

  // 笔顺动画三色
  private get referenceStrokeColor(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '28' : '22')
  }
  private get completedStrokeColor(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '65' : '55')
  }
  private get penTipColor(): string {
    return this.themePrimary
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
    // 全屏 sheet 进入时：标记首次自动播放
    this.pendingAutoPlay = this.largeSize && !this.hasAutoPlayed && this.strokes.length > 0
  }

  aboutToDisappear(): void {
    this.clearAllAnimTimers()
    this.showAnimation = false
    this.currentAnimStroke = -1
    this.currentStrokeProgress = 0
    this.animActive = false
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
          this.strokes = rawStrokes.map((s: Record<string, Object>): HandwritingStroke => {
            return {
              x1: (s['x1'] as number) ?? 0,
              y1: (s['y1'] as number) ?? 0,
              x2: (s['x2'] as number) ?? 0,
              y2: (s['y2'] as number) ?? 0,
              label: (s['label'] as string) ?? ''
            } as HandwritingStroke
          })
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

  // ====== 笔顺动画（笔尖轨迹式）======

  private playStrokeAnimation(): void {
    if (this.strokes.length === 0) {
      return
    }
    this.clearAllAnimTimers()
    this.showAnimation = true
    this.currentAnimStroke = -1
    this.currentStrokeProgress = 0
    this.animActive = true
    this.animateNextStroke()
  }

  private animateNextStroke(): void {
    this.currentAnimStroke = this.currentAnimStroke + 1
    this.currentStrokeProgress = 0

    if (this.currentAnimStroke >= this.strokes.length) {
      // 全部笔完成：停留后回归静态
      this.animTimerId = setTimeout(() => {
        this.animTimerId = -1
        this.showAnimation = false
        this.currentAnimStroke = -1
        this.currentStrokeProgress = 0
        this.animActive = false
        this.drawAnimationFrame()
      }, ANIM_FINAL_PAUSE_MS)
      return
    }

    const totalFrames: number = Math.max(1, Math.round(ANIM_PER_STROKE_MS / ANIM_FRAME_MS))
    let frameCount: number = 0

    // 立即画一帧（progress = 0：笔尖在起点）
    this.drawAnimationFrame()

    this.animFrameTimerId = setInterval(() => {
      frameCount = frameCount + 1
      this.currentStrokeProgress = frameCount / totalFrames
      if (this.currentStrokeProgress >= 1) {
        this.currentStrokeProgress = 1
        this.drawAnimationFrame()
        if (this.animFrameTimerId !== -1) {
          clearInterval(this.animFrameTimerId)
          this.animFrameTimerId = -1
        }
        // 笔间停顿
        this.animTimerId = setTimeout(() => {
          this.animTimerId = -1
          this.animateNextStroke()
        }, ANIM_INTER_STROKE_PAUSE_MS)
      } else {
        this.drawAnimationFrame()
      }
    }, ANIM_FRAME_MS)
  }

  private resetAnimation(): void {
    this.clearAllAnimTimers()
    this.showAnimation = false
    this.currentAnimStroke = -1
    this.currentStrokeProgress = 0
    this.animActive = false
    this.drawAnimationFrame()
  }

  private clearAllAnimTimers(): void {
    if (this.animTimerId !== -1) {
      clearTimeout(this.animTimerId)
      this.animTimerId = -1
    }
    if (this.animFrameTimerId !== -1) {
      clearInterval(this.animFrameTimerId)
      this.animFrameTimerId = -1
    }
  }

  // 绘制当前帧（4 阶段：参考底图 → 已完成笔画 → 当前笔画插值 → 笔尖圆点）
  private drawAnimationFrame(): void {
    if (this.animCanvasWidth === 0 || this.animCanvasHeight === 0) {
      return
    }
    const ctx: CanvasRenderingContext2D = this.animCanvasContext
    const w: number = this.animCanvasWidth
    const h: number = this.animCanvasHeight

    // 1. 清屏
    ctx.clearRect(0, 0, w, h)

    // 2. 参考底图：所有笔画的虚线轮廓
    ctx.strokeStyle = this.referenceStrokeColor
    ctx.lineWidth = ANIM_REFERENCE_LINE_WIDTH
    ctx.setLineDash(ANIM_REFERENCE_DASH)
    ctx.lineCap = 'round'
    for (let i: number = 0; i < this.strokes.length; i++) {
      const s: HandwritingStroke = this.strokes[i]
      ctx.beginPath()
      ctx.moveTo(s.x1 * w, s.y1 * h)
      ctx.lineTo(s.x2 * w, s.y2 * h)
      ctx.stroke()
    }
    ctx.setLineDash([] as number[])

    // 静态态（不播放）只显示参考底图
    if (!this.showAnimation || this.currentAnimStroke < 0) {
      return
    }

    // 3. 已完成笔画（实线，中等透明）
    if (this.currentAnimStroke > 0) {
      ctx.strokeStyle = this.completedStrokeColor
      ctx.lineWidth = ANIM_COMPLETED_STROKE_WIDTH
      ctx.lineCap = 'round'
      for (let i: number = 0; i < this.currentAnimStroke; i++) {
        const s: HandwritingStroke = this.strokes[i]
        ctx.beginPath()
        ctx.moveTo(s.x1 * w, s.y1 * h)
        ctx.lineTo(s.x2 * w, s.y2 * h)
        ctx.stroke()
      }
    }

    // 4. 当前笔画（线性插值）+ 笔尖圆点
    if (this.currentAnimStroke < this.strokes.length) {
      const cur: HandwritingStroke = this.strokes[this.currentAnimStroke]
      const startX: number = cur.x1 * w
      const startY: number = cur.y1 * h
      const endX: number = cur.x2 * w
      const endY: number = cur.y2 * h
      const t: number = this.currentStrokeProgress
      const tipX: number = startX + (endX - startX) * t
      const tipY: number = startY + (endY - startY) * t

      // 4a. 当前笔画的已绘部分
      ctx.strokeStyle = this.penTipColor
      ctx.lineWidth = ANIM_STROKE_WIDTH
      ctx.beginPath()
      ctx.moveTo(startX, startY)
      ctx.lineTo(tipX, tipY)
      ctx.stroke()

      // 4b. 笔尖圆点
      ctx.fillStyle = this.penTipColor
      ctx.beginPath()
      ctx.arc(tipX, tipY, PEN_TIP_RADIUS_VP, 0, Math.PI * 2)
      ctx.fill()

      // 4c. 笔尖白色高光
      ctx.fillStyle = '#FFFFFF'
      ctx.beginPath()
      ctx.arc(tipX - 1.5, tipY - 1.5, PEN_TIP_HIGHLIGHT_RADIUS_VP, 0, Math.PI * 2)
      ctx.fill()
    }
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

      result.handwriting_base64 = handwritingBase64
      const answerJson = JSON.stringify(result)

      this.isCompleted = true
      this.onAnswer(this.toolCall.id, answerJson)
    } catch (error) {
      console.error('HandwritingCard', `Failed to export canvas: ${JSON.stringify(error)}`)
      // Fallback: 提交无图片的结果
      const result: HandwritingResult = {
        character: this.character,
        type: this.charType,
        completed: true,
        stroke_count: this.drawnStrokes.length,
        handwriting_base64: ''
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
        SymbolGlyph($r('sys.symbol.AI_pencil'))
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
        SymbolGlyph($r('sys.symbol.AI_pencil'))
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
        SymbolGlyph($r('sys.symbol.AI_pencil'))
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
      if (this.strokes.length > 0) {
        // 笔尖轨迹动画区
        Stack() {
          // L1: 动画 canvas
          Canvas(this.animCanvasContext)
            .width('100%')
            .height(160)
            .backgroundColor(Color.Transparent)
            .hitTestBehavior(HitTestMode.Transparent)
            .onReady(() => {
              this.drawAnimationFrame()
            })
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              this.animCanvasWidth = newArea.width as number
              this.animCanvasHeight = newArea.height as number
              this.drawAnimationFrame()
            })

          // L2: 文字状态层（覆盖在 canvas 之上，浮于底部）
          Column() {
            if (this.showAnimation) {
              Text(`播放第 ${this.currentAnimStroke + 1} / ${this.strokes.length} 笔`)
                .fontSize(10)
                .fontColor(SUCCESS_GREEN)
            } else {
              Text(`${this.strokes.length} 笔 · ${this.strokeLabels}`)
                .fontSize(11)
                .fontColor(this.demoStrokeDescColor)
            }
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.Center)
          .padding({ bottom: 8 })
        }
        .width('100%')
        .height(160)
      } else {
        // 退化：无 strokes 数据时显示静态大字
        Column() {
          Text(this.character)
            .fontSize(72)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.demoCharColor)
        }
        .width('100%')
        .height(160)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }

      // L3: 重播按钮（Stack 右上角，与 stroke 是否有无关）
      Button('▶ 重播')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .backgroundColor(withColorAlpha(this.themePrimary, '10'))
        .borderRadius(8)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .enabled(this.strokes.length > 0)
        .opacity(this.strokes.length > 0 ? 1 : 0.4)
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
      if (this.strokes.length > 0) {
        this.resetAnimation()
        this.playStrokeAnimation()
      }
    })
    .onAppear(() => {
      // 首次进入 sheet 自动播放一次
      if (this.pendingAutoPlay) {
        this.pendingAutoPlay = false
        this.hasAutoPlayed = true
        this.playStrokeAnimation()
      }
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
