// entry/src/main/ets/components/map/MapZoomCluster.ets
/**
 * MapZoomCluster - 横向缩放簇（缩小 / 放大 / 全图）
 *
 * 设计稿 atlas-foot 里的分段控件：一个圆角胶囊装两个符号键 + 分隔线 + 「全图」。
 * 地图册（MapCard）把它放在卡片页脚；出题 body 由舞台自己浮在地图右上角。
 * 尺寸写死成常量供舞台定位叠层（避免百分比定位）。
 */

import { MapAtlasPalette, getMapAtlasPalette } from './MapAtlasTokens'

export const MAP_ZOOM_CLUSTER_WIDTH: number = 150
export const MAP_ZOOM_CLUSTER_HEIGHT: number = 44

@ComponentV2
export struct MapZoomCluster {
  @Param canZoomIn: boolean = true
  @Param canZoomOut: boolean = false
  @Param isDarkMode: boolean = false
  @Event onZoomIn: () => void = () => {}
  @Event onZoomOut: () => void = () => {}
  @Event onReset: () => void = () => {}

  private get palette(): MapAtlasPalette {
    return getMapAtlasPalette(this.isDarkMode)
  }

  build() {
    Row() {
      this.ZoomButton($r('sys.symbol.minus'), '缩小地图', this.canZoomOut, (): void => this.onZoomOut())
      this.ZoomButton($r('sys.symbol.plus'), '放大地图', this.canZoomIn, (): void => this.onZoomIn())
      Divider()
        .vertical(true)
        .height(22)
        .strokeWidth(1)
        .color(this.palette.border)
      this.ResetButton()
    }
    .width(MAP_ZOOM_CLUSTER_WIDTH)
    .height(MAP_ZOOM_CLUSTER_HEIGHT)
    .clip(true)
    .backgroundColor(this.palette.surfaceAlt)
    .border({ width: 1, color: this.palette.border })
    .borderRadius(13)
  }

  @Builder
  ZoomButton(icon: Resource, label: string, enabled: boolean, action: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(17)
        .fontColor([enabled ? this.palette.fg : this.palette.subtle])
    }
    .width(44)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .opacity(enabled ? 1 : 0.45)
    .accessibilityText(label)
    .onClick(() => {
      if (enabled) {
        action()
      }
    })
  }

  @Builder
  ResetButton() {
    Row({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
        .fontSize(14)
        .fontColor([this.palette.accentInk])
      Text('全图')
        .fontSize(11.5)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.fg)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .accessibilityText('查看全国地图')
    .onClick(() => {
      this.onReset()
    })
  }
}
