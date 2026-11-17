import {
  breakTenOnes, breakTenFromTen, breakTenResult, breakTenLessonSteps,
  breakTenStepNarrations, breakTenPracticeRound, breakTenProblem,
  BreakTenLessonStep, BreakTenProblem
} from '../../utils/MathTeachBreakTen'
import { makeTenBlockColor, makeTenShade, makeTenIsLight } from '../../utils/MathTeachMakeTen'
import { AppStorageKeys } from '../../config/AppStorageKeys'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { normalizeMathSymbolsForTts } from '../../utils/TtsTextUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  KIDS_ACCENT, KIDS_BORDER, KIDS_CHINESE_INK, KIDS_FG, KIDS_MATH, KIDS_MATH_INK,
  KIDS_MUTED, KIDS_ON_GOLD, KIDS_STAR, KIDS_SURFACE
} from '../kids/KidsBrandTokens'

/**
 * BreakTenBoard - 破十减法引导课（math_teach · break_ten 模式）
 *
 * 镜像 TenFrameBoard 结构（spec 2026-11-17 P0 三板 §4.2）：
 * - 学一学：4 步（看个位 → 拆成十和几 → 十里减 → 加回来），Numberblocks
 *   风格方块小人 + 满十格框 + 框外个位块 + 逐块划掉动画 + 飞拢合并。
 * - 练一练：5 题迁移闯关（问关键步「10 - b = ?」→ 划掉 → 揭示最终差 →
 *   下一题 → 成绩页）。
 *
 * 完成门：讲解 4 步各计一次；练习每答对一题计一次。shell 层
 * interactionThreshold 对 break_ten 配 4。回执契约不变，不授星。
 *
 * TTS：语音模式开启时（AppStorage VOICE_MODE_ENABLED），进入每步朗读
 * 该步口播稿；回退/离开即 stop。已答历史态（readonly）渲染完成态、不播。
 */

const STEP_TOTAL: number = 4
const PRACTICE_TOTAL: number = 5
const CELL: number = 28
const CELL_GAP: number = 4
const UNIT: number = 16
const UNIT_GAP: number = 2
const WRONG_FLASH_MS: number = 420
const CROSS_STEP_MS: number = 90
const CROSS_SETTLE_MS: number = 300
const BLINK_MS: number = 520

@ComponentV2
export struct BreakTenBoard {
  @Param a: number = 15
  @Param b: number = 9
  @Param readonly: boolean = false
  @Event onInteract: () => void = () => {}

  // 讲解
  @Local mode: string = 'lesson'
  @Local stepIndex: number = 0
  @Local maxStep: number = 0
  @Local crossing: boolean = false
  @Local crossCount: number = 0
  @Local onesDim: boolean = false

  // 练习
  @Local practiceStarted: boolean = false
  @Local problems: BreakTenProblem[] = []
  @Local pIndex: number = 0
  @Local pPhase: string = 'ask'
  @Local pAttempts: number = 0
  @Local pClean: boolean = true
  @Local pStars: number = 0
  @Local pCrossCount: number = 0
  @Local wrongOptionIdx: number = -1

  private stepDoneFlags: boolean[] = [false, false, false, false]
  private timerIds: number[] = []
  private wrongTimerId: number = -1
  private blinkTimerId: number = -1
  private startedSpeak: boolean = false

  aboutToAppear(): void {
    if (this.readonly) {
      // 已答历史态：直接渲染完成态（草稿纸语义，不恢复孩子离开时的中间过程）
      this.stepIndex = STEP_TOTAL - 1
      this.maxStep = STEP_TOTAL - 1
      return
    }
    this.markStepDone(0)
    this.speakStep(0)
    this.syncBlink()
  }

  aboutToDisappear(): void {
    this.clearCrossTimers()
    this.stopBlink()
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

  // ── 派生值（Builder 内调用保持响应式，不传快照）─────────────────

  private ones(): number {
    return breakTenOnes(this.a)
  }

  private fromTen(): number {
    return breakTenFromTen(this.b)
  }

  private result(): number {
    return breakTenResult(this.a, this.b)
  }

  private seq(n: number): number[] {
    const arr: number[] = []
    for (let i = 0; i < n; i++) {
      arr.push(i)
    }
    return arr
  }

  private currentStep(): BreakTenLessonStep {
    const steps: BreakTenLessonStep[] = breakTenLessonSteps(this.a, this.b)
    return steps[this.stepIndex]
  }

  private currentProblem(): BreakTenProblem {
    if (this.pIndex >= 0 && this.pIndex < this.problems.length) {
      return this.problems[this.pIndex]
    }
    return breakTenProblem(this.a, this.b)
  }

  private practiceFromTen(): number {
    return this.currentProblem().fromTen
  }

  private practiceOnes(): number {
    return this.currentProblem().ones
  }

  private practiceResult(): number {
    return this.currentProblem().result
  }

  private practiceA(): number {
    return this.currentProblem().a
  }

  private practiceB(): number {
    return this.currentProblem().b
  }

  // ── 十格框派生 ───────────────────────────────────────────────────

  private crossActive(): boolean {
    if (this.mode === 'practice') {
      return this.pPhase === 'crossing'
    }
    return this.crossing
  }

  private frameFilledNow(): number {
    if (this.mode === 'practice') {
      if (this.pPhase === 'solved') {
        return this.practiceFromTen()
      }
      if (this.pPhase === 'crossing') {
        return 10 - this.pCrossCount
      }
      return 10
    }
    if (this.stepIndex >= 2) {
      return this.fromTen()
    }
    if (this.crossing) {
      return 10 - this.crossCount
    }
    return 10
  }

  private frameFull(): boolean {
    return this.frameFilledNow() >= 10
  }

  private mergedNow(): boolean {
    if (this.mode === 'practice') {
      return this.pPhase === 'solved'
    }
    return this.stepIndex >= 3
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

  // ── 个位闪烁（第 1 步「不够减」提示）─────────────────────────────

  private syncBlink(): void {
    const should: boolean = !this.readonly && this.mode === 'lesson' && this.stepIndex === 0
    if (should && this.blinkTimerId < 0) {
      this.blinkTimerId = setInterval(() => {
        this.onesDim = !this.onesDim
      }, BLINK_MS)
    } else if (!should) {
      this.stopBlink()
    }
  }

  private stopBlink(): void {
    if (this.blinkTimerId >= 0) {
      clearInterval(this.blinkTimerId)
      this.blinkTimerId = -1
    }
    this.onesDim = false
  }

  // ── 讲解导航 ─────────────────────────────────────────────────────

  private goNext(): void {
    if (this.readonly || this.crossing) {
      return
    }
    if (this.stepIndex === 0) {
      this.stepIndex = 1
      this.maxStep = Math.max(this.maxStep, 1)
      this.markStepDone(1)
      this.speakStep(1)
      this.syncBlink()
      return
    }
    if (this.stepIndex === 1) {
      this.startCross()
      return
    }
    if (this.stepIndex === 2) {
      this.stepIndex = 3
      this.maxStep = Math.max(this.maxStep, 3)
      this.markStepDone(3)
      this.speakStep(3)
      return
    }
    this.switchMode('practice')
  }

  private goToStep(idx: number): void {
    if (this.readonly || this.crossing || idx < 0 || idx > this.maxStep || idx === this.stepIndex) {
      return
    }
    this.stepIndex = idx
    this.speakStep(idx)
    this.syncBlink()
  }

  private resetLesson(): void {
    if (this.readonly || this.crossing) {
      return
    }
    this.clearCrossTimers()
    this.crossCount = 0
    this.stepIndex = 0
    this.maxStep = 0
    this.speakStep(0)
    this.syncBlink()
  }

  private startCross(): void {
    if (this.readonly || this.crossing) {
      return
    }
    this.clearCrossTimers()
    this.crossing = true
    this.crossCount = 0
    const total: number = 10 - this.fromTen()
    for (let i = 1; i <= total; i++) {
      const id: number = setTimeout(() => {
        this.crossCount = i
      }, i * CROSS_STEP_MS)
      this.timerIds.push(id)
    }
    const doneId: number = setTimeout(() => {
      this.finishCross()
    }, total * CROSS_STEP_MS + CROSS_SETTLE_MS)
    this.timerIds.push(doneId)
  }

  private finishCross(): void {
    this.crossing = false
    this.crossCount = 10 - this.fromTen()
    this.stepIndex = 2
    this.maxStep = Math.max(this.maxStep, 2)
    this.markStepDone(2)
    this.speakStep(2)
  }

  private clearCrossTimers(): void {
    for (let i = 0; i < this.timerIds.length; i++) {
      clearTimeout(this.timerIds[i])
    }
    this.timerIds = []
  }

  // ── 练习流程 ─────────────────────────────────────────────────────

  private switchMode(mode: string): void {
    // 讲解划掉动画中不许切页（busy 门），否则 finishCross 会在练习页迟到触发
    if (this.readonly || this.mode === mode || this.crossing) {
      return
    }
    // 练习划掉动画中切回讲解：取消未完成的划掉，退回答题态，本题重新答
    if (mode === 'lesson' && this.pPhase === 'crossing') {
      this.clearCrossTimers()
      this.pCrossCount = 0
      this.pPhase = 'ask'
    }
    this.mode = mode
    this.syncBlink()
    if (mode === 'practice') {
      if (!this.practiceStarted || this.pPhase === 'done') {
        this.startRound()
      } else {
        this.speak(this.guideText())
      }
    }
  }

  private startRound(): void {
    this.clearCrossTimers()
    // 顶层一律换新数组，触发 @Local 响应式刷新
    this.problems = breakTenPracticeRound(this.a, this.b, PRACTICE_TOTAL)
    this.pIndex = 0
    this.pPhase = 'ask'
    this.pAttempts = 0
    this.pClean = true
    this.pStars = 0
    this.pCrossCount = 0
    this.wrongOptionIdx = -1
    this.practiceStarted = true
    this.speak(this.practiceAskText())
  }

  private tapOption(idx: number): void {
    if (this.readonly || this.pPhase !== 'ask') {
      return
    }
    const options: number[] = this.currentProblem().options
    if (idx < 0 || idx >= options.length) {
      return
    }
    if (options[idx] !== this.practiceFromTen()) {
      this.pAttempts += 1
      this.flashWrong(idx)
      return
    }
    this.pClean = this.pAttempts === 0
    this.pPhase = 'crossing'
    this.pCrossCount = 0
    this.clearCrossTimers()
    const total: number = this.practiceB()
    for (let i = 1; i <= total; i++) {
      const id: number = setTimeout(() => {
        this.pCrossCount = i
      }, i * CROSS_STEP_MS)
      this.timerIds.push(id)
    }
    const doneId: number = setTimeout(() => {
      this.finishPractice()
    }, total * CROSS_STEP_MS + CROSS_SETTLE_MS)
    this.timerIds.push(doneId)
  }

  private finishPractice(): void {
    this.pPhase = 'solved'
    this.pStars += 1
    this.onInteract()
    this.speak(this.practiceSolvedText())
  }

  private nextQuestion(): void {
    if (this.readonly || this.pPhase !== 'solved') {
      return
    }
    if (this.pIndex + 1 >= this.problems.length) {
      this.pPhase = 'done'
      return
    }
    this.pIndex += 1
    this.pAttempts = 0
    this.pClean = true
    this.pPhase = 'ask'
    this.pCrossCount = 0
    this.wrongOptionIdx = -1
    this.speak(this.practiceAskText())
  }

  private flashWrong(idx: number): void {
    this.wrongOptionIdx = idx
    if (this.wrongTimerId >= 0) {
      clearTimeout(this.wrongTimerId)
    }
    this.wrongTimerId = setTimeout(() => {
      this.wrongOptionIdx = -1
      this.wrongTimerId = -1
    }, WRONG_FLASH_MS)
  }

  // ── 文案 ─────────────────────────────────────────────────────────

  private practiceAskText(): string {
    return `${this.practiceA()} 减 ${this.practiceB()}，个位不够减。先算关键一步：10 减 ${this.practiceB()} 等于几？`
  }

  private practiceSolvedText(): string {
    return `10 减 ${this.practiceB()} 等于 ${this.practiceFromTen()}。加回个位的 ${this.practiceOnes()}，` +
      `${this.practiceFromTen()} + ${this.practiceOnes()} = ${this.practiceResult()}。` +
      `所以 ${this.practiceA()} - ${this.practiceB()} = ${this.practiceResult()}。`
  }

  private guideChip(): string {
    if (this.mode === 'lesson') {
      return this.currentStep().chip
    }
    if (this.pPhase === 'crossing') {
      return '正在十里减'
    }
    if (this.pPhase === 'solved') {
      return '破十成功'
    }
    return `${this.practiceA()} - ${this.practiceB()}`
  }

  private guideText(): string {
    if (this.mode === 'lesson') {
      return this.currentStep().narration
    }
    if (this.pPhase === 'crossing') {
      return `从满十的框里划掉 ${this.practiceB()} 块，剩下 ${this.practiceFromTen()} 块。`
    }
    if (this.pPhase === 'solved') {
      return this.practiceSolvedText()
    }
    return this.practiceAskText()
  }

  private hintText(): string {
    if (this.mode === 'lesson') {
      return this.currentStep().hint
    }
    if (this.pPhase === 'crossing') {
      return `10 - ${this.practiceB()} = ${this.practiceFromTen()}`
    }
    if (this.pPhase === 'solved') {
      return `${this.practiceFromTen()} + ${this.practiceOnes()} = ${this.practiceResult()}，` +
        `所以 ${this.practiceA()} - ${this.practiceB()} = ${this.practiceResult()}`
    }
    return '从 10 往回数一数，划掉几块就剩几块。'
  }

  // ── TTS ──────────────────────────────────────────────────────────

  // 语音模式（ChatPage 镜像到 AppStorage 的标量）下，进入每步朗读口播稿。
  private isVoiceEnabled(): boolean {
    return AppStorage.get<number>(AppStorageKeys.VOICE_MODE_ENABLED) === 1
  }

  private speakStep(step: number): void {
    if (step < 0 || step >= STEP_TOTAL) {
      return
    }
    const narrations: string[] = breakTenStepNarrations(this.a, this.b)
    this.speak(narrations[step])
  }

  private speak(text: string): void {
    if (this.readonly || !this.isVoiceEnabled() || text === '') {
      return
    }
    this.startedSpeak = true
    // 步骤旁白接管所有在播语音，让孩子听到的是刚进入的这一步。
    ServiceRegistry.tts().stop()
    // TTS 引擎读不出 - ＝ 等符号，转成中文读法再朗读
    ServiceRegistry.tts().speak(normalizeMathSymbolsForTts(text), {
      onStart: () => {},
      onComplete: () => {},
      onError: (_error: string) => {}
    }).catch((_e: Error) => {})
  }

  // ── 通用小件 ─────────────────────────────────────────────────────

  private blockGradient(color: string): LinearGradient {
    return {
      angle: 180,
      colors: [[color, 0.0], [makeTenShade(color, 0.78), 1.0]]
    }
  }

  private smileCommands(size: number): string {
    const w: number = size * 0.38
    const h: number = size * 0.2
    return 'M 0 ' + (h * 0.25).toFixed(2) + ' Q ' + (w / 2).toFixed(2) + ' ' +
      h.toFixed(2) + ' ' + w.toFixed(2) + ' ' + (h * 0.25).toFixed(2)
  }

  @Builder
  Eye(d: number) {
    Stack() {
      Circle({ width: d, height: d })
        .fill(Color.White)
        .stroke(withColorAlpha('#141C2D', '80'))
        .strokeWidth(0.8)
      Circle({ width: d * 0.45, height: d * 0.45 })
        .fill('#182135')
    }
    .width(d).height(d)
  }

  @Builder
  FaceMark(size: number, color: string) {
    Column({ space: Math.max(1, size * 0.06) }) {
      Row({ space: Math.max(1, size * 0.12) }) {
        this.Eye(Math.max(3, size * 0.2))
        this.Eye(Math.max(3, size * 0.2))
      }
      Path({ width: size * 0.38, height: size * 0.2 })
        .commands(this.smileCommands(size))
        .fill(Color.Transparent)
        .stroke(makeTenIsLight(color) ? '#182135' : Color.White)
        .strokeWidth(Math.max(1, size * 0.055))
        .strokeLineCap(LineCapStyle.Round)
    }
  }

  /** Numberblocks 风格方块：渐变底 + 圆角 + 一点阴影，首块带眼睛和微笑。 */
  @Builder
  BlockSquare(size: number, color: string, face: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      if (face) {
        this.FaceMark(size, color)
      }
    }
    .width(size).height(size)
    .borderRadius(size * 0.22)
    .linearGradient(this.blockGradient(color))
    .border({
      width: 1,
      style: BorderStyle.Solid,
      color: withColorAlpha('#141C2D', '14'),
      radius: size * 0.22
    })
    .shadow({ radius: 3, color: '#1F000000', offsetY: 1 })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.5, y: 0.5 }))
      .animation({ duration: 200, curve: Curve.EaseOut }))
  }

  @Builder
  BlockColumn(count: number, color: string, face: boolean) {
    Column({ space: UNIT_GAP }) {
      ForEach(this.seq(count), (i: number) => {
        this.BlockSquare(UNIT, color, face && i === 0)
      }, (i: number) => 'blk' + i.toString())
    }
  }

  /** 1-10 的方块小人：≤5 一排，>5 折成两排（上 5 下余）。 */
  @Builder
  Figure(n: number, color: string, face: boolean) {
    Row({ space: UNIT_GAP }) {
      if (n <= 5) {
        this.BlockColumn(n, color, face)
      } else {
        this.BlockColumn(5, color, face)
        this.BlockColumn(n - 5, color, false)
      }
    }
    .alignItems(VerticalAlign.Bottom)
  }

  /** 一队方块 + 药丸标签；boxed=true 时加虚线蓝框（要关注的那一队）。 */
  @Builder
  Part(n: number, color: string, label: string, boxed: boolean) {
    Column({ space: 6 }) {
      if (boxed) {
        Row() {
          this.Figure(n, color, false)
        }
        .padding(4)
        .borderRadius(10)
        .backgroundColor(withColorAlpha(KIDS_MATH, '0E'))
        .border({
          width: 1.5,
          style: BorderStyle.Dashed,
          color: withColorAlpha(KIDS_MATH, '66'),
          radius: 10
        })
      } else {
        this.Figure(n, color, true)
      }
      Text(label)
        .fontSize(11).fontWeight(FontWeight.Bold)
        .fontColor(boxed ? KIDS_MATH_INK : KIDS_MUTED)
        .maxLines(1)
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .borderRadius(10)
        .backgroundColor(boxed ? withColorAlpha(KIDS_MATH, '10') : KIDS_SURFACE)
        .border({
          width: 1,
          style: BorderStyle.Solid,
          color: boxed ? withColorAlpha(KIDS_MATH, '40') : KIDS_BORDER
        })
    }
  }

  @Builder
  FrameCell(idx: number) {
    Stack() {
      if (idx < this.frameFilledNow()) {
        this.BlockSquare(CELL - 2, makeTenBlockColor(10), false)
      } else if (this.crossActive()) {
        // 划掉动画中：淡化的方块 + 红叉，逐块级联出现
        Stack() {
          this.BlockSquare(CELL - 2, makeTenBlockColor(10), false)
          Text('✕')
            .fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_CHINESE_INK)
        }
        .opacity(0.35)
        .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut }))
      }
    }
    .width(CELL).height(CELL)
    .borderRadius(7)
    .backgroundColor(idx < this.frameFilledNow()
      ? Color.Transparent
      : (this.crossActive() ? withColorAlpha(KIDS_CHINESE_INK, '08') : Color.White))
    .border({
      width: idx < this.frameFilledNow() ? 0 : 1.5,
      style: idx < this.frameFilledNow() ? BorderStyle.Solid : BorderStyle.Dashed,
      color: '#C9D6EA',
      radius: 7
    })
  }

  @Builder
  TenFrame() {
    Column({ space: CELL_GAP }) {
      Row({ space: CELL_GAP }) {
        ForEach(this.seq(5), (c: number) => {
          this.FrameCell(c)
        }, (c: number) => 'fc' + c.toString())
      }
      Row({ space: CELL_GAP }) {
        ForEach(this.seq(5), (c: number) => {
          this.FrameCell(c + 5)
        }, (c: number) => 'fc' + (c + 5).toString())
      }
    }
    .padding(6)
    .borderRadius(12)
    .backgroundColor('#F5F9FF')
    .border({
      width: this.frameFull() ? 2 : 1,
      style: BorderStyle.Solid,
      color: this.frameFull() ? '#E7C25A' : KIDS_BORDER,
      radius: 12
    })
    .shadow({
      radius: this.frameFull() ? 9 : 0,
      color: this.frameFull() ? '#40F4C63D' : '#00000000',
      offsetY: 0
    })
  }

  @Builder
  FrameCaption() {
    Row({ space: 6 }) {
      Text('十格框').fontSize(12).fontColor(KIDS_MUTED)
      Text(`${this.frameFilledNow()} / 10`)
        .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)
    }
  }

  /** 第 4 步 / 答对后：剩块与个位块飞拢合并成的新队伍。 */
  @Builder
  MergedPart(n: number, label: string) {
    Row() {
      this.Part(n, makeTenBlockColor(n), label, false)
    }
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ x: -24 }))
      .animation({ duration: 360, curve: Curve.EaseOut }))
  }

  @Builder
  LessonLoose() {
    if (this.stepIndex === 0) {
      Row() {
        this.Part(this.ones(), makeTenBlockColor(this.ones()), `${this.ones()} 块 · 个位`, true)
      }
      .opacity(this.onesDim ? 0.4 : 1)
      .animation({ duration: 300, curve: Curve.EaseInOut })
    } else if (this.stepIndex === 3) {
      this.MergedPart(this.result(), `${this.fromTen()} + ${this.ones()} = ${this.result()}`)
    } else {
      this.Part(this.ones(), makeTenBlockColor(this.ones()), `${this.ones()} 块 · 个位`, false)
    }
  }

  @Builder
  PracticeLoose() {
    if (this.pPhase === 'solved') {
      this.MergedPart(this.practiceResult(),
        `${this.practiceFromTen()} + ${this.practiceOnes()} = ${this.practiceResult()}`)
    } else {
      this.Part(this.practiceOnes(), makeTenBlockColor(this.practiceOnes()),
        `${this.practiceOnes()} 块 · 个位`, false)
    }
  }

  @Builder
  VisualArea() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center, alignItems: ItemAlign.Center }) {
      Column({ space: 5 }) {
        this.TenFrame()
        this.FrameCaption()
      }
      .margin(4)

      Text('+')
        .fontSize(24).fontWeight(FontWeight.Bold).fontColor('#8A97AD')
        .margin({ left: 2, right: 2 })

      Column({ space: 5 }) {
        if (this.mode === 'lesson') {
          this.LessonLoose()
        } else {
          this.PracticeLoose()
        }
      }
      .margin(4)
    }
    .width('100%')
  }

  /** 分合 chip：a = 10 + ones（第 2 步起亮起）。 */
  @Builder
  BondChip() {
    Text(`${this.a} = 10 + ${this.ones()}`)
      .fontSize(13).fontWeight(FontWeight.Bold).fontColor(KIDS_ON_GOLD)
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .borderRadius(10)
      .backgroundColor('#FFF7DA')
      .border({ width: 1.5, style: BorderStyle.Dashed, color: '#EFD27C' })
  }

  // ── 算式 ─────────────────────────────────────────────────────────

  @Builder
  EqNum(text: string, tone: string) {
    Text(text)
      .fontSize(23)
      .fontWeight(FontWeight.Bold)
      .fontColor(tone === 'result' ? KIDS_FG : KIDS_MATH_INK)
      .textAlign(TextAlign.Center)
      .constraintSize({ minWidth: 20 })
      .padding({
        left: tone === '' ? 0 : 6,
        right: tone === '' ? 0 : 6,
        top: tone === '' ? 0 : 2,
        bottom: tone === '' ? 0 : 2
      })
      .borderRadius(9)
      .backgroundColor(tone === 'result'
        ? KIDS_STAR
        : (tone === 'group' ? withColorAlpha(KIDS_MATH, '14') : '#00000000'))
  }

  @Builder
  EqOp(text: string) {
    Text(text)
      .fontSize(20).fontWeight(FontWeight.Bold).fontColor('#93A1B8')
  }

  @Builder
  EqUnknown() {
    Text('?')
      .fontSize(19).fontWeight(FontWeight.Bold).fontColor('#93A1B8')
      .width(34).height(32).textAlign(TextAlign.Center)
      .borderRadius(9)
      .border({ width: 1.5, style: BorderStyle.Dashed, color: '#B9C7DD' })
  }

  @Builder
  EqGroup(ten: number, rest: number) {
    Row({ space: 2 }) {
      Text('(').fontSize(20).fontColor(KIDS_MATH_INK)
      this.EqNum(`${ten}`, '')
      this.EqOp('+')
      this.EqNum(`${rest}`, '')
      Text(')').fontSize(20).fontColor(KIDS_MATH_INK)
    }
    .padding({ left: 5, right: 5 })
    .borderRadius(9)
    .backgroundColor(withColorAlpha(KIDS_MATH, '14'))
  }

  @Builder
  LessonEquation() {
    if (this.stepIndex === 0) {
      this.EqNum(`${this.a}`, '')
      this.EqOp('-')
      this.EqNum(`${this.b}`, '')
      this.EqOp('=')
      this.EqUnknown()
    } else if (this.stepIndex === 1) {
      if (this.crossing) {
        this.EqNum('10', '')
        this.EqOp('-')
        this.EqNum(`${this.b}`, '')
        this.EqOp('=')
        this.EqUnknown()
      } else {
        this.EqGroup(10, this.ones())
        this.EqOp('-')
        this.EqNum(`${this.b}`, '')
        this.EqOp('=')
        this.EqUnknown()
      }
    } else if (this.stepIndex === 2) {
      this.EqNum('10', '')
      this.EqOp('-')
      this.EqNum(`${this.b}`, '')
      this.EqOp('=')
      this.EqNum(`${this.fromTen()}`, 'group')
    } else {
      this.EqNum(`${this.fromTen()}`, '')
      this.EqOp('+')
      this.EqNum(`${this.ones()}`, '')
      this.EqOp('=')
      this.EqNum(`${this.result()}`, 'result')
    }
  }

  @Builder
  PracticeEquation() {
    if (this.pPhase === 'solved') {
      this.EqNum(`${this.practiceA()}`, '')
      this.EqOp('-')
      this.EqNum(`${this.practiceB()}`, '')
      this.EqOp('=')
      this.EqNum(`${this.practiceResult()}`, 'result')
    } else {
      this.EqNum('10', '')
      this.EqOp('-')
      this.EqNum(`${this.practiceB()}`, '')
      this.EqOp('=')
      this.EqUnknown()
    }
  }

  @Builder
  EquationRow() {
    Row({ space: 2 }) {
      if (this.mode === 'lesson') {
        this.LessonEquation()
      } else {
        this.PracticeEquation()
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  HintLine() {
    Text(this.hintText())
      .fontSize(12.5).fontColor(KIDS_MUTED).lineHeight(19)
      .textAlign(TextAlign.Center)
      .width('100%')
  }

  // ── 引导卡 ───────────────────────────────────────────────────────

  @Builder
  GuideCard() {
    Row({ space: 10 }) {
      Stack() {
        this.BlockSquare(26, KIDS_ACCENT, true)
      }
      .width(42).height(42)
      .borderRadius(13)
      .backgroundColor(KIDS_SURFACE)
      .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha(KIDS_MATH, '30') })

      Column({ space: 5 }) {
        Text(this.guideChip())
          .fontSize(11).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(9)
          .backgroundColor(KIDS_SURFACE)
          .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha(KIDS_MATH, '30') })
        Text(this.guideText())
          .fontSize(13.5).fontColor(KIDS_FG).lineHeight(20)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding(12)
    .borderRadius(14)
    .backgroundColor(withColorAlpha(KIDS_MATH, '0E'))
    .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha(KIDS_MATH, '30') })
  }

  // ── 步骤条 / 口诀卡 ──────────────────────────────────────────────

  @Builder
  StepChip(idx: number) {
    Row({ space: 6 }) {
      Stack() {
        Text(`${idx + 1}`)
          .fontSize(11).fontWeight(FontWeight.Bold)
          .fontColor(idx < this.stepIndex ? '#16704A' : Color.White)
      }
      .width(21).height(21).borderRadius(11)
      .backgroundColor(this.stepIndex === idx
        ? KIDS_MATH_INK
        : (idx < this.stepIndex ? '#DDF3E7' : '#EDF2FA'))

      Text(this.stepTitleAt(idx))
        .fontSize(12).fontWeight(FontWeight.Bold)
        .fontColor(this.stepIndex === idx ? KIDS_MATH_INK : KIDS_MUTED)
        .maxLines(1)

      if (idx < this.stepIndex) {
        Text('✓').fontSize(11).fontWeight(FontWeight.Bold).fontColor('#16704A')
      }
    }
    .padding({ left: 8, right: 8, top: 5, bottom: 5 })
    .borderRadius(9)
    .backgroundColor(this.stepIndex === idx ? withColorAlpha(KIDS_MATH, '12') : Color.Transparent)
    .border({
      width: 1,
      style: BorderStyle.Solid,
      color: this.stepIndex === idx ? withColorAlpha(KIDS_MATH, '50') : '#00000000'
    })
    .opacity(idx <= this.maxStep ? 1 : 0.45)
    .accessibilityText(`第 ${idx + 1} 步 ${this.stepTitleAt(idx)}`)
    .onClick(() => {
      this.goToStep(idx)
    })
  }

  private stepTitleAt(idx: number): string {
    const steps: BreakTenLessonStep[] = breakTenLessonSteps(this.a, this.b)
    return steps[idx].title
  }

  @Builder
  StepStrip() {
    Scroll() {
      Row({ space: 4 }) {
        ForEach(this.seq(STEP_TOTAL), (idx: number) => {
          this.StepChip(idx)
        }, (idx: number) => 'step' + idx.toString())
      }
      .padding({ left: 2, right: 2 })
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }

  @Builder
  MnemonicCard() {
    Column({ space: 4 }) {
      Text('破十小口诀')
        .fontSize(11).fontWeight(FontWeight.Bold).fontColor(KIDS_MUTED)
        .width('100%')
      Text('个位不够减，拆出 10 来减；减完再加回个位。')
        .fontSize(12.5).fontColor(KIDS_FG).lineHeight(19)
        .width('100%')
      Text(`${this.a} - ${this.b} = 10 - ${this.b} + ${this.ones()}`)
        .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(8)
        .backgroundColor(withColorAlpha(KIDS_MATH, '0E'))
        .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha(KIDS_MATH, '30') })
    }
    .width('100%')
    .padding(10)
    .borderRadius(12)
    .backgroundColor(KIDS_SURFACE)
    .border({ width: 1, style: BorderStyle.Solid, color: KIDS_BORDER })
  }

  // ── 练习区 ───────────────────────────────────────────────────────

  @Builder
  PracticeHeader() {
    Column({ space: 5 }) {
      Row() {
        Text('练习闯关')
          .fontSize(11).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
        Blank()
        Text(`★ ${this.pStars} 颗`)
          .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_ON_GOLD)
      }
      .width('100%')

      Text(`第 ${this.pIndex + 1} / ${this.problems.length} 题`)
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)

      Row({ space: 4 }) {
        ForEach(this.seq(PRACTICE_TOTAL), (i: number) => {
          Row()
            .width(22).height(6).borderRadius(3)
            .backgroundColor(i < this.pIndex
              ? '#16704A'
              : (i === this.pIndex ? KIDS_MATH : '#E3EAF6'))
        }, (i: number) => 'dot' + i.toString())
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(12)
    .backgroundColor(KIDS_SURFACE)
    .border({ width: 1, style: BorderStyle.Solid, color: KIDS_BORDER })
  }

  @Builder
  OptionButton(value: number, idx: number) {
    Column({ space: 1 }) {
      Text(`${value}`)
        .fontSize(25).fontWeight(FontWeight.Bold)
        .fontColor(this.wrongOptionIdx === idx ? KIDS_CHINESE_INK : KIDS_FG)
      Text('块')
        .fontSize(10).fontColor(this.wrongOptionIdx === idx ? KIDS_CHINESE_INK : KIDS_MUTED)
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .borderRadius(12)
    .backgroundColor(this.wrongOptionIdx === idx
      ? withColorAlpha(KIDS_CHINESE_INK, '12')
      : KIDS_SURFACE)
    .border({
      width: 1.5,
      style: BorderStyle.Solid,
      color: this.wrongOptionIdx === idx ? KIDS_CHINESE_INK : KIDS_BORDER,
      radius: 12
    })
    .translate({ x: this.wrongOptionIdx === idx ? 5 : 0 })
    .animation({ duration: 60, curve: Curve.EaseOut })
    .accessibilityText(`选项 ${value}`)
    .onClick(() => {
      this.tapOption(idx)
    })
  }

  @Builder
  OptionsRow() {
    Row({ space: 8 }) {
      ForEach(this.currentProblem().options, (value: number, idx: number) => {
        this.OptionButton(value, idx)
      }, (value: number, idx: number) => 'opt' + idx.toString() + '_' + value.toString())
    }
    .width('100%')
  }

  @Builder
  PracticeFeedback() {
    if (this.pPhase === 'ask') {
      Row({ space: 7 }) {
        Stack() {
          Text(this.wrongOptionIdx >= 0 ? '!' : '?')
            .fontSize(11).fontWeight(FontWeight.Bold)
            .fontColor(this.wrongOptionIdx >= 0 ? KIDS_CHINESE_INK : KIDS_MATH_INK)
        }
        .width(21).height(21).borderRadius(11)
        .backgroundColor(this.wrongOptionIdx >= 0
          ? withColorAlpha(KIDS_CHINESE_INK, '12')
          : withColorAlpha(KIDS_MATH, '12'))

        Text(this.wrongOptionIdx >= 0
          ? `再想想：从 10 往回数 ${this.practiceB()} 下，数到几？`
          : `关键一步：10 - ${this.practiceB()} = ?`)
          .fontSize(12.5).fontColor(KIDS_MUTED).layoutWeight(1)
      }
      .width('100%')
    } else if (this.pPhase === 'crossing') {
      Row({ space: 8 }) {
        LoadingProgress().width(18).height(18).color(KIDS_MATH)
        Text(`正在从 10 里划掉 ${this.practiceB()} 块…`)
          .fontSize(12.5).fontColor(KIDS_MUTED)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.pPhase === 'solved') {
      Column({ space: 8 }) {
        Row({ space: 7 }) {
          Stack() {
            Text('✓').fontSize(12).fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.status_success'))
          }
          .width(22).height(22).borderRadius(11)
          .backgroundColor(Color.White)
          Text(this.pClean ? '一次答对，太棒了！' : '这次答对了，继续加油！')
            .fontSize(13.5).fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.status_success'))
        }
        .width('100%')
        .padding(10)
        .borderRadius(12)
        .backgroundColor(withColorAlpha('#16704A', '12'))
        .border({ width: 1, style: BorderStyle.Solid, color: withColorAlpha('#16704A', '30') })

        Button(this.pIndex + 1 >= this.problems.length ? '查看成绩' : '下一题')
          .width('100%').height(46).fontSize(14)
          .backgroundColor(KIDS_MATH_INK)
          .fontColor(Color.White)
          .accessibilityText(this.pIndex + 1 >= this.problems.length ? '查看成绩' : '下一题')
          .onClick(() => {
            this.nextQuestion()
          })
      }
      .width('100%')
    }
  }

  @Builder
  FinishView() {
    Column({ space: 10 }) {
      Row({ space: 4 }) {
        ForEach(this.seq(5), (i: number) => {
          Text('★').fontSize(30).fontColor(KIDS_STAR)
        }, (i: number) => 'fs' + i.toString())
      }
      Text('练习完成')
        .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
      Text('5 道题全部完成')
        .fontSize(21).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)
      Text('你已经会用破十法了：先算 10 减几，再加回个位。')
        .fontSize(13).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
      Button('再来一轮')
        .width(200).height(46).fontSize(14)
        .backgroundColor(KIDS_MATH_INK).fontColor(Color.White)
        .margin({ top: 4 })
        .accessibilityText('再来一轮')
        .onClick(() => {
          this.startRound()
        })
      Button('回学一学')
        .width(200).height(44).fontSize(13)
        .backgroundColor(withColorAlpha(KIDS_FG, '08'))
        .fontColor(KIDS_FG)
        .accessibilityText('回学一学')
        .onClick(() => {
          this.switchMode('lesson')
        })
    }
    .width('100%')
    .padding({ top: 24, bottom: 18 })
    .alignItems(HorizontalAlign.Center)
  }

  // ── 讲解动作 ─────────────────────────────────────────────────────

  @Builder
  LessonActions() {
    if (this.readonly) {
      Row({ space: 6 }) {
        Text('✓').fontSize(13).fontColor($r('app.color.status_success'))
        Text('本课完成 · 先十里减，再加回来')
          .fontSize(12.5).fontColor($r('app.color.status_success'))
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.stepIndex === STEP_TOTAL - 1) {
      Row({ space: 10 }) {
        Button('去练一练')
          .layoutWeight(1).height(46).fontSize(14)
          .backgroundColor(KIDS_MATH_INK).fontColor(Color.White)
          .accessibilityText('去练一练')
          .onClick(() => {
            this.switchMode('practice')
          })
        Button('重来')
          .width(82).height(46).fontSize(13)
          .backgroundColor(withColorAlpha(KIDS_FG, '08'))
          .fontColor(KIDS_FG)
          .accessibilityText('重来')
          .onClick(() => {
            this.resetLesson()
          })
      }
      .width('100%')
    } else {
      Row({ space: 10 }) {
        Button(this.crossing ? '正在划掉…' : this.currentStep().action)
          .layoutWeight(1).height(46).fontSize(14)
          .backgroundColor(KIDS_MATH_INK).fontColor(Color.White)
          .enabled(!this.crossing)
          .opacity(this.crossing ? 0.55 : 1)
          .accessibilityText(this.crossing ? '正在划掉' : this.currentStep().action)
          .onClick(() => {
            this.goNext()
          })
        Button('重来')
          .width(82).height(46).fontSize(13)
          .backgroundColor(withColorAlpha(KIDS_FG, '08'))
          .fontColor(KIDS_FG)
          .enabled(!this.crossing)
          .opacity(this.crossing ? 0.55 : 1)
          .accessibilityText('重来')
          .onClick(() => {
            this.resetLesson()
          })
      }
      .width('100%')
    }
  }

  // ── 视图 ─────────────────────────────────────────────────────────

  @Builder
  ModeTabs() {
    Row({ space: 4 }) {
      Button('学一学')
        .layoutWeight(1).height(34).fontSize(13)
        .fontColor(this.mode === 'lesson' ? Color.White : KIDS_MUTED)
        .backgroundColor(this.mode === 'lesson' ? KIDS_MATH_INK : Color.Transparent)
        .borderRadius(9)
        .accessibilityText('学一学')
        .onClick(() => {
          this.switchMode('lesson')
        })
      Button('练一练')
        .layoutWeight(1).height(34).fontSize(13)
        .fontColor(this.mode === 'practice' ? Color.White : KIDS_MUTED)
        .backgroundColor(this.mode === 'practice' ? KIDS_MATH_INK : Color.Transparent)
        .borderRadius(9)
        .accessibilityText('练一练')
        .onClick(() => {
          this.switchMode('practice')
        })
    }
    .width('100%')
    .padding(4)
    .borderRadius(12)
    .backgroundColor(withColorAlpha(KIDS_MATH, '08'))
    .border({ width: 1, style: BorderStyle.Solid, color: KIDS_BORDER })
  }

  @Builder
  LessonView() {
    Column({ space: 10 }) {
      this.StepStrip()
      this.GuideCard()
      this.VisualArea()
      if (this.stepIndex >= 1) {
        this.BondChip()
      }
      this.EquationRow()
      this.HintLine()
      this.MnemonicCard()
      this.LessonActions()
    }
    .width('100%')
  }

  @Builder
  PracticeView() {
    if (this.pPhase === 'done') {
      this.FinishView()
    } else {
      Column({ space: 10 }) {
        this.PracticeHeader()
        this.GuideCard()
        this.VisualArea()
        this.EquationRow()
        this.HintLine()
        if (this.pPhase === 'ask') {
          this.OptionsRow()
        }
        this.PracticeFeedback()
        this.MnemonicCard()
      }
      .width('100%')
    }
  }

  build() {
    Column({ space: 10 }) {
      if (!this.readonly) {
        this.ModeTabs()
      }
      if (this.mode === 'lesson' || this.readonly) {
        this.LessonView()
      } else {
        this.PracticeView()
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}