# 星星礼物商城实施计划（Star Gift Shop）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 儿童端星星商城——星星药丸进商城、礼物兑换生成领取码、家长门核销、设置里管理自定义礼物。

**Architecture:** 两张新 SQLite 表（`gifts` 内置+自定义目录 / `gift_redemptions` 兑换快照流水），新单例 `GiftShopService` 封装余额（=累计获得−累计兑换）与兑换写路径；三个 NavDestination 页面（商城/兑换记录/礼物管理）分别挂 chatTabNavStack 与 settingsNavPathStack。兑换**不写** star_events，不触碰 StarEventModels 10 处漂移点。

**Tech Stack:** ArkTS (HarmonyOS API 23 stage 模型) + relationalStore (rdb) + hypium（仅 IDE 可跑）+ KidsBrandTokens 恒定暖色绘本皮肤。

**Spec:** `docs/superpowers/specs/2026-10-19-star-gift-shop-design.md`（随计划一起读）

## Global Constraints

- **不修改** `models/StarEventModels.ets` / `config/BuiltinTools.ets` / `services/ToolExecutionService.ets`（spec §10 红线）。
- ArkTS 严格模式：内联对象字面量必须标注类型（`as Foo` 或显式接口注解，否则 10605038）；**禁止解构**（10605074）；`map/filter/sort` 回调必须写显式返回类型；**ForEach 回调体内不能写 `const` 声明**（10905209）——抽成返回已构造对象的私有方法。
- 同一组件挂多个 bindSheet 时，每个 sheet 必须挂在独立的零尺寸 Column 宿主上（KidsHomeView.ets:291 注释经验）。
- 儿童端页面（GiftShop/GiftRecords）用 `components/kids/KidsBrandTokens.ets` 字面色值，**不用** `$r('app.color.*')`，**不随深色模式切换**；图标一律 SVG（`resources/rawfile/kids/`），**禁 emoji**。
- 家长端管理页用 `getAppUiState()` 主题 getter + `$r('app.string.*')`，跟随成人主题。
- 测试运行限制：`hvigorw test` 不可用（脚手架 mismatch）；hypium 测试**写完编译通过即可**，实际运行在 DevEco Studio 里右键测试文件执行。CLI 阶段的验证一律 = `assembleHap` 干净编译。
- 构建命令：
  ```bash
  DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
    /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
    --mode module -p product=default -p buildMode=debug
  ```
- 提交信息用中文 conventional 前缀（`feat:` / `test:` / `chore:`），每个 Task 一提交。
- 计划相对 spec 的两处偏差（实现以本计划为准）：①spec §5 建议分类色令牌放 KidsBrandTokens.ets，实际放在 `GiftModels.GIFT_CATEGORY_META_MAP.tint`（避免 models 层 import components 层）；②GiftManagePage 用自绘简单标题栏而非 HdsNavigation chrome（新独立页，避免复制重型 chrome 依赖）。

## Review Focus

1. **兑换快照不可变**：礼物被编辑/删除后，已有兑换记录的名称/分类/星价必须仍是兑换那一刻的值——`redeem()` 落库必须写快照字段（Task 4），记录页只读快照字段（Task 9）。人工验证：改/删一个已有兑换记录的礼物，记录页显示不变。
2. **余额防超兑边界**：余额恰好等于价格时可兑、差 1 颗时不可兑且提示"还差 1 颗"——Task 1 纯函数测试钉死（`canAffordGift`/`shortfallFor`/`canRedeem`）。
3. **领取码可读性**：6 位、字符集不含 0/O/1/I/L——Task 2 测试钉死。
4. **内置礼物只读**：家长不能编辑/删除 `is_builtin=1` 的礼物（Task 4 服务层守卫）；`gateOnly` 参数默认 false，不得改变现有家长门"答对进概览"行为（Task 6 人工验证）。
5. **余额刷新链路**：兑换后返回主屏，星星药丸必须显示扣减后余额——依赖 Index.ets:923 既有 `kidsStarRefreshTick` 机制（Task 7 接线后人工验证），不得另开刷新管道。

---

### Task 1: GiftModels 模型 + 纯函数（TDD）

**Files:**
- Create: `entry/src/main/ets/models/GiftModels.ets`
- Test: `entry/src/ohosTest/ets/test/utils/GiftModels.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`（注册测试）

**Interfaces:**
- Produces（后续任务依赖的精确签名）:
  - `type GiftCategory = 'building' | 'plush' | 'vehicle' | 'stationery' | 'other'`
  - `GIFT_CATEGORIES: GiftCategory[]`、`GIFT_CATEGORY_ALL: string`（='all'）
  - `interface GiftItem { id: string; name: string; category: string; priceStars: number; isBuiltin: boolean; enabled: boolean; sortOrder: number }`
  - `interface GiftRedemptionRow { id: string; giftId: string; giftName: string; category: string; priceStars: number; redeemCode: string; status: string; createdAt: number; pickedAt: number }`
  - `GIFT_STATUS_PENDING: string`（'pending'）、`GIFT_STATUS_PICKED: string`（'picked'）
  - `interface GiftShopStats { earnedTotal: number; redeemedTotal: number; redeemCount: number }`
  - `interface GiftRedeemResult { success: boolean; reason: string; shortfall: number; redemption: GiftRedemptionRow | null }`
  - `BUILTIN_GIFTS: BuiltinGiftSpec[]`（12 件）、`builtinGiftId(index: number): string`
  - `getGiftCategoryMeta(category: string): GiftCategoryMeta`
  - 纯函数：`canAffordGift(balance, priceStars): boolean`、`shortfallFor(balance, priceStars): number`、`countAffordableGifts(gifts, balance): number`、`filterGiftsByCategory(gifts, category): GiftItem[]`、`sortGiftsForShop(gifts): GiftItem[]`、`canRedeem(balance, gift): GiftRedeemResult`

- [ ] **Step 1: 写失败测试**

`entry/src/ohosTest/ets/test/utils/GiftModels.test.ets` 全文：

```typescript
import { describe, it, expect } from '@ohos/hypium'
import {
  BUILTIN_GIFTS,
  GiftItem,
  GIFT_CATEGORIES,
  builtinGiftId,
  canAffordGift,
  shortfallFor,
  countAffordableGifts,
  filterGiftsByCategory,
  sortGiftsForShop,
  canRedeem,
  getGiftCategoryMeta,
  GIFT_CATEGORY_ALL
} from '../../../../main/ets/models/GiftModels'

/**
 * GiftModels 纯函数单元测试（spec 2026-10-19 §9）
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 * CLI `hvigorw test` 不可用（MEMORY.md）
 */
function makeGift(id: string, priceStars: number, enabled: boolean, sortOrder: number, category: string): GiftItem {
  const gift: GiftItem = {
    id: id, name: `礼物${id}`, category: category, priceStars: priceStars,
    isBuiltin: false, enabled: enabled, sortOrder: sortOrder
  }
  return gift
}

export default function giftModelsTest() {
  describe('GiftModels', () => {
    it('canAffordGift_边界_恰好等于', 0, () => {
      expect(canAffordGift(60, 60)).assertTrue()
      expect(canAffordGift(59, 60)).assertFalse()
      expect(canAffordGift(61, 60)).assertTrue()
    })
    it('shortfallFor_差几颗', 0, () => {
      expect(shortfallFor(59, 60)).assertEqual(1)
      expect(shortfallFor(100, 60)).assertEqual(0)
      expect(shortfallFor(0, 30)).assertEqual(30)
    })
    it('countAffordableGifts_只数enabled', 0, () => {
      const gifts: GiftItem[] = [
        makeGift('a', 30, true, 1, 'other'),
        makeGift('b', 60, true, 2, 'other'),
        makeGift('c', 40, false, 3, 'other')
      ]
      expect(countAffordableGifts(gifts, 50)).assertEqual(1)
      expect(countAffordableGifts(gifts, 100)).assertEqual(2)
      expect(countAffordableGifts(gifts, 0)).assertEqual(0)
    })
    it('filterGiftsByCategory_all_不过滤', 0, () => {
      const gifts: GiftItem[] = [
        makeGift('a', 30, true, 1, 'other'),
        makeGift('b', 60, true, 2, 'plush')
      ]
      expect(filterGiftsByCategory(gifts, GIFT_CATEGORY_ALL).length).assertEqual(2)
      expect(filterGiftsByCategory(gifts, 'plush').length).assertEqual(1)
      expect(filterGiftsByCategory(gifts, 'vehicle').length).assertEqual(0)
    })
    it('sortGiftsForShop_按sortOrder升序_不改原数组', 0, () => {
      const gifts: GiftItem[] = [makeGift('b', 60, true, 2, 'other'), makeGift('a', 30, true, 1, 'other')]
      const sorted: GiftItem[] = sortGiftsForShop(gifts)
      expect(sorted[0].id).assertEqual('a')
      expect(gifts[0].id).assertEqual('b')
    })
    it('canRedeem_三种拒绝_一种通过', 0, () => {
      const off: GiftItem = makeGift('x', 30, false, 1, 'other')
      expect(canRedeem(100, off).success).assertFalse()
      expect(canRedeem(100, off).reason).assertEqual('gift_unavailable')
      expect(canRedeem(100, null).reason).assertEqual('gift_unavailable')
      const poor: GiftItem = makeGift('x', 300, true, 1, 'other')
      const poorResult = canRedeem(100, poor)
      expect(poorResult.success).assertFalse()
      expect(poorResult.reason).assertEqual('insufficient')
      expect(poorResult.shortfall).assertEqual(200)
      const ok: GiftItem = makeGift('x', 100, true, 1, 'other')
      expect(canRedeem(100, ok).success).assertTrue()
    })
    it('builtinGiftId_两位序号', 0, () => {
      expect(builtinGiftId(0)).assertEqual('gift_builtin_00')
      expect(builtinGiftId(11)).assertEqual('gift_builtin_11')
    })
    it('BUILTIN_GIFTS_12件_价格合法_分类合法', 0, () => {
      expect(BUILTIN_GIFTS.length).assertEqual(12)
      for (let i = 0; i < BUILTIN_GIFTS.length; i++) {
        expect(BUILTIN_GIFTS[i].priceStars >= 1).assertTrue()
        expect(GIFT_CATEGORIES.indexOf(BUILTIN_GIFTS[i].category) >= 0).assertTrue()
      }
    })
    it('getGiftCategoryMeta_未知分类回退other', 0, () => {
      expect(getGiftCategoryMeta('plush').label).assertEqual('玩偶')
      expect(getGiftCategoryMeta('nope').label).assertEqual('其他')
    })
  })
}
```

- [ ] **Step 2: 注册测试到 List.test.ets**

`entry/src/ohosTest/ets/test/List.test.ets` 顶部 import 区加：

```typescript
import giftModelsTest from './utils/GiftModels.test';
```

`testsuite()` 函数体末尾加：

```typescript
  giftModelsTest();
```

- [ ] **Step 3: 编译确认测试失败（红）**

测试引用的模块尚不存在，预期编译失败。运行：

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

Expected: FAIL——`GiftModels.ets` 不存在的编译错误（这是本项目的"红"状态；hypium 实际运行在 IDE 中，CLI 只能验证编译）。

- [ ] **Step 4: 实现 GiftModels.ets**

`entry/src/main/ets/models/GiftModels.ets` 全文：

```typescript
/**
 * 星星礼物商城数据模型（spec docs/superpowers/specs/2026-10-19-star-gift-shop-design.md §4.5）
 *
 * gifts 表 / gift_redemptions 表的内存模型、内置目录与纯函数。
 * 刻意不触碰 models/StarEventModels——兑换是独立流水，不进星星事件 10 处漂移点。
 * 分类色 tint 是 brand 暖色绘本调色板的扩展（spec §5），与 KidsBrandTokens 平级；
 * 放在本文件因为它是分类数据的一部分，models 层不 import components 层。
 */

export type GiftCategory = 'building' | 'plush' | 'vehicle' | 'stationery' | 'other'

export const GIFT_CATEGORIES: GiftCategory[] = ['building', 'plush', 'vehicle', 'stationery', 'other']
export const GIFT_CATEGORY_ALL: string = 'all'

export interface GiftCategoryMeta {
  label: string
  iconPath: string
  tint: string
}

const GIFT_CATEGORY_META_MAP: Record<string, GiftCategoryMeta> = {
  'building': { label: '拼搭', iconPath: 'kids/gift_blocks.svg', tint: '#4E8FE0' } as GiftCategoryMeta,
  'plush': { label: '玩偶', iconPath: 'kids/gift_plush.svg', tint: '#E0567C' } as GiftCategoryMeta,
  'vehicle': { label: '玩具车', iconPath: 'kids/gift_vehicle.svg', tint: '#35A98A' } as GiftCategoryMeta,
  'stationery': { label: '文具', iconPath: 'kids/gift_stationery.svg', tint: '#8B72E0' } as GiftCategoryMeta,
  'other': { label: '其他', iconPath: 'kids/gift_other.svg', tint: '#FF9F43' } as GiftCategoryMeta
}

export function getGiftCategoryMeta(category: string): GiftCategoryMeta {
  const meta: GiftCategoryMeta | undefined = GIFT_CATEGORY_META_MAP[category]
  if (meta !== undefined) {
    return meta
  }
  return GIFT_CATEGORY_META_MAP['other']
}

export interface GiftItem {
  id: string
  name: string
  category: string
  priceStars: number
  isBuiltin: boolean
  enabled: boolean
  sortOrder: number
}

export const GIFT_STATUS_PENDING: string = 'pending'
export const GIFT_STATUS_PICKED: string = 'picked'

export interface GiftRedemptionRow {
  id: string
  giftId: string
  giftName: string
  category: string
  priceStars: number
  redeemCode: string
  status: string
  createdAt: number
  pickedAt: number
}

export interface GiftShopStats {
  earnedTotal: number
  redeemedTotal: number
  redeemCount: number
}

export interface GiftRedeemResult {
  success: boolean
  /** '' | 'gift_unavailable' | 'insufficient' | 'db_error' */
  reason: string
  /** reason === 'insufficient' 时为还差颗数，其余为 0 */
  shortfall: number
  redemption: GiftRedemptionRow | null
}

export interface BuiltinGiftSpec {
  name: string
  category: GiftCategory
  priceStars: number
}

/** 内置目录 12 件（spec §4.1 表格）；sortOrder = 数组下标 + 1 */
export const BUILTIN_GIFTS: BuiltinGiftSpec[] = [
  { name: '迷你积木车', category: 'building', priceStars: 60 } as BuiltinGiftSpec,
  { name: '小颗粒积木盒', category: 'building', priceStars: 150 } as BuiltinGiftSpec,
  { name: '卡通钥匙扣', category: 'plush', priceStars: 40 } as BuiltinGiftSpec,
  { name: '毛绒小熊', category: 'plush', priceStars: 120 } as BuiltinGiftSpec,
  { name: '回力小赛车', category: 'vehicle', priceStars: 50 } as BuiltinGiftSpec,
  { name: '遥控越野车', category: 'vehicle', priceStars: 300 } as BuiltinGiftSpec,
  { name: '贴纸一册', category: 'stationery', priceStars: 30 } as BuiltinGiftSpec,
  { name: '漂亮笔记本', category: 'stationery', priceStars: 60 } as BuiltinGiftSpec,
  { name: '彩铅套装', category: 'stationery', priceStars: 100 } as BuiltinGiftSpec,
  { name: '冰淇淋一支', category: 'other', priceStars: 30 } as BuiltinGiftSpec,
  { name: '绘本一本', category: 'other', priceStars: 80 } as BuiltinGiftSpec,
  { name: '周末公园野餐', category: 'other', priceStars: 200 } as BuiltinGiftSpec
]

/** 内置礼物固定 id（幂等种子用），index = BUILTIN_GIFTS 下标 */
export function builtinGiftId(index: number): string {
  return `gift_builtin_${String(index).padStart(2, '0')}`
}

// ── 纯函数（spec §9 测试策略）──

export function canAffordGift(balance: number, priceStars: number): boolean {
  return balance >= priceStars
}

export function shortfallFor(balance: number, priceStars: number): number {
  return Math.max(0, priceStars - balance)
}

export function countAffordableGifts(gifts: GiftItem[], balance: number): number {
  let count = 0
  for (let i = 0; i < gifts.length; i++) {
    const gift = gifts[i]
    if (gift.enabled && gift.priceStars <= balance) {
      count++
    }
  }
  return count
}

export function filterGiftsByCategory(gifts: GiftItem[], category: string): GiftItem[] {
  if (category === GIFT_CATEGORY_ALL) {
    return gifts
  }
  return gifts.filter((gift: GiftItem): boolean => gift.category === category)
}

export function sortGiftsForShop(gifts: GiftItem[]): GiftItem[] {
  const sorted: GiftItem[] = [...gifts]
  sorted.sort((a: GiftItem, b: GiftItem): number => a.sortOrder - b.sortOrder)
  return sorted
}

/** 兑换前置判定：礼物不可用 / 余额不足 / 通过。reason/shortfall 语义见 GiftRedeemResult */
export function canRedeem(balance: number, gift: GiftItem | null): GiftRedeemResult {
  if (gift === null || !gift.enabled) {
    const unavailable: GiftRedeemResult = { success: false, reason: 'gift_unavailable', shortfall: 0, redemption: null }
    return unavailable
  }
  if (!canAffordGift(balance, gift.priceStars)) {
    const insufficient: GiftRedeemResult =
      { success: false, reason: 'insufficient', shortfall: shortfallFor(balance, gift.priceStars), redemption: null }
    return insufficient
  }
  const ok: GiftRedeemResult = { success: true, reason: '', shortfall: 0, redemption: null }
  return ok
}
```

- [ ] **Step 5: 编译确认通过（绿）**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

Expected: PASS（编译通过；单测在 DevEco Studio 右键 `GiftModels.test.ets` 跑，9 组用例应全绿）

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/models/GiftModels.ets entry/src/ohosTest/ets/test/utils/GiftModels.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat: GiftModels 模型+纯函数（礼物/兑换流水/内置目录）"
```

---

### Task 2: RedeemCodeUtils 领取码（TDD）

**Files:**
- Create: `entry/src/main/ets/utils/RedeemCodeUtils.ets`
- Test: `entry/src/ohosTest/ets/test/utils/RedeemCodeUtils.test.ets`
- Modify: `entry/src/ohosTest/ets/test/List.test.ets`

**Interfaces:**
- Consumes: 无
- Produces: `generateRedeemCode(): string`（6 位大写字母数字，字符集无 0/O/1/I/L）、`isValidRedeemCode(code: string): boolean`、`REDEEM_CODE_RETRY_LIMIT: number`（=3）

- [ ] **Step 1: 写失败测试**

`entry/src/ohosTest/ets/test/utils/RedeemCodeUtils.test.ets` 全文：

```typescript
import { describe, it, expect } from '@ohos/hypium'
import { generateRedeemCode, isValidRedeemCode, REDEEM_CODE_RETRY_LIMIT } from '../../../../main/ets/utils/RedeemCodeUtils'

/**
 * 领取码生成/校验测试（spec §4.4 步骤 3、§9）
 * 运行: DevEco Studio → 右键该文件 → Run 'hypium test'
 */
const FORBIDDEN_CHARS: string = '0O1IL'

export default function redeemCodeUtilsTest() {
  describe('RedeemCodeUtils', () => {
    it('generate_长度6', 0, () => {
      expect(generateRedeemCode().length).assertEqual(6)
    })
    it('generate_不含混淆字符', 0, () => {
      for (let i = 0; i < 50; i++) {
        const code: string = generateRedeemCode()
        for (let j = 0; j < FORBIDDEN_CHARS.length; j++) {
          expect(code.indexOf(FORBIDDEN_CHARS[j]) < 0).assertTrue()
        }
      }
    })
    it('generate_随机性_50次不全部相同', 0, () => {
      const first: string = generateRedeemCode()
      let allSame: boolean = true
      for (let i = 0; i < 50; i++) {
        if (generateRedeemCode() !== first) {
          allSame = false
          break
        }
      }
      expect(allSame).assertFalse()
    })
    it('isValid_合法与非法', 0, () => {
      expect(isValidRedeemCode(generateRedeemCode())).assertTrue()
      expect(isValidRedeemCode('A7K2QD')).assertTrue()
      expect(isValidRedeemCode('A7K2Q')).assertFalse()
      expect(isValidRedeemCode('A7K2QDD')).assertFalse()
      expect(isValidRedeemCode('A7K2Q0')).assertFalse()
      expect(isValidRedeemCode('a7k2qd')).assertFalse()
      expect(isValidRedeemCode('')).assertFalse()
    })
    it('RETRY_LIMIT_为3', 0, () => {
      expect(REDEEM_CODE_RETRY_LIMIT).assertEqual(3)
    })
  })
}
```

- [ ] **Step 2: 注册测试**

`List.test.ets` import 区加 `import redeemCodeUtilsTest from './utils/RedeemCodeUtils.test';`，`testsuite()` 末尾加 `redeemCodeUtilsTest();`

- [ ] **Step 3: 编译确认失败（红）**

同 Task 1 Step 3 的构建命令。Expected: FAIL（模块不存在）。

- [ ] **Step 4: 实现 RedeemCodeUtils.ets**

`entry/src/main/ets/utils/RedeemCodeUtils.ets` 全文：

```typescript
/**
 * 领取码生成/校验（spec §4.4 步骤 3）。
 * 字符集去掉视觉混淆字符 0/O/1/I/L，方便家长口头读码、孩子抄写。
 * 6 位字母数字（去混淆后 31 字符集），空间 31^6 ≈ 8.9 亿，单家庭场景碰撞可忽略；
 * 服务层仍会对 pending 记录做碰撞重试（REDEEM_CODE_RETRY_LIMIT 次）。
 */

const REDEEM_CODE_LENGTH: number = 6
const REDEEM_CODE_CHARSET: string = '23456789ABCDEFGHJKMNPQRSTUVWXYZ'

export const REDEEM_CODE_RETRY_LIMIT: number = 3

export function generateRedeemCode(): string {
  let code = ''
  for (let i = 0; i < REDEEM_CODE_LENGTH; i++) {
    const idx: number = Math.floor(Math.random() * REDEEM_CODE_CHARSET.length)
    code += REDEEM_CODE_CHARSET[idx]
  }
  return code
}

export function isValidRedeemCode(code: string): boolean {
  if (code.length !== REDEEM_CODE_LENGTH) {
    return false
  }
  for (let i = 0; i < code.length; i++) {
    if (REDEEM_CODE_CHARSET.indexOf(code[i]) < 0) {
      return false
    }
  }
  return true
}
```

- [ ] **Step 5: 编译确认通过（绿）**

同 Task 1 Step 5 命令。Expected: PASS（IDE 中跑 5 组用例全绿）。

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/utils/RedeemCodeUtils.ets entry/src/ohosTest/ets/test/utils/RedeemCodeUtils.test.ets entry/src/ohosTest/ets/test/List.test.ets
git commit -m "feat: 领取码生成/校验工具（去混淆字符集）"
```

---

### Task 3: DatabaseService 两张表 + 内置种子 + CRUD

**Files:**
- Modify: `entry/src/main/ets/services/DatabaseService.ets`

**Interfaces:**
- Consumes: Task 1 的 `GiftItem` / `GiftRedemptionRow` / `BUILTIN_GIFTS` / `builtinGiftId` / `GIFT_STATUS_PICKED`
- Produces（Task 4 依赖）:
  - `getGifts(): Promise<GiftItem[]>`（sort_order 升序）
  - `insertGift(gift: GiftItem): Promise<boolean>`
  - `updateGift(gift: GiftItem): Promise<boolean>`
  - `deleteGift(id: string): Promise<boolean>`
  - `insertGiftRedemption(redemption: GiftRedemptionRow): Promise<boolean>`
  - `getGiftRedemptions(): Promise<GiftRedemptionRow[]>`（created_at 降序）
  - `getRedeemedStarsTotal(): Promise<number>`
  - `markRedemptionPicked(id: string, pickedAtMs: number): Promise<boolean>`
  - `ensureBuiltinGifts(): Promise<void>`（幂等种子）

- [ ] **Step 1: 加 import 与 TableNames**

`DatabaseService.ets` import 区（已有 GiftModels 无 import——新增）：

```typescript
import { GiftItem, GiftRedemptionRow, BUILTIN_GIFTS, builtinGiftId, GIFT_STATUS_PICKED } from '../models/GiftModels'
```

`TableNames` 类（`entry/src/main/ets/services/DatabaseService.ets:103-125`）`LEARNING_ITEM_EVENTS` 行后加：

```typescript
  // 星星礼物商城（spec 2026-10-19）
  static readonly GIFTS: string = 'gifts'
  static readonly GIFT_REDEMPTIONS: string = 'gift_redemptions'
```

- [ ] **Step 2: createTables 加两张表 + 索引**

在 `star_events` 建表语句块之后（`entry/src/main/ets/services/DatabaseService.ets:439-449` 之后的 `const createDailyLessonPlansTable` 之前）插入：

```typescript
    // 星星礼物商城：礼物目录（内置幂等种子 + 家长自定义，spec §4.1）
    const createGiftsTable = `
      CREATE TABLE IF NOT EXISTS ${TableNames.GIFTS} (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        price_stars INTEGER NOT NULL,
        is_builtin INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL
      )
    `

    // 兑换流水（礼物快照字段 name/category/price 落库，礼物后续被改/删不影响历史，spec §4.2）
    const createGiftRedemptionsTable = `
      CREATE TABLE IF NOT EXISTS ${TableNames.GIFT_REDEMPTIONS} (
        id TEXT PRIMARY KEY,
        gift_id TEXT NOT NULL,
        gift_name TEXT NOT NULL,
        category TEXT NOT NULL,
        price_stars INTEGER NOT NULL,
        redeem_code TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at INTEGER NOT NULL,
        picked_at INTEGER NOT NULL DEFAULT 0
      )
    `
```

并在该方法中既有 `CREATE INDEX` 语句（`idx_star_events_created_at`，`DatabaseService.ets:634`）旁同批执行处加：

```typescript
      `CREATE INDEX IF NOT EXISTS idx_gift_redemptions_created_at ON ${TableNames.GIFT_REDEMPTIONS}(created_at)`
```

（跟随该文件既有把多条 SQL 收集进数组批量 execute 的写法——若 `idx_star_events_created_at` 是单条 `executeSql`，则同样单条 executeSql。）

- [ ] **Step 3: ensureBuiltinGifts 幂等种子**

在 `ensureKidsSubjectAssistants()`（`DatabaseService.ets:1353`）方法后面新增方法：

```typescript
  /**
   * 内置礼物幂等种子（spec §4.1）：INSERT OR IGNORE，升级不重复、不覆盖用户态。
   * 调用时机: createTables 流程内、ensureKidsSubjectAssistants() 之后。
   */
  private async ensureBuiltinGifts(): Promise<void> {
    if (this.rdbStore === null) {
      return
    }
    for (let i = 0; i < BUILTIN_GIFTS.length; i++) {
      const spec = BUILTIN_GIFTS[i]
      const bucket: relationalStore.ValuesBucket = {
        id: builtinGiftId(i),
        name: spec.name,
        category: spec.category,
        price_stars: spec.priceStars,
        is_builtin: 1,
        sort_order: i + 1,
        enabled: 1,
        created_at: Date.now()
      }
      try {
        await this.rdbStore.insert(TableNames.GIFTS, bucket, relationalStore.ConflictResolution.ON_CONFLICT_IGNORE)
      } catch (error) {
        console.error('DatabaseService', `Failed to seed builtin gift ${i}: ${JSON.stringify(error)}`)
      }
    }
  }
```

并在 `createTables` 流程中 `await this.ensureKidsSubjectAssistants()`（`DatabaseService.ets:709`）之后加：

```typescript
      await this.ensureBuiltinGifts()
```

- [ ] **Step 4: CRUD 方法**

在星事件方法区（`getStarTotalsByDay` 附近）后新增整块：

```typescript
  // ============ 星星礼物商城（spec 2026-10-19）============

  private readGiftRow(resultSet: relationalStore.ResultSet): GiftItem {
    const gift: GiftItem = {
      id: resultSet.getString(resultSet.getColumnIndex('id')),
      name: resultSet.getString(resultSet.getColumnIndex('name')),
      category: resultSet.getString(resultSet.getColumnIndex('category')),
      priceStars: resultSet.getLong(resultSet.getColumnIndex('price_stars')),
      isBuiltin: resultSet.getLong(resultSet.getColumnIndex('is_builtin')) === 1,
      enabled: resultSet.getLong(resultSet.getColumnIndex('enabled')) === 1,
      sortOrder: resultSet.getLong(resultSet.getColumnIndex('sort_order'))
    }
    return gift
  }

  private readGiftRedemptionRow(resultSet: relationalStore.ResultSet): GiftRedemptionRow {
    const row: GiftRedemptionRow = {
      id: resultSet.getString(resultSet.getColumnIndex('id')),
      giftId: resultSet.getString(resultSet.getColumnIndex('gift_id')),
      giftName: resultSet.getString(resultSet.getColumnIndex('gift_name')),
      category: resultSet.getString(resultSet.getColumnIndex('category')),
      priceStars: resultSet.getLong(resultSet.getColumnIndex('price_stars')),
      redeemCode: resultSet.getString(resultSet.getColumnIndex('redeem_code')),
      status: resultSet.getString(resultSet.getColumnIndex('status')),
      createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
      pickedAt: resultSet.getLong(resultSet.getColumnIndex('picked_at'))
    }
    return row
  }

  /** 全量礼物（含 enabled=0，管理页需要看到；商城侧在服务层过滤） */
  async getGifts(): Promise<GiftItem[]> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return []
    }
    const gifts: GiftItem[] = []
    const predicates = new relationalStore.RdbPredicates(TableNames.GIFTS)
    predicates.orderByAsc('sort_order')
    try {
      const resultSet = await this.rdbStore.query(predicates)
      while (resultSet.goToNextRow()) {
        gifts.push(this.readGiftRow(resultSet))
      }
      resultSet.close()
    } catch (error) {
      console.error('DatabaseService', `Failed to query gifts: ${JSON.stringify(error)}`)
    }
    return gifts
  }

  async insertGift(gift: GiftItem): Promise<boolean> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return false
    }
    const bucket: relationalStore.ValuesBucket = {
      id: gift.id,
      name: gift.name,
      category: gift.category,
      price_stars: gift.priceStars,
      is_builtin: gift.isBuiltin ? 1 : 0,
      sort_order: gift.sortOrder,
      enabled: gift.enabled ? 1 : 0,
      created_at: Date.now()
    }
    try {
      await this.rdbStore.insert(TableNames.GIFTS, bucket)
      return true
    } catch (error) {
      console.error('DatabaseService', `Failed to insert gift: ${JSON.stringify(error)}`)
      return false
    }
  }

  /** 编辑后整行覆盖（is_builtin 由服务层守卫，此处不重复校验） */
  async updateGift(gift: GiftItem): Promise<boolean> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return false
    }
    const bucket: relationalStore.ValuesBucket = {
      name: gift.name,
      category: gift.category,
      price_stars: gift.priceStars,
      enabled: gift.enabled ? 1 : 0,
      sort_order: gift.sortOrder
    }
    const predicates = new relationalStore.RdbPredicates(TableNames.GIFTS)
    predicates.equalTo('id', gift.id)
    try {
      const rows = await this.rdbStore.update(bucket, predicates)
      return rows > 0
    } catch (error) {
      console.error('DatabaseService', `Failed to update gift: ${JSON.stringify(error)}`)
      return false
    }
  }

  async deleteGift(id: string): Promise<boolean> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return false
    }
    const predicates = new relationalStore.RdbPredicates(TableNames.GIFTS)
    predicates.equalTo('id', id)
    try {
      const rows = await this.rdbStore.delete(predicates)
      return rows > 0
    } catch (error) {
      console.error('DatabaseService', `Failed to delete gift: ${JSON.stringify(error)}`)
      return false
    }
  }

  async insertGiftRedemption(redemption: GiftRedemptionRow): Promise<boolean> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return false
    }
    const bucket: relationalStore.ValuesBucket = {
      id: redemption.id,
      gift_id: redemption.giftId,
      gift_name: redemption.giftName,
      category: redemption.category,
      price_stars: redemption.priceStars,
      redeem_code: redemption.redeemCode,
      status: redemption.status,
      created_at: redemption.createdAt,
      picked_at: redemption.pickedAt
    }
    try {
      await this.rdbStore.insert(TableNames.GIFT_REDEMPTIONS, bucket)
      return true
    } catch (error) {
      console.error('DatabaseService', `Failed to insert gift redemption: ${JSON.stringify(error)}`)
      return false
    }
  }

  /** 兑换流水，created_at 降序（记录页直接展示） */
  async getGiftRedemptions(): Promise<GiftRedemptionRow[]> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return []
    }
    const rows: GiftRedemptionRow[] = []
    const predicates = new relationalStore.RdbPredicates(TableNames.GIFT_REDEMPTIONS)
    predicates.orderByDesc('created_at')
    try {
      const resultSet = await this.rdbStore.query(predicates)
      while (resultSet.goToNextRow()) {
        rows.push(this.readGiftRedemptionRow(resultSet))
      }
      resultSet.close()
    } catch (error) {
      console.error('DatabaseService', `Failed to query gift redemptions: ${JSON.stringify(error)}`)
    }
    return rows
  }

  /** 已兑换星星总额（余额 = 累计获得 − 本值，spec §4.3）。client-side 聚合，对齐 MVP 策略 */
  async getRedeemedStarsTotal(): Promise<number> {
    const rows: GiftRedemptionRow[] = await this.getGiftRedemptions()
    let total = 0
    for (let i = 0; i < rows.length; i++) {
      total += rows[i].priceStars
    }
    return total
  }

  async markRedemptionPicked(id: string, pickedAtMs: number): Promise<boolean> {
    await this.waitForInitialization()
    if (this.rdbStore === null) {
      return false
    }
    const bucket: relationalStore.ValuesBucket = {
      status: GIFT_STATUS_PICKED,
      picked_at: pickedAtMs
    }
    const predicates = new relationalStore.RdbPredicates(TableNames.GIFT_REDEMPTIONS)
    predicates.equalTo('id', id)
    try {
      const rows = await this.rdbStore.update(bucket, predicates)
      return rows > 0
    } catch (error) {
      console.error('DatabaseService', `Failed to mark redemption picked: ${JSON.stringify(error)}`)
      return false
    }
  }
```

- [ ] **Step 5: 编译验证**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/services/DatabaseService.ets
git commit -m "feat: gifts/gift_redemptions 表 + 内置礼物幂等种子 + CRUD"
```

---

### Task 4: StarRewardService.getStarBalance + GiftShopService

**Files:**
- Modify: `entry/src/main/ets/services/StarRewardService.ets`
- Create: `entry/src/main/ets/services/GiftShopService.ets`

**Interfaces:**
- Consumes: Task 1（`GiftRedeemResult`/`canRedeem`/`countAffordableGifts` 等）、Task 2（`generateRedeemCode`/`REDEEM_CODE_RETRY_LIMIT`）、Task 3（DB 方法）
- Produces（Task 7-10 依赖）:
  - `StarRewardService.getStarBalance(): Promise<number>`
  - `getGiftShopService(): GiftShopService`，其方法：
    - `getGiftsForShop(): Promise<GiftItem[]>`（enabled=1，sortOrder 升序）
    - `getGiftsForManage(): Promise<GiftItem[]>`（全量）
    - `addCustomGift(name: string, category: string, priceStars: number): Promise<boolean>`
    - `updateCustomGift(gift: GiftItem): Promise<boolean>`（内置礼物返回 false）
    - `deleteCustomGift(id: string): Promise<boolean>`（内置礼物返回 false）
    - `getStarBalance(): Promise<number>`
    - `getShopStats(): Promise<GiftShopStats>`
    - `redeem(giftId: string): Promise<GiftRedeemResult>`
    - `getRedemptions(): Promise<GiftRedemptionRow[]>`
    - `getPendingRedemptionCount(): Promise<number>`
    - `markRedemptionPicked(id: string): Promise<boolean>`

- [ ] **Step 1: StarRewardService 加 getStarBalance**

在 `getStarsSinceMs`（`StarRewardService.ets:357-361`）之后加：

```typescript
  /**
   * 可用余额 = 累计获得 − 累计兑换（spec §4.3）。
   * 兑换流水独立存 gift_redemptions 表，不写 star_events（避开 10 处漂移点）。
   * 负数余额没有意义，防御性钳到 0（数据异常时可见 0 而非负数）。
   */
  async getStarBalance(): Promise<number> {
    const earned = await this.getAllTimeStarTotal()
    const redeemed = await this.database.getRedeemedStarsTotal()
    return Math.max(0, earned - redeemed)
  }
```

- [ ] **Step 2: 实现 GiftShopService.ets**

`entry/src/main/ets/services/GiftShopService.ets` 全文：

```typescript
/**
 * 星星礼物商城服务（spec docs/superpowers/specs/2026-10-19-star-gift-shop-design.md §4.4）
 *
 * 单例，镜像 StarRewardService 模式。gifts/gift_redemptions 两表的唯一业务写入口：
 * - 余额 = StarRewardService.getAllTimeStarTotal() − getRedeemedStarsTotal()
 * - redeem() 是唯一兑换写路径：前置判定（canRedeem 纯函数）→ 领取码 → 写快照流水
 * - 内置礼物（is_builtin=1）对编辑/删除守卫拒绝，语义对齐内置助手锁定
 */

import { util } from '@kit.ArkTS'
import { getDatabaseService, DatabaseService } from './DatabaseService'
import { getStarRewardService } from './StarRewardService'
import {
  GiftItem,
  GiftRedemptionRow,
  GiftRedeemResult,
  GiftShopStats,
  canRedeem,
  GIFT_STATUS_PENDING
} from '../models/GiftModels'
import { generateRedeemCode, REDEEM_CODE_RETRY_LIMIT } from '../utils/RedeemCodeUtils'

export class GiftShopService {
  private static instance: GiftShopService | null = null
  private database: DatabaseService

  private constructor() {
    this.database = getDatabaseService()
  }

  static getInstance(): GiftShopService {
    if (GiftShopService.instance === null) {
      GiftShopService.instance = new GiftShopService()
    }
    return GiftShopService.instance
  }

  /** 商城用：仅上架礼物，sort_order 升序 */
  async getGiftsForShop(): Promise<GiftItem[]> {
    const all = await this.database.getGifts()
    return all.filter((gift: GiftItem): boolean => gift.enabled)
  }

  /** 管理页用：全量（含下架/内置） */
  async getGiftsForManage(): Promise<GiftItem[]> {
    return await this.database.getGifts()
  }

  async addCustomGift(name: string, category: string, priceStars: number): Promise<boolean> {
    const gift: GiftItem = {
      id: `gift_custom_${util.generateRandomUUID(false)}`,
      name: name.trim(),
      category: category,
      priceStars: Math.max(1, Math.floor(priceStars)),
      isBuiltin: false,
      enabled: true,
      sortOrder: Date.now()
    }
    return await this.database.insertGift(gift)
  }

  async updateCustomGift(gift: GiftItem): Promise<boolean> {
    if (gift.isBuiltin) {
      console.warn('GiftShopService', 'refuse to update builtin gift')
      return false
    }
    return await this.database.updateGift(gift)
  }

  async deleteCustomGift(id: string): Promise<boolean> {
    const all = await this.database.getGifts()
    for (let i = 0; i < all.length; i++) {
      if (all[i].id === id) {
        if (all[i].isBuiltin) {
          console.warn('GiftShopService', 'refuse to delete builtin gift')
          return false
        }
        return await this.database.deleteGift(id)
      }
    }
    return false
  }

  async getStarBalance(): Promise<number> {
    return await getStarRewardService().getStarBalance()
  }

  async getShopStats(): Promise<GiftShopStats> {
    const redemptions: GiftRedemptionRow[] = await this.database.getGiftRedemptions()
    let redeemedTotal = 0
    for (let i = 0; i < redemptions.length; i++) {
      redeemedTotal += redemptions[i].priceStars
    }
    const earnedTotal: number = await getStarRewardService().getAllTimeStarTotal()
    const stats: GiftShopStats = {
      earnedTotal: earnedTotal,
      redeemedTotal: redeemedTotal,
      redeemCount: redemptions.length
    }
    return stats
  }

  /**
   * 兑换（唯一写路径，spec §4.4 流程）：
   * 礼物可用性 → 余额（canRedeem 纯函数）→ 领取码（pending 碰撞重试 ≤3 次，
   * 仍碰撞用最后一个候选——31^6 空间下可忽略）→ 写快照流水。
   * 余额检查与写入无事务（单设备单用户，超兑至多 1 次且 UI 立即暴露）。
   */
  async redeem(giftId: string): Promise<GiftRedeemResult> {
    const gifts: GiftItem[] = await this.database.getGifts()
    let targetIndex = -1
    for (let i = 0; i < gifts.length; i++) {
      if (gifts[i].id === giftId) {
        targetIndex = i
        break
      }
    }
    const balance: number = await this.getStarBalance()
    if (targetIndex < 0) {
      const missing: GiftRedeemResult = { success: false, reason: 'gift_unavailable', shortfall: 0, redemption: null }
      return missing
    }
    const check: GiftRedeemResult = canRedeem(balance, gifts[targetIndex])
    if (!check.success) {
      return check
    }
    const gift: GiftItem = gifts[targetIndex]

    let code = ''
    for (let attempt = 0; attempt < REDEEM_CODE_RETRY_LIMIT; attempt++) {
      const candidate: string = generateRedeemCode()
      code = candidate
      const pending: GiftRedemptionRow[] = await this.database.getGiftRedemptions()
      let collision = false
      for (let i = 0; i < pending.length; i++) {
        if (pending[i].status === GIFT_STATUS_PENDING && pending[i].redeemCode === candidate) {
          collision = true
          break
        }
      }
      if (!collision) {
        break
      }
    }

    const redemption: GiftRedemptionRow = {
      id: `redeem_${util.generateRandomUUID(false)}`,
      giftId: gift.id,
      giftName: gift.name,
      category: gift.category,
      priceStars: gift.priceStars,
      redeemCode: code,
      status: GIFT_STATUS_PENDING,
      createdAt: Date.now(),
      pickedAt: 0
    }
    const ok: boolean = await this.database.insertGiftRedemption(redemption)
    if (!ok) {
      const failed: GiftRedeemResult = { success: false, reason: 'db_error', shortfall: 0, redemption: null }
      return failed
    }
    const success: GiftRedeemResult = { success: true, reason: '', shortfall: 0, redemption: redemption }
    return success
  }

  async getRedemptions(): Promise<GiftRedemptionRow[]> {
    return await this.database.getGiftRedemptions()
  }

  async getPendingRedemptionCount(): Promise<number> {
    const rows: GiftRedemptionRow[] = await this.database.getGiftRedemptions()
    let count = 0
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].status === GIFT_STATUS_PENDING) {
        count++
      }
    }
    return count
  }

  async markRedemptionPicked(id: string): Promise<boolean> {
    return await this.database.markRedemptionPicked(id, Date.now())
  }
}

export function getGiftShopService(): GiftShopService {
  return GiftShopService.getInstance()
}
```

- [ ] **Step 3: 编译验证**

同 Task 1 Step 5 命令。Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/services/StarRewardService.ets entry/src/main/ets/services/GiftShopService.ets
git commit -m "feat: GiftShopService 兑换写路径 + getStarBalance 余额"
```

---

### Task 5: 分类 SVG 图标

**Files:**
- Create: `entry/src/main/resources/rawfile/kids/gift_blocks.svg`
- Create: `entry/src/main/resources/rawfile/kids/gift_plush.svg`
- Create: `entry/src/main/resources/rawfile/kids/gift_vehicle.svg`
- Create: `entry/src/main/resources/rawfile/kids/gift_stationery.svg`
- Create: `entry/src/main/resources/rawfile/kids/gift_other.svg`

**Interfaces:**
- Produces: 5 个 24×24 viewBox 单色 SVG，fill 色 = GiftModels tint 值（`kids/star.svg` 同规格，baked-in 色、无 stroke 外描边依赖）

- [ ] **Step 1: 写入 5 个 SVG**

`gift_blocks.svg`（拼搭 · #4E8FE0，2×2 积木块）：

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect x="4" y="4" width="7" height="7" rx="1.5" fill="#4E8FE0"/><rect x="13" y="4" width="7" height="7" rx="1.5" fill="#4E8FE0" opacity="0.55"/><rect x="4" y="13" width="7" height="7" rx="1.5" fill="#4E8FE0" opacity="0.55"/><rect x="13" y="13" width="7" height="7" rx="1.5" fill="#4E8FE0"/></svg>
```

`gift_plush.svg`（玩偶 · #E0567C，熊头+耳朵）：

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="7" cy="7" r="3" fill="#E0567C"/><circle cx="17" cy="7" r="3" fill="#E0567C"/><circle cx="12" cy="13.5" r="7" fill="#E0567C"/><circle cx="9.5" cy="12.5" r="1.1" fill="#FFFDF8"/><circle cx="14.5" cy="12.5" r="1.1" fill="#FFFDF8"/></svg>
```

`gift_vehicle.svg`（玩具车 · #35A98A，车身+双轮）：

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M3 13.5l1.6-4.2A2 2 0 0 1 6.5 8h7a2 2 0 0 1 1.9 1.3L17 13.5h2a2 2 0 0 1 2 2v2a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-4z" fill="#35A98A"/><circle cx="8" cy="18" r="2.4" fill="#35A98A"/><circle cx="16" cy="18" r="2.4" fill="#35A98A"/><circle cx="8" cy="18" r="1" fill="#FFFDF8"/><circle cx="16" cy="18" r="1" fill="#FFFDF8"/></svg>
```

`gift_stationery.svg`（文具 · #8B72E0，铅笔）：

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M4 20l1.2-4.2L16.4 4.6a2 2 0 0 1 2.8 0l.2.2a2 2 0 0 1 0 2.8L8.2 18.8 4 20z" fill="#8B72E0"/><path d="M14.8 6.2l3 3" stroke="#FFFDF8" stroke-width="1.4" stroke-linecap="round"/></svg>
```

`gift_other.svg`（其他/礼盒 · #FF9F43，礼盒+蝴蝶结）：

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect x="4" y="9" width="16" height="11" rx="1.5" fill="#FF9F43"/><rect x="3" y="6" width="18" height="4" rx="1.2" fill="#FF9F43"/><rect x="11" y="6" width="2" height="14" fill="#FFFDF8" opacity="0.85"/><path d="M12 6c-1.5-3-5.5-3-5 0h5zm0 0c1.5-3 5.5-3 5 0h-5z" fill="#FF9F43"/></svg>
```

- [ ] **Step 2: 编译验证 + Commit**

构建命令同上，Expected: PASS（rawfile 不参与编译校验，主要确认无路径问题）。

```bash
git add entry/src/main/resources/rawfile/kids/gift_*.svg
git commit -m "feat: 礼物分类 SVG 图标 ×5"
```

---

### Task 6: ParentalGateSheet 加 gateOnly 参数

**Files:**
- Modify: `entry/src/main/ets/components/kids/ParentalGateSheet.ets:47-49` 附近与 gate→summary 切换处（`ParentalGateSheet.ets:96`）

**Interfaces:**
- Produces: `@Param gateOnly: boolean = false`——true 时算术门答对直接回调 `onPassed()`，跳过 summary 概览阶段；默认 false 行为完全不变。

- [ ] **Step 1: 加 Param**

在 `@Event onCancelled: () => void = () => {}`（`ParentalGateSheet.ets:50`）之后加：

```typescript
  /** true: 仅算术门（答对直接 onPassed，不进概览）——礼物核销用；默认 false 保持两阶段行为 */
  @Param gateOnly: boolean = false
```

- [ ] **Step 2: 答对路径分流**

找到答对后执行 `this.phase = 'summary'` 的方法（`ParentalGateSheet.ets:96` 所在方法，形如 `private handleConfirm()/checkAnswer()`）。在该赋值语句**之前**插入：

```typescript
      if (this.gateOnly) {
        this.onPassed()
        return
      }
```

保持后续 summary 加载逻辑不动。同时更新类头 doc 注释：补充一行 `* gateOnly=true 时退化为单阶段算术门（礼物核销用，spec 2026-10-19 §5.3）。`

- [ ] **Step 3: 编译验证 + Commit**

构建命令同上，Expected: PASS。人工冒烟（可选，Task 9 一起验）：主屏家长入口过门后仍进概览（默认行为未变）。

```bash
git add entry/src/main/ets/components/kids/ParentalGateSheet.ets
git commit -m "feat: ParentalGateSheet 支持 gateOnly 单阶段模式"
```

---

### Task 7: GiftShopPage 骨架 + 主屏药丸入口 + 路由注册

**Files:**
- Create: `entry/src/main/ets/pages/GiftShopPage.ets`
- Modify: `entry/src/main/resources/base/profile/router_map.json`（+1 条）
- Modify: `entry/src/main/ets/components/kids/KidsHomeView.ets`（药丸改余额 + 可点）
- Modify: `entry/src/main/ets/pages/Index.ets`（KidsRoot 接线）

**Interfaces:**
- Consumes: Task 4 的 `getGiftShopService()`（`getGiftsForShop`/`getStarBalance`/`getShopStats`/`getPendingRedemptionCount`）、Task 1 的模型与纯函数
- Produces: 路由名 `'GiftShopPage'` + `GiftShopPageBuilder`；商城页内部预留 `@Local showConfirmSheet` 等状态（Task 8 填充）；`KidsHomeView` 新 `@Event onOpenGiftShop: () => void`

- [ ] **Step 1: 注册路由**

`entry/src/main/resources/base/profile/router_map.json` 的 `routerMap` 数组末尾加：

```json
    {
      "name": "GiftShopPage",
      "pageSourceFile": "src/main/ets/pages/GiftShopPage.ets",
      "buildFunction": "GiftShopPageBuilder"
    }
```

- [ ] **Step 2: 实现 GiftShopPage**

`entry/src/main/ets/pages/GiftShopPage.ets` 全文（Task 8 将在标注 `// Task 8` 处填充兑换流）：

```typescript
import { GiftItem, GiftShopStats, GiftRedemptionRow,
  countAffordableGifts, filterGiftsByCategory, sortGiftsForShop,
  getGiftCategoryMeta, GIFT_CATEGORIES, GIFT_CATEGORY_ALL } from '../models/GiftModels'
import { getGiftShopService } from '../services/GiftShopService'
import {
  KIDS_BG, KIDS_SURFACE, KIDS_FG, KIDS_MUTED, KIDS_SUBTLE, KIDS_BORDER,
  KIDS_ACCENT, KIDS_ACCENT_2, KIDS_ON_HERO, KIDS_ON_HERO_2, KIDS_STAR, KIDS_ON_GOLD
} from '../components/kids/KidsBrandTokens'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'

/**
 * 星星商城（spec 2026-10-19 §5.2）：余额 hero + 统计条 + 分类 chips + 礼物网格。
 * 恒定 Kids 暖色绘本皮肤；入口 = 儿童主屏星星药丸（KidsHomeView onOpenGiftShop）。
 * 兑换确认/成功 sheet 见 Task 8。
 */

let giftShopPagePathStack: NavPathStack | null = null

@ComponentV2
struct GiftShopPage {
  @Local balance: number = 0
  @Local stats: GiftShopStats = { earnedTotal: 0, redeemedTotal: 0, redeemCount: 0 } as GiftShopStats
  @Local gifts: GiftItem[] = []
  @Local selectedCategory: string = GIFT_CATEGORY_ALL
  @Local pendingCount: number = 0
  // Task 8: 兑换 sheet 状态（showConfirmSheet / confirmGift / redeemState / lastRedemption / redeemError）

  private get topInsetVp(): number {
    return px2vp(getAppUiState().topAvoidHeight)
  }

  aboutToAppear(): void {
    this.loadAll()
  }

  private loadAll(): void {
    getGiftShopService().getStarBalance().then((balance: number): void => {
      this.balance = balance
    }).catch((): void => {
      this.balance = 0
    })
    getGiftShopService().getShopStats().then((stats: GiftShopStats): void => {
      this.stats = stats
    }).catch((): void => {
      this.stats = { earnedTotal: 0, redeemedTotal: 0, redeemCount: 0 } as GiftShopStats
    })
    getGiftShopService().getGiftsForShop().then((gifts: GiftItem[]): void => {
      this.gifts = sortGiftsForShop(gifts)
    }).catch((): void => {
      this.gifts = []
    })
    getGiftShopService().getPendingRedemptionCount().then((count: number): void => {
      this.pendingCount = count
    }).catch((): void => {
      this.pendingCount = 0
    })
  }

  /** ForEach 回调体内不能声明对象（10905209）——抽方法 */
  private chipKeys(): string[] {
    const keys: string[] = [GIFT_CATEGORY_ALL]
    for (let i = 0; i < GIFT_CATEGORIES.length; i++) {
      keys.push(GIFT_CATEGORIES[i])
    }
    return keys
  }

  private visibleGifts(): GiftItem[] {
    return filterGiftsByCategory(this.gifts, this.selectedCategory)
  }

  private affordableCount(): number {
    return countAffordableGifts(this.gifts, this.balance)
  }

  private chipLabel(key: string): string {
    if (key === GIFT_CATEGORY_ALL) {
      return '全部'
    }
    return getGiftCategoryMeta(key).label
  }

  private goBack(): void {
    if (giftShopPagePathStack !== null && giftShopPagePathStack.size() > 0) {
      giftShopPagePathStack.pop()
    }
  }

  private goRecords(): void {
    if (giftShopPagePathStack !== null) {
      giftShopPagePathStack.pushPath({ name: 'GiftRecordsPage' })
    }
  }

  @Builder
  TopBar() {
    Row({ space: 8 }) {
      Image($rawfile('kids/chevron.svg'))
        .width(20).height(20)
        .rotate({ angle: 180 })
        .onClick((): void => {
          this.goBack()
        })
      Text('星星商城')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_FG)
        .layoutWeight(1)
      Row({ space: 4 }) {
        Text('我的兑换')
          .fontSize(12.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(KIDS_FG)
        if (this.pendingCount > 0) {
          Text(`${this.pendingCount}`)
            .fontSize(10.5)
            .fontColor(KIDS_ON_GOLD)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(999)
            .backgroundColor(withColorAlpha(KIDS_STAR, '45'))
        }
      }
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .borderRadius(999)
      .backgroundColor(KIDS_SURFACE)
      .border({ width: 1, color: KIDS_BORDER })
      .onClick((): void => {
        this.goRecords()
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topInsetVp + 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  BalanceHero() {
    Column({ space: 6 }) {
      Text('我的星星')
        .fontSize(11.5)
        .fontColor(KIDS_ON_HERO_2)
      Row({ space: 6 }) {
        Image($rawfile('kids/star.svg')).width(30).height(30)
        Text(`${this.balance}`)
          .fontSize(40)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_ON_HERO)
        Text('颗')
          .fontSize(14)
          .fontColor(KIDS_ON_HERO_2)
      }
      .alignItems(VerticalAlign.Center)
      Text(this.affordableCount() > 0 ? `可换 ${this.affordableCount()} 件礼物` : '再攒一攒，很快能换啦')
        .fontSize(12.5)
        .fontColor(KIDS_ON_HERO)
    }
    .width('100%')
    .padding(20)
    .borderRadius(24)
    .linearGradient({ angle: 135, colors: [[KIDS_ACCENT, 0], [KIDS_ACCENT_2, 1]] })
    .shadow({ radius: 28, color: '#66FF9F43', offsetY: 10 })
  }

  @Builder
  StatsStrip() {
    Row({ space: 12 }) {
      this.StatCell(`${this.stats.earnedTotal}`, '累计获得')
      this.StatCell(`${this.stats.redeemedTotal}`, '累计兑换')
      this.StatCell(`${this.stats.redeemCount}`, '兑换件数')
    }
    .width('100%')
  }

  @Builder
  StatCell(numText: string, caption: string) {
    Column({ space: 2 }) {
      Text(numText)
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_FG)
      Text(caption)
        .fontSize(10.5)
        .fontColor(KIDS_SUBTLE)
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 12 })
    .borderRadius(16)
    .backgroundColor(KIDS_SURFACE)
    .border({ width: 1, color: KIDS_BORDER })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  CategoryChips() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.chipKeys(), (key: string): void => {
          Text(this.chipLabel(key))
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.selectedCategory === key ? '#FFFFFF' : KIDS_FG)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .borderRadius(999)
            .backgroundColor(this.selectedCategory === key ? KIDS_ACCENT : KIDS_SURFACE)
            .border({ width: 1, color: this.selectedCategory === key ? KIDS_ACCENT : KIDS_BORDER })
            .onClick((): void => {
              this.selectedCategory = key
            })
        }, (key: string): string => key)
      }
    }
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  GiftGrid() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
      ForEach(this.visibleGifts(), (gift: GiftItem): void => {
        this.GiftCard(gift)
      }, (gift: GiftItem): string => `${gift.id}_${gift.priceStars}_${this.balance}`)
    }
    .width('100%')
  }

  @Builder
  GiftCard(gift: GiftItem) {
    Column({ space: 8 }) {
      Column() {
        Image($rawfile(getGiftCategoryMeta(gift.category).iconPath)).width(34).height(34)
      }
      .width(64)
      .height(64)
      .borderRadius(20)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(withColorAlpha(getGiftCategoryMeta(gift.category).tint, '26'))

      Text(gift.name)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_FG)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 4 }) {
        Image($rawfile('kids/star.svg')).width(13).height(13)
        Text(`${gift.priceStars}`)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
      }

      // Task 8: 点击卡片 → 打开兑换确认 sheet（余额不足置灰 + 「还差 N 颗」）
    }
    .layoutWeight(1)
    .padding(14)
    .margin({ bottom: 12 })
    .borderRadius(19)
    .backgroundColor(KIDS_SURFACE)
    .border({ width: 1, color: KIDS_BORDER })
    .shadow({ radius: 8, color: '#1424211C', offsetY: 3 })
    .opacity(gift.priceStars <= this.balance ? 1 : 0.55)
  }

  build() {
    Column() {
      this.TopBar()
      Scroll() {
        Column({ space: 16 }) {
          this.BalanceHero()
          this.StatsStrip()
          this.CategoryChips()
          this.GiftGrid()
          Text('和爸爸妈妈商量好，兑换后把领取码给他们看')
            .fontSize(11)
            .fontColor(KIDS_SUBTLE)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      // Task 8: bindSheet 宿主（独立零尺寸 Column）
    }
    .width('100%')
    .height('100%')
    .backgroundColor(KIDS_BG)
  }
}

@Builder
export function GiftShopPageBuilder(_name: string, _param: Object) {
  NavDestination() {
    GiftShopPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    giftShopPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (giftShopPagePathStack !== null && giftShopPagePathStack.size() > 0) {
      giftShopPagePathStack.pop()
    }
    return true
  })
}
```

- [ ] **Step 3: KidsHomeView 药丸改余额 + 可点**

`entry/src/main/ets/components/kids/KidsHomeView.ets`：

1. import 区加：无新 import（`getStarRewardService` 已有）。
2. `@Local totalStars: number = 0`（行 57）改名为 `@Local starBalance: number = 0`。
3. `loadAll()`（行 95-99）改为：

```typescript
    getStarRewardService().getStarBalance().then((balance: number): void => {
      this.starBalance = balance
    }).catch((): void => {
      this.starBalance = 0
    })
```

4. 加 `@Event onOpenGiftShop: () => void = () => {}`（放在 `onGatePassed` 声明后）。
5. 问候行星星药丸（行 254-269）整体替换为：

```typescript
        Row({ space: 6 }) {
          Image($rawfile('kids/star.svg')).width(14).height(14)
          Text(`${this.starBalance}`)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_FG)
          Text('颗')
            .fontSize(11)
            .fontColor(KIDS_MUTED)
        }
        .padding({ left: 13, right: 13, top: 8, bottom: 8 })
        .borderRadius(999)
        .backgroundColor(KIDS_SURFACE)
        .border({ width: 1, color: KIDS_BORDER })
        .shadow({ radius: 6, color: '#1A24211C', offsetY: 2 })
        .accessibilityText(`可用星星 ${this.starBalance} 颗，点击进入星星商城`)
        .scale(this.starPillPressed ? { x: 0.96, y: 0.96 } : { x: 1, y: 1 })
        .animation({ duration: 70, curve: Curve.EaseOut })
        .onTouch((e: TouchEvent): void => {
          if (e.type === TouchType.Down) {
            this.starPillPressed = true
          } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            this.starPillPressed = false
          }
        })
        .onClick((): void => {
          this.onOpenGiftShop()
        })
```

6. 加按压态字段（放在 `pressedSubjectId` 声明后）：

```typescript
  /** 按压反馈: 星星药丸（进商城入口） */
  @Local starPillPressed: boolean = false
```

7. 类头 doc 注释第 3 行「问候行（昵称头像 + 时段问候 + 星星药丸）」后补一句：`星星药丸显示可用余额（累计获得−兑换），点击进星星商城（spec 2026-10-19）。`

- [ ] **Step 4: Index 接线**

`entry/src/main/ets/pages/Index.ets` `KidsRoot()`（`Index.ets:2698-2715`）`KidsHomeView({...})` 参数表 `onGatePassed` 前加：

```typescript
        onOpenGiftShop: (): void => {
          this.chatTabNavStack.pushPath({ name: 'GiftShopPage' })
        },
```

- [ ] **Step 5: 编译验证 + 人工冒烟**

构建命令同上，Expected: PASS。人工冒烟（DevEco 运行）：儿童主屏点星星药丸 → 进商城（余额 hero/统计/分类/网格正常）→ 返回主屏药丸数值不变。

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/pages/GiftShopPage.ets entry/src/main/resources/base/profile/router_map.json entry/src/main/ets/components/kids/KidsHomeView.ets entry/src/main/ets/pages/Index.ets
git commit -m "feat: 星星商城页 + 主屏星星药丸入口（余额口径）"
```

---

### Task 8: 兑换确认 sheet + 成功态

**Files:**
- Modify: `entry/src/main/ets/pages/GiftShopPage.ets`

**Interfaces:**
- Consumes: Task 4 `getGiftShopService().redeem(giftId)`（`GiftRedeemResult`）、Task 1 `canRedeem`/`shortfallFor`/`canAffordGift`
- Produces: 完整兑换流——确认 sheet（余额核对）→ 成功态（领取码展示 + 去我的兑换）

- [ ] **Step 1: 加状态字段**

struct 内 Task 7 预留注释处替换为：

```typescript
  @Local showConfirmSheet: boolean = false
  @Local confirmGift: GiftItem | null = null
  /** 'confirm' | 'success' | 'error' */
  @Local redeemState: string = 'confirm'
  @Local lastRedemption: GiftRedemptionRow | null = null
  @Local redeemError: string = ''
```

（`GiftRedemptionRow` 已在 Task 7 的 import 里。）

- [ ] **Step 2: GiftCard 加点击 + 不足提示**

Task 7 的 `GiftCard` Builder 中 `// Task 8` 注释处替换为：

```typescript
      Text(gift.priceStars <= this.balance ? '点击兑换' : `还差 ${shortfallFor(this.balance, gift.priceStars)} 颗`)
        .fontSize(10.5)
        .fontWeight(FontWeight.Medium)
        .fontColor(gift.priceStars <= this.balance ? getGiftCategoryMeta(gift.category).tint : KIDS_SUBTLE)
```

并在 `GiftCard` 外层 `.opacity(...)` 之后加点击与无障碍：

```typescript
    .accessibilityText(gift.priceStars <= this.balance ?
      `兑换${gift.name}，需要 ${gift.priceStars} 颗星` :
      `${gift.name}需要 ${gift.priceStars} 颗星，还差 ${shortfallFor(this.balance, gift.priceStars)} 颗`)
    .onClick((): void => {
      this.openConfirmSheet(gift)
    })
```

struct 加方法：

```typescript
  private openConfirmSheet(gift: GiftItem): void {
    this.confirmGift = gift
    this.redeemState = 'confirm'
    this.redeemError = ''
    this.lastRedemption = null
    this.showConfirmSheet = true
  }

  private confirmRedeem(): void {
    if (this.confirmGift === null) {
      return
    }
    const giftId: string = this.confirmGift.id
    getGiftShopService().redeem(giftId).then((result: GiftRedeemResult): void => {
      if (result.success && result.redemption !== null) {
        this.lastRedemption = result.redemption
        this.redeemState = 'success'
        this.loadAll()
      } else if (result.reason === 'insufficient') {
        this.redeemState = 'error'
        this.redeemError = `星星还差 ${result.shortfall} 颗，再攒一攒吧`
      } else {
        this.redeemState = 'error'
        this.redeemError = '兑换没有成功，稍后再试试'
      }
    }).catch((): void => {
      this.redeemState = 'error'
      this.redeemError = '兑换没有成功，稍后再试试'
    })
  }

  private goRecordsFromSheet(): void {
    this.showConfirmSheet = false
    this.goRecords()
  }
```

- [ ] **Step 3: bindSheet 宿主 + Sheet 内容**

`build()` 内 `// Task 8: bindSheet 宿主` 注释处加（独立零尺寸 Column 宿主，本页仅此一个 sheet）：

```typescript
      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showConfirmSheet, this.ConfirmSheetBuilder(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          preferType: SheetType.BOTTOM,
          onDisappear: (): void => {
            this.showConfirmSheet = false
          }
        })
```

struct 加 Builder：

```typescript
  @Builder
  ConfirmSheetBuilder() {
    Column({ space: 14 }) {
      Row() {
        Text(this.redeemState === 'success' ? '兑换成功' : (this.redeemState === 'error' ? '换个目标吧' : '确认兑换'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
        Blank()
        Text('✕')
          .fontSize(15)
          .fontColor(KIDS_SUBTLE)
          .width(36).height(36)
          .textAlign(TextAlign.Center)
          .onClick((): void => {
            this.showConfirmSheet = false
          })
      }
      .width('100%')

      if (this.redeemState === 'confirm' && this.confirmGift !== null) {
        Row({ space: 12 }) {
          Column() {
            Image($rawfile(getGiftCategoryMeta(this.confirmGift.category).iconPath)).width(28).height(28)
          }
          .width(52).height(52)
          .borderRadius(16)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(withColorAlpha(getGiftCategoryMeta(this.confirmGift.category).tint, '26'))
          Column({ space: 2 }) {
            Text(this.confirmGift.name)
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor(KIDS_FG)
            Text(`现有 ${this.balance} 颗 · 需要 ${this.confirmGift.priceStars} 颗`)
              .fontSize(12)
              .fontColor(KIDS_MUTED)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(`兑换后可用余额变为 ${this.balance - this.confirmGift.priceStars} 颗`)
          .fontSize(12)
          .fontColor(KIDS_SUBTLE)

        Row({ space: 8 }) {
          Text('再想想')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(KIDS_FG)
            .layoutWeight(1)
            .height(46)
            .textAlign(TextAlign.Center)
            .borderRadius(999)
            .border({ width: 1.5, color: KIDS_BORDER })
          Text(`用 ${this.confirmGift.priceStars} 颗星星兑换`)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .layoutWeight(2)
            .height(46)
            .textAlign(TextAlign.Center)
            .borderRadius(999)
            .backgroundColor(KIDS_ACCENT)
            .opacity(canAffordGift(this.balance, this.confirmGift.priceStars) ? 1 : 0.5)
            .onClick((): void => {
              if (canAffordGift(this.balance, this.confirmGift.priceStars)) {
                this.confirmRedeem()
              }
            })
        }
        .width('100%')
      }

      if (this.redeemState === 'success' && this.lastRedemption !== null) {
        Text('把领取码给爸爸妈妈看吧')
          .fontSize(12.5)
          .fontColor(KIDS_MUTED)
        Text(this.lastRedemption.redeemCode)
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(KIDS_FG)
          .letterSpacing(6)
          .padding(14)
          .width('100%')
          .textAlign(TextAlign.Center)
          .borderRadius(16)
          .backgroundColor(withColorAlpha(KIDS_ACCENT, '14'))
        Row({ space: 8 }) {
          Text('好的')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(KIDS_FG)
            .layoutWeight(1)
            .height(46)
            .textAlign(TextAlign.Center)
            .borderRadius(999)
            .border({ width: 1.5, color: KIDS_BORDER })
            .onClick((): void => {
              this.showConfirmSheet = false
            })
          Text('去查看我的兑换')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .layoutWeight(2)
            .height(46)
            .textAlign(TextAlign.Center)
            .borderRadius(999)
            .backgroundColor(KIDS_ACCENT)
            .onClick((): void => {
              this.goRecordsFromSheet()
            })
        }
        .width('100%')
      }

      if (this.redeemState === 'error') {
        Text(this.redeemError)
          .fontSize(13)
          .fontColor(KIDS_DANGER)
        Text('知道了')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .width('100%')
          .height(46)
          .textAlign(TextAlign.Center)
          .borderRadius(999)
          .backgroundColor(KIDS_ACCENT)
          .onClick((): void => {
            this.showConfirmSheet = false
          })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 18, bottom: 28 })
  }
```

import 区补齐：GiftModels import 加 `canAffordGift, shortfallFor`；KidsBrandTokens import 加 `KIDS_DANGER`。

- [ ] **Step 4: 编译验证 + 人工冒烟**

构建命令同上，Expected: PASS。人工冒烟：点礼物 → 确认 sheet → 兑换 → 成功态显示领取码 → 返回主屏药丸数值减少（Review Focus 5）→ 再进商城余额正确。余额不足礼物显示"还差 N 颗"且确认按钮置灰。

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/pages/GiftShopPage.ets
git commit -m "feat: 礼物兑换确认 sheet + 成功领取码展示"
```

---

### Task 9: GiftRecordsPage 我的兑换 + 家长门核销

**Files:**
- Create: `entry/src/main/ets/pages/GiftRecordsPage.ets`
- Modify: `entry/src/main/resources/base/profile/router_map.json`（+1 条）

**Interfaces:**
- Consumes: Task 4（`getRedemptions`/`markRedemptionPicked`）、Task 6（`ParentalGateSheet` gateOnly）、Task 1（`GIFT_STATUS_PENDING`/`GIFT_STATUS_PICKED`/`getGiftCategoryMeta`）、`utils/KidsSubjectUtils` 的 `formatDateLabel`/`formatHourMinute`
- Produces: 路由名 `'GiftRecordsPage'` + `GiftRecordsPageBuilder`

- [ ] **Step 1: 注册路由**

`router_map.json` 数组加：

```json
    {
      "name": "GiftRecordsPage",
      "pageSourceFile": "src/main/ets/pages/GiftRecordsPage.ets",
      "buildFunction": "GiftRecordsPageBuilder"
    }
```

- [ ] **Step 2: 实现 GiftRecordsPage**

`entry/src/main/ets/pages/GiftRecordsPage.ets` 全文：

```typescript
import { GiftRedemptionRow, GIFT_STATUS_PENDING, GIFT_STATUS_PICKED, getGiftCategoryMeta } from '../models/GiftModels'
import { getGiftShopService } from '../services/GiftShopService'
import { ParentalGateSheet } from '../components/kids/ParentalGateSheet'
import {
  KIDS_BG, KIDS_SURFACE, KIDS_FG, KIDS_MUTED, KIDS_SUBTLE, KIDS_BORDER,
  KIDS_ACCENT, KIDS_STAR, KIDS_DANGER, KIDS_ON_GOLD
} from '../components/kids/KidsBrandTokens'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'
import { formatDateLabel, formatHourMinute } from '../utils/KidsSubjectUtils'

let giftRecordsPagePathStack: NavPathStack | null = null

/**
 * 我的兑换（spec §5.3）：兑换记录列表（快照 + 领取码 + 状态）。
 * 「家长核销」走 ParentalGateSheet(gateOnly)——孩子答对也不产生 onPassed 之外的副作用，
 * 通过后 markRedemptionPicked。空态 CTA 去商城。
 */
@ComponentV2
struct GiftRecordsPage {
  @Local records: GiftRedemptionRow[] = []
  @Local loaded: boolean = false
  @Local showGateSheet: boolean = false
  /** 待核销的记录 id（gate 通过后使用；'' = 无） */
  @Local pendingPickId: string = ''

  private get topInsetVp(): number {
    return px2vp(getAppUiState().topAvoidHeight)
  }

  aboutToAppear(): void {
    this.loadRecords()
  }

  private loadRecords(): void {
    getGiftShopService().getRedemptions().then((rows: GiftRedemptionRow[]): void => {
      this.records = rows
      this.loaded = true
    }).catch((): void => {
      this.records = []
      this.loaded = true
    })
  }

  private goBack(): void {
    if (giftRecordsPagePathStack !== null && giftRecordsPagePathStack.size() > 0) {
      giftRecordsPagePathStack.pop()
    }
  }

  private goShop(): void {
    if (giftRecordsPagePathStack !== null) {
      giftRecordsPagePathStack.pushPath({ name: 'GiftShopPage' })
    }
  }

  private statusLabel(row: GiftRedemptionRow): string {
    return row.status === GIFT_STATUS_PICKED ? '已领取' : '待领取'
  }

  private timeLabel(row: GiftRedemptionRow): string {
    return `${formatDateLabel(row.createdAt)} ${formatHourMinute(row.createdAt)}`
  }

  private openGate(row: GiftRedemptionRow): void {
    this.pendingPickId = row.id
    this.showGateSheet = true
  }

  private handleGatePassed(): void {
    this.showGateSheet = false
    if (this.pendingPickId === '') {
      return
    }
    const pickId: string = this.pendingPickId
    this.pendingPickId = ''
    getGiftShopService().markRedemptionPicked(pickId).then((): void => {
      this.loadRecords()
    }).catch((): void => {
      this.loadRecords()
    })
  }

  @Builder
  TopBar() {
    Row({ space: 8 }) {
      Image($rawfile('kids/chevron.svg'))
        .width(20).height(20)
        .rotate({ angle: 180 })
        .onClick((): void => {
          this.goBack()
        })
      Text('我的兑换')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_FG)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topInsetVp + 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  EmptyState() {
    Column({ space: 10 }) {
      Image($rawfile('kids/gift_other.svg')).width(56).height(56).opacity(0.6)
      Text('还没有兑换过礼物')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(KIDS_FG)
      Text('攒够星星后，去商城挑一件喜欢的吧')
        .fontSize(12)
        .fontColor(KIDS_MUTED)
      Text('去逛星星商城')
        .fontSize(13.5)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .padding({ left: 22, right: 22, top: 12, bottom: 12 })
        .borderRadius(999)
        .backgroundColor(KIDS_ACCENT)
        .onClick((): void => {
          this.goShop()
        })
    }
    .width('100%')
    .padding({ top: 80 })
  }

  @Builder
  RecordCard(row: GiftRedemptionRow) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column() {
          Image($rawfile(getGiftCategoryMeta(row.category).iconPath)).width(24).height(24)
        }
        .width(44).height(44)
        .borderRadius(14)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(withColorAlpha(getGiftCategoryMeta(row.category).tint, '26'))

        Column({ space: 2 }) {
          Text(row.giftName)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_FG)
          Text(`${this.timeLabel(row)} · ${row.priceStars} 颗`)
            .fontSize(11)
            .fontColor(KIDS_MUTED)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.statusLabel(row))
          .fontSize(10.5)
          .fontWeight(FontWeight.Medium)
          .fontColor(row.status === GIFT_STATUS_PICKED ? '#FFFFFF' : KIDS_ON_GOLD)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(999)
          .backgroundColor(row.status === GIFT_STATUS_PICKED ? '#22C55E' : KIDS_STAR)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Column({ space: 3 }) {
          Text('领取码')
            .fontSize(10)
            .fontColor(KIDS_SUBTLE)
          Text(row.redeemCode)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_FG)
            .letterSpacing(5)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (row.status === GIFT_STATUS_PENDING) {
          Text('家长核销')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(KIDS_DANGER)
            .padding({ left: 14, right: 14, top: 9, bottom: 9 })
            .borderRadius(999)
            .border({ width: 1.5, color: withColorAlpha(KIDS_DANGER, '55') })
            .accessibilityText(`家长验证后，把${row.giftName}标记为已领取`)
            .onClick((): void => {
              this.openGate(row)
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(14)
    .margin({ bottom: 12 })
    .borderRadius(19)
    .backgroundColor(KIDS_SURFACE)
    .border({ width: 1, color: KIDS_BORDER })
    .shadow({ radius: 8, color: '#1424211C', offsetY: 3 })
  }

  build() {
    Column() {
      this.TopBar()
      Scroll() {
        Column({ space: 12 }) {
          if (this.loaded && this.records.length === 0) {
            this.EmptyState()
          }
          ForEach(this.records, (row: GiftRedemptionRow): void => {
            this.RecordCard(row)
          }, (row: GiftRedemptionRow): string => `${row.id}_${row.status}`)
          if (this.records.length > 0) {
            Text('到爸爸妈妈这里出示领取码，兑现后由家长标记「已领取」')
              .fontSize(11)
              .fontColor(KIDS_SUBTLE)
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      Column()
        .width(0)
        .height(0)
        .bindSheet($$this.showGateSheet, this.GateSheetBuilder(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          preferType: SheetType.BOTTOM,
          onDisappear: (): void => {
            this.showGateSheet = false
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(KIDS_BG)
  }

  @Builder
  GateSheetBuilder() {
    ParentalGateSheet({
      gateOnly: true,
      onPassed: (): void => {
        this.handleGatePassed()
      },
      onCancelled: (): void => {
        this.showGateSheet = false
      }
    })
  }
}

@Builder
export function GiftRecordsPageBuilder(_name: string, _param: Object) {
  NavDestination() {
    GiftRecordsPage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    giftRecordsPagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (giftRecordsPagePathStack !== null && giftRecordsPagePathStack.size() > 0) {
      giftRecordsPagePathStack.pop()
    }
    return true
  })
}
```

注意核对 `formatHourMinute` 确实从 `utils/KidsSubjectUtils.ets` 导出（KidsSubjectUtils.test.ets 有 import 它，确认存在）；若实际导出于 `utils/DateFormatUtils.ets`，以实际为准改 import。

- [ ] **Step 3: 编译验证 + 人工冒烟**

构建命令同上，Expected: PASS。人工冒烟：商城兑一件 → 「去查看我的兑换」→ 记录出现（待领取 + 领取码）→ 点「家长核销」→ 算术门 → 答对 → 状态翻转「已领取」、核销按钮消失；商城「我的兑换」徽标数减 1。孩子答错只会换题。

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/pages/GiftRecordsPage.ets entry/src/main/resources/base/profile/router_map.json
git commit -m "feat: 我的兑换记录页 + 家长门核销"
```

---

### Task 10: GiftManagePage 礼物管理 + 设置入口

**Files:**
- Create: `entry/src/main/ets/pages/GiftManagePage.ets`
- Modify: `entry/src/main/ets/config/SettingsRouteName.ets`（+1）
- Modify: `entry/src/main/resources/base/profile/router_map.json`（+1 条）
- Modify: `entry/src/main/resources/base/element/string.json`（+2 条）
- Modify: `entry/src/main/ets/components/index/IndexSettingsPanel.ets`（+1 菜单行 + 1 @Event）
- Modify: `entry/src/main/ets/pages/Index.ets`（+1 接线）

**Interfaces:**
- Consumes: Task 4（`getGiftsForManage`/`addCustomGift`/`updateCustomGift`/`deleteCustomGift`）、Task 1（`GIFT_CATEGORIES`/`getGiftCategoryMeta`）
- Produces: `SettingsRouteName.GIFT_MANAGE`；设置 → 学习分组 → 「星星礼物管理」

- [ ] **Step 1: 路由名 + 路由表 + 字符串资源**

`config/SettingsRouteName.ets` `LEARNING_DAILY_EVALUATION` 行后加：

```typescript
  GIFT_MANAGE = 'GiftManagePage',
```

`router_map.json` 加：

```json
    {
      "name": "GiftManagePage",
      "pageSourceFile": "src/main/ets/pages/GiftManagePage.ets",
      "buildFunction": "GiftManagePageBuilder"
    }
```

`resources/base/element/string.json` 任意相邻学习组条目旁（如 `learning_daily_evaluation_desc` 后）加：

```json
    {
      "name": "gift_manage_title",
      "value": "星星礼物管理"
    },
    {
      "name": "gift_manage_desc",
      "value": "配置孩子可用星星兑换的礼物"
    },
```

- [ ] **Step 2: 实现 GiftManagePage**

`entry/src/main/ets/pages/GiftManagePage.ets` 全文（成人壳常规皮肤，自绘简单标题栏——Global Constraints 已注偏差理由）：

```typescript
import { GiftItem, GIFT_CATEGORIES, getGiftCategoryMeta } from '../models/GiftModels'
import { getGiftShopService } from '../services/GiftShopService'
import { getAppUiState } from '../state/AppUiState'
import { withColorAlpha } from '../utils/ColorAlphaUtils'

let giftManagePagePathStack: NavPathStack | null = null

/**
 * 星星礼物管理（spec §6，成人壳设置入口）：内置礼物只读列表 + 自定义礼物 CRUD。
 * 内置礼物（is_builtin=1）无编辑/删除入口（服务层二次守卫）；
 * 兑换流水使用快照字段，删除自定义礼物不影响历史记录。
 */
@ComponentV2
struct GiftManagePage {
  @Local gifts: GiftItem[] = []
  /** 表单模式: 'hidden' | 'add' | 'edit' */
  @Local formMode: string = 'hidden'
  @Local editingId: string = ''
  @Local formName: string = ''
  @Local formCategory: string = GIFT_CATEGORIES[4]
  @Local formPrice: string = ''
  @Local formError: string = ''
  /** 删除二次确认目标 id（'' = 无） */
  @Local confirmDeleteId: string = ''

  private get topInsetVp(): number {
    return px2vp(getAppUiState().topAvoidHeight)
  }

  private get themeBackground(): string {
    return getAppUiState().themeBackground
  }

  private get themeSurface(): string {
    return getAppUiState().themeSurface
  }

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }

  private get textPrimary(): string {
    return getAppUiState().themeTextPrimary
  }

  private get textSecondary(): string {
    return getAppUiState().themeTextSecondary
  }

  aboutToAppear(): void {
    this.loadGifts()
  }

  private loadGifts(): void {
    getGiftShopService().getGiftsForManage().then((gifts: GiftItem[]): void => {
      this.gifts = gifts
    }).catch((): void => {
      this.gifts = []
    })
  }

  private builtinGifts(): GiftItem[] {
    return this.gifts.filter((gift: GiftItem): boolean => gift.isBuiltin)
  }

  private customGifts(): GiftItem[] {
    return this.gifts.filter((gift: GiftItem): boolean => !gift.isBuiltin)
  }

  private categoryOptions(): SelectOption[] {
    const options: SelectOption[] = []
    for (let i = 0; i < GIFT_CATEGORIES.length; i++) {
      const option: SelectOption = { value: getGiftCategoryMeta(GIFT_CATEGORIES[i]).label }
      options.push(option)
    }
    return options
  }

  private categoryIndex(category: string): number {
    for (let i = 0; i < GIFT_CATEGORIES.length; i++) {
      if (GIFT_CATEGORIES[i] === category) {
        return i
      }
    }
    return GIFT_CATEGORIES.length - 1
  }

  private openAddForm(): void {
    this.formMode = 'add'
    this.editingId = ''
    this.formName = ''
    this.formCategory = GIFT_CATEGORIES[4]
    this.formPrice = ''
    this.formError = ''
  }

  private openEditForm(gift: GiftItem): void {
    this.formMode = 'edit'
    this.editingId = gift.id
    this.formName = gift.name
    this.formCategory = gift.category
    this.formPrice = `${gift.priceStars}`
    this.formError = ''
  }

  private hideForm(): void {
    this.formMode = 'hidden'
  }

  private saveForm(): void {
    const name: string = this.formName.trim()
    const price: number = Math.floor(Number(this.formPrice))
    if (name.length === 0) {
      this.formError = '请填写礼物名称'
      return
    }
    if (!Number.isFinite(price) || price < 1) {
      this.formError = '星星价格至少为 1'
      return
    }
    if (this.formMode === 'add') {
      getGiftShopService().addCustomGift(name, this.formCategory, price).then((ok: boolean): void => {
        if (ok) {
          this.hideForm()
          this.loadGifts()
        } else {
          this.formError = '保存失败，稍后再试'
        }
      }).catch((): void => {
        this.formError = '保存失败，稍后再试'
      })
    } else {
      getGiftShopService().getGiftsForManage().then((all: GiftItem[]): void => {
        let target: GiftItem | null = null
        for (let i = 0; i < all.length; i++) {
          if (all[i].id === this.editingId) {
            target = all[i]
            break
          }
        }
        if (target === null) {
          this.formError = '礼物不存在'
          return
        }
        const updated: GiftItem = {
          id: target.id, name: name, category: this.formCategory, priceStars: price,
          isBuiltin: target.isBuiltin, enabled: target.enabled, sortOrder: target.sortOrder
        }
        getGiftShopService().updateCustomGift(updated).then((ok: boolean): void => {
          if (ok) {
            this.hideForm()
            this.loadGifts()
          } else {
            this.formError = '保存失败（内置礼物不可编辑）'
          }
        }).catch((): void => {
          this.formError = '保存失败，稍后再试'
        })
      }).catch((): void => {
        this.formError = '加载失败，稍后再试'
      })
    }
  }

  private deleteCustom(id: string): void {
    this.confirmDeleteId = ''
    getGiftShopService().deleteCustomGift(id).then((ok: boolean): void => {
      if (ok) {
        this.loadGifts()
      }
    }).catch((): void => {
      // 静默失败，列表保持原状
    })
  }

  @Builder
  TopBar() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(20)
        .fontColor([this.textPrimary])
        .onClick((): void => {
          if (giftManagePagePathStack !== null && giftManagePagePathStack.size() > 0) {
            giftManagePagePathStack.pop()
          }
        })
      Text($r('app.string.gift_manage_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topInsetVp + 10, bottom: 10 })
  }

  @Builder
  GiftRow(gift: GiftItem, isCustom: boolean) {
    Row({ space: 12 }) {
      Column() {
        Image($rawfile(getGiftCategoryMeta(gift.category).iconPath)).width(22).height(22)
      }
      .width(40).height(40)
      .borderRadius(12)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(withColorAlpha(getGiftCategoryMeta(gift.category).tint, '1A'))

      Column({ space: 2 }) {
        Row({ space: 6 }) {
          Text(gift.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.textPrimary)
          if (!isCustom) {
            Text('内置')
              .fontSize(9.5)
              .fontColor(this.textSecondary)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(6)
              .backgroundColor(withColorAlpha(this.themePrimary, '14'))
          }
        }
        .alignItems(VerticalAlign.Center)
        Text(`${getGiftCategoryMeta(gift.category).label} · ${gift.priceStars} 颗`)
          .fontSize(11.5)
          .fontColor(this.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (isCustom) {
        Text('编辑')
          .fontSize(12.5)
          .fontColor(this.themePrimary)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .onClick((): void => {
            this.openEditForm(gift)
          })
        Text(this.confirmDeleteId === gift.id ? '确认删除？' : '删除')
          .fontSize(12.5)
          .fontColor(this.confirmDeleteId === gift.id ? '#EF4444' : this.textSecondary)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .onClick((): void => {
            if (this.confirmDeleteId === gift.id) {
              this.deleteCustom(gift.id)
            } else {
              this.confirmDeleteId = gift.id
            }
          })
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor(this.themeSurface)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  FormSection() {
    Column({ space: 10 }) {
      Row() {
        Text(this.formMode === 'add' ? '添加礼物' : '编辑礼物')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textPrimary)
          .layoutWeight(1)
        Text('取消')
          .fontSize(12.5)
          .fontColor(this.textSecondary)
          .onClick((): void => {
            this.hideForm()
          })
      }
      .width('100%')

      TextInput({ text: this.formName, placeholder: '礼物名称（如：冰淇淋一支）' })
        .fontSize(14)
        .height(44)
        .onChange((value: string): void => {
          this.formName = value
        })

      Select(this.categoryOptions())
        .selected(this.categoryIndex(this.formCategory))
        .value(getGiftCategoryMeta(this.formCategory).label)
        .fontColor(this.textPrimary)
        .font({ size: 14 })
        .width('100%')
        .onSelect((index: number): void => {
          this.formCategory = GIFT_CATEGORIES[index]
        })

      TextInput({ text: this.formPrice, placeholder: '星星价格（整数，如 50）' })
        .fontSize(14)
        .height(44)
        .type(InputType.NUMBER_DECIMAL)
        .onChange((value: string): void => {
          this.formPrice = value
        })

      if (this.formError.length > 0) {
        Text(this.formError)
          .fontSize(12)
          .fontColor('#EF4444')
      }

      Button('保存', { type: ButtonType.Capsule })
        .width('100%')
        .height(44)
        .fontSize(14.5)
        .backgroundColor(this.themePrimary)
        .onClick((): void => {
          this.saveForm()
        })
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(this.themeSurface)
  }

  build() {
    Column() {
      this.TopBar()
      Scroll() {
        Column({ space: 12 }) {
          if (this.formMode !== 'hidden') {
            this.FormSection()
          } else {
            Button('＋ 添加自定义礼物', { type: ButtonType.Capsule })
              .width('100%')
              .height(44)
              .fontSize(14)
              .backgroundColor(this.themePrimary)
              .onClick((): void => {
                this.openAddForm()
              })
          }

          Text('内置礼物（只读）')
            .fontSize(12)
            .fontColor(this.textSecondary)
            .width('100%')
          ForEach(this.builtinGifts(), (gift: GiftItem): void => {
            this.GiftRow(gift, false)
          }, (gift: GiftItem): string => `builtin_${gift.id}`)

          Text('自定义礼物')
            .fontSize(12)
            .fontColor(this.textSecondary)
            .width('100%')
          if (this.customGifts().length === 0) {
            Text('还没有自定义礼物，点上方按钮添加')
              .fontSize(12)
              .fontColor(this.textSecondary)
              .width('100%')
              .padding(12)
          }
          ForEach(this.customGifts(), (gift: GiftItem): void => {
            this.GiftRow(gift, true)
          }, (gift: GiftItem): string => `custom_${gift.id}_${gift.name}_${gift.priceStars}`)

          Text('兑换记录使用礼物快照，编辑或删除不会影响已兑换的记录')
            .fontSize(11)
            .fontColor(this.textSecondary)
            .width('100%')
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 24 })
        .constraintSize({ minWidth: 0 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.themeBackground)
    .constraintSize({ minWidth: 0 })
  }
}

@Builder
export function GiftManagePageBuilder(_name: string, _param: Object) {
  NavDestination() {
    GiftManagePage()
  }
  .hideTitleBar(true)
  .hideBackButton(true)
  .onReady((context: NavDestinationContext) => {
    giftManagePagePathStack = context.pathStack
  })
  .onBackPressed((): boolean => {
    if (giftManagePagePathStack !== null && giftManagePagePathStack.size() > 0) {
      giftManagePagePathStack.pop()
    }
    return true
  })
}
```

实现时核对 `getAppUiState()` 的文字色 getter 实名（`themeTextPrimary`/`themeTextSecondary` 若不存在，用 LearningProfilePage.ets:102-110 同款 getter 实名替换，如 `textPrimary`/`textSecondary`——以 `state/AppUiState.ets` 实际字段为准）。`SelectOption` 为 ArkUI 内置类型，无需 import。

- [ ] **Step 3: 设置菜单接线**

`components/index/IndexSettingsPanel.ets`：

1. `@Event onOpenLearningDailyEvaluation`（行 55 附近）后加：

```typescript
  @Event onOpenGiftManage: () => void = () => {}
```

2. `buildGroups()` 的 `learningItems` 数组中 `LEARNING_DAILY_EVALUATION` 条目（行 118-125）后加：

```typescript
      {
        key: SettingsRouteName.GIFT_MANAGE,
        icon: $r('sys.symbol.gift'),
        title: $r('app.string.gift_manage_title'),
        subtitle: $r('app.string.gift_manage_desc'),
        action: (): void => { this.onOpenGiftManage() }
      } as SettingsListItemModel
```

`import { SettingsRouteName }` 已存在于该文件。**symbol 验证**：`sys.symbol.gift` 若编译报资源不存在，按序换 `$r('sys.symbol.bag')` → `$r('sys.symbol.cart')` → `$r('sys.symbol.tag')`，取第一个编译通过的。

`pages/Index.ets` 设置面板实例化块（`onOpenLearningDailyEvaluation` 接线，`Index.ets:5121-5123`）后加：

```typescript
      onOpenGiftManage: (): void => {
        this.openSettingsDestination(SettingsRouteName.GIFT_MANAGE)
      },
```

- [ ] **Step 4: 编译验证 + 人工冒烟**

构建命令同上，Expected: PASS。人工冒烟：成人壳设置 → 学习分组 → 星星礼物管理 → 添加自定义礼物（名称+分类+价格）→ 商城可见；编辑改价 → 商城价格更新；删除 → 商城消失；内置礼物行无编辑/删除入口。

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/pages/GiftManagePage.ets entry/src/main/ets/config/SettingsRouteName.ets entry/src/main/resources/base/profile/router_map.json entry/src/main/resources/base/element/string.json entry/src/main/ets/components/index/IndexSettingsPanel.ets entry/src/main/ets/pages/Index.ets
git commit -m "feat: 礼物管理页 + 设置入口（内置只读 + 自定义 CRUD）"
```

---

### Task 11: 全量验证 + 收尾

**Files:**
- 无新文件；只读验证

**Interfaces:**
- Consumes: 全部前序任务

- [ ] **Step 1: 干净构建**

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw clean --mode module -p product=default
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
  --mode module -p product=default -p buildMode=debug
```

Expected: PASS，产物 `entry/build/default/outputs/default/entry-default-signed.hap`。

- [ ] **Step 2: 触点核对（grep 验证）**

```bash
# 红线：三个文件不得被本特性改动（最后一个触碰它们的提交应早于特性首个提交 feat: GiftModels）
git log --oneline -3 -- entry/src/main/ets/models/StarEventModels.ets entry/src/main/ets/config/BuiltinTools.ets entry/src/main/ets/services/ToolExecutionService.ets
# 路由齐全
grep -c "GiftShopPage\|GiftRecordsPage\|GiftManagePage" entry/src/main/resources/base/profile/router_map.json   # ≥3
# 内置种子挂到 createTables 流程
grep -n "ensureBuiltinGifts" entry/src/main/ets/services/DatabaseService.ets   # ≥2 处（定义+调用）
```

Expected: 第一条最新的提交不是本特性的任何提交（特性提交信息见各 Task 的 Commit 步骤），后两条命中。

- [ ] **Step 3: 端到端人工清单（DevEco 运行，逐项勾选）**

1. 主屏星星药丸显示可用余额（非累计获得——先用历史数据对账），点击进商城
2. 商城余额 hero「可换 N 件」与网格置灰数量一致
3. 兑换成功 → 领取码展示 → 主屏药丸余额减少（Review Focus 5）
4. 余额不足礼物置灰 +「还差 N 颗」，确认按钮置灰
5. 我的兑换：待领取 → 家长核销（算术门）→ 已领取；商城徽标数同步
6. 设置 → 星星礼物管理：内置 12 条只读、自定义 CRUD 生效
7. 编辑/删除已兑换礼物 → 兑换记录快照不变（Review Focus 1）
8. 默认家长门（主屏家长入口）行为不变：过门仍进概览并退出儿童模式（Review Focus 4）
9. 杀进程重启：gifts 表不重复种子、余额/记录/状态均持久

- [ ] **Step 4: 最终提交（如有修正）**

```bash
git add -A
git commit -m "chore: 星星礼物商城收尾验证修正"
```

（无修正则跳过。）
