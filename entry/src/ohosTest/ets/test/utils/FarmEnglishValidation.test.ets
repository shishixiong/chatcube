import { describe, it, expect } from '@ohos/hypium'
import {
  FARM_WORD_IDS,
  resolveFarmEnglishView,
  resolveFarmTimeOfDay,
  resolveFarmWeather,
  validateFarmEnglishArgs
} from '../../../../main/ets/utils/FarmEnglishValidation'

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
      const nine = FARM_WORD_IDS.slice(0, 9)
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

    it('keeps the word-id table unique and growable', 0, () => {
      expect(FARM_WORD_IDS.indexOf('chick') >= 0).assertTrue()
      for (let i = 0; i < FARM_WORD_IDS.length; i++) {
        expect(FARM_WORD_IDS.indexOf(FARM_WORD_IDS[i])).assertEqual(i)
      }
    })

    it('accepts chick as a word id', 0, () => {
      const r = validateFarmEnglishArgs('{"skill_key":"english_vocab","words":["chick","chicken"]}')
      expect(r.ok).assertTrue()
      expect(r.words.length).assertEqual(2)
    })

    it('includes every category sample', 0, () => {
      const samples = [
        // places 11
        'farmhouse', 'barn', 'chicken_coop', 'sheep_pen', 'stable', 'silo', 'windmill', 'greenhouse', 'well', 'gate', 'fence',
        // animals 15
        'cow', 'pig', 'sheep', 'horse', 'goat', 'chicken', 'rooster', 'chick', 'duck', 'goose', 'rabbit', 'cat', 'dog', 'bee', 'bird',
        // crops 10
        'wheat', 'corn', 'potato', 'carrot', 'tomato', 'pumpkin', 'apple', 'strawberry', 'sunflower', 'hay',
        // machines 8
        'tractor', 'trailer', 'plow', 'harvester', 'wheelbarrow', 'watering_can', 'shovel', 'pitchfork',
        // nature 5
        'tree', 'grass', 'flower', 'pond', 'hill',
        // people 3
        'farmer', 'child', 'grandma'
      ]
      for (let i = 0; i < samples.length; i++) {
        expect(FARM_WORD_IDS.indexOf(samples[i]) >= 0).assertTrue()
      }
    })
    it('accepts valid time_of_day and weather', 0, () => {
      const night = validateFarmEnglishArgs('{"skill_key":"english_vocab","time_of_day":"night","weather":"rainy"}')
      expect(night.ok).assertTrue()
      expect(night.timeOfDay).assertEqual('night')
      expect(night.weather).assertEqual('rainy')
      const day = validateFarmEnglishArgs('{"skill_key":"english_vocab","time_of_day":"day","weather":"sunny"}')
      expect(day.ok).assertTrue()
      expect(day.timeOfDay).assertEqual('day')
      expect(day.weather).assertEqual('sunny')
    })

    it('defaults scene fields and rejects illegal values', 0, () => {
      const plain = validateFarmEnglishArgs('{"skill_key":"english_vocab"}')
      expect(plain.ok).assertTrue()
      expect(plain.timeOfDay).assertEqual('')
      expect(plain.weather).assertEqual('')
      const bads = [
        '{"skill_key":"english_vocab","time_of_day":"dusk"}',
        '{"skill_key":"english_vocab","time_of_day":"DAY"}',
        '{"skill_key":"english_vocab","time_of_day":1}',
        '{"skill_key":"english_vocab","weather":"rain"}',
        '{"skill_key":"english_vocab","weather":"Rainy"}',
        '{"skill_key":"english_vocab","weather":true}'
      ]
      for (let i = 0; i < bads.length; i++) {
        expect(validateFarmEnglishArgs(bads[i]).ok).assertFalse()
      }
    })
  })

  describe('resolveFarmScene', () => {
    it('resolves explicit and device-hour time of day', 0, () => {
      expect(resolveFarmTimeOfDay('night', 12)).assertEqual('night')
      expect(resolveFarmTimeOfDay('day', 23)).assertEqual('day')
      expect(resolveFarmTimeOfDay('', 5)).assertEqual('night')
      expect(resolveFarmTimeOfDay('', 6)).assertEqual('day')
      expect(resolveFarmTimeOfDay('', 12)).assertEqual('day')
      expect(resolveFarmTimeOfDay('', 17)).assertEqual('day')
      expect(resolveFarmTimeOfDay('', 18)).assertEqual('night')
      expect(resolveFarmTimeOfDay('', 23)).assertEqual('night')
    })

    it('defaults weather to sunny and honors rainy', 0, () => {
      expect(resolveFarmWeather('')).assertEqual('sunny')
      expect(resolveFarmWeather('sunny')).assertEqual('sunny')
      expect(resolveFarmWeather('rainy')).assertEqual('rainy')
      expect(resolveFarmWeather('RAINY')).assertEqual('sunny')
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
