# 地形与资源素材第一批

本目录提供16种原生16×16地表、24种原生32×32地面资源、4种64×64树木及技术拼接的地形过渡图集。原图由内置ImageGen独立生成，按项目现有素材作画风参考，经Godot脚本切片、最近邻整理、色板处理及二值Alpha校准。

素材规格、区域用途、参考资料与接入规则见 [`docs/05-地图类型与地面资源.md`](../../../docs/05-地图类型与地面资源.md)。2026-11-05起，六张地图及28类资源已接入正式Main会话，支持切区、采集、掉落、再生和保存。独立F6样板仍仅供美术及分布检查。

| 路径 | 用途 |
| --- | --- |
| `terrain/` | 16张地表单图，原生16×16 |
| `resources/` | 28张透明单图；树木64×64，其余32×32 |
| `terrain_atlas.png` | 4×4地表图集，64×64像素 |
| `resources_atlas.png` | 6×4地面资源图集，192×128像素，不含四种树木 |
| `transition_atlas.png` | 16种底面×16种邻面×16个四向边缘掩码，共4096种组合；1024×1024像素 |
| `catalog.json` | 图像数量、尺寸、来源与技术处理清单 |
| `previews/` | 六张真实渲染截图、地图总览及资源标注页；带`.gdignore`不参与导入 |

原始生成图与完整提示词在 [`../sources/world_regions_v1/`](../../../art/sources/world_regions_v1)。原图只作可重建来源，不直接用于游戏，也不参与Godot导入。

区域生成源为 `tools/lib/world_region_catalog.gd`；输出为 `data/maps/*.tres`、`data/ground_resources/*.tres` 和 `scenes/maps/*_preview.tscn`。修改输出配置后再次运行生成器会覆盖，因此要长期保存的布局调整应回写生成源。

```powershell
# 1 切片及技术整理
godot --headless --path . --script res://tools/art/prepare_world_region_art.gd
# 2 导入新PNG
godot --headless --editor --path . --import
# 3 重建原生配置与六张样板
godot --headless --path . --script res://tools/build/build_region_previews.gd
# 4 验证，不读取或写入玩家槽位
pwsh -NoProfile -File tools/run_checks.ps1 -Suites check_world_regions,check_region_gameplay
# 5 真实渲染截图，不能加headless
godot --path . --rendering-method gl_compatibility --script res://tools/preview/preview_world_regions.gd
# 6 直接运行样板，数字1至6切换区域
godot --path . --scene res://scenes/maps/forest_preview.tscn
```

独立样板可以WASD或方向键行走，鼠标悬停查看资源的规划交互；按钮或数字1至6切换区域。实心树木、石头有脚底碰撞，软植被允许穿过。正式玩法请F5运行主游戏，从原农场东侧路标出发；采集数值独立配置在 `data/maps/resource_rules.tres`，地图连接在 `data/maps/region_routes.tres`，重建美术样板不会覆写这两个文件。
