import { describe, it, expect } from '@ohos/hypium'
import { buildTimbreVoices, renderVoiceInto, VoiceSpec } from '../../../../main/ets/utils/MusicToneSynth'

function peak(out: Float32Array): number {
  let max = 0
  for (let i = 0; i < out.length; i++) {
    const v = Math.abs(out[i])
    if (v > max) {
      max = v
    }
  }
  return max
}

export default function musicToneSynthTest() {
  describe('MusicToneSynth', () => {
    it('timbre_voice_counts', 0, () => {
      expect(buildTimbreVoices('piano', 440).length).assertEqual(3)
      expect(buildTimbreVoices('xylophone', 440).length).assertEqual(3)
      expect(buildTimbreVoices('musicbox', 440).length).assertEqual(4)
    })

    it('harmonics_scale_with_base_frequency', 0, () => {
      const voices = buildTimbreVoices('musicbox', 440)
      expect(Math.abs(voices[0].freq - 440) < 0.01).assertTrue()
      expect(Math.abs(voices[1].freq - 440 * 2.76) < 0.01).assertTrue()
    })

    it('renders_non_silent_audio_without_clipping', 0, () => {
      const out = new Float32Array(48000)
      const voices = buildTimbreVoices('piano', 440)
      for (let i = 0; i < voices.length; i++) {
        renderVoiceInto(out, 0, voices[i], 48000)
      }
      const p = peak(out)
      expect(p > 0.05).assertTrue()
      expect(p < 1.0).assertTrue()
      for (let i = 0; i < out.length; i++) {
        expect(Number.isNaN(out[i])).assertFalse()
      }
    })

    it('handles_negative_start_offset', 0, () => {
      const out = new Float32Array(480)
      const spec: VoiceSpec = { freq: 440, gain: 0.2, durationSec: 1, attackSec: 0.005, wave: 'sine' }
      renderVoiceInto(out, -240, spec, 48000)
      expect(peak(out) > 0).assertTrue()
    })
  })
}
