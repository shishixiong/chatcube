import { barPercents, BarPercents } from '../../utils/MathTeachBoards'
import { KIDS_MATH_INK, KIDS_ACCENT, KIDS_MATH } from '../kids/KidsBrandTokens'
import { TeachStepper } from './TeachStepper'

@ComponentV2
export struct BarModelBoard {
  @Param partA: number = 9
  @Param partB: number = 5
  @Param readonly: boolean = false
  @Local curA: number = 0
  @Local curB: number = 0
  @Event onInteract: () => void = () => {}

  aboutToAppear(): void {
    this.curA = this.partA
    this.curB = this.partB
  }

  private pcts(): BarPercents {
    return barPercents(this.curA, this.curB)
  }

  private barPct(kind: number): number {
    if (kind === 2) { return 100 }
    if (kind === 0) { return this.pcts().aPct }
    return this.pcts().bPct
  }

  private barLabel(kind: number): string {
    if (kind === 2) { return '一共 ' + (this.curA + this.curB) }
    if (kind === 0) { return '部分 A' }
    return '部分 B'
  }

  // 响应式关键：标签与宽度在 Builder 体内按 kind 判别后直接读 this.curA / this.curB 计算
  // （kind 是常量判别参），不能在调用点传 this.pcts().aPct 百分比快照——快照传参会断响应式，
  // 步进后长条宽度冻结（同 TenFrameBoard Cell 的修复约定）。
  @Builder
  Bar(kind: number, color: string) {
    Row() {
      Text(this.barLabel(kind)).fontSize(11).fontColor(Color.White).maxLines(1)
    }
    .width(this.barPct(kind) * 2.2)
    .height(30)
    .borderRadius(6)
    .backgroundColor(color)
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .animation({ duration: 350, curve: Curve.EaseInOut })
  }

  build() {
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Row() {
          this.Bar(0, KIDS_MATH_INK)
        }.width('100%')
        Row() {
          this.Bar(1, KIDS_ACCENT)
        }.width('100%')
        Row() {
          this.Bar(2, KIDS_MATH)
        }.width('100%')
      }
      .width('100%')

      Text(this.curA + ' + ' + this.curB + ' = ' + (this.curA + this.curB) + '：两条长条拼成的全长就是一共')
        .fontSize(14).fontWeight(FontWeight.Bold).fontColor(KIDS_MATH_INK)
        .textAlign(TextAlign.Center).width('100%')

      if (!this.readonly) {
        Column({ space: 8 }) {
          TeachStepper({
            label: '部分 A', value: this.curA, minValue: 1, maxValue: 9,
            onChange: (v: number): void => {
              if (v !== this.curA) { this.curA = v; this.onInteract() }
            }
          })
          TeachStepper({
            label: '部分 B', value: this.curB, minValue: 1, maxValue: 9,
            onChange: (v: number): void => {
              if (v !== this.curB) { this.curB = v; this.onInteract() }
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
