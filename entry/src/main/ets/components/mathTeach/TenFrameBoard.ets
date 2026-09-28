import {
  makeTenFriend, makeTenRemain, makeTenScaffold, makeTenChain, makeTenChips,
  makeTenPractice, makeTenStepTitles, makeTenStepNarrations,
  MakeTenScaffoldLine, MakeTenChainLine, MakeTenChips, MakeTenPractice
} from '../../utils/MathTeachMakeTen'
import { AppStorageKeys } from '../../config/AppStorageKeys'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { normalizeMathSymbolsForTts } from '../../utils/TtsTextUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  KIDS_MATH, KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED, KIDS_BORDER,
  KIDS_SURFACE, KIDS_FG, KIDS_CHINESE_INK
} from '../kids/KidsBrandTokens'

/**
 * TenFrameBoard - 十格阵凑十引导课（math_teach · ten_frame 模式）
 *
 * 参考 docs/cou-shi-fa-lesson.html 的 8 步凑十深度课原型，按工具参数 a/b
 * 泛化：看一看 → 找朋友（点十格阵空格）→ 拆一拆 → 凑成十（1 进框）→
 * 十加几 → 写算式（逐行点亮）→ 讲一讲（排序 chips）→ 练一练（迁移选择题）。
 * 底部「凑十记录」脚手架随步骤点亮。
 *
 * 完成门：每完成一步 onInteract() 一次（共 8 步），shell 层
 * interactionThreshold 对 ten_frame 配 8。回执契约不变。
 *
 * TTS：语音模式开启时（AppStorage VOICE_MODE_ENABLED，与 VerticalMathCard
 * 同一开关），进入每步朗读该步口播稿；回退/离开即 stop。已答历史态不播。
 */

const STEP_NAMES: string[] = ['看一看', '找朋友', '拆一拆', '凑成十', '十加几', '写算式', '讲一讲', '练一练']
const STEP_TOTAL: number = 8
const WRONG_FLASH_MS: number = 420

@ComponentV2
export struct TenFrameBoard {
  @Param a: number = 9
  @Param b: number = 5
  @Param readonly: boolean = false
  @Event onInteract: () => void = () => {}

  @Local stepIndex: number = 0
  @Local found: boolean = false
  @Local split: boolean = false
  @Local sent: boolean = false
  @Local chainCount: number = 0
  @Local toldCount: number = 0
  @Local practiced: boolean = false
  // 点错的 chips / 选项下标（>0 时对该项做 nudge 抖动，超时复位）
  @Local chipWrongIdx: number = -1
  @Local choiceWrongIdx: number = -1

  // 已计完成的步骤（非响应式守卫：重访已完成步骤不重复上报 onInteract）
  private stepDoneFlags: boolean[] = [false, false, false, false, false, false, false, false]
  private wrongTimerId: number = -1
  private startedSpeak: boolean = false

  aboutToAppear(): void {
    if (this.readonly) {
      // 已答历史态：直接渲染完成态（草稿纸语义，不恢复孩子离开时的中间过程）
      this.stepIndex = STEP_TOTAL - 1
      this.found = true
      this.split = true
      this.sent = true
      this.chainCount = 4
      this.toldCount = 4
      this.practiced = true
      return
    }
    this.markStepDone(0)
    this.speakStep(0)
  }

  aboutToDisappear(): void {
    if (this.wrongTimerId >= 0) {
      clearTimeout(this.wrongTimerId)
      this.wrongTimerId = -1
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

  private friend(): number {
    return makeTenFriend(this.a)
  }

  private rest(): number {
    return makeTenRemain(this.b, this.friend())
  }

  private sum(): number {
    return this.a + this.b
  }

  private seq(n: number): number[] {
    const arr: number[] = []
    for (let i = 0; i < n; i++) {
      arr.push(i)
    }
    return arr
  }

  private stepTitle(): string {
    const titles: string[] = makeTenStepTitles(this.a, this.b)
    return titles[this.stepIndex]
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
    if (this.stepIndex === 1) {
      return this.found
    }
    if (this.stepIndex === 2) {
      return this.split
    }
    if (this.stepIndex === 3) {
      return this.sent
    }
    if (this.stepIndex === 5) {
      return this.chainCount >= 4
    }
    if (this.stepIndex === 6) {
      return this.toldCount >= 4
    }
    if (this.stepIndex === 7) {
      return this.practiced
    }
    return true
  }

  // ── 导航 ─────────────────────────────────────────────────────────

  private goNext(): void {
    if (this.readonly || this.stepIndex >= STEP_TOTAL - 1 || !this.canAdvance()) {
      return
    }
    this.stepIndex += 1
    if (this.stepIndex === 4) {
      this.markStepDone(4)
    }
    this.speakStep(this.stepIndex)
  }

  private goPrev(): void {
    if (this.readonly || this.stepIndex <= 0) {
      return
    }
    // 回退后正在播的旁白已过时，直接停掉（同 VerticalMathCard 语义）
    try {
      ServiceRegistry.tts().stop()
    } catch (_e) {
    }
    this.stepIndex -= 1
  }

  // ── TTS ──────────────────────────────────────────────────────────

  // 语音模式（ChatPage 镜像到 AppStorage 的标量）下，进入每步朗读口播稿。
  // 读方是交互时刻的一次性 get，不做监听，raw AppStorage 语义即可。
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
    const narrations: string[] = makeTenStepNarrations(this.a, this.b)
    const text: string = narrations[step]
    if (text === '') {
      return
    }
    this.startedSpeak = true
    // 步骤旁白接管所有在播语音，让孩子听到的是刚进入的这一步。
    ServiceRegistry.tts().stop()
    // TTS 引擎读不出 + ＝ 等符号，转成中文读法再朗读
    ServiceRegistry.tts().speak(normalizeMathSymbolsForTts(text), {
      onStart: () => {},
      onComplete: () => {},
      onError: (_error: string) => {}
    }).catch((_e: Error) => {})
  }

  // ── 交互 ─────────────────────────────────────────────────────────

  private tapFriendCell(idx: number): void {
    if (this.readonly || this.stepIndex !== 1 || this.found || idx !== this.a) {
      return
    }
    this.found = true
    this.markStepDone(1)
  }

  private tapSplit(): void {
    if (this.readonly || this.split) {
      return
    }
    this.split = true
    this.markStepDone(2)
  }

  private tapSend(): void {
    if (this.readonly || this.sent) {
      return
    }
    this.sent = true
    this.markStepDone(3)
  }

  private tapChainNext(): void {
    if (this.readonly || this.chainCount >= 4) {
      return
    }
    this.chainCount += 1
    if (this.chainCount >= 4) {
      this.markStepDone(5)
    }
  }

  private tapChip(displayIdx: number): void {
    if (this.readonly || this.toldCount >= 4) {
      return
    }
    const chips: MakeTenChips = makeTenChips(this.a, this.b)
    if (chips.display[displayIdx] === chips.canonical[this.toldCount]) {
      this.toldCount += 1
      if (this.toldCount >= 4) {
        this.markStepDone(6)
      }
    } else {
      this.flashWrong(true, displayIdx)
    }
  }

  private tapChoice(choiceIdx: number): void {
    if (this.readonly || this.practiced) {
      return
    }
    const p: MakeTenPractice = makeTenPractice(this.a, this.b)
    if (p.choices[choiceIdx] === p.answer) {
      this.practiced = true
      this.markStepDone(7)
    } else {
      this.flashWrong(false, choiceIdx)
    }
  }

  private flashWrong(isChip: boolean, idx: number): void {
    if (isChip) {
      this.chipWrongIdx = idx
    } else {
      this.choiceWrongIdx = idx
    }
    if (this.wrongTimerId >= 0) {
      clearTimeout(this.wrongTimerId)
    }
    this.wrongTimerId = setTimeout(() => {
      this.chipWrongIdx = -1
      this.choiceWrongIdx = -1
      this.wrongTimerId = -1
    }, WRONG_FLASH_MS)
  }

  // 展示位 di 的 chip 是否已被正确点过（文本与 canonical 前 toldCount 项匹配）
  private chipUsedAt(displayIdx: number): boolean {
    const chips: MakeTenChips = makeTenChips(this.a, this.b)
    const text: string = chips.display[displayIdx]
    for (let j = 0; j < this.toldCount; j++) {
      if (chips.canonical[j] === text) {
        return true
      }
    }
    return false
  }

  private scaffoldLit(idx: number): boolean {
    if (idx === 0) {
      return true
    }
    if (idx === 1) {
      return this.found
    }
    if (idx === 2) {
      return this.split
    }
    if (idx === 3) {
      return this.sent
    }
    return this.chainCount >= 4 || this.practiced
  }

  // ── 通用小件 ─────────────────────────────────────────────────────

  @Builder
  Dot(color: string) {
    Circle().width(18).height(18).fill(color).margin(2)
  }

  /** 十格阵格：蓝点（已填）/ 朋友橙点 / 可点空格（仅第 2 步）/ 空格。 */
  @Builder
  FrameCell(idx: number) {
    Stack() {
      if (idx < this.a) {
        Circle().width(26).height(26).fill(KIDS_MATH)
      } else if (idx === this.a) {
        if (this.stepIndex === 1) {
          if (this.found) {
            Circle().width(26).height(26).fill(KIDS_ACCENT)
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.scale({ x: 0.2, y: 0.2 }))
                .animation({ duration: 350, curve: Curve.EaseOut }))
          } else {
            // 待点的空格：淡墨圆点提示（儿童端虚线边框为品牌契约）
            Circle().width(18).height(18).fill(withColorAlpha(KIDS_MATH_INK, '55'))
          }
        } else if (this.stepIndex === 3) {
          if (this.sent) {
            Circle().width(26).height(26).fill(KIDS_ACCENT)
              .transition(TransitionEffect.OPACITY
                .combine(TransitionEffect.scale({ x: 0.2, y: 0.2 }))
                .animation({ duration: 350, curve: Curve.EaseOut }))
          }
        } else {
          Circle().width(26).height(26).fill(KIDS_ACCENT)
        }
      }
    }
    .width(40).height(40)
    .border({
      width: 1.5,
      style: this.stepIndex === 1 && idx === this.a && !this.found ? BorderStyle.Solid : BorderStyle.Dashed,
      color: this.stepIndex === 1 && idx === this.a && !this.found ? KIDS_MATH : KIDS_BORDER,
      radius: 8
    })
    .backgroundColor(this.stepIndex === 1 && idx === this.a && !this.found
      ? withColorAlpha(KIDS_MATH, '14') : '#00000000')
    .onClick(() => {
      this.tapFriendCell(idx)
    })
  }

  @Builder
  TenFrame() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        this.FrameCell(0)
        this.FrameCell(1)
        this.FrameCell(2)
        this.FrameCell(3)
        this.FrameCell(4)
      }
      Row({ space: 6 }) {
        this.FrameCell(5)
        this.FrameCell(6)
        this.FrameCell(7)
        this.FrameCell(8)
        this.FrameCell(9)
      }
    }
  }

  /** 框外散点盒：凑十前 b 个（首个带「要进框」虚线环），凑十后剩 rest 个。 */
  @Builder
  LooseBox() {
    Column({ space: 6 }) {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(this.seq(this.sent ? this.rest() : this.b), (i: number) => {
          if (i === 0 && this.stepIndex === 3 && !this.sent) {
            Stack() {
              Circle().width(18).height(18).fill(KIDS_ACCENT)
            }
            .width(24).height(24).margin(2)
            .border({ width: 1.5, style: BorderStyle.Dashed, color: KIDS_ACCENT, radius: 12 })
          } else {
            this.Dot(KIDS_ACCENT)
          }
        }, (i: number) => 'loose' + i.toString())
      }
      .width('100%')

      if (this.stepIndex === 3 && !this.sent) {
        Text(`盒里有 ${this.b} 个，其中 1 个要进框`)
          .fontSize(12).fontColor(KIDS_MUTED)
      } else {
        Text(this.sent || this.stepIndex === 4 ? `框外还剩 ${this.rest()} 个` : `框外有 ${this.b} 个`)
          .fontSize(12).fontColor(KIDS_MUTED)
      }
    }
    .padding(10)
    .borderRadius(14)
    .border({ width: 1.5, style: BorderStyle.Dashed, color: KIDS_BORDER })
    .backgroundColor(withColorAlpha(KIDS_ACCENT, '0A'))
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

  @Builder
  WhyBox(head: string, body: string) {
    Column({ space: 3 }) {
      Text(head).fontSize(13).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
      Text(body).fontSize(12.5).fontColor(KIDS_FG).lineHeight(19)
    }
    .alignItems(HorizontalAlign.Start)
    .padding(10)
    .borderRadius(10)
    .backgroundColor(withColorAlpha(KIDS_MATH, '10'))
    .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha(KIDS_MATH, '30') })
    .width('100%')
  }

  // ── 8 步主体 ─────────────────────────────────────────────────────

  @Builder
  BodySee() {
    Row({ space: 14 }) {
      Column({ space: 6 }) {
        Text('先有').fontSize(12).fontColor(KIDS_MUTED)
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(this.seq(this.a), (i: number) => {
            this.Dot(KIDS_MATH)
          }, (i: number) => 'sa' + i.toString())
        }
        .width(120)
        Text(`${this.a} 个`).fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)
      }
      .padding(10)
      .borderRadius(14)
      .border({ width: 1.5, style: BorderStyle.Solid, color: KIDS_BORDER })
      .backgroundColor(KIDS_SURFACE)

      Column({ space: 6 }) {
        Text('又来了').fontSize(12).fontColor(KIDS_MUTED)
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(this.seq(this.b), (i: number) => {
            this.Dot(KIDS_ACCENT)
          }, (i: number) => 'sb' + i.toString())
        }
        .width(120)
        Text(`${this.b} 个`).fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)
      }
      .padding(10)
      .borderRadius(14)
      .border({ width: 1.5, style: BorderStyle.Solid, color: KIDS_BORDER })
      .backgroundColor(KIDS_SURFACE)
    }
    .alignItems(VerticalAlign.Center)

    this.EqText(`${this.a} + ${this.b} = ?`, false)
    Text('一个一个数太慢啦。我们学一个三步的好办法——凑十法。')
      .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
  }

  @Builder
  BodyFind() {
    this.TenFrame()
    if (this.found) {
      this.EqText(`${this.a} + ${this.friend()} = 10`, true)
      Text(`十格阵满了！${this.friend()} 就是 ${this.a} 的好朋友。`)
        .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
    } else {
      Text('十格阵里还差几个才满十？点一点那个空格。')
        .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
    }
  }

  /** 拆一拆的数位 chip：未知（虚线 ?）与已知（实底）两种。 */
  @Builder
  BondUnknown() {
    Text('?')
      .fontSize(18).fontWeight(FontWeight.Bold).fontColor(KIDS_MUTED)
      .width(50).height(50).textAlign(TextAlign.Center)
      .borderRadius(25)
      .border({ width: 1.5, style: BorderStyle.Dashed, color: KIDS_BORDER })
  }

  @Builder
  BondKnown(value: string, bgColor: string, textColor: string) {
    Text(value)
      .fontSize(18).fontWeight(FontWeight.Bold).fontColor(textColor)
      .width(50).height(50).textAlign(TextAlign.Center)
      .borderRadius(25)
      .backgroundColor(bgColor)
  }

  @Builder
  BodySplit() {
    this.BondKnown(`${this.b}`, withColorAlpha(KIDS_ACCENT, '26'), KIDS_FG)
    Text(this.split ? '拆成' : `要拆成两部分，给 ${this.a} 一部分`)
      .fontSize(12).fontColor(KIDS_MUTED)
    Row({ space: 14 }) {
      if (this.split) {
        this.BondKnown(`${this.friend()}`, withColorAlpha(KIDS_ACCENT, '26'), KIDS_FG)
        Text('+').fontSize(16).fontColor(KIDS_MUTED)
        this.BondKnown(`${this.rest()}`, withColorAlpha(KIDS_MATH, '18'), KIDS_MATH_INK)
      } else {
        this.BondUnknown()
        Text('+').fontSize(16).fontColor(KIDS_MUTED)
        this.BondUnknown()
      }
    }
    .alignItems(VerticalAlign.Center)

    if (this.split) {
      this.EqText(`${this.b} = ${this.friend()} + ${this.rest()}`, false)
      this.WhyBox('为什么拆小数，不拆大数？',
        `${this.a} 离 10 只差 ${this.friend()}，很好凑。把 ${this.b} 拆出 ${this.friend()} 给 ${this.a}，剩下的 ${this.rest()} 留着一会儿加。这就是「看大数，拆小数」。`)
    } else {
      Button(`把 ${this.friend()} 拆出来给 ${this.a}`)
        .width(200).height(44)
        .backgroundColor(KIDS_MATH_INK).fontSize(14)
        .accessibilityText(`把 ${this.friend()} 拆出来给 ${this.a}`)
        .onClick(() => {
          this.tapSplit()
        })
    }
  }

  @Builder
  BodySend() {
    Row({ space: 14 }) {
      this.TenFrame()
      this.LooseBox()
    }
    .alignItems(VerticalAlign.Center)

    if (this.sent) {
      this.EqText(`${this.a} + ${this.friend()} = 10，框外还剩 ${this.rest()}`, true)
      Text('框里正好 10，外面还有几个？变成好算的「十加几」啦。')
        .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
    } else {
      Button(`把 ${this.friend()} 送进十格阵`)
        .width(200).height(44)
        .backgroundColor(KIDS_MATH_INK).fontSize(14)
        .accessibilityText(`把 ${this.friend()} 送进十格阵`)
        .onClick(() => {
          this.tapSend()
        })
    }
  }

  @Builder
  BodyRead() {
    Row({ space: 14 }) {
      this.TenFrame()
      this.LooseBox()
    }
    .alignItems(VerticalAlign.Center)

    this.EqText(`10 + ${this.rest()} = ${this.sum()}`, true)
    this.WhyBox('十加几，得十几', `10 + ${this.rest()} 就是 ${this.sum()}。所以 ${this.a} + ${this.b} 的答案就是 ${this.sum()}。`)
  }

  @Builder
  ChainLine(line: MakeTenChainLine, idx: number) {
    Row({ space: 8 }) {
      Text(line.tag).fontSize(10).fontColor(KIDS_MUTED).width(44)
      Text(line.eq)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(idx < this.chainCount ? KIDS_MATH_INK : KIDS_MUTED)
      Text(line.note).fontSize(10).fontColor(KIDS_MUTED)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .borderRadius(9)
    .backgroundColor(idx < this.chainCount ? withColorAlpha(KIDS_MATH, '12') : withColorAlpha(KIDS_FG, '06'))
    .border({
      width: 1,
      style: BorderStyle.Solid,
      color: idx < this.chainCount ? withColorAlpha(KIDS_MATH, '38') : KIDS_BORDER
    })
    .opacity(idx < this.chainCount ? 1 : 0.5)
  }

  @Builder
  BodyWrite() {
    Column({ space: 8 }) {
      ForEach(makeTenChain(this.a, this.b), (line: MakeTenChainLine, idx: number) => {
        this.ChainLine(line, idx)
      }, (line: MakeTenChainLine) => line.tag)
    }
    .width('100%')

    if (this.chainCount < 4) {
      Button(this.chainCount === 0 ? '一步一步连起来' : '连下一行')
        .width(170).height(44)
        .backgroundColor(KIDS_MATH_INK).fontSize(14)
        .accessibilityText('点亮下一行算式')
        .onClick(() => {
          this.tapChainNext()
        })
    } else {
      Text('看懂了吗？把加法改成「十加几」，一下就出来了。')
        .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
    }
  }

  @Builder
  BodyTell() {
    Text(`说对 ${this.toldCount} / 4 句`).fontSize(12).fontColor(KIDS_MUTED)
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
      ForEach(makeTenChips(this.a, this.b).canonical, (text: string, idx: number) => {
        if (idx < this.toldCount) {
          Text(text)
            .fontSize(12.5).fontWeight(FontWeight.Bold).fontColor(Color.White)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(9)
            .backgroundColor(KIDS_MATH_INK)
            .margin(3)
        } else {
          Text('?')
            .fontSize(12.5).fontColor(KIDS_MUTED)
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .borderRadius(9)
            .border({ width: 1.5, style: BorderStyle.Dashed, color: KIDS_BORDER })
            .margin(3)
        }
      }, (text: string, idx: number) => 'slot' + idx.toString())
    }
    .width('100%')

    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
      ForEach(makeTenChips(this.a, this.b).display, (text: string, idx: number) => {
        Text(text)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.chipUsedAt(idx) ? withColorAlpha(KIDS_MATH_INK, '90') : KIDS_FG)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(18)
          .backgroundColor(this.chipUsedAt(idx) ? withColorAlpha(KIDS_MATH, '16') : KIDS_SURFACE)
          .border({
            width: 1.5,
            style: BorderStyle.Solid,
            color: this.chipUsedAt(idx) ? KIDS_MATH : KIDS_BORDER
          })
          .opacity(this.chipUsedAt(idx) ? 0.6 : 1)
          .margin(4)
          .translate({ x: this.chipWrongIdx === idx ? 5 : 0 })
          .animation({ duration: 60, curve: Curve.EaseOut })
          .onClick(() => {
            this.tapChip(idx)
          })
      }, (text: string, idx: number) => 'chip' + idx.toString())
    }
    .width('100%')

    if (this.toldCount < 4) {
      Text('当小老师，按顺序点出凑十的三句话：先找朋友，再拆数，最后加。')
        .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
    } else {
      Text('真棒！你已经会用自己的话讲凑十法了，这就是真正学会了。')
        .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
    }
  }

  @Builder
  BodyPractice() {
    if (this.practiced) {
      this.EqText(`${makeTenPractice(this.a, this.b).big} + ${makeTenPractice(this.a, this.b).small} = ` +
        `${makeTenPractice(this.a, this.b).big} + ${makeTenPractice(this.a, this.b).answer} + ` +
        `${makeTenPractice(this.a, this.b).small - makeTenPractice(this.a, this.b).answer} = ` +
        `${makeTenPractice(this.a, this.b).big + makeTenPractice(this.a, this.b).small}`, true)
      this.WhyBox('换个数字，方法不变',
        `看大数 ${makeTenPractice(this.a, this.b).big} 差 ${makeTenPractice(this.a, this.b).answer} 满十，` +
        `就从 ${makeTenPractice(this.a, this.b).small} 里拆出 ${makeTenPractice(this.a, this.b).answer}，` +
        `先凑十 10，再加余下的 ${makeTenPractice(this.a, this.b).small - makeTenPractice(this.a, this.b).answer}。凑十法都会这样用。`)
    } else {
      this.EqText(`${makeTenPractice(this.a, this.b).big} + ${makeTenPractice(this.a, this.b).small} = ?`, false)
      Text(`看大数 ${makeTenPractice(this.a, this.b).big}，它差几满十？要从 ${makeTenPractice(this.a, this.b).small} 里拆出几给 ${makeTenPractice(this.a, this.b).big}？`)
        .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
      Row({ space: 12 }) {
        ForEach(makeTenPractice(this.a, this.b).choices, (v: number, idx: number) => {
          Text(`拆出 ${v}`)
            .fontSize(14).fontWeight(FontWeight.Bold)
            .fontColor(this.choiceWrongIdx === idx ? KIDS_CHINESE_INK : KIDS_MATH_INK)
            .width(86).height(48).textAlign(TextAlign.Center)
            .borderRadius(12)
            .backgroundColor(this.choiceWrongIdx === idx
              ? withColorAlpha(KIDS_CHINESE_INK, '12') : KIDS_SURFACE)
            .border({
              width: 1.5,
              style: BorderStyle.Solid,
              color: this.choiceWrongIdx === idx ? KIDS_CHINESE_INK : KIDS_BORDER
            })
            .translate({ x: this.choiceWrongIdx === idx ? 5 : 0 })
            .animation({ duration: 60, curve: Curve.EaseOut })
            .onClick(() => {
              this.tapChoice(idx)
            })
        }, (v: number) => 'choice' + v.toString())
      }
    }
  }

  @Builder
  StepBody() {
    if (this.stepIndex === 0) {
      this.BodySee()
    } else if (this.stepIndex === 1) {
      this.BodyFind()
    } else if (this.stepIndex === 2) {
      this.BodySplit()
    } else if (this.stepIndex === 3) {
      this.BodySend()
    } else if (this.stepIndex === 4) {
      this.BodyRead()
    } else if (this.stepIndex === 5) {
      this.BodyWrite()
    } else if (this.stepIndex === 6) {
      this.BodyTell()
    } else {
      this.BodyPractice()
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
  ScaffoldRow(line: MakeTenScaffoldLine, idx: number) {
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
      Text('凑十记录')
        .fontSize(11).fontWeight(FontWeight.Bold).fontColor(KIDS_MUTED)
        .width('100%')
      ForEach(makeTenScaffold(this.a, this.b), (line: MakeTenScaffoldLine, idx: number) => {
        this.ScaffoldRow(line, idx)
      }, (line: MakeTenScaffoldLine) => line.label)
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
        .enabled(this.canAdvance())
        .opacity(this.canAdvance() ? 1 : 0.45)
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
