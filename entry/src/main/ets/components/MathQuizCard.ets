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
import {
  MathQuizQuestion,
  MathQuizAnswerPayload,
  ExpressionToken,
  parseMathQuiz,
  parseMathQuizAnswer,
  tokenizeExpression,
  getOpDisplay,
  isCorrectAnswer
} from '../utils/MathQuizGame'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { PreferenceKeys } from '../services/PreferencesService'

@ComponentV2
export struct MathQuizCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local quiz: MathQuizQuestion = {
    type: 'arithmetic', question: '', expression: '', correctAnswer: 0,
    options: [], skillKey: '', leftValue: 0, rightValue: 0, operatorOptions: []
  }
  // arithmetic 用 number 选项; shape/comparison/time 用 string 选项
  @Local selectedOption: string | number = -1
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local correctAnswerValue: string | number = 0
  // 连胜状态: 持久化在 PreferencesService, 按 skill_key 区分
  @Local currentStreak: number = 0
  @Local bestStreak: number = 0
  @Local isNewBestStreak: boolean = false
  @Local streakLoaded: boolean = false

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
    // 解析一次题目数据, 后续渲染直接读取 this.quiz, 避免在 build 路径反复 JSON.parse
    this.quiz = parseMathQuiz(this.toolCall.arguments)
    // 如果是已回答状态, 从 answeredPayload 中恢复选中项和结果
    if (this.isAnswered) {
      const prev = parseMathQuizAnswer(this.answeredPayload)
      if (prev !== null) {
        this.selectedOption = prev.child_answer
        this.showResult = true
        this.isCorrect = prev.correct
        this.correctAnswerValue = prev.correct_answer
      }
    }
    // 异步加载连胜 (fire-and-forget, 由 streakLoaded 守卫竞态)
    this.loadStreak(this.quiz.skillKey)
  }

  private handleSelectOption(option: string | number): void {
    if (this.isAnswered || this.showResult) {
      return
    }
    this.selectedOption = option
    // 选完后不再直接提交, 由"确认"按钮触发, 给小朋友留出反悔/检查的时间
  }

  private handleConfirm(): void {
    // 哨兵 -1 同时覆盖 number 和 string | number (number -1 永远 < 0)
    const sentinel = this.selectedOption === -1
    if (sentinel || this.isAnswered || this.showResult) {
      return
    }
    this.handleSubmit()
  }

  private handleSubmit(): void {
    if (this.selectedOption === -1 || this.isAnswered) {
      return
    }

    const quiz = this.quiz
    const isCorrect = isCorrectAnswer(this.selectedOption, quiz.correctAnswer)

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
      skill_key: quiz.skillKey,
      quiz_type: quiz.type
    }

    this.onAnswer(this.toolCall.id, JSON.stringify(payload))

    // 异步更新连胜 (fire-and-forget; @Local 同步变更会立刻触发重渲染, 写盘在后台完成)
    this.updateStreak(quiz.skillKey, isCorrect)
  }

  private handleRetry(): void {
    // 只在"已提交但答错"时启用, 清除状态让小朋友换答案
    if (!this.showResult || this.isCorrect || this.isAnswered) {
      return
    }
    this.selectedOption = -1
    this.showResult = false
    this.isCorrect = false
    this.correctAnswerValue = 0
  }

  private async loadStreak(skillKey: string): Promise<void> {
    if (skillKey === '') {
      this.streakLoaded = true
      return
    }
    try {
      this.currentStreak = await ServiceRegistry.preferences().getNumber(
        PreferenceKeys.MATH_QUIZ_STREAK_CURRENT_PREFIX + skillKey,
        0
      )
      this.bestStreak = await ServiceRegistry.preferences().getNumber(
        PreferenceKeys.MATH_QUIZ_STREAK_BEST_PREFIX + skillKey,
        0
      )
    } catch (_e) {
      this.currentStreak = 0
      this.bestStreak = 0
    } finally {
      this.streakLoaded = true
    }
  }

  private async saveStreak(skillKey: string, current: number, best: number): Promise<void> {
    if (skillKey === '') {
      return
    }
    try {
      await ServiceRegistry.preferences().setNumber(
        PreferenceKeys.MATH_QUIZ_STREAK_CURRENT_PREFIX + skillKey,
        current
      )
      await ServiceRegistry.preferences().setNumber(
        PreferenceKeys.MATH_QUIZ_STREAK_BEST_PREFIX + skillKey,
        best
      )
    } catch (_e) {
      // 持久化失败不阻塞 UI
    }
  }

  private async updateStreak(skillKey: string, correct: boolean): Promise<void> {
    if (skillKey === '' || !this.streakLoaded) {
      return
    }
    if (!correct) {
      // 答错: 重置当前连胜, 最佳不变
      this.currentStreak = 0
      this.isNewBestStreak = false
      await this.saveStreak(skillKey, 0, this.bestStreak)
      return
    }
    const newCurrent = this.currentStreak + 1
    const isNewBest = newCurrent > this.bestStreak
    this.currentStreak = newCurrent
    this.bestStreak = Math.max(this.bestStreak, newCurrent)
    this.isNewBestStreak = isNewBest
    await this.saveStreak(skillKey, newCurrent, this.bestStreak)
  }

  private getOptionState(opt: string | number): string {
    if (!this.showResult && !this.isAnswered) {
      return this.selectedOption === opt ? 'selected' : 'default'
    }
    if (opt === this.quiz.correctAnswer) {
      return this.isCorrect ? 'correct' : 'revealed'
    }
    if (opt === this.selectedOption && !this.isCorrect) {
      return 'wrong'
    }
    return 'default'
  }

  private getOptionGradient(opt: string | number, index: number): LinearGradient {
    const state = this.getOptionState(opt)
    if (state === 'correct' || state === 'revealed') {
      return { angle: 180, colors: [['#22C55E', 0.0], [this.shadeHex('#22C55E', 0.7), 1.0]] }
    }
    if (state === 'wrong') {
      return { angle: 180, colors: [['#FF9F43', 0.0], [this.shadeHex('#FF9F43', 0.7), 1.0]] }
    }
    if (this.isDarkMode) {
      const top = this.themePrimary
      return { angle: 180, colors: [[top, 0.0], [this.shadeHex(top, 0.78), 1.0]] }
    }
    const variant = index % 3
    if (variant === 1) {
      return { angle: 180, colors: [['#FCD34D', 0.0], ['#D97706', 1.0]] }
    }
    if (variant === 2) {
      return { angle: 180, colors: [['#FBBF24', 0.0], ['#B45309', 1.0]] }
    }
    return { angle: 180, colors: [['#F59E0B', 0.0], ['#92400E', 1.0]] }
  }

  private getOptionBorderColor(opt: string | number, index: number): ResourceColor {
    const state = this.getOptionState(opt)
    if (state === 'correct' || state === 'revealed') {
      return '#16A34A'
    }
    if (state === 'wrong') {
      return '#E07A1F'
    }
    if (state === 'selected') {
      return this.themePrimary
    }
    if (this.isDarkMode) {
      return this.shadeHex(this.themePrimary, 0.5)
    }
    const variant = index % 3
    if (variant === 1) return '#D97706'
    if (variant === 2) return '#B45309'
    return '#92400E'
  }

  private getOptionBorderWidth(opt: string | number): number {
    const state = this.getOptionState(opt)
    if (state === 'selected') return 2.5
    if (state === 'correct' || state === 'revealed' || state === 'wrong') return 2
    return 1.5
  }

  private getOptionShadow(opt: string | number): ShadowOptions {
    const state = this.getOptionState(opt)
    if (state === 'selected') {
      return { radius: 12, color: '#1F000000', offsetY: 4 }
    }
    return { radius: 8, color: '#1F000000', offsetY: 2 }
  }

  private shadeHex(color: string, factor: number): string {
    if (!color.startsWith('#') || color.length !== 7) {
      return color
    }
    const r = parseInt(color.substring(1, 3), 16)
    const g = parseInt(color.substring(3, 5), 16)
    const b = parseInt(color.substring(5, 7), 16)
    const newR = Math.max(0, Math.min(255, Math.floor(r * factor)))
    const newG = Math.max(0, Math.min(255, Math.floor(g * factor)))
    const newB = Math.max(0, Math.min(255, Math.floor(b * factor)))
    const toHex = (n: number): string => {
      const h = n.toString(16)
      return h.length === 1 ? '0' + h : h
    }
    return `#${toHex(newR)}${toHex(newG)}${toHex(newB)}`
  }

  private getCardBackgroundColor(): string {
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12')
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
        this.StreakIndicator()
        if (this.isNewBestStreak) {
          Text('新纪录')
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor('#FF6B35')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
        } else if (this.isAnswered) {
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
  OptionButton(opt: string | number, index: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        Text(`${opt}`)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .shadow({ radius: 1, color: '#40000000', offsetY: 1 })
      }
      .width('100%')
      .height(64)
      .justifyContent(FlexAlign.Center)
      .linearGradient(this.getOptionGradient(opt, index))
      .borderRadius(14)
      .border({
        width: this.getOptionBorderWidth(opt),
        color: this.getOptionBorderColor(opt, index)
      })
      .shadow(this.getOptionShadow(opt))

      // 答对时, 在按钮右上角盖一颗星星印章
      if (this.showResult && this.isCorrect && opt === this.quiz.correctAnswer) {
        Text('🌟')
          .fontSize(20)
          .padding(6)
          .transition(
            TransitionEffect.scale({ x: 0, y: 0 })
              .combine(TransitionEffect.OPACITY)
              .animation({ duration: 250, curve: Curve.EaseOut })
          )
      }
    }
    .width('100%')
    .height(64)
    .onClick(() => {
      this.handleSelectOption(opt)
    })
    .animation({ duration: 150, curve: Curve.EaseOut })
  }

  @Builder
  ConfirmButton() {
    Row() {
      Text('确认')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
    }
    .width('100%')
    .height(40)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.themePrimary)
    .borderRadius(10)
    .onClick(() => {
      this.handleConfirm()
    })
    .animation({ duration: 150, curve: Curve.EaseOut })
  }

  @Builder
  StreakIndicator() {
    if (this.currentStreak > 0) {
      Text(`🔥 ${this.currentStreak}`)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.themePrimary)
        .margin({ right: 6 })
    } else if (this.bestStreak > 0) {
      Text(`🏆 最佳 ${this.bestStreak}`)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ right: 6 })
    }
  }

  @Builder
  QuizContent() {
    // 4 种题型分发: arithmetic (原算术) / shape (图形) / comparison (比较) / time (时间)
    if (this.quiz.type === 'shape') {
      this.ShapeContent()
    } else if (this.quiz.type === 'comparison') {
      this.ComparisonContent()
    } else if (this.quiz.type === 'time') {
      this.TimeContent()
    } else {
      this.ArithmeticContent()
    }
  }

  @Builder
  ArithmeticContent() {
    Column({ space: 10 }) {
      ForEach([this.quiz], (quiz: MathQuizQuestion) => {
        // 题目文字
        if (quiz.question !== '') {
          Text(quiz.question)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
        }

        // 算式: 拆成 number/op token, 数字大、运算符小, 视觉上更像算式而不是字符串
        if (quiz.expression !== '') {
          Row({ space: 4 }) {
            ForEach(tokenizeExpression(quiz.expression), (token: ExpressionToken) => {
              if (token.type === 'op') {
                Text(getOpDisplay(token.value))
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(withColorAlpha(this.themePrimary, '90'))
              } else {
                Text(token.value)
                  .fontSize(28)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.themePrimary)
              }
            }, (token: ExpressionToken, idx: number) => `tok_${idx}_${token.value}`)
            Text('=')
              .fontSize(22)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: 4 })
            Text('?')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.themePrimary)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 2, bottom: 2 })
        }

        // 选项按钮: 2 列 Grid 自动换行, 任意选项数都能整齐排列
        if (quiz.options.length > 0) {
          Column({ space: 10 }) {
            Grid() {
              ForEach(quiz.options, (opt: number, idx: number) => {
                GridItem() {
                  this.OptionButton(opt, idx)
                }
              }, (opt: number, idx: number) => `opt_${idx}_${opt}`)
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(10)
            .rowsGap(10)
            .width('100%')

            // 确认按钮: 选中后才出现
            if (this.selectedOption !== -1 && !this.showResult && !this.isAnswered) {
              this.ConfirmButton()
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

  // ---- 图形认知 (math_shapes) ----

  @Builder
  ShapePrimitive(shape: string) {
    // 圆/方/长方形用 ArkUI 原生; 其余用文字符号
    if (shape === 'circle') {
      Circle().width(48).height(48).fill(Color.White)
    } else if (shape === 'square') {
      Rect().width(48).height(48).fill(Color.White).radius(4)
    } else if (shape === 'rectangle') {
      Rect().width(64).height(36).fill(Color.White).radius(3)
    } else if (shape === 'triangle') {
      Text('△')
        .fontSize(46)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
    } else if (shape === 'pentagon') {
      Text('⬠')
        .fontSize(44)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
    } else if (shape === 'star') {
      Text('★')
        .fontSize(46)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
    } else if (shape === 'heart') {
      Text('♥')
        .fontSize(44)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
    } else {
      // 未知名 (LLM 幻觉) — 不渲染, 按钮仍可点
      Text('?')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
    }
  }

  @Builder
  ShapeOptionButton(shape: string, index: number) {
    Stack({ alignContent: Alignment.Center }) {
      this.ShapePrimitive(shape)
    }
    .width('100%')
    .height(72)
    .linearGradient(this.getOptionGradient(shape, index))
    .borderRadius(14)
    .border({
      width: this.getOptionBorderWidth(shape),
      color: this.getOptionBorderColor(shape, index)
    })
    .shadow(this.getOptionShadow(shape))
    .onClick(() => {
      this.handleSelectOption(shape)
    })
    .animation({ duration: 150, curve: Curve.EaseOut })
  }

  @Builder
  ShapeContent() {
    Column({ space: 10 }) {
      if (this.quiz.question !== '') {
        Text(this.quiz.question)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
      }

      if (this.quiz.options.length > 0) {
        Column({ space: 10 }) {
          Grid() {
            ForEach(this.quiz.options, (opt: string | number, idx: number) => {
              GridItem() {
                this.ShapeOptionButton(String(opt), idx)
              }
            }, (opt: string | number, idx: number) => `shape_${idx}_${opt}`)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .width('100%')

          if (this.selectedOption !== -1 && !this.showResult && !this.isAnswered) {
            this.ConfirmButton()
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getCardBackgroundColor())
    .borderRadius(10)
  }

  // ---- 大小比较 (math_comparison) ----

  @Builder
  OperatorButton(op: string) {
    Row() {
      Text(op)
        .fontSize(36)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .shadow({ radius: 1, color: '#40000000', offsetY: 1 })
    }
    .layoutWeight(1)
    .height(64)
    .justifyContent(FlexAlign.Center)
    .linearGradient(this.getOptionGradient(op, 0))
    .borderRadius(14)
    .border({
      width: this.getOptionBorderWidth(op),
      color: this.getOptionBorderColor(op, 0)
    })
    .shadow(this.getOptionShadow(op))
    .onClick(() => {
      this.handleSelectOption(op)
    })
    .animation({ duration: 150, curve: Curve.EaseOut })
  }

  @Builder
  ComparisonContent() {
    Column({ space: 12 }) {
      if (this.quiz.question !== '') {
        Text(this.quiz.question)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
      }

      // 中间表达式行: 左侧数字  〇  右侧数字
      Row({ space: 10 }) {
        Text(`${this.quiz.leftValue}`)
          .fontSize(42)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.themePrimary)
        Text(this.selectedOption !== -1 ? String(this.selectedOption) : '○')
          .fontSize(42)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.themePrimary)
        Text(`${this.quiz.rightValue}`)
          .fontSize(42)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.themePrimary)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // 运算符按钮行
      if (this.quiz.operatorOptions.length > 0) {
        Row({ space: 10 }) {
          ForEach(this.quiz.operatorOptions, (op: string | number) => {
            this.OperatorButton(String(op))
          }, (op: string | number) => `op_${op}`)
        }
        .width('100%')

        if (this.selectedOption !== -1 && !this.showResult && !this.isAnswered) {
          this.ConfirmButton()
        }
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getCardBackgroundColor())
    .borderRadius(10)
  }

  // ---- 时间认知 (math_time) ----

  @Builder
  TimeOptionButton(timeStr: string, index: number) {
    Stack({ alignContent: Alignment.Center }) {
      Text(timeStr)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .shadow({ radius: 1, color: '#40000000', offsetY: 1 })
    }
    .width('100%')
    .height(64)
    .linearGradient(this.getOptionGradient(timeStr, index))
    .borderRadius(14)
    .border({
      width: this.getOptionBorderWidth(timeStr),
      color: this.getOptionBorderColor(timeStr, index)
    })
    .shadow(this.getOptionShadow(timeStr))
    .onClick(() => {
      this.handleSelectOption(timeStr)
    })
    .animation({ duration: 150, curve: Curve.EaseOut })
  }

  @Builder
  TimeContent() {
    Column({ space: 10 }) {
      if (this.quiz.question !== '') {
        Text(this.quiz.question)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
      }

      if (this.quiz.options.length > 0) {
        Column({ space: 10 }) {
          Grid() {
            ForEach(this.quiz.options, (opt: string | number, idx: number) => {
              GridItem() {
                this.TimeOptionButton(String(opt), idx)
              }
            }, (opt: string | number, idx: number) => `time_${idx}_${opt}`)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .width('100%')

          if (this.selectedOption !== -1 && !this.showResult && !this.isAnswered) {
            this.ConfirmButton()
          }
        }
        .width('100%')
      }
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
          SymbolGlyph($r('sys.symbol.info_circle'))
            .fontSize(16)
            .fontColor(['#FF9F43'])
          Text(`答案是 ${this.correctAnswerValue}`)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FF9F43')
          if (!this.isAnswered) {
            Text('再试一次 ↻')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themePrimary)
              .margin({ left: 4 })
              .onClick(() => {
                this.handleRetry()
              })
          }
        }
        .width('100%')
      }
    } else if (this.isAnswered) {
      // 从 answeredPayload 中解析结果
      ForEach([parseMathQuizAnswer(this.answeredPayload)], (prev: MathQuizAnswerPayload | null) => {
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
              SymbolGlyph($r('sys.symbol.info_circle'))
                .fontSize(16)
                .fontColor(['#FF9F43'])
              Text(`答案是 ${prev.correct_answer}`)
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
