import { describe, it, expect } from '@ohos/hypium'
import {
  PLANNER_SYSTEM_PROMPT,
  renderDailyPlanSection,
  renderDailyPlanSectionForSubject
} from '../../../../main/ets/utils/LessonPlanPromptUtils'
import {
  LessonPlan,
  LessonPlanChineseItem,
  LessonPlanVocabItem,
  LessonPlanWritingItem
} from '../../../../main/ets/models/LessonPlanModels'

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

  describe('renderDailyPlanSection - 四学科分组 (Review Focus #5)', () => {
    it('条目按 语文/数学/英语/常识 分组, 空组无空节', 0, () => {
      const p = new LessonPlan()
      p.themeTitle = '秋天的山'
      const c = new LessonPlanChineseItem()
      c.dimension = 'chinese_vocab'
      c.character = '山'
      c.description = '认读并组词'
      c.targetSkillLevel = 2
      p.chinese.push(c)
      const v = new LessonPlanVocabItem()
      v.word = 'apple'
      v.translation = '苹果'
      p.vocab.push(v)
      const wc = new LessonPlanWritingItem()
      wc.characterOrWord = '山'
      wc.subject = 'chinese'
      p.writing.push(wc)
      const we = new LessonPlanWritingItem()
      we.characterOrWord = 'A'
      we.subject = 'english'
      p.writing.push(we)
      const wu = new LessonPlanWritingItem()
      wu.characterOrWord = '旧'
      wu.subject = ''
      p.writing.push(wu)
      const section = renderDailyPlanSection(p, '2026-10-02', '五')
      expect(section.indexOf('### 语文') >= 0).assertTrue()
      expect(section.indexOf('### 英语') >= 0).assertTrue()
      expect(section.indexOf('### 常识') >= 0).assertTrue()
      expect(section.indexOf('### 数学') < 0).assertTrue()   // 空组不输出
      expect(section.indexOf('### 常识') > section.indexOf('### 英语')).assertTrue()
      expect(section.indexOf('apple') >= 0).assertTrue()
      expect(section.indexOf('山') >= 0).assertTrue()
      expect(section.indexOf('旧') > section.indexOf('### 常识')).assertTrue() // 未标签 writing 归常识组
    })
  })

  describe('renderDailyPlanSectionForSubject', () => {
    it('语文视图: 主题句 + chinese 条目 + writing[chinese], 无 teacherNotes / image 指引', 0, () => {
      const p = new LessonPlan()
      p.themeTitle = '秋天的山'
      p.teacherNotes = '记得复习昨天内容'
      const c = new LessonPlanChineseItem()
      c.dimension = 'pinyin'
      c.character = 'shān'
      c.description = '拼读第一声'
      c.targetSkillLevel = 1
      p.chinese.push(c)
      const wc = new LessonPlanWritingItem()
      wc.characterOrWord = '山'
      wc.subject = 'chinese'
      p.writing.push(wc)
      const s = renderDailyPlanSectionForSubject(p, '2026-10-02', '五', 'chinese')
      expect(s.indexOf('语文教学目标') >= 0).assertTrue()
      expect(s.indexOf('主题: 秋天的山') >= 0).assertTrue()
      expect(s.indexOf('shān') >= 0).assertTrue()
      expect(s.indexOf('山') >= 0).assertTrue()
      expect(s.indexOf('记得复习昨天内容') < 0).assertTrue()
      expect(s.indexOf('image_generation') < 0).assertTrue()
      expect(s.indexOf('预生成') < 0).assertTrue()
    })
    it('本学科 0 条 → 返回空字符串 (v1 旧计划静默)', 0, () => {
      const p = new LessonPlan()
      p.themeTitle = '旧计划'
      const v = new LessonPlanVocabItem()
      v.word = 'apple'
      p.vocab.push(v)
      expect(renderDailyPlanSectionForSubject(p, '2026-10-02', '五', 'chinese')).assertEqual('')
      expect(renderDailyPlanSectionForSubject(p, '2026-10-02', '五', 'math')).assertEqual('')
    })
    it('数学视图: math 条目 + writing[math]', 0, () => {
      const p = new LessonPlan()
      const wc = new LessonPlanWritingItem()
      wc.characterOrWord = '3'
      wc.subject = 'math'
      p.writing.push(wc)
      const s = renderDailyPlanSectionForSubject(p, '2026-10-02', '五', 'math')
      expect(s.indexOf('数学教学目标') >= 0).assertTrue()
      expect(s.indexOf('3') >= 0).assertTrue()
      expect(s.indexOf('主题:') < 0).assertTrue()   // themeTitle 为空 → 无主题行 (Review Focus #5)
    })
  })
}
