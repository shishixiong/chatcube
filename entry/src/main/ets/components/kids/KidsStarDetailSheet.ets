import { BusinessError } from '@kit.BasicServicesKit'
import { StarEventRow, TodayStarSummary } from '../../models/StarEventModels'
import { getStarRewardService } from '../../services/StarRewardService'
import {
  buildTodayCategoryRows,
  buildTodayEventRows,
  KidsTodayCategoryRow,
  KidsTodayEventRow
} from '../../utils/KidsSubjectUtils'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  KIDS_BG,
  KIDS_SURFACE,
  KIDS_FG,
  KIDS_MUTED,
  KIDS_SUBTLE,
  KIDS_BORDER,
  KIDS_ACCENT,
  KIDS_STAR,
  KIDS_ON_GOLD,
  KIDS_ENGLISH_INK
} from './KidsBrandTokens'

/**
 * 儿童版今日星星明细 sheet（spec 2026-09-15 §4.6，对照原型 .sheet）。
 * 恒定暖色皮肤、无日历模式——不复用成人壳 TodayStarDetailSheet（避免波及成人侧）。
 * 数据自加载: getTodaySummary + getTodayEvents（与 hero「今日 +N」同源同口径）。
 */
@ComponentV2
export struct KidsStarDetailSheet {
  @Event onClose: () => void = () => {}
  @Local todayStars: number = 0
  @Local categoryRows: KidsTodayCategoryRow[] = []
  @Local eventRows: KidsTodayEventRow[] = []
  @Local loaded: boolean = false

  aboutToAppear(): void {
    this.loadData()
  }

  private loadData(): void {
    getStarRewardService().getTodaySummary().then((summary: TodayStarSummary): void => {
      this.todayStars = summary.total
    }).catch((error: Object): void => {
      console.error('KidsStarDetailSheet', `Failed to load today summary: ${(error as BusinessError).message ?? String(error)}`)
      this.todayStars = 0
    })
    getStarRewardService().getTodayEvents().then((events: StarEventRow[]): void => {
      this.categoryRows = buildTodayCategoryRows(events)
      this.eventRows = buildTodayEventRows(events)
      this.loaded = true
    }).catch((error: Object): void => {
      console.error('KidsStarDetailSheet', `Failed to load today events: ${(error as BusinessError).message ?? String(error)}`)
      this.categoryRows = []
      this.eventRows = []
      this.loaded = true
    })
  }

  build() {
    Column() {
      // ── 头部: 标题 + x 圆钮（44vp） ──
      Row() {
        Text('今日星星')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
          .layoutWeight(1)
        Column() {
          Image($rawfile('kids/close.svg')).width(16).height(16)
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#0F24211C')
        .onClick((): void => {
          this.onClose()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 16 }) {
          this.StarHero()

          if (this.loaded && this.eventRows.length === 0) {
            this.EmptyState()
          } else {
            if (this.categoryRows.length > 0) {
              this.CategorySection()
            }
            if (this.eventRows.length > 0) {
              this.EventSection()
            }
          }
        }
        .width('100%')
        .padding({ top: 16, bottom: 32 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 16 })
    .backgroundColor(KIDS_SURFACE)
  }

  @Builder
  StarHero() {
    // 金 14% 淡底圆角块 + 48vp 金星徽章 + N 31vp + 颗 · 今日获得
    Row({ space: 14 }) {
      Column() {
        Image($rawfile('kids/star.svg')).width(30).height(30)
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#24F5B301')

      Row({ space: 6 }) {
        Text(`${this.todayStars}`)
          .fontSize(31)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_ON_GOLD)
        Text('颗 · 今日获得')
          .fontSize(12.5)
          .fontColor(KIDS_MUTED)
          .margin({ bottom: 5 })
      }
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .padding(18)
    .borderRadius(18)
    .backgroundColor('#24F5B301')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  CategorySection() {
    Column({ space: 10 }) {
      Text(`${this.categoryRows.length} 类活动`)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(KIDS_SUBTLE)

      ForEach(this.categoryRows, (row: KidsTodayCategoryRow): void => {
        Row({ space: 10 }) {
          Column() {
            Image($rawfile(row.iconPath)).width(18).height(18)
          }
          .width(32)
          .height(32)
          .borderRadius(10)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(withColorAlpha(row.tint, '26'))

          Column({ space: 2 }) {
            Text(row.name)
              .fontSize(13.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(KIDS_FG)
            Text(row.detail)
              .fontSize(11)
              .fontColor(KIDS_SUBTLE)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text(`${row.stars}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_ON_GOLD)
          Image($rawfile('kids/star.svg')).width(15).height(15)
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .borderRadius(14)
        .backgroundColor(KIDS_BG)
        .alignItems(VerticalAlign.Center)
      }, (row: KidsTodayCategoryRow, index: number): string => `${row.name}_${index}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  EventSection() {
    Column({ space: 10 }) {
      Text(`今日明细 · 共 ${this.eventRows.length} 条`)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(KIDS_SUBTLE)

      ForEach(this.eventRows, (row: KidsTodayEventRow): void => {
        Row({ space: 10 }) {
          Text(row.timeLabel)
            .fontSize(11)
            .fontColor(KIDS_SUBTLE)
            .width(38)
          Text(row.description)
            .fontSize(12.5)
            .fontColor(KIDS_FG)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          // +N 星 药丸（英语绿 ink 淡底；0 星灰药丸）
          Text(row.stars > 0 ? `+${row.stars} 星` : '0 星')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(row.stars > 0 ? KIDS_ENGLISH_INK : KIDS_SUBTLE)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(999)
            .backgroundColor(row.stars > 0 ? '#2635A98A' : '#0F24211C')
        }
        .width('100%')
        .constraintSize({ minHeight: 44 })
        .padding({ left: 4, right: 4 })
        .alignItems(VerticalAlign.Center)
      }, (row: KidsTodayEventRow, index: number): string => `${row.timeLabel}_${index}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  EmptyState() {
    // 可达空态（spec §4.6）: 今天还没有获得星星
    Column({ space: 10 }) {
      Column() {
        Image($rawfile('kids/star.svg')).width(28).height(28)
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#14F5B301')

      Text('今天还没有获得星星，去学习吧')
        .fontSize(13)
        .fontColor(KIDS_MUTED)
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
    .justifyContent(FlexAlign.Center)
  }
}
