# 木桥与土路原图

`bridges_and_path.png` 由内置 ImageGen 原创生成，参考本项目农场实景的柔和鼠尾草绿、浅蜜色木材和棕色轮廓。完整提示词见 `prompt.txt`。未使用外部星露谷资源作为图片来源。

`tools/art/prepare_path_bridge_art.gd` 负责裁切、二值Alpha、最近邻和项目既有色板整理，输出80×48桥梁图集及64×64四邻接土路图集。桥的左右端、上下端和可重复中段分别取样；道路只为外露边界裁出草地留白。

成品在 `assets/textures/terrain/`，规格见该目录 `path_bridge_catalog.json`。素材总览在 `art/previews/terrain_v2/sheet.png`；游戏实景由 `tools/preview/preview_terrain_art.gd` 输出到 `build/terrain-v2/`。
