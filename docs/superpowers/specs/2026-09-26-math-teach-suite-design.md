# math_teach 讲解工具 + 五步课协议 设计 spec（小星数学老师 v2）

**日期：** 2026-09-26
**版本：** v1
**范围：** `entry/src/main/ets/` 内小星数学老师（kids_math）教学链路升级——新增 `math_teach` 讲解工具（8 块交互讲解板）、五步课协议提示词、画像 2 新维度 + 2 新字段、预校验 5 规则
**前置文档：**
- `docs/math-teaching-suite.html`（交互原型，本文档描述其落地实现）
- `.claude/rules/teaching-architecture.md`（教学体系架构，本文档属 §4 教学工具生态扩展）
- `.claude/rules/number-puzzle-card.md` / `vertical-math-help-sheet.md`（同级组件级设计范例）

---

## 0. 决策记录（2026-09-26 用户确认）

| 决策点 | 结论 |
|--------|------|
| 8 块讲解板范围 | **全部一次做完** |
| 讲解完成是否授星 | **不授星**——讲解是过程不是成就，星星只从 math_quiz / chat_correct 来。跳过 StarEventModels 10 处漂移点整段改动 |
| 助手范围 | **仅 kids_math**——默认小星老师的锁定工具与提示词均不动（其数学段 8 维清单成为 10 维的子集，schema 层不禁止更新新维度，无冲突） |
| 复习步骤工具 | **只加 matching_pairs，不加 number_puzzle**——算式↔结果配对才是数学相关复习；number_puzzle 保持学科分离（游戏老师工具）。HTML 原型契约里写了 number_puzzle，此处有意偏离 |
| matching_pairs schema | **不改**——其内容模型 `{left, right}` 天然支持算式配对（`{left:"9+5", right:"14"}`）；`skill_key` 描述"固定填 observation"保持原样（配对本身即观察力活动，星星计入游戏学科现有行为不变） |

## 0.1 Pre-Step Audit（adding-mini-game-tool 技能强制项）

```
Decision step 4a (StarEventModels 10 处漂移点): NO——产品决策不授星，无新 StarActivityType
Decision step 4b (StarRewardService computeStars 分支): NO——同上
Decision step 8 (ChatPage largeSize sheet): NO——8 块板均按气泡宽度设计，仅内联渲染
Decision step 9a (PreferencesService 最佳分): NO——讲解不是游戏，无成绩语义
Decision step 9b (DatabaseService 记录表): NO——讲解结果由 AI 回执消费，无持久化需求
Decision（args 校验位置）: card 侧 + handler 双层——handler 预校验失败回 should_retry（镜像 math_quiz），
  card aboutToAppear 对 mode 专属参数做防御性兜底（坏参渲染占位而非崩溃）
```

---

## 1. 设计哲学

**关键词：先讲后练、算理可见、动手优先、八板一工具。**

当前 kids_math 的提示词是「出题为主」：8 条策略里 4 条在讲出题，讲解手段只有 vertical_math 竖式一种。孩子一节课刷 10 道题，可能一次凑十的过程都没见过。本 spec 把 kids_math 升级为五步课协议（热身→讲解→操练→输出→复习），核心增量是一把新工具 `math_teach`：AI 按今日知识点八选一调起交互讲解板，孩子先动手摆一摆（凑十跳、借一个、捆小棒），看懂算理后再进入操练。

设计取舍：
- **一个工具八块板（mode 八选一）**，不是八个工具——LLM tool-choice 白名单不膨胀，MessageBubble 只加一套挂载点，与 HTML 原型「新增 1 个讲解工具（不是 8 个）」一致。
- **不授星**：讲解板是"草稿纸 + 教具"，不是答题卡。完成回执只告诉 AI"讲解发生了、孩子动手了"，奖励回路仍由操练题驱动。
- **预校验拦坏课**：讲解参数与算理矛盾（声明凑十却填 9+5=15）的课不进 pending 态，以 `should_retry` 让 AI 自修——与 math_quiz 七题型预校验同范式。
- **组件组织跟随 `verticalMath/` 先例**：shell + 每板一文件 + 纯逻辑 utils 分离可测，不做一个 2000 行巨型卡。

---

## 2. 总体架构

### 2.1 调用链

```
AI 调 math_teach(mode, ...)
  → ToolExecutionService.executeToolCall 特殊路径（math_quiz 分支之后新增 math_teach 分支）
      → handleMathTeach(toolCall, context)
          → ChildProfileService.getInstance().getProfile() 读各维 level
          → validateMathTeachArgs(args, profileLevels)     // utils/MathTeachValidation.ets
              失败 → approvalState='denied'
                     ToolResult {error:'validation_failed', message, should_retry:true}
          → approvalState='pending'，挂 Promise 到 pendingAnswers（镜像 handleMathQuiz L571 结构）
  → MessageBubble 内联渲染 MathTeachCard（isMathTeachFunctionName 路由）
      → shell 按 mode 分发到 components/mathTeach/ 对应板组件
  → 孩子完成关键交互（§4 完成门）→「我学会了 · 继续」
      → onAnswer(toolCallId, JSON.stringify(MathTeachResult))
      → Promise 解决 → 返回回执给 AI（不调 recordStarEvent）
  → AI 收到回执，按五步课协议进入 ③ 操练（math_quiz）
```

### 2.2 文件布局

```
utils/MathTeachValidation.ets          预校验纯函数（validateMathTeachArgs）
utils/MathTeachBoards.ets              板几何纯函数（clockAngles / balanceTilt / barPercents /
                                       numberLineHops / bondSplit / canBundle）
components/MathTeachCard.ets           shell：mode 白名单分发 + 完成门 + 结果回传 + 已答态
components/mathTeach/
  NumberBondBoard.ets                  数的分与合（± 步进探索 + 虚线"好朋友"格）
  NumberLineBoard.ets                  数轴凑十跳（两段弧线动画 +1/+N）
  TenFrameBoard.ets                    十格阵凑十（借一个飞入动画）
  PlaceValueBoard.ets                  小棒与数位（满十捆一捆动画）
  BalanceBoard.ets                     天平比大小（倾斜动画）
  ShapeBoard.ets                       图形拼摆（四形 tile 点选数边角）
  ClockBoard.ets                       时钟拨一拨（时针分针步进）
  BarModelBoard.ets                    应用题图解（两段长条 ± 调整）
```

板组件不共享状态，各自持有 `@Local` 交互状态；shell 持有 `interactions: number` 计数，板通过 `@Event onInteract` 上报关键交互。

---

## 3. math_teach 工具 schema

### 3.1 参数定义

共享参数：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `mode` | string | ✓ | 八选一：number_bond / number_line / ten_frame / place_value / balance / shape / clock / bar_model |
| `stage` | string | ✗ | warm_up / presentation / practice / production / review，缺省 presentation。卡片头部环节标签用 |
| `difficulty` | number | ✓ | 1-5，须与画像等级偏差 ≤1（§5 规则 4） |
| `concept` | string | ✓ | 给孩子看的一句话知识点标题；bar_model 兼作应用题题干（如「小明有 9 个苹果，妈妈又给了 5 个，一共几个？」） |
| `skill_key` | string | ✓ | 对应画像维度（§3.2 映射表），用于难度校验与画像更新提示 |

mode 专属参数：

| mode | 参数 | 校验约束 |
|------|------|----------|
| `number_bond` | `total: number` | 2-20 |
| `number_line` | `start: number` `step: number` | start ∈ [6,9]（保证 cost=10-start ≥ 1，两段跳存在），step ∈ [1,10]，start+step ≤ 20 且 **start+step > 10**（凑十法只讲进位加法；不进位用 math_quiz/vertical_math） |
| `ten_frame` | `a: number` `b: number` | a ∈ [5,9]（框内已有个数），b ∈ [1,10]，a+b ≤ 20 且 a+b > 10（同上进位约束） |
| `place_value` | `tens: number` `ones: number` | tens ∈ [0,8]，ones ∈ [0,9]，不同时为 0；板内 ones 可调到 10 触发捆扎 |
| `balance` | `left: number` `right: number` | 各 ∈ [1,20] |
| `shape` | `focus: string` | circle / square / triangle / rectangle 白名单 |
| `clock` | `hour: number` `minute: number` | hour ∈ [1,12]，minute ∈ {0, 30}（整点/半点） |
| `bar_model` | `part_a: number` `part_b: number` | 各 ∈ [1,9]；concept 非空（题干） |

`number_line` 的 `cost = 10 - start` 由卡片侧派生，AI 不传——少一个可填错的参数。

### 3.2 mode ↔ 画像维度映射（写进工具描述 + 提示词）

| mode | skill_key | 算理一句话 |
|------|-----------|-----------|
| number_bond | math_number_sense | 数的分与合（为凑十打底） |
| number_line | math_addition | 数轴上先跳到 10 再跳余数 |
| ten_frame | math_addition | 十格阵先凑满 10 再看外面剩几 |
| place_value | math_counting | 十根捆一捆，理解十位与个位 |
| balance | math_comparison | 天平两边一放，哪边沉哪边大 |
| shape | math_shapes | 数一数边和角，认识平面图形 |
| clock | math_time | 拨动时针分针，认读整点半点 |
| bar_model | math_word_problem | 长条图把「一共 / 还剩」画出来 |

### 3.3 注册（BuiltinTools.ets，10 步配方 step 2）

- `MathTeachArgs` interface + `MathTeachExecutor`（stub，实际逻辑在 ToolExecutionService 特殊路径）
- `createMathTeachToolDefinition()`：rawSchemaJson 按 §3.1 展开。**描述字段内所有引号用「」，不得出现裸 ASCII `"`**（JSON.parse 启动炸裂陷阱）；凑十约束、进位限定、concept 兼作题干等全部写进 description，并按 tool-call 教训加 ⚠️ 反例（如「⚠️ 严禁 a+b 不超过 10 时使用 ten_frame」）
- `createMathTeachToolConfig()`：名称「数学讲解板」，READ 权限
- `registerBuiltinTools` 注册块 + `getBuiltinToolIds()`（L3020）追加
- 验证：JSON.parse gauntlet（`node -e` 提取 rawSchemaJson 并 JSON.parse）

---

## 4. 八块讲解板交互设计

### 4.1 通用结构

每板四段：问题行（concept，加粗）→ 可玩区 → 算理一句话（board-eq，随交互实时变化）→ 控制区。所有步进按钮 44vp 触控目标、带 accessibilityText；视觉走 KidsBrandTokens 数学色（`KIDS_MATH` 系）+ monoline SVG 风格 + 虚线边框（儿童端品牌契约，dashed 是有意的）。

**完成门**：shell 层持 `interactions` 计数，板通过 `@Event onInteract` 上报；达到阈值后「我学会了 · 继续」按钮亮起。阈值：全板 1 次，shape 为 2（至少点选 2 个图形）。按下后：

```typescript
// MathTeachResult
{
  mode: string,          // 本次讲解板
  skill_key: string,     // 对应画像维度
  stage: string,         // 调用时的 stage
  completed: true,
  interactions: number   // 关键交互次数
}
```

**已答态**（isAnswered=true）：板以初始参数渲染、控制区隐藏、完成按钮替换为「已学会」药丸（status_success 绿）。不恢复孩子离开时的中间态（与竖式帮助 sheet"关闭即清空"同语义——讲解过程不需要持久化）。

### 4.2 各板交互（对齐 HTML 原型）

| 板 | 可玩区 | 关键交互（触发 onInteract） | 算理一句话示例 |
|----|--------|---------------------------|---------------|
| number_bond | 圆点行（左 a 蓝 + 右 b 橙 + 1 个虚线 ghost 格）+ 分合等式 chips | ± 步进器调整左部分（右部分自动补齐） | 「7 和 2 合起来是 9；9 再和 1 做朋友，就能凑成十」 |
| number_line | 数轴 SVG（0-20 刻度，5 的倍数大刻度标数）+ token 方块 | 按「凑十跳」→ 两段弧线依次画出（+1 / +余数），token 从 start 跳到 10 再到 sum | 「9 + 1 = 10，10 + 4 = 14」 |
| ten_frame | 十格阵（a 格已填蓝）+ 框外松散圆点（b 个橙） | 按「借一个凑十」→ 1 个橙点飞入空格，格阵满 10，框外剩 b-1 | 「9 + 1 = 10，10 + 4 = 14」 |
| place_value | 十位列（捆装束）+ 个位列（散棒） | ones 调到 10 →「10 根捆成一捆」亮起 → 按下触发捆扎动画（tens+1, ones=0） | 「个位满 10 根了，捆成一捆放进十位」 |
| balance | 天平 SVG（横梁 spring 倾斜，左盘蓝右盘橙） | ± 调整任一边 → 梁倾角变化（(right−left)×4°，±12° 截断） | 「9 > 5」符号随倾斜切换 |
| shape | 四块 96vp 图形 tile（圆/方/三角/矩形 SVG） | 点选 tile → 显示名称/边数/角数（圆形 0 边 0 角是重点对比项） | 「圆形没有直边和角，这是它和方、三角最大的不同」 |
| clock | 钟面 SVG（12 刻度 + 时针短 + 分针长） | ± 拨时/分针（分针步进 30 分钟），指针 spring 旋转 | 「9 时 30 分 · 短针指时、长针指 6 是半点」 |
| bar_model | 三行长条图（部分 A / 部分 B / 全长） | ± 调整 part_a / part_b → 长条宽度百分比过渡 | 「9 + 5 = 14：两条长条拼成的全长就是一共」 |

### 4.3 纯几何函数（utils/MathTeachBoards.ets）

```
clockAngles(hour, minute): ClockAngles        // {hourDeg = ((h%12)+m/60)*30, minuteDeg = m*6}
balanceTilt(left, right): number              // clamp((right-left)*4, -12, 12)
barPercents(a, b): BarPercents                // {aPct, bPct} 按 a+b 归一
numberLineHops(start, step): NumberLineHops   // {firstHop: 10-start, secondHop: step-(10-start),
                                              //  tokenX1/X2/X3, arc 控制点}——数轴几何全部在此算清
bondSplit(total, left): number                // total-left，含 0 ≤ left ≤ total 防御
canBundle(ones): boolean                      // ones >= 10
```

全部模块级纯函数、强制类型注解返回值（ArkTS 10605038），hypium 全覆盖（§8）。

---

## 5. 预校验（utils/MathTeachValidation.ets）

```typescript
export interface MathTeachValidationResult { ok: boolean; error: string }
export function validateMathTeachArgs(
  args: Record<string, Object>,
  profileLevels: Record<string, number> | null   // handler 注入；null 跳过规则 4
): MathTeachValidationResult
```

5 规则（与 HTML 原型「预校验新增规则」对应）：

1. **mode 白名单**：八选一，越界即拒。mode 专属参数缺失/越界也归入此规则（§3.1 各行约束）。
2. **凑十一致性**：ten_frame/number_line 的 a+b ≤ 20 且 > 10（进位限定——和不大于 10 根本不需要凑十，讲解板与算理直接矛盾）。本工具无 expression 参数，无需复算引擎，校验全是数值界与白名单判断。
3. **概念—模式匹配**：number_bond 必给 total；bar_model 必给两部分且 concept 非空；shape 的 focus 在白名单；clock 的 minute ∈ {0,30}。
4. **难度—画像一致**：`|difficulty − profileLevels[skill_key]| ≤ 1`。level=0（未评估）与 skill_key 缺失时跳过（0 是"从未评估"不是"低水平"）。handler 读 ChildProfileService 后传入，纯函数保持可测。
5. **演示后必练**：**prompt 契约，非机器校验**——工具调用时刻无法预知 AI 下一步。写进五步课协议（§6），AI 自律。

失败统一返回 `{ok:false, error:'<中文具体原因>'}`，handler 镜像 handleMathQuiz L585-600 的 should_retry 包装。校验原则同 MathQuizValidation：只拒绝「算理可证明矛盾」或「板不可玩」的课，纯外观问题（concept 文案弱、stage 怪异）不拦。

---

## 6. 五步课协议（提示词 + 锁定工具）

### 6.1 KIDS_MATH_SYSTEM_PROMPT「数学教学策略」段重写

替换现「聚焦 8 个数学维度…出题必须用 math_quiz…」段（AssistantModels.ets L257-264 区域）为：

```
## 数学教学策略 · 五步课协议
- 聚焦 10 个数学维度:math_number_sense / math_counting / math_addition / math_subtraction /
  math_multiply / math_divide / math_shapes / math_comparison / math_time / math_word_problem。
- 每节课按五步推进,讲解必须先发生,不让孩子在没看懂算理前刷题:
  ① 热身 warm_up:math_quiz(type:arithmetic) 口算接龙 2-3 道,唤醒旧知;
  ② 讲解 presentation:math_teach 先摆一摆再讲算理——数的分与合 number_bond / 数轴跳 number_line /
     十格阵凑十 ten_frame / 小棒数位 place_value / 天平比大小 balance / 图形 shape /
     时钟 clock / 应用题图解 bar_model,按今日知识点八选一;
  ③ 操练 practice:math_quiz / vertical_math 巩固 1-2 题;
  ④ 输出 production:ask_user 让孩子用自己的话讲算理,或 math_verify 验算;
  ⑤ 复习 review:matching_pairs 出算式↔结果配对(left 填「9+5」,right 填「14」),留一个明天验证的钩子。
- mode 与 skill_key 对应:number_bond→math_number_sense,number_line/ten_frame→math_addition,
  place_value→math_counting,balance→math_comparison,shape→math_shapes,clock→math_time,
  bar_model→math_word_problem。
- 讲解板约束:ten_frame/number_line 只讲 20 以内进位加法(和不大于 10 的不用凑十,直接口算);
  讲解参数必须与算理一致,算式是几就摆几。
- 难度跟随画像:各维度 level 决定 math_teach 的 difficulty 与 math_quiz 难度,偏差不超过 1 级;
  level 0-1 从实物+数数开始,不给三位数进位。
- 三类禁止:连续出题不讲解;讲解参数与算理矛盾;超龄难度。
- child_profile(action:"update") 只更新 math_ 开头的技能维度,notes 必须基于本轮具体表现;
  把孩子解题用的方法(凑十/数数/掰手指)记入 strategy 字段,
  常错点(忘记进位/方向反/数位没对齐)记入 misconceptions 字段。
```

授星规则段、边界段不动。

### 6.2 锁定工具

```typescript
// AssistantModels.ets KIDS_MATH_LOCKED_TOOL_IDS（L144）
export const KIDS_MATH_LOCKED_TOOL_IDS: string[] = [
  ASK_USER_TOOL_ID, CHILD_PROFILE_TOOL_ID, GET_TIME_INFO_TOOL_ID, GRANT_STAR_TOOL_ID,
  MATH_VERIFY_TOOL_ID, MATH_QUIZ_TOOL_ID, VERTICAL_MATH_TOOL_ID,
  MATH_TEACH_TOOL_ID, MATCHING_PAIRS_TOOL_ID      // ← 新增 2 个
]
```

注册表锁定（`getBuiltInAssistantSpec`）自动覆盖老用户：`normalizeAssistant` 强制覆盖 enabledToolIds，`ensureKidsSubjectAssistants` 幂等补建时写入新提示词——老 kids_math 会话不受影响（提示词在会话级 buildRequestSystemPrompt 时重读 assistant.systemPrompt，新会话即刻生效）。

---

## 7. 画像扩展（2 维 + 2 字段，7 处同步）

| # | 文件 | 改动 |
|---|------|------|
| 1 | `services/ChildProfileService.ets` | `SkillDimension` + `strategy: string = ''` / `misconceptions: string = ''`（L6 类）；`SKILL_DEFINITIONS` 24→26：`['math_number_sense','数感与数的组成']` 插在 math_counting 后，`['math_word_problem','解决问题']` 加在 math_time 后（L36-61）；`parseProfile` 解析 2 新字段（旧 JSON 缺省 ''，向后兼容）；`saveProfile`/序列化侧同步写入 |
| 2 | `config/BuiltinTools.ets` child_profile schema | `skill_updates.items.properties` + `strategy`/`misconceptions` optional string（描述用「」引号）；L1247 key 枚举 description 与 L1284 工具描述补 2 新 key（24→26） |
| 3 | `config/BuiltinTools.ets` handleUpdate（L1150-1181） | 透传：`item['strategy']`/`item['misconceptions']` 非空才覆盖（镜像 notes 的"非空才写"策略，防 AI 局部更新清空历史） |
| 4 | `pages/LearningProfilePage.ets` | math 组 keys +2（L38 区域）；维度卡在 notes 区下方以小标签渲染 strategy/misconceptions（非空才显示） |
| 5 | `utils/LessonPlannerValidation.ets`（L36） | 合法维度表 +2 |
| 6 | `utils/LessonPlanPromptUtils.ets` | L67 维度清单 +2；L135 进阶表加 2 行（number_sense：L1 分与合→L2 凑十朋友→L3 拆 10→L4 灵活拆→L5 多种拆法；word_problem：L1 听题摆图→L2 看图列式→L3 加减应用题→L4 两步题→L5 自编题） |
| 7 | `models/AssistantModels.ets` | kids_math 提示词（§6.1 已含）。**默认小星老师提示词不改**；LessonPlannerBaseline CORE_DIMS 不动（4 核心默认维度不变） |

串 access 无关紧要的顺序点：`KidsSubjectUtils.countTodayBySubject` 按活动类型计数，与画像维度无关，不动。

---

## 8. 触点清单（adding-mini-game-tool 10 步配方裁剪版）

| # | 文件 | 改动 | 验证 |
|---|------|------|------|
| 1 | `utils/SearchToolIdentityUtils.ets` | `MATH_TEACH_TOOL_ID` 常量 + `isMathTeachFunctionName()` | grep ≥ 2 |
| 2 | `config/BuiltinTools.ets` | import、`MathTeachArgs`、stub executor、`createMathTeachToolDefinition`、`createMathTeachToolConfig`、注册块、`getBuiltinToolIds()`；child_profile schema/描述/handleUpdate（§7 #2 #3） | JSON.parse gauntlet |
| 3 | `services/ToolExecutionService.ets` | import、`handleMathTeach()`（镜像 handleMathQuiz：校验→pending→Promise→回执，**无 recordStarEvent**）、dispatch 分支置于 math_quiz 分支之后、resolveToolId 兜底之前 | grep ≥ 3；分支位置 |
| 4 | ~~StarEventModels~~ / ~~StarRewardService~~ | **跳过**（不授星） | — |
| 5 | `models/AssistantModels.ets` | KIDS_MATH_LOCKED_TOOL_IDS +2；KIDS_MATH_SYSTEM_PROMPT 数学段重写；`SharedPromptFragments` 不动 | grep MATH_TEACH ≥ 3 |
| 6 | `components/MathTeachCard.ets`（NEW）+ `components/mathTeach/` 8 板（NEW） + `utils/MathTeachValidation.ets` + `utils/MathTeachBoards.ets`（NEW） | 见 §2 §4 §5 | hvigorw assembleHap |
| 7 | `components/MessageBubble.ets` | 7 处：import / 内联渲染 guard / isToolStepClickable or 链 / isDefaultExpanded or 链 / isAutoExpandable or 链 / handleToolStepClick switch / step-content switch | 精确行校验（7 站点逐个核对） |
| 8 | ~~ChatPage largeSize~~ | **跳过**（Decision step 8 = NO） | — |
| 9 | ~~Preferences/Database~~ | **跳过**（Decision step 9 = NO） | — |
| 10 | 全部 | JSON.parse gauntlet + 4-grep（本例退化为 MATH_TEACH 身份 grep）+ assembleHap + **真机安装验证** | 全绿 |

真机验证清单：AI 讲解课能调起 math_teach 且板面正确渲染；8 块板关键交互与完成门各自生效；完成后 AI 收到回执并继续出操练题；坏参数（mode 越界 / ten_frame a+b≤10）被拦且 AI 自修重试；数学画像页显示 10 维与新标签；工具中心出现「数学讲解板」。

---

## 9. 测试计划

- `entry/src/ohosTest/ets/test/utils/MathTeachValidation.test.ets`（NEW）：8 mode × 合法/越界/缺参/凑十边界（a+b=10 拒、=11 收、=20 收、=21 拒）、难度偏差 ±1 边界、level=0 跳过、profileLevels=null 跳过。镜像 MathQuizValidation.test.ets 结构。
- `entry/src/ohosTest/ets/test/utils/MathTeachBoards.test.ets`（NEW）：clockAngles（9:30 → 285°/180°）、balanceTilt（截断 ±12）、barPercents（归一）、numberLineHops（9+5 → 1+4 两跳；6+7 → 4+3）、bondSplit 防御。
- 画像向后兼容：旧 JSON（无 strategy/misconceptions、24 维）parse 后 26 维齐全、新字段 ''（在 ChildProfileService 既有测试模式上扩展，如无则补最小用例）。
- 运行方式：DevEco Studio 右键测试文件 Run（CLI `hvigorw test` 不可用，见 MEMORY）。

---

## 10. 已知限制与后续可优化

| 限制 | 原因 | 缓解 |
|------|------|------|
| 讲解中间态不持久化 | 草稿纸语义（同竖式帮助 sheet） | 已答态显示初始板面 +「已学会」 |
| 规则 5「演示后必练」靠 prompt 自律 | 工具调用时刻无法预知下一步 | 提示词五步课协议强约束；后续可在会话层做"讲解后未出题"检测提醒 |
| 难度校验依赖画像已评估 | 未评估维度（level 0）跳过 | 提示词要求 AI 先 child_profile read 再上课（既有协议） |
| clock 仅整点/半点 | spec 范围（5-7 岁） | 后续可扩 15/45 分 |
| matching_pairs 复习计入游戏学科星数 | 沿用现有活动类型归属，不改 | 已在 §0 记录为有意行为 |
| 数轴/十格阵 SVG 在 360dp 屏约 320vp 宽 | 气泡宽度约束 | viewBox 缩放，刻度字号 ≥ 10vp 保证可读 |

后续可优化：讲解板接入 TTS 朗读算理一句话；place_value 扩展百位；bar_model 支持减法情境（还剩）；五步课进度条卡片头（①-⑤ 高亮当前环节）。

---

## 11. 相关文件速查

| 路径 | 角色 |
|------|------|
| `entry/src/main/ets/models/AssistantModels.ets:144,244` | kids_math 锁定工具 + 提示词 |
| `entry/src/main/ets/services/ToolExecutionService.ets:571,1894` | handleMathQuiz 镜像源 + dispatch 锚点 |
| `entry/src/main/ets/config/BuiltinTools.ets:1150,1239,1284,3020` | handleUpdate + child_profile schema + 工具描述 + 注册表 |
| `entry/src/main/ets/services/ChildProfileService.ets:6,36,143` | SkillDimension + SKILL_DEFINITIONS + parseProfile |
| `entry/src/main/ets/pages/LearningProfilePage.ets:33` | SKILL_GROUPS 分组 |
| `entry/src/main/ets/utils/LessonPlannerValidation.ets:36` / `LessonPlanPromptUtils.ets:67,135` / `LessonPlannerBaseline.ets:98` | 备课管线维度同步点 |
| `entry/src/main/ets/utils/MathQuizValidation.ets` / `MathQuizGame.ets:93` | 预校验范式 + 复算引擎复用源 |
| `entry/src/main/ets/components/verticalMath/` | 组件组织先例（Board + 纯函数 Layout + hypium） |
| `docs/math-teaching-suite.html` | 交互原型（8 板动效、composer、契约页） |
