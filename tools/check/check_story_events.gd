extends SceneTree
## B2-04：条件、同步事务、重复读档、完整观看/跳过和三阶段销毁。

const Service := preload("res://scripts/events/event_service.gd")
const Player := preload("res://scripts/events/cutscene_player.gd")
const Registry := preload("res://scripts/persistence/snapshot_registry.gd")
const Store := preload("res://scripts/persistence/json_save_store.gd")

class DialogueDouble extends Node:
	signal advanced
	signal selected(index: int)
	signal skip_requested
	var showing: bool = false
	func show_line(_speaker: String, _text: String) -> void: showing = true
	func show_choices(_text: String, _options: Array[String], _default: int) -> void: showing = true
	func close() -> void: showing = false

class Fixture extends Node2D:
	var service: RefCounted
	var runner: Node
	var actor := Node2D.new()
	var camera := Camera2D.new()
	var wallet := Economy.new()
	var context: Dictionary = {&"location": &"home", &"day": 4, &"minute": 600, &"weather": &"sunny", &"relationship:gardener": 100, &"quest:ch1_01_gate": &"completed"}
	var locks: Dictionary = {&"another_owner": true}
	var allow_acquire: bool = true
	var allow_commit: bool = true
	var allow_save: bool = true
	var commits: int = 0
	var saves: int = 0
	var save_failures: int = 0
	var facing: StringName = &"down"
	func setup() -> void:
		add_child(actor)
		add_child(camera)
		add_child(wallet)
		camera.make_current()
		service = Service.new()
		service.configure(query, commit, persist)
		service.save_failed.connect(func(_id: StringName) -> void: save_failures += 1)
		runner = Player.new()
		runner.configure(service, acquire, unlock, resolve_actor, face_actor, camera)
		add_child(runner)
	func query(kind: StringName, key: StringName) -> Variant:
		return context.get(kind if key == &"" else StringName("%s:%s" % [kind, key]))
	func commit(_id: StringName, _outcome: StringName) -> bool:
		if not allow_commit: return false
		commits += 1
		wallet.earn(25)
		return true
	func persist() -> bool:
		saves += 1
		return allow_save
	func acquire(owner: StringName) -> bool:
		if not allow_acquire: return false
		locks[owner] = true
		return true
	func unlock(owner: StringName) -> void:
		locks.erase(owner)
	func resolve_actor(id: StringName) -> Node2D:
		return actor if id == &"actor" else null
	func face_actor(_id: StringName, direction: StringName) -> void:
		facing = direction
	func dispose() -> void:
		if is_instance_valid(runner): runner.release()
		service.release()

var _checks: int = 0
var _failures: int = 0
var _end: bool = false


func _init() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("[story_events] FAIL: " + message)


func _fixture() -> Fixture:
	var fixture := Fixture.new()
	root.add_child(fixture)
	fixture.setup()
	return fixture


func _event(id: StringName, kinds: Array[String]) -> StoryEvent:
	var event := StoryEvent.new()
	event.id = id
	event.title = String(id)
	event.outcome = &"test_atomic_outcome"
	for kind: String in kinds:
		var cue := StoryCue.new()
		cue.kind = kind
		cue.actor = &"actor"
		cue.text = "示例台词"
		cue.duration = 0.03
		cue.target = Vector2(40, 30)
		cue.facing = "left"
		cue.options = ["继续种田", "欣赏灯火"]
		event.cues.append(cue)
	return event


func _condition(kind: String, key: StringName = &"") -> StoryCondition:
	var condition := StoryCondition.new()
	condition.kind = kind
	condition.key = key
	condition.minimum = 1
	condition.maximum = 1000
	return condition


func _run() -> void:
	_check_conditions()
	_check_transactions()
	await _check_watch_skip()
	await _check_cleanup()
	await _check_view_and_reentry()
	await _check_recovery()
	_end = true
	_check(_end, "all condition, transaction, lifecycle and recovery probes reached end")
	print("[story_events] %d checks, %d failures; reached end" % [_checks, _failures])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check_conditions() -> void:
	var fixture := _fixture()
	var event := _event(&"conditions", [])
	var place := _condition("location")
	place.allowed = [&"home"]
	var date := _condition("day")
	date.minimum = 4
	date.maximum = 5
	var minute := _condition("minute")
	minute.minimum = 540
	minute.maximum = 660
	var weather := _condition("weather")
	weather.allowed = [&"sunny"]
	var relationship := _condition("relationship", &"gardener")
	relationship.minimum = 100
	var quest := _condition("quest", &"ch1_01_gate")
	quest.allowed = [&"completed"]
	event.conditions = [place, date, minute, weather, relationship, quest]
	_check(fixture.service.register_event(event), "all six condition kinds register")
	_check(not fixture.service.register_event(event), "duplicate stable event id rejected")
	_check(fixture.service.can_trigger(event.id), "all conditions combine with AND")
	for key: StringName in fixture.context.keys():
		var value: Variant = fixture.context[key]
		fixture.context[key] = null
		_check(not fixture.service.can_trigger(event.id), "missing %s fails closed" % key)
		fixture.context[key] = &"wrong" if value is StringName else -1
		_check(not fixture.service.can_trigger(event.id), "wrong %s blocks trigger" % key)
		fixture.context[key] = value
	minute.minimum = 1380
	minute.maximum = 120
	_check(minute.matches(0) and minute.matches(1380) and minute.matches(120) and not minute.matches(600) and not minute.matches(1440), "cross-midnight interval is inclusive and bounded")
	_check(not date.matches(true) and not date.matches("4") and not date.matches(4.5) and not date.matches(NAN), "malformed numeric facts rejected")
	_check(fixture.service.status_of(&"missing") == &"unknown", "unknown event status")
	var read_only: RefCounted = Service.new()
	read_only.configure(fixture.query)
	read_only.register_event(event)
	_check(not read_only.trigger(event.id), "missing outcome commit port cannot silently consume an event")
	read_only.release()
	fixture.dispose()
	fixture.free()


func _check_transactions() -> void:
	var fixture := _fixture()
	var event := _event(&"atomic", ["line"])
	fixture.service.register_event(event)
	var observations: Array[bool] = []
	fixture.wallet.changed.connect(func(coins: int) -> void:
		observations.append(coins == 525 and fixture.service.has_completed(event.id))
		_check(not fixture.service.trigger(event.id), "wallet observer reentry rejected")
		_check(not fixture.service.restore({}), "restore during commit rejected")
		_check(not fixture.service.release(), "release during commit rejected"))
	fixture.allow_commit = false
	_check(not fixture.service.trigger(event.id) and not fixture.service.has_completed(event.id) and fixture.wallet.coins == 500, "failed atomic port retains trigger and external state")
	fixture.allow_commit = true
	fixture.allow_save = false
	_check(fixture.service.trigger(event.id), "synchronous result does not require a View")
	_check(observations == [true], "external observers see the completed event and complete result")
	_check(fixture.commits == 1 and fixture.saves == 1 and fixture.save_failures == 1, "save failure is visible and retains one committed result")
	_check(not fixture.service.trigger(event.id) and fixture.commits == 1 and fixture.wallet.coins == 525, "duplicate trigger never settles again")
	var encoded: Dictionary = JSON.parse_string(JSON.stringify(fixture.service.encode()))
	for index: int in 3:
		_check(fixture.service.restore(encoded) and not fixture.service.trigger(event.id) and fixture.wallet.coins == 525, "repeat JSON restore %d is side-effect free" % index)
	_check(not fixture.service.restore({"version": 2, "completed": {}}) and fixture.service.has_completed(event.id), "unsupported partition version preserves completion instead of reopening rewards")
	_check(not fixture.service.restore({"version": 1, "completed": []}) and fixture.service.has_completed(event.id), "malformed completion table is rejected without reopening rewards")
	fixture.service.restore({"version": 1, "completed": {"future_content": 9, "bad": false, "fraction": 2.5, "negative": -1, "array": []}})
	_check(fixture.service.has_completed(&"future_content") and not fixture.service.has_completed(&"bad") and not fixture.service.has_completed(&"fraction") and not fixture.service.has_completed(&"negative"), "unknown stable IDs retained; malformed completed records ignored")
	fixture.dispose()
	_check(fixture.service.status_of(event.id) == &"released" and not fixture.service.trigger(event.id), "released service rejects work and drops its ports")
	fixture.free()


func _check_watch_skip() -> void:
	var kinds: Array[String] = ["fade_out", "wait", "move", "face", "camera", "fade_in", "line", "choice", "line"]
	var watched := _fixture()
	var skipped := _fixture()
	watched.camera.make_current()
	var event := _event(&"watch_skip", kinds)
	watched.service.register_event(event)
	skipped.service.register_event(event)
	_check(watched.runner.play(event.id) and not watched.runner.play(event.id), "one playback owns duplicate play requests")
	_check(watched.wallet.coins == 525 and watched.commits == 1, "critical result committed before fade or dialogue completes")
	for index: int in 200:
		if not watched.runner.is_playing(): break
		var kind: String = watched.runner.current_status().kind
		if kind == "line": watched.runner.advance_line()
		elif kind == "choice":
			_check(not watched.runner.choose(-1) and not watched.runner.choose(2), "invalid choices do not advance")
			if "--preview" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				var image: Image = root.get_texture().get_image()
				_check(image.save_png("user://story_event_choice.png") == OK, "save real choice View preview")
				print("[story_events] preview: " + ProjectSettings.globalize_path("user://story_event_choice.png"))
			watched.runner.choose(1)
		await create_timer(0.01).timeout
	_check(not watched.runner.is_playing() and watched.facing == &"left" and watched.actor.position == Vector2(40, 30), "full watch executes lines, choices, face and movement")
	_check(watched.locks.size() == 1 and watched.locks.has(&"another_owner") and watched.camera.is_current(), "normal completion restores own lock and camera")
	skipped.camera.make_current()
	_check(skipped.runner.play(event.id) and skipped.runner.skip() and not skipped.runner.skip(), "skip finalizes once")
	_check(watched.service.encode() == skipped.service.encode() and watched.wallet.coins == skipped.wallet.coins and watched.actor.position == skipped.actor.position and watched.facing == skipped.facing, "full watch and skip share all persistent and final actor results")
	_check(skipped.locks.size() == 1 and skipped.camera.is_current(), "skip restores camera and preserves another lock")
	watched.dispose()
	skipped.dispose()
	watched.free()
	skipped.free()
	await process_frame


func _check_cleanup() -> void:
	for kind: String in ["fade_out", "wait", "move", "line", "choice"]:
		var fixture := _fixture()
		var kinds: Array[String] = [kind]
		var event := _event(StringName("destroy_" + kind), kinds)
		event.cues[0].duration = 2.0
		fixture.service.register_event(event)
		_check(fixture.runner.play(event.id), "start destruction probe " + kind)
		await create_timer(0.05).timeout
		var curtain: ColorRect = fixture.runner.get("_curtain")
		if kind == "fade_out": _check(curtain.color.a > 0.0, "destroy while fade is actually in progress")
		if kind == "move": _check(fixture.actor.process_mode == Node.PROCESS_MODE_DISABLED, "moving actor suspended by this cutscene")
		fixture.runner.queue_free()
		await process_frame
		_check(fixture.locks.size() == 1 and fixture.locks.has(&"another_owner"), "destroy %s releases only own input lock" % kind)
		_check(fixture.camera.is_current() and not is_instance_valid(curtain) and fixture.actor.process_mode == Node.PROCESS_MODE_INHERIT, "destroy %s restores camera, curtain and actor processing" % kind)
		_check(fixture.service.has_completed(event.id) and fixture.commits == 1 and not fixture.service.trigger(event.id), "destroy %s cannot duplicate committed result" % kind)
		fixture.dispose()
		fixture.free()
		await process_frame
	var fixture := _fixture()
	var event := _event(&"cancel_wait", ["wait"])
	event.cues[0].duration = 10.0
	fixture.service.register_event(event)
	fixture.allow_acquire = false
	_check(not fixture.runner.play(event.id) and fixture.commits == 0, "input lock rejection does not commit event")
	fixture.allow_acquire = true
	_check(fixture.runner.play(event.id) and fixture.runner.cancel() and not fixture.runner.cancel(), "cancel API is idempotent")
	_check(not fixture.runner.is_playing() and fixture.camera.is_current() and fixture.locks.size() == 1, "cancel restores presentation ownership")
	fixture.dispose()
	fixture.free()
	await process_frame


func _check_view_and_reentry() -> void:
	var fixture := _fixture()
	var dialogue := DialogueDouble.new()
	fixture.add_child(dialogue)
	fixture.runner.configure(fixture.service, fixture.acquire, fixture.unlock, fixture.resolve_actor, fixture.face_actor, fixture.camera, dialogue)
	var event := _event(&"replacement", ["line", "choice"])
	fixture.service.register_event(event)
	_check(fixture.runner.play(event.id) and dialogue.showing, "replace native dialogue without changing service")
	dialogue.advanced.emit()
	_check(fixture.runner.current_status().kind == "choice", "replacement dialogue signal advances line")
	dialogue.selected.emit(0)
	_check(not fixture.runner.is_playing() and not dialogue.showing, "replacement choice signal finishes")
	fixture.runner.release()
	_check(dialogue.advanced.get_connections().is_empty() and dialogue.selected.get_connections().is_empty() and dialogue.skip_requested.get_connections().is_empty() and dialogue.tree_exiting.get_connections().is_empty(), "release unbinds every external View signal")
	fixture.dispose()
	fixture.free()
	await process_frame
	fixture = _fixture()
	dialogue = DialogueDouble.new()
	fixture.add_child(dialogue)
	fixture.runner.configure(fixture.service, fixture.acquire, fixture.unlock, fixture.resolve_actor, fixture.face_actor, fixture.camera, dialogue)
	event = _event(&"removed_view", ["line"])
	fixture.service.register_event(event)
	fixture.runner.play(event.id)
	dialogue.queue_free()
	await process_frame
	_check(not fixture.runner.is_playing() and fixture.camera.is_current() and fixture.locks.size() == 1, "destroy external dialogue cancels playback and releases ownership")
	fixture.dispose()
	fixture.free()
	await process_frame
	fixture = _fixture()
	var first := _event(&"first", ["wait"])
	var second := _event(&"second", ["line", "choice"])
	fixture.service.register_event(first)
	fixture.service.register_event(second)
	fixture.runner.playback_started.connect(func(id: StringName) -> void:
		if id == &"first":
			fixture.runner.cancel()
			fixture.runner.play(&"second"))
	_check(fixture.runner.play(&"first") and fixture.runner.current_status().event == "second" and fixture.runner.current_status().kind == "line", "obsolete start callback cannot advance a newly started playback")
	var other := Camera2D.new()
	fixture.add_child(other)
	other.make_current()
	fixture.runner.cancel()
	_check(other.is_current(), "cleanup does not steal a later camera owner's current shot")
	fixture.dispose()
	fixture.free()
	await process_frame
	fixture = _fixture()
	event = _event(&"escape", ["wait"])
	event.cues[0].duration = 5.0
	fixture.service.register_event(event)
	fixture.runner.play(event.id)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	_check(not fixture.runner.is_playing() and fixture.camera.is_current() and fixture.locks.size() == 1, "real Escape input skips during wait")
	fixture.dispose()
	fixture.free()
	await process_frame


func _check_recovery() -> void:
	var fixture := _fixture()
	_check(fixture.service.load_directory("res://data/events") >= 1 and fixture.service.definition(&"ch1_market_memory") != null, "ResourceLoader discovers authored sample event")
	var event := _event(&"disk", ["wait"])
	event.cues[0].duration = 10.0
	fixture.service.register_event(event)
	var registry := Registry.new()
	registry.register_section(&"coins", func() -> int: return fixture.wallet.coins, func(value: int) -> void: fixture.wallet.coins = value, TYPE_INT)
	registry.register_section(&"events", fixture.service.encode, func(data: Dictionary) -> void:
		fixture.runner.cancel()
		fixture.service.restore(data), TYPE_DICTIONARY, true)
	_check(fixture.runner.play(event.id), "start playback before disk save")
	var store := Store.new()
	_check(store.write("user://story_events.json", registry.collect()), "isolated atomic store saves events with original wallet")
	var document: Dictionary = store.read("user://story_events.json")
	for index: int in 3:
		registry.restore(document)
		_check(not fixture.runner.is_playing() and fixture.wallet.coins == 525 and fixture.service.has_completed(event.id) and fixture.commits == 1 and fixture.camera.is_current() and fixture.locks.size() == 1, "disk restore %d cancels old presentation and never settles" % index)
	registry.restore({"coins": 500})
	_check(not fixture.service.has_completed(event.id), "old saves missing optional event section reset records")
	registry.clear()
	fixture.dispose()
	fixture.free()
	await process_frame
