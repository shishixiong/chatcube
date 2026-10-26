import { describe, it, expect } from '@ohos/hypium'
import { ChinaProvince } from '../../../../main/ets/utils/ChinaMapData'
import { MapTransform } from '../../../../main/ets/utils/ChinaMapTransform'
import {
  computePuzzleTransform,
  layoutTray,
  resolveDrop,
  trayRows,
  unionBBox
} from '../../../../main/ets/utils/MapPuzzleLayout'
import { HEBEI_PATH, SHANXI_PATH } from './ChinaMapFixture'

/**
 * MapPuzzleLayout 单元测试（中国地图拼图, spec 2026-10-26 §5.4 / plan Task 3）
 *
 * 坐标与断言值均由 node 原型对真实数据算得（2026-10-26）：
 *  - 山西 bbox = {633.21, 321.76, 699.37, 462.67}，河北质心距山西边界 25.8
 *  - 华北五省并集 bbox 在 340×300 棋盘上拟合比例 0.581
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */

function makeProvince(id: string, short: string, region: string, path: string): ChinaProvince {
  const p: ChinaProvince = {
    id: id,
    name: `${short}省`,
    short: short,
    abbr: 'X',
    capital: '某市',
    region: region,
    path: path
  }
  return p
}

const IDENTITY: MapTransform = { scale: 1, offsetX: 0, offsetY: 0 }

export default function mapPuzzleLayoutTest() {
  describe('unionBBox', () => {
    it('merges two squares', 0, () => {
      const a = makeProvince('1', '甲', '华北', 'M0 0L10 0L10 10L0 10Z')
      const b = makeProvince('2', '乙', '华北', 'M20 5L30 5L30 25L20 25Z')
      const bb = unionBBox([a, b])
      expect(bb.minX).assertEqual(0)
      expect(bb.minY).assertEqual(0)
      expect(bb.maxX).assertEqual(30)
      expect(bb.maxY).assertEqual(25)
    })

    it('returns zeros for an empty list', 0, () => {
      const bb = unionBBox([])
      expect(bb.minX).assertEqual(0)
      expect(bb.maxY).assertEqual(0)
    })
  })

  describe('computePuzzleTransform', () => {
    it('fits the group bbox into the board with padding', 0, () => {
      // bbox 200×100 放进 340×300（padding 26）→ avail 288×248 → min(1.44, 2.48) = 1.44
      const a = makeProvince('1', '甲', '华北', 'M0 0L100 0L100 100L0 100Z')
      const b = makeProvince('2', '乙', '华北', 'M100 0L200 0L200 100L100 100Z')
      const t = computePuzzleTransform([a, b], 340, 300)
      expect(Math.abs(t.scale - 1.44) < 1e-6).assertTrue()
      // 内容水平居中：offsetX = (340 - 288) / 2 = 26
      expect(Math.abs(t.offsetX - 26) < 1e-6).assertTrue()
    })

    it('keeps identity on a degenerate group', 0, () => {
      const t = computePuzzleTransform([], 340, 300)
      expect(t.scale).assertEqual(1)
      expect(t.offsetX).assertEqual(0)
    })
  })

  describe('layoutTray', () => {
    it('wraps after four pieces per row', 0, () => {
      const slots = layoutTray(5, 4, 56, 8, 12, 0)
      expect(slots.length).assertEqual(5)
      expect(slots[0].x).assertEqual(12)
      expect(slots[1].x).assertEqual(76)
      expect(slots[3].x).assertEqual(204)
      expect(slots[4].x).assertEqual(12)
      expect(slots[4].y).assertEqual(64)
    })

    it('reports the row count for the tray height', 0, () => {
      expect(trayRows(5, 4)).assertEqual(2)
      expect(trayRows(8, 4)).assertEqual(2)
      expect(trayRows(3, 4)).assertEqual(1)
      expect(trayRows(0, 4)).assertEqual(1)
    })
  })

  describe('resolveDrop', () => {
    const square = makeProvince('1', '方块', '华北', 'M0 0L10 0L10 10L0 10Z')

    it('hits inside the province', 0, () => {
      const r = resolveDrop(square, [], IDENTITY, 5, 5)
      expect(r.correct).assertTrue()
      expect(r.reason).assertEqual('hit')
    })

    it('accepts a finger-width miss', 0, () => {
      const r = resolveDrop(square, [], IDENTITY, 15, 5)   // 距边界 5 < 14
      expect(r.correct).assertTrue()
      expect(r.reason).assertEqual('tolerance')
    })

    it('rejects a far drop', 0, () => {
      const r = resolveDrop(square, [], IDENTITY, 30, 5)   // 距边界 20 > 14
      expect(r.correct).assertFalse()
      expect(r.reason).assertEqual('miss')
    })

    it('tolerance scales with the board zoom', 0, () => {
      // 同一屏幕距离，放大 2 倍后对应的地图距离减半 → 20 地图单位在 scale=2 时是 10vp < 14vp
      const zoomed: MapTransform = { scale: 2, offsetX: 0, offsetY: 0 }
      const r = resolveDrop(square, [], zoomed, 30, 10)   // 地图坐标 (15, 5) → 距边界 5
      expect(r.correct).assertTrue()
    })

    it('never accepts a drop on the neighbour province (Shanxi piece on Hebei)', 0, () => {
      const shanxi = makeProvince('140000', '山西', '华北', SHANXI_PATH)
      const hebei = makeProvince('130000', '河北', '华北', HEBEI_PATH)
      expect(hebei.short).assertEqual('河北')
      // 河北质心 (725.1, 345.4)：距山西边界 25.8 > 14vp 容差
      const r = resolveDrop(shanxi, [shanxi, hebei], IDENTITY, 725.1, 345.4)
      expect(r.correct).assertFalse()
      expect(r.reason).assertEqual('miss')
    })

    it('rejects a drop squarely inside a sibling, tolerance ring or not', 0, () => {
      // 方块 0-10，邻省 10-20；落点 12 距方块边界只有 2 < 14，但人在邻省身上 → occupied
      const neighbour = makeProvince('2', '邻省', '华北', 'M10 0L30 0L30 10L10 10Z')
      const r = resolveDrop(square, [square, neighbour], IDENTITY, 12, 5)
      expect(r.correct).assertFalse()
      expect(r.reason).assertEqual('occupied')
      // 同一落点：只有自己一块时（单省局）落在外面的 2 单位处仍算容差内
      const solo = resolveDrop(square, [square], IDENTITY, 12, 5)
      expect(solo.correct).assertTrue()
      expect(solo.reason).assertEqual('tolerance')
    })

    it('keeps the tolerance ring for drops in open water around a tiny province', 0, () => {
      // 澳门南侧是海：离省界 3vp 的空白处仍算对（海岸线靠这条规则可放）
      const tiny = makeProvince('820000', '澳门', '华南', 'M0 0L2 0L2 2L0 2Z')
      const sea = resolveDrop(tiny, [tiny], IDENTITY, 1, 5)   // 距边界 3 < 14
      expect(sea.correct).assertTrue()
      expect(sea.reason).assertEqual('tolerance')
    })

    it('accepts a near miss around a tiny province (Macau scale)', 0, () => {
      const tiny = makeProvince('820000', '澳门', '华南', 'M0 0L2 0L2 2L0 2Z')
      const near = resolveDrop(tiny, [tiny], IDENTITY, 10, 1)   // 距边界 8 < 14
      expect(near.correct).assertTrue()
      const far = resolveDrop(tiny, [tiny], IDENTITY, 20, 1)    // 距边界 18 > 14
      expect(far.correct).assertFalse()
    })
  })
}
