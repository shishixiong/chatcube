import { describe, it, expect } from '@ohos/hypium'
import { TtsSessionGuard } from '../../../../main/ets/utils/TtsSessionGuard'

// TtsSessionGuard 用单调 token 取代布尔 sessionClosed:
// stop() 后再 speak() 时, 上一次会话的迟到回调必须失效, 不能干扰新会话。

export default function ttsSessionGuardTest() {
  describe('TtsSessionGuard', () => {
    it('begin returns an active token', 0, () => {
      const guard = new TtsSessionGuard()
      const token = guard.begin()
      expect(guard.isActive(token)).assertTrue()
    })

    it('token zero is never active', 0, () => {
      expect(new TtsSessionGuard().isActive(0)).assertFalse()
    })

    it('invalidate makes the current token stale', 0, () => {
      const guard = new TtsSessionGuard()
      const token = guard.begin()
      guard.invalidate()
      expect(guard.isActive(token)).assertFalse()
    })

    it('stop then speak: old session token cannot abort the new one', 0, () => {
      const guard = new TtsSessionGuard()
      const first = guard.begin()
      guard.invalidate() // stop()
      const second = guard.begin() // speak()
      expect(guard.isActive(first)).assertFalse()
      expect(guard.isActive(second)).assertTrue()
    })

    it('each begin issues a distinct token', 0, () => {
      const guard = new TtsSessionGuard()
      const first = guard.begin()
      const second = guard.begin()
      expect(first === second).assertFalse()
      expect(guard.isActive(first)).assertFalse()
      expect(guard.isActive(second)).assertTrue()
    })
  })
}
