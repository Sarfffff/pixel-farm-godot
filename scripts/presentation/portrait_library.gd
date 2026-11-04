extends RefCounted
## 只映射已存在的四位村民，服饰与行走图一致。

const PEOPLE: Array[StringName] = [&"shopkeeper", &"gardener", &"carpenter", &"fisherman"]
const EMOTIONS: Array[StringName] = [&"neutral", &"happy", &"concerned"]
static var _cache: Dictionary[String, Texture2D] = {}


static func for_owner(owner: Node, emotion: StringName) -> Texture2D:
	if not is_instance_valid(owner): return null
	var id: StringName = &""
	for property: Dictionary in owner.get_property_list():
		if property.name == "npc_id": id = StringName(owner.get(&"npc_id"))
	if id == &"" and owner.get_script() != null and owner.get_script().resource_path.ends_with("/shopkeeper.gd"):
		id = &"shopkeeper"
	# 部分村民尚未加入好感系统，头像身份从其独立场景取得，不改变 npc_id 或存档。
	if id == &"":
		id = StringName(owner.scene_file_path.get_file().get_basename())
	if not PEOPLE.has(id): return null
	var mood: StringName = emotion if EMOTIONS.has(emotion) else &"neutral"
	var key: String = "%s_%s" % [id, mood]
	if not _cache.has(key):
		_cache[key] = load("res://assets/packs/presentation_v3/portraits/" + key + ".png") as Texture2D
	return _cache[key]
