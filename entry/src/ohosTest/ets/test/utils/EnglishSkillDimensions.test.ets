import { describe, it, expect } from '@ohos/hypium'
import {
  skillDimensionLevel,
  weakDimensionsFor,
  LearningItem,
  LEDGER_DIM_RECOGNIZE,
  LEDGER_DIM_LISTEN,
  LEDGER_DIM_READ,
  LEDGER_DIM_WRITE,
  dimensionLabel
} from '../../../../main/ets/models/LearningLedgerModels'
import { skillDimensionFor } from '../../../../main/ets/utils/LedgerExtractUtils'

/**
 * 英语四维掌握度纯函数测试 (2026-11-03)
 * 覆盖: 工具/mode → 维度映射, 0-5 维度推导, 弱项排序。
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test' (CLI hvigorw test 不可用)
 */

function freshItem(): LearningItem {
  return new LearningItem()
}

export default function englishSkillDimensionsTest(): void {
  describe('skillDimensionFor - 工具/mode → 维度', () => {
    it('english_quiz 七 mode 映射', 0, () => {
      expect(skillDimensionFor('english_quiz', 'english_quiz.spell_word', 'en')).assertEqual(LEDGER_DIM_WRITE)
      expect(skillDimensionFor('english_quiz', 'english_quiz.read_aloud', 'en')).assertEqual(LEDGER_DIM_READ)
      expect(skillDimensionFor('english_quiz', 'english_quiz.listen_choice', 'en')).assertEqual(LEDGER_DIM_LISTEN)
      expect(skillDimensionFor('english_quiz', 'english_quiz.phonics_blend', 'en')).assertEqual(LEDGER_DIM_LISTEN)
      expect(skillDimensionFor('english_quiz', 'english_quiz.picture_word', 'en')).assertEqual(LEDGER_DIM_RECOGNIZE)
      expect(skillDimensionFor('english_quiz', 'english_quiz.sentence_fill', 'en')).assertEqual(LEDGER_DIM_RECOGNIZE)
    })

    it('english_quiz legacy 题型映射', 0, () => {
      expect(skillDimensionFor('english_quiz', 'english_quiz.phonics_choice', 'en')).assertEqual(LEDGER_DIM_LISTEN)
      expect(skillDimensionFor('english_quiz', 'english_quiz.word', 'en')).assertEqual(LEDGER_DIM_WRITE)
      expect(skillDimensionFor('english_quiz', 'english_quiz.sentence', 'en')).assertEqual(LEDGER_DIM_WRITE)
    })

    it('其他英语工具映射', 0, () => {
      expect(skillDimensionFor('picture_vocab', '', 'en')).assertEqual(LEDGER_DIM_RECOGNIZE)
      expect(skillDimensionFor('listening_quiz', '', 'en')).assertEqual(LEDGER_DIM_LISTEN)
      expect(skillDimensionFor('matching_pairs', '', 'en')).assertEqual(LEDGER_DIM_RECOGNIZE)
      expect(skillDimensionFor('handwriting_practice', '', 'en')).assertEqual(LEDGER_DIM_WRITE)
    })

    it('讲解型/未知工具返回空串', 0, () => {
      expect(skillDimensionFor('room_english', '', 'en')).assertEqual('')
      expect(skillDimensionFor('city_english', '', 'en')).assertEqual('')
      expect(skillDimensionFor('hanzi_card', '', 'zh')).assertEqual('')
      expect(skillDimensionFor('math_quiz', '', 'en')).assertEqual('')
    })

    it('非英语学科返回空串', 0, () => {
      expect(skillDimensionFor('english_quiz', 'english_quiz.spell_word', 'zh')).assertEqual('')
    })

    it('dimensionLabel 中文标签', 0, () => {
      expect(dimensionLabel(LEDGER_DIM_RECOGNIZE)).assertEqual('认')
      expect(dimensionLabel(LEDGER_DIM_LISTEN)).assertEqual('听')
      expect(dimensionLabel(LEDGER_DIM_READ)).assertEqual('读')
      expect(dimensionLabel(LEDGER_DIM_WRITE)).assertEqual('写')
    })
  })

  describe('skillDimensionLevel - 0-5 推导', () => {
    it('未测 → 0', 0, () => {
      expect(skillDimensionLevel(0, 0)).assertEqual(0)
    })

    it('1 次样本: 对 → 2, 错 → 1', 0, () => {
      expect(skillDimensionLevel(1, 1)).assertEqual(2)
      expect(skillDimensionLevel(0, 1)).assertEqual(1)
    })

    it('2 次样本: 全对 → 3, 一对 → 2, 全错 → 1', 0, () => {
      expect(skillDimensionLevel(2, 2)).assertEqual(3)
      expect(skillDimensionLevel(1, 2)).assertEqual(2)
      expect(skillDimensionLevel(0, 2)).assertEqual(1)
    })

    it('3+ 次样本按正确率分级', 0, () => {
      expect(skillDimensionLevel(9, 10)).assertEqual(5)
      expect(skillDimensionLevel(8, 10)).assertEqual(4)
      expect(skillDimensionLevel(5, 10)).assertEqual(3)
      expect(skillDimensionLevel(3, 10)).assertEqual(2)
      expect(skillDimensionLevel(1, 10)).assertEqual(1)
      expect(skillDimensionLevel(0, 10)).assertEqual(1)
    })
  })

  describe('weakDimensionsFor - 弱项优先级', () => {
    it('全新词: 未测维度按 认/听 顺序取 2 个', 0, () => {
      const weak = weakDimensionsFor(freshItem())
      expect(weak.length).assertEqual(2)
      expect(weak[0]).assertEqual(LEDGER_DIM_RECOGNIZE)
      expect(weak[1]).assertEqual(LEDGER_DIM_LISTEN)
    })

    it('只测过「写」且答错: 未测维度仍优先', 0, () => {
      const item = freshItem()
      item.writeTries = 1
      item.writeOk = 0
      const weak = weakDimensionsFor(item)
      expect(weak.length).assertEqual(2)
      expect(weak[0]).assertEqual(LEDGER_DIM_RECOGNIZE)
      expect(weak[1]).assertEqual(LEDGER_DIM_LISTEN)
    })

    it('全部维度稳定 (level ≥ 3) → 无弱项', 0, () => {
      const item = freshItem()
      item.recognizeTries = 3
      item.recognizeOk = 3
      item.listenTries = 3
      item.listenOk = 3
      item.readTries = 3
      item.readOk = 3
      item.writeTries = 3
      item.writeOk = 3
      expect(weakDimensionsFor(item).length).assertEqual(0)
    })

    it('全部测过但都弱: 按 level 升序', 0, () => {
      const item = freshItem()
      item.recognizeTries = 1
      item.recognizeOk = 0   // level 1
      item.listenTries = 3
      item.listenOk = 1      // level 2
      item.readTries = 3
      item.readOk = 3        // level 5, 不算弱项
      item.writeTries = 1
      item.writeOk = 0       // level 1
      const weak = weakDimensionsFor(item)
      expect(weak.length).assertEqual(2)
      expect(weak[0]).assertEqual(LEDGER_DIM_RECOGNIZE)
      expect(weak[1]).assertEqual(LEDGER_DIM_WRITE)
    })

    it('最多返回 2 个弱项', 0, () => {
      const item = freshItem()
      item.recognizeTries = 2
      item.recognizeOk = 0
      item.listenTries = 2
      item.listenOk = 0
      item.readTries = 2
      item.readOk = 0
      item.writeTries = 2
      item.writeOk = 0
      expect(weakDimensionsFor(item).length).assertEqual(2)
    })
  })
}
