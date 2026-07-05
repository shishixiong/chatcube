# 分类小管家主题库扩展设计

**日期：** 2026-07-04
**版本：** v1
**范围：** 在 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 中追加 `## 分类小管家主题库` 节，引导小星老师优先按 child_profile.categorization level 出数学与抽象逻辑主题
**前置文档：**
- `docs/superpowers/specs/2026-06-06-categorization-helper-design.md`（v1 分类小管家整体设计）
- `docs/superpowers/specs/2026-06-08-handwriting-categorization-teaching-prompts-design.md`（该 spec 中描述的 `## 分类小管家使用节奏` 节已被 `6e4b2a3` 重构移除，本次为凭空重建主题库节）
- `.claude/rules/teaching-architecture.md` §2（小星老师身份与 system prompt 注入位置）

---

## 1. 背景与目标

### 1.1 现状

`DEFAULT_ASSISTANT_SYSTEM_PROMPT` 在 `entry/src/main/ets/models/AssistantModels.ets` 中是一个 JS 数组（`[...].join('\n')`），小星老师当前与分类相关的提示词**只有一处**：

```
## 6 大领域
...
【分类】1 维:categorization。用 categorization 工具,2-3 桶 4-9 件,引导小朋友说分类理由。
```

**历史注脚**：`bd9847a`（2026-06-08）曾在 prompt 中加过 `## 分类小管家` / `## 分类小管家教学目标` / `## 分类小管家使用节奏` 三节，`6e4b2a3`（2026-06-16 系统 prompt 优化 - 静态 prompt 172→36 行 + 共享片段提取）重构后**移除**，当前代码已无这三节。本节是凭空重建一个独立的「主题库」节，不依赖历史节的存在。

### 1.2 问题

一行 `【分类】1 维:categorization` 只描述了 schema（桶数 / 件数），**没有主题示例也没有难度映射**——LLM 出题时容易停留在「动物的家」「水果与蔬菜」等具体生活类别，对 6-7 岁皮亚杰「具体运算阶段」关键期所需的「数学/抽象逻辑维度」（数字奇偶、形状、属性对比等）**出题频率和准确性偏低**，child_profile.categorization 维度提升路径单一。

### 1.3 目标

1. 在 system prompt 中追加独立的 `## 分类小管家主题库` 节，按 **3 个难度分层** 推荐数学与抽象逻辑主题
2. 每个主题给出 1-2 行出题要点（具体桶内物品建议），降低 LLM 出题歧义
3. 与 `## 6 大领域 / 【分类】` 节互补，**不强制 LLM 必须从主题库出题**（仍可出动物/水果等具体生活主题）

---

## 2. 设计

### 2.1 改动范围（仅 1 个文件）

**`entry/src/main/ets/models/AssistantModels.ets`**

在 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 的 JS 数组中，定位到「`## 6 大领域`」节之后的空字符串元素（当前文件 line 51 的 `''`），在空字符串之后、`## 工具调用规则` 之前插入一个新节。

**插入后的数组结构**（粗体为新增行）：

```typescript
export const DEFAULT_ASSISTANT_SYSTEM_PROMPT: string = [
  SHARED_IDENTITY,
  '',
  '## 行为规则',
  buildBasePrompt({...}),
  '- 不会的题目老实说...',
  '- 涉及数字 / 时间 / 星期...',
  '- 答对了真诚夸赞...',
  '',
  '## 教学策略',
  '- 根据 child_profile 各维度的 level...',
  '- child_profile(action: "update") 的 notes...',
  '',
  '## 6 大领域',
  '【数学】8 维:...',
  '【数学题型契约】...',
  '【英语】4 维:...',
  '【常识】3 维:...',
  '【益智】3 维:...',
  '【学写字】3 维:...',
  '【分类】1 维:categorization。用 categorization 工具,2-3 桶 4-9 件,引导小朋友说分类理由。',
  '',
  '## 分类小管家主题库',   // ← 新增
  '<新节正文见 §2.2>',
  '',
  '## 工具调用规则',
  '- 如果本轮适合出题...',
  ...
].join('\n')
```

**为什么插在这里（`## 6 大领域` 与 `## 工具调用规则` 之间）**：
- 紧跟 `【分类】` 一行，LLM 读取时自然把「`【分类】` 是规则 / `## 分类小管家主题库` 是推荐主题」关联起来
- 在「`## 工具调用规则`」之前，因为主题库出题仍然要走 `categorization` 工具
- 不放在 `SHARED_IDENTITY` / 行为规则 之前——避免冲淡身份陈述

**不改动的文件**（明确排除）：
- `components/CategorizationCard.ets` — 组件层无须改动，schema 兼容任意 theme
- `utils/CategorizationValidation.ets` — 校验逻辑无须改动，theme 是自由文本
- `config/BuiltinTools.ets` — 工具 schema 不变
- `services/ChildProfileService.ets` — categorization 维度已存在（v1 已在）
- `models/StarEventModels.ets` — 不新增 StarActivityType

### 2.2 新增 prompt 节内容

```
## 分类小管家主题库

按 child_profile.categorization 的 level 选择对应难度的主题,从具体可感知属性过渡到抽象逻辑维度。数学与抽象逻辑主题让孩子逐步建立「数字/形状/属性」的归纳能力,弥补当前出题主题偏生活常识的不足。

难度 1 (level 0-1, 2 桶 4 件) - 具体可感知属性,适合入门。每桶 2 件,选直观可对比的对象。
主题例子:高矮(高/矮)、大小(大/小)、胖瘦(胖/瘦)、软硬(软/硬)、冷热(冷/热)、明暗(亮/暗)。
示例出题:高矮 → 长颈鹿/树 vs 老鼠/椅子;大小 → 大象 vs 蚂蚁;软硬 → 枕头 vs 石头。

难度 2 (level 2-3, 3 桶 6 件) - 形状与基本分类,需要一定抽象。每桶 2 件。
主题例子:形状(圆/方/三角)、颜色(红/黄/蓝)、大中小(大/中/小)、上下(上/中/下)、数字奇偶(1/3/5 vs 2/4/6 vs 7/8/9)。
数字奇偶出题时直接写数字 1-9,桶内必须是同一奇偶类型;形状出题用 emoji(⚫ ⬜ 🔺)或中文名(圆形/方形/三角形)。

难度 3 (level 4-5, 3 桶 9 件) - 抽象概念与组合属性,需要多步推理。每桶 3 件。
主题例子:颜色冷暖(暖色/冷色/中性)、形状组合(圆+红/方+黄/三角+蓝)、数字大小分组(1-3/4-6/7-9)、快慢强弱(快/中/慢)、生熟(水果/蔬菜/未熟)。
颜色冷暖出题时暖色选 红/橙/黄、冷色选 蓝/绿/紫、中性选 黑/白/灰;形状组合用 emoji 双轴标注(如 🔴⚫ 🟨⬜ 🔺🔵)。
```

### 2.3 与现有节的衔接关系

| 节 | 职责 | 改动 |
|------|------|------|
| `## 6 大领域` / `【分类】1 维` | 分类工具的 schema 与出题规则（桶数 / 件数 / 调用方式） | 不改（保留 schema 描述） |
| `## 分类小管家主题库`（新） | 数学与抽象逻辑主题库 + 按 child_profile.categorization level 选主题 | **新增** |
| `## 工具调用规则` | 何时调 `categorization` 工具（与具体主题无关） | 不改 |
| `## 元指令优先级` | 末尾覆盖段的优先级规则 | 不改 |

LLM 出题时的隐式决策树：
```
1. 决定是否走分类工具（参考 ## 工具调用规则 + 孩子表达）
2. 看 child_profile.categorization level
   ├─ level 0-1 → 主题库「难度 1」主题（具体可感知属性）
   ├─ level 2-3 → 主题库「难度 2」主题（形状/颜色/数字奇偶）
   └─ level 4-5 → 主题库「难度 3」主题（抽象概念组合）
   OR：主题库推荐之外，LLM 仍可自由出「动物的家」「水果与蔬菜」等具体生活主题
3. 出题后调用 categorization 工具,沿用【分类】节定义的 schema
4. 孩子作答 → AI 据结果评估 → 调用 child_profile(action:"update") 更新 categorization 维度
```

### 2.4 显式约束（写入 prompt 的元规则）

1. **不强制**：LLM 仍可自由出「动物的家」「水果与蔬菜」等生活主题，主题库仅作推荐
2. **不重复**：同一会话内同一难度不连续出 3 局相同主题（如不要连续 3 局都是「颜色」），保持新鲜感
3. **不破坏校验**：所有主题出题必须遵守 `categorization` 工具 schema（difficulty 1=2桶4件, 2=3桶6件, 3=3桶9件, 每桶≥2件）
4. **不破坏 tone**：给小朋友们的话保持 1-3 句、≤50 字、不带 emoji/markdown；但 prompt 元描述（给 AI 的操作手册）可以用列表

---

## 3. 验证计划

| 步骤 | 验证项 | 通过标准 |
|------|--------|---------|
| 1 | 编译 | `hvigorw assembleHap --mode module -p product=default -p buildMode=debug` 退出码 0 |
| 2 | 字符串完整性 | 用 node 提取 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 整段，确认新增节标题 `## 分类小管家主题库` 存在 |
| 3 | 分层标题齐全 | 同上脚本 grep `难度 1` / `难度 2` / `难度 3` 三段标题都在 |
| 4 | 出题抽样（手工） | 启动 app，触发 1 次 categorization 工具调用，LLM 出题 theme 应优先从主题库抽取（数学/抽象逻辑类） |
| 5 | 与原 prompt 兼容 | `## 6 大领域` 节（含【分类】一行）和 `## 工具调用规则` 节内容不变 |

### 3.1 节标题与分层校验

注意：`DEFAULT_ASSISTANT_SYSTEM_PROMPT` 是 JS 数组 `[...].join('\n')` 而非单一模板字符串，所有新节内容是数组里的字符串字面量。校验脚本扫描整个文件 grep 关键字符串：

```bash
FILE=/Users/mac/mygame/HarmonyOS-app/chatcube/entry/src/main/ets/models/AssistantModels.ets
for needle in '## 分类小管家主题库' '难度 1 (level 0-1' '难度 2 (level 2-3' '难度 3 (level 4-5'; do
  if ! grep -qF "$needle" "$FILE"; then
    echo "FAIL: missing section heading: $needle"
    exit 1
  fi
done
echo "PASS: all expected section headings found"
```

### 3.2 ASCII 双引号扫描（防 JSON-in-template-literal 陷阱）

虽然本节不是模板字符串而是 JS 数组字面量，但保持 ASCII 双引号检查仍是好习惯（防止后人粘错位置）：

```bash
FILE=/Users/mac/mygame/HarmonyOS-app/chatcube/entry/src/main/ets/models/AssistantModels.ets
# 扫描整个 prompt 数组（含 SHARED_IDENTITY / buildBasePrompt 由 build-time 注入的元素）
node -e "
const fs = require('fs');
const src = fs.readFileSync('$FILE', 'utf-8');
// 找 DEFAULT_ASSISTANT_SYSTEM_PROMPT 数组 + 看是否有意外的 ASCII 双引号出现在中文段内
const block = src.substring(
  src.indexOf('DEFAULT_ASSISTANT_SYSTEM_PROMPT'),
  src.indexOf('].join', src.indexOf('DEFAULT_ASSISTANT_SYSTEM_PROMPT'))
);
// 找形如字符串字面量里的 ASCII \" (允许 JS 字符串的引号对 — 我们关心的只是 ASCII 双引号总数不为 0)
const asciiQuotes = (block.match(/\"/g) || []).length;
console.log('ASCII quote count in prompt array:', asciiQuotes.length);
console.log('ASCII quote count in block:', asciiQuotes);
"
# 期望: ASCII 双引号全部出现在 JS 字符串字面量的边界（'...' 内外各有引号对），
# 而不是出现在 description 字段内。如果新增节里包含 ASCII 双引号描述，
# 必须替换成 「」 或 \"\"\"
```

由于 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 字面量是数组，**此处不调用 JSON.parse**——JSON 解析陷阱只适用于单一模板字符串场景。

---

## 4. 不在本次范围（明确排除）

- ❌ 不动 `CategorizationCard.ets` 组件（UI 已支持任意 theme）
- ❌ 不动工具 schema（`categorization` 工具函数签名/参数不变）
- ❌ 不动 child_profile 维度（`categorization` 维度已存在）
- ❌ 不新增 `StarActivityType`（仍走 `categorization`）
- ❌ 不写 hypium 测试（仅字符串改动，无逻辑分支可测）
- ❌ 不改系统提示词的其他章节（数学/英语/益智等保持原样）
- ❌ 不做主题推荐 UI（让 AI 主动从主题库抽取，不在前端暴露主题列表）
- ❌ 不做主题历史追踪（不记本次会话出过哪些主题，防重复由 prompt 约束而非代码）

---

## 5. 风险与回退

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| LLM 出题时混淆数字奇偶的桶归属（4 写成奇数桶） | 中 | 题目错乱 | prompt 中明确写「桶内必须是同一奇偶类型」，并在「数字奇偶」例子旁给具体数字示例 |
| LLM 给形状主题用 emoji 时格式不一致（部分用 ⚫ ⬜ 🔺，部分用 🔴 🟦 🔺） | 中 | 视觉不一致 | prompt 建议「emoji(⚫ ⬜ 🔺)」或「中文名(圆形/方形/三角形)」二选一，由 LLM 自洽即可 |
| LLM 强行套主题库导致出题僵硬（「动物的家」主题消失） | 低 | 主题多样性下降 | prompt 显式写「不强制」，LLM 仍可自由出生活类主题 |
| 新增节导致 prompt 长度增加 → 首字延迟上升 | 低 | 用户感知 | 增量约 350 字，相对 2000+ 字现有 prompt 增加 ~17%，可接受 |
| 回退方案 | — | — | `git revert` 单次 commit 即可 |

---

## 6. 涉及文件

| 文件 | 改动行数估计 |
|------|-------------|
| `entry/src/main/ets/models/AssistantModels.ets` | +20 行（1 个新节，含 3 个难度子段） |
| `docs/superpowers/specs/2026-07-04-categorization-theme-library-design.md` | 本文档 |

---

## 7. 后续可优化（不阻塞）

- 给主题库加一个轻量级「主题历史」记忆（AppStorage），避免同会话重复出同一主题
- 在 `ChildProfileCard.ets` 显示 categorization 维度时，按主题类型拆解（具体主题完成数 vs 抽象主题完成数）
- 主题库规模扩展：补「季节」「情绪」「时间顺序」「字母大小写/元音辅音」「食物生熟」等更多维度
- LLM 端 fine-tune：用真实对话日志训练更精准的主题-难度匹配模型