import {
  numberBondStepTitles, numberBondStepTips, numberBondStepNarrations,
  numberBondScaffold, numberBondSplits, numberBondSplitReady,
  NumberBondScaffoldLine, NumberBondSplit
} from '../../utils/MathTeachNumberBond'
import { curves } from '@kit.ArkUI'
import { AppStorageKeys } from '../../config/AppStorageKeys'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { normalizeMathSymbolsForTts } from '../../utils/TtsTextUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  KIDS_MATH, KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED, KIDS_BORDER,
  KIDS_SURFACE, KIDS_FG, KIDS_ON_HERO, KIDS_ON_GOLD, KIDS_STAR, KIDS_SUBTLE
} from '../kids/KidsBrandTokens'

/**
 * NumberBondBoard - 数的分与合引导课（math_teach · number_bond 模式）
 *
 * 参考 docs/number-bond-lesson.html 的 4 步分与合深度课原型，按工具参数
 * total 泛化：数一数（逐个点球计数）→ 分一分（小球拖进左右两盘，或点球
 * 再点盘两步投放；两边都有才算分好）→ 合一合（两部分合回整体，分合树互看）→
 * 找全部（单屏逐播：大算式 + 大点阵每次只播一种分法，「再分下一种」逐个播放；
 * 「本课完成」可提前结课——分法没点完也接受本次授课）。
 * 底部「分合记录」脚手架随步骤点亮。
 *
 * 完成门：每完成一步 onInteract() 一次（共 4 步），shell 层
 * interactionThreshold 对 number_bond 配 4。回执契约不变。
 *
 * TTS：语音模式开启时（AppStorage VOICE_MODE_ENABLED，与 TenFrameBoard
 * 同一开关），进入每步朗读该步口播稿；回退/离开即 stop。已答历史态不播。
 */

const STEP_NAMES: string[] = ['数一数', '分一分', '合一合', '找全部']
const STEP_TOTAL: number = 4
// 分合树几何（对应原型 bond-svg viewBox 232x146）
const BOND_W: number = 232
const BOND_H: number = 146
// 拖拽参数（CategorizationCard 同款）
const DRAG_START_DISTANCE: number = 5
const DRAGGING_BALL_SCALE: number = 1.25
const HOVERED_PLATE_SCALE: number = 1.04
// SPRING_QUICK: 拖动球的跟手缩放/位移; SPRING_GENTLE: 盘子高亮缩放
const SPRING_QUICK: AnimateParam = { duration: 180, curve: curves.springMotion(0.6, 0.7) }
const SPRING_GENTLE: AnimateParam = { duration: 360, curve: curves.springMotion(0.4, 0.8) }

/** 盘子的窗口空间 bbox（globalPosition + 宽高），供拖拽命中检测使用。 */
interface PlateRect {
  x: number
  y: number
  w: number
  h: number
}

@ComponentV2
export struct NumberBondBoard {
  @Param total: number = 9
  @Param readonly: boolean = false
  @Event onInteract: () => void = () => {}
  // 末步「本课完成」直通提交：shell 收到后走 submit()（其内部有已提交/门槛守卫）
  @Event onFinish: () => void = () => {}

  @Local stepIndex: number = 0
  // 数一数：每个小球的计数结果（0 = 还没数；否则 = 第几个被数到）
  @Local countNums: number[] = []
  @Local counted: number = 0
  // 分一分：每个小球所在区（0 中间堆 / 1 左盘 / 2 右盘）
  @Local zoneOf: number[] = []
  @Local merged: boolean = false
  @Local revealed: number = 0

  // 拖拽态（CategorizationCard 范式）：拖动中的球、实时位移、悬停的盘子
  @Local draggingBallIdx: number = -1
  @Local dragOffsetX: number = 0
  @Local dragOffsetY: number = 0
  @Local hoveredPlate: number = -1
  // 两步投放态：点选的球（armed），再点盘子落下
  @Local selectedBallIdx: number = -1

  // 已计完成的步骤（非响应式守卫：重访已完成步骤不重复上报 onInteract）
  private stepDoneFlags: boolean[] = [false, false, false, false]
  private startedSpeak: boolean = false

  // 各盘子的窗口空间 bbox，由 Plate.onAreaChange 同步；非响应式避免每 tick 重渲染
  private plateRects: Map<number, PlateRect> = new Map()

  aboutToAppear(): void {
    if (this.readonly) {
      // 已答历史态：直接渲染完成态（草稿纸语义，不恢复孩子离开时的中间过程）
      const l: number = Math.floor(this.total / 2)
      const counts: number[] = []
      const zones: number[] = []
      for (let i = 0; i < this.total; i++) {
        counts.push(i + 1)
        zones.push(i < l ? 1 : 2)
      }
      this.countNums = counts
      this.counted = this.total
      this.zoneOf = zones
      this.merged = true
      this.revealed = this.total + 1
      this.stepIndex = STEP_TOTAL - 1
      return
    }
    // 正常路径：初始化 total 颗球——计数全 0、全在中间堆（ForEach 与
    // 三区过滤都以数组长度为准，缺初始化会导致一颗球都渲染不出来）
    const counts: number[] = []
    const zones: number[] = []
    for (let i = 0; i < this.total; i++) {
      counts.push(0)
      zones.push(0)
    }
    this.countNums = counts
    this.zoneOf = zones
    this.speakStep(0)
  }

  aboutToDisappear(): void {
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

  /** 找全部舞台的单元素源（值 = 已播数）：键随 revealed 变化，驱动整段重建 + 过渡动画。 */
  private revealStage(): number[] {
    const a: number[] = []
    a.push(this.revealed)
    return a
  }

  /** 当前播到的分法（revealed=0 供占位取首行；越界取界）。 */
  private currentSplit(): NumberBondSplit {
    const arr: NumberBondSplit[] = numberBondSplits(this.total)
    let idx: number = this.revealed - 1
    if (idx < 0) {
      idx = 0
    }
    if (idx > arr.length - 1) {
      idx = arr.length - 1
    }
    return arr[idx]
  }

  /** 找全部大点阵直径：一行最多 total 颗，按 total 分档保证不换行。 */
  private bigDotSize(): number {
    if (this.total >= 9) {
      return 20
    }
    if (this.total >= 7) {
      return 24
    }
    return 30
  }

  private stepTitle(): string {
    const titles: string[] = numberBondStepTitles(this.total)
    return titles[this.stepIndex]
  }

  private stepTip(): string {
    const tips: string[] = numberBondStepTips(this.total)
    return tips[this.stepIndex]
  }

  private countZone(zone: number): number {
    let n: number = 0
    for (let i = 0; i < this.zoneOf.length; i++) {
      if (this.zoneOf[i] === zone) {
        n += 1
      }
    }
    return n
  }

  private leftCount(): number {
    return this.countZone(1)
  }

  private rightCount(): number {
    return this.countZone(2)
  }

  private pileCount(): number {
    return this.countZone(0)
  }

  private splitDone(): boolean {
    return numberBondSplitReady(this.pileCount(), this.leftCount(), this.rightCount())
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
      return this.counted >= this.total
    }
    if (this.stepIndex === 1) {
      return this.splitDone()
    }
    if (this.stepIndex === 2) {
      return this.merged
    }
    return this.revealed >= this.total + 1
  }

  // ── 导航 ─────────────────────────────────────────────────────────

  private goNext(): void {
    if (this.readonly) {
      return
    }
    if (this.stepIndex >= STEP_TOTAL - 1) {
      // 末步「本课完成」：分法没点完也接受本次授课（找全部按已播的计一次），
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

  private tapCountDot(idx: number): void {
    if (this.readonly || this.stepIndex !== 0 || this.countNums[idx] > 0) {
      return
    }
    const next: number[] = this.countNums.slice()
    this.counted += 1
    next[idx] = this.counted
    this.countNums = next
    if (this.counted >= this.total) {
      this.markStepDone(0)
    }
  }

  // ── 分一分：拖拽直投 + 点球点盘两步投放 ─────────────────────────

  private placeBall(idx: number, zone: number): void {
    if (this.readonly || this.zoneOf[idx] === zone) {
      return
    }
    const next: number[] = this.zoneOf.slice()
    next[idx] = zone
    this.zoneOf = next
    if (this.splitDone()) {
      this.markStepDone(1)
    }
  }

  /** 盘内球点回中间堆（分好前可反悔；CategorizationCard 的 unplace 语义）。 */
  private unplaceBall(idx: number): void {
    if (this.readonly || this.stepIndex !== 1 || this.splitDone() || this.zoneOf[idx] === 0) {
      return
    }
    const next: number[] = this.zoneOf.slice()
    next[idx] = 0
    this.zoneOf = next
  }

  /** 点中间堆的球 → armed（盘子亮起），再点盘子落下；再点一次取消。 */
  private tapPileBall(idx: number): void {
    if (this.readonly || this.stepIndex !== 1 || this.splitDone() || this.zoneOf[idx] !== 0) {
      return
    }
    this.selectedBallIdx = this.selectedBallIdx === idx ? -1 : idx
  }

  private tapPlate(zone: number): void {
    if (this.readonly || this.stepIndex !== 1 || this.splitDone() || this.selectedBallIdx < 0) {
      return
    }
    const idx: number = this.selectedBallIdx
    this.selectedBallIdx = -1
    this.placeBall(idx, zone)
  }

  private handleDragStart(idx: number): void {
    if (this.readonly || this.stepIndex !== 1 || this.splitDone() || this.zoneOf[idx] !== 0) {
      return
    }
    this.draggingBallIdx = idx
    this.dragOffsetX = 0
    this.dragOffsetY = 0
    this.selectedBallIdx = -1
  }

  private handleDragUpdate(offsetX: number, offsetY: number, globalX: number, globalY: number): void {
    if (this.draggingBallIdx < 0) {
      return
    }
    this.dragOffsetX = offsetX
    this.dragOffsetY = offsetY
    this.hoveredPlate = this.hitTestPlate(globalX, globalY)
  }

  private handleDragEnd(idx: number): void {
    if (this.draggingBallIdx !== idx) {
      return
    }
    const target: number = this.hoveredPlate
    this.draggingBallIdx = -1
    this.dragOffsetX = 0
    this.dragOffsetY = 0
    this.hoveredPlate = -1
    if (target === 1 || target === 2) {
      this.placeBall(idx, target)
    }
  }

  // 同步盘子的窗口空间 bbox. 由 Plate.onAreaChange 调用, 非响应式。
  private updatePlateRect(zone: number, area: Area): void {
    // Area.globalPosition 与 FingerInfo.globalX/Y 同为窗口坐标空间（CategorizationCard 同款转换）
    const rect: PlateRect = {
      x: area.globalPosition.x as number,
      y: area.globalPosition.y as number,
      w: area.width as number,
      h: area.height as number
    }
    this.plateRects.set(zone, rect)
  }

  // 命中检测: 给定窗口坐标, 返回包含该点的盘子 zone (1/2), 找不到返回 -1
  private hitTestPlate(globalX: number, globalY: number): number {
    const it = this.plateRects.entries()
    let entry = it.next()
    while (!entry.done) {
      const idx = entry.value[0] as number
      const rect = entry.value[1] as PlateRect
      if (globalX >= rect.x && globalX <= rect.x + rect.w
        && globalY >= rect.y && globalY <= rect.y + rect.h) {
        return idx
      }
      entry = it.next()
    }
    return -1
  }

  /** 盘子是否应亮起（拖拽悬停，或 armed 状态下两盘都是可投放目标）。 */
  private plateHot(zone: number): boolean {
    if (this.readonly || this.stepIndex !== 1 || this.splitDone()) {
      return false
    }
    return this.hoveredPlate === zone || this.selectedBallIdx >= 0
  }

  private tapMerge(): void {
    if (this.readonly || this.merged) {
      return
    }
    this.merged = true
    this.markStepDone(2)
  }

  private tapRevealNext(): void {
    if (this.readonly || this.revealed >= this.total + 1) {
      return
    }
    this.revealed += 1
    if (this.revealed >= this.total + 1) {
      this.markStepDone(3)
    }
  }

  private scaffoldLit(idx: number): boolean {
    if (idx === 0) {
      return this.counted >= this.total
    }
    if (idx === 1) {
      return this.splitDone()
    }
    if (idx === 2) {
      return this.merged
    }
    return this.revealed >= this.total + 1
  }

  // ── 通用小件 ─────────────────────────────────────────────────────

  /** 待数小球：淡蓝实心（已数后叠白色序号）。 */
  @Builder
  CountDot(idx: number) {
    Stack() {
      Circle()
        .width(30).height(30)
        .fill(this.countNums[idx] > 0 ? KIDS_MATH_INK : withColorAlpha(KIDS_MATH, '26'))
      if (this.countNums[idx] > 0) {
        Text(`${this.countNums[idx]}`)
          .fontSize(13).fontWeight(FontWeight.Bold).fontColor(Color.White)
      }
    }
    .width(44).height(44)
    .margin(4)
    .onClick(() => {
      this.tapCountDot(idx)
    })
  }

  /** 分豆小球：中间堆/左盘蓝色、右盘橙色（颜色随区变化）。 */
  @Builder
  BallDot(zone: number) {
    Circle()
      .width(zone === 2 ? 24 : 28).height(zone === 2 ? 24 : 28)
      .fill(zone === 2 ? KIDS_ACCENT : KIDS_MATH)
  }

  /** 中间堆的球：拖拽直投盘子，或点选（armed 虚线描边）后点盘子落下。 */
  @Builder
  PileBallItem(idx: number) {
    Stack() {
      this.BallDot(0)
    }
    .width(40).height(40)
    .margin(2)
    .border({
      width: this.selectedBallIdx === idx ? 1.5 : 0,
      style: BorderStyle.Dashed,
      color: KIDS_MATH,
      radius: 20
    })
    .scale(this.draggingBallIdx === idx
      ? { x: DRAGGING_BALL_SCALE, y: DRAGGING_BALL_SCALE }
      : { x: 1, y: 1 })
    .shadow(this.draggingBallIdx === idx
      ? { radius: 12, color: '#40000000', offsetY: 4 }
      : { radius: 0, color: '#00000000', offsetY: 0 })
    .translate(this.draggingBallIdx === idx
      ? { x: this.dragOffsetX, y: this.dragOffsetY }
      : { x: 0, y: 0 })
    .animation(SPRING_QUICK)
    .onClick(() => {
      this.tapPileBall(idx)
    })
    .priorityGesture(
      PanGesture({ direction: PanDirection.All, distance: DRAG_START_DISTANCE })
        .onActionStart((_event: GestureEvent) => {
          this.handleDragStart(idx)
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.draggingBallIdx !== idx) {
            return
          }
          const finger = event.fingerList && event.fingerList.length > 0 ? event.fingerList[0] : undefined
          if (finger === undefined) {
            return
          }
          // FingerInfo.globalX/globalY = 窗口坐标, 与 Area.globalPosition 同坐标空间
          this.handleDragUpdate(event.offsetX, event.offsetY,
            (finger as FingerInfo).globalX, (finger as FingerInfo).globalY)
        })
        .onActionEnd((_event: GestureEvent) => {
          if (this.draggingBallIdx !== idx) {
            return
          }
          this.handleDragEnd(idx)
        })
    )
  }

  /** 盘内的球：分好前点一下取回中间堆。 */
  @Builder
  PlateBallItem(idx: number) {
    Stack() {
      this.BallDot(this.zoneOf[idx])
    }
    .width(40).height(40)
    .margin(2)
    .onClick(() => {
      this.unplaceBall(idx)
    })
  }

  /** 分合树：整体在顶，两部分在下（merged 时加向上小箭头示「合」）。 */
  @Builder
  BondTree(total: number, left: number, right: number) {
    Stack() {
      Line({ width: BOND_W, height: BOND_H })
        .startPoint([100, 56]).endPoint([66, 84])
        .stroke(KIDS_BORDER).strokeWidth(2.4).strokeLineCap(LineCapStyle.Round)
      Line({ width: BOND_W, height: BOND_H })
        .startPoint([132, 56]).endPoint([166, 84])
        .stroke(KIDS_BORDER).strokeWidth(2.4).strokeLineCap(LineCapStyle.Round)
      if (this.merged && this.stepIndex === 2) {
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

  /** 双盘：盘子容器 + 盘内小球 + 计数；拖拽悬停/armed 时亮起，onAreaChange 同步 bbox 供命中检测。 */
  @Builder
  Plate(zone: number, caption: string) {
    Column({ space: 6 }) {
      Text(caption).fontSize(12).fontColor(KIDS_MUTED)
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(this.zoneOf, (z: number, idx: number) => {
          if (z === zone) {
            this.PlateBallItem(idx)
          }
        }, (z: number, idx: number) => 'p' + zone.toString() + '_' + idx.toString() + '_' + z.toString())
      }
      .width('100%')
      .constraintSize({ minHeight: 52 })

      Text(`${this.countZone(zone)} 个`)
        .fontSize(16).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)
    }
    .layoutWeight(1)
    .padding(12)
    .borderRadius(14)
    .border({
      width: 1.5,
      style: this.splitDone() || this.plateHot(zone) ? BorderStyle.Solid : BorderStyle.Dashed,
      color: this.splitDone() ? KIDS_MATH
        : (this.plateHot(zone) ? (zone === 2 ? KIDS_ACCENT : KIDS_MATH) : KIDS_BORDER)
    })
    .backgroundColor(this.plateHot(zone)
      ? (zone === 2 ? withColorAlpha(KIDS_ACCENT, '1A') : withColorAlpha(KIDS_MATH, '14'))
      : (zone === 2 ? withColorAlpha(KIDS_ACCENT, '0A') : KIDS_SURFACE))
    .scale(this.plateHot(zone)
      ? { x: HOVERED_PLATE_SCALE, y: HOVERED_PLATE_SCALE }
      : { x: 1, y: 1 })
    .animation(SPRING_GENTLE)
    .onClick(() => {
      this.tapPlate(zone)
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updatePlateRect(zone, newArea)
    })
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

  // ── 4 步主体 ─────────────────────────────────────────────────────

  @Builder
  BodyCount() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
      ForEach(this.seq(this.total), (i: number) => {
        this.CountDot(i)
      }, (i: number) => 'cd' + i.toString() + '_' + this.countNums[i].toString())
    }
    .width('100%')

    if (this.counted >= this.total) {
      this.EqText(`一共就是 ${this.total} 个`, true)
      Text(`一个一个数，最后数到的数字就是一共有几个。整体就是 ${this.total}。`)
        .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
    } else {
      this.EqText(`已经数了 ${this.counted} 个`, false)
      Text('点一点每个小球，边点边数：1、2、3……')
        .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
    }
  }

  @Builder
  BodySplit() {
    if (this.splitDone()) {
      Row({ space: 12 }) {
        this.Plate(1, '左边盘子')
        this.Plate(2, '右边盘子')
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      this.BondTree(this.total, this.leftCount(), this.rightCount())
      this.EqText(`${this.total} 分成 ${this.leftCount()} 和 ${this.rightCount()}`, false)
      Text('分，就是把整体拆成两部分。上面是整体，下面两部分合起来还是它。')
        .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
    } else {
      Column({ space: 6 }) {
        Text('还没分的小球 · 拖进盘子，或先点球再点盘子')
          .fontSize(12).fontColor(KIDS_MUTED)
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(this.zoneOf, (z: number, idx: number) => {
            if (z === 0) {
              this.PileBallItem(idx)
            }
          }, (z: number, idx: number) => 'pile' + idx.toString() + '_' + z.toString())
        }
        .width('100%')
      }
      .width('100%')
      .padding(10)
      .borderRadius(14)
      .border({ width: 1.5, style: BorderStyle.Dashed, color: KIDS_BORDER })
      .backgroundColor(KIDS_SURFACE)

      Row({ space: 12 }) {
        this.Plate(1, '左边盘子')
        this.Plate(2, '右边盘子')
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (this.selectedBallIdx >= 0) {
        Text('把它放进哪个盘子？点一下盘子。')
          .fontSize(12.5).fontColor(KIDS_MATH_INK).textAlign(TextAlign.Center)
      } else if (this.pileCount() > 0) {
        Text(`还剩 ${this.pileCount()} 个没分，把它们拖进两个盘子里。`)
          .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
      } else {
        Text('还有一边是空的。两边都要有小球才算分好。')
          .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
      }
    }
  }

  @Builder
  BodyCompose() {
    Row({ space: 12 }) {
      this.Plate(1, `左 ${this.leftCount()} 个`)
      this.Plate(2, `右 ${this.rightCount()} 个`)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)

    if (this.merged) {
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(this.seq(this.total), (i: number) => {
          Stack() {
            this.BallDot(i < this.leftCount() ? 1 : 2)
          }
          .width(30).height(30).margin(3)
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.2, y: 0.2 }))
            .animation({ duration: 350, curve: Curve.EaseOut }))
        }, (i: number) => 'mg' + i.toString())
      }
      .width('100%')

      this.EqText(`${this.leftCount()} + ${this.rightCount()} = ${this.total}`, true)
      this.BondTree(this.total, this.leftCount(), this.rightCount())
      this.WhyBox('合起来，还是原来的数',
        `分出来的两部分再合起来，就回到整体 ${this.total}。同一张分合树，从上往下是「分」，从下往上是「合」——分完可以用「合」来检查。`)
    } else {
      this.BondTree(this.total, this.leftCount(), this.rightCount())
      Button('把两部分合起来')
        .width(200).height(44)
        .backgroundColor(KIDS_MATH_INK).fontSize(14)
        .accessibilityText('把两部分合起来')
        .onClick(() => {
          this.tapMerge()
        })
      Text(`${this.leftCount()} 和 ${this.rightCount()} 分开放在两个盘子里。把它们合到一起，一共有几个？`)
        .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
    }
  }

  /** 找全部：单屏舞台——大算式 + 大点阵每次只播一种分法，「再分下一种」逐个播放。 */
  @Builder
  BodyAll() {
    Stack() {
      ForEach(this.revealStage(), (rev: number) => {
        Column({ space: 12 }) {
          if (rev > 0) {
            Text(`${this.total} = ${this.currentSplit().left} + ${this.currentSplit().right}`)
              .fontSize(26).fontWeight(FontWeight.Bold).fontColor(KIDS_FG)
          } else {
            Text(`${this.total} = ? + ?`)
              .fontSize(26).fontWeight(FontWeight.Bold).fontColor(KIDS_MUTED)
          }

          Row() {
            ForEach(this.seq(this.total), (i: number) => {
              Circle()
                .width(this.bigDotSize()).height(this.bigDotSize()).margin(3)
                .fill(rev > 0 ? (i < this.currentSplit().left ? KIDS_MATH : KIDS_ACCENT)
                  : withColorAlpha(KIDS_FG, '06'))
                .stroke(rev > 0 ? withColorAlpha(KIDS_FG, '00') : KIDS_BORDER)
                .strokeWidth(rev > 0 ? 0 : 1.5)
                .strokeDashArray([3, 3])
            }, (i: number) => 'bd' + i.toString())
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)

          Text(rev > 0 ? `第 ${rev} 种 · 共 ${this.total + 1} 种` : `一共 ${this.total + 1} 种，一个一个找`)
            .fontSize(12.5).fontColor(KIDS_MUTED)
        }
        .width('100%')
        .padding({ top: 14, bottom: 14, left: 8, right: 8 })
        .borderRadius(14)
        .border({
          width: 1.5,
          style: rev > 0 ? BorderStyle.Solid : BorderStyle.Dashed,
          color: rev > 0 ? withColorAlpha(KIDS_MATH, '38') : KIDS_BORDER
        })
        .backgroundColor(rev > 0 ? KIDS_SURFACE : withColorAlpha(KIDS_FG, '04'))
        .transition(TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.7, y: 0.7 }))
          .animation({ duration: 300, curve: Curve.EaseOut }))
      }, (rev: number) => 'stage' + rev.toString())
    }
    .width('100%')

    if (this.revealed >= this.total + 1) {
      Text(`一共 ${this.total + 1} 种分法。左边每次多 1，右边就每次少 1——有序地想，不重不漏。`)
        .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
    } else {
      Button(this.revealed === 0 ? '开始有序地分' : '再分下一种')
        .width(190).height(46)
        .backgroundColor(KIDS_MATH_INK).fontSize(15)
        .accessibilityText('播放下一种分法')
        .onClick(() => {
          this.tapRevealNext()
        })
      if (this.revealed === 0) {
        Text(`从「左边 0 个」开始，一边多 1、一边少 1，把 ${this.total} 的分法全部找出来。`)
          .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
      } else {
        Text('看仔细：左边每次多 1，右边就每次少 1。')
          .fontSize(12.5).fontColor(KIDS_MUTED).textAlign(TextAlign.Center)
      }
    }
  }

  @Builder
  StepBody() {
    if (this.stepIndex === 0) {
      this.BodyCount()
    } else if (this.stepIndex === 1) {
      this.BodySplit()
    } else if (this.stepIndex === 2) {
      this.BodyCompose()
    } else {
      this.BodyAll()
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
      ForEach(numberBondScaffold(this.total, this.leftCount(), this.rightCount()),
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
