extends SceneTree
## 操作音效生成器
##
## 和 `build_bgm.gd` 共用 `tools/lib/audio_synth.gd`，音色统一成"土、木、金属、布"的真实材质感，
## 而不是单薄的正弦波提示音——这是农场游戏里最影响"手感"的一层：
##   hoe      锄地：柔和松土 + 细碎土粒
##   water    浇水：水柱冲出壶口，落到地面
##   plant    播种：三粒种子落进松土
##   harvest  收获：木琴三连上行，清脆但温暖
##   chop     砍树：刀刃入木的闷响 + 木质共鸣 + 木屑
##   mine     采矿：镐头击石 + 碎石散落
##   coin     金币：经典双音叮当
##   step     脚步：草地轻踏
##   door     开门：木门吱呀 + 门闩
##   sleep    入睡：柔和下行三音
##   ui*      界面：木质轻敲与短促确认
##
## 运行：
##   godot --headless --path . --script res://tools/build/build_sfx.gd

const Synth := preload("res://tools/lib/audio_synth.gd")
const Mixer := preload("res://tools/lib/audio_mixer.gd")

const OUT_DIR: String = "res://assets/audio/sfx"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var jobs: Array[Dictionary] = [
		{"name": "hoe", "peak": 0.46, "render": _hoe},
		{"name": "water", "peak": 0.32, "render": _water},
		{"name": "plant", "peak": 0.3, "render": _plant},
		{"name": "harvest", "peak": 0.38, "render": _harvest},
		{"name": "chop", "peak": 0.5, "render": _chop},
		{"name": "mine", "peak": 0.46, "render": _mine},
		{"name": "coin", "peak": 0.82, "render": _coin},
		{"name": "step", "peak": 0.14, "render": _step},
		{"name": "door", "peak": 0.7, "render": _door},
		{"name": "sleep", "peak": 0.72, "render": _sleep},
		{"name": "ui", "peak": 0.62, "render": _ui},
		{"name": "ui_hover", "peak": 0.3, "render": _ui_hover},
		{"name": "ui_click", "peak": 0.55, "render": _ui_click},
		{"name": "ui_confirm", "peak": 0.66, "render": _ui_confirm},
		{"name": "ui_back", "peak": 0.58, "render": _ui_back},
	]
	var selected: PackedStringArray = PackedStringArray()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="):
			selected = argument.trim_prefix("--only=").split(",", false)
	for selected_name in selected:
		var found: bool = false
		for job in jobs:
			if String(job["name"]) == selected_name:
				found = true
		if not found:
			printerr("[build_sfx] 未知音效：%s" % selected_name)
			quit(1)
			return
	var failed: bool = false
	for job in jobs:
		var name: String = String(job["name"])
		if not selected.is_empty() and not selected.has(name):
			continue
		seed(hash(name))
		var render: Callable = job["render"]
		var samples: PackedFloat32Array = render.call()
		Mixer.normalize_mono(samples, float(job["peak"]))
		var path: String = "%s/%s.wav" % [OUT_DIR, name]
		if Mixer.write_mono(path, samples, false):
			print("[build_sfx] %s  %.3fs  %d frames" % [
				path, float(samples.size()) / float(Synth.SAMPLE_RATE), samples.size(),
			])
		else:
			printerr("[build_sfx] 写入失败：%s" % path)
			failed = true
	print("[build_sfx] 完成")
	quit(1 if failed else 0)


# --------------------------------------------------------------------------
# 农事
# --------------------------------------------------------------------------

func _hoe() -> PackedFloat32Array:
	var left: PackedFloat32Array = Synth.make_buffer(_frames(0.28))
	var right: PackedFloat32Array = Synth.make_buffer(left.size())
	Synth.noise_hit(left, right, 0, _frames(0.2), 0.5,
		{"lowpass": 0.07, "highpass": 0.004, "decay": 18.0, "attack": 0.006})
	Synth.thump(left, right, _frames(0.006), _frames(0.12), 0.12,
		{"from_hz": 155.0, "to_hz": 130.0, "decay": 30.0})
	Synth.noise_hit(left, right, _frames(0.055), _frames(0.15), 0.18,
		{"lowpass": 0.13, "highpass": 0.009, "decay": 22.0, "attack": 0.012})
	return _finish_natural(left, right)


func _water() -> PackedFloat32Array:
	var left: PackedFloat32Array = Synth.make_buffer(_frames(0.62))
	var right: PackedFloat32Array = Synth.make_buffer(left.size())
	Synth.noise_hit(left, right, 0, _frames(0.58), 0.48,
		{"lowpass": 0.11, "highpass": 0.012, "decay": 3.5, "attack": 0.05, "sweep": 0.2})
	Synth.noise_hit(left, right, _frames(0.09), _frames(0.4), 0.12,
		{"lowpass": 0.2, "highpass": 0.025, "decay": 6.0, "attack": 0.035})
	for i in 3:
		Synth.thump(left, right, _frames(0.17 + float(i) * 0.11), _frames(0.07), 0.025,
			{"from_hz": 820.0 - float(i) * 90.0, "to_hz": 520.0, "decay": 45.0})
	return _finish_natural(left, right)


func _plant() -> PackedFloat32Array:
	var left: PackedFloat32Array = Synth.make_buffer(_frames(0.3))
	var right: PackedFloat32Array = Synth.make_buffer(left.size())
	for i in 3:
		Synth.noise_hit(left, right, _frames(float(i) * 0.065), _frames(0.08),
			0.26 - float(i) * 0.04, {"lowpass": 0.1, "decay": 38.0, "attack": 0.004})
	Synth.noise_hit(left, right, _frames(0.16), _frames(0.12), 0.22,
		{"lowpass": 0.035, "decay": 26.0, "attack": 0.014})
	return _finish_natural(left, right)


func _harvest() -> PackedFloat32Array:
	var left: PackedFloat32Array = Synth.make_buffer(_frames(0.42))
	var right: PackedFloat32Array = Synth.make_buffer(left.size())
	Synth.noise_hit(left, right, 0, _frames(0.13), 0.1,
		{"lowpass": 0.09, "decay": 22.0, "attack": 0.006})
	var notes: Array[Array] = [[0.025, 523.25], [0.115, 659.26], [0.205, 783.99]]
	for item in notes:
		Synth.fm_tone(left, right, _frames(float(item[0])), _frames(0.21), float(item[1]), 0.15,
			{"ratio": 2.0, "index": 0.22, "index_decay": 6.0, "decay": 12.0,
			"attack": 0.008, "release": 0.06})
	return _finish_natural(left, right)


func _chop() -> PackedFloat32Array:
	var left: PackedFloat32Array = Synth.make_buffer(_frames(0.29))
	var right: PackedFloat32Array = Synth.make_buffer(left.size())
	Synth.noise_hit(left, right, 0, _frames(0.16), 0.28,
		{"lowpass": 0.16, "highpass": 0.009, "decay": 26.0, "attack": 0.003})
	Synth.fm_tone(left, right, _frames(0.004), _frames(0.18), 220.0, 0.24,
		{"ratio": 2.0, "index": 0.3, "index_decay": 15.0, "decay": 26.0,
		"attack": 0.005, "release": 0.045})
	Synth.fm_tone(left, right, _frames(0.008), _frames(0.13), 370.0, 0.06,
		{"ratio": 1.0, "index": 0.12, "decay": 35.0, "attack": 0.004})
	Synth.noise_hit(left, right, _frames(0.045), _frames(0.13), 0.085,
		{"lowpass": 0.14, "highpass": 0.016, "decay": 24.0, "attack": 0.012})
	return _finish_natural(left, right)


func _mine() -> PackedFloat32Array:
	var left: PackedFloat32Array = Synth.make_buffer(_frames(0.32))
	var right: PackedFloat32Array = Synth.make_buffer(left.size())
	Synth.noise_hit(left, right, 0, _frames(0.1), 0.36,
		{"lowpass": 0.21, "highpass": 0.014, "decay": 36.0, "attack": 0.003})
	Synth.fm_tone(left, right, _frames(0.004), _frames(0.12), 620.0, 0.12,
		{"ratio": 1.41, "index": 0.35, "index_decay": 22.0, "decay": 38.0,
		"attack": 0.004, "release": 0.035})
	Synth.noise_hit(left, right, _frames(0.005), _frames(0.12), 0.24,
		{"lowpass": 0.04, "decay": 28.0, "attack": 0.005})
	for i in 3:
		Synth.noise_hit(left, right, _frames(0.055 + float(i) * 0.052), _frames(0.07),
			0.11 - float(i) * 0.025,
			{"lowpass": 0.17, "highpass": 0.015, "decay": 36.0, "attack": 0.004})
	return _finish_natural(left, right)


# --------------------------------------------------------------------------
# 反馈与界面
# --------------------------------------------------------------------------

func _coin() -> PackedFloat32Array:
	var left := Synth.make_buffer(_frames(0.34))
	var right := Synth.make_buffer(left.size())
	# 经典金币双音：B5 → E6，金属味靠 ratio 2 的调制
	Synth.fm_tone(left, right, 0, _frames(0.12), 987.77, 0.45,
		{"ratio": 2.0, "index": 1.2, "index_decay": 4.0, "decay": 8.0})
	Synth.fm_tone(left, right, _frames(0.055), _frames(0.28), 1318.51, 0.5,
		{"ratio": 2.0, "index": 1.1, "index_decay": 3.5, "decay": 6.5, "release": 0.06})
	return _finish(left, right)


func _step() -> PackedFloat32Array:
	var left: PackedFloat32Array = Synth.make_buffer(_frames(0.16))
	var right: PackedFloat32Array = Synth.make_buffer(left.size())
	Synth.noise_hit(left, right, 0, _frames(0.12), 0.32,
		{"lowpass": 0.065, "highpass": 0.003, "decay": 28.0, "attack": 0.007})
	Synth.noise_hit(left, right, _frames(0.025), _frames(0.1), 0.13,
		{"lowpass": 0.035, "decay": 32.0, "attack": 0.01})
	return _finish_natural(left, right)


func _door() -> PackedFloat32Array:
	var left := Synth.make_buffer(_frames(0.45))
	var right := Synth.make_buffer(left.size())
	# 木头摩擦的底噪
	Synth.noise_hit(left, right, 0, _frames(0.4), 0.28,
		{"lowpass": 0.16, "highpass": 0.04, "decay": 4.2, "attack": 0.05})
	# 吱呀：颤音制造干涩的摩擦感
	Synth.fm_tone(left, right, _frames(0.03), _frames(0.34), 392.0, 0.12,
		{"ratio": 2.4, "index": 2.4, "index_decay": 6.0, "decay": 5.0,
		"vibrato_rate": 9.0, "vibrato_depth": 0.018, "release": 0.06})
	# 门板轻撞门框
	Synth.thump(left, right, _frames(0.02), _frames(0.16), 0.3,
		{"from_hz": 165.0, "to_hz": 88.0, "decay": 26.0})
	return _finish(left, right)


func _sleep() -> PackedFloat32Array:
	var left := Synth.make_buffer(_frames(0.95))
	var right := Synth.make_buffer(left.size())
	# 柔和下行三音：C5 - G4 - C4，上行是奖励，下行是放松
	var notes: Array[Array] = [[0.0, 523.25], [0.22, 392.0], [0.46, 261.63]]
	for item in notes:
		Synth.fm_tone(left, right, _frames(float(item[0])), _frames(0.5), float(item[1]), 0.4,
			{"ratio": 1.0, "index": 0.5, "index_decay": 1.5, "decay": 1.6,
			"attack": 0.02, "release": 0.3})
	Mixer.reverb(left, right, 0.3, 0.82)
	return _finish(left, right)


func _ui() -> PackedFloat32Array:
	var left := Synth.make_buffer(_frames(0.12))
	var right := Synth.make_buffer(left.size())
	# 木质轻敲，不再是尖细的电子"滴"
	Synth.fm_tone(left, right, 0, _frames(0.1), 920.0, 0.5,
		{"ratio": 1.5, "index": 0.7, "index_decay": 9.0, "decay": 26.0, "release": 0.02})
	Synth.noise_hit(left, right, 0, _frames(0.025), 0.12,
		{"lowpass": 0.55, "highpass": 0.3, "decay": 60.0})
	return _finish(left, right)


func _ui_hover() -> PackedFloat32Array:
	var left := Synth.make_buffer(_frames(0.07))
	var right := Synth.make_buffer(left.size())
	Synth.fm_tone(left, right, 0, _frames(0.06), 1180.0, 0.45,
		{"ratio": 1.4, "index": 0.5, "index_decay": 12.0, "decay": 45.0, "release": 0.015})
	return _finish(left, right)


func _ui_click() -> PackedFloat32Array:
	var left := Synth.make_buffer(_frames(0.1))
	var right := Synth.make_buffer(left.size())
	# 更硬的一点木块声，和悬停的轻触区分开
	Synth.fm_tone(left, right, 0, _frames(0.08), 760.0, 0.45,
		{"ratio": 1.6, "index": 0.9, "index_decay": 10.0, "decay": 34.0, "release": 0.02})
	Synth.noise_hit(left, right, 0, _frames(0.02), 0.16,
		{"lowpass": 0.7, "highpass": 0.35, "decay": 70.0})
	return _finish(left, right)


func _ui_confirm() -> PackedFloat32Array:
	var left := Synth.make_buffer(_frames(0.28))
	var right := Synth.make_buffer(left.size())
	var notes: Array[Array] = [[0.0, 659.26], [0.09, 880.0]]
	for item in notes:
		Synth.fm_tone(left, right, _frames(float(item[0])), _frames(0.18), float(item[1]), 0.4,
			{"ratio": 3.0, "index": 1.2, "index_decay": 5.0, "decay": 10.0, "release": 0.04})
	return _finish(left, right)


func _ui_back() -> PackedFloat32Array:
	var left := Synth.make_buffer(_frames(0.26))
	var right := Synth.make_buffer(left.size())
	var notes: Array[Array] = [[0.0, 880.0], [0.085, 659.26]]
	for item in notes:
		Synth.fm_tone(left, right, _frames(float(item[0])), _frames(0.17), float(item[1]), 0.38,
			{"ratio": 3.0, "index": 1.1, "index_decay": 5.0, "decay": 11.0, "release": 0.04})
	return _finish(left, right)


# --------------------------------------------------------------------------
# 工具
# --------------------------------------------------------------------------

func _frames(seconds: float) -> int:
	return maxi(int(round(seconds * float(Synth.SAMPLE_RATE))), 1)


func _finish_natural(left: PackedFloat32Array, right: PackedFloat32Array) -> PackedFloat32Array:
	Mixer.tame_highs(left, right, 0.3)
	Mixer.remove_dc(left, right)
	Mixer.limit_stereo(left, right, 1.0)
	return _finish(left, right, 0.004)


func _finish(left: PackedFloat32Array, right: PackedFloat32Array,
		fade_seconds: float = 0.001) -> PackedFloat32Array:
	var mono: PackedFloat32Array = Mixer.mix_down(left, right)
	var fade: int = mini(_frames(fade_seconds), mono.size() / 4)
	for i in fade:
		var gain: float = float(i) / float(fade)
		mono[i] *= gain
		mono[mono.size() - 1 - i] *= gain
	return mono
