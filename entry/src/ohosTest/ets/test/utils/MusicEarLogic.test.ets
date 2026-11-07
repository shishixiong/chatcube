import { describe, it, expect } from '@ohos/hypium'
import {
  SeededRng,
  buildHighLowQuestion,
  buildEchoSequence,
  buildGuessSongQuestion,
  evaluateEcho,
  scoreRound,
  computeMusicEarStars,
  pickBestRound,
  noteProfileDistance,
  RoundSnapshot
} from '../../../../main/ets/utils/MusicEarLogic'
import { MUSIC_NOTE_ORDER, MUSIC_SONGS, MusicNote } from '../../../../main/ets/utils/MusicEarData'
import { getActivityMeta } from '../../../../main/ets/models/StarEventModels'

function indexOf(note: string): number {
  return MUSIC_NOTE_ORDER.indexOf(note as MusicNote)
}

function notes(values: string[]): MusicNote[] {
  const out: MusicNote[] = []
  for (let i = 0; i < values.length; i++) {
    out.push(values[i] as MusicNote)
  }
  return out
}

export default function musicEarLogicTest() {
  describe('MusicEarLogic', () => {
    it('high_low_difficulty_1_uses_wide_interval', 0, () => {
      for (let seed = 1; seed <= 30; seed++) {
        const q = buildHighLowQuestion(1, new SeededRng(seed))
        expect(Math.abs(indexOf(q.first) - indexOf(q.second)) >= 3).assertTrue()
        expect(q.answer === 'same').assertFalse()
      }
    })

    it('high_low_difficulty_3_can_be_same_note', 0, () => {
      let sawSame = false
      for (let seed = 1; seed <= 200; seed++) {
        const q = buildHighLowQuestion(3, new SeededRng(seed))
        const distance = Math.abs(indexOf(q.first) - indexOf(q.second))
        if (q.answer === 'same') {
          sawSame = true
          expect(distance).assertEqual(0)
        } else {
          expect(distance).assertEqual(1)
        }
      }
      expect(sawSame).assertTrue()
    })

    it('high_low_round_has_no_repeated_pair', 0, () => {
      const used: string[] = []
      for (let i = 0; i < 5; i++) {
        const q = buildHighLowQuestion(1, new SeededRng(100 + i), used)
        expect(used.indexOf(q.pairKey)).assertEqual(-1)
        used.push(q.pairKey)
      }
    })

    it('echo_lengths_follow_difficulty', 0, () => {
      expect(buildEchoSequence(1, new SeededRng(7)).length).assertEqual(3)
      expect(buildEchoSequence(2, new SeededRng(7)).length).assertEqual(4)
      expect(buildEchoSequence(3, new SeededRng(7)).length).assertEqual(5)
    })

    it('guess_song_options_are_unique_and_contain_answer', 0, () => {
      for (let difficulty = 1; difficulty <= 3; difficulty++) {
        const q = buildGuessSongQuestion(difficulty, new SeededRng(11 + difficulty), [])
        expect(q.optionSongKeys.length).assertEqual(difficulty + 2)
        for (let i = 0; i < q.optionSongKeys.length; i++) {
          expect(q.optionSongKeys.indexOf(q.optionSongKeys[i])).assertEqual(i)
        }
        expect(q.optionSongKeys.indexOf(q.answerSongKey) >= 0).assertTrue()
      }
    })

    it('guess_song_avoids_used_songs', 0, () => {
      const used: string[] = ['twinkle', 'tigers']
      const q = buildGuessSongQuestion(1, new SeededRng(3), used)
      expect(used.indexOf(q.answerSongKey)).assertEqual(-1)
    })

    it('evaluate_echo_reports_first_wrong_index', 0, () => {
      const result = evaluateEcho(notes(['C', 'D', 'E']), notes(['C', 'E', 'E']))
      expect(result.correct).assertFalse()
      expect(result.firstWrongIndex).assertEqual(1)
      expect(evaluateEcho(notes(['C', 'D']), notes(['C', 'D'])).correct).assertTrue()
    })

    it('note_profile_distance_rewards_similar_contours', 0, () => {
      const song = MUSIC_SONGS[0]
      expect(noteProfileDistance(song.notes, song.notes)).assertEqual(0)
      expect(noteProfileDistance(notes(['C', 'C']), notes(['A', 'A']))).assertEqual(10)
    })

    it('score_round_counts_eventual_and_first_try', 0, () => {
      const score = scoreRound([true, false, true, true, false], [true, true, true, true, false])
      expect(score.correct).assertEqual(4)
      expect(score.firstTryCorrect).assertEqual(3)
    })

    it('star_rules_follow_difficulty_and_accuracy', 0, () => {
      expect(computeMusicEarStars(1, 5, 5)).assertEqual(2)
      expect(computeMusicEarStars(2, 5, 5)).assertEqual(3)
      expect(computeMusicEarStars(3, 5, 4)).assertEqual(3)
      expect(computeMusicEarStars(2, 5, 3)).assertEqual(1)
      expect(computeMusicEarStars(2, 0, 0)).assertEqual(0)
    })

    it('pick_best_round_prefers_highest_first_try', 0, () => {
      const a: RoundSnapshot = {
        drill: 'echo', difficulty: 2, total: 5, correct: 5, firstTryCorrect: 3, songs: []
      }
      const b: RoundSnapshot = {
        drill: 'echo', difficulty: 2, total: 5, correct: 5, firstTryCorrect: 5, songs: []
      }
      expect(pickBestRound([a, b])?.firstTryCorrect).assertEqual(5)
      expect(pickBestRound([])).assertNull()
    })

    it('song_table_is_complete', 0, () => {
      expect(MUSIC_SONGS.length).assertEqual(6)
    })

    it('music_ear_meta_is_registered', 0, () => {
      const meta = getActivityMeta('music_ear')
      expect(meta.longLabel).assertEqual('音符小耳朵')
      expect(meta.shortLabel).assertEqual('音乐')
    })
  })
}
