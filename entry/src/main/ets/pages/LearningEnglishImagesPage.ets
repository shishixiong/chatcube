import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState } from '../state/AppUiState'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationContentTopPadding,
  buildPointLightBorderEffect,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'
import { AdaptiveImageThumbnail } from '../components/AdaptiveImageThumbnail'
import { getImageIndexService } from '../services/ImageIndexService'
import { getDatabaseService } from '../services/DatabaseService'
import { ImageIndexRow, ImageSource } from '../models/ImageIndexModels'

const TAG = 'LearningEnglishImagesPage'
const GRID_LIMIT: number = 200
const GRID_PHONE_COLUMNS: number = 2
const GRID_TABLET_COLUMNS: number = 3

let learningEnglishImagesPagePathStack: NavPathStack | null = null

enum EnglishImageSource {
  QUIZ_WORD = 'quiz_word',
  QUIZ_SENTENCE = 'quiz_sentence',
  PLAN = 'plan'
}

enum EnglishImageFilter {
  ALL = 0,
  QUIZ = 1,
  PLAN = 2
}

interface EnglishImageGalleryItem {
  id: string
  source: EnglishImageSource
  word: string
  sentence: string
  filePath: string
  mimeType: string
  createdAt: number
  topicKey: string
  sourceLabel: ResourceStr
  displayLabel: string
}

@Entry
@ComponentV2
struct LearningEnglishImagesPage {
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themePrimaryLight(): string {
    return getAppUiState().themePrimaryLight
  }
  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }
  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }
  private get layoutSizeClass(): string {
    return getAppUiState().layoutSizeClass
  }
  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }
  private get windowHeightVp(): number {
    return getAppUiState().windowHeightVp
  }
  private get settingsDetailPresentationMode(): string {
    return getAppUiState().settingsDetailPresentationMode
  }
  private get materialType(): number {
    return getAppUiState().materialType
  }
  private get materialLevel(): number {
    return getAppUiState().materialLevel
  }

  @Local items: EnglishImageGalleryItem[] = []
  @Local isLoading: boolean = true
  @Local filterIndex: number = EnglishImageFilter.ALL

  private compactScroller: Scroller = new Scroller()
  private loadToken: number = 0

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  aboutToAppear(): void {
    this.loadItems()
  }

  private getFilteredItems(): EnglishImageGalleryItem[] {
    if (this.filterIndex === EnglishImageFilter.ALL) {
      return this.items
    }
    const result: EnglishImageGalleryItem[] = []
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i]
      if (this.filterIndex === EnglishImageFilter.QUIZ &&
        (item.source === EnglishImageSource.QUIZ_WORD ||
          item.source === EnglishImageSource.QUIZ_SENTENCE)) {
        result.push(item)
      } else if (this.filterIndex === EnglishImageFilter.PLAN &&
        item.source === EnglishImageSource.PLAN) {
        result.push(item)
      }
    }
    return result
  }

  private getGridColumns(): number {
    if (this.layoutSizeClass === 'lg' || this.layoutSizeClass === 'md') {
      return GRID_TABLET_COLUMNS
    }
    return GRID_PHONE_COLUMNS
  }

  private getColumnsTemplate(): string {
    const cols = this.getGridColumns()
    let template = '1fr'
    for (let i = 1; i < cols; i++) {
      template += ' 1fr'
    }
    return template
  }

  private async loadItems(): Promise<void> {
    const token = this.loadToken + 1
    this.loadToken = token
    this.isLoading = true
    try {
      // 统一从 image_index 表取，限 GRID_LIMIT 条；EnglishQuiz 命中后写回的备课图会出现在 quizRows 里
      const imageIndexService = getImageIndexService()
      const now = Date.now()
      const quizRows: ImageIndexRow[] = await imageIndexService
        .getBySource(ImageSource.ENGLISH_QUIZ, GRID_LIMIT)
      const planRowsRaw: ImageIndexRow[] = await imageIndexService
        .getBySource(ImageSource.LESSON_PLAN, GRID_LIMIT)
      // 老 prepared_media 表里还有历史 row（迁移窗口期），也取一份做兼容
      let legacyPlanRows: ImageIndexRow[] = []
      try {
        const legacy = await getDatabaseService().listReadyPreparedMediaByModule('vocab', GRID_LIMIT, now)
        // 转换成 ImageIndexRow 形态以便 merge
        legacyPlanRows = legacy.map((r) => {
          const row = new ImageIndexRow()
          row.id = r.id
          row.source = ImageSource.LESSON_PLAN
          row.key = r.topicKey
          row.filePath = r.filePath
          row.mimeType = r.mimeType
          row.createdAt = r.createdAt
          row.expiresAt = r.expiresAt
          return row
        })
      } catch (_e) {
        // 老表不存在或读失败 → 静默忽略
      }
      if (token !== this.loadToken) {
        return
      }
      // 合并新表 + 老表的 plan rows（去重）
      const planMap: Map<string, ImageIndexRow> = new Map()
      for (let i = 0; i < planRowsRaw.length; i++) {
        const r = planRowsRaw[i]
        if (r.key.startsWith('vocab.')) {
          planMap.set(r.filePath, r)
        }
      }
      for (let i = 0; i < legacyPlanRows.length; i++) {
        const r = legacyPlanRows[i]
        if (!planMap.has(r.filePath)) {
          planMap.set(r.filePath, r)
        }
      }
      const planRows: ImageIndexRow[] = Array.from(planMap.values())
      this.items = this.mergeSources(quizRows, planRows)
    } catch (error) {
      console.error(TAG, `Failed to load images: ${JSON.stringify(error)}`)
      this.items = []
    } finally {
      if (token === this.loadToken) {
        this.isLoading = false
      }
    }
  }

  private mergeSources(quizRows: ImageIndexRow[], planRows: ImageIndexRow[]): EnglishImageGalleryItem[] {
    const merged: EnglishImageGalleryItem[] = []
    const seenFilePaths: Map<string, boolean> = new Map()

    for (let i = 0; i < quizRows.length; i++) {
      const r = quizRows[i]
      if (r.filePath === '') {
        continue
      }
      if (seenFilePaths.has(r.filePath)) {
        continue
      }
      seenFilePaths.set(r.filePath, true)
      // image_index 的 key 形如 'w:apple' / 's:i_like_apples'，从这里反推 word/sentence
      const isSentence = r.key.startsWith('s:')
      const word = isSentence ? '' : r.key.substring(2)
      const sentence = isSentence ? r.key.substring(2).replace(/_/g, ' ') : ''
      const item: EnglishImageGalleryItem = {
        id: `q_${r.id}`,
        source: isSentence ? EnglishImageSource.QUIZ_SENTENCE : EnglishImageSource.QUIZ_WORD,
        word,
        sentence,
        filePath: r.filePath,
        mimeType: r.mimeType,
        createdAt: r.createdAt,
        topicKey: '',
        sourceLabel: isSentence
          ? $r('app.string.learning_image_source_quiz_sentence')
          : $r('app.string.learning_image_source_quiz_word'),
        displayLabel: word !== '' ? word : sentence
      }
      merged.push(item)
    }

    for (let i = 0; i < planRows.length; i++) {
      const r = planRows[i]
      if (r.filePath === '') {
        continue
      }
      if (seenFilePaths.has(r.filePath)) {
        continue
      }
      seenFilePaths.set(r.filePath, true)
      const item: EnglishImageGalleryItem = {
        id: `p_${r.id}`,
        source: EnglishImageSource.PLAN,
        word: '',
        sentence: '',
        filePath: r.filePath,
        mimeType: r.mimeType,
        createdAt: r.createdAt,
        topicKey: r.key,
        sourceLabel: $r('app.string.learning_image_source_plan'),
        displayLabel: r.key
      }
      merged.push(item)
    }

    merged.sort((a: EnglishImageGalleryItem, b: EnglishImageGalleryItem) => b.createdAt - a.createdAt)
    return merged
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private handleBack(): void {
    if (learningEnglishImagesPagePathStack !== null && learningEnglishImagesPagePathStack.size() > 0) {
      learningEnglishImagesPagePathStack.pop()
    }
  }

  private getCompactContentTopPadding(): number {
    return getHdsTopNavigationContentTopPadding(this.px2vp(this.topAvoidHeight), this.windowWidthVp,
      this.windowHeightVp)
  }

  private getCompactTitleBarOptions(): HdsNavigationTitleBarOptions {
    return buildHdsTopNavigationTitleBarOptionsForPage(this.materialType, this.materialLevel, this.windowWidthVp,
      this.windowHeightVp, (): void => this.CompactTitleStackBuilder())
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: $r('app.string.learning_english_images_title'),
      onBack: () => {
        this.handleBack()
      }
    })
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.learning_english_images_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(64)
      .padding({ left: 24, right: 24 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(this.themeBackground)
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  private FilterChip(filterValue: EnglishImageFilter, title: ResourceStr) {
    Column() {
      Text(title)
        .fontSize(13)
        .fontWeight(this.filterIndex === filterValue ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.filterIndex === filterValue ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .backgroundColor(this.filterIndex === filterValue ? this.themePrimaryLight : Color.Transparent)
        .borderRadius(14)
        .animation({ duration: 180, curve: Curve.EaseOut })
    }
    .onClick(() => {
      this.filterIndex = filterValue
    })
  }

  @Builder
  private FilterRow() {
    Row({ space: 8 }) {
      this.FilterChip(EnglishImageFilter.ALL, $r('app.string.learning_image_filter_all'))
      this.FilterChip(EnglishImageFilter.QUIZ, $r('app.string.learning_image_filter_quiz'))
      this.FilterChip(EnglishImageFilter.PLAN, $r('app.string.learning_image_filter_plan'))
      Blank()
    }
    .width('100%')
    .padding({ left: 0, right: 0, top: 4, bottom: 4 })
  }

  @Builder
  private ImageCard(item: EnglishImageGalleryItem) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        AdaptiveImageThumbnail({
          src: `file://${item.filePath}`,
          previewId: item.id,
          maxWidth: 320,
          maxHeight: 220,
          radius: 10,
          fallbackAspectRatio: 1,
          fillWidth: true,
          clickable: true,
          onPreview: (): void => {
          }
        })
      }
      .width('100%')
      .backgroundColor(this.themeSurface)
      .borderRadius(10)
      .clip(true)

      Text(item.displayLabel !== '' ? item.displayLabel : '—')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(item.sourceLabel)
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(8)
    .backgroundColor(this.themeSurface)
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.divider') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private EmptyState() {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.picture'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')])
        .margin({ bottom: 4 })
      Text($r('app.string.learning_images_empty_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
      Text($r('app.string.learning_images_empty_desc'))
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })
    }
    .width('100%')
    .padding({ top: 64, bottom: 64 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private PageContent() {
    Scroll(this.compactScroller) {
      Row() {
        Column() {
          if (!this.isDetailPaneMode()) {
            Blank()
              .width('100%')
              .height(this.getCompactContentTopPadding())
          }

          if (this.getFilteredItems().length === 0 && !this.isLoading) {
            this.EmptyState()
          } else {
            this.FilterRow()
            Grid() {
              ForEach(this.getFilteredItems(), (item: EnglishImageGalleryItem) => {
                GridItem() {
                  this.ImageCard(item)
                }
              }, (item: EnglishImageGalleryItem) => item.id)
            }
            .width('100%')
            .columnsTemplate(this.getColumnsTemplate())
            .columnsGap(10)
            .rowsGap(10)
            .margin({ top: 8 })
            .padding({ bottom: 8 })
          }

          Blank().width('100%').height(28)
        }
        .width('100%')
        .constraintSize({ maxWidth: this.getContentMaxWidth() })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  build() {
    Column() {
      if (this.isDetailPaneMode()) {
        Column() {
          this.DetailPaneHeader()
          this.PageContent()
        }
        .width('100%')
        .layoutWeight(1)
      } else {
        HdsNavigation() {
          this.PageContent()
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.themeBackground)
        .titleBar(this.getCompactTitleBarOptions())
        .bindToScrollable([this.compactScroller])
        .titleMode(HdsNavigationTitleMode.MINI)
        .systemBarStyle(
          { statusBarContentColor: getHdsStatusBarContentColor() },
          { statusBarContentColor: getHdsStatusBarContentColor() }
        )
        .hideBackButton(true)
        .hideToolBar(true)
        .mode(NavigationMode.Stack)
        .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
  }
}

@Builder
export function LearningEnglishImagesPageBuilder(name: string, param: Object) {
  NavDestination() {
    LearningEnglishImagesPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    learningEnglishImagesPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (learningEnglishImagesPagePathStack !== null && learningEnglishImagesPagePathStack.size() > 0) {
      learningEnglishImagesPagePathStack.pop()
    }
    return true
  })
}
