// components/verticalMath/VerticalMathStepNarrator.ets
// Single-line step narrator for vertical-math walk-through.
// Renders the operation label as a static small title and a single
// animated line below it showing the current step's title + narration.
// Sits above VerticalMathBoard in VerticalMathCard's layout.

import { VERTICAL_MATH_NARRATOR_BG } from '../../utils/VerticalMathColors'
import { VerticalMathStep } from '../../utils/VerticalMathSolver'

@ComponentV2
export struct VerticalMathStepNarrator {
  @Param steps: VerticalMathStep[] = []
  @Param visibleStepCount: number = 0
  @Param operationLabel: string = ''

  private getCurrentStep(): VerticalMathStep | null {
    if (this.steps.length === 0) return null
    const idx = Math.max(0, Math.min(this.visibleStepCount - 1, this.steps.length - 1))
    return this.steps[idx]
  }

  private getNarrationLine(): string {
    if (this.visibleStepCount <= 0 || this.steps.length === 0) {
      return '点击下方“下一步 →”开始查看'
    }
    const step = this.getCurrentStep()
    if (step === null) {
      return '点击下方“下一步 →”开始查看'
    }
    const title = step.title.trim()
    const narration = step.narration.trim()
    if (title !== '' && narration !== '') {
      return `${title}：${narration}`
    }
    if (title !== '') return title
    if (narration !== '') return narration
    return '点击下方“下一步 →”开始查看'
  }

  build() {
    Column() {
      Text(this.operationLabel)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#665b84')
        .margin({ bottom: 6 })
      Text(this.getNarrationLine())
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#21153f')
        .lineHeight(22)
        .width('100%')
        // .id() changes per step force ArkUI V2 to treat each render as a
        // fresh component instance, so the .transition() below actually
        // fires when visibleStepCount changes (insert/delete, not attribute
        // mutation). Without this, the Text content would swap instantly.
        .id(`narrator_step_${this.visibleStepCount}`)
        .transition(
          TransitionEffect.OPACITY
            .combine(TransitionEffect.move(TransitionEdge.START))
            .animation({ duration: 180, curve: Curve.EaseInOut })
        )
    }
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(VERTICAL_MATH_NARRATOR_BG)
    .borderRadius(14)
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}
