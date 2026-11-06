// entry/src/main/ets/components/english/bodies/SpellWordBody.ets
/**
 * SpellWordBody - english_quiz v2 整词默写 body (2026-11-03)
 *
 * 孩子听单词发音 + 看中文意思, 用「字母格 + 屏幕字母键盘」把整词拼出来。
 * 两次机会流 (MathQuizCard 同款):
 *   首错 → 标红错位 + 清掉第一个错字母 + 行内提示, 不提交;
 *   次错 → 揭示正确拼写, 提交 correct=false;
 *   任意一次拼对 → 提交 correct=true (授星走 english_quiz 既有分支)。
 * 回包 dimension 由 utils/LedgerExtractUtils.skillDimensionFor 映射到「写」。
 */

import { ToolCall } from '../../../models/ChatModels'
import { getAppUiState } from '../../../state/AppUiState'
import { withColorAlpha } from '../../../utils/ColorAlphaUtils'
import { CardShell } from '../../cardshell/CardShell'
import { CardShellConfig } from '../../cardshell/CardShellTypes'
import { CardShellState } from '../../cardshell/CardShellState'
import { ServiceRegistry } from '../../../services/ServiceRegistry'
import {
  EnglishQuizAnswerPayload, EnglishQuizModeArgs, ENGLISH_QUIZ_TTS_SPEED,
  parseEnglishQuizModeArgs
} from '../ModeTypes'

/** 自动朗读延迟: 让卡片先渲染稳定, 避免和进场动画/浮层抢音频焦点 */
const AUTO_PLAY_DELAY_MS: number = 500
const LETTERS: string[] = 'abcdefghijklmnopqrstuvwxyz'.split('')
const KEY_BACKSPACE: string = '⌫'
const KEY_SUBMIT: string = '✓'

@ComponentV2
export struct SpellWordBody {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local correctAnswer: string = ''
  @Local targetZh: string = ''
  @Local question: string = ''
  @Local speakText: string = ''
  @Local skillKey: string = 'english_writing'
  @Local stage: string = ''
  @Local slots: string[] = []
  @Local activeIndex: number = 0
  @Local attempts: number = 0
  @Local wrongPositions: number[] = []
  @Local hintText: string = ''
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  @Local isPlayingSound: boolean = false
  private autoPlayTimer: number = -1
  private shellConfig: CardShellConfig = {
    title: '单词默写', subtitle: '', icon: $r('sys.symbol.square_and_pencil'),
    stem: '', hasAudio: true, usesConfirm: false,
    feedbackTitleCorrect: '拼对啦！真棒！', correctAnswerLabel: '正确拼写'
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
    this.correctAnswer = args.correctAnswer
    this.targetZh = args.targetZh
    this.question = args.question
    this.speakText = args.ttsText !== '' ? args.ttsText : args.correctAnswer
    this.skillKey = args.skillKey
    this.stage = args.stage
    this.slots = this.emptySlots(this.correctAnswer.length)
    this.activeIndex = 0
    if (this.isAnswered) {
      const prev = this.parsePreviousAnswer()
      if (prev !== null) {
        this.fillFromAnswer(prev.child_answer)
        this.showResult = true
        this.isCorrect = prev.correct
        this.shellState.submitted = true
        this.shellState.isCorrect = prev.correct
        this.shellState.isFinished = true
        this.shellState.headPill = '已回答'
        this.shellState.headPillColor = '#4CAF50'
      } else {
        // payload 缺失/不可解析: 无法判定当时对错, 抑制反馈横幅 (MathQuizCard 同款守卫)
        this.shellState.feedbackSuppressed = true
        this.shellState.headPill = '已回答'
        this.shellState.headPillColor = '#4CAF50'
      }
    } else {
      // 自动朗读: 孩子先听清发音, 再按中文意思拼写
      this.autoPlayTimer = setTimeout(() => {
        this.autoPlayTimer = -1
        this.handlePlaySound()
      }, AUTO_PLAY_DELAY_MS)
    }
  }

  aboutToDisappear(): void {
    if (this.autoPlayTimer >= 0) {
      clearTimeout(this.autoPlayTimer)
      this.autoPlayTimer = -1
    }
    if (this.isPlayingSound) {
      try {
        ServiceRegistry.tts().stop()
      } catch (_e) {}
      this.isPlayingSound = false
    }
  }

  private emptySlots(count: number): string[] {
    const arr: string[] = []
    for (let i = 0; i < count; i++) {
      arr.push('')
    }
    return arr
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

  /** 历史恢复: 把孩子当时的作答填回字母格 (多余的字母忽略) */
  private fillFromAnswer(answer: string): void {
    const clean = answer.replace(/\s+/g, '')
    const next: string[] = []
    for (let i = 0; i < this.slots.length; i++) {
      next.push(i < clean.length ? clean.charAt(i).toLowerCase() : '')
    }
    this.slots = next
    this.activeIndex = -1
  }

  // ===== 朗读 =====

  private handlePlaySound(): void {
    if (this.speakText === '' || this.isPlayingSound) {
      return
    }
    this.isPlayingSound = true
    this.shellState.isPlaying = true
    ServiceRegistry.tts().speak(this.speakText, {
      onStart: () => {},
      onComplete: () => {
        this.isPlayingSound = false
        this.shellState.isPlaying = false
      },
      onError: (error: string) => {
        this.isPlayingSound = false
        this.shellState.isPlaying = false
        console.error('SpellWordBody', `TTS error: ${error}`)
      }
    }, ENGLISH_QUIZ_TTS_SPEED).catch((e: Error) => {
      this.isPlayingSound = false
      this.shellState.isPlaying = false
      console.error('SpellWordBody', `TTS speak failed: ${e.message}`)
    })
  }

  // ===== 字母格编辑 =====

  private firstEmptyIndex(from: number): number {
    for (let i = from; i < this.slots.length; i++) {
      if (this.slots[i] === '') {
        return i
      }
    }
    for (let i = 0; i < this.slots.length; i++) {
      if (this.slots[i] === '') {
        return i
      }
    }
    return -1
  }

  private lastFilledIndex(): number {
    for (let i = this.slots.length - 1; i >= 0; i--) {
      if (this.slots[i] !== '') {
        return i
      }
    }
    return -1
  }

  private handleCellTap(index: number): void {
    if (this.showResult) {
      return
    }
    this.activeIndex = index
  }

  private handleLetter(letter: string): void {
    if (this.showResult || this.slots.length === 0) {
      return
    }
    let target = this.activeIndex
    if (target < 0 || target >= this.slots.length) {
      target = this.firstEmptyIndex(0)
    }
    if (target < 0) {
      return
    }
    const next: string[] = this.slots.slice()
    next[target] = letter
    this.slots = next
    this.hintText = ''
    this.activeIndex = this.firstEmptyIndex(target + 1)
    this.shellState.hasSelection = true
  }

  private handleBackspace(): void {
    if (this.showResult) {
      return
    }
    let target = this.activeIndex
    if (target < 0 || target >= this.slots.length || this.slots[target] === '') {
      target = this.lastFilledIndex()
    }
    if (target < 0) {
      return
    }
    const next: string[] = this.slots.slice()
    next[target] = ''
    this.slots = next
    this.activeIndex = target
    this.hintText = ''
    this.shellState.hasSelection = this.firstFilledIndex() >= 0
  }

  private firstFilledIndex(): number {
    for (let i = 0; i < this.slots.length; i++) {
      if (this.slots[i] !== '') {
        return i
      }
    }
    return -1
  }

  private handleKey(key: string): void {
    if (key === KEY_BACKSPACE) {
      this.handleBackspace()
      return
    }
    if (key === KEY_SUBMIT) {
      this.handleSubmit()
      return
    }
    this.handleLetter(key)
  }

  // ===== 判定 =====

  private handleSubmit(): void {
    if (this.showResult || this.isAnswered) {
      return
    }
    if (this.firstEmptyIndex(0) >= 0) {
      this.hintText = '还有字母没填哦，写完整再检查～'
      return
    }
    const childAnswer = this.slots.join('')
    const correct = childAnswer.toLowerCase() === this.correctAnswer.toLowerCase()
    if (correct) {
      this.finishAttempt(childAnswer, true)
      return
    }
    const wrong: number[] = []
    for (let i = 0; i < this.slots.length; i++) {
      const expected = i < this.correctAnswer.length ? this.correctAnswer.charAt(i).toLowerCase() : ''
      if (this.slots[i].toLowerCase() !== expected) {
        wrong.push(i)
      }
    }
    this.wrongPositions = wrong
    if (this.attempts === 0) {
      // 首错: 不提交, 标红 + 清掉第一个错字母 + 提示再听
      this.attempts = 1
      const firstWrong = wrong.length > 0 ? wrong[0] : 0
      const next: string[] = this.slots.slice()
      next[firstWrong] = ''
      this.slots = next
      this.activeIndex = firstWrong
      this.hintText = '差一点点！再听一遍，改一改刚才那个字母～'
      return
    }
    // 次错: 揭示正确拼写并提交
    const revealed: string[] = []
    for (let i = 0; i < this.correctAnswer.length; i++) {
      revealed.push(this.correctAnswer.charAt(i))
    }
    this.slots = revealed
    this.finishAttempt(childAnswer, false)
  }

  private finishAttempt(childAnswer: string, correct: boolean): void {
    this.showResult = true
    this.isCorrect = correct
    this.wrongPositions = []
    this.hintText = ''
    this.shellState.hasSelection = false
    this.shellState.submitted = true
    this.shellState.isCorrect = correct
    this.shellState.isFinished = true
    this.shellState.feedbackDetail = correct
      ? (this.attempts === 0 ? '一次就拼对啦！' : `改对啦，第 ${this.attempts + 1} 次成功！`)
      : '记住这个拼写，下次一定行！'
    const payload: EnglishQuizAnswerPayload = {
      answered: true,
      child_answer: childAnswer,
      correct: correct,
      correct_answer: this.correctAnswer,
      word: '',
      sentence: '',
      question_type: 'spell_word',
      skill_key: this.skillKey,
      mode: 'spell_word',
      stage: this.stage,
      target_text: this.correctAnswer,
      attempts: this.attempts + 1
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private handleGiveUp(): void {
    if (this.showResult || this.isAnswered) {
      return
    }
    this.finishAttempt(this.slots.join(''), false)
  }

  private getCardBackgroundColor(): string {
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12')
  }

  private slotBackgroundColor(idx: number): ResourceColor {
    if (this.wrongPositions.indexOf(idx) >= 0) {
      return withColorAlpha('#FF6B6B', '14')
    }
    return $r('app.color.surface')
  }

  private slotBorderColor(idx: number): ResourceColor {
    if (idx === this.activeIndex && !this.showResult) {
      return this.themePrimary
    }
    if (this.wrongPositions.indexOf(idx) >= 0) {
      return '#FF6B6B'
    }
    return $r('app.color.divider')
  }

  private slotTextColor(idx: number): ResourceColor {
    if (this.wrongPositions.indexOf(idx) >= 0) {
      return '#FF6B6B'
    }
    return $r('app.color.text_primary')
  }

  private isActiveSlot(idx: number): boolean {
    return idx === this.activeIndex && !this.showResult
  }

  build() {
    CardShell({
      config: this.shellConfig,
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: this.correctAnswer,
      largeSize: this.largeSize,
      onConfirm: (): void => {},
      onRetry: (): void => {},
      onRequestReplay: (): void => { this.handlePlaySound() },
      onGiveUp: (): void => { this.handleGiveUp() }
    }) {
      Column({ space: 10 }) {
        Text(this.question)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
        if (this.targetZh !== '') {
          Text(this.targetZh)
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        this.SlotRow()
        if (this.hintText !== '' && !this.showResult) {
          Text(this.hintText)
            .fontSize(12)
            .fontColor('#FF6B6B')
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        if (!this.isAnswered && !this.showResult) {
          this.Keyboard()
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.getCardBackgroundColor())
      .borderRadius(10)
    }
  }

  @Builder
  SlotRow() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
      ForEach(this.slots, (letter: string, idx: number) => {
        Column() {
          Text(letter)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.slotTextColor(idx))
        }
        .width(34)
        .height(46)
        .justifyContent(FlexAlign.Center)
        .margin(4)
        .borderRadius(8)
        .backgroundColor(this.slotBackgroundColor(idx))
        .border({
          width: this.isActiveSlot(idx) ? 2 : 1,
          color: this.slotBorderColor(idx),
          style: BorderStyle.Solid
        })
        .onClick(() => {
          this.handleCellTap(idx)
        })
      }, (letter: string, idx: number) => `slot_${idx}`)
    }
    .width('100%')
  }

  @Builder
  Keyboard() {
    Grid() {
      ForEach(LETTERS, (letter: string) => {
        GridItem() {
          Button(letter)
            .type(ButtonType.Normal)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .height(44)
            .backgroundColor($r('app.color.surface'))
            .borderRadius(8)
            .onClick(() => {
              this.handleKey(letter)
            })
        }
      }, (letter: string) => `key_${letter}`)
      GridItem() {
        Button(KEY_BACKSPACE)
          .type(ButtonType.Normal)
          .fontSize(20)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .height(44)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(8)
          .onClick(() => {
            this.handleKey(KEY_BACKSPACE)
          })
      }
      GridItem() {
        Button(KEY_SUBMIT)
          .type(ButtonType.Normal)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .width('100%')
          .height(44)
          .backgroundColor(this.themePrimary)
          .borderRadius(8)
          .onClick(() => {
            this.handleKey(KEY_SUBMIT)
          })
      }
    }
    .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
    .columnsGap(4)
    .rowsGap(6)
    .width('100%')
  }
}
