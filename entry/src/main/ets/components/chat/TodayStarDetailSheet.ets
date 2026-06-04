/**
 * TodayStarDetailSheet - 今日小明星详情面板
 *
 * 位置: ChatPage 的 bindSheet 内容
 * 作用: 展示分类汇总(数学/英语/华容道)+ 今日明细(每条事件一行)
 *
 * 数据源:
 * - 分类汇总: AppUiState.starTodaySummary (顶层状态, 来自 recordEvent 同步)
 * - 明细列表: 直接调 service.getTodayEvents() 拉, 在 aboutToAppear 与 starEarnedTick 变化时刷新
 */

import { getAppUiState, observeAppUiState } from '../../state/AppUiState'
import { AppStorageKeys } from '../../config/AppStorageKeys'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  StarActivityType,
  StarEventRow,
  StarTypeBucket,
  TodayStarSummary,
  createEmptyTodayStarSummary,
  STAR_ACTIVITY_TYPES,
  getActivityMeta,
  getBucketFromSummary
} from '../../models/StarEventModels'
import { getStarRewardService, StarRewardService } from '../../services/StarRewardService'

interface CategoryRow {
  emoji: string
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
        emoji: meta.emoji,
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
    Row() {
      Text(row.emoji)
        .fontSize(18)
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
      .margin({ left: 8 })
      .layoutWeight(1)
      Text(`${row.bucket.stars}`)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.themePrimary)
      Text('颗')
        .fontSize(11)
        .fontColor(this.themeTextSecondary)
        .margin({ left: 2 })
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor(this.chipBackgroundColor)
    .borderRadius(10)
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
      Text(row.starsText)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(row.isGranted ? this.themePrimary : this.themeTextTertiary)
        .backgroundColor(row.isGranted ? this.chipBackgroundColor : 'transparent')
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(6)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('⭐')
          .fontSize(20)
        Text('今日小明星')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.themeTextPrimary)
          .margin({ left: 8 })
        Blank()
        Text(`共 ${this.todaySummary.total} 颗`)
          .fontSize(13)
          .fontColor(this.themeTextSecondary)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 12 })

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
        Row() {
          Text('今天还没有记录, 完成一道题开始吧 ⭐')
            .fontSize(12)
            .fontColor(this.themeTextTertiary)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
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
  }
}
