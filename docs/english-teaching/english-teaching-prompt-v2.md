# 小星老师 · 英语教学工具与 Prompt 优化方案（v2）

面向 `chatcube`（ArkTS）项目。**目标**：把英语教学从「看图认单词」单一模式，升级为覆盖听、说、读、写、拼读的小学英语五步教学闭环；并让「出英语题」这一步从 LLM 即兴发挥变成有契约、可校验、可复用的出题器。

---

## 1. 问题诊断（现状 → 缺口）

| 现状（代码事实） | 缺口 |
|---|---|
| `english_quiz` 的 `question_type` 只有 `word` / `sentence` / `phonics_choice` | 缺「听音选词、拼读拼词、句型操练、跟读评测」；`word` 仍是看图认词 |
| `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 英语段仅 3 行，只讲「用哪个工具」 | 没有教学流程、没有难度阶梯、没有纠错话术、没有主题词库约束 |
| 各工具彼此孤立（`picture_vocab` / `listening_quiz` / `english_quiz`） | 没有「一节课怎么串起来」的主线，孩子体验是零散卡片 |
| 预校验只查「答案在选项内 / 图片 prompt 非空」 | 查不出「干扰项不同类」「phonics 规则不成立」「句型空格数不对」等教学性坏题 |
| 画像 4 维（alphabet/vocab/sentence/phonics）只用来看难度 | 没有把维度映射到具体题型与教学阶段 |

---

## 2. 教学模型：五步英语课（小学 PEP 思路）

> Warm-up 热身 → Presentation 呈现 → Practice 操练 → Production 输出 → Review 复习

| 阶段 | 目标 | 推荐工具（mode） | 画像维度 |
|---|---|---|---|
| ① 热身 Warm-up | 唤醒旧词，开口 | `english_quiz.mode=listen_choice`（听音选词） | english_alphabet / phonics |
| ② 呈现 Presentation | 新词首次输入：音—形—义 | `picture_vocab.mode=en` + `image_generation`；`english_quiz.mode=read_aloud` 跟读 | english_vocab |
| ③ 操练 Practice | 高频重复、辨音辨形 | `english_quiz.mode=phonics_blend`（拼读拼词）、`listening_quiz` | english_phonics |
| ④ 输出 Production | 词不离句、真实表达 | `english_quiz.mode=sentence_fill`（句型操练）、`mode=read_aloud` | english_sentence |
| ⑤ 复习 Review | 归因、巩固、留钩子 | `matching_pairs`（词—图/词—义）、`handwriting_practice(type=letter)` | english_writing |

**每节课编排建议**：①1 题 → ②2 词 → ③2 题 → ④1 句 → ⑤1 组配对。全长 ≤ 15 分钟，中途穿插聊天与故事，不连续超过 10 题。

---

## 3. 出题工具契约（english_quiz v2）

把 `question_type` 升级为 `mode`，六选一；**不新增工具**，避免工具白名单膨胀与选择困难。

```
mode = listen_choice | picture_word | phonics_blend | sentence_fill | read_aloud | letter_trace
stage = warm_up | presentation | practice | production | review
theme = 颜色/动物/食物/家庭/数字/身体/学校/天气...   （约束词表范围）
```

| mode | 输入（关键字段） | 交互 | 必填校验 |
|---|---|---|---|
| `listen_choice` | `word`、`options[4]`、`tts_text` | 朗读，4 选 1 | `tts_text` 可发音；干扰项同韵/同音节 |
| `picture_word` | `image_prompt`、`options[4]` | 看图，4 选 1 | 图只含单一可辨认主体 |
| `phonics_blend` | `word`、`phonics_rule`(如 `short a`)、`options[4]` | 听音拼词 / 选同规则词 | 单词必须完全符合所声明 `phonics_rule` |
| `sentence_fill` | `pattern`(如 `I like ___.`)、`answer`、`options[4]` | 选词补全句子 | 恰好 1 个空；答案词性与句型匹配 |
| `read_aloud` | `target_text`、`phonetic_hint` | 麦克风跟读 + 评分 | 目标文本 ≤ 8 词；不超当前 sentence 等级 |
| `letter_trace` | `letter`、`case`(`upper`/`lower`) | 笔顺描红 | 单字母；联动 `handwriting_practice` |

**新增可选字段**：`stage`、`theme`、`phonics_rule`、`pattern`、`tts_text`、`case`。旧调用（`question_type`）保留兼容映射，避免历史会话渲染失败。

---

## 4. 出题预校验扩展（`EnglishQuizValidation.ets`）

在现有规则之上追加（失败仍返回 `{error, should_retry:true}`，让 LLM 自我修正）：

1. **选项数量与唯一性**：`options.length === 4`，去重后仍为 4（现有代码只查「含答案、≥2 个合法项」）。
2. **干扰项同质**：`picture_word`/`listen_choice` 的 4 个词必须同 `theme`；跨类（apple / bus / red）判坏题。
3. **phonics 一致性**：`phonics_blend` 必须给 `phonics_rule`，且 `word` 的元音—辅音结构匹配该规则；干扰项属同一音族（`cat/cap/can`，不混 `car` 的 r-controlled）。
4. **句型空格**：`sentence_fill` 的 `pattern` 恰含一个 `___`，且 `answer` 出现在 `options`、词性与 `pattern` 匹配。
5. **跟读文本长度**：`read_aloud` 的 `target_text` 词数 ≤ 当前 `english_sentence` 等级对应上限（level 0-1→3 词，2-3→5 词，4-5→8 词）。
6. **难度—维度一致**：`difficulty` 与 `child_profile[skill_key]` 偏差 >1 时提示重估（只警告不拦）。

---

## 5. Prompt 优化：替换英语段（可直接粘贴进 `AssistantModels.ets`）

> 现有英语段只有 3 行，且与「看图识词」「听力」段重复。建议用下面这段**结构化英语教学协议**替换，并把「看图识词/听力」两段合并进来，整体行数持平（约 +6 行），token 不显著增加。

```text
## 英语（五步课）
你是孩子的英语启蒙老师。一节课按「热身→呈现→操练→输出→复习」推进,用以下工具落地:
① 热身:english_quiz(mode:"listen_choice") 听音选词,先复习旧词;
② 呈现:先调 image_generation 生成清晰单物图,picture_vocab(mode:"en") 看图选词,再用 english_quiz(mode:"read_aloud") 让孩子跟读;
③ 操练:english_quiz(mode:"phonics_blend") 拼读拼词(必须给 phonics_rule),listening_quiz 辨音;
④ 输出:english_quiz(mode:"sentence_fill") 句型操练(词不离句),再 read_aloud 说整句;
⑤ 复习:matching_pairs 词—图配对,handwriting_practice(type:"letter") 描字母。
每节课 ≤15 分钟,每步 1-2 题,不连续超过 10 题,中间穿插聊天和小故事。

【出题契约】english_quiz 的 mode 六选一:
- listen_choice:给孩子听一个词,4 个选项选听到的;tts_text 必须是 TTS 可读英文,干扰项同韵( cat/cap/can )。
- picture_word:看图选英文单词,必须给 image_prompt(单主体),4 个选项同主题类(都水果或都动物)。
- phonics_blend:给 phonics_rule(如 "short a"),4 个选项都符合该规则( cat/ham/map/bat );不要把不同规则的词混进来。
- sentence_fill:pattern 里恰好一个 ___,孩子从 4 个词选填( I like ___. → apples );答案词性必须贴句型。
- read_aloud:给孩子一句 ≤8 词的目标句,让他对着麦克风说,卡片自动评分;phonetic_hint 给易错音提示(如 th → "this")。
- letter_trace:写一个字母,case 选 upper/lower,和 handwriting_practice(type:"letter") 联动。
难度按 child_profile:english_alphabet/phonics 定节奏,english_vocab 定词量,english_sentence 定句长(level 0-1→3 词,2-3→5 词,4-5→8 词)。

【纠错话术】孩子答错:先复述他说的、肯定努力,再示范正确音一次,然后给一次再试机会,不连续纠错超过 2 次;答对用 1 句具体表扬(说出他哪里对了),不要只说「真棒」。

【主题纪律】同一节课的词必须同一 theme(颜色/动物/食物/家庭/数字/身体/学校/天气),不要跨主题乱出;每节课保留 2-3 个核心词反复复现。
```

配套修改：
- `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 中「【英语】4 维」「【看图识词】」「【听力】」三段合并为上面一段。
- 「工具调用规则」里把 `english_quiz` 的 mode 说明补进列表。

---

## 6. 落地清单（代码侧）

| 文件 | 改动 |
|---|---|
| `utils/EnglishQuizValidation.ets` | 增加选项数/唯一性、干扰项同质、phonics 规则、句型空格、跟读长度 5 条规则 |
| `config/BuiltinTools.ets` | `english_quiz` schema 增加 `mode/stage/theme/phonics_rule/pattern/tts_text/case`；`question_type` 保留兼容 |
| `models/AssistantModels.ets` | 用 §5 文本替换英语/看图识词/听力三段 |
| `components/EnglishQuizCard.ets` | 按 `mode` 渲染六种卡片形态（沿用现有卡片外壳与授星逻辑） |
| `services/ChildProfileService.ets` | 可增加 `english_reading` 维度承载跟读评分（可选） |
| `docs/superpowers/specs/` | 新增本方案对应 spec，替换零散英语工具记录 |
