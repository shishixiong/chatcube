/**
 * MatchingPairsCard - 连一连配对互动卡片
 *
 * 解析 toolCall.arguments 中的配对参数, 以游戏化方式展示:
 * - 双列布局: 左列原序, 右列种子化洗牌 (shuffleRightColumn)
 * - 纯点击交互 (v1 不做拖拽, 避免与外层 List 滚动手势冲突):
 *   点左高亮 → 点右: 对 → 双双锁定成功态 (绿 + ✓, 禁用);
 *   错 → mistakes+1 + 红色抖动提示, 清空选中
 * - 全部配对成功 → onAnswer(completed: true)
 * - 放弃路径镜像 CategorizationCard → onAnswer(completed: false)
 *
 * 预校验由 ToolExecutionService.handleMatchingPairs 在 pending 前完成;
 * aboutToAppear 仍做防御性重解析 (双保险, 历史消息渲染不经 handler)。
 *
 * 参考 CategorizationCard / PinyinQuizCard 模式: @ComponentV2 + @Event onAnswer 回调
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
  @Local selectedLeft: string = ''
  @Local matchedLefts: string[] = []
  @Local matchedRights: string[] = []
  @Local mistakes: number = 0
  @Local wrongRight: string = ''              // 当前红色闪烁的右项
  @Local isCompleted: boolean = false
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
        // 已答态: 全部标记为已配对
        const lefts: string[] = []
        const rights: string[] = []
        for (let i = 0; i < parsed.pairs.length; i++) {
          lefts.push(parsed.pairs[i].left)
          rights.push(parsed.pairs[i].right)
        }
        this.matchedLefts = lefts
        this.matchedRights = rights
      } catch (e) {
        console.warn('MatchingPairsCard', `failed to parse answeredPayload: ${JSON.stringify(e)}`)
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

  private isLeftMatched(left: string): boolean {
    return this.matchedLefts.indexOf(left) >= 0
  }

  private isRightMatched(right: string): boolean {
    return this.matchedRights.indexOf(right) >= 0
  }

  private findRightOfLeft(left: string): string {
    for (let i = 0; i < this.originalPairs.length; i++) {
      if (this.originalPairs[i].left === left) {
        return this.originalPairs[i].right
      }
    }
    return ''
  }

  private handleLeftTap(left: string): void {
    if (this.isCompleted || this.isAnswered || this.isLeftMatched(left)) {
      return
    }
    this.selectedLeft = this.selectedLeft === left ? '' : left
  }

  private handleRightTap(right: string): void {
    if (this.isCompleted || this.isAnswered || this.selectedLeft === '' || this.isRightMatched(right)) {
      return
    }
    const expected = this.findRightOfLeft(this.selectedLeft)
    if (right === expected) {
      // 配对成功: 双双锁定
      const lefts = this.matchedLefts.slice(0)
      lefts.push(this.selectedLeft)
      const rights = this.matchedRights.slice(0)
      rights.push(right)
      this.matchedLefts = lefts
      this.matchedRights = rights
      this.selectedLeft = ''
      this.checkCompletion()
    } else {
      // 配错: mistakes+1 + 红色闪烁, 清空选中
      this.mistakes += 1
      this.wrongRight = right
      this.selectedLeft = ''
      if (this.wrongTimerId >= 0) {
        clearTimeout(this.wrongTimerId)
      }
      this.wrongTimerId = setTimeout(() => {
        this.wrongRight = ''
        this.wrongTimerId = -1
      }, 600)
    }
  }

  private checkCompletion(): void {
    if (this.matchedLefts.length < this.originalPairs.length) {
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
    const payload: MatchingPairsAnswerPayload = {
      completed: false,
      correct: this.matchedLefts.length,
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

  build() {
    Column({ space: 10 }) {
      // 标题行
      Row() {
        Text('连一连')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 6 })
        if (this.theme !== '') {
          Text(this.theme)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ left: 8 })
        }
      }
      .width('100%')

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
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')

        // 失误计数
        if (!this.isCompleted) {
          Text(`已配对 ${this.matchedLefts.length}/${this.originalPairs.length} · 失误 ${this.mistakes} 次`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
        }

        // 双列配对区
        this.ColumnsArea()

        // 放弃入口
        if (!this.isCompleted && !this.isAnswered) {
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
        if (this.isCompleted || this.isAnswered) {
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
  ColumnsArea() {
    Row({ space: 10 }) {
      // 左列 (原序)
      Column({ space: 8 }) {
        if (this.leftLabel !== '') {
          Text(this.leftLabel)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        ForEach(this.leftItems, (pair: MatchingPair) => {
          this.LeftButton(pair)
        }, (pair: MatchingPair) => pair.left)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      // 右列 (洗牌序)
      Column({ space: 8 }) {
        if (this.rightLabel !== '') {
          Text(this.rightLabel)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        ForEach(this.rightItems, (pair: MatchingPair) => {
          this.RightButton(pair)
        }, (pair: MatchingPair) => pair.right)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding(10)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(10)
  }

  @Builder
  LeftButton(pair: MatchingPair) {
    Column() {
      Text(this.getLeftDisplay(pair))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.getLeftFontColor(pair.left))
    }
    .width('100%')
    .height(52)
    .justifyContent(FlexAlign.Center)
    .borderRadius(12)
    .backgroundColor(this.getLeftBackground(pair.left))
    .border({
      width: this.getLeftBorderWidth(pair.left),
      color: this.getLeftBorderColor(pair.left)
    })
    .onClick(() => {
      this.handleLeftTap(pair.left)
    })
    .animation({ duration: 150, curve: Curve.EaseOut })
  }

  @Builder
  RightButton(pair: MatchingPair) {
    Column() {
      Text(this.getRightDisplay(pair))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.getRightFontColor(pair.right))
      if (this.isRightMatched(pair.right)) {
        Text('✓')
          .fontSize(12)
          .fontColor(Color.Green)
      }
    }
    .width('100%')
    .height(52)
    .justifyContent(FlexAlign.Center)
    .borderRadius(12)
    .backgroundColor(this.getRightBackground(pair.right))
    .border({
      width: this.getRightBorderWidth(pair.right),
      color: this.getRightBorderColor(pair.right)
    })
    .scale(this.wrongRight === pair.right ? { x: 1.04, y: 1.04 } : { x: 1, y: 1 })
    .onClick(() => {
      this.handleRightTap(pair.right)
    })
    .animation({ duration: 150, curve: Curve.EaseOut })
  }

  private getLeftFontColor(left: string): ResourceColor {
    if (this.isLeftMatched(left)) {
      return Color.Green
    }
    return $r('app.color.text_primary')
  }

  private getLeftBackground(left: string): ResourceColor {
    if (this.isLeftMatched(left)) {
      return withColorAlpha(SUCCESS_GREEN, '1A')
    }
    if (this.selectedLeft === left) {
      return withColorAlpha(this.themePrimary, '1F')
    }
    return $r('app.color.surface')
  }

  private getLeftBorderColor(left: string): ResourceColor {
    if (this.isLeftMatched(left)) {
      return SUCCESS_GREEN
    }
    if (this.selectedLeft === left) {
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
      return Color.Red
    }
    if (this.isRightMatched(right)) {
      return Color.Green
    }
    return $r('app.color.text_primary')
  }

  private getRightBackground(right: string): ResourceColor {
    if (this.wrongRight === right) {
      return withColorAlpha(WRONG_RED, '1A')
    }
    if (this.isRightMatched(right)) {
      return withColorAlpha(SUCCESS_GREEN, '1A')
    }
    return $r('app.color.surface')
  }

  private getRightBorderColor(right: string): ResourceColor {
    if (this.wrongRight === right) {
      return WRONG_RED
    }
    if (this.isRightMatched(right)) {
      return SUCCESS_GREEN
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
    Column({ space: 6 }) {
      if (this.isAnswered || this.prevCompleted) {
        // 已答态 (在线视图恢复)
        Row({ space: 6 }) {
          Text(this.prevCompleted ? '🎉' : '💪')
            .fontSize(20)
          Text(this.prevCompleted
            ? (this.prevMistakes === 0 ? '全对！观察力真棒！' : `配对完成！失误 ${this.prevMistakes} 次`)
            : '下次再来挑战～')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.prevCompleted ? Color.Green : $r('app.color.text_primary'))
        }
        .width('100%')
      } else if (this.isCompleted) {
        // 本局完成 (待答态交互结束)
        Row({ space: 6 }) {
          Text('🎉')
            .fontSize(20)
          Text(this.mistakes === 0 ? '全对！观察力真棒！' : `配对完成！失误 ${this.mistakes} 次`)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.Green)
        }
        .width('100%')
      }

      // 配对答案一览 (已答态)
      if (this.isAnswered) {
        Column({ space: 4 }) {
          ForEach(this.originalPairs, (pair: MatchingPair) => {
            Row({ space: 6 }) {
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
            }
            .width('100%')
          }, (pair: MatchingPair) => pair.left)
        }
        .width('100%')
        .padding(8)
        .borderRadius(8)
        .backgroundColor(withColorAlpha(this.themePrimary, '0D'))
      }
    }
    .width('100%')
    .padding(10)
    .borderRadius(8)
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
  }
}
