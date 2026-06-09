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
  private tempFd: number = -1
  private context: common.Context | null = null

  init(context: common.Context): void {
    this.context = context
    console.info('AudioPlayerHelper', 'init done')
  }

  // 从 PCM16 原始数据播放音频（自动封装 WAV 头）
  async playFromPcmData(pcmData: ArrayBuffer, sampleRate: number, callback: AudioPlayerCallback): Promise<void> {
    const wavBuffer = this.pcmToWav(pcmData, sampleRate, 1, 16)
    console.info('AudioPlayerHelper', `WAV buffer size: ${wavBuffer.byteLength}`)
    await this.playFromBuffer(wavBuffer, callback, 'wav')
  }

  // 从 ArrayBuffer 播放音频
  async playFromBuffer(buffer: ArrayBuffer, callback: AudioPlayerCallback, ext?: string): Promise<void> {
    if (this.context === null) {
      console.error('AudioPlayerHelper', 'context is null, calling onError')
      callback.onError('AudioPlayer 未初始化')
      return
    }

    // 播放前先停止之前的播放
    this.stop()

    this.callback = callback

    try {
      // 写入临时文件
      const fileExt = ext ?? 'mp3'
      this.tempFilePath = this.writeTempFile(buffer, fileExt)
      console.info('AudioPlayerHelper', `临时文件: ${this.tempFilePath}, size: ${buffer.byteLength}`)

      // 重新打开文件获取 fd（AVPlayer 需要 fd:// 协议）
      const file = fileIo.openSync(this.tempFilePath, fileIo.OpenMode.READ_ONLY)
      this.tempFd = file.fd

      // 创建 AVPlayer（createAVPlayer 返回 Promise）
      const player = await media.createAVPlayer()
      this.player = player
      console.info('AudioPlayerHelper', 'AVPlayer 创建成功')

      // 监听状态变化
      player.on('stateChange', (state: string) => {
        console.info('AudioPlayerHelper', `AVPlayer state: ${state}`)
        switch (state) {
          case 'initialized':
            // URL 设置完成，准备播放
            player.prepare()
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

      // 使用 fd:// 协议设置 URL 触发初始化流程
      player.url = `fd://${this.tempFd}`
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
  private writeTempFile(buffer: ArrayBuffer, ext: string): string {
    const tempDir = this.context!.tempDir
    const fileName = `tts_audio_${Date.now()}.${ext}`
    const filePath = `${tempDir}/${fileName}`
    console.info('AudioPlayerHelper', `writeTempFile: ${filePath}`)

    const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
    fileIo.writeSync(file.fd, buffer)
    fileIo.closeSync(file)
    console.info('AudioPlayerHelper', `writeTempFile done, wrote ${buffer.byteLength} bytes`)

    return filePath
  }

  // PCM 原始数据转 WAV（添加 44 字节 WAV 文件头）
  private pcmToWav(pcmData: ArrayBuffer, sampleRate: number, numChannels: number, bitsPerSample: number): ArrayBuffer {
    const byteRate = sampleRate * numChannels * bitsPerSample / 8
    const blockAlign = numChannels * bitsPerSample / 8
    const dataSize = pcmData.byteLength
    const headerSize = 44
    const totalSize = headerSize + dataSize

    const buffer = new ArrayBuffer(totalSize)
    const view = new DataView(buffer)

    // RIFF chunk
    this.writeDataViewString(view, 0, 'RIFF')
    view.setUint32(4, totalSize - 8, true)
    this.writeDataViewString(view, 8, 'WAVE')

    // fmt sub-chunk
    this.writeDataViewString(view, 12, 'fmt ')
    view.setUint32(16, 16, true)
    view.setUint16(20, 1, true)
    view.setUint16(22, numChannels, true)
    view.setUint32(24, sampleRate, true)
    view.setUint32(28, byteRate, true)
    view.setUint16(32, blockAlign, true)
    view.setUint16(34, bitsPerSample, true)

    // data sub-chunk
    this.writeDataViewString(view, 36, 'data')
    view.setUint32(40, dataSize, true)

    // 拷贝 PCM 数据
    const pcmView = new Uint8Array(pcmData)
    const wavView = new Uint8Array(buffer)
    wavView.set(pcmView, headerSize)

    return buffer
  }

  private writeDataViewString(view: DataView, offset: number, str: string): void {
    for (let i = 0; i < str.length; i++) {
      view.setUint8(offset + i, str.charCodeAt(i))
    }
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
    if (this.tempFd >= 0) {
      try {
        fileIo.closeSync(this.tempFd)
      } catch (_error) {
        // ignore
      }
      this.tempFd = -1
    }
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
