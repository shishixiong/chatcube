---
name: adding-stroke-order-data
description: Use when adding new Chinese characters, uppercase letters, or numerals to the handwriting-practice stroke order data — fetching SVG path outlines from hanzi-writer-data, generating thick-rectangle paths for letters/numerals, and inserting entries into StrokeOrderData.ets.
---

# Adding Stroke Order Data

## Overview

Add new characters to `entry/src/main/ets/config/StrokeOrderData.ets` for the `HandwritingCard` handwriting-practice mini-game. Each character has an array of strokes; each stroke has a `path` (SVG path string on a 1024×1024 Y-up grid) and a `label` (stroke type name).

## When to Use

- AI calls `handwriting_practice` with a character not in `STROKE_ORDER_MAP`, and the fallback experience (ghost `Text` only, no animation) is unacceptable
- Adding common characters requested by teachers/lessons
- Adding uppercase letters / numerals not yet covered (A-Z and 0-9 already present — check first!)

**When NOT to use:**
- Modifying the `HandwritingCard` component itself (use `systematic-debugging`)
- Adding a brand-new mini-game tool (use `.claude/skills/adding-mini-game-tool/SKILL.md`)

## Data Model (must match)

```typescript
export interface HandwritingStroke {
  path: string   // SVG path (M/Q/L/C/Z), 1024×1024 Y-UP grid
  label: string  // 横|竖|撇|捺|点|折 (or / \ | — ⌒ for letters)
}
```

The `HandwritingCard.drawSvgPath` does the Y-flip at render time (`(SVG_GRID - y)`). **Store paths verbatim from hanzi-writer-data** (Y-up, origin bottom-left). Do NOT pre-flip.

## Quick Reference

| Item | Value |
|---|---|
| Target file | `entry/src/main/ets/config/StrokeOrderData.ets` |
| Chinese char data source | `https://cdn.jsdelivr.net/npm/hanzi-writer-data@2.0.0/${char}.json` |
| Stroke type labels source | `https://cdn.jsdelivr.net/npm/chinese-character-strokes@1.0.0/${char}.json` (numeric codes 1=横 2=竖 3=撇 4=捺/点 5=折) |
| Letters/numerals | Generated via `gen_stroke_data.js` (thick filled rectangles, Y-flipped at generation time — different from Chinese chars!) |
| Grid | 1024×1024, Y-up (hanzi-writer-data convention) |
| Insertion point | Chinese chars: before `// === 大写字母 ===` comment. Letters/numerals: end of file, before `STROKE_ORDER_MAP` construction. |
| Build verify | `hvigorw assembleHap --mode module -p product=default -p buildMode=debug` |

## Recipe: Add a Single Chinese Character

1. **Check for duplicates** — grep the file for the character first. The `STROKE_ORDER_ENTRIES` array feeds `new Map(...)` at the end; a later duplicate key silently overwrites the earlier entry.

2. **Fetch the data** — either:
   - Run the batch script: `node .claude/skills/adding-stroke-order-data/gen_stroke_data.js 明 林 朋 > /tmp/new_entries.txt` (paste the output into the file)
   - Or fetch manually: `curl 'https://cdn.jsdelivr.net/npm/hanzi-writer-data@2.0.0/明.json'` — the JSON has a `strokes` array of SVG path strings. Use them verbatim.

3. **Assign labels** — prefer the proper stroke-type name from `chinese-character-strokes` (fetch separately). **Note: the `chinese-character-strokes@1.0.0` package has been intermittently unavailable on jsdelivr CDN as of 2026-06.** If the lookup fails, the script emits a stderr warning and writes `??` placeholders — you MUST replace these with proper labels manually (横/竖/撇/捺/点/折) based on the character's standard stroke order. **Do NOT leave `??` in the file, and do NOT use generic `笔画N`** — legacy entries with `笔画N` exist but new entries should use proper names.

4. **Insert into `STROKE_ORDER_ENTRIES`** before the `// === 大写字母 ===` comment, matching the existing tuple shape:
   ```typescript
   ['明', [
     { path: 'M 191 698 ...', label: '竖' },
     // ... 7 more strokes
   ]],
   ```

5. **String escaping** — if a label contains `\` (backslash, used for some letter strokes), escape as `\\`. Unescaped `label: '\'` causes "Unterminated string literal" at compile time. See "Common Mistakes".

6. **Verify build**:
   ```bash
   DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
     /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw assembleHap \
     --mode module -p product=default -p buildMode=debug
   ```
   A clean build is the only CLI-side verification (no lint/test task exists — see MEMORY.md).

## Recipe: Add Letters / Numerals

Letters A-Z and numerals 0-9 are NOT in `hanzi-writer-data`. They use a different generation path: thick filled rectangles computed from line segments.

1. Run `node .claude/skills/adding-stroke-order-data/gen_stroke_data.js A B C > /tmp/letters.txt`
2. The script outputs entries with proper Y-flip baked into the path coordinates (different from Chinese chars, where the flip is at render time).
3. Insert at the end of `STROKE_ORDER_ENTRIES` before `const STROKE_ORDER_MAP`.

## Verification Checklist

- [ ] Build compiles cleanly (`hvigorw assembleHap` exits 0)
- [ ] No duplicate entries (grep the character in the file)
- [ ] Labels use proper stroke-type names (横/竖/撇/捺/点/折), not `笔画N`
- [ ] All backslash labels escaped as `\\`
- [ ] Entry inserted before `STROKE_ORDER_MAP` construction (so the Map picks it up)
- [ ] **Visual check in DevEco Studio**: trigger the `handwriting_practice` tool with the new character, verify the animation plays right-side-up and strokes appear in the correct order

## Common Mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| `label: '\'` (unescaped backslash) | `Unterminated string literal` at compile, points to line ending in `\'` | Change to `label: '\\'` — Python/regex replacement: `s.replace("label: '\\'", "label: '\\\\'")` (3-char → 4-char) |
| Pre-flipping Y coordinates at authoring time | Character renders upside-down (水字写倒了) | Store raw hanzi-writer-data paths. The flip happens in `drawSvgPath` via `(SVG_GRID - y)`. |
| Using `points`/`x1y1x2y2` shape | Type error or stale rendering | Current model is `{ path, label }` (single SVG path string per stroke). The old polyline model was replaced 2026-06-22. |
| Adding entry after `STROKE_ORDER_MAP = new Map(...)` | `hasStrokeOrder()` returns false at runtime | Insert inside `STROKE_ORDER_ENTRIES` array, before the `const STROKE_ORDER_MAP` line. |
| Using generic labels `笔画1` | Inconsistent with newer entries | Use proper names: 横/竖/撇/捺/点/折 (or `/ \ | — ⌒` for letter direction strokes). Legacy entries with `笔画N` exist but should not be added going forward. |
| Skipping duplicate check | Later entry silently overwrites earlier (Map semantics) | `grep -n "'<char>'" StrokeOrderData.ets` before adding. |
| Trusting the file header comment "(0,0) = 左上角" | Confusion about Y-axis orientation | The comment is misleading — hanzi-writer-data uses Y-up (origin bottom-left). The data IS Y-up; the flip is at render time. |

## Red Flags — STOP Before Committing

- `label: '\'` anywhere in the file (backslash followed by two single-quotes)
- A character whose paths have negative Y values AND you manually negated them (double-flip — will render upside-down)
- New entry placed AFTER `const STROKE_ORDER_MAP` line
- Build succeeded but you didn't run it — "compile clean" is the only CLI verification
- You added a character without checking if it already exists

## Files Touched

| File | Change |
|---|---|
| `entry/src/main/ets/config/StrokeOrderData.ets` | Add `['<char>', [...strokes]]` tuple to `STROKE_ORDER_ENTRIES` |

**No other files need changes** — `HandwritingCard.ets` reads via `getStrokeOrder()`, `BuiltinTools.ets` schema already accepts the `path`-based shape, `MessageBubble.ets` / `ToolExecutionService.ets` / `StarRewardService.ets` are all downstream and untouched.
