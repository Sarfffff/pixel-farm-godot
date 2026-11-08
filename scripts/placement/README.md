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
