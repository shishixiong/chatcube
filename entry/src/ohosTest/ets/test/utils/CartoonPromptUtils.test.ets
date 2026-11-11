import { describe, it, expect } from '@ohos/hypium'
import { renderCartoonCatalogSection } from '../../../../main/ets/utils/CartoonPromptUtils'
import { CartoonEntry, CartoonEntryStatus, CartoonQuotaSnapshot } from '../../../../main/ets/models/CartoonModels'

function snap(dayMs: number, sessionMs: number): CartoonQuotaSnapshot {
  const s: CartoonQuotaSnapshot = {
    dayKey: '2026-11-10', dayMs: dayMs, sessionMs: sessionMs, lastActivityMs: 0,
    dayLimitMs: 3600000, sessionLimitMs: 1200000
  }
  return s
}

function entry(id: string, title: string, durationMs: number, tags: string, status: string): CartoonEntry {
  const e: CartoonEntry = {
    id: id, uri: 'file://docs/' + id + '.mp4', title: title, tags: tags,
    durationMs: durationMs, addedAt: 1, status: status as CartoonEntryStatus,
    seriesTitle: 'Numberblocks', season: 7, episode: 14, lastWatchedAt: 0
  }
  return e
}

export default function cartoonPromptUtilsTest() {
  describe('CartoonPromptUtils', () => {
    it('empty_library_says_add_in_settings', 0, () => {
      const text = renderCartoonCatalogSection([], snap(0, 0))
      expect(text.indexOf('没有动画片') >= 0).assertTrue()
      expect(text.indexOf('动画片管理') >= 0).assertTrue()
    })

    it('renders_id_title_duration_and_quota', 0, () => {
      const list: CartoonEntry[] = [entry('ct_a', '小猪佩奇 第1集', 372000, '佩奇,小猪', 'ok')]
      const text = renderCartoonCatalogSection(list, snap(34 * 60 * 1000, 12 * 60 * 1000))
      expect(text.indexOf('ct_a') >= 0).assertTrue()
      expect(text.indexOf('小猪佩奇 第1集') >= 0).assertTrue()
      expect(text.indexOf('06:12') >= 0).assertTrue()
      expect(text.indexOf('标签：佩奇,小猪') >= 0).assertTrue()
      expect(text.indexOf('本次已看 12 分钟') >= 0).assertTrue()
      expect(text.indexOf('今天已看 34 分钟') >= 0).assertTrue()
    })

    it('hides_unavailable_entries', 0, () => {
      const list: CartoonEntry[] = [entry('ct_bad', '坏文件', 60000, '', 'unavailable')]
      const text = renderCartoonCatalogSection(list, snap(0, 0))
      expect(text.indexOf('ct_bad') === -1).assertTrue()
      expect(text.indexOf('没有动画片') >= 0).assertTrue()
    })

    it('notes_truncation_when_over_cap', 0, () => {
      const list: CartoonEntry[] = []
      for (let i = 0; i < 65; i++) {
        list.push(entry('ct_' + i, '片' + i, 60000, '', 'ok'))
      }
      const text = renderCartoonCatalogSection(list, snap(0, 0))
      expect(text.indexOf('片库共 65 部') >= 0).assertTrue()
    })

    it('groups_by_series_and_points_to_next_episode', 0, () => {
      const first: CartoonEntry = entry('ct_1', 'One', 360000, '', 'ok')
      first.season = 7
      first.episode = 1
      first.lastWatchedAt = 0
      const second: CartoonEntry = entry('ct_2', 'Two', 360000, '', 'ok')
      second.season = 7
      second.episode = 2
      second.lastWatchedAt = 100
      const third: CartoonEntry = entry('ct_3', 'Three', 360000, '', 'ok')
      third.season = 7
      third.episode = 3
      third.lastWatchedAt = 0
      const text = renderCartoonCatalogSection([first, second, third], snap(0, 0))
      expect(text.indexOf('系列：Numberblocks') >= 0).assertTrue()
      expect(text.indexOf('上次看到 S07E02') >= 0).assertTrue()
      expect(text.indexOf('已看完') === -1).assertTrue()
      expect(text.indexOf('下一集 S07E03') >= 0).assertTrue()
    })

    it('series_finished_says_finished', 0, () => {
      const only: CartoonEntry = entry('ct_1', 'One', 360000, '', 'ok')
      only.season = 7
      only.episode = 1
      only.lastWatchedAt = 100
      const text = renderCartoonCatalogSection([only], snap(0, 0))
      expect(text.indexOf('已看完') >= 0).assertTrue()
    })
  })
}
