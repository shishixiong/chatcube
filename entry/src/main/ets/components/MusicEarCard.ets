/**
 * MusicEarCard - 音符小耳朵（听觉训练）互动卡片
 *
 * 参考 Open Design 原型: 六键果味小钢琴 + 三种听音练习（听高低 / 复述旋律 / 猜儿歌）。
 * 挂到 kids_games（小星游戏老师）, 锻炼 observation。
 *
 * - 自由敲琴: 6 个琴键（C-A 五声音阶）, 点一下发一个音, 先让孩子熟悉音色
 * - 三种练习: 每题两次机会, 首答对才计入 first_try_correct
 * - 一轮 5 题 → 结算页; 「再来一轮」本地重开, 不提交、不重复记星
 * - 提交权唯一: 卡片是本次工具调用唯一的 onAnswer 调用方
 *   （aboutToDisappear 兜底提交, 「回消息」先提交再关闭）
 * - 声音走 MusicToneService（AudioRenderer + 纯 PCM 合成）, 失败时降级提示
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import {
  MUSIC_KEYS,
  MUSIC_QUESTIONS_PER_ROUND,
  MUSIC_TIMBRES,
  MusicDrill,
  MusicKeyDef,
  MusicNote,
  MusicTimbre,
  MusicTimbreDef,
  findSong
} from '../utils/MusicEarData'
import {
  GuessSongQuestion,
  HighLowQuestion,
  RoundSnapshot,
  SeededRng,
  buildEchoSequence,
  buildGuessSongQuestion,
  buildHighLowQuestion,
  clampDifficulty,
  computeMusicEarStars,
  normalizeDrill,
  pickBestRound,
  scoreRound
} from '../utils/MusicEarLogic'
import { MusicToneService, getMusicToneService } from '../services/MusicToneService'

/** 对外结果载荷（ToolResult 经 recordStarEvent → computeStars 消费） */
export interface MusicEarResult {
  drill: string
  difficulty: number
  total: number
  correct: number
  first_try_correct: number
  completed: boolean
  stars: number
  songs: string[]
  rounds_played: number
  cancelled?: boolean
}

interface MusicEarArgsShape {
  drill?: string
  difficulty?: number
}

const SUCCESS_GREEN: string = '#22C55E'
const WARN_ORANGE: string = '#FF9F43'
const ANSWER_FEEDBACK_MS: number = 400
const FEEDBACK_CLEAR_MS: number = 2600
const REPLAY_DELAY_MS: number = 320

@ComponentV2
export struct MusicEarCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
  @Event onRequestClose: () => void = () => {}

  // ---- 页面与设置 ----
  @Local page: string = 'free' // free | round | summary
  @Local drill: MusicDrill = 'high_low'
  @Local difficulty: number = 1
  @Local timbre: MusicTimbre = 'piano'
  @Local muted: boolean = false
  @Local audioReady: boolean = false
  @Local audioFailed: boolean = false

  // ---- 一轮状态 ----
  @Local questionIndex: number = 0
  @Local firstTryResults: boolean[] = []
  @Local eventualResults: boolean[] = []
  @Local roundUsedPairKeys: string[] = []
  @Local roundUsedSongKeys: string[] = []
  @Local roundSongNames: string[] = []
  @Local completedRounds: RoundSnapshot[] = []
  @Local submitted: boolean = false

  // ---- 当前题 ----
  @Local currentHighLow: HighLowQuestion | null = null
  @Local currentEcho: MusicNote[] = []
  @Local pressedEcho: MusicNote[] = []
  @Local currentGuess: GuessSongQuestion | null = null
  @Local feedback: string = ''
  @Local retriedThisQuestion: boolean = false
  @Local locked: boolean = false
  @Local revealedAnswer: string = ''
  @Local wrongShake: boolean = false
  @Local pressedNote: MusicNote = 'C'
  @Local pressedPulse: number = 0

  private rng: SeededRng = new SeededRng(Date.now())
  private advanceTimerId: number = -1
  private feedbackTimerId: number = -1
  private pulseTimerId: number = -1
  private replayTimerId: number = -1

  // ---- 主题令牌 ----
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get bubbleColor(): string {
    return getAppUiState().themeAiBubble
  }

  private get service(): MusicToneService {
    return getMusicToneService()
  }

  // ---- 生命周期 ----

  aboutToAppear(): void {
    this.parseArgs()
    if (this.isAnswered && this.answeredPayload !== '') {
      this.restoreAnsweredState()
      return
    }
    this.startAudio()
  }

  aboutToDisappear(): void {
    // ① 提交（唯一提交点）
    if (!this.submitted) {
      this.submitOnce()
    }
    // ② 清定时器
    this.clearTimers()
    // ③ 收音频
    this.service.stopAll()
    this.service.release()
  }

  private parseArgs(): void {
    try {
      const params = JSON.parse(this.toolCall.arguments) as MusicEarArgsShape
      this.drill = normalizeDrill(params.drill ?? 'high_low')
      this.difficulty = clampDifficulty(params.difficulty ?? 1)
    } catch (_e) {
      this.drill = 'high_low'
      this.difficulty = 1
    }
  }

  private startAudio(): void {
    // 服务是单例，上一张卡片可能留在静音态；每次开卡以卡片自身状态为准。
    this.service.setMuted(this.muted)
    this.service.ensureStarted().then((ok: boolean) => {
      this.audioReady = ok
      this.audioFailed = !ok
    })
  }

  private restoreAnsweredState(): void {
    this.page = 'summary'
    this.submitted = true
    try {
      const result = JSON.parse(this.answeredPayload) as MusicEarResult
      this.drill = normalizeDrill(result.drill)
      this.difficulty = clampDifficulty(result.difficulty)
      const restored: RoundSnapshot = {
        drill: this.drill,
        difficulty: this.difficulty,
        total: result.total,
        correct: result.correct,
        firstTryCorrect: result.first_try_correct,
        songs: result.songs
      }
      const list: RoundSnapshot[] = []
      list.push(restored)
      this.completedRounds = list
    } catch (_e) {
      // 历史载荷损坏时保持空结算页
    }
  }

  private clearTimers(): void {
    if (this.advanceTimerId >= 0) {
      clearTimeout(this.advanceTimerId)
      this.advanceTimerId = -1
    }
    if (this.feedbackTimerId >= 0) {
      clearTimeout(this.feedbackTimerId)
      this.feedbackTimerId = -1
    }
    if (this.pulseTimerId >= 0) {
      clearTimeout(this.pulseTimerId)
      this.pulseTimerId = -1
    }
    if (this.replayTimerId >= 0) {
      clearTimeout(this.replayTimerId)
      this.replayTimerId = -1
    }
  }

  // ---- 自由敲琴 ----

  private pressKey(note: MusicNote): void {
    this.pressedNote = note
    this.pressedPulse += 1
    this.service.playNote(note, this.timbre)
    this.resetPulseLater()
  }

  private toggleMute(): void {
    this.muted = !this.muted
    this.service.setMuted(this.muted)
  }

  private keyGradient(key: MusicKeyDef, pressed: boolean): LinearGradient {
    if (pressed) {
      return { angle: 180, colors: [[key.ink, 0.0], [key.ink, 1.0]] }
    }
    return { angle: 180, colors: [[key.pale, 0.0], [key.color, 1.0]] }
  }

  // ---- 一轮流程（Task 10/11 填充） ----

  private startRound(): void {
    this.questionIndex = 0
    this.firstTryResults = []
    this.eventualResults = []
    this.roundUsedPairKeys = []
    this.roundUsedSongKeys = []
    this.roundSongNames = []
    this.feedback = ''
    this.retriedThisQuestion = false
    this.locked = false
    this.revealedAnswer = ''
    this.page = 'round'
    this.nextQuestion()
  }

  private nextQuestion(): void {
    if (this.questionIndex >= MUSIC_QUESTIONS_PER_ROUND) {
      this.finishRound()
      return
    }
    this.retriedThisQuestion = false
    this.locked = false
    this.revealedAnswer = ''
    this.feedback = ''
    this.pressedEcho = []
    if (this.drill === 'high_low') {
      const question = buildHighLowQuestion(this.difficulty, this.rng, this.roundUsedPairKeys)
      this.roundUsedPairKeys.push(question.pairKey)
      this.currentHighLow = question
      this.playHighLow()
    } else if (this.drill === 'echo') {
      this.currentEcho = buildEchoSequence(this.difficulty, this.rng)
      this.playEchoSequence()
    } else {
      const question = buildGuessSongQuestion(this.difficulty, this.rng, this.roundUsedSongKeys)
      this.roundUsedSongKeys.push(question.songKey)
      const song = findSong(question.songKey)
      if (song !== null) {
        this.roundSongNames.push(song.name)
      }
      this.currentGuess = question
      this.playGuessSong()
    }
  }

  private playHighLow(): void {
    const question = this.currentHighLow
    if (question === null) {
      return
    }
    const notes: MusicNote[] = [question.first, question.second]
    this.service.playSequence(notes, this.timbre, 650, 300)
  }

  private playEchoSequence(): void {
    this.service.playSequence(this.currentEcho, this.timbre, 550, 120)
  }

  private playGuessSong(): void {
    const guess = this.currentGuess
    if (guess === null) {
      return
    }
    const song = findSong(guess.songKey)
    if (song === null) {
      return
    }
    const notes: MusicNote[] = []
    for (let i = 0; i < song.notes.length && i < guess.noteCount; i++) {
      notes.push(song.notes[i])
    }
    this.service.playSequence(notes, this.timbre, 480, 80)
  }

  private replayCurrent(): void {
    if (this.drill === 'high_low') {
      this.playHighLow()
    } else if (this.drill === 'echo') {
      this.pressedEcho = []
      this.playEchoSequence()
    } else {
      this.playGuessSong()
    }
  }

  // 错误音之后再重播，避免两个声音叠在一起
  private replaySoon(): void {
    if (this.replayTimerId >= 0) {
      clearTimeout(this.replayTimerId)
    }
    this.replayTimerId = setTimeout(() => {
      this.replayTimerId = -1
      if (!this.locked) {
        this.replayCurrent()
      }
    }, REPLAY_DELAY_MS)
  }

  // 首答记录（每题只记一次; 重试不再写盘，否则会把「首答对」洗成 false）
  private recordFirstAttempt(correct: boolean): void {
    if (this.firstTryResults.length !== this.questionIndex) {
      return
    }
    const next: boolean[] = this.firstTryResults.slice()
    next.push(correct)
    this.firstTryResults = next
  }

  // 每题最终结果（重试答对也算对; 每题只记一次）
  private recordOutcome(correct: boolean): void {
    if (this.eventualResults.length !== this.questionIndex) {
      return
    }
    const next: boolean[] = this.eventualResults.slice()
    next.push(correct)
    this.eventualResults = next
  }

  // 答对：首答或重试答对都走这里
  private handleCorrect(): void {
    this.recordOutcome(true)
    this.locked = true
    this.showFeedback('答对啦！')
    this.service.playNote('A', 'musicbox')
    this.advanceQuestion()
  }

  // 首答错：记录 + 给一次重试机会，留在本题
  private handleFirstWrong(message: string): void {
    this.retriedThisQuestion = true
    this.recordFirstAttempt(false)
    this.showFeedback(message)
    this.service.playNote('C', 'piano')
  }

  // 重试又错：揭示答案并推进
  private handleWrongAgain(message: string): void {
    this.recordOutcome(false)
    this.locked = true
    this.revealedAnswer = message
    this.showFeedback(message)
    this.service.playNote('C', 'piano')
    this.advanceQuestion()
  }

  private advanceQuestion(): void {
    if (this.advanceTimerId >= 0) {
      clearTimeout(this.advanceTimerId)
    }
    this.advanceTimerId = setTimeout(() => {
      this.advanceTimerId = -1
      this.questionIndex += 1
      this.nextQuestion()
    }, ANSWER_FEEDBACK_MS)
  }

  // ---- high_low 作答 ----

  private handleHighLowPick(pick: string): void {
    const question = this.currentHighLow
    if (question === null || this.locked) {
      return
    }
    if (pick === question.answer) {
      if (!this.retriedThisQuestion) {
        this.recordFirstAttempt(true)
      }
      this.handleCorrect()
      return
    }
    if (!this.retriedThisQuestion) {
      this.handleFirstWrong('再听一次')
      this.replaySoon()
      return
    }
    this.handleWrongAgain(`答案是${this.highLowAnswerLabel(question)}`)
  }

  private highLowAnswerLabel(question: HighLowQuestion): string {
    if (question.answer === 'same') {
      return '一样高'
    }
    return question.answer === 'first' ? '第一个' : '第二个'
  }

  // ---- echo 作答 ----

  private pressEchoKey(note: MusicNote): void {
    if (this.locked || this.currentEcho.length === 0) {
      return
    }
    this.pressedNote = note
    this.pressedPulse += 1
    this.service.playNote(note, this.timbre)
    this.resetPulseLater()

    const pressed: MusicNote[] = this.pressedEcho.slice()
    pressed.push(note)
    this.pressedEcho = pressed
    const index = pressed.length - 1
    if (note === this.currentEcho[index]) {
      if (pressed.length === this.currentEcho.length) {
        if (!this.retriedThisQuestion) {
          this.recordFirstAttempt(true)
        }
        this.handleCorrect()
      }
      return
    }
    // 按错
    this.pressedEcho = []
    if (!this.retriedThisQuestion) {
      this.handleFirstWrong('再听一次，从头来')
      this.replaySoon()
    } else {
      this.handleWrongAgain('再听一次，从头来')
    }
  }

  private resetPulseLater(): void {
    if (this.pulseTimerId >= 0) {
      clearTimeout(this.pulseTimerId)
    }
    this.pulseTimerId = setTimeout(() => {
      this.pressedNote = 'C'
      this.pressedPulse = 0
      this.pulseTimerId = -1
    }, 180)
  }

  // ---- guess_song 作答 ----

  private handleGuessPick(songKey: string): void {
    const guess = this.currentGuess
    if (guess === null || this.locked) {
      return
    }
    if (songKey === guess.answerSongKey) {
      if (!this.retriedThisQuestion) {
        this.recordFirstAttempt(true)
      }
      this.handleCorrect()
      return
    }
    if (!this.retriedThisQuestion) {
      this.handleFirstWrong('再听一次')
      this.replaySoon()
      return
    }
    const song = findSong(guess.answerSongKey)
    this.handleWrongAgain(`是《${song === null ? '答案' : song.name}》`)
  }

  private songNameOf(key: string): string {
    const song = findSong(key)
    return song === null ? key : song.name
  }

  private songEmojiOf(key: string): string {
    const song = findSong(key)
    return song === null ? '🎵' : song.emoji
  }

  private showFeedback(text: string): void {
    this.feedback = text
    if (this.feedbackTimerId >= 0) {
      clearTimeout(this.feedbackTimerId)
    }
    this.feedbackTimerId = setTimeout(() => {
      this.feedback = ''
      this.feedbackTimerId = -1
    }, FEEDBACK_CLEAR_MS)
  }

  private finishRound(): void {
    const score = scoreRound(this.firstTryResults, this.eventualResults)
    const snapshot: RoundSnapshot = {
      drill: this.drill,
      difficulty: this.difficulty,
      total: MUSIC_QUESTIONS_PER_ROUND,
      correct: score.correct,
      firstTryCorrect: score.firstTryCorrect,
      songs: this.roundSongNames
    }
    const rounds: RoundSnapshot[] = this.completedRounds.slice()
    rounds.push(snapshot)
    this.completedRounds = rounds
    this.page = 'summary'
  }

  private buildResult(): MusicEarResult {
    const best = pickBestRound(this.completedRounds)
    if (best === null) {
      const empty: MusicEarResult = {
        drill: this.drill,
        difficulty: this.difficulty,
        total: MUSIC_QUESTIONS_PER_ROUND,
        correct: 0,
        first_try_correct: 0,
        completed: false,
        stars: 0,
        songs: [],
        rounds_played: this.completedRounds.length,
        cancelled: true
      }
      return empty
    }
    const result: MusicEarResult = {
      drill: best.drill,
      difficulty: best.difficulty,
      total: best.total,
      correct: best.correct,
      first_try_correct: best.firstTryCorrect,
      completed: true,
      stars: computeMusicEarStars(best.difficulty, best.total, best.firstTryCorrect),
      songs: best.songs,
      rounds_played: this.completedRounds.length,
      cancelled: false
    }
    return result
  }

  private submitOnce(): void {
    if (this.submitted) {
      return
    }
    this.submitted = true
    this.onAnswer(this.toolCall.id, JSON.stringify(this.buildResult()))
  }

  // ---- UI ----

  build() {
    Column({ space: 12 }) {
      this.HeaderBar()

      if (this.page === 'free') {
        this.FreePage()
      } else if (this.page === 'round') {
        this.RoundPage()
      } else {
        this.SummaryPage()
      }
    }
    .width('100%')
    .padding(this.largeSize ? 0 : 14)
    .borderRadius(this.largeSize ? 0 : 14)
    .backgroundColor(this.largeSize ? Color.Transparent : this.bubbleColor)
  }

  @Builder
  HeaderBar() {
    Row({ space: 8 }) {
      Text('🎵')
        .fontSize(20)
      Column({ space: 2 }) {
        Text('音符小耳朵')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.inkPrimary)
        Text(this.headerSubtitle())
          .fontSize(11)
          .fontColor(this.inkSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button({ type: ButtonType.Circle }) {
        Text(this.muted ? '🔇' : '🔊')
          .fontSize(14)
      }
      .width(32)
      .height(32)
      .backgroundColor(withColorAlpha(this.themePrimary, '14'))
      .onClick(() => {
        this.toggleMute()
      })

      Button({ type: ButtonType.Circle }) {
        Text('✕')
          .fontSize(14)
          .fontColor(this.inkSecondary)
      }
      .width(32)
      .height(32)
      .backgroundColor(withColorAlpha(this.themePrimary, '14'))
      .onClick(() => {
        this.onRequestClose()
      })
    }
    .width('100%')
  }

  @Builder
  FreePage() {
    if (this.audioFailed) {
      this.AudioWarning()
    }
    this.Stage()
    this.TimbreChips()
    this.DrillChips()
    this.StartButton()
    Text('先按一按琴键，听听每个键的声音')
      .fontSize(12)
      .fontColor(this.inkSecondary)
      .width('100%')
      .textAlign(TextAlign.Center)
  }

  @Builder
  StartButton() {
    Button('我准备好啦 · 开始练习')
      .width('100%')
      .height(44)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor('#FFFFFF')
      .backgroundColor(this.audioFailed ? withColorAlpha(this.themePrimary, '40') : this.themePrimary)
      .enabled(!this.audioFailed)
      .onClick(() => {
        if (!this.audioFailed) {
          this.startRound()
        }
      })
  }

  @Builder
  AudioWarning() {
    Column({ space: 8 }) {
      Text('声音没打开')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(WARN_ORANGE)
      Row({ space: 10 }) {
        Button('重试')
          .fontSize(12)
          .height(30)
          .backgroundColor(withColorAlpha(WARN_ORANGE, '18'))
          .fontColor(WARN_ORANGE)
          .onClick(() => {
            this.startAudio()
          })
        Button('先回去')
          .fontSize(12)
          .height(30)
          .backgroundColor(withColorAlpha(this.themePrimary, '14'))
          .fontColor(this.inkSecondary)
          .onClick(() => {
            this.onRequestClose()
          })
      }
    }
    .width('100%')
    .padding(10)
    .borderRadius(12)
    .backgroundColor(withColorAlpha(WARN_ORANGE, '10'))
  }

  @Builder
  Stage() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 天空
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: this.isDarkMode
            ? [[withColorAlpha(this.themePrimary, '22'), 0.0], [withColorAlpha(this.themePrimary, '0C'), 1.0]]
            : [['#FFF7E8', 0.0], ['#EAF4FF', 1.0]]
        })

      // 云
      Row() {
        Ellipse()
          .width(46)
          .height(20)
          .fill(withColorAlpha('#FFFFFF', this.isDarkMode ? '1A' : 'CC'))
        Blank()
        Ellipse()
          .width(34)
          .height(16)
          .fill(withColorAlpha('#FFFFFF', this.isDarkMode ? '14' : 'AA'))
      }
      .width('100%')
      .padding({ left: 18, right: 22 })
      .alignItems(VerticalAlign.Top)
      .margin({ top: 14 })
      .height(40)

      // 琴键
      Row({ space: 6 }) {
        ForEach(MUSIC_KEYS, (item: MusicKeyDef) => {
          this.KeyButton(item)
        }, (item: MusicKeyDef) => item.note)
      }
      .width('100%')
      .padding({ left: 10, right: 10, bottom: 12 })
    }
    .width('100%')
    .height(196)
    .borderRadius(16)
    .clip(true)
    .border({ width: 0.5, color: withColorAlpha(this.themePrimary, '20') })
  }

  @Builder
  KeyButton(item: MusicKeyDef) {
    Column({ space: 2 }) {
      Text(item.emoji)
        .fontSize(20)
      Text(item.note)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(item.ink)
      Text(item.fruit)
        .fontSize(9)
        .fontColor(withColorAlpha(item.ink, 'CC'))
    }
    .justifyContent(FlexAlign.Center)
    .height(88)
    .layoutWeight(1)
    .borderRadius(12)
    .linearGradient(this.keyGradient(item, this.pressedNote === item.note && this.pressedPulse > 0))
    .scale({
      x: this.pressedNote === item.note && this.pressedPulse > 0 ? 0.94 : 1,
      y: this.pressedNote === item.note && this.pressedPulse > 0 ? 0.94 : 1
    })
    .animation({ duration: 90, curve: Curve.EaseOut })
    .onClick(() => {
      if (this.page === 'round' && this.drill === 'echo') {
        this.pressEchoKey(item.note)
      } else {
        this.pressKey(item.note)
      }
    })
  }

  @Builder
  TimbreChips() {
    Row({ space: 8 }) {
      Text('音色')
        .fontSize(11)
        .fontColor(this.inkSecondary)
      ForEach(MUSIC_TIMBRES, (item: MusicTimbreDef) => {
        Text(item.name)
          .fontSize(12)
          .fontColor(this.timbre === item.id ? '#FFFFFF' : this.inkSecondary)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor(this.timbre === item.id ? this.themePrimary : withColorAlpha(this.themePrimary, '12'))
          .onClick(() => {
            this.timbre = item.id
          })
      }, (item: MusicTimbreDef) => item.id)
    }
    .width('100%')
  }

  @Builder
  DrillChips() {
    Row({ space: 8 }) {
      Text('练习')
        .fontSize(11)
        .fontColor(this.inkSecondary)
      ForEach(this.drillOptions(), (item: DrillOption) => {
        Text(item.label)
          .fontSize(12)
          .fontColor(this.drill === item.id ? '#FFFFFF' : this.inkSecondary)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(14)
          .backgroundColor(this.drill === item.id ? this.themePrimary : withColorAlpha(this.themePrimary, '12'))
          .onClick(() => {
            this.drill = item.id
            if (this.page === 'summary') {
              this.page = 'free'
            }
          })
      }, (item: DrillOption) => item.id)
    }
    .width('100%')
  }

  @Builder
  RoundPage() {
    Column({ space: 10 }) {
      this.ProgressRow()

      if (this.feedback !== '') {
        Text(this.feedback)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.feedbackColor())
          .width('100%')
          .textAlign(TextAlign.Center)
      }

      if (this.drill === 'high_low') {
        this.HighLowBody()
      } else if (this.drill === 'echo') {
        this.EchoBody()
      } else {
        this.GuessSongBody()
      }

      Text('再听一遍')
        .fontSize(12)
        .fontColor(this.themePrimary)
        .padding({ top: 4, bottom: 4 })
        .onClick(() => {
          if (!this.locked) {
            this.replayCurrent()
          }
        })
    }
    .width('100%')
  }

  @Builder
  ProgressRow() {
    Row({ space: 8 }) {
      Text(`第 ${this.questionIndex + 1} / ${MUSIC_QUESTIONS_PER_ROUND} 题`)
        .fontSize(11)
        .fontColor(this.inkSecondary)
      Row() {
        Row()
          .width(`${Math.round((this.questionIndex / MUSIC_QUESTIONS_PER_ROUND) * 100)}%`)
          .height(6)
          .borderRadius(3)
          .backgroundColor(this.themePrimary)
      }
      .layoutWeight(1)
      .height(6)
      .borderRadius(3)
      .backgroundColor(withColorAlpha(this.themePrimary, '18'))
    }
    .width('100%')
  }

  @Builder
  HighLowBody() {
    Column({ space: 12 }) {
      Text('听一听，哪个音更高？')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.inkPrimary)

      Row({ space: 8 }) {
        this.ChoiceChip('⬆️', '第一个高', 'first')
        this.ChoiceChip('⬇️', '第二个高', 'second')
        this.ChoiceChip('＝', '一样高', 'same')
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor(withColorAlpha(this.themePrimary, '08'))
  }

  @Builder
  ChoiceChip(icon: string, label: string, value: string) {
    Column({ space: 4 }) {
      Text(icon)
        .fontSize(20)
      Text(label)
        .fontSize(12)
        .fontColor(this.inkPrimary)
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12 })
    .borderRadius(12)
    .backgroundColor(this.isDarkMode ? withColorAlpha('#FFFFFF', '0C') : '#FFFFFF')
    .border({ width: 1, color: withColorAlpha(this.themePrimary, '20') })
    .opacity(this.locked ? 0.5 : 1)
    .onClick(() => {
      this.handleHighLowPick(value)
    })
  }

  @Builder
  EchoBody() {
    Column({ space: 12 }) {
      Text('听一听，按顺序弹出来')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.inkPrimary)

      Row({ space: 6 }) {
        ForEach(this.echoSlots(), (item: EchoSlot) => {
          Text(item.filled ? item.name : '·')
            .fontSize(item.filled ? 14 : 18)
            .fontWeight(item.filled ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(item.filled ? this.themePrimary : withColorAlpha(this.themePrimary, '40'))
            .width(30)
            .height(30)
            .textAlign(TextAlign.Center)
            .borderRadius(15)
            .backgroundColor(withColorAlpha(this.themePrimary, '0C'))
        }, (item: EchoSlot) => item.key)
      }

      Row({ space: 6 }) {
        ForEach(MUSIC_KEYS, (item: MusicKeyDef) => {
          this.KeyButton(item)
        }, (item: MusicKeyDef) => `echo_${item.note}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor(withColorAlpha(this.themePrimary, '08'))
  }

  @Builder
  GuessSongBody() {
    Column({ space: 12 }) {
      Text('听一听，这是哪首歌？')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.inkPrimary)

      Row({ space: 8 }) {
        ForEach(this.guessOptions(), (item: SongOption) => {
          Column({ space: 4 }) {
            Text(item.emoji)
              .fontSize(20)
            Text(item.name)
              .fontSize(12)
              .fontColor(this.inkPrimary)
              .maxLines(1)
          }
          .layoutWeight(1)
          .padding({ top: 12, bottom: 12 })
          .borderRadius(12)
          .backgroundColor(this.isDarkMode ? withColorAlpha('#FFFFFF', '0C') : '#FFFFFF')
          .border({ width: 1, color: withColorAlpha(this.themePrimary, '20') })
          .opacity(this.locked ? 0.5 : 1)
          .onClick(() => {
            this.handleGuessPick(item.key)
          })
        }, (item: SongOption) => item.key)
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .borderRadius(14)
    .backgroundColor(withColorAlpha(this.themePrimary, '08'))
  }

  private feedbackColor(): string {
    if (this.revealedAnswer !== '' && this.feedback === this.revealedAnswer) {
      return WARN_ORANGE
    }
    return this.feedback === '答对啦！' ? SUCCESS_GREEN : this.inkSecondary
  }

  private echoSlots(): EchoSlot[] {
    const slots: EchoSlot[] = []
    for (let i = 0; i < this.currentEcho.length; i++) {
      const filled = i < this.pressedEcho.length
      const slot: EchoSlot = {
        key: `slot_${i}`,
        index: i,
        filled,
        name: filled ? this.pressedEcho[i] : ''
      }
      slots.push(slot)
    }
    return slots
  }

  private guessOptions(): SongOption[] {
    const options: SongOption[] = []
    const guess = this.currentGuess
    if (guess === null) {
      return options
    }
    for (let i = 0; i < guess.optionSongKeys.length; i++) {
      const key = guess.optionSongKeys[i]
      const option: SongOption = {
        key,
        name: this.songNameOf(key),
        emoji: this.songEmojiOf(key)
      }
      options.push(option)
    }
    return options
  }

  @Builder
  SummaryPage() {
    Column({ space: 12 }) {
      Text('这一轮结束啦')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.inkPrimary)

      Text(`答对 ${this.summaryCorrect()} / ${MUSIC_QUESTIONS_PER_ROUND}`)
        .fontSize(13)
        .fontColor(this.inkPrimary)
      Text(`一次就答对 ${this.summaryFirstTry()} 题`)
        .fontSize(12)
        .fontColor(this.inkSecondary)
      Text(this.summaryStarText())
        .fontSize(20)

      if (this.summarySongsText() !== '') {
        Text(`听到的歌：${this.summarySongsText()}`)
          .fontSize(12)
          .fontColor(this.inkSecondary)
          .width('100%')
          .textAlign(TextAlign.Center)
      }

      Button('再来一轮')
        .width('100%')
        .height(42)
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor(this.themePrimary)
        .onClick(() => {
          this.startRound()
        })

      Row({ space: 10 }) {
        Button('回到自由敲琴')
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .fontColor(this.inkPrimary)
          .backgroundColor(withColorAlpha(this.themePrimary, '14'))
          .onClick(() => {
            this.page = 'free'
          })
        Button('回消息')
          .layoutWeight(1)
          .height(38)
          .fontSize(13)
          .fontColor(this.inkPrimary)
          .backgroundColor(withColorAlpha(this.themePrimary, '14'))
          .onClick(() => {
            this.submitOnce()
            this.onRequestClose()
          })
      }
      .width('100%')

      this.DrillChips()
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  private lastRoundSnapshot(): RoundSnapshot | null {
    if (this.completedRounds.length === 0) {
      return null
    }
    return this.completedRounds[this.completedRounds.length - 1]
  }

  private summaryCorrect(): number {
    const last = this.lastRoundSnapshot()
    return last === null ? 0 : last.correct
  }

  private summaryFirstTry(): number {
    const last = this.lastRoundSnapshot()
    return last === null ? 0 : last.firstTryCorrect
  }

  private summaryStarText(): string {
    const last = this.lastRoundSnapshot()
    if (last === null) {
      return ''
    }
    const stars = computeMusicEarStars(last.difficulty, last.total, last.firstTryCorrect)
    let text = ''
    for (let i = 0; i < stars; i++) {
      text += '⭐'
    }
    return text
  }

  private summarySongsText(): string {
    const last = this.lastRoundSnapshot()
    if (last === null || last.songs.length === 0) {
      return ''
    }
    return last.songs.join('、')
  }

  // ---- 派生值 ----

  private headerSubtitle(): string {
    const names: string[] = ['简单', '进阶', '挑战']
    const index = this.difficulty - 1
    const level = index >= 0 && index < names.length ? names[index] : '简单'
    return `${level} · ${this.drillLabel()}`
  }

  private drillLabel(): string {
    if (this.drill === 'echo') {
      return '复述旋律'
    }
    if (this.drill === 'guess_song') {
      return '猜儿歌'
    }
    return '听音高低'
  }

  private drillOptions(): DrillOption[] {
    const options: DrillOption[] = [
      { id: 'high_low', label: '听高低' },
      { id: 'echo', label: '复述' },
      { id: 'guess_song', label: '猜歌' }
    ]
    return options
  }

  private get inkPrimary(): string {
    return this.isDarkMode ? '#F2EDE4' : '#3B342C'
  }

  private get inkSecondary(): string {
    return this.isDarkMode ? '#B9B2A6' : '#746E64'
  }
}

interface DrillOption {
  id: MusicDrill
  label: string
}

interface EchoSlot {
  key: string
  index: number
  filled: boolean
  name: string
}

interface SongOption {
  key: string
  name: string
  emoji: string
}
