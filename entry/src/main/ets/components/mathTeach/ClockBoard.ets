import { clockAngles, ClockAngles } from '../../utils/MathTeachBoards'
import {
  KIDS_MATH, KIDS_MATH_INK, KIDS_MUTED, KIDS_BORDER,
  KIDS_SURFACE, KIDS_FG, KIDS_SUBTLE, KIDS_ACCENT, KIDS_ON_HERO
} from '../kids/KidsBrandTokens'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { AppStorageKeys } from '../../config/AppStorageKeys'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { normalizeMathSymbolsForTts } from '../../utils/TtsTextUtils'

/**
 * ClockBoard - 时钟拨一拨讲解课（math_teach · clock 模式）
 *
 * 参考 docs/clock-telling-lesson.html 的两段式课程原型：
 * - 认一认：4 张图例卡（短针时针 / 长针分针 / 12 个数字 / 大格小格），
 *   点击聚焦——钟面对应层保持、其余淡化 0.26，下方讲解笔记随聚焦切换；
 * - 拨一拨：拖拽指针（按角度差就近判定抓哪根，松手吸附当前步长）、
 *   步长三档（整点 60 / 半点 30 / 5 分 5）、时分 ± 步进器、
 *   数字读出（3:30 + 「3 时 30 分」）、「一步一步读」三步引导
 *   （先短针定时 → 再长针定分 → 合起来读，当前步卡片高亮 + 另一根指针淡化）。
 *
 * 时间用 totalMin（自 12:00 起的分钟数，模 720）单一状态驱动：
 * 时针随分钟连续偏移 0.5°/分（clockAngles 已覆盖），粒度 5 分钟步长
 * （与 MathTeachValidation 的 minute 校验、BuiltinTools schema、
 * kids_math 提示词契约同步拓宽）。
 *
 * 完成门：图例点击 / 拖拽松手 / 步进 / 步长切换 / 引导步进 各计一次
 * onInteract()，shell 层 interactionThreshold 对 clock 配 4。
 * 已答历史态（readonly）：只渲染钟面 + 读出，不渲染交互区。
 *
 * TTS：语音模式开启时（AppStorage VOICE_MODE_ENABLED，与 NumberBondBoard /
 * TenFrameBoard 同一开关），「一步一步读」每推进一步朗读该步口播稿
 * （带「第一步/第二步/第三步」提示词）；时间被改动的交互与回退、切 tab
 * 会让旁白过时——直接停播。已答历史态不播。
 */

// 钟面几何（Stack 216 含 12% 淡橙外环；face 圆 200 居中于 8,8）
const FACE_BOX: number = 216
const FACE_D: number = 200
const C: number = 108
const RING_PAD: number = 8
const NUM_R: number = 72
// 指针/图层淡入淡出（拖拽跟手用短时长 EaseOut，不用 spring——避免连续更新时橡皮筋抖动）
const HAND_ANIM: AnimateParam = { duration: 160, curve: Curve.EaseOut }

/** 刻度线端点（12 点方向为 0°，顺时针均分 60 根） */
interface TickSpec {
  x1: number
  y1: number
  x2: number
  y2: number
  major: boolean
}

/** 钟面在窗口空间的 bbox（globalPosition + 宽高），供拖拽角度换算使用 */
interface ClockFaceRect {
  x: number
  y: number
  w: number
  h: number
}

// 认一认图例（数组 + 下标访问；动态键 Record 在 ArkTS 严格模式不可用）
const LEGEND_IDS: string[] = ['hour', 'minute', 'numbers', 'ticks']
const LEGEND_NAMES: string[] = ['短针 · 时针', '长针 · 分针', '12 个数字', '大格与小格']
const LEGEND_DESCS: string[] = ['又短又粗，报「时」', '又长又细，报「分」', '数字 n 就是 n×5 分', '1 大格 = 5 小格']
const LEGEND_GLYPHS: string[] = ['时', '分', '12', '格']

@ComponentV2
export struct ClockBoard {
  @Param hour: number = 9
  @Param minute: number = 30
  @Param readonly: boolean = false
  @Event onInteract: () => void = () => {}

  // 单一时间状态：自 12:00 起的分钟数（可为负/超 720，读出时归一）
  @Local totalMin: number = 570
  @Local tab: string = 'dial'
  @Local focus: string = ''
  @Local guided: number = 0
  @Local precision: number = 30

  // 刻度静态几何（aboutToAppear 建一次；非响应式）
  private tickSpecs: TickSpec[] = []
  // 钟面 bbox（onAreaChange 同步，窗口坐标；非响应式避免每帧重渲染）
  private faceRect: ClockFaceRect | null = null
  // 拖拽态：抓的是哪根针 + 分针拖拽的上一帧原始刻度（非响应式）
  private dragHand: string = ''
  private lastRaw: number = 0
  // 只有本板真正播过语音才在销毁时 stop——历史 readonly 卡片滚出视口时不误杀在播语音
  private startedSpeak: boolean = false

  aboutToAppear(): void {
    this.tickSpecs = this.buildTickSpecs()
    const h0: number = ((this.hour % 12) + 12) % 12
    // 防御性吸附到 5 分钟步长（历史会话参数只可能是 0/30，此处兜底任意整数）
    const m: number = Math.round(this.minute / 5) * 5
    this.totalMin = h0 * 60 + m
  }

  aboutToDisappear(): void {
    if (this.startedSpeak) {
      try {
        ServiceRegistry.tts().stop()
      } catch (_e) {
      }
    }
  }

  // ── 时间派生值 ────────────────────────────────────────────────

  private normTotal(): number {
    return ((this.totalMin % 720) + 720) % 720
  }

  private hour0(): number {
    return Math.floor(this.normTotal() / 60)
  }

  private hourPart(): number {
    const h0: number = this.hour0()
    return h0 === 0 ? 12 : h0
  }

  private minutePart(): number {
    return this.normTotal() % 60
  }

  private pad2(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString()
  }

  private digitalText(): string {
    return this.hourPart().toString() + ':' + this.pad2(this.minutePart())
  }

  private spokenText(): string {
    const m: number = this.minutePart()
    if (m === 0) { return this.hourPart().toString() + ' 时整' }
    return this.hourPart().toString() + ' 时 ' + m.toString() + ' 分'
  }

  private handAngles(): ClockAngles {
    return clockAngles(this.hourPart(), this.minutePart())
  }

  private snapTotal(tm: number, p: number): number {
    return Math.round(tm / p) * p
  }

  // ── 静态几何 ──────────────────────────────────────────────────

  private buildTickSpecs(): TickSpec[] {
    const arr: TickSpec[] = []
    for (let i = 0; i < 60; i++) {
      const a: number = i * 6 * Math.PI / 180
      const r1: number = i % 5 === 0 ? 84 : 90
      const r2: number = 96
      const spec: TickSpec = {
        x1: C + r1 * Math.sin(a),
        y1: C - r1 * Math.cos(a),
        x2: C + r2 * Math.sin(a),
        y2: C - r2 * Math.cos(a),
        major: i % 5 === 0
      }
      arr.push(spec)
    }
    return arr
  }

  private hourSeq(): number[] {
    const arr: number[] = []
    for (let h = 1; h <= 12; h++) { arr.push(h) }
    return arr
  }

  private numX(h: number): number {
    const rad: number = (h * 30 - 90) * Math.PI / 180
    return C + NUM_R * Math.cos(rad) - 6
  }

  private numY(h: number): number {
    const rad: number = (h * 30 - 90) * Math.PI / 180
    return C + NUM_R * Math.sin(rad) - 9
  }

  private legendSeq(): number[] {
    const arr: number[] = []
    for (let i = 0; i < LEGEND_IDS.length; i++) { arr.push(i) }
    return arr
  }

  private precisionSeq(): number[] {
    const arr: number[] = []
    arr.push(60)
    arr.push(30)
    arr.push(5)
    return arr
  }

  private precisionLabel(p: number): string {
    if (p === 60) { return '整点' }
    if (p === 30) { return '半点' }
    return '5 分'
  }

  // ── 图层聚焦 / 引导淡化 ───────────────────────────────────────

  private focusActive(): boolean {
    return this.tab === 'learn' && this.focus !== ''
  }

  private ticksLayerOpacity(): number {
    if (this.focusActive()) { return this.focus === 'ticks' ? 1 : 0.26 }
    return 1
  }

  private numsLayerOpacity(): number {
    if (this.focusActive()) { return this.focus === 'numbers' ? 1 : 0.26 }
    return 1
  }

  private hourHandOpacity(): number {
    if (this.focusActive()) { return this.focus === 'hour' ? 1 : 0.26 }
    if (this.tab === 'dial' && this.guided === 2) { return 0.25 }
    return 1
  }

  private minuteHandOpacity(): number {
    if (this.focusActive()) { return this.focus === 'minute' ? 1 : 0.26 }
    if (this.tab === 'dial' && this.guided === 1) { return 0.25 }
    return 1
  }

  // ── 交互 ─────────────────────────────────────────────────────

  private setTab(t: string): void {
    if (this.readonly) { return }
    if (t === this.tab) { return }
    this.tab = t
    this.focus = ''
    this.guided = 0
    this.stopSpeech()
  }

  private toggleFocus(idx: number): void {
    if (this.readonly) { return }
    const id: string = LEGEND_IDS[idx]
    this.focus = this.focus === id ? '' : id
    this.onInteract()
  }

  private selectPrecision(p: number): void {
    if (this.readonly) { return }
    if (p === this.precision) { return }
    this.precision = p
    this.totalMin = this.snapTotal(this.totalMin, p)
    this.guided = 0
    this.stopSpeech()
    this.onInteract()
  }

  private stepHour(delta: number): void {
    if (this.readonly) { return }
    this.totalMin += delta * 60
    this.guided = 0
    this.stopSpeech()
    this.onInteract()
  }

  private stepMinute(delta: number): void {
    if (this.readonly) { return }
    const s: number = this.precision === 60 ? 60 : this.precision
    this.totalMin += delta * s
    this.guided = 0
    this.stopSpeech()
    this.onInteract()
  }

  private advanceGuide(): void {
    if (this.readonly) { return }
    this.guided = this.guided >= 3 ? 1 : this.guided + 1
    this.speakGuideStep(this.guided)
    this.onInteract()
  }

  private resetGuide(): void {
    if (this.readonly) { return }
    this.guided = 0
    this.stopSpeech()
    this.onInteract()
  }

  // ── TTS（一步一步读旁白）─────────────────────────────────────

  private isVoiceEnabled(): boolean {
    return AppStorage.get<number>(AppStorageKeys.VOICE_MODE_ENABLED) === 1
  }

  /** 旁白过时（时间被改动 / 回退 / 切 tab）时直接停播，语义同 NumberBondBoard goPrev */
  private stopSpeech(): void {
    if (!this.startedSpeak) {
      return
    }
    try {
      ServiceRegistry.tts().stop()
    } catch (_e) {
    }
  }

  /** 引导步口播稿：带「第一/二/三步」提示词 + 该步读法（算式经 TTS 规范化转中文读法） */
  private speakTextForStep(step: number): string {
    if (step === 1) {
      return '第一步，先看短针。' + this.hourReadText()
    }
    if (step === 2) {
      return '第二步，再看长针。' + this.minuteReadText()
    }
    if (step === 3) {
      return '第三步，合起来读。现在是 ' + this.spokenText() + '。'
    }
    return ''
  }

  private speakGuideStep(step: number): void {
    if (this.readonly || !this.isVoiceEnabled()) {
      return
    }
    const text: string = this.speakTextForStep(step)
    if (text === '') {
      return
    }
    this.startedSpeak = true
    // 步骤旁白接管所有在播语音，让孩子听到的是刚进入的这一步。
    try {
      ServiceRegistry.tts().stop()
    } catch (_e) {
    }
    ServiceRegistry.tts().speak(normalizeMathSymbolsForTts(text), {
      onStart: () => {},
      onComplete: () => {},
      onError: (_error: string) => {}
    }).catch((_e: Error) => {})
  }

  // ── 拖拽（角度就近判定抓针；分针按步长吸附，时针定时不定点）──

  private updateFaceRect(area: Area): void {
    const rect: ClockFaceRect = {
      x: area.globalPosition.x as number,
      y: area.globalPosition.y as number,
      w: area.width as number,
      h: area.height as number
    }
    this.faceRect = rect
  }

  /** 手指相对钟心的角度（12 点方向 0°，顺时针）；bbox 未就绪返回 -1 */
  private fingerAngle(globalX: number, globalY: number): number {
    if (this.faceRect === null) { return -1 }
    const cx: number = this.faceRect.x + this.faceRect.w / 2
    const cy: number = this.faceRect.y + this.faceRect.h / 2
    const deg: number = Math.atan2(globalX - cx, -(globalY - cy)) * 180 / Math.PI
    return ((deg % 360) + 360) % 360
  }

  private angleGap(a: number, b: number): number {
    const d: number = (((a - b) % 360) + 360) % 360
    return d > 180 ? 360 - d : d
  }

  private handleDragStart(event: GestureEvent): void {
    if (this.readonly || this.faceRect === null) { return }
    const finger: Object | undefined =
      event.fingerList && event.fingerList.length > 0 ? event.fingerList[0] : undefined
    if (finger === undefined) { return }
    const ang: number = this.fingerAngle((finger as FingerInfo).globalX, (finger as FingerInfo).globalY)
    if (ang < 0) { return }
    if (this.precision === 60) {
      this.dragHand = 'hour'
    } else {
      const gapHour: number = this.angleGap(ang, this.handAngles().hourDeg)
      const gapMin: number = this.angleGap(ang, this.handAngles().minuteDeg)
      this.dragHand = gapHour < gapMin ? 'hour' : 'minute'
    }
    this.lastRaw = this.dragHand === 'minute' ? ang / 6 : 0
    this.guided = 0
  }

  private handleDragMove(event: GestureEvent): void {
    if (this.readonly || this.dragHand === '') { return }
    const finger: Object | undefined =
      event.fingerList && event.fingerList.length > 0 ? event.fingerList[0] : undefined
    if (finger === undefined) { return }
    const ang: number = this.fingerAngle((finger as FingerInfo).globalX, (finger as FingerInfo).globalY)
    if (ang < 0) { return }
    if (this.dragHand === 'minute') {
      const raw: number = ang / 6
      let d: number = raw - this.lastRaw
      if (d > 30) { d -= 60 }
      if (d < -30) { d += 60 }
      this.totalMin = this.snapTotal(this.totalMin + d, this.precision)
      this.lastRaw = raw
    } else {
      const h0: number = ((Math.round(ang / 30) % 12) + 12) % 12
      const keep: number = this.precision === 60 ? 0 : this.minutePart()
      this.totalMin = h0 * 60 + keep
    }
  }

  private handleDragEnd(): void {
    if (this.dragHand === '') { return }
    this.dragHand = ''
    this.stopSpeech()
    this.onInteract()
  }

  // ── 引导与图例文案 ────────────────────────────────────────────

  private guideTitle(idx: number): string {
    if (idx === 0) { return '先看短针（时针）' }
    if (idx === 1) { return '再看长针（分针）' }
    return '合起来读'
  }

  private guideActive(idx: number): boolean {
    if (idx === 2) { return this.guided >= 3 }
    return this.guided === idx + 1
  }

  /** 第 1 步：短针定时（整点指 N；非整点在 N 和 N+1 之间 → 已过 N 时） */
  private hourReadText(): string {
    const h: number = this.hourPart()
    const m: number = this.minutePart()
    if (m === 0) { return '短针正好指着 ' + h.toString() + '，说明是 ' + h.toString() + ' 时。' }
    const next: number = h === 12 ? 1 : h + 1
    return '短针在 ' + h.toString() + ' 和 ' + next.toString() + ' 之间，已经走过了 ' + h.toString() + ' 时。'
  }

  /** 第 2 步：长针定分（粒度 5 分钟步长，指到数字 k 就是 k × 5 分） */
  private minuteReadText(): string {
    const m: number = this.minutePart()
    if (m === 0) { return '长针正好指着 12，是整点，0 分。' }
    if (m === 30) { return '长针指着 6：6 × 5 = 30 分，正好是半点。' }
    const k: number = m / 5
    return '长针指着数字 ' + k.toString() + '：' + k.toString() + ' × 5 = ' + m.toString() + ' 分。'
  }

  private learnNote(): string {
    if (this.focus === 'hour') {
      return '短针（时针）负责报「时」。它走得慢，1 小时才走 1 大格。先看它走过了哪个数字。'
    }
    if (this.focus === 'minute') {
      return '长针（分针）负责报「分」。它走得快，1 分钟走 1 小格，走 1 大格就是 5 分钟。'
    }
    if (this.focus === 'numbers') {
      return '钟面上有 12 个数字。分针指到数字 n，就是 n × 5 分。比如指到 6 就是 30 分。'
    }
    if (this.focus === 'ticks') {
      return '每一大格里有 5 个小格，合起来正好是 5 分钟。数一数小格，就能精确到 1 分。'
    }
    return '点一点上面的名称，看看它在钟面上是哪一个。也可以转到「拨一拨」，自己转转指针。'
  }

  // ── UI ───────────────────────────────────────────────────────

  @Builder
  TabChip(id: string, label: string) {
    Text(label)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.tab === id ? KIDS_MATH_INK : KIDS_MUTED)
      .padding({ left: 18, right: 18, top: 8, bottom: 8 })
      .borderRadius(20)
      .backgroundColor(this.tab === id ? withColorAlpha(KIDS_MATH, '26') : Color.Transparent)
      .onClick(() => { this.setTab(id) })
  }

  @Builder
  ClockFace() {
    Stack() {
      Circle().width(FACE_BOX).height(FACE_BOX).fill(withColorAlpha(KIDS_ACCENT, '2E'))
      Circle().width(FACE_D).height(FACE_D).fill(KIDS_SURFACE)
        .stroke(withColorAlpha(KIDS_ACCENT, '66')).strokeWidth(3)
        .position({ x: RING_PAD, y: RING_PAD })

      Stack() {
        ForEach(this.tickSpecs, (t: TickSpec) => {
          Line({ width: FACE_BOX, height: FACE_BOX })
            .startPoint([t.x1, t.y1]).endPoint([t.x2, t.y2])
            .stroke(t.major ? KIDS_SUBTLE : KIDS_BORDER)
            .strokeWidth(t.major ? 3 : 1.6)
            .strokeLineCap(LineCapStyle.Round)
        }, (t: TickSpec, idx: number) => 'tick' + idx.toString())
      }
      .width(FACE_BOX).height(FACE_BOX)
      .opacity(this.ticksLayerOpacity())
      .animation(HAND_ANIM)

      Stack() {
        ForEach(this.hourSeq(), (h: number) => {
          Text(h.toString())
            .fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)
            .position({ x: this.numX(h), y: this.numY(h) })
        }, (h: number) => 'num' + h.toString())
      }
      .width(FACE_BOX).height(FACE_BOX)
      .opacity(this.numsLayerOpacity())
      .animation(HAND_ANIM)

      Rect({ width: 9, height: 50 }).fill(KIDS_FG).borderRadius(4.5)
        .position({ x: C - 4.5, y: C - 50 })
        .rotate({ angle: this.handAngles().hourDeg, centerX: '50%', centerY: '100%' })
        .opacity(this.hourHandOpacity())
        .animation(HAND_ANIM)

      Column() {
        Rect({ width: 7, height: 22 }).fill(KIDS_MATH).borderRadius(3.5)
        Rect({ width: 7, height: 52 }).fill(KIDS_MATH_INK).borderRadius(3.5)
      }
      .position({ x: C - 3.5, y: C - 74 })
      .rotate({ angle: this.handAngles().minuteDeg, centerX: '50%', centerY: '100%' })
      .opacity(this.minuteHandOpacity())
      .animation(HAND_ANIM)

      Circle().width(12).height(12).fill(KIDS_FG).position({ x: C - 6, y: C - 6 })
      Circle().width(4.5).height(4.5).fill(KIDS_SURFACE).position({ x: C - 2.25, y: C - 2.25 })
    }
    .width(FACE_BOX).height(FACE_BOX)
    .onAreaChange((_oldArea: Area, newArea: Area) => { this.updateFaceRect(newArea) })
    .priorityGesture(
      PanGesture({ direction: PanDirection.All, distance: 5 })
        .onActionStart((event: GestureEvent) => { this.handleDragStart(event) })
        .onActionUpdate((event: GestureEvent) => { this.handleDragMove(event) })
        .onActionEnd((_event: GestureEvent) => { this.handleDragEnd() })
    )
  }

  @Builder
  Readout() {
    Column({ space: 3 }) {
      Text(this.digitalText())
        .fontSize(30).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)
      Text(this.spokenText())
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }

  @Builder
  LegendCard(idx: number) {
    Row({ space: 8 }) {
      Stack() {
        Text(LEGEND_GLYPHS[idx])
          .fontSize(13).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
      }
      .width(30).height(30).borderRadius(9)
      .backgroundColor(withColorAlpha(KIDS_MATH, '1A'))

      Column({ space: 2 }) {
        Text(LEGEND_NAMES[idx])
          .fontSize(13).fontWeight(FontWeight.Bold).fontColor(KIDS_FG).maxLines(1)
        Text(LEGEND_DESCS[idx])
          .fontSize(11).fontColor(KIDS_MUTED).maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(12)
    .width('48%')
    .margin({ bottom: 8 })
    .border({
      width: 1.2,
      color: this.focus === LEGEND_IDS[idx] ? KIDS_MATH : KIDS_BORDER
    })
    .backgroundColor(this.focus === LEGEND_IDS[idx] ? withColorAlpha(KIDS_MATH, '26') : KIDS_SURFACE)
    .onClick(() => { this.toggleFocus(idx) })
  }

  @Builder
  LearnPanel() {
    Column({ space: 4 }) {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(this.legendSeq(), (idx: number) => {
          this.LegendCard(idx)
        }, (idx: number) => 'leg' + idx.toString())
      }
      .width('100%')

      Text(this.learnNote())
        .fontSize(12.5).lineHeight(19)
        .fontColor(withColorAlpha(KIDS_MATH_INK, 'D9'))
        .padding(12)
        .borderRadius(12)
        .backgroundColor(withColorAlpha(KIDS_MATH, '13'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  GuideCard(idx: number) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Stack() {
          Text((idx + 1).toString())
            .fontSize(12).fontWeight(FontWeight.Bold)
            .fontColor(this.guideActive(idx) ? Color.White : KIDS_MATH_INK)
        }
        .width(22).height(22).borderRadius(11)
        .backgroundColor(this.guideActive(idx) ? KIDS_MATH : withColorAlpha(KIDS_MATH, '1A'))

        Text(this.guideTitle(idx))
          .fontSize(14).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)

        if (idx === 2) {
          Blank()
        }
      }
      .width('100%')

      if (idx === 2) {
        Text(this.spokenText())
          .fontSize(21).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
          .width('100%').textAlign(TextAlign.Center)
        Text('写作 ' + this.digitalText())
          .fontSize(12).fontColor(KIDS_MUTED)
          .width('100%').textAlign(TextAlign.Center)
      } else if (idx === 0) {
        Text(this.hourReadText())
          .fontSize(12.5).lineHeight(18).fontColor(KIDS_MUTED).width('100%')
      } else {
        Text(this.minuteReadText())
          .fontSize(12.5).lineHeight(18).fontColor(KIDS_MUTED).width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .borderRadius(12)
    .width('100%')
    .border({
      width: 1.2,
      color: this.guideActive(idx) ? KIDS_MATH : KIDS_BORDER
    })
    .backgroundColor(this.guideActive(idx) ? withColorAlpha(KIDS_MATH, '1A') : KIDS_SURFACE)
    .animation(HAND_ANIM)
  }

  @Builder
  DialPanel() {
    Column({ space: 10 }) {
      Row({ space: 4 }) {
        ForEach(this.precisionSeq(), (p: number) => {
          Text(this.precisionLabel(p))
            .fontSize(13).fontWeight(FontWeight.Bold)
            .fontColor(this.precision === p ? KIDS_MATH_INK : KIDS_MUTED)
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .borderRadius(18)
            .backgroundColor(this.precision === p ? KIDS_SURFACE : Color.Transparent)
            .border({ width: 1, color: this.precision === p ? KIDS_MATH : Color.Transparent })
            .onClick(() => { this.selectPrecision(p) })
        }, (p: number) => 'prec' + p.toString())
      }
      .padding(4)
      .borderRadius(22)
      .backgroundColor(withColorAlpha(KIDS_MATH, '10'))
      .border({ width: 1, color: KIDS_BORDER })

      Row({ space: 8 }) {
        Text('时').fontSize(12).fontColor(KIDS_SUBTLE)
        Button('−')
          .width(42).height(42).fontSize(18).fontWeight(FontWeight.Bold)
          .type(ButtonType.Capsule)
          .backgroundColor(withColorAlpha(KIDS_MATH, '26')).fontColor(KIDS_MATH_INK)
          .accessibilityText('时针往回拨一小时')
          .onClick(() => { this.stepHour(-1) })
        Button('+')
          .width(42).height(42).fontSize(18).fontWeight(FontWeight.Bold)
          .type(ButtonType.Capsule)
          .backgroundColor(withColorAlpha(KIDS_MATH, '26')).fontColor(KIDS_MATH_INK)
          .accessibilityText('时针往前拨一小时')
          .onClick(() => { this.stepHour(1) })
        Text('分').fontSize(12).fontColor(KIDS_SUBTLE)
        Button('−')
          .width(42).height(42).fontSize(18).fontWeight(FontWeight.Bold)
          .type(ButtonType.Capsule)
          .backgroundColor(withColorAlpha(KIDS_MATH, '26')).fontColor(KIDS_MATH_INK)
          .accessibilityText('分针往回拨')
          .onClick(() => { this.stepMinute(-1) })
        Button('+')
          .width(42).height(42).fontSize(18).fontWeight(FontWeight.Bold)
          .type(ButtonType.Capsule)
          .backgroundColor(withColorAlpha(KIDS_MATH, '26')).fontColor(KIDS_MATH_INK)
          .accessibilityText('分针往前拨')
          .onClick(() => { this.stepMinute(1) })
      }
      .alignItems(VerticalAlign.Center)

      Column({ space: 8 }) {
        this.GuideCard(0)
        this.GuideCard(1)
        this.GuideCard(2)
      }
      .width('100%')

      Row({ space: 10 }) {
        Button('一步一步读')
          .height(40)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_ON_HERO)
          .backgroundColor(KIDS_ACCENT)
          .borderRadius(14)
          .padding({ left: 16, right: 16 })
          .accessibilityText('播放一步一步读时钟')
          .onClick(() => { this.advanceGuide() })
        Button('从头读')
          .height(40)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
          .backgroundColor(KIDS_SURFACE)
          .borderRadius(14)
          .border({ width: 1, color: KIDS_BORDER })
          .padding({ left: 16, right: 16 })
          .accessibilityText('从头开始读时钟')
          .onClick(() => { this.resetGuide() })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column({ space: 12 }) {
      if (!this.readonly) {
        Row({ space: 6 }) {
          this.TabChip('learn', '认一认')
          this.TabChip('dial', '拨一拨')
        }
      }

      this.ClockFace()
      this.Readout()

      if (!this.readonly) {
        if (this.tab === 'learn') {
          this.LearnPanel()
        } else {
          this.DialPanel()
        }
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
