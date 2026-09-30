# Brand spec — Cube Chat · 小星老师英语教学

来源：linked 代码库 `chatcube`（`entry/src/main/ets/models/AssistantModels.ets` 主题色、`config/ThemeDefaults.ets`、`docs/superpowers/specs/2026-09-10-kids-mode-design.md`）。
视觉姿态参考 OpenDesign 方向库 `human-approachable`（消费者教育产品，大圆角、中性底、产品色驱动）。

## 一句话

暖色单一强调（小星橙）落在近中性冷底上，大圆角、强字重对比，状态色承担对错反馈——像孩子会喜欢、家长会信任的产品界面。

## Six OKLch tokens

```css
:root {
  --bg:      oklch(98% 0.004 240);   /* 中性冷底，避开米色陷阱 */
  --surface: oklch(100% 0 0);        /* 卡片、工具底 */
  --fg:      oklch(22% 0.02 240);    /* 正文，非纯黑 */
  --muted:   oklch(50% 0.018 240);   /* 次要文字、说明 */
  --border:  oklch(90% 0.006 240);   /* 发丝分隔线 */
  --accent:  oklch(74% 0.16 62);     /* 小星橙 ≈ 品牌 #FF9F43 */

  --ok:      oklch(62% 0.15 150);    /* 答对 */
  --bad:     oklch(58% 0.19 25);     /* 答错（仅用于内容文字/描边，不铺底） */
  --info:    oklch(58% 0.11 250);    /* 英语/信息领域色，蓝 */
}
```

## Font stacks

```css
--font-display: 'Avenir Next', 'PingFang SC', -apple-system, system-ui, sans-serif;
--font-body:    -apple-system, BlinkMacSystemFont, 'PingFang SC', system-ui, sans-serif;
--font-mono:    ui-monospace, 'SF Mono', 'JetBrains Mono', Menlo, monospace;
```

Display 与 body 同为无衬线但靠字重（600/700 vs 400）拉开层级；mono 用于工具名、JSON、校验清单。

## 3–5 条观察到的规则

1. **单一暖色强调**：小星橙只出现在当前主操作、当前步骤、专注态描边；同一屏 ≤2 处。
2. **大圆角 + 大触控目标**：卡片 16–20px 圆角，可点元素 ≥44px，面向 6–7 岁手指。
3. **颜色即语义**：绿=答对、红=答错、蓝=英语领域；对错颜色只用于文字、图标与描边，不用大面积铺底。
4. **图片是产品生成物**：单词卡图片由 App 内 `image_generation` 生成，原型中用「AI 生成图」画框如实标注，不冒充实拍。
5. **等级可视化**：孩子画像用分段条形表达 0–5 级，避免纯数字冷漠感。
