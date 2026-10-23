import { describe, it, expect } from '@ohos/hypium'
import { ChinaProvince } from '../../../../main/ets/utils/ChinaMapData'
import { buildExploreProgressText, buildTeacherNote, teacherNoteVariant } from '../../../../main/ets/utils/MapAtlasCopy'

/**
 * MapAtlasCopy 单元测试（map-card-redesign 配套）
 *
 * 「小星老师说」文案按省稳定散列到 3 套模板：
 * 同一个省每次同一句（可复习），不同省轮换（不腻）。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */

function makeProvince(id: string, short: string, abbr: string,
  capital: string, region: string): ChinaProvince {
  const p: ChinaProvince = {
    id: id,
    name: `${short}省`,
    short: short,
    abbr: abbr,
    capital: capital,
    region: region,
    path: 'M0 0L1 0L1 1Z'
  }
  return p
}

export default function mapAtlasCopyTest() {
  describe('teacherNoteVariant', () => {
    it('uses last digit to pick one of three variants', 0, () => {
      // '0'=48 % 3 = 0 / '1'=49 % 3 = 1 / '2'=50 % 3 = 2
      expect(teacherNoteVariant('110000')).assertEqual(0)
      expect(teacherNoteVariant('120001')).assertEqual(1)
      expect(teacherNoteVariant('130002')).assertEqual(2)
    })

    it('falls back to the first variant for an empty id', 0, () => {
      expect(teacherNoteVariant('')).assertEqual(0)
    })
  })

  describe('buildTeacherNote', () => {
    it('variant 0 teaches the abbreviation', 0, () => {
      const p = makeProvince('110000', '北京', '京', '北京', '华北')
      expect(buildTeacherNote(p)).assertEqual('记住简称「京」，下次一眼就能认出来。')
    })

    it('variant 1 teaches the administrative centre', 0, () => {
      const p = makeProvince('140001', '山西', '晋', '太原', '华北')
      expect(buildTeacherNote(p)).assertEqual('山西的行政中心在太原，别记混啦。')
    })

    it('variant 2 combines region, name and abbreviation', 0, () => {
      const p = makeProvince('440002', '广东', '粤', '广州', '华南')
      expect(buildTeacherNote(p)).assertEqual('华南的广东，简称「粤」，一起记住它。')
    })

    it('is stable for the same province', 0, () => {
      const p = makeProvince('320000', '江苏', '苏', '南京', '华东')
      expect(buildTeacherNote(p)).assertEqual(buildTeacherNote(p))
    })
  })

  describe('buildExploreProgressText', () => {
    it('renders the explored count', 0, () => {
      expect(buildExploreProgressText(3)).assertEqual('已认识 3 个地方')
    })

    it('clamps negative counts to zero', 0, () => {
      expect(buildExploreProgressText(-2)).assertEqual('已认识 0 个地方')
    })
  })
}
