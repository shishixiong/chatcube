import { describe, it, expect } from '@ohos/hypium'
import { CITY_OBJECT_IDS, resolveCityEnglishView, validateCityEnglishArgs } from '../../../../main/ets/utils/CityEnglishValidation'

/**
 * CityEnglishValidation 单元测试（city_english 3D 小城市英语探索, 2026-11-01）
 *
 * 校验纯逻辑层不依赖 rawfile / Web 容器，可直接跑。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */

export default function cityEnglishValidationTest() {
  describe('validateCityEnglishArgs', () => {
    it('accepts minimal valid args', 0, () => {
      const r = validateCityEnglishArgs('{"skill_key":"english_vocab"}')
      expect(r.ok).assertTrue()
      expect(r.focus).assertEqual('overview')
      expect(r.words.length).assertEqual(0)
    })

    it('accepts focus and words', 0, () => {
      const r = validateCityEnglishArgs('{"skill_key":"english_vocab","focus":"school_zone","words":["school","teacher"]}')
      expect(r.ok).assertTrue()
      expect(r.focus).assertEqual('school_zone')
      expect(r.words.length).assertEqual(2)
      expect(r.words[0]).assertEqual('school')
    })

    it('rejects malformed json', 0, () => {
      const r = validateCityEnglishArgs('not json')
      expect(r.ok).assertFalse()
      expect(r.error.length > 0).assertTrue()
    })

    it('rejects wrong skill_key', 0, () => {
      const r = validateCityEnglishArgs('{"skill_key":"general_social"}')
      expect(r.ok).assertFalse()
    })

    it('rejects a non-string skill_key', 0, () => {
      const r = validateCityEnglishArgs('{"skill_key":1}')
      expect(r.ok).assertFalse()
    })

    it('rejects unknown focus', 0, () => {
      const r = validateCityEnglishArgs('{"skill_key":"english_vocab","focus":"beach_zone"}')
      expect(r.ok).assertFalse()
    })

    it('normalizes all and empty focus to overview', 0, () => {
      const all = validateCityEnglishArgs('{"skill_key":"english_vocab","focus":"all"}')
      expect(all.ok).assertTrue()
      expect(all.focus).assertEqual('overview')
      const empty = validateCityEnglishArgs('{"skill_key":"english_vocab","focus":""}')
      expect(empty.ok).assertTrue()
      expect(empty.focus).assertEqual('overview')
    })

    it('accepts every valid focus', 0, () => {
      const focuses = ['overview', 'main_street', 'school_zone', 'park_zone', 'hospital_zone']
      for (let i = 0; i < focuses.length; i++) {
        const r = validateCityEnglishArgs('{"skill_key":"english_vocab","focus":"' + focuses[i] + '"}')
        expect(r.ok).assertTrue()
        expect(r.focus).assertEqual(focuses[i])
      }
    })

    it('rejects unknown word id', 0, () => {
      const r = validateCityEnglishArgs('{"skill_key":"english_vocab","words":["hospital","spaceship"]}')
      expect(r.ok).assertFalse()
      expect(r.error.indexOf('spaceship') >= 0).assertTrue()
    })

    it('rejects more than 8 words', 0, () => {
      const nine = CITY_OBJECT_IDS.slice(0, 9)
      const args = '{"skill_key":"english_vocab","words":["' + nine.join('","') + '"]}'
      const r = validateCityEnglishArgs(args)
      expect(r.ok).assertFalse()
    })

    it('dedupes repeated words', 0, () => {
      const r = validateCityEnglishArgs('{"skill_key":"english_vocab","words":["park","park","tree"]}')
      expect(r.ok).assertTrue()
      expect(r.words.length).assertEqual(2)
    })

    it('rejects non-string entries', 0, () => {
      const r = validateCityEnglishArgs('{"skill_key":"english_vocab","words":[1,2]}')
      expect(r.ok).assertFalse()
    })

    it('covers 50 city objects', 0, () => {
      expect(CITY_OBJECT_IDS.length).assertEqual(50)
    })

    it('includes every category sample', 0, () => {
      const samples = [
        // places 12
        'hospital', 'school', 'park', 'supermarket', 'bus_stop', 'police_station',
        'fire_station', 'library', 'bakery', 'cafe', 'post_office', 'cinema',
        // transport 10
        'bus', 'car', 'taxi', 'bicycle', 'ambulance', 'fire_truck', 'school_bus',
        'truck', 'scooter', 'boat',
        // street 9
        'road', 'crosswalk', 'traffic_light', 'streetlight', 'bench', 'trash_can',
        'mailbox', 'bridge', 'fountain',
        // people 8
        'teacher', 'doctor', 'nurse', 'police_officer', 'firefighter', 'driver',
        'baker', 'student',
        // nature 8
        'tree', 'flower', 'grass', 'pond', 'swing', 'slide', 'seesaw', 'kite',
        // animals 3
        'duck', 'dog', 'bird'
      ]
      for (let i = 0; i < samples.length; i++) {
        expect(CITY_OBJECT_IDS.indexOf(samples[i]) >= 0).assertTrue()
      }
      expect(samples.length).assertEqual(50)
    })

    it('has no duplicate ids', 0, () => {
      for (let i = 0; i < CITY_OBJECT_IDS.length; i++) {
        expect(CITY_OBJECT_IDS.indexOf(CITY_OBJECT_IDS[i])).assertEqual(i)
      }
    })

    it('accepts hospital_zone focus with words', 0, () => {
      const r = validateCityEnglishArgs('{"skill_key":"english_vocab","focus":"hospital_zone","words":["hospital","doctor","nurse"]}')
      expect(r.ok).assertTrue()
      expect(r.focus).assertEqual('hospital_zone')
      expect(r.words.length).assertEqual(3)
    })
  })

  describe('resolveCityEnglishView', () => {
    it('keeps dedicated zones as-is', 0, () => {
      expect(resolveCityEnglishView('main_street')).assertEqual('main_street')
      expect(resolveCityEnglishView('school_zone')).assertEqual('school_zone')
      expect(resolveCityEnglishView('park_zone')).assertEqual('park_zone')
      expect(resolveCityEnglishView('hospital_zone')).assertEqual('hospital_zone')
    })

    it('falls back to the whole-city overview', 0, () => {
      expect(resolveCityEnglishView('overview')).assertEqual('overview')
      expect(resolveCityEnglishView('all')).assertEqual('overview')
      expect(resolveCityEnglishView('')).assertEqual('overview')
      expect(resolveCityEnglishView('unknown')).assertEqual('overview')
    })
  })
}
