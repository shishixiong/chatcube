import {
  NUMBER_LINE_WIDTH, NUMBER_LINE_BASE_Y, NUMBER_LINE_MAX,
  numberLineX, numberLineHops, numberLineSteps, numberLineStepNarrations,
  NumberLineHops, NumberLineStep
} from '../../utils/MathTeachNumberLine'
import { AppStorageKeys } from '../../config/AppStorageKeys'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { normalizeMathSymbolsForTts } from '../../utils/TtsTextUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { makeTenBlockColor, makeTenShade, makeTenIsLight } from '../../utils/MathTeachMakeTen'
import {
  KIDS_MATH, KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED, KIDS_BORDER,
  KIDS_SURFACE, KIDS_FG, KIDS_STAR, KIDS_ON_GOLD, KIDS_SUBTLE
} from '../kids/KidsBrandTokens'

const STEP_TOTAL: number = 2
const BOARD_H: number = 120
const TOKEN_SIZE: number = 26
const HOP_DURATION_MS: number = 600
const BOUNCE_UP_MS: number = 260

@ComponentV2
export struct NumberLineBoard {
  @Param start: number = 9
  @Param step: number = 5
  @Param op: string = 'add'
  @Param readonly: boolean = false
  @Event onInteract: () => void = () => {}
  @Event onFinish: () => void = () => {}

  @Local stepIndex: number = 0
  @Local hop1Done: boolean = false
  @Local hop2Done: boolean = false
  @Local tokenValue: number = 9
  @Local tokenLift: number = 0
  @Local boardScale: number = 1

  private hops: NumberLineHops = {
    firstHop: 0, secondHop: 0, end: 0, dir: 1,
    x1: 0, x2: 0, x3: 0, arc1X: 0, arc1Y: 0, arc2X: 0, arc2Y: 0
  }
  private steps: NumberLineStep[] = []
  private stepDoneFlags: boolean[] = [false, false]
  private startedSpeak: boolean = false
  private bounceTimerId: number = -1

  aboutToAppear(): void {
    this.hops = numberLineHops(this.start, this.step, this.op)
    this.steps = numberLineSteps(this.start, this.step, this.op)
    this.tokenValue = this.start
    if (this.readonly) {
      this.hop1Done = true
      this.hop2Done = true
      this.tokenValue = this.hops.end
      this.stepIndex = STEP_TOTAL - 1
      return
    }
    this.speakStep(0)
  }

  aboutToDisappear(): void {
    if (this.bounceTimerId >= 0) {
      clearTimeout(this.bounceTimerId)
      this.bounceTimerId = -1
    }
    if (this.startedSpeak) {
      try {
        ServiceRegistry.tts().stop()
      } catch (_e) {
      }
    }
  }

  private seq(n: number): number[] {
    const arr: number[] = []
    for (let i = 0; i < n; i++) {
      arr.push(i)
    }
    return arr
  }

  private fiveTicks(): number[] {
    const arr: number[] = []
    for (let v = 0; v <= NUMBER_LINE_MAX; v += 5) {
      arr.push(v)
    }
    return arr
  }

  private px(v: number): number {
    return numberLineX(v) * this.boardScale
  }

  private py(y: number): number {
    return y * this.boardScale
  }

  private opSign(): string {
    return this.op === 'sub' ? '−' : '+'
  }

  private tokenColor(): string {
    return makeTenBlockColor(this.start)
  }

  private stepTitle(): string {
    return this.steps[this.stepIndex].title
  }

  private stepGuide(): string {
    if (this.stepIndex === 0) {
      return this.op === 'sub' ? '10 是中转站：先往回跳到 10。' : '10 是中转站：先往前跳到 10。'
    }
    if (this.op === 'sub') {
      return `从 10 再往回跳 ${this.hops.secondHop} 格，就到终点。`
    }
    return `从 10 再往前跳 ${this.hops.secondHop} 格，就到终点。`
  }

  private currentHint(): string {
    return this.steps[this.stepIndex].hint
  }

  private stepHopDone(): boolean {
    return this.stepIndex === 0 ? this.hop1Done : this.hop2Done
  }

  private fullEq(): string {
    return `${this.start} ${this.opSign()} ${this.step} = ${this.hops.end}`
  }

  private arcCommands(xa: number, cx: number, cy: number, xb: number): string {
    const s: number = this.boardScale
    const y0: number = NUMBER_LINE_BASE_Y * s
    return 'M ' + (xa * s).toFixed(2) + ' ' + y0.toFixed(2) +
      ' Q ' + (cx * s).toFixed(2) + ' ' + (cy * s).toFixed(2) +
      ' ' + (xb * s).toFixed(2) + ' ' + y0.toFixed(2)
  }

  private arrowCommands(cx: number, cy: number, xb: number): string {
    const s: number = this.boardScale
    const tipX: number = xb * s
    const tipY: number = NUMBER_LINE_BASE_Y * s - 2 * s
    let dx: number = tipX - cx * s
    let dy: number = tipY - cy * s
    const len: number = Math.max(0.001, Math.sqrt(dx * dx + dy * dy))
    dx = dx / len
    dy = dy / len
    const a: number = Math.max(6, 7 * s)
    const baseX: number = tipX - dx * a
    const baseY: number = tipY - dy * a
    const perpX: number = -dy * a * 0.55
    const perpY: number = dx * a * 0.55
    return 'M ' + tipX.toFixed(2) + ' ' + tipY.toFixed(2) +
      ' L ' + (baseX + perpX).toFixed(2) + ' ' + (baseY + perpY).toFixed(2) +
      ' L ' + (baseX - perpX).toFixed(2) + ' ' + (baseY - perpY).toFixed(2) + ' Z'
  }

  private arcApexY(cy: number): number {
    return (NUMBER_LINE_BASE_Y + cy) / 2
  }

  private hopRecordLines(): string[] {
    const sign: string = this.opSign()
    const arr: string[] = []
    arr.push(`${this.start} ${sign} ${this.hops.firstHop} = 10`)
    arr.push(`10 ${sign} ${this.hops.secondHop} = ${this.hops.end}`)
    return arr
  }

  private recordLit(idx: number): boolean {
    return idx === 0 ? this.hop1Done : this.hop2Done
  }

  private markStepDone(step: number): void {
    if (step < 0 || step >= STEP_TOTAL) {
      return
    }
    if (this.stepDoneFlags[step]) {
      return
    }
    this.stepDoneFlags[step] = true
    this.onInteract()
  }

  private canAdvance(): boolean {
    if (this.stepIndex === 0) {
      return this.hop1Done
    }
    return this.hop2Done
  }

  private goNext(): void {
    if (this.readonly) {
      return
    }
    if (this.stepIndex >= STEP_TOTAL - 1) {
      this.markStepDone(STEP_TOTAL - 1)
      this.onFinish()
      return
    }
    if (!this.canAdvance()) {
      return
    }
    this.stepIndex += 1
    this.speakStep(this.stepIndex)
  }

  private navNextEnabled(): boolean {
    if (this.stepIndex === STEP_TOTAL - 1) {
      return true
    }
    return this.canAdvance()
  }

  private goPrev(): void {
    if (this.readonly || this.stepIndex <= 0) {
      return
    }
    try {
      ServiceRegistry.tts().stop()
    } catch (_e) {
    }
    this.stepIndex -= 1
  }

  private isVoiceEnabled(): boolean {
    return AppStorage.get<number>(AppStorageKeys.VOICE_MODE_ENABLED) === 1
  }

  private speakStep(step: number): void {
    if (this.readonly || !this.isVoiceEnabled()) {
      return
    }
    if (step < 0 || step >= STEP_TOTAL) {
      return
    }
    const narrations: string[] = numberLineStepNarrations(this.start, this.step, this.op)
    const text: string = narrations[step]
    if (text === '') {
      return
    }
    this.startedSpeak = true
    ServiceRegistry.tts().stop()
    ServiceRegistry.tts().speak(normalizeMathSymbolsForTts(text), {
      onStart: () => {},
      onComplete: () => {},
      onError: (_error: string) => {}
    }).catch((_e: Error) => {})
  }

  private animateToken(target: number): void {
    if (this.bounceTimerId >= 0) {
      clearTimeout(this.bounceTimerId)
      this.bounceTimerId = -1
    }
    this.getUIContext().animateTo({ duration: HOP_DURATION_MS, curve: Curve.EaseInOut }, (): void => {
      this.tokenValue = target
    })
    this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, (): void => {
      this.tokenLift = 16
    })
    this.bounceTimerId = setTimeout((): void => {
      this.bounceTimerId = -1
      this.getUIContext().animateTo({ duration: 320, curve: Curve.EaseIn }, (): void => {
        this.tokenLift = 0
      })
    }, BOUNCE_UP_MS)
  }

  private tapHop1(): void {
    if (this.readonly || this.hop1Done) {
      return
    }
    this.hop1Done = true
    this.markStepDone(0)
    this.animateToken(10)
  }

  private tapHop2(): void {
    if (this.readonly || this.hop2Done) {
      return
    }
    this.hop2Done = true
    this.markStepDone(1)
    this.animateToken(this.hops.end)
  }

  @Builder
  DemoButton(label: string, accessibility: string, onTap: () => void) {
    Button(label)
      .width(200).height(44)
      .backgroundColor(KIDS_MATH_INK).fontSize(14)
      .accessibilityText(accessibility)
      .onClick(() => {
        onTap()
      })
  }

  @Builder
  AxisBoard() {
    Stack() {
      Circle()
        .width(16).height(16)
        .fill(withColorAlpha(KIDS_STAR, '2E'))
        .stroke(KIDS_STAR).strokeWidth(2)
        .position({ x: this.px(10) - 8, y: this.py(NUMBER_LINE_BASE_Y) - 8 })

      Line()
        .width('100%').height('100%')
        .startPoint([this.px(0), this.py(NUMBER_LINE_BASE_Y)])
        .endPoint([this.px(NUMBER_LINE_MAX), this.py(NUMBER_LINE_BASE_Y)])
        .stroke(KIDS_MUTED).strokeWidth(2).strokeLineCap(LineCapStyle.Round)

      ForEach(this.seq(NUMBER_LINE_MAX + 1), (i: number) => {
        Line()
          .width('100%').height('100%')
          .startPoint([this.px(i), this.py(NUMBER_LINE_BASE_Y)])
          .endPoint([this.px(i), this.py(NUMBER_LINE_BASE_Y + (i % 5 === 0 ? 10 : 5))])
          .stroke(i === 10 ? KIDS_STAR : KIDS_BORDER)
          .strokeWidth(i % 5 === 0 ? 2 : 1)
      }, (i: number) => 'tick' + i.toString())

      ForEach(this.fiveTicks(), (v: number) => {
        Text(`${v}`)
          .fontSize(10.5)
          .fontWeight(v === 10 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(v === 10 ? KIDS_ON_GOLD : KIDS_MUTED)
          .textAlign(TextAlign.Center)
          .width(24)
          .position({ x: this.px(v) - 12, y: this.py(NUMBER_LINE_BASE_Y + 11) })
      }, (v: number) => 'num' + v.toString())

      Text('中转站')
        .fontSize(10).fontWeight(FontWeight.Bold).fontColor(KIDS_ON_GOLD)
        .textAlign(TextAlign.Center)
        .width(48)
        .position({ x: this.px(10) - 24, y: this.py(NUMBER_LINE_BASE_Y + 24) })

      if (this.hop1Done) {
        Path()
          .width('100%').height('100%')
          .commands(this.arcCommands(this.hops.x1, this.hops.arc1X, this.hops.arc1Y, this.hops.x2))
          .fill(Color.Transparent)
          .stroke(KIDS_MATH).strokeWidth(2.4).strokeLineCap(LineCapStyle.Round)
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut }))
        Path()
          .width('100%').height('100%')
          .commands(this.arrowCommands(this.hops.arc1X, this.hops.arc1Y, this.hops.x2))
          .fill(KIDS_MATH)
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut }))
        Text(`${this.opSign()}${this.hops.firstHop}`)
          .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
          .textAlign(TextAlign.Center)
          .width(36)
          .position({
            x: this.px(this.hops.arc1X) - 18,
            y: this.py(this.arcApexY(this.hops.arc1Y)) - 18
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut }))
      }

      if (this.hop2Done) {
        Path()
          .width('100%').height('100%')
          .commands(this.arcCommands(this.hops.x2, this.hops.arc2X, this.hops.arc2Y, this.hops.x3))
          .fill(Color.Transparent)
          .stroke(KIDS_ACCENT).strokeWidth(2.4).strokeLineCap(LineCapStyle.Round)
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut }))
        Path()
          .width('100%').height('100%')
          .commands(this.arrowCommands(this.hops.arc2X, this.hops.arc2Y, this.hops.x3))
          .fill(KIDS_ACCENT)
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut }))
        Text(`${this.opSign()}${this.hops.secondHop}`)
          .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_ON_GOLD)
          .textAlign(TextAlign.Center)
          .width(36)
          .position({
            x: this.px(this.hops.arc2X) - 18,
            y: this.py(this.arcApexY(this.hops.arc2Y)) - 18
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut }))
      }

      Stack() {
        Text(`${this.tokenValue}`)
          .fontSize(13).fontWeight(FontWeight.Bold)
          .fontColor(makeTenIsLight(this.tokenColor()) ? '#182135' : Color.White)
      }
      .width(TOKEN_SIZE).height(TOKEN_SIZE)
      .borderRadius(6)
      .backgroundColor(this.tokenColor())
      .border({
        width: 1.5,
        style: BorderStyle.Solid,
        color: makeTenShade(this.tokenColor(), 0.78)
      })
      .position({
        x: this.px(this.tokenValue) - TOKEN_SIZE / 2,
        y: this.py(NUMBER_LINE_BASE_Y) - TOKEN_SIZE - 4 - this.tokenLift * this.boardScale
      })
      .accessibilityText(`小方块现在在 ${this.tokenValue}`)
    }
    .width('100%')
    .aspectRatio(NUMBER_LINE_WIDTH / BOARD_H)
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      const w: number = newValue.width as number
      if (w > 0) {
        this.boardScale = w / NUMBER_LINE_WIDTH
      }
    })
    .accessibilityText(this.hop2Done ? `数轴演示完成，${this.fullEq()}` : `数轴从 ${this.start} 起跳，10 是中转站`)
  }

  @Builder
  EqArea() {
    Column({ space: 4 }) {
      Text(this.currentHint())
        .fontSize(17).fontWeight(FontWeight.Bold)
        .fontColor(this.stepHopDone() ? $r('app.color.status_success') : KIDS_MATH_INK)
        .textAlign(TextAlign.Center)
        .width('100%')
      if (this.hop2Done) {
        Text(this.fullEq())
          .fontSize(18).fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.status_success'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.7, y: 0.7 }))
            .animation({ duration: 300, curve: Curve.EaseOut }))
      }
    }
    .width('100%')
  }

  @Builder
  StepButtons() {
    if (this.stepIndex === 0 && !this.hop1Done) {
      this.DemoButton(this.steps[0].title, '第一跳，跳到中转站 10', (): void => {
        this.tapHop1()
      })
      Text(`点一点，从 ${this.start} 跳到 10。`)
        .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
    }
    if (this.stepIndex === 1 && !this.hop2Done) {
      this.DemoButton(this.steps[0].action, '第二跳，从中转站 10 跳到终点', (): void => {
        this.tapHop2()
      })
    }
  }

  @Builder
  ProgressRow() {
    Row({ space: 10 }) {
      Row({ space: 4 }) {
        ForEach(this.seq(STEP_TOTAL), (i: number) => {
          Circle()
            .width(i === this.stepIndex ? 10 : 6)
            .height(i === this.stepIndex ? 10 : 6)
            .fill(i <= this.stepIndex ? KIDS_MATH : KIDS_BORDER)
        }, (i: number) => 'pd' + i.toString())
      }
      .alignItems(VerticalAlign.Center)

      Text(`第 ${this.stepIndex + 1} / ${STEP_TOTAL} 步 · ${this.stepTitle()}`)
        .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  HopRecord() {
    Column({ space: 2 }) {
      Text('跳一跳记录')
        .fontSize(11).fontWeight(FontWeight.Bold).fontColor(KIDS_MUTED)
        .width('100%')
      ForEach(this.hopRecordLines(), (line: string, idx: number) => {
        Row({ space: 8 }) {
          Text(line)
            .fontSize(12)
            .fontWeight(this.recordLit(idx) ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.recordLit(idx) ? KIDS_MATH_INK : KIDS_MUTED)
          Text(idx === 0 ? '到中转站' : '到终点').fontSize(10).fontColor(KIDS_MUTED)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(7)
        .backgroundColor(this.recordLit(idx) ? withColorAlpha(KIDS_MATH, '10') : '#00000000')
        .opacity(this.recordLit(idx) ? 1 : 0.45)
      }, (line: string) => line)
    }
    .width('100%')
    .padding(8)
    .borderRadius(10)
    .backgroundColor(withColorAlpha(KIDS_FG, '04'))
  }

  @Builder
  NavRow() {
    Row({ space: 12 }) {
      Button('上一步')
        .width(92).height(44).fontSize(14)
        .backgroundColor(withColorAlpha(KIDS_FG, '08'))
        .fontColor(KIDS_MUTED)
        .enabled(this.stepIndex > 0)
        .opacity(this.stepIndex > 0 ? 1 : 0.4)
        .onClick(() => {
          this.goPrev()
        })
      Button(this.stepIndex >= STEP_TOTAL - 1 ? '本课完成' : '下一步')
        .width(120).height(44).fontSize(14)
        .backgroundColor(KIDS_MATH_INK)
        .fontColor(Color.White)
        .enabled(this.navNextEnabled())
        .opacity(this.navNextEnabled() ? 1 : 0.45)
        .onClick(() => {
          this.goNext()
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column({ space: 10 }) {
      this.ProgressRow()
      Text(this.stepTitle())
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)
      Text(this.stepGuide())
        .fontSize(12).fontColor(KIDS_SUBTLE).textAlign(TextAlign.Center)
      Column() {
        this.AxisBoard()
      }
      .width('100%')
      .padding(8)
      .borderRadius(12)
      .backgroundColor(KIDS_SURFACE)
      .border({
        width: 1.5,
        style: BorderStyle.Dashed,
        color: withColorAlpha(KIDS_MATH, '38')
      })
      this.EqArea()
      if (!this.readonly) {
        this.StepButtons()
        this.NavRow()
      }
      this.HopRecord()
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}