# 新增农场素材

## 当前已校准的植物素材（2026-11-04）

游戏里的蓝莓、土豆、野黑莓、红莓、醋栗和相关图标现在使用 `farm_style_v2/`。
这批素材使用内置 ImageGen，以现有作物图集和 `assets/textures/base/objects/basic_grass_biom_things.png`
中的地图灌木为参照重新生成，保持柔和绿叶、大色块、低细节密度和最近邻像素边缘。
野浆果有幼苗、采摘后、结果三种贴图；果实与种子袋使用不同的 16×16 图标。

- 运行素材：`farm_style_v2/crops/`、`farm_style_v2/berries/`、`farm_style_v2/items/`。
- 原图及完整提示词：`sources/farm_style_v2/`；生成方式记录在 `prompts.json`。
- 清单：`farm_style_v2/catalog.json`，含 31 张单图及尺寸；另有两张预览图集。
- 技术重建：`godot --headless --path . --script res://tools/art/prepare_farm_style_art.gd`。
- 同场景对照：`godot --path . --script res://tools/preview/preview_farm_style.gd`，输出到 `build/farm-previews/`。

蓝莓和土豆均使用 32×32 画布、根部第 31 行、`visual_scale = 1.0`，与原有作物保持相同像素密度。
切片保留幼苗到成株的体积差异，不把每个阶段单独放大到同样大小。
`content_v1/` 和 `expansion_v1/` 中对应旧图保留作历史素材；这两个大素材库尚未全部做过同场景风格验收，
接入其他内容时仍需与实际地图对照，不能只凭色板或图片尺寸认定风格一致。

以下是早期生成流程记录。

所有图片都已保存在本目录，原素材 `assets/textures/base/` 未覆盖。角色、作物和物品采用内置 **image_gen** 生成，再由 `tools/art/prepare_farm_art.gd` 完成技术整理。完整提示词保存在 [prompts.json](../../assets/textures/prompts.json)，切片配置保存在 [manifest.json](../../assets/textures/manifest.json)。

[素材预览](../../docs/screenshots/farm-assets-preview.png) 展示当前接入的两套动作和后续储备的作物、物品。可用 `godot --path . --script res://tools/preview/preview_farm_art.gd` 重新渲染。

## 当前使用与后续储备

| 目录 / 图片 | 内容 | 规格 | 接入情况 |
| --- | --- | --- | --- |
| `characters/farmer_actions_v3.png` | 锄头、斧头各四方向、四阶段，共 32 帧 | 128×256；每格 32×32；4 列 8 行 | 已接入角色动作 |
| `characters/hoe_*.png`、`axe_*.png` | 上述动作的单帧 PNG | 32×32 | 可独立复用 |
| `items/carrot_seeds.png` | 有胡萝卜图案的牛皮纸种子袋 | 16×16 | 已用于数字键 3 |
| `items/farm_items_v1.png` | 4 种种子袋、木材、石头、纤维、肥料、4 种收获物、单金币、金币堆、出货袋、木箱，共 16 项 | 64×64；每格 16×16 | 种子袋已用；其他储备 |
| `crops/crop_growth_v1.png` | 胡萝卜、芜菁、番茄、小麦各 6 张，共 24 张 | 192×128；每格 32×32 | 胡萝卜、番茄已接入生长玩法，另两种待配 `.tres` |
| `crops/<crop>_<stage>.png` | 四种作物的单阶段 PNG | 32×32 | 已用于播种 / 生长 / 收获 |
| `terrain/soil_dry_atlas.png` | 方形小切角干土、八邻域连边 | 256×256；256 格，每格 16×16 | 已用于耕地图集 |
| `terrain/soil_wet_atlas.png` | 同轮廓湿土 | 256×256 | 湿土色彩参考；游戏用同干土轮廓加湿土色调 |

`terrain/` 中其他河岸、坡地、桥梁等图片由独立的地图美术流程维护，不由此生成器覆盖。

## 图集排列

动作图集每行四列：准备、蓄势、命中、收手。前四行依次是锄头下、上、左、右，后四行依次是斧头下、上、左、右。锄头是长柄向下入土，斧头是短柄宽刃横向砍击；朝上时工具位于角色前方。角色脚底基准为 `(16, 24)`，用于 `AnimatedSprite2D` 时与已有 `position = (0, -8)` 搭配。

作物图集行顺序为 `carrot`、`turnip`、`tomato`、`wheat`；列顺序为 `seeds`、`sprout`、`young`、`growing`、`mature`、`harvest`。前五列用于地上植株，最后一列为收获物。单图根部基线在第 31 行，作为世界 Sprite 使用时建议 `position.y = -16`。

物品图集的逐项顺序见 manifest。所有整理后的图片使用最近邻采样，Alpha 只有 0 / 255，无半透明光晕。按 16px 基础地图使用；角色、长势较高的作物允许占用 32px 画布。

## 原图和版本

`sources/` 保留原始生成图片，统一命名为 `<用途>_v<N>.png`；该目录带 `.gdignore`，不参与引擎导入，`tools/art/` 下的脚本用 `Image.load_from_file()` 直接读文件。`farmer_actions_v2.png` 是首版候选，`farmer_actions_v3.png` 是纠正朝上工具方向和横向挥斧后的版本。游戏使用 **v3**；旧的 v2 图集保留用于对照，不再引用。作物与物品使用各自的 v1 原图。原图有近透明背景 RGB，不直接作为游戏贴图使用。

## 重建

```powershell
godot --headless --path . --script res://tools/art/prepare_farm_art.gd
godot --headless --editor --path . --import
godot --headless --path . --script res://tools/build/build_player_frames.gd
```

此流程只整理已保存图片，不重新调用图片生成服务。播种、生长、背包与材料掉落已接入，可直接使用单图或 manifest 指定的图集区域；出售与金币尚未实现。

## 地形与地面资源第一批

`world_regions_v1/` 为当前地图基础素材批次，含16种16×16地表、24种32×32地面资源、4种64×64树木、可拼接过渡图集及六类区域的真实渲染预览。全部新增原图使用内置ImageGen生成，项目画风图片仅作风格参考；提示词和原图保存在 `sources/world_regions_v1/`。

规格、区域用途、资源清单和接入边界见 [`world_regions_v1/README.md`](../../assets/packs/world_regions_v1/README.md) 与 [`docs/05-地图类型与地面资源.md`](../../docs/05-地图类型与地面资源.md)。已生成的样板可运行、可行走并具有实心资源碰撞；新的采集掉落和主世界连接尚未接入。

## 当前建筑、室内与表现统一

`presentation_v3/` 提供53张已分类PNG：4栋建筑、24件家具、5张设备状态、12张村民头像和8张地表/墙面。当前农舍、商店、鸡舍、社区外观、室内与对话已接入；四季、夜间灯光及天气使用对应表现层。规格、配色、脚底基线和重建入口见 [`presentation_v3/README.md`](../../assets/packs/presentation_v3/README.md)。原始生成图与完整提示词保存在 `sources/presentation_v3/`。
