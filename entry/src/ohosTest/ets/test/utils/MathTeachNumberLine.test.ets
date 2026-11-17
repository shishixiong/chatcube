import { describe, it, expect } from '@ohos/hypium'
import {
  numberLineX, numberLineHops, numberLineSteps, numberLineStepNarrations,
  NUMBER_LINE_WIDTH, NUMBER_LINE_PAD, NUMBER_LINE_BASE_Y,
  NumberLineHops, NumberLineStep
} from '../../../../main/ets/utils/MathTeachNumberLine'

export default function mathTeachNumberLineTest() {
  describe('mathTeachNumberLine', () => {
    it('add_9加5_两跳1和4_终点14', 0, () => {
      const h: NumberLineHops = numberLineHops(9, 5, 'add')
      expect(h.firstHop).assertEqual(1)
      expect(h.secondHop).assertEqual(4)
      expect(h.end).assertEqual(14)
      expect(h.dir).assertEqual(1)
    })
    it('add_6加7_两跳4和3', 0, () => {
      const h: NumberLineHops = numberLineHops(6, 7, 'add')
      expect(h.firstHop).assertEqual(4)
      expect(h.secondHop).assertEqual(3)
      expect(h.end).assertEqual(13)
    })
    it('sub_15减9_两跳5和4_终点6', 0, () => {
      const h: NumberLineHops = numberLineHops(15, 9, 'sub')
      expect(h.firstHop).assertEqual(5)
      expect(h.secondHop).assertEqual(4)
      expect(h.end).assertEqual(6)
      expect(h.dir).assertEqual(-1)
    })
    it('sub_11减2_两跳1和1_终点9', 0, () => {
      const h: NumberLineHops = numberLineHops(11, 2, 'sub')
      expect(h.firstHop).assertEqual(1)
      expect(h.secondHop).assertEqual(1)
      expect(h.end).assertEqual(9)
    })
    it('几何_x单调且中转站在10', 0, () => {
      const add: NumberLineHops = numberLineHops(9, 5, 'add')
      expect(add.x1 < add.x2).assertTrue()
      expect(add.x2 < add.x3).assertTrue()
      expect(add.x2).assertEqual(numberLineX(10))
      const sub: NumberLineHops = numberLineHops(15, 9, 'sub')
      expect(sub.x1 > sub.x2).assertTrue()
      expect(sub.x2 > sub.x3).assertTrue()
      expect(sub.x2).assertEqual(numberLineX(10))
    })
    it('几何_弧线控制点在两落点中点且高于基线', 0, () => {
      const h: NumberLineHops = numberLineHops(9, 5, 'add')
      expect(h.arc1X).assertEqual((h.x1 + h.x2) / 2)
      expect(h.arc2X).assertEqual((h.x2 + h.x3) / 2)
      expect(h.arc1Y < NUMBER_LINE_BASE_Y).assertTrue()
      expect(h.arc2Y < NUMBER_LINE_BASE_Y).assertTrue()
      expect(h.arc2Y < h.arc1Y).assertTrue()
    })
    it('数轴映射_0在左垫_20在右垫', 0, () => {
      expect(numberLineX(0)).assertEqual(NUMBER_LINE_PAD)
      expect(numberLineX(20)).assertEqual(NUMBER_LINE_WIDTH - NUMBER_LINE_PAD)
      expect(numberLineX(10)).assertEqual(NUMBER_LINE_WIDTH / 2)
    })
    it('两步步骤数据_add与sub', 0, () => {
      const addSteps: NumberLineStep[] = numberLineSteps(9, 5, 'add')
      expect(addSteps.length).assertEqual(2)
      expect(addSteps[0].title).assertEqual('先跳到 10')
      expect(addSteps[1].title).assertEqual('再跳余数')
      expect(addSteps[1].action).assertEqual('本课完成')
      const subSteps: NumberLineStep[] = numberLineSteps(15, 9, 'sub')
      expect(subSteps.length).assertEqual(2)
      expect(subSteps[0].title).assertEqual('先跳回 10')
      expect(subSteps[1].title).assertEqual('再跳回余数')
    })
    it('口播稿与步骤一致', 0, () => {
      const narrations: string[] = numberLineStepNarrations(15, 9, 'sub')
      const steps: NumberLineStep[] = numberLineSteps(15, 9, 'sub')
      expect(narrations.length).assertEqual(2)
      for (let i = 0; i < steps.length; i++) {
        expect(narrations[i]).assertEqual(steps[i].narration)
      }
    })
    it('防御取界不抛异常', 0, () => {
      const h: NumberLineHops = numberLineHops(3, 20, 'add')
      expect(h.end).assertEqual(16)
      const s: NumberLineHops = numberLineHops(25, 1, 'sub')
      expect(s.end).assertEqual(16)
      expect(numberLineX(-3)).assertEqual(NUMBER_LINE_PAD)
      expect(numberLineX(99)).assertEqual(NUMBER_LINE_WIDTH - NUMBER_LINE_PAD)
    })
  })
}