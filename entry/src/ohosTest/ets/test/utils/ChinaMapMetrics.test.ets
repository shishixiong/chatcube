import { describe, it, expect } from '@ohos/hypium'
import { ChinaProvince } from '../../../../main/ets/utils/ChinaMapData'
import {
  AREA_MIN_RATIO,
  DIRECTION_MIN_DOMINANCE,
  MAP_DIRECTIONS,
  areaRatio,
  dominantDirection,
  largerProvince,
  provinceArea,
  provinceCenter
} from '../../../../main/ets/utils/ChinaMapMetrics'

/**
 * ChinaMapMetrics 单元测试（形状/面积/方位三题型的度量底座）
 *
 * fixture 用可手算的正方形/矩形，避免依赖 rawfile；真实 34 省数据的排序保真度
 * 由 node 脚本对真 rawfile 复核（见 spec §17.4），这里只锁死公式与阈值。
 */

function makeProvince(id: string, short: string, path: string): ChinaProvince {
  const p: ChinaProvince = {
    id: id, name: short, short: short, abbr: 'X', capital: short + '市', region: '华北', path: path
  }
  return p
}

export default function chinaMapMetricsTest(): void {
  const big = makeProvince('1', '大省', 'M0 0L100 0L100 100L0 100Z')
  const small = makeProvince('2', '小省', 'M200 0L220 0L220 20L200 20Z')
  const west = makeProvince('3', '西省', 'M-300 0L-280 0L-280 20L-300 20Z')
  const south = makeProvince('4', '南省', 'M0 300L20 300L20 320L0 320Z')
  const diag = makeProvince('5', '斜省', 'M150 150L160 150L160 160L150 160Z')

  describe('chinaMapMetricsTest', () => {
    it('provinceArea_counts_square_area', 0, () => {
      expect(provinceArea(big)).assertEqual(10000)
      expect(provinceArea(small)).assertEqual(400)
    })

    it('provinceArea_sums_multiple_rings', 0, () => {
      const withIsland = makeProvince('6', '带岛省', 'M0 0L10 0L10 10L0 10ZM100 100L105 100L105 105L100 105Z')
      expect(provinceArea(withIsland)).assertEqual(100 + 25)
    })

    it('provinceCenter_matches_polygon_centroid', 0, () => {
      const center = provinceCenter(big)
      expect(Math.round(center.x)).assertEqual(50)
      expect(Math.round(center.y)).assertEqual(50)
    })

    it('dominantDirection_covers_four_axes', 0, () => {
      expect(dominantDirection(big, small)).assertEqual('东')
      expect(dominantDirection(small, big)).assertEqual('西')
      expect(dominantDirection(big, west)).assertEqual('西')
      expect(dominantDirection(big, south)).assertEqual('南')
      expect(dominantDirection(south, big)).assertEqual('北')
    })

    it('dominantDirection_rejects_diagonal_and_overlap', 0, () => {
      expect(dominantDirection(big, diag)).assertEqual('')
      expect(dominantDirection(big, big)).assertEqual('')
    })

    it('areaRatio_and_largerProvince', 0, () => {
      expect(Math.round(areaRatio(big, small))).assertEqual(25)
      expect(areaRatio(small, big)).assertEqual(areaRatio(big, small))
      expect(largerProvince(big, small)?.short).assertEqual('大省')
      expect(largerProvince(big, big) === null).assertTrue()
    })

    it('thresholds_are_documented_values', 0, () => {
      expect(AREA_MIN_RATIO).assertEqual(1.25)
      expect(DIRECTION_MIN_DOMINANCE).assertEqual(1.6)
      expect(MAP_DIRECTIONS.length).assertEqual(4)
      expect(MAP_DIRECTIONS.indexOf('北') >= 0).assertTrue()
    })
  })
}
