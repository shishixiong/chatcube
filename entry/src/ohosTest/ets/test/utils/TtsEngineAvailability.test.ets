import { describe, it, expect } from '@ohos/hypium'
import { evaluateTtsEngineAvailability } from '../../../../main/ets/utils/TtsEngineAvailabilityUtils'
import { TtsEngineProfile } from '../../../../main/ets/models/TtsEngineProfile'
import { ModelProvider, ProviderType } from '../../../../main/ets/models/ChatModels'

const systemProfile: TtsEngineProfile = {
  id: 'system',
  displayName: '系统朗读',
  description: '使用 HarmonyOS 系统自带的 TTS 能力朗读',
  requiresApiKey: false,
  iconSymbol: 'sys.symbol.speaker_wave_2_fill'
}
const mimoProfile: TtsEngineProfile = {
  id: 'mimo',
  displayName: 'MiMo 语音',
  description: '使用 MiniMax MiMo 在线 TTS 朗读',
  requiresApiKey: true,
  iconSymbol: 'sys.symbol.waveform'
}

function makeProvider(id: string, apiKey: string): ModelProvider {
  // ModelProvider 构造签名: (id, name, type, iconSymbol, brandColor, baseUrl?, apiStyle?)
  const p = new ModelProvider(id, id, ProviderType.CUSTOM, '', $r('app.color.text_primary'))
  p.apiKey = apiKey
  return p
}

export default function ttsEngineAvailabilityTest() {
  describe('evaluateTtsEngineAvailability', () => {
    it('system engine is always enabled', 0, () => {
      const result = evaluateTtsEngineAvailability(systemProfile, [])
      expect(result.isEnabled).assertTrue()
      expect(result.unavailableReason).assertEqual('')
    })

    it('mimo is disabled when no providers configured', 0, () => {
      const result = evaluateTtsEngineAvailability(mimoProfile, [])
      expect(result.isEnabled).assertFalse()
      expect(result.unavailableReason).assertContain('MiniMax')
    })

    it('mimo is disabled when MiniMax exists but no apiKey', 0, () => {
      const result = evaluateTtsEngineAvailability(mimoProfile, [makeProvider('minimax', '')])
      expect(result.isEnabled).assertFalse()
    })

    it('mimo is enabled when MiniMax has apiKey', 0, () => {
      const result = evaluateTtsEngineAvailability(mimoProfile, [makeProvider('minimax', 'sk-xxx')])
      expect(result.isEnabled).assertTrue()
      expect(result.unavailableReason).assertEqual('')
    })

    it('mimo is disabled when only other providers have apiKey', 0, () => {
      const result = evaluateTtsEngineAvailability(
        mimoProfile, [makeProvider('openai', 'sk-ooo')]
      )
      expect(result.isEnabled).assertFalse()
    })
  })
}
