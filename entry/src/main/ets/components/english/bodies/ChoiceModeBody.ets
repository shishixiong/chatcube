// entry/src/main/ets/components/english/bodies/ChoiceModeBody.ets
/**
 * ChoiceModeBody - english_quiz v2 三种 4 选 1 mode 的共用 body
 * listen_choice: TTS 朗读 → 选听到的词 (需要 tts_text)
 * picture_word:  看图 → 选对应的词 (需要 image_prompt, 渲染图片区)
 * phonics_blend: TTS 朗读 → 选符合 phonics_rule 的词 (tts_text 缺省朗读 correct_answer)
 * 点选项即判即交; 授星走 english_quiz 既有分支 (correct=true → 1 星)。
 */

import { ToolCall } from '../../../models/ChatModels'
import { getAppUiState } from '../../../state/AppUiState'
import { withColorAlpha } from '../../../utils/ColorAlphaUtils'
import { CardShell } from '../../cardshell/CardShell'
import { CardShellConfig, CardShellCopy } from '../../cardshell/CardShellTypes'
import { CardShellState } from '../../cardshell/CardShellState'
import { ServiceRegistry } from '../../../services/ServiceRegistry'
import { common } from '@kit.AbilityKit'
import {
  EnglishQuizAnswerPayload, EnglishQuizMode, EnglishQuizModeArgs, modeDisplayName,
  parseEnglishQuizModeArgs
} from '../ModeTypes'
import { resolveQuizImagePath } from '../QuizImageResolver'

@ComponentV2
export struct ChoiceModeBody {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local mode: EnglishQuizMode = 'listen_choice'
  @Local question: string = ''
  @Local options: string[] = []
  @Local correctAnswer: string = ''
  @Local speakText: string = ''
  @Local showImage: boolean = false
  @Local displayImagePath: string = ''
  @Local isImageLoading: boolean = false
  @Local imageLoadFailed: boolean = false
  @Local selectedOption: string = ''
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local isPlayingSound: boolean = false
  @Local skillKey: string = 'english_vocab'
  @Local stage: string = ''
  private imageLoadTimer: number = -1
  private shellConfig: CardShellConfig = {
    title: '听音选词', subtitle: '', icon: $r('sys.symbol.speaker_wave_2_fill'),
    stem: '', hasAudio: false, usesConfirm: true,
    feedbackTitleCorrect: '答对啦！真棒！', correctAnswerLabel: '正确答案'
  }
  private shellState: CardShellState = new CardShellState()

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  aboutToAppear(): void {
    const args: EnglishQuizModeArgs = parseEnglishQuizModeArgs(this.toolCall.arguments)
    this.mode = args.mode
    this.question = args.question
    this.options = args.options
    this.correctAnswer = args.correctAnswer
    this.skillKey = args.skillKey
    this.stage = args.stage
    this.speakText = args.ttsText !== '' ? args.ttsText : args.correctAnswer
    this.showImage = args.mode === 'picture_word'
    this.shellConfig = {
      title: modeDisplayName(args.mode), subtitle: args.theme !== '' ? `主题 · ${args.theme}` : '',
      icon: this.showImage ? $r('sys.symbol.picture') : $r('sys.symbol.speaker_wave_2_fill'),
      stem: '', hasAudio: false, usesConfirm: true,
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
      }
    } else if (this.showImage) {
      this.resolveImage()
    }
  }

  aboutToDisappear(): void {
    if (this.imageLoadTimer >= 0) {
      clearTimeout(this.imageLoadTimer)
      this.imageLoadTimer = -1
    }
    if (this.isPlayingSound) {
      try {
        ServiceRegistry.tts().stop()
      } catch (_e) {}
      this.isPlayingSound = false
    }
  }

  // handleEnglishQuiz 异步注入 image_path 时主动刷新 (原卡 @Monitor 同款)
  @Monitor('toolCall.arguments')
  onArgumentsChanged(): void {
    if (this.isAnswered || !this.showImage) {
      return
    }
    const args = parseEnglishQuizModeArgs(this.toolCall.arguments)
    if (args.imagePath !== '' && args.imagePath !== this.displayImagePath) {
      this.displayImagePath = args.imagePath
      this.isImageLoading = false
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
    const args = parseEnglishQuizModeArgs(this.toolCall.arguments)
    if (args.imagePath !== '') {
      this.displayImagePath = args.imagePath
      return
    }
    this.isImageLoading = true
    this.imageLoadTimer = setTimeout(() => {
      if (this.isImageLoading && this.displayImagePath === '') {
        this.isImageLoading = false
        this.imageLoadFailed = true
      }
    }, 120000)
    resolveQuizImagePath(args.correctAnswer, '', args.imagePrompt).then((filePath: string) => {
      if (filePath !== '') {
        this.displayImagePath = filePath
      } else {
        this.imageLoadFailed = true
      }
      this.isImageLoading = false
      if (this.imageLoadTimer >= 0) {
        clearTimeout(this.imageLoadTimer)
        this.imageLoadTimer = -1
      }
    })
  }

  private handlePlaySound(): void {
    if (this.speakText === '' || this.isPlayingSound) {
      return
    }
    this.isPlayingSound = true
    ServiceRegistry.tts().speak(this.speakText, {
      onStart: () => {},
      onComplete: () => {
        this.isPlayingSound = false
      },
      onError: (error: string) => {
        this.isPlayingSound = false
        console.error('ChoiceModeBody', `TTS error: ${error}`)
      }
    }).catch((e: Error) => {
      this.isPlayingSound = false
      console.error('ChoiceModeBody', `TTS speak failed: ${e.message}`)
    })
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
      word: this.correctAnswer,
      sentence: '',
      question_type: this.mode,
      skill_key: this.skillKey,
      mode: this.mode,
      stage: this.stage
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private getCardBackgroundColor(): string {
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12')
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
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
        if (this.showImage) {
          this.ImageArea()
        }
        if (!this.showImage) {
          this.ListenButton()
        }
        Text(this.question)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
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
  ListenButton() {
    Button() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.speaker_wave_2_fill'))
          .fontSize(20)
          .fontColor([Color.White])
        Text(this.isPlayingSound ? CardShellCopy.PLAYING : CardShellCopy.REPLAY)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
      }
    }
    .type(ButtonType.Normal)
    .width('100%')
    .height(56)
    .backgroundColor(this.isPlayingSound ? '#FF9F43' : this.themePrimary)
    .borderRadius(28)
    .enabled(!this.isPlayingSound)
    .onClick(() => {
      this.handlePlaySound()
    })
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
      this.ImagePlaceholder('图片加载中...')
    } else if (this.imageLoadFailed) {
      this.ImagePlaceholder('图片加载失败')
    } else {
      this.ImagePlaceholder('准备中...')
    }
  }

  @Builder
  ImagePlaceholder(label: string) {
    Column() {
      SymbolGlyph($r('sys.symbol.doc_plaintext'))
        .fontSize(32)
        .fontColor([$r('app.color.text_tertiary')])
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 4 })
    }
    .width('100%')
    .height(120)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(10)
  }

  @Builder
  OptionsGrid() {
    Grid() {
      ForEach(this.options, (option: string, idx: number) => {
        GridItem() {
          Button(option)
            .fontSize(20)
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
