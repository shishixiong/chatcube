// entry/src/main/ets/components/map/ShanghaiMapStage.ets
/**
 * ShanghaiMapStage - 上海 16 区 Canvas 渲染器（map_card 省级下钻页）
 *
 * 与 ChinaMapStage 同一套坐标与手势约定，只是换了数据和叠层：
 * - 数据：rawfile/map/shanghai_districts.json，16 个区的 M/L/Z 纯多边形，
 *   Y-down 1000×1007.4（等距圆柱投影，经度按 31.2° 纬度压缩）。
 * - 前向变换：fitScale = min(w/1000, h/1007.4) 居中 + zoom(1-6) + pan；
 *   命中判定用同一变换的逆变换 → bbox 粗筛 → pointInProvince（射线法，洞/岛靠 evenodd）。
 * - 六态高亮复用全国图的色：visited（看过）/ selected（正在认识）/ line（区界）。
 * - 标签：区名压在地图册上。市中心 7 个区面积小，默认不标名，选中或放大到 1.55× 才出现，
 *   避免「黄浦·静安·虹口」挤成一团墨点。字号按屏幕 vp 定，不随舞台尺寸缩成芝麻。
 * - 小地名：只有选中的区才浮出它自己的地名（外滩、陆家嘴、佘山……），其余区降一档，
 *   视线自然落到「这一区 + 区里有什么」。分级由 placeTierZoom 决定，与设计稿同一条判定：
 *   tier 1 始终显示、2 到 1.7×、3 到 2.6×；邻区地名永不出现（78 个点全标会糊成一片）。
 * - 叠层：坐标纸 + 指北针 + 比例尺；不再画南海诸岛（不属于上海这一页）。
 * - 手势与全国图一致：onTouch stopPropagation 防冒泡到聊天 List，自制 tap 判定，
 *   PanGesture 平移，PinchGesture 缩放，页脚缩放簇经 ChinaMapStageController 遥控。
 */

import {
  ShanghaiDistrict,
  ShanghaiMapData,
  districtLabelAnchor,
  visiblePlaces
} from '../../utils/ShanghaiMapData'
import {
  MapBBox,
  parseProvincePolygons,
  pointInProvince,
  provinceBBox
} from '../../utils/ChinaMapGeometry'
import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { getMapAtlasPalette, MapAtlasPalette } from './MapAtlasTokens'
import { ChinaMapStageController } from './ChinaMapStageController'

const MAP_GRID_W: number = 1000
const MAP_GRID_H: number = 1007.4
const ZOOM_MIN: number = 1
/** 市中心 7 区面积小，4× 点黄浦仍然费力；上海页放到 6× */
const ZOOM_MAX: number = 6
const TAP_MAX_SLOP: number = 12
const TAP_MAX_DURATION_MS: number = 350
/** 坐标纸网格间距（屏幕 vp，随缩放一起放大） */
const GRID_STEP: number = 58
/** 市中心 7 区：面积小，默认不标名 */
const TINY_DISTRICT_IDS: string[] = ['310101', '310104', '310105', '310106', '310107', '310109', '310110']
/** 放大到这个倍率以上，小 district 的标签也出现 */
const TINY_LABEL_MIN_ZOOM: number = 1.55
/** 小地名在屏幕上的字号（vp）：比区名小一档，但不随放大变成巨字 */
const PLACE_FONT_SIZE: number = 9.5
/** 小地名标签往左写的分界：浦东、崇明东侧靠近图右缘，往右写会顶出画布 */
const PLACE_FLIP_X: number = 760
/** 邻区降档的纸色（把非选中区压一档，底色仍是同一张纸） */
const MUTED_MIX: number = 0.55
/** 标签屏幕包围盒：区名与小地名抢位置时用，单位 vp */
interface LabelBox {
  x1: number
  y1: number
  x2: number
  y2: number
}

/** 一个地图单位约合米数：1000 宽 ≈ 132 km（1.3903° 经度 × cos31.27°） */
const METERS_PER_UNIT: number = 132.3

@ComponentV2
export struct ShanghaiMapStage {
  @Param data: ShanghaiMapData | null = null
  @Param selectedId: string = ''
  @Param visitedIds: string[] = []
  @Param interactive: boolean = false
  /** 指北针 + 比例尺题注（内联小图可关掉省地方） */
  @Param showDecorations: boolean = true
  /** 页脚缩放簇的遥控器；null 表示无外部控制 */
  @Param controller: ChinaMapStageController | null = null
  @Event onPickDistrict: (districtId: string) => void = () => {}
  /** 点到海面/空白：取消选中（只在 interactive 时触发） */
  @Event onTapBlank: () => void = () => {}

  @Local zoom: number = 1
  @Local panX: number = 0
  @Local panY: number = 0

  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  )
  // @Local——build 内 .position 读取（叠层控件），onAreaChange 写入须触发重渲染
  @Local canvasWidth: number = 0
  @Local canvasHeight: number = 0
  // 解析 + bbox 缓存：16 区约 2.7k 点，逐帧重算 bbox 没必要
  private pathCache: Map<string, number[][][]> = new Map()
  private bboxCache: Map<string, MapBBox> = new Map()
  private panStartX: number = 0
  private panStartY: number = 0
  private zoomStart: number = 1
  private touchDownX: number = -1
  private touchDownY: number = -1
  private touchDownTime: number = 0
  private redrawScheduled: boolean = false
  private redrawTimerId: number = -1

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get palette(): MapAtlasPalette {
    return getMapAtlasPalette(this.isDarkMode)
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
    const bound = this.controller
    if (bound !== null) {
      bound.zoomInAction = (): void => {}
      bound.zoomOutAction = (): void => {}
      bound.resetAction = (): void => {}
    }
  }

  /** 选中区 / 看过区 / 换数据都要重画：Canvas 不会跟着 @Param 自动刷 */
  @Monitor('data', 'selectedId', 'visitedIds')
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
    // 1× 时整张图正好放进框里：居中就是唯一正确位置，别让孩子把上海拖出画框
    if (contentSize <= viewSize) {
      return 0
    }
    // 放大后内容比视口大：边缘至少留 10% 可见，拖到哪儿都能找到回来的路
    const lo = 0.1 * viewSize - base - contentSize
    const hi = 0.9 * viewSize - base
    return Math.min(hi, Math.max(lo, pan))
  }

  private scheduleRedraw(): void {
    if (this.redrawScheduled) {
      return
    }
    this.redrawScheduled = true
    this.redrawTimerId = setTimeout((): void => {
      this.redrawScheduled = false
      this.redrawTimerId = -1
      this.draw()
    }, 16)
  }

  private syncZoomController(): void {
    const bound = this.controller
    if (bound === null) {
      return
    }
    bound.zoomLevel = this.zoom
    bound.canZoomIn = this.zoom < ZOOM_MAX - 0.01
    bound.canZoomOut = this.zoom > ZOOM_MIN + 0.01
  }

  private stepZoom(direction: number): void {
    const next = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, this.zoom + direction * 0.5))
    if (Math.abs(next - this.zoom) < 0.001) {
      return
    }
    this.zoom = next
    if (next <= ZOOM_MIN + 0.001) {
      this.panX = 0
      this.panY = 0
    } else {
      this.clampView()
    }
    this.syncZoomController()
    this.scheduleRedraw()
  }

  /** 缩放后把平移量收回到「边缘至少留 10%」的范围内，别把上海甩出画框 */
  private clampView(): void {
    if (this.canvasWidth <= 0 || this.canvasHeight <= 0) {
      return
    }
    this.panX = this.clampPan(this.panX, MAP_GRID_W * this.drawScale(), this.canvasWidth, this.baseX())
    this.panY = this.clampPan(this.panY, MAP_GRID_H * this.drawScale(), this.canvasHeight, this.baseY())
  }

  private resetView(): void {
    this.zoom = 1
    this.panX = 0
    this.panY = 0
    this.syncZoomController()
    this.scheduleRedraw()
  }

  // ====== 数据 ======

  private ringsFor(district: ShanghaiDistrict): number[][][] {
    const hit = this.pathCache.get(district.id)
    if (hit !== undefined) {
      return hit
    }
    // 与全国图共用同一个解析器：数据格式本就一致，不为区级另写一份
    const rings: number[][][] = parseProvincePolygons(district.path)
    this.pathCache.set(district.id, rings)
    return rings
  }

  private bboxFor(district: ShanghaiDistrict): MapBBox {
    const hit = this.bboxCache.get(district.id)
    if (hit !== undefined) {
      return hit
    }
    const bbox: MapBBox = provinceBBox(district.path)
    this.bboxCache.set(district.id, bbox)
    return bbox
  }

  // ====== 绘制 ======

  private draw(): void {
    const ctx = this.canvasContext
    const w = this.canvasWidth
    const h = this.canvasHeight
    if (w <= 0 || h <= 0) {
      return
    }
    ctx.clearRect(0, 0, w, h)
    const data = this.data
    if (data === null) {
      return
    }
    const s = this.drawScale()
    const ox = this.baseX() + this.panX
    const oy = this.baseY() + this.panY
    this.drawPaper(ctx, ox, oy, s)
    ctx.save()
    ctx.translate(ox, oy)
    ctx.scale(s, s)
    this.drawLand(ctx, data)
    this.drawBorders(ctx, data)
    ctx.restore()
    this.drawLabels(ctx, ox, oy, s)
    this.drawPlaces(ctx, ox, oy, s)
    if (this.showDecorations) {
      this.drawScaleNote(ctx, s)
    }
  }

  /** 纸张底：暖米色 + 细网格（与 ChinaMapStage 的坐标纸同一张纸） */
  private drawPaper(ctx: CanvasRenderingContext2D, ox: number, oy: number, s: number): void {
    const palette = this.palette
    ctx.fillStyle = palette.water
    ctx.fillRect(0, 0, this.canvasWidth, this.canvasHeight)
    const step = GRID_STEP * s
    if (step < 6) {
      return
    }
    let startX = ox % step
    if (startX < 0) {
      startX += step
    }
    let startY = oy % step
    if (startY < 0) {
      startY += step
    }
    ctx.strokeStyle = palette.grid
    ctx.lineWidth = 1
    ctx.beginPath()
    for (let x = startX; x < this.canvasWidth; x += step) {
      ctx.moveTo(x, 0)
      ctx.lineTo(x, this.canvasHeight)
    }
    for (let y = startY; y < this.canvasHeight; y += step) {
      ctx.moveTo(0, y)
      ctx.lineTo(this.canvasWidth, y)
    }
    ctx.stroke()
  }

  private fillFor(districtId: string): string {
    const base = this.baseFillFor(districtId)
    if (this.selectedId === '' || districtId === this.selectedId) {
      return base
    }
    // 聚焦态：其余区往纸色里混一档，颜色关系不变（看过 / 没看过仍分得开），只是不再抢眼
    return mixHex(base, this.palette.land, MUTED_MIX)
  }

  private baseFillFor(districtId: string): string {
    if (districtId === this.selectedId) {
      return this.palette.selected
    }
    if (this.visitedIds.includes(districtId)) {
      return this.palette.visited
    }
    return this.palette.land
  }

  private drawLand(ctx: CanvasRenderingContext2D, data: ShanghaiMapData): void {
    for (const d of data.districts) {
      const rings = this.ringsFor(d)
      if (rings.length === 0) {
        continue
      }
      ctx.beginPath()
      for (const ring of rings) {
        if (ring.length < 3) {
          continue
        }
        ctx.moveTo(ring[0][0], ring[0][1])
        for (let i = 1; i < ring.length; i++) {
          ctx.lineTo(ring[i][0], ring[i][1])
        }
        ctx.closePath()
      }
      ctx.fillStyle = this.fillFor(d.id)
      ctx.fill('evenodd')
    }
  }

  /** 区界：选中区的界线最后画，不被邻区压住 */
  private drawBorders(ctx: CanvasRenderingContext2D, data: ShanghaiMapData): void {
    let selected: ShanghaiDistrict | null = null
    for (const d of data.districts) {
      if (d.id === this.selectedId) {
        selected = d
        continue
      }
      // 看过的区界线略深一档：和「已探索」底色一起，把走过的路留在纸上
      const visited = this.visitedIds.includes(d.id)
      this.strokeDistrict(ctx, d, visited ? this.palette.visitedLine : this.palette.line,
        visited ? 1.6 : 1)
    }
    if (selected !== null) {
      this.strokeDistrict(ctx, selected, this.palette.selectedLine, 2.2)
    }
  }

  private strokeDistrict(ctx: CanvasRenderingContext2D, district: ShanghaiDistrict,
    color: string, width: number): void {
    const rings = this.ringsFor(district)
    if (rings.length === 0) {
      return
    }
    ctx.beginPath()
    for (const ring of rings) {
      if (ring.length < 3) {
        continue
      }
      ctx.moveTo(ring[0][0], ring[0][1])
      for (let i = 1; i < ring.length; i++) {
        ctx.lineTo(ring[i][0], ring[i][1])
      }
      ctx.closePath()
    }
    ctx.strokeStyle = color
    // 线宽用屏幕 vp 表达：地图坐标里要除以当前倍率，放大时界线才不会跟着变粗
    ctx.lineWidth = width / this.drawScale()
    ctx.lineJoin = 'round'
    ctx.stroke()
  }

  /**
   * 区名层：屏幕坐标里写，字号 12–18vp 随放大缓增。
   * 若按地图坐标写字，小舞台（fit≈0.35）上 12 单位的字只剩 4px，孩子根本看不清。
   */
  private drawLabels(ctx: CanvasRenderingContext2D, ox: number, oy: number, s: number): void {
    const data = this.data
    if (data === null || s <= 0) {
      return
    }
    const size = this.labelFontSize()
    ctx.font = `600 ${size}px serif`
    ctx.textAlign = 'center'
    ctx.lineJoin = 'round'
    for (const d of data.districts) {
      const isSelected = d.id === this.selectedId
      const tiny = TINY_DISTRICT_IDS.includes(d.id)
      if (tiny && !isSelected && this.zoom < TINY_LABEL_MIN_ZOOM) {
        continue
      }
      const pos = this.districtLabelPos(d, ox, oy, s)
      if (pos[0] < -20 || pos[0] > this.canvasWidth + 20
        || pos[1] < -20 || pos[1] > this.canvasHeight + 20) {
        continue
      }
      // 先描一圈纸色再填字：标签压过区界时也读得清（与 HTML 稿的 paint-order 同效）
      ctx.lineWidth = Math.max(2.2, size * 0.2)
      ctx.strokeStyle = this.palette.land
      ctx.strokeText(d.short, pos[0], pos[1])
      ctx.fillStyle = isSelected ? this.palette.fg : this.palette.muted
      ctx.fillText(d.short, pos[0], pos[1])
    }
    ctx.textAlign = 'start'
  }

  /** 区名字号：屏幕 vp，12（1×）→ 18（6×），不随舞台尺寸缩水 */
  private labelFontSize(): number {
    return Math.min(18, Math.max(12, 12 + (this.zoom - 1) * 1.2))
  }

  /**
   * 区名标签的屏幕基线位置。
   * 市中心四区的质心挨得太近：放大到 1.55× 后 12vp 的「静安 / 虹口 / 杨浦」会叠成一团，
   * 给固定错身量，圆点/锚点不动（与地名的 PLACE_NUDGE_Y 同一做法）。
   */
  private districtLabelPos(d: ShanghaiDistrict, ox: number, oy: number, s: number): number[] {
    const anchor = districtLabelAnchor(d, this.bboxFor(d))
    const shifted = TINY_DISTRICT_IDS.includes(d.id) && this.zoom >= TINY_LABEL_MIN_ZOOM
    const nudgeX = shifted ? districtLabelNudgeX(d.id) : 0
    const nudgeY = shifted ? districtLabelNudgeY(d.id) : 0
    const out: number[] = [ox + anchor[0] * s + nudgeX,
      oy + anchor[1] * s + nudgeY + this.labelFontSize() * 0.35]
    return out
  }

  /** 选中区区名标签的包围盒；小地名层用它做避让 */
  private selectedDistrictLabelBox(d: ShanghaiDistrict, ox: number, oy: number, s: number): LabelBox {
    const pos = this.districtLabelPos(d, ox, oy, s)
    const size = this.labelFontSize()
    const half = d.short.length * size / 2 + 2
    const box: LabelBox = {
      x1: pos[0] - half,
      y1: pos[1] - size * 0.95,
      x2: pos[0] + half,
      y2: pos[1] + size * 0.25
    }
    return box
  }

  /**
   * 小地名层：只画选中区的。
   * 圆点 + 光环 + 右侧标签；字号固定屏幕 9.5vp，放大不会变成巨字。
   * 挨得太近的三对地名（苏州河 / 和平公园 / 松江大学城）只把字上下错身，圆点不动。
   */
  private drawPlaces(ctx: CanvasRenderingContext2D, ox: number, oy: number, s: number): void {
    const data = this.data
    if (data === null || this.selectedId === '' || s <= 0) {
      return
    }
    let target: ShanghaiDistrict | null = null
    for (const d of data.districts) {
      if (d.id === this.selectedId) {
        target = d
      }
    }
    if (target === null) {
      return
    }
    const list = visiblePlaces(target, this.zoom)
    if (list.length === 0) {
      return
    }
    const size = PLACE_FONT_SIZE
    const gap = 5
    const dotR = 2.4
    const ink = this.palette.chineseInk
    const districtBox = this.selectedDistrictLabelBox(target, ox, oy, s)
    ctx.font = `600 ${size}px serif`
    ctx.lineJoin = 'round'
    for (const p of list) {
      const sx = ox + p.x * s
      const sy = oy + p.y * s
      if (sx < -30 || sx > this.canvasWidth + 30 || sy < -30 || sy > this.canvasHeight + 30) {
        continue
      }
      // 光环：让圆点在「看过」的浅底上也找得到（设计稿 .place-ring）
      ctx.beginPath()
      ctx.arc(sx, sy, dotR * 2.6, 0, Math.PI * 2)
      ctx.strokeStyle = withColorAlpha(ink, '73')
      ctx.lineWidth = 0.8
      ctx.stroke()
      ctx.beginPath()
      ctx.arc(sx, sy, dotR, 0, Math.PI * 2)
      ctx.fillStyle = ink
      ctx.fill()

      const flip = p.x > PLACE_FLIP_X || sx + gap + p.name.length * size > this.canvasWidth - 4
      ctx.textAlign = flip ? 'right' : 'left'
      const tx = flip ? sx - gap : sx + gap
      let ty = sy + placeNudgeY(p.name) + size * 0.36
      // 「黄浦」与外滩、「虹口」与鲁迅公园这类：区名标签离 tier 1 地名不到一行字，
      // 把地名让到区名的上/下一行（圆点仍在真实坐标），两张标签就都读得清
      const textW = p.name.length * size
      const boxX1 = flip ? tx - textW : tx
      const boxX2 = flip ? tx : tx + textW
      const boxY1 = ty - size * 0.92
      const boxY2 = ty + size * 0.22
      if (boxX1 < districtBox.x2 + 2 && districtBox.x1 - 2 < boxX2
        && boxY1 < districtBox.y2 + 2 && districtBox.y1 - 2 < boxY2) {
        const labelMid = (districtBox.y1 + districtBox.y2) / 2
        ty = ty <= labelMid ? districtBox.y1 - 3 : districtBox.y2 + size + 2
        ty = Math.min(this.canvasHeight - 2, Math.max(size + 2, ty))
      }
      // 先描纸色再填字：地名压在区界上也读得清（与 HTML 稿 paint-order 同效）
      ctx.lineWidth = 2.4
      ctx.strokeStyle = this.palette.land
      ctx.strokeText(p.name, tx, ty)
      ctx.fillStyle = this.palette.fg
      ctx.fillText(p.name, tx, ty)
    }
    ctx.textAlign = 'start'
  }

  /** 比例尺题注：48vp 的线段在屏幕上大约代表多少米 */
  private drawScaleNote(ctx: CanvasRenderingContext2D, scale: number): void {
    const barW = 48
    const barX = this.canvasWidth - barW - 14
    const barY = this.canvasHeight - 18
    ctx.strokeStyle = this.palette.muted
    ctx.lineWidth = 1.4
    ctx.beginPath()
    ctx.moveTo(barX, barY)
    ctx.lineTo(barX + barW, barY)
    ctx.moveTo(barX, barY - 3)
    ctx.lineTo(barX, barY + 3)
    ctx.moveTo(barX + barW, barY - 3)
    ctx.lineTo(barX + barW, barY + 3)
    ctx.stroke()
    const meters = barW / scale * METERS_PER_UNIT
    const label = meters >= 1000 ? `约 ${(Math.round(meters / 100) / 10).toFixed(1)} 公里`
      : `约 ${Math.round(meters / 10) * 10} 米`
    ctx.fillStyle = this.palette.subtle
    ctx.font = '10px sans-serif'
    ctx.textAlign = 'center'
    ctx.fillText(label, barX + barW / 2, barY - 7)
    ctx.textAlign = 'start'
  }

  // ====== 命中判定（逆变换） ======

  private handleTap(localX: number, localY: number): void {
    const data = this.data
    if (data === null || !this.interactive) {
      return
    }
    const s = this.drawScale()
    const mapX = (localX - this.baseX() - this.panX) / s
    const mapY = (localY - this.baseY() - this.panY) / s
    if (mapX < 0 || mapY < 0 || mapX > MAP_GRID_W || mapY > MAP_GRID_H) {
      this.onTapBlank()
      return
    }
    for (const d of data.districts) {
      const bbox = this.bboxFor(d)
      if (mapX < bbox.minX || mapX > bbox.maxX || mapY < bbox.minY || mapY > bbox.maxY) {
        continue
      }
      if (pointInProvince(d.path, mapX, mapY)) {
        this.onPickDistrict(d.id)
        return
      }
    }
    this.onTapBlank()
  }

  // ====== 视图 ======

  build() {
    Stack() {
      Canvas(this.canvasContext)
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette.water)
        .onReady(() => {
          this.draw()
        })
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.canvasWidth = Number(newArea.width)
          this.canvasHeight = Number(newArea.height)
          this.scheduleRedraw()
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
            if (this.touchDownX < 0) {
              return
            }
            const dx = event.touches[0].x - this.touchDownX
            const dy = event.touches[0].y - this.touchDownY
            const duration = Date.now() - this.touchDownTime
            const startX = this.touchDownX
            const startY = this.touchDownY
            this.touchDownX = -1
            this.touchDownY = -1
            if (Math.hypot(dx, dy) <= TAP_MAX_SLOP && duration <= TAP_MAX_DURATION_MS) {
              this.handleTap(startX, startY)
            }
          } else if (event.type === TouchType.Cancel) {
            this.touchDownX = -1
            this.touchDownY = -1
          }
        })
        // pan 走 gesture 通道；双指捏合走 priorityGesture，免得被 distance:5 的单指 pan 抢走
        .gesture(PanGesture({ direction: PanDirection.All, distance: 5 })
          .onActionStart(() => {
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
        .priorityGesture(PinchGesture({ fingers: 2 })
          .onActionStart(() => {
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
              if (next <= ZOOM_MIN + 0.001) {
                this.panX = 0
                this.panY = 0
              } else {
                this.clampView()
              }
              this.syncZoomController()
              this.scheduleRedraw()
            }
          }))

      if (this.showDecorations) {
        this.CompassOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .backgroundColor(this.palette.water)
    .onAppear(() => {
      this.scheduleRedraw()
    })
  }

  @Builder
  CompassOverlay() {
    Column() {
      Text('N')
        .fontSize(10)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.muted)
      // 指针用 SymbolGlyph 而不是 CSS 三角：颜色能跟着主题走，深浅色都不发灰
      SymbolGlyph($r('sys.symbol.arrowtriangle_up_fill'))
        .fontSize(13)
        .fontColor([this.palette.chineseInk])
    }
    .width(34)
    .height(40)
    .borderRadius(11)
    .backgroundColor(withColorAlpha(this.palette.surface, 'D9'))
    .border({ width: 1, color: withColorAlpha(this.palette.border, 'B3') })
    .justifyContent(FlexAlign.Center)
    .position({ x: Math.max(8, this.canvasWidth - 44), y: 9 })
    .accessibilityText('正北方向')
  }
}

/**
 * 市中心四区的标签错身量（屏幕 vp）：只动文字，质心锚点不动。
 * 16 个区名全开时，静安 / 虹口 / 杨浦三张两字标签的锚点相距不到 14vp，必须上下让开。
 */
function districtLabelNudgeY(districtId: string): number {
  if (districtId === '310106') {
    return -20 // 静安：让到普陀 / 虹口之间
  }
  if (districtId === '310110') {
    return 26 // 杨浦：压到虹口下方
  }
  return 0
}

/** 杨浦同时右移，避开「黄浦」的标签（1.55× 时两行只差 12.6vp） */
function districtLabelNudgeX(districtId: string): number {
  return districtId === '310110' ? 10 : 0
}

/** 三对相距不到 1km 的地名：只把字上下错开，圆点仍是真实坐标 */
function placeNudgeY(name: string): number {
  if (name === '苏州河') {
    return -7
  }
  if (name === '和平公园' || name === '松江大学城') {
    return 7
  }
  return 0
}

/**
 * 把 a 以 t 的比例混进 b（t=0 全 a，t=1 全 b）。只处理 #RRGGBB；
 * 颜色读不懂时原样返回，宁可不降档也不要画出随机色。
 */
function mixHex(a: string, b: string, t: number): string {
  const pa = parseHex(a)
  const pb = parseHex(b)
  if (pa.length !== 3 || pb.length !== 3) {
    return a
  }
  const out: number[] = []
  for (let i = 0; i < 3; i++) {
    out.push(Math.round(pa[i] + (pb[i] - pa[i]) * t))
  }
  let hex = '#'
  for (const c of out) {
    const part = Math.min(255, Math.max(0, c)).toString(16)
    hex += part.length < 2 ? `0${part}` : part
  }
  return hex
}

function parseHex(color: string): number[] {
  const out: number[] = []
  if (color.length !== 7 || color.charAt(0) !== '#') {
    return out
  }
  for (let i = 1; i < 7; i += 2) {
    const v = parseInt(color.substring(i, i + 2), 16)
    if (isNaN(v)) {
      return []
    }
    out.push(v)
  }
  return out
}
