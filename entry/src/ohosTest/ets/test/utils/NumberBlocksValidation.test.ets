/*
 * NumberBlocksValidation 单元测试（认数字卡片, plan Task 1 / spec §3）
 *
 * 运行（无 DevEco 时）:
 *   .superpowers/harness/run-test.sh \
 *     entry/src/ohosTest/ets/test/utils/NumberBlocksValidation.test.ets \
 *     entry/src/main/ets/utils/NumberBlocksValidation.ets
 * 或在 DevEco Studio 里右键 Run 'hypium test'。
 */

import { describe, it, expect } from '@ohos/hypium'
import {
  allNumberBlocks,
  NUMBER_BLOCKS_MAX,
  validateNumberBlocksArgs
} from '../../../../main/ets/utils/NumberBlocksValidation'

export default function numberBlocksValidationTest() {
  describe('NumberBlocksValidation', () => {
    it('allNumberBlocks 返回 1..20', 0, () => {
      const all = allNumberBlocks()
      expect(all.length).assertEqual(NUMBER_BLOCKS_MAX)
      expect(all[0]).assertEqual(1)
      expect(all[19]).assertEqual(20)
    })

    it('空对象合法, numbers 为空表示全部', 0, () => {
      const r = validateNumberBlocksArgs('{}')
      expect(r.ok).assertTrue()
      expect(r.numbers.length).assertEqual(0)
      expect(r.focus).assertEqual(1)
      expect(r.mode).assertEqual('display')
    })

    it('numbers 去重并升序', 0, () => {
      const r = validateNumberBlocksArgs('{"numbers":[3,1,2,3]}')
      expect(r.ok).assertTrue()
      expect(r.numbers.length).assertEqual(3)
      expect(r.numbers[0]).assertEqual(1)
      expect(r.numbers[2]).assertEqual(3)
    })

    it('focus 不在 numbers 里时回落到第一个', 0, () => {
      const r = validateNumberBlocksArgs('{"numbers":[4,5],"focus":9}')
      expect(r.ok).assertTrue()
      expect(r.focus).assertEqual(4)
    })

    it('focus 在 numbers 里时保留', 0, () => {
      const r = validateNumberBlocksArgs('{"numbers":[4,5,6],"focus":5}')
      expect(r.focus).assertEqual(5)
    })

    it('拒绝超出 1-20 的数字', 0, () => {
      const r = validateNumberBlocksArgs('{"numbers":[0,21]}')
      expect(r.ok).assertFalse()
      expect(r.error.length > 0).assertTrue()
    })

    it('拒绝非整数', 0, () => {
      expect(validateNumberBlocksArgs('{"numbers":[1.5]}').ok).assertFalse()
      expect(validateNumberBlocksArgs('{"focus":2.5}').ok).assertFalse()
    })

    it('拒绝非数组 numbers', 0, () => {
      expect(validateNumberBlocksArgs('{"numbers":"3"}').ok).assertFalse()
    })

    it('拒绝 v1 不支持的 mode', 0, () => {
      expect(validateNumberBlocksArgs('{"mode":"split"}').ok).assertFalse()
      expect(validateNumberBlocksArgs('{"mode":"display"}').ok).assertTrue()
    })

    it('拒绝坏 JSON 与非对象 JSON', 0, () => {
      expect(validateNumberBlocksArgs('not json').ok).assertFalse()
      expect(validateNumberBlocksArgs('null').ok).assertFalse()
      expect(validateNumberBlocksArgs('[1,2]').ok).assertFalse()
    })
  })
}
