import { describe, it, expect } from '@ohos/hypium'
import {
  isImageCapabilityError,
  hasImageAttachment,
  getCurrentModelVisionSupport
} from '../../../../main/ets/utils/VisionCompat'
import {
  AttachmentType,
  MessageAttachment,
  ModelInfo,
  ModelCapabilities,
  ModelProvider,
  ProviderType,
  ApiStyle
} from '../../../../main/ets/models/ChatModels'

// ============ Test helpers ============

function makeVisionModel(id: string, supportsVision: boolean, userModified: boolean = true): ModelInfo {
  const m = new ModelInfo(id, id, 4096, true, false)
  m.capabilities = new ModelCapabilities(false, false, false, supportsVision, true)
  m.capabilitiesUserModified = userModified
  return m
}

function makeProvider(id: string, models: ModelInfo[]): ModelProvider {
  const p = new ModelProvider(id, id, ProviderType.CUSTOM, '', $r('app.color.text_primary'),
    '', ApiStyle.OPENAI)
  p.models = models
  return p
}

function makeImageAttachment(name: string = 'photo.jpg'): MessageAttachment {
  return new MessageAttachment(
    'att-' + name,
    AttachmentType.IMAGE,
    name,
    '/sandbox/' + name,
    'image/jpeg',
    1024
  )
}

function makeFileAttachment(name: string = 'doc.pdf'): MessageAttachment {
  return new MessageAttachment(
    'att-' + name,
    AttachmentType.FILE,
    name,
    '/sandbox/' + name,
    'application/pdf',
    2048
  )
}

// ============ isImageCapabilityError ============

export default function visionCompatTest() {
  describe('isImageCapabilityError', () => {
    it('returns true for English "image input" error', 0, () => {
      expect(isImageCapabilityError('Model does not support image input')).assertTrue()
    })

    it('returns true for OpenAI "image_url" error', 0, () => {
      expect(isImageCapabilityError('Invalid value: image_url not allowed for this model')).assertTrue()
    })

    it('returns true for "vision" error keyword', 0, () => {
      expect(isImageCapabilityError('Vision is not supported by the current model')).assertTrue()
    })

    it('returns true for "multimodal" error keyword', 0, () => {
      expect(isImageCapabilityError('multimodal content type is unsupported by this model')).assertTrue()
    })

    it('returns true for Chinese "不支持图片" error', 0, () => {
      expect(isImageCapabilityError('当前模型不支持图片输入')).assertTrue()
    })

    it('returns true for Chinese "视觉" error keyword', 0, () => {
      expect(isImageCapabilityError('本接口暂未开放视觉能力')).assertTrue()
    })

    it('returns true for Chinese "多模态" error keyword', 0, () => {
      expect(isImageCapabilityError('该模型不支持多模态输入')).assertTrue()
    })

    it('returns false for HTTP 401 auth error', 0, () => {
      expect(isImageCapabilityError('API Key 认证失败')).assertFalse()
    })

    it('returns false for HTTP 500 server error', 0, () => {
      expect(isImageCapabilityError('服务器错误 (500)')).assertFalse()
    })

    it('returns false for tool-calling error (not image)', 0, () => {
      expect(isImageCapabilityError('tools not supported by this model')).assertFalse()
    })

    it('returns false for empty string', 0, () => {
      expect(isImageCapabilityError('')).assertFalse()
    })
  })

  // ============ hasImageAttachment ============

  describe('hasImageAttachment', () => {
    it('returns false for empty attachment list', 0, () => {
      expect(hasImageAttachment([])).assertFalse()
    })

    it('returns true when list contains an image', 0, () => {
      const attachments: MessageAttachment[] = [makeFileAttachment(), makeImageAttachment()]
      expect(hasImageAttachment(attachments)).assertTrue()
    })

    it('returns false when list contains only files', 0, () => {
      const attachments: MessageAttachment[] = [makeFileAttachment()]
      expect(hasImageAttachment(attachments)).assertFalse()
    })

    it('returns true for image-only list', 0, () => {
      const attachments: MessageAttachment[] = [makeImageAttachment()]
      expect(hasImageAttachment(attachments)).assertTrue()
    })
  })

  // ============ getCurrentModelVisionSupport ============

  describe('getCurrentModelVisionSupport', () => {
    it('returns true when current model supports vision', 0, () => {
      const provider = makeProvider('p1', [makeVisionModel('vision-model', true)])
      expect(getCurrentModelVisionSupport(provider, 'vision-model')).assertTrue()
    })

    it('returns false when current model does not support vision', 0, () => {
      const provider = makeProvider('p1', [makeVisionModel('text-model', false)])
      expect(getCurrentModelVisionSupport(provider, 'text-model')).assertFalse()
    })

    it('returns false when currentModelId is empty', 0, () => {
      const provider = makeProvider('p1', [makeVisionModel('m1', true)])
      expect(getCurrentModelVisionSupport(provider, '')).assertFalse()
    })

    it('returns false when currentModelId is not found in provider models', 0, () => {
      const provider = makeProvider('p1', [makeVisionModel('m1', true)])
      expect(getCurrentModelVisionSupport(provider, 'm2')).assertFalse()
    })

    it('returns true when capabilitiesUserModified is true and user set vision=true', 0, () => {
      // userModified=true + supportsVision=true → effective caps returns persisted value (true)
      const provider = makeProvider('p1', [makeVisionModel('user-override', true, true)])
      expect(getCurrentModelVisionSupport(provider, 'user-override')).assertTrue()
    })

    it('returns false when capabilitiesUserModified is true and user set vision=false', 0, () => {
      const provider = makeProvider('p1', [makeVisionModel('user-disabled', false, true)])
      expect(getCurrentModelVisionSupport(provider, 'user-disabled')).assertFalse()
    })
  })
}
