import { describe, it, expect } from '@ohos/hypium'
import {
  normalizeItemKey,
  normalizePinyinSyllable,
  isCJKText,
  extractLedgerItemsFromTool,
  extractLedgerAnswerItems,
  extractLedgerSeeds
} from '../../../../main/ets/utils/LedgerExtractUtils'
import { LessonPlan, LessonPlanVocabItem, LessonPlanWritingItem } from '../../../../main/ets/models/LessonPlanModels'

export default function ledgerExtractUtilsTest(): void {
  describe('ledgerExtractUtilsTest', () => {
    it('normalizeItemKey_en_vocab', 0, () => {
      expect(normalizeItemKey('en', 'vocab', '  Apple! ')).assertEqual('en:vocab:apple')
      expect(normalizeItemKey('en', 'vocab', "I'm OK")).assertEqual("en:vocab:i'm ok")
    })

    it('normalizeItemKey_en_sentence', 0, () => {
      expect(normalizeItemKey('en', 'sentence', 'I like apples.')).assertEqual('en:sentence:i|like|apples')
    })

    it('normalizeItemKey_zh_char_phrase', 0, () => {
      expect(normalizeItemKey('zh', 'char', '山')).assertEqual('zh:char:山')
      expect(normalizeItemKey('zh', 'phrase', '火车')).assertEqual('zh:phrase:火车')
    })

    it('normalizeItemKey_zh_pinyin_tone_digits', 0, () => {
      expect(normalizeItemKey('zh', 'pinyin', 'shān')).assertEqual('zh:pinyin:shan1')
      expect(normalizePinyinSyllable('Lǜ')).assertEqual('lv4')
      expect(normalizePinyinSyllable('nǚ')).assertEqual('nv3')
      expect(normalizePinyinSyllable('bá')).assertEqual('ba2')
    })

    it('normalizeItemKey_zh_sentence_strips_punct', 0, () => {
      expect(normalizeItemKey('zh', 'sentence', '我爱妈妈。')).assertEqual('zh:sentence:我爱妈妈')
    })

    it('isCJKText_classifies', 0, () => {
      expect(isCJKText('山')).assertTrue()
      expect(isCJKText('火车')).assertTrue()
      expect(isCJKText('apple')).assertFalse()
      expect(isCJKText('')).assertFalse()
    })

    it('extract_english_quiz_correct_answer', 0, () => {
      const args = '{"mode":"listen_choice","correct_answer":"apple","tts_text":"apple"}'
      const items = extractLedgerItemsFromTool('english_quiz', args)
      expect(items.length).assertEqual(1)
      expect(items[0].subject).assertEqual('en')
      expect(items[0].display).assertEqual('apple')
      expect(items[0].mode).assertEqual('english_quiz.listen_choice')
      expect(items[0].skillKey).assertEqual('english_vocab')
    })

    it('extract_english_quiz_read_aloud_is_sentence', 0, () => {
      const args = '{"mode":"read_aloud","correct_answer":"I like apples","target_text":"I like apples"}'
      const items = extractLedgerItemsFromTool('english_quiz', args)
      expect(items.length).assertEqual(1)
      expect(items[0].itemType).assertEqual('sentence')
      expect(items[0].skillKey).assertEqual('english_sentence')
    })

    it('extract_english_quiz_legacy_question_type', 0, () => {
      const args = '{"question_type":"word_choice","correct_answer":"cat"}'
      const items = extractLedgerItemsFromTool('english_quiz', args)
      expect(items.length).assertEqual(1)
      expect(items[0].mode).assertEqual('english_quiz.word_choice')
    })

    it('extract_picture_vocab_en_and_zh', 0, () => {
      const en = extractLedgerItemsFromTool('picture_vocab', '{"mode":"en","correct_answer":"dog"}')
      expect(en.length).assertEqual(1)
      expect(en[0].subject).assertEqual('en')
      const zh = extractLedgerItemsFromTool('picture_vocab', '{"mode":"zh","correct_answer":"火车"}')
      expect(zh.length).assertEqual(1)
      expect(zh[0].itemType).assertEqual('phrase')
      const zhChar = extractLedgerItemsFromTool('picture_vocab', '{"mode":"zh","correct_answer":"山"}')
      expect(zhChar[0].itemType).assertEqual('char')
    })

    it('extract_listening_quiz_word', 0, () => {
      const items = extractLedgerItemsFromTool('listening_quiz', '{"word":"bag","correct_answer":"bag"}')
      expect(items.length).assertEqual(1)
      expect(items[0].display).assertEqual('bag')
      expect(items[0].skillKey).assertEqual('english_vocab')
    })

    it('extract_pinyin_quiz_uses_correct_answer_as_display', 0, () => {
      const items = extractLedgerItemsFromTool('pinyin_quiz', '{"character":"山","correct_answer":"shān"}')
      expect(items.length).assertEqual(1)
      expect(items[0].itemType).assertEqual('pinyin')
      expect(items[0].display).assertEqual('shān')
      expect(items[0].skillKey).assertEqual('pinyin')
    })

    it('extract_explain_cards_record_served', 0, () => {
      const hanzi = extractLedgerItemsFromTool('hanzi_card', '{"character":"山"}')
      expect(hanzi.length).assertEqual(1)
      expect(hanzi[0].itemType).assertEqual('char')
      expect(hanzi[0].mode).assertEqual('hanzi_card')
      const pinyin = extractLedgerItemsFromTool('pinyin_card', '{"syllable":"bà"}')
      expect(pinyin.length).assertEqual(1)
      expect(pinyin[0].itemType).assertEqual('pinyin')
      const talk = extractLedgerItemsFromTool('picture_talk', '{"scene":"公园里孩子们在放风筝"}')
      expect(talk.length).assertEqual(1)
      expect(talk[0].itemType).assertEqual('sentence')
      expect(talk[0].skillKey).assertEqual('chinese_reading')
    })

    it('extract_chinese_quiz_per_mode', 0, () => {
      const wb = extractLedgerItemsFromTool('chinese_quiz',
        '{"mode":"word_build","character":"山","answer":"火山"}')
      expect(wb.length).assertEqual(2) // zh:char + zh:phrase
      const so = extractLedgerItemsFromTool('chinese_quiz',
        '{"mode":"sentence_order","words":["我","爱","妈妈"],"answer":"我爱妈妈"}')
      expect(so.length).assertEqual(1)
      expect(so[0].itemType).assertEqual('sentence')
      const la = extractLedgerItemsFromTool('chinese_quiz',
        '{"mode":"lookalike","stem":"___ has apples","answer":"山","options":["山","出"]}')
      expect(la[0].itemType).assertEqual('char')
      const ant = extractLedgerItemsFromTool('chinese_quiz',
        '{"mode":"antonym","character":"大","answer":"小"}')
      expect(ant.length).assertEqual(1)
      expect(ant[0].display).assertEqual('大')
    })

    it('extract_matching_pairs_left_items', 0, () => {
      const items = extractLedgerItemsFromTool('matching_pairs',
        '{"difficulty":1,"pairs":[{"left":"apple","right":"苹果"},{"left":"山","right":"mountain"}]}')
      expect(items.length).assertEqual(2)
      expect(items[0].subject).assertEqual('en')
      expect(items[1].itemType).assertEqual('char')
    })

    it('extract_handwriting_skips_numbers', 0, () => {
      const num = extractLedgerItemsFromTool('handwriting_practice', '{"character":"3","type":"number"}')
      expect(num.length).assertEqual(0)
      const zh = extractLedgerItemsFromTool('handwriting_practice', '{"character":"山","type":"chinese"}')
      expect(zh.length).assertEqual(1)
      expect(zh[0].itemType).assertEqual('char')
      const letter = extractLedgerItemsFromTool('handwriting_practice', '{"character":"A","type":"letter"}')
      expect(letter[0].subject).assertEqual('en')
    })

    it('extract_non_ledger_tools_return_empty', 0, () => {
      expect(extractLedgerItemsFromTool('math_quiz', '{"correct_answer":"8"}').length).assertEqual(0)
      expect(extractLedgerItemsFromTool('number_puzzle', '{"difficulty":3}').length).assertEqual(0)
      expect(extractLedgerItemsFromTool('english_quiz', 'not-json').length).assertEqual(0)
      expect(extractLedgerItemsFromTool('english_quiz', '{"mode":"listen_choice"}').length).assertEqual(0) // 无 correct_answer
    })

    it('answerItems_quiz_semantics', 0, () => {
      const args = '{"mode":"listen_choice","correct_answer":"apple"}'
      const right = extractLedgerAnswerItems('english_quiz', args, '{"correct":true}')
      expect(right.length).assertEqual(1)
      expect(right[0].itemKey).assertEqual('en:vocab:apple')
      expect(right[0].isCorrect).assertTrue()
      const wrong = extractLedgerAnswerItems('english_quiz', args, '{"correct":false}')
      expect(wrong[0].isCorrect).assertFalse()
    })

    it('answerItems_explain_cards_never_advance_mastery', 0, () => {
      // 讲解型: 无论 completed 与否, 不产生对账项 (Review Focus #3)
      expect(extractLedgerAnswerItems('hanzi_card', '{"character":"山"}', '{"completed":true}').length).assertEqual(0)
      expect(extractLedgerAnswerItems('pinyin_card', '{"syllable":"bà"}', '{"completed":true}').length).assertEqual(0)
      expect(extractLedgerAnswerItems('picture_talk', '{"scene":"公园"}', '{"completed":true}').length).assertEqual(0)
    })

    it('answerItems_completed_gated_tools', 0, () => {
      // 放弃 (completed=false) → 跳过, 不推进掌握度
      expect(extractLedgerAnswerItems('handwriting_practice', '{"character":"山","type":"chinese"}',
        '{"completed":false}').length).assertEqual(0)
      // 完成且全对 → 全部 left 项 isCorrect=true
      const done = extractLedgerAnswerItems('matching_pairs',
        '{"pairs":[{"left":"apple","right":"苹果"}]}', '{"completed":true,"mistakes":0}')
      expect(done.length).assertEqual(1)
      expect(done[0].isCorrect).assertTrue()
    })

    it('answerItems_malformed_answer_returns_empty', 0, () => {
      expect(extractLedgerAnswerItems('english_quiz', '{"correct_answer":"apple"}', 'not-json').length).assertEqual(0)
    })

    it('extractLedgerSeeds_vocab_and_writing', 0, () => {
      const plan: LessonPlan = new LessonPlan()
      // LessonPlan.vocab / writing 为普通类数组属性 (已核对 models/LessonPlanModels.ets), 直接 push
      expect(extractLedgerSeeds(plan).length).assertEqual(0) // 空 plan → 空 seeds
      const vocabItem: LessonPlanVocabItem = new LessonPlanVocabItem()
      vocabItem.word = 'Apple'
      plan.vocab.push(vocabItem)
      const writingItem: LessonPlanWritingItem = new LessonPlanWritingItem()
      writingItem.characterOrWord = '山'
      plan.writing.push(writingItem)
      const seeds = extractLedgerSeeds(plan)
      expect(seeds.length).assertEqual(2)
      expect(seeds[0].display).assertEqual('Apple')
      expect(normalizeItemKey(seeds[0].subject, seeds[0].itemType, seeds[0].display)).assertEqual('en:vocab:apple')
      expect(normalizeItemKey(seeds[1].subject, seeds[1].itemType, seeds[1].display)).assertEqual('zh:char:山')
    })
  })
}
