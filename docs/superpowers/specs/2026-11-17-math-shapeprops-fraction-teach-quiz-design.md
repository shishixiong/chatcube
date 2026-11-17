# 几何图形特征 + 分数初步认识：教学板与出题扩展 设计 spec

**日期：** 2026-11-17
**版本：** v1
**范围：** `entry/src/main/ets/` 内小星数学老师（kids_math）跨出算术——`math_teach` 新增 2 个 mode：`shape_props`（图形特征：数边数角）、`fraction_intro`（分数初步认识：平均分→几分之一→几分之几）；`math_quiz` 扩展 `shape` 题型（shape_ask=name/sides/corners）并新增 `fraction` 题型（identify 看图选分数 / compare 同分母比大小）；画像新增第 11 维 `math_fractions`；shape / fraction 两轨进入完整难度进阶（progression）。
**前置文档：**
- `docs/superpowers/specs/2026-09-26-math-teach-suite-design.md`（math_teach 套件 v1，预校验范式与五步课协议）
- `docs/superpowers/specs/2026-11-17-math-teach-p0-breakten-placevalue-numberline-design.md`（P0 三板，本文档沿用其增量扩展范式与触点配方）
- `docs/superpowers/specs/2026-11-05-math-quiz-progression-design.md`（难度轨 v1，本文档新增 2 轨并升级 shape 轨）
- `.claude/rules/teaching-architecture.md`（教学体系架构）

---

## 0. 设计决策（默认取舍，实现前可调整）

| 决策点 | 结论 | 理由 |
|--------|------|------|
| 几何教学载体 | **新增 mode `shape_props`**，3 步演示课（认一认→数边→数角） | 现有 shape 出题只认名字，「边/角」特征无教学载体；数边数角是图形特征的最小算理单元，对称/拼组/周长面积留 P1+ |
| 可数图形白名单 | **triangle / square / rectangle / pentagon 四种**；circle / star / heart 只用于认名（name），严禁数边角 | 圆的「边」定义有争议（0/1 条曲线边），星形/心形是非凸图形（星形 10 条边）超出一二年级认知；白名单与出题侧共用一份 |
| 分数教学载体 | **新增 mode `fraction_intro`**，2 步演示课（平均分→取几份），双载体 `form: pizza/bar` | 「平均分」是分数概念的唯一算理根基，必须先演示等分再认读写；披萨（扇形）与分数条（长条）是同一模型的两副面孔，参数分叉比两个 mode 清晰（镜像 place_value 的 action 分叉） |
| 分数范围 | **只到真分数初步认识**：分母 2-8、分子 1..分母−1；出题加同分母比大小 | 等值分数、异分母比较、分数加减属 P1；shaded=parts（整体 1）与假分数不进本课 |
| 出题几何扩展 | **复用 type=shape + `shape_ask` 参数**（name/sides/corners，缺省 name），不新增 type | 认名与数边角同属 math_shapes 维度、同一渲染家族；新增 type 会膨胀白名单且割裂图形认知 |
| 分数出题 | **新增 type=fraction**（fraction_ask=identify/compare） | 分数是全新维度与渲染家族（扇形/分数条/竖式分数记号），与 shape 无共享参数 |
| 画像维度 | **新增第 11 维 `math_fractions`（分数）** | 分数有独立难度梯度，复用 math_counting 会污染数数画像；ChildProfileService 是唯一权威源，默认画像/解析自动补维 |
| 难度轨 | **shape 轨升级为完整 5 级轨（原 gate:false 免闸门）；fraction 新建 5 级轨** | 用户选定完整难度轨。shape 旧记录无进度行（免闸门只落库不计进度），升级无迁移负担；认名题归 L1，低龄认名走 warm_up/review |
| 授星 | **讲解不授星**（沿用 v1 §0）；**出题沿用 math_quiz 既有授星**（StarRewardService:78 按 correct=true→1，skill 无关，已验证零改动） | 回执契约不变 |
| 课程基线 | **DEFAULT_MATH_DIMS / DEFAULT_MATH 不动** | 分数是三年级内容，不进 6-7 岁零基础兜底模板；分数课由画像 weakSkills 驱动进课程计划 |
| 图形渲染 | **triangle/pentagon 从 Text 符号（△⬠）升级为 Polygon 精确绘制**；star/heart 保留文字符号 | 数边角必须边角可数、几何精确；文字符号的边数与真实图形不符。扇形用 Path `M/L/A/Z`（NumberLineBoard:132-138 已有 Path.commands 先例），不用 Canvas |

### 0.1 Pre-Step Audit（adding-mini-game-tool 技能强制项）

```
Decision step 4a (StarEventModels 漂移点): NO——quiz 沿用既有 math_quiz activity type，
  teach 不授星，无新 StarActivityType
Decision step 4b (StarRewardService computeStars): NO——:78 math_quiz correct=true→1，
  skill_key 只透传记录（:289-297），新维度自动走通
Decision step 8 (ChatPage largeSize sheet): NO——2 板均按气泡宽度内联渲染
Decision step 9a/9b (Preferences/Database): NO——quiz 记录/进度复用既有表，
  track 为字符串列无枚举约束；讲解无成绩语义、无持久化
Decision（args 校验位置）: handler 预校验 + card 防御兜底，双层沿用 v1
Decision（ToolExecutionService / MessageBubble）: 零改动——handleMathTeach(:897) 与
  handleMathQuiz(:742) 均 mode/type 无关，新 mode/type 自动走通
```

---

## 1. 设计哲学

**关键词：特征可数、等分有根、图数一致。**

现状三个缺口：
1. **图形只认名、不认特征**——shape 题 7 选 1 认名字，孩子说不出「正方形 4 条边 4 个角」，图形认知停在视觉配对，没有属性抽象。
2. **分数零实现**——全项目无 fraction 教学/出题/画像维度（仅 UsageStatsPage:252 的无关局部变量），「平均分」这一分数根基没有演示载体。
3. **图形认知无难度进阶**——shape 轨 gate:false 免闸门，AI 随意出认名题，无法沿「认名→数边→数角」梯度推进。

本 spec 补齐后，图形认知有「特征讲解板 + 特征出题 + 5 级难度轨」完整闭环；分数有「等分演示板 + 看图选分数/同分母比大小 + 5 级难度轨 + 独立画像维度」。教学顺序写进提示词：**shape_props（数边角）→ shape 出题（sides/corners）；fraction_intro（平均分）→ fraction 出题（identify→compare）**。

---

## 2. 总体架构

### 2.1 调用链（与 v1 完全一致，零新链路）

```
AI 调 math_teach(mode=shape_props/fraction_intro, ...)
  → ToolExecutionService.handleMathTeach（既有，mode 无关）
      → validateMathTeachArgs（扩展 2 mode 分支 + SKILL_KEYS +math_fractions）
      → pending → MathTeachCard 内联渲染 → shell 分发到 2 个新板组件
  → 孩子完成关键交互 → 「我学会了 · 继续」→ MathTeachResult 回执（契约不变，不授星）

AI 调 math_quiz(type=shape+shape_ask / type=fraction, ...)
  → ToolExecutionService.handleMathQuiz（既有，type 无关）
      → validateMathQuizArgs（shape 分支扩展 + fraction 新分支）
      → MathQuizHistoryService.evaluateGate → resolveMathQuizLevel
          （shape 轨升级判级 / fraction 新轨判级 → 闸门放行或拒绝）
      → pending → MathQuizCard 渲染（ShapeContent 分叉 / FractionContent 新增）
  → 作答 → recordAnswer 计进度 + recordStarEvent 授星 + math_progress 回执（全既有）
```

### 2.2 文件布局（新增 6 文件，改 14 主代码文件 + 5 测试文件）

```
utils/MathTeachShapeProps.ets              NEW  图形特征纯函数（边角数/顶点几何/步骤/口播）
utils/MathTeachFractionIntro.ets           NEW  分数纯函数（扇形/分数条几何/步骤/口播/读法）
components/mathTeach/ShapePropsBoard.ets   NEW  图形特征演示课（镜像 NumberBondBoard，3 步）
components/mathTeach/FractionIntroBoard.ets NEW 分数初步认识演示课（镜像 NumberBondBoard，2 步）
utils/MathTeachValidation.ets              改   TEACH_MODES +2，SKILL_KEYS +1，validateModeArgs +2 分支
components/MathTeachCard.ets               改   解析/分发/门槛/中文名 +2
config/BuiltinTools.ets                    改   math_teach schema +2 mode；math_quiz schema +fraction/shape_ask；child_profile keys +math_fractions
models/AssistantModels.ets                 改   kids_math 提示词（11 维/九选一/六题型/契约/映射/纪律）
utils/MathQuizGame.ets                     改   QuizType +fraction，Question +6 字段，parse +2 分支，normalizer +4
utils/MathQuizValidation.ets               改   validateShape 扩展 + validateFraction 新增 + 路由
models/MathQuizProgressionModels.ets       改   MathQuizTrack +fraction，MathQuizLevelInput +6 字段
utils/MathQuizProgression.ets              改   SHAPE_ROWS/FRACTION_ROWS +2 表，classify +2，键/初始级/键空间/摘要分支
services/MathQuizHistoryService.ets        改   SUMMARY_TRACKS/SUMMARY_PROFILE_KEYS +shape/fraction
components/MathQuizCard.ets                改   ShapePrimitive 升级 Polygon，ShapeContent 分叉，FractionContent 新增
services/ChildProfileService.ets           改   SKILL_DEFINITIONS +math_fractions（第 11 维）
pages/LearningProfilePage.ets              改   SKILL_GROUPS math keys +math_fractions
utils/LessonPlannerValidation.ets          改   VALID_MATH_DIMENSIONS +math_fractions
utils/LessonPlanPromptUtils.ets            改   维度白名单 + rubric 表 +math_fractions 行
```

板组件不共享状态，各自 `@Local`；shell 持 `interactions` 计数，板 `@Event onInteract` 上报。TTS 沿用 TenFrameBoard 模式（AppStorage `VOICE_MODE_ENABLED` 开关、进入每步朗读、离开即 stop、readonly 不播、只有本板播过才 stop）。

---

## 3. math_teach schema 扩展（7 mode → 9 mode）

### 3.1 mode 与参数

`mode` enum：`number_bond / ten_frame / break_ten / place_value / number_line / balance / clock / shape_props / fraction_intro`

共享参数不变（mode / stage / difficulty / concept / skill_key）。新增专属参数：

| mode | 参数 | 校验约束 | 说明 |
|------|------|----------|------|
| `shape_props` | `shape: string` | triangle / square / rectangle / pentagon 白名单，必填 | 目标图形。⚠️ 严禁 circle/star/heart（不可数边角） |
| `fraction_intro` | `parts: number` | 2-8 整数 | 等分份数（分母） |
| | `shaded: number` | 1..parts−1 整数 | 取的份数（分子）。⚠️ 严禁 shaded ≥ parts（取满即整体 1，超初步认识范围） |
| | `form: string` | pizza / bar 白名单，缺省 pizza | 载体：披萨扇形 / 分数条 |

派生值一律卡片侧算，AI 不传：边角数（n 边形 n 条边 n 个角）、扇形角度（360/parts）、分数读法（「四分之三」）。少一个可填错的参数。

### 3.2 mode ↔ 画像维度映射（写进工具描述 + 提示词）

| mode | skill_key | 算理一句话 |
|------|-----------|-----------|
| shape_props | math_shapes | 图形有几条边几个角，边和角一样多 |
| fraction_intro | math_fractions | 平均分才能用分数：分母是分的份数，分子是取的份数 |

既有 7 mode 映射不变。

### 3.3 注册触点（BuiltinTools.ets）

- `createMathTeachToolDefinition()` rawSchemaJson（:1650-1673）：mode enum（:1653）+2；properties +shape/parts/shaded/form 四字段。**描述内引号一律「」，不得出现裸 ASCII `"`**（JSON.parse 启动炸裂陷阱）。
- 工具描述（:1680）「七种 mode 七选一」→「九种 mode 九选一」，追加 ⚠️ 反例：
  - 「⚠️ 严禁 circle/star/heart 使用 shape_props（圆没有直的边，星形心形边角数不清）」
  - 「⚠️ 严禁 fraction_intro 的 shaded 不小于 parts（取满全部份数是整体 1，不是本课范围）」
  - 「⚠️ 严禁用分数描述不是平均分的东西（份数必须同样大）」
- `createMathTeachToolConfig()`（:1687-1701）描述同步「九种」。
- 验证：JSON.parse gauntlet（`node -e` 提取 rawSchemaJson 并 JSON.parse）。

---

## 4. 两块板交互设计

### 4.1 通用契约（沿用 v1 §4.1）

每板四段：问题行（concept）→ 可玩区 → 算理一句话（随步骤实时变化）→ 控制区。44vp 触控目标 + accessibilityText；KidsBrandTokens 数学色（KIDS_MATH_INK 主色 / KIDS_ACCENT 涂色）+ monoline 图形 + 虚线边框。已答态（readonly）渲染完成态、控制区隐藏、「已学会」药丸，不恢复中间态（草稿纸语义）。

完成门与回执：

| mode | interactionThreshold | 计数来源 |
|------|---------------------|----------|
| shape_props | 3 | 认一认 / 数边 / 数角 三步各计一次 |
| fraction_intro | 2 | 平均分 / 取几份 两步各计一次 |

回执 `MathTeachResult {mode, skill_key, stage, completed, interactions}` 不变，不授星。

### 4.2 shape_props 图形特征演示课（3 步，镜像 NumberBondBoard 演示课范式）

板面：中央 Polygon 大图形（box≈160vp，顶点几何由 utils 算清）+ 下方特征 chip「4 条边 · 4 个角」。

以 shape=square 为例：

| 步 | 标题 | 板面动作 | 算理一句话 | 主按钮 |
|----|------|----------|-----------|--------|
| 1 | 认一认 | 图形弹入 + 名称 chip「正方形」 | 「这是正方形，摸摸它的边和角」 | 数边 |
| 2 | 数边 | 4 条边逐条金色高亮（Line 叠边，逐条 timer），计数 chip 1→4 | 「正方形有 4 条边，4 条边同样长」 | 数角 |
| 3 | 数角 | 4 个角逐个红点高亮（Circle 叠顶点），计数 chip 1→4 | 「正方形有 4 个角，边和角一样多」 | 本课完成 |

形状专属文案（纯函数生成，不硬编码在组件）：square「4 条边同样长」；rectangle「对边同样长」；triangle/pentagon 只报数。第 3 步按钮「本课完成」提前结课（同 NumberBondBoard onFinish 路径）。

**纯函数 `utils/MathTeachShapeProps.ets`**（ArkUI-free、全返回值显式类型注解、防御取界不抛异常）：

```
SHAPE_COUNTABLE: string[]                  // ['triangle','square','rectangle','pentagon']，quiz 侧共用
shapePropsSides(shape): number             // triangle 3 / square 4 / rectangle 4 / pentagon 5；未知 0
shapePropsCorners(shape): number           // 同边数（凸多边形边角等数）
shapePropsVertices(shape, box): number[][] // Polygon 顶点 [x,y][]，居中缩放；rectangle 宽高比 1.6:1
shapePropsSteps(shape): ShapePropsStep[]   // 3 步 {title,chip,desc,narration,hint,action}
shapePropsStepNarrations(shape): string[]  // TTS 口播稿
shapePropsSummary(shape): string           // 「3 条边 · 3 个角」
```

### 4.3 fraction_intro 分数初步认识演示课（2 步）

板面：pizza = 圆形底盘 + parts 个扇形（Path `M/L/A/Z`，涂色份 KIDS_ACCENT 实心、未涂份暖白描边）；bar = 横向长条 Rect 等分（涂色份 KIDS_ACCENT）。下方分数记号区：分子（橙）/ 分数线 / 分母（蓝）竖式排版 + 读法 chip「四分之三」。

以 parts=4, shaded=3, form=pizza 为例：

| 步 | 板面动作 | 算理一句话 |
|----|----------|-----------|
| 1 平均分 | 整圆 → 切割线逐条出现分成 4 个同样大的扇形 | 「把披萨平均分成 4 份，每份同样大——只有平均分才能用分数」 |
| 2 取几份 | 3 个扇形逐份涂橙 + 分数记号 3/4 浮现 | 「平均分成 4 份取 3 份，写成 3/4，读作四分之三；分母 4 是分的份数，分子 3 是取的份数」 |

第 1 步按钮「取 3 份」（文案随 shaded），第 2 步「本课完成」。form=bar 时切割线为竖直等分线，其余一致。

**纯函数 `utils/MathTeachFractionIntro.ets`**：

```
fractionIntroSteps(parts, shaded, form): FractionIntroStep[]  // 2 步 {title,chip,narration,hint,action}
fractionIntroStepNarrations(parts, shaded, form): string[]
fractionSectorCommands(parts, index, box): string  // 第 index 份扇形 Path：M cx cy L x1 y1 A r r 0 0 1 x2 y2 Z
                                                   // 起点 12 点方向（-90°），每份 360/parts；parts=2 半圆 largeArc=0
fractionBarSegments(parts, width): BarSegment[]    // {x,w}[]，等分
fractionReadout(parts, shaded): string             // 「3/4」
fractionReadoutZh(parts, shaded): string           // 「四分之三」（中文数字 1-8 映射）
```

扇形几何全部在此算清（v1 §4.3 约定）；quiz 侧 FractionFigure 复用 fractionSectorCommands / fractionBarSegments（跨 import 先例：MathQuizCard 已 import mathTeach/ClockFaceView）。

---

## 5. math_quiz 题型扩展（5 type → 6 type）

### 5.1 shape 题型扩展：shape_ask

新增参数（MathQuizArgs / schema / MathQuizQuestion 同步）：

| 参数 | 约束 | 说明 |
|------|------|------|
| `shape_ask: string` | name / sides / corners，缺省 name | name=认名（既有行为，向后兼容）；sides=数边；corners=数角 |
| `shape: string` | sides/corners 时必填，∈ SHAPE_COUNTABLE | 目标图形（渲染在题干上方）；name 时忽略 |

- **name**：correct_answer/options 仍是 7 形状英文名（既有白名单不变），渲染不变。
- **sides/corners**：correct_answer 是**数字**（边/角数），options 是数字选项；卡片渲染目标图形 + 数字选项 Grid（复用 ArithmeticContent 的 OptionButton）。**答案权威覆写**：parseMathQuiz 以 shapePropsSides/Corners(shape) 覆写 correctAnswer（镜像 arithmetic 复算 / time 钟面覆写范式），LLM 传错答案不会误判分。

### 5.2 fraction 新题型

| 参数 | 约束 | 说明 |
|------|------|------|
| `fraction_ask: string` | identify / compare，缺省 identify | identify=看图选分数；compare=同分母比大小 |
| `frac_form: string` | pizza / bar，缺省 pizza | 图形载体 |
| `frac_parts: number` | 2-8 整数 | 等分份数（compare 时为公分母） |
| `frac_shaded: number` | 1..parts−1 整数 | 涂色份数（compare 时为左分子） |
| `frac_shaded2: number` | compare 必填，1..parts−1 整数 | 右分子 |

- **identify**：correct_answer 是分数字符串「3/4」，options 是分数字符串。**权威覆写**：correctAnswer = `${frac_shaded}/${frac_parts}`。选项归一化 normalizeFractionString（去空格、分子≥1 分母≥2 整数）；兜底补正确项（镜像 time，options<4 时 push）。
- **compare**：两图同分母并排 + 分数标签，correct_answer 是运算符（> / < / =），**权威覆写**为分子比较真值（镜像 comparison 方向校验）；operator_options 缺省 ['>','<','=']。shaded == shaded2 时真值 '='（合法，教「同样多」）。

### 5.3 MathQuizGame.ets 改动

- `QuizType`（:16）+ `'fraction'`；`normalizeQuizType`（:351-356）+ fraction 分支。
- `MathQuizQuestion`（:18-41）+6 字段：`shapeAsk: string`（默认 'name'）、`shapeTarget: string`（默认 ''）、`fracForm: string`（默认 'pizza'）、`fracParts/fracShaded/fracShaded2: number`（默认 0）。
- `parseMathQuiz`（:127-284）：shape 分支（:181-197）解析 shape_ask/shape，sides/corners 时 correctAnswer 覆写真值数字、options 过滤数字项（镜像 arithmetic :171-180）；新增 fraction 分支（identify/compare 覆写 + 归一化 + 兜底）。
- 新增 normalizer（校验层复用，不重实现）：

```
normalizeShapeAsk(raw): string        // name/sides/corners，未知归 name
normalizeFracForm(raw): string        // pizza/bar，未知归 pizza
normalizeFractionString(raw): string  // 「3 / 4」→「3/4」；分子≥1 分母≥2 整数，否则 ''
fractionCompareTruth(a, b): string    // a>b '>' / a<b '<' / '='
```

### 5.4 MathQuizCard.ets 渲染

- `QuizContent`（:523-545）分发 +fraction → FractionContent；shape 内部按 shapeAsk 分叉。
- `ShapePrimitive`（:648-684）升级：triangle/pentagon 改 `Polygon().points(shapePropsVertices(shape, 48))`（精确边角）；加可选 size 参数（默认 48，目标图形展示区用 96）；circle/square/rectangle/star/heart 画法不变。
- `ShapeContent`（:706-738）：name → 既有 2 列形状 Grid；sides/corners → 题干文字 + 目标图形展示区（ShapePrimitive size 96）+ 数字选项 Grid（复用 OptionButton）。
- `FractionContent`（NEW @Builder）：
  - identify：FractionFigure（pizza：Circle 底盘 + ForEach 扇形 Path().commands(fractionSectorCommands(...))，涂色份 fill KIDS_ACCENT；bar：Row 等分 Rect）+ 分数选项按钮 FractionOptionButton（Column：分子 Text / Divider 分数线 / 分母 Text，竖式记号，72vp 高，2 列 Grid）。
  - compare：Row 双 FractionFigure（同 parts 不同 shaded）+ 各自分数标签 + 中间 ○ + 运算符按钮行（复用 ComparisonContent :795-802 范式）。
- 判分走既有 isCorrectAnswer（identify 字符串 ===、compare 运算符 ===）；两次机会流/草稿纸/确定性洗牌（seed=toolCall.id）全既有，零改动。

---

## 6. 预校验扩展

### 6.1 math_teach（utils/MathTeachValidation.ets）

`TEACH_MODES`（:13-14）7→9；`SKILL_KEYS`（:15-17）+`math_fractions`（10→11）；:70 报错文案「数学画像 10 维之一」→「11 维之一」。`validateModeArgs`（:96-175）新增 2 分支（共享规则 1b/3/4 不动）：

```
shape_props:
  shape ∈ {triangle, square, rectangle, pentagon}
  否则 fail「shape_props 只数直边图形的边角：triangle/square/rectangle/pentagon
  （⚠️ 严禁 circle/star/heart，圆没有直的边，星形心形边角数不清）」

fraction_intro:
  form ∈ {pizza, bar}（缺省 pizza）
  parts ∈ [2,8] 整数
  shaded ∈ [1, parts-1] 整数
  shaded >= parts fail「取满全部份数是整体 1，超出分数初步认识范围（⚠️ 严禁 shaded ≥ parts）」
  shaded < 1 fail「至少要取 1 份」
```

### 6.2 math_quiz（utils/MathQuizValidation.ets）

`validateShape`（:161-178）扩展 + `validateFraction` 新增 + 路由（:297-310）+fraction 分支：

```
shape:
  shape_ask ∈ {name, sides, corners}（缺省 name）
  name: 既有规则不动（7 形状白名单 + 正确答案在选项里 + ≥2 选项）
  sides/corners:
    shape ∈ SHAPE_COUNTABLE，否则 fail（话术同 teach）
    correct_answer 数字（或字符串型数字）=== shapePropsSides/Corners(shape) 真值，
      否则 fail「square 的边数是 4，你给的 correct_answer 是 X，请修正」（权威真值）
    options ≥2 个数字项且含真值

fraction:
  fraction_ask ∈ {identify, compare}（缺省 identify）
  frac_parts ∈ [2,8] 整数；frac_shaded ∈ [1, parts-1] 整数
  identify:
    normalizeFractionString(correct_answer) === 「shaded/parts」，否则 fail（权威覆写口径）
    options ≥2 个合法分数字符串且含正确值
  compare:
    frac_shaded2 ∈ [1, parts-1] 整数
    correct_answer 运算符 === fractionCompareTruth(shaded, shaded2) 真值（方向校验，镜像 comparison）
    operator_options 若给须含正确符
```

校验原则不变：只拒「答案可证明错误」或「卡片不可玩」，纯外观问题（干扰项是否同分母、question 文案）不拦。失败 handler 既有 should_retry 包装自动生效。

---

## 7. 难度轨（shape 升级 + fraction 新建）

### 7.1 SHAPE_ROWS 5 级（utils/MathQuizProgression.ets，镜像 COMPARE_ROWS 结构）

| 级 | label | maxOperand | carryRule | constraint | example |
|----|-------|-----------|-----------|------------|---------|
| 1 | 认图形名字 | 0 | any | shape_ask=name（缺省），7 形状认名 | 「哪个是圆形？」 |
| 2 | 数边（3–4 边） | 4 | none | shape_ask=sides，shape ∈ triangle/square/rectangle | 「正方形有几条边？」 |
| 3 | 数边（5 边） | 5 | none | shape_ask=sides，shape=pentagon | 「五边形有几条边？」 |
| 4 | 数角（3–4 角） | 4 | required | shape_ask=corners，shape ∈ triangle/square/rectangle | 「三角形有几个角？」 |
| 5 | 数角（5 角） | 5 | required | shape_ask=corners，shape=pentagon | 「五边形有几个角？」 |

carryRule 语义复用：none=数边、required=数角、any=认名。maxOperand=最大边数。buildTarget 走既有 constraintTarget 默认分支（:303-307），零改动。

**classifyShape(input)**：ask=name → L1；sides：pentagon→L3 否则 L2；corners：pentagon→L5 否则 L4；shape 不在 SHAPE_COUNTABLE → errInfo('shape', 'circle/star/heart 不适合数边角…')。

### 7.2 FRACTION_ROWS 5 级

| 级 | label | maxOperand | constraint | example |
|----|-------|-----------|------------|---------|
| 1 | 几分之一（分母 2–4） | 4 | identify，frac_shaded=1，frac_parts ∈ 2–4 | 「涂色部分是几分之一？(1/2)」 |
| 2 | 几分之一（分母 5–8） | 8 | identify，frac_shaded=1，frac_parts ∈ 5–8 | 「1/8」 |
| 3 | 几分之几（分母 2–4） | 4 | identify，frac_shaded ≥ 2，frac_parts ∈ 2–4 | 「3/4」 |
| 4 | 几分之几（分母 5–8） | 8 | identify，frac_shaded ≥ 2，frac_parts ∈ 5–8 | 「5/6」 |
| 5 | 同分母分数比大小 | 8 | compare，同分母比分子 | 「2/5 ○ 3/5」 |

maxOperand=最大分母。carryRule 全 any。

**classifyFraction(input)**：parts 越界 / shaded 越界 → errInfo('fraction', …)；identify：shaded=1 → parts≤4?L1:L2；shaded≥2 → parts≤4?L3:L4；compare → L5（shaded2 越界 errInfo）。

### 7.3 挂接点改动（utils/MathQuizProgression.ets + Models）

- `MathQuizTrack`（Models:8）+`'fraction'`（shape 已在联合内）。
- `MathQuizLevelInput`（Models:29-42）+6 字段：`shapeAsk/shapeTarget/correctAnswer: string`、`fracParts/fracShaded/fracShaded2: number`；`buildMathQuizLevelInput`（:387-404）读 raw['shape_ask']/raw['shape']/raw['correct_answer']/raw['frac_parts']/raw['frac_shaded']/raw['frac_shaded2']。
- `SKILL_ALIASES`（:114-135）+`'fractions'`/`'math_fractions'`。
- `resolveMathQuizLevel`（:819-855）：
  - 一致性检查 +`math_fractions` 必须配 `fraction`（镜像 math_shapes :825-826）；
  - **shape 分支（:839-844）从 gate:false 改为 classifyShape(input)**；
  - +fraction 分支 → classifyFraction(input)。
- `errInfo`（:431-437）键排除从 `(track==='none' || track==='shape')` 改为仅 `'none'`（shape 已判级，错误记录也带去重键）。
- `getMaxLevel`（:201-218）/`rowsForTrack`（:220-237）+shape/fraction 分支；`getTrackLabel`（:259-282）+fraction→「分数」（shape→「图形」既有）。
- `initialLevelForTrack`（:333-362）+2 分支：

```
SHAPE_INIT:    [1, 1, 2, 3, 4, 5]   // 下标 = math_shapes 画像 level 0-5
FRACTION_INIT: [1, 1, 2, 3, 4, 5]   // 下标 = math_fractions 画像 level 0-5
```

- `normalizeExpressionKey`（:171-186）+2 分支：

```
shape:    name → 「shape:name:{normalizeShapeName(correctAnswer)}」
          sides/corners → 「shape:{ask}:{shape}」
fraction: identify → 「frac:{parts}:{shaded}」
          compare  → 「frac:{parts}:{shaded}:{shaded2}」
```

- `buildMathQuizRecordExpression`（:188-199）+2 分支：shape name→「认图形:{correct}」、sides→「{shape} 边数」、corners→「{shape} 角数」；fraction identify→「{shaded}/{parts}」、compare→「{shaded}/{parts} ? {shaded2}/{parts}」。
- `estimateLevelKeySpace`（:993-1016）+2 分支（宁小勿大，键空间用尽自动放行重复，防锁死）：

```
shape:    L1=7（7 形状）, L2=3, L3=1, L4=3, L5=1
fraction: L1=3, L2=4, L3=3, L4=18, L5=140
```

  推导：fraction identify 键 = parts×shaded 组合，L1 parts2-4×shaded1=3；L2 parts5-8×1=4；L3 parts2-4 且 shaded≥2：parts2 无、parts3 1 个、parts4 2 个=3；L4 parts5-8：3+4+5+6=18；L5 compare 有序对 Σ(parts−1)² (parts2..8)=1+4+9+16+25+36+49=140。identify 全键空间 3+4+3+18=28，与教学板 28 种组合一致（§8 测试核对）。

### 7.4 摘要与进度（services/MathQuizHistoryService.ets）

`SUMMARY_TRACKS`（:27）+`'shape'`/`'fraction'`；`SUMMARY_PROFILE_KEYS`（:28-29）+`'math_shapes'`/`'math_fractions'`。**关键**：getEffectiveProgress（:50-78）只读 SUMMARY_PROFILE_KEYS 内的画像 level 推导初始级（:63），不加则新轨初始级恒为 1，画像驱动失效。evaluateGate/recordAnswer 逻辑零改动（gate/计进度/授星全由 resolveMathQuizLevel 驱动）。

**迁移说明**：shape 旧免闸门只落库不计进度（recordAnswer :184-191 gate:false 直接 return null），数据库无 shape 进度行，升级后首题按画像初始化，无迁移负担。旧 shape 记录 expressionKey='' 会占去重窗口 1 个唯一键，键空间估值偏小已提前放行，无锁死风险。

---

## 8. 画像第 11 维 math_fractions 触点

ChildProfileService.ets:44-54 `SKILL_DEFINITIONS` 在 math_divide（:50）后插入 `['math_fractions', '分数']`——唯一权威源，createDefaultProfile（:131-140）/parseProfileJson（:159-174）自动补维，旧 JSON 兼容。其余硬编码列举同步：

| 文件:行号 | 改动 |
|------|------|
| `models/AssistantModels.ets:66` | 「【数学】10 维」→11 维 + math_fractions；type 枚举 + fraction |
| `models/AssistantModels.ets:302` | 「聚焦 10 个数学维度」→11 个 + math_fractions |
| `config/BuiltinTools.ets:1290,:1335` | child_profile skill key 列举 + math_fractions |
| `config/BuiltinTools.ets:1585` | math_quiz skill_key 描述 + math_fractions（短名 fractions 自动归一） |
| `pages/LearningProfilePage.ets:40-51` | SKILL_GROUPS math keys + math_fractions |
| `utils/LessonPlannerValidation.ets:38-50` | VALID_MATH_DIMENSIONS + math_fractions |
| `utils/LessonPlanPromptUtils.ets:78-80` | planner 维度白名单 + math_fractions |
| `utils/LessonPlanPromptUtils.ets:162-173` | rubric 表 +行：`| math_fractions | 平均分概念 | 几分之一 | 几分之几 | 同分母比较 | 等值分数 | 分数简单加减 |`（Lv0-3 本 spec 覆盖，Lv4-5 留 P1） |
| `utils/MathTeachValidation.ets:15-17,:70` | SKILL_KEYS + math_fractions；报错文案 10→11 维 |
| `utils/MathQuizProgression.ets:114-135` | SKILL_ALIASES + fractions/math_fractions |

**不动**（动态遍历，已验证）：EvaluationService:606-615（Object.keys 快照）、SkillLabelUtils:40-56（查 SKILL_DEFINITIONS + math_ 前缀推断）、UsageStatsPage、LessonPlannerBaseline DEFAULT_MATH_DIMS/DEFAULT_MATH（§0 决策：分数不进零基础兜底）。

---

## 9. 提示词同步（models/AssistantModels.ets，kids_math 段）

| 行锚点（当前） | 改动 |
|------|------|
| :66 基础提示词 | 10 维→11 维 + math_fractions；type 枚举 + fraction |
| :68 数学题型契约 | 追加：`shape 可带 shape_ask(name 认名/sides 数边/corners 数角),sides/corners 必带 shape(triangle/square/rectangle/pentagon)且 options 是数字;fraction 带 fraction_ask(identify 看图选分数/compare 同分母比大小)/frac_parts(2-8)/frac_shaded(1 到 parts-1),identify 的 options 是分数字符串如「3/4」,compare 再带 frac_shaded2,options 是运算符` |
| :302 维度列举 | 10→11 + math_fractions |
| :305 ②讲解「七选一」 | →「九选一」，列举补 shape_props / fraction_intro |
| :312 【讲解契约】专属参数行 | 追加：`shape_props 给 shape(triangle/square/rectangle/pentagon)数边数角,图形特征先上这课;fraction_intro 给 parts(2-8)/shaded(1 到 parts-1)/form(pizza 披萨/bar 分数条),先立「平均分」概念再认分子分母,分数教学第一课` |
| :313 mode↔skill_key 映射行 | 追加：`shape_props→math_shapes,fraction_intro→math_fractions` |
| :314 讲解板纪律行 | 追加：`分数必须先 fraction_intro 立「平均分」,不是平均分的东西不能用分数表示;circle/star/heart 只认名不数边角;图形特征教学顺序:先 shape_props 板,再 shape 出题 sides/corners` |
| :315 【出题契约】行 | 「type 五选一」→「六选一」+ fraction；追加 shape_ask 与 fraction 参数行（同 :68 口径） |
| :321 strategy 示例 | 「凑十/破十/数数/掰手指」→「凑十/破十/数数/掰手指/平均分/数边角」 |

默认小星老师提示词不动（v1 §0 决策延续）。【难度进度契约】:316 行文 mode 无关（按 mathProgress[].nextTarget），新轨自动生效，不改。

---

## 10. 触点清单（10 步配方裁剪版）

| # | 文件 | 改动 | 验证 |
|---|------|------|------|
| 1 | `utils/SearchToolIdentityUtils.ets` | **不动**（MATH_TEACH/MATH_QUIZ TOOL_ID 既有） | — |
| 2 | `config/BuiltinTools.ets` | §3.3 teach schema；§5 quiz schema（type enum +fraction、+shape_ask/shape/frac_form/frac_parts/frac_shaded/frac_shaded2、correct_answer 描述分叉、:1614 工具描述）；§8 child_profile keys | JSON.parse gauntlet |
| 3 | `services/ToolExecutionService.ets` | **不动**（handleMathTeach/handleMathQuiz mode/type 无关） | grep 确认无硬编码 |
| 4 | StarEventModels / StarRewardService | **跳过**（quiz 授星 skill 无关，:78 已验证） | — |
| 5 | `models/AssistantModels.ets` | §9 九行 | grep fraction_intro ≥ 3 |
| 6 | `utils/MathTeachValidation.ets` | §6.1 | hypium |
| 7 | `utils/MathTeachShapeProps.ets` / `MathTeachFractionIntro.ets`（NEW） | §4 纯函数，强制返回值类型注解（ArkTS 10605038），防御取界不抛异常 | hypium + node harness |
| 8 | `components/mathTeach/ShapePropsBoard.ets` / `FractionIntroBoard.ets`（NEW） | §4 板组件 | assembleHap |
| 9 | `components/MathTeachCard.ets` | TEACH_MODES_ZH（:56-64）+2（图形特征/分数初步认识）；ArgsView（:34-54）+shape/parts/shaded/form 四字段与解析默认值（:89-96,:98-134）；interactionThreshold（:169-182）+2 分支（3/2）；BoardArea（:231-285）分发 +2 | assembleHap |
| 10 | `utils/MathQuizGame.ets` / `MathQuizValidation.ets` | §5.3 / §6.2 | hypium |
| 11 | `models/MathQuizProgressionModels.ets` / `utils/MathQuizProgression.ets` / `services/MathQuizHistoryService.ets` | §7 | hypium（Progression 测试已注册 List.test.ets） |
| 12 | `components/MathQuizCard.ets` | §5.4 | assembleHap |
| 13 | `services/ChildProfileService.ets` / `pages/LearningProfilePage.ets` / `utils/LessonPlannerValidation.ets` / `utils/LessonPlanPromptUtils.ets` | §8 | hypium + assembleHap |
| 14 | MessageBubble / ChatPage / Preferences / Database | **跳过**（路由既有、无 sheet、track 字符串列无 schema 变更） | — |
| 15 | 全部 | gauntlet + assembleHap（宿主执行，沙箱 daemon 卡死见 MEMORY）+ **真机安装验证** | 全绿 |

真机验证清单：
- [ ] AI 能按知识点调起 2 新板且板面正确渲染（含 form=bar / shape=pentagon 分支）。
- [ ] shape_props 3 步完成门 3；fraction_intro 2 步完成门 2；完成后 AI 收回执继续出 math_quiz 操练；不授星。
- [ ] shape sides/corners 题目标图形精确可数（Polygon），答案权威覆写；fraction identify 扇形涂色与分数一致、compare 双图同分母。
- [ ] 坏参被拦且 AI 自修：circle 用 shape_props、fraction_intro shaded=parts、fraction identify 答案与图不一致、compare 方向反、shape sides 答案错。
- [ ] 新轨闸门生效：fraction practice 按 mathProgress target 出题，太易/太难被拒并回 target；10 题首答对升级、连两错降级；shape 认名题在高级别 target 下 practice 被拒（warm_up/review 放行）。
- [ ] 画像页出现「分数」第 11 维；旧画像 JSON 兼容补默认值。
- [ ] 语音模式下 2 板逐步口播、离开即停；readonly 历史态不播、渲染完成态。
- [ ] 既有 7 板 + 5 题型回归不受影响（尤其 shape name 缺省行为、a/b 描述、arithmetic 判分）。

---

## 11. 测试计划

- `MathTeachShapeProps.test.ets`（NEW）：4 形状 sides/corners 真值（3/4/4/5）；未知形状归 0；vertices 数量 = 边数、坐标 ∈ [0,box]；steps 3 步、narrations 3 条；summary 文案。
- `MathTeachFractionIntro.test.ets`（NEW）：**28 种组合**（parts2-8 × shaded1..parts−1 = 1+2+3+4+5+6+7）全部 shaded < parts；steps 2 步；sectorCommands 份数 = parts、parts=2 半圆、坐标 ∈ box；readout「3/4」、readoutZh「四分之三」；防御越界取界。
- `MathTeachValidation.test.ets`（扩展）：shape_props 4 形状收 / circle/star/heart 拒 / 缺 shape 拒；fraction_intro parts=2/shaded=1 收、parts=8/shaded=7 收、shaded=parts 拒、shaded=0 拒、parts=1/9 拒、form 缺省 pizza、form 越界拒；skill_key=math_fractions 收；难度偏差 ±1 与 level=0 跳过沿用既有用式。
- `MathQuizValidation.test.ets`（扩展）：shape name 缺省回归；sides/corners 真值一致收 / 答案错拒 / circle 拒 / 选项缺真值拒；fraction identify 答案一致收 / 「2/4」vs 图 3/4 拒 / 选项缺正确值拒 / parts 越界拒；compare 方向真值收 / 反拒 / shaded=shaded2 → '=' 收 / shaded2 越界拒。
- `MathQuizProgression.test.ets`（扩展，**已注册 List.test.ets:31/:77**）：
  - classifyShape：name→L1、square sides→L2、pentagon sides→L3、triangle corners→L4、pentagon corners→L5、circle sides→error。
  - classifyFraction：1/2→L1、1/4→L1、1/5→L2、1/8→L2、2/3→L3、3/4→L3、2/5→L4、7/8→L4、compare 2/5vs3/5→L5、1/2vs1/2→L5；parts=9/shaded=parts→error。
  - 键格式：shape:name:circle / shape:sides:pentagon / frac:4:3 / frac:5:2:3；recordExpression 文案。
  - estimateLevelKeySpace：shape [7,3,1,3,1]、fraction [3,4,3,18,140]。
  - initialLevelForTrack：math_shapes=3→shape L3、math_fractions=4→fraction L4、level0→L1。
  - 一致性：math_fractions 配 arithmetic→mismatch；math_shapes 配 fraction→mismatch。
  - 闸门：fraction target L1 出 L4→tooHard、出 L1→放行；shape target L3 出 name L1 practice→tooEasy、warm_up→放行（配额内）。
- `LessonPlannerValidation.test.ets`（扩展 :91-95）：白名单 10→11 维断言更新 + math_fractions 收。
- `ChildProfileParse.test.ets`（扩展 :29-30）：旧 JSON 补 math_fractions 默认值断言。
- 运行方式：DevEco Studio 右键测试文件 Run（CLI `hvigorw test` 不可用）；ArkTS 纯函数另用 node 类型剥离跑确定性断言（MEMORY 惯例）；MathTeach* 新测试按惯例不注册进 List.test.ets。

---

## 12. 已知限制与后续可优化

| 限制 | 原因 | 缓解 |
|------|------|------|
| 分数只到同分母比较 | 等值分数/异分母比较/加减属 P1 | rubric Lv4-5 已留位；提示词 strategy 可记孩子自发方法 |
| 图形特征只数边角 | 对称/拼组/周长面积属 P1+ | math_shapes rubric 既有梯度文案不变 |
| circle/star/heart 只认名 | 圆边定义争议、非凸图形超认知 | 白名单机器拦截 + 提示词反例 |
| shape 认名题进 L1 闸门（行为变更） | 完整难度轨决策 | 低龄认名走 warm_up/review（每会话 5/3 配额）；提示词纪律引导 |
| fraction compare 仅同分母 | 异分母需等值分数前置 | P1 扩 compare 异分母几分之一（1/2 vs 1/4） |
| 不涉假分数/带分数/整体 1 | shaded ≤ parts−1 截断 | 后续扩 shaded=parts 边界课 |
| 讲解中间态不持久化 | 草稿纸语义 | readonly 完成态 |
| 分数干扰项不强制同分母 | 外观问题不拦（校验哲学） | 提示词建议 identify 干扰项同分母练分子读数 |

后续可优化：P1 等值分数板（fraction_equivalent：1/2=2/4 叠图）与异分母几分之一比较；图形拼组/对称板；分数加减（同分母）出题；讲解板 TTS 已含，五步课进度条卡片头沿用 v1 展望。

---

## 13. 相关文件速查

| 路径 | 角色 |
|------|------|
| `entry/src/main/ets/utils/MathTeachValidation.ets:13-18,:70,:96-175` | TEACH_MODES/SKILL_KEYS 白名单 + validateModeArgs 扩展点 |
| `entry/src/main/ets/components/MathTeachCard.ets:34-64,:89-134,:169-182,:231-285` | ArgsView/中文名/解析/完成门/BoardArea 分发扩展点 |
| `entry/src/main/ets/config/BuiltinTools.ets:1449-1472,:1518-1614,:1653-1680,:1290,:1335` | quiz/teach schema + child_profile keys |
| `entry/src/main/ets/models/AssistantModels.ets:66,:68,:302,:305,:312-316,:321` | kids_math 提示词同步点 |
| `entry/src/main/ets/utils/MathQuizGame.ets:16,:18-41,:127-284,:348-360` | QuizType/Question/parse/normalizer 扩展点 |
| `entry/src/main/ets/utils/MathQuizValidation.ets:161-178,:289-311` | validateShape 扩展 + 路由 |
| `entry/src/main/ets/utils/MathQuizProgression.ets:56-142,:171-199,:201-362,:387-404,:431-437,:819-855,:993-1016` | 级别表/键/初始级/resolve/键空间扩展点 |
| `entry/src/main/ets/models/MathQuizProgressionModels.ets:8,:29-42` | Track 联合 + LevelInput |
| `entry/src/main/ets/services/MathQuizHistoryService.ets:27-29,:50-78,:184-191` | 摘要数组 + 初始级推导 + 免闸门落库（迁移依据） |
| `entry/src/main/ets/components/MathQuizCard.ets:523-545,:648-738,:777-802` | QuizContent 分发/ShapePrimitive/ShapeContent/Comparison 范式 |
| `entry/src/main/ets/services/ChildProfileService.ets:44-54` | SKILL_DEFINITIONS 第 11 维插入点 |
| `entry/src/main/ets/components/mathTeach/NumberBondBoard.ets` | 2 新板结构镜像源（演示课 + onFinish + TTS） |
| `entry/src/main/ets/components/mathTeach/NumberLineBoard.ets:132-138,:341-346` | Path.commands 弧线先例（扇形几何参照） |
| `entry/src/main/ets/components/mathTeach/ClockFaceView.ets:56-68` | 极坐标点位算法先例（扇形端点参照） |
| `entry/src/main/ets/services/StarRewardService.ets:78,:289-297` | quiz 授星 skill 无关确认点（零改动） |
| `docs/superpowers/specs/2026-11-05-math-quiz-progression-design.md` | 难度轨 v1 spec（状态机/闸门/配额范式） |