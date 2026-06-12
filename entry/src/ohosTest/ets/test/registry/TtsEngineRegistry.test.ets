import { describe, it, expect } from '@ohos/hypium'
import {
  registerTtsEngine,
  listTtsEngines,
  resolveTtsEngine,
  getFallbackTtsEngineId
} from '../../../../main/ets/services/registry/TtsEngineRegistry'
import { ITtsEngine } from '../../../../main/ets/services/tts/ITtsEngine'

class StubEngine implements ITtsEngine {
  init(_context: any): Promise<void> { return Promise.resolve() }
  speak(_text: string, _callback: any): Promise<void> { return Promise.resolve() }
  stop(): void {}
  isSpeaking(): boolean { return false }
  destroy(): void {}
}

function makeRegistration(id: string, displayName: string) {
  return {
    profile: {
      id,
      displayName,
      description: '...',
      requiresApiKey: false,
      iconSymbol: 'sys.symbol.speaker_wave_2_fill'
    },
    factory: (): ITtsEngine => new StubEngine()
  }
}

export default function ttsEngineRegistryTest() {
  describe('TtsEngineRegistry', () => {
    it('resolve returns null for unknown id', 0, () => {
      const engine = resolveTtsEngine('does-not-exist-xyz')
      expect(engine === null).assertTrue()
    })

    it('register + resolve returns factory output', 0, () => {
      registerTtsEngine(makeRegistration('stub-a', 'Stub A'))
      const engine = resolveTtsEngine('stub-a')
      expect(engine !== null).assertTrue()
    })

    it('register overwrites duplicate id', 0, () => {
      registerTtsEngine(makeRegistration('dup', 'First'))
      registerTtsEngine(makeRegistration('dup', 'Second'))
      const list = listTtsEngines()
      const dupMatches = list.filter((e) => e.profile.id === 'dup')
      expect(dupMatches.length).assertEqual(1)
      expect(dupMatches[0].profile.displayName).assertEqual('Second')
    })

    it('getFallbackTtsEngineId returns "system" when system registered', 0, () => {
      registerTtsEngine(makeRegistration('system', 'System'))
      expect(getFallbackTtsEngineId()).assertEqual('system')
    })
  })
}
