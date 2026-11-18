/* ============================================================
   小词城 · 室内场景
   ------------------------------------------------------------
   在街道场景之内搭一间独立的房间：进入时把 street 整体隐藏，
   只显示这间屋子；退出时反过来。相机用街道那套轨道控制，
   只是换成室内的 target / radius。

   为什么不用「楼里挖空」的做法：
   - 现有建筑是一体成型的 box 拼出来的，挖空要重建几何、还要处理
     墙体碰撞和遮挡关系，成本远高于收益；
   - 独立房间能保证镜头永远看不到「房子背面没做完」的部分。

   依赖注入（由 city-scene.js 传入）：
     scene    THREE.Scene
     worldRoot  街道根节点（进出时整体显隐）
     tools    MD.tools（box / cyl / mat ...）
     register(id, node)  把某个物件登记为可点击的单词
   ============================================================ */
(function (global) {
  'use strict';

  var THREE = global.THREE;
  var D = global.WordCityData;
  var I = {};

  var ctx = null;
  var rooms = {};          // id -> { group, words, def }
  var current = null;      // 当前进入的室内 id
  var builtIds = {};       // 已构建过的室内，避免重复搭
  var rootGroup = null;    // 所有室内的共同父节点

  /* ---------------- 建模小工具 ---------------- */

  function mkTools(tools, parent) {
    /* 返回一组绑定了 parent 的快捷方法，让建模代码读起来短一些 */
    return {
      box: function (w, h, d, color, x, y, z, opts) {
        return tools.box(parent, w, h, d, color, x, y, z, opts);
      },
      cyl: function (rt, rb, h, seg, color, x, y, z, opts) {
        return tools.cyl(parent, rt, rb, h, seg, color, x, y, z, opts);
      },
      group: function (x, y, z) {
        var g = new THREE.Group();
        g.position.set(x || 0, y || 0, z || 0);
        parent.add(g);
        return g;
      },
      mat: tools.mat,
      shade: tools.shade
    };
  }

  /* ---------------- 通用：房间外壳与背景 ---------------- */

  /* 相机在室内时，镜头后方（+z 一侧）是敞开的，会直接看到街道天空，
     看起来像「屋顶被掀掉」。这里在相机身后补一块大的浅色挡板，
     只挡 +z 方向，不遮挡正面的视野。 */
  function addBackdrop(group, def, tools) {
    var W = def.w, Dz = def.d, H = def.h;
    var mat = new THREE.MeshLambertMaterial({ color: '#EFE7D7', side: THREE.DoubleSide });
    var wall = new THREE.Mesh(new THREE.PlaneGeometry(W + 12, H + 6), mat);
    wall.position.set(0, H / 2 + 1, Dz / 2 + 3.5);
    wall.rotation.y = Math.PI;   // 面朝屋内
    group.add(wall);
    return wall;
  }

  /* ---------------- 超市 ---------------- */

  function buildSupermarket(def, tools) {
    var group = new THREE.Group();
    group.visible = false;
    var b = mkTools(tools, group);
    var W = def.w, Dz = def.d, H = def.h;
    var hw = W / 2, hd = Dz / 2;

    /* --- 房间壳：地板 / 天花板 / 三面墙（正面敞开，镜头从这里看） --- */
    // 地板：略微带一点木纹色块拼接感
    b.box(W, 0.3, Dz, def.floorColor, 0, -0.15, 0);
    // 地砖网格线，让它不像一块塑料板
    for (var gx = -hw + 2; gx < hw; gx += 4) {
      b.box(0.06, 0.02, Dz, b.shade(def.floorColor, -0.06), gx, 0.005, 0);
    }
    for (var gz = -hd + 2; gz < hd; gz += 4) {
      b.box(W, 0.02, 0.06, b.shade(def.floorColor, -0.06), 0, 0.005, gz);
    }
    // 天花板：向 +z 外延伸一段，盖住相机上方的视野，否则会看到街道天空
    b.box(W + 4, 0.3, Dz + 14, '#FBF7EE', 0, H + 0.15, 3);
    // 后墙 + 左右墙
    b.box(W, H, 0.4, def.wallColor, 0, H / 2, -hd);
    // 镜头身后补一块挡板，避免从门口看到街道天空
    addBackdrop(group, def, tools);
    b.box(0.4, H, Dz, def.wallColor, -hw, H / 2, 0);
    b.box(0.4, H, Dz, def.wallColor, hw, H / 2, 0);
    // 后墙下半段刷一条品牌色护墙板
    b.box(W - 0.8, 0.9, 0.08, def.accent, 0, 0.46, -hd + 0.24);
    b.box(W - 0.8, 0.12, 0.1, b.shade(def.accent, -0.18), 0, 0.94, -hd + 0.24);

    /* --- 天花板灯带：两条长条灯，室内主要光源感 --- */
    var lampMat = new THREE.MeshBasicMaterial({ color: '#FFFBF0' });
    var lampFrameMat = tools.mat('#B9B0A0');
    [-3.6, 3.6].forEach(function (lz) {
      var fixture = new THREE.Mesh(new THREE.BoxGeometry(W * 0.62, 0.16, 0.8), lampFrameMat);
      fixture.position.set(0, H - 0.16, lz);
      group.add(fixture);
      var tube = new THREE.Mesh(new THREE.BoxGeometry(W * 0.58, 0.08, 0.6), lampMat);
      tube.position.set(0, H - 0.26, lz);
      group.add(tube);
    });

    /* --- 货架（word: shelf）：靠后墙三组，中间两组 --- */
    function shelfUnit(x, z, wid, rotY) {
      var g = new THREE.Group();
      g.position.set(x, 0, z);
      g.rotation.y = rotY || 0;
      var t = mkTools(tools, g);
      var shelfH = 2.2;
      var depth = 1.5;
      // 侧板 + 背板
      t.box(0.12, shelfH, depth, '#C9B79A', -wid / 2, shelfH / 2, 0);
      t.box(0.12, shelfH, depth, '#C9B79A', wid / 2, shelfH / 2, 0);
      t.box(wid, shelfH, 0.1, '#E6DCC8', 0, shelfH / 2, -depth / 2 + 0.05);
      // 四层隔板 + 商品
      var levels = [0.18, 0.72, 1.26, 1.8];
      var goodsColors = ['#E5484D', '#F2C14E', '#7ECB6A', '#6FA8DC', '#F2826A', '#C3A6F5'];
      levels.forEach(function (y, li) {
        t.box(wid, 0.08, depth, '#D9C9AC', 0, y, 0, { cast: true });
        // 每层摆一排商品：小方块 + 偶尔圆罐
        var count = Math.max(3, Math.floor(wid / 0.85));
        for (var i = 0; i < count; i++) {
          var cx = -wid / 2 + 0.5 + i * (wid - 1) / Math.max(1, count - 1);
          var color = goodsColors[(i + li) % goodsColors.length];
          if ((i + li) % 3 === 0) {
            t.cyl(0.16, 0.16, 0.42, 8, color, cx, y + 0.25, 0.1);
          } else {
            t.box(0.34, 0.42, 0.34, color, cx, y + 0.25, 0.1);
          }
        }
      });
      group.add(g);
      return g;
    }

    // 后墙一整排（三组），作为 shelf 单词的可点击对象
    var backShelf = shelfUnit(0, -hd + 0.95, 6.2, 0);
    var backShelf2 = shelfUnit(-7.2, -hd + 0.95, 4.4, 0);
    var backShelf3 = shelfUnit(7.2, -hd + 0.95, 4.0, 0);
    // 中间两组双面货架（岛柜）
    shelfUnit(-3.2, -2.2, 5.0, 0);
    shelfUnit(3.2, -2.2, 5.0, 0);

    /* --- 冷柜：靠左墙 --- */
    (function freezer() {
      var g = new THREE.Group();
      g.position.set(-hw + 1.6, 0, -1.5);
      var t = mkTools(tools, g);
      t.box(1.8, 1.3, 5.4, '#EDF4F7', 0, 0.65, 0, { cast: true });
      t.box(1.86, 0.12, 5.5, '#CFDDE4', 0, 1.34, 0);
      // 玻璃门
      var glass = new THREE.Mesh(
        new THREE.BoxGeometry(0.06, 1.0, 4.8),
        new THREE.MeshLambertMaterial({ color: '#BFE3EF', transparent: true, opacity: 0.32 })
      );
      glass.position.set(0.94, 0.72, 0);
      g.add(glass);
      // 里面几盒牛奶
      for (var i = 0; i < 5; i++) {
        t.box(0.3, 0.4, 0.3, i % 2 ? '#FFFFFF' : '#E8F2FA', 0.3, 0.95, -2 + i * 1.0);
      }
      group.add(g);
    })();

    /* --- 收银台（word: cashier） --- */
    var counter = new THREE.Group();
    counter.position.set(6.2, 0, hd - 2.6);
    var ct = mkTools(tools, counter);
    ct.box(7.0, 1.05, 1.5, '#D9C9AC', 0, 0.52, 0, { cast: true });
    ct.box(7.1, 0.1, 1.62, '#BFAE8D', 0, 1.09, 0);
    // 收银机
    ct.box(0.9, 0.6, 0.7, '#5A6470', -1.4, 1.42, 0);
    ct.box(0.62, 0.12, 0.5, '#8CE0A8', -1.4, 1.78, 0.06);
    // 扫码枪、小票打印机
    ct.box(0.18, 0.3, 0.18, '#33302C', -0.7, 1.28, -0.3);
    ct.box(0.5, 0.32, 0.4, '#EDEAE2', 0.4, 1.3, 0);
    // 收银员（站姿小人）
    var cashier = buildShopkeeper(tools, '#E5484D');
    cashier.position.set(-1.4, 0, -0.9);
    cashier.rotation.y = Math.PI;
    counter.add(cashier);
    group.add(counter);

    /* --- 购物车（word: cart）：入口处一排 --- */
    function shoppingCart(x, z, rotY) {
      var g = new THREE.Group();
      g.position.set(x, 0, z);
      g.rotation.y = rotY || 0;
      var t = mkTools(tools, g);
      // 车篮：用几根横杆拼出网格感
      var basketMat = '#B9C0C9';
      t.box(0.78, 0.06, 1.1, basketMat, 0, 0.86, 0);
      t.box(0.78, 0.5, 0.06, basketMat, 0, 0.62, 0.55);
      t.box(0.78, 0.5, 0.06, basketMat, 0, 0.62, -0.55);
      t.box(0.06, 0.5, 1.1, basketMat, 0.39, 0.62, 0);
      t.box(0.06, 0.5, 1.1, basketMat, -0.39, 0.62, 0);
      // 底部
      t.box(0.78, 0.06, 1.1, '#9AA3AD', 0, 0.38, 0);
      // 推手
      t.box(0.06, 0.06, 0.7, '#8A94A0', 0, 1.02, 0.85, { rx: 0.5 });
      t.box(0.5, 0.06, 0.06, '#8A94A0', 0, 1.2, 1.06);
      // 四个轮子
      [[-0.32, 0.4], [0.32, 0.4], [-0.32, -0.4], [0.32, -0.4]].forEach(function (p) {
        t.cyl(0.1, 0.1, 0.06, 8, '#33302C', p[0], 0.11, p[1], { rz: Math.PI / 2 });
      });
      // 车里放点东西
      t.box(0.3, 0.26, 0.3, '#F2C14E', -0.14, 0.54, -0.2);
      t.box(0.26, 0.32, 0.26, '#7ECB6A', 0.16, 0.56, 0.14);
      group.add(g);
      return g;
    }
    var cartGroup = new THREE.Group();
    cartGroup.position.set(-7.0, 0, hd - 3.0);
    group.add(cartGroup);
    var c1 = shoppingCart(0, 0, 0); cartGroup.add(c1);
    cartGroup.add(shoppingCart(-0.95, 0.1, 0.06));
    cartGroup.add(shoppingCart(-1.9, 0.2, -0.05));

    /* --- 购物篮（word: basket）：堆在入口右侧 --- */
    var basketGroup = new THREE.Group();
    basketGroup.position.set(1.2, 0, hd - 3.2);
    (function buildBaskets() {
      var t = mkTools(tools, basketGroup);
      for (var i = 0; i < 3; i++) {
        var y = 0.2 + i * 0.26;
        t.box(0.9, 0.24, 0.62, i % 2 ? '#E5484D' : '#C93F44', 0, y, 0);
        t.box(0.96, 0.05, 0.68, '#F2F2F2', 0, y + 0.13, 0);
      }
    })();
    group.add(basketGroup);

    /* --- 门口地垫（不加门框：相机就在这个位置，门柱会挡住整个镜头） --- */
    b.box(3.6, 0.06, 1.2, '#8C9BA5', 0, 0.03, hd - 1.2);

    /* --- 挂在天花板上的指示牌 --- */
    var signMat = new THREE.MeshBasicMaterial({ color: '#E5484D' });
    var sign = new THREE.Mesh(new THREE.BoxGeometry(3.4, 0.7, 0.1), signMat);
    sign.position.set(6.2, H - 1.1, hd - 2.6);
    group.add(sign);

    return {
      group: group,
      words: {
        shelf: backShelf,
        cashier: counter,
        cart: c1,
        basket: basketGroup
      }
    };
  }

  /* ---------------- 图书馆 ---------------- */

  function buildLibrary(def, tools) {
    var group = new THREE.Group();
    group.visible = false;
    var b = mkTools(tools, group);
    var W = def.w, Dz = def.d, H = def.h;
    var hw = W / 2, hd = Dz / 2;

    /* --- 房间壳 --- */
    b.box(W, 0.3, Dz, def.floorColor, 0, -0.15, 0);
    // 木地板长条
    for (var gz = -hd + 0.8; gz < hd; gz += 1.1) {
      b.box(W, 0.02, 0.05, b.shade(def.floorColor, -0.07), 0, 0.006, gz);
    }
    b.box(W, 0.3, Dz, '#FBF7EE', 0, H + 0.15, 0);
    b.box(W, H, 0.4, def.wallColor, 0, H / 2, -hd);
    b.box(0.4, H, Dz, def.wallColor, -hw, H / 2, 0);
    b.box(0.4, H, Dz, def.wallColor, hw, H / 2, 0);
    // 镜头身后补一块挡板
    addBackdrop(group, def, tools);
    // 深色木护墙板
    b.box(W - 0.8, 1.1, 0.08, '#B08D62', 0, 0.56, -hd + 0.24);

    /* --- 书架（word: bookshelf）：后墙 + 左右两侧 --- */
    function bookShelf(x, z, wid, rotY, levels) {
      var g = new THREE.Group();
      g.position.set(x, 0, z);
      g.rotation.y = rotY || 0;
      var t = mkTools(tools, g);
      var shelfH = 2.9, depth = 1.0;
      t.box(0.14, shelfH, depth, '#9C7A52', -wid / 2, shelfH / 2, 0);
      t.box(0.14, shelfH, depth, '#9C7A52', wid / 2, shelfH / 2, 0);
      t.box(wid, shelfH, 0.1, '#C8A87C', 0, shelfH / 2, -depth / 2 + 0.05);
      // 顶板压条
      t.box(wid + 0.3, 0.12, depth + 0.15, '#8A6A46', 0, shelfH + 0.04, 0);
      var hs = levels || [0.16, 0.76, 1.36, 1.96, 2.56];
      var bookColors = ['#C0392B', '#2E6DA4', '#3E8E5A', '#B7602F', '#6B4E9E', '#C99A2E', '#2F7E8C'];
      hs.forEach(function (y, li) {
        t.box(wid, 0.08, depth, '#D6B88E', 0, y, 0, { cast: true });
        // 一排书：竖着立起来的小方片，宽窄错落
        var x2 = -wid / 2 + 0.35;
        var bi = 0;
        while (x2 < wid / 2 - 0.35) {
          var bw = 0.1 + ((bi * 7 + li * 3) % 5) * 0.035;
          var bh = 0.34 + ((bi * 11 + li * 5) % 6) * 0.045;
          t.box(bw, bh, 0.62, bookColors[(bi + li * 3) % bookColors.length],
            x2 + bw / 2, y + 0.04 + bh / 2, 0.06);
          x2 += bw + 0.035;
          bi++;
        }
      });
      group.add(g);
      return g;
    }

    var mainShelf = bookShelf(-2.6, -hd + 0.7, 7.0, 0);
    bookShelf(5.4, -hd + 0.7, 4.6, 0);
    // 左墙书架（旋转 90°）
    bookShelf(-hw + 0.7, -3.2, 6.0, Math.PI / 2);
    bookShelf(-hw + 0.7, 4.2, 4.2, Math.PI / 2);
    // 右侧靠墙书架
    bookShelf(hw - 0.7, -1.0, 7.4, -Math.PI / 2);

    /* --- 阅读区：书桌 + 椅子 + 台灯 --- */
    function readingDesk(x, z, rotY) {
      var g = new THREE.Group();
      g.position.set(x, 0, z);
      g.rotation.y = rotY || 0;
      var t = mkTools(tools, g);
      // 桌面
      t.box(2.4, 0.1, 1.1, '#C9A87C', 0, 0.76, 0, { cast: true });
      // 四条腿
      [[-1.05, -0.42], [1.05, -0.42], [-1.05, 0.42], [1.05, 0.42]].forEach(function (p) {
        t.box(0.1, 0.76, 0.1, '#8A6A46', p[0], 0.38, p[1]);
      });
      // 桌上摊开的书
      t.box(0.62, 0.06, 0.46, '#F6F1E4', -0.5, 0.84, 0.06, { ry: 0.2 });
      t.box(0.6, 0.05, 0.44, '#E8DFC8', -0.5, 0.89, 0.06, { ry: 0.2 });
      // 台灯
      t.cyl(0.14, 0.18, 0.05, 10, '#3E4E5C', 0.75, 0.83, -0.2);
      t.cyl(0.03, 0.03, 0.5, 6, '#3E4E5C', 0.75, 1.1, -0.2);
      var shadeMesh = new THREE.Mesh(
        new THREE.ConeGeometry(0.26, 0.28, 10, 1, true),
        new THREE.MeshLambertMaterial({ color: '#F2C14E', side: THREE.DoubleSide })
      );
      shadeMesh.position.set(0.75, 1.42, -0.2);
      shadeMesh.rotation.x = Math.PI;
      g.add(shadeMesh);
      // 椅子
      var chair = new THREE.Group();
      chair.position.set(0, 0, 1.0);
      var ch = mkTools(tools, chair);
      ch.box(0.62, 0.08, 0.6, '#B08D62', 0, 0.46, 0);
      ch.box(0.62, 0.62, 0.08, '#B08D62', 0, 0.75, -0.26);
      [[-0.26, -0.24], [0.26, -0.24], [-0.26, 0.24], [0.26, 0.24]].forEach(function (p) {
        ch.box(0.07, 0.46, 0.07, '#8A6A46', p[0], 0.23, p[1]);
      });
      g.add(chair);
      group.add(g);
      return g;
    }

    var desk1 = readingDesk(-4.6, 3.4, 0.1);
    readingDesk(4.4, 3.6, -0.12);

    /* --- 地毯 --- */
    var rug = new THREE.Mesh(
      new THREE.CylinderGeometry(3.6, 3.6, 0.04, 32),
      tools.mat('#8E6E52')
    );
    rug.position.set(0, 0.03, 4.2);
    group.add(rug);
    var rugInner = new THREE.Mesh(
      new THREE.CylinderGeometry(2.9, 2.9, 0.05, 32),
      tools.mat('#A8866A')
    );
    rugInner.position.set(0, 0.045, 4.2);
    group.add(rugInner);

    /* --- 图书管理员（word: librarian）：站在借阅台后 --- */
    var counter = new THREE.Group();
    counter.position.set(-6.4, 0, -1.2);
    var ct = mkTools(tools, counter);
    ct.box(4.6, 1.1, 1.2, '#A8825A', 0, 0.55, 0, { cast: true });
    ct.box(4.7, 0.1, 1.3, '#C9A87C', 0, 1.14, 0);
    // 台面上的书堆
    ct.box(0.7, 0.1, 0.5, '#C0392B', -1.2, 1.24, 0);
    ct.box(0.66, 0.09, 0.46, '#2E6DA4', -1.2, 1.34, 0.02, { ry: 0.15 });
    ct.box(0.6, 0.08, 0.44, '#3E8E5A', -1.2, 1.43, -0.02, { ry: -0.1 });
    // 借书卡盒
    ct.box(0.5, 0.16, 0.34, '#E8DFC8', 0.6, 1.27, 0);
    var libr = buildShopkeeper(tools, '#2E6DA4');
    libr.position.set(0.4, 0, -0.9);
    libr.rotation.y = 0;
    counter.add(libr);
    group.add(counter);

    /* --- 阅读提示牌 / 挂钟 --- */
    (function clockOnWall() {
      var c = new THREE.Group();
      c.position.set(0, H - 0.9, -hd + 0.3);
      var t = mkTools(tools, c);
      t.cyl(0.42, 0.42, 0.08, 20, '#F6F1E4', 0, 0, 0, { rx: Math.PI / 2 });
      t.cyl(0.36, 0.36, 0.1, 20, '#FFFDF8', 0, 0, 0.02, { rx: Math.PI / 2 });
      t.box(0.04, 0.26, 0.03, '#33302C', 0, 0.1, 0.06);
      t.box(0.18, 0.04, 0.03, '#33302C', 0.07, 0, 0.06);
      group.add(c);
    })();

    /* --- 门口地垫（同样不加门框，避免挡住镜头） --- */
    b.box(3.2, 0.05, 1.0, '#9A7E5E', 0, 0.03, hd - 1.2);

    return {
      group: group,
      words: {
        bookshelf: mainShelf,
        desk: desk1,
        book: counter,        // 借阅台上的书堆，用固定点更容易点中
        librarian: libr
      }
    };
  }

  /* ---------------- 通用：店员/管理员小人 ---------------- */

  function buildShopkeeper(tools, shirtColor) {
    var g = new THREE.Group();
    var t = mkTools(tools, g);
    // 腿
    t.box(0.2, 0.72, 0.2, '#3E4E5C', -0.14, 0.36, 0);
    t.box(0.2, 0.72, 0.2, '#3E4E5C', 0.14, 0.36, 0);
    // 身体
    t.box(0.54, 0.7, 0.32, shirtColor, 0, 1.07, 0, { cast: true });
    // 手臂
    t.box(0.16, 0.6, 0.18, shirtColor, -0.35, 1.1, 0);
    t.box(0.16, 0.6, 0.18, shirtColor, 0.35, 1.1, 0);
    // 手
    t.box(0.15, 0.14, 0.16, '#F0C8A8', -0.35, 0.78, 0);
    t.box(0.15, 0.14, 0.16, '#F0C8A8', 0.35, 0.78, 0);
    // 头
    var head = new THREE.Mesh(new THREE.SphereGeometry(0.25, 12, 10), tools.mat('#F5D3B3'));
    head.position.set(0, 1.62, 0);
    head.castShadow = true;
    g.add(head);
    // 头发
    var hair = new THREE.Mesh(new THREE.SphereGeometry(0.26, 12, 8, 0, Math.PI * 2, 0, Math.PI * 0.55), tools.mat('#3B2E26'));
    hair.position.set(0, 1.66, -0.02);
    g.add(hair);
    // 眼睛
    t.box(0.05, 0.05, 0.03, '#33302C', -0.09, 1.63, 0.23);
    t.box(0.05, 0.05, 0.03, '#33302C', 0.09, 1.63, 0.23);
    return g;
  }

  /* ---------------- 构建与进出 ---------------- */

  function build(id) {
    if (builtIds[id]) { return rooms[id]; }
    var def = D.interiors[id];
    if (!def) { return null; }

    if (!rootGroup) {
      rootGroup = new THREE.Group();
      rootGroup.name = 'interiors';
      rootGroup.visible = false;
      ctx.scene.add(rootGroup);
    }

    var built;
    if (id === 'supermarket') {
      built = buildSupermarket(def, ctx.tools);
    } else if (id === 'library') {
      built = buildLibrary(def, ctx.tools);
    } else {
      return null;
    }

    rootGroup.add(built.group);

    // 把室内物件登记进单词系统，让它能被点击 / 显示标签
    var wmap = {};
    Object.keys(built.words).forEach(function (wid) {
      var node = built.words[wid];
      if (!node) { return; }
      wmap[wid] = { node: node, interior: id };
      if (ctx.register) { ctx.register(wid, node, id); }
    });

    var room = {
      id: id,
      def: def,
      group: built.group,
      words: wmap
    };
    rooms[id] = room;
    builtIds[id] = true;
    return room;
  }

  /* 进入：隐藏街道、显示该房间、返回房间定义供相机使用 */
  I.enter = function (id) {
    if (!D.interiors[id]) { return null; }
    var room = build(id);
    if (!room) { return null; }

    // 隐藏其他房间，只留这一间
    Object.keys(rooms).forEach(function (k) {
      rooms[k].group.visible = (k === id);
    });
    if (rootGroup) { rootGroup.visible = true; }
    if (ctx.worldRoot) { ctx.worldRoot.visible = false; }
    // 雾要关掉，否则室内会被远处雾色糊掉
    if (ctx.scene.fog) { ctx.scene.savedFog = ctx.scene.fog; ctx.scene.fog = null; }

    current = id;
    return room.def;
  };

  /* 退出：隐藏所有房间、恢复街道 */
  I.exit = function () {
    Object.keys(rooms).forEach(function (k) { rooms[k].group.visible = false; });
    if (rootGroup) { rootGroup.visible = false; }
    if (ctx && ctx.worldRoot) { ctx.worldRoot.visible = true; }
    if (ctx && ctx.scene && ctx.scene.savedFog) {
      ctx.scene.fog = ctx.scene.savedFog;
      ctx.scene.savedFog = null;
    }
    current = null;
  };

  I.isInside = function () { return !!current; };
  I.currentId = function () { return current; };
  I.getRoom = function (id) { return rooms[id] || null; };
  I.getDef = function (id) { return D.interiors[id] || null; };
  // 室内单词的节点（供场景层做标签 / 高亮）
  I.getWordNode = function (id) {
    if (!current) { return null; }
    var room = rooms[current];
    if (!room || !room.words[id]) { return null; }
    return room.words[id].node;
  };
  I.hasInterior = function (id) { return !!D.interiors[id]; };

  I.init = function (context) {
    ctx = context;
    return true;
  };

  global.WordCityInterior = I;
})(window);
