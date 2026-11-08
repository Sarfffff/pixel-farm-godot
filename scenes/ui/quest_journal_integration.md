# B2-03 任务日志与单目标 HUD 接入

> 本文保留Agent A独立组件交付时的契约和验证记录。2026年11月8日已由整合者接入GameSession、quest_tracking及正式K键；下文“未接入”及Q键建议描述初始交付状态，不是当前开发指令。当前实现与状态以docs/02-系统设计.md、docs/04-后续开发总纲.md及最新章节验证报告为准。

本交付提供独立组件，未修改组合根、主场景、project.godot、NPC 和既有对话面板。B2-03 的正式玩家入口、存档注册及人工试玩仍待整合；不能据本组件检查把 B2 阶段标为已验收。按本轮授权范围未改共享总纲及系统设计，请整合负责人将 B2-03 记为“组件自动验证通过，待组合根接入与人工验收”（检查结果见本文件末尾）。

## 创建和所有权

在 `GameSession` 组合根中实例化以下两个场景，加入已有全屏 UI 容器；HUD 在模态面板之前添加，面板在普通 HUD 之后添加。Presenter 是 Node，挂入 Systems 并由会话持有；不要只保留 Callable。

```gdscript
const QuestJournal := preload("res://scenes/ui/quest_journal.tscn")
const QuestTracker := preload("res://scenes/ui/quest_tracker.tscn")
const QuestJournalPresenter := preload("res://scripts/ui/presenters/quest_journal_presenter.gd")

var _quest_journal_presenter: Node

func _configure_quest_journal() -> void:
	var panel: Control = QuestJournal.instantiate()
	var tracker: Control = QuestTracker.instantiate()
	get_node("UI").add_child(tracker)
	get_node("UI").add_child(panel)
	_quest_journal_presenter = QuestJournalPresenter.new()
	get_node("Systems").add_child(_quest_journal_presenter)
	_quest_journal_presenter.configure(
		quests, get_node("Systems/Inventory"), panel, tracker,
		get_node("Systems/Save"), _quest_giver_location)
	get_node("Systems/Modals").register_panel(panel)
```

`configure(service: RefCounted, inventory: Inventory, panel: Control, hud: Control = null, save: Node = null, location_text: Callable = Callable()) -> void`

- `service`：会话中已 start/configure 的同一个 QuestService。读取 `definitions/status_of/progress/can_deliver`，订阅 `changed/save_failed`；接取/交付只调用服务。服务可选的 `delivery_hint(id)` 用于显示容量或业务拒绝原因；没有此扩展时仍可运行，交付失败显示通用提示，容量始终由服务校验。
- `inventory`：已有背包，仅订阅 `changed` 和查询物品名称，不维护第二份数量或容量规则。
- `panel`：已 ready 的日志 View，也可用同等意图信号和 `render(snapshot)` 的替身；允许传 null 形成仅 HUD 模式。
- `hud`：已 ready 的单目标 View，可省略，形成仅日志模式。
- `save`：可选现有 SaveSystem，订阅 `restored`，最终恢复后重新查询。这里不写文件。
- `location_text(giver_id: StringName) -> String`：组合根提供当前位置/交付线索，不传 NPC Node。当前 QuestData 无地点字段，缺回调或返回空字符串显示“寻找委托人（地点线索待补充）”。整合时提供真实可达地点；不要把测试中的固定柜台文案作为所有村民的位置。

详情由 `scripts/ui/panels/quest_detail.gd` 自动创建，不需另建场景。View 的所有输出均是显示快照，未缓存任务事实。现有章节定义作为主线显示；没有新增人物支线/订单的平行状态。

## 模态及输入

日志继承 ModalPanel，`pauses_world=true`、`PROCESS_MODE_ALWAYS`。必须注册到同一个 ModalCoordinator；不自行设置暂停或玩家输入锁。`panel.open()/close()/set_open(bool)` 和 HUD 的打开请求都走此接口。关闭/销毁由协调器释放暂停和输入锁。

推荐后续在 project.godot 新增 `toggle_quest_log`，绑定 Q；View 的 `toggle_action` 可替换。没有此 action 时键盘入口静默禁用，HUD 的“任务日志”按钮仍可打开。Esc 关闭当前日志，重复按键忽略；其他模态开启时 Q 不抢占。J 保留给既有农场手记。View 不自行注册 InputMap。HUD 默认右侧状态牌下方（右边距 5、宽约 197、上边距 72），与左上手记并存；父级应保持全屏 Control，若整合到容器内应由容器重新安排布局。

## 单目标和保存

`track(id: StringName)` 只接受进行中的任务；空 ID 清空。`tracked_id() -> StringName` 返回唯一追踪 ID；完成后清空，不暗中切换其他任务。通过日志接取且原先无目标时自动追踪；外部 NPC 接取会刷新列表，玩家可手动选择追踪。

新增可选分区建议名 `quest_tracking`。必须放在 **inventory、世界和 quests 之后**，且在初次自动读档之前注册：

```gdscript
save.snapshots.register_section(
	&"quest_tracking",
	_quest_journal_presenter.encode_tracking,
	_quest_journal_presenter.restore_tracking,
	TYPE_DICTIONARY, true)
```

编码 `{"version": 1, "tracked_id": "ch1_01_gate"}`；只保存展示偏好，不保存进度/接取/完成/奖励副本。接口为 `encode_tracking() -> Dictionary`、`restore_tracking(data: Dictionary) -> void`，后者只验证/恢复 ID，绝不调用接取/交付。旧档缺分区、坏标量、未来版本、未知/已完成/未接取 ID 均清空。`restore_missing=true` 防止跨槽残留。正式保存版本继续 v2。

`tracking_changed(id)` 供整合层同步展示或记录偏好变更；它在恢复、完成清空时也会发出，因此不要无条件把此信号直接连到同步 `save_game()`。追踪变更随下一次正常保存落盘；若产品要求点选后立即落盘，整合层应区分玩家意图与恢复阶段，并在事务结束后请求保存。保存失败通过服务事件显示在日志及 HUD，玩家仍能操作，不重复发奖。

## 生命周期

Presenter 重配会解绑旧服务、背包、读档和两组 View 信号；离树或 `dispose()` 同样清理，可重复调用。单独销毁日志后，独立 HUD 仍订阅现有服务；最后一个 View 销毁会解除源信号。替换时先创建/ready 新 View，再 `configure(...)`；如果需要保留同一目标，在重配前 encode、重配后 restore。退出会话时沿用现有快照注册表的 clear，以免持有已释放 Presenter 的回调。

## 验证

统一入口自动发现专属检查，无需修改 run_checks.ps1：

```powershell
pwsh -NoProfile -File tools/run_checks.ps1 -Suites check_quest_journal,check_quests,check_layer_boundaries -Packaged
pwsh -NoProfile -File tools/run_checks.ps1 -Suites check_quest_journal -Windowed -Preview
```

专属检查使用真实服务、背包、钱包、SaveSystem 和三次磁盘读档，验证库存增减、内外部接取、完成/重复交付、满包拒绝、写档失败可见、唯一追踪、坏档/旧档、Q/Esc/J、模态交接、实际农场手记并存、三种窗口比例、View 替换/销毁和 Presenter 解绑。调用 check_safety 保护 user://，以 check_lifecycle 清理退出。最终结果与截图路径见下表；窗口渲染检查不替代真人键鼠试玩。此处未宣称正式主场景接入或人工验收完成。

### 2026-11-08 最终组件交付结果

执行命令：

```powershell
pwsh -NoProfile -File tools/run_checks.ps1 -Suites check_quest_journal,check_quests,check_layer_boundaries,check_compilation -Windowed -Preview -Packaged -TimeoutSeconds 300
python tools/maintenance/audit_project_layout.py
```

| 项目 | 结果 |
| --- | --- |
| 资源预导入 | PASS |
| 脚本编译 | 381 份脚本，0 failures |
| check_quest_journal | 82 项断言，0 failures；执行到末尾清理断言 |
| check_quests / check_layer_boundaries | PASS |
| 实际 PCK 导出 / 包内运行 | PASS / PASS；使用既有发行包检查，不代表新日志已接到正式主场景 |
| 汇总 | 5 套，0 failures；退出码 0，无 SCRIPT ERROR、引擎错误或退出泄漏 |
| 目录审计 | PASS，0 errors，未修复或移动文件 |
| 原生截图 | 已目视检查列表/详情/按钮、HUD 和手记无重叠；自动验证 Q/Esc/J 和三种窗口比例 |
| 正式场景整合与真人试玩 | 未执行，待整合负责人接入后验收 |

冻结副本及原始报告：`C:/Users/86156/AppData/Local/Temp/PixelFarmChecks_607e00c8306e4e258e03a25f4b517049/`（`results.json`、各 `check_*.log`、`packaged_export.log`、`packaged_runtime.log`、`source_manifest.txt`）。交付时核对了 7 份实现/检查源文件的 SHA256，均与该副本一致；保留并行开发的其他文件变更。

原生 PNG：`C:/Users/86156/AppData/Roaming/PixelFarmChecks_607e00c8306e4e258e03a25f4b517049_check_quest_journal/quest_journal.png` 和同目录 `quest_tracker.png`。未读取或写入真实玩家槽位。本交付只新增授权的 UI、场景、专属检查及其 UID/接入说明；共享总纲的 B2-03 状态需在整合时同步，不能标记为已人工验收。
