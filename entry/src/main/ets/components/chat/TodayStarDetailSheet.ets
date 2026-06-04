/**
 * TodayStarDetailSheet - 今日小明星详情面板
 *
 * 位置: ChatPage 的 bindSheet 内容
 * 作用: 展示分类汇总(数学/英语/华容道)+ 今日明细(每条事件一行)
 *
 * v2 视觉升级 (2026-06-04):
 * - 顶部 hero block: 40×40 圆角 icon well (STAR_SUCCESS_GREEN bg) + 32vp Bold 总数
 * - 三个分类块改用 UsageMetricCard 比例 (28×28 icon well + 22vp Bold 数字)
 * - granted pill 用 STAR_SUCCESS_GREEN 背景 + 白字
 * - empty state 用 48vp SymbolGlyph 插画 + 16vp 标题 + 13vp 描述
 * - 容器加 visualEffect(buildPointLightBorderEffect()), 沿用 UsageStatsPage 灯光效果
 *
 * 数据源:
 * - 分类汇总: AppUiState.starTodaySummary (顶层状态, 来自 recordEvent 同步)
 * - 明细列表: 直接调 service.getTodayEvents() 拉, 在 aboutToAppear 与 starEarnedTick 变化时刷新
 */

import { getAppUiState, observeAppUiState } from '../../state/AppUiState'
import { AppStorageKeys } from '../../config/AppStorageKeys'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { buildPointLightBorderEffect } from '../../utils/HdsVisualEffectUtil'
import {
  StarActivityType,
  StarEventRow,
  StarTypeBucket,
  TodayStarSummary,
  createEmptyTodayStarSummary,
  STAR_ACTIVITY_TYPES,
  STAR_SUCCESS_GREEN,
  getActivityMeta,
  getActivitySymbol,
  getBucketFromSummary,
  getTodayStarHeaderSymbol
} from '../../models/StarEventModels'
import { getStarRewardService, StarRewardService } from '../../services/StarRewardService'

interface CategoryRow {
  symbolResource: Resource
  label: string
  unit: string
  bucket: StarTypeBucket
  activityType: StarActivityType
}

interface DetailRowData {
  event: StarEventRow
  timeText: string
  description: string
  starsText: string
  isGranted: boolean
}

@ComponentV2
export struct TodayStarDetailSheet {
  @Local events: StarEventRow[] = []
  @Local hasLoaded: boolean = false
  private service: StarRewardService = getStarRewardService()
  private unsubscribe: (() => void) | null = null

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }

  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }

  private get themeSurface(): string {
    return getAppUiState().themeSurface
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

  aboutToAppear(): void {
    void this.refresh()
    this.unsubscribe = observeAppUiState(AppStorageKeys.STAR_EARNED_TICK, (): void => {
      void this.refresh()
    })
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== null) {
      this.unsubscribe()
      this.unsubscribe = null
    }
  }

  private async refresh(): Promise<void> {
    try {
      const events = await this.service.getTodayEvents()
      this.events = events
      this.hasLoaded = true
    } catch (error) {
      console.error('TodayStarDetailSheet', `refresh failed: ${JSON.stringify(error)}`)
      this.events = []
      this.hasLoaded = true
    }
  }

  private get chipBackgroundColor(): string {
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12')
  }

  private formatTime(ms: number): string {
    const date = new Date(ms)
    const h = date.getHours().toString().padStart(2, '0')
    const m = date.getMinutes().toString().padStart(2, '0')
    return `${h}:${m}`
  }

  private describeEvent(event: StarEventRow): string {
    const type = event.activityType as StarActivityType
    if (type !== 'math_quiz' && type !== 'english_quiz' && type !== 'number_puzzle') {
      return '未知活动'
    }
    const meta = getActivityMeta(type)
    if (event.stars > 0) {
      return meta.grantedHint
    }
    return `${meta.longLabel}${type === 'number_puzzle' ? '放弃' : '答错'}`
  }

  private buildDetailRows(): DetailRowData[] {
    const rows: DetailRowData[] = []
    for (let i = 0; i < this.events.length; i++) {
      const event = this.events[i]
      const isGranted = event.stars > 0
      rows.push({
        event: event,
        timeText: this.formatTime(event.createdAt),
        description: this.describeEvent(event),
        starsText: isGranted ? `+${event.stars} ⭐` : '尝试',
        isGranted: isGranted
      })
    }
    return rows
  }

  private buildCategoryRows(): CategoryRow[] {
    const summary = this.todaySummary
    const rows: CategoryRow[] = []
    for (let i = 0; i < STAR_ACTIVITY_TYPES.length; i++) {
      const type = STAR_ACTIVITY_TYPES[i]
      const meta = getActivityMeta(type)
      const bucket: StarTypeBucket = getBucketFromSummary(summary, type)
      rows.push({
        symbolResource: getActivitySymbol(type),
        label: meta.longLabel,
        unit: meta.unit,
        bucket: bucket,
        activityType: type
      })
    }
    return rows
  }

  @Builder
  private CategoryRow(row: CategoryRow) {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph(row.symbolResource)
          .fontSize(16)
          .fontColor([this.themePrimary])
      }
      .width(28)
      .height(28)
      .borderRadius(9)
      .backgroundColor(this.themePrimaryLight)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Column({ space: 2 }) {
        Text(row.label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themeTextPrimary)
        Text(`${row.bucket.count} ${row.unit}`)
          .fontSize(11)
          .fontColor(this.themeTextTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(`${row.bucket.stars}`)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(STAR_SUCCESS_GREEN)
      Text('颗')
        .fontSize(12)
        .fontColor(this.themeTextSecondary)
        .margin({ left: 2 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.chipBackgroundColor)
    .borderRadius(12)
  }

  @Builder
  private DetailRow(row: DetailRowData) {
    Row() {
      Text(row.timeText)
        .fontSize(11)
        .fontColor(this.themeTextTertiary)
        .width(42)
      Text(row.description)
        .fontSize(13)
        .fontColor(this.themeTextPrimary)
        .layoutWeight(1)
        .margin({ left: 8 })
      if (row.isGranted) {
        Text(row.starsText)
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(STAR_SUCCESS_GREEN)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
      } else {
        Text(row.starsText)
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themeTextTertiary)
          .backgroundColor(withColorAlpha(this.themeTextTertiary, '14'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
      }
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  build() {
    Column() {
      // Hero block: 40×40 圆角 icon well + 32vp Bold 总数
      Row() {
        Row() {
          SymbolGlyph(getTodayStarHeaderSymbol())
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(40)
        .height(40)
        .borderRadius(12)
        .backgroundColor(STAR_SUCCESS_GREEN)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)

        Column({ space: 2 }) {
          Row({ space: 4 }) {
            Text(`${this.todaySummary.total}`)
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.themeTextPrimary)
            Text('颗')
              .fontSize(14)
              .fontColor(this.themeTextSecondary)
              .margin({ top: 12 })
          }
          .alignItems(VerticalAlign.Bottom)

          Text('今日获得')
            .fontSize(13)
            .fontColor(this.themeTextSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 24, bottom: 20 })

      // 分类汇总
      Column({ space: 8 }) {
        ForEach(this.buildCategoryRows(), (row: CategoryRow): void => {
          this.CategoryRow(row)
        }, (row: CategoryRow): string => row.activityType)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 12 })

      // 分割线
      Row()
        .width('100%')
        .height(1)
        .backgroundColor($r('app.color.divider'))

      // 明细标题
      Row() {
        Text('今日明细')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themeTextPrimary)
        Blank()
        Text(`共 ${this.events.length} 条`)
          .fontSize(11)
          .fontColor(this.themeTextTertiary)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      // 明细列表
      if (!this.hasLoaded) {
        Row() {
          Text('加载中...')
            .fontSize(12)
            .fontColor(this.themeTextTertiary)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      } else if (this.events.length === 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(48)
            .fontColor([this.themeTextTertiary])
          Text('今天还没有记录')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themeTextSecondary)
          Text('完成一道题或华容道开始吧')
            .fontSize(13)
            .fontColor(this.themeTextTertiary)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 16, right: 16, top: 48, bottom: 48 })
      } else {
        Column() {
          ForEach(this.buildDetailRows(), (row: DetailRowData): void => {
            this.DetailRow(row)
          }, (row: DetailRowData): string => `${row.event.id}`)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }

      Blank()
    }
    .width('100%')
    .height('60%')
    .backgroundColor(this.themeSurface)
    .borderRadius({ topLeft: 28, topRight: 28 })
    .visualEffect(buildPointLightBorderEffect())
  }
}
