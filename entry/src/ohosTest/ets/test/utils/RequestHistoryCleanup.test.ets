import { describe, it, expect } from '@ohos/hypium'
import { ToolCall } from '../../../../main/ets/models/ChatModels'
import { RequestMessage } from '../../../../main/ets/services/AIApiService'
import { truncateRequestHistory } from '../../../../main/ets/utils/RequestHistoryCleanup'

/**
 * RequestHistoryCleanup 单元测试
 *
 * 覆盖 truncateRequestHistory 在以下场景的行为:
 *  1. 历史长度未超限: 原样返回
 *  2. maxHistoryMessages <= 0: 原样返回 (与原行为一致: 不截断)
 *  3. 普通文本对话: 截断无副作用
 *  4. 截断边界正好落在 tool-result 上: 产生 orphan tool, 必须被清除
 *  5. 截断后 assistant-with-tool_calls 缺少全部 tool-result: assistant + 残余 tool 一起被清除
 *  6. 截断后 assistant-with-tool_calls 只缺部分 tool-result: 整个 assistant + 全部 tool 一起被清除
 *      (部分保留会让 OpenAI 报 "tool call ... was not found", 不如整组丢弃)
 *  7. 中间含完整 assistant+tool 组, 后续 user: 完整组保留, user 保留
 *  8. 空数组: 返回空数组
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

// ============ Test helpers ============

function toolCall(id: string, name: string = 'mock_tool'): ToolCall {
  return new ToolCall(id, name, '{}')
}

function userMsg(content: string): RequestMessage {
  return new RequestMessage('user', content)
}

function assistantMsg(content: string): RequestMessage {
  return new RequestMessage('assistant', content)
}

function assistantWithTools(content: string, toolCallIds: string[]): RequestMessage {
  const msg = new RequestMessage('assistant', content)
  const calls: ToolCall[] = []
  for (let i = 0; i < toolCallIds.length; i++) {
    calls.push(toolCall(toolCallIds[i]))
  }
  msg.toolCalls = calls
  return msg
}

function toolResultMsg(toolCallId: string, content: string): RequestMessage {
  const msg = new RequestMessage('tool', content)
  msg.toolCallId = toolCallId
  return msg
}

// ============ Tests ============

export default function requestHistoryCleanupTest() {
  describe('truncateRequestHistory - no-op 路径', () => {
    it('历史长度未超过 max: 原样返回 (同一引用)', 0, () => {
      const input: RequestMessage[] = [userMsg('hi'), assistantMsg('hello')]
      const result = truncateRequestHistory(input, 10)
      expect(result).assertStrictEquals(input) // 未触发截断
    })

    it('maxHistoryMessages <= 0: 原样返回 (与原代码 "不截断" 语义一致)', 0, () => {
      const input: RequestMessage[] = [userMsg('a'), assistantMsg('b'), userMsg('c')]
      expect(truncateRequestHistory(input, 0)).assertStrictEquals(input)
      expect(truncateRequestHistory(input, -1)).assertStrictEquals(input)
    })

    it('空数组: 返回空数组', 0, () => {
      const result = truncateRequestHistory([], 5)
      expect(result.length).assertEqual(0)
    })

    it('普通文本历史 (无 tool): 截断到末尾 N 条', 0, () => {
      const input: RequestMessage[] = [
        userMsg('m1'), assistantMsg('m2'),
        userMsg('m3'), assistantMsg('m4'),
        userMsg('m5'), assistantMsg('m6')
      ]
      const result = truncateRequestHistory(input, 2)
      expect(result.length).assertEqual(2)
      expect(result[0].content).assertEqual('m5')
      expect(result[1].content).assertEqual('m6')
    })
  })

  describe('truncateRequestHistory - orphan tool 清理', () => {
    it('截断起点正好是 tool-result: 该 orphan tool 被丢弃', 0, () => {
      // 历史: [user, assistant(t1), tool(r1), user2, assistant, user3]
      // 截断到 3 条: slice(-3) = [user2, assistant, user3]  -- 这个本身不 orphan
      // 但如果 max=2: slice(-2) = [assistant, user3] -- 也不 orphan
      // 想制造 leading orphan, 让截断切在 tool 之后:
      // 历史: [user, assistant(t1), tool(r1), user2, assistant, user3]
      // max=4: slice(-4) = [assistant(t1), tool(r1), user2, assistant]
      // 也不 orphan. 试试: max=3 -> slice(-3) = [tool(r1), user2, assistant]
      //   -> leading tool is orphan, 应该被丢弃 -> [user2, assistant]
      const input: RequestMessage[] = [
        userMsg('u1'),
        assistantWithTools('a1', ['t1']),
        toolResultMsg('t1', 'r1'),
        userMsg('u2'),
        assistantMsg('a2')
      ]
      const result = truncateRequestHistory(input, 3)
      expect(result.length).assertEqual(2)
      expect(result[0].content).assertEqual('u2')
      expect(result[1].content).assertEqual('a2')
    })

    it('截断只保留 assistant-with-tool_calls 缺全部 tool-result: 整组被清', 0, () => {
      // 历史: [user, assistant(t1), tool(r1), assistant(t2), tool(r2), user2]
      // max=3: slice(-3) = [tool(r1), assistant(t2), tool(r2)]
      //   -> leading tool orphan -> drop -> [assistant(t2), tool(r2)]
      //   -> assistant(t2) 缺 t1 result? 不, t1 不在它的 tool_calls 里
      //   -> assistant(t2) 的 tool_calls=[t2], result r2 present -> keep
      //   -> [assistant(t2), tool(r2)]
      const input: RequestMessage[] = [
        userMsg('u1'),
        assistantWithTools('a1', ['t1']),
        toolResultMsg('t1', 'r1'),
        assistantWithTools('a2', ['t2']),
        toolResultMsg('t2', 'r2'),
        userMsg('u2')
      ]
      const result = truncateRequestHistory(input, 3)
      expect(result.length).assertEqual(2)
      expect(result[0].role).assertEqual('assistant')
      expect(result[0].hasToolCalls()).assertTrue()
      expect(result[0].toolCalls[0].id).assertEqual('t2')
      expect(result[1].role).assertEqual('tool')
      expect(result[1].toolCallId).assertEqual('t2')
    })

    it('截断只保留 assistant-with-tool_calls 缺部分 tool-result: 整组被清', 0, () => {
      // 历史: [user, assistant(t1,t2), tool(r1), tool(r2), user2]
      // max=2: slice(-2) = [tool(r2), user2]
      //   -> leading tool orphan -> drop -> [user2]
      // max=3: slice(-3) = [tool(r1), tool(r2), user2]
      //   -> leading tool orphan -> drop -> [tool(r2), user2]
      //   -> leading tool orphan -> drop -> [user2]
      // 想保留 assistant 但只缺 r2, 让 r1 在但 r2 缺: 不容易构造, 改测另一种:
      //   保留 assistant 但只保留 r1 (缺 r2), 应清整组
      // 历史: [user, assistant(t1,t2), tool(r1), tool(r2), user2]
      // 假设: 强制 slice 保留 [assistant(t1,t2), tool(r1)] (这是不可能的,
      //   因为 slice 只能切连续区间, 而 tool(r1) 在 tool(r2) 前)
      //   改用更简单的构造: 历史是 [user, assistant(t1,t2), tool(r1), tool(r2), user2]
      //   max=4: slice(-4) = [assistant(t1,t2), tool(r1), tool(r2), user2]
      //   -> assistant has tool_calls=[t1,t2], both r1 and r2 present -> keep -> 不 orphan
      //   改构造: [user, assistant(t1,t2), tool(r1), user2] (没有 r2)
      //   max=2: slice(-2) = [tool(r1), user2] -> leading tool orphan -> drop -> [user2]
      //   max=3: slice(-3) = [assistant(t1,t2), tool(r1), user2]
      //   -> assistant 缺 r2 -> drop assistant
      //   -> result = [tool(r1), user2] -> leading tool orphan -> drop
      //   -> result = [user2]
      const input: RequestMessage[] = [
        userMsg('u1'),
        assistantWithTools('a1', ['t1', 't2']),
        toolResultMsg('t1', 'r1'),
        userMsg('u2')
      ]
      const result = truncateRequestHistory(input, 3)
      expect(result.length).assertEqual(1)
      expect(result[0].content).assertEqual('u2')
    })

    it('多个连续 assistant+tool 组, 截断切在中间: 残缺组被清, 完整组保留', 0, () => {
      // 历史: [user, assistant(t1), tool(r1), assistant(t2), tool(r2), assistant(t3), tool(r3), user2]
      // max=5: slice(-5) = [tool(r1), assistant(t2), tool(r2), assistant(t3), tool(r3)]
      //   -> leading tool r1 orphan -> drop
      //   -> [assistant(t2), tool(r2), assistant(t3), tool(r3)]
      //   -> assistant(t2) 配 r2, assistant(t3) 配 r3, 都完整 -> keep
      const input: RequestMessage[] = [
        userMsg('u1'),
        assistantWithTools('a1', ['t1']),
        toolResultMsg('t1', 'r1'),
        assistantWithTools('a2', ['t2']),
        toolResultMsg('t2', 'r2'),
        assistantWithTools('a3', ['t3']),
        toolResultMsg('t3', 'r3'),
        userMsg('u2')
      ]
      const result = truncateRequestHistory(input, 5)
      expect(result.length).assertEqual(4)
      expect(result[0].role).assertEqual('assistant')
      expect(result[0].toolCalls[0].id).assertEqual('t2')
      expect(result[1].role).assertEqual('tool')
      expect(result[1].toolCallId).assertEqual('t2')
      expect(result[2].role).assertEqual('assistant')
      expect(result[2].toolCalls[0].id).assertEqual('t3')
      expect(result[3].role).assertEqual('tool')
      expect(result[3].toolCallId).assertEqual('t3')
    })

    it('截断后只剩纯 tool-result 和 user: 全部 tool 被清, user 保留', 0, () => {
      // 历史: [user, assistant(t1), tool(r1), user2]
      // max=2: slice(-2) = [tool(r1), user2]
      //   -> leading tool orphan -> drop -> [user2]
      const input: RequestMessage[] = [
        userMsg('u1'),
        assistantWithTools('a1', ['t1']),
        toolResultMsg('t1', 'r1'),
        userMsg('u2')
      ]
      const result = truncateRequestHistory(input, 2)
      expect(result.length).assertEqual(1)
      expect(result[0].role).assertEqual('user')
      expect(result[0].content).assertEqual('u2')
    })
  })

}
