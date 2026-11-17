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
    it('七个mode合法参数通过', 0, () => {
      const c1: Record<string, Object> = baseArgs('number_bond'); c1['total'] = 9
      const c2: Record<string, Object> = baseArgs('ten_frame'); c2['a'] = 9; c2['b'] = 5
      const c3: Record<string, Object> = baseArgs('balance'); c3['left'] = 9; c3['right'] = 5
      const c4: Record<string, Object> = baseArgs('clock'); c4['hour'] = 9; c4['minute'] = 30
      const c5: Record<string, Object> = baseArgs('break_ten'); c5['a'] = 15; c5['b'] = 9; c5['skill_key'] = 'math_subtraction'
      const c6: Record<string, Object> = baseArgs('place_value'); c6['tens'] = 2; c6['ones'] = 8; c6['action'] = 'bundle'; c6['skill_key'] = 'math_counting'
      const c7: Record<string, Object> = baseArgs('number_line'); c7['start'] = 9; c7['step'] = 5; c7['op'] = 'add'
      expect(validateMathTeachArgs(asJson(c1), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c2), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c3), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c4), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c5), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c6), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(c7), null).ok).assertTrue()
    })
    it('未实现mode拒绝', 0, () => {
      expect(validateMathTeachArgs(asJson(baseArgs('shape')), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(baseArgs('bar_model')), null).ok).assertFalse()
    })
    it('number_bond_total放宽2到99', 0, () => {
      const ok1: Record<string, Object> = baseArgs('number_bond'); ok1['total'] = 2
      expect(validateMathTeachArgs(asJson(ok1), null).ok).assertTrue()
      const ok2: Record<string, Object> = baseArgs('number_bond'); ok2['total'] = 28
      expect(validateMathTeachArgs(asJson(ok2), null).ok).assertTrue()
      const ok3: Record<string, Object> = baseArgs('number_bond'); ok3['total'] = 99
      expect(validateMathTeachArgs(asJson(ok3), null).ok).assertTrue()
      const badLow: Record<string, Object> = baseArgs('number_bond'); badLow['total'] = 1
      expect(validateMathTeachArgs(asJson(badLow), null).ok).assertFalse()
      const badHigh: Record<string, Object> = baseArgs('number_bond'); badHigh['total'] = 100
      expect(validateMathTeachArgs(asJson(badHigh), null).ok).assertFalse()
      const badFrac: Record<string, Object> = baseArgs('number_bond'); badFrac['total'] = 28.5
      expect(validateMathTeachArgs(asJson(badFrac), null).ok).assertFalse()
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
    it('balance范围扩到万以内_99999收_21收_100000拒_0拒', 0, () => {
      const ok1: Record<string, Object> = baseArgs('balance'); ok1['left'] = 99999; ok1['right'] = 20
      const ok2: Record<string, Object> = baseArgs('balance'); ok2['left'] = 20; ok2['right'] = 99999
      const ok3: Record<string, Object> = baseArgs('balance'); ok3['left'] = 21; ok3['right'] = 21
      expect(validateMathTeachArgs(asJson(ok1), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(ok2), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(ok3), null).ok).assertTrue()
      const bad1: Record<string, Object> = baseArgs('balance'); bad1['left'] = 100000; bad1['right'] = 5
      const bad2: Record<string, Object> = baseArgs('balance'); bad2['left'] = 0; bad2['right'] = 5
      const bad3: Record<string, Object> = baseArgs('balance'); bad3['left'] = 5; bad3['right'] = 100000
      expect(validateMathTeachArgs(asJson(bad1), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(bad2), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(bad3), null).ok).assertFalse()
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
    it('break_ten退位边界_15减5拒_15减6收_11减2收_18减9收', 0, () => {
      const bad: Record<string, Object> = baseArgs('break_ten'); bad['a'] = 15; bad['b'] = 5
      expect(validateMathTeachArgs(asJson(bad), null).ok).assertFalse()
      const ok1: Record<string, Object> = baseArgs('break_ten'); ok1['a'] = 15; ok1['b'] = 6
      expect(validateMathTeachArgs(asJson(ok1), null).ok).assertTrue()
      const ok2: Record<string, Object> = baseArgs('break_ten'); ok2['a'] = 11; ok2['b'] = 2
      expect(validateMathTeachArgs(asJson(ok2), null).ok).assertTrue()
      const ok3: Record<string, Object> = baseArgs('break_ten'); ok3['a'] = 18; ok3['b'] = 9
      expect(validateMathTeachArgs(asJson(ok3), null).ok).assertTrue()
    })
    it('break_ten范围越界与缺参拒绝', 0, () => {
      const badA1: Record<string, Object> = baseArgs('break_ten'); badA1['a'] = 10; badA1['b'] = 9
      const badA2: Record<string, Object> = baseArgs('break_ten'); badA2['a'] = 19; badA2['b'] = 9
      const badB1: Record<string, Object> = baseArgs('break_ten'); badB1['a'] = 15; badB1['b'] = 1
      const badB2: Record<string, Object> = baseArgs('break_ten'); badB2['a'] = 15; badB2['b'] = 10
      const badFrac: Record<string, Object> = baseArgs('break_ten'); badFrac['a'] = 15.5; badFrac['b'] = 9
      const missing: Record<string, Object> = baseArgs('break_ten'); missing['a'] = 15
      expect(validateMathTeachArgs(asJson(badA1), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(badA2), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(badB1), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(badB2), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(badFrac), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(missing), null).ok).assertFalse()
    })
    it('place_value_action白名单与两分支范围', 0, () => {
      const okB: Record<string, Object> = baseArgs('place_value'); okB['tens'] = 0; okB['ones'] = 9; okB['action'] = 'bundle'
      const okB2: Record<string, Object> = baseArgs('place_value'); okB2['tens'] = 8; okB2['ones'] = 1; okB2['action'] = 'bundle'
      const okU: Record<string, Object> = baseArgs('place_value'); okU['tens'] = 1; okU['ones'] = 0; okU['action'] = 'unbundle'
      const okU2: Record<string, Object> = baseArgs('place_value'); okU2['tens'] = 9; okU2['ones'] = 9; okU2['action'] = 'unbundle'
      expect(validateMathTeachArgs(asJson(okB), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(okB2), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(okU), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(okU2), null).ok).assertTrue()
      const badAct: Record<string, Object> = baseArgs('place_value'); badAct['tens'] = 2; badAct['ones'] = 8; badAct['action'] = 'split'
      const badB1: Record<string, Object> = baseArgs('place_value'); badB1['tens'] = 9; badB1['ones'] = 8; badB1['action'] = 'bundle'
      const badB2: Record<string, Object> = baseArgs('place_value'); badB2['tens'] = 2; badB2['ones'] = 0; badB2['action'] = 'bundle'
      const badU1: Record<string, Object> = baseArgs('place_value'); badU1['tens'] = 0; badU1['ones'] = 5; badU1['action'] = 'unbundle'
      const badU2: Record<string, Object> = baseArgs('place_value'); badU2['tens'] = 3; badU2['ones'] = 10; badU2['action'] = 'unbundle'
      const missingAct: Record<string, Object> = baseArgs('place_value'); missingAct['tens'] = 2; missingAct['ones'] = 8
      expect(validateMathTeachArgs(asJson(badAct), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(badB1), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(badB2), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(badU1), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(badU2), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(missingAct), null).ok).assertFalse()
    })
    it('number_line_add凑十边界_和10拒_11收_19收_step越界拒', 0, () => {
      const bad1: Record<string, Object> = baseArgs('number_line'); bad1['start'] = 6; bad1['step'] = 4; bad1['op'] = 'add'
      const ok1: Record<string, Object> = baseArgs('number_line'); ok1['start'] = 6; ok1['step'] = 5; ok1['op'] = 'add'
      const ok2: Record<string, Object> = baseArgs('number_line'); ok2['start'] = 9; ok2['step'] = 10; ok2['op'] = 'add'
      const bad2: Record<string, Object> = baseArgs('number_line'); bad2['start'] = 9; bad2['step'] = 12; bad2['op'] = 'add'
      expect(validateMathTeachArgs(asJson(bad1), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(ok1), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(ok2), null).ok).assertTrue()
      expect(validateMathTeachArgs(asJson(bad2), null).ok).assertFalse()
      const badStart: Record<string, Object> = baseArgs('number_line'); badStart['start'] = 5; badStart['step'] = 8; badStart['op'] = 'add'
      expect(validateMathTeachArgs(asJson(badStart), null).ok).assertFalse()
    })
    it('number_line_op缺省add_sub破十边界', 0, () => {
      const dflt: Record<string, Object> = baseArgs('number_line'); dflt['start'] = 9; dflt['step'] = 5
      expect(validateMathTeachArgs(asJson(dflt), null).ok).assertTrue()
      const badOp: Record<string, Object> = baseArgs('number_line'); badOp['start'] = 9; badOp['step'] = 5; badOp['op'] = 'mul'
      expect(validateMathTeachArgs(asJson(badOp), null).ok).assertFalse()
      const badSub: Record<string, Object> = baseArgs('number_line'); badSub['start'] = 15; badSub['step'] = 5; badSub['op'] = 'sub'
      expect(validateMathTeachArgs(asJson(badSub), null).ok).assertFalse()
      const okSub: Record<string, Object> = baseArgs('number_line'); okSub['start'] = 15; okSub['step'] = 6; okSub['op'] = 'sub'
      expect(validateMathTeachArgs(asJson(okSub), null).ok).assertTrue()
      const okSub2: Record<string, Object> = baseArgs('number_line'); okSub2['start'] = 11; okSub2['step'] = 2; okSub2['op'] = 'sub'
      expect(validateMathTeachArgs(asJson(okSub2), null).ok).assertTrue()
      const okSub3: Record<string, Object> = baseArgs('number_line'); okSub3['start'] = 18; okSub3['step'] = 9; okSub3['op'] = 'sub'
      expect(validateMathTeachArgs(asJson(okSub3), null).ok).assertTrue()
      const badStart: Record<string, Object> = baseArgs('number_line'); badStart['start'] = 10; badStart['step'] = 9; badStart['op'] = 'sub'
      const badStep: Record<string, Object> = baseArgs('number_line'); badStep['start'] = 15; badStep['step'] = 1; badStep['op'] = 'sub'
      expect(validateMathTeachArgs(asJson(badStart), null).ok).assertFalse()
      expect(validateMathTeachArgs(asJson(badStep), null).ok).assertFalse()
    })
    it('shape_props四个可数图形收_不可数图形拒', 0, () => {
      const shapes: string[] = ['triangle', 'square', 'rectangle', 'pentagon']
      for (let i = 0; i < shapes.length; i++) {
        const ok: Record<string, Object> = baseArgs('shape_props')
        ok['shape'] = shapes[i]
        ok['skill_key'] = 'math_shapes'
        expect(validateMathTeachArgs(asJson(ok), null).ok).assertTrue()
      }
      const bads: string[] = ['circle', 'star', 'heart', 'oval', '']
      for (let i = 0; i < bads.length; i++) {
        const bad: Record<string, Object> = baseArgs('shape_props')
        bad['shape'] = bads[i]
        bad['skill_key'] = 'math_shapes'
        expect(validateMathTeachArgs(asJson(bad), null).ok).assertFalse()
      }
      const missing: Record<string, Object> = baseArgs('shape_props')
      missing['skill_key'] = 'math_shapes'
      expect(validateMathTeachArgs(asJson(missing), null).ok).assertFalse()
    })
    it('fraction_intro份数与分子边界', 0, () => {
      const ok1: Record<string, Object> = baseArgs('fraction_intro')
      ok1['parts'] = 2; ok1['shaded'] = 1; ok1['skill_key'] = 'math_fractions'
      expect(validateMathTeachArgs(asJson(ok1), null).ok).assertTrue()
      const ok2: Record<string, Object> = baseArgs('fraction_intro')
      ok2['parts'] = 8; ok2['shaded'] = 7; ok2['skill_key'] = 'math_fractions'; ok2['form'] = 'bar'
      expect(validateMathTeachArgs(asJson(ok2), null).ok).assertTrue()
      const full: Record<string, Object> = baseArgs('fraction_intro')
      full['parts'] = 4; full['shaded'] = 4; full['skill_key'] = 'math_fractions'
      expect(validateMathTeachArgs(asJson(full), null).ok).assertFalse()
      const zero: Record<string, Object> = baseArgs('fraction_intro')
      zero['parts'] = 4; zero['shaded'] = 0; zero['skill_key'] = 'math_fractions'
      expect(validateMathTeachArgs(asJson(zero), null).ok).assertFalse()
    })
    it('fraction_intro参数范围与form白名单', 0, () => {
      const p1: Record<string, Object> = baseArgs('fraction_intro')
      p1['parts'] = 1; p1['shaded'] = 1; p1['skill_key'] = 'math_fractions'
      expect(validateMathTeachArgs(asJson(p1), null).ok).assertFalse()
      const p9: Record<string, Object> = baseArgs('fraction_intro')
      p9['parts'] = 9; p9['shaded'] = 1; p9['skill_key'] = 'math_fractions'
      expect(validateMathTeachArgs(asJson(p9), null).ok).assertFalse()
      const badForm: Record<string, Object> = baseArgs('fraction_intro')
      badForm['parts'] = 4; badForm['shaded'] = 3; badForm['form'] = 'cake'; badForm['skill_key'] = 'math_fractions'
      expect(validateMathTeachArgs(asJson(badForm), null).ok).assertFalse()
      const dfltForm: Record<string, Object> = baseArgs('fraction_intro')
      dfltForm['parts'] = 4; dfltForm['shaded'] = 3; dfltForm['skill_key'] = 'math_fractions'
      expect(validateMathTeachArgs(asJson(dfltForm), null).ok).assertTrue()
      const badSkill: Record<string, Object> = baseArgs('fraction_intro')
      badSkill['parts'] = 4; badSkill['shaded'] = 3; badSkill['skill_key'] = 'english_vocab'
      expect(validateMathTeachArgs(asJson(badSkill), null).ok).assertFalse()
    })
  })
}
