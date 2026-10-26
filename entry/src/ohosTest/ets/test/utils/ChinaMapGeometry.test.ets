import { describe, it, expect } from '@ohos/hypium'
import { parseProvincePolygons, pointInProvince, provinceBBox, provinceEdgeDistance } from '../../../../main/ets/utils/ChinaMapGeometry'
import { BEIJING_PATH, HEBEI_PATH, SHANXI_PATH, GUANGDONG_PATH, ALL_PROVINCE_PATHS } from './ChinaMapFixture'

/**
 * ChinaMapGeometry 纯函数单元测试（中国地图教学工具, plan Task 2）
 *
 * 真实坐标来源：2026-10-21 从 docs/map-learning/assets_china-provinces.js 射线法程序计算，
 * node 原型已对全部断言坐标验证通过（含 evenodd 洞/岛语义）。
 * 北京 centroid(730.0,329.5) 在北京环内；同一坐标在河北 = false（北京是河北外环的洞）。
 * 山西 centroid(671.3,391.5)；广东 ring0 centroid(709.0,707.9)（20 子路径含岛屿）；
 * 海点(891.6,681.5) 不属任何省。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

const SQUARE = 'M0 0L10 0L10 10Z'
const SQUARE_WITH_HOLE = 'M0 0L10 0L10 10ZM4 4L6 4L6 6L4 6Z'

export default function chinaMapGeometryTest() {
  describe('parseProvincePolygons', () => {
    it('parses a single closed ring', 0, () => {
      const rings = parseProvincePolygons(SQUARE)
      expect(rings.length).assertEqual(1)
      expect(rings[0].length).assertEqual(4)
    })

    it('splits multiple ZM subpaths into separate rings', 0, () => {
      const rings = parseProvincePolygons(SQUARE_WITH_HOLE)
      expect(rings.length).assertEqual(2)
    })

    it('returns empty array for empty path', 0, () => {
      expect(parseProvincePolygons('').length).assertEqual(0)
    })
  })

  describe('pointInProvince', () => {
    it('point inside square', 0, () => {
      expect(pointInProvince(SQUARE, 5, 5)).assertTrue()
    })

    it('point outside square', 0, () => {
      expect(pointInProvince(SQUARE, 15, 5)).assertFalse()
    })

    it('hole center is outside under evenodd rule', 0, () => {
      expect(pointInProvince(SQUARE_WITH_HOLE, 5, 5)).assertFalse()
    })

    it('point between outer ring and hole is inside', 0, () => {
      expect(pointInProvince(SQUARE_WITH_HOLE, 1, 1)).assertTrue()
    })

    it('empty path returns false', 0, () => {
      expect(pointInProvince('', 5, 5)).assertFalse()
    })

    it('real Beijing centroid is inside Beijing', 0, () => {
      expect(pointInProvince(BEIJING_PATH, 730.0, 329.5)).assertTrue()
    })

    it('real Beijing centroid is NOT inside Hebei (hole semantics)', 0, () => {
      expect(pointInProvince(HEBEI_PATH, 730.0, 329.5)).assertFalse()
    })

    it('real Shanxi centroid is inside Shanxi', 0, () => {
      expect(pointInProvince(SHANXI_PATH, 671.3, 391.5)).assertTrue()
    })

    it('real Guangdong mainland centroid is inside Guangdong (20 subpaths)', 0, () => {
      expect(pointInProvince(GUANGDONG_PATH, 709.0, 707.9)).assertTrue()
    })
  })

  describe('provinceBBox', () => {
    it('computes bbox of square', 0, () => {
      const b = provinceBBox(SQUARE)
      expect(b.minX).assertEqual(0)
      expect(b.minY).assertEqual(0)
      expect(b.maxX).assertEqual(10)
      expect(b.maxY).assertEqual(10)
    })

    it('empty path returns zeroed bbox', 0, () => {
      const b = provinceBBox('')
      expect(b.minX).assertEqual(0)
      expect(b.minY).assertEqual(0)
      expect(b.maxX).assertEqual(0)
      expect(b.maxY).assertEqual(0)
    })
  })

  describe('provinceEdgeDistance', () => {
    const SQUARE10 = 'M0 0L10 0L10 10L0 10Z'

    it('returns 0 for a point inside', 0, () => {
      expect(provinceEdgeDistance(SQUARE10, 5, 5)).assertEqual(0)
    })

    it('measures the distance to the nearest edge', 0, () => {
      expect(provinceEdgeDistance(SQUARE10, 15, 5)).assertEqual(5)
      expect(provinceEdgeDistance(SQUARE10, 5, 20)).assertEqual(10)
    })

    it('handles a concave (L shaped) province', 0, () => {
      // 凹口点：最近的边是 y=40 那一段，距离 10
      const L = 'M0 0L40 0L40 40L100 40L100 100L0 100Z'
      expect(provinceEdgeDistance(L, 70, 30)).assertEqual(10)
    })

    it('keeps a finger-width tolerance out of the neighbour province', 0, () => {
      // 山西碎片丢到河北质心：距山西边界约 25.7（> 14vp 容差），必须判外行
      expect(provinceEdgeDistance(SHANXI_PATH, 725.1, 345.4) > 20).assertTrue()
      // 而山西质心自身在省内
      expect(provinceEdgeDistance(SHANXI_PATH, 671.3, 391.5)).assertEqual(0)
    })

    it('works for a tiny province (Macau scale)', 0, () => {
      const tiny = 'M0 0L2 0L2 2L0 2Z'
      expect(provinceEdgeDistance(tiny, 10, 1)).assertEqual(8)
    })
  })

  describe('real full dataset', () => {
    it('sea point (891.6, 681.5) is in no province', 0, () => {
      let anyHit = false
      for (const p of ALL_PROVINCE_PATHS) {
        if (pointInProvince(p, 891.6, 681.5)) {
          anyHit = true
        }
      }
      expect(anyHit).assertFalse()
    })

    it('all 34 province paths are non-empty polygons', 0, () => {
      for (const p of ALL_PROVINCE_PATHS) {
        expect(parseProvincePolygons(p).length > 0).assertTrue()
      }
    })
  })
}
