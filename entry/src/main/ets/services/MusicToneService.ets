/**
 * 音符小耳朵音频服务：AudioRenderer + 混音器，把纯逻辑排期的音符播出来。
 * 单例；未启动/静音时所有播放接口静默降级，绝不抛到 UI。
 */

import { audio } from '@kit.AudioKit'
import { MusicNote, MusicTimbre, MUSIC_NOTE_FREQ } from '../utils/MusicEarData'
import { MusicVoiceMixer, MIXER_SAMPLE_RATE } from '../utils/MusicVoiceMixer'
import { hilog } from '@kit.PerformanceAnalysisKit'

const CHANNELS: number = 2
const BYTES_PER_FRAME: number = CHANNELS * 2
const MASTER_GAIN: number = 0.8
const DOMAIN: number = 0x0000
const TAG: string = 'MusicToneService'

interface SequenceTimer {
  token: number
  timerId: number
}

export class MusicToneService {
  private static instance: MusicToneService | null = null

  static getInstance(): MusicToneService {
    if (MusicToneService.instance === null) {
      MusicToneService.instance = new MusicToneService()
    }
    return MusicToneService.instance
  }

  private renderer: audio.AudioRenderer | null = null
  private mixer: MusicVoiceMixer = new MusicVoiceMixer()
  private muted: boolean = false
  private starting: Promise<boolean> | null = null
  private sequenceTimers: SequenceTimer[] = []
  private nextToken: number = 1
  // 回调线程上不分配：复用一个足够大的混音缓冲
  private mixBuffer: Float32Array = new Float32Array(0)

  private constructor() {
  }

  async ensureStarted(): Promise<boolean> {
    if (this.renderer !== null) {
      return true
    }
    if (this.starting !== null) {
      return this.starting
    }
    this.starting = this.startRenderer()
    const ok = await this.starting
    this.starting = null
    return ok
  }

  private async startRenderer(): Promise<boolean> {
    try {
      const streamInfo: audio.AudioStreamInfo = {
        samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
        channels: audio.AudioChannel.CHANNEL_2,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      }
      const rendererInfo: audio.AudioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_GAME,
        rendererFlags: 0
      }
      const options: audio.AudioRendererOptions = {
        streamInfo,
        rendererInfo
      }
      const renderer = await audio.createAudioRenderer(options)
      renderer.on('writeData', (data: ArrayBuffer) => {
        this.fillPcm(data)
      })
      await renderer.start()
      this.renderer = renderer
      return true
    } catch (err) {
      hilog.warn(DOMAIN, TAG, `startRenderer failed (ignored): ${String(err)}`)
      this.renderer = null
      return false
    }
  }

  private fillPcm(data: ArrayBuffer): void {
    const frameCount = Math.floor(data.byteLength / BYTES_PER_FRAME)
    if (frameCount <= 0) {
      return
    }
    const pcm = new Int16Array(data)
    if (this.muted) {
      pcm.fill(0)
      return
    }
    if (this.mixBuffer.length !== frameCount) {
      this.mixBuffer = new Float32Array(frameCount)
    }
    const mix = this.mixBuffer
    this.mixer.fillBuffer(mix, MIXER_SAMPLE_RATE)
    for (let i = 0; i < frameCount; i++) {
      let sample = mix[i] * MASTER_GAIN
      if (sample > 1) {
        sample = 1
      } else if (sample < -1) {
        sample = -1
      }
      const value = Math.round(sample * 32767)
      pcm[i * CHANNELS] = value
      pcm[i * CHANNELS + 1] = value
    }
  }

  playNote(note: MusicNote, timbre: MusicTimbre): void {
    if (this.renderer === null || this.muted) {
      return
    }
    this.mixer.scheduleNote(MUSIC_NOTE_FREQ[note], timbre, 0)
  }

  /**
   * 一次排期整段旋律，并用定时器逐音回调（用于 UI 高亮当前音）。
   * 返回 token，供 cancelSequence 撤销。
   */
  playSequence(
    notes: MusicNote[],
    timbre: MusicTimbre,
    noteMs: number,
    gapMs: number,
    onNote?: (index: number) => void
  ): number {
    const token = this.nextToken
    this.nextToken += 1
    if (this.renderer === null || this.muted || notes.length === 0) {
      return token
    }
    const freqs: number[] = []
    for (let i = 0; i < notes.length; i++) {
      freqs.push(MUSIC_NOTE_FREQ[notes[i]])
    }
    const noteSamples = Math.floor(noteMs * MIXER_SAMPLE_RATE / 1000)
    const gapSamples = Math.floor(gapMs * MIXER_SAMPLE_RATE / 1000)
    this.mixer.scheduleSequence(freqs, timbre, noteSamples, gapSamples)
    if (onNote !== undefined) {
      for (let i = 0; i < notes.length; i++) {
        const index = i
        const timerId = setTimeout(() => {
          onNote(index)
        }, i * (noteMs + gapMs))
        this.sequenceTimers.push({ token, timerId })
      }
    }
    return token
  }

  cancelSequence(token: number): void {
    const keep: SequenceTimer[] = []
    for (let i = 0; i < this.sequenceTimers.length; i++) {
      const entry = this.sequenceTimers[i]
      if (entry.token === token) {
        clearTimeout(entry.timerId)
      } else {
        keep.push(entry)
      }
    }
    this.sequenceTimers = keep
  }

  stopAll(): void {
    this.clearTimers()
    this.mixer.clear()
  }

  setMuted(muted: boolean): void {
    this.muted = muted
    if (muted) {
      this.stopAll()
    }
  }

  isMuted(): boolean {
    return this.muted
  }

  release(): void {
    this.clearTimers()
    this.mixer.clear()
    const renderer = this.renderer
    this.renderer = null
    if (renderer === null) {
      return
    }
    renderer.off('writeData')
    renderer.stop().then(() => {
      renderer.release()
    }).catch((err: Object) => {
      hilog.warn(DOMAIN, TAG, `release failed (ignored): ${String(err)}`)
    })
  }

  private clearTimers(): void {
    for (let i = 0; i < this.sequenceTimers.length; i++) {
      clearTimeout(this.sequenceTimers[i].timerId)
    }
    this.sequenceTimers = []
  }
}

export function getMusicToneService(): MusicToneService {
  return MusicToneService.getInstance()
}
