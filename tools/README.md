# tools · 离线工具脚本

GDScript 离线工具以 `extends SceneTree` 的形式运行，不进入游戏本体，只在命令行/编辑器里执行一次。
统一调用方式（在项目根目录）：

```bash
godot --headless --path . --script res://tools/<子目录>/<脚本>.gd
```

退出码 `0` 还需结合日志判断；出现 `SCRIPT ERROR` 或断言失败不能算通过。会写盘的检查必须隔离 `user://`，不能对真实玩家存档运行。

回归统一入口（复制固定源码/素材快照、资源预检、每套独立用户目录）：

```powershell
pwsh -NoProfile -File tools/run_checks.ps1
pwsh -NoProfile -File tools/run_checks.ps1 -Suites check_architecture,check_basic_loop
pwsh -NoProfile -File tools/run_checks.ps1 -Suites check_basic_loop -Packaged
pwsh -NoProfile -File tools/run_checks.ps1 -Suites check_region_gameplay,check_basic_loop -Windowed -Preview
```

直接在正式项目运行 `tools/check` 脚本会被隔离保护拒绝。上面的 Godot 通用调用只用于 art/build 等离线工具；回归请使用 PowerShell 入口。架构与扩展要求见 `docs/06-架构与开发规范.md`。

全量回归同时显式编译所有交付脚本、执行功能套件、导出 PCK，并从空目录运行包内经营与保存流程，避免读取工作区资源掩盖漏包。任何脚本/引擎错误、退出泄漏或缺失末尾标记均失败。指定套件时追加 `-Packaged` 可复测打包；`-Windowed` 使用实际窗口渲染。检查结束通过 `lib/check_lifecycle.gd` 清理音频，不能直接打印 PASS 后跳过清理退出。


`-Windowed` 使用兼容渲染器运行实际窗口，`-Preview` 向支持截图的套件传递 `--preview`。区域截图保存在本轮隔离用户目录，路径见该套日志的 `capture` 行。所有检查都要求生命周期结束标记，脚本/引擎错误及退出资源泄漏告警均判为失败。

## 目录

| 目录 | 职责 |
| --- | --- |
| `build/` | 生成或重建游戏资源（场景、动画帧） |
| `art/` | 原始大图切片、量化和图集整理；只处理已保存的图片 |
| `preview/` | 素材总览和真实游戏画面的渲染工具 |
| `maintenance/` | 目录规范、旧路径和资源引用检查 |
| `check/` | 隔离回归自检，可选窗口复测；改完功能按范围运行 |
| `lib/` | 被上面几类脚本共用的纯数据/纯函数模块，不单独运行 |

## build · 资源生成

| 脚本 | 作用 |
| --- | --- |
| `build_shop_interior.gd` | 重建杂货店室内、柜台/货架/店主、门和相机边界 |
| `build_farm_map.gd` | 从零构建 40×30 农场并覆写 `scenes/world/farm.tscn`（改动布局后跑一次） |
| `refresh_farm_paths.gd` | 只刷新现有农场的道路格子与桥/路贴图引用，保留道具、实例和持久身份 |
| `build_region_previews.gd` | 从首批地形和资源创建独立TileSet、六区域配置、28资源定义及六张原生地图样板；不覆盖主农场 |
| `build_player_frames.gd` | 从动作图集切帧，写入 `scenes/player/player_frames.tres` 的 8 个方向动画 |
| `build_bgm.gd` | 波表合成三首原创循环 BGM（`menu` / `farm_day` / `farm_night`），写入 `assets/audio/bgm/`，WAV 内带 smpl 循环块 |
| `build_sfx.gd` | 离线合成 10 个操作音效（锄地/浇水/播种/收获/砍树/采矿/金币/UI/入睡/脚步），写入 `assets/audio/sfx/`；**新生成的 wav 需要 `godot --headless --path . --import` 后才可加载** |
| `build_house_interior.gd` | 生成农舍室内场景 `scenes/world/house_interior.tscn`（27×19 房间、地板/墙层、家具表与家具碰撞、门、床边睡觉点与醒来点） |

## art · 素材流水线

| 脚本 | 作用 |
| --- | --- |
| `prepare_building_art.gd` | 住宅/设施外观、图标、建筑catalog与预览 |
| `prepare_tree_art.gd` | 树木、果树、果实和农田摆设成品 |
| `prepare_npc_art.gd` | NPC四向素材、透明边缘与脚底对齐 |
| `build_npc_walk_frames.gd` | 从NPC方向帧构建迈步动画图集 |
| `prepare_held_tools_art.gd` | 手持工具方向握持姿势与图集 |
| `prepare_pickaxe_art.gd` | 石镐方向动作、背包图标与预览 |
| `prepare_farm_art.gd` | 角色动作 / 作物生长 / 物品图标：均分切片、最近邻缩放、二值 Alpha、统一落脚点 |
| `prepare_world_region_art.gd` | 首批地图素材：16种地表、28类资源、4096种地形过渡组合；只整理已保存的ImageGen原图 |
| `prepare_presentation_art.gd` | 从四张原创原图整理53张建筑、家具、设备状态、头像和季节素材；统一尺寸、色板、Alpha与脚底 |
| `prepare_farm_style_art.gd` | 将重制的作物、野浆果三状态、采集物和种子袋切成 31 张统一风格透明贴图 |
| `prepare_terrain_art.gd` | 用原素材 8×8 象限拼出岸线图集；当前桥/路由 `prepare_path_bridge_art.gd` 整理 |
| `prepare_path_bridge_art.gd` | 整理 `art/sources/terrain_v2` 的ImageGen原图，输出当前木桥与四邻接土路图集；总览在 `art/previews/terrain_v2` |
| `prepare_inventory_art.gd` | 把背包 UI 原图切成九宫格面板、格子态与详情底板，并压到 16 色 |
| `prepare_expansion_art.gd` | 扩展素材：6 种作物、12 种鱼、8 件渔具、6 种动物的透明 PNG 与 16×16 图标 |
| `prepare_content_art.gd` | 原创全品类素材：实际网格识别、统一色板、分类切片、图标与 SpriteFrames |

原始生成图在 `art/sources/` 按批次存放，早期大图在 `art/sources/base/`（整个art目录不参与引擎导入），脚本用 `Image.load_from_file()` 直接读文件，成品写入 `assets/textures/`、`assets/packs/` 或 `assets/ui/` 对应目录。


## preview · 素材与实景预览

脚本位于 `tools/preview/`。素材总览输出到 `art/previews/`，游戏实景截图输出到 `build/` 或 `docs/screenshots/`；这些输出不作为运行时素材。

| 脚本 | 作用 |
| --- | --- |
| `preview_presentation.gd` | 关闭自动读档，只操作内存场景，生成20张日夜、四季、雨雪、室内与UI真实渲染截图到 `build/presentation-preview/` |
| `preview_terrain_art.gd` | 关闭自动读档与保存组，生成两桥、道路、总览及旧档浆果纠偏实景到 `build/terrain-v2/` |
| `preview_world_regions.gd` | 真实渲染六张区域地图、总览和28资源标注页，输出到`art/previews/world_regions_v1/` |
| `preview_farm_style.gd` | 在实际农场对照三种野浆果状态及新旧作物，截图输出到 `build/farm-previews/` |
| `preview_farm_art.gd` | 渲染已接入素材的验收页 |
| `preview_expansion_art.gd` | 渲染扩展素材的验收页 |
| `preview_content_art.gd` | 渲染原创全品类素材库的总览和分类页 |

## check · 回归自检

所有检查通过本页顶部的PowerShell隔离入口运行；正式项目直接执行检查脚本会被拒绝。需要截图时使用 `-Windowed -Preview`，输出位置以套件日志为准，不能将原生渲染等同于完整键鼠试玩。

| 脚本 | 覆盖内容 |
| --- | --- |
| `check_compilation.gd` | 显式编译运行脚本、离线工具及插件 |
| `check_development_controls.gd` | 开发快捷键默认禁用/显式启用、真实N输入、模态/动作/休息排斥、重入/同帧保护和离树解绑；追加 `-EnableDevTools` 验证开发启用路径 |
| `check_crop_seasons.gd` | 换季枯萎、成熟/复收/跨季、免费清理、旧档与重复恢复、种子风险信息及Presenter替换/解绑；支持 `-Windowed -Preview` 检查商店布局 |
| `check_layer_boundaries.gd` | 无具体View的休息/仓储/读档、替换MVP视图、重复请求与保存失败、模型通知完整性及过场销毁清理 |
| `check_save_validation.gd` | JSON内层类型、元数据查询与不兼容版本写保护 |
| `check_resource_safety.gd` | 原农场砍树/清桩整批容量、命中时收益与动画中读档、四季零金币恢复、玩家/耕地占位和连续14日木石再生 |
| `check_region_gameplay.gd` | 六区域路标切换、工具命中帧、掉落与满包整包保留、体力、占位延迟再生、离区作物生长、磁盘重启读档、旧档兼容和野外累倒；支持三张实景截图 |
| `check_berries.gd` | 野浆果生成、采果、种植生长、可见叶丛避让水面/路面，以及异常旧档搬移和重复读档 |
| `check_friendship.gd` | 好感、交谈、送礼、每日计数与保存 |
| `check_interior_layout.gd` | 家具规格、落点、碰撞、地毯层级与门口通道 |
| `smoke_check.gd` | 作物资源头 / 无 BOM 编码及加载、输入映射、玩家动画与场景、地图结构、道具碰撞、主场景、背包装载 |
| `check_basic_loop.gd` | 正常开局两轮生产、真实木石、铜水壶三格效果、再投资目标、雨天、JSON/磁盘存档与旧档迁移；需隔离用户目录，`-- --preview` 输出三张真实渲染截图 |
| `check_world_regions.gd` | 地表/资源规格、确定性生成、占地不重叠/不落水/不堵路、主路与资源可达、原生场景和实际物理碰撞；不读写玩家槽位 |
| `check_farm_interactions.gd` | 目标锁定、动画命中时序、障碍阻挡、浇水、倒树碰撞 |
| `check_farm_terrain.gd` | 地形分层、水体格子、岸线与桥梁数据一致性、坡地与全图可达性 |
| `check_inventory.gd` | 堆叠、溢出、取出、满包、面板开关与输入锁 |
| `check_inventory_exchange.gd` | B3扣料后净容量、多产物共享槽位、失败无改、外层提交与通知重入、非法数量及JSON往返 |
| `check_inventory_hotbar_camera.gd` | 分类映射、快捷位引用与拖放、种子耗尽、旧档迁移、镜头缩放边界 |
| `check_crops.gd` | 播种、浇水推进、成熟、收获、满包保留 |
| `check_shop.gd` | 初始金币、买卖结算、金币不足、背包满、面板与 HUD 同步 |
| `check_calendar.gd` | 日期推进、睡觉结算、存读档一致性、坏档容错 |
| `check_progression.gd` | 采集、订单期限、引导、铜水壶三格浇水、旧档兼容（会写测试存档） |
| `check_survival.gd` | 体力扣减与拦截、睡醒回满、雨天自动浇水、HUD 联动、存档往返 |
| `check_goals.gd` | 每日订单、交付结算、社区阶段上缴、种子解锁、存档往返 |
| `check_quests.gd` | 章节任务：模型状态机与编解码、数据契约、交付事务、满包阻塞、观察者重入、写档失败与磁盘往返 |
| `check_story_events.gd` | B2-04 六类条件、同步一次性提交、完整观看/跳过、重复读档、替代对话/解绑、输入与相机交接、淡出/等待/走位中销毁；`-Windowed -Preview` 输出选项实景 |
| `check_mailbox.gd` | 邮件投递/阅读、整批附件容量、防重入、保存失败重试、旧档/磁盘恢复、模态与Presenter替换；`-Windowed -Preview` 输出信箱实景 |
| `check_quest_integration.gd` | 六任务NPC按钮链、延迟室内绑定、整批奖励与重入、K日志、真实F木桌制作、章节来信、过场租约/跳过/完整观看/读档取消、保存失败与销毁；`-Windowed -Preview`输出交付/工作台/集市截图 |
| `check_farm_activities.gd` | 木箱、采集、加工、差异作物与复收、社区摆设、基础钓鱼、JSON 存档、模态输入 |
| `check_architecture.gd` | 动物状态/快照/交易策略扩展契约、原子存储故障、天气日期、世界恢复、模态锁与导航增删 |
| `check_animals.gd` | 动物状态循环、鸡实际位移/四步循环/左右镜像、斜向/纵向/停步、全部备用动物动画的镜像与四向回退、作息/碰撞/模态、每日下蛋与蛋存档；`-Windowed -Preview` 输出步态对照图 |
| `check_npcs.gd` | 4 位 NPC 的素材与场景（3×4 行走图集）、三位村民的四方向迈步循环、抵达站姿、对话暂停与恢复、寻路与商店交互 |
| `check_pickaxe.gd` | 石镐采矿与岩石四方向表现 |
| `check_held_tools.gd` | 5 种手持工具 × 4 方向的显示 |
| `check_pause.gd` | Esc 优先级、暂停/恢复、保存、设置入口、标题界面继续按钮 |
| `check_settings.gd` | 音量换算边界、AudioManager 联动、设置写盘重读、设置面板开关与尺寸 |
| `check_house.gd` | 门口进屋、农场隐藏与室内显示、玩家 reparent 与落点、相机边界切换、存档取门外坐标、出门复原 |
| `check_release.gd` | 发行就绪：导出预设字段、排除规则、CREDITS 覆盖、版本号、外部素材隔离（无需导出模板） |
| `check_ui_layout.gd` | 不同比例下的 HUD 与模态窗口布局 |
| `check_audio.gd` | 曲目加载与循环点、交叉淡入淡出、昼夜换曲、标题曲目、暂停不中断 |
| `check_content_art.gd` | 原创素材清单到齐、来源约束、唯一 ID、尺寸、透明度与图集像素一致性 |
| `check_presentation.gd` | 四季/草坡/杂草、昼夜灯光、透明建筑边界、室内箱子、真实加工奖励、四人表情、共享主题及存档往返 |

`check_farm_interactions.gd`、`check_farm_terrain.gd`、`check_farm_activities.gd` 追加 `-- --preview` 可在有窗口模式下输出截图（前两者写 `user://farm_previews/` 等目录，后者写 `docs/screenshots/`）。`check_progression.gd` 会写入测试存档，建议用独立用户数据目录运行。

## lib · 共用模块

| 脚本 | 作用 |
| --- | --- |
| `check_lifecycle.gd` | 检查结束后的场景与音频退出清理 |
| `check_safety.gd` | 回归独立user目录保护 |
| `packaged_story_events.gd` | 由包外 packaged_smoke 驱动，从实际PCK加载事件/子资源/独立对话，验证跳过、一次性提交和磁盘恢复 |
| `world_region_catalog.gd` | 区域地表/资源与原图排列对应 |
| `farm_landscape.gd` | 河流、池塘、岸线、桥、草坡的格子数据，保证画面与碰撞同源 |
| `terrain_tiles.gd` | 岸线/桥梁图集的拼接算法与输出路径 |
| `content_art_utils.gd` | 独立生成图的网格定位、去杂边、最近邻整理与 48 色统一色板 |

## 常用组合

`check/check_inventory_hotbar_camera.gd` 验证分类、数字绑定、快捷位拖放、库存同步、满旧档迁移及镜头边界。`art/build_tool_icons.gd` 从可编辑像素轮廓生成统一工具图标。窗口显示基准现为 640×360。

新增 `check/check_progression.gd` 验证本轮完整循环（时钟、自然采集纤维、跨天订单、引导、铜水壶、存档兼容与强制收工）。运行：`pwsh -NoProfile -File tools/run_checks.ps1 -Suites check_progression`。检查会写入测试存档，请在独立用户数据目录执行。

```bash
# 改了地形布局
godot --headless --path . --script res://tools/build/build_farm_map.gd
pwsh -NoProfile -File tools/run_checks.ps1 -Suites check_farm_terrain

# 改了角色动作或作物贴图
godot --headless --path . --script res://tools/art/prepare_farm_art.gd
godot --headless --path . --script res://tools/build/build_player_frames.gd

# 提交前
pwsh -NoProfile -File tools/run_checks.ps1 -Suites smoke_check
```

## maintenance · 目录维护

`python tools/maintenance/audit_project_layout.py` 校验目录边界、旧路径、脚本UID和运行资源引用。追加 `--report build/organization/layout.json` 保存报告；`--repair-legacy-paths` 只修复映射表中已知的旧路径，不移动文件、不操作存档。完整规范见 `docs/07-目录与资源规范.md`。

`run_game.ps1` 是游戏启动入口；`run_checks.ps1` 是隔离回归入口。根目录原有三份重复GDScript已归档到 `archive/tools/`，不再作为执行入口。共享类如 `held_tool_painter.gd` 在 `tools/lib/`，不应直接执行。
