import {
  ImageAspectRatio,
  ImageGenerationOutputFormat,
  ImageGenerationQuality
} from '../../models/ImageGenerationModels'
import { getAppUiState } from '../../state/AppUiState'
import {
  ImageGenerationCapabilityResolver,
  ImageGenerationRouteCapabilities
} from '../../services/ImageGenerationCapabilityResolver'

@ComponentV2
export struct ImageGenerationSettingsSheet {
  @Param numberOfImages: number = 1
  @Param selectedAspectRatio: ImageAspectRatio = ImageAspectRatio.SQUARE
  @Param quality: ImageGenerationQuality = ImageGenerationQuality.AUTO
  @Param outputFormat: ImageGenerationOutputFormat = ImageGenerationOutputFormat.PNG
  @Param outputCompression: number = -1
  @Param promptOptimizer: boolean = false
  @Param seed: number = -1
  @Param styleType: string = ''
  @Param styleWeight: number = -1
  @Param capabilities: ImageGenerationRouteCapabilities = new ImageGenerationRouteCapabilities()
  @Event onNumberChange: (value: number) => void = (_value: number): void => {}
  @Event onAspectRatioChange: (value: ImageAspectRatio) => void = (_value: ImageAspectRatio): void => {}
  @Event onQualityChange: (value: ImageGenerationQuality) => void = (_value: ImageGenerationQuality): void => {}
  @Event onOutputFormatChange: (value: ImageGenerationOutputFormat) => void = (_value: ImageGenerationOutputFormat): void => {}
  @Event onOutputCompressionChange: (value: number) => void = (_value: number): void => {}
  @Event onPromptOptimizerChange: (value: boolean) => void = (_value: boolean): void => {}
  @Event onSeedChange: (value: number) => void = (_value: number): void => {}
  @Event onStyleTypeChange: (value: string) => void = (_value: string): void => {}
  @Event onStyleWeightChange: (value: number) => void = (_value: number): void => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }

  build() {
    Column({ space: 18 }) {
      this.CountSetting()
      this.AspectRatioSetting()
      if (this.capabilities.supportsQuality) {
        this.QualitySetting()
      }
      if (this.capabilities.supportsPromptOptimizer) {
        this.PromptOptimizerSetting()
      }
      if (this.capabilities.supportsSeed) {
        this.SeedSetting()
      }
      if (this.capabilities.supportsStyle) {
        this.StyleSetting()
      }
      if (this.shouldShowAdvancedSettings()) {
        this.AdvancedSettings()
      }
      Column().height(16)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 24 })
  }

  @Builder
  private CountSetting() {
    Column() {
      Text($r('app.string.image_generation_count'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 8 })

      // 步进按钮 + 可键入输入框组合: 用户既能 ± 一张, 也能直接输入 1-4
      // TextInput onChange 中做范围 clamp, 避免脏值进入 ViewModel
      Row() {
        this.DecrementButton()
        TextInput({ text: `${this.numberOfImages}` })
          .type(InputType.Number)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .textAlign(TextAlign.Center)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .maxLength(1)
          .layoutWeight(1)
          .onChange((value: string): void => {
            if (value === '') {
              this.onNumberChange(1)
              return
            }
            const parsed: number = Number.parseInt(value)
            if (!isNaN(parsed)) {
              this.onNumberChange(parsed)
            }
          })
        this.IncrementButton()
      }
      .width('100%')
      .height(48)
      .padding({ left: 8, right: 8 })
      .backgroundColor(this.themeSurface)
      .borderRadius(12)
    }
    .width('100%')
  }

  // 抽成辅助方法避免在 @Builder 调用中直接出现 < / > 操作符
  // (实测 es2abc 解析 builder 调用第三参为箭头函数时会把 `numberOfImages < 4` 中的 < 误识为泛型)
  private canDecrement(): boolean {
    return this.numberOfImages > 1
  }

  private canIncrement(): boolean {
    return this.numberOfImages < 4
  }

  private shouldShowCompressionSetting(): boolean {
    return this.capabilities.supportsOutputCompression && this.outputFormat !== ImageGenerationOutputFormat.PNG
  }

  private shouldShowAdvancedSettings(): boolean {
    return this.capabilities.supportsOutputFormat || this.shouldShowCompressionSetting()
  }

  private getAspectRatioIcon(value: ImageAspectRatio): Resource {
    if (value === ImageAspectRatio.LANDSCAPE) {
      return $r('sys.symbol.rectangle_ratio_16_to_9')
    }
    if (value === ImageAspectRatio.PORTRAIT) {
      return $r('sys.symbol.rectangle_ratio_9_to_16')
    }
    return $r('sys.symbol.rectangle_ratio_1_to_1')
  }

  private getAspectRatioTitle(value: ImageAspectRatio): Resource {
    if (value === ImageAspectRatio.LANDSCAPE) {
      return $r('app.string.image_generation_aspect_landscape_short')
    }
    if (value === ImageAspectRatio.PORTRAIT) {
      return $r('app.string.image_generation_aspect_portrait_short')
    }
    return $r('app.string.image_generation_aspect_square_short')
  }

  private getAspectRatioDetail(value: ImageAspectRatio): string {
    if (this.capabilities.supportsCustomSize) {
      return ImageGenerationCapabilityResolver.getOpenAIImageSize(value)
    }
    if (value === ImageAspectRatio.LANDSCAPE) {
      return '16:9'
    }
    if (value === ImageAspectRatio.PORTRAIT) {
      return '9:16'
    }
    return '1:1'
  }

  @Builder
  private AspectRatioSetting() {
    Column() {
      Text($r('app.string.image_generation_aspect_ratio'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 8 })

      Column() {
        this.AspectOption(ImageAspectRatio.SQUARE, $r('app.string.image_generation_aspect_square'))
        this.AspectOption(ImageAspectRatio.LANDSCAPE, $r('app.string.image_generation_aspect_landscape'))
        this.AspectOption(ImageAspectRatio.PORTRAIT, $r('app.string.image_generation_aspect_portrait'))
      }
      .width('100%')
      .padding({ left: 4, right: 4, top: 4, bottom: 4 })
      .backgroundColor(this.themeSurface)
      .borderRadius(12)
    }
    .width('100%')
  }

  @Builder
  private AspectOption(value: ImageAspectRatio, label: Resource) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row() {
        SymbolGlyph(this.getAspectRatioIcon(value))
          .fontSize(30)
          .fontColor([this.selectedAspectRatio === value ? this.themePrimary : $r('app.color.text_secondary')])
          .width(38)

        Column() {
          Text(this.getAspectRatioTitle(value))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
          Text(this.getAspectRatioDetail(value))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
        }
        .layoutWeight(1)
        .margin({ left: 10 })
        .alignItems(HorizontalAlign.Start)

        if (this.selectedAspectRatio === value) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(20)
            .fontColor([this.themePrimary])
            .width(24)
        } else {
          Blank()
            .width(24)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 10, right: 10 })
    }
    .height(50)
    .width('100%')
    .accessibilityText(label)
    .backgroundColor(this.selectedAspectRatio === value ? getAppUiState().themePrimaryLight : Color.Transparent)
    .borderRadius(10)
    .onClick(() => {
      this.onAspectRatioChange(value)
    })
  }

  @Builder
  private QualitySetting() {
    Column() {
      Text($r('app.string.image_generation_quality'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 8 })

      Row({ space: 8 }) {
        this.QualityChip(ImageGenerationQuality.AUTO, $r('app.string.image_generation_quality_auto'))
        this.QualityChip(ImageGenerationQuality.LOW, $r('app.string.image_generation_quality_low'))
        this.QualityChip(ImageGenerationQuality.MEDIUM, $r('app.string.image_generation_quality_medium'))
        this.QualityChip(ImageGenerationQuality.HIGH, $r('app.string.image_generation_quality_high'))
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private QualityChip(value: ImageGenerationQuality, label: Resource) {
    Button({ type: ButtonType.Capsule, stateEffect: false }) {
      Text(label)
        .fontSize(13)
        .fontColor(this.quality === value ? this.themePrimary : $r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(40)
    .layoutWeight(1)
    .backgroundColor(this.quality === value ? getAppUiState().themePrimaryLight : this.themeSurface)
    .border({
      width: this.quality === value ? 1 : 0.5,
      color: this.quality === value ? this.themePrimary : $r('app.color.divider')
    })
    .onClick(() => {
      this.onQualityChange(value)
    })
  }

  @Builder
  private OutputFormatSetting() {
    Column() {
      Text($r('app.string.image_generation_output_format'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 8 })

      Row({ space: 8 }) {
        this.OutputFormatChip(ImageGenerationOutputFormat.PNG, 'PNG')
        this.OutputFormatChip(ImageGenerationOutputFormat.JPEG, 'JPEG')
        this.OutputFormatChip(ImageGenerationOutputFormat.WEBP, 'WEBP')
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private OutputFormatChip(value: ImageGenerationOutputFormat, label: string) {
    Button({ type: ButtonType.Capsule, stateEffect: false }) {
      Text(label)
        .fontSize(13)
        .fontColor(this.outputFormat === value ? this.themePrimary : $r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(40)
    .layoutWeight(1)
    .backgroundColor(this.outputFormat === value ? getAppUiState().themePrimaryLight : this.themeSurface)
    .border({
      width: this.outputFormat === value ? 1 : 0.5,
      color: this.outputFormat === value ? this.themePrimary : $r('app.color.divider')
    })
    .onClick(() => {
      this.onOutputFormatChange(value)
    })
  }

  @Builder
  private AdvancedSettings() {
    Column({ space: 14 }) {
      Text($r('app.string.image_generation_advanced_settings'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      if (this.capabilities.supportsOutputFormat) {
        this.OutputFormatSetting()
      }
      if (this.shouldShowCompressionSetting()) {
        this.OutputCompressionSetting()
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(this.themeSurface)
    .borderRadius(12)
  }

  @Builder
  private OutputCompressionSetting() {
    Column() {
      Row() {
        Text($r('app.string.image_generation_output_compression'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
        Text(this.getCompressionLabel())
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .margin({ bottom: 8 })

      Row() {
        Slider({
          value: this.getCompressionSliderValue(),
          min: 0,
          max: 100,
          step: 5,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .blockColor(this.themePrimary)
          .selectedColor(this.themePrimary)
          .trackColor($r('app.color.divider'))
          .onChange((value: number): void => {
            this.onOutputCompressionChange(Math.round(value))
          })
        Button({ type: ButtonType.Capsule, stateEffect: false }) {
          Text($r('app.string.image_generation_output_compression_auto'))
            .fontSize(12)
            .fontColor(this.outputCompression < 0 ? this.themePrimary : $r('app.color.text_secondary'))
        }
        .height(32)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.outputCompression < 0 ? getAppUiState().themePrimaryLight : this.themeSurface)
        .onClick(() => {
          this.onOutputCompressionChange(-1)
        })
      }
      .width('100%')
      .height(44)
      .padding({ left: 8, right: 8 })
      .backgroundColor(this.themeSurface)
      .borderRadius(12)
    }
    .width('100%')
  }

  private getCompressionSliderValue(): number {
    if (this.outputCompression < 0) {
      return 100
    }
    return this.outputCompression
  }

  private getCompressionLabel(): ResourceStr {
    if (this.outputCompression < 0) {
      return $r('app.string.image_generation_output_compression_auto')
    }
    return `${this.outputCompression}`
  }

  @Builder
  private PromptOptimizerSetting() {
    Column() {
      Row() {
        Text($r('app.string.image_generation_prompt_optimizer'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.promptOptimizer })
          .onChange((isOn: boolean): void => {
            this.onPromptOptimizerChange(isOn)
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 12 })
      .backgroundColor(this.themeSurface)
      .borderRadius(12)
    }
    .width('100%')
  }

  @Builder
  private SeedSetting() {
    Column() {
      Text($r('app.string.image_generation_seed'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 8 })

      Row() {
        TextInput({ text: this.seed >= 0 ? `${this.seed}` : '', placeholder: $r('app.string.image_generation_seed_placeholder') })
          .type(InputType.Number)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_tertiary'))
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onChange((value: string): void => {
            if (value === '') {
              this.onSeedChange(-1)
              return
            }
            const parsed: number = Number.parseInt(value)
            if (!isNaN(parsed)) {
              this.onSeedChange(parsed)
            }
          })
        if (this.seed >= 0) {
          Button() {
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(18)
              .fontColor([$r('app.color.text_tertiary')])
          }
          .type(ButtonType.Circle)
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.onSeedChange(-1)
          })
        }
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 8 })
      .backgroundColor(this.themeSurface)
      .borderRadius(12)
    }
    .width('100%')
  }

  @Builder
  private StyleSetting() {
    Column({ space: 12 }) {
      Text($r('app.string.image_generation_style'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      TextInput({ text: this.styleType, placeholder: $r('app.string.image_generation_style_placeholder') })
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .width('100%')
        .height(48)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.themeSurface)
        .borderRadius(12)
        .onChange((value: string): void => {
          this.onStyleTypeChange(value)
        })

      if (this.styleType.trim() !== '') {
        Column() {
          Row() {
            Text($r('app.string.image_generation_style_weight'))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Text(`${this.styleWeight > 0 ? this.styleWeight : 50}`)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
              .textAlign(TextAlign.End)
          }
          .width('100%')
          .margin({ bottom: 4 })

          Slider({
            value: this.styleWeight > 0 ? this.styleWeight : 50,
            min: 1,
            max: 100,
            step: 5,
            style: SliderStyle.OutSet
          })
            .width('100%')
            .blockColor(this.themePrimary)
            .selectedColor(this.themePrimary)
            .trackColor($r('app.color.divider'))
            .onChange((value: number): void => {
              this.onStyleWeightChange(Math.round(value))
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(this.themeSurface)
        .borderRadius(12)
      }
    }
    .width('100%')
  }

  @Builder
  private DecrementButton() {
    Button() {
      SymbolGlyph($r('sys.symbol.minus_circle'))
        .fontSize(20)
        .fontColor([this.canDecrement() ? this.themePrimary : $r('app.color.text_tertiary')])
    }
    .type(ButtonType.Circle)
    .width(36)
    .height(36)
    .backgroundColor(Color.Transparent)
    .enabled(this.canDecrement())
    .onClick(() => {
      this.onNumberChange(this.numberOfImages - 1)
    })
  }

  @Builder
  private IncrementButton() {
    Button() {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(20)
        .fontColor([this.canIncrement() ? this.themePrimary : $r('app.color.text_tertiary')])
    }
    .type(ButtonType.Circle)
    .width(36)
    .height(36)
    .backgroundColor(Color.Transparent)
    .enabled(this.canIncrement())
    .onClick(() => {
      this.onNumberChange(this.numberOfImages + 1)
    })
  }
}
