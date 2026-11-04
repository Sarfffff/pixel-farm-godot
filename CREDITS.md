# 版权与素材来源 · Credits

本文件说明《Pixel Farm · 像素农场》里每一项内容的来源与授权，与 `docs/03-素材与资产.md` 互为索引。
**导出发行版只包含本节「一、二、三」列出的内容；第四节的外部参考素材不参与打包。**

---

## 一、代码

仓库内全部 GDScript（`scripts/`、`scenes/`、`tools/`）为本项目原创，随仓库发布。
开发过程由 AI 结对完成（CodeBuddy + Godot AI MCP），人工负责决策、验收与素材方向。

---

## 二、美术

游戏内所有图片来自仓库的 `assets/generated/`，**全部为独立生成或手写整理，不含任何第三方素材的切片、复制或描摹**：

| 目录 | 内容 | 制作方式 |
| --- | --- | --- |
| `assets/generated/characters/` | 角色四向行走与工具动作、4 位 NPC | 内置 image_gen 生成 → `tools/art/prepare_*` 脚本做切片与像素对齐 |
| `assets/generated/crops/` | 6 种作物的生长阶段 | 同上 |
| `assets/generated/items/` | 种子、材料、收获物图标 | 同上 |
| `assets/generated/buildings/` | 20 栋建筑外观（住宅 6 + 设施 14） | 同上 |
| `assets/generated/content_v1/` | 全品类素材库：家具、室内、动物、特效、图标、头像 | 同上 |
| `assets/generated/expansion_v1/` | 鱼类、渔具、加工品等扩展素材 | 同上 |
| `assets/generated/ui/` | 界面贴图 | 同上 |
| `assets/tilesets/` | 耕地、地形、房屋室内瓦片集 | 由上述贴图编排 |
| `icon.svg` | 应用图标 | 本项目绘制 |

生成任务、提示词与切片坐标分别记录在各目录的 `prompts.json` / `manifest.json` / `catalog.json`，可逐项追溯。

---

## 三、音频

`assets/audio/` 下 **13 个 WAV 全部由本项目的离线合成脚本生成**，没有任何采样或第三方音源：

| 文件 | 数量 | 生成脚本 |
| --- | --- | --- |
| `audio/bgm/menu.wav`、`farm_day.wav`、`farm_night.wav` | 3 首循环 BGM | `tools/build/build_bgm.gd`（波表合成，WAV 内带 smpl 循环块） |
| `audio/sfx/*.wav` | 10 个操作音效：锄地 / 浇水 / 播种 / 收获 / 砍树 / 采矿 / 金币 / 界面点击 / 入睡 / 脚步 | `tools/build/build_sfx.gd`（正弦 + 噪声合成） |

重新生成：

```bash
godot --headless --path . --script res://tools/build/build_bgm.gd
godot --headless --path . --script res://tools/build/build_sfx.gd
# 新生成的 wav 需要导入一次才可加载
godot --headless --path . --import
```

---

## 四、不参与发行的外部素材（重要）

仓库根目录的 `星露谷物语素材/` 是《Stardew Valley》的解包美术资源，
版权归 **ConcernedApe** 所有，**仅作为"需要哪些内容"的清单对照**：

- 该目录下的 `.gdignore` 使其被引擎完全忽略，不会被导入；
- `export_presets.cfg` 的 `exclude_filter` 又显式排除了该目录，双重保证不会进入发行包；
- 项目内的对应美术全部按下文方针重新生成，**没有从该目录切片、复制或描摹**。

因此发行版本与该素材包无任何文件层面的关联。若日后分发仓库，应删除该目录。

---

## 五、引擎与运行时

| 组件 | 版本 | 许可 |
| --- | --- | --- |
| [Godot Engine](https://godotengine.org/) | 4.7.2 stable | MIT License，版权归 Godot Engine contributors |
| `addons/godot_ai` | 随仓库 | 开发期调试桥（MCP）。导出后没有编辑器连接时静默空转，不影响运行 |

字体：项目**未内置任何字体文件**，界面统一使用系统字体（`SystemFont`），不涉及字体授权问题。

---

## 六、发行清单核对

发行前请确认：

- [ ] 导出包内不含 `星露谷物语素材/`、`tools/`、`docs/`
- [ ] `assets/audio/` 只有本文件第三节列出的 13 个 WAV
- [ ] 本文件随发行包一起分发
- [ ] 版本号与 `project.godot` 的 `config/version`、`export_presets.cfg` 的 `application/product_version` 一致
