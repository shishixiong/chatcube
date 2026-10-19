/**
 * 领取码生成/校验（spec §4.4 步骤 3）。
 * 字符集去掉视觉混淆字符 0/O/1/I/L，方便家长口头读码、孩子抄写。
 * 6 位字母数字（去混淆后 31 字符集），空间 31^6 ≈ 8.9 亿，单家庭场景碰撞可忽略；
 * 服务层仍会对 pending 记录做碰撞重试（REDEEM_CODE_RETRY_LIMIT 次）。
 */

const REDEEM_CODE_LENGTH: number = 6
const REDEEM_CODE_CHARSET: string = '23456789ABCDEFGHJKMNPQRSTUVWXYZ'

export const REDEEM_CODE_RETRY_LIMIT: number = 3

export function generateRedeemCode(): string {
  let code = ''
  for (let i = 0; i < REDEEM_CODE_LENGTH; i++) {
    const idx: number = Math.floor(Math.random() * REDEEM_CODE_CHARSET.length)
    code += REDEEM_CODE_CHARSET[idx]
  }
  return code
}

export function isValidRedeemCode(code: string): boolean {
  if (code.length !== REDEEM_CODE_LENGTH) {
    return false
  }
  for (let i = 0; i < code.length; i++) {
    if (REDEEM_CODE_CHARSET.indexOf(code[i]) < 0) {
      return false
    }
  }
  return true
}
