import { TtsVoice } from '../../models/TtsEngineProfile'
import { getAppUiState } from '../../state/AppUiState'

// 按语言分组的 voice 列表(用于 ForEach)
interface VoiceLanguageGroup {
  language: string
  langLabel: Resource
  voices: TtsVoice[]
}

@ComponentV2
export struct TtsVoicePickerSheetContent {
  // 当前生效的 voice id (空串 = 用引擎默认)
  @Param currentVoiceId: string = ''
  // 引擎默认 voice id, 用于在列表中标 "默认" 标签
  @Param defaultVoiceId: string = ''
  // 该引擎的全部音色
  @Param voices: TtsVoice[] = []

  @Event onSelectVoice: (voiceId: string) => void = () => {}

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  // 把扁平 voices 按 language 分组, 中文优先, 英文次之, 其他兜底
  private buildGroups(): VoiceLanguageGroup[] {
    const groups: VoiceLanguageGroup[] = []
    const seenLanguages: Map<string, TtsVoice[]> = new Map()
    for (let i = 0; i < this.voices.length; i++) {
      const v = this.voices[i]
      let bucket = seenLanguages.get(v.language)
      if (bucket === undefined) {
        bucket = []
        seenLanguages.set(v.language, bucket)
      }
      bucket.push(v)
    }
    // 推送顺序: 中文 → 英文 → 粤语 → 其他
    const priorityOrder: string[] = ['中文', '英文', '粤语']
    for (let i = 0; i < priorityOrder.length; i++) {
      const lang = priorityOrder[i]
      const list = seenLanguages.get(lang)
      if (list !== undefined && list.length > 0) {
        groups.push({
          language: lang,
          langLabel: this.resolveLangLabel(lang),
          voices: list
        })
        seenLanguages.delete(lang)
      }
    }
    // 其余语言按 Map 自然顺序追加
    seenLanguages.forEach((list: TtsVoice[], lang: string): void => {
      groups.push({
        language: lang,
        langLabel: this.resolveLangLabel(lang),
        voices: list
      })
    })
    return groups
  }

  private resolveLangLabel(language: string): Resource {
    if (language === '中文') {
      return $r('app.string.tts_voice_lang_chinese')
    }
    if (language === '英文') {
      return $r('app.string.tts_voice_lang_english')
    }
    if (language === '粤语') {
      return $r('app.string.tts_voice_lang_cantonese')
    }
    return $r('app.string.tts_voice_lang_other')
  }

  // 用户当前实际生效的 voice id (空串时 fallback 到 defaultVoiceId, 让 UI 上能正确高亮)
  private resolveEffectiveVoiceId(): string {
    if (this.currentVoiceId !== '') {
      return this.currentVoiceId
    }
    return this.defaultVoiceId
  }

  build() {
    Column() {
      // Header
      Row() {
        Text($r('app.string.tts_voice_select_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .height(56)
      .width('100%')
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      if (this.voices.length === 0) {
        Text($r('app.string.tts_voice_empty'))
          .fontColor($r('app.color.text_tertiary'))
          .padding(16)
      }

      List() {
        ForEach(this.buildGroups(), (group: VoiceLanguageGroup) => {
          ListItemGroup({
            header: this.GroupHeader(group.langLabel)
          }) {
            ForEach(group.voices, (voice: TtsVoice) => {
              ListItem() {
                this.VoiceRow(voice)
              }
            })
          }
        })
      }
      .listDirection(Axis.Vertical)
      .sticky(StickyStyle.Header)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private GroupHeader(label: Resource) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 6 })
    .backgroundColor(getAppUiState().themeBackground)
  }

  @Builder
  private VoiceRow(voice: TtsVoice) {
    Row() {
      Column() {
        Row() {
          Text(voice.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))

          if (voice.id === this.defaultVoiceId) {
            Text($r('app.string.tts_voice_default_tag'))
              .fontSize(11)
              .fontColor(Color.White)
              .backgroundColor(this.themePrimary)
              .borderRadius(4)
              .padding({ left: 6, right: 6 })
              .margin({ left: 8 })
          }
        }

        Text(`${voice.language} · ${voice.gender}`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (voice.id === this.resolveEffectiveVoiceId()) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(20)
          .fontColor([this.themePrimary])
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(voice.id === this.resolveEffectiveVoiceId()
      ? getAppUiState().themeSurface
      : Color.Transparent)
    .onClick(() => {
      this.onSelectVoice(voice.id)
    })
  }
}
