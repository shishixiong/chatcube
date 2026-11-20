import { describe, it, expect } from '@ohos/hypium'
import { AIRPORT_WORD_IDS, resolveAirportEnglishView, validateAirportEnglishArgs } from '../../../../main/ets/utils/AirportEnglishValidation'

/**
 * AirportEnglishValidation 单元测试（airport_english 3D 机场英语探索, 2026-11-20）
 *
 * 纯逻辑层不依赖 rawfile / Web 容器，可直接跑。
 * CLI: .superpowers/harness/run-test.sh <this file> entry/src/main/ets/utils/AirportEnglishValidation.ets
 */

export default function airportEnglishValidationTest() {
  describe('validateAirportEnglishArgs', () => {
    it('accepts minimal valid args', 0, () => {
      const r = validateAirportEnglishArgs('{"skill_key":"english_vocab"}')
      expect(r.ok).assertTrue()
      expect(r.focus).assertEqual('overview')
      expect(r.words.length).assertEqual(0)
    })

    it('normalizes focus all to overview', 0, () => {
      const r = validateAirportEnglishArgs('{"skill_key":"english_vocab","focus":"all"}')
      expect(r.ok).assertTrue()
      expect(r.focus).assertEqual('overview')
    })

    it('rejects invalid focus', 0, () => {
      const r = validateAirportEnglishArgs('{"skill_key":"english_vocab","focus":"air_side"}')
      expect(r.ok).assertFalse()
      expect(r.error.length > 0).assertTrue()
    })

    it('dedupes repeated words', 0, () => {
      const r = validateAirportEnglishArgs('{"skill_key":"english_vocab","words":["runway","runway","pilot"]}')
      expect(r.ok).assertTrue()
      expect(r.words.length).assertEqual(2)
      expect(r.words[0]).assertEqual('runway')
      expect(r.words[1]).assertEqual('pilot')
    })

    it('rejects more than 8 words', 0, () => {
      const r = validateAirportEnglishArgs(
        '{"skill_key":"english_vocab","words":["runway","taxiway","apron","pilot","radar","windsock","beacon","papi","sign"]}')
      expect(r.ok).assertFalse()
    })

    it('rejects an unknown word id', 0, () => {
      const r = validateAirportEnglishArgs('{"skill_key":"english_vocab","words":["unicorn"]}')
      expect(r.ok).assertFalse()
      expect(r.error.indexOf('unicorn') >= 0).assertTrue()
    })

    it('rejects non-object JSON documents', 0, () => {
      const r = validateAirportEnglishArgs('null')
      expect(r.ok).assertFalse()
    })

    it('trims skill_key and rejects a different dimension', 0, () => {
      const ok = validateAirportEnglishArgs('{"skill_key":" english_vocab "}')
      expect(ok.ok).assertTrue()
      const bad = validateAirportEnglishArgs('{"skill_key":"math_counting"}')
      expect(bad.ok).assertFalse()
    })

    it('keeps the 50-word catalog unique', 0, () => {
      expect(AIRPORT_WORD_IDS.length).assertEqual(50)
      const seen: string[] = []
      for (let i = 0; i < AIRPORT_WORD_IDS.length; i++) {
        const id = AIRPORT_WORD_IDS[i]
        expect(seen.indexOf(id) < 0).assertTrue()
        seen.push(id)
      }
    })

    it('resolves camera views', 0, () => {
      expect(resolveAirportEnglishView('apron_zone')).assertEqual('apron_zone')
      expect(resolveAirportEnglishView('')).assertEqual('overview')
      expect(resolveAirportEnglishView('all')).assertEqual('overview')
      expect(resolveAirportEnglishView('nonsense')).assertEqual('overview')
    })
  })
}
