extends RefCounted
## B6-01 周限礼与偏好记录：纯状态服务，不读场景/背包/存档，不发信号，不发奖励，不创建节点。
## 好感点数唯一归 Friendship；本服务只做周限与偏好判定，通过注入的 grant 请求加点，不复制好友状态。
## 扣物品由主线程在调用前完成：先 can_gift 再扣，超限时本服务返回 ok=false 让主线程不扣。

const SAVE_VERSION: int = 1
const BASE_POINTS: int = 10
const LIKED_BONUS: int = 10
const DAYS_PER_WEEK: int = 7
const MAX_PREFERENCES: int = 32

var busy: bool = false
var last_rejection: String = ""

var _limits: Dictionary = {}
var _liked: Dictionary = {}
var _neutral: Dictionary = {}
var _disliked: Dictionary = {}
var _counts: Dictionary = {}
var _grant: Callable = Callable()
var _current_day: Callable = Callable()


func is_configured() -> bool:
	return not _limits.is_empty()


## 新会话初始化：校验通过才整体替换并清空周计数；非法配置返回 false 且保留原状态。
func configure(preferences: Array[GiftPreference], grant: Callable, current_day: Callable) -> bool:
	if busy: return false
	if preferences.is_empty() or preferences.size() > MAX_PREFERENCES: return false
	if not grant.is_valid() or not current_day.is_valid(): return false
	var limits: Dictionary = {}
	var liked: Dictionary = {}
	var neutral: Dictionary = {}
	var disliked: Dictionary = {}
	for pref: GiftPreference in preferences:
		if pref == null or not pref.is_valid(): return false
		if limits.has(pref.npc_id): return false
		limits[pref.npc_id] = pref.weekly_limit
		liked[pref.npc_id] = _names(pref.liked)
		neutral[pref.npc_id] = _names(pref.neutral)
		disliked[pref.npc_id] = _names(pref.disliked)
	_limits = limits
	_liked = liked
	_neutral = neutral
	_disliked = disliked
	_counts.clear()
	_grant = grant
	_current_day = current_day
	last_rejection = ""
	return true


func _names(values: Array[StringName]) -> Dictionary:
	var result: Dictionary = {}
	for value: StringName in values:
		result[value] = true
	return result


func _has_in(table: Dictionary, npc_id: StringName, item_id: StringName) -> bool:
	var raw: Variant = table.get(npc_id, null)
	if not (raw is Dictionary): return false
	var names: Dictionary = raw
	return names.has(item_id)


## 隔离读取绝对日：无效 Callable、非整数或运行时错误导致的空返回都按 0 处理。
func _day() -> int:
	if not _current_day.is_valid(): return 0
	var value: Variant = _current_day.call()
	if value is int: return maxi(0, int(value))
	return 0


## 绝对周序号：第 1..7 天为 0，第 8..14 天为 1；跨天不回退，跨周旧计数自动失效。
func week_key() -> int:
	return maxi(0, _day() - 1) / DAYS_PER_WEEK


func _count_for(npc_id: StringName, week: int) -> int:
	var raw: Variant = _counts.get(npc_id, null)
	if not (raw is Dictionary): return 0
	var row: Dictionary = raw
	if int(row.get("week", -1)) != week: return 0
	return maxi(0, int(row.get("count", 0)))


## 只读偏好文本；不产生计数、不调用 grant。
func preference_of(npc_id: StringName, item_id: StringName) -> Dictionary:
	if not _limits.has(npc_id): return {"liked": false, "text": "没有这位村民的礼物偏好记录"}
	if item_id == &"": return {"liked": false, "text": "没有可送的物品"}
	if _has_in(_liked, npc_id, item_id): return {"liked": true, "text": "很喜欢这份礼物"}
	if _has_in(_disliked, npc_id, item_id): return {"liked": false, "text": "不太喜欢这份礼物"}
	if _has_in(_neutral, npc_id, item_id): return {"liked": false, "text": "收下了礼物"}
	return {"liked": false, "text": "第一次见到这份礼物"}


## 只校验周限与 NPC 配置，不改任何状态；主线程据此决定是否先扣物品。
func can_gift(npc_id: StringName, item_id: StringName) -> Dictionary:
	var liked: bool = _has_in(_liked, npc_id, item_id)
	if not _limits.has(npc_id): return {"ok": false, "reason": "未配置这位村民的礼物偏好", "liked": liked}
	if item_id == &"": return {"ok": false, "reason": "没有可送的物品", "liked": liked}
	var week: int = week_key()
	if _count_for(npc_id, week) >= int(_limits[npc_id]):
		return {"ok": false, "reason": "本周送礼已达上限", "liked": liked}
	return {"ok": true, "reason": "", "liked": liked}


## 送出一份礼物：先校验，再提交本周计数，最后通过注入端口请求加点。
## grant 返回 0 或非整数（含运行时错误空返回）都不回滚计数，保证不能重复刷礼。
func gift(npc_id: StringName, item_id: StringName) -> Dictionary:
	if busy: return {"ok": false, "reason": "操作进行中", "points": 0, "liked": false}
	busy = true
	var result: Dictionary = _commit_gift(npc_id, item_id)
	busy = false
	return result


func _commit_gift(npc_id: StringName, item_id: StringName) -> Dictionary:
	var check: Dictionary = can_gift(npc_id, item_id)
	if not bool(check.ok):
		last_rejection = String(check.reason)
		return {"ok": false, "reason": String(check.reason), "points": 0, "liked": bool(check.liked)}
	var week: int = week_key()
	var count: int = _count_for(npc_id, week)
	var liked: bool = bool(check.liked)
	var requested: int = BASE_POINTS + (LIKED_BONUS if liked else 0)
	_counts[npc_id] = {"week": week, "count": count + 1}
	var granted: int = _request_points(npc_id, requested)
	last_rejection = ""
	return {"ok": true, "reason": "", "points": granted, "liked": liked}


## 隔离调用注入端口：任何非 int 结果收敛为 0，保证事务正常收尾、busy 不泄漏。
func _request_points(npc_id: StringName, points: int) -> int:
	if not _grant.is_valid(): return 0
	var outcome: Variant = _grant.call(npc_id, points)
	if outcome is int: return maxi(0, int(outcome))
	return 0


func encode() -> Dictionary:
	var weeks: Dictionary = {}
	for npc_id: StringName in _counts:
		var row: Dictionary = _counts[npc_id]
		weeks[String(npc_id)] = {"week": int(row.get("week", 0)), "count": int(row.get("count", 0))}
	return {"schema": SAVE_VERSION, "weeks": weeks}


## 空字典是旧档缺分区（清空周计数）；未来版本、坏结构整分区拒绝并保留现状态。
func restore(data: Dictionary) -> bool:
	if busy or _limits.is_empty(): return false
	if data.is_empty():
		_counts.clear()
		last_rejection = ""
		return true
	if data.size() > 2: return _refuse("礼物存档结构无效")
	if typeof(data.get("schema", null)) != TYPE_INT or int(data.get("schema", 0)) != SAVE_VERSION:
		return _refuse("礼物存档版本不受支持")
	var raw_weeks: Variant = data.get("weeks", null)
	if not (raw_weeks is Dictionary) or raw_weeks.size() > MAX_PREFERENCES:
		return _refuse("礼物周计数表无效")
	var weeks: Dictionary = raw_weeks
	var decoded: Dictionary = {}
	for key: Variant in weeks:
		if not (key is String or key is StringName): return _refuse("礼物村民标识无效")
		var npc_id: StringName = StringName(key)
		if not _limits.has(npc_id): return _refuse("礼物周计数含未配置村民")
		var raw_row: Variant = weeks[key]
		if not (raw_row is Dictionary) or raw_row.size() != 2: return _refuse("礼物周计数行无效")
		var row: Dictionary = raw_row
		if typeof(row.get("week", null)) != TYPE_INT or typeof(row.get("count", null)) != TYPE_INT:
			return _refuse("礼物周计数类型无效")
		var week: int = int(row["week"])
		var count: int = int(row["count"])
		if week < 0 or count < 0 or count > int(_limits[npc_id]): return _refuse("礼物周计数越界")
		decoded[npc_id] = {"week": week, "count": count}
	_counts = decoded
	last_rejection = ""
	return true


func _refuse(reason: String) -> bool:
	last_rejection = reason
	return false


## 组合根离树时释放：清空配置副本、周计数与注入端口，不留下指向外部对象的 Callable。
func release() -> void:
	if busy: return
	_limits.clear()
	_liked.clear()
	_neutral.clear()
	_disliked.clear()
	_counts.clear()
	_grant = Callable()
	_current_day = Callable()
	last_rejection = ""
