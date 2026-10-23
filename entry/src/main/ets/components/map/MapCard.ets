// entry/src/main/ets/components/map/MapCard.ets
/**
 * MapCard - 中国地图小课堂（map_card 工具，讲解型回执）
 *
 * 视觉取自 map-card-redesign.html：暖纸质地图册。
 * - 大尺寸（全屏 sheet）：自绘表头（地理 · 小课堂 / 已探索 N/34）+ 地图册卡
 *   （纸质网格底 + 指北针 + 图例 + 南海诸岛题注 + 页脚缩放簇）+ 省份资料卡
 *   （简称印章 + 大区标签 + 行政中心 + 听一听 + 小星老师说）+ 进度行 + 主按钮。
 * - 小尺寸（时间线内联复原）：CardShell 外壳 + 紧凑地图 + 资料卡 + 状态行。
 *
 * 交互语义沿用既有定案：focus 省自动展示、点省即读 TTS（🔊/听一听 作重播）、
 * 「我学会了 · 继续」提交回执；讲解课不授星（2026-10-22 定案）。
 * 探索过的省份留「已探索」底色，可一眼看出这节课认识了几个地方。
 */

import common from '@ohos.app.ability.common'
import { getAppUiState } from '../../state/AppUiState'
import { ToolCall } from '../../models/ChatModels'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { ServiceRegistry } from '../../services/ServiceRegistry'
import { ChinaMapData, ChinaProvince, findProvinceByRef, loadChinaMapData } from '../../utils/ChinaMapData'
import { buildExploreProgressText, buildTeacherNote } from '../../utils/MapAtlasCopy'
import { CardShell } from '../cardshell/CardShell'
import { CardShellConfig } from '../cardshell/CardShellTypes'
import { CardShellState } from '../cardshell/CardShellState'
import { getMapAtlasPalette, MapAtlasPalette } from './MapAtlasTokens'
import { ChinaMapStage } from './ChinaMapStage'
import { ChinaMapStageController } from './ChinaMapStageController'
import { MapZoomCluster } from './MapZoomCluster'

export interface MapCardResult {
  completed: boolean
  focus_province: string
  explored_count: number
  skill_key: string
}

export interface MapCardArgsView {
  valid: boolean
  focusProvince: string
  skillKey: string
}

/** 34 个省级行政区；数据未加载时的兜底分母 */
const DEFAULT_PROVINCE_TOTAL: number = 34

function createDefaultArgsView(): MapCardArgsView {
  const view: MapCardArgsView = { valid: false, focusProvince: '', skillKey: 'general_social' }
  return view
}

export function parseMapCardArgs(raw: string): MapCardArgsView {
  const view: MapCardArgsView = createDefaultArgsView()
  try {
    const obj = JSON.parse(raw) as Record<string, Object>
    view.valid = true
    const focus: Object | undefined = obj['focus_province']
    if (typeof focus === 'string') {
      view.focusProvince = (focus as string).trim()
    }
    const skill: Object | undefined = obj['skill_key']
    if (typeof skill === 'string' && (skill as string).trim() !== '') {
      view.skillKey = (skill as string).trim()
    }
  } catch (_e) {
    return createDefaultArgsView()
  }
  return view
}

@ComponentV2
export struct MapCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
  @Event onRequestClose: () => void = () => {}

  @Local argsView: MapCardArgsView = createDefaultArgsView()
  @Local data: ChinaMapData | null = null
  @Local selectedId: string = ''
  /** 探索过的省份（含 focus），只增不减——地图上留「已探索」底色 */
  @Local visitedIds: string[] = []
  @Local currentInfo: ChinaProvince | null = null
  @Local provinceTotal: number = DEFAULT_PROVINCE_TOTAL
  @Local noteText: string = ''
  @Local isSpeaking: boolean = false
  @Local listenLabel: string = '听一听'
  @Local submitDone: boolean = false
  @Local hasCompleted: boolean = false
  @Local sealScale: number = 1

  /** 内联复原时从历史 payload 读回：focus 省 + 已认识数量 */
  private restoredFocusRef: string = ''
  private restoredExplored: number = 0
  /** 朗读序号：连续点省时旧回调不覆盖新一次「朗读中」状态 */
  private speakSeq: number = 0
  private shellState: CardShellState = new CardShellState()
  private shellConfig: CardShellConfig = {
    title: '中国地图小课堂', subtitle: '点一点省份，认识全中国', icon: $r('sys.symbol.map'),
    stem: '', hasAudio: false, usesConfirm: false,
    feedbackTitleCorrect: '学完啦！', correctAnswerLabel: ''
  }
  private mapController: ChinaMapStageController = new ChinaMapStageController()

  private get palette(): MapAtlasPalette {
    return getMapAtlasPalette(this.isDarkMode)
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  /** 矮屏判断：给地图让位，收起老师留言行 */
  private get compactHeight(): boolean {
    const height = getAppUiState().windowHeightVp
    return height > 0 && height < 720
  }

  aboutToAppear(): void {
    this.argsView = parseMapCardArgs(this.toolCall.arguments)
    this.shellState.feedbackSuppressed = true
    if (this.argsView.focusProvince !== '') {
      this.shellConfig.subtitle = `今天认识「${this.argsView.focusProvince}」`
    }
    if (this.isAnswered) {
      this.restoreFromPayload()
    }
    const ctx = getContext(this) as common.UIAbilityContext
    loadChinaMapData(ctx).then((loaded: ChinaMapData | null) => {
      if (loaded === null) {
        return
      }
      this.data = loaded
      this.provinceTotal = loaded.provinces.length
      this.applyInitialSelection(loaded)
    }).catch((_e: Error) => {
    })
  }

  aboutToDisappear(): void {
    this.stopSpeech()
  }

  // ====== 状态 ======

  private restoreFromPayload(): void {
    try {
      const prev = JSON.parse(this.answeredPayload) as Record<string, Object>
      this.hasCompleted = prev['completed'] === true
      const focus: Object | undefined = prev['focus_province']
      if (typeof focus === 'string') {
        this.restoredFocusRef = (focus as string).trim()
      }
      const count: Object | undefined = prev['explored_count']
      if (typeof count === 'number') {
        this.restoredExplored = count as number
      }
    } catch (_e) {
      this.hasCompleted = false
    }
  }

  private applyInitialSelection(data: ChinaMapData): void {
    const ref = this.restoredFocusRef !== '' ? this.restoredFocusRef : this.argsView.focusProvince
    if (ref === '') {
      return
    }
    const focus = findProvinceByRef(data.provinces, ref)
    if (focus === null) {
      return
    }
    this.selectedId = focus.id
    this.currentInfo = focus
    this.noteText = buildTeacherNote(focus)
    this.markVisited(focus.id)
  }

  private markVisited(provinceId: string): void {
    if (provinceId === '' || this.visitedIds.includes(provinceId)) {
      return
    }
    const next: string[] = this.visitedIds.slice()
    next.push(provinceId)
    this.visitedIds = next
  }

  private exploredCount(): number {
    return Math.max(this.visitedIds.length, this.restoredExplored)
  }

  private canSubmit(): boolean {
    return !this.isAnswered && !this.submitDone && this.exploredCount() > 0
  }

  /** 已学会（历史复原且 completed=true，或本次刚提交）——页脚切到完成态 */
  private isFinished(): boolean {
    return this.submitDone || this.hasCompleted
  }

  /** 历史复原但当年是放弃/取消收场 */
  private isCancelled(): boolean {
    return this.isAnswered && !this.isFinished()
  }

  private stampIn(): void {
    // 先落到小尺寸再下一帧弹回，避开同帧赋值被合并（设计稿 stamp-in）
    this.sealScale = 0.88
    const uiContext = this.getUIContext()
    setTimeout((): void => {
      uiContext.animateTo({ duration: 200, curve: Curve.EaseOut }, (): void => {
        this.sealScale = 1
      })
    }, 16)
  }

  // ====== 点选 / 朗读 ======

  private handlePickProvince(provinceId: string): void {
    if (this.isAnswered || this.submitDone || this.data === null) {
      return
    }
    let picked: ChinaProvince | null = null
    for (const p of this.data.provinces) {
      if (p.id === provinceId) {
        picked = p
        break
      }
    }
    if (picked === null) {
      return
    }
    this.selectedId = provinceId
    this.currentInfo = picked
    this.noteText = buildTeacherNote(picked)
    this.markVisited(provinceId)
    this.stampIn()
    // 点省即读：资料卡展示的同时直接 TTS 播报，「听一听」保留作重播
    this.speakProvinceInfo()
  }

  private speakProvinceInfo(): void {
    const info = this.currentInfo
    if (info === null) {
      return
    }
    this.stopSpeech()
    this.speakSeq = this.speakSeq + 1
    const seq = this.speakSeq
    this.isSpeaking = true
    this.listenLabel = '朗读中'
    ServiceRegistry.tts().speak(`${info.name}。简称${info.abbr}。行政中心${info.capital}。`, {
      onStart: () => {},
      onComplete: () => {
        if (seq !== this.speakSeq) {
          return // 已被下一次朗读接管，旧回调不覆盖按钮状态
        }
        this.isSpeaking = false
        this.listenLabel = '再听'
      },
      onError: (error: string) => {
        if (seq !== this.speakSeq) {
          return
        }
        this.isSpeaking = false
        this.listenLabel = '再听'
        console.error('MapCard', `province info TTS error: ${error}`)
      }
    }).catch((e: Error) => {
      if (seq !== this.speakSeq) {
        return
      }
      this.isSpeaking = false
      this.listenLabel = '再听'
      console.error('MapCard', `province info TTS speak failed: ${e.message}`)
    })
  }

  private stopSpeech(): void {
    this.isSpeaking = false
    this.listenLabel = '再听'
    try {
      ServiceRegistry.tts().stop()
    } catch (_e) {
    }
  }

  // ====== 提交 ======

  private submit(): void {
    if (!this.canSubmit()) {
      return
    }
    this.submitDone = true
    this.stopSpeech()
    const result: MapCardResult = {
      completed: true,
      focus_province: this.argsView.focusProvince,
      explored_count: this.exploredCount(),
      skill_key: this.argsView.skillKey
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
  }

  // ====== 大尺寸：表头 ======

  @Builder
  LessonHeader() {
    Row() {
      Column({ space: 2 }) {
        Text('地理 · 小课堂')
          .fontSize(9.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette.chineseInk)
          .letterSpacing(1.4)
        Text('中国地图小课堂')
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.fg)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row({ space: 3 }) {
        Text('已探索')
          .fontSize(10.5)
          .fontColor(this.palette.muted)
        Text(`${this.exploredCount()}`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.fg)
        Text(`/${this.provinceTotal}`)
          .fontSize(10)
          .fontColor(this.palette.subtle)
      }
      .height(36)
      .padding({ left: 10, right: 10 })
      .borderRadius(12)
      .backgroundColor(this.palette.surface)
      .border({ width: 1, color: this.palette.border })
      .accessibilityText(`已探索 ${this.exploredCount()} 个省份，共 ${this.provinceTotal} 个`)
    }
    .width('100%')
    // 右上角让位给 sheet 的系统关闭键（bindSheet showClose），避免徽章被压住
    .padding({ right: 40 })
    .alignItems(VerticalAlign.Center)
  }

  // ====== 地图册卡（表头 + 地图 + 页脚缩放） ======

  @Builder
  AtlasCard() {
    Column() {
      if (this.largeSize) {
        this.AtlasHead()
      }

      Column() {
        ChinaMapStage({
          data: this.data,
          targetId: '',
          selectedId: this.selectedId,
          visitedIds: this.visitedIds,
          interactive: !this.isAnswered && !this.submitDone,
          showDecorations: this.largeSize,
          showZoomControls: !this.largeSize,
          controller: this.mapController,
          onPickProvince: (provinceId: string): void => this.handlePickProvince(provinceId)
        })
      }
      .width('100%')
      .layoutWeight(1)
      .clip(true)
      .borderRadius(this.largeSize ? 17 : 12)
      .border({ width: 1, color: withColorAlpha(this.palette.border, 'E6') })

      if (this.largeSize) {
        this.AtlasFoot()
      }
    }
    .width('100%')
    .height('100%')
    .padding(this.largeSize ? 9 : 0)
    .borderRadius(this.largeSize ? 24 : 14)
    .backgroundColor(this.largeSize ? this.palette.surface : Color.Transparent)
    .border({
      width: this.largeSize ? 1 : 0,
      color: this.largeSize ? this.palette.border : Color.Transparent
    })
  }

  @Builder
  AtlasHead() {
    Row() {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.map'))
          .fontSize(14)
          .fontColor([this.palette.chineseInk])
        Text(`中国 · ${this.provinceTotal} 个省级行政区`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette.fg)
      }
      .layoutWeight(1)

      Text('点一点地图')
        .fontSize(11)
        .fontColor(this.palette.subtle)
    }
    .width('100%')
    .padding({ left: 6, right: 6, top: 1, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  AtlasFoot() {
    Row() {
      Text('拖动地图 · 双指缩放')
        .fontSize(11)
        .fontColor(this.palette.subtle)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.data !== null) {
        MapZoomCluster({
          canZoomIn: this.mapController.canZoomIn,
          canZoomOut: this.mapController.canZoomOut,
          isDarkMode: this.isDarkMode,
          onZoomIn: (): void => this.mapController.zoomIn(),
          onZoomOut: (): void => this.mapController.zoomOut(),
          onReset: (): void => this.mapController.reset()
        })
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 6, right: 2, top: 6 })
    .alignItems(VerticalAlign.Center)
  }

  // ====== 省份资料卡 ======

  @Builder
  ProvinceCard() {
    Column({ space: this.largeSize ? 12 : 8 }) {
      if (this.data === null) {
        Row({ space: 10 }) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color(this.palette.muted)
          Text('地图加载中…')
            .fontSize(13)
            .fontColor(this.palette.muted)
        }
        .width('100%')
        .height(this.largeSize ? 104 : 80)
        .justifyContent(FlexAlign.Center)
      } else if (this.currentInfo !== null) {
        this.ProvinceFilled()
        // 矮屏（≈6.5" 以下）让位给地图：设计稿 @media (max-height: 760px) 同款取舍
        if (this.largeSize && !this.compactHeight) {
          this.TeacherNote()
        }
      } else if (this.isAnswered) {
        this.CompletedSummary()
      } else {
        this.ProvinceEmpty()
      }
    }
    .width('100%')
    .padding({
      left: this.largeSize ? 15 : 12,
      right: this.largeSize ? 15 : 12,
      top: this.largeSize ? 14 : 11,
      bottom: this.largeSize ? 13 : 11
    })
    .borderRadius(this.largeSize ? 22 : 16)
    .backgroundColor(this.palette.surface)
    .border({ width: 1, color: this.palette.border })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ProvinceFilled() {
    Row({ space: this.largeSize ? 11 : 9 }) {
      this.Seal()

      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(this.currentInfo!.short)
            .fontSize(this.largeSize ? 28 : 22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.fg)
            .maxLines(1)
          Text(this.currentInfo!.region)
            .fontSize(10.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.accentInk)
            .padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .backgroundColor(this.palette.surfaceAlt)
            .borderRadius(999)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.currentInfo!.name)
          .fontSize(11.5)
          .fontColor(this.palette.muted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.pin'))
            .fontSize(12)
            .fontColor([this.palette.chineseInk])
          Text('行政中心')
            .fontSize(12)
            .fontColor(this.palette.muted)
          Text(this.currentInfo!.capital)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.fg)
            .maxLines(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      this.ListenButton()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  Seal() {
    Column() {
      // 内圈细线 = 设计稿印章的 inset 环，abbr 大字号压在内圈里
      Column({ space: 1 }) {
        Text(this.currentInfo!.abbr)
          .fontSize(this.largeSize ? 25 : 21)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.chineseInk)
          .lineHeight(this.largeSize ? 27 : 23)
        Text('简称')
          .fontSize(9)
          .fontColor(this.palette.muted)
      }
      .padding({ left: 4, right: 4, top: 2, bottom: 2 })
      .border({ width: 3, color: this.palette.surface })
      .borderRadius(10)
    }
    .width(this.largeSize ? 54 : 46)
    .height(this.largeSize ? 58 : 50)
    .borderRadius(13)
    .backgroundColor(this.palette.surfaceAlt)
    .border({ width: 1.5, color: this.palette.sealBorder })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .rotate({ angle: -2 })
    .scale({ x: this.sealScale, y: this.sealScale })
    .accessibilityText(`简称${this.currentInfo!.abbr}`)
  }

  @Builder
  ListenButton() {
    Row({ space: 4 }) {
      SymbolGlyph(this.isSpeaking
        ? $r('sys.symbol.speaker_wave_2_fill')
        : $r('sys.symbol.speaker_wave_2'))
        .fontSize(15)
        .fontColor([this.palette.chineseInk])
      Text(this.listenLabel)
        .fontSize(11.5)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.fg)
        .maxLines(1)
    }
    .height(44)
    .padding({ left: 10, right: 10 })
    .borderRadius(13)
    .backgroundColor(this.isSpeaking
      ? withColorAlpha(this.palette.accent, '2E')
      : this.palette.surfaceAlt)
    .border({
      width: 1,
      color: this.isSpeaking ? withColorAlpha(this.palette.accent, '66') : this.palette.border
    })
    .accessibilityText(this.listenAccessibilityLabel())
    .onClick(() => {
      this.speakProvinceInfo()
    })
  }

  private listenAccessibilityLabel(): string {
    const info = this.currentInfo
    if (info === null) {
      return '听一听省份介绍'
    }
    return `听一听${info.name}的介绍`
  }

  @Builder
  TeacherNote() {
    Divider()
      .width('100%')
      .strokeWidth(1)
      .color(this.palette.noteLine)
    Row({ space: 7 }) {
      Text('小星老师说')
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.chineseInk)
        .letterSpacing(0.4)
      Text(this.noteText)
        .fontSize(12.5)
        .fontColor(this.palette.muted)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  ProvinceEmpty() {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.map'))
          .fontSize(24)
          .fontColor([this.palette.chineseInk])
      }
      .width(48)
      .height(48)
      .borderRadius(15)
      .backgroundColor(this.palette.surfaceAlt)
      .justifyContent(FlexAlign.Center)

      Column({ space: 5 }) {
        Text('选一个地方开始')
          .fontSize(this.largeSize ? 19 : 16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.fg)
        Text('点一点地图，看看它的名字、简称和行政中心。')
          .fontSize(12)
          .fontColor(this.palette.muted)
          .maxLines(2)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  CompletedSummary() {
    Row({ space: 12 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(24)
          .fontColor([this.palette.success])
      }
      .width(48)
      .height(48)
      .borderRadius(15)
      .backgroundColor(this.palette.surfaceAlt)
      .justifyContent(FlexAlign.Center)

      Column({ space: 4 }) {
        Text(this.hasCompleted ? '本节地图课已完成' : '这一课先到这里')
          .fontSize(this.largeSize ? 19 : 16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.fg)
        Text(this.exploredCount() > 0
          ? `认识了 ${this.exploredCount()} 个地方，点开地图还能回看。`
          : '点开地图还能回看。')
          .fontSize(12)
          .fontColor(this.palette.muted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  // ====== 页脚：进度 + 主按钮 ======

  @Builder
  FooterRegion() {
    Column({ space: 8 }) {
      Row() {
        Text() {
          Span('已认识 ')
          Span(`${this.exploredCount()}`)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.fg)
          Span(' 个地方')
        }
        .fontSize(11.5)
        .fontColor(this.palette.muted)
        .layoutWeight(1)
        .accessibilityText(buildExploreProgressText(this.exploredCount()))

        Text(this.isFinished()
          ? '本节地图课已完成'
          : (this.isAnswered ? '这一课先到这里' : (this.canSubmit() ? '再点几个，记得更牢' : '点一个省份就能继续')))
          .fontSize(10.5)
          .fontColor(this.isFinished() ? this.palette.success : this.palette.subtle)
          .maxLines(1)
      }
      .width('100%')

      if (this.isFinished()) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(15)
            .fontColor([this.palette.success])
          Text('已学会')
            .fontSize(13)
            .fontColor(this.palette.success)
        }
        .width('100%')
        .height(this.largeSize ? 48 : 40)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(withColorAlpha(this.palette.success, '14'))
        .borderRadius(this.largeSize ? 16 : 12)
      } else if (this.isCancelled()) {
        Row({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(15)
            .fontColor([this.palette.subtle])
          Text('本节已结束')
            .fontSize(13)
            .fontColor(this.palette.subtle)
        }
        .width('100%')
        .height(this.largeSize ? 48 : 40)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.palette.surfaceAlt)
        .borderRadius(this.largeSize ? 16 : 12)
      } else {
        this.SubmitButton()
      }
    }
    .width('100%')
    .padding({ left: 4, right: 4 })
  }

  /** 未选省时按钮改文案（设计稿：先点一个地方） */
  private submitLabel(): string {
    return this.canSubmit() ? '我学会了 · 继续' : '先点一个地方'
  }

  @Builder
  SubmitButton() {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 8 }) {
        Text(this.submitLabel())
          .fontSize(this.largeSize ? 16 : 15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.canSubmit() ? this.palette.onAccent : this.palette.subtle)
        if (this.canSubmit()) {
          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(this.largeSize ? 18 : 16)
            .fontColor([this.palette.onAccent])
        }
      }
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height(this.largeSize ? 54 : 44)
    .borderRadius(this.largeSize ? 16 : 12)
    .backgroundColor(this.canSubmit() ? this.palette.accent : this.palette.surfaceAlt)
    .border({
      width: this.canSubmit() ? 0 : 1,
      color: this.palette.border
    })
    .shadow({
      radius: this.canSubmit() ? 12 : 0,
      color: this.palette.ctaShadow,
      offsetX: 0,
      offsetY: this.canSubmit() ? 5 : 0
    })
    .enabled(this.canSubmit())
    .onClick(() => {
      this.submit()
    })
  }

  @Builder
  InvalidState() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(16)
        .fontColor([this.palette.muted])
      Text('这张地图出错了，老师马上换一张')
        .fontSize(14)
        .fontColor(this.palette.muted)
    }
    .width('100%')
    .padding(this.largeSize ? 24 : 12)
  }

  build() {
    if (!this.argsView.valid) {
      this.InvalidState()
    } else if (this.largeSize) {
      Column({ space: 12 }) {
        this.LessonHeader()

        Column() {
          this.AtlasCard()
        }
        .width('100%')
        .layoutWeight(1)

        this.ProvinceCard()
        this.FooterRegion()
      }
      .width('100%')
      .height('100%')
      .padding({ left: 2, right: 2, top: 2 })
    } else {
      CardShell({
        config: this.shellConfig,
        state: this.shellState,
        isAnswered: this.isAnswered,
        correctAnswerText: '',
        onConfirm: (): void => {},
        onRetry: (): void => {}
      }) {
        Column({ space: 10 }) {
          Column() {
            this.AtlasCard()
          }
          .width('100%')
          .height(200)

          this.ProvinceCard()
          this.FooterRegion()
        }
        .width('100%')
      }
    }
  }
}
