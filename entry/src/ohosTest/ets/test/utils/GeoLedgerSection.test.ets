import { describe, it, expect } from '@ohos/hypium'
import { renderGeoLedgerSection } from '../../../../main/ets/utils/LessonPlanPromptUtils'
import { LedgerSummary, DueReviewHint, createEmptyLedgerSummary } from '../../../../main/ets/models/LearningLedgerModels'

function sampleGeoSummary(): LedgerSummary {
  const summary = createEmptyLedgerSummary()
  summary.newPool = ['河北', '山西']
  const hint: DueReviewHint = { display: '天津', lastMode: 'map_puzzle.district', dueInMs: 0 }
  summary.dueReview = [hint]
  summary.mastered = ['北京']
  summary.cooling = ['内蒙古']
  return summary
}

export default function geoLedgerSectionTest(): void {
  describe('geoLedgerSectionTest', () => {
    it('null_or_empty_summary_renders_empty_string', 0, () => {
      expect(renderGeoLedgerSection(null)).assertEqual('')
      expect(renderGeoLedgerSection(createEmptyLedgerSummary())).assertEqual('')
    })

    it('renders_geo_section_with_four_lists', 0, () => {
      const text = renderGeoLedgerSection(sampleGeoSummary())
      expect(text.indexOf('【地理台账】') >= 0).assertTrue()
      expect(text.indexOf('地理今日新词') >= 0).assertTrue()
      expect(text.indexOf('河北') >= 0).assertTrue()
      expect(text.indexOf('地理已掌握') >= 0).assertTrue()
      expect(text.indexOf('北京') >= 0).assertTrue()
      expect(text.indexOf('地理冷却中') >= 0).assertTrue()
    })

    it('due_review_keeps_last_mode_so_teacher_can_switch_playstyle', 0, () => {
      const text = renderGeoLedgerSection(sampleGeoSummary())
      expect(text.indexOf('天津(上次 map_puzzle.district)') >= 0).assertTrue()
      expect(text.indexOf('换题型巩固') >= 0).assertTrue()
    })

    it('rules_mention_the_three_map_playstyles', 0, () => {
      const text = renderGeoLedgerSection(sampleGeoSummary())
      expect(text.indexOf('map_quiz.locate') >= 0).assertTrue()
      expect(text.indexOf('map_puzzle') >= 0).assertTrue()
      expect(text.indexOf('【词汇台账】') < 0).assertTrue()
    })
  })
}
