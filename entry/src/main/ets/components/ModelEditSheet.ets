/**
 * 模型编辑半模态组件
 * 单页滚动布局：核心信息 → 能力标签
 *
 * 历史背景:这里曾经有一个"高级参数"折叠区,放 temperature / topP / presencePenalty / frequencyPenalty
 * 等采样参数。2026/05 重构后,所有采样参数都搬到助手设置(Assistant.xxxEnabled / xxx),模型级整段废弃。
 */
import { ModelInfo, InputMode, OutputMode, ModelInfoExtendedJson } from '../models/ChatModels'
import { LengthMetrics } from '@kit.ArkUI'
import { getAppUiState } from '../state/AppUiState'
import { lookupModelAbilities, ModelAbility, ModelModality } from '../services/registry/ModelAbilityRegistry'
import { getEffectiveCapabilities, getEffectiveOutputMode } from '../utils/ModelCapabilityDeriver'

@ComponentV2
export struct ModelEditSheet {
  @Param model: ModelInfo = new ModelInfo('', '')
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  @Local tempName: string = ''
  // 能力开关状态（用于触发 UI 刷新）
  @Local capSupportsTools: boolean = false
  @Local capSupportsReasoning: boolean = false
  @Local capSupportsWebSearch: boolean = false
  @Local capSupportsVision: boolean = false
  @Local capSupportsStreaming: boolean = false
  @Local capOutputImage: boolean = false
  @Local capSupportsMusicGeneration: boolean = false
  @Local capSupportsVideoGeneration: boolean = false
  // 派生覆盖跟踪
  // userTouched: 本次进入 sheet 后用户是否动过任何开关
  // originalUserModified: 进入 sheet 时 model.capabilitiesUserModified 的快照,用于保护"不改动直接保存"的场景
  @Local userTouched: boolean = false
  @Local originalUserModified: boolean = false
  // 回调函数
  @Event onSave: (draft: ModelInfoExtendedJson) => Promise<void> = async (_draft: ModelInfoExtendedJson): Promise<void> => {
  }
  @Event onCancel: () => void = () => {
  }

  aboutToAppear(): void {
    this.syncDraftFromModel()
  }

  private syncDraftFromModel(): void {
    this.tempName = this.model.name
    // 读 effective 能力:override=false 时 UI 显示派生值,override=true 时显示持久化值
    const effective = getEffectiveCapabilities(this.model)
    this.capSupportsTools = effective.supportsTools
    this.capSupportsReasoning = effective.supportsReasoning
    this.capSupportsWebSearch = effective.supportsWebSearch
    this.capSupportsVision = effective.supportsVision
    this.capSupportsStreaming = effective.supportsStreaming
    this.capOutputImage = getEffectiveOutputMode(this.model) === OutputMode.IMAGE
    this.capSupportsMusicGeneration = effective.supportsMusicGeneration
    this.capSupportsVideoGeneration = effective.supportsVideoGeneration
    this.originalUserModified = this.model.capabilitiesUserModified
    this.userTouched = false
  }

  private resetCapabilities(): void {
    const result = lookupModelAbilities(this.model.id)
    this.capSupportsTools = result.abilities.includes(ModelAbility.TOOL)
    this.capSupportsReasoning = result.abilities.includes(ModelAbility.REASONING)
    this.capSupportsVision = result.inputModalities.includes(ModelModality.IMAGE)
    this.capOutputImage = result.abilities.includes(ModelAbility.IMAGE_GENERATION) ||
      result.outputModalities.includes(ModelModality.IMAGE)
    this.capSupportsMusicGeneration = result.abilities.includes(ModelAbility.MUSIC_GENERATION)
    this.capSupportsVideoGeneration = result.abilities.includes(ModelAbility.VIDEO_GENERATION)
    this.capSupportsWebSearch = false
    this.capSupportsStreaming = true
    // 强制清除覆盖标志:用户主动选择回到派生轨道
    this.userTouched = false
    this.originalUserModified = false
  }

  private buildDraft(): ModelInfoExtendedJson {
    // outputMode 优先级: music > video > image > text, 与 ModelCapabilityDeriver.deriveModelOutputMode 保持一致。
    let resolvedOutputMode: OutputMode = OutputMode.TEXT
    if (this.capSupportsMusicGeneration) {
      resolvedOutputMode = OutputMode.MUSIC
    } else if (this.capSupportsVideoGeneration) {
      resolvedOutputMode = OutputMode.VIDEO
    } else if (this.capOutputImage) {
      resolvedOutputMode = OutputMode.IMAGE
    }
    return {
      id: this.model.id,
      name: this.tempName,
      contextLength: this.model.contextLength,
      isEnabled: this.model.isEnabled,
      isRecommended: this.model.isRecommended,
      modelType: this.model.modelType,
      inputMode: this.capSupportsVision ? InputMode.VISION : InputMode.TEXT,
      outputMode: resolvedOutputMode,
      capabilities: {
        supportsTools: this.capSupportsTools,
        supportsReasoning: this.capSupportsReasoning,
        supportsWebSearch: this.capSupportsWebSearch,
        supportsVision: this.capSupportsVision,
        supportsStreaming: this.capSupportsStreaming,
        supportsMusicGeneration: this.capSupportsMusicGeneration,
        supportsVideoGeneration: this.capSupportsVideoGeneration
      },
      capabilitiesUserModified: this.userTouched || this.originalUserModified
    }
  }

  build() {
    Column() {
      this.HeaderBar()

      Scroll() {
        Column() {
          // 核心信息区
          this.ModelIdSection()
          this.ModelNameSection()
          // 能力标签区
          this.CapabilityChipsSection()
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 34 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(getAppUiState().themeBackground)
  }

  @Builder
  HeaderBar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(18)
          .fontColor([$r('app.color.text_secondary')])
      }
      .type(ButtonType.Circle)
      .width(36)
      .height(36)
      .backgroundColor($r('app.color.divider'))
      .onClick(() => {
        this.onCancel()
      })

      Text('编辑模型')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Button() {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontColor([Color.White])
      }
      .type(ButtonType.Circle)
      .width(36)
      .height(36)
      .backgroundColor(this.themePrimary)
      .onClick(async () => {
        await this.onSave(this.buildDraft())
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 20, right: 20 })
  }

  @Builder
  ModelIdSection() {
    Row() {
      Column() {
        Text('模型 ID')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ bottom: 4 })

        Text(this.model.id)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button() {
        SymbolGlyph($r('sys.symbol.rectangle_on_rectangle'))
          .fontSize(16)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .type(ButtonType.Circle)
      .width(32)
      .height(32)
      .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(getAppUiState().themeSurface)
    .borderRadius(16)
    .margin({ bottom: 12 })
  }

  @Builder
  ModelNameSection() {
    Column() {
      Text('模型名称')
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ bottom: 8 })

      TextInput({ text: this.tempName, placeholder: '输入模型显示名称' })
        .width('100%')
        .height(44)
        .backgroundColor($r('app.color.divider'))
        .borderRadius(12)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.tempName = value
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(getAppUiState().themeSurface)
    .borderRadius(16)
    .margin({ bottom: 12 })
  }

  @Builder
  CapabilityChipsSection() {
    Column() {
      Row() {
        Text('模型能力')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))

        Blank()

        Text('重置')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .onClick(() => {
            this.resetCapabilities()
          })
      }
      .width('100%')
      .margin({ bottom: 12 })

      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        // 工具调用
        Row() {
          SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
            .fontSize(16)
            .fontColor([this.capSupportsTools ? this.themePrimary : $r('app.color.text_tertiary')])
          Text('工具调用')
            .fontSize(13)
            .fontColor(this.capSupportsTools ? this.themePrimary : $r('app.color.text_secondary'))
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 12, right: 14 })
        .backgroundColor(this.capSupportsTools ? this.themePrimaryLight : $r('app.color.divider'))
        .borderRadius(18)
        .onClick(() => {
          this.capSupportsTools = !this.capSupportsTools
          this.userTouched = true
        })

        // 推理
        Row() {
          SymbolGlyph($r('sys.symbol.AI_deep_thinking'))
            .fontSize(16)
            .fontColor([this.capSupportsReasoning ? this.themePrimary : $r('app.color.text_tertiary')])
          Text('推理')
            .fontSize(13)
            .fontColor(this.capSupportsReasoning ? this.themePrimary : $r('app.color.text_secondary'))
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 12, right: 14 })
        .backgroundColor(this.capSupportsReasoning ? this.themePrimaryLight : $r('app.color.divider'))
        .borderRadius(18)
        .onClick(() => {
          this.capSupportsReasoning = !this.capSupportsReasoning
          this.userTouched = true
        })

        // 模型原生/内置联网搜索
        Row() {
          SymbolGlyph($r('sys.symbol.ohos_wifi'))
            .fontSize(16)
            .fontColor([this.capSupportsWebSearch ? this.themePrimary : $r('app.color.text_tertiary')])
          Text('内置联网')
            .fontSize(13)
            .fontColor(this.capSupportsWebSearch ? this.themePrimary : $r('app.color.text_secondary'))
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 12, right: 14 })

        .backgroundColor(this.capSupportsWebSearch ? this.themePrimaryLight : $r('app.color.divider'))
        .borderRadius(18)
        .onClick(() => {
          this.capSupportsWebSearch = !this.capSupportsWebSearch
          this.userTouched = true
        })

        // 视觉理解
        Row() {
          SymbolGlyph($r('sys.symbol.ohos_photo'))
            .fontSize(16)
            .fontColor([this.capSupportsVision ? this.themePrimary : $r('app.color.text_tertiary')])
          Text('视觉理解')
            .fontSize(13)
            .fontColor(this.capSupportsVision ? this.themePrimary : $r('app.color.text_secondary'))
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 12, right: 14 })
        .backgroundColor(this.capSupportsVision ? this.themePrimaryLight : $r('app.color.divider'))
        .borderRadius(18)
        .onClick(() => {
          this.capSupportsVision = !this.capSupportsVision
          this.userTouched = true
        })

        // 图片生成
        Row() {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(16)
            .fontColor([this.capOutputImage ? this.themePrimary : $r('app.color.text_tertiary')])
          Text('图片生成')
            .fontSize(13)
            .fontColor(this.capOutputImage ? this.themePrimary : $r('app.color.text_secondary'))
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 12, right: 14 })
        .backgroundColor(this.capOutputImage ? this.themePrimaryLight : $r('app.color.divider'))
        .borderRadius(18)
        .onClick(() => {
          this.capOutputImage = !this.capOutputImage
          this.userTouched = true
        })

        // 音乐生成
        Row() {
          SymbolGlyph($r('sys.symbol.waveform'))
            .fontSize(16)
            .fontColor([this.capSupportsMusicGeneration ? this.themePrimary : $r('app.color.text_tertiary')])
          Text('音乐生成')
            .fontSize(13)
            .fontColor(this.capSupportsMusicGeneration ? this.themePrimary : $r('app.color.text_secondary'))
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 12, right: 14 })
        .backgroundColor(this.capSupportsMusicGeneration ? this.themePrimaryLight : $r('app.color.divider'))
        .borderRadius(18)
        .onClick(() => {
          this.capSupportsMusicGeneration = !this.capSupportsMusicGeneration
          this.userTouched = true
        })

        // 视频生成
        Row() {
          SymbolGlyph($r('sys.symbol.wand_and_stars'))
            .fontSize(16)
            .fontColor([this.capSupportsVideoGeneration ? this.themePrimary : $r('app.color.text_tertiary')])
          Text('视频生成')
            .fontSize(13)
            .fontColor(this.capSupportsVideoGeneration ? this.themePrimary : $r('app.color.text_secondary'))
            .margin({ left: 6 })
        }
        .height(36)
        .padding({ left: 12, right: 14 })
        .backgroundColor(this.capSupportsVideoGeneration ? this.themePrimaryLight : $r('app.color.divider'))
        .borderRadius(18)
        .onClick(() => {
          this.capSupportsVideoGeneration = !this.capSupportsVideoGeneration
          this.userTouched = true
        })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(getAppUiState().themeSurface)
    .borderRadius(16)
    .margin({ bottom: 12 })
  }
}
