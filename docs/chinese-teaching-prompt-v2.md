# 小星老师 · 语文教学工具与 Prompt 优化方案（v2）

面向 `chatcube`（ArkTS）项目。**目标**：把语文教学从「只会出拼音题 + 练字」升级为覆盖 **识字、正音、明义、观形、组词、表达** 的完整讲解闭环；让「教」这一步从 LLM 即兴口述变成有工具、有契约、可校验的互动卡片。

> 现状一句话：数学有 `vertical_math` 讲「怎么算」，英语有「五步课」讲「怎么学」，**语文没有任何讲解工具**——`pinyin_quiz` 直接考、`handwriting_practice` 只练字，孩子从头到尾被"测"，没有被"教"。

---

## 1. 问题诊断（现状 → 缺口）

| 现状（代码事实） | 缺口 |
|---|---|
| `kids_chinese` 只锁 `pinyin_quiz` + `handwriting_practice`（`AssistantModels.ets:154`） | 全科语文只有「测拼音 + 练字」两种动作，没有「讲汉字」的工具 |
| `pinyin_quiz` 是「看字选拼音」，直接考（`BuiltinTools.ets:2545`） | 汉语拼音是独立教学单元（声母/韵母/声调/拼读），只有测、没有教 |
| `handwriting_practice` 内嵌笔顺动画，但定位是「练 + 评分」（`HandwritingCard.ets:238`） | 笔顺的**讲解**（笔画名称、书写口诀、结构）被藏在练习里，孩子一上来就要写 |
| `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 语文相关只有【拼音】1 行 +【学写字】1 行 | 没有识字教学流程、没有字理（象形/会意）、没有形近字/同音字辨析、没有阅读与表达 |
| `picture_vocab(zh)`、`matching_pairs` 存在但**不属语文老师白名单** | 看图识字、字↔拼音配对没有被语文教学用起来 |
| `child_profile` 语文只有 `pinyin` 1 维 + `chinese_writing` + `fine_motor`（`ChildProfileService.ets:36`） | 没有「识字量 / 组词」「阅读表达」维度，识字与表达进步无处记录 |
| 备课计划有 `writing` 模块（`writing.<char>`），但只到「写哪个字」 | 没有「这个字怎么讲、组什么词、讲什么字理」的备课字段 |

---

## 2. 教学模型：六步识字法（对标部编版一年级）

> 认字 → 正音 → 明义 → 观形 → 组词 → 练写（先讲后练，讲完必练）

| 阶段 | 目标 | 工具 | 画像维度 |
|---|---|---|---|
| ① 认字 | 看清字形、认结构部首 | `hanzi_card`（认字区块） | `chinese_vocab` |
| ② 正音 | 读准声母韵母与声调 | `pinyin_card` | `pinyin` |
| ③ 明义 | 懂字义、听字源（象形/会意） | `hanzi_card`（字义/字源区块） | `chinese_vocab` |
| ④ 观形 | 数笔画、看逐笔笔顺 | `hanzi_card`（笔顺动画） | `chinese_writing` |
| ⑤ 组词 | 组词造句、会用 | `hanzi_card`（组词/例句）+ `chinese_quiz(mode:"word_build")` | `chinese_vocab` |
| ⑥ 练写 | 米字格跟写一个字 | `handwriting_practice(type:"chinese")` | `chinese_writing` / `fine_motor` |
| 延伸·辨析 | 形近字/同音字、近反义词 | `chinese_quiz(mode:"lookalike" / "antonym")` | `chinese_vocab` |
| 延伸·表达 | 看图说话、连词成句 | `picture_talk`、`chinese_quiz(mode:"sentence_order")` | `chinese_reading` |

**每节课编排**：1 个新字 + 1 个复习字；先讲（hanzi_card / pinyin_card）后练（handwriting_practice / chinese_quiz）；每步 1 题，全长 ≤ 12 分钟，中途穿插聊天与小故事。**硬规则：每讲完一个字必须给孩子练一次**，既不"只讲不练"，也不"只出题不讲"。

---

## 3. 工具契约（新增 3 个 + 1 个路由器）

### 3.1 `hanzi_card`（汉字小课堂）· 讲解型

一个字一张卡，分区块展示；笔顺动画复用 `config/StrokeOrderData.ets` 的 `getStrokeOrder()`（已有 90 个汉字数据）。

```
character      必填 单个汉字（须在 StrokeOrderData 内，保证有笔顺）
pinyin         必填 带调拼音（若在 PinyinData 内须与字典一致）
radical        必填 部首，如「山」
structure      必填 独体字 / 上下 / 左右 / 左中右 / 上中下 / 半包围 / 全包围
stroke_count   必填 笔画数（须与 StrokeOrderData 的笔顺条数一致）
meaning        必填 一句话字义（≤20 字，儿童可懂）
words          必填 2-3 个组词，每个都含该字
sentence       必填 一个例句，含该字，≤12 字
origin         可选 字理小故事（象形/会意/形声），≤30 字
lookalikes     可选 形近字/同音字对比 [{char, pinyin, note}]，最多 2 组
difficulty     必填 1-3
skill_key      必填 chinese_vocab
```

- UI：顶部米字格大字 + 拼音；中部「部首 / 结构 / 笔画」三枚标签；下半区依次为 字义 / 组词 / 例句 / 字源 / 形近字；底部两个动作：**「▶ 看笔顺」**（逐笔动画）与 **「跟着写一遍」**（起 `handwriting_practice(type:"chinese", character:同字)`）。
- 这是语文版的 `vertical_math`：`hanzi_card` 负责「教怎么认、怎么写」，`handwriting_practice` / `pinyin_quiz` 负责「测会不会」。

### 3.2 `pinyin_card`（拼音小课堂）· 讲解型

```
initial        必填 声母（可为空串表示零声母，如「安 ān」）
final          必填 韵母，如「an」
tone           必填 1-4 或 0（轻声）
syllable       必填 带调音节，如「shān」，须等于 initial+final+调号
examples       必填 四声示范 [{tone, syllable, char, word}]（1-4 声，至少 2 条）
mnemonic       必填 拼读/记忆口诀（≤24 字，如「b 像收音机，听广播 bbb」）
contrast       可选 易混对比 [{a, b, tip}]（b/p、n/l、平翘舌、前后鼻音）
difficulty     必填 1-3
skill_key      必填 pinyin
```

- UI：中部「声母 + 韵母 = 音节」拼合式；下方四声卡片（带调符号 + 例字 + 词）；再下口诀与易混对比；底部动作 **「去考一考」** 起 `pinyin_quiz`（同音节同调）。
- 定位：拼音教学单元（声母表 / 韵母表 / 四声 / 拼读）的讲解载体，补 `pinyin_quiz` 只有测的缺口。

### 3.3 `picture_talk`（看图说话）· 表达型

```
image_prompt   必填 单场景图像描述（英文），由 image_generation 出图
scene          必填 一句话场景说明（给孩子看，≤16 字）
questions      必填 1-3 个引导问题 [{q, options?}]（谁 / 在哪里 / 在做什么 / 怎么样）
words          必填 3-5 个可用词（给孩子提示）
sample         必填 示范完整句（≤15 字）
difficulty     必填 1-3
skill_key      必填 chinese_reading
```

- UI：上方 AI 生成图框（如实标注「AI 生成图」）；中部引导问题逐个出现，孩子**语音**作答（ASR）或从词卡点选；下方「完整说一句」示范；AI 依据表达给出 1 星 + 具体点评。
- 定位：口语交际与写话起步，训练观察 + 完整句表达。

### 3.4 `chinese_quiz`（语文小练习）· 题型路由器

沿用 `english_quiz v2` 的 mode 路线（`components/english/bodies/` 薄路由模式），**一个工具承载多种题型**，避免白名单膨胀：

```
mode = word_build | sentence_order | lookalike | antonym
```

| mode | 中文 | 关键参数 | 交互 | 对应能力 |
|---|---|---|---|---|
| `word_build` | 组词造句 | `character` · `target` · `options[4]` | 给字选能组的词 / 选正确搭配 | 识字组词 |
| `sentence_order` | 连词成句 | `words[2-6]`（打乱）· `answer` | 点词卡排序成通顺句 | 写话入门 |
| `lookalike` | 形近字辨析 | `stem`（含 `___`）· `options[4]`（单字）· `answer` | 选字填空 | 识字辨析 |
| `antonym` | 近反义词 | `character` · `options[4]` · `answer` | 找出相反的词 | 词汇积累 |

公共字段：`difficulty`(1-3) · `skill_key`（默认 `chinese_vocab`，`sentence_order` 为 `chinese_reading`）。

> 备选：也可把 `picture_talk` 做成 `chinese_quiz` 的一个 mode；但看图说话是开放式语音交互，与选择/排序差异过大，故独立成工具。

---

## 4. 出题预校验扩展（新增 `utils/ChineseQuizValidation.ets` + `HanziCardValidation.ets`）

沿用现有 `{error, should_retry:true}` 范式（参考 `PinyinQuizValidation.ets`）：

1. **hanzi_card**：`character` 是单字且 `hasStrokeOrder()` 为真；`stroke_count` 与笔顺条数一致；`words` 非空且每个含 `character`；`structure` 在枚举内；若 `pinyin` 命中 `PinyinData` 则须与字典读音一致。
2. **pinyin_card**：`syllable === initial + final + 调号`；`tone` 与 `examples[].tone` 自洽；`examples` 至少 2 条且各 `char` 单字。
3. **picture_talk**：`image_prompt` 非空且单场景；`questions` 1-3 个且各有 `q`；`words` 非空；`sample` 非空。
4. **chinese_quiz**：`options.length === 4` 且去重后仍为 4；`answer ∈ options`；`sentence_order` 的 `words` 2-6 个、`answer` 与打乱前一致；`lookalike` 的 `options` 均为单字、`stem` 恰含一个 `___`；`antonym` 的 `answer` 与 `character` 语义相反（无法程序判定的部分只做「非空 + 唯一」硬校验，语义交 LLM）。

---

## 5. Prompt 优化

### 5.1 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` —— 语文段

把现有【拼音】+【学写字】两行，扩成「语文（六步识字）」协议块（可直接粘贴进 `AssistantModels.ets`）。同时更新「工具调用规则」的工具清单。

```text
## 语文（六步识字）
你是孩子的语文启蒙老师。一个字按「认字→正音→明义→观形→组词→练写」教,先讲后练,讲完必须给孩子练一次:
① 认字+正音:hanzi_card 讲这个字(拼音/部首/结构/笔画/字义/字源),拼音单元另用 pinyin_card 教声母韵母声调;
② 明义+组词:hanzi_card 的组词与例句讲清字义,再用 chinese_quiz(mode:"word_build") 练组词;
③ 观形:hanzi_card 里点「看笔顺」看逐笔,再 handwriting_practice(type:"chinese") 跟着写同一个字;
④ 辨析:chinese_quiz(mode:"lookalike") 形近字/同音字,chinese_quiz(mode:"antonym") 近反义词;
⑤ 表达:picture_talk 看图说话,chinese_quiz(mode:"sentence_order") 连词成句;
⑥ 测:pinyin_quiz 认读音,handwriting_practice 练写。
每节课 1 个新字 + 1 个复习字,≤12 分钟;严禁只出题不讲解,也严禁只讲解不给孩子练。
【出题契约】chinese_quiz 的 mode 四选一:
- word_build:给一个字,4 个词里选出能跟它组词的(火→火车/火苗),干扰项不能成词;
- sentence_order:给 2-6 个打乱的词卡,孩子排成一句通顺的话,answer 是正确顺序;
- lookalike:句子留一个 ___,4 个形近字/同音字里选正确的填空,如 爬(山) 不选 出;
- antonym:给一个字,4 个词里选出意思相反的(大→小)。
难度按 child_profile:chinese_vocab 定识字与组词量,pinyin 定声调区分度(level 0-1→声母韵母差异明显,4-5→仅声调不同)。
【字理纪律】讲象形/会意/形声字时用一句话小故事(如「山」像三座山峰并立),不要长篇;每节课保留 1-2 个核心字反复复现。
```

配套：`DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` 增加 `HANZI_CARD` / `PINYIN_CARD` / `PICTURE_TALK` / `CHINESE_QUIZ`；【工具白名单】共享片段同步列出。

### 5.2 `KIDS_CHINESE_SYSTEM_PROMPT` —— 整段替换

```text
## 语文教学策略
- 聚焦 4 个维度:pinyin / chinese_writing / chinese_vocab / chinese_reading。
- 一节课按「认字→正音→明义→观形→组词→练写」推进:
  ① 认字:hanzi_card 讲字形、部首、结构;② 正音:pinyin_card 教声母韵母声调(或 pinyin_quiz 测);
  ③ 明义:hanzi_card 的字义与字源;④ 观形:hanzi_card 看笔顺,handwriting_practice(type:"chinese") 跟写;
  ⑤ 组词:chinese_quiz(mode:"word_build");⑥ 表达:picture_talk 看图说话 或 chinese_quiz(mode:"sentence_order")。
- 每节课 1 个新字 + 1 个复习字,≤12 分钟,每步 1 题,先讲后练。
- 难度按 child_profile:chinese_vocab 定识字量,pinyin 定声调区分度,chinese_reading 定看图说话的句长。
- 纠错:先肯定,再示范正确读音/字形一次,给一次再试机会,不连续纠错超过 2 次。
- child_profile(action: "update") 只更新 pinyin / chinese_writing / chinese_vocab / chinese_reading / fine_motor 维度,notes 必须基于本轮具体表现。
```

`KIDS_CHINESE_LOCKED_TOOL_IDS` 增加 4 个新工具。

### 5.3 共享片段（`SharedPromptFragments.ets`）

- 【工具白名单】补 `hanzi_card / pinyin_card / picture_talk / chinese_quiz`。
- 【child_profile 行为规则】「23 维」更正为「26 维」（本就与 24 维现状不符，顺带修正）。

---

## 6. child_profile 扩展（24 → 26 维）

| 新增 key | label | 分组 | 含义 |
|---|---|---|---|
| `chinese_vocab` | 识字组词 | 语文 | 认字量、部首结构辨识、组词能力 |
| `chinese_reading` | 阅读表达 | 语文 | 看图说话、连词成句、句子理解 |

**触点（必须同步，参照 teaching-architecture §11.5「naked 风险」）**：

1. `services/ChildProfileService.ets` — `SKILL_DEFINITIONS` 追加 2 条。
2. `config/BuiltinTools.ets` — `child_profile` schema 的 `skill_key` 枚举（约 1247 行）+ 顶层工具描述 Available skill keys（约 1284 行）。
3. `utils/SkillLabelUtils.ets` — `inferSkillGroup` 增加 `chinese_` 前缀归「语文」。
4. `pages/LearningProfilePage.ets` — `SKILL_GROUPS` 的 `chinese` 组 `keys` 追加 2 个。
5. 5 份系统提示词的维度子集（`DEFAULT` / `KIDS_CHINESE` 至少）。
6. 若采纳备课扩展（§7），`LessonPlan` 相关渲染也引用新维度。

---

## 7. 备课计划扩展（P1，可选）

现有 `writing` 模块只到 `characterOrWord`。建议给 `LessonPlanWritingItem` 增加可选字段，让备课老师直接产出「明天讲哪个字、组什么词、讲什么字理」，小星老师次日照单讲解：

```
pinyin?: string           // 该字拼音
words?: string[]          // 预置组词
teachingTip?: string      // 字理/讲解提示（≤30 字）
```

同步：`models/LessonPlanModels.ets`（字段 + hydrate）、`utils/LessonPlanPromptUtils.ets`（`PLANNER_SYSTEM_PROMPT` 输出示例 + `formatWritingLine`）、`LessonPlannerValidation`（校验组词含该字）。`topicKey` 沿用 `writing.<char>`，无需新模块。

---

## 8. 落地清单（代码侧触点）

| 文件 | 改动 |
|---|---|
| `utils/SearchToolIdentityUtils.ets` | 新增 `HANZI_CARD_TOOL_ID` / `PINYIN_CARD_TOOL_ID` / `PICTURE_TALK_TOOL_ID` / `CHINESE_QUIZ_TOOL_ID` 常量 |
| `config/BuiltinTools.ets` | 4 个新工具 schema + executor + register；`child_profile` 枚举 2 处；工具注册数组 |
| `services/ToolExecutionService.ets` | 4 个 `handleXxx` 特殊路径（挂起 → onAnswer → 授星） |
| `models/StarEventModels.ets` | 新增 4 个 activityType（**10 处漂移点**，见 `adding-mini-game-tool` 技能） |
| `services/StarRewardService.ets` | `computeStars` 分支（讲解卡首次完成 1 星；quiz 答对 1 星） |
| `models/AssistantModels.ets` | default 白名单 + 语文段；`KIDS_CHINESE_LOCKED_TOOL_IDS` + 语文段；import |
| `utils/SharedPromptFragments.ets` | 工具白名单 + 24→26 维措辞 |
| `services/ChildProfileService.ets` | 2 个新维度 |
| `utils/SkillLabelUtils.ets` + `pages/LearningProfilePage.ets` | 语文分组 |
| `components/HanziCard.ets` / `PinyinCard.ets` / `PictureTalkCard.ets` / `ChineseQuizCard.ets`（+ `components/chinese/bodies/`） | 新卡片（复用 `CardShell` + `StrokeOrderData` 笔顺动画） |
| `components/MessageBubble.ets` | 7 处挂载（内联 + or 链 + 助手 + 点击 + 步骤切换 + 步骤内容） |
| `components/kids/KidsSubjectCatalog.ets` | `chinese.activityTypes` 补 4 个新类型 |
| `utils/KidsSubjectUtils.ets` | 无需改（按 activityTypes 通用计数） |
| `utils/*Validation.ets` | 新增 `HanziCardValidation` / `ChineseQuizValidation` |
| `docs/superpowers/specs/` | 本方案对应 spec |

---

## 9. 验收

1. **讲解可触达**：对小星老师说「教我一个汉字」，应调 `hanzi_card` 并展示字义/组词/笔顺，而不是直接 `pinyin_quiz` 出题。
2. **先讲后练**：一次完整识字流程里，`hanzi_card`（或 `pinyin_card`）出现在 `handwriting_practice` / `chinese_quiz` 之前。
3. **笔顺数据命中**：`hanzi_card` 的 `character` 在 `StrokeOrderData` 内，卡片能播放逐笔动画；字典外字符被预校验拒绝并 `should_retry`。
4. **维度可读写**：`child_profile(read)` 返回含 `chinese_vocab` / `chinese_reading`；完成一次识字课后能 `update` 对应维度。
5. **表达有反馈**：`picture_talk` 语音作答后返回 1 星与具体点评；`chinese_quiz(sentence_order)` 排序正确后判对。
6. **不回归**：`pinyin_quiz` / `handwriting_practice` 行为与授星不变；英语/数学助手不受影响。

---

## 10. 风险与不纳入本轮

- **新增 4 个工具 = 白名单从 19 → 23**：语文助手白名单从 6 → 10，选择面变大。用 `pinyin_card`（讲）vs `pinyin_quiz`（测）、`hanzi_card`（讲）vs `handwriting_practice`（练）的**讲解/练习二分**在 prompt 里显式约束，降低误选。
- **`chinese_quiz` 四 mode 的语义校验（反义词/组词是否成立）无法完全程序化**：硬校验只保证「4 选 1、答案在选项、结构合法」，语义正确性靠 prompt 契约 + LLM 自检；后续可加反义词词表。
- **笔画名称依赖 `StrokeOrderData` 的 label**（竖/折/撇/捺…）：已足够展示，但若要「横折钩」级别的规范笔画名，需扩充数据。
- **不纳入本轮**：古诗/儿歌诵读、成语、段落阅读（`chinese_reading` 目前由看图说话/连词成句承载）——留作下一批，避免一次摊太薄。
