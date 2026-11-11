/**
 * 动画片卡片/时间线的纯展示逻辑（可单测）。
 */

import { formatDurationSeconds } from './CartoonQuotaMath'

/**
 * 把 play_cartoon 的回执/拒绝 JSON 变成一句人话。
 * 关键：拒绝 JSON 没有 watched_seconds，绝不能渲染成「看到 00:00 关掉了」。
 */
export function summarizeCartoonPayload(payloadJson: string): string {
  if (payloadJson === '') {
    return ''
  }
  try {
    const parsed = JSON.parse(payloadJson) as Record<string, Object>
    const errorCode = parsed['error'] as string
    if (errorCode !== undefined && errorCode !== null && errorCode !== '') {
      switch (errorCode) {
        case 'daily_limit_reached':
          return '今天看够啦'
        case 'session_limit_reached':
          return '这次看够啦'
        case 'video_too_long':
          return '这一集太长了'
        case 'video_unavailable':
          return '这一集打不开了'
        case 'validation_failed':
          return '没有找到这一集'
        case 'too_soon':
          return '等孩子再说一次'
        case 'already_playing':
          return '已经在播了'
        default:
          return '没有播放'
      }
    }
    const completed = parsed['completed'] as boolean
    const watchedSeconds = parsed['watched_seconds'] as number
    const watched = watchedSeconds !== undefined && watchedSeconds !== null ? watchedSeconds : 0
    const clock = formatDurationSeconds(watched)
    return completed === true ? `已看完 ${clock}` : `看到 ${clock} 关掉了`
  } catch (_error) {
    return ''
  }
}
