extends RefCounted
## 技能契约断言：正式玩法基准对齐、凭据矩阵、劳动端口。只读配置，不持有服务或场景生命周期。
## 由 check_skills 注入断言、时钟、场景根与 Service 工厂，保持唯一测试入口。

const FarmTiller := preload("res://scripts/world/farming/farm_tiller.gd")
const LaborPort := preload("res://scripts/progression/labor_port.gd")
const ActivitiesData: Resource = preload("res://data/activities/farm_activities.tres")
const WateringCanRule: Resource = preload("res://data/upgrades/watering_can.tres")
const RegionRules: Resource = preload("res://data/maps/resource_rules.tres")

var _check: Callable
var _clock: Node
var _stage: Node
var _factory: Callable


## 只统计查询次数：验证劳动端口每次投竿只向服务取一次参数，且不缓存旧值。
class CountingService extends RefCounted:
	var queries: int = 0
	var wait_scale: float = 1.0
	func stamina_cost(_action: StringName, base_cost: int) -> int: return base_cost
	func fishing_parameters(wait_min: float, wait_max: float, bite_window: float) -> Dictionary:
		queries += 1
		return {"wait_min": wait_min * wait_scale, "wait_max": wait_max * wait_scale, "bite_window": bite_window}


func configure(check: Callable, clock: Node, stage: Node, service_factory: Callable) -> void:
	_check = check
	_clock = clock
	_stage = stage
	_factory = service_factory


func _report(condition: bool, message: String) -> void:
	_check.call(condition, message)


func _new_service() -> RefCounted:
	return _factory.call()


## 正式玩法当前真实基准：farm_tiller 工具价、铜壶升级、区域采集规则与钓鱼活动配置。
static func baseline_costs() -> Dictionary:
	var farm: Dictionary = FarmTiller.STAMINA_COST
	var rules: Dictionary = RegionRules.get("rules")
	var weeds: Dictionary = rules.get("weeds", {})
	return {
		&"hoe": int(farm.get(&"hoe", 0)),
		&"watering_can": int(farm.get(&"watering_can", 0)),
		&"watering_can_copper": int(WateringCanRule.get("stamina_cost")),
		&"seeds": int(farm.get(&"seeds", 0)),
		&"axe": int(farm.get(&"axe", 0)),
		&"harvest": int(farm.get(&"harvest", 0)),
		&"forage": int(weeds.get("cost", 0)),
		&"fishing": int(ActivitiesData.get("fishing_cost")),
	}


static func fishing_bases() -> Dictionary:
	return {"wait_min": float(ActivitiesData.get("fish_wait_min")),
		"wait_max": float(ActivitiesData.get("fish_wait_max")),
		"bite_window": float(ActivitiesData.get("fish_bite_window"))}


static func action_of(key: StringName) -> StringName:
	return &"watering_can" if key == &"watering_can_copper" else key


## 某等级在真实基准上的可执行结果；规则与 SkillService 相同：max(1, base-累计减免)。
static func capability_profile(definition: SkillDefinition, level: int, bases: Dictionary) -> Dictionary:
	var effects: Dictionary = definition.effects_for(level)
	var reductions: Dictionary = effects.stamina_reductions
	var profile: Dictionary = {}
	for key: StringName in bases:
		profile[key] = maxi(1, int(bases[key]) - int(reductions.get(action_of(key), 0)))
	profile[&"wait_scale"] = snappedf(float(effects.fishing_wait_scale), 0.001)
	profile[&"bite_bonus"] = snappedf(float(effects.fishing_bite_window_bonus), 0.001)
	return profile


static func definition_of(definitions: Array[SkillDefinition], id: StringName) -> SkillDefinition:
	for definition: SkillDefinition in definitions:
		if definition.id == id: return definition
	return null


## 用该技能自己的劳动动作累加到目标等级；唯一 ID 前缀保证不与既有凭据冲突。
static func level_up(service: RefCounted, definition: SkillDefinition, target: int, day: int) -> void:
	if definition == null: return
	var action: StringName = &"harvest" if definition.experience_for.has(&"harvest") else definition.experience_for.keys()[0]
	var limit: int = mini(target, definition.levels.size())
	var guard: int = 0
	while service.level_of(definition.id) < limit and guard < 10001:
		guard += 1
		service.record_labor(action, {"id": "levelup/%s/%d" % [definition.id, guard], "day": day})


## 核对三份 .tres 的五级收益在正式玩法基准上都可执行，且数字与描述一致。
func run_alignment(definitions: Array[SkillDefinition]) -> void:
	var bases: Dictionary = baseline_costs()
	_report(bases == {&"hoe": 4, &"watering_can": 2, &"watering_can_copper": 3, &"seeds": 2, &"axe": 8, &"harvest": 2, &"forage": 2, &"fishing": 4},
		"formal baselines stay hoe4/watering2/copper3/seeds2/axe8/harvest2/forage2/fishing4")
	var farm: Dictionary = FarmTiller.STAMINA_COST
	_report(int(farm.get(&"stone_pickaxe", 0)) == 6, "mining keeps its own 6-cost baseline outside the skill scope")
	var agriculture: SkillDefinition = definition_of(definitions, &"agriculture")
	var foraging: SkillDefinition = definition_of(definitions, &"foraging")
	var fishing: SkillDefinition = definition_of(definitions, &"fishing")
	for definition: SkillDefinition in [agriculture, foraging, fishing]:
		for level in range(1, 6):
			_report(capability_profile(definition, level, bases) != capability_profile(definition, level - 1, bases),
				"%s level %d changes a real gameplay cost or timing, not only its description" % [definition.id, level])
	_report(capability_profile(agriculture, 1, bases)[&"harvest"] == 1, "agriculture 1 lowers the real 2-cost harvest to 1")
	_report(capability_profile(agriculture, 2, bases)[&"seeds"] == 1, "agriculture 2 lowers the real 2-cost planting to 1")
	_report(capability_profile(agriculture, 3, bases)[&"hoe"] == 3, "agriculture 3 lowers the real 4-cost hoe to 3")
	_report(capability_profile(agriculture, 4, bases)[&"watering_can"] == 1 and capability_profile(agriculture, 4, bases)[&"watering_can_copper"] == 2,
		"agriculture 4 lowers normal watering 2->1 and the upgraded copper can 3->2")
	_report(capability_profile(agriculture, 5, bases)[&"hoe"] == 2, "agriculture 5 lowers the hoe to 2")
	for level in range(1, 6):
		_report(capability_profile(foraging, level, bases)[&"axe"] == 8 - level, "foraging level %d lowers the real 8-cost axe to %d" % [level, 8 - level])
	_report(capability_profile(foraging, 2, bases)[&"forage"] == 1, "foraging 2 lowers the real 2-cost wild gathering to 1")
	var rules: Dictionary = RegionRules.get("rules")
	var berry: Dictionary = rules.get("berry_bush", {})
	_report(int(berry.get("cost", 0)) == 1 and capability_profile(foraging, 5, bases)[&"forage"] == 1,
		"one-stamina wild nodes stay at the authored 1 floor instead of going free")
	var casts: Array[int] = []
	for level in range(1, 6):
		casts.append(int(capability_profile(fishing, level, bases)[&"fishing"]))
	_report(casts == [3, 3, 2, 2, 1], "fishing cast steps follow the real 4-cost cast as 3/3/2/2/1")
	var timing: Dictionary = fishing_bases()
	_report(is_equal_approx(float(timing.wait_min), 1.5) and is_equal_approx(float(timing.wait_max), 3.0) and is_equal_approx(float(timing.bite_window), 2.0),
		"authored fishing steps still match the formal 1.5-3.0s wait and 2.0s bite window")
	_report(is_equal_approx(1.5 * float(fishing.effects_for(2).fishing_wait_scale), 1.2) and is_equal_approx(3.0 * float(fishing.effects_for(2).fishing_wait_scale), 2.4),
		"fishing 2 shortens the real 1.5-3.0s wait to 1.2-2.4s with one multiplicative scale")
	_report(is_equal_approx(2.0 + float(fishing.effects_for(4).fishing_bite_window_bonus), 2.5),
		"fishing 4 extends the real 2.0s bite window to 2.5s")


## 凭据矩阵：同一 ID 换动作/换日/重放，满级，busy 重入，以及 restore 后的旧凭据都不能再加经验。
func run_receipt_matrix() -> void:
	var service: RefCounted = _new_service()
	var today: int = int(_clock.day)
	_report(service.record_labor(&"harvest", {"id": "matrix/replay", "day": today}), "matrix: the first receipt of a stable ID counts once")
	var committed: Dictionary = service.encode()
	for action: StringName in [&"harvest", &"chop_tree", &"clear_stump", &"forage", &"catch_fish"]:
		_report(not service.record_labor(action, {"id": "matrix/replay", "day": today}), "matrix: %s cannot re-credit an ID already used by another action" % action)
	_clock.day = today + 1
	_report(not service.record_labor(&"harvest", {"id": "matrix/replay", "day": _clock.day}), "matrix: a new day cannot replay a credited ID")
	_clock.day = today - 1
	_report(not service.record_labor(&"harvest", {"id": "matrix/replay", "day": _clock.day}), "matrix: moving the date backwards cannot replay it either")
	_clock.day = today
	for attempt in 4:
		_report(not service.record_labor(&"harvest", {"id": "matrix/replay", "day": today}), "matrix: replay attempt %d adds no experience" % attempt)
	_report(service.encode() == committed and service.xp_of(&"agriculture") == 8, "matrix: every rejected replay leaves XP, receipts and summary untouched")
	var definition: SkillDefinition = definition_of(service.definitions(), &"agriculture")
	level_up(service, definition, definition.levels.size(), today)
	var capped: Dictionary = service.encode()
	_report(service.xp_of(&"agriculture") == definition.max_xp() and service.level_of(&"agriculture") == definition.levels.size(), "matrix: the skill reaches its authored cap")
	_report(not service.record_labor(&"harvest", {"id": "matrix/capped", "day": today}), "matrix: a maxed skill refuses a fresh receipt")
	_report(service.encode() == capped and not service.encode().receipts.has("matrix/capped"), "matrix: a max-level rejection stores neither XP nor receipt history")
	_report(service.record_labor(&"forage", {"id": "matrix/capped", "day": today}), "matrix: an ID refused only by the cap still credits another skill once")
	var busy_service: RefCounted = _new_service()
	var nested: Array[bool] = []
	var watcher := func() -> void:
		nested.append(busy_service.record_labor(&"forage", {"id": "matrix/busy/nested", "day": today}))
		nested.append(busy_service.restore(busy_service.encode()))
		nested.append(busy_service.acknowledge_summary(today))
		nested.append(busy_service.configure(_clock.today))
	busy_service.changed.connect(watcher)
	_report(busy_service.record_labor(&"harvest", {"id": "matrix/busy/outer", "day": today}), "matrix: the outer receipt commits before its observers run")
	busy_service.changed.disconnect(watcher)
	_report(not nested.has(true) and not busy_service.busy, "matrix: record/restore/acknowledge/configure all refuse observer reentry and no busy flag leaks")
	_report(busy_service.encode().receipts.size() == 1 and busy_service.xp_of(&"foraging") == 0, "matrix: refused reentry leaves no half-committed receipt")
	var restored: RefCounted = _new_service()
	_report(restored.record_labor(&"forage", {"id": "matrix/old", "day": today}), "matrix: a receipt is credited before restore")
	var snapshot: Dictionary = restored.encode()
	_report(restored.restore({"version": 1, "xp": {"agriculture": 8, "foraging": 3, "fishing": 0}, "receipts": {"matrix/old": today}, "pending_upgrades": []}),
		"matrix: a saved section carrying the old receipt restores")
	_report(not restored.record_labor(&"forage", {"id": "matrix/old", "day": today}), "matrix: a receipt loaded from disk still cannot earn XP again")
	var after_restore: Dictionary = restored.encode()
	_report(not restored.record_labor(&"harvest", {"id": "matrix/old", "day": today}) and restored.encode() == after_restore,
		"matrix: the restored receipt blocks every action without mutation")
	_report(restored.record_labor(&"forage", {"id": "matrix/new", "day": today}) and restored.xp_of(&"foraging") == 6, "matrix: a brand-new receipt still counts once after restore")
	_report(restored.restore(snapshot) and restored.record_labor(&"forage", {"id": "matrix/new", "day": today}),
		"matrix: an earlier save section only knows its own receipts, so the slot re-credits that ID exactly once")
	restored.release()
	busy_service.release()
	service.release()
	_clock.day = today


## 劳动端口契约：max(1, base-减免)、免费基准保持0，参数在投竿开始时只取一次。
func run_labor_port() -> void:
	var priced: RefCounted = _new_service()
	var port: Node = LaborPort.new()
	_stage.add_child(port)
	_report(port.is_in_group(&"labor"), "labor port registers in the group the composition root looks up")
	_report(port.today() == 0 and port.stamina_cost(&"hoe", 4) == 4 and port.stamina_cost(&"hoe", 0) == 0,
		"an unconfigured port returns original prices and reports no day")
	_report(port.fishing_parameters(1.5, 3.0, 2.0) == {"wait_min": 1.5, "wait_max": 3.0, "bite_window": 2.0},
		"an unconfigured port forwards fishing bases unchanged")
	_report(not port.record(&"harvest", "port/unconfigured"), "an unconfigured port cannot submit labor")
	var bases: Dictionary = baseline_costs()
	var today: int = int(_clock.day)
	port.configure(priced, _clock.today)
	_report(port.today() == _clock.day and port.today_text() == "第 %d 天" % _clock.day,
		"the port reads the injected calendar instead of caching a day")
	for key: StringName in bases:
		var action: StringName = action_of(key)
		var base: int = int(bases[key])
		_report(port.stamina_cost(action, base) == int(priced.stamina_cost(action, base)) and port.stamina_cost(action, base) == base,
			"level 0 port price for %s equals the service and the formal baseline" % key)
	var opening: Dictionary = port.fishing_parameters(1.5, 3.0, 2.0)
	_report(opening == {"wait_min": 1.5, "wait_max": 3.0, "bite_window": 2.0}, "level 0 keeps the configured fishing timing")
	for attempt in 3:
		_report(port.fishing_parameters(1.5, 3.0, 2.0) == opening, "repeated timing queries stay identical instead of compounding")
	opening["wait_min"] = 99.0
	_report(port.fishing_parameters(1.5, 3.0, 2.0) == {"wait_min": 1.5, "wait_max": 3.0, "bite_window": 2.0},
		"a caller cannot mutate later casts through a returned timing dictionary")
	var fishing: SkillDefinition = definition_of(priced.definitions(), &"fishing")
	level_up(priced, fishing, 2, today)
	var sampled: Dictionary = port.fishing_parameters(1.5, 3.0, 2.0)
	_report(is_equal_approx(float(sampled.wait_min), 1.2) and is_equal_approx(float(sampled.wait_max), 2.4) and is_equal_approx(float(sampled.bite_window), 2.0),
		"fishing level 2 shortens the sampled cast to 1.2-2.4s without touching the bite window")
	level_up(priced, fishing, 5, today)
	_report(is_equal_approx(float(sampled.wait_min), 1.2) and is_equal_approx(float(sampled.wait_max), 2.4) and is_equal_approx(float(sampled.bite_window), 2.0),
		"a cast that sampled before the level-up keeps its frozen parameters")
	var maxed: Dictionary = port.fishing_parameters(1.5, 3.0, 2.0)
	_report(is_equal_approx(float(maxed.wait_min), 1.2) and is_equal_approx(float(maxed.wait_max), 2.4) and is_equal_approx(float(maxed.bite_window), 2.5),
		"the next cast at level 5 samples 1.2-2.4s wait and the 2.5s window")
	for definition: SkillDefinition in priced.definitions():
		level_up(priced, definition, definition.levels.size(), today)
	var expected: Dictionary = {&"hoe": 2, &"watering_can": 1, &"watering_can_copper": 2, &"seeds": 1, &"axe": 3, &"harvest": 1, &"forage": 1, &"fishing": 1}
	for key: StringName in expected:
		var action: StringName = action_of(key)
		var base: int = int(bases[key])
		_report(port.stamina_cost(action, base) == int(expected[key]) and int(priced.stamina_cost(action, base)) == int(expected[key]),
			"maxed port %s equals max(1, base - reduction) = %d" % [key, int(expected[key])])
	for base in range(1, 13):
		_report(port.stamina_cost(&"axe", base) == maxi(1, base - 5), "the port never discounts the axe below one stamina at base %d" % base)
	_report(port.stamina_cost(&"stone_pickaxe", 6) == 6 and port.stamina_cost(&"mine", 6) == 6,
		"mining and unowned actions keep their full baseline cost")
	_report(port.stamina_cost(&"axe", 0) == 0 and int(priced.stamina_cost(&"axe", -3)) == 0,
		"a free baseline stays zero and the service never charges a negative one")
	_report(port.stamina_cost(&"axe", -3) <= 0, "a negative baseline is never turned into a positive charge by the port")
	var counting := CountingService.new()
	port.configure(counting, _clock.today)
	_report(port.fishing_parameters(2.0, 4.0, 1.0) == {"wait_min": 2.0, "wait_max": 4.0, "bite_window": 1.0} and counting.queries == 1,
		"one cast start takes exactly one parameter query from the service")
	port.fishing_parameters(2.0, 4.0, 1.0)
	_report(counting.queries == 2, "the port caches nothing, so a later cast samples once instead of reusing stale bounds")
	var frozen: Dictionary = port.fishing_parameters(2.0, 4.0, 1.0)
	counting.wait_scale = 0.5
	_report(is_equal_approx(float(frozen.wait_min), 2.0) and is_equal_approx(float(port.fishing_parameters(2.0, 4.0, 1.0).wait_min), 1.0),
		"parameters sampled at cast start stay fixed while a later cast sees the new level")
	var committing: RefCounted = _new_service()
	port.configure(committing, _clock.today)
	_report(port.record(&"harvest", "port/labor/one") and committing.xp_of(&"agriculture") == 8,
		"the port forwards a committed labor receipt with the configured points")
	_report(not port.record(&"harvest", "port/labor/one"), "the port keeps the service's global receipt deduplication")
	_report(not port.record(&"harvest", "   ") and not port.record(&"mine", "port/labor/mine") and committing.xp_of(&"agriculture") == 8,
		"blank IDs and non-labor actions are refused before they reach the model")
	_clock.day = today + 1
	_report(port.record(&"forage", "port/labor/two") and int(committing.encode().receipts["port/labor/two"]) == today + 1,
		"the port stamps the current day at submission time")
	_report(not port.record(&"forage", "port/labor/one"), "a receipt from another day stays deduplicated through the port")
	port.clear()
	_report(port.today() == 0 and port.stamina_cost(&"axe", 8) == 8 and not port.record(&"forage", "port/after_clear"),
		"clear restores passthrough pricing and refuses further labor")
	_report(committing.xp_of(&"foraging") == 3 and committing.xp_of(&"agriculture") == 8, "clearing the port never erases committed skill facts")
	_clock.day = today
	port.queue_free()
	priced.release()
	committing.release()
