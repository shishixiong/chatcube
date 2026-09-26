import { describe, it, expect } from '@ohos/hypium'
import { validateMathTeachArgs } from '../../../../main/ets/utils/MathTeachValidation'

function baseArgs(mode: string): Record<string, Object> {
  const a: Record<string, Object> = {}
  a['mode'] = mode
  a['difficulty'] = 2
  a['concept'] = '测试知识点'
  a['skill_key'] = 'math_addition'
  return a
}

function asJson(a: Record<string, Object>): string {
  return JSON.stringify(a)
}

export default function mathTeachValidationTest() {
  describe('mathTeachValidation', () => {
    it('八个mode合法参数通过', 0, () => {
      const c1: Record<string, Object> = baseArgs('number_bond'); c1['total'] = 9
      const c2: Record<string, Object> = baseArgs('number_line'); c2['start'] = 9; c2['step'] = 5
      const c3: Record<string, Object> = baseArgs('ten_frame'); c3['a'] = 9; c3['b'] = 5
      const c4: Record<string, Object> = baseArgs('place_value'); c4['tens'] = 1; c4['ones'] = 7
      const c5: Record<string, Object> = baseArgs('balance'); c5['left'] = 9; c5['right'] = 5
      const c6: Record<string, Object> = baseArgs('shape'); c6['focus'] = 'circle'
      const c7: Record<string, Object> = baseArgs('clock'); c7['hour'] = 9; c7['minute'] = 30
      const c8: Record<string, Object> = baseArgs('bar_model'); c8['part_a'] = 3; c8['part_b'] = 4
      expect(validateMathTeachArgs(asJson(c1), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c2), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c3), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c4), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c5), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c6), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c7), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c8), null).ok).assertTrue()
    })
    it('mode越界或缺失拒绝', 0, () => {
      expect(validateMathTeachArgs(asJson(baseArgs('huarongdao')), null).ok).assertFalse()
      expect(validateMathTeachArgs('{}', null).ok).assertFalse()
    })
    it('坏JSON拒绝', 0, () => {
      expect(validateMathTeachArgs('not-json', null).ok).assertFalse()
    })
    it('凑十边界_number_line_sum10拒_11收_19收', 0, () => {
      const r1: Record<string, Object> = baseArgs('number_line'); r1['start'] = 9; r1['step'] = 1
      expect(validateMathTeachArgs(asJson(r1), null).ok).assertFalse()
      const r2: Record<string, Object> = baseArgs('number_line'); r2['start'] = 6; r2['step'] = 5
      expect(validateMathTeachArgs(asJson(r2), null).ok).assertTrue()
      const r3: Record<string, Object> = baseArgs('number_line'); r3['start'] = 9; r3['step'] = 10
      expect(validateMathTeachArgs(asJson(r3), null).ok).assertTrue()
    })
    it('凑十边界_ten_frame_sum10拒_11收_19收', 0, () => {
      const t1: Record<string, Object> = baseArgs('ten_frame'); t1['a'] = 5; t1['b'] = 5
      expect(validateMathTeachArgs(asJson(t1), null).ok).assertFalse()
      const t2: Record<string, Object> = baseArgs('ten_frame'); t2['a'] = 5; t2['b'] = 6
      expect(validateMathTeachArgs(asJson(t2), null).ok).assertTrue()
      const t3: Record<string, Object> = baseArgs('ten_frame'); t3['a'] = 9; t3['b'] = 10
      expect(validateMathTeachArgs(asJson(t3), null).ok).assertTrue()
    })
    it('number_line_start越界拒绝', 0, () => {
      const r: Record<string, Object> = baseArgs('number_line'); r['start'] = 5; r['step'] = 7
      expect(validateMathTeachArgs(asJson(r), null).ok).assertFalse()
    })
    it('难度偏差±1收_2拒', 0, () => {
      const lv: Record<string, number> = {}
      lv['math_addition'] = 3
      const ok1: Record<string, Object> = baseArgs('number_bond'); ok1['total'] = 9; ok1['difficulty'] = 2
      const ok2: Record<string, Object> = baseArgs('number_bond'); ok2['total'] = 9; ok2['difficulty'] = 4
      const bad1: Record<string, Object> = baseArgs('number_bond'); bad1['total'] = 9; bad1['difficulty'] = 1
      const bad2: Record<string, Object> = baseArgs('number_bond'); bad2['total'] = 9; bad2['difficulty'] = 5
      expect(validateMathTeachArgs(asJson(ok1), lv).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(ok2), lv).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(bad1), lv).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(bad2), lv).ok).assertFalse()
    })
    it('level0未评估跳过规则4', 0, () => {
      const lv: Record<string, number> = {}
      lv['math_addition'] = 0
      const c: Record<string, Object> = baseArgs('number_bond'); c['total'] = 9; c['difficulty'] = 5
      expect(validateMathTeachArgs(asJson(c), lv).ok).assertTrue()
    })
    it('profileLevels_null跳过规则4', 0, () => {
      const c: Record<string, Object> = baseArgs('number_bond'); c['total'] = 9; c['difficulty'] = 5
      expect(validateMathTeachArgs(asJson(c), null).ok).assertTrue()
    })
    it('skill_key越界与concept空拒绝', 0, () => {
      const s: Record<string, Object> = baseArgs('number_bond'); s['total'] = 9; s['skill_key'] = 'english_vocab'
      expect(validateMathTeachArgs(asJson(s), null).ok).assertFalse()
      const c: Record<string, Object> = baseArgs('number_bond'); c['total'] = 9; c['concept'] = ''
      expect(validateMathTeachArgs(asJson(c), null).ok).assertFalse()
    })
    it('clock_minute只收0和30', 0, () => {
      const c1: Record<string, Object> = baseArgs('clock'); c1['hour'] = 9; c1['minute'] = 15
      expect(validateMathTeachArgs(asJson(c1), null).ok).assertFalse()
      const c2: Record<string, Object> = baseArgs('clock'); c2['hour'] = 9; c2['minute'] = 0
      expect(validateMathTeachArgs(asJson(c2), null).ok).assertTrue()
    })
    it('shape_focus白名单', 0, () => {
      const s: Record<string, Object> = baseArgs('shape'); s['focus'] = 'hexagon'
      expect(validateMathTeachArgs(asJson(s), null).ok).assertFalse()
    })
    it('place_value双零拒绝', 0, () => {
      const p: Record<string, Object> = baseArgs('place_value'); p['tens'] = 0; p['ones'] = 0
      expect(validateMathTeachArgs(asJson(p), null).ok).assertFalse()
    })
  })
}
