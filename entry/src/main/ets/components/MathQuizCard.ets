/**
 * MathQuizCard - 数学游戏互动卡片
 *
 * 解析 toolCall.arguments 中的数学题目参数, 以游戏化方式展示:
 * - 题目描述（口语化）
 * - 算式（如 "3 + 2 = ?"）
 * - 数字选项按钮（小朋友点选答案）
 * - 提交后即时反馈对错
 *
 * 视觉（2026-11-17 统一）: slot 内容对齐 math_teach 讲解板的儿童品牌风——
 * KidsBrandTokens 数学蓝淡底 + 暖白选项面 + 实线描边, 无渐变无阴影;
 * 恒定暖色绘本皮肤不随深色模式切换（与讲解板同契约）。外壳仍走 CardShell。
 *
 * 参考 AskUserCard 模式: @ComponentV2 + @Event onAnswer 回调
 */

import { ToolCall } from '../models/ChatModels'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import {
  KIDS_BORDER, KIDS_CHINESE_INK, KIDS_FG, KIDS_MATH, KIDS_MATH_INK, KIDS_MUTED, KIDS_SURFACE
} from './kids/KidsBrandTokens'
import { CardShell } from './cardshell/CardShell'
import { CardShellConfig } from './cardshell/CardShellTypes'
import { CardShellState } from './cardshell/CardShellState'
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
import { ColumnPaperLayout, parseChainExpression, computeColumnPaperLayout } from '../utils/MathColumnPaperLayout'
import { hashSeedFromString, shuffleQuizOptions, shuffleStringOptions } from '../utils/QuizOptionShuffle'
import { MathScratchSheet } from './mathQuiz/MathScratchSheet'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { PreferenceKeys } from '../services/PreferencesService'
import { ClockFaceView } from './mathTeach/ClockFaceView'

@ComponentV2
export struct MathQuizCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local quiz: MathQuizQuestion = {
    type: 'arithmetic', question: '', expression: '', correctAnswer: 0,
    options: [], skillKey: '', wordProblem: false, leftValue: 0, rightValue: 0, operatorOptions: [],
    clockHour: 0, clockMinute: 0,
    startHour: 0, startMinute: 0, endHour: 0, endMinute: 0
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

  // 两次机会流 (2026-10-15): 首次答错仅行内提示不提交, 第二次答错才揭示并回传。
  // submitCount = 本次提交序号 (1 起); wrongPicks = 已试错的选项 (保持红色 wrong 态)。
  @Local submitCount: number = 0
  @Local wrongPicks: string[] = []
  @Local showHint: boolean = false

  // 草稿纸 sheet: aboutToAppear 时按表达式解析一次 (null = 隐藏入口)
  @Local scratchLayout: ColumnPaperLayout | null = null
  @Local showScratchSheet: boolean = false

  @Local shellConfig: CardShellConfig = {
    title: '数学小游戏',
    subtitle: '',
    icon: $r('sys.symbol.checkmark'),
    stem: '',
    hasAudio: false,
    usesConfirm: true,
    feedbackTitleCorrect: '答对啦！真棒！',
    correctAnswerLabel: '正确答案'
  }
  private shellState: CardShellState = new CardShellState()

  aboutToAppear(): void {
    // 解析一次题目数据, 后续渲染直接读取 this.quiz, 避免在 build 路径反复 JSON.parse
    const parsed = parseMathQuiz(this.toolCall.arguments)
    // 选项顺序确定性洗牌: LLM 即使被告知「打乱顺序」也习惯把正确答案放第一个,
    // 渲染层强制按 toolCall.id 种子洗牌 (同一题每次渲染顺序稳定, 不随重渲染跳动)。
    const seed = hashSeedFromString(this.toolCall.id)
    parsed.options = shuffleQuizOptions(parsed.options, seed)
    parsed.operatorOptions = shuffleStringOptions(parsed.operatorOptions, seed)
    this.quiz = parsed
    // 如果是已回答状态, 从 answeredPayload 中恢复选中项和结果
    if (this.isAnswered) {
      const prev = parseMathQuizAnswer(this.answeredPayload)
      if (prev !== null) {
        this.selectedOption = prev.child_answer
        this.showResult = true
        this.isCorrect = prev.correct
        this.correctAnswerValue = prev.correct_answer
      } else {
        // payload 缺失/不可解析(如旧会话数据断链): 无法判定当时对错,
        // 抑制反馈横幅——否则默认 isCorrect=false 会把实际答对的题
        // 渲染成假「再试一次」(绿色揭示正确答案 + 红色横幅的矛盾组合)
        this.shellState.feedbackSuppressed = true
      }
    }
    // 异步加载连胜 (fire-and-forget, 由 streakLoaded 守卫竞态)
    this.loadStreak(this.quiz.skillKey)
    // 草稿纸可用性: 仅 +− 链式算术题可解析出竖式布局时显示入口 (wordProblem 泄题拒绝)
    this.scratchLayout = this.computeScratchLayout()

    // 重建外壳配置 (题面在 slot 内, stem 保持 '')
    this.shellConfig = {
      title: '数学小游戏',
      subtitle: '',
      icon: $r('sys.symbol.checkmark'),
      stem: '',
      hasAudio: false,
      usesConfirm: true,
      feedbackTitleCorrect: '答对啦！真棒！',
      correctAnswerLabel: '正确答案'
    }
    if (this.showResult) {
      this.shellState.submitted = true
      this.shellState.isCorrect = this.isCorrect
    }
    if (this.isAnswered) {
      this.shellState.headPill = '已回答'
      this.shellState.headPillColor = '#4CAF50'
    }
  }

  private handleSelectOption(option: string | number): void {
    if (this.isAnswered || this.showResult) {
      return
    }
    this.selectedOption = option
    this.shellState.hasSelection = true
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
    if (this.selectedOption === -1 || this.isAnswered || this.showResult) {
      return
    }

    const quiz = this.quiz
    const isCorrect = isCorrectAnswer(this.selectedOption, quiz.correctAnswer)
    this.submitCount += 1

    if (isCorrect) {
      // 答对 (任意次): 标准庆祝 + 回传 + 连胜 +1
      this.showResult = true
      this.isCorrect = true
      this.correctAnswerValue = quiz.correctAnswer
      this.shellState.submitted = true
      this.shellState.isCorrect = true
      this.showHint = false
      this.submitPayload(true)
      this.updateStreak(quiz.skillKey, true)
      return
    }

    // 第 1 次答错: 行内提示不提交不揭示, 清空选中让孩子换答案 (参考稿两次机会流)
    if (this.submitCount < 2) {
      this.wrongPicks.push(String(this.selectedOption))
      this.selectedOption = -1
      this.shellState.hasSelection = false
      this.showHint = true
      this.updateStreak(quiz.skillKey, false)
      return
    }

    // 第 2 次答错: 揭示正确答案 + 标准答错反馈 + 回传
    this.showResult = true
    this.isCorrect = false
    this.correctAnswerValue = quiz.correctAnswer
    this.shellState.submitted = true
    this.shellState.isCorrect = false
    this.showHint = false
    this.submitPayload(false)
    this.updateStreak(quiz.skillKey, false)
  }

  // 最终结果回传 (每次交互只回传一次; pending 在两次尝试期间由卡片持住)
  private submitPayload(correct: boolean): void {
    const quiz = this.quiz
    const payload: MathQuizAnswerPayload = {
      answered: true,
      child_answer: this.selectedOption,
      child_answer_valid: true,
      correct: correct,
      correct_answer: quiz.correctAnswer,
      expression: quiz.expression,
      question: quiz.question,
      skill_key: quiz.skillKey,
      quiz_type: quiz.type,
      attempts: this.submitCount,
      current_streak: this.currentStreak
    }

    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  // 草稿纸可用性: +− 链式算术题可解析出竖式布局时, 草稿纸额外提供「竖式计算」tab。
  // 返回 null 不代表没有草稿纸 (所有题型都有手写草稿), 只代表无可排竖式。
  // wordProblem 拒绝排竖式 (题干含答案语义, 摆竖式会泄题); × ÷ 题不排竖式。
  private computeScratchLayout(): ColumnPaperLayout | null {
    if (this.quiz.type !== 'arithmetic' || this.quiz.wordProblem || this.quiz.expression === '') {
      return null
    }
    const chain = parseChainExpression(this.quiz.expression)
    if (chain === null) {
      return null
    }
    return computeColumnPaperLayout(chain.nums, chain.ops)
  }

  // 草稿纸顶部的题目提示 (无竖式布局时显示; 有竖式时用 layout.expressionText)。
  // 应用题只显示题干 —— 隐藏的 expression 摆出来等于泄题。
  private scratchPromptText(): string {
    const quiz = this.quiz
    if (quiz.type === 'arithmetic') {
      return quiz.wordProblem ? quiz.question : (quiz.expression !== '' ? quiz.expression : quiz.question)
    }
    if (quiz.type === 'comparison') {
      return `${quiz.leftValue} ○ ${quiz.rightValue}`
    }
    if (quiz.type === 'time') {
      return quiz.question !== '' ? quiz.question : '现在是几点呀?'
    }
    if (quiz.type === 'elapsed_time') {
      return quiz.question !== '' ? quiz.question : '从开始到结束, 经过多久呀?'
    }
    return quiz.question
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
    this.showHint = false
    this.shellState.hasSelection = false
    this.shellState.submitted = false
    this.shellState.isCorrect = false
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
      this.syncHeadBadge()
      this.bestStreak = await ServiceRegistry.preferences().getNumber(
        PreferenceKeys.MATH_QUIZ_STREAK_BEST_PREFIX + skillKey,
        0
      )
      this.syncHeadBadge()
    } catch (_e) {
      this.currentStreak = 0
      this.syncHeadBadge()
      this.bestStreak = 0
      this.syncHeadBadge()
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
      this.syncHeadBadge()
      this.isNewBestStreak = false
      await this.saveStreak(skillKey, 0, this.bestStreak)
      return
    }
    const newCurrent = this.currentStreak + 1
    const isNewBest = newCurrent > this.bestStreak
    this.currentStreak = newCurrent
    this.syncHeadBadge()
    this.bestStreak = Math.max(this.bestStreak, newCurrent)
    this.syncHeadBadge()
    this.isNewBestStreak = isNewBest
    if (isNewBest) {
      this.shellState.headPill = '新纪录'
      this.shellState.headPillColor = '#FF6B35'
    }
    await this.saveStreak(skillKey, newCurrent, this.bestStreak)
  }

  // 连胜徽章同步到外壳 head: 当前连胜 > 0 显示 🔥 N, 否则最佳 > 0 显示 🏆 最佳 N, 否则不渲染
  private syncHeadBadge(): void {
    this.shellState.headBadge = this.currentStreak > 0
      ? `🔥 ${this.currentStreak}`
      : (this.bestStreak > 0 ? `🏆 最佳 ${this.bestStreak}` : '')
  }

  private getOptionState(opt: string | number): string {
    if (!this.showResult && !this.isAnswered) {
      if (this.selectedOption === opt) {
        return 'selected'
      }
      // 两次机会流: 已试错的选项保持红色 wrong 态 (换答案后仍可见)
      if (this.wrongPicks.indexOf(String(opt)) >= 0) {
        return 'wrong'
      }
      return 'default'
    }
    if (opt === this.quiz.correctAnswer) {
      return this.isCorrect ? 'correct' : 'revealed'
    }
    if (opt === this.selectedOption && !this.isCorrect) {
      return 'wrong'
    }
    return 'default'
  }

  // ---- 儿童品牌选项状态色（对齐 math_teach TenFrameBoard 练习选项，2026-11-17 视觉统一）----
  // 扁平暖白面 + 实线描边，无渐变无阴影；答错语文红、答对深绿、选中数学蓝。
  // 恒定暖色绘本皮肤，不随深色模式切换（KidsBrandTokens 契约，与讲解板一致）。

  private getOptionBackground(opt: string | number): string {
    const state = this.getOptionState(opt)
    if (state === 'correct' || state === 'revealed') {
      return withColorAlpha('#16704A', '12')
    }
    if (state === 'wrong') {
      return withColorAlpha(KIDS_CHINESE_INK, '12')
    }
    if (state === 'selected') {
      return withColorAlpha(KIDS_MATH, '14')
    }
    return KIDS_SURFACE
  }

  private getOptionBorderColor(opt: string | number): ResourceColor {
    const state = this.getOptionState(opt)
    if (state === 'correct' || state === 'revealed') {
      return '#16704A'
    }
    if (state === 'wrong') {
      return KIDS_CHINESE_INK
    }
    if (state === 'selected') {
      return KIDS_MATH_INK
    }
    return KIDS_BORDER
  }

  private getOptionTextColor(opt: string | number): string {
    const state = this.getOptionState(opt)
    if (state === 'correct' || state === 'revealed') {
      return '#16704A'
    }
    if (state === 'wrong') {
      return KIDS_CHINESE_INK
    }
    if (state === 'selected') {
      return KIDS_MATH_INK
    }
    return KIDS_FG
  }

  private getOptionBorderWidth(opt: string | number): number {
    const state = this.getOptionState(opt)
    if (state === 'selected' || state === 'correct' || state === 'revealed' || state === 'wrong') {
      return 2
    }
    return 1.5
  }

  private getCardBackgroundColor(): string {
    return withColorAlpha(KIDS_MATH, '0E')
  }

  build() {
    Stack() {
      CardShell({
        config: this.shellConfig,
        state: this.shellState,
        isAnswered: this.isAnswered,
        // showResult=true 才持有真实正确答案; answeredPayload 解析失败时保持 0, 传 '' 让
        // shell 跳过「正确答案」行 (CardShell 对 '' 不渲染该行), 与迁移前行为一致
        correctAnswerText: this.showResult ? String(this.correctAnswerValue) : '',
        onConfirm: (): void => { this.handleConfirm() },
        onRetry: (): void => { this.handleRetry() }
      }) {
        this.QuizContent()
      }

      // bindSheet 宿主: 零尺寸 Column 挂载 (custom 组件不能直接挂 bindSheet,
      // ProviderDetailSheet.UnifiedSheetHost 同款模式)
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showScratchSheet, this.ScratchSheetBuilder(), {
          height: SheetSize.LARGE,
          detents: [SheetSize.LARGE],
          dragBar: true,
          showClose: false,
          preferType: SheetType.BOTTOM
        })
    }
    .width('100%')
  }

  @Builder
  ScratchSheetBuilder() {
    MathScratchSheet({
      layout: this.scratchLayout,
      promptText: this.scratchPromptText(),
      onClose: (): void => {
        this.showScratchSheet = false
      }
    })
  }

  // 两次机会流: 第 1 次答错后的行内提示条 (不走 CardShell 标准反馈横幅)
  @Builder
  HintRow() {
    Row({ space: 6 }) {
      Text('💡')
        .fontSize(14)
      Text(this.scratchLayout !== null
        ? '再想想～ 可以点「草稿纸」列竖式试试'
        : '再想想～ 可以点「草稿纸」算一算试试')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(KIDS_MATH_INK)
    }
    .width('100%')
    .padding(10)
    .borderRadius(8)
    .backgroundColor(withColorAlpha(KIDS_MATH, '12'))
  }

  @Builder
  OptionButton(opt: string | number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        Text(`${opt}`)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getOptionTextColor(opt))
      }
      .width('100%')
      .height(64)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.getOptionBackground(opt))
      .borderRadius(12)
      .border({
        width: this.getOptionBorderWidth(opt),
        color: this.getOptionBorderColor(opt),
        radius: 12
      })

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
  QuizContent() {
    // 5 种题型分发: arithmetic (原算术+应用题) / shape (图形) / comparison (比较) / time (时间-读) / elapsed_time (时间-经过)
    if (this.quiz.type === 'shape') {
      this.ShapeContent()
    } else if (this.quiz.type === 'comparison') {
      this.ComparisonContent()
    } else if (this.quiz.type === 'time') {
      this.TimeContent()
    } else if (this.quiz.type === 'elapsed_time') {
      this.ElapsedTimeContent()
    } else {
      this.ArithmeticContent()
    }
    // 草稿纸入口: 所有 math_quiz 题型统一提供 (2026-11-14 起)。+− 链式算式可额外切到
    // 「竖式计算」tab (scratchLayout 非空); 应用题 / × ÷ / 图形 / 比较 / 时间只有手写草稿。
    // 应用题不显示算式 (只显示题干), 避免把隐藏的算式摆到孩子面前泄题。
    this.ScratchEntry()
    // 两次机会流: 第 1 次答错后的行内提示 (第 2 次答错走 shell 标准反馈)
    if (this.showHint && !this.showResult && !this.isAnswered) {
      this.HintRow()
    }
  }

  @Builder
  ScratchEntry() {
    if (!this.showResult && !this.isAnswered) {
      Row() {
        Row({ space: 6 }) {
          Text('✏️')
            .fontSize(14)
          Text('草稿纸')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(KIDS_MATH_INK)
        }
        .height(34)
        .padding({ left: 14, right: 14 })
        .borderRadius(17)
        .border({ width: 1.5, color: withColorAlpha(KIDS_MATH_INK, '66') })
        .backgroundColor(withColorAlpha(KIDS_MATH, '0D'))
        .onClick(() => {
          this.showScratchSheet = true
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  ArithmeticContent() {
    Column({ space: 10 }) {
      ForEach([this.quiz], (quiz: MathQuizQuestion) => {
        // 题目文字; 应用题模式下字号加大、加粗, 让小朋友看清楚场景描述
        if (quiz.question !== '') {
          Text(quiz.question)
            .fontSize(quiz.wordProblem ? 17 : 15)
            .fontWeight(quiz.wordProblem ? FontWeight.Medium : FontWeight.Normal)
            .lineHeight(quiz.wordProblem ? 24 : 22)
            .fontColor(KIDS_FG)
            .width('100%')
            .padding(quiz.wordProblem ? { top: 4, bottom: 6 } : { bottom: 2 })
        }

        // 算式: 应用题模式下隐藏 (只渲染场景描述, 让小朋友把语言翻译成算式)
        // 拆成 number/op token, 数字大、运算符小, 视觉上更像算式而不是字符串
        if (quiz.expression !== '' && !quiz.wordProblem) {
          Row({ space: 4 }) {
            ForEach(tokenizeExpression(quiz.expression), (token: ExpressionToken) => {
              if (token.type === 'op') {
                Text(getOpDisplay(token.value))
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(KIDS_MUTED)
              } else {
                Text(token.value)
                  .fontSize(28)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(KIDS_MATH_INK)
              }
            }, (token: ExpressionToken, idx: number) => `tok_${idx}_${token.value}`)
            Text('=')
              .fontSize(22)
              .fontWeight(FontWeight.Medium)
              .fontColor(KIDS_MUTED)
              .margin({ left: 4 })
            Text('?')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(KIDS_MATH_INK)
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
                  this.OptionButton(opt)
                }
              }, (opt: number, idx: number) => `opt_${idx}_${opt}`)
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(10)
            .rowsGap(10)
            .width('100%')
          }
          .width('100%')
        }
      }, (_: MathQuizQuestion) => 'quiz')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getCardBackgroundColor())
    .borderRadius(12)
    .border({ width: 1, color: withColorAlpha(KIDS_MATH, '30'), radius: 12 })
  }

  // ---- 图形认知 (math_shapes) ----

  @Builder
  ShapePrimitive(shape: string) {
    // 圆/方/长方形用 ArkUI 原生; 其余用文字符号。暖白面上统一数学蓝实心图形
    if (shape === 'circle') {
      Circle().width(48).height(48).fill(KIDS_MATH)
    } else if (shape === 'square') {
      Rect().width(48).height(48).fill(KIDS_MATH).radius(4)
    } else if (shape === 'rectangle') {
      Rect().width(64).height(36).fill(KIDS_MATH).radius(3)
    } else if (shape === 'triangle') {
      Text('△')
        .fontSize(46)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_MATH_INK)
    } else if (shape === 'pentagon') {
      Text('⬠')
        .fontSize(44)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_MATH_INK)
    } else if (shape === 'star') {
      Text('★')
        .fontSize(46)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_MATH_INK)
    } else if (shape === 'heart') {
      Text('♥')
        .fontSize(44)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_MATH_INK)
    } else {
      // 未知名 (LLM 幻觉) — 不渲染, 按钮仍可点
      Text('?')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_MUTED)
    }
  }

  @Builder
  ShapeOptionButton(shape: string) {
    Stack({ alignContent: Alignment.Center }) {
      this.ShapePrimitive(shape)
    }
    .width('100%')
    .height(72)
    .backgroundColor(this.getOptionBackground(shape))
    .borderRadius(12)
    .border({
      width: this.getOptionBorderWidth(shape),
      color: this.getOptionBorderColor(shape),
      radius: 12
    })
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
          .fontColor(KIDS_FG)
          .width('100%')
      }

      if (this.quiz.options.length > 0) {
        Column({ space: 10 }) {
          Grid() {
            ForEach(this.quiz.options, (opt: string | number, idx: number) => {
              GridItem() {
                this.ShapeOptionButton(String(opt))
              }
            }, (opt: string | number, idx: number) => `shape_${idx}_${opt}`)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .width('100%')
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getCardBackgroundColor())
    .borderRadius(12)
    .border({ width: 1, color: withColorAlpha(KIDS_MATH, '30'), radius: 12 })
  }

  // ---- 大小比较 (math_comparison) ----

  @Builder
  OperatorButton(op: string) {
    Row() {
      Text(op)
        .fontSize(36)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getOptionTextColor(op))
    }
    .layoutWeight(1)
    .height(64)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.getOptionBackground(op))
    .borderRadius(12)
    .border({
      width: this.getOptionBorderWidth(op),
      color: this.getOptionBorderColor(op),
      radius: 12
    })
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
          .fontColor(KIDS_FG)
          .width('100%')
      }

      // 中间表达式行: 左侧数字  〇  右侧数字
      Row({ space: 10 }) {
        Text(`${this.quiz.leftValue}`)
          .fontSize(42)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_MATH_INK)
        Text(this.selectedOption !== -1 ? String(this.selectedOption) : '○')
          .fontSize(42)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.selectedOption !== -1 ? KIDS_MATH_INK : KIDS_MUTED)
        Text(`${this.quiz.rightValue}`)
          .fontSize(42)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_MATH_INK)
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
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getCardBackgroundColor())
    .borderRadius(12)
    .border({ width: 1, color: withColorAlpha(KIDS_MATH, '30'), radius: 12 })
  }

  // ---- 时间认知 (math_time) ----

  @Builder
  TimeOptionButton(timeStr: string) {
    Stack({ alignContent: Alignment.Center }) {
      Text(timeStr)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getOptionTextColor(timeStr))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(64)
    .backgroundColor(this.getOptionBackground(timeStr))
    .borderRadius(12)
    .border({
      width: this.getOptionBorderWidth(timeStr),
      color: this.getOptionBorderColor(timeStr),
      radius: 12
    })
    .onClick(() => {
      this.handleSelectOption(timeStr)
    })
    .animation({ duration: 150, curve: Curve.EaseOut })
  }

  @Builder
  ClockFace(hour: number, minute: number, size: number = 216) {
    // size=216 (默认) time 题型钟面; size=120 给 elapsed_time 两钟面
    // 视觉复用 math_teach ClockBoard 的盘面（纯展示版 ClockFaceView，kids 品牌色）
    ClockFaceView({ hour: hour, minute: minute, box: size })
  }

  @Builder
  TimeContent() {
    Column({ space: 12 }) {
      Text(this.quiz.question !== '' ? this.quiz.question : '现在是几点呀?')
        .fontSize(15)
        .fontColor(KIDS_FG)
        .width('100%')

      // 钟面: 仅当 AI 传了有效 hour/minute 时渲染; 缺字段时退化到纯文字 question
      if (this.quiz.clockHour > 0) {
        Row() {
          this.ClockFace(this.quiz.clockHour, this.quiz.clockMinute)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }

      if (this.quiz.options.length > 0) {
        Column({ space: 10 }) {
          Grid() {
            ForEach(this.quiz.options, (opt: string | number, idx: number) => {
            GridItem() {
              this.TimeOptionButton(String(opt))
            }
          }, (opt: string | number, idx: number) => `time_${idx}_${opt}`)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .width('100%')
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getCardBackgroundColor())
    .borderRadius(12)
    .border({ width: 1, color: withColorAlpha(KIDS_MATH, '30'), radius: 12 })
  }

  // ---- 计时经过 (math_time, elapsed_time 子类型) ----
  // 复用 ClockFace (size=120) + TimeOptionButton: 两个钟面上下排列 + 中间箭头, 4 个时长按钮选项
  // 上下排列: 适配窄 bubble 宽度 (水平并排放不下 2 个 120vp+ 钟面)

  @Builder
  ElapsedTimeContent() {
    Column({ space: 10 }) {
      Text(this.quiz.question !== '' ? this.quiz.question : '从开始到结束, 经过多久呀?')
        .fontSize(15)
        .fontColor(KIDS_FG)
        .width('100%')

      // 两个钟面上下排列 + 中间 ↓ 箭头; 任意一个钟面有效即渲染
      if (this.quiz.startHour > 0 || this.quiz.endHour > 0) {
        // 开始钟面
        Column({ space: 4 }) {
          Text('开始')
            .fontSize(11)
            .fontColor(KIDS_MUTED)
          this.ClockFace(this.quiz.startHour, this.quiz.startMinute, 120)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        // 中间 ↓ 箭头 (上下钟面视觉连接)
        Text('↓')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_MATH_INK)
          .width('100%')
          .textAlign(TextAlign.Center)

        // 结束钟面
        Column({ space: 4 }) {
          Text('结束')
            .fontSize(11)
            .fontColor(KIDS_MUTED)
          this.ClockFace(this.quiz.endHour, this.quiz.endMinute, 120)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }

      // 时长选项 (4 个按钮, 沿用 TimeOptionButton 渲染 "X 小时 Y 分" 字符串)
      if (this.quiz.options.length > 0) {
        Column({ space: 10 }) {
          Grid() {
            ForEach(this.quiz.options, (opt: string | number, idx: number) => {
            GridItem() {
              this.TimeOptionButton(String(opt))
            }
          }, (opt: string | number, idx: number) => `elapsed_${idx}_${opt}`)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .width('100%')
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getCardBackgroundColor())
    .borderRadius(12)
    .border({ width: 1, color: withColorAlpha(KIDS_MATH, '30'), radius: 12 })
  }
}
