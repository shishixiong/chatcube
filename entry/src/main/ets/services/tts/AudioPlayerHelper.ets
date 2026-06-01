import { media } from '@kit.MediaKit'
import { fileIo } from '@kit.CoreFileKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'

export interface AudioPlayerCallback {
  onStart: () => void
  onComplete: () => void
  onError: (error: string) => void
}

export class AudioPlayerHelper {
  private player: media.AVPlayer | null = null
  private callback: AudioPlayerCallback | null = null
  private tempFilePath: string = ''
  private context: common.Context | null = null

  init(context: common.Context): void {
    this.context = context
  }

  // 从 ArrayBuffer 播放音频
  async playFromBuffer(buffer: ArrayBuffer, callback: AudioPlayerCallback): Promise<void> {
    if (this.context === null) {
      callback.onError('AudioPlayer 未初始化')
      return
    }

    // 播放前先停止之前的播放
    this.stop()

    this.callback = callback

    try {
      // 写入临时文件
      this.tempFilePath = this.writeTempFile(buffer)

      // 创建 AVPlayer（createAVPlayer 返回 Promise）
      const player = await media.createAVPlayer()
      this.player = player

      // 监听状态变化
      player.on('stateChange', (state: string) => {
        switch (state) {
          case 'initialized':
            // 使用 file:// URL 播放
            player.url = `file://${this.tempFilePath}`
            break
          case 'prepared':
            player.play()
            break
          case 'playing':
            if (this.callback !== null) {
              this.callback.onStart()
            }
            break
          case 'completed':
            this.handlePlayComplete()
            break
          case 'stopped':
            break
          case 'error':
            this.handlePlayError('播放状态异常')
            break
        }
      })

      // 监听播放错误
      player.on('error', (err: BusinessError) => {
        console.error('AudioPlayerHelper', `AVPlayer error: ${err.code}, ${err.message}`)
        this.handlePlayError(`音频播放失败: ${err.message}`)
      })
    } catch (error) {
      const err = error as BusinessError
      console.error('AudioPlayerHelper', `创建播放器失败: ${JSON.stringify(error)}`)
      this.cleanupTempFile()
      callback.onError(`音频播放器创建失败: ${err.message}`)
    }
  }

  // 停止播放
  stop(): void {
    try {
      if (this.player !== null) {
        this.player.stop()
        this.player.reset()
        this.player.release()
        this.player = null
      }
    } catch (_error) {
      // ignore
    }
    this.cleanupTempFile()
    this.callback = null
  }

  // 是否正在播放
  isPlaying(): boolean {
    if (this.player !== null) {
      try {
        return this.player.state === 'playing'
      } catch (_error) {
        return false
      }
    }
    return false
  }

  // 释放资源
  destroy(): void {
    this.callback = null
    try {
      if (this.player !== null) {
        this.player.stop()
        this.player.reset()
        this.player.release()
        this.player = null
      }
    } catch (_error) {
      // ignore
    }
    this.cleanupTempFile()
  }

  // 写入临时文件
  private writeTempFile(buffer: ArrayBuffer): string {
    const tempDir = this.context!.tempDir
    const fileName = `tts_audio_${Date.now()}.mp3`
    const filePath = `${tempDir}/${fileName}`

    const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
    fileIo.writeSync(file.fd, buffer)
    fileIo.closeSync(file)

    return filePath
  }

  private handlePlayComplete(): void {
    this.cleanupTempFile()
    const cb = this.callback
    this.callback = null
    if (cb !== null) {
      cb.onComplete()
    }
  }

  private handlePlayError(message: string): void {
    this.cleanupTempFile()
    const cb = this.callback
    this.callback = null
    if (cb !== null) {
      cb.onError(message)
    }
  }

  // 清理临时文件
  private cleanupTempFile(): void {
    if (this.tempFilePath !== '') {
      try {
        fileIo.unlinkSync(this.tempFilePath)
      } catch (_error) {
        // 文件不存在或已删除
      }
      this.tempFilePath = ''
    }
  }
}
