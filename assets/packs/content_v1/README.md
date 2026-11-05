# Pixel Farm · 原创全品类素材

以项目文档中的内容分类为范围，通过 **内置 ImageGen** 独立设计和生成；未从外部游戏资源包读取、切片、复制或描摹图片。

本版已完成：**2,452 张基础切片 + 368 张图标 + 62 张成品图集**，并附 **154 组 SpriteFrames**。总览共 6 页，逐类预览共 62 页。

- [当前素材入口与接入规范](../../../docs/03-素材与资产.md)
- [历史外部清单与完整规格](../../../archive/docs/2026-11-06-before-consolidation/03-素材与资产.md)
- [全部生成提示词与每格制作计划](generation_plan.json)
- [实际素材目录](catalog.json)：路径、尺寸、锚点、原图与图集区域
- [逐类覆盖状态](coverage.json)
- [第一张 Godot 渲染总览](../../../art/previews/content_v1/overview_01.png)

正式 PNG 按 `animals / buildings / characters / portraits / terrain / maps / crops / objects / items / icons / ui / effects / minigames` 分类。原图在项目的 `art/sources/content_v1/`，已排除引擎导入。整理脚本位于 `tools/art/prepare_content_art.gd`。

这是可供后续接入的美术资源库，不含新玩法逻辑或可玩场景配置。生成任务与实际完成情况分开记录，未到齐的图集会明确列入 `catalog.json` 的 `missing_sources`。
