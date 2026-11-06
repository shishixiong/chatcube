import { describe, it, expect } from '@ohos/hypium'
import { FARM_OBJECT_IDS, resolveFarmEnglishView, validateFarmEnglishArgs } from '../../../../main/ets/utils/FarmEnglishValidation'

/**
 * FarmEnglishValidation 单元测试（farm_english 3D 阳光农场英语探索, 2026-11-06）
 *
 * 校验纯逻辑层不依赖 rawfile / Web 容器，可直接跑。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */

export default function farmEnglishValidationTest() {
  describe('validateFarmEnglishArgs', () => {
    it('accepts minimal valid args', 0, () => {
      const r = validateFarmEnglishArgs('{"skill_key":"english_vocab"}')
      expect(r.ok).assertTrue()
      expect(r.focus).assertEqual('overview')
      expect(r.words.length).assertEqual(0)
    })

    it('accepts every valid focus', 0, () => {
      const focuses = ['overview', 'farmyard_zone', 'field_zone', 'pasture_zone', 'orchard_pond_zone']
      for (let i = 0; i < focuses.length; i++) {
        const r = validateFarmEnglishArgs('{"skill_key":"english_vocab","focus":"' + focuses[i] + '"}')
        expect(r.ok).assertTrue()
        expect(r.focus).assertEqual(focuses[i])
      }
    })

    it('normalizes all and empty focus to overview', 0, () => {
      expect(validateFarmEnglishArgs('{"skill_key":"english_vocab","focus":"all"}').focus).assertEqual('overview')
      expect(validateFarmEnglishArgs('{"skill_key":"english_vocab","focus":""}').focus).assertEqual('overview')
    })

    it('rejects unknown focus, wrong skill_key and malformed json', 0, () => {
      expect(validateFarmEnglishArgs('{"skill_key":"english_vocab","focus":"beach_zone"}').ok).assertFalse()
      expect(validateFarmEnglishArgs('{"skill_key":"general_social"}').ok).assertFalse()
      expect(validateFarmEnglishArgs('not json').ok).assertFalse()
    })

    it('rejects non-object json documents', 0, () => {
      const docs = ['null', '[]', '123', '"farm"', 'true']
      for (let i = 0; i < docs.length; i++) {
        const r = validateFarmEnglishArgs(docs[i])
        expect(r.ok).assertFalse()
        expect(r.error.length > 0).assertTrue()
      }
    })

    it('rejects unknown word id and more than 8 words', 0, () => {
      const unknown = validateFarmEnglishArgs('{"skill_key":"english_vocab","words":["cow","spaceship"]}')
      expect(unknown.ok).assertFalse()
      expect(unknown.error.indexOf('spaceship') >= 0).assertTrue()
      const nine = FARM_OBJECT_IDS.slice(0, 9)
      const r = validateFarmEnglishArgs('{"skill_key":"english_vocab","words":["' + nine.join('","') + '"]}')
      expect(r.ok).assertFalse()
    })

    it('dedupes and rejects non-strings', 0, () => {
      const r = validateFarmEnglishArgs('{"skill_key":"english_vocab","words":["cow","cow","wheat"]}')
      expect(r.ok).assertTrue()
      expect(r.words.length).assertEqual(2)
      expect(r.words[0]).assertEqual('cow')
      expect(validateFarmEnglishArgs('{"skill_key":"english_vocab","words":[1,2]}').ok).assertFalse()
    })

    it('covers 50 unique farm objects', 0, () => {
      expect(FARM_OBJECT_IDS.length).assertEqual(50)
      for (let i = 0; i < FARM_OBJECT_IDS.length; i++) {
        expect(FARM_OBJECT_IDS.indexOf(FARM_OBJECT_IDS[i])).assertEqual(i)
      }
    })

    it('includes every category sample', 0, () => {
      const samples = [
        // places 10
        'farmhouse', 'barn', 'chicken_coop', 'stable', 'silo', 'windmill', 'greenhouse', 'well', 'gate', 'fence',
        // animals 14
        'cow', 'pig', 'sheep', 'horse', 'goat', 'chicken', 'rooster', 'duck', 'goose', 'rabbit', 'cat', 'dog', 'bee', 'bird',
        // crops 10
        'wheat', 'corn', 'potato', 'carrot', 'tomato', 'pumpkin', 'apple', 'strawberry', 'sunflower', 'hay',
        // machines 8
        'tractor', 'trailer', 'plow', 'harvester', 'wheelbarrow', 'watering_can', 'shovel', 'pitchfork',
        // nature 5
        'tree', 'grass', 'flower', 'pond', 'hill',
        // people 3
        'farmer', 'child', 'grandma'
      ]
      expect(samples.length).assertEqual(50)
      for (let i = 0; i < samples.length; i++) {
        expect(FARM_OBJECT_IDS.indexOf(samples[i]) >= 0).assertTrue()
      }
    })
  })

  describe('resolveFarmEnglishView', () => {
    it('keeps dedicated zones and falls back to overview', 0, () => {
      expect(resolveFarmEnglishView('farmyard_zone')).assertEqual('farmyard_zone')
      expect(resolveFarmEnglishView('field_zone')).assertEqual('field_zone')
      expect(resolveFarmEnglishView('pasture_zone')).assertEqual('pasture_zone')
      expect(resolveFarmEnglishView('orchard_pond_zone')).assertEqual('orchard_pond_zone')
      expect(resolveFarmEnglishView('overview')).assertEqual('overview')
      expect(resolveFarmEnglishView('all')).assertEqual('overview')
      expect(resolveFarmEnglishView('')).assertEqual('overview')
      expect(resolveFarmEnglishView('unknown')).assertEqual('overview')
    })
  })
}
