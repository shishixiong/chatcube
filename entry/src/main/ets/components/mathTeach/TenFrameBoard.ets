import { KIDS_MATH_INK, KIDS_ACCENT, KIDS_MUTED, KIDS_BORDER } from '../kids/KidsBrandTokens'

@ComponentV2
export struct TenFrameBoard {
  @Param a: number = 9
  @Param b: number = 5
  @Param readonly: boolean = false
  @Local frameDots: number = 0
  @Local outside: number = 0
  @Event onInteract: () => void = () => {}

  aboutToAppear(): void {
    this.frameDots = this.a
    this.outside = this.b
  }

  private seq(n: number): number[] {
    const arr: number[] = []
    for (let i = 0; i < n; i++) { arr.push(i) }
    return arr
  }

  private borrow(): void {
    if (this.readonly || this.outside < 1 || this.frameDots >= 10) { return }
    this.onInteract()
    this.frameDots += 1
    this.outside -= 1
  }

  private eqText(): string {
    if (this.frameDots < 10) {
      return `${this.a} + ${this.b}：框里还差 ${10 - this.frameDots} 个凑满 10`
    }
    return `${this.a} + ${10 - this.a} = 10，10 + ${this.outside} = ${10 + this.outside}`
  }

  @Builder
  Cell(occupied: boolean) {
    Stack() {
      if (occupied) {
        Circle().width(26).height(26).fill(KIDS_MATH_INK)
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ x: 0.2, y: 0.2 }))
            .animation({ duration: 300, curve: Curve.EaseOut }))
      }
    }
    .width(40).height(40)
    .border({ width: 1.5, style: BorderStyle.Dashed, color: KIDS_BORDER, radius: 8 })
  }

  build() {
    Column({ space: 12 }) {
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          ForEach(this.seq(5), (i: number) => {
            this.Cell(i < this.frameDots)
          }, (i: number) => 'c1_' + i.toString())
        }
        Row({ space: 6 }) {
          ForEach(this.seq(5), (i: number) => {
            this.Cell(i + 5 < this.frameDots)
          }, (i: number) => 'c2_' + i.toString())
        }
      }

      Row({ space: 6 }) {
        ForEach(this.seq(this.outside), (i: number) => {
          Circle().width(16).height(16).fill(KIDS_ACCENT)
        }, (i: number) => 'o' + i.toString())
        Text(this.outside > 0 ? '框外还有 ' + this.outside + ' 个' : '框外空了')
          .fontSize(12).fontColor(KIDS_MUTED)
      }

      Text(this.eqText())
        .fontSize(15).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
        .textAlign(TextAlign.Center).width('100%')

      if (!this.readonly && this.frameDots < 10) {
        Button('借一个进框')
          .width(140).height(44)
          .backgroundColor(KIDS_MATH_INK).fontSize(15)
          .onClick(() => { this.borrow() })
      }
    }
    .alignItems(HorizontalAlign.Center)
    .width('100%')
  }
}
