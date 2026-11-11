import { describe, it, expect } from '@ohos/hypium'
import { summarizeCartoonPayload } from '../../../../main/ets/utils/CartoonCardUtils'

export default function cartoonCardUtilsTest() {
  describe('CartoonCardUtils', () => {
    it('daily_limit_is_not_rendered_as_watched_zero', 0, () => {
      const text = summarizeCartoonPayload('{"error":"daily_limit_reached"}')
      expect(text).assertEqual('今天看够啦')
      expect(text.indexOf('00:00') === -1).assertTrue()
    })

    it('session_limit_text', 0, () => {
      expect(summarizeCartoonPayload('{"error":"session_limit_reached"}')).assertEqual('这次看够啦')
    })

    it('unavailable_text', 0, () => {
      expect(summarizeCartoonPayload('{"error":"video_unavailable","should_retry":true}')).assertEqual('这一集打不开了')
    })

    it('too_long_text', 0, () => {
      expect(summarizeCartoonPayload('{"error":"video_too_long"}')).assertEqual('这一集太长了')
    })

    it('finished_payload_text', 0, () => {
      const text = summarizeCartoonPayload('{"completed":true,"watched_seconds":372,"ended_by":"finished"}')
      expect(text).assertEqual('已看完 06:12')
    })

    it('closed_payload_text', 0, () => {
      const text = summarizeCartoonPayload('{"completed":false,"watched_seconds":151,"ended_by":"closed"}')
      expect(text).assertEqual('看到 02:31 关掉了')
    })

    it('malformed_payload_is_empty', 0, () => {
      expect(summarizeCartoonPayload('')).assertEqual('')
      expect(summarizeCartoonPayload('{oops')).assertEqual('')
    })
  })
}
