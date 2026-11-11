/**
 * 播放页单例守卫：防止同一张待答横幅被连点两次，打开两个播放页
 * （第二个播放页会继续调用 addWatched，导致观看时长双倍累计）。
 */

let activeToolCallId: string = ''

export function beginCartoonPlayerSession(toolCallId: string): boolean {
  if (activeToolCallId !== '') {
    return false
  }
  activeToolCallId = toolCallId
  return true
}

export function endCartoonPlayerSession(toolCallId: string): void {
  if (activeToolCallId === toolCallId) {
    activeToolCallId = ''
  }
}

export function getActiveCartoonPlayerToolCallId(): string {
  return activeToolCallId
}
