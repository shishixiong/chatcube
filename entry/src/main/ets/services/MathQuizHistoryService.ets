/**
 * math_quiz 难度渐进 — 服务层编排
 *
 * 职责：出题前判定难度门槛（evaluateGate），答题后落库 + 推进等级（recordAnswer），
 * 并提供画像摘要（getProgressSummary）。纯判定逻辑全部在 utils/MathQuizProgression.ets，
 * 本服务只做数据库 / 画像读取与组合，不依赖 BuiltinTools / ToolExecutionService / UI。
 */

import { getDatabaseService } from './DatabaseService'
import type { DatabaseService } from './DatabaseService'
import { getChildProfileService } from './ChildProfileService'
import type { ChildKnowledgeProfile, SkillDimension } from './ChildProfileService'
import { parseMathQuizAnswer } from '../utils/MathQuizGame'
import type { MathQuizAnswerPayload } from '../utils/MathQuizGame'
import {
  MATH_QUIZ_NEEDED_CORRECT, MATH_QUIZ_RECENT_LIMIT, applyMathQuizProgress, buildMathQuizProgressHint,
  buildMathQuizRecordExpression, buildTarget, evaluateMathQuizGate, getLevelSpec, initialLevelForTrack,
  normalizeSkillKey, parseMathQuizGatingArgs, resolveMathQuizLevel
} from '../utils/MathQuizProgression'
import type { MathQuizGatingArgs } from '../utils/MathQuizProgression'
import type {
  ChildProfileMathProgress, MathQuizGateInput, MathQuizGateResult, MathQuizLevelInfo,
  MathQuizProgressHint, MathQuizProgressRow, MathQuizProgressSnapshot, MathQuizProgressUpdate,
  MathQuizRecordInsert, MathQuizRecordRow, MathQuizTarget, MathQuizTrack
} from '../models/MathQuizProgressionModels'

const SUMMARY_TRACKS: MathQuizTrack[] = ['add', 'sub', 'muldiv', 'compare', 'clock', 'elapsed']
const SUMMARY_PROFILE_KEYS: string[] =
  ['math_addition', 'math_subtraction', 'math_multiply', 'math_divide', 'math_comparison', 'math_time']
const TAG: string = 'MathQuizHistoryService'

export class MathQuizHistoryService {
  private static instance: MathQuizHistoryService | null = null
  private database: DatabaseService

  private constructor(database: DatabaseService) {
    this.database = database
  }

  static getInstance(): MathQuizHistoryService {
    if (MathQuizHistoryService.instance === null) {
      MathQuizHistoryService.instance = new MathQuizHistoryService(getDatabaseService())
    }
    return MathQuizHistoryService.instance
  }

  /**
   * 读取某轨道的有效进度：优先数据库进度行；没有则按孩子画像推导初始等级（只读不写）。
   */
  async getEffectiveProgress(track: MathQuizTrack): Promise<MathQuizProgressRow> {
    try {
      const row: MathQuizProgressRow | null = await this.database.getMathQuizProgress(track)
      if (row !== null) {
        return row
      }
    } catch (error) {
      console.warn(TAG, `read progress failed: ${String(error)}`)
    }
    let level: number = 1
    try {
      const profile: ChildKnowledgeProfile = await getChildProfileService().getProfile()
      const levels: Record<string, number> = {}
      for (const key of SUMMARY_PROFILE_KEYS) {
        const dim: Object | undefined = profile.skills[key]
        if (dim !== undefined && dim !== null) {
          levels[key] = (dim as SkillDimension).level
        }
      }
      level = initialLevelForTrack(track, levels)
    } catch (error) {
      console.warn(TAG, `profile initial level failed: ${String(error)}`)
      level = 1
    }
    const initial: MathQuizProgressRow = {
      track: track, currentLevel: level, correctAtLevel: 0, consecutiveWrong: 0, updatedAt: 0
    }
    return initial
  }

  /**
   * 出题前门槛：解析题目 → 判定级别 → 读取进度 / 最近题目 / 本会话额度 → 放行或拒绝。
   */
  async evaluateGate(argsJson: string, sessionId: string): Promise<MathQuizGateResult> {
    const gating: MathQuizGatingArgs | null = parseMathQuizGatingArgs(argsJson)
    if (gating === null) {
      const parseFailed: MathQuizGateResult = {
        ok: false, error: 'difficulty_gate', message: 'math_quiz 参数解析失败，请检查 JSON 后重试',
        target: null, progress: null
      }
      return parseFailed
    }
    const info: MathQuizLevelInfo = resolveMathQuizLevel(gating.input)
    if (!info.gate && info.error === '') {
      const allowed: MathQuizGateResult = { ok: true, error: '', message: '', target: null, progress: null }
      return allowed
    }
    const progress: MathQuizProgressRow = await this.getEffectiveProgress(info.track)
    const recentKeys: string[] = []
    if (gating.purpose === 'practice' && info.expressionKey !== '') {
      try {
        const records: MathQuizRecordRow[] = await this.database.getRecentMathQuizRecords(
          info.track, MATH_QUIZ_RECENT_LIMIT)
        for (const record of records) {
          recentKeys.push(record.expressionKey)
        }
      } catch (error) {
        console.warn(TAG, `recent records read failed: ${String(error)}`)
      }
    }
    let purposeCount: number = 0
    if ((gating.purpose === 'warm_up' || gating.purpose === 'review') && sessionId !== '') {
      try {
        purposeCount = await this.database.countMathQuizPurposeInSession(sessionId, gating.purpose)
      } catch (error) {
        console.warn(TAG, `purpose count read failed: ${String(error)}`)
        purposeCount = 0
      }
    }
    const gateInput: MathQuizGateInput = {
      info: info,
      purpose: gating.purpose,
      progressLevel: progress.currentLevel,
      recentExpressionKeys: recentKeys,
      purposeCountInSession: purposeCount,
      sessionId: sessionId
    }
    const decision = evaluateMathQuizGate(gateInput)
    const snapshot: MathQuizProgressSnapshot = {
      correct_at_level: progress.correctAtLevel,
      needed: MATH_QUIZ_NEEDED_CORRECT,
      consecutive_wrong: progress.consecutiveWrong
    }
    const result: MathQuizGateResult = {
      ok: decision.allowed,
      error: decision.error,
      message: decision.message,
      target: decision.target,
      progress: snapshot
    }
    return result
  }

  /**
   * 答题后记录：落库，可计数时推进等级，返回给 AI 的进度提示；不满足记录条件返回 null。
   */
  async recordAnswer(argsJson: string, answerJson: string, sessionId: string,
    toolCallId: string): Promise<MathQuizProgressHint | null> {
    const gating: MathQuizGatingArgs | null = parseMathQuizGatingArgs(argsJson)
    const answer: MathQuizAnswerPayload | null = parseMathQuizAnswer(answerJson)
    if (gating === null || answer === null || answer.answered !== true) {
      return null
    }
    let raw: Record<string, Object> | null = null
    try {
      raw = JSON.parse(argsJson) as Record<string, Object>
    } catch (_error) {
      return null
    }
    if (raw === null) {
      return null
    }
    const info: MathQuizLevelInfo = resolveMathQuizLevel(gating.input)
    const attempts: number = this.resolveAttempts(answer)
    const record: MathQuizRecordInsert = {
      createdAt: Date.now(),
      sessionId: sessionId,
      toolCallId: toolCallId,
      quizType: gating.input.quizType,
      track: info.track,
      level: info.level,
      purpose: gating.purpose,
      skillKey: normalizeSkillKey(gating.input.skillKey),
      expressionKey: info.expressionKey,
      expression: buildMathQuizRecordExpression(gating.input),
      question: this.readRawString(raw, 'question'),
      correct: answer.correct === true,
      firstTry: answer.correct === true && attempts === 1,
      attempts: attempts,
      childAnswer: String(answer.child_answer),
      correctAnswer: String(answer.correct_answer),
      counted: false,
      metadataJson: ''
    }
    if (!info.gate || info.error !== '') {
      try {
        await this.database.insertMathQuizRecord(record)
      } catch (error) {
        console.warn(TAG, `ungated record insert failed: ${String(error)}`)
      }
      return null
    }
    try {
      const progress: MathQuizProgressRow = await this.getEffectiveProgress(info.track)
      const update: MathQuizProgressUpdate = applyMathQuizProgress(progress, info.level, gating.purpose,
        answer.correct === true, attempts, Date.now())
      record.counted = update.counted
      const rowId: number = await this.database.recordMathQuizAnswer(record, update.counted ? update.row : null)
      if (rowId < 0) {
        return null
      }
      return buildMathQuizProgressHint(update, info.track, MATH_QUIZ_NEEDED_CORRECT)
    } catch (error) {
      console.warn(TAG, `record answer failed: ${String(error)}`)
      return null
    }
  }

  /**
   * 孩子画像摘要：六个可度量轨道的当前等级、本级进度与下一目标。
   */
  async getProgressSummary(): Promise<ChildProfileMathProgress[]> {
    try {
      const summary: ChildProfileMathProgress[] = []
      for (const track of SUMMARY_TRACKS) {
        const row: MathQuizProgressRow = await this.getEffectiveProgress(track)
        const spec = getLevelSpec(track, row.currentLevel)
        if (spec === null) {
          continue
        }
        const nextTarget: MathQuizTarget = buildTarget(spec)
        const item: ChildProfileMathProgress = {
          track: track,
          level: row.currentLevel,
          label: spec.label,
          correct_at_level: row.correctAtLevel,
          needed: MATH_QUIZ_NEEDED_CORRECT,
          nextTarget: nextTarget
        }
        summary.push(item)
      }
      return summary
    } catch (error) {
      console.warn(TAG, `progress summary failed: ${String(error)}`)
      return []
    }
  }

  private resolveAttempts(answer: MathQuizAnswerPayload): number {
    const rawAttempts: number = answer.attempts !== undefined ? answer.attempts as number : 0
    if (rawAttempts > 0) {
      return rawAttempts
    }
    return answer.correct === true ? 1 : 2
  }

  private readRawString(raw: Record<string, Object>, key: string): string {
    const value: Object | undefined = raw[key]
    return typeof value === 'string' ? value as string : ''
  }
}

export function getMathQuizHistoryService(): MathQuizHistoryService {
  return MathQuizHistoryService.getInstance()
}
