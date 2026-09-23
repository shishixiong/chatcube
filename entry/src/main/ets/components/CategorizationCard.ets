/**
 * CategorizationCard - 分类小管家互动卡片
 *
 * 设计语言对齐 NumberPuzzleCard / MathQuizCard 卡片族 + docs/categorization-game.html 原型:
 * - CardShell 统一外壳 (head/stem/feedback), direct 模式 (usesConfirm: false)
 * - 物品白底卡 + 桶虚线轮廓 (绘本感), 拖拽或"先点物品再点桶"两种交互
 * - 物品/桶图标: CategorizationIconBank 解析 rawfile SVG (kids/icons/),
 *   未命中退化 emoji → 文字 (题库外自由题仍可玩)
 * - 双卡片统计 (时间 / 进度)
 * - 完成反馈横幅含「为什么这样分」讲解 (why); 答错轻摇 + 轻提示文字, 不扣分
 * - 严格的输入校验: 桶数 2-3、物品数 4/6/9、bin_index 合法、每桶 ≥2 物品
 *
 * 公共 API: toolCall / isAnswered / answeredPayload / largeSize / onAnswer
 * 导出: CategorizationResult / CategorizationBin / CategorizationItem
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { getPreferencesService, PreferenceKeys } from '../services/PreferencesService'
import { validateAndNormalizeCategorization, NormalizedCategorizationData } from '../utils/CategorizationValidation'
import { resolveItemIconPath, resolveBinGlyphPath } from '../utils/CategorizationIconBank'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { curves } from '@kit.ArkUI'
import { CardShell } from './cardshell/CardShell'
import { CardShellConfig } from './cardshell/CardShellTypes'
import { CardShellState } from './cardshell/CardShellState'

const DOMAIN = 0x0002
const TAG = 'CategorizationCard'
const GIVEUP_ORANGE: string = '#FF9F43'
const ERROR_RED: string = '#FF3B30'

// ================ 弹性动画预设 (温馨童趣视觉签名) ================
// SPRING_QUICK: 选中/取消类瞬时反馈 (180ms, 略低 damping = 更"弹")
// SPRING_GENTLE: 桶高亮/缩放 (360ms, 较高 damping = 优雅, 避免来回震荡)
const SPRING_QUICK: AnimateParam = { duration: 180, curve: curves.springMotion(0.6, 0.7) }
const SPRING_GENTLE: AnimateParam = { duration: 360, curve: curves.springMotion(0.4, 0.8) }

// 桶主题暖色 (与 NumberPuzzleCard 琥珀协调, 避免撞色)
const BIN_COLOR_WARM: string = '#FB923C'   // 暖橙
const BIN_COLOR_HONEY: string = '#FBBF24'  // 蜂蜜黄
const BIN_COLOR_MINT: string = '#34D399'   // 薄荷绿 (冷色平衡)

// ================ 物品呼吸 / 引导动画参数 ================
// 这些之前散落在 ItemCard / startItemAnim / shakeItem 里, 抽出来便于调参。
const ITEM_ANIM_INTERVAL_MS: number = 50         // 呼吸 setInterval 频率
const ITEM_ANIM_PHASE_STEP: number = 6            // 每 tick 推进的相位 (度), 6° / 50ms = 120°/s
const ITEM_BREATHING_AMPLITUDE: number = 0.03      // 未选中物品 ±3% scale (sin 驱动)
const ITEM_PHASE_OFFSET_PER_INDEX: number = 30     // 多物品间的相位差, 避免整齐划一
const ITEM_TUTORIAL_BOB_AMPLITUDE: number = 1.5    // 引导态首物品 bobbing 浮动幅度 (vp)
const WRONG_DROP_SHAKE_MS: number = 400            // 拖错时物品震动持续时长

// ================ 拖拽命中检测 ================
const DRAG_START_DISTANCE: number = 5              // PanGesture 触发阈值 (vp), 避免误触
const DRAGGING_ITEM_SCALE: number = 1.2            // 拖动中物品放大
const DRAGGING_SHADOW_RADIUS: number = 12           // 拖动阴影半径
const HOVERED_BIN_SCALE: number = 1.05             // 拖到桶上方时桶放大

// 桶的窗口空间 bbox, 由 onAreaChange 同步, 供拖拽命中检测使用
interface BinRect {
  x: number
  y: number
  w: number
  h: number
}

// ================ 绘本感视觉 (docs/categorization-game.html 原型) ================
const ITEM_SURFACE: string = '#FFFDF8'   // 物品卡固定浅色面 (贴纸感, 双模式一致, 保证暖色图标对比度)
const BIN_LETTER_BG: string = '#8B72E0'  // 字母桶色块 (m/p/b/A/B/C 拼音英文主题无类别字形的兜底)
const BIN_LETTER_INK: string = '#6A49DB'
const WRONG_HINT_MS: number = 2000       // 答错轻提示显示时长 (与 shake 同源触发)

// ================ 公共接口 ================
export interface CategorizationResult {
  theme: string
  difficulty: number
  correct: number
  total: number
  time_seconds: number
  wrong_attempts: number
  completed: boolean
}

export interface CategorizationBin {
  name: string
  emoji: string
}

export interface CategorizationItem {
  name: string
  emoji: string
  bin_index: number
}

// 校验 / 解析逻辑已抽到 utils/CategorizationValidation.ets, 此处仅复用其类型

// ================ 组件 ================
// 拖拽 + 点选双交互均已实现 (spec §7.1)。

@ComponentV2
export struct CategorizationCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  // 题面态
  @Local theme: string = ''
  @Local instruction: string = ''
  @Local bins: CategorizationBin[] = []
  @Local items: CategorizationItem[] = []
  @Local difficulty: number = 1
  @Local validationError: string = ''
  // 「为什么这样分」讲解 (AI 可选字段, 完成横幅展示)
  @Local why: string = ''
  // 图标路径 (与 bins/items 下标对齐): kids/icons/*.svg, 未命中为 ''
  @Local binGlyphPaths: string[] = []
  @Local itemIconPaths: string[] = []
  // 答错轻提示 (WRONG_HINT_MS 后自动消失; 不用全局 toast —— 卡片在聊天气泡内)
  @Local wrongHint: string = ''

  // 游戏态
  @Local placedItems: number[] = []
  @Local correctCount: number = 0
  @Local wrongAttempts: number = 0
  @Local elapsedSeconds: number = 0
  @Local isCompleted: boolean = false
  @Local hasWon: boolean = false
  @Local selectedItemIndex: number = -1
  @Local hoveredBinIndex: number = -1
  @Local shakingItemIndex: number = -1
  @Local itemPressedIndex: number = -1

  // 拖拽态: draggingItemIndex = 当前被拖动的物品; dragOffsetX/Y = 实时位移 (驱动 scale + translate)
  @Local draggingItemIndex: number = -1
  @Local dragOffsetX: number = 0
  @Local dragOffsetY: number = 0

  // 引导状态: 首次玩时显示气泡 + 首物品 bobbing 动画
  @Local isFirstPlay: boolean = true

  // 共享物品动画相位: 所有未选中物品的呼吸 scale 派生于此, 首物品在 tutorial 状态下额外叠加 translateY 浮动
  @Local itemAnimPhase: number = 0

  // 最佳成绩: 速度王 (任意完成) + 全对王 (correct===total), 按 difficulty 区分
  @Local bestTimeSeconds: number = -1
  @Local bestPerfectSeconds: number = -1
  @Local isNewBest: boolean = false
  // 防止在 loadBestScores 完成前 saveBestScoresIfImproved 用 stale -1 覆盖已有最佳
  @Local bestScoresLoaded: boolean = false

  // CardShell 外壳配置/状态 (direct 模式: usesConfirm=false, 完成态由 state.submitted 驱动)
  @Local shellConfig: CardShellConfig = {
    title: '分类小管家',
    subtitle: '',
    icon: $r('sys.symbol.folder'),
    stem: '',
    hasAudio: false,
    usesConfirm: false,
    feedbackTitleCorrect: '分类完成！',
    correctAnswerLabel: ''
  }
  private shellState: CardShellState = new CardShellState()

  // 非响应式
  private timerId: number = -1
  private shakeTimerId: number = -1
  private wrongHintTimerId: number = -1
  private itemAnimTimerId: number = -1
  private startTime: number = 0

  // 拖拽命中检测: 各桶的窗口空间 bbox (globalPosition + width/height)。
  // 由 BinCell 的 onAreaChange 实时同步, 非响应式避免每 tick 触发重渲染。
  private binRects: Map<number, BinRect> = new Map()

  // ================ 主题派生 (NumberPuzzleCard 同款 getter) ================
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  // ================ 生命周期 ================
  aboutToAppear(): void {
    const v = this.validateAndNormalize()
    if (!v.ok) {
      this.validationError = v.error
      hilog.warn(DOMAIN, TAG, `validation failed: ${v.error}`)
      return
    }
    this.theme = v.theme
    this.instruction = v.instruction
    this.bins = v.bins
    this.items = v.items
    this.difficulty = v.difficulty
    this.why = v.why
    this.placedItems = this.createPlacedArray(this.items.length)
    // 最佳成绩两个分支都需要: 未回答时给新纪录检测用; 已回答时在线视图由
    // loadBestScores 完成后重建反馈区, 在 feedbackDetail 末尾展示「最佳 X:Y · 0 错」
    this.loadBestScores(this.difficulty)
    if (this.isAnswered) {
      this.parseAnsweredPayload()
      // 在线视图: 视为已看过引导 (不会显示气泡)
      this.isFirstPlay = false
      // 恢复路径同步 shell 终局状态 (按 hasWon; 解析失败走 validationError 分支不同步)
      if (this.validationError === '') {
        this.syncOutcomeShellState()
      }
    } else {
      this.shuffleItems()
      this.startTimer()
      this.startItemAnim()
      this.loadTutorialState()
    }
    // 图标路径解析 (与 bins/items 下标对齐; shuffleItems 只重排 items, 元素值不变)
    this.binGlyphPaths = this.resolveBinGlyphPaths()
    this.itemIconPaths = this.resolveItemIconPaths()
    // 校验通过后重建 shell 配置 (subtitle/stem 依赖已解析的题面数据)
    this.shellConfig = {
      title: '分类小管家',
      subtitle: `${this.theme} · ${this.getDifficultyLabel()} · ${this.items.length}件 ${this.bins.length}桶`,
      icon: $r('sys.symbol.folder'),
      stem: this.instruction,
      hasAudio: false,
      usesConfirm: false,
      feedbackTitleCorrect: '分类完成！',
      correctAnswerLabel: ''
    }
  }

  aboutToDisappear(): void {
    this.stopTimer()
    this.stopItemAnim()
    if (this.shakeTimerId >= 0) {
      clearTimeout(this.shakeTimerId)
      this.shakeTimerId = -1
    }
    if (this.wrongHintTimerId >= 0) {
      clearTimeout(this.wrongHintTimerId)
      this.wrongHintTimerId = -1
    }
  }

  // 异步读 preferences, 决定是否首次玩 (显示引导气泡)
  private async loadTutorialState(): Promise<void> {
    try {
      const seen = await getPreferencesService().getCategorizationTutorialSeen()
      this.isFirstPlay = !seen
    } catch (_e) {
      // 读取失败视为首次玩, 仍然显示引导 (更保守)
      this.isFirstPlay = true
    }
  }

  private startItemAnim(): void {
    this.stopItemAnim()
    // ITEM_ANIM_PHASE_STEP° / ITEM_ANIM_INTERVAL_MS ms = 120°/s, |sin| 半周期 1.5s,
    // 驱动首物品 bobbing + 所有物品呼吸 scale
    this.itemAnimTimerId = setInterval(() => {
      this.itemAnimPhase = (this.itemAnimPhase + ITEM_ANIM_PHASE_STEP) % 360
    }, ITEM_ANIM_INTERVAL_MS)
  }

  private stopItemAnim(): void {
    if (this.itemAnimTimerId >= 0) {
      clearInterval(this.itemAnimTimerId)
      this.itemAnimTimerId = -1
    }
  }

  // 用户首次点击物品后, 关闭引导并持久化。
  // 同时停止呼吸 setInterval(50ms)——引导已尽其职, 物品不再需要 bobbing / 呼吸 scale,
  // 节省每 50ms × N 物品的属性求值开销 (难度 3 = 9 件 × 20/s ≈ 180 次/s)。
  private async dismissTutorial(): Promise<void> {
    if (!this.isFirstPlay) {
      return
    }
    this.isFirstPlay = false
    this.stopItemAnim()
    try {
      await getPreferencesService().setCategorizationTutorialSeen(true)
    } catch (_e) {
      hilog.warn(DOMAIN, TAG, 'failed to persist tutorial seen flag')
    }
  }

  // 异步读最佳成绩。未回答时供新纪录检测; 已回答(在线恢复)时加载完成后经
  // syncShellStateIfSettled 重建反馈区, 补上 feedbackDetail 的「最佳 X:Y · 0 错」行
  private async loadBestScores(difficulty: number): Promise<void> {
    try {
      const prefs = getPreferencesService()
      const timeKey = `${PreferenceKeys.CATEGORIZATION_BEST_TIME_PREFIX}${difficulty}`
      const perfectKey = `${PreferenceKeys.CATEGORIZATION_BEST_PERFECT_PREFIX}${difficulty}`
      // Promise.all 把两次 getNumber 批成 1 次 render, 避免 3 次 post-await 触发连续重绘。
      // ArkTS 不支持解构声明 (arkts-no-destruct-decls), 用数组索引代替。
      const results: number[] = await Promise.all([
        prefs.getNumber(timeKey, -1),
        prefs.getNumber(perfectKey, -1)
      ])
      this.bestTimeSeconds = results[0]
      this.bestPerfectSeconds = results[1]
      this.bestScoresLoaded = true
      // 加载晚于 shell 状态构建时(在线恢复路径 / 极快通关), 重建一次补上最佳成绩行
      this.syncShellStateIfSettled()
    } catch (_e) {
      this.bestTimeSeconds = -1
      this.bestPerfectSeconds = -1
      // 加载失败也要解除守卫, 否则 saveBestScoresIfImproved 永远不写
      this.bestScoresLoaded = true
      // 失败路径 bestPerfectSeconds=-1, 重建后最佳成绩行自然缺席
      this.syncShellStateIfSettled()
      hilog.warn(DOMAIN, TAG, 'failed to load best scores')
    }
  }

  // 在 evaluateWin 命中后异步调用, 不阻塞 onAnswer。
  // 速度王: 任意完成的最快; 全对王: 仅 wrongAttempts===0 的最快。
  private async saveBestScoresIfImproved(): Promise<void> {
    // 防止 race: loadBestScores 未完成时 bestTimeSeconds/bestPerfectSeconds 是 stale 的 -1,
    // 会让任何一次完成都被当成"新纪录"覆盖已有最佳. 这种情况直接放弃本次保存.
    if (!this.bestScoresLoaded) {
      return
    }
    try {
      const prefs = getPreferencesService()
      const timeKey = `${PreferenceKeys.CATEGORIZATION_BEST_TIME_PREFIX}${this.difficulty}`
      const perfectKey = `${PreferenceKeys.CATEGORIZATION_BEST_PERFECT_PREFIX}${this.difficulty}`
      const isNewBestTime = this.bestTimeSeconds < 0 || this.elapsedSeconds < this.bestTimeSeconds
      const isNewBestPerfect = this.wrongAttempts === 0 &&
        (this.bestPerfectSeconds < 0 || this.elapsedSeconds < this.bestPerfectSeconds)
      if (isNewBestTime) {
        await prefs.setNumber(timeKey, this.elapsedSeconds)
        this.bestTimeSeconds = this.elapsedSeconds
      }
      if (isNewBestPerfect) {
        await prefs.setNumber(perfectKey, this.elapsedSeconds)
        this.bestPerfectSeconds = this.elapsedSeconds
      }
      this.isNewBest = isNewBestTime || isNewBestPerfect
      // 异步写回完成后重建反馈区 —— 原 WinBanner 的 '新纪录' 药丸与最佳成绩行
      // 同样在保存完成后才出现(响应式读取); 迁移后需重建快照字符串
      this.syncShellStateIfSettled()
    } catch (_e) {
      // 持久化失败不阻塞 UI
      hilog.warn(DOMAIN, TAG, 'failed to save best scores')
    }
  }

  private formatBestTime(seconds: number): string {
    const m = Math.floor(seconds / 60)
    const s = seconds % 60
    const sStr = s < 10 ? `0${s}` : `${s}`
    return `${m}:${sStr}`
  }

  private createPlacedArray(len: number): number[] {
    const arr: number[] = []
    for (let i = 0; i < len; i++) {
      arr.push(-1)
    }
    return arr
  }

  // 题库图标解析: 桶名/物品名 → rawfile SVG 路径; 未命中 '' (渲染层退化 emoji → 文字)
  private resolveBinGlyphPaths(): string[] {
    const paths: string[] = []
    for (let i = 0; i < this.bins.length; i++) {
      paths.push(resolveBinGlyphPath(this.bins[i].name))
    }
    return paths
  }

  private resolveItemIconPaths(): string[] {
    const paths: string[] = []
    for (let i = 0; i < this.items.length; i++) {
      paths.push(resolveItemIconPath(this.items[i].name))
    }
    return paths
  }

  // ================ 校验 / 解析 ================
  // 校验逻辑已抽到 utils/CategorizationValidation.ets (纯函数, 可单测)。
  // 此处仅做参数转发, 保留组件内访问入口。
  private validateAndNormalize(): NormalizedCategorizationData {
    return validateAndNormalizeCategorization(this.toolCall.arguments)
  }

  private parseAnsweredPayload(): void {
    if (this.answeredPayload === '') {
      return
    }
    try {
      const result = JSON.parse(this.answeredPayload) as CategorizationResult
      this.correctCount = result.correct
      this.wrongAttempts = result.wrong_attempts
      this.elapsedSeconds = Math.floor(result.time_seconds)
      this.hasWon = result.completed === true && result.correct === result.total
      this.isCompleted = true
      // 还原终局: 所有物品落到正确桶
      const placed: number[] = []
      for (let i = 0; i < this.items.length; i++) {
        placed.push(this.items[i].bin_index)
      }
      this.placedItems = placed
    } catch (_e) {
      this.validationError = '已答数据格式错误'
    }
  }

  // ================ 业务逻辑 ================
  private shuffleItems(): void {
    const shuffled: CategorizationItem[] = []
    for (let i = 0; i < this.items.length; i++) {
      shuffled.push(this.items[i])
    }
    for (let i = shuffled.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1))
      const tmp = shuffled[i]
      shuffled[i] = shuffled[j]
      shuffled[j] = tmp
    }
    this.items = shuffled
    this.placedItems = this.createPlacedArray(this.items.length)
  }

  private startTimer(): void {
    this.stopTimer()
    this.startTime = Date.now()
    this.timerId = setInterval(() => {
      if (!this.isCompleted && this.startTime > 0) {
        this.elapsedSeconds = Math.floor((Date.now() - this.startTime) / 1000)
      }
    }, 500)
  }

  private stopTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  private handleItemClick(itemIndex: number): void {
    if (this.isCompleted || this.placedItems[itemIndex] >= 0) {
      return
    }
    if (this.selectedItemIndex === itemIndex) {
      this.selectedItemIndex = -1
    } else {
      this.selectedItemIndex = itemIndex
      // 首次玩首次点选: 关闭引导气泡 (fire-and-forget 持久化)
      this.dismissTutorial()
    }
  }

  private handleBinClick(binIndex: number): void {
    if (this.isCompleted || this.selectedItemIndex < 0) {
      return
    }
    const targetIdx = this.selectedItemIndex
    this.selectedItemIndex = -1
    this.handleDrop(targetIdx, binIndex)
  }

  private handleDrop(itemIndex: number, binIndex: number): void {
    if (this.isCompleted) {
      return
    }
    if (binIndex < 0 || binIndex >= this.bins.length) {
      return
    }
    if (itemIndex < 0 || itemIndex >= this.items.length) {
      return
    }
    if (this.placedItems[itemIndex] >= 0) {
      return
    }
    const item = this.items[itemIndex]
    if (item.bin_index === binIndex) {
      // 命中: 写入对应桶, 同步 correctCount
      const placed: number[] = []
      for (let i = 0; i < this.placedItems.length; i++) {
        placed.push(i === itemIndex ? binIndex : this.placedItems[i])
      }
      this.placedItems = placed
      this.correctCount = this.correctCount + 1
      hilog.info(DOMAIN, TAG, `correct drop: item=${itemIndex} bin=${binIndex}, progress=${this.correctCount}/${this.items.length}`)
      this.evaluateWin()
    } else {
      this.wrongAttempts = this.wrongAttempts + 1
      this.shakeItem(itemIndex)
      this.showWrongHint(item.name)
      hilog.info(DOMAIN, TAG, `wrong drop: item=${itemIndex} expected=${item.bin_index} got=${binIndex}`)
    }
  }

  private shakeItem(itemIndex: number): void {
    this.shakingItemIndex = itemIndex
    if (this.shakeTimerId >= 0) {
      clearTimeout(this.shakeTimerId)
    }
    this.shakeTimerId = setTimeout(() => {
      this.shakingItemIndex = -1
      this.shakeTimerId = -1
    }, WRONG_DROP_SHAKE_MS)
  }

  // 答错轻提示: 与 shake 同源触发, WRONG_HINT_MS 后自动消失
  // (原型 toast 的气泡内等价物, 只提示不扣分, 不打断孩子)
  private showWrongHint(itemName: string): void {
    this.wrongHint = `再想想～「${itemName}」不是放这里哦`
    if (this.wrongHintTimerId >= 0) {
      clearTimeout(this.wrongHintTimerId)
    }
    this.wrongHintTimerId = setTimeout(() => {
      this.wrongHint = ''
      this.wrongHintTimerId = -1
    }, WRONG_HINT_MS)
  }

  // ================ shell 状态同步 ================
  // 判胜同步: 反馈横幅 + 头部药丸。注意调用时 isNewBest 通常还是 false
  // (saveBestScoresIfImproved 异步写回后才置 true, 届时单独升级为 '新纪录')。
  private syncWinShellState(): void {
    this.shellState.submitted = true
    this.shellState.isCorrect = true
    this.shellState.feedbackTitle = '分类完成！'
    this.shellState.feedbackDetail =
      `${this.correctCount}/${this.items.length} · ${this.formatBestTime(this.elapsedSeconds)} · 失败 ${this.wrongAttempts} 次`
    // 原 WinBanner 的最佳成绩行(全对王): 仅在已加载到有效最佳 (>= 0) 时追加, 与迁移前条件渲染一致
    if (this.bestPerfectSeconds >= 0) {
      this.shellState.feedbackDetail += `\n最佳 ${this.formatBestTime(this.bestPerfectSeconds)} · 0 错`
    }
    // 「为什么这样分」教学讲解 (AI 可选字段 why, 校验层已 trim + 截断)
    if (this.why !== '') {
      this.shellState.feedbackDetail += `\n${this.why}`
    }
    this.shellState.headPill = this.isNewBest ? '新纪录' : '已完成'
    this.shellState.headPillColor = '#4CAF50'
  }

  // loadBestScores / saveBestScoresIfImproved 异步完成后调用:
  // 若终局状态已构建 (hasWon), 重建反馈区 —— 原 WinBanner 响应式读取 bestPerfectSeconds,
  // 迁移后 feedbackDetail 是快照字符串, 需重建才能补上/刷新「最佳 X:Y · 0 错」行。
  private syncShellStateIfSettled(): void {
    if (this.hasWon) {
      this.syncWinShellState()
    }
  }

  // 已答恢复同步: 按 hasWon 恢复终局。恢复路径不跑 saveBestScoresIfImproved,
  // isNewBest 恒 false, 药丸固定 '已完成' / '已放弃'。
  private syncOutcomeShellState(): void {
    if (this.hasWon) {
      this.syncWinShellState()
    } else {
      this.shellState.headPill = '已放弃'
      this.shellState.headPillColor = '#FF9F43'
    }
  }

  private evaluateWin(): void {
    let allPlaced = true
    for (let i = 0; i < this.placedItems.length; i++) {
      if (this.placedItems[i] < 0) {
        allPlaced = false
        break
      }
    }
    if (!allPlaced) {
      return
    }
    this.stopTimer()
    this.isCompleted = true
    this.hasWon = true
    this.syncWinShellState()
    this.submitResult(true)
    // 异步持久化最佳成绩, 不阻塞 onAnswer 回传 (race-guard 防止 stale -1 覆盖)
    this.saveBestScoresIfImproved()
  }

  private handleGiveUp(): void {
    if (this.isCompleted) {
      return
    }
    this.stopTimer()
    this.isCompleted = true
    this.hasWon = false
    // 放弃只改头部药丸, 不置 submitted —— 与原行为一致 (WinBanner 仅 hasWon 时渲染)
    this.shellState.headPill = '已放弃'
    this.shellState.headPillColor = '#FF9F43'
    this.submitResult(false)
  }

  // 撤回: 点击桶内已归位的物品, 取出回到 ItemsLayer。
  // 若该物品原本正确归类, correctCount 同步扣减; wrongAttempts 不动 (累计指标)。
  private handleUnplace(itemIndex: number): void {
    if (this.isCompleted) {
      return
    }
    const bin = this.placedItems[itemIndex]
    if (bin < 0) {
      return
    }
    if (this.items[itemIndex].bin_index === bin) {
      this.correctCount = Math.max(0, this.correctCount - 1)
    }
    const next: number[] = []
    for (let i = 0; i < this.placedItems.length; i++) {
      next.push(i === itemIndex ? -1 : this.placedItems[i])
    }
    this.placedItems = next
    hilog.info(DOMAIN, TAG, `unplace: item=${itemIndex} from bin=${bin}`)
  }

  // ================ 拖拽手势 handler ================
  // PanGesture 链: onActionStart 设 draggingItemIndex, onActionUpdate 跟随手指 + 更新 hoveredBinIndex,
  // onActionEnd 视 hoveredBinIndex 决定 handleDrop 或弹回。
  private handleDragStart(itemIndex: number): void {
    if (this.isCompleted || this.isAnswered) {
      return
    }
    // 已归位的物品不允许起拖 (撤回走 handleUnplace 独立路径)
    if (this.placedItems[itemIndex] >= 0) {
      return
    }
    this.draggingItemIndex = itemIndex
    this.dragOffsetX = 0
    this.dragOffsetY = 0
    // 起拖即关闭引导 (与点击行为一致)
    this.dismissTutorial()
  }

  private handleDragUpdate(offsetX: number, offsetY: number, globalX: number, globalY: number): void {
    if (this.draggingItemIndex < 0) {
      return
    }
    this.dragOffsetX = offsetX
    this.dragOffsetY = offsetY
    this.hoveredBinIndex = this.hitTestBin(globalX, globalY)
  }

  private handleDragEnd(itemIndex: number): void {
    if (this.draggingItemIndex !== itemIndex) {
      return
    }
    const targetBin = this.hoveredBinIndex
    this.draggingItemIndex = -1
    this.dragOffsetX = 0
    this.dragOffsetY = 0
    this.hoveredBinIndex = -1
    if (targetBin >= 0) {
      this.handleDrop(itemIndex, targetBin)
    }
  }

  private submitResult(completed: boolean): void {
    // 通关: correctCount 即正确数; 放弃: 已落桶且 bin 对的为正确
    let correct = 0
    if (completed) {
      correct = this.correctCount
    } else {
      for (let i = 0; i < this.placedItems.length; i++) {
        if (this.placedItems[i] >= 0 && this.placedItems[i] === this.items[i].bin_index) {
          correct = correct + 1
        }
      }
    }
    const seconds = this.elapsedSeconds
    const result: CategorizationResult = {
      theme: this.theme,
      difficulty: this.difficulty,
      correct,
      total: this.items.length,
      time_seconds: seconds,
      wrong_attempts: this.wrongAttempts,
      completed
    }
    hilog.info(DOMAIN, TAG, `submit: ${JSON.stringify(result)}`)
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
  }

  // ================ 辅助方法 ================
  private getDifficultyLabel(): string {
    if (this.difficulty === 1) {
      return '入门'
    }
    if (this.difficulty === 2) {
      return '简单'
    }
    return '进阶'
  }

  private getBinAccentColor(binIndex: number): string {
    if (binIndex === 0) {
      return BIN_COLOR_WARM
    }
    if (binIndex === 1) {
      return BIN_COLOR_HONEY
    }
    return BIN_COLOR_MINT
  }

  private countPlacedInBin(binIndex: number): number {
    let count = 0
    for (let i = 0; i < this.placedItems.length; i++) {
      if (this.placedItems[i] === binIndex) {
        count++
      }
    }
    return count
  }

  // 返回该桶内已归位物品的 index 数组 (按 placed 顺序, 用于在桶内渲染 mini item)
  private getItemsInBin(binIndex: number): number[] {
    const result: number[] = []
    for (let i = 0; i < this.placedItems.length; i++) {
      if (this.placedItems[i] === binIndex) {
        result.push(i)
      }
    }
    return result
  }

  // 同步桶的窗口空间 bbox. 由 BinCell.onAreaChange 调用, 非响应式。
  private updateBinRect(binIndex: number, area: Area): void {
    // Area.globalPosition.x/y 类型是 Length (string | number), 运行时通常是 number vp。
    // 强转为 number 以便后续坐标比较 (与 FingerInfo.globalX/Y 同一坐标空间)。
    const rect: BinRect = {
      x: area.globalPosition.x as number,
      y: area.globalPosition.y as number,
      w: area.width as number,
      h: area.height as number
    }
    this.binRects.set(binIndex, rect)
  }

  // 命中检测: 给定窗口坐标, 返回包含该点的桶 index, 找不到返回 -1
  private hitTestBin(globalX: number, globalY: number): number {
    const it = this.binRects.entries()
    let entry = it.next()
    while (!entry.done) {
      const idx = entry.value[0] as number
      const rect = entry.value[1] as BinRect
      if (globalX >= rect.x && globalX <= rect.x + rect.w
        && globalY >= rect.y && globalY <= rect.y + rect.h) {
        return idx
      }
      entry = it.next()
    }
    return -1
  }

  private hasUnplacedItem(): boolean {
    for (let i = 0; i < this.placedItems.length; i++) {
      if (this.placedItems[i] < 0) {
        return true
      }
    }
    return false
  }

  // ================ 主 build ================
  build() {
    if (this.validationError !== '') {
      // 坏题兜底分支: 保留原卡片底色 (不走 shell, 避免罕见路径视觉回归)
      Column() {
        this.ErrorPlaceholder()
      }
      .width('100%')
      .padding(this.largeSize ? 24 : 14)
      .backgroundColor(this.largeSize ? Color.Transparent : this.themeAiBubble)
      .borderRadius(this.largeSize ? 0 : 14)
      .border(this.largeSize
        ? { width: 0, color: Color.Transparent, style: BorderStyle.Solid }
        : { width: 1, color: $r('app.color.divider'), style: BorderStyle.Solid })
      .onTouch((e: TouchEvent) => e.stopPropagation())
    } else {
      CardShell({
        config: this.shellConfig,
        state: this.shellState,
        isAnswered: false,
        largeSize: this.largeSize,
        blockTouch: true
      }) {
        this.BinRow()
        this.ItemsLayer()
        this.StatsGrid()
        if (!this.isCompleted) {
          this.ActionRow()
        }
      }
    }
  }

  // ================ 子区块 ================
  @Builder
  BinRow() {
    Row({ space: 10 }) {
      ForEach(this.bins, (bin: CategorizationBin, index: number) => {
        this.BinCell(bin, index)
      }, (bin: CategorizationBin, index: number) => `bin_${index}_${bin.name}`)
    }
    .width('100%')
  }

  // ================ 槽位数据 (绘本感桶: 固定 quota 格, 已归位/虚线空槽) ================
  // 每桶槽位数 = 物品数 / 桶数 (校验器保证 2/2、2/2/2、3/3/3 分布)
  private getBinSlotQuota(): number {
    if (this.bins.length === 0) {
      return 0
    }
    return Math.floor(this.items.length / this.bins.length)
  }

  private buildSlotIndices(): number[] {
    const indices: number[] = []
    const quota = this.getBinSlotQuota()
    for (let p = 0; p < quota; p++) {
      indices.push(p)
    }
    return indices
  }

  private getSlotItemIndex(binIndex: number, slotIdx: number): number {
    const inBin = this.getItemsInBin(binIndex)
    if (slotIdx < 0 || slotIdx >= inBin.length) {
      return -1
    }
    return inBin[slotIdx]
  }

  private getSlotIconPath(binIndex: number, slotIdx: number): string {
    const itemIdx = this.getSlotItemIndex(binIndex, slotIdx)
    if (itemIdx >= 0 && itemIdx < this.itemIconPaths.length) {
      return this.itemIconPaths[itemIdx]
    }
    return ''
  }

  private getSlotEmoji(binIndex: number, slotIdx: number): string {
    const itemIdx = this.getSlotItemIndex(binIndex, slotIdx)
    if (itemIdx >= 0 && itemIdx < this.items.length) {
      return this.items[itemIdx].emoji
    }
    return ''
  }

  private getSlotName(binIndex: number, slotIdx: number): string {
    const itemIdx = this.getSlotItemIndex(binIndex, slotIdx)
    if (itemIdx >= 0 && itemIdx < this.items.length) {
      return this.items[itemIdx].name
    }
    return ''
  }

  private isSingleLetterName(name: string): boolean {
    if (name.length !== 1) {
      return false
    }
    const c = name.charAt(0)
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
  }

  @Builder
  BinCell(bin: CategorizationBin, index: number) {
    Column() {
      // 桶头: 类别字形 (或 emoji / 字母色块兜底) + 桶名 + 归位计数
      Column({ space: this.largeSize ? 3 : 2 }) {
        this.BinHeadArt(bin, index)
        Text(bin.name)
          .fontSize(this.largeSize ? 13 : 12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
        Text(`${this.countPlacedInBin(index)} 件已归位`)
          .fontSize(this.largeSize ? 11 : 10)
          .fontColor($r('app.color.text_tertiary'))
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      // 归位槽位行: 已归位显示 mini 图标 (点击撤回), 空槽虚线占位
      this.BinSlotsRow(index)
    }
    .layoutWeight(1)
    .height(this.largeSize ? 150 : 128)
    .padding({ left: 6, right: 6, top: this.largeSize ? 10 : 8, bottom: this.largeSize ? 10 : 8 })
    .borderRadius(this.largeSize ? 18 : 16)
    // 选中物品后 (armed) 桶切换实线加强边框, 提示"点这里放进去"
    .backgroundColor(withColorAlpha(this.getBinAccentColor(index), this.selectedItemIndex >= 0 ? '16' : '0C'))
    .border({
      width: 1.5,
      style: this.selectedItemIndex >= 0 ? BorderStyle.Solid : BorderStyle.Dashed,
      color: this.hoveredBinIndex === index || this.selectedItemIndex >= 0
        ? this.themePrimary
        : withColorAlpha(this.getBinAccentColor(index), '45')
    })
    .scale(this.hoveredBinIndex === index || this.selectedItemIndex >= 0
      ? { x: HOVERED_BIN_SCALE, y: HOVERED_BIN_SCALE }
      : { x: 1, y: 1 })
    .animation(SPRING_GENTLE)
    .onClick(() => this.handleBinClick(index))
    // 同步桶的窗口空间 bbox, 供拖拽命中检测使用
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateBinRect(index, newArea)
    })
  }

  // 桶头字形: 类别字形 (水里/天上 等分类概念) → emoji → 字母色块 (m/p/b/A/B/C 拼音英文主题)
  @Builder
  BinHeadArt(bin: CategorizationBin, index: number) {
    if (index < this.binGlyphPaths.length && this.binGlyphPaths[index] !== '') {
      Image($rawfile(this.binGlyphPaths[index]))
        .width(this.largeSize ? 40 : 34)
        .height(this.largeSize ? 40 : 34)
    } else if (bin.emoji !== '') {
      Text(bin.emoji)
        .fontSize(this.largeSize ? 32 : 28)
    } else if (this.isSingleLetterName(bin.name)) {
      Text(bin.name)
        .fontSize(this.largeSize ? 20 : 17)
        .fontWeight(FontWeight.Bold)
        .fontColor(BIN_LETTER_INK)
        .width(this.largeSize ? 40 : 34)
        .height(this.largeSize ? 40 : 34)
        .textAlign(TextAlign.Center)
        .backgroundColor(withColorAlpha(BIN_LETTER_BG, '26'))
        .borderRadius(this.largeSize ? 12 : 10)
    }
  }

  // 槽位行: 固定 quota 个格子 (与校验分布一致), 空槽即"还差几件"的可视进度
  @Builder
  BinSlotsRow(binIndex: number) {
    Row({ space: this.largeSize ? 5 : 4 }) {
      ForEach(this.buildSlotIndices(), (slotIdx: number) => {
        this.BinSlot(binIndex, slotIdx)
      }, (slotIdx: number) => `slot_${binIndex}_${slotIdx}`)
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
  }

  @Builder
  BinSlot(binIndex: number, slotIdx: number) {
    if (slotIdx < this.getItemsInBin(binIndex).length) {
      // 已归位槽: 白底 mini 贴纸, 点击撤回
      Column() {
        if (this.getSlotIconPath(binIndex, slotIdx) !== '') {
          Image($rawfile(this.getSlotIconPath(binIndex, slotIdx)))
            .width(this.largeSize ? 20 : 18)
            .height(this.largeSize ? 20 : 18)
        } else if (this.getSlotEmoji(binIndex, slotIdx) !== '') {
          Text(this.getSlotEmoji(binIndex, slotIdx))
            .fontSize(this.largeSize ? 13 : 12)
        } else {
          Text(this.getSlotName(binIndex, slotIdx))
            .fontSize(9)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
        }
      }
      .width(this.largeSize ? 30 : 26)
      .height(this.largeSize ? 30 : 26)
      .borderRadius(this.largeSize ? 10 : 9)
      .backgroundColor(ITEM_SURFACE)
      .border({
        width: 1,
        color: withColorAlpha(this.getBinAccentColor(binIndex), '55'),
        style: BorderStyle.Solid
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .scale(this.itemPressedIndex === this.getSlotItemIndex(binIndex, slotIdx)
        ? { x: 0.9, y: 0.9 } : { x: 1, y: 1 })
      .animation(SPRING_QUICK)
      .onTouch((e: TouchEvent) => {
        const itemIdx = this.getSlotItemIndex(binIndex, slotIdx)
        if (e.type === TouchType.Down) {
          this.itemPressedIndex = itemIdx
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.itemPressedIndex = -1
        }
      })
      // 只在未完成 + 非 isAnswered 时允许撤回
      .onClick(() => {
        if (!this.isCompleted && !this.isAnswered) {
          this.handleUnplace(this.getSlotItemIndex(binIndex, slotIdx))
        }
      })
    } else {
      // 空槽: 虚线占位 (等待落子)
      Column()
        .width(this.largeSize ? 30 : 26)
        .height(this.largeSize ? 30 : 26)
        .borderRadius(this.largeSize ? 10 : 9)
        .backgroundColor(withColorAlpha(this.getBinAccentColor(binIndex), '10'))
        .border({
          width: 1,
          color: withColorAlpha(this.getBinAccentColor(binIndex), '30'),
          style: BorderStyle.Dashed
        })
    }
  }

  @Builder
  ItemsLayer() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center, alignItems: ItemAlign.Center }) {
      ForEach(this.items, (item: CategorizationItem, index: number) => {
        if (this.placedItems[index] < 0) {
          this.ItemCard(item, index)
        }
      }, (item: CategorizationItem, index: number) => `item_${index}_${item.name}`)
    }
    .width('100%')
    .padding(this.largeSize ? 12 : 8)
    .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '08' : '05'))
    .borderRadius(12)
  }

  // 物品卡: 白底圆角贴纸 (固定浅色面, 双模式一致保证暖色图标对比度) + 图标/emoji + 名称
  // 降级链: 题库 SVG → emoji → 名称文字 (题库外自由题仍可玩)
  @Builder
  ItemCard(item: CategorizationItem, index: number) {
    Column({ space: this.largeSize ? 5 : 4 }) {
      if (index < this.itemIconPaths.length && this.itemIconPaths[index] !== '') {
        Image($rawfile(this.itemIconPaths[index]))
          .width(this.largeSize ? 52 : 44)
          .height(this.largeSize ? 52 : 44)
        Text(item.name)
          .fontSize(this.largeSize ? 12 : 11)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .maxLines(1)
      } else if (item.emoji !== '') {
        Text(item.emoji)
          .fontSize(this.largeSize ? 30 : 26)
        Text(item.name)
          .fontSize(this.largeSize ? 12 : 11)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .maxLines(1)
      } else {
        // 图标/emoji 双缺失: 名称文字即主体
        Text(item.name)
          .fontSize(this.largeSize ? 15 : 13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .maxLines(2)
      }
    }
    .width(this.largeSize ? 84 : 74)
    .height(this.largeSize ? 92 : 82)
    .borderRadius(this.largeSize ? 18 : 16)
    .backgroundColor(ITEM_SURFACE)
    .borderWidth(this.selectedItemIndex === index || this.shakingItemIndex === index
      || this.draggingItemIndex === index ? 2.5 : 1)
    .borderColor(this.shakingItemIndex === index
      ? ERROR_RED
      : (this.selectedItemIndex === index || this.draggingItemIndex === index
        ? this.themePrimary
        : withColorAlpha(this.themePrimary, '22')))
    .scale(this.draggingItemIndex === index
      ? { x: DRAGGING_ITEM_SCALE, y: DRAGGING_ITEM_SCALE }
      : (this.selectedItemIndex === index
        ? { x: 1.15, y: 1.15 }
        : (this.shakingItemIndex === index
          ? { x: 1.05, y: 1.05 }
          : (this.itemPressedIndex === index
            ? { x: 0.95, y: 0.95 }
            : {
              x: 1 + Math.sin((this.itemAnimPhase + index * ITEM_PHASE_OFFSET_PER_INDEX) % 360 * Math.PI / 180) * ITEM_BREATHING_AMPLITUDE,
              y: 1 + Math.sin((this.itemAnimPhase + index * ITEM_PHASE_OFFSET_PER_INDEX) % 360 * Math.PI / 180) * ITEM_BREATHING_AMPLITUDE
            }))))
    .shadow(this.draggingItemIndex === index
      ? { radius: DRAGGING_SHADOW_RADIUS, color: '#40000000', offsetY: 4 }
      : (this.selectedItemIndex === index
        ? { radius: 10, color: '#33000000', offsetY: 3 }
        : { radius: 4, color: '#1F000000', offsetY: 1 }))
    .translate(this.draggingItemIndex === index
      ? { x: this.dragOffsetX, y: this.dragOffsetY }
      : (this.isFirstPlay && index === 0
        && this.selectedItemIndex !== index
        && this.shakingItemIndex !== index
        && this.itemPressedIndex !== index
        ? { x: 0, y: -Math.abs(Math.sin(this.itemAnimPhase * Math.PI / 180)) * ITEM_TUTORIAL_BOB_AMPLITUDE }
        : { x: 0, y: 0 }))
    .animation(SPRING_QUICK)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .margin(6)
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.itemPressedIndex = index
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.itemPressedIndex = -1
      }
    })
    .onClick(() => this.handleItemClick(index))
    // 拖拽手势: 已回答 / 已完成时不出拖 (与 onClick 同条件)
    .priorityGesture(
      PanGesture({ direction: PanDirection.All, distance: DRAG_START_DISTANCE })
        .onActionStart((event: GestureEvent) => {
          if (this.isCompleted || this.isAnswered) {
            return
          }
          this.handleDragStart(index)
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.draggingItemIndex !== index) {
            return
          }
          const finger = event.fingerList && event.fingerList.length > 0 ? event.fingerList[0] : undefined
          if (finger === undefined) {
            return
          }
          // FingerInfo.globalX/globalY = 窗口坐标, 与 Area.globalPosition 同坐标空间
          this.handleDragUpdate(event.offsetX, event.offsetY,
            (finger as FingerInfo).globalX, (finger as FingerInfo).globalY)
        })
        .onActionEnd((_event: GestureEvent) => {
          if (this.draggingItemIndex !== index) {
            return
          }
          this.handleDragEnd(index)
        })
    )
  }

  @Builder
  StatsGrid() {
    Row({ space: 8 }) {
      this.StatCard($r('sys.symbol.clock'), '时间', this.formatBestTime(this.elapsedSeconds), false)
      this.StatCard($r('sys.symbol.checkmark'), '进度', `${this.correctCount}/${this.items.length}`, true)
    }
    .width('100%')
  }

  @Builder
  StatCard(icon: Resource, label: string, value: string, showWrongAttempts: boolean) {
    Column({ space: 4 }) {
      Row({ space: 4 }) {
        SymbolGlyph(icon)
          .fontSize(11)
          .fontColor([$r('app.color.text_tertiary')])
        Text(label)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')

      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ top: 2 })

      if (showWrongAttempts && this.wrongAttempts > 0) {
        Text(`失败 ${this.wrongAttempts} 次`)
          .fontSize(10)
          .fontColor(GIVEUP_ORANGE)
      } else {
        Text(' ')
          .fontSize(10)
      }
    }
    .layoutWeight(1)
    .padding(10)
    .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '10' : '08'))
    .borderRadius(10)
    .border({
      width: 1,
      color: withColorAlpha(this.themePrimary, this.isDarkMode ? '22' : '18'),
      style: BorderStyle.Solid
    })
  }

  @Builder
  ActionRow() {
    Row() {
      if (this.wrongHint !== '') {
        // 答错轻提示: 优先于引导/操作提示 (与 shake 同源触发, WRONG_HINT_MS 后自动消失)
        Text(this.wrongHint)
          .fontSize(11)
          .fontColor(ERROR_RED)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else if (this.isFirstPlay && this.selectedItemIndex < 0 && this.hasUnplacedItem()) {
        this.TutorialBubble()
      } else if (this.selectedItemIndex >= 0) {
        Text('选好一个物品 → 点击对应分类桶')
          .fontSize(11)
          .fontColor(this.themePrimary)
          .layoutWeight(1)
      } else if (this.hasUnplacedItem()) {
        Text('先点物品 → 再点桶')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .layoutWeight(1)
      } else {
        Blank().layoutWeight(1)
      }
      Text('放弃本局')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .padding(8)
        .onClick(() => this.handleGiveUp())
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  TutorialBubble() {
    // 引导气泡: 圆角矩形主体, 👆 emoji 自身作为"指向"提示
    Row({ space: 6 }) {
      Text('👆')
        .fontSize(14)
      Text('先点物品 → 再点桶')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(this.themePrimary)
    .borderRadius(12)
    .shadow({ radius: 6, color: '#33000000', offsetY: 2 })
    .layoutWeight(1)
    .transition(TransitionEffect.scale({ x: 0.8, y: 0.8 })
      .combine(TransitionEffect.OPACITY)
      .animation({ duration: 200, curve: Curve.EaseOut }))
  }

  @Builder
  ErrorPlaceholder() {
    Row({ space: 8 }) {
      Text('💡')
        .fontSize(20)
      Text(this.validationError)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .borderRadius(10)
    .backgroundColor(withColorAlpha(GIVEUP_ORANGE, '10'))
    .border({
      width: 1,
      color: withColorAlpha(GIVEUP_ORANGE, '30'),
      style: BorderStyle.Solid
    })
  }
}
