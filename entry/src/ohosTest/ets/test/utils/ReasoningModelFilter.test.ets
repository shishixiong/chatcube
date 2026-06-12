import { describe, it, expect } from '@ohos/hypium'
import { filterReasoningModels, ReasoningModelPick } from '../../../../main/ets/utils/ReasoningModelFilter'
import { ModelInfo, ModelProvider, ModelCapabilities, ProviderType, ApiStyle } from '../../../../main/ets/models/ChatModels'

// Helper: build a ModelInfo with a specific capabilities override
function makeModel(id: string, isEnabled: boolean, supportsReasoning: boolean,
  userModified: boolean = true): ModelInfo {
  const m = new ModelInfo(id, id, 4096, isEnabled, false)
  const caps = new ModelCapabilities(false, supportsReasoning, false, false, true)
  m.capabilities = caps
  m.capabilitiesUserModified = userModified
  return m
}

function makeProvider(id: string, models: ModelInfo[]): ModelProvider {
  const p = new ModelProvider(id, id, ProviderType.CUSTOM, '', $r('app.color.text_primary'),
    '', ApiStyle.OPENAI)
  p.models = models
  return p
}

export default function reasoningModelFilterTest() {
  describe('filterReasoningModels', () => {
    it('returns null when providers is empty', 0, () => {
      const result = filterReasoningModels([])
      expect(result).assertNull()
    })

    it('returns null when all models are disabled', 0, () => {
      const providers = [
        makeProvider('p1', [makeModel('m1', false, true), makeModel('m2', false, true)])
      ]
      const result = filterReasoningModels(providers)
      expect(result).assertNull()
    })

    it('returns null when enabled models all lack reasoning', 0, () => {
      const providers = [
        makeProvider('p1', [makeModel('m1', true, false), makeModel('m2', true, false)])
      ]
      const result = filterReasoningModels(providers)
      expect(result).assertNull()
    })

    it('returns the first enabled + reasoning model from the first matching provider', 0, () => {
      const m1 = makeModel('m1', true, false)
      const m2 = makeModel('m2', true, true)  // first hit
      const m3 = makeModel('m3', true, true)
      const providers = [
        makeProvider('p1', [m1, m2]),
        makeProvider('p2', [m3])
      ]
      const result = filterReasoningModels(providers)
      expect(result).assertNotNull()
      const pick = result as ReasoningModelPick
      expect(pick.provider.id).assertEqual('p1')
      expect(pick.reasoningModel.id).assertEqual('m2')
    })

    it('skips disabled models and returns the next enabled + reasoning one', 0, () => {
      const m1 = makeModel('m1', true, false)
      const m2 = makeModel('m2', false, true)  // disabled, skipped
      const m3 = makeModel('m3', true, true)  // first hit
      const providers = [
        makeProvider('p1', [m1, m2, m3])
      ]
      const result = filterReasoningModels(providers)
      expect(result).assertNotNull()
      const pick = result as ReasoningModelPick
      expect(pick.reasoningModel.id).assertEqual('m3')
    })

    it('honors capabilitiesUserModified override when supportsReasoning is set true', 0, () => {
      // Build a model where user manually set supportsReasoning=true via userModified=true.
      // We can't easily make a non-registry model without mocking, so we exercise the
      // userModified path by confirming our test helper's userModified=true is preserved.
      const m = makeModel('user-override', true, true, true)
      expect(m.capabilitiesUserModified).assertTrue()
      const result = filterReasoningModels([makeProvider('p1', [m])])
      expect(result).assertNotNull()
      const pick = result as ReasoningModelPick
      expect(pick.reasoningModel.id).assertEqual('user-override')
    })
  })
}
