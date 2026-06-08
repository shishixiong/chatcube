# 学写字与分类小管家：教学目标与使用节奏 prompt 增强

**日期：** 2026-06-08
**版本：** v1
**范围：** 扩展"小星老师"默认助手系统提示词中两个已存在工具的章节，并扩展 ChildProfileService 的技能维度清单
**前置文件：**
- `entry/src/main/ets/models/AssistantModels.ets`（DEFAULT_ASSISTANT_SYSTEM_PROMPT）
- `entry/src/main/ets/services/ChildProfileService.ets`（SKILL_DEFINITIONS）

---

## 1. 背景与目标

`DEFAULT_ASSISTANT_SYSTEM_PROMPT` 中已经为数学、英语、益智游戏三类工具分别建立了「## XX 出题/教学目标」双节结构（教学目标列出该工具训练的 child_profile 维度，出题节描述使用流程）。但 **学写字**（handwriting_practice）和 **分类小管家**（categorization）只描述了怎么用工具，没有「教学目标」节。

与此同时，`ChildProfileService.SKILL_DEFINITIONS` 里没有 精细动作 / 英文书写 / 中文书写 / 分类归纳 这 4 个维度，AI 即便观察到这些能力也无法用 `child_profile(action:"update")` 记录进步。

**本次目标：**
1. 让 prompt 中两个工具的章节与数学/英语/益智对齐：补「## XX 教学目标」+「## XX 使用节奏」两个子节
2. 在 SKILL_DEFINITIONS 末尾追加 4 个新维度，让 AI 能真正把这两个工具的观察写回画像

---

## 2. 系统 prompt 增量

在 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 字符串字面量中：
- `## 学写字` 之后追加 `## 学写字教学目标` 与 `## 学写字使用节奏`
- `## 分类小管家` 之后追加 `## 分类小管家教学目标` 与 `## 分类小管家使用节奏`

注意保持现有 prompt 的写作约束（每次回复 1-3 句、50 字内、绝对不要 emoji、绝对不要 markdown/星号/列表），但 **prompt 本身的元描述不在此约束内**（描述 AI 该怎么用工具的元说明仍然可以是连续段落 + 短列表，因为 prompt 是给 AI 看的"操作手册"而非给小朋友的"话"）。

### 2.1 学写字教学目标（新增）

> 学写字教学目标
>
> 精细动作(fine_motor):握笔稳、控笔方向、笔顺流畅。
> 英文字母书写(english_writing):大小写字母的形状识别与正确笔顺。
> 中文书写(chinese_writing):基本汉字的结构理解与笔顺。
> 写完每个字后,根据 AI 评价与表现评估 level 0 到 5,调用 child_profile(action:"update") 更新对应维度的评估。
> 写英文字母更新 english_writing,写汉字更新 chinese_writing,任何书写都更新 fine_motor。
> 数字 1-9 可同时更新 fine_motor 和 english_alphabet(巩固数字字形)。

### 2.2 学写字使用节奏（新增）

> 学写字使用节奏
>
> 每次只练 1 个字,看笔顺再写,写完先夸优点再给 1 个改进点。
> 不连续超过 3 个字,中间要穿插聊天或鼓励。
> 字符起步顺序推荐:数字 1-3 → 大写 A C E O → 简单汉字(人 大 小 上 下)。
> level 0 到 1 用数字和英文字母,level 2 到 3 加大写字母和简单汉字,level 4 到 5 试复杂汉字。

### 2.3 分类小管家教学目标（新增）

> 分类小管家教学目标
>
> 分类归纳(categorization):理解物品共同特征、按规则归类、发现分类逻辑。
> 完成后根据正确率与思考过程评估 level 0 到 5,调用 child_profile(action:"update") 更新 categorization 维度的评估。
> 全对且能说清理由:level 可进 1 步;部分正确但坚持完成:level 不变,notes 写过程优点;放弃或全错:level 保持不变,notes 标注需降低难度。

### 2.4 分类小管家使用节奏（新增）

> 分类小管家使用节奏
>
> 选个贴近生活的主题,出题后说一句话引导,比如:来,帮小动物回家吧。
> 完成后先夸赞过程(认真思考、仔细观察)再给结果反馈。
> 不连续超过 3 局,中间要聊聊天或换其他活动。
> 引导小朋友说出分类理由(为什么放这个桶),帮助他理解分类逻辑。
> level 0 到 1 用 2 桶 4 件,level 2 到 3 用 3 桶 6 件,level 4 到 5 用 3 桶 9 件。
> 主题起步推荐:动物的家、水果与蔬菜、玩具与工具,熟悉后再换会飞不会飞这种抽象维度。

---

## 3. ChildProfileService 维度扩展

### 3.1 SKILL_DEFINITIONS 追加项

在 `entry/src/main/ets/services/ChildProfileService.ets` 的 `SKILL_DEFINITIONS` 数组 **末尾** 追加 4 个新维度（保持现有 19 项的顺序不变）：

```ts
['fine_motor', '精细动作'],
['english_writing', '英文书写'],
['chinese_writing', '中文书写'],
['categorization', '分类归纳']
```

最终数组长度：19 + 4 = 23 项。

### 3.2 兼容性检查

- `SkillDimension.key` 是字符串键，无枚举/数值依赖
- `Record<string, SkillDimension>` 是动态键，不受数组顺序影响
- `cachedProfile` 反序列化时按 key 查找，新 key 首次出现会得到默认值(level=0, lastAssessed=0, notes='')
- 现有调用方（如果存在遍历 SKILL_DEFINITIONS 显示列表的地方）会自动显示新增维度——这正是预期行为

---

## 4. 不改的部分

| 模块 | 不改理由 |
|------|---------|
| `DEFAULT_ASSISTANT_LOCKED_TOOL_IDS` | 已包含 `HANDWRITING_PRACTICE_TOOL_ID` 与 `CATEGORIZATION_TOOL_ID` |
| `BuiltinTools.ets` 中的工具 schema | 现有 schema 完整，本次只调整 prompt |
| `StarEventModels.ets` / `StarRewardService.ets` | handwriting / categorization 已在所有 4 条 if/else 链中（commit `a391ead`、commit `3029b59` 修复） |
| `ToolExecutionService.ets` | 已有 `handleHandwritingPractice` 与 `handleCategorization` 特殊路径 |
| `HandwritingCard.ets` / `CategorizationCard.ets` | UI 组件与本次 prompt 改动无关 |

---

## 5. 验证计划

| 步骤 | 验证内容 | 通过标准 |
|------|---------|---------|
| 1 | 编译 | `hvigorw assembleHap --mode module -p product=default -p buildMode=debug` 退出码 0 |
| 2 | 字符串完整性 | 用 node 提取 DEFAULT_ASSISTANT_SYSTEM_PROMPT 整段，确认新增 4 个 `## ` 小节标题（学写字教学目标/学写字使用节奏/分类小管家教学目标/分类小管家使用节奏）都在 |
| 3 | 维度数组长度 | `SKILL_DEFINITIONS.length === 23` |
| 4 | 维度可读写 | 启动 app，进入小星老师对话，触发 `child_profile(action:"read")` 检查 fine_motor / english_writing / chinese_writing / categorization 4 个维度初始值都是 level 0 |
| 5 | 工具调用路径 | 触发 1 次 handwriting_practice 工具调用，AI 写完后能调用 child_profile(action:update, dimension:fine_motor)；触发 1 次 categorization，能调用 child_profile(action:update, dimension:categorization) |
| 6 | 在线画像持久化 | 退出再进会话，调 read 确认 4 个新维度的 level 写入并被持久化到 preferences |

---

## 6. 风险与回退

| 风险 | 概率 | 缓解 |
|------|------|------|
| AI 不按 prompt 中新增的 child_profile dimension 调用 | 中 | 教学目标节明确写出 dimension 名称与场景；UI 不动，回退只需恢复 prompt 字符串 |
| 新维度引发 UI 列表长度溢出 | 低 | 项目里没有遍历 SKILL_DEFINITIONS 的写死长度 UI |
| prompt 字符串过长影响首 token 延迟 | 低 | 增量约 350 字，相对 2000+ 字现有 prompt 增加 ~17%，可接受 |

回退方案：`git revert` 单次 commit 即可，prompt 字符串与 SKILL_DEFINITIONS 数组都是单一文件原子改动。

---

## 7. 涉及文件

| 文件 | 改动行数估计 |
|------|-------------|
| `entry/src/main/ets/models/AssistantModels.ets` | +20 行（4 个新小节，每节 5 行） |
| `entry/src/main/ets/services/ChildProfileService.ets` | +5 行（4 个新维度 + 闭合括号） |
| `docs/superpowers/specs/2026-06-08-handwriting-categorization-teaching-prompts-design.md` | 本文档 |

---

## 8. 后续可优化（不阻塞）

- 给 4 个新维度在 `ChildProfileCard.ets` 或类似 UI 中按"语言/动作/逻辑"分组显示，而不是一长串 23 项平铺
- 在 `StarEventModels.ets` 的 `StarActivityMetaMap` 中给 handwriting_practice / categorization 加更细致的元数据（标签、图标）
- 给 handwriting 工具的 AI 评价结果加一个 `dimension_hints` 字段，让 system 提示 AI 更准确判断写得好不好
