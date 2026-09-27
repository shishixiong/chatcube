/**
 * MathTeachCard - 数学讲解板互动卡片（math_teach 工具）
 *
 * 解析 toolCall.arguments 中的讲解参数（8 种 mode），分发到对应讲解板组件；
 * 孩子在板内动手操作（onInteract 计数），达到门槛后可点「我学会了 · 继续」
 * 提交 MathTeachResult。无对错判定，完成即成功。
 *
 * 参考 MathQuizCard 模式: @ComponentV2 + CardShell 外壳 + @Event onAnswer 回调。
 * Task 8 of math-teach suite; MessageBubble 挂载见 Task 9。
 */

import { CardShell } from './cardshell/CardShell'
import { CardShellConfig } from './cardshell/CardShellTypes'
import { CardShellState } from './cardshell/CardShellState'
import { ToolCall } from '../models/ChatModels'
import { KIDS_MATH_INK, KIDS_MUTED } from './kids/KidsBrandTokens'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { NumberBondBoard } from './mathTeach/NumberBondBoard'
import { NumberLineBoard } from './mathTeach/NumberLineBoard'
import { TenFrameBoard } from './mathTeach/TenFrameBoard'
import { PlaceValueBoard } from './mathTeach/PlaceValueBoard'
import { BalanceBoard } from './mathTeach/BalanceBoard'
import { ShapeBoard } from './mathTeach/ShapeBoard'
import { ClockBoard } from './mathTeach/ClockBoard'
import { BarModelBoard } from './mathTeach/BarModelBoard'

export interface MathTeachResult {
  mode: string
  skill_key: string
  stage: string
  completed: boolean
  interactions: number
}

interface MathTeachArgsView {
  valid: boolean
  mode: string
  stage: string
  difficulty: number
  concept: string
  skill_key: string
  total: number
  start: number
  step: number
  a: number
  b: number
  tens: number
  ones: number
  left: number
  right: number
  focus: string
  hour: number
  minute: number
  part_a: number
  part_b: number
}

const TEACH_MODES_ZH: Record<string, string> = {
  'number_bond': '数的分与合',
  'number_line': '数轴凑十跳',
  'ten_frame': '十格阵凑十',
  'place_value': '小棒与数位',
  'balance': '天平比大小',
  'shape': '图形数一数',
  'clock': '时钟拨一拨',
  'bar_model': '应用题图解'
}

const STAGE_ZH: Record<string, string> = {
  'warm_up': '热身',
  'presentation': '讲解',
  'practice': '操练',
  'production': '输出',
  'review': '复习'
}

function getNum(obj: Record<string, Object>, key: string, dflt: number): number {
  const v: Object | undefined = obj[key]
  if (typeof v === 'number') {
    const n: number = v as number
    if (!Number.isNaN(n)) { return n }
  }
  return dflt
}

function getStr(obj: Record<string, Object>, key: string, dflt: string): string {
  const v: Object | undefined = obj[key]
  if (typeof v === 'string') { return v as string }
  return dflt
}

function createDefaultArgsView(): MathTeachArgsView {
  const view: MathTeachArgsView = {
    valid: false, mode: '', stage: 'presentation', difficulty: 1, concept: '', skill_key: '',
    total: 9, start: 9, step: 5, a: 9, b: 5, tens: 1, ones: 5, left: 9, right: 5,
    focus: 'circle', hour: 9, minute: 0, part_a: 5, part_b: 5
  }
  return view
}

export function parseMathTeachArgs(raw: string): MathTeachArgsView {
  const view: MathTeachArgsView = createDefaultArgsView()
  try {
    const obj = JSON.parse(raw) as Record<string, Object>
    const mode: string = getStr(obj, 'mode', '')
    const stageRaw: string = getStr(obj, 'stage', 'presentation')
    // 显式拓宽为 string | undefined 再判空——避免 Record<string,string> 下标
    // 直接待 undefined 的 no-overlap 比较歧义（与 modeZhOf 同一写法）
    const modeKnown: string | undefined = TEACH_MODES_ZH[mode]
    if (modeKnown === undefined) {
      return view
    }
    const stageKnown: string | undefined = STAGE_ZH[stageRaw]
    view.valid = true
    view.mode = mode
    view.stage = stageKnown !== undefined ? stageRaw : 'presentation'
    view.difficulty = getNum(obj, 'difficulty', 1)
    view.concept = getStr(obj, 'concept', '')
    view.skill_key = getStr(obj, 'skill_key', '')
    view.total = getNum(obj, 'total', 9)
    view.start = getNum(obj, 'start', 9)
    view.step = getNum(obj, 'step', 5)
    view.a = getNum(obj, 'a', 9)
    view.b = getNum(obj, 'b', 5)
    view.tens = getNum(obj, 'tens', 1)
    view.ones = getNum(obj, 'ones', 5)
    view.left = getNum(obj, 'left', 9)
    view.right = getNum(obj, 'right', 5)
    view.focus = getStr(obj, 'focus', 'circle')
    view.hour = getNum(obj, 'hour', 9)
    view.minute = getNum(obj, 'minute', 0)
    view.part_a = getNum(obj, 'part_a', 5)
    view.part_b = getNum(obj, 'part_b', 5)
  } catch (_e) {
    return view
  }
  return view
}

function modeZhOf(mode: string): string {
  const z: string | undefined = TEACH_MODES_ZH[mode]
  if (z === undefined) { return '讲解板' }
  return z
}

function stageZhOf(stage: string): string {
  const z: string | undefined = STAGE_ZH[stage]
  if (z === undefined) { return '讲解' }
  return z
}

@ComponentV2
export struct MathTeachCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = (_id: string, _a: string) => {}

  @Local interactions: number = 0
  @Local submitted: boolean = false
  private shellState: CardShellState = new CardShellState()
  private argsView: MathTeachArgsView = createDefaultArgsView()

  aboutToAppear(): void {
    this.argsView = parseMathTeachArgs(this.toolCall.arguments)
    // 本卡片无对错判定（完成即成功），永久抑制对/错反馈横幅：
    // 已答历史态 isAnswered=true 会让 CardShell 渲染反馈区，而 shellState 默认
    // isCorrect=false 会被误渲染成假「再试一次」横幅（同 MathQuizCard payload
    // 丢失场景的处理），完成状态由 ControlArea 的「已学会」行表达。
    this.shellState.feedbackSuppressed = true
  }

  private interactionThreshold(): number {
    return this.argsView.mode === 'shape' ? 2 : 1
  }

  private canSubmit(): boolean {
    return this.interactions >= this.interactionThreshold()
  }

  private submit(): void {
    if (this.submitted || !this.canSubmit()) { return }
    this.submitted = true
    const result: MathTeachResult = {
      mode: this.argsView.mode,
      skill_key: this.argsView.skill_key,
      stage: this.argsView.stage,
      completed: true,
      interactions: this.interactions
    }
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
  }

  private answeredTail(): string {
    try {
      const obj = JSON.parse(this.answeredPayload) as Record<string, Object>
      const n: Object | undefined = obj['interactions']
      if (typeof n === 'number' && (n as number) > 0) {
        return ' · 动手 ' + (n as number) + ' 次'
      }
    } catch (_e) {
    }
    return ''
  }

  private shellConfig(): CardShellConfig {
    const config: CardShellConfig = {
      title: '数学讲解板',
      subtitle: modeZhOf(this.argsView.mode) + ' · ' + stageZhOf(this.argsView.stage),
      icon: $r('sys.symbol.lightbulb'),
      stem: this.argsView.concept === '' ? '这道讲解出错了，老师马上换一张' : this.argsView.concept,
      hasAudio: false,
      usesConfirm: false,
      feedbackTitleCorrect: '',
      correctAnswerLabel: ''
    }
    return config
  }

  private countInteract(): void {
    this.interactions += 1
  }

  @Builder
  BoardArea() {
    if (!this.argsView.valid) {
      Text('这道讲解出错了，老师马上换一张')
        .fontSize(14).fontColor(KIDS_MUTED)
        .padding({ top: 8, bottom: 8 })
    } else if (this.argsView.mode === 'number_bond') {
      NumberBondBoard({ total: this.argsView.total, readonly: this.isAnswered, onInteract: () => { this.countInteract() } })
    } else if (this.argsView.mode === 'number_line') {
      NumberLineBoard({ start: this.argsView.start, step: this.argsView.step, readonly: this.isAnswered, onInteract: () => { this.countInteract() } })
    } else if (this.argsView.mode === 'ten_frame') {
      TenFrameBoard({ a: this.argsView.a, b: this.argsView.b, readonly: this.isAnswered, onInteract: () => { this.countInteract() } })
    } else if (this.argsView.mode === 'place_value') {
      PlaceValueBoard({ tens: this.argsView.tens, ones: this.argsView.ones, readonly: this.isAnswered, onInteract: () => { this.countInteract() } })
    } else if (this.argsView.mode === 'balance') {
      BalanceBoard({ left: this.argsView.left, right: this.argsView.right, readonly: this.isAnswered, onInteract: () => { this.countInteract() } })
    } else if (this.argsView.mode === 'shape') {
      ShapeBoard({ focus: this.argsView.focus, readonly: this.isAnswered, onInteract: () => { this.countInteract() } })
    } else if (this.argsView.mode === 'clock') {
      ClockBoard({ hour: this.argsView.hour, minute: this.argsView.minute, readonly: this.isAnswered, onInteract: () => { this.countInteract() } })
    } else if (this.argsView.mode === 'bar_model') {
      BarModelBoard({ partA: this.argsView.part_a, partB: this.argsView.part_b, readonly: this.isAnswered, onInteract: () => { this.countInteract() } })
    }
  }

  @Builder
  ControlArea() {
    if (this.isAnswered) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.checkmark_circle'))
          .fontSize(14)
          .fontColor([$r('app.color.status_success')])
        Text('已学会' + this.answeredTail())
          .fontSize(13)
          .fontColor($r('app.color.status_success'))
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    } else if (this.argsView.valid) {
      Button('我学会了 · 继续')
        .width('100%').height(44)
        .fontSize(15)
        .backgroundColor(this.canSubmit() ? KIDS_MATH_INK : withColorAlpha(KIDS_MATH_INK, '33'))
        .fontColor(Color.White)
        .enabled(this.canSubmit())
        .opacity(this.canSubmit() ? 1 : 0.55)
        .onClick(() => { this.submit() })
    }
  }

  build() {
    CardShell({
      config: this.shellConfig(),
      state: this.shellState,
      isAnswered: this.isAnswered,
      correctAnswerText: '',
      onConfirm: () => {},
      onRetry: () => {}
    }) {
      Column({ space: 12 }) {
        this.BoardArea()
        this.ControlArea()
      }
      .width('100%')
    }
  }
}
