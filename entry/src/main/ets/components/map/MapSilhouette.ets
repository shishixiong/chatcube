// entry/src/main/ets/components/map/MapSilhouette.ets
/**
 * MapSilhouette - 省份剪影渲染器（map_quiz 的 shape / compare 题型用）
 *
 * 一块纸底 + 若干个「只有形状、没有底图」的省份，三种排版：
 *  - single: 单个省铺满整块（形状猜省：只给轮廓，不给名字）
 *  - cells:  每省各自铺满自己那一格（面积比较的题面：两块看起来一样大，逼孩子凭记忆判断）
 *  - shared: 所有省共用同一个比例尺并排（面积比较的揭晓：同一个尺子下大小一目了然）
 *
 * 纯展示组件，不持有任何游戏状态；配色沿用 MapAtlasTokens 的纸质地图册皮肤。
 */

import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { ChinaProvince } from '../../utils/ChinaMapData'
import { parseProvincePolygons, provinceBBox } from '../../utils/ChinaMapGeometry'
import { getMapAtlasPalette, MapAtlasPalette } from './MapAtlasTokens'

const GRID_STEP: number = 29
/** 纸边留白（vp） */
const PAD: number = 10

export const SILHOUETTE_LAYOUT_SINGLE: string = 'single'
export const SILHOUETTE_LAYOUT_CELLS: string = 'cells'
export const SILHOUETTE_LAYOUT_SHARED: string = 'shared'

@ComponentV2
export struct MapSilhouette {
  @Param provinces: ChinaProvince[] = []
  /** 与 provinces 一一对应的标签；空字符串 = 该格不画名字 */
  @Param labels: string[] = []
  @Param layout: string = SILHOUETTE_LAYOUT_SINGLE
  /** 高亮某一个省 id（揭晓时用实色，其余灰色）；空 = 全部实色 */
  @Param accentId: string = ''
  @Param showGrid: boolean = true

  @Local canvasWidth: number = 0
  @Local canvasHeight: number = 0

  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  )
  private polygonCache: Map<string, number[][][]> = new Map()

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get palette(): MapAtlasPalette {
    return getMapAtlasPalette(this.isDarkMode)
  }

  @Monitor('provinces', 'labels', 'layout', 'accentId')
  onStateChanged(): void {
    this.redraw()
  }

  private polygonsFor(path: string): number[][][] {
    const cached = this.polygonCache.get(path)
    if (cached !== undefined) {
      return cached
    }
    const rings = parseProvincePolygons(path)
    this.polygonCache.set(path, rings)
    return rings
  }

  // ====== 排版 ======

  /** cells 模式的分格宽；shared/single 也用同一套格宽，保证并排对齐 */
  private cellWidth(): number {
    const count = this.provinces.length === 0 ? 1 : this.provinces.length
    return (this.canvasWidth - PAD * 2) / count
  }

  /** 单省铺满一格的缩放比 */
  private fitScaleIn(p: ChinaProvince, boxW: number, boxH: number): number {
    const box = provinceBBox(p.path)
    const w = Math.max(1, box.maxX - box.minX)
    const h = Math.max(1, box.maxY - box.minY)
    return Math.min(boxW / w, boxH / h)
  }

  /** 本块统一的缩放比：cells 各自算、shared 取全部里最小的那个 */
  private scaleFor(index: number, cellW: number, cellH: number,
    shared: number): number {
    if (shared > 0) {
      return shared
    }
    const p = this.provinces[index]
    return this.fitScaleIn(p, cellW, cellH)
  }

  private sharedScale(cellW: number, cellH: number): number {
    let min = Infinity
    for (let i = 0; i < this.provinces.length; i++) {
      const s = this.fitScaleIn(this.provinces[i], cellW, cellH)
      if (s < min) {
        min = s
      }
    }
    return min === Infinity ? 1 : min
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
    this.drawPaper(ctx, w, h)
    if (this.provinces.length === 0) {
      return
    }
    const shared = this.layout === SILHOUETTE_LAYOUT_SHARED ? this.sharedScale(this.cellWidth(),
      h - PAD * 2) : 0
    for (let i = 0; i < this.provinces.length; i++) {
      const p = this.provinces[i]
      const label = i < this.labels.length ? this.labels[i] : ''
      this.drawCell(ctx, p, label, i, shared)
    }
  }

  private drawPaper(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    const palette = this.palette
    ctx.fillStyle = palette.water
    ctx.fillRect(0, 0, w, h)
    if (!this.showGrid) {
      return
    }
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

  private drawCell(ctx: CanvasRenderingContext2D, p: ChinaProvince, label: string,
    index: number, shared: number): void {
    const palette = this.palette
    const cellW = this.cellWidth()
    const cellX = PAD + cellW * index
    const availableH = this.canvasHeight - PAD * 2
    const scale = this.scaleFor(index, cellW - PAD, availableH, shared)
    const box = provinceBBox(p.path)
    const shapeW = (box.maxX - box.minX) * scale
    const shapeH = (box.maxY - box.minY) * scale
    const offsetX = cellX + (cellW - shapeW) / 2
    const offsetY = PAD + (availableH - shapeH) / 2
    const rings = this.polygonsFor(p.path)
    if (rings.length === 0) {
      return
    }
    ctx.beginPath()
    for (const ring of rings) {
      for (let i = 0; i < ring.length; i++) {
        const x = offsetX + (ring[i][0] - box.minX) * scale
        const y = offsetY + (ring[i][1] - box.minY) * scale
        if (i === 0) {
          ctx.moveTo(x, y)
        } else {
          ctx.lineTo(x, y)
        }
      }
      ctx.closePath()
    }
    const dimmed = this.accentId !== '' && this.accentId !== p.id
    ctx.fillStyle = dimmed
      ? withColorAlpha(palette.land, this.isDarkMode ? '22' : '33')
      : palette.land
    ctx.fill('evenodd')
    ctx.strokeStyle = dimmed ? withColorAlpha(palette.line, '88') : palette.line
    ctx.lineWidth = 1.4
    ctx.stroke()
    if (label !== '') {
      ctx.font = '600 14px sans-serif'
      ctx.fillStyle = dimmed ? withColorAlpha(palette.fg, '88') : palette.fg
      ctx.textAlign = 'center'
      ctx.fillText(label, cellX + cellW / 2, this.canvasHeight - 6)
      ctx.textAlign = 'start'
    }
  }

  build() {
    Canvas(this.canvasContext)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.redraw()
      })
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.canvasWidth = Number(newValue.width)
        this.canvasHeight = Number(newValue.height)
        this.redraw()
      })
  }
}
