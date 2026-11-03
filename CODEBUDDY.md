# CODEBUDDY.md

Godot 4.7 小游戏项目（`My_ai_Game`），通过 **Godot AI** 插件（`addons/godot_ai`，v4.3.1）把 Godot 编辑器接入 CodeBuddy 的 MCP，让 AI 能直接读写场景、节点、脚本并运行游戏。

## 关键文件

| 路径 | 说明 |
| --- | --- |
| `project.godot` | 引擎配置（Forward+、Jolt Physics、Windows D3D12、320×180 视口 + canvas_items 拉伸、Nearest 过滤） |
| `scenes/main.tscn` | 入口场景：`Farm` + `Player` + 跟随相机 |
| `scenes/world/farm.tscn` | 40×30 农场地图：Ground/Water/Overlay/Detail 四层 TileMapLayer + WaterCollision 水碰撞 + World(y_sort) 道具容器 + Bounds 边界墙 |
| `scenes/world/props/` | 可复用道具场景（小屋、树、灌木、石头、蘑菇、原木），贴图取区见 `docs/02` 素材坐标备忘 |
| `scenes/player/` | 玩家场景 + `player_frames.tres`（8 个方向动画） |
| `scripts/player/player.gd` | 四向移动、朝向记忆、动画切换 |
| `scripts/world/camera_follow.gd` | 相机平滑跟随 + 地图边界限制 |
| `scripts/world/occlusion_fader.gd` | 角色被建筑/树遮挡时把道具淡到 55% 透明度（挂在 `World` 上） |
| `scripts/world/farm_tiller.gd` | 耕地系统：面前格高亮、锄地、浇水、九宫格自动连边（挂在 `Farm/Tiller`） |
| `scenes/world/tile_cursor.tscn` | 面前格白色高亮框 |
| `scenes/ui/toolbar.tscn` | 底部工具栏（H/W/S 三格，订阅 `tool_changed`） |
| `scripts/data/item_data.gd` + `data/items/` | 物品定义 Resource 与 8 个物品数据（背包扫描该目录） |
| `scripts/systems/inventory.gd` | 背包系统：24 格堆叠、溢出返回、`changed` / `item_added` 信号（`Main/Systems/Inventory`） |
| `scenes/ui/inventory_panel.tscn` | 背包面板（6×4 格，`B` 开关，打开时锁玩家输入并收起工具栏；九宫格主题见 `assets/generated/ui/inventory/`） |
| `scenes/ui/toast.tscn` | 入包飘字提示（订阅 `item_added`） |
| `scripts/data/crop_data.gd` + `data/crops/` | 作物定义 Resource 与作物表（4 阶段贴图，耕地脚本扫描该目录） |
| `scenes/world/crop.tscn` + `scripts/world/crop.gd` | 作物节点：阶段切换、浇水推进、成熟与收获动画 |
| `assets/tilesets/farm_terrain.tres` | 农场地形 TileSet（source 0 草地 / 1 耕地 / 2 水面） |
| `assets/game/` | 原始素材包（16×16 像素，只读） |
| `assets/generated/` | 生成产物：切片贴图、图集、背包 UI 九宫格；`sources/` 存 AI 原始大图，带 `.gdignore` 不参与导入 |
| `tools/README.md` | 离线工具脚本索引（每个脚本的作用与运行命令） |
| `tools/build/` | `build_farm_map.gd` 地图生成器、`build_player_frames.gd` 动画帧生成器、`build_bgm.gd` BGM 波表合成器 |
| `scripts/systems/economy.gd` | 金币系统（初始 500、`spend` 不足不改数、`coins_gained` 飘字），挂在 `Main/Systems/Economy` |
| `scenes/ui/hud.tscn` | 右上角金币条（订阅 `economy`，收入飘 `+N`） |
| `scenes/ui/shop_panel.tscn` | 农场商店：左买种子、右卖背包货，商品来自物品表 `buy_price`/`sell_price` |
| `scenes/npcs/shopkeeper.tscn` + `scripts/npcs/shopkeeper.gd` | 杂货铺老板：脚底碰撞、固定朝下、靠近按 `E` 对话（`interactable` 组） |
| `scenes/ui/dialogue_panel.tscn` + `scripts/ui/dialogue_panel.gd` | 通用对话框：说话人 + 台词 + 选项，选项回调 owner 的 `on_dialogue_option` |
| `scripts/systems/time_system.gd` | 时间系统：天数/时:分、06:00 起 02:00 收工、`day_started` 驱动作物结算（`Main/Systems/Time`） |
| `scripts/systems/save_system.gd` | 存档：`user://save_1.json`，含时间/金币/背包/耕地/作物/玩家位置，坏档自动隔离 |
| `scripts/systems/stamina.gd` | 体力（100，干活扣、睡觉回满，`Main/Systems/Stamina`） |
| `scripts/systems/weather.gd` | 天气（晴/阴/雨，雨天自动浇作物；`lock()` 可固定天气供回归用，`Main/Systems/Weather`） |
| `scripts/systems/audio_manager.gd` | 背景音乐单例（autoload `AudioManager`）：双播放器交叉淡入淡出、强制首尾循环、音量与开关 |
| `scripts/world/bgm_controller.gd` | 农场 BGM 昼夜切换（`Main/Systems/BGM`），17:00 切夜晚曲目 |
| `assets/audio/bgm/` | 三首原创循环 BGM（`menu` / `farm_day` / `farm_night`），由 `tools/build/build_bgm.gd` 合成 |
| `scenes/ui/day_summary.tscn` | 睡前日报：今日收获与收入，确认后睡觉并自动存档 |
| `scenes/world/sleep_spot.tscn` | 木屋门口的睡觉点（靠近按 `E`） |
| `scripts/world/day_night_tint.gd` | 昼夜色调（`CanvasModulate`，只暗化世界） |
| `scenes/ui/main_menu.tscn` | 标题界面（项目主场景）：继续 / 新游戏 / 退出 |
| `scenes/ui/pause_menu.tscn` | 暂停菜单：`Esc` 暂停场景树，继续 / 保存 / 保存并返回标题 / 按键说明 |
| `scenes/world/chicken.tscn` + `scripts/world/chicken.gd` | 鸡：`CharacterBody2D` 在出生点半径内随机踱步，撞障碍换点，左右各两帧走路 |
| `scenes/world/props/chicken_coop.tscn` + `scripts/world/chicken_coop.gd` | 鸡窝：监听 `day_started` 每天下蛋（上限 3 颗），蛋坐标进存档 |
| `scenes/world/egg.tscn` + `scripts/world/egg.gd` | 地上的鸡蛋：`interactable` 组，`E` 拾取，满包留在地上 |
| `scenes/ui/help_panel.tscn` + `scripts/ui/help_panel.gd` | 按键说明：`F1` 或暂停菜单打开，打开时暂停游戏树 |
| `scripts/systems/orders.gd` | 每日订单：按解锁阶段出单、交付发奖金、`day_started` 换新单 |
| `scripts/systems/community_center.gd` | 社区中心：三阶段上缴，`unlocked_stage()` 决定商店卖哪些种子 |
| `scripts/systems/stamina.gd` | 体力：干活消耗、睡觉回满，`spend()` 扣不动就拦住操作 |
| `scripts/systems/weather.gd` | 天气：每天翻一次（晴/阴/雨），雨天自动浇水；`lock()` 供测试固定天气 |
| `scenes/world/props/order_bin.tscn` + `order_bin.gd` | 木屋旁的订单箱（`interactable`，`E` 打开订单面板） |
| `scenes/world/props/community_building.tscn` + `community_building.gd` | 社区中心建筑（左下空地，`E` 打开上缴面板） |
| `scenes/ui/order_panel.tscn`、`scenes/ui/community_panel.tscn` | 订单与社区中心面板 |
| `tools/check/` | `smoke_check.gd` 自检、`check_inventory.gd` 背包、`check_crops.gd` 作物、`check_shop.gd` 商店、`check_animals.gd` 鸡与蛋、`check_npcs.gd` NPC、`check_audio.gd` 背景音乐、`check_farm_*.gd` 耕地与地形回归 |
| `tools/art/` | 素材整理脚本（角色动作、作物、物品、地形岸线、背包 UI 九宫格、预览页） |
| `tools/lib/` | 地图脚本共用的格子数据（`farm_landscape.gd`、`terrain_tiles.gd`） |
| `docs/` | 流程、路线图、参考项目对照文档 |
| `addons/godot_ai/` | Godot AI 插件（只读，勿改） |
| `addons/godot_ai/runtime/game_helper.gd` | autoload `_mcp_game_helper`，运行期与 MCP 通信 |
| `.codebuddy/rules/` | 项目规则（Godot 规范 + MCP 工作流） |
| `.codebuddy/mcp.json` | （可选）项目级 MCP 配置；当前 `godot-ai` 条目在用户级 `~/.codebuddy/mcp.json` |

## 环境要求

- Godot 4.7.x
- `uv`（提供 `uvx`，已安装：`C:\Users\<user>\.local\bin\uvx.exe`）
- CodeBuddy IDE，MCP 中使用 stdio：`godot-ai attach --port 8000 --ws-port 9500`

## 常用命令

```bash
# 语法检查单个脚本
godot --headless --check-only --script res://scripts/xxx.gd

# 重建资源（地图 / 玩家动画帧）
godot --headless --path e:/my-ai-game --script res://tools/build/build_farm_map.gd
godot --headless --path e:/my-ai-game --script res://tools/build/build_player_frames.gd
godot --headless --path e:/my-ai-game --script res://tools/build/build_bgm.gd

# 冒烟自检（退出码 0 = 全部通过）
godot --headless --path e:/my-ai-game --script res://tools/check/smoke_check.gd

# 背包回归（堆叠 / 溢出 / 满包 / 面板联动）
godot --headless --path e:/my-ai-game --script res://tools/check/check_inventory.gd

# 作物回归（播种 / 浇水推进 / 成熟 / 收获）
godot --headless --path e:/my-ai-game --script res://tools/check/check_crops.gd

# 商店回归（买卖结算 / 金币不足 / 面板互斥）
godot --headless --path e:/my-ai-game --script res://tools/check/check_shop.gd

# 时间与存档回归（日期推进 / 隔夜生长 / 存读档 / 坏档容错）
godot --headless --path e:/my-ai-game --script res://tools/check/check_calendar.gd

# 暂停与标题界面回归（Esc 优先级 / 暂停时钟 / 保存 / 继续按钮）
godot --headless --path e:/my-ai-game --script res://tools/check/check_pause.gd

# 交互与地形回归（目标锁定 / 命中时序 / 障碍 / 水体格数）
godot --headless --path e:/my-ai-game --script res://tools/check/check_farm_interactions.gd
godot --headless --path e:/my-ai-game --script res://tools/check/check_farm_terrain.gd

# 无头运行项目
godot --headless --path e:/my-ai-game

# 用 uvx 直接起 MCP 服务（手动调试）
uvx --from godot-ai==4.3.1 godot-ai attach --port 8000 --ws-port 9500
```

## 工作方式

1. 在 Godot 编辑器里打开本项目并启用 **Godot AI** 插件，确认面板连接正常（服务端口 8000 / WebSocket 9500）。
2. 在 CodeBuddy 里确认 MCP 的 `godot-ai` 变绿；工具列表出现 `editor_state`、`scene_get_hierarchy` 等即可用。
3. 遵循 `.codebuddy/rules/godot-project-standards` 的 GDScript 规范；涉及场景操作时按 `godot-ai-mcp-workflow` 的读→改→存→跑→查日志顺序执行。
4. 代码改动必须实际运行验证，控制台不允许残留 `SCRIPT ERROR`。
