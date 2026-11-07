/**
 * 音符小耳朵（music_ear）纯逻辑：题目生成、判分、星级、最好一轮选择。
 * 全部为纯函数 / 自带种子的伪随机，不依赖 ArkUI 与音频，可单测。
 */

import { MUSIC_NOTE_ORDER, MUSIC_SONGS, MUSIC_NOTE_FREQ, MusicNote, MusicSongDef, MusicDrill } from './MusicEarData'

export interface HighLowQuestion {
  first: MusicNote
  second: MusicNote
  answer: 'first' | 'second' | 'same'
  pairKey: string
}

export interface GuessSongQuestion {
  songKey: string
  optionSongKeys: string[]
  answerSongKey: string
  noteCount: number
}

export interface EchoEvaluation {
  correct: boolean
  firstWrongIndex: number
}

export interface RoundScore {
  correct: number
  firstTryCorrect: number
}

export interface RoundSnapshot {
  drill: MusicDrill
  difficulty: number
  total: number
  correct: number
  firstTryCorrect: number
  songs: string[]
}

/** 线性同余伪随机，固定种子可复现题目。 */
export class SeededRng {
  private state: number

  constructor(seed: number) {
    let normalized = Math.floor(Math.abs(seed))
    normalized = normalized % 4294967296
    this.state = normalized === 0 ? 1 : normalized
  }

  next(): number {
    this.state = (this.state * 1664525 + 1013904223) % 4294967296
    return this.state / 4294967296
  }

  nextInt(maxExclusive: number): number {
    if (maxExclusive <= 1) {
      return 0
    }
    return Math.floor(this.next() * maxExclusive)
  }
}

export function clampDifficulty(value: number): number {
  if (!Number.isFinite(value)) {
    return 1
  }
  const rounded = Math.round(value)
  if (rounded < 1) {
    return 1
  }
  if (rounded > 3) {
    return 3
  }
  return rounded
}

/** 只认别名表；未知值返回 null，交给调用方决定兜底。 */
export function parseDrill(value: string): MusicDrill | null {
  const normalized = value.trim().toLowerCase().replace(/-/g, '_')
  if (normalized === 'high_low' || normalized === 'highlow' || normalized === 'pitch') {
    return 'high_low'
  }
  if (normalized === 'echo' || normalized === 'repeat' || normalized === 'memory') {
    return 'echo'
  }
  if (normalized === 'guess_song' || normalized === 'guess' || normalized === 'song') {
    return 'guess_song'
  }
  return null
}

/** 卡片侧兜底：坏值一律当 high_low。 */
export function normalizeDrill(value: string): MusicDrill {
  const parsed = parseDrill(value)
  return parsed === null ? 'high_low' : parsed
}

export function noteIndex(note: MusicNote): number {
  return MUSIC_NOTE_ORDER.indexOf(note)
}

/** 以「先听哪个音」区分：C→F 与 F→C 是答案相反的两道题。 */
function notePairKey(a: MusicNote, b: MusicNote): string {
  return `${a}|${b}`
}

function buildOneHighLow(level: number, rng: SeededRng): HighLowQuestion {
  if (level === 3 && rng.nextInt(100) < 25) {
    const note = MUSIC_NOTE_ORDER[rng.nextInt(MUSIC_NOTE_ORDER.length)]
    const same: HighLowQuestion = {
      first: note,
      second: note,
      answer: 'same',
      pairKey: notePairKey(note, note)
    }
    return same
  }
  const distance = level === 1 ? 3 : (level === 2 ? 2 : 1)
  const lowIndex = rng.nextInt(MUSIC_NOTE_ORDER.length - distance)
  const highIndex = lowIndex + distance
  const ascending = rng.nextInt(2) === 0
  const first = ascending ? MUSIC_NOTE_ORDER[lowIndex] : MUSIC_NOTE_ORDER[highIndex]
  const second = ascending ? MUSIC_NOTE_ORDER[highIndex] : MUSIC_NOTE_ORDER[lowIndex]
  const question: HighLowQuestion = {
    first,
    second,
    answer: ascending ? 'second' : 'first',
    pairKey: notePairKey(first, second)
  }
  return question
}

export function buildHighLowQuestion(
  difficulty: number,
  rng: SeededRng,
  usedPairKeys?: string[]
): HighLowQuestion {
  const level = clampDifficulty(difficulty)
  let question = buildOneHighLow(level, rng)
  if (usedPairKeys === undefined || usedPairKeys.length === 0) {
    return question
  }
  // 难度 1 只有 6 个无序音对，5 题总能凑满；40 次仍重复则放行，绝不空转。
  for (let attempt = 0; attempt < 40; attempt++) {
    if (usedPairKeys.indexOf(question.pairKey) < 0) {
      return question
    }
    question = buildOneHighLow(level, rng)
  }
  return question
}

export function buildEchoSequence(difficulty: number, rng: SeededRng): MusicNote[] {
  const level = clampDifficulty(difficulty)
  const length = level + 2
  const result: MusicNote[] = []
  let previousIndex = -1
  for (let i = 0; i < length; i++) {
    let index = rng.nextInt(MUSIC_NOTE_ORDER.length)
    if (index === previousIndex) {
      index = (index + 1 + rng.nextInt(MUSIC_NOTE_ORDER.length - 1)) % MUSIC_NOTE_ORDER.length
    }
    result.push(MUSIC_NOTE_ORDER[index])
    previousIndex = index
  }
  return result
}

export function noteProfileDistance(a: MusicNote[], b: MusicNote[]): number {
  const count = Math.min(a.length, b.length)
  let sum = 0
  for (let i = 0; i < count; i++) {
    sum += Math.abs(noteIndex(a[i]) - noteIndex(b[i]))
  }
  return sum
}

export function buildGuessSongQuestion(
  difficulty: number,
  rng: SeededRng,
  usedSongKeys: string[]
): GuessSongQuestion {
  const level = clampDifficulty(difficulty)
  const available: MusicSongDef[] = []
  for (let i = 0; i < MUSIC_SONGS.length; i++) {
    if (usedSongKeys.indexOf(MUSIC_SONGS[i].key) < 0) {
      available.push(MUSIC_SONGS[i])
    }
  }
  const answerPool: MusicSongDef[] = available.length > 0 ? available : MUSIC_SONGS.slice()
  const answer = answerPool[rng.nextInt(answerPool.length)]

  const others: MusicSongDef[] = []
  for (let i = 0; i < MUSIC_SONGS.length; i++) {
    if (MUSIC_SONGS[i].key !== answer.key) {
      others.push(MUSIC_SONGS[i])
    }
  }
  others.sort((x: MusicSongDef, y: MusicSongDef): number => {
    return noteProfileDistance(answer.notes, x.notes) - noteProfileDistance(answer.notes, y.notes)
  })

  const optionCount = level + 2
  const picks: MusicSongDef[] = [answer]
  for (let i = 0; i < others.length && picks.length < optionCount; i++) {
    picks.push(others[i])
  }
  for (let i = picks.length - 1; i > 0; i--) {
    const j = rng.nextInt(i + 1)
    const tmp = picks[i]
    picks[i] = picks[j]
    picks[j] = tmp
  }

  const optionSongKeys: string[] = []
  for (let i = 0; i < picks.length; i++) {
    optionSongKeys.push(picks[i].key)
  }

  const question: GuessSongQuestion = {
    songKey: answer.key,
    optionSongKeys,
    answerSongKey: answer.key,
    noteCount: Math.min(5 + level, answer.notes.length)
  }
  return question
}

export function evaluateEcho(expected: MusicNote[], pressed: MusicNote[]): EchoEvaluation {
  const count = Math.min(expected.length, pressed.length)
  for (let i = 0; i < count; i++) {
    if (expected[i] !== pressed[i]) {
      const wrong: EchoEvaluation = { correct: false, firstWrongIndex: i }
      return wrong
    }
  }
  const result: EchoEvaluation = {
    correct: expected.length === pressed.length,
    firstWrongIndex: -1
  }
  return result
}

/**
 * @param firstTryResults 每题首答是否答对（决定星数）
 * @param eventualResults 每题最终是否答对（重试答对也算，决定「答对 X/5」）
 */
export function scoreRound(firstTryResults: boolean[], eventualResults: boolean[]): RoundScore {
  let firstTryCorrect = 0
  for (let i = 0; i < firstTryResults.length; i++) {
    if (firstTryResults[i]) {
      firstTryCorrect += 1
    }
  }
  let correct = 0
  for (let i = 0; i < eventualResults.length; i++) {
    if (eventualResults[i]) {
      correct += 1
    }
  }
  const score: RoundScore = {
    correct,
    firstTryCorrect
  }
  return score
}

/** 卡片结算页与 StarRewardService 共用同一公式，避免两套星数漂移。 */
export function computeMusicEarStars(difficulty: number, total: number, firstTryCorrect: number): number {
  if (total <= 0) {
    return 0
  }
  const threshold = Math.ceil(total * 0.8)
  if (firstTryCorrect >= threshold) {
    return Math.min(3, clampDifficulty(difficulty) + 1)
  }
  return 1
}

export function pickBestRound(rounds: RoundSnapshot[]): RoundSnapshot | null {
  if (rounds.length === 0) {
    return null
  }
  let best = rounds[0]
  for (let i = 1; i < rounds.length; i++) {
    if (rounds[i].firstTryCorrect > best.firstTryCorrect) {
      best = rounds[i]
    }
  }
  return best
}

export function noteFrequency(note: MusicNote): number {
  return MUSIC_NOTE_FREQ[note]
}
