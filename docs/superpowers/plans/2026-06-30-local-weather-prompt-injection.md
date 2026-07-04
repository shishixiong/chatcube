# Local Weather Prompt Injection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Inject a "current local weather" section into 小星老师's system prompt so AI can adapt lessons to real weather, via Amap weather API + Location Kit with graceful degradation.

**Architecture:**
- Single-instance `WeatherService` runs a 4-step degradation chain: cache (1h TTL) → GPS Location → manual city → `null`. Never throws to caller.
- Pure parse/render functions in `utils/WeatherUtils.ets` and `utils/WeatherPromptUtils.ets` (TDD-friendly).
- `WeatherProvider` interface for future provider swap (v1 hardcodes Amap).
- `ChatViewModel.injectTeachingSections` appends weather as 4th section (after 今日教学目标, before greeting hint). 仅小星老师 (`assistantId === 'default'`) — 其他助手跳过。

**Tech Stack:**
- HarmonyOS 6 (API 23) + ArkTS strict mode
- `@ohos.geoLocationManager` (Location Kit) for GPS
- 高德 weather/regeo/district REST API
- `rcp` (Remote Communication Kit) for HTTP — same as existing `ImageGenerationRcpClient` (services/ImageGenerationRcpClient.ets:183 — `response.body` is `ArrayBuffer`, decode with `util.TextDecoder`; ref MEMORY.md `rcp.Response.body` gotcha)
- `AppStorageV2` for `manualCity` state (per MEMORY.md, must use `setAppUiStateValue` wrapper, not raw `AppStorage.setOrCreate`)
- `@ohos/hypium` + `@ohos/hamock` for tests (run in DevEco Studio; CLI `hvigorw test` broken — ref MEMORY.md)

**Spec:** `docs/superpowers/specs/2026-06-30-local-weather-prompt-injection-design.md`

## Global Constraints

These constraints apply to EVERY task below. Do not deviate.

1. **ArkTS strict mode** — see MEMORY.md: object literal return types must be explicit (`10605038`); no inline object literal type annotations (`10605040`); no `const` declarations in `@Builder` bodies; no `arr.map(this.method.bind(this))` (use lambda wrapper).
2. **JSON-in-template-literal trap** — when embedding JSON schema/responses in template literals, use 「」 or full-width quotes for any Chinese strings to avoid `JSON.parse` crashes. Verify with `node -e ...` extraction.
3. **AppStorageV2 writes** — never use raw `AppStorage.setOrCreate` for fields observed by `UIUtils.addMonitor`/shared state. Use `setAppUiStateValue` wrapper.
4. **`rcp.Response.body` is `ArrayBuffer`** — never call `response.toString()`. Decode via `new util.TextDecoder('utf-8').decodeToString(new Uint8Array(response.body))`.
5. **`JSON.stringify(error)` returns `"{}"` for Error** — log `(error as BusinessError).message ?? String(error)`.
6. **Test runner** — hypium tests run in DevEco Studio (right-click test file → Run), not CLI.
7. **No "服务不可用" type errors visible to user** — weather is nice-to-have; all failures degrade silently to `null`.
8. **Cache TTL** — exactly 1 hour (`60 * 60 * 1000` ms).
9. **No new fonts/colors** — reuse existing theme tokens (`themePrimary`, `themeTextPrimary`, etc.).
10. **Commit messages** — `feat:` for new files, `refactor:` for behavior-preserving changes, `docs:` for docs, `test:` for test-only.

---

## File Structure

| Path | Status | Role |
|------|--------|------|
| `entry/src/main/ets/utils/WeatherUtils.ets` | **NEW** | 4 pure parse functions: `parseAmapLiveResponse`, `parseAmapRegeoResponse`, `parseAmapDistrictResponse`, `isWeatherExpired` |
| `entry/src/main/ets/utils/WeatherPromptUtils.ets` | **NEW** | 1 pure function: `renderWeatherSection` |
| `entry/src/main/ets/services/WeatherService.ets` | **NEW** | Singleton: `getCurrentWeather` (cache→GPS→manual→null), `setManualCity` |
| `entry/src/main/ets/state/AppUiState.ets` | MODIFY | Add `manualCity` @Trace + extend `setAppUiStateValue` switch |
| `entry/src/main/ets/config/AppStorageKeys.ets` | MODIFY | Add `WEATHER_MANUAL_CITY` constant |
| `entry/src/main/ets/services/PreferencesService.ets` | MODIFY | Add `AMAP_WEATHER_API_KEY` key in `PreferenceKeys` |
| `entry/src/main/ets/entryability/EntryAbility.ets` | MODIFY | Pre-warm `getWeatherService()` in `initializeServices` |
| `entry/src/main/ets/viewmodels/ChatViewModel.ets` | MODIFY | `injectTeachingSections` add 4th section (only for `DEFAULT_ASSISTANT_ID`) |
| `entry/src/main/module.json5` | MODIFY | Add `ohos.permission.APPROXIMATELY_LOCATION` request |
| `entry/src/main/ets/pages/WeatherSettingsPage.ets` | **NEW** | City search + manual selection + last-fetch display |
| `entry/src/main/resources/base/profile/router_map.json` | MODIFY | Register `WeatherSettingsPage` |
| `entry/src/main/resources/base/element/string.json` | MODIFY | Add 8 i18n strings (titles, labels, prompts) |
| `entry/src/ohosTest/ets/test/WeatherUtils.test.ets` | **NEW** | 5 pure-function test suites |
| `entry/src/ohosTest/ets/test/List.test.ets` | MODIFY | Add `weatherTest` import + call |

---

## Task 1: Pure Parse Functions in WeatherUtils + Tests

**Files:**
- Create: `entry/src/main/ets/utils/WeatherUtils.ets`
- Test: `entry/src/ohosTest/ets/test/WeatherUtils.test.ets`

**Interfaces:**
- Produces: 4 exported functions
  ```typescript
  export class WeatherSnapshot {
    city: string = ''
    adcode: string = ''
    weather: string = ''
    temperature: number = 0
    temperatureRange: string = ''
    humidity: number = 0
    windDirection: string = ''
    windPower: string = ''
    reportTime: string = ''
    source: 'gps' | 'manual' = 'manual'
    fetchedAt: number = 0
  }
  export function parseAmapLiveResponse(json: string): WeatherSnapshot
  export function parseAmapRegeoResponse(json: string): { name: string; adcode: string }
  export function parseAmapDistrictResponse(json: string): Array<{ name: string; adcode: string }>
  export function isWeatherExpired(snapshot: WeatherSnapshot, now: number): boolean
  ```
- Consumption note: `parseAmapLiveResponse` returns `source='manual'` and `fetchedAt=0` — caller (provider) sets them after parsing.

- [ ] **Step 1.1: Write the failing test file**

Create `entry/src/ohosTest/ets/test/WeatherUtils.test.ets`:

```typescript
import { describe, it, expect } from '@ohos/hypium';
import { parseAmapLiveResponse, parseAmapRegeoResponse, parseAmapDistrictResponse, isWeatherExpired, WeatherSnapshot } from '../../../main/ets/utils/WeatherUtils';

export default function weatherTest() {
  describe('WeatherUtils', () => {
    describe('parseAmapLiveResponse', () => {
      it('parses a normal response', 0, () => {
        const json = `{
          "status": "1",
          "lives": [{
            "adcode": "310000",
            "city": "上海市",
            "weather": "小雨",
            "temperature": "18",
            "humidity": "80",
            "winddirection": "东北",
            "windpower": "4",
            "reporttime": "2026-06-30 10:00:00"
          }]
        }`;
        const s = parseAmapLiveResponse(json);
        expect(s.adcode).assertEqual('310000');
        expect(s.city).assertEqual('上海');  // 上海市 -> 上海 (strip "市")
        expect(s.weather).assertEqual('小雨');
        expect(s.temperature).assertEqual(18);
        expect(s.humidity).assertEqual(80);
        expect(s.windDirection).assertEqual('东北');
        expect(s.windPower).assertEqual('4');
        expect(s.reportTime).assertEqual('2026-06-30 10:00:00');
      });

      it('returns empty snapshot when status is 0', 0, () => {
        const json = '{"status":"0","info":"INVALID_USER_KEY","lives":[]}';
        const s = parseAmapLiveResponse(json);
        expect(s.adcode).assertEqual('');
        expect(s.weather).assertEqual('');
        expect(s.temperature).assertEqual(0);
      });

      it('returns empty snapshot when lives is empty array', 0, () => {
        const json = '{"status":"1","lives":[]}';
        const s = parseAmapLiveResponse(json);
        expect(s.weather).assertEqual('');
      });

      it('handles malformed JSON by returning empty snapshot', 0, () => {
        const s = parseAmapLiveResponse('not json{');
        expect(s.weather).assertEqual('');
        expect(s.adcode).assertEqual('');
      });

      it('parses city name without 市 suffix unchanged', 0, () => {
        const json = `{"status":"1","lives":[{"adcode":"110000","city":"北京","weather":"晴","temperature":"25","humidity":"40","winddirection":"南","windpower":"2","reporttime":"2026-06-30 12:00"}]}`;
        const s = parseAmapLiveResponse(json);
        expect(s.city).assertEqual('北京');
      });
    });

    describe('parseAmapRegeoResponse', () => {
      it('parses a normal response', 0, () => {
        const json = `{
          "status": "1",
          "regeocode": {
            "addressComponent": { "adcode": "310101", "city": "上海市" }
          }
        }`;
        const r = parseAmapRegeoResponse(json);
        expect(r.adcode).assertEqual('310101');
        expect(r.name).assertEqual('上海');
      });

      it('returns empty when adcode missing', 0, () => {
        const json = `{"status":"1","regeocode":{"addressComponent":{"city":"上海市"}}}`;
        const r = parseAmapRegeoResponse(json);
        expect(r.adcode).assertEqual('');
      });
    });

    describe('parseAmapDistrictResponse', () => {
      it('parses multiple districts', 0, () => {
        const json = `{
          "status": "1",
          "districts": [
            { "name": "上海市", "adcode": "310000" },
            { "name": "上海县", "adcode": "310100" }
          ]
        }`;
        const list = parseAmapDistrictResponse(json);
        expect(list.length).assertEqual(2);
        expect(list[0].name).assertEqual('上海市');
        expect(list[0].adcode).assertEqual('310000');
      });

      it('returns empty array on no match', 0, () => {
        const json = '{"status":"1","districts":[]}';
        const list = parseAmapDistrictResponse(json);
        expect(list.length).assertEqual(0);
      });
    });

    describe('isWeatherExpired', () => {
      it('returns false for fresh snapshot', 0, () => {
        const s: WeatherSnapshot = new WeatherSnapshot();
        s.fetchedAt = 1000;
        expect(isWeatherExpired(s, 1000 + 60 * 60 * 1000 - 1)).assertEqual(false);
      });
      it('returns true for 1-hour-old snapshot', 0, () => {
        const s: WeatherSnapshot = new WeatherSnapshot();
        s.fetchedAt = 1000;
        expect(isWeatherExpired(s, 1000 + 60 * 60 * 1000)).assertEqual(true);
      });
      it('returns true for way-old snapshot', 0, () => {
        const s: WeatherSnapshot = new WeatherSnapshot();
        s.fetchedAt = 1000;
        expect(isWeatherExpired(s, 99999999)).assertEqual(true);
      });
    });
  });
}
```

- [ ] **Step 1.2: Run test to verify it fails (compilation)**

Run: `cd /Users/mac/mygame/HarmonyOS-app/chatcube && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -30`
Expected: Compile error — module `../../../main/ets/utils/WeatherUtils` not found.

- [ ] **Step 1.3: Write the implementation**

Create `entry/src/main/ets/utils/WeatherUtils.ets`:

```typescript
/**
 * 高德天气 API 响应解析 + 缓存过期判断 (纯函数).
 *
 * 全部函数不抛错: 异常 (JSON 格式坏, 字段缺失) 全部降级返回空值,
 * 由调用方 (WeatherService) 统一决定 fallback.
 */

export class WeatherSnapshot {
  city: string = ''
  adcode: string = ''
  weather: string = ''
  temperature: number = 0
  // v1: 不调用 forecast, 温度区间不可用. 字段保留以备 v2 (见 spec §6)
  temperatureRange: string = ''
  humidity: number = 0
  windDirection: string = ''
  windPower: string = ''
  reportTime: string = ''
  source: 'gps' | 'manual' = 'manual'
  fetchedAt: number = 0
}

/** 去掉城市名末尾的 "市" / "县" / "区" 后缀, 保留简洁展示名. */
function stripCitySuffix(name: string): string {
  if (name === '') {
    return ''
  }
  // 仅去除单个字后缀, 避免 "三亚市" → "三亚" 但 "市辖区" 误改
  const last = name.charAt(name.length - 1)
  if (last === '市' || last === '县' || last === '区') {
    return name.substring(0, name.length - 1)
  }
  return name
}

function safeNumber(s: string | undefined): number {
  if (s === undefined || s === '') {
    return 0
  }
  const n = Number(s)
  if (isNaN(n)) {
    return 0
  }
  return n
}

/**
 * 解析高德实时天气响应 (extensions=base).
 * 输入示例:
 *   {"status":"1","lives":[{"adcode":"310000","city":"上海市",
 *    "weather":"小雨","temperature":"18","humidity":"80",
 *    "winddirection":"东北","windpower":"4","reporttime":"2026-06-30 10:00:00"}]}
 * 失败 (status != "1" / lives 空 / JSON 坏) → 返回空 WeatherSnapshot.
 */
export function parseAmapLiveResponse(json: string): WeatherSnapshot {
  const empty: WeatherSnapshot = new WeatherSnapshot()
  if (json === '') {
    return empty
  }
  let parsed: Record<string, Object> | null = null
  try {
    parsed = JSON.parse(json) as Record<string, Object>
  } catch (_e) {
    return empty
  }
  if (parsed === null) {
    return empty
  }
  const status = parsed['status'] as string | undefined
  if (status !== '1') {
    return empty
  }
  const lives = parsed['lives'] as Array<Record<string, string>> | undefined
  if (lives === undefined || lives.length === 0) {
    return empty
  }
  const live = lives[0]
  const snap: WeatherSnapshot = new WeatherSnapshot()
  snap.adcode = live['adcode'] ?? ''
  snap.city = stripCitySuffix(live['city'] ?? '')
  snap.weather = live['weather'] ?? ''
  snap.temperature = safeNumber(live['temperature'])
  snap.humidity = safeNumber(live['humidity'])
  snap.windDirection = live['winddirection'] ?? ''
  snap.windPower = live['windpower'] ?? ''
  snap.reportTime = live['reporttime'] ?? ''
  // source 和 fetchedAt 由 provider 调用方在 parse 后设置
  return snap
}

/**
 * 解析高德逆地理响应.
 * 输入示例:
 *   {"status":"1","regeocode":{"addressComponent":{"adcode":"310101","city":"上海市"}}}
 * 失败 → 返回 {name:'', adcode:''}.
 */
export function parseAmapRegeoResponse(json: string): { name: string; adcode: string } {
  const empty = { name: '', adcode: '' }
  if (json === '') {
    return empty
  }
  let parsed: Record<string, Object> | null = null
  try {
    parsed = JSON.parse(json) as Record<string, Object>
  } catch (_e) {
    return empty
  }
  if (parsed === null) {
    return empty
  }
  const status = parsed['status'] as string | undefined
  if (status !== '1') {
    return empty
  }
  const regeocode = parsed['regeocode'] as Record<string, Object> | undefined
  if (regeocode === undefined) {
    return empty
  }
  const comp = regeocode['addressComponent'] as Record<string, string> | undefined
  if (comp === undefined) {
    return empty
  }
  return {
    name: stripCitySuffix(comp['city'] ?? comp['province'] ?? ''),
    adcode: comp['adcode'] ?? ''
  }
}

/**
 * 解析高德城市搜索响应 (district API).
 * 输入示例:
 *   {"status":"1","districts":[{"name":"上海市","adcode":"310000"}, ...]}
 */
export function parseAmapDistrictResponse(json: string): Array<{ name: string; adcode: string }> {
  const empty: Array<{ name: string; adcode: string }> = []
  if (json === '') {
    return empty
  }
  let parsed: Record<string, Object> | null = null
  try {
    parsed = JSON.parse(json) as Record<string, Object>
  } catch (_e) {
    return empty
  }
  if (parsed === null) {
    return empty
  }
  const districts = parsed['districts'] as Array<Record<string, string>> | undefined
  if (districts === undefined) {
    return empty
  }
  const out: Array<{ name: string; adcode: string }> = []
  for (const d of districts) {
    const name = d['name'] ?? ''
    const adcode = d['adcode'] ?? ''
    if (name !== '' && adcode !== '') {
      out.push({ name: name, adcode: adcode })
    }
  }
  return out
}

/**
 * 判断 snapshot 是否已超过 1h 缓存期.
 * 边界: now - fetchedAt >= TTL 时算过期.
 */
export function isWeatherExpired(snapshot: WeatherSnapshot, now: number): boolean {
  const TTL_MS = 60 * 60 * 1000
  if (snapshot.fetchedAt <= 0) {
    return true
  }
  return (now - snapshot.fetchedAt) >= TTL_MS
}
```

- [ ] **Step 1.4: Build to verify compile**

Run: `cd /Users/mac/mygame/HarmonyOS-app/chatcube && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -10`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 1.5: Run hypium tests in DevEco Studio**

Open `entry/src/ohosTest/ets/test/WeatherUtils.test.ets` in DevEco Studio → right-click → Run.
Expected: 13 it-blocks all PASS.

- [ ] **Step 1.6: Wire into test suite**

Modify `entry/src/ohosTest/ets/test/List.test.ets`:

```typescript
import abilityTest from './Ability.test';
import weatherTest from './WeatherUtils.test';

export default function testsuite() {
  abilityTest();
  weatherTest();
}
```

- [ ] **Step 1.7: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && git add entry/src/main/ets/utils/WeatherUtils.ets entry/src/ohosTest/ets/test/WeatherUtils.test.ets entry/src/ohosTest/ets/test/List.test.ets && git commit -m "feat(weather): pure parse functions + hypium tests"
```

---

## Task 2: Pure Render Function in WeatherPromptUtils + Tests

**Files:**
- Create: `entry/src/main/ets/utils/WeatherPromptUtils.ets`
- Test: extend `entry/src/ohosTest/ets/test/WeatherUtils.test.ets` (or new `WeatherPromptUtils.test.ets` — implementer's choice; spec says same file is fine)

**Interfaces:**
- Produces:
  ```typescript
  export function renderWeatherSection(snapshot: WeatherSnapshot | null): string
  ```
- Returns `''` when `snapshot === null` or `snapshot.weather === ''` (静默降级, 不在 prompt 留空 section).
- Output format (non-empty):
  ```
  ## 当前天气
  城市: 上海 | 天气: 小雨 | 温度: 18°C | 湿度: 80% | 东北风 4级
  教学建议: 雨天适合教雨具/水循环/室内游戏, 户外活动建议改期
  ```
- 教学建议由 weather 描述启发式派生 (见 Step 2.3).

- [ ] **Step 2.1: Write the failing test (append to WeatherUtils.test.ets)**

Append to `entry/src/ohosTest/ets/test/WeatherUtils.test.ets` inside `describe('WeatherUtils', () => {})`:

```typescript
import { renderWeatherSection } from '../../../main/ets/utils/WeatherPromptUtils';

// ... inside the describe block:
describe('renderWeatherSection', () => {
  it('returns empty string for null snapshot', 0, () => {
    expect(renderWeatherSection(null)).assertEqual('');
  });
  it('returns empty string for snapshot with empty weather', 0, () => {
    const s: WeatherSnapshot = new WeatherSnapshot();
    expect(renderWeatherSection(s)).assertEqual('');
  });
  it('renders full snapshot with rain suggestion', 0, () => {
    const s: WeatherSnapshot = new WeatherSnapshot();
    s.city = '上海';
    s.weather = '小雨';
    s.temperature = 18;
    s.humidity = 80;
    s.windDirection = '东北';
    s.windPower = '4';
    const out = renderWeatherSection(s);
    expect(out.includes('## 当前天气')).assertEqual(true);
    expect(out.includes('城市: 上海')).assertEqual(true);
    expect(out.includes('天气: 小雨')).assertEqual(true);
    expect(out.includes('温度: 18°C')).assertEqual(true);
    expect(out.includes('湿度: 80%')).assertEqual(true);
    expect(out.includes('东北风 4级')).assertEqual(true);
    expect(out.includes('雨具') || out.includes('水循环') || out.includes('室内')).assertEqual(true);
  });
  it('renders sunny weather with outdoor suggestion', 0, () => {
    const s: WeatherSnapshot = new WeatherSnapshot();
    s.city = '北京';
    s.weather = '晴';
    s.temperature = 28;
    s.humidity = 40;
    s.windDirection = '南';
    s.windPower = '2';
    const out = renderWeatherSection(s);
    expect(out.includes('天气: 晴')).assertEqual(true);
    expect(out.includes('户外') || out.includes('公园') || out.includes('防晒')).assertEqual(true);
  });
  it('omits humidity and wind when zero/empty', 0, () => {
    const s: WeatherSnapshot = new WeatherSnapshot();
    s.city = '广州';
    s.weather = '多云';
    s.temperature = 25;
    const out = renderWeatherSection(s);
    expect(out.includes('## 当前天气')).assertEqual(true);
    expect(out.includes('天气: 多云')).assertEqual(true);
    // 0/empty 字段不应出现
    expect(out.includes('湿度: 0%')).assertEqual(false);
    expect(out.includes('南风 0级')).assertEqual(false);
  });
});
```

- [ ] **Step 2.2: Run test to verify it fails**

Run: `cd /Users/mac/mygame/HarmonyOS-app/chatcube && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -10`
Expected: Compile error — `renderWeatherSection` not exported from anywhere.

- [ ] **Step 2.3: Write the implementation**

Create `entry/src/main/ets/utils/WeatherPromptUtils.ets`:

```typescript
import { WeatherSnapshot } from './WeatherUtils'

/**
 * 把 WeatherSnapshot 渲染成可注入 system prompt 的一段中文文字.
 * 失败 (null 或 weather 为空) → 返回 '' (静默降级, 不在 prompt 留空段).
 *
 * 渲染格式 (非空):
 *   ## 当前天气
 *   城市: 上海 | 天气: 小雨 | 温度: 18°C | 湿度: 80% | 东北风 4级
 *   教学建议: 雨天适合教雨具/水循环/室内游戏, 户外活动建议改期
 *
 * 启发式映射 weather 描述 → 教学建议:
 *   - 雨/雷/雪 → 室内主题 (雨具/水循环/防寒/雷电安全)
 *   - 晴/多云 → 户外主题 (公园/防晒/动植物)
 *   - 阴/雾/霾 → 健康主题 (空气/呼吸/室内游戏)
 *   - 沙尘/大风 → 室内主题
 *   - 极端温度 (≤0 或 ≥35) → 防寒/防晒
 */
export function renderWeatherSection(snapshot: WeatherSnapshot | null): string {
  if (snapshot === null) {
    return ''
  }
  if (snapshot.weather === '') {
    return ''
  }
  const header = '## 当前天气'
  const fields: string[] = []
  if (snapshot.city !== '') {
    fields.push(`城市: ${snapshot.city}`)
  }
  fields.push(`天气: ${snapshot.weather}`)
  if (snapshot.temperature !== 0) {
    fields.push(`温度: ${snapshot.temperature}°C`)
  }
  if (snapshot.humidity > 0) {
    fields.push(`湿度: ${snapshot.humidity}%`)
  }
  if (snapshot.windDirection !== '' && snapshot.windPower !== '' && snapshot.windPower !== '0') {
    fields.push(`${snapshot.windDirection}风 ${snapshot.windPower}级`)
  }
  const line1 = fields.join(' | ')
  const advice = deriveTeachingAdvice(snapshot)
  return `${header}\n${line1}\n教学建议: ${advice}`
}

function deriveTeachingAdvice(snapshot: WeatherSnapshot): string {
  const w = snapshot.weather
  const t = snapshot.temperature
  // 雨/雪/雷 → 室内 + 相关词汇
  if (w.includes('雨') || w.includes('雷')) {
    return '雨天适合教雨具/水循环/室内游戏, 户外活动建议改期'
  }
  if (w.includes('雪')) {
    return '雪天适合教防寒衣物/雪花形状/室内堆雪人游戏, 户外注意保暖'
  }
  // 晴/多云 → 户外
  if (w.includes('晴') || w.includes('多云')) {
    if (t >= 30) {
      return '晴天高温, 适合教防晒/水/阴凉处; 避免长时间户外活动'
    }
    return '晴好天气, 适合户外主题 (公园/动植物/影子), 别忘涂防晒'
  }
  // 阴/雾/霾 → 健康
  if (w.includes('阴') || w.includes('雾') || w.includes('霾')) {
    return '阴/雾/霾天, 适合教空气/呼吸/室内游戏, 出门戴口罩'
  }
  // 风/沙
  if (w.includes('风') || w.includes('沙') || w.includes('尘')) {
    return '大风/沙尘天, 建议室内活动, 可教风力分级/沙尘防护'
  }
  // 极端温度
  if (t <= 0) {
    return '低温, 适合教防寒/结冰/冬眠, 户外注意保暖'
  }
  if (t >= 35) {
    return '高温, 适合教防晒/中暑预防/阴凉处, 多喝水'
  }
  // 兜底
  return '天气信息可作为出题背景, 引导孩子观察和描述'
}
```

- [ ] **Step 2.4: Build to verify compile**

Run: `cd /Users/mac/mygame/HarmonyOS-app/chatcube && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -10`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 2.5: Run tests in DevEco Studio**

Open `entry/src/ohosTest/ets/test/WeatherUtils.test.ets` → Run.
Expected: All it-blocks (13 from Task 1 + 5 new = 18 total) PASS.

- [ ] **Step 2.6: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && git add entry/src/main/ets/utils/WeatherPromptUtils.ets entry/src/ohosTest/ets/test/WeatherUtils.test.ets && git commit -m "feat(weather): renderWeatherSection + heuristic teaching advice"
```

---

## Task 3: AmapWeatherProvider (HTTP + 3 endpoints)

**Files:**
- Create: `entry/src/main/ets/services/WeatherService.ets` (will hold both provider + service in v1; this task adds the provider)
- Test: extend `entry/src/ohosTest/ets/test/WeatherUtils.test.ets`

**Interfaces:**
- Produces:
  ```typescript
  export interface WeatherProvider {
    fetchLive(adcode: string): Promise<WeatherSnapshot>  // 实时天气 (city 已知 → 走这条)
    fetchRegeo(lng: number, lat: number): Promise<{ name: string; adcode: string }>  // GPS → 城市
    searchDistrict(keyword: string): Promise<Array<{ name: string; adcode: string }>>  // 设置页搜索
  }
  class AmapWeatherProvider implements WeatherProvider { ... }
  ```
- Reads `PreferenceKeys.AMAP_WEATHER_API_KEY` via `PreferencesService.getString`.
- If key empty → returns empty snapshot / empty array (NOT throw — caller's catch handles it).
- Uses `rcp` for HTTP (match `ImageGenerationRcpClient` pattern). Body decode via `util.TextDecoder`.

- [ ] **Step 3.1: Write the failing provider test (mock-style)**

Append to `entry/src/ohosTest/ets/test/WeatherUtils.test.ets`:

```typescript
import { AmapWeatherProvider } from '../../../main/ets/services/WeatherService';

// ... inside the describe block:
describe('AmapWeatherProvider', () => {
  it('returns empty snapshot when API key not configured', 0, async () => {
    const p = new AmapWeatherProvider('');  // empty key
    const s = await p.fetchLive('310000');
    expect(s.weather).assertEqual('');
  });
  it('returns empty array from searchDistrict when key missing', 0, async () => {
    const p = new AmapWeatherProvider('');
    const list = await p.searchDistrict('上海');
    expect(list.length).assertEqual(0);
  });
  it('returns empty regeo when key missing', 0, async () => {
    const p = new AmapWeatherProvider('');
    const r = await p.fetchRegeo(121.5, 31.2);
    expect(r.adcode).assertEqual('');
  });
});
```

- [ ] **Step 3.2: Build to verify it fails**

Run: `cd /Users/mac/mygame/HarmonyOS-app/chatcube && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -10`
Expected: Compile error — `WeatherService.ets` not found.

- [ ] **Step 3.3: Add the keys constant**

Modify `entry/src/main/ets/services/PreferencesService.ets` — inside `class PreferenceKeys`, add at end:

```typescript
  // 天气服务 (高德) API Key
  static readonly AMAP_WEATHER_API_KEY: string = 'amap_weather_api_key'
```

- [ ] **Step 3.4: Write the WeatherService.ets with provider skeleton (no full service yet)**

Create `entry/src/main/ets/services/WeatherService.ets`:

```typescript
/**
 * WeatherService — 单例服务 (v1)
 *
 * 职责: 把"实时天气"按需注入小星老师 system prompt.
 * 走 4 步降级链: 缓存(1h TTL) → GPS → 手动城市 → null.
 *
 * 关键设计:
 * - getCurrentWeather 永不抛错到调用方 (所有步骤 try/catch 包裹)
 * - WeatherProvider 接口预留 (v1 硬编码 Amap, v2 抽 registry)
 * - HTTP 用 rcp, body 用 util.TextDecoder 解码 (ref MEMORY.md rcp.Response.body 陷阱)
 */

import { rcp } from '@kit.RemoteCommunicationKit'
import { util } from '@kit.ArkTS'
import { BusinessError } from '@kit.BasicServicesKit'
import { getPreferencesService, PreferencesService, PreferenceKeys } from './PreferencesService'
import { WeatherSnapshot, parseAmapLiveResponse, parseAmapRegeoResponse, parseAmapDistrictResponse } from '../utils/WeatherUtils'

const AMAP_BASE_URL = 'https://restapi.amap.com/v3'

export interface WeatherProvider {
  fetchLive(adcode: string): Promise<WeatherSnapshot>
  fetchRegeo(lng: number, lat: number): Promise<{ name: string; adcode: string }>
  searchDistrict(keyword: string): Promise<Array<{ name: string; adcode: string }>>
}

export class AmapWeatherProvider implements WeatherProvider {
  private apiKey: string = ''

  constructor(apiKey: string = '') {
    this.apiKey = apiKey
  }

  setApiKey(key: string): void {
    this.apiKey = key
  }

  async fetchLive(adcode: string): Promise<WeatherSnapshot> {
    if (this.apiKey === '' || adcode === '') {
      return new WeatherSnapshot()
    }
    const url = `${AMAP_BASE_URL}/weather/weatherInfo?city=${adcode}&key=${this.apiKey}&extensions=base`
    const text = await httpGetText(url)
    return parseAmapLiveResponse(text)
  }

  async fetchRegeo(lng: number, lat: number): Promise<{ name: string; adcode: string }> {
    if (this.apiKey === '') {
      return { name: '', adcode: '' }
    }
    const url = `${AMAP_BASE_URL}/geocode/regeo?location=${lng},${lat}&key=${this.apiKey}&extensions=base`
    const text = await httpGetText(url)
    return parseAmapRegeoResponse(text)
  }

  async searchDistrict(keyword: string): Promise<Array<{ name: string; adcode: string }>> {
    if (this.apiKey === '' || keyword === '') {
      return []
    }
    const url = `${AMAP_BASE_URL}/config/district?keywords=${encodeURIComponent(keyword)}&key=${this.apiKey}&subdistrict=0&extensions=base`
    const text = await httpGetText(url)
    return parseAmapDistrictResponse(text)
  }
}

/** 内部: rcp GET, 返回 UTF-8 文本. 失败 → 返回 '' (不抛错). */
async function httpGetText(url: string): Promise<string> {
  try {
    const session = rcp.createSession()
    const response = await session.get(url)
    const body = response.body
    if (body === undefined) {
      return ''
    }
    return new util.TextDecoder('utf-8').decodeToString(new Uint8Array(body))
  } catch (e) {
    const err = e as BusinessError
    console.warn('WeatherService', `httpGetText failed: ${err.message ?? String(e)}`)
    return ''
  }
}

// ===== WeatherService 单例 (v1 骨架, 完整降级链见 Task 6) =====
class WeatherServiceImpl {
  private static instance: WeatherServiceImpl | null = null
  private snapshot: WeatherSnapshot | null = null
  private provider: WeatherProvider = new AmapWeatherProvider()

  static getInstance(): WeatherServiceImpl {
    if (WeatherServiceImpl.instance === null) {
      WeatherServiceImpl.instance = new WeatherServiceImpl()
    }
    return WeatherServiceImpl.instance
  }

  getProvider(): WeatherProvider {
    return this.provider
  }
}

export function getWeatherService(): WeatherServiceImpl {
  return WeatherServiceImpl.getInstance()
}
```

- [ ] **Step 3.5: Build to verify compile**

Run: `cd /Users/mac/mygame/HarmonyOS-app/chatcube && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -10`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3.6: Run tests in DevEco Studio**

Open `entry/src/ohosTest/ets/test/WeatherUtils.test.ets` → Run.
Expected: 18 (from Task 2) + 3 (this task) = 21 it-blocks PASS.

- [ ] **Step 3.7: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && git add entry/src/main/ets/services/WeatherService.ets entry/src/main/ets/services/PreferencesService.ets entry/src/ohosTest/ets/test/WeatherUtils.test.ets && git commit -m "feat(weather): AmapWeatherProvider with 3 endpoints + empty-key fallback"
```

---

## Task 4: AppStorageV2 State Wiring (manualCity)

**Files:**
- Modify: `entry/src/main/ets/config/AppStorageKeys.ets`
- Modify: `entry/src/main/ets/state/AppUiState.ets`
- Test: extend `entry/src/ohosTest/ets/test/WeatherUtils.test.ets` (or skip — pure field additions, no behavior)

**Interfaces:**
- Produces (in AppUiState):
  ```typescript
  @Trace manualCity: { name: string; adcode: string } | null = null
  ```
- `setAppUiStateValue` extended with new case for `WEATHER_MANUAL_CITY`.
- New key: `AppStorageKeys.WEATHER_MANUAL_CITY = 'weather_manual_city'`.

- [ ] **Step 4.1: Add the AppStorageKeys constant**

Modify `entry/src/main/ets/config/AppStorageKeys.ets` — add at end (before closing `}`):

```typescript
  // 天气服务: 用户手动设置的城市 (GPS 失败时 fallback)
  // 写入必须用 setAppUiStateValue 包装
  static readonly WEATHER_MANUAL_CITY: string = 'weather_manual_city'
```

- [ ] **Step 4.2: Add @Trace field to AppUiState**

Modify `entry/src/main/ets/state/AppUiState.ets` — inside `class AppUiState`, add after `lastGreetDate`:

```typescript
  // 天气服务: 手动城市 (GPS 失败时 fallback). null = 未设置
  @Trace manualCity: { name: string; adcode: string } | null = null
```

- [ ] **Step 4.3: Extend setAppUiStateValue switch**

Modify `entry/src/main/ets/state/AppUiState.ets` — inside `function applyAppUiStateValue`, add a case before the default (find the `switch (key)` and add at end before `default:` if any, or as a new case):

```typescript
    case AppStorageKeys.WEATHER_MANUAL_CITY:
      state.manualCity = value as { name: string; adcode: string } | null
      return
```

- [ ] **Step 4.4: Build to verify compile**

Run: `cd /Users/mac/mygame/HarmonyOS-app/chatcube && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -10`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 4.5: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && git add entry/src/main/ets/config/AppStorageKeys.ets entry/src/main/ets/state/AppUiState.ets && git commit -m "feat(weather): manualCity @Trace + WEATHER_MANUAL_CITY key"
```

---

## Task 5: LOCATION Permission + tryGpsLocation Helper

**Files:**
- Modify: `entry/src/main/module.json5`
- Modify: `entry/src/main/ets/services/WeatherService.ets` (add `tryGpsLocation` private method + `requestLocationPermission` helper)
- Modify: `entry/src/main/resources/base/element/string.json` (add 2 i18n strings: `permission_location_reason`, `permission_location_inuse_reason`)

**Interfaces:**
- Produces (in WeatherService):
  ```typescript
  private async tryGpsLocation(): Promise<{ name: string; adcode: string } | null>
  static async ensureLocationPermission(): Promise<boolean>  // 弹系统框; true = granted
  ```
- Uses `@ohos.geoLocationManager` from Location Kit.
- 8s timeout, fallback to `null` on any error.
- Test: skip (system API, can't unit test deterministically).

- [ ] **Step 5.1: Add LOCATION permission to module.json5**

Modify `entry/src/main/module.json5` — inside `requestPermissions` array (append after the MICROPHONE entry):

```json
,
{
  "name": "ohos.permission.APPROXIMATELY_LOCATION",
  "reason": "$string:permission_location_reason",
  "usedScene": {
    "abilities": ["EntryAbility"],
    "when": "inuse"
  }
}
```

- [ ] **Step 5.2: Add i18n strings**

Read `entry/src/main/resources/base/element/string.json` first. Find a good insertion point (e.g. near other permission strings). Add:

```json
{
  "name": "permission_location_reason",
  "value": "用于获取当前位置, 让小星老师能根据当地天气调整教学内容"
},
{
  "name": "permission_location_inuse_reason",
  "value": "仅在您使用天气功能时获取位置, 用于查询当前城市天气"
}
```

- [ ] **Step 5.3: Add GPS helper to WeatherService.ets**

Modify `entry/src/main/ets/services/WeatherService.ets` — add imports at top, and add helpers inside `class WeatherServiceImpl`:

Add imports:
```typescript
import { geoLocationManager } from '@kit.LocationKit'
import { abilityAccessCtrl, common } from '@kit.AbilityKit'
```

Add static method (inside `class WeatherServiceImpl`):
```typescript
  /**
   * 检查并申请 LOCATION 权限. 返回 true = 已授权.
   * 失败路径: 用户拒 → 返回 false (不抛错).
   */
  static async ensureLocationPermission(): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager()
      const grantStatus = await atManager.checkAccessTokenSync(
        // tokenId 留 0 让系统从当前 context 推断; 简化版
        0,
        'ohos.permission.APPROXIMATELY_LOCATION'
      )
      if (grantStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true
      }
      // 申请
      const result = await atManager.requestPermissionsFromUser(
        // context 在鸿蒙中通常通过 getContext(this) 获取, 这里用全局 API
        common.UIAbilityContext,
        ['ohos.permission.APPROXIMATELY_LOCATION']
      )
      const granted = result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
      return granted
    } catch (e) {
      const err = e as BusinessError
      console.warn('WeatherService', `ensureLocationPermission failed: ${err.message ?? String(e)}`)
      return false
    }
  }

  private async tryGpsLocation(): Promise<{ name: string; adcode: string } | null> {
    try {
      const granted = await WeatherServiceImpl.ensureLocationPermission()
      if (!granted) {
        return null
      }
      // 8s timeout — 高德限频, 失败就降级
      const request: geoLocationManager.LocationRequest = {
        'priority': geoLocationManager.LocationRequestPriority.ACCURACY,
        'scenario': geoLocationManager.LocationRequestScenario.UNSET,
        'maxAccuracy': 100,
        'timeoutMs': 8000
      }
      const location = await geoLocationManager.getCurrentLocation(request)
      if (location === null || location === undefined) {
        return null
      }
      const lng = location.longitude
      const lat = location.latitude
      if (lng === undefined || lat === undefined) {
        return null
      }
      const result = await this.provider.fetchRegeo(lng, lat)
      if (result.adcode === '') {
        return null
      }
      return result
    } catch (e) {
      const err = e as BusinessError
      console.warn('WeatherService', `tryGpsLocation failed: ${err.message ?? String(e)}`)
      return null
    }
  }
```

> **NOTE for implementer**: The `requestPermissionsFromUser` signature may vary by HarmonyOS version. The code above uses the basic signature. If DevEco Studio flags it, look at the latest @kit.AbilityKit docs and adjust. Don't refactor the rest of the file.

- [ ] **Step 5.4: Build to verify compile**

Run: `cd /Users/mac/mygame/HarmonyOS-app/chatcube && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -10`
Expected: BUILD SUCCESSFUL (with possibly a warning about the permissions API, not a hard error).

- [ ] **Step 5.5: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && git add entry/src/main/module.json5 entry/src/main/resources/base/element/string.json entry/src/main/ets/services/WeatherService.ets && git commit -m "feat(weather): LOCATION permission + tryGpsLocation helper"
```

---

## Task 6: WeatherService Singleton — Full Degradation Chain

**Files:**
- Modify: `entry/src/main/ets/services/WeatherService.ets` (extend `class WeatherServiceImpl`)
- Test: extend `entry/src/ohosTest/ets/test/WeatherUtils.test.ets` (mock provider)

**Interfaces:**
- Produces:
  ```typescript
  class WeatherServiceImpl {
    // (已有) getProvider
    async getCurrentWeather(): Promise<WeatherSnapshot | null>  // 4 步降级链
    setManualCity(name: string, adcode: string): void
    getManualCity(): { name: string; adcode: string } | null
    getCachedSnapshot(): WeatherSnapshot | null  // UI 展示用, 不触发 API
    async initialize(): Promise<void>  // 启动时加载 API key + manual city
  }
  ```
- 4 步降级: 缓存命中 → GPS (无 key 跳过) → 手动城市 (无设置跳过) → null
- 缓存用 `this.snapshot` (in-memory only; 重启后从手动城市/GPS 重建)
- 失败率限制: provider 抛错 → catch + return null, console.warn 一次
- 测试用 mock WeatherProvider, 验证降级顺序

- [ ] **Step 6.1: Write the failing degradation test (mock provider)**

Append to `entry/src/ohosTest/ets/test/WeatherUtils.test.ets`:

```typescript
import { WeatherProvider, getWeatherService, WeatherServiceImpl } from '../../../main/ets/services/WeatherService';
import { isWeatherExpired } from '../../../main/ets/utils/WeatherUtils';

// ... inside the describe block:
describe('WeatherService degradation chain', () => {
  // 绕过单例, 直接 new (ArkTS 严格模式限制下用 unknown cast)
  const FreshClass = WeatherServiceImpl as unknown as new () => WeatherServiceImpl

  // Mock provider that returns whatever the test configures
  class MockProvider implements WeatherProvider {
    public liveToReturn: WeatherSnapshot = new WeatherSnapshot();
    public regeoToReturn: { name: string; adcode: string } = { name: '', adcode: '' };
    public districtToReturn: Array<{ name: string; adcode: string }> = [];
    public liveCallCount: number = 0;
    async fetchLive(adcode: string): Promise<WeatherSnapshot> {
      this.liveCallCount += 1;
      return this.liveToReturn;
    }
    async fetchRegeo(lng: number, lat: number): Promise<{ name: string; adcode: string }> {
      return this.regeoToReturn;
    }
    async searchDistrict(keyword: string): Promise<Array<{ name: string; adcode: string }>> {
      return this.districtToReturn;
    }
  }

  it('returns null when manual city empty and no GPS (provider empty)', 0, async () => {
    const fresh = new FreshClass();
    const mock = new MockProvider();
    (fresh as any).provider = mock;
    (fresh as any).snapshot = null;
    (fresh as any).manualCity = null;
    (fresh as any).tryGpsLocation = async () => null;
    const result = await (fresh as any).getCurrentWeather();
    expect(result).assertEqual(null);
  });

  it('uses cached snapshot within 1h', 0, async () => {
    const fresh = new FreshClass();
    const mock = new MockProvider();
    (fresh as any).provider = mock;
    const cached: WeatherSnapshot = new WeatherSnapshot();
    cached.weather = '晴';
    cached.temperature = 25;
    cached.fetchedAt = Date.now() - 1000; // 1s ago
    (fresh as any).snapshot = cached;
    const result = await (fresh as any).getCurrentWeather();
    expect(result !== null).assertEqual(true);
    expect(result!.weather).assertEqual('晴');
    expect(mock.liveCallCount).assertEqual(0);  // 没调 API
  });

  it('refreshes when cache expired and manual city set', 0, async () => {
    const fresh = new FreshClass();
    const mock = new MockProvider();
    (fresh as any).provider = mock;
    const fresh_snap: WeatherSnapshot = new WeatherSnapshot();
    fresh_snap.fetchedAt = Date.now() - 2 * 60 * 60 * 1000; // 2h ago
    (fresh as any).snapshot = fresh_snap;
    (fresh as any).manualCity = { name: '上海', adcode: '310000' };
    mock.liveToReturn.weather = '小雨';
    mock.liveToReturn.temperature = 18;
    mock.liveToReturn.city = '上海';
    mock.liveToReturn.adcode = '310000';
    (fresh as any).tryGpsLocation = async () => null;  // skip GPS
    const result = await (fresh as any).getCurrentWeather();
    expect(result !== null).assertEqual(true);
    expect(result!.weather).assertEqual('小雨');
    expect(result!.source).assertEqual('manual');
    expect(mock.liveCallCount).assertEqual(1);
  });

  it('uses GPS result when cache expired and GPS succeeds', 0, async () => {
    const fresh = new FreshClass();
    const mock = new MockProvider();
    (fresh as any).provider = mock;
    (fresh as any).snapshot = null;
    (fresh as any).manualCity = null;
    mock.liveToReturn.weather = '晴';
    mock.liveToReturn.city = '北京';
    mock.liveToReturn.adcode = '110000';
    (fresh as any).tryGpsLocation = async () => ({ name: '北京', adcode: '110000' });
    const result = await (fresh as any).getCurrentWeather();
    expect(result !== null).assertEqual(true);
    expect(result!.source).assertEqual('gps');
    expect(result!.weather).assertEqual('晴');
  });

  it('setManualCity stores the city', 0, () => {
    const fresh = new FreshClass();
    (fresh as any).setManualCity('上海', '310000');
    const c = (fresh as any).getManualCity();
    expect(c !== null).assertEqual(true);
    expect(c!.name).assertEqual('上海');
  });
});
```

- [ ] **Step 6.2: Build to verify it fails**

Run: `cd /Users/mac/mygame/HarmonyOS-app/chatcube && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -10`
Expected: Compile error — `getCurrentWeather`, `setManualCity`, `getManualCity` not on `WeatherServiceImpl`.

- [ ] **Step 6.3: Extend WeatherServiceImpl with full chain**

Modify `entry/src/main/ets/services/WeatherService.ets` — inside `class WeatherServiceImpl`, add the chain. Also add the manual city state + ApiKey refresh:

```typescript
  // (in class WeatherServiceImpl, after getProvider)
  private manualCity: { name: string; adcode: string } | null = null
  private readonly TTL_MS = 60 * 60 * 1000

  /**
   * 主入口: 4 步降级链.
   *   1. 内存缓存 (1h TTL, snapshot.weather !== '')
   *   2. GPS 定位 → regeo → 实时天气
   *   3. 手动城市 (用户设置) → 实时天气
   *   4. 全部失败 → null (不抛错)
   */
  async getCurrentWeather(): Promise<WeatherSnapshot | null> {
    try {
      // 1) 缓存
      if (this.snapshot !== null && this.snapshot.weather !== '' && !isWeatherExpired(this.snapshot, Date.now())) {
        return this.snapshot
      }
      // 2) GPS
      const gps = await this.tryGpsLocation()
      if (gps !== null) {
        const live = await this.provider.fetchLive(gps.adcode)
        if (live.weather !== '') {
          live.city = gps.name
          live.adcode = gps.adcode
          live.source = 'gps'
          live.fetchedAt = Date.now()
          this.snapshot = live
          return live
        }
      }
      // 3) 手动城市
      if (this.manualCity !== null) {
        const live = await this.provider.fetchLive(this.manualCity.adcode)
        if (live.weather !== '') {
          live.city = this.manualCity.name
          live.adcode = this.manualCity.adcode
          live.source = 'manual'
          live.fetchedAt = Date.now()
          this.snapshot = live
          return live
        }
      }
      return null
    } catch (e) {
      const err = e as BusinessError
      console.warn('WeatherService', `getCurrentWeather failed: ${err.message ?? String(e)}`)
      return null
    }
  }

  setManualCity(name: string, adcode: string): void {
    this.manualCity = { name: name, adcode: adcode }
    // 立刻失效缓存, 下一轮用新城市
    this.snapshot = null
  }

  getManualCity(): { name: string; adcode: string } | null {
    return this.manualCity
  }

  /** UI 展示用: 返回内存中最近一次 fetch 的 snapshot (不触发 API 调用). */
  getCachedSnapshot(): WeatherSnapshot | null {
    return this.snapshot
  }

  /** 启动时从 PreferencesService 加载 API key 和手动城市. */
  async initialize(): Promise<void> {
    try {
      const prefs: PreferencesService = getPreferencesService()
      const key = await prefs.getString(PreferenceKeys.AMAP_WEATHER_API_KEY, '')
      if (key !== '') {
        this.provider.setApiKey(key)
      }
      // 手动城市从 AppStorageV2 读
      const uiState = getAppUiState()
      if (uiState.manualCity !== null) {
        this.manualCity = uiState.manualCity
      }
    } catch (e) {
      const err = e as BusinessError
      console.warn('WeatherService', `initialize failed: ${err.message ?? String(e)}`)
    }
  }
```

- [ ] **Step 6.4: Add getAppUiState import**

Modify top of `entry/src/main/ets/services/WeatherService.ets` — add:

```typescript
import { getAppUiState } from '../state/AppUiState'
```

- [ ] **Step 6.5: Build to verify compile**

Run: `cd /Users/mac/mygame/HarmonyOS-app/chatcube && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -10`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 6.6: Run tests in DevEco Studio**

Open `entry/src/ohosTest/ets/test/WeatherUtils.test.ets` → Run.
Expected: 21 (from Task 3) + 5 (this task) = 26 it-blocks PASS.

- [ ] **Step 6.7: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && git add entry/src/main/ets/services/WeatherService.ets entry/src/ohosTest/ets/test/WeatherUtils.test.ets && git commit -m "feat(weather): WeatherService full 4-step degradation chain + tests"
```

---

## Task 7: ChatViewModel Inject Teaching Section

**Files:**
- Modify: `entry/src/main/ets/viewmodels/ChatViewModel.ets` (extend `injectTeachingSections`)
- Modify: `entry/src/main/ets/entryability/EntryAbility.ets` (pre-warm in `initializeServices`)

**Interfaces:**
- Produces: weather section as 4th in `injectTeachingSections` (after 今日教学目标, before greeting hint)
- 仅 `assistantId === DEFAULT_ASSISTANT_ID` 时执行 — already gated in the existing function
- 调用 `await getWeatherService().getCurrentWeather()` → `await renderWeatherSection(snap)`

- [ ] **Step 7.1: Add the import to ChatViewModel**

Modify `entry/src/main/ets/viewmodels/ChatViewModel.ets` — find the existing `import` block for `LessonPlanPromptUtils` (or near similar), add:

```typescript
import { renderWeatherSection } from '../utils/WeatherPromptUtils'
import { getWeatherService } from '../services/WeatherService'
```

- [ ] **Step 7.2: Extend injectTeachingSections**

Modify `entry/src/main/ets/viewmodels/ChatViewModel.ets` — inside `injectTeachingSections`, after section 3 (今日教学目标) and before section 4 (greetingHint), add:

```typescript
      // 4. 当前天气 (静态段, 仅小星老师)
      try {
        const snapshot = await getWeatherService().getCurrentWeather()
        if (snapshot !== null) {
          const section = renderWeatherSection(snapshot)
          if (section !== '') {
            composed = this.assistantService.combineSystemPrompts(composed, section)
          }
        }
      } catch (error) {
        const err = error as Error
        console.warn('ChatViewModel', `inject weather section failed: ${err.message ?? String(error)}`)
        // 静默降级, 继续走 greeting
      }
```

Place this AFTER the section 3 (今日教学目标) `if (today !== null) { ... }` block, and BEFORE the section 4 (greetingHint) `if (greetingHint.trim() !== '') { ... }` block.

- [ ] **Step 7.3: Pre-warm WeatherService in EntryAbility**

Read `entry/src/main/ets/entryability/EntryAbility.ets` first. Find `initializeServices()` (or similar init method). Add at the end:

```typescript
  // 天气服务预热 (加载 API key + 手动城市, 后续 1h 缓存生效)
  getWeatherService().initialize()
```

(If `initializeServices` returns a Promise, `await` it.)

- [ ] **Step 7.4: Build to verify compile**

Run: `cd /Users/mac/mygame/HarmonyOS-app/chatcube && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -10`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 7.5: Manual smoke test (build & inspect prompt)**

Build: `cd /Users/mac/mygame/HarmonyOS-app/chatcube && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL.

In DevEco Studio, run the app, start a chat with 小星老师. The system prompt (visible in some debug view or via `console.info`) should now include the weather section when configured.

- [ ] **Step 7.6: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && git add entry/src/main/ets/viewmodels/ChatViewModel.ets entry/src/main/ets/entryability/EntryAbility.ets && git commit -m "feat(weather): inject weather section into 小星老师 system prompt"
```

---

## Task 8: WeatherSettingsPage (City Search + Manual Selection + Last Fetch)

**Files:**
- Create: `entry/src/main/ets/pages/WeatherSettingsPage.ets`
- Modify: `entry/src/main/resources/base/profile/router_map.json` (register page)
- Modify: `entry/src/main/resources/base/element/string.json` (8 i18n strings)
- Test: skip (UI; can't easily hypium-test pages)

**Interfaces:**
- Page: `WeatherSettingsPage` (no `largeSize` / no special routing)
  - Top: "当前 API Key" status (set/not set) + button "去设置" → focus the API key input
  - Middle: "搜索城市" input + result list (3 max)
  - Bottom: "已选城市" + "上次天气" snapshot display
- Save: calls `getWeatherService().setManualCity(name, adcode)` + `setAppUiStateValue(WEATHER_MANUAL_CITY, {name, adcode})`
- API key: writes to `prefs.putString(AMAP_WEATHER_API_KEY, key)` and `provider.setApiKey(key)`
- Build function: `WeatherSettingsPageBuilder`

- [ ] **Step 8.1: Add i18n strings**

Read `entry/src/main/resources/base/element/string.json`. Add 4 entries (near other settings strings):

```json
{
  "name": "weather_settings_title",
  "value": "城市 / 天气"
},
{
  "name": "weather_settings_search_placeholder",
  "value": "搜索城市名 (例: 上海)"
},
{
  "name": "weather_settings_key_prompt",
  "value": "高德开放平台 API Key (在 amap.apkbs.com 注册)"
},
{
  "name": "weather_settings_no_result",
  "value": "未找到结果"
},
{
  "name": "weather_settings_current_city_label",
  "value": "当前城市"
},
{
  "name": "weather_settings_last_fetch_label",
  "value": "最近一次天气"
},
{
  "name": "weather_settings_section_api_key",
  "value": "高德 API Key"
},
{
  "name": "weather_settings_section_search",
  "value": "搜索并设置城市"
}
```

- [ ] **Step 8.2: Create the page**

Create `entry/src/main/ets/pages/WeatherSettingsPage.ets`. This page mirrors the layout of small settings pages like `LanguageSettingsPage.ets` (single Column with cards, theme tokens, no fancy navigation):

```typescript
import { promptAction } from '@kit.ArkUI'
import { getWeatherService, WeatherServiceImpl, AmapWeatherProvider } from '../services/WeatherService'
import { getPreferencesService, PreferencesService, PreferenceKeys } from '../services/PreferencesService'
import { getAppUiState, setAppUiStateValue } from '../state/AppUiState'
import { AppStorageKeys } from '../config/AppStorageKeys'
import { WeatherSnapshot } from '../utils/WeatherUtils'

@Builder
export function WeatherSettingsPageBuilder() {
  WeatherSettingsPage()
}

@ComponentV2
export struct WeatherSettingsPage {
  @Local apiKeyInput: string = ''
  @Local searchInput: string = ''
  @Local searchResults: Array<{ name: string; adcode: string }> = []
  @Local manualCity: { name: string; adcode: string } | null = null
  @Local lastSnapshot: WeatherSnapshot | null = null
  @Local isSearching: boolean = false

  async aboutToAppear(): Promise<void> {
    const prefs: PreferencesService = getPreferencesService()
    this.apiKeyInput = await prefs.getString(PreferenceKeys.AMAP_WEATHER_API_KEY, '')
    const uiState = getAppUiState()
    this.manualCity = uiState.manualCity
    // 从 WeatherService 内部 cache 读最近一次 fetch 的 snapshot (不调 API)
    this.lastSnapshot = getWeatherService().getCachedSnapshot()
  }

  build() {
    Column() {
      // 1. API Key 卡片
      this.ApiKeyCard()
      // 2. 搜索 + 手动城市
      this.SearchCard()
      // 3. 当前状态
      this.StatusCard()
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  private ApiKeyCard() {
    Column({ space: 12 }) {
      Text($r('app.string.weather_settings_section_api_key'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text($r('app.string.weather_settings_key_prompt'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      TextInput({ placeholder: 'AMAP_KEY', text: this.apiKeyInput })
        .type(InputType.Normal)
        .onChange((v: string) => { this.apiKeyInput = v })
      Button('保存 API Key')
        .onClick(async () => {
          const prefs: PreferencesService = getPreferencesService()
          await prefs.putString(PreferenceKeys.AMAP_WEATHER_API_KEY, this.apiKeyInput)
          // 立即更新 provider
          const svc = getWeatherService()
          ;(svc.getProvider() as AmapWeatherProvider).setApiKey(this.apiKeyInput)
          promptAction.showToast({ message: '已保存' })
        })
    }
    .width('100%')
    .padding(16)
    .margin({ bottom: 16 })
    .borderRadius(14)
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private SearchCard() {
    Column({ space: 12 }) {
      Text($r('app.string.weather_settings_section_search'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Row({ space: 8 }) {
        TextInput({ placeholder: $r('app.string.weather_settings_search_placeholder'), text: this.searchInput })
          .layoutWeight(1)
          .onChange((v: string) => { this.searchInput = v })
        Button('搜索')
          .enabled(!this.isSearching && this.searchInput.length > 0)
          .onClick(async () => {
            this.isSearching = true
            try {
              const svc = getWeatherService()
              const results = await svc.getProvider().searchDistrict(this.searchInput)
              this.searchResults = results.slice(0, 5)
            } catch (_e) {
              this.searchResults = []
            } finally {
              this.isSearching = false
            }
          })
      }
      if (this.searchResults.length === 0 && this.searchInput.length > 0 && !this.isSearching) {
        Text($r('app.string.weather_settings_no_result'))
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
      }
      ForEach(this.searchResults, (item: { name: string; adcode: string }) => {
        Row() {
          Text(item.name)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Button('选这个')
            .onClick(async () => {
              const svc = getWeatherService()
              svc.setManualCity(item.name, item.adcode)
              setAppUiStateValue(AppStorageKeys.WEATHER_MANUAL_CITY, { name: item.name, adcode: item.adcode })
              this.manualCity = { name: item.name, adcode: item.adcode }
              this.searchResults = []
              this.searchInput = ''
              promptAction.showToast({ message: `已选 ${item.name}` })
            })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      })
    }
    .width('100%')
    .padding(16)
    .margin({ bottom: 16 })
    .borderRadius(14)
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  private StatusCard() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.weather_settings_current_city_label'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Text(this.manualCity === null ? '未设置' : this.manualCity.name)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      if (this.lastSnapshot !== null && this.lastSnapshot.weather !== '') {
        Row() {
          Text($r('app.string.weather_settings_last_fetch_label'))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
          Text(`${this.lastSnapshot.weather} / ${this.lastSnapshot.temperature}°C`)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(14)
    .backgroundColor($r('app.color.surface'))
  }
}
```

> **NOTE for implementer**: Resource keys (`$r('app.color.background')`, `$r('app.string.*')`) must exist in `resources/base/element/color.json` and `string.json`. Use existing tokens (e.g. `themeBackground`, `themeSurface`, `themeTextPrimary`) if the literal names don't exist. Don't invent new colors.

- [ ] **Step 8.3: Register in router_map.json**

Modify `entry/src/main/resources/base/profile/router_map.json` — add at end of `routerMap` array (before the closing `]`):

```json
,
{
  "name": "WeatherSettingsPage",
  "pageSourceFile": "src/main/ets/pages/WeatherSettingsPage.ets",
  "buildFunction": "WeatherSettingsPageBuilder"
}
```

- [ ] **Step 8.4: Build to verify compile**

Run: `cd /Users/mac/mygame/HarmonyOS-app/chatcube && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -10`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 8.5: Manual smoke test**

In DevEco Studio, run the app, navigate to Settings → 城市 / 天气 (add this entry in whatever settings list page exists; implementer should add a Row that `router.pushUrl({ url: 'pages/WeatherSettingsPage' })` to its `onClick`).

Test:
1. Enter an Amap API key → click 保存 → toast "已保存" appears.
2. Type "上海" in search → click 搜索 → 1+ result appears.
3. Click "选这个" on "上海市" → toast "已选 上海" appears, "当前城市" shows "上海".
4. Start a chat with 小星老师 → in the system prompt, the weather section should now appear (assuming the API key is valid).

- [ ] **Step 8.6: Commit**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && git add entry/src/main/ets/pages/WeatherSettingsPage.ets entry/src/main/resources/base/profile/router_map.json entry/src/main/resources/base/element/string.json && git commit -m "feat(weather): settings page for API key + city search"
```

---

## Final Verification

- [ ] **Step 9.1: Run full test suite**

Open `entry/src/ohosTest/ets/test/List.test.ets` → Run in DevEco Studio.
Expected: All 26 it-blocks across all test files PASS.

- [ ] **Step 9.2: Run lint (IDE-side)**

In DevEco Studio: right-click `entry/` → Code Linter → Run.
Expected: 0 new errors (existing pre-existing warnings OK).

- [ ] **Step 9.3: Clean build**

Run: `cd /Users/mac/mygame/HarmonyOS-app/chatcube && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw clean --mode module -p product=default && /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap --mode module -p product=default -p buildMode=debug 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 9.4: End-to-end manual verification**

1. Fresh install the app (clear data).
2. Set Amap API key in Settings → 城市 / 天气.
3. Search and pick "上海".
4. Open 小星老师 chat → ask "今天天气怎么样" → AI should reference 上海 weather.
5. Force quit + relaunch → weather should reload via cache.
6. Disable network → open chat → AI should not crash, just not have weather in prompt.
7. Verify other assistants (any non-小星老师) don't have weather in their prompt.

- [ ] **Step 9.5: Final commit (if any post-fix changes)**

```bash
cd /Users/mac/mygame/HarmonyOS-app/chatcube && git status
# If any uncommitted fixes:
git add -A && git commit -m "chore(weather): post-verification fixes"
```

---

## Self-Review Checklist (per spec)

- [x] Spec §2 架构与数据流 → Task 6, 7
- [x] Spec §3.1 新建文件 → Task 1 (WeatherUtils), Task 2 (WeatherPromptUtils), Task 3 (WeatherService with AmapProvider)
- [x] Spec §3.2 修改文件 → Task 4 (AppUiState, AppStorageKeys), Task 5 (module.json5), Task 6 (PreferencesService), Task 7 (ChatViewModel, EntryAbility), Task 8 (router_map, string.json)
- [x] Spec §3.3 AppStorageV2 键 → Task 4
- [x] Spec §3.4 高德 API 端点 → Task 3 (3 endpoints)
- [x] Spec §4 错误处理 → Task 5 (GPS), Task 6 (chain never throws)
- [x] Spec §5.1 纯函数测试 → Task 1 (4 functions), Task 2 (render)
- [x] Spec §9 验收清单 → Step 9.4 manual verification
- [x] Global constraints (ArkTS strict mode, JSON-in-template, rcp body, etc.) → noted in each task's notes
