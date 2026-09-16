import {
  KIDS_MATH,
  KIDS_MATH_INK,
  KIDS_ENGLISH,
  KIDS_ENGLISH_INK,
  KIDS_CHINESE,
  KIDS_CHINESE_INK,
  KIDS_GAMES,
  KIDS_GAMES_INK
} from './KidsBrandTokens'

/**
 * 儿童主屏「今天玩什么」2×2 学科目录（纯数据，无 ArkUI 依赖）。
 * 取代 v1 的 12 emoji 宫格活动目录组件（已删除）。
 *
 * 每学科绑定一个专用内置助手（spec §3）；activityTypes 决定「今日 N 题」
 * 的星星事件归属（按 activityType 而非会话助手，chat_correct 不计入任何学科）。
 */
export interface KidsSubjectItem {
  /** 稳定标识 'math' | 'english' | 'chinese' | 'games'（ForEach key） */
  id: string
  /** 对应内置学科助手 id */
  assistantId: string
  /** 卡片标题 */
  label: string
  /** 老师名（记录行次行 / 家长概览用） */
  teacher: string
  /** 卡片副标题（原型锁定文案） */
  subtitle: string
  /** rawfile SVG 图标路径（ink 色 baked-in） */
  iconPath: string
  /** 学科原色（仅 15% 淡底用） */
  color: string
  /** 学科墨色（文字/图标用） */
  ink: string
  /** 今日计数量词：题 / 局 */
  countUnit: string
  /** 点击卡片后自动发送的引导语 */
  startPrompt: string
  /** 「今日 N 题」计数归属的 StarActivityType 集合 */
  activityTypes: string[]
}

export const KIDS_SUBJECTS: KidsSubjectItem[] = [
  {
    id: 'math',
    assistantId: 'kids_math',
    label: '学数学',
    teacher: '小星数学老师',
    subtitle: '口算 · 竖式 · 图形',
    iconPath: 'kids/math.svg',
    color: KIDS_MATH,
    ink: KIDS_MATH_INK,
    countUnit: '题',
    startPrompt: '我想练数学题，请给我出题吧',
    activityTypes: ['math_quiz']
  },
  {
    id: 'english',
    assistantId: 'kids_english',
    label: '学英语',
    teacher: '小星英语老师',
    subtitle: '听音 · 单词 · 认读',
    iconPath: 'kids/english.svg',
    color: KIDS_ENGLISH,
    ink: KIDS_ENGLISH_INK,
    countUnit: '题',
    startPrompt: '我想练英语，请给我出题吧',
    activityTypes: ['english_quiz', 'picture_vocab', 'listening_quiz']
  },
  {
    id: 'chinese',
    assistantId: 'kids_chinese',
    label: '学语文',
    teacher: '小星语文老师',
    subtitle: '拼音 · 识字 · 写字',
    iconPath: 'kids/chinese.svg',
    color: KIDS_CHINESE,
    ink: KIDS_CHINESE_INK,
    countUnit: '题',
    startPrompt: '我想学语文，请带我练拼音和写字吧',
    activityTypes: ['pinyin_quiz', 'handwriting_practice']
  },
  {
    id: 'games',
    assistantId: 'kids_games',
    label: '小游戏',
    teacher: '小星游戏老师',
    subtitle: '华容道 · 迷宫 · 数独',
    iconPath: 'kids/games.svg',
    color: KIDS_GAMES,
    ink: KIDS_GAMES_INK,
    countUnit: '局',
    startPrompt: '我想玩益智小游戏，请开始一局吧',
    activityTypes: ['number_puzzle', 'maze', 'sudoku', 'matching_pairs', 'categorization']
  }
]

/** 会话 assistantId → 学科元数据；default / 未知返回 null（调用方回退小星老师样式） */
export function subjectForAssistantId(assistantId: string): KidsSubjectItem | null {
  for (let i = 0; i < KIDS_SUBJECTS.length; i++) {
    if (KIDS_SUBJECTS[i].assistantId === assistantId) {
      return KIDS_SUBJECTS[i]
    }
  }
  return null
}
