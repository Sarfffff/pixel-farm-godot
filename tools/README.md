# tools · 离线工具脚本

全部脚本以 `extends SceneTree` 的形式运行，不进入游戏本体，只在命令行/编辑器里执行一次。
统一调用方式（在项目根目录）：

```bash
godot --headless --path . --script res://tools/<子目录>/<脚本>.gd
```

退出码 `0` 表示成功。

## 目录

| 目录 | 职责 |
| --- | --- |
| `build/` | 生成或重建游戏资源（场景、动画帧） |
| `art/` | 把 AI 原始大图切片、量化、拼图集，产出可用的像素素材；以及素材预览页 |
| `check/` | 无窗口回归自检，改完功能必须跑 |
| `lib/` | 被上面几类脚本共用的纯数据/纯函数模块，不单独运行 |

## build · 资源生成

| 脚本 | 作用 |
| --- | --- |
| `build_farm_map.gd` | 从零构建 40×30 农场并覆写 `scenes/world/farm.tscn`（改动布局后跑一次） |
| `build_player_frames.gd` | 从动作图集切帧，写入 `scenes/player/player_frames.tres` 的 8 个方向动画 |
| `build_bgm.gd` | 波表合成三首原创循环 BGM（`menu` / `farm_day` / `farm_night`），写入 `assets/audio/bgm/`，WAV 内带 smpl 循环块 |

## art · 素材流水线

| 脚本 | 作用 |
| --- | --- |
| `prepare_farm_art.gd` | 角色动作 / 作物生长 / 物品图标：均分切片、最近邻缩放、二值 Alpha、统一落脚点 |
| `prepare_terrain_art.gd` | 用原素材 8×8 象限拼出岸线图集与桥梁图集 |
| `prepare_inventory_art.gd` | 把背包 UI 原图切成九宫格面板、格子态与详情底板，并压到 16 色 |
| `prepare_expansion_art.gd` | 扩展素材：6 种作物、12 种鱼、8 件渔具、6 种动物的透明 PNG 与 16×16 图标 |
| `preview_farm_art.gd` | 渲染已接入素材的验收页 |
| `preview_expansion_art.gd` | 渲染扩展素材的验收页 |

原始生成图固定在 `assets/generated/sources/`（含 `.gdignore`，不参与引擎导入），脚本用 `Image.load_from_file()` 直接读文件，产物写到 `assets/generated/` 对应子目录。

## check · 回归自检

| 脚本 | 覆盖内容 |
| --- | --- |
| `smoke_check.gd` | 输入映射、玩家动画与场景、地图结构、道具碰撞、主场景、背包装载 |
| `check_farm_interactions.gd` | 目标锁定、动画命中时序、障碍阻挡、浇水、倒树碰撞 |
| `check_farm_terrain.gd` | 地形分层、水体格子、岸线与桥梁数据一致性 |
| `check_inventory.gd` | 堆叠、溢出、满包、面板联动 |
| `check_crops.gd` | 播种、浇水推进、成熟、收获、满包保留 |
| `check_audio.gd` | 曲目加载与循环点、交叉淡入淡出、昼夜换曲、标题曲目、暂停不中断 |

`check_farm_interactions.gd` 与 `check_farm_terrain.gd` 追加 `-- --preview` 可在有窗口模式下输出截图到 `user://farm_previews/`。

## lib · 共用模块

| 脚本 | 作用 |
| --- | --- |
| `farm_landscape.gd` | 河流、池塘、岸线、桥、草坡的格子数据，保证画面与碰撞同源 |
| `terrain_tiles.gd` | 岸线/桥梁图集的拼接算法与输出路径 |

## 常用组合

```bash
# 改了地形布局
godot --headless --path . --script res://tools/build/build_farm_map.gd
godot --headless --path . --script res://tools/check/check_farm_terrain.gd

# 改了角色动作或作物贴图
godot --headless --path . --script res://tools/art/prepare_farm_art.gd
godot --headless --path . --script res://tools/build/build_player_frames.gd

# 提交前
godot --headless --path . --script res://tools/check/smoke_check.gd
```
