import { describe, it, expect } from '@ohos/hypium'
import { validateMusicEarArgs } from '../../../../main/ets/utils/MusicEarValidation'
import { isMusicEarFunctionName, MUSIC_EAR_TOOL_ID } from '../../../../main/ets/utils/SearchToolIdentityUtils'

export default function musicEarValidationTest() {
  describe('MusicEarValidation', () => {
    it('accepts_valid_args', 0, () => {
      const r = validateMusicEarArgs('{"drill":"echo","difficulty":2}')
      expect(r.ok).assertTrue()
      expect(r.drill).assertEqual('echo')
      expect(r.difficulty).assertEqual(2)
    })

    it('normalizes_aliases', 0, () => {
      expect(validateMusicEarArgs('{"drill":"high-low","difficulty":1}').drill).assertEqual('high_low')
      expect(validateMusicEarArgs('{"drill":"song","difficulty":3}').drill).assertEqual('guess_song')
    })

    it('rejects_bad_drill', 0, () => {
      const r = validateMusicEarArgs('{"drill":"piano","difficulty":1}')
      expect(r.ok).assertFalse()
      expect(r.error.length > 0).assertTrue()
    })

    it('rejects_out_of_range_difficulty', 0, () => {
      expect(validateMusicEarArgs('{"drill":"echo","difficulty":0}').ok).assertFalse()
      expect(validateMusicEarArgs('{"drill":"echo","difficulty":4}').ok).assertFalse()
      expect(validateMusicEarArgs('{"drill":"echo","difficulty":1.5}').ok).assertFalse()
    })

    it('rejects_malformed_json', 0, () => {
      expect(validateMusicEarArgs('not json').ok).assertFalse()
    })

    it('identifies_music_ear_names', 0, () => {
      expect(MUSIC_EAR_TOOL_ID).assertEqual('music_ear')
      expect(isMusicEarFunctionName('music_ear')).assertTrue()
      expect(isMusicEarFunctionName('music-ear')).assertTrue()
      expect(isMusicEarFunctionName('ear_training')).assertTrue()
      expect(isMusicEarFunctionName('math_quiz')).assertFalse()
    })
  })
}
