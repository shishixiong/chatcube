import { describe, it, expect } from '@ohos/hypium'
import { parseLessonPlan, serializeLessonPlan } from '../../../../main/ets/models/LessonPlanModels'

/**
 * LessonPlanModels 单元测试 (2026-10-01 学科拆分)
 * 覆盖: v2 水合 / v1 兼容 / 候选 key 容错 / 序列化回环
 * 运行: DevEco Studio → 右键该文件 → Run (CLI hvigorw test 不可用)
 */
export default function lessonPlanModelsTest() {
  describe('parseLessonPlan - v2 水合', () => {
    it('chinese 数组 + writing.subject 正确水合', 0, () => {
      const json = `{
        "schemaVersion": 2, "planDate": "2026-10-02",
        "themeTitle": "秋天的山",
        "chinese": [
          {"topicKey": "chinese.chinese_vocab.shan", "dimension": "chinese_vocab",
           "character": "山", "description": "认读并组词", "targetSkillLevel": 2, "imagePrompt": ""},
          {"topicKey": "chinese.pinyin.shan", "dimension": "pinyin",
           "character": "shān", "description": "拼读第一声", "targetSkillLevel": 1, "imagePrompt": ""}
        ],
        "writing": [
          {"topicKey": "writing.山", "characterOrWord": "山", "subject": "chinese", "description": "", "imagePrompt": ""},
          {"topicKey": "writing.A", "characterOrWord": "A", "subject": "english", "description": "", "imagePrompt": ""}
        ]
      }`
      const plan = parseLessonPlan(json)
      expect(plan.schemaVersion).assertEqual(2)
      expect(plan.chinese.length).assertEqual(2)
      expect(plan.chinese[0].dimension).assertEqual('chinese_vocab')
      expect(plan.chinese[0].character).assertEqual('山')
      expect(plan.chinese[0].targetSkillLevel).assertEqual(2)
      expect(plan.chinese[1].character).assertEqual('shān')
      expect(plan.writing.length).assertEqual(2)
      expect(plan.writing[0].subject).assertEqual('chinese')
      expect(plan.writing[1].subject).assertEqual('english')
    })
  })

  describe('parseLessonPlan - v1 兼容 (Review Focus #1)', () => {
    it('无 chinese key / writing 无 subject → 空数组 + 空串, 不抛错', 0, () => {
      const json = `{
        "schemaVersion": 1, "planDate": "2026-09-30",
        "themeTitle": "旧计划",
        "writing": [{"topicKey": "writing.一", "characterOrWord": "一", "description": "", "imagePrompt": ""}]
      }`
      const plan = parseLessonPlan(json)
      expect(plan.schemaVersion).assertEqual(1)
      expect(plan.chinese.length).assertEqual(0)
      expect(plan.writing.length).assertEqual(1)
      expect(plan.writing[0].subject).assertEqual('')
    })
  })

  describe('parseLessonPlan - 容错', () => {
    it('chineseItems 候选 key 命中', 0, () => {
      const json = `{"chineseItems": [{"topicKey": "chinese.pinyin.ma", "dimension": "pinyin", "character": "mā", "description": "", "targetSkillLevel": 1, "imagePrompt": ""}]}`
      const plan = parseLessonPlan(json)
      expect(plan.chinese.length).assertEqual(1)
      expect(plan.chinese[0].character).assertEqual('mā')
    })
    it('chinese 不是数组 → 降级空数组; 非法 JSON → 空 plan', 0, () => {
      const p1 = parseLessonPlan('{"chinese": "oops"}')
      expect(p1.chinese.length).assertEqual(0)
      const p2 = parseLessonPlan('not-json')
      expect(p2.themeTitle).assertEqual('')
      expect(p2.chinese.length).assertEqual(0)
    })
    it('新 LessonPlan 默认 schemaVersion=2', 0, () => {
      const plan = parseLessonPlan(serializeLessonPlan(parseLessonPlan('')))
      expect(plan.schemaVersion).assertEqual(2)
    })
  })
}
