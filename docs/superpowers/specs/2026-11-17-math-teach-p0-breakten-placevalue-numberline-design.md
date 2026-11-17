# math_teach P0 三板扩展：破十减法 / 小棒数位 / 数轴跳一跳 设计 spec

**日期：** 2026-11-17
**版本：** v1
**范围：** `entry/src/main/ets/` 内小星数学老师（kids_math）讲解板补齐 P0 算理缺口——`math_teach` 新增 3 个 mode：`break_ten`（破十减法）、`place_value`（小棒与数位）、`number_line`（数轴跳一跳，加减双向）
**前置文档：**
- `docs/superpowers/specs/2026-09-26-math-teach-suite-design.md`（math_teach 套件 v1 + number_bond v2，本文档是其增量扩展；v1 设计了 8 板实际落地 4 板，本 spec 补回其中 2 板并新增 1 板）
- `.claude/rules/teaching-architecture.md`（教学体系架构）
- `.claude/rules/vertical-math-help-sheet.md`（草稿纸语义先例）

---

## 0. 设计决策（默认取舍，实现前可调整）

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 破十减法载体 | **新增 mode `break_ten`**，不给 ten_frame 加 op 参数 | TenFrameBoard 已是 1300+ 行完整引导课（4 步讲解 + 5 题练习 + TTS），混入减法会让状态机翻倍；新板镜像其结构、复用 MathTeachMakeTen 的方块色/明暗函数，成本更低 |
| 破十教法范围 | **只教破十法**（15−9 → 10−9+5）；平十法、想加算减不做 | 一课一法，与凑十课对称；其余策略属 P2 口算策略库，后续另立 spec |
| number_line 方向 | **单 mode + `op: add/sub`**，加法凑十跳、减法破十跳 | 「数轴是加减统一模型」正是 P0 诉求；拆成两个 mode 会膨胀白名单 |
| place_value 形态 | **单 mode + `action: bundle/unbundle`**，捆扎课 / 拆捆课二选一 | 进位算理（满十捆一捆）与退位算理（拆一捆变十根）是同一教具的两面，参数分叉比两个 mode 清晰 |
| 课型深度 | break_ten 镜像 ten_frame（4 步讲解 + 5 题迁移练习）；place_value / number_line 镜像 number_bond v2（2 步演示课，练交给后续 math_quiz） | 破十是最大算理缺口，值得完整闯关；数位与数轴是「看一眼就懂」的过程演示，2 步足够，避免单课超 15 分钟 |
| 授星 | **不授星**，沿用 v1 §0 决策 | 讲解是过程不是成就；回执契约不变，StarEventModels / StarRewardService 零改动 |
| 画像维度 | **不加新维度**：break_ten→math_subtraction，place_value→math_counting，number_line 按 op 映射 math_addition / math_subtraction | 10 维已覆盖；strategy 字段记「破十/捆小棒/数轴跳」即可 |
| place_value 百位 | **不做**：bundle 课 tens ≤ 8（捆完 ≤ 9 捆），不引入百位 | 与 v1 §10 限制一致，百位扩展留后续 |

### 0.1 Pre-Step Audit（adding-mini-game-tool 技能强制项）

```
Decision step 4a (StarEventModels 漂移点): NO——不授星，无新 StarActivityType
Decision step 4b (StarRewardService computeStars): NO——同上
Decision step 8 (ChatPage largeSize sheet): NO——3 板均按气泡宽度内联渲染
Decision step 9a/9b (Preferences/Database): NO——讲解无成绩语义、无持久化
Decision（args 校验位置）: handler 预校验 + card 防御兜底，双层沿用 v1
Decision（ToolExecutionService / MessageBubble）: 零改动——handleMathTeach 与
  isMathTeachFunctionName 路由均 mode 无关，新 mode 自动走通
```

---

## 1. 设计哲学

**关键词：加减对称、竖式有根、一数多形。**

现状三个不对称：
1. **凑十有板、破十无板**——进位加法有十格阵引导课，退位减法却只能靠竖式教步骤，孩子没见过「为什么要借 1」。
2. **竖式教程序、不教算理**——「满十进一」「借一当十」背后的小棒操作（捆一捆 / 拆一捆）没有演示载体。
3. **加法有凑十跳设计、减法没有数轴**——v1 设计的 number_line 未落地，加减法缺统一的「跳一跳」心理模型。

本 spec 补齐后，20 以内进位加 / 退位减各自有「实物板（十格阵）+ 半抽象板（数轴）」双载体，竖式进退位有 place_value 作算理前置课。教学顺序建议写进提示词：**place_value（捆/拆）→ ten_frame / break_ten（凑十/破十）→ number_line（数轴统一）→ vertical_math（竖式程序）**。

---

## 2. 总体架构

### 2.1 调用链（与 v1 完全一致，零新链路）

```
AI 调 math_teach(mode=break_ten/place_value/number_line, ...)
  → ToolExecutionService.handleMathTeach（既有，mode 无关）
      → validateMathTeachArgs（扩展 3 mode 分支）
          失败 → denied + should_retry，AI 自修
      → pending → MathTeachCard 内联渲染（既有挂载点）
          → shell 按 mode 分发到 3 个新板组件
  → 孩子完成关键交互 → 「我学会了 · 继续」
      → MathTeachResult 回执（契约不变）→ AI 按五步课进入操练
```

### 2.2 文件布局（新增 6 文件，改 3 文件）

```
utils/MathTeachBreakTen.ets            NEW  破十课纯函数（步骤/口播/题库/选项）
utils/MathTeachPlaceValue.ets          NEW  小棒数位纯函数（读数/捆拆状态/步骤）
utils/MathTeachNumberLine.ets          NEW  数轴纯函数（两跳几何/步骤/口播）
components/mathTeach/BreakTenBoard.ets NEW  破十减法引导课（镜像 TenFrameBoard）
components/mathTeach/PlaceValueBoard.ets NEW 小棒与数位演示课（镜像 NumberBondBoard）
components/mathTeach/NumberLineBoard.ets NEW 数轴跳一跳演示课（镜像 NumberBondBoard）
utils/MathTeachValidation.ets          改   TEACH_MODES +3，validateModeArgs +3 分支
components/MathTeachCard.ets           改   解析/分发/门槛/中文名 +3
config/BuiltinTools.ets                改   math_teach schema + 描述
models/AssistantModels.ets             改   kids_math 提示词 4 行
```

板组件不共享状态，各自 `@Local`；shell 持 `interactions` 计数，板 `@Event onInteract` 上报。TTS 沿用 TenFrameBoard 模式（AppStorage `VOICE_MODE_ENABLED` 开关、进入每步朗读、离开即 stop、readonly 不播、只有本板播过才 stop）。

---

## 3. math_teach schema 扩展

### 3.1 mode 与参数（4 mode → 7 mode）

`mode` enum：`number_bond / ten_frame / break_ten / place_value / number_line / balance / clock`

共享参数不变（mode / stage / difficulty / concept / skill_key）。新增与修订的专属参数：

| mode | 参数 | 校验约束 | 说明 |
|------|------|----------|------|
| `break_ten` | `a: number` | 11-18 整数 | 被减数（十几）。**复用既有 a 字段**，描述按 mode 分叉 |
| | `b: number` | 2-9 整数，且 **b > a−10** | 减数。必须大于被减数个位，否则不需要退位（退位一致性，镜像凑十一致性） |
| `place_value` | `tens: number` | bundle：0-8；unbundle：1-9 | 十位捆数。bundle 上限 8 保证捆完 ≤ 9 捆，不引入百位 |
| | `ones: number` | bundle：1-9；unbundle：0-9 | 个位散棒数。bundle 至少 1 根才有「添满十」可演 |
| | `action: string` | bundle / unbundle 白名单，必填 | bundle 捆扎课（进位算理）/ unbundle 拆捆课（退位算理） |
| `number_line` | `start: number` | add：6-9；sub：11-18 | 起跳点。add 保证第一跳 ≥1；sub 保证是十几 |
| | `step: number` | add：1-10；sub：2-9 | 跳的总量（加数/减数） |
| | `op: string` | add / sub 白名单，缺省 add | 方向。add 凑十跳（start+step >10 且 ≤20）；sub 破十跳（step > start−10，必须跨过 10） |

派生值一律卡片侧算，AI 不传：break_ten 的 `ones = a−10`、`fromTen = 10−b`、`result = fromTen + ones`；number_line 的 `firstHop / secondHop / end`；place_value 的添棒数 `10−ones`。少一个可填错的参数。

**a/b 字段描述修订**（现有描述只写 ten_frame，须改为按 mode 分叉）：
- `a`：「ten_frame：框内已有个数 5-9；break_ten：被减数 11-18（十几）」
- `b`：「ten_frame：框外散点 1-10，a+b 须 >10 且 ≤20；break_ten：减数 2-9，须大于 a 的个位（⚠️ 严禁不退位的减法用 break_ten）」

### 3.2 mode ↔ 画像维度映射（写进工具描述 + 提示词）

| mode | skill_key | 算理一句话 |
|------|-----------|-----------|
| break_ten | math_subtraction | 个位不够减，把十几拆成 10 和几，先算 10 减几再加回来 |
| place_value | math_counting | 十根捆一捆是进位，拆一捆变十根是退位 |
| number_line（op=add） | math_addition | 数轴上先跳到 10，再跳余数 |
| number_line（op=sub） | math_subtraction | 数轴上先跳回 10，再跳回余数 |

既有 4 mode 映射不变。number_line 的 skill_key 随 op 走，校验规则 4 按传入 skill_key 查画像，不做 op↔skill_key 交叉强制（提示词约束即可，机器只管数值界）。

### 3.3 注册触点（BuiltinTools.ets）

- `createMathTeachToolDefinition()` rawSchemaJson：mode enum +3；properties +tens/ones/action/start/step/op；a/b 描述分叉。**描述内引号一律「」，不得出现裸 ASCII `"`**（JSON.parse 启动炸裂陷阱）。
- 工具描述「四种 mode 四选一」→「七种 mode 七选一」，追加 ⚠️ 反例：
  - 「⚠️ 严禁不需要退位的减法（减数不大于被减数个位，如 15−3）使用 break_ten」
  - 「⚠️ 严禁 number_line op=sub 时 step 不大于 start 的个位（跳不过 10 就不需要破十）」
  - 「⚠️ 严禁 place_value action=unbundle 时 tens=0（没有捆可拆）」
- `createMathTeachToolConfig()` 描述同步「七种」。
- 验证：JSON.parse gauntlet（`node -e` 提取 rawSchemaJson 并 JSON.parse）。

---

## 4. 三块板交互设计

### 4.1 通用契约（沿用 v1 §4.1）

每板四段：问题行（concept）→ 可玩区 → 算理一句话（随步骤实时变化）→ 控制区。44vp 触控目标 + accessibilityText；KidsBrandTokens 数学色 + monoline SVG + 虚线边框。已答态（readonly）渲染完成态、控制区隐藏、「已学会」药丸，不恢复中间态（草稿纸语义）。

完成门与回执：

| mode | interactionThreshold | 计数来源 |
|------|---------------------|----------|
| break_ten | 4 | 讲解 4 步各计一次（练习答对也计，同 ten_frame） |
| place_value | 2 | 演示 2 步各计一次 |
| number_line | 2 | 两跳各计一次 |

回执 `MathTeachResult {mode, skill_key, stage, completed, interactions}` 不变，不授星。

### 4.2 break_ten 破十减法引导课（镜像 TenFrameBoard）

**学一学 4 步**（以 15−9 为例，Numberblocks 方块小人复用 makeTenBlockColor 色系）：

| 步 | 标题 | 板面动作 | 算理一句话 | 主按钮 |
|----|------|----------|-----------|--------|
| 1 | 看个位 | 十格框满 10 + 框外 5 块；个位 5 块闪烁 | 「5 减 9 不够减，怎么办？」 | 拆开 15 |
| 2 | 拆成十和几 | 15 分成「10」与「5」两组，分合 chip 亮起 | 「15 = 10 + 5」 | 用 10 来减 |
| 3 | 十里减 | 从满格框里划掉 9 块（逐块淡出），框里剩 1 | 「10 − 9 = 1」 | 加回来 |
| 4 | 加回来 | 框里剩的 1 块与框外 5 块飞拢合并 | 「1 + 5 = 6，所以 15 − 9 = 6」 | 去练一练 |

**练一练 5 题**（镜像 makeTenPracticeRound）：题库 a∈11-18、b∈2-9、b>a−10（共 36 题）；每题问关键步「10 − b = ?」（3 个唯一选项，值域 [1,9]，seed 确定性轮转），答对自动播放「加回来」动画揭示最终差，答错行内提示再答；优先避开本课 a/b，确定性步长取题不撞题。成绩页同 ten_frame。

**纯函数 `utils/MathTeachBreakTen.ets`**：

```
breakTenOnes(a): number                    // a-10，防御取界 [1,8]
breakTenFromTen(b): number                 // 10-b
breakTenResult(a, b): number               // (10-b)+(a-10)
breakTenLessonSteps(a, b): BreakTenLessonStep[]   // 4 步 {title,chip,desc,narration,hint,action}
breakTenStepNarrations(a, b): string[]     // TTS 口播稿
breakTenPracticePool(): BreakTenProblem[]  // 36 题
breakTenProblem(a, b): BreakTenProblem     // {a,b,fromTen,ones,result,options}
breakTenOptions(fromTen, seed): number[]   // 3 唯一选项 ∈[1,9]，确定性轮转
breakTenPracticeRound(a, b, count): BreakTenProblem[]
```

方块色/明暗/亮色判断 **import 复用 MathTeachMakeTen**（makeTenBlockColor / makeTenShade / makeTenIsLight），不复制。

### 4.3 place_value 小棒与数位演示课（镜像 NumberBondBoard v2 两步式）

板面：左十位列（捆装小棒束 SVG）+ 右个位列（散棒），下方读数 chip「2 捆 8 根 = 28」。

**bundle 捆扎课**（进位算理，以 tens=2, ones=8 为例）：

| 步 | 板面动作 | 算理一句话 |
|----|----------|-----------|
| 1 数一数 | 2 捆 + 8 根，读数 28 | 「2 捆和 8 根，是 28」 |
| 2 满十捆一捆 | 添 2 根散棒逐根弹入 → 个位满 10 → 捆扎动画（10 根收拢成 1 捆飞入十位）→ 3 捆 0 根 = 30 | 「8 根添 2 根满 10，捆成 1 捆放进十位——竖式进位「进 1」就是这一捆」 |

**unbundle 拆捆课**（退位算理，以 tens=3, ones=2 为例）：

| 步 | 板面动作 | 算理一句话 |
|----|----------|-----------|
| 1 数一数 | 3 捆 + 2 根，读数 32 | 「3 捆和 2 根，是 32」 |
| 2 拆一捆 | 十位 1 捆飞入个位散开成 10 根 → 2 捆 12 根，读数仍 32 | 「拆 1 捆变 10 根，还是 32——竖式退位「借 1 当 10」就是拆这一捆」 |

第 2 步按钮文案随 action：「添棒凑十」/「拆一捆」。完成按钮「本课完成」提前结课（同 NumberBondBoard onFinish 路径）。

**纯函数 `utils/MathTeachPlaceValue.ets`**：

```
placeValueRead(tens, ones): number         // tens*10+ones
placeValueAddToTen(ones): number           // 10-ones（bundle 课添棒数）
canBundle(ones): boolean                   // ones >= 10
placeValueSteps(tens, ones, action): PlaceValueStep[]  // 2 步 {title,chip,narration,hint,action}
placeValueAfter(tens, ones, action): PlaceValueState   // bundle→{tens+1,0}；unbundle→{tens-1,ones+10}
```

### 4.4 number_line 数轴跳一跳演示课（2 步）

板面：0-20 数轴 SVG（5 的倍数大刻度标数，刻度字号 ≥10vp，viewBox 缩放适配 320vp 气泡宽）+ token 方块 + 两段弧线。

**op=add 凑十跳**（以 9+5 为例）：

| 步 | 板面动作 | 算理一句话 |
|----|----------|-----------|
| 1 先跳到 10 | 弧线①从 9 到 10（+1），token 弹跳 | 「9 + 1 = 10」 |
| 2 再跳余数 | 弧线②从 10 到 14（+4），token 弹跳 | 「10 + 4 = 14，所以 9 + 5 = 14」 |

**op=sub 破十跳**（以 15−9 为例）：

| 步 | 板面动作 | 算理一句话 |
|----|----------|-----------|
| 1 先跳回 10 | 弧线①从 15 向左到 10（−5） | 「15 − 5 = 10」 |
| 2 再跳回余数 | 弧线②从 10 向左到 6（−4） | 「10 − 4 = 6，所以 15 − 9 = 6」 |

10 处刻度加金色高亮锚点（「10 是中转站」）。两跳方向由 op 决定，弧线开口向上、左跳箭头朝左。

**纯函数 `utils/MathTeachNumberLine.ets`**：

```
numberLineHops(start, step, op): NumberLineHops
  // add: {firstHop:10-start, secondHop:start+step-10, end:start+step, dir:1}
  // sub: {firstHop:start-10, secondHop:step-(start-10), end:start-step, dir:-1}
  // 含 tokenX1/X2/X3 与弧线控制点几何，全部在此算清（v1 §4.3 约定）
numberLineSteps(start, step, op): NumberLineStep[]   // 2 步 {title,chip,narration,hint,action}
```

---

## 5. 预校验扩展（utils/MathTeachValidation.ets）

`TEACH_MODES` 4→7。`validateModeArgs` 新增 3 分支（共享规则 1b/3/4 不动）：

```
break_ten:
  a ∈ [11,18] 整数；b ∈ [2,9] 整数
  b > a-10，否则 fail「break_ten 只讲 20 以内退位减法：减数必须大于被减数个位
  （⚠️ 严禁 15−3 这类不退位减法用 break_ten，直接口算）」

place_value:
  action ∈ {bundle, unbundle}
  bundle: tens ∈ [0,8]，ones ∈ [1,9]
  unbundle: tens ∈ [1,9]（tens=0 fail「没有捆可拆」），ones ∈ [0,9]

number_line:
  op ∈ {add, sub}（缺省 add）
  add: start ∈ [6,9]，step ∈ [1,10]，start+step > 10 且 ≤ 20
       （和不大于 10 fail，话术同 ten_frame 凑十一致性）
  sub: start ∈ [11,18]，step ∈ [2,9]，step > start-10
       （跳不过 10 fail「不需要破十，直接口算」）
```

校验原则不变：只拒「算理可证明矛盾」或「板不可玩」，纯外观问题不拦。失败 handler 既有 should_retry 包装自动生效，ToolExecutionService 零改动。

---

## 6. 提示词同步（models/AssistantModels.ets，kids_math 段 4 行）

| 行锚点（当前） | 改动 |
|------|------|
| L305 ② 讲解「按今日知识点四选一」 | →「七选一」，列举补 break_ten / place_value / number_line |
| L312 【讲解契约】专属参数行 | 追加：`break_ten 给 a(11-18)/b(2-9 且大于 a 的个位),个位不够减就用十里减再加回来;place_value 给 tens/ones/action(bundle 捆扎课讲进位、unbundle 拆捆课讲退位),竖式进退位前先上这课;number_line 给 start/step/op(add 凑十跳 6-9 起跳、sub 破十跳 11-18 起跳),数轴是加减统一的跳一跳模型` |
| L313 mode↔skill_key 映射行 | 追加：`break_ten→math_subtraction,place_value→math_counting,number_line→op=add 配 math_addition、op=sub 配 math_subtraction` |
| L314 讲解板纪律行 | 追加：`不退位的减法不用破十板;退位减法教学顺序:先 place_value 拆捆看「借 1 当 10」,再 break_ten 破十,再 number_line 数轴跳,最后 vertical_math 竖式` |
| L321 strategy 示例 | 「凑十/数数/掰手指」→「凑十/破十/数数/掰手指」 |

默认小星老师提示词不动（v1 §0 决策延续）。`LessonPlanPromptUtils.ets` 维度表已含 math_subtraction / math_counting，rubric 不改。

---

## 7. 触点清单（10 步配方裁剪版）

| # | 文件 | 改动 | 验证 |
|---|------|------|------|
| 1 | `utils/SearchToolIdentityUtils.ets` | **不动**（MATH_TEACH_TOOL_ID 既有） | — |
| 2 | `config/BuiltinTools.ets` | schema mode enum +3、properties +6、a/b 描述分叉、工具/配置描述「七选一」+ ⚠️ 反例 | JSON.parse gauntlet |
| 3 | `services/ToolExecutionService.ets` | **不动**（handleMathTeach mode 无关） | grep 确认无 mode 硬编码 |
| 4 | StarEventModels / StarRewardService | **跳过**（不授星） | — |
| 5 | `models/AssistantModels.ets` | §6 五行 | grep break_ten ≥ 3 |
| 6 | `utils/MathTeachValidation.ets` | §5 | hypium |
| 7 | `utils/MathTeachBreakTen.ets` / `MathTeachPlaceValue.ets` / `MathTeachNumberLine.ets`（NEW） | §4 纯函数，强制返回值类型注解（ArkTS 10605038），防御取界不抛异常 | hypium |
| 8 | `components/mathTeach/BreakTenBoard.ets` / `PlaceValueBoard.ets` / `NumberLineBoard.ets`（NEW） | §4 板组件 | assembleHap |
| 9 | `components/MathTeachCard.ets` | TEACH_MODES_ZH +3（破十减法/小棒与数位/数轴跳一跳）；MathTeachArgsView +tens/ones/action/start/step/op 六字段与解析默认值；interactionThreshold +3 分支（4/2/2）；BoardArea 分发 +3 | assembleHap |
| 10 | MessageBubble / ChatPage / Preferences / Database | **跳过**（路由既有、无 sheet、无成绩） | — |
| 11 | 全部 | gauntlet + assembleHap + **真机安装验证** | 全绿 |

真机验证清单：
- [ ] AI 能按知识点调起 3 新板且板面正确渲染（含 op=sub / action=unbundle 分支）。
- [ ] break_ten 4 步讲解 + 5 题练习完整走通，完成门 4；place_value / number_line 2 步完成门 2。
- [ ] 完成后 AI 收到回执并继续出 math_quiz 操练题；不授星。
- [ ] 坏参被拦且 AI 自修：15−3 用 break_ten、number_line sub 跳不过 10、unbundle tens=0、bundle tens=9。
- [ ] 语音模式下 3 板逐步口播、离开即停；readonly 历史态不播、渲染完成态。
- [ ] 既有 4 板回归不受影响（尤其 a/b 描述分叉后 ten_frame 调用正常）。

---

## 8. 测试计划

- `entry/src/ohosTest/ets/test/utils/MathTeachBreakTen.test.ets`（NEW）：15−9 → ones=5/fromTen=1/result=6；题库 36 题且全部 b>a−10；选项 3 唯一 ∈[1,9] 含正确值；轮次避开本课 a/b、确定性（同参同果）；边界 a=11/b=2 与 a=18/b=9。
- `entry/src/ohosTest/ets/test/utils/MathTeachPlaceValue.test.ets`（NEW）：placeValueRead(2,8)=28；bundle after(2,8)→{3,0}；unbundle after(3,2)→{2,12} 且读数不变；canBundle 边界 9/10；防御越界取界。
- `entry/src/ohosTest/ets/test/utils/MathTeachNumberLine.test.ets`（NEW）：add 9+5 → 1+4 两跳 end=14；add 6+7 → 4+3；sub 15−9 → 5+4 两跳 end=6；sub 11−2 → 1+1 end=9；dir 符号；几何坐标单调性。
- `MathTeachValidation.test.ets`（扩展）：3 新 mode × 合法/越界/缺参；退位边界（15−5 拒 b=5=a−10、15−6 收）；number_line add 和=10 拒/=11 收/=19 收（start≤9、step≤10 时和最大 19，20 不可达）、step 越界拒，sub step=start−10 拒/=start−9 收；place_value action 越界拒、bundle tens=9 拒、unbundle tens=0 拒；难度偏差 ±1 与 level=0 跳过沿用既有用式。
- 运行方式：DevEco Studio 右键测试文件 Run（CLI `hvigorw test` 不可用，见 MEMORY）。

---

## 9. 已知限制与后续可优化

| 限制 | 原因 | 缓解 |
|------|------|------|
| 破十只教一法 | 一课一法，平十/想加算减属 P2 策略库 | 提示词 strategy 字段已可记录孩子自发用的其他方法 |
| place_value 无百位 | bundle tens≤8 截断 | 后续扩百位列（v1 §10 既有展望） |
| number_line 只讲跨 10 的两跳 | 与凑十/破十板配套，不跨 10 的口算不需要演示 | 后续可扩 counting on/back 任意跳（P2 估算载体） |
| break_ten 练习问「十里减」而非最终差 | 关键步检测迁移，最终差由动画揭示 | 与 ten_frame 练「送几块」同范式；操练阶段 math_quiz 测最终差 |
| 讲解中间态不持久化 | 草稿纸语义 | readonly 完成态 |
| op↔skill_key 不做机器交叉校验 | 数值界校验已拦坏课，映射错误属外观问题 | 提示词映射行约束 |

后续可优化：P1 乘除概念板（等组/阵列、等分/包含除）与 bar_model；P2 口算策略库（加倍±1/补偿/一图四式）与流畅度玩法；讲解板 TTS 已含，五步课进度条卡片头沿用 v1 展望。

---

## 10. 相关文件速查

| 路径 | 角色 |
|------|------|
| `entry/src/main/ets/utils/MathTeachValidation.ets:13,95` | TEACH_MODES 白名单 + validateModeArgs 扩展点 |
| `entry/src/main/ets/components/MathTeachCard.ets:47,150,207` | 中文名表 + 完成门 + BoardArea 分发扩展点 |
| `entry/src/main/ets/config/BuiltinTools.ets:1649` | createMathTeachToolDefinition schema |
| `entry/src/main/ets/models/AssistantModels.ets:305,312,313,314,321` | kids_math 提示词同步点 |
| `entry/src/main/ets/utils/MathTeachMakeTen.ets` | break_ten 镜像源 + 方块色函数复用源 |
| `entry/src/main/ets/components/mathTeach/TenFrameBoard.ets` | BreakTenBoard 结构镜像源（4 步 + 5 练 + TTS） |
| `entry/src/main/ets/components/mathTeach/NumberBondBoard.ets` | PlaceValue/NumberLine 两步演示课镜像源 |
| `entry/src/main/ets/services/ToolExecutionService.ets:897` | handleMathTeach（零改动，mode 无关确认点） |
| `docs/superpowers/specs/2026-09-26-math-teach-suite-design.md` | v1 套件 spec（8 板设计、预校验范式、五步课协议） |