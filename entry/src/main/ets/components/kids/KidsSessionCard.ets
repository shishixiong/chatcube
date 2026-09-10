import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { getAppUiState } from '../../state/AppUiState'

/**
 * 儿童主屏图形化会话卡片: 主题色头像块 + 星星徽章 + 相对时间。
 * 刻意不渲染文字标题/消息预览（spec §4.2）; title 仅用于无障碍朗读。
 */
@ComponentV2
export struct KidsSessionCard {
  @Param sessionTitle: string = ''
  @Param starCount: number = 0
  @Param timeLabel: string = ''
  @Param themeColor: string = '#FF9F43'
  @Event onTap: () => void = () => {}

  private isDark(): boolean {
    return getAppUiState().isDarkMode
  }

  build() {
    Row({ space: 14 }) {
      Text('⭐')
        .fontSize(32)
        .width(60)
        .height(60)
        .textAlign(TextAlign.Center)
        .borderRadius(18)
        .backgroundColor(withColorAlpha(this.themeColor, this.isDark() ? '33' : '1A'))

      Column({ space: 6 }) {
        if (this.starCount > 0) {
          Text(`⭐ ${this.starCount}`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .borderRadius(10)
            .backgroundColor(withColorAlpha(this.themeColor, this.isDark() ? '2E' : '14'))
        }

        Text(this.timeLabel)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .borderRadius(20)
    .backgroundColor(getAppUiState().themeAiBubble)
    .border({ width: 1, color: $r('app.color.divider') })
    .accessibilityText(`和小星老师的会话，获得 ${this.starCount} 颗星，${this.timeLabel}`)
    .onClick((): void => {
      this.onTap()
    })
  }
}
