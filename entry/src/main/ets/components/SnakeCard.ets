/**
 * SnakeCard - 贪吃蛇互动卡片
 *
 * 参考 docs/tanshishe.html 原型: 16×16 网格上方向键/屏幕按钮/手指滑动三种方式控制小蛇,
 * 吃红苹果变长并得连击分, 金色星星限时出现值 5×连击分。硬墙模式: 撞到边界或自己的
 * 身体直接结束。难度 1-3 由老师(小星老师/小星游戏老师)经工具参数决定, 每档 =
 * 基础速度 × 目标果子数 (1=慢慢爬·8 颗, 2=正常速·12 颗, 3=飞快·16 颗),
 * 吃满目标果子过关(果园大通关); 速度随吃到的果子逐渐加快。
 *
 * CardShell 统一外壳 (feedbackAboveSlot 棋盘卡范式, 镜像 MemoryMatchCard),
 * direct 模式 (usesConfirm: false)。挂到 kids_games (小星游戏老师),
 * 与 number_puzzle/maze/sudoku/memory_match 同属益智游戏族,
 * 锻炼 logic_thinking / spatial_reasoning (反应速度 + 方向规划)。
 *
 * - 棋局在卡片内部运行 (镜像 number_puzzle 模式, 不经 handler 注入)
 * - 渲染走 Canvas (镜像 HTML 原型的 draw 函数; HandwritingCard 先例),
 *   50ms 渲染 tick + 逻辑步进累加器 (HTML requestAnimationFrame 结构的等价简化)
 *   + 逐帧插值 (alpha = acc / interval, 镜像原型 state.alpha 补间)
 * - 【单独玩 session 模型】孩子独自面对卡片, 没有任何人在旁边帮忙重开。因此一局结束
 *   不再提交回执, 而是累计进本次 session 并弹出「再来一局 / 玩够了」; 只有孩子点
 *   「玩够了」、走 CardShell 放弃链、或卡片被销毁 (aboutToDisappear 兜底) 时才提交
 *   一次回执。回执取「最好一局」作为 score/apples 主字段 (与历史 payload 语义一致),
 *   另带 rounds / session_apples 聚合字段。原因: 一旦提交, approvalState 变 answered,
 *   MessageBubble.shouldRenderSnakeGameInteractionCard 返回 false, 整张卡片从消息流
 *   消失 —— 单独玩的孩子会直接失去游戏, 这是不可接受的结构缺陷。
 * - 死亡有反馈: 撞墙/撞己时进 'dying' 相位, 蛇身从尾到头缩散 + 头部闪红 + 粒子爆散,
 *   约 420ms 后才落结算横幅 (原实现是画面直接冻住, 孩子分不清「撞了」还是「卡了」)
 * - 控制入口: D-pad 方向按钮 (真实 Button, 防 List 滚动吞点击) + 棋盘滑动
 *   (priorityGesture + onTouch stopPropagation, 镜像 NumberPuzzleCard §6.3)
 *   + 键盘方向键 (棋盘 focusable + focusOnTouch + onKeyEvent, 开局/恢复时
 *   requestFocus; 点棋盘也可重新聚焦)
 * - 最佳得分按难度持久化 (snake_best_score_<difficulty>, bestScoresLoaded 竞态守卫
 *   镜像 MemoryMatchCard); 星级由 StarRewardService 计算: 吃满 4 颗给 1 星,
 *   难度 1/2 通关给 2 星, 难度 3 通关给 3 星, 不足 4 颗或放弃 0 星
 *   (session 模型下 won 取「本次最好一局是否通关」, 见 submitAnswer)
 * - 音效不做 (HTML 的 WebAudio 在 ArkTS 无对应简单基建), 保留 +N 得分飘字
 *
 * aboutToAppear 做防御性难度 clamp (双保险, 历史消息渲染不经 handler)。
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { getPreferencesService, PreferenceKeys } from '../services/PreferencesService'
import { KeyCode } from '@ohos.multimodalInput.keyCode'
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
  /** 本档目标果子数 (难度 = 速度 × 果子数) */
  target_fruits: number
  /** 吃满目标果子过关 (果园大通关) */
  won: boolean
  gold_stars: number
  best_combo: number
  length: number
  time_seconds: number
  completed: boolean
  /** session 模型新增: 本次一共玩了几局 (旧 payload 无此字段, 缺省按 1 局) */
  rounds?: number
  /** session 模型新增: 各局吃到的果子总数 (跨局累计, 与 apples_eaten 区分) */
  session_apples?: number
}

interface SnakeLevel {
  difficulty: number
  name: string
  baseSpeedMs: number
  /** 过关所需果子数 (难度系数的第二维度) */
  targetFruits: number
}

/** 难度表: 与工具 schema description 严格一致 (BuiltinTools.createSnakeGameToolDefinition) */
const SNAKE_LEVELS: SnakeLevel[] = [
  { difficulty: 1, name: '慢慢爬', baseSpeedMs: 210, targetFruits: 8 },
  { difficulty: 2, name: '正常速', baseSpeedMs: 180, targetFruits: 12 },
  { difficulty: 3, name: '飞快', baseSpeedMs: 150, targetFruits: 16 }
]

const GRID: number = 16
/** 连击窗口: 距上次进食 < 2200ms 连击 +1 (与原型一致) */
const COMBO_WINDOW_MS: number = 2200
/** 连击回落: > 2600ms 未进食回 x1 (与原型一致) */
const COMBO_RESET_MS: number = 2600
const COMBO_MAX: number = 5
/** 金星出现概率 / 存活时长。
 *  TTL 原为 6500ms, 但 16×16 棋盘平均曼哈顿距离约 10.6 格, 难度 3 (150ms/步)
 *  平均 1.3s 就能吃到 —— 6.5s 是白送, 金星不构成「风险/回报」决策。
 *  压到 3400ms 后需要玩家主动改道抢, 才是一个决策。
 *  [PLACEHOLDER] 3400 为按平均到达时间 1.5x 推算, 未在真机用真实滑动输入实测。
 */
const GOLD_CHANCE: number = 0.4
const GOLD_TTL_MS: number = 3400
/** 速度下限与每颗果子加速 (难度 = 基础速度 × 目标果子数; 越接近过关越快).
 *  下限原为 100ms, 但难度 3 从第 13 颗起就锁死 100ms = 10 格/秒,
 *  7 岁儿童的计划-反应延迟约 500ms (≈5 格), 后半段容错归零。
 *  抬到 130ms 保住最后 4 颗的可玩性, 同时保留「越来越快」的压迫感。
 *  [PLACEHOLDER] 130 为按儿童反应延迟粗估, 需真机 playtest 确认。
 */
const SPEED_FLOOR_MS: number = 130
const SPEED_RAMP_PER_FRUIT: number = 4
/** 渲染 tick 间隔 (HTML requestAnimationFrame 的简化等价) */
const RENDER_TICK_MS: number = 50
/** 死亡动画时长: 蛇身缩散 + 头部闪红, 播完才落结算横幅 */
const DEATH_ANIM_MS: number = 420
/** 胜利后停留时长: 让通关爆散粒子播完再弹覆盖层 (否则粒子被遮住, 赢了毫无反馈) */
const WIN_TAIL_MS: number = 300
/** 金星到期前开始闪烁的剩余时间: 没有预警的金星 = 孩子看着它凭空消失 */
const GOLD_WARN_MS: number = 1100
/** 方向键按下反馈的持续时长 */
const DIR_ACK_MS: number = 130
/** 滑动判定阈值 (vp): 与 PanGesture distance 一致, 避免手指微小抖动误触发 */
const SWIPE_MIN_OFFSET: number = 14
/**
 * 拿 1 星所需的最小果子数。
 * 必须与 StarRewardService.computeStars('snake_game') 的未通关分支保持一致
 * (那边是 `eaten >= 4 ? 1 : 0`)。改一处必须改两处 —— 这里只用于结算文案播报,
 * 不影响实际授星。
 */
const STAR_THRESHOLD: number = 4

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

/** 爆散粒子 (网格坐标, 用于吃果子和死亡反馈) */
interface Spark {
  gx: number
  gy: number
  vx: number
  vy: number
  life: number
  color: string
  radius: number
}

/** 一次「死亡散架」中单节蛇身的动画参数 */
interface ShrinkSeg {
  gx: number
  gy: number
  /** 0~1, 越小越晚消失 */
  delay: number
  isHead: boolean
}

function makePos(x: number, y: number): GridPos {
  const p: GridPos = { x: x, y: y }
  return p
}

function makeSpark(gx: number, gy: number, vx: number, vy: number, color: string, radius: number): Spark {
  const s: Spark = { gx: gx, gy: gy, vx: vx, vy: vy, life: 1, color: color, radius: radius }
  return s
}

function makeShrink(gx: number, gy: number, delay: number, isHead: boolean): ShrinkSeg {
  const s: ShrinkSeg = { gx: gx, gy: gy, delay: delay, isHead: isHead }
  return s
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
  @Local targetFruits: number = 12

  // 覆盖层 (开始/倒计时/暂停/结束)
  @Local overlayShow: boolean = false
  @Local overlayCount: string = ''
  @Local overlayTitle: string = ''
  @Local overlaySub: string = ''
  @Local overlayBtnText: string = ''
  /** 结算/暂停覆盖层是否显示「玩够了」按钮 (单独玩出口; idle 开始页不显示) */
  @Local overlayShowSessionDone: boolean = false
  /** true 时覆盖层只画倒计时数字, 不铺遮罩 —— 孩子要在倒计时期间看清蛇和果子的位置 */
  @Local overlayCountdownMode: boolean = false
  /** 方向键短暂高亮反馈: 记录刚按下的方向 'up'|'down'|'left'|'right', '' 为无 */
  @Local activeDirKey: string = ''
  private dirAckTimerId: number = -1
  /** 通关尾帧定时器 */
  private winTailTimerId: number = -1
  /** 本次拖动是否已经产生过转向指令 (防一次滑动刷多条) */
  private swipeConsumed: boolean = false

  // 最佳得分 (按难度)
  @Local bestScore: number = -1
  @Local bestScoresLoaded: boolean = false

  // 已答态恢复用
  @Local prevCompleted: boolean = false
  @Local prevScore: number = 0
  private prevWon: boolean = false

  // ---- session 模型: 一局结束不提交, 累计到 session, 孩子主动「玩够了」才提交 ----
  /** 本次 session 已完成的局数 (含当前这局) */
  @Local roundsPlayed: number = 0
  /** 本次 session 跨局累计吃到的果子数 */
  @Local sessionApples: number = 0
  /** 本次 session 最好一局的成绩 (回执主字段取它, 与历史 payload 语义一致) */
  private bestRoundScore: number = -1
  private bestRoundApples: number = 0
  private bestRoundWon: boolean = false
  private bestRoundLength: number = 3
  private bestRoundGold: number = 0
  private bestRoundCombo: number = 1
  /** 本次 session 已玩过的总秒数 (跨局累加, 不含暂停) */
  private sessionSeconds: number = 0
  /** 本次 session 是否已经提交过回执 (防止重复提交) */
  private receiptSubmitted: boolean = false

  // ---- 插值/死亡动画 ----
  /** 上一逻辑步的蛇身快照 (逐帧插值用, 对应原型的 state.prevSnake) */
  private prevSnake: GridPos[] = []
  /** 当前步进进度 0~1 (acc / interval), 驱动插值 */
  private stepAlpha: number = 1
  /** dying 相位的起始时间戳 */
  private dyingSince: number = 0
  /** 死亡散架: 每节蛇身的动画参数 + 粒子 */
  private shrinkSegs: ShrinkSeg[] = []
  private sparks: Spark[] = []

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
    this.targetFruits = SNAKE_LEVELS[difficulty - 1].targetFruits
    this.quizOk = true

    if (this.isAnswered && this.answeredPayload !== '') {
      this.restoreAnsweredState(difficulty)
    } else {
      this.initNewGame()
    }

    this.shellConfig = {
      title: '贪吃蛇',
      subtitle: `${this.levelName} · 16×16 · 硬墙`,
      icon: $r('sys.symbol.dot_grid_2x2'),
      stem: `屏幕按钮/键盘方向键/滑动都能转弯，吃满 ${this.targetFruits} 颗果子过关`,
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
    // 单独玩兜底: 卡片被回收 (列表滚动/切页) 时, 已玩过的局不能静默丢失。
    // 注意与主动退出的区别: 这里只补交「确实玩过」的 session, 一局未开始就不交,
    // 避免卡片只是被回收就给孩子记一次放弃。
    if (!this.receiptSubmitted && !this.isAnswered && this.roundsPlayed > 0) {
      this.receiptSubmitted = true
      this.submitAnswer(this.bestRoundWon, false)
    }
    this.clearAllTimers()
  }

  // ---- 开局 / 恢复 ----

  private initNewGame(): void {
    this.resetGame()
    this.gamePhase = 'idle'
    this.showStartOverlay()
  }

  private resetGame(): void {
    // 插值快照先清空, 否则新局第一帧会从上局残留位置滑进来
    this.snakeBody = [makePos(5, 8), makePos(4, 8), makePos(3, 8)]
    this.prevSnake = this.snakeBody.map((p: GridPos): GridPos => makePos(p.x, p.y))
    this.stepAlpha = 1
    this.dir = makePos(1, 0)
    this.dirQueue = []
    this.food = makePos(12, 8)
    this.gold = null
    this.goldExpireAt = 0
    this.popups = []
    this.sparks = []
    this.shrinkSegs = []
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
    // 先重置棋面, 再回填最终成绩——顺序反了会被 resetGame 清零 (存量 bug 修复)
    this.resetGame()
    this.gamePhase = 'over'
    this.overlayShow = false
    // 历史态只读: 「玩够了」按钮会让已结束的卡片重新走一遍提交流程, 必须关掉
    this.overlayShowSessionDone = false
    this.receiptSubmitted = true

    // 已答态: 棋面 payload 不携带, 按确定性初始局面绘制作汇总视图 (同 NumberPuzzleCard
    // 还原 solvedBoard 思路), HUD 显示最终成绩。
    let completed = true
    try {
      const prev = JSON.parse(this.answeredPayload) as SnakeGameResult
      completed = prev.completed === true
      this.prevScore = prev.score ?? 0
      this.score = this.prevScore
      this.applesEaten = prev.apples_eaten ?? 0
      this.targetFruits = (prev.target_fruits as number) ?? SNAKE_LEVELS[difficulty - 1].targetFruits
      this.prevWon = prev.won === true
      this.goldStars = prev.gold_stars ?? 0
      this.bestCombo = prev.best_combo ?? 1
      this.snakeLength = prev.length ?? 3
      this.elapsedSeconds = prev.time_seconds ?? 0
      // session 聚合字段 (旧 payload 无 → 按 1 局回填)
      this.roundsPlayed = (prev.rounds as number) ?? 1
      this.sessionApples = (prev.session_apples as number) ?? (prev.apples_eaten ?? 0)
      if (prev.level_name !== undefined && prev.level_name !== '') {
        this.levelName = prev.level_name
      }
    } catch (_e) {
      // payload 缺失: 按已完成展示, 不渲染对错横幅
      this.shellState.feedbackSuppressed = true
    }
    this.prevCompleted = completed

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
      // guard 防负值/异常间隔导致卡死在循环里 (原型同样有 guard < 4)
      let guard = 0
      while (this.acc >= this.currentIntervalMs() && guard < 4) {
        this.acc -= this.currentIntervalMs()
        this.step()
        guard += 1
        if (this.gamePhase !== 'playing') {
          break
        }
      }
      // 插值进度: 0 → 刚走完一步, 1 → 即将走下一步 (镜像原型 state.alpha)
      this.stepAlpha = this.gamePhase === 'playing'
        ? Math.min(1, this.acc / this.currentIntervalMs())
        : 1
      if (this.combo > 1 && now - this.lastEatAt > COMBO_RESET_MS) {
        this.combo = 1
      }
      if (this.gold !== null && now >= this.goldExpireAt) {
        this.gold = null
      }
      if (this.startTime > 0) {
        this.elapsedSeconds = Math.floor((now - this.startTime) / 1000)
      }
    } else if (this.gamePhase === 'dying') {
      this.stepAlpha = 1
      if (now - this.dyingSince >= DEATH_ANIM_MS) {
        this.gamePhase = 'over'
        this.onRoundEnded(false)
      }
    } else if (this.gamePhase === 'won_tail') {
      // 通关后的粒子尾帧: 继续以渲染帧推进粒子, 但不再走逻辑步进
      this.stepAlpha = 1
    }

    this.updatePopups(dt)
    this.updateSparks(dt)
    this.redraw()
  }

  /** 当前步进间隔: 基础速度随吃到的果子加快 (越接近过关越快) */
  private currentIntervalMs(): number {
    const base = SNAKE_LEVELS[this.difficulty - 1].baseSpeedMs
    return Math.max(SPEED_FLOOR_MS, base - this.applesEaten * SPEED_RAMP_PER_FRUIT)
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
      this.beginDeath(nx, ny)
      return
    }

    // 插值快照: 记下走这一步之前的蛇身, 供逐帧补间 (镜像原型 state.prevSnake)
    this.prevSnake = this.snakeBody.map((p: GridPos): GridPos => makePos(p.x, p.y))
    this.snakeBody.unshift(makePos(nx, ny))
    let ate = false
    if (nx === this.food.x && ny === this.food.y) {
      ate = true
      this.applyCombo()
      this.applesEaten += 1
      this.score += this.combo
      this.addPopup('+' + this.combo, nx, ny, POPUP_APPLE)
      this.burstAt(nx, ny, APPLE_RED, 7)
      this.snakeLength = this.snakeBody.length
      // 吃满目标果子 → 过关 (果园大通关), 不再刷新苹果
      if (this.applesEaten >= this.targetFruits) {
        this.handleWin()
        return
      }
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
      this.burstAt(nx, ny, GOLD_STAR, 10)
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

  /**
   * 从蛇身 + 苹果 + 金星之外的空格随机取一格。
   * 额外做一次可达性检查: 长蛇 (长度 ≥ 16) 可能把自己盘成一堵墙, 把棋盘切成
   * 互不相通的区域 —— 若果子刷在蛇头到不了的那一侧, 孩子只能自杀重开。
   * 先用 BFS 从蛇头扩散, 只在可达空格里挑。无空格返回 (0,0) 兜底。
   */
  private randomFreeCell(): GridPos {
    const occupied: boolean[] = []
    for (let i = 0; i < GRID * GRID; i++) {
      occupied.push(false)
    }
    for (let i = 0; i < this.snakeBody.length; i++) {
      occupied[this.snakeBody[i].y * GRID + this.snakeBody[i].x] = true
    }
    if (this.snakeBody.length > 0) {
      const h = this.snakeBody[0]
      occupied[h.y * GRID + h.x] = true
    }
    occupied[this.food.y * GRID + this.food.x] = true
    if (this.gold !== null) {
      occupied[this.gold.y * GRID + this.gold.x] = true
    }

    // BFS 可达性 (蛇身当障碍) —— 只有 256 格, 开销可忽略
    const reachable: boolean[] = []
    for (let i = 0; i < GRID * GRID; i++) {
      reachable.push(false)
    }
    const queue: number[] = []
    const head = this.snakeBody.length > 0 ? this.snakeBody[0] : this.food
    // 蛇头本身算起点 (它是障碍, 但可达性从这里算)
    for (let d = 0; d < 4; d++) {
      const nx = head.x + (d === 0 ? 1 : (d === 1 ? -1 : 0))
      const ny = head.y + (d === 2 ? 1 : (d === 3 ? -1 : 0))
      if (nx < 0 || ny < 0 || nx >= GRID || ny >= GRID) {
        continue
      }
      const idx = ny * GRID + nx
      if (!occupied[idx] && !reachable[idx]) {
        reachable[idx] = true
        queue.push(idx)
      }
    }
    let qi = 0
    while (qi < queue.length) {
      const cur = queue[qi]
      qi += 1
      const cx = cur % GRID
      const cy = Math.floor(cur / GRID)
      for (let d = 0; d < 4; d++) {
        const nx = cx + (d === 0 ? 1 : (d === 1 ? -1 : 0))
        const ny = cy + (d === 2 ? 1 : (d === 3 ? -1 : 0))
        if (nx < 0 || ny < 0 || nx >= GRID || ny >= GRID) {
          continue
        }
        const idx = ny * GRID + nx
        if (!occupied[idx] && !reachable[idx]) {
          reachable[idx] = true
          queue.push(idx)
        }
      }
    }

    const free: number[] = []
    for (let i = 0; i < GRID * GRID; i++) {
      if (reachable[i]) {
        free.push(i)
      }
    }
    if (free.length === 0) {
      // 可达格全被占 (棋盘几乎填满): 退回全空格随机, 至少不让游戏卡死
      for (let i = 0; i < GRID * GRID; i++) {
        if (!occupied[i]) {
          free.push(i)
        }
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

  /** 方向键高亮反馈: 让「按下去了」和「真的转了」在视觉上分开 */
  private flashDirKey(dx: number, dy: number): void {
    const key = dy < 0 ? 'up' : (dy > 0 ? 'down' : (dx < 0 ? 'left' : 'right'))
    this.activeDirKey = key
    if (this.dirAckTimerId >= 0) {
      clearTimeout(this.dirAckTimerId)
    }
    this.dirAckTimerId = setTimeout(() => {
      this.dirAckTimerId = -1
      this.activeDirKey = ''
    }, DIR_ACK_MS)
  }

  private clearDirAck(): void {
    this.activeDirKey = ''
    if (this.dirAckTimerId >= 0) {
      clearTimeout(this.dirAckTimerId)
      this.dirAckTimerId = -1
    }
  }

  private handleDirInput(dx: number, dy: number): void {
    if (this.isAnswered || this.gamePhase === 'idle' || this.gamePhase === 'over'
      || this.gamePhase === 'countdown' || this.gamePhase === 'dying'
      || this.gamePhase === 'won_tail') {
      return
    }
    // 暂停时不响应方向键: 原实现在这里 togglePause() 静默恢复游戏,
    // 孩子只是想按方向键看看, 结果蛇立刻开始动、他还没准备好就撞了。
    // 恢复只能走「继续」按钮 (明确动作)。
    if (this.gamePhase === 'paused') {
      return
    }
    // 无论这次输入是否会被接受, 都先给出按键反馈:
    // 原实现把反向/同向输入静默丢弃, 孩子只会认为「按钮没反应」。
    this.flashDirKey(dx, dy)
    this.pushDir(dx, dy)
  }

  // ---- 键盘方向键 (第三控制通道: 方向键/屏幕按钮/滑动三通道等价) ----

  private handleKeyEvent(event: KeyEvent): void {
    if (event.type !== KeyType.Down) {
      return
    }
    let dx = 0
    let dy = 0
    if (event.keyCode === KeyCode.KEYCODE_DPAD_UP) {
      dy = -1
    } else if (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
      dy = 1
    } else if (event.keyCode === KeyCode.KEYCODE_DPAD_LEFT) {
      dx = -1
    } else if (event.keyCode === KeyCode.KEYCODE_DPAD_RIGHT) {
      dx = 1
    } else {
      return
    }
    event.stopPropagation()
    this.handleDirInput(dx, dy)
  }

  /** 开局/恢复时把焦点移到棋盘, 让键盘方向键立即生效 (失败由 focusOnTouch 兜底) */
  private focusBoard(): void {
    try {
      this.getUIContext().getFocusController().requestFocus('snakeBoard')
    } catch (_e) {
      // 焦点请求失败静默: 点一下棋盘也能聚焦
    }
  }

  private togglePause(): void {
    if (this.gamePhase === 'playing') {
      this.gamePhase = 'paused'
      // 暂停时停掉渲染循环: 覆盖层挡住棋盘, 继续 50ms 空重绘 256 个圆点纯耗电
      this.stopRenderLoop()
      this.overlayCount = ''
      this.overlayTitle = '已暂停'
      this.overlaySub = ''
      this.overlayBtnText = '继续'
      this.overlayShowSessionDone = true
      this.overlayShow = true
    } else if (this.gamePhase === 'paused') {
      this.gamePhase = 'playing'
      this.acc = 0
      this.lastTickTs = Date.now()
      this.lastEatAt = Date.now()
      this.overlayShow = false
      this.overlayShowSessionDone = false
      this.startRenderLoop()
      this.focusBoard()
    }
  }

  // ---- 开局 / 倒计时 ----

  private startGame(): void {
    if (this.countdownTimerId >= 0) {
      clearTimeout(this.countdownTimerId)
      this.countdownTimerId = -1
    }
    this.resetGame()
    // 必须立刻重绘: resetGame 只改数据不画布, 而倒计时期间渲染循环还没启动,
    // 不补这一下棋盘会停在上一局的散架残影上 (倒计时不遮罩后尤其明显)
    this.redraw()
    this.gamePhase = 'countdown'
    this.countdownIdx = 0
    this.overlaySub = ''
    this.overlayBtnText = ''
    this.overlayShowSessionDone = false
    // 倒计时只叠数字、不铺遮罩: 孩子需要在这 2 秒里看清蛇头朝向和果子位置,
    // 为第一个转弯做规划。原实现整块盖死, 等于把最需要观察的时刻遮掉了。
    this.overlayCountdownMode = true
    this.overlayShow = true
    this.clearDirAck()
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
      this.overlayCountdownMode = false
      this.overlayShow = false
      this.gamePhase = 'playing'
      this.startTime = Date.now()
      this.lastEatAt = Date.now()
      this.startRenderLoop()
      this.focusBoard()
    }
  }

  private showStartOverlay(): void {
    this.overlayCount = ''
    this.overlayTitle = '贪吃蛇'
    this.overlaySub = `吃满 ${this.targetFruits} 颗果子过关 · 撞墙或撞到自己都结束`
    this.overlayBtnText = '开始游戏'
    this.overlayShowSessionDone = false
    this.overlayCountdownMode = false
    this.overlayShow = true
  }

  private handleOverlayButton(): void {
    if (this.gamePhase === 'paused') {
      this.togglePause()
      return
    }
    if (this.gamePhase === 'idle') {
      this.startGame()
      return
    }
    // 一局结束后的「再来一局」: 单独玩的核心通路, 不能要求孩子回去找 AI
    if (this.gamePhase === 'over' && !this.isAnswered) {
      this.startGame()
    }
  }

  // ---- 结算 (session 模型: 一局结束不提交, 累计后弹出重开) ----

  /**
   * 撞墙/撞到自己: 先播死亡散架动画, 动画结束才落结算。
   * 原实现直接改 phase 冻屏, 孩子分不清「撞了」还是「卡了」。
   */
  private beginDeath(nx: number, ny: number): void {
    if (this.gamePhase !== 'playing') {
      return
    }
    this.gamePhase = 'dying'
    this.dyingSince = Date.now()
    this.combo = 1

    // 散架顺序: 头先炸, 尾巴最后消失 (视觉上是「从撞击点往回崩」)
    this.shrinkSegs = []
    const n = this.snakeBody.length
    for (let i = 0; i < n; i++) {
      const s = this.snakeBody[i]
      // 头段 delay 0, 每往后 +0.42 节错峰, 上限让整段在动画时长内走完
      const delay = Math.min(0.8, i * 0.42 / Math.max(1, n - 1))
      this.shrinkSegs.push(makeShrink(s.x, s.y, delay, i === 0))
    }
    // 撞击点爆散 (越界时把坐标夹回棋盘内, 让粒子出现在边缘而不是画布外)
    const clampX = Math.max(0, Math.min(GRID - 1, nx))
    const clampY = Math.max(0, Math.min(GRID - 1, ny))
    this.burstAt(clampX, clampY, '#FFFFFF', 12)
  }

  /** 吃满目标果子: 果园大通关 (本局通关, 不是 session 结束) */
  private handleWin(): void {
    if (this.gamePhase !== 'playing') {
      return
    }
    this.gamePhase = 'won_tail'
    this.combo = 1
    if (this.snakeBody.length > 0) {
      this.burstAt(this.snakeBody[0].x, this.snakeBody[0].y, GOLD_STAR, 14)
    }
    // 停留一小段让粒子播完再弹覆盖层: 原实现立刻盖遮罩, 赢了什么都没看到
    if (this.winTailTimerId >= 0) {
      clearTimeout(this.winTailTimerId)
    }
    this.winTailTimerId = setTimeout(() => {
      this.winTailTimerId = -1
      if (this.gamePhase !== 'won_tail') {
        return
      }
      this.gamePhase = 'over'
      this.onRoundEnded(true)
    }, WIN_TAIL_MS)
  }

  /**
   * 一局结束的统一入口。
   * 累计 session 统计 → 更新本局反馈 → 弹出「再来一局 / 玩够了」。
   * 关键: 这里绝不 submitAnswer —— 提交会让卡片从消息流消失 (见文件头说明)。
   */
  private onRoundEnded(won: boolean): void {
    this.stopRenderLoop()
    this.elapsedSeconds = this.startTime > 0
      ? Math.floor((Date.now() - this.startTime) / 1000)
      : this.elapsedSeconds

    // 累计 session
    this.roundsPlayed += 1
    this.sessionApples += this.applesEaten
    this.sessionSeconds += Math.max(0, this.elapsedSeconds)

    // 记录最好一局 (分数优先; 分数相同取吃果更多的)
    const better = this.score > this.bestRoundScore
      || (this.score === this.bestRoundScore && this.applesEaten > this.bestRoundApples)
    if (better) {
      this.bestRoundScore = this.score
      this.bestRoundApples = this.applesEaten
      this.bestRoundWon = won
      this.bestRoundLength = this.snakeLength
      this.bestRoundGold = this.goldStars
      this.bestRoundCombo = this.bestCombo
    }

    void this.saveBestScoreIfImproved()
    this.redraw()

    // 本局反馈横幅: 不写 submitted —— 横幅是「一局结论」, 而卡片还没结束,
    // 横幅一出现就压住棋盘且不会消失, 会挡住孩子看下一局。结论放进覆盖层。
    this.overlayCount = ''
    this.overlayTitle = won ? '果园大通关！' : '撞到啦，没关系'
    // 未通关时按「就近可达的奖励」播报, 而不是只报离通关还差多少。
    // 只报「再吃 9 颗」对 5-7 岁是个看不见的距离, 会让孩子直接放弃;
    // 4 颗就能拿星, 所以优先告诉他这个马上够得着的目标。
    if (won) {
      this.overlaySub = `吃掉 ${this.applesEaten} 颗果子 · 得 ${this.score} 分`
    } else if (this.applesEaten >= STAR_THRESHOLD) {
      // 已过拿星线: 明确告诉他星星已经拿到了, 再把通关差距当前进目标
      this.overlaySub = `⭐ 星星到手啦！再吃 ${Math.max(0, this.targetFruits - this.applesEaten)} 颗就通关`
    } else {
      // 未到拿星线: 只播报离星星还差几颗 (这个数字小, 够得着)
      this.overlaySub = `再吃 ${STAR_THRESHOLD - this.applesEaten} 颗就能得到 1 颗星`
    }
    this.overlayBtnText = '再来一局'
    this.overlayShowSessionDone = true
    this.overlayCountdownMode = false
    this.overlayShow = true

    // 头部药丸显示本次 session 累计, 让孩子知道「玩了几局、攒了多少」
    this.shellState.headPill = this.roundsPlayed > 1 ? `第 ${this.roundsPlayed} 局` : '已完成'
    this.shellState.headPillColor = won ? SUCCESS_GREEN : GIVEUP_ORANGE
    if (this.bestScore >= 0) {
      this.shellState.headBadge = `🏆 最佳 ${this.bestScore}`
    }
    // 不抢焦点: 此时覆盖层上有「再来一局 / 玩够了」按钮, 焦点应留给它们给读屏和键盘用户
  }

  /** 孩子点「玩够了」: 结束整个 session, 提交一次回执 */
  private handleSessionDone(): void {
    if (this.receiptSubmitted) {
      return
    }
    this.stopRenderLoop()
    if (this.countdownTimerId >= 0) {
      clearTimeout(this.countdownTimerId)
      this.countdownTimerId = -1
    }
    this.overlayShow = false
    this.overlayShowSessionDone = false
    this.gamePhase = 'over'
    this.flushReceiptIfNeeded()
  }

  /** CardShell 的「结束游戏」链: 单独玩时与「玩够了」同义, 不额外惩罚 */
  private handleGiveUp(): void {
    if (this.isAnswered) {
      return
    }
    this.handleSessionDone()
  }

  /**
   * 提交回执的唯一出口。
   * - 玩过至少一局 (roundsPlayed > 0): completed = true, won = 最好一局是否通关 ——
   *   孩子确实玩了, 就按实际表现授星, 不能因为「点到退出」就抹掉成绩。
   * - 一局没打就退出: completed = false (0 星), 释放 pending 让 AI 能继续对话,
   *   否则工具调用会一直挂着。
   */
  private flushReceiptIfNeeded(): void {
    if (this.receiptSubmitted || this.isAnswered) {
      return
    }
    this.receiptSubmitted = true
    const played = this.roundsPlayed > 0
    this.submitAnswer(played && this.bestRoundWon, !played)
  }

  private submitAnswer(won: boolean, abandoned: boolean): void {
    // 主字段取「最好一局」, 保持历史 payload 语义 (score/apples 指单局成绩),
    // 跨局总量放 session_apples, 局数放 rounds。
    const payload: SnakeGameResult = {
      difficulty: this.difficulty,
      level_name: this.levelName,
      grid_size: '16×16',
      score: Math.max(0, this.bestRoundScore),
      apples_eaten: this.bestRoundApples,
      target_fruits: this.targetFruits,
      won: won,
      gold_stars: this.bestRoundGold,
      best_combo: this.bestRoundCombo,
      length: this.bestRoundLength,
      time_seconds: Math.max(0, Math.floor(this.sessionSeconds)),
      completed: !abandoned,
      rounds: this.roundsPlayed,
      session_apples: this.sessionApples
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private getBannerTitle(): string {
    if (this.gamePhase === 'over' && this.shellState.isCorrect) {
      if (this.isNewBest() && this.bestScore >= 0) {
        return this.gameWonRound() ? '果园大通关 · 新纪录！' : '新纪录！'
      }
      return this.gameWonRound() ? '果园大通关！' : '游戏结束'
    }
    if (this.prevCompleted) {
      return this.prevWon ? '果园大通关！' : '游戏结束'
    }
    return '没关系，下次再试试～'
  }

  private gameWonRound(): boolean {
    return this.applesEaten >= this.targetFruits
  }

  private getBannerSub(): string {
    const best = this.bestScore >= 0 ? ` · 最佳 ${this.bestScore}` : ''
    return `得分 ${this.score}${best} · 果子 ${this.applesEaten}/${this.targetFruits} · 金星 ${this.goldStars}`
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
    if (this.dirAckTimerId >= 0) {
      clearTimeout(this.dirAckTimerId)
      this.dirAckTimerId = -1
    }
    if (this.winTailTimerId >= 0) {
      clearTimeout(this.winTailTimerId)
      this.winTailTimerId = -1
    }
  }

  // ---- 粒子 / 飘字 ----

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

  /** 在网格格心炸开 count 个粒子 (方向均匀分布 + 少量抖动, 避免「齿轮」感) */
  private burstAt(gx: number, gy: number, color: string, count: number): void {
    for (let i = 0; i < count; i++) {
      const ang = (Math.PI * 2 * i) / count + (Math.random() - 0.5) * 0.5
      const speed = 2.4 + Math.random() * 2.2
      this.sparks.push(makeSpark(
        gx + 0.5,
        gy + 0.5,
        Math.cos(ang) * speed,
        Math.sin(ang) * speed,
        color,
        0.06 + Math.random() * 0.06
      ))
    }
  }

  private updateSparks(dt: number): void {
    if (this.sparks.length === 0) {
      return
    }
    const sec = dt / 1000
    for (let i = this.sparks.length - 1; i >= 0; i--) {
      const s = this.sparks[i]
      s.gx += s.vx * sec
      s.gy += s.vy * sec
      // 轻微重力 + 阻尼, 让粒子自然落下
      s.vy += 4.5 * sec
      s.vx *= 0.94
      s.vy *= 0.94
      s.life -= dt / 620
      if (s.life <= 0) {
        this.sparks.splice(i, 1)
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
      // 到期前 1.1 秒开始闪烁: 没有预警的金星 = 孩子看着它凭空消失,
      // 只会觉得「游戏骗人」。闪烁是唯一的「快没了」通道。
      const remain = this.goldExpireAt - Date.now()
      const fading = remain <= GOLD_WARN_MS
      if (fading) {
        // 8Hz 闪烁, 不做渐变 (幼儿园年龄段对突变更敏感)
        const on = Math.floor(remain / 120) % 2 === 0
        ctx.globalAlpha = on ? 1 : 0.3
      }
      this.drawStar(ctx, this.gold.x * cell + cell / 2, this.gold.y * cell + cell / 2, cell * 0.34)
      ctx.globalAlpha = 1
    }
    // dying 相位: 果子留在原地不画 (棋盘正在「散架」, 多一个静止物件会分心)
    if (this.gamePhase !== 'dying') {
      this.drawApple(ctx, this.food.x * cell + cell / 2, this.food.y * cell + cell / 2, cell * 0.32)
    }
    if (this.gamePhase === 'dying') {
      this.drawDeath(ctx, cell)
    } else {
      this.drawSnake(ctx, cell)
    }
    this.drawSparks(ctx, cell)
    this.drawPopups(ctx, cell)
  }

  private drawSparks(ctx: CanvasRenderingContext2D, cell: number): void {
    if (this.sparks.length === 0) {
      return
    }
    for (let i = 0; i < this.sparks.length; i++) {
      const s = this.sparks[i]
      const a = Math.max(0, Math.min(1, s.life))
      ctx.globalAlpha = a
      ctx.fillStyle = s.color
      ctx.beginPath()
      ctx.arc(s.gx * cell, s.gy * cell, Math.max(1, cell * s.radius * a), 0, Math.PI * 2)
      ctx.fill()
    }
    ctx.globalAlpha = 1
  }

  /** 死亡散架: 蛇身从撞击端往后逐节放大淡出, 头部闪红 (对应 beginDeath 的 delay) */
  private drawDeath(ctx: CanvasRenderingContext2D, cell: number): void {
    const t = Math.min(1, (Date.now() - this.dyingSince) / DEATH_ANIM_MS)
    for (let i = 0; i < this.shrinkSegs.length; i++) {
      const seg = this.shrinkSegs[i]
      const local = Math.max(0, Math.min(1, (t - seg.delay) / 0.34))
      if (local >= 1) {
        continue
      }
      const pad = cell * 0.1
      const grow = 1 + local * 0.5
      const size = (cell - pad * 2) * grow
      const cx = seg.gx * cell + cell / 2
      const cy = seg.gy * cell + cell / 2
      ctx.globalAlpha = 1 - local
      // 头节点闪白红, 身体按原配色褪成暗色
      ctx.fillStyle = seg.isHead
        ? (local < 0.28 ? '#FFFFFF' : APPLE_RED)
        : (i % 2 ? SNAKE_BODY_A : SNAKE_BODY_B)
      this.roundRectPath(ctx, cx - size / 2, cy - size / 2, size, size, size * 0.3)
      ctx.fill()
    }
    ctx.globalAlpha = 1
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

  /**
   * 绘制蛇身 (逐帧插值版)。
   * 原实现按逻辑格位置直接画, 150ms/步 = 每 3 帧瞬移一格, 是「卡顿感」的根因;
   * 原型用 state.alpha 在 prevSnake → snake 之间补间, 这里补回同一个机制。
   * 插值规则: 第 i 节从 prevSnake[i] 滑到 snake[i], 进度用 stepAlpha。
   * 长度变化时 (吃果子/金星) prevSnake 短一节, 缺位的那节不插值直接落在新位置。
   */
  private drawSnake(ctx: CanvasRenderingContext2D, cell: number): void {
    if (this.snakeBody.length === 0) {
      return
    }
    const t = Math.max(0, Math.min(1, this.stepAlpha))
    const pad = cell * 0.1
    // 先算好每节的实际绘制中心, 头和眼睛共用同一组坐标, 避免眼睛和头错位
    let headCx = 0
    let headCy = 0
    for (let i = this.snakeBody.length - 1; i >= 0; i--) {
      const cur = this.snakeBody[i]
      const prev = i < this.prevSnake.length ? this.prevSnake[i] : cur
      // 只有相邻格才插值 (穿墙/重生/长度突变时不插, 否则会横穿整个棋盘)
      const adjacent = Math.abs(cur.x - prev.x) + Math.abs(cur.y - prev.y) === 1
      const px = adjacent ? prev.x + (cur.x - prev.x) * t : cur.x
      const py = adjacent ? prev.y + (cur.y - prev.y) * t : cur.y
      const cx = px * cell + cell / 2
      const cy = py * cell + cell / 2
      ctx.fillStyle = i === 0 ? SNAKE_HEAD : (i % 2 ? SNAKE_BODY_A : SNAKE_BODY_B)
      this.roundRectPath(ctx, cx - (cell - pad * 2) / 2, cy - (cell - pad * 2) / 2,
        cell - pad * 2, cell - pad * 2, cell * 0.3)
      ctx.fill()
      if (i === 0) {
        headCx = cx
        headCy = cy
      }
    }
    // 蛇眼 (原型: 沿行进方向前置 + 垂直偏移)
    const fwd = cell * 0.16
    const side = cell * 0.17
    const er = Math.max(1.6, cell * 0.09)
    const px = -this.dir.y
    const py = this.dir.x
    ctx.fillStyle = EYE_INK
    ctx.beginPath()
    ctx.arc(headCx + this.dir.x * fwd + px * side, headCy + this.dir.y * fwd + py * side, er, 0, Math.PI * 2)
    ctx.fill()
    ctx.beginPath()
    ctx.arc(headCx + this.dir.x * fwd - px * side, headCy + this.dir.y * fwd - py * side, er, 0, Math.PI * 2)
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
        this.ProgressPips()
        this.BoardArea()
        if (!this.isAnswered) {
          this.DpadArea()
        }
      }
    }
  }

  @Builder
  HudRow() {
    Row({ space: 10 }) {
      Text(`得分 ${this.score}`)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(`连击 x${this.combo}`)
        .fontSize(11)
        .fontColor(this.combo > 1 ? '#FF6B6B' : $r('app.color.text_tertiary'))
      Blank()
      // 单独玩时的 session 进度: 已完成局数 + 跨局累计果子 (第 2 局起才显示, 首局不噪音)
      if (this.roundsPlayed > 1 && !this.isAnswered) {
        Text(`已玩 ${this.roundsPlayed} 局 · 共 ${this.sessionApples} 颗`)
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
      }
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

  /**
   * 果子进度: 图形化点阵替代「果子 3/12」。
   * 5-7 岁对文字分数没有概念, 但「亮了几格」是一眼能读的。目标数最多 16,
   * 一行 16 格在 320vp 宽度下每格约 15vp, 足够看见。
   */
  @Builder
  ProgressPips() {
    Row({ space: 3 }) {
      ForEach(this.pipIndexes(), (i: number) => {
        // 第 4 格 (拿星门槛) 用金色描边标出来, 其余是普通红点。
        // 不加标记的话, 孩子只知道「吃了几个」, 不知道「吃到哪一格就有星星」——
        // 4 颗拿星这条新规则就等于不存在。
        Row()
          .width(12)
          .height(12)
          .borderRadius(3)
          .backgroundColor(i < this.applesEaten ? APPLE_RED : 'rgba(0,0,0,0.10)')
          .border(i === STAR_THRESHOLD - 1
            ? { width: 2, color: i < this.applesEaten ? GOLD_STAR : SUCCESS_GREEN }
            : { width: 0, color: Color.Transparent })
      }, (i: number) => 'pip_' + i.toString())
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  /** 供 ForEach 使用的目标索引数组 (ArkTS 不允许内联 new Array 直接进 ForEach) */
  private pipIndexes(): number[] {
    const out: number[] = []
    const n = Math.min(this.targetFruits, 16)
    for (let i = 0; i < n; i++) {
      out.push(i)
    }
    return out
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
    .id('snakeBoard')
    .focusable(true)
    .focusOnTouch(true)
    .onKeyEvent((event: KeyEvent) => {
      this.handleKeyEvent(event)
    })
    .onTouch((e: TouchEvent) => {
      // 吞掉棋盘上的触摸, 防止外层 List 抢走滑动 (紧急转向时被滚动会直接送命)
      e.stopPropagation()
    })
    .priorityGesture(
      PanGesture({ direction: PanDirection.All, distance: SWIPE_MIN_OFFSET })
        // 用 onActionUpdate 而不是 onActionEnd: 实时游戏里「抬手才转向」等于多一整个
        // 手指行程的延迟, 紧急拐弯必撞墙。原型用 pointerup 是因为鼠标/触屏演示场景,
        // 移植到实时操作必须改成拖动即生效。
        .onActionUpdate((event: GestureEvent) => {
          if (this.isAnswered || this.gamePhase !== 'playing') {
            return
          }
          const offsetX = event.offsetX as number
          const offsetY = event.offsetY as number
          if (Math.abs(offsetX) < SWIPE_MIN_OFFSET && Math.abs(offsetY) < SWIPE_MIN_OFFSET) {
            return
          }
          // 一次拖动只认一个方向: 判过就置位, 避免手指持续拖动每帧刷一条指令
          if (this.swipeConsumed) {
            return
          }
          this.swipeConsumed = true
          if (Math.abs(offsetX) > Math.abs(offsetY)) {
            this.handleDirInput(offsetX > 0 ? 1 : -1, 0)
          } else {
            this.handleDirInput(0, offsetY > 0 ? 1 : -1)
          }
        })
        .onActionStart(() => {
          this.swipeConsumed = false
        })
        .onActionEnd(() => {
          this.swipeConsumed = false
        })
    )
  }

  @Builder
  BoardOverlay() {
    Column({ space: 10 }) {
      if (this.overlayCount !== '') {
        // 倒计时数字: 加描边光晕, 压在深色棋盘上也能一眼看清
        Text(this.overlayCount)
          .fontSize(this.overlayCountdownMode ? 64 : 56)
          .fontWeight(FontWeight.Bolder)
          .fontColor(GOLD_STAR)
          .textShadow({ radius: 18, color: 'rgba(255,193,58,0.55)', offsetX: 0, offsetY: 0 })
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
      // 单独玩的孩子需要明确的「不玩了」出口, 否则卡片永远挂在这里
      if (this.overlayShowSessionDone) {
        Button('玩够了')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(OVERLAY_SUB)
          .backgroundColor('rgba(255,255,255,0.10)')
          .borderRadius(16)
          .padding({ left: 20, right: 20, top: 8, bottom: 8 })
          .onClick(() => {
            this.handleSessionDone()
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    // 倒计时只叠数字, 不铺遮罩: 孩子要趁这 2 秒看清蛇和果子的位置
    .backgroundColor(this.overlayCountdownMode ? 'rgba(16,27,51,0.28)' : 'rgba(16,27,51,0.82)')
    .borderRadius(16)
    // 倒计时期间不拦截触摸: 触摸会落到棋盘上 (点一下即可给棋盘焦点)。
    // 注意 countdown 阶段的转向指令仍会被 handleDirInput 丢弃 —— 这是刻意的:
    // 预输入会让开局第一步朝孩子随手划的方向走, 比「不响应」更容易撞墙。
    .hitTestBehavior(this.overlayCountdownMode ? HitTestMode.None : HitTestMode.Default)
  }

  @Builder
  DpadArea() {
    // space 收到 8: 棋盘与方向键之间原本有 CardShell 的 10 + 这里 10,
    // 孩子的视线在蛇身上、手指要跨过整块屏幕, 收紧后眼睛和手更靠在一起
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        this.DirButton(180, 0, -1, '向上', 'up')
      }
      Row({ space: 8 }) {
        this.DirButton(90, -1, 0, '向左', 'left')
        this.DirButton(0, 0, 1, '向下', 'down')
        this.DirButton(-90, 1, 0, '向右', 'right')
      }
      Text('方向键 / 按钮 / 滑动都能转弯')
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .constraintSize({ maxWidth: 320 })
    .alignSelf(ItemAlign.Center)
    .margin({ top: -2 })
  }

  /** chevron_down 旋转出四向 (whitelist symbol; down=0 / left=90 / right=-90 / up=180) */
  @Builder
  DirButton(angle: number, dx: number, dy: number, a11y: string, key: string) {
    Button() {
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(26)
        // 高亮态用主题色, 让「按到了」和「没按到」有差别
        .fontColor([this.activeDirKey === key ? Color.White : $r('app.color.text_primary')])
        .rotate({ angle: angle })
    }
    // 64×50 对 5 岁孩子偏小 (成人拇指目标 44vp, 儿童需要更大):
    // 高度抬到 56 并加宽, 减少「按空了蛇就撞墙」的挫败
    .width(72)
    .height(56)
    .backgroundColor(this.activeDirKey === key ? this.themePrimary : $r('app.color.surface'))
    .borderRadius(18)
    .border({ width: 1, color: $r('app.color.divider') })
    .accessibilityText(a11y)
    .onClick(() => {
      this.handleDirInput(dx, dy)
    })
  }
}
