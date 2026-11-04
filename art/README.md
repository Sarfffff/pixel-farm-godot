# 美术工作区

这里保存制作资料；游戏可加载的成品统一在 [assets](../assets/README.md)。整个目录由 `.gdignore` 和导出排除规则隔离，不能把这里的原图当作场景贴图引用。

| 目录 | 内容 | 如何使用 |
| --- | --- | --- |
| `sources/base/` | 早期角色动作、物品、建筑、树木等原创生成大图 | 对应 `tools/art/prepare_*` 的 `SOURCE`；保留原图，重新切片时读取 |
| `sources/content_v1/` | 全品类原创素材库原图、提示词 | 对应 `assets/packs/content_v1/` |
| `sources/farm_style_v2/` | 作物、浆果风格修订原图 | 对应 `assets/packs/farm_style_v2/` |
| `sources/presentation_v3/` | 当前建筑、家具、头像和地表原图及完整提示词 | 对应 `assets/packs/presentation_v3/` |
| `sources/world_regions_v1/` | 区域地表与资源原图、提示词 | 对应 `assets/packs/world_regions_v1/` |
| `sources/npc_v1/` | NPC 原始生成图 | 对应 `assets/textures/characters/npcs_v1/` |
| `previews/` | 放大总览、带标签的验收页 | 按素材类别或批次归档；由 `tools/preview/` 或切片工具输出，不是游戏精灵 |
| `reference/stardew_valley/` | 原有星露谷资源及目录结构 | 仅作内容清单对照，不作为本项目图片来源 |

新增原图先按用途/批次归入 `sources/`，同时记录提示词和来源；切片与量化由 `tools/art/` 完成。成品放进 `assets/textures/`、`assets/ui/` 或完整的 `assets/packs/<批次>/`，随后更新对应 catalog。不要把预览图重新放回成品目录。

目录全貌和迁移对应见 [目录与资源规范](../docs/07-目录与资源规范.md)。
