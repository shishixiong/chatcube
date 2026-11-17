import { describe, it, expect } from '@ohos/hypium'
import {
  placeValueRead, placeValueAddToTen, canBundle, placeValueAfter,
  placeValueSteps, placeValueStepNarrations, PlaceValueState, PlaceValueStep
} from '../../../../main/ets/utils/MathTeachPlaceValue'

export default function mathTeachPlaceValueTest() {
  describe('mathTeachPlaceValue', () => {
    it('读数_2捆8根是28', 0, () => {
      expect(placeValueRead(2, 8)).assertEqual(28)
      expect(placeValueRead(0, 5)).assertEqual(5)
      expect(placeValueRead(9, 9)).assertEqual(99)
    })
    it('添棒数_10减个位', 0, () => {
      expect(placeValueAddToTen(8)).assertEqual(2)
      expect(placeValueAddToTen(1)).assertEqual(9)
      expect(placeValueAddToTen(9)).assertEqual(1)
    })
    it('canBundle边界_9不捆_10捆', 0, () => {
      expect(canBundle(9)).assertFalse()
      expect(canBundle(10)).assertTrue()
      expect(canBundle(12)).assertTrue()
    })
    it('bundle后_2捆8根变3捆0根', 0, () => {
      const after: PlaceValueState = placeValueAfter(2, 8, 'bundle')
      expect(after.tens).assertEqual(3)
      expect(after.ones).assertEqual(0)
      expect(placeValueRead(after.tens, after.ones)).assertEqual(30)
    })
    it('unbundle后_3捆2根变2捆12根_总数不变', 0, () => {
      const before: number = placeValueRead(3, 2)
      const after: PlaceValueState = placeValueAfter(3, 2, 'unbundle')
      expect(after.tens).assertEqual(2)
      expect(after.ones).assertEqual(12)
      expect(placeValueRead(after.tens, after.ones)).assertEqual(before)
    })
    it('unbundle边界_1捆0根拆完0捆10根', 0, () => {
      const after: PlaceValueState = placeValueAfter(1, 0, 'unbundle')
      expect(after.tens).assertEqual(0)
      expect(after.ones).assertEqual(10)
      expect(placeValueRead(after.tens, after.ones)).assertEqual(10)
    })
    it('两步步骤数据_bundle与unbundle', 0, () => {
      const bSteps: PlaceValueStep[] = placeValueSteps(2, 8, 'bundle')
      expect(bSteps.length).assertEqual(2)
      expect(bSteps[0].title).assertEqual('数一数')
      expect(bSteps[1].title).assertEqual('满十捆一捆')
      expect(bSteps[0].action).assertEqual('添棒凑十')
      expect(bSteps[1].action).assertEqual('本课完成')
      const uSteps: PlaceValueStep[] = placeValueSteps(3, 2, 'unbundle')
      expect(uSteps.length).assertEqual(2)
      expect(uSteps[1].title).assertEqual('拆一捆')
      expect(uSteps[0].action).assertEqual('拆一捆')
    })
    it('口播稿与步骤一致', 0, () => {
      const narrations: string[] = placeValueStepNarrations(2, 8, 'bundle')
      const steps: PlaceValueStep[] = placeValueSteps(2, 8, 'bundle')
      expect(narrations.length).assertEqual(2)
      for (let i = 0; i < steps.length; i++) {
        expect(narrations[i]).assertEqual(steps[i].narration)
      }
    })
    it('防御取界不抛异常', 0, () => {
      expect(placeValueRead(-1, 0)).assertEqual(0)
      expect(placeValueAddToTen(0)).assertEqual(9)
      const after: PlaceValueState = placeValueAfter(0, 5, 'unbundle')
      expect(after.tens).assertEqual(0)
      expect(after.ones).assertEqual(15)
    })
  })
}