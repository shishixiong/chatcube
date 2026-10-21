// entry/src/main/ets/components/map/bodies/MapWriteBody.ets
/**
 * MapWriteBody - map_quiz write 题型 body（看地图省份，把名字写下来）
 *
 * 金色 target 地图 + ghost 描红 toggle + 手写 Canvas（镜像 HandwritingCard 采集，
 * 不导出 base64——自评语义 spec §9.3）+ 「笔顺演示」逐字小卡（Y-up 汉字路径含 (1024-y)
 * 翻转，与地图数据 Y-down 不同）+ 参考答案 + 自评三按钮（payload correct 按自评）。
 */

import common from '@ohos.app.ability.common'
import { getAppUiState } from '../../../state/AppUiState'
import { ToolCall } from '../../../models/ChatModels'
import { withColorAlpha } from '../../../utils/ColorAlphaUtils'
import { HandwritingStroke, getStrokeOrder, hasStrokeOrder } from '../../../config/StrokeOrderData'
import { ChinaMapData, findProvinceByRef, getCachedChinaMapData, loadChinaMapData } from '../../../utils/ChinaMapData'
import { CardShell } from '../../cardshell/CardShell'
import { CardShellConfig } from '../../cardshell/CardShellTypes'
import { CardShellState } from '../../cardshell/CardShellState'
import { KIDS_MUTED } from '../../kids/KidsBrandTokens'
import { ChinaMapStage } from '../ChinaMapStage'
import { MapQuizAnswerPayload, MapQuizArgsView, parseMapQuizArgs } from '../MapQuizTypes'

interface DrawnPoint {
  x: number
  y: number
}

interface DrawnStroke {
  points: DrawnPoint[]
}

const TICK_MS: number = 33
const FADE_PER_TICK: number = 0.05
const SVG_GRID: number = 1024

/**
 * StrokeDemoCell - 单字笔顺演示小卡（HanziCard demo canvas 逐字版，tap 重播）
 */
@ComponentV2
struct StrokeDemoCell {
  @Param charStr: string = ''
  @Local strokes: HandwritingStroke[] = []
  @Local isPlaying: boolean = false
  @Local currentStrokeIdx: number = -1
  @Local currentStrokeAlpha: number = 0
  @Local playedStrokeCount: number = 0

  private animTimerId: number = -1
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private canvasWidth: number = 0
  private canvasHeight: number = 0

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  aboutToAppear(): void {
    const localStrokes = hasStrokeOrder(this.charStr) ? getStrokeOrder(this.charStr) : null
    this.strokes = localStrokes !== null ? localStrokes : []
  }

  aboutToDisappear(): void {
    this.stopPlayback()
  }

  private startPlayback(): void {
    if (this.strokes.length === 0 || this.canvasWidth === 0 || this.canvasHeight === 0) {
      return
    }
    this.stopPlayback()
    this.isPlaying = true
    this.currentStrokeIdx = 0
    this.currentStrokeAlpha = 0
    this.playedStrokeCount = 0
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
    const ctx = this.canvasContext
    const w = this.canvasWidth
    const h = this.canvasHeight
    if (w <= 0 || h <= 0) {
      return
    }
    ctx.clearRect(0, 0, w, h)
    const scale = Math.min(w, h) / SVG_GRID
    const offsetX = (w - SVG_GRID * scale) / 2
    const offsetY = (h - SVG_GRID * scale) / 2
    ctx.fillStyle = this.themePrimary
    const playedEnd = Math.min(this.playedStrokeCount, this.strokes.length)
    for (let i = 0; i < playedEnd; i++) {
      ctx.beginPath()
      this.drawSvgPath(ctx, this.strokes[i].path, scale, offsetX, offsetY)
      ctx.fill()
    }
    if (this.currentStrokeIdx >= 0 && this.currentStrokeIdx < this.strokes.length) {
      ctx.fillStyle = '#22C55E'
      ctx.globalAlpha = Math.max(0, Math.min(1, this.currentStrokeAlpha))
      ctx.beginPath()
      this.drawSvgPath(ctx, this.strokes[this.currentStrokeIdx].path, scale, offsetX, offsetY)
      ctx.fill()
      ctx.globalAlpha = 1
    }
  }

  // 汉字路径 Y-up → Y-down 翻转（与地图数据相反，勿混用）
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

  private strokeLabels(): string {
    const parts: string[] = []
    for (const s of this.strokes) {
      parts.push(s.label)
    }
    return parts.join(' · ')
  }

  build() {
    Row({ space: 10 }) {
      if (this.strokes.length > 0) {
        Column() {
          Canvas(this.canvasContext)
            .width(72)
            .height(72)
            .onReady(() => {
              this.startPlayback()
            })
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              this.canvasWidth = newArea.width as number
              this.canvasHeight = newArea.height as number
              if (!this.isPlaying) {
                this.startPlayback()
              }
            })
            .onClick(() => this.startPlayback())
        }

        Column({ space: 4 }) {
          Text(this.charStr)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(`${this.strokes.length} 画`)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
          Text(this.strokeLabels())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      } else {
        // 无笔顺数据：降级 ghost 大字（HandwritingCard 同款）
        Text(this.charStr)
          .fontSize(48)
          .fontWeight(FontWeight.Bold)
          .fontColor(withColorAlpha(getAppUiState().themePrimary, '26'))
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(8)
    .borderRadius(10)
    .backgroundColor(withColorAlpha(getAppUiState().themePrimary, this.strokes.length > 0 ? '0A' : '06'))
  }
}

@ComponentV2
export struct MapWriteBody {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local data: ChinaMapData | null = null
  @Local targetId: string = ''
  @Local targetName: string = ''
  @Local targetShort: string = ''
  @Local targetAbbr: string = ''
  @Local skillKey: string = 'general_social'
  @Local showGhost: boolean = true
  @Local showDemo: boolean = false
  @Local revealAnswer: boolean = false
  @Local hasInk: boolean = false
  @Local summaryText: string = ''

  private argsView: MapQuizArgsView = parseMapQuizArgs('')
  private submitted: boolean = false
  private shellState: CardShellState = new CardShellState()
  private shellConfig: CardShellConfig = {
    title: '中国地图出题', subtitle: '写名字', icon: $r('sys.symbol.map'),
    stem: '', hasAudio: false, usesConfirm: false,
    feedbackTitleCorrect: '答对啦！真棒！', correctAnswerLabel: '正确答案'
  }

  // 手写 Canvas（HandwritingCard 同构）
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private canvasWidth: number = 0
  private canvasHeight: number = 0
  private currentPoints: DrawnPoint[] = []
  private drawnStrokes: DrawnStroke[] = []

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  aboutToAppear(): void {
    this.argsView = parseMapQuizArgs(this.toolCall.arguments)
    this.initWithProvinces(getCachedChinaMapData())
    if (this.data === null) {
      const ctx = getContext(this) as common.UIAbilityContext
      loadChinaMapData(ctx).then((loaded: ChinaMapData | null) => {
        this.initWithProvinces(loaded)
      }).catch((_e: Error) => {
      })
    }
    if (this.isAnswered) {
      try {
        const prev = JSON.parse(this.answeredPayload) as Record<string, Object>
        this.revealAnswer = true
        this.summaryText = prev['correct'] === true ? '你自评写对了，继续加油！' : '这次没写对，下次看准笔画慢慢写。'
      } catch (_e) {
        this.revealAnswer = false
        this.summaryText = ''
      }
    }
  }

  private initWithProvinces(loaded: ChinaMapData | null): void {
    if (loaded === null || !this.argsView.valid) {
      return
    }
    const target = findProvinceByRef(loaded.provinces, this.argsView.province)
    if (target === null) {
      return
    }
    this.data = loaded
    this.targetId = target.id
    this.targetName = target.name
    this.targetShort = target.short
    this.targetAbbr = target.abbr
    this.skillKey = this.argsView.skillKey
  }

  // ====== 手写采集（HandwritingCard :178-208 逐行镜像，不导出 base64） ======

  private handleTouchDown(event: TouchEvent): void {
    if (this.isAnswered || this.submitted) {
      return
    }
    event.stopPropagation()
    const touch = event.touches[0]
    const point: DrawnPoint = { x: touch.x, y: touch.y }
    this.currentPoints = [point]
    this.canvasContext.beginPath()
    this.canvasContext.moveTo(point.x, point.y)
  }

  private handleTouchMove(event: TouchEvent): void {
    if (this.isAnswered || this.submitted || this.currentPoints.length === 0) {
      return
    }
    event.stopPropagation()
    const touch = event.touches[0]
    const point: DrawnPoint = { x: touch.x, y: touch.y }
    this.currentPoints.push(point)
    this.canvasContext.lineTo(point.x, point.y)
    this.canvasContext.stroke()
    this.hasInk = true
  }

  private handleTouchUp(event: TouchEvent): void {
    if (this.isAnswered || this.submitted) {
      return
    }
    event.stopPropagation()
    if (this.currentPoints.length > 0) {
      const stroke: DrawnStroke = { points: [...this.currentPoints] }
      this.drawnStrokes.push(stroke)
      this.currentPoints = []
    }
    this.hasInk = this.drawnStrokes.length > 0
  }

  private handleClear(): void {
    this.drawnStrokes = []
    this.currentPoints = []
    this.canvasContext.clearRect(0, 0, this.canvasWidth, this.canvasHeight)
    this.hasInk = false
  }

  // ====== 自评提交 ======

  private submitSelfGrade(correct: boolean): void {
    if (this.submitted || this.isAnswered) {
      return
    }
    this.submitted = true
    const payload: MapQuizAnswerPayload = {
      answered: true,
      mode: 'write',
      province: this.targetShort,
      province_id: this.targetId,
      clue: '',
      child_answer: correct ? '自评写对了' : '自评没写对',
      correct: correct,
      skill_key: this.skillKey
    }
    this.revealAnswer = true
    this.summaryText = correct ? '你自评写对了，继续加油！' : '这次没写对，下次看准笔画慢慢写。'
    this.shellState.hasSelection = true
    this.shellState.submitted = true
    this.shellState.isCorrect = correct
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private referenceAnswerText(): string {
    if (this.targetName === this.targetShort) {
      return `${this.targetName} · 简称 ${this.targetAbbr}`
    }
    return `${this.targetName}（${this.targetShort}） · 简称 ${this.targetAbbr}`
  }

  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: this.targetShort,
      onConfirm: (): void => {},
      onRetry: (): void => {}
    }) {
      Column({ space: 10 }) {
        if (this.data !== null && this.targetId !== '') {
          Text('看地图上高亮的省份，把它的名字写下来。')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          Column() {
            ChinaMapStage({
              data: this.data,
              targetId: this.targetId,
              interactive: false
            })
          }
          .width('100%')
          .height(180)
          .borderRadius(12)
          .clip(true)
          .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '0A' : '06'))

          Row({ space: 8 }) {
            Button(this.showGhost ? '整字描红 ✓' : '整字描红')
              .fontSize(12)
              .fontColor(this.showGhost ? Color.White : this.themePrimary)
              .backgroundColor(this.showGhost ? this.themePrimary : withColorAlpha(this.themePrimary, '1F'))
              .height(30)
              .onClick(() => {
                this.showGhost = !this.showGhost
              })
            Button('笔顺演示')
              .fontSize(12)
              .fontColor(this.themePrimary)
              .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '1F' : '14'))
              .height(30)
              .onClick(() => {
                this.showDemo = !this.showDemo
              })
            Blank()
            Button('擦掉重写')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .backgroundColor(withColorAlpha(KIDS_MUTED, '1F'))
              .height(30)
              .onClick(() => this.handleClear())
          }
          .width('100%')

          Stack() {
            if (this.showGhost) {
              Text(this.targetShort)
                .fontSize(64)
                .fontWeight(FontWeight.Bold)
                .fontColor(withColorAlpha(this.themePrimary, '26'))
            }
            Canvas(this.canvasContext)
              .width('100%')
              .height('100%')
              .onAreaChange((_oldArea: Area, newArea: Area) => {
                this.canvasWidth = newArea.width as number
                this.canvasHeight = newArea.height as number
              })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.handleTouchDown(event)
                } else if (event.type === TouchType.Move) {
                  this.handleTouchMove(event)
                } else if (event.type === TouchType.Up) {
                  this.handleTouchUp(event)
                }
              })
          }
          .width('100%')
          .height(150)
          .borderRadius(12)
          .backgroundColor(this.isDarkMode ? '#1C1C1E' : '#FFFFFF')
          .border({ width: 1, color: withColorAlpha(this.themePrimary, '33') })
          .alignContent(Alignment.Center)

          if (this.showDemo) {
            Column({ space: 8 }) {
              ForEach(this.targetShort.split(''), (ch: string, idx: number) => {
                StrokeDemoCell({ charStr: ch })
              }, (ch: string, idx: number) => `demo_${idx}_${ch}`)
            }
            .width('100%')
          }

          if (this.revealAnswer) {
            Column({ space: 6 }) {
              Text('参考答案')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
              Text(this.referenceAnswerText())
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              if (this.summaryText !== '') {
                Text(this.summaryText)
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
              }
            }
            .width('100%')
            .padding(10)
            .borderRadius(10)
            .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '12' : '0A'))
            .alignItems(HorizontalAlign.Start)
          }

          if (!this.isAnswered && !this.revealAnswer) {
            if (!this.hasInk) {
              Text('先在格子里写一写，再对照答案给自己打个分吧')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
            }
            Button('写好了，看答案')
              .width('100%').height(44)
              .fontSize(15)
              .backgroundColor(this.hasInk ? this.themePrimary : withColorAlpha(this.themePrimary, '33'))
              .fontColor(Color.White)
              .enabled(this.hasInk)
              .opacity(this.hasInk ? 1 : 0.55)
              .onClick(() => {
                this.revealAnswer = true
              })
          }

          if (!this.isAnswered && this.revealAnswer && !this.submitted) {
            Column({ space: 8 }) {
              Button('我写对了')
                .width('100%').height(42)
                .fontSize(15)
                .fontColor(Color.White)
                .backgroundColor('#22C55E')
                .onClick(() => this.submitSelfGrade(true))
              Row({ space: 8 }) {
                Button('再写一次')
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(14)
                  .fontColor(this.themePrimary)
                  .backgroundColor(withColorAlpha(this.themePrimary, '1F'))
                  .onClick(() => {
                    this.revealAnswer = false
                    this.handleClear()
                  })
                Button('这次没写对，继续')
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(14)
                  .fontColor(Color.White)
                  .backgroundColor(withColorAlpha(KIDS_MUTED, 'CC'))
                  .onClick(() => this.submitSelfGrade(false))
              }
              .width('100%')
            }
            .width('100%')
          }
        } else if (!this.isAnswered) {
          Text('这道地图题出错了，老师马上换一张')
            .fontSize(14).fontColor(KIDS_MUTED)
            .padding({ top: 8, bottom: 8 })
        } else {
          Text('已回答')
            .fontSize(13).fontColor($r('app.color.text_tertiary'))
            .padding({ top: 8, bottom: 8 })
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12'))
      .borderRadius(10)
    }
  }
}
