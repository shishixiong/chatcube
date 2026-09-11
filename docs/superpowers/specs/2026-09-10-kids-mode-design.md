# 儿童模式（Kids Mode）设计 Spec

**日期：** 2026-09-10
**版本：** v1
**状态：** 已与用户对齐（brainstorming 完成），待实施 plan
**范围：** 应用外壳级儿童模式——冷启动直达儿童主屏、算术题家长门、图形化会话列表、ChatPage 成人入口裁剪、设置开关

---

## 1. 背景与问题

App 外壳是成人 AI 客户端：底部三 tab（助手/对话/设置）里，服务商管理、模型选择、WebDAV、工具中心全在 5 岁孩子可触达的位置，小星老师只是助手列表中的一项。孩子会迷路，也可能误删配置。

**目标：** 家长在设置中开启"儿童模式"后，App 对孩子呈现为一张纯净的教学主屏——大卡片直进小星老师会话，管理面全部收进"家长门"（算术题验证）后面。

## 2. 已对齐的产品决策

| 决策点 | 结论 |
|---|---|
| 启动行为 | 儿童模式开启后，**冷启动直接落在儿童主屏**，成人外壳不挂载 |
| 家长门形式 | **随机算术题**（两位数×一位数 / 三位数±两位数），无需记忆、无重置流程，幼儿算不出 |
| 解锁时长 | **本次 App 进程内解锁**——过门一次后进入成人壳，本次运行内不再验证；成人壳中可经设置「回到儿童界面」行**免过门**返回儿童主屏；冷启动自动回到儿童主屏（解锁状态纯内存，不持久化）。实现为三态模型（见 §3 / §5.1），而非单一的 `enabled && !unlocked` 表达式 |
| 会话列表范围 | 儿童主屏**只显示小星老师会话**（`assistantId === DEFAULT_ASSISTANT_ID`，即 `'default'`，见 `models/AssistantModels.ets:26`） |
| 会话列表形态 | **图形化**：主题色渐变卡片 + 大 emoji 头像 + 星星数徽章 + 相对时间，**不用文字标题做主视觉** |
| ChatPage | **复用现有 ChatPage**，儿童模式下隐藏顶栏成人入口（模型选择、助手切换、会话管理菜单），聊天功能全保留 |
| 架构落点 | **方案 A：Index 内嵌分支 + 独立组件目录**——`Index.build()` 顶层按模式分支渲染，全部儿童 UI 隔离在 `components/kids/`；不新建页面、不走 `router.pushUrl`（避开 main_pages.json 已知坑） |

## 3. 架构总览

```
pages/Index.ets
  └─ build() 顶层分支（Index.ets:2031）：
       isKidsUiActive() === true  →  KidsRoot(): Navigation(this.chatTabNavStack) { KidsHomeView(...) }
       isKidsUiActive() === false →  现有内容原样（ExpandedRoot / CompactRoot）

  // 三态模型（Index.ets:152-154）：
  @Local kidsModeEnabled: boolean    // Preferences 开关的本地镜像（持久开关）
  private parentalGateUnlocked: boolean  // 家长门解锁态（纯内存, 冷启动重置；防重复验证）
  @Local kidsRootActive: boolean     // 当前是否渲染儿童主屏（渲染分支标志）

  isKidsUiActive() { return this.kidsRootActive }   // 不再等于 enabled && !unlocked

  状态迁移：
    loadKidsModeEnabled()      启动读 Preferences → kidsModeEnabled = kidsRootActive = enabled，
                               并 setAppUiStateValue(KIDS_MODE_ACTIVE, enabled)
    handleKidsGatePassed()     过门答对 → parentalGateUnlocked = true; kidsRootActive = false（进成人壳）
    handleBackToKidsHome()     成人壳「回到儿童界面」行 → kidsRootActive = true（无需再过门，
                               unlocked 保持 true；先 chatTabNavStack.clear + 复位 TAB_CHAT）
    applyKidsModeToggled(true) 设置里开启 → unlocked = true; kidsRootActive = false（本次运行留成人壳）
    applyKidsModeToggled(false)设置里关闭 → unlocked = false; kidsRootActive = false

components/kids/  (新目录)
  ├─ KidsHomeView.ets       儿童主屏（@ComponentV2）
  ├─ KidsSessionCard.ets    图形化会话卡片（@ComponentV2）
  └─ ParentalGateSheet.ets  算术题门 sheet chrome + 交互（@ComponentV2）

utils/ParentalGateMath.ets  纯函数：出题 + 校验（ArkUI-free，hypium 可测）
```

**关键点：儿童分支必须自带 Navigation 宿主。** `chatTabNavStack` 的 `HdsNavigation` 宿主（Index.ets:2514）挂在 ChatTab 内容里；儿童模式下三 tab 不挂载，栈失去宿主，`pushPath(ChatPage)` 无处渲染。因此儿童分支 `KidsRoot()` 用同一个 `chatTabNavStack` 包一层原生 `Navigation`（`.hideTitleBar(true)` + `.hideToolBar(true)`，复用 `getChatNavigationMode()` / split-layout navBarWidth），`KidsHomeView` 作为栈的 navBar 内容：

- 打开会话 = 现有 `pushPath({ name: CHAT_PAGE_ROUTE, param })` 原样调用（含现有 interception、split-layout 逻辑）
- ChatPage 返回键 pop 回 KidsHomeView
- 零新导航机制，不触碰 `router_map.json` / `main_pages.json`

## 4. 组件设计

### 4.1 KidsHomeView（儿童主屏）

```
┌────────────────────────────┐
│  ⭐ 128                     │  ← 顶部栏：累计星星总数
│                            │     （StarRewardService.getAllTimeStarTotal()，
│                            │      StarRewardService.ets:282）
│  ┌──────────────────────┐  │
│  │   ⭐ 大头像            │  │  ← 大卡片（≈160vp 高，themeAiBubble 外壳语言）
│  │  找小星老师玩！         │  │     副文案：有最近会话→「继续上次」；无→「开始新的」
│  └──────────────────────┘  │     点击 → 打开小星老师最近会话，无则新建
│                            │
│  我的学习乐园                │  ← 图形化会话列表（垂直滚动，仅列表非空时显示）
│  ┌────┐ ┌────┐ ┌────┐      │
│  │🎨 ⭐3│ │🔤 ⭐1│ │➕ ⭐5│   │  ← KidsSessionCard，2 列网格或全宽行，plan 阶段定
│  │ 昨天 │ │周一 │ │9/2 │    │
│  └────┘ └────┘ └────┘      │
│                            │
│              家长入口 (小灰字) │  ← 右下角，text_tertiary 12vp，不吸引孩子
└────────────────────────────┘
```

- **列表只读**：无长按删除/重命名/多选——会话管理全部在家长门后
- 会话数据复用 Index 现有数据源，前端过滤 `assistantId === DEFAULT_ASSISTANT_ID`
- 空列表 → 只显示大卡片 + 顶部星星栏
- 星星徽章 = 该会话累计星星（§5.2 新查询）；**0 星会话不显示徽章**
- 视觉基调：小星老师主题色 `#FF9F43` 系暖色，大圆角、大触控目标（≥48vp），字号偏大（儿童可读）

### 4.2 KidsSessionCard（图形化会话卡片）

| 元素 | 来源 |
|---|---|
| 背景 | 助手主题色渐变（`withColorAlpha` + LinearGradient，与 NumberPuzzleCard tile 渐变同语言） |
| 大 emoji | 小星老师头像 `⭐`（AssistantModels）；后续若按会话内容区分 emoji 属增强项，本期固定用助手头像 |
| 星星徽章 | `⭐ N`（N = 会话累计星星，>0 才显示） |
| 相对时间 | 「昨天」「周一」「9/2」——复用/扩展现有会话列表的时间格式化 util（plan 阶段确认具体文件） |
| 点击 | 回调 Index 打开对应会话（pushPath ChatPage） |

**不渲染**：文字标题、消息预览、草稿标识。

### 4.3 ParentalGateSheet（算术题家长门）

- 挂载：KidsHomeView「家长入口」→ `bindSheet`（FIT_CONTENT，自绘标题「家长验证」+ ✕，样式参照 `VerticalMathHelpSheet` chrome）
- 出题：`ParentalGateMath.generate()` 随机两类混合：
  - 两位数 × 一位数（如 17×6，积 ≤ 999）
  - 三位数 ± 两位数（如 482−57，差 > 0）
- 输入：自绘数字键盘（样式参照 `VerticalMathNumberPad` 但不复用组件——它绑定竖式回调）或 `TextInput(InputType.Number)` + 确认键，**取实现简单者，plan 阶段定**
- 答错：红色抖动反馈 + `generate()` **换新题**（防同一题穷举试错）
- 答对：关 sheet → 回调 Index `handleKidsGatePassed()`：置 `parentalGateUnlocked = true` 且 `kidsRootActive = false` → Index 重渲染成人壳
- 关闭（✕ / 拖拽）：不解锁，停留在儿童主屏

### 4.4 utils/ParentalGateMath.ets（纯函数）

```typescript
export interface GateQuestion {
  text: string        // "17 × 6"
  answer: number      // 102
}

export function generateGateQuestion(): GateQuestion   // 随机两类混合，保证 answer > 0
export function checkGateAnswer(q: GateQuestion, input: string): boolean
  // 前端拦截空/非数字/超长输入，返回 false 不抛异常
```

ArkUI-free，全量 hypium 单测覆盖（§8）。

## 5. 状态与持久化

### 5.1 状态字段（三态模型）

> **v1 修订（2026-09-11）**：原设计的两态表达式 `isKidsUiActive = kidsModeEnabled && !parentalGateUnlocked` 会导致过门后孩子无法回到儿童主屏（渲染分支在本次运行内永久关闭）。实现改为三态：`kidsModeEnabled`（持久开关）/ `parentalGateUnlocked`（防重复验证）/ `kidsRootActive`（当前渲染分支），配合成人壳设置面板的「回到儿童界面」行（见 §6.2）闭合回路。

| 项 | 方案 |
|---|---|
| `kidsModeEnabled`（持久化 + Index `@Local` 镜像） | `PreferencesService` 键 `kids_mode_enabled`，boolean，默认 false；Index 持有 `@Local kidsModeEnabled` 镜像驱动设置面板行（副标题/「回到儿童界面」行显隐） |
| 全局响应式镜像 | `AppUiState` 新增 `@Trace kidsModeActive: boolean` + `AppStorageKeys.KIDS_MODE_ACTIVE`，经 `setAppUiStateValue` 写入——**ChatPage 靠它裁剪成人入口**（不依赖 Index 传参）。注意：它是 `kids_mode_enabled` 的镜像（启动加载与开关翻转时写入，过门解锁**不**改变它），即儿童模式开启期间 ChatPage 始终裁剪。MEMORY 已知坑：必须用 `setAppUiStateValue`，不能裸 `AppStorage.setOrCreate` |
| `parentalGateUnlocked`（内存） | Index 私有字段（非响应式），不持久化、不进 AppUiState；过门置 true，仅用于"本次运行内不再弹门" |
| `kidsRootActive`（内存，`@Local`） | Index 渲染分支标志：`build()` 顶层 `isKidsUiActive()` 直接返回它。冷启动 = enabled；过门 → false；「回到儿童界面」→ true（无需再过门）；开关翻转 → false |
| 启动加载 | Index `loadKidsModeEnabled()` 读 Preferences → 写 `kidsModeEnabled` / `kidsRootActive` + `setAppUiStateValue`；读取失败默认 false（成人壳，绝不把孩子锁死） |

### 5.2 每会话星星数（新查询）

`DatabaseService` 新增：

```typescript
async getStarTotalsBySession(): Promise<Map<string, number>>
// SELECT session_id, SUM(stars) AS total FROM star_events
//   WHERE session_id IS NOT NULL AND session_id != '' GROUP BY session_id
```

- 现有 `star_events` 表已含 `session_id` 列（teaching-architecture §8），无需迁移
- 查询失败 → 返回空 Map，卡片不显示徽章（优雅降级）
- KidsHomeView 在 `aboutToAppear` 及会话返回（onShown / pop 回主屏）时刷新

### 5.3 会话过滤

复用 Index 现有会话数据源（`rebuildSessionListGroupViewModels` 所用的 sessions 数组），前端过滤 `assistantId === DEFAULT_ASSISTANT_ID`。不新增 ViewModel 层。

## 6. ChatPage 裁剪 + 设置开关

### 6.1 ChatPage（读 `AppUiState.kidsModeActive`）

**隐藏（凡通向服务商/模型/助手/会话管理的触点）：**
- 顶栏模型选择入口：`ChatTitleStackBuilder` 传 `modelSelectEnabled: !this.kidsModeActive`——模型名仍显示但不可点、无 chevron
- 标题栏管理菜单：`getTitleBarMenuItems()` 中消息地图 / 重命名标题 / 重新生成标题 / 删除会话 4 项包在 `if (!this.kidsModeActive)` 内，儿童模式下菜单只剩「今日小明星」
- ~~顶栏助手头像/名称的切换 sheet 入口~~ **（v1 修正：该入口不存在）**——经 grep 验证，ChatPage 标题栏**没有**助手切换 sheet 入口；助手切换只存在于 Index / 助手编辑页，而儿童模式下成人外壳（含这些页面）根本不挂载，故 ChatPage 侧无需任何处理

**保留：** 输入、发送、停止、工具卡片渲染、语音、全部聊天功能。

> 具体触点清单在 plan 阶段逐个 grep ChatPage 顶栏 Builder 确认，原则不变：**管理面隐藏，聊天本体不动**。

### 6.2 设置开关（成人壳设置面板）

- 「儿童模式」行位于 `IndexSettingsPanel` 的「学习中心」（`learning_center`）分组首行（key `'kids_mode'`，普通列表行而非 Toggle 组件），副标题按 `kidsModeEnabled` 显示"开启后孩子进入专属学习界面…"/"已开启…"
- **开启**：点击行 → Index `confirmKidsModeToggle()` 弹 `showAlertDialog` 确认——「开启后，下次启动将直接进入儿童界面，返回管理界面需要通过算术题验证」；确认后 `applyKidsModeToggled(true)`：
  1. 写 Preferences `kids_mode_enabled = true`（异步，失败仅记日志）
  2. `setAppUiStateValue(KIDS_MODE_ACTIVE, true)`
  3. `parentalGateUnlocked = true` 且 `kidsRootActive = false`（**避免家长开完开关把自己锁在门外**——本次运行内停留在成人壳）
  4. 下次冷启动 `loadKidsModeEnabled()` 置 `kidsRootActive = true` 生效，直达儿童主屏
- **关闭**：同一行点击 → 确认对话框 → `applyKidsModeToggled(false)`：写回 Preferences + AppUiState，`parentalGateUnlocked` / `kidsRootActive` 均复位 false，立即恢复普通启动行为
- **「回到儿童界面」行**（三态模型的回路闭合点）：同在 `learning_center` 分组（splice 到 index 1），**仅 `kidsModeEnabled === true` 时显示**；icon 用 `sys.symbol.arrow_clockwise`（原拟 `arrow_uturn_left` symbol 不存在）；点击 → Index `handleBackToKidsHome()`：校验 enabled → `chatTabNavStack.clear(false)` 清掉成人壳可能推入的详情路由 → 复位 `TAB_CHAT` → `kidsRootActive = true`，**立即回儿童主屏、不弹算术题**（本次运行 `parentalGateUnlocked` 保持 true，再进成人壳无需重验）
- ForEach key 携带开关态（`learning_center:on` / `learning_center:off`）：面板常驻挂载时切换开关，固定 key 会复用旧子树导致副标题 / 「回到儿童界面」行不刷新

## 7. 错误处理

| 场景 | 处理 |
|---|---|
| `kids_mode_enabled` 读取失败 | 默认 false → 成人壳（优雅降级） |
| 星星汇总查询失败 | 空 Map → 卡片不显示徽章 |
| 最近会话打开失败（会话已删） | 回退到新建小星老师会话 |
| 家长门输入非法（空/非数字/超长） | `checkGateAnswer` 返回 false，不抛异常、不消耗题目 |
| 儿童模式下小星老师被禁用/删除 | 不可能发生——默认助手锁定（AssistantService.normalizeAssistant），无需处理 |

## 8. 测试策略

- **hypium 单测**（`entry/src/ohosTest/ets/test/utils/`）：
  - `ParentalGateMath.test.ets`：题目范围（操作数位数、积/差上限、answer > 0）、`checkGateAnswer` 正误/非法输入、多次生成不恒同
  - 星星按会话聚合若抽纯函数（行数组 → Map）则一并覆盖
- **CLI 验证**：干净 `assembleHap`（MEMORY：hvigor 无 lint/test CLI 任务）
- **人工验收清单**（DevEco 模拟器）：
  - [ ] 设置开启儿童模式 → 确认对话框 → 本次运行仍在成人壳
  - [ ] 冷启动 → 直达儿童主屏，三 tab 不可见
  - [ ] 大卡片 → 打开最近小星老师会话 / 无会话时新建
  - [ ] 列表只显示小星老师会话；卡片无文字标题；星星徽章正确；0 星不显示徽章
  - [ ] 列表只读：无长按/删除/多选
  - [ ] ChatPage：无模型选择/助手切换/会话管理入口；聊天、工具卡片全功能正常；返回键回儿童主屏
  - [ ] 家长入口 → 算术题 → 答错换题 + 抖动 → 答对进成人壳 → 本次运行内自由往返
  - [ ] 成人壳内关闭儿童模式 → 下次冷启动恢复普通外壳
  - [ ] 深色模式 / 主题色切换下儿童主屏视觉正常
  - [ ] Preferences 损坏/首装（无键）→ 默认成人壳

## 9. 触点文件清单

| 文件 | 改动 |
|---|---|
| `pages/Index.ets` | build() 顶层分支 + `KidsRoot(): Navigation(chatTabNavStack){KidsHomeView}` + 三态字段（`kidsModeEnabled` / `parentalGateUnlocked` / `kidsRootActive`）+ 启动读 Preferences + `handleKidsGatePassed` / `handleBackToKidsHome` / `confirmKidsModeToggle` |
| `components/kids/KidsHomeView.ets` | **新建** |
| `components/kids/KidsSessionCard.ets` | **新建** |
| `components/kids/ParentalGateSheet.ets` | **新建** |
| `utils/ParentalGateMath.ets` | **新建**（纯函数） |
| `state/AppUiState.ets` | `@Trace kidsModeActive` + apply 分支 |
| `config/AppStorageKeys.ets` | `KIDS_MODE_ACTIVE` 键 |
| `services/PreferencesService.ets` | `PreferenceKeys` 新键 + 读写封装（随现有模式） |
| `services/DatabaseService.ets` | `getStarTotalsBySession()` |
| `pages/ChatPage.ets` + `components/ChatNavigationTitleContent.ets` | 顶栏成人入口按 `kidsModeActive` 隐藏（标题菜单裁剪 + `modelSelectEnabled` 传参） |
| `components/index/IndexSettingsPanel.ets` | 「儿童模式」行 + 「回到儿童界面」行（learning_center 分组，key 携带开关态） |
| `entry/src/main/resources/{base,zh_CN}/element/string.json` | 各 5 个 `kids_mode_*` 字符串 |
| `entry/src/ohosTest/ets/test/utils/ParentalGateMath.test.ets` | **新建** |

## 10. 明确不做（YAGNI）

- PIN 码 / 双验证方式（只做算术题门）
- 儿童专属简化聊天页（复用 ChatPage）
- 儿童主屏多入口宫格（学写字/迷宫等直达——本期只有大卡片 + 会话列表）
- 会话卡片按内容区分 emoji（固定小星老师头像）
- 限时解锁 / 每次切换都验
- 儿童模式下显示非小星老师会话
- 音效 / 动画彩蛋（后续增强）

## 11. 已知风险与缓解

| 风险 | 缓解 |
|---|---|
| Index.ets 已 5481 行，继续膨胀 | 儿童逻辑全部在 `components/kids/` + `utils/`，Index 只加分支和字段 |
| `chatTabNavStack` 在儿童分支复用后，现有 interception / CHAT_DETAIL_EMPTY_ROUTE / split-layout 逻辑可能有隐藏耦合 | plan 阶段通读 Index.ets:721-940 栈管理逻辑，验收清单覆盖"儿童模式开会话→返回→再开"路径 |
| `UIUtils.addMonitor` 对 @Trace 字段不可靠（MEMORY 已知坑） | 儿童模式切换**不依赖 observer**：Index 直接读 AppUiState 字段渲染分支（组件自身响应式），ChatPage 同理 |
| 算术题对 6-7 岁学过乘法的孩子可能被破解 | 接受——目标用户 5 岁左右；两位数×一位数超纲。若未来需要可升级为 PIN（本期不做） |

---

**前置文档：** `.claude/rules/teaching-architecture.md`（小星老师体系）
**后续：** 实施 plan（writing-plans）
