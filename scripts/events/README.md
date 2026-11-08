# B2-04 条件事件与过场

本模块提供独立组件和接线契约。组件交付本身不修改组合根、玩家输入或常规对话框；后续整合者已在GameSession接入独立输入租约、events恢复及ChapterFlow第一章触发。下文保留可复用端口契约；当前整合行为及验证以docs/02-系统设计.md和最新章节报告为准，组件成绩不替代完整章节人工验收。

## 状态与资源

- `scripts/data/story_event.gd`：`StoryEvent` 定义稳定的 `id`、标题、同步结果 `outcome`、AND 条件和表现指令。所有事件一次性；注册时深复制配置，拒绝重复 ID。
- `story_condition.gd`：地点、日期闭区间、分钟闭区间（支持跨午夜）、天气、关系值和任务状态。类别用 `allowed`，数字用 `minimum/maximum`，所有外部事实每次经查询端口读取；缺失/类型错误拒绝触发。
- `story_cue.gd`：`line/move/face/camera/fade_out/fade_in/choice/wait`。位置均为世界坐标，duration 为秒。数据需经 `is_valid`，不接受负数、非有限值或未知指令。
- `data/events/market_memory.tres`：农场 + 第一章末任务已完成条件下的纯对话事件，无额外奖励；已由ChapterFlow在章节完成后的正常玩法边界触发。添加事件不改服务分支，目录扫描使用 `ResourceLoader.list_directory`，支持 PCK。
- `event_state.gd`：只保存 `{version: 1, completed: {event_id: 完成日}}`。保留未知内容 ID 防止暂时下线后重复结算；丢弃非法记录。外部任务、好感、背包、金币不复制。

## 服务接口

| 接口 | 契约 |
| --- | --- |
| `configure(query, commit, save)` | 注入只读条件、原子结果和保存端口；服务显式由 GameSession 持有 |
| `register_event(event) -> bool` / `load_directory(path) -> int` | 注册 Resource / 加载目录，返回是否成功 / 新注册数量 |
| `definition(id)` | 返回只读用途的深复制定义，调用方修改不污染注册表 |
| `can_trigger(id)` / `status_of(id)` / `has_completed(id)` | 查询可触发和一次性事实；状态 unknown/blocked/available/completed/released |
| `trigger(id) -> bool` | 同步提交剧情结果与一次性记录，不等待过场；失败不消费事件 |
| `encode()` / `restore(data) -> bool` | 仅事实往返；不发奖、不自动重播；事务中拒绝恢复 |
| `release() -> bool` | 丢弃状态、定义和全部外部 Callable；事务中拒绝释放，之后不再接收操作 |

`query(kind: StringName, key: StringName) -> Variant` 的返回值：location/weather 为稳定字符串 ID，day 为从1起的绝对日数，minute 为0–1439（当前时钟支持26:00，适配时用 `clock.minutes % 1440`），relationship 从既有 `Friendship.points_of(key)` 读取整数值，quest 从既有 QuestService 映射稳定状态字符串（例如 locked/available/active/completed）。事件内不保存外部事实快照。

`commit(event_id, outcome) -> bool` 必须是**同步、不可 await 的完整应用用例**。先检查全部前置条件和容量，失败不改任何事实；成功在任何模型通知前完成整笔结果。不在此端口串联多个可能部分成功的公开用例。空 outcome 不调用 commit，非空却缺端口拒绝触发。模块自己不认识库存或金币。

服务在调用结果端口前暂存完成记录，因此外部模型观察者能看到事件已完成，重复 trigger、restore、release 均被 busy 拒绝；commit 返回 false 时撤回暂存记录。成功后发 `committed(id)`、`changed`，再请求 `save() -> bool`。保存失败保留已结算事实，发 `save_failed(id)`，组合根必须接 Toast，并允许手动重试保存；不能重跑奖励端口。重新读取结算前的旧快照会同时还原外部模型和事件记录，这是正常回档。

## 过场与独立对话

`cutscene_player.gd` 为 Node。`configure(service, acquire, release_lock, resolve_actor, face_actor, camera, dialogue)` 后加入树；`play(id)` 在预检指令、角色与输入租约成功后调用同一个同步 trigger。`cancel()` 终止表现；`skip()` 把剩余走位和朝向落实到终点后终止；均不再次结算。`is_playing/current_status` 查询，`advance_line/choose(index)` 接入输入或测试，`release()` 释放端口、UI、相机和自己的输入租约，离树自动调用。

关键结果在触发时已提交，因此**取消、离树或销毁不会撤回剧情，也不会将此事件留为可再次发奖**。不承诺取消后的角色位置等于完整观看；跳过会应用剩余位置和朝向，保证终点一致。不要在走位中执行地点/任务操作。

选项是表现回应：`choice_selected(event_id, cue_index, option)` 供显示反馈，不用于关键奖励。跳过不弹选项，不发布假点击，不改变固定 outcome；`default_option` 决定按钮初始焦点。需要影响任务/奖励的选择，应另写同步选择用例及持久化规则后再接入，不能在 View 信号回调临时发奖。

默认创建独立的 `cutscene_dialogue.gd`，包含继续/选项/跳过按钮；Escape 在台词、淡出、等待及走位中均可跳过。可注入替代 Node，要求实现 `show_line(speaker,text)`、`show_choices(text,options,default)`、`close()` 和 `advanced/selected(index)/skip_requested` 信号。替代 View 由调用方持有，release 时断开组件自己建立的全部连接。

执行器使用逐帧状态而非悬挂 Timer/动画协程；销毁后无旧等待恢复。走位直线插值到世界坐标，期间暂停该角色 process_mode，结束恢复原值。`resolve_actor(id) -> Node2D` 只返回仍在树中的角色；`face_actor(id, direction)` 连接角色公开表现端口，不能跨模块改私有朝向字段。路线须由内容作者确保无碰撞/不可穿墙；有导航需求时由地图侧提供预计算的多个 move 点，生产移动动画由角色适配端口负责。

## 组合根接线要求

1. **显式持有** EventService 和 CutscenePlayer；先恢复基础时间、天气、关系和任务，再恢复事件分区。恢复完成后，在正常的区域进入或条件变化边界尝试 `player.play(id)`；禁止恢复回调自动尝试触发事件。
2. **输入租约**：`acquire(owner: StringName) -> bool`、`release_lock(owner)` 必须按 owner 独占持有、幂等释放。拒绝模态、工具动作、休息和其他过场冲突。旧 Player 的 `set_input_locked(bool)` 是共享布尔入口，不能直接当 release_lock，否则会误清除睡觉等来源的锁。由组合根接入统一租约仲裁器后再启用正式触发；本模块不偷偷改玩家 API。
3. **时间**：目前 TimeSystem 在玩家 input_locked 时停止，租约驱动此锁即可冻结；若替换输入适配，必须保证相同的暂停语义。不要直接改 `SceneTree.paused`，否则过场执行器自身也可能停止。
4. **镜头**：传当前同 Viewport 的 Camera2D。执行器创建临时 Camera2D，复制当前位置、缩放和边界，不修改 CameraFollow 的目标/配置。结束、跳过、取消、离树时禁用并删除临时相机；仅当它仍是当前相机时恢复原相机，避免抢走后来接管的镜头。原相机必须在整个过场期间存活；区域切换前先 cancel。
5. **黑幕**：执行器自有129层 CanvasLayer，对话130层；不借用或清理全局 ScreenFade。不要让两个过场同时争抢屏幕；销毁只删自己的黑幕，既有睡觉/进屋黑幕不动。
6. **存档**：注册可选 `events` 分区，正式v2版本不变，缺少分区恢复为空；与结果修改的外部模型在**同一快照**保存。开始载入前先 `player.cancel()`，然后统一恢复，不能保留旧的播放游标。退出先 player.release，再清快照回调，最后 service.release。

接线示例（在 GameSession 完成输入仲裁和结果用例后）：

```gdscript
# 成员显式保留 event_service、cutscene_player，具体端口由组合根提供。
event_service.configure(query_story_fact, commit_story_outcome, save.save_game)
event_service.load_directory("res://data/events")
event_service.save_failed.connect(show_story_save_failure)
cutscene_player.configure(event_service, acquire_story_lease, release_story_lease,
	resolve_story_actor, face_story_actor, get_node("Camera"))
get_node("Systems").add_child(cutscene_player)
# 注册在 quests 后；restore_story_events 内先 cancel，再 service.restore(data)。
save.snapshots.register_section(&"events", event_service.encode, restore_story_events,
	TYPE_DICTIONARY, true)
```

验证入口：`pwsh -NoProfile -File tools/run_checks.ps1 -Suites check_story_events,check_layer_boundaries,check_quests -Packaged`。完整观看/跳过、事务和磁盘恢复、取消/销毁使用自动检查；正式章节的碰撞路线、角色行走动画、真实键鼠和节奏仍需集成后人工验收。

2026-11-08验证：专项83项、实际窗口84项通过，43套全量（含PCK导出/运行）通过，无脚本/引擎错误或退出泄漏。[证据报告](../../docs/validation/2026-11-08-b2-events.json)。窗口预览是组件替身场景，不是第一章完整玩家流程。
