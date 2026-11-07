import { describe, it, expect } from '@ohos/hypium'
import { MusicVoiceMixer } from '../../../../main/ets/utils/MusicVoiceMixer'

function hasNonZero(out: Float32Array): boolean {
  for (let i = 0; i < out.length; i++) {
    if (out[i] !== 0) {
      return true
    }
  }
  return false
}

export default function musicVoiceMixerTest() {
  describe('MusicVoiceMixer', () => {
    it('renders_scheduled_note', 0, () => {
      const mixer = new MusicVoiceMixer()
      mixer.scheduleNote(440, 'piano', 0)
      const out = new Float32Array(480)
      mixer.fillBuffer(out, 48000)
      expect(hasNonZero(out)).assertTrue()
    })

    it('keeps_silence_before_future_note', 0, () => {
      const mixer = new MusicVoiceMixer()
      mixer.scheduleNote(440, 'piano', 4800)
      const out = new Float32Array(480)
      mixer.fillBuffer(out, 48000)
      expect(hasNonZero(out)).assertFalse()
    })

    it('caps_active_voices_at_eight', 0, () => {
      const mixer = new MusicVoiceMixer()
      for (let i = 0; i < 12; i++) {
        mixer.scheduleNote(200 + i * 20, 'piano', 0)
      }
      expect(mixer.getActiveVoiceCount() <= 8).assertTrue()
    })

    it('clear_drops_all_voices', 0, () => {
      const mixer = new MusicVoiceMixer()
      mixer.scheduleNote(440, 'piano', 0)
      const out = new Float32Array(480)
      mixer.fillBuffer(out, 48000)
      mixer.clear()
      expect(mixer.getActiveVoiceCount()).assertEqual(0)
      expect(hasNonZero(out)).assertTrue()
      const silent = new Float32Array(480)
      mixer.fillBuffer(silent, 48000)
      expect(hasNonZero(silent)).assertFalse()
    })

    it('schedules_sequence_with_spacing', 0, () => {
      const mixer = new MusicVoiceMixer()
      mixer.scheduleSequence([261.63, 329.63, 392.0], 'xylophone', 2400, 480)
      expect(mixer.getActiveVoiceCount()).assertEqual(3)
    })
  })
}
