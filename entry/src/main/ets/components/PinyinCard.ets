/**
 * PinyinCard - 拼音小课堂互动卡片（pinyin_card 工具）
 *
 * 讲解型卡片: 按六步识字法的拼音讲解呈现——声母+韵母=音节拼装公式、
 * 四声示范列表（点行 TTS 朗读）、记忆口诀、易混对比（可选）。
 * 孩子点任意一条四声示范听到发音后, 可点「我学会了 · 继续」提交完成回执。
 * 无对错判定, 完成即授星 (computeStars: completed=true → 1 星)。
 *
 * 参考 MathTeachCard (讲解回执) + ChoiceModeBody (TTS 模式)。
 */

import { getAppUiState } from '../state/AppUiState'
import { ToolCall } from '../models/ChatModels'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { CardShell } from './cardshell/CardShell'
import { CardShellConfig } from './cardshell/CardShellTypes'
import { CardShellState } from './cardshell/CardShellState'
import { KIDS_MATH_INK, KIDS_MUTED } from './kids/KidsBrandTokens'

export interface PinyinCardResult {
  syllable: string
  skill_key: string
  completed: boolean
}

interface PinyinCardExampleView {
  tone: number
  syllable: string
  char: string
  word: string
}

interface PinyinCardContrastView {
  a: string
  b: string
  tip: string
}

interface PinyinCardArgsView {
  valid: boolean
  initial: string
  final: string
  tone: number
  syllable: string
  examples: PinyinCardExampleView[]
  mnemonic: string
  contrast: PinyinCardContrastView[]
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

function toneName(tone: number): string {
  if (tone === 0) {
    return '轻声'
  }
  if (tone === 1) {
    return '一声'
  }
  if (tone === 2) {
    return '二声'
  }
  if (tone === 3) {
    return '三声'
  }
  return '四声'
}

function createDefaultArgsView(): PinyinCardArgsView {
  const view: PinyinCardArgsView = {
    valid: false, initial: '', final: '', tone: 1, syllable: '',
    examples: [], mnemonic: '', contrast: [], difficulty: 1, skillKey: 'pinyin'
  }
  return view
}

export function parsePinyinCardArgs(raw: string): PinyinCardArgsView {
  const view: PinyinCardArgsView = createDefaultArgsView()
  try {
    const obj = JSON.parse(raw) as Record<string, Object>
    view.final = getStr(obj, 'final', '')
    if (view.final === '') {
      return view
    }
    view.valid = true
    view.initial = getStr(obj, 'initial', '')
    view.tone = getNum(obj, 'tone', 1)
    view.syllable = getStr(obj, 'syllable', '')
    const examplesRaw: Object | undefined = obj['examples']
    if (Array.isArray(examplesRaw)) {
      const items = examplesRaw as Object[]
      for (let i = 0; i < items.length; i++) {
        const item = items[i] as Record<string, Object>
        const ex: PinyinCardExampleView = {
          tone: getNum(item, 'tone', 1),
          syllable: getStr(item, 'syllable', ''),
          char: getStr(item, 'char', ''),
          word: getStr(item, 'word', '')
        }
        view.examples.push(ex)
      }
    }
    view.mnemonic = getStr(obj, 'mnemonic', '')
    const contrastRaw: Object | undefined = obj['contrast']
    if (Array.isArray(contrastRaw)) {
      const items = contrastRaw as Object[]
      for (let i = 0; i < items.length; i++) {
        const item = items[i] as Record<string, Object>
        const pair: PinyinCardContrastView = {
          a: getStr(item, 'a', ''),
          b: getStr(item, 'b', ''),
          tip: getStr(item, 'tip', '')
        }
        view.contrast.push(pair)
      }
    }
    view.difficulty = getNum(obj, 'difficulty', 1)
    const skillRaw = getStr(obj, 'skill_key', '')
    view.skillKey = skillRaw !== '' ? skillRaw : 'pinyin'
  } catch (_e) {
    return view
  }
  return view
}

@ComponentV2
export struct PinyinCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local argsView: PinyinCardArgsView = createDefaultArgsView()
  @Local hasListened: boolean = false
  @Local playingIdx: number = -1

  private submitted: boolean = false
  private shellState: CardShellState = new CardShellState()
  private shellConfig: CardShellConfig = {
    title: '拼音小课堂', subtitle: '', icon: $r('sys.symbol.textformat'),
    stem: '', hasAudio: false, usesConfirm: false,
    feedbackTitleCorrect: '学会啦！', correctAnswerLabel: ''
  }

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  aboutToAppear(): void {
    this.argsView = parsePinyinCardArgs(this.toolCall.arguments)
    const syllable = this.argsView.syllable
    const toneText = toneName(this.argsView.tone)
    this.shellConfig = {
      title: '拼音小课堂',
      subtitle: syllable !== '' ? `${syllable} · ${toneText}` : '',
      icon: $r('sys.symbol.textformat'),
      stem: '', hasAudio: false, usesConfirm: false,
      feedbackTitleCorrect: '学会啦！', correctAnswerLabel: ''
    }
    // 讲解型卡片无对错判定, 永久抑制反馈横幅 (MathTeachCard 同款)
    this.shellState.feedbackSuppressed = true
    if (this.isAnswered) {
      try {
        const prev = JSON.parse(this.answeredPayload) as Record<string, Object>
        this.hasListened = true
        const syl = prev['syllable']
        if (typeof syl === 'string' && (syl as string) !== '') {
          this.shellConfig = {
            title: '拼音小课堂',
            subtitle: `${syl as string} · ${toneText}`,
            icon: $r('sys.symbol.textformat'),
            stem: '', hasAudio: false, usesConfirm: false,
            feedbackTitleCorrect: '学会啦！', correctAnswerLabel: ''
          }
        }
      } catch (_e) {
        this.hasListened = false
      }
    }
  }

  aboutToDisappear(): void {
    ServiceRegistry.tts().stop()
  }

  // ====== 交互 ======

  private handleExampleTap(ex: PinyinCardExampleView, idx: number): void {
    if (this.isAnswered) {
      return
    }
    this.hasListened = true
    if (this.playingIdx >= 0 || ex.syllable === '') {
      return
    }
    this.playingIdx = idx
    ServiceRegistry.tts().speak(`${ex.char}, ${ex.word}`, {
      onStart: () => {},
      onComplete: () => {
        this.playingIdx = -1
      },
      onError: (error: string) => {
        this.playingIdx = -1
        console.error('PinyinCard', `TTS error: ${error}`)
      }
    }).catch((e: Error) => {
      this.playingIdx = -1
      console.error('PinyinCard', `TTS speak failed: ${e.message}`)
    })
  }

  private canSubmit(): boolean {
    return this.hasListened
  }

  private submit(): void {
    if (this.submitted || !this.canSubmit() || this.isAnswered) {
      return
    }
    this.submitted = true
    const result: PinyinCardResult = {
      syllable: this.argsView.syllable,
      skill_key: this.argsView.skillKey,
      completed: true
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
  }

  // ====== 视图 ======

  @Builder
  FormulaRow() {
    Row({ space: 8 }) {
      if (this.argsView.initial !== '') {
        this.FormulaBlock(this.argsView.initial, '声母', false)
        Text('+').fontSize(20).fontColor(KIDS_MUTED)
      }
      this.FormulaBlock(this.argsView.final, '韵母', false)
      Text('=').fontSize(20).fontColor(KIDS_MUTED)
      this.FormulaBlock(this.argsView.syllable, toneName(this.argsView.tone), true)
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  FormulaBlock(text: string, label: string, highlight: boolean) {
    Column({ space: 4 }) {
      Text(text)
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor(highlight ? Color.White : $r('app.color.text_primary'))
      Text(label)
        .fontSize(10)
        .fontColor(highlight ? withColorAlpha('#FFFFFF', 'B0') : KIDS_MUTED)
    }
    .width(84)
    .padding({ top: 12, bottom: 10 })
    .backgroundColor(highlight ? this.themePrimary
      : (this.isDarkMode ? withColorAlpha(this.themePrimary, '14') : withColorAlpha(this.themePrimary, '0C')))
    .borderRadius(12)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  ToneList() {
    Column({ space: 6 }) {
      Text('四声这样读 · 点一下听一听')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      ForEach(this.argsView.examples, (ex: PinyinCardExampleView, idx: number) => {
        Row({ space: 10 }) {
          Text(toneName(ex.tone))
            .fontSize(11)
            .fontColor(this.playingIdx === idx ? Color.White : this.themePrimary)
            .backgroundColor(this.playingIdx === idx ? this.themePrimary : withColorAlpha(this.themePrimary, '14'))
            .borderRadius(6)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
          Text(ex.syllable)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(ex.char)
            .fontSize(24)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themePrimary)
          Text(ex.word)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
          SymbolGlyph(this.playingIdx === idx ? $r('sys.symbol.speaker_wave_2') : $r('sys.symbol.pause'))
            .fontSize(16)
            .fontColor([withColorAlpha(this.themePrimary, this.playingIdx === idx ? 'FF' : '66')])
        }
        .width('100%')
        .padding(10)
        .borderRadius(10)
        .backgroundColor(this.playingIdx === idx
          ? withColorAlpha(this.themePrimary, this.isDarkMode ? '1E' : '14')
          : (this.isDarkMode ? withColorAlpha(this.themePrimary, '0E') : withColorAlpha(this.themePrimary, '07')))
        .onClick(() => {
          this.handleExampleTap(ex, idx)
        })
      }, (ex: PinyinCardExampleView, idx: number) => `ex_${idx}_${ex.syllable}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  MnemonicSection() {
    Column({ space: 6 }) {
      Text('口诀')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      Text(this.argsView.mnemonic)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
    }
    .width('100%')
    .padding(10)
    .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '12' : '0A'))
    .borderRadius(10)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ContrastSection() {
    Column({ space: 6 }) {
      Text('别混啦')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      ForEach(this.argsView.contrast, (pair: PinyinCardContrastView) => {
        Row({ space: 10 }) {
          Text(`${pair.a} ↔ ${pair.b}`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(pair.tip)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }, (pair: PinyinCardContrastView) => `ct_${pair.a}_${pair.b}`)
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
        Text('已学会')
          .fontSize(13)
          .fontColor($r('app.color.status_success'))
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    } else if (this.argsView.valid) {
      Column({ space: 4 }) {
        if (!this.canSubmit()) {
          Text('先点上面的拼音听一听')
            .fontSize(12)
            .fontColor(KIDS_MUTED)
        }
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
      Column({ space: 12 }) {
        if (this.argsView.valid) {
          this.FormulaRow()
          this.ToneList()
          this.MnemonicSection()
          if (this.argsView.contrast.length > 0) {
            this.ContrastSection()
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
