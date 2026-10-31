import { describe, it, expect } from '@ohos/hypium'
import {
  advanceTask,
  buildRevealPrompt,
  buildSuccessPrompt,
  buildTaskPrompt,
  buildWrongPrompt,
  createTaskState,
  currentTargetId,
  isTaskComplete,
  judgeTaskTap,
  nextTourIndex
} from '../../../../main/ets/utils/RoomEnglishLesson'

const TARGETS: string[] = ['sofa', 'rug', 'tv']

export default function roomEnglishLessonTest() {
  describe('createTaskState', () => {
    it('starts at the first target', 0, () => {
      const s = createTaskState(TARGETS)
      expect(s.targetIndex).assertEqual(0)
      expect(s.correct).assertEqual(0)
      expect(s.completed).assertFalse()
      expect(s.resolved).assertFalse()
      expect(currentTargetId(s, TARGETS)).assertEqual('sofa')
    })
  })

  describe('judgeTaskTap', () => {
    it('accepts a first-try correct tap', 0, () => {
      const r = judgeTaskTap(createTaskState(TARGETS), TARGETS, 'sofa', 2)
      expect(r.verdict).assertEqual('correct')
      expect(r.targetId).assertEqual('sofa')
      expect(r.advanced).assertTrue()
      expect(r.state.correct).assertEqual(1)
      expect(r.state.firstTry).assertEqual(1)
      expect(r.state.attempts).assertEqual(1)
      expect(r.state.resolved).assertTrue()
    })

    it('counts a wrong-then-correct tap as correct but not first-try', 0, () => {
      let r = judgeTaskTap(createTaskState(TARGETS), TARGETS, 'rug', 2)
      expect(r.verdict).assertEqual('wrong')
      r = judgeTaskTap(r.state, TARGETS, 'sofa', 2)
      expect(r.verdict).assertEqual('correct')
      expect(r.state.correct).assertEqual(1)
      expect(r.state.firstTry).assertEqual(0)
      expect(r.state.attempts).assertEqual(2)
    })

    it('does not burn a second attempt on the same wrong object', 0, () => {
      let r = judgeTaskTap(createTaskState(TARGETS), TARGETS, 'tv', 2)
      expect(r.verdict).assertEqual('wrong')
      expect(r.state.wrongStreak).assertEqual(1)
      r = judgeTaskTap(r.state, TARGETS, 'tv', 2)
      expect(r.verdict).assertEqual('repeat_wrong')
      expect(r.state.wrongStreak).assertEqual(1)
      expect(r.state.attempts).assertEqual(2)
    })

    it('reveals after max_attempts different wrong taps', 0, () => {
      let r = judgeTaskTap(createTaskState(TARGETS), TARGETS, 'rug', 2)
      r = judgeTaskTap(r.state, TARGETS, 'tv', 2)
      expect(r.verdict).assertEqual('reveal')
      expect(r.targetId).assertEqual('sofa')
      expect(r.advanced).assertTrue()
      expect(r.state.revealed).assertEqual(1)
      expect(r.state.attempts).assertEqual(2)
      expect(r.state.resolved).assertTrue()
    })

    it('ignores taps after a target is resolved', 0, () => {
      let r = judgeTaskTap(createTaskState(TARGETS), TARGETS, 'sofa', 2)
      r = judgeTaskTap(r.state, TARGETS, 'rug', 2)
      expect(r.verdict).assertEqual('ignore')
      expect(r.advanced).assertFalse()
    })

    it('ignores an empty id', 0, () => {
      const r = judgeTaskTap(createTaskState(TARGETS), TARGETS, '', 2)
      expect(r.verdict).assertEqual('ignore')
    })
  })

  describe('advanceTask', () => {
    it('moves to the next target and clears the per-target counters', 0, () => {
      let r = judgeTaskTap(createTaskState(TARGETS), TARGETS, 'sofa', 2)
      let s = advanceTask(r.state, TARGETS)
      expect(s.targetIndex).assertEqual(1)
      expect(s.wrongStreak).assertEqual(0)
      expect(s.lastWrongId).assertEqual('')
      expect(s.resolved).assertFalse()
      expect(currentTargetId(s, TARGETS)).assertEqual('rug')
    })

    it('completes after the last target', 0, () => {
      let s = createTaskState(TARGETS)
      let r = judgeTaskTap(s, TARGETS, 'sofa', 2)
      s = advanceTask(r.state, TARGETS)
      r = judgeTaskTap(s, TARGETS, 'rug', 2)
      s = advanceTask(r.state, TARGETS)
      r = judgeTaskTap(s, TARGETS, 'tv', 2)
      s = advanceTask(r.state, TARGETS)
      expect(s.completed).assertTrue()
      expect(s.targetIndex).assertEqual(3)
      expect(isTaskComplete(s, TARGETS)).assertTrue()
    })
  })

  describe('nextTourIndex', () => {
    it('advances until the last tour step', 0, () => {
      expect(nextTourIndex(0, 3)).assertEqual(1)
      expect(nextTourIndex(1, 3)).assertEqual(2)
      expect(nextTourIndex(2, 3)).assertEqual(-1)
    })
  })

  describe('prompt copy', () => {
    it('builds the exact task and feedback sentences', 0, () => {
      expect(buildTaskPrompt('coffee table')).assertEqual('Find the coffee table.')
      expect(buildWrongPrompt('rug')).assertEqual("That's a rug. Try again.")
      expect(buildSuccessPrompt('sofa')).assertEqual('Yes! This is a sofa.')
      expect(buildRevealPrompt('sofa')).assertEqual('Here it is! This is a sofa.')
    })

    it('uses an for vowel-initial words', 0, () => {
      expect(buildSuccessPrompt('oven')).assertEqual('Yes! This is an oven.')
      expect(buildWrongPrompt('air conditioner')).assertEqual("That's an air conditioner. Try again.")
    })
  })
}
