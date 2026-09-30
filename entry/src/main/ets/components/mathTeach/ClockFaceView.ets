import { clockAngles, ClockAngles } from '../../utils/MathTeachBoards'
import {
  KIDS_MATH, KIDS_MATH_INK, KIDS_BORDER,
  KIDS_SURFACE, KIDS_FG, KIDS_SUBTLE, KIDS_ACCENT
} from '../kids/KidsBrandTokens'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'

/**
 * ClockFaceView - 纯展示时钟盘面（math_quiz time / elapsed_time 题型用）
 *
 * 视觉与 ClockBoard（math_teach · clock 模式）的钟面同源：
 * 淡橙外环 + 奶油盘面 + 60 根大小刻度 + 粗短时针 + 双色分针 + 双层轴心。
 * 与 ClockBoard 的差异：无拖拽 / 图层聚焦 / 引导淡化，纯静态展示；
 * 新增 box 参数按 216 基准盒等比缩放（elapsed_time 双钟面用 120）。
 * 固定 kids 品牌色，不随主题/暗色切换（ClockBoard 同款约定）。
 */

// 几何基准（与 ClockBoard 同源）：Stack 盒 216 含淡橙外环；face 圆 200 居中于 8,8
const BASE_BOX: number = 216
const BASE_FACE: number = 200
const BASE_C: number = 108
const BASE_RING_PAD: number = 8
const BASE_NUM_R: number = 72

/** 刻度线端点（12 点方向为 0°，顺时针均分 60 根） */
interface TickSpec {
  x1: number
  y1: number
  x2: number
  y2: number
  major: boolean
}

@ComponentV2
export struct ClockFaceView {
  @Param hour: number = 12
  @Param minute: number = 0
  /** 盒子边长（含外环），按 216 基准等比缩放 */
  @Param box: number = 216

  // 刻度静态几何（aboutToAppear 建一次；box 在调用点写死，实例复用时不会变）
  private tickSpecs: TickSpec[] = []

  aboutToAppear(): void {
    this.tickSpecs = this.buildTickSpecs()
  }

  private s(): number {
    return this.box / BASE_BOX
  }

  private buildTickSpecs(): TickSpec[] {
    const s: number = this.s()
    const c: number = BASE_C * s
    const arr: TickSpec[] = []
    for (let i = 0; i < 60; i++) {
      const a: number = i * 6 * Math.PI / 180
      const r1: number = (i % 5 === 0 ? 84 : 90) * s
      const r2: number = 96 * s
      const spec: TickSpec = {
        x1: c + r1 * Math.sin(a),
        y1: c - r1 * Math.cos(a),
        x2: c + r2 * Math.sin(a),
        y2: c - r2 * Math.cos(a),
        major: i % 5 === 0
      }
      arr.push(spec)
    }
    return arr
  }

  // 12 → 0 走钟面语义（clockAngles 内部再做 h%12）
  private hourPart(): number {
    const h: number = ((this.hour % 12) + 12) % 12
    return h === 0 ? 12 : h
  }

  private handAngles(): ClockAngles {
    return clockAngles(this.hourPart(), this.minute)
  }

  private hourSeq(): number[] {
    const arr: number[] = []
    for (let h = 1; h <= 12; h++) { arr.push(h) }
    return arr
  }

  private numX(h: number): number {
    const s: number = this.s()
    const rad: number = (h * 30 - 90) * Math.PI / 180
    return BASE_C * s + BASE_NUM_R * s * Math.cos(rad) - 6 * s
  }

  private numY(h: number): number {
    const s: number = this.s()
    const rad: number = (h * 30 - 90) * Math.PI / 180
    return BASE_C * s + BASE_NUM_R * s * Math.sin(rad) - 9 * s
  }

  build() {
    Stack() {
      Circle().width(this.box).height(this.box).fill(withColorAlpha(KIDS_ACCENT, '2E'))
      Circle().width(BASE_FACE * this.s()).height(BASE_FACE * this.s()).fill(KIDS_SURFACE)
        .stroke(withColorAlpha(KIDS_ACCENT, '66'))
        .strokeWidth(Math.max(2, 3 * this.s()))
        .position({ x: BASE_RING_PAD * this.s(), y: BASE_RING_PAD * this.s() })

      Stack() {
        ForEach(this.tickSpecs, (t: TickSpec) => {
          Line({ width: this.box, height: this.box })
            .startPoint([t.x1, t.y1]).endPoint([t.x2, t.y2])
            .stroke(t.major ? KIDS_SUBTLE : KIDS_BORDER)
            .strokeWidth(t.major ? Math.max(1.5, 3 * this.s()) : Math.max(1, 1.6 * this.s()))
            .strokeLineCap(LineCapStyle.Round)
        }, (t: TickSpec, idx: number) => 'tick' + idx.toString())
      }
      .width(this.box).height(this.box)

      Stack() {
        ForEach(this.hourSeq(), (h: number) => {
          Text(h.toString())
            .fontSize(Math.max(8, 15 * this.s()))
            .fontWeight(FontWeight.Bold).fontColor(KIDS_FG)
            .position({ x: this.numX(h), y: this.numY(h) })
        }, (h: number) => 'num' + h.toString())
      }
      .width(this.box).height(this.box)

      // 时针（短粗，KIDS_FG）；旋转支点 '50%'/'100%' 相对自身尺寸（ClockBoard 同款）
      Rect({ width: 9 * this.s(), height: 50 * this.s() }).fill(KIDS_FG)
        .borderRadius(4.5 * this.s())
        .position({ x: BASE_C * this.s() - 4.5 * this.s(), y: BASE_C * this.s() - 50 * this.s() })
        .rotate({ angle: this.handAngles().hourDeg, centerX: '50%', centerY: '100%' })

      // 分针（双色：KIDS_MATH 尖段 + KIDS_MATH_INK 主段）
      Column() {
        Rect({ width: 7 * this.s(), height: 22 * this.s() }).fill(KIDS_MATH)
          .borderRadius(3.5 * this.s())
        Rect({ width: 7 * this.s(), height: 52 * this.s() }).fill(KIDS_MATH_INK)
          .borderRadius(3.5 * this.s())
      }
      .position({ x: BASE_C * this.s() - 3.5 * this.s(), y: BASE_C * this.s() - 74 * this.s() })
      .rotate({ angle: this.handAngles().minuteDeg, centerX: '50%', centerY: '100%' })

      // 双层轴心
      Circle().width(12 * this.s()).height(12 * this.s()).fill(KIDS_FG)
        .position({ x: BASE_C * this.s() - 6 * this.s(), y: BASE_C * this.s() - 6 * this.s() })
      Circle().width(4.5 * this.s()).height(4.5 * this.s()).fill(KIDS_SURFACE)
        .position({ x: BASE_C * this.s() - 2.25 * this.s(), y: BASE_C * this.s() - 2.25 * this.s() })
    }
    .width(this.box).height(this.box)
  }
}
