extends SceneTree
## B5-07 鱼种条件与渔具成长：条件过滤、确定性权重抽取、配置校验与纯查询边界。

const Service := preload("res://scripts/activities/fishing_rule_service.gd")
const Species := preload("res://scripts/data/fish_species_data.gd")
const Gear := preload("res://scripts/data/fishing_gear_data.gd")
const SPECIES_DIR: String = "res://data/fish"
const GEAR_DIR: String = "res://data/gear"

var _checks: int = 0
var _failures: int = 0
var _service: RefCounted
var _authored_species: Array[FishSpeciesData] = []
var _authored_gear: Array[FishingGearData] = []
var _probe_species: Array[FishSpeciesData] = []
var _probe_gear: Array[FishingGearData] = []


func _init() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("[fishing_rules] FAIL: " + message)


func _run() -> void:
	_service = Service.new()
	_check(_load_authored(), "authored fish and gear resources load from data/fish and data/gear")
	_probe_species = _build_species()
	_probe_gear = _build_gear()
	var catalog: Array[FishSpeciesData] = []
	catalog.assign(_authored_species)
	catalog.append_array(_probe_species)
	var gears: Array[FishingGearData] = []
	gears.assign(_authored_gear)
	gears.append_array(_probe_gear)
	_check(_service.configure(catalog, gears), "service configures authored plus probe data")
	_check_authored_contract()
	_check_filters()
	_check_context_validation()
	_check_gear_fallbacks()
	_check_determinism()
	_check_weights()
	_check_configuration(catalog, gears)
	_check_resource_isolation()
	_check_pure_query()
	_check_release()
	print("[fishing_rules] %d checks, %d failures; reached end; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _load_authored() -> bool:
	for folder: String in [SPECIES_DIR, GEAR_DIR]:
		for file: String in ResourceLoader.list_directory(folder):
			if not file.ends_with(".tres"): continue
			if folder == SPECIES_DIR:
				var fish := load(SPECIES_DIR.path_join(file)) as FishSpeciesData
				if fish != null: _authored_species.append(fish)
			else:
				var item := load(GEAR_DIR.path_join(file)) as FishingGearData
				if item != null: _authored_gear.append(item)
	return _authored_species.size() == 2 and _authored_gear.size() == 1


func _probe(id: StringName) -> FishSpeciesData:
	var data := Species.new()
	data.id = id
	data.display_name = String(id)
	data.regions.assign([&"home"])
	data.seasons.assign([&"spring"])
	data.weathers.assign([&"sunny"])
	data.min_rod_level = 1
	data.weight = 1.0
	data.min_minute = 600
	data.max_minute = 720
	return data


func _build_species() -> Array[FishSpeciesData]:
	var golden := _probe(&"golden_carp")
	golden.min_rod_level = 2
	var eel := _probe(&"night_eel")
	eel.regions.assign([&"wetland"])
	eel.seasons.assign([&"summer"])
	eel.weathers.assign([&"rainy"])
	eel.min_minute = 1200
	eel.max_minute = 1500
	var result: Array[FishSpeciesData] = [golden, eel]
	return result


func _build_gear() -> Array[FishingGearData]:
	var copper := Gear.new()
	copper.item_id = &"copper_rod"
	copper.level = 2
	copper.cast_stamina_scale = 0.8
	copper.allowed_species_bonus.assign({&"golden_carp": 1.0})
	var iron := Gear.new()
	iron.item_id = &"iron_rod"
	iron.level = 2
	iron.cast_stamina_scale = 1.0
	var result: Array[FishingGearData] = [copper, iron]
	return result


func _ctx(region: StringName = &"home", season: StringName = &"spring", weather: StringName = &"sunny", minute: int = 600, rod: StringName = &"bamboo_rod") -> Dictionary:
	return {&"region": region, &"season": season, &"weather": weather, &"minute": minute, &"rod_item": rod}


func _authored(id: StringName) -> FishSpeciesData:
	for data: FishSpeciesData in _authored_species:
		if data.id == id: return data
	return null


func _check_authored_contract() -> void:
	var crucian: FishSpeciesData = _authored(&"crucian_carp")
	var common: FishSpeciesData = _authored(&"common_carp")
	_check(crucian != null and crucian.is_valid() and crucian.display_name == "鲫鱼", "crucian carp keeps its existing item id and name")
	_check(common != null and common.is_valid() and common.display_name == "鲤鱼", "common carp keeps its existing item id and name")
	if crucian == null or common == null: return
	_check(crucian.regions.size() == 2 and crucian.regions.has(&"home") and crucian.regions.has(&"wetland"), "crucian carp is limited to pond regions")
	_check(crucian.seasons.size() == 3 and not crucian.seasons.has(&"winter"), "crucian carp skips winter")
	_check(crucian.weathers.size() == 3 and crucian.weathers.has(&"rainy"), "crucian carp accepts every authored weather")
	_check(crucian.min_rod_level == 1 and is_equal_approx(crucian.weight, 3.0), "crucian carp needs the bamboo rod and keeps weight three")
	_check(crucian.min_minute == 360 and crucian.max_minute == 1080, "crucian carp keeps its daytime window")
	_check(common.seasons.size() == 4 and common.seasons.has(&"winter"), "common carp is available in all four seasons")
	_check(common.min_rod_level == 1 and is_equal_approx(common.weight, 2.0), "common carp needs the bamboo rod and keeps weight two")
	_check(common.min_minute == 300 and common.max_minute == 1260, "common carp keeps its longer window")
	var rod: FishingGearData = _authored_gear[0]
	_check(rod.item_id == &"bamboo_rod" and rod.level == 1, "bamboo rod is the level one gear entry for its existing item")
	_check(is_equal_approx(rod.cast_stamina_scale, 1.0) and rod.allowed_species_bonus.is_empty(), "the bamboo rod has no stamina discount and an empty bonus map")
	_check(_service.gear_level(&"bamboo_rod") == 1 and is_equal_approx(_service.cast_stamina_scale(&"bamboo_rod"), 1.0), "the configured service exposes the authored gear values")


func _check_filters() -> void:
	var pond: Array[StringName] = _service.candidates(_ctx())
	_check(pond.size() == 2 and pond.has(&"crucian_carp") and pond.has(&"common_carp"), "pond in spring at 10:00 offers both authored fish")
	_check(_service.candidates(_ctx(&"quarry")).is_empty(), "a region outside every fish list yields no candidates")
	var winter: Array[StringName] = _service.candidates(_ctx(&"home", &"winter"))
	_check(winter.size() == 1 and winter.has(&"common_carp"), "the season filter drops the fish that avoids winter")
	_check(not _service.candidates(_ctx(&"home", &"spring", &"rainy", 650)).has(&"golden_carp"), "the weather filter drops the sunshine-only probe")
	var early: Array[StringName] = _service.candidates(_ctx(&"home", &"spring", &"sunny", 200))
	_check(early.is_empty(), "before the earliest window nothing is active")
	var late: Array[StringName] = _service.candidates(_ctx(&"home", &"spring", &"sunny", 1100))
	_check(late.size() == 1 and late.has(&"common_carp"), "the time filter drops the fish whose window already closed")
	_check(_service.candidates(_ctx(&"wetland", &"summer", &"rainy", 1250)).has(&"night_eel"), "the night probe appears in its own window")
	_check(not _service.candidates(_ctx(&"wetland", &"summer", &"rainy", 1150)).has(&"night_eel"), "the night probe is excluded before its window")
	_check(not _service.candidates(_ctx(&"home", &"spring", &"sunny", 650)).has(&"golden_carp"), "rod level one hides the level two fish")
	var upgraded: Array[StringName] = _service.candidates(_ctx(&"home", &"spring", &"sunny", 650, &"iron_rod"))
	_check(upgraded.size() == 3 and upgraded.has(&"golden_carp"), "a level two rod admits the rare fish")
	_check(_service.candidates(_ctx(&"home", &"spring", &"sunny", 1560)).is_empty(), "the last clock minute is valid but has no active fish")


func _check_context_validation() -> void:
	for key: StringName in [&"region", &"season", &"weather", &"minute", &"rod_item"]:
		var broken: Dictionary = _ctx()
		broken.erase(key)
		_check(_service.candidates(broken).is_empty(), "a missing context key yields no candidates: " + String(key))
		var picked: Dictionary = _service.pick(broken, 1)
		_check(not picked.ok and not String(picked.reason).is_empty(), "a missing context key refuses the pick: " + String(key))
	_check(_service.candidates({}).is_empty() and not _service.pick({}, 1).ok, "an empty context is refused")
	var mutations: Array[Dictionary] = [
		{&"region": 5}, {&"season": true}, {&"weather": []}, {&"rod_item": 1.5},
		{&"minute": "600"}, {&"minute": true}, {&"minute": 600.5}, {&"minute": -1}, {&"minute": 1561},
	]
	for mutation: Dictionary in mutations:
		var broken: Dictionary = _ctx()
		for key: Variant in mutation: broken[key] = mutation[key]
		_check(_service.candidates(broken).is_empty(), "a wrong context value yields no candidates: " + str(mutation))
	var extended: Dictionary = _ctx()
	extended[&"day"] = 12
	_check(_service.candidates(extended) == _service.candidates(_ctx()), "extra context keys are ignored")
	_check(_service.candidates(_ctx(&"moon")).is_empty(), "an unknown region value yields no candidates")
	_check(_service.candidates(_ctx(&"home", &"monsoon")).is_empty(), "an unknown season value yields no candidates")
	_check(_service.candidates(_ctx(&"home", &"spring", &"snow")).is_empty(), "an unknown weather value yields no candidates")
	var empty_pick: Dictionary = _service.pick(_ctx(&"home", &"spring", &"sunny", 1560), 3)
	_check(not empty_pick.ok and String(empty_pick.reason).contains("没有"), "a valid but empty context explains the refusal")


func _check_gear_fallbacks() -> void:
	_check(_service.gear_level(&"missing_rod") == 0, "an unknown rod reports level zero")
	_check(is_equal_approx(_service.cast_stamina_scale(&"missing_rod"), 1.0), "an unknown rod keeps the base stamina scale")
	_check(_service.gear_level(&"copper_rod") == 2, "a registered rod exposes its level")
	_check(is_equal_approx(_service.cast_stamina_scale(&"copper_rod"), 0.8), "a registered rod exposes its stamina scale")
	_check(_service.candidates(_ctx(&"home", &"spring", &"sunny", 650, &"missing_rod")).is_empty(), "an unknown rod cannot reach level one fish")


func _check_determinism() -> void:
	var first: Dictionary = _service.pick(_ctx(), 20261110)
	_check(first.ok and (first.fish == &"crucian_carp" or first.fish == &"common_carp"), "pick returns one of the eligible fish")
	var stable: bool = true
	for attempt: int in 20:
		stable = stable and _service.pick(_ctx(), 20261110).fish == first.fish
	_check(stable, "the same context and seed always return the same fish")
	var varied: bool = false
	for value: int in 200:
		varied = varied or _service.pick(_ctx(), value).fish != first.fish
	_check(varied, "different seeds reach more than one fish")


func _check_weights() -> void:
	var counts: Dictionary = {&"crucian_carp": 0, &"common_carp": 0}
	for seed: int in 4000:
		var result: Dictionary = _service.pick(_ctx(), seed)
		counts[result.fish] = int(counts.get(result.fish, 0)) + 1
	var share: float = float(counts[&"crucian_carp"]) / 4000.0
	_check(share > 0.5 and share < 0.7, "weights three to two produce a near sixty percent share")
	var plain: float = _share(&"iron_rod", &"golden_carp")
	var boosted: float = _share(&"copper_rod", &"golden_carp")
	_check(plain > 0.1 and boosted > plain, "the gear bonus raises the boosted species share")
	_check(_service.candidates(_ctx(&"home", &"spring", &"sunny", 650, &"copper_rod")).size() == 3, "weights never change the candidate set")


func _share(rod: StringName, fish: StringName) -> float:
	var hits: int = 0
	for seed: int in 2000:
		if _service.pick(_ctx(&"home", &"spring", &"sunny", 650, rod), seed).fish == fish: hits += 1
	return float(hits) / 2000.0


func _check_configuration(catalog: Array[FishSpeciesData], gears: Array[FishingGearData]) -> void:
	var baseline: Array[StringName] = _service.candidates(_ctx())
	var baseline_pick: StringName = StringName(_service.pick(_ctx(), 4242).fish)
	var duplicate: Array[FishSpeciesData] = []
	duplicate.assign(catalog)
	duplicate.append(catalog[0])
	_check(not _service.configure(duplicate, gears), "a duplicate species id is refused")
	var repeated_gear: Array[FishingGearData] = []
	repeated_gear.assign(gears)
	repeated_gear.append(gears[0])
	_check(not _service.configure(catalog, repeated_gear), "a duplicate gear item id is refused")
	var probe: FishSpeciesData = _probe(&"config_probe")
	var single: Array[FishSpeciesData] = [probe]
	var no_gear: Array[FishingGearData] = []
	probe.weight = 0.0
	_check(not _service.configure(single, no_gear), "zero weight is refused")
	probe.weight = NAN
	_check(not _service.configure(single, no_gear), "a non-finite weight is refused")
	probe.weight = 2.0
	probe.min_minute = 900
	probe.max_minute = 600
	_check(not _service.configure(single, no_gear), "an inverted time window is refused")
	probe.min_minute = 0
	probe.max_minute = 1561
	_check(not _service.configure(single, no_gear), "a window beyond the clock is refused")
	var bad_rod: FishingGearData = Gear.new()
	bad_rod.item_id = &"bad_rod"
	var single_gear: Array[FishingGearData] = [bad_rod]
	bad_rod.level = 0
	_check(not _service.configure(catalog, single_gear), "a zero gear level is refused")
	bad_rod.level = 1
	bad_rod.cast_stamina_scale = INF
	_check(not _service.configure(catalog, single_gear), "a non-finite stamina scale is refused")
	bad_rod.cast_stamina_scale = 1.0
	bad_rod.allowed_species_bonus.assign({&"crucian_carp": -0.5})
	_check(not _service.configure(catalog, single_gear), "a negative species bonus is refused")
	_check(_service.candidates(_ctx()) == baseline and _service.pick(_ctx(), 4242).fish == baseline_pick, "every refused configuration keeps the previous service")


func _check_resource_isolation() -> void:
	var weight: float = _probe_species[0].weight
	var regions: int = _probe_species[0].regions.size()
	var scale: float = _probe_gear[0].cast_stamina_scale
	var bonus: int = _probe_gear[0].allowed_species_bonus.size()
	_service.candidates(_ctx(&"home", &"spring", &"sunny", 650, &"copper_rod"))
	_service.pick(_ctx(), 77)
	_check(is_equal_approx(_probe_species[0].weight, weight) and _probe_species[0].regions.size() == regions, "queries never rewrite the passed species resources")
	_check(is_equal_approx(_probe_gear[0].cast_stamina_scale, scale) and _probe_gear[0].allowed_species_bonus.size() == bonus, "queries never rewrite the passed gear resources")
	_probe_species[0].weight = 99.0
	_check(_service.pick(_ctx(&"home", &"spring", &"sunny", 650, &"copper_rod"), 1).ok, "mutating the source resource leaves the configured snapshot intact")
	_probe_species[0].weight = weight
	var snapshot: Array[StringName] = _service.candidates(_ctx())
	snapshot.clear()
	_check(_service.candidates(_ctx()).size() == 2, "the returned candidate array is a fresh copy")


func _check_pure_query() -> void:
	_check(_service.get_class() == "RefCounted" and _service.get_script() != null, "the rule service is a plain RefCounted script without a tree")
	var declared: GDScript = _service.get_script() as GDScript
	_check(declared != null and declared.get_script_signal_list().is_empty(), "the rule service declares no signals")


func _check_release() -> void:
	_service.release()
	_check(_service.candidates(_ctx()).is_empty() and not _service.pick(_ctx(), 1).ok, "the released service returns nothing")
	_check(_service.gear_level(&"bamboo_rod") == 0 and is_equal_approx(_service.cast_stamina_scale(&"bamboo_rod"), 1.0), "the released service forgets gear but keeps the safe fallback")
	_check(not _service.configure(_authored_species, _authored_gear), "the released service refuses reconfiguration")
