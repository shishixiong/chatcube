/* ============================================================
   小词城 Word City · 唯一数据源
   50 个单词、5 个分区镜头、交通与行人配置。
   单词卡的英文 / 音标 / 中文 / 儿童解释 / 例句全部从这里读取，
   UI 层不允许再硬编码任何单词文案。
   ============================================================ */
(function () {
  'use strict';

  /* 分类：单词卡 chip、词汇表分组、进度点阵共用 */
  var categories = [
    {
      id: 'places',
      label: '地点',
      en: 'Places',
      color: '#6FA8DC',
      icon: '<path d="M4 20V9.5L12 4l8 5.5V20a1 1 0 0 1-1 1h-5v-6h-4v6H5a1 1 0 0 1-1-1Z"/>'
    },
    {
      id: 'transport',
      label: '交通',
      en: 'Transport',
      color: '#F2C14E',
      icon: '<path d="M5 16V7a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v9"/><path d="M5 16h14v2a1 1 0 0 1-1 1h-1a1 1 0 0 1-1-1v-1H8v1a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1v-2Z"/><circle cx="7.5" cy="11.5" r="1"/><circle cx="16.5" cy="11.5" r="1"/>'
    },
    {
      id: 'street',
      label: '街道',
      en: 'Street',
      color: '#8FC7B0',
      icon: '<path d="M12 3v18"/><path d="M6 6h3M6 12h3M6 18h3M15 6h3M15 12h3M15 18h3"/>'
    },
    {
      id: 'people',
      label: '人物',
      en: 'People',
      color: '#F2826A',
      icon: '<circle cx="12" cy="8" r="3.4"/><path d="M5 20a7 7 0 0 1 14 0"/>'
    },
    {
      id: 'nature',
      label: '自然',
      en: 'Nature',
      color: '#7ECB6A',
      icon: '<path d="M12 21V10"/><path d="M12 13c-4 0-6-2.4-6-5.5C9.4 7.5 12 9 12 13Z"/><path d="M12 10c0-3 2.2-5 5.5-5.5C17.5 8 15.4 10 12 10Z"/>'
    },
    {
      id: 'animals',
      label: '动物',
      en: 'Animals',
      color: '#C3A6F5',
      icon: '<ellipse cx="12" cy="15" rx="5.2" ry="4.2"/><circle cx="6.4" cy="9.6" r="2.1"/><circle cx="11" cy="7.2" r="2.1"/><circle cx="16.4" cy="8.4" r="2.1"/><circle cx="19.2" cy="13" r="1.9"/>'
    }
  ];

  /* 50 个可点单词（顺序固定，id 不可更改） */
  var objects = [
    /* ---- places 地点 ---- */
    { id: 'hospital', word: 'hospital', phonetic: '/ˈhɑːspɪtl/', zh: '医院', kidDefinition: '生病时去看医生的地方。', example: 'I go to the hospital when I am sick.', category: 'places', zone: 'hospital_zone' },
    { id: 'school', word: 'school', phonetic: '/skuːl/', zh: '学校', kidDefinition: '小朋友上课和玩耍的地方。', example: 'I learn ABC at school.', category: 'places', zone: 'school_zone' },
    { id: 'park', word: 'park', phonetic: '/pɑːrk/', zh: '公园', kidDefinition: '有大树和草地，可以散步玩的地方。', example: 'We play in the park.', category: 'places', zone: 'park_zone' },
    { id: 'supermarket', word: 'supermarket', phonetic: '/ˈsuːpərmɑːrkɪt/', zh: '超市', kidDefinition: '可以买到食物和日用品的大商店。', example: 'Mom buys milk at the supermarket.', category: 'places', zone: 'main_street' },
    { id: 'bus_stop', word: 'bus stop', phonetic: '/ˈbʌs stɑːp/', zh: '公交站', kidDefinition: '等公交车的地方。', example: 'We wait at the bus stop.', category: 'places', zone: 'main_street' },
    { id: 'police_station', word: 'police station', phonetic: '/pəˈliːs ˈsteɪʃən/', zh: '警察局', kidDefinition: '警察叔叔工作的地方。', example: 'The police officer works at the police station.', category: 'places', zone: 'main_street' },
    { id: 'fire_station', word: 'fire station', phonetic: '/ˈfaɪər ˈsteɪʃən/', zh: '消防站', kidDefinition: '消防员和消防车住的地方。', example: 'The fire truck lives at the fire station.', category: 'places', zone: 'hospital_zone' },
    { id: 'library', word: 'library', phonetic: '/ˈlaɪbreri/', zh: '图书馆', kidDefinition: '可以安静看书、借书的地方。', example: 'I read books at the library.', category: 'places', zone: 'school_zone' },
    { id: 'bakery', word: 'bakery', phonetic: '/ˈbeɪkəri/', zh: '面包店', kidDefinition: '烤面包和蛋糕的香香小店。', example: 'The bakery smells sweet.', category: 'places', zone: 'main_street' },
    { id: 'cafe', word: 'cafe', phonetic: '/kæˈfeɪ/', zh: '咖啡馆', kidDefinition: '可以坐下来喝东西的地方。', example: 'We drink juice at the cafe.', category: 'places', zone: 'main_street' },
    { id: 'post_office', word: 'post office', phonetic: '/ˈpoʊst ˌɔːfɪs/', zh: '邮局', kidDefinition: '寄信和包裹的地方。', example: 'I send a letter at the post office.', category: 'places', zone: 'main_street' },
    { id: 'cinema', word: 'cinema', phonetic: '/ˈsɪnəmə/', zh: '电影院', kidDefinition: '看大银幕电影的地方。', example: 'We watch a movie at the cinema.', category: 'places', zone: 'main_street' },

    /* ---- transport 交通 ---- */
    { id: 'bus', word: 'bus', phonetic: '/bʌs/', zh: '公交车', kidDefinition: '载很多人一起走的车。', example: 'The bus takes us to school.', category: 'transport', zone: 'main_street' },
    { id: 'car', word: 'car', phonetic: '/kɑːr/', zh: '小汽车', kidDefinition: '爸爸开的小汽车。', example: 'The car is red.', category: 'transport', zone: 'main_street' },
    { id: 'taxi', word: 'taxi', phonetic: '/ˈtæksi/', zh: '出租车', kidDefinition: '招手就停、送你去目的地的车。', example: 'We take a taxi to the station.', category: 'transport', zone: 'main_street' },
    { id: 'bicycle', word: 'bicycle', phonetic: '/ˈbaɪsɪkl/', zh: '自行车', kidDefinition: '用脚踩的两轮车。', example: 'I ride my bicycle.', category: 'transport', zone: 'school_zone' },
    { id: 'ambulance', word: 'ambulance', phonetic: '/ˈæmbjələns/', zh: '救护车', kidDefinition: '送病人去医院的白色车。', example: 'The ambulance goes to the hospital.', category: 'transport', zone: 'hospital_zone' },
    { id: 'fire_truck', word: 'fire truck', phonetic: '/ˈfaɪər trʌk/', zh: '消防车', kidDefinition: '消防员灭火开的红色大车。', example: 'The fire truck is red.', category: 'transport', zone: 'hospital_zone' },
    { id: 'school_bus', word: 'school bus', phonetic: '/skuːl bʌs/', zh: '校车', kidDefinition: '接送小朋友上学的黄色车。', example: 'The school bus picks up the children.', category: 'transport', zone: 'school_zone' },
    { id: 'truck', word: 'truck', phonetic: '/trʌk/', zh: '卡车', kidDefinition: '装很多货物的大车。', example: 'The truck carries boxes.', category: 'transport', zone: 'main_street' },
    { id: 'scooter', word: 'scooter', phonetic: '/ˈskuːtər/', zh: '滑板车', kidDefinition: '一只脚踩、一只脚蹬的小车。', example: 'I ride my scooter in the park.', category: 'transport', zone: 'park_zone' },
    { id: 'boat', word: 'boat', phonetic: '/boʊt/', zh: '小船', kidDefinition: '在水上开的船。', example: 'The boat sails on the river.', category: 'transport', zone: 'park_zone' },

    /* ---- street 街道 ---- */
    { id: 'road', word: 'road', phonetic: '/roʊd/', zh: '马路', kidDefinition: '汽车和行人走的马路。', example: 'Cars drive on the road.', category: 'street', zone: 'citywide' },
    { id: 'crosswalk', word: 'crosswalk', phonetic: '/ˈkrɔːswɔːk/', zh: '斑马线', kidDefinition: '过马路时走的白色条纹。', example: 'Walk on the crosswalk.', category: 'street', zone: 'school_zone' },
    { id: 'traffic_light', word: 'traffic light', phonetic: '/ˈtræfɪk laɪt/', zh: '红绿灯', kidDefinition: '红黄绿三色灯，指挥车和行人。', example: 'The traffic light is green.', category: 'street', zone: 'school_zone' },
    { id: 'streetlight', word: 'streetlight', phonetic: '/ˈstriːtlaɪt/', zh: '路灯', kidDefinition: '晚上照亮马路的灯。', example: 'The streetlight helps us see at night.', category: 'street', zone: 'main_street' },
    { id: 'bench', word: 'bench', phonetic: '/bentʃ/', zh: '长椅', kidDefinition: '公园里可以坐下休息的长椅。', example: 'We sit on the bench.', category: 'street', zone: 'park_zone' },
    { id: 'trash_can', word: 'trash can', phonetic: '/træʃ kæn/', zh: '垃圾桶', kidDefinition: '扔垃圾的地方。', example: 'Put the paper in the trash can.', category: 'street', zone: 'main_street' },
    { id: 'mailbox', word: 'mailbox', phonetic: '/ˈmeɪlbɑːks/', zh: '邮筒', kidDefinition: '把信投进去的箱子。', example: 'I put a letter in the mailbox.', category: 'street', zone: 'main_street' },
    { id: 'bridge', word: 'bridge', phonetic: '/brɪdʒ/', zh: '小桥', kidDefinition: '架在河上，可以走过去。', example: 'We walk across the bridge.', category: 'street', zone: 'park_zone' },
    { id: 'fountain', word: 'fountain', phonetic: '/ˈfaʊntn/', zh: '喷泉', kidDefinition: '会喷水的小水池。', example: 'Water comes out of the fountain.', category: 'street', zone: 'main_street' },

    /* ---- people 人物 ---- */
    { id: 'teacher', word: 'teacher', phonetic: '/ˈtiːtʃər/', zh: '老师', kidDefinition: '教小朋友学习的人。', example: 'My teacher is kind.', category: 'people', zone: 'school_zone' },
    { id: 'doctor', word: 'doctor', phonetic: '/ˈdɑːktər/', zh: '医生', kidDefinition: '帮病人看病的人。', example: 'The doctor helps sick people.', category: 'people', zone: 'hospital_zone' },
    { id: 'nurse', word: 'nurse', phonetic: '/nɜːrs/', zh: '护士', kidDefinition: '在医院照顾病人的人。', example: 'The nurse is very kind.', category: 'people', zone: 'hospital_zone' },
    { id: 'police_officer', word: 'police officer', phonetic: '/pəˈliːs ˈɔːfɪsər/', zh: '警察', kidDefinition: '保护大家安全的警察。', example: 'The police officer helps us.', category: 'people', zone: 'main_street' },
    { id: 'firefighter', word: 'firefighter', phonetic: '/ˈfaɪərfaɪtər/', zh: '消防员', kidDefinition: '灭火救人的消防员。', example: 'The firefighter is brave.', category: 'people', zone: 'hospital_zone' },
    { id: 'driver', word: 'driver', phonetic: '/ˈdraɪvər/', zh: '司机', kidDefinition: '开车的人。', example: 'The bus driver says hello.', category: 'people', zone: 'main_street' },
    { id: 'baker', word: 'baker', phonetic: '/ˈbeɪkər/', zh: '面包师', kidDefinition: '做面包和蛋糕的人。', example: 'The baker makes bread.', category: 'people', zone: 'main_street' },
    { id: 'student', word: 'student', phonetic: '/ˈstuːdnt/', zh: '学生', kidDefinition: '在学校学习的小朋友。', example: 'I am a student.', category: 'people', zone: 'school_zone' },

    /* ---- nature 自然 ---- */
    { id: 'tree', word: 'tree', phonetic: '/triː/', zh: '树', kidDefinition: '有树干、树枝和叶子的大植物。', example: 'The tree is tall.', category: 'nature', zone: 'park_zone' },
    { id: 'flower', word: 'flower', phonetic: '/ˈflaʊər/', zh: '花', kidDefinition: '有花瓣、香香的小植物。', example: 'The flower is pink.', category: 'nature', zone: 'park_zone' },
    { id: 'grass', word: 'grass', phonetic: '/ɡræs/', zh: '草地', kidDefinition: '地上绿绿的矮矮的植物。', example: 'The grass is green.', category: 'nature', zone: 'park_zone' },
    { id: 'pond', word: 'pond', phonetic: '/pɑːnd/', zh: '池塘', kidDefinition: '公园里的小水池。', example: 'Ducks swim in the pond.', category: 'nature', zone: 'park_zone' },
    { id: 'swing', word: 'swing', phonetic: '/swɪŋ/', zh: '秋千', kidDefinition: '荡来荡去的秋千。', example: 'I swing high on the swing.', category: 'nature', zone: 'park_zone' },
    { id: 'slide', word: 'slide', phonetic: '/slaɪd/', zh: '滑梯', kidDefinition: '从上面滑下来的滑梯。', example: 'I slide down the slide.', category: 'nature', zone: 'park_zone' },
    { id: 'seesaw', word: 'seesaw', phonetic: '/ˈsiːsɔː/', zh: '跷跷板', kidDefinition: '一上一下的跷跷板。', example: 'We play on the seesaw.', category: 'nature', zone: 'park_zone' },
    { id: 'kite', word: 'kite', phonetic: '/kaɪt/', zh: '风筝', kidDefinition: '用线拉着飞上天的玩具。', example: 'The kite flies in the sky.', category: 'nature', zone: 'park_zone' },

    /* ---- animals 动物 ---- */
    { id: 'duck', word: 'duck', phonetic: '/dʌk/', zh: '鸭子', kidDefinition: '会游泳、嘎嘎叫的小动物。', example: 'The duck says quack.', category: 'animals', zone: 'park_zone' },
    { id: 'dog', word: 'dog', phonetic: '/dɔːɡ/', zh: '小狗', kidDefinition: '会汪汪叫、爱摇尾巴的小动物。', example: 'The dog runs fast.', category: 'animals', zone: 'park_zone' },
    { id: 'bird', word: 'bird', phonetic: '/bɜːrd/', zh: '小鸟', kidDefinition: '有翅膀、会飞的小动物。', example: 'The bird sings in the tree.', category: 'animals', zone: 'citywide' }
  ];

  /* 5 个分区镜头。fit 为需要适配的地面跨度（米），由场景按屏幕比例换算距离 */
  var zones = [
    { id: 'overview', label: '全城', en: 'Word City', hint: '整座小城' },
    { id: 'main_street', label: '商业街', en: 'Main Street', hint: '超市 · 面包店 · 喷泉' },
    { id: 'school_zone', label: '学校', en: 'School', hint: '学校 · 图书馆 · 斑马线' },
    { id: 'park_zone', label: '公园', en: 'Park', hint: '池塘 · 游乐场 · 小桥' },
    { id: 'hospital_zone', label: '医院', en: 'Hospital', hint: '医院 · 消防站' }
  ];

  var views = {
    overview: { target: [0, 0, 0], fit: [142, 110], phi: 0.62, theta: -0.52 },
    main_street: { target: [-20, 2.5, 10], radius: 60, phi: 1.0, theta: -0.3 },
    school_zone: { target: [14, 2.5, -14], radius: 62, phi: 1.0, theta: 0.24 },
    park_zone: { target: [30, 2, 21], radius: 64, phi: 1.02, theta: 0.12 },
    hospital_zone: { target: [-34, 3.5, -17], radius: 66, phi: 0.98, theta: -0.14 }
  };

  /* 相机通用限制 */
  var camera = {
    minRadius: 22,
    maxRadius: 320,
    minPhi: 0.2,
    maxPhi: 1.32,
    flightMs: 900,
    focusRadius: 30,
    focusPhi: 1.0
  };

  /* 交通配置：两条闭合车道（A 内环、B 外环），两个信号灯路口 + 学校门口值日警察 */
  var traffic = {
    lights: [
      { id: 'school', x: -10, z: 0, offset: 0 },
      { id: 'park', x: 35, z: 0, offset: 7 }
    ],
    guard: { x: 10, z: 0, cycle: 26, stopFrom: 8, stopTo: 17 },
    loops: {
      A: [
        [-10, 2.2], [4, 2.2], [20, 2.2], [30, 2.2], [33.4, 2.1], [35, 0.6],
        [35, -6], [35, -24], [35, -30], [33, -32], [28, -32], [4, -32],
        [-8, -32], [-10, -30], [-10, -24], [-10, -6], [-10, 0.4]
      ],
      B: [
        [35, -2.2], [20, -2.2], [4, -2.2], [-6, -2.2], [-9.2, -2.4], [-11.5, -4.4],
        [-11.5, -10], [-11.5, -26], [-11.5, -31.5], [-9, -34], [-4, -34],
        [10, -34], [28, -34], [34, -34], [36.5, -31], [36.5, -26],
        [36.5, -10], [36.5, -4], [35, -2.2]
      ]
    },
    stops: [
      { loop: 'A', x: 10, z: 2.2, dwell: 4, types: ['bus'] },
      { loop: 'B', x: 16, z: -2.2, dwell: 3, types: ['school_bus'] }
    ],
    vehicles: [
      { type: 'bus', loop: 'A', offset: 0.02, speed: 6.4, word: 'bus' },
      { type: 'bus', loop: 'A', offset: 0.52, speed: 6.0 },
      { type: 'car', loop: 'A', offset: 0.16, speed: 8.6, color: '#F2826A', word: 'car' },
      { type: 'car', loop: 'B', offset: 0.2, speed: 8.2, color: '#6FA8DC' },
      { type: 'car', loop: 'B', offset: 0.48, speed: 7.6, color: '#F2C14E' },
      { type: 'car', loop: 'A', offset: 0.7, speed: 9.0, color: '#FFF3D6' },
      { type: 'taxi', loop: 'B', offset: 0.7, speed: 8.4, word: 'taxi' },
      { type: 'ambulance', loop: 'A', offset: 0.34, speed: 9.4, word: 'ambulance' },
      { type: 'fire_truck', loop: 'B', offset: 0.08, speed: 7.2, word: 'fire_truck' },
      { type: 'school_bus', loop: 'B', offset: 0.33, speed: 6.2, word: 'school_bus' },
      { type: 'truck', loop: 'A', offset: 0.45, speed: 7.0, word: 'truck' },
      { type: 'bicycle', loop: 'A', offset: 0.28, speed: 3.1, word: 'bicycle' },
      { type: 'bicycle', loop: 'B', offset: 0.62, speed: 2.9 },
      { type: 'bicycle', loop: 'A', offset: 0.88, speed: 3.3 },
      { type: 'boat', loop: 'river', offset: 0.1, speed: 1.6, word: 'boat' }
    ],
    riverPath: [
      [18, 36.5], [22, 36.9], [26, 36.3], [30, 36.7]
    ],
    pedestrians: [
      { type: 'student', loop: 'main', offset: 0.03, speed: 1.25 },
      { type: 'office', loop: 'main', offset: 0.31, speed: 1.35 },
      { type: 'parent', loop: 'main', offset: 0.62, speed: 1.1 },
      { type: 'dogwalker', loop: 'main', offset: 0.78, speed: 1.18 },
      { type: 'courier', loop: 'plaza', offset: 0.12, speed: 1.4 },
      { type: 'child', loop: 'plaza', offset: 0.52, speed: 1.5 },
      { type: 'student', loop: 'park', offset: 0.09, speed: 1.2 },
      { type: 'office', loop: 'park', offset: 0.4, speed: 1.3 },
      { type: 'parent', loop: 'park', offset: 0.73, speed: 1.05 },
      { type: 'child', loop: 'school', offset: 0.14, speed: 1.45 },
      { type: 'student', loop: 'school', offset: 0.46, speed: 1.3 },
      { type: 'teacher', loop: 'school', offset: 0.7, speed: 1.15 }
    ],
    pedestrianLoops: {
      main: [
        [-52, 6.2], [-30, 6.2], [-8, 6.2], [16, 6.2], [40, 6.2], [54, 6.2],
        [54, 7.6], [30, 7.6], [4, 7.6], [-20, 7.6], [-52, 7.6]
      ],
      plaza: [
        [-6, 6.4], [5, 6.4], [7.4, 8.4], [7.4, 14.4], [5, 16.6], [-5, 16.6],
        [-7.4, 14.4], [-7.4, 8.6]
      ],
      park: [
        [12, 8], [22, 8], [28, 10], [28, 16], [26, 22],
        [24, 28], [14, 29], [12, 16]
      ],
      school: [
        [2, -11], [22, -11], [26, -10], [26, -8], [2, -8]
      ]
    },
    crossing: { x: 10, z0: 6.3, z1: -6.3, speed: 1.15 }
  };

  window.WordCityData = {
    objects: objects,
    categories: categories,
    zones: zones,
    views: views,
    camera: camera,
    traffic: traffic,
    storageKey: 'wordcity.discovered.v1',
    onboardKey: 'wordcity.onboarded.v1'
  };
})();
