# 今日计划按学科拆分 — 设计规格

**日期：** 2026-10-01
**状态：** 待评审（Draft · v1 已核对代码）
**范围：** `LessonPlan` 数据模型新增语文模块 + writing 学科标签；备课提示词 / 校验器 / 渲染器 / 注入门控 / baseline / 台账种子 / 家长计划页的联动改造
**关联文档：** `.claude/rules/teaching-architecture.md`（§3 提示词注入 / §5.2 教学计划 / §7 备课管线）、`docs/superpowers/specs/2026-09-30-vocab-repetition-control-design.md`（词级台账）、`docs/superpowers/specs/2026-09-30-chinese-teaching-tools-implementation.md`（语文工具套件）

---

## 1. Context

### 1.1 问题现象

今日计划（`daily_lesson_plans.plan_json`）只注入小星老师（`default`）；4 个学科助手（`kids_math` / `kids_english` / `kids_chinese` / `kids_games`）在 `ChatViewModel.buildRequestSystemPrompt` 中提前 return，拿不到任何计划内容。学科老师上课"无教案"，全凭自己的学科提示词 + 孩子画像即兴发挥，与备课老师管线脱节。

同时，计划结构本身无法按学科过滤：

| 现有模块 | 隐含学科 | 问题 |
|---|---|---|
| `vocab` | 英语 | 可以直接映射 |
| `math` | 数学 | 可以直接映射 |
| `writing` | **混装**（汉字 + 英文字母 + 数字） | 无法整体归入任何单一学科 |
| `generalKnowledge` | 常识 | 非 3 学科之一 |
| — | 语文 | **没有任何模块承载**——语文 3 维画像（`pinyin` / `chinese_vocab` / `chinese_reading`）与 kids_chinese 工具集（hanzi_card / pinyin_card / pinyin_quiz / chinese_quiz / picture_talk）在计划层无对应物 |

### 1.2 现状代码事实（已逐一核对）

| 层级 | 现状 | 位置 |
|---|---|---|
| 注入门控 | 非 `DEFAULT_ASSISTANT_ID` → 拼 `greetingHint`（若有）后直接 return | `viewmodels/ChatViewModel.ets:322-328` |
| 计划模型 | 4 强类型模块 + freeform，`schemaVersion: 1`，无学科字段 | `models/LessonPlanModels.ets:69-85` |
| 备课提示词 | 密度下限 vocab≥4 / math≥4 / writing≥2 / general≥2（合计 12-16），无语文内容要求 | `utils/LessonPlanPromptUtils.ets:29-167`（`PLANNER_SYSTEM_PROMPT`） |
| 校验器 | 模块数量下限 + math dimension 白名单 + targetSkillLevel ∈ [1,5] | `utils/LessonPlannerValidation.ets:61-88` |
| 渲染器 | `renderDailyPlanSection` 平铺全部模块；"使用建议"含 image_generation 预生成图指引 | `utils/LessonPlanPromptUtils.ets:173-236` |
| 台账输入 | `buildPlannerLedgerPayload` **已合并 en+zh** 台账摘要（newCandidates/dueReview/mastered/cooling 四名单） | `services/LessonPlanningService.ets:751-775` |
| 台账种子 | `extractLedgerSeeds` 只收 `vocab[].word`（en:vocab）+ `writing[].characterOrWord`（CJK 分类） | `utils/LedgerExtractUtils.ets:330-357` |
| baseline 兜底 | `generateBaselinePlan` 模板无 chinese 项，writing 模板（一/二/A/B）无学科标签 | `utils/LessonPlannerBaseline.ets:116-125` |
| 预生成图 | `extractPrefetchRequests` 只收集 vocab/math/writing/generalKnowledge 四模块，`imagePrompt` 为空自然跳过 | `services/LessonPlanningService.ets:1047-1074` |
| 家长计划页 | 按 4 模块分区渲染，全空判定也只查 4 模块 | `pages/LearningTomorrowPlanPage.ets:212-222, 339-356` |

### 1.3 已确认的产品决策（2026-10-01 评审）

1. 学科老师**只拿本学科**部分：数学→数学、英语→英语、语文→语文；常识（generalKnowledge）仍只给小星老师；`kids_games` 不拿计划。
2. **新增 `chinese` 强类型模块**承载语文内容（维度白名单 `pinyin` / `chinese_vocab` / `chinese_reading`，对齐语文 3 维画像与 kids_chinese 工具集）。
3. 学科老师注入**给主题句（themeTitle），不给教学提示（teacherNotes）**——teacherNotes 通常跨学科。

---

## 2. 目标与非目标

### 2.1 目标

1. 计划数据层面**明确区分语文 / 数学 / 英语 / 常识**四部分，`writing` 模块内每项携带学科标签。
2. 3 个学科助手开课时 system prompt 拿到**本学科专属**的计划段（主题句 + 本学科教学点 + 学科适用的使用建议）。
3. 备课老师开始产出语文内容（zh 台账防重复，与英语词同款约束）。
4. 旧 v1 计划无需迁移：对学科老师自然表现为"无本学科内容 → 不注入"。

### 2.2 非目标

- 不把计划重构为 `{chinese:{}, english:{}, ...}` 式学科分组结构（churn 大、freeform 扩展位作废）——保持 5 个强类型模块 + freeform。
- 学科会话不进备课输入管线（`notifySessionEnd` 仍仅接受 `default`）。
- 昨日小结 / 教学风格调整 / 词汇台账段仍仅注入小星老师。
- `kids_games` 无计划承载（游戏类工具自行生成内容）。
- 语文项不做预生成图（语文工具自带笔画数据 / 运行时生图，见 §4）。

---

## 3. 数据模型（`models/LessonPlanModels.ets`）

### 3.1 新增 `LessonPlanChineseItem`

```typescript
export class LessonPlanChineseItem extends LessonPlanItemBase {
  dimension: string = ''        // 白名单: 'pinyin' | 'chinese_vocab' | 'chinese_reading'
  character: string = ''        // 汉字 / 词 / 拼音音节（带调，如 'shān'）/ 短句
  description: string = ''      // 教学描述（中文）
  targetSkillLevel: number = 0  // 目标 level 1-5，对齐 math 项
  // imagePrompt 继承自 base——语文项约定留空（不进预生成图，见 §8.3）
}
```

### 3.2 `LessonPlanWritingItem` 加学科标签

```typescript
export class LessonPlanWritingItem extends LessonPlanItemBase {
  characterOrWord: string = ''
  subject: string = ''          // '' | 'english' | 'chinese' | 'math'
  description: string = ''
  imagePrompt: string = ''
}
```

标签约定：汉字/中文词 → `chinese`；英文字母/英文单词 → `english`；数字书写 → `math`。

### 3.3 `LessonPlan` 根结构

- 新增 `chinese: LessonPlanChineseItem[] = []`（第 5 个强类型模块，排在 `generalKnowledge` 之后）
- `schemaVersion` **类默认值 1 → 2**（`hydrateLessonPlan` 照旧读取显式值、不拒绝旧版本号；baseline 兜底计划经类默认自动成为 v2）
- `freeform` / `childSnapshot` 不变

### 3.4 学科类型与收集纯函数（新文件 `utils/LessonPlanSubjectUtils.ets`）

```typescript
export type PlanSubject = 'chinese' | 'math' | 'english'

export interface SubjectPlanItems {
  chinese: LessonPlanChineseItem[]   // 仅 subject='chinese' 时非空
  vocab: LessonPlanVocabItem[]       // 仅 subject='english' 时非空
  math: LessonPlanMathItem[]         // 仅 subject='math' 时非空
  writing: LessonPlanWritingItem[]   // 按标签过滤后的 writing 项
}

export function planSubjectForAssistant(assistantId: string): PlanSubject | null
// 'kids_math'→'math'，'kids_english'→'english'，'kids_chinese'→'chinese'，其余→null

export function collectPlanItemsForSubject(plan: LessonPlan, subject: PlanSubject): SubjectPlanItems
// math    → plan.math + writing[subject==='math']
// english → plan.vocab + writing[subject==='english']
// chinese → plan.chinese + writing[subject==='chinese']
// 未打标签的 writing 项对学科老师不可见（防脏数据静默漏出）
```

放置于新文件而非 `KidsSubjectUtils.ets`：后者依赖 UI 目录（`KidsSubjectCatalog`），且其"学科"是星数统计口径，与本功能无关。

### 3.5 兼容性（hydrate）

`hydrateLessonPlan` 增补：

- `chinese` 数组解析（候选 key：`chinese` / `chineseItems` / `hanzi`），逐条 `hydrateChineseItem`（缺字段给默认值，同现有模式）
- `writing` 项读取 `subject` 字段（`stringField(r, 'subject')`）

旧 v1 JSON：`chinese` 解析为空数组、`writing.subject` 为空串——**无需迁移**。

---

## 4. 备课提示词（`PLANNER_SYSTEM_PROMPT`）

1. **输出 schema** 增加 `chinese[]` 示例行：

   ```json
   "chinese": [
     {"topicKey": "chinese.pinyin.shan", "dimension": "pinyin", "character": "shān", "description": "认读声母 sh 与韵母 an 的拼读", "targetSkillLevel": 2, "imagePrompt": ""}
   ]
   ```

   及 `writing[]` 示例行补 `"subject": "chinese"` 字段。输出模板的 `"schemaVersion"` 同步 1 → 2。

2. **密度要求更新**：chinese ≥2（建议 3）；合计下限 12-16 → **14-19**。内容要求对齐语文 3 维：
   - `pinyin`：拼音认读（对齐 `pinyin_quiz` / `pinyin_card` 能力）
   - `chinese_vocab`：识字组词（对齐 `hanzi_card` / `chinese_quiz word_build`）
   - `chinese_reading`：阅读表达 / 看图说话（对齐 `picture_talk` / `chinese_quiz sentence_order`）

3. **zh 台账约束**（复用现有 merged 四名单，不拆载荷）：明确说明 ledger 覆盖英语词**和**语文项——`chinese[].character` 严禁出现在 `ledger.mastered` / `ledger.cooling` 中，优先取 `newCandidates` / `dueReview` 中语文项。

4. **writing 标签硬约束**：每个 writing 项必须填 `subject` ∈ {english, chinese, math}（缺失系统会拒绝重试）。

5. **chinese 项 imagePrompt 一律留空**（语文卡片自带笔画数据 / picture_talk 运行时生图）。

6. topicKey 推荐格式补 `chinese.<dim>.<topic>`。

---

## 5. 校验器（`utils/LessonPlannerValidation.ets`）

| 规则 | 内容 |
|---|---|
| 数量下限 | `MIN_PLANNER_COUNTS` 增加 `chinese: 2` |
| chinese dimension 白名单 | `VALID_CHINESE_DIMENSIONS = ['pinyin', 'chinese_vocab', 'chinese_reading']`；空串或不在名单 → issue |
| chinese targetSkillLevel | ∈ [1,5]，0 视为未填 → issue（照抄 math 项模式） |
| writing subject 白名单 | ∈ {'english', 'chinese', 'math'}；空串 → issue（触发 LLM 重试自修） |

全部规则进 `validatePlannerOutput`，复用现有 3 次内部重试循环。

---

## 6. 渲染器（`utils/LessonPlanPromptUtils.ets`）

### 6.1 `renderDailyPlanSection`（小星老师，现有函数改造）

「推荐教学点」从平铺改为**四个学科分组标题**（计划本身直观区分学科）：

```
### 语文
- [chinese_vocab] 字:山 — 组词"高山"…(目标 level 2)
### 数学
- 数学 (math): 两位数加两位数含进位 [math_addition] (目标 level 3)
### 英语
- 英语词汇 (vocab): apple (苹果) — 例句: …
### 常识
- 常识 (generalKnowledge): …
```

- 各组按现有 `formatXxxLine` 输出条目；chinese 项新增 `formatChineseLine`（`- [维度] 字/词/音节 — 描述 (目标 level N)`）
- writing 项按 `subject` 标签归入对应组；**未打标签**的 writing 项归入「常识」组（防御性兜底，校验器使其实际不出现）
- 某组为空 → 整组标题不输出（不出现空节）
- 「使用建议」段（含 image_generation 指引）保持不变——仅小星老师有该工具

### 6.2 新增 `renderDailyPlanSectionForSubject(plan, planDate, weekday, subject)`

```
## 本学科教学目标 (2026-10-02, 星期五)
[SHARED_OVERRIDE_HEADER]
主题: <themeTitle>          ← 有才输出，无则跳过

### 推荐教学点
- <本学科条目，复用 formatXxxLine>

### 使用建议
- 不要一次教完所有点,每次聚焦 1-2 个
- 教新点前调用 child_profile(action:"read") 确认小朋友当前水平
- 已教过的点不要重复出题;可围绕主题变体出题巩固
```

- **本学科 0 条时返回 ''**（调用方整段省略）——旧 v1 计划对学科老师自然静默
- **不含**：teacherNotes（决策 3）、image_generation 预生成图指引（学科助手锁定工具无 `image_generation`）
- 不含词汇台账段 / 昨日小结 / 风格调整（维持小星老师专属）

### 6.3 `renderYesterdaySummarySection` 不动

昨日小结仍仅小星老师；其逐模块列举逻辑不感知 chinese 模块（可选增强，不在本期）。

---

## 7. 注入门控（`viewmodels/ChatViewModel.ets`）

`buildRequestSystemPrompt` 的非 default 分支（现 `:322-328`）改造为：

```
非 default:
  subject = planSubjectForAssistant(assistantId)          // 纯函数
  if subject !== null:
      planSection = 今日计划 → renderDailyPlanSectionForSubject(...)   // try/catch，失败 ''
      withExtra = combine(withExtra, planSection)          // 非空才拼
  if greetingHint 非空:
      return combine(withExtra, greetingHint)              // 招呼元指令仍在末尾最高优先级
  return withExtra

default:
  injectTeachingSections(...)                              // 原路径不动
```

行为矩阵：

| assistantId | 今日计划 | greetingHint（开场） |
|---|---|---|
| `default`（小星老师） | 全量四学科分组段 + 昨日小结 + 风格 + 台账 | 现状 |
| `kids_math` | 数学段（math + writing[math]） | 现状 |
| `kids_english` | 英语段（vocab + writing[english]） | 现状 |
| `kids_chinese` | 语文段（chinese + writing[chinese]） | 现状 |
| `kids_games` / 自定义助手 | 不注入 | 现状 |

- `LESSON_PLAN_REFRESH_TICK` 无需改动：prompt 每次发送重建，学科老师自动拿到刷新后的计划
- 学科老师注入失败（计划拉取异常）→ planSection='' 静默降级，不阻塞对话（与 default 路径同款容错）

---

## 8. 备课服务（`services/LessonPlanningService.ets` + 关联）

### 8.1 baseline 兜底（`utils/LessonPlannerBaseline.ets`）

- `MIN_CHINESE_COUNT = 2` 镜像常量
- 新增 `DEFAULT_CHINESE` 模板（覆盖 3 维度各 1 条 + 1 条备用，如 山/pinyin shān/看图说一句），确定性、无随机
- `DEFAULT_WRITING` 模板补 subject 标签（一/二→chinese，A/B→english）
- baseline 契约不变：输出必通过 `validatePlannerOutput`（含新 chinese 规则）

### 8.2 台账种子（`utils/LedgerExtractUtils.ets` 的 `extractLedgerSeeds`）

增补 chinese 模块收集，按 dimension 映射 item_type：

| dimension | seed item_type | 归一化 |
|---|---|---|
| `pinyin` | `zh:pinyin` | `normalizePinyinSyllable`（`character` 为带调音节） |
| `chinese_vocab` | 单字 → `zh:char`；多字 → `zh:phrase` | 原样（复用 `isCJKText`/长度判定） |
| `chinese_reading` | `zh:sentence` | 现有 sentence 归一化 |

使备课计划的语文项与出题工具共享同一套台账防重复闭环（zh 台账已在 planner 输入四名单内）。

### 8.3 预生成图

`extractPrefetchRequests` 不收集 chinese 模块——语文项无图，逻辑零改动（imagePrompt 约定为空是双保险）。

---

## 9. 家长计划页（`pages/LearningTomorrowPlanPage.ets`）

- 新增「语文」分区渲染 chinese 项（维度标签 + 内容 + 描述 + 目标 level），复用现有分区组件模式
- 两处全空判定（`:339-356`）补 `plan.chinese.length === 0`，避免 chinese-only 计划被误判为空
- writing 分区条目显示学科小标签（`中` / `英` / `数`）——家长可直接看到 writing 拆分归属，呼应「计划明确区分学科」的产品目标

---

## 10. 测试

hypium 纯函数测试（放 `entry/src/ohosTest/ets/test/utils/`，随既有测试组织）：

| 对象 | 用例 |
|---|---|
| `hydrateLessonPlan` | v1 JSON（无 chinese/subject）→ 空数组/空串；v2 JSON 正确水合；候选 key 容错 |
| `collectPlanItemsForSubject` | 三学科各自收集正确；未打标签 writing 不可见；跨模块组合（模块 + writing 标签） |
| `planSubjectForAssistant` | 5 个内置助手 + 未知 id 映射 |
| `renderDailyPlanSectionForSubject` | 有内容输出结构（主题句 + 条目 + 建议三段）；0 条 → ''；不含 teacherNotes / image 指引 |
| `renderDailyPlanSection`（改造后） | 四分组标题；空组不输出空节；未打标签 writing 归常识组 |
| `validatePlannerOutput` | chinese 下限 / dimension 白名单 / level 越界 / writing subject 空串与白名单外 |
| `extractLedgerSeeds` | chinese 三 dimension → 正确 item_type + 归一化 |

组件层（ChatViewModel 分支、计划页分区）不做 ArkUI 测试（项目无基建），靠 CLI assembleHap 编译 + 现有测试回归。

---

## 11. 触点文件清单

| 文件 | 改动 |
|---|---|
| `models/LessonPlanModels.ets` | chinese 模块 + writing.subject + hydrate + schemaVersion 2 |
| `utils/LessonPlanSubjectUtils.ets` | **新建**：PlanSubject / planSubjectForAssistant / collectPlanItemsForSubject |
| `utils/LessonPlannerValidation.ets` | chinese 下限 + 双白名单 + subject 白名单 |
| `utils/LessonPlanPromptUtils.ets` | PLANNER_SYSTEM_PROMPT + renderDailyPlanSection 分组 + renderDailyPlanSectionForSubject + formatChineseLine |
| `utils/LessonPlannerBaseline.ets` | DEFAULT_CHINESE + writing 标签 + MIN_CHINESE_COUNT |
| `utils/LedgerExtractUtils.ets` | extractLedgerSeeds 收 chinese 项 |
| `viewmodels/ChatViewModel.ets` | 非 default 分支学科注入（`buildRequestSystemPrompt`） |
| `pages/LearningTomorrowPlanPage.ets` | 语文分区 + 全空判定 |
| `.claude/rules/teaching-architecture.md` | §2.1 / §3 / §5.2 同步描述 |
| `entry/src/ohosTest/ets/test/utils/` | 新增测试文件 |

明确不改：`MessageBubble.ets`（无新卡片）、`StarEventModels.ets`（无新活动类型）、`ToolExecutionService.ets`（无新工具）、prefetch 路径。

---

## 12. 验收清单

- [ ] 备课老师生成的 v2 计划包含非空 chinese 模块（≥2 项，3 维度白名单内）与全部 writing 项 subject 标签
- [ ] 小星老师 prompt 中「今日教学目标」按 语文/数学/英语/常识 四组呈现，空组无空节
- [ ] 数学老师会话 system prompt 含主题句 + 数学条目，不含英语/语文/常识/teacherNotes/image 指引
- [ ] 英语老师、语文老师同理，各自只见本学科
- [ ] kids_games 与自定义助手行为与现状完全一致
- [ ] 旧 v1 计划（升级前生成）：学科老师无计划段注入、小星老师渲染不报错、家长页正常
- [ ] baseline 兜底计划通过新校验器
- [ ] chinese 计划项进入 zh 台账种子，次日备课不再重复选同字
- [ ] 家长计划页显示语文分区；chinese-only 计划不被误判为空
- [ ] hypium 新增用例全绿；assembleHap 编译通过
