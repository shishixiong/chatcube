/**
 * 家长端「动画片管理」页（spec 2026-11-10 §9）。
 *
 * - 从系统文件选择器导入本地视频；不复制文件，走 fileShare 持久授权
 * - 自动读取时长；超过 20 分钟的片子直接拒绝导入
 * - 显示今天已看时长；文件失效可重新关联
 */

import { picker } from '@kit.CoreFileKit'
import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState } from '../state/AppUiState'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationContentTopPadding,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'
import { getCartoonLibraryService } from '../services/CartoonLibraryService'
import { getCartoonWatchService } from '../services/CartoonWatchService'
import { CartoonEntry } from '../models/CartoonModels'
import { formatDurationSeconds } from '../utils/CartoonQuotaMath'
import { formatEpisodeLabel } from '../utils/CartoonLibraryUtils'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { showToast } from '../utils/ToastUtil'

const TAG = 'CartoonLibraryPage'

let cartoonLibraryPagePathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct CartoonLibraryPage {
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

  @Local entries: CartoonEntry[] = []
  @Local todayUsedMs: number = 0
  @Local isLoading: boolean = true
  @Local showEditSheet: boolean = false
  @Local editingId: string = ''
  @Local editingSeriesTitle: string = ''
  @Local editingSeason: string = ''
  @Local editingEpisode: string = ''
  @Local editingTitle: string = ''
  @Local editingTags: string = ''

  private compactScroller: Scroller = new Scroller()

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  aboutToAppear(): void {
    this.loadAll()
  }

  private async loadAll(): Promise<void> {
    this.isLoading = true
    try {
      const library = getCartoonLibraryService()
      await library.initialize()
      await library.refreshStatuses()
      this.entries = library.list()
      const snapshot = await getCartoonWatchService().snapshot()
      this.todayUsedMs = snapshot.dayMs
    } catch (error) {
      console.error(TAG, `loadAll failed: ${JSON.stringify(error)}`)
    } finally {
      this.isLoading = false
    }
  }

  private async reload(): Promise<void> {
    this.entries = getCartoonLibraryService().list()
    this.todayUsedMs = (await getCartoonWatchService().snapshot()).dayMs
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
    if (cartoonLibraryPagePathStack !== null && cartoonLibraryPagePathStack.size() > 0) {
      cartoonLibraryPagePathStack.pop()
    }
  }

  private async pickVideos(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext()
      if (context === undefined) {
        return
      }
      const documentPicker = new picker.DocumentViewPicker(context)
      const options = new picker.DocumentSelectOptions()
      options.maxSelectNumber = 20
      options.fileSuffixFilters = ['视频|.mp4,.mkv,.mov,.webm,.avi,.ts']
      const uris = await documentPicker.select(options)
      if (uris.length === 0) {
        return
      }
      const outcome = await getCartoonLibraryService().addFromUris(uris)
      await this.reload()
      if (outcome.addedCount > 0) {
        const rejectedNote = outcome.rejectedMessages.length > 0
          ? `，${outcome.rejectedMessages.length} 部没加上`
          : ''
        showToast(this.getUIContext(), `已添加 ${outcome.addedCount} 部${rejectedNote}`)
      } else if (outcome.rejectedMessages.length > 0) {
        showToast(this.getUIContext(), outcome.rejectedMessages[0], 3000)
      } else {
        showToast(this.getUIContext(), '没有添加新的动画片')
      }
    } catch (error) {
      console.error(TAG, `pickVideos failed: ${JSON.stringify(error)}`)
      showToast(this.getUIContext(), '打开文件选择器失败')
    }
  }

  private async relink(entry: CartoonEntry): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext()
      if (context === undefined) {
        return
      }
      const documentPicker = new picker.DocumentViewPicker(context)
      const options = new picker.DocumentSelectOptions()
      options.maxSelectNumber = 1
      options.fileSuffixFilters = ['视频|.mp4,.mkv,.mov,.webm,.avi,.ts']
      const uris = await documentPicker.select(options)
      if (uris.length === 0) {
        return
      }
      const message = await getCartoonLibraryService().relinkEntry(entry.id, uris[0])
      if (message !== '') {
        showToast(this.getUIContext(), message, 3000)
      }
      await this.reload()
    } catch (error) {
      console.error(TAG, `relink failed: ${JSON.stringify(error)}`)
      showToast(this.getUIContext(), '重新关联失败')
    }
  }

  private startEdit(entry: CartoonEntry): void {
    this.editingId = entry.id
    this.editingSeriesTitle = entry.seriesTitle
    this.editingSeason = entry.season > 0 ? entry.season.toString() : ''
    this.editingEpisode = entry.episode > 0 ? entry.episode.toString() : ''
    this.editingTitle = entry.title
    this.editingTags = entry.tags
    this.showEditSheet = true
  }

  private async saveEdit(): Promise<void> {
    const seriesTitle = this.editingSeriesTitle.trim()
    const title = this.editingTitle.trim()
    if (seriesTitle === '') {
      showToast(this.getUIContext(), '动画片名不能为空')
      return
    }
    if (title === '') {
      showToast(this.getUIContext(), '集标题不能为空')
      return
    }
    const season = Number(this.editingSeason.trim())
    const episode = Number(this.editingEpisode.trim())
    const ok = await getCartoonLibraryService().updateEntry(
      this.editingId,
      seriesTitle,
      Number.isFinite(season) ? Math.floor(season) : 0,
      Number.isFinite(episode) ? Math.floor(episode) : 0,
      title,
      this.editingTags
    )
    if (!ok) {
      showToast(this.getUIContext(), '这条动画片已经不在了')
    }
    this.showEditSheet = false
    await this.reload()
  }

  private confirmDelete(entry: CartoonEntry): void {
    AlertDialog.show({
      title: '删除动画片',
      message: `删除「${entry.title}」后，小星游戏老师就找不到这一集了。`,
      primaryButton: {
        value: '取消',
        action: (): void => {}
      },
      secondaryButton: {
        value: '删除',
        action: (): void => {
          this.removeEntry(entry)
        }
      }
    })
  }

  private async removeEntry(entry: CartoonEntry): Promise<void> {
    await getCartoonLibraryService().removeEntry(entry.id)
    await this.reload()
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: '动画片管理',
      onBack: (): void => {
        this.handleBack()
      }
    })
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text('动画片管理')
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
  private InfoCard() {
    Column({ space: 6 }) {
      Text('只有小星游戏老师能播放这些动画片。')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
      Text('单次连续最多 20 分钟，每天最多 60 分钟；到点只会在集与集之间停，不会切断正在播的一集。')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .lineHeight(18)
        .width('100%')
      Text(`今天已看 ${Math.floor(this.todayUsedMs / 60000)} 分钟 / 60 分钟`)
        .fontSize(12)
        .fontColor(this.themePrimary)
        .width('100%')
        .margin({ top: 2 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor(withColorAlpha(this.themePrimary, '14'))
    .borderRadius(12)
  }

  private entryHeadline(entry: CartoonEntry): string {
    const label = formatEpisodeLabel(entry)
    const prefix = label !== '' ? `${entry.seriesTitle} · ${label}` : entry.seriesTitle
    if (entry.title !== '' && entry.title !== entry.seriesTitle) {
      return `${prefix} · ${entry.title}`
    }
    return prefix
  }

  private entrySubline(entry: CartoonEntry): string {
    const parts: string[] = []
    parts.push(formatDurationSeconds(Math.round(entry.durationMs / 1000)))
    if (entry.tags !== '') {
      parts.push(entry.tags)
    }
    if (entry.lastWatchedAt > 0) {
      parts.push('看过')
    }
    return parts.join(' · ')
  }

  @Builder
  private EntryRow(entry: CartoonEntry) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.play_circle'))
          .fontSize(18)
          .fontColor([this.themePrimary])
        Column({ space: 2 }) {
          Text(this.entryHeadline(entry))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.entrySubline(entry))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(entry.status === 'ok' ? '正常' : '失效')
          .fontSize(11)
          .fontColor(entry.status === 'ok' ? $r('app.color.status_success') : $r('app.color.status_error'))
      }
      .width('100%')

      Row({ space: 8 }) {
        if (entry.status !== 'ok') {
          Button('重新关联')
            .fontSize(12)
            .height(30)
            .backgroundColor(this.themeSurface)
            .fontColor(this.themePrimary)
            .onClick(() => {
              this.relink(entry)
            })
        }
        Blank()
        Button('编辑')
          .fontSize(12)
          .height(30)
          .backgroundColor(this.themeSurface)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.startEdit(entry)
          })
        Button('删除')
          .fontSize(12)
          .height(30)
          .backgroundColor(this.themeSurface)
          .fontColor($r('app.color.status_error'))
          .onClick(() => {
            this.confirmDelete(entry)
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.themeSurface)
    .borderRadius(12)
  }

  @Builder
  private EmptyState() {
    Column({ space: 8 }) {
      Text('还没有动画片')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text('点击下方按钮，从手机里选择视频文件。')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private EditSheetBuilder() {
    Column({ space: 12 }) {
      Text('编辑动画片')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      TextInput({ text: this.editingSeriesTitle, placeholder: '动画片名（如 Numberblocks）' })
        .height(44)
        .onChange((value: string) => {
          this.editingSeriesTitle = value
        })
      Row({ space: 10 }) {
        TextInput({ text: this.editingSeason, placeholder: '第几季' })
          .height(44)
          .type(InputType.Number)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.editingSeason = value
          })
        TextInput({ text: this.editingEpisode, placeholder: '第几集' })
          .height(44)
          .type(InputType.Number)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.editingEpisode = value
          })
      }
      .width('100%')
      TextInput({ text: this.editingTitle, placeholder: '集标题（可选）' })
        .height(44)
        .onChange((value: string) => {
          this.editingTitle = value
        })
      TextInput({ text: this.editingTags, placeholder: '标签，逗号分隔（可选）' })
        .height(44)
        .onChange((value: string) => {
          this.editingTags = value
        })
      Button('保存')
        .width('100%')
        .height(44)
        .backgroundColor(this.themePrimary)
        .fontColor(Color.White)
        .onClick(() => {
          this.saveEdit()
        })
    }
    .width('100%')
    .padding(20)
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

          this.InfoCard()

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
          } else if (this.entries.length === 0) {
            this.EmptyState()
          } else {
            ForEach(this.entries, (entry: CartoonEntry) => {
              this.EntryRow(entry)
            }, (entry: CartoonEntry) => entry.id)
          }

          Button('＋ 添加动画片')
            .width('100%')
            .height(46)
            .backgroundColor(this.themePrimary)
            .fontColor(Color.White)
            .onClick(() => {
              this.pickVideos()
            })

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
    .bindSheet($$this.showEditSheet, this.EditSheetBuilder(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: true,
      preferType: SheetType.BOTTOM
    })
  }
}

@Builder
export function CartoonLibraryPageBuilder(name: string, param: Object) {
  NavDestination() {
    CartoonLibraryPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    cartoonLibraryPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (cartoonLibraryPagePathStack !== null && cartoonLibraryPagePathStack.size() > 0) {
      cartoonLibraryPagePathStack.pop()
    }
    return true
  })
}
