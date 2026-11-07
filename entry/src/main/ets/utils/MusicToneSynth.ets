/**
 * 纯 PCM 波形合成（音符小耳朵）：把音色拆成若干振荡器声部，逐个叠加进
 * Float32 缓冲。不依赖音频 API，可单测。
 */

import { MusicTimbre } from './MusicEarData'

export type OscillatorWave = 'sine' | 'triangle'

export interface VoiceSpec {
  freq: number
  gain: number
  durationSec: number
  attackSec: number
  wave: OscillatorWave
}

const FADE_OUT_SEC: number = 0.01

interface Harmonic {
  ratio: number
  gain: number
  wave: OscillatorWave
}

interface TimbreRecipe {
  durationSec: number
  harmonics: Harmonic[]
}

const PIANO: TimbreRecipe = {
  durationSec: 1.2,
  harmonics: [
    { ratio: 1, gain: 0.55, wave: 'triangle' },
    { ratio: 2, gain: 0.22, wave: 'sine' },
    { ratio: 3, gain: 0.12, wave: 'sine' }
  ]
}

const XYLOPHONE: TimbreRecipe = {
  durationSec: 0.5,
  harmonics: [
    { ratio: 1, gain: 0.60, wave: 'sine' },
    { ratio: 3, gain: 0.20, wave: 'sine' },
    { ratio: 4.2, gain: 0.10, wave: 'sine' }
  ]
}

const MUSICBOX: TimbreRecipe = {
  durationSec: 0.9,
  harmonics: [
    { ratio: 1, gain: 0.45, wave: 'sine' },
    { ratio: 2.76, gain: 0.20, wave: 'sine' },
    { ratio: 5.4, gain: 0.14, wave: 'sine' },
    { ratio: 2, gain: 0.12, wave: 'triangle' }
  ]
}

function recipeOf(timbre: MusicTimbre): TimbreRecipe {
  if (timbre === 'xylophone') {
    return XYLOPHONE
  }
  if (timbre === 'musicbox') {
    return MUSICBOX
  }
  return PIANO
}

export function buildTimbreVoices(timbre: MusicTimbre, baseFreq: number): VoiceSpec[] {
  const recipe = recipeOf(timbre)
  const voices: VoiceSpec[] = []
  for (let i = 0; i < recipe.harmonics.length; i++) {
    const harmonic = recipe.harmonics[i]
    const voice: VoiceSpec = {
      freq: baseFreq * harmonic.ratio,
      gain: harmonic.gain,
      durationSec: recipe.durationSec,
      attackSec: 0.005,
      wave: harmonic.wave
    }
    voices.push(voice)
  }
  return voices
}

function shape(wave: OscillatorWave, phase: number): number {
  if (wave === 'triangle') {
    return (2 / Math.PI) * Math.asin(Math.sin(phase))
  }
  return Math.sin(phase)
}

/**
 * 把单个声部叠加进 `out`；`startSample` 可为负（窗口从音中途开始）。
 * 返回实际写入的采样数。
 */
export function renderVoiceInto(
  out: Float32Array,
  startSample: number,
  spec: VoiceSpec,
  sampleRate: number
): number {
  const totalSamples = Math.floor(spec.durationSec * sampleRate)
  let written = 0
  for (let i = 0; i < totalSamples; i++) {
    const abs = startSample + i
    if (abs >= out.length) {
      break
    }
    const t = i / sampleRate
    if (abs < 0 || t > spec.durationSec) {
      continue
    }
    let env = t < spec.attackSec
      ? t / spec.attackSec
      : Math.exp(-5 * (t - spec.attackSec) / spec.durationSec)
    const fadeStart = spec.durationSec - FADE_OUT_SEC
    if (t > fadeStart) {
      env = env * Math.max(0, (spec.durationSec - t) / FADE_OUT_SEC)
    }
    const phase = 2 * Math.PI * spec.freq * t
    out[abs] += shape(spec.wave, phase) * spec.gain * env
    written++
  }
  return written
}
