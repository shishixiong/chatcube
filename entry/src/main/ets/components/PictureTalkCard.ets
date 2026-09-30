// entry/src/main/ets/components/PictureTalkCard.ets
/**
 * PictureTalkCard - 看图说话互动卡片（picture_talk 工具）
 *
 * 讲解型卡片: AI 生成场景图 → 孩子看图回答 1-3 个开放式问题（按住说话 ASR,
 * 麦克风不可用时打字兜底）→ 点「说好了 · 继续」提交 child_said 回执。
 * 无对错判定, 完成即授星 (computeStars: completed=true → 1 星)。
 * 提交后展示 sample 示范句, 供家长/老师对照。
 *
 * 图片注入: handlePictureTalk 异步生图后把 image_path 写回 toolCall.arguments,
 * 卡片经 @Monitor('toolCall.arguments') 刷新 (ChoiceModeBody 同款)。
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { CardShell } from './cardshell/CardShell'
import { CardShellConfig } from './cardshell/CardShellTypes'
import { CardShellState } from './cardshell/CardShellState'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { SpeechRecognitionCallback } from '../services/SpeechRecognitionService'
import { common } from '@kit.AbilityKit'
import { KIDS_MATH_INK, KIDS_MUTED } from './kids/KidsBrandTokens'

export interface PictureTalkResult {
  completed: boolean
  child_said: string
  skill_key: string
}

interface PictureTalkArgsView {
  valid: boolean
  imagePath: string
  scene: string
  questions: string[]
  words: string[]
  sample: string
  difficulty: number
  skillKey: string
}

function getStr(obj: Record<string, Object>, key: string, dflt: string): string {
  const v: Object | undefined = obj[key]
  if (typeof v === 'string') {
    return v as string
  }
  return dflt
}

function getNum(obj: Record<string, Object>, key: string, dflt: number): number {
  const v: Object | undefined = obj[key]
  if (typeof v === 'number') {
    const n: number = v as number
    if (!Number.isNaN(n)) {
      return n
    }
  }
  return dflt
}

function getStringArray(obj: Record<string, Object>, key: string): string[] {
  const out: string[] = []
  const raw: Object | undefined = obj[key]
  if (Array.isArray(raw)) {
    const arr = raw as Object[]
    for (let i = 0; i < arr.length; i++) {
      const v = arr[i]
      if (typeof v === 'string' && (v as string).trim() !== '') {
        out.push((v as string).trim())
      }
    }
  }
  return out
}

function createDefaultArgsView(): PictureTalkArgsView {
  const view: PictureTalkArgsView = {
    valid: false, imagePath: '', scene: '', questions: [], words: [],
    sample: '', difficulty: 1, skillKey: 'chinese_reading'
  }
  return view
}

export function parsePictureTalkArgs(raw: string): PictureTalkArgsView {
  const view: PictureTalkArgsView = createDefaultArgsView()
  try {
    const obj = JSON.parse(raw) as Record<string, Object>
    const scene = getStr(obj, 'scene', '')
    if (scene === '') {
      return view
    }
    view.valid = true
    view.imagePath = getStr(obj, 'image_path', '')
    view.scene = scene
    view.questions = getStringArray(obj, 'questions')
    view.words = getStringArray(obj, 'words')
    view.sample = getStr(obj, 'sample', '')
    view.difficulty = getNum(obj, 'difficulty', 1)
    const skillRaw = getStr(obj, 'skill_key', '')
    view.skillKey = skillRaw !== '' ? skillRaw : 'chinese_reading'
  } catch (_e) {
    return view
  }
  return view
}

@ComponentV2
export struct PictureTalkCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local argsView: PictureTalkArgsView = createDefaultArgsView()
  @Local displayImagePath: string = ''
  @Local isImageLoading: boolean = false
  @Local imageLoadFailed: boolean = false
  @Local childSaid: string = ''
  @Local isRecording: boolean = false
  @Local recognitionPreview: string = ''
  @Local voicePermissionDenied: boolean = false
  @Local wasCancelled: boolean = false
  @Local showSample: boolean = false

  private submitted: boolean = false
  private imageLoadTimer: number = -1
  private shellState: CardShellState = new CardShellState()
  private shellConfig: CardShellConfig = {
    title: '看图说话', subtitle: '', icon: $r('sys.symbol.picture'),
    stem: '', hasAudio: false, usesConfirm: false,
    feedbackTitleCorrect: '说得真棒！', correctAnswerLabel: ''
  }

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  aboutToAppear(): void {
    this.argsView = parsePictureTalkArgs(this.toolCall.arguments)
    this.refreshShellConfig()
    // 讲解型卡片无对错判定, 永久抑制反馈横幅 (MathTeachCard 同款)
    this.shellState.feedbackSuppressed = true
    if (this.isAnswered) {
      try {
        const prev = JSON.parse(this.answeredPayload) as Record<string, Object>
        const said = prev['child_said']
        if (typeof said === 'string') {
          this.childSaid = said as string
        }
        this.showSample = true
      } catch (_e) {
        this.showSample = false
      }
    } else if (this.argsView.valid) {
      if (this.argsView.imagePath !== '') {
        this.displayImagePath = this.argsView.imagePath
      } else {
        this.isImageLoading = true
        // 生图最长 ~2 分钟, 超时降级为无图继续说 (不阻塞活动)
        this.imageLoadTimer = setTimeout(() => {
          if (this.isImageLoading && this.displayImagePath === '') {
            this.isImageLoading = false
            this.imageLoadFailed = true
          }
        }, 120000)
      }
    }
  }

  aboutToDisappear(): void {
    if (this.imageLoadTimer >= 0) {
      clearTimeout(this.imageLoadTimer)
      this.imageLoadTimer = -1
    }
    if (this.isRecording) {
      try {
        ServiceRegistry.speechRecognition().cancelListening()
      } catch (_e) {}
      this.isRecording = false
    }
  }

  // handlePictureTalk 异步注入 image_path 时主动刷新 (ChoiceModeBody 同款)
  @Monitor('toolCall.arguments')
  onArgumentsChanged(): void {
    if (this.isAnswered) {
      return
    }
    const args = parsePictureTalkArgs(this.toolCall.arguments)
    if (args.imagePath !== '' && args.imagePath !== this.displayImagePath) {
      this.displayImagePath = args.imagePath
      this.isImageLoading = false
      this.imageLoadFailed = false
    }
  }

  private refreshShellConfig(): void {
    this.shellConfig = {
      title: '看图说话',
      subtitle: this.argsView.valid ? `难度 ${this.argsView.difficulty} · ${this.argsView.questions.length} 个问题` : '',
      icon: $r('sys.symbol.picture'),
      stem: '', hasAudio: false, usesConfirm: false,
      feedbackTitleCorrect: '说得真棒！', correctAnswerLabel: ''
    }
  }

  // ====== 语音流程 (ReadAloudBody 同款, 差异: 转写填入 childSaid 不自动判分) ======

  private handleVoiceRecordStart(): void {
    if (this.isRecording || this.isAnswered || this.voicePermissionDenied) {
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
              this.childSaid = finalText.trim()
            }
          },
          onCancel: () => {
            this.isRecording = false
          },
          onError: (code: number, message: string) => {
            this.isRecording = false
            console.error('PictureTalkCard', `Voice recognition error: ${code} ${message}`)
          }
        }
        speechService.startListening(callback)
      }).catch((err: Error) => {
        console.error('PictureTalkCard', `Failed to init speech: ${err.message}`)
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

  // ====== 提交 ======

  private canSubmit(): boolean {
    return this.childSaid.trim() !== ''
  }

  private submit(): void {
    if (this.submitted || !this.canSubmit() || this.isAnswered) {
      return
    }
    this.submitted = true
    const result: PictureTalkResult = {
      completed: true,
      child_said: this.childSaid.trim(),
      skill_key: this.argsView.skillKey
    }
    this.showSample = true
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
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

  private getCardBackgroundColor(): string {
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12')
  }

  // ====== 视图 ======

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
    .height(160)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(10)
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
      this.ImagePlaceholder('老师正在画图…')
    } else if (this.imageLoadFailed) {
      this.ImagePlaceholder('图片没画出来 · 看着题目说也可以')
    } else {
      this.ImagePlaceholder('准备中...')
    }
  }

  @Builder
  SceneSection() {
    Text(this.argsView.scene)
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
      .width('100%')
      .textAlign(TextAlign.Center)
  }

  @Builder
  QuestionsSection() {
    Column({ space: 6 }) {
      ForEach(this.argsView.questions, (q: string, idx: number) => {
        Row({ space: 8 }) {
          Text(`${idx + 1}`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor(this.themePrimary)
            .borderRadius(10)
            .width(20)
            .height(20)
            .textAlign(TextAlign.Center)
          Text(q)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (q: string, idx: number) => `q_${idx}_${q}`)
    }
    .width('100%')
    .padding(10)
    .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '12' : '0A'))
    .borderRadius(10)
  }

  @Builder
  WordsSection() {
    Column({ space: 6 }) {
      Text('可以用的词')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.argsView.words, (word: string) => {
          Text(word)
            .fontSize(14)
            .fontColor(this.themePrimary)
            .backgroundColor(withColorAlpha(this.themePrimary, '14'))
            .borderRadius(8)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .margin(3)
        }, (word: string) => `w_${word}`)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SaidArea() {
    Column({ space: 4 }) {
      Text('你说的')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      Text(this.childSaid)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(10)
    .borderRadius(10)
    .border({
      width: 1.5,
      color: withColorAlpha(this.themePrimary, this.isDarkMode ? '38' : '2C'),
      style: BorderStyle.Dashed
    })
  }

  @Builder
  InputArea() {
    Column({ space: 8 }) {
      if (!this.voicePermissionDenied) {
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
        .width('100%')
        .height(40)
        .backgroundColor(this.isRecording ? '#FF6B6B' : this.themePrimary)
        .borderRadius(20)
        .onTouch((event: TouchEvent) => {
          if (this.isAnswered) {
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
      } else {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.mic'))
            .fontSize(14)
            .fontColor([$r('app.color.text_tertiary')])
          Text('麦克风不可用 · 打字说也可以 ✏️')
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
      TextInput({ text: this.childSaid, placeholder: '打不出来? 把想说的话打出来...' })
        .width('100%')
        .height(40)
        .fontSize(15)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(10)
        .onChange((value: string) => {
          this.childSaid = value
        })
    }
    .width('100%')
  }

  @Builder
  SampleSection() {
    Column({ space: 4 }) {
      Text('老师想听到的话')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      Text(this.argsView.sample)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(10)
    .backgroundColor(withColorAlpha('#22C55E', this.isDarkMode ? '1A' : '10'))
    .borderRadius(10)
  }

  @Builder
  ControlArea() {
    if (this.isAnswered) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(14)
          .fontColor([$r('app.color.status_success')])
        Text('已说完')
          .fontSize(13)
          .fontColor($r('app.color.status_success'))
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    } else if (this.argsView.valid) {
      Column({ space: 4 }) {
        if (this.childSaid.trim() !== '') {
          this.SaidArea()
        }
        if (!this.canSubmit()) {
          Text('先按住说话, 说完松手')
            .fontSize(12)
            .fontColor(KIDS_MUTED)
        }
        Button('说好了 · 继续')
          .width('100%').height(44)
          .fontSize(15)
          .backgroundColor(this.canSubmit() ? KIDS_MATH_INK : withColorAlpha(KIDS_MATH_INK, '33'))
          .fontColor(Color.White)
          .enabled(this.canSubmit())
          .opacity(this.canSubmit() ? 1 : 0.55)
          .onClick(() => {
            this.submit()
          })
      }
      .width('100%')
    }
  }

  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: '',
      onConfirm: (): void => {},
      onRetry: (): void => {}
    }) {
      Column({ space: 10 }) {
        if (this.argsView.valid) {
          this.ImageArea()
          this.SceneSection()
          this.QuestionsSection()
          if (this.argsView.words.length > 0) {
            this.WordsSection()
          }
          if (!this.isAnswered) {
            this.InputArea()
          }
          if (this.showSample && this.argsView.sample !== '') {
            this.SampleSection()
          }
          this.ControlArea()
        } else {
          Text('这道讲解出错了，老师马上换一张')
            .fontSize(14).fontColor(KIDS_MUTED)
            .padding({ top: 8, bottom: 8 })
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.getCardBackgroundColor())
      .borderRadius(10)
    }
  }
}
