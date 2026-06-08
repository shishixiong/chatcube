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
import { getLessonPlanningService } from '../services/LessonPlanningService'
import { getDatabaseService } from '../services/DatabaseService'
import {
  ChildSnapshot,
  DailyLessonPlan,
  DailyLessonPlanRow,
  LessonPlan,
  LessonPlanGeneralItem,
  LessonPlanMathItem,
  LessonPlanStatus,
  LessonPlanVocabItem,
  LessonPlanWritingItem,
  formatLocalYMD,
  parseLessonPlan
} from '../models/LessonPlanModels'

const RECENT_DAYS: number = 7
const REFRESH_POLL_INTERVAL_MS: number = 2000
const REFRESH_POLL_TIMEOUT_MS: number = 120000

const TAG = 'LearningTomorrowPlanPage'

let learningTomorrowPlanPagePathStack: NavPathStack | null = null

@Entry
@ComponentV2
struct LearningTomorrowPlanPage {
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

  @Local plan: LessonPlan = new LessonPlan()
  @Local planDate: string = ''
  @Local status: string = ''
  @Local isLoading: boolean = true
  @Local recentRows: DailyLessonPlanRow[] = []
  @Local isGenerating: boolean = false
  @Local expandedDate: string = ''

  private compactScroller: Scroller = new Scroller()
  private loadToken: number = 0
  private pollTimerId: number = -1
  private pollStartedAt: number = 0
  private pastPlanCache: Map<string, LessonPlan> = new Map()

  private px2vp(px: number): number {
    return px / (this.getUIContext().getHostContext()?.resourceManager.getDeviceCapabilitySync().screenDensity ?? 3) * 160
  }

  aboutToAppear(): void {
    this.loadAll()
  }

  aboutToDisappear(): void {
    this.stopPolling()
  }

  private getTodayYMD(): string {
    return formatLocalYMD(new Date())
  }

  private getDayOfWeekLabel(date: Date): string {
    const labels: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']
    return labels[date.getDay()]
  }

  private getRelativeDateLabel(ymd: string): string {
    if (ymd === '') {
      return ''
    }
    if (ymd === this.getTodayYMD()) {
      return '今天'
    }
    const y = new Date()
    y.setDate(y.getDate() - 1)
    if (ymd === formatLocalYMD(y)) {
      return '昨天'
    }
    // 解析 ymd → MM-DD 周X
    const parts: string[] = ymd.split('-')
    if (parts.length !== 3) {
      return ymd
    }
    const monthStr: string = parts[1]
    const dayStr: string = parts[2]
    const parsed: Date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
    return `${monthStr}-${dayStr} ${this.getDayOfWeekLabel(parsed)}`
  }

  private async loadAll(): Promise<void> {
    await this.loadPlan()
    await this.loadRecent()
  }

  private async loadPlan(): Promise<void> {
    const token = this.loadToken + 1
    this.loadToken = token
    this.isLoading = true
    try {
      const todayYMD = this.getTodayYMD()
      // 注意: getTodayPlan() 内部使用"明天"作为 planDate, 这里需要查"今天"
      // 所以直接走 getPlanByDate(todayYMD), 与 getTodayPlan 共享幂等 + 解析逻辑
      const result: DailyLessonPlan | null = await getLessonPlanningService().getPlanByDate(todayYMD)
      if (token !== this.loadToken) {
        return
      }
      if (result !== null) {
        this.plan = result.plan
        this.planDate = result.row.planDate
        this.status = result.row.status
      } else {
        // 即使 status=pending/running/failed, row 也不为空 (因为昨天可能已写入过今日行);
        // 此时 getPlanByDate 返回 null (因为它只接受 done 状态)。用 getDailyLessonPlanByDate 拿原始行。
        const rawRow: DailyLessonPlanRow | null = await getDatabaseService().getDailyLessonPlanByDate(todayYMD)
        if (token !== this.loadToken) {
          return
        }
        if (rawRow !== null) {
          this.plan = parseLessonPlan(rawRow.planJson)
          this.planDate = rawRow.planDate
          this.status = rawRow.status
        } else {
          this.plan = new LessonPlan()
          this.planDate = todayYMD
          this.status = ''
        }
      }
    } catch (error) {
      console.error(TAG, `Failed to load plan: ${JSON.stringify(error)}`)
    } finally {
      if (token === this.loadToken) {
        this.isLoading = false
      }
    }
  }

  private async loadRecent(): Promise<void> {
    try {
      // 多取 1 行以防今日挤进 7 天窗口
      const rows: DailyLessonPlanRow[] = await getDatabaseService().getRecentDailyLessonPlans(RECENT_DAYS + 1)
      // 过滤掉今日 (今日在主视图完整展示), 只保留过去 7 天
      const todayYMD = this.getTodayYMD()
      const pastRows: DailyLessonPlanRow[] = rows.filter(r => r.planDate !== todayYMD).slice(0, RECENT_DAYS)
      this.recentRows = pastRows
      this.pastPlanCache.clear()
    } catch (error) {
      console.error(TAG, `Failed to load recent plans: ${JSON.stringify(error)}`)
      this.recentRows = []
    }
  }

  private getPastPlan(date: string): LessonPlan | null {
    const cached = this.pastPlanCache.get(date)
    if (cached !== undefined) {
      return cached
    }
    const row = this.recentRows.find(r => r.planDate === date)
    if (row === undefined) {
      return null
    }
    const plan = parseLessonPlan(row.planJson)
    this.pastPlanCache.set(date, plan)
    return plan
  }

  private handlePastRowClick(row: DailyLessonPlanRow): void {
    if (row.status !== LessonPlanStatus.DONE) {
      return
    }
    if (this.expandedDate === row.planDate) {
      this.expandedDate = ''
    } else {
      this.expandedDate = row.planDate
    }
  }

  private stopPolling(): void {
    if (this.pollTimerId >= 0) {
      clearInterval(this.pollTimerId)
      this.pollTimerId = -1
    }
  }

  private startPolling(): void {
    this.stopPolling()
    this.pollStartedAt = Date.now()
    this.pollTimerId = setInterval(() => {
      if (Date.now() - this.pollStartedAt > REFRESH_POLL_TIMEOUT_MS) {
        // 超时兜底, 避免无限轮询
        this.stopPolling()
        this.isGenerating = false
        return
      }
      void this.loadAll()
    }, REFRESH_POLL_INTERVAL_MS)
  }

  private async handleRefresh(): Promise<void> {
    if (this.isGenerating) {
      return
    }
    this.isGenerating = true
    this.stopPolling()
    const todayYMD = this.getTodayYMD()
    try {
      await getLessonPlanningService().triggerPlanningForDate(todayYMD, true, 'manual')
      // 一次性完成: 关闭轮询, 重新拉一次
      this.stopPolling()
      await this.loadAll()
    } catch (error) {
      console.error(TAG, `triggerPlanningForDate failed: ${JSON.stringify(error)}`)
    } finally {
      this.isGenerating = false
    }
  }

  private isEmpty(): boolean {
    if (this.planDate === '' || this.status !== 'done') {
      return true
    }
    const p = this.plan
    return p.themeTitle === '' &&
      p.vocab.length === 0 &&
      p.math.length === 0 &&
      p.writing.length === 0 &&
      p.generalKnowledge.length === 0
  }

  /**
   * 是否为"半残"plan: status=done 但 4 个模块数组全空
   * (LLM 把内容写成 theme 叙述而没填入 4 个数组, 通过 runPlanningPipeline 校验会失败重试,
   * 但老数据可能存在). 这种情况仍允许用户手动重新生成.
   */
  private isPlanBroken(): boolean {
    if (this.status !== LessonPlanStatus.DONE) {
      return false
    }
    const p = this.plan
    return p.vocab.length === 0 && p.math.length === 0 &&
      p.writing.length === 0 && p.generalKnowledge.length === 0
  }

  /**
   * 是否允许手动重新生成今日计划.
   * - 无 row / 失败 / pending / running: 允许
   * - done + 内容完整: 不允许 (避免误覆盖)
   * - done + 4 段全空 (半残): 允许 (给用户修复入口)
   */
  private canRegenerate(): boolean {
    if (this.isGenerating) {
      return false
    }
    if (this.status === '' || this.status === LessonPlanStatus.FAILED ||
      this.status === LessonPlanStatus.PENDING || this.status === LessonPlanStatus.RUNNING) {
      return true
    }
    return this.isPlanBroken()
  }

  private getContentMaxWidth(): number {
    return getSettingsPageContentMaxWidth(this.layoutSizeClass, this.windowWidthVp, this.settingsDetailPresentationMode,
      this.windowHeightVp)
  }

  private isDetailPaneMode(): boolean {
    return this.settingsDetailPresentationMode === SettingsPagePresentationMode.DETAIL_PANE
  }

  private handleBack(): void {
    if (learningTomorrowPlanPagePathStack !== null && learningTomorrowPlanPagePathStack.size() > 0) {
      learningTomorrowPlanPagePathStack.pop()
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

  private getSnapshotAgeLabel(snapshot: ChildSnapshot): string {
    if (snapshot.ageYears > 0) {
      return `${snapshot.ageYears} 岁`
    }
    return ''
  }

  @Builder
  private CompactTitleStackBuilder() {
    SettingsCompactTitleBarContent({
      title: $r('app.string.learning_tomorrow_plan_title'),
      onBack: () => {
        this.handleBack()
      }
    })
  }

  @Builder
  private DetailPaneHeader() {
    Column() {
      Row() {
        Text($r('app.string.learning_tomorrow_plan_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        if (this.planDate !== '') {
          Text(this.planDate)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
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
  private SectionTitle(title: ResourceStr) {
    Text(title)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_secondary'))
      .padding({ left: 4, bottom: 6 })
      .width('100%')
  }

  @Builder
  private TextCard(title: ResourceStr, body: string) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
      Text(body !== '' ? body : '—')
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(22)
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.divider') })
    .visualEffect(buildPointLightBorderEffect())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ChildSnapshotCard(snapshot: ChildSnapshot) {
    Column({ space: 8 }) {
      Text($r('app.string.learning_section_child_snapshot'))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))

      Row({ space: 8 }) {
        if (snapshot.childName !== '') {
          Text(snapshot.childName)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        if (this.getSnapshotAgeLabel(snapshot) !== '') {
          Text(this.getSnapshotAgeLabel(snapshot))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      }

      if (snapshot.overallNote !== '') {
        Text(snapshot.overallNote)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(18)
          .width('100%')
      }

      if (snapshot.strongSkills.length > 0 || snapshot.weakSkills.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(snapshot.strongSkills, (key: string, index: number) => {
            Text(`擅长 · ${key}`)
              .fontSize(11)
              .fontColor(this.themePrimary)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(10)
              .backgroundColor(this.themePrimaryLight)
              .margin({ right: 6, bottom: 6 })
          }, (key: string, index: number) => `s_${index}_${key}`)

          ForEach(snapshot.weakSkills, (key: string, index: number) => {
            Text(`薄弱 · ${key}`)
              .fontSize(11)
              .fontColor('#B45309')
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(10)
              .backgroundColor('#FEF3C7')
              .margin({ right: 6, bottom: 6 })
          }, (key: string, index: number) => `w_${index}_${key}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.themeSurface)
    .borderRadius(16)
    .border({ width: 1, color: $r('app.color.divider') })
    .visualEffect(buildPointLightBorderEffect())
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private VocabRow(item: LessonPlanVocabItem) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(item.word !== '' ? item.word : '—')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        if (item.translation !== '') {
          Text(item.translation)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        Blank()
        if (item.difficultyHint !== '') {
          Text(item.difficultyHint)
            .fontSize(11)
            .fontColor(this.themePrimary)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
            .backgroundColor(this.themePrimaryLight)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (item.exampleSentence !== '') {
        Text(item.exampleSentence)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .lineHeight(18)
          .width('100%')
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 14, right: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private MathRow(item: LessonPlanMathItem) {
    Column({ space: 4 }) {
      Text(item.description !== '' ? item.description : '—')
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(20)
        .width('100%')
      if (item.dimension !== '') {
        Text(item.dimension)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 14, right: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private WritingRow(item: LessonPlanWritingItem) {
    Row({ space: 10 }) {
      Text(item.characterOrWord !== '' ? item.characterOrWord : '—')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(item.description !== '' ? item.description : '')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 14, right: 14 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private GeneralRow(item: LessonPlanGeneralItem) {
    Column({ space: 4 }) {
      Text(item.description !== '' ? item.description : '—')
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(20)
        .width('100%')
      if (item.dimension !== '') {
        Text(item.dimension)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10, left: 14, right: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private VocabSection() {
    Column({ space: 6 }) {
      this.SectionTitle($r('app.string.learning_section_vocab'))
      this.VocabBlock(this.plan)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private MathSection() {
    Column({ space: 6 }) {
      this.SectionTitle($r('app.string.learning_section_math'))
      this.MathBlock(this.plan)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private WritingSection() {
    Column({ space: 6 }) {
      this.SectionTitle($r('app.string.learning_section_writing'))
      this.WritingBlock(this.plan)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private GeneralSection() {
    Column({ space: 6 }) {
      this.SectionTitle($r('app.string.learning_section_general'))
      this.GeneralBlock(this.plan)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private VocabBlock(plan: LessonPlan) {
    if (plan.vocab.length === 0) {
      Column() {
        Text('—')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .padding(14)
      }
      .width('100%')
      .backgroundColor(this.themeSurface)
      .borderRadius(16)
      .clip(true)
      .border({ width: 1, color: $r('app.color.divider') })
      .visualEffect(buildPointLightBorderEffect())
    } else {
      Column() {
        ForEach(plan.vocab, (item: LessonPlanVocabItem, index: number) => {
          Column() {
            this.VocabRow(item)
            if (index < plan.vocab.length - 1) {
              Divider()
                .color($r('app.color.divider'))
                .margin({ left: 14, right: 14 })
            }
          }
        }, (item: LessonPlanVocabItem, index: number) => `v_${index}_${item.word}_${item.topicKey}`)
      }
      .width('100%')
    }
  }

  @Builder
  private MathBlock(plan: LessonPlan) {
    if (plan.math.length === 0) {
      Column() {
        Text('—')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .padding(14)
      }
      .width('100%')
      .backgroundColor(this.themeSurface)
      .borderRadius(16)
      .clip(true)
      .border({ width: 1, color: $r('app.color.divider') })
      .visualEffect(buildPointLightBorderEffect())
    } else {
      Column() {
        ForEach(plan.math, (item: LessonPlanMathItem, index: number) => {
          Column() {
            this.MathRow(item)
            if (index < plan.math.length - 1) {
              Divider()
                .color($r('app.color.divider'))
                .margin({ left: 14, right: 14 })
            }
          }
        }, (item: LessonPlanMathItem, index: number) => `m_${index}_${item.topicKey}`)
      }
      .width('100%')
    }
  }

  @Builder
  private WritingBlock(plan: LessonPlan) {
    if (plan.writing.length === 0) {
      Column() {
        Text('—')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .padding(14)
      }
      .width('100%')
      .backgroundColor(this.themeSurface)
      .borderRadius(16)
      .clip(true)
      .border({ width: 1, color: $r('app.color.divider') })
      .visualEffect(buildPointLightBorderEffect())
    } else {
      Column() {
        ForEach(plan.writing, (item: LessonPlanWritingItem, index: number) => {
          Column() {
            this.WritingRow(item)
            if (index < plan.writing.length - 1) {
              Divider()
                .color($r('app.color.divider'))
                .margin({ left: 14, right: 14 })
            }
          }
        }, (item: LessonPlanWritingItem, index: number) => `w_${index}_${item.characterOrWord}_${item.topicKey}`)
      }
      .width('100%')
    }
  }

  @Builder
  private GeneralBlock(plan: LessonPlan) {
    if (plan.generalKnowledge.length === 0) {
      Column() {
        Text('—')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .padding(14)
      }
      .width('100%')
      .backgroundColor(this.themeSurface)
      .borderRadius(16)
      .clip(true)
      .border({ width: 1, color: $r('app.color.divider') })
      .visualEffect(buildPointLightBorderEffect())
    } else {
      Column() {
        ForEach(plan.generalKnowledge, (item: LessonPlanGeneralItem, index: number) => {
          Column() {
            this.GeneralRow(item)
            if (index < plan.generalKnowledge.length - 1) {
              Divider()
                .color($r('app.color.divider'))
                .margin({ left: 14, right: 14 })
            }
          }
        }, (item: LessonPlanGeneralItem, index: number) => `g_${index}_${item.topicKey}`)
      }
      .width('100%')
    }
  }

  @Builder
  private EmptyState() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.calendar'))
        .fontSize(48)
        .fontColor([$r('app.color.text_tertiary')])
        .margin({ bottom: 4 })
      Text($r('app.string.learning_plan_empty_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
      Text($r('app.string.learning_plan_empty_desc'))
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })

      if (this.isGenerating) {
        Row({ space: 6 }) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(this.themePrimary)
          Text($r('app.string.learning_plan_generating'))
            .fontSize(13)
            .fontColor(this.themePrimary)
        }
        .padding({ top: 4 })
      } else if (this.status === LessonPlanStatus.FAILED) {
        // 失败: 显示重试按钮
        Text($r('app.string.learning_plan_generate_failed'))
          .fontSize(13)
          .fontColor('#FF9F43')
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .borderRadius(14)
          .backgroundColor('#FEF3C7')
          .margin({ top: 6 })
          .onClick(() => {
            void this.handleRefresh()
          })
      } else if (this.status !== LessonPlanStatus.DONE || this.isPlanBroken()) {
        // 缺计划 / pending / running: 提示用户可以手动触发
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(13)
            .fontColor([this.themePrimary])
          Text($r('app.string.learning_plan_refresh'))
            .fontSize(13)
            .fontColor(this.themePrimary)
        }
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .borderRadius(14)
        .backgroundColor(this.themePrimaryLight)
        .margin({ top: 6 })
        .onClick(() => {
          void this.handleRefresh()
        })
      }
    }
    .width('100%')
    .padding({ top: 48, bottom: 32 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private RecentRow(row: DailyLessonPlanRow) {
    Row({ space: 10 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.calendar'))
          .fontSize(14)
          .fontColor([this.themePrimary])
      }
      .width(28)
      .height(28)
      .borderRadius(14)
      .backgroundColor(this.themePrimaryLight)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 2 }) {
        Text(this.getRelativeDateLabel(row.planDate))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(row.planDate)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column() {
        if (row.status === LessonPlanStatus.DONE) {
          Text($r('app.string.learning_plan_status_done'))
            .fontSize(11)
            .fontColor('#22C55E')
        } else if (row.status === LessonPlanStatus.FAILED) {
          Text($r('app.string.learning_plan_status_failed'))
            .fontSize(11)
            .fontColor('#EF4444')
        } else {
          // pending / running
          Text($r('app.string.learning_plan_status_pending'))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
      }
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(10)
      .backgroundColor($r('app.color.surface'))

      // 已完成的行可点击展开, 用 chevron 指示状态
      if (row.status === LessonPlanStatus.DONE) {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(12)
          .fontColor([$r('app.color.text_tertiary')])
          .rotate({ angle: this.expandedDate === row.planDate ? 180 : 0 })
          .animation({ duration: 200, curve: Curve.EaseInOut })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.handlePastRowClick(row)
    })
  }

  @Builder
  private ExpandedPastPlanContent(plan: LessonPlan) {
    Column({ space: 12 }) {
      this.TextCard($r('app.string.learning_section_theme'), plan.themeTitle)

      if (plan.themeDescription !== '') {
        this.TextCard($r('app.string.learning_section_teacher_notes'), plan.themeDescription)
      }

      this.SectionTitle($r('app.string.learning_section_vocab'))
      this.VocabBlock(plan)

      this.SectionTitle($r('app.string.learning_section_math'))
      this.MathBlock(plan)

      this.SectionTitle($r('app.string.learning_section_writing'))
      this.WritingBlock(plan)

      this.SectionTitle($r('app.string.learning_section_general'))
      this.GeneralBlock(plan)
    }
    .width('100%')
    .padding({ top: 4, bottom: 12, left: 12, right: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private RecentPlansSection() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(13)
          .fontColor([$r('app.color.text_secondary')])
        Text($r('app.string.learning_plan_recent_plans'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ left: 4, bottom: 2 })
      .alignItems(VerticalAlign.Center)

      if (this.recentRows.length === 0) {
        Text($r('app.string.learning_plan_no_recent'))
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .padding(12)
      } else {
        Column() {
          ForEach(this.recentRows, (row: DailyLessonPlanRow, index: number) => {
            Column() {
              this.RecentRow(row)
              if (this.expandedDate === row.planDate) {
                this.ExpandedPastPlanContent(this.getPastPlan(row.planDate) ?? new LessonPlan())
              }
              if (index < this.recentRows.length - 1) {
                Divider()
                  .color($r('app.color.divider'))
                  .margin({ left: 50, right: 12 })
              }
            }
          }, (row: DailyLessonPlanRow) => `r_${row.id}_${row.planDate}`)
        }
        .width('100%')
        .backgroundColor(this.themeSurface)
        .borderRadius(16)
        .clip(true)
        .border({ width: 1, color: $r('app.color.divider') })
        .visualEffect(buildPointLightBorderEffect())
      }
    }
    .width('100%')
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

          if (this.isEmpty() && !this.isLoading) {
            this.EmptyState()
          } else {
            // 顶部刷新按钮: 完整 plan 隐藏 (避免误覆盖), 半残 plan (done+4 段全空) 仍可重新生成
            if (!this.isLoading && this.canRegenerate()) {
              Row() {
                Blank()
                Row({ space: 4 }) {
                  SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                    .fontSize(12)
                    .fontColor([this.isGenerating ? $r('app.color.text_tertiary') : this.themePrimary])
                  Text(this.isGenerating ? $r('app.string.learning_plan_generating') : $r('app.string.learning_plan_refresh'))
                    .fontSize(12)
                    .fontColor(this.isGenerating ? $r('app.color.text_tertiary') : this.themePrimary)
                }
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(12)
                .backgroundColor(this.themePrimaryLight)
                .opacity(this.isGenerating ? 0.5 : 1)
                .onClick(() => {
                  if (!this.isGenerating) {
                    void this.handleRefresh()
                  }
                })
              }
              .width('100%')
              .margin({ bottom: 8 })
            }
            this.TextCard($r('app.string.learning_section_theme'), this.plan.themeTitle)
            if (this.plan.themeDescription !== '') {
              Column() {
                this.TextCard($r('app.string.learning_section_teacher_notes'), this.plan.themeDescription)
              }
              .width('100%')
              .margin({ top: 14 })
              .alignItems(HorizontalAlign.Start)
            }

            if (this.plan.teacherNotes !== '') {
              Column() {
                this.TextCard($r('app.string.learning_section_teacher_notes'), this.plan.teacherNotes)
              }
              .width('100%')
              .margin({ top: 14 })
              .alignItems(HorizontalAlign.Start)
            }

            Column() {
              this.ChildSnapshotCard(this.plan.childSnapshot)
            }
            .width('100%')
            .margin({ top: 14 })
            .alignItems(HorizontalAlign.Start)

            this.VocabSection()

            Column() {
              this.MathSection()
            }
            .width('100%')
            .margin({ top: 14 })
            .alignItems(HorizontalAlign.Start)

            Column() {
              this.WritingSection()
            }
            .width('100%')
            .margin({ top: 14 })
            .alignItems(HorizontalAlign.Start)

            Column() {
              this.GeneralSection()
            }
            .width('100%')
            .margin({ top: 14 })
            .alignItems(HorizontalAlign.Start)
          }

          // 过去 7 天 (始终展示, 独立于今日是否有 plan)
          Column() {
            this.RecentPlansSection()
          }
          .width('100%')
          .margin({ top: 24 })
          .alignItems(HorizontalAlign.Start)

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
export function LearningTomorrowPlanPageBuilder(name: string, param: Object) {
  NavDestination() {
    LearningTomorrowPlanPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    learningTomorrowPlanPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (learningTomorrowPlanPagePathStack !== null && learningTomorrowPlanPagePathStack.size() > 0) {
      learningTomorrowPlanPagePathStack.pop()
    }
    return true
  })
}
