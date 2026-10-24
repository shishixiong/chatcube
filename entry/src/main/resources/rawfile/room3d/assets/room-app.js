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
    modalOpen: false,
    ready: false,
    celebrated: false,
    lastFocus: null,
    modalTimer: 0,
    loaderTimer: 0,
    toastTimer: 0,
    speechTimer: 0,
    speechSeq: 0
  };

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
    cacheDom();
    validateData();
    updateStaticCounts();
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
      'glossaryModal', 'glossaryBody', 'closeGlossary', 'toast', 'liveRegion'
    ].forEach((id) => {
      dom[id] = el(id);
    });
  }

  function validateData() {
    if (OBJECTS.length !== 25) throw new Error('场景需要 25 个单词，当前为 ' + OBJECTS.length);
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
    });
    const living = OBJECTS.filter((item) => item.category === 'living').length;
    const dining = OBJECTS.filter((item) => item.category === 'dining').length;
    if (living !== 15 || dining !== 10) {
      throw new Error('分类数量应为 15 + 10，当前为 ' + living + ' + ' + dining);
    }
  }

  function updateStaticCounts() {
    const stats = document.querySelectorAll('.room-stat strong');
    const living = OBJECTS.filter((item) => item.category === 'living').length;
    const dining = OBJECTS.filter((item) => item.category === 'dining').length;
    if (stats[0]) stats[0].textContent = String(living);
    if (stats[1]) stats[1].textContent = String(dining);
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
          bridgeCall('onReady');
          dom['scene-canvas'].tabIndex = 0;
          dom.labelToggle.disabled = false;
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
        onFrame: () => {
          if (state.labelsVisible) updateLabels();
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
      'clock', 'air_conditioner', 'trash_can', 'cushion'
    ]);

    const sorted = OBJECTS.slice().sort((a, b) => {
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
    ['living', 'dining'].forEach((category) => {
      const items = OBJECTS.filter((item) => item.category === category);
      const section = document.createElement('section');
      section.className = 'word-group';
      section.dataset.category = category;

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

  function setLabelsVisible(visible) {
    if (!state.ready) return;
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

  function bindUI() {
    dom.labelToggle.addEventListener('click', () => {
      if (!state.ready) return;
      setLabelsVisible(!state.labelsVisible);
    });

    dom.resetView.addEventListener('click', () => {
      room?.resetView();
    });

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
        if (state.selectedId !== id) syncSelection(id);
      } else {
        room.select(id);
      }
    } else {
      syncSelection(id);
    }
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
    const index = OBJECTS.findIndex((item) => item.id === meta.id) + 1;
    const total = OBJECTS.length;
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
    const current = OBJECTS.findIndex((item) => item.id === state.selectedId);
    if (current < 0) return;
    const next = (current + direction + OBJECTS.length) % OBJECTS.length;
    chooseObject(OBJECTS[next].id);
  }

  function updateProgress() {
    const count = state.discovered.size;
    dom.progressChip.setAttribute('aria-label', '已收集 ' + count + ' / 25 个单词');
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
      copy.textContent = count === 25
        ? '25 个单词全部点亮了，和这个房间说一声你真棒！'
        : '每点开一个物品，就会点亮一格。试试从沙发开始？';
    }
    if (count === 25 && !state.celebrated) {
      state.celebrated = true;
      showToast('25 个单词全部收集完成，你真棒！');
    }
  }

  function updateSelectedLabel() {
    dom.labels.querySelectorAll('.scene-label').forEach((label) => {
      label.classList.toggle('is-selected', label.dataset.id === state.selectedId);
    });
    if (state.selectedId) updateLabels();
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
    if (getBridge() && bridgeCall('speak', meta.word) === 'true') {
      dom.pronounceButton.classList.add('is-playing');
      dom.pronounceLabel.textContent = '正在播放…';
      window.clearTimeout(state.speechTimer);
      state.speechTimer = window.setTimeout(() => resetPronounceButton(), 3200);
      return;
    }
    if (!('speechSynthesis' in window) || !('SpeechSynthesisUtterance' in window)) {
      showToast('当前设备不支持语音朗读，可以跟着音标读一读。');
      return;
    }
    stopSpeech();
    const seq = state.speechSeq;
    try {
      const utterance = new SpeechSynthesisUtterance(meta.word);
      utterance.lang = 'en-US';
      utterance.rate = 0.82;
      utterance.pitch = 1.04;
      utterance.volume = 1;
      const voices = window.speechSynthesis.getVoices();
      const preferred =
        voices.find((voice) => /en[-_]US/i.test(voice.lang) && /samantha|aria|jenny|zira|google us/i.test(voice.name)) ||
        voices.find((voice) => /en[-_]US/i.test(voice.lang)) ||
        voices.find((voice) => /^en/i.test(voice.lang));
      if (preferred) utterance.voice = preferred;

      dom.pronounceButton.classList.add('is-playing');
      dom.pronounceLabel.textContent = '正在播放…';
      utterance.onend = () => {
        if (seq === state.speechSeq) resetPronounceButton();
      };
      utterance.onerror = (event) => {
        if (seq !== state.speechSeq) return;
        resetPronounceButton();
        if (event.error !== 'interrupted' && event.error !== 'canceled') {
          showToast('发音没有播放成功，可以再点一次试试。');
        }
      };
      window.speechSynthesis.speak(utterance);
      state.speechTimer = window.setTimeout(() => {
        if (seq === state.speechSeq) resetPronounceButton();
      }, 6000);
    } catch (error) {
      resetPronounceButton();
      showToast('发音没有播放成功，可以再点一次试试。');
    }
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

  // 供宿主 (ArkWeb runJavaScript) 调用：高亮某个物品 / 显示英文标签。
  window.WordRoomApp = {
    select: function (id) { chooseObject(id || null); },
    setLabels: function (visible) { setLabelsVisible(!!visible); },
    ids: OBJECTS.map(function (item) { return item.id; })
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
