import {
  numberBondStepTitles, numberBondStepTips, numberBondStepNarrations,
  numberBondScaffold, numberBondBestSplit,
  NumberBondScaffoldLine, NumberBondSplit
} from '../../utils/MathTeachNumberBond'
import { AppStorageKeys } from '../../config/AppStorageKeys'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { normalizeMathSymbolsForTts } from '../../utils/TtsTextUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  KIDS_MATH, KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED, KIDS_BORDER,
  KIDS_SURFACE, KIDS_FG, KIDS_ON_HERO, KIDS_ON_GOLD, KIDS_STAR, KIDS_SUBTLE
} from '../kids/KidsBrandTokens'

/**
 * NumberBondBoard - 数的分与合两步演示课（math_teach · number_bond 模式 v2）
 *
 * v2（2026-10-03）：原 4 步引导课（数一数→分一分→合一合→找全部）精简为
 * 两步演示课——分一分（板面按 numberBondBestSplit 推荐最佳分法：两位数按
 * 整十+剩余、10 以内按 5 锚定，点阵分组动画拆成两组 + 分合树 + 算式）→
 * 合起来（从大数往后数的数序条 + 两组合并点阵 + 绿色算式 + 分合树互看）。
 * 底部「分合记录」脚手架随步骤点亮（整体/分/合 3 行）。
 *
 * 完成门：每步点一次演示按钮 onInteract() 一次（共 2 步），shell 层
 * interactionThreshold 对 number_bond 配 2。末步「本课完成」可提前结课。
 *
 * TTS：语音模式开启时（AppStorage VOICE_MODE_ENABLED，与 TenFrameBoard
 * 同一开关），进入每步朗读该步口播稿；回退/离开即 stop。已答历史态不播。
 */

const STEP_NAMES: string[] = ['分一分', '合起来']
const STEP_TOTAL: number = 2
// 分合树几何（对应原型 bond-svg viewBox 232x146）
const BOND_W: number = 232
const BOND_H: number = 146
const COUNT_REVEAL_INTERVAL_MS: number = 300

@ComponentV2
export struct NumberBondBoard {
  @Param total: number = 9
  @Param readonly: boolean = false
  @Event onInteract: () => void = () => {}
  // 末步「本课完成」直通提交：shell 收到后走 submit()（其内部有已提交/门槛守卫）
  @Event onFinish: () => void = () => {}

  @Local stepIndex: number = 0
  // 分一步：已点「分一分」（整堆 → 两组）
  @Local splitShown: boolean = false
  // 合一步：已点「合起来」（两组 → 合并 + 数序条）
  @Local mergeShown: boolean = false
  // 数序条已揭出的个数（含起始大数锚点；1..add+1）
  @Local countShown: number = 0

  // 推荐分法（aboutToAppear 一次算定；total 固定不变）
  private best: NumberBondSplit = { left: 0, right: 0 }
  // 已计完成的步骤（非响应式守卫：重访已完成步骤不重复上报 onInteract）
  private stepDoneFlags: boolean[] = [false, false]
  private startedSpeak: boolean = false
  private revealTimerId: number = -1

  aboutToAppear(): void {
    this.best = numberBondBestSplit(this.total)
    if (this.readonly) {
      // 已答历史态：直接渲染完成态（草稿纸语义，不恢复孩子离开时的中间过程）
      this.splitShown = true
      this.mergeShown = true
      this.countShown = Math.min(this.best.left, this.best.right) + 1
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

  // ── 派生值（Builder 内调用保持响应式，不传布尔快照）──────────────

  private seq(n: number): number[] {
    const arr: number[] = []
    for (let i = 0; i < n; i++) {
      arr.push(i)
    }
    return arr
  }

  /** 分一步舞台的单元素源（0 整堆 / 1 两组）：键随 splitShown 变化驱动重建 + 过渡。 */
  private splitStage(): number[] {
    const a: number[] = []
    a.push(this.splitShown ? 1 : 0)
    return a
  }

  /** 合一步舞台的单元素源（0 两组 / 1 合并完成）：键随 mergeShown 变化驱动重建 + 过渡。 */
  private mergeStage(): number[] {
    const a: number[] = []
    a.push(this.mergeShown ? 1 : 0)
    return a
  }

  /** 数序条待揭总数（锚点 + 往后数 small 个）。 */
  private countChipsTotal(): number {
    const big: number = this.best.left >= this.best.right ? this.best.left : this.best.right
    return this.total - big + 1
  }

  /** 数序条起始锚点（大的部分）。 */
  private countBase(): number {
    return this.best.left >= this.best.right ? this.best.left : this.best.right
  }

  /** 点阵格距：一行最多 10 颗，按 total 分档保证不换行不超宽。 */
  private dotSpan(): number {
    const t: number = this.total
    if (t <= 6) {
      return 32
    }
    if (t <= 10) {
      return 26
    }
    if (t <= 24) {
      return 20
    }
    if (t <= 48) {
      return 17
    }
    return 15
  }

  private stepTitle(): string {
    const titles: string[] = numberBondStepTitles(this.total)
    return titles[this.stepIndex]
  }

  private stepTip(): string {
    const tips: string[] = numberBondStepTips(this.total)
    return tips[this.stepIndex]
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
      return this.splitShown
    }
    return this.mergeShown
  }

  // ── 导航 ─────────────────────────────────────────────────────────

  private goNext(): void {
    if (this.readonly) {
      return
    }
    if (this.stepIndex >= STEP_TOTAL - 1) {
      // 末步「本课完成」：动画没看完也接受本次授课（合一步按已点的计一次），
      // 再通知 shell 直接提交——submit() 内部守卫保证幂等。
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

  /** 末步的「本课完成」随时可点（提前结课）；其余步骤仍按完成门放行。 */
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
    // 回退后正在播的旁白已过时，直接停掉（同 TenFrameBoard 语义）
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
    const narrations: string[] = numberBondStepNarrations(this.total)
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

  // ── 交互 ─────────────────────────────────────────────────────────

  private tapSplit(): void {
    if (this.readonly || this.splitShown) {
      return
    }
    this.splitShown = true
    this.markStepDone(0)
  }

  private tapMerge(): void {
    if (this.readonly || this.mergeShown) {
      return
    }
    this.mergeShown = true
    this.markStepDone(1)
    this.startCountReveal()
  }

  /** 数序条逐个揭出：锚点先现，之后每 300ms 多一个（合的过程可视化）。 */
  private startCountReveal(): void {
    if (this.revealTimerId >= 0) {
      clearTimeout(this.revealTimerId)
      this.revealTimerId = -1
    }
    this.countShown = 1
    this.revealTick()
  }

  private revealTick(): void {
    if (this.countShown >= this.countChipsTotal()) {
      this.revealTimerId = -1
      return
    }
    this.revealTimerId = setTimeout(() => {
      this.countShown += 1
      this.revealTick()
    }, COUNT_REVEAL_INTERVAL_MS)
  }

  private scaffoldLit(idx: number): boolean {
    if (idx === 0) {
      return true
    }
    if (idx === 1) {
      return this.splitShown
    }
    return this.mergeShown
  }

  // ── 通用小件 ─────────────────────────────────────────────────────

  /**
   * 点阵块：一行最多 10 颗自动换行，前 splitAt 颗蓝色、其余橙色。
   * splitAt=count → 全蓝；splitAt=0 → 全橙；merged 时传 left → 两色续接。
   */
  @Builder
  DotRows(count: number, splitAt: number) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
      ForEach(this.seq(count), (i: number) => {
        Circle()
          .width(this.dotSpan() - 4).height(this.dotSpan() - 4)
          .margin(2)
          .fill(i < splitAt ? KIDS_MATH : KIDS_ACCENT)
      }, (i: number) => 'd' + i.toString() + '_' + count.toString() + '_' + splitAt.toString())
    }
    .width(Math.min(count, 10) * this.dotSpan())
  }

  /** 一组点阵 + 计数（blue=左组蓝 / 右组橙，与分合树两色一致）。 */
  @Builder
  GroupPanel(count: number, blue: boolean, caption: string) {
    Column({ space: 4 }) {
      this.DotRows(count, blue ? count : 0)
      Text(caption)
        .fontSize(15).fontWeight(FontWeight.Bold)
        .fontColor(blue ? KIDS_MATH_INK : KIDS_ON_GOLD)
    }
    .width('100%')
    .padding(8)
    .borderRadius(12)
    .backgroundColor(KIDS_SURFACE)
    .border({
      width: 1.5,
      style: BorderStyle.Solid,
      color: blue ? withColorAlpha(KIDS_MATH, '38') : withColorAlpha(KIDS_ACCENT, '38')
    })
  }

  /** 分好的两组：total ≤ 10 并排（各占一半），两位数竖排（每组一行最多 10 颗）。 */
  @Builder
  SplitGroups() {
    if (this.total <= 10) {
      Row({ space: 8 }) {
        Column() {
          this.GroupPanel(this.best.left, true, `${this.best.left}`)
        }
        .layoutWeight(1)

        Column() {
          this.GroupPanel(this.best.right, false, `${this.best.right}`)
        }
        .layoutWeight(1)
      }
      .width('100%')
    } else {
      Column({ space: 8 }) {
        this.GroupPanel(this.best.left, true, `${this.best.left}`)
        this.GroupPanel(this.best.right, false, `${this.best.right}`)
      }
      .width('100%')
    }
  }

  /** 「推荐分法」小标签（分一步拆开后的金框章）。 */
  @Builder
  RecommendChip() {
    Text('推荐分法')
      .fontSize(11).fontWeight(FontWeight.Bold).fontColor(KIDS_ON_GOLD)
      .padding({ left: 10, right: 10, top: 3, bottom: 3 })
      .borderRadius(9)
      .backgroundColor(withColorAlpha(KIDS_STAR, '20'))
      .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha(KIDS_STAR, '60') })
  }

  /** 数序条：从大数锚点开始逐个揭出（20 → 21 → … → 28），合的过程可视化。 */
  @Builder
  CountOnStrip() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
      ForEach(this.seq(this.countShown), (i: number) => {
        Text(`${this.countBase() + i}`)
          .fontSize(15).fontWeight(FontWeight.Bold)
          .fontColor(i === 0 ? Color.White : KIDS_MATH_INK)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .margin(3)
          .borderRadius(9)
          .backgroundColor(i === 0 ? KIDS_MATH_INK : withColorAlpha(KIDS_MATH, '10'))
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.4, y: 0.4 }))
            .animation({ duration: 240, curve: Curve.EaseOut }))
      }, (i: number) => 'chip' + i.toString())
    }
    .width('100%')
  }

  /** 算式行：绿色（完成）/ 墨蓝（过程）。 */
  @Builder
  EqText(text: string, done: boolean) {
    Text(text)
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .fontColor(done ? $r('app.color.status_success') : KIDS_MATH_INK)
      .textAlign(TextAlign.Center)
      .width('100%')
  }

  /** 分合树：整体在顶，两部分在下（合一步完成时加向上小箭头示「合」）。 */
  @Builder
  BondTree(total: number, left: number, right: number) {
    Stack() {
      Line({ width: BOND_W, height: BOND_H })
        .startPoint([100, 56]).endPoint([66, 84])
        .stroke(KIDS_BORDER).strokeWidth(2.4).strokeLineCap(LineCapStyle.Round)
      Line({ width: BOND_W, height: BOND_H })
        .startPoint([132, 56]).endPoint([166, 84])
        .stroke(KIDS_BORDER).strokeWidth(2.4).strokeLineCap(LineCapStyle.Round)
      if (this.mergeShown && this.stepIndex === 1) {
        Line({ width: BOND_W, height: BOND_H })
          .startPoint([108, 80]).endPoint([116, 70])
          .stroke(KIDS_MATH_INK).strokeWidth(2.6).strokeLineCap(LineCapStyle.Round)
        Line({ width: BOND_W, height: BOND_H })
          .startPoint([116, 70]).endPoint([124, 80])
          .stroke(KIDS_MATH_INK).strokeWidth(2.6).strokeLineCap(LineCapStyle.Round)
      }

      Stack() {
        Circle().width(62).height(62)
          .fill(KIDS_ACCENT).stroke(withColorAlpha(KIDS_ON_HERO, '40')).strokeWidth(2)
        Text(`${total}`)
          .fontSize(24).fontWeight(FontWeight.Bold).fontColor(KIDS_ON_HERO)
      }
      .width(62).height(62)
      .position({ x: 116 - 31, y: 34 - 31 })

      Stack() {
        Circle().width(56).height(56)
          .fill(withColorAlpha(KIDS_MATH, '14')).stroke(KIDS_MATH).strokeWidth(2.4)
        Text(`${left}`)
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
      }
      .width(56).height(56)
      .position({ x: 48 - 28, y: 112 - 28 })

      Stack() {
        Circle().width(56).height(56)
          .fill(withColorAlpha(KIDS_ACCENT, '18')).stroke(KIDS_ACCENT).strokeWidth(2.4)
        Text(`${right}`)
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(KIDS_ON_GOLD)
      }
      .width(56).height(56)
      .position({ x: 184 - 28, y: 112 - 28 })
    }
    .width(BOND_W).height(BOND_H)
  }

  @Builder
  WhyBox(head: string, body: string) {
    Column({ space: 3 }) {
      Text(head).fontSize(13).fontWeight(FontWeight.Bold).fontColor(KIDS_ON_GOLD)
      Text(body).fontSize(12.5).fontColor(KIDS_FG).lineHeight(19)
    }
    .alignItems(HorizontalAlign.Start)
    .padding(10)
    .borderRadius(10)
    .backgroundColor(withColorAlpha(KIDS_STAR, '20'))
    .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha(KIDS_STAR, '60') })
    .width('100%')
  }

  /** 演示按钮（每步一个，点一下播动画并计一次动手）。 */
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
  BodySplit() {
    Stack() {
      ForEach(this.splitStage(), (st: number) => {
        Column({ space: 10 }) {
          if (st === 0) {
            this.DotRows(this.total, this.total)
            Text(`一共 ${this.total} 个`)
              .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
          } else {
            this.SplitGroups()
            this.RecommendChip()
            this.BondTree(this.total, this.best.left, this.best.right)
            this.EqText(`${this.total} = ${this.best.left} + ${this.best.right}`, false)
            Text('分，就是把整体拆成两部分。上面是整体，下面两部分合起来还是它。')
              .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
          }
        }
        .width('100%')
        .padding({ top: 12, bottom: 12, left: 8, right: 8 })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.7, y: 0.7 }))
          .animation({ duration: 300, curve: Curve.EaseOut }))
      }, (st: number) => 'ss' + st.toString())
    }
    .width('100%')

    if (!this.splitShown) {
      this.DemoButton('分一分', '把点子分成两组', (): void => {
        this.tapSplit()
      })
      Text(`点一点，把 ${this.total} 分成两组。`)
        .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
    }
  }

  @Builder
  BodyCompose() {
    Stack() {
      ForEach(this.mergeStage(), (st: number) => {
        Column({ space: 10 }) {
          if (st === 0) {
            this.SplitGroups()
            Text('把它们合到一起，一共是几个？')
              .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
          } else {
            this.CountOnStrip()
            this.DotRows(this.total, this.best.left)
            this.EqText(`${this.best.left} + ${this.best.right} = ${this.total}`, true)
            this.BondTree(this.total, this.best.left, this.best.right)
            this.WhyBox('合起来，还是原来的数',
              `分出来的两部分再合起来，就回到整体 ${this.total}。同一张分合树，从上往下是「分」，从下往上是「合」——分完可以用「合」来检查。`)
          }
        }
        .width('100%')
        .padding({ top: 12, bottom: 12, left: 8, right: 8 })
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.7, y: 0.7 }))
          .animation({ duration: 300, curve: Curve.EaseOut }))
      }, (st: number) => 'ms' + st.toString())
    }
    .width('100%')

    if (!this.mergeShown) {
      this.DemoButton('合起来', '把两组合到一起', (): void => {
        this.tapMerge()
      })
    }
  }

  @Builder
  StepBody() {
    if (this.stepIndex === 0) {
      this.BodySplit()
    } else {
      this.BodyCompose()
    }
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

      Text(`第 ${this.stepIndex + 1} / ${STEP_TOTAL} 步 · ${STEP_NAMES[this.stepIndex]}`)
        .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ScaffoldRow(line: NumberBondScaffoldLine, idx: number) {
    Row({ space: 8 }) {
      Text(line.eq)
        .fontSize(12)
        .fontWeight(this.scaffoldLit(idx) ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.scaffoldLit(idx) ? KIDS_MATH_INK : KIDS_MUTED)
      Text(line.label).fontSize(10).fontColor(KIDS_MUTED)
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .borderRadius(7)
    .backgroundColor(this.scaffoldLit(idx) ? withColorAlpha(KIDS_MATH, '10') : '#00000000')
    .opacity(this.scaffoldLit(idx) ? 1 : 0.45)
  }

  @Builder
  ScaffoldArea() {
    Column({ space: 2 }) {
      Text('分合记录')
        .fontSize(11).fontWeight(FontWeight.Bold).fontColor(KIDS_MUTED)
        .width('100%')
      ForEach(numberBondScaffold(this.total, this.best.left, this.best.right),
        (line: NumberBondScaffoldLine, idx: number) => {
          this.ScaffoldRow(line, idx)
        }, (line: NumberBondScaffoldLine) => line.label)
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
        .width(92).height(40).fontSize(14)
        .backgroundColor(withColorAlpha(KIDS_FG, '08'))
        .fontColor(KIDS_MUTED)
        .enabled(this.stepIndex > 0)
        .opacity(this.stepIndex > 0 ? 1 : 0.4)
        .onClick(() => {
          this.goPrev()
        })
      Button(this.stepIndex >= STEP_TOTAL - 1 ? '本课完成' : '下一步')
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
      this.ProgressRow()
      Text(this.stepTitle())
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)
      Text(this.stepTip())
        .fontSize(12).fontColor(KIDS_SUBTLE).textAlign(TextAlign.Center)
      this.StepBody()
      if (!this.readonly) {
        this.NavRow()
      }
      this.ScaffoldArea()
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
