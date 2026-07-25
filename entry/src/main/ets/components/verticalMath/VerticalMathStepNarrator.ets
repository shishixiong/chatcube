// components/verticalMath/VerticalMathStepNarrator.ets
// Single-line step narrator for vertical-math walk-through.
// Renders the current step's placeLabel as a small focus chip and the
// step's narration as the primary text below it. Sits above VerticalMathBoard
// in VerticalMathCard's layout.

import { VerticalMathPalette, resolveVerticalMathPalette } from '../../utils/VerticalMathColors'
import { VerticalMathStep } from '../../utils/VerticalMathSolver'

@ComponentV2
export struct VerticalMathStepNarrator {
  @Param steps: VerticalMathStep[] = []
  @Param visibleStepCount: number = 0
  @Param isDarkMode: boolean = false
  @Param reduceMotion: boolean = false

  private get palette(): VerticalMathPalette {
    return resolveVerticalMathPalette(this.isDarkMode)
  }

  private getCurrentStep(): VerticalMathStep | null {
    if (this.steps.length === 0) return null
    const idx = Math.max(0, Math.min(this.visibleStepCount - 1, this.steps.length - 1))
    return this.steps[idx]
  }

  private getPlaceLabel(): string {
    if (this.visibleStepCount <= 0) return '准备'
    const step = this.getCurrentStep()
    if (step === null) return '准备'
    return step.placeLabel
  }

  private getNarrationLine(): string {
    if (this.visibleStepCount <= 0 || this.steps.length === 0) {
      return '从右边的个位开始算。'
    }
    const step = this.getCurrentStep()
    if (step === null) {
      return '从右边的个位开始算。'
    }
    return step.narration
  }

  build() {
    Column() {
      Row() {
        Text(this.getPlaceLabel())
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette.focusText)
          .backgroundColor(this.palette.focus)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(8)
      }
      .margin({ bottom: 6 })

      Text(this.getNarrationLine())
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.ink)
        .lineHeight(22)
        .width('100%')
        // .id() changes per step force ArkUI V2 to treat each render as a
        // fresh component instance, so the .transition() below actually
        // fires when visibleStepCount changes (insert/delete, not attribute
        // mutation). Without this, the Text content would swap instantly.
        .id(`narrator_step_${this.visibleStepCount}`)
        .transition(
          TransitionEffect.OPACITY.animation({
            duration: this.reduceMotion ? 0 : 180,
            curve: Curve.EaseInOut
          })
        )
    }
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(this.palette.paper)
    .borderRadius(14)
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}
