import { describe, it, expect } from '@ohos/hypium'
import { resolveStepAnswerPayload } from '../../../../main/ets/utils/ChatMessagePartsHelper'

/**
 * resolveStepAnswerPayload 纯函数测试:
 * 互动卡 timeline step 展开恢复时, 答题 payload 的来源选择。
 *
 * 背景 bug: ChatViewModel 在出题达上限时会给最后一个 toolResult.content
 * 尾部追加「[系统提示] ...」带内指令 (面向 LLM), toolResult 因此不再是纯 JSON,
 * 卡片 JSON.parse 失败 → 恢复跳过 → isCorrect 默认 false → 假「再试一次」。
 * 干净 payload 一直在 toolApprovalReason (toolCall.approvalReason 同步而来)。
 */
export default function stepAnswerPayloadTest() {
  describe('resolveStepAnswerPayload', () => {
    const CLEAN = '{"answered":true,"child_answer":"eye","correct":true,"correct_answer":"eye"}'
    const POLLUTED = CLEAN + '\n[系统提示] 本回合互动出题已达上限（3 题）。接下来请用一两句话总结本回合学习并收尾, 不要再调用出题工具。'

    it('approvalReason 干净时优先于被污染的 toolResult', 0, () => {
      expect(resolveStepAnswerPayload(POLLUTED, CLEAN)).assertEqual(CLEAN)
    })

    it('toolResult 干净且 approvalReason 干净时也取 approvalReason', 0, () => {
      expect(resolveStepAnswerPayload(CLEAN, CLEAN)).assertEqual(CLEAN)
    })

    it('approvalReason 为空时回退 toolResult', 0, () => {
      expect(resolveStepAnswerPayload(CLEAN, '')).assertEqual(CLEAN)
    })

    it('approvalReason 为审批态文本 (非 JSON 对象) 时回退 toolResult', 0, () => {
      expect(resolveStepAnswerPayload(CLEAN, 'always_allow')).assertEqual(CLEAN)
      expect(resolveStepAnswerPayload(CLEAN, '用户拒绝了工具调用')).assertEqual(CLEAN)
    })

    it('approvalReason 带首尾空白的 JSON 仍被识别采用', 0, () => {
      expect(resolveStepAnswerPayload(POLLUTED, '  ' + CLEAN + '  ')).assertEqual('  ' + CLEAN + '  ')
    })

    it('两者皆空返回空串', 0, () => {
      expect(resolveStepAnswerPayload('', '')).assertEqual('')
    })

    it('approvalReason 非对象 JSON (如数组) 时回退 toolResult', 0, () => {
      expect(resolveStepAnswerPayload(CLEAN, '["not","an","object"]')).assertEqual(CLEAN)
    })
  })
}
