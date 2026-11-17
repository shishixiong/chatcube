import {
  shapePropsSteps, shapePropsVertices, shapePropsEdges, shapePropsSummary,
  ShapePropsStep, ShapePropsEdge
} from '../../utils/MathTeachShapeProps'
import { AppStorageKeys } from '../../config/AppStorageKeys'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { normalizeMathSymbolsForTts } from '../../utils/TtsTextUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  KIDS_MATH, KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED, KIDS_BORDER,
  KIDS_FG, KIDS_SUBTLE, KIDS_STAR, KIDS_ON_GOLD, KIDS_CHINESE_INK
} from '../kids/KidsBrandTokens'

/**
 * ShapePropsBoard - 图形特征三步演示课（math_teach · shape_props 模式）
 *
 * 认一认（图形 + 名称）→ 数边（逐条金色高亮，计数 1..n）→ 数角（逐个红点高亮）。
 * 顶点几何由 utils/MathTeachShapeProps 算清，板面只用 Polygon + Line + Circle 绘图，
 * 保证「边可数、角可数、边角数与真值一致」——文字符号 △⬠ 的边角画不准，已弃用。
 *
 * 完成门：三步各计一次动手（认一认 / 数边 / 数角），shell 层 interactionThreshold 配 3。
 * 末步「本课完成」可提前结课。
 *
 * TTS：语音模式开启时（AppStorage VOICE_MODE_ENABLED）进入每步朗读该步口播稿；
 * 回退 / 离开即 stop；已答历史态不播。
 */

const STEP_TOTAL: number = 3
const SHAPE_BOX: number = 160
const REVEAL_INTERVAL_MS: number = 280

@ComponentV2
export struct ShapePropsBoard {
  @Param shape: string = 'square'
  @Param readonly: boolean = false
  @Event onInteract: () => void = () => {}
  @Event onFinish: () => void = () => {}

  @Local stepIndex: number = 0
  @Local nameShown: boolean = false
  @Local edgesShown: number = 0
  @Local cornersShown: number = 0

  private steps: ShapePropsStep[] = []
  private vertices: number[][] = []
  private edges: ShapePropsEdge[] = []
  // 已计完成的步骤（非响应式守卫：重访已完成步骤不重复上报 onInteract）
  private stepDoneFlags: boolean[] = [false, false, false]
  private startedSpeak: boolean = false
  private revealTimerId: number = -1

  aboutToAppear(): void {
    this.steps = shapePropsSteps(this.shape)
    this.vertices = shapePropsVertices(this.shape, SHAPE_BOX)
    this.edges = shapePropsEdges(this.shape, SHAPE_BOX)
    if (this.readonly) {
      // 已答历史态：直接渲染完成态（草稿纸语义，不恢复孩子离开时的中间过程）
      this.nameShown = true
      this.edgesShown = this.edges.length
      this.cornersShown = this.vertices.length
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
    // 只有本板真正播过语音才 stop——历史 readonly 卡片滚出视口时不误杀在播语音
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

  private sideCount(): number {
    return this.edges.length
  }

  private stepTitle(): string {
    if (this.steps.length === 0) {
      return '图形特征'
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

  /** 当前应高亮多少条边（数边步随计数逐条亮；数角步全部保持亮） */
  private visibleEdgeCount(): number {
    return this.edgesShown
  }

  private visibleCornerCount(): number {
    return this.cornersShown
  }

  private revealedEdges(): ShapePropsEdge[] {
    const arr: ShapePropsEdge[] = []
    const upTo: number = Math.min(this.visibleEdgeCount(), this.edges.length)
    for (let i = 0; i < upTo; i++) {
      arr.push(this.edges[i])
    }
    return arr
  }

  private revealedCorners(): number[][] {
    const arr: number[][] = []
    const upTo: number = Math.min(this.visibleCornerCount(), this.vertices.length)
    for (let i = 0; i < upTo; i++) {
      arr.push(this.vertices[i])
    }
    return arr
  }

  private countedChips(): number[] {
    if (this.stepIndex === 1) {
      return this.seq(this.edgesShown)
    }
    if (this.stepIndex === 2) {
      return this.seq(this.cornersShown)
    }
    return []
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
      return this.nameShown
    }
    if (this.stepIndex === 1) {
      return this.edgesShown >= this.edges.length
    }
    return true
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
    if (this.stepIndex === 0) {
      return '数边'
    }
    return '数角'
  }

  // ── 导航 ─────────────────────────────────────────────────────────

  private goNext(): void {
    if (this.readonly) {
      return
    }
    if (this.stepIndex >= STEP_TOTAL - 1) {
      // 末步「本课完成」：动画没看完也接受本次授课，再通知 shell 直接提交（submit 幂等）
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

  private tapName(): void {
    if (this.readonly || this.nameShown) {
      return
    }
    this.nameShown = true
    this.markStepDone(0)
  }

  private tapCountEdges(): void {
    if (this.readonly || this.edges.length === 0) {
      return
    }
    if (this.edgesShown >= this.edges.length || this.revealTimerId >= 0) {
      return
    }
    this.edgesShown = 1
    this.tickEdges()
    this.markStepDone(1)
  }

  private tickEdges(): void {
    if (this.edgesShown >= this.edges.length) {
      this.revealTimerId = -1
      return
    }
    this.revealTimerId = setTimeout(() => {
      this.edgesShown += 1
      this.tickEdges()
    }, REVEAL_INTERVAL_MS)
  }

  private tapCountCorners(): void {
    if (this.readonly || this.vertices.length === 0) {
      return
    }
    if (this.cornersShown >= this.vertices.length || this.revealTimerId >= 0) {
      return
    }
    this.cornersShown = 1
    this.tickCorners()
    this.markStepDone(2)
  }

  private tickCorners(): void {
    if (this.cornersShown >= this.vertices.length) {
      this.revealTimerId = -1
      return
    }
    this.revealTimerId = setTimeout(() => {
      this.cornersShown += 1
      this.tickCorners()
    }, REVEAL_INTERVAL_MS)
  }

  // ── 小件 ─────────────────────────────────────────────────────────

  @Builder
  ShapeStage() {
    Stack() {
      if (this.vertices.length > 0) {
        Polygon({ width: SHAPE_BOX, height: SHAPE_BOX })
          .points(this.vertices)
          .fill(withColorAlpha(KIDS_MATH, '14'))
          .stroke(KIDS_MATH)
          .strokeWidth(2.5)
      }
      ForEach(this.revealedEdges(), (e: ShapePropsEdge, idx: number) => {
        Line({ width: SHAPE_BOX, height: SHAPE_BOX })
          .startPoint([e.x1, e.y1]).endPoint([e.x2, e.y2])
          .stroke(KIDS_STAR)
          .strokeWidth(5)
          .strokeLineCap(LineCapStyle.Round)
          .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
      }, (e: ShapePropsEdge, idx: number) => 'edge' + idx.toString())
      ForEach(this.revealedCorners(), (p: number[], idx: number) => {
        Circle()
          .width(16).height(16)
          .fill(KIDS_CHINESE_INK)
          .position({ x: p[0] - 8, y: p[1] - 8 })
          .transition(TransitionEffect.scale({ x: 0.3, y: 0.3 })
            .combine(TransitionEffect.OPACITY)
            .animation({ duration: 220, curve: Curve.EaseOut }))
      }, (p: number[], idx: number) => 'corner' + idx.toString())
    }
    .width(SHAPE_BOX).height(SHAPE_BOX)
  }

  @Builder
  NameChip() {
    Text(this.steps[0].chip)
      .fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
      .padding({ left: 14, right: 14, top: 5, bottom: 5 })
      .borderRadius(12)
      .backgroundColor(withColorAlpha(KIDS_MATH, '14'))
      .border({ width: 1.5, style: BorderStyle.Solid, color: withColorAlpha(KIDS_MATH, '4D') })
  }

  @Builder
  FeatureChip() {
    if (this.sideCount() > 0) {
      Text(shapePropsSummary(this.shape))
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor(KIDS_ON_GOLD)
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .borderRadius(10)
        .backgroundColor(withColorAlpha(KIDS_ACCENT, '20'))
        .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha(KIDS_ACCENT, '66') })
    }
  }

  @Builder
  CountChips() {
    if (this.countedChips().length > 0) {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(this.countedChips(), (i: number) => {
          Text(`${i + 1}`)
            .fontSize(12).fontWeight(FontWeight.Bold).fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .width(24).height(24)
            .borderRadius(12)
            .margin(3)
            .backgroundColor(this.stepIndex === 1 ? KIDS_ON_GOLD : KIDS_CHINESE_INK)
            .transition(TransitionEffect.scale({ x: 0.4, y: 0.4 })
              .combine(TransitionEffect.OPACITY)
              .animation({ duration: 220, curve: Curve.EaseOut }))
        }, (i: number) => 'chip' + i.toString())
      }
      .width('100%')
    }
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

  // ── 3 步主体 ─────────────────────────────────────────────────────

  @Builder
  StepBody() {
    if (this.steps.length === 0) {
      Text('这个图形暂时不能数边角，老师换一个图形')
        .fontSize(13).fontColor(KIDS_MUTED)
        .padding({ top: 8, bottom: 8 })
    } else if (this.stepIndex === 0) {
      Column({ space: 8 }) {
        if (this.nameShown) {
          this.NameChip()
          Text('边是一条直的线，角是两条边碰头的地方。')
            .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
        } else {
          this.DemoButton(this.stepAction(), '看图形叫什么名字', (): void => {
            this.tapName()
          })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    } else if (this.stepIndex === 1) {
      Column({ space: 8 }) {
        this.CountChips()
        if (this.edgesShown < this.edges.length) {
          this.DemoButton(this.stepAction(), '一条一条数出图形的边', (): void => {
            this.tapCountEdges()
          })
        } else {
          Text(`一共 ${this.sideCount()} 条边`)
            .fontSize(13).fontWeight(FontWeight.Bold).fontColor(KIDS_ON_GOLD)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    } else {
      Column({ space: 8 }) {
        this.CountChips()
        if (this.cornersShown < this.vertices.length) {
          this.DemoButton(this.stepAction(), '一个一个数出图形的角', (): void => {
            this.tapCountCorners()
          })
        } else {
          Text(`一共 ${this.vertices.length} 个角`)
            .fontSize(13).fontWeight(FontWeight.Bold).fontColor(KIDS_CHINESE_INK)
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
      this.ShapeStage()
      this.FeatureChip()
      this.StepBody()
      if (!this.readonly && this.steps.length > 0) {
        this.NavRow()
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}