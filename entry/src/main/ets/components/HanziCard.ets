/**
 * HanziCard - 汉字小课堂互动卡片（hanzi_card 工具）
 *
 * 讲解型卡片: 按六步识字法呈现一个汉字——大字认读、正音、字义、
 * 米字格笔顺动画（看笔顺）、组词、例句、字源、形近字对比。
 * 孩子点「看笔顺」看完逐笔动画后可点「我学会了 · 继续」提交完成回执。
 * 语音模式开启时 (AppStorage VOICE_MODE_ENABLED), 首次笔顺动画播完后
 * 自动口播讲解: 意义 → 词组 → 例句 → 字源小故事 (NumberBondBoard 旁白范式)。
 * 无对错判定, 完成即授星 (computeStars: completed=true → 1 星)。
 *
 * 参考 MathTeachCard (讲解回执) + HandwritingCard (笔顺 Canvas 动画) 模式。
 */

import { getAppUiState } from '../state/AppUiState'
import { ToolCall } from '../models/ChatModels'
import { getStrokeOrder, hasStrokeOrder, HandwritingStroke } from '../config/StrokeOrderData'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { CardShell } from './cardshell/CardShell'
import { CardShellConfig } from './cardshell/CardShellTypes'
import { CardShellState } from './cardshell/CardShellState'
import { KIDS_MATH_INK, KIDS_MUTED } from './kids/KidsBrandTokens'

export interface HanziCardResult {
  character: string
  skill_key: string
  completed: boolean
  watched_strokes: boolean
}

interface HanziCardLookalikeView {
  char: string
  pinyin: string
  note: string
}

interface HanziCardArgsView {
  valid: boolean
  character: string
  pinyin: string
  radical: string
  structure: string
  strokeCount: number
  meaning: string
  words: string[]
  sentence: string
  origin: string
  lookalikes: HanziCardLookalikeView[]
  difficulty: number
  skillKey: string
}

const TICK_MS: number = 33           // ~30fps
const FADE_PER_TICK: number = 0.05   // ~20 ticks to full alpha ≈ 660ms per stroke
const SVG_GRID: number = 1024        // hanzi-writer-data 网格尺寸
const SUCCESS_GREEN: string = '#22C55E'

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

function createDefaultArgsView(): HanziCardArgsView {
  const view: HanziCardArgsView = {
    valid: false, character: '', pinyin: '', radical: '', structure: '', strokeCount: 0,
    meaning: '', words: [], sentence: '', origin: '', lookalikes: [], difficulty: 1, skillKey: 'chinese_vocab'
  }
  return view
}

export function parseHanziCardArgs(raw: string): HanziCardArgsView {
  const view: HanziCardArgsView = createDefaultArgsView()
  try {
    const obj = JSON.parse(raw) as Record<string, Object>
    const character = getStr(obj, 'character', '')
    if (character.length !== 1 || !hasStrokeOrder(character)) {
      // 无笔顺数据的字无法播放动画, 走 invalid 兜底文案
      return view
    }
    view.valid = true
    view.character = character
    view.pinyin = getStr(obj, 'pinyin', '')
    view.radical = getStr(obj, 'radical', '')
    view.structure = getStr(obj, 'structure', '')
    view.strokeCount = getNum(obj, 'stroke_count', 0)
    view.meaning = getStr(obj, 'meaning', '')
    view.words = getStringArray(obj, 'words')
    view.sentence = getStr(obj, 'sentence', '')
    view.origin = getStr(obj, 'origin', '')
    const lookalikesRaw: Object | undefined = obj['lookalikes']
    if (Array.isArray(lookalikesRaw)) {
      const pairs = lookalikesRaw as Object[]
      for (let i = 0; i < pairs.length && i < 2; i++) {
        const item = pairs[i] as Record<string, Object>
        const c = getStr(item, 'char', '')
        if (c !== '') {
          const pair: HanziCardLookalikeView = {
            char: c,
            pinyin: getStr(item, 'pinyin', ''),
            note: getStr(item, 'note', '')
          }
          view.lookalikes.push(pair)
        }
      }
    }
    view.difficulty = getNum(obj, 'difficulty', 1)
    const skillRaw = getStr(obj, 'skill_key', '')
    view.skillKey = skillRaw !== '' ? skillRaw : 'chinese_vocab'
  } catch (_e) {
    return view
  }
  return view
}

@ComponentV2
export struct HanziCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local argsView: HanziCardArgsView = createDefaultArgsView()
  @Local strokes: HandwritingStroke[] = []
  // 笔顺动画状态 (HandwritingCard demo canvas 同款)
  @Local isPlaying: boolean = false
  @Local currentStrokeIdx: number = -1
  @Local currentStrokeAlpha: number = 0
  @Local playedStrokeCount: number = 0
  @Local hasWatchedStrokes: boolean = false

  private submitted: boolean = false
  private narrationDone: boolean = false
  private shellState: CardShellState = new CardShellState()
  private shellConfig: CardShellConfig = {
    title: '汉字小课堂', subtitle: '', icon: $r('sys.symbol.character'),
    stem: '', hasAudio: false, usesConfirm: false,
    feedbackTitleCorrect: '学会啦！', correctAnswerLabel: ''
  }
  private animTimerId: number = -1
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true))
  private demoCanvasWidth: number = 0
  private demoCanvasHeight: number = 0

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get strokeDescColor(): string {
    return this.isDarkMode ? '#FBBF24' : '#b45309'
  }

  aboutToAppear(): void {
    this.argsView = parseHanziCardArgs(this.toolCall.arguments)
    if (this.argsView.valid) {
      const localStrokes = getStrokeOrder(this.argsView.character)
      this.strokes = localStrokes !== null ? localStrokes : []
    }
    const char = this.argsView.character
    this.shellConfig = {
      title: '汉字小课堂',
      subtitle: char !== '' ? `${char} · ${this.argsView.structure} · ${this.argsView.strokeCount} 画 · 部首 ${this.argsView.radical}` : '',
      icon: $r('sys.symbol.character'),
      stem: '', hasAudio: false, usesConfirm: false,
      feedbackTitleCorrect: '学会啦！', correctAnswerLabel: ''
    }
    // 讲解型卡片无对错判定, 永久抑制反馈横幅 (MathTeachCard 同款)
    this.shellState.feedbackSuppressed = true
    if (this.isAnswered) {
      try {
        const prev = JSON.parse(this.answeredPayload) as Record<string, Object>
        const watched = prev['watched_strokes']
        this.hasWatchedStrokes = watched === true
      } catch (_e) {
        this.hasWatchedStrokes = false
      }
    }
  }

  aboutToDisappear(): void {
    this.stopPlayback()
    // 离开页面/卡片回收时停掉未播完的讲解旁白 (PinyinCard 同语义)
    try {
      ServiceRegistry.tts().stop()
    } catch (_e) {
    }
  }

  // ====== 笔顺动画 (HandwritingCard demo canvas 同款机制) ======

  private startPlayback(): void {
    if (this.strokes.length === 0 || this.demoCanvasWidth === 0 || this.demoCanvasHeight === 0) {
      return
    }
    this.stopPlayback()
    this.isPlaying = true
    this.currentStrokeIdx = 0
    this.currentStrokeAlpha = 0
    this.playedStrokeCount = 0
    this.animTimerId = setInterval((): void => this.tick(), TICK_MS)
  }

  private stopPlayback(): void {
    if (this.animTimerId !== -1) {
      clearInterval(this.animTimerId)
      this.animTimerId = -1
    }
    this.isPlaying = false
  }

  private tick(): void {
    if (this.currentStrokeIdx < 0 || this.currentStrokeIdx >= this.strokes.length) {
      this.stopPlayback()
      this.currentStrokeIdx = -1
      this.redrawDemoCanvas()
      // 动画播完 → 语音讲解后续内容 (意义/词组/例句/字源小故事)
      this.narrateLessonAfterStrokes()
      return
    }
    this.currentStrokeAlpha += FADE_PER_TICK
    if (this.currentStrokeAlpha >= 1) {
      this.playedStrokeCount = this.currentStrokeIdx + 1
      this.currentStrokeIdx += 1
      this.currentStrokeAlpha = 0
    }
    this.redrawDemoCanvas()
  }

  private redrawDemoCanvas(): void {
    const ctx = this.canvasContext
    const w = this.demoCanvasWidth
    const h = this.demoCanvasHeight
    if (w === 0 || h === 0) {
      return
    }
    ctx.clearRect(0, 0, w, h)

    // 1. 米字格底 (虚线外框 + 对角线 + 十字)
    this.drawGrid(ctx, w, h)

    const scale = Math.min(w, h) / SVG_GRID
    const offsetX = (w - SVG_GRID * scale) / 2
    const offsetY = (h - SVG_GRID * scale) / 2

    // 2. 已完成的笔画 (深色)
    ctx.fillStyle = this.strokeDescColor
    const playedEnd = Math.min(this.playedStrokeCount, this.strokes.length)
    for (let i = 0; i < playedEnd; i++) {
      ctx.beginPath()
      this.drawSvgPath(ctx, this.strokes[i].path, scale, offsetX, offsetY)
      ctx.fill()
    }

    // 3. 当前笔画 (绿色, 淡入)
    if (this.currentStrokeIdx >= 0 && this.currentStrokeIdx < this.strokes.length) {
      ctx.fillStyle = SUCCESS_GREEN
      ctx.globalAlpha = Math.max(0, Math.min(1, this.currentStrokeAlpha))
      ctx.beginPath()
      this.drawSvgPath(ctx, this.strokes[this.currentStrokeIdx].path, scale, offsetX, offsetY)
      ctx.fill()
      ctx.globalAlpha = 1
    }
  }

  private drawGrid(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    ctx.strokeStyle = withColorAlpha(KIDS_MUTED, '40')
    ctx.lineWidth = 1
    ctx.setLineDash([6, 5])
    // 外框
    ctx.beginPath()
    ctx.rect(1, 1, w - 2, h - 2)
    ctx.stroke()
    // 十字
    ctx.beginPath()
    ctx.moveTo(w / 2, 1)
    ctx.lineTo(w / 2, h - 1)
    ctx.moveTo(1, h / 2)
    ctx.lineTo(w - 1, h / 2)
    ctx.stroke()
    // 对角线
    ctx.beginPath()
    ctx.moveTo(1, 1)
    ctx.lineTo(w - 1, h - 1)
    ctx.moveTo(w - 1, 1)
    ctx.lineTo(1, h - 1)
    ctx.stroke()
    ctx.setLineDash([])
  }

  // 解析 SVG path 并执行到 Canvas 上下文 (M/Q/L/C/Z; Y-up → Y-down 翻转)
  private drawSvgPath(ctx: CanvasRenderingContext2D, path: string, scale: number, offsetX: number, offsetY: number): void {
    const tokens = path.match(/[MQLCZmqlcz]|-?\d+\.?\d*/g)
    if (tokens === null || tokens.length === 0) {
      return
    }
    let i = 0
    while (i < tokens.length) {
      const cmd = tokens[i]
      i += 1
      if (cmd === 'M' || cmd === 'm') {
        const x = parseFloat(tokens[i]) * scale + offsetX
        const y = (SVG_GRID - parseFloat(tokens[i + 1])) * scale + offsetY
        ctx.moveTo(x, y)
        i += 2
      } else if (cmd === 'Q' || cmd === 'q') {
        const cx = parseFloat(tokens[i]) * scale + offsetX
        const cy = (SVG_GRID - parseFloat(tokens[i + 1])) * scale + offsetY
        const x = parseFloat(tokens[i + 2]) * scale + offsetX
        const y = (SVG_GRID - parseFloat(tokens[i + 3])) * scale + offsetY
        ctx.quadraticCurveTo(cx, cy, x, y)
        i += 4
      } else if (cmd === 'C' || cmd === 'c') {
        const cx1 = parseFloat(tokens[i]) * scale + offsetX
        const cy1 = (SVG_GRID - parseFloat(tokens[i + 1])) * scale + offsetY
        const cx2 = parseFloat(tokens[i + 2]) * scale + offsetX
        const cy2 = (SVG_GRID - parseFloat(tokens[i + 3])) * scale + offsetY
        const x = parseFloat(tokens[i + 4]) * scale + offsetX
        const y = (SVG_GRID - parseFloat(tokens[i + 5])) * scale + offsetY
        ctx.bezierCurveTo(cx1, cy1, cx2, cy2, x, y)
        i += 6
      } else if (cmd === 'L' || cmd === 'l') {
        const x = parseFloat(tokens[i]) * scale + offsetX
        const y = (SVG_GRID - parseFloat(tokens[i + 1])) * scale + offsetY
        ctx.lineTo(x, y)
        i += 2
      } else if (cmd === 'Z' || cmd === 'z') {
        ctx.closePath()
      }
    }
  }

  // ====== 讲解旁白 (NumberBondBoard.speakStep 同范式) ======

  private isVoiceEnabled(): boolean {
    return AppStorage.get<number>(AppStorageKeys.VOICE_MODE_ENABLED) === 1
  }

  // 笔顺后的口播内容：意义 → 词组 → 例句 → 字源小故事(可选)
  private buildLessonNarrationText(): string {
    let text = ''
    if (this.argsView.character !== '') {
      text += this.argsView.character + '，'
    }
    if (this.argsView.meaning.trim() !== '') {
      text += '意思是' + this.argsView.meaning.trim() + '。'
    }
    if (this.argsView.words.length > 0) {
      text += '可以组成' + this.argsView.words.join('、') + '。'
    }
    if (this.argsView.sentence.trim() !== '') {
      text += '例句：' + this.argsView.sentence.trim() + '。'
    }
    if (this.argsView.origin.trim() !== '') {
      text += '字源小故事：' + this.argsView.origin.trim()
    }
    return text.trim()
  }

  // 只在首次看笔顺的动画播完后讲一次; 复看与历史回放不重复播
  private narrateLessonAfterStrokes(): void {
    if (this.narrationDone || this.isAnswered || !this.isVoiceEnabled()) {
      return
    }
    const text = this.buildLessonNarrationText()
    if (text === '') {
      return
    }
    this.narrationDone = true
    // 旁白接管所有在播语音, 让孩子听到的是刚看完笔顺的这一段
    try {
      ServiceRegistry.tts().stop()
    } catch (_e) {
    }
    ServiceRegistry.tts().speak(text, {
      onStart: () => {},
      onComplete: () => {},
      onError: (error: string) => {
        console.error('HanziCard', `lesson narration TTS error: ${error}`)
      }
    }).catch((e: Error) => {
      console.error('HanziCard', `lesson narration TTS speak failed: ${e.message}`)
    })
  }

  // ====== 提交 ======

  private handleWatch(): void {
    if (this.hasWatchedStrokes) {
      // 复看: 重播动画但不重复计分
      this.startPlayback()
      return
    }
    this.hasWatchedStrokes = true
    this.startPlayback()
  }

  private canSubmit(): boolean {
    return this.hasWatchedStrokes
  }

  private submit(): void {
    if (this.submitted || !this.canSubmit() || this.isAnswered) {
      return
    }
    this.submitted = true
    // 提交后旁白已过时, 停掉让位给 AI 的衔接语 (NumberBondBoard.goPrev 同语义)
    try {
      ServiceRegistry.tts().stop()
    } catch (_e) {
    }
    const result: HanziCardResult = {
      character: this.argsView.character,
      skill_key: this.argsView.skillKey,
      completed: true,
      watched_strokes: true
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
  }

  @Builder
  CharHeader() {
    Column({ space: 6 }) {
      Text(this.argsView.pinyin)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.themePrimary)
      Text(this.argsView.character)
        .fontSize(64)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  StrokeArea() {
    Column({ space: 8 }) {
      Canvas(this.canvasContext)
        .width(200)
        .height(200)
        .backgroundColor(this.isDarkMode ? withColorAlpha(this.themePrimary, '10') : withColorAlpha(this.themePrimary, '08'))
        .borderRadius(12)
        .onReady(() => {
          this.demoCanvasWidth = 200
          this.demoCanvasHeight = 200
          this.canvasContext.lineCap = 'round'
          this.canvasContext.lineJoin = 'round'
          // 静态先画出整字浅色底? v1 只画米字格, 等孩子点「看笔顺」
          this.redrawDemoCanvas()
        })
      if (this.strokes.length > 0) {
        Button() {
          Row({ space: 6 }) {
            SymbolGlyph(this.isPlaying ? $r('sys.symbol.arrow_clockwise') : $r('sys.symbol.AI_pencil'))
              .fontSize(14)
              .fontColor([Color.White])
            Text(this.isPlaying ? `第 ${Math.min(this.playedStrokeCount + 1, this.strokes.length)} 笔…` : (this.hasWatchedStrokes ? '再看一遍笔顺' : '看笔顺'))
              .fontSize(13)
              .fontColor(Color.White)
          }
        }
        .type(ButtonType.Normal)
        .height(36)
        .padding({ left: 16, right: 16 })
        .backgroundColor(KIDS_MATH_INK)
        .borderRadius(18)
        .enabled(!this.isPlaying)
        .opacity(this.isPlaying ? 0.6 : 1)
        .onClick(() => {
          this.handleWatch()
        })
      } else {
        Text('这个字暂时没有笔顺动画')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  MeaningSection() {
    Column({ space: 6 }) {
      Text('意思')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      Text(this.argsView.meaning)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  WordsSection() {
    Column({ space: 6 }) {
      Text('组词')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      Row({ space: 8 }) {
        ForEach(this.argsView.words, (word: string) => {
          Text(word)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themePrimary)
            .backgroundColor(withColorAlpha(this.themePrimary, '14'))
            .borderRadius(8)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        }, (word: string) => `word_${word}`)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SentenceSection() {
    Column({ space: 6 }) {
      Text('例句')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      Text(this.argsView.sentence)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  OriginSection() {
    Column({ space: 6 }) {
      Text('字源小故事')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      Text(this.argsView.origin)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding(10)
    .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '12' : '0A'))
    .borderRadius(10)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  LookalikeSection() {
    Column({ space: 6 }) {
      Text('别认错啦')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      ForEach(this.argsView.lookalikes, (pair: HanziCardLookalikeView) => {
        Row({ space: 10 }) {
          Text(`${this.argsView.character} ↔ ${pair.char}`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(pair.note)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }, (pair: HanziCardLookalikeView) => `lk_${pair.char}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ControlArea() {
    if (this.isAnswered) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(14)
          .fontColor([$r('app.color.status_success')])
        Text('已学会' + (this.hasWatchedStrokes ? '' : ' · 未看笔顺'))
          .fontSize(13)
          .fontColor($r('app.color.status_success'))
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    } else if (this.argsView.valid) {
      Button('我学会了 · 继续')
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
      Column({ space: 12 }) {
        if (this.argsView.valid) {
          this.CharHeader()
          this.StrokeArea()
          this.MeaningSection()
          this.WordsSection()
          this.SentenceSection()
          if (this.argsView.origin !== '') {
            this.OriginSection()
          }
          if (this.argsView.lookalikes.length > 0) {
            this.LookalikeSection()
          }
          this.ControlArea()
        } else {
          Text('这道讲解出错了，老师马上换一张')
            .fontSize(14).fontColor(KIDS_MUTED)
            .padding({ top: 8, bottom: 8 })
        }
      }
      .width('100%')
    }
  }
}
