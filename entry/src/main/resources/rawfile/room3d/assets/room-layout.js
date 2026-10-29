/*
 * 户型级纯数据：客餐厅分区域取景中心 + 卧室门洞。
 *
 * 单独成文件的原因：room-models.js 依赖 THREE，Node 里没法直接加载；
 * 这两组数据只是常量，抽出来后 scripts/verify-room3d-data.mjs 可以直接跑几何回归
 * （取景中心落在客餐厅里、门洞落在西墙家具之间的空段、门洞宽度/高度合理）。
 *
 * 坐标约定：
 *  - areas：世界坐标（客餐厅 group 就在原点，所以等于局部坐标）。
 *  - doors：卧室房间的局部 z 区间（房间中心 = 0，北墙在 -hd）；世界 z = ROOM_OFFSETS[room].z + 局部 z。
 */
(function (global) {
  'use strict';

  // 客餐厅一条东西向的开放空间：西侧客厅（沙发/电视/书架）、中部餐厅、东侧开放厨房。
  // target 是镜头环绕中心，radius 是俯视距离；实际值会被 room-scene 的 zoomRange() 夹紧。
  var MAIN_AREAS = {
    living: {
      label: '客厅',
      target: { x: -1.9, y: 0.9, z: -0.05 },
      radius: 6.9
    },
    dining: {
      label: '餐厅',
      target: { x: 2.2, y: 0.95, z: -0.15 },
      radius: 5.9
    },
    kitchen: {
      label: '厨房',
      target: { x: 6.1, y: 0.95, z: -1.3 },
      radius: 6.4
    }
  };

  // 卧室西墙开口（儿童房/主卧与客餐厅之间的共享墙）。
  // 门洞避开西墙家具：儿童房在衣柜(-1.725..-1.175)与书柜(0.29..1.61)之间；
  // 主卧在衣帽柜(-1.7..-0.5)与南移后的斗柜(0.45..1.15)之间。
  var ROOM_DOORS = {
    child: { z0: -0.89, z1: -0.01, height: 2.05, open: 1.42 },
    master: { z0: -0.46, z1: 0.34, height: 2.05, open: 1.42 }
  };

  global.WordRoomLayout = { areas: MAIN_AREAS, doors: ROOM_DOORS };
})(typeof window !== 'undefined' ? window : globalThis);
