/**
 * 动画片气泡卡片：待答态是「▶ 播放」横幅，已答态是一行观看摘要。
 * 真正的播放由 CartoonPlayerCover 负责（Index 根级全屏覆盖层）。
 */

import { ToolCall } from '../../models/ChatModels'
import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { formatDurationSeconds } from '../../utils/CartoonQuotaMath'
import { summarizeCartoonPayload } from '../../utils/CartoonCardUtils'

@ComponentV2
export struct CartoonCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Event onOpen: (toolCall: ToolCall) => void = () => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  private titleText(): string {
    try {
      const parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      const series = parsed['series_title'] as string
      const season = parsed['season'] as number
      const episode = parsed['episode'] as number
      const title = parsed['title'] as string
      let label = ''
      if (season !== undefined && season !== null && season > 0 &&
        episode !== undefined && episode !== null && episode > 0) {
        label = `S${this.pad2(season)}E${this.pad2(episode)}`
      } else if (episode !== undefined && episode !== null && episode > 0) {
        label = `E${this.pad2(episode)}`
      }
      if (series !== undefined && series !== null && series !== '') {
        return label !== '' ? `${series} · ${label}` : series
      }
      if (title !== undefined && title !== null && title !== '') {
        return title
      }
    } catch (_error) {
      // fall through
    }
    return '动画片'
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`
  }

  private durationText(): string {
    try {
      const parsed = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      const durationMs = parsed['duration_ms'] as number
      if (durationMs !== undefined && durationMs !== null && durationMs > 0) {
        return formatDurationSeconds(Math.round(durationMs / 1000))
      }
    } catch (_error) {
      // fall through
    }
    return '00:00'
  }

  private summaryText(): string {
    return summarizeCartoonPayload(this.answeredPayload)
  }

  build() {
    if (this.isAnswered) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.play_circle'))
          .fontSize(13)
          .fontColor([this.themePrimary])
        Text(`${this.titleText()} · ${this.summaryText()}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: 2, bottom: 2 })
    } else {
      Row() {
        Column() {
          SymbolGlyph($r('sys.symbol.play_circle'))
            .fontSize(17)
            .fontColor([this.themePrimary])
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .backgroundColor(withColorAlpha(this.themePrimary, '18'))
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)

        Column({ space: 2 }) {
          Text(this.titleText())
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.durationText()} · 点一下就能看`)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 8 })
        .layoutWeight(1)

        Text('播放')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themePrimary)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor(this.themeAiBubble)
      .borderRadius(12)
      .border({ width: 1, color: $r('app.color.divider') })
      .margin({ bottom: 6 })
      .onClick(() => {
        this.onOpen(this.toolCall)
      })
    }
  }
}
