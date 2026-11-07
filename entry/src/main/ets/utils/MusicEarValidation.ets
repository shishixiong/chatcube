/**
 * music_ear 工具参数预校验：坏题直接回 should_retry，不渲染不可玩的卡片。
 */

import { MusicDrill } from './MusicEarData'
import { parseDrill } from './MusicEarLogic'

export interface MusicEarArgsValidation {
  ok: boolean
  drill: string
  difficulty: number
  error: string
}

interface MusicEarArgsShape {
  drill?: string
  difficulty?: number
}

function fail(message: string): MusicEarArgsValidation {
  const result: MusicEarArgsValidation = {
    ok: false,
    drill: '',
    difficulty: 1,
    error: message
  }
  return result
}

export function validateMusicEarArgs(argsJson: string): MusicEarArgsValidation {
  let raw: MusicEarArgsShape
  try {
    raw = JSON.parse(argsJson) as MusicEarArgsShape
  } catch (err) {
    return fail('参数不是合法 JSON')
  }
  if (raw === null || raw === undefined) {
    return fail('参数为空')
  }
  const drillText = raw.drill === undefined ? '' : raw.drill
  const parsed: MusicDrill | null = parseDrill(drillText)
  if (parsed === null) {
    return fail(`drill「${drillText}」不支持，只能是 high_low / echo / guess_song`)
  }
  const difficulty = raw.difficulty
  if (difficulty === undefined || !Number.isInteger(difficulty) || difficulty < 1 || difficulty > 3) {
    return fail('difficulty 必须是 1、2 或 3 的整数')
  }
  const result: MusicEarArgsValidation = {
    ok: true,
    drill: parsed,
    difficulty,
    error: ''
  }
  return result
}
