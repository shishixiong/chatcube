/**
 * 动画片播放器（AVPlayer + XComponent）。
 *
 * 片源是文件选择器 URI：openSync 拿 fd → url = 'fd://<fd>'。
 * 只统计 playing 状态下的进度增量；暂停/切后台不计时。
 */

import { media } from '@kit.MediaKit'
import { fileIo } from '@kit.CoreFileKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { evaluatePreparedDuration } from '../../utils/CartoonQuotaMath'
import { getCartoonLibraryService } from '../../services/CartoonLibraryService'

function formatClock(ms: number): string {
  const total = ms > 0 ? Math.floor(ms / 1000) : 0
  const minutes = Math.floor(total / 60)
  const seconds = total % 60
  const mm = minutes < 10 ? `0${minutes}` : `${minutes}`
  const ss = seconds < 10 ? `0${seconds}` : `${seconds}`
  return `${mm}:${ss}`
}

@ComponentV2
export struct CartoonPlayerView {
  @Param uri: string = ''
  @Param videoId: string = ''
  @Param entryDurationMs: number = 0
  @Param autoPlay: boolean = true
  @Param sessionLeftMs: number = 0
  @Param dailyLeftMs: number = 0
  @Event onReady: (durationMs: number) => void = () => {}
  @Event onPlayedDelta: (deltaMs: number) => void = () => {}
  @Event onFinished: () => void = () => {}
  @Event onError: (message: string) => void = () => {}
  @Event onTooLong: () => void = () => {}

  @Local playing: boolean = false
  @Local currentTimeMs: number = 0
  @Local durationMsUi: number = 0
  @Local sliderValue: number = 0
  @Local videoReady: boolean = false
  @Local areaWidthVp: number = 0
  @Local areaHeightVp: number = 0

  private seeking: boolean = false
  private videoWidthPx: number = 0
  private videoHeightPx: number = 0

  private xComponentController: XComponentController = new XComponentController()
  private player: media.AVPlayer | null = null
  private file: fileIo.File | null = null
  private surfaceId: string = ''
  private lastTimeMs: number = -1
  private pendingDeltaMs: number = 0
  private durationMs: number = 0
  private released: boolean = false
  private finishEmitted: boolean = false
  private started: boolean = false
  private backgroundListener = (): void => {
    if (this.player !== null) {
      try {
        this.player.pause()
      } catch (_e) {
        // ignore
      }
    }
  }

  aboutToAppear(): void {
    try {
      getContext(this).eventHub.on('app_background', this.backgroundListener)
    } catch (error) {
      console.warn('CartoonPlayerView', `eventHub.on failed: ${JSON.stringify(error)}`)
    }
  }

  aboutToDisappear(): void {
    try {
      getContext(this).eventHub.off('app_background', this.backgroundListener)
    } catch (_e) {
      // ignore
    }
    this.releasePlayer()
  }

  private async startPlayback(): Promise<void> {
    if (this.started || this.released || this.uri === '') {
      return
    }
    this.started = true
    this.surfaceId = this.xComponentController.getXComponentSurfaceId()
    try {
      this.file = fileIo.openSync(this.uri, fileIo.OpenMode.READ_ONLY)
    } catch (error) {
      console.error('CartoonPlayerView', `open failed: ${JSON.stringify(error)}`)
      this.onError('这一集打不开了')
      return
    }
    try {
      const player = await media.createAVPlayer()
      // 页面可能在 await 期间已经被销毁：立刻释放，避免泄漏原生播放器
      if (this.released) {
        try {
          player.release()
        } catch (_e) {
          // ignore
        }
        return
      }
      this.player = player
      player.on('stateChange', (state: string) => {
        this.handleStateChange(state, player)
      })
      player.on('timeUpdate', (time: number) => {
        this.handleTimeUpdate(time)
      })
      player.on('endOfStream', () => {
        this.emitFinished()
      })
      player.on('error', (error: BusinessError) => {
        console.error('CartoonPlayerView', `AVPlayer error: ${error.code}, ${error.message}`)
        this.onError('播放出错了')
      })
      if (this.file === null) {
        try {
          player.release()
        } catch (_e) {
          // ignore
        }
        this.player = null
        return
      }
      player.url = `fd://${this.file.fd}`
    } catch (error) {
      console.error('CartoonPlayerView', `createAVPlayer failed: ${JSON.stringify(error)}`)
      this.onError('播放器打不开')
    }
  }

  private handleStateChange(state: string, player: media.AVPlayer): void {
    switch (state) {
      case 'initialized': {
        if (this.surfaceId !== '') {
          player.surfaceId = this.surfaceId
        }
        player.prepare()
        break
      }
      case 'prepared': {
        // videoScaleType 只能在 prepared/playing/paused/completed 状态设置（SDK 5400102）
        try {
          player.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT
        } catch (error) {
          console.warn('CartoonPlayerView', `set videoScaleType failed: ${JSON.stringify(error)}`)
        }
        const width = player.width
        const height = player.height
        if (width > 0 && height > 0) {
          this.videoWidthPx = width
          this.videoHeightPx = height
          this.videoReady = true
        }
        const decision = evaluatePreparedDuration(player.duration, this.entryDurationMs)
        this.durationMs = decision.effectiveDurationMs
        this.durationMsUi = this.durationMs
        this.onReady(this.durationMs)
        if (decision.shouldUpdateEntry && this.videoId !== '' && decision.effectiveDurationMs > 0) {
          getCartoonLibraryService().updateDuration(this.videoId, decision.effectiveDurationMs).catch((error: Error) => {
            console.warn('CartoonPlayerView', `updateDuration failed: ${error.message}`)
          })
        }
        if (decision.abort) {
          this.onTooLong()
          return
        }
        if (this.autoPlay) {
          try {
            player.play()
          } catch (_e) {
            // ignore
          }
        }
        break
      }
      case 'playing': {
        this.playing = true
        break
      }
      case 'paused': {
        this.playing = false
        this.flushDelta()
        break
      }
      case 'completed': {
        this.playing = false
        this.flushDelta()
        this.emitFinished()
        break
      }
      default:
        break
    }
  }

  private handleTimeUpdate(time: number): void {
    if (this.lastTimeMs >= 0) {
      const delta = time - this.lastTimeMs
      if (delta > 0 && delta <= 1500) {
        this.pendingDeltaMs += delta
      }
    }
    this.lastTimeMs = time
    this.currentTimeMs = time > 0 ? time : 0
    if (!this.seeking) {
      this.sliderValue = this.currentTimeMs
    }
    if (this.pendingDeltaMs >= 1000) {
      const whole = Math.floor(this.pendingDeltaMs / 1000) * 1000
      this.pendingDeltaMs -= whole
      this.onPlayedDelta(whole)
    }
  }

  private flushDelta(): void {
    const whole = Math.floor(this.pendingDeltaMs)
    if (whole > 0) {
      this.pendingDeltaMs -= whole
      this.onPlayedDelta(whole)
    }
  }

  private emitFinished(): void {
    if (this.finishEmitted || this.released) {
      return
    }
    this.finishEmitted = true
    this.playing = false
    this.flushDelta()
    this.onFinished()
  }

  private togglePlay(): void {
    if (this.player === null) {
      return
    }
    try {
      if (this.playing) {
        this.player.pause()
      } else {
        this.player.play()
      }
    } catch (error) {
      console.warn('CartoonPlayerView', `togglePlay failed: ${JSON.stringify(error)}`)
    }
  }

  private handleSliderChange(value: number, mode: SliderChangeMode): void {
    this.sliderValue = value
    this.currentTimeMs = value
    if (mode === SliderChangeMode.Begin) {
      this.seeking = true
      return
    }
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.seeking = false
      this.seekTo(value)
    }
  }

  private seekTo(ms: number): void {
    if (this.player === null) {
      return
    }
    const target = ms > 0 ? ms : 0
    // 跳转本身不计观看时长；把基准点移到目标位置，之后的增量照常统计
    this.lastTimeMs = target
    try {
      this.player.seek(target)
    } catch (error) {
      console.warn('CartoonPlayerView', `seek threw: ${JSON.stringify(error)}`)
    }
  }

  /** 按视频原始宽高比做 contain（vp 与 px 的换算因子在 min 两侧同时出现，可约掉） */
  private computeFitScale(): number {
    if (!this.videoReady || this.videoWidthPx <= 0 || this.videoHeightPx <= 0 ||
      this.areaWidthVp <= 0 || this.areaHeightVp <= 0) {
      return 0
    }
    return Math.min(this.areaWidthVp / this.videoWidthPx, this.areaHeightVp / this.videoHeightPx)
  }

  private getFittedWidth(): Length {
    const scale = this.computeFitScale()
    if (scale <= 0) {
      return '100%'
    }
    return this.videoWidthPx * scale
  }

  private getFittedHeight(): Length {
    const scale = this.computeFitScale()
    if (scale <= 0) {
      return '100%'
    }
    return this.videoHeightPx * scale
  }

  private releasePlayer(): void {
    this.released = true
    const player = this.player
    this.player = null
    if (player !== null) {
      try {
        player.release()
      } catch (_e) {
        // ignore
      }
    }
    if (this.file !== null) {
      try {
        fileIo.closeSync(this.file)
      } catch (_e) {
        // ignore
      }
      this.file = null
    }
  }

  build() {
    Stack() {
      XComponent({
        id: 'cartoon_video_surface',
        type: XComponentType.SURFACE,
        controller: this.xComponentController
      })
        .width(this.getFittedWidth())
        .height(this.getFittedHeight())
        .opacity(this.videoReady ? 1 : 0)
        .onLoad(() => {
          this.startPlayback()
        })

      Column() {
        Blank()
        Column({ space: 6 }) {
          Slider({
            value: this.sliderValue,
            min: 0,
            max: this.durationMsUi > 0 ? this.durationMsUi : 1,
            style: SliderStyle.OutSet
          })
            .width('100%')
            .blockColor(Color.White)
            .trackColor('#66FFFFFF')
            .selectedColor(Color.White)
            .onChange((value: number, mode: SliderChangeMode) => {
              this.handleSliderChange(value, mode)
            })

          Row({ space: 14 }) {
            Button(this.playing ? '暂停' : '播放')
              .fontSize(14)
              .fontColor(Color.White)
              .backgroundColor('#55000000')
              .height(36)
              .onClick(() => {
                this.togglePlay()
              })
            Text(`${formatClock(this.currentTimeMs)} / ${formatClock(this.durationMsUi)}`)
              .fontSize(13)
              .fontColor('#E6FFFFFF')
            Blank()
            Text(`本次还剩 ${Math.floor(this.sessionLeftMs / 60000)} 分钟 · 今天还剩 ${Math.floor(this.dailyLeftMs / 60000)} 分钟`)
              .fontSize(13)
              .fontColor('#E6FFFFFF')
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 18 })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.areaWidthVp = newArea.width as number
      this.areaHeightVp = newArea.height as number
    })
  }
}
