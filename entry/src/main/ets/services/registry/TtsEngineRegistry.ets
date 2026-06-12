import { ITtsEngine } from '../tts/ITtsEngine'
import {
  TtsEngineRegistration,
  TtsEngineAvailability
} from '../../models/TtsEngineProfile'
import { evaluateTtsEngineAvailability } from '../../utils/TtsEngineAvailabilityUtils'
import { getAppSettingsState } from '../../state/AppSettingsState'
import { TTS_FALLBACK_ENGINE_ID } from '../../config/TtsConfig'

// ============ 注册表状态 ============
const REGISTRATIONS: Map<string, TtsEngineRegistration> = new Map()

// ============ 注册 API ============
export function registerTtsEngine(registration: TtsEngineRegistration): void {
  if (REGISTRATIONS.has(registration.profile.id)) {
    console.warn('TtsEngineRegistry',
      `engine '${registration.profile.id}' already registered, overwriting`)
  }
  REGISTRATIONS.set(registration.profile.id, registration)
}

// ============ 查询 API ============

// 列出所有已注册引擎, 附带运行时可用性
export function listTtsEngines(): TtsEngineAvailability[] {
  const result: TtsEngineAvailability[] = []
  const providers = getAppSettingsState().providers
  REGISTRATIONS.forEach((reg) => {
    result.push(evaluateTtsEngineAvailability(reg.profile, providers))
  })
  return result
}

// 按 id 取一个引擎实例, 不存在或工厂抛错时返回 null
export function resolveTtsEngine(id: string): ITtsEngine | null {
  const reg = REGISTRATIONS.get(id)
  if (reg === undefined) {
    return null
  }
  try {
    return reg.factory()
  } catch (err) {
    console.error('TtsEngineRegistry',
      `factory for '${id}' threw: ${JSON.stringify(err)}`)
    return null
  }
}

// 仅用于 TTSService 的 fallback 链
export function getFallbackTtsEngineId(): string {
  return REGISTRATIONS.has(TTS_FALLBACK_ENGINE_ID) ? TTS_FALLBACK_ENGINE_ID : ''
}
