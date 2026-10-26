import { describe, it, expect } from '@ohos/hypium'
import { MapBBox } from '../../../../main/ets/utils/ChinaMapGeometry'
import {
  createFitTransform,
  MapTransform,
  mapToScreen,
  screenLengthToMap,
  screenToMap
} from '../../../../main/ets/utils/ChinaMapTransform'

/**
 * ChinaMapTransform 单元测试（中国地图拼图, spec 2026-10-26 §5.2 / plan Task 2）
 *
 * 断言值由 node 原型算得：bbox{100,200,500,600} 放进 340×300（padding 26）
 * → scale 0.62 / offset(-16, -98)，bbox 中心 (300,400) 映射到视口中心 (170,150)。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */

const BBOX: MapBBox = { minX: 100, minY: 200, maxX: 500, maxY: 600 }

export default function chinaMapTransformTest() {
  describe('createFitTransform', () => {
    it('fits without distortion and centres the content', 0, () => {
      const t = createFitTransform(BBOX, 340, 300, 26)
      // avail 288×248，内容 400×400 → 0.62
      expect(Math.abs(t.scale - 0.62) < 1e-9).assertTrue()
      expect(Math.abs(t.offsetX - (-16)) < 1e-9).assertTrue()
      expect(Math.abs(t.offsetY - (-98)) < 1e-9).assertTrue()
      const centre = mapToScreen(t, 300, 400)
      expect(Math.round(centre.x)).assertEqual(170)
      expect(Math.round(centre.y)).assertEqual(150)
    })

    it('keeps square pixels (uniform scale both axes)', 0, () => {
      const t = createFitTransform(BBOX, 340, 300, 26)
      const a = mapToScreen(t, 100, 200)
      const b = mapToScreen(t, 200, 300)
      expect(Math.abs((b.x - a.x) - (b.y - a.y)) < 1e-9).assertTrue()
    })

    it('falls back to identity for a degenerate bbox', 0, () => {
      const flat: MapBBox = { minX: 5, minY: 5, maxX: 5, maxY: 5 }
      const t = createFitTransform(flat, 340, 300, 26)
      expect(t.scale).assertEqual(1)
      expect(t.offsetX).assertEqual(0)
      expect(t.offsetY).assertEqual(0)
    })

    it('falls back to identity for an empty viewport', 0, () => {
      const t = createFitTransform(BBOX, 0, 0, 26)
      expect(t.scale).assertEqual(1)
    })
  })

  describe('screenToMap', () => {
    it('round-trips with mapToScreen', 0, () => {
      const t = createFitTransform(BBOX, 340, 300, 26)
      const m = screenToMap(t, 123, 77)
      const s = mapToScreen(t, m.x, m.y)
      expect(Math.abs(s.x - 123) < 1e-6).assertTrue()
      expect(Math.abs(s.y - 77) < 1e-6).assertTrue()
    })

    it('converts a vp length into map units', 0, () => {
      const t = createFitTransform(BBOX, 340, 300, 26)   // scale 0.62
      expect(Math.abs(screenLengthToMap(t, 14) - (14 / 0.62)) < 1e-6).assertTrue()
    })

    it('survives a zero scale without NaN', 0, () => {
      const broken: MapTransform = { scale: 0, offsetX: 0, offsetY: 0 }
      const p = screenToMap(broken, 10, 10)
      expect(Number.isNaN(p.x)).assertFalse()
    })
  })
}
