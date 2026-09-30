import { describe, it, expect } from '@ohos/hypium'
import { renderVocabLedgerSection } from '../../../../main/ets/utils/LessonPlanPromptUtils'
import { LedgerSummary, DueReviewHint, createEmptyLedgerSummary } from '../../../../main/ets/models/LearningLedgerModels'

function sampleEnSummary(): LedgerSummary {
  const summary = createEmptyLedgerSummary()
  summary.newPool = ['banana', 'dog']
  summary.dueReview = []
  summary.mastered = ['apple', 'cat']
  summary.cooling = ['red']
  return summary
}

export default function vocabLedgerSectionTest(): void {
  describe('vocabLedgerSectionTest', () => {
    it('empty_summaries_render_empty_string', 0, () => {
      const empty = createEmptyLedgerSummary()
      expect(renderVocabLedgerSection(null, null)).assertEqual('')
      expect(renderVocabLedgerSection(empty, empty)).assertEqual('')
    })

    it('en_only_renders_english_lines_and_rules', 0, () => {
      const text = renderVocabLedgerSection(sampleEnSummary(), null)
      expect(text.indexOf('【词汇台账】') >= 0).assertTrue()
      expect(text.indexOf('英语已掌握') >= 0).assertTrue()
      expect(text.indexOf('apple') >= 0).assertTrue()
      expect(text.indexOf('英语今日新词') >= 0).assertTrue()
      expect(text.indexOf('英语冷却中') >= 0).assertTrue()
      expect(text.indexOf('语文') < 0).assertTrue()
      expect(text.indexOf('出题规则') >= 0).assertTrue()
    })

    it('due_review_hint_shows_last_mode', 0, () => {
      const summary = createEmptyLedgerSummary()
      const hint: DueReviewHint = { display: 'banana', lastMode: 'english_quiz.listen_choice', dueInMs: 0 }
      summary.dueReview = [hint]
      const text = renderVocabLedgerSection(summary, null)
      expect(text.indexOf('banana(上次 english_quiz.listen_choice)') >= 0).assertTrue()
      expect(text.indexOf('换题型巩固') >= 0).assertTrue()
    })

    it('zh_lines_rendered_for_chinese_summary', 0, () => {
      const zh = createEmptyLedgerSummary()
      zh.mastered = ['山']
      const text = renderVocabLedgerSection(null, zh)
      expect(text.indexOf('语文已掌握') >= 0).assertTrue()
      expect(text.indexOf('山') >= 0).assertTrue()
    })
  })
}
