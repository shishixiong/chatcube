/* ============================================================
   小词城 Word City · UI 状态、单词卡、词汇表、进度与宿主桥接
   导出 window.WordCityApp
   ============================================================ */
(function () {
  'use strict';

  var D = window.WordCityData;
  var S = window.WordCityScene;
  if (!D) {
    console.error('[WordCity] 缺少 WordCityData。');
    return;
  }

  var byId = {};
  var catById = {};
  var zoneById = {};
  D.objects.forEach(function (o) { byId[o.id] = o; });
  D.categories.forEach(function (c) { catById[c.id] = c; });
  D.zones.forEach(function (z) { zoneById[z.id] = z; });

  var CHECK_SVG = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12.5 10 17.5 19 7"/></svg>';
  var SPEAKER_SVG = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 10v4h3l4 3.5v-11L7 10H4Z"/><path d="M15 9.5a3.5 3.5 0 0 1 0 5"/><path d="M17.6 7a7 7 0 0 1 0 10"/></svg>';

  var state = {
    discovered: new Set(),
    currentId: null,
    currentZone: 'overview',
    labelsOn: window.innerWidth >= 900,
    nightOn: false,
    sheetOpen: false,
    celebrating: false,
    completeOnLoad: false
  };

  var els = {};
  var sceneReady = false;
  var canvasEl = null;
  var labelEls = {};
  var dotEls = {};
  var vocabItems = {};
  var vocabGroupEls = {};
  var vocabOpen = false;
  var lastFocus = null;
  var sheetDragY = null;
  var lastCardFocus = null;
  var toastTimer = 0;
  var progressTimer = 0;

  function $(id) { return document.getElementById(id); }

  function bridgeCall(method, a, b) {
    try {
      if (window.CityNativeBridge && typeof window.CityNativeBridge[method] === 'function') {
        return window.CityNativeBridge[method](a, b);
      }
    } catch (err) {
      /* 浏览器预览时静默降级 */
    }
    return null;
  }

  function toast(msg) {
    if (!els.toast) { return; }
    els.toast.textContent = msg;
    els.toast.classList.add('is-on');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
      els.toast.classList.remove('is-on');
    }, 2600);
  }

  function loadProgress() {
    try {
      var raw = window.localStorage.getItem(D.storageKey);
      if (!raw) { return; }
      var ids = JSON.parse(raw);
      if (Array.isArray(ids)) {
        ids.forEach(function (id) {
          if (byId[id]) { state.discovered.add(id); }
        });
      }
    } catch (err) {
      /* 私有模式下 localStorage 可能不可用 */
    }
  }

  function saveProgress() {
    try {
      window.localStorage.setItem(D.storageKey, JSON.stringify(Array.from(state.discovered)));
    } catch (err) { /* 忽略 */ }
  }

  function reportProgress() {
    clearTimeout(progressTimer);
    progressTimer = setTimeout(function () {
      bridgeCall('onProgress', JSON.stringify(Array.from(state.discovered)));
    }, 200);
  }

  function zoneLabel(id) {
    var z = zoneById[id];
    return z ? z.label : '全城';
  }

  /* ---------------- 构建 UI ---------------- */

  function cacheEls() {
    [
      'zoneTabs', 'view', 'labels', 'btnLabels', 'btnReset', 'btnNight', 'btnVocab',
      'loading', 'webglError', 'errorRetry', 'errorVocab',
      'onboarding', 'obStep', 'obTitle', 'obText', 'obIcon', 'obNext', 'obDots',
      'hintChip', 'panel', 'panelHandle', 'panelScroll', 'panelZone',
      'wordCard', 'wcChip', 'wcIndex', 'wcClose', 'wcWord', 'wcPhonetic',
      'wcZh', 'wcDefIcon', 'wcDefText', 'wcExample', 'wcExampleText',
      'wcSpeak', 'wcPrev', 'wcNext', 'wcState', 'panelEmpty', 'panelPeek',
      'peekText', 'peekCount', 'panelCount', 'dotGrid', 'progressCount',
      'badgeCard', 'vocabModal', 'vocabClose', 'vocabCount', 'vocabSearch',
      'vocabClear', 'vocabBody', 'vocabEmpty', 'vocabLive', 'toast',
      'confetti'
    ].forEach(function (id) { els[id] = $(id); });
  }

  function buildZones() {
    D.zones.forEach(function (z) {
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'zone-tab';
      b.setAttribute('role', 'tab');
      b.setAttribute('aria-selected', z.id === state.currentZone ? 'true' : 'false');
      b.dataset.zone = z.id;
      b.innerHTML = '<span class="zone-dot"></span><span></span>';
      b.lastElementChild.textContent = z.label;
      b.title = z.en + ' · ' + z.hint;
      b.addEventListener('click', function () { setZone(z.id); });
      els.zoneTabs.appendChild(b);
      z.el = b;
    });
  }

  function buildDots() {
    D.objects.forEach(function (o) {
      var b = document.createElement('span');
      b.className = 'dot cat-' + o.category;
      b.dataset.id = o.id;
      b.title = o.word + ' · ' + o.zh;
      b.setAttribute('aria-hidden', 'true');
      els.dotGrid.appendChild(b);
      dotEls[o.id] = b;
    });
  }

  function buildLabels() {
    D.objects.forEach(function (o) {
      var el = document.createElement('span');
      el.className = 'map-label';
      var dot = document.createElement('span');
      dot.className = 'label-dot';
      var text = document.createElement('span');
      text.className = 'label-text';
      text.lang = 'en';
      text.textContent = o.word;
      el.appendChild(dot);
      el.appendChild(text);
      els.labels.appendChild(el);
      labelEls[o.id] = el;
    });
  }

  function itemSpeakSvg() {
    return '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 10v4h3l4 3.5v-11L7 10H4Z"/><path d="M15 9.5a3.5 3.5 0 0 1 0 5"/><path d="M17.6 7a7 7 0 0 1 0 10"/></svg>';
  }

  function buildVocab() {
    D.categories.forEach(function (cat) {
      var words = D.objects.filter(function (o) { return o.category === cat.id; });
      var section = document.createElement('section');
      section.className = 'vocab-group';
      section.dataset.cat = cat.id;

      var h = document.createElement('h3');
      h.className = 'vocab-group-title';
      var dot = document.createElement('span');
      dot.className = 'group-dot';
      dot.style.background = cat.color;
      var name = document.createElement('span');
      name.textContent = cat.label;
      var count = document.createElement('em');
      count.dataset.role = 'group-count';
      h.appendChild(dot);
      h.appendChild(name);
      h.appendChild(count);

      var ul = document.createElement('ul');
      ul.className = 'vocab-list';

      words.forEach(function (o) {
        var li = document.createElement('li');
        li.className = 'vocab-item';
        li.dataset.id = o.id;

        var open = document.createElement('button');
        open.type = 'button';
        open.className = 'vi-open';
        open.dataset.id = o.id;

        var main = document.createElement('span');
        main.className = 'vi-main';
        var w = document.createElement('span');
        w.className = 'vi-word';
        w.lang = 'en';
        w.textContent = o.word;
        var zh = document.createElement('span');
        zh.className = 'vi-zh';
        zh.textContent = o.zh;
        main.appendChild(w);
        main.appendChild(zh);

        var check = document.createElement('span');
        check.className = 'vi-check';
        check.innerHTML = CHECK_SVG;

        open.appendChild(main);
        open.appendChild(check);
        open.addEventListener('click', function () {
          closeVocab();
          var zone = o.zone === 'citywide' ? 'overview' : o.zone;
          if (zoneById[zone]) { state.currentZone = zone; syncZoneTabs(); }
          openWord(o.id);
        });

        var speak = document.createElement('button');
        speak.type = 'button';
        speak.className = 'vi-speak';
        speak.setAttribute('aria-label', '朗读 ' + o.word);
        speak.innerHTML = itemSpeakSvg();
        speak.addEventListener('click', function (e) {
          e.stopPropagation();
          speakText(o.word, o.zh);
        });

        li.appendChild(open);
        li.appendChild(speak);
        ul.appendChild(li);
        vocabItems[o.id] = li;
        o._vocabGroup = section;
      });

      section.appendChild(h);
      section.appendChild(ul);
      els.vocabBody.appendChild(section);
      vocabGroupEls[cat.id] = { section: section, count: count, total: words.length };
    });
  }

  function speakText(text, zh) {
    var handled = bridgeCall('speak', text, zh || '');
    if (String(handled) === 'true') { return true; }
    if (!('speechSynthesis' in window) || typeof window.SpeechSynthesisUtterance !== 'function') {
      toast('这台设备暂时不能发音，单词卡还可以继续看。');
      return false;
    }
    try {
      var synth = window.speechSynthesis;
      synth.cancel();
      var u = new window.SpeechSynthesisUtterance(text);
      u.lang = 'en-US';
      u.rate = 0.83;
      u.pitch = 1.08;
      synth.speak(u);
      return true;
    } catch (err) {
      toast('发音没有播放成功，可以再点一次试试。');
      return false;
    }
  }

  function stopSpeak() {
    bridgeCall('stopSpeak');
    if ('speechSynthesis' in window) {
      try { window.speechSynthesis.cancel(); } catch (err) { /* 忽略 */ }
    }
  }

  /* ---------------- 进度 ---------------- */

  function updateCounts() {
    var n = state.discovered.size;
    var total = D.objects.length;
    if (els.panelCount) { els.panelCount.textContent = n + '/' + total; }
    if (els.progressCount) { els.progressCount.textContent = String(n); }
    if (els.peekCount) { els.peekCount.textContent = n + '/' + total; }
    if (els.vocabCount) { els.vocabCount.textContent = '已收集 ' + n + ' / ' + total; }
    if (els.badgeCard) { els.badgeCard.hidden = n < total; }
  }

  function updateDot(id, isNew) {
    var el = dotEls[id];
    if (!el) { return; }
    el.classList.toggle('is-on', state.discovered.has(id));
    if (isNew) {
      el.classList.remove('is-new');
      void el.offsetWidth;
      el.classList.add('is-new');
      setTimeout(function () { el.classList.remove('is-new'); }, 500);
    }
  }

  function updateAllDots() {
    Object.keys(dotEls).forEach(function (id) { updateDot(id, false); });
  }

  function updateVocabCounts() {
    D.categories.forEach(function (cat) {
      var g = vocabGroupEls[cat.id];
      if (!g) { return; }
      var n = D.objects.filter(function (o) {
        return o.category === cat.id && state.discovered.has(o.id);
      }).length;
      g.count.textContent = n + ' / ' + g.total;
    });
  }

  function updateVocabItem(id) {
    var li = vocabItems[id];
    if (li) { li.classList.toggle('is-collected', state.discovered.has(id)); }
  }

  function refreshAllVocab() {
    Object.keys(vocabItems).forEach(updateVocabItem);
    updateVocabCounts();
  }

  function celebrate() {
    if (state.celebrating) { return; }
    state.celebrating = true;
    els.badgeCard.hidden = false;
    toast('你认识了小词城里的 50 个单词！');
    var colors = ['#F2826A', '#F2C14E', '#6FCF97', '#6FA8DC', '#A78BFA', '#FF9F43'];
    for (var i = 0; i < 46; i++) {
      var p = document.createElement('span');
      p.className = 'confetti-piece';
      p.style.left = (Math.random() * 100) + '%';
      p.style.background = colors[i % colors.length];
      p.style.animationDuration = (1.6 + Math.random() * 0.9) + 's';
      p.style.animationDelay = (Math.random() * 0.5) + 's';
      p.style.setProperty('--drift', (Math.random() * 220 - 110) + 'px');
      p.style.setProperty('--spin', (Math.random() * 900 - 300) + 'deg');
      els.confetti.appendChild(p);
    }
    setTimeout(function () {
      while (els.confetti.firstChild) { els.confetti.removeChild(els.confetti.firstChild); }
      state.celebrating = false;
    }, 3200);
  }

  /* ---------------- 面板与单词卡 ---------------- */

  function setZone(id, fromUser) {
    if (!zoneById[id]) { return; }
    state.currentZone = id;
    syncZoneTabs();
    closeCard();
    if (sceneReady) { S.setView(id); }
    if (els.panelZone) { els.panelZone.textContent = zoneLabel(id) + ' · ' + zoneById[id].en; }
    if (fromUser) { hideHint(); }
  }

  function syncZoneTabs() {
    D.zones.forEach(function (z) {
      if (!z.el) { return; }
      var on = z.id === state.currentZone;
      z.el.setAttribute('aria-selected', on ? 'true' : 'false');
    });
    if (els.panelZone) {
      els.panelZone.textContent = zoneLabel(state.currentZone) + ' · ' + (zoneById[state.currentZone] ? zoneById[state.currentZone].en : '');
    }
  }

  function zoneWords() {
    if (state.currentZone === 'overview') { return D.objects.slice(); }
    var list = D.objects.filter(function (o) { return o.zone === state.currentZone; });
    return list.length > 1 ? list : D.objects.slice();
  }

  function renderCard(o, wasNew) {
    var cat = catById[o.category] || D.categories[0];
    els.wcChip.innerHTML = '';
    var dot = document.createElement('span');
    dot.className = 'chip-dot';
    dot.style.background = cat.color;
    var label = document.createElement('span');
    label.textContent = cat.label;
    els.wcChip.appendChild(dot);
    els.wcChip.appendChild(label);

    var idx = D.objects.indexOf(o) + 1;
    els.wcIndex.textContent = idx + ' / ' + D.objects.length;
    els.wcWord.textContent = o.word;
    els.wcPhonetic.textContent = o.phonetic;
    els.wcZh.textContent = o.zh;
    els.wcDefText.textContent = o.kidDefinition;
    els.wcDefIcon.innerHTML = '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + cat.icon + '</svg>';
    els.wcExampleText.textContent = o.example;
    els.wcState.hidden = !state.discovered.has(o.id);
    els.wcState.innerHTML = state.discovered.has(o.id) ? CHECK_SVG + '<span>' + (wasNew ? '已收进小词城护照' : '已收集') + '</span>' : '';

    els.wordCard.hidden = false;
    els.panelEmpty.hidden = true;
    els.wordCard.setAttribute('aria-label', o.word + '，' + o.zh);
  }

  function openWord(id, opts) {
    opts = opts || {};
    var o = byId[id];
    if (!o) {
      toast('这个单词还在搭建中，先看看别的吧。');
      return;
    }
    if (!state.currentId) { lastCardFocus = document.activeElement; }
    var wasNew = !state.discovered.has(id);
    if (wasNew) {
      state.discovered.add(id);
      saveProgress();
      reportProgress();
      updateDot(id, true);
      updateVocabItem(id);
      updateVocabCounts();
      if (state.discovered.size === D.objects.length && !state.completeOnLoad) {
        celebrate();
      }
    }
    state.currentId = id;
    updateCounts();
    renderCard(o, wasNew);
    els.panelScroll.scrollTop = 0;
    updatePeek();

    var zone = o.zone === 'citywide' ? state.currentZone : o.zone;
    if (zoneById[zone]) {
      state.currentZone = zone;
      syncZoneTabs();
    }

    if (sceneReady) {
      var ok = S.focusWord(id);
      if (!ok) { toast('场景里暂时找不到它，不过单词卡可以先看。'); }
    }
    setSheet(true);

    bridgeCall('onSelect', id, o.word);
    speakText(o.word, o.zh);

    if (!opts.silentFocus) {
      var target = els.wcWord;
      target.setAttribute('tabindex', '-1');
      try { target.focus({ preventScroll: true }); } catch (err) { /* 忽略 */ }
    }
    hideHint();
  }

  function closeCard() {
    if (!state.currentId) { return; }
    var id = state.currentId;
    state.currentId = null;
    els.wordCard.hidden = true;
    els.panelEmpty.hidden = false;
    if (sceneReady) {
      S.releaseWord(id);
      S.clearHighlight();
    }
    stopSpeak();
    updatePeek();
    setSheet(false);
    if (lastCardFocus && lastCardFocus !== document.body && document.body.contains(lastCardFocus) && typeof lastCardFocus.focus === 'function') {
      try { lastCardFocus.focus({ preventScroll: true }); } catch (err) { /* 忽略 */ }
    } else if (canvasEl) {
      try { canvasEl.focus({ preventScroll: true }); } catch (err) { /* 忽略 */ }
    }
    lastCardFocus = null;
  }

  function stepWord(dir) {
    var list = zoneWords();
    var current = state.currentId ? byId[state.currentId] : null;
    var index = current ? list.indexOf(current) : -1;
    if (index < 0) {
      list = D.objects;
      index = current ? list.indexOf(current) : 0;
    }
    var next = (index + dir + list.length) % list.length;
    openWord(list[next].id, { silentFocus: true });
  }

  function updatePeek() {
    if (!els.peekText) { return; }
    if (state.currentId && byId[state.currentId]) {
      var o = byId[state.currentId];
      els.peekText.textContent = o.word + ' · ' + o.zh;
    } else {
      els.peekText.textContent = '点一点小城里的建筑、车子和动物';
    }
    if (els.peekCount) {
      els.peekCount.textContent = state.discovered.size + '/' + D.objects.length;
    }
  }

  function setSheet(open) {
    if (window.innerWidth >= 900) { return; }
    state.sheetOpen = !!open;
    els.panel.classList.toggle('is-open', state.sheetOpen);
    els.panelHandle.setAttribute('aria-expanded', state.sheetOpen ? 'true' : 'false');
    els.panelPeek.setAttribute('aria-label', state.sheetOpen ? '收起学习面板' : '展开学习面板');
  }

  /* ---------------- 标签 ---------------- */

  function updateLabels(list) {
    if (!state.labelsOn) { return; }
    var w = els.labels.clientWidth;
    var h = els.labels.clientHeight;
    if (!w || !h) { return; }
    var items = [];
    for (var i = 0; i < list.length; i++) {
      var it = list[i];
      var o = byId[it.id];
      if (!o) { continue; }
      var pri = it.id === state.currentId ? 0 : (state.discovered.has(it.id) ? 1 : 2);
      items.push({ id: it.id, x: it.x, y: it.y, dist: it.dist, pri: pri, word: o.word });
    }
    items.sort(function (a, b) { return a.pri - b.pri || a.dist - b.dist; });

    var placed = [];
    var limit = window.innerWidth < 600 ? 7 : 12;
    var shown = 0;

    Object.keys(labelEls).forEach(function (id) {
      labelEls[id].classList.remove('is-visible');
    });

    for (var j = 0; j < items.length && shown < limit; j++) {
      var item = items[j];
      if (item.x < 36 || item.x > w - 36 || item.y < 34 || item.y > h - 12) { continue; }
      var lw = 18 + item.word.length * 6.4;
      var lh = 22;
      var rect = { x: item.x - lw / 2, y: item.y - lh - 10, w: lw, h: lh };
      var clash = false;
      for (var k = 0; k < placed.length; k++) {
        var p = placed[k];
        if (rect.x < p.x + p.w + 6 && rect.x + rect.w + 6 > p.x &&
            rect.y < p.y + p.h + 4 && rect.y + rect.h + 4 > p.y) {
          clash = true;
          break;
        }
      }
      if (clash) { continue; }
      placed.push(rect);
      var el = labelEls[item.id];
      if (!el) { continue; }
      el.style.transform = 'translate3d(' + item.x.toFixed(1) + 'px,' + item.y.toFixed(1) + 'px,0) translate(-50%,-100%)';
      el.classList.add('is-visible');
      el.classList.toggle('is-current', item.id === state.currentId);
      el.classList.toggle('is-explored', state.discovered.has(item.id));
      shown++;
    }
  }

  function setNight(on, fromUser) {
    state.nightOn = !!on;
    if (els.view) { els.view.classList.toggle('is-night', state.nightOn); }
    if (els.btnNight) {
      els.btnNight.setAttribute('aria-pressed', state.nightOn ? 'true' : 'false');
      els.btnNight.setAttribute('aria-label', state.nightOn ? '关闭黄昏夜灯，回到白天' : '打开黄昏光照与夜间路灯');
      els.btnNight.title = state.nightOn ? '回到白天' : '黄昏光照 · 夜间路灯';
    }
    if (sceneReady && S.setNight) { S.setNight(state.nightOn); }
    if (fromUser) {
      toast(state.nightOn ? '黄昏来了，路灯亮起来了' : '回到明亮的白天');
      hideHint();
    }
  }

  function setLabels(on, fromUser) {
    state.labelsOn = !!on;
    if (els.btnLabels) {
      els.btnLabels.setAttribute('aria-pressed', state.labelsOn ? 'true' : 'false');
      els.btnLabels.classList.toggle('is-on', state.labelsOn);
    }
    if (sceneReady && S.setLabelsEnabled) { S.setLabelsEnabled(state.labelsOn); }
    if (!state.labelsOn) {
      Object.keys(labelEls).forEach(function (id) {
        labelEls[id].classList.remove('is-visible');
      });
    }
    if (fromUser) {
      toast(state.labelsOn ? '已显示英文标签' : '已隐藏英文标签');
    }
  }

  /* ---------------- 词汇表 ---------------- */

  function visibleOpenButtons() {
    var all = els.vocabBody.querySelectorAll('.vi-open');
    var out = [];
    for (var i = 0; i < all.length; i++) {
      if (all[i].offsetParent !== null) { out.push(all[i]); }
    }
    return out;
  }

  function filterVocab(q) {
    q = (q || '').trim().toLowerCase();
    var visible = 0;
    D.categories.forEach(function (cat) {
      var groupVisible = 0;
      D.objects.forEach(function (o) {
        if (o.category !== cat.id) { return; }
        var match = !q || o.word.toLowerCase().indexOf(q) >= 0 || o.zh.indexOf(q) >= 0;
        var li = vocabItems[o.id];
        if (li) { li.hidden = !match; }
        if (match) { groupVisible++; visible++; }
      });
      var g = vocabGroupEls[cat.id];
      if (g) { g.section.hidden = groupVisible === 0; }
    });
    els.vocabEmpty.hidden = visible > 0;
    els.vocabBody.style.display = visible > 0 ? '' : 'none';
    els.vocabClear.hidden = !q;
    els.vocabLive.textContent = q
      ? '找到 ' + visible + ' 个单词'
      : '共 ' + D.objects.length + ' 个单词，已收集 ' + state.discovered.size + ' 个';
  }

  function openVocab() {
    lastFocus = document.activeElement;
    vocabOpen = true;
    els.vocabModal.hidden = false;
    els.vocabSearch.value = '';
    updateCounts();
    refreshAllVocab();
    filterVocab('');
    setTimeout(function () {
      try { els.vocabSearch.focus(); } catch (err) { /* 忽略 */ }
    }, 30);
  }

  function closeVocab() {
    if (!vocabOpen) { return; }
    vocabOpen = false;
    els.vocabModal.hidden = true;
    if (lastFocus && typeof lastFocus.focus === 'function') {
      try { lastFocus.focus({ preventScroll: true }); } catch (err) { /* 忽略 */ }
    } else if (els.btnVocab) {
      try { els.btnVocab.focus({ preventScroll: true }); } catch (err) { /* 忽略 */ }
    }
  }

  function moveVocabFocus(dir) {
    var items = visibleOpenButtons();
    if (!items.length) { return; }
    var active = document.activeElement;
    var idx = items.indexOf(active);
    if (idx < 0) {
      items[0].focus();
      return;
    }
    var next = (idx + dir + items.length) % items.length;
    items[next].focus();
  }

  function trapFocus(e) {
    var nodes = els.vocabModal.querySelectorAll('button, input');
    var list = [];
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].offsetParent !== null && !nodes[i].disabled) { list.push(nodes[i]); }
    }
    if (!list.length) { return; }
    var first = list[0];
    var last = list[list.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  }

  /* ---------------- 新手引导 ---------------- */

  var OB_STEPS = [
    {
      title: '拖动旋转，双指缩放',
      text: '按住画面左右拖动就能绕着小城转一圈；滚轮或双指可以拉近拉远。',
      icon: '<path d="M8 12V6.5a1.5 1.5 0 0 1 3 0V11"/><path d="M11 10.5V5.5a1.5 1.5 0 0 1 3 0V11"/><path d="M14 10.5V7a1.5 1.5 0 0 1 3 0v6.5a5.5 5.5 0 0 1-5.5 5.5H10a5 5 0 0 1-3.5-1.5L3.6 14a1.5 1.5 0 0 1 2.2-2l2.2 2.2"/>'
    },
    {
      title: '点一点建筑、车子和小动物',
      text: '点开后会听到英文发音，还能看到小朋友也能懂的中文解释和例句。',
      icon: '<circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2"/>'
    },
    {
      title: '打开词汇表，看看 50 个单词',
      text: '按地点、交通、街道、人物、自然和动物分组，收集到的单词会亮起来。',
      icon: '<path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v16H6.5A2.5 2.5 0 0 0 4 21.5V5.5Z"/><path d="M4 18.5A2.5 2.5 0 0 1 6.5 16H20"/>'
    }
  ];
  var obIndex = 0;

  function renderOnboarding() {
    var s = OB_STEPS[obIndex];
    els.obStep.textContent = '第 ' + (obIndex + 1) + ' / ' + OB_STEPS.length + ' 步';
    els.obTitle.textContent = s.title;
    els.obText.textContent = s.text;
    els.obIcon.innerHTML = '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + s.icon + '</svg>';
    els.obNext.textContent = obIndex === OB_STEPS.length - 1 ? '开始探索' : '知道啦';
    var dots = els.obDots.querySelectorAll('span');
    for (var i = 0; i < dots.length; i++) {
      dots[i].classList.toggle('is-on', i <= obIndex);
    }
  }

  function maybeShowOnboarding() {
    var done = false;
    try { done = !!window.localStorage.getItem(D.onboardKey); } catch (err) { /* 忽略 */ }
    if (done || state.discovered.size > 0) {
      els.onboarding.hidden = true;
      return;
    }
    els.onboarding.hidden = false;
    renderOnboarding();
  }

  function finishOnboarding() {
    els.onboarding.classList.add('is-leaving');
    setTimeout(function () { els.onboarding.hidden = true; }, 240);
    try { window.localStorage.setItem(D.onboardKey, '1'); } catch (err) { /* 忽略 */ }
  }

  /* ---------------- 提示与宿主 ---------------- */

  var hintTimer = 0;

  function hideHint() {
    if (!els.hintChip) { return; }
    clearTimeout(hintTimer);
    els.hintChip.classList.add('is-hidden');
  }

  function scheduleHint() {
    clearTimeout(hintTimer);
    hintTimer = setTimeout(hideHint, 9000);
  }

  function setHostMode(on) {
    document.body.classList.toggle('is-host', !!on);
  }

  /* ---------------- 事件绑定 ---------------- */

  function bindUI() {
    els.btnVocab.addEventListener('click', openVocab);
    els.vocabClose.addEventListener('click', closeVocab);
    els.vocabModal.querySelector('.modal-backdrop').addEventListener('click', closeVocab);
    els.vocabSearch.addEventListener('input', function () {
      filterVocab(els.vocabSearch.value);
    });
    els.vocabClear.addEventListener('click', function () {
      els.vocabSearch.value = '';
      filterVocab('');
      els.vocabSearch.focus();
    });
    els.vocabSearch.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') {
        var list = visibleOpenButtons();
        if (list.length) {
          e.preventDefault();
          list[0].click();
        }
      } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        moveVocabFocus(1);
      }
    });

    els.btnLabels.addEventListener('click', function () {
      setLabels(!state.labelsOn, true);
    });
    els.btnNight.addEventListener('click', function () {
      setNight(!state.nightOn, true);
    });
    els.btnReset.addEventListener('click', function () {
      if (sceneReady) { S.resetView(); }
      hideHint();
    });

    els.wcClose.addEventListener('click', closeCard);
    els.wcSpeak.addEventListener('click', function () {
      if (!state.currentId) { return; }
      var o = byId[state.currentId];
      if (o) { speakText(o.word, o.zh); }
    });
    els.wcExample.addEventListener('click', function () {
      if (!state.currentId) { return; }
      var o = byId[state.currentId];
      if (o) { speakText(o.example, ''); }
    });
    els.wcPrev.addEventListener('click', function () { stepWord(-1); });
    els.wcNext.addEventListener('click', function () { stepWord(1); });

    els.panelHandle.addEventListener('pointerdown', function (e) {
      sheetDragY = e.clientY;
    });
    els.panelHandle.addEventListener('pointerup', function (e) {
      if (sheetDragY === null) { return; }
      var dy = e.clientY - sheetDragY;
      sheetDragY = null;
      if (dy < -18) {
        setSheet(true);
      } else if (dy > 18) {
        setSheet(false);
      } else {
        setSheet(!state.sheetOpen);
      }
    });
    els.panelPeek.addEventListener('click', function () {
      setSheet(!state.sheetOpen);
    });

    els.errorRetry.addEventListener('click', function () {
      try { window.location.reload(); } catch (err) { window.location.href = window.location.href; }
    });
    els.errorVocab.addEventListener('click', openVocab);

    els.obNext.addEventListener('click', function () {
      if (obIndex < OB_STEPS.length - 1) {
        obIndex++;
        renderOnboarding();
      } else {
        finishOnboarding();
      }
    });

    document.addEventListener('keydown', function (e) {
      if (vocabOpen) {
        if (e.key === 'Escape') {
          e.preventDefault();
          closeVocab();
          return;
        }
        if (e.key === 'Tab') {
          trapFocus(e);
          return;
        }
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
          e.preventDefault();
          moveVocabFocus(e.key === 'ArrowDown' ? 1 : -1);
        }
        return;
      }
      if (e.key === 'Escape' && state.currentId) {
        closeCard();
      }
    });

    ['pointerdown', 'wheel', 'touchstart'].forEach(function (evt) {
      els.view.addEventListener(evt, hideHint, { passive: true });
    });
    scheduleHint();
  }

  /* ---------------- 初始化场景 ---------------- */

  function initScene() {
    var reduced = false;
    try {
      reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    } catch (err) { /* 忽略 */ }

    try {
      S.init({
        container: els.view,
        reducedMotion: reduced,
        labels: state.labelsOn,
        onPick: function (id) {
          if (!id) {
            closeCard();
          } else {
            openWord(id);
          }
        },
        onLabels: updateLabels
      });
      canvasEl = els.view.querySelector('canvas');
      if (canvasEl) { canvasEl.tabIndex = 0; }
      sceneReady = true;
      window.setTimeout(function () {
        if (els.loading) { els.loading.classList.add('is-done'); }
        window.requestAnimationFrame(function () {
          bridgeCall('onReady');
          reportProgress();
        });
      }, 380);
    } catch (err) {
      console.error('[WordCity] 3D 初始化失败：', err);
      sceneReady = false;
      if (els.loading) { els.loading.classList.add('is-done'); }
      if (els.webglError) { els.webglError.hidden = false; }
    }
  }

  /* ---------------- 启动 ---------------- */

  function boot() {
    if (!els.obDots) {
      cacheEls();
    }
    buildZones();
    buildDots();
    buildLabels();
    buildVocab();

    loadProgress();
    state.completeOnLoad = state.discovered.size === D.objects.length;
    updateAllDots();
    refreshAllVocab();
    updateCounts();
    updatePeek();
    syncZoneTabs();
    setLabels(state.labelsOn, false);

    bindUI();
    initScene();
    setNight(state.nightOn, false);
    maybeShowOnboarding();

    if (els.btnLabels) {
      els.btnLabels.setAttribute('aria-pressed', state.labelsOn ? 'true' : 'false');
    }

    window.WordCityApp = {
      select: function (id) { openWord(id); },
      setLabels: function (on) { setLabels(!!on, false); },
      setNight: function (on) { setNight(!!on, false); },
      setView: function (id) { setZone(id); },
      ids: function () { return D.objects.map(function (o) { return o.id; }); },
      discovered: function () { return Array.from(state.discovered); },
      openVocab: openVocab,
      setHostMode: setHostMode
    };

    try {
      if (/(?:^|[?&])host=1(?:&|$)/.test(window.location.search)) {
        setHostMode(true);
      }
    } catch (err) { /* 忽略 */ }

    if (state.discovered.size === D.objects.length) {
      els.badgeCard.hidden = false;
    }
    console.info('[WordCity] 小词城已就绪：' + D.objects.length + ' 个单词。');
  }

  // 页面已构建完成后启动（脚本放在 body 末尾）
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () {
      cacheEls();
      boot();
    });
  } else {
    cacheEls();
    boot();
  }
})();
