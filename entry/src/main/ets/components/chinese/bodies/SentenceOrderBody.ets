// entry/src/main/ets/components/chinese/bodies/SentenceOrderBody.ets
/**
 * SentenceOrderBody - chinese_quiz 连词成句 body
 * 词卡池 → 孩子按顺序点词卡拼句子 → 点已放词卡撤回 → 拼满自动判分。
 * AI 传来的 words 必须是打乱顺序 (schema 层校验), 这里不重复洗牌,
 * 仅在词序恰好等于正确语序时本地兜底洗一次 (防 AI 直接把答案摆池子里)。
 * 授星走 chinese_quiz 既有分支 (correct=true → 1 星, skill_key=chinese_reading)。
 */

import { ToolCall } from '../../../models/ChatModels'
import { getAppUiState } from '../../../state/AppUiState'
import { withColorAlpha } from '../../../utils/ColorAlphaUtils'
import { CardShell } from '../../cardshell/CardShell'
import { CardShellConfig } from '../../cardshell/CardShellTypes'
import { CardShellState } from '../../cardshell/CardShellState'
import {
  ChineseQuizAnswerPayload, ChineseQuizModeArgs, normalizeSentence,
  parseChineseQuizModeArgs
} from '../ModeTypes'

@ComponentV2
export struct SentenceOrderBody {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local words: string[] = []
  @Local pool: string[] = []
  @Local placed: string[] = []
  @Local correctAnswer: string = ''
  @Local skillKey: string = 'chinese_reading'
  @Local showResult: boolean = false
  @Local isCorrect: boolean = false
  private shellConfig: CardShellConfig = {
    title: '连词成句', subtitle: '', icon: $r('sys.symbol.book'),
    stem: '点词卡排成一句通顺的话', hasAudio: false, usesConfirm: false,
    feedbackTitleCorrect: '答对啦！真棒！', correctAnswerLabel: '正确语序'
  }
  private shellState: CardShellState = new CardShellState()

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  aboutToAppear(): void {
    const args: ChineseQuizModeArgs = parseChineseQuizModeArgs(this.toolCall.arguments)
    this.words = args.words
    this.correctAnswer = args.answer
    this.skillKey = args.skillKey
    this.shellConfig = {
      title: '连词成句',
      subtitle: args.difficulty >= 1 ? `难度 ${args.difficulty} · ${args.words.length} 个词卡` : '',
      icon: $r('sys.symbol.book'),
      stem: '点词卡排成一句通顺的话', hasAudio: false, usesConfirm: false,
      feedbackTitleCorrect: '答对啦！真棒！', correctAnswerLabel: '正确语序'
    }
    if (this.isAnswered) {
      const prev = this.parsePreviousAnswer()
      if (prev !== null) {
        this.placed = this.words.slice()
        this.pool = []
        this.showResult = true
        this.isCorrect = prev.correct
        this.shellState.submitted = true
        this.shellState.hasSelection = true
        this.shellState.isCorrect = prev.correct
        this.shellState.headPill = '已回答'
        this.shellState.headPillColor = '#4CAF50'
      } else {
        this.shellState.feedbackSuppressed = true
        this.shellState.headPill = '已回答'
        this.shellState.headPillColor = '#4CAF50'
      }
    } else {
      this.pool = this.buildShuffledPool(args.words, args.answer)
    }
  }

  private parsePreviousAnswer(): ChineseQuizAnswerPayload | null {
    if (this.answeredPayload === '') {
      return null
    }
    try {
      return JSON.parse(this.answeredPayload) as ChineseQuizAnswerPayload
    } catch (_e) {
      return null
    }
  }

  /** 池子洗牌; 若 AI 给的顺序恰好可通 (等于正确语序), 再洗直到不同 (2 词时最多试几次) */
  private buildShuffledPool(words: string[], answer: string): string[] {
    const pool = words.slice()
    const answerNorm = normalizeSentence(answer)
    for (let attempt = 0; attempt < 8; attempt++) {
      this.shuffleInPlace(pool)
      if (words.length < 2 || normalizeSentence(pool.join('')) !== answerNorm) {
        break
      }
    }
    return pool
  }

  private shuffleInPlace(arr: string[]): void {
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1))
      const tmp = arr[i]
      arr[i] = arr[j]
      arr[j] = tmp
    }
  }

  private handlePickFromPool(word: string, poolIdx: number): void {
    if (this.isAnswered || this.showResult) {
      return
    }
    const nextPlaced = this.placed.slice()
    nextPlaced.push(word)
    const nextPool = this.pool.slice()
    nextPool.splice(poolIdx, 1)
    this.placed = nextPlaced
    this.pool = nextPool
    this.shellState.hasSelection = nextPlaced.length > 0
    if (nextPool.length === 0) {
      this.judge()
    }
  }

  private handleReturnFromPlaced(placedIdx: number): void {
    if (this.isAnswered || this.showResult) {
      return
    }
    const nextPlaced = this.placed.slice()
    const word = nextPlaced.splice(placedIdx, 1)[0]
    const nextPool = this.pool.slice()
    nextPool.push(word)
    this.placed = nextPlaced
    this.pool = nextPool
    this.shellState.hasSelection = nextPlaced.length > 0
  }

  private judge(): void {
    const childAnswer = this.placed.join('')
    const correct = normalizeSentence(childAnswer) === normalizeSentence(this.correctAnswer)
    this.showResult = true
    this.isCorrect = correct
    this.shellState.submitted = true
    this.shellState.isCorrect = correct
    const payload: ChineseQuizAnswerPayload = {
      answered: true,
      mode: 'sentence_order',
      child_answer: childAnswer,
      correct: correct,
      correct_answer: this.correctAnswer,
      skill_key: this.skillKey
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private getCardBackgroundColor(): string {
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12')
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
        this.SlotArea()
        if (!this.isAnswered && !this.showResult) {
          this.PoolArea()
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.getCardBackgroundColor())
      .borderRadius(10)
    }
  }

  @Builder
  SlotArea() {
    Column({ space: 6 }) {
      if (this.placed.length === 0) {
        Text('按顺序点下面的词卡…')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 10, bottom: 10 })
      } else {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(this.placed, (word: string, idx: number) => {
            Text(word)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor(this.showResult
                ? (this.isCorrect ? $r('app.color.status_success') : '#FF6B6B')
                : this.themePrimary)
              .borderRadius(10)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .margin(4)
              .onClick(() => {
                this.handleReturnFromPlaced(idx)
              })
          }, (word: string, idx: number) => `placed_${idx}_${word}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(8)
    .borderRadius(10)
    .border({
      width: 1.5,
      color: withColorAlpha(this.themePrimary, this.isDarkMode ? '38' : '2C'),
      style: BorderStyle.Dashed
    })
  }

  @Builder
  PoolArea() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
      ForEach(this.pool, (word: string, idx: number) => {
        Text(word)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.surface'))
          .borderRadius(10)
          .border({
            width: 1,
            color: $r('app.color.divider'),
            style: BorderStyle.Solid
          })
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .margin(4)
          .onClick(() => {
            this.handlePickFromPool(word, idx)
          })
      }, (word: string, idx: number) => `pool_${idx}_${word}`)
    }
    .width('100%')
  }
}
