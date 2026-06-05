/**
 * TodayStarDetailSheet - 今日小明星详情面板
 *
 * 位置: ChatPage 的 bindSheet 内容
 * 作用: 展示分类汇总(数学/英语/华容道)+ 今日明细(每条事件一行)
 *
 * v2 视觉升级 (2026-06-04):
 * - 顶部 hero block: 40×40 圆角 icon well (STAR_SUCCESS_GREEN bg) + 32vp Bold 总数
 * - 三个分类块改用 UsageMetricCard 比例 (28×28 icon well + 22vp Bold 数字)
 * - granted pill 用 STAR_SUCCESS_GREEN 背景 + 白字
 * - empty state 用 48vp SymbolGlyph 插画 + 16vp 标题 + 13vp 描述
 * - 容器加 visualEffect(buildPointLightBorderEffect()), 沿用 UsageStatsPage 灯光效果
 *
 * 数据源:
 * - 分类汇总: AppUiState.starTodaySummary (顶层状态, 来自 recordEvent 同步)
 * - 明细列表: 直接调 service.getTodayEvents() 拉, 在 aboutToAppear 与 starEarnedTick 变化时刷新
 */

import { getAppUiState, observeAppUiState } from '../../state/AppUiState'
import { AppStorageKeys } from '../../config/AppStorageKeys'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { buildPointLightBorderEffect } from '../../utils/HdsVisualEffectUtil'
import {
  formatYMD,
  getIsoWeekday,
  getStartOfMonthMs,
  WEEKDAY_SHORT_LABELS_ZH
} from '../../utils/DateFormatUtils'
import {
  StarActivityType,
  StarEventRow,
  StarTypeBucket,
  TodayStarSummary,
  createEmptyTodayStarSummary,
  STAR_ACTIVITY_TYPES,
  STAR_SUCCESS_GREEN,
  getActivityMeta,
  getActivitySymbol,
  getBucketFromSummary,
  getTodayStarHeaderSymbol
} from '../../models/StarEventModels'
import { getStarRewardService, StarRewardService } from '../../services/StarRewardService'

interface CategoryRow {
  symbolResource: Resource
  label: string
  unit: string
  bucket: StarTypeBucket
  activityType: StarActivityType
}

interface DetailRowData {
  event: StarEventRow
  timeText: string
  description: string
  starsText: string
  isGranted: boolean
}

interface CalendarDayCell {
  date: string          // YYYY-MM-DD
  dayOfMonth: number    // 1-31
  isCurrentMonth: boolean
  isToday: boolean
  starCount: number     // 当日 +stars
}

@ComponentV2
export struct TodayStarDetailSheet {
  @Local events: StarEventRow[] = []
  @Local hasLoaded: boolean = false
  @Local viewMode: 'today' | 'calendar' = 'today'
  @Local calendarYear: number = new Date().getFullYear()
  @Local calendarMonth: number = new Date().getMonth() + 1
  @Local calendarDayCells: CalendarDayCell[] = []
  @Local calendarMonthTotal: number = 0
  @Local calendarAllTimeTotal: number = 0
  @Local calendarSelectedDate: string = ''
  @Local calendarSelectedDayEvents: StarEventRow[] = []
  @Local calendarHasLoaded: boolean = false
  private service: StarRewardService = getStarRewardService()
  private unsubscribe: (() => void) | null = null

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

  private get themeAiBubble(): string {
    return getAppUiState().themeAiBubble
  }

  private get themeTextPrimary(): string {
    return getAppUiState().themeTextPrimary
  }

  private get themeTextSecondary(): string {
    return getAppUiState().themeTextSecondary
  }

  private get themeTextTertiary(): string {
    return getAppUiState().themeTextTertiary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get todaySummary(): TodayStarSummary {
    const json = getAppUiState().starTodaySummary
    if (json === '') {
      return createEmptyTodayStarSummary()
    }
    try {
      return JSON.parse(json) as TodayStarSummary
    } catch (_e) {
      return createEmptyTodayStarSummary()
    }
  }

  aboutToAppear(): void {
    void this.refresh()
    this.unsubscribe = observeAppUiState(AppStorageKeys.STAR_EARNED_TICK, (): void => {
      void this.refresh()
      if (this.viewMode === 'calendar') {
        void this.loadCalendarData()
        if (this.calendarSelectedDate !== '') {
          void this.loadCalendarDayDetail(this.calendarSelectedDate)
        }
      }
    })
  }

  aboutToDisappear(): void {
    if (this.unsubscribe !== null) {
      this.unsubscribe()
      this.unsubscribe = null
    }
  }

  private async refresh(): Promise<void> {
    try {
      const events = await this.service.getTodayEvents()
      this.events = events
      this.hasLoaded = true
    } catch (error) {
      console.error('TodayStarDetailSheet', `refresh failed: ${JSON.stringify(error)}`)
      this.events = []
      this.hasLoaded = true
    }
  }

  private async switchViewMode(mode: 'today' | 'calendar'): Promise<void> {
    if (this.viewMode === mode) {
      return
    }
    this.viewMode = mode
    if (mode === 'calendar' && !this.calendarHasLoaded) {
      await this.loadCalendarData()
    }
  }

  private async loadCalendarData(): Promise<void> {
    try {
      const monthResult = await Promise.all([
        this.service.getMonthStarEvents(this.calendarYear, this.calendarMonth),
        this.service.getAllTimeStarTotal()
      ])
      const monthEvents = monthResult[0]
      const allTimeTotal = monthResult[1]
      // 按 YMD 分桶聚合 +stars
      const bucket: Map<string, number> = new Map()
      let monthTotal = 0
      for (let i = 0; i < monthEvents.length; i++) {
        const ev = monthEvents[i]
        if (ev.stars <= 0) {
          continue
        }
        const key = formatYMD(ev.createdAt)
        bucket.set(key, (bucket.get(key) ?? 0) + ev.stars)
        monthTotal += ev.stars
      }
      this.calendarDayCells = this.buildCalendarCells(this.calendarYear, this.calendarMonth, bucket)
      this.calendarMonthTotal = monthTotal
      this.calendarAllTimeTotal = allTimeTotal
      this.calendarHasLoaded = true
      // 校验当前选中日期是否还在可视月份内, 不在则清
      if (this.calendarSelectedDate !== '') {
        const selected = this.calendarSelectedDate
        const inView = this.calendarDayCells.some((c: CalendarDayCell): boolean => c.date === selected)
        if (!inView) {
          this.calendarSelectedDate = ''
          this.calendarSelectedDayEvents = []
        }
      }
    } catch (error) {
      console.error('TodayStarDetailSheet', `loadCalendarData failed: ${JSON.stringify(error)}`)
      this.calendarDayCells = []
      this.calendarMonthTotal = 0
      this.calendarHasLoaded = true
    }
  }

  private buildCalendarCells(year: number, month: number, starBucket: Map<string, number>): CalendarDayCell[] {
    const cells: CalendarDayCell[] = []
    const firstOfMonth = getStartOfMonthMs(year, month)
    const firstWeekday = getIsoWeekday(firstOfMonth) // 周一=0
    // 前置: 上月末尾 days
    const prevMonthEnd = new Date(year, month - 1, 0) // month-1 传 0 → 上月最后一天
    const prevDaysInMonth = prevMonthEnd.getDate()
    for (let i = firstWeekday - 1; i >= 0; i--) {
      const d = new Date(prevMonthEnd.getTime())
      d.setDate(prevDaysInMonth - i)
      const ms = d.getTime()
      cells.push(this.makeCell(ms, false, starBucket))
    }
    // 当月
    const daysInMonth = new Date(year, month, 0).getDate()
    for (let day = 1; day <= daysInMonth; day++) {
      const ms = new Date(year, month - 1, day, 0, 0, 0, 0).getTime()
      cells.push(this.makeCell(ms, true, starBucket))
    }
    // 后置: 补齐到 6 行 × 7 列 = 42
    while (cells.length < 42) {
      const last = cells[cells.length - 1]
      const d = new Date(this.parseCellDateMs(last.date))
      d.setDate(d.getDate() + 1)
      cells.push(this.makeCell(d.getTime(), false, starBucket))
    }
    return cells
  }

  private makeCell(ms: number, isCurrentMonth: boolean, starBucket: Map<string, number>): CalendarDayCell {
    const d = new Date(ms)
    const today = new Date()
    const isToday = d.getFullYear() === today.getFullYear() &&
      d.getMonth() === today.getMonth() &&
      d.getDate() === today.getDate()
    const key = formatYMD(ms)
    return {
      date: key,
      dayOfMonth: d.getDate(),
      isCurrentMonth: isCurrentMonth,
      isToday: isToday,
      starCount: starBucket.get(key) ?? 0
    }
  }

  private parseCellDateMs(ymd: string): number {
    // YYYY-MM-DD 解析为本地 0 点
    const parts = ymd.split('-')
    const y = Number(parts[0])
    const m = Number(parts[1])
    const d = Number(parts[2])
    return new Date(y, m - 1, d, 0, 0, 0, 0).getTime()
  }

  private async goToPrevMonth(): Promise<void> {
    let y = this.calendarYear
    let m = this.calendarMonth - 1
    if (m < 1) {
      m = 12
      y = y - 1
    }
    this.calendarYear = y
    this.calendarMonth = m
    await this.loadCalendarData()
  }

  private async goToNextMonth(): Promise<void> {
    let y = this.calendarYear
    let m = this.calendarMonth + 1
    if (m > 12) {
      m = 1
      y = y + 1
    }
    this.calendarYear = y
    this.calendarMonth = m
    await this.loadCalendarData()
  }

  private async handleCalendarDayTap(date: string): Promise<void> {
    if (this.calendarSelectedDate === date) {
      // 再点同一格: 收起
      this.calendarSelectedDate = ''
      this.calendarSelectedDayEvents = []
      return
    }
    this.calendarSelectedDate = date
    await this.loadCalendarDayDetail(date)
  }

  private async loadCalendarDayDetail(date: string): Promise<void> {
    try {
      // 从月份事件中过滤; 月级查询已加载, 复用即可
      const monthEvents = await this.service.getMonthStarEvents(this.calendarYear, this.calendarMonth)
      const filtered: StarEventRow[] = []
      for (let i = 0; i < monthEvents.length; i++) {
        if (formatYMD(monthEvents[i].createdAt) === date) {
          filtered.push(monthEvents[i])
        }
      }
      this.calendarSelectedDayEvents = filtered
    } catch (error) {
      console.error('TodayStarDetailSheet', `loadCalendarDayDetail failed: ${JSON.stringify(error)}`)
      this.calendarSelectedDayEvents = []
    }
  }

  private closeCalendarDayDetail(): void {
    this.calendarSelectedDate = ''
    this.calendarSelectedDayEvents = []
  }

  private get chipBackgroundColor(): string {
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '18') : withColorAlpha(this.themePrimary, '12')
  }

  private formatTime(ms: number): string {
    const date = new Date(ms)
    const h = date.getHours().toString().padStart(2, '0')
    const m = date.getMinutes().toString().padStart(2, '0')
    return `${h}:${m}`
  }

  private describeEvent(event: StarEventRow): string {
    const type = event.activityType as StarActivityType
    if (type !== 'math_quiz' && type !== 'english_quiz' && type !== 'number_puzzle') {
      return '未知活动'
    }
    const meta = getActivityMeta(type)
    if (event.stars > 0) {
      return meta.grantedHint
    }
    return `${meta.longLabel}${type === 'number_puzzle' ? '放弃' : '答错'}`
  }

  private buildDetailRows(): DetailRowData[] {
    const rows: DetailRowData[] = []
    for (let i = 0; i < this.events.length; i++) {
      const event = this.events[i]
      const isGranted = event.stars > 0
      rows.push({
        event: event,
        timeText: this.formatTime(event.createdAt),
        description: this.describeEvent(event),
        starsText: isGranted ? `+${event.stars} ⭐` : '尝试',
        isGranted: isGranted
      })
    }
    return rows
  }

  private buildCategoryRows(): CategoryRow[] {
    const summary = this.todaySummary
    const rows: CategoryRow[] = []
    for (let i = 0; i < STAR_ACTIVITY_TYPES.length; i++) {
      const type = STAR_ACTIVITY_TYPES[i]
      const meta = getActivityMeta(type)
      const bucket: StarTypeBucket = getBucketFromSummary(summary, type)
      rows.push({
        symbolResource: getActivitySymbol(type),
        label: meta.longLabel,
        unit: meta.unit,
        bucket: bucket,
        activityType: type
      })
    }
    return rows
  }

  @Builder
  private CategoryRow(row: CategoryRow) {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph(row.symbolResource)
          .fontSize(16)
          .fontColor([this.themePrimary])
      }
      .width(28)
      .height(28)
      .borderRadius(9)
      .backgroundColor(this.themePrimaryLight)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Column({ space: 2 }) {
        Text(row.label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themeTextPrimary)
        Text(`${row.bucket.count} ${row.unit}`)
          .fontSize(11)
          .fontColor(this.themeTextTertiary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(`${row.bucket.stars}`)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(STAR_SUCCESS_GREEN)
      Text('颗')
        .fontSize(12)
        .fontColor(this.themeTextSecondary)
        .margin({ left: 2 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.chipBackgroundColor)
    .borderRadius(12)
  }

  @Builder
  private DetailRow(row: DetailRowData) {
    Row() {
      Text(row.timeText)
        .fontSize(11)
        .fontColor(this.themeTextTertiary)
        .width(42)
      Text(row.description)
        .fontSize(13)
        .fontColor(this.themeTextPrimary)
        .layoutWeight(1)
        .margin({ left: 8 })
      if (row.isGranted) {
        Text(row.starsText)
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(STAR_SUCCESS_GREEN)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
      } else {
        Text(row.starsText)
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themeTextTertiary)
          .backgroundColor(withColorAlpha(this.themeTextTertiary, '14'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
      }
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  // ========== 日历视图 (v3, 2026-06-05) ==========

  private buildCalendarDayDetailRows(): DetailRowData[] {
    const rows: DetailRowData[] = []
    for (let i = 0; i < this.calendarSelectedDayEvents.length; i++) {
      const event = this.calendarSelectedDayEvents[i]
      const isGranted = event.stars > 0
      rows.push({
        event: event,
        timeText: this.formatTime(event.createdAt),
        description: this.describeEvent(event),
        starsText: isGranted ? `+${event.stars} ⭐` : '尝试',
        isGranted: isGranted
      })
    }
    return rows
  }

  private getCellBackgroundColor(cell: CalendarDayCell): ResourceColor {
    if (cell.isToday && this.calendarSelectedDate === cell.date) {
      return withColorAlpha(this.themePrimary, '1F')
    }
    if (cell.isToday) {
      return withColorAlpha(this.themePrimary, '14')
    }
    if (this.calendarSelectedDate === cell.date) {
      return withColorAlpha(this.themePrimary, '10')
    }
    if (cell.starCount > 0) {
      return withColorAlpha(STAR_SUCCESS_GREEN, '0C')
    }
    return Color.Transparent
  }

  private getCellBorderColor(cell: CalendarDayCell): ResourceColor {
    if (this.calendarSelectedDate === cell.date) {
      return this.themePrimary
    }
    if (cell.isToday) {
      return withColorAlpha(this.themePrimary, '50')
    }
    return Color.Transparent
  }

  private getCellBorderWidth(cell: CalendarDayCell): number {
    if (this.calendarSelectedDate === cell.date) {
      return 1.5
    }
    if (cell.isToday) {
      return 0.5
    }
    return 0
  }

  private formatMonthLabel(year: number, month: number): string {
    return `${year} 年 ${month} 月`
  }

  private formatSelectedDateLabel(ymd: string): string {
    if (ymd === '') {
      return ''
    }
    const parts = ymd.split('-')
    return `${Number(parts[1])} 月 ${Number(parts[2])} 日`
  }

  @Builder
  private ViewTabButton(label: Resource, isActive: boolean, onTap: () => void) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(15)
        .fontWeight(isActive ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(isActive ? this.themeTextPrimary : this.themeTextTertiary)
      Row()
        .width(isActive ? 24 : 14)
        .height(3)
        .borderRadius(2)
        .backgroundColor(isActive ? this.themePrimary : Color.Transparent)
    }
    .padding({ top: 4, bottom: 8 })
    .onClick((): void => { onTap() })
  }

  @Builder
  private ViewTabs() {
    Row() {
      this.ViewTabButton($r('app.string.star_calendar_view_today'), this.viewMode === 'today', (): void => {
        void this.switchViewMode('today')
      })
      Blank()
      this.ViewTabButton($r('app.string.star_calendar_view_calendar'), this.viewMode === 'calendar', (): void => {
        void this.switchViewMode('calendar')
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 4 })
  }

  @Builder
  private CalendarHeader() {
    Column({ space: 8 }) {
      // 累计 hero
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.star_fill'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(40)
        .height(40)
        .borderRadius(12)
        .backgroundColor(STAR_SUCCESS_GREEN)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)

        Column({ space: 2 }) {
          Row({ space: 4 }) {
            Text(`${this.calendarAllTimeTotal}`)
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.themeTextPrimary)
            Text('颗')
              .fontSize(14)
              .fontColor(this.themeTextSecondary)
              .margin({ top: 12 })
          }
          .alignItems(VerticalAlign.Bottom)

          Text($r('app.string.star_calendar_cumulative_label'))
            .fontSize(13)
            .fontColor(this.themeTextSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 8 })

      // 月份导航 + 本月小计
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(18)
          .fontColor([this.themeTextSecondary])
          .padding(8)
          .accessibilityText($r('app.string.star_calendar_prev_month'))
          .onClick((): void => { void this.goToPrevMonth() })

        Text(this.formatMonthLabel(this.calendarYear, this.calendarMonth))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themeTextPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(18)
          .fontColor([this.themeTextSecondary])
          .padding(8)
          .accessibilityText($r('app.string.star_calendar_next_month'))
          .onClick((): void => { void this.goToNextMonth() })
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 4, bottom: 0 })

      // 本月小计行
      Row({ space: 6 }) {
        Text($r('app.string.star_calendar_month_total_label'))
          .fontSize(11)
          .fontColor(this.themeTextTertiary)
        Text(`${this.calendarMonthTotal}`)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(STAR_SUCCESS_GREEN)
        Text('颗')
          .fontSize(11)
          .fontColor(this.themeTextTertiary)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ top: 0, bottom: 8 })
    }
    .width('100%')
  }

  @Builder
  private CalendarWeekdayHeader() {
    Row() {
      ForEach(WEEKDAY_SHORT_LABELS_ZH, (label: string): void => {
        Text(label)
          .fontSize(11)
          .fontColor(this.themeTextTertiary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
      }, (label: string): string => label)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
  }

  @Builder
  private CalendarDayCellView(cell: CalendarDayCell) {
    Column({ space: 2 }) {
      Text(`${cell.dayOfMonth}`)
        .fontSize(13)
        .fontColor(cell.isCurrentMonth ? this.themeTextPrimary : this.themeTextTertiary)
        .fontWeight(cell.isToday ? FontWeight.Bold : FontWeight.Normal)
      if (cell.starCount > 0) {
        Row({ space: 1 }) {
          Text(`${cell.starCount}`)
            .fontSize(9)
            .fontColor(STAR_SUCCESS_GREEN)
            .fontWeight(FontWeight.Medium)
          Text('⭐')
            .fontSize(8)
        }
      } else {
        Text(' ')
          .fontSize(9)
      }
    }
    .width('100%')
    .height(46)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(10)
    .backgroundColor(this.getCellBackgroundColor(cell))
    .border({
      width: this.getCellBorderWidth(cell),
      color: this.getCellBorderColor(cell)
    })
    .onClick((): void => { void this.handleCalendarDayTap(cell.date) })
  }

  @Builder
  private CalendarGrid() {
    if (!this.calendarHasLoaded) {
      Row() {
        Text('加载中...')
          .fontSize(12)
          .fontColor(this.themeTextTertiary)
      }
      .width('100%')
      .padding({ top: 24, bottom: 24 })
      .justifyContent(FlexAlign.Center)
    } else {
      Grid() {
        ForEach(this.calendarDayCells, (cell: CalendarDayCell): void => {
          GridItem() {
            this.CalendarDayCellView(cell)
          }
        }, (cell: CalendarDayCell): string => cell.date)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .rowsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
      .columnsGap(4)
      .rowsGap(4)
      .width('100%')
      .height(310)  // 6 × 46 + 5 × 4(gap)
      .padding({ left: 8, right: 8 })
    }
  }

  @Builder
  private CalendarDayDetail() {
    if (this.calendarSelectedDate !== '') {
      Column() {
        Row() {
          Text(this.formatSelectedDateLabel(this.calendarSelectedDate))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themeTextPrimary)
          Blank()
          Text(`共 ${this.calendarSelectedDayEvents.length} 条`)
            .fontSize(11)
            .fontColor(this.themeTextTertiary)
          Text(' · ')
            .fontSize(11)
            .fontColor(this.themeTextTertiary)
          Text($r('app.string.star_calendar_close_day_detail'))
            .fontSize(11)
            .fontColor(this.themePrimary)
            .onClick((): void => { this.closeCalendarDayDetail() })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 4 })

        if (this.calendarSelectedDayEvents.length === 0) {
          Column({ space: 4 }) {
            Text($r('app.string.star_calendar_empty_day'))
              .fontSize(13)
              .fontColor(this.themeTextTertiary)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 16, bottom: 16 })
        } else {
          Column() {
            ForEach(this.buildCalendarDayDetailRows(), (row: DetailRowData): void => {
              this.DetailRow(row)
            }, (row: DetailRowData): string => `${row.event.id}`)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
      }
      .width('100%')
    }
  }

  @Builder
  private CalendarView() {
    Column({ space: 0 }) {
      this.CalendarHeader()
      this.CalendarWeekdayHeader()
      this.CalendarGrid()
      this.CalendarDayDetail()
    }
    .width('100%')
  }

  build() {
    Column() {
      // Hero block: 40×40 圆角 icon well + 32vp Bold 总数
      Row() {
        Row() {
          SymbolGlyph(getTodayStarHeaderSymbol())
            .fontSize(20)
            .fontColor([Color.White])
        }
        .width(40)
        .height(40)
        .borderRadius(12)
        .backgroundColor(STAR_SUCCESS_GREEN)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)

        Column({ space: 2 }) {
          Row({ space: 4 }) {
            Text(`${this.todaySummary.total}`)
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.themeTextPrimary)
            Text('颗')
              .fontSize(14)
              .fontColor(this.themeTextSecondary)
              .margin({ top: 12 })
          }
          .alignItems(VerticalAlign.Bottom)

          Text('今日获得')
            .fontSize(13)
            .fontColor(this.themeTextSecondary)
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 24, bottom: 16 })

      // 视图分段: 今日 / 日历
      this.ViewTabs()

      if (this.viewMode === 'today') {
        // 分类汇总
        Column({ space: 8 }) {
          ForEach(this.buildCategoryRows(), (row: CategoryRow): void => {
            this.CategoryRow(row)
          }, (row: CategoryRow): string => row.activityType)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 12 })

        // 分割线
        Row()
          .width('100%')
          .height(1)
          .backgroundColor($r('app.color.divider'))

        // 明细标题
        Row() {
          Text('今日明细')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themeTextPrimary)
          Blank()
          Text(`共 ${this.events.length} 条`)
            .fontSize(11)
            .fontColor(this.themeTextTertiary)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

        // 明细列表
        if (!this.hasLoaded) {
          Row() {
            Text('加载中...')
              .fontSize(12)
              .fontColor(this.themeTextTertiary)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        } else if (this.events.length === 0) {
          Column({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(48)
              .fontColor([this.themeTextTertiary])
            Text('今天还没有记录')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themeTextSecondary)
            Text('完成一道题或华容道开始吧')
              .fontSize(13)
              .fontColor(this.themeTextTertiary)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 16, right: 16, top: 48, bottom: 48 })
        } else {
          Column() {
            ForEach(this.buildDetailRows(), (row: DetailRowData): void => {
              this.DetailRow(row)
            }, (row: DetailRowData): string => `${row.event.id}`)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
      } else {
        // 日历视图
        this.CalendarView()
      }

      Blank()
    }
    .width('100%')
    .height('70%')
    .backgroundColor(this.themeSurface)
    .borderRadius({ topLeft: 28, topRight: 28 })
    .visualEffect(buildPointLightBorderEffect())
  }
}
