import { GateQuestion, generateGateQuestion, checkGateAnswer } from '../../utils/ParentalGateMath'

const GATE_ACCENT: string = '#FF9F43'
const GATE_ERROR: string = '#FF6B57'
const SHAKE_OFFSETS: number[] = [10, -10, 6, -6, 0]
const SHAKE_STEP_MS: number = 60

/**
 * 家长门（算术题验证）sheet 内容。
 * 答对 → onPassed（宿主负责关 sheet + 置解锁态）; 答错 → 红框 + 抖动 + 换新题; ✕/拖拽 → onCancelled。
 * 无状态持久化: 关闭即清空, 与"草稿纸"语义一致。
 */
@ComponentV2
export struct ParentalGateSheet {
  @Event onPassed: () => void = () => {}
  @Event onCancelled: () => void = () => {}
  @Local currentQuestion: GateQuestion = { text: '', answer: 0 } as GateQuestion
  @Local inputText: string = ''
  @Local showError: boolean = false
  @Local shakeX: number = 0
  private shakeTimerIds: number[] = []

  aboutToAppear(): void {
    this.currentQuestion = generateGateQuestion()
  }

  aboutToDisappear(): void {
    this.clearShakeTimers()
  }

  private clearShakeTimers(): void {
    for (let i = 0; i < this.shakeTimerIds.length; i++) {
      clearTimeout(this.shakeTimerIds[i])
    }
    this.shakeTimerIds = []
  }

  private handleConfirm(): void {
    if (checkGateAnswer(this.currentQuestion, this.inputText)) {
      this.onPassed()
      return
    }
    this.showError = true
    this.inputText = ''
    this.currentQuestion = generateGateQuestion()
    this.playShake()
  }

  private playShake(): void {
    this.clearShakeTimers()
    for (let i = 0; i < SHAKE_OFFSETS.length; i++) {
      const offset: number = SHAKE_OFFSETS[i]
      const timerId: number = setTimeout((): void => {
        this.shakeX = offset
      }, i * SHAKE_STEP_MS)
      this.shakeTimerIds.push(timerId)
    }
  }

  build() {
    Column({ space: 16 }) {
      // 标题栏: 左占位保持标题居中, 右侧 ✕
      Row() {
        Column()
          .width(36)
          .height(36)

        Text('家长验证')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('app.color.text_secondary')])
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor($r('app.color.divider'))
        .onClick((): void => {
          this.onCancelled()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('请算出下面的题目，答对即可进入')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))

      Text(this.currentQuestion.text)
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .translate({ x: this.shakeX })
        .animation({ duration: SHAKE_STEP_MS, curve: Curve.EaseOut })

      TextInput({ text: this.inputText, placeholder: '输入答案' })
        .type(InputType.Number)
        .fontSize(22)
        .textAlign(TextAlign.Center)
        .height(56)
        .borderRadius(14)
        .borderWidth(this.showError ? 2 : 0)
        .borderColor(GATE_ERROR)
        .onChange((value: string): void => {
          this.inputText = value
          this.showError = false
        })
        .onSubmit((): void => {
          this.handleConfirm()
        })

      if (this.showError) {
        Text('答案不对，换一题啦')
          .fontSize(13)
          .fontColor(GATE_ERROR)
      }

      Button('确定')
        .width('100%')
        .height(50)
        .borderRadius(14)
        .backgroundColor(GATE_ACCENT)
        .fontColor(Color.White)
        .fontSize(17)
        .onClick((): void => {
          this.handleConfirm()
        })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 16, bottom: 32 })
  }
}
