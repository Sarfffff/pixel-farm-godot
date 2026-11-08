extends RefCounted
## 包外驱动，运行资源/业务与 View 均从真实 PCK 加载。


static func run(tree: SceneTree, main: Node, check: Callable) -> void:
	var service: RefCounted = load("res://scripts/events/event_service.gd").new()
	var wallet: Economy = main.get_node("Systems/Economy")
	var before: int = wallet.coins
	var commits: Array[int] = [0]
	service.configure(func(kind: StringName, _key: StringName) -> Variant:
		if kind == &"day": return 4
		if kind == &"location": return &"home"
		if kind == &"quest": return &"completed"
		return null,
		func(_id: StringName, _outcome: StringName) -> bool:
			commits[0] += 1
			wallet.earn(7)
			return true)
	check.call(service.load_directory("res://data/events") >= 1, "pack discovers event resources through ResourceLoader")
	var event: Resource = load("res://data/events/market_memory.tres").duplicate(true)
	event.id = &"pack_story_probe"
	event.outcome = &"atomic_pack_probe"
	check.call(service.register_event(event), "pack registers event and its typed condition/cue subresources")
	var locks: Dictionary = {&"unrelated": true}
	var runner: Node = load("res://scripts/events/cutscene_player.gd").new()
	runner.configure(service,
		func(owner: StringName) -> bool:
			locks[owner] = true
			return true,
		func(owner: StringName) -> void: locks.erase(owner), Callable(), Callable(), main.get_node("Camera"))
	main.get_node("Systems").add_child(runner)
	check.call(runner.play(event.id) and wallet.coins == before + 7 and commits[0] == 1, "pack commits story before rendering dialogue")
	check.call(runner.skip() and not runner.is_playing() and locks.size() == 1 and main.get_node("Camera").is_current(), "pack skip releases only its own lock and camera")
	var registry: RefCounted = load("res://scripts/persistence/snapshot_registry.gd").new()
	registry.register_section(&"events", service.encode, service.restore, TYPE_DICTIONARY, true)
	var store: RefCounted = load("res://scripts/persistence/json_save_store.gd").new()
	check.call(store.write("user://pack_story_events.json", registry.collect()), "pack writes event completion in isolated storage")
	for index: int in 3:
		registry.restore(store.read("user://pack_story_events.json"))
		check.call(service.has_completed(event.id) and not service.trigger(event.id) and commits[0] == 1 and wallet.coins == before + 7, "pack repeated event restore %d does not settle twice" % index)
	registry.clear()
	runner.release()
	runner.queue_free()
	service.release()
	await tree.process_frame
