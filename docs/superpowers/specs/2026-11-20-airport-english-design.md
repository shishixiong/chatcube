# 机场 3D 英语探索（airport_english）设计

**日期：** 2026-11-20
**状态：** 待评审
**范围：** 新增 `airport_english` 讲解型工具——给小星英语老师（`kids_english`）与小星老师（`default`）用的 3D 机场英语探索卡；3D 模型取自 polyfork.dev 的 Airport kit
**前置文档：** `.claude/rules/teaching-architecture.md`、`docs/superpowers/specs/2026-11-06-farm-english-3d-design.md`

---

## 1. 意图与理由

孩子学 airport / plane / pilot / luggage / runway 这类"机场"词汇时，图片和文字都太薄。农场（`farm_english`）已经证明：一个可环视、可点击、有声音的 3D 小世界，能把"点一下 → 听到中文意思 → 再听到英文单词"变成孩子愿意反复玩的探索。

机场是同一类场景里最有吸引力的一个：飞机、塔台、跑道、地勤车天然吸引孩子。本工具复用农场的交互范式（点实体 → 单词卡 → 原生 TTS → 收集护照 → 我学会了），但场景、模型、词表全部换成机场。

**为什么现在做：** polyfork.dev 的 Airport kit 免费开放了 97 个统一色板、真实米制、低多边形部件（GLB 为 CC BY 4.0），正好覆盖"机场全景"所需的建筑、飞机、车辆、人物与设施。

**成功的样子：** 孩子说"我想看飞机场"，小星英语老师调 `airport_english`，全屏展开一个能转、能点、能听发音的机场；一次课点开 3–8 个词，回执带回本次词表，老师接着用 `english_quiz` 复测并授星。

---

## 2. 目标 / 非目标

### 目标

- 新增工具 `airport_english`，讲解型、**不授星**（与 `room_english` / `city_english` / `farm_english` 一致）。
- 一个可自由环视的机场全景场景，5 个镜头分区：`overview` / `terminal_zone` / `apron_zone` / `runway_zone` / `hangar_zone`。
- 约 50 个可点击实体，每实体一张单词卡：英文、音标、中文、儿童解释、例句、原生 TTS（先中文后英文，语速 0.8）。
- 英文标签开关、词汇表、收集护照、跨会话累计收集、「我学会了」完成回执。
- 全离线：模型与代码全部打进 `rawfile/airport3d/`。
- 3D 模型忠实使用 polyfork Airport kit 的 GLB 网格（不自行重做模型），保留人物 Idle/Walk 骨骼动画与场景内移动动效。

### 非目标

- 不做登机流程剧情/任务链（用户已定：机场全景）。
- 不做昼夜/天气切换（农场有，机场 v1 不做；后续可加）。
- 不做授星、不做答题判定（星星由后续 `english_quiz` 给）。
- 不做内嵌视频、不做语音识别。
- 不使用 polyfork 的 `.mjs` 源码模块与 HD 版本（授权不允许自托管）。

### 反向目标（即使技术上成立也算失败）

- 联网才能打开，或断网白屏。
- 孩子点一个实体却听不到发音 / 打不开单词卡。
- 首屏加载超过 ~8 秒且没有任何进度提示。
- 包体增长超过 ~16MB。
- 署名缺失（CC BY 4.0 要求）。

---

## 3. 约束（已实测）

1. **ArkWeb 不能 XHR 读本地资源。** 华为官方文档明确：`resource://rawfile` 的 XHR 被 CORS 拒绝（允许的 scheme 只有 http/https/arkweb-extension/...）。因此不能 `GLTFLoader.load('...glb')`；必须把 GLB 以 base64 字符串放进 JS 文件，用 `<script src>` 加载，再 `GLTFLoader.parse(arrayBuffer)`。
2. **three 版本固定 r128（全局 `THREE`）。** 项目内 `farm3d/city3d/room3d` 都用 `three.min.js` r128。实测 three@0.128.0 的 `GLTFLoader` 能解析 polyfork 用 r185 导出的 GLB：静态模型（塔台）与蒙皮人物（traveller，7 个 skinned mesh + Idle/Walk/Run）均解析通过，无扩展依赖。
3. **r128 的 `MeshLambertMaterial` 不支持 `flatShading`。** 需要低多边形平面着色时用 `MeshPhongMaterial({ flatShading: true, shininess: 0, specular: 0 })`（项目内 `farm-models.js` 已有同名注释）。
4. **polyfork GLB 规格：** 单材质、顶点色（`COLOR_0`）、真实米制、原点在地面、Y-up、正面朝 +Z；kit 网格 4m，地面砖顶面 y=0.05，跑道宽 44m（11 块 4m），滑行道宽 16m（4 块），窄体机位 40×48m，人物 1.8m，舱门高 2.1m。
5. **使用 `preview_glb` 而不是正式 GLB。** API 的 `preview_glb` 与正式版**同几何、同三角形数、同顶点数、同蒙皮/动画**，只去掉 `NORMAL`（塔台 201KB→138KB，省 31%）；我们统一用 `MeshPhongMaterial({ flatShading: true })`，法线由 shader 导数计算，视觉一致。整套 50 词实测约 **10.3MB 原始 / 13.7MB base64**，落在 16MB 预算内。
6. **polyfork CDN 不稳定：** 单文件 20–300KB/s，偶发卡住；kit 整包 zip 需要免费账号（401），所以只能用逐文件 GLB 下载，下载脚本必须可重跑、可重试。
7. **授权：** GLB 网格为 CC BY 4.0（可自托管，需署名并说明改动）或 Polyfork 许可（不署名、不可再分发）。我们选择 **CC BY 4.0 + 署名**，在 App 内和仓库文档里保留每个资产的 credit 行。不得自托管 `.mjs` / HD。

---

## 4. 方案对比（用户已选 B）

### A. 构建期重打包（未选）

把 GLB 解码后重新量化（位置 int16、颜色调色板索引、丢弃法线），生成 ~3MB 自定义数据包，运行时自写解码器还原 `BufferGeometry`。

- 优点：包小、解析快、不依赖 GLTFLoader。
- 缺点：转换器与解码器都要自己写；蒙皮人物必须在构建期把 Idle 姿势烘成静态，人物不能动。

### B. 原样 GLB + 自带 GLTFLoader（**已选**）

每个 GLB 转成 base64 放进 `rawfile/airport3d/assets/models/<id>.js`，页面用 `<script>` 动态加载，`THREE.GLTFLoader.parse` 建场景。

- 优点：代码最少；蒙皮、骨骼动画（Idle/Walk/Run）原生可用；模型 100% 保真。
- 代价：包体约 +14–16MB，首次解析较慢，WebView 内存占用较高。用户已接受。

### C. 运行时直连 polyfork CDN（否决）

不打包、免署名，但必须联网；CDN 实测又慢又抖，断网白屏。与"离线可用"目标冲突。

---

## 5. 场景设计

### 5.1 俯视布局

```
                    ┌────────── 跑道 runway（44m 宽，东西向）──────────┐
                    │  跑道灯 · PAPI · 跑道号牌 · 风向袋（北侧草坪）      │
                    └───────────────────┬──────────────────────────────┘
                                        │ 滑行道 taxiway（16m）
        ┌──────────────┐        ┌───────┴───────────────────────────┐
        │ 机库维修区    │        │           停机坪 apron             │
        │ maintenance  │        │   ✈ 宽体  ✈ 窄体  ✈ 私人机         │
        │ hangar       │        │   登机桥×2  地勤车队  加油车        │
        │ 消防站        │        │   行李车 餐车 客梯车 摆渡车         │
        │ 货运棚        │        └───────────────┬───────────────────┘
        │ 油罐 塔台     │                        │
        └──────────────┘        ┌───────────────┴───────────────────┐
                                │       航站楼 terminal（切面）       │
                                │ 值机 · 安检 · 登机口 · 行李转盘     │
                                │ 信息屏 · 自动步道 · 扶梯           │
                                └───────────────┬───────────────────┘
                                   陆侧：落客雨棚 · 机场酒店 · 立体车库
```

- **航线/滑行**：一架窄体机沿滑行道缓慢滑行；一辆引导车（follow-me car）在机位间行驶；一列行李车（tug + 2 carts）绕停机坪；一辆摆渡车在航站楼与远机位之间往返。
- **人物**：traveller 在航站楼内 Walk，pilot / flight attendant / security officer / baggage handler 原地 Idle。全部用 GLB 自带 `Idle`/`Walk` 动画 + `AnimationMixer`。
- **静态细节**：塔台、雷达、旋转灯标（若节点名可旋转则转）、风向袋轻微摆动、跑道灯/滑行道灯、机位牌、登机桥、消防车、除冰车、清扫车等。
- **人物/车辆的词与装饰分工**：`§5.3` 词表是唯一权威。`aircraft-maintenance-engineer`、`cargo-forklift`、`crew-minivan`、`uld-container` 等只做场景装饰，不可点击、不占词 id；预算紧张时直接不放。`fire_truck` 的 zone 以词表为准（`hangar_zone`），`§5.2` 的图文描述不构成契约。
- **地面**：程序化平面（草地 / 沥青 / 混凝土 / 跑道标线），颜色取自 kit 调色板；kit 的地砖模型只少量点缀，避免上百个 draw call。

### 5.2 五个镜头分区

| focus | 镜头 | 覆盖的词 |
|---|---|---|
| `overview` | 东南高空斜俯视全机场 | 全部 |
| `terminal_zone` | 航站楼切面上方（能看到内部） | 航站楼、值机、安检、登机口、行李转盘、信息屏、自动步道、扶梯、护照亭、X 光机、旅客、安检员 |
| `apron_zone` | 停机坪低空，飞机与地勤车为前景 | 飞机、登机桥、推车、行李车、装载机、传送带车、加油车、餐车、客梯车、摆渡车、消防车、地勤人员 |
| `runway_zone` | 沿跑道方向低位 | 跑道、滑行道、跑道灯、PAPI、风向袋、引导车、灯塔、塔台 |
| `hangar_zone` | 西侧机库/维修区 | 机库、货运棚、消防站、油罐、货机、螺旋桨飞机、机务工程师、叉车 |

### 5.3 词表（50 个）

分类：places 14 / aircraft 6 / vehicles 12 / people 5 / facilities 13。

| id | 英文 | 中文 | 类别 | 分区 | 模型（polyfork asset id） |
|---|---|---|---|---|---|
| terminal | terminal | 航站楼 | places | terminal_zone | terminal-structure-bay + terminal-facade-module |
| control_tower | control tower | 塔台 | places | runway_zone | control-tower-c95a65 |
| runway | runway | 跑道 | places | runway_zone | 程序化地面 + runway-edge-light-run |
| taxiway | taxiway | 滑行道 | places | runway_zone | 程序化地面 + taxiway-edge-light-run |
| apron | apron | 停机坪 | places | apron_zone | 程序化地面 + apron-tile |
| hangar | hangar | 机库 | places | hangar_zone | maintenance-hangar-6fab99 |
| cargo_shed | cargo shed | 货运仓库 | places | hangar_zone | cargo-shed-bcb2a8 |
| fire_station | fire station | 消防站 | places | hangar_zone | airport-fire-station-92c6b7 |
| airport_hotel | airport hotel | 机场酒店 | places | overview | airport-hotel-1a1e0a |
| car_park | car park | 停车场 | places | overview | multi-storey-car-park-021465 |
| jet_bridge | jet bridge | 登机桥 | places | apron_zone | jet-bridge-4f39c0 |
| gate | gate | 登机口 | places | terminal_zone | gate-lounge-module-5ebc23 |
| check_in | check-in desk | 值机柜台 | places | terminal_zone | check-in-desk-run-b96c12 |
| baggage_carousel | baggage carousel | 行李转盘 | places | terminal_zone | baggage-reclaim-carousel-7ceef0 |
| airplane | airplane | 大飞机 | aircraft | apron_zone | widebody-airliner-ae0a5a |
| jet | jet | 喷气式飞机 | aircraft | apron_zone | narrow-body-airliner-619183 |
| turboprop | turboprop | 螺旋桨飞机 | aircraft | hangar_zone | regional-turboprop-097f26 |
| private_jet | private jet | 私人飞机 | aircraft | apron_zone | business-jet-684611 |
| cargo_plane | cargo plane | 货运飞机 | aircraft | hangar_zone | cargo-freighter-b4377e |
| helicopter | helicopter | 直升机 | aircraft | apron_zone | helicopter-9d1986 |
| pushback_tug | pushback tug | 推车 | vehicles | apron_zone | pushback-tug-8eab46 |
| baggage_tug | baggage tug | 行李牵引车 | vehicles | apron_zone | baggage-tug-fb69f7 |
| baggage_cart | baggage cart | 行李车 | vehicles | apron_zone | baggage-cart-b1bb82 |
| container_loader | container loader | 集装箱装载机 | vehicles | apron_zone | container-loader-254a74 |
| belt_loader | belt loader | 传送带车 | vehicles | apron_zone | belt-loader-3d84fd |
| fuel_truck | fuel truck | 加油车 | vehicles | apron_zone | aviation-fuel-tanker-truck-37ed29 |
| catering_truck | catering truck | 餐车 | vehicles | apron_zone | catering-truck-496150 |
| airstairs_truck | airstairs truck | 客梯车 | vehicles | apron_zone | airstairs-truck-de0f4b |
| airport_bus | airport bus | 摆渡车 | vehicles | apron_zone | apron-passenger-bus-c46aef |
| follow_me_car | follow-me car | 引导车 | vehicles | runway_zone | follow-me-car-b3c6a5 |
| fire_truck | fire truck | 消防车 | vehicles | hangar_zone | airport-crash-tender-2422ba |
| sweeper | sweeper | 清扫车 | vehicles | apron_zone | apron-sweeper-truck-937ca0 |
| pilot | pilot | 飞行员 | people | apron_zone | airline-pilot-63226a |
| flight_attendant | flight attendant | 空乘 | people | terminal_zone | flight-attendant-befaf4 |
| traveller | traveller | 旅客 | people | terminal_zone | traveller-92f20c |
| security_officer | security officer | 安检员 | people | terminal_zone | airport-security-officer-8fd38a |
| baggage_handler | baggage handler | 行李搬运工 | people | apron_zone | baggage-handler-0823f5 |
| windsock | windsock | 风向袋 | facilities | runway_zone | windsock-d5df79 |
| radar | radar | 雷达 | facilities | runway_zone | air-traffic-radar-mast-3e5642 |
| beacon | beacon | 机场灯塔 | facilities | runway_zone | rotating-airport-beacon-e1ea5a |
| runway_lights | runway lights | 跑道灯 | facilities | runway_zone | runway-edge-light-run-ebe7e1 |
| papi | PAPI | 下滑指示灯 | facilities | runway_zone | papi-unit-adc7c4 |
| sign | sign | 指示牌 | facilities | terminal_zone | overhead-wayfinding-sign-64d4e8 |
| fuel_tank | fuel tank | 储油罐 | facilities | hangar_zone | fuel-farm-tank-ed67f0 |
| floodlight | floodlight | 探照灯 | facilities | apron_zone | apron-floodlight-mast-e0d04a |
| passport_control | passport control | 护照查验 | facilities | terminal_zone | passport-control-booth-7724c6 |
| x_ray | X-ray machine | 行李安检机 | facilities | terminal_zone | x-ray-baggage-conveyor-b3d1cc |
| departures_board | departures board | 航班信息屏 | facilities | terminal_zone | departures-board-7b85c8 |
| moving_walkway | moving walkway | 自动步道 | facilities | terminal_zone | moving-walkway-run-9f078a |
| escalator | escalator | 自动扶梯 | facilities | terminal_zone | terminal-escalator-b80f37 |

> **模型 id 必须带 hash 后缀。** 上表为了可读性省略了后缀（如 `terminal-structure-bay`）；实际 manifest 必须从 `GET https://polyfork.dev/api/kits/airport-43b137` 的 `parts` 生成完整 id（如 `terminal-structure-bay-ea2467`），构建期校验每个 id 都能在 kit 响应里找到。
>
> **缺模型时不找替身。** 若某个主模型下载或解析失败，按以下顺序处理：① 重试；② 若仍失败，**删掉这个词**（同时更新 `AIRPORT_WORD_IDS`、`airport-data.js`、`models-manifest.js` 三处，词总数可以低于 50），并在 `credits.txt` 记录；**不得**用语义不相关的同 kit 部件顶替（`helicopter` 打开一张座椅是错误）。构建脚本发现主模型缺失但词表仍引用它时必须退出码 1。

---

## 6. 架构与文件

### 6.1 Web 场景（`entry/src/main/resources/rawfile/airport3d/`）

```
airport3d/
├── index.html                 # 顶栏 / 画布 / 分区标签 / 单词卡 / 词汇表 / 加载页
├── credits.txt                # 所有 GLB 的 CC BY 4.0 credit 行 + 改动说明
└── assets/
    ├── airport.css            # 页面与舞台样式（沿用 farm 的 od-* 基础层）
    ├── airport-panel.css      # 单词卡 / 词汇表 / 收集护照
    ├── airport-host.css       # 宿主模式（隐藏网页顶栏）
    ├── airport-data.js        # 50 词词表（id/word/phonetic/zh/kidDefinition/example/category/zone/model）
    ├── airport-scene.js       # 场景搭建：地面、模型实例、分区、点击/高亮、动画
    ├── airport-app.js         # UI 状态机、词汇表、标签、bridge 调用
    ├── models-manifest.js     # 生成文件：模型 id → 文件路径 + 三角面/尺寸
    ├── models/<asset-id>.js   # 生成文件：window.AIRPORT_MODELS['<id>'] = '<base64 glb>'
    └── vendor/
        ├── three.min.js       # 从 farm3d 复制（r128）
        └── GLTFLoader.js      # three@0.128.0 examples/js/loaders/GLTFLoader.js
```

- 页面加载顺序：`three.min.js` → `GLTFLoader.js` → `airport-data.js` → `models-manifest.js` → 动态注入各 `models/*.js`（并行，带进度）→ `airport-scene.js` → `airport-app.js`。
- `GLTFLoader.parse(base64ToArrayBuffer(text), '', onLoad, onError)`；每个模型解析完后 `scene.add(gltf.scene)`，`gltf.scene.traverse` 设 `castShadow`、`userData.wordId`。
- 材质：统一 `MeshPhongMaterial({ vertexColors: true, flatShading: true, shininess: 0, specular: 0 })`；蒙皮模型复用其自带材质并设 `flatShading`。
- 人物：每创建一个 `AnimationMixer(gltf.scene)`，播放 `Idle`（原地）或 `Walk`（移动人物），`mixer.update(dt)` 在渲染循环里推进。
- 点击：`Raycaster` 命中 `userData.wordId` → `AirportApp.select(id)` → 相机聚焦 + 单词卡 + `AirportNativeBridge.speak(en, zh)`。
- 选择高亮：目标对象脚下放一个半透明圆环 + 轻微脉冲（farm 同款），不做描边。
- 标签：`CSS2D` 不可用（会引入额外模块），用屏幕投影把 `Vector3` 投到 2D DOM 标签（farm 的 `label-layer` 同法）。
- 进度持久化：`localStorage['airport.discovered.v1']`（跨会话累计），`onProgress(idsJson)` 上报原生。

### 6.2 原生侧（`entry/src/main/ets/`）

| 文件 | 改动 |
|---|---|
| `utils/AirportEnglishValidation.ets`（新建） | 常量 `AIRPORT_WORD_IDS`、`AIRPORT_FOCUS_VALUES`；`validateAirportEnglishArgs`；`resolveAirportEnglishView`；`parseAirportEnglishArgs` |
| `components/airport/AirportEnglishCard.ets`（新建） | 镜像 `FarmEnglishCard`：Web 容器、`AirportNativeBridge`（speak/stopSpeak/onReady/onError/onSelect/onProgress）、Header（词汇表 + 我学会了）、SummaryView、看门狗、`onRegisterDismissPayload` |
| `config/BuiltinTools.ets` | `AirportEnglishArgs` / executor / `createAirportEnglishToolDefinition()`（schema）/ `createAirportEnglishToolConfig()` / 注册 |
| `services/ToolExecutionService.ets` | `handleAirportEnglish`（校验 → pending → Promise）+ `isAirportEnglishFunctionName` 分发 |
| `utils/SearchToolIdentityUtils.ets` | `AIRPORT_ENGLISH_TOOL_ID` + `isAirportEnglishFunctionName` + 归入教学工具判断 |
| `models/AssistantModels.ets` | `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` 与 `KIDS_ENGLISH_LOCKED_TOOL_IDS` 各加 `airport_english`；小星老师与 kids_english 提示词各加一段 |
| `utils/ToolIconMapping.ets` | `airport_english` 图标（飞机） |
| `utils/LedgerExtractUtils.ets` | `airport_english` 的 `words[]` 曝光词提取 |
| `components/MessageBubble.ets` | import、待答态横幅、已答回执渲染、step 内容渲染（7 处，照 farm） |
| `pages/ChatPage.ets` | import、`showAirportEnglishSheet`、`onOpenAirportEnglishSheet`、`bindSheet`、`AirportEnglishSheetBuilder` |
| `entry/src/ohosTest/.../AirportEnglishValidation.test.ets` | 纯函数单测：focus / words / skill_key 校验，词表 id 唯一、zone 合法 |

### 6.3 素材流水线（`tools/airport-assets/`，提交仓库）

- `manifest.json`：每个资产 id → 文件名、词 id、credit 行（`<Title> by Polyfork (https://polyfork.dev/asset/<id>), CC BY 4.0`）、改动说明。
- `download.py`：按 manifest 逐个下载 `https://polyfork.dev/cdn/<id>.glb`，支持重试/断点重跑/跳过已存在，校验 GLB 头与长度；输出到 `raw/`。
- `pack.py`：把 `raw/*.glb` 转成 `models/<id>.js`（`window.AIRPORT_MODELS['<id>'] = '<base64>'`）+ `models-manifest.js`；同时生成 `credits.txt`。
- README：一条命令跑完，说明 CDN 慢时的重试方式。

---

## 7. 数据与交互契约

### 7.1 工具参数

```json
{
  "skill_key": "english_vocab",
  "focus": "overview | terminal_zone | apron_zone | runway_zone | hangar_zone",
  "words": ["airplane", "pilot", "runway"]
}
```

- `skill_key` 固定 `english_vocab`。
- `focus` 缺省 `overview`。
- `words` ≤ 8 个，必须是 `AIRPORT_WORD_IDS` 成员；`words` 可以不传（可选）。
- 校验失败返回 `{error: 'validation_failed', should_retry: true}`（沿用现有范式）。

### 7.1.1 打开顺序（与农场一致）

| 参数 | 卡片打开后 |
|---|---|
| 只有 `focus` | 只切到该分区镜头，不自动打开任何单词卡 |
| 有 `words` | 选中 `words[0]`，镜头跟随该词；`words[0]` 属于哪个分区就切到哪个分区，**忽略 `focus`**（避免 700ms 后 focus 镜头覆盖刚选的词） |
| 两者都有且 `words[0]` 不在 `focus` 区 | 词优先（同上） |
| 都没有 | `overview` |

`words` 与 `focus` 不需要互相匹配；校验层不因二者不一致报错。

### 7.2 回执（`approvalReason`，随 ToolResult 回给 AI）

```json
{
  "completed": true,
  "explored_count": 5,
  "words": ["airplane", "pilot", "runway", "jet_bridge", "windsock"],
  "focus": "apron_zone",
  "skill_key": "english_vocab",
  "cancelled": false
}
```

- `words` / `explored_count` 只统计**本次 sheet 会话**点开的词，不是跨会话累计的 `discovered`。
- **不写星星事件**，不新增 `StarActivityType`。

**回执矩阵**（与 `FarmEnglishCard` 的 `buildDismissJson` 一致；`cancelled` 永远为 `false`）：

| 结束方式 | completed | cancelled | words |
|---|---|---|---|
| 点「我学会了」（≥1 词） | `true` | `false` | 本次会话点开的词 |
| 下拉收起（≥1 词） | `true` | `false` | 本次会话点开的词 |
| 下拉收起（0 词） | `false` | `false` | `[]` |
| 外部 stop / 工具被中断 | 不走本回执，由 handler 返回 `{cancelled: true}` 的 ToolResult | — | — |

「我学会了」在 0 词时按钮禁用，因此不存在 `completed: true` + 0 词的路径。

### 7.3 原生 → Web（`runJavaScript`）

- `AirportApp.setHostMode(true)`：隐藏网页顶栏。
- `AirportApp.select('<wordId>')`：选中并聚焦。
- `AirportApp.setView('<focus>')`：切分区镜头。
- `AirportApp.openVocab()`：打开词汇表。
- `AirportApp.setLabels(true|false)`：英文标签。

### 7.4 Web → 原生（`AirportNativeBridge`）

与 farm 完全同签名：`speak(text, zh)` / `stopSpeak()` / `onReady()` / `onError(reason)` / `onSelect(id, word)` / `onProgress(idsJson)`。

---

## 8. 视觉方向

- **色调**：天空浅蓝到地平线暖白渐变；草地 #8FBF6A 系；沥青 #6C7278；跑道/滑行道白色标线；安全黄 #E5C84A 点缀地勤车与标牌；kit 自带砖红 #B94C34 用于航站楼重点与塔台条纹。
- **形状语言**：低多边形 + 平面着色，和农场一致；不使用贴图。
- **镜头**：透视 45°，近 0.5m，远 5000m（kit 文档建议）；`overview` 相机在东南 45° 高空，能同时看到跑道、停机坪、航站楼切面。
- **字体与卡片**：复用农场单词卡结构（英文大字 + 音标 + 中文 + 儿童解释 + 例句 + 听发音），配色换成机场蓝/黄。
- **儿童端约束**：所有可点目标 ≥ 44px 屏幕投影直径（远物按镜头分区自动放大）；文案 1–3 句；不出现 markdown。

---

## 9. 性能与体积预算

| 项 | 预算 | 说明 |
|---|---|---|
| GLB 原始总量 | ≤ 11MB | 50 词对应的 ~50 个 `preview_glb`，实测约 10.3MB |
| base64 JS 总量 | ≤ 15MB | 1.33×，实测约 13.7MB |
| 首屏解析 | ≤ 8s | 分模型解析，加载页显示 `装配中 n/N`；解析后缓存到页面内存 |
| draw call | ≤ 200 | 每个 GLB 1–7 个 draw call；地面标线合并 |
| 三角形 | ≤ 250k | 主要来自 6 架飞机 + 5 个人物 + 12 辆车 |
| 内存 | ≤ 100MB WebView | 若超标，先移除人物动画的 mixer 更新（降级为静态 Idle 首帧） |

---

## 10. 授权与署名

- 所有 GLB 均为 **CC BY 4.0**；在以下位置署名：
  - `rawfile/airport3d/credits.txt`（逐条 credit + “已改动：打包为 base64、统一材质为平面着色、缩放/摆放”）。
  - App 内词汇表底部「关于素材」入口，展示 “3D 模型来自 Polyfork Airport Kit（CC BY 4.0）” + 链接。
  - `docs/airport-3d-credits.md`（仓库文档，逐条列出）。
- 不包含 `.mjs`、HD 版本、polyfork 品牌 logo。
- 素材不重新分发为独立资产包（只作为 App 内嵌资源）。

---

## 11. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| CDN 慢/断 | 模型下载失败 | 下载脚本可重跑 + 重试 + 校验长度；已下载文件跳过 |
| 14MB base64 首屏解析慢 | 孩子等待 | 分模型并行加载 + 进度条；解析结果缓存；失败模型降级为同 kit 备选 |
| GLTFLoader r128 与 r185 GLB 兼容 | 部分模型解析失败 | 已实测静态 + 蒙皮 → 通过；打包脚本对每个 GLB 跑一次 Node 解析冒烟 |
| 蒙皮人物 T-pose / 动画不自然 | 观感差 | 加载后立即 `mixer` 播 `Idle`；若仍异常，人物降级为静态网格或移除 |
| WebView 内存/性能 | 卡顿、闪退 | 关闭阴影贴图、限制像素比 `min(devicePixelRatio, 2)`、人物动画降级开关 |
| 词表/验证与模型不同步 | 点了空白 | 词表 id 与 `models-manifest` 在构建期交叉校验；缺模型直接构建失败 |

---

## 12. 验收清单

- [ ] `kids_english` 与小星老师都能调用 `airport_english`；其它助手看不到该工具。
- [ ] 坏参数（focus 越界 / words 超过 8 / 未知词）返回 `should_retry`，不渲染卡片。
- [ ] 5 个分区镜头可切换；`words` 会自动选中第一个词并聚焦。
- [ ] 50 个词全部可点、可听（先中文后英文）、可看单词卡。
- [ ] 英文标签、词汇表、收集护照、跨会话收集数正常。
- [ ] 点 ≥1 个词后「我学会了」可提交；下拉收起也能正常回执。
- [ ] 断网可完整使用。
- [ ] 首屏 < 8s（中端机），加载有进度。
- [ ] 包体增长 ≤ 16MB。
- [ ] 素材署名在 App 内可见。
- [ ] 不产生任何星星事件。
- [ ] 单测：`validateAirportEnglishArgs` 全分支通过；词表 id 唯一且 zone 合法。

---

## 13. 留给实施者的决定

- 具体相机方位/高度、地面配色微调、飞机停放角度。
- 哪些车辆/人物做移动动效（建议：滑行客机、行李列车、摆渡车、引导车、1 个行走旅客）。
- 航站楼切面的具体搭法（开哪一面、屋顶做不做玻璃）。
- 加载页的分批大小与并发数。
- 是否需要 `AirportApp.stats()` 调试口（照 farm 的 `stats()`）。
