/**
 * MatchingPairsCard - 连一连配对互动卡片 (v2 连线版)
 *
 * 解析 toolCall.arguments 中的配对参数, 以游戏化方式展示:
 * - 双列布局: 左列原序, 右列种子化洗牌 (shuffleRightColumn)
 * - 列间"连线通道" (lane): 配对成功画一条彩色贝塞尔"电线" + 两端圆点,
 *   选中左项时显示虚线短线, 配错时显示红色虚线弧线 (600ms 淡出)。
 *   每对配对按完成顺序分配 WIRE_COLORS 中的一种颜色, 连线/圆点/芯片边框/
 *   进度点/答案列表圆点共用同一颜色, 便于孩子追踪。
 * - 纯点击交互 (不做拖拽, 避免与外层 List 滚动手势冲突):
 *   点左高亮 → 点右: 对 → 双双锁定成功态 (彩色 + ✓ 徽标, 禁用);
 *   错 → mistakes+1 + 红色闪烁 + 红色虚线弧线; 选中态保留, 可直接换右边再试。
 * - 全部配对成功 → onAnswer(completed: true)
 * - 放弃路径镜像 CategorizationCard → onAnswer(completed: false)
 *
 * 预校验由 ToolExecutionService.handleMatchingPairs 在 pending 前完成;
 * aboutToAppear 仍做防御性重解析 (双保险, 历史消息渲染不经 handler)。
 *
 * 参考 NumberPuzzleCard (Premium Tactile) / CategorizationCard 模式:
 * @ComponentV2 + @Event onAnswer 回调。
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import {
  MatchingPair,
  NormalizedMatchingPairsData,
  shuffleRightColumn,
  validateAndNormalizeMatchingPairs
} from '../utils/MatchingPairsGame'

interface MatchingPairsAnswerPayload {
  completed: boolean
  correct: number
  total: number
  mistakes: number
  difficulty: number
  skill_key: string
  theme: string
}

const SUCCESS_GREEN: string = '#22C55E'
const WRONG_RED: string = '#FF6B6B'
const GIVEUP_ORANGE: string = '#FF9F43'

// 连线通道几何: 芯片固定高度 + 固定间距, 行中心 y = index * CHIP_STEP + CHIP_HEIGHT / 2
const CHIP_HEIGHT: number = 48
const CHIP_GAP: number = 8
const CHIP_STEP: number = CHIP_HEIGHT + CHIP_GAP
const LANE_WIDTH: number = 34
// 每对配对按完成顺序取色 (5 色循环), 连线/圆点/芯片/答案列表共用
const WIRE_COLORS: string[] = ['#F59E0B', '#14B8A6', '#8B5CF6', '#EC4899', '#3B82F6']

function hashStringToSeed(value: string): number {
  let hash = 0
  for (let i = 0; i < value.length; i++) {
    hash = (hash * 31 + value.charCodeAt(i)) >>> 0
  }
  return hash === 0 ? 1 : hash
}

@ComponentV2
export struct MatchingPairsCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local quizOk: boolean = false
  @Local quizError: string = ''
  @Local theme: string = ''
  @Local instruction: string = ''
  @Local leftLabel: string = ''
  @Local rightLabel: string = ''
  @Local difficulty: number = 1
  @Local skillKey: string = 'observation'
  @Local leftItems: MatchingPair[] = []
  @Local rightItems: MatchingPair[] = []      // 洗牌后的右列
  @Local originalPairs: MatchingPair[] = []   // 原序 (已答态展示连线用)
  @Local matchedOrder: MatchingPair[] = []    // 按完成顺序记录已配对的 pair (单一数据源)
  @Local selectedLeft: string = ''
  @Local mistakes: number = 0
  @Local wrongRight: string = ''              // 当前红色闪烁的右项
  @Local isCompleted: boolean = false
  @Local gaveUp: boolean = false
  @Local pressedKey: string = ''              // 按压反馈 (触摸中的芯片)
  // 已答态
  @Local prevCompleted: boolean = false
  @Local prevCorrect: number = 0
  @Local prevTotal: number = 0
  @Local prevMistakes: number = 0

  private wrongTimerId: number = -1

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  aboutToAppear(): void {
    const parsed: NormalizedMatchingPairsData = validateAndNormalizeMatchingPairs(this.toolCall.arguments)
    if (!parsed.ok) {
      // 防御性兜底: handler 已预校验, 这里只兜历史消息/异常路径
      this.quizOk = false
      this.quizError = parsed.error
      return
    }
    this.quizOk = true
    this.theme = parsed.theme
    this.instruction = parsed.instruction
    this.leftLabel = parsed.leftLabel
    this.rightLabel = parsed.rightLabel
    this.difficulty = parsed.difficulty
    this.skillKey = parsed.skillKey
    this.leftItems = parsed.pairs
    this.originalPairs = parsed.pairs
    this.rightItems = shuffleRightColumn(parsed.pairs, hashStringToSeed(this.toolCall.id))

    if (this.isAnswered && this.answeredPayload !== '') {
      try {
        const prev = JSON.parse(this.answeredPayload) as MatchingPairsAnswerPayload
        this.prevCompleted = prev.completed === true
        this.prevCorrect = prev.correct ?? 0
        this.prevTotal = prev.total ?? parsed.pairs.length
        this.prevMistakes = prev.mistakes ?? 0
        this.isCompleted = true
        // 已答态: 全部标记为已配对 (原序), 连线按原序配色
        this.matchedOrder = parsed.pairs
      } catch (e) {
        console.warn('MatchingPairsCard', `failed to parse answeredPayload: ${(e as Error).message ?? String(e)}`)
      }
    }
  }

  aboutToDisappear(): void {
    if (this.wrongTimerId >= 0) {
      clearTimeout(this.wrongTimerId)
      this.wrongTimerId = -1
    }
  }

  private getInstructionText(): string {
    if (this.instruction !== '') {
      return this.instruction
    }
    return '把左边和右边配成一对吧！'
  }

  private getSubtitle(): string {
    if (this.theme !== '') {
      return `${this.theme} · ${this.originalPairs.length} 对`
    }
    return `${this.originalPairs.length} 对`
  }

  private isLeftMatched(left: string): boolean {
    for (let i = 0; i < this.matchedOrder.length; i++) {
      if (this.matchedOrder[i].left === left) {
        return true
      }
    }
    return false
  }

  private isRightMatched(right: string): boolean {
    for (let i = 0; i < this.matchedOrder.length; i++) {
      if (this.matchedOrder[i].right === right) {
        return true
      }
    }
    return false
  }

  private findPairOfLeft(left: string): MatchingPair | null {
    for (let i = 0; i < this.originalPairs.length; i++) {
      if (this.originalPairs[i].left === left) {
        return this.originalPairs[i]
      }
    }
    return null
  }

  private wireColorForPair(pair: MatchingPair): string {
    const index = this.matchedOrder.indexOf(pair)
    if (index < 0) {
      return SUCCESS_GREEN
    }
    return WIRE_COLORS[index % WIRE_COLORS.length]
  }

  private wireColorForLeft(left: string): string {
    const pair = this.findPairOfLeft(left)
    return pair !== null ? this.wireColorForPair(pair) : SUCCESS_GREEN
  }

  // ---- 连线几何 (纯方法, 芯片行高固定故可确定性计算) ----
  // 注意: Path.commands 的坐标单位是 px (官方文档明确), 而布局用 vp,
  // 所以下命令前必须把 vp 坐标换算成 px, 否则连线被压成 1/density 大小。

  private vpToPx(value: number): number {
    return Math.round(this.getUIContext().vp2px(value) * 100) / 100
  }

  private boardHeight(): number {
    const n = this.leftItems.length
    return n > 0 ? n * CHIP_STEP - CHIP_GAP : 0
  }

  private rowCenterY(index: number): number {
    return index * CHIP_STEP + CHIP_HEIGHT / 2
  }

  private indexOfLeft(left: string): number {
    for (let i = 0; i < this.leftItems.length; i++) {
      if (this.leftItems[i].left === left) {
        return i
      }
    }
    return -1
  }

  private indexOfRight(right: string): number {
    for (let i = 0; i < this.rightItems.length; i++) {
      if (this.rightItems[i].right === right) {
        return i
      }
    }
    return -1
  }

  private wireCommandsFor(y1: number, y2: number): string {
    // 三次贝塞尔: 两端水平切线 → 平滑"电线" (坐标换算为 px, 见 vpToPx 注释)
    const x1 = this.vpToPx(4)
    const x2 = this.vpToPx(LANE_WIDTH - 4)
    const mid = this.vpToPx(LANE_WIDTH / 2)
    const py1 = this.vpToPx(y1)
    const py2 = this.vpToPx(y2)
    return `M ${x1} ${py1} C ${mid} ${py1}, ${mid} ${py2}, ${x2} ${py2}`
  }

  private pairWireCommands(pair: MatchingPair): string {
    const li = this.indexOfLeft(pair.left)
    const ri = this.indexOfRight(pair.right)
    if (li < 0 || ri < 0) {
      return ''
    }
    return this.wireCommandsFor(this.rowCenterY(li), this.rowCenterY(ri))
  }

  private stubCommands(): string {
    const li = this.indexOfLeft(this.selectedLeft)
    if (li < 0) {
      return ''
    }
    const y = this.vpToPx(this.rowCenterY(li))
    return `M ${this.vpToPx(4)} ${y} L ${this.vpToPx(LANE_WIDTH / 2)} ${y}`
  }

  private wrongWireCommands(): string {
    const li = this.indexOfLeft(this.selectedLeft)
    const ri = this.indexOfRight(this.wrongRight)
    if (li < 0 || ri < 0) {
      return ''
    }
    return this.wireCommandsFor(this.rowCenterY(li), this.rowCenterY(ri))
  }

  // ---- 交互 ----

  private handleChipTouch(event: TouchEvent, key: string, locked: boolean): void {
    if (locked) {
      return
    }
    if (event.type === TouchType.Down) {
      this.pressedKey = key
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.pressedKey === key) {
        this.pressedKey = ''
      }
    }
  }

  private handleLeftTap(left: string): void {
    if (this.isCompleted || this.isAnswered || this.isLeftMatched(left)) {
      return
    }
    this.wrongRight = ''
    this.selectedLeft = this.selectedLeft === left ? '' : left
  }

  private handleRightTap(right: string): void {
    if (this.isCompleted || this.isAnswered || this.selectedLeft === '' || this.isRightMatched(right)) {
      return
    }
    const selectedPair = this.findPairOfLeft(this.selectedLeft)
    if (selectedPair !== null && right === selectedPair.right) {
      // 配对成功: 记录顺序 + 锁定
      const next = this.matchedOrder.slice(0)
      next.push(selectedPair)
      this.matchedOrder = next
      this.wrongRight = ''
      this.selectedLeft = ''
      this.checkCompletion()
    } else {
      // 配错: mistakes+1 + 红色闪烁 + 红色虚线弧线; 选中态保留, 可直接换右边再试
      this.mistakes += 1
      this.wrongRight = right
      if (this.wrongTimerId >= 0) {
        clearTimeout(this.wrongTimerId)
      }
      this.wrongTimerId = setTimeout(() => {
        this.wrongRight = ''
        this.wrongTimerId = -1
      }, 650)
    }
  }

  private checkCompletion(): void {
    if (this.matchedOrder.length < this.originalPairs.length) {
      return
    }
    this.isCompleted = true
    const payload: MatchingPairsAnswerPayload = {
      completed: true,
      correct: this.originalPairs.length,
      total: this.originalPairs.length,
      mistakes: this.mistakes,
      difficulty: this.difficulty,
      skill_key: this.skillKey,
      theme: this.theme
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private handleGiveUp(): void {
    if (this.isCompleted || this.isAnswered) {
      return
    }
    this.isCompleted = true
    this.gaveUp = true
    const payload: MatchingPairsAnswerPayload = {
      completed: false,
      correct: this.matchedOrder.length,
      total: this.originalPairs.length,
      mistakes: this.mistakes,
      difficulty: this.difficulty,
      skill_key: this.skillKey,
      theme: this.theme
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private getLeftDisplay(pair: MatchingPair): string {
    return pair.leftEmoji !== '' ? `${pair.leftEmoji} ${pair.left}` : pair.left
  }

  private getRightDisplay(pair: MatchingPair): string {
    return pair.rightEmoji !== '' ? `${pair.rightEmoji} ${pair.right}` : pair.right
  }

  private isFinished(): boolean {
    return this.isCompleted || this.isAnswered
  }

  private hasWon(): boolean {
    return this.isAnswered ? this.prevCompleted : this.isCompleted && !this.gaveUp
  }

  private getStatusLabel(): string {
    return this.hasWon() ? '已完成' : '已放弃'
  }

  private getStatusColor(): string {
    return this.hasWon() ? SUCCESS_GREEN : GIVEUP_ORANGE
  }

  private getBannerEmoji(): string {
    return this.hasWon() ? '🎉' : '💪'
  }

  private getBannerTitle(): string {
    if (this.hasWon()) {
      const misses = this.isAnswered ? this.prevMistakes : this.mistakes
      return misses === 0 ? '一次全对！观察力超棒！' : '全部配对成功！'
    }
    return '没关系，下次再试试～'
  }

  private getBannerSub(): string {
    const correct = this.isAnswered ? this.prevCorrect : this.matchedOrder.length
    const total = this.isAnswered ? this.prevTotal : this.originalPairs.length
    const misses = this.isAnswered ? this.prevMistakes : this.mistakes
    return `配对 ${correct}/${total} · 失误 ${misses} 次`
  }

  build() {
    Column({ space: 10 }) {
      this.HeaderRow()

      if (!this.quizOk) {
        // 坏题兜底 (handler 已预校验拦截, 极少走到)
        Text(this.quizError !== '' ? this.quizError : '题目参数有误')
          .fontSize(13)
          .fontColor($r('app.color.status_error'))
          .width('100%')
          .padding(8)
      } else {
        // 玩法说明
        Text(this.getInstructionText())
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .width('100%')

        // 双列配对区 (含连线通道)
        this.BoardArea()

        if (!this.isFinished()) {
          this.ProgressRow()
        }

        // 放弃入口
        if (!this.isFinished()) {
          Row() {
            Text('不玩了')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            this.handleGiveUp()
          })
        }

        // 结果反馈
        if (this.isFinished()) {
          this.ResultFeedback()
        }
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.themeAiBubble)
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  HeaderRow() {
    Row({ space: 8 }) {
      Stack() {
        Text('🔗')
          .fontSize(14)
      }
      .width(28)
      .height(28)
      .borderRadius(14)
      .backgroundColor(withColorAlpha(this.themePrimary, '18'))

      Column({ space: 1 }) {
        Text('连一连')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.getSubtitle())
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.isFinished()) {
        Text(this.getStatusLabel())
          .fontSize(10)
          .fontColor(this.getStatusColor())
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(9)
          .border({ width: 1, color: withColorAlpha(this.getStatusColor(), '59') })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  BoardArea() {
    Column({ space: 6 }) {
      // 列标签 (置于棋盘上方, 保证连线几何确定性)
      if (this.leftLabel !== '' || this.rightLabel !== '') {
        Row() {
          Text(this.leftLabel)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .layoutWeight(1)
          Text(this.rightLabel)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }

      Row() {
        // 左列 (原序)
        Column({ space: CHIP_GAP }) {
          ForEach(this.leftItems, (pair: MatchingPair) => {
            this.LeftChip(pair)
          }, (pair: MatchingPair) => pair.left)
        }
        .layoutWeight(1)

        // 连线通道: 命中画彩线, 选中画虚线短线, 配错画红色虚线弧线
        Stack() {
          if (this.selectedLeft !== '' && this.wrongRight === '') {
            Path({ width: LANE_WIDTH, height: this.boardHeight() })
              .commands(this.stubCommands())
              .fill(Color.Transparent)
              .stroke(this.themePrimary)
              .strokeWidth(2)
              .strokeDashArray([4, 4])
              .strokeLineCap(LineCapStyle.Round)
              .position({ x: 0, y: 0 })
              .transition(TransitionEffect.OPACITY.animation({ duration: 150 }))
          }
          if (this.wrongRight !== '' && this.selectedLeft !== '') {
            Path({ width: LANE_WIDTH, height: this.boardHeight() })
              .commands(this.wrongWireCommands())
              .fill(Color.Transparent)
              .stroke(WRONG_RED)
              .strokeWidth(2)
              .strokeDashArray([4, 4])
              .strokeLineCap(LineCapStyle.Round)
              .position({ x: 0, y: 0 })
              .transition(TransitionEffect.OPACITY.animation({ duration: 120 }))
          }
          ForEach(this.matchedOrder, (pair: MatchingPair) => {
            Stack() {
              Path({ width: LANE_WIDTH, height: this.boardHeight() })
                .commands(this.pairWireCommands(pair))
                .fill(Color.Transparent)
                .stroke(this.wireColorForPair(pair))
                .strokeWidth(2.5)
                .strokeLineCap(LineCapStyle.Round)
                .position({ x: 0, y: 0 })
              Circle({ width: 7, height: 7 })
                .fill(this.wireColorForPair(pair))
                .position({ x: 0.5, y: this.pairLeftPinY(pair) })
              Circle({ width: 7, height: 7 })
                .fill(this.wireColorForPair(pair))
                .position({ x: LANE_WIDTH - 7.5, y: this.pairRightPinY(pair) })
            }
            .width(LANE_WIDTH)
            .height(this.boardHeight())
            .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut }))
          }, (pair: MatchingPair) => pair.left + '_wire')
        }
        .width(LANE_WIDTH)
        .height(this.boardHeight())

        // 右列 (洗牌序)
        Column({ space: CHIP_GAP }) {
          ForEach(this.rightItems, (pair: MatchingPair) => {
            this.RightChip(pair)
          }, (pair: MatchingPair) => pair.right)
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .padding(10)
    .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '14' : '0A'))
    .borderRadius(10)
  }

  private pairLeftPinY(pair: MatchingPair): number {
    const li = this.indexOfLeft(pair.left)
    return li >= 0 ? this.rowCenterY(li) - 3.5 : 0
  }

  private pairRightPinY(pair: MatchingPair): number {
    const ri = this.indexOfRight(pair.right)
    return ri >= 0 ? this.rowCenterY(ri) - 3.5 : 0
  }

  @Builder
  LeftChip(pair: MatchingPair) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        Text(this.getLeftDisplay(pair))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(CHIP_HEIGHT)
      .justifyContent(FlexAlign.Center)
      .padding({ left: 8, right: 8 })
      .borderRadius(12)
      .backgroundColor(this.getLeftBackground(pair))
      .border({
        width: this.getLeftBorderWidth(pair.left),
        color: this.getLeftBorderColor(pair)
      })
      .scale(this.pressedKey === pair.left ? { x: 0.96, y: 0.96 } : { x: 1, y: 1 })
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onClick(() => {
        this.handleLeftTap(pair.left)
      })
      .onTouch((event: TouchEvent) => {
        this.handleChipTouch(event, pair.left, this.isLeftMatched(pair.left) || this.isFinished())
      })

      if (this.isLeftMatched(pair.left)) {
        this.CheckBadge(this.wireColorForPair(pair))
      }
    }
    .width('100%')
    .height(CHIP_HEIGHT)
  }

  @Builder
  RightChip(pair: MatchingPair) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        Text(this.getRightDisplay(pair))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.getRightFontColor(pair.right))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(CHIP_HEIGHT)
      .justifyContent(FlexAlign.Center)
      .padding({ left: 8, right: 8 })
      .borderRadius(12)
      .backgroundColor(this.getRightBackground(pair.right))
      .border({
        width: this.getRightBorderWidth(pair.right),
        color: this.getRightBorderColor(pair.right)
      })
      .scale(this.wrongRight === pair.right ? { x: 1.04, y: 1.04 }
        : (this.pressedKey === pair.right ? { x: 0.96, y: 0.96 } : { x: 1, y: 1 }))
      .animation({ duration: 120, curve: Curve.EaseOut })
      .onClick(() => {
        this.handleRightTap(pair.right)
      })
      .onTouch((event: TouchEvent) => {
        this.handleChipTouch(event, pair.right, this.isRightMatched(pair.right) || this.isFinished())
      })

      if (this.isRightMatched(pair.right)) {
        this.CheckBadge(this.wireColorForPair(pair))
      }
    }
    .width('100%')
    .height(CHIP_HEIGHT)
  }

  @Builder
  CheckBadge(color: string) {
    Text('✓')
      .fontSize(10)
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .width(16)
      .height(16)
      .textAlign(TextAlign.Center)
      .borderRadius(8)
      .backgroundColor(color)
      .margin({ top: -5, right: -5 })
  }

  @Builder
  ProgressRow() {
    Row() {
      Row({ space: 5 }) {
        ForEach(this.leftItems, (pair: MatchingPair) => {
          Circle({ width: 8, height: 8 })
            .fill(this.isLeftMatched(pair.left)
              ? this.wireColorForLeft(pair.left)
              : withColorAlpha(this.themePrimary, '30'))
        }, (pair: MatchingPair) => pair.left + '_dot')
      }

      Text(`失误 ${this.mistakes} 次`)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
  }

  private getLeftBackground(pair: MatchingPair): ResourceColor {
    if (this.isLeftMatched(pair.left)) {
      return withColorAlpha(this.wireColorForPair(pair), '1C')
    }
    if (this.selectedLeft === pair.left) {
      return withColorAlpha(this.themePrimary, '1F')
    }
    return $r('app.color.surface')
  }

  private getLeftBorderColor(pair: MatchingPair): ResourceColor {
    if (this.isLeftMatched(pair.left)) {
      return this.wireColorForPair(pair)
    }
    if (this.selectedLeft === pair.left) {
      return this.themePrimary
    }
    return $r('app.color.divider')
  }

  private getLeftBorderWidth(left: string): number {
    if (this.isLeftMatched(left) || this.selectedLeft === left) {
      return 2
    }
    return 1
  }

  private getRightFontColor(right: string): ResourceColor {
    if (this.wrongRight === right) {
      return WRONG_RED
    }
    return $r('app.color.text_primary')
  }

  private getRightBackground(right: string): ResourceColor {
    if (this.wrongRight === right) {
      return withColorAlpha(WRONG_RED, '1A')
    }
    const pair = this.findRightPair(right)
    if (pair !== null && this.isRightMatched(right)) {
      return withColorAlpha(this.wireColorForPair(pair), '1C')
    }
    return $r('app.color.surface')
  }

  private findRightPair(right: string): MatchingPair | null {
    for (let i = 0; i < this.originalPairs.length; i++) {
      if (this.originalPairs[i].right === right) {
        return this.originalPairs[i]
      }
    }
    return null
  }

  private getRightBorderColor(right: string): ResourceColor {
    if (this.wrongRight === right) {
      return WRONG_RED
    }
    const pair = this.findRightPair(right)
    if (pair !== null && this.isRightMatched(right)) {
      return this.wireColorForPair(pair)
    }
    return $r('app.color.divider')
  }

  private getRightBorderWidth(right: string): number {
    if (this.wrongRight === right || this.isRightMatched(right)) {
      return 2
    }
    return 1
  }

  @Builder
  ResultFeedback() {
    Column({ space: 8 }) {
      // 结果横幅
      Row({ space: 8 }) {
        Text(this.getBannerEmoji())
          .fontSize(22)
        Column({ space: 2 }) {
          Text(this.getBannerTitle())
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.hasWon() ? SUCCESS_GREEN : $r('app.color.text_primary'))
          Text(this.getBannerSub())
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(10)
      .borderRadius(10)
      .backgroundColor(withColorAlpha(this.hasWon() ? SUCCESS_GREEN : GIVEUP_ORANGE,
        this.isDarkMode ? '18' : '0C'))
      .border({
        width: 1,
        color: withColorAlpha(this.hasWon() ? SUCCESS_GREEN : GIVEUP_ORANGE,
          this.isDarkMode ? '38' : '28')
      })
      .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))

      // 配对答案一览 (已答态, 圆点颜色与连线一致)
      if (this.isAnswered) {
        Column({ space: 6 }) {
          ForEach(this.originalPairs, (pair: MatchingPair, index: number) => {
            Row({ space: 6 }) {
              Circle({ width: 6, height: 6 })
                .fill(WIRE_COLORS[index % WIRE_COLORS.length])
              Text(this.getLeftDisplay(pair))
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
              Text('—')
                .fontSize(13)
                .fontColor($r('app.color.text_tertiary'))
              Text(this.getRightDisplay(pair))
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
          }, (pair: MatchingPair) => pair.left + '_answer')
        }
        .width('100%')
        .padding(8)
        .borderRadius(8)
        .backgroundColor(withColorAlpha(this.themePrimary, '0D'))
      }
    }
    .width('100%')
  }
}
