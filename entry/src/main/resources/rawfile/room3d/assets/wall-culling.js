// 近侧墙显隐判定（纯函数，不依赖 THREE / DOM，供 verify-room3d-data.mjs 在 Node 下回归测试）。
// 语义：相机坐标小于「房间中心 − 距离」时隐藏近侧墙。
// 已隐藏时用较浅的距离保持隐藏，已显示时用较深的距离才隐藏——中间 0.2m 缓冲带内状态不变，避免每帧闪烁。
(function (global) {
  var HIDE_DISTANCE = 0.5;
  var SHOW_DISTANCE = 0.3;

  function nextWallHidden(cameraCoord, centerCoord, previousHidden) {
    var distance = previousHidden ? SHOW_DISTANCE : HIDE_DISTANCE;
    return cameraCoord < centerCoord - distance;
  }

  global.WordRoomWalls = { nextWallHidden: nextWallHidden };
})(typeof window !== 'undefined' ? window : globalThis);
