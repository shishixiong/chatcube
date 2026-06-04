/**
 * TodayStarSummaryCard - 今日小明星小卡片
 *
 * 位置: ChatPage 顶部, 消息列表上方
 * 作用: 一眼展示今日星星总数 + 三个分类(数学/英语/华容道)小芯片
 * 交互: 点击展开 bindSheet 看到完整明细
 *
 * 数据来源: AppUiState.starTodaySummary (JSON 字符串, 来自 StarRewardService 预热)
 * 响应式: 不传 prop, 直接读 AppUiState 的 @Trace 字段, 自动响应
 */

import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  StarTypeBucket,
  TodayStarSummary,
  createEmptyTodayStarSummary,
  STAR_ACTIVITY_TYPES,
  StarActivityType,
  getActivityMeta,
  getBucketFromSummary
} from '../../models/StarEventModels'

interface CategoryChip {
  emoji: string
  label: string
  bucket: StarTypeBucket
  activityType: StarActivityType
}

@ComponentV2
export struct TodayStarSummaryCard {
  @Event onOpenDetail: () => void = (): void => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
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

  @Builder
  private CategoryChip(chip: CategoryChip) {
    Row({ space: 4 }) {
      Text(chip.emoji)
        .fontSize(13)
      Text(`${chip.bucket.stars}`)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.themePrimary)
      Text(chip.label)
        .fontSize(11)
        .fontColor(this.themeTextTertiary)
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(this.chipBackgroundColor)
    .borderRadius(8)
  }

  private buildCategoryChips(): CategoryChip[] {
    const summary = this.todaySummary
    const chips: CategoryChip[] = []
    for (let i = 0; i < STAR_ACTIVITY_TYPES.length; i++) {
      const type = STAR_ACTIVITY_TYPES[i]
      const meta = getActivityMeta(type)
      const bucket: StarTypeBucket = getBucketFromSummary(summary, type)
      chips.push({
        emoji: meta.emoji,
        label: meta.shortLabel,
        bucket: bucket,
        activityType: type
      })
    }
    return chips
  }

  build() {
    Row() {
      Column({ space: 6 }) {
        // Row 1: ⭐ 标题 + 总数 + 查看链接
        Row() {
          Text('⭐')
            .fontSize(18)
          Text('今日小明星')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.themeTextPrimary)
            .margin({ left: 6 })
          Blank()
          if (this.todaySummary.total > 0) {
            Text(`${this.todaySummary.total}`)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.themePrimary)
            Text('颗')
              .fontSize(12)
              .fontColor(this.themeTextSecondary)
              .margin({ right: 6 })
          }
          Text('查看')
            .fontSize(12)
            .fontColor(this.themePrimary)
          Text('→')
            .fontSize(12)
            .fontColor(this.themePrimary)
        }
        .width('100%')

        // Row 2: 空状态 OR 三个分类小芯片
        if (this.todaySummary.total > 0) {
          Row({ space: 8 }) {
            ForEach(this.buildCategoryChips(), (chip: CategoryChip): void => {
              this.CategoryChip(chip)
            }, (chip: CategoryChip): string => chip.activityType)
          }
          .width('100%')
        } else {
          Row() {
            Text('今天还没有星星哦，开始学习吧')
              .fontSize(12)
              .fontColor(this.themeTextTertiary)
            Text(' ⭐')
              .fontSize(12)
          }
          .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.themeAiBubble)
    .borderRadius(14)
    .border({ width: 1, color: $r('app.color.divider') })
    .onClick(() => {
      this.onOpenDetail()
    })
  }
}
