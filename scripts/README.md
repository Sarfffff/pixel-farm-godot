# 运行时代码

代码按业务职责归类；Godot 节点名称、组名和保存分区不因目录调整而改变。`scenes/` 存节点树，`data/` 存 Resource 配置，`scripts/data/` 存这些配置对应的类定义。

| 目录 | 责任与入口 |
| --- | --- |
| `core/` | 组合根 `game_session.gd` 和跨系统每日用例 `daily_cycle.gd`；跨模块接线从这里开始 |
| `platform/` | 引擎服务：设置、音频 Autoload、退出清理，以及默认关闭/发行禁用的开发输入适配 |
| `time/` | 日期、时钟与天气 |
| `economy/` | 金币与交易用例；面板不自行实现扣款 |
| `inventory/` | 背包、堆叠及仓库数据结构 |
| `progression/` | 引导、订单、社区、好感和工具升级；`quest_log.gd` 是章节任务事实，`quest_service.gd` 是接受/进度/交付用例 |
| `progression/mailbox_state.gd`、`progression/mail_service.gd` | 邮件投递/阅读/附件事实、整批领取与保存端口；通过 `GameSession.mail` 供整合层调用 |
| `progression/chapter_flow.gd`、`progression/crafting_service.gd` | 第一章正常玩法边界、来信与事件安排；固定工作台即时制作，复用唯一库存与章节资格 |
| `activities/` | 农场活动入口和独立钓鱼会话 |
| `events/` | B2-04 一次性条件事件、同步结果用例、独立过场与对话；输入租约、相机和保存接线见[模块契约](events/README.md) |
| `animals/` | 动物适配、鸡舍、蛋和状态机；`states/` 存可注册状态 |
| `player/` | 玩家移动、工具动作和体力 |
| `npcs/` | 村民与店主的场景适配 |
| `regions/` | 正式区域入口/返回点、场景创建、工具交互、采集服务及资源纯状态；规则和路线在data/maps，接入边界见地图文档第8节 |
| `world/farming/` | 耕地、作物和土壤连边；`farm_ground_rules.gd` 按完整植物占地查询河水、道路、桥面和坡地 |
| `world/resources/` | 树木、石头、采矿、浆果与杂草采集 |
| `world/interiors/` | 房屋管理、室内、门、睡觉点与箱子入口 |
| `world/interactions/` | 世界交互适配：活动物件、订单箱、社区入口 |
| `world/navigation/`、`world/maps/` | 网格导航与区域布局/预览适配 |
| `presentation/` | 相机、遮挡、昼夜、天气粒子、阴影、头像、灯光与音效表现 |
| `ui/common/` | 面板基类、模态协调和通用物品格 |
| `ui/panels/` | 背包、商店、对话、订单、社区、活动和帮助面板 |
| `ui/menus/` | 标题、暂停和设置菜单 |
| `ui/hud/` | HUD、快捷栏、提示、日报、淡入淡出与金币反馈 |
| `ui/presenters/` | 视图数据整理与意图适配；调用业务服务，不创建第二份状态或重写规则 |
| `data/` | 自定义 Resource 类，实例配置在根目录 `data/` |
| `persistence/` | 保存服务、分区注册、迁移、JSON存储和世界/农田编解码 |

开发顺序：先读 [架构规范](../docs/06-架构与开发规范.md) 与 [总纲](../docs/04-后续开发总纲.md)，从配置或应用用例定位模块，再调整场景适配。不要重新建立 `scripts/systems/` 或把不同职责的脚本直接堆到 `world/`、`ui/` 根目录。

代码移动必须连同 `.gd.uid` 保留，并同步 preload/load、场景 ext_resource、Autoload、测试和生成器中的路径。目录校验：`python tools/maintenance/audit_project_layout.py`；逻辑回归：`pwsh -NoProfile -File tools/run_checks.ps1`。
