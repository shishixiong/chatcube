/**
 * 音符小耳朵（music_ear）静态数据：音符、频率、琴键角色、儿歌旋律、音色。
 * 纯数据 + 纯类型，不依赖 ArkUI / 音频，便于单测。
 */

export type MusicNote = 'C' | 'D' | 'E' | 'F' | 'G' | 'A'

export type MusicTimbre = 'piano' | 'xylophone' | 'musicbox'

export type MusicDrill = 'high_low' | 'echo' | 'guess_song'

export interface MusicKeyDef {
  note: MusicNote
  fruit: string
  emoji: string
  color: string
  ink: string
  pale: string
}

export interface MusicSongDef {
  key: string
  name: string
  emoji: string
  notes: MusicNote[]
}

export interface MusicTimbreDef {
  id: MusicTimbre
  name: string
}

export const MUSIC_QUESTIONS_PER_ROUND: number = 5

export const MUSIC_NOTE_ORDER: MusicNote[] = ['C', 'D', 'E', 'F', 'G', 'A']

export const MUSIC_NOTE_FREQ: Record<MusicNote, number> = {
  'C': 261.63,
  'D': 293.66,
  'E': 329.63,
  'F': 349.23,
  'G': 392.00,
  'A': 440.00
}

export const MUSIC_KEYS: MusicKeyDef[] = [
  { note: 'C', fruit: '小苹果', emoji: '🍎', color: '#FF9A9A', ink: '#E24A4A', pale: '#FFC9C9' },
  { note: 'D', fruit: '小橘子', emoji: '🍊', color: '#FFC078', ink: '#DE7A22', pale: '#FFE0B8' },
  { note: 'E', fruit: '小太阳', emoji: '☀️', color: '#FFE066', ink: '#C99A00', pale: '#FFF3B8' },
  { note: 'F', fruit: '小叶子', emoji: '🍃', color: '#9BE9A8', ink: '#2F9550', pale: '#CFF5D6' },
  { note: 'G', fruit: '小水滴', emoji: '💧', color: '#8FD3FF', ink: '#2A82C9', pale: '#C9EBFF' },
  { note: 'A', fruit: '小葡萄', emoji: '🍇', color: '#C3A6FF', ink: '#7150CE', pale: '#E2D5FF' }
]

export const MUSIC_SONGS: MusicSongDef[] = [
  {
    key: 'twinkle',
    name: '小星星',
    emoji: '⭐',
    notes: ['C', 'C', 'G', 'G', 'A', 'A', 'G', 'F', 'F', 'E', 'E', 'D', 'D', 'C']
  },
  {
    key: 'tigers',
    name: '两只老虎',
    emoji: '🐯',
    notes: ['C', 'D', 'E', 'C', 'C', 'D', 'E', 'C', 'E', 'F', 'G', 'E', 'F', 'G']
  },
  {
    key: 'ode',
    name: '欢乐颂',
    emoji: '🎵',
    notes: ['E', 'E', 'F', 'G', 'G', 'F', 'E', 'D', 'C', 'C', 'D', 'E', 'E', 'D', 'D']
  },
  {
    key: 'mary',
    name: '小羊羔',
    emoji: '🐑',
    notes: ['E', 'D', 'C', 'D', 'E', 'E', 'E', 'D', 'D', 'D', 'E', 'G', 'G']
  },
  {
    key: 'row',
    name: '划小船',
    emoji: '⛵',
    notes: ['C', 'C', 'C', 'D', 'E', 'E', 'D', 'E', 'F', 'G']
  },
  {
    key: 'bee',
    name: '小蜜蜂',
    emoji: '🐝',
    notes: ['G', 'E', 'E', 'F', 'D', 'D', 'C', 'D', 'E', 'F', 'G', 'G', 'G']
  }
]

export const MUSIC_TIMBRES: MusicTimbreDef[] = [
  { id: 'piano', name: '钢琴' },
  { id: 'xylophone', name: '木琴' },
  { id: 'musicbox', name: '八音盒' }
]

export function findSong(key: string): MusicSongDef | null {
  for (let i = 0; i < MUSIC_SONGS.length; i++) {
    if (MUSIC_SONGS[i].key === key) {
      return MUSIC_SONGS[i]
    }
  }
  return null
}

export function musicKeyOf(note: MusicNote): MusicKeyDef {
  for (let i = 0; i < MUSIC_KEYS.length; i++) {
    if (MUSIC_KEYS[i].note === note) {
      return MUSIC_KEYS[i]
    }
  }
  return MUSIC_KEYS[0]
}
