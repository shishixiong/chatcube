# 阳光农场 3D · 昼夜 / 晴雨 + 鸡舍升级 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `farm_english` 支持 `time_of_day` / `weather` 参数，3D 农场可切换白天/晚上 × 晴天/雨天，并把鸡舍升级为有夜灯、鸡归舍、屋檐躲雨、清晨打鸣的「活点」。

**Architecture:** 分三层接线：ArkTS 纯逻辑层校验并解析参数 → 原生卡片把最终场景模式下发给 Web → `farm3d` 的 `FarmScene` / `FarmAgents` 执行天光、雨丝、鸡舍行为。场景状态两轴独立，首次应用吸附、之后平滑过渡；昼夜与天气的 auto/hold 状态在 `FarmAgents.recomputeEnvironment()` 统一重算。

**Tech Stack:** HarmonyOS ArkTS (API 23, @ComponentV2)、@ohos/hypium、ArkWeb、three.js r128（本地 UMD）、HTML/CSS/vanilla JS。

**Spec:** `docs/superpowers/specs/2026-11-12-farm-daynight-weather-coop-design.md`

## Global Constraints

- `farm_english` 仍然**不授星**；不改 `StarEventModels.ets` / `StarRewardService.ets`。
- 不新增任何图片 / 音频资源，不联网，不加定位权限。
- 50 个单词 id、5 个分区、TTS、词汇表、收集护照、台账**零改动**。
- `time_of_day` 只接受 `day` / `night`；`weather` 只接受 `sunny` / `rainy`；非法值 `should_retry`。
- 首次场景应用必须吸附（不淡入）；后续手动切换用 1.2s（昼夜）/ 1.5s（天气）插值。
- 鸡 / 公鸡的 `position / rotation / visible` 由 `FarmScene` 独占，`FarmAgents` 的睡姿列表必须跳过它们。
- 天空体材质必须 `fog: false`。
- 所有 Web JS 改动后先跑 `node --check`；ArkTS 改动后跑 `assembleHap`。
- 测试运行：`entry/src/ohosTest` 用 DevEco Studio 右键 Run；纯逻辑可用仓库内 hypium shim：
  `.superpowers/harness/run-test.sh <test.ets> <source.ets>...`

## Review Focus

- **不可见的拾取目标**：夜里舍内的鸡、雨天隐藏的蜜蜂/小鸟仍是 raycast 命中对象；点它们前方的物体不应被它们抢走，点空气不应弹单词卡。→ Task 8 的 `pickAt` + Task 9 的点击守卫。
- **夜里雨停 / 天亮雨未停**：不能把农夫/小孩/狗放回环线，也不能让马/兔子恢复巡游。→ Task 9 的 `recomputeEnvironment`。
- **雾吞掉天体**：星空/月亮/太阳在雾外，材质不关雾就等于没有夜空。→ Task 6 的 `fog:false`。
- **首次打开闪白天晴天**：必须吸附，不能从 DAY/SUNNY 淡入。→ Task 6 的 `instant` + Task 3 的 `applySceneMode`。
- **蹲在雨里的鸡**：`shelter` 点必须落在大雨棚下（局部 `z=2.55`），否则躲雨行为穿帮。→ Task 7 的前檐雨棚 + Task 8 的坐标。

---

### Task 1: 参数校验与场景解析纯函数

**Files:**
- Modify: `entry/src/main/ets/utils/FarmEnglishValidation.ets`
- Modify: `entry/src/ohosTest/ets/test/utils/FarmEnglishValidation.test.ets`

**Interfaces:**
- Produces:
  - `FarmEnglishValidationResult` 新增 `timeOfDay: string`（`'day' | 'night' | ''`）与 `weather: string`（`'sunny' | 'rainy' | ''`）
  - `export function resolveFarmTimeOfDay(arg: string, hour: number): string`
  - `export function resolveFarmWeather(arg: string): string`
  - `validateFarmEnglishArgs(args: string): FarmEnglishValidationResult`（签名不变）

- [ ] **Step 1: 写失败测试**

在 `FarmEnglishValidation.test.ets` 的 `describe('validateFarmEnglishArgs', ...)` 内追加两个用例，并新增一个 `describe('resolveFarmScene', ...)`：

```ts
it('accepts valid time_of_day and weather', 0, () => {
  const night = validateFarmEnglishArgs('{"skill_key":"english_vocab","time_of_day":"night","weather":"rainy"}')
  expect(night.ok).assertTrue()
  expect(night.timeOfDay).assertEqual('night')
  expect(night.weather).assertEqual('rainy')
  const day = validateFarmEnglishArgs('{"skill_key":"english_vocab","time_of_day":"day","weather":"sunny"}')
  expect(day.ok).assertTrue()
  expect(day.timeOfDay).assertEqual('day')
  expect(day.weather).assertEqual('sunny')
})

it('defaults scene fields and rejects illegal values', 0, () => {
  const plain = validateFarmEnglishArgs('{"skill_key":"english_vocab"}')
  expect(plain.ok).assertTrue()
  expect(plain.timeOfDay).assertEqual('')
  expect(plain.weather).assertEqual('')
  const bads = [
    '{"skill_key":"english_vocab","time_of_day":"dusk"}',
    '{"skill_key":"english_vocab","time_of_day":"DAY"}',
    '{"skill_key":"english_vocab","time_of_day":1}',
    '{"skill_key":"english_vocab","weather":"rain"}',
    '{"skill_key":"english_vocab","weather":"Rainy"}',
    '{"skill_key":"english_vocab","weather":true}'
  ]
  for (let i = 0; i < bads.length; i++) {
    expect(validateFarmEnglishArgs(bads[i]).ok).assertFalse()
  }
})

describe('resolveFarmScene', () => {
  it('resolves explicit and device-hour time of day', 0, () => {
    expect(resolveFarmTimeOfDay('night', 12)).assertEqual('night')
    expect(resolveFarmTimeOfDay('day', 23)).assertEqual('day')
    expect(resolveFarmTimeOfDay('', 5)).assertEqual('night')
    expect(resolveFarmTimeOfDay('', 6)).assertEqual('day')
    expect(resolveFarmTimeOfDay('', 12)).assertEqual('day')
    expect(resolveFarmTimeOfDay('', 17)).assertEqual('day')
    expect(resolveFarmTimeOfDay('', 18)).assertEqual('night')
    expect(resolveFarmTimeOfDay('', 23)).assertEqual('night')
  })

  it('defaults weather to sunny and honors rainy', 0, () => {
    expect(resolveFarmWeather('')).assertEqual('sunny')
    expect(resolveFarmWeather('sunny')).assertEqual('sunny')
    expect(resolveFarmWeather('rainy')).assertEqual('rainy')
    expect(resolveFarmWeather('RAINY')).assertEqual('sunny')
  })
})
```

同时更新 import：

```ts
import {
  FARM_OBJECT_IDS,
  resolveFarmEnglishView,
  resolveFarmTimeOfDay,
  resolveFarmWeather,
  validateFarmEnglishArgs
} from '../../../../main/ets/utils/FarmEnglishValidation'
```

- [ ] **Step 2: 运行测试确认失败**

Run:
```bash
.superpowers/harness/run-test.sh \
  entry/src/ohosTest/ets/test/utils/FarmEnglishValidation.test.ets \
  entry/src/main/ets/utils/FarmEnglishValidation.ets
```
Expected: FAIL（`timeOfDay` 为 undefined / `resolveFarmTimeOfDay is not a function`）。

- [ ] **Step 3: 实现校验与解析**

`FarmEnglishValidation.ets`：

- `FarmEnglishValidationResult` 增加两个字段；`fail()` 与成功返回都要带默认值。
- `validateFarmEnglishArgs` 在 `focus` 之后、`words` 之前处理两个可选字段：

```ts
let timeOfDay = ''
const timeRaw = parsed['time_of_day']
if (timeRaw !== undefined && timeRaw !== null) {
  if (typeof timeRaw !== 'string') {
    return fail('farm_english 的 time_of_day 必须是字符串：day / night')
  }
  timeOfDay = (timeRaw as string).trim()
  if (timeOfDay !== '' && timeOfDay !== 'day' && timeOfDay !== 'night') {
    return fail(`farm_english 的 time_of_day「${timeOfDay}」无效，只能是 day / night`)
  }
}

let weather = ''
const weatherRaw = parsed['weather']
if (weatherRaw !== undefined && weatherRaw !== null) {
  if (typeof weatherRaw !== 'string') {
    return fail('farm_english 的 weather 必须是字符串：sunny / rainy')
  }
  weather = (weatherRaw as string).trim()
  if (weather !== '' && weather !== 'sunny' && weather !== 'rainy') {
    return fail(`farm_english 的 weather「${weather}」无效，只能是 sunny / rainy`)
  }
}
```

成功返回 `{ ok: true, error: '', focus: focus, words: words, timeOfDay: timeOfDay, weather: weather }`。

模块底部新增：

```ts
/** 显式参数优先；缺省时 06:00–17:59 为 day，其余为 night。 */
export function resolveFarmTimeOfDay(arg: string, hour: number): string {
  const value = arg ? arg.trim() : ''
  if (value === 'day' || value === 'night') {
    return value
  }
  return hour >= 6 && hour < 18 ? 'day' : 'night'
}

/** 缺省 / 非法值回落到 sunny（校验层已挡非法值，这里做防御）。 */
export function resolveFarmWeather(arg: string): string {
  return arg && arg.trim() === 'rainy' ? 'rainy' : 'sunny'
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: 同 Step 2
Expected: `RESULT N passed, 0 failed`。

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/utils/FarmEnglishValidation.ets \
  entry/src/ohosTest/ets/test/utils/FarmEnglishValidation.test.ets
git commit -m "feat(farm): validate time_of_day and weather for farm_english"
```

---

### Task 2: 工具 schema 与 executor 回显

**Files:**
- Modify: `entry/src/main/ets/config/BuiltinTools.ets:4221-4300`

**Interfaces:**
- Consumes: Task 1 的枚举值 `day/night`、`sunny/rainy`
- Produces: `farm_english` 工具调用参数支持 `time_of_day`、`weather`；executor 回显同名字段

- [ ] **Step 1: 写失败校验命令**

Run:
```bash
node -e "const fs=require('fs');const s=fs.readFileSync('entry/src/main/ets/config/BuiltinTools.ets','utf8');const a=s.indexOf('// ===== farm_english',0);const b=s.indexOf('rawSchemaJson: string = \`{',a);const c=s.indexOf('\`',b+30);const raw=s.slice(s.indexOf('{',b),c);const j=JSON.parse(raw);if(!j.properties.time_of_day||!j.properties.weather)throw new Error('missing scene props');console.log('farm schema ok')"
```
Expected: FAIL `missing scene props`。

- [ ] **Step 2: 修改 schema 与参数接口**

`interface FarmEnglishArgs` 增加：

```ts
time_of_day?: string
weather?: string
```

`rawSchemaJson` 的属性里、`focus` 之前加：

```json
"time_of_day": {
  "type": "string",
  "enum": ["day", "night"],
  "description": "可选。这次农场是什么时间：day=白天，night=晚上。老师应先调用 get_time_info，按本地小时判断（06:00–17:59 传 day，其余传 night）。不传时卡片按设备当前时间自动判断。"
},
"weather": {
  "type": "string",
  "enum": ["sunny", "rainy"],
  "description": "可选。这次农场的天气：sunny=晴天（默认），rainy=雨天。只在孩子明确提到天气（「今天下雨了」「外面是晴天」）或课堂需要对比时才传 rainy；不知道就留空，不要编造真实天气。"
},
```

> 注意：`rawSchemaJson` 是模板字符串，描述里不要出现 ASCII 双引号；上面用「」。

executor 回显增加：

```ts
time_of_day: params.time_of_day ?? '',
weather: params.weather ?? '',
```

工具描述（`new ToolFunction(FARM_ENGLISH_TOOL_ID, '...'` 的第二个参数）末尾追加：
`You may pass time_of_day (day/night) and weather (sunny/rainy) to match the lesson context; night lights up the farm and sends the hens to the coop, rain brings rain streaks and sheltering animals. These affect the scene only — no extra words and no stars.`

- [ ] **Step 3: 校验 schema 可解析**

Run: 同 Step 1
Expected: `farm schema ok`。

- [ ] **Step 4: 编译**

Run:
```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```
Expected: `BUILD SUCCESSFUL`。

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/config/BuiltinTools.ets
git commit -m "feat(farm): expose time_of_day and weather in farm_english schema"
```

---

### Task 3: 原生卡片接线与顶栏切换

**Files:**
- Modify: `entry/src/main/ets/components/farm/FarmEnglishCard.ets`

**Interfaces:**
- Consumes: Task 1 的 `resolveFarmTimeOfDay` / `resolveFarmWeather`；Task 2 的参数
- Produces:
  - `FarmEnglishArgsView` 增加 `timeOfDay: string`、`weather: string`
  - `FarmEnglishAnswerPayload` 增加 `time_of_day: string`、`weather: string`
  - `FarmApp.setNight(v, instant)` / `FarmApp.setWeather(v, instant)` 由 Web 侧（Task 5/6）提供

- [ ] **Step 1: 写失败断言**

Run:
```bash
grep -n "weatherOn\|applySceneMode\|setWeather" entry/src/main/ets/components/farm/FarmEnglishCard.ets
```
Expected: 无输出（还没有）。

- [ ] **Step 2: 实现 args view、状态与回执**

- import 增加 `resolveFarmTimeOfDay`、`resolveFarmWeather`。
- `FarmEnglishArgsView` 增加两个字段；`createArgsView()` 初始化 `timeOfDay: ''`、`weather: ''`。
- `parseFarmEnglishArgs` 透传 `result.timeOfDay` / `result.weather`。
- `FarmEnglishAnswerPayload` 增加 `time_of_day: string`、`weather: string`。
- `@Local weatherOn: boolean = false`。
- `aboutToAppear` 在 `this.argsView = parseFarmEnglishArgs(...)` 之后：

```ts
this.nightOn = resolveFarmTimeOfDay(this.argsView.timeOfDay, new Date().getHours()) === 'night'
this.weatherOn = resolveFarmWeather(this.argsView.weather) === 'rainy'
```

- `buildPayload` 增加：

```ts
time_of_day: this.nightOn ? 'night' : 'day',
weather: this.weatherOn ? 'rainy' : 'sunny',
```

- [ ] **Step 3: 实现场景下发与天气按钮**

- `readyHandler` 内、`applyFocusWords()` 之前调用 `this.applySceneMode()`。
- 新增方法：

```ts
private applySceneMode(): void {
  const night = this.nightOn ? 'true' : 'false'
  const rain = this.weatherOn ? 'true' : 'false'
  const script = `(function(){try{var app=window.FarmApp;if(!app){return;}` +
    `app.setNight(${night},true);app.setWeather(${rain},true);}catch(e){}})();`
  this.controller.runJavaScript(script).catch((e: Error) => {
    console.error('FarmEnglishCard', `apply scene mode failed: ${e.message}`)
  })
}

private toggleWeather(): void {
  this.weatherOn = !this.weatherOn
  const on = this.weatherOn ? 'true' : 'false'
  this.runWeb(`(function(){try{var app=window.FarmApp;if(app){app.setWeather(${on});}}catch(e){}})();`)
    .catch((e: Error) => {
      console.error('FarmEnglishCard', 'set weather failed: ' + e.message)
    })
}
```

- `HeaderBar` 在夜间按钮后加一个 30×30 圆形按钮：

```ts
Button({ type: ButtonType.Circle }) {
  Text(this.weatherOn ? '☀️' : '🌧️')
    .fontSize(13)
}
.width(30)
.height(30)
.backgroundColor(withColorAlpha(this.themePrimary, '14'))
.onClick(() => {
  this.toggleWeather()
})
```

- [ ] **Step 4: 编译**

Run: Task 2 Step 4 的 `assembleHap` 命令
Expected: `BUILD SUCCESSFUL`。

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/components/farm/FarmEnglishCard.ets
git commit -m "feat(farm): apply time/weather scene mode and report it in receipt"
```

---

### Task 4: 教学提示词

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets:77,348`

**Interfaces:**
- Consumes: Task 2 的参数名
- Produces: 小星老师 / 小星英语老师在开农场前传场景参数

- [ ] **Step 1: 写失败断言**

Run:
```bash
grep -c "time_of_day" entry/src/main/ets/models/AssistantModels.ets
```
Expected: `0`。

- [ ] **Step 2: 改两段提示词**

- 第 77 行小星老师「阳光农场 3D 英语探索」段，在 `focus` 说明后追加：
  `打开前先调 get_time_info:本地 06:00-17:59 传 time_of_day:"day",其余传 "night";孩子提到天气(下雨/晴天)就传对应 weather,没提就留空(默认晴)。晚上农场会亮灯、小鸡回舍,雨天会下雨、动物躲雨,可以用这些画面引导孩子说 night / rain / sunny / shelter。`
- 第 348 行小星英语老师同类段落追加：
  `开课前先 get_time_info:06:00-17:59 传 time_of_day:"day",否则 "night";天气只从孩子的话里取,提到下雨传 weather:"rainy",否则留空。`

> 两个字符串都是单引号字面量；追加内容不要引入未转义的 ASCII 单引号。

- [ ] **Step 3: 编译**

Run: Task 2 Step 4 的 `assembleHap` 命令
Expected: `BUILD SUCCESSFUL`。

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/models/AssistantModels.ets
git commit -m "docs(farm): teach built-in teachers to pass time/weather"
```

---

### Task 5: Web 顶栏与 FarmApp API

**Files:**
- Modify: `entry/src/main/resources/rawfile/farm3d/index.html:70-78`
- Modify: `entry/src/main/resources/rawfile/farm3d/assets/farm-app.js`（`ICONS`、`state`、`cacheDom`、`applyNight`、`FarmApp`、`boot`）

**Interfaces:**
- Consumes: Task 6 的 `FarmScene.setNight(v, instant)` / `FarmScene.setWeather(v, instant)`
- Produces:
  - `FarmApp.setNight(v: boolean, instant?: boolean)`
  - `FarmApp.setWeather(v: boolean, instant?: boolean)`
  - `state.rain: boolean`

- [ ] **Step 1: 写失败断言**

Run:
```bash
grep -n "setWeather\|rainBtn" entry/src/main/resources/rawfile/farm3d/assets/farm-app.js entry/src/main/resources/rawfile/farm3d/index.html
```
Expected: 无输出。

- [ ] **Step 2: 顶栏与图标**

`index.html` 在 `nightBtn` 后加：

```html
<button class="btn" id="rainBtn" type="button" aria-pressed="false" aria-label="切换晴天/雨天">
  <svg class="ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M7 15.5a4.5 4.5 0 0 1 .6-8.96A5.5 5.5 0 0 1 18.2 8.6 3.7 3.7 0 0 1 18 15.5Z"/><path d="M8 19l-1 2M12 19l-1 2M16 19l-1 2"/></svg>
  <span class="btn-label" id="rainLabel">下雨</span>
</button>
```

同时把 `nightLabel` 的初始文案从 `黄昏` 改为 `晚上`。

`farm-app.js` 的 `ICONS` 增加：

```js
rain: '<path d="M7 15.5a4.5 4.5 0 0 1 .6-8.96A5.5 5.5 0 0 1 18.2 8.6 3.7 3.7 0 0 1 18 15.5Z"/><path d="M8 19l-1 2M12 19l-1 2M16 19l-1 2"/>',
```

- [ ] **Step 3: 状态与 API**

- `state` 增加 `rain: false`。
- `cacheDom` 的 `ids` 增加 `'rainBtn'`、`'rainLabel'`。
- `applyNight(on, instant)`：`FarmScene.setNight(state.night, !!instant)`；label 改为 `state.night ? '白天' : '晚上'`；toast 改为 `state.night ? '晚上模式：灯亮起来了' : '回到白天'`。
- 新增 `applyWeather(on, instant)`：

```js
function applyWeather(on, instant) {
  state.rain = !!on;
  if (sceneOk && global.FarmScene) global.FarmScene.setWeather(state.rain, !!instant);
  if (dom.rainBtn) dom.rainBtn.setAttribute('aria-pressed', state.rain ? 'true' : 'false');
  if (dom.rainBtn) {
    dom.rainBtn.innerHTML = icon(state.rain ? 'sun' : 'rain') +
      '<span id="rainLabel" class="btn-label">' + (state.rain ? '晴天' : '下雨') + '</span>';
    dom.rainLabel = $('rainLabel');
  }
  showToast(state.rain ? '下雨啦，小鸡躲进鸡舍里了' : '雨停啦，太阳出来喽');
}
```

- `FarmApp` 增加：

```js
setNight: function (v, instant) { apiCall(applyNight, [v, instant]); },
setWeather: function (v, instant) { apiCall(applyWeather, [v, instant]); },
```

- `bindUI` 给 `rainBtn` 绑定 `applyWeather(!state.rain)`。
- `boot()` 的场景恢复改为 `setNight(true, true)` / `setWeather(true, true)`。

- [ ] **Step 4: 语法检查**

Run:
```bash
node --check entry/src/main/resources/rawfile/farm3d/assets/farm-app.js
```
Expected: 无输出（退出码 0）。

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/resources/rawfile/farm3d/index.html \
  entry/src/main/resources/rawfile/farm3d/assets/farm-app.js
git commit -m "feat(farm3d): add weather toggle and instant scene API"
```

---

### Task 6: 场景天气核心、雨丝、天空与地面

**Files:**
- Modify: `entry/src/main/resources/rawfile/farm3d/assets/farm-scene.js`（顶部常量、`init`、`updateScene`、`applyNightColors`、`S.setNight`、`pickAt` 前的场景对象）
- Modify: `entry/src/main/resources/rawfile/farm3d/assets/farm-models.js`（地面唯一材质、云材质导出）

**Interfaces:**
- Consumes: `FarmApp` 下发
- Produces:
  - `S.setNight(on: boolean, instant?: boolean)`
  - `S.getNight(): boolean`
  - `S.setWeather(on: boolean, instant?: boolean)`
  - `S.getWeather(): boolean`
  - `built.groundMat`、`built.cloudMats`

- [ ] **Step 1: 写失败断言**

Run:
```bash
grep -n "setWeather\|rainTarget\|fog: false" entry/src/main/resources/rawfile/farm3d/assets/farm-scene.js
```
Expected: 无输出。

- [ ] **Step 2: 模型侧导出**

`farm-models.js`：

- 地面：`var ground = new THREE.Mesh(new THREE.PlaneGeometry(140, 110), material(C.grass, { unique: true }));`
- 地面材质：`ground.material.specular = new THREE.Color(0x9FB4C4);`（默认高光为 0，雨天 `shininess` 才看得出来）
- 云：`var cloudMats = [];` 在创建每朵云后 `cloudMats.push(cloud.children[0].material);`
- `return` 对象增加 `groundMat: ground.material, cloudMats: cloudMats`。

- [ ] **Step 3: 场景常量与状态**

`farm-scene.js` 顶部增加：

```js
var RAIN_DAY = {
  sky: 0x9AA9B4, fog: 0x9AA9B4, hemiSky: 0xB9C6CC, hemiGround: 0x7B8668,
  hemiI: 0.50, dirColor: 0xC9D4DC, dirI: 0.35
};
var RAIN_NIGHT = {
  sky: 0x1E2230, fog: 0x232838, hemiSky: 0x515A70, hemiGround: 0x2B3428,
  hemiI: 0.26, dirColor: 0x9AA6C4, dirI: 0.12
};
var RAIN_COUNT = 700;
var RAIN_AREA_X = 70;
var RAIN_AREA_Z = 55;
var RAIN_TOP = 38;
```

状态变量区增加 `var rain = 0; var rainTarget = 0;`，以及 `rainMesh`、`rainDrops`、`rainMaterial`、`starField`、`sunDisc`、`moonDisc`。

- [ ] **Step 4: 创建雨与天体**

`init` 内、`applyNightColors(0)` 前后：

- `createRain()`：`BufferGeometry` + `Float32Array(RAIN_COUNT * 6)`；`LineBasicMaterial({ color: 0xCFE0EC, transparent: true, opacity: 0, depthWrite: false })`；每条雨滴 `{ x, y, z, speed, len }`，`x = (Math.random() - 0.5) * 2 * RAIN_AREA_X`、`z` 同理、`y = Math.random() * RAIN_TOP`、`speed = 24 + Math.random() * 8`、`len = 0.55`；`rainMesh.frustumCulled = false; rainMesh.visible = false; scene.add(rainMesh)`。
- `createSkyBodies()`：
  - 星空：`BufferGeometry` 500 个位置，均匀分布在上半球半径 420；`PointsMaterial({ color: 0xFFFFFF, size: 1.6, transparent: true, opacity: 0, depthWrite: false, fog: false })`。
  - 太阳：`SphereGeometry(12, 12, 10)` + `MeshBasicMaterial({ color: 0xFFF2C4, fog: false })`，位置 `(180, 160, -240)`。
  - 月亮：`SphereGeometry(9, 12, 10)` + `MeshBasicMaterial({ color: 0xF6F1D5, fog: false })`，位置 `(-180, 150, -240)`。
  - 全部 `scene.add`，初始 `visible = false`。
- 把 `applyNightColors(0)` 改为 `applySceneColors(0, 0)`。

- [ ] **Step 5: 统一场景配色**

把 `applyNightColors(n)` 替换为 `applySceneColors(n, r)`：

```js
function lerpC(a, b, t) { return a.clone().lerp(b, t); }
function applySceneColors(n, r) {
  if (!built) return;
  var rainPal = n > 0.5 ? RAIN_NIGHT : RAIN_DAY;
  var sky = lerpC(daySkyColor, nightSkyColor, n).lerp(new THREE.Color(rainPal.sky), r);
  var fog = lerpC(dayFogColor, nightFogColor, n).lerp(new THREE.Color(rainPal.fog), r);
  scene.background.copy(sky);
  scene.fog.color.copy(fog);
  scene.fog.near = 110 - 20 * r;
  scene.fog.far = 310 - 90 * r;
  hemi.color.copy(lerpC(dayHemiSky, nightHemiSky, n).lerp(new THREE.Color(rainPal.hemiSky), r * 0.75));
  hemi.groundColor.copy(lerpC(dayHemiGround, nightHemiGround, n).lerp(new THREE.Color(rainPal.hemiGround), r * 0.75));
  hemi.intensity = (DAY.hemiI + (NIGHT.hemiI - DAY.hemiI) * n) * (1 - 0.28 * r);
  dir.color.copy(lerpC(dayDir, nightDir, n).lerp(new THREE.Color(rainPal.dirColor), r * 0.7));
  dir.intensity = (DAY.dirI + (NIGHT.dirI - DAY.dirI) * n) * (1 - 0.65 * r);
  for (var i = 0; i < built.windowMats.length; i++) built.windowMats[i].emissiveIntensity = n * 1.15;
  for (var j = 0; j < built.lampMats.length; j++) built.lampMats[j].emissiveIntensity = n * 1.5;
  if (built.coopLamp) built.coopLamp.intensity = 6.5 * n * (1 - 0.25 * r);
  if (built.groundMat) {
    built.groundMat.color.copy(new THREE.Color(0x8FBF6A).lerp(new THREE.Color(0x5E8347), r * 0.7));
    built.groundMat.shininess = 18 * r;
  }
  if (built.cloudMats) {
    for (var c = 0; c < built.cloudMats.length; c++) {
      built.cloudMats[c].color.copy(new THREE.Color(0xFFFDF6).lerp(new THREE.Color(0x8E99A3), r * 0.85));
      built.cloudMats[c].opacity = 0.92 + 0.05 * r;
    }
  }
  if (built.puddleMat) built.puddleMat.opacity = 0.35 * r;
  starField.visible = n > 0.02 && r < 0.5;
  starField.material.opacity = 0.9 * n * (1 - r);
  sunDisc.visible = n < 0.5 && r < 0.55;
  moonDisc.visible = n > 0.05 && r < 0.6;
  if (built.bee) built.bee.visible = r < 0.5;
}
```

- [ ] **Step 6: 雨丝与水洼更新**

`updateScene(dt, t)` 中：

- 雨强插值：`if (rain !== rainTarget) { var step = dt / 1.5; ... applySceneColors(night, rain); }`
- 夜间插值保持 1.2s，但改为调用 `applySceneColors(night, rain)`。
- 雨丝：

```js
if (rain < 0.01) {
  rainMesh.visible = false;
} else {
  rainMesh.visible = true;
  rainMaterial.opacity = 0.55 * rain;
  for (var ri = 0; ri < RAIN_COUNT; ri++) {
    var d = rainDrops[ri];
    d.y -= d.speed * dt;
    if (d.y < 0) d.y = RAIN_TOP;
    var idx = ri * 6;
    var pos = rainMesh.geometry.attributes.position.array;
    pos[idx] = d.x; pos[idx + 1] = d.y; pos[idx + 2] = d.z;
    pos[idx + 3] = d.x - 0.12; pos[idx + 4] = d.y + d.len + 0.35 * rain; pos[idx + 5] = d.z;
  }
  rainMesh.geometry.attributes.position.needsUpdate = true;
}
```

- 萤火虫：`built.fireflyMat.opacity = night * 0.9 * (1 - rain)`，`visible = night > 0.05 && rain < 0.5`。
- 水洼（`createPuddles()` 一次创建 6 个 `CircleGeometry` 扁平圆盘 + 一个共享 `MeshBasicMaterial({ color: 0xBFD8E8, transparent: true, opacity: 0, depthWrite: false })`，`built.puddleMat` 指向它）。

- [ ] **Step 7: API**

```js
S.setNight = function (on, instant) {
  var next = on ? 1 : 0;
  var changed = next !== nightTarget;
  nightTarget = next;
  if (instant) { night = nightTarget; applySceneColors(night, rain); }
  if (changed && global.FarmAgents && global.FarmAgents.isReady && global.FarmAgents.isReady() && global.FarmAgents.onNightChange) {
    global.FarmAgents.onNightChange(!!on);
  }
};
S.setWeather = function (on, instant) {
  var next = on ? 1 : 0;
  var changed = next !== rainTarget;
  rainTarget = next;
  if (instant) { rain = rainTarget; applySceneColors(night, rain); }
  if (changed && global.FarmAgents && global.FarmAgents.isReady && global.FarmAgents.isReady() && global.FarmAgents.onWeatherChange) {
    global.FarmAgents.onWeatherChange(!!on);
  }
};
S.getWeather = function () { return rainTarget > 0.5; };
```

- [ ] **Step 8: 语法检查**

Run:
```bash
node --check entry/src/main/resources/rawfile/farm3d/assets/farm-scene.js
node --check entry/src/main/resources/rawfile/farm3d/assets/farm-models.js
```
Expected: 无输出。

- [ ] **Step 9: Commit**

```bash
git add entry/src/main/resources/rawfile/farm3d/assets/farm-scene.js \
  entry/src/main/resources/rawfile/farm3d/assets/farm-models.js
git commit -m "feat(farm3d): add rain, night sky and scene color blending"
```

---

### Task 7: 鸡舍建模与夜灯

**Files:**
- Modify: `entry/src/main/resources/rawfile/farm3d/assets/farm-models.js:249-257`（`makeCoop`）
- Modify: `entry/src/main/resources/rawfile/farm3d/assets/farm-models.js`（`buildAll` 的 coop 注册与 return）

**Interfaces:**
- Consumes: 现有 `mesh` / `box` / `gable` / `windowMaterial` / `lampMaterial` 辅助
- Produces: `built.coopLamp`（`THREE.PointLight`）、鸡舍窗/门/灯的 `windowMats` / `lampMats`

- [ ] **Step 1: 写失败断言**

Run:
```bash
grep -n "coopLamp" entry/src/main/resources/rawfile/farm3d/assets/farm-models.js
```
Expected: 无输出。

- [ ] **Step 2: 重写 makeCoop**

用下面的关键尺寸重写（所有坐标是鸡舍局部坐标，`z+` 为正面）：

- 底座：`box(5.0, 0.24, 3.9)` at `(0, 0.12, 0)`
- 后墙：`box(4.8, 2.1, 0.14)` at `(0, 1.17, -1.78)`
- 侧墙：`box(0.14, 2.1, 3.56)` at `(±2.4, 1.17, 0)`
- 正面墙两段：门洞宽 1.5 → `box(1.55, 2.1, 0.14)` at `(±1.62, 1.17, 1.85)`；门楣 `box(1.5, 0.6, 0.14)` at `(0, 1.9, 1.85)`
- 屋顶：`box(3.0, 0.14, 4.0)` at `(±1.35, 2.6, 0)` + `rz = ±0.5`；屋脊 `box(0.2, 0.2, 4.05)` at `(0, 3.23, 0)`
- 山墙三角：正面 / 背面各一块，底边 `y=2.2`、顶点 `y=3.22`、`z=±1.78`
- 门内暗腔：`box(1.45, 1.5, 0.06)` at `(0, 0.95, 1.8)`；门板暖光：`lampMaterial()` + `box(1.35, 1.4, 0.03)` at `(0, 0.95, 1.84)`
- 侧窗（左侧）：窗芯 `windowMaterial()` + `box(0.9, 0.9, 0.06)` at `(-2.48, 1.5, -0.2)`；深色窗框 + 十字窗棂（4 根细木条）
- **前檐雨棚**：`box(4.4, 0.12, 1.75)` at `(0, 2.15, 2.6)` + `rx = 0.16`；立柱 `box(0.12, 2.0, 0.12)` at `(±2.0, 1.0, 3.1)`
- 坡道：`box(1.5, 0.08, 2.2)` at `(0, 0.35, 2.9)` + `rx = -0.2`；3 根横木条
- 栖木：`box(2.6, 0.1, 0.12)` at `(0, 0.55, 2.05)`
- 食槽：`box(1.4, 0.25, 0.5)` at `(1.3, 0.18, 2.7)`
- 稻草：8 个 `box(0.3–0.7, 0.02, 0.1)`，围绕坡道随机
- 舍内吊灯：`lampMaterial()` + `sph(0.2)` at `(0, 2.05, 0.4)`；`var lamp = new THREE.PointLight(0xFFB45E, 0, 7, 2); lamp.position.set(0, 2.0, 0.4); g.add(lamp); g.userData.coopLamp = lamp;`

`register('chicken_coop', coop, 4.2)` 保持不变。

- [ ] **Step 3: buildAll 导出 coopLamp**

在 `var coop = placeFromLayout('chicken_coop', makeCoop());` 之后保留引用，`return` 对象增加：

```js
coopLamp: coop.userData.coopLamp,
```

- [ ] **Step 4: 语法检查**

Run: `node --check entry/src/main/resources/rawfile/farm3d/assets/farm-models.js`
Expected: 无输出。

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/resources/rawfile/farm3d/assets/farm-models.js
git commit -m "feat(farm3d): upgrade chicken coop model with porch and night lamp"
```

---

### Task 8: 鸡的归舍 / 躲雨 / 打鸣与拾取可见性

**Files:**
- Modify: `entry/src/main/resources/rawfile/farm3d/assets/farm-scene.js`（`pickAt:344-363`、`buildCoopBirdRoutine:1095-1143`、`updateCoopBirds:1145-1277`、`S.setCoopBirdsAuto:1280-1286`）

**Interfaces:**
- Consumes: Task 6 的 `nightTarget` / `rainTarget`
- Produces:
  - `updateCoopBirds` 新增状态 `toShelter` / `shelter`
  - `S.setCoopBirdsAuto(on: boolean)` 只写标志
  - `FarmAgents.trigger('rooster_crow')` 由场景在出舍后调用

- [ ] **Step 1: 写失败断言**

Run:
```bash
grep -n "toShelter\|pendingCrow\|visible === false" entry/src/main/resources/rawfile/farm3d/assets/farm-scene.js
```
Expected: 无输出。

- [ ] **Step 2: 拾取跳过不可见祖先**

把 `pickAt` 的命中处理改为遍历 `hits`：

```js
for (var hi = 0; hi < hits.length; hi++) {
  var obj = hits[hi].object;
  var visible = true;
  var walk = obj;
  while (walk) {
    if (walk.visible === false) { visible = false; break; }
    walk = walk.parent;
  }
  if (!visible) continue;
  while (obj) {
    if (obj.userData && obj.userData.wordId) { id = obj.userData.wordId; target = obj; break; }
    obj = obj.parent;
  }
  if (id) { point = hits[hi].point; break; }
}
```

- [ ] **Step 3: 鸡舍 routine 增加 shelter 与强制模式**

- `buildCoopBirdRoutine` 为每只鸡增加：
  - `shelter: localPoint(ids[i] === 'chicken' ? -1.15 : 1.15, 2.55)`
  - `state: 'wait'` 等现有字段不变
  - `forceDelay: i * 0.8`（入夜时错开进舍）
- `updateCoopBirds` 开头计算：
```js
var forceNight = nightTarget > 0.5;
var forceRain = !forceNight && rainTarget > 0.5;
if (forceNight && !wasForceNight) {
  for (var fi = 0; fi < coopBirdRoutines.length; fi++) {
    coopBirdRoutines[fi].forceDelay = fi * 0.8;
  }
}
wasForceNight = forceNight;
```
（新增模块级 `wasForceNight = false`；这样每天晚上都会重新错开，而不是只有第一晚。）
- 每只 routine 先处理强制模式，再执行原有 `if (!coopBirdAuto) return;` 的自由巡游：

```
if (forceNight) {
  if (r.state === 'inside') { root.visible = false; continue; }
  if (r.state !== 'toCoop' && r.state !== 'enter') {
    if (r.forceDelay > 0) { r.forceDelay -= dt; continue; }
    r.target = r.stage; r.faceYaw = ...; r.state = 'toCoop';
  }
  // 落到下面的 walk/toCoop 分支
} else if (forceRain) {
  if (r.state === 'inside') { 触发 exit；continue; }
  if (r.state !== 'toShelter' && r.state !== 'shelter' && r.state !== 'exit') {
    r.target = r.shelter; r.faceYaw = ...; r.state = 'toShelter';
  }
} else {
  if (r.state === 'shelter') { r.state = 'wait'; r.timer = 0.5; root.rotation.x = 0; }
  if (r.state === 'inside') { 触发 exit；continue; }
}
if (!coopBirdAuto && !forceNight && !forceRain) continue;
if (reduceMotion && !forceNight && !forceRain) { resetCoopBird(r); continue; }
```

- 行走分支把 `'walk' || 'toCoop'` 扩展为 `'walk' || 'toCoop' || 'toShelter'`；到达目标时：
  - `toCoop`：走原有进门补间
  - `toShelter`：`r.state = 'shelter'; root.rotation.x = 0.18;`
- 新增 `shelter` 分支：`root.rotation.x = 0.18; root.rotation.z = reduceMotion ? 0 : Math.sin(now * 18 + cfg.phase) * 0.012; coopLegsRest(cfg);`
- 新增 `startCoopExit(r)` 辅助，用于天亮 / 雨停时立即出舍：

```js
function startCoopExit(r) {
  r.root.visible = true;
  r.root.position.set(r.door.x, r.baseY, r.door.z);
  r.root.scale.setScalar(0.58);
  r.root.rotation.set(0, r.faceYaw, 0);
  r.fromX = r.door.x; r.fromZ = r.door.z;
  r.toX = r.stage.x; r.toZ = r.stage.z;
  r.travelT = 0; r.travelDur = 0.7;
  r.state = 'exit';
}
```

- 到达门口前若 `coopIsBusy(r)` 且 `!forceNight`，保持原逻辑；强制入夜时允许两只先后进入（`forceDelay` 已错开）。
- `S.setCoopBirdsAuto` 删除内部 `for ... resetCoopBird`，只保留 `coopBirdAuto = !!on; return true;`。
- 公鸡打鸣：routine 增加 `roostedForNight: boolean`。强制入夜并进入 `inside` 时置 `true`；出舍补间完成、`state = 'wait'` 后，若 `r.id === 'rooster' && r.roostedForNight && !rainTarget && !reduceMotion`，设置 `pendingCrow = true` 并清掉 `roostedForNight`。自由巡游的普通进舍 / 出舍**不**打鸣。`updateScene` 末尾（或 `updateCoopBirds` 末尾）执行：
```js
if (pendingCrow && global.FarmAgents && global.FarmAgents.isStoryActive &&
    !global.FarmAgents.isStoryActive() && global.FarmAgents.trigger) {
  pendingCrow = false;
  global.FarmAgents.trigger('rooster_crow');
}
```
（Task 9 提供 `A.isStoryActive`；Task 8 先按这个签名写，Task 9 落地。）

- [ ] **Step 4: 语法检查**

Run: `node --check entry/src/main/resources/rawfile/farm3d/assets/farm-scene.js`
Expected: 无输出。

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/resources/rawfile/farm3d/assets/farm-scene.js
git commit -m "feat(farm3d): roost at night, shelter from rain, skip invisible picks"
```

---

### Task 9: FarmAgents 环境重算与雨姿

**Files:**
- Modify: `entry/src/main/resources/rawfile/farm3d/assets/farm-agents.js`（`buildAgents`、`releaseResources`、`A.update`、`A.interact`、`onNightChange`、新增 `onWeatherChange` / `recomputeEnvironment` / `applyRainPose`）

**Interfaces:**
- Consumes: `host.setHorseAuto` / `setRabbitAuto` / `setCoopBirdsAuto` / `holdActor`
- Produces:
  - `A.onWeatherChange(on: boolean)`
  - `A.isRaining(): boolean`
  - `A.isStoryActive(): boolean`
  - `recomputeEnvironment()`

- [ ] **Step 1: 写失败断言**

Run:
```bash
grep -n "onWeatherChange\|recomputeEnvironment\|applyRainPose" entry/src/main/resources/rawfile/farm3d/assets/farm-agents.js
```
Expected: 无输出。

- [ ] **Step 2: 鸡从睡姿列表移除**

`buildAgents` 收集 `sleepList` 的两处都要跳过鸡舍鸟：

```js
// idles 循环里，makeSleepAgent 之后
if (rec.root.userData && rec.root.userData.coopBird) continue;
// agentOrder 兜底循环里，push 之前
if (agentOrder[k].root.userData && agentOrder[k].root.userData.coopBird) continue;
```

- [ ] **Step 3: 统一环境重算**

新增：

```js
var rainOn = false;
var rainK = 0;
var wasRainPose = false;

function recomputeEnvironment() {
  var held = nightOn || rainOn;
  if (host.setHorseAuto) host.setHorseAuto(!nightOn && !rainOn);
  if (host.setRabbitAuto) host.setRabbitAuto(!nightOn && !rainOn);
  if (host.setCoopBirdsAuto) host.setCoopBirdsAuto(!nightOn && !rainOn);
  host.holdActor('farmer', held);
  host.holdActor('child', held);
  host.holdActor('dog', held);
}
```

- `releaseResources` 的 `setCoopBirdsAuto(!nightOn)` 改为 `recomputeEnvironment()`。
- `onNightChange` 改为：更新 `nightOn` → `cancelStory()` → `recomputeEnvironment()` → 夜间 / 天亮气泡；**删除** `startStory('rooster_crow')`；保留现有「入夜把兔子拉回 `basePos` / `baseRot`」的重置代码。
- 新增 `A.onWeatherChange`：更新 `rainOn` → `cancelStory()` → `recomputeEnvironment()` → 气泡（雨天「下雨啦，大家躲一躲。」/ 雨停「雨停啦」）。锚点优先 `agents.cat || agents.chicken || agents.rabbit`。
- **雨天暂停自动小剧场**：`tick()` 的早退条件从 `if (nightOn || host.isReduceMotion()) return;` 改为 `if (nightOn || rainOn || host.isReduceMotion()) return;`，避免 `grandma_feed` / `chicken_peck` 在雨里把鸡从屋檐下拉走。手动点击非鸡动物仍可播放反应。
- `A.isRaining = function(){ return rainOn; };`
- `A.isStoryActive = function(){ return !!story; };`

- [ ] **Step 4: 雨姿**

在 `A.update` 的睡姿处理之后：

```js
var wantRain = rainOn && !nightOn;
if (wantRain) rainK = Math.min(1, rainK + realDt / 0.8);
else rainK = Math.max(0, rainK - realDt / 0.8);
if (rainK > 0 && !nightOn) { applyRainPose(rainK, t); wasRainPose = true; }
else if (wasRainPose && !nightOn) { restoreRainPose(); wasRainPose = false; }
```

`applyRainPose(k, t)` 按 `a.idle.kind`：

- `cow` / `sheep` / `horse` / `goat`：`head.rotation.x = baseHeadX + 0.3 * k`；`root.position.y = basePos.y - 0.03 * k`；`root.rotation.z = baseRot.z + Math.sin(t * 6 + phase) * 0.01 * k`
- `pig`：`head + 0.22 * k`
- `cat` / `lazy_cat` / `rabbit` / `rabbit_graze`：`head + 0.2 * k`；兔子耳朵后压 `±(0.3 + 0.2 * k)`
- `dog` / `farmer` / `child` / `grandma` / `walk`：`root.rotation.x = baseRot.x + 0.05 * k`；`root.position.y = basePos.y - 0.02 * k`
- `bee` / `bird`：`root.visible = k < 0.5`（与场景的 bee 隐藏重复无害）
- `chicken` / `rooster` / `duck` / `goose`：跳过（鸡由场景接管，鸭鹅照常）

`restoreRainPose()` 恢复 `head.rotation.x = baseHeadX`、`root.rotation.x/z = baseRot.x/z`、`root.position.y = basePos.y`（`!actorId` 时）、`root.visible = true`。

- [ ] **Step 5: 点击守卫**

`A.interact` 开头：

```js
if (id === 'chicken' || id === 'rooster' || id === 'grandma') {
  if (rainOn) {
    showBubble('click:' + id, agentFor(id, root) || agents.chicken || agents.rooster,
      '我在躲雨呢。', 'I am hiding from the rain.', 2600);
    return true;
  }
  if (nightOn) return false;
}
```

`grandma` 也要挡，因为 `grandma_feed` 小剧场会把鸡一起拉出来啄食。

- [ ] **Step 6: dispose 复位**

`A.dispose` 增加 `rainOn = false; rainK = 0; wasRainPose = false;`。

- [ ] **Step 7: 语法检查**

Run: `node --check entry/src/main/resources/rawfile/farm3d/assets/farm-agents.js`
Expected: 无输出。

- [ ] **Step 8: Commit**

```bash
git add entry/src/main/resources/rawfile/farm3d/assets/farm-agents.js
git commit -m "feat(farm3d): recompute environment and add rain shelters for animals"
```

---

### Task 10: 集成验证与文档

**Files:**
- Modify: `CLAUDE.md`（farm_english 行）
- Modify: `.claude/rules/teaching-architecture.md`（§4 工具表 farm_english 行 / 场景说明）
- Create: `scripts/verify-farm3d-scene.mjs`（静态不变量检查）

**Interfaces:**
- Consumes: Task 1–9 全部产物
- Produces: 可重复的 CLI 验证 + 文档同步

- [ ] **Step 1: 写静态不变量脚本**

`scripts/verify-farm3d-scene.mjs` 读取三个 JS 文件并断言：

```js
import fs from 'node:fs'
const root = 'entry/src/main/resources/rawfile/farm3d/assets/'
const scene = fs.readFileSync(root + 'farm-scene.js', 'utf8')
const models = fs.readFileSync(root + 'farm-models.js', 'utf8')
const agents = fs.readFileSync(root + 'farm-agents.js', 'utf8')

const checks = [
  ['sky bodies ignore fog', /fog:\s*false/.test(scene)],
  ['rain API exists', /S\.setWeather\s*=/.test(scene)],
  ['pick skips invisible ancestors', /visible\s*===\s*false/.test(scene)],
  ['coop lamp exported', /coopLamp/.test(models)],
  ['porch roof present', /4\.4,\s*0\.12,\s*1\.75/.test(models)],
  ['setCoopBirdsAuto no teleport', !/S\.setCoopBirdsAuto[\s\S]{0,200}resetCoopBird/.test(scene)],
  ['environment recompute', /recomputeEnvironment/.test(agents)],
  ['rain change hook', /onWeatherChange/.test(agents)],
  ['coop birds excluded from sleep', /coopBird\)\s*continue|coopBird\).*continue/.test(agents)]
]
let failed = 0
for (const [name, ok] of checks) {
  console.log((ok ? 'PASS ' : 'FAIL ') + name)
  if (!ok) failed++
}
process.exit(failed ? 1 : 0)
```

- [ ] **Step 2: 跑全部语法与静态检查**

Run:
```bash
node --check entry/src/main/resources/rawfile/farm3d/assets/farm-scene.js
node --check entry/src/main/resources/rawfile/farm3d/assets/farm-models.js
node --check entry/src/main/resources/rawfile/farm3d/assets/farm-agents.js
node --check entry/src/main/resources/rawfile/farm3d/assets/farm-app.js
node scripts/verify-farm3d-scene.mjs
```
Expected: 四个 `node --check` 无输出；脚本全 `PASS`，退出码 0。

- [ ] **Step 3: 跑纯逻辑测试**

Run:
```bash
.superpowers/harness/run-test.sh \
  entry/src/ohosTest/ets/test/utils/FarmEnglishValidation.test.ets \
  entry/src/main/ets/utils/FarmEnglishValidation.ets
```
Expected: `RESULT N passed, 0 failed`。

- [ ] **Step 4: 编译 HAP**

Run: Task 2 Step 4 的 `assembleHap` 命令
Expected: `BUILD SUCCESSFUL`。

- [ ] **Step 5: 更新文档**

- `CLAUDE.md` 的 `farm_english` 行补：`time_of_day` / `weather` 两参数、鸡舍夜灯/归舍/躲雨、雨天动物就地避雨。
- `.claude/rules/teaching-architecture.md` §4 表格的 `farm_english` 行补同样内容，并在 §2.1 `kids_english` 工具子集说明里保持 `farm_english` 不变。

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md .claude/rules/teaching-architecture.md scripts/verify-farm3d-scene.mjs
git commit -m "docs(farm3d): document day/night weather and verify scene invariants"
```

---

### Task 11: 真机 / 预览器手动验收

**Files:** 无（验证任务）

**Interfaces:** Consumes Task 1–10

- [ ] **Step 1: 四组合截图**

在 DevEco 预览器或真机打开农场，依次验证：

- day + sunny：无雨、太阳可见、鸡自由巡游；
- day + rainy：雨丝、湿地面、水洼、太阳隐藏、鸡在檐下、其它动物低头、蜜蜂消失；
- night + sunny：星空、月亮、窗灯 / 门灯 / 舍内灯、萤火虫、鸡不在外面；
- night + rainy：雨丝 + 夜灯、无星无月无萤火虫、鸡在舍内。

- [ ] **Step 2: 行为边界**

- 夜里雨停：农夫 / 小孩 / 狗不回环线，马 / 兔子不恢复巡游；
- 雨天点檐下的鸡：只出「我在躲雨呢」，不把它拉出去；
- 夜里点鸡舍位置：不弹出鸡的单词卡（舍内不可拾取）；
- 雨天点蜜蜂 / 小鸟原位：不弹卡；点前面的向日葵 / 池塘正常；
- 打开即目标态：夜里 / 雨天打开不先闪白天晴天；
- 旧会话回看：无按钮、无报错。

- [ ] **Step 3: AI 路径**

对小星英语老师说「晚上好，外面下雨了，带我去农场看鸡」，确认：

- 工具参数含 `time_of_day:"night"`、`weather:"rainy"`；
- 卡片按夜雨打开；
- 回执含 `time_of_day` / `weather`。

- [ ] **Step 4: 记录结果**

把四组合截图与失败项写入 PR 描述或 `docs/superpowers/plans/` 旁的验收记录；有失败则回到对应 Task 修复。

---

## Self-Review

- **Spec coverage:** §4 场景模型 → Task 6；§5 鸡舍 → Task 7 + 8；§6 其它动物 + 拾取 → Task 9；§7 工具/原生/Web → Task 1–5；§8 兼容边界 → Task 3/8/9；§9 触点 → 全部覆盖；§10 测试 → Task 1 / 10 / 11；§12 验收 → Task 10/11。无遗漏。
- **Type consistency:** `time_of_day` / `weather` 在 ArkTS 侧用驼峰 `timeOfDay` / `weather`，JSON 与回执用下划线；`FarmApp.setNight(v, instant)` / `setWeather(v, instant)` 在 Task 5 与 Task 6 一致；`built.groundMat` / `cloudMats` / `coopLamp` 在 Task 6/7 一致；`onWeatherChange` / `recomputeEnvironment` / `isStoryActive` 在 Task 8/9 一致。
- **Review Focus:** 五个失败模式分别由 Task 8（拾取）、Task 9（重算 + 雨天停自动小剧场 + 奶奶点击守卫）、Task 6（雾）、Task 6+3（吸附）、Task 7+8（雨棚坐标）覆盖；Task 10 的静态脚本再兜一次不变量。
- **Proportion:** 计划以签名、坐标与测试断言为主，未贴完整实现。
