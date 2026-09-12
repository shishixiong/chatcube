/**
 * PinyinQuizCard - 拼音题互动卡片
 *
 * 解析 toolCall.arguments 中的拼音题参数, 以游戏化方式展示:
 * - 大字号汉字展示区（48-64vp）
 * - 题目提示语（「这个字怎么读？」）
 * - 4 个带调拼音选项按钮（小朋友点选答案）
 * - 提交后即时反馈对错
 *
 * 参考 ListeningQuizCard / PictureVocabCard 模式: @ComponentV2 + @Event onAnswer 回调
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { CardShell } from './cardshell/CardShell'
import { CardShellConfig } from './cardshell/CardShellTypes'
import { CardShellState } from './cardshell/CardShellState'

interface PinyinQuizQuestion {
  character: string
  question: string
  correctAnswer: string
  options: string[]
  difficulty: number
  skillKey: string
}

interface PinyinQuizAnswerPayload {
  answered: boolean
  child_answer: string
  correct: boolean
  correct_answer: string
  character: string
  skill_key: string
}

@ComponentV2
export struct PinyinQuizCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local selectedOption: string = ''
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local quiz: PinyinQuizQuestion = {
    character: '',
    question: '',
    correctAnswer: '',
    options: [],
    difficulty: 1,
    skillKey: 'pinyin'
  }

  @Local shellConfig: CardShellConfig = {
    title: '拼音题',
    subtitle: '',
    icon: $r('sys.symbol.character_textbox'),
    stem: '',
    hasAudio: false,
    usesConfirm: true,
    feedbackTitleCorrect: '答对啦！真棒！',
    correctAnswerLabel: '正确读音'
  }
  private shellState: CardShellState = new CardShellState()

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  aboutToAppear(): void {
    this.quiz = this.parseQuiz()

    if (this.isAnswered && this.answeredPayload !== '') {
      try {
        const prev = JSON.parse(this.answeredPayload) as PinyinQuizAnswerPayload
        if (prev.answered) {
          this.selectedOption = prev.child_answer ?? ''
          this.showResult = true
          this.isCorrect = prev.correct
        }
      } catch (e) {
        console.warn('PinyinQuizCard', `failed to parse answeredPayload: ${JSON.stringify(e)}`)
      }
    }

    this.shellConfig = {
      title: '拼音题',
      subtitle: '',
      icon: $r('sys.symbol.character_textbox'),
      stem: this.getQuestionText(),
      hasAudio: false,
      usesConfirm: true,
      feedbackTitleCorrect: '答对啦！真棒！',
      correctAnswerLabel: '正确读音'
    }
    if (this.showResult) {
      this.shellState.submitted = true
      this.shellState.isCorrect = this.isCorrect
    }
  }

  private parseQuiz(): PinyinQuizQuestion {
    const result: PinyinQuizQuestion = {
      character: '',
      question: '',
      correctAnswer: '',
      options: [],
      difficulty: 1,
      skillKey: 'pinyin'
    }
    try {
      const parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      result.character = (parsed['character'] as string) ?? ''
      result.question = (parsed['question'] as string) ?? ''
      result.correctAnswer = (parsed['correct_answer'] as string) ?? ''
      const opts = parsed['options']
      if (opts instanceof Array) {
        const strings: string[] = []
        for (let i = 0; i < opts.length; i++) {
          strings.push(String(opts[i]))
        }
        result.options = strings
      }
      result.difficulty = (parsed['difficulty'] as number) ?? 1
      const skillKey = (parsed['skill_key'] as string) ?? ''
      result.skillKey = skillKey.trim() !== '' ? skillKey : 'pinyin'
    } catch (e) {
      console.error('PinyinQuizCard', `parseQuiz failed: ${JSON.stringify(e)}`)
    }
    return result
  }

  private getQuestionText(): string {
    if (this.quiz.question !== '') {
      return this.quiz.question
    }
    return '这个字怎么读？'
  }

  private getOptionGradient(_index: number): LinearGradient {
    return {
      angle: 135,
      colors: [
        [withColorAlpha(this.themePrimary, 'D9'), 0.0],
        [withColorAlpha(this.themePrimary, 'A6'), 1.0]
      ]
    }
  }

  private getOptionBorderColor(opt: string): ResourceColor {
    if (this.showResult || this.isAnswered) {
      if (opt === this.quiz.correctAnswer) {
        return Color.Green
      }
      if (opt === this.selectedOption && !this.isCorrect) {
        return Color.Red
      }
      return $r('app.color.divider')
    }
    if (opt === this.selectedOption) {
      return this.themePrimary
    }
    return $r('app.color.divider')
  }

  private getOptionBorderWidth(opt: string): number {
    if (this.showResult || this.isAnswered) {
      if (opt === this.quiz.correctAnswer || (opt === this.selectedOption && !this.isCorrect)) {
        return 3
      }
      return 1
    }
    return opt === this.selectedOption ? 3 : 1
  }

  private getOptionFontColor(opt: string): ResourceColor {
    if (this.showResult || this.isAnswered) {
      if (opt === this.quiz.correctAnswer) {
        return Color.Green
      }
      if (opt === this.selectedOption && !this.isCorrect) {
        return Color.Red
      }
    }
    return Color.White
  }

  private handleSelectOption(opt: string): void {
    if (this.isAnswered || this.showResult) {
      return
    }
    this.selectedOption = opt
    this.shellState.hasSelection = true
  }

  private handleConfirm(): void {
    if (this.selectedOption === '' || this.isAnswered || this.showResult) {
      return
    }

    const isCorrect = this.selectedOption === this.quiz.correctAnswer

    this.showResult = true
    this.isCorrect = isCorrect
    this.shellState.submitted = true
    this.shellState.isCorrect = isCorrect

    const payload: PinyinQuizAnswerPayload = {
      answered: true,
      child_answer: this.selectedOption,
      correct: isCorrect,
      correct_answer: this.quiz.correctAnswer,
      character: this.quiz.character,
      skill_key: this.quiz.skillKey
    }

    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private handleRetry(): void {
    if (!this.showResult || this.isCorrect || this.isAnswered) {
      return
    }
    this.selectedOption = ''
    this.showResult = false
    this.isCorrect = false
    this.shellState.hasSelection = false
    this.shellState.submitted = false
    this.shellState.isCorrect = false
  }

  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: this.quiz.correctAnswer,
      onConfirm: (): void => { this.handleConfirm() },
      onRetry: (): void => { this.handleRetry() }
    }) {
      this.CharacterArea()
      this.OptionsArea()
    }
  }

  @Builder
  CharacterArea() {
    Column({ space: 8 }) {
      Text(this.quiz.character)
        .fontSize(64)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(10)
  }

  @Builder
  OptionsArea() {
    if (this.quiz.options.length > 0) {
      Column({ space: 8 }) {
        ForEach(this.quiz.options, (opt: string, index: number) => {
          Column() {
            Text(opt)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getOptionFontColor(opt))
          }
          .width('100%')
          .height(56)
          .justifyContent(FlexAlign.Center)
          .linearGradient(this.getOptionGradient(index))
          .borderRadius(14)
          .border({
            width: this.getOptionBorderWidth(opt),
            color: this.getOptionBorderColor(opt)
          })
          .shadow({ radius: 3, color: '#20000000', offsetY: 2 })
          .onClick(() => {
            this.handleSelectOption(opt)
          })
          .animation({ duration: 150, curve: Curve.EaseOut })
        }, (opt: string) => opt)
      }
      .width('100%')
    }
  }
}
