// entry/src/main/ets/components/map/MapAtlasProvinceCard.ets
/**
 * MapAtlasProvinceCard / MapAtlasDistrictCard - 地图册资料卡（全国页 / 上海页共用）
 *
 * 只负责画：印章 + 名称 + 大区 / 第 N 个区 + 行政中心 / 地标 + 听一听 + 小星老师说。
 * 点选、朗读、提交都在 MapCard 里，卡片不知道「页」的存在。
 * 从 MapCard 原样抽出，行为零变化；上海页只是换一张同构的区卡。
 */

import { ChinaProvince } from '../../utils/ChinaMapData'
import { ShanghaiDistrict } from '../../utils/ShanghaiMapData'
import { buildDistrictEmptyHint, districtFact } from '../../utils/ShanghaiAtlasCopy'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { getMapAtlasPalette, MapAtlasPalette } from './MapAtlasTokens'

@ComponentV2
export struct MapAtlasProvinceCard {
  @Param info: ChinaProvince | null = null
  /** 地图数据还没加载完（全国页首帧） */
  @Param loading: boolean = false
  @Param noteText: string = ''
  @Param isSpeaking: boolean = false
  @Param listenLabel: string = '听一听'
  @Param largeSize: boolean = true
  @Param compactHeight: boolean = false
  @Param isDarkMode: boolean = false
  @Param isAnswered: boolean = false
  @Param hasCompleted: boolean = false
  @Param exploredCount: number = 0
  @Param sealScale: number = 1
  /** 只有全国页选中上海时展示「再看看 16 个区」入口；上海页传 false */
  @Param showDrilldownEntry: boolean = false
  @Param drilldownLabel: string = ''
  @Event onListen: () => void = () => {}
  @Event onEnterDrilldown: () => void = () => {}

  private get palette(): MapAtlasPalette {
    return getMapAtlasPalette(this.isDarkMode)
  }

  build() {
    Column({ space: this.largeSize ? 12 : 8 }) {
      if (this.loading) {
        this.LoadingRow()
      } else if (this.info !== null) {
        this.ProvinceFilled()
        if (this.showDrilldownEntry) {
          this.PeekDrilldown()
        }
        // 矮屏（≈6.5" 以下）让位给地图：设计稿 @media (max-height: 760px) 同款取舍
        if (this.largeSize && !this.compactHeight) {
          this.TeacherNote()
        }
      } else if (this.isAnswered) {
        this.CompletedSummary()
      } else {
        this.ProvinceEmpty()
      }
    }
    .width('100%')
    .padding({
      left: this.largeSize ? 15 : 12,
      right: this.largeSize ? 15 : 12,
      top: this.largeSize ? 14 : 11,
      bottom: this.largeSize ? 13 : 11
    })
    .borderRadius(this.largeSize ? 22 : 16)
    .backgroundColor(this.palette.surface)
    .border({ width: 1, color: this.palette.border })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  LoadingRow() {
    Row({ space: 10 }) {
      LoadingProgress()
        .width(24)
        .height(24)
        .color(this.palette.muted)
      Text('地图加载中…')
        .fontSize(13)
        .fontColor(this.palette.muted)
    }
    .width('100%')
    .height(this.largeSize ? 104 : 80)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ProvinceFilled() {
    Row({ space: this.largeSize ? 11 : 9 }) {
      this.Seal()

      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(this.info!.short)
            .fontSize(this.largeSize ? 28 : 22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.fg)
            .maxLines(1)
          Text(this.info!.region)
            .fontSize(10.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.accentInk)
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .backgroundColor(this.palette.surfaceAlt)
            .borderRadius(999)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.info!.name)
          .fontSize(11.5)
          .fontColor(this.palette.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.pin'))
            .fontSize(12)
            .fontColor([this.palette.chineseInk])
          Text('行政中心')
            .fontSize(12)
            .fontColor(this.palette.muted)
          Text(this.info!.capital)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.fg)
            .maxLines(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.ListenButton()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  Seal() {
    Column() {
      // 内圈细线 = 设计稿印章的 inset 环，abbr 大字号压在内圈里
      Column({ space: 1 }) {
        Text(this.info!.abbr)
          .fontSize(this.largeSize ? 25 : 21)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.chineseInk)
          .lineHeight(this.largeSize ? 27 : 23)
        Text('简称')
          .fontSize(9)
          .fontColor(this.palette.muted)
      }
      .padding({ left: 4, right: 4, top: 2, bottom: 2 })
      .border({ width: 3, color: this.palette.surface })
      .borderRadius(10)
    }
    .width(this.largeSize ? 54 : 46)
    .height(this.largeSize ? 58 : 50)
    .borderRadius(13)
    .backgroundColor(this.palette.surfaceAlt)
    .border({ width: 1.5, color: this.palette.sealBorder })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .rotate({ angle: -2 })
    .scale({ x: this.sealScale, y: this.sealScale })
    .accessibilityText(`简称${this.info!.abbr}`)
  }

  @Builder
  ListenButton() {
    Row({ space: 4 }) {
      SymbolGlyph(this.isSpeaking
        ? $r('sys.symbol.speaker_wave_2_fill')
        : $r('sys.symbol.speaker_wave_2'))
        .fontSize(15)
        .fontColor([this.palette.chineseInk])
      Text(this.listenLabel)
        .fontSize(11.5)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.fg)
        .maxLines(1)
    }
    .height(44)
    .padding({ left: 10, right: 10 })
    .borderRadius(13)
    .backgroundColor(this.isSpeaking
      ? withColorAlpha(this.palette.accent, '2E')
      : this.palette.surfaceAlt)
    .border({
      width: 1,
      color: this.isSpeaking ? withColorAlpha(this.palette.accent, '66') : this.palette.border
    })
    .accessibilityText(this.listenAccessibilityLabel())
    .onClick(() => {
      this.onListen()
    })
  }

  private listenAccessibilityLabel(): string {
    const info = this.info
    if (info === null) {
      return '听一听省份介绍'
    }
    return `听一听${info.name}的介绍`
  }

  @Builder
  TeacherNote() {
    Divider()
      .width('100%')
      .strokeWidth(1)
      .color(this.palette.noteLine)
    Row({ space: 7 }) {
      Text('小星老师说')
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.chineseInk)
        .letterSpacing(0.4)
      Text(this.noteText)
        .fontSize(12.5)
        .fontColor(this.palette.muted)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  /** 全国页选中上海时的下钻入口：一行「再看看 16 个区」，不抢主按钮 */
  @Builder
  PeekDrilldown() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.map'))
        .fontSize(14)
        .fontColor([this.palette.chineseInk])
      Text(this.drilldownLabel)
        .fontSize(12.5)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.fg)
        .layoutWeight(1)
        .maxLines(1)
      SymbolGlyph($r('sys.symbol.arrow_right'))
        .fontSize(14)
        .fontColor([this.palette.subtle])
    }
    .width('100%')
    .height(40)
    .padding({ left: 10, right: 10 })
    .borderRadius(12)
    .backgroundColor(this.palette.surfaceAlt)
    .border({ width: 1, color: this.palette.border })
    .alignItems(VerticalAlign.Center)
    .accessibilityText(this.drilldownLabel)
    .onClick(() => {
      this.onEnterDrilldown()
    })
  }

  @Builder
  ProvinceEmpty() {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.map'))
          .fontSize(24)
          .fontColor([this.palette.chineseInk])
      }
      .width(48)
      .height(48)
      .borderRadius(15)
      .backgroundColor(this.palette.surfaceAlt)
      .justifyContent(FlexAlign.Center)

      Column({ space: 5 }) {
        Text('选一个地方开始')
          .fontSize(this.largeSize ? 19 : 16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.fg)
        Text('点一点地图，看看它的名字、简称和行政中心。')
          .fontSize(12)
          .fontColor(this.palette.muted)
          .maxLines(2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  CompletedSummary() {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(24)
          .fontColor([this.palette.success])
      }
      .width(48)
      .height(48)
      .borderRadius(15)
      .backgroundColor(this.palette.surfaceAlt)
      .justifyContent(FlexAlign.Center)

      Column({ space: 4 }) {
        Text(this.hasCompleted ? '本节地图课已完成' : '这一课先到这里')
          .fontSize(this.largeSize ? 19 : 16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.fg)
        Text(this.exploredCount > 0
          ? `认识了 ${this.exploredCount} 个地方，点开地图还能回看。`
          : '点开地图还能回看。')
          .fontSize(12)
          .fontColor(this.palette.muted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

/**
 * 区资料卡：结构与省卡同构。
 * 印章写简称（「黄浦」比「黄」更好认）、标签换「第 N 个区」、行政中心那行换成地标。
 */
@ComponentV2
export struct MapAtlasDistrictCard {
  @Param district: ShanghaiDistrict | null = null
  @Param order: number = 0
  @Param noteText: string = ''
  @Param total: number = 16
  /** 「里面还有」：同区小地名，如「外滩 +2」；空串表示不显示这一行 */
  @Param placesText: string = ''
  @Param isSpeaking: boolean = false
  @Param listenLabel: string = '听一听'
  @Param largeSize: boolean = true
  @Param compactHeight: boolean = false
  @Param isDarkMode: boolean = false
  @Param sealScale: number = 1
  @Event onListen: () => void = () => {}

  private get palette(): MapAtlasPalette {
    return getMapAtlasPalette(this.isDarkMode)
  }

  private landmarkText(): string {
    const d = this.district
    if (d === null) {
      return '—'
    }
    const fact = districtFact(d.id)
    return fact === null ? '—' : fact.landmark
  }

  build() {
    Column({ space: this.largeSize ? 12 : 8 }) {
      if (this.district === null) {
        this.EmptyState()
      } else {
        Row({ space: this.largeSize ? 11 : 9 }) {
          this.Seal()

          Column({ space: 2 }) {
            Row({ space: 6 }) {
              Text(this.district!.name)
                .fontSize(this.largeSize ? 22 : 18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.fg)
                .maxLines(1)
              Text(this.order > 0 ? `第 ${this.order} 个区` : '区')
                .fontSize(10.5)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette.accentInk)
                .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                .backgroundColor(this.palette.surfaceAlt)
                .borderRadius(999)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.pin'))
                .fontSize(12)
                .fontColor([this.palette.chineseInk])
              Text('地标')
                .fontSize(12)
                .fontColor(this.palette.muted)
              Text(this.landmarkText())
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette.fg)
                .maxLines(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 3 })

            if (this.placesText !== '') {
              Row({ space: 4 }) {
                Text('里面还有')
                  .fontSize(12)
                  .fontColor(this.palette.muted)
                  .flexShrink(0)
                Text(this.placesText)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette.chineseInk)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .margin({ top: 1 })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          this.ListenButton()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.largeSize && !this.compactHeight) {
          this.TeacherNote()
        }
      }
    }
    .width('100%')
    .padding({
      left: this.largeSize ? 15 : 12,
      right: this.largeSize ? 15 : 12,
      top: this.largeSize ? 14 : 11,
      bottom: this.largeSize ? 13 : 11
    })
    .borderRadius(this.largeSize ? 22 : 16)
    .backgroundColor(this.palette.surface)
    .border({ width: 1, color: this.palette.border })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  EmptyState() {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.map'))
          .fontSize(24)
          .fontColor([this.palette.chineseInk])
      }
      .width(48)
      .height(48)
      .borderRadius(15)
      .backgroundColor(this.palette.surfaceAlt)
      .justifyContent(FlexAlign.Center)

      Column({ space: 5 }) {
        Text('选一个区开始')
          .fontSize(this.largeSize ? 19 : 16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.fg)
        Text(buildDistrictEmptyHint(this.total))
          .fontSize(12)
          .fontColor(this.palette.muted)
          .maxLines(2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  Seal() {
    Column() {
      Column({ space: 1 }) {
        Text(this.district!.short)
          .fontSize(this.largeSize ? 22 : 18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.chineseInk)
          .lineHeight(this.largeSize ? 25 : 21)
        Text('区')
          .fontSize(9)
          .fontColor(this.palette.muted)
      }
      .padding({ left: 3, right: 3, top: 2, bottom: 2 })
      .border({ width: 3, color: this.palette.surface })
      .borderRadius(10)
    }
    .width(this.largeSize ? 54 : 46)
    .height(this.largeSize ? 58 : 50)
    .borderRadius(13)
    .backgroundColor(this.palette.surfaceAlt)
    .border({ width: 1.5, color: this.palette.sealBorder })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .rotate({ angle: -2 })
    .scale({ x: this.sealScale, y: this.sealScale })
    .accessibilityText(`简称${this.district!.short}`)
  }

  @Builder
  ListenButton() {
    Row({ space: 4 }) {
      SymbolGlyph(this.isSpeaking
        ? $r('sys.symbol.speaker_wave_2_fill')
        : $r('sys.symbol.speaker_wave_2'))
        .fontSize(15)
        .fontColor([this.palette.chineseInk])
      Text(this.listenLabel)
        .fontSize(11.5)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.fg)
        .maxLines(1)
    }
    .height(44)
    .padding({ left: 10, right: 10 })
    .borderRadius(13)
    .backgroundColor(this.isSpeaking
      ? withColorAlpha(this.palette.accent, '2E')
      : this.palette.surfaceAlt)
    .border({
      width: 1,
      color: this.isSpeaking ? withColorAlpha(this.palette.accent, '66') : this.palette.border
    })
    .accessibilityText(this.listenAccessibilityLabel())
    .onClick(() => {
      this.onListen()
    })
  }

  private listenAccessibilityLabel(): string {
    const d = this.district
    if (d === null) {
      return '听一听区的介绍'
    }
    return `听一听${d.name}的介绍`
  }

  @Builder
  TeacherNote() {
    Divider()
      .width('100%')
      .strokeWidth(1)
      .color(this.palette.noteLine)
    Row({ space: 7 }) {
      Text('小星老师说')
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.chineseInk)
        .letterSpacing(0.4)
      Text(this.noteText)
        .fontSize(12.5)
        .fontColor(this.palette.muted)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}
