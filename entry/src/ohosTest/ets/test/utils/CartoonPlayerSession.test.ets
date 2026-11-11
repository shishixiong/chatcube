import { describe, it, expect } from '@ohos/hypium'
import {
  beginCartoonPlayerSession,
  endCartoonPlayerSession,
  getActiveCartoonPlayerToolCallId
} from '../../../../main/ets/utils/CartoonPlayerSession'

export default function cartoonPlayerSessionTest() {
  describe('CartoonPlayerSession', () => {
    it('same_tool_call_cannot_open_twice', 0, () => {
      endCartoonPlayerSession('a')
      expect(beginCartoonPlayerSession('a')).assertTrue()
      expect(beginCartoonPlayerSession('a')).assertFalse()
      expect(getActiveCartoonPlayerToolCallId()).assertEqual('a')
    })

    it('other_call_is_blocked_while_active', 0, () => {
      endCartoonPlayerSession('a')
      beginCartoonPlayerSession('a')
      expect(beginCartoonPlayerSession('b')).assertFalse()
      expect(getActiveCartoonPlayerToolCallId()).assertEqual('a')
    })

    it('end_only_clears_matching_call', 0, () => {
      endCartoonPlayerSession('a')
      beginCartoonPlayerSession('a')
      endCartoonPlayerSession('b')
      expect(getActiveCartoonPlayerToolCallId()).assertEqual('a')
      endCartoonPlayerSession('a')
      expect(getActiveCartoonPlayerToolCallId()).assertEqual('')
      expect(beginCartoonPlayerSession('b')).assertTrue()
      endCartoonPlayerSession('b')
    })
  })
}
