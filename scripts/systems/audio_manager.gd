extends Node
## 背景音乐管理器（autoload：`AudioManager`）
##
## 曲目都是离线合成的原创循环（见 `tools/build/build_bgm.gd`），
## 这里负责：加载曲目、强制首尾循环、双播放器交叉淡入淡出、音量与开关。
## 因为挂在 autoload 上，切场景（标题 ↔ 农场）音乐不会被打断。
##
## 用法：
##   AudioManager.play_music(&"farm_day")
##   AudioManager.set_music_volume(-14.0)

signal track_changed(track: StringName)

const TRACKS: Dictionary = {
	&"menu": "res://assets/audio/bgm/menu.wav",
	&"farm_day": "res://assets/audio/bgm/farm_day.wav",
	&"farm_night": "res://assets/audio/bgm/farm_night.wav",
}
## 游戏内 BGM 基准音量，偏小一点给音效留空间。
const VOLUME_DB: float = -10.0
const SILENT_DB: float = -60.0
const DEFAULT_FADE: float = 1.2

## 当前曲目名，空 StringName 表示没在放。
var current_track: StringName = &""
var music_enabled: bool = true

var _players: Array[AudioStreamPlayer] = []
var _tweens: Array[Tween] = []
var _active: int = 0
var _volume_db: float = VOLUME_DB


func _ready() -> void:
	# 暂停菜单会暂停场景树，音乐要照常淡出淡入
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Music%d" % i
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.volume_db = SILENT_DB
		add_child(player)
		_players.append(player)
		_tweens.append(null)


## 切到指定曲目；同一首正在放时不会重播。
func play_music(track: StringName, fade: float = DEFAULT_FADE) -> void:
	if _players.is_empty():
		return
	if track == current_track and _players[_active].playing:
		return
	var path: String = str(TRACKS.get(track, ""))
	if path.is_empty():
		push_warning("[AudioManager] 未知曲目：%s" % track)
		return
	var stream: AudioStreamWAV = _load_looped(path)
	if stream == null:
		return

	current_track = track
	var previous_index: int = _active
	_active = 1 - _active
	var player: AudioStreamPlayer = _players[_active]
	player.stream = stream
	player.volume_db = SILENT_DB
	player.play()
	_fade_to(_active, _target_db(), fade)
	if _players[previous_index].playing:
		_fade_to(previous_index, SILENT_DB, fade, true)
	track_changed.emit(track)


func stop_music(fade: float = DEFAULT_FADE) -> void:
	current_track = &""
	for index in _players.size():
		if _players[index].playing:
			_fade_to(index, SILENT_DB, fade, true)


## 设置 BGM 音量（dB），关掉音乐后再打开会沿用这个值。
func set_music_volume(db: float) -> void:
	_volume_db = clampf(db, SILENT_DB, 6.0)
	if _players.is_empty():
		return
	_players[_active].volume_db = _target_db()


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	if _players.is_empty():
		return
	_players[_active].volume_db = _target_db()


func is_music_playing() -> bool:
	if _players.is_empty():
		return false
	return _players[_active].playing and _players[_active].stream != null


func _target_db() -> float:
	return _volume_db if music_enabled else SILENT_DB


func _fade_to(index: int, target_db: float, fade: float, stop_after: bool = false) -> void:
	var player: AudioStreamPlayer = _players[index]
	var previous: Tween = _tweens[index]
	if previous != null and previous.is_valid():
		previous.kill()
	if fade <= 0.0:
		player.volume_db = target_db
		if stop_after:
			player.stop()
		return
	var tween: Tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(player, "volume_db", target_db, fade)
	if stop_after:
		tween.tween_callback(player.stop)
	_tweens[index] = tween


## 加载曲目并保证是首尾循环：导入器没识别到 smpl 循环块时兜底补上。
func _load_looped(path: String) -> AudioStreamWAV:
	var stream: AudioStreamWAV = load(path) as AudioStreamWAV
	if stream == null:
		push_warning("[AudioManager] 无法加载 %s" % path)
		return null
	if stream.loop_mode != AudioStreamWAV.LOOP_FORWARD:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	if stream.loop_end <= stream.loop_begin:
		stream.loop_begin = 0
		stream.loop_end = int(round(stream.get_length() * float(stream.mix_rate)))
	return stream
