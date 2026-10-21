// entry/src/main/ets/components/map/ChinaMapStage.ets
/**
 * ChinaMapStage - 可复用中国地图 Canvas 渲染器（spec 2026-10-21 §9.1）
 *
 * - 34 省 M/L/Z 纯多边形，Y-down 1000×870 坐标系（不做 Y 翻转，与 HandwritingCard 不同）。
 *   洞/岛语义（河北环抱北京、广东群岛）依赖 fill('evenodd') 奇偶规则。
 * - 前向变换：fitScale = min(w/1000, h/870.2) 居中 + zoom(1-4) + pan；
 *   命中判定用同一前向变换的逆变换：触摸点 → 地图坐标 → bbox 粗筛 → pointInProvince。
 * - inset 南海诸岛附图右下角 0.75 倍绘制 + 底板，不参与命中判定。
 * - 四态高亮：targetId（讲解聚焦/出题目标）/ selectedId（探索点击）/ correctId / wrongId。
 * - 触摸隔离：onTouch stopPropagation 防冒泡到聊天 List（NumberPuzzleCard §6.3 先例）。
 * - 点按（onTouch 内自制 tap 判定，避开 TapGesture 坐标 API 差异）+ PanGesture 平移 + PinchGesture 缩放
 *   + ＋/−/⟲ 三按钮；重绘按帧节流（16ms）。
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

const MAP_GRID_W: number = 1000
const MAP_GRID_H: number = 870.2
const ZOOM_MIN: number = 1
const ZOOM_MAX: number = 4
const INSET_SCALE_RATIO: number = 0.75
const REDRAW_INTERVAL_MS: number = 16
const TAP_MAX_SLOP: number = 12
const TAP_MAX_DURATION_MS: number = 350

// 四态高亮色（KIDS_CHINESE 系强调色 + 主题令牌；与 chinese/ 卡片族一致）
const COLOR_CORRECT: string = '#22C55E'
const COLOR_WRONG: string = '#EF4444'

@ComponentV2
export struct ChinaMapStage {
  @Param data: ChinaMapData | null = null
  @Param targetId: string = ''
  @Param selectedId: string = ''
  @Param correctId: string = ''
  @Param wrongId: string = ''
  @Param interactive: boolean = false
  @Event onPickProvince: (provinceId: string) => void = () => {}

  @Local zoom: number = 1
  @Local panX: number = 0
  @Local panY: number = 0

  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  )
  // @Local——build 内 .position 读取（缩放按钮列），onAreaChange 写入须触发重渲染
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

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  aboutToDisappear(): void {
    if (this.redrawTimerId >= 0) {
      clearTimeout(this.redrawTimerId)
      this.redrawTimerId = -1
    }
  }

  @Monitor('targetId', 'selectedId', 'correctId', 'wrongId', 'data')
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

  // ====== 绘制 ======

  private polygonsFor(path: string): number[][][] {
    const cachedRings = this.polygonCache.get(path)
    if (cachedRings !== undefined) {
      return cachedRings
    }
    const rings = parseProvincePolygons(path)
    this.polygonCache.set(path, rings)
    return rings
  }

  private fillForProvince(p: ChinaProvince): string {
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
      return withColorAlpha(this.themePrimary, this.isDarkMode ? '59' : '4D')
    }
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '16') : withColorAlpha(this.themePrimary, '0A')
  }

  private strokeForProvince(p: ChinaProvince): string {
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
      return this.themePrimary
    }
    return this.isDarkMode ? withColorAlpha(this.themePrimary, '33') : withColorAlpha(this.themePrimary, '26')
  }

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
    const s = this.drawScale()
    const ox = this.baseX() + this.panX
    const oy = this.baseY() + this.panY

    // 主图：每省一 path（环为子路径），evenodd 填充
    ctx.lineWidth = this.zoom > 1.5 ? 0.5 : 1
    for (const p of data.provinces) {
      const rings = this.polygonsFor(p.path)
      if (rings.length === 0) {
        continue
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
      ctx.stroke()
    }

    // inset 附图：右下角 0.75 倍 + 底板，不参与命中
    const insetS = s * INSET_SCALE_RATIO
    const insetW = data.inset.width * insetS
    const insetH = data.inset.height * insetS
    const margin = 10
    this.insetScreenW = insetW + 2 * margin
    this.insetScreenH = insetH + 2 * margin
    this.insetScreenX = w - this.insetScreenW - 6
    this.insetScreenY = h - this.insetScreenH - 6
    ctx.fillStyle = this.isDarkMode ? withColorAlpha(this.themePrimary, '14') : '#F7F3EC'
    ctx.strokeStyle = this.isDarkMode ? withColorAlpha(this.themePrimary, '38') : withColorAlpha(this.themePrimary, '2E')
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.rect(this.insetScreenX, this.insetScreenY, this.insetScreenW, this.insetScreenH)
    ctx.fill()
    ctx.stroke()
    ctx.beginPath()
    const insetRings = this.polygonsFor(data.inset.path)
    for (const ring of insetRings) {
      for (let i = 0; i < ring.length; i++) {
        const sx = this.insetScreenX + margin + ring[i][0] * insetS
        const sy = this.insetScreenY + margin + ring[i][1] * insetS
        if (i === 0) {
          ctx.moveTo(sx, sy)
        } else {
          ctx.lineTo(sx, sy)
        }
      }
      ctx.closePath()
    }
    ctx.fillStyle = this.isDarkMode ? withColorAlpha(this.themePrimary, '2E') : withColorAlpha(this.themePrimary, '26')
    ctx.fill('evenodd')
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

  // ====== UI ======

  build() {
    Stack() {
      if (this.data === null) {
        Text('地图加载中…')
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
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
              this.panStartX = this.panX
              this.panStartY = this.panY
            })
            .onActionUpdate((event: GestureEvent) => {
              if (this.canvasWidth <= 0 || this.canvasHeight <= 0) {
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
              this.zoomStart = this.zoom
            })
            .onActionUpdate((event: GestureEvent) => {
              const next = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, this.zoomStart * event.scale))
              if (next !== this.zoom) {
                this.zoom = next
                this.scheduleRedraw()
              }
            }))

        if (this.interactive) {
          Column({ space: 8 }) {
            this.ZoomButton('＋', (): void => this.stepZoom(1))
            this.ZoomButton('−', (): void => this.stepZoom(-1))
            this.ZoomButton('⟲', (): void => this.resetView())
          }
          .alignItems(HorizontalAlign.End)
          .position({ x: this.canvasWidth - 52, y: this.canvasHeight - 190 })
        }
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ZoomButton(label: string, onTap: () => void) {
    Button(label, { type: ButtonType.Circle, stateEffect: true }) {
      Text(label)
        .fontSize(18)
        .fontColor(this.themePrimary)
    }
    .width(36)
    .height(36)
    .backgroundColor(this.isDarkMode ? withColorAlpha(this.themePrimary, '1F') : '#FFFFFF')
    .borderWidth(1)
    .borderColor(withColorAlpha(this.themePrimary, '4D'))
    .onClick(() => onTap())
  }

  private stepZoom(direction: number): void {
    const next = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, this.zoom + direction * 0.5))
    if (next !== this.zoom) {
      this.zoom = next
      this.scheduleRedraw()
    }
  }

  private resetView(): void {
    this.zoom = 1
    this.panX = 0
    this.panY = 0
    this.scheduleRedraw()
  }
}
