# 中国地图小课堂 · 地图册视觉改版（map_card）

**日期：** 2026-10-23
**来源：** 交互稿 `map-card-redesign.html`（暖纸质地图册）
**范围：** `components/map/MapCard.ets`、`ChinaMapStage.ets`、新增 `MapAtlasTokens / MapZoomCluster / ChinaMapStageController`；`MessageBubble` 的入口横幅
**不改：** 工具契约（`map_card` args / 回执 payload）、`map_quiz` 三个 body 的题面与判定、星星系统（讲解课仍不授星）

## 1. 为什么改

旧版卡片是 CardShell 通用外观：地图只有主题色底 + 灰描边 + 右下角竖排 `＋/−/⟲` 文本键，
省份资料卡只有「名称 + 简称 + 行政中心」，探索过的地方在地图上看不出来。
交互稿给了一套「纸质地图册」语言——坐标纸底、印章、指北针、图例、附图章、橙色主按钮，
和儿童模式品牌色同源（`KidsBrandTokens` 的暖米白/暖橙），所以按稿落地。

## 2. 视觉契约

### 2.1 配色（新增 `MapAtlasTokens.ets`）

`getMapAtlasPalette(isDarkMode)` 返回 `MapAtlasPalette`：

| 语义 | light | dark |
|---|---|---|
| 卡片表面 `surface` | `#FFFDF8` | `#2A251F` |
| 次表面 `surfaceAlt` | `#F4EDDF` | `#342D24` |
| 主文字 `fg` / 次级 `muted` | `#24211C` / `#6F6A60` | `#F2ECE1` / `#BFB5A4` |
| 强调 `accent`（主按钮） | `#FF9F43` | `#FF9F43` |
| 水域 `water` / 陆地 `land` | `#F7F1E4` / `#EADCC5` | `#221E18` / `#3B3226` |
| 已探索 `visited` / 选中 `selected` | `#F8E4CB` / `#FFCB92` | `#4A3A24` / `#7A5324` |
| 省界 `line` / 选中界线 `selectedLine` | `#947A58` / `#6E4A1C` | `#7C6647` / `#F0BE84` |

深色不是纯黑：地图是「纸」，深色下也保持暖褐色相，避免卡片从聊天流里跳出来。
判题红绿（`#22C55E` / `#EF4444`）沿用旧值，跨主题稳定。

### 2.2 层级（全屏 sheet，`largeSize: true`）

```
表头      地理 · 小课堂（kicker） / 中国地图小课堂（21）      [已探索 1/34]
地图册卡  中国 · 34 个省级行政区                     点一点地图
          ┌ 地图视口（纸张网格 + 指北针 + 图例 + 南海诸岛附图）┐
          └ 页脚：拖动地图 · 双指缩放      [− ＋ | 全图]      ┘
资料卡    印章(简称) │ 省名 + 大区徽章 / 全名 / 📍行政中心 │ 听一听
          ── 小星老师说：记住简称「晋」…（虚线分隔）
页脚      已认识 N 个地方              再点几个，记得更牢
          [ 我学会了 · 继续 → ]（未选省时：先点一个地方，禁用态）
```

矮屏（`windowHeightVp < 720`）隐藏「小星老师说」行给地图让位，对应交互稿
`@media (max-height: 760px)` 的取舍。

### 2.3 地图态

| 态 | 填充 | 描边 |
|---|---|---|
| 未探索 | `land` | `line` 1vp |
| 已探索 `visitedIds` | `visited` | `visitedLine` 1.4vp |
| 正在认识 `selectedId` | `selected` | `selectedLine` 2.2vp |
| 出题目标 `targetId` | 学科橙半透明 | 学科橙 2.2vp |
| 对/错 `correctId/wrongId` | 绿/红半透明 | 绿/红 2vp |

重点省最后绘制，界线不被邻省盖住。附图（南海诸岛）改为**固定 34–62vp 的小卡片**
（交互稿里它是图章，不随地图缩放），带「南海诸岛」题注，仍不参与命中判定。

## 3. 交互

- **点省**：资料卡即时刷新 + 印章 stamp-in（0.88→1，200ms）+ 自动 TTS（沿用既有定案）。
- **听一听**：重播；说话中显示实心喇叭 + 「朗读中」，结束变「再听」；连续点省用序号守卫，
  旧朗读的 onComplete 不覆盖新状态。
- **缩放**：页脚横向分段控件（缩小 / 放大 / 全图），由 `ChinaMapStageController`
  遥控舞台（`zoomIn/zoomOut/reset` + `canZoomIn/canZoomOut` 反向同步）；到底时按键置灰。
  出题 body 仍用舞台内建的同款控件（浮在地图右上角），`showZoomControls` 切换。
- **提交**：门槛仍是「探索 ≥1 省」；payload 字段不变，`explored_count` 取去重省数。
- **历史复原**（时间线内联，`largeSize: false`）：从 payload 读回 `focus_province` /
  `explored_count`，内联渲染静态地图（`interactive: false`）+ 精简资料卡 + 完成态行。

## 4. 组件

| 文件 | 职责 |
|---|---|
| `MapAtlasTokens.ets` | 地图册色板（light/dark） |
| `ChinaMapStageController.ets` | `@ObservedV2` 遥控器：舞台注入动作，页脚读缩放态 |
| `MapZoomCluster.ets` | 横向缩放簇（固定 150×44，供页脚与舞台内建两处复用） |
| `ChinaMapStage.ets` | 纸张底 + 六态省色 + 附图章 + 指北针/图例叠层 + 手势 |
| `MapCard.ets` | 表头 / 地图册卡 / 资料卡 / 页脚 |
| `utils/MapAtlasCopy.ets` | 「小星老师说」三套模板（按省 id 稳定散列）+ 进度句，纯函数 |

## 5. 测试

`entry/src/ohosTest/ets/test/utils/MapAtlasCopy.test.ets`：
模板散列稳定、三套文案逐一断言、空 id 兜底、进度句取整。

## 6. 非目标

- 不改 `map_quiz` 的题面/判定/反馈文案。
- 不给 `map_card` 加星星。
- 不做地图省份的悬停态（移动端无 hover）。
- 不做地图区域旋转/复位到省份的动画。
