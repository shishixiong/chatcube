(function (global) {
  'use strict';

  var storageKey = 'farm.discovered.v1';
  var onboardKey = 'farm.onboarded.v1';

  var objects = [
    { id: 'farmhouse', word: 'farmhouse', phonetic: '/ˈfɑːrmhaʊs/', zh: '农舍', kidDefinition: '一家人住的房子', example: 'The farmhouse is warm.', category: 'places', zone: 'farmyard_zone' },
    { id: 'barn', word: 'barn', phonetic: '/bɑːrn/', zh: '谷仓', kidDefinition: '装干草和粮食的红房子', example: 'Hay is in the barn.', category: 'places', zone: 'farmyard_zone' },
    { id: 'chicken_coop', word: 'chicken coop', phonetic: '/ˈtʃɪkɪn kuːp/', zh: '鸡舍', kidDefinition: '母鸡住的小屋', example: 'The hen sleeps in the coop.', category: 'places', zone: 'farmyard_zone' },
    { id: 'stable', word: 'stable', phonetic: '/ˈsteɪbl/', zh: '马厩', kidDefinition: '马儿休息的家', example: 'The horse is in the stable.', category: 'places', zone: 'farmyard_zone' },
    { id: 'silo', word: 'silo', phonetic: '/ˈsaɪloʊ/', zh: '筒仓', kidDefinition: '又高又圆的粮仓', example: 'The silo is very tall.', category: 'places', zone: 'farmyard_zone' },
    { id: 'windmill', word: 'windmill', phonetic: '/ˈwɪndmɪl/', zh: '风车', kidDefinition: '风一吹就转的高塔', example: 'The windmill turns in the wind.', category: 'places', zone: 'farmyard_zone' },
    { id: 'greenhouse', word: 'greenhouse', phonetic: '/ˈɡriːnhaʊs/', zh: '温室', kidDefinition: '玻璃房里的暖和小屋', example: 'Tomatoes grow in the greenhouse.', category: 'places', zone: 'field_zone' },
    { id: 'well', word: 'well', phonetic: '/wel/', zh: '水井', kidDefinition: '打水的圆井', example: 'We get water from the well.', category: 'places', zone: 'farmyard_zone' },
    { id: 'gate', word: 'gate', phonetic: '/ɡeɪt/', zh: '农场大门', kidDefinition: '农场的入口大门', example: 'Please close the gate.', category: 'places', zone: 'farmyard_zone' },
    { id: 'fence', word: 'fence', phonetic: '/fens/', zh: '栅栏', kidDefinition: '围住农场的木栏', example: 'The fence keeps animals inside.', category: 'places', zone: 'farmwide' },

    { id: 'cow', word: 'cow', phonetic: '/kaʊ/', zh: '奶牛', kidDefinition: '会产奶的大牛', example: 'The cow eats green grass.', category: 'animals', zone: 'pasture_zone' },
    { id: 'pig', word: 'pig', phonetic: '/pɪɡ/', zh: '猪', kidDefinition: '爱在泥里打滚', example: 'The pig is pink.', category: 'animals', zone: 'farmyard_zone' },
    { id: 'sheep', word: 'sheep', phonetic: '/ʃiːp/', zh: '绵羊', kidDefinition: '毛茸茸的白羊', example: 'The sheep has soft wool.', category: 'animals', zone: 'pasture_zone' },
    { id: 'horse', word: 'horse', phonetic: '/hɔːrs/', zh: '马', kidDefinition: '跑得很快的大动物', example: 'The horse can run fast.', category: 'animals', zone: 'pasture_zone' },
    { id: 'goat', word: 'goat', phonetic: '/ɡoʊt/', zh: '山羊', kidDefinition: '有角和胡须的山羊', example: 'The goat eats leaves.', category: 'animals', zone: 'pasture_zone' },
    { id: 'chicken', word: 'chicken', phonetic: '/ˈtʃɪkɪn/', zh: '母鸡', kidDefinition: '会下蛋的鸡', example: 'The chicken lays eggs.', category: 'animals', zone: 'farmyard_zone' },
    { id: 'rooster', word: 'rooster', phonetic: '/ˈruːstər/', zh: '公鸡', kidDefinition: '早上会打鸣的鸡', example: 'The rooster wakes us up.', category: 'animals', zone: 'farmyard_zone' },
    { id: 'duck', word: 'duck', phonetic: '/dʌk/', zh: '鸭子', kidDefinition: '会游泳的扁嘴鸟', example: 'The duck swims in the pond.', category: 'animals', zone: 'orchard_pond_zone' },
    { id: 'goose', word: 'goose', phonetic: '/ɡuːs/', zh: '鹅', kidDefinition: '脖子长长的水鸟', example: 'The goose has a long neck.', category: 'animals', zone: 'orchard_pond_zone' },
    { id: 'rabbit', word: 'rabbit', phonetic: '/ˈræbɪt/', zh: '兔子', kidDefinition: '长耳朵爱吃萝卜', example: 'The rabbit hops away.', category: 'animals', zone: 'farmyard_zone' },
    { id: 'cat', word: 'cat', phonetic: '/kæt/', zh: '猫', kidDefinition: '爱晒太阳的小猫', example: 'The cat sleeps by the door.', category: 'animals', zone: 'farmyard_zone' },
    { id: 'dog', word: 'dog', phonetic: '/dɔːɡ/', zh: '狗', kidDefinition: '看家护院的好朋友', example: 'The dog runs with the farmer.', category: 'animals', zone: 'farmyard_zone' },
    { id: 'bee', word: 'bee', phonetic: '/biː/', zh: '蜜蜂', kidDefinition: '嗡嗡采蜜的小虫', example: 'The bee likes flowers.', category: 'animals', zone: 'field_zone' },
    { id: 'bird', word: 'bird', phonetic: '/bɜːrd/', zh: '小鸟', kidDefinition: '会唱歌会飞翔', example: 'A bird sings in the tree.', category: 'animals', zone: 'orchard_pond_zone' },

    { id: 'wheat', word: 'wheat', phonetic: '/wiːt/', zh: '小麦', kidDefinition: '做面包的金黄谷子', example: 'The wheat is golden.', category: 'crops', zone: 'field_zone' },
    { id: 'corn', word: 'corn', phonetic: '/kɔːrn/', zh: '玉米', kidDefinition: '长着黄粒的高秆', example: 'We pick corn in autumn.', category: 'crops', zone: 'field_zone' },
    { id: 'potato', word: 'potato', phonetic: '/pəˈteɪtoʊ/', zh: '土豆', kidDefinition: '长在土里的圆块', example: 'The potato grows in soil.', category: 'crops', zone: 'field_zone' },
    { id: 'carrot', word: 'carrot', phonetic: '/ˈkærət/', zh: '胡萝卜', kidDefinition: '橙色甜甜的根', example: 'Rabbits love carrots.', category: 'crops', zone: 'field_zone' },
    { id: 'tomato', word: 'tomato', phonetic: '/təˈmeɪtoʊ/', zh: '西红柿', kidDefinition: '红红的圆果子', example: 'The tomato is red.', category: 'crops', zone: 'field_zone' },
    { id: 'pumpkin', word: 'pumpkin', phonetic: '/ˈpʌmpkɪn/', zh: '南瓜', kidDefinition: '又大又圆的橙瓜', example: 'The pumpkin is big.', category: 'crops', zone: 'field_zone' },
    { id: 'apple', word: 'apple', phonetic: '/ˈæpl/', zh: '苹果', kidDefinition: '树上红红的果子', example: 'I eat an apple.', category: 'crops', zone: 'orchard_pond_zone' },
    { id: 'strawberry', word: 'strawberry', phonetic: '/ˈstrɔːberi/', zh: '草莓', kidDefinition: '红红的小甜果', example: 'The strawberry is sweet.', category: 'crops', zone: 'orchard_pond_zone' },
    { id: 'sunflower', word: 'sunflower', phonetic: '/ˈsʌnflaʊər/', zh: '向日葵', kidDefinition: '总是朝着太阳', example: 'The sunflower is very tall.', category: 'crops', zone: 'field_zone' },
    { id: 'hay', word: 'hay', phonetic: '/heɪ/', zh: '干草', kidDefinition: '晒干的草堆', example: 'The hay is dry.', category: 'crops', zone: 'field_zone' },

    { id: 'tractor', word: 'tractor', phonetic: '/ˈtræktər/', zh: '拖拉机', kidDefinition: '力气很大的农场车', example: 'The tractor pulls the trailer.', category: 'machines', zone: 'farmyard_zone' },
    { id: 'trailer', word: 'trailer', phonetic: '/ˈtreɪlər/', zh: '拖车', kidDefinition: '被拖拉机拉着走', example: 'The trailer is full of hay.', category: 'machines', zone: 'farmyard_zone' },
    { id: 'plow', word: 'plow', phonetic: '/plaʊ/', zh: '犁', kidDefinition: '翻松泥土的工具', example: 'The plow turns the soil.', category: 'machines', zone: 'field_zone' },
    { id: 'harvester', word: 'harvester', phonetic: '/ˈhɑːrvɪstər/', zh: '收割机', kidDefinition: '收割庄稼的大机器', example: 'The harvester cuts the wheat.', category: 'machines', zone: 'field_zone' },
    { id: 'wheelbarrow', word: 'wheelbarrow', phonetic: '/ˈwiːlbæroʊ/', zh: '独轮车', kidDefinition: '一个轮子的小推车', example: 'Put the tools in the wheelbarrow.', category: 'machines', zone: 'farmyard_zone' },
    { id: 'watering_can', word: 'watering can', phonetic: '/ˈwɔːtərɪŋ kæn/', zh: '洒水壶', kidDefinition: '给植物浇水的壶', example: 'Fill the watering can.', category: 'machines', zone: 'field_zone' },
    { id: 'shovel', word: 'shovel', phonetic: '/ˈʃʌvl/', zh: '铲子', kidDefinition: '挖土用的小工具', example: 'Dig with the shovel.', category: 'machines', zone: 'farmyard_zone' },
    { id: 'pitchfork', word: 'pitchfork', phonetic: '/ˈpɪtʃfɔːrk/', zh: '干草叉', kidDefinition: '叉干草的长叉', example: 'Use the pitchfork for hay.', category: 'machines', zone: 'farmyard_zone' },

    { id: 'tree', word: 'tree', phonetic: '/triː/', zh: '大树', kidDefinition: '有粗枝和树叶', example: 'Birds live in the tree.', category: 'nature', zone: 'farmwide' },
    { id: 'grass', word: 'grass', phonetic: '/ɡræs/', zh: '草地', kidDefinition: '绿绿的软软的地', example: "Let's sit on the grass.", category: 'nature', zone: 'farmwide' },
    { id: 'flower', word: 'flower', phonetic: '/ˈflaʊər/', zh: '花', kidDefinition: '有颜色会香香', example: 'The flower is pink.', category: 'nature', zone: 'orchard_pond_zone' },
    { id: 'pond', word: 'pond', phonetic: '/pɑːnd/', zh: '池塘', kidDefinition: '一小片静静的水', example: 'Ducks swim in the pond.', category: 'nature', zone: 'orchard_pond_zone' },
    { id: 'hill', word: 'hill', phonetic: '/hɪl/', zh: '小山', kidDefinition: '矮矮的绿色山包', example: 'The sheep walk up the hill.', category: 'nature', zone: 'pasture_zone' },

    { id: 'farmer', word: 'farmer', phonetic: '/ˈfɑːrmər/', zh: '农民', kidDefinition: '种地养动物的人', example: 'The farmer feeds the cows.', category: 'people', zone: 'farmwide' },
    { id: 'child', word: 'child', phonetic: '/tʃaɪld/', zh: '小朋友', kidDefinition: '在农场玩耍的孩子', example: 'The child waves hello.', category: 'people', zone: 'farmyard_zone' },
    { id: 'grandma', word: 'grandma', phonetic: '/ˈɡrænmɑː/', zh: '奶奶', kidDefinition: '会做好吃的老人家', example: 'Grandma bakes bread.', category: 'people', zone: 'farmyard_zone' }
  ];

  var categories = {
    places: { id: 'places', label: '地点', color: '#E07A5F', icon: 'house' },
    animals: { id: 'animals', label: '动物', color: '#C3A6F5', icon: 'paw' },
    crops: { id: 'crops', label: '作物', color: '#F2C14E', icon: 'sprout' },
    machines: { id: 'machines', label: '农机', color: '#6FA8DC', icon: 'gear' },
    nature: { id: 'nature', label: '自然', color: '#7ECB6A', icon: 'mountain' },
    people: { id: 'people', label: '人物', color: '#8FC7B0', icon: 'user' }
  };

  var categoryOrder = ['places', 'animals', 'crops', 'machines', 'nature', 'people'];

  var zones = [
    { id: 'overview', label: '全农场', en: 'Overview', icon: 'farm', hint: '转动农场，找找今天想认识谁' },
    { id: 'farmyard_zone', label: '农舍区', en: 'Farmyard', icon: 'house', hint: '红谷仓和农舍都住在这里' },
    { id: 'field_zone', label: '田地区', en: 'Field', icon: 'sprout', hint: '麦田、玉米地和温室' },
    { id: 'pasture_zone', label: '牧场区', en: 'Pasture', icon: 'paw', hint: '奶牛、绵羊、马和山羊在草坡上' },
    { id: 'orchard_pond_zone', label: '果园池塘', en: 'Orchard', icon: 'water', hint: '苹果树和池塘里的鸭子' }
  ];

  var views = {
    overview: { target: [0, 2, 0], radius: 150, theta: 0.80, phi: 0.96, focus: ['farmer', 'wheat', 'cow', 'apple'] },
    farmyard_zone: { target: [-32, 4, -20], radius: 68, theta: 0.62, phi: 0.95, focus: ['barn', 'chicken', 'pig', 'tractor'] },
    field_zone: { target: [38, 3, -24], radius: 66, theta: 0.70, phi: 0.92, focus: ['wheat', 'corn', 'sunflower', 'greenhouse'] },
    pasture_zone: { target: [-30, 3, 24], radius: 70, theta: 0.90, phi: 0.95, focus: ['cow', 'sheep', 'horse', 'goat', 'hill'] },
    orchard_pond_zone: { target: [38, 2, 26], radius: 62, theta: 0.80, phi: 0.92, focus: ['pond', 'duck', 'apple', 'flower'] }
  };

  var camera = { minRadius: 10, maxRadius: 320, minPhi: 0.2, maxPhi: 1.32 };

  var layout = {
    farmhouse: { x: -48, z: -14, ry: 0.10 },
    barn: { x: -34, z: -28, ry: 0.06 },
    chicken_coop: { x: -20, z: -26, ry: 0.22 },
    stable: { x: -48, z: -34, ry: 0 },
    silo: { x: -22, z: -32, ry: 0 },
    windmill: { x: -14, z: -22, ry: 0 },
    greenhouse: { x: 36, z: -36, ry: 0.04 },
    well: { x: -30, z: -13, ry: 0 },
    gate: { x: -66, z: -8, ry: Math.PI / 2 },
    fence: { x: 0, z: -52, ry: 0 },

    cow: { x: -30, z: 16, ry: -0.6 },
    pig: { x: -40, z: -20, ry: 0.4 },
    sheep: { x: -42, z: 24, ry: -1.2 },
    horse: { x: -16, z: 26, ry: 0.8 },
    goat: { x: -56, z: 14, ry: -0.4 },
    chicken: { x: -20, z: -22.5, ry: 0.9 },
    rooster: { x: -17, z: -20.8, ry: -0.5 },
    duck: { x: 42, z: 30, ry: 0.3 },
    goose: { x: 33, z: 28, ry: -0.7 },
    rabbit: { x: -31.2, z: -21.2, ry: 0.15 },
    cat: { x: -45, z: -8, ry: 0.9 },
    dog: { x: 0, z: 0, ry: 0 },
    bee: { x: 40, z: -14, ry: 0 },
    bird: { x: 24, z: 12, ry: 0 },

    wheat: { x: 44, z: -22 },
    corn: { x: 27, z: -24 },
    potato: { x: 54, z: -34 },
    carrot: { x: 50, z: -18 },
    tomato: { x: 58, z: -28 },
    pumpkin: { x: 46, z: -34 },
    apple: { x: 20, z: 12 },
    strawberry: { x: 24, z: 40 },
    sunflower: { x: 32, z: -16 },
    hay: { x: 22, z: -32 },

    tractor: { x: 0, z: 0, ry: 0 },
    trailer: { x: 0, z: 0, ry: 0 },
    plow: { x: 26, z: -13, ry: 0.4 },
    harvester: { x: 62, z: -12, ry: 0.1 },
    wheelbarrow: { x: -27.0, z: -13.8, ry: 0.5 },
    watering_can: { x: 36, z: -8, ry: 0.2 },
    shovel: { x: -44, z: -22, ry: 0.7 },
    pitchfork: { x: -24.6, z: -12.6, ry: -0.3 },

    tree: { x: -62, z: 20 },
    grass: { x: 0, z: 0 },
    flower: { x: 26, z: 16 },
    pond: { x: 38, z: 26 },
    hill: { x: -52, z: 34 },

    farmer: { x: 0, z: 0 },
    child: { x: 0, z: 0 },
    grandma: { x: -54, z: -6 }
  };

  var palette = {
    cream: '#FFF8E7',
    grass: '#8FBF6A',
    sage: '#A8C686',
    wheat: '#F2C14E',
    barn: '#C8553D',
    soil: '#C9A66B',
    sky: '#DDF3FF',
    water: '#7EC8E3',
    ink: '#3D3527'
  };

  global.FarmData = {
    objects: objects,
    categories: categories,
    categoryOrder: categoryOrder,
    zones: zones,
    views: views,
    camera: camera,
    storageKey: storageKey,
    onboardKey: onboardKey,
    layout: layout,
    palette: palette
  };
})(window);
