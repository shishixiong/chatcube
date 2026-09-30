# 语文教学工具套件 v2 — 实施记录

**日期：** 2026-09-30
**范围：** `kids_chinese`（小星语文老师）语文教学升级——新增 4 个互动工具（hanzi_card / pinyin_card / picture_talk / chinese_quiz）+ 2 个画像维度（chinese_vocab / chinese_reading）+ 提示词六步识字法重构
**前置设计：** `docs/chinese-teaching-suite.html`（工具规格）、`docs/chinese-teaching-prompt-v2.md`（提示词 v2）
**相关文档：** `.claude/rules/teaching-architecture.md`（教学体系总架构）、`.claude/skills/adding-mini-game-tool/SKILL.md`（10 步配方）

> 本轮**不包含** §7 备课管线扩展（LessonPlanWritingItem 的 pinyin/words/teachingTip 字段），后续单独排期。

---

## 1. 总览

语文老师从小星老师的「出题为主」升级为「讲解 + 练习二分」：

- **讲解型**（我学会了回执，完成即 1 星）：`hanzi_card` 汉字小课堂、`pinyin_card` 拼音小课堂、`picture_talk` 看图说话
- **练习型**（即判即交，答对 1 星）：`chinese_quiz` 语文小练习（一个工具承载 4 mode）

讲解型卡片沿用 `MathTeachCard` 的回执范式（`feedbackSuppressed = true` 永久抑制对错横幅，操作门槛满足后可点「我学会了 · 继续」）；练习型沿用 `MathQuizCard` 即判范式。

## 2. 四个工具

### 2.1 hanzi_card 汉字小课堂（讲解型）

- **参数契约**：`character`（单字，**必须来自 StrokeOrderData 支持字表**——schema description 注入 `${supportedChars}`）、`pinyin`、`radical`、`structure`（HANZI_STRUCTURES 7 枚举）、`stroke_count`（必须等于笔顺数据笔画数）、`meaning`、`words`(2-3，每个都含本字)、`sentence`（含本字）、`origin?`（字源）、`lookalikes?`(≤2 组 {char,pinyin,note})、`difficulty` 1-3、`skill_key`（固定 chinese_vocab）
- **校验**：`utils/HanziCardValidation.ets` 预校验 + should_retry；卡片侧 `parseHanziCardArgs` 对无笔顺数据的字渲染 invalid 兜底文案
- **卡片**（`components/HanziCard.ets`）：大字 + 拼音头部 → 米字格 Canvas 笔顺动画（复用 HandwritingCard 机制：TICK_MS 33 / FADE_PER_TICK 0.05 / SVG_GRID 1024 / Y-flip，当前笔绿色淡入、已完成笔深色）→ 意思 → 组词 chips → 例句 → 字源卡 → 形近字对比 → 「我学会了 · 继续」（门槛：点过「看笔顺」）
- **结果**：`{character, skill_key, completed: true, watched_strokes}`

### 2.2 pinyin_card 拼音小课堂（讲解型）

- **参数契约**：`initial`（可空=零声母）、`final`、`tone` 0-4（0=轻声）、`syllable`（**必须等于 `composeSyllable(initial, final, tone)` 程序推导的拼合结果**——调号位置按标调规则硬校验）、`examples`(2-5 条 {tone, syllable, char, word})、`mnemonic`、`contrast?`([{a,b,tip}])、`difficulty`、`skill_key`（默认 pinyin）
- **校验**：`utils/PinyinCardValidation.ets`（含 `applyToneMark` / `composeSyllable` 纯函数，a→o→e→iu 标后优先级）
- **卡片**（`components/PinyinCard.ets`）：拼装公式块（声母 + 韵母 = 音节，音节块主题色高亮）→ 四声示范列表（点行 TTS 朗读 `${char}, ${word}`，播放行高亮）→ 口诀 → 易混对比 → 「我学会了 · 继续」（门槛：点过任一示范行）
- **结果**：`{syllable, skill_key, completed: true}`

### 2.3 picture_talk 看图说话（讲解型）

- **参数契约**：`image_prompt`（≤500）、`scene`、`questions`(1-3)、`words`(2-6)、`sample`（示范句）、`difficulty`、`skill_key`（默认 chinese_reading）
- **图片管线**：`handlePictureTalk` 异步调 `ImageIndexService.generateAndStore(ImageSource.PICTURE_TALK, 'pt:' + prompt 小写)`（**永不过期**，`expires_at=0`）→ 成功后把 `image_path` 写回 `toolCall.arguments` → 卡片 `@Monitor('toolCall.arguments')` 刷新（ChoiceModeBody 同款）；生图超时 120s 降级为无图继续说
- **卡片**（`components/PictureTalkCard.ets`）：图片区（占位三态）→ 场景描述 → 编号问题列表 → 可用词 chips → 按住说话 ASR（ReadAloudBody 语音流程，转写填入「你说的」区不自动判分）+ 打字兜底 → 「说好了 · 继续」（门槛：childSaid 非空）→ 提交后展示 sample 示范句
- **结果**：`{completed: true, child_said, skill_key}`

### 2.4 chinese_quiz 语文小练习（练习型，4 mode 薄路由）

- **参数契约**：`mode` 枚举 `word_build / sentence_order / lookalike / antonym` + mode 条件字段：word_build/antonym 用 `character + options`(4 选 1)；lookalike 用 `stem`（恰一个 `___`）+ 单字 options；sentence_order 用 `words`(2-6 打乱词卡)；公共 `answer`、`difficulty`、`skill_key`
- **校验**：`utils/ChineseQuizValidation.ets`——4 唯一非空选项 + answer ∈ options；lookalike stem 恰一个 `___`；sentence_order 的 answer 必须是 words 的字级多重集排列（`sortedChars` 归一化比对，标点/空白剥离）
- **卡片**（`components/chinese/ChineseQuizCard.ets` 薄路由 → `bodies/ChineseChoiceBody` / `bodies/SentenceOrderBody`）：
  - ChoiceBody：lookalike 用 Flex wrap 渲染 stemBefore + ⬜/答案 + stemAfter；word_build/antonym 大字 + 引导语；2 列选项 Grid，点选即判即交
  - SentenceOrderBody：虚线槽区（已放词卡，点击撤回）+ 词卡池（点击放入）；池子本地洗牌最多 8 次，避免 AI 给的顺序恰好等于答案；拼满自动判分（`normalizeSentence` 剥标点比对）
- **结果**：`{answered: true, mode, child_answer, correct, correct_answer, skill_key}`

## 3. 星星与画像

- **StarEventModels 10 漂移点 × 4 全部落位**（union L10 / summary 接口 L51-54 / init L90-93 / meta 接口 L119-122 / META 常量 L209-233 / metaRecord L251-254 / activityTypes L258 / getBucket L296-306 / getMeta L345-355 / getSymbol L398-407）。Symbols：hanzi_card→`sys.symbol.character`、pinyin_card→`textformat`、picture_talk→`mic`、chinese_quiz→`book`（SDK sysResource.js 实测存在）
- **computeStars**：hanzi_card / pinyin_card / picture_talk → `completed === true ? 1 : 0`；chinese_quiz → `correct === true ? 1 : 0`
- **画像 26→28 维**：+`chinese_vocab`（识字组词）、`chinese_reading`（阅读表达）；`ChildProfileService.SKILL_DEFINITIONS`、`SkillLabelUtils.inferSkillGroup`（归「语文」组）、`LearningProfilePage` 语文分组、`BuiltinTools` child_profile schema description（28 keys）四处同步
- **儿童主屏「今日 N 题」**：`KidsSubjectCatalog` 语文 entry activityTypes +4；`countTodayBySubject` 是通用实现自动生效

## 4. 提示词

- `DEFAULT_ASSISTANT_SYSTEM_PROMPT`（小星老师）：新增「## 语文（六步识字法）」①-⑥ 段、「【出题契约】chinese_quiz mode 四选一」、「【字理纪律】」；锁定工具 19→23
- `KIDS_CHINESE_SYSTEM_PROMPT`（语文老师）：教学策略替换为 4 维目标（pinyin / chinese_writing / chinese_vocab / chinese_reading）+ 六步①-⑥ 逐行展开（讲/练工具分工、「严禁只讲不练/只练不讲」硬规则）；并**在 doc §5.2 之上增补**（2026-09-30 二次优化）：「## 出题契约」（hanzi_card 字表严禁外字 / pinyin_card 标调与易混对比 / chinese_quiz 4 mode 质量约束——干扰项不能成词、lookalike 干扰项形近同音、sentence_order 词卡顺序严禁等于答案、antonym answer 严禁等于本字，均带 ⚠️ 严禁 negative example）、「## 看图说话点评」（child_said 回执的点评纪律：先肯定→示范完整句→不判对错）、「## 纠错」独立段；锁定工具 6→10
- `SharedPromptFragments`：工具白名单行 + 4 工具名；「23 维技能」→「28 维技能」

## 5. 触点清单（本轮全部落位）

| 层 | 文件 | 变更 |
|----|------|------|
| 身份 | `utils/SearchToolIdentityUtils.ets` | +4 TOOL_ID 常量 + 4 isXxxFunctionName |
| 注册 | `config/BuiltinTools.ets` | +4 schema/executor/config/注册/getBuiltinToolIds |
| 分发 | `services/ToolExecutionService.ets` | +4 handler（L1282/1372/1462/1580）+ 4 分发分支（L2493-2511，**在 resolveToolId 兜底 L2515 之前**） |
| 星星 | `models/StarEventModels.ets` + `services/StarRewardService.ets` | 10 漂移点 ×4 + computeStars 4 分支 |
| 助手 | `models/AssistantModels.ets` + `utils/SharedPromptFragments.ets` | 锁定列表 + 提示词段落 |
| 卡片 | `components/HanziCard.ets`、`PinyinCard.ets`、`PictureTalkCard.ets`、`chinese/`{ModeTypes, ChineseQuizCard, bodies/ChineseChoiceBody, bodies/SentenceOrderBody} | 新建 7 文件 |
| 挂载 | `components/MessageBubble.ets` | 每工具 7 处 identity 引用（import / clickable 分支 / 2 or-chain / render 守卫 / click 分发 / step switch）+ 4 pending ForEach 块 + 4 StepContent builder |
| 主屏 | `components/kids/KidsSubjectCatalog.ets` | 语文 activityTypes +4 |
| 画像 | `services/ChildProfileService.ets`、`utils/SkillLabelUtils.ets`、`pages/LearningProfilePage.ets` | +2 维度 |
| 图片 | `models/ImageIndexModels.ets` | ImageSource +`PICTURE_TALK`（零消费方破坏：所有条件判断都是 `=== LESSON_PLAN`） |

## 6. 验证记录

- ✅ JSON.parse gauntlet：BuiltinTools.ets 全部 21 个 rawSchemaJson 块解析通过
- ✅ StarEventModels 4-grep：4 类型 × 10 漂移点全部在位（grep 逐行核对）
- ✅ MessageBubble exact-line：每工具恰好 7 处 isXxxFunctionName（import 52 / clickable ~2792-2801 / or-chain 2862+2872 / 守卫 ~3031-3052 / 分发 ~3460-3478 / switch ~3922-3929），无多余
- ✅ 分发分支位于 `resolveToolId` 兜底（L2515）之前
- ✅ `hvigorw assembleHap` debug **BUILD SUCCESSFUL**（修复 4 个编译错后：@Builder 三参默认值、mode 联合类型、Row→Flex flexWrap）
- ⚠️ **设备安装未做**——按 SKILL.md，build 绿只是必要条件。装机后需走一遍：4 卡片内联渲染 / 提交回传 AI / 星星计数 / 今日星星明细标签正确（汉字/拼读/说话/语文）/ 工具中心出现 4 工具 / 语文老师（kids_chinese）会话可触发 / 看图说话生图注入

## 7. 已知限制与后续

1. **备课管线未扩展**：LessonPlanWritingItem 不含 pinyin/words/teachingTip 字段（用户决定本轮不做）
2. **hanzi_card 字表边界**：不支持字表外的字 → handler should_retry 让 AI 换字；卡片对无笔顺字渲染兜底文案
3. **picture_talk 图片失败降级**：生图失败/超时仍可口语作答（题目文字仍在），不阻塞活动
4. **pinyin_card TTS 依赖**：示范朗读走系统 TTS 读 `${char}, ${word}`（不直接读拼音字母）；TTS 不可用时门槛仍可由点击满足
5. **LearningEnglishImagesPage 不展示 picture_talk 图**：该页按 `ImageSource.QUIZ/PLAN` 过滤，属英语专用页；picture_talk 图仅聊天内消费（可接受）
