import {
  makeTenFriend, makeTenRemain, makeTenLessonSteps, makeTenStepNarrations,
  makeTenPracticeRound, makeTenProblem, makeTenFriendPairs, makeTenBlockColor,
  makeTenShade, makeTenIsLight,
  MakeTenLessonStep, MakeTenProblem, MakeTenPair
} from '../../utils/MathTeachMakeTen'
import { AppStorageKeys } from '../../config/AppStorageKeys'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { normalizeMathSymbolsForTts } from '../../utils/TtsTextUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  KIDS_ACCENT, KIDS_BORDER, KIDS_CHINESE_INK, KIDS_FG, KIDS_MATH, KIDS_MATH_INK,
  KIDS_MUTED, KIDS_ON_GOLD, KIDS_STAR, KIDS_SURFACE
} from '../kids/KidsBrandTokens'

/**
 * TenFrameBoard - 十格阵凑十引导课（math_teach · ten_frame 模式）
 *
 * 对齐原型 docs 原型「凑十小队 · 方块小人的十格课堂」：
 * - 学一学：4 步（看大数 → 拆小数 → 凑成十 → 十加几），Numberblocks
 *   风格彩色方块小人 + 十格框 + 送块逐格弹入 + 凑十好朋友配对卡。
 * - 练一练：5 题迁移闯关（选块数 → 送块 → 成功 → 下一题 → 成绩页）。
 *
 * 完成门：讲解 4 步各计一次；练习每答对一题计一次。shell 层
 * interactionThreshold 对 ten_frame 配 4。回执契约不变。
 *
 * TTS：语音模式开启时（AppStorage VOICE_MODE_ENABLED，与 VerticalMathCard
 * 同一开关），进入每步朗读该步口播稿；回退/离开即 stop。已答历史态不播。
 */

const STEP_TOTAL: number = 4
const PRACTICE_TOTAL: number = 5
const CELL: number = 28
const CELL_GAP: number = 4
const UNIT: number = 16
const UNIT_GAP: number = 2
const WRONG_FLASH_MS: number = 420
const FILL_STEP_MS: number = 90
const FILL_SETTLE_MS: number = 300

@ComponentV2
export struct TenFrameBoard {
  @Param a: number = 9
  @Param b: number = 5
  @Param readonly: boolean = false
  @Event onInteract: () => void = () => {}

  // 讲解
  @Local mode: string = 'lesson'
  @Local stepIndex: number = 0
  @Local maxStep: number = 0
  @Local sending: boolean = false
  @Local fillExtra: number = 0

  // 练习
  @Local practiceStarted: boolean = false
  @Local problems: MakeTenProblem[] = []
  @Local pIndex: number = 0
  @Local pPhase: string = 'ask'
  @Local pAttempts: number = 0
  @Local pClean: boolean = true
  @Local pStars: number = 0
  @Local pFillExtra: number = 0
  @Local wrongOptionIdx: number = -1

  private stepDoneFlags: boolean[] = [false, false, false, false]
  private timerIds: number[] = []
  private wrongTimerId: number = -1
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
  }

  aboutToDisappear(): void {
    this.clearFillTimers()
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

  private currentStep(): MakeTenLessonStep {
    const steps: MakeTenLessonStep[] = makeTenLessonSteps(this.a, this.b)
    return steps[this.stepIndex]
  }

  private currentProblem(): MakeTenProblem {
    if (this.pIndex >= 0 && this.pIndex < this.problems.length) {
      return this.problems[this.pIndex]
    }
    return makeTenProblem(this.a, this.b)
  }

  private practiceNeed(): number {
    return this.currentProblem().need
  }

  private practiceRest(): number {
    return this.currentProblem().rest
  }

  private practiceSum(): number {
    return this.currentProblem().a + this.currentProblem().b
  }

  private practiceBig(): number {
    return this.currentProblem().a
  }

  private practiceSmall(): number {
    return this.currentProblem().b
  }

  // ── 十格框派生 ───────────────────────────────────────────────────

  private lessonExtra(): number {
    if (this.stepIndex >= 2) {
      return this.friend()
    }
    if (this.stepIndex === 1 && this.sending) {
      return this.fillExtra
    }
    return 0
  }

  private practiceExtra(): number {
    if (this.pPhase === 'solved') {
      return this.practiceNeed()
    }
    if (this.pPhase === 'sending') {
      return this.pFillExtra
    }
    return 0
  }

  private frameBase(): number {
    if (this.mode === 'practice') {
      return this.practiceBig()
    }
    return this.a
  }

  private frameFilled(): number {
    if (this.mode === 'practice') {
      return this.frameBase() + this.practiceExtra()
    }
    return this.frameBase() + this.lessonExtra()
  }

  private frameColorAt(idx: number): string {
    if (idx < this.frameBase()) {
      if (this.mode === 'practice') {
        return makeTenBlockColor(this.practiceBig())
      }
      return makeTenBlockColor(this.a)
    }
    if (this.mode === 'practice') {
      return makeTenBlockColor(this.practiceSmall())
    }
    return makeTenBlockColor(this.b)
  }

  private frameReady(): boolean {
    if (this.mode === 'practice') {
      return this.pPhase === 'ask'
    }
    return this.stepIndex === 1 && !this.sending
  }

  private frameFull(): boolean {
    return this.frameFilled() >= 10
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

  // ── 讲解导航 ─────────────────────────────────────────────────────

  private goNext(): void {
    if (this.readonly || this.sending) {
      return
    }
    if (this.stepIndex === 0) {
      this.stepIndex = 1
      this.maxStep = Math.max(this.maxStep, 1)
      this.markStepDone(1)
      this.speakStep(1)
      return
    }
    if (this.stepIndex === 1) {
      this.startSend()
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
    if (this.readonly || this.sending || idx < 0 || idx > this.maxStep || idx === this.stepIndex) {
      return
    }
    this.stepIndex = idx
    this.speakStep(idx)
  }

  private resetLesson(): void {
    if (this.readonly || this.sending) {
      return
    }
    this.clearFillTimers()
    this.fillExtra = 0
    this.stepIndex = 0
    this.maxStep = 0
    this.speakStep(0)
  }

  private startSend(): void {
    if (this.readonly || this.sending) {
      return
    }
    this.clearFillTimers()
    this.sending = true
    this.fillExtra = 0
    const need: number = this.friend()
    for (let i = 1; i <= need; i++) {
      const id: number = setTimeout(() => {
        this.fillExtra = i
      }, i * FILL_STEP_MS)
      this.timerIds.push(id)
    }
    const doneId: number = setTimeout(() => {
      this.finishSend()
    }, need * FILL_STEP_MS + FILL_SETTLE_MS)
    this.timerIds.push(doneId)
  }

  private finishSend(): void {
    this.sending = false
    this.fillExtra = this.friend()
    this.stepIndex = 2
    this.maxStep = Math.max(this.maxStep, 2)
    this.markStepDone(2)
    this.speakStep(2)
  }

  private clearFillTimers(): void {
    for (let i = 0; i < this.timerIds.length; i++) {
      clearTimeout(this.timerIds[i])
    }
    this.timerIds = []
  }

  // ── 练习流程 ─────────────────────────────────────────────────────

  private switchMode(mode: string): void {
    // 讲解送块动画中不许切页（与原型 busy 门一致），否则 finishSend 会在练习页迟到触发
    if (this.readonly || this.mode === mode || this.sending) {
      return
    }
    // 练习送块动画中切回讲解：取消未完成的送块，退回答题态，本题重新答
    if (mode === 'lesson' && this.pPhase === 'sending') {
      this.clearFillTimers()
      this.pFillExtra = 0
      this.pPhase = 'ask'
    }
    this.mode = mode
    if (mode === 'practice') {
      if (!this.practiceStarted || this.pPhase === 'done') {
        this.startRound()
      } else {
        this.speak(this.guideText())
      }
    }
  }

  private startRound(): void {
    this.clearFillTimers()
    // 顶层一律换新数组，触发 @Local 响应式刷新
    this.problems = makeTenPracticeRound(this.a, this.b, PRACTICE_TOTAL)
    this.pIndex = 0
    this.pPhase = 'ask'
    this.pAttempts = 0
    this.pClean = true
    this.pStars = 0
    this.pFillExtra = 0
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
    if (options[idx] !== this.practiceNeed()) {
      this.pAttempts += 1
      this.flashWrong(idx)
      return
    }
    this.pClean = this.pAttempts === 0
    this.pPhase = 'sending'
    this.pFillExtra = 0
    this.clearFillTimers()
    const need: number = this.practiceNeed()
    for (let i = 1; i <= need; i++) {
      const id: number = setTimeout(() => {
        this.pFillExtra = i
      }, i * FILL_STEP_MS)
      this.timerIds.push(id)
    }
    const doneId: number = setTimeout(() => {
      this.finishPractice()
    }, need * FILL_STEP_MS + FILL_SETTLE_MS)
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
    this.pFillExtra = 0
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
    return `从 ${this.practiceSmall()} 里拿几块放进空格，正好凑成 10？`
  }

  private practiceSolvedText(): string {
    return `十格框满了，是 10。再加剩下的 ${this.practiceRest()}，` +
      `${this.practiceBig()} + ${this.practiceSmall()} = ${this.practiceSum()}。`
  }

  private guideChip(): string {
    if (this.mode === 'lesson') {
      return this.currentStep().chip
    }
    if (this.pPhase === 'sending') {
      return '正在凑十'
    }
    if (this.pPhase === 'solved') {
      return '凑十成功'
    }
    return `${this.practiceBig()} + ${this.practiceSmall()}`
  }

  private guideText(): string {
    if (this.mode === 'lesson') {
      return this.currentStep().narration
    }
    if (this.pPhase === 'sending') {
      return `把 ${this.practiceNeed()} 块送进十格框，${this.practiceBig()} 就变成 10 了。`
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
    if (this.pPhase === 'sending') {
      return `${this.practiceBig()} + ${this.practiceNeed()} = 10`
    }
    if (this.pPhase === 'solved') {
      return `10 + ${this.practiceRest()} = ${this.practiceSum()}`
    }
    return '空格有几格，就从右边的队伍里拿几块。'
  }

  private needNow(): number {
    if (this.mode === 'practice') {
      return this.practiceNeed()
    }
    return this.friend()
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
    const narrations: string[] = makeTenStepNarrations(this.a, this.b)
    this.speak(narrations[step])
  }

  private speak(text: string): void {
    if (this.readonly || !this.isVoiceEnabled() || text === '') {
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

  /** 一队方块 + 药丸标签；need=true 时加虚线蓝框（要送走的那一队）。 */
  @Builder
  Part(n: number, color: string, label: string, need: boolean) {
    Column({ space: 6 }) {
      if (need) {
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
        .fontColor(need ? KIDS_MATH_INK : KIDS_MUTED)
        .maxLines(1)
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .borderRadius(10)
        .backgroundColor(need ? withColorAlpha(KIDS_MATH, '10') : KIDS_SURFACE)
        .border({
          width: 1,
          style: BorderStyle.Solid,
          color: need ? withColorAlpha(KIDS_MATH, '40') : KIDS_BORDER
        })
    }
  }

  @Builder
  FrameCell(idx: number) {
    Stack() {
      if (idx < this.frameFilled()) {
        this.BlockSquare(CELL - 2, this.frameColorAt(idx), false)
      }
    }
    .width(CELL).height(CELL)
    .borderRadius(7)
    .backgroundColor(idx < this.frameFilled()
      ? Color.Transparent
      : (this.frameReady() ? withColorAlpha(KIDS_MATH, '0C') : Color.White))
    .border({
      width: idx < this.frameFilled() ? 0 : 1.5,
      style: idx < this.frameFilled() ? BorderStyle.Solid : BorderStyle.Dashed,
      color: this.frameReady() ? KIDS_MATH : '#C9D6EA',
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
      Text(`${this.frameFilled()} / 10`)
        .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)
    }
  }

  @Builder
  LessonLoose() {
    if (this.stepIndex === 0) {
      this.Part(this.b, makeTenBlockColor(this.b), `${this.b} 块待拆`, false)
    } else if (this.stepIndex === 1) {
      Row({ space: 10 }) {
        this.Part(this.friend(), makeTenBlockColor(this.b), `送走 ${this.friend()}`, true)
        this.Part(this.rest(), makeTenBlockColor(this.b), `剩下 ${this.rest()}`, false)
      }
      .alignItems(VerticalAlign.Bottom)
    } else {
      this.Part(this.rest(), makeTenBlockColor(this.b), `剩下 ${this.rest()} 块`, false)
    }
  }

  @Builder
  PracticeLoose() {
    if (this.pPhase === 'ask') {
      this.Part(this.practiceSmall(), makeTenBlockColor(this.practiceSmall()),
        `${this.practiceSmall()} 块`, false)
    } else if (this.pPhase === 'sending') {
      Row({ space: 10 }) {
        this.Part(this.practiceNeed(), makeTenBlockColor(this.practiceSmall()),
          `送走 ${this.practiceNeed()}`, true)
        this.Part(this.practiceRest(), makeTenBlockColor(this.practiceSmall()),
          `剩下 ${this.practiceRest()}`, false)
      }
      .alignItems(VerticalAlign.Bottom)
    } else {
      this.Part(this.practiceRest(), makeTenBlockColor(this.practiceSmall()),
        `剩下 ${this.practiceRest()} 块`, false)
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
  EqGroup(need: number, rest: number) {
    Row({ space: 2 }) {
      Text('(').fontSize(20).fontColor(KIDS_MATH_INK)
      this.EqNum(`${need}`, '')
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
      this.EqOp('+')
      this.EqNum(`${this.b}`, '')
      this.EqOp('=')
      this.EqUnknown()
    } else if (this.stepIndex === 1) {
      this.EqNum(`${this.a}`, '')
      this.EqOp('+')
      this.EqGroup(this.friend(), this.rest())
      this.EqOp('=')
      this.EqUnknown()
    } else if (this.stepIndex === 2) {
      this.EqNum('10', '')
      this.EqOp('+')
      this.EqNum(`${this.rest()}`, '')
      this.EqOp('=')
      this.EqUnknown()
    } else {
      this.EqNum('10', '')
      this.EqOp('+')
      this.EqNum(`${this.rest()}`, '')
      this.EqOp('=')
      this.EqNum(`${this.sum()}`, 'result')
    }
  }

  @Builder
  PracticeEquation() {
    if (this.pPhase === 'sending') {
      this.EqNum(`${this.practiceBig()}`, '')
      this.EqOp('+')
      this.EqGroup(this.practiceNeed(), this.practiceRest())
      this.EqOp('=')
      this.EqUnknown()
    } else if (this.pPhase === 'solved') {
      this.EqNum(`${this.practiceBig()}`, '')
      this.EqOp('+')
      this.EqNum(`${this.practiceSmall()}`, '')
      this.EqOp('=')
      this.EqNum(`${this.practiceSum()}`, 'result')
    } else {
      this.EqNum(`${this.practiceBig()}`, '')
      this.EqOp('+')
      this.EqNum(`${this.practiceSmall()}`, '')
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

  // ── 步骤条 / 好朋友 ──────────────────────────────────────────────

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
    .onClick(() => {
      this.goToStep(idx)
    })
  }

  private stepTitleAt(idx: number): string {
    const steps: MakeTenLessonStep[] = makeTenLessonSteps(this.a, this.b)
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
  PairChip(pair: MakeTenPair) {
    Row({ space: 3 }) {
      Row()
        .width(9).height(9).borderRadius(3)
        .backgroundColor(makeTenBlockColor(pair.x))
      Text(`${pair.x}`).fontSize(11).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)
      Text('+').fontSize(10).fontColor('#93A1B8')
      Row()
        .width(9).height(9).borderRadius(3)
        .backgroundColor(makeTenBlockColor(pair.y))
      Text(`${pair.y}`).fontSize(11).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)
    }
    .padding({ left: 6, right: 6, top: 3, bottom: 3 })
    .margin(2)
    .borderRadius(8)
    .backgroundColor(Math.min(pair.x, pair.y) === this.needNow()
      ? '#FFF7DA'
      : withColorAlpha(KIDS_FG, '04'))
    .border({
      width: 1,
      style: BorderStyle.Solid,
      color: Math.min(pair.x, pair.y) === this.needNow() ? '#EFD27C' : KIDS_BORDER
    })
  }

  @Builder
  FriendsCard() {
    Column({ space: 4 }) {
      Text('凑十好朋友')
        .fontSize(11).fontWeight(FontWeight.Bold).fontColor(KIDS_MUTED)
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(makeTenFriendPairs(), (pair: MakeTenPair) => {
          this.PairChip(pair)
        }, (pair: MakeTenPair) => 'pair' + pair.x.toString())
      }
      .width('100%')
      Text('见 9 想 1，见 8 想 2……')
        .fontSize(11).fontColor(KIDS_MUTED)
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
          ? `再想想：${this.practiceBig()} 和几凑成 10？看看下面的好朋友卡。`
          : '数一数，空格里还差几块？')
          .fontSize(12.5).fontColor(KIDS_MUTED).layoutWeight(1)
      }
      .width('100%')
    } else if (this.pPhase === 'sending') {
      Row({ space: 8 }) {
        LoadingProgress().width(18).height(18).color(KIDS_MATH)
        Text(`正在把 ${this.practiceNeed()} 块送进十格框…`)
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
      Text('你已经会用凑十法了：先凑成 10，再多加几。')
        .fontSize(13).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
      Button('再来一轮')
        .width(200).height(46).fontSize(14)
        .backgroundColor(KIDS_MATH_INK).fontColor(Color.White)
        .margin({ top: 4 })
        .onClick(() => {
          this.startRound()
        })
      Button('回学一学')
        .width(200).height(44).fontSize(13)
        .backgroundColor(withColorAlpha(KIDS_FG, '08'))
        .fontColor(KIDS_FG)
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
        Text('本课完成 · 先凑成 10，再多加几')
          .fontSize(12.5).fontColor($r('app.color.status_success'))
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.stepIndex === STEP_TOTAL - 1) {
      Row({ space: 10 }) {
        Button('去练一练')
          .layoutWeight(1).height(46).fontSize(14)
          .backgroundColor(KIDS_MATH_INK).fontColor(Color.White)
          .onClick(() => {
            this.switchMode('practice')
          })
        Button('重来')
          .width(82).height(46).fontSize(13)
          .backgroundColor(withColorAlpha(KIDS_FG, '08'))
          .fontColor(KIDS_FG)
          .onClick(() => {
            this.resetLesson()
          })
      }
      .width('100%')
    } else {
      Row({ space: 10 }) {
        Button(this.sending ? '正在凑十…' : this.currentStep().action)
          .layoutWeight(1).height(46).fontSize(14)
          .backgroundColor(KIDS_MATH_INK).fontColor(Color.White)
          .enabled(!this.sending)
          .opacity(this.sending ? 0.55 : 1)
          .onClick(() => {
            this.goNext()
          })
        Button('重来')
          .width(82).height(46).fontSize(13)
          .backgroundColor(withColorAlpha(KIDS_FG, '08'))
          .fontColor(KIDS_FG)
          .enabled(!this.sending)
          .opacity(this.sending ? 0.55 : 1)
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
        .onClick(() => {
          this.switchMode('lesson')
        })
      Button('练一练')
        .layoutWeight(1).height(34).fontSize(13)
        .fontColor(this.mode === 'practice' ? Color.White : KIDS_MUTED)
        .backgroundColor(this.mode === 'practice' ? KIDS_MATH_INK : Color.Transparent)
        .borderRadius(9)
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
      this.EquationRow()
      this.HintLine()
      this.FriendsCard()
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
        this.FriendsCard()
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
