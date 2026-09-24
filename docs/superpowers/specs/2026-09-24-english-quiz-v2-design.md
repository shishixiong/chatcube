# english_quiz v2 · 五步英语教学闭环设计 spec

**日期：** 2026-09-24
**状态：** 待实施
**来源文档：** `docs/english-teaching/english-teaching-prompt-v2.md`（优化方案）、`docs/english-teaching/brand-spec.md`（视觉令牌）
**范围：** `english_quiz` 工具契约升级（3 题型 → 6 mode）、预校验扩展、卡片重组为 mode 子组件、默认助手 + kids_english 提示词改写、新增 `english_reading` 画像维度
**前置架构文档：** `.claude/rules/teaching-architecture.md`（§4 教学工具生态 / §5 教学数据模型）

---

## 1. 背景与目标

现状（代码事实）：

- `english_quiz` 的 `question_type` 只有 `word` / `sentence` / `phonics_choice`，`word` 仍是"看图自由作答"单一模式
- `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 的英语段仅 3 行（`AssistantModels.ets:53`），只讲用哪个工具；【看图识词】【听力】两段（行 54-55）与 english_quiz 部分能力重复
- 三个英语工具（`english_quiz` / `picture_vocab` / `listening_quiz`）彼此孤立，没有"一节课怎么串"的主线
- 预校验（`EnglishQuizValidation.ets`，102 行）只查"答案在选项内 / image_prompt 非空"，查不出选项数量不足、phonics 规则不成立、句型空格数不对等教学性坏题
- 画像英语 4 维（alphabet/vocab/sentence/phonics）只用于选难度，没有映射到题型

**目标**：把英语教学升级为覆盖听、说、读、写、拼读的小学五步教学闭环（Warm-up → Presentation → Practice → Production → Review）；出题从 LLM 即兴发挥变成有契约、可校验、可复用的出题器。**不新增工具**，避免白名单膨胀与选择困难。

## 2. 非目标

- 不做发音置信度评测（口语评分 = ASR 转写文本归一化匹配，非真实发音打分）
- 不做 stage 状态机 / 连续多题编排自动追踪——`stage` 只入协议，由提示词约束 LLM 自行推进
- 不新增工具、不改 `picture_vocab` / `listening_quiz`（它们继续存在，五步课复习/呈现环节使用）
- 不改 `StarEventModels.ets`（`english_quiz` 活动类型已存在，零联合漂移）
- 干扰项同主题、答案词性匹配等**语义级**规则不入代码校验（代码无法判定），靠提示词纪律 + 工具 description 负例

## 3. 教学模型（五步英语课）

| 阶段 | stage 值 | 推荐工具（mode） | 画像维度 |
|---|---|---|---|
| ① 热身 Warm-up | `warm_up` | `english_quiz(mode=listen_choice)` | english_alphabet / phonics |
| ② 呈现 Presentation | `presentation` | `picture_vocab(mode=en)` + `english_quiz(mode=read_aloud)` | english_vocab |
| ③ 操练 Practice | `practice` | `english_quiz(mode=phonics_blend)`、`listening_quiz` | english_phonics |
| ④ 输出 Production | `production` | `english_quiz(mode=sentence_fill)`、`read_aloud` | english_sentence |
| ⑤ 复习 Review | `review` | `matching_pairs`（词—图）、`handwriting_practice(type=letter)` | english_writing |

每节课 ≤ 15 分钟，每步 1-2 题，不连续超过 10 题，中间穿插聊天和小故事。同一节课词汇必须同一 theme。

## 4. 工具契约（`config/BuiltinTools.ets` · english_quiz schema v2）

### 4.1 字段

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `mode` | enum 6 选一：`listen_choice` \| `picture_word` \| `phonics_blend` \| `sentence_fill` \| `read_aloud` \| `letter_trace` | ✓（schema required） | 新契约主键 |
| `question` | string | ✓ | 给孩子看的中文指令（如"听一听，选出你听到的单词"） |
| `correct_answer` | string | ✓ | 正确答案（各 mode 语义见 §5） |
| `difficulty` | number 1-5 | 可选 | 沿用现有语义 |
| `skill_key` | string | 可选 | 各 mode 默认映射见 §8.2 |
| `stage` | enum 5：`warm_up`/`presentation`/`practice`/`production`/`review` | 可选 | 五步课阶段标记，仅入协议 |
| `theme` | string | 可选 | 主题词表范围（颜色/动物/食物/家庭/数字/身体/学校/天气） |
| `options` | string[4] | 4 个 choice/fill mode 必填（校验层管） | 恰好 4 个选项，含 `correct_answer` |
| `image_prompt` | string | `picture_word` 必填（校验层管） | **从 schema required 中移除**（6 mode 中 5 个不需要图） |
| `phonics_rule` | string | `phonics_blend` 必填 | 如 `"short a"` |
| `pattern` | string | `sentence_fill` 必填 | 如 `"I like ___."`，恰含一个 `___` |
| `tts_text` | string | `listen_choice` 必填 | TTS 朗读的英文词 |
| `target_text` | string | `read_aloud` 必填 | 跟读目标句，≤ 8 词 |
| `phonetic_hint` | string | 可选 | 易错音提示（如 th → "this"） |
| `letter` | string | `letter_trace` 必填 | 单字母 a-zA-Z |
| `case` | enum：`upper` \| `lower` | `letter_trace` 必填 | 大小写 |
| `question_type` | enum：`word`/`sentence`/`phonics_choice` | 保留，description 标 deprecated | 历史会话渲染兼容；新调用不要发 |
| `letter_options` / `sound_text` | 保留 | 否 | 仅 legacy `phonics_choice` 用 |

### 4.2 schema required 变更

```
旧: required = ["correct_answer", "question_type", "image_prompt", "question"]
新: required = ["question", "mode", "correct_answer"]
```

`image_prompt` 退出 required（5/6 mode 无图）；`question_type` 退出 required（legacy 兼容路径由校验层兜底：`mode` 缺失时按 `question_type` 走 legacy 校验规则，两者都缺 → 校验失败）。

### 4.3 工具 description 重写

替换现有"看图说话"单一定位，改为：六 mode 何时用哪个 + 授星说明 + **⚠️ 严禁负例**（按 memory `tool-call-forgetting` 教训：驱动可见 UI 的参数必须给负例）：

- 严禁把不同 phonics 规则的词混进 `phonics_blend` 选项（cat/cap/can ✓，混入 car ✗）
- 严禁 `sentence_fill` 的 pattern 出现 0 个或多个 `___`
- 严禁 4 个选项跨主题（apple/bus/red ✗）
- `listen_choice`/`picture_word` 选项必须 4 个且互不相同

### 4.4 mode × 必填字段矩阵

| mode | 必填 | 交互 | correct_answer 语义 |
|---|---|---|---|
| `listen_choice` | options, tts_text | TTS 朗读 → 4 选 1 | 听到的词 |
| `picture_word` | options, image_prompt | 看图 → 4 选 1 | 图对应的词 |
| `phonics_blend` | options, phonics_rule | 听音拼词 / 选同规则词（4 选 1） | 符合规则的词 |
| `sentence_fill` | options, pattern | 选词补全句子 | 空格处的词 |
| `read_aloud` | target_text | 麦克风跟读 + 自动评分 | 目标句本身（供回包展示） |
| `letter_trace` | letter, case | 笔顺描红（内嵌 HandwritingCard） | 字母本身 |

## 5. 预校验（`utils/EnglishQuizValidation.ets`）

### 5.1 结构

- 新增 `resolveQuizMode(args)` 纯函数：解析 mode/question_type → `{ mode, isLegacy }`。`mode` 存在且在 6 值内 → 新路径；否则 `question_type` ∈ 3 legacy 值 → legacy 路径；都缺 → fail。
- 按 mode 分派到独立校验函数（`validateListenChoice` / `validatePictureWord` / ... 全部纯函数，hypium 可测）。
- legacy `word` / `sentence` / `phonics_choice` 规则**原样保留**（现有 102 行逻辑不动，历史行为零变化）。
- 失败统一返回 `{ ok: false, error }` → `handleEnglishQuiz` 现有路径回 `{error: 'validation_failed', should_retry: true}`。

### 5.2 新增规则

| 规则 | mode | 处置 |
|---|---|---|
| options 恰 4 项、去重后仍 4 项、含 correct_answer | listen_choice / picture_word / phonics_blend / sentence_fill | 拦截 |
| `tts_text` 非空 | listen_choice | 拦截 |
| `image_prompt` 非空 | picture_word | 拦截 |
| `phonics_rule` 非空；**short 元音规则 CVC 结构匹配**：rule 形如 `short <vowel>` 时，correct_answer 必须 3 字母 CVC（辅-元-辅）且元音与 rule 一致；干扰项同短元音族（同上 CVC 校验） | phonics_blend | 拦截（rule 无法解析为已知形式时**仅警告不拦**） |
| pattern 恰含一个 `___`；correct_answer 在 options 内 | sentence_fill | 拦截 |
| `target_text` 词数 ≤ 8 | read_aloud | 拦截（画像分级上限 0-1→3 词 / 2-3→5 词 / 4-5→8 词由提示词约束，校验只守硬顶） |
| `letter` 为单个 a-zA-Z；`case` ∈ {upper, lower} | letter_trace | 拦截 |

### 5.3 不入校验的规则（提示词纪律）

干扰项同主题（theme 同质）、答案词性与句型匹配、`phonics_blend` 干扰项避免 r-controlled 混入（CVC 校验已覆盖 correct_answer，干扰项语义靠负例）——代码无法可靠判定，全部走工具 description 负例 + 提示词。

## 6. 卡片架构（`components/english/`）

### 6.1 目录与职责

```
components/english/
  EnglishQuizCard.ets        ← 薄路由器（~200 行）：保留原名原路径导出，
                               MessageBubble 挂载点（pending + answered 两处）零改动
  ModeTypes.ets              ← EnglishQuizMode 类型 + resolveEnglishQuizMode(args)
                               + mode 显示名/图标映射 + 参数解析为 ModeArgs
  QuizImageResolver.ets      ← 从现有卡片抽出的三层图片解析纯异步函数
                               （Tier1 英语题缓存 → Tier2 备课图 → Tier3 现生图）
  bodies/
    LegacyBody.ets           ← 现有 free-input（word/sentence）+ phonics_choice UI
                               **原样搬运**，不改行为——历史会话渲染零风险
    ChoiceModeBody.ets       ← listen_choice / picture_word / phonics_blend 共用：
                               题干指令 + （picture_word 带）图片区 + 4 个大按钮选项
                               + tts_text 有则带 TTS 播放钮（复用现有 phonics_choice
                               的 TTS 播放模式）
    SentenceFillBody.ets     ← pattern 渲染（空格高亮槽）+ 4 个词块点选
    ReadAloudBody.ets        ← 目标句展示 + phonetic_hint + ASR 录音钮
                               （复用 SpeechRecognitionService 模式 +
                               voicePermissionDenied 降级）+ 归一化匹配评分
    LetterTraceBody.ets      ← letter_trace 参数映射为 HandwritingCard 契约后内嵌
```

### 6.2 路由规则

`EnglishQuizCard.aboutToAppear` 解析 `toolCall.arguments`：

- 已回答态：payload 含 `mode` → 对应新 body；payload 无 `mode` → LegacyBody（历史会话）
- 待答态：`resolveEnglishQuizMode(args)` → 6 新 mode 之一 → 对应 body；legacy → LegacyBody

所有 body 统一 `@Param toolCall / isAnswered / answeredPayload / largeSize` + `@Event onAnswer`（与现有 HandwritingCard 签名一致，传透即可）。

### 6.3 Answer payload v2（向后兼容）

现有 `EnglishQuizAnswerPayload` 字段全保留，新增：

```typescript
interface EnglishQuizAnswerPayload {
  // ── 现有字段（不动）──
  answered: boolean
  child_answer: string
  correct: boolean
  correct_answer: string
  word: string
  sentence: string
  question_type: string        // 新 mode 回包统一回填 mode 本身（消费方仅 legacy 分支
                               // 判 'phonics_choice'，回 mode 值不会误入该分支）
  skill_key: string
  letter_options?: string[]
  sound_text?: string
  // ── v2 新增 ──
  mode?: string                // 六选一；legacy 回包无此字段
  stage?: string
  pattern?: string             // sentence_fill 回填
  target_text?: string         // read_aloud 回填
  completed?: boolean          // letter_trace 置 true
}
```

word/sentence 字段映射：listen_choice/picture_word/phonics_blend → `word=correct_answer`；sentence_fill → `sentence=correct_answer`；read_aloud → `sentence=target_text`；letter_trace → `letter` 语义由 `child_answer`（描的字母）承载。

**授星零漂移**：`ToolExecutionService.ets:833` 的 `recordStarEvent('english_quiz', ...)` 不动；`StarRewardService.computeStars` 的 `english_quiz` 分支（correct=true → 1 星）不动。letter_trace 的 `completed` 由 LetterTraceBody 映射为 `correct=true` 回包（描红完成即得 1 星，与 handwriting_practice 同语义）。

### 6.4 read_aloud 评分（归一化匹配）

```
normalize(s) = lowercase → 去标点 → 折叠连续空格 → trim
correct = normalize(transcript) === normalize(target)
       || normalize(transcript).includes(normalize(target))
```

- 识别成功即评：命中 → 自动提交 `correct=true`（1 星）
- 未命中 → 显示"再试一次"，可无限重录
- "放弃本局"文字链（NumberPuzzleCard 同款）→ 提交 `correct=false`
- ASR 权限拒绝 → 现有 `voicePermissionDenied` 降级模式（隐藏语音钮 + 键盘输入提示；键盘输入同样走归一化匹配——孩子实在开不了麦也能打字完成）

### 6.5 letter_trace ↔ HandwritingCard 映射

```
letter_trace args                    →  HandwritingCard args
{ letter: "A", case: "upper" }       →  { type: "letter", character: "A" }
{ letter: "a", case: "lower" }       →  { type: "letter", character: "a" }
```

- LetterTraceBody 构造合成 `ToolCall`（arguments 为映射后 JSON）传给内嵌 HandwritingCard；HandwritingCard 的 `onAnswer` 回包 `{completed: boolean}` 在 LetterTraceBody 内适配为 english_quiz payload v2 后透传外层 `onAnswer`。
- **小写笔顺数据缺口**：`config/StrokeOrderData.ets` 现仅 A-Z 大写（程序生成粗线段路径）+ 汉字。`case=lower` 需按同配方补 a-z 小写数据（实施时参考 `adding-stroke-order-data` skill）。**降级方案**：若小写生成成本超预期，先在校验层拦 `case=lower`（should_retry 提示改出 upper），schema description 同步标注"本轮仅支持 upper"——不阻塞主链路。
- 无笔顺数据且 AI 未传 `strokes` 时 HandwritingCard 自有降级渲染，LetterTraceBody 无需额外处理。

### 6.6 视觉

沿用 CardShell 外壳（themeAiBubble 背景 + divider 边框 + 12-14vp 圆角），brand-spec 令牌：小星橙只上当前主操作/选中态（同屏 ≤2 处）、蓝 = 英语领域色、对错只用文字/图标/描边不铺底、可点元素 ≥44vp、卡片 16-20vp 圆角。

## 7. 图片管线（`ToolExecutionService.handleEnglishQuiz`）

现有条件 `questionType === 'phonics_choice' 跳过管线` 改为 **仅 `mode === 'picture_word'`（或 legacy word/sentence）走三层图片解析**；listen_choice / phonics_blend / sentence_fill / read_aloud / letter_trace 直接跳过（无图需求）。

legacy 分支保持现状：word/sentence 走管线、phonics_choice 跳过。校验已保证 picture_word 必有 image_prompt，管线输入契约不变。

## 8. 画像维度：english_reading（23 → 24 维）

### 8.1 触点（4 处 + 1 文档）

| 文件 | 改动 |
|---|---|
| `services/ChildProfileService.ets` `SKILL_DEFINITIONS` | english 组（行 45-48 后）加 `['english_reading', '英语跟读']` |
| `pages/LearningProfilePage.ets` | `sectionKey: 'english'` 的 keys 数组加 `'english_reading'` |
| `config/BuiltinTools.ets` child_profile schema | skill_key description **2 处**（行 1247 schema + 行 1284 tool description）加 `english_reading` |
| `.claude/rules/teaching-architecture.md` §5.1 | 维度清单同步（英语 4 → 5，总数 23 → 24，防 naked drift） |

老画像无需迁移：`ChildProfileService` 按 `SKILL_DEFINITIONS` 遍历构建画像，新维度自动以 level 0 补水。

### 8.2 skill_key 默认映射（新 mode）

AI 未传 `skill_key` 时，由 `ModeTypes.ets` 在解析 ModeArgs 阶段应用下表默认值，卡片构建 payload 时写入（AI 显式传值则覆盖）：

| mode | 默认 skill_key |
|---|---|
| listen_choice | english_alphabet（词听辨则 english_vocab，提示词约束） |
| picture_word | english_vocab |
| phonics_blend | english_phonics |
| sentence_fill | english_sentence |
| read_aloud | **english_reading** |
| letter_trace | english_writing |

## 9. 提示词改写（`models/AssistantModels.ets`）

### 9.1 默认助手（default）

用下面协议**替换**现有三段：【英语】（行 53）、【看图识词】（行 54）、【听力】（行 55）。基于 `docs/english-teaching/english-teaching-prompt-v2.md` §5 文本，微调两处：明确 picture_vocab/listening_quiz 继续在复习/呈现环节使用；纠错话术按原文保留：

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
- phonics_blend:给 phonics_rule(如 "short a"),4 个选项都符合该规则( cat/ham/map/bat );严禁把不同规则的词混进来(如 r-controlled 的 car)。
- sentence_fill:pattern 里恰好一个 ___,孩子从 4 个词选填( I like ___. → apples );严禁 0 个或多个空格;答案词性必须贴句型。
- read_aloud:给孩子一句 ≤8 词的目标句,让他对着麦克风说,卡片自动评分;phonetic_hint 给易错音提示(如 th → "this")。
- letter_trace:写一个字母,case 选 upper/lower,和 handwriting_practice(type:"letter") 联动。
难度按 child_profile:english_alphabet/phonics 定节奏,english_vocab 定词量,english_sentence 定句长(level 0-1→3 词,2-3→5 词,4-5→8 词)。跟读用 english_reading 记录进步。

【纠错话术】孩子答错:先复述他说的、肯定努力,再示范正确音一次,然后给一次再试机会,不连续纠错超过 2 次;答对用 1 句具体表扬(说出他哪里对了),不要只说「真棒」。

【主题纪律】同一节课的词必须同一 theme(颜色/动物/食物/家庭/数字/身体/学校/天气),不要跨主题乱出;每节课保留 2-3 个核心词反复复现。
```

配套：`工具调用规则` 列表（行 82）已含 english_quiz，无需改；【english_quiz imagePrompt】缓存提示（行 88）保留。

### 9.2 学科助手（kids_english）

`KIDS_ENGLISH_SYSTEM_PROMPT` 的「英语教学策略」段同步改写为五步课 + mode 契约，**按其自身工具白名单裁剪**（kids_english 无 image_generation / matching_pairs / handwriting_practice）：

```text
## 英语教学策略
- 聚焦 5 个维度:english_alphabet / english_vocab / english_sentence / english_phonics / english_reading。
- 一节课按「热身→呈现→操练→输出→复习」推进:
  ① 热身:english_quiz(mode:"listen_choice") 听音选词,先复习旧词;
  ② 呈现:picture_vocab(mode:"en") 看图选词(卡片自动出图),再用 english_quiz(mode:"read_aloud") 跟读;
  ③ 操练:english_quiz(mode:"phonics_blend") 拼读拼词(必须给 phonics_rule),listening_quiz 辨音;
  ④ 输出:english_quiz(mode:"sentence_fill") 句型操练,再 read_aloud 说整句;
  ⑤ 复习:english_quiz(mode:"listen_choice" 或 "picture_word") 换个形式重考本课核心词。
- 每节课 ≤15 分钟,每步 1-2 题,不连续超过 10 题,中间穿插聊天和小故事。
- 出题契约同【小星老师出题契约】六 mode 规则(干扰项同韵/同主题、phonics 规则一致、句型恰一个空、跟读 ≤8 词)。
- 难度按 child_profile 各维度 level:english_alphabet/phonics 定节奏,english_vocab 定词量,english_sentence 定句长(level 0-1→3 词,2-3→5 词,4-5→8 词)。
- 纠错:先复述他说的、肯定努力,再示范正确音一次,给一次再试机会,不连续纠错超过 2 次。
- skill_key 对应:听辨 english_alphabet,认词 english_vocab,拼读 english_phonics,句型 english_sentence,跟读 english_reading。
- child_profile(action: "update") 只更新 english_ 开头的技能维度,notes 必须基于本轮具体表现。
```

（其余段：说话方式 / 授星规则 / 边界不动。）

## 10. 兼容性与风险

| 风险 | 缓解 |
|---|---|
| 历史会话（question_type 调用）渲染失败 | LegacyBody 原样搬运现有 UI；payload 无 mode 自动路由 legacy；legacy 校验规则不动 |
| LLM 过渡期仍发 question_type 老调用 | schema required 含 `mode`，但校验层 legacy 兜底路径照常工作（返回 error + should_retry 提示改用 mode）——实际上 required 不满足时多数供应商已在 API 层拒绝，降级风险集中在弱供应商：legacy 兜底保证不崩 |
| 小写笔顺数据缺口 | §6.5 降级方案（校验拦 case=lower） |
| `resolvePendingAnswer` 消费方假设 payload 形状 | payload v2 全量保留旧字段，新增字段全部 optional |
| ASR 对低龄童音识别率 | 归一化包含子串匹配放宽 + 无限重录 + 键盘输入兜底路径 |
| english_reading 在老画像缺失 | SKILL_DEFINITIONS 驱动构建，自动 level 0 补水，无需迁移 |

## 11. 错误处理（复用现有模式）

| 场景 | 处理 |
|---|---|
| 校验失败 | `{error: 'validation_failed', should_retry: true}`（现有路径） |
| picture_word 图片生成失败 | 现有 loading 占位 + 卡片内重试（现有行为） |
| ASR 权限拒绝 | `voicePermissionDenied` 降级 + 键盘输入匹配路径（§6.4） |
| TTS 播放失败 | 重播钮（现有 phonics_choice 模式） |
| 描红中 HandwritingCard 异常 | HandwritingCard 自有降级渲染，LetterTraceBody 不额外包裹 |

## 12. 测试策略

- **hypium 单测**（`entry/src/ohosTest/ets/test/utils/`，DevEco Studio 运行；CLI 验证以干净 `assembleHap` 为准）：
  - `EnglishQuizValidation` 新增：六 mode 各 happy path + 每条拦截规则至少 1 负例；resolveQuizMode 的 mode/question_type/双缺三分支；legacy 三题型回归用例（现有行为快照）
  - phonics CVC 匹配：short a/e/i/o/u 各 1 正例 + r-controlled / 长元音负例 + 不可解析 rule 警告路径
  - 归一化匹配函数：大小写/标点/空格/子串边界用例（若抽为 `utils/ReadAloudMatcher.ets` 纯函数则直接测）
- **无 ArkUI 测试**（项目无组件测试基建）；卡片正确性靠 TS 编译 + 手工验收清单
- **手工验收**：六 mode 各出 1 题走通出题 → 作答 → 授星 → 画像更新链路；历史会话（含 word/sentence/phonics_choice 老消息）渲染不变

## 13. 触点文件清单

| 文件 | 改动类型 |
|---|---|
| `config/BuiltinTools.ets` | english_quiz schema v2 + description 重写 + child_profile skill_key 2 处 |
| `utils/EnglishQuizValidation.ets` | resolveQuizMode + 6 mode 校验函数（+hypium） |
| `components/english/EnglishQuizCard.ets` | 新建（自 `components/EnglishQuizCard.ets` 重构为路由器；**原路径文件删除**，MessageBubble import 路径更新） |
| `components/english/ModeTypes.ets` | 新建 |
| `components/english/QuizImageResolver.ets` | 新建（抽自原卡片） |
| `components/english/bodies/LegacyBody.ets` | 新建（原样搬运） |
| `components/english/bodies/ChoiceModeBody.ets` | 新建 |
| `components/english/bodies/SentenceFillBody.ets` | 新建 |
| `components/english/bodies/ReadAloudBody.ets` | 新建 |
| `components/english/bodies/LetterTraceBody.ets` | 新建 |
| `components/MessageBubble.ets` | 仅 import 路径（挂载逻辑零改动） |
| `services/ToolExecutionService.ets` | handleEnglishQuiz 图片管线条件收窄为 picture_word |
| `services/ChildProfileService.ets` | SKILL_DEFINITIONS + english_reading |
| `pages/LearningProfilePage.ets` | english 组 keys + english_reading |
| `models/AssistantModels.ets` | default 三段替换 + kids_english 策略段改写 |
| `config/StrokeOrderData.ets` | a-z 小写笔顺数据（或走 §6.5 降级） |
| `.claude/rules/teaching-architecture.md` | §4 工具表（english_quiz 行）+ §5.1 维度数 + §2.1 kids_english 说明微调 |
| `entry/src/ohosTest/ets/test/utils/` | 新增校验/映射/归一化测试文件 |

**明确不动**：`models/StarEventModels.ets`（零漂移）、`services/StarRewardService.ets`、`components/PictureVocabCard.ets`、`components/ListeningQuizCard.ets`、`services/SpeechRecognitionService.ets`、`services/LessonPlanningService.ets`（备课管线不感知 mode）。

## 14. 验收清单

- [ ] 六 mode 各 1 题端到端：出题 → 卡片渲染 → 作答 → 授星 → AI 收到 payload v2
- [ ] 校验拦截：options≠4 / 重复 / 缺答案、phonics CVC 不匹配、句型 0/2 个空、跟读 >8 词、letter 非单字符 → 全部 should_retry
- [ ] 历史会话（word / sentence / phonics_choice 老消息）渲染与改动前一致
- [ ] read_aloud：识别命中自动提交 1 星；权限拒后键盘输入可用；放弃提交 correct=false
- [ ] letter_trace：upper 描红走通得 1 星；lower 视笔顺数据落地情况可用或被校验拦截
- [ ] picture_word 三层图片管线命中行为与现状一致；其余 mode 不触发生图
- [ ] 画像页出现「英语跟读」维度（老数据 level 0）；read_aloud 答题后画像更新
- [ ] 默认助手/kids_english 提示词按 §9 生效（新会话首轮 child_profile read 后按五步课推进）
- [ ] `assembleHap` 干净构建通过

---

**相关文档：** `docs/english-teaching/english-teaching-prompt-v2.md`（来源方案）、`docs/english-teaching/brand-spec.md`（视觉令牌）、`.claude/rules/teaching-architecture.md`（教学架构）、`.claude/skills/adding-mini-game-tool/SKILL.md`（新工具配方——本 spec 不加新工具，仅作触点清单参照）
