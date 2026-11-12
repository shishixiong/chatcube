# 阳光农场 3D · 昼夜 / 晴雨场景 + 鸡舍升级 设计

**日期：** 2026-11-12
**状态：** 待用户批准
**范围：** `farm_english`（阳光农场 3D 英语探索）新增 `time_of_day` / `weather` 两个工具参数；Web 场景新增白天/晚上、晴天/雨天两轴场景切换；鸡舍按 open-design 原型升级（更细建模 + 夜灯 + 鸡归舍 / 躲雨 / 清晨打鸣）；农场其它动物做雨天就地避雨反应。
**参考原型：** `/Users/mac/Library/Application Support/Open Design/namespaces/release-stable-intel/data/projects/14442a50-c293-4e4f-8b75-b8a991cd8957`（单鸡舍场景，含昼夜、雨、鸡归舍、躲雨、夜灯）
**前置文档：** `docs/superpowers/specs/2026-11-06-farm-english-3d-design.md`（农场工具 v1）、`.claude/rules/teaching-architecture.md` §4

---

## 1. 背景与目标

### 1.1 现状

- `farm3d` 已有**手动**的白天 / 黄昏切换：Web 顶栏一个按钮，原生卡片 Header 一个 🌙 按钮，经由 `FarmApp.setNight(bool)` → `FarmScene.setNight(bool)` 改天光、窗灯、萤火虫。
- **没有任何天气系统**（无雨、无阴天、无湿地面）。
- 鸡舍是简单木箱 + 人字顶 + 门 + 坡道；鸡 / 公鸡已有「门口—进舍—隐藏—出舍」的巡游状态机（`farm-scene.js` 的 `updateCoopBirds`），但**天黑时只是原地站住**，不会真的归舍；也没有窗灯、门灯、舍内吊灯。
- 农场其它动物有 idle / 小剧场 / 夜间睡姿，但**没有雨天反应**。

### 1.2 目标

1. 小星老师（`default`）与小星英语老师（`kids_english`）调用 `farm_english` 时，可以传 `time_of_day`（`day` / `night`）和 `weather`（`sunny` / `rainy`），卡片按传入值打开场景。
2. 老师不传时：`time_of_day` 按设备本地时间自动判定（06:00–17:59 为白天，其余为晚上），`weather` 默认晴天。
3. 孩子在卡片 Header 仍可手动切「白天 / 晚上」「晴天 / 雨天」，方便课堂对比；手动切换后回执如实上报当前场景。
4. 夜间场景有星空、月亮、更明显的窗灯 / 路灯 / 萤火虫；雨天有雨丝、阴天光、湿地面、水洼，太阳 / 星星 / 萤火虫隐去。
5. 鸡舍升级为场景里的「活点」：
   - 更细的木墙、窗棂、门、坡道、栖木、稻草、食槽；
   - 窗户、门缝、门前马灯、舍内吊灯夜里透暖光；
   - 天黑 → 鸡和公鸡走到门口进舍、隐藏过夜；清晨 → 出舍，公鸡打鸣（下雨则先躲雨不打鸣）；
   - 下雨 → 鸡和公鸡走到舍前屋檐下缩着躲雨（可见、轻微发抖），雨停恢复巡游；
   - 白天晴天 → 保持现有自由巡游（walk / peck / 偶尔进舍再出来）。
6. 雨天其它动物：奶牛 / 绵羊 / 马 / 山羊 / 猪 / 猫低头缩着；鸡 / 公鸡躲屋檐；蜜蜂、小鸟隐藏；农夫 / 小孩 / 狗就地停下避雨；鸭子 / 白鹅不受影响（照常）。

### 1.3 成功标准

- 老师说「现在是晚上」并调用 `farm_english`，卡片打开即为夜晚；说「外面下雨了」，打开即雨天；两个参数可组合（夜雨）。
- 不传参数时，晚上 8 点打开是夜晚，下午 3 点打开是白天；天气默认晴天。
- 夜里鸡舍窗、门、灯亮，鸡和公鸡不在外面晃；早上它们从舍里出来，公鸡打鸣。
- 雨天鸡在屋檐下、其它动物低头、雨丝和湿地面可见；雨停后半分钟内恢复晴天状态。
- 手动切换与 AI 传入不打架：打开时用 AI 传入值，打开后孩子的手动切换保持到本次课程结束；回执上报最终状态。
- 旧会话回看（`isAnswered`）不显示任何切换按钮，不触发场景参数。
- 现有 50 个单词 id、5 个分区镜头、TTS、词汇表、台账、星星规则**零改动**。

---

## 2. 用户已拍板的决策

| 决策 | 内容 |
|------|------|
| 天气来源 | 不接华为内置天气（官方明确「仅面向系统应用开放」），由**小星老师传入**；老师可先调 `get_time_info` 判断昼夜，天气从孩子对话中提取，默认晴天。 |
| 鸡舍范围 | **视觉 + 行为都要**：参考原型升级建模与夜灯，并实现归舍 / 躲雨 / 清晨打鸣。 |
| 其它动物 | **鸡舍精细 + 其它就地避雨**：鸡回舍 / 屋檐；其它动物原地低头缩着；不做全农场寻路。 |

---

## 3. 非目标（本期不做）

- 不做完整连续时间轴（清晨 / 黄昏 / 正午渐变）；本期只有 `day` / `night` 两态 + 1.2s 交叉淡入，黄昏由 `applyNightColors` 过渡过程自然带过。
- 不做雨声 / 雷声 / 环境音；不新增任何音频资源。
- 不接任何天气 API、不加定位权限、不联网；天气完全由 AI 参数或孩子对话决定。
- 不改 50 个单词数据、分区、点击拾取、TTS、词汇表、收集护照、台账。
- 不做其它动物走到屋檐 / 牛棚的寻路；农夫 / 小孩 / 狗就地停下，不瞬移、不消失。
- 不新增「雪天 / 大风 / 雾」；枚举只留 `sunny` / `rainy`，以后可扩。
- 不改星星规则：`farm_english` 仍然不授星。

### 失败定义

- 雨天 / 夜晚打开后画面仍与晴天白天一样（参数没生效）。
- 夜里鸡还在地上走、或鸡舍全黑。
- 雨停后雨丝、湿地面、动物姿势卡住不恢复。
- 孩子手动切晴天，回执却仍报雨天。
- 旧会话回看时页面报错或出现多余按钮。

---

## 4. 场景模型

### 4.1 两个正交轴

| 轴 | 取值 | 默认 | 说明 |
|----|------|------|------|
| `time_of_day` | `day` / `night` | 设备本地小时 6–17 → `day`，否则 `night` | 控制天光、窗灯、萤火虫、星空 / 月亮 / 太阳、鸡归舍 |
| `weather` | `sunny` / `rainy` | `sunny` | 控制雨丝、阴天光、湿地面、水洼、动物避雨 |

四种组合都要成立：白天晴、白天雨、夜晚晴、夜晚雨。

### 4.2 目标画面

| 组合 | 天空 / 雾 | 光照 | 可见元素 |
|------|-----------|------|----------|
| day + sunny | 现有亮蓝 `0xDDF3FF` | 现有日照 | 太阳、云、萤火虫无 |
| night + sunny | 深蓝紫 `0x2B2745` | 冷暗月光 | 星空、月亮、窗灯、路灯、萤火虫 |
| day + rainy | 灰蓝 `0x9AA9B4` | 弱而平的阴天光 | 雨丝、湿地面、水洼、云压暗、太阳隐去 |
| night + rainy | 深灰蓝 `0x1E2230` | 更暗的月光 | 雨丝、湿地面、窗灯、无星无月无萤火虫 |

### 4.3 夜间天空

在 `farm-scene.js` 内新增（不放进 `farm-models.js`，因为不是可点单词）：

- **星空**：`THREE.Points`，约 500 颗，分布在半径 420 的上半球，`opacity = night × (1 - rain) × 0.9`，`night > 0.02 && rain < 0.5` 时可见。
- **月亮**：半径约 9 的小球，暖白 `0xF6F1D5`，固定在高空；`night > 0.05 && rain < 0.6` 时可见。
- **太阳**：半径约 12 的小球，暖黄 `0xFFF2C4`，位置与月亮相对；`day` 且 `rain < 0.55` 时可见。
- 参考原型的 `sunDisc / moonDisc / starField` 做法；这里用球体而不是面向相机的圆盘，避免相机环绕时被看扁。
- **必须 `fog: false`**：场景雾是 `Fog(DAY.fog, 110, 310)`，天体在半径 420 处，`PointsMaterial` / `MeshBasicMaterial` 默认受雾影响会被整片染成雾色。星空、太阳、月亮三种材质都要显式 `fog: false`，否则夜空看起来仍是平涂色（静默失败，截图才发现）。
- **首次应用直接吸附**：`boot()` 与原生 `applySceneMode()` 第一次下发时走 `setNight(on, true)` / `setWeather(on, true)`（instant 参数），直接 `night = nightTarget; rain = rainTarget; applySceneColors(...)`，不从白天淡入；只有卡片打开后的手动切换才走 1.2s / 1.5s 插值。

### 4.4 雨天表现

在 `farm-scene.js` 内新增 `rain` 强度（0–1）与雨丝系统：

- **雨丝**：`THREE.LineSegments`，约 700 条，覆盖 140m × 110m、高度 0–38m；下落速度 24–32 m/s，带轻微斜角；`y < 0` 时回到顶部。`opacity = 0.55 × rain`，`rain < 0.01` 时 `visible = false` 且跳过每帧更新。
- **天光**：先按 `night` 在 DAY / NIGHT 之间插值，再按 `rain` 向 RAIN_DAY / RAIN_NIGHT 插值（沿用参考原型的 overcast 叠加思路）。
- **雾**：`scene.fog.color` 跟着天光走；`near` 收近、`far` 缩短约 30%，让雨天的远景更朦胧。
- **云**：`built.cloudMats` 逐云材质颜色向 `0x8E99A3` 压暗，透明度略增。
- **地面**：新建地面材质时改用 `material(C.grass, { unique: true })`，`built.groundMat` 颜色向湿绿 `0x4E6B3A` 插值、`shininess` 提高，表现「打湿了」。
- **水洼**：6 个扁平透明圆盘（浅蓝 `0xBFD8E8`，`opacity = 0.35 × rain`）放在固定坐标；随雨强淡入淡出，轻微缩放呼吸。
- **隐藏**：太阳 / 月亮 / 星空 / 萤火虫 / 蜜蜂在雨天隐藏或淡出；**鸭子 / 白鹅不下雨也照常**。

`applyNightColors(n)` 升级为 `applySceneColors(night, rain)`；初始化时以 `(0, 0)` 调用，`.setNight()` / `.setWeather()` 只改目标值，逐帧向目标插值（夜 1.2s、雨 1.5s 左右），沿用现有 `night` / `nightTarget` 的写法。

### 4.5 雨 / 夜对场景里已有动画的影响

- 萤火虫：`opacity = night × 0.9 × (1 - rain)`，`group.visible = night > 0.05 && rain < 0.5`。
- 蜜蜂：`built.bee.visible = rain < 0.5`（雨天回巢）。
- 池塘涟漪：保留现有；雨天可把涟漪频率略微调高（可选，非必须）。
- 云：雨天移动速度不变，只是颜色 / 透明度变化。
- `reduceMotion`：雨丝仍然下（这是环境，不是动效），但动物发抖 / 水洼呼吸等高频小动作降到 0。

---

## 5. 鸡舍升级

### 5.1 建模（`farm-models.js` 的 `makeCoop`）

保留现有注册与交互契约。**主体进深略增（3.2 → 3.7），正面墙前移到 `z ≈ 1.85`，门中心保持 `z = 1.82`**，因此进门 / 出门动画的 `door` / `stage` 坐标不需要改；新增前檐雨棚，把屋檐下的躲雨点真正盖住：

- 原 `farm-scene.js` 的进舍路径依赖：门 `localPoint(0, 1.82)`、等待点 `localPoint(0, 3.15)`、巡游中心 `localPoint(0, 4.4)`、椭圆半径 `4.0 × 1.9`。新模型正面墙 `z = 1.85`，门洞中心 `z = 1.82`，坡道从门口铺到 `z ≈ 3.4`。
- 结构参考原型：
  - 石 / 木底座（略宽于主体，压住地面）；
  - 后墙 + 左右侧墙 + 正面墙（门洞两侧各一段），墙板上加竖木条缝；
  - 正面门洞：深色内腔 + 暖色内门板（`lampMaterial()`），夜里从门缝透光；
  - 左侧墙一扇小窗：深色窗框 + `windowMaterial()` 窗芯 + 十字窗棂，夜里暖光；
  - 人字屋顶 + 屋脊压条 + 前后山墙三角封板；
  - **前檐雨棚**：一块约 `4.3 × 1.75` 的斜板，从正面墙 `z = 1.85` 伸到 `z ≈ 3.25`，两根立柱落在 `x = ±2.0, z ≈ 3.1`——原型 `buildCoop` 的门前棚子；没有它，`shelter` 点（`z = 2.55`）会暴露在雨里；
  - 门前坡道（带 3 根横木条，从门洞铺到 `z ≈ 3.4`，从雨棚下穿过）；
  - 舍前栖木 / 食槽 / 稻草若干（低多边形小盒 + 草色）；
  - 舍内吊灯：`lampMaterial()` 灯罩 + 一个 `THREE.PointLight(0xFFB45E, 0, 7, 2)`，挂在舍内顶部。
- 继续 `register('chicken_coop', coop, 4.2)`；`wordId` 点击锚点、选中光圈尺寸不变（`select()` 按 group bbox 推导，进深 +0.5 只让光圈略大，不需要手动调）。
- `makeCoop` 把新的发光材质自动推入 `windowMats` / `lampMats`（沿用现有辅助函数），并把 `PointLight` 挂到 `coop.userData.coopLamp`；`buildAll` 在 `built` 里返回 `coopLamp`。
- `applySceneColors` 中：`coopLamp.intensity = 6.5 × night × (1 - 0.25 × rain)`；白天为 0。

### 5.2 鸡的行为状态机（`farm-scene.js` 的 `updateCoopBirds`）

现有状态：`wait / walk / peck / toCoop / enter / inside / exit`。新增 `toShelter / shelter`，并加一个「强制模式」优先级：

```
forceNight = nightTarget > 0.5
forceRain  = !forceNight && rainTarget > 0.5
```

每个鸡 / 公鸡的 routine 每帧先处理强制模式，再走原有自由巡游：

| 条件 | 行为 |
|------|------|
| `forceNight` 且不在 `toCoop/enter/inside` | 从当前位置走向 `stage` → `door` → 进舍隐藏；已在 `inside` 则保持 |
| `forceNight` 且 `inside` | 保持隐藏，不设退出定时 |
| `forceNight` 结束（天亮） | 若 `forceRain`：出舍后走到屋檐下 `shelter` 位；否则出舍后回到 `wait`，并触发一次 `rooster_crow`（仅公鸡、且当前不是雨天） |
| `forceRain` 且不在 `toCoop/inside/toShelter/shelter` | 从当前位置走向自己的屋檐 `shelter` 位（两只鸡左右各一），到达后 `shelter` 姿势 |
| `shelter` 姿势 | 身体略低、头低垂、腿不动、每帧极小幅度 `rotation.z` 发抖；`reduceMotion` 时不抖 |
| `forceRain` 结束 | `shelter → wait`，抖一下翅膀（`flap` 可选），恢复自由巡游 |
| 无强制模式 | 就走现有的 `wait / walk / peck / 偶尔 toCoop → inside → exit` 逻辑 |

- 屋檐 `shelter` 位（局部坐标）：`x = ±1.15, z = 2.55`；按 `chicken_coop` 的 `ry` 旋转到世界坐标。位置在前檐雨棚下、坡道两侧，不会被墙挡住。
- **控制权归属**：鸡 / 公鸡的 `position / rotation / visible` 由 `FarmScene.updateCoopBirds` 独占；把它们从 `FarmAgents` 的夜间 `sleepList` 中移除（`buildAgents` 时为 `coopBird` 的 root 跳过），避免 `applySleep` 每帧覆盖场景算好的进舍位置。`FarmAgents.interact` 仍可对它们播点击小剧；夜间 / 雨天由 §6.1 的守卫拦下。
- **`setCoopBirdsAuto` 改为纯开关**：删除函数内部的 `resetCoopBird` 循环，只写 `coopBirdAuto`。现有调用点（`releaseResources`、`onNightChange`、`dispose`）都不需要「瞬移回窝」这个副作用；故事结束时的位置恢复由 `restoreAgent` 负责。这样雨天开始 / 结束、故事收尾都不会把鸡瞬移回家，屋檐 / 出舍动画能完整播放。
- **强制模式优先**：`forceNight` / `forceRain` 期间忽略 `coopBirdAuto`（自由巡游开关），保证无论故事怎么设置它，鸡都会归舍 / 躲雨。
- **清晨公鸡打鸣由场景触发**：从 `FarmAgents.onNightChange(false)` 中移除 `startStory('rooster_crow')`。改由 `updateCoopBirds` 在公鸡 `exit` 补间结束、状态回到 `wait` 后置 `pendingCrow = true`；下一帧若 `!rainTarget && !reduceMotion && !story`，调用 `FarmAgents.trigger('rooster_crow')`。这样打鸣不会和出舍补间抢 transform，也不会在雨天把公鸡从屋檐下拉走。
- 故事（`grandma_feed` / `chicken_peck` / `rooster_crow`）接管期间遇到入夜 / 下雨：`FarmAgents` 先 `cancelStory()` 恢复姿势，再由场景的强制模式接管。
- 回执不受影响：鸡的行为仍不影响单词点击、收集与「我学会了」。

### 5.3 夜灯与单词卡

- 鸡舍仍是 `chicken_coop` 单词（chicken coop / 鸡舍），点击照常出卡。
- 夜灯只是视觉，不加新单词、不加新 id。
- 舍内吊灯不投影（`castShadow = false`），避免多光源阴影开销。

---

## 6. 其它动物的雨天反应

在 `farm-agents.js` 新增 `rainOn` 与 `A.onWeatherChange(on)`，与 `onNightChange` 对称。**两个 handler 不再各自维护 auto / hold 状态，而是统一收口到一个纯状态重算函数**：

```
function recomputeEnvironment() {
  var asleep = nightOn
  var wet = rainOn && !nightOn          // 夜里睡姿优先，雨姿只在白天生效
  host.setHorseAuto(!nightOn && !rainOn)
  host.setRabbitAuto(!nightOn && !rainOn)
  host.setCoopBirdsAuto(!nightOn && !rainOn)   // 纯开关，不再瞬移
  host.holdActor('farmer', nightOn || rainOn)
  host.holdActor('child', nightOn || rainOn)
  host.holdActor('dog', nightOn || rainOn)
  ...雨姿 / 睡姿的目标强度由 asleep / wet 决定
}
```

- `onNightChange(on)`：更新 `nightOn` → `cancelStory()` → `recomputeEnvironment()` → 夜间气泡。
- `onWeatherChange(on)`：更新 `rainOn` → `cancelStory()` → `recomputeEnvironment()` → 雨天 / 雨停气泡。
- 这样**夜里雨停不会把农夫 / 小孩 / 狗放回环线、也不会重新启用马和兔子**（builder-check 指出的交叉 bug）。
- 进入雨天：`cancelStory()`；气泡「下雨啦，大家躲一躲。」（由猫 / 鸡做锚点，若存在）。
- 雨天姿势（新增 `applyRainPose`，与睡姿分开）：
  - 奶牛 / 绵羊 / 马 / 山羊：头低垂、身体略压、轻微左右摇；
  - 猪：头低、尾巴不动；
  - 猫 / 兔子：头低、耳朵后压；
  - 农夫 / 小孩 / 狗：站定、头微低、身体小幅前后晃；
  - 蜜蜂 / 小鸟：隐藏（`visible = false`，拾取见 §6.1）；
  - 鸭子 / 白鹅：不套用雨姿，照常。
- 雨停：`recomputeEnvironment()` 恢复 auto / 释放 hold，气泡「雨停啦，太阳出来喽。」（夜晚则只说「雨停啦」）。
- 夜晚 + 雨天：睡姿优先；雨姿目标为 0，避免两套姿势打架。夜晚的鸡仍按 §5.2 归舍。
- **人物 / 狗就地停下**，不瞬移、不消失。真正走回农舍需要新的离环寻路，超出本期；这是本设计的明确取舍（用户选项标题为「其它就地避雨」）。

### 6.1 点击与拾取（隐藏物体 / 躲雨的鸡）

- `pickAt` 命中后向上找 `wordId` 时，**任何祖先 `visible === false` 的命中直接跳过**（`raycaster.intersectObjects` 不会自动忽略不可见网格——这是 r128 的行为）。这样夜里藏在舍内的鸡、雨天隐藏的蜜蜂 / 小鸟不会留下「空气点击区」，也不会抢走前面向日葵 / 池塘的点击。
- `FarmAgents.interact` 增加守卫：
  - 雨天点鸡 / 公鸡 → 不播 `chicken_peck` / `rooster_crow`（会把它从屋檐下拉出去），改为一句气泡「我在躲雨呢。」；夜里点它们 → 已在舍内不可见，拾取已被 §6.1 第一条挡住，不会触发；
  - 雨天 / 夜里点奶奶 → 同样拦下（`grandma_feed` 小剧场会把鸡一起拉出来啄食），雨天给气泡、夜里直接不响应；
  - 其它动物雨天可正常点击（`onWeatherChange` 的 `cancelStory` 后会被重新 `holdActor` 或回到雨姿）。
  - 雨天暂停**自动**小剧场调度（`tick` 早退），避免 `grandma_feed` / `chicken_peck` 把鸡从屋檐下拉走；手动点击仍可触发反应。
- 老师用 `words:["bee"]` / `words:["bird"]` / `words:["chicken"]` 在雨天 / 夜里打开时：单词卡与发音照常（教学优先），3D 光圈落在物体的原始锚点，不强制把动物显示出来。这是明确取舍，写进文档避免实现时纠结。

---

## 7. 工具参数与原生接线

### 7.1 `farm_english` schema（`config/BuiltinTools.ets`）

新增两个可选字段：

```json
{
  "time_of_day": {
    "type": "string",
    "enum": ["day", "night"],
    "description": "可选。这次农场是什么时间：day=白天，night=晚上。老师应先调用 get_time_info，按本地小时判断（06:00–17:59 传 day，其余传 night）。不传时卡片按设备当前时间自动判断。"
  },
  "weather": {
    "type": "string",
    "enum": ["sunny", "rainy"],
    "description": "可选。这次农场的天气：sunny=晴天（默认），rainy=雨天。只在孩子明确提到天气（「今天下雨了」「外面是晴天」）或课堂需要对比时才传 rainy；不知道就留空，不要编造真实天气。"
  }
}
```

- `FarmEnglishArgs` / `FarmEnglishExecutor` 回显增加 `time_of_day`、`weather`（缺省回 `''`）。
- 工具描述补一句：可传 `time_of_day` / `weather` 让 3D 农场与课堂情境一致；晚上会亮灯、鸡回舍，雨天会下雨、动物躲雨；这两个参数只改场景，不改变单词与星星规则。
- `required` 仍只有 `skill_key`。

### 7.2 预校验（`utils/FarmEnglishValidation.ets`）

`FarmEnglishValidationResult` 增加：

```ts
timeOfDay: string   // 'day' | 'night' | ''（缺省 = auto）
weather: string     // 'sunny' | 'rainy' | ''（缺省 = auto）
```

规则：

- `time_of_day` 可选；出现时必须是字符串，且（trim 后）为 `day` / `night`；兼容别名 `morning` / `afternoon` → `day`，`evening` / `dusk` → `night`？**不兼容别名**——保持两个枚举干净，避免模型乱造；非法值直接 `should_retry`。
- `weather` 可选；出现时必须是字符串，且（trim 后）为 `sunny` / `rainy`；非法值 `should_retry`。
- 空字符串视为未传。
- 其它字段（`skill_key` / `focus` / `words`）规则不变。

### 7.3 原生解析（`components/farm/FarmEnglishCard.ets`）

- `FarmEnglishArgsView` 增加 `timeOfDay: string`、`weather: string`。
- `parseFarmEnglishArgs` 透传校验结果。
- 新增纯函数（放在 `FarmEnglishValidation.ets`，便于测）：
  - `resolveFarmTimeOfDay(arg: string, hour: number): string`：arg 为 `day`/`night` 时直接用；否则 `hour >= 6 && hour < 18 ? 'day' : 'night'`。
  - `resolveFarmWeather(arg: string): string`：`rainy` 或 `sunny`，否则 `'sunny'`。
- `@Local nightOn: boolean` 已有；新增 `@Local weatherOn: boolean = false`。
- `aboutToAppear`：用 `resolveFarm...` 初始化两个状态；**不要**在 `isAnswered` 时初始化场景（回看态不加载 Web 控制）。
- `bridge.readyHandler` → `applyFocusWords()` 之后（或同一脚本里）新增 `applySceneMode()`：执行
  `FarmApp.setNight(<nightOn>, true); FarmApp.setWeather(<weatherOn>, true);`
  再执行原有的 `setHostMode` / `select` / `setView`。顺序：先场景模式，再镜头 / 选词，避免镜头飞到一半换光。第二个参数 `true` 表示**首次应用的吸附模式**（不淡入）。
- `toggleNight()` 保持；新增 `toggleWeather()` → `FarmApp.setWeather(...)`，更新 `weatherOn`。
- Header 增加一个天气按钮（圆形 30×30，☀️ / 🌧️），与现有 🌙 / ☀️ 并排；空间不足时标题块被压缩（已有 `layoutWeight(1)` + 省略号），按钮保持图标级尺寸。
- `isAnswered` 回看态：不显示 HeaderBar，行为不变。

### 7.4 Web 控制 API（`farm-app.js` / `index.html`）

- `FarmApp.setWeather(v, instant)` → `applyWeather(!!v, !!instant)`，`state.rain` 持久到页面级。
- `FarmApp.setNight(v, instant)` 增加可选的 `instant` 参数，透传给 `FarmScene.setNight(v, instant)`；不传时保持现有 1.2s 渐变，传 `true` 时直接吸附。
- `applyWeather`：`FarmScene.setWeather(state.rain, instant)`；更新 Web 顶栏按钮（仅非 host 模式可见）；toast「下雨啦，小鸡躲进鸡舍里了」/「雨停啦，太阳出来喽」。
- `index.html` 顶栏加一个天气按钮（`rainBtn` / `rainLabel`），默认隐藏于 host 模式；文案从「黄昏」改为「晚上」。
- `boot()` 初始化时：`if (state.night) setNight(true, true); if (state.rain) setWeather(true, true);`（在 `Scene.resize()` 之后、`onReady` 之前，吸附模式）。
- `FarmScene.setWeather(on)` / `getWeather()`；`setWeather` 变化时通知 `FarmAgents.onWeatherChange(on)`。
- `FarmScene.setNight` 已有；把 `FarmAgents` 通知保留。

### 7.5 回执

`FarmEnglishAnswerPayload` 增加：

```ts
time_of_day: string   // 'day' | 'night'（最终实际状态）
weather: string       // 'sunny' | 'rainy'
```

`buildPayload` 用当前 `nightOn` / `weatherOn` 生成。AI 因此知道孩子看到的是哪个场景，可在后续 `english_quiz` 里自然复用（如「刚下雨的时候，我们看到了 duck」）。

`cancelled` / `completed` / `explored_count` / `words` / `focus` / `skill_key` 不变。

### 7.6 教学提示词（`models/AssistantModels.ets`）

- 小星老师提示词第 77 行「阳光农场 3D 英语探索」段追加：
  > 打开农场前先调 `get_time_info`：本地时间 06:00–17:59 传 `time_of_day:"day"`，其余传 `"night"`；孩子提到天气（下雨 / 晴天）就传对应 `weather`，没提就留空（默认晴）。晚上农场会亮灯、小鸡回舍，雨天会下雨、动物躲雨——可以用这些画面引导孩子说 `night` / `rain` / `sunny` / `shelter` 等词。
- 小星英语老师提示词第 348 行同样补一句（更短，只保留「先 get_time_info，传 day/night；天气来自孩子对话，默认晴」）。
- 不改 `get_time_info` 工具本身，不改锁定工具列表（`get_time_info` 已在 5 个内置助手的白名单内）。

---

## 8. 兼容性与边界

- **旧会话回看**：`isAnswered` 只渲染 `SummaryView`，不加载 Web、不读参数；新增字段在旧 payload 里不存在时按默认值处理（`time_of_day=''`、`weather=''`）。
- **旧参数**：不带新字段的 `farm_english` 调用完全兼容：时间自动、天气晴。
- **Web 资源失败**：现有 watchdog / 错误面板不变；新场景初始化不得在 `FarmScene.init` 之前调用。
- **性能**：
  - 雨丝 700 条线段、星空 500 点、月亮 / 太阳各一个球；都是一次性几何 + 每帧只改 opacity/position；
  - 雨天不新增阴影投射；鸡舍吊灯 `castShadow=false`；
  - `rain < 0.01` 时跳过雨丝更新；`night < 0.02` 时跳过星空更新；
  - `reduceMotion` 下不跑动物发抖 / 水洼呼吸。
- **ArkTS 严格模式**：新增 JSON schema 仍在模板字符串里，描述字段避免 ASCII 双引号（用「」），改完用 `node -e` 提取 `JSON.parse` 验证。
- **Web JS 无类型检查**：改动后需在 DevEco 真机 / 预览器跑一次四组合截图级验证。

---

## 9. 文件触点

| 文件 | 改动 |
|------|------|
| `entry/src/main/ets/config/BuiltinTools.ets` | `farm_english` schema 增加 `time_of_day` / `weather`；`FarmEnglishArgs` / executor 回显；工具描述补场景参数 |
| `entry/src/main/ets/utils/FarmEnglishValidation.ets` | 结果增加 `timeOfDay` / `weather`；校验 + `resolveFarmTimeOfDay` / `resolveFarmWeather` 纯函数 |
| `entry/src/main/ets/components/farm/FarmEnglishCard.ets` | args view、`weatherOn` 状态、`toggleWeather`、Header 天气按钮、`applySceneMode`、payload 增加场景字段 |
| `entry/src/main/ets/models/AssistantModels.ets` | 小星老师 / 小星英语老师提示词各补一段场景参数用法 |
| `entry/src/main/resources/rawfile/farm3d/index.html` | Web 顶栏天气按钮；「黄昏」文案改「晚上」 |
| `entry/src/main/resources/rawfile/farm3d/assets/farm-app.js` | `state.rain`、`applyWeather`、`FarmApp.setWeather`、启动恢复 |
| `entry/src/main/resources/rawfile/farm3d/assets/farm-scene.js` | `rain` / `rainTarget`、`setWeather` / `getWeather`、雨丝、星空 / 月 / 日（`fog:false`）、`applySceneColors`、地面 / 云 / 萤火虫 / 蜜蜂响应、鸡舍灯、鸡的强制归舍 / 躲雨、出舍后打鸣、`setCoopBirdsAuto` 去 reset、`pickAt` 跳过不可见祖先 |
| `entry/src/main/resources/rawfile/farm3d/assets/farm-models.js` | `makeCoop` 升级建模 + 前檐雨棚 + 夜灯；地面材质唯一化；`cloudMats` / `coopLamp` / `groundMat` 导出 |
| `entry/src/main/resources/rawfile/farm3d/assets/farm-agents.js` | `rainOn`、`onWeatherChange`、`recomputeEnvironment`、雨姿 / 恢复、鸡从 `sleepList` 移除、躲雨鸡点击守卫、移除 `onNightChange` 打鸣 |
| `entry/src/main/resources/rawfile/farm3d/assets/farm.css` / `index.html` | 天气按钮样式（若顶栏布局需要） |
| `entry/src/ohosTest/ets/test/utils/FarmEnglishValidation.test.ets` | 新字段的校验与解析用例 |
| `CLAUDE.md` / `.claude/rules/teaching-architecture.md` | 工具行补 `time_of_day` / `weather` 与鸡舍行为说明 |

---

## 10. 测试计划

### 10.1 单元测试（hypium，`FarmEnglishValidation.test.ets`）

- `time_of_day`：`day` / `night` 通过；`dusk` / `DAY` / 空串 / 数字 → 空串或失败（按规则：空串当未传，非法值失败）。
- `weather`：`sunny` / `rainy` 通过；`rain` / `Rainy` / 数字 → 失败。
- 缺省：不传两个字段时结果 `ok=true`，`timeOfDay=''`、`weather=''`。
- `resolveFarmTimeOfDay('', 5/6/12/17/18/23)` → `night/day/day/day/night/night`。
- `resolveFarmTimeOfDay('night', 12)` → `night`（显式参数优先）。
- `resolveFarmWeather('')` → `sunny`；`'rainy'` → `rainy`。
- 旧字段回归：`skill_key` / `focus` / `words` 原有用例全绿。

### 10.2 手动验证（DevEco + 真机 / 预览器）

四组合逐一检查：

- day + sunny：无雨、无星、太阳可见、鸡自由巡游；
- day + rainy：雨丝、湿地面、水洼、太阳隐藏、鸡在屋檐下、其它动物低头、蜜蜂消失；
- night + sunny：星空、月亮、窗灯 / 门灯 / 舍内灯、萤火虫、鸡不在外面；
- night + rainy：雨丝 + 夜灯，无星无月无萤火虫，鸡在舍内。
- 切换：点击 Header 两个按钮来回切，确认 1–2 秒内平滑过渡、无闪烁、无卡死；雨停后 30 秒内动物恢复。
- **打开即目标态**：夜里 / 雨天打开卡片，不应先看到白天晴天再淡入（首次应用吸附）。
- **夜里雨停**：夜晚先下雨再停雨，农夫 / 小孩 / 狗不应被放回环线走动，马和兔子也不应恢复巡游。
- **躲雨的鸡**：雨天点屋檐下的鸡，只出「我在躲雨呢」气泡，不把它拉出去啄食；夜里点鸡舍位置不会点出单词（舍内鸡不可拾取）。
- **隐藏物体拾取**：雨天点蜜蜂 / 小鸟原来的位置，不应弹出单词卡；点它们前方的向日葵 / 池塘仍能正常选中。
- AI 路径：新会话对小星英语老师说「晚上好，外面下雨了，带我去农场看鸡」，确认工具参数带 `time_of_day:"night"`、`weather:"rainy"`，卡片按夜雨打开；回执含 `time_of_day` / `weather`。
- 不传参数：下午打开为白天晴；晚上打开为夜晚晴。
- 旧会话回看：`isAnswered` 页面正常，无按钮，无脚本错误。
- 性能：夜雨时旋转 / 缩放 / 点词流畅；`console` 无新报错。

---

## 11. 后续可优化（不阻塞本期）

- 连续时间轴（清晨 / 黄昏 / 正午）+ 太阳角度；
- 雨声 / 雷声 / 鸟鸣环境音（WebAudio 合成，不新增素材）；
- 雪天 / 大风 / 雾；
- 人物真正走回农舍（离环寻路）；
- 雨天鸡舍门口的泥脚印 / 水花；
- AI 依据真实天气服务（若华为开放第三方）自动传入。

---

## 12. 验收清单

- [ ] `farm_english` schema 含 `time_of_day` / `weather`，非法值 `should_retry`
- [ ] 不传参数时按设备时间自动昼夜、默认晴天
- [ ] AI 传 `night` + `rainy` 打开即夜雨
- [ ] Header 两个切换按钮可用，回执上报最终状态
- [ ] 旧会话回看无按钮、无报错
- [ ] 四种组合视觉正确（雨丝 / 湿地面 / 星空 / 月亮 / 太阳 / 夜灯）
- [ ] 夜里鸡 / 公鸡归舍隐藏，清晨出舍且公鸡打鸣（雨天不打鸣）
- [ ] 鸡的控制权只在 FarmScene（不与 sleepList 抢 transform），`setCoopBirdsAuto` 不再瞬移
- [ ] 雨天鸡在屋檐下缩着，雨停恢复巡游
- [ ] 夜里雨停不会误放人物 / 马 / 兔子回环线
- [ ] 雨天其它动物低头、蜜蜂小鸟隐藏、鸭子白鹅照常
- [ ] 隐藏物体（舍内鸡 / 雨天蜜蜂小鸟）不可拾取，也不挡住前面的物体
- [ ] 首次打开直接是目标昼夜 / 天气，不先闪一下白天晴天
- [ ] 天空体不受雾影响（夜间能看见星星 / 月亮）
- [ ] 鸡舍仍是可点单词，点击 / 收集 / TTS 不变
- [ ] `FarmEnglishValidation` 新用例全绿
- [ ] `assembleHap` 通过
- [ ] CLAUDE.md / teaching-architecture 工具行已更新
