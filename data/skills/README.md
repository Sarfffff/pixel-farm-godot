# B3-01 技能配置与组件接入

三份 Resource：`agriculture.tres`、`foraging.tres`、`fishing.tres`，各5级，未入门为0级。曲线为累计经验，收益为逐级新增能力。数值是当前实现配置，尚未经过真人经营平衡验收。采矿不在本轮技能范围，不提前配置不存在的配方奖励。

## 主线程接入契约

`scripts/progression/skill_service.gd` 为 RefCounted，由 GameSession 显式持有：

```gdscript
var skills: RefCounted = preload("res://scripts/progression/skill_service.gd").new()

# 在读档前完成配置；省略第二参时用 ResourceLoader.list_directory 读取本目录。
skills.configure(func() -> int: return int(clock.day))
# 恢复顺序由主线程安排：基础日期/世界先还原，消费恢复边界期间不提交劳动。
save.snapshots.register_section(&"skills", skills.encode, skills.restore, TYPE_DICTIONARY, true)
```

`configure(current_day: Callable, definitions: Array[SkillDefinition] = []) -> bool` 是新会话初始化，重配会归零；替换 View 不要重配服务。坏配置（重复技能/动作、非法曲线、无效能力）拒绝且不破坏原服务。

手动传定义时使用 `Array[SkillDefinition]` 类型的变量；经 RefCounted 动态调用时，无类型 Array 字面量不会自动转换。正常接入省略第二参即可。

`record_labor(action: StringName, receipt: Dictionary) -> bool` 仅接已提交成功的真实劳动；`receipt` 必须有稳定 `id`（1–180字符，禁止首尾空白/换行）和绝对 `day`（与注入当前日一致）。经验点只由配置计算，外来的 count/points/xp 不参与计算。相同 ID 全局去重，换动作或改日期也不能重复计入。应在物品、体力、作物/耗尽/掉落状态全部提交后、对外通知前，同步调用本端口；主线程保证“成功劳动”来源，模块不订阅无来源的背包信号。

| 劳动动作 | 技能 | 每笔经验 | 凭据与成功边界 |
| --- | --- | --- | --- |
| `harvest` | agriculture | 8 | 作物实例/轮次；满包、体力不足、枯株清理不调用 |
| `chop_tree` | foraging | 6 | 稳定树ID/生成代数/倒树阶段；不按每次斧击累计 |
| `clear_stump` | foraging | 2 | 稳定树ID/生成代数/清桩阶段 |
| `forage` | foraging | 3 | 采集点或灌木/复生轮次；整笔浆果含种子只算一次 |
| `catch_fish` | fishing | 10 | 稳定投竿/领取轮次；仅成功入包领取，不计投竿、取消或逃鱼 |

区域地面掉落建议在完整拾取、删除掉落账本后用稳定 drop ID 计一次；不要同时在资源打完和拾取两处计经验。投竿/复收或掉落跨日领取时，凭据 ID 保持该次劳动身份，day 使用实际成功领取日。买卖、取箱、制作、任务/邮件奖励、读档和自动雨水均不调用。

## 冻结查询与能力端口

- `definitions() -> Array[SkillDefinition]`：深复制配置；`xp_of(id) -> int`、`level_of(id) -> int`。
- `effects_of(id) -> Dictionary`：`stamina_reductions`（动作→累计减免）、`fishing_wait_scale`（乘数）、`fishing_bite_window_bonus`（秒）；返回的是独立查询结果。
- `stamina_cost(action: StringName, base_cost: int) -> int`：支持 `hoe/watering_can/seeds/axe/harvest/forage/fishing`；原本免费的动作仍为0，其余最低1。采矿保持原消耗。基准应先使用工具升级后的原消耗，再应用一次技能减免；预检、实际扣费和提示调用同一端口，不能重复减免或在扣体力后才改价。
- `fishing_parameters(wait_min: float, wait_max: float, bite_window: float) -> Dictionary`：返回同名三键；每次投竿开始时查询并固定本次参数，不能每帧重复相乘或改写共享配置 Resource。
- `changed`、`level_advanced(skill: StringName, old_level: int, new_level: int)`：经验、凭据、全部跨级能力和通知记录提交后发出。通知期间拒绝重入授予、恢复、确认、重配及 release。

每级实际收益：农业1收获2→1，2播种2→1，3锄地4→3，4普通壶2→1/铜壶3→2，5锄地3→2；采集每级斧头减1（农场8→7→6→5→4→3），2级另减徒手采集1（杂草/纤维2→1，1体力目标保持1）；钓鱼1投竿4→3，2等待×0.8，3投竿3→2，4咬钩窗口+0.5秒，5投竿2→1。低基准动作受最低1限制，每个等级仍有至少一个当前可执行动作的明确收益。

基准对齐（`check_skills` 直接读取，不写死第二套数值）：

| 基准来源 | 值 | 对应收益 |
| --- | --- | --- |
| `FarmTiller.STAMINA_COST` | hoe4 / watering_can2 / seeds2 / axe8 / harvest2 / stone_pickaxe6 | 农业1–5、采集斧头五级 |
| `data/upgrades/watering_can.tres` | stamina_cost 3 | 农业4铜壶3→2 |
| `data/maps/resource_rules.tres` | 树8、杂草/蕨2、浆果1 | 采集斧头、徒手采集（1体力节点保持1） |
| `scripts/data/farm_activities_data.gd` 默认值（`data/activities/farm_activities.tres` 只覆盖落点与物品） | fishing_cost4、等待1.5–3.0、咬钩2.0 | 钓鱼1/3/5投竿、2等待1.2–2.4、4窗口2.5 |

改写这四份玩法配置时，`check_skills` 会失败并指出哪一级“只有描述、没有可执行变化”；改数值后必须同步本表与三份 `.tres` 描述。

## 夜间与保存

`pending_upgrades(day: int = 0) -> Array[Dictionary]` 返回未确认升级，0为全部，否则只取获得日≤day；每项为 `{skill, level, day, skill_name, description}`。主线程可直接交给夜间 Presenter；本模块 `SkillPresenter.upgrade_lines(day)` 也提供格式化文案。读取不发奖、不确认。

`acknowledge_summary(day: int) -> bool` 只在玩家确实看到/确认对应夜间摘要后调用，移除该日及之前的通知，不改变能力。漏看弹窗、白天升级或保存失败时能力仍立即生效。不要在每次查询或普通读档时自动确认。当前是效率收益，没有需要另存的物品或金币奖励账本。

`encode() -> Dictionary` 编码 `version=1`、`xp`、`receipts` 和 `pending_upgrades`。`restore(data: Dictionary) -> bool`：旧档缺 skills 分区传 `{}`，三项归零并清除旧槽凭据/摘要；恢复不发 `level_advanced`，不产生新能力奖励，只根据恢复经验重建查询结果。内层坏字段过滤，经验封顶；未来版本或过量结构返回 false 并保留当前状态，主线程应显示拒绝原因，不能随后覆盖该档。正式存档仍v2。

劳动历史只为已增加经验的凭据保存；满级拒绝新增凭据，因此数量由三技能经验上限自然约束，不按天清除历史而放开重复计入。`release()` 清理日期 Callable、状态与配置，由组合根退出时调用；退出同时 clear 快照回调。

读取历史使用每技能10000条的稳定结构上限，避免数值平衡调低当前曲线时拒绝旧的合法凭据；超过上限整段拒绝，不截断去重历史。改变这一格式上限需显式考虑迁移。

## 显示 MVP

创建 `scenes/ui/skill_panel.tscn` 加入 UI 后，创建 Node `scripts/ui/presenters/skill_presenter.gd` 挂入 Systems，调用 `configure(service, view)`。服务和 Presenter 分别显式持有；Presenter 不重新计算等级或能力。View 只渲染快照/发选择意图，无加经验和收益领取按钮。`presenter.open()` 打开，必须通过既有 `ModalCoordinator.register_panel(view)` 注册，统一暂停、输入锁和焦点。默认不绑定键盘，主线程可从现有菜单添加入口或设置 `view.toggle_action` 为已注册的空闲输入动作。

重复配置 Presenter 会解除旧 View/服务信号；View 销毁、Presenter 离树或 dispose 均解绑。主线程负责 GameSession/主场景/输入/劳动/存档/夜间接线；此模块独立交付不代表正式主场景或真人验收已完成。

## 专属检查

`pwsh -NoProfile -File tools/run_checks.ps1 -Suites check_skills -TimeoutSeconds 300`（本机未装 pwsh 时用 `powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_checks.ps1 ...`）。支持 `-Windowed -Preview` 输出技能原生截图。仅独立测试目录写盘，使用 check_lifecycle 退出。最终结果见模块交付答复；全量与 PCK 由主线程执行。

八个断言组：`catalog`（含基准对齐）、`receipts`、`matrix`（同ID换动作/换日/重放、满级、busy 重入、restore 后旧凭据）、`port`（LaborPort 契约与投竿参数只取样一次）、`atomic`、`summary`、`producer`、`mvp`。

遵守新增的 AGENTS 临时目录规则：在本轮进程中先设置 `TEMP`/`TMP` 到 `build/skills-checks-temp/`，再调用上述统一入口。本轮专属检查还把进程内 `APPDATA` 设置到 `build/skills-checks-userdata/`，Godot 的导入缓存、隔离存档和截图均落在 E 盘；不修改全局环境。已结束副本的递归清理被工具安全策略拒绝时必须如实保留路径，不宣称已清理。

### 2026-11-08 独立模块交付证据

| 项目 | 结果 |
| --- | --- |
| 最终命令 | `pwsh -NoProfile -File tools/run_checks.ps1 -Suites check_skills -Windowed -Preview -TimeoutSeconds 300`（上述进程环境先指向E盘） |
| 资源预导入 | PASS |
| check_skills | 268项，0 failures；六组场景均执行到末尾，退出码0 |
| 错误/退出泄漏 | 无SCRIPT ERROR、引擎错误和退出资源泄漏；一条预期JSON替换失败注入警告 |
| 原生检查 | 1280×720、1920×1080、800×600布局、Esc和模态、View替换/销毁均通过；PNG已目视复核 |
| 行为与保存 | 五级实际能力、固定劳动经验、跨动作/跨日全局ID去重、观察者重入、满包/缺体力拒绝、三次磁盘恢复、旧档缺分区及未来版本拒绝通过 |
| 正式接线/全量/PCK/真人 | 未执行，由整合者继续；不把独立模块通过标记为正式玩法或真人验收完成 |

原始报告、日志、源码指纹和冻结代码：`E:/Godot/pixel-farm-godot/build/skills-checks-temp/PixelFarmChecks_943664ca8d394391949b997c60ffd95c/`。交付前核对了11份实现/配置/检查文件SHA256，均与该副本一致。截图：`E:/Godot/pixel-farm-godot/build/skills-checks-userdata/PixelFarmChecks_943664ca8d394391949b997c60ffd95c_check_skills/skills.png`。

本轮最终副本及两个失败副本（`9f81100744e3408b9d879eb01ffde1db`、`7d988a4b7a9a42b0b5860b21e300425c`）都保留在上述E盘临时父目录；递归清理操作被工具安全策略拒绝（仅返回 blocked by policy），所以未完成清理。此前C盘目录也未被本聊天删除，不宣称释放了历史占用。

文件清单：`scripts/data/skill_definition.gd`、`scripts/data/skill_level_reward.gd`、三份 `data/skills/*.tres`、`scripts/progression/skill_state.gd`、`scripts/progression/skill_service.gd`、`scripts/ui/presenters/skill_presenter.gd`、`scripts/ui/panels/skill_panel.gd`、`scenes/ui/skill_panel.tscn`、`tools/check/check_skills.gd`、本说明及7份脚本UID。额外依用户新指令修改根 `AGENTS.md` 的临时目录和清理规则；未修改组合根、主场景、project.godot及其他共享业务文件，保留其他Agent并行修改。

整合提醒：`record_labor` 返回false也可能只是满级/重复凭据，不能回滚已成功劳动；错误来源请查 `last_rejection`。能力查询应在本次操作预检时固定，升级对下一笔劳动生效；`skills.changed` 可由组合根刷新工具提示和制作资格View，但技能服务不持有制作服务。未来skills分区被拒绝时应由整合层阻止随后覆盖该档，并提示不兼容原因。

### 2026-11-09 基准对齐与劳动端口/凭据矩阵

| 项目 | 结果 |
| --- | --- |
| 命令 | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_checks.ps1 -Suites check_skills,check_layer_boundaries -TimeoutSeconds 300`（本机无 pwsh，脚本本身兼容 5.1） |
| 结果 | check_skills 385项0失败、check_layer_boundaries 34项0失败；资源预导入 PASS，无 SCRIPT ERROR、引擎错误与退出资源泄漏 |
| 日志 | `e:/my-ai-game/build/skills-checks-temp/PixelFarmChecks_6e74155f70484537999b1641487809a1/` |
| 本轮改动 | `data/skills/foraging.tres` 2级描述补充“杂草/纤维2→1，1体力目标保持1”；`tools/check/check_skills.gd` 增加基准对齐、labor_port 契约与凭据矩阵断言（三个新组拆到 `tools/lib/skills_contracts.gd`，保持单文件<500行）；本说明 |
| 未改动 | `game_session.gd`、`project.godot`、`farm_tiller.gd`、`farm_activities.gd`、`regions/*`、`labor_port.gd` |

契约结论：`SkillService.stamina_cost` 对正基准等于 `max(1, base-累计减免)`，base≤0 返回0。`LaborPort` 对0返回0；负基准目前原样透传（正式玩法只传非负基准），若要端口也归零，需要主线程在 `labor_port.gd` 改一行，本轮未越界修改。
