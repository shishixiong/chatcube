// entry/src/main/ets/utils/LocalVocabCatalog.ets
/**
 * LocalVocabCatalog - english_quiz 内置本地词库（词条 + 本地 SVG 插图路径）
 *
 * 词条与图片随包内置：rawfile/kids/vocab/<word>.svg。
 * picture_word / legacy word 题的 correct_answer 命中本词库时，
 * ToolExecutionService 直接注入 image_rawfile，卡片从 rawfile 读取图片，
 * 不再走「英语题缓存 → 备课图 → 现生图」的在线图片管线。
 * 图片素材来自 OpenMoji，许可 CC BY-SA 4.0（见 rawfile/kids/vocab/NOTICE.md）。
 */

export interface LocalVocabEntry {
  word: string
  zh: string
  category: string
  image: string
}

export const LOCAL_VOCAB_ENTRIES: LocalVocabEntry[] = [
  { word: 'apple', zh: '苹果', category: '水果', image: 'kids/vocab/apple.svg' },
  { word: 'banana', zh: '香蕉', category: '水果', image: 'kids/vocab/banana.svg' },
  { word: 'cherry', zh: '樱桃', category: '水果', image: 'kids/vocab/cherry.svg' },
  { word: 'grape', zh: '葡萄', category: '水果', image: 'kids/vocab/grape.svg' },
  { word: 'lemon', zh: '柠檬', category: '水果', image: 'kids/vocab/lemon.svg' },
  { word: 'orange', zh: '橙子', category: '水果', image: 'kids/vocab/orange.svg' },
  { word: 'peach', zh: '桃子', category: '水果', image: 'kids/vocab/peach.svg' },
  { word: 'pear', zh: '梨', category: '水果', image: 'kids/vocab/pear.svg' },
  { word: 'strawberry', zh: '草莓', category: '水果', image: 'kids/vocab/strawberry.svg' },
  { word: 'watermelon', zh: '西瓜', category: '水果', image: 'kids/vocab/watermelon.svg' },
  { word: 'bird', zh: '鸟', category: '动物', image: 'kids/vocab/bird.svg' },
  { word: 'cat', zh: '猫', category: '动物', image: 'kids/vocab/cat.svg' },
  { word: 'dog', zh: '狗', category: '动物', image: 'kids/vocab/dog.svg' },
  { word: 'elephant', zh: '大象', category: '动物', image: 'kids/vocab/elephant.svg' },
  { word: 'fish', zh: '鱼', category: '动物', image: 'kids/vocab/fish.svg' },
  { word: 'lion', zh: '狮子', category: '动物', image: 'kids/vocab/lion.svg' },
  { word: 'monkey', zh: '猴子', category: '动物', image: 'kids/vocab/monkey.svg' },
  { word: 'panda', zh: '熊猫', category: '动物', image: 'kids/vocab/panda.svg' },
  { word: 'rabbit', zh: '兔子', category: '动物', image: 'kids/vocab/rabbit.svg' },
  { word: 'tiger', zh: '老虎', category: '动物', image: 'kids/vocab/tiger.svg' },
  { word: 'bread', zh: '面包', category: '食物', image: 'kids/vocab/bread.svg' },
  { word: 'cake', zh: '蛋糕', category: '食物', image: 'kids/vocab/cake.svg' },
  { word: 'cheese', zh: '奶酪', category: '食物', image: 'kids/vocab/cheese.svg' },
  { word: 'cookie', zh: '饼干', category: '食物', image: 'kids/vocab/cookie.svg' },
  { word: 'egg', zh: '鸡蛋', category: '食物', image: 'kids/vocab/egg.svg' },
  { word: 'hamburger', zh: '汉堡', category: '食物', image: 'kids/vocab/hamburger.svg' },
  { word: 'milk', zh: '牛奶', category: '食物', image: 'kids/vocab/milk.svg' },
  { word: 'noodle', zh: '面条', category: '食物', image: 'kids/vocab/noodle.svg' },
  { word: 'pizza', zh: '披萨', category: '食物', image: 'kids/vocab/pizza.svg' },
  { word: 'rice', zh: '米饭', category: '食物', image: 'kids/vocab/rice.svg' },
  { word: 'backpack', zh: '背包', category: '学习用品', image: 'kids/vocab/backpack.svg' },
  { word: 'book', zh: '书', category: '学习用品', image: 'kids/vocab/book.svg' },
  { word: 'crayon', zh: '蜡笔', category: '学习用品', image: 'kids/vocab/crayon.svg' },
  { word: 'globe', zh: '地球仪', category: '学习用品', image: 'kids/vocab/globe.svg' },
  { word: 'notebook', zh: '笔记本', category: '学习用品', image: 'kids/vocab/notebook.svg' },
  { word: 'paintbrush', zh: '画笔', category: '学习用品', image: 'kids/vocab/paintbrush.svg' },
  { word: 'paperclip', zh: '回形针', category: '学习用品', image: 'kids/vocab/paperclip.svg' },
  { word: 'pencil', zh: '铅笔', category: '学习用品', image: 'kids/vocab/pencil.svg' },
  { word: 'ruler', zh: '尺子', category: '学习用品', image: 'kids/vocab/ruler.svg' },
  { word: 'scissors', zh: '剪刀', category: '学习用品', image: 'kids/vocab/scissors.svg' },
  { word: 'black', zh: '黑色', category: '颜色', image: 'kids/vocab/black.svg' },
  { word: 'blue', zh: '蓝色', category: '颜色', image: 'kids/vocab/blue.svg' },
  { word: 'brown', zh: '棕色', category: '颜色', image: 'kids/vocab/brown.svg' },
  { word: 'gray', zh: '灰色', category: '颜色', image: 'kids/vocab/gray.svg' },
  { word: 'green', zh: '绿色', category: '颜色', image: 'kids/vocab/green.svg' },
  { word: 'pink', zh: '粉色', category: '颜色', image: 'kids/vocab/pink.svg' },
  { word: 'purple', zh: '紫色', category: '颜色', image: 'kids/vocab/purple.svg' },
  { word: 'red', zh: '红色', category: '颜色', image: 'kids/vocab/red.svg' },
  { word: 'white', zh: '白色', category: '颜色', image: 'kids/vocab/white.svg' },
  { word: 'yellow', zh: '黄色', category: '颜色', image: 'kids/vocab/yellow.svg' },
  { word: 'brain', zh: '大脑', category: '身体', image: 'kids/vocab/brain.svg' },
  { word: 'ear', zh: '耳朵', category: '身体', image: 'kids/vocab/ear.svg' },
  { word: 'eye', zh: '眼睛', category: '身体', image: 'kids/vocab/eye.svg' },
  { word: 'face', zh: '脸', category: '身体', image: 'kids/vocab/face.svg' },
  { word: 'foot', zh: '脚', category: '身体', image: 'kids/vocab/foot.svg' },
  { word: 'hand', zh: '手', category: '身体', image: 'kids/vocab/hand.svg' },
  { word: 'mouth', zh: '嘴巴', category: '身体', image: 'kids/vocab/mouth.svg' },
  { word: 'nose', zh: '鼻子', category: '身体', image: 'kids/vocab/nose.svg' },
  { word: 'tongue', zh: '舌头', category: '身体', image: 'kids/vocab/tongue.svg' },
  { word: 'tooth', zh: '牙齿', category: '身体', image: 'kids/vocab/tooth.svg' },
  { word: 'baby', zh: '宝宝', category: '家庭', image: 'kids/vocab/baby.svg' },
  { word: 'brother', zh: '哥哥', category: '家庭', image: 'kids/vocab/brother.svg' },
  { word: 'child', zh: '孩子', category: '家庭', image: 'kids/vocab/child.svg' },
  { word: 'family', zh: '家庭', category: '家庭', image: 'kids/vocab/family.svg' },
  { word: 'father', zh: '爸爸', category: '家庭', image: 'kids/vocab/father.svg' },
  { word: 'grandfather', zh: '爷爷', category: '家庭', image: 'kids/vocab/grandfather.svg' },
  { word: 'grandmother', zh: '奶奶', category: '家庭', image: 'kids/vocab/grandmother.svg' },
  { word: 'mother', zh: '妈妈', category: '家庭', image: 'kids/vocab/mother.svg' },
  { word: 'sister', zh: '姐姐', category: '家庭', image: 'kids/vocab/sister.svg' },
  { word: 'teacher', zh: '老师', category: '家庭', image: 'kids/vocab/teacher.svg' },
  { word: 'airplane', zh: '飞机', category: '交通', image: 'kids/vocab/airplane.svg' },
  { word: 'bicycle', zh: '自行车', category: '交通', image: 'kids/vocab/bicycle.svg' },
  { word: 'boat', zh: '船', category: '交通', image: 'kids/vocab/boat.svg' },
  { word: 'bus', zh: '公交车', category: '交通', image: 'kids/vocab/bus.svg' },
  { word: 'car', zh: '汽车', category: '交通', image: 'kids/vocab/car.svg' },
  { word: 'motorcycle', zh: '摩托车', category: '交通', image: 'kids/vocab/motorcycle.svg' },
  { word: 'rocket', zh: '火箭', category: '交通', image: 'kids/vocab/rocket.svg' },
  { word: 'taxi', zh: '出租车', category: '交通', image: 'kids/vocab/taxi.svg' },
  { word: 'train', zh: '火车', category: '交通', image: 'kids/vocab/train.svg' },
  { word: 'truck', zh: '卡车', category: '交通', image: 'kids/vocab/truck.svg' },
  { word: 'cloud', zh: '云', category: '天气', image: 'kids/vocab/cloud.svg' },
  { word: 'lightning', zh: '闪电', category: '天气', image: 'kids/vocab/lightning.svg' },
  { word: 'moon', zh: '月亮', category: '天气', image: 'kids/vocab/moon.svg' },
  { word: 'rain', zh: '雨', category: '天气', image: 'kids/vocab/rain.svg' },
  { word: 'rainbow', zh: '彩虹', category: '天气', image: 'kids/vocab/rainbow.svg' },
  { word: 'snow', zh: '雪', category: '天气', image: 'kids/vocab/snow.svg' },
  { word: 'star', zh: '星星', category: '天气', image: 'kids/vocab/star.svg' },
  { word: 'sun', zh: '太阳', category: '天气', image: 'kids/vocab/sun.svg' },
  { word: 'umbrella', zh: '雨伞', category: '天气', image: 'kids/vocab/umbrella.svg' },
  { word: 'wind', zh: '风', category: '天气', image: 'kids/vocab/wind.svg' },
  { word: 'bathtub', zh: '浴缸', category: '家居', image: 'kids/vocab/bathtub.svg' },
  { word: 'bed', zh: '床', category: '家居', image: 'kids/vocab/bed.svg' },
  { word: 'chair', zh: '椅子', category: '家居', image: 'kids/vocab/chair.svg' },
  { word: 'clock', zh: '时钟', category: '家居', image: 'kids/vocab/clock.svg' },
  { word: 'door', zh: '门', category: '家居', image: 'kids/vocab/door.svg' },
  { word: 'house', zh: '房子', category: '家居', image: 'kids/vocab/house.svg' },
  { word: 'key', zh: '钥匙', category: '家居', image: 'kids/vocab/key.svg' },
  { word: 'lamp', zh: '台灯', category: '家居', image: 'kids/vocab/lamp.svg' },
  { word: 'sofa', zh: '沙发', category: '家居', image: 'kids/vocab/sofa.svg' },
  { word: 'toilet', zh: '马桶', category: '家居', image: 'kids/vocab/toilet.svg' }
]

let entryMap: Map<string, LocalVocabEntry> | null = null

function buildEntryMap(): Map<string, LocalVocabEntry> {
  const map: Map<string, LocalVocabEntry> = new Map()
  for (let i = 0; i < LOCAL_VOCAB_ENTRIES.length; i++) {
    const entry = LOCAL_VOCAB_ENTRIES[i]
    map.set(entry.word.toLowerCase(), entry)
  }
  return map
}

/** 按英文单词查本地词条（忽略大小写与首尾空白）；未命中返回 null。 */
export function findLocalVocabEntry(word: string): LocalVocabEntry | null {
  const needle = word.trim().toLowerCase()
  if (needle === '') {
    return null
  }
  if (entryMap === null) {
    entryMap = buildEntryMap()
  }
  const hit = entryMap.get(needle)
  return hit === undefined ? null : hit
}

/** 按中文释义查词条：精确匹配优先；也容忍「只写一个字」的旧习惯（唯一前缀命中才算）。 */
export function findLocalVocabEntryByChinese(answer: string): LocalVocabEntry | null {
  const needle = answer.trim()
  if (needle === '') {
    return null
  }
  let prefixHit: LocalVocabEntry | null = null
  let prefixCount = 0
  for (let i = 0; i < LOCAL_VOCAB_ENTRIES.length; i++) {
    const entry = LOCAL_VOCAB_ENTRIES[i]
    if (entry.zh === needle) {
      return entry
    }
    if (entry.zh.length > needle.length && entry.zh.startsWith(needle)) {
      prefixHit = entry
      prefixCount += 1
    }
  }
  return prefixCount === 1 ? prefixHit : null
}

/** picture_vocab: mode=en 按英文单词查, mode=zh 按中文释义查。 */
export function findLocalVocabEntryForMode(mode: string, answer: string): LocalVocabEntry | null {
  if (mode === 'zh') {
    return findLocalVocabEntryByChinese(answer)
  }
  return findLocalVocabEntry(answer)
}

/** 中英对照词表（按主题分组），注入 picture_vocab 工具描述，保证 en/zh 两种模式都能命中原图。 */
export function getLocalVocabBilingualPromptHint(): string {
  const categories: string[] = ['水果', '动物', '食物', '学习用品', '颜色', '身体', '家庭', '交通', '天气', '家居']
  const parts: string[] = []
  for (let c = 0; c < categories.length; c++) {
    const pairs: string[] = []
    for (let i = 0; i < LOCAL_VOCAB_ENTRIES.length; i++) {
      const entry = LOCAL_VOCAB_ENTRIES[i]
      if (entry.category === categories[c]) {
        pairs.push(entry.word + ' ' + entry.zh)
      }
    }
    if (pairs.length > 0) {
      parts.push(categories[c] + ': ' + pairs.join(', '))
    }
  }
  return parts.join('；')
}

/** 按主题分组的紧凑词表，注入 english_quiz 工具描述，提示模型优先从本地词库选词。 */
export function getLocalVocabPromptHint(): string {
  const categories: string[] = ['水果', '动物', '食物', '学习用品', '颜色', '身体', '家庭', '交通', '天气', '家居']
  const parts: string[] = []
  for (let c = 0; c < categories.length; c++) {
    const words: string[] = []
    for (let i = 0; i < LOCAL_VOCAB_ENTRIES.length; i++) {
      if (LOCAL_VOCAB_ENTRIES[i].category === categories[c]) {
        words.push(LOCAL_VOCAB_ENTRIES[i].word)
      }
    }
    if (words.length > 0) {
      parts.push(categories[c] + ': ' + words.join(', '))
    }
  }
  return parts.join('；')
}
