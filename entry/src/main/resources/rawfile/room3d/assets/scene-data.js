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

    // —— 儿童房：4.4m × 3.6m，12 件可点物品 ——
    {
      id: 'bed',
      word: 'bed',
      phonetic: '/bed/',
      zh: '床',
      kidDefinition: '睡觉的大床，晚上整个人躺进去。',
      example: 'My bed is soft.',
      category: 'child',
      labelBias: [24, -20]
    },
    {
      id: 'desk',
      word: 'desk',
      phonetic: '/desk/',
      zh: '书桌',
      kidDefinition: '写作业、画画用的桌子。',
      example: 'I do homework at my desk.',
      category: 'child',
      labelBias: [30, -22]
    },
    {
      id: 'chair',
      word: 'chair',
      phonetic: '/tʃer/',
      zh: '椅子',
      kidDefinition: '有四条腿，坐上去写字。',
      example: 'Sit on your chair.',
      category: 'child',
      labelBias: [34, 8]
    },
    {
      id: 'wardrobe',
      word: 'wardrobe',
      phonetic: '/ˈwɔːrdroʊb/',
      zh: '衣柜',
      kidDefinition: '高高的柜子，衣服挂进去不皱。',
      example: 'Open the wardrobe.',
      category: 'child',
      labelBias: [-40, -26]
    },
    {
      id: 'toy_box',
      word: 'toy box',
      phonetic: '/tɔɪ bɑːks/',
      zh: '玩具箱',
      kidDefinition: '玩好的玩具都放进来。',
      example: 'Put toys in the toy box.',
      category: 'child',
      labelBias: [-44, -12]
    },
    {
      id: 'round_rug',
      word: 'round rug',
      phonetic: '/raʊnd rʌɡ/',
      zh: '圆地毯',
      kidDefinition: '地上圆圆的一块，踩着暖暖的。',
      example: 'The rug is round.',
      category: 'child',
      labelBias: [-56, 18]
    },
    {
      id: 'bookcase',
      word: 'bookcase',
      phonetic: '/ˈbʊkkeɪs/',
      zh: '书柜',
      kidDefinition: '一层层格子，书排得整齐。',
      example: 'Books go on the bookcase.',
      category: 'child',
      labelBias: [46, 22]
    },
    {
      id: 'shelf',
      word: 'shelf',
      phonetic: '/ʃelf/',
      zh: '搁板',
      kidDefinition: '一层小架子，放小车和积木。',
      example: 'A car is on the shelf.',
      category: 'child',
      labelBias: [-46, 22]
    },
    {
      id: 'basket',
      word: 'basket',
      phonetic: '/ˈbæskɪt/',
      zh: '篮子',
      kidDefinition: '装脏衣服和小玩具的筐。',
      example: 'Throw it in the basket.',
      category: 'child',
      labelBias: [-30, 26]
    },
    {
      id: 'poster',
      word: 'poster',
      phonetic: '/ˈpoʊstər/',
      zh: '海报',
      kidDefinition: '墙上的一张画，颜色很鲜艳。',
      example: 'Look at my poster.',
      category: 'child',
      labelBias: [30, -34]
    },
    {
      id: 'blanket',
      word: 'blanket',
      phonetic: '/ˈblæŋkɪt/',
      zh: '毯子',
      kidDefinition: '软软的一块，冷了搭在身上。',
      example: 'I need a blanket.',
      category: 'child',
      labelBias: [-20, -30]
    },
    {
      id: 'toy_car',
      word: 'toy car',
      phonetic: '/tɔɪ kɑːr/',
      zh: '玩具车',
      kidDefinition: '四个轮子跑得飞快的小车。',
      example: 'The toy car is fast.',
      category: 'child',
      labelBias: [10, 30]
    },

    // —— 主卧：4.6m × 3.6m，12 件可点物品 ——
    {
      id: 'double_bed',
      word: 'double bed',
      phonetic: '/ˈdʌbəl bed/',
      zh: '双人床',
      kidDefinition: '大大的床，两个人睡也够。',
      example: 'This is a double bed.',
      category: 'master',
      labelBias: [26, -18]
    },
    {
      id: 'nightstand',
      word: 'nightstand',
      phonetic: '/ˈnaɪtstænd/',
      zh: '床头柜',
      kidDefinition: '床边的小柜子，放水杯和书。',
      example: 'My glass is on the nightstand.',
      category: 'master',
      labelBias: [40, -6]
    },
    {
      id: 'lamp',
      word: 'lamp',
      phonetic: '/læmp/',
      zh: '台灯',
      kidDefinition: '按一下亮起来，晚上看书用。',
      example: 'Turn on the lamp.',
      category: 'master',
      labelBias: [46, -34]
    },
    {
      id: 'pillow',
      word: 'pillow',
      phonetic: '/ˈpɪloʊ/',
      zh: '枕头',
      kidDefinition: '软软的，睡觉把头放上去。',
      example: 'This pillow is too soft.',
      category: 'master',
      labelBias: [-12, -32]
    },
    {
      id: 'closet',
      word: 'closet',
      phonetic: '/ˈklɑːzɪt/',
      zh: '衣帽柜',
      kidDefinition: '整面墙的大柜子，被子也能放。',
      example: 'Put your coat in the closet.',
      category: 'master',
      labelBias: [-42, -26]
    },
    {
      id: 'dresser',
      word: 'dresser',
      phonetic: '/ˈdresər/',
      zh: '斗柜',
      kidDefinition: '一层层抽屉，装裤子和小衣服。',
      example: 'Socks are in the dresser.',
      category: 'master',
      labelBias: [54, 12]
    },
    {
      id: 'mirror',
      word: 'mirror',
      phonetic: '/ˈmɪrər/',
      zh: '镜子',
      kidDefinition: '站在它前面，看见自己的脸。',
      example: 'Look in the mirror.',
      category: 'master',
      labelBias: [56, -22]
    },
    {
      id: 'stool_master',
      word: 'stool',
      phonetic: '/stuːl/',
      zh: '凳子',
      kidDefinition: '没有靠背，坐着照镜子最方便。',
      example: 'Sit on the stool.',
      category: 'master',
      labelBias: [30, 26]
    },
    {
      id: 'bench',
      word: 'bench',
      phonetic: '/bentʃ/',
      zh: '长凳',
      kidDefinition: '横在床尾的长凳子，先坐再脱鞋。',
      example: 'Sit on the bench.',
      category: 'master',
      labelBias: [-30, 12]
    },
    {
      id: 'rug_master',
      word: 'rug',
      phonetic: '/rʌɡ/',
      zh: '地毯',
      kidDefinition: '铺在床边，脚踩上去不冰。',
      example: 'A rug is on the floor.',
      category: 'master',
      labelBias: [-34, 28]
    },
    {
      id: 'heater',
      word: 'heater',
      phonetic: '/ˈhiːtər/',
      zh: '暖气片',
      kidDefinition: '冬天热热的，靠近就不冷。',
      example: 'The heater is hot.',
      category: 'master',
      labelBias: [50, 34]
    },
    {
      id: 'photo_frame',
      word: 'photo frame',
      phonetic: '/ˈfoʊtoʊ freɪm/',
      zh: '相框',
      kidDefinition: '把小画片夹在木框里立起来。',
      example: 'Look at the photo frame.',
      category: 'master',
      labelBias: [50, -18]
    },

    // —— 卫生间：2.4m × 2.0m，12 件可点物品 ——
    {
      id: 'towel',
      word: 'towel',
      phonetic: '/ˈtaʊəl/',
      zh: '毛巾',
      kidDefinition: '软软的布，擦干手和脸。',
      example: 'Dry your hands with a towel.',
      category: 'bathroom',
      labelBias: [-34, 26]
    },
    {
      id: 'toothbrush',
      word: 'toothbrush',
      phonetic: '/ˈtuːθbrʌʃ/',
      zh: '牙刷',
      kidDefinition: '插在杯子里，早晚刷一刷。',
      example: 'Brush your teeth with a toothbrush.',
      category: 'bathroom',
      labelBias: [-44, -22]
    },
    {
      id: 'soap',
      word: 'soap',
      phonetic: '/soʊp/',
      zh: '肥皂',
      kidDefinition: '滑溜溜的小方块，揉出泡泡。',
      example: 'Wash your hands with soap.',
      category: 'bathroom',
      labelBias: [-6, -20]
    },
    {
      id: 'shampoo',
      word: 'shampoo',
      phonetic: '/ʃæmˈpuː/',
      zh: '洗发水',
      kidDefinition: '按一按，香香的泡泡洗头发。',
      example: 'Use shampoo when you wash your hair.',
      category: 'bathroom',
      labelBias: [30, -24]
    },
    {
      id: 'toilet_paper',
      word: 'toilet paper',
      phonetic: '/ˈtɔɪlət ˌpeɪpər/',
      zh: '卷纸',
      kidDefinition: '软软的一卷纸，挂在架子上。',
      example: 'We need more toilet paper.',
      category: 'bathroom',
      labelBias: [-38, 18]
    },
    {
      id: 'bath_mat',
      word: 'bath mat',
      phonetic: '/ˈbɑːθ mæt/',
      zh: '浴室地垫',
      kidDefinition: '洗手台前的软垫，踩上去不冰。',
      example: 'Step on the bath mat.',
      category: 'bathroom',
      labelBias: [-48, 30]
    },
    {
      id: 'scale',
      word: 'scale',
      phonetic: '/skeɪl/',
      zh: '体重秤',
      kidDefinition: '站上去，数字就跳出来。',
      example: 'Stand on the scale slowly.',
      category: 'bathroom',
      labelBias: [-30, 34]
    },
    {
      id: 'mirror_bath',
      word: 'mirror',
      phonetic: '/ˈmɪrər/',
      zh: '镜子',
      kidDefinition: '挂在墙上，能看见自己的脸。',
      example: 'Look in the mirror and smile.',
      category: 'bathroom',
      labelBias: [-46, -30]
    },
    {
      id: 'shower',
      word: 'shower',
      phonetic: '/ˈʃaʊər/',
      zh: '花洒',
      kidDefinition: '墙边高高的喷头，一开就下小雨。',
      example: 'I take a shower in the morning.',
      category: 'bathroom',
      labelBias: [40, -34]
    },
    {
      id: 'toilet',
      word: 'toilet',
      phonetic: '/ˈtɔɪlət/',
      zh: '马桶',
      kidDefinition: '白色的坐便，用完要冲水。',
      example: 'Flush the toilet after you use it.',
      category: 'bathroom',
      labelBias: [-40, 8]
    },
    {
      id: 'washbasin',
      word: 'washbasin',
      phonetic: '/ˈwɒʃbeɪsn/',
      zh: '洗手盆',
      kidDefinition: '洗手洗脸的盆，龙头一拧出水。',
      example: 'Wash your hands in the washbasin.',
      category: 'bathroom',
      labelBias: [-40, -26]
    },
    {
      id: 'bathtub',
      word: 'bathtub',
      phonetic: '/ˈbɑːθtʌb/',
      zh: '浴缸',
      kidDefinition: '泡澡的大缸子，边上还有小黄鸭。',
      example: 'I take a bath in the bathtub.',
      category: 'bathroom',
      labelBias: [26, 30]
    },

    // —— 阳台：3.6m × 1.4m，12 件可点物品 ——
    {
      id: 'washing_machine',
      word: 'washing machine',
      phonetic: '/ˈwɒʃɪŋ məˌʃiːn/',
      zh: '洗衣机',
      kidDefinition: '中间有圆门，衣服转一圈就干净。',
      example: 'Put your clothes in the washing machine.',
      category: 'balcony',
      labelBias: [-46, -28]
    },
    {
      id: 'bag',
      word: 'bag',
      phonetic: '/bæɡ/',
      zh: '布袋',
      kidDefinition: '鼓鼓的袋子，两只提手立着。',
      example: 'Put the clothes in the bag.',
      category: 'balcony',
      labelBias: [-30, 30]
    },
    {
      id: 'mop_bucket',
      word: 'bucket',
      phonetic: '/ˈbʌkɪt/',
      zh: '水桶',
      kidDefinition: '深色水桶，桶口有拧干板。',
      example: 'Fill the bucket with water.',
      category: 'balcony',
      labelBias: [-14, -24]
    },
    {
      id: 'mop',
      word: 'mop',
      phonetic: '/mɒp/',
      zh: '拖把',
      kidDefinition: '长杆子下面一团软毛，推着擦地。',
      example: 'Mop the floor with water.',
      category: 'balcony',
      labelBias: [-40, -30]
    },
    {
      id: 'watering_can',
      word: 'watering can',
      phonetic: '/ˈwɔːtərɪŋ kæn/',
      zh: '浇水壶',
      kidDefinition: '大肚子壶，长嘴洒出一条水线。',
      example: 'Water the plants with the watering can.',
      category: 'balcony',
      labelBias: [18, -22]
    },
    {
      id: 'deck_chair',
      word: 'chair',
      phonetic: '/tʃer/',
      zh: '折叠椅',
      kidDefinition: '有靠背的小椅子，坐着晒太阳。',
      example: 'Sit on the chair and rest.',
      category: 'balcony',
      labelBias: [-30, -24]
    },
    {
      id: 'side_table',
      word: 'table',
      phonetic: '/ˈteɪbl/',
      zh: '小圆桌',
      kidDefinition: '圆圆的小桌面，刚好放一杯水。',
      example: 'The cup is on the table.',
      category: 'balcony',
      labelBias: [30, -20]
    },
    {
      id: 'slippers',
      word: 'slippers',
      phonetic: '/ˈslɪpərz/',
      zh: '拖鞋',
      kidDefinition: '一双软软的鞋，并排摆在一起。',
      example: 'Put on your slippers at the door.',
      category: 'balcony',
      labelBias: [34, 26]
    },
    {
      id: 'flower_pot',
      word: 'flower pot',
      phonetic: '/ˈflaʊər pɒt/',
      zh: '花盆',
      kidDefinition: '陶土小盆，里面长着一丛绿叶。',
      example: 'The flower pot is by the wall.',
      category: 'balcony',
      labelBias: [30, -28]
    },
    {
      id: 'broom',
      word: 'broom',
      phonetic: '/bruːm/',
      zh: '扫帚',
      kidDefinition: '长柄，下面一排软毛，扫灰尘用。',
      example: 'Sweep the floor with the broom.',
      category: 'balcony',
      labelBias: [40, -26]
    },
    {
      id: 'hanger',
      word: 'hanger',
      phonetic: '/ˈhæŋər/',
      zh: '衣架',
      kidDefinition: '三角形的架子，挂衣服用。',
      example: 'Hang your coat on the hanger.',
      category: 'balcony',
      labelBias: [26, -34]
    },
    {
      id: 'ball',
      word: 'ball',
      phonetic: '/bɔːl/',
      zh: '皮球',
      kidDefinition: '圆圆的球，拍一下会跳起来。',
      example: 'Bounce the ball with your hand.',
      category: 'balcony',
      labelBias: [34, 22]
    },
  ].map((item) => ({ ...item, objectName: 'OBJ_' + item.id }));

  const ROOM_BY_CATEGORY = {
    living: 'main',
    dining: 'main',
    kitchen: 'main',
    child: 'child',
    master: 'master',
    bathroom: 'bathroom',
    balcony: 'balcony'
  };

  const countOf = (category) => objects.filter((item) => item.category === category).length;
  const roomOf = (category) => ROOM_BY_CATEGORY[category];

  objects.forEach((item) => {
    item.room = roomOf(item.category);
  });

  window.WordRoomData = {
    title: '客餐厅 · 厨房 · 儿童房 · 主卧 · 卫生间 · 阳台英语探索',
    // 一间房一份取景：主屋 11.8m × 6m 是原有场景，两间卧室是东翼扩建的，卫生间与阳台在另一侧。
    rooms: {
      main: {
        zh: '客餐厅',
        tab: '客餐厅',
        eyebrow: '客餐厅 · 厨房 · 3D 场景',
        heading: '客餐厅 · 厨房英语探索',
        size: '11.8m × 6m',
        note: '从沙发走到岛台，客厅、餐厅和厨房一共 37 件东西可以点。'
      },
      child: {
        zh: '儿童房',
        tab: '儿童房',
        eyebrow: '儿童房 · 3D 场景',
        heading: '儿童房英语探索',
        size: '4.4m × 3.6m',
        note: '床、书桌和玩具都在这间屋，点开看看它们的英文名字。'
      },
      master: {
        zh: '主卧',
        tab: '主卧',
        eyebrow: '主卧 · 3D 场景',
        heading: '主卧英语探索',
        size: '4.6m × 3.6m',
        note: '双人床、衣柜和镜子，爸爸妈妈的房间也有 12 个单词。'
      },
      bathroom: {
        zh: '卫生间',
        tab: '卫生间',
        eyebrow: '卫生间 · 3D 场景',
        heading: '卫生间英语探索',
        size: '2.4m × 2.0m',
        note: '小房间里藏着洗手、洗澡、照镜子三件大事。'
      },
      balcony: {
        zh: '阳台',
        tab: '阳台',
        eyebrow: '阳台 · 3D 场景',
        heading: '阳台英语探索',
        size: '3.6m × 1.4m',
        note: '一半是家，一半是天空：洗衣机、花盆和扫帚都在这儿。'
      }
    },
    roomOrder: ['main', 'child', 'master', 'bathroom', 'balcony'],
    categories: {
      living: { zh: '客厅', en: 'LIVING ROOM', count: countOf('living'), room: 'main' },
      dining: { zh: '餐厅', en: 'DINING ROOM', count: countOf('dining'), room: 'main' },
      kitchen: { zh: '厨房', en: 'KITCHEN', count: countOf('kitchen'), room: 'main' },
      child: { zh: '儿童房', en: 'KIDS ROOM', count: countOf('child'), room: 'child' },
      master: { zh: '主卧', en: 'MASTER BEDROOM', count: countOf('master'), room: 'master' },
      bathroom: { zh: '卫生间', en: 'BATHROOM', count: countOf('bathroom'), room: 'bathroom' },
      balcony: { zh: '阳台', en: 'BALCONY', count: countOf('balcony'), room: 'balcony' }
    },
    objects
  };
})();
