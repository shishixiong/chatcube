import { describe, it, expect } from '@ohos/hypium'
import { generateRedeemCode, isValidRedeemCode, REDEEM_CODE_RETRY_LIMIT } from '../../../../main/ets/utils/RedeemCodeUtils'

/**
 * 领取码生成/校验测试（spec §4.4 步骤 3、§9）
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */
const FORBIDDEN_CHARS: string = '0O1IL'

export default function redeemCodeUtilsTest() {
  describe('RedeemCodeUtils', () => {
    it('generate_长度6', 0, () => {
      expect(generateRedeemCode().length).assertEqual(6)
    })
    it('generate_不含混淆字符', 0, () => {
      for (let i = 0; i < 50; i++) {
        const code: string = generateRedeemCode()
        for (let j = 0; j < FORBIDDEN_CHARS.length; j++) {
          expect(code.indexOf(FORBIDDEN_CHARS[j]) < 0).assertTrue()
        }
      }
    })
    it('generate_随机性_50次不全部相同', 0, () => {
      const first: string = generateRedeemCode()
      let allSame: boolean = true
      for (let i = 0; i < 50; i++) {
        if (generateRedeemCode() !== first) {
          allSame = false
          break
        }
      }
      expect(allSame).assertFalse()
    })
    it('isValid_合法与非法', 0, () => {
      expect(isValidRedeemCode(generateRedeemCode())).assertTrue()
      expect(isValidRedeemCode('A7K2QD')).assertTrue()
      expect(isValidRedeemCode('A7K2Q')).assertFalse()
      expect(isValidRedeemCode('A7K2QDD')).assertFalse()
      expect(isValidRedeemCode('A7K2Q0')).assertFalse()
      expect(isValidRedeemCode('a7k2qd')).assertFalse()
      expect(isValidRedeemCode('')).assertFalse()
    })
    it('RETRY_LIMIT_为3', 0, () => {
      expect(REDEEM_CODE_RETRY_LIMIT).assertEqual(3)
    })
  })
}
