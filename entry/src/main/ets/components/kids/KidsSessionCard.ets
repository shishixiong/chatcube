import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import {
  KIDS_SURFACE,
  KIDS_FG,
  KIDS_SUBTLE,
  KIDS_BORDER,
  KIDS_STAR,
  KIDS_ON_GOLD,
  KIDS_ACCENT
} from './KidsBrandTokens'

/**
 * 儿童主屏会话卡片（竖版，2 列网格用）。
 *
 * 对照 docs/kids-home-prototype.html 的 `.sess`：
 * 上排 = 分类色图标块 + 金色星星徽章（>0 才显示），
 * 中排 = 会话标题（13.5fp 加粗），底排 = 相对时间。
 * 恒定暖色令牌（KidsBrandTokens），不随深色模式切换。
 */
@ComponentV2
export struct KidsSessionCard {
  @Param sessionTitle: string = ''
  @Param starCount: number = 0
  @Param timeLabel: string = ''
  @Param themeColor: string = KIDS_ACCENT
  @Event onTap: () => void = () => {}

  build() {
    Column() {
      // 上排: 图标块 + 星星徽章
      Row() {
        Text('⭐')
          .fontSize(20)
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .borderRadius(13)
          .backgroundColor(withColorAlpha(this.themeColor, '29'))

        Blank()

        if (this.starCount > 0) {
          Text(`⭐ ${this.starCount}`)
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_ON_GOLD)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(999)
            .backgroundColor(withColorAlpha(KIDS_STAR, '38'))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Blank()

      // 中排: 会话标题
      Text(this.sessionTitle.length > 0 ? this.sessionTitle : '和小星老师的学习')
        .fontSize(13.5)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_FG)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      // 底排: 相对时间
      Text(this.timeLabel)
        .fontSize(11)
        .fontColor(KIDS_SUBTLE)
        .margin({ top: 4 })
        .width('100%')
    }
    .width('100%')
    .height(118)
    .padding(14)
    .borderRadius(18)
    .backgroundColor(KIDS_SURFACE)
    .border({ width: 1, color: KIDS_BORDER })
    .alignItems(HorizontalAlign.Start)
    .accessibilityText(`和小星老师的会话「${this.sessionTitle}」，获得 ${this.starCount} 颗星，${this.timeLabel}`)
    .onClick((): void => {
      this.onTap()
    })
  }
}
