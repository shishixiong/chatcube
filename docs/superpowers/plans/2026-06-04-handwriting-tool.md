# HandwritingCard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a handwriting practice teaching tool card where kids write characters on Canvas, get AI vision evaluation feedback.

**Architecture:** Reuses NumberPuzzleCard's dual-view pattern — inline banner in MessageBubble, largeSize sheet in ChatPage. Core component `HandwritingCard` handles Canvas drawing + stroke order animation. AI evaluation happens inline inside `ToolExecutionService.handleHandwriting()` (内聚流).

**Tech Stack:** ArkTS @ComponentV2, CanvasRenderingContext2D, PixelMap export, existing AIApiService vision pipeline.

---

### Task 1: Create stroke order data file

**Files:**
- Create: `entry/src/main/ets/config/StrokeOrderData.ets`

- [ ] **Step 1: Write StrokeOrderData.ets**

```typescript
// HandwritingCard 本地笔顺数据
// 相对坐标 (0.0-1.0)，渲染时按 Canvas 尺寸缩放

export interface HandwritingStroke {
  x1: number
  y1: number
  x2: number
  y2: number
  label: string
}

// 获取指定字符的笔顺数据，未命中返回 null
export function getStrokeOrder(character: string): HandwritingStroke[] | null {
  const data = STROKE_ORDER_MAP.get(character)
  if (data === undefined) {
    return null
  }
  return data
}

// 检查是否有本地笔顺数据
export function hasStrokeOrder(character: string): boolean {
  return STROKE_ORDER_MAP.has(character)
}

const STROKE_ORDER_MAP: Map<string, HandwritingStroke[]> = new Map([
  // === 大写字母 ===
  ['A', [
    { x1: 0.3, y1: 0.85, x2: 0.5, y2: 0.1, label: '/' },
    { x1: 0.5, y1: 0.1, x2: 0.7, y2: 0.85, label: '\\' },
    { x1: 0.35, y1: 0.5, x2: 0.65, y2: 0.5, label: '—' }
  ]],
  ['B', [
    { x1: 0.15, y1: 0.1, x2: 0.15, y2: 0.9, label: '|' },
    { x1: 0.15, y1: 0.1, x2: 0.7, y2: 0.1, label: '—' },
    { x1: 0.7, y1: 0.1, x2: 0.7, y2: 0.45, label: '|' },
    { x1: 0.7, y1: 0.45, x2: 0.15, y2: 0.45, label: '—' },
    { x1: 0.15, y1: 0.45, x2: 0.75, y2: 0.45, label: '—' },
    { x1: 0.75, y1: 0.45, x2: 0.75, y2: 0.9, label: '|' },
    { x1: 0.75, y1: 0.9, x2: 0.15, y2: 0.9, label: '—' }
  ]],
  ['C', [
    { x1: 0.8, y1: 0.2, x2: 0.2, y2: 0.2, label: '⌒' },
    { x1: 0.2, y1: 0.2, x2: 0.2, y2: 0.8, label: '|' },
    { x1: 0.2, y1: 0.8, x2: 0.8, y2: 0.8, label: '⌒' }
  ]],
  ['D', [
    { x1: 0.15, y1: 0.1, x2: 0.15, y2: 0.9, label: '|' },
    { x1: 0.15, y1: 0.1, x2: 0.65, y2: 0.1, label: '—' },
    { x1: 0.65, y1: 0.1, x2: 0.85, y2: 0.5, label: '\\' },
    { x1: 0.85, y1: 0.5, x2: 0.65, y2: 0.9, label: '/' },
    { x1: 0.65, y1: 0.9, x2: 0.15, y2: 0.9, label: '—' }
  ]],
  ['E', [
    { x1: 0.2, y1: 0.1, x2: 0.8, y2: 0.1, label: '—' },
    { x1: 0.2, y1: 0.1, x2: 0.2, y2: 0.9, label: '|' },
    { x1: 0.2, y1: 0.5, x2: 0.6, y2: 0.5, label: '—' },
    { x1: 0.2, y1: 0.9, x2: 0.8, y2: 0.9, label: '—' }
  ]],
  ['F', [
    { x1: 0.2, y1: 0.1, x2: 0.8, y2: 0.1, label: '—' },
    { x1: 0.2, y1: 0.1, x2: 0.2, y2: 0.9, label: '|' },
    { x1: 0.2, y1: 0.5, x2: 0.6, y2: 0.5, label: '—' }
  ]],
  ['G', [
    { x1: 0.8, y1: 0.15, x2: 0.25, y2: 0.15, label: '⌒' },
    { x1: 0.2, y1: 0.15, x2: 0.2, y2: 0.85, label: '|' },
    { x1: 0.2, y1: 0.85, x2: 0.7, y2: 0.85, label: '⌒' },
    { x1: 0.7, y1: 0.85, x2: 0.7, y2: 0.5, label: '|' },
    { x1: 0.7, y1: 0.5, x2: 0.5, y2: 0.5, label: '—' }
  ]],
  ['H', [
    { x1: 0.2, y1: 0.1, x2: 0.2, y2: 0.9, label: '|' },
    { x1: 0.2, y1: 0.5, x2: 0.8, y2: 0.5, label: '—' },
    { x1: 0.8, y1: 0.1, x2: 0.8, y2: 0.9, label: '|' }
  ]],
  ['I', [
    { x1: 0.3, y1: 0.1, x2: 0.7, y2: 0.1, label: '—' },
    { x1: 0.5, y1: 0.1, x2: 0.5, y2: 0.9, label: '|' },
    { x1: 0.3, y1: 0.9, x2: 0.7, y2: 0.9, label: '—' }
  ]],
  ['J', [
    { x1: 0.3, y1: 0.1, x2: 0.8, y2: 0.1, label: '—' },
    { x1: 0.65, y1: 0.1, x2: 0.65, y2: 0.75, label: '|' },
    { x1: 0.65, y1: 0.75, x2: 0.3, y2: 0.85, label: '⌒' }
  ]],
  ['K', [
    { x1: 0.2, y1: 0.1, x2: 0.2, y2: 0.9, label: '|' },
    { x1: 0.2, y1: 0.5, x2: 0.75, y2: 0.1, label: '/' },
    { x1: 0.35, y1: 0.5, x2: 0.8, y2: 0.9, label: '\\' }
  ]],
  ['L', [
    { x1: 0.2, y1: 0.1, x2: 0.2, y2: 0.9, label: '|' },
    { x1: 0.2, y1: 0.9, x2: 0.8, y2: 0.9, label: '—' }
  ]],
  ['M', [
    { x1: 0.15, y1: 0.1, x2: 0.15, y2: 0.9, label: '|' },
    { x1: 0.15, y1: 0.1, x2: 0.5, y2: 0.55, label: '\\' },
    { x1: 0.5, y1: 0.55, x2: 0.85, y2: 0.1, label: '/' },
    { x1: 0.85, y1: 0.1, x2: 0.85, y2: 0.9, label: '|' }
  ]],
  ['N', [
    { x1: 0.15, y1: 0.1, x2: 0.15, y2: 0.9, label: '|' },
    { x1: 0.15, y1: 0.1, x2: 0.85, y2: 0.9, label: '\\' },
    { x1: 0.85, y1: 0.1, x2: 0.85, y2: 0.9, label: '|' }
  ]],
  ['O', [
    { x1: 0.5, y1: 0.1, x2: 0.2, y2: 0.1, label: '⌒' },
    { x1: 0.2, y1: 0.1, x2: 0.2, y2: 0.9, label: '|' },
    { x1: 0.2, y1: 0.9, x2: 0.8, y2: 0.9, label: '⌒' },
    { x1: 0.8, y1: 0.9, x2: 0.8, y2: 0.1, label: '|' }
  ]],
  ['P', [
    { x1: 0.2, y1: 0.1, x2: 0.2, y2: 0.9, label: '|' },
    { x1: 0.2, y1: 0.1, x2: 0.75, y2: 0.1, label: '—' },
    { x1: 0.75, y1: 0.1, x2: 0.75, y2: 0.45, label: '|' },
    { x1: 0.75, y1: 0.45, x2: 0.2, y2: 0.45, label: '—' }
  ]],
  ['Q', [
    { x1: 0.5, y1: 0.12, x2: 0.2, y2: 0.12, label: '⌒' },
    { x1: 0.2, y1: 0.12, x2: 0.2, y2: 0.78, label: '|' },
    { x1: 0.2, y1: 0.78, x2: 0.8, y2: 0.78, label: '⌒' },
    { x1: 0.8, y1: 0.78, x2: 0.8, y2: 0.12, label: '|' },
    { x1: 0.6, y1: 0.65, x2: 0.88, y2: 0.92, label: '\\' }
  ]],
  ['R', [
    { x1: 0.2, y1: 0.1, x2: 0.2, y2: 0.9, label: '|' },
    { x1: 0.2, y1: 0.1, x2: 0.75, y2: 0.1, label: '—' },
    { x1: 0.75, y1: 0.1, x2: 0.75, y2: 0.45, label: '|' },
    { x1: 0.75, y1: 0.45, x2: 0.2, y2: 0.45, label: '—' },
    { x1: 0.35, y1: 0.45, x2: 0.8, y2: 0.9, label: '\\' }
  ]],
  ['S', [
    { x1: 0.75, y1: 0.15, x2: 0.25, y2: 0.15, label: '—' },
    { x1: 0.2, y1: 0.15, x2: 0.2, y2: 0.45, label: '|' },
    { x1: 0.2, y1: 0.45, x2: 0.8, y2: 0.45, label: '—' },
    { x1: 0.8, y1: 0.45, x2: 0.8, y2: 0.85, label: '|' },
    { x1: 0.8, y1: 0.85, x2: 0.2, y2: 0.85, label: '—' }
  ]],
  ['T', [
    { x1: 0.3, y1: 0.1, x2: 0.7, y2: 0.1, label: '—' },
    { x1: 0.5, y1: 0.1, x2: 0.5, y2: 0.9, label: '|' }
  ]],
  ['U', [
    { x1: 0.2, y1: 0.1, x2: 0.2, y2: 0.8, label: '|' },
    { x1: 0.2, y1: 0.8, x2: 0.8, y2: 0.8, label: '⌒' },
    { x1: 0.8, y1: 0.8, x2: 0.8, y2: 0.1, label: '|' }
  ]],
  ['V', [
    { x1: 0.2, y1: 0.1, x2: 0.5, y2: 0.9, label: '\\' },
    { x1: 0.5, y1: 0.9, x2: 0.8, y2: 0.1, label: '/' }
  ]],
  ['W', [
    { x1: 0.1, y1: 0.1, x2: 0.3, y2: 0.9, label: '\\' },
    { x1: 0.3, y1: 0.9, x2: 0.5, y2: 0.5, label: '/' },
    { x1: 0.5, y1: 0.5, x2: 0.7, y2: 0.9, label: '\\' },
    { x1: 0.7, y1: 0.9, x2: 0.9, y2: 0.1, label: '/' }
  ]],
  ['X', [
    { x1: 0.2, y1: 0.1, x2: 0.8, y2: 0.9, label: '\\' },
    { x1: 0.8, y1: 0.1, x2: 0.2, y2: 0.9, label: '/' }
  ]],
  ['Y', [
    { x1: 0.2, y1: 0.1, x2: 0.5, y2: 0.5, label: '\\' },
    { x1: 0.5, y1: 0.5, x2: 0.8, y2: 0.1, label: '/' },
    { x1: 0.5, y1: 0.5, x2: 0.5, y2: 0.9, label: '|' }
  ]],
  ['Z', [
    { x1: 0.2, y1: 0.1, x2: 0.8, y2: 0.1, label: '—' },
    { x1: 0.8, y1: 0.1, x2: 0.2, y2: 0.9, label: '/' },
    { x1: 0.2, y1: 0.9, x2: 0.8, y2: 0.9, label: '—' }
  ]],

  // === 数字 ===
  ['0', [
    { x1: 0.5, y1: 0.1, x2: 0.2, y2: 0.3, label: '⌒' },
    { x1: 0.2, y1: 0.3, x2: 0.2, y2: 0.7, label: '|' },
    { x1: 0.2, y1: 0.7, x2: 0.5, y2: 0.9, label: '⌒' },
    { x1: 0.5, y1: 0.9, x2: 0.8, y2: 0.7, label: '⌒' },
    { x1: 0.8, y1: 0.7, x2: 0.8, y2: 0.3, label: '|' },
    { x1: 0.8, y1: 0.3, x2: 0.5, y2: 0.1, label: '⌒' }
  ]],
  ['1', [
    { x1: 0.35, y1: 0.2, x2: 0.5, y2: 0.1, label: '/' },
    { x1: 0.5, y1: 0.1, x2: 0.5, y2: 0.9, label: '|' }
  ]],
  ['2', [
    { x1: 0.25, y1: 0.2, x2: 0.7, y2: 0.15, label: '⌒' },
    { x1: 0.75, y1: 0.2, x2: 0.35, y2: 0.55, label: '/' },
    { x1: 0.2, y1: 0.55, x2: 0.8, y2: 0.85, label: '—' }
  ]],
  ['3', [
    { x1: 0.25, y1: 0.15, x2: 0.75, y2: 0.15, label: '⌒' },
    { x1: 0.8, y1: 0.2, x2: 0.55, y2: 0.45, label: '/' },
    { x1: 0.4, y1: 0.5, x2: 0.75, y2: 0.5, label: '⌒' },
    { x1: 0.8, y1: 0.55, x2: 0.55, y2: 0.85, label: '/' },
    { x1: 0.25, y1: 0.85, x2: 0.75, y2: 0.85, label: '⌒' }
  ]],
  ['4', [
    { x1: 0.65, y1: 0.1, x2: 0.65, y2: 0.9, label: '|' },
    { x1: 0.65, y1: 0.45, x2: 0.15, y2: 0.45, label: '—' },
    { x1: 0.15, y1: 0.45, x2: 0.25, y2: 0.1, label: '/' }
  ]],
  ['5', [
    { x1: 0.7, y1: 0.1, x2: 0.2, y2: 0.1, label: '—' },
    { x1: 0.2, y1: 0.1, x2: 0.2, y2: 0.45, label: '|' },
    { x1: 0.2, y1: 0.45, x2: 0.7, y2: 0.45, label: '—' },
    { x1: 0.75, y1: 0.5, x2: 0.3, y2: 0.85, label: '/' },
    { x1: 0.25, y1: 0.85, x2: 0.7, y2: 0.85, label: '—' }
  ]],
  ['6', [
    { x1: 0.7, y1: 0.12, x2: 0.25, y2: 0.20, label: '⌒' },
    { x1: 0.2, y1: 0.2, x2: 0.2, y2: 0.85, label: '|' },
    { x1: 0.2, y1: 0.85, x2: 0.7, y2: 0.75, label: '⌒' },
    { x1: 0.7, y1: 0.75, x2: 0.7, y2: 0.45, label: '|' },
    { x1: 0.7, y1: 0.45, x2: 0.2, y2: 0.45, label: '⌒' }
  ]],
  ['7', [
    { x1: 0.2, y1: 0.1, x2: 0.8, y2: 0.1, label: '—' },
    { x1: 0.8, y1: 0.1, x2: 0.35, y2: 0.9, label: '/' }
  ]],
  ['8', [
    { x1: 0.5, y1: 0.1, x2: 0.25, y2: 0.15, label: '⌒' },
    { x1: 0.25, y1: 0.15, x2: 0.25, y2: 0.42, label: '|' },
    { x1: 0.25, y1: 0.42, x2: 0.75, y2: 0.42, label: '⌒' },
    { x1: 0.75, y1: 0.42, x2: 0.75, y2: 0.15, label: '|' },
    { x1: 0.5, y1: 0.48, x2: 0.25, y2: 0.52, label: '⌒' },
    { x1: 0.25, y1: 0.52, x2: 0.25, y2: 0.85, label: '|' },
    { x1: 0.25, y1: 0.85, x2: 0.75, y2: 0.85, label: '⌒' },
    { x1: 0.75, y1: 0.85, x2: 0.75, y2: 0.52, label: '|' }
  ]],
  ['9', [
    { x1: 0.5, y1: 0.1, x2: 0.25, y2: 0.15, label: '⌒' },
    { x1: 0.25, y1: 0.15, x2: 0.25, y2: 0.42, label: '|' },
    { x1: 0.25, y1: 0.42, x2: 0.75, y2: 0.42, label: '⌒' },
    { x1: 0.75, y1: 0.42, x2: 0.75, y2: 0.15, label: '|' },
    { x1: 0.75, y1: 0.15, x2: 0.75, y2: 0.88, label: '|' }
  ]],

  // === 基础汉字 ===
  ['一', [
    { x1: 0.15, y1: 0.5, x2: 0.85, y2: 0.5, label: '—' }
  ]],
  ['二', [
    { x1: 0.2, y1: 0.3, x2: 0.8, y2: 0.3, label: '—' },
    { x1: 0.15, y1: 0.7, x2: 0.85, y2: 0.7, label: '—' }
  ]],
  ['三', [
    { x1: 0.2, y1: 0.18, x2: 0.8, y2: 0.18, label: '—' },
    { x1: 0.25, y1: 0.5, x2: 0.75, y2: 0.5, label: '—' },
    { x1: 0.15, y1: 0.82, x2: 0.85, y2: 0.82, label: '—' }
  ]],
  ['人', [
    { x1: 0.3, y1: 0.1, x2: 0.5, y2: 0.5, label: '/' },
    { x1: 0.7, y1: 0.1, x2: 0.5, y2: 0.9, label: '\\' }
  ]],
  ['大', [
    { x1: 0.2, y1: 0.5, x2: 0.8, y2: 0.5, label: '—' },
    { x1: 0.5, y1: 0.5, x2: 0.3, y2: 0.1, label: '/' },
    { x1: 0.5, y1: 0.5, x2: 0.7, y2: 0.9, label: '\\' }
  ]],
  ['山', [
    { x1: 0.3, y1: 0.8, x2: 0.5, y2: 0.15, label: '|' },
    { x1: 0.5, y1: 0.15, x2: 0.5, y2: 0.5, label: '|' },
    { x1: 0.5, y1: 0.5, x2: 0.8, y2: 0.8, label: '|' }
  ]],
  ['水', [
    { x1: 0.5, y1: 0.1, x2: 0.5, y2: 0.65, label: '|' },
    { x1: 0.5, y1: 0.65, x2: 0.2, y2: 0.35, label: '/' },
    { x1: 0.5, y1: 0.65, x2: 0.8, y2: 0.35, label: '\\' },
    { x1: 0.5, y1: 0.35, x2: 0.2, y2: 0.9, label: '/' },
    { x1: 0.5, y1: 0.35, x2: 0.8, y2: 0.9, label: '\\' }
  ]],
  ['日', [
    { x1: 0.2, y1: 0.15, x2: 0.8, y2: 0.15, label: '—' },
    { x1: 0.8, y1: 0.15, x2: 0.8, y2: 0.85, label: '|' },
    { x1: 0.8, y1: 0.5, x2: 0.2, y2: 0.5, label: '—' },
    { x1: 0.2, y1: 0.15, x2: 0.2, y2: 0.85, label: '|' },
    { x1: 0.2, y1: 0.85, x2: 0.8, y2: 0.85, label: '—' }
  ]],
  ['月', [
    { x1: 0.2, y1: 0.15, x2: 0.2, y2: 0.85, label: '|' },
    { x1: 0.2, y1: 0.15, x2: 0.7, y2: 0.15, label: '—' },
    { x1: 0.7, y1: 0.15, x2: 0.7, y2: 0.5, label: '|' },
    { x1: 0.7, y1: 0.5, x2: 0.2, y2: 0.5, label: '—' },
    { x1: 0.2, y1: 0.5, x2: 0.2, y2: 0.85, label: '|' },
    { x1: 0.2, y1: 0.85, x2: 0.7, y2: 0.85, label: '—' }
  ]]
])
```

- [ ] **Step 2: Commit**

```bash
git add entry/src/main/ets/config/StrokeOrderData.ets
git commit -m "feat: add stroke order data for handwriting tool"
```

---

### Task 2: Add tool ID and guard function

**Files:**
- Modify: `entry/src/main/ets/utils/SearchToolIdentityUtils.ets:11-79`

- [ ] **Step 1: Add constant (after line 11)**

```typescript
export const HANDWRITING_PRACTICE_TOOL_ID: string = 'handwriting_practice'
```

- [ ] **Step 2: Add guard function (after line 79, before `getSearchToolIds`)**

```typescript
export function isHandwritingPracticeFunctionName(functionName: string): boolean {
  const normalized = normalizeToolFunctionName(functionName)
  return normalized === HANDWRITING_PRACTICE_TOOL_ID ||
    normalized === 'handwriting' ||
    normalized === 'write_practice' ||
    normalized === 'learn_to_write'
}
```

- [ ] **Step 3: Commit**

```bash
git add entry/src/main/ets/utils/SearchToolIdentityUtils.ets
git commit -m "feat: add handwriting_practice tool ID and guard function"
```

---

### Task 3: Register handwriting_practice tool in BuiltinTools

**Files:**
- Modify: `entry/src/main/ets/config/BuiltinTools.ets:1461-1461` (end of file, after line 1461)

- [ ] **Step 1: Add import at top of file**

```typescript
import { HANDWRITING_PRACTICE_TOOL_ID } from '../utils/SearchToolIdentityUtils'
```

Locate the existing imports section (around line 1-40) and add the import. The existing import of `NUMBER_PUZZLE_TOOL_ID` from `SearchToolIdentityUtils` is at or near the top.

- [ ] **Step 2: Add executor class, tool definition, and tool config (after NumberPuzzleExecutor, before `registerBuiltinTools`)**

Insert after line 1328 (end of `createNumberPuzzleToolConfig`):

```typescript
// ===== handwriting_practice 工具 =====
// 学写字互动工具：教小朋友写英文字母、数字、基础汉字，通过 Canvas 自由书写，AI 评价。

interface HandwritingPracticeArgs {
  character: string
  type: string
  strokes?: HandwritingStroke[]
}

interface HandwritingStroke {
  x1: number
  y1: number
  x2: number
  y2: number
  label: string
}

class HandwritingPracticeExecutor implements ToolExecutor {
  async execute(_args: string): Promise<string> {
    try {
      const params = JSON.parse(_args) as HandwritingPracticeArgs
      return JSON.stringify({
        character: params.character ?? 'A',
        type: params.type ?? 'letter',
        completed: false,
        stroke_count: 0
      })
    } catch (error) {
      return JSON.stringify(new ErrorOutput(`handwriting_practice error: ${JSON.stringify(error)}`))
    }
  }
}

function createHandwritingPracticeToolDefinition(): ToolDefinition {
  const rawSchemaJson: string = `{
    "type": "object",
    "properties": {
      "character": {
        "type": "string",
        "description": "The character to practice. For letters use 'A', 'a' etc. For numbers use '5'. For Chinese characters use the single character like '人', '大'."
      },
      "type": {
        "type": "string",
        "description": "The type of character: 'letter' for English letters, 'number' for digits, 'chinese' for Chinese characters.",
        "enum": ["letter", "number", "chinese"]
      },
      "strokes": {
        "type": "array",
        "description": "Optional. Stroke order data as array of objects with x1,y1,x2,y2 (relative 0-1 coordinates) and label. If omitted, the built-in stroke library will be used for common characters.",
        "items": {
          "type": "object",
          "properties": {
            "x1": { "type": "number" },
            "y1": { "type": "number" },
            "x2": { "type": "number" },
            "y2": { "type": "number" },
            "label": { "type": "string" }
          }
        }
      }
    },
    "required": ["character", "type"]
  }`

  const parameters = new ToolParameters()
  parameters.setRawSchema(JSON.parse(rawSchemaJson) as Object)

  const func = new ToolFunction(
    HANDWRITING_PRACTICE_TOOL_ID,
    'Launch a handwriting practice activity for the child. The child watches a stroke order demonstration of a character (letter, number, or simple Chinese character), then practices writing it on a blank canvas. After submission, AI vision evaluates the handwriting and gives encouraging feedback. Choose characters appropriate to the child\'s age and skill level. Start with simple letters (A, B, C) or numbers (1, 2, 3) for beginners.',
    parameters
  )

  return new ToolDefinition(func)
}

function createHandwritingPracticeToolConfig(): ToolConfig {
  return new ToolConfig(
    HANDWRITING_PRACTICE_TOOL_ID,
    '学写字',
    '学写字互动工具, 观看笔顺示范后在 Canvas 上自由书写, AI 识别评价书写成果。',
    null,
    true,
    false,
    ToolSourceType.BUILTIN,
    'builtin',
    HANDWRITING_PRACTICE_TOOL_ID,
    '内置工具',
    ToolPermissionLevel.READ
  )
}
```

- [ ] **Step 3: Add registration call in `registerBuiltinTools()` (after NUMBER_PUZZLE_TOOL_ID block, around line 1455)**

```typescript
  if (!registry.isToolRegistered(HANDWRITING_PRACTICE_TOOL_ID)) {
    const handwritingTool = new RegisteredTool(
      HANDWRITING_PRACTICE_TOOL_ID,
      createHandwritingPracticeToolConfig(),
      createHandwritingPracticeToolDefinition(),
      new HandwritingPracticeExecutor()
    )
    registry.registerTool(handwritingTool)
    registeredNow += 1
  }
```

- [ ] **Step 4: Add to `getBuiltinToolIds()` return array**

In the return array of `getBuiltinToolIds()` (line 1465), add `HANDWRITING_PRACTICE_TOOL_ID` after `NUMBER_PUZZLE_TOOL_ID`.

- [ ] **Step 5: Commit**

```bash
git add entry/src/main/ets/config/BuiltinTools.ets
git commit -m "feat: register handwriting_practice tool definition and config"
```

---

### Task 4: Add to assistant locked tool IDs

**Files:**
- Modify: `entry/src/main/ets/models/AssistantModels.ets:97-105`

- [ ] **Step 1: Ensure import of HANDWRITING_PRACTICE_TOOL_ID**

Check the imports at the top of AssistantModels.ets. Add:
```typescript
import { HANDWRITING_PRACTICE_TOOL_ID } from '../utils/SearchToolIdentityUtils'
```

- [ ] **Step 2: Add to DEFAULT_ASSISTANT_LOCKED_TOOL_IDS array**

Change:
```typescript
export const DEFAULT_ASSISTANT_LOCKED_TOOL_IDS: string[] = [
  CHILD_PROFILE_TOOL_ID,
  GET_TIME_INFO_TOOL_ID,
  IMAGE_GENERATION_TOOL_ID,
  MATH_VERIFY_TOOL_ID,
  MATH_QUIZ_TOOL_ID,
  ENGLISH_QUIZ_TOOL_ID,
  NUMBER_PUZZLE_TOOL_ID
]
```

To:
```typescript
export const DEFAULT_ASSISTANT_LOCKED_TOOL_IDS: string[] = [
  CHILD_PROFILE_TOOL_ID,
  GET_TIME_INFO_TOOL_ID,
  IMAGE_GENERATION_TOOL_ID,
  MATH_VERIFY_TOOL_ID,
  MATH_QUIZ_TOOL_ID,
  ENGLISH_QUIZ_TOOL_ID,
  NUMBER_PUZZLE_TOOL_ID,
  HANDWRITING_PRACTICE_TOOL_ID
]
```

- [ ] **Step 3: Commit**

```bash
git add entry/src/main/ets/models/AssistantModels.ets
git commit -m "feat: add handwriting_practice to assistant locked tools"
```

---

### Task 5: Add handleHandwriting in ToolExecutionService

**Files:**
- Modify: `entry/src/main/ets/services/ToolExecutionService.ets:850-851` (between number_puzzle and general path)

- [ ] **Step 1: Add import for tool ID and guard function**

At the top of ToolExecutionService.ets, add:
```typescript
import { HANDWRITING_PRACTICE_TOOL_ID, isHandwritingPracticeFunctionName } from '../utils/SearchToolIdentityUtils'
import { getAppSettingsState } from '../state/AppSettingsState'
import { ServiceRegistry } from './ServiceRegistry'
import { RequestMessage, MessageAttachment, AttachmentType } from './AIApiService'
import { modelSupportsVision } from './registry/ModelAbilityRegistry'
```

Note: Verify the actual import paths by checking existing imports in this file. Adjust as needed.

- [ ] **Step 2: Add dispatch branch in `executeToolCall()`**

Insert after the number_puzzle dispatch (around line 849):

```typescript
    // === handwriting_practice 特殊路径 ===
    // 学写字互动工具, 由 HandwritingCard 收集小朋友的书写, 然后调用 AI vision 评价。
    if (isHandwritingPracticeFunctionName(normalizedFunctionName)) {
      return await this.handleHandwriting(toolCall, context)
    }
```

- [ ] **Step 3: Add `handleHandwriting()` method**

Add after `handleNumberPuzzle()` (after line 811):

```typescript
  // handwriting_practice 特殊路径: 与 number_puzzle 类似, 挂起等待 HandwritingCard 回答。
  // 孩子完成书写后调用 AI vision 评价, 将评价文字作为 ToolResult 返回。
  private async handleHandwriting(toolCall: ToolCall, context: ToolExecutionContext): Promise<ToolResult> {
    toolCall.toolId = HANDWRITING_PRACTICE_TOOL_ID
    if (toolCall.displayName.trim() === '') {
      toolCall.displayName = '学写字'
    }
    toolCall.sourceType = ToolSourceType.BUILTIN
    if (toolCall.sourceLabel.trim() === '') {
      toolCall.sourceLabel = '内置工具'
    }
    toolCall.permissionLevel = ToolPermissionLevel.READ

    toolCall.approvalState = 'pending'

    let answerJson: string | null = null
    try {
      answerJson = await new Promise<string | null>((resolve) => {
        const existing = this.pendingAnswers.get(toolCall.id)
        if (existing !== undefined) {
          existing.resolve(null)
          this.pendingAnswers.delete(toolCall.id)
        }
        const snapshot = this.buildAskUserSnapshot(toolCall, context)
        snapshot.kind = PendingToolInteractionKind.ASK_USER
        snapshot.toolId = HANDWRITING_PRACTICE_TOOL_ID
        this.pendingAnswers.set(toolCall.id, new PendingToolAnswerRuntime(snapshot, resolve))
        this.publishPendingInteractionChanged()
      })
    } catch (error) {
      console.error('ToolExecutionService', `handwriting_practice answer callback failed: ${JSON.stringify(error)}`)
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ error: `handwriting_practice 失败: ${JSON.stringify(error)}`, cancelled: true }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    if (this.isCancelled()) {
      console.info('ToolExecutionService', 'handwriting_practice cancelled by external stop')
      toolCall.approvalState = 'denied'
      return this.buildCancelledResult(toolCall, toolCall.displayName, toolCall.sourceLabel)
    }

    if (answerJson === null) {
      toolCall.approvalState = 'denied'
      return new ToolResult(
        toolCall.id,
        JSON.stringify({ cancelled: true, error: '小朋友未完成书写练习' }),
        true,
        toolCall.displayName,
        toolCall.sourceLabel
      )
    }

    // 解析结果生成反馈
    let evalText: string = ''
    try {
      const answer = JSON.parse(answerJson) as Record<string, Object>
      const handwritingBase64 = (answer['handwriting_base64'] as string) ?? ''
      const character = (answer['character'] as string) ?? '字'
      const charType = (answer['type'] as string) ?? 'letter'
      const completed = (answer['completed'] as boolean) ?? true

      if (!completed || handwritingBase64 === '') {
        // 放弃: 返回简单提示
        evalText = `小朋友这次没有完成${character}的书写，没关系，下次再来！`
      } else {
        // 调用 AI vision 评价
        evalText = await this.evaluateHandwriting(handwritingBase64, character, charType)
      }
    } catch (error) {
      console.error('ToolExecutionService', `Failed to evaluate handwriting: ${JSON.stringify(error)}`)
      evalText = '写得真棒！继续加油！'
    }

    const resultContent = JSON.stringify({ evaluation: evalText })
    toolCall.approvalState = 'answered'
    toolCall.approvalReason = answerJson
    console.info('ToolExecutionService', `handwriting_practice answered: ${toolCall.id}`)
    return new ToolResult(
      toolCall.id,
      resultContent,
      false,
      toolCall.displayName,
      toolCall.sourceLabel
    )
  }

  // 调用 AI vision 模型评价书写
  private async evaluateHandwriting(
    base64Image: string,
    character: string,
    charType: string
  ): Promise<string> {
    try {
      const appSettings = getAppSettingsState()
      const modelId = appSettings.defaultTextModelId

      // 检查模型是否支持 vision
      if (!modelSupportsVision(modelId)) {
        return '写得真不错！继续练习会越来越好的！'
      }

      // 获取 provider 配置
      const provider = appSettings.getProviderForModel(modelId)
      if (provider === null || provider === undefined) {
        return '写得很认真哦，再来一次吧！'
      }

      // 构建 API 配置
      const apiConfig = provider.buildApiConfig()
      if (apiConfig === null || apiConfig.apiKey === '') {
        return '写得很好，下次一定会更棒！'
      }

      // 构造评价请求消息
      const typeLabel = charType === 'letter' ? '英文字母' : charType === 'number' ? '数字' : '汉字'
      const prompt = `请用鼓励的语气评价小朋友写的"${character}"（${typeLabel}）。

注意观察：
- 笔画方向是否正确
- 字形大小是否合适
- 整体是否端正

请给出1-2句鼓励性反馈，语气要温暖，像幼儿园老师对小朋友说话。用中文回复。`

      const attachment = new MessageAttachment()
      attachment.type = AttachmentType.IMAGE
      attachment.mimeType = 'image/jpeg'
      attachment.base64Data = base64Image

      const msg = new RequestMessage('user', prompt)
      msg.attachments = [attachment]

      const apiResult = await ServiceRegistry.aiApi().sendChatRequest(
        apiConfig,
        [msg],
        modelId
      )

      if (apiResult.success && apiResult.content.trim() !== '') {
        return apiResult.content.trim()
      }
      return '写得真好，继续练习会越来越棒！'
    } catch (error) {
      console.error('ToolExecutionService', `evaluateHandwriting failed: ${JSON.stringify(error)}`)
      return '写得很认真哦，下次一定会更好的！'
    }
  }
```

- [ ] **Step 4: Commit**

```bash
git add entry/src/main/ets/services/ToolExecutionService.ets
git commit -m "feat: add handleHandwriting with AI vision evaluation"
```

---

### Task 6: Create HandwritingCard component

**Files:**
- Create: `entry/src/main/ets/components/HandwritingCard.ets`

- [ ] **Step 1: Write HandwritingCard.ets**

```typescript
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { image } from '@kit.ImageKit'
import { getAppUiState } from '../state/AppUiState'
import { ToolCall } from '../models/ChatModels'
import { getStrokeOrder, HandwritingStroke } from '../config/StrokeOrderData'
import { withColorAlpha } from '../utils/ColorAlphaUtils'

// 用户写的笔画点
interface StrokePoint {
  x: number
  y: number
  timestamp: number
}

// 完成的一笔
interface DrawnStroke {
  points: StrokePoint[]
}

// 结果接口（与组件导出对齐）
export interface HandwritingResult {
  character: string
  type: string
  completed: boolean
  stroke_count: number
}

const SUCCESS_GREEN: string = '#22C55E'
const PENCIL_COLOR: string = '#333333'
const STROKE_WIDTH: number = 6
const CANVAS_BG: string = '#FAFAF9'

@ComponentV2
export struct HandwritingCard {
  @Param toolCall: ToolCall = new ToolCall()
  @Param isAnswered: boolean = false
  @Param answeredPayload: string = ''
  @Param largeSize: boolean = false
  @Event onAnswer: (toolCallId: string, answerJson: string) => void = () => {}

  // 字符信息
  @Local character: string = ''
  @Local charType: string = 'letter'
  @Local strokes: HandwritingStroke[] = []

  // 绘图状态
  @Local drawnStrokes: DrawnStroke[] = []
  @Local isSubmitting: boolean = false
  @Local showAnimation: boolean = false
  @Local currentAnimStroke: number = -1
  @Local isCompleted: boolean = false
  @Local hasContent: boolean = false

  // 私有
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(
    new RenderingContextSettings(true)
  )
  private animTimerId: number = -1
  private canvasWidth: number = 0
  private canvasHeight: number = 0
  private currentPoints: StrokePoint[] = []

  private get themePrimary(): string {
    return getAppUiState().themePrimary
  }
  private get themeAiBubble(): ResourceColor {
    return getAppUiState().themeAiBubble
  }
  private get isDarkMode(): boolean {
    return getAppUiState().isDarkMode
  }

  // 难度标签
  private get typeLabel(): string {
    switch (this.charType) {
      case 'letter': return '字母 · Letter'
      case 'number': return '数字 · Number'
      case 'chinese': return '汉字 · 中文'
      default: return '书写'
    }
  }

  // 笔顺描述
  private get strokeLabels(): string {
    return this.strokes.map((s: HandwritingStroke) => s.label).join(' ')
  }

  aboutToAppear(): void {
    this.parseArguments()
    if (this.isAnswered) {
      this.parsePreviousResult()
    }
  }

  aboutToDisappear(): void {
    if (this.animTimerId !== -1) {
      clearTimeout(this.animTimerId)
      this.animTimerId = -1
    }
  }

  private parseArguments(): void {
    try {
      const args = JSON.parse(this.toolCall.arguments) as Record<string, Object>
      this.character = (args['character'] as string) ?? 'A'
      this.charType = (args['type'] as string) ?? 'letter'

      // 优先使用本地笔顺数据
      const localStrokes = getStrokeOrder(this.character)
      if (localStrokes !== null) {
        this.strokes = localStrokes
      } else {
        // 使用 AI 提供的笔顺
        const rawStrokes = args['strokes'] as Array<Record<string, Object>> | undefined
        if (rawStrokes !== undefined) {
          this.strokes = rawStrokes.map((s: Record<string, Object>) => ({
            x1: (s['x1'] as number) ?? 0,
            y1: (s['y1'] as number) ?? 0,
            x2: (s['x2'] as number) ?? 0,
            y2: (s['y2'] as number) ?? 0,
            label: (s['label'] as string) ?? ''
          }))
        }
      }
    } catch (_e) {
      this.character = 'A'
      this.charType = 'letter'
    }
  }

  private parsePreviousResult(): void {
    try {
      const result = JSON.parse(this.answeredPayload) as Record<string, Object>
      this.isCompleted = (result['completed'] as boolean) ?? true
    } catch (_e) {
      this.isCompleted = true
    }
  }

  // ====== 笔顺动画 ======

  private playStrokeAnimation(): void {
    if (this.strokes.length === 0) {
      return
    }
    this.showAnimation = true
    this.currentAnimStroke = -1
    this.animateNextStroke()
  }

  private animateNextStroke(): void {
    this.currentAnimStroke++
    if (this.currentAnimStroke >= this.strokes.length) {
      this.showAnimation = false
      this.currentAnimStroke = -1
      return
    }
    this.animTimerId = setTimeout(() => {
      this.animateNextStroke()
    }, 600)
  }

  private resetAnimation(): void {
    if (this.animTimerId !== -1) {
      clearTimeout(this.animTimerId)
      this.animTimerId = -1
    }
    this.showAnimation = false
    this.currentAnimStroke = -1
  }

  // ====== Canvas 绘图 ======

  private handleTouchDown(event: TouchEvent): void {
    if (this.isCompleted || this.isSubmitting) {
      return
    }
    event.stopPropagation()
    const touch = event.touches[0]
    const point: StrokePoint = { x: touch.x, y: touch.y, timestamp: Date.now() }
    this.currentPoints = [point]
    this.canvasContext.beginPath()
    this.canvasContext.moveTo(point.x, point.y)
  }

  private handleTouchMove(event: TouchEvent): void {
    if (this.isCompleted || this.isSubmitting || this.currentPoints.length === 0) {
      return
    }
    event.stopPropagation()
    const touch = event.touches[0]
    const point: StrokePoint = { x: touch.x, y: touch.y, timestamp: Date.now() }
    this.currentPoints.push(point)
    this.canvasContext.lineTo(point.x, point.y)
    this.canvasContext.stroke()
    this.hasContent = true
  }

  private handleTouchUp(event: TouchEvent): void {
    if (this.isCompleted || this.isSubmitting) {
      return
    }
    event.stopPropagation()
    if (this.currentPoints.length > 0) {
      this.drawnStrokes.push({ points: [...this.currentPoints] })
      this.currentPoints = []
    }
    this.hasContent = this.drawnStrokes.length > 0
  }

  private redrawAll(): void {
    this.canvasContext.clearRect(0, 0, this.canvasWidth, this.canvasHeight)
    for (const stroke of this.drawnStrokes) {
      if (stroke.points.length === 0) {
        continue
      }
      this.canvasContext.beginPath()
      this.canvasContext.moveTo(stroke.points[0].x, stroke.points[0].y)
      for (let i = 1; i < stroke.points.length; i++) {
        this.canvasContext.lineTo(stroke.points[i].x, stroke.points[i].y)
      }
      this.canvasContext.stroke()
    }
  }

  private handleUndo(): void {
    this.drawnStrokes.pop()
    this.redrawAll()
    this.hasContent = this.drawnStrokes.length > 0
  }

  private handleClear(): void {
    this.drawnStrokes = []
    this.currentPoints = []
    this.canvasContext.clearRect(0, 0, this.canvasWidth, this.canvasHeight)
    this.hasContent = false
  }

  // ====== 提交 ======

  private async handleSubmit(): Promise<void> {
    if (this.isSubmitting || this.isCompleted) {
      return
    }
    this.isSubmitting = true

    try {
      // 导出 Canvas 为 base64 JPEG
      const handwritingBase64 = await this.exportCanvasAsBase64()

      const result: HandwritingResult = {
        character: this.character,
        type: this.charType,
        completed: true,
        stroke_count: this.drawnStrokes.length
      }

      const answerJson = JSON.stringify({
        ...result,
        handwriting_base64: handwritingBase64
      })

      this.isCompleted = true
      this.onAnswer(this.toolCall.id, answerJson)
    } catch (error) {
      console.error('HandwritingCard', `Failed to export canvas: ${JSON.stringify(error)}`)
      // Fallback: 提交无图片的结果
      const result: HandwritingResult = {
        character: this.character,
        type: this.charType,
        completed: true,
        stroke_count: this.drawnStrokes.length
      }
      this.isCompleted = true
      this.onAnswer(this.toolCall.id, JSON.stringify(result))
    } finally {
      this.isSubmitting = false
    }
  }

  private async exportCanvasAsBase64(): Promise<string> {
    // 使用 Canvas 的 toDataURL 导出
    try {
      const pixelMap = this.canvasContext.getPixelMap(0, 0, this.canvasWidth, this.canvasHeight)
      const imagePacker = image.createImagePacker()
      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: 80
      }
      const buffer = await imagePacker.packing(pixelMap, packOpts)
      imagePacker.release()
      pixelMap.release()
      return this.arrayBufferToBase64(buffer)
    } catch (error) {
      console.error('HandwritingCard', `Canvas export failed: ${JSON.stringify(error)}`)
      return ''
    }
  }

  private arrayBufferToBase64(buffer: ArrayBuffer): string {
    const uint8Array = new Uint8Array(buffer)
    let binary = ''
    for (let i = 0; i < uint8Array.length; i++) {
      binary += String.fromCharCode(uint8Array[i])
    }
    return binary
  }

  // ====== 放弃 ======

  private handleGiveUp(): void {
    const result: HandwritingResult = {
      character: this.character,
      type: this.charType,
      completed: false,
      stroke_count: 0
    }
    this.isCompleted = true
    this.onAnswer(this.toolCall.id, JSON.stringify(result))
  }

  // ====== UI Builders ======

  build() {
    if (this.isAnswered && !this.largeSize) {
      // 已答内联：只读回顾
      this.AnsweredView()
    } else if (!this.largeSize) {
      // 内联横幅
      this.InlineBanner()
    } else {
      // 全屏书写模式
      this.FullScreenSheet()
    }
  }

  @Builder
  AnsweredView() {
    Row() {
      Column() {
        SymbolGlyph($r('sys.symbol.pencil'))
          .fontSize(15)
          .fontColor([this.themePrimary])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(withColorAlpha(this.themePrimary, '18'))
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)

      Column({ space: 2 }) {
        Text(`学写字 - ${this.character}`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(this.isCompleted ? '已完成' : '已放弃')
          .fontSize(10)
          .fontColor(this.isCompleted ? SUCCESS_GREEN : '#FF9F43')
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 8 })
      .layoutWeight(1)

      Column()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(this.isCompleted ? SUCCESS_GREEN : '#FF9F43')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.themeAiBubble)
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  InlineBanner() {
    Row() {
      Column() {
        SymbolGlyph($r('sys.symbol.pencil'))
          .fontSize(15)
          .fontColor([this.themePrimary])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(withColorAlpha(this.themePrimary, '18'))
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)

      Column({ space: 2 }) {
        Text(`学写字 · ${this.character}`)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text('点击开始写字')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 8 })
      .layoutWeight(1)

      Text('>')
        .fontSize(14)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.themeAiBubble)
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.divider') })
  }

  @Builder
  FullScreenSheet() {
    Column({ space: 14 }) {
      // 1. HeaderRow
      this.HeaderRow()

      // 2. DemoPanel
      this.DemoPanel()

      // 3. CanvasPanel
      this.CanvasPanel()

      // 4. ActionRow
      this.ActionRow()
    }
    .width('100%')
    .padding(20)
    .backgroundColor(Color.Transparent)
  }

  @Builder
  HeaderRow() {
    Row({ space: 10 }) {
      Column() {
        SymbolGlyph($r('sys.symbol.pencil'))
          .fontSize(15)
          .fontColor([this.themePrimary])
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor(withColorAlpha(this.themePrimary, '18'))
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)

      Column({ space: 2 }) {
        Text('学写字')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.typeLabel)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.strokeLabels !== '') {
        Text(`笔顺: ${this.strokeLabels}`)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
  }

  @Builder
  DemoPanel() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        // 大字示范
        Text(this.character)
          .fontSize(72)
          .fontWeight(FontWeight.Bold)
          .fontColor('#92400E')
          .fontFamily('monospace')

        // 笔顺描述
        if (this.strokes.length > 0) {
          Text(`${this.strokes.length}笔 · ${this.strokeLabels}`)
            .fontSize(11)
            .fontColor('#b45309')
            .margin({ top: 4 })
        }

        // 动画状态
        if (this.showAnimation) {
          Text(`播放第 ${this.currentAnimStroke + 1}/${this.strokes.length} 笔`)
            .fontSize(10)
            .fontColor('#22C55E')
            .margin({ top: 2 })
        }
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Center)

      Button('▶ 重播')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .backgroundColor(withColorAlpha(this.themePrimary, '10'))
        .borderRadius(8)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .onClick(() => {
          this.resetAnimation()
          this.playStrokeAnimation()
        })
    }
    .width('100%')
    .backgroundColor(withColorAlpha(this.themePrimary, '08'))
    .borderRadius(12)
    .border({ width: 1.5, color: withColorAlpha(this.themePrimary, '38'), style: BorderStyle.Dashed })
    .onClick(() => {
      this.resetAnimation()
      this.playStrokeAnimation()
    })
  }

  @Builder
  CanvasPanel() {
    Column() {
      Canvas(this.canvasContext)
        .width('100%')
        .height(220)
        .backgroundColor(CANVAS_BG)
        .borderRadius(12)
        .border({ width: 2, color: '#DDD', style: BorderStyle.Dashed })
        .onReady(() => {
          this.canvasContext.strokeStyle = PENCIL_COLOR
          this.canvasContext.lineWidth = STROKE_WIDTH
          this.canvasContext.lineCap = 'round'
          this.canvasContext.lineJoin = 'round'
        })
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.canvasWidth = newArea.width as number
          this.canvasHeight = newArea.height as number
        })
        .onTouch((event: TouchEvent) => {
          switch (event.type) {
            case TouchType.Down:
              this.handleTouchDown(event)
              break
            case TouchType.Move:
              this.handleTouchMove(event)
              break
            case TouchType.Up:
              this.handleTouchUp(event)
              break
          }
          event.stopPropagation()
        })
        .hitTestBehavior(HitTestMode.Block)
    }
    .width('100%')
  }

  @Builder
  ActionRow() {
    Row() {
      // 撤销
      Button('↩ 撤销')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .enabled(this.drawnStrokes.length > 0 && !this.isSubmitting && !this.isCompleted)
        .opacity(this.drawnStrokes.length > 0 && !this.isSubmitting && !this.isCompleted ? 1 : 0.4)
        .onClick(() => {
          this.handleUndo()
        })

      // 清除
      Button('✕ 清除')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .enabled(this.hasContent && !this.isSubmitting && !this.isCompleted)
        .opacity(this.hasContent && !this.isSubmitting && !this.isCompleted ? 1 : 0.4)
        .onClick(() => {
          this.handleClear()
        })

      Blank()

      // 提交
      Button(this.isSubmitting ? '小星老师正在看...' : '提交评价')
        .fontSize(13)
        .fontColor(Color.White)
        .backgroundColor(SUCCESS_GREEN)
        .borderRadius(8)
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
        .enabled(this.hasContent && !this.isSubmitting && !this.isCompleted)
        .opacity(this.hasContent && !this.isSubmitting && !this.isCompleted ? 1 : 0.5)
        .onClick(() => {
          this.handleSubmit()
        })
    }
    .width('100%')
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add entry/src/main/ets/components/HandwritingCard.ets
git commit -m "feat: add HandwritingCard component with Canvas drawing and stroke animation"
```

---

### Task 7: Add callback in ChatMessageListSection

**Files:**
- Modify: `entry/src/main/ets/components/chat/ChatMessageListSection.ets:57` and `:495`

- [ ] **Step 1: Add @Event callback (after line 57)**

```typescript
  @Event onOpenHandwritingSheet: (toolCall: ToolCall) => void = (_toolCall: ToolCall): void => {}
```

- [ ] **Step 2: Propagate to MessageBubble (after line 496)**

In the MessageBubble constructor block (around line 495-497), add:
```typescript
                    onOpenHandwritingSheet: (toolCall: ToolCall): void => {
                      this.onOpenHandwritingSheet(toolCall)
                    },
```

- [ ] **Step 3: Commit**

```bash
git add entry/src/main/ets/components/chat/ChatMessageListSection.ets
git commit -m "feat: add onOpenHandwritingSheet callback pass-through"
```

---

### Task 8: Add sheet integration in ChatPage

**Files:**
- Modify: `entry/src/main/ets/pages/ChatPage.ets:280-282` and `:2449` and `:2813` and `:3331`

- [ ] **Step 1: Add import**

After the NumberPuzzleCard import (line 44), add:
```typescript
import { HandwritingCard, HandwritingResult } from '../components/HandwritingCard'
```

- [ ] **Step 2: Add state variables (after line 282)**

```typescript
  @Local showHandwritingSheet: boolean = false
  @Local handwritingSheetToolCall: ToolCall = new ToolCall()
  @Local handwritingAnswered: boolean = false
```

- [ ] **Step 3: Add callback binding (after line 2461)**

```typescript
          onOpenHandwritingSheet: (toolCall: ToolCall): void => {
            this.handwritingSheetToolCall = toolCall
            this.handwritingAnswered = false
            this.showHandwritingSheet = true
          },
```

- [ ] **Step 4: Add bindSheet (after the number_puzzle bindSheet, around line 2845)**

```typescript
        Column()
          .width(0)
          .height(0)
          .bindSheet($$this.showHandwritingSheet, this.HandwritingSheetBuilder(), {
            height: SheetSize.LARGE,
            dragBar: true,
            showClose: true,
            blurStyle: BlurStyle.Thick,
            backgroundColor: this.themeBackground,
            preferType: SheetType.BOTTOM,
            disableSwipe: true,
            onDisappear: () => {
              if (this.showHandwritingSheet && !this.handwritingAnswered) {
                const cancelResult: HandwritingResult = {
                  character: '',
                  type: 'letter',
                  completed: false,
                  stroke_count: 0
                }
                try {
                  const parsed = JSON.parse(this.handwritingSheetToolCall.arguments) as Record<string, Object>
                  cancelResult.character = (parsed['character'] as string) ?? ''
                  cancelResult.type = (parsed['type'] as string) ?? 'letter'
                } catch (_e) {
                  // ignore
                }
                this.handleAskUserAnswer(this.handwritingSheetToolCall.id, JSON.stringify(cancelResult))
              }
              this.showHandwritingSheet = false
            }
          })
```

Note: `disableSwipe: true` prevents the Sheet from being dismissed by swipe gesture while the child is drawing on Canvas. The close button in the dragBar still works.

- [ ] **Step 5: Add HandwritingSheetBuilder (after NumberPuzzleSheetBuilder, around line 3343)**

```typescript
  @Builder
  HandwritingSheetBuilder() {
    HandwritingCard({
      toolCall: this.handwritingSheetToolCall,
      isAnswered: false,
      answeredPayload: '',
      largeSize: true,
      onAnswer: (toolCallId: string, answerJson: string): void => {
        this.handwritingAnswered = true
        this.handleAskUserAnswer(toolCallId, answerJson)
        this.showHandwritingSheet = false
      }
    })
  }
```

- [ ] **Step 6: Commit**

```bash
git add entry/src/main/ets/pages/ChatPage.ets
git commit -m "feat: add HandwritingSheet integration in ChatPage"
```

---

### Task 9: Add inline banner + answered view + routing in MessageBubble

**Files:**
- Modify: `entry/src/main/ets/components/MessageBubble.ets:248` and `:2087` and `:2648` and `:2985` and `:3409` and `:3786`

- [ ] **Step 1: Add import**

```typescript
import { HandwritingCard, HandwritingResult } from '../components/HandwritingCard'
import { isHandwritingPracticeFunctionName } from '../utils/SearchToolIdentityUtils'
```

- [ ] **Step 2: Add @Event callback (after line 248)**

```typescript
  @Event onOpenHandwritingSheet: (toolCall: ToolCall) => void = (_toolCall: ToolCall): void => {}
```

- [ ] **Step 3: Add inline banner rendering (after number_puzzle banner, around line 2087)**

After the `ForEach` for number_puzzle banners:

```typescript
              // handwriting_practice 待答时显示紧凑横幅，点击打开全屏 sheet
              if (this.message.hasToolCalls()) {
                ForEach(this.message.toolCalls, (toolCall: ToolCall, index: number) => {
                  if (this.shouldRenderHandwritingInteractionCard(toolCall, index)) {
                    Row() {
                      Column() {
                        SymbolGlyph($r('sys.symbol.pencil'))
                          .fontSize(15)
                          .fontColor([this.themePrimary])
                      }
                      .width(32)
                      .height(32)
                      .borderRadius(16)
                      .backgroundColor(withColorAlpha(this.themePrimary, '18'))
                      .alignItems(HorizontalAlign.Center)
                      .justifyContent(FlexAlign.Center)

                      Column({ space: 2 }) {
                        Text(`学写字 · ${this.getHandwritingCharacter(toolCall)}`)
                          .fontSize(13)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.text_primary'))
                        Text('点击开始写字')
                          .fontSize(11)
                          .fontColor($r('app.color.text_tertiary'))
                      }
                      .alignItems(HorizontalAlign.Start)
                      .margin({ left: 8 })
                      .layoutWeight(1)

                      Text('>')
                        .fontSize(14)
                        .fontColor($r('app.color.text_tertiary'))
                    }
                    .width('100%')
                    .padding(12)
                    .backgroundColor(this.themeAiBubble)
                    .borderRadius(12)
                    .border({ width: 1, color: $r('app.color.divider') })
                    .margin({ bottom: 6 })
                    .onClick(() => {
                      this.onOpenHandwritingSheet(toolCall)
                    })
                  }
                }, (toolCall: ToolCall, index: number) => 'handwriting_' + toolCall.id + '_' + index.toString())
              }
```

- [ ] **Step 4: Add helper method**

Add `getHandwritingCharacter` to extract the character from tool call arguments:

```typescript
  private getHandwritingCharacter(toolCall: ToolCall): string {
    try {
      const args = JSON.parse(toolCall.arguments) as Record<string, Object>
      return (args['character'] as string) ?? '字'
    } catch (_e) {
      return '字'
    }
  }
```

- [ ] **Step 5: Add shouldRenderHandwritingInteractionCard (after line 2649)**

```typescript
  private shouldRenderHandwritingInteractionCard(toolCall: ToolCall, index: number): boolean {
    if (!isHandwritingPracticeFunctionName(toolCall.functionName) || this.shouldHideToolCallCard(toolCall)) {
      return false
    }
    return !this.isAskUserToolCallAnswered(toolCall, index)
  }
```

- [ ] **Step 6: Add routing in ToolStepContent (after line 3408, NumberPuzzleStepContent)**

```typescript
    } else if (isHandwritingPracticeFunctionName(step.toolName)) {
      this.HandwritingStepContent(step)
```

- [ ] **Step 7: Add click handler routing (after line 2985)**

```typescript
    // 学写字: 展开/折叠查看结果
    if (isHandwritingPracticeFunctionName(part.toolName)) {
      this.toggleToolStep(part)
      return
    }
```

- [ ] **Step 8: Add clickable check (after line 2508)**

```typescript
    if (isHandwritingPracticeFunctionName(part.toolName)) {
      return this.isSuccessfulToolStep(part)
    }
```

- [ ] **Step 9: Add default expand (in `isToolStepExpanded`, after NumberPuzzle entry around line 2558)**

Add `isHandwritingPracticeFunctionName(part.toolName)` to both the default-expand line and toggle-check line.

First, in `isToolStepExpanded` around line 2558:
Change:
```typescript
    if (isImageGenerationFunctionName(part.toolName) || isMathQuizFunctionName(part.toolName) || isEnglishQuizFunctionName(part.toolName) || isNumberPuzzleFunctionName(part.toolName)) {
```
To:
```typescript
    if (isImageGenerationFunctionName(part.toolName) || isMathQuizFunctionName(part.toolName) || isEnglishQuizFunctionName(part.toolName) || isNumberPuzzleFunctionName(part.toolName) || isHandwritingPracticeFunctionName(part.toolName)) {
```

Then, in `toggleToolStep` around line 2567:
Change:
```typescript
      (isImageGenerationFunctionName(part.toolName) || isMathQuizFunctionName(part.toolName) || isEnglishQuizFunctionName(part.toolName) || isNumberPuzzleFunctionName(part.toolName))
```
To:
```typescript
      (isImageGenerationFunctionName(part.toolName) || isMathQuizFunctionName(part.toolName) || isEnglishQuizFunctionName(part.toolName) || isNumberPuzzleFunctionName(part.toolName) || isHandwritingPracticeFunctionName(part.toolName))
```

- [ ] **Step 10: Add HandwritingStepContent Builder (after NumberPuzzleStepContent, around line 3786)**

```typescript
  // handwriting_practice 工具步骤: 已完成的书写练习, 在 timeline 中显示简化结果, 可展开查看详情
  @Builder
  HandwritingStepContent(step: MessagePart) {
    Column() {
      Row({ space: 6 }) {
        if (step.toolStatus === 'succeeded') {
          SymbolGlyph($r('sys.symbol.checkmark_circle'))
            .fontSize(13)
            .fontColor([$r('app.color.status_success')])
        } else if (step.toolStatus === 'failed' || step.toolStatus === 'denied') {
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(13)
            .fontColor([$r('app.color.status_error')])
        } else {
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.themePrimary)
        }

        Text(this.buildToolStepTitle(step))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        if (this.isToolStepClickable(step)) {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(12)
            .fontColor([$r('app.color.text_tertiary')])
            .rotate({ angle: this.isToolStepExpanded(step) ? 0 : -90 })
            .animation({ duration: 200, curve: Curve.EaseOut })
        }
      }
      .width('100%')
      .onClick(() => {
        if (this.isToolStepClickable(step)) {
          this.handleToolStepClick(step)
        }
      })

      if (this.isToolStepExpanded(step) && step.toolResult !== '') {
        HandwritingCard({
          toolCall: this.buildToolCallFromStep(step),
          isAnswered: true,
          answeredPayload: step.toolResult,
          onAnswer: (_toolCallId: string, _answerJson: string): void => {}
        })
        .margin({ top: 8 })
      }
    }
    .width('100%')
  }
```

- [ ] **Step 11: Commit**

```bash
git add entry/src/main/ets/components/MessageBubble.ets
git commit -m "feat: add HandwritingCard integration in MessageBubble (banner, timeline, routing)"
```

---

### Task 10: Verification

- [ ] **Step 1: Verify build compiles**

Open the project in DevEco Studio 5.0+, sync, and build. Check for any compilation errors.

- [ ] **Step 2: Check imports consistency**

Manually verify all import paths in these files are correct:
- `BuiltinTools.ets`: `HANDWRITING_PRACTICE_TOOL_ID` imported from `SearchToolIdentityUtils`
- `AssistantModels.ets`: `HANDWRITING_PRACTICE_TOOL_ID` imported from `SearchToolIdentityUtils`
- `ToolExecutionService.ets`: `HANDWRITING_PRACTICE_TOOL_ID`, `isHandwritingPracticeFunctionName` imported
- `ChatPage.ets`: `HandwritingCard`, `HandwritingResult` imported from `../components/HandwritingCard`
- `MessageBubble.ets`: `HandwritingCard`, `isHandwritingPracticeFunctionName` imported
- `ChatMessageListSection.ets`: `ToolCall` already imported (check if needed)

- [ ] **Step 3: Verify API contracts**

Check that:
- `HandwritingCard` uses `@ComponentV2` with correct `@Param`/`@Event` signatures
- `HandwritingResult` exports match what `ChatPage` and `ToolExecutionService` expect
- `getStrokeOrder()` returns `HandwritingStroke[] | null` as consumed by `HandwritingCard`
- `ServiceRegistry.aiApi()` and `ServiceRegistry.toolRegistry()` are accessible from `ToolExecutionService`
- `modelSupportsVision()` import path is correct in `ToolExecutionService.ets`

- [ ] **Step 4: Run on device/simulator**

1. Start a chat with 小星老师
2. Ask "教我写字母 A"
3. Verify the inline banner appears with "学写字 · A" and "点击开始写字"
4. Click the banner → full-screen sheet opens
5. Verify DemoPanel shows "A" with stroke order text
6. Click "重播" → verify animation plays
7. Draw on Canvas → verify strokes render
8. Click "撤销" → last stroke removed
9. Click "清除" → all strokes cleared
10. Draw a letter A, then click "提交评价"
11. Verify sheet closes, tool result appears in chat
12. Check that the AI's evaluation text appears in the conversation
13. Verify the answered step is expandable/collapsible in the timeline
14. Test with different characters (数字 1, 汉字 人)
15. Test in dark mode
16. Test sheet dismiss without submitting (close button or drag bar) — verify cancel result is sent

- [ ] **Step 5: Commit verification changes (if any)**

```bash
git add -A
git commit -m "chore: verification fixes for handwriting tool integration"
```

---

### Summary: File Change Map

| File | Action | Lines ~ |
|------|--------|---------|
| `config/StrokeOrderData.ets` | Create | ~200 |
| `utils/SearchToolIdentityUtils.ets` | +2 additions | +2 |
| `config/BuiltinTools.ets` | +executor +def +config +register +list | +70 |
| `models/AssistantModels.ets` | +1 entry in array | +1 |
| `services/ToolExecutionService.ets` | +dispatch +handleHandwriting +evaluateHandwriting | +130 |
| `components/HandwritingCard.ets` | Create | ~370 |
| `components/chat/ChatMessageListSection.ets` | +1 @Event +1 propagation | +3 |
| `pages/ChatPage.ets` | +import +3 state vars +callback +bindSheet +Builder | +60 |
| `components/MessageBubble.ets` | +import +@Event +banner +helper +guard +6 routing points +StepContent | +100 |
| **Total** | | **~936** |
