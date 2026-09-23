import { describe, it, expect } from '@ohos/hypium'
import { resolveItemIconPath, resolveBinGlyphPath } from '../../../../main/ets/utils/CategorizationIconBank'

/**
 * CategorizationIconBank 单元测试
 *
 * 覆盖: 题库物品名直查 / token 拆词 ('帽子 m') / 手工别名 (萝卜) /
 * 未命中退化 ('' 由组件层接 emoji→文字) / 桶类别字形直查 / 字母桶无字形。
 *
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用 (pre-existing scaffold mismatch, 详见 MEMORY.md)
 */

export default function categorizationIconBankTest() {
  describe('resolveItemIconPath - 物品图标解析', () => {
    it('题库物品名直查: 大象 → elephant.svg', 0, () => {
      expect(resolveItemIconPath('大象')).assertEqual('kids/icons/elephant.svg')
    })

    it('多主题共享物品: 苹果 → apple.svg', 0, () => {
      expect(resolveItemIconPath('苹果')).assertEqual('kids/icons/apple.svg')
    })

    it('首尾空白修剪: 「 大象 」仍命中', 0, () => {
      expect(resolveItemIconPath(' 大象 ')).assertEqual('kids/icons/elephant.svg')
    })

    it('扩库物品直查: 奶牛 → cow.svg', 0, () => {
      expect(resolveItemIconPath('奶牛')).assertEqual('kids/icons/cow.svg')
    })

    it('扩库物品直查: 泰迪熊 → teddy.svg', 0, () => {
      expect(resolveItemIconPath('泰迪熊')).assertEqual('kids/icons/teddy.svg')
    })

    it('扩库尾缀字母 token: 「大象 d」命中 elephant', 0, () => {
      expect(resolveItemIconPath('大象 d')).assertEqual('kids/icons/elephant.svg')
    })

    it('全角空格归一: 「帽子　m」命中 hat', 0, () => {
      expect(resolveItemIconPath('帽子　m')).assertEqual('kids/icons/hat.svg')
    })

    it('token 拆词: 「帽子 m」命中 hat', 0, () => {
      expect(resolveItemIconPath('帽子 m')).assertEqual('kids/icons/hat.svg')
    })

    it('token 拆词: 「apple 苹果」命中 apple', 0, () => {
      expect(resolveItemIconPath('apple 苹果')).assertEqual('kids/icons/apple.svg')
    })

    it('token 拆词子词: 「apple 苹果」的中文子词单独查询也命中', 0, () => {
      expect(resolveItemIconPath('苹果')).assertEqual('kids/icons/apple.svg')
    })

    it('手工别名: 萝卜 → carrot (LLM 出题常用变体)', 0, () => {
      expect(resolveItemIconPath('萝卜')).assertEqual('kids/icons/carrot.svg')
    })

    it('手工别名带空白: 「 萝卜 」命中', 0, () => {
      expect(resolveItemIconPath(' 萝卜 ')).assertEqual('kids/icons/carrot.svg')
    })

    it('未命中题库: 返回空串 (组件层退化 emoji→文字)', 0, () => {
      expect(resolveItemIconPath('外星飞船')).assertEqual('')
    })

    it('空字符串输入: 返回空串', 0, () => {
      expect(resolveItemIconPath('')).assertEqual('')
    })

    it('纯空白输入: 返回空串', 0, () => {
      expect(resolveItemIconPath('   ')).assertEqual('')
    })
  })

  describe('resolveBinGlyphPath - 桶类别字形解析', () => {
    it('桶名直查: 陆地 → cat-land.svg', 0, () => {
      expect(resolveBinGlyphPath('陆地')).assertEqual('kids/icons/cat-land.svg')
    })

    it('跨主题同义桶: 水里 / 会游 / 水上 → cat-water.svg', 0, () => {
      expect(resolveBinGlyphPath('水里')).assertEqual('kids/icons/cat-water.svg')
      expect(resolveBinGlyphPath('会游')).assertEqual('kids/icons/cat-water.svg')
      expect(resolveBinGlyphPath('水上')).assertEqual('kids/icons/cat-water.svg')
    })

    it('同形桶跨主题: 天空 / 天上的 → cat-sky.svg', 0, () => {
      expect(resolveBinGlyphPath('天空')).assertEqual('kids/icons/cat-sky.svg')
      expect(resolveBinGlyphPath('天上的')).assertEqual('kids/icons/cat-sky.svg')
    })

    it('字母桶无字形 (letter-* 图标被排除): 返回空串', 0, () => {
      expect(resolveBinGlyphPath('m')).assertEqual('')
      expect(resolveBinGlyphPath('p')).assertEqual('')
      expect(resolveBinGlyphPath('b')).assertEqual('')
      expect(resolveBinGlyphPath('A')).assertEqual('')
    })

    it('扩库桶直查: 快 → fast.svg', 0, () => {
      expect(resolveBinGlyphPath('快')).assertEqual('kids/icons/fast.svg')
    })

    it('扩库桶直查: 家具 → cat-furniture.svg', 0, () => {
      expect(resolveBinGlyphPath('家具')).assertEqual('kids/icons/cat-furniture.svg')
    })

    it('题库外桶名: 返回空串 (组件层退化 emoji→字母块)', 0, () => {
      expect(resolveBinGlyphPath('太空')).assertEqual('')
    })

    it('空字符串输入: 返回空串', 0, () => {
      expect(resolveBinGlyphPath('')).assertEqual('')
    })

    it('路径格式: 一律以 kids/icons/ 开头 .svg 结尾', 0, () => {
      const p = resolveBinGlyphPath('文具')
      expect(p.startsWith('kids/icons/')).assertTrue()
      expect(p.endsWith('.svg')).assertTrue()
    })
  })
}
