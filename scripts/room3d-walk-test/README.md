# 小词屋「走进去」无头集成测试

`rawfile/room3d/` 是纯前端（three.js + 原生 JS），ArkWeb 里跑的东西没法用 hypium 测。
这里用 `jsdom` 打开真实的 `index.html`，加载仓库自带的 `three.min.js`，把
`THREE.WebGLRenderer` 换成一个只保留 `setSize / render / setAnimationLoop` 的桩——
几何、射线拾取、碰撞盒、标签分档、方位播报全是真的，所以能验证：

- 视角切换（全屋拒绝、单间房进入、文案翻转、开始带逛自动退出）
- 第一人称移动（按住前进、WASD 四方向、斜走不加速、撞墙、不穿家具）
- 四间房出生点、蹲下/站起、看见多远分档、滚轮调节
- 方位播报（站定后播报、开关、再点同一件 3.2 秒后补一句）
- 换房间 / 回全屋 / 原生 `setMode` 的 pendingWalk、词汇表打开时停走路

## 运行

```bash
cd scripts/room3d-walk-test
npm install        # 只装 jsdom，不碰仓库其它依赖
npm test
```

`npm test` 默认以仓库根目录为基准；也可以手动指定：`node integration.cjs /path/to/chatcube`。

## 约定

- 不测 WebGL 像素：桩渲染器不画图，只让渲染循环跑起来。
- 时间用手动 `tick(dt)` 推进（`frames(n)` = n × 16ms），不依赖真实时钟；
  只有「3.2 秒后补方位」这类 `setTimeout` 用真实等待。
- 静态一致性（DOM id、脚本顺序、桥接方法、CSS 规则）在 `scripts/verify-room3d-data.mjs`，
  不需要 jsdom，跟着仓库脚本跑。
