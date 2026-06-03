/**
 * MathQuizCard - 数学游戏互动卡片
 *
 * 解析 toolCall.arguments 中的数学题目参数, 以游戏化方式展示:
 * - 题目描述（口语化）
 * - 算式（如 "3 + 2 = ?"）
 * - 数字选项按钮（小朋友点选答案）
 * - 提交后即时反馈对错
 *
 * 参考 AskUserCard 模式: @ComponentV2 + @Event onAnswer 回调
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { evaluateMathExpression } from '../utils/MathExpressionParser'

interface MathQuizQuestion {
  question: string
  expression: string
  correctAnswer: number
  options: number[]
  skillKey: string
}

interface MathQuizAnswerPayload {
  answered: boolean
  child_answer: number
  child_answer_valid: boolean
  correct: boolean
  correct_answer: number
  expression: string
  question: string
  skill_key: string
}

@ComponentV2
export struct MathQuizCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local selectedOption: number = -1
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local correctAnswerValue: number = 0

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
    // 如果是已回答状态, 从 answeredPayload 中恢复选中项和结果
    if (this.isAnswered) {
      const prev = this.parsePreviousAnswer()
      if (prev !== null) {
        this.selectedOption = prev.child_answer
        this.showResult = true
        this.isCorrect = prev.correct
        this.correctAnswerValue = prev.correct_answer
      }
    }
  }

  private parseQuiz(): MathQuizQuestion {
    const result: MathQuizQuestion = {
      question: '',
      expression: '',
      correctAnswer: 0,
      options: [],
      skillKey: ''
    }
    try {
      const parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      result.question = (parsed['question'] as string) ?? ''
      result.expression = (parsed['expression'] as string) ?? ''
      result.correctAnswer = (parsed['correct_answer'] as number) ?? 0
      result.skillKey = (parsed['skill_key'] as string) ?? ''

      const rawOptions = parsed['options']
      if (Array.isArray(rawOptions)) {
        const arr = rawOptions as Object[]
        for (let i = 0; i < arr.length; i++) {
          const val = arr[i]
          if (typeof val === 'number') {
            result.options.push(val as number)
          }
        }
      }

      // 如果 AI 没传 correct_answer, 尝试计算
      if (result.correctAnswer === 0 && result.expression !== '') {
        try {
          result.correctAnswer = evaluateMathExpression(result.expression)
        } catch (_e) {
          // 无法计算, 保持 0
        }
      }
    } catch (_e) {}
    return result
  }

  private parsePreviousAnswer(): MathQuizAnswerPayload | null {
    if (this.answeredPayload === '') {
      return null
    }
    try {
      return JSON.parse(this.answeredPayload) as MathQuizAnswerPayload
    } catch (_e) {
      return null
    }
  }

  private handleSelectOption(option: number): void {
    if (this.isAnswered || this.showResult) {
      return
    }
    this.selectedOption = option
    // 选择后直接提交答案
    this.handleSubmit()
  }

  private handleSubmit(): void {
    if (this.selectedOption < 0 || this.isAnswered) {
      return
    }

    const quiz = this.parseQuiz()
    const isCorrect = Math.abs(this.selectedOption - quiz.correctAnswer) < 0.001

    // 先显示即时反馈
    this.showResult = true
    this.isCorrect = isCorrect
    this.correctAnswerValue = quiz.correctAnswer

    // 构建 payload 回传
    const payload: MathQuizAnswerPayload = {
      answered: true,
      child_answer: this.selectedOption,
      child_answer_valid: true,
      correct: isCorrect,
      correct_answer: quiz.correctAnswer,
      expression: quiz.expression,
      question: quiz.question,
      skill_key: quiz.skillKey
    }

    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private getOptionBackgroundColor(option: number): ResourceColor {
    if (!this.showResult && !this.isAnswered) {
      return this.selectedOption === option ? this.themePrimary : $r('app.color.surface')
    }

    const quiz = this.parseQuiz()
    if (option === quiz.correctAnswer) {
      return '#4CAF50'
    }
    if (option === this.selectedOption && !this.isCorrect) {
      return '#FF9F43'
    }
    return $r('app.color.surface')
  }

  private getOptionTextColor(option: number): ResourceColor {
    if (!this.showResult && !this.isAnswered) {
      return this.selectedOption === option ? Color.White : $r('app.color.text_primary')
    }

    const quiz = this.parseQuiz()
    if (option === quiz.correctAnswer) {
      return Color.White
    }
    if (option === this.selectedOption && !this.isCorrect) {
      return Color.White
    }
    return $r('app.color.text_secondary')
  }

  private getCardBackgroundColor(): string {
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12')
  }

  private getFirstRowOptions(options: number[]): number[] {
    const result: number[] = []
    const count = options.length <= 3 ? 2 : 2
    for (let i = 0; i < Math.min(count, options.length); i++) {
      result.push(options[i])
    }
    return result
  }

  private getSecondRowOptions(options: number[]): number[] {
    if (options.length <= 2) {
      return []
    }
    const result: number[] = []
    for (let i = 2; i < options.length; i++) {
      result.push(options[i])
    }
    return result
  }

  build() {
    Column({ space: 10 }) {
      // 标题行
      Row() {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(14)
          .fontColor([this.themePrimary])
        Text('数学小游戏')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 6 })
        Blank()
        if (this.isAnswered) {
          Text('已回答')
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.status_success'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
        }
      }
      .width('100%')

      // 题目区域
      this.QuizContent()

      // 结果反馈
      if (this.showResult || this.isAnswered) {
        this.ResultFeedback()
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.themeAiBubble)
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  OptionButton(opt: number) {
    Column() {
      Text(`${opt}`)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.getOptionTextColor(opt))
    }
    .layoutWeight(1)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.getOptionBackgroundColor(opt))
    .borderRadius(12)
    .border({
      width: this.selectedOption === opt && !this.showResult && !this.isAnswered ? 2 : 1,
      color: this.selectedOption === opt && !this.showResult && !this.isAnswered ? this.themePrimary : $r('app.color.divider')
    })
    .onClick(() => {
      this.handleSelectOption(opt)
    })
    .animation({ duration: 150, curve: Curve.EaseOut })
  }

  @Builder
  QuizContent() {
    Column({ space: 10 }) {
      ForEach([this.parseQuiz()], (quiz: MathQuizQuestion) => {
        // 题目文字
        if (quiz.question !== '') {
          Text(quiz.question)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
        }

        // 算式
        if (quiz.expression !== '') {
          Text(`${quiz.expression} = ?`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.themePrimary)
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 2, bottom: 2 })
        }

        // 选项按钮: 两行网格布局, 避免溢出屏幕
        if (quiz.options.length > 0) {
          Column({ space: 10 }) {
            // 第一行: 前 2 个选项
            Row({ space: 10 }) {
              ForEach(this.getFirstRowOptions(quiz.options), (opt: number, idx: number) => {
                this.OptionButton(opt)
              }, (opt: number, idx: number) => `row1_${opt}_${idx}`)
            }
            .width('100%')

            // 第二行: 剩余选项
            if (this.getSecondRowOptions(quiz.options).length > 0) {
              Row({ space: 10 }) {
                ForEach(this.getSecondRowOptions(quiz.options), (opt: number, idx: number) => {
                  this.OptionButton(opt)
                }, (opt: number, idx: number) => `row2_${opt}_${idx}`)
              }
              .width('100%')
            }
          }
          .width('100%')
        }
      }, (_: MathQuizQuestion) => 'quiz')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getCardBackgroundColor())
    .borderRadius(10)
  }

  @Builder
  ResultFeedback() {
    if (this.showResult) {
      if (this.isCorrect) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(16)
            .fontColor(['#4CAF50'])
          Text('答对了, 真棒!')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#4CAF50')
        }
        .width('100%')
      } else {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(16)
            .fontColor(['#FF9F43'])
          Text(`再想想哦, 正确答案是 ${this.correctAnswerValue}`)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FF9F43')
        }
        .width('100%')
      }
    } else if (this.isAnswered) {
      // 从 answeredPayload 中解析结果
      ForEach([this.parsePreviousAnswer()], (prev: MathQuizAnswerPayload | null) => {
        if (prev !== null) {
          if (prev.correct) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.checkmark_circle'))
                .fontSize(16)
                .fontColor(['#4CAF50'])
              Text('答对了, 真棒!')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#4CAF50')
            }
            .width('100%')
          } else {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.xmark_circle'))
                .fontSize(16)
                .fontColor(['#FF9F43'])
              Text(`正确答案是 ${prev.correct_answer}`)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FF9F43')
            }
            .width('100%')
          }
        }
      }, (_: MathQuizAnswerPayload | null) => 'result')
    }
  }
}
