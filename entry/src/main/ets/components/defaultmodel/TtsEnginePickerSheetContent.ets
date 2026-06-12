import { TtsEngineAvailability } from '../../models/TtsEngineProfile'
import { getAppUiState } from '../../state/AppUiState'

@ComponentV2
export struct TtsEnginePickerSheetContent {
  @Param currentEngineId: string = ''
  @Param engines: TtsEngineAvailability[] = []

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  @Event onSelectEngine: (id: string) => void = () => {}

  build() {
    Column() {
      // Header
      Row() {
        Text($r('app.string.tts_engine_select_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .height(56)
      .width('100%')
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      if (this.engines.length === 0) {
        Text($r('app.string.tts_engine_empty'))
          .fontColor($r('app.color.text_tertiary'))
          .padding(16)
      }

      List() {
        ForEach(this.engines, (item: TtsEngineAvailability) => {
          ListItem() {
            this.EngineRow(item)
          }
        })
      }
      .listDirection(Axis.Vertical)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private EngineRow(item: TtsEngineAvailability) {
    Row() {
      SymbolGlyph($r(`sys.symbol.${item.profile.iconSymbol}`))
        .fontSize(24)
        .fontColor([item.isEnabled ? this.themePrimary : $r('app.color.text_tertiary')])
        .width(40)

      Column() {
        Row() {
          Text(item.profile.displayName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(item.isEnabled
              ? $r('app.color.text_primary')
              : $r('app.color.text_tertiary'))

          if (!item.isEnabled) {
            Text($r('app.string.tts_engine_unavailable_tag'))
              .fontSize(11)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.text_tertiary'))
              .borderRadius(4)
              .padding({ left: 6, right: 6 })
              .margin({ left: 8 })
          }
        }

        Text(item.isEnabled
          ? item.profile.description
          : item.unavailableReason)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (item.profile.id === this.currentEngineId) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([this.themePrimary])
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(item.profile.id === this.currentEngineId
      ? getAppUiState().themeSurface
      : Color.Transparent)
    .enabled(item.isEnabled)
    .onClick(() => {
      if (item.isEnabled) {
        this.onSelectEngine(item.profile.id)
      }
    })
  }
}
