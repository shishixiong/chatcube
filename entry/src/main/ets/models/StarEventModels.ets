/**
 * 星星事件数据模型
 *
 * 用于星星奖励系统的核心数据契约。
 * - 写入: StarRewardService.recordEvent
 * - 存储: SQLite 表 star_events
 * - 读取: ChatPage 标题栏菜单项 / TodayStarDetailSheet
 */

export type StarActivityType = 'math_quiz' | 'english_quiz' | 'number_puzzle' | 'handwriting_practice' | 'categorization' | 'maze' | 'chat_correct'

export interface StarEventInsert {
  createdAt: number
  activityType: StarActivityType
  stars: number
  toolCallId: string
  sessionId: string
  skillKey: string
  metadataJson: string
}

export interface StarEventRow {
  id: number
  createdAt: number
  activityType: string
  stars: number
  toolCallId: string
  sessionId: string
  skillKey: string
  metadataJson: string
}

export interface StarTypeBucket {
  count: number
  stars: number
}

export interface TodayStarSummaryByType {
  math_quiz: StarTypeBucket
  english_quiz: StarTypeBucket
  number_puzzle: StarTypeBucket
  handwriting_practice: StarTypeBucket
  categorization: StarTypeBucket
  maze: StarTypeBucket
  chat_correct: StarTypeBucket
}

export interface TodayStarSummary {
  total: number
  byType: TodayStarSummaryByType
}

export interface LastStarGrant {
  stars: number
  activityType: StarActivityType
  createdAt: number
}

export interface RecordStarEventResult {
  stars: number
}

export function createEmptyBucket(): StarTypeBucket {
  return { count: 0, stars: 0 }
}

export function createEmptyTodayStarSummary(): TodayStarSummary {
  const byType: TodayStarSummaryByType = {
    math_quiz: createEmptyBucket(),
    english_quiz: createEmptyBucket(),
    number_puzzle: createEmptyBucket(),
    handwriting_practice: createEmptyBucket(),
    categorization: createEmptyBucket(),
    maze: createEmptyBucket(),
    chat_correct: createEmptyBucket()
  }
  return { total: 0, byType: byType }
}

export interface StarActivityMeta {
  emoji: string
  shortLabel: string
  longLabel: string
  grantedHint: string
  unit: string
}

export interface StarActivityMetaMap {
  math_quiz: StarActivityMeta
  english_quiz: StarActivityMeta
  number_puzzle: StarActivityMeta
  handwriting_practice: StarActivityMeta
  categorization: StarActivityMeta
  maze: StarActivityMeta
  chat_correct: StarActivityMeta
}

const META_MATH: StarActivityMeta = {
  emoji: '🧮',
  shortLabel: '数学',
  longLabel: '数学题',
  grantedHint: '数学题答对',
  unit: '题'
}
const META_ENGLISH: StarActivityMeta = {
  emoji: '📚',
  shortLabel: '英语',
  longLabel: '英语题',
  grantedHint: '英语题答对',
  unit: '题'
}
const META_PUZZLE: StarActivityMeta = {
  emoji: '🎮',
  shortLabel: '华容道',
  longLabel: '数字华容道',
  grantedHint: '数字华容道完成',
  unit: '局'
}
const META_HANDWRITING: StarActivityMeta = {
  emoji: '✏️',
  shortLabel: '写字',
  longLabel: '学写字',
  grantedHint: '学写字完成',
  unit: '字'
}
const META_CATEGORIZATION: StarActivityMeta = {
  emoji: '📦',
  shortLabel: '分类',
  longLabel: '分类小管家',
  grantedHint: '分类小管家完成',
  unit: '局'
}
const META_MAZE: StarActivityMeta = {
  emoji: '🧭',
  shortLabel: '迷宫',
  longLabel: '走迷宫',
  grantedHint: '走出迷宫',
  unit: '局'
}
const META_CHAT_CORRECT: StarActivityMeta = {
  emoji: '💬',
  shortLabel: '聊天',
  longLabel: '聊天答对',
  grantedHint: '聊天答对',
  unit: '次'
}

const metaRecord: StarActivityMetaMap = {
  math_quiz: META_MATH,
  english_quiz: META_ENGLISH,
  number_puzzle: META_PUZZLE,
  handwriting_practice: META_HANDWRITING,
  categorization: META_CATEGORIZATION,
  maze: META_MAZE,
  chat_correct: META_CHAT_CORRECT
}
export const STAR_ACTIVITY_META: StarActivityMetaMap = metaRecord

const activityTypes: StarActivityType[] = ['math_quiz', 'english_quiz', 'number_puzzle', 'handwriting_practice', 'categorization', 'maze', 'chat_correct']
export const STAR_ACTIVITY_TYPES: StarActivityType[] = activityTypes

export function getBucketFromSummary(summary: TodayStarSummary, type: StarActivityType): StarTypeBucket {
  const byType: TodayStarSummaryByType = summary.byType
  if (type === 'math_quiz') {
    return byType.math_quiz
  }
  if (type === 'english_quiz') {
    return byType.english_quiz
  }
  if (type === 'handwriting_practice') {
    return byType.handwriting_practice
  }
  if (type === 'categorization') {
    return byType.categorization
  }
  if (type === 'maze') {
    return byType.maze
  }
  if (type === 'chat_correct') {
    return byType.chat_correct
  }
  return byType.number_puzzle
}

export function getActivityMeta(type: StarActivityType): StarActivityMeta {
  if (type === 'math_quiz') {
    return META_MATH
  }
  if (type === 'english_quiz') {
    return META_ENGLISH
  }
  if (type === 'handwriting_practice') {
    return META_HANDWRITING
  }
  if (type === 'categorization') {
    return META_CATEGORIZATION
  }
  if (type === 'maze') {
    return META_MAZE
  }
  if (type === 'chat_correct') {
    return META_CHAT_CORRECT
  }
  return META_PUZZLE
}

/**
 * 取活动的 SymbolGlyph 资源, 用于 v2 视觉升级的 icon well
 * 集中在此处让 TodayStarDetailSheet 复用
 */
export function getActivitySymbol(type: StarActivityType): Resource {
  if (type === 'math_quiz') {
    return $r('sys.symbol.plus')
  }
  if (type === 'english_quiz') {
    return $r('sys.symbol.doc_plaintext')
  }
  if (type === 'handwriting_practice') {
    return $r('sys.symbol.AI_pencil')
  }
  if (type === 'categorization') {
    return $r('sys.symbol.folder')
  }
  if (type === 'maze') {
    return $r('sys.symbol.wand_and_stars')
  }
  if (type === 'chat_correct') {
    return $r('sys.symbol.message')
  }
  return $r('sys.symbol.lightbulb')
}

/**
 * 顶部"今日小明星"主题的 SymbolGlyph, 集中一处便于统一调整
 */
export function getTodayStarHeaderSymbol(): Resource {
  return $r('sys.symbol.wand_and_stars')
}

// 星星奖励系统专用颜色 token
// STAR_SUCCESS_GREEN: 与 NumberPuzzleCard 私有 SUCCESS_GREEN 同步, 用作"授予星星"的视觉锚点
// STAR_CELEBRATION_GOLD: 与 NumberPuzzleCard 琥珀 tile 起点色一致, 用于首次授星的高光
export const STAR_SUCCESS_GREEN: string = '#22C55E'
export const STAR_CELEBRATION_GOLD: string = '#F59E0B'
