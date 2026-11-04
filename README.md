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
| 快捷栏 | 已完成 | 八格物品引用，可拖拽或按数字绑定；数字右上、数量右下，与背包实时同步 |
| 播种 · 作物生长 | 已完成 | 胡萝卜、番茄、白萝卜、小麦；浇水后过夜生长，成熟后收获入包 |
| 背包 | 已完成 | 30 格；全部 / 工具 / 种子 / 收获 / 材料分类，支持拖拽整理与快捷位绑定 |
| 商店 · 金币 | 已完成 | 买种子、卖物品、花金币和木石升级铜水壶 |
| 昼夜 · 存档 | 已完成 | 时间按帧累计，02:00 收工；睡觉自动保存，三个存档槽 |
| 杂草 · 纤维 | 已完成 | 田边按 E 清理，每丛 2 纤维 / 2 体力，每天最多再生 3 丛 |
| 订单 · 社区 | 已完成 | 首单收纤维；订单保留五天，社区分阶段上缴并解锁种子 |
| 引导 · HUD | 已完成 | 可收起手记、首次种植至出售引导、统一状态牌和工具提示 |
| 鸡蛋 · 天气 · 体力 | 已完成 | 每日产蛋，雨天自动浇水，干活耗体力、睡醒恢复 |
| 木箱 · 采集 · 加工 | 已完成 | 屋右木箱存取，三种采集物每日补长，3 个番茄过夜腌制 |
| 土豆 · 蓝莓 | 已完成 | 土豆 2 晚成熟；蓝莓首收 5 晚、复收 2 晚，每次产出 2 份 |
| 基础钓鱼 | 已完成 | 商店买竹鱼竿，池塘北岸按 E 投竿；鲫鱼 / 鲤鱼入包并出售 |
| 社区变化 · 明日预告 | 已完成 | 围栏、摊位、招牌随社区阶段出现，睡前预告新一天的产出 |
| 设置 · 音量 · 窗口 · 流速 | 已完成 | 暂停菜单进「设置」：音乐/音效滑条、窗口/全屏、时间流速（慢/标准/快），偏好存 `user://settings.cfg` |
| 季节 | 已完成 | 一季 28 天、一年 112 天，由天数推导（旧档自动兼容）；HUD 显示「春 3日」，各季有不同色调，作物只能在对应季节播种 |
| 音乐 · 音效 | 已完成 | 3 首循环 BGM + 10 个操作音效（脚步、UI 点击、入睡、锄地/浇水/收获等），全部离线合成 |
| 村民 · 寻路 · 对话 | 已完成 | 园艺师/木匠/渔夫按日程在农场里走（格子 A* 自动避开水与道具），按 E 多句对话；店主仍是固定摊位 |
| 可进入的房子 · 睡觉 | 已完成 | 门口按 E 带开门音与黑屏过场进屋（不切场景），家具可碰撞、**贴着床才能睡**；白天小睡到 20:00（不换天），18:00 后上床才过夜、天亮在床边醒来 |
| 可进入的杂货店 | 已完成 | 农场新增店铺建筑，门口按 E 进店；店主在柜台后（09:00–17:00 营业，打烊只聊天），店里有货架与展示柜 |
| 室内可用家具 | 已完成 | 屋里有木箱（按 E 存取 24 格仓库）；背包内 `Delete` 丢 1 个（工具不可丢） |

## 操作

| 按键 | 作用 |
| --- | --- |
| `W A S D` / 方向键 | 移动 |
| `空格` / 鼠标左键 | 使用当前工具（对面前那一格） |
| `Q` / `E` | 上一个 / 下一个工具；面前或身边有成熟作物时 `E` 优先收获 |
| `1`–`8` | 选择快捷位；背包打开时将选中物品绑定到对应快捷位 |
| `B` | 打开 / 关闭背包 |
| `J` | 展开 / 收起农场手记 |
| `E` | 靠近交互点对话、睡觉、捡蛋或清理杂草；优先收获成熟作物 |
| `F1` / `Esc` | 按键说明 / 暂停菜单（内有设置：音乐音量、音效音量、窗口模式） |
| `Tab` / `Delete` | 打开背包 / 背包内丢弃选中的 1 个（工具不可丢） |
| 滚轮 / `+` `-` / `Home` | 镜头缩放 / 恢复默认视野 |
| `F11` | 切换全屏 |
| `N` | 推进一天（调试入口） |

工具一次作用于面前一格，鼠标左键与空格使用同一目标。浅黄色框表示可操作，水壶为浅蓝色；暗红色表示当前格不可操作。动作期间锁定朝向、目标和工具，命中帧才改变地块或伤害树木；无效操作不会空挥。种植区内允许独立开新田，建筑、石头和树干会阻止开垦。

选择锄头时淡显可种植区，工具栏上方说明当前操作。`3` 拿种子袋，`Q/E` 换种子，图标与库存同步。铜水壶在商店底部购买：600 金币、6 木材、4 石头；升级后覆盖目标与左右两格（按朝向旋转），一次消耗 3 体力。新内容与验收见 [系统设计 · 循环与界面改进](docs/02-系统设计.md)。

## 快速开始

默认窗口为 1600×900，显示基准 640×360，默认镜头约显示 32×18 格；窗口与镜头缩放独立于 UI。具体设计和背包迁移规则见 [系统设计 · 视野与背包互通](docs/02-系统设计.md)。

需要 **Godot 4.7.x**（Forward+ 渲染，Windows 上默认走 D3D12）。

新活动的操作、数值、存档规则见 [系统设计 · 素材接入与农场新活动](docs/02-系统设计.md)。

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
godot --headless --path . --script res://tools/check/check_farm_activities.gd
```

`tools/check/` 下共 23 个自检脚本（背包快捷键、商店、体力天气、订单进程、NPC、房屋进出、暂停、设置、音频、UI 布局、发行就绪等），完整清单与分组见 [`tools/README.md`](tools/README.md)。

## 打包发布

导出预设已入库（`export_presets.cfg`，Windows x86_64、单文件 exe、产品名 `Pixel Farm`）。**先装导出模板**：编辑器 → 编辑器 → 管理导出模板，下载 4.7.2 模板。

```bash
# 版本号在 project.godot 的 application/config/version
godot --headless --path . --script res://tools/check/check_release.gd   # 静态核对预设与版权文件
godot --headless --path . --export-pack "Windows Desktop" build/PixelFarm.pck   # 无模板也能验证打包内容
godot --headless --path . --export-release "Windows Desktop" build/PixelFarm.exe
```

发行包会排除 `tools/`、`docs/` 与外部参考素材 `星露谷物语素材/`；素材与音频来源见 [`CREDITS.md`](CREDITS.md)。

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
│   ├── systems/inventory.gd   # 背包：30 格堆叠、8 格快捷位、溢出返回、信号
│   ├── ui/                    # 工具栏、背包面板、飘字
│   └── data/                  # ItemData / CropData 两个 Resource 定义
├── data/
│   ├── items/                 # 物品数据（28 个 .tres，背包启动时扫描）
│   └── crops/                 # 作物数据（6 个 .tres，耕地脚本扫描）
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
| ✅ V0.6 | 背包、商店、金币与种植买卖循环 |
| ✅ V0.7 | 时钟天数、睡觉结算、三槽存档读档 |
| ✅ V0.8–V0.9 | 动物、订单、社区、引导、帮助、音效（脚步/界面/入睡）、设置面板、村民寻路与对话、可进入的房子 |
| 🟡 V1.0 | 导出预设与版权文件已就绪；只差装导出模板出 exe 与干净环境验收 |

## 文档

设计过程写在 `docs/` 里，按需查阅：

- [`docs/01-开发流程与路线图.md`](docs/01-开发流程与路线图.md) —— 开发阶段、每版游戏长什么样、参考项目对照
- [`docs/02-系统设计.md`](docs/02-系统设计.md) —— 各系统的设计取舍：工具耕地、地形、背包、作物、经济、时间存档、NPC、动物、订单、体力天气、界面
- [`docs/03-素材与资产.md`](docs/03-素材与资产.md) —— 素材清单、取区索引与原创素材库规范
- [`tools/README.md`](tools/README.md) —— 离线工具脚本索引与常用组合
- `CODEBUDDY.md` —— 环境要求与常用命令

## 素材说明

按外部资源清单独立生成的本项目画风素材统一放在 [`assets/generated/content_v1/`](assets/generated/content_v1/README.md)，分类、内容对照与验收方式见 [`docs/03-素材与资产.md`](docs/03-素材与资产.md)。原始外部包只保留清单对照，并由 `.gdignore` 排除导入和导出。

新增的鱼类、鱼竿、六种作物生长阶段和六种动物四向站姿见 [`assets/generated/expansion_v1/README.md`](assets/generated/expansion_v1/README.md)，含独立透明 PNG、16×16 图标、合并图集、素材目录和生成提示词，供后续钓鱼与养殖功能使用。

`assets/game/` 下的像素素材为免费素材包，仅用于本项目的学习与演示；如需商用请自行确认原始授权。代码部分可自由参考。
