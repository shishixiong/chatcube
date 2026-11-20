# 机场 3D 英语探索（airport_english）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增讲解型工具 `airport_english`——一个离线可用的 3D 机场全景，约 50 个可点实体（polyfork Airport kit 的真实 GLB 模型），点一下弹单词卡并用原生 TTS 先中文后英文朗读。

**Architecture:** Web 场景（`rawfile/airport3d/`，three r128 + 项目自带 GLTFLoader）负责 3D、点击、单词卡、词汇表与收集进度；原生 ArkTS 侧负责工具注册、参数预校验、全屏 sheet 宿主、TTS 桥与完成回执。模型以 base64 JS 文件随包分发，通过 `<script>` 注入后 `GLTFLoader.parse`，完全避开 ArkWeb 对 `resource://` XHR 的跨域封锁。

**Tech Stack:** ArkTS / ArkUI（@ComponentV2）、ArkWeb、three.js r128（全局 `THREE`）、`THREE.GLTFLoader`（r128 examples/js）、Python 3（素材下载/打包）、Node 24（GLB 冒烟验证 + 无头 Chromium 自检）。

**Spec:** `docs/superpowers/specs/2026-11-20-airport-english-design.md`

## Global Constraints

- 工具 id 固定 `airport_english`；`skill_key` 固定 `'english_vocab'`。
- `focus` 只允许：`overview` / `terminal_zone` / `apron_zone` / `runway_zone` / `hangar_zone`；缺省 `overview`。
- `words` 最多 8 个，必须是 `AIRPORT_WORD_IDS` 成员；重复值去重、空串忽略。
- 讲解型工具，**不写任何星星事件**，不新增 `StarActivityType`。
- 词表 50 个 id，必须与 `rawfile/airport3d/assets/airport-data.js`、`models-manifest.js` 三方一致（构建期校验）。
- 3D：three r128；低多边形平面着色只能用 `MeshPhongMaterial({ flatShading: true, shininess: 0, specular: 0 })`（r128 的 Lambert 不支持 flatShading）。
- 页面必须离线：所有资源在 `rawfile/airport3d/` 内，禁止运行时联网；禁止 XHR 读本地文件。
- 模型只使用 polyfork **`preview_glb`**（与正式版同几何/同蒙皮/同动画，仅无 `NORMAL`；CC BY 4.0），不得包含 `.mjs` / HD 版本；署名必须出现在 App 内与 `credits.txt`。
- `words` / `explored_count` 只统计本次 sheet 会话；回执中 `cancelled` 恒为 `false`；下拉收起按「本次词数 > 0」决定 `completed`。
- 打开顺序：只有 `focus` → 只切镜头；有 `words` → 选中 `words[0]` 并由它决定分区/lens，忽略 `focus`。
- 缺模型时删词（三处同步、总数可 < 50），**不得**用语义不相关的部件顶替；构建脚本发现词表引用缺失主模型时退出码 1。
- TTS 语速固定 `0.8`，先中文后英文；Web 侧只通过 `AirportNativeBridge` 调用。
- 场景网格：4m；跑道宽 44m；滑行道宽 16m；地面砖顶面 y=0.05；人物 1.8m。
- ArkTS 严格模式：不用解构；对象字面量需显式类型；`ForEach` 回调内不写 `const x: Foo = {...}`；`Record<string, V>` 字面量键必须加引号。
- 构建命令：`DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug`。

## Review Focus

1. **模型缺失/损坏**：任一 `models/<id>.js` 缺失或 base64 损坏时，页面不能永久停在加载页——必须显示「3D 机场没能打开」+ 词汇表入口，且词汇表/发音仍可用。
2. **低端 WebView**：WebGL 创建失败或显存不足时，`AirportApp` 必须上报 `onError`，原生切错误面板，不白屏、不卡死。
3. **坏参数**：`words` 含未知 id、超过 8 个、`focus` 越界时，handler 必须返回 `should_retry: true`，不得进入 pending。
4. **点击移动目标**：Raycaster 必须命中 GLB 内部的子 mesh（`userData.wordId` 沿父链上传），移动中的人物/车辆也要能点中。
5. **sheet 下拉收起**：`onRegisterDismissPayload` 必须在 `aboutToAppear` 就注册；下拉收起要回传本次已点开的词，不能丢成 `cancelled: true`。

---

### Task 1: 素材流水线与模型打包

**Files:**
- Create: `tools/airport-assets/word-models.json`
- Create: `tools/airport-assets/gen_manifest.py`
- Create: `tools/airport-assets/manifest.json`（生成）
- Create: `tools/airport-assets/download.py`
- Create: `tools/airport-assets/pack.py`
- Create: `tools/airport-assets/verify_glb.mjs`
- Create: `tools/airport-assets/README.md`
- Create (generated): `entry/src/main/resources/rawfile/airport3d/assets/models/<asset-id>.js`
- Create (generated): `entry/src/main/resources/rawfile/airport3d/assets/models-manifest.js`
- Create (generated): `entry/src/main/resources/rawfile/airport3d/credits.txt`

**Interfaces:**
- Produces: `window.AIRPORT_MODELS: Record<string, string>`（每个 key 是 polyfork asset id，value 是 base64 GLB）
- Produces: `window.AirportModelManifest: Array<{ id: string; file: string; wordId: string; triangles: number }>`
- Produces: `credits.txt`，每行 `<Title> by Polyfork (https://polyfork.dev/asset/<id>), CC BY 4.0`

- [ ] **Step 1: 写 word-models.json（词 → 完整 asset id）**

从 spec §5.3 词表抄 50 个词，但 **asset id 必须带 hash 后缀**（写在 `word-models.json` 里；不手抄后手改）：

```json
[
  { "wordId": "control_tower", "assets": ["control-tower-c95a65"] },
  { "wordId": "terminal",      "assets": ["terminal-structure-bay-ea2467", "terminal-facade-module-5574b6", "gate-lounge-module-5ebc23"] },
  { "wordId": "runway",        "assets": [] }
]
```

规则：
- `assets[0]` 是主模型（挂 `wordId`）；`assets[1..]` 是装饰（不挂词）。
- `runway` / `taxiway` / `apron` 的主点击目标是程序化地面，`assets` 可以为空或只放灯/砖装饰。
- 拿不准的完整 id 从 `GET https://polyfork.dev/api/kits/airport-43b137` 的 `parts` 里找。

- [ ] **Step 2: 写 gen_manifest.py**

行为：读 `word-models.json`；拉取 kit 详情（`https://polyfork.dev/api/kits/airport-43b137?compact=false` 或逐个 `/api/assets/<id>`）；校验每个 asset id 存在；从 API 取 `preview_glb`、`triangles`、`title`；写 `manifest.json`：

```json
[
  { "assetId": "control-tower-c95a65", "wordId": "control_tower", "title": "Control Tower",
    "previewUrl": "https://polyfork.dev/cdn/control-tower-c95a65-preview.glb", "triangles": 1752 }
]
```

任一 id 不存在 → 打印缺失项并退出码 1（回到 Step 1 修正）。

- [ ] **Step 3: 写 download.py**

行为：读 `manifest.json`；对每个 `previewUrl` 下载到 `tools/airport-assets/raw/<assetId>-preview.glb`；已存在且 GLB 长度与头部 `total length` 一致则跳过；每文件最多 5 次重试、每次 180s 超时；下载后校验 magic `glTF` 与 `total length === file size`。

关键函数签名：

```python
def fetch_one(asset_id: str, url: str, dest: Path) -> bool
def main() -> int   # 0 = 全部齐全；1 = 有缺失，打印缺失 id
```

- [ ] **Step 4: 写 pack.py**

行为：读 `manifest.json` + `raw/*-preview.glb`；为每个文件生成 `assets/models/<assetId>.js`：

```js
window.AIRPORT_MODELS = window.AIRPORT_MODELS || {};
window.AIRPORT_MODELS['control-tower-c95a65'] = 'Z2xURgIAAAAA...';
```

并生成 `models-manifest.js` 与 `credits.txt`。`triangles` 从 GLB JSON 的 index count / 3 计算。任一 `wordId` 非空的主模型缺失 → 退出码 1，并打印「请从 word-models.json / airport-data.js / AIRPORT_WORD_IDS 三处删掉该词」。

- [ ] **Step 5: 写 verify_glb.mjs**

用 Node 24 + 临时安装的 `three@0.128.0` + `examples/jsm/loaders/GLTFLoader.js`，逐个 `raw/*-preview.glb` 调 `loader.parse`，打印 `id meshes/ skinned/ tris/ anims`；任一解析失败退出码 1。

（安装命令写进 README：`npm --prefix tools/airport-assets install three@0.128.0`。）

- [ ] **Step 6: 生成并下载全部模型**

Run:
```bash
python3 tools/airport-assets/gen_manifest.py
python3 tools/airport-assets/download.py
```
Expected: `OK n/N`；如 CDN 卡住，重跑 `download.py` 直到补齐（已存在文件会跳过）。

- [ ] **Step 7: 冒烟验证所有 GLB**

Run: `node tools/airport-assets/verify_glb.mjs`
Expected: 每个文件一行 `OK`，最后 `ALL OK <n>`；出现 `FAIL` 则重试；仍失败则按 spec §5.3 规则**删词**并同步三处。

- [ ] **Step 8: 生成 base64 与清单**

Run: `python3 tools/airport-assets/pack.py`
Expected: `models/*.js` 与 `models-manifest.js` 生成；`du -sh entry/src/main/resources/rawfile/airport3d` ≤ 16MB。

- [ ] **Step 9: Commit**

```bash
git add tools/airport-assets entry/src/main/resources/rawfile/airport3d
git commit -m "feat(airport): bundle polyfork airport kit models as offline base64 assets"
```

---

### Task 2: Web 词表与数据一致性测试

**Files:**
- Create: `entry/src/main/resources/rawfile/airport3d/assets/airport-data.js`
- Create: `tools/airport-assets/verify_data.mjs`
- Test: `tools/airport-assets/verify_data.mjs`（本身就是测试）

**Interfaces:**
- Consumes: `models-manifest.js` 的 `window.AirportModelManifest`
- Produces: `window.AirportData = { objects: AirportWord[], byId: Record<string, AirportWord> }`
- Produces: `AirportWord` 形状：

```js
{
  id: 'runway',              // AIRPORT_WORD_IDS 成员
  word: 'runway',
  phonetic: '/ˈrʌnweɪ/',
  zh: '跑道',
  kidDefinition: '飞机起飞和降落的长长跑道',
  example: 'The plane waits on the runway.',
  category: 'places',        // places | aircraft | vehicles | people | facilities
  zone: 'runway_zone'        // 5 个 focus 之一
}
```

- [ ] **Step 1: 写失败测试 verify_data.mjs**

断言：
- `objects.length === 50`（若 Task 1 删过词，则为实际词数；同一数字必须出现在 `AIRPORT_WORD_IDS` 与 `verify_data.mjs` 里）
- id 唯一、非空
- `category` ∈ 四类
- `zone` ∈ 五区
- 每个 `word` / `phonetic` / `zh` / `kidDefinition` / `example` 非空
- 存在主模型的词，其 `id` 必须出现在 `AirportModelManifest` 的 `wordId` 里

Run: `node tools/airport-assets/verify_data.mjs`
Expected: FAIL（airport-data.js 不存在）

- [ ] **Step 2: 写 airport-data.js**

逐条填 spec §5.3 的 50 个词；`window.AirportData` 同时挂 `objects` 与 `byId`。

- [ ] **Step 3: 跑测试**

Run: `node tools/airport-assets/verify_data.mjs`
Expected: `DATA OK 50`

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/resources/rawfile/airport3d/assets/airport-data.js tools/airport-assets/verify_data.mjs
git commit -m "feat(airport): add 50-word airport vocabulary catalog with consistency check"
```

---

### Task 3: 原生预校验（TDD）

**Files:**
- Create: `entry/src/main/ets/utils/AirportEnglishValidation.ets`
- Test: `entry/src/ohosTest/ets/test/utils/AirportEnglishValidation.test.ets`

**Interfaces:**
- Produces:

```ts
export interface AirportEnglishValidationResult {
  ok: boolean
  error: string
  focus: string
  words: string[]
}

export const AIRPORT_WORD_IDS: string[] = [ /* 50 ids, 顺序同 spec §5.3 */ ]

export function resolveAirportEnglishView(focus: string): string
export function validateAirportEnglishArgs(args: string): AirportEnglishValidationResult
```

**测试运行方式：** 项目自带的纯逻辑 shim（无需 DevEco）：

```bash
.superpowers/harness/run-test.sh \
  entry/src/ohosTest/ets/test/utils/AirportEnglishValidation.test.ets \
  entry/src/main/ets/utils/AirportEnglishValidation.ets
```

- [ ] **Step 1: 写失败测试**

用例（每条一个 `it`）：
- `valid minimal`：`{"skill_key":"english_vocab"}` → `ok=true`, `focus='overview'`, `words=[]`
- `focus all`：`{"skill_key":"english_vocab","focus":"all"}` → `focus='overview'`
- `focus invalid`：`{"skill_key":"english_vocab","focus":"air_side"}` → `ok=false`
- `words dedupe`：`["runway","runway","pilot"]` → `['runway','pilot']`
- `words too many`：9 个 → `ok=false`
- `word unknown`：`["unicorn"]` → `ok=false`
- `non object`：`null` → `ok=false`
- `skill_key wrong`：`"english_vocab "` trim 后通过；`"math_counting"` 失败
- `catalog`：`AIRPORT_WORD_IDS.length === 50` 且无重复
- `resolve view`：`resolveAirportEnglishView('apron_zone') === 'apron_zone'`；`''` / `'all'` / 非法值 → `'overview'`

- [ ] **Step 2: 运行，确认失败**

Run: 上面的 `run-test.sh`
Expected: FAIL（模块不存在）

- [ ] **Step 3: 实现 AirportEnglishValidation.ets**

照 `FarmEnglishValidation.ets` 的结构，删掉 `time_of_day` / `weather` 分支；错误文案把 `farm_english` 换成 `airport_english`；`words` 合法 id 列表用 `AIRPORT_WORD_IDS`。

- [ ] **Step 4: 运行，确认通过**

Run: 上面的 `run-test.sh`
Expected: `RESULT 10 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/utils/AirportEnglishValidation.ets entry/src/ohosTest/ets/test/utils/AirportEnglishValidation.test.ets
git commit -m "feat(airport): add airport_english arg validation with unit tests"
```

---

### Task 4: Web 页面骨架与单模型渲染

**Files:**
- Create: `entry/src/main/resources/rawfile/airport3d/index.html`
- Create: `entry/src/main/resources/rawfile/airport3d/assets/airport.css`
- Create: `entry/src/main/resources/rawfile/airport3d/assets/airport-panel.css`
- Create: `entry/src/main/resources/rawfile/airport3d/assets/airport-host.css`
- Create: `entry/src/main/resources/rawfile/airport3d/assets/vendor/three.min.js`（从 `farm3d/assets/vendor/three.min.js` 复制）
- Create: `entry/src/main/resources/rawfile/airport3d/assets/vendor/GLTFLoader.js`（`https://unpkg.com/three@0.128.0/examples/js/loaders/GLTFLoader.js`）
- Create: `entry/src/main/resources/rawfile/airport3d/assets/airport-scene.js`
- Create: `entry/src/main/resources/rawfile/airport3d/assets/airport-app.js`

**Interfaces:**
- Consumes: `AIRPORT_MODELS`, `AirportModelManifest`, `AirportData`
- Produces: `window.AirportBoot`（内部引导对象，不对外）
- Produces DOM 契约（后续任务依赖这些 id）：
  - `#stageCanvas`（canvas）
  - `#loadScreen` / `#failCard`
  - `#zoneTabs`
  - `#wordCard` / `#cardWord` / `#cardPhon` / `#cardZh` / `#cardDef` / `#cardExampleText` / `#cardSpeak`
  - `#labelLayer` / `#bubbleLayer` / `#sceneToast`
  - `#vocabBtn` / `#labelsBtn` / `#resetBtn`
  - `#panel` / `#panelZone` / `#panelCount`
  - `#selftestResult`（隐藏 div，自检写结果）

- [ ] **Step 1: 建 index.html 骨架**

加载顺序：`vendor/three.min.js` → `vendor/GLTFLoader.js` → `airport-data.js` → `models-manifest.js` → 动态注入 `models/*.js`。顶栏含品牌「3D 机场 Airport」、分区标签容器、词汇表/标签/重置按钮；舞台含 canvas、加载页、失败卡。**不写**任何 `<script type="module">`。

- [ ] **Step 2: 写 CSS**

沿用 farm 的 `od-*` 布局层；机场配色：天空 `#BFE3F5` → `#F3F0E4`，草地 `#8FBF6A`，沥青 `#6C7278`，安全黄 `#E5C84A`，砖红 `#B94C34`。宿主模式 `body.host` 时隐藏 `.topbar`。

- [ ] **Step 3: 写机场引导脚本**

在 `airport-scene.js` 里实现：
- `createRenderer()`：`antialias:true`、`setPixelRatio(Math.min(devicePixelRatio,2))`、失败时 `AirportNativeBridge.onError('webgl')`。
- `createScene()`：天空渐变背景（canvas texture 或 scene.background 纯色）、HemisphereLight + DirectionalLight（无阴影）。
- `loadModels(onProgress)`：为每个模型并行插入 `<script src="assets/models/<id>.js">`（`script.onload` 即解析），全部加载后逐个 `new THREE.GLTFLoader().parse(base64ToArrayBuffer(text), '', onLoad, onError)`；每完成一个更新加载页 `装配中 n/N`。
- 先只把 `control-tower-c95a65` 放到 `(0,0,0)`，相机 `(40,30,60)` 看向塔台。
- 渲染循环 `requestAnimationFrame`。

- [ ] **Step 4: 本地打开验证**

Run:
```bash
python3 -m http.server 8765 -d entry/src/main/resources/rawfile
```
然后打开 `http://127.0.0.1:8765/airport3d/index.html`。
Expected: 加载完成后看到塔台；控制台无 `Uncaught`。

- [ ] **Step 5: 无头截图验证**

Run:
```bash
"/Users/mac/Library/Caches/ms-playwright/chromium-1255/chrome-mac-x64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing" \
  --headless=new --enable-unsafe-swiftshader --use-angle=swiftshader \
  --window-size=1280,800 --virtual-time-budget=20000 \
  --screenshot=/tmp/airport-skeleton.png \
  http://127.0.0.1:8765/airport3d/index.html
```
Expected: 生成 PNG，画面非纯色（人工打开确认有塔台）。

- [ ] **Step 5b: 验证失败路径**

`index.html?failtest=1` 时，引导脚本故意把 `AIRPORT_MODELS['control-tower-c95a65']` 改成非法 base64 再解析。Run:
```bash
"/Users/mac/Library/Caches/ms-playwright/chromium-1255/chrome-mac-x64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing" \
  --headless=new --enable-unsafe-swiftshader --use-angle=swiftshader \
  --virtual-time-budget=15000 --dump-dom \
  "http://127.0.0.1:8765/airport3d/index.html?failtest=1" | grep -c "3D 机场没能打开"
```
Expected: 输出 ≥ 1（错误面板出现，词汇表按钮存在）。

Run（模拟无 WebGL）：
```bash
"/Users/mac/Library/Caches/ms-playwright/chromium-1255/chrome-mac-x64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing" \
  --headless=new --disable-webgl --disable-3d-apis --virtual-time-budget=15000 --dump-dom \
  "http://127.0.0.1:8765/airport3d/index.html" | grep -c "3D 机场没能打开"
```
Expected: 输出 ≥ 1（`onError('webgl')` 生效，不白屏）。

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/resources/rawfile/airport3d/index.html entry/src/main/resources/rawfile/airport3d/assets
git commit -m "feat(airport): add offline web shell that loads and renders a GLB model"
```

---

### Task 5: 机场场景与五个分区镜头

**Files:**
- Modify: `entry/src/main/resources/rawfile/airport3d/assets/airport-scene.js`

**Interfaces:**
- Produces: `window.AirportScene`：

```js
{
  setView(focus),            // 'overview'|'terminal_zone'|'apron_zone'|'runway_zone'|'hangar_zone'
  focusWord(wordId),         // 相机聚焦到该词根节点
  setLabels(on),             // 显示/隐藏英文标签
  update(dt),                // 动画推进（app.js 的 raf 调用）
  raycaster: THREE.Raycaster,
  pick(clientX, clientY),    // → wordId | null
  stats()                    // → { drawCalls, triangles, meshes }
}
```

- [ ] **Step 1: 地面与标线**

世界坐标：x 东、z 南、y 上；地面 520×420。程序化平面：
- 草地 `PlaneGeometry(520,420)` y=0，颜色 `#8FBF6A`
- 跑道：中心线 z=-140，宽 44（z∈[-162,-118]），长 400（x∈[-200,200]），颜色 `#5E6469`，白色虚线中线 + 两端跑道号
- 滑行道：中心线 z=-100，宽 16，长 400，颜色 `#6C7278`，黄色中线
- 停机坪：z∈[-72,-8]，x∈[-40,140]，颜色 `#7A8084`，白色机位线
- 陆侧道路：z∈[40,56]，深灰
- 用 `THREE.MeshBasicMaterial` 或 Lambert；全部 `renderOrder` 合理，避免 z-fighting（y 依次 0.00/0.01/0.02）

- [ ] **Step 2: 摆放建筑与飞机**

按 spec §5.1 的俯视布局，用 4m 网格摆放（坐标可微调，但必须保持分区归属）：
- 航站楼：`terminal-structure-bay` ×6 + `terminal-facade-module` ×8，组成 x∈[-20,100]、z∈[-8,32] 的开南面大厅；屋顶只盖一半（切面）
- 塔台 `(110,-20)`；机库区 x∈[-220,-90]；货运棚、消防站、油罐、货机、螺旋桨机
- 停机坪：宽体机 `(20,-40)`、窄体机 `(60,-40)`、私人机 `(100,-40)`、直升机 `(130,-20)`；登机桥 ×2 连接航站楼与宽体/窄体
- 陆侧：机场酒店 `(120,60)`、立体车库 `(-40,70)`、落客雨棚 沿 z=40
- 所有主模型根节点：`root.userData.wordId = '<词 id>'`，并对所有子 mesh 设 `mesh.userData.wordId`（沿父链继承）

- [ ] **Step 3: 分区镜头**

```js
var VIEWS = {
  overview:      { target: [20, 0, -40],  position: [190, 130, 190] },
  terminal_zone: { target: [40, 3, 12],   position: [40, 30, 78] },
  apron_zone:    { target: [50, 6, -40],  position: [120, 28, 15] },
  runway_zone:   { target: [-40, 2, -140], position: [-40, 20, -50] },
  hangar_zone:   { target: [-150, 5, -20], position: [-70, 34, 45] }
};
```
`setView` 用 700ms 缓动插值相机 position/target。`#zoneTabs` 渲染 5 个标签，点击切镜头。

- [ ] **Step 4: 动效**

- 窄体机沿滑行道 x 从 180 → -180 往返，速度 4m/s，朝向随方向
- 行李列车（tug + 2 carts）绕停机坪矩形路径
- 摆渡车在航站楼与远机位之间往返
- 引导车沿滑行道单向行驶
- traveller 在航站楼内 x 10→80 往返，播放 `Walk`；其余人物 `Idle`
- 风向袋轻微摆动；旋转灯标若节点名含 `beacon`/`lamp` 则绕 y 慢转，否则跳过
- 每个蒙皮人物：`new THREE.AnimationMixer(gltf.scene)`，`clip = THREE.AnimationClip.findByName(gltf.animations, 'Idle')`；`mixer.update(dt)`

- [ ] **Step 5: 验证分区与性能**

在页面控制台执行：
```js
AirportApp.setView('runway_zone'); AirportScene.stats()
```
Expected: `stats().triangles < 250000`、`drawCalls < 200`；5 个分区都能看到对应主体。

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/resources/rawfile/airport3d/assets/airport-scene.js
git commit -m "feat(airport): compose airport scene with five camera zones and ambient motion"
```

---

### Task 6: 交互、单词卡、词汇表与自检

**Files:**
- Modify: `entry/src/main/resources/rawfile/airport3d/assets/airport-app.js`
- Modify: `entry/src/main/resources/rawfile/airport3d/index.html`（面板 DOM 已在 Task 4 建好，这里补词汇表/护照容器）

**Interfaces:**
- Produces: `window.AirportApp`：

```js
{
  setHostMode(on),
  select(wordId),
  setView(focus),
  openVocab(),
  setLabels(on),
  stats()
}
```

- Produces: `localStorage['airport.discovered.v1']` = `string[]`
- Produces: `#selftestResult` 文本：`SELFTEST PASS` 或 `SELFTEST FAIL: <reason>`

- [ ] **Step 1: 点击 → 单词卡**

`canvas` 的 `pointerup`（位移 <6px 才算点击）→ `AirportScene.pick` → `AirportApp.select(wordId)`：
- 单词卡填入 `word/phonetic/zh/kidDefinition/example`
- 相机 `focusWord(wordId)`（700ms）
- 选中圆环移到该词根节点脚下
- `AirportNativeBridge.speak(word, zh)`（Web 只调桥，不自己发声）
- 首次点开写入 `discovered`，更新 `#panelCount` 并 `onProgress(JSON.stringify(ids))`

- [ ] **Step 2: 标签与词汇表**

- `setLabels(true)`：每个词根节点上方生成 DOM 标签，每帧用 `camera.project` 投影到屏幕；超出视口隐藏。
- `openVocab()`：按 category 分组的 50 词列表，点词 = `select(id)`；底部「关于素材」显示 CC BY 4.0 署名。
- `#panel` 显示当前分区与 `已收集 N/50`。

- [ ] **Step 3: 自检模式**

URL 带 `?selftest=1` 时，等所有模型加载完成后：
- 遍历 `AirportData.objects`，逐个 `select(id)`，断言 `#cardWord.textContent === word`
- 额外点三个移动目标：`traveller`、`baggage_handler`、`follow_me_car`，断言卡片能打开（验证 Raycaster 命中子 mesh 与移动节点）
- 断言 `#panelCount` 文本包含 `AirportData.objects.length`
- 通过则 `#selftestResult.textContent = 'SELFTEST PASS'`，否则写失败原因
- 最后把 `window.__selftestDone = true`

- [ ] **Step 4: 无头自检验证**

Run:
```bash
"/Users/mac/Library/Caches/ms-playwright/chromium-1255/chrome-mac-x64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing" \
  --headless=new --enable-unsafe-swiftshader --use-angle=swiftshader \
  --virtual-time-budget=30000 --dump-dom \
  "http://127.0.0.1:8765/airport3d/index.html?selftest=1" | grep -o "SELFTEST [A-Z]*"
```
Expected: `SELFTEST PASS`

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/resources/rawfile/airport3d/assets/airport-app.js entry/src/main/resources/rawfile/airport3d/index.html
git commit -m "feat(airport): add word cards, labels, vocabulary sheet and selftest"
```

---

### Task 7: 原生卡片 AirportEnglishCard

**Files:**
- Create: `entry/src/main/ets/components/airport/AirportEnglishCard.ets`

**Interfaces:**
- Consumes: `validateAirportEnglishArgs`, `resolveAirportEnglishView`, `AIRPORT_WORD_IDS`
- Produces:

```ts
export interface AirportEnglishAnswerPayload {
  completed: boolean
  explored_count: number
  words: string[]
  focus: string
  skill_key: string
  cancelled: boolean
}

export interface AirportEnglishArgsView {
  valid: boolean
  focus: string
  words: string[]
}

export function parseAirportEnglishArgs(raw: string): AirportEnglishArgsView

@ComponentV2
export struct AirportEnglishCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}
  @Event onRequestClose: () => void = () => {}
  @Event onRegisterDismissPayload: (provider: () => string) => void = () => {}
}
```

- [ ] **Step 1: 复制 FarmEnglishCard 的骨架并改名**

桥对象 `AirportNativeBridge`，方法完全相同：`speak(text, zh)` / `stopSpeak()` / `onReady()` / `onError(reason)` / `onSelect(id, word)` / `onProgress(idsJson)`；proxy name 改为 `AirportNativeBridge`；页面 URL `resource://rawfile/airport3d/index.html`；TTS 语速 0.8；看门狗 10000ms。

- [ ] **Step 2: 调整 Header 与回执**

- 标题「3D 机场英语探索」
- 副标题：`本次 N 个 · 机场收集 D / 50`
- 按钮：`词汇表` / `我学会了`（无昼夜/天气）
- `buildPayload` 不含 `time_of_day` / `weather`；`words` / `explored_count` 只取 `sessionIds`（不是 `discoveredIds`）
- 回执矩阵（`cancelled` 恒 `false`）：
  - 点「我学会了」（≥1 词）→ `completed: true`
  - 下拉收起（≥1 词）→ `completed: true`
  - 下拉收起（0 词）→ `completed: false`
  - 「我学会了」0 词时按钮禁用
- 下拉收起 provider 返回 `JSON.stringify(buildPayload(sessionIds.length > 0, false))`

- [ ] **Step 3: 页面控制脚本**

```ts
private applyFocusWords(): void {
  // AirportApp.setHostMode(true)
  // 有 words：select(words[0])，由该词决定镜头/分区，忽略 focus
  // 无 words：setView(resolveAirportEnglishView(focus))
}
```

- [ ] **Step 4: 编译验证**

Run: 构建命令
Expected: BUILD SUCCESSFUL

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/components/airport/AirportEnglishCard.ets
git commit -m "feat(airport): add native web-host card for the 3D airport"
```

---

### Task 8: 工具注册、执行链与台账

**Files:**
- Modify: `entry/src/main/ets/utils/SearchToolIdentityUtils.ets`
- Modify: `entry/src/main/ets/config/BuiltinTools.ets`
- Modify: `entry/src/main/ets/services/ToolExecutionService.ets`
- Modify: `entry/src/main/ets/utils/LedgerExtractUtils.ets`
- Modify: `entry/src/main/ets/utils/ToolIconMapping.ets`

**Interfaces:**
- Produces: `AIRPORT_ENGLISH_TOOL_ID = 'airport_english'`
- Produces: `isAirportEnglishFunctionName(name: string): boolean`
- Produces: `handleAirportEnglish(toolCall, context): Promise<ToolResult>`

- [ ] **Step 1: 工具 id 与判定**

`SearchToolIdentityUtils.ets`：
- 在 `FARM_ENGLISH_TOOL_ID` 后加 `export const AIRPORT_ENGLISH_TOOL_ID: string = 'airport_english'`
- 加 `isAirportEnglishFunctionName`
- 把 `isAirportEnglishFunctionName` 加入 `isTeachingInteractionToolFunctionName`（或同类聚集函数，farm 所在的那个）与 `getAllBuiltinToolIds()` 的列表（后者在 BuiltinTools）

- [ ] **Step 2: BuiltinTools 注册**

照 `farm_english` 复制：
- `interface AirportEnglishArgs { focus?: string; words?: string[]; skill_key: string }`
- `class AirportEnglishExecutor`
- `createAirportEnglishToolDefinition()`：schema 的 `focus` enum 五区，`words` 描述列 50 个 id，`skill_key` 固定 `english_vocab`
- `createAirportEnglishToolConfig()`：显示名「3D 机场英语探索」
- 在 `ensureBuiltinTools`（farm 注册块之后）注册
- 在 `getAllBuiltinToolIds()` 返回数组里加 `AIRPORT_ENGLISH_TOOL_ID`

- [ ] **Step 3: ToolExecutionService**

- import `validateAirportEnglishArgs`、`AIRPORT_ENGLISH_TOOL_ID`、`isAirportEnglishFunctionName`
- 复制 `handleFarmEnglish` → `handleAirportEnglish`，删掉时间/天气校验字段；`displayName` 默认「3D 机场英语探索」
- 在分发链 farm 分支后加 `if (isAirportEnglishFunctionName(normalizedFunctionName)) { return await this.handleAirportEnglish(toolCall, context) }`

- [ ] **Step 4: 台账与图标**

- `LedgerExtractUtils.extractLedgerItemsFromTool`：加 `if (toolId === 'airport_english') return farmEnglishItems(parsed)` 同款（可抽出通用 `englishWordItems(parsed, toolId)`）
- `extractLedgerAnswerItems` 的讲解型列表加 `'airport_english'`
- `ToolIconMapping.ets`：加 `AIRPORT_KEYWORDS = ['airport_english']` 并映射到飞机图标（若现有图标集无飞机，复用 `farm` 或 `map` 的通用图标，不新增资源）

- [ ] **Step 5: 编译 + 台账测试**

Run: 构建命令
Expected: BUILD SUCCESSFUL

Run: `.superpowers/harness/run-test.sh entry/src/ohosTest/ets/test/utils/AirportEnglishValidation.test.ets entry/src/main/ets/utils/AirportEnglishValidation.ets`
Expected: 仍 10 passed（回归）

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/utils/SearchToolIdentityUtils.ets entry/src/main/ets/config/BuiltinTools.ets entry/src/main/ets/services/ToolExecutionService.ets entry/src/main/ets/utils/LedgerExtractUtils.ets entry/src/main/ets/utils/ToolIconMapping.ets
git commit -m "feat(airport): register airport_english tool and execution path"
```

---

### Task 9: ChatPage / MessageBubble 集成

**Files:**
- Modify: `entry/src/main/ets/components/MessageBubble.ets`
- Modify: `entry/src/main/ets/pages/ChatPage.ets`

**Interfaces:**
- Consumes: `AirportEnglishCard`, `AirportEnglishAnswerPayload`
- Produces: `@Event onOpenAirportEnglishSheet: (toolCall: ToolCall) => void`

- [ ] **Step 1: MessageBubble**

照 farm 的 7 处：
- import `isAirportEnglishFunctionName`
- 待答态横幅（`#stage` 前）：飞机图标 + 「3D 机场英语探索 / 点击走进机场」→ `onOpenAirportEnglishSheet(toolCall)`
- 已答回执可展开：`isSuccessfulToolStep` 分支
- `shouldRenderAirportEnglishInteractionCard`（照 `shouldRenderFarmEnglishInteractionCard`）
- 步骤内容渲染（回执词 chips）

- [ ] **Step 2: ChatPage**

照 farm：
- import card + payload
- `@Local showAirportEnglishSheet = false`、`airportEnglishToolCall`、`airportEnglishAnswered`、`airportEnglishDismissPayload`
- `onOpenAirportEnglishSheet` 回调
- `bindSheet($$this.showAirportEnglishSheet, this.AirportEnglishSheetBuilder(), {...})`，`onDisappear` 里用 provider 回传
- `AirportEnglishSheetBuilder()` 渲染 `AirportEnglishCard`

- [ ] **Step 3: 编译验证**

Run: 构建命令
Expected: BUILD SUCCESSFUL

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/components/MessageBubble.ets entry/src/main/ets/pages/ChatPage.ets
git commit -m "feat(airport): wire airport_english sheet into chat page and message bubble"
```

---

### Task 10: 助手提示词、锁定与文档

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets`
- Modify: `.claude/rules/teaching-architecture.md`
- Modify: `CLAUDE.md`
- Create: `docs/airport-3d-credits.md`

**Interfaces:**
- Consumes: `AIRPORT_ENGLISH_TOOL_ID`
- Produces: 小星老师提示词段 + kids_english 提示词段；两个锁定列表各加该 id

- [ ] **Step 1: 锁定列表**

- `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS`：在 `FARM_ENGLISH_TOOL_ID` 后加 `AIRPORT_ENGLISH_TOOL_ID`
- `KIDS_ENGLISH_LOCKED_TOOL_IDS`：在 `FARM_ENGLISH_TOOL_ID` 后加 `AIRPORT_ENGLISH_TOOL_ID`
- import 列表同步

- [ ] **Step 2: 提示词**

小星老师 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 数组里，farm 段之后加「## 3D 机场英语探索」段（照 spec 的目标/焦点/回执/复测写，明确 airport_english 不授星、机场词不要用 picture_word）。

kids_english 提示词数组里，在「②-3 农场词汇」之后加「②-4 机场词汇」一段（同样结构）。

- [ ] **Step 3: 文档**

- `.claude/rules/teaching-architecture.md`：§4 工具表加一行 `airport_english`；§2.1 kids_english 锁定子集加 `airport_english`；§12 文件清单加 `components/airport/AirportEnglishCard.ets` + `rawfile/airport3d/`
- `CLAUDE.md`：互动卡片表加一行 `AirportEnglishCard`
- `docs/airport-3d-credits.md`：逐条列出 `credits.txt` 内容 + 改动说明

- [ ] **Step 4: 编译验证**

Run: 构建命令
Expected: BUILD SUCCESSFUL

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/models/AssistantModels.ets .claude/rules/teaching-architecture.md CLAUDE.md docs/airport-3d-credits.md
git commit -m "feat(airport): lock airport_english for kids_english and 小星老师, document credits"
```

---

### Task 11: 端到端验收

**Files:** 无（只验证）

- [ ] **Step 1: 全量构建**

Run: 构建命令
Expected: BUILD SUCCESSFUL，产物 `entry/build/default/outputs/default/entry-default-signed.hap`

- [ ] **Step 2: 包体检查**

Run:
```bash
du -sh entry/src/main/resources/rawfile/airport3d
ls -la entry/build/default/outputs/default/entry-default-signed.hap
```
Expected: airport3d ≤ 16MB；HAP 增量 ≤ ~16MB（对比改动前 62MB）

- [ ] **Step 3: 无头自检回归**

Run: Task 6 Step 4 的命令
Expected: `SELFTEST PASS`

- [ ] **Step 4: 纯逻辑测试回归**

Run: Task 3 Step 2 的命令
Expected: 10 passed

- [ ] **Step 5: 人工真机清单**

在 DevEco 真机/模拟器上逐条确认 spec §12 的验收清单：
- 小星英语老师与小星老师都能调用，其它助手看不到
- 5 个分区镜头、全部词（默认 50）点击、先中文后英文朗读
- 词汇表、标签、收集护照、我学会了、下拉收起回执
- 断网可用、加载有进度、失败有错误面板
- 无星星事件产生

- [ ] **Step 6: 最终 commit（如有验收修正）**

```bash
git add -A
git commit -m "chore(airport): final acceptance fixes"
```
