extends RefCounted
## 存储端口。实现者只负责完整文档的读写，不访问游戏节点。

var last_error: Error = OK


func read(_path: String) -> Dictionary:
	last_error = ERR_UNAVAILABLE
	return {}


func write(_path: String, _document: Dictionary) -> bool:
	last_error = ERR_UNAVAILABLE
	return false
