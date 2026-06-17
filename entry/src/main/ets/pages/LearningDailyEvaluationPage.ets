import { HdsNavigation, HdsNavigationTitleBarOptions, HdsNavigationTitleMode } from '@kit.UIDesignKit'
import { SettingsCompactTitleBarContent } from '../components/settings/SettingsCompactPageHeader'
import { SettingsPagePresentationMode } from '../config/SettingsDetailPresentation'
import { getSettingsPageContentMaxWidth } from '../utils/SettingsPageLayoutHelper'
import { getAppUiState, observeAppUiState } from '../state/AppUiState'
import {
  buildHdsTopNavigationTitleBarOptionsForPage,
  getHdsTopNavigationContentTopPadding,
  buildPointLightBorderEffect,
  getHdsStatusBarContentColor
} from '../utils/HdsVisualEffectUtil'
import {
  TeachingStyleAdjustment,
  WeeklyTrend,
  TeachingStyleAdjustmentStatus
} from '../models/TeachingReflectionModels'
import { formatLocalYMD } from '../models/LessonPlanModels'
import { ServiceRegistry } from '../services/ServiceRegistry'
import {
  todayYMD,
  shiftYMD,
  canGoBack as utilCanGoBack,
  canGoForward as utilCanGoForward,
  isWithinHistoryRange
} from '../utils/DateRangeUtils'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { formatRelativeTime } from '../utils/TimeFormatUtils'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import {
  getDimensionLabel,
  computeTrendProgress,
  getTrendRatingLabel
} from '../utils/TeachingStyleAdjustmentUtils'
import { BusinessError } from '@kit.BasicServicesKit'

const TAG = 'LearningDailyEvaluationPage'

let learningDailyEvaluationPagePathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct LearningDailyEvaluationPage {
  private get topAvoidHeight(): number {
    return getAppUiState().topAvoidHeight
  }
  private get themeBackground(): string {
    return getAppUiState().themeBackground
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
  private get windowWidthVp(): number {
    return getAppUiState().windowWidthVp
  }
  private get windowHeightVp(): number {
    return getAppUiState().windowHeightVp
  }
  private get layoutSizeClass(): string {
    return getAppUiState().layoutSizeClass
  }
  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  @Local adjustment: TeachingStyleAdjustment | null = null
  @Local trend: WeeklyTrend | null = null
  @Local selectedDate: string = ''
  @Local isLoading: boolean = true
  @Local isTriggering: boolean = false
  @Local isErrorSheetVisible: boolean = false
  @Local loadError: string = ''

  private loadToken: number = 0
  private pollTimerId: number = -1
  private pollCount: number = 0
  private readonly POLL_INTERVAL_MS: number = 2000
  private readonly POLL_MAX_COUNT: number = 60
  private appStorageDisposer: (() => void) | null = null

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  aboutToAppear(): void {
    this.selectedDate = todayYMD()
    this.loadPage()
    this.subscribeRefreshTick()
  }

  aboutToDisappear(): void {
    this.stopPolling()
    if (this.appStorageDisposer !== null) {
      this.appStorageDisposer()
      this.appStorageDisposer = null
    }
  }

  private async loadPage(): Promise<void> {
    const token: number = ++this.loadToken
    this.isLoading = true
    this.loadError = ''
    try {
      const adj: TeachingStyleAdjustment | null =
        await ServiceRegistry.teachingStyle().getAdjustmentForDate(this.selectedDate)
      if (token !== this.loadToken) {
        return
      }
      this.adjustment = adj
      if (adj !== null && adj.sourceWeeklyTrendId !== '') {
        try {
          this.trend = await ServiceRegistry.weeklyTrend().getTrendById(adj.sourceWeeklyTrendId)
        } catch (e) {
          console.error(TAG, `getTrendById failed: ${(e as BusinessError).message ?? String(e)}`)
          this.trend = null
        }
      } else {
        this.trend = null
      }
    } catch (e) {
      console.error(TAG, `loadPage failed: ${(e as BusinessError).message ?? String(e)}`)
      if (token === this.loadToken) {
        this.loadError = (e as BusinessError).message ?? String(e)
        this.adjustment = null
        this.trend = null
      }
    } finally {
      if (token === this.loadToken) {
        this.isLoading = false
      }
    }
    this.maybeStartPolling()
  }

  private maybeStartPolling(): void {
    const status: string = this.adjustment?.status ?? ''
    if (status !== TeachingStyleAdjustmentStatus.DONE && status !== '' &&
        status !== TeachingStyleAdjustmentStatus.FAILED) {
      this.startPolling()
    } else {
      this.stopPolling()
    }
  }

  private startPolling(): void {
    if (this.pollTimerId !== -1) {
      return
    }
    this.pollCount = 0
    this.pollTimerId = setInterval((): void => {
      this.pollCount++
      if (this.pollCount > this.POLL_MAX_COUNT) {
        console.warn(TAG, `polling timeout after ${this.pollCount} ticks`)
        this.stopPolling()
        return
      }
      this.loadPage()
    }, this.POLL_INTERVAL_MS)
  }

  private stopPolling(): void {
    if (this.pollTimerId !== -1) {
      clearInterval(this.pollTimerId)
      this.pollTimerId = -1
    }
  }

  private subscribeRefreshTick(): void {
    if (this.appStorageDisposer !== null) {
      return
    }
    this.appStorageDisposer = observeAppUiState(AppStorageKeys.TEACHING_STYLE_ADJUSTMENT_REFRESH_TICK, (): void => {
      this.loadPage()
    })
  }

  private async handleTriggerEvaluation(): Promise<void> {
    if (this.isTriggering || this.selectedDate !== todayYMD()) {
      return
    }
    this.isTriggering = true
    try {
      await ServiceRegistry.evaluation().triggerEvaluationForToday(true, 'manual')
    } catch (e) {
      const msg: string = (e as BusinessError).message ?? String(e)
      console.error(TAG, `trigger failed: ${msg}`)
      this.loadError = msg
      this.isErrorSheetVisible = true
    } finally {
      this.isTriggering = false
    }
  }

  private handleBack(): void {
    if (learningDailyEvaluationPagePathStack !== null && learningDailyEvaluationPagePathStack.size() > 0) {
      learningDailyEvaluationPagePathStack.pop()
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

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: $r('app.string.learning_daily_evaluation_title'),
      onBack: () => {
        this.handleBack()
      }
    })
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.learning_daily_evaluation_title'))
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
  private DatePickerBar() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(16)
        .fontColor([this.canGoBack() ? $r('app.color.text_primary') : $r('app.color.text_tertiary')])
        .onClick((): void => {
          if (this.canGoBack()) {
            this.selectedDate = shiftYMD(this.selectedDate, -1)
            this.loadPage()
          }
        })

      Column() {
        Text(this.formatDateDisplay(this.selectedDate))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.formatWeekdayDisplay(this.selectedDate))
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([this.canGoForward() ? $r('app.color.text_primary') : $r('app.color.text_tertiary')])
        .onClick((): void => {
          if (this.canGoForward()) {
            this.selectedDate = shiftYMD(this.selectedDate, 1)
            this.loadPage()
          }
        })

      if (this.selectedDate !== todayYMD()) {
        Text($r('app.string.learning_daily_evaluation_today_short'))
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12)
          .backgroundColor(withColorAlpha(this.themePrimary, '14'))
          .onClick((): void => {
            this.selectedDate = todayYMD()
            this.loadPage()
          })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
  }

  private formatDateDisplay(ymd: string): string {
    if (ymd === todayYMD()) {
      return '今天'
    }
    return ymd
  }

  private formatWeekdayDisplay(ymd: string): string {
    const labels: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']
    const parts: string[] = ymd.split('-')
    if (parts.length !== 3) {
      return ''
    }
    const y: number = parseInt(parts[0], 10)
    const m: number = parseInt(parts[1], 10) - 1
    const d: number = parseInt(parts[2], 10)
    const date: Date = new Date(y, m, d)
    return labels[date.getDay()]
  }

  private canGoBack(): boolean {
    return utilCanGoBack(this.selectedDate)
  }

  private canGoForward(): boolean {
    return utilCanGoForward(this.selectedDate)
  }

  @Builder
  private StatusPill(status: string) {
    Text(this.getStatusLabel(status))
      .fontSize(10)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.getStatusTextColor(status))
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(10)
      .backgroundColor(this.getStatusBgColor(status))
  }

  private getStatusLabel(status: string): string {
    switch (status) {
      case TeachingStyleAdjustmentStatus.DONE: return '已完成'
      case TeachingStyleAdjustmentStatus.FAILED: return '失败'
      case 'pending': return '排队中'
      case 'running': return '生成中'
      default: return '未知'
    }
  }

  private getStatusBgColor(status: string): string {
    switch (status) {
      case TeachingStyleAdjustmentStatus.DONE: return withColorAlpha('#22C55E', '0C')
      case TeachingStyleAdjustmentStatus.FAILED: return withColorAlpha('#EF4444', '0C')
      case 'pending': return withColorAlpha('#FF9F43', '0C')
      case 'running': return withColorAlpha('#3B82F6', '0C')
      default: return withColorAlpha('#9CA3AF', '0C')
    }
  }

  private getStatusTextColor(status: string): string {
    switch (status) {
      case TeachingStyleAdjustmentStatus.DONE: return '#22C55E'
      case TeachingStyleAdjustmentStatus.FAILED: return '#EF4444'
      case 'pending': return '#FF9F43'
      case 'running': return '#3B82F6'
      default: return '#9CA3AF'
    }
  }

  @Builder
  private SummaryCard() {
    if (this.adjustment === null) {
      // 占位
      Column() {}
    } else {
      Column({ space: 6 }) {
        Row() {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.calendar'))
              .fontSize(13)
              .fontColor([getAppUiState().themePrimary])
            Text(this.formatDateDisplay(this.adjustment.effectiveDate))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
          }
          .layoutWeight(1)

          this.StatusPill(this.adjustment.status)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(`生成于 ${formatRelativeTime(this.adjustment.createdAt)} · 来自 ${this.adjustment.sourceSessionCount} 次对话`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))

        Text(`置信度 ${this.formatConfidence(this.adjustment.confidence)} · 模型 ${this.adjustment.evaluatorModelName !== '' ? this.adjustment.evaluatorModelName : '—'}`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .padding(14)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(16)
      .border({ width: 1, color: $r('app.color.divider') })
      .visualEffect(buildPointLightBorderEffect())
    }
  }

  private formatConfidence(c: number): string {
    if (c <= 0) {
      return '—'
    }
    return c.toFixed(2)
  }

  @Builder
  private PageContent() {
    Column({ space: 12 }) {
      this.DatePickerBar()
      if (!this.isLoading && this.adjustment !== null) {
        this.SummaryCard()
      }
      Text('TODO: 4 维度 + WeeklyTrend')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 16, right: 16 })
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
        .bindToScrollable([])
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
export function LearningDailyEvaluationPageBuilder(name: string, param: Object) {
  NavDestination() {
    LearningDailyEvaluationPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    learningDailyEvaluationPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (learningDailyEvaluationPagePathStack !== null && learningDailyEvaluationPagePathStack.size() > 0) {
      learningDailyEvaluationPagePathStack.pop()
    }
    return true
  })
}
