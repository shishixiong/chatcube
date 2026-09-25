// entry/src/main/ets/components/english/bodies/ReadAloudBody.ets
/**
 * ReadAloudBody - english_quiz v2 跟读评分 body
 * ASR 转写 → ReadAloudMatcher 归一化匹配; 命中自动提交, 未命中可无限重录, 放弃提交 correct=false。
 * 语音流程/权限降级复用原 EnglishQuizCard 语音路径。
 */

import { ToolCall } from '../../../models/ChatModels'
import { getAppUiState } from '../../../state/AppUiState'
import { withColorAlpha } from '../../../utils/ColorAlphaUtils'
import { CardShell } from '../../cardshell/CardShell'
import { CardShellConfig } from '../../cardshell/CardShellTypes'
import { CardShellState } from '../../cardshell/CardShellState'
import { ServiceRegistry } from '../../../services/ServiceRegistry'
import { SpeechRecognitionCallback } from '../../../services/SpeechRecognitionService'
import { common } from '@kit.AbilityKit'
import { isReadAloudMatch } from '../../../utils/ReadAloudMatcher'
import {
  EnglishQuizAnswerPayload, EnglishQuizModeArgs, parseEnglishQuizModeArgs
} from '../ModeTypes'

@ComponentV2
export struct ReadAloudBody {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local targetText: string = ''
  @Local phoneticHint: string = ''
  @Local question: string = ''
  @Local skillKey: string = 'english_reading'
  @Local stage: string = ''
  @Local isRecording: boolean = false
  @Local recognitionPreview: string = ''
  @Local lastHeard: string = ''
  @Local attemptFailed: boolean = false
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local inputText: string = ''
  @Local voicePermissionDenied: boolean = false
  @Local wasCancelled: boolean = false
  private shellConfig: CardShellConfig = {
    title: '跟我读', subtitle: '', icon: $r('sys.symbol.mic'),
    stem: '', hasAudio: false, usesConfirm: true, usesGiveUp: true,
    feedbackTitleCorrect: '读得真棒！', correctAnswerLabel: '目标句'
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
    this.targetText = args.targetText !== '' ? args.targetText : args.correctAnswer
    this.phoneticHint = args.phoneticHint
    this.question = args.question
    this.skillKey = args.skillKey
    this.stage = args.stage
    if (this.isAnswered) {
      const prev = this.parsePreviousAnswer()
      if (prev !== null) {
        this.lastHeard = prev.child_answer
        this.showResult = true
        this.isCorrect = prev.correct
        this.shellState.submitted = true
        this.shellState.isCorrect = prev.correct
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

  /** 匹配并提交 (命中或放弃或键盘提交共用); failed=false 表示命中 */
  private submitAttempt(childAnswer: string, correct: boolean): void {
    this.showResult = true
    this.isCorrect = correct
    this.shellState.submitted = true
    this.shellState.isCorrect = correct
    const payload: EnglishQuizAnswerPayload = {
      answered: true,
      child_answer: childAnswer,
      correct: correct,
      correct_answer: this.targetText,
      word: '',
      sentence: this.targetText,
      question_type: 'read_aloud',
      skill_key: this.skillKey,
      mode: 'read_aloud',
      stage: this.stage,
      target_text: this.targetText
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  /** ASR onResult(final): 命中 → 提交 correct=true; 未命中 → 记录 + 本地重试提示 */
  private evaluateAttempt(transcript: string): void {
    this.lastHeard = transcript
    if (isReadAloudMatch(transcript, this.targetText)) {
      this.submitAttempt(transcript, true)
    } else {
      this.attemptFailed = true
    }
  }

  private handleGiveUp(): void {
    if (this.isAnswered || this.showResult) {
      return
    }
    if (this.isRecording) {
      this.handleVoiceRecordCancel()
    }
    this.submitAttempt(this.lastHeard, false)
  }

  private handleTypedSubmit(): void {
    if (this.inputText.trim() === '' || this.isAnswered || this.showResult) {
      return
    }
    this.evaluateAttempt(this.inputText.trim())
  }

  // ===== 语音流程 (原 EnglishQuizCard handleVoiceRecord* 原样复用, 仅 onComplete 改调 evaluateAttempt) =====

  private handleVoiceRecordStart(): void {
    if (this.isRecording || this.isAnswered || this.showResult || this.voicePermissionDenied) {
      return
    }
    const speechService = ServiceRegistry.speechRecognition()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    speechService.checkPermission(context).then((granted: boolean) => {
      if (!granted) {
        this.voicePermissionDenied = true
        return
      }
      speechService.init().then(() => {
        this.isRecording = true
        this.recognitionPreview = ''
        const callback: SpeechRecognitionCallback = {
          onStart: () => {},
          onResult: (text: string, isFinal: boolean) => {
            if (isFinal) {
              this.recognitionPreview = text
            }
          },
          onComplete: (finalText: string) => {
            this.isRecording = false
            if (this.wasCancelled) {
              this.wasCancelled = false
              return
            }
            if (finalText.trim() !== '') {
              this.evaluateAttempt(finalText.trim())
            }
          },
          onCancel: () => {
            this.isRecording = false
          },
          onError: (code: number, message: string) => {
            this.isRecording = false
            console.error('ReadAloudBody', `Voice recognition error: ${code} ${message}`)
          }
        }
        speechService.startListening(callback)
      }).catch((err: Error) => {
        console.error('ReadAloudBody', `Failed to init speech: ${err.message}`)
      })
    })
  }

  private handleVoiceRecordFinish(): void {
    ServiceRegistry.speechRecognition().finishListening()
  }

  private handleVoiceRecordCancel(): void {
    ServiceRegistry.speechRecognition().cancelListening()
    this.isRecording = false
    this.wasCancelled = true
  }

  private getCardBackgroundColor(): string {
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12')
  }

  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: this.targetText,
      onConfirm: (): void => { this.handleTypedSubmit() },
      onRetry: (): void => {
        // 外壳「再试一次」仅键盘路径使用: 清输入, 不重复计分
        this.inputText = ''
        this.shellState.hasSelection = false
        this.shellState.submitted = false
        this.shellState.isCorrect = false
      },
      onGiveUp: (): void => { this.handleGiveUp() }
    }) {
      Column({ space: 10 }) {
        Text(this.question)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
        Text(this.targetText)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .textAlign(TextAlign.Center)
        if (this.phoneticHint !== '') {
          Text(`小提示: ${this.phoneticHint}`)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        if (this.attemptFailed && !this.showResult) {
          Text(`听到的是「${this.lastHeard}」, 再试一次!`)
            .fontSize(12)
            .fontColor('#FF6B6B')
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        if (!this.isAnswered && !this.showResult) {
          this.InputArea()
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.getCardBackgroundColor())
      .borderRadius(10)
    }
  }

  @Builder
  InputArea() {
    Column({ space: 8 }) {
      if (!this.voicePermissionDenied) {
        Row() {
          Button() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.mic'))
                .fontSize(16)
                .fontColor([Color.White])
              Text(this.isRecording ? '松开结束' : '按住说话')
                .fontSize(14)
                .fontColor(Color.White)
            }
          }
          .type(ButtonType.Normal)
          .height(40)
          .layoutWeight(1)
          .backgroundColor(this.isRecording ? '#FF6B6B' : this.themePrimary)
          .borderRadius(20)
          .onTouch((event: TouchEvent) => {
            if (this.isAnswered || this.showResult) {
              return
            }
            if (event.type === TouchType.Down) {
              this.handleVoiceRecordStart()
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              if (this.isRecording) {
                if (event.type === TouchType.Cancel) {
                  this.handleVoiceRecordCancel()
                } else {
                  this.handleVoiceRecordFinish()
                }
              }
            }
          })
        }
        .width('100%')
      } else {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.mic'))
            .fontSize(14)
            .fontColor([$r('app.color.text_tertiary')])
          Text('麦克风不可用 · 打字读出来也可以 ✏️')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .height(40)
        .justifyContent(FlexAlign.Center)
        .enabled(false)
      }
      if (this.isRecording && this.recognitionPreview !== '') {
        Text(`识别中: ${this.recognitionPreview}`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      }
      Row({ space: 8 }) {
        TextInput({ text: this.inputText, placeholder: '打不出来? 输入这句话...' })
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(10)
          .onChange((value: string) => {
            this.inputText = value
            this.shellState.hasSelection = value.trim() !== ''
          })
          .onSubmit(() => {
            this.handleTypedSubmit()
          })
      }
      .width('100%')
    }
    .width('100%')
  }
}
