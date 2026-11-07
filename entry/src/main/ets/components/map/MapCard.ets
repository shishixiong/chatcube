// entry/src/main/ets/components/map/MapCard.ets
/**
 * MapCard - 中国地图小课堂（map_card 工具，讲解型回执）
 *
 * 视觉取自 map-card-redesign.html：暖纸质地图册。
 * - 大尺寸（全屏 sheet）：自绘表头（地理 · 小课堂 / 已探索 N/34）+ 地图册卡
 *   （纸质网格底 + 指北针 + 图例 + 南海诸岛题注 + 页脚缩放簇）+ 资料卡
 *   （简称印章 + 大区标签 + 行政中心 + 听一听 + 小星老师说）+ 进度行 + 主按钮。
 * - 小尺寸（时间线内联复原）：CardShell 外壳 + 紧凑地图 + 资料卡 + 状态行。
 *
 * 省级下钻（2026-11-06）：点上海 = 把地图册翻到里面一页。同一张卡片、同一个位置，
 * 只有地图和资料卡换了内容；页眉左边是「‹ 返回全国」，进度口径仍是 34 个省级行政区，
 * 区级「看过 k / 16」只做二级进度。上海以外点省仍是原来的单页行为。
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
import {
  SHANGHAI_PROVINCE_ID,
  ShanghaiDistrict,
  ShanghaiMapData,
  districtOrder,
  findDistrictByRef,
  loadShanghaiMapData
} from '../../utils/ShanghaiMapData'
import {
  buildBackToChinaLabel,
  buildDistrictNote,
  buildDistrictProgressText,
  buildDistrictSpeech,
  buildDrilldownEntryLabel,
  buildPlaceSummary,
  buildShanghaiAtlasTitle
} from '../../utils/ShanghaiAtlasCopy'
import { buildExploreProgressText, buildTeacherNote } from '../../utils/MapAtlasCopy'
import { CardShell } from '../cardshell/CardShell'
import { CardShellConfig } from '../cardshell/CardShellTypes'
import { CardShellState } from '../cardshell/CardShellState'
import { getMapAtlasPalette, MapAtlasPalette } from './MapAtlasTokens'
import { ChinaMapStage } from './ChinaMapStage'
import { ChinaMapStageController } from './ChinaMapStageController'
import { ShanghaiMapStage } from './ShanghaiMapStage'
import { MapAtlasDistrictCard, MapAtlasProvinceCard } from './MapAtlasProvinceCard'
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

/** 地图册翻到哪一页：全国 / 上海 */
export type MapCardPage = 'cn' | 'sh'

/** 34 个省级行政区；数据未加载时的兜底分母 */
const DEFAULT_PROVINCE_TOTAL: number = 34
/** 16 个市辖区；数据未加载时的兜底分母 */
const DEFAULT_DISTRICT_TOTAL: number = 16

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

  /** 当前翻到哪一页。全国页的缩放/选中状态原样保留，翻回来还在 */
  @Local page: MapCardPage = 'cn'
  @Local districtData: ShanghaiMapData | null = null
  @Local selectedDistrictId: string = ''
  @Local currentDistrict: ShanghaiDistrict | null = null
  /** 看过的区：二级进度，只影响页眉「看过 k / 16」，不进主进度 */
  @Local visitedDistrictIds: string[] = []

  /** 内联复原时从历史 payload 读回：focus 省 + 已认识数量 */
  private restoredFocusRef: string = ''
  private restoredExplored: number = 0
  /** 朗读序号：连续点省/区时旧回调不覆盖新一次「朗读中」状态 */
  private speakSeq: number = 0
  private shellState: CardShellState = new CardShellState()
  private shellConfig: CardShellConfig = {
    title: '中国地图小课堂', subtitle: '点一点省份，认识全中国', icon: $r('sys.symbol.map'),
    stem: '', hasAudio: false, usesConfirm: false,
    feedbackTitleCorrect: '学完啦！', correctAnswerLabel: ''
  }
  private mapController: ChinaMapStageController = new ChinaMapStageController()
  private districtController: ChinaMapStageController = new ChinaMapStageController()

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
    // 下钻页的数据提前拿好：点上海时要立刻翻页，不能先出现一帧空地图
    loadShanghaiMapData(ctx).then((sh: ShanghaiMapData | null) => {
      this.districtData = sh
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
    // 点上海 = 把地图册翻到里面一页，而不是换一张资料卡就结束
    if (provinceId === SHANGHAI_PROVINCE_ID && this.districtData !== null) {
      this.enterShanghai(false)
      return
    }
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

  // ====== 上海页：翻页 / 选区 / 朗读 ======

  /**
   * @param readOnly true = 讲解已经结束、只是从时间线回看：允许翻页但不改状态
   */
  private enterShanghai(readOnly: boolean): void {
    if (this.districtData === null) {
      return
    }
    if (!readOnly && (this.isAnswered || this.submitDone)) {
      return
    }
    this.page = 'sh'
    this.selectedDistrictId = ''
    this.currentDistrict = null
    this.stopSpeech()
  }

  private backToChina(): void {
    // 回看不改任何进度：已讲解完的时间线也能翻回全国页
    this.page = 'cn'
    this.selectedDistrictId = ''
    this.currentDistrict = null
    this.stopSpeech()
  }

  private handlePickDistrict(districtId: string): void {
    if (this.isAnswered || this.submitDone || this.districtData === null) {
      return
    }
    const picked = findDistrictByRef(this.districtData.districts, districtId)
    if (picked === null) {
      return
    }
    this.selectedDistrictId = picked.id
    this.currentDistrict = picked
    if (!this.visitedDistrictIds.includes(picked.id)) {
      const next: string[] = this.visitedDistrictIds.slice()
      next.push(picked.id)
      this.visitedDistrictIds = next
    }
    this.stampIn()
    this.speakDistrictInfo()
  }

  /** 点空白/海面：取消选区，回到「选一个区开始」 */
  private handleTapBlank(): void {
    if (this.selectedDistrictId === '' || this.isAnswered) {
      return
    }
    this.selectedDistrictId = ''
    this.currentDistrict = null
    this.stopSpeech()
  }

  private speakDistrictInfo(): void {
    const d = this.currentDistrict
    const data = this.districtData
    if (d === null || data === null) {
      return
    }
    this.stopSpeech()
    this.speakSeq = this.speakSeq + 1
    const seq = this.speakSeq
    this.isSpeaking = true
    this.listenLabel = '朗读中'
    ServiceRegistry.tts().speak(buildDistrictSpeech(d, districtOrder(data.districts, d.id)), {
      onStart: () => {},
      onComplete: () => {
        if (seq !== this.speakSeq) {
          return
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
        console.error('MapCard', `district info TTS error: ${error}`)
      }
    }).catch((e: Error) => {
      if (seq !== this.speakSeq) {
        return
      }
      this.isSpeaking = false
      this.listenLabel = '再听'
      console.error('MapCard', `district info TTS speak failed: ${e.message}`)
    })
  }

  private districtCardOrder(): number {
    const data = this.districtData
    if (data === null) {
      return 0
    }
    return districtOrder(data.districts, this.selectedDistrictId)
  }

  private districtCardNote(): string {
    const d = this.currentDistrict
    if (d === null) {
      return ''
    }
    return buildDistrictNote(d, this.districtCardOrder())
  }

  private districtProgressText(): string {
    const total = this.districtData === null ? DEFAULT_DISTRICT_TOTAL : this.districtData.districts.length
    return buildDistrictProgressText(this.visitedDistrictIds.length, total)
  }

  /** 全国页选中上海时才出现下钻入口；本课已提交后不再出现（sheet 随即关闭） */
  private canShowDrilldownEntry(): boolean {
    const info = this.currentInfo
    return this.page === 'cn' && info !== null && info.id === SHANGHAI_PROVINCE_ID
      && this.districtData !== null && !this.submitDone
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
        Text(this.page === 'sh' ? '上海地图小课堂' : '中国地图小课堂')
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

      Stack() {
        if (this.page === 'sh') {
          ShanghaiMapStage({
            data: this.districtData,
            selectedId: this.selectedDistrictId,
            visitedIds: this.visitedDistrictIds,
            interactive: !this.isAnswered && !this.submitDone,
            showDecorations: this.largeSize,
            controller: this.districtController,
            onPickDistrict: (districtId: string): void => this.handlePickDistrict(districtId),
            onTapBlank: (): void => this.handleTapBlank()
          })
        } else {
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
        // 小图没有 AtlasHead 面包屑；上海页在左上角补一个，保证「翻进去还能翻回来」
        if (this.page === 'sh' && !this.largeSize) {
          this.CompactBackChip()
        }
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

  /** 内联小图的返回键：不占地图高度，压在地图左上角 */
  @Builder
  CompactBackChip() {
    Row({ space: 2 }) {
      Text('‹')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.chineseInk)
      Text('返回全国')
        .fontSize(11.5)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.fg)
    }
    .height(28)
    .padding({ left: 7, right: 9 })
    .borderRadius(9)
    .backgroundColor(withColorAlpha(this.palette.surface, 'E6'))
    .border({ width: 1, color: withColorAlpha(this.palette.border, 'B3') })
    .alignItems(VerticalAlign.Center)
    .position({ x: 8, y: 8 })
    .accessibilityText(buildBackToChinaLabel())
    .onClick(() => {
      this.backToChina()
    })
  }

  @Builder
  AtlasHead() {
    Row() {
      if (this.page === 'sh') {
        // 面包屑是入口不是标题：小一号、可点，右边跟二级进度
        Row({ space: 8 }) {
          Row({ space: 2 }) {
            Text('‹')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette.chineseInk)
            Text('返回全国')
              .fontSize(12.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette.fg)
          }
          .height(32)
          .padding({ left: 4, right: 8 })
          .borderRadius(10)
          .backgroundColor(this.palette.surfaceAlt)
          .border({ width: 1, color: this.palette.border })
          .accessibilityText(buildBackToChinaLabel())
          .onClick(() => {
            this.backToChina()
          })

          Text(buildShanghaiAtlasTitle(
            this.districtData === null ? DEFAULT_DISTRICT_TOTAL : this.districtData.districts.length))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.muted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
      } else {
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
      }

      Text(this.page === 'sh' ? '点一个区看看' : '点一点地图')
        .fontSize(11)
        .fontColor(this.palette.subtle)
        .maxLines(1)
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

      if (this.page === 'sh' && this.districtData !== null) {
        MapZoomCluster({
          canZoomIn: this.districtController.canZoomIn,
          canZoomOut: this.districtController.canZoomOut,
          isDarkMode: this.isDarkMode,
          resetLabel: '全市',
          resetAccessibilityLabel: '查看上海全市',
          onZoomIn: (): void => this.districtController.zoomIn(),
          onZoomOut: (): void => this.districtController.zoomOut(),
          onReset: (): void => this.districtController.reset()
        })
      } else if (this.data !== null) {
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

  // ====== 资料卡 ======

  @Builder
  ProvinceCard() {
    if (this.page === 'sh' && this.districtData !== null && !this.isAnswered) {
      this.DistrictCard()
    } else {
      // 全国页原样复用抽出来的资料卡；已交卷后回看的上海页也走这里
      MapAtlasProvinceCard({
        info: this.currentInfo,
        loading: this.data === null,
        noteText: this.noteText,
        isSpeaking: this.isSpeaking,
        listenLabel: this.listenLabel,
        largeSize: this.largeSize,
        compactHeight: this.compactHeight,
        isDarkMode: this.isDarkMode,
        isAnswered: this.isAnswered,
        hasCompleted: this.hasCompleted,
        exploredCount: this.exploredCount(),
        sealScale: this.sealScale,
        showDrilldownEntry: this.canShowDrilldownEntry(),
        drilldownLabel: buildDrilldownEntryLabel(
          this.districtData === null ? DEFAULT_DISTRICT_TOTAL : this.districtData.districts.length),
        onListen: (): void => this.speakProvinceInfo(),
        onEnterDrilldown: (): void => this.enterShanghai(this.isAnswered)
      })
    }
  }

  @Builder
  DistrictCard() {
    MapAtlasDistrictCard({
      district: this.currentDistrict,
      order: this.districtCardOrder(),
      noteText: this.districtCardNote(),
      total: this.districtData === null ? DEFAULT_DISTRICT_TOTAL : this.districtData.districts.length,
      // 与地图同一条分级判定：卡片写「外滩 +2」，地图上此刻也只有外滩那一个点。
      // 倍率取遥控器的 zoomLevel（舞台每次 applyView 回写），不另存一份状态
      placesText: buildPlaceSummary(this.currentDistrict, this.districtController.zoomLevel),
      isSpeaking: this.isSpeaking,
      listenLabel: this.listenLabel,
      largeSize: this.largeSize,
      compactHeight: this.compactHeight,
      isDarkMode: this.isDarkMode,
      sealScale: this.sealScale,
      onListen: (): void => this.speakDistrictInfo()
    })
  }

  // ====== 页脚：进度 + 主按钮 ======

  @Builder
  FooterRegion() {
    Column({ space: 8 }) {
      Row() {
        if (this.page === 'sh' && this.districtData !== null) {
          // 二级进度：单位是区，只在地图册页脚出现，不进主进度
          Text(this.districtProgressText())
            .fontSize(11.5)
            .fontColor(this.palette.muted)
            .layoutWeight(1)
            .accessibilityText(
              `看过 ${this.visitedDistrictIds.length} 个区，共 ${this.districtData.districts.length} 个`)
        } else {
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
        }

        Text(this.footerHint())
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

  /** 页脚右侧的下一步提示：按页给不同的「再做什么」，不重复主按钮文案 */
  private footerHint(): string {
    if (this.isFinished()) {
      return '本节地图课已完成'
    }
    if (this.isAnswered) {
      return '这一课先到这里'
    }
    if (this.page === 'sh') {
      return this.visitedDistrictIds.length > 0 ? '再看看别的区，记得更牢' : '点一个区，听听它叫什么'
    }
    return this.canSubmit() ? '再点几个，记得更牢' : '点一个省份就能继续'
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
