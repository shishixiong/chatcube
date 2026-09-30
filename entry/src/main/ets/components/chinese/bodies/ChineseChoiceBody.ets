// entry/src/main/ets/components/chinese/bodies/ChineseChoiceBody.ets
/**
 * ChineseChoiceBody - chinese_quiz 三种 4 选 1 mode 的共用 body
 * word_build: 本字 + 选能跟它组词的词
 * lookalike:  含 ___ 的句子 + 4 个单字选项选填空
 * antonym:    本字 + 选意思相反的词
 * 点选项即判即交; 授星走 chinese_quiz 既有分支 (correct=true → 1 星)。
 */

import { ToolCall } from '../../../models/ChatModels'
import { getAppUiState } from '../../../state/AppUiState'
import { withColorAlpha } from '../../../utils/ColorAlphaUtils'
import { CardShell } from '../../cardshell/CardShell'
import { CardShellConfig } from '../../cardshell/CardShellTypes'
import { CardShellState } from '../../cardshell/CardShellState'
import {
  ChineseQuizAnswerPayload, ChineseQuizMode, ChineseQuizModeArgs, chineseModeDisplayName,
  parseChineseQuizModeArgs
} from '../ModeTypes'

@ComponentV2
export struct ChineseChoiceBody {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local mode: string = 'word_build'
  @Local stem: string = ''
  @Local character: string = ''
  @Local options: string[] = []
  @Local correctAnswer: string = ''
  @Local skillKey: string = 'chinese_vocab'
  @Local selectedOption: string = ''
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  private shellConfig: CardShellConfig = {
    title: '语文小练习', subtitle: '', icon: $r('sys.symbol.book'),
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
    const args: ChineseQuizModeArgs = parseChineseQuizModeArgs(this.toolCall.arguments)
    this.mode = args.mode
    this.stem = args.stem
    this.character = args.character
    this.options = args.options
    this.correctAnswer = args.answer
    this.skillKey = args.skillKey
    this.shellConfig = {
      title: '语文小练习',
      subtitle: chineseModeDisplayName(args.mode) + ` · 难度 ${args.difficulty}`,
      icon: $r('sys.symbol.book'),
      stem: '', hasAudio: false, usesConfirm: false,
      feedbackTitleCorrect: '答对啦！真棒！', correctAnswerLabel: '正确答案'
    }
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
        // payload 缺失/不可解析: 无法判定当时对错, 抑制反馈横幅 (ChoiceModeBody 同款守卫)
        this.shellState.feedbackSuppressed = true
        this.shellState.headPill = '已回答'
        this.shellState.headPillColor = '#4CAF50'
      }
    }
  }

  private parsePreviousAnswer(): ChineseQuizAnswerPayload | null {
    if (this.answeredPayload === '') {
      return null
    }
    try {
      return JSON.parse(this.answeredPayload) as ChineseQuizAnswerPayload
    } catch (_e) {
      return null
    }
  }

  private handleOptionSelect(option: string): void {
    if (this.isAnswered || this.showResult) {
      return
    }
    const correct = option === this.correctAnswer
    this.selectedOption = option
    this.showResult = true
    this.isCorrect = correct
    this.shellState.hasSelection = true
    this.shellState.submitted = true
    this.shellState.isCorrect = correct

    const payload: ChineseQuizAnswerPayload = {
      answered: true,
      mode: this.argsMode(),
      child_answer: option,
      correct: correct,
      correct_answer: this.correctAnswer,
      skill_key: this.skillKey
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private argsMode(): ChineseQuizMode {
    if (this.mode === 'sentence_order' || this.mode === 'lookalike' || this.mode === 'antonym') {
      return this.mode
    }
    return 'word_build'
  }

  /** stem 里的 ___ 高亮渲染: 拆成前后段, 空位画方框 */
  private stemBefore(): string {
    const idx = this.stem.indexOf('___')
    if (idx < 0) {
      return this.stem
    }
    return this.stem.substring(0, idx)
  }

  private stemAfter(): string {
    const idx = this.stem.indexOf('___')
    if (idx < 0) {
      return ''
    }
    return this.stem.substring(idx + 3)
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
      Column({ space: 10 }) {
        this.PromptArea()
        if (!this.isAnswered && !this.showResult) {
          this.OptionsGrid()
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.getCardBackgroundColor())
      .borderRadius(10)
    }
  }

  @Builder
  PromptArea() {
    if (this.mode === 'lookalike' && this.stem !== '') {
      Flex({
        wrap: FlexWrap.Wrap,
        justifyContent: FlexAlign.Center,
        alignItems: ItemAlign.Center
      }) {
        Text(this.stemBefore())
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        if (this.showResult) {
          Text(this.correctAnswer)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isCorrect ? $r('app.color.status_success') : this.themePrimary)
        } else {
          Text('⬜')
            .fontSize(22)
        }
        Text(this.stemAfter())
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
    } else if (this.character !== '') {
      // word_build / antonym: 大字展示
      Column({ space: 4 }) {
        Text(this.character)
          .fontSize(56)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.mode === 'antonym' ? '它的反义词是哪个？' : '哪个词能跟它做朋友？')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  OptionsGrid() {
    Grid() {
      ForEach(this.options, (option: string, idx: number) => {
        GridItem() {
          Button(option)
            .fontSize(this.mode === 'lookalike' ? 24 : 16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .width('100%')
            .height(56)
            .backgroundColor(this.themePrimary)
            .borderRadius(12)
            .onClick(() => {
              this.handleOptionSelect(option)
            })
        }
      }, (option: string, idx: number) => `opt_${idx}_${option}`)
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(10)
    .rowsGap(10)
    .width('100%')
  }
}
