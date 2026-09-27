import { balanceTilt } from '../../utils/MathTeachBoards'
import { curves } from '@kit.ArkUI'
import { KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED } from '../kids/KidsBrandTokens'
import { TeachStepper } from './TeachStepper'

@ComponentV2
export struct BalanceBoard {
  @Param left: number = 9
  @Param right: number = 5
  @Param readonly: boolean = false
  @Local curLeft: number = 0
  @Local curRight: number = 0
  @Event onInteract: () => void = () => {}

  aboutToAppear(): void {
    this.curLeft = this.left
    this.curRight = this.right
  }

  private tilt(): number {
    return balanceTilt(this.curLeft, this.curRight)
  }

  private symbol(): string {
    if (this.curLeft > this.curRight) { return '>' }
    if (this.curLeft < this.curRight) { return '<' }
    return '='
  }

  // 响应式关键：数量在 Builder 体内按 isLeft 判别后直接读 this.curLeft / this.curRight
  // （isLeft 是常量判别参），不能在调用点传 this.curLeft 数值快照——快照传参会断响应式，
  // 步进后盘子数字不刷新（同 TenFrameBoard Cell 的修复约定）。
  @Builder
  Pan(color: string, isLeft: boolean) {
    Column({ space: 4 }) {
      Text((isLeft ? this.curLeft : this.curRight) + ' 个').fontSize(13).fontWeight(FontWeight.Bold).fontColor(color)
      Column()
        .width(56).height(4).borderRadius(2).backgroundColor(color)
    }
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column({ space: 12 }) {
      Stack() {
        Polygon({ width: 28, height: 20 })
          .points([[14, 0], [28, 20], [0, 20]])
          .fill(KIDS_MUTED)
          .position({ x: 106, y: 78 })

        Row() {
          this.Pan(KIDS_MATH_INK, true)
          Rect({ width: 130, height: 5 }).fill(KIDS_MATH_INK).borderRadius(2)
          this.Pan(KIDS_ACCENT, false)
        }
        .alignItems(VerticalAlign.Center)
        .rotate({ angle: this.tilt(), centerX: '50%', centerY: '50%' })
        .animation({ curve: curves.springMotion(0.35, 0.85) })
      }
      .width(240).height(110)

      Text(this.curLeft + ' ' + this.symbol() + ' ' + this.curRight)
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)

      if (!this.readonly) {
        Column({ space: 8 }) {
          TeachStepper({
            label: '左盘', value: this.curLeft, minValue: 1, maxValue: 20,
            onChange: (v: number): void => {
              if (v !== this.curLeft) { this.curLeft = v; this.onInteract() }
            }
          })
          TeachStepper({
            label: '右盘', value: this.curRight, minValue: 1, maxValue: 20,
            onChange: (v: number): void => {
              if (v !== this.curRight) { this.curRight = v; this.onInteract() }
            }
          })
        }
        .alignItems(HorizontalAlign.Center)
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
