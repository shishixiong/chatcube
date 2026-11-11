import { describe, it, expect } from '@ohos/hypium'
import {
  parseCartoonLibrary, serializeCartoonLibrary, titleFromUri, appendCartoonEntry,
  removeCartoonEntry, updateCartoonEntry, pickPromptEntries, parseMetadataDurationMs,
  buildCartoonEntryId, parseEpisodeMetaFromUri, sortEntriesByEpisode, groupEntriesBySeries,
  findNextEpisode, findEpisodeInGroup, formatEpisodeLabel
} from '../../../../main/ets/utils/CartoonLibraryUtils'
import { CartoonEntry, CartoonEntryStatus } from '../../../../main/ets/models/CartoonModels'

function entry(id: string, addedAt: number, status: string, uri: string): CartoonEntry {
  const e: CartoonEntry = {
    id: id, uri: uri, title: id, tags: '', durationMs: 360000, addedAt: addedAt,
    status: status as CartoonEntryStatus,
    seriesTitle: 'Series', season: 1, episode: addedAt, lastWatchedAt: 0
  }
  return e
}

function episode(id: string, season: number, episodeNo: number, lastWatchedAt: number): CartoonEntry {
  const e: CartoonEntry = {
    id: id, uri: 'file://docs/' + id + '.mp4', title: id, tags: '', durationMs: 360000,
    addedAt: 1, status: 'ok', seriesTitle: 'Numberblocks', season: season, episode: episodeNo,
    lastWatchedAt: lastWatchedAt
  }
  return e
}

export default function cartoonLibraryUtilsTest() {
  describe('CartoonLibraryUtils', () => {
    it('malformed_json_returns_empty', 0, () => {
      expect(parseCartoonLibrary('{oops').length).assertEqual(0)
      expect(parseCartoonLibrary('').length).assertEqual(0)
    })

    it('serialize_roundtrip', 0, () => {
      const list: CartoonEntry[] = [entry('ct_a', 1, 'ok', 'file://docs/a.mp4')]
      expect(parseCartoonLibrary(serializeCartoonLibrary(list)).length).assertEqual(1)
    })

    it('title_from_uri_strips_extension_and_decodes', 0, () => {
      expect(titleFromUri('file://docs/storage/Users/currentUser/Download/Peppa%20Pig.mp4'))
        .assertEqual('Peppa Pig')
      expect(titleFromUri('file://docs/a/b/c.mkv')).assertEqual('c')
    })

    it('append_dedupes_by_uri', 0, () => {
      const list: CartoonEntry[] = [entry('ct_a', 1, 'ok', 'file://docs/a.mp4')]
      const next = appendCartoonEntry(list, entry('ct_b', 2, 'ok', 'file://docs/a.mp4'))
      expect(next.length).assertEqual(1)
    })

    it('remove_and_update', 0, () => {
      const list: CartoonEntry[] = [entry('ct_a', 1, 'ok', 'file://docs/a.mp4')]
      expect(removeCartoonEntry(list, 'ct_a').length).assertEqual(0)
      const updated = updateCartoonEntry(list, 'ct_a', '  佩奇  ', 2, 5, '  第5集  ', '小猪,家庭')
      expect(updated[0].seriesTitle).assertEqual('佩奇')
      expect(updated[0].season).assertEqual(2)
      expect(updated[0].episode).assertEqual(5)
      expect(updated[0].title).assertEqual('第5集')
      expect(updated[0].tags).assertEqual('小猪,家庭')
    })

    it('pick_prompt_entries_filters_and_caps', 0, () => {
      const list: CartoonEntry[] = []
      for (let i = 0; i < 70; i++) {
        list.push(entry('ct_' + i, i, i === 0 ? 'unavailable' : 'ok', 'file://docs/' + i + '.mp4'))
      }
      const picked = pickPromptEntries(list, 60)
      expect(picked.length).assertEqual(60)
      expect(picked[0].id).assertEqual('ct_69')
      for (let i = 0; i < picked.length; i++) {
        expect(picked[i].status).assertEqual('ok')
      }
    })

    it('metadata_duration_parses_ms_and_rejects_junk', 0, () => {
      expect(parseMetadataDurationMs('372000')).assertEqual(372000)
      expect(parseMetadataDurationMs('')).assertEqual(0)
      expect(parseMetadataDurationMs('abc')).assertEqual(0)
      expect(parseMetadataDurationMs('-1')).assertEqual(0)
    })

    it('entry_id_is_stable_shape', 0, () => {
      expect(buildCartoonEntryId(1720000000000, 'ab12')).assertEqual('ct_1720000000000_ab12')
    })

    it('episode_meta_parses_sxxeyy', 0, () => {
      const meta = parseEpisodeMetaFromUri('file://docs/storage/Users/currentUser/Download/Numberblocks/S07E14_Nines_Time_to_Shine.mp4')
      expect(meta.season).assertEqual(7)
      expect(meta.episode).assertEqual(14)
      expect(meta.seriesTitle).assertEqual('Numberblocks')
      expect(meta.title).assertEqual('Nines Time to Shine')
    })

    it('episode_meta_parses_chinese_markers', 0, () => {
      const meta = parseEpisodeMetaFromUri('file://docs/Download/Peppa%20Pig/第2季第5集-去露营.mp4')
      expect(meta.season).assertEqual(2)
      expect(meta.episode).assertEqual(5)
      expect(meta.seriesTitle).assertEqual('Peppa Pig')
      expect(meta.title).assertEqual('去露营')
    })

    it('episode_meta_falls_back_for_flat_files', 0, () => {
      const meta = parseEpisodeMetaFromUri('file://docs/storage/Users/currentUser/Download/Peppa%20Pig.mp4')
      expect(meta.season).assertEqual(0)
      expect(meta.episode).assertEqual(0)
      expect(meta.title).assertEqual('Peppa Pig')
      expect(meta.seriesTitle).assertEqual('Peppa Pig')
    })

    it('parse_library_migrates_missing_episode_fields', 0, () => {
      const legacy = '[{"id":"ct_a","uri":"file://docs/Download/Numberblocks/S07E14_Nines.mp4","title":"S07E14_Nines","tags":"","durationMs":360000,"addedAt":1,"status":"ok"}]'
      const parsed = parseCartoonLibrary(legacy)
      expect(parsed[0].season).assertEqual(7)
      expect(parsed[0].episode).assertEqual(14)
      expect(parsed[0].seriesTitle).assertEqual('Numberblocks')
      expect(parsed[0].lastWatchedAt).assertEqual(0)
    })

    it('sort_by_season_and_episode', 0, () => {
      const sorted = sortEntriesByEpisode([episode('b', 1, 2, 0), episode('a', 1, 1, 0), episode('c', 2, 1, 0)])
      expect(sorted[0].id).assertEqual('a')
      expect(sorted[1].id).assertEqual('b')
      expect(sorted[2].id).assertEqual('c')
    })

    it('next_episode_follows_last_watched', 0, () => {
      const list: CartoonEntry[] = [episode('a', 1, 1, 0), episode('b', 1, 2, 100), episode('c', 1, 3, 0)]
      expect(findNextEpisode(list)!.id).assertEqual('c')
    })

    it('next_episode_starts_at_first_when_never_watched', 0, () => {
      const list: CartoonEntry[] = [episode('b', 1, 2, 0), episode('a', 1, 1, 0)]
      expect(findNextEpisode(list)!.id).assertEqual('a')
    })

    it('next_episode_is_null_after_finale', 0, () => {
      const list: CartoonEntry[] = [episode('a', 1, 1, 0), episode('b', 1, 2, 100)]
      expect(findNextEpisode(list) === null).assertTrue()
    })

    it('group_entries_by_series', 0, () => {
      const groups = groupEntriesBySeries([episode('a', 1, 1, 0), episode('b', 1, 2, 0)])
      expect(groups.length).assertEqual(1)
      expect(groups[0].seriesTitle).assertEqual('Numberblocks')
      expect(groups[0].entries.length).assertEqual(2)
    })

    it('find_episode_in_group_by_season_episode', 0, () => {
      const list: CartoonEntry[] = [episode('a', 1, 1, 0), episode('b', 1, 2, 0)]
      expect(findEpisodeInGroup(list, 1, 2)!.id).assertEqual('b')
      expect(findEpisodeInGroup(list, 9, 9) === null).assertTrue()
    })

    it('episode_label_formats', 0, () => {
      expect(formatEpisodeLabel(episode('a', 7, 14, 0))).assertEqual('S07E14')
      expect(formatEpisodeLabel(episode('a', 0, 3, 0))).assertEqual('E03')
      expect(formatEpisodeLabel(episode('a', 0, 0, 0))).assertEqual('')
    })
  })
}
