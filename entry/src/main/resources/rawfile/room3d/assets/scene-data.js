/* 25 个可点击物品的唯一数据源：场景对象、单词卡与词汇表共用。 */
(function () {
  'use strict';

  const objects = [
    {
      id: 'sofa',
      word: 'sofa',
      phonetic: '/ˈsoʊfə/',
      zh: '沙发',
      kidDefinition: '客厅里软软的长椅子，可以坐和躺。',
      example: 'I sit on the sofa.',
      category: 'living',
      labelBias: [-58, -18]
    },
    {
      id: 'coffee_table',
      word: 'coffee table',
      phonetic: '/ˈkɔːfi ˌteɪbəl/',
      zh: '茶几',
      kidDefinition: '放在沙发前的小桌子，能放水杯。',
      example: 'The cup is on the coffee table.',
      category: 'living',
      labelBias: [56, -14]
    },
    {
      id: 'tv',
      word: 'TV',
      phonetic: '/ˌtiː ˈviː/',
      zh: '电视',
      kidDefinition: '会说话的屏幕，可以看动画片。',
      example: 'We watch TV together.',
      category: 'living',
      labelBias: [-70, -22]
    },
    {
      id: 'tv_stand',
      word: 'TV stand',
      phonetic: '/ˌtiː ˈviː stænd/',
      zh: '电视柜',
      kidDefinition: '电视下面的柜子，可以收纳东西。',
      example: 'The TV stand is made of wood.',
      category: 'living',
      labelBias: [66, 10]
    },
    {
      id: 'remote_control',
      word: 'remote control',
      phonetic: '/rɪˈmoʊt kənˈtroʊl/',
      zh: '遥控器',
      kidDefinition: '按一按就能换台的小工具。',
      example: 'Please pass me the remote control.',
      category: 'living',
      labelBias: [-92, -8]
    },
    {
      id: 'rug',
      word: 'rug',
      phonetic: '/rʌɡ/',
      zh: '地毯',
      kidDefinition: '铺在地上的软垫，脚踩上去很暖。',
      example: 'The rug is soft under my feet.',
      category: 'living',
      labelBias: [0, 24]
    },
    {
      id: 'cushion',
      word: 'cushion',
      phonetic: '/ˈkʊʃən/',
      zh: '抱枕',
      kidDefinition: '软软的小靠垫，抱着很舒服。',
      example: 'This cushion is very soft.',
      category: 'living',
      labelBias: [90, -18]
    },
    {
      id: 'floor_lamp',
      word: 'floor lamp',
      phonetic: '/ˈflɔːr læmp/',
      zh: '落地灯',
      kidDefinition: '站在地上的灯，照亮客厅角落。',
      example: 'The floor lamp gives warm light.',
      category: 'living',
      labelBias: [-54, -24]
    },
    {
      id: 'bookshelf',
      word: 'bookshelf',
      phonetic: '/ˈbʊkʃelf/',
      zh: '书架',
      kidDefinition: '放很多书的架子，像书的房子。',
      example: 'My books are on the bookshelf.',
      category: 'living',
      labelBias: [-12, -18]
    },
    {
      id: 'book',
      word: 'book',
      phonetic: '/bʊk/',
      zh: '书',
      kidDefinition: '一页一页的故事，等你来读。',
      example: 'I read a book every night.',
      category: 'living',
      labelBias: [54, -26]
    },
    {
      id: 'plant',
      word: 'plant',
      phonetic: '/plænt/',
      zh: '绿植',
      kidDefinition: '会喝水的绿色小伙伴。',
      example: 'The plant needs some water.',
      category: 'living',
      labelBias: [-52, -22]
    },
    {
      id: 'curtain',
      word: 'curtain',
      phonetic: '/ˈkɜːrtən/',
      zh: '窗帘',
      kidDefinition: '挂在窗边的布，拉开能看见阳光。',
      example: 'Please open the curtain.',
      category: 'living',
      labelBias: [70, -18]
    },
    {
      id: 'window',
      word: 'window',
      phonetic: '/ˈwɪndoʊ/',
      zh: '窗户',
      kidDefinition: '墙上透光的洞，可以看外面。',
      example: 'Look out of the window.',
      category: 'living',
      labelBias: [-12, -8]
    },
    {
      id: 'picture',
      word: 'picture',
      phonetic: '/ˈpɪktʃər/',
      zh: '挂画',
      kidDefinition: '挂在墙上的画，让房间更好看。',
      example: 'There is a picture on the wall.',
      category: 'living',
      labelBias: [72, -18]
    },
    {
      id: 'clock',
      word: 'clock',
      phonetic: '/klɑːk/',
      zh: '时钟',
      kidDefinition: '滴答滴答，告诉我们时间。',
      example: "The clock says eight o'clock.",
      category: 'living',
      labelBias: [0, -14]
    },
    {
      id: 'air_conditioner',
      word: 'air conditioner',
      phonetic: '/ˈer kənˌdɪʃənər/',
      zh: '空调',
      kidDefinition: '夏天吹凉风的白色小帮手。',
      example: 'The air conditioner keeps us cool.',
      category: 'dining',
      labelBias: [0, -12]
    },
    {
      id: 'trash_can',
      word: 'trash can',
      phonetic: '/ˈtræʃ kæn/',
      zh: '垃圾桶',
      kidDefinition: '装废纸和果皮的干净小桶。',
      example: 'Put the paper in the trash can.',
      category: 'dining',
      labelBias: [48, -22]
    },
    {
      id: 'dining_table',
      word: 'dining table',
      phonetic: '/ˈdaɪnɪŋ ˌteɪbəl/',
      zh: '餐桌',
      kidDefinition: '一家人吃饭的大桌子。',
      example: 'We eat dinner at the dining table.',
      category: 'dining',
      labelBias: [-40, -22]
    },
    {
      id: 'dining_chair',
      word: 'dining chair',
      phonetic: '/ˈdaɪnɪŋ tʃer/',
      zh: '餐椅',
      kidDefinition: '坐在餐桌旁吃饭的小椅子。',
      example: 'Pull up a dining chair, please.',
      category: 'dining',
      labelBias: [72, 16]
    },
    {
      id: 'plate',
      word: 'plate',
      phonetic: '/pleɪt/',
      zh: '盘子',
      kidDefinition: '圆圆的盘子，装好吃的食物。',
      example: 'My plate is full of fruit.',
      category: 'dining',
      labelBias: [-86, -10]
    },
    {
      id: 'bowl',
      word: 'bowl',
      phonetic: '/boʊl/',
      zh: '碗',
      kidDefinition: '深深的碗，可以装汤和米饭。',
      example: 'The bowl is full of soup.',
      category: 'dining',
      labelBias: [70, -18]
    },
    {
      id: 'cup',
      word: 'cup',
      phonetic: '/kʌp/',
      zh: '杯子',
      kidDefinition: '用来装水或喝水的杯子。',
      example: 'I drink milk from a cup.',
      category: 'dining',
      labelBias: [104, -38]
    },
    {
      id: 'spoon',
      word: 'spoon',
      phonetic: '/spuːn/',
      zh: '勺子',
      kidDefinition: '喝汤用的小勺子，舀一口。',
      example: 'Eat the soup with a spoon.',
      category: 'dining',
      labelBias: [-52, 30]
    },
    {
      id: 'fork',
      word: 'fork',
      phonetic: '/fɔːrk/',
      zh: '叉子',
      kidDefinition: '吃饭用的小叉子，叉住食物。',
      example: 'Use a fork for the noodles.',
      category: 'dining',
      labelBias: [42, 30]
    },
    {
      id: 'kettle',
      word: 'kettle',
      phonetic: '/ˈketəl/',
      zh: '水壶',
      kidDefinition: '烧水用的壶，会冒热气。',
      example: 'The kettle is boiling water.',
      category: 'dining',
      labelBias: [-26, -78]
    },
    {
      id: 'fridge',
      word: 'fridge',
      phonetic: '/frɪdʒ/',
      zh: '冰箱',
      kidDefinition: '厨房里的大柜子，里面很冷。',
      example: 'The milk is in the fridge.',
      category: 'kitchen',
      labelBias: [-38, -46]
    },
    {
      id: 'stove',
      word: 'stove',
      phonetic: '/stoʊv/',
      zh: '灶台',
      kidDefinition: '上面有火，锅放在上面煮。',
      example: 'Put the pot on the stove.',
      category: 'kitchen',
      labelBias: [-6, -62]
    },
    {
      id: 'oven',
      word: 'oven',
      phonetic: '/ˈʌvən/',
      zh: '烤箱',
      kidDefinition: '关上门烤蛋糕和面包。',
      example: 'The cake is in the oven.',
      category: 'kitchen',
      labelBias: [-44, 30]
    },
    {
      id: 'sink',
      word: 'sink',
      phonetic: '/sɪŋk/',
      zh: '水槽',
      kidDefinition: '洗菜洗碗的水池，有龙头。',
      example: 'Wash the apple in the sink.',
      category: 'kitchen',
      labelBias: [-46, 22]
    },
    {
      id: 'pot',
      word: 'pot',
      phonetic: '/pɑːt/',
      zh: '锅',
      kidDefinition: '深深的锅，用来煮汤。',
      example: 'The soup is in the pot.',
      category: 'kitchen',
      labelBias: [-30, -74]
    },
    {
      id: 'pan',
      word: 'pan',
      phonetic: '/pæn/',
      zh: '平底锅',
      kidDefinition: '浅浅的锅，可以煎鸡蛋。',
      example: 'Fry an egg in the pan.',
      category: 'kitchen',
      labelBias: [26, -68]
    },
    {
      id: 'toaster',
      word: 'toaster',
      phonetic: '/ˈtoʊstər/',
      zh: '烤面包机',
      kidDefinition: '放进面包，跳起来就好了。',
      example: 'The toast pops out of the toaster.',
      category: 'kitchen',
      labelBias: [40, 16]
    },
    {
      id: 'microwave',
      word: 'microwave',
      phonetic: '/ˈmaɪkrəweɪv/',
      zh: '微波炉',
      kidDefinition: '一按就热，热牛奶很快。',
      example: 'Heat the milk in the microwave.',
      category: 'kitchen',
      labelBias: [46, -30]
    },
    {
      id: 'dishwasher',
      word: 'dishwasher',
      phonetic: '/ˈdɪʃwɔːʃər/',
      zh: '洗碗机',
      kidDefinition: '把脏碗放进去，它会洗。',
      example: 'Put the plates in the dishwasher.',
      category: 'kitchen',
      labelBias: [40, 34]
    },
    {
      id: 'cabinet',
      word: 'cabinet',
      phonetic: '/ˈkæbɪnət/',
      zh: '橱柜',
      kidDefinition: '墙上的柜子，收碗和杯子。',
      example: 'The bowls are in the cabinet.',
      category: 'kitchen',
      labelBias: [-4, -88]
    },
    {
      id: 'knife',
      word: 'knife',
      phonetic: '/naɪf/',
      zh: '刀',
      kidDefinition: '切菜用的刀，要小心。',
      example: 'Cut the bread with a knife.',
      category: 'kitchen',
      labelBias: [38, 12]
    },
    {
      id: 'stool',
      word: 'stool',
      phonetic: '/stuːl/',
      zh: '吧台凳',
      kidDefinition: '高高的小凳子，坐在岛台边。',
      example: 'I sit on the stool.',
      category: 'kitchen',
      labelBias: [6, 50]
    },
  ].map((item) => ({ ...item, objectName: 'OBJ_' + item.id }));

  window.WordRoomData = {
    title: '客餐厅 · 厨房英语探索',
    roomSize: { width: 11.8, depth: 6, label: '11.8m × 6m' },
    categories: {
      living: { zh: '客厅', en: 'LIVING ROOM', count: objects.filter((item) => item.category === 'living').length },
      dining: { zh: '餐厅', en: 'DINING ROOM', count: objects.filter((item) => item.category === 'dining').length },
      kitchen: { zh: '厨房', en: 'KITCHEN', count: objects.filter((item) => item.category === 'kitchen').length }
    },
    objects
  };
})();
