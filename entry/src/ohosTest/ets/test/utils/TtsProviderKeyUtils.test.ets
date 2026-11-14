import { describe, it, expect } from '@ohos/hypium'
import { findProviderApiKey, TtsProviderKeyRef } from '../../../../main/ets/utils/TtsProviderKeyUtils'

// findProviderApiKey 是 DeepSeek / StepFun / MiniMax 等云 TTS 引擎共用的
// provider key 查找纯函数: 只在 id 匹配且 apiKey 非空时返回 key。

export default function ttsProviderKeyUtilsTest() {
  describe('findProviderApiKey', () => {
    it('returns empty when no providers configured', 0, () => {
      const providers: TtsProviderKeyRef[] = []
      expect(findProviderApiKey(providers, 'deepseek')).assertEqual('')
    })

    it('returns empty when matching provider has empty apiKey', 0, () => {
      const providers: TtsProviderKeyRef[] = [{ id: 'deepseek', apiKey: '' }]
      expect(findProviderApiKey(providers, 'deepseek')).assertEqual('')
    })

    it('returns key when matching provider has apiKey', 0, () => {
      const providers: TtsProviderKeyRef[] = [{ id: 'deepseek', apiKey: 'sk-ds' }]
      expect(findProviderApiKey(providers, 'deepseek')).assertEqual('sk-ds')
    })

    it('returns empty when only other providers have apiKey', 0, () => {
      const providers: TtsProviderKeyRef[] = [{ id: 'openai', apiKey: 'sk-ooo' }]
      expect(findProviderApiKey(providers, 'deepseek')).assertEqual('')
    })

    it('returns matching provider key among many providers', 0, () => {
      const providers: TtsProviderKeyRef[] = [
        { id: 'openai', apiKey: 'sk-ooo' },
        { id: 'deepseek', apiKey: 'sk-ds' },
        { id: 'stepfun', apiKey: 'sk-sf' }
      ]
      expect(findProviderApiKey(providers, 'deepseek')).assertEqual('sk-ds')
    })
  })
}
