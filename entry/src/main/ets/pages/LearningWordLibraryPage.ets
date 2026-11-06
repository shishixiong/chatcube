/**
 * LearningWordLibraryPage - 家长端「英语单词库」页 (2026-11-03)
 *
 * 数据源: learning_items (subject='en', item_type='vocab'), 按最近教学时间倒序。
 * 每行: 英文词 / 中文释义 (本地词库命中才有) / 教学次数 / 最近教学时间 / 四维掌握状态 / 弱项标签。
 * 四维: 认 (看图认词) · 听 (听音选词/辨音) · 读 (跟读) · 写 (默写/拼写), 各 0-5 级。
 * 单字母条目 (letter_trace 写入的 en:vocab:a) 不属于单词库, 过滤掉。
 */

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
import { getLearningLedgerService } from '../services/LearningLedgerService'
import {
  LearningItem,
  LEDGER_DIMENSIONS,
  dimensionLabel,
  dimensionCountsOf,
  skillDimensionLevel,
  weakDimensionsFor
} from '../models/LearningLedgerModels'
import { findLocalVocabEntry } from '../utils/LocalVocabCatalog'
import { formatRelativeTime } from '../utils/TimeFormatUtils'
import { withColorAlpha } from '../utils/ColorAlphaUtils'

const TAG = 'LearningWordLibraryPage'
const FILTER_ALL: number = 0
const FILTER_DUE: number = 1
const FILTER_WEAK: number = 2
const FILTERS: number[] = [FILTER_ALL, FILTER_DUE, FILTER_WEAK]
const WORD_LIBRARY_LIMIT: number = 500

let learningWordLibraryPagePathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct LearningWordLibraryPage {
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
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

  @Local words: LearningItem[] = []
  @Local isLoading: boolean = true
  @Local filterIndex: number = FILTER_ALL

  private compactScroller: Scroller = new Scroller()

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  aboutToAppear(): void {
    this.loadWords()
  }

  private async loadWords(): Promise<void> {
    this.isLoading = true
    try {
      const rows = await getLearningLedgerService().listWords('en', 'vocab', WORD_LIBRARY_LIMIT)
      const filtered: LearningItem[] = []
      for (let i = 0; i < rows.length; i++) {
        // 单字母条目是字母描红留下的, 不属于单词库
        if (rows[i].display.trim().length >= 2) {
          filtered.push(rows[i])
        }
      }
      this.words = filtered
    } catch (error) {
      console.warn(TAG, `loadWords failed (ignored): ${String(error)}`)
    } finally {
      this.isLoading = false
    }
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private getCompactContentTopPadding(): number {
    return getHdsTopNavigationContentTopPadding(this.px2vp(this.topAvoidHeight), this.windowWidthVp,
      this.windowHeightVp)
  }

  private getCompactTitleBarOptions(): HdsNavigationTitleBarOptions {
    return buildHdsTopNavigationTitleBarOptionsForPage(this.materialType, this.materialLevel, this.windowWidthVp,
      this.windowHeightVp, (): void => this.CompactTitleStackBuilder())
  }

  private handleBack(): void {
    if (learningWordLibraryPagePathStack !== null && learningWordLibraryPagePathStack.size() > 0) {
      learningWordLibraryPagePathStack.pop()
    }
  }

  private matchesFilter(item: LearningItem): boolean {
    if (this.filterIndex === FILTER_DUE) {
      return item.nextReviewAt > 0 && item.nextReviewAt <= Date.now()
    }
    if (this.filterIndex === FILTER_WEAK) {
      return weakDimensionsFor(item).length > 0
    }
    return true
  }

  private visibleWords(): LearningItem[] {
    const out: LearningItem[] = []
    for (let i = 0; i < this.words.length; i++) {
      if (this.matchesFilter(this.words[i])) {
        out.push(this.words[i])
      }
    }
    return out
  }

  private zhOf(word: string): string {
    const entry = findLocalVocabEntry(word)
    return entry !== null ? entry.zh : ''
  }

  private dimensionSummary(item: LearningItem): string {
    const parts: string[] = []
    for (let i = 0; i < LEDGER_DIMENSIONS.length; i++) {
      const dim = LEDGER_DIMENSIONS[i]
      const counts = dimensionCountsOf(item, dim)
      parts.push(`${dimensionLabel(dim)} ${skillDimensionLevel(counts.ok, counts.tries)}`)
    }
    return parts.join(' · ')
  }

  private weakLabel(item: LearningItem): string {
    const weak = weakDimensionsFor(item)
    if (weak.length === 0) {
      return ''
    }
    const labels: string[] = []
    for (let i = 0; i < weak.length; i++) {
      labels.push(dimensionLabel(weak[i]))
    }
    return `弱项 ${labels.join('/')}`
  }

  private filterLabel(index: number): string {
    if (index === FILTER_DUE) {
      return '待复习'
    }
    if (index === FILTER_WEAK) {
      return '弱项'
    }
    return '全部'
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: '单词库',
      onBack: () => {
        this.handleBack()
      }
    })
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text('单词库')
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
  private FilterBar() {
    Row({ space: 8 }) {
      ForEach(FILTERS, (index: number) => {
        Text(this.filterLabel(index))
          .fontSize(13)
          .fontWeight(this.filterIndex === index ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.filterIndex === index ? Color.White : $r('app.color.text_secondary'))
          .backgroundColor(this.filterIndex === index ? this.themePrimary : this.themeSurface)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .borderRadius(16)
          .onClick(() => {
            this.filterIndex = index
          })
      }, (index: number) => `filter_${index}`)
    }
    .width('100%')
  }

  @Builder
  private WordRow(item: LearningItem) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(item.display)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        if (this.zhOf(item.display) !== '') {
          Text(this.zhOf(item.display))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        Blank()
        if (this.weakLabel(item) !== '') {
          Text(this.weakLabel(item))
            .fontSize(10)
            .fontColor('#FF9F43')
            .backgroundColor(withColorAlpha('#FF9F43', '18'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(item.exposureCount > 0
        ? `教学 ${item.exposureCount} 次 · 最近教学 ${formatRelativeTime(item.lastSeenAt)}`
        : '未开始')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')

      Text(this.dimensionSummary(item))
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.themeSurface)
    .borderRadius(14)
    .border({ width: 1, color: $r('app.color.divider') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private EmptyState() {
    Column({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.book'))
        .fontSize(44)
        .fontColor([$r('app.color.text_tertiary')])
        .margin({ bottom: 4 })
      Text(this.words.length === 0 && !this.isLoading ? '还没有教过的单词' : '这个筛选下没有单词')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
      Text(this.words.length === 0 && !this.isLoading
        ? '和小星老师上一节英语课，学过的词会自动收进这里'
        : '换个筛选看看，或者先学几个新词')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })
    }
    .width('100%')
    .padding({ top: 56, bottom: 56 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private PageContent() {
    Scroll(this.compactScroller) {
      Row() {
        Column({ space: 12 }) {
          if (!this.isDetailPaneMode()) {
            Blank()
              .width('100%')
              .height(this.getCompactContentTopPadding())
          }

          this.FilterBar()

          if (this.isLoading) {
            Row() {
              LoadingProgress()
                .width(28)
                .height(28)
                .color(this.themePrimary)
            }
            .width('100%')
            .padding({ top: 48, bottom: 48 })
            .justifyContent(FlexAlign.Center)
          } else if (this.visibleWords().length === 0) {
            this.EmptyState()
          } else {
            ForEach(this.visibleWords(), (item: LearningItem) => {
              this.WordRow(item)
            }, (item: LearningItem) => item.itemKey)
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
export function LearningWordLibraryPageBuilder(name: string, param: Object) {
  NavDestination() {
    LearningWordLibraryPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    learningWordLibraryPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (learningWordLibraryPagePathStack !== null && learningWordLibraryPagePathStack.size() > 0) {
      learningWordLibraryPagePathStack.pop()
    }
    return true
  })
}
