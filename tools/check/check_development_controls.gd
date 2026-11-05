extends SceneTree
## 默认禁用、显式启用、模态与休息排斥、重入/同帧保护及组件离树清理。

const Controls := preload("res://scripts/platform/development_controls.gd")
var _checks: int = 0
var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		printerr("[development_controls] FAIL: " + message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	for editor: bool in [false, true]:
		for production: bool in [false, true]:
			for requested: bool in [false, true]:
				_check(Controls.allowed(editor, production, requested) == (editor and not production and requested), "only explicit editor workspace activation is allowed")
	await _check_adapter()
	await _check_session()
	print("[development_controls] %d checks, %d failures; reached end; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check_adapter() -> void:
	var controls := Controls.new()
	root.add_child(controls)
	var calls: Array[int] = [0]
	var context: Array[bool] = [true]
	var advance := func() -> void:
		calls[0] += 1
		_check(not controls.request_advance(), "observer reentry cannot advance twice")
	controls.configure(false, advance, func() -> bool: return context[0])
	_check(not controls.request_advance() and calls[0] == 0, "disabled adapter never invokes date port")
	controls.configure(true, advance, func() -> bool: return context[0])
	context[0] = false
	_check(not controls.request_advance(), "context rejection leaves callback untouched")
	context[0] = true
	_check(controls.request_advance() and calls[0] == 1, "enabled adapter invokes date port once")
	_check(not controls.request_advance() and calls[0] == 1, "multiple requests in one frame cannot duplicate daily rewards")
	await process_frame
	await process_frame
	_check(controls.request_advance() and calls[0] == 2, "later deliberate request remains available")
	root.remove_child(controls)
	_check(not controls.enabled and not controls.request_advance(), "leaving tree releases ports and disables detached component")
	controls.free()


func _check_session() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.get_node("Systems/Save").autoload_enabled = false
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	var clock: Node = main.get_node("Systems/Time")
	clock.running = false
	var player: Node = main.get_node("Farm/World/Player")
	var controls: Node = main.get_node("Systems/DevelopmentControls")
	var expected: bool = Controls.allowed(OS.has_feature("editor"), OS.has_feature("farm_release"), "--enable-dev-tools" in OS.get_cmdline_user_args())
	_check(controls.enabled == expected, "composition root uses actual feature and command-line policy")
	_check(not player.has_signal(&"day_advanced"), "player no longer exposes the old ungated shortcut")
	var day: int = clock.day
	var event := InputEventKey.new()
	event.physical_keycode = KEY_N
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame
	_check(clock.day == day + (1 if expected else 0), "actual N input obeys opt-in policy")
	if expected:
		var bag: Node = main.get_node("UI/InventoryPanel")
		bag.set_open(true)
		_check(not controls.request_advance(), "inventory modal blocks development shortcut")
		bag.set_open(false)
		var pause: Node = main.get_node("UI/PauseMenu")
		pause.open()
		_check(not controls.request_advance(), "paused world cannot be advanced")
		pause.close()
		player.set_input_locked(true)
		_check(not controls.request_advance(), "manual cutscene input lock blocks shortcut")
		player.set_input_locked(false)
		player.is_acting = true
		_check(not controls.request_advance(), "tool action cannot be interrupted by date shortcut")
		player.is_acting = false
		var rest: Node = main.get_node("Systems/Rest")
		_check(rest.service.begin(), "real rest service acquires session")
		_check(not controls.request_advance(), "rest session excludes concurrent debug day settlement")
		rest.service.finish()
		var before_echo: int = clock.day
		event.echo = true
		Input.parse_input_event(event)
		await process_frame
		await process_frame
		_check(clock.day == before_echo, "keyboard repeat does not skip more days")
	_check(main.get_node("Systems/Save").collect().keys().has(&"time"), "normal save snapshot remains available without new debug fields")
	main.queue_free()
	await process_frame
