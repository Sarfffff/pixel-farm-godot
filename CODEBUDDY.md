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
| `assets/tilesets/farm_terrain.tres` | 农场地形 TileSet（source 0 草地 / 1 耕地 / 2 水面） |
| `assets/game/` | 原始素材包（16×16 像素，只读） |
| `tools/build_farm_map.gd` | 地图生成器：改布局后跑一次即可重建 farm.tscn |
| `tools/build_player_frames.gd` | 玩家动画帧生成器（切图集写 SpriteFrames） |
| `tools/smoke_check.gd` | 无窗口自检：输入映射 / 动画 / 场景结构，退出码即结果 |
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
godot --headless --path e:/my-ai-game --script res://tools/build_farm_map.gd
godot --headless --path e:/my-ai-game --script res://tools/build_player_frames.gd

# 冒烟自检（退出码 0 = 全部通过）
godot --headless --path e:/my-ai-game --script res://tools/smoke_check.gd

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
