/**
 * PictureVocabCard - 看图识词互动卡片
 *
 * 解析 toolCall.arguments 中的看图识词参数, 以游戏化方式展示:
 * - 图片（由 handlePictureVocab 注入 image_path, 或 AI 传入的 image 字段）
 * - 题目提示语（"What is this?" / "这是什么？"）
 * - 4 个选项按钮（小朋友点选答案）
 * - 提交后即时反馈对错
 *
 * 参考 MathQuizCard / EnglishQuizCard 模式: @ComponentV2 + @Event onAnswer 回调
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'

interface PictureVocabQuestion {
  mode: string
  imagePath: string
  imagePrompt: string
  correctAnswer: string
  options: string[]
  question: string
  difficulty: number
  skillKey: string
}

interface PictureVocabAnswerPayload {
  answered: boolean
  child_answer: string
  correct: boolean
  correct_answer: string
  mode: string
  skill_key: string
}

@ComponentV2
export struct PictureVocabCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local selectedOption: string = ''
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local displayImagePath: string = ''
  @Local isImageLoading: boolean = false
  @Local imageLoadFailed: boolean = false
  @Local quiz: PictureVocabQuestion = {
    mode: 'en',
    imagePath: '',
    imagePrompt: '',
    correctAnswer: '',
    options: [],
    question: '',
    difficulty: 1,
    skillKey: ''
  }

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
    this.quiz = this.parseQuiz()
    this.resolveImage()

    if (this.isAnswered && this.answeredPayload !== '') {
      try {
        const prev = JSON.parse(this.answeredPayload) as PictureVocabAnswerPayload
        if (prev.answered) {
          this.selectedOption = prev.child_answer ?? ''
          this.showResult = true
          this.isCorrect = prev.correct
        }
      } catch (e) {
        console.warn('PictureVocabCard', `failed to parse answeredPayload: ${JSON.stringify(e)}`)
      }
    }
  }

  private parseQuiz(): PictureVocabQuestion {
    const result: PictureVocabQuestion = {
      mode: 'en',
      imagePath: '',
      imagePrompt: '',
      correctAnswer: '',
      options: [],
      question: '',
      difficulty: 1,
      skillKey: ''
    }
    try {
      const parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      result.mode = (parsed['mode'] as string) ?? 'en'
      result.imagePath = (parsed['image_path'] as string) ?? (parsed['image'] as string) ?? ''
      result.imagePrompt = (parsed['image_prompt'] as string) ?? ''
      result.correctAnswer = (parsed['correct_answer'] as string) ?? ''
      const opts = parsed['options']
      if (opts instanceof Array) {
        const strings: string[] = []
        for (let i = 0; i < opts.length; i++) {
          strings.push(String(opts[i]))
        }
        result.options = strings
      }
      result.question = (parsed['question'] as string) ?? ''
      result.difficulty = (parsed['difficulty'] as number) ?? 1
      result.skillKey = (parsed['skill_key'] as string) ?? ''
    } catch (e) {
      console.error('PictureVocabCard', `parseQuiz failed: ${JSON.stringify(e)}`)
    }
    return result
  }

  private toFileUrl(path: string): string {
    if (path === '') {
      return ''
    }
    if (path.startsWith('file://') || path.startsWith('data:') ||
        path.startsWith('http://') || path.startsWith('https://')) {
      return path
    }
    return 'file://' + path
  }

  private resolveImage(): void {
    const quiz = this.quiz
    if (quiz.imagePath !== '') {
      this.displayImagePath = quiz.imagePath
      this.isImageLoading = false
      this.imageLoadFailed = false
    } else {
      this.isImageLoading = true
      this.imageLoadFailed = false
      try {
        const parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
        const imagePath = (parsed['image_path'] as string) ?? (parsed['image'] as string) ?? ''
        if (imagePath !== '') {
          this.displayImagePath = imagePath
          this.isImageLoading = false
          this.quiz.imagePath = imagePath
        }
      } catch (e) {
        console.warn('PictureVocabCard', `resolveImage re-check failed: ${JSON.stringify(e)}`)
      }
    }
  }

  private getQuestionText(): string {
    const quiz = this.quiz
    if (quiz.question !== '') {
      return quiz.question
    }
    if (quiz.mode === 'zh') {
      return '这是什么？'
    }
    return 'What is this?'
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
      const quiz = this.quiz
      if (opt === quiz.correctAnswer) {
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
      const quiz = this.quiz
      if (opt === quiz.correctAnswer || (opt === this.selectedOption && !this.isCorrect)) {
        return 3
      }
      return 1
    }
    return opt === this.selectedOption ? 3 : 1
  }

  private getOptionFontColor(opt: string): ResourceColor {
    if (this.showResult || this.isAnswered) {
      const quiz = this.quiz
      if (opt === quiz.correctAnswer) {
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
  }

  private handleConfirm(): void {
    if (this.selectedOption === '' || this.isAnswered || this.showResult) {
      return
    }

    const quiz = this.quiz
    const isCorrect = this.selectedOption === quiz.correctAnswer

    this.showResult = true
    this.isCorrect = isCorrect

    const payload: PictureVocabAnswerPayload = {
      answered: true,
      child_answer: this.selectedOption,
      correct: isCorrect,
      correct_answer: quiz.correctAnswer,
      mode: quiz.mode,
      skill_key: quiz.skillKey
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
  }

  build() {
    Column({ space: 10 }) {
      // 标题行
      Row() {
        SymbolGlyph($r('sys.symbol.translate'))
          .fontSize(18)
          .fontColor([this.themePrimary])
        Text(this.quiz.mode === 'zh' ? '看图识字' : '看图识词')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 6 })
      }
      .width('100%')

      // 题目提示语
      Text(this.getQuestionText())
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      // 图片区域
      this.ImageArea()

      // 选项按钮区域
      this.OptionsArea()

      // 确认按钮（选中后且未提交时显示）
      if (this.selectedOption !== '' && !this.showResult && !this.isAnswered) {
        this.ConfirmButton()
      }

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
  ImageArea() {
    if (this.displayImagePath !== '') {
      Image(this.toFileUrl(this.displayImagePath))
        .width('100%')
        .height(180)
        .objectFit(ImageFit.Contain)
        .borderRadius(10)
        .backgroundColor($r('app.color.surface'))
    } else if (this.isImageLoading) {
      Column() {
        LoadingProgress()
          .width(36)
          .height(36)
          .color($r('app.color.text_tertiary'))
        Text('图片加载中...')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 6 })
      }
      .width('100%')
      .height(180)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(10)
    } else {
      Column() {
        SymbolGlyph($r('sys.symbol.doc_plaintext'))
          .fontSize(32)
          .fontColor([$r('app.color.text_tertiary')])
        Text('图片准备中...')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 4 })
      }
      .width('100%')
      .height(180)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(10)
    }
  }

  @Builder
  OptionsArea() {
    if (this.quiz.options.length > 0) {
      Row({ space: 8 }) {
        ForEach(this.quiz.options, (opt: string, index: number) => {
          Column() {
            Text(opt)
              .fontSize(this.quiz.mode === 'zh' ? 32 : 22)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getOptionFontColor(opt))
          }
          .layoutWeight(1)
          .height(72)
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

  @Builder
  ConfirmButton() {
    Row() {
      Text('确认')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
    }
    .width('100%')
    .height(44)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.themePrimary)
    .borderRadius(10)
    .onClick(() => {
      this.handleConfirm()
    })
  }

  @Builder
  ResultFeedback() {
    Column({ space: 8 }) {
      if (this.isCorrect) {
        Row({ space: 6 }) {
          Text('🌟')
            .fontSize(22)
          Text('答对了！好厉害！')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.Green)
        }
        .width('100%')
      } else {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Text('💪')
              .fontSize(20)
            Text('再试试看～')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')

          Row({ space: 4 }) {
            Text('正确答案：')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Text(this.quiz.correctAnswer)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.Green)
          }
          .width('100%')

          if (!this.isAnswered) {
            Row() {
              Text('换一个答案')
                .fontSize(14)
                .fontColor(this.themePrimary)
            }
            .width('100%')
            .height(38)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(withColorAlpha(this.themePrimary, '1F'))
            .borderRadius(8)
            .onClick(() => {
              this.handleRetry()
            })
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor(withColorAlpha(this.isCorrect ? '#22C55E' : '#FF6B6B', '1A'))
    .borderRadius(8)
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
  }
}
