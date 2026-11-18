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
  // 室内词与街道词共用一个查表，单词卡 / 词汇表 / 进度都不用改分支
  (D.indoorObjects || []).forEach(function (o) { byId[o.id] = o; });
  // 全部单词（街道 + 室内）。统计口径统一走这个，避免各算各的。
  var allWords = D.objects.concat(D.indoorObjects || []);
  // 室内状态提早声明：buildVocab 等早于业务函数执行的代码也要读它
  var interior = {
    inside: false,
    id: null,
    savedZone: 'overview'
  };
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
    tourOn: false,
    hour: 10,
    timeFlow: false,
    weather: 'clear',
    instantWeather: false,
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
      'zoneTabs', 'view', 'labels', 'btnLabels', 'btnReset', 'btnNight', 'btnVocab', 'btnTour', 'tourLabel', 'btnHunt',
      'skyBar', 'skyClock', 'skyPhase', 'skyFill', 'hourRange', 'btnTimeFlow',
      'loading', 'webglError', 'errorRetry', 'errorVocab',
      'onboarding', 'obStep', 'obTitle', 'obText', 'obIcon', 'obNext', 'obDots',
      'hintChip', 'panel', 'panelHandle', 'panelScroll', 'panelZone',
      'wordCard', 'wcChip', 'wcIndex', 'wcClose', 'wcWord', 'wcPhonetic',
      'wcZh', 'wcDefIcon', 'wcDefText', 'wcExample', 'wcExampleText',
      'wcSpeak', 'wcPrev', 'wcNext', 'wcState', 'panelEmpty', 'panelPeek',
      'wcEnter',
      'enterTip', 'enterBtn', 'enterLabel', 'enterName',
      'interiorBar', 'interiorBack', 'interiorTitle',
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
    // 室内只列本屋的词；在街上不列室内词（免得列出一堆看不见的东西）
    var scopeWords = interior.inside
      ? allWords.filter(function (o) { return o.interior === interior.id; })
      : allWords.filter(function (o) { return !o.interior; });

    D.categories.forEach(function (cat) {
      var words = scopeWords.filter(function (o) { return o.category === cat.id; });
      if (!words.length) { return; }
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
    var total = allWords.length;
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

    var idx = allWords.indexOf(o) + 1;
    els.wcIndex.textContent = idx + ' / ' + allWords.length;
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

    /* 可进入的建筑：卡上多一个「推门进去」的入口。
       室内词不显示（避免在屋里点屋里）。 */
    if (els.wcEnter) {
      var canEnter = !interior.inside && isEnterable(o.id);
      els.wcEnter.hidden = !canEnter;
      if (canEnter) {
        els.wcEnter.dataset.target = o.id;
        var idef = window.WordCityInterior.getDef(o.id);
        els.wcEnter.querySelector('.wce-text').textContent =
          '推门进' + (idef ? idef.name : '里面') + '看看';
      }
    }
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
      if (state.discovered.size === allWords.length && !state.completeOnLoad) {
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
      els.peekCount.textContent = state.discovered.size + '/' + allWords.length;
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

  /* ---------------- 时间与天气 ---------------- */

  // 时段名：由场景层按 hour 推算，UI 只负责显示
  function phaseLabel(h) {
    if (h < 4.5) { return '深夜'; }
    if (h < 7.5) { return '清晨'; }
    if (h < 11.5) { return '上午'; }
    if (h < 14.5) { return '正午'; }
    if (h < 17.5) { return '下午'; }
    if (h < 19.8) { return '黄昏'; }
    return '夜晚';
  }

  function syncSkyUI(h) {
    if (els.hourRange && document.activeElement !== els.hourRange) {
      els.hourRange.value = String(h.toFixed(2));
    }
    if (els.skyClock) { els.skyClock.textContent = S.hourLabel ? S.hourLabel(h) : ''; }
    if (els.skyPhase) { els.skyPhase.textContent = phaseLabel(h); }
    if (els.skyFill) { els.skyFill.style.width = (h / 24 * 100).toFixed(1) + '%'; }
    // 夜色 / 暖色强度由场景层统一算，UI 只负责写进 CSS 变量
    var st = (sceneReady && S.getSkyState) ? S.getSkyState() : null;
    var night = st ? st.night : nightAmount(h);
    var warm = st ? st.warm * 0.72 : warmAmount(h);
    if (els.view) {
      els.view.style.setProperty('--night-op', night.toFixed(3));
      els.view.style.setProperty('--warm-op', warm.toFixed(3));
      // 雨雪天让背景层也偏灰，避免出现「灰色3D + 蓝天CSS」的割裂
      if (st) {
        var wet = Math.max(st.rain, st.snow);
        els.view.style.setProperty('--wet-op', (wet * 0.62).toFixed(3));
      }
    }
    state.nightOn = night > 0.5;
  }

  // 与场景层 sampleSky 的派生量保持一致（只用于 UI 配色）
  function nightAmount(h) {
    if (h >= 18.5) { return Math.min(1, (h - 18.5) / 2.4); }
    if (h <= 5.4) { return Math.max(0, Math.min(1, 1 - (h - 4.0) / 1.4)); }
    return 0;
  }
  function warmAmount(h) {
    var d = (h >= 16.5 && h <= 20) ? Math.sin(((h - 16.5) / 3.5) * Math.PI) : 0;
    var w = (h >= 4.6 && h <= 7.6) ? Math.sin(((h - 4.6) / 3.0) * Math.PI) : 0;
    return Math.max(d, w) * 0.72;
  }

  var lastPushedHour = -1;

  function setHour(h, fromUser, instant) {
    h = ((h % 24) + 24) % 24;
    state.hour = h;
    if (sceneReady && S.setHour) { S.setHour(h, !!instant); }
    // 立即模式下场景已经跳变，UI 也要马上对齐
    if (instant) { lastPushedHour = h; }
    syncSkyUI(h);
    if (fromUser) {
      hideHint();
      // 用户拖动时如果时间在流动，先停下，免得刚拖完又跑走
      if (state.timeFlow) { setTimeFlow(false, false); }
    }
  }

  function setTimeFlow(on, fromUser) {
    state.timeFlow = !!on;
    if (sceneReady && S.setTimeFlow) { S.setTimeFlow(state.timeFlow); }
    if (els.btnTimeFlow) {
      els.btnTimeFlow.setAttribute('aria-pressed', state.timeFlow ? 'true' : 'false');
      els.btnTimeFlow.setAttribute('aria-label', state.timeFlow ? '暂停时间流动' : '播放一天的时间流动');
      els.btnTimeFlow.title = state.timeFlow ? '暂停时间' : '让时间自己走（约 5 分钟过完一天）';
    }
    if (fromUser) {
      toast(state.timeFlow ? '时间开始流动，从早到晚慢慢走过' : '时间停住了');
      hideHint();
    }
  }

  var WEATHER_LABEL = { clear: '晴天', rain: '下雨了', snow: '下雪了' };

  function setWeather(kind, fromUser) {
    if (kind !== 'clear' && kind !== 'rain' && kind !== 'snow') { kind = 'clear'; }
    state.weather = kind;
    if (sceneReady && S.setWeather) { S.setWeather(kind, !fromUser && state.instantWeather); }
    // 按钮状态
    var btns = document.querySelectorAll('.weather-btn');
    for (var i = 0; i < btns.length; i++) {
      var on = btns[i].getAttribute('data-weather') === kind;
      btns[i].classList.toggle('is-on', on);
      btns[i].setAttribute('aria-pressed', on ? 'true' : 'false');
    }
    if (fromUser) {
      toast(kind === 'clear' ? '雨停雪停，太阳出来啦'
        : kind === 'rain' ? '下雨了，大家都撑起了伞'
        : '下雪了，整个小城都变白了');
      hideHint();
    }
  }

  /* 把 setNight 保留成旧接口：宿主原生按钮仍然调它。
     它现在只是「跳到晚上 / 跳回白天」的语法糖。 */
  function setNight(on, fromUser) {
    var target = on ? 20.5 : 10;
    if (state.timeFlow) { setTimeFlow(false, false); }
    setHour(target, fromUser);
    if (fromUser) {
      toast(on ? '黄昏来了，路灯亮起来了' : '回到明亮的白天');
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
      : '共 ' + allWords.length + ' 个单词，已收集 ' + state.discovered.size + ' 个';
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

  /* ---------------- 自动巡游 ---------------- */

  // 巡游顺序：从商业街出发，绕学校、公园、医院一圈，回到全城俯视。
  var TOUR_ZONES = ['main_street', 'school_zone', 'park_zone', 'hospital_zone', 'overview'];
  var tourStopTimer = 0;

  function setTour(on, fromUser) {
    if (!sceneReady || !S.startTour) { return; }
    state.tourOn = !!on;
    if (state.tourOn) {
      closeCard();
      S.startTour(TOUR_ZONES, function (id, index) {
        state.currentZone = id;
        syncZoneTabs();
        if (els.tourLabel) {
          els.tourLabel.textContent = '巡游 ' + (index + 1) + '/' + TOUR_ZONES.length;
        }
      });
      if (els.btnTour) {
        els.btnTour.classList.add('is-on');
        els.btnTour.setAttribute('aria-pressed', 'true');
      }
      if (fromUser) { toast('小城巡游开始了，点一下画面就能自己走'); }
      hideHint();
    } else {
      S.stopTour();
      if (els.btnTour) {
        els.btnTour.classList.remove('is-on');
        els.btnTour.setAttribute('aria-pressed', 'false');
      }
      if (els.tourLabel) { els.tourLabel.textContent = '自动巡游'; }
    }
  }

  // 用户一拖动画面，巡游就自动停下（场景层已经 stopTour，这里同步 UI）
  function syncTourUI() {
    if (!state.tourOn) { return; }
    if (S.isTouring && !S.isTouring()) {
      state.tourOn = false;
      if (els.btnTour) {
        els.btnTour.classList.remove('is-on');
        els.btnTour.setAttribute('aria-pressed', 'false');
      }
      if (els.tourLabel) { els.tourLabel.textContent = '自动巡游'; }
    }
  }

  /* ---------------- 建筑内部 ---------------- */

  /* 可进入的建筑：街道上的建筑 id 与室内 id 同名。
     点中建筑时先弹单词卡，卡上给一个「推门进去」的按钮；
     也可以直接点门口的提示条进去。 */

  function isEnterable(id) {
    return !!(window.WordCityScene && window.WordCityScene.hasInterior &&
      window.WordCityScene.hasInterior(id));
  }

  function enterInterior(id, immediate) {
    if (!isEnterable(id)) {
      toast('这栋楼还没有开放内部哦');
      return false;
    }
    if (window.WordCityHunt && window.WordCityHunt.isActive()) {
      toast('先退出寻宝再进去逛吧');
      return false;
    }
    closeVocab();
    closeCard();
    hideEnterTip();

    interior.savedZone = state.currentZone;
    var ok = window.WordCityScene.enterInterior(id, !!immediate);
    if (!ok) { return false; }
    interior.inside = true;
    interior.id = id;

    var def = window.WordCityInterior.getDef(id);
    document.body.classList.add('is-indoor');
    if (els.interiorBar) {
      els.interiorBar.hidden = false;
      if (els.interiorTitle) { els.interiorTitle.textContent = def ? def.name : '室内'; }
    }
    // 室内词才 3~4 个，标签开着反而好找，直接打开
    setLabels(true, false);
    // 把词汇表的可点范围切到室内
    refreshVocabScope();
    return true;
  }

  function exitInterior() {
    if (!interior.inside) { return false; }
    closeCard();
    window.WordCityScene.exitInterior();
    interior.inside = false;
    interior.id = null;
    document.body.classList.remove('is-indoor');
    if (els.interiorBar) { els.interiorBar.hidden = true; }
    refreshVocabScope();
    return true;
  }

  /* 词汇表在室内只列这间屋子的词；在街上不列室内词 */
  function refreshVocabScope() {
    if (typeof buildVocab === 'function') { buildVocab(); }
  }

  function showEnterTip(id) {
    if (!els.enterTip || interior.inside) { return; }
    var def = window.WordCityInterior ? window.WordCityInterior.getDef(id) : null;
    if (!def) { hideEnterTip(); return; }
    els.enterTip.hidden = false;
    els.enterTip.dataset.target = id;
    if (els.enterName) { els.enterName.textContent = def.name; }
    if (els.enterLabel) { els.enterLabel.textContent = '推门进去看看'; }
  }

  function hideEnterTip() {
    if (!els.enterTip) { return; }
    els.enterTip.hidden = true;
    els.enterTip.dataset.target = '';
  }

  function bindInterior() {
    if (els.enterBtn) {
      els.enterBtn.addEventListener('click', function () {
        var id = els.enterTip ? els.enterTip.dataset.target : '';
        if (id) { enterInterior(id); }
      });
    }
    if (els.interiorBack) {
      els.interiorBack.addEventListener('click', function () { exitInterior(); });
    }
    // 单词卡上的「推门进去」
    if (els.wcEnter) {
      els.wcEnter.addEventListener('click', function () {
        var id = els.wcEnter.dataset.target;
        if (id) { enterInterior(id); }
      });
    }
    // Esc 退出室内
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Escape') { return; }
      if (interior.inside) {
        e.preventDefault();
        exitInterior();
      }
    });
  }

  /* ---------------- 单词寻宝 ---------------- */

  function huntActive() {
    return !!(window.WordCityHunt && window.WordCityHunt.isActive && window.WordCityHunt.isActive());
  }

  // 进寻宝前把界面收拾干净：关卡片、关词表、记下标签开关再关掉
  var huntPrevLabels = null;

  function enterHuntMode() {
    if (!window.WordCityHunt) { return false; }
    if (!sceneReady) { toast('小城还在搭建，稍等一下'); return false; }
    closeVocab();
    closeCard();
    if (state.tourOn) { setTour(false, false); }
    huntPrevLabels = state.labelsOn;
    // 英文标签会把答案直接写在墙上，进游戏必须关掉
    setLabels(false, false);

    var ok = window.WordCityHunt.start();
    if (ok) {
      if (els.btnHunt) { els.btnHunt.classList.add('is-on'); }
      hideHint();
    }
    return ok;
  }

  function exitHuntMode() {
    if (els.btnHunt) { els.btnHunt.classList.remove('is-on'); }
    if (huntPrevLabels !== null) {
      setLabels(huntPrevLabels, false);
      huntPrevLabels = null;
    }
  }

  function bindHunt() {
    if (!window.WordCityHunt) { return; }
    window.WordCityHunt.init({
      data: D,
      scene: {
        setHuntTarget: function (id, strength) {
          if (sceneReady && S.setHuntTarget) { S.setHuntTarget(id, strength); }
        },
        burstAt: function (id) { if (sceneReady && S.burstAt) { S.burstAt(id); } },
        setView: function (id, immediate) { if (sceneReady) { S.setView(id, immediate); } },
        getWordScreenPos: function (id) { return sceneReady && S.getWordScreenPos ? S.getWordScreenPos(id) : null; },
        distanceToWord: function (id) { return sceneReady && S.distanceToWord ? S.distanceToWord(id) : Infinity; }
      },
      toast: toast,
      openWord: function (id) { openWord(id); },
      onEnter: function () { /* 已由 enterHuntMode 处理 */ },
      onExit: exitHuntMode
    });
    if (els.btnHunt) {
      els.btnHunt.addEventListener('click', function () {
        if (huntActive()) {
          window.WordCityHunt.stop(false);
        } else {
          enterHuntMode();
        }
      });
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
    // ?onboard=0 用于截图 / 嵌入演示，直接跳过新手引导
    try {
      if (/(?:^|[?&])onboard=0(?:&|$)/.test(window.location.search)) {
        els.onboarding.hidden = true;
        return;
      }
    } catch (err) { /* 忽略 */ }
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

  /* 深链参数：让「打开就是某个画面」成为可能
     ?hour=18.5     直接跳到某个时刻（0..24）
     ?flow=1        打开就播放时间流动
     ?weather=rain  天气：clear / rain / snow
     ?night=1       兼容旧参数，等于 ?hour=20.5
     ?zone=park_zone 直接飞到某个分区
     ?labels=0/1    英文标签开关
     ?select=tree   打开某个单词卡 */
  function applyDeepLink() {
    var q;
    try { q = new URLSearchParams(window.location.search); } catch (err) { return; }
    if (!q) { return; }
    var night = q.get('night');
    if (night === '1' || night === 'true') { setHour(20.5, false, true); }
    var hourParam = q.get('hour');
    if (hourParam !== null && hourParam !== '' && isFinite(parseFloat(hourParam))) {
      // 深链要直接落到那一刻，不走缓动（否则截图和分享链接的首帧都是错的）
      setHour(parseFloat(hourParam), false, true);
    }
    var w = q.get('weather');
    if (w === 'rain' || w === 'snow' || w === 'clear') {
      state.instantWeather = true;
      setWeather(w, false);
    }
    var flow = q.get('flow');
    if (flow === '1' || flow === 'true') { setTimeFlow(true, false); }
    // 直接进入寻宝：分享「来挑战一轮」的链接时用
    var huntQ = q.get('hunt');
    if (huntQ === '1' || huntQ === 'true') {
      window.setTimeout(function () { enterHuntMode(); }, 420);
    }
    // 直接进屋：?inside=supermarket，方便分享「超市里有什么」的链接
    var insideQ = q.get('inside');
    if (insideQ && window.WordCityScene && window.WordCityScene.hasInterior(insideQ)) {
      window.setTimeout(function () { enterInterior(insideQ, true); }, 500);
    }
    var labels = q.get('labels');
    if (labels === '1' || labels === 'true') { setLabels(true, false); }
    else if (labels === '0' || labels === 'false') { setLabels(false, false); }
    var zone = q.get('zone');
    if (zone && zoneById[zone] && zone !== state.currentZone) {
      state.currentZone = zone;
      syncZoneTabs();
      if (sceneReady) { S.setView(zone, true); }
    }
    var sel = q.get('select');
    if (sel && byId[sel]) {
      window.setTimeout(function () { openWord(sel, { silentFocus: true }); }, 260);
    }
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

    /* 时间轴：拖动即时生效，松手才提示 */
    if (els.hourRange) {
      els.hourRange.addEventListener('input', function () {
        setHour(parseFloat(els.hourRange.value), false);
      });
      els.hourRange.addEventListener('change', function () {
        var h = parseFloat(els.hourRange.value);
        setHour(h, false);
        if (state.timeFlow) { setTimeFlow(false, false); }
        toast('现在是 ' + (S.hourLabel ? S.hourLabel(h) : '') + ' · ' + phaseLabel(h));
        hideHint();
      });
    }
    if (els.btnTimeFlow) {
      els.btnTimeFlow.addEventListener('click', function () {
        setTimeFlow(!state.timeFlow, true);
      });
    }
    /* 天气三态 */
    var weatherBtns = document.querySelectorAll('.weather-btn');
    for (var wi2 = 0; wi2 < weatherBtns.length; wi2++) {
      weatherBtns[wi2].addEventListener('click', function () {
        setWeather(this.getAttribute('data-weather'), true);
      });
    }
    if (els.btnTour) {
      els.btnTour.addEventListener('click', function () {
        setTour(!state.tourOn, true);
      });
    }
    els.btnReset.addEventListener('click', function () {
      if (state.tourOn) { setTour(false, false); }
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
    // 巡游时用户一旦手动操作画面，立刻同步按钮状态
    ['pointerdown', 'wheel', 'dblclick'].forEach(function (evt) {
      els.view.addEventListener(evt, function () {
        window.setTimeout(syncTourUI, 0);
      }, { passive: true });
    });
    window.setInterval(syncTourUI, 400);
    // 时间流动 / 缓动时，UI 时钟与滑块的 CSS 变量要跟着场景走
    window.setInterval(function () {
      if (!sceneReady || !S.getHour) { return; }
      var h = S.getHour();
      if (Math.abs(h - lastPushedHour) < 0.004) { return; }
      lastPushedHour = h;
      state.hour = h;
      syncSkyUI(h);
    }, 120);
    bindHunt();
    bindInterior();
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
          // 寻宝进行中：点击交给游戏判定，不弹单词卡
          if (huntActive() && window.WordCityHunt.handlePick(id)) { return; }
          if (!id) {
            closeCard();
            hideEnterTip();
          } else {
            openWord(id);
            // 点中可进入的建筑时，门口给一个更明显的「推门」提示
            if (isEnterable(id) && !interior.inside) { showEnterTip(id); }
            else { hideEnterTip(); }
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
    state.completeOnLoad = state.discovered.size === allWords.length;
    updateAllDots();
    refreshAllVocab();
    updateCounts();
    updatePeek();
    syncZoneTabs();
    setLabels(state.labelsOn, false);

    bindUI();
    initScene();
    setHour(state.hour, false);
    setWeather(state.weather, false);
    maybeShowOnboarding();

    if (els.btnLabels) {
      els.btnLabels.setAttribute('aria-pressed', state.labelsOn ? 'true' : 'false');
    }

    window.WordCityApp = {
      select: function (id) { openWord(id); },
      setLabels: function (on) { setLabels(!!on, false); },
      // 旧接口保留：宿主原生夜灯按钮仍调用它
      setNight: function (on) { setNight(!!on, false); },
      setView: function (id) { setZone(id); },
      // 时间与天气
      setHour: function (h) { setHour(h, false); },
      getHour: function () { return S.getHour ? S.getHour() : state.hour; },
      setTimeFlow: function (on) { setTimeFlow(!!on, false); },
      isTimeFlowing: function () { return state.timeFlow; },
      setWeather: function (kind) { setWeather(kind, false); },
      getWeather: function () { return state.weather; },
      // 单词寻宝
      startHunt: function (zone) { return enterHuntMode(); },
      stopHunt: function () { if (window.WordCityHunt) { window.WordCityHunt.stop(true); } exitHuntMode(); },
      isHunting: function () { return huntActive(); },
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

    // 深链参数：?night=1 直接进黄昏夜灯，?zone=park_zone 直接飞到某个分区，
    // ?labels=0/1 控制英文标签，?select=tree 直接打开某个单词卡。
    // 宿主或分享链接都可用，参数非法时静默忽略。
    applyDeepLink();

    if (state.discovered.size === allWords.length) {
      els.badgeCard.hidden = false;
    }
    console.info('[WordCity] 小词城已就绪：' + allWords.length + ' 个单词（街道 ' + D.objects.length + ' + 室内 ' + (D.indoorObjects || []).length + '）。');
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
