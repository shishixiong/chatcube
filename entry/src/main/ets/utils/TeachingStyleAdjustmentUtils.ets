/**
 * 教学风格调整 utils
 * - 4 维度 enum 值 → 中文 label / 图标
 * - 进度条 0-5 档计算
 */

export type TeachingDimension =
  | 'difficultyTendency'
  | 'feedbackTone'
  | 'weakStrongBalance'
  | 'learningPace'

const DIMENSION_LABELS: Record<TeachingDimension, Record<string, string>> = {
  difficultyTendency: {
    'easier': '偏简单',
    'current': '保持',
    'harder': '偏难'
  },
  feedbackTone: {
    'gentle': '温柔鼓励',
    'neutral': '中性',
    'playful': '活泼'
  },
  weakStrongBalance: {
    'weak_focus': '弱项强化',
    'balanced': '均衡',
    'strong_focus': '强项深化'
  },
  learningPace: {
    'minimal': '精简',
    'standard': '适中',
    'extensive': '拓展'
  }
}

/**
 * 把维度 enum 值翻译成中文 label
 * - 未知 value 或未知 dimension: 返回原 value 字符串
 */
export function getDimensionLabel(dimension: string, value: string): string {
  const dimMap: Record<string, string> | undefined = DIMENSION_LABELS[dimension as TeachingDimension]
  if (dimMap === undefined) {
    return value
  }
  const label: string | undefined = dimMap[value]
  if (label === undefined) {
    return value
  }
  return label
}

/**
 * 进度条 0-5 档计算
 * - improvements 越多, 进度越高
 * - regressions 越多, 进度越低
 * - 中心点为 2 (3:3 时)
 * - 输出 clamp 到 [0, 5]
 */
export function computeTrendProgress(improvements: number, regressions: number): number {
  const raw: number = 2 + improvements - regressions
  if (raw < 0) {
    return 0
  }
  if (raw > 5) {
    return 5
  }
  return raw
}

/**
 * 进度档位 (0-5) → 简评
 */
export function getTrendRatingLabel(progress: number): string {
  if (progress <= 0) {
    return '待观察'
  }
  if (progress === 1) {
    return '偏差'
  }
  if (progress === 2) {
    return '中等'
  }
  if (progress <= 4) {
    return '较好'
  }
  return '优秀'
}