# 小词屋 3D v3（全屋视图 + 360° 环绕 + 生活阳台）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把小词屋从「三间房轮播」升级为默认全屋户型视图，加入 360° 环绕、跟手相机、自动藏墙，并扩建一间生活阳台，单词总数 61 → 76。

**Architecture:** 四组 `THREE.Group` 在同一个世界坐标系按真实户型摆放，`overview` 视图同时显示全部；单间视图只显示对应组。相机改为单层球坐标阻尼 + 松手惯性；每帧按相机相对各房间世界中心的位置隐藏近侧北/西墙。数据层（`scene-data.js`）仍是唯一词表来源，原生校验/schema 与 Web 数据用脚本锁步。

**Tech Stack:** HarmonyOS 6 / ArkTS 6 / ArkWeb、three.js 0.185（本地 vendor）、原生 HTML/CSS/JS、hypium。

**Spec:** `docs/superpowers/specs/2026-10-29-room3d-overview-balcony-design.md`

## Global Constraints

- 单词总数 **76**：客厅 15 + 餐厅 10 + 厨房 12 + 儿童房 12 + 主卧 12 + 阳台 15。
- 视图顺序固定为 **全屋 / 客餐厅 / 儿童房 / 主卧 / 阳台**，默认 **全屋（overview）**。
- 全屋模式下英文标签开关禁用；任何单词卡序号在全屋按 **76**、单间按该房间数量。
- 全屋点物品只开单词卡，不切换视图；切到单间后沿用现有「点另一间房的词就切过去」行为。
- 阳台 15 个 id 固定为：`washing_machine / dryer / laundry_basket / drying_rack / clothespin / laundry_sink / storage_cabinet / broom / mop / bucket / balcony_plant / flower_pot / watering_can / railing / folding_stool`。
- 不新增第三方依赖、不使用网络资源或外部贴图；全部程序化几何 + canvas 纹理。
- 既有 61 件物品的 id、单词卡内容、发音行为不得改变。
- 所有 `rawfile/room3d/assets/*.js` 必须通过 `node --check`；最终 `hvigorw assembleHap` 通过。
- ArkTS 严格模式：不用解构、对象字面量显式类型；`BuiltinTools.ets` 的 rawSchemaJson 内新增描述不得含 ASCII 双引号（用「」）。

## Review Focus

- **360° 转到任意房间的北/西侧**：只隐藏该房间近侧墙，东翼两间房用各自世界中心判断；来回越过阈值不闪烁，另一间房的墙不受影响。
- **墙已隐藏时从词汇表选中 `window` / `curtain`**：必须强制显示所在墙并保持可点、可朗读；取消选中后墙恢复自动隐藏，标签不悬空。
- **全屋视图点物品或词汇表**：镜头必须留在全屋，单词卡序号按 76 遍历；只有单间模式才因跨房间选词而切房。
- **AI focus 无 words**：`focus:"living"` 必须切主屋；`all` / 缺省 / 无效才停在全屋；`balcony` 直接切阳台。
- **窄屏 5 个标签 + 4 个统计卡**：390×844 下标签不溢出、不换行，4 个统计卡可读，全屋画面完整不裁切。

---

### Task 1: 数据层与数据不变量检查器

**Files:**
- Create: `scripts/verify-room3d-data.mjs`
- Modify: `entry/src/main/resources/rawfile/room3d/assets/scene-data.js`
- Modify: `entry/src/main/resources/rawfile/room3d/assets/room-app.js`（仅 `CATEGORY_ORDER` 加 `'balcony'`，让页面在新数据下仍能启动）

**Interfaces:**
- Consumes: 无。
- Produces: `window.WordRoomData.rooms.overview`（`zh/tab/eyebrow/heading/size/note`）、`rooms.balcony`、`roomOrder = ['main','child','master','balcony']`、`categories.balcony`、76 个 `objects`（阳台 15 个 `room:'balcony', category:'balcony'`）。检查器导出无模块 API，仅 `process.exit(1)` 失败。

- [ ] **Step 1: 写失败的数据检查器**

创建 `scripts/verify-room3d-data.mjs`，用 Node `vm` 加载 IIFE 数据文件并断言：

```js
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
assert.deepEqual(data.roomOrder, ['main', 'child', 'master', 'balcony']);
assert.equal(new Set(data.objects.map((o) => o.id)).size, 76);
assert.equal(data.objects.filter((o) => o.room === 'main').length, 37);
assert.equal(data.objects.filter((o) => o.room === 'child').length, 12);
assert.equal(data.objects.filter((o) => o.room === 'master').length, 12);
assert.equal(data.objects.filter((o) => o.room === 'balcony').length, 15);
assert.deepEqual(
  data.objects.filter((o) => o.room === 'balcony').map((o) => o.id),
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
```

- [ ] **Step 2: 运行检查器，确认按预期失败**

Run: `node scripts/verify-room3d-data.mjs`
Expected: FAIL，`actual 61`（或首个 count 断言失败）。

- [ ] **Step 3: 在 `scene-data.js` 追加阳台与 overview 数据**

按 spec §4.4 的表格把 15 个对象追加到 `objects` 数组末尾（字段顺序与既有对象一致，`category` 均为 `'balcony'`，`labelBias` 给合理小偏移如 `[0, 18]`）。然后：

- `ROOM_BY_CATEGORY` 加 `balcony: 'balcony'`。
- `rooms` 增加：

```js
overview: {
  zh: '全屋',
  tab: '全屋',
  eyebrow: '我的家 · 3D 户型',
  heading: '全屋 3D 探索',
  size: '16.8m × 8.9m',
  note: '四间房加一个生活阳台，先看看整个家的样子。'
},
balcony: {
  zh: '阳台',
  tab: '阳台',
  eyebrow: '阳台 · 3D 场景',
  heading: '生活阳台英语探索',
  size: '6.6m × 2.4m',
  note: '洗衣机、晾衣架和清洁工具都在阳台，一共 15 件东西可以点。'
}
```

- `roomOrder` 改为 `['main', 'child', 'master', 'balcony']`（overview 不是 room，不放入）。
- `categories` 加 `balcony: { zh: '阳台', en: 'BALCONY', count: countOf('balcony'), room: 'balcony' }`。
- `room-app.js` 的 `CATEGORY_ORDER` 追加 `'balcony'`（否则 `validateData` 会把阳台对象判成未知分类）。
- `title` 改为 `'全屋 · 客餐厅 · 厨房 · 儿童房 · 主卧 · 阳台英语探索'`。

- [ ] **Step 4: 重新运行检查器**

Run: `node scripts/verify-room3d-data.mjs`
Expected: `room3d data OK: 76 objects / 4 rooms / 15 balcony`

- [ ] **Step 5: 语法检查并提交**

```bash
node --check entry/src/main/resources/rawfile/room3d/assets/scene-data.js
node scripts/verify-room3d-data.mjs
git add scripts/verify-room3d-data.mjs \
  entry/src/main/resources/rawfile/room3d/assets/scene-data.js \
  entry/src/main/resources/rawfile/room3d/assets/room-app.js
git commit -m "feat(room3d): add balcony word data and whole-home metadata"
```

---

### Task 2: 阳台几何、房间偏移、世界取景与墙体标记

**Files:**
- Modify: `entry/src/main/resources/rawfile/room3d/assets/room-models.js`
- Modify: `scripts/verify-room3d-data.mjs`

**Interfaces:**
- Consumes: Task 1 的 15 个阳台 id 与 `room:'balcony'`。
- Produces:
  - `window.WordRoomModels.buildBalcony(root) -> { objects: THREE.Group[], hitboxes: THREE.Mesh[] }`（恰好 15 个 object group）。
  - `window.WordRoomModels.offsets = { main:{x:0,z:0}, child:{x:10.01,z:-1.19}, master:{x:10.11,z:2.81}, balcony:{x:-0.89,z:4.39} }`。
  - `window.WordRoomModels.rooms` 全部为**世界坐标**，含 `main/child/master/balcony/overview`。
  - 所有实体墙 mesh 及挂墙物品的 `userData.wallSide` 为 `'north'|'west'`；可点挂墙 group 另带 `userData.wallSide` 且保留 `interactive/objectId`。

- [ ] **Step 1: 先扩展检查器，锁定模型与数据一一对应**

在 `scripts/verify-room3d-data.mjs` 末尾追加：

```js
const modelSource = read('entry/src/main/resources/rawfile/room3d/assets/room-models.js');
const modeled = new Set(
  [...modelSource.matchAll(/(?:objectGroup|objectMeta)\('([a-z_]+)'/g)].map((m) => m[1])
);
assert.equal(modeled.size, 76);
for (const item of data.objects) assert.ok(modeled.has(item.id), `no model for ${item.id}`);
assert.match(modelSource, /buildBalcony/);
assert.match(modelSource, /balcony:\s*\{\s*x:\s*-0\.89,\s*z:\s*4\.39\s*\}/);
console.log('room3d model parity OK: 76 models');
```

Run: `node scripts/verify-room3d-data.mjs`
Expected: FAIL，`no model for washing_machine`（或 `modeled.size` 为 61）。

- [ ] **Step 2: 修主屋地板东缘**

把 `buildRoomShell` 的 15 条地板改成等距铺满 `-3.995 .. 7.63`，不再固定 `w=0.795 / step=0.8`（现有最西一条中心 `x=-3.6`、宽 0.795 → 西缘正是 `-3.995`，**西缘不能动**，只收东缘）：

```js
const floorStart = -3.995;
const floorEnd = ROOM.maxX - 0.02; // 7.63
const step = (floorEnd - floorStart) / 15;
for (let i = 0; i < 15; i += 1) {
  const x = floorStart + step / 2 + i * step;
  // BoxGeometry(step - 0.005, 0.036, 5.92)，x 用上面的值
}
```

验收：最西一块左缘仍 ≈ -3.995，最东一块右缘 ≈ 7.63（原为 ≈ 8.00），落在 base 东缘 7.68 以内，不会和东翼地板共面。

- [ ] **Step 3: 给现有墙体与挂墙物品打 `wallSide`**

在 `room-models.js` 加小工具：

```js
function wallSide(mesh, side) {
  mesh.userData.wallSide = side;
  return mesh;
}
```

标记范围（只标实体/挂墙件，不标家具）：

- 主屋 `buildRoomShell`：北墙 5 段、北踢脚线、北护墙板条/压条/竖向分缝、北门套线 → `'north'`；西墙、西踢脚线 → `'west'`。
- `buildKitchenShell`：北侧台面后挡墙、墙砖、竖向砖缝、微波炉搁板 → `'north'`。
- `buildWindowAndCurtain`：`windowGroup.userData.wallSide = 'north'`、`curtainGroup.userData.wallSide = 'north'`。
- `bedroomShell`：北墙四段、窗台、玻璃、竖梃、北踢脚线、窗帘杆、两片窗帘 → `'north'`；西墙、西踢脚线 → `'west'`。

不要给 `tv / tv_stand / picture / clock / cabinet / air_conditioner` 等家具打标记——本版只让 spec 明确的窗/窗帘与墙体联动，避免扩大行为面。

- [ ] **Step 4: 新增 `buildBalcony(root)` 与 15 件家具**

在 `buildBedrooms` 前新增函数，使用现有 `box/cylinder/addMesh/objectGroup/hit/material` 工具。几何要点：

- 局部坐标以阳台中心为原点，尺寸 6.6m（x）× 2.4m（z），`FLOOR_Y = 0.03`。
- base：`6.9 × 0.28 × 2.58`，局部中心 `(0, -0.142, 0.06)`（比主屋 base 低 2mm，避免北缘共面）。
- 地砖：512×512 canvas 纹理（浅灰底、深灰砖缝、少量噪点），铺 `6.6 × 0.036 × 2.4` 于 `y = FLOOR_Y - 0.018`。
- 北侧玻璃推拉门：局部 `z = -1.2`，通高 2.2m，两扇各约 3.15m 宽，细金属框 + `RGB.glass` 半透明玻璃，上下轨道；不参与点击、不参与藏墙。
- 南/东/西三侧栏杆高 1.1m：立柱 + 上下横杆，材质 `RGB.steel`；东侧中段加 `1.2m × 1.8m` 矮墙（`RGB.wall`）。
- 家具 group 的 `objectGroup(id, x, FLOOR_Y, z, root)` 建议位置（局部坐标；可微调但不能越界 ±3.3 / ±1.2，也不能互相穿模）：

| id | 位置 (x,z) | 造型要点 |
|----|-----------|----------|
| `washing_machine` | (2.72, -0.72) | 0.62×0.9×0.62 白色机身 + 圆形门 + 顶部旋钮 |
| `dryer` | (2.72, -0.72) | 同 x/z，机身叠在洗衣机上方，离地 0.98 |
| `storage_cabinet` | (2.80, 0.10) | 0.52×1.7×0.5 窄高柜，两扇门 + 把手 |
| `laundry_sink` | (2.55, 0.62) | 0.55×0.85×0.5 柱盆 + 水龙头 |
| `drying_rack` | (0.55, 0.25) | 1.4×1.35×0.6 A 字架 + 多根横杆 |
| `laundry_basket` | (1.65, 0.75) | 直径 0.42、高 0.45 的圆柱篮 + 提手 |
| `clothespin` | (1.62, 0.55)，`y=FLOOR_Y+0.68` | 篮沿/架上的小木夹，hitbox ≥0.18m |
| `folding_stool` | (0.95, 0.85) | 0.38×0.42×0.38 折叠凳 |
| `broom` | (-3.15, 0.40) | 长柄 + 斜刷头 |
| `mop` | (-2.65, 0.50) | 长柄 + 圆盘拖布 |
| `bucket` | (-2.25, 0.80) | 直径 0.36、高 0.4 圆桶 |
| `balcony_plant` | (-2.70, -0.75) | 陶盆 + 5–7 片低多边形叶子 |
| `flower_pot` | (-1.70, -0.80) | 小陶盆 + 土面 |
| `watering_can` | (-1.55, 0.65) | 壶身 + 长嘴 + 提手 |
| `railing` | (0, 0.00) | 整个南/东/西栏杆组；hitbox 覆盖南侧长条，高度到 1.1m |

每件家具都要 `objects.push(g)` 并至少一个 `hit(g, id, ...)`，最后：

```js
if (objects.length !== 15) throw new Error('阳台应该有 15 件可点物品，实际 ' + objects.length);
return { objects, hitboxes };
```

- [ ] **Step 5: 加房间偏移，世界化 frames，导出新接口**

在 `ROOM_FRAMES` 前定义：

```js
const ROOM_OFFSETS = {
  main: { x: 0, z: 0 },
  child: { x: 10.01, z: -1.19 },
  master: { x: 10.11, z: 2.81 },
  balcony: { x: -0.89, z: 4.39 }
};
```

把 `child/master` 的 `bounds/target` 全部加上各自偏移；新增：

```js
balcony: {
  bounds: { minX: -4.19, maxX: 2.41, minZ: 3.19, maxZ: 5.59,
    centerX: -0.89, centerZ: 4.39, halfWidth: 3.3, halfDepth: 1.2 },
  target: { x: -0.89, y: 0.8, z: 4.39 },
  fitMin: 4.5, fitMax: 13.5, zoomMin: 2.4,
  panInsetX: 0.9, panInsetZ: 0.45, fitScale: 1
},
overview: {
  bounds: { minX: -4.36, maxX: 12.58, minZ: -3.19, maxZ: 5.76,
    centerX: 4.11, centerZ: 1.285, halfWidth: 8.47, halfDepth: 4.475 },
  target: { x: 4.1, y: 0.7, z: 1.3 },
  fitMin: 16, fitMax: 48, zoomMin: 8,
  panInsetX: 1.2, panInsetZ: 0.8, fitScale: 1
}
```

- child target：`{ x: 10.06, y: 0.78, z: -1.17 }`；master target：`{ x: 10.16, y: 0.78, z: 2.83 }`。
- 阳台 `fitMax: 13.5` 是竖屏手机的下限：`fitRadius()` 用 `halfWidth/(tan(fov/2)*aspect)*1.13`，390×844 的 3D 舞台 aspect≈0.76、fov 44° → 需要 ≈12.2 才不裁掉 6.6m 面宽（spec 原写 9 只够桌面横屏）；`fitMax` 同时是最大拉远距离，放宽后桌面上限也不受影响（桌面初始 fit≈6.8 仍由 `fitMin` 决定）。

导出改为：

```js
window.WordRoomModels = {
  buildRoom,
  buildBedrooms,
  buildBalcony,
  FLOOR_Y,
  rooms: ROOM_FRAMES,
  offsets: ROOM_OFFSETS,
  bounds: ROOM_FRAMES.main.bounds
};
```

- [ ] **Step 6: 运行检查器 + 语法检查**

Run:
```bash
node --check entry/src/main/resources/rawfile/room3d/assets/room-models.js
node scripts/verify-room3d-data.mjs
```
Expected: `room3d data OK...` 与 `room3d model parity OK: 76 models`。

- [ ] **Step 7: 提交**

```bash
git add entry/src/main/resources/rawfile/room3d/assets/room-models.js scripts/verify-room3d-data.mjs
git commit -m "feat(room3d): build balcony geometry, world frames and wall tags"
```

---

### Task 3: 场景组装——四组同世界摆放 + 全屋可见

**Files:**
- Modify: `entry/src/main/resources/rawfile/room3d/assets/room-scene.js`
- Modify: `entry/src/main/resources/rawfile/room3d/assets/room-app.js`（仅 `VIEW_ORDER` / `objectsInRoom` 最小接线）

**Interfaces:**
- Consumes: Task 2 的 `WordRoomModels.offsets / rooms / buildBalcony`。
- Produces:
  - `RoomExperience.setRoom('overview'|'main'|'child'|'master'|'balcony')`。
  - `this.roomGroups` 含四间房；`this.roomObjects.overview` / `this.roomHitboxes.overview` 为全部汇总。
  - `room-app` 的 `VIEW_ORDER = ['overview','main','child','master','balcony']`，`WordRoomApp.setRoom('overview')` 可用于验收。

- [ ] **Step 1: 改场景构造与四组摆放**

`DEFAULT_ROOM` 改为 `'overview'`；`FALLBACK_FRAME` 保留。构造时：

- `this.activeRoom = 'overview'; this.frame = frameOf('overview');`
- `createRoomGroup` 四组全部 `visible = true`。
- build：
  ```js
  const builtMain = models.buildRoom(mainGroup);
  const builtBeds = models.buildBedrooms(childGroup, masterGroup);
  const builtBalcony = models.buildBalcony(balconyGroup);
  ```
- 应用组偏移：
  ```js
  Object.keys(models.offsets).forEach((id) => {
    const off = models.offsets[id];
    this.roomGroups[id].position.set(off.x, 0, off.z);
  });
  ```
- `roomObjects/ balcony`、`roomHitboxes/balcony` 从 `builtBalcony` 填充；`overview` 为四组 concat。
- `this.objects` 为全部 76；`this.hitboxes = this.roomHitboxes.overview`。
- 相机 `far` 从 60 改为 **120**。

- [ ] **Step 2: 实现 overview 的 `setRoom` 与阴影跟随**

```js
setRoom(roomId) {
  const next = roomId === 'overview' || this.roomGroups[roomId] ? roomId : 'overview';
  ...
}
```

- 可见性：`group.visible = next === 'overview' || id === next`。
- `frame = frameOf(next)`；hitboxes 取 `roomHitboxes[next] || []`；target 用新 frame；theta `.79`、phi `.85`、radius `fitRadius()`。
- 清 selection/hover/outline。
- 新增 `updateShadowFrustum()`：
  - 保存 `this.keyLight = key`。
  - 光源方向固定：`key.position = target + (6.5, 8.7, 7.5)`（原 `(6.5,9.5,7.5)` 对 `(0,0.8,0)` 的偏移）。
  - `key.target.position.set(frame.target.x, 0.8, frame.target.z)`。
  - `half = max(width, depth) / 2 + 2`；`left=-half/right=half/top=half/bottom=-half`；`near=0.5`；`far=half*2+30`；`updateProjectionMatrix()`。
  - `setRoom` 与初始 `snapCamera` 后调用一次。

- [ ] **Step 3: app 层最小接线**

`room-app.js` 加：

```js
const VIEW_ORDER = ['overview'].concat(ROOM_ORDER);
const objectsInRoom = (roomId) =>
  roomId === 'overview' ? OBJECTS : OBJECTS.filter((item) => item.room === roomId);
```

`setActiveRoom` 的合法集合从 `ROOM_ORDER` 改为 `VIEW_ORDER`。此任务**先不改**默认 `activeRoom`（仍 `'main'`），全屋通过 `WordRoomApp.setRoom('overview')` 验证；Task 6 再切默认值。

- [ ] **Step 4: 启动本地服务并用 headless 浏览器验收**

```bash
python3 -m http.server 8765 --directory entry/src/main/resources/rawfile/room3d
agent-browser set viewport 1280 900
agent-browser open http://127.0.0.1:8765/index.html
agent-browser wait 1500
agent-browser console --clear
agent-browser eval "window.WordRoomApp.setRoom('overview'); 'ok'"
agent-browser wait 800
mkdir -p /tmp/room3d
agent-browser screenshot /tmp/room3d/overview.png
agent-browser eval "window.WordRoomApp.setRoom('balcony'); 'ok'"
agent-browser wait 800
agent-browser screenshot /tmp/room3d/balcony.png
agent-browser errors
```

Expected:
- 截图可见主屋 + 东翼儿童房/主卧 + 南侧阳台；阳台东端洗烘、中段晾衣架、西端清洁/绿植清晰。
- 东翼两间房有阴影；主屋东缘与东翼之间无共面闪烁。
- `agent-browser errors` 无输出。

- [ ] **Step 5: 语法检查并提交**

```bash
node --check entry/src/main/resources/rawfile/room3d/assets/room-scene.js
node --check entry/src/main/resources/rawfile/room3d/assets/room-app.js
git add entry/src/main/resources/rawfile/room3d/assets/room-scene.js \
  entry/src/main/resources/rawfile/room3d/assets/room-app.js
git commit -m "feat(room3d): assemble whole-home floor plan with balcony"
```

---

### Task 4: 360° 相机、单层阻尼与统一手势

**Files:**
- Modify: `entry/src/main/resources/rawfile/room3d/assets/room-scene.js`

**Interfaces:**
- Consumes: Task 3 的 `this.orbit` / `this.desired` / `fitRadius()`。
- Produces: `PHI_MIN = 0.38`、`PHI_MAX = 1.22`；`onFrame(moving: boolean)`；`RoomExperience.drag` 增加 `lastMoveTime`。

- [ ] **Step 1: 常量化垂直限位并解除水平限位**

文件顶部：

```js
const PHI_MIN = 0.38;
const PHI_MAX = 1.22;
```

新增：

```js
function wrapAngle(angle) {
  return Math.atan2(Math.sin(angle), Math.cos(angle));
}
function shortestAngle(delta) {
  return Math.atan2(Math.sin(delta), Math.cos(delta));
}
```

所有 theta 赋值改成 `wrapAngle(...)`；所有 phi 用 `clamp(..., PHI_MIN, PHI_MAX)`。删除 `0.18/1.4/0.64/1.24` 硬编码。

- [ ] **Step 2: 单层阻尼替换双层 lerp**

`animate()` 改为：

```js
const dragging = Boolean(this.drag || this.pinch);
const rate = this.reducedMotion ? 1 : 1 - Math.exp(-dt * (dragging ? 18 : 6));
this.orbit.theta = wrapAngle(this.orbit.theta + shortestAngle(this.desired.theta - this.orbit.theta) * rate);
this.orbit.phi += (this.desired.phi - this.orbit.phi) * rate;
this.orbit.radius += (this.desired.radius - this.orbit.radius) * rate;
this.orbit.target.lerp(this.desired.target, rate);
```

相机位置每帧直接由 `orbit` 计算，`camera.lookAt(this.orbit.target)`；删除 `currentTarget` 与 `camera.position.lerp`。`snapCamera` 同样直接用 `orbit`。

- [ ] **Step 3: 拖拽速度采样与松手惯性**

构造器初始化 `this.spinTheta = 0; this.spinPhi = 0;`，`resetView()` 与 `setRoom()` 也清零；手指按下/进入双指时清零，避免残留惯性。

`handlePointerDown` 的 drag 对象加 `lastMoveTime: performance.now()`；`handlePointerMove` 旋转分支：

```js
const now = performance.now();
const moveDt = Math.max(0.008, (now - this.drag.lastMoveTime) / 1000);
this.drag.lastMoveTime = now;
this.desired.theta = wrapAngle(this.desired.theta - dx * 0.005);
this.desired.phi = clamp(this.desired.phi - dy * 0.0028, PHI_MIN, PHI_MAX);
this.spinTheta = clamp(-dx * 0.005 / moveDt, -3.5, 3.5);
this.spinPhi = clamp(-dy * 0.0028 / moveDt, -2, 2);
```

`handlePointerUp`：若本次确实是旋转拖拽（`moved > 4` 且 `performance.now() - drag.lastMoveTime < 80`），保留 `spinTheta/spinPhi *= 0.55`；否则清零。`handlePointerCancel` 清零。双指退回单指时重建的 drag 对象必须带 `lastMoveTime: performance.now()`、`pan: false`。

`animate()` 开头（无指针、非 reducedMotion）注入：

```js
if (!this.pointers.size && (this.spinTheta || this.spinPhi)) {
  this.desired.theta = wrapAngle(this.desired.theta + this.spinTheta * dt);
  this.desired.phi = clamp(this.desired.phi + this.spinPhi * dt, PHI_MIN, PHI_MAX);
  const decay = Math.exp(-dt * 3.2);
  this.spinTheta *= decay;
  this.spinPhi *= decay;
  if (Math.abs(this.spinTheta) < 0.01 && Math.abs(this.spinPhi) < 0.01) {
    this.spinTheta = 0;
    this.spinPhi = 0;
  }
}
```

- [ ] **Step 4: 手势语义与像素比**

- `handlePointerDown`：鼠标右键或 `Shift + 左键` 记为 `pan: true`；左键/触摸单指记为 `pan: false`；删除 `radius < fit*0.85` 判断。非左键且非右键的鼠标按键直接 return。
- canvas 绑定 `contextmenu` → `preventDefault()`（destroy 时移除）。
- 双指仍为捏合缩放 + 平移。
- 移动端 pixel ratio：`Math.min(dpr, innerWidth < 760 ? 1.4 : 2)`。
- 键盘：左右 `wrapAngle(±step)`，上下 clamp 到 `[PHI_MIN, PHI_MAX]`；`R` 复位。
- 滚轮逻辑不变。

- [ ] **Step 5: onFrame 报告是否仍在移动**

```js
const moving =
  Math.abs(shortestAngle(this.desired.theta - this.orbit.theta)) > 1e-4 ||
  Math.abs(this.desired.phi - this.orbit.phi) > 1e-4 ||
  Math.abs(this.desired.radius - this.orbit.radius) > 1e-4 ||
  this.orbit.target.distanceToSquared(this.desired.target) > 1e-6 ||
  Boolean(this.spinTheta || this.spinPhi);
this.options.onFrame?.(moving);
```

- [ ] **Step 6: 浏览器验收旋转与跟手**

```bash
agent-browser set viewport 1280 900
agent-browser open http://127.0.0.1:8765/index.html
agent-browser wait 1200
agent-browser eval "window.WordRoomApp.setRoom('main'); 'ok'"
agent-browser wait 700
agent-browser mouse move 640 420
agent-browser mouse down
agent-browser mouse move 900 420
agent-browser mouse move 1100 420
agent-browser mouse up
agent-browser wait 900
agent-browser screenshot /tmp/room3d/rotated-1.png
agent-browser mouse move 640 420
agent-browser mouse down
agent-browser mouse move 300 420
agent-browser mouse move 80 420
agent-browser mouse up
agent-browser wait 900
agent-browser screenshot /tmp/room3d/rotated-2.png
agent-browser errors
```

Expected: 连续拖动可越过原 70° 限位，画面无跳变/回弹；两次截图视角明显不同且都能看到室内；无页面错误。

- [ ] **Step 7: 提交**

```bash
node --check entry/src/main/resources/rawfile/room3d/assets/room-scene.js
git add entry/src/main/resources/rawfile/room3d/assets/room-scene.js
git commit -m "feat(room3d): 360-degree orbit with single-layer damping and inertia"
```

---

### Task 5: 近侧墙自动隐藏与挂墙物品联动

**Files:**
- Modify: `entry/src/main/resources/rawfile/room3d/assets/room-scene.js`

**Interfaces:**
- Consumes: Task 2 的 `userData.wallSide`；Task 3 的四组 `roomGroups`；Task 4 的逐帧相机。
- Produces: `this.roomWalls[roomId] = {north: Mesh[], west: Mesh[]}`、`this.wallObjects[roomId] = {group, side}[]`、`this.wallHidden[roomId] = {north, west}`。

- [ ] **Step 1: 收集墙体与挂墙物品**

构造/build 完成后调 `collectWalls()`：

```js
collectWalls() {
  this.roomWalls = {};
  this.wallObjects = {};
  this.wallHidden = {};
  Object.keys(this.roomGroups).forEach((roomId) => {
    const walls = { north: new Set(), west: new Set() };
    const objects = [];
    this.roomGroups[roomId].traverse((node) => {
      const side = node.userData && node.userData.wallSide;
      if (!side) return;
      if (node.userData.interactive && node.userData.objectId) {
        objects.push({ group: node, side });
      } else if (node.isMesh) {
        walls[side].add(node);
      }
    });
    this.roomWalls[roomId] = { north: Array.from(walls.north), west: Array.from(walls.west) };
    this.wallObjects[roomId] = objects;
    this.wallHidden[roomId] = { north: false, west: false };
  });
}
```

- [ ] **Step 2: 每帧按世界中心 + 迟滞更新显隐**

```js
updateWalls() {
  const cam = this.camera.position;
  Object.keys(this.roomGroups).forEach((roomId) => {
    const b = frameOf(roomId).bounds;
    const state = this.wallHidden[roomId];
    state.north = WordRoomWalls.nextWallHidden(cam.z, b.centerZ, state.north);
    state.west = WordRoomWalls.nextWallHidden(cam.x, b.centerX, state.west);

    const selected = this.selected;
    const forceNorth = selected && selected.userData.wallSide === 'north' && selected.userData.room === roomId;
    const forceWest = selected && selected.userData.wallSide === 'west' && selected.userData.room === roomId;

    this.roomWalls[roomId].north.forEach((mesh) => { mesh.visible = !state.north || forceNorth; });
    this.roomWalls[roomId].west.forEach((mesh) => { mesh.visible = !state.west || forceWest; });
    this.wallObjects[roomId].forEach((entry) => {
      entry.group.visible = entry.side === 'north' ? (!state.north || forceNorth) : (!state.west || forceWest);
    });
  });
}
```

`animate()` 在相机位置更新后、渲染前调用。`select()` 里必须在 `this.selected = group` **之后、`buildOutline(...)` 之前**调用一次 `updateWalls()`——否则挂墙窗户原本随墙隐藏，选中时墙体虽恢复，轮廓却已在隐藏 mesh 上构建成空；取消选中同样先清空 `selected` 再 `updateWalls()`。`setRoom` 清空选中后也调用一次。

- [ ] **Step 3: 拾取与标签跳过隐藏对象**

- `pickAt`：遍历 intersects 时加 `if (!intersects[i].object.parent || intersects[i].object.parent.visible === false) continue;`（three.js 对隐藏父组的子 mesh 仍可能返回 intersection）。
- `getLabelAnchors`：每次迭代先 `if (!group.visible) return;`，避免窗户/窗帘标签悬空。

- [ ] **Step 4: 验收北/西侧藏墙与选中强制显示**

```bash
agent-browser set viewport 1280 900
agent-browser open http://127.0.0.1:8765/index.html
agent-browser wait 1200
agent-browser eval "window.WordRoomApp.setRoom('main'); 'ok'"
agent-browser wait 700
# 转到北侧（约 180°）
agent-browser mouse move 640 420
agent-browser mouse down
agent-browser mouse move 900 420
agent-browser mouse move 1200 420
agent-browser mouse up
agent-browser wait 900
agent-browser screenshot /tmp/room3d/main-north.png
# 选中挂墙窗户，墙应强制显示
agent-browser eval "window.WordRoomApp.select('window'); document.querySelector('#wordEnglish').textContent"
agent-browser wait 700
agent-browser screenshot /tmp/room3d/window-selected.png
# 取消选中，墙恢复隐藏
agent-browser eval "window.WordRoomApp.select(''); 'cleared'"
agent-browser wait 700
agent-browser screenshot /tmp/room3d/main-north-cleared.png
agent-browser errors
```

Expected:
- `main-north.png`：北墙消失，能从背面看进室内；窗/窗帘不悬空。
- `window-selected.png`：北墙重新出现，窗户高亮、单词卡打开。
- `main-north-cleared.png`：墙再次隐藏。
- 对 `child` / `master` 重复 `setRoom` + 旋转，确认只用各自世界中心判断，主屋墙体不受影响；无闪烁（可连续截图两帧对比）。
- `agent-browser errors` 无输出。

- [ ] **Step 5: 提交**

```bash
node --check entry/src/main/resources/rawfile/room3d/assets/room-scene.js
git add entry/src/main/resources/rawfile/room3d/assets/room-scene.js
git commit -m "feat(room3d): cull near walls with hysteresis and wall-object linking"
```

---

### Task 6: 页面层——5 标签、4 统计卡、全屋交互与标签禁用

**Files:**
- Modify: `entry/src/main/resources/rawfile/room3d/assets/room-app.js`
- Modify: `entry/src/main/resources/rawfile/room3d/index.html`
- Modify: `entry/src/main/resources/rawfile/room3d/assets/room.css`
- Modify: `entry/src/main/resources/rawfile/room3d/assets/room-panel.css`

**Interfaces:**
- Consumes: Task 3 的 `VIEW_ORDER` / overview；Task 4 的 `onFrame(moving)`；Task 5 的藏墙。
- Produces: `state.activeRoom = 'overview'`；`objectsInRoom('overview')` 返回全部；标签开关在 overview `disabled`。

- [ ] **Step 1: app 默认全屋与交互规则**

- `CATEGORY_ORDER` 已在 Task 1 含 `'balcony'`；此任务只确认词汇表分组文案来自 `categories.balcony`。
- `state.activeRoom = 'overview'`。
- `objectsInRoom` 已支持 overview（Task 3）。
- `validateData` 仍要求每个对象 `ROOM_ORDER.includes(item.room)`（overview 不参与归属）。
- `updateStaticCounts` 改为按 data-room 查：
  ```js
  ROOM_ORDER.forEach((roomId) => {
    const cell = document.querySelector(`.room-stat[data-room="${roomId}"]`);
    if (cell) cell.querySelector('strong').textContent = String(objectsInRoom(roomId).length);
  });
  ```
- `setActiveRoom` 默认值改 `'overview'`；切到 overview 时直接在状态里关闭标签（`state.labelsVisible=false`、`aria-checked=false`、`label-layer.hidden=true`），不能在改成 overview 之后再调 `setLabelsVisible(false)`——该函数会在全屋守卫处直接 return。
- `setLabelsVisible` 开头加 `if (!state.ready || state.activeRoom === 'overview') return;`。
- `syncRoomChrome`：
  - 更新 `dom.labelToggle.disabled = !state.ready || state.activeRoom === 'overview'`，并设 `title`；
  - overview 时隐藏标签层、`aria-checked=false`；
  - 词汇表分组：overview 时所有 `word-group` 都加 `is-active-room`（不压暗），单间时只亮当前房；
  - 统计卡 active 只对 4 个真实房间生效。
- `chooseObject`：仅当 `state.activeRoom !== 'overview'` 且 `meta.room !== state.activeRoom` 时 `setActiveRoom(meta.room)`；overview 内选词不切视图。
- `renderWordCard` / `moveWord` 的列表改用 `objectsInRoom(state.activeRoom)`（overview 自动是 76）。
- `updateProgress` 完成文案改 `TOTAL + ' 个单词全部点亮了，和这个家说一声你真棒！'`。
- `syncSelection` / `updateSelectedLabel`：只有 `state.labelsVisible` 时才调用 `updateLabels()`，全屋下不做无用的标签布局计算。
- `onReady` 中在 `state.roomApplied = true` 后调用 `syncRoomChrome()`，让 overview 的禁用态生效；删除无条件 `labelToggle.disabled = false`（或让其被 sync 覆盖）。
- `onFrame` 改为：
  ```js
  onFrame: (moving) => {
    if (state.labelsVisible && (moving || state.labelsMoving)) updateLabels();
    state.labelsMoving = moving;
  }
  ```
  `state` 加 `labelsMoving: false`。

- [ ] **Step 2: `index.html` 改 5 标签 / 4 统计卡 / 76**

- 顶部 pill：`3 间房` → `4 间房 · 1 阳台`，`data-total` 保留由 JS 填 76。
- `room-tabs` 第一项加：
  ```html
  <button class="room-tab is-active" type="button" role="tab" aria-selected="true" data-room="overview">全屋</button>
  ```
  其余标签去掉 `is-active`，末尾加 `data-room="balcony"` 的「阳台」。
- `.room-stats` 增加第 4 格：
  ```html
  <div class="room-stat" data-room="balcony"><strong>15</strong><span>阳台</span></div>
  ```
- 所有可见的 `61` 改为 `76`（顶部 pill、欢迎页、进度、词汇表、单词卡初始 `01 / 76`、word-nav、aria、description）。
- 欢迎/aria 文案：三间房 → 四间房 + 生活阳台；操作提示改「单指拖动旋转 · 双指缩放/平移」；说明全屋默认、点标签进单间。
- 页面 `<title>` / `WORD ROOM` 小字同步。

- [ ] **Step 3: CSS 适配 5 标签与 4 统计卡**

`room.css`：

- `.room-tab` 保持 `flex:1 1 0; min-width:0; white-space:nowrap`；桌面字号 12.5px，窄屏 12.5px（不再放大到 13px 防止 5 项溢出）。
- `@media (max-width: 520px)` 下 `.room-tabs { gap: 3px; padding: 3px; } .room-tab { min-height: 34px; padding: 0 5px; font-size: 12px; }`。
- `.room-tabs` 加 `overflow-x: auto; scrollbar-width: none;` 兜底，且 `.room-tabs::-webkit-scrollbar{display:none}`。

`room-panel.css`：

- `.room-stats { grid-template-columns: repeat(4, minmax(0, 1fr)); }`。
- `@media (max-width: 520px)`：`.room-stat { padding: 10px 8px 11px; } .room-stat strong { font-size: 22px; } .room-stat span { font-size: 10.5px; }`。
- `.welcome::after { content: '76'; }`。

- [ ] **Step 4: 验收全屋默认、5 标签、4 统计、标签禁用、76 遍历与窄屏**

```bash
agent-browser set viewport 390 844
agent-browser open http://127.0.0.1:8765/index.html
agent-browser wait 1500
agent-browser eval "JSON.stringify({tabs:[...document.querySelectorAll('.room-tab')].map(t=>t.dataset.room), active:document.querySelector('.room-tab.is-active').dataset.room, totals:[...document.querySelectorAll('[data-total]')].map(n=>n.textContent), stats:[...document.querySelectorAll('.room-stat strong')].map(n=>n.textContent), labelsDisabled:document.querySelector('#labelToggle').disabled, overflow:document.querySelector('.room-tabs').scrollWidth > document.querySelector('.room-tabs').clientWidth})"
agent-browser screenshot /tmp/room3d/mobile-overview.png
agent-browser eval "window.WordRoomApp.setRoom('overview'); window.WordRoomApp.select('sofa'); JSON.stringify({active:document.querySelector('.room-tab.is-active').dataset.room, index:document.querySelector('#wordIndex').textContent, nav:document.querySelector('#wordNavIndex').textContent})"
agent-browser eval "document.querySelector('#nextWord').click(); document.querySelector('#wordIndex').textContent"
agent-browser eval "window.WordRoomApp.setRoom('balcony'); JSON.stringify({active:document.querySelector('.room-tab.is-active').dataset.room, count:document.querySelector('#sceneCount').textContent, labelsDisabled:document.querySelector('#labelToggle').disabled})"
agent-browser screenshot /tmp/room3d/mobile-balcony.png
agent-browser eval "window.WordRoomApp.setRoom('main'); document.querySelector('#labelToggle').click(); [...document.querySelectorAll('.scene-label')].filter(n=>n.style.visibility==='visible').length"
agent-browser errors
```

Expected:
- `tabs = ["overview","main","child","master","balcony"]`，`active = "overview"`。
- `totals` 全为 `"76"`；`stats = ["37","12","12","15"]`；`labelsDisabled = true`；`overflow = false`。
- 点 `sofa` 后 `active` 仍为 `"overview"`，`index = "01 / 76"`；点下一个后变为 `"02 / 76"`。
- 阳台 `active = "balcony"`、`count = "15"`、`labelsDisabled = false`。
- 单间点标签开关后可见标签数 > 0。
- 手机截图 5 个标签单行可读，4 个统计卡不溢出，全屋完整。
- `/tmp/room3d/mobile-balcony.png` 中阳台东端矮墙与西端栏杆都在画面内（6.6m 面宽未被裁切；若被裁，把 `fitMax` 继续调大，不要改 `fitMin`）。
- 无页面错误。

- [ ] **Step 5: 语法检查并提交**

```bash
node --check entry/src/main/resources/rawfile/room3d/assets/room-app.js
node scripts/verify-room3d-data.mjs
git add entry/src/main/resources/rawfile/room3d/assets/room-app.js \
  entry/src/main/resources/rawfile/room3d/index.html \
  entry/src/main/resources/rawfile/room3d/assets/room.css \
  entry/src/main/resources/rawfile/room3d/assets/room-panel.css
git commit -m "feat(room3d): whole-home UI with five tabs and balcony stats"
```

---

### Task 7: 原生校验、focus 映射、schema 与卡片文案

**Files:**
- Modify: `entry/src/main/ets/utils/RoomEnglishValidation.ets`
- Modify: `entry/src/ohosTest/ets/test/utils/RoomEnglishValidation.test.ets`
- Modify: `entry/src/main/ets/components/room/RoomEnglishCard.ets`
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`
- Modify: `entry/src/main/ets/models/AssistantModels.ets`
- Modify: `scripts/verify-room3d-data.mjs`

**Interfaces:**
- Consumes: Task 1 的 76 个 id 与 15 个阳台 id。
- Produces:
  - `ROOM_OBJECT_IDS.length === 76`；`FOCUS_MODES` 含 `'balcony'`。
  - `export function resolveRoomEnglishView(focus: string): string`：`child|master|balcony → 同名`；`living|dining|kitchen → 'main'`；其他（含 `all`/空）→ `'overview'`。
  - `RoomEnglishCard.ets` 模块级 `const ROOM_OBJECT_TOTAL: number = 76`（不是 struct 字段）；`focusRoom()` 委托 `resolveRoomEnglishView`；`applyFocusWords` 无 words 也切房。

- [ ] **Step 1: 先改测试（红）**

`RoomEnglishValidation.test.ets`：

- 「rejects unknown focus」改用 `focus:"garden"`（`balcony` 将合法）。
- 「covers 61 room objects」改为 `covers 76 room objects`，断言 `76`。
- 新增「includes every balcony word」：对 15 个 id 逐个断言 `indexOf >= 0`。
- 新增「accepts balcony focus」：`{"focus":"balcony","words":["washing_machine","railing"]}` → ok / focus `balcony`。
- 新增 `resolveRoomEnglishView` 用例：
  ```ts
  expect(resolveRoomEnglishView('living')).assertEqual('main')
  expect(resolveRoomEnglishView('dining')).assertEqual('main')
  expect(resolveRoomEnglishView('kitchen')).assertEqual('main')
  expect(resolveRoomEnglishView('child')).assertEqual('child')
  expect(resolveRoomEnglishView('master')).assertEqual('master')
  expect(resolveRoomEnglishView('balcony')).assertEqual('balcony')
  expect(resolveRoomEnglishView('all')).assertEqual('overview')
  expect(resolveRoomEnglishView('')).assertEqual('overview')
  ```
- import 加 `resolveRoomEnglishView`。

Run: DevEco Studio → 右键该测试文件 → Run。
Expected: FAIL（函数不存在 / 61 断言失败）。
（`hvigorw test` 在本项目不可用，按 MEMORY 记录只在 IDE 跑。）

- [ ] **Step 2: 更新校验层**

- 文件头注释：三间房 61 → 四间房 76；focus 枚举说明加 balcony。
- `ROOM_OBJECT_IDS` 末尾追加 15 个阳台 id（顺序与 Task 1 一致）。
- `FOCUS_MODES` 加 `'balcony'`。
- `FOCUS_HINT` 改为 `'living / dining / kitchen / child / master / balcony / all'`。
- 新增：

```ts
/** focus → 页面视图：三科区域归主屋，三间房各自打开，all/缺省打开全屋。 */
export function resolveRoomEnglishView(focus: string): string {
  const value: string = focus ? focus.trim() : ''
  if (value === 'child' || value === 'master' || value === 'balcony') {
    return value
  }
  if (value === 'living' || value === 'dining' || value === 'kitchen') {
    return 'main'
  }
  return 'overview'
}
```

- [ ] **Step 3: 更新 `RoomEnglishCard`**

- import 改为 `{ RoomEnglishValidationResult, resolveRoomEnglishView, validateRoomEnglishArgs }`。
- `ROOM_OBJECT_TOTAL = 76`；注释计数加阳台 15。
- `focusRoom()` 直接 `return resolveRoomEnglishView(this.argsView.focus)`。
- `applyFocusWords()` 删除 `if (room === 'main' && first === 'null') return`，保留其余逻辑：始终 `setRoom(room)`，有 first 才 `select`。
- 头部注释/副标题改四间房 + 阳台；空进度文案改为「全屋、客餐厅、儿童房、主卧、阳台，点一点就知道它叫什么」。

- [ ] **Step 4: 更新工具 schema 与描述**

`BuiltinTools.ets` room_english 段：

- 注释：四间房 76 件 + 全屋。
- `focus.enum` 加 `"balcony"`；description 加 `balcony=阳台（15 件物品）`，说明 `child/master/balcony` 直接切房、`all` 打开全屋。
- `words.description` 在末尾加：`阳台 washing_machine dryer laundry_basket drying_rack clothespin laundry_sink storage_cabinet broom mop bucket balcony_plant flower_pot watering_can railing folding_stool。`
- `func.description`：four rooms + balcony / 76 objects / overview tab；保持 `INSTEAD of describing furniture` 措辞。
- `ToolConfig` 中文摘要：「走进全屋、客餐厅、厨房、两间卧室和阳台，76 个家居单词」。
- rawSchemaJson 新描述只用中文标点，禁止 ASCII 双引号。

- [ ] **Step 5: 更新助手教学提示**

`AssistantModels.ets` 两处 room_english 文案：加“全屋/阳台/生活词汇”，focus 示例补 `balcony`；不改变教学流程与授星规则。

- [ ] **Step 6: 扩展脚本，锁定原生与页面同步**

`scripts/verify-room3d-data.mjs` 追加：

```js
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
assert.equal((html.match(/class="room-tab/g) || []).length, 5);
assert.equal((html.match(/class="room-stat"/g) || []).length, 4);
assert.ok(!/data-total>61</.test(html));
console.log('room3d native/page parity OK');
```

Run: `node scripts/verify-room3d-data.mjs`
Expected: `room3d native/page parity OK`（在 Step 2–4 完成前会失败，可作为红/绿检查）。

- [ ] **Step 7: 跑测试并提交**

Run: DevEco Studio → `RoomEnglishValidation.test.ets` → Run。
Expected: 全部 PASS。

```bash
node scripts/verify-room3d-data.mjs
git add entry/src/main/ets/utils/RoomEnglishValidation.ets \
  entry/src/ohosTest/ets/test/utils/RoomEnglishValidation.test.ets \
  entry/src/main/ets/components/room/RoomEnglishCard.ets \
  entry/src/main/ets/config/BuiltinTools.ets \
  entry/src/main/ets/models/AssistantModels.ets \
  scripts/verify-room3d-data.mjs
git commit -m "feat(room_english): accept balcony focus and 76 word ids"
```

---

### Task 8: 文档同步与整机回归

**Files:**
- Modify: `CLAUDE.md`
- Modify: `.claude/rules/teaching-architecture.md`
- Maybe modify: `CHANGELOG.md`（若仓库当前版本段存在 room_english 条目）

**Interfaces:**
- Consumes: Tasks 1–7 全部。
- Produces: 文档描述与代码一致；最终构建产物。

- [ ] **Step 1: 更新项目文档**

- `CLAUDE.md` room_english 行：三间房 61 → 四间房 + 生活阳台 76；补「默认全屋户型视图、360° 环绕、近侧墙自动隐藏」。
- `.claude/rules/teaching-architecture.md` §4 工具表 room_english 行同步；若文首有房间/物品计数描述一并更新。
- `CHANGELOG.md` 若当前未发布段存在 3D 词屋条目，追加本次变更；没有则跳过，不新开版本段。

- [ ] **Step 2: 全量静态检查**

```bash
for f in entry/src/main/resources/rawfile/room3d/assets/*.js; do node --check "$f" || exit 1; done
node scripts/verify-room3d-data.mjs
```
Expected: 全部 `node --check` 静默通过；脚本输出三行 OK（data / model parity / native-page parity）。

- [ ] **Step 3: 浏览器整机验收（桌面 + 手机）**

```bash
python3 -m http.server 8765 --directory entry/src/main/resources/rawfile/room3d &
mkdir -p /tmp/room3d-final
agent-browser set viewport 1280 900
agent-browser open http://127.0.0.1:8765/index.html
agent-browser wait 1500
for room in overview main child master balcony; do
  agent-browser eval "window.WordRoomApp.setRoom('$room'); 'ok'"
  agent-browser wait 700
  agent-browser screenshot "/tmp/room3d-final/desktop-$room.png"
done
agent-browser set viewport 390 844
agent-browser reload
agent-browser wait 1500
agent-browser screenshot /tmp/room3d-final/mobile-overview.png
agent-browser eval "window.WordRoomApp.setRoom('balcony'); 'ok'"
agent-browser wait 700
agent-browser screenshot /tmp/room3d-final/mobile-balcony.png
agent-browser errors
agent-browser console
```

手动核对：
- 全屋构图、四间房 + 阳台关系清楚，无穿模/地板共面闪烁。
- 每个单间取景居中，阳台 15 件家具可辨认。
- 360° 北/西侧藏墙正常；窗/窗帘选中强制显示。
- 手机 5 标签不溢出、统计卡不挤压、画面完整。
- 控制台无 error。

- [ ] **Step 4: 编译 HAP**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```
Expected: BUILD SUCCESSFUL，产物 `entry/build/default/outputs/default/entry-default-signed.hap`。

- [ ] **Step 5: 跑 hypium 测试**

DevEco Studio → `entry/src/ohosTest/ets/test/utils/RoomEnglishValidation.test.ets` → Run。
Expected: 全部 PASS（CLI 不支持 `hvigorw test`，不要用命令行结果判断）。

- [ ] **Step 6: 提交文档与最终修正**

```bash
git add CLAUDE.md .claude/rules/teaching-architecture.md CHANGELOG.md
git commit -m "docs(room3d): document whole-home view and balcony vocabulary"
```

---

## Self-Review Notes

- Spec §4.1 户型摆放 → Task 2 offsets / Task 3 groups；§4.2 360° 与藏墙 → Task 4 / Task 5；§4.3 手感 → Task 4；§4.4 阳台 15 件 → Task 1 / Task 2；§4.5 UI/交互 → Task 6；§4.6 原生 → Task 7；§4.7 frames/地板修边 → Task 2；§4.8 阴影 → Task 3；§6 验收 → Task 8。
- Review Focus 五项均落到具体任务：藏墙/选中 → Task 5；全屋点选与 76 遍历 → Task 6；focus 映射 → Task 7；窄屏 → Task 6。
- 类型/命名一致性：`WordRoomModels.offsets`、`buildBalcony`、`resolveRoomEnglishView`、`VIEW_ORDER`、`ROOM_OBJECT_TOTAL` 在相关任务中同名。
- 不新增依赖；不改变既有 61 件物品数据；所有计数由 61 → 76 锁步。
