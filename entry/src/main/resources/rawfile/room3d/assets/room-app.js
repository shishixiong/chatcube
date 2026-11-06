/* 应用层：单词卡、标签、词汇表、发音与场景状态同步。 */
(function () {
  'use strict';

  const DATA = window.WordRoomData;
  const OBJECTS = DATA.objects;
  const byId = new Map(OBJECTS.map((item) => [item.id, item]));
  const categoryById = DATA.categories;
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  const state = {
    selectedId: null,
    discovered: new Set(),
    labelsVisible: false,
    autoSpeak: true,
    modalOpen: false,
    ready: false,
    celebrated: false,
    lastFocus: null,
    modalTimer: 0,
    loaderTimer: 0,
    toastTimer: 0,
    speechTimer: 0,
    speechSeq: 0,
    activeRoom: 'overview',
    activeArea: null,
    roomApplied: false,
    labelsMoving: false,
    // 视角：orbit = 上帝视角（默认），walk = 走进去的第一人称
    mode: 'orbit',
    pendingWalk: false,
    labelsBeforeWalk: null,
    walkVisible: 0,
    walkEye: 'stand',
    walkRange: 5,
    // 方位语音：第二次点同一件物品时才念「在你左手边」。第一次已经念过中文和单词，
    // 再补一句方位就把音拖到 8 秒开外，小朋友听不完。
    walkHintTimer: 0,
    walkHintLast: null,
    walkHintAt: 0,
    // 方位语音总开关：默认开，用户点一下关掉就记在本机
    walkHint: true
  };

  // 同一条方位提示的冷却：停稳后原地转头，同一件东西不重复念
  const WALK_HINT_COOLDOWN = 9000;

  const el = (id) => document.getElementById(id);
  const dom = {};
  let room = null;
  let labelMetrics = new Map();
  let rowsById = new Map();

  // 鸿蒙宿主桥：RoomNativeBridge 由 ArkWeb javaScriptProxy 注入。宿主栏由原生接管，
  // 页面本身始终使用 host 布局（这份 index.html 只在小词屋 sheet 里被加载）。
  function getBridge() {
    return typeof window !== 'undefined' && window.RoomNativeBridge ? window.RoomNativeBridge : null;
  }
  function bridgeCall(name, ...args) {
    const target = getBridge();
    if (!target) return null;
    try {
      const fn = target[name];
      return typeof fn === 'function' ? fn.apply(target, args) : null;
    } catch (error) {
      return null;
    }
  }
  document.body.classList.add('room-host');

  function boot() {
    // 方位语音的开关记在本机：小朋友关过一次，下次进来别再自动说话
    try {
      const saved = window.localStorage.getItem('wordroom.walkHint');
      if (saved === '0') state.walkHint = false;
    } catch (error) {
      /* 读不到就用默认值 */
    }
    syncWalkHint();
    cacheDom();
    validateData();
    updateStaticCounts();
    syncRoomChrome();
    buildLabelLayer();
    buildDotGrid();
    buildGlossary();
    bindUI();
    startScene();
    if (document.fonts && document.fonts.ready) {
      document.fonts.ready.then(() => {
        if (state.labelsVisible) {
          measureLabels();
          updateLabels();
        }
      });
    }
  }

  function cacheDom() {
    [
      'stage', 'scene-canvas', 'sceneLoader', 'sceneError', 'retryScene',
      'labelToggle', 'label-layer', 'label-lines', 'labels', 'hoverChip',
      'resetView', 'panel', 'panelTitle', 'panelBody', 'progressChip', 'progressCount',
      'closeWord', 'welcomeView', 'wordView', 'wordCategory', 'wordIndex',
      'wordEnglish', 'wordPhonetic', 'wordZh', 'wordDefinition', 'wordExample',
      'pronounceButton', 'pronounceLabel', 'prevWord', 'nextWord', 'wordNavIndex',
      'dotGrid', 'welcomeCount', 'openGlossary', 'openGlossaryInline',
      'glossaryModal', 'glossaryBody', 'closeGlossary', 'toast', 'liveRegion',
      'roomTabs', 'areaTabs', 'sceneEyebrow', 'sceneHeading', 'sceneSize', 'sceneCount',
      'walkToggle', 'walkControls', 'walkRange', 'walkRangeOut', 'walkEye', 'walkBack', 'walkForward',
      'walkHint'
    ].forEach((id) => {
      dom[id] = el(id);
    });
  }

  const TOTAL = OBJECTS.length;
  const CATEGORY_ORDER = ['living', 'dining', 'kitchen', 'child', 'master', 'balcony'];
  const ROOM_ORDER = DATA.roomOrder || ['main', 'child', 'master'];
  const VIEW_ORDER = ['overview'].concat(ROOM_ORDER);
  const ROOM_META = DATA.rooms || {};
  const objectsInRoom = (roomId) =>
    roomId === 'overview' ? OBJECTS : OBJECTS.filter((item) => item.room === roomId);

  function validateData() {
    if (TOTAL < 1) throw new Error('场景没有单词数据');
    const ids = new Set();
    OBJECTS.forEach((item) => {
      if (ids.has(item.id)) throw new Error('重复的对象 id: ' + item.id);
      ids.add(item.id);
      if (!item.word || !item.phonetic || !item.zh || !item.kidDefinition || !item.example) {
        throw new Error('单词数据不完整: ' + item.id);
      }
      if (item.kidDefinition.length > 20) {
        throw new Error('儿童解释超过 20 个字符: ' + item.id + ' (' + item.kidDefinition.length + ')');
      }
      if (ROOM_ORDER.indexOf(item.room) < 0) {
        throw new Error('物品缺少房间归属: ' + item.id);
      }
      if (!ROOM_META[item.room]) {
        throw new Error('缺少房间文案: ' + item.room);
      }
    });
    CATEGORY_ORDER.forEach((category) => {
      const meta = window.WordRoomData.categories[category];
      if (!meta) throw new Error('缺少分类文案: ' + category);
      const count = OBJECTS.filter((item) => item.category === category).length;
      if (count !== meta.count) {
        throw new Error('分类 ' + category + ' 数量不一致: ' + count + ' vs ' + meta.count);
      }
    });
    const unknown = OBJECTS.filter((item) => CATEGORY_ORDER.indexOf(item.category) < 0);
    if (unknown.length) throw new Error('未知分类: ' + unknown[0].category);
  }

  function updateStaticCounts() {
    ROOM_ORDER.forEach((roomId) => {
      const cell = document.querySelector(`.room-stat[data-room="${roomId}"]`);
      if (cell) cell.querySelector('strong').textContent = String(objectsInRoom(roomId).length);
    });
    document.querySelectorAll('[data-total]').forEach((node) => {
      node.textContent = String(TOTAL);
    });
  }

  function startScene() {
    stopSpeech();
    if (room) {
      room.destroy();
      room = null;
    }
    state.ready = false;
    dom['scene-canvas'].tabIndex = -1;
    window.clearTimeout(state.loaderTimer);
    state.labelsVisible = false;
    dom.labelToggle.setAttribute('aria-checked', 'false');
    dom['label-layer'].hidden = true;
    if (state.selectedId) {
      state.selectedId = null;
      closeWordView();
      updateProgress();
      updateSelectedLabel();
    }
    dom.stage.classList.remove('has-scene-error');
    dom.sceneError.hidden = true;
    dom.sceneLoader.hidden = false;
    dom.sceneLoader.classList.remove('is-hidden');
    dom.labelToggle.disabled = true;
    dom.resetView.disabled = true;

    if (!window.THREE || !window.WordRoomModels || !window.RoomExperience) {
      showSceneError();
      return;
    }

    try {
      room = new window.RoomExperience(dom['scene-canvas'], {
        onReady: () => {
          state.ready = true;
          // onReady 在构造函数里触发，此时模块级的 room 还没赋值，房间切换要挪到下一个 tick
          window.setTimeout(() => {
            if (!room) return;
            room.setRoom(state.activeRoom);
            if (state.activeArea && state.activeRoom === 'main' && typeof room.focusArea === 'function') {
              room.focusArea(state.activeArea);
            }
            state.roomApplied = true;
            syncRoomChrome();
            if (state.pendingWalk) setWalkMode('walk', { silent: true });
            if (state.labelsVisible) {
              measureLabels();
              updateLabels();
            }
          }, 0);
          bridgeCall('onReady');
          dom['scene-canvas'].tabIndex = 0;
          dom.resetView.disabled = false;
          dom.sceneLoader.classList.add('is-hidden');
          window.clearTimeout(state.loaderTimer);
          state.loaderTimer = window.setTimeout(() => {
            if (state.ready) dom.sceneLoader.hidden = true;
          }, reducedMotion ? 0 : 450);
          if (state.selectedId) {
            window.setTimeout(() => {
              if (room && state.selectedId) room.select(state.selectedId);
            }, 0);
          }
          if (state.labelsVisible) {
            window.setTimeout(() => {
              measureLabels();
              updateLabels();
            }, 20);
          }
        },
        onTap: (id) => {
          if (id) chooseObject(id);
          else if (state.selectedId) chooseObject(null);
        },
        onHover: (id, x, y) => {
          showHoverChip(id, x, y);
        },
        onSelectionChange: (id) => {
          syncSelection(id);
        },
        onFrame: (moving) => {
          if (state.labelsVisible && (moving || state.labelsMoving)) updateLabels();
          state.labelsMoving = moving;
        },
        onModeChange: (mode) => {
          syncWalkMode(mode);
        },
        // 站定（脚步和转头都停了）时报一句方位：「左手边，在 2 米外」
        onWalkSettled: () => {
          announceWalkDirection();
        },
        onWalkRange: (meters) => {
          state.walkRange = meters;
          syncRangeOutput(meters);
        }
      });
    } catch (error) {
      console.error('3D scene failed to start:', error);
      showSceneError();
    }
  }

  function showSceneError() {
    state.ready = false;
    window.clearTimeout(state.loaderTimer);
    dom.sceneLoader.classList.add('is-hidden');
    dom.sceneLoader.hidden = true;
    dom.sceneError.hidden = false;
    dom.stage.classList.add('has-scene-error');
    dom['scene-canvas'].tabIndex = -1;
    dom.labelToggle.disabled = true;
    dom.resetView.disabled = true;
    state.labelsVisible = false;
    dom.labelToggle.setAttribute('aria-checked', 'false');
    dom['label-layer'].hidden = true;
  }

  function buildLabelLayer() {
    const svg = dom['label-lines'];
    const labelWrap = dom.labels;
    // 重建 DOM 时把引用缓存一起清掉，否则会指向已被替换的节点
    labelNodes.clear();
    OBJECTS.forEach((meta) => {
      const label = document.createElement('span');
      label.className = 'scene-label';
      label.lang = 'en';
      label.dataset.id = meta.id;
      label.textContent = meta.word;
      label.style.opacity = '0';
      labelWrap.appendChild(label);

      const group = document.createElementNS('http://www.w3.org/2000/svg', 'g');
      group.dataset.id = meta.id;
      const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
      line.setAttribute('x1', '0');
      line.setAttribute('y1', '0');
      line.setAttribute('x2', '0');
      line.setAttribute('y2', '0');
      line.setAttribute('visibility', 'hidden');
      const dot = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
      dot.setAttribute('r', '2.4');
      dot.setAttribute('cx', '0');
      dot.setAttribute('cy', '0');
      dot.setAttribute('visibility', 'hidden');
      group.appendChild(line);
      group.appendChild(dot);
      svg.appendChild(group);
    });
  }

  function measureLabels() {
    labelMetrics = new Map();
    dom.labels.querySelectorAll('.scene-label').forEach((label) => {
      labelMetrics.set(label.dataset.id, {
        width: Math.max(54, Math.ceil(label.offsetWidth)),
        height: Math.max(24, Math.ceil(label.offsetHeight))
      });
    });
  }

  function updateLabels() {
    if (!state.labelsVisible || !room || !state.ready) return;
    // 第一人称：标签按「看见多远」分档，和上帝视角的摆放规则完全不同
    if (state.mode === 'walk') {
      updateWalkLabels();
      return;
    }
    const stageRect = dom.stage.getBoundingClientRect();
    const width = stageRect.width;
    const height = stageRect.height;
    if (!width || !height) return;
    if (!labelMetrics.size) measureLabels();

    const svg = dom['label-lines'];
    svg.setAttribute('viewBox', '0 0 ' + width + ' ' + height);
    svg.setAttribute('preserveAspectRatio', 'none');

    const anchors = room.getLabelAnchors();
    const anchorById = new Map(anchors.map((anchor) => [anchor.id, anchor]));
    const safeTop = width < 700 ? 78 : 88;
    const safeBottom = 68;
    const safeLeft = 8;
    const safeRight = 8;
    const placed = [];
    const bigFirst = new Set([
      'sofa', 'rug', 'coffee_table', 'dining_table', 'dining_chair', 'bookshelf',
      'window', 'curtain', 'tv', 'tv_stand', 'floor_lamp', 'plant', 'picture',
      'clock', 'air_conditioner', 'trash_can', 'cushion',
      'fridge', 'cabinet', 'sink', 'dishwasher', 'stove', 'microwave'
    ]);
    // 37 个单词放不下就宁可隐藏远处的标签，也不要拉出一条横穿场景的长引线
    const maxLead = width < 700 ? 132 : 156;

    const sorted = OBJECTS.slice().sort((a, b) => {
      if (state.selectedId) {
        if (a.id === state.selectedId) return -1;
        if (b.id === state.selectedId) return 1;
      }
      const priority = (bigFirst.has(a.id) ? 0 : 1) - (bigFirst.has(b.id) ? 0 : 1);
      if (priority !== 0) return priority;
      const da = anchorById.get(a.id)?.depth ?? 0;
      const db = anchorById.get(b.id)?.depth ?? 0;
      return da - db;
    });

    sorted.forEach((meta) => {
      const label = dom.labels.querySelector('.scene-label[data-id="' + meta.id + '"]');
      const group = svg.querySelector('g[data-id="' + meta.id + '"]');
      const anchor = anchorById.get(meta.id);
      if (!label || !group) return;
      const line = group.querySelector('line');
      const dot = group.querySelector('circle');
      if (!anchor || !anchor.visible) {
        label.style.opacity = '0';
        label.style.visibility = 'hidden';
        line.setAttribute('visibility', 'hidden');
        dot.setAttribute('visibility', 'hidden');
        return;
      }

      const metrics = labelMetrics.get(meta.id) || { width: 70, height: 24 };
      const bias = meta.labelBias || [0, -16];
      const baseLeft = clamp(anchor.x + bias[0] - metrics.width / 2, safeLeft, width - metrics.width - safeRight);
      const baseTop = clamp(anchor.y + bias[1] - metrics.height, safeTop, height - metrics.height - safeBottom);
      const candidates = [
        [0, 0], [0, -30], [0, 30], [-42, 0], [42, 0],
        [-42, -30], [42, -30], [-42, 30], [42, 30],
        [0, -60], [0, 60], [-76, -18], [76, -18],
        [-76, 18], [76, 18], [0, -90], [0, 90],
        [-104, -48], [104, -48], [-104, 48], [104, 48]
      ];

      let chosen = null;
      for (let i = 0; i < candidates.length; i += 1) {
        const left = clamp(baseLeft + candidates[i][0], safeLeft, width - metrics.width - safeRight);
        const top = clamp(baseTop + candidates[i][1], safeTop, height - metrics.height - safeBottom);
        const rect = { left, top, right: left + metrics.width, bottom: top + metrics.height };
        if (!placed.some((other) => overlaps(rect, other))) {
          chosen = rect;
          break;
        }
      }

      if (!chosen) {
        for (let top = safeTop; top <= height - metrics.height - safeBottom && !chosen; top += 28) {
          for (let left = safeLeft; left <= width - metrics.width - safeRight; left += 34) {
            const rect = { left, top, right: left + metrics.width, bottom: top + metrics.height };
            if (!placed.some((other) => overlaps(rect, other))) {
              chosen = rect;
              break;
            }
          }
        }
      }

      if (!chosen) chosen = { left: baseLeft, top: baseTop, right: baseLeft + metrics.width, bottom: baseTop + metrics.height };

      const leadX = clamp(anchor.x, chosen.left + 4, chosen.right - 4);
      const leadY = clamp(anchor.y, chosen.top + 4, chosen.bottom - 4);
      const lead = Math.hypot(leadX - anchor.x, leadY - anchor.y);
      if (lead > maxLead && state.selectedId !== meta.id) {
        label.style.opacity = '0';
        label.style.visibility = 'hidden';
        line.setAttribute('visibility', 'hidden');
        dot.setAttribute('visibility', 'hidden');
        return;
      }
      placed.push(chosen);

      label.style.visibility = 'visible';
      label.style.opacity = '1';
      label.style.transform = 'translate3d(' + chosen.left + 'px,' + chosen.top + 'px,0)';
      label.style.zIndex = state.selectedId === meta.id ? '3' : '1';
      label.classList.toggle('is-selected', state.selectedId === meta.id);

      const endX = clamp(anchor.x, chosen.left + 4, chosen.right - 4);
      const endY = clamp(anchor.y, chosen.top + 4, chosen.bottom - 4);
      const distance = Math.hypot(endX - anchor.x, endY - anchor.y);
      dot.setAttribute('cx', anchor.x);
      dot.setAttribute('cy', anchor.y);
      dot.setAttribute('visibility', 'visible');
      if (distance > 16) {
        line.setAttribute('x1', anchor.x);
        line.setAttribute('y1', anchor.y);
        line.setAttribute('x2', endX);
        line.setAttribute('y2', endY);
        line.setAttribute('visibility', 'visible');
      } else {
        line.setAttribute('visibility', 'hidden');
      }
    });
  }

  // 走进去时标签跟着人走：只显示「看见多远」以内的单词，远的先藏起来。
  // 排序按距离：近的优先占位置，远处的标签宁可藏掉也不拉长引线。
  function updateWalkLabels() {
    const stageRect = dom.stage.getBoundingClientRect();
    const width = stageRect.width;
    const height = stageRect.height;
    if (!width || !height) return;
    if (!labelMetrics.size) measureLabels();

    const svg = dom['label-lines'];
    svg.setAttribute('viewBox', '0 0 ' + width + ' ' + height);
    svg.setAttribute('preserveAspectRatio', 'none');

    const tierOf = window.WordRoomWalk
      ? (distance) => window.WordRoomWalk.labelTier(distance, state.walkRange)
      : () => 'near';
    const anchors = room.getLabelAnchors();
    const anchorById = new Map(anchors.map((anchor) => [anchor.id, anchor]));

    // 安全区要躲开顶部卡片和底部控件：手机竖屏时底部控件更高
    const safeTop = width < 700 ? 96 : 104;
    const safeBottom = width < 700 ? 150 : 120;
    const safeLeft = 10;
    const safeRight = 10;
    const maxLead = width < 700 ? 96 : 124;
    const placed = [];
    let visibleCount = 0;

    const sorted = OBJECTS.slice()
      .filter((meta) => {
        const anchor = anchorById.get(meta.id);
        return anchor && anchor.visible && tierOf(anchor.distance) !== 'hidden';
      })
      .sort((a, b) => {
        if (state.selectedId) {
          if (a.id === state.selectedId) return -1;
          if (b.id === state.selectedId) return 1;
        }
        return (anchorById.get(a.id)?.distance ?? 99) - (anchorById.get(b.id)?.distance ?? 99);
      });
    const keep = new Set(sorted.map((meta) => meta.id));

    // 先收：这一帧没排上队的一律藏起来，排上的再逐个摆
    OBJECTS.forEach((meta) => {
      const nodes = labelNodesFor(meta.id);
      if (!nodes) return;
      nodes.label.classList.remove('is-far');
      if (!keep.has(meta.id)) hideLabelNodes(nodes);
    });

    sorted.forEach((meta) => {
      const nodes = labelNodesFor(meta.id);
      const anchor = anchorById.get(meta.id);
      if (!nodes || !anchor) return;
      const label = nodes.label;
      const line = nodes.line;
      const dot = nodes.dot;
      const metrics = labelMetrics.get(meta.id) || { width: 70, height: 24 };
      const tier = tierOf(anchor.distance);
      const isSelected = state.selectedId === meta.id;
      // 标签只有一行：字落在物品上方，不压住物品本身
      const baseLeft = clamp(anchor.x - metrics.width / 2, safeLeft, width - metrics.width - safeRight);
      const baseTop = clamp(anchor.y - metrics.height - 14, safeTop, height - metrics.height - safeBottom);

      let chosen = null;
      const offsets = [[0, 0], [-24, -22], [24, -22], [0, -46], [-48, 0], [48, 0], [0, 26]];
      for (let i = 0; i < offsets.length && !chosen; i += 1) {
        const left = clamp(baseLeft + offsets[i][0], safeLeft, width - metrics.width - safeRight);
        const top = clamp(baseTop + offsets[i][1], safeTop, height - metrics.height - safeBottom);
        const rect = { left, top, right: left + metrics.width, bottom: top + metrics.height };
        if (!placed.some((other) => overlaps(rect, other))) chosen = rect;
      }
      // 挤不下：远景标签就算了（看不见也是一种发现），近景和选中的必须留
      if (!chosen && tier === 'near') chosen = { left: baseLeft, top: baseTop, right: baseLeft + metrics.width, bottom: baseTop + metrics.height };
      if (!chosen && isSelected) chosen = { left: baseLeft, top: baseTop, right: baseLeft + metrics.width, bottom: baseTop + metrics.height };
      if (!chosen) {
        hideLabelNodes(nodes);
        return;
      }

      const leadX = clamp(anchor.x, chosen.left + 4, chosen.right - 4);
      const leadY = clamp(anchor.y, chosen.top + 4, chosen.bottom - 4);
      const lead = Math.hypot(leadX - anchor.x, leadY - anchor.y);
      // 引线太长说明牌被挤到离物品很远的地方；近景（已经走到跟前）例外——
      // 不然屏幕边上的东西明明就在手边，标签却因为「引线超长」被藏掉
      if (lead > maxLead && !isSelected && tier !== 'near') {
        hideLabelNodes(nodes);
        return;
      }

      placed.push(chosen);
      visibleCount += 1;
      label.style.visibility = 'visible';
      label.style.opacity = tier === 'middle' && !isSelected ? '0.72' : '1';
      label.style.transform = 'translate3d(' + chosen.left + 'px,' + chosen.top + 'px,0)';
      label.style.zIndex = isSelected ? '3' : '1';
      label.classList.toggle('is-selected', isSelected);
      label.classList.toggle('is-far', tier === 'middle' && !isSelected);

      dot.setAttribute('cx', anchor.x);
      dot.setAttribute('cy', anchor.y);
      dot.setAttribute('visibility', 'visible');
      if (lead > 14) {
        line.setAttribute('x1', anchor.x);
        line.setAttribute('y1', anchor.y);
        line.setAttribute('x2', leadX);
        line.setAttribute('y2', leadY);
        line.setAttribute('visibility', 'visible');
      } else {
        line.setAttribute('visibility', 'hidden');
      }
    });

    state.walkVisible = visibleCount;
  }

  // 标签 DOM 引用缓存：走路时每帧都要摆 76 个标签，每次 querySelector 会把手势帧拖慢
  const labelNodes = new Map();

  function labelNodesFor(id) {
    let nodes = labelNodes.get(id);
    if (nodes) return nodes;
    const label = dom.labels.querySelector('.scene-label[data-id="' + id + '"]');
    const group = dom['label-lines'].querySelector('g[data-id="' + id + '"]');
    if (!label || !group) return null;
    nodes = { label, group, line: group.querySelector('line'), dot: group.querySelector('circle') };
    labelNodes.set(id, nodes);
    return nodes;
  }

  function hideLabelNodes(nodes) {
    nodes.label.style.opacity = '0';
    nodes.label.style.visibility = 'hidden';
    nodes.line.setAttribute('visibility', 'hidden');
    nodes.dot.setAttribute('visibility', 'hidden');
  }

  function overlaps(a, b) {
    return a.left < b.right + 4 && a.right + 4 > b.left && a.top < b.bottom + 4 && a.bottom + 4 > b.top;
  }

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value));
  }

  function buildDotGrid() {
    const frag = document.createDocumentFragment();
    OBJECTS.forEach((meta) => {
      const dot = document.createElement('span');
      dot.className = 'progress-dot';
      dot.dataset.id = meta.id;
      dot.title = meta.word;
      frag.appendChild(dot);
    });
    dom.dotGrid.appendChild(frag);
  }

  function buildGlossary() {
    const frag = document.createDocumentFragment();
    CATEGORY_ORDER.forEach((category) => {
      const items = OBJECTS.filter((item) => item.category === category);
      const section = document.createElement('section');
      section.className = 'word-group';
      section.dataset.category = category;
      section.dataset.room = categoryById[category].room;

      const head = document.createElement('div');
      head.className = 'word-group-head';
      const title = document.createElement('h3');
      title.textContent = categoryById[category].zh;
      const count = document.createElement('span');
      count.textContent = String(items.length).padStart(2, '0') + ' 个单词';
      head.appendChild(title);
      head.appendChild(count);

      const list = document.createElement('div');
      list.className = 'word-list';
      items.forEach((meta) => {
        const overall = OBJECTS.findIndex((item) => item.id === meta.id) + 1;
        const row = document.createElement('button');
        row.type = 'button';
        row.className = 'word-row';
        row.dataset.id = meta.id;
        row.dataset.odId = 'glossary-item-' + meta.id.replace(/_/g, '-');
        row.setAttribute('aria-label', meta.word + '，' + meta.zh);
        const index = document.createElement('span');
        index.className = 'row-index';
        index.textContent = String(overall).padStart(2, '0');
        const word = document.createElement('span');
        word.className = 'row-word';
        word.lang = 'en';
        word.textContent = meta.word;
        const zh = document.createElement('span');
        zh.className = 'row-zh';
        zh.textContent = meta.zh;
        row.appendChild(index);
        row.appendChild(word);
        row.appendChild(zh);
        list.appendChild(row);
        rowsById.set(meta.id, row);
      });

      section.appendChild(head);
      section.appendChild(list);
      frag.appendChild(section);
    });
    dom.glossaryBody.appendChild(frag);
  }

  function syncRoomChrome() {
    const meta = ROOM_META[state.activeRoom] || {};
    if (dom.sceneEyebrow) dom.sceneEyebrow.textContent = meta.eyebrow || '3D 场景';
    if (dom.sceneHeading) dom.sceneHeading.textContent = meta.heading || '房间英语探索';
    if (dom.sceneSize) dom.sceneSize.textContent = meta.size || '';
    if (dom.sceneCount) dom.sceneCount.textContent = String(objectsInRoom(state.activeRoom).length);
    if (dom.roomTabs) {
      dom.roomTabs.querySelectorAll('.room-tab').forEach((tab) => {
        const active = tab.dataset.room === state.activeRoom;
        tab.classList.toggle('is-active', active);
        tab.setAttribute('aria-selected', String(active));
        tab.tabIndex = active ? 0 : -1;
        const roomMeta = ROOM_META[tab.dataset.room];
        if (roomMeta && roomMeta.tab) tab.textContent = roomMeta.tab;
      });
    }
    const overview = state.activeRoom === 'overview';
    document.querySelectorAll('.word-group[data-room]').forEach((section) => {
      section.classList.toggle('is-active-room', overview || section.dataset.room === state.activeRoom);
    });
    document.querySelectorAll('.room-stat[data-room]').forEach((cell) => {
      cell.classList.toggle('is-active', !overview && cell.dataset.room === state.activeRoom);
    });
    if (dom.walkToggle) {
      // 全屋视图没有房间之间的地面，走不出去；只在单间房里出现
      dom.walkToggle.hidden = overview || !state.ready;
      dom.walkToggle.setAttribute('aria-pressed', String(state.mode === 'walk'));
      dom.walkToggle.title = state.mode === 'walk' ? '回到上帝视角看整间房' : '走进去，用第一人称看这间房';
      dom.walkToggle.querySelector('.walk-toggle-copy span').textContent = state.mode === 'walk' ? '回到全景' : '走进去';
      dom.walkToggle.querySelector('.walk-toggle-copy small').textContent =
        state.mode === 'walk' ? '上帝视角看整间房' : '站着看这间房';
    }
    if (overview && state.mode === 'walk') setWalkMode('orbit', { silent: true });
    if (dom.labelToggle) {
      dom.labelToggle.disabled = !state.ready || overview;
      dom.labelToggle.title = overview
        ? '全屋视图不支持英文标签，点一间房再打开'
        : '显示物品的英文名称';
      if (overview) {
        state.labelsVisible = false;
        dom.labelToggle.setAttribute('aria-checked', 'false');
        dom['label-layer'].hidden = true;
      }
    }
    if (dom['scene-canvas']) {
      dom['scene-canvas'].setAttribute('aria-label', state.mode === 'walk'
        ? '第一人称视角的 ' + (meta.zh || '房间') + '。拖动环顾，按住向上箭头前进；轻点物品打开单词卡。'
        : '可旋转的 3D ' + (meta.zh || '房间') + '。点击或触摸物品打开单词卡；也可以打开词汇表选择单词。');
    }
    syncAreaChrome();
  }

  // 客餐厅分区镜头（客厅 / 餐厅 / 厨房）：chips 只在客餐厅里显示。
  function syncAreaChrome() {
    if (!dom.areaTabs) return;
    const show = state.activeRoom === 'main';
    dom.areaTabs.hidden = !show;
    dom.areaTabs.querySelectorAll('.area-tab').forEach((chip) => {
      const active = show && chip.dataset.area === state.activeArea;
      chip.classList.toggle('is-active', active);
      chip.setAttribute('aria-pressed', String(active));
    });
  }

  function walkAvailable() {
    return Boolean(room && state.ready && typeof room.setMode === 'function' && state.activeRoom !== 'overview');
  }

  // 切换上帝视角 ⇄ 走进去。原生侧也会调（RoomNativeBridge.setMode / WordRoomApp.setMode）。
  function setWalkMode(mode, options) {
    const next = mode === 'walk' ? 'walk' : 'orbit';
    const opts = options || {};
    if (next === 'walk' && !walkAvailable()) {
      state.pendingWalk = true;
      return 'orbit';
    }
    state.mode = next;
    state.pendingWalk = false;
    // room.setMode 会回调 onModeChange → syncWalkMode：界面只在一个地方跟着状态走
    if (room && state.ready && typeof room.setMode === 'function' && room.mode !== next) room.setMode(next);
    else syncWalkMode(next);
    // 标签层在全屋守卫之外单独处理：走进去时标签是「发现」的主要反馈
    if (next === 'walk') {
      // 走路时视线里只有几件东西，标签全开也不会糊成一片；先记住用户原来开没开，出来时还原
      if (!state.labelsBeforeWalk) state.labelsBeforeWalk = state.labelsVisible;
      state.labelsVisible = true;
      dom.labelToggle.setAttribute('aria-checked', 'true');
      dom['label-layer'].hidden = false;
      measureLabels();
      updateLabels();
      // 新的一程：方位提示的「第二次才念」范围和冷却都重新算
      state.walkHintLast = null;
      state.walkHintAt = 0;
      cancelWalkHint();
      if (!opts.silent) announce('已经走进房间。拖动环顾，按住向上箭头前进。');
    } else {
      cancelWalkHint();
      const restore = state.labelsBeforeWalk;
      state.labelsBeforeWalk = null;
      if (restore === false) setLabelsVisible(false);
      else if (state.labelsVisible) updateLabels();
      if (!opts.silent) announce('已回到上帝视角。');
    }
    // 原生侧通过 syncWalkMode 里的 onMode 回调知道视角，这里不再单独发一次：
    // 集中到一个出口，全屋强制回轨道、换房间重置这些「Web 自己改的视角」原生也能跟上。
    dom['scene-canvas']?.focus?.({ preventScroll: true });
    hideHoverChip();
    return next;
  }

  // 界面跟着模式走：提示文案、控件显隐、画布原子类
  function syncWalkMode(mode) {
    const walking = mode === 'walk';
    syncWalkHint();
    state.mode = walking ? 'walk' : 'orbit';
    dom.stage.classList.toggle('is-walk', walking);
    if (dom.walkControls) dom.walkControls.hidden = !walking;
    if (dom.resetView) dom.resetView.hidden = walking;
    if (dom.walkToggle) {
      dom.walkToggle.setAttribute('aria-pressed', String(walking));
      dom.walkToggle.setAttribute('aria-label', walking ? '回到上帝视角' : '走进去，用第一人称看这间房');
    }
    if (dom.walkEye) {
      dom.walkEye.setAttribute('aria-pressed', String(state.walkEye === 'crouch'));
      dom.walkEye.setAttribute('aria-label', state.walkEye === 'crouch' ? '站起来' : '蹲下来看看');
    }
    if (dom['scene-canvas'] && state.ready) {
      const meta = ROOM_META[state.activeRoom] || {};
      dom['scene-canvas'].setAttribute('aria-label', walking
        ? '第一人称视角的 ' + (meta.zh || '房间') + '。拖动环顾，按住向上箭头前进；轻点物品打开单词卡。'
        : '可旋转的 3D ' + (meta.zh || '房间') + '。点击或触摸物品打开单词卡；也可以打开词汇表选择单词。');
    }
    syncRangeOutput(state.walkRange);
    // 进和出都要刷房间外壳：按钮文案（「走进去 / 回到全景」）在 syncRoomChrome 里，
    // 只在进入时刷，退出后卡片会一直停在「回到全景」。
    syncRoomChrome();
    // 唯一的视角广播出口：Web 自己改的（全屋强制回轨道、换房间重置）也要让原生知道，
    // 否则原生按钮会停在「回到全景」而页面其实已经是上帝视角。
    bridgeCall('onMode', state.mode);
  }

  // 方位语音开关的外形：按下 = 开（实心底），松开 = 关（浅底、同色文字，对比度不降）
  function syncWalkHint() {
    if (!dom.walkHint) return;
    dom.walkHint.setAttribute('aria-pressed', String(state.walkHint));
    dom.walkHint.setAttribute('aria-label', state.walkHint ? '方位提示：打开' : '方位提示：关闭');
  }

  function setWalkHint(enabled, options) {
    const opts = options || {};
    state.walkHint = Boolean(enabled);
    if (!state.walkHint) cancelWalkHint();
    syncWalkHint();
    if (!opts.silent) announce(state.walkHint ? '方位提示打开了：站定时会说东西在你哪边。' : '方位提示关掉了。');
    try {
      window.localStorage.setItem('wordroom.walkHint', state.walkHint ? '1' : '0');
    } catch (error) {
      /* 隐私模式下写不进去就算了，不影响使用 */
    }
    return state.walkHint;
  }

  function syncRangeOutput(meters) {
    const value = Number(meters) || 5;
    if (dom.walkRange) dom.walkRange.value = String(value);
    if (dom.walkRangeOut) dom.walkRangeOut.textContent = value.toFixed(1) + ' m';
  }

  function hasArea(areaId) {
    const areas = window.WordRoomLayout && window.WordRoomLayout.areas;
    return Boolean(areaId && areas && Object.prototype.hasOwnProperty.call(areas, areaId));
  }

  function setActiveArea(areaId) {
    const next = areaId || '';
    if (!hasArea(next)) return false;
    if (state.activeRoom !== 'main') {
      setActiveRoom('main');
      if (state.activeRoom !== 'main') return false;
    }
    state.activeArea = next;
    // 场景还没就绪时只记住选择，onReady 里补应用
    if (room && state.ready) {
      room.focusArea(next);
    }
    syncAreaChrome();
    const areas = (window.WordRoomLayout && window.WordRoomLayout.areas) || {};
    const area = areas[next] || {};
    announce('镜头已对准' + (area.label || next));
    return true;
  }

  function setActiveRoom(roomId) {
    const next = VIEW_ORDER.indexOf(roomId) >= 0 ? roomId : VIEW_ORDER[0];
    if (next === state.activeRoom && state.roomApplied) {
      // 再点同一间房 = 把视角复位（客餐厅同时回到整间取景）
      if (room) room.resetView();
      state.activeArea = null;
      syncAreaChrome();
      return state.activeRoom;
    }
    state.activeRoom = next;
    state.activeArea = null;
    state.roomApplied = true;
    // 换到新房间：上一间房的方位提示和冷却都不再适用
    state.walkHintLast = null;
    state.walkHintAt = 0;
    cancelWalkHint();
    // 走进去时换房间直接落在新房间里：先设模式再换房，避免先复位到轨道机位再跳过去
    if (room && state.ready) room.setRoom(next, state.mode === 'walk' && next !== 'overview' ? 'walk' : undefined);
    // 原生在全屋视图里点过「走进去」：等用户选到具体房间，这次请求才真正生效。
    // 只在换到单间房时补一次，overview 仍然拒绝（四间房之间的地面没建模）。
    if (state.pendingWalk && next !== 'overview') setWalkMode('walk', { silent: true });

    // 全屋视图不支持英文标签——直接关掉状态，不能走 setLabelsVisible（它会被全屋守卫拦下）
    if (next === 'overview') {
      state.labelsVisible = false;
      dom.labelToggle.setAttribute('aria-checked', 'false');
      dom['label-layer'].hidden = true;
    }

    // 换房间时把上一张单词卡收起，避免卡片停在小房间里
    stopSpeech();
    if (state.selectedId) {
      state.selectedId = null;
      closeWordView();
      updateProgress();
      updateSelectedLabel();
    }
    hideHoverChip();
    syncRoomChrome();
    if (state.labelsVisible) {
      measureLabels();
      updateLabels();
    }
    const meta = ROOM_META[next] || {};
    announce('已切换到' + (meta.zh || '房间'));
    return next;
  }

  function setLabelsVisible(visible) {
    if (!state.ready || state.activeRoom === 'overview') return;
    state.labelsVisible = !!visible;
    dom.labelToggle.setAttribute('aria-checked', String(state.labelsVisible));
    if (state.labelsVisible) {
      dom['label-layer'].hidden = false;
      measureLabels();
      updateLabels();
      announce('已显示英文标签');
    } else {
      dom['label-layer'].hidden = true;
      announce('已隐藏英文标签');
    }
  }

  function setLessonMode(enabled) {
    const on = !!enabled;
    dom.stage.classList.toggle('lesson-mode', on);
    // 带逛 / 找一找都是「老师带你飞过去看」，机位得由课程控制：先退出第一人称
    if (on && state.mode === 'walk') setWalkMode('orbit', { silent: true });
    if (on && state.labelsVisible) {
      setLabelsVisible(false);
    }
  }

  function bindUI() {
    dom.labelToggle.addEventListener('click', () => {
      if (!state.ready) return;
      setLabelsVisible(!state.labelsVisible);
    });

    if (dom.walkToggle) {
      dom.walkToggle.addEventListener('click', () => {
        if (!state.ready) return;
        setWalkMode(state.mode === 'walk' ? 'orbit' : 'walk');
      });
    }

    if (dom.walkRange) {
      const applyRange = () => {
        const value = Number(dom.walkRange.value) || state.walkRange;
        state.walkRange = value;
        syncRangeOutput(value);
        if (room && typeof room.setWalkRange === 'function') room.setWalkRange(value);
        if (state.labelsVisible && state.mode === 'walk') updateLabels();
      };
      dom.walkRange.addEventListener('input', applyRange);
      dom.walkRange.addEventListener('change', applyRange);
    }

    if (dom.walkHint) {
      dom.walkHint.addEventListener('click', () => setWalkHint(!state.walkHint));
    }

    if (dom.walkEye) {
      dom.walkEye.addEventListener('click', () => {
        if (room && typeof room.setWalkEye === 'function') room.setWalkEye(state.walkEye === 'crouch' ? 'stand' : 'crouch');
        state.walkEye = state.walkEye === 'crouch' ? 'stand' : 'crouch';
        dom.walkEye.setAttribute('aria-pressed', String(state.walkEye === 'crouch'));
        dom.walkEye.setAttribute('aria-label', state.walkEye === 'crouch' ? '站起来' : '蹲下来看看');
        announce(state.walkEye === 'crouch' ? '蹲下来了，视线降到沙发高度。' : '站起来，恢复站立高度。');
      });
    }

    if (dom.walkBack && dom.walkToggle) {
      dom.walkBack.addEventListener('click', () => {
        // 回到起点 = 重新落一次出生点（模式不变）；再点一次「走进去」也会重新落点
        if (!walkAvailable() || typeof room.setWalkSpawn !== 'function') return;
        room.setWalkSpawn(state.activeRoom);
        announce('回到房间起点。');
      });
    }

    if (dom['scene-canvas']) {
      // 键盘走路的「松开」要兜住：按键在画布外松开、切到别的窗口，都要停下脚步。
      // 连 keys 一起清：切走后 keyup 收不到，回来时会一直往前走。
      const releaseKeys = () => {
        dom.walkForward?.classList.remove('is-down');
        if (room) {
          if (typeof room.releaseWalkInput === 'function') room.releaseWalkInput();
          else if (room.walker) room.walker.press(false);
        }
      };
      window.addEventListener('blur', releaseKeys);
      document.addEventListener('visibilitychange', () => {
        if (document.hidden) releaseKeys();
      });
    }

    // 注意别在这里判断 room：bindUI() 跑在 startScene() 之前，那时 room 还是 null，
    // 条件写 `&& room` 会让「按住前进」永远绑不上事件（点着没反应）。room 在回调里再判。
    if (dom.walkForward) {
      const start = (event) => {
        event.preventDefault();
        dom.walkForward.classList.add('is-down');
        dom.walkForward.setPointerCapture?.(event.pointerId);
        if (room && room.walker) room.walker.press(true);
      };
      const stop = (event) => {
        dom.walkForward.classList.remove('is-down');
        if (room && room.walker) room.walker.press(false);
        if (event && event.type === 'pointerup') dom.walkForward.releasePointerCapture?.(event.pointerId);
      };
      dom.walkForward.addEventListener('pointerdown', start);
      dom.walkForward.addEventListener('pointerup', stop);
      dom.walkForward.addEventListener('pointercancel', stop);
      dom.walkForward.addEventListener('pointerleave', stop);
      dom.walkForward.addEventListener('keydown', (event) => {
        if (event.key !== ' ' && event.key !== 'Enter') return;
        event.preventDefault();
        start(event);
      });
      dom.walkForward.addEventListener('keyup', (event) => {
        if (event.key !== ' ' && event.key !== 'Enter') return;
        event.preventDefault();
        stop(event);
      });
    }

    dom.resetView.addEventListener('click', () => {
      room?.resetView();
      state.activeArea = null;
      syncAreaChrome();
    });

    if (dom.areaTabs) {
      dom.areaTabs.addEventListener('click', (event) => {
        const chip = event.target.closest('.area-tab');
        if (!chip || !chip.dataset.area) return;
        setActiveArea(chip.dataset.area);
      });
    }

    if (dom.roomTabs) {
      dom.roomTabs.addEventListener('click', (event) => {
        const tab = event.target.closest('.room-tab');
        if (!tab || !tab.dataset.room) return;
        setActiveRoom(tab.dataset.room);
      });
      // role=tablist 的键盘惯例：左右方向键换房间
      dom.roomTabs.addEventListener('keydown', (event) => {
        if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
        const tabs = Array.from(dom.roomTabs.querySelectorAll('.room-tab'));
        const current = tabs.findIndex((tab) => tab.dataset.room === state.activeRoom);
        if (current < 0) return;
        event.preventDefault();
        const step = event.key === 'ArrowRight' ? 1 : -1;
        const target = tabs[(current + step + tabs.length) % tabs.length];
        setActiveRoom(target.dataset.room);
        target.focus({ preventScroll: true });
      });
    }

    dom.retryScene.addEventListener('click', () => {
      startScene();
    });

    dom.closeWord.addEventListener('click', () => {
      chooseObject(null);
      dom.openGlossaryInline.focus({ preventScroll: true });
    });
    dom.pronounceButton.addEventListener('click', () => speakCurrentWord());
    dom.prevWord.addEventListener('click', () => moveWord(-1));
    dom.nextWord.addEventListener('click', () => moveWord(1));

    dom.openGlossary.addEventListener('click', openGlossary);
    dom.openGlossaryInline.addEventListener('click', openGlossary);
    dom.closeGlossary.addEventListener('click', () => closeGlossary());
    dom.glossaryModal.addEventListener('click', (event) => {
      if (event.target === dom.glossaryModal) closeGlossary();
    });
    dom.glossaryBody.addEventListener('click', (event) => {
      const row = event.target.closest('.word-row');
      if (!row) return;
      const id = row.dataset.id;
      closeGlossary(false, dom.closeWord);
      chooseObject(id);
    });

    document.addEventListener('keydown', handleGlobalKeydown);
    window.addEventListener('resize', () => {
      if (state.labelsVisible) updateLabels();
    });
  }

  function handleGlobalKeydown(event) {
    if (state.modalOpen) {
      if (event.key === 'Escape') {
        event.preventDefault();
        closeGlossary();
        return;
      }
      if (event.key === 'Tab') {
        trapFocus(event, dom.glossaryModal);
      }
      return;
    }

    if (event.key === 'Escape' && state.selectedId) {
      event.preventDefault();
      chooseObject(null);
      dom['scene-canvas'].focus({ preventScroll: true });
      return;
    }

    if (state.selectedId && (event.key === 'ArrowLeft' || event.key === 'ArrowRight')) {
      const target = event.target;
      if (target && target.closest && target.closest('button, a, input, textarea, select, [contenteditable="true"], #scene-canvas')) return;
      event.preventDefault();
      moveWord(event.key === 'ArrowLeft' ? -1 : 1);
    }
  }

  function trapFocus(event, container) {
    const focusable = Array.from(
      container.querySelectorAll('button:not([disabled]), [href], input, select, textarea, [tabindex]:not([tabindex="-1"])')
    ).filter((node) => node.offsetParent !== null);
    if (!focusable.length) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  function chooseObject(id) {
    if (id && !byId.has(id)) return;
    if (id && state.activeRoom !== 'overview') {
      const meta = byId.get(id);
      if (meta && meta.room && meta.room !== state.activeRoom) setActiveRoom(meta.room);
    }
    if (!id) {
      if (!state.selectedId) {
        hideHoverChip();
        return;
      }
      if (room) room.select(null);
      else syncSelection(null);
      return;
    }

    if (room) {
      const current = room.selected?.userData?.objectId || null;
      if (current === id) {
        if (state.selectedId !== id) {
          syncSelection(id);
        } else {
          // 重复点同一件物品：只补一次选中回调（引导课「再试一次」需要），
          // 不重渲染、不重发音，自由探索的可见行为不变。
          const meta = byId.get(id);
          bridgeCall('onSelect', id, meta ? meta.word : '');
          // 走进去时再点一次：单词卡还开着，3 秒后补一句「它在你哪边」，
          // 不和刚念过的中文 + 英文抢同一句话
          if (state.mode === 'walk' && state.walkHint && state.autoSpeak) scheduleWalkHint(id);
        }
      } else {
        room.select(id);
      }
    } else {
      syncSelection(id);
    }
  }

  // 引导课「找一找」准备：切到目标物品所在房间/分区并收起单词卡，但不选中、不发音。
  function prepareFind(id) {
    const meta = byId.get(id);
    if (!meta) return false;
    setActiveRoom(meta.room);
    if (meta.room === 'main' && hasArea(meta.category)) {
      setActiveArea(meta.category);
    }
    chooseObject(null);
    return true;
  }

  function syncSelection(id) {
    state.selectedId = id;
    if (id) {
      stopSpeech();
      const meta = byId.get(id);
      if (!meta) return;
      state.discovered.add(id);
      renderWordCard(meta);
      openWordView();
      updateProgress();
      updateSelectedLabel();
      hideHoverChip();
      announce(meta.word + '，' + meta.zh + '。' + meta.kidDefinition);
      // 点开就念：先中文意思，再英文单词（小朋友先听懂，再记发音）
      if (state.autoSpeak) speakCurrentWord();
    } else {
      stopSpeech();
      closeWordView();
      updateProgress();
      updateSelectedLabel();
    }
    bridgeCall('onSelect', id || '', id && byId.get(id) ? byId.get(id).word : '');
    bridgeCall('onProgress', JSON.stringify(Array.from(state.discovered)));
  }

  function renderWordCard(meta) {
    const inRoom = objectsInRoom(state.activeRoom);
    const index = inRoom.findIndex((item) => item.id === meta.id) + 1;
    const total = inRoom.length;
    const category = categoryById[meta.category];

    dom.wordCategory.textContent = category.zh;
    dom.wordCategory.dataset.category = meta.category;
    dom.wordIndex.textContent = pad(index) + ' / ' + total;
    dom.wordNavIndex.textContent = pad(index) + ' / ' + total;
    dom.wordEnglish.textContent = meta.word;
    dom.wordEnglish.className = 'word-en';
    if (meta.word.length > 12) dom.wordEnglish.classList.add('is-very-long');
    else if (meta.word.length > 8) dom.wordEnglish.classList.add('is-long');
    dom.wordPhonetic.textContent = meta.phonetic;
    dom.wordZh.textContent = meta.zh;
    dom.wordDefinition.textContent = meta.kidDefinition;
    dom.wordExample.textContent = meta.example;
    dom.pronounceButton.dataset.id = meta.id;
    dom.pronounceButton.setAttribute('aria-label', '播放 ' + meta.word + ' 的英文发音');
    resetPronounceButton();
    dom.panelBody.scrollTop = 0;
  }

  function openWordView() {
    dom.welcomeView.hidden = true;
    dom.wordView.hidden = false;
    dom.closeWord.hidden = false;
    dom.panelTitle.textContent = '单词卡';
    dom.panel.setAttribute('aria-labelledby', 'panelTitle');
  }

  function closeWordView() {
    dom.wordView.hidden = true;
    dom.welcomeView.hidden = false;
    dom.closeWord.hidden = true;
    dom.panelTitle.textContent = '发现单词';
    dom.panelBody.scrollTop = 0;
    resetPronounceButton();
  }

  function moveWord(direction) {
    if (!state.selectedId) return;
    const meta = byId.get(state.selectedId);
    if (!meta) return;
    const list = objectsInRoom(state.activeRoom);
    const current = list.findIndex((item) => item.id === state.selectedId);
    if (current < 0) return;
    const next = (current + direction + list.length) % list.length;
    chooseObject(list[next].id);
  }

  function updateProgress() {
    const count = state.discovered.size;
    dom.progressChip.setAttribute('aria-label', '已收集 ' + count + ' / ' + TOTAL + ' 个单词');
    dom.progressCount.textContent = String(count);
    dom.welcomeCount.textContent = String(count);
    dom.dotGrid.querySelectorAll('.progress-dot').forEach((dot) => {
      dot.classList.toggle('is-found', state.discovered.has(dot.dataset.id));
      dot.classList.toggle('is-current', dot.dataset.id === state.selectedId);
    });
    rowsById.forEach((row, id) => {
      row.classList.toggle('is-found', state.discovered.has(id));
    });

    const copy = dom.welcomeView.querySelector('.progress-copy p');
    if (copy) {
      const note = ROOM_META[state.activeRoom] && ROOM_META[state.activeRoom].note;
      copy.textContent = count === TOTAL
        ? TOTAL + ' 个单词全部点亮了，和这个家说一声你真棒！'
        : '每点开一个物品，就会点亮一格。' + (note || '');
    }
    if (count === TOTAL && !state.celebrated) {
      state.celebrated = true;
      showToast(TOTAL + ' 个单词全部收集完成，你真棒！');
    }
  }

  function updateSelectedLabel() {
    dom.labels.querySelectorAll('.scene-label').forEach((label) => {
      label.classList.toggle('is-selected', label.dataset.id === state.selectedId);
    });
    // 取消选中时也要刷新：挂墙物品选中的墙会被强制显示，取消后墙重新隐藏，
    // 不刷新就会留下悬空的标签和引线（相机静止时 onFrame 不会补刷）。
    if (state.labelsVisible) updateLabels();
  }

  function showHoverChip(id, x, y) {
    if (!id || !byId.has(id) || x == null || y == null) {
      hideHoverChip();
      return;
    }
    const meta = byId.get(id);
    const rect = dom.stage.getBoundingClientRect();
    const px = clamp(x - rect.left, 72, rect.width - 72);
    const py = clamp(y - rect.top - 12, 92, rect.height - 18);
    dom.hoverChip.textContent = meta.word;
    dom.hoverChip.style.left = px + 'px';
    dom.hoverChip.style.top = py + 'px';
    dom.hoverChip.classList.add('is-visible');
  }

  function hideHoverChip() {
    dom.hoverChip.classList.remove('is-visible');
  }

  function speakCurrentWord() {
    if (!state.selectedId) return;
    const meta = byId.get(state.selectedId);
    if (!meta) return;
    // 先中文意思，再英文单词：小朋友先听懂是什么，再记发音
    const zh = meta.zh && meta.zh !== meta.word ? meta.zh : '';
    if (getBridge() && bridgeCall('speak', meta.word, zh) === 'true') {
      dom.pronounceButton.classList.add('is-playing');
      dom.pronounceLabel.textContent = '正在播放…';
      window.clearTimeout(state.speechTimer);
      state.speechTimer = window.setTimeout(() => resetPronounceButton(), zh ? 4600 : 3200);
      return;
    }
    if (!('speechSynthesis' in window) || !('SpeechSynthesisUtterance' in window)) {
      showToast('当前设备不支持语音朗读，可以跟着音标读一读。');
      return;
    }
    stopSpeech();
    const seq = state.speechSeq;
    try {
      const voices = window.speechSynthesis.getVoices();
      const preferredEn =
        voices.find((voice) => /en[-_]US/i.test(voice.lang) && /samantha|aria|jenny|zira|google us/i.test(voice.name)) ||
        voices.find((voice) => /en[-_]US/i.test(voice.lang)) ||
        voices.find((voice) => /^en/i.test(voice.lang));
      const preferredZh =
        voices.find((voice) => /zh[-_]CN/i.test(voice.lang) && /ting|xiaoxiao|huihui|google/i.test(voice.name)) ||
        voices.find((voice) => /zh[-_]CN/i.test(voice.lang)) ||
        voices.find((voice) => /^zh/i.test(voice.lang));

      const wordUtterance = new SpeechSynthesisUtterance(meta.word);
      wordUtterance.lang = 'en-US';
      wordUtterance.rate = 0.82;
      wordUtterance.pitch = 1.04;
      wordUtterance.volume = 1;
      if (preferredEn) wordUtterance.voice = preferredEn;
      wordUtterance.onend = () => {
        if (seq === state.speechSeq) resetPronounceButton();
      };
      wordUtterance.onerror = (event) => {
        if (seq !== state.speechSeq) return;
        resetPronounceButton();
        if (event.error !== 'interrupted' && event.error !== 'canceled') {
          showToast('发音没有播放成功，可以再点一次试试。');
        }
      };

      dom.pronounceButton.classList.add('is-playing');
      dom.pronounceLabel.textContent = '正在播放…';

      if (zh) {
        const meaning = new SpeechSynthesisUtterance(zh);
        meaning.lang = 'zh-CN';
        meaning.rate = 0.9;
        meaning.volume = 1;
        if (preferredZh) meaning.voice = preferredZh;
        meaning.onend = () => {
          if (seq !== state.speechSeq) return;
          window.speechSynthesis.speak(wordUtterance);
        };
        meaning.onerror = () => {
          if (seq !== state.speechSeq) return;
          window.speechSynthesis.speak(wordUtterance);
        };
        window.speechSynthesis.speak(meaning);
      } else {
        window.speechSynthesis.speak(wordUtterance);
      }

      state.speechTimer = window.setTimeout(() => {
        if (seq === state.speechSeq) resetPronounceButton();
      }, zh ? 8000 : 6000);
    } catch (error) {
      resetPronounceButton();
      showToast('发音没有播放成功，可以再点一次试试。');
    }
  }

  // ---------- 方位语音：「在你左手边」 ----------

  // 走进去以后离眼睛最近的物品：方位提示的目标。
  // 用世界坐标算方位，不用屏幕坐标——透视会把身后的东西翻到画面另一侧，屏幕方位会骗人。
  function walkNearest() {
    if (!state.ready || !room || typeof room.getLabelAnchors !== 'function') return null;
    let best = null;
    // 进房间/转身后的第一帧矩阵可能还没刷，先同步一次，方位才不会指向旧位置
    if (room.root && typeof room.root.updateMatrixWorld === 'function') room.root.updateMatrixWorld();
    room.getLabelAnchors().forEach((anchor) => {
      if (!anchor || !anchor.world || typeof anchor.distance !== 'number') return;
      if (anchor.distance > walkRange()) return;
      const meta = byId.get(anchor.id);
      if (!meta || meta.room !== state.activeRoom) return;
      if (!best || anchor.distance < best.distance) {
        best = { id: meta.id, word: meta.word, distance: anchor.distance, world: anchor.world, lift: anchor.lift };
      }
    });
    return best;
  }

  // 方位那句话（不含单词本身）：「左手边，在 2 米外」。几何算在 walk-camera.js 里，这里只要一句话。
  function walkWhere(world, lift) {
    const walker = room && room.walker;
    if (!walker || !world || typeof walker.describe !== 'function') return '';
    // 注意第二个参数是「相对眼睛高多少」，不是世界坐标 y：walk-camera 自己再减一次视线高度，
    // 传世界高度会把差值抵消掉，空调和地毯都不出声。
    const height = typeof lift === 'number' ? lift : undefined;
    return walker.describe(world, height);
  }

  // 「看见多远」的真实值在 walker 上（滚轮 / 双指直接改它），state.walkRange 只是界面副本
  function walkRange() {
    const walker = room && room.walker;
    const live = walker && typeof walker.targetRange === 'number' ? walker.targetRange : 0;
    return live || state.walkRange || 5;
  }

  function cancelWalkHint() {
    window.clearTimeout(state.walkHintTimer);
    state.walkHintTimer = 0;
  }

  // 念一句中文：优先走原生朗读（和单词同一个声音），浏览器里退回 speechSynthesis
  function speakWhere(text) {
    if (!text || !state.walkHint) return false;
    if (getBridge() && bridgeCall('speak', text, '') === 'true') return true;
    if (!('speechSynthesis' in window) || !('SpeechSynthesisUtterance' in window)) return false;
    try {
      const utterance = new window.SpeechSynthesisUtterance(text);
      utterance.lang = 'zh-CN';
      utterance.rate = 0.92;
      window.speechSynthesis.speak(utterance);
      return true;
    } catch (error) {
      return false;
    }
  }

  // 停稳以后报一句：视野里最近的东西在哪个方向。同一件东西 9 秒内不重复念。
  function announceWalkDirection() {
    if (state.mode !== 'walk' || !state.ready) return;
    const target = walkNearest();
    if (!target) return;
    const now = Date.now();
    if (state.walkHintLast === target.id && now - state.walkHintAt < WALK_HINT_COOLDOWN) return;
    const where = walkWhere(target.world, target.lift);
    if (!where) return;
    state.walkHintLast = target.id;
    state.walkHintAt = now;
    markSpeaking('正在播报方位…');
    speakWhere(target.word + '，' + where);
  }

  // 方位提示也是一次朗读：按钮跟着亮一下，念完恢复，避免和单词播放的状态打架
  function markSpeaking(label) {
    if (!dom.pronounceButton) return;
    dom.pronounceButton.classList.add('is-playing');
    if (dom.pronounceLabel) dom.pronounceLabel.textContent = label;
    window.clearTimeout(state.speechTimer);
    state.speechTimer = window.setTimeout(() => resetPronounceButton(), 2600);
  }

  // 第二次点同一件物品：等单词念完再补方位，别和「中文 + 英文」抢一句话
  function scheduleWalkHint(id) {
    const meta = byId.get(id);
    if (!meta || !room || typeof room.getLabelAnchors !== 'function') return;
    // 用户点的就是这一件，直接查它的锚点：不能拿「离得最近的那件」凑数，
    // 否则点柜子会报成旁边椅子的方位
    const anchor = (room.getLabelAnchors() || []).find((item) => item && item.id === id);
    const where = walkWhere(anchor && anchor.world, anchor && anchor.lift);
    if (!where) return;
    cancelWalkHint();
    state.walkHintTimer = window.setTimeout(() => {
      if (state.mode !== 'walk') return;
      markSpeaking('正在播报方位…');
      speakWhere(meta.word + '，' + where);
    }, 3200);
  }

  function stopSpeech() {
    state.speechSeq += 1;
    bridgeCall('stopSpeak');
    if ('speechSynthesis' in window) {
      try {
        window.speechSynthesis.cancel();
      } catch (error) {
        /* no-op */
      }
    }
    resetPronounceButton();
  }

  function resetPronounceButton() {
    window.clearTimeout(state.speechTimer);
    if (!dom.pronounceButton) return;
    dom.pronounceButton.classList.remove('is-playing');
    dom.pronounceLabel.textContent = '听发音';
  }

  function openGlossary() {
    if (state.modalOpen) return;
    stopSpeech();
    state.lastFocus = document.activeElement;
    state.modalOpen = true;
    // 弹层挡住 3D 舞台：停掉键盘走路，别让 W 键在背后带着相机跑
    if (room && typeof room.setInputBlocked === 'function') room.setInputBlocked(true);
    window.clearTimeout(state.modalTimer);
    dom.glossaryModal.hidden = false;
    dom.openGlossary.setAttribute('aria-expanded', 'true');
    dom.openGlossaryInline.setAttribute('aria-expanded', 'true');
    document.body.style.overflow = 'hidden';
    rowsById.forEach((row, id) => row.classList.toggle('is-current', id === state.selectedId));
    window.requestAnimationFrame(() => {
      if (!state.modalOpen) return;
      dom.glossaryModal.classList.add('is-open');
      dom.closeGlossary.focus();
    });
  }

  function closeGlossary(restoreFocus, focusTarget) {
    if (!state.modalOpen) return;
    state.modalOpen = false;
    if (room && typeof room.setInputBlocked === 'function') room.setInputBlocked(false);
    dom.glossaryModal.classList.remove('is-open');
    dom.openGlossary.setAttribute('aria-expanded', 'false');
    dom.openGlossaryInline.setAttribute('aria-expanded', 'false');
    document.body.style.overflow = '';
    const shouldRestore = restoreFocus !== false;
    state.modalTimer = window.setTimeout(() => {
      if (state.modalOpen) return;
      dom.glossaryModal.hidden = true;
      const target = focusTarget || (shouldRestore ? state.lastFocus : null);
      if (target && target.isConnected && !target.closest('[hidden]') && typeof target.focus === 'function') {
        target.focus({ preventScroll: true });
      }
    }, reducedMotion ? 0 : 190);
  }

  function showToast(message) {
    window.clearTimeout(state.toastTimer);
    dom.toast.textContent = message;
    dom.toast.classList.add('is-visible');
    state.toastTimer = window.setTimeout(() => {
      dom.toast.classList.remove('is-visible');
    }, 3000);
  }

  let announceTimer = 0;
  function announce(message) {
    window.clearTimeout(announceTimer);
    dom.liveRegion.textContent = '';
    announceTimer = window.setTimeout(() => {
      dom.liveRegion.textContent = message;
    }, 30);
  }

  function pad(value) {
    return String(value).padStart(2, '0');
  }

  // 供宿主 (ArkWeb runJavaScript) 调用：高亮某个物品 / 显示英文标签 / 切房间 / 对准客餐厅分区。
  window.WordRoomApp = {
    select: function (id) { chooseObject(id || null); },
    setLabels: function (visible) { setLabelsVisible(!!visible); },
    setRoom: function (roomId) { setActiveRoom(roomId); },
    setArea: function (areaId) { return setActiveArea(areaId || ''); },
    setAutoSpeak: function (enabled) { state.autoSpeak = !!enabled; },
    setWalkHint: function (enabled) { return setWalkHint(enabled, { silent: true }); },
    getWalkHint: function () { return state.walkHint; },
    setLessonMode: function (enabled) { setLessonMode(!!enabled); },
    prepareFind: function (id) { return prepareFind(id); },
    // 视角：'walk' 走进去，'orbit' 回上帝视角。全屋视图没有房间之间的地面，会自动回 orbit。
    setMode: function (mode) { return setWalkMode(mode === 'walk' ? 'walk' : 'orbit'); },
    getMode: function () { return state.mode; },
    setWalkRange: function (meters) {
      state.walkRange = Math.min(8, Math.max(1.5, Number(meters) || 5));
      syncRangeOutput(state.walkRange);
      if (room && typeof room.setWalkRange === 'function') room.setWalkRange(state.walkRange);
      if (state.mode === 'walk' && state.labelsVisible) updateLabels();
      return state.walkRange;
    },
    setWalkEye: function (mode) {
      state.walkEye = mode === 'crouch' ? 'crouch' : 'stand';
      if (room && typeof room.setWalkEye === 'function') room.setWalkEye(state.walkEye);
      if (dom.walkEye) dom.walkEye.setAttribute('aria-pressed', String(state.walkEye === 'crouch'));
      return state.walkEye;
    },
    ids: OBJECTS.map(function (item) { return item.id; })
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
