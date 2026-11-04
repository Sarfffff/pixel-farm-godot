# 当前农场表现素材

本批使用内置 ImageGen 原创生成，参考项目已有猫村民、浆果和农场配色；未复制星露谷资源。四次完整提示词见 [prompts.json](../../../art/sources/presentation_v3/prompts.json)，原图在同目录。`catalog.json` 列出53张整理后的PNG。

| 分类 | 数量与尺寸 | 当前接入 |
| --- | --- | --- |
| `structures` | 4张96×96透明画布 | 农舍、商店、社区建筑、鸡舍；共用脚底基线95 |
| `furniture` | 24张32×32 | 农舍和商店的家具、地毯；家具脚底基线31 |
| `objects` | 5张32×32 | 箱子开合、腌制设备待机/加工/完成 |
| `portraits` | 12张48×48 | 四位村民，各有平静、开心、担忧三种表情 |
| `tiles` | 8张16×16 | 木地板、墙面和四季地表；春季保留原地图草地纹理 |

风格约定：16px地图格、最近邻过滤；奶油色、鼠尾草绿、暖木棕和低饱和陶红；褐色细轮廓，减少碎点和高反差纹理。透明精灵采用二值Alpha。建筑画布留白不属于碰撞或遮挡范围，使用 `VisibleSpriteBounds` 的可见范围。家具按0.75比例放置，不按原始生成图尺寸直接入场。

季节只改变地表和植被，保留建筑材质与果实辨识度。天气粒子、灯光、接触阴影及设备动效由运行时表现脚本生成，不烘焙进物品图标，也不加入保存字段。

重建素材：`godot --headless --path . --script res://tools/art/prepare_presentation_art.gd`，随后执行编辑器资源导入。此操作只整理已保存原图，不重新生成图片。原生画面检查使用 `tools/preview/preview_presentation.gd`，输出 `build/presentation-preview/`。
