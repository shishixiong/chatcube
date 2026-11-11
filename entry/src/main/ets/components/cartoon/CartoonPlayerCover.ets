/**
 * 全屏动画片播放覆盖层（Index 根节点 bindContentCover 的宿主内容）。
 *
 * 覆盖整个窗口（含分栏、底部 Tab、待答浮条），强制横屏；关闭后回到聊天。
 * settled 守卫保证工具 Promise 只 resolve 一次。
 */

import { window } from '@kit.ArkUI'
import { CartoonPlayerView } from './CartoonPlayerView'
import { CartoonEntry, CartoonPlayerRouteParams } from '../../models/CartoonModels'
import { buildPlaybackResult } from '../../utils/CartoonQuotaMath'
import { getCartoonWatchService } from '../../services/CartoonWatchService'
import { getCartoonLibraryService } from '../../services/CartoonLibraryService'
import { getToolExecutionService } from '../../services/ToolExecutionService'
import { endCartoonPlayerSession } from '../../utils/CartoonPlayerSession'

function emptyCartoonPlayerParams(): CartoonPlayerRouteParams {
  const params: CartoonPlayerRouteParams = {
    toolCallId: '',
    videoId: '',
    title: '',
    durationMs: 0,
    uri: ''
  }
  return params
}

@ComponentV2
export struct CartoonPlayerCover {
  @Param params: CartoonPlayerRouteParams = emptyCartoonPlayerParams()
  @Event onClose: () => void = () => {}

  @Local watchedMs: number = 0
  @Local sessionLeftMs: number = 0
  @Local dailyLeftMs: number = 0
  @Local finishedOverlay: boolean = false
  @Local errorMessage: string = ''

  private settled: boolean = false
  private playWindow: window.Window | null = null
  private savedOrientation: window.Orientation = window.Orientation.UNSPECIFIED
  private finishTimer: number = -1

  aboutToAppear(): void {
    this.applyLandscape()
    this.initQuota()
    if (this.params.uri === '' || this.params.toolCallId === '') {
      this.errorMessage = '这一集打不开了'
      this.finishTimer = setTimeout(() => {
        this.settle('error', false)
      }, 1200)
    }
  }

  aboutToDisappear(): void {
    if (this.finishTimer >= 0) {
      clearTimeout(this.finishTimer)
      this.finishTimer = -1
    }
    endCartoonPlayerSession(this.params.toolCallId)
    if (!this.settled) {
      this.settle('closed', false)
    } else {
      this.restoreOrientation()
    }
  }

  private async applyLandscape(): Promise<void> {
    try {
      const win = await window.getLastWindow(getContext(this))
      this.playWindow = win
      this.savedOrientation = win.getPreferredOrientation()
      await win.setPreferredOrientation(window.Orientation.LANDSCAPE)
    } catch (error) {
      console.warn('CartoonPlayerCover', `setPreferredOrientation failed: ${JSON.stringify(error)}`)
    }
  }

  private restoreOrientation(): void {
    if (this.playWindow === null) {
      return
    }
    try {
      this.playWindow.setPreferredOrientation(this.savedOrientation)
    } catch (error) {
      console.warn('CartoonPlayerCover', `restore orientation failed: ${JSON.stringify(error)}`)
    }
  }

  private async initQuota(): Promise<void> {
    try {
      const snapshot = await getCartoonWatchService().snapshot()
      this.sessionLeftMs = Math.max(0, snapshot.sessionLimitMs - snapshot.sessionMs)
      this.dailyLeftMs = Math.max(0, snapshot.dayLimitMs - snapshot.dayMs)
    } catch (error) {
      console.error('CartoonPlayerCover', `initQuota failed: ${JSON.stringify(error)}`)
    }
  }

  private handlePlayedDelta(deltaMs: number): void {
    this.watchedMs += deltaMs
    this.sessionLeftMs = Math.max(0, this.sessionLeftMs - deltaMs)
    this.dailyLeftMs = Math.max(0, this.dailyLeftMs - deltaMs)
    getCartoonWatchService().addWatched(deltaMs).catch((error: Error) => {
      console.error('CartoonPlayerCover', `addWatched failed: ${error.message}`)
    })
  }

  private handleFinished(): void {
    if (this.settled || this.finishedOverlay) {
      return
    }
    this.finishedOverlay = true
    this.finishTimer = setTimeout(() => {
      this.finishTimer = -1
      this.settle('finished', true)
    }, 1000)
  }

  private handleError(message: string): void {
    if (this.settled) {
      return
    }
    this.errorMessage = message
    this.finishTimer = setTimeout(() => {
      this.finishTimer = -1
      this.settle('error', false)
    }, 1500)
  }

  private requestExit(): void {
    if (this.settled) {
      return
    }
    if (this.watchedMs <= 0) {
      this.settle('closed', false)
      return
    }
    AlertDialog.show({
      title: '还没看完',
      message: '要关掉动画片吗？',
      autoCancel: false,
      primaryButton: {
        value: '继续看',
        action: (): void => {}
      },
      secondaryButton: {
        value: '关掉',
        action: (): void => {
          this.settle('closed', false)
        }
      }
    })
  }

  private async settle(endedBy: string, completed: boolean): Promise<void> {
    if (this.settled) {
      return
    }
    this.settled = true
    const watch = getCartoonWatchService()
    try {
      await watch.flush()
    } catch (error) {
      console.error('CartoonPlayerCover', `flush failed: ${JSON.stringify(error)}`)
    }
    const snapshot = await watch.snapshot()
    const entry: CartoonEntry = {
      id: this.params.videoId,
      uri: this.params.uri,
      title: this.params.title,
      tags: '',
      durationMs: this.params.durationMs,
      addedAt: 0,
      status: 'ok',
      seriesTitle: '',
      season: 0,
      episode: 0,
      lastWatchedAt: 0
    }
    const result = buildPlaybackResult(entry, this.watchedMs, completed, endedBy, snapshot)
    if (completed && this.params.videoId !== '') {
      try {
        await getCartoonLibraryService().markWatched(this.params.videoId)
      } catch (error) {
        console.error('CartoonPlayerCover', `markWatched failed: ${JSON.stringify(error)}`)
      }
    }
    try {
      getToolExecutionService().resolvePendingAnswer(this.params.toolCallId, JSON.stringify(result))
    } catch (error) {
      console.error('CartoonPlayerCover', `resolvePendingAnswer failed: ${JSON.stringify(error)}`)
    }
    watch.markPlaybackEnded()
    endCartoonPlayerSession(this.params.toolCallId)
    this.restoreOrientation()
    this.onClose()
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.params.uri !== '') {
        CartoonPlayerView({
          uri: this.params.uri,
          videoId: this.params.videoId,
          entryDurationMs: this.params.durationMs,
          autoPlay: true,
          sessionLeftMs: this.sessionLeftMs,
          dailyLeftMs: this.dailyLeftMs,
          onReady: (_durationMs: number): void => {},
          onPlayedDelta: (deltaMs: number): void => {
            this.handlePlayedDelta(deltaMs)
          },
          onFinished: (): void => {
            this.handleFinished()
          },
          onError: (message: string): void => {
            this.handleError(message)
          },
          onTooLong: (): void => {
            this.handleError('这一集太长了')
          }
        })
      }

      Row({ space: 12 }) {
        Text(this.params.title !== '' ? this.params.title : '动画片')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Button('✕')
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor('#55000000')
          .width(40)
          .height(40)
          .onClick(() => {
            this.requestExit()
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 14 })
      .hitTestBehavior(HitTestMode.Transparent)

      if (this.finishedOverlay) {
        Column() {
          Text('看完啦')
            .fontSize(26)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#88000000')
      }

      if (this.errorMessage !== '') {
        Column() {
          Text(this.errorMessage)
            .fontSize(18)
            .fontColor(Color.White)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#88000000')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
