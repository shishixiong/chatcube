/**
 * 教学风格调整服务（4 维度）
 *
 * 责任：
 * - 评估老师（EvaluationService）写 saveAdjustment
 * - 主 agent（ChatViewModel）读 getCurrentAdjustment + renderForPrompt 拼到 systemPrompt
 * - 备课老师（LessonPlanningService）读 toSummary 作为 userInput.currentStyleAdjustment
 *
 * 数据流：
 *   EvaluationService 产出 TeachingStyleAdjustment → upsertTeachingStyleAdjustment
 *   → pulse TEACHING_STYLE_ADJUSTMENT_REFRESH_TICK
 *   → ChatViewModel 读 → renderForPrompt → 拼到 systemPrompt
 */

import { Context } from '@kit.AbilityKit'
import { formatLocalYMD } from '../models/LessonPlanModels'
import {
  TeachingStyleAdjustment,
  TeachingStyleAdjustmentRow,
  TeachingStyleAdjustmentSummary,
  TeachingStyleAdjustmentStatus,
  DifficultyTendency,
  FeedbackTone,
  WeakStrongBalance,
  LearningPace
} from '../models/TeachingReflectionModels'
import { getDatabaseService } from './DatabaseService'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { setAppUiStateValue } from '../state/AppUiState'
import { SHARED_OVERRIDE_HEADER } from '../utils/SharedPromptFragments'

// 默认有效期：14 天
const DEFAULT_EXPIRES_DAYS = 14
const MS_PER_DAY = 24 * 60 * 60 * 1000

// =================== 单例 ===================

export class TeachingStyleAdjustmentService {
  private static instance: TeachingStyleAdjustmentService | null = null

  static getInstance(): TeachingStyleAdjustmentService {
    if (TeachingStyleAdjustmentService.instance === null) {
      TeachingStyleAdjustmentService.instance = new TeachingStyleAdjustmentService()
    }
    return TeachingStyleAdjustmentService.instance
  }

  // =================== 生命周期 ===================

  /**
   * 初始化时清理过期 tsa 行。best-effort，失败不阻塞。
   */
  async initialize(_context: Context): Promise<void> {
    try {
      const deleted = await getDatabaseService().cleanupExpiredTeachingStyleAdjustments(Date.now())
      if (deleted > 0) {
        console.info('TeachingStyleAdjustmentService', `initialize cleaned up ${deleted} expired adjustments`)
      }
    } catch (e) {
      console.warn('TeachingStyleAdjustmentService', `initialize cleanup failed: ${JSON.stringify(e)}`)
    }
  }

  // =================== 写侧 ===================

  /**
   * 保存教学风格调整。
   * - 自动设置 expiresAt（如未设置）
   * - 自动生成 id（如未设置）
   * - 写后 pulse TEACHING_STYLE_ADJUSTMENT_REFRESH_TICK
   */
  async saveAdjustment(adj: TeachingStyleAdjustment): Promise<boolean> {
    if (adj.effectiveDate === '') {
      adj.effectiveDate = formatLocalYMD(new Date())
    }
    if (adj.expiresAt === 0) {
      adj.expiresAt = Date.now() + DEFAULT_EXPIRES_DAYS * MS_PER_DAY
    }
    if (adj.id === '') {
      adj.id = 'tsa_' + adj.effectiveDate.replace(/-/g, '')
    }
    if (adj.createdAt === 0) {
      adj.createdAt = Date.now()
    }
    const row = this.toRow(adj)
    const ok = await getDatabaseService().upsertTeachingStyleAdjustment(row)
    if (ok) {
      setAppUiStateValue(AppStorageKeys.TEACHING_STYLE_ADJUSTMENT_REFRESH_TICK, Date.now())
    }
    return ok
  }

  // =================== 读侧 ===================

  /**
   * 取当前生效的调整。
   * - asOfYMD: 'YYYY-MM-DD'（空字符串 = 今天）
   * - nowMs: 当前时间戳（用于 expires_at 比较）
   * - 失败行（status='failed'）一律跳过，返回 null（不应让前端 prompt 使用失败行的空 rationale）
   * - 返回 null 表示无当前可用的调整
   */
  async getCurrentAdjustment(asOfYMD: string = '', nowMs: number = Date.now()): Promise<TeachingStyleAdjustment | null> {
    const row = await getDatabaseService().getCurrentTeachingStyleAdjustment(asOfYMD, nowMs)
    if (row === null) {
      return null
    }
    if (row.status === TeachingStyleAdjustmentStatus.FAILED) {
      return null
    }
    return this.fromRow(row)
  }

  /**
   * 按 effective_date 查调整（精确匹配）
   */
  async getAdjustmentForDate(ymd: string): Promise<TeachingStyleAdjustment | null> {
    const current = await this.getCurrentAdjustment(ymd, Date.now())
    if (current !== null && current.effectiveDate === ymd) {
      return current
    }
    return null
  }

  /** 清理过期行。返回删除条数 */
  async cleanupExpired(nowMs: number = Date.now()): Promise<number> {
    return await getDatabaseService().cleanupExpiredTeachingStyleAdjustments(nowMs)
  }

  // =================== 转换工具 ===================

  /** Row → 完整对象 */
  fromRow(row: TeachingStyleAdjustmentRow): TeachingStyleAdjustment {
    const adj = new TeachingStyleAdjustment()
    adj.id = row.id
    adj.effectiveDate = row.effective_date
    adj.expiresAt = row.expires_at
    adj.sourceWeeklyTrendId = row.source_weekly_trend_id
    adj.sourceSessionCount = row.source_session_count
    adj.difficultyTendency = row.difficulty_tendency as DifficultyTendency
    adj.feedbackTone = row.feedback_tone as FeedbackTone
    adj.weakStrongBalance = row.weak_strong_balance as WeakStrongBalance
    adj.learningPace = row.learning_pace as LearningPace
    adj.difficultyRationale = row.difficulty_rationale
    adj.feedbackRationale = row.feedback_rationale
    adj.balanceRationale = row.balance_rationale
    adj.paceRationale = row.pace_rationale
    adj.evaluatorProviderId = row.evaluator_provider_id
    adj.evaluatorModelId = row.evaluator_model_id
    adj.evaluatorModelName = row.evaluator_model_name
    adj.confidence = row.confidence
    adj.status = row.status
    adj.createdAt = row.created_at
    return adj
  }

  /** 完整对象 → Row */
  toRow(adj: TeachingStyleAdjustment): TeachingStyleAdjustmentRow {
    const row = new TeachingStyleAdjustmentRow()
    row.id = adj.id
    row.effective_date = adj.effectiveDate
    row.expires_at = adj.expiresAt
    row.source_weekly_trend_id = adj.sourceWeeklyTrendId
    row.source_session_count = adj.sourceSessionCount
    row.difficulty_tendency = adj.difficultyTendency
    row.feedback_tone = adj.feedbackTone
    row.weak_strong_balance = adj.weakStrongBalance
    row.learning_pace = adj.learningPace
    row.difficulty_rationale = adj.difficultyRationale
    row.feedback_rationale = adj.feedbackRationale
    row.balance_rationale = adj.balanceRationale
    row.pace_rationale = adj.paceRationale
    row.evaluator_provider_id = adj.evaluatorProviderId
    row.evaluator_model_id = adj.evaluatorModelId
    row.evaluator_model_name = adj.evaluatorModelName
    row.confidence = adj.confidence
    row.status = adj.status
    row.created_at = adj.createdAt
    return row
  }

  /** 完整对象 → 摘要（备课老师 LLM 输入用） */
  toSummary(adj: TeachingStyleAdjustment): TeachingStyleAdjustmentSummary {
    const s = new TeachingStyleAdjustmentSummary()
    s.effectiveDate = adj.effectiveDate
    s.difficultyTendency = adj.difficultyTendency
    s.feedbackTone = adj.feedbackTone
    s.weakStrongBalance = adj.weakStrongBalance
    s.learningPace = adj.learningPace
    s.difficultyRationale = adj.difficultyRationale
    s.feedbackRationale = adj.feedbackRationale
    s.balanceRationale = adj.balanceRationale
    s.paceRationale = adj.paceRationale
    return s
  }

  // =================== Prompt 渲染 ===================

  /**
   * 把 TeachingStyleAdjustment 渲染为注入 systemPrompt 末尾的 4 维度段。
   * 格式与 plan §3.4 一致：5 行分点 + 1 行 "不要逐条复述给小朋友" 提示。
   */
  renderForPrompt(adj: TeachingStyleAdjustment): string {
    if (adj.effectiveDate === '') {
      return ''
    }
    const lines: string[] = []
    lines.push(`## 今日教学风格 (评估于 ${adj.effectiveDate})`)
    lines.push('')
    lines.push(SHARED_OVERRIDE_HEADER)
    lines.push(`- 出题难度: ${this.difficultyLabel(adj.difficultyTendency)} (${adj.difficultyRationale})`)
    lines.push(`- 反馈语气: ${this.feedbackToneLabel(adj.feedbackTone)} (${adj.feedbackRationale})`)
    lines.push(`- 弱强比重: ${this.balanceLabel(adj.weakStrongBalance)} (${adj.balanceRationale})`)
    lines.push(`- 学习节奏: ${this.paceLabel(adj.learningPace)} (${adj.paceRationale})`)
    lines.push('')
    lines.push('以上风格调整是给你(小星老师)看的元指令,**不要逐条复述给小朋友**。')
    lines.push('小朋友的回复仍要保持 1-3 句、不超过 50 字、不分点。')
    return lines.join('\n')
  }

  // 4 维度中文 label 字典（避免 switch 块，Record 查表）
  private difficultyLabel(v: DifficultyTendency): string {
    const map: Record<DifficultyTendency, string> = {
      'easier': '偏简单',
      'current': '保持当前难度',
      'harder': '可挑战'
    }
    return map[v]
  }

  private feedbackToneLabel(v: FeedbackTone): string {
    const map: Record<FeedbackTone, string> = {
      'gentle': '温柔鼓励',
      'neutral': '中性专业',
      'playful': '活泼游戏化'
    }
    return map[v]
  }

  private balanceLabel(v: WeakStrongBalance): string {
    const map: Record<WeakStrongBalance, string> = {
      'weak_focus': '弱项强化(70%)',
      'balanced': '均衡(50/50)',
      'strong_focus': '强项巩固(70%)'
    }
    return map[v]
  }

  private paceLabel(v: LearningPace): string {
    const map: Record<LearningPace, string> = {
      'minimal': '少而精(2-3 点)',
      'standard': '适中(3-4 点)',
      'extensive': '多而广(5-6 点)'
    }
    return map[v]
  }
}

export function getTeachingStyleAdjustmentService(): TeachingStyleAdjustmentService {
  return TeachingStyleAdjustmentService.getInstance()
}
