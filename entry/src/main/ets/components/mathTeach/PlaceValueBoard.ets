import { canBundle } from '../../utils/MathTeachBoards'
import { KIDS_MATH, KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED } from '../kids/KidsBrandTokens'
import { TeachStepper } from './TeachStepper'

@ComponentV2
export struct PlaceValueBoard {
  @Param tens: number = 1
  @Param ones: number = 7
  @Param readonly: boolean = false
  @Local curTens: number = 0
  @Local curOnes: number = 0
  @Event onInteract: () => void = () => {}

  aboutToAppear(): void {
    this.curTens = this.tens
    this.curOnes = this.ones
  }

  private seq(n: number): number[] {
    const arr: number[] = []
    for (let i = 0; i < n; i++) { arr.push(i) }
    return arr
  }

  private bundle(): void {
    if (this.readonly || !canBundle(this.curOnes)) { return }
    this.onInteract()
    this.curTens += 1
    this.curOnes -= 10
  }

  @Builder
  Bundle() {
    Stack() {
      Rect({ width: 36, height: 46 }).fill(KIDS_MATH).borderRadius(6)
      Text('10').fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.White)
    }
  }

  @Builder
  Stick() {
    Rect({ width: 5, height: 46 }).fill(KIDS_MATH_INK).borderRadius(2)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 28 }) {
        Column({ space: 8 }) {
          Text('十位 · 捆').fontSize(12).fontColor(KIDS_MUTED)
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            ForEach(this.seq(this.curTens), (i: number) => {
              this.Bundle()
            }, (i: number) => 'b' + i.toString())
          }.width(160)
          Text(this.curTens + ' 捆').fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
        }
        .alignItems(HorizontalAlign.Center)

        Column({ space: 8 }) {
          Text('个位 · 根').fontSize(12).fontColor(KIDS_MUTED)
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            ForEach(this.seq(this.curOnes), (i: number) => {
              this.Stick()
            }, (i: number) => 's' + i.toString())
          }.width(160)
          Text(this.curOnes + ' 根').fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
        }
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      if (canBundle(this.curOnes) && !this.readonly) {
        Button('10 根捆成一捆')
          .width(160).height(44)
          .backgroundColor(KIDS_ACCENT).fontSize(15)
          .onClick(() => { this.bundle() })
      }

      Text(this.curTens + ' 捆 ' + this.curOnes + ' 根 = ' + (this.curTens * 10 + this.curOnes))
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)

      if (!this.readonly) {
        TeachStepper({
          label: '个位加一根', value: this.curOnes, minValue: 0, maxValue: 19,
          onChange: (v: number): void => {
            if (v !== this.curOnes) {
              this.curOnes = v
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
