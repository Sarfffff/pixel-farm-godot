# 历史归档

这个目录不被 Godot 导入或导出，也不作为开发入口。

| 目录 | 内容 |
| --- | --- |
| `tools/` | 原来直接放在 tools 根目录的三份过时工具：地图生成、玩家动画生成、冒烟检查 |
| `docs/` | 旧的 generated 素材总说明，保留生成过程和历史规格供追溯 |

当前唯一入口：`tools/build/build_farm_map.gd`、`tools/build/build_player_frames.gd`、`tools/run_checks.ps1 -Suites smoke_check`。不要执行这里的旧脚本；它们不代表当前地图、保存协议或校验规范。当前目录规则见 [目录与资源规范](../docs/07-目录与资源规范.md)。
