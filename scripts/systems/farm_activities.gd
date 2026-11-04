extends Node
## 新活动统一接入旧交互、背包、时间、社区和存档；不另建金币或日历。

signal changed

const Settings = preload("res://scripts/data/farm_activities_data.gd")
const Recipe = preload("res://scripts/data/processing_recipe_data.gd")
const Store = preload("res://scripts/systems/stack_store.gd")
const Prop = preload("res://scripts/world/activity_prop.gd")
const ActivityPanel = preload("res://scripts/ui/farm_activities_panel.gd")
const CommunityVisuals = preload("res://scripts/world/community_visuals.gd")
const SETTINGS: Settings = preload("res://data/activities/farm_activities.tres")
const RECIPE: Recipe = preload("res://data/recipes/pickled_tomato.tres")
const CHEST_ART: Texture2D = preload("res://assets/generated/content_v1/objects/craftables/wood_chest.png")
const MACHINE_ART: Texture2D = preload("res://assets/generated/content_v1/objects/craftables/preserves_jar.png")
const ROD_ART: Texture2D = preload("res://assets/generated/expansion_v1/fishing/bamboo_rod.png")
const BOBBER_ART: Texture2D = preload("res://assets/generated/expansion_v1/fishing/bobber.png")
const SIGN_ART: Texture2D = preload("res://assets/generated/content_v1/objects/craftables/sign_board.png")

var settings: Settings = SETTINGS
var inventory: Inventory
var player: CharacterBody2D
var storage: Store
var panel: ActivityPanel
var visuals: CommunityVisuals
var pickups: Array[Prop] = []
var depleted: Array[int] = []
var last_day: int = 1
var processing_ready_day: int = 0
var casts_today: int = 0
var pending_fish: StringName = &""
var fishing_state: StringName = &"idle"
var message: String = ""
var _candidate: StringName = &""
var _elapsed: float = 0.0
var _wait: float = 0.0
var _bite_elapsed: float = 0.0
var _rod: Sprite2D
var _bobber: Sprite2D
var _line: Line2D
var _machine_status: Label
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _cast_tween: Tween


func _ready() -> void:
	add_to_group(&"farm_activities")
	_rng.randomize()
	inventory = get_tree().get_first_node_in_group(&"inventory") as Inventory
	player = get_tree().get_first_node_in_group(&"player") as CharacterBody2D
	storage = Store.new(settings.storage_capacity)
	var main: Node = get_parent().get_parent()
	var world: Node2D = main.get_node("Farm/World") as Node2D
	var ui: Node = main.get_node("UI")
	_prop(world, &"storage", -1, settings.chest_position, CHEST_ART, true)
	var machine: Prop = _prop(world, &"processing", -1, settings.machine_position, MACHINE_ART, true)
	_machine_status = Label.new()
	_machine_status.position = Vector2(-13, -35)
	_machine_status.add_theme_font_size_override("font_size", 6)
	_machine_status.add_theme_color_override("font_color", Color("514c40"))
	machine.add_child(_machine_status)
	var marker: Prop = _prop(world, &"fishing", -1, settings.fishing_position, SIGN_ART, false)
	marker.radius = 22.0
	marker.offset.x = 22
	var symbol: Sprite2D = Sprite2D.new()
	symbol.texture = ROD_ART
	symbol.position = Vector2(22, -12)
	symbol.scale = Vector2.ONE * 0.45
	marker.add_child(symbol)
	for index: int in settings.forage_positions.size():
		var item: ItemData = inventory.definition(settings.forage_items[index])
		if item != null:
			pickups.append(_prop(world, &"forage", index, settings.forage_positions[index], item.icon, false))
	visuals = CommunityVisuals.new()
	visuals.world = world
	add_child(visuals)
	panel = ActivityPanel.new()
	panel.name = "FarmActivitiesPanel"
	panel.manager = self
	ui.add_child(panel)
	_rod = Sprite2D.new()
	_rod.texture = ROD_ART
	_rod.position = Vector2(5, -9)
	_rod.scale = Vector2.ONE * 0.65
	_rod.z_index = 1
	player.add_child(_rod)
	_bobber = Sprite2D.new()
	_bobber.texture = BOBBER_ART
	_bobber.position = settings.fishing_target
	_bobber.scale = Vector2.ONE * 0.3
	# 浮标本来就浮在水面上，标一下组，别被"道具脚下不能有水深"这类检查误判。
	_bobber.add_to_group(&"water_visual")
	world.add_child(_bobber)
	_line = Line2D.new()
	_line.width = 1.0
	_line.default_color = Color("eee3c2")
	_line.add_to_group(&"water_visual")
	world.add_child(_line)
	_set_fishing_visual(false)
	var clock: Node = _clock()
	if clock != null:
		last_day = int(clock.day)
		clock.day_started.connect(on_day_started)
	_refresh_world()


func _prop(world: Node2D, kind: StringName, key: int, position: Vector2, texture: Texture2D, solid: bool) -> Prop:
	var prop: Prop = Prop.new()
	prop.name = String(kind).to_pascal_case() + str(key)
	prop.kind = kind
	prop.key = key
	prop.manager = self
	prop.position = position
	prop.texture = texture
	prop.offset = Vector2(0, -12 if solid or kind == &"fishing" else -5)
	world.add_child(prop)
	if solid:
		prop.add_body(Vector2(16, 8))
	return prop


func _process(delta: float) -> void:
	tick_fishing(delta)
	if _line.visible:
		_line.points = PackedVector2Array([player.global_position + Vector2(11, -23), _bobber.position])


func activity_hint(kind: StringName, key: int = -1) -> String:
	match kind:
		&"storage": return "[E] 农场木箱 · 存取物品"
		&"processing":
			if processing_ready_day == 0:
				return "[E] 腌制台 · 番茄 ×3 → 腌菜 ×1 / 过夜完成"
			return "[E] 领取番茄腌菜" if processing_ready_day <= today() else "腌制中 · 第 %d 天可领取" % processing_ready_day
		&"forage":
			if key >= 0 and key < settings.forage_items.size():
				return "[E] 采集%s · 体力 1" % inventory.definition(settings.forage_items[key]).display_name
		&"fishing":
			return "[E] 领取寄存鱼获" if pending_fish != &"" else "[E] 池塘钓鱼 · 竹鱼竿 / 每天三次"
	return ""


func interact_activity(kind: StringName, key: int = -1) -> void:
	match kind:
		&"storage":
			message = ""
			panel.open(&"storage")
		&"processing": use_processing()
		&"forage": collect_forage(key)
		&"fishing":
			if pending_fish == &"" and inventory.count_of(&"bamboo_rod") < 1:
				_notify("先去商店买竹鱼竿 · 80 金币")
				return
			message = ""
			panel.open(&"fishing")


func deposit(id: StringName, amount: int) -> int:
	var item: ItemData = inventory.definition(id)
	if item == null or amount <= 0:
		return 0
	if item.category == &"tool":
		_notify("工具随身保管，不放入木箱")
		return 0
	var moved: int = mini(mini(amount, inventory.count_of(id)), storage.capacity_for(id, item.max_stack))
	if moved <= 0:
		_notify("木箱已满 · 物品仍在背包")
		return 0
	if not inventory.remove_item(id, moved):
		return 0
	storage.add(id, moved, item.max_stack)
	_notify("存入%s ×%d" % [item.display_name, moved])
	_persist()
	return moved


func withdraw(id: StringName, amount: int) -> int:
	var item: ItemData = inventory.definition(id)
	if item == null or amount <= 0:
		return 0
	var moved: int = mini(mini(amount, storage.count_of(id)), _bag_capacity(id, item.max_stack))
	if moved <= 0:
		_notify("背包已满 · 物品仍在木箱")
		return 0
	if not storage.remove(id, moved):
		return 0
	var collected: int = inventory.today_collected
	inventory.add_item(id, moved)
	inventory.today_collected = collected
	_notify("取出%s ×%d" % [item.display_name, moved])
	_persist()
	return moved


func _bag_capacity(id: StringName, maximum: int) -> int:
	var result: int = 0
	for index: int in inventory.slot_count():
		var slot: Dictionary = inventory.item_at(index)
		if slot.is_empty():
			result += maximum
		elif StringName(slot[&"id"]) == id:
			result += maxi(0, maximum - int(slot[&"count"]))
	return result


func collect_forage(index: int) -> bool:
	if index < 0 or index >= settings.forage_items.size() or depleted.has(index):
		return false
	var id: StringName = settings.forage_items[index]
	if not inventory.has_space_for(id, 1):
		_notify("背包已满 · 采集物留在原地")
		return false
	if not _spend(1):
		return false
	inventory.add_item(id, 1)
	depleted.append(index)
	_refresh_world()
	_notify("采到%s" % inventory.definition(id).display_name)
	_persist()
	return true


func use_processing() -> bool:
	if processing_ready_day > 0:
		if processing_ready_day > today():
			_notify("腌制中 · 第 %d 天可领取" % processing_ready_day)
			return false
		if not inventory.has_space_for(RECIPE.product, RECIPE.product_count):
			_notify("背包已满 · 腌菜保留在加工台")
			return false
		inventory.add_item(RECIPE.product, RECIPE.product_count)
		processing_ready_day = 0
		_notify("领取%s ×%d" % [RECIPE.display_name, RECIPE.product_count])
	else:
		if not inventory.remove_item(RECIPE.ingredient, RECIPE.ingredient_count):
			_notify("需要番茄 ×%d · 收获后再来腌制" % RECIPE.ingredient_count)
			return false
		processing_ready_day = today() + maxi(1, RECIPE.days)
		_notify("已投入番茄 · 第 %d 天腌制完成" % processing_ready_day)
	_refresh_world()
	_persist()
	return true


func fishing_action() -> bool:
	if pending_fish != &"":
		return claim_fish()
	if fishing_state == &"bite":
		pending_fish = _candidate
		_candidate = &""
		fishing_state = &"ready"
		_set_fishing_visual(false)
		_persist()
		return claim_fish()
	if fishing_state == &"waiting":
		return false
	return start_fishing()


func start_fishing() -> bool:
	if fishing_state in [&"waiting", &"bite"] or pending_fish != &"":
		return false
	if inventory.count_of(&"bamboo_rod") < 1:
		_notify("先去商店买竹鱼竿 · 80 金币")
		return false
	if casts_today >= settings.fishing_limit:
		_notify("今天已投竿三次 · 明天再来")
		return false
	var candidate: StringName = settings.fish_items[_rng.randi_range(0, settings.fish_items.size() - 1)]
	if not inventory.has_space_for(candidate, 1):
		_notify("背包已满 · 先腾出一个鱼获位置")
		return false
	if not _spend(settings.fishing_cost):
		return false
	casts_today += 1
	_candidate = candidate
	_elapsed = 0.0
	_bite_elapsed = 0.0
	_wait = _rng.randf_range(settings.fish_wait_min, settings.fish_wait_max)
	fishing_state = &"waiting"
	message = ""
	player.set("_facing", &"down")
	_set_fishing_visual(true)
	if _cast_tween != null and _cast_tween.is_valid(): _cast_tween.kill()
	_cast_tween = create_tween()
	_rod.rotation = -0.7
	_cast_tween.tween_property(_rod, "rotation", 0.2, 0.3)
	_bobber.position = player.global_position + Vector2(5, -10)
	_cast_tween.parallel().tween_property(_bobber, "position", settings.fishing_target, 0.35)
	changed.emit()
	_persist()
	return true


func tick_fishing(delta: float) -> void:
	if fishing_state == &"waiting":
		_elapsed += maxf(0.0, delta)
		if _elapsed >= _wait:
			fishing_state = &"bite"
			_bite_elapsed = 0.0
			changed.emit()
	elif fishing_state == &"bite":
		_bite_elapsed += maxf(0.0, delta)
		_bobber.position.y = settings.fishing_target.y + (2 if int(_bite_elapsed * 8) % 2 == 0 else 0)
		if _bite_elapsed > settings.fish_bite_window:
			cancel_fishing()
			_notify("鱼溜走了 · 咬钩时按 E 或空格收杆")


func claim_fish() -> bool:
	if pending_fish == &"":
		return false
	if not inventory.has_space_for(pending_fish, 1):
		_notify("背包已满 · 鱼获寄存在钓点，腾出空间后领取")
		return false
	var id: StringName = pending_fish
	pending_fish = &""
	fishing_state = &"idle"
	inventory.add_item(id, 1)
	_notify("钓到%s！可去商店出售" % inventory.definition(id).display_name)
	_persist()
	return true


func cancel_fishing() -> void:
	if _cast_tween != null and _cast_tween.is_valid(): _cast_tween.kill()
	_candidate = &""
	fishing_state = &"ready" if pending_fish != &"" else &"idle"
	_set_fishing_visual(false)
	changed.emit()


func fishing_text() -> String:
	if fishing_state == &"waiting": return "浮漂入水了，耐心等鱼咬钩…"
	if fishing_state == &"bite": return "鱼咬钩了！现在收杆！"
	if pending_fish != &"": return "鱼获已寄存 · 腾出背包空间后领取"
	return message if not message.is_empty() else "池塘里有鲫鱼和鲤鱼。准备好就投竿吧。"


func fishing_progress() -> float:
	if fishing_state == &"waiting": return clampf(_elapsed / maxf(_wait, 0.01), 0, 1)
	if fishing_state == &"bite": return 1.0 - clampf(_bite_elapsed / maxf(settings.fish_bite_window, 0.01), 0, 1)
	return 0.0


func _set_fishing_visual(shown: bool) -> void:
	if is_instance_valid(_rod): _rod.visible = shown
	if is_instance_valid(_bobber): _bobber.visible = shown
	if is_instance_valid(_line): _line.visible = shown


func on_day_started(day: int) -> void:
	if day <= last_day:
		return
	last_day = day
	casts_today = 0
	for index: int in mini(settings.forage_respawn_per_day, depleted.size()):
		depleted.pop_front()
	cancel_fishing()
	_refresh_world()
	changed.emit()


func _refresh_world() -> void:
	for pickup: Prop in pickups:
		pickup.visible = not depleted.has(pickup.key)
	if is_instance_valid(_machine_status):
		_machine_status.text = "可领取" if processing_ready_day > 0 and processing_ready_day <= today() else "腌制中" if processing_ready_day > 0 else "腌制台"


func _clock() -> Node:
	return get_tree().get_first_node_in_group(&"time")


func today() -> int:
	var clock: Node = _clock()
	return int(clock.day) if clock != null else 1


func tomorrow_text() -> String:
	var parts: Array[String] = []
	if processing_ready_day > 0 and processing_ready_day <= today() + 1:
		parts.append("腌菜可领取")
	var tiller: Node = get_tree().get_first_node_in_group(&"farm_tiller")
	var ready: int = 0
	if tiller != null:
		for crop: Crop in tiller._crops.values():
			if crop.is_mature() or not crop.watered:
				continue
			var needed: int = crop.data.regrow_days if crop.regrowing else crop.data.days_at_stage(crop.stage)
			if (crop.regrowing or crop.stage == crop.data.last_stage() - 1) and crop.stage_age + 1 >= needed:
				ready += 1
	if ready > 0:
		parts.append("预计 %d 株成熟" % ready)
	if not depleted.is_empty():
		parts.append("采集物补长 %d 处" % mini(depleted.size(), settings.forage_respawn_per_day))
	parts.append("钓鱼次数恢复")
	return "明日：" + " · ".join(parts)


func _spend(amount: int) -> bool:
	var stamina: Node = get_tree().get_first_node_in_group(&"stamina")
	if stamina != null and not stamina.spend(amount):
		_notify("体力不够 · 回屋睡一觉")
		return false
	return true


func _notify(text: String) -> void:
	message = text
	var toast: Node = get_tree().current_scene.get_node_or_null("UI/Toast")
	if toast != null and not panel.visible:
		toast.show_message(text)
	changed.emit()


func _persist() -> void:
	var save: Node = get_tree().get_first_node_in_group(&"save")
	if save != null:
		save.save_game()


func to_dict() -> Dictionary:
	return {"slots": storage.slots.duplicate(true), "depleted": depleted.duplicate(), "last_day": last_day,
		"processing_ready_day": processing_ready_day, "casts_today": casts_today, "pending_fish": String(pending_fish)}


func from_dict(data: Dictionary) -> void:
	panel.close()
	storage.restore(data.get("slots", []), inventory)
	depleted.clear()
	for value: Variant in data.get("depleted", []):
		var index: int = int(value)
		if index >= 0 and index < settings.forage_items.size() and not depleted.has(index): depleted.append(index)
	last_day = clampi(int(data.get("last_day", today())), 1, today())
	processing_ready_day = maxi(0, int(data.get("processing_ready_day", 0)))
	casts_today = clampi(int(data.get("casts_today", 0)), 0, settings.fishing_limit)
	pending_fish = StringName(data.get("pending_fish", ""))
	if not settings.fish_items.has(pending_fish): pending_fish = &""
	cancel_fishing()
	_refresh_world()
	visuals.refresh()
	changed.emit()
