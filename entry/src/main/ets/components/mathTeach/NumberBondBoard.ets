import { bondSplit } from '../../utils/MathTeachBoards'
import { KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED } from '../kids/KidsBrandTokens'
import { TeachStepper } from './TeachStepper'

@ComponentV2
export struct NumberBondBoard {
  @Param total: number = 9
  @Param readonly: boolean = false
  @Local left: number = 4
  @Event onInteract: () => void = () => {}

  aboutToAppear(): void {
    this.left = Math.floor(this.total / 2)
  }

  private right(): number {
    return bondSplit(this.total, this.left)
  }

  private seq(n: number): number[] {
    const arr: number[] = []
    for (let i = 0; i < n; i++) { arr.push(i) }
    return arr
  }

  @Builder
  Dot(color: string) {
    Circle().width(18).height(18).fill(color)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 6 }) {
        ForEach(this.seq(this.left), (i: number) => {
          this.Dot(KIDS_MATH_INK)
        }, (i: number) => 'l' + i.toString())
        ForEach(this.seq(this.right()), (i: number) => {
          this.Dot(KIDS_ACCENT)
        }, (i: number) => 'r' + i.toString())
        if (this.total < 10) {
          Column() {
            Text('+').fontSize(12).fontColor(KIDS_MUTED)
          }
          .width(18).height(18)
          .justifyContent(FlexAlign.Center)
          .border({ width: 1.5, style: BorderStyle.Dashed, color: KIDS_MUTED, radius: 9 })
        }
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .width('100%')

      Text(this.left + ' 和 ' + this.right() + ' 合起来是 ' + this.total)
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
      if (this.total < 10) {
        Text(this.total + ' 再和 ' + (10 - this.total) + ' 做朋友，就能凑成十')
          .fontSize(13).fontColor(KIDS_MUTED)
      }

      if (!this.readonly) {
        TeachStepper({
          label: '左边圆点', value: this.left, minValue: 0, maxValue: this.total,
          onChange: (v: number): void => {
            if (v !== this.left) {
              this.left = v
              this.onInteract()
            }
          }
        })
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
