# 原创素材集合

每个目录保留一套完整的图片、图集、清单和相关 Godot 资源。版本号用于追溯生成批次，不代表整个目录都在当前游戏使用，也不代表版本号更大的图适合替换所有旧图。

| 目录 | 内容与接入情况 | 原图 |
| --- | --- | --- |
| [presentation_v3](presentation_v3/README.md) | 当前四栋建筑、室内家具、设备状态、四位村民头像、地表和墙面，53张PNG | `art/sources/presentation_v3/` |
| `farm_style_v2/` | 当前部分作物、野浆果及图标的风格修订，catalog 记录31张贴图 | `art/sources/farm_style_v2/` |
| [world_regions_v1](world_regions_v1/README.md) | 区域地表、资源、过渡图集；主世界连接状态以系统设计和总纲为准 | `art/sources/world_regions_v1/` |
| [expansion_v1](expansion_v1/README.md) | 鱼、渔具、作物和动物储备；基础钓鱼已使用部分鱼和竹竿 | `art/sources/base/` |
| [content_v1](content_v1/README.md) | 全品类原创资源，按 animals/buildings/characters/objects/terrain/ui 等分类；部分物件已使用 | `art/sources/content_v1/` |

查某一张图的尺寸、用途和生成来源，先查看批次的 `catalog.json`；图集排列、生长/动画状态和切片坐标随批次保留。全部预览在 `art/previews/<批次>/`，不参与游戏加载。不要仅凭目录存在就宣布对应玩法已经完成。
