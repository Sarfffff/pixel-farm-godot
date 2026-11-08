extends SceneTree
## B3-03独立设备：真实库存净交换、碰撞工厂、仓储、严格恢复及MVP解绑。

const Service := preload("res://scripts/placement/placement_service.gd")
const World := preload("res://scripts/placement/device_world.gd")
const PlacementView := preload("res://scripts/ui/panels/placement_panel.gd")
const PlacementPresenter := preload("res://scripts/ui/presenters/placement_presenter.gd")
const StorageView := preload("res://scripts/ui/panels/device_storage_panel.gd")
const StoragePresenter := preload("res://scripts/ui/presenters/device_storage_presenter.gd")
const Preview := preload("res://scripts/world/interactions/placement_preview.gd")
const Modals := preload("res://scripts/ui/common/modal_coordinator.gd")
var _checks: int = 0
var _failures: int = 0
var _scene: Node2D
var _world: Node2D
var _bag: Inventory
var _save: SaveSystem
var _service := Service.new()
var _factory := World.new()
var _catalog: Array = []
var _ports: Dictionary
var _save_ok: bool = true
var _writes: int = 0
var _fence: String
var _crate: String
var _other_crate: String


func _init() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	_checks += 1
	if not value:
		_failures += 1
		printerr("[placement] FAIL: " + message)


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	_scene = Node2D.new()
	root.add_child(_scene)
	current_scene = _scene
	_world = Node2D.new()
	_scene.add_child(_world)
	_bag = Inventory.new()
	_scene.add_child(_bag)
	_save = SaveSystem.new()
	_save.autoload_enabled = false
	_scene.add_child(_save)
	await process_frame
	for file: String in ResourceLoader.list_directory("res://data/devices"):
		if file.ends_with(".tres"): _catalog.append(load("res://data/devices/".path_join(file)))
	_factory.configure(_world, _position)
	_ports = {"query": _query, "allowed": func(_item: StringName) -> bool: return true, "create": _factory.create, "update": _factory.update_instance, "remove": _factory.remove_instance, "restore": _factory.restore_instances, "save": _persist}
	_service.configure(_bag, _catalog, _ports)
	_save.snapshots.register_section(&"inventory", _bag.to_dict, _bag.from_dict)
	_save.snapshots.register_section(&"devices", _service.encode, _service.restore, TYPE_DICTIONARY, true)
	_save.saved.connect(_confirmed)
	_bag.add_item(&"wood_fence", 10, &"crafting")
	_bag.add_item(&"storage_crate", 3, &"crafting")
	_check_rules()
	_check_transactions()
	_check_storage()
	_check_failures()
	await _check_views()
	_check_restoration()
	await process_frame
	_check(_world.get_child_count() == _service.instances().size(), "final live projection matches exactly the authoritative instances")
	_check(true, "all placement, storage, persistence and lifecycle probes reached their end")
	_service.release()
	_factory.release()
	_save.saved.disconnect(_confirmed)
	_scene.queue_free()
	await process_frame
	print("[placement] %d checks; %d failures; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _position(cell: Vector2i) -> Vector2:
	return Vector2(cell * 16) + Vector2(8, 8)


func _query(space: StringName, cells: Array[Vector2i], _ignore: String, _restoring: bool) -> Dictionary:
	if space != &"home": return {"ok": false, "reason": "区域未开放"}
	var blocked: Dictionary = {Vector2i(1, 1): "水面", Vector2i(2, 1): "作物", Vector2i(3, 1): "人物", Vector2i(4, 1): "门口", Vector2i(5, 1): "出口通道", Vector2i(6, 1): "静态物件"}
	for cell: Vector2i in cells:
		if not Rect2i(0, 0, 12, 12).has_point(cell): return {"ok": false, "reason": "地图边界"}
		if blocked.has(cell): return {"ok": false, "reason": blocked[cell]}
	return {"ok": true, "reason": ""}


func _persist() -> bool:
	_writes += 1
	return _save_ok and _save.save_game()


func _confirmed(_slot: int) -> void:
	_service.confirm_saved()


func _check_rules() -> void:
	_check(_catalog.size() == 2 and _service.type_for_item(&"wood_fence") == &"wood_fence" and _service.type_for_item(&"storage_crate") == &"storage_crate", "trusted authored catalog maps actual craftable item IDs")
	_check(not _service.preview(&"unknown", &"home", Vector2i.ZERO, 0).ok and not _service.preview(&"wood_fence", &"forest", Vector2i.ZERO, 0).ok, "unknown types and unopened regions reject")
	_check(not _service.preview(&"wood_fence", &"home", Vector2i.ZERO, -1).ok and not _service.preview(&"wood_fence", &"home", Vector2i.ZERO, 4).ok, "invalid orientations reject")
	for x: int in range(1, 7):
		var result: Dictionary = _service.preview(&"wood_fence", &"home", Vector2i(x, 1), 0)
		_check(not result.ok and not result.reason.is_empty(), "world port rejects blocked terrain %d with an explanation" % x)
	var wide: Resource = _catalog[0].duplicate()
	wide.id = &"wide_fixture"
	wide.footprint = Vector2i(2, 1)
	_service.configure(_bag, _catalog + [wide], _ports)
	_check(wide.cells(Vector2i.ZERO, 0) == [Vector2i.ZERO, Vector2i(1, 0)] and wide.cells(Vector2i.ZERO, 1) == [Vector2i.ZERO, Vector2i(0, 1)], "rotating an asymmetric footprint changes all occupied cells")
	_check(not _service.preview(&"wide_fixture", &"home", Vector2i(11, 3), 0).ok and _service.preview(&"wide_fixture", &"home", Vector2i(11, 3), 1).ok, "full rotated footprint respects map boundary")
	_check(not _service.preview(&"wide_fixture", &"home", Vector2i(0, 1), 0).ok, "secondary footprint cell cannot overlap water")
	_service.configure(_bag, _catalog, _ports)
	var denied: Dictionary = _ports.duplicate()
	denied.allowed = func(_item: StringName) -> bool: return false
	_service.configure(_bag, _catalog, denied)
	_check(not _service.preview(&"wood_fence", &"home", Vector2i.ZERO, 0).ok, "real eligibility port gates new placement")
	_service.configure(_bag, _catalog, _ports)
	var before: Dictionary = _bag.to_dict()
	_service.preview(&"wood_fence", &"home", Vector2i(2, 3), 0)
	_check(_bag.to_dict() == before and _service.instances().is_empty() and _world.get_child_count() == 0, "preview creates no instances, occupancy or inventory writes")
	var reentrant: Dictionary = _ports.duplicate()
	reentrant.query = func(space: StringName, cells: Array[Vector2i], ignore: String, restoring: bool) -> Dictionary:
		_check(_service.place(&"wood_fence", &"home", Vector2i(9, 9), 0).is_empty(), "query callback cannot reenter a preview or commit")
		return _query(space, cells, ignore, restoring)
	_service.configure(_bag, _catalog, reentrant)
	_check(_service.preview(&"wood_fence", &"home", Vector2i(2, 3), 0).ok and _bag.to_dict() == before and _service.instances().is_empty(), "preview remains read-only even with a reentrant query adapter")
	_service.configure(_bag, _catalog, _ports)


func _check_transactions() -> void:
	var observations: Array[bool] = []
	var before: int = _bag.count_of(&"wood_fence")
	var listener := func() -> void:
		observations.append(_service.instances().size() == 1 and _world.get_child_count() == 1 and _bag.count_of(&"wood_fence") == before - 1)
		_check(_service.place(&"wood_fence", &"home", Vector2i(9, 9), 0).is_empty() and not _service.dismantle("device_000000000001"), "inventory observer cannot submit same or cross-instance work")
		_check(not _service.restore({}), "observer cannot restore over a live placement")
	_bag.changed.connect(listener)
	_fence = _service.place(&"wood_fence", &"home", Vector2i(2, 3), 0)
	_bag.changed.disconnect(listener)
	_check(not _fence.is_empty() and observations.size() == 1 and not observations.has(false), "inventory observers see the entire placement already committed")
	var fence_node: Node2D = _factory.node_for(_fence)
	_check(fence_node != null and fence_node.get_child(1) is StaticBody2D and (fence_node.get_child(1).get_child(0) as CollisionShape2D).shape is RectangleShape2D, "authored fence has real nested collision for navigation scanning")
	var snapshot: Dictionary = _service.encode()
	_check(_service.place(&"wood_fence", &"home", Vector2i(2, 3), 1).is_empty() and _service.encode() == snapshot, "double placement cannot overlap the first device")
	_crate = _service.place(&"storage_crate", &"home", Vector2i(4, 3), 0)
	_other_crate = _service.place(&"storage_crate", &"home", Vector2i(6, 3), 0)
	_check(not _crate.is_empty() and not _other_crate.is_empty() and _crate != _other_crate, "two identical device types have independent stable instance IDs")
	var position: Vector2 = fence_node.position
	_check(not _service.move(_fence, &"home", Vector2i(4, 3), 1) and _factory.node_for(_fence).position == position and _service.instance(_fence).cell == [2, 3], "failed move keeps ID, position and occupancy unchanged")
	_check(_service.move(_fence, &"home", Vector2i(2, 4), 1) and _service.instance(_fence).id == _fence and _service.instance(_fence).facing == 1, "valid rotation and movement retain stable identity")
	var signal_observer := func(_id: String) -> void:
		_check(not _service.dismantle(_crate) and not _service.move(_other_crate, &"home", Vector2i(8, 8), 0), "success notification rejects cross-device submissions")
	_service.moved.connect(signal_observer)
	_service.move(_fence, &"home", Vector2i(2, 3), 0)
	_service.moved.disconnect(signal_observer)


func _check_storage() -> void:
	_bag.add_item(&"wood", 5, &"transfer")
	var collected: int = _bag.today_collected
	var observed: Array[bool] = []
	var listener := func() -> void:
		observed.append(_service.storage_count(_crate, &"wood") == 3 and _bag.count_of(&"wood") == 2)
		_check(_service.withdraw(_crate, &"wood", 3) == 0 and _service.deposit(_other_crate, &"wood", 1) == 0, "storage notifications reject same and cross-box reentry")
	_bag.changed.connect(listener)
	_check(_service.deposit(_crate, &"wood", 3) == 3, "crate uses the existing storage transfer transaction")
	_bag.changed.disconnect(listener)
	_check(observed.size() == 1 and not observed.has(false) and _service.storage_count(_other_crate, &"wood") == 0, "both sides commit before notifications and separate crates do not share contents")
	_check(not _service.dismantle(_crate) and not _service.move(_crate, &"home", Vector2i(7, 7), 0), "nonempty box cannot be moved or destroyed")
	_check(_service.withdraw(_crate, &"wood", 1) == 1 and _service.storage_count(_crate, &"wood") == 2 and _bag.today_collected == collected, "withdrawal is a transfer and creates no harvest credit")
	var filled: Array = []
	for id: StringName in Inventory.TOOL_IDS: filled.append({"id": String(id), "count": 1})
	while filled.size() < _bag.slot_count(): filled.append({"id": "carrot", "count": _bag.definition(&"carrot").max_stack})
	var bag: Dictionary = _bag.to_dict()
	_bag.from_dict({"slots": filled})
	var devices: Dictionary = _service.encode()
	_check(not _service.dismantle(_fence) and _service.encode() == devices and _factory.node_for(_fence) != null, "full bag preserves the entire dismantled device")
	_check(_service.withdraw(_crate, &"wood", 2) == 0 and _service.storage_count(_crate, &"wood") == 2, "full bag leaves stored contents untouched")
	_bag.from_dict(bag)
	_check(_service.dismantle(_other_crate) and not _service.dismantle(_other_crate), "empty box dismantles once and cannot refund twice")
	_check(_factory.node_for(_other_crate) == null and _service.instance(_other_crate).is_empty(), "dismantling immediately removes both instance and collision projection")


func _check_failures() -> void:
	var ports: Dictionary = _ports.duplicate()
	ports.create = func(definition: Resource, record: Dictionary) -> bool:
		_factory.create(definition, record)
		return false
	_service.configure(_bag, _catalog, ports)
	var devices: Dictionary = _service.encode()
	var bag: Dictionary = _bag.to_dict()
	var nodes: int = _world.get_child_count()
	_check(_service.place(&"wood_fence", &"home", Vector2i(9, 9), 0).is_empty() and _world.get_child_count() == nodes and _service.encode() == devices and _bag.to_dict() == bag, "failed factory cleans half-created nodes without consuming item or stable ID")
	ports = _ports.duplicate()
	ports.update = func(_record: Dictionary) -> bool: return false
	_service.configure(_bag, _catalog, ports)
	_check(not _service.move(_fence, &"home", Vector2i(9, 9), 1) and _service.encode() == devices, "failed projection update keeps model unchanged")
	_service.configure(_bag, _catalog, _ports)
	_save_ok = false
	var failed: Array[bool] = []
	var listener := func() -> void: failed.append(true)
	_service.save_failed.connect(listener)
	_check(_service.move(_fence, &"home", Vector2i(2, 4), 1) and _service.save_pending and failed.size() == 1, "failed save retains committed device and exposes retry state")
	_save_ok = true
	var state: Dictionary = _service.encode()
	var writes: int = _writes
	_check(_save.save_game() and not _service.save_pending, "successful save from another entry point acknowledges devices")
	_service.confirm_saved()
	_service.confirm_saved()
	_check(_service.encode() == state and _writes == writes, "repeated acknowledgement performs neither gameplay nor save recursion")
	_service.save_failed.disconnect(listener)


func _check_views() -> void:
	var modals := Modals.new()
	_scene.add_child(modals)
	var allowed: Array[bool] = [false]
	modals.opening_allowed = func() -> bool: return allowed[0]
	var view := PlacementView.new()
	_scene.add_child(view)
	modals.register_panel(view)
	var presenter := PlacementPresenter.new()
	_scene.add_child(presenter)
	var before: int = _service.changed.get_connections().size()
	presenter.configure(_service, view)
	var preview := Preview.new()
	_scene.add_child(preview)
	preview.configure(_position)
	presenter.preview_changed.connect(preview.render)
	presenter.open_place(&"wood_fence", Vector2i(8, 8))
	var records: Dictionary = _service.encode()
	view.commit_requested.emit()
	_check(not view.visible and _service.encode() == records and not paused, "real placement modal rejection cannot commit or pause")
	allowed[0] = true
	presenter.open_move(_fence)
	view.rotate_requested.emit()
	_check(view.visible and paused and presenter.snapshot().facing == 2, "real placement view previews rotation through Presenter")
	presenter.set_target(Vector2i(4, 3))
	_check(not presenter.snapshot().ok, "move preview exposes cross-device occupancy reason")
	var next := PlacementView.new()
	_scene.add_child(next)
	modals.register_panel(next)
	presenter.configure(_service, next)
	view.dismantle_requested.emit()
	_check(not view.visible and not paused and not _service.instance(_fence).is_empty() and view.commit_requested.get_connections().is_empty(), "replacing placement view releases modal and every old intent")
	presenter.queue_free()
	await process_frame
	_check(_service.changed.get_connections().size() == before, "placement Presenter disconnects its model observer")
	var storage_view := StorageView.new()
	_scene.add_child(storage_view)
	modals.register_panel(storage_view)
	var storage_presenter := StoragePresenter.new()
	_scene.add_child(storage_presenter)
	var bag_connections: int = _bag.changed.get_connections().size()
	storage_presenter.configure(_service, _bag, storage_view)
	storage_presenter.open_storage(_crate)
	_check(storage_view.visible and paused and not storage_presenter.snapshot().storage.is_empty(), "real crate UI displays its independent contents")
	storage_view.withdraw_requested.emit(&"wood", false)
	_check(_service.storage_count(_crate, &"wood") == 1, "crate View intent uses the shared transfer service")
	var managed: Array[String] = []
	storage_presenter.manage_requested.connect(func(id: String) -> void: managed.append(id))
	storage_view.manage_requested.emit()
	_check(managed == [_crate] and not storage_view.visible and not paused and _service.storage_count(_crate, &"wood") == 1, "crate management releases its modal before forwarding the stable ID without moving contents")
	storage_presenter.queue_free()
	await process_frame
	_check(not storage_view.visible and not paused and _bag.changed.get_connections().size() == bag_connections and _service.changed.get_connections().size() == before and storage_view.withdraw_requested.get_connections().is_empty() and storage_view.manage_requested.get_connections().is_empty(), "storage Presenter teardown closes modal and disconnects all sources")
	for node: Node in [view, next, preview, storage_view, modals]: node.queue_free()
	await process_frame


func _check_restoration() -> void:
	var expected: Dictionary = _service.encode()
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(expected))
	var bag: Dictionary = _bag.to_dict()
	var writes: int = _writes
	for index: int in 3: _check(_service.restore(snapshot), "JSON snapshot restore succeeds %d" % index)
	_check(_service.encode() == expected and _bag.to_dict() == bag and _writes == writes and _world.get_child_count() == snapshot.instances.size() and _service.storage_count(_crate, &"wood") == 1, "three restores neither duplicate nodes nor grant, discard or resave materials")
	var bad: Dictionary = snapshot.duplicate(true)
	bad.instances[0].type_id = "res://arbitrary_scene.tscn"
	_check(not _service.restore(bad) and _service.encode() == expected, "unknown type or arbitrary scene path atomically preserves the previous state")
	for value: Variant in ["oops", -1, 1.5, true]:
		bad = snapshot.duplicate(true)
		bad.instances[0].facing = value
		_check(not _service.restore(bad) and _service.encode() == expected, "malformed facing rejected without partial restoration")
	bad = snapshot.duplicate(true)
	bad.instances.append(bad.instances[0].duplicate(true))
	_check(not _service.restore(bad), "duplicate stable IDs reject")
	bad = snapshot.duplicate(true)
	bad.instances[1].cell = bad.instances[0].cell.duplicate()
	_check(not _service.restore(bad), "overlapping saved instances reject")
	bad = snapshot.duplicate(true)
	bad.instances[0].cell = [4, 1]
	_check(not _service.restore(bad), "restoration cannot occupy a protected doorway")
	bad = snapshot.duplicate(true)
	bad.instances[1].slots = [{"id": "wood", "count": 999999}]
	_check(not _service.restore(bad) and _service.encode() == expected, "invalid storage amounts never become free materials")
	var ports: Dictionary = _ports.duplicate()
	ports.restore = func(_definitions: Dictionary, _records: Array) -> bool: return false
	_service.configure(_bag, _catalog, ports)
	_check(not _service.restore(snapshot) and _service.encode() == expected and _world.get_child_count() == snapshot.instances.size(), "failed restore factory preserves both current model and live nodes")
	_service.configure(_bag, _catalog, _ports)
	for phase: String in ["processing", "ready"]:
		var working: Dictionary = snapshot.duplicate(true)
		working.instances[0].operation.phase = phase
		working.instances[0].operation.recipe_id = "future_recipe"
		working.instances[0].operation.inputs = {"wood": 1}
		working.instances[0].operation.pending_outputs = {"stone": 1}
		_check(_service.restore(working) and not _service.dismantle(working.instances[0].id) and not _service.move(working.instances[0].id, &"home", Vector2i(8, 8), 0), "busy or unclaimed content survives and cannot be dismantled or moved: " + phase)
		_check(_bag.to_dict() == bag and _writes == writes, "restoring work facts never produces or refunds anything")
	_service.restore(snapshot)
	_check(_save.save_game(), "isolated real SaveSystem writes devices partition")
	_service.restore({})
	_check(_service.instances().is_empty() and _world.get_child_count() == 0, "missing optional partition removes previous-session dynamic instances")
	_check(_save.load_game() and _service.encode() == expected and _bag.to_dict() == bag, "real disk reload rebuilds device types, IDs, positions and independent storage without rewards")
	var legacy: Dictionary = _save.collect()
	legacy.erase("devices")
	_save.apply(legacy)
	_check(_service.instances().is_empty() and _world.get_child_count() == 0 and _bag.to_dict() == bag, "old v2 save missing devices initializes empty without touching fixed storage or player bag")
