# 小词屋 3D 房间 v3：全屋平面视图 + 360° 环绕 + 生活阳台

**日期：** 2026-10-29
**状态：** 待确认（brainstorming 产出，未开始实施）
**范围：** `entry/src/main/resources/rawfile/room3d/`（Web 3D 场景 + 数据 + 页面）、`RoomEnglishCard` 宿主集成、`room_english` 工具校验与 schema、相关文档
**参考：** 本地 Open Design 原型 `…/projects/713725c6-…`（三室一阳台 3D 漫游，仅借鉴视觉与空间组织，不照搬其页面）

---

## 1. 为什么做

现有小词屋已经有 3 间房、61 个单词、房间标签、点击出单词卡、TTS、英文标签层。但孩子/家长打开后有三个明显缺口：

1. **看不到"整套房子"**：三间房都建在原点，同一时刻只显示一间，无法建立"家"的空间概念，也没有设计图式的整体视角。
2. **不能 360° 看**：水平角被硬限在 `0.18–1.4`（约 70°），垂直角限在 `0.64–1.24`；从背面看会撞墙。
3. **操作不跟手**：拖拽经过 `desired → orbit → camera` 三层缓动，缩放/旋转有明显迟滞和橡皮筋感。
4. **缺一间生活阳台**：真实家庭里洗衣机、晾衣架、清洁工具都在阳台，是孩子高频接触的生活词汇区。

参考项目恰好给出了"整套户型 + 全景视角"的答案，本次把它的空间组织方式吸收进来，同时保留小词屋自己的单词卡/发音/进度体系。

## 2. 目标 / 非目标

**目标**

- 新增「全屋」视角并作为默认视图：四间房按真实户型摆好，同屏可见，像看一张 3D 设计图。
- 相机支持完整 360° 水平环绕；垂直方向保留合理限位。
- 拖拽/旋转/缩放改为单层阻尼、直接跟手；移动端收紧像素比与阴影开销。
- 新增第 4 间房「生活阳台」（约 6.6m × 2.4m）+ 15 件可点物品，单词总数 61 → 76。
- 房间标签、欢迎页统计、词汇表、进度、原生 `room_english` 校验同步更新。

**非目标**

- 不重写单词卡、TTS、词汇表、进度存储等既有交互。
- 不引入新依赖、外部贴图或网络资源；全部使用现有 three.js + 程序化 canvas 纹理。
- 不改变 `room_english` 的讲解型语义（不授星、不判对错）。
- 不复制参考项目的 HTML/CSS/UI；只借鉴空间与镜头组织。

**反目标（做了就算失败）**

- 全屋视图变成"四个房间挤在一起穿模"。
- 360° 旋转时只剩外墙，或墙在镜头前闪烁。
- 旋转跟手变好但点击、双指缩放、单词卡被打断。
- 新增阳台后 `room_english` 的 `words` 校验拒绝新 id。

---

## 3. 现状（需要改的代码事实）

| 位置 | 现状 |
|------|------|
| `rawfile/room3d/assets/scene-data.js` | 61 个物品，`roomOrder: ['main','child','master']`；`ROOM_BY_CATEGORY` 五类 |
| `rawfile/room3d/assets/room-models.js` | `buildRoom` / `buildBedrooms` 把每间房建在各自原点；`ROOM_FRAMES` 三份；主屋壳体只有北墙+西墙，卧室同样只砌北/西（东/南剖开展示） |
| `rawfile/room3d/assets/room-scene.js` | 三组 `roomGroups`，一次只显示一组；`DEFAULT_ROOM='main'`；theta 硬限 `[0.18,1.4]`、phi `[0.64,1.24]`；动画里 orbit 与 camera 双重 lerp |
| `rawfile/room3d/assets/room-app.js` | `activeRoom='main'`；`ROOM_ORDER` 驱动标签与统计；`objectsInRoom` 单房间过滤 |
| `rawfile/room3d/index.html` | 3 个房间标签、3 个统计卡、写死 61 |
| `entry/src/main/ets/utils/RoomEnglishValidation.ets` | 写死 61 个物品 id；focus 枚举无 balcony |
| `entry/src/main/ets/config/BuiltinTools.ets` | focus 枚举 / 描述写死三间房、61 件 |
| `entry/src/main/ets/components/room/RoomEnglishCard.ets` | `ROOM_OBJECT_TOTAL=61`；`focusRoom()` 只认 child/master |

---

## 4. 关键设计决策

### 4.1 全屋视图 = 真实户型摆放（默认视图）

不是把四个房间按标签页轮换显示，而是**在同一个世界坐标系里按户型摆放**，四组 room group 同时可见：

```
z
↑  北
│   ┌──────────────────────────┐
│   │        客餐厅 + 厨房      │      ┌──────────┐
│   │        11.8m × 6.4m      │      │  儿童房   │
│   │                          │      │ 4.4×3.6  │
│   │                          │      ├──────────┤
│   │                          │      │   主卧   │
│   └───────────┬──────────────┘      │ 4.6×3.6  │
│               │ 玻璃推拉门           └──────────┘
│        ┌──────┴────────┐
│        │   生活阳台     │
│        │   6.6 × 2.4   │
│        └───────────────┘
└──────────────────────────────→ x 东
```

- 主屋 group 保持原点；儿童房/主卧平移到东翼；阳台平移到客厅南侧。
- 由于现有房间壳体本来就是「北墙 + 西墙、东/南剖开」的 dollhouse，四组按上述方式相邻摆放后，东/南开口正好朝向默认镜头（东南上方），天然形成剖切展示，不需要重砌共享墙。
- 房间之间保留 0.1–0.2m 的结构缝/墙体厚度，避免地板共面 z-fighting。
- 标签顺序：**全屋 / 客餐厅 / 儿童房 / 主卧 / 阳台**，默认 `overview`。
- 全屋模式下所有物品可点、词汇表/进度显示全部 76 个；点「客餐厅」等标签再拉近到单间（其余房间隐藏，沿用现有 `setRoom` 语义）。

**为什么不是照参考项目做一整片连续大平层**：现有三间房各自带 base slab 和剖切壳体，强行连续会重复墙体/地板；"户型摆放 + 剖切玩具屋"既读得懂空间关系，又不用重做全部几何。

### 4.2 相机：360° 水平环绕 + 靠墙自动隐藏

- 水平角 `theta` 解除硬限位，允许无限旋转（内部对 `2π` 取模，避免数值漂移）。
- 垂直角 `phi` 保留限位，建议 `[0.38, 1.22]`（约 20°–68° 俯角），防止钻到地板下或完全平视。
- 每个房间只有北墙/西墙实体。给墙体 mesh 打 `userData.wallSide = 'north' | 'west'`（含主屋北墙、厨房北墙、卧室北墙、卧室窗框/玻璃/窗帘装饰、主屋 window/curtain 两个可点物品）。
- 每帧根据相机相对房间中心的位置决定显隐：
  - 相机在房间北侧（`camera.z < center.z - 阈值`）→ 隐藏北墙；
  - 相机在房间西侧（`camera.x < center.x - 阈值`）→ 隐藏西墙。
  - 用不对称阈值（隐藏 0.5m / 显示 0.3m）做迟滞，避免边界抖动；判定抽成 `assets/wall-culling.js` 的 `nextWallHidden()` 纯函数，由 `scripts/verify-room3d-data.mjs` 固定回归。
- 东/南侧本来就是开口，因此从任意方位都能看进房间；转到背面时隐藏近侧墙，不会只看到外墙背面。
- 阳台的玻璃推拉门是半透明玻璃，不参与隐藏；栏杆不遮挡。
- 全屋模式下墙体显隐按**每个房间各自的世界中心**计算。
- **挂在墙上的可点物品**（主屋 `window` / `curtain`，以及卧室窗框/玻璃/窗帘装饰）跟随墙体一起隐藏：
  - 墙体隐藏时，同时隐藏它们的 mesh、hitbox 和标签；
  - 如果孩子从词汇表/上一个下一个/native `words` 选中了它们，**选中态强制显示所在墙**，取消选中后恢复自动显隐；
  - `updateLabels` 跳过被墙隐藏的未选中物品，避免标签悬空。

### 4.3 手感：单层阻尼 + 直接跟手

现有 `animate()` 里：

```js
// orbit 先追 desired，camera 再追 orbit —— 两层平滑叠加
this.orbit.theta += (this.desired.theta - this.orbit.theta) * ease;
...
this.camera.position.lerp(targetPosition, 1 - Math.exp(-dt * 9));
```

改为：

- 保留 `desired` 与 `current` 两份球坐标状态；
- 拖拽/缩放进行中：`current` 以更高的半衰速率追 `desired`（`1 - exp(-dt*18)`），视觉上接近 1:1；
- 手指/滚轮停止后：速率降到 `1 - exp(-dt*6)` 做短惯性收尾；
- **删除 `camera.position.lerp`**，相机位置每帧直接由 `current` 球坐标计算；
- `dt` 统一 `Math.min(0.05, …)`，保证掉帧时不会瞬移；
- 记录最近若干次拖拽角速度，松手后把速度注入 `desired`，形成自然的惯性滑行（`reducedMotion` 时禁用）。

手势语义统一：

- 单指拖动 = 旋转（不再在放大后偷偷切成平移；现在的 `pan: radius < fit*0.85` 是"转不动"的主要来源）；
- 双指 = 捏合缩放 + 双指平移（保留）；
- 鼠标：左键旋转、滚轮缩放、右键/Shift+左键平移；
- 键盘方向键旋转，`+/-` 缩放，`R` 复位（沿用）。

性能收紧：

- 移动端 `setPixelRatio` 上限从 1.65 降到 **1.4**；桌面维持 2。
- 移动端阴影贴图维持 1024，桌面 2048（现状）。
- 标签层只在 `labelsVisible` 时更新（现状已如此），并跳过镜头静止帧。
- 不引入 render-on-demand（风险大于收益，本版不强制）。

### 4.4 生活阳台

- 位置：客厅南侧，室内矩形约 **6.6m × 2.4m**；北侧与客厅之间是一整面玻璃推拉门（两扇大玻璃 + 细框），南/东/西三侧为 1.1m 玻璃栏杆 + 扶手；东端加一段 1.2m 高矮墙给洗烘叠放做背景。
- 地面：防滑地砖（程序化 canvas 纹理，网格 + 轻微噪点），与客厅木地板区分。
- 功能分区：
  - **东端洗涤区**：洗衣机 + 上方叠放烘干机、洗衣池。
  - **中段晾晒区**：折叠晾衣架、晾衣夹、洗衣篮。
  - **西端清洁/园艺区**：收纳柜、扫帚、拖把、水桶、绿植、花盆、浇水壶、折叠凳。
  - > 收纳柜最初放在东端洗涤区，从默认东南视角把洗衣机和烘干机挡在后面；现已移到西端清洁区（见 §10 补记）。
  - **南侧栏杆**：可点选，作为 `railing` 单词。
- 15 件物品（id / 英文 / 中文 / 音标 / 儿童解释 ≤20 字 / 例句）：

| id | word | zh | phonetic | kidDefinition | example |
|----|------|----|----------|---------------|---------|
| `washing_machine` | washing machine | 洗衣机 | /ˈwɔːʃɪŋ məˌʃiːn/ | 洗衣服的大机器，转一转就干净。 | The washing machine is spinning. |
| `dryer` | dryer | 烘干机 | /ˈdraɪər/ | 把湿衣服吹干的机器。 | The dryer makes clothes warm. |
| `laundry_basket` | laundry basket | 洗衣篮 | /ˈlɔːndri ˌbæskɪt/ | 装脏衣服的篮子。 | Put the clothes in the basket. |
| `drying_rack` | drying rack | 晾衣架 | /ˈdraɪɪŋ ræk/ | 挂湿衣服晾干的架子。 | The shirt is on the rack. |
| `clothespin` | clothespin | 晾衣夹 | /ˈkloʊðz pɪn/ | 夹住衣服的小夹子。 | Use a clothespin to hold it. |
| `laundry_sink` | laundry sink | 洗衣池 | /ˈlɔːndri sɪŋk/ | 洗小件衣物的水池。 | Wash the socks in the sink. |
| `storage_cabinet` | storage cabinet | 收纳柜 | /ˈstɔːrɪdʒ ˈkæbɪnət/ | 放洗衣液和工具的柜子。 | The soap is in the cabinet. |
| `broom` | broom | 扫帚 | /bruːm/ | 扫地用的长把刷子。 | Sweep the floor with a broom. |
| `mop` | mop | 拖把 | /mɑːp/ | 拖地用的湿湿的布头。 | Mop the floor with water. |
| `bucket` | bucket | 水桶 | /ˈbʌkɪt/ | 提水用的小桶。 | Fill the bucket with water. |
| `balcony_plant` | plant | 绿植 | /plænt/ | 阳台上晒太阳的绿色朋友。 | The plant likes the sun. |
| `flower_pot` | flower pot | 花盆 | /ˈflaʊər pɑːt/ | 装泥土种花的小盆。 | The flower grows in a pot. |
| `watering_can` | watering can | 浇水壶 | /ˈwɔːtərɪŋ kæn/ | 给花浇水的壶。 | Water the flowers with it. |
| `railing` | railing | 栏杆 | /ˈreɪlɪŋ/ | 阳台边上的扶手，很安全。 | Hold the railing. |
| `folding_stool` | folding stool | 折叠凳 | /ˈfoʊldɪŋ stuːl/ | 折起来就能收好的小凳子。 | I sit on the folding stool. |

- 新增 category `balcony`（zh 阳台 / en BALCONY）与 room `balcony`（zh 阳台 / tab 阳台 / eyebrow「阳台 · 3D 场景」/ heading「生活阳台英语探索」/ size「6.6m × 2.4m」）。
- 单词总数 61 → **76**（客厅 15 + 餐厅 10 + 厨房 12 + 儿童房 12 + 主卧 12 + 阳台 15）。

### 4.5 UI 与数据同步

- `scene-data.js`：物品追加、`ROOM_BY_CATEGORY` 加 `balcony`、`rooms`/`roomOrder` 加阳台、`categories` 加阳台。
- 新增 `overview` 视图元数据（不是 room，不参与物品归属）：
  - `rooms.overview = { zh:'全屋', tab:'全屋', eyebrow:'我的家 · 3D 户型', heading:'全屋 3D 探索', size:'16.8m × 8.9m', note:'…' }`
  - `roomOrder` 保持四个真实房间；标签渲染用 `VIEW_ORDER = ['overview', ...roomOrder]`，统计卡只渲染 `roomOrder`。
- `objectsInRoom('overview')` 返回全部；`activeRoom` 默认 `overview`。
- `index.html`：5 个标签、4 个房间统计卡、静态 `61` → `76`、aria 描述改为"四间房 + 阳台"、欢迎页文案。
- 词汇表按 `CATEGORY_ORDER` 增加 `balcony` 分组。
- 进度/欢迎文案从"这三间房"改为"这个家/四间房"。

#### 4.5.1 全屋模式下的交互规则（评审后确定）

- **点物品不离开全屋**：`activeRoom === 'overview'` 时，点场景物品/词汇表/上一个下一个都只打开单词卡，不自动切房间。镜头保持全屋。
- **单词卡序号**：全屋模式按全部 76 个词排序；单间模式只排该房间的词（与现有行为一致）。`moveWord` 依据当前视图的列表。
- **标签层**：英文标签是"单间学习"工具——全屋模式下标签开关禁用、标签层隐藏；切到任一间房后恢复可用。全屋下悬停/选中仍有单词提示 chip。
- **AI focus 映射**：`child` / `master` / `balcony` → 对应房间；`living` / `dining` / `kitchen` → `main`；`all` 或缺省 → `overview`。
- **无 words 的 focus 也要切房**：`applyFocusWords` 不再因为 `room === 'main' && first === 'null'` 提前 return——`focus:"living"` 即使不带 words，也必须切到主屋；只有 `overview` 可以无 words 直接停留。

### 4.6 原生集成（必须同步，否则 AI 传不了阳台词）

- `RoomEnglishValidation.ets`：`ROOM_OBJECT_IDS` 追加 15 个 id；`FOCUS_MODES` 加 `balcony`；`FOCUS_HINT` 更新；注释 61→76。
- `BuiltinTools.ets`：room_english schema 的 `focus.enum` 加 `balcony`；描述改成四间房 76 件，加阳台 id 列表。
- `RoomEnglishCard.ets`：`ROOM_OBJECT_TOTAL` 61→76；`focusRoom()` 对 `balcony` 返回 `'balcony'`；`focus==='all'` 时返回 `'overview'`（让"全屋"成为默认打开视图）；同步注释。
- 可选文案更新：`AssistantModels.ets` 里 room_english 的教学提示加入"阳台/生活词汇"；`SearchToolIdentityUtils.ets` 注释。
- 文档：`CLAUDE.md` 的 room_english 行、`.claude/rules/teaching-architecture.md` 第 4 节工具表同步为"四间房 76 件 + 全屋视图"。

### 4.7 全屋取景参数（建议值，builder 可微调）

| 视图 | group 位置 (x,z) | target | bounds (z 从北到南) | fit |
|------|------------------|--------|---------------------|-----|
| main | (0, 0) | 现有 | 现有 `-4.19..7.65 / -3.19..3.19` | 现有 |
| child | (10.01, -1.19) | 世界坐标 + 组偏移 | 组局部 ±2.2 / ±1.8 | 现有参数 + 偏移 |
| master | (10.11, 2.81) | 同上 | 组局部 ±2.3 / ±1.8 | 现有参数 + 偏移 |
| balcony | (-0.89, 4.39) | (-0.89, 0.8, 4.39) | x -4.19..2.41 / z 3.19..5.59 | fitMin 4.5 / fitMax 13.5 / zoomMin 2.4（fitMax 原定 9 只够桌面横屏；竖屏手机 aspect≈0.76 时需 ≈12.2 才不裁 6.6m 面宽） |
| overview | — | (4.1, 0.7, 1.3) | x -4.36..12.58 / z -3.19..5.76 | fitMin 16 / fitMax 48 / zoomMin 8 |

- 东翼两间房西墙外皮都落在 `x ≈ 7.65`，与主屋东缘对齐；儿童房北缘与主屋北缘对齐；主卧在儿童房南侧。
- 阳台东缘 `x ≈ 2.41`，不碰东翼；南缘 `z ≈ 5.59`，是全屋最南端。
- `fitRadius()` 已按 halfWidth/halfDepth 计算，只需给 overview 足够大的 `fitMax`；移动端 aspect 小会自然拉远。
- **主屋地板必须修边**：现有 `buildRoomShell` 的 15 条地板从 `x=-3.6` 起、宽 0.795、步距 0.8，最东到 `x≈8.00`，比 `ROOM.maxX=7.65` 和 base 东缘 7.68 多出约 0.3m。实施时把最后一条/整体裁到 7.65，否则会和东翼地板共面 z-fighting。
- **接缝**：儿童房/主卧 base 与主屋 base 保持 ≥4cm 结构缝；阳台 base 北缘从 `z=3.19` 开始（不做北侧外挑），或将阳台 base 下沉 2mm，避免与主屋 base 共面。

#### 4.8 阴影覆盖（评审后确定）

- 现有一盏固定方向光的 shadow camera 是 ±7m、对准原点，东翼移到 `x≈10–12.6` 后会完全落在阴影相机外——两间卧室会失去阴影。
- 改为**跟随当前视图的 shadow frustum**：
  - 光源方向保持不变；`key.target` 跟随当前视图 target；
  - 阴影相机 `left/right/top/bottom` 按当前视图 bounds 的较大半轴 + 2m 计算；
  - overview 约 ±11m，单间约 ±5m；`setRoom()` / `resetView()` 时更新；
  - 移动端保持 1024、桌面 2048。
- 这样单间阴影仍然清晰，全屋视图的阴影略软但可接受（低多边形风格容错高）。

---

## 5. 文件触点

| 文件 | 改动 |
|------|------|
| `rawfile/room3d/assets/scene-data.js` | +15 物品、阳台 category/room、overview 元数据、总数 |
| `rawfile/room3d/assets/room-models.js` | 阳台壳体 + 15 件家具；墙体 `wallSide` 标记；room group 偏移；`ROOM_FRAMES` 加 overview/balcony 并世界化 |
| `rawfile/room3d/assets/room-scene.js` | overview 组可见性、360 相机、单层阻尼、惯性、墙体显隐、hitboxes/objects 汇总 |
| `rawfile/room3d/assets/room-app.js` | 默认 overview、VIEW_ORDER、objectsInRoom、统计、标签、词汇表分类 |
| `rawfile/room3d/index.html` | 5 标签、4 统计卡、76、aria/欢迎文案 |
| `rawfile/room3d/assets/room.css` | 5 标签在窄屏的排布（可能改字号/间距/横向滚动） |
| `entry/src/main/ets/utils/RoomEnglishValidation.ets` | id 白名单 + focus |
| `entry/src/main/ets/config/BuiltinTools.ets` | schema enum + 描述 |
| `entry/src/main/ets/components/room/RoomEnglishCard.ets` | 总数、focusRoom、注释 |
| `entry/src/main/ets/models/AssistantModels.ets` | 教学提示文案（可选） |
| `CLAUDE.md` / `.claude/rules/teaching-architecture.md` | 文档同步 |
| `docs/superpowers/specs/2026-10-29-room3d-overview-balcony-design.md` | 本文档 |

---

## 6. 验收标准

**功能**

- [ ] 首次打开默认「全屋」，同屏看到主屋、东翼两间卧室、南侧阳台，空间关系一眼可读。
- [ ] 5 个标签可切换；切到单间后镜头拉近，其他房间隐藏；再点同一标签复位。
- [ ] 全屋/单间模式下水平拖动可连续转满 360°，无跳变、无硬限位。
- [ ] 相机转到北侧/西侧时，近侧墙体（含窗/窗帘）自动隐藏；转回后恢复，无闪烁。
- [ ] 单指旋转、双指缩放+平移、鼠标左键旋转/滚轮缩放/右键平移均可用；松手有短惯性。
- [ ] 阳台 15 件物品均可点击，单词卡内容正确，TTS 可朗读。
- [ ] 全屋模式下点物品只打开单词卡，镜头不切走；上一个/下一个按全部 76 词遍历。
- [ ] 全屋模式下英文标签开关禁用；切到单间后可正常显示。
- [ ] 相机转到北/西侧时，挂墙物品（window/curtain）与墙一起隐藏；从词汇表选中它们时墙临时显示，取消后恢复。
- [ ] `focus:"living"` 即使不带 `words` 也会切到主屋；`focus` 缺省/`all` 打开全屋。
- [ ] 东翼两间房在全屋和单间视图下都有阴影；主屋东缘与东翼之间无明显共面闪烁。
- [ ] 总数 76 在顶部 pill、欢迎页、词汇表、进度中一致；4 个房间统计数正确。
- [ ] `room_english` 传 `focus:"balcony"` 或 `words:["washing_machine", …]` 能通过校验并直接切到阳台。

**手感 / 性能**

- [ ] 拖动过程中画面与手指位移基本 1:1，无肉眼可见的追赶延迟。
- [ ] 快速连续旋转/缩放 10 秒，帧率稳定，无累积漂移或突然回弹。
- [ ] 移动端像素比 ≤1.4；场景加载后无持续高 CPU（标签关闭时不每帧改 DOM）。

**工程**

- [ ] 所有 rawfile JS 通过 `node --check`。
- [ ] `hvigorw assembleHap` 编译通过。
- [ ] 无新增第三方依赖、无网络请求。
- [ ] 既有 61 件物品的 id/单词卡/发音不受影响。

---

## 7. 风险与取舍

| 风险 | 处理 |
|------|------|
| 四组房间相邻处地板/墙体 z-fighting | 保留 0.1–0.2m 缝或基础板单独下沉 2mm；验收时截图检查 |
| 墙体显隐在阈值附近抖动 | 不对称阈值 + 0.2m 迟滞（`wall-culling.js` 纯函数 + Node 回归：停在带内不翻转） |
| 360° 转到背面时室内被家具挡住 | 只隐藏北/西墙，东/南本就开口；必要时再提高 phi 下限 |
| 全屋视图在窄屏上过小 | 移动端 `fov` 44、fitMax 放宽；标签先切房间；全屋仅做空间认知 |
| 单指取消"放大后平移"改变老习惯 | 双指仍可平移；文档与手势提示更新为"单指旋转 · 双指缩放/平移" |
| 新增 id 与既有单词重复（plant/cabinet/sink/stool） | 使用独立 id（balcony_plant/storage_cabinet/laundry_sink/folding_stool），词汇表允许同词多物 |

**留给 builder 的决定**：阳台家具的具体尺寸/摆放细节、地砖纹理样式、晾衣架展开角度、玻璃推拉门分格、墙体标记的具体实现方式（数组收集 vs userData）、惯性系数。

---

## 8. 实施顺序建议

1. 数据层：`scene-data.js` 加 15 词 + 阳台/overview 元数据。
2. 场景层：`room-models.js` 阳台几何、墙体标记、房间偏移与 frames。
3. 控制器：`room-scene.js` overview、360、单层阻尼、惯性、墙体显隐。
4. 页面层：`room-app.js` + `index.html` + CSS 标签/统计/文案。
5. 原生：校验白名单、schema、RoomEnglishCard。
6. 验证：node --check、headless 截图（全屋/各房间/阳台）、assembleHap、文档同步。

---

## 9. 评审后拍板的决定（供快速核对）

独立 builder 评审提出的 6 个问题，均已在不改变已确认方向的前提下定案：

1. **全屋点物品不切房间**——保持全屋镜头，只开单词卡；上一个/下一个在全屋按 76 词、单间按该房间词遍历。
2. **挂墙物品随墙一起隐藏**（mesh + hitbox + 标签）；选中时强制显示所在墙，取消后恢复。
3. **修主屋地板东缘**：地板实际伸到 `x≈8.00`，裁回 7.65，而不是把东翼继续外移；阳台 base 与主屋 base 不共面。
4. **阴影相机跟随视图**：overview ±11m、单间 ±5m，光源方向不变，移动端 1024 / 桌面 2048。
5. **全屋不显示英文标签**：标签是单间学习工具，全屋下禁用开关；悬停/选中仍有提示。
6. **`focus:"living"` 无 words 也切主屋**：修掉默认视图改为 overview 后引入的回归；`all`/缺省才停在全屋。

---

## 10. 补记（2026-10-29 体验修正）

上线后试用反馈三处问题，均在本 spec 方向内修复，不新增工具、不改单词表（仍 76 件）：

### 10.1 客餐厅多镜头中心（客厅 / 餐厅 / 厨房）

**问题**：客餐厅只有一个固定取景目标 + 较紧的平移夹取范围（`panInsetX 1.7 / panInsetZ 1.3`），放大后往厨房方向拖，镜头被夹在客厅这头，厨房拖不过来。

**方案**：
- 新增纯数据模块 `assets/room-layout.js`（`window.WordRoomLayout = { areas, doors }`，与 `wall-culling.js` 同法，Node 可直接加载做回归）。`areas` 三个分区中心：

  | area | label | target (x, y, z) | radius |
  |------|-------|------------------|--------|
  | `living` | 客厅 | (-1.9, 0.9, -0.05) | 6.9 |
  | `dining` | 餐厅 | (2.2, 0.95, -0.15) | 5.9 |
  | `kitchen` | 厨房 | (6.1, 0.95, -1.3) | 6.4 |

- `room-models.js` 的 `ROOM_FRAMES.main` 增加 `areas: LAYOUT.areas`，并把平移夹取放宽到 `panInsetX 0.6 / panInsetZ 0.5`——放大后可以自由拖到房间任意角落。
- `room-scene.js` 新增 `focusArea(areaId)`：直接改 `desired.target` + `desired.radius`（半径再经 `zoomRange()` 夹取），置 `autoFit = false`，记录 `activeArea`；切房 / 重置时清空。
- 页面 `index.html` 在房间标签下加一行 `#areaTabs`（镜头 客厅 餐厅 厨房），仅在客餐厅可见；`room-app.js` 负责 `state.activeArea`、`syncAreaChrome()`、`setActiveArea()`、桥接 `setArea(areaId)`。
- 原生：`utils/RoomEnglishValidation.ets` 新增纯函数 `resolveRoomEnglishArea(focus)`（living/dining/kitchen → 同名，其余 → `''`）；`RoomEnglishCard.applyFocusWords()` 在 `setRoom` 之后追加 `app.setArea(...)`——AI 用 `focus:"kitchen"` 时镜头直接对准厨房。schema 里 `focus` 描述同步说明。
- 房间标签重进同一房间（单词无变化路径）会重置视图并清空分区选中，避免"看着厨房、标签却说着客厅"的错位。

### 10.2 客餐厅通往儿童房 / 主卧的门

**问题**：两间卧室的西墙（面向客餐厅）是整面实墙，从客餐厅看过去没有入口。

**方案**：
- `room-layout.js` 新增 `doors.child` / `doors.master`：`{ z0, z1, height: 2.05, open: 1.42 }`（本地坐标，米）。
- `room-models.js` 的 `bedroomShell(...)` 新增 `door` 参数：西墙拆成「北段 + 南段 + 门楣」，加门套（jambs + head trim，`wallSide 'west'` 参与遮挡剔除）；门扇是独立 `THREE.Group`，合页挂在北侧门边 `(-hw + 0.045, FLOOR_Y, z0 + 0.02)`，`rotation.y = open` 向房内敞开；门扇双面贴凹槽面板 + 两个黄铜把手；全部 mesh 打 `'west'` 墙标，随墙一起隐显。西侧踢脚线同步在门洞处断开。
- 门洞位置避开贴墙家具：
  - 儿童房：`z ∈ [-0.89, -0.01]`，夹在衣柜（`-1.725…-1.175`）和书架（`0.29…1.61`）之间。
  - 主卧：`z ∈ [-0.46, 0.34]`；梳妆台 / 镜子 / 凳子整组南移到 `z = 0.8`，相框 `z = 0.67`，让开门洞与门扇扫过的范围。
- 门洞高 2.05m，宽 0.88m（子房）/ 0.80m（主卧），符合低多边形尺度也够孩子"看进去"。

### 10.3 阳台收纳柜挡洗衣机 / 烘干机

**问题**：收纳柜原在东端洗涤区、洗衣机烘干机正前方，默认（东南）视角下把两台机器整个挡住。

**方案**：收纳柜移到**西端清洁区** `(-2.88, FLOOR_Y, -0.2)`，`rotation.y = π` 让柜门朝东（面向阳台内部）。校验：`x ≤ -2.5` 且 `z ∈ [-0.6, 0.2]`，不碰西侧栏杆（`x ≥ -3.14`）、绿植（`-2.7, -0.75`）；洗衣机 / 烘干机从默认镜头完全露出。`scene-data.js`、点击热区、单词表均不动——`storage_cabinet` 仍是同一个 id。

### 10.4 回归锁

`scripts/verify-room3d-data.mjs` 新增两组断言：

1. **布局数据组**：三个 area 的 target 落在主屋范围、radius 5–12、客厅在西 / 餐厅居中 / 厨房在东；两扇门的 `z1 > z0`、宽 0.78–1.0 / 高 1.95–2.15 / 开角 1.1–1.6，且门洞落在对应卧室的家具让位带内；`room-models.js` 确实消费 `LAYOUT.doors` / `areas`；收纳柜 `x ≤ -2.5`，梳妆台 `z ≥ 0.7`、相框 `z ≥ 0.6`。
2. **页面/原生接线组**：`#areaTabs` 存在且恰好 3 个 `.area-tab`、data-area 三选一；`room-layout.js` 在 `room-models.js` 之前加载；`room-scene.js` 有 `focusArea` 与 `frame.areas`；`room-app.js` 有 `setActiveArea` / `dom.areaTabs` / 桥接 `setArea`；原生 `resolveRoomEnglishArea` 存在、`RoomEnglishCard` 引用它并调用 `app.setArea`、hypium 用例覆盖。

