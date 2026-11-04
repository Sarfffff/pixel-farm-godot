# 游戏资源

`assets/` 保存游戏成品；原图、参考包和放大预览在 [art](../art/README.md)。统一使用 `assets` 复数目录，不再建立 `asset/` 或 `generated/` 平行目录。

| 目录 | 内容 |
| --- | --- |
| [textures](textures/README.md) | 按角色、建筑、作物、物品、地形等分类的基础贴图 |
| [packs](packs/README.md) | 带图集、清单、版本与重建流程的完整原创素材集合 |
| `ui/` | 当前共享主题 `farm_hud.tres`、控件纹理与滑块图标 |
| `tilesets/` | Godot TileSet 资源；引用 textures/packs 中的图片 |
| `shaders/` | 地表与植被的季节材质 |
| `audio/bgm/`、`audio/sfx/` | 音乐和操作音效 |

## 找图入口

| 需要的内容 | 优先查看 |
| --- | --- |
| 当前农舍、鸡舍、商店、社区外观 | `packs/presentation_v3/structures/` |
| 当前室内家具、地板、设备状态、对话头像 | `packs/presentation_v3/` 下的 furniture、tiles、objects、portraits |
| 当前蓝莓、土豆、野浆果与相关物品图标 | `packs/farm_style_v2/`；以 `data/crops/`、`data/items/` 中引用为准 |
| 玩家动作、手持工具、NPC 行走 | `textures/characters/`；基础角色图在 `textures/base/characters/` |
| 鱼、鱼竿、浮漂和后续动物图 | `packs/expansion_v1/` |
| 区域地表、树木、地面资源 | `packs/world_regions_v1/`，定义在 `data/maps/`、`data/ground_resources/` |
| 更多家具、建筑、动物、人物、物品、特效 | `packs/content_v1/` 的分类目录和 catalog.json |
| 其他建筑和果树储备 | `textures/buildings/`、`textures/trees/` |
| UI 配色与控件样式 | `ui/farm_hud.tres` |

“素材齐全”不代表玩法已接入。是否使用由场景、Resource 配置和实际加载代码决定；找当前物品图时优先从 `data/` 的定义追踪，不根据版本号猜测。完整批次保留自身目录，避免打散后丢失图集、动画和原图之间的对应关系。

规则：文件名使用英文 `snake_case`；PNG 采用最近邻；Godot 配套 `.import`、脚本 `.uid` 与资源一起迁移并保留身份；新增或替换后执行导入、目录检查和相关隔离回归。不要手动改 `.godot/` 缓存。
