# 新增农场素材

所有图片都已保存在本目录，原素材 `assets/game/` 未覆盖。角色、作物和物品采用内置 **image_gen** 生成，再由 `tools/prepare_farm_art.gd` 完成技术整理。完整提示词保存在 [prompts.json](prompts.json)，切片配置保存在 [manifest.json](manifest.json)。

[素材预览](../../docs/screenshots/farm-assets-preview.png) 展示当前接入的两套动作和后续储备的作物、物品。可用 `godot --path . --script res://tools/preview_farm_art.gd` 重新渲染。

## 当前使用与后续储备

| 目录 / 图片 | 内容 | 规格 | 接入情况 |
| --- | --- | --- | --- |
| `characters/farmer_actions_v3.png` | 锄头、斧头各四方向、四阶段，共 32 帧 | 128×256；每格 32×32；4 列 8 行 | 已接入角色动作 |
| `characters/hoe_*.png`、`axe_*.png` | 上述动作的单帧 PNG | 32×32 | 可独立复用 |
| `items/carrot_seeds.png` | 有胡萝卜图案的牛皮纸种子袋 | 16×16 | 已用于数字键 3 |
| `items/farm_items_v1.png` | 4 种种子袋、木材、石头、纤维、肥料、4 种收获物、单金币、金币堆、出货袋、木箱，共 16 项 | 64×64；每格 16×16 | 种子袋已用；其他储备 |
| `crops/crop_growth_v1.png` | 胡萝卜、芜菁、番茄、小麦各 6 张，共 24 张 | 192×128；每格 32×32 | 图片已备，生长玩法待接入 |
| `crops/<crop>_<stage>.png` | 四种作物的单阶段 PNG | 32×32 | 后续播种 / 生长 / 收获 |
| `terrain/soil_dry_atlas.png` | 方形小切角干土、八邻域连边 | 256×256；256 格，每格 16×16 | 已用于耕地图集 |
| `terrain/soil_wet_atlas.png` | 同轮廓湿土 | 256×256 | 湿土色彩参考；游戏用同干土轮廓加湿土色调 |

`terrain/` 中其他河岸、坡地、桥梁等图片由独立的地图美术流程维护，不由此生成器覆盖。

## 图集排列

动作图集每行四列：准备、蓄势、命中、收手。前四行依次是锄头下、上、左、右，后四行依次是斧头下、上、左、右。锄头是长柄向下入土，斧头是短柄宽刃横向砍击；朝上时工具位于角色前方。角色脚底基准为 `(16, 24)`，用于 `AnimatedSprite2D` 时与已有 `position = (0, -8)` 搭配。

作物图集行顺序为 `carrot`、`turnip`、`tomato`、`wheat`；列顺序为 `seeds`、`sprout`、`young`、`growing`、`mature`、`harvest`。前五列用于地上植株，最后一列为收获物。单图根部基线在第 31 行，作为世界 Sprite 使用时建议 `position.y = -16`。

物品图集的逐项顺序见 manifest。所有整理后的图片使用最近邻采样，Alpha 只有 0 / 255，无半透明光晕。按 16px 基础地图使用；角色、长势较高的作物允许占用 32px 画布。

## 原图和版本

`sources/` 保留原始生成图片。`farmer_actions_v2.png` 是首版候选，`farmer_actions_v3.png` 是纠正朝上工具方向和横向挥斧后的版本。游戏使用 **v3**；旧的 v2 图集保留用于对照，不再引用。作物与物品使用各自的 v1 原图。原图有近透明背景 RGB，不直接作为游戏贴图使用。

## 重建

```powershell
godot --headless --path . --script res://tools/prepare_farm_art.gd
godot --headless --editor --path . --import
godot --headless --path . --script res://tools/build_player_frames.gd
```

此流程只整理已保存图片，不重新调用图片生成服务。后续接入播种、生长、背包、材料掉落与出售时，可直接使用单图或 manifest 指定的图集区域；这些系统当前尚未实现。
