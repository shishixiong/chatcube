import { describe, it, expect } from '@ohos/hypium'
import {
  validateChineseQuizArgs,
  CHINESE_QUIZ_MODES
} from '../../../../main/ets/utils/ChineseQuizValidation'

/**
 * ChineseQuizValidation 单元测试
 *
 * 覆盖四个 mode 的硬校验 + explanation 必填 (2026-11-19 新增)。
 * 语义正确性 (反义词是否成立 / 组词是否成词) 无法程序判定, 不在本测试范围。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */

function buildArgs(overrides: Record<string, Object>): string {
  return JSON.stringify(overrides)
}

/** word_build 的合法基线, 各用例覆写单个字段 */
function wordBuildBase(): Record<string, Object> {
  return {
    mode: 'word_build',
    character: '花',
    options: ['花朵', '火车', '水杯', '石头'],
    answer: '花朵',
    explanation: '花朵是花开的，别的词跟花没关系呀',
    difficulty: 1,
    skill_key: 'chinese_vocab'
  }
}

export default function chineseQuizValidationTest() {
  describe('validateChineseQuizArgs - mode 分派', () => {
    it('四个合法 mode 均被接受', 0, () => {
      expect(CHINESE_QUIZ_MODES.length).assertEqual(4)
      expect(CHINESE_QUIZ_MODES.includes('word_build')).assertTrue()
      expect(CHINESE_QUIZ_MODES.includes('sentence_order')).assertTrue()
      expect(CHINESE_QUIZ_MODES.includes('lookalike')).assertTrue()
      expect(CHINESE_QUIZ_MODES.includes('antonym')).assertTrue()
    })

    it('未知 mode 被拒绝并列出可选值', 0, () => {
      const args = wordBuildBase()
      args['mode'] = 'fill_blank'
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('mode')).assertTrue()
      expect(r.error.includes('word_build')).assertTrue()
    })

    it('非法 JSON 被拒绝', 0, () => {
      const r = validateChineseQuizArgs('{not json')
      expect(r.ok).assertFalse()
      expect(r.error.includes('JSON')).assertTrue()
    })
  })

  describe('word_build 组词造句', () => {
    it('合法基线通过', 0, () => {
      const r = validateChineseQuizArgs(buildArgs(wordBuildBase()))
      expect(r.ok).assertTrue()
    })

    it('character 非单个汉字被拒绝', 0, () => {
      const args = wordBuildBase()
      args['character'] = '花朵'
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('单个汉字')).assertTrue()
    })

    it('answer 不含本字被拒绝', 0, () => {
      const args = wordBuildBase()
      args['answer'] = '火车'
      args['options'] = ['火车', '水杯', '石头', '月亮']
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('不含本字')).assertTrue()
    })
  })

  describe('选型通用校验 (options / answer)', () => {
    it('options 不是 4 个被拒绝', 0, () => {
      const args = wordBuildBase()
      args['options'] = ['花朵', '火车', '水杯']
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('4')).assertTrue()
    })

    it('options 有重复被拒绝', 0, () => {
      const args = wordBuildBase()
      args['options'] = ['花朵', '花朵', '水杯', '石头']
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('重复')).assertTrue()
    })

    it('answer 不在 options 内被拒绝', 0, () => {
      const args = wordBuildBase()
      args['answer'] = '花园'
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('不在选项')).assertTrue()
    })
  })

  describe('sentence_order 连词成句', () => {
    function base(): Record<string, Object> {
      return {
        mode: 'sentence_order',
        words: ['花园', '里', '小猫', '在'],
        answer: '小猫在花园里',
        explanation: '谁 + 在 + 哪里，先说小猫再说地方',
        difficulty: 2,
        skill_key: 'chinese_reading'
      }
    }

    it('合法基线通过 (answer 可由词卡还原)', 0, () => {
      const r = validateChineseQuizArgs(buildArgs(base()))
      expect(r.ok).assertTrue()
    })

    it('answer 无法由词卡还原时被拒绝 (防漏词/错字)', 0, () => {
      const args = base()
      args['answer'] = '小狗在花园里'
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('还原')).assertTrue()
    })

    it('词卡少于 2 个被拒绝', 0, () => {
      const args = base()
      args['words'] = ['小猫']
      args['answer'] = '小猫'
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('2-6')).assertTrue()
    })

    it('标点不参与多重集比较 (answer 带句号仍通过)', 0, () => {
      const args = base()
      args['answer'] = '小猫在花园里。'
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertTrue()
    })
  })

  describe('lookalike 形近字辨析', () => {
    function base(): Record<string, Object> {
      return {
        mode: 'lookalike',
        stem: '小明去___山。',
        options: ['爬', '爪', '巴', '把'],
        answer: '爬',
        explanation: '爬山要用脚，爪是爪子的爪',
        difficulty: 2,
        skill_key: 'chinese_vocab'
      }
    }

    it('合法基线通过', 0, () => {
      const r = validateChineseQuizArgs(buildArgs(base()))
      expect(r.ok).assertTrue()
    })

    it('stem 没有 ___ 被拒绝', 0, () => {
      const args = base()
      args['stem'] = '小明去爬山。'
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('___')).assertTrue()
    })

    it('stem 有两个 ___ 被拒绝', 0, () => {
      const args = base()
      args['stem'] = '___去___山。'
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('1 个')).assertTrue()
    })

    it('选项不是单字被拒绝', 0, () => {
      const args = base()
      args['options'] = ['爬山', '爪', '巴', '把']
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('单个汉字')).assertTrue()
    })
  })

  describe('antonym 近反义词', () => {
    function base(): Record<string, Object> {
      return {
        mode: 'antonym',
        character: '大',
        options: ['小', '多', '高', '快'],
        answer: '小',
        explanation: '大和小是反过来的，一个大一个小',
        difficulty: 1,
        skill_key: 'chinese_vocab'
      }
    }

    it('合法基线通过', 0, () => {
      const r = validateChineseQuizArgs(buildArgs(base()))
      expect(r.ok).assertTrue()
    })

    it('answer 等于 character 被拒绝', 0, () => {
      const args = base()
      args['answer'] = '大'
      args['options'] = ['大', '多', '高', '快']
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('相同')).assertTrue()
    })
  })

  describe('explanation 必填 (2026-11-19 新增)', () => {
    it('缺少 explanation 被拒绝', 0, () => {
      const args = wordBuildBase()
      delete args['explanation']
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('explanation')).assertTrue()
    })

    it('explanation 为空白被拒绝', 0, () => {
      const args = wordBuildBase()
      args['explanation'] = '   '
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('explanation')).assertTrue()
    })

    it('explanation 超长被拒绝 (防长篇大论)', 0, () => {
      const args = wordBuildBase()
      args['explanation'] = '这'.repeat(70)
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('太长')).assertTrue()
    })

    it('sentence_order 同样要求 explanation', 0, () => {
      const r = validateChineseQuizArgs(buildArgs({
        mode: 'sentence_order',
        words: ['小猫', '在', '家里'],
        answer: '小猫在家里',
        difficulty: 1,
        skill_key: 'chinese_reading'
      }))
      expect(r.ok).assertFalse()
      expect(r.error.includes('explanation')).assertTrue()
    })
  })

  describe('difficulty 边界', () => {
    it('difficulty 为 0 被拒绝', 0, () => {
      const args = wordBuildBase()
      args['difficulty'] = 0
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
      expect(r.error.includes('1-3')).assertTrue()
    })

    it('difficulty 为 4 被拒绝', 0, () => {
      const args = wordBuildBase()
      args['difficulty'] = 4
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
    })

    it('difficulty 非数字被拒绝', 0, () => {
      const args = wordBuildBase()
      args['difficulty'] = '2'
      const r = validateChineseQuizArgs(buildArgs(args))
      expect(r.ok).assertFalse()
    })
  })
}
