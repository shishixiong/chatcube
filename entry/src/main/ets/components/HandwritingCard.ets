import { SymbolGlyphModifier } from '@kit.ArkUI'
import { util } from '@kit.ArkTS'
import { image } from '@kit.ImageKit'
import { getAppUiState } from '../state/AppUiState'
import { ToolCall } from '../models/ChatModels'
import { getStrokeOrder, HandwritingStroke } from '../config/StrokeOrderData'
import { withColorAlpha } from '../utils/ColorAlphaUtils'

// 用户写的笔画点
interface DrawnPoint {
  x: number
  y: number
  timestamp: number
}

// 完成的一笔
interface DrawnStroke {
  points: DrawnPoint[]
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
const TICK_MS: number = 33           // ~30fps
const FADE_PER_TICK: number = 0.08   // ~12 ticks to full alpha ≈ 400ms per stroke
const SVG_GRID: number = 1024       // hanzi-writer-data 网格尺寸

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
  @Local isCompleted: boolean = false
  @Local hasContent: boolean = false

  // 笔顺动画状态
  @Local isPlaying: boolean = false
  @Local currentStrokeIdx: number = -1       // 当前播放的笔画索引，-1 = 未开始/已结束
  @Local currentStrokeAlpha: number = 0      // 0..1 当前笔画的淡入透明度
  @Local playedStrokeCount: number = 0        // 已完整显示的笔画数

  // 私有
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  )
  private canvasWidth: number = 0
  private canvasHeight: number = 0
  private currentPoints: DrawnPoint[] = []

  // 笔顺动画私有字段
  private demoCanvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  )
  private demoCanvasWidth: number = 0
  private demoCanvasHeight: number = 0
  private animTimerId: number = -1

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

  // 字符字形底图颜色（淡主题色）
  private get ghostCharColor(): string {
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '24' : '1A')
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
    this.stopPlayback()
  }

  private parseArguments(): void {
    try {
      const args = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      this.character = (args['character'] as string) ?? 'A'
      this.charType = (args['type'] as string) ?? 'letter'

      // 使用本地笔顺数据（SVG 路径）
      const localStrokes = getStrokeOrder(this.character)
      if (localStrokes !== null) {
        this.strokes = localStrokes
      }
      // AI 也可直接传 SVG path 数据
      const rawStrokes = args['strokes'] as Array<Record<string, Object>> | undefined
      if (localStrokes === null && rawStrokes !== undefined) {
        this.strokes = rawStrokes.map((s: Record<string, Object>): HandwritingStroke => {
          const stroke: HandwritingStroke = {
            path: (s['path'] as string) ?? '',
            label: (s['label'] as string) ?? ''
          }
          return stroke
        })
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

  // ====== Canvas 绘图 ======

  private handleTouchDown(event: TouchEvent): void {
    if (this.isCompleted || this.isSubmitting) {
      return
    }
    event.stopPropagation()
    const touch = event.touches[0]
    const point: DrawnPoint = { x: touch.x, y: touch.y, timestamp: Date.now() }
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
    const point: DrawnPoint = { x: touch.x, y: touch.y, timestamp: Date.now() }
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

  // ====== 笔顺动画（SVG 路径填充 + 逐笔淡入）======

  private initDemoCanvas(): void {
    this.demoCanvasContext.lineCap = 'round'
    this.demoCanvasContext.lineJoin = 'round'
  }

  // 启动笔顺动画；无笔顺数据时直接 return
  private startPlayback(): void {
    if (this.strokes.length === 0) {
      console.info('HandwritingCard', `startPlayback: no strokes for character "${this.character}"`)
      return
    }
    if (this.demoCanvasWidth === 0 || this.demoCanvasHeight === 0) {
      console.info('HandwritingCard', `startPlayback: canvas not ready (w=${this.demoCanvasWidth} h=${this.demoCanvasHeight})`)
      return
    }
    this.stopPlayback()
    this.demoCanvasContext.clearRect(0, 0, this.demoCanvasWidth, this.demoCanvasHeight)
    this.isPlaying = true
    this.currentStrokeIdx = 0
    this.currentStrokeAlpha = 0
    this.playedStrokeCount = 0
    console.info('HandwritingCard', `startPlayback: ${this.strokes.length} strokes, canvas ${this.demoCanvasWidth}x${this.demoCanvasHeight}`)
    this.animTimerId = setInterval((): void => this.tick(), TICK_MS)
  }

  private stopPlayback(): void {
    if (this.animTimerId !== -1) {
      clearInterval(this.animTimerId)
      this.animTimerId = -1
    }
    this.isPlaying = false
  }

  private tick(): void {
    if (this.currentStrokeIdx < 0 || this.currentStrokeIdx >= this.strokes.length) {
      this.stopPlayback()
      this.currentStrokeIdx = -1
      this.redrawDemoCanvas()
      return
    }
    this.currentStrokeAlpha += FADE_PER_TICK
    if (this.currentStrokeAlpha >= 1) {
      this.playedStrokeCount = this.currentStrokeIdx + 1
      this.currentStrokeIdx += 1
      this.currentStrokeAlpha = 0
    }
    this.redrawDemoCanvas()
  }

  private redrawDemoCanvas(): void {
    const ctx = this.demoCanvasContext
    const w = this.demoCanvasWidth
    const h = this.demoCanvasHeight
    if (w === 0 || h === 0) {
      return
    }
    ctx.clearRect(0, 0, w, h)

    // 等比缩放居中：1024×1024 网格 → Canvas 尺寸
    const scale = Math.min(w, h) / SVG_GRID
    const offsetX = (w - SVG_GRID * scale) / 2
    const offsetY = (h - SVG_GRID * scale) / 2

    // 1. 画已完成的笔画（深琥珀色）
    ctx.fillStyle = this.demoStrokeDescColor
    const playedEnd = Math.min(this.playedStrokeCount, this.strokes.length)
    for (let i = 0; i < playedEnd; i++) {
      ctx.beginPath()
      this.drawSvgPath(ctx, this.strokes[i].path, scale, offsetX, offsetY)
      ctx.fill()
    }

    // 2. 画当前笔画（绿色，淡入）
    if (this.currentStrokeIdx >= 0 && this.currentStrokeIdx < this.strokes.length) {
      ctx.fillStyle = SUCCESS_GREEN
      ctx.globalAlpha = Math.max(0, Math.min(1, this.currentStrokeAlpha))
      ctx.beginPath()
      this.drawSvgPath(ctx, this.strokes[this.currentStrokeIdx].path, scale, offsetX, offsetY)
      ctx.fill()
      ctx.globalAlpha = 1
    }
  }

  // 解析 SVG path 字符串并执行到 Canvas 上下文
  // 支持 M / Q / L / C / Z 命令
  // hanzi-writer-data 使用 Y-up 坐标系（原点在左下角），需翻转 Y 轴适配 Canvas（Y-down）
  private drawSvgPath(ctx: CanvasRenderingContext2D, path: string, scale: number, offsetX: number, offsetY: number): void {
    const tokens = path.match(/[MQLCZmqlcz]|-?\d+\.?\d*/g)
    if (tokens === null || tokens.length === 0) {
      return
    }
    let i = 0
    while (i < tokens.length) {
      const cmd = tokens[i]
      i += 1
      if (cmd === 'M' || cmd === 'm') {
        const x = parseFloat(tokens[i]) * scale + offsetX
        const y = (SVG_GRID - parseFloat(tokens[i + 1])) * scale + offsetY
        ctx.moveTo(x, y)
        i += 2
      } else if (cmd === 'Q' || cmd === 'q') {
        const cx = parseFloat(tokens[i]) * scale + offsetX
        const cy = (SVG_GRID - parseFloat(tokens[i + 1])) * scale + offsetY
        const x = parseFloat(tokens[i + 2]) * scale + offsetX
        const y = (SVG_GRID - parseFloat(tokens[i + 3])) * scale + offsetY
        ctx.quadraticCurveTo(cx, cy, x, y)
        i += 4
      } else if (cmd === 'C' || cmd === 'c') {
        const cx1 = parseFloat(tokens[i]) * scale + offsetX
        const cy1 = (SVG_GRID - parseFloat(tokens[i + 1])) * scale + offsetY
        const cx2 = parseFloat(tokens[i + 2]) * scale + offsetX
        const cy2 = (SVG_GRID - parseFloat(tokens[i + 3])) * scale + offsetY
        const x = parseFloat(tokens[i + 4]) * scale + offsetX
        const y = (SVG_GRID - parseFloat(tokens[i + 5])) * scale + offsetY
        ctx.bezierCurveTo(cx1, cy1, cx2, cy2, x, y)
        i += 6
      } else if (cmd === 'L' || cmd === 'l') {
        const x = parseFloat(tokens[i]) * scale + offsetX
        const y = (SVG_GRID - parseFloat(tokens[i + 1])) * scale + offsetY
        ctx.lineTo(x, y)
        i += 2
      } else if (cmd === 'Z' || cmd === 'z') {
        ctx.closePath()
      }
    }
  }

  // ====== 提交 ======

  private async handleSubmit(): Promise<void> {
    if (this.isSubmitting || this.isCompleted) {
      return
    }
    this.stopPlayback()
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
    this.stopPlayback()
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
    Column({ space: 6 }) {
      // 字形 + 笔顺动画 Canvas
      Stack({ alignContent: Alignment.Center }) {
        // 笔顺动画 Canvas（透明背景）
        if (this.strokes.length > 0) {
          Canvas(this.demoCanvasContext)
            .width('100%')
            .height(160)
            .onReady(() => {
              this.initDemoCanvas()
            })
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              this.demoCanvasWidth = newArea.width as number
              this.demoCanvasHeight = newArea.height as number
              // 首次获得有效尺寸时启动播放
              if (!this.isPlaying && this.currentStrokeIdx === -1 && !this.isCompleted) {
                this.startPlayback()
              }
              this.redrawDemoCanvas()
            })
            .hitTestBehavior(HitTestMode.Transparent)
        } else {
          // 无笔顺数据时显示鬼影大字
          Text(this.character)
            .fontSize(120)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.ghostCharColor)
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .height(160)
      .alignContent(Alignment.Center)
      .backgroundColor(withColorAlpha(this.themePrimary, '08'))
      .borderRadius(12)
      .border({ width: 1.5, color: withColorAlpha(this.themePrimary, '38'), style: BorderStyle.Dashed })

      // 笔顺描述 + 重播按钮
      if (this.strokes.length > 0) {
        Row() {
          Text(`${this.strokes.length} 笔 · ${this.strokeLabels}`)
            .fontSize(11)
            .fontColor(this.demoStrokeDescColor)
            .layoutWeight(1)

          Button(this.isPlaying ? '播放中...' : '▶ 重播')
            .fontSize(11)
            .fontColor(this.themePrimary)
            .backgroundColor(Color.Transparent)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .enabled(!this.isPlaying && !this.isCompleted)
            .opacity(!this.isPlaying && !this.isCompleted ? 1 : 0.5)
            .onClick(() => {
              this.startPlayback()
            })
        }
        .width('100%')
      }
    }
    .width('100%')
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
