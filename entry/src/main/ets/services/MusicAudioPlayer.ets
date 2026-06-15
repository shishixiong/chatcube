/**
 * 音乐文件播放器
 *
 * 设计目标:
 * - 单例模式, 全局共享一个 AVPlayer 实例 (同 TTS 的 AudioPlayerHelper 一样)
 * - 接收 filePath 而非 buffer (与 TTS 不同: 音乐文件已通过 AttachmentStorageService 持久化到沙箱)
 * - 暴露 play / pause / resume / stop / release / getCurrentTime / getDuration / isPlaying
 *
 * 复用 AudioPlayerHelper.ets 的 fd:// 协议模式 + stateChange 事件流转, 不重新发明轮子。
 */

import { media } from '@kit.MediaKit'
import { fileIo } from '@kit.CoreFileKit'
import { BusinessError } from '@kit.BasicServicesKit'

export interface MusicAudioPlayerCallback {
  onPrepared?: (durationMs: number) => void
  onPlay: () => void
  onPause: () => void
  onComplete: () => void
  onError: (error: string) => void
}

export class MusicAudioPlayer {
  private static instance: MusicAudioPlayer | null = null
  private player: media.AVPlayer | null = null
  private currentFd: number = -1
  private currentPath: string = ''
  private callbacks: MusicAudioPlayerCallback | null = null
  // 上报给 UI 的"准备就绪"时长(毫秒)。在 prepared 状态写入, 之后保持稳定,
  // 避免 UI 反复从 player.duration 读取 (部分 HarmonyOS 版本上 access 该属性会抛同步异常)。
  private preparedDurationMs: number = 0

  static getInstance(): MusicAudioPlayer {
    if (MusicAudioPlayer.instance === null) {
      MusicAudioPlayer.instance = new MusicAudioPlayer()
    }
    return MusicAudioPlayer.instance
  }

  // 播放一个本地音频文件
  async play(filePath: string, callbacks: MusicAudioPlayerCallback): Promise<void> {
    if (filePath === '') {
      callbacks.onError('音频路径为空')
      return
    }
    // 切换曲目时先释放旧实例
    this.releaseInternal()
    this.currentPath = filePath
    this.callbacks = callbacks
    this.preparedDurationMs = 0

    let file: fileIo.File | null = null
    try {
      file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY)
      this.currentFd = file.fd
    } catch (error) {
      const err = error as BusinessError
      callbacks.onError(`无法打开音频文件: ${err.message}`)
      this.resetCallback()
      return
    } finally {
      // fileIo.openSync 不会返回需要 close 的句柄 (fd 模式下, fd 才是资源)
      // 这里 file 变量仅用于兼容 try/finally 语法
      file = null
    }

    try {
      const player = await media.createAVPlayer()
      this.player = player

      player.on('stateChange', (state: string) => {
        this.handleStateChange(state, player)
      })
      player.on('error', (err: BusinessError) => {
        console.error('MusicAudioPlayer', `AVPlayer error: ${err.code}, ${err.message}`)
        this.dispatchError(`音频播放失败: ${err.message}`)
      })

      // 触发初始化流程
      player.url = `fd://${this.currentFd}`
    } catch (error) {
      const err = error as BusinessError
      console.error('MusicAudioPlayer', `创建播放器失败: ${JSON.stringify(error)}`)
      this.dispatchError(`音频播放器创建失败: ${err.message}`)
    }
  }

  private handleStateChange(state: string, player: media.AVPlayer): void {
    switch (state) {
      case 'initialized':
        player.prepare()
        break
      case 'prepared':
        try {
          // duration 单位秒, 转毫秒
          this.preparedDurationMs = Math.max(0, Math.floor(player.duration * 1000))
        } catch (_error) {
          this.preparedDurationMs = 0
        }
        const cb = this.callbacks
        if (cb !== null && cb.onPrepared !== undefined) {
          cb.onPrepared(this.preparedDurationMs)
        }
        player.play()
        break
      case 'playing':
        const onPlayCb = this.callbacks
        if (onPlayCb !== null) {
          onPlayCb.onPlay()
        }
        break
      case 'paused':
        const onPauseCb = this.callbacks
        if (onPauseCb !== null) {
          onPauseCb.onPause()
        }
        break
      case 'completed':
        this.dispatchComplete()
        break
      case 'stopped':
        break
      case 'error':
        this.dispatchError('播放状态异常')
        break
    }
  }

  // 暂停 (仅在已 prepared 后才生效)
  pause(): void {
    if (this.player === null) {
      return
    }
    try {
      if (this.player.state === 'playing') {
        this.player.pause()
      }
    } catch (error) {
      console.warn('MusicAudioPlayer', `pause failed: ${JSON.stringify(error)}`)
    }
  }

  // 恢复播放
  resume(): void {
    if (this.player === null) {
      return
    }
    try {
      if (this.player.state === 'paused') {
        this.player.play()
      }
    } catch (error) {
      console.warn('MusicAudioPlayer', `resume failed: ${JSON.stringify(error)}`)
    }
  }

  // 完整停止 + 释放 (外部不再使用时调用)
  stop(): void {
    this.releaseInternal()
    this.resetCallback()
  }

  // 当前播放进度 (毫秒)
  getCurrentTimeMs(): number {
    if (this.player === null) {
      return 0
    }
    try {
      if (this.player.state === 'playing' || this.player.state === 'paused') {
        return Math.max(0, Math.floor(this.player.currentTime * 1000))
      }
    } catch (_error) {
    }
    return 0
  }

  // 总时长 (毫秒), 仅在 prepared 之后才返回有效值
  getDurationMs(): number {
    return this.preparedDurationMs
  }

  // 是否正在播放
  isPlaying(): boolean {
    if (this.player === null) {
      return false
    }
    try {
      return this.player.state === 'playing'
    } catch (_error) {
      return false
    }
  }

  // 当前加载的曲目路径
  getCurrentPath(): string {
    return this.currentPath
  }

  // 释放资源, 保留 callback 引用 (用于切换曲目场景)
  private releaseInternal(): void {
    if (this.player !== null) {
      try {
        this.player.off('stateChange')
        this.player.off('error')
        this.player.stop()
        this.player.reset()
        this.player.release()
      } catch (_error) {
        // ignore
      }
      this.player = null
    }
    if (this.currentFd >= 0) {
      try {
        fileIo.closeSync(this.currentFd)
      } catch (_error) {
        // ignore
      }
      this.currentFd = -1
    }
    this.currentPath = ''
    this.preparedDurationMs = 0
  }

  // 完整释放 (外部组件 aboutToDisappear 时调用)
  release(): void {
    this.releaseInternal()
    this.resetCallback()
  }

  private dispatchComplete(): void {
    const cb = this.callbacks
    this.resetCallback()
    // 释放 fd/player 但保留 callback 已派发
    this.releaseInternal()
    if (cb !== null) {
      cb.onComplete()
    }
  }

  private dispatchError(message: string): void {
    const cb = this.callbacks
    this.resetCallback()
    this.releaseInternal()
    if (cb !== null) {
      cb.onError(message)
    }
  }

  private resetCallback(): void {
    this.callbacks = null
  }
}

export function getMusicAudioPlayer(): MusicAudioPlayer {
  return MusicAudioPlayer.getInstance()
}
