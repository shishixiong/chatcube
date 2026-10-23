// entry/src/main/ets/components/map/ChinaMapStage.ets
/**
 * ChinaMapStage - 可复用中国地图 Canvas 渲染器（spec 2026-10-21 §9.1）
 *
 * - 34 省 M/L/Z 纯多边形，Y-down 1000×870 坐标系（不做 Y 翻转，与 HandwritingCard 不同）。
 *   洞/岛语义（河北环抱北京、广东群岛）依赖 fill('evenodd') 奇偶规则。
 * - 前向变换：fitScale = min(w/1000, h/870.2) 居中 + zoom(1-4) + pan；
 *   命中判定用同一前向变换的逆变换：触摸点 → 地图坐标 → bbox 粗筛 → pointInProvince。
 * - inset 南海诸岛附图：右下角固定尺寸小卡片 + 虚线上框 + 「南海诸岛」题注，不参与命中判定。
 * - 六态高亮：targetId（讲解聚焦/出题目标）/ selectedId（正在认识）/ visitedIds（已探索）
 *   / correctId / wrongId；底色取自 MapAtlasTokens 的纸质地图册皮肤。
 * - 触摸隔离：onTouch stopPropagation 防冒泡到聊天 List（NumberPuzzleCard §6.3 先例）。
 * - 点按（onTouch 内自制 tap 判定，避开 TapGesture 坐标 API 差异）+ PanGesture 平移 + PinchGesture 缩放。
 *   缩放按钮不再长在地图里：卡片把 MapZoomCluster 放页脚，经 ChinaMapStageController 遥控。
 */

import {
  ChinaMapData,
  ChinaProvince
} from '../../utils/ChinaMapData'
import {
  parseProvincePolygons,
  pointInProvince,
  provinceBBox
} from '../../utils/ChinaMapGeometry'
import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { KIDS_CHINESE } from '../kids/KidsBrandTokens'
import { getMapAtlasPalette, MapAtlasPalette } from './MapAtlasTokens'
import { ChinaMapStageController } from './ChinaMapStageController'
import { MAP_ZOOM_CLUSTER_WIDTH, MapZoomCluster } from './MapZoomCluster'

const MAP_GRID_W: number = 1000
const MAP_GRID_H: number = 870.2
const ZOOM_MIN: number = 1
const ZOOM_MAX: number = 4
/** 南海诸岛附图的目标宽度（vp）——设计稿 .inset-card 的 62px */
const INSET_MAX_WIDTH: number = 62
const REDRAW_INTERVAL_MS: number = 16
const TAP_MAX_SLOP: number = 12
const TAP_MAX_DURATION_MS: number = 350
const GRID_STEP: number = 58

// 军规四态色（判题用；与主题无关，红绿语义跨主题稳定）
const COLOR_CORRECT: string = '#22C55E'
const COLOR_WRONG: string = '#EF4444'

@ComponentV2
export struct ChinaMapStage {
  @Param data: ChinaMapData | null = null
  @Param targetId: string = ''
  @Param selectedId: string = ''
  @Param visitedIds: string[] = []
  @Param correctId: string = ''
  @Param wrongId: string = ''
  @Param interactive: boolean = false
  /** 指北针 + 图例 + 附图虚框题注（小地图可关掉省地方） */
  @Param showDecorations: boolean = true
  /** 内建缩放簇（浮在地图右上角）；卡片把控件放页脚时传 false */
  @Param showZoomControls: boolean = true
  /** 页脚缩放簇的遥控器；null 表示无外部控制 */
  @Param controller: ChinaMapStageController | null = null
  @Event onPickProvince: (provinceId: string) => void = () => {}

  @Local zoom: number = 1
  @Local panX: number = 0
  @Local panY: number = 0

  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  )
  // @Local——build 内 .position 读取（叠层控件），onAreaChange 写入须触发重渲染
  @Local canvasWidth: number = 0
  @Local canvasHeight: number = 0
  // 解析缓存：path → 环数组（19k 点/帧不重复解析）
  private polygonCache: Map<string, number[][][]> = new Map()
  // 手势状态
  private panStartX: number = 0
  private panStartY: number = 0
  private zoomStart: number = 1
  // 自制 tap 判定
  private touchDownX: number = -1
  private touchDownY: number = -1
  private touchDownTime: number = 0
  // 绘制期记录 inset 屏幕矩形（排除命中）
  private insetScreenX: number = 0
  private insetScreenY: number = 0
  private insetScreenW: number = 0
  private insetScreenH: number = 0
  // 帧节流
  private redrawScheduled: boolean = false
  private redrawTimerId: number = -1

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get palette(): MapAtlasPalette {
    return getMapAtlasPalette(this.isDarkMode)
  }

  private get showLegend(): boolean {
    return this.targetId === '' && this.correctId === '' && this.wrongId === ''
      && (this.selectedId !== '' || this.visitedIds.length > 0)
  }

  aboutToAppear(): void {
    const bound = this.controller
    if (bound !== null) {
      bound.zoomInAction = (): void => this.stepZoom(1)
      bound.zoomOutAction = (): void => this.stepZoom(-1)
      bound.resetAction = (): void => this.resetView()
      this.syncZoomController()
    }
  }

  aboutToDisappear(): void {
    if (this.redrawTimerId >= 0) {
      clearTimeout(this.redrawTimerId)
      this.redrawTimerId = -1
    }
  }

  @Monitor('targetId', 'selectedId', 'visitedIds', 'correctId', 'wrongId', 'data')
  onHighlightChanged(): void {
    this.scheduleRedraw()
  }

  // ====== 变换 ======

  private fitScale(): number {
    if (this.canvasWidth <= 0 || this.canvasHeight <= 0) {
      return 1
    }
    return Math.min(this.canvasWidth / MAP_GRID_W, this.canvasHeight / MAP_GRID_H)
  }

  private drawScale(): number {
    return this.fitScale() * this.zoom
  }

  private baseX(): number {
    return (this.canvasWidth - MAP_GRID_W * this.drawScale()) / 2
  }

  private baseY(): number {
    return (this.canvasHeight - MAP_GRID_H * this.drawScale()) / 2
  }

  private clampPan(pan: number, contentSize: number, viewSize: number, base: number): number {
    // 内容矩形 [base + pan, base + pan + contentSize] 与视口至少保留 10% 可见
    const lo = 0.1 * viewSize - base - contentSize
    const hi = 0.9 * viewSize - base
    return Math.min(hi, Math.max(lo, pan))
  }

  private scheduleRedraw(): void {
    if (this.redrawScheduled) {
      return
    }
    this.redrawScheduled = true
    this.redrawTimerId = setTimeout(() => {
      this.redrawScheduled = false
      this.redrawTimerId = -1
      this.redraw()
    }, REDRAW_INTERVAL_MS)
  }

  private syncZoomController(): void {
    const bound = this.controller
    if (bound === null) {
      return
    }
    bound.zoomLevel = this.zoom
    bound.canZoomIn = this.zoom < ZOOM_MAX - 0.001
    bound.canZoomOut = this.zoom > ZOOM_MIN + 0.001
  }

  // ====== 配色 ======

  private polygonsFor(path: string): number[][][] {
    const cachedRings = this.polygonCache.get(path)
    if (cachedRings !== undefined) {
      return cachedRings
    }
    const rings = parseProvincePolygons(path)
    this.polygonCache.set(path, rings)
    return rings
  }

  private isVisited(p: ChinaProvince): boolean {
    return this.visitedIds.includes(p.id)
  }

  private fillForProvince(p: ChinaProvince): string {
    const palette = this.palette
    if (this.wrongId !== '' && p.id === this.wrongId) {
      return withColorAlpha(COLOR_WRONG, this.isDarkMode ? '5C' : '4D')
    }
    if (this.correctId !== '' && p.id === this.correctId) {
      return withColorAlpha(COLOR_CORRECT, this.isDarkMode ? '5C' : '4D')
    }
    if (this.targetId !== '' && p.id === this.targetId) {
      return withColorAlpha(KIDS_CHINESE, this.isDarkMode ? '66' : '59')
    }
    if (this.selectedId !== '' && p.id === this.selectedId) {
      return palette.selected
    }
    if (this.isVisited(p)) {
      return palette.visited
    }
    return palette.land
  }

  private strokeForProvince(p: ChinaProvince): string {
    const palette = this.palette
    if (this.wrongId !== '' && p.id === this.wrongId) {
      return withColorAlpha(COLOR_WRONG, this.isDarkMode ? 'B3' : '99')
    }
    if (this.correctId !== '' && p.id === this.correctId) {
      return withColorAlpha(COLOR_CORRECT, this.isDarkMode ? 'B3' : '99')
    }
    if (this.targetId !== '' && p.id === this.targetId) {
      return KIDS_CHINESE
    }
    if (this.selectedId !== '' && p.id === this.selectedId) {
      return palette.selectedLine
    }
    if (this.isVisited(p)) {
      return palette.visitedLine
    }
    return palette.line
  }

  private lineWidthForProvince(p: ChinaProvince): number {
    if (this.wrongId !== '' && p.id === this.wrongId) {
      return 2
    }
    if (this.correctId !== '' && p.id === this.correctId) {
      return 2
    }
    if (this.targetId !== '' && p.id === this.targetId) {
      return 2.2
    }
    if (this.selectedId !== '' && p.id === this.selectedId) {
      return 2.2
    }
    if (this.isVisited(p)) {
      return 1.4
    }
    return 1
  }

  /** 重点省最后画，省界线不被后画的邻省盖住 */
  private emphasisId(): string {
    if (this.wrongId !== '') {
      return this.wrongId
    }
    if (this.correctId !== '') {
      return this.correctId
    }
    if (this.targetId !== '') {
      return this.targetId
    }
    return this.selectedId
  }

  // ====== 绘制 ======

  private redraw(): void {
    if (this.canvasWidth <= 0 || this.canvasHeight <= 0) {
      return
    }
    const ctx = this.canvasContext
    const w = this.canvasWidth
    const h = this.canvasHeight
    ctx.clearRect(0, 0, w, h)
    const data = this.data
    if (data === null) {
      return
    }
    this.drawPaper(ctx, w, h)
    const s = this.drawScale()
    const ox = this.baseX() + this.panX
    const oy = this.baseY() + this.panY

    // 主图：每省一 path（环为子路径），evenodd 填充
    const emphasis = this.emphasisId()
    let emphasisProvince: ChinaProvince | null = null
    for (const p of data.provinces) {
      if (emphasis !== '' && p.id === emphasis) {
        emphasisProvince = p
        continue
      }
      this.drawProvince(ctx, p, ox, oy, s)
    }
    if (emphasisProvince !== null) {
      this.drawProvince(ctx, emphasisProvince, ox, oy, s)
    }

    this.drawInset(ctx, w, h)
  }

  /** 纸张底：暖米色 + 细网格（设计稿 .map-viewport 的坐标纸） */
  private drawPaper(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    const palette = this.palette
    ctx.fillStyle = palette.water
    ctx.fillRect(0, 0, w, h)
    ctx.strokeStyle = palette.grid
    ctx.lineWidth = 1
    ctx.beginPath()
    for (let x = GRID_STEP; x < w; x += GRID_STEP) {
      ctx.moveTo(x, 0)
      ctx.lineTo(x, h)
    }
    for (let y = GRID_STEP; y < h; y += GRID_STEP) {
      ctx.moveTo(0, y)
      ctx.lineTo(w, y)
    }
    ctx.stroke()
  }

  private drawProvince(ctx: CanvasRenderingContext2D, p: ChinaProvince,
    ox: number, oy: number, s: number): void {
    const rings = this.polygonsFor(p.path)
    if (rings.length === 0) {
      return
    }
    ctx.beginPath()
    for (const ring of rings) {
      for (let i = 0; i < ring.length; i++) {
        const sx = ox + ring[i][0] * s
        const sy = oy + ring[i][1] * s
        if (i === 0) {
          ctx.moveTo(sx, sy)
        } else {
          ctx.lineTo(sx, sy)
        }
      }
      ctx.closePath()
    }
    ctx.fillStyle = this.fillForProvince(p)
    ctx.fill('evenodd')
    ctx.strokeStyle = this.strokeForProvince(p)
    ctx.lineWidth = this.lineWidthForProvince(p)
    ctx.stroke()
  }

  /**
   * inset 附图：右下角固定尺寸小卡片 + 虚线上框 + 「南海诸岛」题注，不参与命中。
   *
   * 改版后不再按地图缩放比例绘制（设计稿里它是固定 62px 的附图章，缩放/平移时不动）：
   * 宽度按视口收敛到 34-62vp，矮视口再按高度让位，避免内联小地图被附图挤满。
   */
  private drawInset(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    const data = this.data
    if (data === null) {
      return
    }
    const palette = this.palette
    const insetW = Math.max(34, Math.min(INSET_MAX_WIDTH, Math.min(w * 0.17, h * 0.2)))
    const insetS = insetW / data.inset.width
    const pad = 4
    const captionH = 13
    const boxW = insetW + pad * 2
    const boxH = data.inset.height * insetS + pad * 2 + captionH
    const boxX = w - boxW - 7
    const boxY = h - boxH - 7
    this.insetScreenX = boxX
    this.insetScreenY = boxY
    this.insetScreenW = boxW
    this.insetScreenH = boxH

    ctx.setLineDash([3, 2])
    ctx.fillStyle = palette.insetBg
    ctx.beginPath()
    this.roundRectPath(ctx, boxX, boxY, boxW, boxH, 6)
    ctx.fill()
    ctx.strokeStyle = withColorAlpha(palette.insetLine, '66')
    ctx.lineWidth = 1
    ctx.stroke()
    ctx.setLineDash([])

    const insetRings = this.polygonsFor(data.inset.path)
    ctx.beginPath()
    for (const ring of insetRings) {
      for (let i = 0; i < ring.length; i++) {
        const sx = boxX + pad + ring[i][0] * insetS
        const sy = boxY + pad + ring[i][1] * insetS
        if (i === 0) {
          ctx.moveTo(sx, sy)
        } else {
          ctx.lineTo(sx, sy)
        }
      }
      ctx.closePath()
    }
    ctx.fillStyle = palette.insetFill
    ctx.fill('evenodd')
    ctx.strokeStyle = palette.insetLine
    ctx.lineWidth = 0.8
    ctx.stroke()

    ctx.fillStyle = palette.muted
    ctx.font = '9px sans-serif'
    ctx.textAlign = 'center'
    ctx.fillText('南海诸岛', boxX + boxW / 2, boxY + boxH - 4)
    ctx.textAlign = 'start'
  }

  private roundRectPath(ctx: CanvasRenderingContext2D, x: number, y: number,
    width: number, height: number, radius: number): void {
    ctx.moveTo(x + radius, y)
    ctx.arcTo(x + width, y, x + width, y + height, radius)
    ctx.arcTo(x + width, y + height, x, y + height, radius)
    ctx.arcTo(x, y + height, x, y, radius)
    ctx.arcTo(x, y, x + width, y, radius)
    ctx.closePath()
  }

  // ====== 命中判定（逆变换） ======

  private handleTap(localX: number, localY: number): void {
    const data = this.data
    if (data === null || !this.interactive) {
      return
    }
    if (localX >= this.insetScreenX && localY >= this.insetScreenY
      && localX <= this.insetScreenX + this.insetScreenW
      && localY <= this.insetScreenY + this.insetScreenH) {
      return // inset 附图区不参与命中
    }
    const s = this.drawScale()
    const mapX = (localX - this.baseX() - this.panX) / s
    const mapY = (localY - this.baseY() - this.panY) / s
    if (mapX < 0 || mapY < 0 || mapX > MAP_GRID_W || mapY > MAP_GRID_H) {
      return
    }
    for (const p of data.provinces) {
      const bbox = provinceBBox(p.path)
      if (mapX < bbox.minX || mapX > bbox.maxX || mapY < bbox.minY || mapY > bbox.maxY) {
        continue
      }
      if (pointInProvince(p.path, mapX, mapY)) {
        this.onPickProvince(p.id)
        return
      }
    }
  }

  // ====== 叠层控件 ======

  @Builder
  CompassOverlay() {
    Column() {
      SymbolGlyph($r('sys.symbol.compass'))
        .fontSize(22)
        .fontColor([this.palette.selectedLine])
    }
    .width(34)
    .height(34)
    .borderRadius(17)
    .backgroundColor(this.palette.compassBg)
    .border({ width: 1, color: withColorAlpha(this.palette.line, '2E') })
    .justifyContent(FlexAlign.Center)
    .position({
      x: this.interactive && this.showZoomControls ? 10 : this.canvasWidth - 44,
      y: 9
    })
    .accessibilityText('指北针')
  }

  @Builder
  LegendOverlay() {
    Row({ space: 8 }) {
      this.LegendItem(this.palette.visited, this.palette.visitedLine, '已探索')
      this.LegendItem(this.palette.selected, this.palette.selectedLine, '正在认识')
    }
    .height(22)
    .padding({ left: 7, right: 7 })
    .borderRadius(11)
    .backgroundColor(this.palette.legendBg)
    .border({ width: 1, color: withColorAlpha(this.palette.line, '29') })
    .position({ x: 9, y: this.canvasHeight - 31 })
  }

  @Builder
  LegendItem(fill: string, line: string, label: string) {
    Row({ space: 3 }) {
      Column()
        .width(7)
        .height(7)
        .borderRadius(3.5)
        .backgroundColor(fill)
        .border({ width: 1, color: line })
      Text(label)
        .fontSize(9.5)
        .fontColor(this.palette.muted)
    }
  }

  @Builder
  ZoomOverlay() {
    Row() {
      MapZoomCluster({
        canZoomIn: this.zoom < ZOOM_MAX - 0.001,
        canZoomOut: this.zoom > ZOOM_MIN + 0.001,
        isDarkMode: this.isDarkMode,
        onZoomIn: (): void => this.stepZoom(1),
        onZoomOut: (): void => this.stepZoom(-1),
        onReset: (): void => this.resetView()
      })
    }
    .position({
      x: this.canvasWidth - MAP_ZOOM_CLUSTER_WIDTH - 9,
      y: 9
    })
  }

  // ====== UI ======

  build() {
    Stack() {
      if (this.data === null) {
        Column({ space: 8 }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(this.palette.muted)
          Text('地图加载中…')
            .fontSize(13)
            .fontColor(this.palette.muted)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Canvas(this.canvasContext)
          .width('100%')
          .height('100%')
          .onReady(() => {
            this.redraw()
          })
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            this.canvasWidth = newArea.width as number
            this.canvasHeight = newArea.height as number
            this.panX = this.clampPan(this.panX, MAP_GRID_W * this.drawScale(), this.canvasWidth, this.baseX())
            this.panY = this.clampPan(this.panY, MAP_GRID_H * this.drawScale(), this.canvasHeight, this.baseY())
            this.redraw()
          })
          .onTouch((event: TouchEvent) => {
            event.stopPropagation()
            if (!this.interactive) {
              return
            }
            if (event.type === TouchType.Down) {
              this.touchDownX = event.touches[0].x
              this.touchDownY = event.touches[0].y
              this.touchDownTime = Date.now()
            } else if (event.type === TouchType.Up) {
              const dx = event.touches[0].x - this.touchDownX
              const dy = event.touches[0].y - this.touchDownY
              const duration = Date.now() - this.touchDownTime
              if (Math.hypot(dx, dy) <= TAP_MAX_SLOP && duration <= TAP_MAX_DURATION_MS) {
                this.handleTap(event.touches[0].x, event.touches[0].y)
              }
            }
          })
          .gesture(PanGesture({ direction: PanDirection.All, distance: 5 })
            .onActionStart((_event: GestureEvent) => {
              if (!this.interactive) {
                return
              }
              this.panStartX = this.panX
              this.panStartY = this.panY
            })
            .onActionUpdate((event: GestureEvent) => {
              if (!this.interactive || this.canvasWidth <= 0 || this.canvasHeight <= 0) {
                return
              }
              this.panX = this.clampPan(this.panStartX + event.offsetX,
                MAP_GRID_W * this.drawScale(), this.canvasWidth, this.baseX())
              this.panY = this.clampPan(this.panStartY + event.offsetY,
                MAP_GRID_H * this.drawScale(), this.canvasHeight, this.baseY())
              this.scheduleRedraw()
            }))
          // pinch 走 priorityGesture——双指捏合不被 distance:5 的单指 pan 抢占（pan 仍在 gesture 通道）
          .priorityGesture(PinchGesture({ fingers: 2 })
            .onActionStart((_event: GestureEvent) => {
              if (!this.interactive) {
                return
              }
              this.zoomStart = this.zoom
            })
            .onActionUpdate((event: GestureEvent) => {
              if (!this.interactive) {
                return
              }
              const next = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, this.zoomStart * event.scale))
              if (Math.abs(next - this.zoom) > 0.001) {
                this.zoom = next
                this.syncZoomController()
                this.scheduleRedraw()
              }
            }))

        if (this.showDecorations) {
          this.CompassOverlay()
          if (this.showLegend) {
            this.LegendOverlay()
          }
        }
        if (this.interactive && this.showZoomControls) {
          this.ZoomOverlay()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.water)
  }

  private stepZoom(direction: number): void {
    const next = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, this.zoom + direction * 0.5))
    if (Math.abs(next - this.zoom) > 0.001) {
      this.zoom = next
      this.syncZoomController()
      this.scheduleRedraw()
    }
  }

  private resetView(): void {
    this.zoom = 1
    this.panX = 0
    this.panY = 0
    this.syncZoomController()
    this.scheduleRedraw()
  }
}
