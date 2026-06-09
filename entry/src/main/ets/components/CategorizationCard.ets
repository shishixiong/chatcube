/**
 * CategorizationCard - 分类小管家互动卡片
 *
 * 设计语言对齐 NumberPuzzleCard / MathQuizCard 卡片族:
 * - 圆形徽章标题, 主题色调暖色琥珀
 * - 物品圆球 + 桶虚线轮廓, 拖拽或"先点物品再点桶"两种交互
 * - 双卡片统计 (时间 / 进度)
 * - 完成横幅 (绿色) / 放弃药丸 (橙色)
 * - 严格的输入校验: 桶数 2-3、物品数 4/6/9、bin_index 合法、每桶 ≥2 物品
 *
 * 公共 API: toolCall / isAnswered / answeredPayload / largeSize / onAnswer
 * 导出: CategorizationResult / CategorizationBin / CategorizationItem
 */

import { ToolCall } from '../models/ChatModels'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { getPreferencesService, PreferenceKeys } from '../services/PreferencesService'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { curves } from '@kit.ArkUI'

const DOMAIN = 0x0002
const TAG = 'CategorizationCard'
const SUCCESS_GREEN: string = '#22C55E'
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

interface NormalizedData {
  ok: boolean
  error: string
  bins: CategorizationBin[]
  items: CategorizationItem[]
  difficulty: number
  theme: string
  instruction: string
}

// ================ 组件 ================
// TODO (v1.1): 当前仅实现点击交互 (点击物品选中 → 点击桶归位)。
// 拖拽交互 (PanGesture + 命中检测) 计划在 v1.1 增量添加，
// 参见 spec §7.1 和 docs/superpowers/plans/2026-06-06-categorization-helper.md。

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

  // 非响应式
  private timerId: number = -1
  private shakeTimerId: number = -1
  private itemAnimTimerId: number = -1
  private startTime: number = 0

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
    this.placedItems = this.createPlacedArray(this.items.length)
    // 最佳成绩两个分支都需要: 未回答时给新纪录检测用, 已回答时给在线视图展示「最佳 X:Y」
    this.loadBestScores(this.difficulty)
    if (this.isAnswered) {
      this.parseAnsweredPayload()
      // 在线视图: 视为已看过引导 (不会显示气泡)
      this.isFirstPlay = false
    } else {
      this.shuffleItems()
      this.startTimer()
      this.startItemAnim()
      this.loadTutorialState()
    }
  }

  aboutToDisappear(): void {
    this.stopTimer()
    this.stopItemAnim()
    if (this.shakeTimerId >= 0) {
      clearTimeout(this.shakeTimerId)
      this.shakeTimerId = -1
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
    // 6° / 50ms = 120°/s, |sin| 半周期 1.5s, 驱动首物品 bobbing + 所有物品呼吸 scale
    this.itemAnimTimerId = setInterval(() => {
      this.itemAnimPhase = (this.itemAnimPhase + 6) % 360
    }, 50)
  }

  private stopItemAnim(): void {
    if (this.itemAnimTimerId >= 0) {
      clearInterval(this.itemAnimTimerId)
      this.itemAnimTimerId = -1
    }
  }

  // 用户首次点击物品后, 关闭引导并持久化 (item anim 继续跑, 只用于呼吸)
  private async dismissTutorial(): Promise<void> {
    if (!this.isFirstPlay) {
      return
    }
    this.isFirstPlay = false
    try {
      await getPreferencesService().setCategorizationTutorialSeen(true)
    } catch (_e) {
      hilog.warn(DOMAIN, TAG, 'failed to persist tutorial seen flag')
    }
  }

  // 异步读最佳成绩。已回答/未回答两个分支都需要, 让在线视图也能展示「最佳 X:Y · 0 错」
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
    } catch (_e) {
      this.bestTimeSeconds = -1
      this.bestPerfectSeconds = -1
      // 加载失败也要解除守卫, 否则 saveBestScoresIfImproved 永远不写
      this.bestScoresLoaded = true
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

  // ================ 校验 / 解析 ================
  private validateAndNormalize(): NormalizedData {
    const fail = (msg: string): NormalizedData => {
      return {
        ok: false,
        error: msg,
        bins: [],
        items: [],
        difficulty: 1,
        theme: '',
        instruction: ''
      }
    }

    let parsed: Record<string, Object>
    try {
      parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
    } catch (_e) {
      return fail('题目格式错误，请提示小星老师再出一题吧')
    }

    const theme = ((parsed['theme'] as string) ?? '').trim()
    if (theme === '') {
      return fail('主题为空，请提示小星老师再出一题吧')
    }
    const instruction = ((parsed['instruction'] as string) ?? '').trim()

    const binsRaw = parsed['bins'] as Array<Record<string, Object>> | undefined
    if (!binsRaw || binsRaw.length < 2 || binsRaw.length > 3) {
      return fail('分类桶数量不对（需要 2 或 3 个）')
    }
    const bins: CategorizationBin[] = []
    for (let i = 0; i < binsRaw.length; i++) {
      const raw = binsRaw[i]
      const name = ((raw['name'] as string) ?? '').trim()
      if (name === '') {
        return fail(`第 ${i + 1} 个分类桶缺少名字`)
      }
      bins.push({
        name: name,
        emoji: (raw['emoji'] as string) ?? ''
      })
    }

    const itemsRaw = parsed['items'] as Array<Record<string, Object>> | undefined
    if (!itemsRaw || itemsRaw.length === 0) {
      return fail('物品列表为空')
    }

    let difficulty = (parsed['difficulty'] as number) ?? 0
    if (difficulty !== 1 && difficulty !== 2 && difficulty !== 3) {
      if (itemsRaw.length === 4) {
        difficulty = 1
      } else if (itemsRaw.length === 6) {
        difficulty = 2
      } else if (itemsRaw.length === 9) {
        difficulty = 3
      } else {
        return fail(`物品数量 ${itemsRaw.length} 与难度不匹配（应为 4/6/9）`)
      }
    }
    const expectedCount = difficulty === 1 ? 4 : (difficulty === 2 ? 6 : 9)
    if (itemsRaw.length !== expectedCount) {
      return fail(`物品数量 ${itemsRaw.length} 与难度 ${difficulty}（期望 ${expectedCount}）不一致`)
    }

    const binCounts: number[] = []
    for (let i = 0; i < bins.length; i++) {
      binCounts.push(0)
    }
    const items: CategorizationItem[] = []
    for (let i = 0; i < itemsRaw.length; i++) {
      const raw = itemsRaw[i]
      const name = ((raw['name'] as string) ?? '').trim()
      const emoji = (raw['emoji'] as string) ?? ''
      const binIndex = raw['bin_index'] as number
      if (name === '') {
        return fail(`第 ${i + 1} 个物品缺少名字`)
      }
      if (typeof binIndex !== 'number' || Math.floor(binIndex) !== binIndex
        || binIndex < 0 || binIndex >= bins.length) {
        return fail(`第 ${i + 1} 个物品的 bin_index 不合法`)
      }
      binCounts[binIndex] = binCounts[binIndex] + 1
      items.push({ name: name, emoji: emoji, bin_index: binIndex })
    }
    for (let i = 0; i < binCounts.length; i++) {
      if (binCounts[i] < 2) {
        return fail(`第 ${i + 1} 个桶只有 ${binCounts[i]} 件物品（至少 2 件）`)
      }
    }

    return {
      ok: true,
      error: '',
      bins,
      items,
      difficulty,
      theme,
      instruction
    }
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
    }, 400)
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
    this.submitResult(false)
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
    Column({ space: this.largeSize ? 20 : 10 }) {
      if (this.validationError !== '') {
        this.ErrorPlaceholder()
      } else {
        this.HeaderRow()
        if (this.hasWon) {
          this.WinBanner()
        }
        if (this.instruction !== '') {
          this.InstructionRow()
        }
        this.BinRow()
        this.ItemsLayer()
        this.StatsGrid()
        if (!this.isCompleted) {
          this.ActionRow()
        }
      }
    }
    .width('100%')
    .padding(this.largeSize ? 24 : 14)
    .backgroundColor(this.largeSize ? Color.Transparent : this.themeAiBubble)
    .borderRadius(this.largeSize ? 0 : 14)
    .border(this.largeSize
      ? { width: 0, color: Color.Transparent, style: BorderStyle.Solid }
      : { width: 1, color: $r('app.color.divider'), style: BorderStyle.Solid })
    .alignItems(HorizontalAlign.Start)
    .onTouch((e: TouchEvent) => e.stopPropagation())
  }

  // ================ 子区块 ================
  @Builder
  HeaderRow() {
    Row() {
      Column() {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(15)
          .fontColor([this.themePrimary])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(withColorAlpha(this.themePrimary, '18'))
      .justifyContent(FlexAlign.Center)

      Column() {
        Text('分类小管家')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(`${this.theme} · ${this.getDifficultyLabel()} · ${this.items.length}件 ${this.bins.length}桶`)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })
      .layoutWeight(1)

      if (this.isCompleted) {
        Text(this.hasWon ? '已完成' : '已放弃')
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor(this.hasWon ? $r('app.color.status_success') : GIVEUP_ORANGE)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  WinBanner() {
    Row({ space: 10 }) {
      Text('🎉')
        .fontSize(24)
      Column() {
        Text('分类完成！')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.status_success'))
        Text(`${this.correctCount}/${this.items.length} · ${this.formatBestTime(this.elapsedSeconds)} · 失败 ${this.wrongAttempts} 次`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 2 })
        if (this.bestPerfectSeconds >= 0) {
          Text(`最佳 ${this.formatBestTime(this.bestPerfectSeconds)} · 0 错`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (this.isNewBest) {
        Text('新纪录')
          .fontSize(10)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.status_success'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(withColorAlpha(SUCCESS_GREEN, this.isDarkMode ? '18' : '0C'))
    .borderRadius(12)
    .border({
      width: 1,
      color: withColorAlpha(SUCCESS_GREEN, this.isDarkMode ? '38' : '28'),
      style: BorderStyle.Solid
    })
  }

  @Builder
  InstructionRow() {
    Row() {
      Text(this.instruction)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
  }

  @Builder
  BinRow() {
    Row({ space: 10 }) {
      ForEach(this.bins, (bin: CategorizationBin, index: number) => {
        this.BinCell(bin, index)
      }, (bin: CategorizationBin, index: number) => `bin_${index}_${bin.name}`)
    }
    .width('100%')
  }

  @Builder
  BinCell(bin: CategorizationBin, index: number) {
    Column() {
      // 桶口高光带 (暗示容器开口)
      Row()
        .width('100%')
        .height(this.largeSize ? 10 : 8)
        .linearGradient({
          angle: 90,
          colors: [
            [Color.Transparent, 0.0],
            [withColorAlpha(this.getBinAccentColor(index), '55'), 0.5],
            [Color.Transparent, 1.0]
          ]
        })

      // 内容
      Column({ space: this.largeSize ? 4 : 3 }) {
        if (bin.emoji !== '') {
          Text(bin.emoji)
            .fontSize(this.largeSize ? 32 : 28)
        }
        Text(bin.name)
          .fontSize(this.largeSize ? 13 : 12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(`${this.countPlacedInBin(index)} 件`)
          .fontSize(this.largeSize ? 11 : 10)
          .fontColor($r('app.color.text_tertiary'))
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      // 桶底暗影 (暗示容器底部)
      Row()
        .width('100%')
        .height(this.largeSize ? 6 : 5)
        .linearGradient({
          angle: 90,
          colors: [
            [Color.Transparent, 0.0],
            [withColorAlpha(this.getBinAccentColor(index), '32'), 0.5],
            [Color.Transparent, 1.0]
          ]
        })
    }
    .layoutWeight(1)
    .height(this.largeSize ? 120 : 96)
    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
    .borderRadius(this.largeSize ? 16 : 14)
    .linearGradient(this.hoveredBinIndex === index
      ? {
        angle: 180,
        colors: [
          [withColorAlpha(this.themePrimary, '32'), 0.0],
          [withColorAlpha(this.themePrimary, '18'), 1.0]
        ]
      }
      : {
        angle: 180,
        colors: [
          [withColorAlpha(this.getBinAccentColor(index), '22'), 0.0],
          [withColorAlpha(this.getBinAccentColor(index), '10'), 1.0]
        ]
      })
    .border({
      width: 0.5,
      style: BorderStyle.Solid,
      color: this.hoveredBinIndex === index
        ? this.themePrimary
        : withColorAlpha(this.getBinAccentColor(index), '38')
    })
    .scale(this.selectedItemIndex >= 0
      ? { x: 1.05, y: 1.05 }
      : { x: 1, y: 1 })
    .animation(SPRING_GENTLE)
    .onClick(() => this.handleBinClick(index))
  }

  @Builder
  ItemsLayer() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center, alignItems: ItemAlign.Center }) {
      ForEach(this.items, (item: CategorizationItem, index: number) => {
        if (this.placedItems[index] < 0) {
          this.ItemCircle(item, index)
        }
      }, (item: CategorizationItem, index: number) => `item_${index}_${item.name}`)
    }
    .width('100%')
    .padding(this.largeSize ? 12 : 8)
    .backgroundColor(withColorAlpha(this.themePrimary, this.isDarkMode ? '08' : '05'))
    .borderRadius(12)
  }

  @Builder
  ItemCircle(item: CategorizationItem, index: number) {
    Column() {
      if (item.emoji !== '') {
        Text(item.emoji)
          .fontSize(this.largeSize ? 30 : 24)
      } else {
        Text(item.name)
          .fontSize(this.largeSize ? 13 : 11)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .maxLines(2)
      }
    }
    .width(this.largeSize ? 80 : 68)
    .height(this.largeSize ? 80 : 68)
    .borderRadius(this.largeSize ? 40 : 34)
    .linearGradient(this.selectedItemIndex === index
      ? {
        angle: 180,
        colors: [
          [withColorAlpha(this.themePrimary, '32'), 0.0],
          [withColorAlpha(this.themePrimary, '18'), 1.0]
        ]
      }
      : {
        angle: 180,
        colors: [
          [withColorAlpha(this.themePrimary, '14'), 0.0],
          [withColorAlpha(this.themePrimary, '04'), 1.0]
        ]
      })
    .borderWidth(this.selectedItemIndex === index || this.shakingItemIndex === index ? 3 : 1)
    .borderColor(this.shakingItemIndex === index
      ? ERROR_RED
      : (this.selectedItemIndex === index ? this.themePrimary : withColorAlpha(this.themePrimary, '30')))
    .scale(this.selectedItemIndex === index
      ? { x: 1.15, y: 1.15 }
      : (this.shakingItemIndex === index
        ? { x: 1.05, y: 1.05 }
        : (this.itemPressedIndex === index
          ? { x: 0.95, y: 0.95 }
          : {
            x: 1 + Math.sin((this.itemAnimPhase + index * 30) % 360 * Math.PI / 180) * 0.03,
            y: 1 + Math.sin((this.itemAnimPhase + index * 30) % 360 * Math.PI / 180) * 0.03
          })))
    .shadow(this.selectedItemIndex === index
      ? { radius: 10, color: '#33000000', offsetY: 3 }
      : { radius: 4, color: '#1F000000', offsetY: 1 })
    .translate(this.isFirstPlay && index === 0
      && this.selectedItemIndex !== index
      && this.shakingItemIndex !== index
      && this.itemPressedIndex !== index
      ? { x: 0, y: -Math.abs(Math.sin(this.itemAnimPhase * Math.PI / 180)) * 1.5 }
      : { x: 0, y: 0 })
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
  }

  @Builder
  StatsGrid() {
    Row({ space: 8 }) {
      this.StatCard($r('sys.symbol.clock'), '时间', this.formatBestTime(this.elapsedSeconds))
      this.StatCard($r('sys.symbol.checkmark'), '进度', `${this.correctCount}/${this.items.length}`)
    }
    .width('100%')
  }

  @Builder
  StatCard(icon: Resource, label: string, value: string) {
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

      if (this.wrongAttempts > 0 && label === '进度') {
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
      if (this.isFirstPlay && this.selectedItemIndex < 0 && this.hasUnplacedItem()) {
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
