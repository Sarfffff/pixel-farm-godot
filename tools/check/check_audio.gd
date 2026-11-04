extends SceneTree
## 背景音乐：曲目资源、循环点、切换与淡入淡出、昼夜换曲、标题曲目、暂停不中断。
##
## 运行方式：
##   godot --headless --path e:/my-ai-game --script res://tools/check/check_audio.gd

var _failures: int = 0


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("[audio] FAIL: " + message)


func _run() -> void:
	var mgr := root.get_node_or_null("AudioManager")
	_check(mgr != null, "AudioManager autoload exists")
	if mgr == null:
		_finish()
		return

	# 1. 三首曲子都能加载、长度合理、自动循环
	var tracks: Dictionary = load("res://scripts/systems/audio_manager.gd").get_script_constant_map()["TRACKS"]
	_check(tracks.size() == 3, "three tracks registered")
	for key in tracks:
		var stream: AudioStreamWAV = load(str(tracks[key])) as AudioStreamWAV
		_check(stream != null, "track loads: %s" % key)
		if stream == null:
			continue
		var length: float = stream.get_length()
		_check(length > 8.0 and length < 40.0, "%s length sane (%.1fs)" % [key, length])
		_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s loops forward" % key)
		_check(stream.loop_end > stream.loop_begin, "%s has a loop range" % key)
		_check(stream.loop_end >= int(round(length * float(stream.mix_rate))) - 1,
			"%s loops whole track (%d)" % [key, stream.loop_end])

	# 2. 两个音乐播放器 + 一组音效播放器，暂停时都继续放
	var music_players: int = 0
	var sfx_players: int = 0
	for child in mgr.get_children():
		var player := child as AudioStreamPlayer
		if player == null:
			continue
		if String(player.name).begins_with("Music"):
			music_players += 1
		elif String(player.name).begins_with("Sfx"):
			sfx_players += 1
		_check(player.process_mode == Node.PROCESS_MODE_ALWAYS, "player runs while paused")
	_check(music_players == 2, "two players for crossfade")
	_check(sfx_players >= 4, "sfx pool exists")

	# 3. 播放与切换
	mgr.play_music(&"farm_day", 0.0)
	await process_frame
	_check(mgr.current_track == &"farm_day", "play farm_day")
	_check(mgr.is_music_playing(), "farm_day is playing")
	mgr.play_music(&"farm_night", 0.0)
	await process_frame
	_check(mgr.current_track == &"farm_night", "switch to farm_night")
	var playing: int = 0
	for child in mgr.get_children():
		if (child as AudioStreamPlayer).playing:
			playing += 1
	_check(playing == 1, "旧曲目淡出后停止（当前在放 %d 个）" % playing)

	# 4. 未知曲目不动当前播放
	mgr.play_music(&"nope", 0.0)
	_check(mgr.current_track == &"farm_night", "unknown track ignored")

	# 5. 音量与开关
	mgr.set_music_volume(-20.0)
	_check(is_equal_approx(_active_volume(mgr), -20.0), "volume applied")
	mgr.set_music_enabled(false)
	_check(is_equal_approx(_active_volume(mgr), -60.0), "disabled mutes")
	mgr.set_music_enabled(true)
	_check(is_equal_approx(_active_volume(mgr), -20.0), "enabled restores volume")
	mgr.set_music_volume(-10.0)

	# 6. 主场景：白天曲目，入夜切夜晚，睡觉切回白天
	var main: Node2D = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node2D
	main.get_node("Systems/Save").set(&"autoload_enabled", false)
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	_check(main.get_node_or_null("Systems/BGM") != null, "main scene has Systems/BGM")
	_check(mgr.current_track == &"farm_day", "main scene starts with day track")

	var time: Node = get_first_node_in_group(&"time")
	_check(time != null, "time system present")
	if time != null:
		time.set(&"minutes", 17 * 60 - 1)
		time.call(&"_process", 1.0)
		await process_frame
		_check(mgr.current_track == &"farm_night", "evening switches to night track")
		time.call(&"sleep")
		await process_frame
		_check(mgr.current_track == &"farm_day", "waking up switches back to day track")

	# 7. 标题界面用 menu 曲目
	var menu: Control = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate() as Control
	root.add_child(menu)
	await process_frame
	_check(mgr.current_track == &"menu", "title screen plays menu track")
	menu.queue_free()

	# 8. 操作音效：都能加载、不循环、能播、不打断音乐
	var sfx_names: Dictionary = load("res://scripts/systems/audio_manager.gd").get_script_constant_map()["SFX"]
	_check(sfx_names.size() >= 8, "sfx registered (%d)" % sfx_names.size())
	for key in sfx_names:
		var sfx: AudioStreamWAV = load(str(sfx_names[key])) as AudioStreamWAV
		_check(sfx != null, "sfx loads: %s" % key)
		if sfx == null:
			continue
		var sfx_length: float = sfx.get_length()
		_check(sfx_length > 0.04 and sfx_length < 1.2, "%s sfx length sane (%.2fs)" % [key, sfx_length])
		_check(sfx.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s sfx does not loop" % key)

	mgr.play_sfx(&"hoe")
	await process_frame
	var playing_sfx: int = 0
	for child in mgr.get_children():
		var player := child as AudioStreamPlayer
		if player != null and String(player.name).begins_with("Sfx") and player.playing:
			playing_sfx += 1
	_check(playing_sfx >= 1, "sfx actually plays")
	_check(mgr.current_track == &"menu", "sfx does not disturb the music")
	mgr.play_sfx(&"nope")
	_check(mgr.current_track == &"menu", "unknown sfx is ignored")
	mgr.set_sfx_enabled(false)
	mgr.play_sfx(&"coin")
	_check(not mgr.is_sfx_enabled(), "sfx can be muted")
	mgr.set_sfx_enabled(true)
	_check(mgr.is_sfx_enabled(), "sfx can be turned back on")

	# 9. 停止
	mgr.stop_music(0.0)
	await process_frame
	_check(not mgr.is_music_playing(), "stop_music silences")

	_finish(main)


## 只看音乐播放器的音量，音效池在响也不影响判断。
func _active_volume(mgr: Node) -> float:
	var music: Array[AudioStreamPlayer] = []
	for child in mgr.get_children():
		var player := child as AudioStreamPlayer
		if player != null and String(player.name).begins_with("Music"):
			music.append(player)
	for player in music:
		if player.playing:
			return player.volume_db
	return music[0].volume_db if not music.is_empty() else 0.0


func _finish(main: Node = null) -> void:
	if main != null:
		main.queue_free()
	if _failures == 0:
		print("[audio] all checks passed")
		quit(0)
	else:
		printerr("[audio] %d check(s) failed" % _failures)
		quit(1)
