/**
 * 音乐生成工具结果展示组件
 *
 * 在消息气泡的 ToolStepContent 展开区域中渲染, 解析 toolResult JSON
 * 并展示生成的音频播放器。每条音频 = 播放/暂停按钮 + 文件名 + 时长 + 进度条。
 *
 * 复用 MusicAudioPlayer 单例 (services/MusicAudioPlayer.ets) 进行实际播放。
 * 与 ImageGenerationToolResult 同构: 同层目录、同 Param/Event 风格。
 */

import { MusicAudioPlayer } from '../../services/MusicAudioPlayer'

class MusicGenDisplayItem {
  filePath: string = ''
  fileName: string = ''
  mimeType: string = ''
  prompt: string = ''
  audioLengthMs: number = 0

  constructor(filePath: string, fileName: string, mimeType: string, prompt: string, audioLengthMs: number) {
    this.filePath = filePath
    this.fileName = fileName
    this.mimeType = mimeType
    this.prompt = prompt
    this.audioLengthMs = audioLengthMs
  }
}

function parseOutput(raw: string): MusicGenDisplayItem[] {
  const trimmed = raw.trim()
  if (trimmed === '') {
    return []
  }
  try {
    const obj = JSON.parse(trimmed) as Record<string, Object>
    // MusicGenerationOutput format: { audio: [{ filePath, mimeType, prompt, audioLengthMs }] }
    // 同时兼容错误输出 { error: string } - 返回空数组, 上层走 error 分支
    if (obj['error'] !== undefined && typeof obj['error'] === 'string') {
      return []
    }
    const audioArr = obj['audio'] as Object[] | undefined
    if (audioArr === undefined || audioArr === null) {
      return []
    }
    const items: MusicGenDisplayItem[] = []
    for (let i = 0; i < audioArr.length; i++) {
      const a = audioArr[i] as Record<string, Object>
      const fp = a['filePath'] as string
      if (fp === undefined || fp.trim() === '') {
        continue
      }
      const mime = a['mimeType'] as string
      const prompt = a['prompt'] as string
      const lengthMs = a['audioLengthMs'] as number
      const fileName = extractFileName(fp)
      items.push(new MusicGenDisplayItem(
        fp.trim(),
        fileName,
        mime !== undefined ? mime : '',
        prompt !== undefined ? prompt : '',
        typeof lengthMs === 'number' ? Math.max(0, Math.floor(lengthMs)) : 0
      ))
    }
    return items
  } catch (_e) {
    return []
  }
}

function extractFileName(filePath: string): string {
  const idx = filePath.lastIndexOf('/')
  if (idx < 0 || idx === filePath.length - 1) {
    return filePath
  }
  return filePath.substring(idx + 1)
}

function extractError(raw: string): string {
  const trimmed = raw.trim()
  if (trimmed === '') {
    return ''
  }
  try {
    const obj = JSON.parse(trimmed) as Record<string, Object>
    const err = obj['error'] as string
    if (err !== undefined && err.trim() !== '') {
      return err
    }
  } catch (_e) {
  }
  return ''
}

function formatMs(ms: number): string {
  if (!Number.isFinite(ms) || ms < 0) {
    return '0:00'
  }
  const totalSec = Math.floor(ms / 1000)
  const hours = Math.floor(totalSec / 3600)
  const min = Math.floor((totalSec % 3600) / 60)
  const sec = totalSec % 60
  if (hours > 0) {
    return `${hours}:${min.toString().padStart(2, '0')}:${sec.toString().padStart(2, '0')}`
  }
  return `${min}:${sec.toString().padStart(2, '0')}`
}

@ComponentV2
export struct MusicGenerationToolResult {
  @Param toolResult: string = ''
  @Local private itemsCache: MusicGenDisplayItem[] = []
  @Local private errorMessageCache: string = ''
  @Local private rawCache: string = ''

  // 内部 @Local: 当前播放中条目索引 (-1 = 无)
  @Local private playingIndex: number = -1
  // 暂停状态下的条目索引 (-1 = 无, 与 playingIndex 互斥)
  @Local private pausedIndex: number = -1
  // 播放完毕的条目索引 (-1 = 无, 可点击重新播放)
  @Local private completedIndex: number = -1
  // 播放出错的条目索引 (-1 = 无)
  @Local private errorIndex: number = -1
  // 当前条目播放进度 (ms)
  @Local private currentTimeMs: number = 0
  // 当前条目总时长 (ms)
  @Local private durationMs: number = 0
  // 错误信息 (播放失败时显示)
  @Local private playError: string = ''

  private player: MusicAudioPlayer = MusicAudioPlayer.getInstance()
  private progressTimerId: number = -1
  // 保存 onPrepared 回调闭包, 用于 aboutToDisappear 时移除非本组件的监听
  // (MusicAudioPlayer 当前是单例 + 单回调设计, 不支持多 listener, 这里只能靠 aboutToDisappear 主动 stop)

  @Computed
  get items(): MusicGenDisplayItem[] {
    if (this.toolResult !== this.rawCache) {
      this.rawCache = this.toolResult
      this.itemsCache = parseOutput(this.toolResult)
      this.errorMessageCache = this.itemsCache.length === 0 ? extractError(this.toolResult) : ''
    }
    return this.itemsCache
  }

  @Computed
  get errorMessage(): string {
    if (this.toolResult !== this.rawCache) {
      this.rawCache = this.toolResult
      this.itemsCache = parseOutput(this.toolResult)
      this.errorMessageCache = this.itemsCache.length === 0 ? extractError(this.toolResult) : ''
    }
    return this.errorMessageCache
  }

  @Computed
  get hasItems(): boolean {
    return this.items.length > 0
  }

  aboutToDisappear(): void {
    this.stopProgressTimer()
    // 单例播放器: 如果当前正在播的曲目属于本组件, 主动停止以避免泄漏
    // (用户切走/切到其他页面时不应继续播)
    this.player.stop()
    this.playingIndex = -1
    this.pausedIndex = -1
    this.completedIndex = -1
    this.errorIndex = -1
    this.currentTimeMs = 0
    this.durationMs = 0
    this.playError = ''
  }

  build() {
    if (this.hasItems) {
      Column({ space: 8 }) {
        ForEach(this.items, (item: MusicGenDisplayItem, index: number) => {
          this.MusicCard(item, index)
        }, (item: MusicGenDisplayItem, index: number) => `${item.filePath}_${index}`)
      }
      .width('100%')
      .margin({ top: 6 })
      .alignItems(HorizontalAlign.Start)
    } else if (this.errorMessage !== '') {
      Text(this.errorMessage)
        .fontSize(12)
        .fontColor($r('app.color.status_error'))
        .margin({ top: 6 })
    }
  }

  @Builder
  private MusicCard(item: MusicGenDisplayItem, index: number) {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        // 圆形播放/暂停按钮
        Button() {
          SymbolGlyph(this.playingIndex === index ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
            .fontSize(20)
            .fontColor([Color.White])
        }
        .type(ButtonType.Circle)
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.primary'))
        .onClick(() => {
          this.togglePlay(item, index)
        })

        Column({ space: 2 }) {
          // 文件名 + 时长
          Row() {
            Text(item.fileName)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            Text(this.formatCurrentDuration(index, item))
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ left: 8 })
          }
          .width('100%')

          // 进度条: 用 Progress 组件展示百分比
          Progress({
            value: this.computeProgressPercent(index, item),
            total: 100,
            type: ProgressType.Linear
          })
            .width('100%')
            .height(4)
            .color($r('app.color.primary'))
            .backgroundColor($r('app.color.divider'))
            .style({ strokeWidth: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.playError !== '' && this.errorIndex === index) {
        Text(this.playError)
          .fontSize(11)
          .fontColor($r('app.color.status_error'))
          .width('100%')
          .margin({ left: 50 })
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor($r('app.color.divider'))
    .borderRadius(10)
  }

  // 计算当前条目的进度百分比 (0-100)
  private computeProgressPercent(index: number, item: MusicGenDisplayItem): number {
    if (this.playingIndex !== index && this.pausedIndex !== index && this.completedIndex !== index) {
      return 0
    }
    const total = this.durationMs > 0 ? this.durationMs : item.audioLengthMs
    if (total <= 0) {
      return 0
    }
    const pct = Math.floor((this.currentTimeMs / total) * 100)
    if (pct < 0) {
      return 0
    }
    if (pct > 100) {
      return 100
    }
    return pct
  }

  // 当前显示的时长文本
  private formatCurrentDuration(index: number, item: MusicGenDisplayItem): string {
    if (this.playingIndex === index || this.pausedIndex === index || this.completedIndex === index) {
      const total = this.durationMs > 0 ? this.durationMs : item.audioLengthMs
      return `${formatMs(this.currentTimeMs)} / ${formatMs(total)}`
    }
    return formatMs(item.audioLengthMs)
  }

  // 切换播放/暂停
  private async togglePlay(item: MusicGenDisplayItem, index: number): Promise<void> {
    this.playError = ''
    this.errorIndex = -1

    // 1) 若点击的是正在播放的条目 → 暂停 (button 回到 ▶, 进度冻结)
    if (this.playingIndex === index) {
      this.player.pause()
      this.stopProgressTimer()
      this.playingIndex = -1
      this.pausedIndex = index
      return
    }
    // 2) 若点击的是已暂停的同一条目 → 恢复 (button 切回 ⏸, 进度继续走)
    if (this.pausedIndex === index) {
      this.player.resume()
      this.playingIndex = index
      this.pausedIndex = -1
      this.startProgressTimer()
      return
    }
    // 3) 若点击的是已播完的条目 → 从头重新播放 (button 切回 ⏸, 进度归零)

    // 切换到另一首 (或重播已完成的): 先停旧的
    this.stopProgressTimer()
    this.player.stop()
    this.playingIndex = -1
    this.pausedIndex = -1
    this.completedIndex = -1
    this.currentTimeMs = 0
    this.durationMs = 0

    // 播放新条目
    this.playingIndex = index
    this.durationMs = item.audioLengthMs > 0 ? item.audioLengthMs : 0
    this.currentTimeMs = 0
    try {
      await this.player.play(item.filePath, {
        onPrepared: (durationMs: number): void => {
          // 用 prepared 返回的真实时长覆盖 audioLengthMs 估算值
          if (durationMs > 0) {
            this.durationMs = durationMs
          }
        },
        onPlay: (): void => {
          this.startProgressTimer()
        },
        onPause: (): void => {
          this.stopProgressTimer()
        },
        onComplete: (): void => {
          this.stopProgressTimer()
          this.currentTimeMs = this.durationMs
          // 切回 ▶ 状态: playingIndex=-1 + completedIndex=index
          // 下一轮用户点击走 togglePlay 第 3 分支 (重新播放)
          this.playingIndex = -1
          this.completedIndex = index
        },
        onError: (msg: string): void => {
          this.stopProgressTimer()
          this.playingIndex = -1
          this.pausedIndex = -1
          this.completedIndex = -1
          this.errorIndex = index
          this.currentTimeMs = 0
          this.durationMs = 0
          this.playError = msg
        }
      })
      // 同步一次时长: 部分 HarmonyOS 版本 onPrepared 在 play() 内部 await 期间还没派发, 这里补一次保险读取
      const reported = this.player.getDurationMs()
      if (reported > 0) {
        this.durationMs = reported
      }
    } catch (error) {
      this.playingIndex = -1
      this.pausedIndex = -1
      this.completedIndex = -1
      this.errorIndex = index
      this.durationMs = 0
      this.currentTimeMs = 0
      this.playError = `播放失败: ${JSON.stringify(error)}`
    }
  }

  private startProgressTimer(): void {
    this.stopProgressTimer()
    this.progressTimerId = setInterval(() => {
      const t = this.player.getCurrentTimeMs()
      // 触发响应式刷新 (ArkTS 2 重 @Local 直接赋值即可)
      this.currentTimeMs = t
    }, 250)
  }

  private stopProgressTimer(): void {
    if (this.progressTimerId >= 0) {
      clearInterval(this.progressTimerId)
      this.progressTimerId = -1
    }
  }
}
