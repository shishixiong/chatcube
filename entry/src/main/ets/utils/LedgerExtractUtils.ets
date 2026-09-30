/**
 * LedgerExtractUtils - 台账写入侧的目标项提取与归一化 (纯函数)
 *
 * 设计: docs/superpowers/specs/2026-09-30-vocab-repetition-control-design.md §3/§6.2 (v1.1 已核对校验器字段名)
 * - normalizeItemKey 是全项目唯一的 key 归一化实现, 写入侧与门禁侧共用
 * - extractLedgerItemsFromTool: 从工具 arguments 提取目标学习项 (v1.1 校正的字段名见各分支注释)
 * - extractLedgerAnswerItems: 作答对账——quiz 型看顶层 correct; completed 型 (handwriting/matching_pairs)
 *   completed=false 跳过; 讲解型 (hanzi_card/pinyin_card/picture_talk) 恒返回 []
 * - mode 命名: compositeMode = toolId (无内部 mode) 或 `${toolId}.${modeValue}`,
 *   保证跨工具不同题型不互相误伤冷却
 */
import { LedgerAnswerItem, LedgerItemSeed, LedgerToolItem } from '../models/LearningLedgerModels'
import { LessonPlan } from '../models/LessonPlanModels'

/** 声调映射: 带调字母 → 基字母+调号 (spec §3.1, ü→v) */
const TONE_MAP: Record<string, string> = {
  'ā': 'a1', 'á': 'a2', 'ǎ': 'a3', 'à': 'a4',
  'ē': 'e1', 'é': 'e2', 'ě': 'e3', 'è': 'e4',
  'ī': 'i1', 'í': 'i2', 'ǐ': 'i3', 'ì': 'i4',
  'ō': 'o1', 'ó': 'o2', 'ǒ': 'o3', 'ò': 'o4',
  'ū': 'u1', 'ú': 'u2', 'ǔ': 'u3', 'ù': 'u4',
  'ǖ': 'v1', 'ǘ': 'v2', 'ǚ': 'v3', 'ǜ': 'v4',
  'ü': 'v'
}

export function normalizePinyinSyllable(syllable: string): string {
  const lowered = syllable.trim().toLowerCase()
  let out = ''
  let toneDigit = ''
  for (let i = 0; i < lowered.length; i++) {
    const ch = lowered.charAt(i)
    const mapped = TONE_MAP[ch]
    if (mapped !== undefined) {
      // 带调字母: 取基字母原位保留, 调号拆出统一追加到音节末尾 (spec §3.1: shān→shan1)
      out += mapped.charAt(0)
      if (mapped.length > 1) {
        toneDigit = mapped.charAt(1)
      }
    } else {
      out += ch
    }
  }
  out = out.replace(/\s+/g, '')
  return toneDigit === '' ? out : out + toneDigit
}

function stripEnPunctuation(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9\s']/g, ' ').replace(/\s+/g, ' ').trim()
}

/** 全部字符都是 CJK 基本区汉字 (至少 1 个字符) */
export function isCJKText(value: string): boolean {
  const trimmed = value.trim()
  if (trimmed.length === 0) {
    return false
  }
  let allCjk = true
  for (let i = 0; i < trimmed.length; i++) {
    const code = trimmed.charCodeAt(i)
    if (!(code >= 0x4E00 && code <= 0x9FFF)) {
      allCjk = false
    }
  }
  return allCjk
}

/**
 * 唯一的 item_key 归一化实现 (spec §3.1)。
 * en:vocab 小写去标点; en:sentence 分词竖线连接; zh:char/phrase 原样;
 * zh:pinyin 声调数字化; zh:sentence 去标点空白。
 */
export function normalizeItemKey(subject: string, itemType: string, display: string): string {
  const raw = display.trim()
  if (subject === 'en') {
    if (itemType === 'sentence') {
      const words = raw.toLowerCase().split(/[^a-z0-9']+/)
      const kept: string[] = []
      for (let i = 0; i < words.length; i++) {
        if (words[i] !== '') {
          kept.push(words[i])
        }
      }
      return `en:sentence:${kept.join('|')}`
    }
    return `en:vocab:${stripEnPunctuation(raw)}`
  }
  if (itemType === 'pinyin') {
    return `zh:pinyin:${normalizePinyinSyllable(raw)}`
  }
  if (itemType === 'sentence') {
    return `zh:sentence:${raw.replace(/[\s，。！？、,.!?;；:：「」『』()（）]/g, '')}`
  }
  if (itemType === 'phrase') {
    return `zh:phrase:${raw}`
  }
  return `zh:char:${raw}`
}

function toolItem(subject: string, itemType: string, display: string, mode: string,
  skillKey: string): LedgerToolItem {
  const item: LedgerToolItem = {
    subject: subject,
    itemType: itemType,
    display: display,
    mode: mode,
    skillKey: skillKey
  }
  return item
}

function emptyItems(): LedgerToolItem[] {
  const items: LedgerToolItem[] = []
  return items
}

function compositeMode(toolId: string, mode: string): string {
  return mode === '' ? toolId : `${toolId}.${mode}`
}

function argString(parsed: Record<string, Object>, key: string): string {
  const v = parsed[key]
  return typeof v === 'string' ? (v as string).trim() : ''
}

/** 分类混排项 (matching_pairs 左列 / handwriting character): CJK 单字→zh:char, CJK 多字→zh:phrase, 其余→en:vocab */
function classifyMixedItem(text: string, mode: string): LedgerToolItem {
  if (isCJKText(text)) {
    if (text.length === 1) {
      return toolItem('zh', 'char', text, mode, 'chinese_vocab')
    }
    return toolItem('zh', 'phrase', text, mode, 'chinese_vocab')
  }
  return toolItem('en', 'vocab', text, mode, 'english_vocab')
}

function singleOf(item: LedgerToolItem): LedgerToolItem[] {
  const items: LedgerToolItem[] = [item]
  return items
}

/**
 * 从工具 arguments 提取目标学习项。字段名严格对照 v1.1 校正:
 * - english_quiz: correct_answer (六 mode 统一; read_aloud 空时回退 target_text);
 *   mode 空/legacy 时回退 question_type; read_aloud → en:sentence
 * - picture_vocab: correct_answer; mode=en→en:vocab, mode=zh→zh:char|zh:phrase
 * - listening_quiz: word (被朗读项; 单个拉丁字母 skill=english_alphabet)
 * - pinyin_quiz: correct_answer (带调拼音) 为 display, item=zh:pinyin (被考字本身不单独建行)
 * - hanzi_card: character → zh:char (讲解计曝光); pinyin_card: syllable;
 *   picture_talk: scene → zh:sentence
 * - chinese_quiz: word_build→[character zh:char + answer zh:phrase]; sentence_order→answer zh:sentence;
 *   lookalike→answer zh:char; antonym→character zh:char
 * - matching_pairs: pairs[].left 逐项分类; handwriting_practice: character+type (number 跳过)
 */
export function extractLedgerItemsFromTool(toolId: string, argsJson: string): LedgerToolItem[] {
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(argsJson) as Record<string, Object>
  } catch (_e) {
    return emptyItems()
  }
  if (toolId === 'english_quiz') {
    const mode = argString(parsed, 'mode')
    const legacyType = argString(parsed, 'question_type')
    const effectiveMode = mode !== '' ? mode : legacyType
    let target = argString(parsed, 'correct_answer')
    if (target === '' && effectiveMode === 'read_aloud') {
      target = argString(parsed, 'target_text')
    }
    if (target === '') {
      return emptyItems()
    }
    const isSentence = effectiveMode === 'read_aloud'
    return singleOf(toolItem('en', isSentence ? 'sentence' : 'vocab', target,
      compositeMode(toolId, effectiveMode), isSentence ? 'english_sentence' : 'english_vocab'))
  }
  if (toolId === 'picture_vocab') {
    const target = argString(parsed, 'correct_answer')
    if (target === '') {
      return emptyItems()
    }
    const mode = argString(parsed, 'mode')
    if (mode === 'zh') {
      return singleOf(toolItem('zh', target.length === 1 ? 'char' : 'phrase', target,
        compositeMode(toolId, mode), 'chinese_vocab'))
    }
    return singleOf(toolItem('en', 'vocab', target, compositeMode(toolId, mode), 'english_vocab'))
  }
  if (toolId === 'listening_quiz') {
    const word = argString(parsed, 'word')
    if (word === '') {
      return emptyItems()
    }
    const isSingleLetter = /^[a-z]$/i.test(word)
    return singleOf(toolItem('en', 'vocab', word, compositeMode(toolId, ''),
      isSingleLetter ? 'english_alphabet' : 'english_vocab'))
  }
  if (toolId === 'pinyin_quiz') {
    const answer = argString(parsed, 'correct_answer')
    if (answer === '') {
      return emptyItems()
    }
    return singleOf(toolItem('zh', 'pinyin', answer, compositeMode(toolId, ''), 'pinyin'))
  }
  if (toolId === 'hanzi_card') {
    const character = argString(parsed, 'character')
    if (character === '') {
      return emptyItems()
    }
    return singleOf(toolItem('zh', 'char', character, compositeMode(toolId, ''), 'chinese_vocab'))
  }
  if (toolId === 'pinyin_card') {
    const syllable = argString(parsed, 'syllable')
    if (syllable === '') {
      return emptyItems()
    }
    return singleOf(toolItem('zh', 'pinyin', syllable, compositeMode(toolId, ''), 'pinyin'))
  }
  if (toolId === 'picture_talk') {
    const scene = argString(parsed, 'scene')
    if (scene === '') {
      return emptyItems()
    }
    return singleOf(toolItem('zh', 'sentence', scene, compositeMode(toolId, ''), 'chinese_reading'))
  }
  if (toolId === 'chinese_quiz') {
    const mode = argString(parsed, 'mode')
    const modeTag = compositeMode(toolId, mode)
    const items: LedgerToolItem[] = []
    if (mode === 'word_build') {
      const character = argString(parsed, 'character')
      const answer = argString(parsed, 'answer')
      if (character !== '') {
        items.push(toolItem('zh', 'char', character, modeTag, 'chinese_vocab'))
      }
      if (answer !== '') {
        items.push(toolItem('zh', 'phrase', answer, modeTag, 'chinese_vocab'))
      }
    } else if (mode === 'sentence_order') {
      const answer = argString(parsed, 'answer')
      if (answer !== '') {
        items.push(toolItem('zh', 'sentence', answer, modeTag, 'chinese_reading'))
      }
    } else if (mode === 'lookalike') {
      const answer = argString(parsed, 'answer')
      if (answer !== '') {
        items.push(toolItem('zh', 'char', answer, modeTag, 'chinese_vocab'))
      }
    } else {
      const character = argString(parsed, 'character')
      if (character !== '') {
        items.push(toolItem('zh', 'char', character, modeTag, 'chinese_vocab'))
      }
    }
    return items
  }
  if (toolId === 'matching_pairs') {
    const pairsRaw = parsed['pairs']
    if (!Array.isArray(pairsRaw)) {
      return emptyItems()
    }
    const arr = pairsRaw as Object[]
    const items: LedgerToolItem[] = []
    for (let i = 0; i < arr.length; i++) {
      const pair = arr[i] as Record<string, Object>
      const left = argString(pair, 'left')
      if (left !== '') {
        items.push(classifyMixedItem(left, compositeMode(toolId, '')))
      }
    }
    return items
  }
  if (toolId === 'handwriting_practice') {
    const character = argString(parsed, 'character')
    if (character === '' || argString(parsed, 'type') === 'number') {
      return emptyItems()
    }
    return singleOf(classifyMixedItem(character, compositeMode(toolId, '')))
  }
  return emptyItems()
}

/**
 * 作答对账。语义:
 * - english_quiz/picture_vocab/listening_quiz/pinyin_quiz/chinese_quiz: 全部 served 项 isCorrect = (payload.correct === true)
 * - handwriting_practice / matching_pairs: completed !== true → [] (放弃/中途关闭不推进掌握度);
 *   completed === true → 全部项 isCorrect=true
 * - hanzi_card/pinyin_card/picture_talk: 恒 [] (讲解型, 曝光已在 recordServed 记, 掌握度不因讲解推进)
 * - answerJson 非法 JSON → []
 */
export function extractLedgerAnswerItems(toolId: string, argsJson: string,
  answerJson: string): LedgerAnswerItem[] {
  const served = extractLedgerItemsFromTool(toolId, argsJson)
  const answers: LedgerAnswerItem[] = []
  if (served.length === 0) {
    return answers
  }
  let parsed: Record<string, Object>
  try {
    parsed = JSON.parse(answerJson) as Record<string, Object>
  } catch (_e) {
    return answers
  }
  if (toolId === 'hanzi_card' || toolId === 'pinyin_card' || toolId === 'picture_talk') {
    return answers
  }
  let isCorrect = false
  if (toolId === 'handwriting_practice' || toolId === 'matching_pairs') {
    if (parsed['completed'] !== true) {
      return answers
    }
    isCorrect = true
  } else {
    isCorrect = parsed['correct'] === true
  }
  for (let i = 0; i < served.length; i++) {
    const servedItem = served[i]
    const answer: LedgerAnswerItem = {
      itemKey: normalizeItemKey(servedItem.subject, servedItem.itemType, servedItem.display),
      isCorrect: isCorrect
    }
    answers.push(answer)
  }
  return answers
}

/**
 * 备课计划 → 台账种子 (spec §6.1): plan.vocab[].word → en:vocab;
 * plan.writing[].characterOrWord 按 CJK 判定 zh:char|zh:phrase|en:vocab。按 key 去重。只建行不改掌握度。
 */
export function extractLedgerSeeds(plan: LessonPlan): LedgerItemSeed[] {
  const seeds: LedgerItemSeed[] = []
  const seen: string[] = []
  const vocabItems = plan.vocab
  for (let i = 0; i < vocabItems.length; i++) {
    const word = vocabItems[i].word.trim()
    if (word !== '') {
      pushSeed(seeds, seen, 'en', 'vocab', word, 'english_vocab')
    }
  }
  const writingItems = plan.writing
  for (let i = 0; i < writingItems.length; i++) {
    const text = writingItems[i].characterOrWord.trim()
    if (text === '') {
      continue
    }
    if (isCJKText(text)) {
      if (text.length === 1) {
        pushSeed(seeds, seen, 'zh', 'char', text, 'chinese_vocab')
      } else {
        pushSeed(seeds, seen, 'zh', 'phrase', text, 'chinese_vocab')
      }
    } else {
      pushSeed(seeds, seen, 'en', 'vocab', text, 'english_vocab')
    }
  }
  return seeds
}

function pushSeed(seeds: LedgerItemSeed[], seen: string[], subject: string, itemType: string,
  display: string, skillKey: string): void {
  const key = normalizeItemKey(subject, itemType, display)
  if (key === '' || seen.indexOf(key) >= 0) {
    return
  }
  seen.push(key)
  const seed: LedgerItemSeed = {
    subject: subject,
    itemType: itemType,
    display: display,
    skillKey: skillKey
  }
  seeds.push(seed)
}
