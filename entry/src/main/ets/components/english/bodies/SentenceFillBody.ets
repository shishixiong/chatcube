// entry/src/main/ets/components/english/bodies/SentenceFillBody.ets
/**
 * SentenceFillBody - english_quiz v2 句型填空 body
 * pattern 按 ___ 切分, 空位高亮槽 + 4 词块点选, 点选即判即交。
 */

import { ToolCall } from '../../../models/ChatModels'
import { getAppUiState } from '../../../state/AppUiState'
import { withColorAlpha } from '../../../utils/ColorAlphaUtils'
import { CardShell } from '../../cardshell/CardShell'
import { CardShellConfig } from '../../cardshell/CardShellTypes'
import { CardShellState } from '../../cardshell/CardShellState'
import {
  EnglishQuizAnswerPayload, EnglishQuizModeArgs, parseEnglishQuizModeArgs
} from '../ModeTypes'

@ComponentV2
export struct SentenceFillBody {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local patternBefore: string = ''
  @Local patternAfter: string = ''
  @Local question: string = ''
  @Local options: string[] = []
  @Local correctAnswer: string = ''
  @Local selectedOption: string = ''
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local skillKey: string = 'english_sentence'
  @Local stage: string = ''
  private shellConfig: CardShellConfig = {
    title: '句型填空', subtitle: '', icon: $r('sys.symbol.square_and_pencil'),
    stem: '', hasAudio: false, usesConfirm: false,
    feedbackTitleCorrect: '答对啦！真棒！', correctAnswerLabel: '正确答案'
  }
  private shellState: CardShellState = new CardShellState()

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  aboutToAppear(): void {
    const args: EnglishQuizModeArgs = parseEnglishQuizModeArgs(this.toolCall.arguments)
    // 校验层已保证恰一个 ___; 防御: 多于一个时按第一段截断
    const firstSplit = args.pattern.split('___')
    this.patternBefore = firstSplit.length > 0 ? firstSplit[0] : args.pattern
    this.patternAfter = firstSplit.length > 1 ? firstSplit[1] : ''
    this.question = args.question
    this.options = args.options
    this.correctAnswer = args.correctAnswer
    this.skillKey = args.skillKey
    this.stage = args.stage
    if (this.isAnswered) {
      const prev = this.parsePreviousAnswer()
      if (prev !== null) {
        this.selectedOption = prev.child_answer
        this.showResult = true
        this.isCorrect = prev.correct
        this.shellState.submitted = true
        this.shellState.hasSelection = true
        this.shellState.isCorrect = prev.correct
        this.shellState.headPill = '已回答'
        this.shellState.headPillColor = '#4CAF50'
      } else {
        // payload 缺失/不可解析: 无法判定当时对错, 抑制反馈横幅 (MathQuizCard 同款守卫)
        this.shellState.feedbackSuppressed = true
        this.shellState.headPill = '已回答'
        this.shellState.headPillColor = '#4CAF50'
      }
    }
  }

  private parsePreviousAnswer(): EnglishQuizAnswerPayload | null {
    if (this.answeredPayload === '') {
      return null
    }
    try {
      return JSON.parse(this.answeredPayload) as EnglishQuizAnswerPayload
    } catch (_e) {
      return null
    }
  }

  private handleOptionSelect(option: string): void {
    if (this.isAnswered || this.showResult) {
      return
    }
    const correct = option.trim().toLowerCase() === this.correctAnswer.trim().toLowerCase()
    this.selectedOption = option
    this.showResult = true
    this.isCorrect = correct
    this.shellState.hasSelection = true
    this.shellState.submitted = true
    this.shellState.isCorrect = correct

    const payload: EnglishQuizAnswerPayload = {
      answered: true,
      child_answer: option,
      correct: correct,
      correct_answer: this.correctAnswer,
      word: '',
      sentence: this.correctAnswer,
      question_type: 'sentence_fill',
      skill_key: this.skillKey,
      mode: 'sentence_fill',
      stage: this.stage,
      pattern: this.patternBefore + '___' + this.patternAfter
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private getCardBackgroundColor(): string {
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12')
  }

  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: this.correctAnswer,
      onConfirm: (): void => {},
      onRetry: (): void => {}
    }) {
      Column({ space: 12 }) {
        Text(this.question)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
        // 句型行: 前 _ 空位槽 _ 后
        Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Center, justifyContent: FlexAlign.Center }) {
          Text(this.patternBefore)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.showResult || this.selectedOption !== '' ? this.selectedOption : '?')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.showResult ? (this.isCorrect ? '#4CAF50' : '#FF6B6B') : this.themePrimary)
            .backgroundColor(this.showResult ? Color.Transparent : withColorAlpha(this.themePrimary, '1A'))
            .borderRadius(8)
            .padding({ left: 10, right: 10 })
            .constraintSize({ minWidth: 48 })
            .textAlign(TextAlign.Center)
          Text(this.patternAfter)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .padding(10)
        .backgroundColor(this.getCardBackgroundColor())
        .borderRadius(10)
        if (!this.isAnswered && !this.showResult) {
          this.OptionsGrid()
        }
      }
      .width('100%')
      .padding(12)
    }
  }

  @Builder
  OptionsGrid() {
    Grid() {
      ForEach(this.options, (option: string, idx: number) => {
        GridItem() {
          Button(option)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .width('100%')
            .height(52)
            .backgroundColor(this.themePrimary)
            .borderRadius(12)
            .onClick(() => {
              this.handleOptionSelect(option)
            })
        }
      }, (option: string, idx: number) => `fill_${idx}_${option}`)
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(10)
    .rowsGap(10)
    .width('100%')
  }
}
