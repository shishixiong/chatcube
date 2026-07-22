// components/VerticalMathCard.ets
// Shell component that owns interactive state, renders the input form,
// control buttons, and assembles Board + Narrator for the vertical-math
// mini-game. Mirrors the MathQuizCard @Param/@Event contract.

import { ToolCall } from '../models/ChatModels'
import {
  solveVerticalMath,
  VerticalMathOperation,
  VerticalMathSolution
} from '../utils/VerticalMathSolver'
import {
  VERTICAL_MATH_ERROR_BG,
  VERTICAL_MATH_ERROR_TEXT
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

@ComponentV2
export struct VerticalMathCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false

  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  @Local operandA: string = ''
  @Local operandB: string = ''
  @Local selectedOperation: VerticalMathOperation = VerticalMathOperation.ADD
  @Local solution: VerticalMathSolution | null = null
  @Local visibleStepCount: number = 0
  @Local errorMessage: string = ''
  @Local hasAnswered: boolean = false

  aboutToAppear() {
    this.parseToolCallArguments()
    if (this.isAnswered) {
      // Pre-compute solution so the user can walk through it again.
      this.regenerateSolution()
      // Skip to the final step so re-opening a completed timeline entry shows the
      // answer instead of "step 0 / N" + just the aligned initial board. The user
      // can still replay the walk-through via "重置" or step back with "← 上一步".
      if (this.solution !== null && this.solution.steps.length > 0) {
        this.visibleStepCount = this.solution.steps.length
      }
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

  private handleNext() {
    if (this.solution === null) return
    if (this.visibleStepCount < this.solution.steps.length) {
      this.visibleStepCount++
    }
    if (this.solution !== null && this.visibleStepCount === this.solution.steps.length && !this.hasAnswered) {
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

  @Builder
  private InputForm() {
    Column() {
      Row() {
        TextInput({ text: this.operandA, placeholder: 'A' })
          .type(InputType.Number)
          .width(80)
          .height(44)
          .onChange((v: string) => this.handleInputA(v))
        Text(this.operationSymbol(this.selectedOperation))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 8, right: 8 })
        TextInput({ text: this.operandB, placeholder: 'B' })
          .type(InputType.Number)
          .width(80)
          .height(44)
          .onChange((v: string) => this.handleInputB(v))
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
    .backgroundColor(this.largeSize ? Color.Transparent : '#fffaf0')
    .borderRadius(14)
  }

  @Builder
  private Controls() {
    Row() {
      Button('← 上一步')
        .height(44)
        .layoutWeight(1)
        .margin({ right: 8 })
        .backgroundColor('#eee8ff')
        .fontColor('#30205f')
        .enabled(this.visibleStepCount > 0)
        .onClick(() => this.handlePrev())
      Button('下一步 →')
        .height(44)
        .layoutWeight(1)
        .margin({ right: 8 })
        .backgroundColor('#ffe66d')
        .fontColor('#3a2d0c')
        .enabled(this.solution !== null && this.visibleStepCount < this.solution.steps.length)
        .onClick(() => this.handleNext())
      Button('重置')
        .height(44)
        .layoutWeight(1)
        .backgroundColor('#ffe3dc')
        .fontColor('#89564b')
        .onClick(() => this.handleReset())
    }
    .padding(12)
  }

  build() {
    Column() {
      // Header
      Row() {
        Text('🧮 小小数学家 · 竖式闯关')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#21153f')
          .layoutWeight(1)
        if (this.solution !== null && this.solution.steps.length > 0) {
          Text(this.visibleStepCount === this.solution.steps.length
            ? `闯关完成 · ${this.visibleStepCount} / ${this.solution.steps.length}`
            : `第 ${this.visibleStepCount} / ${this.solution.steps.length} 步`)
            .fontSize(12)
            .fontColor('#665b84')
        }
      }
      .padding({ left: 14, right: 14, top: 12, bottom: 8 })

      // Error banner
      if (this.errorMessage !== '') {
        Row() {
          Text(this.errorMessage)
            .fontSize(13)
            .fontColor(VERTICAL_MATH_ERROR_TEXT)
            .layoutWeight(1)
        }
        .padding(11)
        .backgroundColor(VERTICAL_MATH_ERROR_BG)
        .borderRadius(12)
        .margin({ left: 14, right: 14, bottom: 8 })
      }

      // Input form (always visible when no solution)
      if (this.solution === null) {
        this.InputForm()
      }

      // Controls (always visible when solution exists)
      if (this.solution !== null) {
        this.Controls()
        // Board + narrator
        if (this.isCompact()) {
          // Stacked layout (mobile)
          Column() {
            VerticalMathBoard({
              solution: this.solution,
              visibleStepCount: this.visibleStepCount,
              compact: true
            })
            .height('60%')
            VerticalMathStepNarrator({
              steps: this.solution.steps,
              visibleStepCount: this.visibleStepCount,
              operationLabel: `第 ${this.visibleStepCount} / ${this.solution.steps.length} 步`
            })
            .height('40%')
          }
          .layoutWeight(1)
          .padding({ left: 12, right: 12, bottom: 12 })
        } else {
          // 70/30 layout (tablet / largeSize)
          Row() {
            VerticalMathBoard({
              solution: this.solution,
              visibleStepCount: this.visibleStepCount,
              compact: false
            })
            .layoutWeight(7)
            VerticalMathStepNarrator({
              steps: this.solution.steps,
              visibleStepCount: this.visibleStepCount,
              operationLabel: `第 ${this.visibleStepCount} / ${this.solution.steps.length} 步`
            })
            .layoutWeight(3)
          }
          .layoutWeight(1)
          .padding(12)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.largeSize ? Color.Transparent : '#f4efff')
  }
}