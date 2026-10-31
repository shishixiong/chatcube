import { describe, it, expect } from '@ohos/hypium'
import { BODY_PART_IDS, resolveBody3DFocusGroup, validateBody3DArgs } from '../../../../main/ets/utils/Body3DValidation'

/**
 * Body3DValidation 单元测试（body_3d 3D 身体英语课, spec 2026-10-31 §5）
 *
 * 校验纯逻辑层不依赖 rawfile / Web 容器，可直接跑。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */

export default function body3DValidationTest() {
  describe('validateBody3DArgs', () => {
    it('accepts minimal valid args', 0, () => {
      const r = validateBody3DArgs('{"skill_key":"english_vocab"}')
      expect(r.ok).assertTrue()
      expect(r.focus).assertEqual('all')
      expect(r.words.length).assertEqual(0)
    })

    it('accepts focus and words', 0, () => {
      const r = validateBody3DArgs('{"skill_key":"english_vocab","focus":"head","words":["head","eye"]}')
      expect(r.ok).assertTrue()
      expect(r.focus).assertEqual('head')
      expect(r.words.length).assertEqual(2)
      expect(r.words[1]).assertEqual('eye')
    })

    it('rejects malformed json', 0, () => {
      const r = validateBody3DArgs('not json')
      expect(r.ok).assertFalse()
      expect(r.error.length > 0).assertTrue()
    })

    it('rejects wrong skill_key', 0, () => {
      const r = validateBody3DArgs('{"skill_key":"general_social"}')
      expect(r.ok).assertFalse()
    })

    it('rejects unknown focus', 0, () => {
      const r = validateBody3DArgs('{"skill_key":"english_vocab","focus":"face"}')
      expect(r.ok).assertFalse()
    })

    it('accepts legs focus and maps to leg group', 0, () => {
      const r = validateBody3DArgs('{"skill_key":"english_vocab","focus":"legs","words":["knee","foot"]}')
      expect(r.ok).assertTrue()
      expect(r.focus).assertEqual('legs')
      expect(r.words.length).assertEqual(2)
      expect(resolveBody3DFocusGroup(r.focus)).assertEqual('leg')
    })

    it('rejects unknown word id', 0, () => {
      const r = validateBody3DArgs('{"skill_key":"english_vocab","words":["head","tail"]}')
      expect(r.ok).assertFalse()
      expect(r.error.indexOf('tail') >= 0).assertTrue()
    })

    it('rejects words outside the focus group', 0, () => {
      const r = validateBody3DArgs('{"skill_key":"english_vocab","focus":"legs","words":["head","knee"]}')
      expect(r.ok).assertFalse()
      expect(r.error).assertContain('focus')
    })

    it('rejects more than 8 words', 0, () => {
      const nine = BODY_PART_IDS.slice(0, 9)
      const args = '{"skill_key":"english_vocab","words":["' + nine.join('","') + '"]}'
      const r = validateBody3DArgs(args)
      expect(r.ok).assertFalse()
    })

    it('dedupes repeated words', 0, () => {
      const r = validateBody3DArgs('{"skill_key":"english_vocab","words":["head","head","nose"]}')
      expect(r.ok).assertTrue()
      expect(r.words.length).assertEqual(2)
    })

    it('rejects non-string entries', 0, () => {
      const r = validateBody3DArgs('{"skill_key":"english_vocab","words":[1,2]}')
      expect(r.ok).assertFalse()
    })

    it('covers 25 body parts', 0, () => {
      expect(BODY_PART_IDS.length).assertEqual(25)
    })

    it('includes every head word', 0, () => {
      const head = ['head', 'hair', 'face', 'ear', 'eye', 'nose', 'mouth', 'teeth']
      for (let i = 0; i < head.length; i++) {
        expect(BODY_PART_IDS.indexOf(head[i]) >= 0).assertTrue()
      }
    })

    it('includes every body word', 0, () => {
      const body = ['neck', 'shoulder', 'arm', 'elbow', 'hand', 'finger', 'thumb', 'chest', 'belly', 'back']
      for (let i = 0; i < body.length; i++) {
        expect(BODY_PART_IDS.indexOf(body[i]) >= 0).assertTrue()
      }
    })

    it('includes every leg and whole word', 0, () => {
      const rest = ['leg', 'knee', 'foot', 'toe', 'body', 'skin', 'tummy']
      for (let i = 0; i < rest.length; i++) {
        expect(BODY_PART_IDS.indexOf(rest[i]) >= 0).assertTrue()
      }
    })

    it('resolves focus groups', 0, () => {
      expect(resolveBody3DFocusGroup('head')).assertEqual('head')
      expect(resolveBody3DFocusGroup('body')).assertEqual('body')
      expect(resolveBody3DFocusGroup('legs')).assertEqual('leg')
      expect(resolveBody3DFocusGroup('whole')).assertEqual('whole')
      expect(resolveBody3DFocusGroup('all')).assertEqual('all')
      expect(resolveBody3DFocusGroup('')).assertEqual('all')
    })
  })
}
