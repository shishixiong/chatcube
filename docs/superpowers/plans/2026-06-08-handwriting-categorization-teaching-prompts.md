# 学写字与分类小管家教学 Prompt 增强实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 中为 `handwriting_practice` 与 `categorization` 工具补齐"教学目标"+"使用节奏"子节，并在 `ChildProfileService.SKILL_DEFINITIONS` 末尾新增 4 个对应技能维度。

**Architecture:** 本次改动为单一原子功能（提示词 + 维度表），按"基础维度 → 第一个工具 prompt → 第二个工具 prompt → 编译验证"的顺序提交，每步均可独立回退。两个文件改动，1 个 git 仓库，无新依赖。

**Tech Stack:** ArkTS / HarmonyOS stage 模型 / 模板字面量提示词 / 字符串字面量维度表。项目无 .ets 单元测试基建（见记忆备注），改用"结构断言脚本 + 编译验证"代替传统 TDD 流程。

---

## 文件改动总览

| 文件 | 类型 | 责任 |
|------|------|------|
| `entry/src/main/ets/services/ChildProfileService.ets` | Modify | 在 `SKILL_DEFINITIONS` 末尾追加 4 个新维度（line 54 之后） |
| `entry/src/main/ets/models/AssistantModels.ets` | Modify | 在 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 字符串中追加 4 个子节（line 112 之后追加学写字两块，line 122 之后追加分类小管家两块） |

无新文件创建。

---

## Task 1: 扩展 SKILL_DEFINITIONS（基础维度）

**Files:**
- Modify: `entry/src/main/ets/services/ChildProfileService.ets:55`（在 `['spatial_reasoning', '空间推理']` 之后、闭合 `]` 之前）

- [ ] **Step 1: 写失败的结构断言**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
grep -c "精细动作\|英文书写\|中文书写\|分类归纳" entry/src/main/ets/services/ChildProfileService.ets
```

预期输出：`0`（4 个新维度都还不存在，断言失败）

- [ ] **Step 2: 验证 SKILL_DEFINITIONS 当前长度**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
node -e "const f=require('fs').readFileSync('entry/src/main/ets/services/ChildProfileService.ets','utf-8'); const m=f.match(/const SKILL_DEFINITIONS: \[string, string\]\[\] = \[([\s\S]*?)\]/); const arr = m[1].match(/\['[^']+', '[^']+'\]/g); console.log('count=' + arr.length);"
```

预期输出：`count=19`（现有 19 项维度）

- [ ] **Step 3: 修改文件 — 在数组末尾追加 4 个新维度**

在 `entry/src/main/ets/services/ChildProfileService.ets` 中找到 line 54 `['spatial_reasoning', '空间推理']` 那一行，**保留原行的逗号**，在其后插入 4 行新条目（**不要删除** line 55 的闭合 `]`）：

```ts
  ['spatial_reasoning', '空间推理'],
  ['fine_motor', '精细动作'],
  ['english_writing', '英文书写'],
  ['chinese_writing', '中文书写'],
  ['categorization', '分类归纳']
]
```

确认 line 55 仍是 `]`（闭合数组）。最终 36-58 行内容应为：

```ts
const SKILL_DEFINITIONS: [string, string][] = [
  ['math_counting', '数数'],
  ['math_addition', '加法'],
  ['math_subtraction', '减法'],
  ['math_multiply', '乘法'],
  ['math_divide', '除法'],
  ['math_shapes', '图形认知'],
  ['math_comparison', '比较排序'],
  ['math_time', '时间认知'],
  ['english_alphabet', '英语字母'],
  ['english_vocab', '英语词汇'],
  ['english_sentence', '英语句子'],
  ['english_phonics', '自然拼读'],
  ['general_nature', '自然常识'],
  ['general_social', '社交礼仪'],
  ['general_life', '生活常识'],
  ['logic_thinking', '逻辑思维'],
  ['observation', '观察力'],
  ['spatial_reasoning', '空间推理'],
  ['fine_motor', '精细动作'],
  ['english_writing', '英文书写'],
  ['chinese_writing', '中文书写'],
  ['categorization', '分类归纳']
]
```

- [ ] **Step 4: 验证长度变为 23**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
node -e "const f=require('fs').readFileSync('entry/src/main/ets/services/ChildProfileService.ets','utf-8'); const m=f.match(/const SKILL_DEFINITIONS: \[string, string\]\[\] = \[([\s\S]*?)\]/); const arr = m[1].match(/\['[^']+', '[^']+'\]/g); console.log('count=' + arr.length);"
```

预期输出：`count=23`

- [ ] **Step 5: 验证 4 个新维度都存在**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
grep -c "精细动作\|英文书写\|中文书写\|分类归纳" entry/src/main/ets/services/ChildProfileService.ets
```

预期输出：`4`（每条 1 次，4 个新标签全在）

- [ ] **Step 6: 编译**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -30
```

预期：退出码 0，无编译错误。

- [ ] **Step 7: 提交**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/services/ChildProfileService.ets
git commit -m "feat(child-profile): add 4 new skill dimensions for handwriting/categorization"
```

---

## Task 2: 在 DEFAULT_ASSISTANT_SYSTEM_PROMPT 末尾追加「学写字教学目标」与「学写字使用节奏」

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets:122`（在现有 `## 分类小管家` 节末尾的 `child_profile(action:"update") 更新 observation 评估。` 之后追加之前先确认学写字节的尾部位置——本任务在 line 112 之后追加）

- [ ] **Step 1: 写失败的结构断言 — 学写字教学目标子节不存在**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
grep -c "学写字教学目标\|学写字使用节奏" entry/src/main/ets/models/AssistantModels.ets
```

预期输出：`0`（两个新子节都还不存在）

- [ ] **Step 2: 定位当前「## 学写字」节尾部的精确字符串**

在 `AssistantModels.ets` 中找到 `## 学写字` 节，节末句是：

```
字符起步顺序:数字 1-3 → 大写 A C E → 简单汉字(人 大 小 上 下 口 日 月 山 水 火 木 etc.),从简单字符起步。
```

这一行末尾是 `\``,` 之前的位置。

- [ ] **Step 3: 修改文件 — 在「## 学写字」节之后插入 2 个新子节**

在 `AssistantModels.ets` line 112 之后（即在 `从简单字符起步。` 这一行后面，紧接 `## 分类小管家` 这一行之前）插入 2 个新子节文本。**保留**后续 `## 分类小管家` 节不动。

需要插入的完整文本（**注意行首空格必须与现有 prompt 保持一致——每行以 4 空格开头对齐**）：

```

## 学写字教学目标

精细动作(fine_motor):握笔稳、控笔方向、笔顺流畅。
英文字母书写(english_writing):大小写字母的形状识别与正确笔顺。
中文书写(chinese_writing):基本汉字的结构理解与笔顺。
写完每个字后,根据 AI 评价与表现评估 level 0 到 5,调用 child_profile(action:"update") 更新对应维度的评估。
写英文字母更新 english_writing,写汉字更新 chinese_writing,任何书写都更新 fine_motor。
数字 1-9 可同时更新 fine_motor 和 english_alphabet(巩固数字字形)。

## 学写字使用节奏

每次只练 1 个字,看笔顺再写,写完先夸优点再给 1 个改进点。
不连续超过 3 个字,中间要穿插聊天或鼓励。
字符起步顺序推荐:数字 1-3 → 大写 A C E O → 简单汉字(人 大 小 上 下)。
level 0 到 1 用数字和英文字母,level 2 到 3 加大写字母和简单汉字,level 4 到 5 试复杂汉字。
```

最终的提示词尾部结构应当是：

```
## 学写字
[原有 8 行]
适合 letter A-Z a-z、digit 0-9、basic chinese(人 大 小 上 下 口 日 月 山 水 火 木 etc.),从简单字符起步。

## 学写字教学目标
精细动作(fine_motor):握笔稳、控笔方向、笔顺流畅。
英文字母书写(english_writing):大小写字母的形状识别与正确笔顺。
中文书写(chinese_writing):基本汉字的结构理解与笔顺。
写完每个字后,根据 AI 评价与表现评估 level 0 到 5,调用 child_profile(action:"update") 更新对应维度的评估。
写英文字母更新 english_writing,写汉字更新 chinese_writing,任何书写都更新 fine_motor。
数字 1-9 可同时更新 fine_motor 和 english_alphabet(巩固数字字形)。

## 学写字使用节奏
每次只练 1 个字,看笔顺再写,写完先夸优点再给 1 个改进点。
不连续超过 3 个字,中间要穿插聊天或鼓励。
字符起步顺序推荐:数字 1-3 → 大写 A C E O → 简单汉字(人 大 小 上 下)。
level 0 到 1 用数字和英文字母,level 2 到 3 加大写字母和简单汉字,level 4 到 5 试复杂汉字。

## 分类小管家
[原有 8 行不变]
```

- [ ] **Step 4: 验证两个新子节标题存在**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
grep -c "学写字教学目标\|学写字使用节奏" entry/src/main/ets/models/AssistantModels.ets
```

预期输出：`2`（两个新子节标题各出现 1 次）

- [ ] **Step 5: 验证子节内的 3 个维度名都在（间接验证内容正确）**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
grep -E "fine_motor|english_writing|chinese_writing" entry/src/main/ets/models/AssistantModels.ets
```

预期输出：3 行匹配，每行 1 个维度名（出现在 `## 学写字教学目标` 节中）。

- [ ] **Step 6: 验证 4 个 `## ` 子节标题的相对顺序**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
grep -n "^    ## " entry/src/main/ets/models/AssistantModels.ets
```

预期输出（行号可能略有差异，但相对顺序必须为）：`## 学写字` → `## 学写字教学目标` → `## 学写字使用节奏` → `## 分类小管家`

- [ ] **Step 7: 提交**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/models/AssistantModels.ets
git commit -m "feat(prompt): add 学写字教学目标 + 学写字使用节奏 to default assistant"
```

---

## Task 3: 在 DEFAULT_ASSISTANT_SYSTEM_PROMPT 末尾追加「分类小管家教学目标」与「分类小管家使用节奏」

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets`（在 `## 分类小管家` 节末尾之后追加——本任务把 Task 2 之后的剩余 prompt 改动做完）

- [ ] **Step 1: 写失败的结构断言 — 分类小管家两个新子节不存在**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
grep -c "分类小管家教学目标\|分类小管家使用节奏" entry/src/main/ets/models/AssistantModels.ets
```

预期输出：`0`

- [ ] **Step 2: 定位当前「## 分类小管家」节尾部的精确字符串**

当前节末句是：

```
小朋友完成后会返回 correct_count/total_count,根据正确率夸赞或温柔点评,然后 child_profile(action:"update") 更新 observation 评估。
```

这一行之后是反引号 `\`` 闭合整段模板字面量。需要在这一行**之后**插入新内容（反引号之前）。

- [ ] **Step 3: 修改文件 — 在「## 分类小管家」节之后插入 2 个新子节**

需要插入的完整文本（同样以 4 空格开头对齐）：

```

## 分类小管家教学目标

分类归纳(categorization):理解物品共同特征、按规则归类、发现分类逻辑。
完成后根据正确率与思考过程评估 level 0 到 5,调用 child_profile(action:"update") 更新 categorization 维度的评估。
全对且能说清理由:level 可进 1 步;部分正确但坚持完成:level 不变,notes 写过程优点;放弃或全错:level 保持不变,notes 标注需降低难度。

## 分类小管家使用节奏

选个贴近生活的主题,出题后说一句话引导,比如:来,帮小动物回家吧。
完成后先夸赞过程(认真思考、仔细观察)再给结果反馈。
不连续超过 3 局,中间要聊聊天或换其他活动。
引导小朋友说出分类理由(为什么放这个桶),帮助他理解分类逻辑。
level 0 到 1 用 2 桶 4 件,level 2 到 3 用 3 桶 6 件,level 4 到 5 用 3 桶 9 件。
主题起步推荐:动物的家、水果与蔬菜、玩具与工具,熟悉后再换会飞不会飞这种抽象维度。
```

最终的提示词尾部结构应当是：

```
## 分类小管家
[原有 8 行]
小朋友完成后会返回 correct_count/total_count,根据正确率夸赞或温柔点评,然后 child_profile(action:"update") 更新 observation 评估。

## 分类小管家教学目标
分类归纳(categorization):理解物品共同特征、按规则归类、发现分类逻辑。
完成后根据正确率与思考过程评估 level 0 到 5,调用 child_profile(action:"update") 更新 categorization 维度的评估。
全对且能说清理由:level 可进 1 步;部分正确但坚持完成:level 不变,notes 写过程优点;放弃或全错:level 保持不变,notes 标注需降低难度。

## 分类小管家使用节奏
选个贴近生活的主题,出题后说一句话引导,比如:来,帮小动物回家吧。
完成后先夸赞过程(认真思考、仔细观察)再给结果反馈。
不连续超过 3 局,中间要聊聊天或换其他活动。
引导小朋友说出分类理由(为什么放这个桶),帮助他理解分类逻辑。
level 0 到 1 用 2 桶 4 件,level 2 到 3 用 3 桶 6 件,level 4 到 5 用 3 桶 9 件。
主题起步推荐:动物的家、水果与蔬菜、玩具与工具,熟悉后再换会飞不会飞这种抽象维度。
```
```

注意：最后一行 `\`\`` 是模板字面量的闭合反引号，本次插入**不要**触碰它。

- [ ] **Step 4: 验证两个新子节标题存在**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
grep -c "分类小管家教学目标\|分类小管家使用节奏" entry/src/main/ets/models/AssistantModels.ets
```

预期输出：`2`

- [ ] **Step 5: 验证 categorization 维度名被引用**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
grep -c "dimension.*categorization\|categorization.*level\|更新 categorization" entry/src/main/ets/models/AssistantModels.ets
```

预期输出：`>= 1`（至少 1 处引用）

- [ ] **Step 6: 验证 6 个 `## ` 子节标题的相对顺序（学写字/分类小管家 4 节 + 原有 2 节）**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
grep -n "^    ## " entry/src/main/ets/models/AssistantModels.ets
```

预期输出（按顺序）：`## 学写字` → `## 学写字教学目标` → `## 学写字使用节奏` → `## 分类小管家` → `## 分类小管家教学目标` → `## 分类小管家使用节奏` —— 共 6 行 `## ` 标题。

- [ ] **Step 7: 验证模板字面量语法未破坏（反引号配对）**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
node -e "const f=require('fs').readFileSync('entry/src/main/ets/models/AssistantModels.ets','utf-8'); const m=f.match(/DEFAULT_ASSISTANT_SYSTEM_PROMPT: string = \`([\s\S]*?)\`/); console.log('length=' + m[1].length);"
```

预期输出：长度 > 2500（之前约 2200 字符，新增 4 个子节约 +300 字符）。如果输出 `undefined` 或 `null`，说明反引号配对被破坏，需要回退检查。

- [ ] **Step 8: 提交**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git add entry/src/main/ets/models/AssistantModels.ets
git commit -m "feat(prompt): add 分类小管家教学目标 + 分类小管家使用节奏 to default assistant"
```

---

## Task 4: 整体编译与端到端冒烟验证

**Files:**
- (no file changes — verification only)

- [ ] **Step 1: 整体编译**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -30
```

预期：退出码 0，无 ArkTS 编译错误。

- [ ] **Step 2: 提取提示词整体做完整性检查**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
node -e "
const f=require('fs').readFileSync('entry/src/main/ets/models/AssistantModels.ets','utf-8');
const m=f.match(/DEFAULT_ASSISTANT_SYSTEM_PROMPT: string = \`([\s\S]*?)\`/);
const s=m[1];
const required=['学写字教学目标','学写字使用节奏','分类小管家教学目标','分类小管家使用节奏','fine_motor','english_writing','chinese_writing','categorization'];
const missing=required.filter(k=>!s.includes(k));
console.log('totalLen=' + s.length);
console.log('missing=' + JSON.stringify(missing));
"
```

预期输出：
- `totalLen` > 2400
- `missing=[]`（空数组，所有关键字都在）

- [ ] **Step 3: 提取维度数组做完整性检查**

运行：

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
node -e "
const f=require('fs').readFileSync('entry/src/main/ets/services/ChildProfileService.ets','utf-8');
const m=f.match(/const SKILL_DEFINITIONS: \[string, string\]\[\] = \[([\s\S]*?)\]/);
const arr=m[1].match(/\['([^']+)', '([^']+)'\]/g);
const keys=arr.map(s=>s.match(/\['([^']+)/)[1]);
console.log('count=' + arr.length);
console.log('last4=' + JSON.stringify(keys.slice(-4)));
"
```

预期输出：
- `count=23`
- `last4=["fine_motor","english_writing","chinese_writing","categorization"]`

- [ ] **Step 4: 启动 app 并在 DevEco 中跑一次对话（人工）**

1. 在 DevEco Studio 中 Run 编译产物到模拟器/真机
2. 进入"小星老师"助手，发起任意对话
3. 等到 AI 调用一次 `child_profile(action:"read")` 时，确认返回的 `skills` 字段包含 `fine_motor / english_writing / chinese_writing / categorization` 4 个 key，且各自 `level === 0`
4. 输入"我想学写字"，触发 1 次 `handwriting_practice` 工具调用
5. 在 HandwritingCard 上完成书写提交
6. 等到 AI 调用 `child_profile(action:"update")` 时，确认 `updates` 数组中包含 `key: "fine_motor"`（或 english_writing / chinese_writing，取决于 AI 写的是哪个字）
7. 输入"我们来玩分类游戏吧"，触发 1 次 `categorization` 工具调用
8. 在 CategorizationCard 上完成
9. 等到 AI 调用 `child_profile(action:"update")` 时，确认 `updates` 数组中包含 `key: "categorization"`
10. 退出 app 重新进入，重复步骤 3 确认 4 个维度的 level 都被持久化

预期：所有步骤都通过，AI 的实际调用与新增 prompt 一致。

- [ ] **Step 5: 最终 commit（如有未提交改动）**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
git status
# 若有 uncommitted 改动, git add + git commit
```

预期：`git status` 输出无未提交改动。

---

## 自审检查

**1. Spec 覆盖：**
- §2.1 学写字教学目标 → Task 2 Step 3
- §2.2 学写字使用节奏 → Task 2 Step 3
- §2.3 分类小管家教学目标 → Task 3 Step 3
- §2.4 分类小管家使用节奏 → Task 3 Step 3
- §3.1 SKILL_DEFINITIONS 追加 → Task 1 Step 3
- §5 验证计划（编译 + 字符串完整 + 维度数组 + 端到端）→ Task 4

**2. 占位符扫描：** 无 "TBD/TODO/类似 Task N/稍后实现"。

**3. 类型一致性：** `fine_motor / english_writing / chinese_writing / categorization` 这 4 个 key 在 Task 1（定义）、Task 2/3（引用）、Task 4（验证）三处完全一致。
