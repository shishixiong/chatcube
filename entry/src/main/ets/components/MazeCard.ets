/**
 * MazeCard - 走迷宫互动卡片 (v3 · Paper Map)
 *
 * 设计语言: 儿童绘本纸面地图
 * - 纸面背景 (#F5EFE3 暖米黄), 深墨蓝墙线 (#1F3A52)
 * - 兔子玩家 (🐰 玩家位置), 小屋锚点 (🏠 终点)
 * - 死胡同藏胡萝卜 (🥕 收集时放大上浮淡出)
 * - 道具: ⚡时间冻结(计时暂停 6 秒) / 🧭指路(绿色高亮正确路线 4 秒) / 🎁宝箱(开出随机道具)
 * - 传送门 (🌀 挑战档): 一对互相远离的格子, 踩上即传送到另一端
 * - 移动: 点按相邻格 或 在棋盘上滑动(与数字华容道手势一致)
 * - 足迹: 走过的格子留墨蓝小圆点, 帮孩子认路
 * - 放弃后: 绿色高亮从当前位置到终点的正确路线 (solveMaze BFS)
 * - 撞墙抖动 + 玩家移动弹簧动画
 *
 * 双形态 (v3, 参考 docs/zoumigong.html):
 * - largeSize=false: 紧凑结果摘要卡 (isAnswered=true 时, 供时间线步骤详情复用)
 * - largeSize=true: 全屏 sheet 游戏 (由 ChatPage MazeSheetBuilder 承载, 气泡侧
 *   MessageBubble 渲染 handwriting 式横幅, 点击后经 onOpenMazeSheet 打开)
 *
 * 公共 API 保持家族一致: toolCall / isAnswered / answeredPayload / largeSize / onAnswer
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { getPreferencesService, PreferenceKeys } from '../services/PreferencesService'
import {
  MazeData,
  MazeCell,
  MazePosition,
  MazeDifficulty,
  MazeDimensions,
  MazeExtras,
  Direction,
  generateMaze,
  movePlayer as mazeMovePlayer,
  getNeighborPosition,
  solveMaze,
  isAtGoal,
  collectStar as mazeCollectStar,
  getDifficultyLabel,
  getGridSizeLabel,
  getGridDimensions,
  computePar,
  evaluateStars,
  getPortalTarget
} from '../utils/MazeGame'
import { CardShell } from './cardshell/CardShell'
import { CardShellConfig, CardShellCopy } from './cardshell/CardShellTypes'
import { CardShellState } from './cardshell/CardShellState'

// 滑动手势触发阈值 (vp), 与 NumberPuzzleCard 保持一致
const SWIPE_MIN_OFFSET: number = 10

export interface MazeResult {
  difficulty: number
  grid_size: string
  time_seconds: number
  move_count: number
  stars_collected: number
  stars_total: number
  completed: boolean
  // 走迷宫 v3: 表现评级 1-3 星 (放弃时 0; 历史会话 payload 无此字段)
  stars: number
}

@ComponentV2
export struct MazeCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  // 迷宫状态
  @Local maze: MazeData | null = null
  @Local playerPos: MazePosition = { row: 0, col: 0 }
  @Local difficulty: MazeDifficulty = 1

  // 计时与步数
  @Local moveCount: number = 0
  // 计时器私有状态 (v3: 累加式, 支持暂停/冻结; 非响应式)
  private timerAccumMs: number = 0
  private lastTickAt: number = 0
  private effectToastTimerId: number = -1
  private winOverlayTimerId: number = -1
  @Local elapsedSeconds: number = 0
  @Local starsCollected: number = 0

  // 状态机
  @Local isCompleted: boolean = false
  @Local hasWon: boolean = false
  // 玩家移动入场动画: 首次渲染期间为 false, 之后开启
  @Local shouldAnimate: boolean = false
  @Local bestTimeSeconds: number = -1
  @Local bestMoves: number = -1
  @Local bestStars: number = -1
  @Local bestRating: number = -1          // 最佳评级 1-3 星 (-1 = 无)
  // 已答完的历史结果 (AnsweredSummaryCard 数据源; null = 无有效 payload)
  @Local restoredResult: MazeResult | null = null
  @Local isNewBest: boolean = false
  @Local bestScoresLoaded: boolean = false

  // 触碰反馈
  @Local pressedCellKey: string = ''       // 当前按下的格子 (格式 "r,c")
  @Local wallBumpKey: string = ''          // 撞墙抖动键 (格式 "r,c")
  @Local wallBumpAxis: 'h' | 'v' = 'h'     // 抖动方向
  @Local wallBumpStep: number = 0          // 抖动阶段 (0=静止, 1-4=抖动幅度)
  @Local collectedKey: string = ''         // 刚被收集的胡萝卜位置 (用于飞出动画)
  @Local collectFly: boolean = false       // 收集动画阶段 (false=定格, true=放大上浮淡出)
  // 已收集胡萝卜键集合 (Set 需整体重赋值才能触发 @Local 响应)
  // 必要性: cell.hasStar 是 @Builder 形参的普通字段, 非响应式; mazeCollectStar 的原地修改
  // 无法触发 ForEach 重新渲染该格, 导致胡萝卜永久残留。collectedKeys 是 @Local Set, 可靠。
  @Local collectedKeys: Set<string> = new Set<string>()

  // 足迹与提示路线 (key 格式 "r,c"; Set 需整体重赋值才能触发 @Local 响应)
  @Local visitedKeys: Set<string> = new Set<string>()
  @Local hintKeys: Set<string> = new Set<string>()

  // ===== 走迷宫 v3: 道具/暂停/胜利弹窗 =====
  @Local frozenUntilMs: number = 0            // ⚡ 时间冻结截止时间戳 (0 = 未冻结)
  @Local isPaused: boolean = false            // 暂停中 (计时与移动都停)
  @Local activeEffectText: string = ''        // 效果横幅文案 ('' = 隐藏)
  // 已使用的道具/宝箱格 (Set 需整体重赋值才能触发 @Local 响应)
  @Local usedPowerupKeys: Set<string> = new Set<string>()
  @Local par: number = 0                      // 星级评定基准步数 (computePar)
  @Local winStars: number = 0                 // 胜利评级星 (1-3)
  @Local showWinOverlay: boolean = false      // 胜利弹窗
  @Local portalFlash: boolean = false         // 传送门传送闪烁
  @Local boardAreaWidth: number = 0           // 全屏棋盘实测宽度 (onAreaChange)
  // 胜利弹窗「完成」→ 请求 ChatPage 关闭 sheet
  @Event onRequestClose: () => void = () => {}

  @Local shellConfig: CardShellConfig = {
    title: '走迷宫',
    subtitle: '',
    icon: $r('sys.symbol.map'),
    stem: '',
    hasAudio: false,
    usesConfirm: false,
    feedbackTitleCorrect: '走出迷宫！',
    correctAnswerLabel: '',
    feedbackAboveSlot: true,
    usesGiveUp: true,
    giveUpLabel: ''
  }
  private shellState: CardShellState = new CardShellState()

  private timerId: number = -1

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  // 纸面调色板
  private get paperBackground(): string {
    return this.isDarkMode ? '#2A2520' : '#F5EFE3'
  }

  private get cellPathColor(): string {
    return this.isDarkMode ? '#332E27' : '#FBF7EE'
  }

  private get wallColor(): string {
    return this.isDarkMode ? '#7FA8C9' : '#1F3A52'
  }

  private get boardBackground(): string {
    return withColorAlpha(this.wallColor, this.isDarkMode ? '0C' : '06')
  }

  // 单元格尺寸: 根据网格大小动态调整,8×8 自动缩小以适应聊天气泡宽度
  // 单元格尺寸: sheet 全屏下按实测宽度自适应 (9/11/13 列)
  private get cellSize(): number {
    const cols: number = this.maze !== null
      ? this.maze.cols
      : this.difficultyToRows(this.difficulty)
    // boardAreaWidth 为 MazePanel 容器实测宽; 首帧前用估算兜底
    const inner: number = this.boardAreaWidth > 0
      ? this.boardAreaWidth
      : (this.largeSize ? 320 : 300)
    const gap: number = this.largeSize ? 2 : 1
    const gapTotal: number = gap * 2 * (cols + 2)
    const per: number = Math.floor((inner - gapTotal) / cols)
    return Math.max(20, Math.min(44, per))
  }

  private get cellGap(): number {
    // 内联模式大格(cellSize≥40)用 0vp 间隙节省宽度, 小格保持 1vp 让墙条更明显
    if (this.largeSize) return 2
    return this.cellSize >= 40 ? 0 : 1
  }

  private get wallThickness(): number {
    return this.largeSize ? 4 : 3
  }

  // 玩家/图标尺寸跟随 cellSize 缩放
  private get playerSize(): number {
    return Math.max(14, Math.round(this.cellSize * 0.62))
  }

  private get starSize(): number {
    return Math.max(10, Math.round(this.cellSize * 0.46))
  }

  private get goalSize(): number {
    return Math.max(14, Math.round(this.cellSize * 0.6))
  }

  private get trailDotSize(): number {
    return Math.max(4, Math.round(this.cellSize * 0.14))
  }

  private difficultyToRows(d: number): number {
    if (d >= 3) return 13
    if (d >= 2) return 11
    return 9
  }

  // 派生标签
  private get difficultyLabel(): string {
    const diffLabel: string = getDifficultyLabel(this.difficulty)
    const sizeLabel: string = getGridSizeLabel(this.difficulty)
    return `${diffLabel} · ${sizeLabel}`
  }

  // subtitle 依赖 parseAndInitialize 之后才稳定的 difficulty, 必须整体重赋值触发响应
  private rebuildShellConfig(): void {
    this.shellConfig = {
      title: '走迷宫',
      subtitle: this.difficultyLabel,
      icon: $r('sys.symbol.map'),
      stem: '',
      giveUpLabel: '走不出去了？看正确路线 →',
      hasAudio: false,
      usesConfirm: false,
      feedbackTitleCorrect: '走出迷宫！',
      correctAnswerLabel: '',
      feedbackAboveSlot: true,
      usesGiveUp: true
    }
  }

  // 外壳状态同步: submitted=hasWon, isFinished=isCompleted; 明细带胡萝卜收集后缀
  private syncShellState(): void {
    this.shellState.submitted = this.hasWon
    this.shellState.isFinished = this.isCompleted
    this.shellState.isCorrect = this.hasWon
    this.shellState.feedbackTitle = this.isAnswered ? '已完成' : ''
    let detail: string = `${this.formatTime(this.elapsedSeconds)} · ${this.moveCount} 步`
    if (this.maze !== null && this.maze.starsTotal > 0) {
      detail += ` · 🥕${this.starsCollected}/${this.maze.starsTotal}`
    }
    this.shellState.feedbackDetail = detail
    this.shellState.feedbackBadge = this.isNewBest ? '新纪录' : ''
    if (this.isAnswered || this.isCompleted) {
      this.shellState.headPill = this.hasWon ? '已完成' : '已放弃'
      this.shellState.headPillColor = this.hasWon ? '#4CAF50' : '#FF9F43'
    } else {
      this.shellState.headPill = ''
    }
  }

  aboutToAppear(): void {
    this.parseAndInitialize()
    this.rebuildShellConfig()
    this.syncShellState()
  }

  aboutToDisappear(): void {
    this.stopTimer()
  }

  private parseAndInitialize(): void {
    try {
      const args = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      const rawDiff = (args['difficulty'] as number) ?? 1
      const clamped: MazeDifficulty = (rawDiff >= 1 && rawDiff <= 3 ? rawDiff : 1) as MazeDifficulty
      this.difficulty = clamped

      if (this.isAnswered && this.answeredPayload !== '') {
        // 还原历史结果
        try {
          const parsed = JSON.parse(this.answeredPayload) as Record<string, Object>
          const result: MazeResult = {
            difficulty: (parsed['difficulty'] as number) ?? 1,
            grid_size: (parsed['grid_size'] as string) ?? '',
            time_seconds: (parsed['time_seconds'] as number) ?? 0,
            move_count: (parsed['move_count'] as number) ?? 0,
            stars_collected: (parsed['stars_collected'] as number) ?? 0,
            stars_total: (parsed['stars_total'] as number) ?? 0,
            completed: parsed['completed'] === true,
            // v3 字段: 历史会话 payload 可能缺失, 缺省 0
            stars: (parsed['stars'] as number) ?? 0
          }
          this.restoredResult = result
          this.elapsedSeconds = result.time_seconds
          this.moveCount = result.move_count
          this.starsCollected = result.stars_collected
          this.hasWon = result.completed
          this.winStars = result.stars
          this.isCompleted = true
          // 尝试从 args 还原迷宫布局
          const cellsRaw = args['cells']
          if (cellsRaw !== undefined && cellsRaw !== null) {
            this.maze = this.deserializeMaze(args)
            // 历史放弃的局: 揭示正确路线, 与现场放弃体验一致
            if (!this.hasWon && this.maze !== null) {
              this.revealHint()
            }
          }
        } catch (_e) {
          // 还原失败,使用空状态
        }
      } else if (this.isAnswered) {
        this.isCompleted = true
      } else {
        // 新游戏: 使用后端注入的 maze cells (如有), 否则现场生成
        const cellsRaw = args['cells']
        if (cellsRaw !== undefined && cellsRaw !== null) {
          this.maze = this.deserializeMaze(args)
        } else {
          this.maze = this.generateFreshMaze(clamped)
        }
        if (this.maze !== null) {
          this.par = computePar(this.maze)
        }
        this.startTimer()
        // 起点计入足迹
        this.markVisited(this.playerPos)
        // 初次渲染后开启入场动画, 避免首次出现玩家就有滑入效果
        this.shouldAnimate = true
      }

      // 异步加载最佳成绩(无论新游戏还是还原都需要)
      void this.loadBestScores(clamped)
    } catch (error) {
      console.error('MazeCard', `Failed to parse toolCall.arguments: ${String(error)}`)
      // 降级: 生成一个最小可玩迷宫
      const fallbackMaze: MazeData = this.generateFreshMaze(1)
      this.maze = fallbackMaze
      this.par = computePar(fallbackMaze)
    }
  }

  // 新局生成: 9/11/13 档, 道具 2 + 宝箱 1, 挑战档加传送门; 胡萝卜 3/4/5
  private generateFreshMaze(diff: MazeDifficulty): MazeData {
    const dims: MazeDimensions = getGridDimensions(diff)
    const extras: MazeExtras = {
      powerupCount: 2,
      treasureCount: 1,
      portalPair: diff === 3
    }
    const carrotCount: number = diff === 1 ? 3 : (diff === 2 ? 4 : 5)
    return generateMaze(dims.rows, dims.cols, carrotCount, undefined, extras)
  }


  private deserializeMaze(args: Record<string, Object>): MazeData | null {
    try {
      const cellsRaw = args['cells'] as Record<string, Object>[]
      const rows = (args['rows'] as number) ?? 4
      const cols = (args['cols'] as number) ?? 4
      const starsTotal = (args['stars_total'] as number) ?? 0
      const cells: MazeCell[][] = []
      for (let r = 0; r < rows; r++) {
        const rowCells: MazeCell[] = []
        const srcRow = cellsRaw[r]
        if (srcRow === undefined) {
          return null
        }
        for (let c = 0; c < cols; c++) {
          const srcCell = srcRow[c] as Record<string, Object>
          if (srcCell === undefined) {
            return null
          }
          const wallsRaw = srcCell['walls'] as Record<string, Object>
          const cell: MazeCell = {
            walls: {
              top: (wallsRaw['top'] as boolean) === true,
              right: (wallsRaw['right'] as boolean) === true,
              bottom: (wallsRaw['bottom'] as boolean) === true,
              left: (wallsRaw['left'] as boolean) === true
            },
            hasStar: (srcCell['hasStar'] as boolean) === true,
            isStart: (srcCell['isStart'] as boolean) === true,
            isGoal: (srcCell['isGoal'] as boolean) === true
          }
          // v3: 道具与传送门 (可选字段, 历史数据无)
          const powerupRaw = srcCell['powerup']
          if (powerupRaw === 'freeze') {
            cell.powerup = 'freeze'
          } else if (powerupRaw === 'compass') {
            cell.powerup = 'compass'
          } else if (powerupRaw === 'treasure') {
            cell.powerup = 'treasure'
          }
          const portalRaw = srcCell['portalTo']
          if (portalRaw !== undefined && portalRaw !== null) {
            const portalObj = portalRaw as Record<string, Object>
            const portalPos: MazePosition = {
              row: (portalObj['row'] as number) ?? 0,
              col: (portalObj['col'] as number) ?? 0
            }
            cell.portalTo = portalPos
          }

          rowCells.push(cell)
        }
        cells.push(rowCells)
      }
      return { rows: rows, cols: cols, cells: cells, starsTotal: starsTotal }
    } catch (_e) {
      return null
    }
  }

  private async loadBestScores(difficulty: MazeDifficulty): Promise<void> {
    const prefs = getPreferencesService()
    try {
      this.bestTimeSeconds = await prefs.getNumber(
        PreferenceKeys.MAZE_BEST_TIME_PREFIX + difficulty.toString(), -1)
      this.bestMoves = await prefs.getNumber(
        PreferenceKeys.MAZE_BEST_MOVES_PREFIX + difficulty.toString(), -1)
      this.bestStars = await prefs.getNumber(
        PreferenceKeys.MAZE_BEST_STARS_PREFIX + difficulty.toString(), -1)
      this.bestRating = await prefs.getNumber(
        PreferenceKeys.MAZE_BEST_RATING_PREFIX + difficulty.toString(), -1)
    } catch (_e) {
      this.bestTimeSeconds = -1
      this.bestMoves = -1
      this.bestStars = -1
      this.bestRating = -1
    } finally {
      this.bestScoresLoaded = true
    }
  }


  private async saveBestScoresIfImproved(timeSec: number, moves: number, carrots: number, rating: number): Promise<void> {
    if (!this.bestScoresLoaded) {
      // 异步竞态守卫: 最佳成绩未加载完则放弃本次保存(避免 stale -1 覆盖真实最佳)
      return
    }
    const prefs = getPreferencesService()
    const key = this.difficulty.toString()
    const timeKey = PreferenceKeys.MAZE_BEST_TIME_PREFIX + key
    const movesKey = PreferenceKeys.MAZE_BEST_MOVES_PREFIX + key
    const starsKey = PreferenceKeys.MAZE_BEST_STARS_PREFIX + key
    const ratingKey = PreferenceKeys.MAZE_BEST_RATING_PREFIX + key

    let isNew = false
    if (this.bestTimeSeconds < 0 || timeSec < this.bestTimeSeconds) {
      await prefs.setNumber(timeKey, timeSec)
      isNew = true
    }
    if (this.bestMoves < 0 || moves < this.bestMoves) {
      await prefs.setNumber(movesKey, moves)
      isNew = true
    }
    if (this.bestStars < 0 || carrots > this.bestStars) {
      await prefs.setNumber(starsKey, carrots)
      isNew = true
    }
    if (this.bestRating < 0 || rating > this.bestRating) {
      await prefs.setNumber(ratingKey, rating)
      isNew = true
    }
    if (isNew) {
      this.isNewBest = true
      this.bestTimeSeconds = Math.min(this.bestTimeSeconds < 0 ? timeSec : this.bestTimeSeconds, timeSec)
      this.bestMoves = Math.min(this.bestMoves < 0 ? moves : this.bestMoves, moves)
      this.bestStars = Math.max(this.bestStars < 0 ? carrots : this.bestStars, carrots)
      this.bestRating = Math.max(this.bestRating < 0 ? rating : this.bestRating, rating)
      this.shellState.feedbackBadge = '新纪录'
    }
  }

  private startTimer(): void {
    this.stopTimer()
    this.timerAccumMs = this.elapsedSeconds * 1000
    this.lastTickAt = Date.now()
    this.timerId = setInterval((): void => {
      const now = Date.now()
      const delta: number = now - this.lastTickAt
      this.lastTickAt = now
      // 暂停/冻结/已结束: 只推进基准点, 不累计 (delta 过大视为后台挂起, 丢弃)
      if (this.isCompleted || this.isPaused || now < this.frozenUntilMs) {
        return
      }
      if (delta > 0 && delta < 5000) {
        this.timerAccumMs += delta
        this.elapsedSeconds = Math.floor(this.timerAccumMs / 1000)
      }
    }, 500)
  }

  private stopTimer(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
    if (this.effectToastTimerId !== -1) {
      clearTimeout(this.effectToastTimerId)
      this.effectToastTimerId = -1
    }
    if (this.winOverlayTimerId !== -1) {
      clearTimeout(this.winOverlayTimerId)
      this.winOverlayTimerId = -1
    }
  }


  private handleCellPress(row: number, col: number): void {
    if (this.isCompleted || this.maze === null) {
      return
    }
    if (row === this.playerPos.row && col === this.playerPos.col) {
      return
    }
    const dr = row - this.playerPos.row
    const dc = col - this.playerPos.col
    if (Math.abs(dr) + Math.abs(dc) !== 1) {
      // 非相邻: 拒绝(无视觉反馈,保持简单)
      return
    }
    const direction: Direction = dr === -1 ? 'top' : (dr === 1 ? 'bottom' : (dc === -1 ? 'left' : 'right'))
    this.movePlayer(direction)
  }

  // 棋盘滑动手势: 水平/垂直分量大的方向移动一步(与数字华容道一致)
  private handleBoardSwipe(offsetX: number, offsetY: number): void {
    if (Math.abs(offsetX) < SWIPE_MIN_OFFSET && Math.abs(offsetY) < SWIPE_MIN_OFFSET) {
      return
    }
    const direction: Direction = Math.abs(offsetX) > Math.abs(offsetY)
      ? (offsetX > 0 ? 'right' : 'left')
      : (offsetY > 0 ? 'bottom' : 'top')
    this.movePlayer(direction)
  }

  // 统一移动入口: 点按相邻格与滑动手势共用
  private movePlayer(direction: Direction): void {
    if (this.isCompleted || this.isPaused || this.maze === null) {
      return
    }
    const newPos: MazePosition | null = mazeMovePlayer(this.maze.cells, this.playerPos, direction)
    if (newPos === null) {
      // 撞墙或越界: 目标格存在则抖动该格提示
      const target: MazePosition | null = getNeighborPosition(
        this.playerPos, direction, this.maze.rows, this.maze.cols)
      if (target !== null) {
        this.triggerWallBump(target.row, target.col,
          (direction === 'top' || direction === 'bottom') ? 'v' : 'h')
      }
      return
    }
    this.commitMove(newPos)
  }

  private commitMove(newPos: MazePosition): void {
    if (this.maze === null) {
      return
    }
    this.moveCount += 1
    this.markVisited(newPos)
    this.movePlayerVisually(newPos)
    this.processCellContents(newPos, false)
  }

  // 落格结算: 胡萝卜 → 道具/宝箱 → 传送门(每步至多一次, 防循环) → 终点
  private processCellContents(pos: MazePosition, viaPortal: boolean): void {
    if (this.maze === null) {
      return
    }
    const landedCell: MazeCell = this.maze.cells[pos.row][pos.col]
    const posKey: string = pos.row + ',' + pos.col
    // 胡萝卜收集
    if (landedCell.hasStar && mazeCollectStar(landedCell)) {
      this.starsCollected += 1
      // 记入已收集集合 (响应式): cell.hasStar 的原地修改不触发 @Builder 重渲染,
      // 必须通过 collectedKeys Set 才能让该格的胡萝卜在视觉上消失
      const nextCollected: Set<string> = new Set<string>()
      this.collectedKeys.forEach((k: string) => {
        nextCollected.add(k)
      })
      nextCollected.add(posKey)
      this.collectedKeys = nextCollected
      this.collectedKey = posKey
      this.collectFly = false
      // 先定格渲染一帧, 再切换到飞出态触发动画
      setTimeout((): void => {
        this.collectFly = true
      }, 30)
      setTimeout((): void => {
        this.collectedKey = ''
        this.collectFly = false
      }, 400)
    }
    // 道具/宝箱 (每格一次性)
    if (landedCell.powerup !== undefined && landedCell.powerup !== '' &&
      !this.usedPowerupKeys.has(posKey)) {
      const nextUsed: Set<string> = new Set<string>()
      this.usedPowerupKeys.forEach((k: string) => {
        nextUsed.add(k)
      })
      nextUsed.add(posKey)
      this.usedPowerupKeys = nextUsed
      if (landedCell.powerup === 'freeze') {
        this.applyFreezePowerup()
      } else if (landedCell.powerup === 'compass') {
        this.applyCompassPowerup()
      } else if (landedCell.powerup === 'treasure') {
        // 宝箱: 随机开出一种道具
        if (Math.random() < 0.5) {
          this.applyFreezePowerup()
        } else {
          this.applyCompassPowerup()
        }
      }
    }
    // 传送门: 落格即传送到另一端 (viaPortal 防止 A→B→A 循环)
    if (!viaPortal) {
      const portalTarget: MazePosition | null = getPortalTarget(landedCell)
      if (portalTarget !== null) {
        this.portalFlash = true
        setTimeout((): void => {
          this.portalFlash = false
        }, 350)
        this.markVisited(portalTarget)
        this.movePlayerVisually(portalTarget)
        this.processCellContents(portalTarget, true)
        return
      }
    }
    // 终点
    if (isAtGoal(landedCell)) {
      this.handleWin()
    }
  }

  // ❄ 冻结: 6 秒内计时暂停 (计时器 tick 时检查 frozenUntilMs)
  private applyFreezePowerup(): void {
    this.frozenUntilMs = Date.now() + 6000
    this.showEffectToast('❄️ 时间冻结 6 秒')
  }

  // 🧭 指路: 高亮当前位置到终点的路线, 4 秒后收回
  private applyCompassPowerup(): void {
    this.revealHint()
    setTimeout((): void => {
      if (!this.isCompleted && !this.hasWon) {
        this.hintKeys = new Set<string>()
      }
    }, 4000)
    this.showEffectToast('🧭 已标出正确路线')
  }

  // 效果横幅: 2.5 秒后自动消失
  private showEffectToast(text: string): void {
    this.activeEffectText = text
    if (this.effectToastTimerId !== -1) {
      clearTimeout(this.effectToastTimerId)
    }
    this.effectToastTimerId = setTimeout((): void => {
      this.activeEffectText = ''
      this.effectToastTimerId = -1
    }, 2500)
  }


  // 足迹: Set 需整体重赋值才能触发 @Local 响应
  private markVisited(pos: MazePosition): void {
    const key: string = pos.row + ',' + pos.col
    if (this.visitedKeys.has(key)) {
      return
    }
    const next: Set<string> = new Set<string>()
    this.visitedKeys.forEach((k: string) => {
      next.add(k)
    })
    next.add(key)
    this.visitedKeys = next
  }

  // 放弃后揭示从当前位置到终点的正确路线
  private revealHint(): void {
    if (this.maze === null) {
      return
    }
    const goalPos: MazePosition | null = this.findGoalPosition()
    if (goalPos === null) {
      return
    }
    const path: MazePosition[] | null = solveMaze(this.maze.cells, this.playerPos, goalPos)
    if (path === null) {
      return
    }
    const keys: Set<string> = new Set<string>()
    for (let i = 0; i < path.length; i++) {
      keys.add(path[i].row + ',' + path[i].col)
    }
    this.hintKeys = keys
  }

  private findGoalPosition(): MazePosition | null {
    if (this.maze === null) {
      return null
    }
    for (let r = 0; r < this.maze.rows; r++) {
      for (let c = 0; c < this.maze.cols; c++) {
        if (this.maze.cells[r][c].isGoal) {
          return { row: r, col: c }
        }
      }
    }
    return null
  }

  private handleCellTouchDown(row: number, col: number): void {
    if (this.isCompleted) {
      return
    }
    this.pressedCellKey = row + ',' + col
  }

  private handleCellTouchUp(): void {
    this.pressedCellKey = ''
  }

  private movePlayerVisually(newPos: MazePosition): void {
    // 初始渲染期间 shouldAnimate=false: 同步赋值, 不开启动画 (避免首屏兔子飞入)
    // 之后 shouldAnimate=true: 用 animateTo 包裹状态变化, 让 overlay 平滑滑动到新格子
    if (!this.shouldAnimate) {
      this.playerPos = newPos
      return
    }
    animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
      this.playerPos = newPos
    })
  }

  private triggerWallBump(row: number, col: number, axis: 'h' | 'v'): void {
    this.wallBumpKey = `${row},${col}`
    this.wallBumpAxis = axis
    this.wallBumpStep = 1
    setTimeout((): void => { this.wallBumpStep = 2 }, 50)
    setTimeout((): void => { this.wallBumpStep = 3 }, 100)
    setTimeout((): void => { this.wallBumpStep = 4 }, 150)
    setTimeout((): void => { this.wallBumpStep = 0 }, 220)
  }

  private getBumpOffset(row: number, col: number, axis: 'h' | 'v'): number {
    const cellKey: string = `${row},${col}`
    if (this.wallBumpKey !== cellKey) {
      return 0
    }
    if (axis !== this.wallBumpAxis) {
      return 0
    }
    if (this.wallBumpStep <= 0) {
      return 0
    }
    const offsets: number[] = [0, 3, -3, 1, -1]
    return offsets[this.wallBumpStep] ?? 0
  }

  private handleWin(): void {
    if (this.hasWon) {
      return
    }
    this.hasWon = true
    this.isCompleted = true
    this.stopTimer()
    const starsTotal: number = this.maze !== null ? this.maze.starsTotal : 0
    const rating: number = evaluateStars(this.moveCount, this.par, this.starsCollected, starsTotal)
    this.winStars = rating
    const result: MazeResult = {
      difficulty: this.difficulty,
      grid_size: getGridSizeLabel(this.difficulty),
      time_seconds: this.elapsedSeconds,
      move_count: this.moveCount,
      stars_collected: this.starsCollected,
      stars_total: starsTotal,
      completed: true,
      stars: rating
    }
    void this.saveBestScoresIfImproved(
      this.elapsedSeconds, this.moveCount, this.starsCollected, rating
    )
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
    this.syncShellState()
    // 先让孩子看清终点, 再弹庆祝窗
    this.winOverlayTimerId = setTimeout((): void => {
      this.showWinOverlay = true
      this.winOverlayTimerId = -1
    }, 650)
  }


  private handleGiveUp(): void {
    if (this.isCompleted) {
      return
    }
    this.isCompleted = true
    this.hasWon = false
    this.stopTimer()
    // 揭示正确路线: 让"放弃"同时成为一次看答案的学习机会
    this.revealHint()
    const result: MazeResult = {
      difficulty: this.difficulty,
      grid_size: getGridSizeLabel(this.difficulty),
      time_seconds: this.elapsedSeconds,
      move_count: this.moveCount,
      stars_collected: this.starsCollected,
      stars_total: this.maze !== null ? this.maze.starsTotal : 0,
      completed: false,
      stars: 0
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
    this.syncShellState()
  }


  private formatTime(seconds: number): string {
    const m: number = Math.floor(seconds / 60)
    const s: number = seconds % 60
    if (m === 0) {
      return `0:${s.toString().padStart(2, '0')}`
    }
    return `${m}:${s.toString().padStart(2, '0')}`
  }

  build() {
    if (this.isAnswered) {
      // 已结束: 时间线步骤详情使用的紧凑摘要卡
      this.AnsweredSummaryCard()
    } else {
      Stack() {
        CardShell({
          config: this.shellConfig,
          state: this.shellState,
          isAnswered: this.isAnswered,
          largeSize: this.largeSize,
          onGiveUp: () => {
            this.handleGiveUp()
          }
        }) {
          this.MazePanel()
          this.StatsGrid()
          this.GameControlsRow()
          this.HintCaption()
        }
        // 效果横幅: 覆盖在卡片顶部, 不拦截点击
        if (this.activeEffectText !== '') {
          this.EffectToast()
        }
        // 胜利庆祝弹窗: 最后渲染, 覆盖一切
        if (this.showWinOverlay) {
          this.WinOverlay()
        }
      }
      .width('100%')
    }
  }


  // 放弃后的路线提示行 — 原操作区的 else 分支, 留 slot(Shell actions 区只渲染放弃链)
  @Builder
  HintCaption() {
    if (!this.hasWon && this.hintKeys.size > 0) {
      Row() {
        Blank()
        Text('💡 绿色格子就是正确路线')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .padding(8)
      }
      .width('100%')
    }
  }

  // 重开一局: 同难度重新生成迷宫并重置全部状态
  private restartRound(): void {
    const freshMaze: MazeData = this.generateFreshMaze(this.difficulty)
    this.maze = freshMaze
    this.par = computePar(freshMaze)
    const startPos: MazePosition = { row: 0, col: 0 }
    this.playerPos = startPos
    this.moveCount = 0
    this.starsCollected = 0
    this.elapsedSeconds = 0
    this.hasWon = false
    this.isCompleted = false
    this.isPaused = false
    this.frozenUntilMs = 0
    this.activeEffectText = ''
    this.winStars = 0
    this.showWinOverlay = false
    this.isNewBest = false
    this.portalFlash = false
    this.collectedKeys = new Set<string>()
    this.visitedKeys = new Set<string>()
    this.hintKeys = new Set<string>()
    this.usedPowerupKeys = new Set<string>()
    this.collectedKey = ''
    this.collectFly = false
    this.markVisited(this.playerPos)
    this.startTimer()
    this.syncShellState()
  }

  private togglePause(): void {
    if (this.isCompleted) {
      return
    }
    this.isPaused = !this.isPaused
  }

  // 控制行: 暂停 (计时与移动都停) / 重新开始 (换一局)
  @Builder
  GameControlsRow() {
    Row({ space: 10 }) {
      Button(this.isPaused ? '▶ 继续' : '⏸ 暂停', { type: ButtonType.Capsule })
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor(withColorAlpha(this.wallColor, this.isDarkMode ? '18' : '10'))
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
        .onClick(() => {
          this.togglePause()
        })
      Button('↻ 重新开始', { type: ButtonType.Capsule })
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor(withColorAlpha(this.wallColor, this.isDarkMode ? '18' : '10'))
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
        .onClick(() => {
          this.restartRound()
        })
      Blank()
    }
    .width('100%')
  }

  // 效果横幅: 覆盖在卡片顶部, 不拦截点击
  @Builder
  EffectToast() {
    Column() {
      Row() {
        Text(this.activeEffectText)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
      }
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .borderRadius(999)
      .backgroundColor(this.isDarkMode ? '#3A342C' : '#FFF9EC')
      .border({
        width: 1,
        color: withColorAlpha(this.wallColor, this.isDarkMode ? '40' : '30'),
        style: BorderStyle.Solid
      })
      .shadow({ radius: 12, color: '#22000000', offsetY: 3 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
    .padding({ top: 10 })
    .hitTestBehavior(HitTestMode.None)
  }

  // 胜利庆祝弹窗: ★ 评级 + 用时/步数/胡萝卜 + 新纪录徽章
  @Builder
  WinOverlay() {
    Column() {
      Column({ space: 10 }) {
        Text('🎉')
          .fontSize(44)
        Text('走出迷宫啦！')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Row({ space: 6 }) {
          ForEach([0, 1, 2], (idx: number) => {
            Text('★')
              .fontSize(26)
              .fontColor(idx < this.winStars
                ? '#F59E0B'
                : withColorAlpha(this.wallColor, this.isDarkMode ? '26' : '20'))
          }, (idx: number) => `maze_win_star_${idx}`)
        }
        .justifyContent(FlexAlign.Center)
        Text(`⏱ ${this.formatTime(this.elapsedSeconds)} · 👆 ${this.moveCount} 步 · 🥕 ${this.starsCollected}/${this.maze !== null ? this.maze.starsTotal : 0}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        if (this.isNewBest) {
          Text('🏆 新纪录')
            .fontSize(11)
            .fontColor('#FFFFFF')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(999)
            .backgroundColor('#F59E0B')
        }
        Button('完成', { type: ButtonType.Capsule })
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor(withColorAlpha(this.wallColor, 'E6'))
          .padding({ left: 28, right: 28, top: 8, bottom: 8 })
          .margin({ top: 6 })
          .onClick(() => {
            this.showWinOverlay = false
            this.onRequestClose()
          })
      }
      .padding({ left: 24, right: 24, top: 22, bottom: 20 })
      .borderRadius(20)
      .backgroundColor(this.isDarkMode ? '#2A2520' : '#FDF8EC')
      .border({
        width: 1,
        color: withColorAlpha(this.wallColor, this.isDarkMode ? '38' : '2A'),
        style: BorderStyle.Solid
      })
      .shadow({ radius: 24, color: '#33000000', offsetY: 6 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  // 已答完: 紧凑摘要卡 (时间线步骤详情复用; 新游戏入口走 sheet, 不再内联渲染棋盘)
  @Builder
  AnsweredSummaryCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text('🌀')
          .fontSize(22)
        Column({ space: 2 }) {
          Text('走迷宫')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(this.difficultyLabel)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Text(this.restoredResult !== null && this.restoredResult.completed ? '已完成' : '已放弃')
          .fontSize(10)
          .fontColor('#FFFFFF')
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(999)
          .backgroundColor(this.restoredResult !== null && this.restoredResult.completed ? '#4CAF50' : '#FF9F43')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Row({ space: 4 }) {
        ForEach([0, 1, 2], (idx: number) => {
          Text('★')
            .fontSize(18)
            .fontColor(this.restoredResult !== null && idx < this.restoredResult.stars
              ? '#F59E0B'
              : withColorAlpha(this.wallColor, this.isDarkMode ? '26' : '1E'))
        }, (idx: number) => `maze_sum_star_${idx}`)
      }
      .width('100%')
      Row({ space: 14 }) {
        Text(`⏱ ${this.formatTime(this.elapsedSeconds)}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Text(`👆 ${this.moveCount} 步`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Text(`🥕 ${this.starsCollected}/${this.maze !== null ? this.maze.starsTotal : 0}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
    }
    .padding(14)
    .borderRadius(14)
    .backgroundColor(this.boardBackground)
    .border({
      width: 1,
      color: withColorAlpha(this.wallColor, this.isDarkMode ? '30' : '22'),
      style: BorderStyle.Solid
    })
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder

  MazePanel() {
    Column() {
      if (this.maze !== null) {
        Stack() {
          // 背景层: 单元格网格(不含玩家)
          Column() {
            ForEach(this.maze.cells, (row: MazeCell[], rowIndex: number) => {
              Row() {
                ForEach(row, (cell: MazeCell, colIndex: number) => {
                  this.MazeCellView(cell, rowIndex, colIndex)
                }, (cell: MazeCell, colIndex: number) => `cell_${rowIndex}_${colIndex}`)
              }
              .width('100%')
            }, (row: MazeCell[], rowIndex: number) => `row_${rowIndex}`)
          }
          .width('100%')

          // 前景层: 玩家 overlay(绝对定位, 通过 .position() 滑动)
          if (this.shouldShowPlayer) {
            Column() {
              Text('🐰')
                .fontSize(this.playerSize)
            }
            .width(this.cellSize)
            .height(this.cellSize)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .position({
              x: this.cellGap + this.playerPos.col * (this.cellSize + this.cellGap * 2),
              y: this.cellGap + this.playerPos.row * (this.cellSize + this.cellGap * 2)
            })
            .animation({ duration: 200, curve: Curve.EaseOut })
          }
        }
        .width('100%')
        .padding(this.cellGap * 2)
        .backgroundColor(this.boardBackground)
        .borderRadius(14)
        .border({
          width: 0.5,
          color: withColorAlpha(this.wallColor, this.isDarkMode ? '20' : '14'),
          style: BorderStyle.Solid
        })
      }
    }
    .width('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.boardAreaWidth = newArea.width as number
    })
    .onTouch((e: TouchEvent) => {
      // 阻止事件冒泡到外层 List(scroll)
      e.stopPropagation()
    })
    .priorityGesture(
      PanGesture({ direction: PanDirection.All, distance: SWIPE_MIN_OFFSET })
        .onActionEnd((event: GestureEvent) => {
          if (this.isCompleted) {
            return
          }
          this.handleBoardSwipe(event.offsetX as number, event.offsetY as number)
        })
    )
  }

  private get shouldShowPlayer(): boolean {
    if (this.maze === null) {
      return false
    }
    if (this.isCompleted && this.hasWon) {
      return false
    }
    const cell: MazeCell = this.maze.cells[this.playerPos.row][this.playerPos.col]
    return !cell.isGoal
  }

  @Builder
  MazeCellView(cell: MazeCell, row: number, col: number) {
    Stack() {
      // path 背景
      Column()
        .width(this.cellSize)
        .height(this.cellSize)
        .backgroundColor(this.cellPathColor)

      // 正确路线高亮(放弃后): 纸面上的一抹绿色标记
      if (this.hintKeys.has(row + ',' + col)) {
        Column()
          .width(this.cellSize - 8)
          .height(this.cellSize - 8)
          .borderRadius(this.cellSize * 0.2)
          .backgroundColor(withColorAlpha(CardShellCopy.SUCCESS_GREEN, this.isDarkMode ? '30' : '22'))
          .position({ x: 4, y: 4 })
      }

      // 足迹小圆点: 走过的格子留痕, 起点终点不画; 胡萝卜格在收集后也画
      // (收集前胡萝卜图标渲染在更上层会自然遮住圆点, 无需额外排除)
      if (this.visitedKeys.has(row + ',' + col) && !cell.isStart && !cell.isGoal &&
        (!cell.hasStar || this.collectedKeys.has(row + ',' + col))) {
        Column()
          .width(this.trailDotSize)
          .height(this.trailDotSize)
          .borderRadius(this.trailDotSize / 2)
          .backgroundColor(withColorAlpha(this.wallColor, this.isDarkMode ? '32' : '24'))
          .position({
            x: (this.cellSize - this.trailDotSize) / 2,
            y: (this.cellSize - this.trailDotSize) / 2
          })
      }

      // 墙条: 上、右、下、左(只在有墙时绘制)
      if (cell.walls.top) {
        Column()
          .width(this.cellSize)
          .height(this.wallThickness)
          .backgroundColor(this.wallColor)
          .position({ x: 0, y: 0 })
      }
      if (cell.walls.right) {
        Column()
          .width(this.wallThickness)
          .height(this.cellSize)
          .backgroundColor(this.wallColor)
          .position({ x: this.cellSize - this.wallThickness, y: 0 })
      }
      if (cell.walls.bottom) {
        Column()
          .width(this.cellSize)
          .height(this.wallThickness)
          .backgroundColor(this.wallColor)
          .position({ x: 0, y: this.cellSize - this.wallThickness })
      }
      if (cell.walls.left) {
        Column()
          .width(this.wallThickness)
          .height(this.cellSize)
          .backgroundColor(this.wallColor)
          .position({ x: 0, y: 0 })
      }

      // 中心图标: 终点(小屋) / 胡萝卜 / 收集飞出动画 (玩家已提升为 MazePanel 顶层 overlay)
      if (cell.isGoal) {
        // 目的地印章: 虚线圆角包裹, 强化"纸面地图 + 终点标记"语义
        Column()
          .width(this.cellSize - 6)
          .height(this.cellSize - 6)
          .border({
            width: 1.5,
            color: withColorAlpha(this.wallColor, this.isDarkMode ? '50' : '38'),
            style: BorderStyle.Dashed
          })
          .borderRadius(this.cellSize * 0.22)
          .position({ x: 3, y: 3 })
        Column() {
          Text('🏠')
            .fontSize(this.goalSize)
        }
        .width(this.cellSize)
        .height(this.cellSize)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (cell.portalTo !== undefined && cell.portalTo !== null) {
        // 传送门 (挑战档): 成对出现的 🌀
        Column() {
          Text('🌀')
            .fontSize(this.starSize + 2)
        }
        .width(this.cellSize)
        .height(this.cellSize)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (cell.powerup !== undefined && cell.powerup !== '' &&
        !this.usedPowerupKeys.has(row + ',' + col)) {
        // 道具/宝箱: 未使用前显示图标
        Column() {
          Text(cell.powerup === 'treasure' ? '🎁' : (cell.powerup === 'freeze' ? '❄️' : '🧭'))
            .fontSize(this.starSize + 2)
        }
        .width(this.cellSize)
        .height(this.cellSize)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (cell.hasStar && !this.collectedKeys.has(row + ',' + col)) {
        // 胡萝卜 (未收集): collectedKeys 是 @Local Set, 修改后触发该格重渲染隐藏胡萝卜
        Column() {
          Text('🥕')
            .fontSize(this.starSize)
        }
        .width(this.cellSize)
        .height(this.cellSize)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.collectedKey === row + ',' + col) {
        // 收集飞出: 胡萝卜定格一帧后放大、上浮、淡出
        Column() {
          Text('🥕')
            .fontSize(this.starSize)
        }
        .width(this.cellSize)
        .height(this.cellSize)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .scale({
          x: this.collectFly ? 1.6 : 1,
          y: this.collectFly ? 1.6 : 1
        })
        .opacity(this.collectFly ? 0 : 1)
        .translate({ y: this.collectFly ? -8 : 0 })
        .animation({ duration: 300, curve: Curve.EaseOut })
      }
    }
    .width(this.cellSize)
    .height(this.cellSize)
    .margin(this.cellGap)
    .translate({
      x: this.getBumpOffset(row, col, 'h'),
      y: this.getBumpOffset(row, col, 'v')
    })
    .animation({ duration: 50, curve: Curve.EaseOut })
    .scale({
      x: this.pressedCellKey === `${row},${col}` ? 0.94 : 1,
      y: this.pressedCellKey === `${row},${col}` ? 0.94 : 1
    })
    .animation({ duration: 80, curve: Curve.EaseOut })
    .onClick((): void => {
      this.handleCellPress(row, col)
    })
    .onTouch((e: TouchEvent) => {
      // 按下缩放反馈(事件继续冒泡至面板层统一拦截, 不阻断手势)
      if (e.type === TouchType.Down) {
        this.handleCellTouchDown(row, col)
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.handleCellTouchUp()
      }
    })
  }

  @Builder
  StatsGrid() {
    Row({ space: 8 }) {
      // 时间卡片
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text('⏱')
            .fontSize(11)
          Text('时间')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        Text(this.formatTime(this.elapsedSeconds))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        if (this.bestTimeSeconds >= 0) {
          Text(`最佳 ${this.formatTime(this.bestTimeSeconds)}`)
            .fontSize(10)
            .fontColor(this.isNewBest ? $r('app.color.status_success') : $r('app.color.text_tertiary'))
        }
      }
      .layoutWeight(1)
      .padding(10)
      .borderRadius(10)
      .backgroundColor(withColorAlpha(this.wallColor, this.isDarkMode ? '12' : '08'))
      .border({
        width: 1,
        color: this.isNewBest
          ? withColorAlpha(CardShellCopy.SUCCESS_GREEN, '60')
          : withColorAlpha(this.wallColor, this.isDarkMode ? '28' : '1C'),
        style: BorderStyle.Solid
      })

      // 步数卡片
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text('👆')
            .fontSize(11)
          Text('步数')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        Text(this.moveCount.toString())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        if (this.bestMoves >= 0) {
          Text(`最佳 ${this.bestMoves}`)
            .fontSize(10)
            .fontColor(this.isNewBest ? $r('app.color.status_success') : $r('app.color.text_tertiary'))
        }
      }
      .layoutWeight(1)
      .padding(10)
      .borderRadius(10)
      .backgroundColor(withColorAlpha('#B45309', this.isDarkMode ? '12' : '08'))
      .border({
        width: 1,
        color: this.isNewBest
          ? withColorAlpha(CardShellCopy.SUCCESS_GREEN, '60')
          : withColorAlpha('#B45309', this.isDarkMode ? '28' : '1C'),
        style: BorderStyle.Solid
      })

      // 收藏卡片(胡萝卜)
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text('🥕')
            .fontSize(11)
          Text('胡萝卜')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        Text(this.maze !== null
          ? `${this.starsCollected}/${this.maze.starsTotal}`
          : '0/0')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        if (this.bestStars >= 0) {
          Text(`最佳 ${this.bestStars}`)
            .fontSize(10)
            .fontColor(this.isNewBest ? $r('app.color.status_success') : $r('app.color.text_tertiary'))
        }
      }
      .layoutWeight(1)
      .padding(10)
      .borderRadius(10)
      .backgroundColor(withColorAlpha('#FF9F43', this.isDarkMode ? '10' : '08'))
      .border({
        width: 1,
        color: this.isNewBest
          ? withColorAlpha(CardShellCopy.SUCCESS_GREEN, '60')
          : withColorAlpha('#FF9F43', this.isDarkMode ? '22' : '18'),
        style: BorderStyle.Solid
      })
    }
      // 评级卡片 (v3: 胜利按 par 步数+胡萝卜评定 1-3 星)
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text('⭐')
            .fontSize(11)
          Text('评级')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        Text(this.winStars > 0 ? `${this.winStars}★` : '-')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        if (this.bestRating >= 0) {
          Text(`最佳 ${this.bestRating}★`)
            .fontSize(10)
            .fontColor(this.isNewBest ? $r('app.color.status_success') : $r('app.color.text_tertiary'))
        }
      }
      .layoutWeight(1)
      .padding(10)
      .borderRadius(10)
      .backgroundColor(withColorAlpha('#F59E0B', this.isDarkMode ? '10' : '08'))
      .border({
        width: 1,
        color: this.isNewBest
          ? withColorAlpha('#22C55E', '60')
          : withColorAlpha('#F59E0B', this.isDarkMode ? '22' : '18'),
        style: BorderStyle.Solid
      })

    .width('100%')
  }
}