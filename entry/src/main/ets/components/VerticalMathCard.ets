// components/VerticalMathCard.ets
// Shell component that owns interactive state, renders the input form,
// control buttons, and assembles Board + Narrator for the vertical-math
// mini-game. Mirrors the MathQuizCard @Param/@Event contract.

import { ToolCall } from '../models/ChatModels'
import {
  solveVerticalMath,
  VerticalMathOperation,
  VerticalMathSolution,
  VerticalMathStep
} from '../utils/VerticalMathSolver'
import { getAppUiState } from '../state/AppUiState'
import {
  VerticalMathPalette,
  resolveVerticalMathPalette
} from '../utils/VerticalMathColors'
import { VerticalMathBoard } from './verticalMath/VerticalMathBoard'
import { VerticalMathStepNarrator } from './verticalMath/VerticalMathStepNarrator'

interface VerticalMathResultPayload {
  completed: boolean
  operation: string
  operand_a: number
  operand_b: number
  result: number
  remainder: number
  step_count: number
}

interface OperationButtonDescriptor {
  label: string
  op: VerticalMathOperation
}

// Module-level typed const for the operation chooser. ArkTS strict mode
// rejects inline `{ label, op }` object literals inside @Builder/ForEach
// bodies; a named typed array satisfies the inferred-array-type check.
const OPERATION_BUTTONS: OperationButtonDescriptor[] = [
  { label: '＋', op: VerticalMathOperation.ADD },
  { label: '－', op: VerticalMathOperation.SUBTRACT },
  { label: '×', op: VerticalMathOperation.MULTIPLY },
  { label: '÷', op: VerticalMathOperation.DIVIDE }
]

// File-private helper: validate that an AI-supplied toolCall.arguments payload
// has all three required fields (operation + two operands) and that the operands
// fit the solver's accepted range (0..999 integers). Used by aboutToAppear to
// decide whether to auto-solve or fall back to the input form.
//
// Operands arrive as raw strings (the component holds them in @Local string
// fields for the input form). Empty strings are treated as "missing" — Number('')
// is 0, which would otherwise sneak into the valid range.
function isCompleteVerticalMathArgs(
  operation: string,
  operandAStr: string,
  operandBStr: string
): boolean {
  if (operation !== VerticalMathOperation.ADD &&
    operation !== VerticalMathOperation.SUBTRACT &&
    operation !== VerticalMathOperation.MULTIPLY &&
    operation !== VerticalMathOperation.DIVIDE) {
    return false
  }
  if (operandAStr === '' || operandBStr === '') {
    return false
  }
  const operandA: number = Number(operandAStr)
  const operandB: number = Number(operandBStr)
  if (!Number.isInteger(operandA) || operandA < 0 || operandA > 999) {
    return false
  }
  if (!Number.isInteger(operandB) || operandB < 0 || operandB > 999) {
    return false
  }
  return true
}

@ComponentV2
export struct VerticalMathCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Param reduceMotion: boolean = false

  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local operandA: string = ''
  @Local operandB: string = ''
  @Local selectedOperation: VerticalMathOperation = VerticalMathOperation.ADD
  @Local solution: VerticalMathSolution | null = null
  @Local visibleStepCount: number = 0
  @Local errorMessage: string = ''
  @Local hasAnswered: boolean = false

  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  private get palette(): VerticalMathPalette {
    return resolveVerticalMathPalette(this.isDarkMode)
  }

  aboutToAppear() {
    this.parseToolCallArguments()
    if (this.isAnswered) {
      this.hasAnswered = true
      // Pre-compute solution so the user can walk through it again.
      this.regenerateSolution()
      // Skip to the final step so re-opening a completed timeline entry shows the
      // answer instead of "step 0 / N" + just the aligned initial board. The user
      // can still replay the walk-through via "重置" or step back with "← 上一步".
      if (this.solution !== null && this.solution.steps.length > 0) {
        this.visibleStepCount = this.solution.steps.length
      }
    } else if (isCompleteVerticalMathArgs(this.selectedOperation, this.operandA, this.operandB)) {
      // AI supplied a complete operands payload — auto-solve and render the
      // walk-through immediately. Missing/out-of-range/unknown-operation cases
      // fall through and the input form is rendered (handled in build()).
      this.regenerateSolution()
    }
  }

  private parseToolCallArguments() {
    try {
      const args: Record<string, Object> = JSON.parse(this.toolCall.arguments ?? '{}') as Record<string, Object>
      const op = args['operation']
      if (typeof op === 'string') {
        switch (op) {
          case 'add': this.selectedOperation = VerticalMathOperation.ADD; break
          case 'subtract': this.selectedOperation = VerticalMathOperation.SUBTRACT; break
          case 'multiply': this.selectedOperation = VerticalMathOperation.MULTIPLY; break
          case 'divide': this.selectedOperation = VerticalMathOperation.DIVIDE; break
        }
      }
      const a = args['operand_a']
      if (typeof a === 'number' && a >= 0) this.operandA = String(a)
      const b = args['operand_b']
      if (typeof b === 'number' && b >= 0) this.operandB = String(b)
    } catch (_e) {
      // Malformed arguments → leave defaults (empty inputs, ADD).
    }
  }

  private regenerateSolution() {
    const a = Number(this.operandA)
    const b = Number(this.operandB)
    const sol = solveVerticalMath(this.selectedOperation, a, b)
    if (sol.errorMessage !== undefined && sol.errorMessage !== '') {
      this.errorMessage = sol.errorMessage
      this.solution = null
      this.visibleStepCount = 0
      return
    }
    this.errorMessage = ''
    this.solution = sol
    this.visibleStepCount = 0
  }

  private handleStart() {
    this.regenerateSolution()
  }

  private submitResult() {
    if (this.solution === null || this.hasAnswered) return
    this.hasAnswered = true
    const payload: VerticalMathResultPayload = {
      completed: true,
      operation: this.selectedOperation,
      operand_a: Number(this.operandA),
      operand_b: Number(this.operandB),
      result: this.solution.result,
      remainder: this.solution.remainder,
      step_count: this.visibleStepCount
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private handleNext() {
    if (this.solution === null || this.hasAnswered) return
    if (this.visibleStepCount < this.solution.steps.length) {
      this.visibleStepCount++
      return
    }
    this.submitResult()
  }

  private handlePrev() {
    if (this.visibleStepCount > 0) {
      this.visibleStepCount--
    }
  }

  private handleReset() {
    this.visibleStepCount = 0
  }

  private handleInputA(value: string) {
    const filtered = value.replace(/[^0-9]/g, '').slice(0, 3)
    this.operandA = filtered
  }

  private handleInputB(value: string) {
    const filtered = value.replace(/[^0-9]/g, '').slice(0, 3)
    this.operandB = filtered
  }

  private operationSymbol(op: VerticalMathOperation): string {
    switch (op) {
      case VerticalMathOperation.ADD: return '＋'
      case VerticalMathOperation.SUBTRACT: return '－'
      case VerticalMathOperation.MULTIPLY: return '×'
      case VerticalMathOperation.DIVIDE: return '÷'
    }
  }

  private canStart(): boolean {
    return this.operandA.length > 0 && this.operandB.length > 0
  }

  private isCompact(): boolean {
    // Phone-narrow detection is delegated to the parent; largeSize==false means inline.
    return !this.largeSize
  }

  private isFinalAnswerVisible(): boolean {
    return this.solution !== null && this.visibleStepCount === this.solution.steps.length
  }

  private getPrimaryActionLabel(): string {
    if (this.solution === null) return ''
    if (this.hasAnswered) return '已告诉小星老师'
    if (this.isFinalAnswerVisible()) return '完成，告诉小星老师'
    const nextStep: VerticalMathStep = this.solution.steps[this.visibleStepCount]
    return this.visibleStepCount === 0 ? `开始${nextStep.actionLabel}` : nextStep.actionLabel
  }

  @Builder
  private InputForm() {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text('第一个数')
            .fontSize(12)
            .fontColor(this.palette.secondaryText)
          TextInput({ text: this.operandA, placeholder: '47' })
            .type(InputType.Number)
            .height(48)
            .onChange((v: string) => this.handleInputA(v))
        }
        .layoutWeight(1)

        Text(this.operationSymbol(this.selectedOperation))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 8, right: 8 })

        Column({ space: 4 }) {
          Text('第二个数')
            .fontSize(12)
            .fontColor(this.palette.secondaryText)
          TextInput({ text: this.operandB, placeholder: '28' })
            .type(InputType.Number)
            .height(48)
            .onChange((v: string) => this.handleInputB(v))
        }
        .layoutWeight(1)
      }
      .alignItems(VerticalAlign.Center)

      Row() {
        ForEach(OPERATION_BUTTONS, (item: OperationButtonDescriptor) => {
          Button(item.label)
            .height(44)
            .padding({ left: 12, right: 12 })
            .margin({ right: 6 })
            .backgroundColor(this.selectedOperation === item.op ? '#ffe66d' : '#eee8ff')
            .fontColor(this.selectedOperation === item.op ? '#3a2d0c' : '#30205f')
            .onClick(() => { this.selectedOperation = item.op })
        }, (item: OperationButtonDescriptor) => item.label)
      }
      .margin({ top: 12 })

      Button('开始计算')
        .height(44)
        .width('100%')
        .margin({ top: 12 })
        .backgroundColor('#ffe66d')
        .fontColor('#3a2d0c')
        .enabled(this.canStart())
        .onClick(() => this.handleStart())
    }
    .padding(12)
    .backgroundColor(this.largeSize ? Color.Transparent : this.palette.paper)
    .borderRadius(14)
  }

  @Builder
  private Controls() {
    Column() {
      Row() {
        Button('← 上一步')
          .height(48)
          .fontSize(13)
          .layoutWeight(1)
          .margin({ right: 8 })
          .backgroundColor('#eee8ff')
          .fontColor('#30205f')
          .enabled(this.visibleStepCount > 0 && !this.hasAnswered)
          .onClick(() => this.handlePrev())
          .accessibilityText('回到上一步')

        Button(this.getPrimaryActionLabel())
          .height(48)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .backgroundColor(this.hasAnswered ? '#c8c2b5' : '#ffe66d')
          .fontColor(this.hasAnswered ? '#5e574a' : '#3a2d0c')
          .enabled(this.solution !== null && !this.hasAnswered)
          .onClick(() => this.handleNext())
          .accessibilityText(this.hasAnswered ? '结果已告诉小星老师' : '进入下一步')
      }
      .width('100%')

      Row() {
        Text('重新开始')
          .fontSize(12)
          .fontColor('#665b84')
          .padding(8)
          .onClick(() => this.handleReset())
          .accessibilityText('重新开始竖式走一遍')
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .padding({ left: 12, right: 12, top: 4, bottom: 12 })
  }

  @Builder
  private StepProgressSegments() {
    Column({ space: 7 }) {
      Row() {
        Text(this.visibleStepCount === 0 ? '准备开始' :
          this.isFinalAnswerVisible() ? '竖式完成' :
            `${this.solution?.steps[this.visibleStepCount - 1].placeLabel ?? ''}完成`)
          .fontSize(11)
          .fontColor(this.palette.secondaryText)
          .layoutWeight(1)
        if (!this.isFinalAnswerVisible() && this.solution !== null) {
          Text(`下一步：${this.solution.steps[this.visibleStepCount].placeLabel}`)
            .fontSize(11)
            .fontColor(this.palette.secondaryText)
        }
      }
      Row({ space: 6 }) {
        if (this.solution !== null) {
          ForEach(this.solution.steps, (_step: VerticalMathStep, index: number) => {
            Row()
              .height(6)
              .layoutWeight(index === this.visibleStepCount ? 1.4 : 1)
              .borderRadius(3)
              .backgroundColor(index < this.visibleStepCount ? this.palette.success :
                index === this.visibleStepCount ? this.palette.focus : this.palette.divider)
          }, (_step: VerticalMathStep, index: number) => `step_segment_${index}`)
        }
      }
      .width('100%')
    }
    .margin({ top: 12, bottom: 12 })
  }

  build() {
    Column() {
      // Header
      Row() {
        Text('竖式计算')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.ink)
          .layoutWeight(1)
        if (this.solution !== null) {
          Text(`${this.operandA}${this.operationSymbol(this.selectedOperation)}${this.operandB}`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette.secondaryText)
        }
      }
      .padding({ left: 14, right: 14, top: 12, bottom: 8 })

      // Error banner
      if (this.errorMessage !== '') {
        Row() {
          Text(this.errorMessage)
            .fontSize(13)
            .fontColor('#89564b')
            .layoutWeight(1)
        }
        .padding(11)
        .backgroundColor('#ffe3dc')
        .borderRadius(12)
        .margin({ left: 14, right: 14, bottom: 8 })
      }

      // Input form (always visible when no solution)
      if (this.solution === null) {
        this.InputForm()
      }

      // Board + narrator + segmented progress (always visible when solution exists)
      if (this.solution !== null) {
        if (this.isCompact()) {
          // Stacked layout (mobile)
          Column() {
            VerticalMathStepNarrator({
              steps: this.solution.steps,
              visibleStepCount: this.visibleStepCount,
              isDarkMode: this.isDarkMode,
              reduceMotion: this.reduceMotion
            })
            .margin({ bottom: 8 })
            VerticalMathBoard({
              solution: this.solution,
              visibleStepCount: this.visibleStepCount,
              compact: true,
              isDarkMode: this.isDarkMode,
              reduceMotion: this.reduceMotion
            })
            .layoutWeight(1)
            this.StepProgressSegments()
          }
          .layoutWeight(1)
          .padding({ left: 12, right: 12, top: 12, bottom: 8 })
        } else {
          // Narrator header above full-width board (tablet / largeSize)
          Column() {
            VerticalMathStepNarrator({
              steps: this.solution.steps,
              visibleStepCount: this.visibleStepCount,
              isDarkMode: this.isDarkMode,
              reduceMotion: this.reduceMotion
            })
            .margin({ bottom: 10 })
            VerticalMathBoard({
              solution: this.solution,
              visibleStepCount: this.visibleStepCount,
              compact: false,
              isDarkMode: this.isDarkMode,
              reduceMotion: this.reduceMotion
            })
            .layoutWeight(1)
            this.StepProgressSegments()
          }
          .layoutWeight(1)
          .padding(12)
        }
        // Controls now sit below the main content (see spec §3.2.4 rationale).
        this.Controls()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.largeSize ? Color.Transparent : this.palette.shell)
  }
}
