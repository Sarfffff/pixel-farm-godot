# 主农场设备放置（B3-03）

定义：`data/devices/*.tres`，物品：`wood_fence`、`storage_crate`。制作只给物品，放置消耗1件，空闲拆除返还1件。仅`home`；不含洒水器日结或多设备生产。

## 整合端口

`placement_service.gd` 为 RefCounted，由 GameSession 显式持有。

```gdscript
service.configure(bag, definitions, {
	"query": query_cells, "allowed": placement_allowed,
	"create": world.create, "update": world.update_instance,
	"remove": world.remove_instance, "restore": world.restore_instances,
	"save": save.save_game,
})
```

- `query(space_id: StringName, cells: Array[Vector2i], ignore_id: String, restoring: bool) -> Dictionary`：返回`{ok: bool, reason: String}`。整合层负责真实地表/边界、静态物件、作物/耕地、人物、门口/出口及通道可达；移动仅忽略目标设备自身，不能忽略其他物件。恢复时仍校验地表和静态安全区，可忽略临时人物。服务自己校验设备间重叠。
- `allowed(item_id: StringName) -> bool`：真实制作/摆放资格，未注入即拒绝；恢复、取箱、拆回已有物品不要求重新解锁。
- `create(definition: DeviceDefinition, record: Dictionary) -> bool`：只用可信Resource；失败必须清理半成品。服务也调用remove清理。创建期间服务busy，不能反向提交玩法。
- `update(record: Dictionary) -> bool`：失败保持原节点位置/朝向；成功后只更新表现。
- `remove(id: String) -> void`：立即移除碰撞和父节点，延迟销毁可用queue_free。
- `restore(definitions: Dictionary, records: Array[Dictionary]) -> bool`：先构建候选节点，全成功后替换；失败保留旧节点。服务校验后调用此端口，无奖励入口。
- `device_world.gd` 提供上述工厂。`configure(parent, cell_to_world)`，`cell_to_world(cell: Vector2i) -> Vector2`返回格子中心的世界坐标。`interacted(id)`由根线程按definition.storage_capacity分派：箱子调用储物箱Presenter.open_storage，围栏调用放置Presenter.open_move；`obstacle_changed`接导航重建。

公开服务：`preview(type_id, space_id, cell, facing, ignore_id="") -> Dictionary`、`place(...) -> String`（失败空串）、`move(id, space_id, cell, facing) -> bool`、`dismantle(id) -> bool`、`instance(id)`、`instances()`、`occupied_cells(space_id, ignore_id="")`、`definition(type_id)`、`definitions()`、`type_for_item(item_id)`、`deposit(id,item,count)`、`withdraw(...)`、`storage_count(id,item)`、`encode()`、`restore(data)->bool`、`retry_save/confirm_saved/release`。

`changed`、`placed(id)`、`moved(id)`、`removed(id)`、`save_failed`、`restore_failed(reason)`为公开通知。`busy/save_pending/last_rejection`供显示。库存使用根线程提供的`preview_exchange_batch/exchange_batch`，外层begin/end_update保证观察者看到设备与库存已经一起提交。保存失败保留已提交事实、明确提示并允许重试。

## UI与输入

`placement_panel.gd`（ModalPanel）+`placement_presenter.gd`提供设备目录、朝向、原因和提交按钮。Presenter.configure(service, view)，`open_place(type_id, cell)`与`open_move(id)`由根线程打开；`set_target(cell)`由地图鼠标/键盘选点适配调用。面板只发意图。世界`placement_preview.gd`接Presenter的`preview_changed(snapshot)`显示占地，根线程提供cell_to_world；关闭/解绑时清空预览。建议从当前持有设备物品进入摆放，沿用已有按键/鼠标路由；不要占用Q/E。

`device_storage_panel.gd`（ModalPanel）+`device_storage_presenter.gd`复用StackStore与StorageTransferService。Presenter.configure(service, bag, view)，`open_storage(instance_id)`，无需修改FarmActivities。储物箱Presenter.manage_requested(id)接放置Presenter.open_move：先关闭储物箱模态，再交出稳定ID。两个面板都须经ModalCoordinator注册，pauses_world=true；暂停期间地图选点输入适配须PROCESS_MODE_ALWAYS。存取不增加劳动收获；有内容、加工中或待领取的实例不允许移动/拆除。

## 保存

注册`devices`可选字典分区，`restore_missing=true`；在日期/库存/农场/区域之后、任务/事件之前。`save.saved`接`confirm_saved()`；`save.restoring`先关闭两个面板和清预览。编码schema=1、next_id、instances；每条含稳定id/type_id/space_id/cell/facing、operation和独立slots。缺分区清空动态设备，不迁移或复制原固定箱子/加工点。

坏结构、未知类型、重叠或世界重建失败整分区原子拒绝，保留当前实例并发restore_failed；整合层必须显示失败，不能将返回false当恢复成功。不会退款、发物资、开始加工或结算。节点/脚本路径不来自存档。

## 本轮验证边界

2026-11-08独立隔离检查：`check_placement`72项、`check_layer_boundaries`34项通过，均有退出生命周期完成标记，无脚本错误、引擎错误或退出资源泄漏。原始日志、results.json及完整源码指纹保留在`build/agent_c_checks/PixelFarmChecks_e7487b94be174f6fa18d6eb0a573dd19/`。使用本次进程TEMP/TMP切换到E盘，未修改全局环境变量或真实玩家槽位。

该成绩覆盖独立工厂、库存、仓储、模态及真实SaveSystem磁盘往返。正式主世界的地表/人物/门口/出口查询、输入与GameSession注册由整合线程接入后另行验收；未执行全量、原生窗口、PCK或人工试玩，不据此关闭B3整合门槛。

临时完整副本的清理命令被自动审批以`blocked by policy`拒绝；未删除项目素材，测试副本尚保留，交由整合线程统一回收。

## 2026-11-09 主农场端口契约补强

主线程已在 `game_session.gd::_placement_query` 接入真实地表（Ground/Water/Bridges/Paths）、耕地、门口±1×±2、玩家格与层1物理静态碰撞（移动时忽略目标设备自身），并注册 `devices` 分区；正式接线由主线程 `check_b3_integration` 覆盖。本专项不加载主场景，改用与正式端口一一对应的契约镜像回归服务侧行为：

- 水面/道路/耕地/门口/人物/静态物件（另含桥面、无地面）一律拒绝且 `reason` 非空；`restoring=true` 只忽略临时人物，地表、门口与静态物件仍拒绝。
- 端口参数契约：`preview` 传完整占地且 `restoring=false`；`move` 传稳定 `ignore_id`；`restore` 传 `restoring=true`。契约镜像与正式实现的一致性由主线程 `check_b3_integration` 在真实场景兜底；按 `AGENTS.md` 第20条与 `docs/06` 第33/67条，不用源码文本、节点数量或类数量代替行为验证，本检查也不读取 `game_session.gd` 源码文本（避免导出包中无 `.gd` 原文时误报）。
- 原子性复核：create 失败清理半成品、无幽灵碰撞、ID 不推进且原因可见；restore 失败保留旧节点、同一引用与内容并发 `restore_failed`；非空箱移动/拆除被拒且不影响另一箱；双箱存储与节点互不影响。
- `device_instance.hint()` 与正式 `[F]` 分派一致：箱子→储物箱面板，围栏→移动/拆除面板；已固化为断言。

玩家行为变化：无（仅新增自动回归断言）。存档影响：无（检查只写隔离 `user://`，不触碰真实玩家槽位，`devices` 分区字段未变）。

运行（本机无 `pwsh`，使用兼容的 Windows PowerShell 5.1）：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_checks.ps1 -Suites check_placement,check_inventory_exchange -TimeoutSeconds 300`。首次快照因并行工作区改动被入口以 `Files were removed during snapshot creation` 拒绝，按 `docs/06` 第156条保留失败记录后重新生成固定快照，未以忽略指纹方式运行混合版本。复测结果：`check_placement` 119 项（较 72 项基线新增 47 项）、`check_inventory_exchange` 63 项，均 0 failures、`[checks] lifecycle complete; exit=0`、`ExitResourceWarning=false`，日志无 `SCRIPT ERROR`/`ERROR`/`FAIL`。仅本次进程设置 TEMP/TMP 到 E 盘，未改全局环境变量或真实玩家槽位。

证据保留在 `build/placement-contract-checks/2026-11-09/`（两份原始日志、`results.json`、`import.log`、`source_manifest.txt` 指纹、本轮 `check_placement.gd` 及快照失败记录 `snapshot-failure-1.txt`）；本轮两份完整副本（`PixelFarmChecks_af2ea6e646394abf9a6a317868b87578` 失败副本、`PixelFarmChecks_91f56d61ea064fa49af08d41ecfb5a10` 成功副本）均已回收。按 `AGENTS.md` 第13条，详细交付记录与验证索引应由主线程汇总到 `docs/history/开发记录.md`、`docs/validation/`，总纲任务状态亦由主线程维护；本轮因用户限定的维护范围只落在模块 README 与 `build/` 证据目录。全量、原生窗口、PCK 与真人键鼠流程仍由主线程验收，本轮不据此关闭 B3-03 人工门槛。

## 外部状态锁与三态表现端口（2026-11-09）

`placement_service.set_lock_provider(provider: Callable)` 由主线程接线，签名为 `provider(device_id: String) -> String`。服务在既有内锁 `_locked_reason`（operation/slots）**之后**追加一次调用：返回非空 String 即拒绝 `move`/`dismantle`，并以该原因写入 `last_rejection`；未注入或 `Callable.is_valid() == false` 时保持现行为。调用被隔离在 `_external_lock_reason()`：任何非 String 结果（含运行时错误导致的空返回）统一收敛为 `设备状态不可用`，校验阶段始终正常返回，不半途退出事务、不泄漏 `busy`。GDScript 无 try/catch，专项用返回 `null`/非 String 的替身覆盖该路径，避免制造引擎 `SCRIPT ERROR`。provider 不进入 `encode()` 快照，不影响拆回物品、存档与 `restore()`；`release()` 清空该 Callable。加工状态的事实来自 AgentB 的加工服务，本模块只提供锁端口，不判断能否领取、不推进任务/事件进程。

`device_instance.set_state(state: Dictionary)` 接受 `{phase: StringName("idle|working|ready"), label: String}`，可选 `texture: Texture2D`（亦兼容未来定义上的 `<phase>_texture` 属性）。只改 Sprite2D 贴图、`hint()` 与可选 `StateLabel` 小标签，不读写库存、存档或 operation；缺贴图或非法 phase 一律回退 idle 原图与现有文案。`configure()` 重建与 `_exit_tree()` 释放时由 `clear_state()` 清空表现状态。hint：idle 为现有 `[F]` 文案，working 追加 `· 加工中`，ready 追加 `· 可领取`；箱子始终保留 `[F] 打开储物箱` 入口，`interacted(id)` 与按 `storage_capacity` 的分派不变。

专项新增 16 项断言：锁提供者拒绝移动/拆除与放行、provider 不进存档、异常（非 String/null）收敛且不泄漏 busy、放行后拆回物品与快照往返、带 provider 时任务/事件 operation 事实完整恢复、三态贴图/hint/小标签、缺图回退、非法 phase 回退、箱子入口不变、重建清空。既有 119 项断言全部保留。

验证命令：`powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_checks.ps1 -Suites check_placement,check_inventory_exchange -TimeoutSeconds 300`（本机无 `pwsh`，用兼容的 Windows PowerShell 5.1）。首次运行因一条新增断言误把移动后快照与移动前比较而 FAIL，已修正断言并保留失败证据后复测通过：`check_placement` 135 项、`check_inventory_exchange` 63 项，均 0 failures、`[checks] lifecycle complete; exit=0`、`ExitResourceWarning=false`，日志无 `SCRIPT ERROR`/`ERROR`/`FAIL`。玩家行为变化：无（默认未注入 provider 时行为完全一致）；存档影响：无（`devices` 分区字段未变）。仅本次进程设置 TEMP/TMP 到 E 盘，未改全局环境变量或真实玩家槽位。

本轮证据：`build/placement-contract-checks/2026-11-09-lock-state/`（成功运行日志、`results.json`、`import.log`、`source_manifest.txt` 指纹、四个改动源码副本与 `failed-run-1-*` 首次失败证据）；两份完整副本（`PixelFarmChecks_b6420e5856494affab76646072c56154` 失败、`PixelFarmChecks_9646be87bf7441fe8a5cb1139ccaec55` 成功）均已回收。按 `AGENTS.md` 第13条，详细交付记录与验证索引仍由主线程汇总到 `docs/history/开发记录.md`、`docs/validation/`，总纲任务状态由主线程维护。真实接线、全量、原生窗口、PCK 与真人键鼠仍待主线程验收，本轮不据此关闭 B3-03 门槛。
