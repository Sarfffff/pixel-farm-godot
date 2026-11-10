extends RefCounted
## B5-07 鱼种条件与渔具成长：纯查询。不读场景/库存/存档，不发信号，不改传入Resource。

const MAX_SPECIES: int = 64
const MAX_GEAR: int = 32
const MINUTE_LIMIT: int = FishSpeciesData.MINUTE_LIMIT
const NAME_KEYS: Array[StringName] = [&"region", &"season", &"weather", &"rod_item"]

var _species: Array[FishSpeciesData] = []
var _lookup: Dictionary[StringName, FishSpeciesData] = {}
var _gear: Dictionary[StringName, FishingGearData] = {}
var _released: bool = false


## 全部条目先校验并复制，再整体替换；失败时旧配置继续可用。
func configure(species: Array[FishSpeciesData], gear: Array[FishingGearData]) -> bool:
	if _released or species.size() > MAX_SPECIES or gear.size() > MAX_GEAR: return false
	var accepted: Dictionary[StringName, FishSpeciesData] = {}
	for data: FishSpeciesData in species:
		if data == null or not data.is_valid() or accepted.has(data.id): return false
		accepted[data.id] = data.duplicate(true) as FishSpeciesData
	var gears: Dictionary[StringName, FishingGearData] = {}
	for data: FishingGearData in gear:
		if data == null or not data.is_valid() or gears.has(data.item_id): return false
		gears[data.item_id] = data.duplicate(true) as FishingGearData
	var ids: Array[String] = []
	for id: StringName in accepted: ids.append(String(id))
	ids.sort()
	var ordered: Array[FishSpeciesData] = []
	for id: String in ids: ordered.append(accepted[StringName(id)])
	_species = ordered
	_lookup = accepted
	_gear = gears
	return true


## 只按条件过滤，不参与权重；缺键或类型错返回空数组。
func candidates(ctx: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	if _released: return result
	var parsed: Dictionary = _context(ctx)
	if not bool(parsed.ok): return result
	return _matching(parsed)


## 同ctx同seed结果一致；按候选权重做确定性抽取，无候选时给出原因。
func pick(ctx: Dictionary, seed: int) -> Dictionary:
	if _released: return _miss("鱼种规则尚未配置")
	var parsed: Dictionary = _context(ctx)
	if not bool(parsed.ok): return _miss(String(parsed.reason))
	var ids: Array[StringName] = _matching(parsed)
	if ids.is_empty(): return _miss("当前条件没有可钓的鱼")
	var gear: FishingGearData = _gear.get(StringName(parsed.rod_item))
	var bonus: Dictionary[StringName, float] = gear.allowed_species_bonus if gear != null else {}
	var weights: Array[float] = []
	var total: float = 0.0
	for id: StringName in ids:
		var weight: float = _effective_weight(id, bonus)
		weights.append(weight)
		total += weight
	if total <= 0.0: return _miss("当前条件没有可钓的鱼")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var roll: float = rng.randf() * total
	var upto: float = 0.0
	for index: int in ids.size():
		upto += weights[index]
		if roll < upto: return {"ok": true, "fish": ids[index], "reason": ""}
	return {"ok": true, "fish": ids[ids.size() - 1], "reason": ""}


## 未登记的渔具按 0 级计算，因此会过滤掉所有设了最低等级的鱼。
func gear_level(item_id: StringName) -> int:
	if _released: return 0
	var gear: FishingGearData = _gear.get(item_id)
	return gear.level if gear != null else 0


## 未登记或非有限系数回退 1.0，调用方拿到的总是可用体力倍率。
func cast_stamina_scale(item_id: StringName) -> float:
	if _released: return 1.0
	var gear: FishingGearData = _gear.get(item_id)
	if gear == null: return 1.0
	var scale: float = float(gear.cast_stamina_scale)
	return scale if is_finite(scale) and scale > 0.0 else 1.0


func release() -> void:
	_species.clear()
	_lookup.clear()
	_gear.clear()
	_released = true


func _context(ctx: Dictionary) -> Dictionary:
	for key: StringName in NAME_KEYS:
		if not ctx.has(key): return _bad_context("钓鱼条件缺少：" + String(key))
		var value: Variant = ctx[key]
		if not (value is String or value is StringName) or String(value).is_empty(): return _bad_context("钓鱼条件类型无效：" + String(key))
	if not ctx.has(&"minute") or not _valid_minute(ctx[&"minute"]): return _bad_context("钓鱼条件时间无效")
	return {
		"ok": true,
		"reason": "",
		"region": StringName(ctx[&"region"]),
		"season": StringName(ctx[&"season"]),
		"weather": StringName(ctx[&"weather"]),
		"minute": int(ctx[&"minute"]),
		"rod_item": StringName(ctx[&"rod_item"]),
	}


func _matching(parsed: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	var level: int = gear_level(StringName(parsed.rod_item))
	for data: FishSpeciesData in _species:
		if level < data.min_rod_level: continue
		if not data.regions.has(parsed.region): continue
		if not data.seasons.has(parsed.season): continue
		if not data.weathers.has(parsed.weather): continue
		if int(parsed.minute) < data.min_minute or int(parsed.minute) > data.max_minute: continue
		result.append(data.id)
	return result


func _effective_weight(id: StringName, bonus: Dictionary[StringName, float]) -> float:
	var data: FishSpeciesData = _lookup.get(id)
	if data == null: return 0.0
	var scale: float = 1.0 + float(bonus.get(id, 0.0))
	return data.weight * maxf(scale, 0.0)


func _valid_minute(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value) and value >= 0 and value <= MINUTE_LIMIT


func _bad_context(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func _miss(reason: String) -> Dictionary:
	return {"ok": false, "fish": &"", "reason": reason}
