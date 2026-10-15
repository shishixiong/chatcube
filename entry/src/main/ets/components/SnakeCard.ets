/**
 * SnakeCard - 贪吃蛇互动卡片
 *
 * 参考 docs/tanshishe_game.html 原型: 16×16 网格上方向键/滑动控制小蛇,
 * 吃红苹果变长并得连击分, 金色星星限时出现值 5×连击分, 速度随得分加快,
 * 撞墙/撞到自己游戏结束。难度 1-3 映射基础速度 (慢慢爬/正常速/飞快)。
 *
 * CardShell 统一外壳 (feedbackAboveSlot 棋盘卡范式, 镜像 MemoryMatchCard),
 * direct 模式 (usesConfirm: false)。挂到 kids_games (小星游戏老师),
 * 与 number_puzzle/maze/sudoku/memory_match 同属益智游戏族,
 * 锻炼 logic_thinking / spatial_reasoning (反应速度 + 方向规划)。
 *
 * - 棋局在卡片内部运行 (镜像 number_puzzle 模式, 不经 handler 注入)
 * - 渲染走 Canvas (镜像 HTML 原型的 draw 函数; HandwritingCard 先例),
 *   50ms 渲染 tick + 逻辑步进累加器 (HTML requestAnimationFrame 结构的等价简化)
 * - 首次游戏结束 (撞墙/撞己) 即提交回执 completed: true —— 「再来一局」由 AI
 *   重新发起工具调用控制节奏 (镜像 number_puzzle 先例); CardShell 放弃链提交 completed: false
 * - 控制入口: D-pad 方向按钮 (真实 Button, 防 List 滚动吞点击) + 棋盘滑动
 *   (priorityGesture + onTouch stopPropagation, 镜像 NumberPuzzleCard §6.3)
 * - 最佳得分按难度持久化 (snake_best_score_<difficulty>, bestScoresLoaded 竞态守卫
 *   镜像 MemoryMatchCard); 星级由 StarRewardService 按分数阈值计算 (≥25→3★, ≥12→2★, 其余 1★)
 * - 音效不做 (HTML 的 WebAudio 在 ArkTS 无对应简单基建), 保留 +N 得分飘字
 *
 * aboutToAppear 做防御性难度 clamp (双保险, 历史消息渲染不经 handler)。
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { getPreferencesService, PreferenceKeys } from '../services/PreferencesService'
import { CardShell } from './cardshell/CardShell'
import { CardShellConfig } from './cardshell/CardShellTypes'
import { CardShellState } from './cardshell/CardShellState'

/** 对外结果载荷 (ToolResult 经 recordStarEvent → computeStars 消费) */
export interface SnakeGameResult {
  difficulty: number
  level_name: string
  grid_size: string
  score: number
  apples_eaten: number
  gold_stars: number
  best_combo: number
  length: number
  time_seconds: number
  completed: boolean
}

interface SnakeLevel {
  difficulty: number
  name: string
  baseSpeedMs: number
}

/** 难度表: 与工具 schema description 严格一致 (BuiltinTools.createSnakeGameToolDefinition) */
const SNAKE_LEVELS: SnakeLevel[] = [
  { difficulty: 1, name: '慢慢爬', baseSpeedMs: 210 },
  { difficulty: 2, name: '正常速', baseSpeedMs: 180 },
  { difficulty: 3, name: '飞快', baseSpeedMs: 150 }
]

const GRID: number = 16
/** 连击窗口: 距上次进食 < 2200ms 连击 +1 (与原型一致) */
const COMBO_WINDOW_MS: number = 2200
/** 连击回落: > 2600ms 未进食回 x1 (与原型一致) */
const COMBO_RESET_MS: number = 2600
const COMBO_MAX: number = 5
/** 金星出现概率 / 存活时长 (与原型 0.4 / 6500ms 一致) */
const GOLD_CHANCE: number = 0.4
const GOLD_TTL_MS: number = 6500
/** 速度下限与每分加速 (与原型 max(85, base - score*3) 一致) */
const SPEED_FLOOR_MS: number = 85
const SPEED_RAMP_PER_POINT: number = 3
/** 渲染 tick 间隔 (HTML requestAnimationFrame 的简化等价) */
const RENDER_TICK_MS: number = 50

// 棋盘配色 (镜像原型)
const BOARD_BG: string = '#101B33'
const SNAKE_HEAD: string = '#7DE0CF'
const SNAKE_BODY_A: string = '#2FB49F'
const SNAKE_BODY_B: string = '#39C7B0'
const APPLE_RED: string = '#FF6B6B'
const APPLE_LEAF: string = '#39C7B0'
const APPLE_STEM: string = '#8A6A45'
const GOLD_STAR: string = '#FFC13A'
const EYE_INK: string = '#0E1B33'
const POPUP_APPLE: string = '#FFD86B'
const OVERLAY_SUB: string = '#C9D4EC'

const SUCCESS_GREEN: string = '#22C55E'
const GIVEUP_ORANGE: string = '#FF9F43'

interface GridPos {
  x: number
  y: number
}

interface ScorePopup {
  text: string
  gridX: number
  gridY: number
  life: number
  color: string
}

function makePos(x: number, y: number): GridPos {
  const p: GridPos = { x: x, y: y }
  return p
}

function makePopup(text: string, gridX: number, gridY: number, color: string): ScorePopup {
  const p: ScorePopup = { text: text, gridX: gridX, gridY: gridY, life: 1, color: color }
  return p
}

@ComponentV2
export struct SnakeCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  // ---- 游戏状态 (canvas 手动重绘, 棋面数据无需响应式) ----
  @Local quizOk: boolean = false
  @Local gamePhase: string = 'idle' // idle | countdown | playing | paused | over
  @Local score: number = 0
  @Local combo: number = 1
  @Local snakeLength: number = 3
  @Local applesEaten: number = 0
  @Local goldStars: number = 0
  @Local bestCombo: number = 1
  @Local elapsedSeconds: number = 0
  @Local levelName: string = '正常速'
  @Local difficulty: number = 2

  // 覆盖层 (开始/倒计时/暂停/结束)
  @Local overlayShow: boolean = false
  @Local overlayCount: string = ''
  @Local overlayTitle: string = ''
  @Local overlaySub: string = ''
  @Local overlayBtnText: string = ''

  // 最佳得分 (按难度)
  @Local bestScore: number = -1
  @Local bestScoresLoaded: boolean = false

  // 已答态恢复用
  @Local prevCompleted: boolean = false
  @Local prevScore: number = 0

  private snakeBody: GridPos[] = []
  private dir: GridPos = makePos(1, 0)
  private dirQueue: GridPos[] = []
  private food: GridPos = makePos(12, 8)
  private gold: GridPos | null = null
  private goldExpireAt: number = 0
  private lastEatAt: number = 0
  private startTime: number = 0
  private popups: ScorePopup[] = []

  // 计时器
  private renderTimerId: number = -1
  private countdownTimerId: number = -1
  private lastTickTs: number = 0
  private acc: number = 0

  // Canvas (HandwritingCard 先例: onReady + onAreaChange 捕获 vp 尺寸)
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  )
  private canvasWidth: number = 0

  // CardShell 外壳配置/状态 (direct 模式: usesConfirm=false, feedbackAboveSlot 棋盘卡庆祝横幅位)
  @Local shellConfig: CardShellConfig = {
    title: '贪吃蛇',
    subtitle: '',
    icon: $r('sys.symbol.dot_grid_2x2'),
    stem: '',
    hasAudio: false,
    usesConfirm: false,
    feedbackTitleCorrect: '游戏结束',
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
      difficulty = Math.max(1, Math.min(3, raw))
    } catch (_e) {
      difficulty = 1
    }
    this.difficulty = difficulty
    this.levelName = SNAKE_LEVELS[difficulty - 1].name
    this.quizOk = true

    if (this.isAnswered && this.answeredPayload !== '') {
      this.restoreAnsweredState(difficulty)
    } else {
      this.initNewGame()
    }

    this.shellConfig = {
      title: '贪吃蛇',
      subtitle: `${this.levelName} · 16×16`,
      icon: $r('sys.symbol.dot_grid_2x2'),
      stem: '吃苹果变长，连着吃连击分更高，金色星星 ×5',
      hasAudio: false,
      usesConfirm: false,
      feedbackTitleCorrect: '游戏结束',
      correctAnswerLabel: '',
      feedbackAboveSlot: true,
      usesGiveUp: true,
      giveUpLabel: ''
    }

    // 最佳得分异步加载, 完成前禁用保存 (竞态守卫, 镜像 MemoryMatchCard)
    if (!this.isAnswered) {
      void this.loadBestScores(difficulty)
    }
  }

  aboutToDisappear(): void {
    this.clearAllTimers()
  }

  // ---- 开局 / 恢复 ----

  private initNewGame(): void {
    this.resetGame()
    this.gamePhase = 'idle'
    this.showStartOverlay()
  }

  private resetGame(): void {
    this.snakeBody = [makePos(5, 8), makePos(4, 8), makePos(3, 8)]
    this.dir = makePos(1, 0)
    this.dirQueue = []
    this.food = makePos(12, 8)
    this.gold = null
    this.goldExpireAt = 0
    this.popups = []
    this.score = 0
    this.combo = 1
    this.snakeLength = 3
    this.applesEaten = 0
    this.goldStars = 0
    this.bestCombo = 1
    this.elapsedSeconds = 0
    this.startTime = 0
    this.lastEatAt = Date.now()
    this.acc = 0
  }

  private restoreAnsweredState(difficulty: number): void {
    // 已答态: 棋面 payload 不携带, 按确定性初始局面绘制作汇总视图 (同 NumberPuzzleCard
    // 还原 solvedBoard 思路), HUD 显示最终成绩。
    let completed = true
    try {
      const prev = JSON.parse(this.answeredPayload) as SnakeGameResult
      completed = prev.completed === true
      this.prevScore = prev.score ?? 0
      this.score = this.prevScore
      this.applesEaten = prev.apples_eaten ?? 0
      this.goldStars = prev.gold_stars ?? 0
      this.bestCombo = prev.best_combo ?? 1
      this.snakeLength = prev.length ?? 3
      this.elapsedSeconds = prev.time_seconds ?? 0
      if (prev.level_name !== undefined && prev.level_name !== '') {
        this.levelName = prev.level_name
      }
    } catch (_e) {
      // payload 缺失: 按已完成展示, 不渲染对错横幅
      this.shellState.feedbackSuppressed = true
    }
    this.prevCompleted = completed

    this.resetGame()
    this.gamePhase = 'over'
    this.overlayShow = false

    this.shellState.isFinished = true
    this.shellState.submitted = true
    this.shellState.isCorrect = this.prevCompleted
    this.shellState.feedbackTitle = this.getBannerTitle()
    this.shellState.feedbackDetail = this.getBannerSub()
    this.shellState.headPill = this.prevCompleted ? '已完成' : '已放弃'
    this.shellState.headPillColor = this.prevCompleted ? SUCCESS_GREEN : GIVEUP_ORANGE

    // 恢复历史最佳徽章 (只读展示)
    const prefs = getPreferencesService()
    prefs.getNumber(PreferenceKeys.SNAKE_BEST_SCORE_PREFIX + difficulty.toString(), -1)
      .then((best: number) => {
        if (best >= 0) {
          this.shellState.headBadge = `🏆 最佳 ${best}`
        }
      })
      .catch((_e: Object) => {})
  }

  // ---- 主循环 (HTML loop 结构的等价简化: 渲染 tick + 逻辑步进累加) ----

  private startRenderLoop(): void {
    this.stopRenderLoop()
    this.lastTickTs = Date.now()
    this.acc = 0
    this.renderTimerId = setInterval(() => {
      this.renderTick()
    }, RENDER_TICK_MS)
  }

  private stopRenderLoop(): void {
    if (this.renderTimerId >= 0) {
      clearInterval(this.renderTimerId)
      this.renderTimerId = -1
    }
  }

  private renderTick(): void {
    const now = Date.now()
    const dt = Math.min(48, now - this.lastTickTs)
    this.lastTickTs = now
    if (this.gamePhase === 'playing') {
      this.acc += dt
      while (this.acc >= this.currentIntervalMs()) {
        this.acc -= this.currentIntervalMs()
        this.step()
        if (this.gamePhase !== 'playing') {
          break
        }
      }
      if (this.combo > 1 && now - this.lastEatAt > COMBO_RESET_MS) {
        this.combo = 1
      }
      if (this.gold !== null && now >= this.goldExpireAt) {
        this.gold = null
      }
      if (this.startTime > 0) {
        this.elapsedSeconds = Math.floor((now - this.startTime) / 1000)
      }
    }
    this.updatePopups(dt)
    this.redraw()
  }

  /** 当前步进间隔: 基础速度随得分加快 (镜像原型 speedFor) */
  private currentIntervalMs(): number {
    const base = SNAKE_LEVELS[this.difficulty - 1].baseSpeedMs
    return Math.max(SPEED_FLOOR_MS, base - this.score * SPEED_RAMP_PER_POINT)
  }

  // ---- 棋局逻辑 (镜像原型 step) ----

  private step(): void {
    // 应用方向队列: 跳过反向/同向输入
    while (this.dirQueue.length > 0) {
      const d = this.dirQueue.shift()
      if (d === undefined) {
        break
      }
      const isReverse = d.x === -this.dir.x && d.y === -this.dir.y
      const isSame = d.x === this.dir.x && d.y === this.dir.y
      if (!isReverse && !isSame) {
        this.dir = d
        break
      }
    }

    const head = this.snakeBody[0]
    const nx = head.x + this.dir.x
    const ny = head.y + this.dir.y
    if (nx < 0 || ny < 0 || nx >= GRID || ny >= GRID || this.hitsSnake(nx, ny)) {
      this.handleGameOver()
      return
    }

    this.snakeBody.unshift(makePos(nx, ny))
    let ate = false
    if (nx === this.food.x && ny === this.food.y) {
      ate = true
      this.applyCombo()
      this.applesEaten += 1
      this.score += this.combo
      this.addPopup('+' + this.combo, nx, ny, POPUP_APPLE)
      this.placeFood()
      this.maybeGold()
    } else if (this.gold !== null && nx === this.gold.x && ny === this.gold.y) {
      ate = true
      this.applyCombo()
      this.goldStars += 1
      this.score += this.combo * 5
      // 金星额外长 1 节 (与原型一致: unshift + 补尾)
      const tail = this.snakeBody[this.snakeBody.length - 1]
      this.snakeBody.push(makePos(tail.x, tail.y))
      this.addPopup('+' + (this.combo * 5), nx, ny, GOLD_STAR)
      this.gold = null
      this.goldExpireAt = 0
    }
    if (!ate) {
      this.snakeBody.pop()
    }
    this.snakeLength = this.snakeBody.length
  }

  private applyCombo(): void {
    const now = Date.now()
    this.combo = (now - this.lastEatAt < COMBO_WINDOW_MS) ? Math.min(this.combo + 1, COMBO_MAX) : 1
    this.lastEatAt = now
    if (this.combo > this.bestCombo) {
      this.bestCombo = this.combo
    }
  }

  private hitsSnake(headX: number, headY: number): boolean {
    // 与原型一致: 排除尾节 (不进食时尾节让位)
    for (let i = 0; i < this.snakeBody.length - 1; i++) {
      if (this.snakeBody[i].x === headX && this.snakeBody[i].y === headY) {
        return true
      }
    }
    return false
  }

  /** 从蛇身 + 苹果 + 金星之外的空格随机取一格; 无空格返回 (0,0) 兜底 */
  private randomFreeCell(): GridPos {
    const occupied: boolean[] = []
    for (let i = 0; i < GRID * GRID; i++) {
      occupied.push(false)
    }
    for (let i = 0; i < this.snakeBody.length; i++) {
      occupied[this.snakeBody[i].y * GRID + this.snakeBody[i].x] = true
    }
    occupied[this.food.y * GRID + this.food.x] = true
    if (this.gold !== null) {
      occupied[this.gold.y * GRID + this.gold.x] = true
    }
    const free: number[] = []
    for (let i = 0; i < GRID * GRID; i++) {
      if (!occupied[i]) {
        free.push(i)
      }
    }
    if (free.length === 0) {
      return makePos(0, 0)
    }
    const idx = free[Math.floor(Math.random() * free.length)]
    return makePos(idx % GRID, Math.floor(idx / GRID))
  }

  private placeFood(): void {
    this.food = this.randomFreeCell()
  }

  private maybeGold(): void {
    if (this.gold !== null) {
      return
    }
    if (Math.random() > GOLD_CHANCE) {
      return
    }
    this.gold = this.randomFreeCell()
    this.goldExpireAt = Date.now() + GOLD_TTL_MS
  }

  // ---- 输入 ----

  private pushDir(dx: number, dy: number): void {
    const last = this.dirQueue.length > 0 ? this.dirQueue[this.dirQueue.length - 1] : this.dir
    const isReverse = dx === -last.x && dy === -last.y
    const isSame = dx === last.x && dy === last.y
    if (isReverse || isSame) {
      return
    }
    if (this.dirQueue.length < 2) {
      this.dirQueue.push(makePos(dx, dy))
    }
  }

  private handleDirInput(dx: number, dy: number): void {
    if (this.isAnswered || this.gamePhase === 'idle' || this.gamePhase === 'over' || this.gamePhase === 'countdown') {
      return
    }
    if (this.gamePhase === 'paused') {
      this.togglePause()
    }
    this.pushDir(dx, dy)
  }

  private togglePause(): void {
    if (this.gamePhase === 'playing') {
      this.gamePhase = 'paused'
      this.overlayCount = ''
      this.overlayTitle = '已暂停'
      this.overlaySub = ''
      this.overlayBtnText = '继续'
      this.overlayShow = true
    } else if (this.gamePhase === 'paused') {
      this.gamePhase = 'playing'
      this.acc = 0
      this.lastTickTs = Date.now()
      this.lastEatAt = Date.now()
      this.overlayShow = false
    }
  }

  // ---- 开局 / 倒计时 ----

  private startGame(): void {
    if (this.countdownTimerId >= 0) {
      clearTimeout(this.countdownTimerId)
      this.countdownTimerId = -1
    }
    this.resetGame()
    this.gamePhase = 'countdown'
    this.countdownIdx = 0
    this.overlaySub = ''
    this.overlayBtnText = ''
    this.overlayShow = true
    this.countdownStep()
  }

  private countdownIdx: number = 0

  private countdownStep(): void {
    if (this.gamePhase !== 'countdown') {
      return
    }
    const seq: string[] = ['3', '2', '1', '出发！']
    if (this.countdownIdx < seq.length) {
      this.overlayCount = seq[this.countdownIdx]
      this.overlayTitle = ''
      this.countdownIdx++
      const delay = this.countdownIdx === seq.length ? 520 : 640
      this.countdownTimerId = setTimeout(() => {
        this.countdownTimerId = -1
        this.countdownStep()
      }, delay)
    } else {
      this.overlayCount = ''
      this.overlayTitle = ''
      this.overlayShow = false
      this.gamePhase = 'playing'
      this.startTime = Date.now()
      this.lastEatAt = Date.now()
      this.startRenderLoop()
    }
  }

  private showStartOverlay(): void {
    this.overlayCount = ''
    this.overlayTitle = '贪吃蛇'
    this.overlaySub = '吃苹果变长，金星限时 5 倍分'
    this.overlayBtnText = '开始游戏'
    this.overlayShow = true
  }

  private handleOverlayButton(): void {
    if (this.gamePhase === 'paused') {
      this.togglePause()
      return
    }
    if (this.gamePhase === 'idle') {
      this.startGame()
    }
  }

  // ---- 结算 ----

  private handleGameOver(): void {
    if (this.gamePhase !== 'playing') {
      return
    }
    this.gamePhase = 'over'
    this.combo = 1
    this.stopRenderLoop()
    this.elapsedSeconds = this.startTime > 0 ? Math.floor((Date.now() - this.startTime) / 1000) : this.elapsedSeconds
    void this.saveBestScoreIfImproved()
    this.redraw()

    const isNewBest = this.isNewBest()
    this.shellState.isFinished = true
    this.shellState.submitted = true
    this.shellState.isCorrect = true
    this.shellState.feedbackTitle = isNewBest ? '新纪录！' : '游戏结束'
    this.shellState.feedbackDetail = this.getBannerSub()
    this.shellState.feedbackBadge = isNewBest ? '新纪录' : ''
    this.shellState.headPill = '已完成'
    this.shellState.headPillColor = SUCCESS_GREEN
    this.submitAnswer(true)
  }

  private handleGiveUp(): void {
    if (this.isAnswered || this.gamePhase === 'over') {
      return
    }
    this.gamePhase = 'over'
    if (this.countdownTimerId >= 0) {
      clearTimeout(this.countdownTimerId)
      this.countdownTimerId = -1
    }
    this.stopRenderLoop()
    this.overlayShow = false

    this.shellState.isFinished = true
    this.shellState.submitted = true
    this.shellState.isCorrect = false
    this.shellState.feedbackTitle = '没关系，下次再试试～'
    this.shellState.feedbackDetail = this.getBannerSub()
    this.shellState.headPill = '已放弃'
    this.shellState.headPillColor = GIVEUP_ORANGE
    this.submitAnswer(false)
  }

  private submitAnswer(completed: boolean): void {
    const payload: SnakeGameResult = {
      difficulty: this.difficulty,
      level_name: this.levelName,
      grid_size: '16×16',
      score: this.score,
      apples_eaten: this.applesEaten,
      gold_stars: this.goldStars,
      best_combo: this.bestCombo,
      length: this.snakeLength,
      time_seconds: Math.max(0, Math.floor(this.elapsedSeconds)),
      completed: completed
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private getBannerTitle(): string {
    if (this.gamePhase === 'over' && this.shellState.isCorrect) {
      return this.isNewBest() && this.bestScore >= 0 ? '新纪录！' : '游戏结束'
    }
    if (this.prevCompleted) {
      return '游戏结束'
    }
    return '没关系，下次再试试～'
  }

  private getBannerSub(): string {
    const best = this.bestScore >= 0 ? ` · 最佳 ${this.bestScore}` : ''
    return `得分 ${this.score}${best} · 苹果 ${this.applesEaten} · 金星 ${this.goldStars}`
  }

  // ---- 最佳得分 (按难度, bestScoresLoaded 竞态守卫镜像 MemoryMatchCard) ----

  private isNewBest(): boolean {
    if (!this.bestScoresLoaded || this.bestScore < 0) {
      return false
    }
    return this.score > this.bestScore
  }

  private async loadBestScores(difficulty: number): Promise<void> {
    const prefs = getPreferencesService()
    try {
      this.bestScore = await prefs.getNumber(PreferenceKeys.SNAKE_BEST_SCORE_PREFIX + difficulty.toString(), -1)
      this.bestScoresLoaded = true
    } catch (_e) {
      this.bestScore = -1
      this.bestScoresLoaded = true
    }
    if (this.bestScore >= 0) {
      this.shellState.headBadge = `🏆 最佳 ${this.bestScore}`
    }
  }

  private async saveBestScoreIfImproved(): Promise<void> {
    if (!this.bestScoresLoaded) {
      // 未加载完 → 放弃本次保存 (罕见竞态), 优于覆盖真实记录
      return
    }
    if (this.score <= 0 || this.score <= this.bestScore) {
      return
    }
    const prefs = getPreferencesService()
    try {
      await prefs.setNumber(PreferenceKeys.SNAKE_BEST_SCORE_PREFIX + this.difficulty.toString(), this.score)
      this.bestScore = this.score
      this.shellState.headBadge = `🏆 最佳 ${this.bestScore}`
    } catch (_e) {
      // 持久化失败静默: 星星与 AI 回执不受影响
    }
  }

  // ---- 计时器管理 ----

  private clearAllTimers(): void {
    this.stopRenderLoop()
    if (this.countdownTimerId >= 0) {
      clearTimeout(this.countdownTimerId)
      this.countdownTimerId = -1
    }
  }

  // ---- 飘字 ----

  private addPopup(text: string, gridX: number, gridY: number, color: string): void {
    this.popups.push(makePopup(text, gridX, gridY, color))
  }

  private updatePopups(dt: number): void {
    for (let i = this.popups.length - 1; i >= 0; i--) {
      this.popups[i].life -= dt / 900
      if (this.popups[i].life <= 0) {
        this.popups.splice(i, 1)
      }
    }
  }

  // ---- Canvas 绘制 (镜像原型 draw 函数) ----

  private redraw(): void {
    const ctx = this.canvasContext
    const w = this.canvasWidth
    if (w <= 0) {
      return
    }
    const cell = w / GRID

    ctx.fillStyle = BOARD_BG
    ctx.fillRect(0, 0, w, w)

    // 网格定位点 (原型 drawBoardBg)
    ctx.fillStyle = 'rgba(255,255,255,0.05)'
    const dotR = Math.max(1, cell * 0.05)
    for (let gx = 0; gx < GRID; gx++) {
      for (let gy = 0; gy < GRID; gy++) {
        ctx.beginPath()
        ctx.arc(gx * cell + cell / 2, gy * cell + cell / 2, dotR, 0, Math.PI * 2)
        ctx.fill()
      }
    }

    if (this.gold !== null) {
      this.drawStar(ctx, this.gold.x * cell + cell / 2, this.gold.y * cell + cell / 2, cell * 0.34)
    }
    this.drawApple(ctx, this.food.x * cell + cell / 2, this.food.y * cell + cell / 2, cell * 0.32)
    this.drawSnake(ctx, cell)
    this.drawPopups(ctx, cell)
  }

  private roundRectPath(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
    ctx.beginPath()
    ctx.moveTo(x + r, y)
    ctx.arcTo(x + w, y, x + w, y + h, r)
    ctx.arcTo(x + w, y + h, x, y + h, r)
    ctx.arcTo(x, y + h, x, y, r)
    ctx.arcTo(x, y, x + w, y, r)
    ctx.closePath()
  }

  private drawApple(ctx: CanvasRenderingContext2D, cx: number, cy: number, rad: number): void {
    ctx.save()
    ctx.fillStyle = APPLE_RED
    ctx.beginPath()
    ctx.arc(cx, cy + rad * 0.12, rad, 0, Math.PI * 2)
    ctx.fill()
    ctx.fillStyle = 'rgba(255,255,255,0.4)'
    ctx.beginPath()
    ctx.arc(cx - rad * 0.3, cy - rad * 0.25, rad * 0.22, 0, Math.PI * 2)
    ctx.fill()
    ctx.strokeStyle = APPLE_STEM
    ctx.lineWidth = Math.max(1.4, rad * 0.14)
    ctx.lineCap = 'round'
    ctx.beginPath()
    ctx.moveTo(cx, cy - rad * 0.85)
    ctx.lineTo(cx, cy - rad * 1.18)
    ctx.stroke()
    ctx.fillStyle = APPLE_LEAF
    ctx.beginPath()
    ctx.ellipse(cx + rad * 0.3, cy - rad * 1.02, rad * 0.42, rad * 0.2, -0.6, 0, Math.PI * 2)
    ctx.fill()
    ctx.restore()
  }

  private drawStar(ctx: CanvasRenderingContext2D, cx: number, cy: number, radius: number): void {
    ctx.save()
    ctx.fillStyle = GOLD_STAR
    ctx.beginPath()
    const points = 5
    for (let i = 0; i < points * 2; i++) {
      const ang = -Math.PI / 2 + i * Math.PI / points
      const rad = (i % 2) ? radius * 0.45 : radius
      const px = cx + Math.cos(ang) * rad
      const py = cy + Math.sin(ang) * rad
      if (i === 0) {
        ctx.moveTo(px, py)
      } else {
        ctx.lineTo(px, py)
      }
    }
    ctx.closePath()
    ctx.fill()
    ctx.strokeStyle = 'rgba(255,255,255,0.55)'
    ctx.lineWidth = Math.max(1, radius * 0.1)
    ctx.stroke()
    ctx.restore()
  }

  private drawSnake(ctx: CanvasRenderingContext2D, cell: number): void {
    if (this.snakeBody.length === 0) {
      return
    }
    for (let i = this.snakeBody.length - 1; i >= 0; i--) {
      const s = this.snakeBody[i]
      const pad = cell * 0.1
      ctx.fillStyle = i === 0 ? SNAKE_HEAD : (i % 2 ? SNAKE_BODY_A : SNAKE_BODY_B)
      this.roundRectPath(ctx, s.x * cell + pad, s.y * cell + pad, cell - pad * 2, cell - pad * 2, cell * 0.3)
      ctx.fill()
    }
    // 蛇眼 (原型: 沿行进方向前置 + 垂直偏移)
    const h = this.snakeBody[0]
    const cx = h.x * cell + cell / 2
    const cy = h.y * cell + cell / 2
    const fwd = cell * 0.16
    const side = cell * 0.17
    const er = Math.max(1.6, cell * 0.09)
    const px = -this.dir.y
    const py = this.dir.x
    ctx.fillStyle = EYE_INK
    ctx.beginPath()
    ctx.arc(cx + this.dir.x * fwd + px * side, cy + this.dir.y * fwd + py * side, er, 0, Math.PI * 2)
    ctx.fill()
    ctx.beginPath()
    ctx.arc(cx + this.dir.x * fwd - px * side, cy + this.dir.y * fwd - py * side, er, 0, Math.PI * 2)
    ctx.fill()
  }

  private drawPopups(ctx: CanvasRenderingContext2D, cell: number): void {
    if (this.popups.length === 0) {
      return
    }
    ctx.textAlign = 'center'
    ctx.font = `800 ${Math.round(cell * 0.72)}px sans-serif`
    for (let i = 0; i < this.popups.length; i++) {
      const p = this.popups[i]
      const floatUp = (1 - Math.max(0, p.life)) * cell * 0.6
      ctx.globalAlpha = Math.max(0, p.life)
      ctx.fillStyle = p.color
      ctx.fillText(p.text, p.gridX * cell + cell / 2, p.gridY * cell - cell * 0.1 - floatUp)
    }
    ctx.globalAlpha = 1
    ctx.textAlign = 'start'
  }

  // ---- 视图 ----

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
        this.BoardArea()
        if (!this.isAnswered) {
          this.DpadArea()
        }
      }
    }
  }

  @Builder
  HudRow() {
    Row({ space: 12 }) {
      Text(`得分 ${this.score}`)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(`连击 x${this.combo}`)
        .fontSize(11)
        .fontColor(this.combo > 1 ? '#FF6B6B' : $r('app.color.text_tertiary'))
      Text(`长度 ${this.snakeLength}`)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
      Blank()
      if (this.gamePhase === 'playing' || this.gamePhase === 'paused') {
        Button(this.gamePhase === 'paused' ? '继续' : '暂停')
          .fontSize(11)
          .fontColor(Color.White)
          .backgroundColor(this.themePrimary)
          .borderRadius(999)
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .onClick(() => {
            this.togglePause()
          })
      }
    }
    .width('100%')
  }

  @Builder
  BoardArea() {
    Stack({ alignContent: Alignment.Center }) {
      Canvas(this.canvasContext)
        .width('100%')
        .height('100%')
        .onReady(() => {
          this.redraw()
        })
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.canvasWidth = newArea.width as number
          this.redraw()
        })

      if (this.overlayShow) {
        this.BoardOverlay()
      }
    }
    .width('100%')
    .aspectRatio(1)
    .borderRadius(16)
    .backgroundColor(BOARD_BG)
    .constraintSize({ maxWidth: 340 })
    .alignSelf(ItemAlign.Center)
    .onTouch((e: TouchEvent) => {
      e.stopPropagation()
    })
    .priorityGesture(
      PanGesture({ direction: PanDirection.All, distance: 10 })
        .onActionEnd((event: GestureEvent) => {
          if (this.isAnswered) {
            return
          }
          const offsetX = event.offsetX as number
          const offsetY = event.offsetY as number
          if (Math.abs(offsetX) < 10 && Math.abs(offsetY) < 10) {
            return
          }
          if (Math.abs(offsetX) > Math.abs(offsetY)) {
            this.handleDirInput(offsetX > 0 ? 1 : -1, 0)
          } else {
            this.handleDirInput(0, offsetY > 0 ? 1 : -1)
          }
        })
    )
  }

  @Builder
  BoardOverlay() {
    Column({ space: 10 }) {
      if (this.overlayCount !== '') {
        Text(this.overlayCount)
          .fontSize(56)
          .fontWeight(FontWeight.Bolder)
          .fontColor(GOLD_STAR)
      }
      if (this.overlayTitle !== '') {
        Text(this.overlayTitle)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
      }
      if (this.overlaySub !== '') {
        Text(this.overlaySub)
          .fontSize(13)
          .fontColor(OVERLAY_SUB)
          .textAlign(TextAlign.Center)
      }
      if (this.overlayBtnText !== '') {
        Button(this.overlayBtnText)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(EYE_INK)
          .backgroundColor(GOLD_STAR)
          .borderRadius(18)
          .padding({ left: 26, right: 26, top: 10, bottom: 10 })
          .onClick(() => {
            this.handleOverlayButton()
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(16,27,51,0.82)')
    .borderRadius(16)
  }

  @Builder
  DpadArea() {
    Column({ space: 10 }) {
      Row() {
        this.DirButton(180, 0, -1, '向上')
      }
      Row({ space: 10 }) {
        this.DirButton(90, -1, 0, '向左')
        this.DirButton(0, 0, 1, '向下')
        this.DirButton(-90, 1, 0, '向右')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .constraintSize({ maxWidth: 300 })
    .alignSelf(ItemAlign.Center)
  }

  /** chevron_down 旋转出四向 (whitelist symbol; down=0 / left=90 / right=-90 / up=180) */
  @Builder
  DirButton(angle: number, dx: number, dy: number, a11y: string) {
    Button() {
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(24)
        .fontColor([$r('app.color.text_primary')])
        .rotate({ angle: angle })
    }
    .width(64)
    .height(50)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.divider') })
    .accessibilityText(a11y)
    .onClick(() => {
      this.handleDirInput(dx, dy)
    })
  }
}
