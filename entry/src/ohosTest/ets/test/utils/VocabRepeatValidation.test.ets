import { describe, it, expect } from '@ohos/hypium'
import {
  parsePurpose,
  evaluateRepeatPolicy,
  buildRepeatBlockedMessage,
  VocabRepeatGateResult
} from '../../../../main/ets/utils/VocabRepeatValidation'
import { RepeatPolicyInput, SAME_MODE_COOLDOWN_MS, MASTERED_RECHECK_MS,
  REPEAT_REASON_SESSION_GAP, REPEAT_REASON_SAME_MODE_COOLDOWN, REPEAT_REASON_MASTERED_RECHECK
} from '../../../../main/ets/models/LearningLedgerModels'

function baseInput(): RepeatPolicyInput {
  const input: RepeatPolicyInput = {
    purpose: 'new',
    mode: 'english_quiz.listen_choice',
    now: 1000000,
    found: true,
    lastSeenAt: 1000000 - SAME_MODE_COOLDOWN_MS - 1000, // 默认已出冷却
    lastMode: 'english_quiz.listen_choice',
    mastery: 2,
    nextReviewAt: 1000000 + 60 * 60 * 1000,
    inSessionGap: false,
    itemKey: 'en:vocab:apple',
    display: 'apple'
  }
  return input
}

export default function vocabRepeatValidationTest(): void {
  describe('vocabRepeatValidationTest', () => {
    it('parsePurpose_defaults_to_new', 0, () => {
      expect(parsePurpose('{"mode":"listen_choice"}')).assertEqual('new')
      expect(parsePurpose('{"purpose":"review"}')).assertEqual('review')
      expect(parsePurpose('{"purpose":"NEW"}')).assertEqual('new')
      expect(parsePurpose('not-json')).assertEqual('new')
    })

    it('policy_new_item_allowed', 0, () => {
      const input = baseInput()
      input.found = false
      expect(evaluateRepeatPolicy(input).allowed).assertTrue()
    })

    it('policy_session_gap_blocks_any_purpose', 0, () => {
      // Review Focus #4: review 也不豁免 session_gap
      const inputNew = baseInput()
      inputNew.inSessionGap = true
      const checkNew = evaluateRepeatPolicy(inputNew)
      expect(checkNew.allowed).assertFalse()
      expect(checkNew.reason).assertEqual(REPEAT_REASON_SESSION_GAP)
      const inputReview = baseInput()
      inputReview.inSessionGap = true
      inputReview.purpose = 'review'
      const checkReview = evaluateRepeatPolicy(inputReview)
      expect(checkReview.allowed).assertFalse()
      expect(checkReview.reason).assertEqual(REPEAT_REASON_SESSION_GAP)
    })

    it('policy_review_bypasses_cooldown_and_recheck', 0, () => {
      const inCooldown = baseInput()
      inCooldown.lastSeenAt = 1000000 - 1000 // 1 秒前刚出, 同 mode → 冷却中
      inCooldown.purpose = 'review'
      expect(evaluateRepeatPolicy(inCooldown).allowed).assertTrue()
      const mastered = baseInput()
      mastered.mastery = 5
      mastered.nextReviewAt = 1000000 + MASTERED_RECHECK_MS
      mastered.purpose = 'review'
      expect(evaluateRepeatPolicy(mastered).allowed).assertTrue()
    })

    it('policy_new_blocked_by_same_mode_cooldown', 0, () => {
      const input = baseInput()
      input.lastSeenAt = 1000000 - 1000 // 冷却窗口内
      const check = evaluateRepeatPolicy(input)
      expect(check.allowed).assertFalse()
      expect(check.reason).assertEqual(REPEAT_REASON_SAME_MODE_COOLDOWN)
    })

    it('policy_new_allowed_when_mode_differs', 0, () => {
      // 同词不同题型 = 巩固, 放行
      const input = baseInput()
      input.lastSeenAt = 1000000 - 1000
      input.mode = 'english_quiz.spelling'
      expect(evaluateRepeatPolicy(input).allowed).assertTrue()
    })

    it('policy_new_blocked_by_mastered_recheck', 0, () => {
      const input = baseInput()
      input.mastery = 5
      input.nextReviewAt = 1000000 + MASTERED_RECHECK_MS
      // lastSeenAt 保持默认 (冷却窗口外), 只触发达标抽检
      const check = evaluateRepeatPolicy(input)
      expect(check.allowed).assertFalse()
      expect(check.reason).assertEqual(REPEAT_REASON_MASTERED_RECHECK)
    })

    it('blocked_message_contains_display_and_purpose_hint', 0, () => {
      const msg = buildRepeatBlockedMessage(REPEAT_REASON_SAME_MODE_COOLDOWN, 'apple')
      expect(msg.indexOf('apple') >= 0).assertTrue()
      expect(msg.indexOf('review') >= 0).assertTrue()
      const gap = buildRepeatBlockedMessage(REPEAT_REASON_SESSION_GAP, 'apple')
      expect(gap.indexOf('对话') >= 0).assertTrue()
      const gate: VocabRepeatGateResult = { blocked: true, error: 'repeat_blocked', message: msg }
      expect(gate.error).assertEqual('repeat_blocked')
    })
  })
}
