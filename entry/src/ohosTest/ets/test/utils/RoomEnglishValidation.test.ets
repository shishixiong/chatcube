import { describe, it, expect } from '@ohos/hypium'
import { ROOM_OBJECT_IDS, resolveRoomEnglishArea, resolveRoomEnglishView, validateRoomEnglishArgs } from '../../../../main/ets/utils/RoomEnglishValidation'

/**
 * RoomEnglishValidation 单元测试（room_english 全屋 + 四间房 3D 英语探索, spec 2026-10-29 §5）
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
      const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","focus":"garden"}')
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

    it('covers 76 room objects', 0, () => {
      expect(ROOM_OBJECT_IDS.length).assertEqual(76)
    })

    it('includes every balcony word', 0, () => {
      const balcony = ['washing_machine', 'dryer', 'laundry_basket', 'drying_rack', 'clothespin',
        'laundry_sink', 'storage_cabinet', 'broom', 'mop', 'bucket',
        'balcony_plant', 'flower_pot', 'watering_can', 'railing', 'folding_stool']
      for (let i = 0; i < balcony.length; i++) {
        expect(ROOM_OBJECT_IDS.indexOf(balcony[i]) >= 0).assertTrue()
      }
    })

    it('accepts balcony focus', 0, () => {
      const r = validateRoomEnglishArgs('{"skill_key":"english_vocab","focus":"balcony","words":["washing_machine","railing"]}')
      expect(r.ok).assertTrue()
      expect(r.focus).assertEqual('balcony')
      expect(r.words.length).assertEqual(2)
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

  describe('resolveRoomEnglishView', () => {
    it('maps living areas to the main room', 0, () => {
      expect(resolveRoomEnglishView('living')).assertEqual('main')
      expect(resolveRoomEnglishView('dining')).assertEqual('main')
      expect(resolveRoomEnglishView('kitchen')).assertEqual('main')
    })

    it('keeps dedicated rooms as-is', 0, () => {
      expect(resolveRoomEnglishView('child')).assertEqual('child')
      expect(resolveRoomEnglishView('master')).assertEqual('master')
      expect(resolveRoomEnglishView('balcony')).assertEqual('balcony')
    })

    it('falls back to the whole-home overview', 0, () => {
      expect(resolveRoomEnglishView('all')).assertEqual('overview')
      expect(resolveRoomEnglishView('')).assertEqual('overview')
    })
  })

  describe('resolveRoomEnglishArea', () => {
    it('maps the three living areas to their camera center', 0, () => {
      expect(resolveRoomEnglishArea('living')).assertEqual('living')
      expect(resolveRoomEnglishArea('dining')).assertEqual('dining')
      expect(resolveRoomEnglishArea('kitchen')).assertEqual('kitchen')
      expect(resolveRoomEnglishArea('  kitchen  ')).assertEqual('kitchen')
    })

    it('returns empty for dedicated rooms and all', 0, () => {
      expect(resolveRoomEnglishArea('child')).assertEqual('')
      expect(resolveRoomEnglishArea('master')).assertEqual('')
      expect(resolveRoomEnglishArea('balcony')).assertEqual('')
      expect(resolveRoomEnglishArea('all')).assertEqual('')
      expect(resolveRoomEnglishArea('')).assertEqual('')
    })
  })
}
