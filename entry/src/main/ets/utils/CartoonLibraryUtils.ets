/**
 * 动画片片库纯函数：JSON 解析/序列化、标题/季集索引、增删改、排序/分组/下一集。
 * 无 ArkUI / 无 I/O，可直接 hypium 单测。
 */

import { CartoonEntry, CartoonEntryStatus } from '../models/CartoonModels'

const FALLBACK_TITLE: string = '未命名动画'
const GENERIC_FOLDERS: string[] = ['download', 'downloads', 'documents', 'movies', 'dcim', '0', 'files', 'cache']

export interface CartoonEpisodeMeta {
  title: string
  seriesTitle: string
  season: number
  episode: number
}

export interface CartoonSeriesGroup {
  seriesTitle: string
  entries: CartoonEntry[]
}

function decodeSegment(segment: string): string {
  try {
    return decodeURIComponent(segment)
  } catch (_e) {
    return segment
  }
}

function cleanTitle(raw: string): string {
  return raw.replace(/[_.\-]+/g, ' ').replace(/\s+/g, ' ').trim()
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`
}

/**
 * 从 picker URI 解析：集标题 / 动画片名 / 季 / 集。
 * 顺序：文件名里的 SxxEyy 或 第N季第M集 → 父文件夹名做系列名 → 文件名前缀做系列名 → 集标题兜底。
 */
export function parseEpisodeMetaFromUri(uri: string): CartoonEpisodeMeta {
  const slash = uri.lastIndexOf('/')
  const filenameRaw = slash >= 0 ? uri.substring(slash + 1) : uri
  const filename = decodeSegment(filenameRaw)
  const dot = filename.lastIndexOf('.')
  const stem = dot > 0 ? filename.substring(0, dot) : filename

  const parentRaw = slash > 0 ? uri.substring(0, slash) : ''
  const parentSlash = parentRaw.lastIndexOf('/')
  const parentSegment = parentSlash >= 0
    ? decodeSegment(parentRaw.substring(parentSlash + 1))
    : decodeSegment(parentRaw)

  let season = 0
  let episode = 0
  let title = stem
  const match = /S(\d{1,2})E(\d{1,3})/i.exec(stem)
  if (match !== null) {
    season = Number(match[1])
    episode = Number(match[2])
    title = cleanTitle(stem.replace(match[0], ' '))
  } else {
    const seasonMatch = /第\s*(\d+)\s*季/.exec(stem)
    const episodeMatch = /第\s*(\d+)\s*集/.exec(stem)
    if (seasonMatch !== null) {
      season = Number(seasonMatch[1])
    }
    if (episodeMatch !== null) {
      episode = Number(episodeMatch[1])
    }
    title = cleanTitle(stem.replace(/第\s*\d+\s*季/g, ' ').replace(/第\s*\d+\s*集/g, ' '))
  }
  if (title === '') {
    title = cleanTitle(stem)
  }
  if (title === '') {
    title = FALLBACK_TITLE
  }

  let seriesTitle = ''
  if (parentSegment !== '' && GENERIC_FOLDERS.indexOf(parentSegment.toLowerCase()) === -1) {
    seriesTitle = parentSegment
  }
  if (seriesTitle === '' && match !== null) {
    seriesTitle = cleanTitle(stem.substring(0, match.index))
  }
  if (seriesTitle === '') {
    seriesTitle = title
  }

  const meta: CartoonEpisodeMeta = {
    title: title,
    seriesTitle: seriesTitle,
    season: season,
    episode: episode
  }
  return meta
}

export function parseCartoonLibrary(json: string): CartoonEntry[] {
  if (json.trim() === '') {
    return []
  }
  try {
    const parsed = JSON.parse(json) as CartoonEntry[]
    if (!Array.isArray(parsed)) {
      return []
    }
    const out: CartoonEntry[] = []
    for (let i = 0; i < parsed.length; i++) {
      const raw = parsed[i]
      if (raw === null || raw === undefined) {
        continue
      }
      const uri = typeof raw.uri === 'string' ? raw.uri : ''
      if (uri === '') {
        continue
      }
      const meta = parseEpisodeMetaFromUri(uri)
      const status: CartoonEntryStatus = raw.status === 'ok' ? 'ok' : 'unavailable'
      const storedTitle = typeof raw.title === 'string' ? raw.title : ''
      const entry: CartoonEntry = {
        id: typeof raw.id === 'string' ? raw.id : '',
        uri: uri,
        title: storedTitle !== '' ? storedTitle : meta.title,
        tags: typeof raw.tags === 'string' ? raw.tags : '',
        durationMs: typeof raw.durationMs === 'number' && raw.durationMs > 0 ? raw.durationMs : 0,
        addedAt: typeof raw.addedAt === 'number' ? raw.addedAt : 0,
        status: status,
        seriesTitle: typeof raw.seriesTitle === 'string' && raw.seriesTitle !== ''
          ? raw.seriesTitle
          : meta.seriesTitle,
        season: typeof raw.season === 'number' && raw.season > 0 ? raw.season : meta.season,
        episode: typeof raw.episode === 'number' && raw.episode > 0 ? raw.episode : meta.episode,
        lastWatchedAt: typeof raw.lastWatchedAt === 'number' && raw.lastWatchedAt > 0
          ? raw.lastWatchedAt
          : 0
      }
      if (entry.id !== '') {
        out.push(entry)
      }
    }
    return out
  } catch (_e) {
    return []
  }
}

export function serializeCartoonLibrary(entries: CartoonEntry[]): string {
  return JSON.stringify(entries)
}

/** 从 picker URI 取文件名并去掉扩展名；解码失败保留原串 */
export function titleFromUri(uri: string): string {
  const slash = uri.lastIndexOf('/')
  const segment = slash >= 0 ? uri.substring(slash + 1) : uri
  const decoded = decodeSegment(segment)
  const dot = decoded.lastIndexOf('.')
  const title = dot > 0 ? decoded.substring(0, dot) : decoded
  const trimmed = title.trim()
  return trimmed !== '' ? trimmed : FALLBACK_TITLE
}

/** 同一个 uri 不重复加入 */
export function appendCartoonEntry(entries: CartoonEntry[], entry: CartoonEntry): CartoonEntry[] {
  const next: CartoonEntry[] = []
  let duplicate = false
  for (let i = 0; i < entries.length; i++) {
    next.push(entries[i])
    if (entries[i].uri === entry.uri) {
      duplicate = true
    }
  }
  if (!duplicate) {
    next.push(entry)
  }
  return next
}

export function removeCartoonEntry(entries: CartoonEntry[], id: string): CartoonEntry[] {
  const next: CartoonEntry[] = []
  for (let i = 0; i < entries.length; i++) {
    if (entries[i].id !== id) {
      next.push(entries[i])
    }
  }
  return next
}

export function updateCartoonEntry(
  entries: CartoonEntry[],
  id: string,
  seriesTitle: string,
  season: number,
  episode: number,
  title: string,
  tags: string
): CartoonEntry[] {
  const next: CartoonEntry[] = []
  const trimmedSeries = seriesTitle.trim()
  const trimmedTitle = title.trim()
  const trimmedTags = tags.trim()
  for (let i = 0; i < entries.length; i++) {
    const current = entries[i]
    if (current.id === id) {
      const updated: CartoonEntry = {
        id: current.id,
        uri: current.uri,
        title: trimmedTitle !== '' ? trimmedTitle : current.title,
        tags: trimmedTags,
        durationMs: current.durationMs,
        addedAt: current.addedAt,
        status: current.status,
        seriesTitle: trimmedSeries !== '' ? trimmedSeries : current.seriesTitle,
        season: season > 0 ? season : current.season,
        episode: episode > 0 ? episode : current.episode,
        lastWatchedAt: current.lastWatchedAt
      }
      next.push(updated)
    } else {
      next.push(current)
    }
  }
  return next
}

/** 只返回可播放条目，按添加时间倒序，最多 maxCount 条 */
export function pickPromptEntries(entries: CartoonEntry[], maxCount: number): CartoonEntry[] {
  const usable: CartoonEntry[] = []
  for (let i = 0; i < entries.length; i++) {
    if (entries[i].status === 'ok') {
      usable.push(entries[i])
    }
  }
  usable.sort((a: CartoonEntry, b: CartoonEntry): number => b.addedAt - a.addedAt)
  return usable.slice(0, maxCount > 0 ? maxCount : 0)
}

/** S07E14 / E03 / '' */
export function formatEpisodeLabel(entry: CartoonEntry): string {
  if (entry.season > 0 && entry.episode > 0) {
    return `S${pad2(entry.season)}E${pad2(entry.episode)}`
  }
  if (entry.episode > 0) {
    return `E${pad2(entry.episode)}`
  }
  return ''
}

/** 按 季 → 集 → 添加时间 排序（返回新数组） */
export function sortEntriesByEpisode(entries: CartoonEntry[]): CartoonEntry[] {
  const sorted: CartoonEntry[] = entries.slice()
  sorted.sort((a: CartoonEntry, b: CartoonEntry): number => {
    if (a.season !== b.season) {
      return a.season - b.season
    }
    if (a.episode !== b.episode) {
      return a.episode - b.episode
    }
    return a.addedAt - b.addedAt
  })
  return sorted
}

export function groupEntriesBySeries(entries: CartoonEntry[]): CartoonSeriesGroup[] {
  const sorted = sortEntriesByEpisode(entries)
  const groups: CartoonSeriesGroup[] = []
  for (let i = 0; i < sorted.length; i++) {
    const item = sorted[i]
    let group: CartoonSeriesGroup | null = null
    for (let j = 0; j < groups.length; j++) {
      if (groups[j].seriesTitle === item.seriesTitle) {
        group = groups[j]
        break
      }
    }
    if (group === null) {
      const created: CartoonSeriesGroup = { seriesTitle: item.seriesTitle, entries: [item] }
      groups.push(created)
    } else {
      group.entries.push(item)
    }
  }
  return groups
}

export function findLastWatched(entries: CartoonEntry[]): CartoonEntry | null {
  let found: CartoonEntry | null = null
  let latest = 0
  for (let i = 0; i < entries.length; i++) {
    if (entries[i].lastWatchedAt > latest) {
      latest = entries[i].lastWatchedAt
      found = entries[i]
    }
  }
  return found
}

/** 上次看完的下一集；没看过返回第一集；已播完最后一集返回 null */
export function findNextEpisode(entries: CartoonEntry[]): CartoonEntry | null {
  const sorted = sortEntriesByEpisode(entries)
  if (sorted.length === 0) {
    return null
  }
  let lastIndex = -1
  let latest = 0
  for (let i = 0; i < sorted.length; i++) {
    if (sorted[i].lastWatchedAt > latest) {
      latest = sorted[i].lastWatchedAt
      lastIndex = i
    }
  }
  if (lastIndex === -1) {
    return sorted[0]
  }
  if (lastIndex + 1 < sorted.length) {
    return sorted[lastIndex + 1]
  }
  return null
}

export function findEpisodeInGroup(entries: CartoonEntry[], season: number, episode: number): CartoonEntry | null {
  for (let i = 0; i < entries.length; i++) {
    if (entries[i].season === season && entries[i].episode === episode) {
      return entries[i]
    }
  }
  return null
}

/** AVMetadata.duration 是毫秒字符串；异常/非正数返回 0 */
export function parseMetadataDurationMs(raw: string): number {
  const value = Number(raw)
  if (!Number.isFinite(value) || value <= 0) {
    return 0
  }
  return Math.round(value)
}

export function buildCartoonEntryId(nowMs: number, suffix: string): string {
  return `ct_${nowMs}_${suffix}`
}
