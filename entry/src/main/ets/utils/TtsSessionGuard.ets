// TTS 会话守卫: 用单调递增 token 替代布尔 sessionClosed。
// stop() 后再 speak() 时, 上一次会话的迟到网络/播放回调必须失效,
// 不能误关新会话或推进新会话的 chunkIndex。

export class TtsSessionGuard {
  private currentToken: number = 0

  // 开启新会话, 返回本次 token; 之前所有 token 立即失效
  begin(): number {
    this.currentToken++
    return this.currentToken
  }

  // 结束当前会话 (完成 / 出错 / 主动 stop), 使当前 token 失效
  invalidate(): void {
    this.currentToken++
  }

  // 回调是否仍属于当前会话
  isActive(token: number): boolean {
    return token !== 0 && token === this.currentToken
  }
}
