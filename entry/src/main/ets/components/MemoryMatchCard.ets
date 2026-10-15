/**
 * MemoryMatchCard - 记忆翻牌互动卡片 (宝石主题)
 *
 * 参考 docs/open-close-game.html 原型 (宝石记忆): 孩子先看短暂预览记住宝石位置,
 * 再两张两张翻开配对; 步数越少评级越高 (1-3 星), 难度 1-5 映射 3×2 至 6×4 棋盘。
 *
 * CardShell 统一外壳 (feedbackAboveSlot 棋盘卡范式, 镜像 MazeCard), direct 模式
 * (usesConfirm: false)。挂到 kids_games (小星游戏老师), 与 number_puzzle/maze/sudoku
 * 同属益智游戏族, 锻炼 observation / spatial_reasoning。
 *
 * - 牌面布局在 aboutToAppear 内随机生成 (镜像 number_puzzle 模式, 不经 handler 注入)
 * - 预览阶段: 全部明置 + 「记住位置」倒计时 pill, 结束后盖回并开始计时
 * - 翻牌规则: 每次翻两张, 配对成功锁定为已配对态 (绿环 + ✓ 徽标),
 *   配错 820ms 后自动盖回 (期间锁定, 防连点)
 * - 全部配对成功 → onAnswer(completed: true, rating: 1-3)
 * - 放弃路径镜像 MatchingPairsCard → onAnswer(completed: false)
 * - 最佳成绩按难度持久化 (镜像 MazeCard: moves/time/rating 三键 + bestScoresLoaded 竞态守卫)
 *
 * aboutToAppear 做防御性难度 clamp (双保险, 历史消息渲染不经 handler)。
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { getPreferencesService, PreferenceKeys } from '../services/PreferencesService'
import { CardShell } from './cardshell/CardShell'
import { CardShellConfig } from './cardshell/CardShellTypes'
import { CardShellState } from './cardshell/CardShellState'

/** 对外结果载荷 (ToolResult 经 recordStarEvent → computeStars 消费) */
export interface MemoryMatchResult {
  difficulty: number
  level_name: string
  grid_size: string
  pairs: number
  move_count: number
  time_seconds: number
  rating: number
  matched_pairs: number
  completed: boolean
  /** 本局牌面主题 label (食物/形状/字母/数字/颜色), 供恢复态还原正确主题 */
  theme: string
}

interface MemoryMatchLevel {
  difficulty: number
  name: string
  cols: number
  rows: number
  previewMs: number
}

/** 难度表: 与工具 schema description 严格一致 (BuiltinTools.createMemoryMatchToolDefinition) */
const MEMORY_LEVELS: MemoryMatchLevel[] = [
  { difficulty: 1, name: '见习', cols: 3, rows: 2, previewMs: 2500 },
  { difficulty: 2, name: '学徒', cols: 4, rows: 3, previewMs: 2200 },
  { difficulty: 3, name: '行家', cols: 4, rows: 4, previewMs: 2000 },
  { difficulty: 4, name: '大师', cols: 5, rows: 4, previewMs: 1600 },
  { difficulty: 5, name: '宗师', cols: 6, rows: 4, previewMs: 1200 }
]

/**
 * 牌面主题: 每局随机一个, 从主题池随机取 pairs 种牌面。
 * 呼应教学场景 (观察力/短时记忆): 食物 / 形状 / 字母 / 数字 / 颜色 五类。
 * - kind 'emoji': 彩色 emoji 牌面
 * - kind 'char':  单色字符牌面 (形状/字母/数字), 用 text_primary 着色
 * - kind 'color': 纯色圆点牌面 (颜色认知), 走 colors hex
 */
interface MemoryMatchTheme {
  kind: string
  label: string
  faces: string[]
  names: string[]
  colors?: string[]
}

const FOOD_FACES: string[] = ['🍎', '🍌', '🍇', '🍓', '🍊', '🍉', '🥕', '🌽', '🍞', '🧀', '🍔', '🍦']
const FOOD_NAMES: string[] = ['苹果', '香蕉', '葡萄', '草莓', '橘子', '西瓜', '胡萝卜', '玉米', '面包', '奶酪', '汉堡', '冰淇淋']
const SHAPE_FACES: string[] = ['●', '○', '▲', '■', '★', '◆', '▼', '◐', '✚', '◇', '▽', '▣']
const SHAPE_NAMES: string[] = ['圆形', '小圆', '三角', '方块', '星形', '菱形', '倒三角', '半月', '十字', '空菱形', '下三角', '方徽']
const LETTER_FACES: string[] = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'K', 'L', 'M', 'N']
const NUMBER_FACES: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12']
const COLOR_NAMES: string[] = ['红色', '橙色', '黄色', '绿色', '青色', '蓝色', '靛蓝', '紫色', '粉色', '棕色', '灰色', '黑色']
const COLOR_HEX: string[] = ['#E53935', '#FB8C00', '#FDD835', '#43A047', '#00ACC1', '#1E88E5', '#3949AB', '#8E24AA', '#EC407A', '#6D4C41', '#9E9E9E', '#212121']

const MEMORY_THEMES: MemoryMatchTheme[] = [
  { kind: 'emoji', label: '食物', faces: FOOD_FACES, names: FOOD_NAMES },
  { kind: 'char', label: '形状', faces: SHAPE_FACES, names: SHAPE_NAMES },
  { kind: 'char', label: '字母', faces: LETTER_FACES, names: LETTER_FACES },
  { kind: 'char', label: '数字', faces: NUMBER_FACES, names: NUMBER_FACES },
  { kind: 'color', label: '颜色', faces: SHAPE_FACES, names: COLOR_NAMES, colors: COLOR_HEX }
]

const SUCCESS_GREEN: string = '#22C55E'
const GIVEUP_ORANGE: string = '#FF9F43'
/** 配错翻回等待 (与原型的 820ms 一致) */
const FLIP_BACK_DELAY_MS: number = 820

function shuffleNumbers(values: number[]): number[] {
  const out: number[] = values.slice(0)
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    const tmp = out[i]
    out[i] = out[j]
    out[j] = tmp
  }
  return out
}

@ComponentV2
export struct MemoryMatchCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local quizOk: boolean = false
  // 棋盘数据: cardGems 发牌后不变 (ForEach key 源), cardStates 每次变更整体重赋值驱动渲染
  @Local cardGems: number[] = []
  @Local cardStates: string[] = []
  @Local cols: number = 3
  @Local rows: number = 2
  @Local pairs: number = 3
  @Local levelName: string = '见习'
  @Local themeLabel: string = '食物'
  @Local moves: number = 0
  @Local matchedPairs: number = 0
  @Local elapsedSeconds: number = 0
  @Local isPreviewing: boolean = false
  @Local previewRemainingMs: number = 0
  @Local isCompleted: boolean = false
  @Local gaveUp: boolean = false
  @Local pressedIndex: number = -1
  // 最佳成绩 (按难度)
  @Local bestMoves: number = -1
  @Local bestTimeSeconds: number = -1
  @Local bestRating: number = 0
  @Local bestScoresLoaded: boolean = false
  // 已答态恢复用
  @Local prevCompleted: boolean = false
  @Local prevRating: number = 0

  private firstIndex: number = -1
  private locked: boolean = true
  private startTime: number = 0
  private theme: MemoryMatchTheme = MEMORY_THEMES[0]
  private tickTimerId: number = -1
  private previewTimerId: number = -1
  private previewTickId: number = -1
  private flipBackTimerId: number = -1

  // CardShell 外壳配置/状态 (direct 模式: usesConfirm=false, feedbackAboveSlot 棋盘卡庆祝横幅位)
  @Local shellConfig: CardShellConfig = {
    title: '记忆翻牌',
    subtitle: '',
    icon: $r('sys.symbol.checkmark_square_on_square'),
    stem: '',
    hasAudio: false,
    usesConfirm: false,
    feedbackTitleCorrect: '全部配对完成！',
    correctAnswerLabel: '',
    feedbackAboveSlot: true,
    usesGiveUp: true,
    giveUpLabel: ''
  }
  private shellState: CardShellState = new CardShellState()

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
    // 防御性难度 clamp: handler 已规范化, 这里兜历史消息/异常路径
    let difficulty = 1
    try {
      const parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      const raw = Math.floor((parsed['difficulty'] as number) ?? 1)
      difficulty = Math.max(1, Math.min(5, raw))
    } catch (_e) {
      difficulty = 1
    }

    const level = MEMORY_LEVELS[difficulty - 1]
    this.cols = level.cols
    this.rows = level.rows
    this.pairs = (level.cols * level.rows) / 2
    this.levelName = level.name
    this.quizOk = true

    if (this.isAnswered && this.answeredPayload !== '') {
      this.restoreAnsweredState(difficulty)
    } else {
      this.dealNewGame(level)
    }

    this.shellConfig = {
      title: '记忆翻牌',
      subtitle: `${this.levelName} · ${this.cols}×${this.rows} · ${this.pairs} 对`,
      icon: $r('sys.symbol.checkmark_square_on_square'),
      stem: `先记住${this.themeLabel}的位置，再两张两张找出一样的`,
      hasAudio: false,
      usesConfirm: false,
      feedbackTitleCorrect: '全部配对完成！',
      correctAnswerLabel: '',
      feedbackAboveSlot: true,
      usesGiveUp: true,
      giveUpLabel: ''
    }

    // 最佳成绩异步加载, 完成前禁用保存 (竞态守卫, 镜像 NumberPuzzleCard)
    if (!this.isAnswered) {
      void this.loadBestScores(difficulty)
    }
  }

  aboutToDisappear(): void {
    this.clearAllTimers()
  }

  // ---- 发牌 / 恢复 ----

  private dealNewGame(level: MemoryMatchLevel): void {
    // 每局随机主题 (食物/形状/字母/数字/颜色), 从主题池随机取 pairs 种牌面成对洗牌
    const themeIndex = Math.floor(Math.random() * MEMORY_THEMES.length)
    this.theme = MEMORY_THEMES[themeIndex]
    this.themeLabel = this.theme.label
    const pool: number[] = []
    for (let i = 0; i < this.theme.faces.length; i++) {
      pool.push(i)
    }
    const picked = shuffleNumbers(pool).slice(0, this.pairs)
    const deck = shuffleNumbers(picked.concat(picked))
    this.cardGems = deck
    this.cardStates = deck.map((_gem: number): string => 'down')

    // 预览阶段: 全部明置, 倒计时结束盖回
    this.locked = true
    this.isPreviewing = true
    this.previewRemainingMs = level.previewMs
    this.cardStates = this.cardGems.map((_gem: number): string => 'up')
    this.previewTimerId = setTimeout(() => {
      this.endPreview()
    }, level.previewMs)
    this.previewTickId = setInterval(() => {
      this.previewRemainingMs = Math.max(0, this.previewRemainingMs - 100)
    }, 100)
  }

  private endPreview(): void {
    this.clearPreviewTimers()
    this.isPreviewing = false
    this.previewRemainingMs = 0
    if (this.isCompleted || this.isAnswered) {
      return
    }
    this.cardStates = this.cardGems.map((_gem: number): string => 'down')
    this.locked = false
    this.startTime = Date.now()
    this.tickTimerId = setInterval(() => {
      if (this.startTime > 0 && !this.isCompleted) {
        this.elapsedSeconds = Math.floor((Date.now() - this.startTime) / 1000)
      }
    }, 500)
  }

  private restoreAnsweredState(difficulty: number): void {
    // 已答态: 牌面按确定性顺序复原并全部呈已配对样式 (同 NumberPuzzleCard 还原 solvedBoard 思路)。
    // 主题从 payload 恢复, 保证回执视图与实际游玩主题一致 (无 theme 字段的历史 payload 回退默认主题)
    let prevMoves = 0
    let prevTime = 0
    let prevMatched = 0
    try {
      const prev = JSON.parse(this.answeredPayload) as MemoryMatchResult
      this.prevCompleted = prev.completed === true
      this.prevRating = prev.rating ?? 0
      prevMoves = prev.move_count ?? 0
      prevTime = prev.time_seconds ?? 0
      prevMatched = prev.matched_pairs ?? this.pairs
      for (let i = 0; i < MEMORY_THEMES.length; i++) {
        if (MEMORY_THEMES[i].label === prev.theme) {
          this.theme = MEMORY_THEMES[i]
          this.themeLabel = this.theme.label
          break
        }
      }
    } catch (_e) {
      // payload 缺失: 按已完成展示, 不渲染对错横幅
      this.prevCompleted = true
      this.shellState.feedbackSuppressed = true
      prevMatched = this.pairs
    }

    const deck: number[] = []
    for (let i = 0; i < this.pairs; i++) {
      const gem = i % this.theme.faces.length
      deck.push(gem)
      deck.push(gem)
    }
    this.cardGems = deck
    this.cardStates = deck.map((_gem: number): string => 'matched')
    this.moves = prevMoves
    this.elapsedSeconds = prevTime
    this.matchedPairs = prevMatched
    this.isCompleted = true
    this.locked = true

    this.shellState.isFinished = true
    this.shellState.submitted = true
    this.shellState.isCorrect = this.prevCompleted
    this.shellState.feedbackTitle = this.getBannerTitle()
    this.shellState.feedbackDetail = this.getBannerSub()
    this.shellState.headPill = this.hasWon() ? '已完成' : '已放弃'
    this.shellState.headPillColor = this.hasWon() ? SUCCESS_GREEN : GIVEUP_ORANGE
  }

  // ---- 交互 ----

  private cellState(index: number): string {
    const states = this.cardStates
    if (index < 0 || index >= states.length) {
      return 'down'
    }
    return states[index]
  }

  private handleCardTouch(event: TouchEvent, index: number): void {
    if (event.type === TouchType.Down) {
      this.pressedIndex = index
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.pressedIndex === index) {
        this.pressedIndex = -1
      }
    }
  }

  private handleCardTap(index: number): void {
    if (this.locked || this.isCompleted || this.isAnswered) {
      return
    }
    if (this.cellState(index) !== 'down') {
      return
    }
    this.flipOpen(index)
    if (this.firstIndex < 0) {
      this.firstIndex = index
      return
    }
    // 第二张: 计步并结算
    const a = this.firstIndex
    const b = index
    this.firstIndex = -1
    this.moves += 1
    if (this.cardGems[a] === this.cardGems[b]) {
      this.setCellState(a, 'matched')
      this.setCellState(b, 'matched')
      this.matchedPairs += 1
      if (this.matchedPairs >= this.pairs) {
        this.handleWin()
      }
    } else {
      this.locked = true
      if (this.flipBackTimerId >= 0) {
        clearTimeout(this.flipBackTimerId)
      }
      this.flipBackTimerId = setTimeout(() => {
        this.flipBackTimerId = -1
        this.setCellState(a, 'down')
        this.setCellState(b, 'down')
        this.locked = false
      }, FLIP_BACK_DELAY_MS)
    }
  }

  private flipOpen(index: number): void {
    this.setCellState(index, 'up')
  }

  private setCellState(index: number, state: string): void {
    const states = this.cardStates.slice(0)
    if (index < 0 || index >= states.length) {
      return
    }
    states[index] = state
    this.cardStates = states
  }

  // ---- 结算 ----

  private computeRating(): number {
    // 步数效率评级 (与原型 starsFor 一致): ≤1.5×对数 3 星, ≤2.2× 2 星, 其余 1 星
    const ratio = this.pairs > 0 ? this.moves / this.pairs : 99
    if (ratio <= 1.5) {
      return 3
    }
    if (ratio <= 2.2) {
      return 2
    }
    return 1
  }

  private formatTime(totalSeconds: number): string {
    const total = Math.max(0, Math.floor(totalSeconds))
    const m = Math.floor(total / 60)
    const s = total % 60
    return `${m}:${s < 10 ? '0' : ''}${s}`
  }

  private handleWin(): void {
    this.isCompleted = true
    this.locked = true
    this.clearGameTimers()
    this.elapsedSeconds = this.startTime > 0 ? Math.floor((Date.now() - this.startTime) / 1000) : this.elapsedSeconds
    const rating = this.computeRating()
    this.prevRating = rating
    this.prevCompleted = true
    void this.saveBestScoresIfImproved(rating)

    this.shellState.isFinished = true
    this.shellState.submitted = true
    this.shellState.isCorrect = true
    this.shellState.feedbackTitle = '全部配对完成！'
    this.shellState.feedbackDetail = `${this.moves} 步 · ${this.formatTime(this.elapsedSeconds)} · ${'★'.repeat(rating)}`
    this.shellState.feedbackBadge = this.bestMoves >= 0 && this.isNewBest(rating) ? '新纪录' : ''
    this.shellState.headPill = '已完成'
    this.shellState.headPillColor = SUCCESS_GREEN
    this.submitAnswer(true, rating)
  }

  private handleGiveUp(): void {
    if (this.isCompleted || this.isAnswered) {
      return
    }
    this.isCompleted = true
    this.gaveUp = true
    this.locked = true
    this.clearGameTimers()

    this.shellState.isFinished = true
    this.shellState.submitted = true
    this.shellState.isCorrect = false
    this.shellState.feedbackTitle = '没关系，下次再试试～'
    this.shellState.feedbackDetail = `已配对 ${this.matchedPairs}/${this.pairs}`
    this.shellState.headPill = '已放弃'
    this.shellState.headPillColor = GIVEUP_ORANGE
    this.submitAnswer(false, 0)
  }

  private submitAnswer(completed: boolean, rating: number): void {
    const payload: MemoryMatchResult = {
      difficulty: this.levelDifficulty(),
      level_name: this.levelName,
      grid_size: `${this.cols}×${this.rows}`,
      pairs: this.pairs,
      move_count: this.moves,
      time_seconds: Math.max(0, Math.floor(this.elapsedSeconds)),
      rating: rating,
      matched_pairs: this.matchedPairs,
      completed: completed,
      theme: this.themeLabel
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private levelDifficulty(): number {
    for (let i = 0; i < MEMORY_LEVELS.length; i++) {
      if (MEMORY_LEVELS[i].name === this.levelName) {
        return MEMORY_LEVELS[i].difficulty
      }
    }
    return 1
  }

  private isFinished(): boolean {
    return this.isCompleted || this.isAnswered
  }

  private hasWon(): boolean {
    return this.isAnswered ? this.prevCompleted : this.isCompleted && !this.gaveUp
  }

  private getBannerTitle(): string {
    if (this.hasWon()) {
      return '全部配对完成！'
    }
    return '没关系，下次再试试～'
  }

  private getBannerSub(): string {
    if (this.hasWon()) {
      const rating = this.isAnswered ? this.prevRating : 0
      const stars = rating > 0 ? `${'★'.repeat(rating)}` : ''
      return `${this.moves} 步 · ${this.formatTime(this.elapsedSeconds)}${stars !== '' ? ` · ${stars}` : ''}`
    }
    return `已配对 ${this.matchedPairs}/${this.pairs}`
  }

  // ---- 最佳成绩 (镜像 MazeCard: moves 升序优先, 平局比时间; rating 取历史最高) ----

  private isNewBest(rating: number): boolean {
    if (!this.bestScoresLoaded || this.bestMoves < 0) {
      return false
    }
    return this.moves < this.bestMoves ||
      (this.moves === this.bestMoves && this.elapsedSeconds < this.bestTimeSeconds) ||
      rating > this.bestRating
  }

  private async loadBestScores(difficulty: number): Promise<void> {
    const key = difficulty.toString()
    const prefs = getPreferencesService()
    try {
      this.bestMoves = await prefs.getNumber(PreferenceKeys.MEMORY_MATCH_BEST_MOVES_PREFIX + key, -1)
      this.bestTimeSeconds = await prefs.getNumber(PreferenceKeys.MEMORY_MATCH_BEST_TIME_PREFIX + key, -1)
      this.bestRating = await prefs.getNumber(PreferenceKeys.MEMORY_MATCH_BEST_RATING_PREFIX + key, 0)
      this.bestScoresLoaded = true
    } catch (_e) {
      this.bestMoves = -1
      this.bestTimeSeconds = -1
      this.bestRating = 0
      this.bestScoresLoaded = true
    }
    if (this.bestMoves >= 0) {
      this.shellState.headBadge = `最佳 ${this.bestMoves} 步`
    }
  }

  private async saveBestScoresIfImproved(rating: number): Promise<void> {
    if (!this.bestScoresLoaded) {
      // 未加载完 → 放弃本次保存 (罕见竞态), 优于覆盖真实记录
      return
    }
    const improved = this.bestMoves < 0 || this.moves < this.bestMoves ||
      (this.moves === this.bestMoves && this.elapsedSeconds < this.bestTimeSeconds)
    if (!improved) {
      return
    }
    const key = this.levelDifficulty().toString()
    const prefs = getPreferencesService()
    const nextRating = Math.max(rating, this.bestRating)
    try {
      await prefs.setNumber(PreferenceKeys.MEMORY_MATCH_BEST_MOVES_PREFIX + key, this.moves)
      await prefs.setNumber(PreferenceKeys.MEMORY_MATCH_BEST_TIME_PREFIX + key, Math.max(0, Math.floor(this.elapsedSeconds)))
      await prefs.setNumber(PreferenceKeys.MEMORY_MATCH_BEST_RATING_PREFIX + key, nextRating)
      this.bestMoves = this.moves
      this.bestTimeSeconds = Math.max(0, Math.floor(this.elapsedSeconds))
      this.bestRating = nextRating
    } catch (_e) {
      // 持久化失败静默: 星星与 AI 回执不受影响
    }
  }

  // ---- 计时器管理 ----

  private clearPreviewTimers(): void {
    if (this.previewTimerId >= 0) {
      clearTimeout(this.previewTimerId)
      this.previewTimerId = -1
    }
    if (this.previewTickId >= 0) {
      clearInterval(this.previewTickId)
      this.previewTickId = -1
    }
  }

  private clearGameTimers(): void {
    if (this.tickTimerId >= 0) {
      clearInterval(this.tickTimerId)
      this.tickTimerId = -1
    }
    if (this.flipBackTimerId >= 0) {
      clearTimeout(this.flipBackTimerId)
      this.flipBackTimerId = -1
    }
  }

  private clearAllTimers(): void {
    this.clearPreviewTimers()
    this.clearGameTimers()
  }

  // ---- 视觉辅助 ----

  private get emojiFontSize(): number {
    if (this.cols <= 3) {
      return 36
    }
    if (this.cols === 4) {
      return 28
    }
    if (this.cols === 5) {
      return 24
    }
    return 20
  }

  /** 字符类牌面 (形状/字母/数字) 字号: 单字符略大于 emoji, 双字符数字缩小防溢出 */
  private charFaceFontSize(face: string): number {
    const single = this.emojiFontSize
    if (face.length > 1) {
      return Math.round(single * 0.62)
    }
    return Math.round(single * 0.86)
  }

  /** 颜色主题: 圆点颜色取自主题 hex 表; 其他主题不需要 */
  private faceColorFor(gem: number): string {
    if (this.theme.colors !== undefined && gem >= 0 && gem < this.theme.colors.length) {
      return this.theme.colors[gem]
    }
    return this.themePrimary
  }

  private cellBackground(index: number): ResourceColor {
    const state = this.cellState(index)
    if (state === 'matched') {
      return withColorAlpha(SUCCESS_GREEN, this.isDarkMode ? '1E' : '14')
    }
    if (state === 'up') {
      return $r('app.color.surface')
    }
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '22' : '14')
  }

  private cellBorderColor(index: number): ResourceColor {
    const state = this.cellState(index)
    if (state === 'matched') {
      return SUCCESS_GREEN
    }
    if (state === 'up') {
      return $r('app.color.divider')
    }
    return withColorAlpha(this.themePrimary, this.isDarkMode ? '38' : '28')
  }

  private gemName(gem: number): string {
    return gem >= 0 && gem < this.theme.names.length ? this.theme.names[gem] : '牌面'
  }

  build() {
    if (!this.quizOk) {
      Column() {
        Text('题目参数有误')
          .fontSize(13)
          .fontColor($r('app.color.status_error'))
          .width('100%')
          .padding(8)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.themeAiBubble)
      .borderRadius(12)
      .border({ width: 1, color: $r('app.color.divider') })
    } else {
      CardShell({
        config: this.shellConfig,
        state: this.shellState,
        isAnswered: false,
        onGiveUp: () => {
          this.handleGiveUp()
        }
      }) {
        this.HudRow()
        if (this.isPreviewing) {
          this.PreviewPill()
        }
        this.BoardArea()
      }
    }
  }

  @Builder
  HudRow() {
    Row({ space: 12 }) {
      Text(`步数 ${this.moves}`)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
      Text(`用时 ${this.formatTime(this.elapsedSeconds)}`)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
      Text(`配对 ${this.matchedPairs}/${this.pairs}`)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  PreviewPill() {
    Row() {
      Text(`记住位置 · ${Math.ceil(this.previewRemainingMs / 1000)}`)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
    }
    .padding({ left: 14, right: 14, top: 5, bottom: 5 })
    .borderRadius(999)
    .backgroundColor(this.themePrimary)
    .margin({ top: 2 })
  }

  @Builder
  BoardArea() {
    Column() {
      Grid() {
        ForEach(this.cardGems, (gem: number, index: number) => {
          GridItem() {
            this.CardCell(gem, index)
          }
        }, (gem: number, index: number) => `cell_${index}_${gem}`)
      }
      .columnsTemplate(`repeat(${this.cols}, 1fr)`)
      .columnsGap(6)
      .rowsGap(6)
      .width('100%')
    }
    .width('100%')
    .padding(10)
    .constraintSize({ maxWidth: 340 })
    .alignSelf(ItemAlign.Center)
    .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '14' : '0A'))
    .borderRadius(10)
  }

  @Builder
  CardFace(gem: number) {
    if (this.theme.kind === 'color') {
      // 颜色主题: 纯色圆点 (hex 走主题色表)
      Text('●')
        .fontSize(this.charFaceFontSize('●'))
        .fontColor(this.faceColorFor(gem))
    } else if (this.theme.kind === 'char') {
      // 字符主题 (形状/字母/数字): text_primary 着色
      Text(this.theme.faces[gem] ?? '?')
        .fontSize(this.charFaceFontSize(this.theme.faces[gem] ?? '?'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
    } else {
      // emoji 主题 (食物)
      Text(this.theme.faces[gem] ?? '❓')
        .fontSize(this.emojiFontSize)
    }
  }

  @Builder
  CardCell(gem: number, index: number) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.cellState(index) === 'down') {
        // 牌背: 主题色微透 + 菱形印记 (呼应原型 cover-mark)
        Column() {
          Text('◆')
            .fontSize(Math.round(this.emojiFontSize * 0.5))
            .fontColor(withColorAlpha(this.themePrimary, '70'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseInOut }))
      } else {
        // 牌面: 按主题渲染; 已配对加 ✓ 徽标
        Column() {
          this.CardFace(gem)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseInOut }))

        if (this.cellState(index) === 'matched') {
          Text('✓')
            .fontSize(9)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .width(15)
            .height(15)
            .textAlign(TextAlign.Center)
            .borderRadius(8)
            .backgroundColor(SUCCESS_GREEN)
            .margin({ top: 3, right: 3 })
        }
      }
    }
    .width('100%')
    .aspectRatio(1)
    .borderRadius(10)
    .backgroundColor(this.cellBackground(index))
    .border({ width: this.cellState(index) === 'matched' ? 2 : 1, color: this.cellBorderColor(index) })
    .scale(this.pressedIndex === index ? { x: 0.94, y: 0.94 } : { x: 1, y: 1 })
    .animation({ duration: 120, curve: Curve.EaseOut })
    .onClick(() => {
      this.handleCardTap(index)
    })
    .onTouch((event: TouchEvent) => {
      this.handleCardTouch(event, index)
    })
    .accessibilityText(this.cellState(index) === 'down' ? `第 ${index + 1} 张, 未翻开` : `第 ${index + 1} 张, ${this.gemName(gem)}`)
  }
}
