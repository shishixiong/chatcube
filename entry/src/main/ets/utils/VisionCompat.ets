/**
 * Vision 兼容性工具 - 判定当前模型/附件/错误是否与图片输入兼容
 *
 * 背景：项目支持 15+ AI 服务商，部分模型（如 deepseek-v3、qwen-3、GLM）不支持视觉。
 * 之前 ChatSendFlow 和 ChatViewModel 无条件把图片附件塞进请求体，导致非视觉模型
 * 持续 400 错误并把图片残留在历史中。
 *
 * 本文件提取 3 个纯函数供 ChatSendFlow（pre-send 守门 + post-error 重试）和
 * ChatViewModel（历史构建时静默跳过图片）共享。
 */

import {
  AttachmentType,
  MessageAttachment,
  ModelInfo,
  ModelProvider
} from '../models/ChatModels'
import { getEffectiveCapabilities } from './ModelCapabilityDeriver'

// 错误关键词分两组：
// - imageHintKeywords: 含"图片/图像"或"vision/multimodal"等明显视觉相关词
// - combined: imageHintKeywords 命中后再判断是否有"不支持/未支持"等能力缺失词
// 严格双层匹配避免误伤（例如"image upload successful"这种状态消息）
const imageHintKeywords: string[] = [
  'image',
  'image_url',
  'input_image',
  'vision',
  'multimodal',
  '图片',
  '图像',
  '视觉',
  '多模态'
]

const unsupportedKeywords: string[] = [
  'not support',
  'not supported',
  'does not support',
  "doesn't support",
  'do not support',
  'unsupported',
  'unknown parameter',
  'unknown field',
  'unrecognized request argument',
  'unrecognized field',
  'extra_forbidden',
  'extra inputs are not permitted',
  'invalid parameter',
  'invalid_request_error',
  'not allowed',
  'is not permitted',
  'invalid value',
  '不允许',
  '不支持',
  '未知参数',
  '未支持',
  '暂未开放',
  '无法识别'
]

/**
 * 判断一条错误字符串是否是"模型不支持图片输入"类型的错误。
 *
 * 匹配规则：错误文本需同时命中"视觉相关词"和"不支持/未支持"两组关键词。
 * 严格的"两组"匹配避免对普通 HTTP 401/500/工具调用错误误判。
 *
 * @param error 错误文本（来自 AIApiService.extractHttpErrorMessage / extractApiErrorMessage）
 * @returns 是否图片能力不兼容
 */
export function isImageCapabilityError(error: string): boolean {
  if (error === '') {
    return false
  }
  const lower = error.toLowerCase()
  let hintHit = false
  for (let i = 0; i < imageHintKeywords.length; i++) {
    if (lower.includes(imageHintKeywords[i].toLowerCase()) || error.includes(imageHintKeywords[i])) {
      hintHit = true
      break
    }
  }
  if (!hintHit) {
    return false
  }
  for (let i = 0; i < unsupportedKeywords.length; i++) {
    if (lower.includes(unsupportedKeywords[i].toLowerCase()) || error.includes(unsupportedKeywords[i])) {
      return true
    }
  }
  return false
}

/**
 * 判断附件列表中是否包含图片（AttachmentType.IMAGE）。
 * 用于 pre-send 守门——新附件里有图片但模型不支持视觉时阻断发送。
 */
export function hasImageAttachment(attachments: MessageAttachment[]): boolean {
  for (let i = 0; i < attachments.length; i++) {
    if (attachments[i].type === AttachmentType.IMAGE) {
      return true
    }
  }
  return false
}

/**
 * 在 provider.models 中按 currentModelId 找到当前模型，返回其有效视觉能力。
 *
 * - modelId 为空 / 不在列表中 → 返回 false（保守按"不支持"处理）
 * - 找到的 model 走 getEffectiveCapabilities，自动尊重 capabilitiesUserModified 锁定
 *
 * 用于 pre-send 守门（executeSend）和 ChatViewModel 历史构建（visionAware 计算）。
 */
export function getCurrentModelVisionSupport(currentProvider: ModelProvider, currentModelId: string): boolean {
  if (currentModelId === '') {
    return false
  }
  for (let i = 0; i < currentProvider.models.length; i++) {
    const model: ModelInfo = currentProvider.models[i]
    if (model.id === currentModelId) {
      return getEffectiveCapabilities(model).supportsVision
    }
  }
  return false
}
