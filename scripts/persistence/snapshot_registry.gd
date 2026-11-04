extends RefCounted
## 小接口适配器：每个持久化参与者只提供编码/恢复回调，注册顺序就是依赖恢复顺序。

var _sections: Array[Dictionary] = []


func has_sections() -> bool:
	return not _sections.is_empty()


func clear() -> void:
	_sections.clear()


func register_section(key: StringName, encode: Callable, decode: Callable, kind: int = TYPE_DICTIONARY, restore_missing: bool = false) -> void:
	assert(not _sections.any(func(section: Dictionary) -> bool: return section.key == key), "duplicate save section")
	_sections.append({&"key": key, &"encode": encode, &"decode": decode, &"kind": kind, &"restore_missing": restore_missing})


func collect() -> Dictionary:
	var result: Dictionary = {}
	for section: Dictionary in _sections:
		result[section.key] = section.encode.call()
	return result


func restore(data: Dictionary) -> void:
	for section: Dictionary in _sections:
		var value: Variant = data.get(String(section.key))
		if section.kind == TYPE_INT and value is float:
			value = int(value)
		if typeof(value) == section.kind:
			section.decode.call(value)
		elif section.restore_missing and section.kind == TYPE_DICTIONARY:
			section.decode.call({})
