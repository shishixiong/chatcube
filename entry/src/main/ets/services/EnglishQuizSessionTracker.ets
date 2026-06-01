/**
 * 英语出题工具会话答题追踪
 *
 * 内存中追踪每个 session 的答题计数和正确率。
 * 当答题数达到 10 的倍数时，提示 AI 调用 english_progress 生成阶段总结。
 */

class SessionQuizStats {
  total: number = 0
  correct: number = 0
  bySkillKey: Record<string, SkillQuizStats> = {}
}

class SkillQuizStats {
  total: number = 0
  correct: number = 0

  constructor(total: number = 0, correct: number = 0) {
    this.total = total
    this.correct = correct
  }
}

export class EnglishQuizSessionStats {
  total: number = 0
  correct: number = 0
  accuracy: number = 0
  bySkillKey: Record<string, SkillQuizStats> = {}

  constructor(total: number = 0, correct: number = 0, accuracy: number = 0,
    bySkillKey: Record<string, SkillQuizStats> = {}) {
    this.total = total
    this.correct = correct
    this.accuracy = accuracy
    this.bySkillKey = bySkillKey
  }
}

export class EnglishQuizSessionTracker {
  private static instance: EnglishQuizSessionTracker | null = null
  private sessions: Map<string, SessionQuizStats> = new Map()

  private constructor() {}

  static getInstance(): EnglishQuizSessionTracker {
    if (EnglishQuizSessionTracker.instance === null) {
      EnglishQuizSessionTracker.instance = new EnglishQuizSessionTracker()
    }
    return EnglishQuizSessionTracker.instance
  }

  /**
   * 记录一次答题
   */
  recordAnswer(sessionId: string, correct: boolean, skillKey: string): void {
    if (sessionId === '') {
      return
    }
    let stats = this.sessions.get(sessionId)
    if (stats === undefined) {
      stats = new SessionQuizStats()
      this.sessions.set(sessionId, stats)
    }
    stats.total += 1
    if (correct) {
      stats.correct += 1
    }

    // 按技能维度统计
    if (skillKey !== '') {
      let skillStats = stats.bySkillKey[skillKey]
      if (skillStats === undefined) {
        skillStats = new SkillQuizStats()
        stats.bySkillKey[skillKey] = skillStats
      }
      skillStats.total += 1
      if (correct) {
        skillStats.correct += 1
      }
    }
  }

  /**
   * 获取会话统计
   */
  getSessionStats(sessionId: string): EnglishQuizSessionStats {
    const stats = this.sessions.get(sessionId)
    if (stats === undefined) {
      return new EnglishQuizSessionStats()
    }
    const accuracy = stats.total > 0 ? Math.round((stats.correct / stats.total) * 100) : 0
    return new EnglishQuizSessionStats(stats.total, stats.correct, accuracy, stats.bySkillKey)
  }

  /**
   * 判断是否应该生成阶段总结（每 10 题）
   */
  shouldSummarize(sessionId: string): boolean {
    const stats = this.sessions.get(sessionId)
    if (stats === undefined || stats.total === 0) {
      return false
    }
    return stats.total % 10 === 0
  }

  /**
   * 清理会话数据
   */
  clearSession(sessionId: string): void {
    this.sessions.delete(sessionId)
  }

  /**
   * 清理所有会话数据
   */
  clearAll(): void {
    this.sessions.clear()
  }
}

export function getEnglishQuizSessionTracker(): EnglishQuizSessionTracker {
  return EnglishQuizSessionTracker.getInstance()
}
