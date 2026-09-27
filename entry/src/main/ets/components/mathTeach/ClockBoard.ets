import { clockAngles, ClockAngles } from '../../utils/MathTeachBoards'
import { curves } from '@kit.ArkUI'
import { KIDS_MATH_INK, KIDS_ACCENT, KIDS_MATH } from '../kids/KidsBrandTokens'
import { withColorAlpha } from '../../utils/ColorAlphaUtils'

@ComponentV2
export struct ClockBoard {
  @Param hour: number = 9
  @Param minute: number = 30
  @Param readonly: boolean = false
  @Local curH: number = 9
  @Local curM: number = 0
  @Event onInteract: () => void = () => {}

  aboutToAppear(): void {
    this.curH = this.hour
    this.curM = this.minute
  }

  private angles(): ClockAngles {
    return clockAngles(this.curH, this.curM)
  }

  private hourSeq(): number[] {
    const arr: number[] = []
    for (let h = 1; h <= 12; h++) { arr.push(h) }
    return arr
  }

  private numX(h: number): number {
    const rad: number = (h * 30 - 90) * Math.PI / 180
    return 84 + 60 * Math.cos(rad) - 8
  }

  private numY(h: number): number {
    const rad: number = (h * 30 - 90) * Math.PI / 180
    return 84 + 60 * Math.sin(rad) - 9
  }

  private stepHour(delta: number): void {
    if (this.readonly) { return }
    const next: number = delta > 0 ? this.curH % 12 + 1 : (this.curH + 10) % 12 + 1
    if (next !== this.curH) {
      this.curH = next
      this.onInteract()
    }
  }

  private setHalf(half: boolean): void {
    if (this.readonly) { return }
    const m: number = half ? 30 : 0
    if (m !== this.curM) {
      this.curM = m
      this.onInteract()
    }
  }

  private timeText(): string {
    if (this.curM === 0) {
      return this.curH + ' 时整 · 短针指 ' + this.curH + '、长针指 12'
    }
    return this.curH + ' 时 30 分（半点）· 短针在两个数中间、长针指 6'
  }

  build() {
    Column({ space: 12 }) {
      Stack() {
        Circle().width(168).height(168).fill(Color.White).stroke(KIDS_MATH_INK).strokeWidth(3)
        ForEach(this.hourSeq(), (h: number) => {
          Text(h.toString()).fontSize(13).fontWeight(FontWeight.Medium).fontColor(KIDS_MATH_INK)
            .position({ x: this.numX(h), y: this.numY(h) })
        }, (h: number) => 'h' + h.toString())
        Rect({ width: 8, height: 48 }).fill(KIDS_MATH_INK).borderRadius(4)
          .position({ x: 80, y: 36 })
          .rotate({ angle: this.angles().hourDeg, centerX: '50%', centerY: '100%' })
          .animation({ curve: curves.springMotion(0.35, 0.85) })
        Rect({ width: 6, height: 64 }).fill(KIDS_ACCENT).borderRadius(3)
          .position({ x: 81, y: 20 })
          .rotate({ angle: this.angles().minuteDeg, centerX: '50%', centerY: '100%' })
          .animation({ curve: curves.springMotion(0.35, 0.85) })
        Circle().width(10).height(10).fill(KIDS_MATH_INK).position({ x: 79, y: 79 })
      }
      .width(168).height(168)

      Text(this.timeText())
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
        .textAlign(TextAlign.Center).width('100%')

      if (!this.readonly) {
        Row({ space: 10 }) {
          Button('时 −').width(60).height(40)
            .backgroundColor(withColorAlpha(KIDS_MATH, '26')).fontColor(KIDS_MATH_INK)
            .accessibilityText('减少一小时')
            .onClick(() => { this.stepHour(-1) })
          Button('时 +').width(60).height(40)
            .backgroundColor(withColorAlpha(KIDS_MATH, '26')).fontColor(KIDS_MATH_INK)
            .accessibilityText('增加一小时')
            .onClick(() => { this.stepHour(1) })
          Button('整点').width(64).height(40)
            .backgroundColor(withColorAlpha(KIDS_MATH, '26')).fontColor(KIDS_MATH_INK)
            .accessibilityText('设置为整点')
            .onClick(() => { this.setHalf(false) })
          Button('半点').width(64).height(40)
            .backgroundColor(withColorAlpha(KIDS_MATH, '26')).fontColor(KIDS_MATH_INK)
            .accessibilityText('设置为半点')
            .onClick(() => { this.setHalf(true) })
        }
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
