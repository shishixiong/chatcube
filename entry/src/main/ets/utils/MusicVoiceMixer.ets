/**
 * 音符小耳朵混音器：把「在哪个采样点开始」的音排期成可见样本，
 * 由 MusicToneService 的 AudioRenderer writeData 回调反复拉取。
 * 一个排期项 = 一个音（含该音色全部谐波声部）。纯逻辑，可单测。
 */

import { MusicTimbre } from './MusicEarData'
import { buildTimbreVoices, renderVoiceInto, VoiceSpec } from './MusicToneSynth'

const MAX_NOTES: number = 8
/** 混音器采样率；fillBuffer 的 sampleRate 必须一致，否则回收时机错位。 */
export const MIXER_SAMPLE_RATE: number = 48000

interface ScheduledNote {
  startSample: number
  specs: VoiceSpec[]
  durationSamples: number
}

function durationSamplesOf(specs: VoiceSpec[]): number {
  let longest = 0
  for (let i = 0; i < specs.length; i++) {
    const samples = Math.floor(specs[i].durationSec * MIXER_SAMPLE_RATE)
    if (samples > longest) {
      longest = samples
    }
  }
  return longest
}

export class MusicVoiceMixer {
  private notes: ScheduledNote[] = []
  private cursor: number = 0

  scheduleNote(freq: number, timbre: MusicTimbre, delaySamples: number): void {
    const specs = buildTimbreVoices(timbre, freq)
    this.push({
      startSample: this.cursor + Math.max(0, delaySamples),
      specs,
      durationSamples: durationSamplesOf(specs)
    })
  }

  scheduleSequence(freqs: number[], timbre: MusicTimbre, noteSamples: number, gapSamples: number): void {
    for (let i = 0; i < freqs.length; i++) {
      const specs = buildTimbreVoices(timbre, freqs[i])
      this.push({
        startSample: this.cursor + i * (noteSamples + gapSamples),
        specs,
        durationSamples: durationSamplesOf(specs)
      })
    }
  }

  fillBuffer(out: Float32Array, sampleRate: number): void {
    out.fill(0)
    for (let i = 0; i < this.notes.length; i++) {
      const note = this.notes[i]
      const offset = note.startSample - this.cursor
      for (let j = 0; j < note.specs.length; j++) {
        renderVoiceInto(out, offset, note.specs[j], sampleRate)
      }
    }
    this.cursor += out.length
    this.dropFinished()
  }

  clear(): void {
    this.notes = []
  }

  getActiveVoiceCount(): number {
    return this.notes.length
  }

  getCursor(): number {
    return this.cursor
  }

  private push(note: ScheduledNote): void {
    if (this.notes.length >= MAX_NOTES) {
      this.notes.shift()
    }
    this.notes.push(note)
  }

  private dropFinished(): void {
    const alive: ScheduledNote[] = []
    for (let i = 0; i < this.notes.length; i++) {
      const note = this.notes[i]
      if (note.startSample + note.durationSamples > this.cursor) {
        alive.push(note)
      }
    }
    this.notes = alive
  }
}
