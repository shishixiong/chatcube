/**
 * 「本地动画片库」system prompt 段渲染（spec 2026-11-10 §8.2 + v2 季集索引）。
 * 纯函数，无 I/O。
 */

import { CartoonEntry, CartoonQuotaSnapshot, CARTOON_PROMPT_MAX_ENTRIES } from '../models/CartoonModels'
import { formatDurationSeconds } from './CartoonQuotaMath'
import {
  pickPromptEntries,
  groupEntriesBySeries,
  findLastWatched,
  findNextEpisode,
  formatEpisodeLabel
} from './CartoonLibraryUtils'

function displayName(entry: CartoonEntry): string {
  const label = formatEpisodeLabel(entry)
  return label !== '' ? label : entry.title
}

export function renderCartoonCatalogSection(entries: CartoonEntry[], snapshot: CartoonQuotaSnapshot): string {
  const usable = pickPromptEntries(entries, CARTOON_PROMPT_MAX_ENTRIES)
  if (usable.length === 0) {
    return '【本地动画片库】当前没有动画片。孩子想看时，告诉他请爸爸妈妈在设置里的「动画片管理」添加。'
  }

  const lines: string[] = []
  lines.push('【本地动画片库】仅在孩子主动提出看动画时使用。')
  const groups = groupEntriesBySeries(usable)
  for (let g = 0; g < groups.length; g++) {
    const group = groups[g]
    const last = findLastWatched(group.entries)
    const next = findNextEpisode(group.entries)
    const lastText = last !== null ? `上次看到 ${displayName(last)}` : '还没看过'
    const nextText = next !== null ? `下一集 ${displayName(next)} → ${next.id}` : '已看完'
    lines.push(`系列：${group.seriesTitle}（${group.entries.length} 集；${lastText}；${nextText}）`)
    for (let i = 0; i < group.entries.length; i++) {
      const item = group.entries[i]
      const label = formatEpisodeLabel(item)
      const durationText = formatDurationSeconds(Math.round(item.durationMs / 1000))
      const titlePart = label !== '' && item.title !== '' && item.title !== group.seriesTitle
        ? `｜${item.title}`
        : ''
      const tagPart = item.tags.trim() !== '' ? `｜标签：${item.tags.trim()}` : ''
      lines.push(`- ${item.id}｜${displayName(item)}｜${durationText}${titlePart}${tagPart}`)
    }
  }
  if (entries.length > usable.length) {
    lines.push(`（片库共 ${entries.length} 部，这里只列最近 ${usable.length} 部）`)
  }

  const sessionMinutes = Math.floor(snapshot.sessionMs / 60000)
  const dailyMinutes = Math.floor(snapshot.dayMs / 60000)
  const sessionLimitMinutes = Math.floor(snapshot.sessionLimitMs / 60000)
  const dailyLimitMinutes = Math.floor(snapshot.dayLimitMs / 60000)
  const sessionLeft = Math.max(0, sessionLimitMinutes - sessionMinutes)
  const dailyLeft = Math.max(0, dailyLimitMinutes - dailyMinutes)
  lines.push(
    `时间：本次已看 ${sessionMinutes} 分钟（单次上限 ${sessionLimitMinutes} 分钟，还剩 ${sessionLeft} 分钟）；` +
    `今天已看 ${dailyMinutes} 分钟（每天上限 ${dailyLimitMinutes} 分钟，还剩 ${dailyLeft} 分钟）。`
  )
  lines.push('孩子没点名系列时，优先继续上次看过的那部；都没看过就从第一部开始。孩子没指定从哪一集开始，播放该系列的「下一集」；点名第 X 季第 Y 集时，找对应行；找不到就如实说没有。')
  lines.push('一次只播一集。额度到上限时不要调用工具，直接告诉孩子今天先看到这里。')
  return lines.join('\n')
}
