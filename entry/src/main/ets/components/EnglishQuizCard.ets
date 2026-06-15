/**
 * EnglishQuizCard - 英语看图说话互动卡片
 *
 * 解析 toolCall.arguments 中的英语题目参数, 以游戏化方式展示:
 * - 图片（本地生成的图片, 由组件内部通过 EnglishQuizImageIndex 异步加载）
 * - 提示文字（"看图说出英语单词" / "看图说出英语句子"）
 * - 语音输入按钮 + 文字输入框
 * - 提交后即时反馈对错
 *
 * 参考 MathQuizCard 模式: @ComponentV2 + @Event onAnswer 回调
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { SpeechRecognitionCallback } from '../services/SpeechRecognitionService'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { getEnglishQuizImageIndex } from '../services/EnglishQuizImageIndex'
import { common } from '@kit.AbilityKit'

interface EnglishQuizQuestion {
  word: string
  sentence: string
  imagePath: string
  imagePrompt: string
  correctAnswer: string
  questionType: string
  difficulty: number
  skillKey: string
  letterOptions: string[]    // phonics_choice 用: 3-4 个字母选项
  soundText: string           // phonics_choice 用: TTS 要朗读的字母音
}

interface EnglishQuizAnswerPayload {
  answered: boolean
  child_answer: string
  correct: boolean
  correct_answer: string
  word: string
  sentence: string
  question_type: string
  skill_key: string
  letter_options?: string[]
  sound_text?: string
}

@ComponentV2
export struct EnglishQuizCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local inputText: string = ''
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local correctAnswerText: string = ''
  @Local isRecording: boolean = false
  @Local recognitionPreview: string = ''
  // 麦克风权限被拒后, 隐藏语音按钮并展示键盘输入提示, 避免孩子反复点不出声音卡住
  @Local voicePermissionDenied: boolean = false
  // 标记本次语音会话已被 cancel / retry 重置, onComplete 收到时直接吞掉, 防止覆盖 retry 清空的状态
  @Local wasCancelled: boolean = false
  // 组件内部异步解析的图片路径, 不再依赖 handleEnglishQuiz 注入 image_path
  @Local resolvedImagePath: string = ''
  // 供 @Builder 直接读取的展示路径, 避免方法调用导致 V2 响应式追踪失效
  @Local displayImagePath: string = ''
  @Local isImageLoading: boolean = false
  @Local imageLoadFailed: boolean = false
  // ===== phonics_choice 题型专用状态 =====
  @Local letterOptions: string[] = []
  @Local soundText: string = ''
  @Local selectedLetter: string = ''         // 用户点击的字母, 用于反馈展示
  @Local isPlayingSound: boolean = false    // TTS 播放中
  private imageLoadTimer: number = -1

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
    // 如果是已回答状态, 从 answeredPayload 中恢复结果
    if (this.isAnswered) {
      const prev = this.parsePreviousAnswer()
      if (prev !== null) {
        this.inputText = prev.child_answer
        this.showResult = true
        this.isCorrect = prev.correct
        this.correctAnswerText = prev.correct_answer
        // phonics_choice: 恢复孩子选的字母
        if (prev.question_type === 'phonics_choice') {
          this.selectedLetter = prev.child_answer
        }
      }
    }

    // 读取 phonics_choice 题型字段 (letter_options / sound_text)
    const quiz = this.parseQuiz()
    if (quiz.questionType === 'phonics_choice') {
      this.letterOptions = quiz.letterOptions
      this.soundText = quiz.soundText
      // phonics_choice 不需要图片, 直接跳过整个 image 解析管线
      return
    }

    // 异步解析图片: 优先从 arguments 中已有的 image_path 读取,
    // 没有则通过 EnglishQuizImageIndex 查缓存/生成
    this.resolveImage()
  }

  // handleEnglishQuiz 在后台异步解析图片后注入 image_path 到 arguments,
  // 此时 ForEach 可能跳过 dirty mark 导致卡片不重渲染, 需要主动检测。
  // 注意: 不能简单用 resolvedImagePath !== '' 做 guard,
  // 因为 resolveImage 可能拿到的是过期的缓存路径 (文件已被系统清理),
  // 此时 handleEnglishQuiz 重新生成的新 image_path 会被错误跳过。
  @Monitor('toolCall.arguments')
  onArgumentsChanged(): void {
    if (this.isAnswered) {
      return
    }
    try {
      const parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      const imagePath = (parsed['image_path'] as string) ?? ''
      if (imagePath !== '' && imagePath !== this.displayImagePath) {
        this.resolvedImagePath = imagePath
        this.displayImagePath = imagePath
        this.isImageLoading = false
      }
    } catch (_e) {}
  }

  aboutToDisappear(): void {
    if (this.imageLoadTimer >= 0) {
      clearTimeout(this.imageLoadTimer)
      this.imageLoadTimer = -1
    }
    // 停止 TTS 朗读, 避免离开卡片后还在播
    if (this.isPlayingSound) {
      try {
        ServiceRegistry.tts().stop()
      } catch (_e) {}
      this.isPlayingSound = false
    }
  }

  /**
   * 将沙箱绝对路径转为 file:// URL, 供 Image 组件加载本地文件
   */
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

  /**
   * 异步解析图片路径:
   * 1. 先从 toolCall.arguments 的 image_path 读取 (handleEnglishQuiz 可能已注入)
   * 2. 没有则通过 EnglishQuizImageIndex 查缓存
   * 3. 缓存未命中则延迟 3s 后自行调用 generate (给 handleEnglishQuiz 优先权)
   * 4. 30s 超时兜底
   */
  private resolveImage(): void {
    const quiz = this.parseQuiz()

    // 已有 image_path (由 handleEnglishQuiz 注入或缓存命中)
    if (quiz.imagePath !== '') {
      this.resolvedImagePath = quiz.imagePath
      this.displayImagePath = quiz.imagePath
      console.info('EnglishQuizCard', `Image already resolved in arguments: ${quiz.imagePath}`)
      return
    }

    // 无需加载图片的场景 (没有 word/sentence 也没 imagePrompt)
    if (quiz.word === '' && quiz.sentence === '' && quiz.imagePrompt === '') {
      console.warn('EnglishQuizCard', 'No word, sentence, or imagePrompt in quiz data')
      return
    }

    // 开始异步加载: 先查缓存
    this.isImageLoading = true
    const word = quiz.word
    const sentence = quiz.sentence
    const imagePrompt = quiz.imagePrompt

    console.info('EnglishQuizCard',
      `Starting cache lookup: word="${word}", sentence="${sentence}", imagePrompt="${imagePrompt.substring(0, 60)}..."`)

    getEnglishQuizImageIndex().lookup(word, sentence).then((cached) => {
      if (cached !== null && cached.filePath !== '') {
        this.resolvedImagePath = cached.filePath
        this.displayImagePath = cached.filePath
        this.isImageLoading = false
        console.info('EnglishQuizCard', `Cache HIT: ${cached.filePath}`)
        return
      }
      // 缓存未命中: 等待 3s 给 handleEnglishQuiz 优先权, 然后自行生成
      console.info('EnglishQuizCard', 'Cache miss, will try generation in 3s as fallback')
      setTimeout(() => {
        // 检查 handleEnglishQuiz 是否已经解决了图片
        const currentQuiz = this.parseQuiz()
        if (currentQuiz.imagePath !== '') {
          this.resolvedImagePath = currentQuiz.imagePath
          this.displayImagePath = currentQuiz.imagePath
          this.isImageLoading = false
          console.info('EnglishQuizCard', `Image already injected by handleEnglishQuiz: ${currentQuiz.imagePath}`)
          return
        }
        if (this.resolvedImagePath !== '') {
          // 已经通过其他方式解决了
          this.isImageLoading = false
          return
        }
        // 自行生成
        if (imagePrompt !== '') {
          console.info('EnglishQuizCard', 'Starting fallback generation...')
          getEnglishQuizImageIndex().generate(word, sentence, imagePrompt).then((generated) => {
            if (generated !== null && generated.filePath !== '') {
              this.resolvedImagePath = generated.filePath
              this.displayImagePath = generated.filePath
              this.isImageLoading = false
              console.info('EnglishQuizCard', `Fallback generation SUCCESS: ${generated.filePath}`)
            } else {
              console.error('EnglishQuizCard', 'Fallback generation FAILED: generate() returned null')
              // 不立即设置 error, 给 handleEnglishQuiz 更多时间 (由 30s 超时处理)
            }
          }).catch((err: Error) => {
            console.error('EnglishQuizCard', `Fallback generation exception: ${err.message}`)
          })
        } else {
          console.warn('EnglishQuizCard', 'No imagePrompt available for generation')
        }
      }, 3000)

      // 启动 30s 超时定时器
      this.imageLoadTimer = setTimeout(() => {
        if (this.isImageLoading && this.resolvedImagePath === '') {
          const finalQuiz = this.parseQuiz()
          if (finalQuiz.imagePath === '') {
            console.error('EnglishQuizCard', 'Image load timed out after 30s - showing error state')
            this.isImageLoading = false
            this.imageLoadFailed = true
          } else {
            // handleEnglishQuiz 最终注入了路径
            this.resolvedImagePath = finalQuiz.imagePath
            this.displayImagePath = finalQuiz.imagePath
            this.isImageLoading = false
            console.info('EnglishQuizCard', `Image resolved at timeout check: ${finalQuiz.imagePath}`)
          }
        }
      }, 120000)
    }).catch((error: Error) => {
      console.error('EnglishQuizCard', `Cache lookup exception: ${error.message}`)
      // 不清除 isImageLoading, 给 handleEnglishQuiz 和 fallback generation 机会
    })
  }

  private parseQuiz(): EnglishQuizQuestion {
    const result: EnglishQuizQuestion = {
      word: '',
      sentence: '',
      imagePath: '',
      imagePrompt: '',
      correctAnswer: '',
      questionType: 'word',
      difficulty: 1,
      skillKey: 'english_vocab',
      letterOptions: [],
      soundText: ''
    }
    try {
      const parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      const questionType = (parsed['question_type'] as string) ?? 'word'
      const answer = (parsed['correct_answer'] as string) ?? ''
      if (answer !== '') {
        if (questionType === 'sentence') {
          result.sentence = answer
        } else if (questionType === 'phonics_choice') {
          // phonics_choice: correct_answer 是单个字母
          result.word = answer
        } else {
          result.word = answer
        }
      } else {
        // 兼容旧格式: correct_answer 为空时回退读 word/sentence
        result.word = (parsed['word'] as string) ?? ''
        result.sentence = (parsed['sentence'] as string) ?? ''
      }
      result.imagePath = (parsed['image_path'] as string) ?? ''
      result.imagePrompt = (parsed['image_prompt'] as string) ?? ''
      result.correctAnswer = (parsed['correct_answer'] as string) ?? ''
      result.questionType = (parsed['question_type'] as string) ?? 'word'
      result.difficulty = (parsed['difficulty'] as number) ?? 1
      result.skillKey = (parsed['skill_key'] as string) ?? 'english_vocab'
      result.letterOptions = (parsed['letter_options'] as string[]) ?? []
      result.soundText = (parsed['sound_text'] as string) ?? ''
    } catch (_e) {}
    return result
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

  /**
   * 判断答案是否正确
   * - 单词模式：忽略大小写和前后空格；允许编辑距离 ≤ 1 的拼写错误（aple→apple）
   * - 句子模式：忽略大小写 + 多余空格，每个词允许编辑距离 ≤ 1，匹配度 ≥ 50% 即正确
   *
   * 放宽理由：6-7 岁孩子拼写不稳定、容易漏掉虚词（a/an/the），80% 阈值过严。
   */
  private checkAnswer(childAnswer: string, correctAnswer: string, questionType: string): boolean {
    const child = childAnswer.trim().toLowerCase()
    const correct = correctAnswer.trim().toLowerCase()

    if (child === '' || correct === '') {
      return false
    }

    if (questionType === 'phonics_choice') {
      // 单字母点选: 忽略大小写完全匹配即可, 无需编辑距离
      return child === correct
    }

    if (questionType === 'word') {
      if (child === correct) {
        return true
      }
      // 单字符拼写错误宽容
      return this.levenshteinDistance(child, correct) <= 1
    }

    // 句子模式：分词后逐词匹配（允许编辑距离 ≤ 1）
    const childWords = child.split(/\s+/).filter((w: string): boolean => w.length > 0)
    const correctWords = correct.split(/\s+/).filter((w: string): boolean => w.length > 0)

    if (correctWords.length === 0) {
      return false
    }

    let matchCount = 0
    const usedIndices: Set<number> = new Set()
    for (let i = 0; i < childWords.length; i++) {
      for (let j = 0; j < correctWords.length; j++) {
        if (!usedIndices.has(j) && this.softWordEqual(childWords[i], correctWords[j])) {
          matchCount++
          usedIndices.add(j)
          break
        }
      }
    }

    const accuracy = matchCount / correctWords.length
    return accuracy >= 0.5
  }

  /**
   * 单词软匹配：完全相等 或 编辑距离 ≤ 1
   * - 长度差 > 1 时不可能 ≤ 1 编辑距离，直接 false
   */
  private softWordEqual(a: string, b: string): boolean {
    if (a === b) {
      return true
    }
    return this.levenshteinDistance(a, b) <= 1
  }

  /**
   * 编辑距离（Levenshtein）。长度差 > 1 时直接返回较大长度（剪枝）。
   * 仅用于 6-12 字符以内的英文单词匹配，2 行 DP 足够。
   */
  private levenshteinDistance(a: string, b: string): number {
    if (a === b) {
      return 0
    }
    const la = a.length
    const lb = b.length
    if (la === 0) {
      return lb
    }
    if (lb === 0) {
      return la
    }
    if (Math.abs(la - lb) > 1) {
      return Math.max(la, lb)
    }
    let prev: number[] = new Array(lb + 1)
    let curr: number[] = new Array(lb + 1)
    for (let j = 0; j <= lb; j++) {
      prev[j] = j
    }
    for (let i = 1; i <= la; i++) {
      curr[0] = i
      for (let j = 1; j <= lb; j++) {
        const cost = a[i - 1] === b[j - 1] ? 0 : 1
        const del = prev[j] + 1
        const ins = curr[j - 1] + 1
        const sub = prev[j - 1] + cost
        let min = del
        if (ins < min) {
          min = ins
        }
        if (sub < min) {
          min = sub
        }
        curr[j] = min
      }
      const tmp = prev
      prev = curr
      curr = tmp
    }
    return prev[lb]
  }

  private handleSubmit(): void {
    if (this.inputText.trim() === '' || this.isAnswered) {
      return
    }

    const quiz = this.parseQuiz()
    const correct = this.checkAnswer(this.inputText, quiz.correctAnswer, quiz.questionType)

    // 先显示即时反馈
    this.showResult = true
    this.isCorrect = correct
    this.correctAnswerText = quiz.correctAnswer

    // 构建 payload 回传
    const payload: EnglishQuizAnswerPayload = {
      answered: true,
      child_answer: this.inputText.trim(),
      correct: correct,
      correct_answer: quiz.correctAnswer,
      word: quiz.word,
      sentence: quiz.sentence,
      question_type: quiz.questionType,
      skill_key: quiz.skillKey
    }

    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private handleRetry(): void {
    // retry 是纯本地重置: AI 已收到第一次 onAnswer, 不再调 onAnswer, 避免重复计分。
    if (!this.showResult || this.isCorrect || this.isAnswered) {
      return
    }
    if (this.isRecording) {
      this.handleVoiceRecordCancel()
    }
    this.showResult = false
    this.isCorrect = false
    this.inputText = ''
    this.recognitionPreview = ''
    this.selectedLetter = ''
  }

  /**
   * phonics_choice: 用户点击字母按钮
   */
  private handleLetterSelect(letter: string): void {
    if (this.isAnswered || this.showResult) {
      return
    }
    const quiz = this.parseQuiz()
    if (quiz.questionType !== 'phonics_choice') {
      return
    }

    const correct = this.checkAnswer(letter, quiz.correctAnswer, quiz.questionType)

    this.selectedLetter = letter
    this.showResult = true
    this.isCorrect = correct
    this.correctAnswerText = quiz.correctAnswer

    const payload: EnglishQuizAnswerPayload = {
      answered: true,
      child_answer: letter.trim(),
      correct: correct,
      correct_answer: quiz.correctAnswer,
      word: '',
      sentence: '',
      question_type: quiz.questionType,
      skill_key: quiz.skillKey,
      letter_options: this.letterOptions,
      sound_text: this.soundText
    }

    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  /**
   * phonics_choice: 播放字母音
   */
  private handlePlaySound(): void {
    if (this.soundText === '' || this.isPlayingSound) {
      return
    }
    this.isPlayingSound = true
    ServiceRegistry.tts().speak(this.soundText, {
      onStart: () => {},
      onComplete: () => {
        this.isPlayingSound = false
      },
      onError: (error: string) => {
        this.isPlayingSound = false
        console.error('EnglishQuizCard', `TTS error: ${error}`)
      }
    }).catch((e: Error) => {
      this.isPlayingSound = false
      console.error('EnglishQuizCard', `TTS speak failed: ${e.message}`)
    })
  }

  private handleVoiceRecordStart(): void {
    if (this.isRecording || this.isAnswered || this.showResult || this.voicePermissionDenied) {
      return
    }

    const speechService = ServiceRegistry.speechRecognition()
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext

    speechService.checkPermission(context).then((granted: boolean) => {
      if (!granted) {
        // 权限被拒: 标记为降级, InputArea 会隐藏语音按钮并提示改用键盘, 不再静默 return
        this.voicePermissionDenied = true
        return
      }
      speechService.init().then(() => {
        this.isRecording = true
        this.recognitionPreview = ''
        const callback: SpeechRecognitionCallback = {
          onStart: () => {
            console.info('EnglishQuizCard', 'Voice recording started')
          },
          onResult: (text: string, isFinal: boolean) => {
            if (isFinal) {
              this.recognitionPreview = text
            }
          },
          onComplete: (finalText: string) => {
            this.isRecording = false
            // 防御 cancel 后引擎仍可能触发的延迟 onComplete, 避免覆盖 retry 重置的 inputText / 重复 submit
            if (this.wasCancelled) {
              this.wasCancelled = false
              return
            }
            if (finalText.trim() !== '') {
              this.inputText = finalText.trim()
              // 语音识别完成后直接提交答案
              this.handleSubmit()
            }
          },
          onCancel: () => {
            this.isRecording = false
          },
          onError: (code: number, message: string) => {
            this.isRecording = false
            console.error('EnglishQuizCard', `Voice recognition error: ${code} ${message}`)
          }
        }
        speechService.startListening(callback)
      }).catch((err: Error) => {
        console.error('EnglishQuizCard', `Failed to init speech: ${err.message}`)
      })
    })
  }

  private handleVoiceRecordFinish(): void {
    ServiceRegistry.speechRecognition().finishListening()
  }

  private handleVoiceRecordCancel(): void {
    ServiceRegistry.speechRecognition().cancelListening()
    this.isRecording = false
    // 引擎 cancel 后仍可能触发延迟 onComplete, 标记一下让 onComplete 吞掉, 防止 inputText 被覆盖
    this.wasCancelled = true
  }

  private getCardBackgroundColor(): string {
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12')
  }

  build() {
    Column({ space: 10 }) {
      // 标题行
      Row() {
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(14)
          .fontColor([this.themePrimary])
        Text(this.parseQuiz().questionType === 'phonics_choice' ? '自然拼读' : '英语小游戏')
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

      if (this.parseQuiz().questionType === 'phonics_choice') {
        // phonics_choice: 听音 + 字母选项
        this.PhonicsContent()

        // 字母选项网格 (未回答时)
        if (!this.isAnswered && !this.showResult) {
          this.LetterOptionsGrid()
        }

        // 结果反馈
        if (this.showResult || this.isAnswered) {
          this.ResultFeedback()
        }
      } else {
        // 现有 word / sentence 题型
        this.QuizContent()

        // 输入区域（未回答时）
        if (!this.isAnswered && !this.showResult) {
          this.InputArea()
        }

        // 结果反馈
        if (this.showResult || this.isAnswered) {
          this.ResultFeedback()
        }
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.themeAiBubble)
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  QuizContent() {
    Column({ space: 10 }) {
      // 图片区域: 直接读取 @Local displayImagePath, 确保 V2 响应式追踪生效
      if (this.displayImagePath !== '') {
        Image(this.toFileUrl(this.displayImagePath))
          .width('100%')
          .height(180)
          .objectFit(ImageFit.Contain)
          .borderRadius(10)
          .backgroundColor($r('app.color.surface'))
      } else if (this.isImageLoading) {
        // 正在异步加载图片中
        Column() {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(32)
            .fontColor([$r('app.color.text_tertiary')])
          Text('图片加载中...')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 4 })
        }
        .width('100%')
        .height(120)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(10)
      } else if (this.imageLoadFailed) {
        // 图片生成失败
        Column() {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(32)
            .fontColor([$r('app.color.text_tertiary')])
          Text('图片加载失败')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 4 })
        }
        .width('100%')
        .height(120)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(10)
      } else {
        // 初始状态: 尚未开始加载
        Column() {
          SymbolGlyph($r('sys.symbol.doc_plaintext'))
            .fontSize(32)
            .fontColor([$r('app.color.text_tertiary')])
          Text('准备中...')
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

      // 提示文字
      Text(this.parseQuiz().questionType === 'sentence' ? '看图说出英语句子' : '看图说出英语单词')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getCardBackgroundColor())
    .borderRadius(10)
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
        // 权限被拒降级提示: 显式告诉孩子「麦克风没开, 改用键盘也行」, 避免无声卡住
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.mic'))
            .fontSize(14)
            .fontColor([$r('app.color.text_tertiary')])
          Text('麦克风不可用 · 用键盘输入也可以 ✏️')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .height(40)
        .justifyContent(FlexAlign.Center)
        .enabled(false)
      }

      // 语音识别预览
      if (this.isRecording && this.recognitionPreview !== '') {
        Text(`识别中: ${this.recognitionPreview}`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      }

      // 文字输入框
      Row({ space: 8 }) {
        TextInput({ text: this.inputText, placeholder: '输入英语答案...' })
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(10)
          .onChange((value: string) => {
            this.inputText = value
          })
          .onSubmit(() => {
            this.handleSubmit()
          })

        Button('提交')
          .height(40)
          .padding({ left: 16, right: 16 })
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor(this.inputText.trim() !== '' ? this.themePrimary : $r('app.color.text_tertiary'))
          .enabled(this.inputText.trim() !== '')
          .borderRadius(10)
          .onClick(() => {
            this.handleSubmit()
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  ResultFeedback() {
    Column({ space: 6 }) {
      if (this.showResult) {
        if (this.isCorrect) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle'))
              .fontSize(16)
              .fontColor(['#4CAF50'])
            Text('Great job! 答对了!')
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
            Text(`正确答案是: ${this.correctAnswerText}`)
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
        ForEach([this.parsePreviousAnswer()], (prev: EnglishQuizAnswerPayload | null) => {
          if (prev !== null) {
            if (prev.correct) {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.checkmark_circle'))
                  .fontSize(16)
                  .fontColor(['#4CAF50'])
                Text('Great job! 答对了!')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#4CAF50')
              }
              .width('100%')
            } else {
              Column({ space: 4 }) {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.xmark_circle'))
                    .fontSize(16)
                    .fontColor(['#FF9F43'])
                  Text(`你的回答: ${prev.child_answer}`)
                    .fontSize(13)
                    .fontColor('#FF9F43')
                }
                .width('100%')
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.checkmark_circle'))
                    .fontSize(16)
                    .fontColor(['#4CAF50'])
                  Text(`正确答案: ${prev.correct_answer}`)
                    .fontSize(13)
                    .fontColor('#4CAF50')
                }
                .width('100%')
              }
              .width('100%')
            }
          }
        }, (_: EnglishQuizAnswerPayload | null) => 'result')
      }
    }
    .width('100%')
  }

  @Builder
  PhonicsContent() {
    Column({ space: 10 }) {
      // 🔊 大听音按钮: 孩子点一下就读字母音
      Button() {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.speaker_wave_2_fill'))
            .fontSize(20)
            .fontColor([Color.White])
          Text(this.isPlayingSound ? '播放中...' : '听一听')
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

      Text('听一听, 选出正确的字母')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.getCardBackgroundColor())
    .borderRadius(10)
  }

  @Builder
  LetterOptionsGrid() {
    Grid() {
      ForEach(this.letterOptions, (letter: string, idx: number) => {
        GridItem() {
          Button(letter.toUpperCase())
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .width('100%')
            .height(64)
            .backgroundColor(this.themePrimary)
            .borderRadius(12)
            .onClick(() => {
              this.handleLetterSelect(letter)
            })
        }
      }, (letter: string, idx: number) => `letter_${idx}_${letter}`)
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(10)
    .rowsGap(10)
    .width('100%')
  }
}
