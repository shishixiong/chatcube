// entry/src/main/ets/components/map/MapPuzzleBoard.ets
/**
 * MapPuzzleBoard - 拼图棋盘（map_puzzle, spec 2026-10-26 §9.1）
 *
 * 一张白纸地图：只画本局省份的「凹槽」（虚线 + 8% 底色），拼对后原地变成实色省份。
 * 棋盘自动聚焦到本局省份的并集区域（东北 3 省不该只有全国图 1/8 大），
 * 变换由 utils/MapPuzzleLayout.computePuzzleTransform 统一给出，落点判定用同一份变换反算，
 * 保证「看到的」和「判到的」是同一个坐标系。
 *
 * 纯展示 + 点击回报，不持有游戏状态（状态全在 MapPuzzleCard）。
 */

import { getAppUiState } from '../../state/AppUiState'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'
import { ChinaMapData, ChinaProvince } from '../../utils/ChinaMapData'
import { parseProvincePolygons } from '../../utils/ChinaMapGeometry'
import { MapTransform, mapToScreen } from '../../utils/ChinaMapTransform'
import { computePuzzleTransform } from '../../utils/MapPuzzleLayout'
import { getMapAtlasPalette, MapAtlasPalette } from './MapAtlasTokens'

/** 坐标纸网格（与 ChinaMapStage 同一视觉，间距略小以贴合棋盘尺寸） */
const GRID_STEP: number = 29
/** 点击判定上限：位移 12vp / 按住 350ms */
const TAP_MOVE_LIMIT: number = 12
const TAP_TIME_LIMIT: number = 350

@ComponentV2
export struct MapPuzzleBoard {
  @Param data: ChinaMapData | null = null
  @Param targets: ChinaProvince[] = []
  @Param placedIds: string[] = []
  @Param hintId: string = ''
  /** 提示序号：同一块连续提示时 hintId 不变，靠它触发重新呼吸 */
  @Param hintSeq: number = 0
  @Param completed: boolean = false
  @Event onBoardTap: (boardX: number, boardY: number) => void = () => {}

  @Local boardWidth: number = 0
  @Local boardHeight: number = 0
  /** 提示呼吸：1 常态，0.35 暗态；由 startHintPulse 驱动 */
  @Local hintAlpha: number = 1

  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  )
  private polygonCache: Map<string, number[][][]> = new Map()
  private hintTimerId: number = -1
  private touchDownX: number = -1
  private touchDownY: number = -1
  private touchDownTime: number = 0

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get palette(): MapAtlasPalette {
    return getMapAtlasPalette(this.isDarkMode)
  }

  aboutToAppear(): void {
    if (this.hintId !== '') {
      this.startHintPulse()
    }
  }

  aboutToDisappear(): void {
    this.stopHintPulse()
  }

  @Monitor('placedIds', 'targets', 'hintId', 'hintSeq', 'completed', 'data')
  onStateChanged(): void {
    if (this.hintId !== '') {
      this.startHintPulse()
    }
    this.redraw()
  }

  // ====== 提示呼吸 ======

  private startHintPulse(): void {
    this.stopHintPulse()
    this.hintAlpha = 1
    let ticks = 0
    this.hintTimerId = setInterval(() => {
      ticks += 1
      this.hintAlpha = ticks % 2 === 0 ? 1 : 0.35
      this.redraw()
      if (ticks >= 6) {
        this.stopHintPulse()
        this.hintAlpha = 1
        this.redraw()
      }
    }, 260)
  }

  private stopHintPulse(): void {
    if (this.hintTimerId >= 0) {
      clearInterval(this.hintTimerId)
      this.hintTimerId = -1
    }
  }

  // ====== 变换 ======

  private boardTransform(): MapTransform {
    return computePuzzleTransform(this.targets, this.boardWidth, this.boardHeight)
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

  private isPlaced(p: ChinaProvince): boolean {
    return this.placedIds.indexOf(p.id) >= 0
  }

  // ====== 绘制 ======

  private redraw(): void {
    if (this.boardWidth <= 0 || this.boardHeight <= 0) {
      return
    }
    const ctx = this.canvasContext
    const w = this.boardWidth
    const h = this.boardHeight
    ctx.clearRect(0, 0, w, h)
    this.drawPaper(ctx, w, h)
    if (this.targets.length === 0) {
      return
    }
    const t = this.boardTransform()
    // 先空槽后已拼：已拼的省份压在上面，边缘不被虚线盖住
    for (const p of this.targets) {
      if (!this.isPlaced(p)) {
        this.drawSlot(ctx, p, t, p.id === this.hintId && this.hintId !== '')
      }
    }
    for (const p of this.targets) {
      if (this.isPlaced(p)) {
        this.drawPlaced(ctx, p, t)
      }
    }
  }

  /** 纸张底：暖米色 + 细网格 */
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

  private traceProvince(ctx: CanvasRenderingContext2D, p: ChinaProvince, t: MapTransform): void {
    const rings = this.polygonsFor(p.path)
    if (rings.length === 0) {
      return
    }
    ctx.beginPath()
    for (const ring of rings) {
      for (let i = 0; i < ring.length; i++) {
        const screen = mapToScreen(t, ring[i][0], ring[i][1])
        if (i === 0) {
          ctx.moveTo(screen.x, screen.y)
        } else {
          ctx.lineTo(screen.x, screen.y)
        }
      }
      ctx.closePath()
    }
  }

  /** 空槽：浅底色 + 虚线外框（提示时换成高亮虚线并参与呼吸） */
  private drawSlot(ctx: CanvasRenderingContext2D, p: ChinaProvince,
    t: MapTransform, isHint: boolean): void {
    const palette = this.palette
    this.traceProvince(ctx, p, t)
    ctx.fillStyle = withColorAlpha(palette.land, this.isDarkMode ? '22' : '33')
    ctx.fill('evenodd')
    ctx.setLineDash([4, 3])
    if (isHint) {
      const hinted = withColorAlpha(palette.selectedLine, this.hintAlpha >= 1 ? 'ff' : '66')
      ctx.strokeStyle = hinted
      ctx.lineWidth = 2.4
    } else {
      ctx.strokeStyle = withColorAlpha(palette.line, '99')
      ctx.lineWidth = 1.2
    }
    ctx.stroke()
    ctx.setLineDash([])
  }

  /** 已拼：实色省份 + 实线边界 */
  private drawPlaced(ctx: CanvasRenderingContext2D, p: ChinaProvince, t: MapTransform): void {
    const palette = this.palette
    this.traceProvince(ctx, p, t)
    ctx.fillStyle = this.completed ? palette.visited : palette.land
    ctx.fill('evenodd')
    ctx.strokeStyle = palette.line
    ctx.lineWidth = 1.4
    ctx.stroke()
  }

  // ====== 交互 ======

  private handleTouch(event: TouchEvent): void {
    if (event.touches.length === 0) {
      return
    }
    const touch = event.touches[0]
    if (event.type === TouchType.Down) {
      this.touchDownX = touch.x
      this.touchDownY = touch.y
      this.touchDownTime = Date.now()
      return
    }
    if (event.type !== TouchType.Up) {
      return
    }
    if (this.touchDownX < 0) {
      return
    }
    const moved = Math.abs(touch.x - this.touchDownX) + Math.abs(touch.y - this.touchDownY)
    const elapsed = Date.now() - this.touchDownTime
    const downX = this.touchDownX
    const downY = this.touchDownY
    this.touchDownX = -1
    this.touchDownY = -1
    if (moved > TAP_MOVE_LIMIT || elapsed > TAP_TIME_LIMIT) {
      return
    }
    this.onBoardTap(downX, downY)
  }

  build() {
    Canvas(this.canvasContext)
      .id('mapPuzzleBoard')
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.redraw()
      })
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.boardWidth = Number(newValue.width)
        this.boardHeight = Number(newValue.height)
        this.redraw()
      })
      .onTouch((event: TouchEvent) => {
        this.handleTouch(event)
      })
  }
}
