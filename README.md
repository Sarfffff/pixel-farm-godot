# Pixel Farm · 像素农场

用 **Godot 4** 从零手写的 2D 像素农场游戏。目标很简单：做一个真正能玩完一天的种田游戏——走路、锄地、播种、浇水、收获、卖钱、睡觉进入下一天。

整个过程用 AI 结对开发（CodeBuddy + Godot AI MCP），刻意把"想法 → 场景 → 可玩版本 → 验收"的每一步都留在仓库里：文档、生成器脚本、冒烟自检都在版本控制内，而不是散落在本地。

![Godot](https://img.shields.io/badge/Godot-4.7-478CBF?logo=godotengine&logoColor=white)
![GDScript](https://img.shields.io/badge/Language-GDScript-355570)
![Style](https://img.shields.io/badge/Style-16%C3%9716%20Pixel-8a6d3b)
![Platform](https://img.shields.io/badge/Platform-Windows-0078D6?logo=windows&logoColor=white)

---

## 现在能玩到什么

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 40×30 农场地图 | 已完成 | 弯曲河流连通池塘、四帧水面、圆角岸线、两座可通行木桥、木板小路与草坡 |
| 角色移动 | 已完成 | 四向移动 + 8 方向动画，镜头平滑跟随并限制在地图内 |
| Y 轴遮挡 | 已完成 | 走到树/屋后面时角色被正确遮挡，挡视线时道具淡出到 55% |
| 锄地 / 浇水 | 已完成 | 四向角色动作、命中帧生效；种植区虚线、原因提示、方格耕地自动连片 |
| 砍树 | 已完成 | 独立横向挥斧，小树 2 次、大树与果树 3 次；摇晃、木屑、倒树，树桩保留碰撞 |
| 工具栏 | 已完成 | 锄头 / 水壶 / 种子 / 斧头四格，选中项高亮 |
| 播种 · 作物生长 | 已完成 | 胡萝卜、番茄两种作物；浇水推进一步，成熟后收获入包 |
| 背包 | 已完成 | 24 格堆叠、`B` 开关面板、入包飘字提示 |
| 商店 · 金币 | 待做 | V0.6 |
| 昼夜 · 存档 | 待做 | V0.7 |

## 操作

| 按键 | 作用 |
| --- | --- |
| `W A S D` / 方向键 | 移动 |
| `空格` / 鼠标左键 | 使用当前工具（对面前那一格） |
| `Q` / `E` | 上一个 / 下一个工具；面前或身边有成熟作物时 `E` 优先收获 |
| `1` `2` `3` `4` | 直接切换 锄头 / 水壶 / 种子 / 斧头 |
| `B` | 打开 / 关闭背包 |
| `N` | 推进一天（调试入口，V0.7 由时间系统接管） |

工具一次作用于面前一格，鼠标左键与空格使用同一目标。浅黄色框表示可操作，水壶为浅蓝色；暗红色表示当前格不可操作。动作期间锁定朝向、目标和工具，命中帧才改变地块或伤害树木；无效操作不会空挥。种植区内允许独立开新田，建筑、石头和树干会阻止开垦。

选择锄头时，虚线圈出可种植区，顶部说明无法开垦的原因。`3` 是种子袋，播种尚未开放；胡萝卜、芜菁、番茄、小麦的生长图和资源图标已预备，见 [新增素材索引](assets/generated/README.md)。

## 快速开始

需要 **Godot 4.7.x**（Forward+ 渲染，Windows 上默认走 D3D12）。

```bash
git clone <this-repo>
cd pixel-farm-godot
godot --path .          # 或用 Godot 编辑器打开 project.godot
```

命令行自检（退出码 0 即全部通过，不弹窗口）：

```bash
godot --headless --path . --script res://tools/check/smoke_check.gd
godot --headless --path . --script res://tools/check/check_farm_interactions.gd
godot --headless --path . --script res://tools/check/check_farm_terrain.gd
godot --headless --path . --script res://tools/check/check_inventory.gd
godot --headless --path . --script res://tools/check/check_crops.gd
```

## 目录结构

```
.
├── project.godot              # 引擎配置：320×180 视口、Nearest 过滤、Jolt 物理、输入映射
├── scenes/
│   ├── main.tscn              # 入口：农场 + 玩家 + 相机 + UI + Systems
│   ├── player/                # 玩家场景 + SpriteFrames（8 方向动画）
│   ├── world/                 # farm.tscn、crop.tscn、tile_cursor.tscn、props/ 可复用道具
│   └── ui/                    # toolbar.tscn、inventory_panel.tscn、toast.tscn
├── scripts/
│   ├── player/player.gd       # 移动、朝向记忆、动画切换、工具切换
│   ├── world/                 # 相机、遮挡淡出、耕地、作物、砍树、土壤连边、工具特效
│   ├── systems/inventory.gd   # 背包：24 格堆叠、溢出返回、信号
│   ├── ui/                    # 工具栏、背包面板、飘字
│   └── data/                  # ItemData / CropData 两个 Resource 定义
├── data/
│   ├── items/                 # 物品数据（8 个 .tres，背包启动时扫描）
│   └── crops/                 # 作物数据（作物表，耕地脚本扫描）
├── assets/
│   ├── game/                  # 原始素材包（16×16 像素，只读）
│   ├── generated/             # 生成产物：切片贴图、图集、UI 九宫格（sources/ 为原始大图，不导入）
│   └── tilesets/farm_terrain.tres
├── tools/                     # 离线工具脚本（详见 tools/README.md）
│   ├── build/                 # 重建 farm.tscn 与玩家动画帧
│   ├── art/                   # 素材切片、拼图集、预览页
│   ├── check/                 # 无窗口回归自检
│   └── lib/                   # 共用布局与瓦片数据
├── docs/                      # 流程、版本路线图、技术对照
└── addons/godot_ai/           # Godot AI 插件（第三方，只读）
```

## 工程约定

- **纯 Godot 4 语法**：`@export` / `@onready` / `signal` / `await`，全量静态类型，缩进用 Tab。
- **数据与逻辑分离**：可复用配置写成 `Resource` 并 `@export`，不在脚本里堆常量。
- **地图先立**：所有坐标、碰撞、交互格、存档格都以 40×30 的格子为基准，地图不稳就不往上叠功能。
- **场景由脚本生成**：地图和动画帧不靠手拖，`tools/` 下跑一次即可重建，改布局可复现。
- **每个版本都要能跑**：改完必须实际运行并检查控制台，不留 `SCRIPT ERROR`。

## 开发路线

| 版本 | 目标 |
| --- | --- |
| ✅ V0.1–V0.3 | 静态地图 → 能走路 → 能逛完整农场（遮挡、碰撞） |
| ✅ V0.4 | 能改地形：锄地、浇水、工具切换 |
| ✅ V0.5 | 能种地：播种、作物分阶段生长、收获入包 |
| 🟡 V0.6 | 背包已完成；商店与金币待做 —— 补上即第一个真实可玩循环 |
| ⬜ V0.7 | 能长期玩：时钟天数、睡觉结算、存档读档 |
| ⬜ V0.8–V0.9 | 养鸡产蛋线；引导与帮助界面 |
| ⬜ V1.0 | 完整 7 天体验闭环、正式 UI 与音效 |

## 文档

设计过程写在 `docs/` 里，按需查阅：

- `01-游戏开发全流程.md` —— 从创意到上线 11 个阶段，每阶段的产出物与验收标准
- `02-可玩版本演进路线图.md` —— 每个版本画面上有什么、玩家能做什么
- `03-参考项目技术对照.md` —— 参考项目的逐项 Godot 4 实现对照
- `04-工具交互与耕地美术.md` —— 同类游戏参考、当前交互取舍与验收方式
- `05-河流与地形.md` —— 河流布局、原素材拼接、桥梁碰撞、地图预览与重建命令
- `06-背包与物品.md` —— 格子与堆叠规则、物品 Resource、面板与飘字联动
- `07-作物与收获.md` —— 作物数据、生长与浇水推进、收获结算
- [`tools/README.md`](tools/README.md) —— 离线工具脚本索引与常用组合
- `CODEBUDDY.md` —— 环境要求与常用命令

## 素材说明

新增的鱼类、鱼竿、六种作物生长阶段和六种动物四向站姿见 [`assets/generated/expansion_v1/README.md`](assets/generated/expansion_v1/README.md)，含独立透明 PNG、16×16 图标、合并图集、素材目录和生成提示词，供后续钓鱼与养殖功能使用。

`assets/game/` 下的像素素材为免费素材包，仅用于本项目的学习与演示；如需商用请自行确认原始授权。代码部分可自由参考。
