import {
  VERTICAL_MATH_NARRATOR_BG,
  VERTICAL_MATH_NARRATOR_ACTIVE_BG,
  VERTICAL_MATH_NARRATOR_ACTIVE_TEXT,
  VERTICAL_MATH_NARRATOR_DONE_BG,
  VERTICAL_MATH_NARRATOR_DONE_TEXT
} from '../../utils/VerticalMathColors'
import { VerticalMathStep } from '../../utils/VerticalMathSolver'

@ComponentV2
export struct VerticalMathStepNarrator {
  @Param steps: VerticalMathStep[] = []
  @Param visibleStepCount: number = 0
  @Param operationLabel: string = ''

  private listScroller: Scroller = new Scroller()

  aboutToAppear() {
    // Scroll to active step after layout settles.
    setTimeout(() => {
      const active = Math.max(0, Math.min(this.visibleStepCount - 1, this.steps.length - 1))
      this.listScroller.scrollToIndex(active, true, ScrollAlign.CENTER)
    }, 50)
  }

  aboutToUpdate() {
    const active = Math.max(0, Math.min(this.visibleStepCount - 1, this.steps.length - 1))
    this.listScroller.scrollToIndex(active, true, ScrollAlign.CENTER)
  }

  private isStepDone(index: number): boolean {
    return index < this.visibleStepCount
  }

  private isStepActive(index: number): boolean {
    return index === this.visibleStepCount - 1
  }

  private getBadgeText(index: number): string {
    return this.isStepDone(index) ? '✓' : `${index + 1}`
  }

  private getBadgeBg(index: number): string {
    return this.isStepDone(index) ? VERTICAL_MATH_NARRATOR_DONE_BG : '#dcd0ff'
  }

  private getBadgeColor(index: number): string {
    return this.isStepDone(index) ? VERTICAL_MATH_NARRATOR_DONE_TEXT : '#6954a5'
  }

  private getCardBg(index: number): string {
    if (this.isStepActive(index)) {
      return VERTICAL_MATH_NARRATOR_ACTIVE_BG
    }
    if (this.isStepDone(index)) {
      return VERTICAL_MATH_NARRATOR_DONE_BG
    }
    return '#f1ecff'
  }

  private getTextColor(index: number): string {
    if (this.isStepActive(index)) {
      return VERTICAL_MATH_NARRATOR_ACTIVE_TEXT
    }
    if (this.isStepDone(index)) {
      return VERTICAL_MATH_NARRATOR_DONE_TEXT
    }
    return '#62577d'
  }

  @Builder
  private StepCard(step: VerticalMathStep, index: number) {
    Row() {
      Text(this.getBadgeText(index))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getBadgeColor(index))
        .width(22)
        .height(22)
        .borderRadius(11)
        .backgroundColor(this.getBadgeBg(index))
        .textAlign(TextAlign.Center)
      Column() {
        Text(step.title)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getTextColor(index))
        if (step.narration !== '') {
          Text(step.narration)
            .fontSize(12)
            .fontColor(this.getTextColor(index))
            .margin({ top: 4 })
            .lineHeight(16)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 8 })
    }
    .padding(11)
    .borderRadius(13)
    .backgroundColor(this.getCardBg(index))
    .margin({ bottom: 8 })
  }

  private renderStepCard(step: VerticalMathStep, index: number): ListItem {
    ListItem() {
      this.StepCard(step, index)
    }
  }

  build() {
    Column() {
      Text(this.operationLabel)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#21153f')
        .margin({ bottom: 12 })
      List({ scroller: this.listScroller }) {
        ForEach(this.steps, (step: VerticalMathStep, index: number) => {
          this.renderStepCard(step, index)
        }, (step: VerticalMathStep, index: number) => `step_${index}`)
      }
      .width('100%')
      .layoutWeight(1)
      .listDirection(Axis.Vertical)
      .scrollBar(BarState.Off)
    }
    .padding(16)
    .backgroundColor(VERTICAL_MATH_NARRATOR_BG)
    .borderRadius(20)
    .height('100%')
  }
}
