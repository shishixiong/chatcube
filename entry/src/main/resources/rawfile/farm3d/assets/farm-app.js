(function (global) {
  'use strict';

  var D = global.FarmData;
  var doc = global.document;

  var ICONS = {
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4"/>',
    moon: '<path d="M20 14.5A8 8 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5Z"/>',
    book: '<path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v15H6.5A2.5 2.5 0 0 0 4 20.5V5.5Z"/><path d="M4 20.5A2.5 2.5 0 0 1 6.5 18H20v3H6.5"/>',
    tag: '<path d="M20.6 13.4 13.4 20.6a2 2 0 0 1-2.8 0L3 13V3h10l7.6 7.6a2 2 0 0 1 0 2.8Z"/><circle cx="7.5" cy="7.5" r="1.4"/>',
    reset: '<path d="M3.5 12a8.5 8.5 0 1 0 2.6-6.1"/><path d="M3.5 4.5V10H9"/>',
    volume: '<path d="M4 9.5h3.5L12 6v12l-4.5-3.5H4a1 1 0 0 1-1-1v-3a1 1 0 0 1 1-1Z"/><path d="M16 8.8a4.5 4.5 0 0 1 0 6.4"/><path d="M18.8 6.2a8 8 0 0 1 0 11.6"/>',
    close: '<path d="M5 5l14 14M19 5 5 19"/>',
    chevron: '<path d="m6 9 6 6 6-6"/>',
    search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4.5 4.5"/>',
    check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
    house: '<path d="M4 10.5 12 4l8 6.5"/><path d="M6 9.5V20h12V9.5"/><path d="M10 20v-5h4v5"/>',
    paw: '<circle cx="7" cy="8.5" r="1.8"/><circle cx="12" cy="6.5" r="1.8"/><circle cx="17" cy="8.5" r="1.8"/><path d="M12 11c3 0 5 2.2 5 4.5S14.8 20 12 20s-5-2.2-5-4.5S9 11 12 11Z"/>',
    sprout: '<path d="M12 20V11"/><path d="M12 11C12 7 9 5 5 5c0 4 3 6 7 6Z"/><path d="M12 13c0-3 2.5-5 6-5 0 3-2.5 5-6 5Z"/>',
    gear: '<circle cx="12" cy="12" r="3"/><path d="M12 3v2.5M12 18.5V21M3 12h2.5M18.5 12H21M5.6 5.6l1.8 1.8M16.6 16.6l1.8 1.8M18.4 5.6l-1.8 1.8M7.4 16.6l-1.8 1.8"/>',
    mountain: '<path d="m3 19 6-11 4.5 8 2.5-4 5 7Z"/><path d="m7.2 12 3 3"/>',
    user: '<circle cx="12" cy="8" r="3.6"/><path d="M4.5 20c.6-4 3.6-6 7.5-6s6.9 2 7.5 6"/>',
    farm: '<path d="M3 20V11l5-3 5 3v9"/><path d="M13 20V8l4-3 4 3v12"/><path d="M6.5 20v-4h3v4"/><path d="M16 20v-6h2v6"/>',
    water: '<path d="M12 3.5c3 4 6 7 6 10a6 6 0 0 1-12 0c0-3 3-6 6-10Z"/>',
    arrowLeft: '<path d="m14 6-6 6 6 6"/>',
    arrowRight: '<path d="m10 6 6 6-6 6"/>',
    play: '<path d="M8 5.5v13l10-6.5Z"/>',
    spot: '<circle cx="12" cy="12" r="7.5"/><circle cx="12" cy="12" r="2"/>'
  };

  function icon(name, cls) {
    var body = ICONS[name] || ICONS.spot;
    return '<svg class="ico' + (cls ? ' ' + cls : '') + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">' + body + '</svg>';
  }

  var state = {
    zone: 'overview',
    selected: null,
    discovered: {},
    idList: [],
    night: false,
    host: false,
    labels: false,
    panel: 'collapsed',
    query: '',
    cat: 'all'
  };

  var dom = {};
  var sceneOk = false;
  var sceneFailReason = '';
  var booted = false;
  var apiReady = false;
  var queue = [];
  var focusTimer = 0;
  var labelEls = {};
  var labelTick = 0;
  var lastFocus = null;

  var byIdMap = {};

  function buildLookup() {
    for (var i = 0; i < D.objects.length; i++) byIdMap[D.objects[i].id] = D.objects[i];
  }

  function $(id) { return doc.getElementById(id); }

  function make(tag, cls, text) {
    var n = doc.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  function loadJSON(key, fallback) {
    try {
      var raw = global.localStorage.getItem(key);
      if (!raw) return fallback;
      return JSON.parse(raw);
    } catch (e) {
      return fallback;
    }
  }

  function saveJSON(key, value) {
    try {
      global.localStorage.setItem(key, JSON.stringify(value));
    } catch (e) {}
  }

  function loadFlag(key) {
    try { return global.localStorage.getItem(key) === '1'; } catch (e) { return false; }
  }

  function saveFlag(key) {
    try { global.localStorage.setItem(key, '1'); } catch (e) {}
  }

  function bridge() { return global.FarmNativeBridge; }

  function bridgeCall(name, args) {
    var b = bridge();
    if (b && typeof b[name] === 'function') {
      try { return b[name].apply(b, args || []); } catch (e) {}
    }
    return null;
  }

  function speak(text, zh) {
    var b = bridge();
    if (b && typeof b.speak === 'function') {
      try { b.speak(text, zh || ''); return true; } catch (e) {}
    }
    return false;
  }

  function stopSpeak() {
    var b = bridge();
    if (b && typeof b.stopSpeak === 'function') {
      try { b.stopSpeak(); } catch (e) {}
    }
  }

  // 把原生朗读桥和舞台/气泡层交给智能体模块
  function attachAgentUI() {
    if (!sceneOk || !global.FarmAgents || !global.FarmAgents.attachUI) return;
    global.FarmAgents.attachUI({
      layer: dom.bubbleLayer,
      stage: dom.stage,
      speak: speak,
      stopSpeak: stopSpeak,
      toast: showToast
    });
  }

  function cacheDom() {
    var ids = [
      'app', 'webTopbar', 'nightBtn', 'nightLabel', 'vocabBtn', 'stage', 'farmCanvas',
      'zoneTabs', 'labelsBtn', 'resetBtn', 'labelLayer', 'bubbleLayer', 'sceneToast', 'loadScreen', 'failCard',
      'failVocabBtn', 'failRetryBtn', 'panel', 'panelGrab', 'panelToggle', 'panelZone',
      'panelCount', 'panelPeek', 'panelBody', 'emptyState', 'wordCard', 'cardCat', 'cardIndex',
      'cardWord', 'cardPhon', 'cardZh', 'cardDef', 'cardExample', 'cardExampleText',
      'cardSpeak', 'cardPrev', 'cardNext', 'cardClose', 'passportGrid', 'passportCount',
      'passportLegend', 'vocabScrim', 'vocabDialog', 'vocabClose', 'vocabSearch', 'vocabFilters',
      'vocabList', 'vocabEmpty', 'onboard', 'onboardStart', 'onboardClose'
    ];
    for (var i = 0; i < ids.length; i++) dom[ids[i]] = $(ids[i]);
  }

  function loadProgress() {
    var saved = loadJSON(D.storageKey, []);
    if (saved && !Array.isArray(saved) && typeof saved === 'object') {
      saved = Object.keys(saved).filter(function (k) { return saved[k]; });
    }
    if (!Array.isArray(saved)) saved = [];
    for (var i = 0; i < saved.length; i++) {
      if (byIdMap[saved[i]] && !state.discovered[saved[i]]) {
        state.discovered[saved[i]] = true;
        state.idList.push(saved[i]);
      }
    }
  }

  function buildZoneTabs() {
    dom.zoneTabs.innerHTML = '';
    for (var i = 0; i < D.zones.length; i++) {
      (function (z) {
        var b = make('button', 'zone-tab');
        b.type = 'button';
        b.setAttribute('role', 'tab');
        b.setAttribute('aria-selected', z.id === state.zone ? 'true' : 'false');
        b.dataset.zone = z.id;
        b.innerHTML = icon(z.icon);
        b.appendChild(make('span', 'zone-tab-label', z.label));
        b.addEventListener('click', function () {
          setZone(z.id, { openFocus: false });
        });
        dom.zoneTabs.appendChild(b);
      })(D.zones[i]);
    }
  }

  function buildPassport() {
    dom.passportGrid.innerHTML = '';
    for (var i = 0; i < D.objects.length; i++) {
      (function (item) {
        var cell = make('div', 'passport-cell');
        cell.dataset.id = item.id;
        cell.style.setProperty('--cat', D.categories[item.category].color);
        cell.innerHTML = '<span class="pc-check">' + icon('check') + '</span>';
        cell.setAttribute('aria-label', item.word + ' ' + item.zh + '，未收集');
        dom.passportGrid.appendChild(cell);
        labelEls['passport:' + item.id] = cell;
      })(D.objects[i]);
    }
    dom.passportLegend.innerHTML = '';
    for (var c = 0; c < D.categoryOrder.length; c++) {
      var cat = D.categories[D.categoryOrder[c]];
      var row = make('span', 'legend-item');
      var dot = make('span', 'legend-dot');
      dot.style.background = cat.color;
      row.appendChild(dot);
      row.appendChild(make('span', 'legend-label', cat.label));
      dom.passportLegend.appendChild(row);
    }
  }

  function buildLabels() {
    dom.labelLayer.innerHTML = '';
    for (var i = 0; i < D.objects.length; i++) {
      (function (item) {
        var chip = make('span', 'label-chip');
        chip.dataset.id = item.id;
        var dot = make('span', 'label-dot');
        dot.style.background = D.categories[item.category].color;
        chip.appendChild(dot);
        chip.appendChild(make('span', 'label-text', item.word));
        chip.style.display = 'none';
        dom.labelLayer.appendChild(chip);
        labelEls['label:' + item.id] = chip;
      })(D.objects[i]);
    }
  }

  function buildVocabFilters() {
    dom.vocabFilters.innerHTML = '';
    var all = make('button', 'filter-chip', '全部');
    all.type = 'button';
    all.dataset.cat = 'all';
    all.setAttribute('aria-pressed', 'true');
    all.addEventListener('click', function () {
      state.cat = 'all';
      updateFilterState();
      renderVocabList();
    });
    dom.vocabFilters.appendChild(all);
    for (var i = 0; i < D.categoryOrder.length; i++) {
      (function (catId) {
        var cat = D.categories[catId];
        var b = make('button', 'filter-chip');
        b.type = 'button';
        b.dataset.cat = catId;
        b.setAttribute('aria-pressed', 'false');
        var dot = make('span', 'filter-dot');
        dot.style.background = cat.color;
        b.appendChild(dot);
        b.appendChild(make('span', null, cat.label));
        b.addEventListener('click', function () {
          state.cat = catId;
          updateFilterState();
          renderVocabList();
        });
        dom.vocabFilters.appendChild(b);
      })(D.categoryOrder[i]);
    }
  }

  function updateFilterState() {
    var chips = dom.vocabFilters.querySelectorAll('.filter-chip');
    for (var i = 0; i < chips.length; i++) {
      chips[i].setAttribute('aria-pressed', chips[i].dataset.cat === state.cat ? 'true' : 'false');
    }
  }

  function updateZoneTabs() {
    var tabs = dom.zoneTabs.querySelectorAll('.zone-tab');
    for (var i = 0; i < tabs.length; i++) {
      tabs[i].setAttribute('aria-selected', tabs[i].dataset.zone === state.zone ? 'true' : 'false');
    }
  }

  function updateCounts() {
    var n = state.idList.length;
    dom.panelCount.textContent = n + ' / 50';
    dom.passportCount.textContent = n + ' / 50';
    for (var i = 0; i < D.objects.length; i++) {
      var item = D.objects[i];
      var cell = dom.passportGrid.children[i];
      if (!cell) continue;
      var found = !!state.discovered[item.id];
      if (found) cell.classList.add('is-found');
      else cell.classList.remove('is-found');
      cell.setAttribute('aria-label', item.word + ' ' + item.zh + '，' + (found ? '已收集' : '未收集'));
    }
  }

  function discover(id) {
    if (state.discovered[id]) return;
    state.discovered[id] = true;
    state.idList.push(id);
    saveJSON(D.storageKey, state.idList);
    updateCounts();
    bridgeCall('onProgress', [JSON.stringify(state.idList)]);
  }

  function updatePanelZone() {
    var z = null;
    for (var i = 0; i < D.zones.length; i++) if (D.zones[i].id === state.zone) z = D.zones[i];
    dom.panelZone.textContent = z ? z.label : '全农场';
  }

  function setZone(zone, opts) {
    if (!byIdMap) return;
    var valid = false;
    for (var i = 0; i < D.zones.length; i++) if (D.zones[i].id === zone) valid = true;
    if (!valid) return;
    state.zone = zone;
    updateZoneTabs();
    updatePanelZone();
    if (sceneOk && global.FarmScene) global.FarmScene.setView(zone);
    if (focusTimer) { global.clearTimeout(focusTimer); focusTimer = 0; }
    if (opts && opts.openFocus) {
      var v = D.views[zone];
      if (v && v.focus && v.focus.length) {
        focusTimer = global.setTimeout(function () {
          focusTimer = 0;
          if (state.zone === zone) selectWord(v.focus[0]);
        }, 960);
      }
    }
  }

  function navList() {
    if (state.zone === 'overview') return D.objects;
    var out = [];
    for (var i = 0; i < D.objects.length; i++) {
      var o = D.objects[i];
      if (o.zone === state.zone || o.zone === 'farmwide') out.push(o);
    }
    return out;
  }

  function renderCard(item) {
    var cat = D.categories[item.category];
    dom.cardCat.innerHTML = '<span class="cat-dot" style="background:' + cat.color + '"></span>' + icon(cat.icon) + '<span class="cat-name">' + cat.label + '</span>';
    var idx = 0;
    for (var i = 0; i < D.objects.length; i++) if (D.objects[i].id === item.id) idx = i + 1;
    dom.cardIndex.textContent = idx + ' / 50';
    dom.cardWord.textContent = item.word;
    dom.cardPhon.textContent = item.phonetic;
    dom.cardZh.textContent = item.zh;
    dom.cardDef.textContent = item.kidDefinition;
    dom.cardExampleText.textContent = item.example;
    dom.cardExample.setAttribute('aria-label', '朗读例句：' + item.example);
    dom.cardSpeak.setAttribute('aria-label', '朗读 ' + item.word);
    dom.wordCard.hidden = false;
    dom.emptyState.hidden = true;
    dom.wordCard.classList.remove('is-entering');
    void dom.wordCard.offsetWidth;
    dom.wordCard.classList.add('is-entering');
  }

  function selectWord(id, opts) {
    var item = byIdMap[id];
    if (!item) return false;
    if (sceneOk && global.FarmScene) global.FarmScene.select(id, opts && opts.root);
    state.selected = id;
    renderCard(item);
    openPanel();
    discover(id);
    speak(item.word, item.zh);
    bridgeCall('onSelect', [id, item.word]);
    if (!opts || opts.scroll !== false) {
      dom.panelBody.scrollTop = 0;
    }
    return true;
  }

  function closeCard() {
    state.selected = null;
    if (sceneOk && global.FarmScene) global.FarmScene.clearSelection();
    dom.wordCard.hidden = true;
    dom.emptyState.hidden = false;
    collapsePanel();
    stopSpeak();
  }

  function stepWord(delta) {
    var list = navList();
    if (!list.length) return;
    var idx = -1;
    for (var i = 0; i < list.length; i++) if (list[i].id === state.selected) idx = i;
    if (idx < 0) idx = 0;
    var next = list[(idx + delta + list.length) % list.length];
    selectWord(next.id);
  }

  function openPanel() {
    state.panel = 'open';
    if (dom.panel) dom.panel.setAttribute('data-state', 'open');
    if (dom.panelToggle) dom.panelToggle.setAttribute('aria-expanded', 'true');
  }

  function collapsePanel() {
    state.panel = 'collapsed';
    if (dom.panel) dom.panel.setAttribute('data-state', 'collapsed');
    if (dom.panelToggle) dom.panelToggle.setAttribute('aria-expanded', 'false');
  }

  function togglePanel() {
    if (state.panel === 'open') collapsePanel();
    else openPanel();
  }

  function applyNight(on) {
    state.night = !!on;
    if (sceneOk && global.FarmScene) global.FarmScene.setNight(state.night);
    if (dom.nightBtn) dom.nightBtn.setAttribute('aria-pressed', state.night ? 'true' : 'false');
    if (dom.nightLabel) dom.nightLabel.textContent = state.night ? '白天' : '黄昏';
    if (dom.nightBtn) {
      dom.nightBtn.innerHTML = icon(state.night ? 'sun' : 'moon') + '<span id="nightLabel" class="btn-label">' + (state.night ? '白天' : '黄昏') + '</span>';
      dom.nightLabel = $('nightLabel');
    }
    showToast(state.night ? '黄昏模式：灯亮起来了' : '回到白天');
  }

  var toastTimer = 0;
  function showToast(text) {
    if (!dom.sceneToast) return;
    dom.sceneToast.textContent = text;
    dom.sceneToast.classList.add('is-visible');
    if (toastTimer) global.clearTimeout(toastTimer);
    toastTimer = global.setTimeout(function () {
      dom.sceneToast.classList.remove('is-visible');
    }, 1900);
  }

  function toggleLabels() {
    state.labels = !state.labels;
    if (dom.labelsBtn) dom.labelsBtn.setAttribute('aria-pressed', state.labels ? 'true' : 'false');
    if (dom.labelLayer) dom.labelLayer.hidden = !state.labels;
    if (sceneOk && global.FarmScene) global.FarmScene.setLabelsVisible(state.labels);
    if (!state.labels) {
      for (var id in labelEls) {
        if (id.indexOf('label:') === 0) labelEls[id].style.display = 'none';
      }
    } else {
      positionLabels();
    }
  }

  function positionLabels() {
    if (!state.labels || !sceneOk || !global.FarmScene) return;
    for (var key in labelEls) {
      if (key.indexOf('label:') === 0) labelEls[key].style.display = 'none';
    }
    var data = global.FarmScene.getLabels();
    if (!data.length) return;
    data.sort(function (a, b) {
      var za = (byIdMap[a.id] && (byIdMap[a.id].zone === state.zone || byIdMap[a.id].zone === 'farmwide')) ? 0 : 1;
      var zb = (byIdMap[b.id] && (byIdMap[b.id].zone === state.zone || byIdMap[b.id].zone === 'farmwide')) ? 0 : 1;
      if (za !== zb) return za - zb;
      return a.dist - b.dist;
    });
    var w = dom.stage.clientWidth;
    var h = dom.stage.clientHeight;
    if (w < 20 || h < 20) return;
    var used = [];
    if (global.FarmAgents && global.FarmAgents.getOcclusionRects) {
      var bubbleRects = global.FarmAgents.getOcclusionRects();
      for (var b = 0; b < bubbleRects.length; b++) used.push(bubbleRects[b]);
    }
    for (var i = 0; i < data.length; i++) {
      var d = data[i];
      var item = byIdMap[d.id];
      if (!item) continue;
      var chip = labelEls['label:' + d.id];
      if (!chip) continue;
      var width = 22 + item.word.length * 7.2;
      if (d.x < -40 || d.x > w + 40 || d.y < 0 || d.y > h + 20) {
        chip.style.display = 'none';
        continue;
      }
      var x = Math.max(width / 2 + 8, Math.min(w - width / 2 - 8, d.x));
      var y = Math.max(56, Math.min(h - 12, d.y));
      var rect = { x: x - width / 2, y: y - 28, w: width, h: 26 };
      var hit = false;
      for (var u = 0; u < used.length; u++) {
        var r = used[u];
        if (rect.x < r.x + r.w + 4 && rect.x + rect.w + 4 > r.x && rect.y < r.y + r.h + 4 && rect.y + rect.h + 4 > r.y) {
          hit = true;
          break;
        }
      }
      if (hit) {
        chip.style.display = 'none';
        continue;
      }
      used.push(rect);
      chip.style.display = 'flex';
      chip.style.left = x + 'px';
      chip.style.top = y + 'px';
    }
  }

  function frameTick() {
    var now = Date.now();
    if (global.FarmAgents && global.FarmAgents.frame) global.FarmAgents.frame(now);
    if (!state.labels) return;
    if (now - labelTick < 90) return;
    labelTick = now;
    positionLabels();
  }

  function handlePick(id, root, point) {
    if (!id) {
      closeCard();
      return;
    }
    // 单击动物：先让它做短反应（马会先回到原位），再打开单词卡，
    // 这样选中环和相机都按反应后的位置计算，不会对到旧位置。
    if (global.FarmAgents && global.FarmAgents.isAgent && global.FarmAgents.isAgent(id)) {
      global.FarmAgents.interact(id, root);
    }
    selectWord(id, { root: root });
    // 点中物体：把相机中心移到它身上，方便继续放大细看
    if (sceneOk && global.FarmScene && global.FarmScene.focus) {
      global.FarmScene.focus(id, root, point);
    }
  }

  function renderVocabList() {
    if (!dom.vocabList) return;
    var q = state.query.toLowerCase();
    dom.vocabList.innerHTML = '';
    var count = 0;
    for (var i = 0; i < D.objects.length; i++) {
      var item = D.objects[i];
      if (state.cat !== 'all' && item.category !== state.cat) continue;
      if (q && item.word.toLowerCase().indexOf(q) < 0 && item.zh.indexOf(state.query) < 0) continue;
      count++;
      var row = make('div', 'vocab-row');
      var main = make('button', 'vocab-main');
      main.type = 'button';
      main.setAttribute('aria-label', '查看 ' + item.word + ' ' + item.zh);
      var head = make('span', 'vocab-line');
      head.appendChild(make('span', 'vocab-word', item.word));
      head.appendChild(make('span', 'vocab-phon', item.phonetic));
      main.appendChild(head);
      var sub = make('span', 'vocab-sub');
      var dot = make('span', 'cat-dot');
      dot.style.background = D.categories[item.category].color;
      sub.appendChild(dot);
      sub.appendChild(make('span', 'vocab-zh', item.zh));
      sub.appendChild(make('span', 'vocab-cat', D.categories[item.category].label));
      main.appendChild(sub);
      (function (id) {
        main.addEventListener('click', function () {
          closeVocab();
          selectWord(id);
          setZoneFocusFor(id);
        });
      })(item.id);
      row.appendChild(main);

      var play = make('button', 'vocab-play');
      play.type = 'button';
      play.innerHTML = icon('volume');
      play.setAttribute('aria-label', '朗读 ' + item.word);
      (function (word, zh) {
        play.addEventListener('click', function () {
          if (!speak(word, zh)) showToast('当前环境无法播放发音');
        });
      })(item.word, item.zh);
      row.appendChild(play);

      var found = !!state.discovered[item.id];
      var badge = make('span', 'vocab-badge' + (found ? ' is-found' : ''));
      badge.innerHTML = found ? icon('check') : icon('spot');
      badge.appendChild(make('span', 'badge-text', found ? '已收集' : '未收集'));
      row.appendChild(badge);

      dom.vocabList.appendChild(row);
    }
    dom.vocabEmpty.hidden = count !== 0;
    dom.vocabList.hidden = count === 0;
    if (count === 0) {
      dom.vocabEmpty.textContent = '没有找到「' + state.query + '」，换一个中文或英文试试。';
    }
  }

  function setZoneFocusFor(id) {
    var item = byIdMap[id];
    if (!item) return;
    if (item.zone !== 'farmwide' && item.zone !== state.zone) {
      setZone(item.zone, { openFocus: false });
    }
  }

  function openVocab() {
    if (!dom.vocabScrim) return;
    lastFocus = doc.activeElement;
    state.query = '';
    if (dom.vocabSearch) dom.vocabSearch.value = '';
    renderVocabList();
    updateFilterState();
    dom.vocabScrim.hidden = false;
    doc.body.classList.add('is-modal');
    global.setTimeout(function () {
      if (dom.vocabClose) dom.vocabClose.focus();
    }, 40);
  }

  function closeVocab() {
    if (!dom.vocabScrim) return;
    dom.vocabScrim.hidden = true;
    doc.body.classList.remove('is-modal');
    if (lastFocus && lastFocus.focus) {
      try { lastFocus.focus(); } catch (e) {}
    }
  }

  function showFail() {
    if (dom.loadScreen) dom.loadScreen.classList.add('is-hidden');
    if (dom.failCard) dom.failCard.hidden = false;
    showToast('3D 场景未能启动，可先用词汇表学习');
  }

  function hideLoad() {
    if (!dom.loadScreen) return;
    dom.loadScreen.classList.add('is-hidden');
    global.setTimeout(function () {
      if (dom.loadScreen) dom.loadScreen.hidden = true;
    }, 480);
  }

  function hasWebGL() {
    try {
      var c = doc.createElement('canvas');
      var gl = c.getContext('webgl') || c.getContext('experimental-webgl');
      return !!gl;
    } catch (e) {
      return false;
    }
  }

  function initScene() {
    if (dom.failCard) dom.failCard.hidden = true;
    var reason = '';
    if (!global.THREE) {
      reason = 'three-missing';
    } else if (!global.FarmScene) {
      reason = 'scene-missing';
    } else if (!hasWebGL()) {
      reason = 'no-webgl';
    } else {
      try {
        sceneOk = global.FarmScene.init(dom.farmCanvas, { onPick: handlePick, onFrame: frameTick });
        if (!sceneOk) reason = 'init-false';
      } catch (e) {
        sceneOk = false;
        reason = 'init-threw: ' + (e && e.message ? e.message : String(e));
      }
    }
    if (!sceneOk) {
      sceneFailReason = reason || 'unknown';
      console.error('[farm] initScene failed: ' + sceneFailReason);
      showFail();
    }
    return sceneOk;
  }

  function bindUI() {
    if (dom.nightBtn) dom.nightBtn.addEventListener('click', function () { applyNight(!state.night); });
    if (dom.vocabBtn) dom.vocabBtn.addEventListener('click', openVocab);
    if (dom.labelsBtn) dom.labelsBtn.addEventListener('click', toggleLabels);
    if (dom.resetBtn) {
      dom.resetBtn.addEventListener('click', function () {
        setZone('overview', { openFocus: false });
        closeCard();
        if (sceneOk && global.FarmScene) global.FarmScene.resetView();
        showToast('已回到全农场视角');
      });
    }
    if (dom.panelToggle) dom.panelToggle.addEventListener('click', togglePanel);
    if (dom.cardClose) dom.cardClose.addEventListener('click', closeCard);
    if (dom.cardSpeak) {
      dom.cardSpeak.addEventListener('click', function () {
        if (state.selected) {
          var item = byIdMap[state.selected];
          if (item && !speak(item.word, item.zh)) showToast('当前环境无法播放发音');
        }
      });
    }
    if (dom.cardExample) {
      dom.cardExample.addEventListener('click', function () {
        if (state.selected) {
          var item = byIdMap[state.selected];
          if (item && !speak(item.example, '')) showToast('当前环境无法播放发音');
        }
      });
    }
    if (dom.cardPrev) dom.cardPrev.addEventListener('click', function () { stepWord(-1); });
    if (dom.cardNext) dom.cardNext.addEventListener('click', function () { stepWord(1); });
    if (dom.vocabClose) dom.vocabClose.addEventListener('click', closeVocab);
    if (dom.vocabScrim) {
      dom.vocabScrim.addEventListener('click', function (e) {
        if (e.target === dom.vocabScrim) closeVocab();
      });
    }
    if (dom.vocabSearch) {
      dom.vocabSearch.addEventListener('input', function () {
        state.query = dom.vocabSearch.value || '';
        renderVocabList();
      });
    }
    if (dom.onboardStart) {
      dom.onboardStart.addEventListener('click', dismissOnboard);
    }
    if (dom.onboardClose) dom.onboardClose.addEventListener('click', dismissOnboard);
    if (dom.failVocabBtn) dom.failVocabBtn.addEventListener('click', openVocab);
    if (dom.failRetryBtn) {
      dom.failRetryBtn.addEventListener('click', function () {
        try { global.location.reload(); } catch (e) {}
      });
    }
    doc.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') {
        if (dom.vocabScrim && !dom.vocabScrim.hidden) closeVocab();
        else if (state.selected) closeCard();
      }
    });
    doc.addEventListener('visibilitychange', function () {
      if (doc.hidden && global.FarmAgents && global.FarmAgents.clearBubbles) {
        global.FarmAgents.clearBubbles();
      }
    });
  }

  function dismissOnboard() {
    if (dom.onboard) dom.onboard.hidden = true;
    saveFlag(D.onboardKey);
  }

  function maybeOnboard() {
    if (loadFlag(D.onboardKey)) return;
    global.setTimeout(function () {
      if (dom.onboard) dom.onboard.hidden = false;
    }, 900);
  }

  function flushQueue() {
    apiReady = true;
    while (queue.length) {
      var item = queue.shift();
      item[0].apply(null, item[1]);
    }
  }

  function apiCall(fn, args) {
    if (!apiReady) {
      queue.push([fn, args || []]);
      return;
    }
    fn.apply(null, args || []);
  }

  function apiSetView(name) {
    setZone(name, { openFocus: true });
  }

  function apiSelect(id) {
    if (byIdMap[id]) {
      setZoneFocusFor(id);
      selectWord(id);
    }
  }

  function apiSetHostMode(on) {
    state.host = !!on;
    if (dom.app) dom.app.classList.toggle('host-mode', state.host);
    if (dom.webTopbar) dom.webTopbar.hidden = state.host;
  }

  function apiResetView() {
    setZone('overview', { openFocus: false });
    closeCard();
    if (sceneOk && global.FarmScene) global.FarmScene.resetView();
  }

  global.FarmApp = {
    setHostMode: function (v) { apiCall(apiSetHostMode, [v]); },
    setView: function (name) { apiCall(apiSetView, [name]); },
    select: function (id) { apiCall(apiSelect, [id]); },
    openVocab: function () { apiCall(openVocab, []); },
    setNight: function (v) { apiCall(applyNight, [v]); },
    resetView: function () { apiCall(apiResetView, []); }
  };

  function boot() {
    if (booted) return;
    booted = true;
    if (!D) {
      if (doc.getElementById('loadScreen')) doc.getElementById('loadScreen').hidden = true;
      bridgeCall('onError', ['data']);
      return;
    }
    buildLookup();
    cacheDom();
    loadProgress();
    buildZoneTabs();
    buildPassport();
    buildLabels();
    buildVocabFilters();
    bindUI();
    updateCounts();
    updatePanelZone();
    if (dom.panel) dom.panel.setAttribute('data-state', 'collapsed');
    global.setTimeout(function () {
      initScene();
      if (sceneOk && global.FarmScene) {
        global.FarmScene.resize();
        attachAgentUI();
        if (state.labels) global.FarmScene.setLabelsVisible(true);
        if (state.night) global.FarmScene.setNight(true);
      }
      hideLoad();
      flushQueue();
      if (sceneOk) {
        bridgeCall('onReady', []);
      } else {
        bridgeCall('onError', [sceneFailReason || 'webgl']);
      }
      bridgeCall('onProgress', [JSON.stringify(state.idList)]);
      maybeOnboard();
      global.setTimeout(function () {
        if (sceneOk && global.FarmScene) global.FarmScene.resize();
      }, 160);
    }, 50);
  }

  if (doc.readyState === 'loading') {
    doc.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})(window);
