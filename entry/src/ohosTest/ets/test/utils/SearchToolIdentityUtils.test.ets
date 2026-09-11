import { describe, it, expect } from '@ohos/hypium'
import { isInteractiveQuizFunctionName } from '../../../../main/ets/utils/SearchToolIdentityUtils'

/**
 * SearchToolIdentityUtils.isInteractiveQuizFunctionName 单元测试。
 *
 * 该判定是 ChatViewModel 单回合出题上限（MAX_INTERACTIVE_QUIZZES_PER_TURN）的
 * 收敛条件——覆盖 13 个挂起等待孩子作答的出题/游戏工具（含 legacy huarongdao），
 * 并明确排除即时返回的后端工具（grant_star / child_profile / math_verify）与
 * 搜索/生图/音乐类工具，防止把非出题工具误计入上限。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */
export default function searchToolIdentityUtilsTest() {
  describe('isInteractiveQuizFunctionName', () => {
    it('accepts all interactive quiz/game tools', 0, () => {
      const quizNames: string[] = [
        'math_quiz', 'english_quiz', 'picture_vocab', 'listening_quiz',
        'pinyin_quiz', 'matching_pairs', 'number_puzzle', 'huarongdao',
        'handwriting_practice', 'categorization', 'vertical_math',
        'maze', 'sudoku'
      ]
      for (let i = 0; i < quizNames.length; i++) {
        expect(isInteractiveQuizFunctionName(quizNames[i])).assertTrue()
      }
    })

    it('accepts known legacy aliases of interactive tools', 0, () => {
      expect(isInteractiveQuizFunctionName('picture_vocabulary')).assertTrue()
      expect(isInteractiveQuizFunctionName('listen_and_choose')).assertTrue()
      expect(isInteractiveQuizFunctionName('match_pairs')).assertTrue()
      expect(isInteractiveQuizFunctionName('number_sliding_puzzle')).assertTrue()
      expect(isInteractiveQuizFunctionName('classify')).assertTrue()
      expect(isInteractiveQuizFunctionName('learn_to_write')).assertTrue()
    })

    it('normalizes case and separators before matching', 0, () => {
      expect(isInteractiveQuizFunctionName('Math-Quiz')).assertTrue()
      expect(isInteractiveQuizFunctionName('  ENGLISH_QUIZ  ')).assertTrue()
    })

    it('rejects instant-return backend tools (not quizzes)', 0, () => {
      expect(isInteractiveQuizFunctionName('grant_star')).assertFalse()
      expect(isInteractiveQuizFunctionName('child_profile')).assertFalse()
      expect(isInteractiveQuizFunctionName('math_verify')).assertFalse()
      expect(isInteractiveQuizFunctionName('get_time_info')).assertFalse()
    })

    it('rejects search / image / music / ask_user tools', 0, () => {
      expect(isInteractiveQuizFunctionName('search_web')).assertFalse()
      expect(isInteractiveQuizFunctionName('scrape_web')).assertFalse()
      expect(isInteractiveQuizFunctionName('image_generation')).assertFalse()
      expect(isInteractiveQuizFunctionName('music_generation')).assertFalse()
      expect(isInteractiveQuizFunctionName('ask_user')).assertFalse()
    })

    it('rejects empty and unknown names', 0, () => {
      expect(isInteractiveQuizFunctionName('')).assertFalse()
      expect(isInteractiveQuizFunctionName('unknown_tool')).assertFalse()
    })
  })
}
