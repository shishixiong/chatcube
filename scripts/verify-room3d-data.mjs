import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const root = process.cwd();
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');
const sandbox = { window: {} };
vm.runInNewContext(
  read('entry/src/main/resources/rawfile/room3d/assets/scene-data.js'),
  sandbox,
  { filename: 'scene-data.js' }
);
const data = sandbox.window.WordRoomData;
const balconyIds = [
  'washing_machine', 'dryer', 'laundry_basket', 'drying_rack', 'clothespin',
  'laundry_sink', 'storage_cabinet', 'broom', 'mop', 'bucket',
  'balcony_plant', 'flower_pot', 'watering_can', 'railing', 'folding_stool'
];

assert.equal(data.objects.length, 76);
assert.deepEqual([...data.roomOrder], ['main', 'child', 'master', 'balcony']);
assert.equal(new Set(data.objects.map((o) => o.id)).size, 76);
assert.equal(data.objects.filter((o) => o.room === 'main').length, 37);
assert.equal(data.objects.filter((o) => o.room === 'child').length, 12);
assert.equal(data.objects.filter((o) => o.room === 'master').length, 12);
assert.equal(data.objects.filter((o) => o.room === 'balcony').length, 15);
assert.deepEqual(
  [...data.objects.filter((o) => o.room === 'balcony').map((o) => o.id)],
  balconyIds
);
for (const item of data.objects) {
  assert.ok(item.word && item.phonetic && item.zh && item.kidDefinition && item.example, item.id);
  assert.ok(item.kidDefinition.length <= 20, `${item.id}: ${item.kidDefinition.length}`);
  assert.ok(data.roomOrder.includes(item.room), item.id);
  assert.ok(data.categories[item.category], item.category);
}
for (const [id, meta] of Object.entries(data.categories)) {
  assert.equal(data.objects.filter((o) => o.category === id).length, meta.count, id);
}
assert.equal(data.rooms.overview.tab, '全屋');
assert.equal(data.rooms.overview.heading, '全屋 3D 探索');
assert.equal(data.rooms.overview.size, '16.8m × 8.9m');
assert.equal(data.categories.balcony.room, 'balcony');
console.log('room3d data OK: 76 objects / 4 rooms / 15 balcony');

const modelSource = read('entry/src/main/resources/rawfile/room3d/assets/room-models.js');
const modeled = new Set(
  [...modelSource.matchAll(/(?:objectGroup|objectMeta)\('([a-z_]+)'/g)].map((m) => m[1])
);
assert.equal(modeled.size, 76);
for (const item of data.objects) assert.ok(modeled.has(item.id), `no model for ${item.id}`);
assert.match(modelSource, /buildBalcony/);
assert.match(modelSource, /balcony:\s*\{\s*x:\s*-0\.89,\s*z:\s*4\.39\s*\}/);
console.log('room3d model parity OK: 76 models');

// 客餐厅多取景中心 + 卧室门洞：纯数据模块，Node 可直接加载并做几何回归。
const layoutSandbox = { window: {} };
vm.runInNewContext(
  read('entry/src/main/resources/rawfile/room3d/assets/room-layout.js'),
  layoutSandbox,
  { filename: 'room-layout.js' }
);
const layout = layoutSandbox.window.WordRoomLayout;
assert.ok(layout && layout.areas && layout.doors, 'room-layout.js must export WordRoomLayout.areas/.doors');

const roomBounds = { minX: -4.19, maxX: 7.65, minZ: -3.19, maxZ: 3.19 };
const areaIds = ['living', 'dining', 'kitchen'];
assert.deepEqual(Object.keys(layout.areas).sort(), areaIds.slice().sort());
for (const id of areaIds) {
  const area = layout.areas[id];
  assert.ok(area.label, `${id} needs a label`);
  assert.ok(area.target.x > roomBounds.minX && area.target.x < roomBounds.maxX, `${id}.target.x outside main room`);
  assert.ok(area.target.z > roomBounds.minZ && area.target.z < roomBounds.maxZ, `${id}.target.z outside main room`);
  assert.ok(area.radius >= 5 && area.radius <= 12, `${id}.radius out of range: ${area.radius}`);
}
assert.ok(layout.areas.living.target.x < 0, 'living center must sit in the west living zone');
assert.ok(layout.areas.dining.target.x > 1 && layout.areas.dining.target.x < 3.5, 'dining center must sit at the table');
assert.ok(layout.areas.kitchen.target.x > 4.5, 'kitchen center must sit in the east kitchen');

// 西墙家具占位：门洞必须落在两件家具之间的空墙段。
// 儿童房：衣柜 z -1.725..-1.175，书柜 z 0.29..1.61；主卧：衣帽柜 -1.7..-0.5，斗柜 0.45..1.15。
const doorClear = { child: { lo: -1.175, hi: 0.29 }, master: { lo: -0.5, hi: 0.45 } };
const roomOffsetZ = { child: -1.19, master: 2.81 };
for (const roomId of ['child', 'master']) {
  const door = layout.doors[roomId];
  assert.ok(door, `${roomId} door spec missing`);
  assert.ok(door.z1 > door.z0, `${roomId} door z0/z1 inverted`);
  const width = door.z1 - door.z0;
  assert.ok(width >= 0.78 && width <= 1.0, `${roomId} door width out of range: ${width}`);
  assert.ok(door.height >= 1.95 && door.height <= 2.15, `${roomId} door height out of range: ${door.height}`);
  assert.ok(door.open > 1.1 && door.open < 1.6, `${roomId} door open angle out of range: ${door.open}`);
  const clear = doorClear[roomId];
  assert.ok(door.z0 >= clear.lo && door.z1 <= clear.hi,
    `${roomId} door overlaps west-wall furniture: ${door.z0}..${door.z1} vs ${clear.lo}..${clear.hi}`);
  const worldZ0 = roomOffsetZ[roomId] + door.z0;
  const worldZ1 = roomOffsetZ[roomId] + door.z1;
  assert.ok(worldZ0 > roomBounds.minZ && worldZ1 < roomBounds.maxZ, `${roomId} door outside the main room span`);
}

assert.ok(modelSource.includes('LAYOUT.doors.child') && modelSource.includes('LAYOUT.doors.master'),
  'bedroomShell must receive the door specs');
assert.match(modelSource, /areas:\s*LAYOUT\.areas/);

// 阳台：收纳柜必须离开洗衣机/烘干机的正前方（相机从南侧看进来）。
const cabinetMatch = modelSource.match(/objectGroup\('storage_cabinet',\s*(-?[\d.]+),\s*FLOOR_Y,\s*(-?[\d.]+)/);
assert.ok(cabinetMatch, 'storage_cabinet model missing');
assert.ok(Number(cabinetMatch[1]) <= -2.5, `storage_cabinet must move to the west end, x=${cabinetMatch[1]}`);
assert.ok(Number(cabinetMatch[2]) > -0.6 && Number(cabinetMatch[2]) < 0.2, `storage_cabinet z=${cabinetMatch[2]}`);
// 主卧西墙家具必须南移，给门洞让出墙面。
const dresserMatch = modelSource.match(/objectGroup\('dresser',\s*(-?[\d.]+),\s*FLOOR_Y,\s*(-?[\d.]+)/);
assert.ok(dresserMatch && Number(dresserMatch[2]) >= 0.7, `dresser must shift south, z=${dresserMatch && dresserMatch[2]}`);
const photoMatch = modelSource.match(/objectGroup\('photo_frame',\s*(-?[\d.]+),\s*FLOOR_Y\s*\+\s*0\.99,\s*(-?[\d.]+)/);
assert.ok(photoMatch && Number(photoMatch[2]) >= 0.6, `photo_frame must shift south, z=${photoMatch && photoMatch[2]}`);
console.log('room3d layout OK: 3 area centers + 2 bedroom doors + balcony cabinet clear');

const validation = read('entry/src/main/ets/utils/RoomEnglishValidation.ets');
const card = read('entry/src/main/ets/components/room/RoomEnglishCard.ets');
const builtin = read('entry/src/main/ets/config/BuiltinTools.ets');
const html = read('entry/src/main/resources/rawfile/room3d/index.html');

for (const item of data.objects) {
  assert.ok(validation.includes(`'${item.id}'`), `validation missing ${item.id}`);
  assert.ok(builtin.includes(item.id), `schema missing ${item.id}`);
}
assert.ok(validation.includes("'balcony'"));
assert.match(card, /ROOM_OBJECT_TOTAL:\s*number\s*=\s*76/);
assert.match(validation, /export function resolveRoomEnglishView/);
assert.equal((html.match(/class="room-tab(?:\s|")/g) || []).length, 5);
assert.equal((html.match(/class="room-stat"/g) || []).length, 4);
assert.ok(!/data-total>61</.test(html));
console.log('room3d native/page parity OK');

// 客餐厅区域镜头：页面 chip + 场景 API + 原生 focus 映射三层都要接上。
assert.ok(html.includes('id="areaTabs"'), 'index.html missing #areaTabs');
assert.equal((html.match(/class="area-tab"/g) || []).length, 3);
assert.equal((html.match(/data-area="(living|dining|kitchen)"/g) || []).length, 3);
assert.ok(
  html.indexOf('assets/room-layout.js') > -1 &&
    html.indexOf('assets/room-layout.js') < html.indexOf('assets/room-models.js'),
  'index.html must load room-layout.js before room-models.js'
);
const app = read('entry/src/main/resources/rawfile/room3d/assets/room-app.js');
const scene = read('entry/src/main/resources/rawfile/room3d/assets/room-scene.js');
assert.match(scene, /focusArea\(areaId\)/, 'room-scene.js missing RoomExperience.focusArea');
assert.match(scene, /this\.frame\.areas/, 'focusArea must read frame.areas');
assert.match(app, /function setActiveArea/, 'room-app.js missing setActiveArea');
assert.match(app, /dom\.areaTabs/, 'room-app.js must wire #areaTabs');
assert.match(app, /setArea:\s*function/, 'WordRoomApp.setArea missing');
assert.match(validation, /export function resolveRoomEnglishArea/, 'native validation missing resolveRoomEnglishArea');
assert.match(card, /resolveRoomEnglishArea/, 'RoomEnglishCard must map focus to an area');
assert.match(card, /app\.setArea/, 'RoomEnglishCard must call WordRoomApp.setArea');
assert.ok(
  read('entry/src/ohosTest/ets/test/utils/RoomEnglishValidation.test.ets').includes('resolveRoomEnglishArea'),
  'hypium test missing resolveRoomEnglishArea coverage'
);
console.log('room3d area focus wiring OK');

// 近侧墙迟滞：相机停在迟滞带内不能来回翻转，扫过时每个方向只切换一次。
const wallsSandbox = { window: {} };
vm.runInNewContext(
  read('entry/src/main/resources/rawfile/room3d/assets/wall-culling.js'),
  wallsSandbox,
  { filename: 'wall-culling.js' }
);
const walls = wallsSandbox.window.WordRoomWalls;
assert.ok(walls && typeof walls.nextWallHidden === 'function', 'wall-culling.js missing WordRoomWalls.nextWallHidden');

for (let z = -0.8; z <= 0.0001; z += 0.01) {
  let hidden = walls.nextWallHidden(z, 0, false);
  for (let i = 0; i < 20; i++) {
    const next = walls.nextWallHidden(z, 0, hidden);
    assert.equal(next, hidden, `wall state oscillates at z=${z.toFixed(2)}`);
    hidden = next;
  }
}

let hidden = false;
let flips = 0;
for (let z = 0; z <= 1.0001; z += 0.01) {
  const next = walls.nextWallHidden(-z, 0, hidden);
  if (next !== hidden) flips++;
  hidden = next;
}
assert.equal(flips, 1, `forward sweep should hide exactly once, got ${flips}`);
flips = 0;
for (let z = 1; z >= -0.0001; z -= 0.01) {
  const next = walls.nextWallHidden(-z, 0, hidden);
  if (next !== hidden) flips++;
  hidden = next;
}
assert.equal(flips, 1, `round trip should toggle exactly once per direction, got ${flips}`);

assert.ok(
  html.indexOf('assets/wall-culling.js') > -1 &&
    html.indexOf('assets/wall-culling.js') < html.indexOf('assets/room-scene.js'),
  'index.html must load wall-culling.js before room-scene.js'
);
assert.match(scene, /window\.WordRoomWalls\.nextWallHidden\(cam\.z, centerZ, state\.north\)/);
assert.match(scene, /window\.WordRoomWalls\.nextWallHidden\(cam\.x, centerX, state\.west\)/);
assert.ok(!/state\.(north|west) \? 0\.5 : 0\.3/.test(scene), 'inline inverted hysteresis must be gone');
console.log('room3d wall culling OK: hysteresis stable, one transition per direction');
