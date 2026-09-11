import { GateQuestion, generateGateQuestion, checkGateAnswer } from '../../utils/ParentalGateMath'
import {
  KIDS_BG,
  KIDS_SURFACE,
  KIDS_FG,
  KIDS_MUTED,
  KIDS_SUBTLE,
  KIDS_BORDER,
  KIDS_ACCENT,
  KIDS_DANGER,
  KIDS_ON_HERO
} from './KidsBrandTokens'

const SHAKE_OFFSETS: number[] = [10, -10, 6, -6, 0]
const SHAKE_STEP_MS: number = 60
const MAX_INPUT_LENGTH: number = 4
const DIGIT_KEYS: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9']

/**
 * 家长门（算术题验证）sheet 内容——自绘数字键盘版
 * （对照 docs/kids-home-prototype.html 的 .gate 区块）。
 *
 * 答案显示框（空态「输入答案」, 答错红边框 + 抖动 + 换题）
 * + 3×4 数字键盘（1–9 / ⌫ / 0 / 通栏「确定」）, 不依赖系统输入法。
 * 答对 → onPassed（宿主负责关 sheet + 置解锁态）; ✕/拖拽 → onCancelled。
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

  private handleDigit(digit: string): void {
    this.showError = false
    if (this.inputText.length < MAX_INPUT_LENGTH) {
      this.inputText += digit
    }
  }

  private handleBackspace(): void {
    this.showError = false
    this.inputText = this.inputText.slice(0, -1)
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
    Column() {
      // 标题栏: 左占位保持标题居中, 右侧 ✕
      Row() {
        Column()
          .width(36)
          .height(36)

        Text('家长验证')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([KIDS_MUTED])
        }
        .type(ButtonType.Circle)
        .width(36)
        .height(36)
        .backgroundColor('#0F24211C')
        .onClick((): void => {
          this.onCancelled()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('请算出下面的题目，答对即可进入')
        .fontSize(12.5)
        .fontColor(KIDS_MUTED)
        .margin({ top: 14 })

      // 题目
      Text(this.currentQuestion.text)
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_FG)
        .letterSpacing(1)
        .margin({ top: 14 })

      // 答案显示框（答错: 红边框 + 抖动）
      Column() {
        if (this.inputText.length > 0) {
          Text(this.inputText)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_FG)
            .letterSpacing(2)
        } else {
          Text('输入答案')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(KIDS_SUBTLE)
        }
      }
      .width('100%')
      .height(56)
      .borderRadius(14)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(KIDS_BG)
      .border({ width: 2, color: this.showError ? KIDS_DANGER : KIDS_BORDER })
      .translate({ x: this.shakeX })
      .animation({ duration: SHAKE_STEP_MS, curve: Curve.EaseOut })
      .margin({ top: 14 })

      // 错误提示（固定高度避免布局跳动）
      Text(this.showError ? '答案不对，换一题啦' : ' ')
        .fontSize(12.5)
        .fontColor(KIDS_DANGER)
        .height(18)
        .margin({ top: 10 })

      // 数字键盘: 1-9 / ⌫ / 0 / 通栏确定
      Grid() {
        ForEach(DIGIT_KEYS, (key: string): void => {
          GridItem() {
            this.DigitKey(key)
          }
        }, (key: string): string => key)

        GridItem() {
          this.AltKey('⌫', (): void => {
            this.handleBackspace()
          })
        }

        GridItem() {
          this.DigitKey('0')
        }

        GridItem() {
          Column()
            .width('100%')
            .height(52)
        }
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(10)
      .rowsGap(10)
      .width('100%')
      .height(4 * 52 + 3 * 10)
      .scrollBar(BarState.Off)

      Button('确定')
        .width('100%')
        .height(52)
        .borderRadius(14)
        .backgroundColor(KIDS_ACCENT)
        .fontColor(KIDS_ON_HERO)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 10 })
        .onClick((): void => {
          this.handleConfirm()
        })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 16, bottom: 32 })
    .backgroundColor(KIDS_SURFACE)
  }

  @Builder
  DigitKey(digit: string) {
    Text(digit)
      .fontSize(21)
      .fontWeight(FontWeight.Bold)
      .fontColor(KIDS_FG)
      .width('100%')
      .height(52)
      .textAlign(TextAlign.Center)
      .borderRadius(14)
      .backgroundColor(KIDS_BG)
      .border({ width: 1, color: KIDS_BORDER })
      .onClick((): void => {
        this.handleDigit(digit)
      })
  }

  @Builder
  AltKey(label: string, action: () => void) {
    Text(label)
      .fontSize(17)
      .fontColor(KIDS_MUTED)
      .width('100%')
      .height(52)
      .textAlign(TextAlign.Center)
      .borderRadius(14)
      .backgroundColor(KIDS_BG)
      .border({ width: 1, color: KIDS_BORDER })
      .onClick((): void => {
        action()
      })
  }
}
