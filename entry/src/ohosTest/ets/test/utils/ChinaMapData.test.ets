import { describe, it, expect } from '@ohos/hypium'
import { ChinaProvince, findProvinceByRef } from '../../../../main/ets/utils/ChinaMapData'

/**
 * ChinaMapData 查询纯函数单元测试（中国地图教学工具, plan Task 1）
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

function makeProvince(id: string, name: string, short: string): ChinaProvince {
  const p: ChinaProvince = {
    id: id,
    name: name,
    short: short,
    abbr: 'X',
    capital: '某市',
    region: '测试大区',
    path: 'M0 0L1 0L1 1Z'
  }
  return p
}

export default function chinaMapDataTest() {
  describe('findProvinceByRef', () => {
    const provinces: ChinaProvince[] = [
      makeProvince('140000', '山西省', '山西'),
      makeProvince('110000', '北京市', '北京'),
      makeProvince('820000', '澳门特别行政区', '澳门')
    ]

    it('matches by short name', 0, () => {
      const hit = findProvinceByRef(provinces, '山西')
      expect(hit !== null).assertTrue()
      if (hit !== null) {
        expect(hit.id).assertEqual('140000')
      }
    })

    it('matches by full name', 0, () => {
      const hit = findProvinceByRef(provinces, '北京市')
      expect(hit !== null).assertTrue()
      if (hit !== null) {
        expect(hit.short).assertEqual('北京')
      }
    })

    it('matches by id', 0, () => {
      const hit = findProvinceByRef(provinces, '820000')
      expect(hit !== null).assertTrue()
      if (hit !== null) {
        expect(hit.short).assertEqual('澳门')
      }
    })

    it('trims surrounding whitespace before matching', 0, () => {
      const hit = findProvinceByRef(provinces, ' 山西 ')
      expect(hit !== null).assertTrue()
      if (hit !== null) {
        expect(hit.id).assertEqual('140000')
      }
    })

    it('returns null on unknown ref', 0, () => {
      expect(findProvinceByRef(provinces, '东德') === null).assertTrue()
    })

    it('returns null on empty province list', 0, () => {
      expect(findProvinceByRef([], '北京') === null).assertTrue()
    })
  })
}
