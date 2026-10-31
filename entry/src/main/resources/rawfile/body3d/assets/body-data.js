/* 小星英语 · 3D 身体课：25 个身体部位的数据源。
 * 原生侧白名单在 utils/Body3DValidation.ets，两处必须同步（单测断言 25 条）。 */
(function () {
  'use strict';

  const PARTS = [
    { id: 'head', en: 'head', cn: '头', ipa: '/hed/', grp: 'head', kind: 'single', desc: '小星的脑袋圆圆的，里面装着好多英语单词。' },
    { id: 'hair', en: 'hair', cn: '头发', ipa: '/heə(r)/', grp: 'head', kind: 'single', desc: '头上一撮卷卷的头发，摸一摸。' },
    { id: 'face', en: 'face', cn: '脸', ipa: '/feɪs/', grp: 'head', kind: 'single', desc: '脸上有眼睛、鼻子和嘴巴。' },
    { id: 'ear', en: 'ears', cn: '耳朵', ipa: '/ɪəz/', once: 'ear', grp: 'head', kind: 'pair', desc: '两只大耳朵，听得见老师说的英语。' },
    { id: 'eye', en: 'eyes', cn: '眼睛', ipa: '/aɪz/', once: 'eye', grp: 'head', kind: 'pair', desc: '亮晶晶的眼睛，还会眨一眨。' },
    { id: 'nose', en: 'nose', cn: '鼻子', ipa: '/nəʊz/', grp: 'head', kind: 'single', desc: '小鼻子闻一闻花香。' },
    { id: 'mouth', en: 'mouth', cn: '嘴巴', ipa: '/maʊθ/', grp: 'head', kind: 'single', desc: '张大嘴巴，一起说英语。' },
    { id: 'teeth', en: 'teeth', cn: '牙齿', ipa: '/tiːθ/', grp: 'head', kind: 'multi', desc: '洁白的小牙齿，每天早晚都要刷。' },
    { id: 'neck', en: 'neck', cn: '脖子', ipa: '/nek/', grp: 'body', kind: 'single', desc: '转一转脖子，看看身后。' },
    { id: 'shoulder', en: 'shoulders', cn: '肩膀', ipa: '/ˈʃəʊldəz/', once: 'shoulder', grp: 'body', kind: 'pair', desc: '耸一耸肩膀，放松一下。' },
    { id: 'arm', en: 'arms', cn: '手臂', ipa: '/ɑːmz/', once: 'arm', grp: 'body', kind: 'pair', desc: '小星用手臂跟你挥手说 hello。' },
    { id: 'elbow', en: 'elbows', cn: '手肘', ipa: '/ˈelbəʊz/', once: 'elbow', grp: 'body', kind: 'pair', desc: '弯一弯手肘，像在打招呼。' },
    { id: 'hand', en: 'hands', cn: '手', ipa: '/hændz/', once: 'hand', grp: 'body', kind: 'pair', desc: '举起手，告诉老师答案。' },
    { id: 'finger', en: 'fingers', cn: '手指', ipa: '/ˈfɪŋɡəz/', grp: 'body', kind: 'multi', desc: '数一数，一只手有五根手指。' },
    { id: 'thumb', en: 'thumb', cn: '大拇指', ipa: '/θʌm/', grp: 'body', kind: 'single', desc: '竖一个大拇指，说 Very good！' },
    { id: 'chest', en: 'chest', cn: '胸口', ipa: '/tʃest/', grp: 'body', kind: 'single', desc: '摸摸胸口，能感觉到心跳。' },
    { id: 'belly', en: 'belly', cn: '肚子', ipa: '/ˈbeli/', grp: 'body', kind: 'single', desc: '圆圆的小肚子。' },
    { id: 'back', en: 'back', cn: '后背', ipa: '/bæk/', grp: 'body', kind: 'single', desc: '转过身去，看看小星的后背。' },
    { id: 'leg', en: 'legs', cn: '腿', ipa: '/leɡz/', once: 'leg', grp: 'leg', kind: 'pair', desc: '两条腿站得稳稳的。' },
    { id: 'knee', en: 'knees', cn: '膝盖', ipa: '/niːz/', once: 'knee', grp: 'leg', kind: 'pair', desc: '膝盖弯一弯，就能蹲下来。' },
    { id: 'foot', en: 'feet', cn: '脚', ipa: '/fiːt/', once: 'foot', grp: 'leg', kind: 'pair', desc: '两只小脚穿好鞋子来上课。' },
    { id: 'toe', en: 'toes', cn: '脚趾', ipa: '/təʊz/', grp: 'leg', kind: 'multi', desc: '动一动脚趾，痒痒的。' },
    { id: 'body', en: 'body', cn: '身体', ipa: '/ˈbɒdi/', grp: 'whole', kind: 'single', desc: '这就是小星的身体，从上到下都有名字。' },
    { id: 'skin', en: 'skin', cn: '皮肤', ipa: '/skɪn/', grp: 'whole', kind: 'single', desc: '软软的皮肤，保护着我们的身体。' },
    { id: 'tummy', en: 'belly button', cn: '肚脐', ipa: '/ˈbeli ˈbʌtn/', grp: 'whole', kind: 'single', desc: '肚脐也叫 belly button，你也有一个。' }
  ];

  const PART_BY_ID = {};
  PARTS.forEach(function (part) { PART_BY_ID[part.id] = part; });

  const GROUPS = [
    { key: 'head', zh: '头部', en: 'Head' },
    { key: 'body', zh: '身体', en: 'Body' },
    { key: 'leg', zh: '下肢', en: 'Legs' },
    { key: 'whole', zh: '整体', en: 'Whole' }
  ];

  /* 环形指示点：贴在小星身体上的定位标记，不压住画面主体。 */
  const GUIDE = {
    hair: [[0, 4.3, 0.06], [0.318, 4.18, 0.2], [-0.318, 4.18, 0.2], [-0.61, 3.92, 0.16]],
    head: [[-0.5, 3.18, 0.42], [0.5, 3.18, 0.42], [0, 4.0, 0.1]],
    face: [[-0.3, 3.42, 0.66], [0.3, 3.42, 0.66]],
    ear: [[0.735, 3.32, 0.02], [0.66, 3.16, 0.1]],
    eye: [[-0.25, 3.44, 0.74], [0.25, 3.44, 0.74]],
    nose: [[-0.1, 3.32, 0.86], [0.1, 3.32, 0.86]],
    mouth: [[-0.16, 3.1, 0.82], [0.16, 3.1, 0.82]],
    teeth: [[-0.07, 3.09, 0.9], [0.07, 3.09, 0.9]],
    neck: [[-0.19, 2.62, 0.24], [0.19, 2.62, 0.24]],
    shoulder: [[0.6, 2.36, 0.24], [0.78, 2.2, 0.22]],
    arm: [[0.78, 1.98, 0.1], [0.8, 1.6, 0.12]],
    elbow: [[0.74, 1.98, 0.14], [0.82, 1.84, 0.18]],
    hand: [[0.84, 0.72, 0.18], [0.9, 0.98, 0.2]],
    finger: [[0.86, 0.5, 0.16], [0.92, 0.66, 0.2]],
    thumb: [[0.68, 0.92, 0.24], [0.82, 1.02, 0.24]],
    chest: [[-0.22, 1.98, 0.58], [0.22, 1.98, 0.58]],
    belly: [[-0.2, 1.44, 0.58], [0.2, 1.44, 0.58]],
    tummy: [[0, 1.36, 0.72]],
    back: [[-0.45, 2.0, -0.45], [0.45, 2.0, -0.45]],
    skin: [[0.55, 3.74, 0.36], [0.45, 3.86, 0.3]],
    body: [[-0.5, 2.16, 0.38], [0.5, 2.16, 0.38], [0, 1.6, -0.52]],
    leg: [[0.3, 0.72, 0.15], [0.3, 0.46, 0.15]],
    knee: [[0.26, 0.62, 0.22], [0.3, 0.5, 0.24]],
    foot: [[0.3, 0.2, 0.4], [0.4, 0.16, 0.36]],
    toe: [[0.22, 0.12, 0.44], [0.4, 0.1, 0.42]]
  };

  /* 部位热区（世界坐标，角色根位于 y=0）。 */
  const HIT = {
    hair: { c: [0, 3.92, -0.02], r: 0.42 },
    head: { c: [0, 3.4, 0.0], r: 0.6 },
    face: { c: [0, 3.26, 1.12], r: 0.46 },
    ear: { c: [0.76, 3.3, -0.02], r: 0.3 },
    eye: { c: [0.25, 3.43, 0.98], r: 0.4 },
    nose: { c: [0, 3.28, 1.1], r: 0.26 },
    mouth: { c: [0, 3.06, 1.02], r: 0.34 },
    teeth: { c: [0, 3.07, 1.14], r: 0.22 },
    neck: { c: [0, 2.62, 0.0], r: 0.34 },
    shoulder: { c: [0.86, 2.28, 0], r: 0.34 },
    arm: { c: [1.1, 1.66, 0], r: 0.36 },
    elbow: { c: [1.06, 1.9, 0], r: 0.24 },
    hand: { c: [1.18, 0.88, 0.04], r: 0.32 },
    finger: { c: [1.18, 0.6, 0.04], r: 0.24 },
    thumb: { c: [0.95, 0.92, 0.2], r: 0.17 },
    chest: { c: [0, 1.86, 0.7], r: 0.38 },
    belly: { c: [0, 1.62, 0.34], r: 0.34 },
    tummy: { c: [0, 1.32, 0.44], r: 0.2 },
    back: { c: [0, 1.72, -0.66], r: 0.5 },
    skin: { c: [0.3, 3.5, 0.6], r: 0.2 },
    body: { c: [0, 1.5, 0], r: 0.9 },
    leg: { c: [0.34, 0.6, 0], r: 0.3 },
    knee: { c: [0.34, 0.82, 0.2], r: 0.22 },
    foot: { c: [0.34, 0.12, 0.28], r: 0.26 },
    toe: { c: [0, 0.17, 0.7], r: 0.26 }
  };

  /* 部位图上的标签（14 个代表部位，其余在单词表里点）。 */
  const MAP_LABELS = [
    { id: 'hair', side: 'l', foot: 10 }, { id: 'head', side: 'r', foot: 10 },
    { id: 'ear', side: 'l', foot: 12 }, { id: 'eye', side: 'l', foot: 34 },
    { id: 'mouth', side: 'l', foot: 58 }, { id: 'nose', side: 'r', foot: 34 },
    { id: 'neck', side: 'r', foot: 52 }, { id: 'chest', side: 'l', foot: 40 },
    { id: 'belly', side: 'l', foot: 58 }, { id: 'arm', side: 'l', foot: 30 },
    { id: 'hand', side: 'l', foot: 14 }, { id: 'leg', side: 'l', foot: 30 },
    { id: 'knee', side: 'l', foot: 46 }, { id: 'foot', side: 'r', foot: 14 }
  ];

  function pluralCn(part) {
    if (part.kind === 'pair') return '两只' + part.cn;
    if (part.kind === 'multi') return '好多' + part.cn;
    return part.cn === '肚脐' ? '一个肚脐' : '一个' + part.cn;
  }

  function groupOf(focus) {
    if (focus === 'legs') return 'leg';
    return focus;
  }

  window.BodyClassData = {
    parts: PARTS,
    byId: PART_BY_ID,
    groups: GROUPS,
    guide: GUIDE,
    hit: HIT,
    mapLabels: MAP_LABELS,
    pluralCn: pluralCn,
    groupOf: groupOf
  };
})();
