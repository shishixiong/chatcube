import { numberLineHops, NumberLineHops } from '../../utils/MathTeachBoards'
import { KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED } from '../kids/KidsBrandTokens'

const NL_W: number = 280
const NL_X0: number = 14
const NL_GAP: number = (NL_W - 28) / 20
const NL_Y: number = 120

@ComponentV2
export struct NumberLineBoard {
  @Param start: number = 9
  @Param step: number = 5
  @Param readonly: boolean = false
  @Local hopStage: number = 0
  @Event onInteract: () => void = () => {}
  private timerId: number = -1

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId)
      this.timerId = -1
    }
  }

  private hops(): NumberLineHops {
    return numberLineHops(this.start, this.step)
  }

  private x(idx: number): number {
    return NL_X0 + idx * NL_GAP
  }

  private arcPath(fromIdx: number, toIdx: number): string {
    const x0: number = this.x(fromIdx)
    const x1: number = this.x(toIdx)
    const cx: number = (x0 + x1) / 2
    return `M ${x0} ${NL_Y} Q ${cx} 58 ${x1} ${NL_Y}`
  }

  private tokenX(): number {
    if (this.hopStage === 0) { return this.x(this.start) }
    if (this.hopStage === 1) { return this.x(10) }
    return this.x(this.hops().sum)
  }

  private eqText(): string {
    const h: NumberLineHops = this.hops()
    if (this.hopStage === 0) {
      return `${this.start} + ${this.step}：先跳到 10 还差 ${h.firstHop}`
    }
    if (this.hopStage === 1) {
      return `${this.start} + ${h.firstHop} = 10`
    }
    return `${this.start} + ${h.firstHop} = 10，10 + ${h.secondHop} = ${h.sum}`
  }

  private tickSeq(): number[] {
    const arr: number[] = []
    for (let i = 0; i <= 20; i++) { arr.push(i) }
    return arr
  }

  private startHop(): void {
    if (this.readonly || this.hopStage > 0) { return }
    this.onInteract()
    this.hopStage = 1
    this.timerId = setTimeout(() => {
      this.hopStage = 2
    }, 600)
  }

  build() {
    Column({ space: 12 }) {
      Stack() {
        Rect({ width: NL_W - 28, height: 2 }).fill(KIDS_MUTED)
          .position({ x: NL_X0, y: NL_Y })
        ForEach(this.tickSeq(), (i: number) => {
          Column() {
            if (i % 5 === 0) {
              Text(i.toString()).fontSize(10).fontColor(KIDS_MUTED)
            }
            Rect({ width: i % 5 === 0 ? 2 : 1, height: i % 5 === 0 ? 10 : 6 })
              .fill(i === 10 ? KIDS_ACCENT : KIDS_MUTED)
          }
          .position({ x: this.x(i) - 1, y: NL_Y - (i % 5 === 0 ? 26 : 12) })
        }, (i: number) => 't' + i.toString())

        if (this.hopStage >= 1) {
          Path().commands(this.arcPath(this.start, 10))
            .stroke(KIDS_MATH_INK).strokeWidth(2.5).fillOpacity(0)
            .width(NL_W).height(170)
          Text('+' + this.hops().firstHop)
            .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
            .position({ x: (this.x(this.start) + this.x(10)) / 2 - 8, y: 66 })
        }
        if (this.hopStage >= 2) {
          Path().commands(this.arcPath(10, this.hops().sum))
            .stroke(KIDS_ACCENT).strokeWidth(2.5).fillOpacity(0)
            .width(NL_W).height(170)
          Text('+' + this.hops().secondHop)
            .fontSize(12).fontWeight(FontWeight.Bold).fontColor(KIDS_ACCENT)
            .position({ x: (this.x(10) + this.x(this.hops().sum)) / 2 - 10, y: 66 })
        }

        Rect({ width: 22, height: 22 }).fill(KIDS_MATH_INK).borderRadius(6)
          .position({ x: this.tokenX() - 11, y: NL_Y + 12 })
          .animation({ duration: 500, curve: Curve.EaseInOut })
      }
      .width(NL_W).height(170)

      Text(this.eqText())
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
        .textAlign(TextAlign.Center).width('100%')

      if (this.hopStage === 0 && !this.readonly) {
        Button('凑十跳')
          .width(140).height(44)
          .backgroundColor(KIDS_MATH_INK).fontSize(15)
          .onClick(() => { this.startHop() })
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
