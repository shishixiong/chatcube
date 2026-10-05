// components/VerticalMathCard.ets
// 竖式计算卡片 v2（docs/vertical_math_refine.html 重设计）：
// - 双页壳：「竖式」（AI 给数的演示走一遍）+「练习」（难度出题 + 判答 + 计分 + 查看讲解）
// - 黑板棋盘 + 三色语义（黄=进位/借位调整、蓝=部分积/逐步乘积、绿=答案/余数）
// - 步骤条：上一步 / 步骤 N/M / 下一步 + 全部展开 / 重置
// - 练习答完回传 { mode:'practice', correct_count, ... }，由 ToolExecutionService 授星
import { ToolCall } from '../models/ChatModels'
import {
  solveVerticalMath,
  VerticalMathOperation,
  VerticalMathSolution,
  VerticalMathStep
} from '../utils/VerticalMathSolver'
import {
  generatePracticeSet,
  VerticalMathPracticeProblem,
  RandomSource
} from '../utils/VerticalMathPracticeGenerator'
import { getAppUiState } from '../state/AppUiState'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { ServiceRegistry } from '../services/ServiceRegistry'
import { normalizeMathSymbolsForTts } from '../utils/TtsTextUtils'
import {
  VerticalMathPalette,
  resolveVerticalMathPalette
} from '../utils/VerticalMathColors'
import { VerticalMathBoard } from './verticalMath/VerticalMathBoard'
import { VerticalMathStepNarrator } from './verticalMath/VerticalMathStepNarrator'

const TAB_DEMO: string = 'demo'
const TAB_PRACTICE: string = 'practice'

interface VerticalMathDemoPayload {
  mode: string
  completed: boolean
  operation: string
  operand_a: number
  operand_b: number
  result: number
  remainder: number
  step_count: number
}

interface VerticalMathPracticePayload {
  mode: string
  completed: boolean
  operation: string
  difficulty: number
  total: number
  correct_count: number
  attempt_count: number
  best_streak: number
  details: string[]
}

interface OperationButtonDescriptor {
  label: string
  op: VerticalMathOperation
}

interface DifficultyButtonDescriptor {
  label: string
  level: number
}

// Module-level typed consts: ArkTS strict mode rejects inline object literals
// inside @Builder/ForEach bodies; named typed arrays satisfy the check.
const OPERATION_BUTTONS: OperationButtonDescriptor[] = [
  { label: '＋', op: VerticalMathOperation.ADD },
  { label: '－', op: VerticalMathOperation.SUBTRACT },
  { label: '×', op: VerticalMathOperation.MULTIPLY },
  { label: '÷', op: VerticalMathOperation.DIVIDE }
]

const DIFFICULTY_BUTTONS: DifficultyButtonDescriptor[] = [
  { label: '入门', level: 1 },
  { label: '进阶', level: 2 },
  { label: '挑战', level: 3 }
]

// File-private helper: validate that an AI-supplied toolCall.arguments payload
// has all three required fields (operation + two operands) and that the operands
// fit the solver's accepted range (0..99999 integers). Used by aboutToAppear to
// decide whether to auto-solve or fall back to the input form.
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
  if (!Number.isInteger(operandA) || operandA < 0 || operandA > 99999) {
    return false
  }
  if (!Number.isInteger(operandB) || operandB < 0 || operandB > 99999) {
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

  @Local activeTab: string = TAB_DEMO

  // ===== 竖式演示页 =====
  @Local operandA: string = ''
  @Local operandB: string = ''
  @Local selectedOperation: VerticalMathOperation = VerticalMathOperation.ADD
  @Local solution: VerticalMathSolution | null = null
  @Local visibleStepCount: number = 0
  @Local errorMessage: string = ''
  @Local hasAnswered: boolean = false

  // ===== 练习页 =====
  @Local practiceOperation: VerticalMathOperation = VerticalMathOperation.ADD
  @Local practiceDifficulty: number = 1
  @Local practiceProblems: VerticalMathPracticeProblem[] = []
  @Local practiceIndex: number = 0
  @Local practiceInput: string = ''
  @Local practiceAnswered: boolean = false
  @Local practiceCorrect: boolean = false
  @Local practiceError: string = ''
  @Local practiceCorrectCount: number = 0
  @Local practiceAttemptCount: number = 0
  @Local practiceStreak: number = 0
  @Local practiceBestStreak: number = 0
  @Local practiceRevealSolution: VerticalMathSolution | null = null
  @Local practiceShowSolution: boolean = false
  @Local practiceReplayPayload: VerticalMathPracticePayload | null = null

  private practiceCount: number = 5
  private practiceDetailLines: string[] = []

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
      this.restoreAnsweredState()
    } else if (this.activeTab === TAB_PRACTICE) {
      this.regeneratePracticeSet()
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
      const mode = args['mode']
      if (mode === TAB_PRACTICE) {
        this.activeTab = TAB_PRACTICE
      }
      const practiceConfig = args['practice']
      if (practiceConfig !== null && practiceConfig !== undefined && typeof practiceConfig === 'object') {
        const config: Record<string, Object> = practiceConfig as Record<string, Object>
        const practiceOp = config['operation']
        if (typeof practiceOp === 'string') {
          this.practiceOperation = this.operationFromString(practiceOp)
        }
        const difficulty = config['difficulty']
        if (typeof difficulty === 'number') {
          this.practiceDifficulty = Math.min(3, Math.max(1, Math.floor(difficulty)))
        }
        const count = config['count']
        if (typeof count === 'number') {
          this.practiceCount = Math.min(10, Math.max(1, Math.floor(count)))
        }
      }
      const op = args['operation']
      if (typeof op === 'string') {
        this.selectedOperation = this.operationFromString(op)
      }
      const a = args['operand_a']
      if (typeof a === 'number' && a >= 0) this.operandA = String(a)
      const b = args['operand_b']
      if (typeof b === 'number' && b >= 0) this.operandB = String(b)
    } catch (_e) {
      // Malformed arguments → leave defaults (empty inputs, ADD).
    }
  }

  private operationFromString(op: string): VerticalMathOperation {
    if (op === VerticalMathOperation.SUBTRACT) return VerticalMathOperation.SUBTRACT
    if (op === VerticalMathOperation.MULTIPLY) return VerticalMathOperation.MULTIPLY
    if (op === VerticalMathOperation.DIVIDE) return VerticalMathOperation.DIVIDE
    return VerticalMathOperation.ADD
  }

  /** 已回答卡片的恢复：练习回执显示计分总结，演示回执跳到完整板书。 */
  private restoreAnsweredState() {
    try {
      const payload: Record<string, Object> =
        JSON.parse(this.answeredPayload) as Record<string, Object>
      if (payload['mode'] === TAB_PRACTICE) {
        const replay: VerticalMathPracticePayload = {
          mode: TAB_PRACTICE,
          completed: payload['completed'] === true,
          operation: typeof payload['operation'] === 'string' ? payload['operation'] as string : 'add',
          difficulty: typeof payload['difficulty'] === 'number' ? payload['difficulty'] as number : 1,
          total: typeof payload['total'] === 'number' ? payload['total'] as number : 0,
          correct_count: typeof payload['correct_count'] === 'number' ? payload['correct_count'] as number : 0,
          attempt_count: typeof payload['attempt_count'] === 'number' ? payload['attempt_count'] as number : 0,
          best_streak: typeof payload['best_streak'] === 'number' ? payload['best_streak'] as number : 0,
          details: Array.isArray(payload['details']) ? payload['details'] as string[] : []
        }
        this.practiceReplayPayload = replay
        this.activeTab = TAB_PRACTICE
        return
      }
    } catch (_e) {
      // 非 JSON 回执 → 按演示回执处理
    }
    // 演示回执：重算解并跳到最终步，重开时直接看到答案（可重置重放）。
    if (isCompleteVerticalMathArgs(this.selectedOperation, this.operandA, this.operandB)) {
      this.regenerateSolution()
      if (this.solution !== null && this.solution.steps.length > 0) {
        this.visibleStepCount = this.solution.steps.length
      }
    }
  }

  // ===== 演示页逻辑 =====

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

  private submitDemoResult() {
    if (this.solution === null || this.hasAnswered) return
    this.hasAnswered = true
    const payload: VerticalMathDemoPayload = {
      mode: TAB_DEMO,
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
      this.speakStepNarration(this.visibleStepCount - 1)
      return
    }
    this.submitDemoResult()
  }

  private handlePrev() {
    if (this.visibleStepCount > 0) {
      this.visibleStepCount--
      // 回退后正在播的旁白已过时，直接停掉
      ServiceRegistry.tts().stop()
    }
  }

  private handleReset() {
    this.visibleStepCount = 0
    ServiceRegistry.tts().stop()
  }

  private handleExpandAll() {
    if (this.solution === null) return
    this.visibleStepCount = this.solution.steps.length
    ServiceRegistry.tts().stop()
  }

  // 语音模式（ChatPage 镜像到 AppStorage 的标量）下，孩子点"下一步"时
  // 朗读当前步的旁白——孩子可以听着讲解逐步完成竖式。
  private isVoicePlaybackEnabled(): boolean {
    return AppStorage.get<number>(AppStorageKeys.VOICE_MODE_ENABLED) === 1
  }

  private speakStepNarration(stepIndex: number): void {
    if (!this.isVoicePlaybackEnabled()) return
    if (this.solution === null || stepIndex < 0 || stepIndex >= this.solution.steps.length) return
    const narration: string = this.solution.steps[stepIndex].narration
    if (narration === '') return
    // TTS 引擎读不出 − × ÷ ＝ 等符号, 转成中文读法再朗读
    // (屏幕上的 StepNarrator 仍显示符号形式)。
    const ttsText: string = normalizeMathSymbolsForTts(narration)
    // 步骤旁白接管所有在播语音（如引入卡片的消息正文自动朗读），
    // 让孩子听到的是刚前进到的这一步。
    ServiceRegistry.tts().stop()
    ServiceRegistry.tts().speak(ttsText, {
      onStart: () => {},
      onComplete: () => {},
      onError: (_error: string) => {}
    }).catch((_e: Error) => {})
  }

  private handleInputA(value: string) {
    const filtered = value.replace(/[^0-9]/g, '').slice(0, 5)
    this.operandA = filtered
  }

  private handleInputB(value: string) {
    const filtered = value.replace(/[^0-9]/g, '').slice(0, 5)
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

  private operationName(op: VerticalMathOperation): string {
    switch (op) {
      case VerticalMathOperation.ADD: return '加法'
      case VerticalMathOperation.SUBTRACT: return '减法'
      case VerticalMathOperation.MULTIPLY: return '乘法'
      case VerticalMathOperation.DIVIDE: return '除法'
    }
  }

  private canStart(): boolean {
    return this.operandA.length > 0 && this.operandB.length > 0
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

  private getStepIndicatorText(): string {
    if (this.solution === null) return ''
    const total: number = this.solution.steps.length
    const current: number = Math.min(this.visibleStepCount + 1, total + 1)
    return `步骤 ${current} / ${total + 1}`
  }

  // ===== 练习页逻辑 =====

  private regeneratePracticeSet() {
    const rand: RandomSource = (): number => Math.random()
    this.practiceProblems = generatePracticeSet(
      this.practiceOperation, this.practiceDifficulty, this.practiceCount, rand)
    this.practiceIndex = 0
    this.practiceCorrectCount = 0
    this.practiceAttemptCount = 0
    this.practiceStreak = 0
    this.practiceBestStreak = 0
    this.practiceDetailLines = []
    this.resetCurrentProblem()
  }

  private resetCurrentProblem() {
    this.practiceInput = ''
    this.practiceAnswered = false
    this.practiceCorrect = false
    this.practiceError = ''
    this.practiceRevealSolution = null
    this.practiceShowSolution = false
  }

  private getCurrentProblem(): VerticalMathPracticeProblem | null {
    if (this.practiceIndex < 0 || this.practiceIndex >= this.practiceProblems.length) {
      return null
    }
    return this.practiceProblems[this.practiceIndex]
  }

  private isLastProblem(): boolean {
    return this.practiceIndex >= this.practiceProblems.length - 1
  }

  private handlePracticeOperationChange(op: VerticalMathOperation) {
    if (this.practiceOperation === op) return
    this.practiceOperation = op
    this.regeneratePracticeSet()
  }

  private handlePracticeDifficultyChange(level: number) {
    if (this.practiceDifficulty === level) return
    this.practiceDifficulty = level
    this.regeneratePracticeSet()
  }

  private handlePracticeInput(value: string) {
    if (this.practiceAnswered) return
    const filtered = value.replace(/[^0-9]/g, '').slice(0, 6)
    this.practiceInput = filtered
    this.practiceError = ''
  }

  private handlePracticeCheck() {
    const problem = this.getCurrentProblem()
    if (problem === null || this.practiceAnswered || this.hasAnswered) return
    const raw: string = this.practiceInput.trim()
    if (raw === '') {
      this.practiceError = '请先输入答案'
      return
    }
    if (!/^\d+$/.test(raw)) {
      this.practiceError = '只能填写数字，请重新输入'
      return
    }
    this.practiceError = ''
    this.practiceAnswered = true
    this.practiceAttemptCount++
    this.practiceCorrect = Number(raw) === problem.answer
    if (this.practiceCorrect) {
      this.practiceCorrectCount++
      this.practiceStreak++
      if (this.practiceStreak > this.practiceBestStreak) {
        this.practiceBestStreak = this.practiceStreak
      }
    } else {
      this.practiceStreak = 0
    }
    // 出题范围恒在求解器校验内；防御式兜底——解析失败就不给讲解板
    const sol = solveVerticalMath(problem.operation, problem.a, problem.b)
    if (sol.errorMessage === undefined || sol.errorMessage === '') {
      this.practiceRevealSolution = sol
    } else {
      this.practiceRevealSolution = null
    }
    // 作答明细累积到回执 details（换题前的作答也保留，如实记录尝试）
    const mark: string = this.practiceCorrect ? '✓' : '✗'
    this.practiceDetailLines.push(
      `${problem.a}${this.operationSymbol(problem.operation)}${problem.b}＝${raw}${mark}（正确 ${problem.answer}）`)
  }

  private handlePracticeNext() {
    if (this.practiceAnswered && !this.isLastProblem()) {
      this.practiceIndex++
      this.resetCurrentProblem()
    }
  }

  private handlePracticeSkip() {
    if (this.hasAnswered) return
    // 换一题：替换当前题为新的同配置题，不计分
    const rand: RandomSource = (): number => Math.random()
    const fresh = generatePracticeSet(this.practiceOperation, this.practiceDifficulty, 1, rand)
    if (fresh.length > 0) {
      const replacement: VerticalMathPracticeProblem[] = this.practiceProblems.slice()
      replacement[this.practiceIndex] = fresh[0]
      this.practiceProblems = replacement
    }
    this.resetCurrentProblem()
  }

  private submitPracticeResult() {
    if (this.hasAnswered) return
    this.hasAnswered = true
    const payload: VerticalMathPracticePayload = {
      mode: TAB_PRACTICE,
      completed: true,
      operation: this.practiceOperation,
      difficulty: this.practiceDifficulty,
      total: this.practiceProblems.length,
      correct_count: this.practiceCorrectCount,
      attempt_count: this.practiceAttemptCount,
      best_streak: this.practiceBestStreak,
      details: this.practiceDetailLines.slice()
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(payload))
  }

  private getPracticePrimaryLabel(): string {
    if (this.hasAnswered) return '已告诉小星老师'
    if (this.practiceAnswered && this.isLastProblem()) return '完成，告诉小星老师'
    if (this.practiceAnswered) return '下一题'
    return '提交答案'
  }

  private handlePracticePrimary() {
    if (this.hasAnswered) return
    if (!this.practiceAnswered) {
      this.handlePracticeCheck()
      return
    }
    if (this.isLastProblem()) {
      this.submitPracticeResult()
      return
    }
    this.handlePracticeNext()
  }

  // ===== UI =====

  @Builder
  private TabSwitch() {
    Row({ space: 6 }) {
      Button('竖式')
        .layoutWeight(1)
        .height(36)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .borderRadius(10)
        .backgroundColor(this.activeTab === TAB_DEMO ? this.palette.focus : this.palette.accentBackground)
        .fontColor(this.activeTab === TAB_DEMO ? this.palette.focusText : this.palette.accentText)
        .onClick(() => { this.switchTab(TAB_DEMO) })
        .accessibilityText('切换到竖式演示')
      Button('练习')
        .layoutWeight(1)
        .height(36)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .borderRadius(10)
        .backgroundColor(this.activeTab === TAB_PRACTICE ? this.palette.focus : this.palette.accentBackground)
        .fontColor(this.activeTab === TAB_PRACTICE ? this.palette.focusText : this.palette.accentText)
        .onClick(() => { this.switchTab(TAB_PRACTICE) })
        .accessibilityText('切换到练习模式')
    }
    .padding({ left: 14, right: 14, top: 10, bottom: 4 })
  }

  private switchTab(tab: string) {
    if (this.activeTab === tab || this.hasAnswered) return
    this.activeTab = tab
    ServiceRegistry.tts().stop()
    if (tab === TAB_PRACTICE && this.practiceProblems.length === 0 && !this.hasAnswered) {
      this.regeneratePracticeSet()
    }
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
            .height(48)
            .padding({ left: 12, right: 12 })
            .margin({ right: 6 })
            .backgroundColor(this.selectedOperation === item.op ? this.palette.focus : this.palette.accentBackground)
            .fontColor(this.selectedOperation === item.op ? this.palette.focusText : this.palette.accentText)
            .onClick(() => { this.selectedOperation = item.op })
            .accessibilityText(
              item.op === VerticalMathOperation.ADD ? '选择加法' :
                item.op === VerticalMathOperation.SUBTRACT ? '选择减法' :
                item.op === VerticalMathOperation.MULTIPLY ? '选择乘法' :
                '选择除法'
            )
        }, (item: OperationButtonDescriptor) => item.label)
      }
      .margin({ top: 12 })

      Button('开始计算')
        .height(48)
        .width('100%')
        .margin({ top: 12 })
        .backgroundColor(this.palette.focus)
        .fontColor(this.palette.focusText)
        .enabled(this.canStart())
        .onClick(() => this.handleStart())
        .accessibilityText('开始计算')
    }
    .padding(12)
    .backgroundColor(this.largeSize ? Color.Transparent : this.palette.paper)
    .borderRadius(14)
  }

  @Builder
  private ExpressionHeader() {
    Row() {
      Text(this.buildExpressionText())
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily('ui-monospace, SFMono-Regular, Menlo, monospace')
        .fontColor(this.palette.ink)
        .layoutWeight(1)
      Text(this.operationName(this.selectedOperation))
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.accentText)
        .backgroundColor(this.palette.accentBackground)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(999)
    }
    .padding({ left: 14, right: 14, bottom: 8 })
  }

  private buildExpressionText(): string {
    if (this.solution === null) return ''
    const answer: string = this.isFinalAnswerVisible()
      ? `${this.solution.result}${this.solution.remainder > 0 ? `……${this.solution.remainder}` : ''}`
      : '？'
    return `${this.operandA} ${this.operationSymbol(this.selectedOperation)} ${this.operandB} ＝ ${answer}`
  }

  @Builder
  private Legend() {
    Row({ space: 12 }) {
      Row({ space: 4 }) {
        Row().width(9).height(9).borderRadius(3).backgroundColor(this.palette.boardCarry)
        Text('进位/借位').fontSize(11).fontColor(this.palette.secondaryText)
      }
      Row({ space: 4 }) {
        Row().width(9).height(9).borderRadius(3).backgroundColor(this.palette.boardProduct)
        Text('部分积/乘积').fontSize(11).fontColor(this.palette.secondaryText)
      }
      Row({ space: 4 }) {
        Row().width(9).height(9).borderRadius(3).backgroundColor(this.palette.boardFinal)
        Text('答案/余数').fontSize(11).fontColor(this.palette.secondaryText)
      }
    }
    .justifyContent(FlexAlign.Center)
    .margin({ top: 8 })
  }

  @Builder
  private StepBar() {
    Column() {
      Row() {
        Button('← 上一步')
          .height(44)
          .fontSize(13)
          .layoutWeight(1)
          .backgroundColor(this.palette.accentBackground)
          .fontColor(this.palette.accentText)
          .enabled(this.visibleStepCount > 0 && !this.hasAnswered)
          .onClick(() => this.handlePrev())
          .accessibilityText('回到上一步')

        Text(this.getStepIndicatorText())
          .fontSize(12)
          .fontColor(this.palette.secondaryText)
          .margin({ left: 8, right: 8 })

        Button(this.getPrimaryActionLabel())
          .height(44)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .backgroundColor(this.hasAnswered ? this.palette.disabledBackground : this.palette.focus)
          .fontColor(this.hasAnswered ? this.palette.disabledText : this.palette.focusText)
          .enabled(this.solution !== null && !this.hasAnswered)
          .onClick(() => this.handleNext())
          .accessibilityText(this.hasAnswered ? '结果已告诉小星老师' : this.getPrimaryActionLabel())
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 8 }) {
        Button('全部展开')
          .height(40)
          .fontSize(12)
          .layoutWeight(1)
          .backgroundColor(this.palette.accentBackground)
          .fontColor(this.palette.accentText)
          .enabled(this.solution !== null && !this.isFinalAnswerVisible() && !this.hasAnswered)
          .onClick(() => this.handleExpandAll())
          .accessibilityText('一次性展开全部步骤')
        Button('重置')
          .height(40)
          .fontSize(12)
          .layoutWeight(1)
          .backgroundColor(this.palette.accentBackground)
          .fontColor(this.palette.accentText)
          .enabled(this.visibleStepCount > 0 && !this.hasAnswered)
          .onClick(() => this.handleReset())
          .accessibilityText('重置竖式重新走一遍')
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .padding({ left: 14, right: 14, top: 10, bottom: 12 })
  }

  @Builder
  private DemoView() {
    Column() {
      // Error banner
      if (this.errorMessage !== '') {
        Row() {
          Text(this.errorMessage)
            .fontSize(13)
            .fontColor(this.palette.errorText)
            .layoutWeight(1)
        }
        .padding(11)
        .backgroundColor(this.palette.errorBackground)
        .borderRadius(12)
        .margin({ left: 14, right: 14, bottom: 8 })
      }

      // Input form (visible when no solution)
      if (this.solution === null) {
        this.InputForm()
      }

      // Board + narrator + legend + step bar (visible when solution exists)
      if (this.solution !== null) {
        this.ExpressionHeader()
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
            compact: this.largeSize ? false : true,
            isDarkMode: this.isDarkMode,
            reduceMotion: this.reduceMotion
          })
          this.Legend()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        this.StepBar()
      }
    }
    .width('100%')
  }

  @Builder
  private PracticeProgressRow() {
    Row() {
      Text(`第 ${this.practiceIndex + 1} / ${this.practiceProblems.length} 题`)
        .fontSize(12)
        .fontColor(this.palette.secondaryText)
        .layoutWeight(1)
      Text(this.operationName(this.practiceOperation))
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.accentText)
        .backgroundColor(this.palette.accentBackground)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .borderRadius(999)
    }
    .padding({ left: 14, right: 14, top: 4, bottom: 6 })
  }

  @Builder
  private PracticeAnswerCard() {
    Column() {
      Row() {
        Text(`${this.practiceOperationSymbolText()} ＝`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontFamily('ui-monospace, SFMono-Regular, Menlo, monospace')
          .fontColor(this.palette.ink)
        TextInput({ text: this.practiceInput, placeholder: '?' })
          .type(InputType.Number)
          .width(110)
          .height(48)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 10 })
          .enabled(!this.practiceAnswered && !this.hasAnswered)
          .onChange((v: string) => this.handlePracticeInput(v))
          .accessibilityText('输入答案')
      }
      .alignItems(VerticalAlign.Center)

      if (this.practiceError !== '') {
        Text(this.practiceError)
          .fontSize(13)
          .fontColor(this.palette.errorText)
          .margin({ top: 8 })
          .width('100%')
      }
      if (this.practiceAnswered && this.practiceCorrect) {
        Text('答对啦！')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette.success)
          .margin({ top: 8 })
          .width('100%')
      }
      if (this.practiceAnswered && !this.practiceCorrect) {
        Text(this.buildWrongFeedback())
          .fontSize(14)
          .fontColor(this.palette.errorText)
          .margin({ top: 8 })
          .width('100%')
      }
    }
    .padding(14)
    .backgroundColor(this.largeSize ? Color.Transparent : this.palette.paper)
    .borderRadius(14)
    .alignItems(HorizontalAlign.Start)
  }

  private practiceOperationSymbolText(): string {
    const problem = this.getCurrentProblem()
    if (problem === null) return ''
    return `${problem.a} ${this.operationSymbol(problem.operation)} ${problem.b}`
  }

  private buildWrongFeedback(): string {
    const problem = this.getCurrentProblem()
    if (problem === null) return '再想想～'
    return `再想想～ 正确答案是 ${problem.answer}，可以看下面的竖式讲解。`
  }

  @Builder
  private PracticeActions() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button('换一题')
          .height(44)
          .fontSize(13)
          .layoutWeight(1)
          .backgroundColor(this.palette.accentBackground)
          .fontColor(this.palette.accentText)
          .enabled(!this.hasAnswered)
          .visibility(!this.practiceAnswered || !this.isLastProblem() ? Visibility.Visible : Visibility.None)
          .onClick(() => this.handlePracticeSkip())
          .accessibilityText('换一道题')
        Button(this.getPracticePrimaryLabel())
          .height(44)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .backgroundColor(this.hasAnswered ? this.palette.disabledBackground : this.palette.focus)
          .fontColor(this.hasAnswered ? this.palette.disabledText : this.palette.focusText)
          .enabled(!this.hasAnswered)
          .onClick(() => this.handlePracticePrimary())
          .accessibilityText(this.getPracticePrimaryLabel())
      }
      .width('100%')
      if (this.practiceAnswered && this.practiceRevealSolution !== null && !this.hasAnswered) {
        Button(this.practiceShowSolution ? '收起讲解' : '查看竖式讲解')
          .height(40)
          .width('100%')
          .fontSize(13)
          .backgroundColor(this.palette.accentBackground)
          .fontColor(this.palette.accentText)
          .onClick(() => { this.practiceShowSolution = !this.practiceShowSolution })
          .accessibilityText('切换竖式讲解')
      }
    }
    .padding({ left: 14, right: 14, top: 4, bottom: 8 })
    .width('100%')
  }

  @Builder
  private PracticeScoreCard() {
    Row() {
      Column({ space: 2 }) {
        Text(`${this.practiceCorrectCount}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.success)
        Text('答对').fontSize(11).fontColor(this.palette.secondaryText)
      }
      .layoutWeight(1)
      Column({ space: 2 }) {
        Text(`${this.practiceAttemptCount}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.ink)
        Text('已答').fontSize(11).fontColor(this.palette.secondaryText)
      }
      .layoutWeight(1)
      Column({ space: 2 }) {
        Text(`${this.practiceStreak}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.ink)
        Text('连续答对').fontSize(11).fontColor(this.palette.secondaryText)
      }
      .layoutWeight(1)
    }
    .padding({ left: 14, right: 14, top: 6, bottom: 6 })
    .width('100%')
  }

  @Builder
  private PracticeRevealBoard() {
    Column({ space: 8 }) {
      Text('竖式讲解')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.secondaryText)
      if (this.practiceRevealSolution !== null) {
        VerticalMathBoard({
          solution: this.practiceRevealSolution,
          visibleStepCount: this.practiceRevealSolution.steps.length,
          compact: this.largeSize ? false : true,
          isDarkMode: this.isDarkMode,
          reduceMotion: this.reduceMotion
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 14, right: 14, top: 4, bottom: 10 })
  }

  @Builder
  private PracticeView() {
    Column() {
      this.PracticeProgressRow()
      if (this.practiceReplayPayload !== null) {
        this.PracticeReplaySummary()
      } else {
        this.PracticeConfigRow()
        this.PracticeAnswerCard()
        this.PracticeActions()
        this.PracticeScoreCard()
        if (this.practiceShowSolution && this.practiceRevealSolution !== null) {
          this.PracticeRevealBoard()
        }
      }
    }
    .width('100%')
  }

  @Builder
  private PracticeConfigRow() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        ForEach(OPERATION_BUTTONS, (item: OperationButtonDescriptor) => {
          Button(item.label)
            .layoutWeight(1)
            .height(40)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .borderRadius(10)
            .backgroundColor(this.practiceOperation === item.op ? this.palette.focus : this.palette.accentBackground)
            .fontColor(this.practiceOperation === item.op ? this.palette.focusText : this.palette.accentText)
            .enabled(!this.hasAnswered)
            .onClick(() => this.handlePracticeOperationChange(item.op))
            .accessibilityText(`练习${this.operationName(item.op)}`)
        }, (item: OperationButtonDescriptor) => `practice_op_${item.label}`)
      }
      .width('100%')

      Row({ space: 6 }) {
        ForEach(DIFFICULTY_BUTTONS, (item: DifficultyButtonDescriptor) => {
          Button(item.label)
            .layoutWeight(1)
            .height(36)
            .fontSize(13)
            .borderRadius(10)
            .backgroundColor(this.practiceDifficulty === item.level ? this.palette.focus : this.palette.accentBackground)
            .fontColor(this.practiceDifficulty === item.level ? this.palette.focusText : this.palette.accentText)
            .enabled(!this.hasAnswered)
            .onClick(() => this.handlePracticeDifficultyChange(item.level))
            .accessibilityText(`难度${item.label}`)
        }, (item: DifficultyButtonDescriptor) => `practice_lv_${item.level}`)
      }
      .width('100%')
    }
    .padding({ left: 14, right: 14, top: 2, bottom: 6 })
    .width('100%')
  }

  @Builder
  private PracticeReplaySummary() {
    Column({ space: 10 }) {
      Text(this.practiceReplayPayload?.completed === true ? '练习完成' : '练习已结束')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.ink)
      Row() {
        Column({ space: 2 }) {
          Text(`${this.practiceReplayPayload?.correct_count ?? 0}`)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.success)
          Text('答对').fontSize(11).fontColor(this.palette.secondaryText)
        }
        .layoutWeight(1)
        Column({ space: 2 }) {
          Text(`${this.practiceReplayPayload?.attempt_count ?? 0}`)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.ink)
          Text('已答').fontSize(11).fontColor(this.palette.secondaryText)
        }
        .layoutWeight(1)
        Column({ space: 2 }) {
          Text(`${this.practiceReplayPayload?.best_streak ?? 0}`)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.ink)
          Text('连续答对').fontSize(11).fontColor(this.palette.secondaryText)
        }
        .layoutWeight(1)
      }
      .width('100%')
      Text('结果已告诉小星老师')
        .fontSize(12)
        .fontColor(this.palette.secondaryText)
    }
    .padding(14)
    .backgroundColor(this.largeSize ? Color.Transparent : this.palette.paper)
    .borderRadius(14)
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      this.TabSwitch()
      if (this.activeTab === TAB_PRACTICE) {
        this.PracticeView()
      } else {
        this.DemoView()
      }
    }
    .width('100%')
    .backgroundColor(this.largeSize ? Color.Transparent : this.palette.shell)
  }
}
