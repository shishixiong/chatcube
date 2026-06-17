# 每日评估查看页 — 设计规格

**日期：** 2026-06-17
**状态：** 设计已确认，待实施
**范围：** 在"学习中心"分组加第 4 个入口，新增 `LearningDailyEvaluationPage` 展示评估老师每日产出的 4 维度教学风格调整 + 关联的本周趋势
**前置：** 评估老师（`EvaluationService`）+ `TeachingStyleAdjustmentService` + `teaching_style_adjustments` 表已上线（commit `9d3a1cf` 之前的工作）

---

## 1. Context

评估老师是教学体系的第二层 AI（参考 `.claude/rules/teaching-architecture.md` §7.5 类似位置），每日 21:00 由 WorkScheduler 触发（降级路径 21:00~21:30 setInterval），输入本周 4 指标趋势 + 今日 sessions 摘要 + 孩子画像，输出 4 维度教学风格调整（`difficultyTendency` / `feedbackTone` / `weakStrongBalance` / `learningPace`）并同步触发备课。

**当前缺口**：

- 数据**已写入** `teaching_style_adjustments` 表（14 天滚动），家长**无法查看**
- 家长看不到今晚 21:00 评估老师给的"难度偏简单 / 温柔鼓励 / 弱项强化 / 适中"具体含义
- 家长看不到本周孩子的 4 指标趋势（技能速度 / 反复出错 / 兴趣主题 / 注意力）
- 没有"历史评估"浏览入口

**用户已确认的 4 个关键决策**：

- 内容范围：**只显示现有 4 维度**（不扩展评估老师加 LLM 长文报告）
- 日期范围：**默认今天 + 顶部日期选择器支持过去 14 天**（不提供"未来日期"或"超过 14 天"）
- 无评估态：**完整状态机**（pending / running / done / failed）+ 轮询 + 失败重试
- 入口位置：**"学习中心"分组末位**（与 LearningProfilePage / LearningTomorrowPlanPage / LearningEnglishImagesPage 同级）

---

## 2. 架构总览

```
┌────────────────────────────────────────────────────────────┐
│ IndexSettingsPanel.ets "学习中心"分组 (第 4 项)             │
│   ↓ 路由 LEARNING_DAILY_EVALUATION                          │
│   ↓ openSettingsDestination(routeName)                    │
├────────────────────────────────────────────────────────────┤
│ LearningDailyEvaluationPage                                 │
│   ├── DetailPaneHeader (← 每日评估 + 日期选择条)            │
│   ├── SummaryCard (date + 相对生成时间 + session 数 + 置信度)│
│   ├── DimensionsBlock (4 维度卡片)                          │
│   │     ├── DimensionRow × 4                                │
│   │     │   (label + enum 中文 label + rationale 多行)     │
│   └── WeeklyTrendBlock (4 指标进度条)                       │
│         └── TrendRow × 4                                    │
│             (标题 + 5 档进度条 + 子项 chip 列表)            │
│                                                              │
│ 状态分支:                                                    │
│   pending  → PendingState (spinner)                        │
│   running  → RunningState (spinner)                        │
│   failed   → FailedState (错误 sheet + 重试)               │
│   null     → EmptyState (3 种子态按时间窗)                 │
├────────────────────────────────────────────────────────────┤
│ 数据层 (无新服务)                                            │
│   TeachingStyleAdjustmentService.getAdjustmentForDate(ymd) │
│   WeeklyTrendService.getTrendByWeekStart(ymd) ← 新增 helper │
│   EvaluationService.triggerEvaluationForToday(force, src)  │
│   DatabaseService.getCurrentTeachingStyleAdjustment(...)   │
├────────────────────────────────────────────────────────────┤
│ 刷新机制 (双保险)                                            │
│   setInterval(2000) 轮询 pending/running                  │
│   AppStorage 订阅 TEACHING_STYLE_ADJUSTMENT_REFRESH_TICK   │
└────────────────────────────────────────────────────────────┘
```

---

## 3. 页面布局

```
┌─────────────────────────────────────────┐
│  ← 每日评估              [日期: 今天 ▼]  │  ← DetailPaneHeader (顶部)
├─────────────────────────────────────────┤
│                                          │
│  ┌─ 评估摘要卡 ──────────────────────┐  │  ← SummaryCard
│  │  📅 2026-06-17 (周二)              │  │
│  │  ⏱ 生成于 3 分钟前 · 来自 5 次对话  │  │
│  │  置信度 0.85 · 模型 gpt-4o [done]   │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌─ 教学风格调整 (4 维度) ────────────┐  │  ← DimensionsBlock
│  │  难度倾向   [偏简单]               │  │
│  │  "孩子今天在减法上卡了 3 次..."     │  │
│  │  ─────────────────────────────     │  │
│  │  反馈语气   [温柔鼓励]             │  │
│  │  "孩子有点累, 不要 push 太狠..."   │  │
│  │  ─────────────────────────────     │  │
│  │  强弱侧重   [弱项强化]             │  │
│  │  "形状识别需要 2-3 题再练..."     │  │
│  │  ─────────────────────────────     │  │
│  │  学习节奏   [适中]                 │  │
│  │  "保持 6-7 题为宜..."             │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌─ 本周趋势 (4 指标) ────────────────┐  │  ← WeeklyTrendBlock
│  │  技能速度   ▓▓▓░░ 上升             │  │
│  │  反复出错   ▓░░░░ 改善             │  │
│  │  兴趣主题   [数学/英文]            │  │
│  │  注意力     ▓▓▓▓░ 较好             │  │
│  └────────────────────────────────────┘  │
│                                          │
└─────────────────────────────────────────┘
```

### 3.1 DetailPaneHeader + 日期选择条

- 左：返回按钮（`onBack` → `pathStack.pop`）
- 中：标题 `每日评估`
- 右：`日期选择条`（`DatePickerBar` @Builder）
  - `← 2026-06-17 (周二) →` 横排
  - 左箭头：`-1d` 切换（`canGoBack: boolean` 控制可点性）
  - 右箭头：`+1d` 切换（`canGoForward: boolean` 控制可点性）
  - 中间文字：可点击打开日期弹窗（选过去 14 天任意一天）
  - "今天" 按钮：`selectedDate !== today` 时显示，点击 → 回到今天

### 3.2 SummaryCard

- 日期 + 星期（`formatLocalYMD` + `getDayOfWeekLabel`）
- 相对生成时间（`formatRelativeTime(adjustment.createdAt)`）
- 来源 session 数（`sourceSessionCount`）
- 置信度（`confidence`，0-1 保留 2 位小数）
- 模型名（`evaluatorModelName`，无则显示 "—"）
- 状态 pill（右上角）：`done` (绿) / `pending` (橙) / `running` (蓝) / `failed` (红)

### 3.3 DimensionsBlock

- Section title：`教学风格调整`
- 4 个 `DimensionRow`，按 `difficultyTendency` / `feedbackTone` / `weakStrongBalance` / `learningPace` 固定顺序
- 每个 `DimensionRow`：
  - 标题：维度中文名（13vp Medium `text_primary`）
  - enum label 胶囊：中文 label（`偏简单` / `current` / `harder` → `偏简单` / `保持` / `偏难` 等）
  - rationale：13vp `text_primary` + lineHeight 20vp + maxLines 4 + ellipsis
  - rationale 为空时 label 旁加灰色小字 `(无解释)`
- 行间 `Divider()` 分割（最后一行不画）

### 3.4 WeeklyTrendBlock

- Section title：`本周趋势`
- 4 个 `TrendRow`：
  - 技能速度：5 档进度条（`topImprovements.length - topRegressions.length` 映射 0-5）
  - 反复出错：5 档进度条（`topStruggling.length` 倒数映射，越多越差）
  - 兴趣主题：chip 列表（`topImprovements` 数组）—— 无 chip 时 "无明显偏好"
  - 注意力：5 档进度条
- 进度条：复用 `SkillLevelDots` 视觉模式，5 个 8vp 圆点 + active/inactive 颜色
- 进度条后跟简评：0→待观察 / 1→偏差 / 2→中等 / 3-4→较好 / 5→优秀

### 3.5 状态分支

#### 3.5.1 PendingState / RunningState

- 居中 spinner（`LoadingProgress` 组件 32vp）
- 标题：`评估排队中` / `评估生成中`
- 描述：`评估老师稍后开始处理` / `正在分析本周学习数据`
- 轮询持续

#### 3.5.2 FailedState

- 顶部大 icon（`exclamationmark_triangle_fill` 48vp `status_error`）
- 标题：`评估生成失败`
- 错误详情（`errorMessage` 全文，多行）
- "重试" 按钮（`isTriggering` 守卫）+ "关闭" 按钮
- 仅当 `selectedDate === today` 时显示"重试"（过去日期的 failed 不可重试）

#### 3.5.3 EmptyState（3 种子态）

| 条件 | 标题 | 描述 | 按钮 |
|------|------|------|------|
| `selectedDate === today` && `now < 21:00` | `今日评估即将生成` | `评估老师每晚 21:00 总结当天学习` | 无 |
| `selectedDate === today` && `now >= 21:00` | `今日评估未生成` | `可能评估服务尚未运行, 可手动触发` | `立即生成` (调 `triggerEvaluationForToday`) |
| `selectedDate !== today` && row 为空 | `该日期暂无评估` | `评估仅保留最近 14 天记录` | 无 |
| `selectedDate` 距今 > 14d | `已超出 14 天保留范围` | `评估数据 14 天滚动, 旧数据已清理` | 无 |

### 3.6 状态 pill 颜色（`status` → 颜色）

| status | 背景 | 文字 | 边框 |
|--------|------|------|------|
| `done` | `withColorAlpha(SUCCESS_GREEN, '0C')` | `status_success` | `withColorAlpha(SUCCESS_GREEN, '28')` |
| `pending` | `withColorAlpha(WARNING_ORANGE, '0C')` | `#FF9F43` | `withColorAlpha(WARNING_ORANGE, '28')` |
| `running` | `withColorAlpha(INFO_BLUE, '0C')` | `#3B82F6` | `withColorAlpha(INFO_BLUE, '28')` |
| `failed` | `withColorAlpha(ERROR_RED, '0C')` | `status_error` | `withColorAlpha(ERROR_RED, '28')` |

---

## 4. 数据契约

### 4.1 已有 API（直接复用）

```typescript
// TeachingStyleAdjustmentService (services/TeachingStyleAdjustmentService.ets:102, 116)
getCurrentAdjustment(asOfYMD: string = '', nowMs: number = Date.now()): Promise<TeachingStyleAdjustment | null>
getAdjustmentForDate(ymd: string): Promise<TeachingStyleAdjustment | null>

// DatabaseService (services/DatabaseService.ets:4354)
getCurrentTeachingStyleAdjustment(asOfYMD: string, nowMs: number): Promise<TeachingStyleAdjustmentRow | null>

// EvaluationService (services/EvaluationService.ets:235)
triggerEvaluationForToday(force: boolean = false, source: EvaluatorTriggerSource = 'manual'): Promise<void>
// EvaluatorTriggerSource = 'workScheduler' | 'appStart' | 'manual' | 'intervalCheck'
```

### 4.2 新增 helper（最小改动）

`WeeklyTrendService.getTrendById(id: string): Promise<WeeklyTrend | null>` —— 解析 `wt_YYYYMMDD` → `weekStartYMD` → 调 `getTrendByWeekStart`。约 10 行。

```typescript
// services/WeeklyTrendService.ets (新增方法)
async getTrendById(id: string): Promise<WeeklyTrend | null> {
  if (!id.startsWith('wt_') || id.length !== 11) {
    return null
  }
  const ymd = `${id.substring(3, 7)}-${id.substring(7, 9)}-${id.substring(9, 11)}`
  return await this.getTrendByWeekStart(ymd)
}
```

### 4.3 TeachingStyleAdjustment 字段映射

| 字段 | UI 渲染 | 备注 |
|------|---------|------|
| `effectiveDate` | SummaryCard 日期 | `YYYY-MM-DD` |
| `createdAt` | SummaryCard 相对时间 | epoch ms |
| `sourceSessionCount` | SummaryCard session 数 | 数字 |
| `confidence` | SummaryCard 置信度 | 0-1，2 位小数 |
| `evaluatorModelName` | SummaryCard 模型名 | 字符串 |
| `status` | 状态 pill + 状态分支 | `'done'`/`'pending'`/`'running'`/`'failed'` |
| `errorMessage` | FailedState 错误详情 | failed 状态才有值 |
| `difficultyTendency` | DimensionRow 1 enum | 枚举 |
| `feedbackTone` | DimensionRow 2 enum | 枚举 |
| `weakStrongBalance` | DimensionRow 3 enum | 枚举 |
| `learningPace` | DimensionRow 4 enum | 枚举 |
| `difficultyTendencyRationale` | DimensionRow 1 rationale | 字符串 |
| `feedbackToneRationale` | DimensionRow 2 rationale | 字符串 |
| `weakStrongBalanceRationale` | DimensionRow 3 rationale | 字符串 |
| `learningPaceRationale` | DimensionRow 4 rationale | 字符串 |
| `sourceWeeklyTrendId` | WeeklyTrendBlock 查询键 | `wt_YYYYMMDD` 格式 |

### 4.4 WeeklyTrend 字段映射

| 字段 | UI 渲染 | 备注 |
|------|---------|------|
| `topImprovements` | 技能速度 + 兴趣主题 | 字符串数组 |
| `topRegressions` | 技能速度（反向） | 字符串数组 |
| `topStruggling` | 反复出错 | 字符串数组 |
| `attentionLevel` | 注意力 | 枚举 0-4 |
| `weekStartYMD` | WeeklyTrendBlock 标题旁日期 | `YYYY-MM-DD` |

---

## 5. 关键组件 & 文件

### 5.1 新增文件

| 路径 | 行数估算 | 角色 |
|------|----------|------|
| `pages/LearningDailyEvaluationPage.ets` | ~750 | 主页面 |
| `utils/TeachingStyleAdjustmentUtils.ets` | ~80 | 维度 enum → 中文 label/icon 映射 |
| `utils/DateRangeUtils.ets` | ~40 | 14 天边界判断 |

### 5.2 修改文件

| 路径 | 改动 |
|------|------|
| `services/WeeklyTrendService.ets` | + `getTrendById(id)` 1 个方法 |
| `config/SettingsRouteName.ets:18-20` | + `LEARNING_DAILY_EVALUATION = 'LearningDailyEvaluationPage'` |
| `resources/base/profile/router_map.json:104-117` | + 注册 `LearningDailyEvaluationPage` → `LearningDailyEvaluationPageBuilder` |
| `components/index/IndexSettingsPanel.ets:79-107` | "学习中心"分组加第 4 项 |
| `pages/Index.ets:4851-4905` | + `onOpenLearningDailyEvaluation: () => this.openSettingsDestination(SettingsRouteName.LEARNING_DAILY_EVALUATION)` |
| `resources/base/element/string.json` | + 13 个 string key（见 §6） |

### 5.3 复用现有

- `HdsNavigation` + `SettingsCompactTitleBarContent`（`components/settings/SettingsCompactPageHeader.ets`）
- `SettingsPagePresentationMode.DETAIL_PANE` 检测
- `getSettingsPageContentMaxWidth` 宽度
- `formatRelativeTime`（`utils/TimeFormatUtils.ets`）
- `formatLocalYMD` + `getDayOfWeekLabel`（已有 utils）
- `buildPointLightBorderEffect`（`utils/HdsVisualEffectUtil.ets`）
- `getAppUiState().themePrimary/PrimaryLight/Surface/Background/TextPrimary/TextSecondary/TextTertiary/Divider`
- `withColorAlpha`（`utils/ColorAlphaUtils.ets`）
- 视觉规范：与 `LearningProfilePage.ets` 的卡片外壳一致（`themeSurface` + 1px `divider` + 16vp radius + `buildPointLightBorderEffect`）

### 5.4 Page 内 @Builder 列表

1. `DetailPaneHeader` (40 行) — 顶部标题 + 日期选择条
2. `DatePickerBar` (40 行) — `← 日期 →` 横排 + 今天按钮
3. `SummaryCard` (50 行) — 日期 + 相对时间 + session 数 + 置信度 + 模型名 + 状态 pill
4. `DimensionsBlock` (60 行) — section title + 4 个 DimensionRow
5. `DimensionRow` (50 行) — 单维度行
6. `WeeklyTrendBlock` (60 行) — section title + 4 个 TrendRow
7. `TrendRow` (60 行) — 单指标行
8. `ProgressDots` (30 行) — 5 档进度条（视觉参考 `SkillLevelDots` 但线性展示）
9. `PendingState` (30 行)
10. `RunningState` (30 行)
11. `FailedState` (50 行) — 失败主区域
12. `ErrorDetailSheet` (40 行) — 半屏错误详情 sheet
13. `EmptyState` (50 行) — 4 种子态分支

### 5.5 关键状态字段

```typescript
@Local adjustment: TeachingStyleAdjustment | null = null
@Local trend: WeeklyTrend | null = null
@Local selectedDate: string = ''  // YYYY-MM-DD
@Local isTriggering: boolean = false
@Local isErrorSheetVisible: boolean = false
@Local isLoading: boolean = true

private loadToken: number = 0
private pollTimerId: number = -1
private pollCount: number = 0
private readonly POLL_INTERVAL_MS: number = 2000
private readonly POLL_MAX_COUNT: number = 60  // 2min 上限
```

### 5.6 关键方法

```typescript
aboutToAppear(): void {
  this.selectedDate = todayYMD()
  this.loadPage()
  this.subscribeRefreshTick()
}

private async loadPage(): Promise<void> {
  const token = ++this.loadToken
  this.isLoading = true
  try {
    const adj = await getTeachingStyleAdjustmentService().getAdjustmentForDate(this.selectedDate)
    if (token !== this.loadToken) return  // 切日期后旧请求丢弃
    this.adjustment = adj
    if (adj !== null && adj.sourceWeeklyTrendId !== '') {
      this.trend = await getWeeklyTrendService().getTrendById(adj.sourceWeeklyTrendId)
    } else {
      this.trend = null
    }
  } catch (e) {
    console.error(TAG, `loadPage failed: ${(e as BusinessError).message ?? String(e)}`)
  } finally {
    if (token === this.loadToken) this.isLoading = false
  }
  this.maybeStartPolling()
}

private maybeStartPolling(): void {
  if (this.adjustment !== null &&
      this.adjustment.status !== 'pending' &&
      this.adjustment.status !== 'running') {
    this.stopPolling()
    return
  }
  this.startPolling()
}

private startPolling(): void {
  if (this.pollTimerId !== -1) return
  this.pollCount = 0
  this.pollTimerId = setInterval((): void => {
    this.pollCount++
    if (this.pollCount > this.POLL_MAX_COUNT) {
      this.stopPolling()
      return
    }
    this.loadPage()
  }, this.POLL_INTERVAL_MS)
}

private stopPolling(): void {
  if (this.pollTimerId !== -1) {
    clearInterval(this.pollTimerId)
    this.pollTimerId = -1
  }
}

private async handleTriggerEvaluation(): Promise<void> {
  if (this.isTriggering || this.selectedDate !== todayYMD()) return
  this.isTriggering = true
  try {
    await getEvaluationService().triggerEvaluationForToday(true, 'manual')
  } catch (e) {
    console.error(TAG, `trigger failed: ${(e as BusinessError).message ?? String(e)}`)
    this.isErrorSheetVisible = true
  } finally {
    this.isTriggering = false
  }
}

aboutToDisappear(): void {
  this.stopPolling()
}
```

---

## 6. 字符串资源（13 个新增 key）

```
learning_daily_evaluation_title        = "每日评估"
learning_daily_evaluation_desc         = "评估老师每晚 21:00 总结当天学习"
learning_daily_evaluation_summary      = "评估摘要"
learning_daily_evaluation_dimensions   = "教学风格调整"
learning_daily_evaluation_trend        = "本周趋势"

learning_daily_evaluation_dim_difficulty = "难度倾向"
learning_daily_evaluation_dim_feedback   = "反馈语气"
learning_daily_evaluation_dim_balance    = "强弱侧重"
learning_daily_evaluation_dim_pace       = "学习节奏"

learning_daily_evaluation_pending_title = "评估排队中"
learning_daily_evaluation_pending_desc  = "评估老师稍后开始处理"
learning_daily_evaluation_running_title = "评估生成中"
learning_daily_evaluation_running_desc  = "正在分析本周学习数据"
learning_daily_evaluation_failed_title  = "评估生成失败"
learning_daily_evaluation_empty_today_future_title = "今日评估即将生成"
learning_daily_evaluation_empty_today_future_desc  = "评估老师每晚 21:00 总结当天学习"
learning_daily_evaluation_empty_today_past_title   = "今日评估未生成"
learning_daily_evaluation_empty_today_past_desc    = "可能评估服务尚未运行, 可手动触发"
learning_daily_evaluation_empty_past_title  = "该日期暂无评估"
learning_daily_evaluation_empty_past_desc   = "评估仅保留最近 14 天记录"
learning_daily_evaluation_empty_oob_title   = "已超出 14 天保留范围"
learning_daily_evaluation_empty_oob_desc    = "评估数据 14 天滚动, 旧数据已清理"

learning_daily_evaluation_trigger_now  = "立即生成"
learning_daily_evaluation_retry        = "重试"
learning_daily_evaluation_close        = "关闭"
learning_daily_evaluation_today_short  = "今天"

learning_daily_evaluation_status_done    = "已完成"
learning_daily_evaluation_status_pending = "排队中"
learning_daily_evaluation_status_running = "生成中"
learning_daily_evaluation_status_failed  = "失败"
learning_daily_evaluation_rationale_missing = "（无解释）"
```

**总计 32 个 key**（比原估算 7 个多 25 个，因为 EmptyState 子态/状态文案/pill 文字都要独立 key 才能本地化）。

---

## 7. utils 函数

### 7.1 `utils/TeachingStyleAdjustmentUtils.ets`

```typescript
export type TeachingDimension = 'difficultyTendency' | 'feedbackTone' | 'weakStrongBalance' | 'learningPace'

interface DimensionValueMeta {
  label: string
  icon: Resource
  color: string  // themePrimaryLight alpha 即可
}

const DIFFICULTY_META: Record<string, DimensionValueMeta> = {
  easier: { label: '偏简单', icon: $r('sys.symbol.minus'), color: '18' },
  current: { label: '保持', icon: $r('sys.symbol.equal'), color: '18' },
  harder: { label: '偏难', icon: $r('sys.symbol.plus'), color: '18' }
}
// ... feedbackTone / weakStrongBalance / learningPace 各 3 个值

export function getDimensionLabel(dimension: TeachingDimension, value: string): string
export function getDimensionIcon(dimension: TeachingDimension, value: string): Resource
export function computeTrendProgress(improvements: number, regressions: number): number  // 0-5
```

### 7.2 `utils/DateRangeUtils.ets`

```typescript
const MAX_HISTORY_DAYS: number = 14

export function isWithinHistoryRange(ymd: string, nowMs: number = Date.now()): boolean
export function canGoBack(selectedYMD: string, nowMs: number = Date.now()): boolean  // 距今 < 14d
export function canGoForward(selectedYMD: string, nowMs: number = Date.now()): boolean  // 不晚于今天
export function todayYMD(nowMs: number = Date.now()): string
export function shiftYMD(ymd: string, days: number): string
```

---

## 8. 状态机 & 数据流

### 8.1 状态机

| `adjustment.status` | UI 渲染 | 轮询 | 重试按钮 |
|---------------------|---------|------|----------|
| `null` (row 不存在) | EmptyState 4 种子态 | ✗（无 row 无可轮询，依赖 AppStorage 订阅） | `selectedDate === today && now >= 21:00` 时显示 |
| `pending` | PendingState | ✓ | ✗（避免覆盖入队状态） |
| `running` | RunningState | ✓ | ✗ |
| `done` | SummaryCard + 2 个 Block | ✗ | ✗ |
| `failed` | FailedState | ✗ | 仅 `selectedDate === today` 时显示 |

### 8.2 轮询守卫

- `pollCount > 60` 自动停止（2min 上限）
- `status` 变为 `done` / `failed` 自动停止
- `aboutToDisappear` 必停（无内存泄漏）
- 切日期时新 loadPage 内部重置 pollCount

### 8.3 刷新机制

- **setInterval(2000ms) 轮询** —— 主路径，处理 `pending` → `running` → `done` 状态流转
- **AppStorage 订阅 `TEACHING_STYLE_ADJUSTMENT_REFRESH_TICK`** —— 备路径，评估服务写回时 +1
- 两个机制并存：轮询保底，订阅加速

### 8.4 切日期缓存

- 简单方案：每次切日期重新查 DB（14 天数据量小，不做缓存）
- 不引入 `Map<date, adjustment>` 缓存 —— 过度设计

---

## 9. 错误处理

| 错误 | 处理 |
|------|------|
| DB 读 `getAdjustmentForDate` 异常 | console.error + 视为 `null` → EmptyState 渲染，不显示技术错误 |
| DB 读 `getTrendById` 异常 | 4 维度卡片正常显示，WeeklyTrendBlock 显示降级态 "本周趋势数据已过期" |
| `triggerEvaluationForToday` 异常 | console.error + 弹 FailedState sheet |
| 轮询超时（2min 状态不变） | 停止轮询 + 显示 "生成超时" 提示 + 重试按钮 |
| 切到 15 天前日期 | 箭头禁用 + EmptyState 第四种 "超出 14 天保留范围" |
| 切到未来日期 | 箭头禁用 |
| 重复点重试 | `isTriggering` 守卫 + 按钮 disable + 文字改 "生成中..." |
| rationale 字段为空 | 维度 label 旁加灰色小字 `（无解释）` |
| topImprovements 为空数组 | 进度条全灰 + "无明显偏好" 字样 |
| confidence 字段缺失 | 显示 "—" 而非崩溃 |

---

## 10. 测试

### 10.1 单元测试（hypium + hamock）

| 模块 | 函数 | 断言数 |
|------|------|--------|
| `utils/TeachingStyleAdjustmentUtils.ets` | `getDimensionLabel` | 4 维 × 3 值 = 12 |
| 同上 | `getDimensionIcon` | 4 维 × 3 值 = 12 |
| 同上 | `computeTrendProgress` | 5 个边界 |
| `utils/DateRangeUtils.ets` | `isWithinHistoryRange` | 4 边界 |
| 同上 | `canGoBack` / `canGoForward` | 6 边界 |
| 同上 | `shiftYMD` | 4 边界（跨月/跨年） |
| `services/WeeklyTrendService.getTrendById` | 解析 `wt_20260616` → `2026-06-16` | 4 边界 |

**总计 ~50 个断言**。

### 10.2 手动验证（ArkUI 组件层无基建，按项目惯例）

| 场景 | 期望 |
|------|------|
| T1 首次进入（无数据） | EmptyState "今日评估即将生成" |
| T2 21:00 之后 | EmptyState "今日评估未生成" + "立即生成" 按钮 |
| T3 触发后 pending → running → done | spinner 切换 3 次，最后显示完整内容 |
| T4 失败态 | FailedState + 错误 sheet + 重试按钮 |
| T5 切到昨天 | 显示昨日评估（若有） |
| T6 切到 16 天前 | "超出 14 天保留范围" |
| T7 切回今天 | "今天"按钮隐藏 |
| T8 连续点重试 | `isTriggering` 守卫 + 按钮 disable |
| T9 切日期时旧请求串数据 | loadToken 守卫丢弃 |
| T10 关页面后 timer 泄漏 | aboutToDisappear 清理 |

### 10.3 端到端烟测

| 场景 | 期望 |
|------|------|
| S1 新装 app 当日 21:00 前 | EmptyState "今日评估即将生成"，无"立即生成"按钮 |
| S2 当日 21:30 | 评估老师已跑，status='done'，4 维度 + WeeklyTrend 完整显示 |
| S3 手动点"立即生成" | status: null → pending → running → done |
| S4 模拟 LLM 失败 | status='failed'，错误 sheet 弹出 |
| S5 切到昨天 | 显示昨天的 done 评估 |
| S6 切到 16 天前 | "超出 14 天历史保留范围" |
| S7 回归 LearningProfilePage / LearningTomorrowPlanPage | 行为不变 |

### 10.4 验收清单

- [ ] `assembleHap` 通过（无 ArkTS 严格模式错误）
- [ ] 入口在 IndexSettingsPanel "学习中心"分组末位可点进
- [ ] 顶部 ←/→ 切日期正常，14 天边界/今天边界禁用
- [ ] 默认显示今日；3 种 EmptyState 子态正确
- [ ] 4 维度胶囊 label 显示中文
- [ ] rationale 多行省略号正常
- [ ] WeeklyTrend 4 指标进度条正确
- [ ] 手动触发 → pending → running → done 全程
- [ ] 失败态 → 错误 sheet → 重试
- [ ] 切日期 loadToken 守卫不串数据
- [ ] 关页面后轮询 timer 清理
- [ ] ~50 个单元测试全过
- [ ] LearningProfilePage / LearningTomorrowPlanPage 行为不变

---

## 11. 关键文件清单

### 11.1 新增

| 路径 | 角色 |
|------|------|
| `pages/LearningDailyEvaluationPage.ets` | 主页面 |
| `utils/TeachingStyleAdjustmentUtils.ets` | 维度 enum → 中文 label/icon 映射 + 进度计算 |
| `utils/DateRangeUtils.ets` | 14 天边界判断 + YMD shift |

### 11.2 修改

| 路径 | 改动 |
|------|------|
| `services/WeeklyTrendService.ets` | + `getTrendById(id)` 1 个方法（10 行） |
| `config/SettingsRouteName.ets:18-20` | + `LEARNING_DAILY_EVALUATION` 枚举 |
| `resources/base/profile/router_map.json:104-117` | + 注册 `LearningDailyEvaluationPage` |
| `components/index/IndexSettingsPanel.ets:79-107` | "学习中心"分组加第 4 项（icon `lightbulb_max`） |
| `pages/Index.ets:4851-4905` | + `onOpenLearningDailyEvaluation` handler |
| `resources/base/element/string.json` | + 30 个 string key |

### 11.3 不变

- `services/EvaluationService.ets` — 不变（手动触发用现成 `triggerEvaluationForToday`）
- `services/TeachingStyleAdjustmentService.ets` — 不变（读侧用现成 `getAdjustmentForDate`）
- `services/DatabaseService.ets` — 不变（无新查询）
- `models/TeachingReflectionModels.ets` — 不变（无新字段）
- `entry/src/main/ets/entryworkplannerability/EntryWorkPlannerAbility.ets` — 不变（触发链不动）

---

## 12. 风险 & 缓解

| 风险 | 缓解 |
|------|------|
| `triggerEvaluationForToday` 只接受今天 | spec 明确"过去日期不显示重试按钮" |
| `sourceWeeklyTrendId` 引用 `wt_YYYYMMDD` 但服务无 `getTrendById` | 加 10 行 helper（§4.2） |
| `LearningDailyEvaluationPage` 整页 ~750 行，超出建议 600 行上限 | builder 拆 12 个清晰子块；如果仍然过大，v2 拆 `SummaryCard` / `DimensionsBlock` / `WeeklyTrendBlock` 到独立文件 |
| 轮询 2s 间隔 + 2min 上限不够 | v1 先这样，未来按需加 AppStorage 订阅加速 |
| 字符串资源 30 个一次性加 30 个 key | 不分批，本 PR 一次加完，未来可按子模块优化 |
| 切日期时 `getAdjustmentForDate` 返回 `null` 但之前页面有数据 | loadToken 守卫 + finally 中仅在 token 匹配时清 isLoading |
| 4 维度的 enum label 翻译可能不准确 | spec 用"偏简单/保持/偏难"等口语化翻译；v1 后按用户反馈迭代 |
| 进度条 5 档映射不一定能精确反映趋势强弱 | 简化映射：`Math.min(5, max(0, improvements.length - regressions.length + 2))`；v1 可接受近似 |

---

## 13. 后续可优化（不阻塞本次）

- 4 维度胶囊 label 加交互：点击展开完整 rationale 全文（避免 rationale 长时被截）
- 进度条加动画（进入页面时从 0 涨到目标值）
- 评估历史导出（家长可下载 PDF 给医生看）
- 评估触发时机可视化（"上次评估距今 X 小时" + 进度环）
- 评估老师 prompt 优化：让 LLM 输出 1-2 段自由文本 narrative，UI 端可加 "查看完整分析" 按钮
- 4 维度历史趋势折线图（"近 14 天难度倾向" 时间序列）

---

**前置文档：** `.claude/rules/teaching-architecture.md` §7.5 评估老师
**相关 spec：** `docs/superpowers/specs/2026-06-06-lesson-planning-design.md`（备课老师，对标模式）
