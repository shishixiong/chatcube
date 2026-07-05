# 分类小管家主题库扩展实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 中追加 `## 分类小管家主题库` 节，引导小星老师按 `child_profile.categorization` level 出数学与抽象逻辑主题。

**Architecture:** 单一字符串改动 — 在 `AssistantModels.ets` 的 JS 数组中两个相邻元素之间插入 14 行新字符串字面量。沿用 2026-06-08 plan（`2026-06-08-handwriting-categorization-teaching-prompts.md`）的「结构断言 + 编译验证」流程替代传统 TDD，因为本次改动是字符串字面量、无逻辑分支可单测。1 个文件、1 次 commit、零新文件、零新依赖。

**Tech Stack:** ArkTS / HarmonyOS stage 模型 / JS 数组 join 出提示词。项目无 `.ets` 单测基建（见 MEMORY.md 「hvigor CLI limitations」），改用 grep 字符串断言 + `hvigorw assembleHap` 编译验证。

---

## 文件改动总览

| 文件 | 类型 | 责任 |
|------|------|------|
| `entry/src/main/ets/models/AssistantModels.ets` | Modify | 在 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 数组里 line 51 之后插入 14 行新元素 |

无新文件创建。

---

## Global Constraints

- **`DEFAULT_ASSISTANT_SYSTEM_PROMPT` 是 JS 数组（非模板字符串）**：与 `Models` 文件 line 25-64 中 `[...].join('\n')` 形式保持一致，每行独立字符串字面量，**不要**改成单一模板字符串
- **ASCII 双引号陷阱（MEMORY.md JSON-in-template-literal）**：本任务虽然不是模板字符串，但维持现有「描述文字用中文逗号 / 全角标点」惯例；新增内容里**禁止出现 ASCII 双引号 `"`**
- **不破坏现有 5 节结构**：`## 行为规则` / `## 教学策略` / `## 6 大领域` / `## 工具调用规则` / `## 元指令优先级` 内容不变；新节插在 `## 6 大领域` 与 `## 工具调用规则` 之间
- **不动其他文件**：`CategorizationCard.ets` / `CategorizationValidation.ets` / `BuiltinTools.ets` / `ChildProfileService.ets` / `StarEventModels.ets` / `SharedPromptFragments.ets` 全部明确排除（见 spec §2.1）
- **编译命令**（与 MEMORY.md 一致）：`DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug`

---

## Task 1: 验证当前插入点（前/后置断言）

**Files:**
- Read: `entry/src/main/ets/models/AssistantModels.ets:25-64`

**Interfaces:**
- Produces: 一个 baseline 数字（line 数、新节标题存在性）给后续 task 对照

- [ ] **Step 1: 读取 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 当前 line 25-64**

```bash
sed -n '25,64p' entry/src/main/ets/models/AssistantModels.ets
```

预期输出末尾应当形如：

```typescript
  '【分类】1 维:categorization。用 categorization 工具,2-3 桶 4-9 件,引导小朋友说分类理由。',
  '',
  '## 工具调用规则',
  '- 如果本轮适合出题 / 写字 / 拼图 / 分类 / 向孩子提问...'
].join('\n')
```

确认 `【分类】` 一行之后是空字符串 `''`（line 51），再下面才是 `## 工具调用规则`。**这是唯一正确的插入锚点**。

- [ ] **Step 2: 断言新节标题当前不存在（前/后对照）**

运行：

```bash
grep -c '## 分类小管家主题库' entry/src/main/ets/models/AssistantModels.ets
```

预期输出：`0`（新节标题目前不存在，作为 baseline）

- [ ] **Step 3: 断言数组 join 形式未破坏（确认仍是 `[...].join('\n')`）**

运行：

```bash
grep -n '.join' entry/src/main/ets/models/AssistantModels.ets
```

预期：看到一行 `].join('\n')`（在 prompt 数组尾部）。如果不是这个形式，**立即停下**，先按 spec §2.1 重构为数组形式再继续。

---

## Task 2: 插入新节（14 行 JS 数组元素）

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets:51-52`（在 line 51 的 `'',` 之后插入；line 52 的 `'## 工具调用规则',` 之前）

**Interfaces:**
- Produces: 14 行新 JS 字符串字面量，按 spec §2.2 内容写入；保持与现有文件一致的标点风格（中文逗号，无 emoji，无 ASCII 双引号）

- [ ] **Step 1: 定位锚点**

用 Edit 工具的 `old_string` 必须**唯一且完整**——下面给出精确定位片段（包含 line 50 末行内容 + line 51 空字符串 + line 52 新节起始）：

在 `entry/src/main/ets/models/AssistantModels.ets` 中找到以下相邻 2 行（这是当前文件 line 51 + line 52）：

```typescript
  '【分类】1 维:categorization。用 categorization 工具,2-3 桶 4-9 件,引导小朋友说分类理由。',
  '',
  '## 工具调用规则',
```

- [ ] **Step 2: 用 Edit 工具插入新节**

`old_string` 必须是这 3 行（让 Edit 精确定位到 line 51 的 `''` 之后）：

```typescript
  '【分类】1 维:categorization。用 categorization 工具,2-3 桶 4-9 件,引导小朋友说分类理由。',
  '',
  '## 工具调用规则',
```

`new_string` 替换为：

```typescript
  '【分类】1 维:categorization。用 categorization 工具,2-3 桶 4-9 件,引导小朋友说分类理由。',
  '',
  '## 分类小管家主题库',
  '按 child_profile.categorization 的 level 选择对应难度的主题,从具体可感知属性过渡到抽象逻辑维度。数学与抽象逻辑主题让孩子逐步建立「数字/形状/属性」的归纳能力,弥补当前出题主题偏生活常识的不足。',
  '',
  '难度 1 (level 0-1, 2 桶 4 件) - 具体可感知属性,适合入门。每桶 2 件,选直观可对比的对象。',
  '主题例子:高矮(高/矮)、大小(大/小)、胖瘦(胖/瘦)、软硬(软/硬)、冷热(冷/热)、明暗(亮/暗)。',
  '示例出题:高矮 → 长颈鹿/树 vs 老鼠/椅子;大小 → 大象 vs 蚂蚁;软硬 → 枕头 vs 石头。',
  '',
  '难度 2 (level 2-3, 3 桶 6 件) - 形状与基本分类,需要一定抽象。每桶 2 件。',
  '主题例子:形状(圆/方/三角)、颜色(红/黄/蓝)、大中小(大/中/小)、上下(上/中/下)、数字奇偶(1/3/5 vs 2/4/6 vs 7/8/9)。',
  '数字奇偶出题时直接写数字 1-9,桶内必须是同一奇偶类型;形状出题用 emoji(⚫ ⬜ 🔺)或中文名(圆形/方形/三角形)。',
  '',
  '难度 3 (level 4-5, 3 桶 9 件) - 抽象概念与组合属性,需要多步推理。每桶 3 件。',
  '主题例子:颜色冷暖(暖色/冷色/中性)、形状组合(圆+红/方+黄/三角+蓝)、数字大小分组(1-3/4-6/7-9)、快慢强弱(快/中/慢)、生熟(水果/蔬菜/未熟)。',
  '颜色冷暖出题时暖色选 红/橙/黄、冷色选 蓝/绿/紫、中性选 黑/白/灰;形状组合用 emoji 双轴标注(如 🔴⚫ 🟨⬜ 🔺🔵)。',
  '',
  '## 工具调用规则',
```

调用 Edit（**不要用 replace_all**——只有这 1 处需要替换）：

```bash
# Claude Code 中调用 Edit 工具，参数见上
```

预期：Edit 报告成功，旧 3 行替换为 14 行（净增 11 行——header + 12 内容 + 1 收尾空字符串）。

- [ ] **Step 3: 校验插入后行数**

运行：

```bash
wc -l entry/src/main/ets/models/AssistantModels.ets
```

预期：原 158 行 + 11 行 = **169 行**（增量可能因空行处理略有 ±2，但总增加 11 行）

- [ ] **Step 4: 视觉确认插入位置**

```bash
sed -n '48,68p' entry/src/main/ets/models/AssistantModels.ets
```

预期看到新节出现在 line 51 之后、`## 工具调用规则` 之前，顺序为：「`【分类】1 维:categorization...`」→「空」→**`## 分类小管家主题库`**→**新节正文 11 行**→「空」→`## 工具调用规则`。

---

## Task 3: 断言新节完整性（grep 4 个锚点）

**Files:**
- Read: `entry/src/main/ets/models/AssistantModels.ets`（仅 grep）

- [ ] **Step 1: 验证节标题存在**

```bash
grep -c '## 分类小管家主题库' entry/src/main/ets/models/AssistantModels.ets
```

预期输出：`1`（与 Task 1 Step 2 的 baseline `0` 对照）

- [ ] **Step 2: 验证 3 个难度分层标题齐全**

```bash
grep -cE '难度 [123] \(level' entry/src/main/ets/models/AssistantModels.ets
```

预期输出：`3`（难度 1 / 难度 2 / 难度 3 各一行）

- [ ] **Step 3: 验证每行字数在合理范围（防合并丢失换行）**

```bash
awk '/^  ## 分类小管家主题库/,/^  ## 工具调用规则/' entry/src/main/ets/models/AssistantModels.ets | grep -cE '^\s+.{20,200}'
```

预期输出：`>= 10`（节正文每行应有 20-200 字符，若少于 10 说明换行被吞掉成单行）

- [ ] **Step 4: ASCII 双引号最终扫描（防 JSON-in-template-literal 陷阱迁移）**

```bash
sed -n '/## 分类小管家主题库/,/## 工具调用规则/p' entry/src/main/ets/models/AssistantModels.ets | grep -c '"'
```

预期输出：`0`（新节内任何 ASCII 双引号必须替换为 `「」` 或全宽 `""`；**如果有命中，立即回退 Task 2 Edit 重写**）

---

## Task 4: 编译验证

**Files:**
- Build: 整个 `entry` 模块

- [ ] **Step 1: 运行 hvigorw assembleHap**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug 2>&1 | tail -40
```

预期：
- 退出码：`0`
- 末尾出现 `BUILD SUCCESSFUL`
- 产物：`entry/build/default/outputs/default/entry-default-signed.hap`

**如果编译失败**：
1. 看末尾错误信息——大概率是 10605038 / 10605040 之类 ArkTS strict-mode 错误
2. 本任务只改字符串字面量，正常情况下不会触发 strict-mode 错误（除非有人误把单引号串改成模板字符串或加 `const` 声明到数组里）
3. 若确实遇到，从 Task 2 重新检查 old_string / new_string 边界

- [ ] **Step 2: 校验 tap 产物时间戳**

```bash
ls -la entry/build/default/outputs/default/entry-default-signed.hap
```

预期：文件时间戳为刚刚（最近 5 分钟内）

---

## Task 5: 提交

**Files:**
- Stage: `entry/src/main/ets/models/AssistantModels.ets`

- [ ] **Step 1: git diff 复核**

```bash
git diff entry/src/main/ets/models/AssistantModels.ets
```

预期：看到 line 51 之后插入 11-14 行新增元素；其余行未变更；`];.join('\n')` 末尾未变动。

- [ ] **Step 2: git add + commit**

```bash
git add entry/src/main/ets/models/AssistantModels.ets
git commit -m "feat(categorization): add 分类小管家主题库 prompt section with 3 difficulty tiers

Adds a new ## 分类小管家主题库 section to DEFAULT_ASSISTANT_SYSTEM_PROMPT
(production JS array form: [...].join('\\n')) at line 51, between ## 6 大领域
and ## 工具调用规则.

Three difficulty tiers mapped to child_profile.categorization level:
- 难度 1 (level 0-1): concrete perceptual attributes (高矮/大小/软硬...)
- 难度 2 (level 2-3): shape/color/number parity (形状/颜色/数字奇偶...)
- 难度 3 (level 4-5): abstract combinations (颜色冷暖/形状组合/数字大小分组...)

Goal: reduce LLM dependence on '动物的家/水果与蔬菜' concrete-life themes
and expand coverage toward math/abstract-logic themes for the 6-7yo
'具体运算阶段' learning window.

Spec: docs/superpowers/specs/2026-07-04-categorization-theme-library-design.md
No other files changed (CategorizationCard.ets / BuiltinTools.ets /
ChildProfileService.ets / StarEventModels.ets explicitly out of scope)."
```

预期：commit 成功，hash 起始 7 位记录下来，下游 reviewer 看 commit 内容。

---

## 端到端验证（subagent 必须执行 + 由后续人工 reviewer 复核）

| # | 场景 | 期望 | 由谁验证 |
|---|------|------|----------|
| 1 | DevEco Studio 内启动 app（不依赖本次改动） | 正常启动 | subagent |
| 2 | 用「小星老师」开启新会话 | 系统 prompt 拉取正确（含新主题库） | subagent |
| 3 | 触发 1 次 categorization 工具调用（child_profile categorization level=0） | AI 应按主题库「难度 1」出题（如「大小」「高矮」等），而不是「动物的家」 | 人工 reviewer |
| 4 | 手动把 child_profile categorization 调到 level=3 后再出一次 | AI 应按主题库「难度 2」出题（形状/颜色/数字奇偶） | 人工 reviewer |
| 5 | 调到 level=5 再出一次 | AI 应按主题库「难度 3」出题（颜色冷暖/数字大小分组） | 人工 reviewer |
| 6 | 显式观察 AI 出题 theme 字段 | theme 字符串包含新引入的数学/抽象关键词（如「数字奇偶」「颜色」） | 人工 reviewer |

> **关于 #3-#6**：本任务是 prompt 引导改动，效果需在生产 LLM 真实会话中观察；纯 subagent 单元测试**无法**自动验证 LLM 出题主题分布。这种「prompt 改动 + 抽样验收」是 LLM 类项目的标准实践。subagent 在 commit 前只需保证编译 + 字符串断言通过；prompt 效果由人工事后复核。

---

## 回退 / 风险

| 风险 | 触发条件 | 缓解 |
|------|---------|------|
| LLM 出题时混淆数字奇偶桶归属（4 写成奇数桶） | LLM 误读 prompt | prompt 内明确写「桶内必须是同一奇偶类型」+ 给具体数字示例 (1/3/5 vs 2/4/6 vs 7/8/9) |
| LLM 给形状主题用 emoji 格式不一致 | LLM 自选表达 | prompt 建议「emoji(⚫ ⬜ 🔺)」或「中文名(圆形/方形/三角形)」二选一 |
| LLM 强行套主题库导致生活主题消失 | 推得太狠 | Task 2 内容用「推荐」「主题例子」而非「必须」「只能」 |
| 新增 ~350 字符导致首字延迟上升 | 内容增长 | 相对 2000+ 字符现有 prompt 增加 ~17%，可接受 |
| **回退方案** | 任何阶段发现不达预期 | 单 commit `git revert` 即清空新节，回到 task 1 baseline |

---

## 不在本次范围（明确排除）

- ❌ 不动 `CategorizationCard.ets`（UI 已支持任意 theme）
- ❌ 不动工具 schema（`categorization` 工具函数签名/参数不变）
- ❌ 不动 child_profile 维度（`categorization` 维度已存在）
- ❌ 不新增 `StarActivityType`（仍走 `categorization`）
- ❌ 不写 hypium 测试（字符串改动，无逻辑分支可测）
- ❌ 不改系统提示词的其他章节（数学/英语/益智等保持原样）
- ❌ 不做主题推荐 UI（让 AI 主动从主题库抽取，不在前端暴露主题列表）
- ❌ 不做主题历史追踪（防重复由 prompt 约束而非代码）

---

## 文件参考

| 路径 | 角色 |
|------|------|
| `entry/src/main/ets/models/AssistantModels.ets` | **唯一改动文件**——line 25-64 的 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 数组 |
| `entry/src/main/ets/components/CategorizationCard.ets` | **不改**——theme 是自由文本，UI 已支持任意 theme |
| `entry/src/main/ets/utils/CategorizationValidation.ets` | **不改**——theme 是自由文本 |
| `entry/src/main/ets/config/BuiltinTools.ets` | **不改**——`categorization` 工具 schema 不变 |
| `entry/src/main/ets/services/ChildProfileService.ets` | **不改**——`categorization` 维度已存在 |
| `entry/src/main/ets/models/StarEventModels.ets` | **不改**——不新增 `StarActivityType` |
| `docs/superpowers/specs/2026-07-04-categorization-theme-library-design.md` | 设计 spec（已 commit 9e21dca） |
| `docs/superpowers/plans/2026-06-08-handwriting-categorization-teaching-prompts.md` | 2026-06-08 同类 prompt 改动 plan（参考「结构断言 + 编译验证」流程） |
| `MEMORY.md` → 「JSON-in-template-literal 陷阱」 | 本次不触发（改数组而非模板字符串），但仍按惯例规避 ASCII 双引号 |
| `MEMORY.md` → 「hvigor CLI limitations」 | CLI 无 lint/test 任务，靠 `assembleHap` 退出码 + grep 字符串断言兜底 |
