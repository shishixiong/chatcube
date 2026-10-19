# 星星礼物商城（星星换礼物）设计文档

**日期：** 2026-10-19
**状态：** 设计定稿（待实施）
**参考原型：** `docs/star_to_gift.html`（静态结构稿；其引用的 styles.css / app.js 不在仓库内，交互逻辑以本文档为准）
**前置文档：** `.claude/rules/teaching-architecture.md`（§6 星星奖励系统）、`docs/brand-spec.md`（儿童端视觉契约）

---

## 1. 背景与目标

儿童端已有星星奖励系统（`star_events` 流水 + `getAllTimeStarTotal()` 累计总额），但星星只有"挣"没有"花"。本功能增加**星星礼物商城**：孩子用累计星星兑换礼物，生成领取记录与领取码，家长线下兑现并核销，形成"学习 → 星星 → 现实奖励"闭环。

## 2. 产品决策记录（2026-10-19 与用户确认）

| # | 决策点 | 结论 |
|---|--------|------|
| 1 | 兑换履约模型 | **沿用领取码模式**：兑换即时扣星 → 生成领取记录（含领取码）→ 家长线下兑现 |
| 2 | 礼物目录来源 | **内置目录 + 家长自定义**：内置约 12 个礼物开箱可用，家长可添加/编辑/删除自定义礼物 |
| 3 | 核销方式 | **家长验证后核销**：孩子端只能看状态；「已领取」需过家长算术门后标记 |
| 4 | 页面范围 | **商城 + 我的兑换两个新页面**；星星明细复用现有 KidsStarDetailSheet，不建明细页 |
| 5 | 商城入口 | **问候行星星药丸即入口**（药丸由纯展示改为可点）；主屏不加新卡/横滑栏 |
| 6 | 礼物管理入口 | **成人壳设置里新增「礼物管理」页**（学习分组内） |

## 3. 范围

**v1 做**：礼物目录（内置 + 自定义 CRUD）、兑换（扣星 + 领取码 + 庆祝）、兑换记录（含家长门核销）、商城/记录/管理三页面、主屏药丸入口。

**v1 不做（future）**：取消兑换/退款、礼物库存数量限制（原型"礼物数量有限"提示仅作文案）、自定义礼物图标上传（图标固定由分类决定）、WebDAV/导入导出纳入两张新表、兑换后星星在 KidsStarDetailSheet 中展示负数流水。

## 4. 数据层设计

### 4.1 `gifts` 表（礼物目录，内置 + 自定义统一存储）

镜像 `ensureKidsSubjectAssistants` 的启动幂等种子模式：

```sql
CREATE TABLE IF NOT EXISTS gifts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  category TEXT NOT NULL,        -- 'building' | 'plush' | 'vehicle' | 'stationery' | 'other'
  price_stars INTEGER NOT NULL,  -- ≥ 1
  is_builtin INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
)
```

- **内置礼物**：`id = 'gift_builtin_XXX'`，由 `DatabaseService.ensureBuiltinGifts()`（createTables 流程内、紧随 `ensureKidsSubjectAssistants()` 之后调用）幂等补种——`INSERT OR IGNORE`，用户升级不重复插入、不覆盖。
- **内置礼物对家长只读**（不可编辑/删除，管理页置灰），语义对齐 5 个内置助手的注册表锁定。
- **自定义礼物**：`id = 'gift_custom_<uuid>'`，全字段可编辑、可删除。

**内置目录（12 个，价格梯度 20–300，可在实施时微调文案）**：

| 分类 | 礼物 | 星价 |
|------|------|------|
| 拼搭 building | 迷你积木车 60 / 小颗粒积木盒 150 | 60 / 150 |
| 玩偶 plush | 卡通钥匙扣 40 / 毛绒小熊 120 | 40 / 120 |
| 玩具车 vehicle | 回力小赛车 50 / 遥控越野车 300 | 50 / 300 |
| 文具 stationery | 贴纸一册 30 / 漂亮笔记本 60 / 彩铅套装 100 | 30 / 60 / 100 |
| 其他 other | 冰淇淋一支 30 / 绘本一本 80 / 周末公园野餐 200 | 30 / 80 / 200 |

### 4.2 `gift_redemptions` 表（兑换流水）

```sql
CREATE TABLE IF NOT EXISTS gift_redemptions (
  id TEXT PRIMARY KEY,             -- 'redeem_<uuid>'
  gift_id TEXT NOT NULL,
  gift_name TEXT NOT NULL,         -- 快照：礼物日后被改/删不影响历史
  category TEXT NOT NULL,          -- 快照
  price_stars INTEGER NOT NULL,    -- 快照
  redeem_code TEXT NOT NULL,       -- 6 位领取码
  status TEXT NOT NULL DEFAULT 'pending',  -- 'pending' | 'picked'
  created_at INTEGER NOT NULL,
  picked_at INTEGER NOT NULL DEFAULT 0
)
```

加索引 `idx_gift_redemptions_created_at (created_at)`（记录页按时间倒序）。

**快照字段是硬性要求**：记录页与领取码展示必须永远还原兑换那一刻的礼物信息，`gifts` 行被编辑或删除后历史不得变形。

### 4.3 余额模型（关键架构取舍）

```
可用余额 = getAllTimeStarTotal() − SUM(gift_redemptions.price_stars)
```

**兑换不写入 `star_events`**（不加 `gift_redeem` 负数星事件）。理由：

1. `models/StarEventModels.ets` 的 10 处联合漂移点是已知"编译过、运行时静默错"的高危面（MEMORY.md / teaching-architecture §6）；
2. `StarRewardService.aggregateEvents` 只累计 `stars > 0`，负数事件会被静默忽略，改它牵连今日汇总/学科计数全链路；
3. 独立表让"挣"与"花"两条流水天然解耦，商城统计（累计获得/累计兑换/件数）直接可查。

 KidsHomeView 药丸与商城 hero 的余额改走新方法 `StarRewardService.getStarBalance()`；现有 `getAllTimeStarTotal()` 语义不变（仍是"累计获得"），商城统计条继续用它。

### 4.4 新服务 `services/GiftShopService.ets`（单例，镜像 StarRewardService 模式）

```
getGifts(): Promise<GiftItem[]>                       // gifts 表全量（enabled 过滤在 UI 层做，管理页需要看到下架项）
addCustomGift(name, category, price): Promise<boolean>
updateCustomGift(gift: GiftItem): Promise<boolean>    // is_builtin 行拒绝
deleteCustomGift(id: string): Promise<boolean>        // is_builtin 行拒绝
getStarBalance(): Promise<number>                     // 委托 StarRewardService.getAllTimeStarTotal − getRedeemedStarsTotal
getShopStats(): Promise<GiftShopStats>                // { earnedTotal, redeemedTotal, redeemCount }
redeem(giftId): Promise<GiftRedeemResult>             // 见下
getRedemptions(): Promise<GiftRedemptionRow[]>        // created_at 倒序
markRedemptionPicked(id): Promise<boolean>
```

**`redeem()` 流程**（唯一写路径，含余额防超兑）：

1. 读礼物行（不存在/enabled=0 → `{ success: false, reason: 'gift_unavailable' }`）
2. `getStarBalance()` < `price_stars` → `{ success: false, reason: 'insufficient', shortfall }`
3. 生成领取码（`utils/RedeemCodeUtils.generateRedeemCode()`，字符集去掉 `0O1IL` 的 6 位大写字母数字；与现存 `pending` 记录碰撞则重生成，至多 3 次）
4. INSERT `gift_redemptions`（快照 name/category/price）→ 失败 `{ success: false, reason: 'db_error' }`
5. 成功返回 `{ success: true, redemption }`

余额检查与写入之间无事务（单设备单用户场景，竞态窗口可忽略；超兑最多 1 次且视觉上立即暴露）。UI 侧在确认 sheet 打开时也做一次余额预检，双保险。

### 4.5 模型 `models/GiftModels.ets`

```
GiftCategory 联合: 'building' | 'plush' | 'vehicle' | 'stationery' | 'other'
GiftCategoryMeta: { label, iconPath, colorToken }  — 5 分类固定元数据
GiftItem { id, name, category, priceStars, isBuiltin, enabled, sortOrder }
GiftRedemptionRow { id, giftId, giftName, category, priceStars, redeemCode, status, createdAt, pickedAt }
GiftRedeemResult / GiftShopStats
BUILTIN_GIFTS 常量（§4.1 目录，含 sortOrder）
```

## 5. 儿童端页面设计

两页均为 NavDestination，注册进 `router_map.json`，由 `Index.KidsRoot` 的 `chatTabNavStack` 承载（与 ChatPage 同栈）。**恒定 Kids 暖色绘本皮肤**（KidsBrandTokens 字面色值，不随深色模式切换）；图标一律 SVG（`resources/rawfile/kids/`），无 emoji；文字色用现有令牌，分类色新增 5 个淡底令牌放 `KidsBrandTokens.ets`。

### 5.1 新增 SVG 图标（5 个，monoline、baked-in 色，对齐现有 8 图标规格）

`kids/gift_blocks.svg`（拼搭）、`kids/gift_plush.svg`（玩偶）、`kids/gift_vehicle.svg`（玩具车）、`kids/gift_stationery.svg`（文具）、`kids/gift_other.svg`（其他/礼盒）。复用现有 `star.svg` / `chevron.svg` / `close.svg` / `lock.svg`。

### 5.2 `pages/GiftShopPage.ets`（星星商城）

```
导航栏（返回 ‹ + 标题「星星商城」+ 右上「我的兑换」入口含 pending 数徽标）
余额 hero（KIDS_ACCENT 渐变卡）: 「我的星星」+ 大数字余额 + 「可换 N 件」（N = enabled 且 price_stars ≤ 余额 的礼物数）
统计条: 累计获得 | 累计兑换 | 兑换件数
分类 chips 横滑: 全部 / 拼搭 / 玩偶 / 玩具车 / 文具 / 其他
礼物 2 列网格: 分类色淡底图标块 + 名称 + 星价（star.svg + 数字）
  - 余额不足: 卡片置灰 + 「还差 N 颗」
  - 空分类: 「这个分类暂时没有礼物」空态
页脚文案: 「和爸爸妈妈商量好，兑换后把领取码给他们看」
```

**兑换确认 sheet**（bindSheet，挂独立空节点，对齐 KidsHomeView 的多 bindSheet 宿主经验）：礼物信息 + 余额/价差核对 + 「用 N 颗星星兑换」主按钮。确认 → `redeem()` → sheet 切成功态（礼盒图标 + 领取码大字 + 「去查看我的兑换」）→ 关 sheet 后刷新余额/网格。失败（insufficient）→ sheet 内提示"星星还差 N 颗，再攒一攒"。

### 5.3 `pages/GiftRecordsPage.ets`（我的兑换）

```
导航栏（返回 ‹ + 标题「我的兑换」）
记录列表（倒序）:
  礼物快照（分类图标 + 名称）+ 兑换时间 + 星价
  领取码大字展示（等宽感加字距，方便家长读）
  状态药丸: 待领取（KIDS_STAR 金）/ 已领取（绿）
  pending 记录行尾「家长核销」按钮
空态: 「还没有兑换过礼物」+ 「去逛星星商城」CTA
```

**家长核销**：点「家长核销」→ bindSheet 弹 `ParentalGateSheet` → 答对 → `markRedemptionPicked(id)` → 行内状态翻转为已领取。孩子答错只会换题，无副作用。

`ParentalGateSheet` 加 `@Param gateOnly: boolean = false`：gateOnly 模式下答对直接 `onPassed()`（跳过 summary 概览阶段，不退出儿童模式）；默认 false 保持现有行为不变。

## 6. 家长端：`pages/GiftManagePage.ets`（礼物管理）

- 注册：`SettingsRouteName.GIFT_MANAGE = 'GiftManagePage'` + `router_map.json` + `IndexSettingsPanel.buildGroups()` 学习分组（learningItems）末尾新增一行（`sys.symbol.gift` 图标；若该 symbol 不存在则选用存在的近似符号，实施时验证）+ `app.string` 资源（title/desc）+ `Index.ets` 的 `onOpenGiftManage` → `settingsNavPathStack.pushPath`。
- 内容（成人壳常规皮肤，跟随主题）：
  - 内置礼物只读列表（置灰编辑入口或无编辑入口，标注「内置」）
  - 自定义礼物列表 + 「添加礼物」按钮 → 行内表单（名称输入 + 分类选择 + 星价数字输入）
  - 编辑/删除仅对 `gift_custom_*` 生效；删除无历史引用问题（记录页全靠快照）

## 7. 主屏改动（KidsHomeView + Index）

| 触点 | 改动 |
|------|------|
| `components/kids/KidsHomeView.ets` | ① `totalStars` 改由 `getStarBalance()` 加载（药丸语义从"累计获得"变为"可用余额"，accessibilityText 同步改）② 星星药丸加 `.onClick` + 按压反馈 → 新 `@Event onOpenGiftShop` |
| `pages/Index.ets` `KidsRoot()` | 接线 `onOpenGiftShop: () => this.chatTabNavStack.pushPath({ name: 'GiftShopPage' })` |
| 余额刷新 | 复用现有机制：从商城返回 navBar 时 Index 已递增 `kidsStarRefreshTick`（Index.ets:923）→ KidsHomeView.loadAll() 重拉余额，无需新管道 |

## 8. 导航与路由注册

```json
{ "name": "GiftShopPage",    "pageSourceFile": "src/main/ets/pages/GiftShopPage.ets",    "buildFunction": "GiftShopPageBuilder" },
{ "name": "GiftRecordsPage", "pageSourceFile": "src/main/ets/pages/GiftRecordsPage.ets", "buildFunction": "GiftRecordsPageBuilder" },
{ "name": "GiftManagePage",  "pageSourceFile": "src/main/ets/pages/GiftManagePage.ets",  "buildFunction": "GiftManagePageBuilder" }
```

商城 ↔ 兑换记录之间用 `pushPath` 同栈跳转；管理页走 `settingsNavPathStack`。三个页面 Builder 均需包 `NavDestination`（MEMORY.md：裸 buildFunction 渲染空白）。

## 9. 测试策略

按项目惯例抽纯函数进 `utils/` 并补 hypium 用例（`entry/src/ohosTest/`，DevEco Studio 内运行）：

| 纯函数 | 用例 |
|--------|------|
| `RedeemCodeUtils.generateRedeemCode` / `isValidRedeemCode` | 长度 6、字符集不含 0O1IL、非法字符拒绝 |
| `GiftModels` 内余额/统计聚合辅助（如 `computeBalance(earned, redeemed)`、`affordance(balance, price)` → 可换/还差 N） | 边界：0 余额、刚好等于、超出 |
| `GiftShopService.redeem` 的可测前置判定抽出（`canRedeem(balance, gift)`） | 余额不足 / 礼物下架 / 正常 |

组件层不写 ArkUI 测试（项目无基建）。

## 10. 触点文件清单

| 类型 | 路径 |
|------|------|
| 新增模型 | `models/GiftModels.ets` |
| 新增服务 | `services/GiftShopService.ets` |
| 新增工具 | `utils/RedeemCodeUtils.ets` |
| 新增页面 | `pages/GiftShopPage.ets` / `pages/GiftRecordsPage.ets` / `pages/GiftManagePage.ets` |
| 新增图标 | `resources/rawfile/kids/gift_*.svg` ×5 |
| 修改 DB | `services/DatabaseService.ets`（TableNames ×2、createTables ×2、ensureBuiltinGifts、gift/redemption CRUD、`getRedeemedStarsTotal`） |
| 修改星星服务 | `services/StarRewardService.ets`（新增 `getStarBalance`，不改现有方法） |
| 修改组件 | `components/kids/KidsHomeView.ets`（药丸点击 + 余额口径）、`components/kids/ParentalGateSheet.ets`（gateOnly 参数）、`components/kids/KidsBrandTokens.ets`（分类色令牌） |
| 修改导航 | `resources/base/profile/router_map.json`（+3）、`config/SettingsRouteName.ets`（+1）、`pages/Index.ets`（KidsRoot 接线 + GiftManage 路由）、`components/index/IndexSettingsPanel.ets`（菜单行）、`resources/base/element/string.json`（资源） |

**注意**：本功能不触碰 `models/StarEventModels.ets`、`config/BuiltinTools.ets`、`ToolExecutionService.ets`——不新增 AI 工具，不进 10 处漂移点。

## 11. 实施注意（ArkTS 踩坑对齐）

- ForEach 回调体内不能 `const` 声明（10905209）；内联对象字面量需显式返回类型（10605038）；不允许解构（10605074）
- 同节点链多 bindSheet 需各挂独立空节点宿主（KidsHomeView 既有注释经验）
- `sys.symbol.*` 非 iOS SF Symbols，`gift` 等名字存在性需在 DevEco 中验证
- SQL 拼接走 TableNames 常量 + `relationalStore.ValuesBucket`（对齐 insertStarEvent 写法）

## 12. 未来扩展（不阻塞 v1）

兑换退款（家长门 + 反向流水）、礼物库存与"库存不足"状态、兑换纳入 WebDAV 备份/导入导出、KidsStarDetailSheet 中展示兑换流水、AI 老师（小星老师）感知余额并口头激励（`get_time_info` 式只读工具 `get_star_balance`）、商城页通知家长"有新兑换"的本地通知。
