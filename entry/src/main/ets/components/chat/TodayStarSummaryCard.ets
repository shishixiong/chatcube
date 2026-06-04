/**
 * TodayStarSummaryCard - 今日小明星小卡片
 *
 * 位置: ChatPage 顶部, 消息列表上方
 * 作用: 一眼展示今日星星总数 + 三个分类(数学/英语/华容道)小芯片
 * 交互: 点击展开 bindSheet 看到完整明细
 *
 * v2 视觉升级 (2026-06-04):
 * - SymbolGlyph 替换文本 emoji ⭐, 与项目内卡片族保持一致
 * - 32×32 圆角 icon well 突出"今日小明星"主题 (UsageStatsPage MetricCard 模式)
 * - 总数从 18vp 升到 22vp Bold, 视觉权重提升
 * - 分类 chip 改用 28×28 icon well + 16vp SymbolGlyph, 与 hero 呼应
 * - 200ms scale pulse + 600ms 数字 roll-up: 答对题的"活起来"瞬间
 * - 今日第一颗星触发 🎉 1.5s 庆祝 (匹配 NumberPuzzleCard WinBanner 风格)
 *
 * 数据来源: AppUiState.starTodaySummary (JSON 字符串, 来自 StarRewardService 预热)
 * 响应式: 不传 prop, 直接读 AppUiState 的 @Trace 字段, 自动响应
 */

import { getAppUiState, observeAppUiState } from '../../state/AppUiState'
import { AppStorageKeys } from '../../config/AppStorageKeys'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  StarTypeBucket,
  TodayStarSummary,
  createEmptyTodayStarSummary,
  STAR_ACTIVITY_TYPES,
  StarActivityType,
  STAR_SUCCESS_GREEN,
  STAR_CELEBRATION_GOLD,
  getActivityMeta,
  getActivitySymbol,
  getBucketFromSummary,
  getTodayStarHeaderSymbol
} from '../../models/StarEventModels'

interface CategoryMetric {
  symbolResource: Resource
  label: string
  bucket: StarTypeBucket
  activityType: StarActivityType
}

const PULSE_DURATION_MS: number = 200
const ROLLUP_DURATION_MS: number = 600
const ROLLUP_TICK_MS: number = 16
const FIRST_STAR_CELEBRATION_MS: number = 1500

@ComponentV2
export struct TodayStarSummaryCard {
  @Event onOpenDetail: () => void = (): void => {}
  @Local pulseActive: boolean = false
  @Local displayedTotal: number = 0
  @Local showFirstStarCelebration: boolean = false
  private pulseTimerId: number = -1
  private rollTimerId: number = -1
  private celebrationTimerId: number = -1
  private unsubscribe: (() => void) | null = null

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }

  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  private get themeTextPrimary(): string {
    return getAppUiState().themeTextPrimary
  }

  private get themeTextSecondary(): string {
    return getAppUiState().themeTextSecondary
  }

  private get themeTextTertiary(): string {
    return getAppUiState().themeTextTertiary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get todaySummary(): TodayStarSummary {
    const json = getAppUiState().starTodaySummary
    if (json === '') {
      return createEmptyTodayStarSummary()
    }
    try {
      return JSON.parse(json) as TodayStarSummary
    } catch (_e) {
      return createEmptyTodayStarSummary()
    }
  }

  private get chipBackgroundColor(): string {
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12')
  }

  aboutToAppear(): void {
    this.displayedTotal = this.todaySummary.total
    this.unsubscribe = observeAppUiState(AppStorageKeys.STAR_EARNED_TICK, (): void => {
      this.triggerGrantAnimation()
    })
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== null) {
      this.unsubscribe()
      this.unsubscribe = null
    }
    if (this.pulseTimerId !== -1) {
      clearTimeout(this.pulseTimerId)
      this.pulseTimerId = -1
    }
    if (this.rollTimerId !== -1) {
      clearInterval(this.rollTimerId)
      this.rollTimerId = -1
    }
    if (this.celebrationTimerId !== -1) {
      clearTimeout(this.celebrationTimerId)
      this.celebrationTimerId = -1
    }
  }

  private triggerGrantAnimation(): void {
    const target: number = this.todaySummary.total

    // 200ms scale pulse
    this.pulseActive = true
    if (this.pulseTimerId !== -1) {
      clearTimeout(this.pulseTimerId)
    }
    this.pulseTimerId = setTimeout((): void => {
      this.pulseActive = false
      this.pulseTimerId = -1
    }, PULSE_DURATION_MS)

    // 600ms 数字 roll-up (仅正向)
    if (target > this.displayedTotal) {
      if (this.rollTimerId !== -1) {
        clearInterval(this.rollTimerId)
      }
      const start: number = this.displayedTotal
      const delta: number = target - start
      const startTime: number = Date.now()
      this.rollTimerId = setInterval((): void => {
        const elapsed: number = Date.now() - startTime
        if (elapsed >= ROLLUP_DURATION_MS) {
          this.displayedTotal = target
          clearInterval(this.rollTimerId)
          this.rollTimerId = -1
          return
        }
        const progress: number = elapsed / ROLLUP_DURATION_MS
        this.displayedTotal = Math.round(start + delta * progress)
      }, ROLLUP_TICK_MS)
    }

    // 今日第一颗星: 一次性 🎉 庆祝
    if (this.displayedTotal === 0 && target > 0) {
      this.showFirstStarCelebration = true
      if (this.celebrationTimerId !== -1) {
        clearTimeout(this.celebrationTimerId)
      }
      this.celebrationTimerId = setTimeout((): void => {
        this.showFirstStarCelebration = false
        this.celebrationTimerId = -1
      }, FIRST_STAR_CELEBRATION_MS)
    }
  }

  @Builder
  private CategoryMetric(metric: CategoryMetric) {
    Row({ space: 6 }) {
      Row() {
        SymbolGlyph(metric.symbolResource)
          .fontSize(14)
          .fontColor([this.themePrimary])
      }
      .width(24)
      .height(24)
      .borderRadius(8)
      .backgroundColor(this.themePrimaryLight)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Text(`${metric.bucket.stars}`)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.themePrimary)
      Text(metric.label)
        .fontSize(11)
        .fontColor(this.themeTextTertiary)
    }
    .padding({ left: 6, right: 10, top: 4, bottom: 4 })
    .backgroundColor(this.chipBackgroundColor)
    .borderRadius(10)
  }

  private buildCategoryMetrics(): CategoryMetric[] {
    const summary: TodayStarSummary = this.todaySummary
    const metrics: CategoryMetric[] = []
    for (let i = 0; i < STAR_ACTIVITY_TYPES.length; i++) {
      const type: StarActivityType = STAR_ACTIVITY_TYPES[i]
      const meta = getActivityMeta(type)
      const bucket: StarTypeBucket = getBucketFromSummary(summary, type)
      metrics.push({
        symbolResource: getActivitySymbol(type),
        label: meta.shortLabel,
        bucket: bucket,
        activityType: type
      })
    }
    return metrics
  }

  build() {
    Column({ space: 8 }) {
      // 首次授星庆祝 banner (1.5s 后自动消失)
      if (this.showFirstStarCelebration) {
        Row({ space: 6 }) {
          Text('🎉')
            .fontSize(15)
          Text('今日第一颗星！')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(STAR_CELEBRATION_GOLD)
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 2, bottom: 2 })
        .alignItems(VerticalAlign.Center)
      }

      Column({ space: 8 }) {
        // Row 1: icon well + 标题 + Blank + 总数 + chevron
        Row() {
          Row() {
            SymbolGlyph(getTodayStarHeaderSymbol())
              .fontSize(16)
              .fontColor([this.themePrimary])
          }
          .width(32)
          .height(32)
          .borderRadius(16)
          .backgroundColor(this.chipBackgroundColor)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)

          Text('今日小明星')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.themeTextPrimary)
            .margin({ left: 8 })

          Blank()

          if (this.displayedTotal > 0) {
            Text(`${this.displayedTotal}`)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(STAR_SUCCESS_GREEN)
            Text('颗')
              .fontSize(12)
              .fontColor(this.themeTextSecondary)
              .margin({ left: 2, right: 4 })
          }

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([this.themeTextTertiary])
        }
        .width('100%')

        // Row 2: 空状态 OR 三个分类 metric
        if (this.displayedTotal > 0) {
          Row({ space: 8 }) {
            ForEach(this.buildCategoryMetrics(), (metric: CategoryMetric): void => {
              this.CategoryMetric(metric)
            }, (metric: CategoryMetric): string => metric.activityType)
          }
          .width('100%')
        } else {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(14)
              .fontColor([this.themeTextTertiary])
            Text('今天还没有星星, 完成一道题开始吧')
              .fontSize(12)
              .fontColor(this.themeTextTertiary)
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.themeAiBubble)
      .borderRadius(14)
      .border({ width: 1, color: $r('app.color.divider') })
      .scale(this.pulseActive ? { x: 1.04, y: 1.04 } : { x: 1.0, y: 1.0 })
      .animation({ duration: PULSE_DURATION_MS, curve: Curve.EaseOut })
      .onClick((): void => {
        this.onOpenDetail()
      })
    }
    .width('100%')
  }
}
