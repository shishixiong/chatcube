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
    it('四个mode合法参数通过', 0, () => {
      const c1: Record<string, Object> = baseArgs('number_bond'); c1['total'] = 9
      const c2: Record<string, Object> = baseArgs('ten_frame'); c2['a'] = 9; c2['b'] = 5
      const c3: Record<string, Object> = baseArgs('balance'); c3['left'] = 9; c3['right'] = 5
      const c4: Record<string, Object> = baseArgs('clock'); c4['hour'] = 9; c4['minute'] = 30
      expect(validateMathTeachArgs(asJson(c1), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c2), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c3), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c4), null).ok).assertTrue()
    })
    it('已下线mode拒绝', 0, () => {
      expect(validateMathTeachArgs(asJson(baseArgs('number_line')), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(baseArgs('place_value')), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(baseArgs('shape')), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(baseArgs('bar_model')), null).ok).assertFalse()
    })
    it('number_bond_total收窄2到10', 0, () => {
      const ok: Record<string, Object> = baseArgs('number_bond'); ok['total'] = 10
      expect(validateMathTeachArgs(asJson(ok), null).ok).assertTrue()
      const bad: Record<string, Object> = baseArgs('number_bond'); bad['total'] = 11
      expect(validateMathTeachArgs(asJson(bad), null).ok).assertFalse()
    })
    it('mode越界或缺失拒绝', 0, () => {
      expect(validateMathTeachArgs(asJson(baseArgs('huarongdao')), null).ok).assertFalse()
      expect(validateMathTeachArgs('{}', null).ok).assertFalse()
    })
    it('坏JSON拒绝', 0, () => {
      expect(validateMathTeachArgs('not-json', null).ok).assertFalse()
    })
    it('凑十边界_ten_frame_sum10拒_11收_19收', 0, () => {
      const t1: Record<string, Object> = baseArgs('ten_frame'); t1['a'] = 5; t1['b'] = 5
      expect(validateMathTeachArgs(asJson(t1), null).ok).assertFalse()
      const t2: Record<string, Object> = baseArgs('ten_frame'); t2['a'] = 5; t2['b'] = 6
      expect(validateMathTeachArgs(asJson(t2), null).ok).assertTrue()
      const t3: Record<string, Object> = baseArgs('ten_frame'); t3['a'] = 9; t3['b'] = 10
      expect(validateMathTeachArgs(asJson(t3), null).ok).assertTrue()
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
    it('clock_minute只收5分钟步长', 0, () => {
      const ok1: Record<string, Object> = baseArgs('clock'); ok1['hour'] = 9; ok1['minute'] = 0
      const ok2: Record<string, Object> = baseArgs('clock'); ok2['hour'] = 9; ok2['minute'] = 30
      const ok3: Record<string, Object> = baseArgs('clock'); ok3['hour'] = 9; ok3['minute'] = 55
      const ok4: Record<string, Object> = baseArgs('clock'); ok4['hour'] = 12; ok4['minute'] = 5
      expect(validateMathTeachArgs(asJson(ok1), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(ok2), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(ok3), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(ok4), null).ok).assertTrue()
      const bad1: Record<string, Object> = baseArgs('clock'); bad1['hour'] = 9; bad1['minute'] = 3
      const bad2: Record<string, Object> = baseArgs('clock'); bad2['hour'] = 9; bad2['minute'] = 57
      const bad3: Record<string, Object> = baseArgs('clock'); bad3['hour'] = 9; bad3['minute'] = 60
      const bad4: Record<string, Object> = baseArgs('clock'); bad4['hour'] = 13; bad4['minute'] = 0
      expect(validateMathTeachArgs(asJson(bad1), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(bad2), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(bad3), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(bad4), null).ok).assertFalse()
    })
  })
}
