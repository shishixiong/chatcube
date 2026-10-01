import { describe, it, expect } from '@ohos/hypium'
import { PLANNER_SYSTEM_PROMPT } from '../../../../main/ets/utils/LessonPlanPromptUtils'

/**
 * 备课提示词 + 计划 Section 渲染单元测试
 * (Task 5 落 prompt 标记断言; Task 6 追加渲染用例)
 */
export default function lessonPlanSectionRenderTest() {
  describe('PLANNER_SYSTEM_PROMPT - v2 输出契约标记', () => {
    it('包含 chinese 模块示例与字段', 0, () => {
      expect(PLANNER_SYSTEM_PROMPT.indexOf('"chinese"') >= 0).assertTrue()
      expect(PLANNER_SYSTEM_PROMPT.indexOf('"dimension": "pinyin"') >= 0).assertTrue()
      expect(PLANNER_SYSTEM_PROMPT.indexOf('"character"') >= 0).assertTrue()
    })
    it('包含 writing subject 字段与 schemaVersion 2', 0, () => {
      expect(PLANNER_SYSTEM_PROMPT.indexOf('"subject"') >= 0).assertTrue()
      expect(PLANNER_SYSTEM_PROMPT.indexOf('"schemaVersion": 2') >= 0).assertTrue()
    })
    it('包含 chinese 密度下限与台账约束文案', 0, () => {
      expect(PLANNER_SYSTEM_PROMPT.indexOf('chinese: 至少 2 个') >= 0).assertTrue()
      expect(PLANNER_SYSTEM_PROMPT.indexOf('chinese[].character') >= 0).assertTrue()
    })
  })
}
