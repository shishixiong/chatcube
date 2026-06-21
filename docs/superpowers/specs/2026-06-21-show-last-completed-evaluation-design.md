# 每日评估页 — 展示上次完成的评估 — 设计规格

**日期：** 2026-06-21
**状态：** 设计已确认，待实施
**范围：** 在 `LearningDailyEvaluationPage` 已有的今日态下方追加"上次评估" section,仅在今日未完成时显示,点击头部可跳转到该日期
**前置：** `LearningDailyEvaluationPage` 已上线 (commit `d155aa8` 之后),`TeachingStyleAdjustmentService.getCurrentAdjustment` 已支持 `asOfYMD <= today ORDER BY DESC LIMIT 1` 语义

---

## 1. Context

每日评估页(`LearningDailyEvaluationPage`)当前默认显示**今日**评估,6 个状态分支:loading / done / pending / running / failed / empty(4 子态)。

**问题**: 今日评估**未完成**时(尤其 21:00 之前),家长打开页面只能看到 EmptyState —— "今日评估即将生成" 或 "今日评估未生成",**看不到任何实质性内容**。即使历史已经有 1-13 天的完成评估,家长也必须用 DatePickerBar 切日期才能看到。

**目标**: 今日未完成时,在主区下方追加一个"上次评估 (YYYY-MM-DD)" section,直接展示最近一次已完成的完整内容(SummaryCard + 4 维度 + 本周趋势),让家长开页就能看到"上次评估老师给了什么"。

**用户已确认的 4 个关键决策**:

1. 呈现方式:**追加在下方**(Top 今日态 + Bottom 上次 section),不替换
2. Section 头部:**可点击跳转**到该日期(同步 DatePickerBar)
3. 今日 done 时:**整个 section 自动隐藏**
4. 过去日期浏览:不显示该 section(避免与 DatePickerBar 冲突)

---

## 2. 架构总览

```
┌────────────────────────────────────────────────────────────┐
│ LearningDailyEvaluationPage                                │
│   ├── DetailPaneHeader                                     │
│   ├── DatePickerBar                                        │
│   ├── [今日态 - 6 个状态分支]                              │
│   │     Pending / Running / Failed / EmptyState /          │
│   │     SummaryCard + DimensionsBlock + WeeklyTrendBlock   │
│   └── LastCompletedSection ← 新增 (条件渲染)               │
│         ├── Header (可点击 → 跳日期)                       │
│         ├── SummaryCard(adj)                               │
│         ├── DimensionsBlock(adj)                           │
│         └── WeeklyTrendBlock(trend)                        │
│                                                              │
│ 数据层:                                                     │
│   loadPage() 内并行加载:                                    │
│     - getAdjustmentForDate(selectedDate)  ← 今日/过去     │
│     - getCurrentAdjustment(yesterday, now) ← 上次完成     │
│       (仅 selectedDate === today && 今日未 done 时)        │
└────────────────────────────────────────────────────────────┘
```

---

## 3. 触发条件

`LastCompletedSection` 渲染分**两层条件**,因果链如下:

**层 A (fetch 时机) — `shouldFetchLastCompleted()` 决定是否拉取数据**:

| # | 条件 | 说明 |
|---|------|------|
| ① | `selectedDate === todayYMD()` | 切到过去日期时不拉,避免与 DatePickerBar 冲突 |
| ② | `this.adjustment === null \|\| status !== 'done'` | 今日未完成(null/pending/running/failed 都算) |

```typescript
private shouldFetchLastCompleted(): boolean {
  if (this.selectedDate !== todayYMD()) return false
  if (this.adjustment === null) return true
  if (this.adjustment.status === TeachingStyleAdjustmentStatus.DONE) return false
  return true
}
```

不满足层 A → `clearLastCompleted()` → `lastCompletedAdj = null` → 层 B 的 ③ 自动短路。

**层 B (render 守卫) — `LastCompletedSection()` builder 顶部短路**:

| # | 条件 | 说明 |
|---|------|------|
| ③ | `this.lastCompletedAdj !== null` | 历史无数据时静默隐藏 |
| ④ | `this.lastCompletedAdj.effectiveDate !== todayYMD()` | 防御性,理论上 `getCurrentAdjustment(yesterday, now)` 不会返回今天 |

层 A 失败 → ③ 自动失败(both null);层 A 成功 → ③ 取决于 DB 返回;层 B ③④ 是兜底防御。

---

## 4. 数据获取

### 4.1 复用 service 已有能力,0 改动

- `TeachingStyleAdjustmentService.getCurrentAdjustment(asOfYMD, nowMs)` (service 行 102)
  - 内部走 `DatabaseService.getCurrentTeachingStyleAdjustment`
  - DB 查询: `effective_date <= asOfYMD AND expires_at > now ORDER BY effective_date DESC LIMIT 1`
  - service 拿到 row 后**自动过滤 `status='failed'`** (service 行 107-109)

**关键**: 调用时传 `asOfYMD = shiftYMD(today, -1)` (昨天),查询变为 `effective_date <= yesterday` —— 严格排除今天,只返回**最近一次 `effective_date < today` 且 `status='done'`** 的那一条,正是"上次完成"语义。

### 4.2 trend 复用

- 拿到 `lastCompletedAdj` 后,若 `adj.sourceWeeklyTrendId !== ''`,调 `WeeklyTrendService.getTrendById(id)`
- 失败 → `lastCompletedTrend = null` + console.error,UI 走现有 WeeklyTrendBlock 降级态

---

## 5. 状态字段

### 5.1 新增 3 个 `@Local`

```typescript
@Local lastCompletedAdj: TeachingStyleAdjustment | null = null
@Local lastCompletedTrend: WeeklyTrend | null = null
@Local lastCompletedLoadError: string = ''
```

### 5.2 新增 1 个私有 token

```typescript
private lastCompletedToken: number = 0
```

不与主 `loadToken` 共享 —— 切日期时虽然两个 fetch 都被丢弃,但 last completed 可能在主数据已就绪后还在跑,token 独立便于排查。

### 5.3 复用现有

- `this.adjustment` / `this.trend` (今日)
- `this.loadToken` (主守卫)
- `this.pollTimerId` / `this.POLL_MAX_COUNT` (轮询只跟主数据走,last completed 是一次性读)

**不新增 `isLastCompletedLoading`**: last completed 是一次性读,跟主数据的 `isLoading` 同步清/置。失败回退为 null + error 字段,UI 显示降级态。

---

## 6. 加载流程

### 6.1 `loadPage()` 末尾追加

```typescript
// (主数据加载完成后, 已存在 finally 清 isLoading)
if (token === this.loadToken) {
  if (this.shouldFetchLastCompleted()) {
    await this.loadLastCompleted()
  } else {
    this.clearLastCompleted()
  }
}
```

### 6.2 `loadLastCompleted()`

```typescript
private async loadLastCompleted(): Promise<void> {
  const token: number = ++this.lastCompletedToken
  this.lastCompletedLoadError = ''
  try {
    const yesterdayYMD: string = shiftYMD(todayYMD(), -1)
    const adj: TeachingStyleAdjustment | null =
      await ServiceRegistry.teachingStyle().getCurrentAdjustment(yesterdayYMD, Date.now())
    if (token !== this.lastCompletedToken) return
    this.lastCompletedAdj = adj
    if (adj !== null && adj.sourceWeeklyTrendId !== '') {
      try {
        const trend = await ServiceRegistry.weeklyTrend().getTrendById(adj.sourceWeeklyTrendId)
        if (token !== this.lastCompletedToken) return
        this.lastCompletedTrend = trend
      } catch (e) {
        console.error(TAG, `lastCompleted getTrendById failed: ${(e as BusinessError).message ?? String(e)}`)
        this.lastCompletedTrend = null
      }
    } else {
      this.lastCompletedTrend = null
    }
  } catch (e) {
    console.error(TAG, `loadLastCompleted failed: ${(e as BusinessError).message ?? String(e)}`)
    if (token === this.lastCompletedToken) {
      this.lastCompletedLoadError = (e as BusinessError).message ?? String(e)
      this.lastCompletedAdj = null
      this.lastCompletedTrend = null
    }
  }
}
```

### 6.3 `clearLastCompleted()`

```typescript
private clearLastCompleted(): void {
  this.lastCompletedAdj = null
  this.lastCompletedTrend = null
  this.lastCompletedLoadError = ''
  this.lastCompletedToken++  // 丢弃 in-flight
}
```

---

## 7. UI 渲染

### 7.1 改造 3 个现有 builder 为参数化

| 改前 | 改后 |
|------|------|
| `SummaryCard()` 读 `this.adjustment` | `SummaryCard(adj: TeachingStyleAdjustment)` |
| `DimensionsBlock()` 读 `this.adjustment` | `DimensionsBlock(adj: TeachingStyleAdjustment)` |
| `WeeklyTrendBlock()` 读 `this.trend` | `WeeklyTrendBlock(trend: WeeklyTrend \| null)` |

`PageContent()` done 分支调用更新:

```typescript
this.SummaryCard(this.adjustment)
this.DimensionsBlock(this.adjustment)
this.WeeklyTrendBlock(this.trend)
```

### 7.2 新增 `LastCompletedSection()` builder

```
┌──────────────────────────────────────────────────┐
│  上次评估 · 2026-06-17 (距今 2 天)  chevron_right │  ← 可点击 header
├──────────────────────────────────────────────────┤
│  SummaryCard(adj)                                │
│  DimensionsBlock(adj)                            │
│  WeeklyTrendBlock(trend)                         │
└──────────────────────────────────────────────────┘
```

**视觉规范**:
- **不嵌套外层卡片** (避免 SummaryCard 套娃在 LastCompletedSection 卡片里)
- 外层 Column 顶部 16vp 空白 + 1px 顶部分割线 (`$r('app.color.divider')`) —— 与主区分隔
- Header: 44vp 高度,Row 内放 `Text("上次评估")` + `Text(" · 2026-06-17 (距今 2 天)")` + 右侧 `SymbolGlyph(chevron_right)` 12vp;header 自身是唯一的新视觉元素
- 内部 3 个 block 各自保留原有卡片外壳 (themeSurface + 16vp 圆角 + 1px divider + buildPointLightBorderEffect),与主区视觉一致
- 内部 3 个 block 上下间距 12vp,沿用主区节奏

**点击行为**:

```typescript
.onClick((): void => {
  this.selectedDate = this.lastCompletedAdj.effectiveDate
  this.loadPage()
})
```

**降级渲染** (§3 触发条件 ③ ④ 已在 builder 顶部短路):

```typescript
@Builder
private LastCompletedSection() {
  if (this.lastCompletedAdj === null) {
    Column() {}
    return
  }
  if (this.lastCompletedAdj.effectiveDate === todayYMD()) {
    Column() {}
    return
  }
  // 正常渲染 header + 3 blocks
}
```

### 7.3 `PageContent()` 末尾追加

```typescript
Column({ space: 12 }) {
  this.DatePickerBar()
  // ... 今日 6 个状态分支不变 ...
  this.LastCompletedSection()  // ← 新增; 内部 null 短路
}
```

不需要新增 `if` 条件 —— builder 内部决定。

### 7.4 Header 副标题"距今 N 天"工具

`utils/DateRangeUtils.ets` 新增:

```typescript
export function daysBetween(fromYMD: string, toYMD: string): number {
  if (fromYMD === '' || toYMD === '') return 0
  const from = parseYMD(fromYMD)
  const to = parseYMD(toYMD)
  if (from === null || to === null) return 0
  return Math.round((to.getTime() - from.getTime()) / 86400000)
}

function parseYMD(ymd: string): Date | null {
  const parts: string[] = ymd.split('-')
  if (parts.length !== 3) return null
  const y: number = parseInt(parts[0], 10)
  const m: number = parseInt(parts[1], 10) - 1
  const d: number = parseInt(parts[2], 10)
  if (isNaN(y) || isNaN(m) || isNaN(d)) return null
  return new Date(y, m, d)
}
```

约 15 行,与现有 `shiftYMD` / `todayYMD` 风格一致。

---

## 8. 资源键

新增 2 个 `resources/base/element/string.json` 键:

```json
{
  "learning_daily_evaluation_last_completed_title": {
    "value": "上次评估"
  },
  "learning_daily_evaluation_last_completed_subtitle_format": {
    "value": "距今 %d 天"
  }
}
```

副标题代码: `String($r('app.string.learning_daily_evaluation_last_completed_subtitle_format')).replace('%d', String(days))`

---

## 9. 错误处理矩阵

| 场景 | 行为 |
|------|------|
| `getCurrentAdjustment(yesterday, now)` 返回 null(无历史) | `lastCompletedAdj = null` → 整个 section 不渲染 |
| `getCurrentAdjustment` 抛异常 | catch → `lastCompletedLoadError = msg` + console.error + `lastCompletedAdj = null` → section 不渲染,**不弹任何 UI** |
| `getTrendById` 抛异常 | `lastCompletedTrend = null` + console.error → section 渲染,WeeklyTrendBlock 走降级态 |
| 今日 null → 触发立即生成 → done | `TEACHING_STYLE_ADJUSTMENT_REFRESH_TICK` 触发 → `loadPage` 重跑 → `shouldFetchLastCompleted` 返 false → `clearLastCompleted` → section 消失 |
| 今日 pending/running 轮询超时(2min) | 当前代码"生成超时"提示;section 仍渲染(对家长有用) |
| 切日期 today → yesterday | `loadPage(yesterday)` → `loadToken++` + `shouldFetchLastCompleted` 返 false → `clearLastCompleted` → section 消失 |
| 切日期 yesterday → today | `loadPage(today)` → 今日空 → `shouldFetchLastCompleted` 返 true → 重新拉 → section 出现 |
| 用户点 section header 跳转 | `selectedDate = lastCompletedAdj.effectiveDate; loadPage()` → 主区变成该日期完整内容 + section 自动消失 |
| 连点 section header 两次 | 第二次读 `lastCompletedAdj.effectiveDate`(同步值)→ 同样 `selectedDate` + `loadPage` → `loadToken++` 丢旧请求,幂等无副作用 |
| LastCompleted fetch 还在 in-flight,用户切日期 | `loadToken++` + `clearLastCompleted` 内部 `lastCompletedToken++` → 旧 await 返回后 token 不匹配,丢弃 |
| `lastCompletedAdj.effectiveDate === today`(理论不可能) | §7.2 第二个守卫不渲染 |

---

## 10. 轮询 / 订阅 与 last completed 的交互

- **不扩展轮询**: 轮询仅跟踪今日 `pending/running` 状态,`loadLastCompleted` 是一次性读,不轮询
- **AppStorage 订阅已覆盖**: `subscribeRefreshTick` 在 `loadPage` 中调用,当评估老师写任何 tsa 行(今天或过去)都触发 → 重跑 `loadPage` → 自然刷新 last completed
- **不引入新 AppStorage key**

---

## 11. 测试

### 11.1 单元测试(hypium + hamock)

**新增文件**: `entry/src/ohosTest/ets/test/utils/DateRangeUtils.test.ets`

`daysBetween` 测试矩阵(**10 个 case**):

| # | 输入 | 期望 | 说明 |
|---|------|------|------|
| 1 | `daysBetween('2026-06-19', '2026-06-19')` | `0` | 同一天 |
| 2 | `daysBetween('2026-06-18', '2026-06-19')` | `1` | 相邻 |
| 3 | `daysBetween('2026-06-05', '2026-06-19')` | `14` | 14 天滚动边界 |
| 4 | `daysBetween('2026-05-31', '2026-06-02')` | `2` | 跨月 |
| 5 | `daysBetween('2025-12-31', '2026-01-01')` | `1` | 跨年 |
| 6 | `daysBetween('2026-06-19', '2026-06-18')` | `-1` | 反向(防御) |
| 7 | `daysBetween('', '2026-06-19')` | `0` | 空字符串 fallback |
| 8 | `daysBetween('2026-06-19', '')` | `0` | 空字符串 fallback |
| 9 | `daysBetween('invalid', '2026-06-19')` | `0` | 格式错 fallback |
| 10 | `daysBetween('2026-06-19', '2026-06-19')` | `0` | 显式同日期 |

**不测**:
- `getCurrentAdjustment` 行为(service 已有覆盖,page 只是调用)
- `LastCompletedSection` builder(ArkUI 组件级测试基建缺失,按项目惯例放手动)

### 11.2 手动验证(端到端,**14 个场景**)

| # | 场景 | 操作 | 期望 |
|---|------|------|------|
| M1 | 全新用户,今日 21:00 前 | 开页 | EmptyState "今日评估即将生成",**无 section** |
| M2 | 全新用户,今日 21:00 后 | 开页 | EmptyState "今日评估未生成" + "立即生成",**无 section** |
| M3 | 有 1 天历史,今日空 | 开页 | 主区 EmptyState "今日评估未生成";section header "上次评估 · 昨天 (距今 1 天)" + SummaryCard + 4 维度 + Trend |
| M4 | 有 3 天历史,今日空 | 开页 | section 显示最近一天(距今 1 天) |
| M5 | 今日 pending | 手动触发后立刻开页 | PendingState + section 仍显示 |
| M6 | 今日 running | pending 完成后 | RunningState + section 仍显示 |
| M7 | 今日 done | running 完成后 | 完整 3 块内容,**section 自动消失** |
| M8 | 今日 failed | 模拟 LLM 失败 | FailedState + section 仍显示 |
| M9 | 点 section header | 点击 | 跳到该日期,DatePickerBar 同步,**section 消失**(视图变成该日期的完整内容) |
| M10 | 切日期 today → yesterday | DatePickerBar ← | 主区变成昨天视图,**section 消失** |
| M11 | 切回 today | DatePickerBar "今天"按钮 | section 重新出现 |
| M12 | 趋势数据缺失 | 删 prepared_media 关联 trend | section 仍渲染,WeeklyTrendBlock 降级态"本周趋势数据已过期" |
| M13 | 边界:14 天前完成 | 手动写 14 天前 tsa 行 | section header "(距今 14 天)",副标题可点跳转 |
| M14 | EmptyState 4 子态 + section 共存 | M3 场景验证 | 主区 EmptyState 与 section 视觉上垂直堆叠、明确分隔(1px divider) |

### 11.3 端到端烟测(**4 个场景**)

| # | 场景 | 期望 |
|---|------|------|
| S1 | 新装 app + 0 历史 | 任何状态都不出现 section |
| S2 | 有 3 天历史 + 今日 done | section 不出现(今日 done 触发自动隐藏) |
| S3 | 有 3 天历史 + 今日 null | section 出现,正确显示最近一次 |
| S4 | 切日期时 section 状态 | 来回切 3 次,section 出现/消失行为符合 M10/M11 |

### 11.4 验收清单

- [ ] `assembleHap` 通过(无 ArkTS 严格模式错误,无 10605038/10605040)
- [ ] `daysBetween` 10 个 hypium 单元测试全过
- [ ] M1-M14 14 个手动场景全部符合预期
- [ ] S1-S4 4 个烟测场景全部符合预期
- [ ] `LearningProfilePage` / `LearningTomorrowPlanPage` / IndexSettingsPanel 入口行为不变
- [ ] 现有 `getCurrentAdjustment` 调用方(备课老师 / ChatViewModel)行为不变(page 是新增调用,不修改已有)
- [ ] `TEACHING_STYLE_ADJUSTMENT_REFRESH_TICK` 订阅 + 轮询 行为不变
- [ ] `assembleHap` 完成后 `entry-default-signed.hap` 产物正常生成

---

## 12. 关键文件清单

### 12.1 修改(3 个文件)

| 路径 | 改动 |
|------|------|
| `entry/src/main/ets/pages/LearningDailyEvaluationPage.ets` | +3 个 @Local + 1 个 token + 1 个谓词 + 1 个 loadLastCompleted + 1 个 clearLastCompleted + 1 个 LastCompletedSection builder + 3 个 builder 参数化 + 1 个 daysBetween 引用 + import 扩展 |
| `entry/src/main/ets/utils/DateRangeUtils.ets` | + `daysBetween(fromYMD, toYMD): number` (~15 行) + 私有 `parseYMD` helper (~10 行) |
| `entry/src/main/resources/base/element/string.json` | + 2 个 string key |

### 12.2 新增(1 个文件)

| 路径 | 角色 |
|------|------|
| `entry/src/ohosTest/ets/test/utils/DateRangeUtils.test.ets` | `daysBetween` 10 个 hypium case |

### 12.3 不修改

- `services/TeachingStyleAdjustmentService.ets`(已有 `getCurrentAdjustment` 满足需求)
- `services/WeeklyTrendService.ets`(已有 `getTrendById`)
- `services/DatabaseService.ets`(无新查询)
- `config/AppStorageKeys.ets`(无新 key)
- `router_map.json` / `SettingsRouteName.ets`(无新路由)

---

## 13. 风险 & 缓解

| 风险 | 缓解 |
|------|------|
| `getCurrentAdjustment(yesterday, now)` 在 `getAdjustmentForDate(today)` 之前完成,出现 race | `loadToken` + `lastCompletedToken` 双层守卫;旧请求返回后 token 不匹配直接 return |
| `daysBetween` 在 DST 切换日(中国不实行 DST,但鸿蒙底层 Date 可能有 1 小时偏移)边界误差 | `Math.round` 吸收;副标题"距今 N 天"对 ±1 天不敏感,UI 误差不可见 |
| `lastCompletedTrend` 为 null 时 WeeklyTrendBlock 降级态体验差 | 复用现有"本周趋势数据已过期"提示,改动 0 |
| section header 跳转后,用户立即按"今天"按钮 | 现有 DatePickerBar 已有该按钮,行为不变,section 自动按 selectedDate 重新评估 |
| 大量历史数据(接近 14 天)时,section 长期占据屏幕 | 14 天滚动窗口限制最大;section 内部没有水平/垂直滚动,UI 占用空间 ≤ 600vp,可接受 |
| `parseYMD` 对非法输入返回 null,fallback 为 0 天 | 测试覆盖;UI 显示"距今 0 天",不崩溃 |
| `loadLastCompleted` 与 `subscribeRefreshTick` 的 `loadPage` 在 1s 内多次触发 | token 守卫 + 每次 `clearLastCompleted` 自增 `lastCompletedToken` |

---

## 14. 后续可优化(不阻塞本次)

- section header 副标题加 `chevron_right` 闪烁动效,提示可点击
- 多次访问 section 时加 transition 动画(从顶部 16vp 空白渐入)
- 上次评估的 4 维度与今日 EmptyState 的"立即生成"按钮放并排,对比"上次 vs 今日"
- section 支持折叠/展开(默认展开,长屏用户可折叠节省滚动)

---

**前置文档:** `docs/superpowers/specs/2026-06-17-daily-evaluation-page-design.md` (v1 评估页)
**相关 spec:** `.claude/rules/teaching-architecture.md` §7.5 评估老师
