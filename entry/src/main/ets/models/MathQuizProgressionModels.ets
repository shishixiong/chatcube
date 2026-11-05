/**
 * math_quiz 难度渐进 — 纯数据模型
 *
 * 只含类型与接口, 无副作用; 判定逻辑在 utils/MathQuizProgression.ets,
 * 持久化在 services/MathQuizHistoryService.ets + DatabaseService。
 */

export type MathQuizTrack = 'add' | 'sub' | 'muldiv' | 'compare' | 'clock' | 'elapsed' | 'shape' | 'none'

export type MathQuizPurpose = 'practice' | 'warm_up' | 'review'

export type MathQuizProgressStatus = 'in_progress' | 'level_up' | 'level_down' | 'max_level' | 'not_counted'

export type MathQuizProgressReason =
  'first_try_correct' | 'second_try' | 'two_wrong' | 'warm_up' | 'review' | 'stale_level'

export interface MathQuizLevelSpec {
  track: MathQuizTrack
  level: number
  label: string
  maxOperand: number
  minSteps: number
  maxSteps: number
  carryRule: 'none' | 'required' | 'any'
  constraint: string
  example: string
}

export interface MathQuizLevelInput {
  quizType: string
  expression: string
  wordProblem: boolean
  skillKey: string
  leftValue: number
  rightValue: number
  clockHour: number
  clockMinute: number
  startHour: number
  startMinute: number
  endHour: number
  endMinute: number
}

export interface MathQuizLevelInfo {
  track: MathQuizTrack
  level: number
  gate: boolean
  spec: MathQuizLevelSpec | null
  expressionKey: string
  error: string
}

export interface MathQuizTarget {
  track: string
  level: number
  label: string
  max_operand?: number
  steps?: string
  carry?: string
  constraint?: string
  example: string
}

export interface MathQuizRecordInsert {
  createdAt: number
  sessionId: string
  toolCallId: string
  quizType: string
  track: string
  level: number
  purpose: string
  skillKey: string
  expressionKey: string
  expression: string
  question: string
  correct: boolean
  firstTry: boolean
  attempts: number
  childAnswer: string
  correctAnswer: string
  counted: boolean
  metadataJson: string
}

export interface MathQuizRecordRow {
  id: number
  createdAt: number
  sessionId: string
  toolCallId: string
  quizType: string
  track: string
  level: number
  purpose: string
  skillKey: string
  expressionKey: string
  expression: string
  question: string
  correct: boolean
  firstTry: boolean
  attempts: number
  childAnswer: string
  correctAnswer: string
  counted: boolean
  metadataJson: string
}

export interface MathQuizProgressRow {
  track: string
  currentLevel: number
  correctAtLevel: number
  consecutiveWrong: number
  updatedAt: number
}

export interface MathQuizProgressUpdate {
  row: MathQuizProgressRow
  counted: boolean
  status: MathQuizProgressStatus
  reason: MathQuizProgressReason
}

export interface MathQuizProgressHint {
  track: string
  level: number
  level_label: string
  correct_at_level: number
  needed: number
  consecutive_wrong: number
  status: string
  reason: string
  next_target: MathQuizTarget
}

export interface MathQuizGateInput {
  info: MathQuizLevelInfo
  purpose: MathQuizPurpose
  progressLevel: number
  recentExpressionKeys: string[]
  purposeCountInSession: number
  sessionId: string
}

export interface MathQuizGateDecision {
  allowed: boolean
  error: string
  message: string
  target: MathQuizTarget | null
}

export interface MathQuizProgressSnapshot {
  correct_at_level: number
  needed: number
  consecutive_wrong: number
}

export interface MathQuizGateResult {
  ok: boolean
  error: string
  message: string
  target: MathQuizTarget | null
  progress: MathQuizProgressSnapshot | null
}

export interface ChildProfileMathProgress {
  track: string
  level: number
  label: string
  correct_at_level: number
  needed: number
  nextTarget: MathQuizTarget
}
