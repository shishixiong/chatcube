/**
 * ListeningQuizCard - 听力题互动卡片
 *
 * 解析 toolCall.arguments 中的听力题参数, 以游戏化方式展示:
 * - TTS 朗读区（aboutToAppear 自动播一次 + 重播按钮）
 * - 题目提示语（"听一听，是哪个单词？"）
 * - 4 个英文选项按钮（小朋友点选答案）
 * - 提交后即时反馈对错
 *
 * TTS 失败兜底: speak() reject / onError 时显示「显示文字」开关,
 * 家长可展开看到要听的词, 避免无可用引擎时题不可答。
 *
 * 参考 PictureVocabCard / EnglishQuizCard 模式: @ComponentV2 + @Event onAnswer 回调
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { ServiceRegistry } from '../services/ServiceRegistry'

interface ListeningQuizQuestion {
  word: string
  question: string
  correctAnswer: string
  options: string[]
  difficulty: number
  skillKey: string
  soundText: string
}

interface ListeningQuizAnswerPayload {
  answered: boolean
  child_answer: string
  correct: boolean
  correct_answer: string
  word: string
  skill_key: string
}

@ComponentV2
export struct ListeningQuizCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local selectedOption: string = ''
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local isPlayingSound: boolean = false
  // TTS 失败兜底: true 时显示「显示文字」入口
  @Local ttsFailed: boolean = false
  @Local showWordText: boolean = false
  @Local quiz: ListeningQuizQuestion = {
    word: '',
    question: '',
    correctAnswer: '',
    options: [],
    difficulty: 1,
    skillKey: '',
    soundText: ''
  }

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  aboutToAppear(): void {
    this.quiz = this.parseQuiz()

    if (this.isAnswered && this.answeredPayload !== '') {
      try {
        const prev = JSON.parse(this.answeredPayload) as ListeningQuizAnswerPayload
        if (prev.answered) {
          this.selectedOption = prev.child_answer ?? ''
          this.showResult = true
          this.isCorrect = prev.correct
        }
      } catch (e) {
        console.warn('ListeningQuizCard', `failed to parse answeredPayload: ${JSON.stringify(e)}`)
      }
      return
    }

    // 未作答时自动播放一次听力
    this.handlePlaySound()
  }

  aboutToDisappear(): void {
    if (this.isPlayingSound) {
      try {
        ServiceRegistry.tts().stop()
      } catch (_e) {}
      this.isPlayingSound = false
    }
  }

  private parseQuiz(): ListeningQuizQuestion {
    const result: ListeningQuizQuestion = {
      word: '',
      question: '',
      correctAnswer: '',
      options: [],
      difficulty: 1,
      skillKey: '',
      soundText: ''
    }
    try {
      const parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      result.word = (parsed['word'] as string) ?? ''
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
      result.skillKey = (parsed['skill_key'] as string) ?? 'english_vocab'
      // sound_text 可选, 缺省用 word
      const soundText = ((parsed['sound_text'] as string) ?? '').trim()
      result.soundText = soundText !== '' ? soundText : result.word
    } catch (e) {
      console.error('ListeningQuizCard', `parseQuiz failed: ${JSON.stringify(e)}`)
    }
    return result
  }

  private getQuestionText(): string {
    if (this.quiz.question !== '') {
      return this.quiz.question
    }
    return '听一听，是哪个单词？'
  }

  /**
   * 播放听力 (TTS)。失败时标记 ttsFailed, 展示「显示文字」兜底入口。
   */
  private handlePlaySound(): void {
    if (this.quiz.soundText === '' || this.isPlayingSound) {
      return
    }
    this.isPlayingSound = true
    this.ttsFailed = false
    ServiceRegistry.tts().speak(this.quiz.soundText, {
      onStart: () => {},
      onComplete: () => {
        this.isPlayingSound = false
      },
      onError: (error: string) => {
        this.isPlayingSound = false
        this.ttsFailed = true
        console.error('ListeningQuizCard', `TTS error: ${error}`)
      }
    }).catch((e: Error) => {
      this.isPlayingSound = false
      this.ttsFailed = true
      console.error('ListeningQuizCard', `TTS speak failed: ${e.message}`)
    })
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
  }

  private handleConfirm(): void {
    if (this.selectedOption === '' || this.isAnswered || this.showResult) {
      return
    }

    const isCorrect = this.selectedOption === this.quiz.correctAnswer

    this.showResult = true
    this.isCorrect = isCorrect

    const payload: ListeningQuizAnswerPayload = {
      answered: true,
      child_answer: this.selectedOption,
      correct: isCorrect,
      correct_answer: this.quiz.correctAnswer,
      word: this.quiz.word,
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
  }

  build() {
    Column({ space: 10 }) {
      // 标题行
      Row() {
        SymbolGlyph($r('sys.symbol.speaker_wave_2'))
          .fontSize(18)
          .fontColor([this.themePrimary])
        Text('听力题')
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

      // 播放区
      this.SoundArea()

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
  SoundArea() {
    Column({ space: 8 }) {
      Row() {
        Column() {
          if (this.isPlayingSound) {
            LoadingProgress()
              .width(30)
              .height(30)
              .color(Color.White)
          } else {
            SymbolGlyph($r('sys.symbol.speaker_wave_2'))
              .fontSize(30)
              .fontColor([Color.White])
          }
        }
        .width(64)
        .height(64)
        .borderRadius(32)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.themePrimary)
        .shadow({ radius: 4, color: '#20000000', offsetY: 2 })
        .onClick(() => {
          this.handlePlaySound()
        })
        .animation({ duration: 150, curve: Curve.EaseOut })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // 播放中提示 / 重播提示
      Text(this.isPlayingSound ? '正在播放...' : '点上面的按钮再听一遍')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))

      // TTS 失败兜底: 显示文字开关 (风险 R5)
      if (this.ttsFailed && !this.isAnswered && !this.showResult) {
        Column({ space: 6 }) {
          Text('声音播放失败')
            .fontSize(12)
            .fontColor($r('app.color.status_error'))
          Row() {
            Text(this.showWordText ? '隐藏文字' : '显示文字')
              .fontSize(14)
              .fontColor(this.themePrimary)
          }
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(withColorAlpha(this.themePrimary, '1F'))
          .borderRadius(8)
          .onClick(() => {
            this.showWordText = !this.showWordText
          })
        }
        .width('100%')
        .padding(8)
        .backgroundColor(withColorAlpha('#FF6B6B', '1A'))
        .borderRadius(8)

        if (this.showWordText) {
          Text(this.quiz.soundText)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .textAlign(TextAlign.Center)
        }
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(10)
  }

  @Builder
  OptionsArea() {
    if (this.quiz.options.length > 0) {
      Row({ space: 8 }) {
        ForEach(this.quiz.options, (opt: string, index: number) => {
          Column() {
            Text(opt)
              .fontSize(22)
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
          Text('听对了！好厉害！')
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
            Text('再听听看～')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')

          Row({ space: 4 }) {
            Text('听到的是：')
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
