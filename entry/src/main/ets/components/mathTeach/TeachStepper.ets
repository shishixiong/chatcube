import { KIDS_MATH, KIDS_MATH_INK, KIDS_MUTED } from '../kids/KidsBrandTokens'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'

@ComponentV2
export struct TeachStepper {
  @Param label: string = ''
  @Param value: number = 0
  @Param minValue: number = 0
  @Param maxValue: number = 20
  @Event onChange: (v: number) => void = (_v: number) => {}

  private tap(delta: number): void {
    const next: number = Math.min(this.maxValue, Math.max(this.minValue, this.value + delta))
    if (next !== this.value) {
      this.onChange(next)
    }
  }

  build() {
    Row({ space: 10 }) {
      Text(this.label).fontSize(14).fontColor(KIDS_MUTED)
      Button('-')
        .width(44).height(44)
        .type(ButtonType.Capsule)
        .backgroundColor(withColorAlpha(KIDS_MATH, '26')).fontColor(KIDS_MATH_INK).fontSize(20)
        .accessibilityText('减少一个')
        .onClick(() => { this.tap(-1) })
      Text(this.value.toString())
        .fontSize(18).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
        .minWidth(28).textAlign(TextAlign.Center)
      Button('+')
        .width(44).height(44)
        .type(ButtonType.Capsule)
        .backgroundColor(withColorAlpha(KIDS_MATH, '26')).fontColor(KIDS_MATH_INK).fontSize(20)
        .accessibilityText('增加一个')
        .onClick(() => { this.tap(1) })
    }
    .padding(4)
    .borderRadius(24)
    .backgroundColor(withColorAlpha(KIDS_MATH, '15'))
    .alignItems(VerticalAlign.Center)
  }
}
