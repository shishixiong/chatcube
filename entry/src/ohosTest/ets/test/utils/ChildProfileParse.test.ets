import { describe, it, expect } from '@ohos/hypium'
import { parseProfileJson } from '../../../../main/ets/services/ChildProfileService'

/**
 * ChildProfileService.parseProfileJson 兼容性单元测试
 *
 * 覆盖画像扩展（math_number_sense / math_word_problem + strategy / misconceptions 字段）后的
 * 旧版 JSON 兼容解析：缺字段补默认值、26 维齐全、新字段透传。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 * 本文件不注册进 List.test.ets（由人工在 IDE 中执行）
 */
export default function childProfileParseTest() {
  describe('childProfileParse', () => {
    it('旧JSON_24维无新字段_兼容', 0, () => {
      const emptyArr: Object[] = []
      const old: Record<string, Object> = {}
      const dim: Record<string, Object> = {}
      dim['level'] = 2
      dim['lastAssessed'] = 0
      dim['notes'] = '会凑十'
      const skills: Record<string, Object> = {}
      skills['math_addition'] = dim
      old['skills'] = skills
      old['strengths'] = emptyArr
      old['weakAreas'] = emptyArr
      const p = parseProfileJson(JSON.stringify(old))
      expect(p.skills['math_number_sense'] !== undefined).assertTrue()
      expect(p.skills['math_word_problem'] !== undefined).assertTrue()
      expect(p.skills['math_addition'].strategy === '').assertTrue()
      expect(p.skills['math_addition'].misconceptions === '').assertTrue()
      expect(p.skills['math_addition'].notes === '会凑十').assertTrue()
      expect(p.skills['math_addition'].level === 2).assertTrue()
    })
    it('新JSON_新字段透传', 0, () => {
      const emptyArr: Object[] = []
      const raw: Record<string, Object> = {}
      const dim: Record<string, Object> = {}
      dim['level'] = 3
      dim['lastAssessed'] = 0
      dim['notes'] = ''
      dim['strategy'] = '凑十'
      dim['misconceptions'] = '忘记进位'
      const skills: Record<string, Object> = {}
      skills['math_addition'] = dim
      raw['skills'] = skills
      raw['strengths'] = emptyArr
      raw['weakAreas'] = emptyArr
      const p = parseProfileJson(JSON.stringify(raw))
      expect(p.skills['math_addition'].strategy === '凑十').assertTrue()
      expect(p.skills['math_addition'].misconceptions === '忘记进位').assertTrue()
    })
  })
}
