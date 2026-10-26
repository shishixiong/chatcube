import { describe, it, expect } from '@ohos/hypium'
import { ROOM_OBJECT_IDS, validateRoomEnglishArgs } from '../../../../main/ets/utils/RoomEnglishValidation'

/**
 * RoomEnglishValidation 单元测试（room_english 客餐厅 + 厨房 3D 英语探索, spec 2026-10-24 §5）
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
      const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","focus":"balcony"}')
      expect(r.ok).assertFalse()
    })

    it('accepts kitchen focus', 0, () => {
      const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","focus":"kitchen","words":["fridge","stove"]}')
      expect(r.ok).assertTrue()
      expect(r.focus).assertEqual('kitchen')
      expect(r.words.length).assertEqual(2)
      expect(r.words[0]).assertEqual('fridge')
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

    it('covers 61 room objects', 0, () => {
      expect(ROOM_OBJECT_IDS.length).assertEqual(61)
    })

    it('includes every kitchen word', 0, () => {
      const kitchen = ['fridge', 'stove', 'oven', 'sink', 'pot', 'pan',
        'toaster', 'microwave', 'dishwasher', 'cabinet', 'knife', 'stool']
      for (let i = 0; i < kitchen.length; i++) {
        expect(ROOM_OBJECT_IDS.indexOf(kitchen[i]) >= 0).assertTrue()
      }
    })

    it('includes every bedroom word', 0, () => {
      const bedrooms = ['bed', 'desk', 'chair', 'wardrobe', 'toy_box', 'round_rug',
        'bookcase', 'shelf', 'basket', 'poster', 'blanket', 'toy_car',
        'double_bed', 'nightstand', 'lamp', 'pillow', 'closet', 'dresser',
        'mirror', 'stool_master', 'bench', 'rug_master', 'heater', 'photo_frame']
      for (let i = 0; i < bedrooms.length; i++) {
        expect(ROOM_OBJECT_IDS.indexOf(bedrooms[i]) >= 0).assertTrue()
      }
    })

    it('accepts bedroom focus and switches room ids', 0, () => {
      const child = validateRoomEnglishArgs('{"skill_key":"english_vocab","focus":"child","words":["bed","toy_box"]}')
      expect(child.ok).assertTrue()
      expect(child.focus).assertEqual('child')
      const master = validateRoomEnglishArgs('{"skill_key":"english_vocab","focus":"master","words":["double_bed"]}')
      expect(master.ok).assertTrue()
      expect(master.focus).assertEqual('master')
    })
  })
}
