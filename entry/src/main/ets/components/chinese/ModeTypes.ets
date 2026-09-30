// entry/src/main/ets/components/chinese/ModeTypes.ets
/**
 * ModeTypes - chinese_quiz 四 mode 的参数/结果契约与解析 (参照 english/ModeTypes)
 *
 * 一个工具承载四种 mode:
 * - word_build:    组词造句选择 (character + options 4 选 1, answer 必含 character)
 * - sentence_order:连词成句 (words 打乱词卡 → 排序, answer 为正确语序)
 * - lookalike:     形近字辨析 (stem 恰一个 ___ + options 单字 4 选 1)
 * - antonym:       近反义词 (character + options 4 选 1)
 *
 * schema 层硬校验已在 ToolExecutionService.handleChineseQuiz (should_retry) 完成;
 * 本解析只做渲染兜底, 坏参数走 invalidBody 分支。
 */

export type ChineseQuizMode = 'word_build' | 'sentence_order' | 'lookalike' | 'antonym'

export interface ChineseQuizModeArgs {
  mode: ChineseQuizMode
  stem: string
  character: string
  words: string[]
  options: string[]
  answer: string
  difficulty: number
  skillKey: string
}

export interface ChineseQuizAnswerPayload {
  answered: boolean
  mode: ChineseQuizMode
  child_answer: string
  correct: boolean
  correct_answer: string
  skill_key: string
}

function getStr(obj: Record<string, Object>, key: string, dflt: string): string {
  const v: Object | undefined = obj[key]
  if (typeof v === 'string') {
    return v as string
  }
  return dflt
}

function getNum(obj: Record<string, Object>, key: string, dflt: number): number {
  const v: Object | undefined = obj[key]
  if (typeof v === 'number') {
    const n: number = v as number
    if (!Number.isNaN(n)) {
      return n
    }
  }
  return dflt
}

function getStringArray(obj: Record<string, Object>, key: string): string[] {
  const out: string[] = []
  const raw: Object | undefined = obj[key]
  if (Array.isArray(raw)) {
    const arr = raw as Object[]
    for (let i = 0; i < arr.length; i++) {
      const v = arr[i]
      if (typeof v === 'string' && (v as string).trim() !== '') {
        out.push((v as string).trim())
      }
    }
  }
  return out
}

export const CHINESE_QUIZ_MODES: string[] = ['word_build', 'sentence_order', 'lookalike', 'antonym']

/** 解析 chinese_quiz arguments; mode 不合法时 valid=false 交给 router 兜底 */
export function parseChineseQuizModeArgs(raw: string): ChineseQuizModeArgs {
  const args: ChineseQuizModeArgs = {
    mode: 'word_build',
    stem: '',
    character: '',
    words: [],
    options: [],
    answer: '',
    difficulty: 1,
    skillKey: 'chinese_vocab'
  }
  try {
    const obj = JSON.parse(raw) as Record<string, Object>
    const modeRaw = getStr(obj, 'mode', '')
    if (modeRaw === 'sentence_order') {
      args.mode = 'sentence_order'
    } else if (modeRaw === 'lookalike') {
      args.mode = 'lookalike'
    } else if (modeRaw === 'antonym') {
      args.mode = 'antonym'
    } else if (modeRaw === 'word_build') {
      args.mode = 'word_build'
    } else {
      // 未知 mode 原样返回 (router 无匹配时渲染 fallback 文案)
      args.mode = 'word_build'
      args.stem = ''
      args.character = ''
      args.words = []
      args.options = []
      args.answer = ''
      return args
    }
    args.stem = getStr(obj, 'stem', '')
    args.character = getStr(obj, 'character', '')
    args.words = getStringArray(obj, 'words')
    args.options = getStringArray(obj, 'options')
    args.answer = getStr(obj, 'answer', '')
    args.difficulty = getNum(obj, 'difficulty', 1)
    const skillRaw = getStr(obj, 'skill_key', '')
    args.skillKey = skillRaw !== '' ? skillRaw : (args.mode === 'sentence_order' ? 'chinese_reading' : 'chinese_vocab')
  } catch (_e) {
    return args
  }
  return args
}

export function chineseModeDisplayName(mode: ChineseQuizMode): string {
  if (mode === 'sentence_order') {
    return '连词成句'
  }
  if (mode === 'lookalike') {
    return '形近字辨析'
  }
  if (mode === 'antonym') {
    return '近反义词'
  }
  return '组词造句'
}

/** 连词成句归一化: 去空白与常见中英文标点, 用于答案比对 */
export function normalizeSentence(value: string): string {
  return value.replace(/[\s，。！？、,.!?;；:：「」『』()（）]/g, '')
}
