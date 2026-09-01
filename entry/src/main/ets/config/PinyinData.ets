/**
 * 拼音字典 (供 pinyin_quiz 使用)
 *
 * 一年级常用单音节汉字 → 带调拼音。
 * 字集优先与 StrokeOrderData 重叠——这些字已有写字练习支持, 可以「先认读后书写」跨功能协同。
 * 全部为单音节、常用读音 (多音字取一年级最常用读音)。
 */

export interface PinyinEntry {
  char: string
  pinyin: string
}

const PINYIN_ENTRIES: [string, string][] = [
  ['一', 'yī'],
  ['二', 'èr'],
  ['三', 'sān'],
  ['四', 'sì'],
  ['五', 'wǔ'],
  ['六', 'liù'],
  ['七', 'qī'],
  ['八', 'bā'],
  ['九', 'jiǔ'],
  ['十', 'shí'],
  ['人', 'rén'],
  ['大', 'dà'],
  ['小', 'xiǎo'],
  ['山', 'shān'],
  ['水', 'shuǐ'],
  ['火', 'huǒ'],
  ['土', 'tǔ'],
  ['日', 'rì'],
  ['月', 'yuè'],
  ['口', 'kǒu'],
  ['手', 'shǒu'],
  ['上', 'shàng'],
  ['下', 'xià'],
  ['中', 'zhōng'],
  ['田', 'tián'],
  ['目', 'mù'],
  ['天', 'tiān'],
  ['木', 'mù'],
  ['子', 'zǐ'],
  ['女', 'nǚ'],
  ['白', 'bái'],
  ['石', 'shí'],
  ['心', 'xīn'],
  ['王', 'wáng'],
  ['生', 'shēng'],
  ['花', 'huā'],
  ['鸟', 'niǎo'],
  ['鱼', 'yú'],
  ['马', 'mǎ'],
  ['云', 'yún'],
  ['风', 'fēng'],
  ['牛', 'niú'],
  ['羊', 'yáng'],
  ['虫', 'chóng'],
  ['竹', 'zhú'],
  ['雨', 'yǔ'],
  ['电', 'diàn'],
  ['耳', 'ěr'],
  ['衣', 'yī'],
  ['几', 'jǐ'],
  ['力', 'lì'],
  ['工', 'gōng'],
  ['米', 'mǐ'],
  ['头', 'tóu'],
  ['不', 'bù'],
  ['飞', 'fēi'],
  ['万', 'wàn'],
  ['千', 'qiān'],
  ['百', 'bǎi'],
  ['干', 'gān'],
  ['士', 'shì'],
  ['元', 'yuán'],
  ['开', 'kāi'],
  ['久', 'jiǔ'],
  ['出', 'chū'],
  ['门', 'mén'],
  ['半', 'bàn'],
  ['习', 'xí'],
  ['东', 'dōng'],
  ['两', 'liǎng'],
  ['明', 'míng'],
  ['林', 'lín']
]

const PINYIN_MAP: Map<string, string> = new Map<string, string>(PINYIN_ENTRIES)

/**
 * 查询单字的拼音。不在字典内返回 null。
 */
export function getPinyin(char: string): string | null {
  const pinyin = PINYIN_MAP.get(char)
  if (pinyin === undefined) {
    return null
  }
  return pinyin
}

/**
 * 判断单字是否在拼音字典内。
 */
export function hasPinyin(char: string): boolean {
  return PINYIN_MAP.has(char)
}

/**
 * 字典内所有汉字 (供 AI 参考 / 测试)。
 */
export function getPinyinChars(): string[] {
  const chars: string[] = []
  for (let i = 0; i < PINYIN_ENTRIES.length; i++) {
    chars.push(PINYIN_ENTRIES[i][0])
  }
  return chars
}

/**
 * 拼接字典内所有汉字为「一 二 三 ...」空格分隔字符串。
 * 用于嵌入 tool schema description, 让 AI 只从支持的字表里出题 (防字典外字符重试死循环)。
 */
export function getPinyinCharsJoined(): string {
  const parts: string[] = []
  for (let i = 0; i < PINYIN_ENTRIES.length; i++) {
    parts.push(PINYIN_ENTRIES[i][0])
  }
  return parts.join(' ')
}
