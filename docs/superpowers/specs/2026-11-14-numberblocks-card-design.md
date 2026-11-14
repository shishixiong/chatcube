# Numberblocks 认数字卡片（number_blocks）设计

**日期：** 2026-11-14
**版本：** v1（display 模式）
**范围：** 新工具 `number_blocks` + Web 场景 `rawfile/numberblocks/` + `components/numberblocks/NumberBlocksCard.ets` + ChatPage 全屏 sheet
**参考：** 用户提供的 `artifact-e0f9006e….html`（纯 CSS 3D 的 Numberblocks 1–20 角色画廊，零依赖）

---

## 1. 意图

给小星老师（和数学老师）一张「把数字摆出来给孩子看」的卡片。孩子第一次认 1–20、想看看「3 到底长什么样」、或者数数时，老师调 `number_blocks` 打开一个数字乐园：20 个方块小人排成长廊，点一个就放大到舞台，拖一拖能转，点一下就听见「三」和「Three」。

**这不是一道题**——讲解型，不判对错、不授星（与 `map_card` / `room_english` / `city_english` / `farm_english` 同族）。认完数字后老师照常可以用 `math_quiz` / `picture_vocab` 出题巩固，星星在那边给。

### 非目标（v1 明确不做）

- 不出题、不判对错、不记星星
- 不做分与合 / 乘法 / 阶梯（v2+，见 §10）
- 不做跨会话收集进度（每次打开都是全新的一轮）

### 反目标（技术上做出来也算失败）

- 把 3D 降到 2D 平铺色块——那这套素材的意义就没了
- 把 20 个角色塞进一个高度有限的聊天气泡里，细节全糊
- 靠打字模拟念数字——发音必须走原生 TTS

---

## 2. 用户路径

```
小星老师：「我们来看看数字朋友吧」→ number_blocks(numbers:[1..5], focus:1)
   ↓
聊天里出现紧凑横幅「🔢 认数字 · 点开看看数字朋友」
   ↓ 点击
全屏 sheet（原生标题栏 + Web 场景）
   ↓
长廊：5 列 × 4 行，20 个缩略小人，点谁放大谁
   ↓ 点「3」
舞台：3 号小人站中间，拖拽转视角，原生 TTS 念「三。Three。」
   ↓ 左右滑动 / 底部数字条 / ▶ 自动巡游
看够几个 → 顶部「我学会了 · 继续」→ 回执给 AI
```

---

## 3. 工具定义

**tool id：** `number_blocks`

**参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `numbers` | integer[] | 否 | 今天的**重点**数字，1–20 的去重子集。**不影响长廊内容**——长廊永远展示全部 1–20（孩子要能自己挑）；这些数字在长廊里挂一枚小圆点、自动巡游只走这些。不填 = 全部 |
| `focus` | integer | 否 | 打开时长廊里呼吸高亮一次的格子（不自动进舞台）。不填 = `numbers` 第一个 |
| `mode` | string | 否 | v1 只有 `display`。缺省 `display`。非法值 → `should_retry` |

**预校验**（渲染前，`utils/NumberBlocksValidation.ets`）：

- `numbers` 每项必须是 1–20 整数；重复项去重；升序排序；超过 20 项截断
- `focus` 必须是 1–20 整数；不在 `numbers` 里则回落到第一个
- `mode` 必须是 `display`
- 失败返回 `{error:'validation_failed', message:<原因>, should_retry:true}`，不渲染坏卡

**锁定**：`DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` + `KIDS_MATH_LOCKED_TOOL_IDS`。不进 `kids_english` / `kids_chinese` / `kids_games`。

**系统提示词段（AssistantModels）**：孩子刚接触数字、想认数字 / 数数 / 看「数字长什么样」时调 `number_blocks`；讲解型，不判对错；看完后可在后续回合用 `math_quiz` 出认数题巩固。不得在文字里假装展示数字小人。

---

## 4. 原生卡片

`components/numberblocks/NumberBlocksCard.ets`，骨架镜像 `FarmEnglishCard`：

```
HeaderBar（原生）
  ├─ 标题「认数字 Numberblocks」
  ├─ 副标题「已认识 3 / 20 · 点一点方块听数字」
  └─ 右侧按钮「我学会了」/「先看看数字」（看 ≥1 个才可点）
Web 容器（resource://rawfile/numberblocks/index.html）
  └─ 就绪看门狗 10s，超时切原生错误面板 + 重试按钮
```

**Native Bridge**（`javaScriptProxy`，方法返回值统一用字符串）：

| 方法 | 用途 |
|------|------|
| `speak(en, zh)` | 原生 TTS，先中文后英文（`ServiceRegistry.tts()`，语速 0.8） |
| `stopSpeak()` | 停止朗读（切数字 / 关 sheet / 离开页面） |
| `onReady()` | 场景就绪，解除看门狗，应用 host 模式 |
| `onError(reason)` | WebGL / 数据缺失 → 原生错误面板 |
| `onSelect(n)` | 孩子进入舞台的某个数 → 并入原生 `seenNumbers`（**唯一权威来源**） |
| `onProgress(idsJson)` | 仅用于页面重载后让原生把新看过的补进 `seenNumbers`；原生只并集、不覆盖、不清空 |

**回执 payload**（写 `toolCall.approvalReason`）：

```ts
interface NumberBlocksAnswerPayload {
  completed: boolean
  explored_count: number
  numbers: number[]      // 本次看过的数字，升序
  focus: number
  mode: string
  skill_key: string      // 'math_counting'
  cancelled: boolean
}
```

**不授星**：`handleNumberBlocks` 不调 `recordStarEvent`；`StarEventModels` / `StarRewardService` 不改（与 `room_english` / `farm_english` 一致，这两个也没进星星联合）。

**Sheet 收起**：注册 `onRegisterDismissPayload`，下拉收起 = 本次到此为止，回执照常带已看数字（`completed = count > 0`）。

---

## 5. Web 场景

`resources/rawfile/numberblocks/`：

```
index.html
assets/numberblocks.css        # 角色 3D 样式（搬参考稿）
assets/numberblocks-host.css   # host 模式：隐藏网页品牌栏
assets/numberblocks-models.js  # cube / box / grid / blocks / limb / decal / lens / mouth …（搬参考稿）
assets/numberblocks-data.js    # 20 个 CHARS 定义 + PAL 调色板（搬参考稿）
assets/numberblocks-scene.js   # 长廊 / 舞台控制器
```

脚本按顺序普通 `<script>` 引入（非 module），共享全局作用域。

### 5.1 长廊（默认视图）

- 5 列 × 4 行，**永远 20 个格子**，一屏放得下，不滚动；窄屏按格子宽度等比缩小（缩略比例由 JS 按实际宽度算，不写死）
- 每格把对应角色**用同一套 DOM 构建器渲染**，外层 `transform: scale(var(--thumb-scale))` 缩小；裁剪窗口取 300×600 坐标空间的 y∈[10,550]，让小人刚好坐满格子
- 格子底色取角色**分色条**的浅色调（`split` 有就用 `split`，没有用 `color`）；左上角数字徽章同色。11–20 全是红色主色，靠 `split` 区分
- `numbers` 里的格子右上角挂一枚重点小圆点；`focus` 那格进页面时呼吸高亮一次
- 长廊**不播动画**（不浮动、不眨眼、道具也静止）——20 个同时动会很吵，也费电
- 点格子 → 进舞台

### 5.2 舞台

- 一次一个角色，居中大尺寸，**全部原稿动画照跑**：呼吸浮动、眨眼、3 号的抛球、13 号飘在身后的黄块、14 号的滑板晃动、挥手手套、8 号的触手——它们是小人性格的一部分，冻住会像坏掉
- 拖拽旋转：`pointerdown/move/up`，**横向不设上限**（与参考稿一致，来回拖能一直转），纵向限 ±60°
- 进入舞台立即 TTS 念「三。Three。」
- 点角色本体 = 重播
- 舞台左右滑 → 相邻数字（1–20 内，边界不循环）
- 底部数字条 1–20（横向可滚），当前项高亮；点任何一项直接切
- 舞台下方两个按钮：「🔊 再听一次」「▶ 自动巡游」
- 左上角「‹ 长廊」返回

### 5.3 自动巡游

从 `numbers` 的第一个开始（`numbers` 为空 = 从 1 开始），**2.4 秒一个**念到最后一个，然后停在最后一个。任一触摸（点、拖、切数字、返回）立刻停止。停止时 `stopSpeak()`。

### 5.4 眼睛跟随

参考稿靠 `--px/--py` 跟着鼠标转。触屏上改为：拖拽时按拖拽方向偏一点，松手后 0.6s 回到正中。不跟随手指绝对位置（会让人分心）。

### 5.5 「已看」的口径

**舞台出现过一次就算看过**——从长廊点进去、左右滑过去、数字条点过去、自动巡游念到，都算。理由：认数字的核心动作是「看见 + 听见」，这三条路径都完整给了。

- 页面每次进舞台调 `onSelect(n)`，原生把 n 并入 `seenNumbers`（升序、**只增不减**，页面重载也不清）
- 长廊 = 全部 20，所以「已认识 N / 20」的分母恒为 20
- 榜单只在本次 sheet 生命周期内有效，关掉就没了（不做跨会话收集）
- 底部不提供「全部看过」按钮——看没看是孩子的行为，不该一键代劳

---

## 6. 视觉

沿用参考稿的材质与配色，不改：

- 角色主色、`split` 分色条、`head` 白顶、灰色系（9/19）、彩虹系（7/17）全部按原稿
- 圆角方块、`linear-gradient(150deg, light, base 55%)` 正面、深色侧面
- **舞台顶部保留参考稿那张卡的彩色数字横幅**（`head` 白顶 / `split` 分色条 / 主色底 + 大号数字）——舞台就是那张卡放大；没有它，11–20 十个红色小人只剩方块形状能区分
- 长廊格子用 `split` 的浅色调作底（11–20 靠它区分），不再复制横幅
- 页面底色 `#eef2f7`（浅）；深色模式 v1 不改场景（参考稿是固定浅色，与 three.js 场景同策略）

---

## 7. 文件触点

| # | 文件 | 改动 |
|---|------|------|
| 1 | `utils/SearchToolIdentityUtils.ets` | `NUMBER_BLOCKS_TOOL_ID = 'number_blocks'` + `isNumberBlocksFunctionName()` |
| 2 | `config/BuiltinTools.ets` | import、`NumberBlocksArgs`、`NumberBlocksExecutor`、`createNumberBlocksToolDefinition`、`createNumberBlocksToolConfig`、`registerBuiltinTools`、`getBuiltinToolIds()` |
| 3 | `services/ToolExecutionService.ets` | import、`handleNumberBlocks()`（镜像 `handleFarmEnglish`）、dispatch 分支（放在 `resolveToolId` 兜底之前） |
| 4 | `models/AssistantModels.ets` | import、`DEFAULT_ASSISTANT_LOCKED_TOOL_IDS`、`KIDS_MATH_LOCKED_TOOL_IDS`、系统提示词段 |
| 5 | `utils/NumberBlocksValidation.ets`（新） | `validateNumberBlocksArgs()` 纯函数 + 常量 |
| 6 | `components/numberblocks/NumberBlocksCard.ets`（新） | 卡片 |
| 7 | `components/MessageBubble.ets` | import、内联横幅、3 处 or-chain、`shouldRenderNumberBlocksInteractionCard`、点击分发、步骤切换 / 内容 |
| 8 | `pages/ChatPage.ets` | `showNumberBlocksSheet` / `numberBlocksAnswered` / `numberBlocksToolCall` + `bindSheet` + builder + 收起回执 |
| 9 | `resources/rawfile/numberblocks/**`（新） | Web 场景 |
| 10 | `entry/src/ohosTest/ets/test/utils/NumberBlocksValidation.test.ets`（新） | 校验纯函数单测 |

**不改**：`models/StarEventModels.ets`、`services/StarRewardService.ets`（讲解型不授星）。

---

## 8. 决策记录

| 决策 | 取舍 |
|------|------|
| Web 容器而非原生 ArkUI | 20 个角色的 CSS 3D 材质很难在 ArkUI 里 1:1 复刻；`room3d`/`city3d`/`farm3d` 已有成熟桥接范式 |
| 长廊 + 舞台两视图 | 用户指定「给一个 1–20 的缩略长廊，让孩子自己挑」；但一屏 20 个都做成大舞台会互相挤压 |
| 不循环切换 | 1 前面没有 0，20 后面没有 21——循环会骗孩子 |
| `numbers` 不裁剪长廊 | 用户明确要「1–20 的缩略长廊，让孩子自己挑」；`numbers` 退化为「今天的重点」标记 + 巡游范围 |
| 舞台保留彩色数字横幅 | 11–20 主色全是红，没有横幅只能靠方块形状分辨 |
| 道具动画在舞台照跑 | 抛球/滑板/触手是小人性格，冻住像坏了 |
| 长廊不播动画 | 20 个同时呼吸 = 视觉噪音 + 耗电 |
| 进舞台即朗读 | 「认数字」的核心动作就是听见它 |
| `mode` 参数 v1 只开 `display` | 给分与合 / 乘法 / 阶梯留显式扩展位，且参数校验现在就位 |
| 不做跨会话收集 | 认数字不需要养成；多做一层进度存储只会增加状态面 |

---

## 9. 验收

- [ ] AI 调 `number_blocks` → 聊天出现横幅 → 点开全屏 sheet
- [ ] 长廊 20 个缩略角色全部渲染，`focus` 高亮正确
- [ ] 点格子进舞台，角色大尺寸、可拖拽旋转、呼吸 + 眨眼
- [ ] 进舞台即 TTS 念「三。Three。」；🔊 重播；切数字时旧朗读立即停
- [ ] 舞台左右滑 / 数字条切数字，边界不循环
- [ ] ▶ 自动巡游按 `numbers` 顺序逐个念，触摸即停
- [ ] 「我学会了」需 ≥1 个已看；提交后回执 JSON 含 `numbers` / `explored_count` / `skill_key`
- [ ] 下拉收起 sheet 也回执，TTS 立即停
- [ ] 星星数不变（讲解型不授星）
- [ ] 工具出现在工具中心；4-grep + JSON.parse 校验通过
- [ ] 断网 / `rawfile` 资源缺失 / 脚本报错 → 10s 看门狗切原生错误面板，不无限转圈

---

## 10. v2 扩展位（不在本期）

同一个方块系统按 `mode` 长出：

- `split`（分与合）：5 号小人从腰部分开成 2 + 3，两块各自走开再合回来
- `multiply`（乘法）：3×4 = 12 块摆成 3 行 4 列（复用 `blocks()` 的字符画排布）
- `stairs`（阶梯）：1..N 叠成台阶，一眼看出「多一个」

实现前提：`CHARS` 的 `build()` 已经拆成「方块布局 + 表情贴片」两层，运算模式只需要换方块布局、复用表情与四肢。

---

**相关文档：** `.claude/rules/teaching-architecture.md`（§4 教学工具生态）、`.claude/skills/adding-mini-game-tool/SKILL.md`（8 文件触点配方）
