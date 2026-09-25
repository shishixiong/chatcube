import { describe, it, expect } from '@ohos/hypium'
import { hasStrokeOrder } from '../../../../main/ets/config/StrokeOrderData'

export default function strokeOrderCoverageTest() {
  describe('letter_trace 小写笔顺覆盖', () => {
    it('a-z 26 个小写字母全部有笔顺数据', 0, () => {
      let missing: string = ''
      for (let i = 0; i < 26; i++) {
        const ch = String.fromCharCode(97 + i)
        if (!hasStrokeOrder(ch)) {
          missing += ch
        }
      }
      expect(missing).assertEqual('')
    })
    it('A-Z 大写回归不受影响', 0, () => {
      expect(hasStrokeOrder('A')).assertTrue()
      expect(hasStrokeOrder('Z')).assertTrue()
    })
  })
}
