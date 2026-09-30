# 小星老师 · 数学教学工具与 Prompt 优化方案（v2）

面向 `chatcube`（ArkTS）项目。**目标**：把数学教学从「出题—判对错」单一模式，升级为「讲道理—动手摆—再练习—会表达」的小学低段五步教学闭环；并让「怎么讲」这一步从 LLM 即兴发挥变成有契约、可校验、可复用的讲解演示器。

---

## 1. 问题诊断（现状 → 缺口）

| 现状（代码事实） | 缺口 |
|---|---|
| `KIDS_MATH_SYSTEM_PROMPT` 的「## 数学教学策略」6 条里，4 条在讲怎么出题 | 没有教学流程，没有「先讲后练」的强制顺序，孩子容易只刷题 |
| 讲解工具只有 `vertical_math`（竖式） | 数与代数（凑十、数位、数轴）、图形、比较、时间的算理**没有演示载体**，「教怎么算」几乎只能出题 |
| `math_quiz.type` 只有 `arithmetic / shape / comparison / time / elapsed_time` | 全是「测会不会」，没有「教会不会」；应用题（`word_problem`）只渲染文字，没有图解 |
| `MathQuizValidation.ets` 只校验答案/选项等**结果性**规则 | 查不出「演示与算理不符」「超龄难度」「讲解后没有紧跟练习」等**教学性**坏课 |
| 画像 8 维（counting/addition/subtraction/multiply/divide/shapes/comparison/time）只承载难度 | 缺「数感」「解决问题」两维；也没记录孩子**用什么方法**（凑十/数数/掰手指）与**常错点** |
| 一次只出 1 题、题型轮换 | 有节奏但无结构，一节课与一节课之间没有「热身—讲解—操练—输出—复习」的主线 |

---

## 2. 教学模型：五步数学课（小学低段思路）

> Warm-up 热身 → Presentation 讲解 → Practice 操练 → Production 输出 → Review 复习

| 阶段 | 目标 | 推荐工具（mode） | 画像维度 |
|---|---|---|---|
| ① 热身 Warm-up | 口算接龙，唤醒旧知 | `math_quiz(type=arithmetic)` | math_counting / math_addition |
| ② 讲解 Presentation | 动手摆一摆，讲清算理 | `math_teach(mode=...)` 讲解演示板 | math_number_sense / 对应运算维 |
| ③ 操练 Practice | 模仿练习，形成技能 | `math_quiz` + `vertical_math` | math_addition / math_subtraction |
| ④ 输出 Production | 让孩子讲题、自己出题 | `ask_user` 讲题 + `math_verify` 验算 | math_word_problem |
| ⑤ 复习 Review | 归因巩固，留个钩子 | `matching_pairs`（算式配对）+ `number_puzzle` | 各运算维 |

**每节课编排建议**：①2-3 题 → ②1-2 块讲解板 → ③2 题 → ④1 次讲题 → ⑤1 组配对。全长 ≤ 15 分钟，每步 1-2 题，**不连续超过 10 题**，中间穿插聊天和小故事。

**硬约束（新增）**：一节课里讲解（`math_teach` 或 `vertical_math`）必须先于同类巩固题发生；不让孩子在看过算理前刷同型题。

---

## 3. 讲解工具契约（math_teach v2）

新增 **1 个**讲解工具（不是 8 个），按 `mode` 渲染对应讲解板；**旧调用不受影响**，遵循英语方案「避免工具白名单膨胀与选择困难」的同一原则。

```
mode = number_bond | number_line | ten_frame | place_value | balance | shape | clock | bar_model
stage = warm_up | presentation | practice | production | review
skill_key = math_number_sense | math_addition | math_counting | math_comparison | math_shapes | math_time | math_word_problem
```

| mode | 输入（关键字段） | 演示算什么理 | 必填校验 |
|---|---|---|---|
| `number_bond` | `total`、`left_part`、`right_part` | 数的分与合（为凑十打底） | `left_part + right_part === total`；`total ≤ 20` |
| `number_line` | `a`、`b`、`cost` | 数轴上向右跳、向左跳 | `a + b ≤ 20`；`cost = 10 - a`（凑十步长一致） |
| `ten_frame` | `a`、`b` | 十格阵凑十 | `a + b ≤ 20`；`a` 或 `b` 属于 8-9，才配「凑十」话术 |
| `place_value` | `ones`、`tens` | 小棒捆扎、十位与个位 | `0 ≤ ones ≤ 9`、`0 ≤ tens ≤ 9`；`ones=10` 必须进位 |
| `balance` | `left`、`right` | 天平比大小 | 两数均 ≥ 1；比较符号由数值自动推导，不接受 LLM 手填方向 |
| `shape` | `focus` | 图形边与角 | `focus ∈ circle/square/triangle/rectangle`；图形的边角数由定义表给出 |
| `clock` | `hour`、`minute` | 认读整点与半点 | `hour ∈ 1-12`、`minute ∈ {0,30}`；指针角度由数值推导 |
| `bar_model` | `part_a`、`part_b` | 长条图解「一共 / 还剩」 | 两部分均为正；`part_a + part_b` 与渲染全长一致 |

**新增可选字段**：`stage`、`skill_key`、`concept`。`math_teach` 与 `math_quiz` 的 `type` 字段**不共用**——讲解走 `mode`，出题继续走 `type`，避免历史卡片渲染冲突。

---

## 4. 校验扩展（`MathQuizValidation.ets` + math_teach 预校验）

在现有规则之上追加（失败仍返回 `{error, should_retry:true}`，让 LLM 自我修正）：

1. **mode 白名单**：`math_teach.mode` 八选一，越界即拒绝。
2. **凑十一致性**：`ten_frame` / `number_line` 的 `a + b ≤ 20` 且可由「先凑十」推出（`a` 或 `b` ∈ 8-9）；不允许声明凑十却给出无法凑十的算式。
3. **概念—模式匹配**：`number_bond` 必须给 `total`，`bar_model` 必须给 `part_a`/`part_b`；缺参数判坏课。
4. **数位进位**：`place_value` 的 `ones` 达到 10 必须进位成 `tens`，不接受「13 = 0 个十 13 个一」这类不成立摆法。
5. **比较方向自洽**：`balance` / `comparison` 的比较符号必须与左右数值一致（沿用现有 comparison 规则，但由引擎推导而非模型填报）。
6. **难度—维度一致**：`difficulty` 与 `child_profile[skill_key]` 偏差 >1 时提示重估（只警告不拦）。
7. **演示后必练**：一节课的**最后一块**讲解板之后若没有任何 `math_quiz`/`vertical_math` 巩固题，判为未完成一课（提醒补 1-2 题）。

---

## 5. Prompt 优化：替换数学段（可直接粘贴进 `AssistantModels.ets`）

> 现有 `KIDS_MATH_SYSTEM_PROMPT` 的「## 数学教学策略」为 6 条、约 8 行，其中 4 条在讲出题。用下面这段**结构化数学教学协议**替换（整体行数 +3 左右，token 不显著增加），并把「先讲后练、讲解工具钩子、难度纪律」写死。

```text
## 数学教学策略（五步课）
你是孩子的数学启蒙老师。一节课按「热身→讲解→操练→输出→复习」推进,用以下工具落地:
① 热身:math_quiz(type:"arithmetic") 口算接龙,先复习旧知;
② 讲解:先动手摆一摆再讲算理——用 math_teach(mode) 渲染讲解演示板(number_bond 数的分与合 / number_line 数轴跳一跳 / ten_frame 十格阵凑十 / place_value 小棒与数位 / balance 天平比大小 / shape 图形拼摆 / clock 时钟拨一拨 / bar_model 应用题图解),竖式加减乘除仍用 vertical_math;
③ 操练:math_quiz / vertical_math 模仿巩固,由易到难,一次 1 题,答对升一点、连错 2 次降难度并鼓励;
④ 输出:用 ask_user 让孩子用自己的话讲题,或让孩子出一道题,再用 math_verify 验算;
⑤ 复习:matching_pairs 算式—结果配对 + number_puzzle,留一道明天要用的钩子题。
每节课 ≤15 分钟,每步 1-2 题,不连续超过 10 题,中间穿插聊天和小故事。
【讲解优先】一节课里讲解必须先于同类巩固题发生;不让孩子在看过算理前刷同型题。

【讲解契约】math_teach 的 mode 八选一,按 mode 渲染对应讲解板:
- number_bond:给 total/left_part/right_part,把数拆成两部分(为凑十打底)。
- number_line:给 a/b/cost,在数轴上先跳到 10 再跳余数(cost = 10 - a)。
- ten_frame:给 a/b,放进十格阵先凑满 10 再看外面剩几;仅当 a 或 b 是 8-9 才叫「凑十」。
- place_value:给 ones/tens,十根捆一捆,理解十位与个位;个位满 10 必须进位。
- balance:给 left/right,天平哪边沉哪边数大;比较符号由引擎推导,不要手填方向。
- shape:给 focus,数一数图形的边和角。
- clock:给 hour/minute,认读整点与半点(0/30 分步骤)。
- bar_model:给 part_a/part_b,用长条图把「一共 / 还剩」画出来。

【出题契约】math_quiz 的 type 五选一:arithmetic / shape / comparison / time / elapsed_time(应用题不是独立 type,而是在 arithmetic 上设 word_problem:true,只用 question 讲场景、expression 留空);comparison 的 correct_answer 必须是「使 left_value ○ right_value 成立的符号」,不要按「哪个更大」选。
【难度纪律】按 child_profile 各维度 level 定节奏;math_number_sense 定数感与数的组成,math_word_problem 定应用题难度;一次只出/讲一个知识点。
【纠错话术】孩子答错:先复述他的想法、肯定努力,再示范正确的算理一次,然后给一次再试机会,不连续纠错超过 2 次;答对用 1 句具体表扬(说出他哪里对了),不要只说「真棒」。
【画像纪律】child_profile(action: "update") 只更新 math_ 开头的技能维度,并记录本轮用的方法和常错点(见 notes/strategy),notes 必须基于本轮具体表现。
```

配套修改：
- `KIDS_MATH_SYSTEM_PROMPT` 中「## 数学教学策略」整段替换为上面内容。
- 「工具调用规则」里把 `math_teach` 加进数学工具白名单，并注明「讲解用 math_teach，出题用 math_quiz，不要互相替代」。

---

## 6. 画像扩展（`ChildProfileService.ets`）

新增 **2 个维度**（`SKILL_DEFINITIONS`），并为每个维度记录「方法」与「常错点」：

| 项 | 改动 |
|---|---|
| `math_number_sense` | 新增维度：数感与数的组成、分与合（位于 `math_counting` 之后） |
| `math_word_problem` | 新增维度：解决问题 / 应用题（位于 `math_time` 之后） |
| `SkillDimension.strategy` | 新增字段（`string`）：记录孩子用的方法（凑十 / 数数 / 掰手指 / 直接记答案） |
| `SkillDimension.misconceptions` | 新增字段（`string[]`）：记录常错点（忘记进位 / 数轴方向反了 / 比较符号选反） |

- `SkillDimension` 构造函数保持 `(key, label)` 兼容，新字段给默认值，旧画像反序列化不受影响。
- `child_profile(action:"update")` 时，`strategy` / `misconceptions` 由模型依据本轮具体表现填写，`notes` 保持一句话总结。

---

## 7. 落地清单（代码侧）

| 文件 | 改动 |
|---|---|
| `config/BuiltinTools.ets` | 新增 `math_teach` 工具 schema：`mode`(八选一必填) + `stage`/`skill_key`/`concept` + 各 mode 专属参数；`math_quiz` 不变 |
| `utils/MathQuizValidation.ets` | 增加 mode 白名单、凑十一致性、概念—模式匹配、数位进位、比较方向自洽、难度—维度一致、演示后必练 7 条规则 |
| `models/AssistantModels.ets` | 用 §5 文本替换 `KIDS_MATH_SYSTEM_PROMPT` 的「## 数学教学策略」段；工具白名单补 `math_teach` |
| `components/MathTeachCard.ets`（新增） | 按 `mode` 渲染 8 种讲解板形态（交互沿用现有卡片外壳与授星逻辑） |
| `services/ChildProfileService.ets` | 增加 `math_number_sense` / `math_word_problem` 两维；`SkillDimension` 增加 `strategy` / `misconceptions` |
| `docs/` | 本方案 + 配套原型 `math-teaching-suite.html`，替换零散数学工具记录 |

---

## 8. 验收标准

- [ ] 一节课里讲解（`math_teach` 或 `vertical_math`）出现在同类巩固题之前。
- [ ] 8 种 `mode` 都能在卡片内渲染并可动手操作，且算理与演示一致。
- [ ] 坏课能被预校验拦下：无法凑十的「凑十」、个位 13 的摆法、比较符号选反、讲完不练。
- [ ] 新画像维度可被更新与读取，旧画像数据不丢字段。
