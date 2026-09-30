import { describe, it, expect } from '@ohos/hypium'
import {
  LEDGER_INTERVAL_DAYS,
  MASTERED_RECHECK_MS,
  LearningItem,
  LedgerSummary,
  createEmptyLedgerSummary,
  computeMasteryTransition
} from '../../../../main/ets/models/LearningLedgerModels'

export default function learningLedgerModelsTest(): void {
  describe('learningLedgerModelsTest', () => {
    it('interval_table_has_6_slots', 0, () => {
      expect(LEDGER_INTERVAL_DAYS.length).assertEqual(6)
      expect(LEDGER_INTERVAL_DAYS[0]).assertEqual(0)
      expect(LEDGER_INTERVAL_DAYS[5]).assertEqual(15)
    })

    it('computeMasteryTransition_correct_twice_bumps_mastery', 0, () => {
      // streak=1, mastery=1 → 再对一次 → mastery 2, 间隔 2 天
      const t = computeMasteryTransition(1, 1, true, 1000000)
      expect(t.mastery).assertEqual(2)
      expect(t.consecutiveCorrect).assertEqual(2)
      expect(t.justMastered).assertFalse()
      expect(t.nextReviewAt).assertEqual(1000000 + 2 * 24 * 60 * 60 * 1000)
    })

    it('computeMasteryTransition_correct_once_no_bump', 0, () => {
      const t = computeMasteryTransition(0, 0, true, 1000000)
      expect(t.mastery).assertEqual(0)
      expect(t.consecutiveCorrect).assertEqual(1)
    })

    it('computeMasteryTransition_wrong_drops_and_resets', 0, () => {
      const t = computeMasteryTransition(3, 2, false, 1000000)
      expect(t.mastery).assertEqual(2)
      expect(t.consecutiveCorrect).assertEqual(0)
      expect(t.nextReviewAt).assertEqual(1000000 + 2 * 24 * 60 * 60 * 1000)
    })

    it('computeMasteryTransition_wrong_at_zero_floors', 0, () => {
      const t = computeMasteryTransition(0, 0, false, 1000000)
      expect(t.mastery).assertEqual(0)
      expect(t.nextReviewAt).assertEqual(1000000) // INTERVAL[0] = 0 天
    })

    it('computeMasteryTransition_mastery5_stays_and_uses_recheck_interval', 0, () => {
      // 已是 5：不再升, justMastered=false, 间隔 = 30 天抽检
      const t = computeMasteryTransition(5, 4, true, 1000000)
      expect(t.mastery).assertEqual(5)
      expect(t.justMastered).assertFalse()
      expect(t.nextReviewAt).assertEqual(1000000 + MASTERED_RECHECK_MS)
    })

    it('computeMasteryTransition_just_mastered_sets_flag_and_recheck', 0, () => {
      // mastery=4, streak=1 → 再对 → 升到 5, justMastered=true, 30 天抽检
      const t = computeMasteryTransition(4, 1, true, 1000000)
      expect(t.mastery).assertEqual(5)
      expect(t.justMastered).assertTrue()
      expect(t.nextReviewAt).assertEqual(1000000 + MASTERED_RECHECK_MS)
    })

    it('empty_summary_has_all_empty_lists', 0, () => {
      const s: LedgerSummary = createEmptyLedgerSummary()
      expect(s.newPool.length).assertEqual(0)
      expect(s.dueReview.length).assertEqual(0)
      expect(s.mastered.length).assertEqual(0)
      expect(s.cooling.length).assertEqual(0)
      expect(s.topRepeated.length).assertEqual(0)
    })

    it('learning_item_defaults', 0, () => {
      const item: LearningItem = new LearningItem()
      expect(item.itemKey).assertEqual('')
      expect(item.mastery).assertEqual(0)
      expect(item.exposureCount).assertEqual(0)
      expect(item.source).assertEqual('session')
    })
  })
}
