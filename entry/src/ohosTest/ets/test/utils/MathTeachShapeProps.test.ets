import { describe, it, expect } from '@ohos/hypium'
import {
  SHAPE_COUNTABLE, shapePropsSides, shapePropsCorners, shapePropsVertices, shapePropsEdges,
  shapePropsSteps, shapePropsStepNarrations, shapePropsSummary, shapePropsNameZh, isCountableShape,
  ShapePropsStep, ShapePropsEdge
} from '../../../../main/ets/utils/MathTeachShapeProps'

/**
 * MathTeachShapeProps 单元测试
 *
 * 图形特征纯函数：边角真值（含未知图形防御取界）、顶点几何落在 box 内、
 * 3 步演示文案与口播、摘要。
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * 本文件按 MathTeach* 惯例不注册进 List.test.ets（由人工在 IDE 中执行）
 */
export default function mathTeachShapePropsTest() {
  describe('mathTeachShapeProps', () => {
    it('四种可数图形的边角真值', 0, () => {
      expect(SHAPE_COUNTABLE.length).assertEqual(4)
      expect(shapePropsSides('triangle')).assertEqual(3)
      expect(shapePropsSides('square')).assertEqual(4)
      expect(shapePropsSides('rectangle')).assertEqual(4)
      expect(shapePropsSides('pentagon')).assertEqual(5)
      expect(shapePropsCorners('triangle')).assertEqual(3)
      expect(shapePropsCorners('square')).assertEqual(4)
      expect(shapePropsCorners('rectangle')).assertEqual(4)
      expect(shapePropsCorners('pentagon')).assertEqual(5)
    })

    it('未知图形防御取界为 0 与空数组', 0, () => {
      const bads: string[] = ['circle', 'star', 'heart', 'oval', '']
      for (let i = 0; i < bads.length; i++) {
        expect(shapePropsSides(bads[i])).assertEqual(0)
        expect(shapePropsCorners(bads[i])).assertEqual(0)
        expect(shapePropsVertices(bads[i], 160).length).assertEqual(0)
        expect(shapePropsEdges(bads[i], 160).length).assertEqual(0)
        expect(shapePropsSteps(bads[i]).length).assertEqual(0)
        expect(shapePropsSummary(bads[i])).assertEqual('')
        expect(shapePropsNameZh(bads[i])).assertEqual('')
        expect(isCountableShape(bads[i])).assertFalse()
      }
      expect(isCountableShape('square')).assertTrue()
    })

    it('顶点数量等于边数且坐标落在 box 内', 0, () => {
      const box: number = 160
      const shapes: string[] = ['triangle', 'square', 'rectangle', 'pentagon']
      for (let s = 0; s < shapes.length; s++) {
        const shape: string = shapes[s]
        const vertices: number[][] = shapePropsVertices(shape, box)
        expect(vertices.length).assertEqual(shapePropsSides(shape))
        for (let i = 0; i < vertices.length; i++) {
          expect(vertices[i].length).assertEqual(2)
          expect(vertices[i][0] >= 0 && vertices[i][0] <= box).assertTrue()
          expect(vertices[i][1] >= 0 && vertices[i][1] <= box).assertTrue()
        }
        const edges: ShapePropsEdge[] = shapePropsEdges(shape, box)
        expect(edges.length).assertEqual(shapePropsSides(shape))
      }
    })

    it('三步演示课文案与口播', 0, () => {
      const steps: ShapePropsStep[] = shapePropsSteps('square')
      expect(steps.length).assertEqual(3)
      expect(steps[0].title).assertEqual('认一认')
      expect(steps[0].chip).assertEqual('正方形')
      expect(steps[1].title).assertEqual('数边')
      expect(steps[1].chip).assertEqual('4 条边')
      expect(steps[1].desc).assertEqual('4 条边同样长')
      expect(steps[2].title).assertEqual('数角')
      expect(steps[2].chip).assertEqual('4 个角')
      expect(steps[2].narration.includes('边和角一样多')).assertTrue()
      expect(shapePropsStepNarrations('square').length).assertEqual(3)
      const rect: ShapePropsStep[] = shapePropsSteps('rectangle')
      expect(rect[1].desc).assertEqual('4 条边，对边同样长')
      const tri: ShapePropsStep[] = shapePropsSteps('triangle')
      expect(tri[2].chip).assertEqual('3 个角')
    })

    it('特征摘要在文案与真实边角一致', 0, () => {
      expect(shapePropsSummary('triangle')).assertEqual('3 条边 · 3 个角')
      expect(shapePropsSummary('square')).assertEqual('4 条边 · 4 个角')
      expect(shapePropsSummary('pentagon')).assertEqual('5 条边 · 5 个角')
    })
  })
}