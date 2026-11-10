extends SceneTree
## B6-01 周限礼、偏好记录与对话条件求值纯状态检查。
## 只加载新增模块与四位 NPC 的偏好资源，不打开主场景、不读写真实玩家存档、不接线。

const Service := preload("res://scripts/progression/gift_service.gd")
const Conditions := preload("res://scripts/progression/dialogue_conditions.gd")
const PreferenceScript := preload("res://scripts/data/gift_preference.gd")
const Shopkeeper: Resource = preload("res://data/gifts/shopkeeper.tres")
const Carpenter: Resource = preload("res://data/gifts/carpenter.tres")
const Fisherman: Resource = preload("res://data/gifts/fisherman.tres")
const Gardener: Resource = preload("res://data/gifts/gardener.tres")

var _checks: int = 0
var _failures: int = 0
var _service: RefCounted
var _conditions: RefCounted
var _day: int = 1
var _grant_mode: StringName = &"normal"
var _grant_calls: Array[Dictionary] = []
var _grant_port: Callable = Callable()
var _day_port: Callable = Callable()


func _init() -> void:
	_grant_port = Callable(self, "_fake_grant")
	_day_port = Callable(self, "_fake_day")
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("[gifts] FAIL: " + message)


func _fake_day() -> int:
	return _day


func _fake_grant(npc_id: StringName, points: int) -> Variant:
	_grant_calls.append({"npc": npc_id, "points": points})
	match _grant_mode:
		&"zero": return 0
		&"null": return null
		&"bad_type": return "oops"
		&"negative": return -5
		_: return points


func _prefs() -> Array[GiftPreference]:
	var result: Array[GiftPreference] = []
	for pref: Resource in [Shopkeeper, Carpenter, Fisherman, Gardener]:
		result.append(pref as GiftPreference)
	return result


func _pref(id: StringName, liked: Array, neutral: Array, disliked: Array, limit: int) -> GiftPreference:
	var pref := GiftPreference.new()
	pref.npc_id = id
	pref.liked.assign(liked)
	pref.neutral.assign(neutral)
	pref.disliked.assign(disliked)
	pref.weekly_limit = limit
	return pref


func _configure(prefs: Array[GiftPreference]) -> bool:
	_day = 1
	_grant_calls.clear()
	_grant_mode = &"normal"
	return _service.configure(prefs, _grant_port, _day_port)


func _grants() -> int:
	return _grant_calls.size()


func _run() -> void:
	if not preload("res://tools/lib/check_safety.gd").require_isolated(self): return
	_service = Service.new()
	_conditions = Conditions.new()
	_check_contract_and_unconfigured()
	_check_configure_validation()
	_check_shipped_preferences()
	_check_weekly_limit()
	_check_week_rollover()
	_check_npc_independence()
	_check_preferences()
	_check_grant_failures()
	_check_persistence()
	_check_conditions()
	_check_condition_rejections()
	_check_purity_and_release()
	_check(true, "all gift, preference, persistence and condition groups reached their final assertions")
	_service.release()
	_service = null
	_conditions = null
	print("[gifts] reached end; %d checks, %d failures; %s" % [_checks, _failures, "PASS" if _failures == 0 else "FAIL"])
	preload("res://tools/lib/check_lifecycle.gd").finish(self, 0 if _failures == 0 else 1)


func _check_contract_and_unconfigured() -> void:
	_check(_service.get_script().get_instance_base_type() == "RefCounted", "gift service is a plain RefCounted and needs no scene node")
	_check(_service.get_script().get_script_signal_list().is_empty(), "gift service declares no signals: it never pushes gameplay events")
	_check(_conditions.get_script().get_instance_base_type() == "RefCounted", "dialogue conditions is a plain RefCounted")
	_check(_conditions.get_script().get_script_signal_list().is_empty(), "dialogue conditions declares no signals")
	_check(not _service.is_configured() and _service.week_key() == 0, "an unconfigured service reports week 0")
	_check(not bool(_service.can_gift(&"shopkeeper", &"egg").ok), "an unconfigured service refuses can_gift")
	_check(not bool(_service.gift(&"shopkeeper", &"egg").ok) and _grants() == 0, "an unconfigured service never grants points")
	_check(String(_service.preference_of(&"shopkeeper", &"egg").text).contains("没有"), "an unconfigured service explains its missing preference")
	_check(_service.encode() == {"schema": 1, "weeks": {}}, "encode always reports schema 1 with the weekly table")
	_check(not _service.restore({"schema": 1, "weeks": {}}), "restore before configure is refused")
	var empty: Array[GiftPreference] = []
	_check(not _service.configure(empty, _grant_port, _day_port), "no preferences is refused")


func _check_configure_validation() -> void:
	var good: Array[GiftPreference] = _prefs()
	_check(not _service.configure(good, Callable(), _day_port), "an invalid grant Callable is refused")
	_check(not _service.configure(good, _grant_port, Callable()), "an invalid current_day Callable is refused")
	_check(not _service.is_configured(), "refused configuration leaves the service unconfigured")
	var duplicate: Array[GiftPreference] = [good[0], good[0]]
	_check(not _service.configure(duplicate, _grant_port, _day_port), "duplicate npc_id is refused")
	var bad: Array[GiftPreference] = [_pref(&"ghost", [&"wood"], [&"wood"], [], 2)]
	_check(not _service.configure(bad, _grant_port, _day_port), "an item listed in two preference groups is refused")
	bad = [_pref(&"ghost", [], [], [], 0)]
	_check(not _service.configure(bad, _grant_port, _day_port), "a zero weekly limit is refused")
	bad = [_pref(&"", [&"wood"], [], [], 2)]
	_check(not _service.configure(bad, _grant_port, _day_port), "an empty npc_id is refused")
	_check(not _service.is_configured(), "all refused configurations keep the service unconfigured")
	_check(_pref(&"probe", [], [], [], 2).is_valid(), "the fixture preference passes the same validation as the service")
	_check(_configure(good), "four shipped preferences configure")
	_check(_service.is_configured(), "a valid configuration is retained")


func _check_shipped_preferences() -> void:
	var ids: Array[StringName] = [&"shopkeeper", &"carpenter", &"fisherman", &"gardener"]
	var all: Array[GiftPreference] = _prefs()
	_check(all.size() == 4 and Shopkeeper.get_script() == PreferenceScript, "four NPC preference resources load as GiftPreference")
	for i: int in 4:
		var pref: GiftPreference = all[i]
		_check(pref.is_valid() and pref.npc_id == ids[i] and pref.weekly_limit == 2, "shipped %s preference is valid with a weekly limit" % ids[i])
	_check(all[3].liked.has(&"carrot") and all[3].liked.has(&"wild_flower"), "gardener keeps the liked items already used by the scene")
	_check(all[0].disliked.has(&"coal") and all[2].liked.has(&"crucian_carp"), "shopkeeper and fisherman carry their own distinct preferences")


func _check_weekly_limit() -> void:
	_configure(_prefs())
	var first: Dictionary = _service.gift(&"shopkeeper", &"egg")
	_check(bool(first.ok) and int(first.points) == 20 and bool(first.liked), "a liked gift grants base plus bonus")
	var second: Dictionary = _service.gift(&"shopkeeper", &"wood")
	_check(bool(second.ok) and int(second.points) == 10 and not bool(second.liked), "a neutral gift grants the base points")
	_check(_grants() == 2 and int(_grant_calls[0].points) == 20 and int(_grant_calls[1].points) == 10, "grant receives only the requested points, never a copied friendship total")
	_check(_service.encode() == {"schema": 1, "weeks": {"shopkeeper": {"week": 0, "count": 2}}}, "encode stores week and count per NPC")
	var preview: Dictionary = _service.can_gift(&"shopkeeper", &"egg")
	_check(not bool(preview.ok) and not String(preview.reason).is_empty(), "the N+1 gift is refused by can_gift with a reason")
	var refused: Dictionary = _service.gift(&"shopkeeper", &"egg")
	_check(not bool(refused.ok) and int(refused.points) == 0 and not String(_service.last_rejection).is_empty(), "the N+1 gift is refused with zero points and an explanation")
	_check(_grants() == 2 and not _service.busy, "an over-limit gift never calls grant and never leaks busy")
	_check(_service.encode() == {"schema": 1, "weeks": {"shopkeeper": {"week": 0, "count": 2}}}, "an over-limit gift leaves the weekly count unchanged")


func _check_week_rollover() -> void:
	_configure(_prefs())
	_check(_service.week_key() == 0, "day 1 starts at week 0")
	for day: int in [2, 5, 7]:
		_day = day
		_check(_service.week_key() == 0, "day %d stays in week 0 so cross-day gifts never reset" % day)
	_day = 1
	_service.gift(&"shopkeeper", &"egg")
	_service.gift(&"shopkeeper", &"egg")
	_check(not bool(_service.can_gift(&"shopkeeper", &"egg").ok), "week 0 is exhausted before the rollover")
	_day = 8
	_check(_service.week_key() == 1, "day 8 advances to week 1")
	_check(bool(_service.can_gift(&"shopkeeper", &"egg").ok), "a new week allows gifting again")
	var granted: Dictionary = _service.gift(&"shopkeeper", &"egg")
	_check(bool(granted.ok) and _service.encode() == {"schema": 1, "weeks": {"shopkeeper": {"week": 1, "count": 1}}}, "the new week starts its count from one")
	_day = 15
	_check(_service.week_key() == 2 and bool(_service.can_gift(&"shopkeeper", &"egg").ok), "week 2 also starts fresh")
	var old_week: Dictionary = {"schema": 1, "weeks": {"shopkeeper": {"week": 0, "count": 2}}}
	_check(_service.restore(old_week) and bool(_service.can_gift(&"shopkeeper", &"egg").ok), "restoring an exhausted old-week snapshot does not block the current week")


func _check_npc_independence() -> void:
	_configure(_prefs())
	_service.gift(&"shopkeeper", &"egg")
	_service.gift(&"shopkeeper", &"egg")
	_check(not bool(_service.can_gift(&"shopkeeper", &"egg").ok), "shopkeeper is at its weekly limit")
	_check(bool(_service.can_gift(&"carpenter", &"wood").ok) and bool(_service.can_gift(&"gardener", &"carrot").ok), "other NPCs keep their own allowance")
	_check(bool(_service.gift(&"carpenter", &"wood").ok), "carpenter can still receive a gift")
	var weeks: Dictionary = _service.encode().weeks
	_check(int(weeks.shopkeeper.count) == 2 and int(weeks.carpenter.count) == 1 and not weeks.has("gardener"), "weekly counts are stored independently per NPC")


func _check_preferences() -> void:
	_configure(_prefs())
	var liked: Dictionary = _service.preference_of(&"shopkeeper", &"egg")
	var neutral: Dictionary = _service.preference_of(&"shopkeeper", &"wood")
	var disliked: Dictionary = _service.preference_of(&"shopkeeper", &"coal")
	var unknown: Dictionary = _service.preference_of(&"shopkeeper", &"blueberry")
	_check(bool(liked.liked) and String(liked.text).contains("喜欢"), "liked item reports liked with its own text")
	_check(not bool(neutral.liked) and String(neutral.text).contains("收下"), "neutral item has its own text")
	_check(not bool(disliked.liked) and String(disliked.text).contains("不太喜欢"), "disliked item has its own text")
	_check(not bool(unknown.liked) and String(unknown.text).contains("第一次"), "unknown item has its own text")
	_check(String(liked.text) != String(neutral.text) and String(neutral.text) != String(disliked.text) and String(disliked.text) != String(unknown.text), "the four preference texts are distinct")
	var missing: Dictionary = _service.preference_of(&"ghost", &"egg")
	_check(not bool(missing.liked) and String(missing.text).contains("没有"), "an unconfigured NPC has no preference record")
	_check(not bool(_service.can_gift(&"ghost", &"egg").ok) and not bool(_service.gift(&"ghost", &"egg").ok) and _grants() == 0, "an unconfigured NPC is refused without granting")
	_check(not bool(_service.can_gift(&"shopkeeper", &"").ok), "an empty item id is refused")
	var before: int = _grants()
	for i: int in 3:
		_service.preference_of(&"shopkeeper", &"egg")
		_service.can_gift(&"shopkeeper", &"egg")
		_service.encode()
		_service.week_key()
	_check(_grants() == before, "repeated read-only queries never grant points")


func _check_grant_failures() -> void:
	for mode: StringName in [&"zero", &"null", &"bad_type", &"negative"]:
		_configure(_prefs())
		_grant_mode = mode
		var result: Dictionary = _service.gift(&"shopkeeper", &"egg")
		_check(bool(result.ok) and int(result.points) == 0, "grant %s still delivers one gift with zero granted points" % mode)
		_check(_grants() == 1 and _service.encode() == {"schema": 1, "weeks": {"shopkeeper": {"week": 0, "count": 1}}} and not _service.busy, "grant %s keeps the weekly count consistent and clears busy" % mode)
		_grant_mode = &"normal"
		var second: Dictionary = _service.gift(&"shopkeeper", &"egg")
		_check(bool(second.ok) and int(second.points) == 20 and _grants() == 2, "a later normal grant is never compensated for the earlier failure")
		_check(not bool(_service.gift(&"shopkeeper", &"egg").ok) and _grants() == 2, "a failed grant never reopens the weekly allowance")


func _check_persistence() -> void:
	_configure(_prefs())
	_service.gift(&"shopkeeper", &"egg")
	_service.gift(&"fisherman", &"crucian_carp")
	var snapshot: Dictionary = _service.encode()
	_check(int(snapshot.schema) == 1 and snapshot.weeks.size() == 2, "encode reports schema 1 and one row per gifted NPC")
	var before: int = _grants()
	for attempt: int in 3:
		_check(_service.restore(snapshot), "restore round %d accepts the service's own snapshot" % (attempt + 1))
		_check(_service.encode() == snapshot and _grants() == before, "restore round %d is idempotent and never grants" % (attempt + 1))
	_check(_service.restore({}) and _service.encode() == {"schema": 1, "weeks": {}}, "an old save without this section clears weekly counts")
	_check(bool(_service.can_gift(&"shopkeeper", &"egg").ok), "an old save allows gifting again from a clean week")
	_service.gift(&"shopkeeper", &"egg")
	var kept: Dictionary = _service.encode()
	for bad: Dictionary in [
		{"schema": 2, "weeks": {}},
		{"schema": "1", "weeks": {}},
		{"weeks": {}},
		{"schema": 1},
		{"schema": 1, "weeks": []},
		{"schema": 1, "weeks": {}, "extra": 1},
		{"schema": 1, "weeks": {"ghost": {"week": 0, "count": 1}}},
		{"schema": 1, "weeks": {"shopkeeper": {"week": 0, "count": 1, "extra": 1}}},
		{"schema": 1, "weeks": {"shopkeeper": {"week": 0, "count": 1.5}}},
		{"schema": 1, "weeks": {"shopkeeper": {"week": 0, "count": true}}},
		{"schema": 1, "weeks": {"shopkeeper": {"week": 0, "count": -1}}},
		{"schema": 1, "weeks": {"shopkeeper": {"week": 0, "count": 99}}},
		{"schema": 1, "weeks": {"shopkeeper": "bad"}},
	]:
		_check(not _service.restore(bad) and _service.encode() == kept and not String(_service.last_rejection).is_empty(), "refused snapshot keeps counts and explains itself: %s" % str(bad))
	_check(_service.restore({"schema": 1, "weeks": {"shopkeeper": {"week": 0, "count": 2}}}) and not bool(_service.can_gift(&"shopkeeper", &"egg").ok), "a restored full week blocks further gifts")


func _check_conditions() -> void:
	_check(_conditions.conditions_met({}, {}), "empty conditions are always met")
	var facts: Dictionary = {"friendship": 80, "day": 10, "weather": &"sunny", "quests": {"ch1_gate": "completed", "ch2_road": "active"}, "flags": [&"read_letter", &"met_carpenter"]}
	_check(_conditions.conditions_met({"friendship_min": 80}, facts) and not _conditions.conditions_met({"friendship_min": 81}, facts), "friendship_min compares against the current friendship value")
	_check(_conditions.conditions_met({"day_min": 10, "day_max": 10}, facts), "day_min and day_max are inclusive")
	_check(not _conditions.conditions_met({"day_min": 11}, facts) and not _conditions.conditions_met({"day_max": 9}, facts), "day bounds reject out-of-range days")
	_check(_conditions.conditions_met({"weather": &"sunny"}, facts) and _conditions.conditions_met({"weather": ["sunny", "rainy"]}, facts), "weather accepts a single value or a list")
	_check(not _conditions.conditions_met({"weather": &"rainy"}, facts) and not _conditions.conditions_met({"weather": ["rainy", "cloudy"]}, facts), "weather rejects a non-matching value")
	_check(_conditions.conditions_met({"quest_status": {"ch1_gate": "completed"}}, facts), "quest_status matches an exact quest state")
	_check(not _conditions.conditions_met({"quest_status": {"ch1_gate": "active"}}, facts), "quest_status rejects a different state")
	_check(not _conditions.conditions_met({"quest_status": {"ghost": "completed"}}, facts), "quest_status rejects an unknown quest")
	_check(_conditions.conditions_met({"flag": &"read_letter"}, facts) and _conditions.conditions_met({"flag": [&"read_letter", &"met_carpenter"]}, facts), "flag accepts a single read marker or a list")
	_check(not _conditions.conditions_met({"flag": &"unread"}, facts), "flag rejects a marker that has not been read")
	var dictionary_flags: Dictionary = {"friendship": 80, "day": 10, "weather": "sunny", "quests": {}, "flags": {"read_letter": true, "unread": false}}
	_check(_conditions.conditions_met({"flag": &"read_letter"}, dictionary_flags) and not _conditions.conditions_met({"flag": &"unread"}, dictionary_flags), "dictionary flags honour their boolean value")
	_check(_conditions.conditions_met({"friendship_min": 20, "day_min": 3, "day_max": 20, "weather": &"sunny", "quest_status": {"ch1_gate": "completed"}, "flag": &"read_letter"}, facts), "all six condition kinds can be satisfied together")
	_check(not _conditions.conditions_met({"friendship_min": 20, "weather": &"rainy"}, facts), "one unsatisfied condition fails the whole set")
	_check(_conditions.conditions_met({}, facts) and String(_conditions.last_rejection).is_empty(), "a met set leaves no rejection reason")


func _check_condition_rejections() -> void:
	var facts: Dictionary = {"friendship": 80, "day": 10, "weather": &"sunny", "quests": {"ch1_gate": "completed"}, "flags": [&"read_letter"]}
	for bad: Dictionary in [
		{"friendship_min": "20"}, {"friendship_min": 20.5}, {"friendship_min": true},
		{"day_min": "1"}, {"day_max": 1.5},
		{"weather": 3}, {"weather": [1, 2]},
		{"quest_status": "completed"}, {"quest_status": {"ch1_gate": 3}},
		{"flag": 3}, {"flag": [1]},
		{"unknown_key": 1}, {"Friendship_Min": 20},
	]:
		_check(not _conditions.conditions_met(bad, facts) and not String(_conditions.last_rejection).is_empty(), "invalid or unknown condition is refused with an explanation: %s" % str(bad))
	_check(not _conditions.conditions_met({"unknown_key": 1}, facts) and String(_conditions.last_rejection).contains("未知"), "unknown keys explain themselves as unknown")
	var non_string: Dictionary = {3: 1}
	_check(not _conditions.conditions_met(non_string, facts) and String(_conditions.last_rejection).contains("未知"), "a non-string key is refused as unknown")
	for bad_facts: Dictionary in [{}, {"friendship": "80"}, {"day": "10"}, {"weather": 5}, {"quests": []}, {"flags": 3}]:
		_check(not _conditions.conditions_met({"friendship_min": 1, "day_min": 1, "day_max": 30, "weather": &"sunny", "quest_status": {"ch1_gate": "completed"}, "flag": &"read_letter"}, bad_facts), "missing or mistyped facts never satisfy a full condition set: %s" % str(bad_facts))
	var conditions: Dictionary = {"friendship_min": 20}
	var facts_copy: Dictionary = {"friendship": 80}
	var c_snapshot: Dictionary = conditions.duplicate(true)
	var f_snapshot: Dictionary = facts_copy.duplicate(true)
	_conditions.conditions_met(conditions, facts_copy)
	_check(conditions == c_snapshot and facts_copy == f_snapshot, "condition evaluation never mutates the caller's dictionaries")


func _check_purity_and_release() -> void:
	_configure(_prefs())
	_service.gift(&"shopkeeper", &"egg")
	_service.release()
	_check(not _service.is_configured() and _service.week_key() == 0, "release clears the configuration and the weekly clock")
	_check(_service.encode() == {"schema": 1, "weeks": {}} and not bool(_service.can_gift(&"shopkeeper", &"egg").ok), "release leaves an empty weekly table and refuses gifts")
	_check(not _service.restore({"schema": 1, "weeks": {}}), "a released service refuses snapshots")
	_check(_configure(_prefs()), "the composition root can configure a released service again")
	_check(bool(_service.gift(&"shopkeeper", &"egg").ok) and _grants() == 1, "a reconfigured service starts a fresh week with one grant")
