import {
  fractionIntroSteps, fractionSectorCommands, fractionBarSegments, fractionReadout, fractionReadoutZh,
  normalizeFractionForm, clampFractionParts, clampFractionShaded,
  FractionIntroStep, BarSegment
} from '../../utils/MathTeachFractionIntro'
import { AppStorageKeys } from '../../config/AppStorageKeys'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { normalizeMathSymbolsForTts } from '../../utils/TtsTextUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  KIDS_MATH, KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED, KIDS_BORDER,
  KIDS_SURFACE, KIDS_FG, KIDS_SUBTLE, KIDS_ON_GOLD, KIDS_STAR
} from '../kids/KidsBrandTokens'

/**
 * FractionIntroBoard - 分数初步认识两步演示课（math_teach · fraction_intro 模式）
 *
 * 平均分（整圆/长条被切成 parts 个同样大的扇形/等分格）→ 取几份（逐份涂橙 +
 * 分数记号 3/4 浮现 + 读法「四分之三」）。只有平均分才能用分数。
 *
 * 载体双形态：form=pizza 扇形（Path M/L/A/Z）、form=bar 分数条（等分 Rect），
 * 几何由 utils/MathTeachFractionIntro 算清，quiz 卡片复用同一份函数。
 *
 * 完成门：两步各计一次动手（平均分 / 取几份），shell 层 interactionThreshold 配 2。
 * 末步「本课完成」可提前结课。
 *
 * TTS：语音模式开启时（AppStorage VOICE_MODE_ENABLED）进入每步朗读该步口播稿；
 * 回退 / 离开即 stop；已答历史态不播。
 */

const STEP_TOTAL: number = 2
const PIZZA_BOX: number = 168
const BAR_W: number = 260
const BAR_H: number = 56
const SHADE_INTERVAL_MS: number = 260

@ComponentV2
export struct FractionIntroBoard {
  @Param parts: number = 4
  @Param shaded: number = 3
  @Param form: string = 'pizza'
  @Param readonly: boolean = false
  @Event onInteract: () => void = () => {}
  @Event onFinish: () => void = () => {}

  @Local stepIndex: number = 0
  // 平均分已完成（切割线全部出现）
  @Local cutShown: boolean = false
  // 已涂色份数（取几份的逐份动画）
  @Local shadedShown: number = 0

  private steps: FractionIntroStep[] = []
  private totalParts: number = 4
  private totalShaded: number = 3
  private stepDoneFlags: boolean[] = [false, false]
  private startedSpeak: boolean = false
  private revealTimerId: number = -1

  aboutToAppear(): void {
    this.totalParts = clampFractionParts(this.parts)
    this.totalShaded = clampFractionShaded(this.totalParts, this.shaded)
    this.steps = fractionIntroSteps(this.totalParts, this.totalShaded, this.form)
    if (this.readonly) {
      // 已答历史态：渲染完成态（全部切好、全部涂色）
      this.cutShown = true
      this.shadedShown = this.totalShaded
      this.stepIndex = STEP_TOTAL - 1
      return
    }
    this.speakStep(0)
  }

  aboutToDisappear(): void {
    if (this.revealTimerId >= 0) {
      clearTimeout(this.revealTimerId)
      this.revealTimerId = -1
    }
    if (this.startedSpeak) {
      try {
        ServiceRegistry.tts().stop()
      } catch (_e) {
      }
    }
  }

  // ── 派生值 ───────────────────────────────────────────────────────

  private seq(n: number): number[] {
    const arr: number[] = []
    for (let i = 0; i < n; i++) {
      arr.push(i)
    }
    return arr
  }

  private isBar(): boolean {
    return normalizeFractionForm(this.form) === 'bar'
  }

  private stepTitle(): string {
    if (this.steps.length === 0) {
      return '分数初步认识'
    }
    if (this.stepIndex < 0 || this.stepIndex >= this.steps.length) {
      return this.steps[0].title
    }
    return this.steps[this.stepIndex].title
  }

  private stepTip(): string {
    if (this.steps.length === 0) {
      return ''
    }
    if (this.stepIndex < 0 || this.stepIndex >= this.steps.length) {
      return this.steps[0].hint
    }
    return this.steps[this.stepIndex].hint
  }

  private stepAction(): string {
    if (this.steps.length === 0) {
      return ''
    }
    if (this.stepIndex < 0 || this.stepIndex >= this.steps.length) {
      return this.steps[0].action
    }
    return this.steps[this.stepIndex].action
  }

  private pizzaRadius(): number {
    return PIZZA_BOX * 0.46
  }

  private barSegments(): BarSegment[] {
    return fractionBarSegments(this.totalParts, BAR_W)
  }

  private readout(): string {
    return fractionReadout(this.totalParts, this.totalShaded)
  }

  private readoutZh(): string {
    return fractionReadoutZh(this.totalParts, this.totalShaded)
  }

  // ── 完成门 ───────────────────────────────────────────────────────

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
      return this.cutShown
    }
    return this.shadedShown >= this.totalShaded
  }

  private navNextEnabled(): boolean {
    if (this.stepIndex === STEP_TOTAL - 1) {
      return true
    }
    return this.canAdvance()
  }

  private navNextLabel(): string {
    if (this.stepIndex === STEP_TOTAL - 1) {
      return '本课完成'
    }
    return this.stepAction()
  }

  // ── 导航 ─────────────────────────────────────────────────────────

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

  // ── TTS ──────────────────────────────────────────────────────────

  private isVoiceEnabled(): boolean {
    return AppStorage.get<number>(AppStorageKeys.VOICE_MODE_ENABLED) === 1
  }

  private speakStep(step: number): void {
    if (this.readonly || !this.isVoiceEnabled()) {
      return
    }
    if (step < 0 || step >= this.steps.length) {
      return
    }
    const text: string = this.steps[step].narration
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

  // ── 交互 ─────────────────────────────────────────────────────────

  private tapCut(): void {
    if (this.readonly || this.cutShown) {
      return
    }
    this.cutShown = true
    this.markStepDone(0)
  }

  private tapShade(): void {
    if (this.readonly || this.totalShaded <= 0) {
      return
    }
    if (this.shadedShown >= this.totalShaded || this.revealTimerId >= 0) {
      return
    }
    this.shadedShown = 1
    this.tickShade()
    this.markStepDone(1)
  }

  private tickShade(): void {
    if (this.shadedShown >= this.totalShaded) {
      this.revealTimerId = -1
      return
    }
    this.revealTimerId = setTimeout(() => {
      this.shadedShown += 1
      this.tickShade()
    }, SHADE_INTERVAL_MS)
  }

  // ── 图形 ─────────────────────────────────────────────────────────

  @Builder
  PizzaFigure() {
    Stack() {
      if (!this.cutShown) {
        Circle()
          .width(PIZZA_BOX * 0.92).height(PIZZA_BOX * 0.92)
          .fill(KIDS_SURFACE)
          .stroke(KIDS_BORDER).strokeWidth(2)
          .position({ x: PIZZA_BOX * 0.04, y: PIZZA_BOX * 0.04 })
      } else {
        ForEach(this.seq(this.totalParts), (i: number) => {
          Path()
            .width('100%').height('100%')
            .commands(fractionSectorCommands(this.totalParts, i, PIZZA_BOX))
            .fill(i < this.shadedShown ? KIDS_ACCENT : KIDS_SURFACE)
            .stroke(KIDS_BORDER)
            .strokeWidth(1.5)
            .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }))
        }, (i: number) => 'sector' + i.toString() + '_' + this.totalParts.toString() +
          '_' + this.shadedShown.toString())
      }
    }
    .width(PIZZA_BOX).height(PIZZA_BOX)
  }

  @Builder
  BarFigure() {
    Stack() {
      if (!this.cutShown) {
        Rect({ width: BAR_W, height: BAR_H })
          .fill(KIDS_SURFACE)
          .stroke(KIDS_BORDER).strokeWidth(2)
          .radius(8)
      } else {
        ForEach(this.barSegments(), (seg: BarSegment, i: number) => {
          Rect({ width: seg.w, height: BAR_H })
            .fill(i < this.shadedShown ? KIDS_ACCENT : KIDS_SURFACE)
            .stroke(KIDS_BORDER).strokeWidth(1.5)
            .position({ x: seg.x, y: 0 })
            .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }))
        }, (seg: BarSegment, i: number) => 'bseg' + i.toString() + '_' + this.shadedShown.toString())
      }
    }
    .width(BAR_W).height(BAR_H)
  }

  @Builder
  FigureStub() {
    if (this.isBar()) {
      this.BarFigure()
    } else {
      this.PizzaFigure()
    }
  }

  @Builder
  FractionNotation() {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(`${this.totalShaded}`)
          .fontSize(24).fontWeight(FontWeight.Bold).fontColor(KIDS_ON_GOLD)
        Divider()
          .width(26).strokeWidth(2).color(KIDS_MATH_INK)
        Text(`${this.totalParts}`)
          .fontSize(24).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
      }
      .alignItems(HorizontalAlign.Center)

      Column({ space: 3 }) {
        Text('读作')
          .fontSize(11).fontColor(KIDS_MUTED)
        Text(this.readoutZh())
          .fontSize(16).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)
      }
      .alignItems(HorizontalAlign.Start)
    }
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .borderRadius(12)
    .backgroundColor(withColorAlpha(KIDS_ACCENT, '1A'))
    .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha(KIDS_ACCENT, '59') })
  }

  @Builder
  ReadoutChip() {
    Text(`${this.readout()} 读作${this.readoutZh()}`)
      .fontSize(13).fontWeight(FontWeight.Bold).fontColor(KIDS_ON_GOLD)
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .borderRadius(10)
      .backgroundColor(withColorAlpha(KIDS_STAR, '20'))
      .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha(KIDS_STAR, '60') })
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

  // ── 2 步主体 ─────────────────────────────────────────────────────

  @Builder
  StepBody() {
    if (this.steps.length === 0) {
      Text('这块分数板出错了，老师马上换一张')
        .fontSize(13).fontColor(KIDS_MUTED)
        .padding({ top: 8, bottom: 8 })
    } else if (this.stepIndex === 0) {
      Column({ space: 8 }) {
        if (this.cutShown) {
          Text(`平均分成 ${this.totalParts} 份，每份一样大`)
            .fontSize(13).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
          Text('只有每一份都同样大，才能用分数表示。')
            .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
        } else {
          this.DemoButton(this.stepAction(), '把整体平均分成几份', (): void => {
            this.tapCut()
          })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    } else {
      Column({ space: 8 }) {
        if (this.shadedShown < this.totalShaded) {
          this.DemoButton(this.stepAction(), '取几份涂色', (): void => {
            this.tapShade()
          })
        } else {
          this.FractionNotation()
          Text(`分母 ${this.totalParts} 是平均分的份数，分子 ${this.totalShaded} 是取的份数。`)
            .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
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
  NavRow() {
    Row({ space: 12 }) {
      Button('上一步')
        .width(92).height(40).fontSize(14)
        .backgroundColor(withColorAlpha(KIDS_FG, '08'))
        .fontColor(KIDS_MUTED)
        .enabled(this.stepIndex > 0)
        .opacity(this.stepIndex > 0 ? 1 : 0.4)
        .onClick(() => {
          this.goPrev()
        })
      Button(this.navNextLabel())
        .width(120).height(40).fontSize(14)
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
      if (this.steps.length > 0) {
        this.ProgressRow()
      }
      Text(this.stepTitle())
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)
      if (this.stepTip() !== '') {
        Text(this.stepTip())
          .fontSize(12).fontColor(KIDS_SUBTLE).textAlign(TextAlign.Center)
      }
      this.FigureStub()
      if (this.stepIndex === 1 && this.shadedShown >= this.totalShaded) {
        this.ReadoutChip()
      }
      this.StepBody()
      if (!this.readonly && this.steps.length > 0) {
        this.NavRow()
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}