import { describe, it, expect } from '@ohos/hypium'
import { ROOM_OBJECT_IDS, validateRoomEnglishArgs } from '../../../../main/ets/utils/RoomEnglishValidation'

/**
 * RoomEnglishValidation 单元测试（room_english 客餐厅 3D 英语探索, spec 2026-10-24 §5）
 *
 * 校验纯逻辑层不依赖 rawfile / Web 容器，可直接跑。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */

export default function roomEnglishValidationTest() {
  describe('validateRoomEnglishArgs', () => {
    it('accepts minimal valid args', 0, () => {
      const r = validateRoomEnglishArgs('{"skill_key":"english_vocab"}')
      expect(r.ok).assertTrue()
      expect(r.focus).assertEqual('all')
      expect(r.words.length).assertEqual(0)
    })

    it('accepts focus and words', 0, () => {
      const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","focus":"living","words":["sofa","tv"]}')
      expect(r.ok).assertTrue()
      expect(r.focus).assertEqual('living')
      expect(r.words.length).assertEqual(2)
      expect(r.words[0]).assertEqual('sofa')
    })

    it('rejects malformed json', 0, () => {
      const r = validateRoomEnglishArgs('not json')
      expect(r.ok).assertFalse()
      expect(r.error.length > 0).assertTrue()
    })

    it('rejects wrong skill_key', 0, () => {
      const r = validateRoomEnglishArgs('{"skill_key":"general_social"}')
      expect(r.ok).assertFalse()
    })

    it('rejects unknown focus', 0, () => {
      const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","focus":"kitchen"}')
      expect(r.ok).assertFalse()
    })

    it('rejects unknown word id', 0, () => {
      const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","words":["sofa","bathtub"]}')
      expect(r.ok).assertFalse()
      expect(r.error.indexOf('bathtub') >= 0).assertTrue()
    })

    it('rejects more than 8 words', 0, () => {
      const nine = ROOM_OBJECT_IDS.slice(0, 9)
      const args = '{"skill_key":"english_vocab","words":["' + nine.join('","') + '"]}'
      const r = validateRoomEnglishArgs(args)
      expect(r.ok).assertFalse()
    })

    it('dedupes repeated words', 0, () => {
      const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","words":["sofa","sofa","rug"]}')
      expect(r.ok).assertTrue()
      expect(r.words.length).assertEqual(2)
    })

    it('rejects non-string entries', 0, () => {
      const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","words":[1,2]}')
      expect(r.ok).assertFalse()
    })

    it('covers 25 room objects', 0, () => {
      expect(ROOM_OBJECT_IDS.length).assertEqual(25)
    })
  })
}
