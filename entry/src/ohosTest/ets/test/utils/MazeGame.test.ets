/**
 * MazeGame 单元测试
 *
 * 覆盖:
 * - solveMaze: BFS 最短路径(固定 2×2 迷宫的唯一路径/不可达/同格/越界,
 *   以及 generateMaze 各难度的路径合法性: 相邻步、无墙、首尾正确)
 * - getNeighborPosition: 方向增量与边界
 * - generateMaze: 结构健全性(尺寸、起终点标记、相邻格墙对称、种子可复现)
 */

import { describe, it, expect } from '@ohos/hypium'
import {
  MazeCell,
  MazeData,
  MazePosition,
  generateMaze,
  solveMaze,
  getNeighborPosition,
  findDeadEnds
  MazeDifficulty,
  MazeDimensions,
  MazeExtras,
  getGridDimensions,
  computePar,
  evaluateStars,
  getPortalTarget
} from '../../../../main/ets/utils/MazeGame'

// 固定 2×2 迷宫: (0,0)→(0,1)→(1,1) 唯一路径, (1,0) 四面墙不可达
function buildFixedMaze(): MazeData {
  const cells: MazeCell[][] = [
    [
      {
        walls: { top: true, right: false, bottom: true, left: true },
        hasStar: false, isStart: true, isGoal: false
      },
      {
        walls: { top: true, right: true, bottom: false, left: false },
        hasStar: false, isStart: false, isGoal: false
      }
    ],
    [
      {
        walls: { top: true, right: true, bottom: true, left: true },
        hasStar: false, isStart: false, isGoal: false
      },
      {
        walls: { top: false, right: true, bottom: true, left: true },
        hasStar: false, isStart: false, isGoal: true
      }
    ]
  ]
  return { rows: 2, cols: 2, cells: cells, starsTotal: 0 }
}

// 校验路径中相邻两步: 曼哈顿距离为 1 且中间无墙
function isStepOpen(cells: MazeCell[][], from: MazePosition, to: MazePosition): boolean {
  if (from.row === to.row && to.col === from.col + 1) {
    return !cells[from.row][from.col].walls.right
  }
  if (from.row === to.row && to.col === from.col - 1) {
    return !cells[from.row][from.col].walls.left
  }
  if (from.col === to.col && to.row === from.row + 1) {
    return !cells[from.row][from.col].walls.bottom
  }
  if (from.col === to.col && to.row === from.row - 1) {
    return !cells[from.row][from.col].walls.top
  }
  return false
}

export default function MazeGameTest() {
  describe('MazeGameTest', () => {
    // ===== solveMaze =====

    it('solveMaze_finds_unique_path_on_fixed_maze', 0, () => {
      const maze: MazeData = buildFixedMaze()
      const path: MazePosition[] | null = solveMaze(
        maze.cells, { row: 0, col: 0 }, { row: 1, col: 1 })
      expect(path !== null).assertTrue()
      if (path === null) {
        return
      }
      expect(path.length).assertEqual(3)
      expect(path[0].row).assertEqual(0)
      expect(path[0].col).assertEqual(0)
      expect(path[1].row).assertEqual(0)
      expect(path[1].col).assertEqual(1)
      expect(path[2].row).assertEqual(1)
      expect(path[2].col).assertEqual(1)
    })

    it('solveMaze_returns_null_for_unreachable_cell', 0, () => {
      const maze: MazeData = buildFixedMaze()
      const path: MazePosition[] | null = solveMaze(
        maze.cells, { row: 0, col: 0 }, { row: 1, col: 0 })
      expect(path === null).assertTrue()
    })

    it('solveMaze_same_from_to_returns_single_cell', 0, () => {
      const maze: MazeData = buildFixedMaze()
      const path: MazePosition[] | null = solveMaze(
        maze.cells, { row: 0, col: 1 }, { row: 0, col: 1 })
      expect(path !== null).assertTrue()
      if (path === null) {
        return
      }
      expect(path.length).assertEqual(1)
      expect(path[0].row).assertEqual(0)
      expect(path[0].col).assertEqual(1)
    })

    it('solveMaze_rejects_out_of_bounds', 0, () => {
      const maze: MazeData = buildFixedMaze()
      expect(solveMaze(maze.cells, { row: -1, col: 0 }, { row: 1, col: 1 }) === null).assertTrue()
      expect(solveMaze(maze.cells, { row: 0, col: 0 }, { row: 2, col: 0 }) === null).assertTrue()
      expect(solveMaze(maze.cells, { row: 0, col: 5 }, { row: 1, col: 1 }) === null).assertTrue()
    })

    it('solveMaze_generated_mazes_have_valid_start_to_goal_path', 0, () => {
      const sizes: MazePosition[] = [
        { row: 4, col: 4 }, { row: 6, col: 6 }, { row: 8, col: 8 }
      ]
      for (let i = 0; i < sizes.length; i++) {
        const maze: MazeData = generateMaze(sizes[i].row, sizes[i].col, 2, 1000 + i)
        const path: MazePosition[] | null = solveMaze(
          maze.cells, { row: 0, col: 0 }, { row: maze.rows - 1, col: maze.cols - 1 })
        expect(path !== null).assertTrue()
        if (path === null) {
          return
        }
        // 首尾正确
        expect(path[0].row).assertEqual(0)
        expect(path[0].col).assertEqual(0)
        expect(path[path.length - 1].row).assertEqual(maze.rows - 1)
        expect(path[path.length - 1].col).assertEqual(maze.cols - 1)
        // 每一步相邻且无墙
        for (let s = 1; s < path.length; s++) {
          expect(isStepOpen(maze.cells, path[s - 1], path[s])).assertTrue()
        }
      }
    })

    // ===== getNeighborPosition =====

    it('getNeighborPosition_returns_delta_for_each_direction', 0, () => {
      const center: MazePosition = { row: 2, col: 2 }
      const right: MazePosition | null = getNeighborPosition(center, 'right', 5, 5)
      expect(right !== null).assertTrue()
      if (right !== null) {
        expect(right.row).assertEqual(2)
        expect(right.col).assertEqual(3)
      }
      const top: MazePosition | null = getNeighborPosition(center, 'top', 5, 5)
      expect(top !== null).assertTrue()
      if (top !== null) {
        expect(top.row).assertEqual(1)
        expect(top.col).assertEqual(2)
      }
      const left: MazePosition | null = getNeighborPosition(center, 'left', 5, 5)
      expect(left !== null).assertTrue()
      if (left !== null) {
        expect(left.row).assertEqual(2)
        expect(left.col).assertEqual(1)
      }
      const bottom: MazePosition | null = getNeighborPosition(center, 'bottom', 5, 5)
      expect(bottom !== null).assertTrue()
      if (bottom !== null) {
        expect(bottom.row).assertEqual(3)
        expect(bottom.col).assertEqual(2)
      }
    })

    it('getNeighborPosition_returns_null_out_of_bounds', 0, () => {
      const corner: MazePosition = { row: 0, col: 0 }
      expect(getNeighborPosition(corner, 'top', 4, 4) === null).assertTrue()
      expect(getNeighborPosition(corner, 'left', 4, 4) === null).assertTrue()
      const farCorner: MazePosition = { row: 3, col: 3 }
      expect(getNeighborPosition(farCorner, 'bottom', 4, 4) === null).assertTrue()
      expect(getNeighborPosition(farCorner, 'right', 4, 4) === null).assertTrue()
    })

    // ===== generateMaze 健全性 =====

    it('generateMaze_marks_start_and_goal_and_limits_stars', 0, () => {
      const maze: MazeData = generateMaze(6, 6, 2, 42)
      expect(maze.rows).assertEqual(6)
      expect(maze.cols).assertEqual(6)
      expect(maze.cells[0][0].isStart).assertTrue()
      expect(maze.cells[5][5].isGoal).assertTrue()
      expect(maze.starsTotal <= 2).assertTrue()
      // 起点终点不藏胡萝卜
      expect(maze.cells[0][0].hasStar).assertFalse()
      expect(maze.cells[5][5].hasStar).assertFalse()
    })

    it('generateMaze_walls_are_symmetric_between_neighbors', 0, () => {
      const maze: MazeData = generateMaze(8, 8, 2, 7)
      for (let r = 0; r < maze.rows; r++) {
        for (let c = 0; c < maze.cols; c++) {
          if (c < maze.cols - 1) {
            expect(maze.cells[r][c].walls.right === maze.cells[r][c + 1].walls.left).assertTrue()
          }
          if (r < maze.rows - 1) {
            expect(maze.cells[r][c].walls.bottom === maze.cells[r + 1][c].walls.top).assertTrue()
          }
        }
      }
    })

    it('generateMaze_same_seed_produces_same_solution', 0, () => {
      const a: MazeData = generateMaze(6, 6, 2, 2026)
      const b: MazeData = generateMaze(6, 6, 2, 2026)
      const pathA: MazePosition[] | null = solveMaze(
        a.cells, { row: 0, col: 0 }, { row: 5, col: 5 })
      const pathB: MazePosition[] | null = solveMaze(
        b.cells, { row: 0, col: 0 }, { row: 5, col: 5 })
      expect(pathA !== null && pathB !== null).assertTrue()
      if (pathA === null || pathB === null) {
        return
      }
      expect(pathA.length).assertEqual(pathB.length)
      for (let i = 0; i < pathA.length; i++) {
        expect(pathA[i].row === pathB[i].row).assertTrue()
        expect(pathA[i].col === pathB[i].col).assertTrue()
      }
    })

    it('findDeadEnds_on_fixed_maze_finds_isolated_and_start_cells', 0, () => {
      const maze: MazeData = buildFixedMaze()
      const deadEnds: MazePosition[] = findDeadEnds(maze.cells)
      // (1,0) 四面墙 + 起点 (0,0) 三面墙都是死胡同; (0,1)/(1,1) 两面墙不是
      expect(deadEnds.length).assertEqual(2)
      let hasIsolated: boolean = false
      let hasStart: boolean = false
      for (let i = 0; i < deadEnds.length; i++) {
        if (deadEnds[i].row === 1 && deadEnds[i].col === 0) {
          hasIsolated = true
        }
        if (deadEnds[i].row === 0 && deadEnds[i].col === 0) {
          hasStart = true
        }
      }
      expect(hasIsolated).assertTrue()
      expect(hasStart).assertTrue()
    })

    // ===== v3: 更大迷宫 / 道具 / 传送门 / 星级评定 =====

    it('getGridDimensions_maps_difficulty_to_grid_sizes', 0, () => {
      const d1: MazeDimensions = getGridDimensions(1 as MazeDifficulty)
      const d2: MazeDimensions = getGridDimensions(2 as MazeDifficulty)
      const d3: MazeDimensions = getGridDimensions(3 as MazeDifficulty)
      expect(d1.rows).assertEqual(9)
      expect(d1.cols).assertEqual(9)
      expect(d2.rows).assertEqual(11)
      expect(d2.cols).assertEqual(11)
      expect(d3.rows).assertEqual(13)
      expect(d3.cols).assertEqual(13)
    })

    it('generateMaze_13x13_has_valid_solution', 0, () => {
      const maze: MazeData = generateMaze(13, 13, 5)
      expect(maze.rows).assertEqual(13)
      expect(maze.cols).assertEqual(13)
      const goal: MazePosition = { row: 12, col: 12 }
      const path: MazePosition[] | null = solveMaze(maze.cells, { row: 0, col: 0 }, goal)
      expect(path !== null).assertTrue()
      expect(path !== null ? path.length : 0).assertLarger(13)
    })

    it('generateMaze_extras_places_exact_powerup_treasure_portal_counts', 0, () => {
      const extras: MazeExtras = { powerupCount: 2, treasureCount: 1, portalPair: true }
      const maze: MazeData = generateMaze(11, 11, 4, 20260930, extras)
      let powerups: number = 0
      let treasures: number = 0
      let portals: number = 0
      for (let r = 0; r < maze.rows; r++) {
        for (let c = 0; c < maze.cols; c++) {
          const cell: MazeCell = maze.cells[r][c]
          if (cell.powerup !== undefined && cell.powerup !== '') {
            powerups += 1
            if (cell.powerup === 'treasure') {
              treasures += 1
            }
          }
          if (cell.portalTo !== undefined && cell.portalTo !== null) {
            portals += 1
          }
        }
      }
      expect(powerups).assertEqual(3)
      expect(treasures).assertEqual(1)
      expect(portals).assertEqual(2)
    })

    it('generateMaze_portal_pair_points_to_each_other', 0, () => {
      const extras: MazeExtras = { powerupCount: 2, treasureCount: 1, portalPair: true }
      const maze: MazeData = generateMaze(11, 11, 4, 7, extras)
      let firstPortal: MazePosition | null = null
      let mutual: boolean = false
      for (let r = 0; r < maze.rows; r++) {
        for (let c = 0; c < maze.cols; c++) {
          const cell: MazeCell = maze.cells[r][c]
          if (cell.portalTo !== undefined && cell.portalTo !== null) {
            if (firstPortal === null) {
              firstPortal = { row: r, col: c }
            } else {
              const back: MazeCell = maze.cells[cell.portalTo.row][cell.portalTo.col]
              mutual = back.portalTo !== undefined && back.portalTo !== null &&
                back.portalTo.row === r && back.portalTo.col === c
            }
          }
        }
      }
      expect(firstPortal !== null).assertTrue()
      expect(mutual).assertTrue()
    })

    it('computePar_adds_shortest_path_and_carrot_bonus', 0, () => {
      const maze: MazeData = buildFixedMaze()
      maze.starsTotal = 3
      // 固定 2×2: 最短路径 2 步 + 3 胡萝卜 ×2 = 8
      expect(computePar(maze)).assertEqual(8)
    })

    it('evaluateStars_three_tiers_boundaries', 0, () => {
      // 3 星: 收满且超额 ≤ 2
      expect(evaluateStars(8, 8, 3, 3)).assertEqual(3)
      expect(evaluateStars(10, 8, 3, 3)).assertEqual(3)
      expect(evaluateStars(11, 8, 3, 3)).assertEqual(2)
      // 2 星: 收满但超额 > 2, 或未收满但超额 ≤ 6
      expect(evaluateStars(20, 8, 3, 3)).assertEqual(2)
      expect(evaluateStars(14, 8, 2, 3)).assertEqual(2)
      // 1 星: 未收满且超额 > 6
      expect(evaluateStars(15, 8, 2, 3)).assertEqual(1)
    })

    it('getPortalTarget_returns_null_for_plain_cell', 0, () => {
      const maze: MazeData = buildFixedMaze()
      expect(getPortalTarget(maze.cells[0][0])).assertNull()
    })

  })
}
