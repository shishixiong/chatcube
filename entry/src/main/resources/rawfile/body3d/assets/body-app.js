/* 小星英语 · 3D 身体课：界面、单词卡、部位图、发音与原生桥。
 * 原生宿主（Body3DCard）通过 window.BodyNativeBridge 注入 TTS；
 * 页面也暴露 window.BodyClassApp 给原生做 focus 注入。 */
(function () {
  'use strict';

  const DATA = window.BodyClassData;
  if (!DATA) return;

  const PARTS = DATA.parts;
  const BY_ID = DATA.byId;
  const GROUPS = DATA.groups;
  const MAP_LABELS = DATA.mapLabels;
  const STORAGE_KEY = 'xiaoxing-body-class:v2';

  const state = {
    selected: 'head',
    cardOpen: true,
    tab: 'words',
    learned: new Set(),
    playing: false,
    focus: 'all',
    focusWords: [],
    stage: null,
    ready: false,
    pendingFocus: null,
    speakTimer: 0
  };

  const $ = function (id) { return document.getElementById(id); };

  function getBridge() {
    return typeof window !== 'undefined' && window.BodyNativeBridge ? window.BodyNativeBridge : null;
  }

  function bridgeCall(name) {
    const target = getBridge();
    if (!target) return null;
    try {
      const fn = target[name];
      const rest = Array.prototype.slice.call(arguments, 1);
      return typeof fn === 'function' ? fn.apply(target, rest) : null;
    } catch (error) {
      return null;
    }
  }

  function loadSaved() {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY);
      if (!raw) return null;
      const data = JSON.parse(raw);
      return data && Array.isArray(data.learned) ? data : null;
    } catch (error) {
      return null;
    }
  }

  function saveSaved() {
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify({
        learned: Array.from(state.learned),
        selected: state.selected
      }));
    } catch (error) {
      /* 隐私模式 / 存储满：进度只保留在内存里 */
    }
  }

  function pluralSuffix(part) {
    if (part.kind === 'pair') return '（两只）';
    if (part.kind === 'multi') return '（多个）';
    return '';
  }

  function adviceOf(part) {
    if (part.kind === 'pair') return '复数：一个说 ' + part.once + '，两个说 ' + part.en;
    if (part.kind === 'multi') return '复数：身上有很多个，所以说 ' + part.en;
    return '单数：只说一个的时候用这个词';
  }

  function focusLabel(focus) {
    if (focus === 'head') return '本节重点 · 头部 Head';
    if (focus === 'body') return '本节重点 · 身体 Body';
    if (focus === 'legs') return '本节重点 · 下肢 Legs';
    if (focus === 'whole') return '本节重点 · 整体 Whole';
    return '';
  }

  // ====== 发音 ======

  function speechEnded() {
    state.playing = false;
    if (state.stage) state.stage.setSpeaking(false);
    if (state.speakTimer) {
      window.clearTimeout(state.speakTimer);
      state.speakTimer = 0;
    }
    const bars = $('speakingBars');
    const icon = $('speakIcon');
    const label = $('speakLabel');
    if (bars) bars.hidden = true;
    if (icon) icon.hidden = false;
    if (label) label.textContent = '听一听';
    renderCard();
  }

  function fallbackSpeak(part) {
    if (!window.speechSynthesis || typeof window.SpeechSynthesisUtterance === 'undefined') {
      window.setTimeout(speechEnded, 900);
      return;
    }
    try {
      window.speechSynthesis.cancel();
      const u = new SpeechSynthesisUtterance(part.en + ', ' + part.en);
      u.lang = 'en-US';
      u.rate = 0.78;
      u.pitch = 1.15;
      u.onend = speechEnded;
      u.onerror = speechEnded;
      window.speechSynthesis.speak(u);
      state.speakTimer = window.setTimeout(speechEnded, 4600);
    } catch (error) {
      window.setTimeout(speechEnded, 700);
    }
  }

  function speakPart(part) {
    state.playing = true;
    if (state.stage) state.stage.setSpeaking(true);
    const bars = $('speakingBars');
    const icon = $('speakIcon');
    const label = $('speakLabel');
    if (bars) bars.hidden = false;
    if (icon) icon.hidden = true;
    if (label) label.textContent = '正在读…';

    const handled = bridgeCall('speak', part.en + ', ' + part.en, '');
    if (handled === 'true' || handled === true) {
      if (state.speakTimer) window.clearTimeout(state.speakTimer);
      state.speakTimer = window.setTimeout(speechEnded, 4200 + part.en.length * 80);
    } else {
      fallbackSpeak(part);
    }
  }

  // ====== 单词卡 ======

  function renderCard() {
    const part = BY_ID[state.selected] || BY_ID.head;
    const card = $('wordCard');
    const reopen = $('cardReopen');
    if (!card || !reopen) return;
    card.hidden = !state.cardOpen;
    reopen.hidden = state.cardOpen;
    if (!state.cardOpen) return;

    $('wcCn').textContent = part.cn + pluralSuffix(part);
    $('wcEn').textContent = part.en;
    $('wcIpa').textContent = part.ipa;
    $('wcDesc').textContent = part.desc;
    $('wcNote').textContent = adviceOf(part);

    const chip = $('learnedChip');
    const learned = state.learned.has(part.id);
    chip.textContent = learned ? '✓ 已学会' : '点一下听读音';
    chip.className = 'learned-chip' + (learned ? '' : ' pending');
    $('speakBtn').setAttribute('aria-label', '朗读 ' + part.en + '，' + part.cn);
  }

  function closeCard() {
    state.cardOpen = false;
    renderCard();
  }

  function openCard() {
    state.cardOpen = true;
    renderCard();
  }

  // ====== 选中部位 ======

  function pickPart(id, options) {
    const part = BY_ID[id];
    if (!part) return;
    const opts = options || {};
    state.selected = id;
    state.cardOpen = true;
    if (state.stage) state.stage.setSelected(id, opts.face === true);
    if (!state.learned.has(id)) {
      state.learned.add(id);
      showToast('学会新词：' + part.en + ' · ' + part.cn);
    }
    persistProgress();
    syncPanel();
    renderCard();
    bridgeCall('onSelect', id, part.en);
    syncProgressToBridge();
    if (opts.speak !== false) speakPart(part);
  }

  function persistProgress() {
    saveSaved();
  }

  function syncProgressToBridge() {
    bridgeCall('onProgress', JSON.stringify(Array.from(state.learned)));
  }

  function showToast(text) {
    const wrap = $('toastWrap');
    if (!wrap) return;
    while (wrap.children.length >= 2) wrap.removeChild(wrap.firstChild);
    const div = document.createElement('div');
    div.className = 'toast';
    div.innerHTML = '<svg viewBox="0 0 24 24" width="16" height="16" fill="currentColor" aria-hidden="true"><path d="M12 3.2l2.6 5.7 6.2.7-4.6 4.2 1.2 6.1L12 16.9l-5.4 2.9 1.2-6.1-4.6-4.2 6.2-.7z"/></svg>';
    const span = document.createElement('span');
    span.textContent = text;
    div.appendChild(span);
    wrap.appendChild(div);
    window.setTimeout(function () {
      if (div.parentNode) div.parentNode.removeChild(div);
    }, 2400);
  }

  // ====== 单词表面板 ======

  function buildGroups() {
    const host = $('groups');
    if (!host) return;
    host.innerHTML = '';
    GROUPS.forEach(function (group) {
      const items = PARTS.filter(function (p) { return p.grp === group.key; });
      const box = document.createElement('div');
      box.className = 'group';
      box.dataset.group = group.key;

      const head = document.createElement('div');
      head.className = 'group-head';
      const title = document.createElement('span');
      title.className = 'group-title';
      title.textContent = group.zh;
      const en = document.createElement('span');
      en.className = 'group-en';
      en.textContent = group.en;
      const count = document.createElement('span');
      count.className = 'group-count';
      count.dataset.count = group.key;
      count.textContent = '0/' + items.length;
      head.appendChild(title);
      head.appendChild(en);
      head.appendChild(count);

      const chips = document.createElement('div');
      chips.className = 'chips';
      items.forEach(function (part) {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'chip';
        btn.dataset.part = part.id;
        btn.setAttribute('aria-label', part.en + '，' + part.cn);
        const dot = document.createElement('span');
        dot.className = 'dot';
        dot.setAttribute('aria-hidden', 'true');
        btn.appendChild(dot);
        btn.appendChild(document.createTextNode(part.en));
        btn.addEventListener('click', function () {
          pickPart(part.id, { face: true, speak: true });
        });
        chips.appendChild(btn);
      });
      box.appendChild(head);
      box.appendChild(chips);
      host.appendChild(box);
    });
  }

  function syncPanel() {
    const n = state.learned.size;
    const pct = Math.round(n / PARTS.length * 100);
    $('learnedCount').textContent = String(n).padStart(2, '0');
    $('progressPct').textContent = String(pct);
    $('panelCount').textContent = n + '/' + PARTS.length;
    $('panelFoot').textContent = n >= 8
      ? '小测会从 25 个部位里随机出题，已学 ' + n + ' 个'
      : '先点 4 个部位试试，现在已学 ' + n + ' 个';

    GROUPS.forEach(function (group) {
      const items = PARTS.filter(function (p) { return p.grp === group.key; });
      const done = items.filter(function (p) { return state.learned.has(p.id); }).length;
      const count = document.querySelector('[data-count="' + group.key + '"]');
      if (count) count.textContent = done + '/' + items.length;
    });

    PARTS.forEach(function (part) {
      const chip = document.querySelector('[data-part="' + part.id + '"]');
      if (!chip) return;
      chip.classList.toggle('learned', state.learned.has(part.id));
      chip.classList.toggle('active', state.selected === part.id);
      chip.classList.toggle('focus-target', state.focusWords.indexOf(part.id) >= 0);
    });

    const hint = $('stageHint');
    const pillEl = $('focusPill');
    const hasFocusPill = pillEl ? !pillEl.hidden : false;
    // 有「本节重点」徽标时让位；平时保留拖动提示，避免顶部出现空白。
    if (hint) hint.classList.toggle('gone', hasFocusPill);
    syncMap();
  }

  // ====== 部位图 ======

  const FALLBACK_POS = {
    hair: [50, 9.5], head: [64, 14], ear: [73, 22], eye: [42, 21], mouth: [50, 27.5],
    nose: [50, 23.5], neck: [50, 33], chest: [40, 42], belly: [42, 52], arm: [79, 55],
    hand: [88, 66], leg: [37, 76], knee: [37, 84], foot: [63, 90]
  };

  /* 部位图是静态 SVG，直接用为它手工标定的百分比坐标。
   * 之前拿 3D 相机投影：相机在 11.5 远、角色只有 1.8 宽，所有点都挤在
   * 图中央（手落到腰、脚落到膝），对不上插画。 */
  function projectPins() {
    const out = {};
    MAP_LABELS.forEach(function (label) {
      out[label.id] = FALLBACK_POS[label.id] || [50, 50];
    });
    return out;
  }

  function buildMapPins() {
    const host = $('mapPins');
    if (!host) return;
    const proj = projectPins();
    host.innerHTML = '';
    MAP_LABELS.forEach(function (label, index) {
      const part = BY_ID[label.id];
      const pt = proj[label.id];
      if (!part || !pt) return;
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'map-pin ' + label.side;
      btn.dataset.pin = label.id;
      btn.style.left = pt[0] + '%';
      btn.style.top = pt[1] + '%';
      btn.style.zIndex = String(100 - Math.round(pt[1]));
      btn.style.animationDelay = (index * 22) + 'ms';
      btn.setAttribute('aria-label', part.en + '，' + part.cn);

      const dot = document.createElement('span');
      dot.className = 'pin-dot';
      dot.setAttribute('aria-hidden', 'true');
      const foot = document.createElement('span');
      foot.className = 'pin-foot';
      foot.setAttribute('aria-hidden', 'true');
      foot.style.height = label.foot + 'px';
      const text = document.createElement('span');
      text.className = 'pin-text';
      text.textContent = part.en;
      const cn = document.createElement('span');
      cn.className = 'pin-cn';
      cn.setAttribute('aria-hidden', 'true');
      cn.textContent = part.cn;

      btn.appendChild(dot);
      btn.appendChild(foot);
      btn.appendChild(text);
      btn.appendChild(cn);
      btn.addEventListener('click', function () {
        pickPart(part.id, { face: true, speak: true });
      });
      host.appendChild(btn);
    });
  }

  function syncMap() {
    const part = BY_ID[state.selected] || BY_ID.head;
    $('mrCn').textContent = part.cn;
    $('mrEn').textContent = part.en;
    $('mrIpa').textContent = part.ipa;
    const done = state.learned.has(part.id);
    const stateEl = $('mrState');
    stateEl.textContent = done ? '✓ 已学会' : '还没学';
    stateEl.classList.toggle('done', done);

    const revision = $('mapRead');
    if (revision) {
      revision.style.animation = 'none';
      void revision.offsetWidth;
      revision.style.animation = '';
    }

    MAP_LABELS.forEach(function (label) {
      const btn = document.querySelector('[data-pin="' + label.id + '"]');
      if (!btn) return;
      btn.classList.toggle('on', state.selected === label.id);
      btn.classList.toggle('done', state.learned.has(label.id));
    });
  }

  // ====== 视图切换 ======

  function setTab(tab) {
    state.tab = tab === 'map' ? 'map' : 'words';
    $('tabWords').setAttribute('aria-selected', state.tab === 'words' ? 'true' : 'false');
    $('tabMap').setAttribute('aria-selected', state.tab === 'map' ? 'true' : 'false');
    $('wordsView').hidden = state.tab !== 'words';
    $('mapView').hidden = state.tab !== 'map';
    if (state.tab === 'map') syncMap();
  }

  // ====== 原生 focus 注入 ======

  function applyFocus(focus, words) {
    const normalized = focus || 'all';
    state.focus = normalized;
    state.focusWords = Array.isArray(words) ? words.filter(function (id) { return !!BY_ID[id]; }) : [];
    const pill = $('focusPill');
    const label = focusLabel(normalized);
    if (pill) {
      pill.hidden = label === '';
      pill.textContent = label;
    }
    const groupKey = DATA.groupOf(normalized);
    // 不调用 scrollIntoView：页面本身可滚动，自动滚动会把 3D 小星顶出屏幕。
    // 重点分组只用 chip 高亮（.focus-target）标出，孩子自己滑到单词表即可。

    if (state.focusWords.length > 0) {
      const first = state.focusWords[0];
      pickPart(first, { face: true, speak: true });
      return;
    }
    const groupParts = PARTS.filter(function (p) { return p.grp === groupKey; });
    if (groupParts.length > 0) {
      state.selected = groupParts[0].id;
      state.cardOpen = true;
      if (state.stage) state.stage.setSelected(state.selected, true);
      renderCard();
      syncPanel();
    } else {
      syncPanel();
    }
  }

  function setFocus(focus, words) {
    let list = words;
    if (typeof list === 'string') {
      try {
        list = JSON.parse(list);
      } catch (error) {
        list = [];
      }
    }
    if (!Array.isArray(list)) list = [];
    if (!state.ready) {
      state.pendingFocus = { focus: focus, words: list };
      return;
    }
    applyFocus(focus, list);
  }

  // ====== 启动 ======

  function bindUi() {
    $('tabWords').addEventListener('click', function () { setTab('words'); });
    $('tabMap').addEventListener('click', function () { setTab('map'); });
    $('cardClose').addEventListener('click', closeCard);
    $('cardReopen').addEventListener('click', openCard);
    $('speakBtn').addEventListener('click', function () {
      const part = BY_ID[state.selected];
      if (part) speakPart(part);
    });
    $('turnLeft').addEventListener('click', function () { if (state.stage) state.stage.nudge(-1); });
    $('turnRight').addEventListener('click', function () { if (state.stage) state.stage.nudge(1); });
    $('waveBtn').addEventListener('click', function () { if (state.stage) state.stage.wave(); });
    $('resetView').addEventListener('click', function () {
      if (state.stage) {
        state.stage.reset();
        state.stage.setSelected(state.selected, false);
      }
    });
    $('retryScene').addEventListener('click', function () {
      window.location.reload();
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && state.cardOpen) closeCard();
    });
    window.addEventListener('pagehide', function () {
      bridgeCall('stopSpeak');
    });
  }

  function boot() {
    const saved = loadSaved();
    if (saved) {
      const valid = saved.learned.filter(function (id) { return !!BY_ID[id]; });
      valid.forEach(function (id) { state.learned.add(id); });
      if (saved.selected && BY_ID[saved.selected]) state.selected = saved.selected;
    }

    buildGroups();
    buildMapPins();
    bindUi();
    renderCard();
    setTab('words');
    syncPanel();
    syncProgressToBridge();

    const stageEl = $('scene');
    if (!window.BodyStage) {
      $('sceneLoader').classList.add('hide');
      $('sceneError').hidden = false;
      return;
    }
    state.stage = new window.BodyStage(stageEl, {
      onPick: function (id) {
        pickPart(id, { face: false, speak: true });
      },
      onReady: function () {
        state.ready = true;
        const loader = $('sceneLoader');
        if (loader) loader.classList.add('hide');
        bridgeCall('onReady');
        if (state.pendingFocus) {
          const pending = state.pendingFocus;
          state.pendingFocus = null;
          applyFocus(pending.focus, pending.words);
        }
      },
      onError: function () {
        const loader = $('sceneLoader');
        if (loader) loader.classList.add('hide');
        $('sceneError').hidden = false;
      }
    });
    state.stage.setSelected(state.selected, false);
  }

  window.BodyClassApp = {
    setFocus: setFocus,
    select: function (id) {
      if (BY_ID[id]) pickPart(id, { face: true, speak: false });
    },
    speechEnded: speechEnded,
    getLearned: function () { return Array.from(state.learned); }
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
