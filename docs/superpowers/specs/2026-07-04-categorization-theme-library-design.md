# 分类小管家主题库扩展设计

**日期：** 2026-07-04
**版本：** v1
**范围：** 在 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 中追加 `## 分类小管家主题库` 节，引导小星老师优先按 child_profile.categorization level 出数学与抽象逻辑主题
**前置文档：**
- `docs/superpowers/specs/2026-06-06-categorization-helper-design.md`（v1 分类小管家整体设计）
- `docs/superpowers/specs/2026-06-08-handwriting-categorization-teaching-prompts-design.md`（教学目标与使用节奏节，本次追加主题库节）
- `.claude/rules/teaching-architecture.md` §2（小星老师身份与 system prompt 注入位置）

---

## 1. 背景与目标

### 1.1 现状

`DEFAULT_ASSISTANT_SYSTEM_PROMPT` 中的「分类小管家」相关节已有 3 个：
- `## 分类小管家`（基础出题规则）
- `## 分类小管家教学目标`（教学目标与 child_profile 维度映射）
- `## 分类小管家使用节奏`（节奏规则 + 主题起步推荐）

但「使用节奏」节中只列了 3 个推荐主题（动物的家 / 水果与蔬菜 / 玩具与工具）+ 1 个抽象维度举例（会飞/不会飞），没有按难度分层，主题范围偏「生活常识」，**缺少数学与抽象逻辑维度**（数字奇偶、形状、属性对比等）。

### 1.2 问题

6-7 岁是皮亚杰「具体运算阶段」的关键期，分类归纳能力需要从「具体可感知属性」过渡到「抽象逻辑维度」。目前 prompt 引导的主题偏具体，LLM 出题时容易停留在「动物的家」「水果与蔬菜」等具体类别，**对数学/抽象逻辑主题的出题频率和准确性偏低**，child_profile.categorization 维度提升路径单一。

### 1.3 目标

1. 在 system prompt 中追加独立的 `## 分类小管家主题库` 节，按 **3 个难度分层** 推荐数学与抽象逻辑主题
2. 每个主题给出 1-2 行出题要点（具体桶内物品建议），降低 LLM 出题歧义
3. 与现有 3 个分类小管家节互补，**不强制 LLM 必须从主题库出题**（仍可出动物/水果等具体生活主题）

---

## 2. 设计

### 2.1 改动范围（仅 1 个文件）

**`entry/src/main/ets/models/AssistantModels.ets`**

在 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 字符串字面量中，定位到「`## 分类小管家使用节奏`」节的结束位置，在其后追加新节「`## 分类小管家主题库`」。

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
| `## 分类小管家` | 基础出题规则（schema、难度对应） | 不改 |
| `## 分类小管家教学目标` | 训练 child_profile.categorization 维度的目标 | 不改 |
| `## 分类小管家使用节奏` | 出题节奏规则 + 主题起步推荐（旧） | 不改（保留 3 个生活主题作为入门示例） |
| `## 分类小管家主题库`（新） | 数学与抽象逻辑主题库，按难度分层 | **新增** |

LLM 出题时的隐式决策树：
```
1. 看 child_profile.categorization level
   ├─ level 0-1 → 主题库「难度 1」主题 OR 使用节奏的 3 个生活主题
   ├─ level 2-3 → 主题库「难度 2」主题
   └─ level 4-5 → 主题库「难度 3」主题（抽象概念）
2. 出题后调用 categorization_helper 工具,沿用现有 schema
3. 孩子作答 → AI 据结果评估 → 调用 child_profile(action:"update") 更新 categorization 维度
```

### 2.4 显式约束（写入 prompt 的元规则）

1. **不强制**：LLM 仍可自由出「动物的家」「水果与蔬菜」等生活主题，主题库仅作推荐
2. **不重复**：同一会话内同一难度不连续出 3 局相同主题（如不要连续 3 局都是「颜色」），保持新鲜感
3. **不破坏校验**：所有主题出题必须遵守 `categorization_helper` schema（difficulty 1=2桶4件, 2=3桶6件, 3=3桶9件, 每桶≥2件）
4. **不破坏 tone**：给小朋友们的话保持 1-3 句、≤50 字、不带 emoji/markdown；但 prompt 元描述（给 AI 的操作手册）可以用列表

---

## 3. 验证计划

| 步骤 | 验证项 | 通过标准 |
|------|--------|---------|
| 1 | 编译 | `hvigorw assembleHap --mode module -p product=default -p buildMode=debug` 退出码 0 |
| 2 | 字符串完整性 | 用 node 提取 `DEFAULT_ASSISTANT_SYSTEM_PROMPT` 整段，确认新增节标题 `## 分类小管家主题库` 存在 |
| 3 | 分层标题齐全 | 同上脚本 grep `难度 1` / `难度 2` / `难度 3` 三段标题都在 |
| 4 | 出题抽样（手工） | 启动 app，触发 1 次 categorization 工具调用，LLM 出题 theme 应优先从主题库抽取（数学/抽象逻辑类） |
| 5 | 与原 prompt 兼容 | 现有 3 个分类小管家节内容不变，使用节奏节的 3 个推荐主题保留 |

### 3.1 字符串提取与 JSON.parse 校验（防 ASCII " 陷阱）

按 MEMORY.md 的 `JSON-in-template-literal` 陷阱规则，prompt 中所有 ASCII 双引号必须替换为 `「」` 或全宽引号：

```bash
node -e "
const fs = require('fs');
const src = fs.readFileSync(
  '/Users/mac/mygame/HarmonyOS-app/chatcube/entry/src/main/ets/models/AssistantModels.ets',
  'utf-8'
);
const m = src.match(/DEFAULT_ASSISTANT_SYSTEM_PROMPT: string = \`([\s\S]*?)\`/);
if (!m) { console.error('FAIL: prompt literal not found'); process.exit(1); }
const body = m[1];
const expected = [
  '## 分类小管家主题库',
  '难度 1',
  '难度 2',
  '难度 3'
];
for (const e of expected) {
  if (!body.includes(e)) {
    console.error('FAIL: missing section', e);
    process.exit(1);
  }
}
console.log('PASS: all expected sections found');
"
```

### 3.2 ASCII 双引号扫描

```bash
node -e "
const fs = require('fs');
const src = fs.readFileSync(
  '/Users/mac/mygame/HarmonyOS-app/chatcube/entry/src/main/ets/models/AssistantModels.ets',
  'utf-8'
);
const m = src.match(/DEFAULT_ASSISTANT_SYSTEM_PROMPT: string = \`([\s\S]*?)\`/);
const body = m[1];
// 匹配 ASCII 双引号 (U+0022),排除已经被前面转义的情况
const asciiQuotes = body.match(/\"/g) || [];
console.log('ASCII quote count in prompt:', asciiQuotes.length);
if (asciiQuotes.length > 0) {
  console.error('FAIL: ASCII quotes present, replace with 「」 or 「」');
  process.exit(1);
}
console.log('PASS: no ASCII quotes in prompt');
"
```

---

## 4. 不在本次范围（明确排除）

- ❌ 不动 `CategorizationCard.ets` 组件（UI 已支持任意 theme）
- ❌ 不动工具 schema（`categorization_helper` 函数签名/参数不变）
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
| LLM 强行套主题库导致出题僵硬（「动物的家」主题消失） | 低 | 主题多样性下降 | prompt 显式写「不强制」，使用节奏节保留 3 个生活主题作为入门路径 |
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