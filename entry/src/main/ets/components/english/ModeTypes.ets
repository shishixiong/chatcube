/**
 * ModeTypes - english_quiz v2 六 mode 的类型、参数解析与展示映射
 *
 * 路由器 (EnglishQuizCard) 用 parseEnglishQuizModeArgs 决定渲染哪个 body;
 * 各 body 再用同一份解析结果取自己的字段, 保证解析只有一处。
 * 纯逻辑 (无 ArkUI 依赖), resolveQuizMode 复用 utils/EnglishQuizValidation。
 * 设计见 docs/superpowers/specs/2026-09-24-english-quiz-v2-design.md §6。
 */

import { resolveQuizMode } from '../../utils/EnglishQuizValidation'

export type EnglishQuizMode =
  | 'listen_choice' | 'picture_word' | 'phonics_blend'
  | 'sentence_fill' | 'read_aloud' | 'letter_trace' | 'legacy'

/** answer payload v2: 现有字段全保留 (ToolExecutionService/AI 契约不动), 新增字段全部可选 */
export interface EnglishQuizAnswerPayload {
  answered: boolean
  child_answer: string
  correct: boolean
  correct_answer: string
  word: string
  sentence: string
  question_type: string        // 新 mode 回包统一回填 mode 本身 (消费方仅 legacy 分支判 'phonics_choice')
  skill_key: string
  letter_options?: string[]
  sound_text?: string
  mode?: string
  stage?: string
  pattern?: string
  target_text?: string
  completed?: boolean          // letter_trace 置 true
}

export interface EnglishQuizModeArgs {
  mode: EnglishQuizMode
  question: string
  correctAnswer: string
  options: string[]
  imagePath: string            // handleEnglishQuiz 注入的 image_path (可能为 '')
  imagePrompt: string
  phonicsRule: string
  pattern: string
  ttsText: string
  targetText: string
  phoneticHint: string
  letter: string
  letterCase: string
  skillKey: string
  difficulty: number
  stage: string
  theme: string
  legacyQuestionType: string   // legacy 三题型原值 ('word'/'sentence'/'phonics_choice')
  legacyLetterOptions: string[]
  legacySoundText: string
}

/** AI 未传 skill_key 时的默认映射 (spec §8.2) */
export function defaultSkillKeyForMode(mode: EnglishQuizMode): string {
  switch (mode) {
    case 'listen_choice': return 'english_alphabet'
    case 'picture_word': return 'english_vocab'
    case 'phonics_blend': return 'english_phonics'
    case 'sentence_fill': return 'english_sentence'
    case 'read_aloud': return 'english_reading'
    case 'letter_trace': return 'english_writing'
    default: return 'english_vocab'   // legacy 默认, 与原 parseQuiz 一致
  }
}

export function modeDisplayName(mode: EnglishQuizMode): string {
  switch (mode) {
    case 'listen_choice': return '听音选词'
    case 'picture_word': return '看图选词'
    case 'phonics_blend': return '自然拼读'
    case 'sentence_fill': return '句型填空'
    case 'read_aloud': return '跟我读'
    case 'letter_trace': return '字母描红'
    default: return '英语小游戏'
  }
}

/**
 * 解析 toolCall.arguments → ModeArgs。
 * 解析失败 / mode 与 question_type 都缺 → mode='legacy' (路由器回落 LegacyBody, 最安全)。
 */
export function parseEnglishQuizModeArgs(argsJson: string): EnglishQuizModeArgs {
  const empty: EnglishQuizModeArgs = {
    mode: 'legacy', question: '', correctAnswer: '', options: [],
    imagePath: '', imagePrompt: '', phonicsRule: '', pattern: '',
    ttsText: '', targetText: '', phoneticHint: '', letter: '', letterCase: '',
    skillKey: 'english_vocab', difficulty: 1, stage: '', theme: '',
    legacyQuestionType: 'word', legacyLetterOptions: [], legacySoundText: ''
  }
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(argsJson) as Record<string, Object>
  } catch (_e) {
    return empty
  }
  const resolved = resolveQuizMode(parsed)
  const result: EnglishQuizModeArgs = {
    mode: 'legacy',
    question: ((parsed['question'] as string) ?? '').trim(),
    correctAnswer: ((parsed['correct_answer'] as string) ?? '').trim(),
    options: [],
    imagePath: ((parsed['image_path'] as string) ?? '').trim(),
    imagePrompt: ((parsed['image_prompt'] as string) ?? '').trim(),
    phonicsRule: ((parsed['phonics_rule'] as string) ?? '').trim(),
    pattern: ((parsed['pattern'] as string) ?? '').trim(),
    ttsText: ((parsed['tts_text'] as string) ?? '').trim(),
    targetText: ((parsed['target_text'] as string) ?? '').trim(),
    phoneticHint: ((parsed['phonetic_hint'] as string) ?? '').trim(),
    letter: ((parsed['letter'] as string) ?? '').trim(),
    letterCase: ((parsed['case'] as string) ?? '').trim(),
    skillKey: ((parsed['skill_key'] as string) ?? '').trim(),
    difficulty: (parsed['difficulty'] as number) ?? 1,
    stage: ((parsed['stage'] as string) ?? '').trim(),
    theme: ((parsed['theme'] as string) ?? '').trim(),
    legacyQuestionType: resolved.isLegacy ? resolved.mode : '',
    legacyLetterOptions: [],
    legacySoundText: ((parsed['sound_text'] as string) ?? '').trim()
  }
  if (resolved.isLegacy) {
    result.mode = 'legacy'
    result.skillKey = result.skillKey !== '' ? result.skillKey : 'english_vocab'
    const rawLetters = parsed['letter_options']
    if (Array.isArray(rawLetters)) {
      const arr = rawLetters as Object[]
      for (let i = 0; i < arr.length; i++) {
        if (typeof arr[i] === 'string') {
          result.legacyLetterOptions.push(arr[i] as string)
        }
      }
    }
    return result
  }
  // 新 mode
  const modeValue = resolved.mode as EnglishQuizMode
  result.mode = modeValue
  result.skillKey = result.skillKey !== '' ? result.skillKey : defaultSkillKeyForMode(modeValue)
  const rawOptions = parsed['options']
  if (Array.isArray(rawOptions)) {
    const arr = rawOptions as Object[]
    for (let i = 0; i < arr.length; i++) {
      if (typeof arr[i] === 'string') {
        result.options.push((arr[i] as string).trim())
      }
    }
  }
  return result
}
