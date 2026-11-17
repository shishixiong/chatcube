import {
  placeValueRead, placeValueAddToTen, canBundle, placeValueAfter,
  placeValueSteps, placeValueStepNarrations,
  PlaceValueState, PlaceValueStep
} from '../../utils/MathTeachPlaceValue'
import { AppStorageKeys } from '../../config/AppStorageKeys'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { normalizeMathSymbolsForTts } from '../../utils/TtsTextUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  KIDS_MATH, KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED, KIDS_BORDER,
  KIDS_SURFACE, KIDS_FG, KIDS_ON_GOLD, KIDS_STAR, KIDS_SUBTLE
} from '../kids/KidsBrandTokens'

/**
 * PlaceValueBoard - 小棒与数位两步演示课（math_teach · place_value 模式）
 *
 * spec 2026-11-17 P0 三板 §4.3，镜像 NumberBondBoard v2 两步演示课结构：
 * 第 1 步「数一数」进入即计一次动手；第 2 步演示按钮（bundle「添棒凑十」/
 * unbundle「拆一捆」，文案取 placeValueSteps 的 action 字段）触发动画并计
 * 一次动手；动画完成后「本课完成」可结课（markStepDone 幂等守卫防重复计数）。
 *
 * 板面：左十位列（捆装小棒束）+ 右个位列（散棒），下方读数 chip
 * 「tens 捆 ones 根 = read」。bundle：添棒逐根弹入 → 满十 → 捆扎收拢飞入
 * 十位；unbundle：十位 1 捆拆散成 10 根逐根弹入，强调「总数不变」。
 *
 * TTS：语音模式开启时（AppStorage VOICE_MODE_ENABLED，与 TenFrameBoard /
 * NumberBondBoard 同一开关），进入每步朗读该步口播稿；回退/离开即 stop。
 * 已答历史态（readonly）直接渲染 placeValueAfter 完成态，不播、控制区隐藏。
 */

const STEP_TOTAL: number = 2
const ADD_INTERVAL_MS: number = 300
const BUNDLE_PAUSE_MS: number = 600
const UNBUNDLE_MOVE_MS: number = 500
const SPREAD_INTERVAL_MS: number = 120

@ComponentV2
export struct PlaceValueBoard {
  @Param tens: number = 2
  @Param ones: number = 8
  @Param action: string = 'bundle'
  @Param readonly: boolean = false
  @Event onInteract: () => void = () => {}
  // 末步「本课完成」直通提交：shell 收到后走 submit()（其内部有已提交/门槛守卫）
  @Event onFinish: () => void = () => {}

  @Local stepIndex: number = 0
  // 第 2 步已点演示按钮（按钮隐藏，动画进行中或已完成）
  @Local demoStarted: boolean = false
  // bundle：已添入的散棒数（0..add）；unbundle：已散开的散棒数（0..10）
  @Local addedCount: number = 0
  // 动画完成（bundle 捆扎完毕 / unbundle 10 根散尽），「本课完成」放行
  @Local animDone: boolean = false

  // 步骤数据与完成态（aboutToAppear 一次算定；tens/ones/action 固定不变）
  private steps: PlaceValueStep[] = []
  private after: PlaceValueState = { tens: 0, ones: 0 }
  // 已计完成的步骤（非响应式守卫：重访已完成步骤不重复上报 onInteract）
  private stepDoneFlags: boolean[] = [false, false]
  private startedSpeak: boolean = false
  private timerId: number = -1

  aboutToAppear(): void {
    this.steps = placeValueSteps(this.tens, this.ones, this.action)
    this.after = placeValueAfter(this.tens, this.ones, this.action)
    if (this.readonly) {
      // 已答历史态：直接渲染完成态（草稿纸语义，不恢复孩子离开时的中间过程）
      this.stepIndex = STEP_TOTAL - 1
      this.demoStarted = true
      this.animDone = true
      this.addedCount = this.action === 'unbundle' ? 10 : placeValueAddToTen(this.ones)
      return
    }
    // 第 1 步「数一数」进入即计一次动手（完成门 2 的第 1 次）
    this.markStepDone(0)
    this.speakStep(0)
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId)
      this.timerId = -1
    }
    // 只有本板真正播过语音才 stop——历史 readonly 卡片滚出视口时不误杀在播语音
    if (this.startedSpeak) {
      try {
        ServiceRegistry.tts().stop()
      } catch (_e) {
      }
    }
  }

  // ── 派生值（Builder 内调用保持响应式，不传快照）──────────────────

  private seq(n: number): number[] {
    const arr: number[] = []
    for (let i = 0; i < n; i++) {
      arr.push(i)
    }
    return arr
  }

  private isUnbundle(): boolean {
    return this.action === 'unbundle'
  }

  /** 十位列当前捆数：bundle 捆扎完成 +1；unbundle 点拆即 -1（捆飞入个位）。 */
  private tensShown(): number {
    if (this.isUnbundle()) {
      return this.demoStarted ? this.after.tens : this.tens
    }
    return this.animDone ? this.after.tens : this.tens
  }

  /** 个位列当前散棒数：bundle 捆扎完成清空；其余 = 原有 + 已添/已散。 */
  private onesShown(): number {
    if (!this.isUnbundle() && this.animDone) {
      return this.after.ones
    }
    return this.ones + this.addedCount
  }

  private readShown(): number {
    return placeValueRead(this.tensShown(), this.onesShown())
  }

  private stepTitle(): string {
    return this.steps[this.stepIndex].title
  }

  private stepChip(): string {
    return this.steps[this.stepIndex].chip
  }

  private stepNarration(): string {
    return this.steps[this.stepIndex].narration
  }

  private stepHint(): string {
    return this.steps[this.stepIndex].hint
  }

  /** 第 2 步演示按钮文案：来自 placeValueSteps 第 1 步的 action 字段。 */
  private demoLabel(): string {
    return this.steps[0].action
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

  // ── 导航 ─────────────────────────────────────────────────────────

  private goNext(): void {
    if (this.readonly) {
      return
    }
    if (this.stepIndex >= STEP_TOTAL - 1) {
      // 末步「本课完成」：演示按钮已计过一次（stepDoneFlags 幂等守卫），
      // 再通知 shell 直接提交——submit() 内部守卫保证幂等。
      this.markStepDone(STEP_TOTAL - 1)
      this.onFinish()
      return
    }
    this.stepIndex += 1
    this.speakStep(this.stepIndex)
  }

  /** 第 1 步数一数进入即完成，直接放行；末步须动画完成才出「本课完成」。 */
  private navNextEnabled(): boolean {
    if (this.stepIndex === STEP_TOTAL - 1) {
      return this.animDone
    }
    return true
  }

  private goPrev(): void {
    if (this.readonly || this.stepIndex <= 0) {
      return
    }
    // 回退后正在播的旁白已过时，直接停掉（同 NumberBondBoard 语义）
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
    if (step < 0 || step >= STEP_TOTAL) {
      return
    }
    const narrations: string[] = placeValueStepNarrations(this.tens, this.ones, this.action)
    const text: string = narrations[step]
    if (text === '') {
      return
    }
    this.startedSpeak = true
    // 步骤旁白接管所有在播语音，让孩子听到的是刚进入的这一步。
    ServiceRegistry.tts().stop()
    ServiceRegistry.tts().speak(normalizeMathSymbolsForTts(text), {
      onStart: () => {},
      onComplete: () => {},
      onError: (_error: string) => {}
    }).catch((_e: Error) => {})
  }

  // ── 交互与动画级联 ───────────────────────────────────────────────

  private tapDemo(): void {
    if (this.readonly || this.demoStarted) {
      return
    }
    this.demoStarted = true
    this.markStepDone(1)
    if (this.isUnbundle()) {
      // 先留 500ms 让十位那捆「飞走」（消失过渡），再逐根散开
      this.timerId = setTimeout(() => {
        this.spreadTick()
      }, UNBUNDLE_MOVE_MS)
    } else {
      this.addTick()
    }
  }

  /** bundle：逐根添棒 → 满十停顿 → 捆扎（10 根收拢消失、十位新捆弹入）。 */
  private addTick(): void {
    const target: number = placeValueAddToTen(this.ones)
    if (this.addedCount >= target) {
      this.timerId = setTimeout(() => {
        this.timerId = -1
        this.animDone = true
      }, BUNDLE_PAUSE_MS)
      return
    }
    this.timerId = setTimeout(() => {
      this.addedCount += 1
      this.addTick()
    }, ADD_INTERVAL_MS)
  }

  /** unbundle：拆下的 1 捆逐根散开成 10 根，散尽即完成。 */
  private spreadTick(): void {
    if (this.addedCount >= 10) {
      this.timerId = -1
      this.animDone = true
      return
    }
    this.timerId = setTimeout(() => {
      this.addedCount += 1
      this.spreadTick()
    }, SPREAD_INTERVAL_MS)
  }

  // ── 通用小件 ─────────────────────────────────────────────────────

  /** 一捆小棒：5 根竖棒示意 + 中间一道捆扎绳（Row/Stack 组合图形）。 */
  @Builder
  BundleGlyph() {
    Stack() {
      Row({ space: 2 }) {
        ForEach(this.seq(5), (i: number) => {
          Column()
            .width(4).height(46)
            .borderRadius(2)
            .backgroundColor(KIDS_MATH)
        }, (i: number) => 'bs' + i.toString())
      }
      .alignItems(VerticalAlign.Center)

      Column()
        .width(32).height(7)
        .borderRadius(3.5)
        .backgroundColor(KIDS_ACCENT)
        .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha(KIDS_ON_GOLD, '50') })
    }
    .width(36).height(50)
  }

  /** 十位列：捆装小棒束，新捆弹入（捆扎完成 / 拆捆飞走都有过渡）。 */
  @Builder
  TensColumn() {
    Column({ space: 6 }) {
      Text('十位')
        .fontSize(13).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(this.seq(this.tensShown()), (i: number) => {
          Column() {
            this.BundleGlyph()
          }
          .margin(3)
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.4, y: 0.4 }))
            .combine(TransitionEffect.translate({ x: 40 }))
            .animation({ duration: 320, curve: Curve.EaseOut }))
        }, (i: number) => 'b' + i.toString())
      }
      .width('100%')
      .layoutWeight(1)

      Text(`${this.tensShown()} 捆`)
        .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_MUTED)
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: 150 })
    .padding(8)
    .borderRadius(12)
    .backgroundColor(KIDS_SURFACE)
    .border({ width: 1.5, style: BorderStyle.Dashed, color: withColorAlpha(KIDS_MATH, '55') })
  }

  /** 个位列：散棒（原有蓝 / 添入或散开橙），逐根弹入、捆扎时收拢消失。 */
  @Builder
  OnesColumn() {
    Column({ space: 6 }) {
      Text('个位')
        .fontSize(13).fontWeight(FontWeight.Bold).fontColor(KIDS_ON_GOLD)
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(this.seq(this.onesShown()), (i: number) => {
          Column()
            .width(8).height(48)
            .borderRadius(4)
            .margin(3)
            .backgroundColor(i < this.ones ? KIDS_MATH : KIDS_ACCENT)
            .transition(TransitionEffect.OPACITY
              .combine(TransitionEffect.scale({ x: 0.3, y: 0.3 }))
              .animation({ duration: 240, curve: Curve.EaseOut }))
        }, (i: number) => 's' + i.toString())
      }
      .width('100%')
      .layoutWeight(1)

      Text(`${this.onesShown()} 根`)
        .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_MUTED)
    }
    .layoutWeight(1)
    .constraintSize({ minHeight: 150 })
    .padding(8)
    .borderRadius(12)
    .backgroundColor(KIDS_SURFACE)
    .border({ width: 1.5, style: BorderStyle.Dashed, color: withColorAlpha(KIDS_ACCENT, '55') })
  }

  /** 读数 chip：「tens 捆 ones 根 = read」，随动画实时更新。 */
  @Builder
  ReadChip() {
    Text(`${this.tensShown()} 捆 ${this.onesShown()} 根 = ${this.readShown()}`)
      .fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(11)
      .backgroundColor(withColorAlpha(KIDS_MATH, '10'))
      .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha(KIDS_MATH, '38') })
      .accessibilityText(`现在是 ${this.tensShown()} 捆 ${this.onesShown()} 根，读作 ${this.readShown()}`)
  }

  /** 过程状态 chip：满十提示 / 拆捆进行中 / 总数不变（金章）。 */
  @Builder
  StatusChip() {
    if (!this.isUnbundle() && !this.animDone && canBundle(this.ones + this.addedCount)) {
      Text('满 10 根啦，捆一捆！')
        .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_ON_GOLD)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(9)
        .backgroundColor(withColorAlpha(KIDS_STAR, '20'))
        .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha(KIDS_STAR, '60') })
    }
    if (this.isUnbundle() && this.demoStarted && !this.animDone) {
      Text('1 捆拆成 10 根…')
        .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_ON_GOLD)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(9)
        .backgroundColor(withColorAlpha(KIDS_STAR, '20'))
        .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha(KIDS_STAR, '60') })
    }
    if (this.isUnbundle() && this.animDone) {
      Text(`总数不变，还是 ${this.readShown()}`)
        .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_ON_GOLD)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(9)
        .backgroundColor(withColorAlpha(KIDS_STAR, '20'))
        .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha(KIDS_STAR, '60') })
        .accessibilityText(`拆捆后总数不变，还是 ${this.readShown()}`)
    }
  }

  /** 引导卡：本步口播正文 + 算理 hint（随步骤实时变化）。 */
  @Builder
  GuideCard() {
    Column({ space: 4 }) {
      Text(this.stepNarration())
        .fontSize(13).fontColor(KIDS_FG).lineHeight(20)
      Text(this.stepHint())
        .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(10)
    .borderRadius(10)
    .backgroundColor(withColorAlpha(KIDS_MATH, '08'))
    .border({ width: 1, style: BorderStyle.Dashed, color: withColorAlpha(KIDS_MATH, '38') })
  }

  /** 动画完成后点出竖式联系（spec §4.3 算理一句话）。 */
  @Builder
  WhyBox() {
    Column({ space: 3 }) {
      Text('竖式里的秘密')
        .fontSize(13).fontWeight(FontWeight.Bold).fontColor(KIDS_ON_GOLD)
      Text(this.isUnbundle()
        ? '「借 1 当 10」就是拆这一捆：十位少 1 捆，个位多 10 根，总数不变。'
        : '「进 1」就是这一捆：个位满十捆成 1 捆，放进十位。')
        .fontSize(12.5).fontColor(KIDS_FG).lineHeight(19)
    }
    .alignItems(HorizontalAlign.Start)
    .padding(10)
    .borderRadius(10)
    .backgroundColor(withColorAlpha(KIDS_STAR, '20'))
    .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha(KIDS_STAR, '60') })
    .width('100%')
  }

  /** 演示按钮（第 2 步一个，点一下播动画并计一次动手）。 */
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

  // ── 框架区 ───────────────────────────────────────────────────────

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

      Text(this.stepChip())
        .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  BoardArea() {
    Row({ space: 8 }) {
      this.TensColumn()
      this.OnesColumn()
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)

    this.ReadChip()
    this.StatusChip()
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
        .accessibilityText('回到上一步')
        .onClick(() => {
          this.goPrev()
        })
      Button(this.stepIndex >= STEP_TOTAL - 1 ? '本课完成' : '下一步')
        .width(120).height(44).fontSize(14)
        .backgroundColor(KIDS_MATH_INK)
        .fontColor(Color.White)
        .enabled(this.navNextEnabled())
        .opacity(this.navNextEnabled() ? 1 : 0.45)
        .accessibilityText(this.stepIndex >= STEP_TOTAL - 1 ? '本课完成，继续学习' : '进入下一步')
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
      this.GuideCard()
      this.BoardArea()
      if (this.stepIndex === STEP_TOTAL - 1 && !this.demoStarted && !this.readonly) {
        this.DemoButton(this.demoLabel(),
          this.isUnbundle() ? '拆开一捆小棒变成十根' : '添小棒凑满十再捆成一捆', (): void => {
            this.tapDemo()
          })
        Text(this.isUnbundle() ? '点一点，把十位的 1 捆拆成 10 根。' : `点一点，个位再添 ${placeValueAddToTen(this.ones)} 根凑满 10。`)
          .fontSize(12.5).fontColor(KIDS_SUBTLE).textAlign(TextAlign.Center)
      }
      if (this.animDone) {
        this.WhyBox()
      }
      if (!this.readonly) {
        this.NavRow()
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}