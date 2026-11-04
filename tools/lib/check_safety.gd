extends RefCounted
## 所有回归必须先确认 user:// 隔离，防止开发命令误删玩家槽位。


static func require_isolated(tree: SceneTree) -> bool:
	var isolated: bool = bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false))
	var directory: String = str(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not isolated or not directory.begins_with("PixelFarmChecks_"):
		printerr("[checks] REFUSED: 请使用 tools/run_checks.ps1；当前 user:// 未使用专用测试目录")
		tree.quit(2)
		return false
	return true
