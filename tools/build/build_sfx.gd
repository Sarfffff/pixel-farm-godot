extends SceneTree
## 操作音效生成器
##
## 和 `build_bgm.gd` 共用 `tools/lib/audio_synth.gd`，音色统一成"土、木、金属、布"的真实材质感，
## 而不是单薄的正弦波提示音——这是农场游戏里最影响"手感"的一层：
##   hoe      锄地：铲刃入土的低频 + 翻起的土块
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
		{"name": "hoe", "peak": 0.88, "samples": _hoe()},
		{"name": "water", "peak": 0.72, "samples": _water()},
		{"name": "plant", "peak": 0.66, "samples": _plant()},
		{"name": "harvest", "peak": 0.84, "samples": _harvest()},
		{"name": "chop", "peak": 0.88, "samples": _chop()},
		{"name": "mine", "peak": 0.86, "samples": _mine()},
		{"name": "coin", "peak": 0.82, "samples": _coin()},
		{"name": "step", "peak": 0.45, "samples": _step()},
		{"name": "door", "peak": 0.7, "samples": _door()},
		{"name": "sleep", "peak": 0.72, "samples": _sleep()},
		{"name": "ui", "peak": 0.62, "samples": _ui()},
		{"name": "ui_hover", "peak": 0.3, "samples": _ui_hover()},
		{"name": "ui_click", "peak": 0.55, "samples": _ui_click()},
		{"name": "ui_confirm", "peak": 0.66, "samples": _ui_confirm()},
		{"name": "ui_back", "peak": 0.58, "samples": _ui_back()},
	]
	var failed: bool = false
	for job in jobs:
		var name: String = String(job["name"])
		var samples: PackedFloat32Array = job["samples"]
		Mixer.normalize_mono(samples, float(job["peak"]))
		var path := "%s/%s.wav" % [OUT_DIR, name]
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
	var left := Synth.make_buffer(_frames(0.30))
	var right := Synth.make_buffer(left.size())
	# 铲刃入土：低频下坠 + 一点金属/木柄的撞击感
	Synth.thump(left, right, 0, _frames(0.26), 0.85,
		{"from_hz": 175.0, "to_hz": 58.0, "decay": 14.0, "click": 0.32})
	# 翻起的土块：低通噪声，衰减很快
	Synth.noise_hit(left, right, 0, _frames(0.22), 0.5,
		{"lowpass": 0.3, "highpass": 0.12, "decay": 15.0})
	# 散落的碎土粒
	Synth.noise_hit(left, right, _frames(0.03), _frames(0.12), 0.16,
		{"lowpass": 0.6, "highpass": 0.4, "decay": 32.0})
	return _finish(left, right)


func _water() -> PackedFloat32Array:
	var left := Synth.make_buffer(_frames(0.48))
	var right := Synth.make_buffer(left.size())
	# 水柱：带宽较窄的噪声，慢慢起、慢慢收
	Synth.noise_hit(left, right, 0, _frames(0.48), 0.55,
		{"lowpass": 0.44, "highpass": 0.2, "decay": 4.6, "attack": 0.06, "sweep": 0.45})
	# 落地水花
	Synth.noise_hit(left, right, _frames(0.02), _frames(0.34), 0.26,
		{"lowpass": 0.72, "highpass": 0.46, "decay": 7.5, "attack": 0.03})
	# 一两颗水滴
	Synth.fm_tone(left, right, _frames(0.14), _frames(0.16), 1180.0, 0.09,
		{"ratio": 2.0, "index": 0.7, "index_decay": 8.0, "decay": 26.0})
	return _finish(left, right)


func _plant() -> PackedFloat32Array:
	var left := Synth.make_buffer(_frames(0.30))
	var right := Synth.make_buffer(left.size())
	# 三粒种子先后落进松土
	Synth.noise_hit(left, right, 0, _frames(0.07), 0.32,
		{"lowpass": 0.24, "decay": 42.0})
	Synth.noise_hit(left, right, _frames(0.07), _frames(0.07), 0.28,
		{"lowpass": 0.26, "decay": 40.0})
	Synth.noise_hit(left, right, _frames(0.15), _frames(0.07), 0.22,
		{"lowpass": 0.3, "decay": 46.0})
	# 手按进土里的闷声
	Synth.thump(left, right, _frames(0.01), _frames(0.14), 0.3,
		{"from_hz": 230.0, "to_hz": 110.0, "decay": 34.0})
	return _finish(left, right)


func _harvest() -> PackedFloat32Array:
	var left := Synth.make_buffer(_frames(0.38))
	var right := Synth.make_buffer(left.size())
	# 木琴三连上行：C6 - E6 - G6，收获的奖励感靠这三个音
	var notes: Array[Array] = [[0.0, 1046.5], [0.075, 1318.5], [0.15, 1568.0]]
	for item in notes:
		Synth.fm_tone(left, right, _frames(float(item[0])), _frames(0.24), float(item[1]), 0.42,
			{"ratio": 3.0, "index": 1.6, "index_decay": 5.0, "decay": 8.5, "release": 0.04})
	# 采下来的轻微"啵"
	Synth.thump(left, right, 0, _frames(0.09), 0.22,
		{"from_hz": 320.0, "to_hz": 190.0, "decay": 40.0})
	return _finish(left, right)


func _chop() -> PackedFloat32Array:
	var left := Synth.make_buffer(_frames(0.32))
	var right := Synth.make_buffer(left.size())
	# 斧刃入木
	Synth.thump(left, right, 0, _frames(0.26), 0.8,
		{"from_hz": 245.0, "to_hz": 92.0, "decay": 15.0, "click": 0.42})
	Synth.noise_hit(left, right, 0, _frames(0.18), 0.48,
		{"lowpass": 0.4, "highpass": 0.1, "decay": 18.0})
	# 木头的空腔共鸣
	Synth.fm_tone(left, right, _frames(0.006), _frames(0.22), 196.0, 0.26,
		{"ratio": 1.5, "index": 0.9, "index_decay": 6.0, "decay": 22.0, "release": 0.05})
	# 崩开的木屑
	Synth.noise_hit(left, right, _frames(0.05), _frames(0.12), 0.14,
		{"lowpass": 0.9, "highpass": 0.58, "decay": 30.0})
	return _finish(left, right)


func _mine() -> PackedFloat32Array:
	var left := Synth.make_buffer(_frames(0.34))
	var right := Synth.make_buffer(left.size())
	# 镐头撞石
	Synth.noise_hit(left, right, 0, _frames(0.14), 0.55,
		{"lowpass": 0.88, "highpass": 0.5, "decay": 27.0})
	# 金属镐的锐利泛音
	Synth.fm_tone(left, right, 0, _frames(0.2), 1760.0, 0.2,
		{"ratio": 3.3, "index": 2.2, "index_decay": 7.0, "decay": 19.0})
	Synth.thump(left, right, 0, _frames(0.2), 0.42,
		{"from_hz": 185.0, "to_hz": 80.0, "decay": 21.0})
	# 碎石散落
	for i in 4:
		Synth.noise_hit(left, right, _frames(0.06 + float(i) * 0.045), _frames(0.08),
			0.13 - float(i) * 0.02,
			{"lowpass": 0.62, "highpass": 0.36, "decay": 38.0})
	return _finish(left, right)


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
	var left := Synth.make_buffer(_frames(0.14))
	var right := Synth.make_buffer(left.size())
	# 草地：闷噪声当鞋底，低频当落地
	Synth.noise_hit(left, right, 0, _frames(0.11), 0.45,
		{"lowpass": 0.3, "highpass": 0.06, "decay": 38.0, "attack": 0.002})
	Synth.thump(left, right, 0, _frames(0.09), 0.24,
		{"from_hz": 132.0, "to_hz": 82.0, "decay": 45.0})
	return _finish(left, right)


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


## 双声道工作缓冲收成单声道音效，并淡入淡出 1ms，避免首尾爆音。
func _finish(left: PackedFloat32Array, right: PackedFloat32Array) -> PackedFloat32Array:
	var mono: PackedFloat32Array = Mixer.mix_down(left, right)
	var fade: int = mini(_frames(0.001), mono.size() / 4)
	for i in fade:
		var gain: float = float(i) / float(fade)
		mono[i] *= gain
		mono[mono.size() - 1 - i] *= gain
	return mono
