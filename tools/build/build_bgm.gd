extends SceneTree
## 背景音乐生成器
##
## 三首原创循环曲，音色换成"木吉他 + 木琴 + 弦乐垫 + 手风琴"的民谣农场风格，
## 对齐市面上农场经营游戏的听感：白天轻快有律动、夜晚安静留白、标题温暖期待。
## 每首都按整小节渲染，长音和混响尾巴回绕到开头，所以循环点听不出接缝；
## 生成的 WAV 内写 smpl 循环块，Godot 导入后即可自动循环。
##
## 运行：
##   godot --headless --path . --script res://tools/build/build_bgm.gd

const Synth := preload("res://tools/lib/audio_synth.gd")
const Mixer := preload("res://tools/lib/audio_mixer.gd")

const OUT_DIR: String = "res://assets/audio/bgm"
## 渲染时多留的尾巴：长音和混响的收尾折叠回开头，循环点才不会"咔"一声。
const TAIL_BEATS: float = 8.0
const REVERB_WET: float = 0.2
const REVERB_DECAY: float = 0.78
## 木吉他分解的弦序：低到高再回落的八分音符型。
const GUITAR_ORDER: Array[int] = [0, 2, 1, 3, 2, 3, 1, 2]
## 竖琴琶音型，比吉他更连贯，用来铺标题和夜晚。
const HARP_ORDER: Array[int] = [0, 1, 2, 3, 2, 3, 1, 2]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var jobs: Array[Dictionary] = [
		{"name": "menu", "score": _menu_score()},
		{"name": "farm_day", "score": _day_score()},
		{"name": "farm_night", "score": _night_score()},
	]
	var failed: bool = false
	for job in jobs:
		var name: String = String(job["name"])
		var channels: Array[PackedFloat32Array] = _render(job["score"])
		var path := "%s/%s.wav" % [OUT_DIR, name]
		var ok: bool = Mixer.write_stereo(path, channels[0], channels[1], true)
		if ok:
			print("[build_bgm] %s  %.1fs  %d frames  bpm=%d" % [
				path, float(channels[0].size()) / float(Synth.SAMPLE_RATE),
				channels[0].size(), int(job["score"]["bpm"]),
			])
		else:
			printerr("[build_bgm] 写入失败：%s" % path)
			failed = true
	print("[build_bgm] 完成")
	quit(1 if failed else 0)


# --------------------------------------------------------------------------
# 乐谱：farm_day —— G 大调，116 BPM，16 小节，主题 8 小节 + 回答 8 小节
# --------------------------------------------------------------------------

func _day_score() -> Dictionary:
	var score := _make_score(116.0, 16)
	var chords: Array[Dictionary] = [
		{"root": 43, "tones": [59, 62, 67, 71], "pad": [55, 59, 62]},   # G
		{"root": 48, "tones": [60, 64, 67, 72], "pad": [55, 60, 64]},   # C
		{"root": 43, "tones": [59, 62, 67, 71], "pad": [55, 59, 62]},   # G
		{"root": 50, "tones": [57, 62, 66, 69], "pad": [57, 62, 66]},   # D
		{"root": 40, "tones": [59, 64, 67, 71], "pad": [55, 59, 64]},   # Em
		{"root": 48, "tones": [60, 64, 67, 72], "pad": [55, 60, 64]},   # C
		{"root": 50, "tones": [57, 62, 66, 69], "pad": [57, 62, 66]},   # D
		{"root": 43, "tones": [59, 62, 67, 71], "pad": [55, 59, 62]},   # G
		{"root": 48, "tones": [60, 64, 67, 72], "pad": [55, 60, 64]},   # C
		{"root": 50, "tones": [57, 62, 66, 69], "pad": [57, 62, 66]},   # D
		{"root": 47, "tones": [59, 62, 66, 71], "pad": [54, 59, 62]},   # Bm
		{"root": 40, "tones": [59, 64, 67, 71], "pad": [55, 59, 64]},   # Em
		{"root": 48, "tones": [60, 64, 67, 72], "pad": [55, 60, 64]},   # C
		{"root": 50, "tones": [57, 62, 66, 69], "pad": [57, 62, 66]},   # D
		{"root": 43, "tones": [59, 62, 67, 71], "pad": [55, 59, 62]},   # G
		{"root": 43, "tones": [59, 62, 67, 71], "pad": [55, 59, 62]},   # G
	]
	for bar in chords.size():
		# 后 8 小节才铺弦乐，前半段留出空间给木吉他和木琴。
		_day_backing(score, bar, chords[bar], bar >= 8)
	_day_lead(score)
	# 白天曲拨弦多，混完收一下 4kHz 以上，避免一直"沙沙"响。
	score["tame"] = 0.4
	return score


## 木吉他分解 + 拨弦贝斯 + 沙锤，farm_day 的律动骨架。
func _day_backing(score: Dictionary, bar: int, chord: Dictionary, with_pad: bool) -> void:
	var beat: float = float(bar * 4)
	var root: int = int(chord["root"])
	var tones: Array = chord["tones"]
	# 低音在第 1、3 拍，第 3 拍走五度，听感更"走动"。
	_note(score, beat, 1.9, root, 0.4, &"pluck",
		{"damping": 0.9993, "bright": 0.2, "decay": 0.35, "release": 0.1})
	_note(score, beat + 2.0, 1.7, root + 7, 0.3, &"pluck",
		{"damping": 0.9993, "bright": 0.2, "decay": 0.5, "release": 0.1})
	# 吉他：八分音符分解，奇偶步做轻重，第 4、8 步挑高八度。
	# bright 压到 0.35：指腹拨弦的木质感，不要拨片那种"嚓"。
	for step in 8:
		var midi: int = int(tones[GUITAR_ORDER[step] % tones.size()])
		if step == 3 or step == 7:
			midi += 12
		var accent: float = 1.0 if step % 2 == 0 else 0.72
		_note(score, beat + float(step) * 0.5, 0.6, midi, 0.15 * accent, &"pluck",
			{"pan": -0.28, "bright": 0.3, "damping": 0.993, "release": 0.05})
	# 沙锤：只打反拍，短而暗。八分音符全铺会让整首曲子"沙沙"响。
	for step in 8:
		if step % 2 == 0:
			continue
		_note(score, beat + float(step) * 0.5, 0.09, 0, 0.03, &"shaker",
			{"pan": 0.35, "lowpass": 0.24, "highpass": 0.38, "decay": 42.0})
	if with_pad:
		for midi in chord["pad"]:
			_note(score, beat, 3.9, int(midi), 0.05, &"strings",
				{"attack": 0.32, "release": 0.5, "tone": 0.12})


## 主旋律：木琴领奏，后 8 小节叠手风琴三度，把"乡村乐队"的厚度做出来。
func _day_lead(score: Dictionary) -> void:
	var melody: Array[Array] = [
		[0.0, 1.0, 74], [1.0, 0.5, 71], [1.5, 0.5, 69], [2.0, 2.0, 67],
		[4.0, 1.0, 76], [5.0, 1.0, 74], [6.0, 2.0, 71],
		[8.0, 0.5, 67], [8.5, 0.5, 69], [9.0, 1.0, 71], [10.0, 1.0, 74], [11.0, 1.0, 76],
		[12.0, 2.0, 74], [14.0, 1.0, 71], [15.0, 1.0, 69],
		[16.0, 1.0, 67], [17.0, 1.0, 71], [18.0, 1.0, 74], [19.0, 1.0, 76],
		[20.0, 1.5, 74], [21.5, 0.5, 71], [22.0, 1.0, 69], [23.0, 1.0, 67],
		[24.0, 1.0, 69], [25.0, 1.0, 71], [26.0, 1.0, 69], [27.0, 1.0, 66],
		[28.0, 4.0, 67],
		[32.0, 1.0, 76], [33.0, 1.0, 74], [34.0, 1.0, 71], [35.0, 1.0, 74],
		[36.0, 1.0, 76], [37.0, 1.0, 78], [38.0, 1.0, 76], [39.0, 1.0, 74],
		[40.0, 1.0, 74], [41.0, 1.0, 71], [42.0, 1.0, 69], [43.0, 1.0, 71],
		[44.0, 2.0, 71], [46.0, 2.0, 67],
		[48.0, 0.5, 67], [48.5, 0.5, 69], [49.0, 1.0, 71], [50.0, 1.0, 74], [51.0, 1.0, 76],
		[52.0, 1.0, 74], [53.0, 1.0, 69], [54.0, 2.0, 71],
		[56.0, 0.5, 69], [56.5, 0.5, 71], [57.0, 1.0, 74], [58.0, 1.0, 76], [59.0, 1.0, 74],
		[60.0, 4.0, 67],
	]
	for item in melody:
		var beat: float = float(item[0])
		var beats: float = float(item[1])
		var midi: int = int(item[2])
		_note(score, beat, beats, midi, 0.24, &"fm",
			{"pan": 0.16, "ratio": 2.0, "index": 1.0, "index_decay": 3.2, "decay": 0.8,
			"attack": 0.004, "release": 0.14})
		# 附点八分后的轻回声，模拟木琴在谷仓里的反射。
		_note(score, beat + 0.75, beats * 0.7, midi, 0.07, &"fm",
			{"pan": -0.42, "ratio": 2.0, "index": 0.55, "index_decay": 3.6, "decay": 2.4,
			"release": 0.1})
		if beat >= 32.0:
			_note(score, beat, beats * 0.92, midi - 4, 0.085, &"reed",
				{"pan": -0.14, "attack": 0.07, "release": 0.22, "tone": 0.3, "detune": 0.0018})


# --------------------------------------------------------------------------
# 乐谱：menu —— C 大调，84 BPM，8 小节，竖琴铺底 + 暖钢琴主题
# --------------------------------------------------------------------------

func _menu_score() -> Dictionary:
	var score := _make_score(84.0, 8)
	var chords: Array[Dictionary] = [
		{"root": 48, "tones": [60, 64, 67, 72], "pad": [52, 55, 60]},   # C
		{"root": 45, "tones": [57, 60, 64, 69], "pad": [52, 57, 60]},   # Am
		{"root": 41, "tones": [53, 57, 60, 65], "pad": [48, 53, 57]},   # F
		{"root": 43, "tones": [55, 59, 62, 67], "pad": [50, 55, 59]},   # G
		{"root": 48, "tones": [60, 64, 67, 72], "pad": [52, 55, 60]},   # C
		{"root": 40, "tones": [59, 64, 67, 71], "pad": [52, 55, 59]},   # Em
		{"root": 41, "tones": [53, 57, 60, 65], "pad": [48, 53, 57]},   # F
		{"root": 43, "tones": [55, 59, 62, 67], "pad": [50, 55, 59]},   # G
	]
	for bar in chords.size():
		var beat: float = float(bar * 4)
		var tones: Array = chords[bar]["tones"]
		_note(score, beat, 3.6, int(chords[bar]["root"]), 0.27, &"pluck",
			{"damping": 0.9995, "bright": 0.2, "decay": 0.22, "release": 0.25})
		for step in 8:
			var midi: int = int(tones[HARP_ORDER[step] % tones.size()]) + 12
			var accent: float = 1.0 if step % 2 == 0 else 0.68
			_note(score, beat + float(step) * 0.5, 0.95, midi, 0.075 * accent, &"pluck",
				{"pan": -0.22, "bright": 0.5, "damping": 0.9965, "release": 0.16})
		for midi in chords[bar]["pad"]:
			_note(score, beat, 3.9, int(midi), 0.045, &"strings",
				{"attack": 0.45, "release": 0.6, "tone": 0.1})
	var melody: Array[Array] = [
		[0.0, 2.0, 72], [2.0, 1.0, 76], [3.0, 1.0, 79],
		[4.0, 2.0, 69], [6.0, 1.0, 72], [7.0, 1.0, 76],
		[8.0, 2.0, 77], [10.0, 1.0, 76], [11.0, 1.0, 74],
		[12.0, 3.0, 74], [15.0, 1.0, 71],
		[16.0, 1.0, 72], [17.0, 1.0, 76], [18.0, 1.0, 79], [19.0, 1.0, 84],
		[20.0, 2.0, 83], [22.0, 1.0, 79], [23.0, 1.0, 76],
		[24.0, 2.0, 81], [26.0, 1.0, 77], [27.0, 1.0, 81],
		[28.0, 4.0, 79],
	]
	for item in melody:
		_note(score, float(item[0]), float(item[1]), int(item[2]), 0.26, &"fm",
			{"pan": 0.12, "ratio": 1.0, "index": 0.45, "index_decay": 1.4, "decay": 1.0,
			"attack": 0.006, "release": 0.35, "vibrato_rate": 4.6, "vibrato_depth": 0.0025})
	return score


# --------------------------------------------------------------------------
# 乐谱：farm_night —— A 小调，62 BPM，8 小节，稀疏、留白、星空感
# --------------------------------------------------------------------------

func _night_score() -> Dictionary:
	var score := _make_score(62.0, 8)
	var chords: Array[Dictionary] = [
		{"root": 45, "tones": [57, 60, 64, 69], "pad": [57, 60, 64]},   # Am
		{"root": 41, "tones": [53, 57, 60, 64], "pad": [53, 57, 60]},   # Fmaj7
		{"root": 48, "tones": [52, 55, 59, 64], "pad": [52, 55, 59]},   # Cmaj7
		{"root": 43, "tones": [55, 59, 62, 67], "pad": [55, 59, 62]},   # G
		{"root": 45, "tones": [57, 60, 64, 69], "pad": [57, 60, 64]},   # Am
		{"root": 40, "tones": [52, 55, 59, 64], "pad": [52, 55, 59]},   # Em
		{"root": 41, "tones": [53, 57, 60, 65], "pad": [53, 57, 60]},   # F
		{"root": 43, "tones": [55, 59, 62, 67], "pad": [55, 59, 62]},   # G
	]
	var sparkles: Array[int] = [88, 91, 93, 95]
	for bar in chords.size():
		var beat: float = float(bar * 4)
		var tones: Array = chords[bar]["tones"]
		_note(score, beat, 3.8, int(chords[bar]["root"]), 0.19, &"pluck",
			{"damping": 0.9996, "bright": 0.2, "decay": 0.16, "release": 0.35})
		# 竖琴只走四拍，音符拉长，让每一下都听得见尾音。
		for step in 4:
			var midi: int = int(tones[(step + bar) % tones.size()]) + 12
			_note(score, beat + float(step), 1.6, midi, 0.075, &"pluck",
				{"pan": -0.26, "bright": 0.52, "damping": 0.9984, "release": 0.3})
		for midi in chords[bar]["pad"]:
			_note(score, beat, 3.9, int(midi), 0.06, &"strings",
				{"attack": 0.9, "release": 0.9, "tone": 0.09})
		# 远处的一颗"星"：高音钟琴，随机落在小节里。
		_note(score, beat + float(sparkles[bar % sparkles.size()] % 3), 1.4,
			sparkles[bar % sparkles.size()], 0.05, &"fm",
			{"pan": 0.45, "ratio": 2.76, "index": 1.0, "index_decay": 2.2,
			"decay": 1.7, "release": 0.2})
	var melody: Array[Array] = [
		[0.0, 2.0, 76], [2.0, 1.0, 74], [3.0, 1.0, 72],
		[4.0, 2.0, 69], [6.0, 1.0, 72], [7.0, 1.0, 76],
		[8.0, 2.0, 74], [10.0, 1.0, 72], [11.0, 1.0, 71],
		[12.0, 4.0, 69],
		[16.0, 2.0, 76], [18.0, 1.0, 79], [19.0, 1.0, 76],
		[20.0, 2.0, 74], [22.0, 1.0, 71], [23.0, 1.0, 69],
		[24.0, 2.0, 72], [26.0, 1.0, 74], [27.0, 1.0, 76],
		[28.0, 4.0, 69],
	]
	for item in melody:
		_note(score, float(item[0]), float(item[1]), int(item[2]), 0.22, &"fm",
			{"pan": 0.1, "ratio": 1.0, "index": 0.38, "index_decay": 1.1, "decay": 0.62,
			"attack": 0.02, "release": 0.5, "vibrato_rate": 4.2, "vibrato_depth": 0.003})
	return score


# --------------------------------------------------------------------------
# 渲染与写出
# --------------------------------------------------------------------------

func _make_score(bpm: float, bars: int) -> Dictionary:
	return {"bpm": bpm, "bars": bars, "notes": []}


func _note(score: Dictionary, beat: float, beats: float, midi: int, amp: float,
		voice: StringName, opts: Dictionary = {}) -> void:
	var notes: Array = score["notes"]
	notes.append({
		"beat": beat,
		"beats": maxf(beats, 0.05),
		"midi": midi,
		"amp": amp,
		"voice": voice,
		"opts": opts,
	})


func _render(score: Dictionary) -> Array[PackedFloat32Array]:
	var beat_sec: float = 60.0 / float(score["bpm"])
	var frames: int = int(round(float(score["bars"]) * 4.0 * beat_sec * float(Synth.SAMPLE_RATE)))
	var tail: int = int(round(TAIL_BEATS * beat_sec * float(Synth.SAMPLE_RATE)))
	var left: PackedFloat32Array = Synth.make_buffer(frames + tail)
	var right: PackedFloat32Array = Synth.make_buffer(frames + tail)

	var notes: Array = score["notes"]
	for entry in notes:
		var note: Dictionary = entry
		var start: int = int(round(float(note["beat"]) * beat_sec * float(Synth.SAMPLE_RATE)))
		var length: int = maxi(int(round(float(note["beats"]) * beat_sec * float(Synth.SAMPLE_RATE))), 1)
		var amp: float = float(note["amp"])
		var opts: Dictionary = note["opts"]
		var freq: float = _midi_to_freq(int(note["midi"]))
		match StringName(note["voice"]):
			&"pluck":
				Synth.pluck(left, right, start, length, freq, amp, opts)
			&"fm":
				Synth.fm_tone(left, right, start, length, freq, amp, opts)
			&"wind":
				Synth.wind(left, right, start, length, freq, amp, opts)
			&"reed":
				Synth.reed(left, right, start, length, freq, amp, opts)
			&"strings":
				Synth.strings(left, right, start, length, freq, amp, opts)
			&"shaker":
				Synth.noise_hit(left, right, start, length, amp, opts)
			&"thump":
				Synth.thump(left, right, start, length, amp, opts)
			_:
				push_warning("[build_bgm] 未知音色：%s" % note["voice"])

	Mixer.reverb(left, right, REVERB_WET, REVERB_DECAY)
	# 尾巴折回开头：循环播放时尾音正好接上下一遍的起头。
	for i in tail:
		left[i] += left[frames + i]
		right[i] += right[frames + i]
	left.resize(frames)
	right.resize(frames)
	Mixer.tame_highs(left, right, float(score.get("tame", 0.0)))
	Mixer.remove_dc(left, right)
	Mixer.limit_stereo(left, right, 1.05)
	Mixer.normalize_stereo(left, right, 0.94)
	var channels: Array[PackedFloat32Array] = [left, right]
	return channels


func _midi_to_freq(midi: int) -> float:
	return 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)
