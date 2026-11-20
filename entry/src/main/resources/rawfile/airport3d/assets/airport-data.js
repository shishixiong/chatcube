(function (global) {
  'use strict';

  // 50 个可点击单词。category: places / aircraft / vehicles / people / facilities
  // zone: overview / terminal_zone / apron_zone / runway_zone / hangar_zone
  var objects = [
    { id: 'terminal', word: 'terminal', phonetic: '/ˈtɜːrmɪnl/', zh: '航站楼', kidDefinition: '坐飞机前办手续的大厅', example: 'We wait in the terminal.', category: 'places', zone: 'terminal_zone' },
    { id: 'control_tower', word: 'control tower', phonetic: '/kənˈtroʊl ˈtaʊər/', zh: '塔台', kidDefinition: '指挥飞机起降的高塔', example: 'The tower watches the planes.', category: 'places', zone: 'runway_zone' },
    { id: 'runway', word: 'runway', phonetic: '/ˈrʌnweɪ/', zh: '跑道', kidDefinition: '飞机起飞和降落的长路', example: 'The plane runs on the runway.', category: 'places', zone: 'runway_zone' },
    { id: 'taxiway', word: 'taxiway', phonetic: '/ˈtæksiweɪ/', zh: '滑行道', kidDefinition: '飞机慢慢开去跑道的小路', example: 'The plane rolls on the taxiway.', category: 'places', zone: 'runway_zone' },
    { id: 'apron', word: 'apron', phonetic: '/ˈeɪprən/', zh: '停机坪', kidDefinition: '飞机停靠的大空地', example: 'Planes park on the apron.', category: 'places', zone: 'apron_zone' },
    { id: 'hangar', word: 'hangar', phonetic: '/ˈhæŋər/', zh: '机库', kidDefinition: '停放和修理飞机的大房子', example: 'The plane sleeps in the hangar.', category: 'places', zone: 'hangar_zone' },
    { id: 'cargo_shed', word: 'cargo shed', phonetic: '/ˈkɑːrɡoʊ ʃed/', zh: '货运仓库', kidDefinition: '装货物的大仓库', example: 'Boxes wait in the cargo shed.', category: 'places', zone: 'hangar_zone' },
    { id: 'fire_station', word: 'fire station', phonetic: '/ˈfaɪər ˈsteɪʃn/', zh: '消防站', kidDefinition: '机场消防车住的地方', example: 'The fire truck leaves the fire station.', category: 'places', zone: 'hangar_zone' },
    { id: 'airport_hotel', word: 'airport hotel', phonetic: '/ˈerpɔːrt hoʊˈtel/', zh: '机场酒店', kidDefinition: '机场旁边住旅客的酒店', example: 'We sleep at the airport hotel.', category: 'places', zone: 'overview' },
    { id: 'car_park', word: 'car park', phonetic: '/kɑːr pɑːrk/', zh: '停车场', kidDefinition: '停很多车的大楼', example: 'Our car is in the car park.', category: 'places', zone: 'overview' },
    { id: 'jet_bridge', word: 'jet bridge', phonetic: '/dʒet brɪdʒ/', zh: '登机桥', kidDefinition: '从候机楼走到飞机上的桥', example: 'We walk through the jet bridge.', category: 'places', zone: 'apron_zone' },
    { id: 'gate', word: 'gate', phonetic: '/ɡeɪt/', zh: '登机口', kidDefinition: '上飞机前等待的地方', example: 'We wait at gate five.', category: 'places', zone: 'terminal_zone' },
    { id: 'check_in', word: 'check-in desk', phonetic: '/ˈtʃek ɪn desk/', zh: '值机柜台', kidDefinition: '换登机牌和托运行李的柜台', example: 'We check in at the desk.', category: 'places', zone: 'terminal_zone' },
    { id: 'baggage_carousel', word: 'baggage carousel', phonetic: '/ˈbæɡɪdʒ ˌkærəˈsel/', zh: '行李转盘', kidDefinition: '等行李转出来的大转盘', example: 'Our bags come on the carousel.', category: 'places', zone: 'terminal_zone' },

    { id: 'airplane', word: 'airplane', phonetic: '/ˈerpleɪn/', zh: '飞机', kidDefinition: '在天上飞的大机器', example: 'The airplane flies high.', category: 'aircraft', zone: 'apron_zone' },
    { id: 'jet', word: 'jet', phonetic: '/dʒet/', zh: '喷气式飞机', kidDefinition: '喷气飞得很快的飞机', example: 'The jet flies very fast.', category: 'aircraft', zone: 'apron_zone' },
    { id: 'turboprop', word: 'turboprop', phonetic: '/ˈtɜːrboʊprɑːp/', zh: '螺旋桨飞机', kidDefinition: '用螺旋桨飞的飞机', example: 'The turboprop has propellers.', category: 'aircraft', zone: 'hangar_zone' },
    { id: 'private_jet', word: 'private jet', phonetic: '/ˈpraɪvət dʒet/', zh: '私人飞机', kidDefinition: '一家人用的小飞机', example: 'The private jet is small.', category: 'aircraft', zone: 'apron_zone' },
    { id: 'cargo_plane', word: 'cargo plane', phonetic: '/ˈkɑːrɡoʊ pleɪn/', zh: '货运飞机', kidDefinition: '专门运货的飞机', example: 'The cargo plane carries boxes.', category: 'aircraft', zone: 'hangar_zone' },
    { id: 'helicopter', word: 'helicopter', phonetic: '/ˈhelɪkɑːptər/', zh: '直升机', kidDefinition: '头顶有螺旋桨的飞行器', example: 'The helicopter hovers.', category: 'aircraft', zone: 'apron_zone' },

    { id: 'pushback_tug', word: 'pushback tug', phonetic: '/ˈpʊʃbæk tʌɡ/', zh: '推车', kidDefinition: '把飞机推出机位的小车', example: 'The tug pushes the plane.', category: 'vehicles', zone: 'apron_zone' },
    { id: 'baggage_tug', word: 'baggage tug', phonetic: '/ˈbæɡɪdʒ tʌɡ/', zh: '行李牵引车', kidDefinition: '拖着行李车的小车', example: 'The baggage tug pulls carts.', category: 'vehicles', zone: 'apron_zone' },
    { id: 'baggage_cart', word: 'baggage cart', phonetic: '/ˈbæɡɪdʒ kɑːrt/', zh: '行李车', kidDefinition: '装行李的小车', example: 'Suitcases ride on the cart.', category: 'vehicles', zone: 'apron_zone' },
    { id: 'container_loader', word: 'container loader', phonetic: '/kənˈteɪnər ˈloʊdər/', zh: '集装箱装载机', kidDefinition: '把货箱装上飞机的大车', example: 'The loader lifts the container.', category: 'vehicles', zone: 'apron_zone' },
    { id: 'belt_loader', word: 'belt loader', phonetic: '/belt ˈloʊdər/', zh: '传送带车', kidDefinition: '把行李送上飞机的传送带车', example: 'Bags go up the belt loader.', category: 'vehicles', zone: 'apron_zone' },
    { id: 'fuel_truck', word: 'fuel truck', phonetic: '/ˈfjuːəl trʌk/', zh: '加油车', kidDefinition: '给飞机加油的大车', example: 'The fuel truck fills the plane.', category: 'vehicles', zone: 'apron_zone' },
    { id: 'catering_truck', word: 'catering truck', phonetic: '/ˈkeɪtərɪŋ trʌk/', zh: '餐车', kidDefinition: '给飞机送饭的卡车', example: 'The catering truck brings food.', category: 'vehicles', zone: 'apron_zone' },
    { id: 'airstairs_truck', word: 'airstairs truck', phonetic: '/ˈersterz trʌk/', zh: '客梯车', kidDefinition: '带楼梯的登机小车', example: 'We climb the airstairs truck.', category: 'vehicles', zone: 'apron_zone' },
    { id: 'airport_bus', word: 'airport bus', phonetic: '/ˈerpɔːrt bʌs/', zh: '摆渡车', kidDefinition: '在机场里接送乘客的大巴', example: 'The bus takes us to the plane.', category: 'vehicles', zone: 'apron_zone' },
    { id: 'follow_me_car', word: 'follow-me car', phonetic: '/ˈfɑːloʊ mi kɑːr/', zh: '引导车', kidDefinition: '给飞机带路的小黄车', example: 'The follow-me car leads the plane.', category: 'vehicles', zone: 'runway_zone' },
    { id: 'fire_truck', word: 'fire truck', phonetic: '/ˈfaɪər trʌk/', zh: '消防车', kidDefinition: '喷水灭火的大红车', example: 'The fire truck is ready.', category: 'vehicles', zone: 'hangar_zone' },
    { id: 'sweeper', word: 'sweeper', phonetic: '/ˈswiːpər/', zh: '清扫车', kidDefinition: '打扫停机坪的清洁车', example: 'The sweeper cleans the apron.', category: 'vehicles', zone: 'apron_zone' },

    { id: 'pilot', word: 'pilot', phonetic: '/ˈpaɪlət/', zh: '飞行员', kidDefinition: '开飞机的人', example: 'The pilot sits in the cockpit.', category: 'people', zone: 'apron_zone' },
    { id: 'flight_attendant', word: 'flight attendant', phonetic: '/flaɪt əˈtendənt/', zh: '空乘', kidDefinition: '在飞机上照顾乘客的人', example: 'The flight attendant smiles.', category: 'people', zone: 'terminal_zone' },
    { id: 'traveller', word: 'traveller', phonetic: '/ˈtrævələr/', zh: '旅客', kidDefinition: '坐飞机出行的人', example: 'The traveller has a bag.', category: 'people', zone: 'terminal_zone' },
    { id: 'security_officer', word: 'security officer', phonetic: '/sɪˈkjʊrəti ˈɔːfɪsər/', zh: '安检员', kidDefinition: '检查行李和身体的人', example: 'The security officer checks bags.', category: 'people', zone: 'terminal_zone' },
    { id: 'baggage_handler', word: 'baggage handler', phonetic: '/ˈbæɡɪdʒ ˈhændlər/', zh: '行李搬运工', kidDefinition: '搬运行李的地勤人员', example: 'The handler lifts the suitcase.', category: 'people', zone: 'apron_zone' },

    { id: 'windsock', word: 'windsock', phonetic: '/ˈwɪndsɑːk/', zh: '风向袋', kidDefinition: '看风往哪吹的布筒', example: 'The windsock shows the wind.', category: 'facilities', zone: 'runway_zone' },
    { id: 'radar', word: 'radar', phonetic: '/ˈreɪdɑːr/', zh: '雷达', kidDefinition: '看飞机在哪的圆盘', example: 'The radar finds the planes.', category: 'facilities', zone: 'runway_zone' },
    { id: 'beacon', word: 'beacon', phonetic: '/ˈbiːkən/', zh: '机场灯塔', kidDefinition: '晚上一闪一闪的灯', example: 'The beacon flashes at night.', category: 'facilities', zone: 'runway_zone' },
    { id: 'runway_lights', word: 'runway lights', phonetic: '/ˈrʌnweɪ laɪts/', zh: '跑道灯', kidDefinition: '照亮跑道的小灯', example: 'The runway lights shine.', category: 'facilities', zone: 'runway_zone' },
    { id: 'papi', word: 'PAPI', phonetic: '/ˈpæpi/', zh: '下滑指示灯', kidDefinition: '告诉飞机飞得高不高的灯', example: 'The PAPI guides the plane down.', category: 'facilities', zone: 'runway_zone' },
    { id: 'sign', word: 'sign', phonetic: '/saɪn/', zh: '指示牌', kidDefinition: '写着方向的牌子', example: 'The sign shows the way.', category: 'facilities', zone: 'terminal_zone' },
    { id: 'fuel_tank', word: 'fuel tank', phonetic: '/ˈfjuːəl tæŋk/', zh: '储油罐', kidDefinition: '存飞机燃油的大罐子', example: 'Fuel is kept in the tank.', category: 'facilities', zone: 'hangar_zone' },
    { id: 'floodlight', word: 'floodlight', phonetic: '/ˈflʌdlaɪt/', zh: '探照灯', kidDefinition: '把停机坪照亮的大灯', example: 'The floodlight lights the apron.', category: 'facilities', zone: 'apron_zone' },
    { id: 'passport_control', word: 'passport control', phonetic: '/ˈpæspɔːrt kənˈtroʊl/', zh: '护照查验', kidDefinition: '检查护照的小窗口', example: 'We show our passport here.', category: 'facilities', zone: 'terminal_zone' },
    { id: 'x_ray', word: 'X-ray machine', phonetic: '/ˈeks reɪ məˈʃiːn/', zh: 'X 光机', kidDefinition: '检查行李里面的大机器', example: 'The X-ray sees inside bags.', category: 'facilities', zone: 'terminal_zone' },
    { id: 'departures_board', word: 'departures board', phonetic: '/dɪˈpɑːrtʃərz bɔːrd/', zh: '航班信息屏', kidDefinition: '显示飞机几点走的大屏', example: 'The board shows our flight.', category: 'facilities', zone: 'terminal_zone' },
    { id: 'moving_walkway', word: 'moving walkway', phonetic: '/ˈmuːvɪŋ ˈwɔːkweɪ/', zh: '自动步道', kidDefinition: '自己会走的平路', example: 'We ride the moving walkway.', category: 'facilities', zone: 'terminal_zone' },
    { id: 'escalator', word: 'escalator', phonetic: '/ˈeskəleɪtər/', zh: '自动扶梯', kidDefinition: '自己会上下的楼梯', example: 'We take the escalator up.', category: 'facilities', zone: 'terminal_zone' }
  ];

  var byId = {};
  for (var i = 0; i < objects.length; i++) {
    byId[objects[i].id] = objects[i];
  }

  global.AirportData = { objects: objects, byId: byId };
})(typeof window !== 'undefined' ? window : globalThis);
