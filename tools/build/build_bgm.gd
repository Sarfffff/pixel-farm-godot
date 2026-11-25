extends SceneTree
## 背景音乐生成器
##
## 三首原创循环曲：指弹木吉他、毡音钢琴与轻木管。
## 白天舒缓明亮、夜晚安静留白、标题温暖期待。
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
const REVERB_WET: float = 0.14
const REVERB_DECAY: float = 0.72
const GUITAR_ORDER: Array[int] = [0, 2, 1, 3]
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
		seed(hash(name))
		var channels: Array[PackedFloat32Array] = _render(job["score"])
		var path: String = "%s/%s.wav" % [OUT_DIR, name]
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
# 乐谱：farm_day —— G 大调，78 BPM，16 小节，主题与回答
# --------------------------------------------------------------------------

func _day_score() -> Dictionary:
	var score: Dictionary = _make_score(78.0, 16)
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
		_day_backing(score, bar, chords[bar], bar >= 8)
	_day_lead(score)
	score["tame"] = 0.28
	score["rms"] = 0.12
	return score


func _day_backing(score: Dictionary, bar: int, chord: Dictionary, with_pad: bool) -> void:
	var beat: float = float(bar * 4)
	var root: int = int(chord["root"])
	var tones: Array = chord["tones"]
	_note(score, beat, 3.8, root + 12, 0.14, &"pluck",
		{"damping": 0.9992, "bright": 0.12, "attack": 0.012, "decay": 0.7, "release": 0.3})
	for step in 4:
		var midi: int = int(tones[GUITAR_ORDER[step] % tones.size()])
		var accent: float = 1.0 if step % 2 == 0 else 0.76
		var offset: float = 0.018 if step % 2 == 1 else 0.0
		_note(score, beat + float(step) + offset, 1.6, midi, 0.11 * accent, &"pluck",
			{"pan": -0.2, "bright": 0.14, "damping": 0.997, "attack": 0.009, "release": 0.22})
	if with_pad:
		for midi in chord["pad"]:
			_note(score, beat + 0.1, 3.8, int(midi), 0.018, &"wind",
				{"attack": 0.65, "release": 0.8, "harmonics": 0.06, "breath": 0.002,
				"vibrato_depth": 0.001, "decay": 0.18})


func _day_lead(score: Dictionary) -> void:
	var melody: Array[Array] = [
		[0.5, 1.5, 67], [2.5, 1.0, 71],
		[4.5, 1.5, 72], [6.5, 1.0, 67],
		[8.5, 1.0, 69], [10.0, 1.5, 71],
		[12.5, 2.5, 69],
		[16.5, 1.5, 67], [18.5, 1.0, 71],
		[20.5, 2.0, 72],
		[24.5, 1.5, 69], [26.5, 1.0, 66], [28.5, 2.5, 67],
		[32.5, 1.5, 72], [34.5, 1.0, 76],
		[36.5, 1.5, 74], [38.5, 1.0, 69],
		[40.5, 1.5, 71], [42.5, 1.0, 66],
		[44.5, 2.5, 67],
		[48.5, 1.0, 67], [50.0, 1.5, 72],
		[52.5, 1.5, 69], [54.5, 1.0, 66],
		[56.5, 1.5, 71], [58.5, 1.0, 69], [60.5, 2.5, 67],
	]
	for item in melody:
		var beat: float = float(item[0])
		var beats: float = float(item[1])
		var midi: int = int(item[2])
		_note(score, beat, beats, midi, 0.15, &"fm",
			{"pan": 0.12, "ratio": 1.0, "index": 0.28, "index_decay": 3.0,
			"decay": 1.5, "attack": 0.018, "release": 0.3})
		if beat >= 32.0 and midi <= 72:
			_note(score, beat + 0.04, beats * 0.8, midi, 0.025, &"wind",
				{"pan": 0.22, "attack": 0.12, "release": 0.3, "harmonics": 0.08,
				"breath": 0.003, "vibrato_depth": 0.002, "decay": 0.5})


# --------------------------------------------------------------------------
# 乐谱：menu —— C 大调，72 BPM，16 小节，指弹与毡音钢琴
# --------------------------------------------------------------------------

func _menu_score() -> Dictionary:
	var score: Dictionary = _make_score(72.0, 16)
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
	for bar in 16:
		var chord: Dictionary = chords[bar % chords.size()]
		var beat: float = float(bar * 4)
		var tones: Array = chord["tones"]
		_note(score, beat, 3.8, int(chord["root"]), 0.1, &"fm",
			{"ratio": 1.0, "index": 0.18, "decay": 0.9, "attack": 0.025, "release": 0.5})
		for step in 4:
			var midi: int = int(tones[HARP_ORDER[(step + bar / 8) % HARP_ORDER.size()]])
			_note(score, beat + float(step) + 0.03, 1.8, midi, 0.075, &"pluck",
				{"pan": -0.18, "bright": 0.12, "damping": 0.998, "attack": 0.014, "release": 0.35})
		for midi in chord["pad"]:
			_note(score, beat + 0.06, 3.8, int(midi), 0.045, &"fm",
				{"pan": 0.16, "ratio": 1.0, "index": 0.16, "decay": 1.1,
				"attack": 0.04, "release": 0.5})
	var melody: Array[Array] = [
		[0.5, 2.0, 64], [3.0, 0.75, 67], [4.5, 2.5, 69],
		[8.5, 1.5, 65], [10.5, 1.0, 64], [12.5, 2.5, 62],
		[16.5, 1.5, 64], [18.5, 1.0, 67], [20.5, 2.5, 71],
		[24.5, 1.5, 69], [26.5, 1.0, 65], [28.5, 2.5, 67],
		[32.5, 1.5, 67], [34.5, 1.0, 72], [36.5, 2.5, 69],
		[40.5, 1.5, 65], [42.5, 1.0, 69], [44.5, 2.5, 67],
		[48.5, 1.5, 64], [50.5, 1.0, 67], [52.5, 2.5, 64],
		[56.5, 1.5, 65], [58.5, 1.0, 64], [60.5, 2.5, 62],
	]
	for item in melody:
		_note(score, float(item[0]), float(item[1]), int(item[2]), 0.16, &"fm",
			{"pan": 0.1, "ratio": 1.0, "index": 0.22, "index_decay": 2.0, "decay": 1.2,
			"attack": 0.022, "release": 0.45})
	score["tame"] = 0.26
	score["rms"] = 0.12
	return score


# --------------------------------------------------------------------------
# 乐谱：farm_night —— C 大调，56 BPM，16 小节，暖钢琴与轻木管
# --------------------------------------------------------------------------

func _night_score() -> Dictionary:
	var score: Dictionary = _make_score(56.0, 16)
	var chords: Array[Dictionary] = [
		{"root": 48, "tones": [60, 64, 67, 71]},
		{"root": 45, "tones": [57, 60, 64, 67]},
		{"root": 41, "tones": [53, 57, 60, 64]},
		{"root": 43, "tones": [55, 59, 62, 67]},
		{"root": 48, "tones": [60, 64, 67, 71]},
		{"root": 40, "tones": [52, 55, 59, 64]},
		{"root": 41, "tones": [53, 57, 60, 64]},
		{"root": 43, "tones": [55, 59, 62, 67]},
	]
	for bar in 16:
		var chord: Dictionary = chords[bar % chords.size()]
		var beat: float = float(bar * 4)
		var tones: Array = chord["tones"]
		_note(score, beat, 3.8, int(chord["root"]), 0.09, &"fm",
			{"ratio": 1.0, "index": 0.12, "decay": 0.85, "attack": 0.035, "release": 0.7})
		for step in 2:
			var midi: int = int(tones[(step * 2 + bar / 8) % tones.size()])
			_note(score, beat + float(step * 2) + 0.05, 2.8, midi, 0.06, &"fm",
				{"pan": -0.16, "ratio": 1.0, "index": 0.14, "decay": 1.0,
				"attack": 0.03, "release": 0.6})
		if bar % 2 == 1:
			_note(score, beat + 1.0, 2.5, int(tones[2]), 0.024, &"wind",
				{"pan": 0.2, "attack": 0.45, "release": 0.7, "harmonics": 0.04,
				"breath": 0.001, "vibrato_depth": 0.0015, "decay": 0.3})
	var melody: Array[Array] = [
		[0.75, 2.0, 64], [4.75, 2.0, 60], [8.75, 2.0, 65], [12.75, 2.0, 62],
		[16.75, 1.5, 67], [18.75, 1.0, 64], [20.75, 2.0, 59],
		[24.75, 2.0, 60], [28.75, 2.0, 62],
		[32.75, 2.0, 67], [36.75, 2.0, 64], [40.75, 2.0, 65],
		[44.75, 1.5, 67], [46.75, 1.0, 62], [48.75, 2.0, 64],
		[52.75, 2.0, 59], [56.75, 2.0, 60], [60.75, 2.0, 62],
	]
	for item in melody:
		_note(score, float(item[0]), float(item[1]), int(item[2]), 0.11, &"fm",
			{"pan": 0.08, "ratio": 1.0, "index": 0.16, "index_decay": 1.6,
			"decay": 0.85, "attack": 0.035, "release": 0.6})
	score["tame"] = 0.22
	score["rms"] = 0.1
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
	Mixer.tame_highs(left, right, float(score.get("tame", 0.26)))
	Mixer.remove_dc(left, right)
	for i in tail:
		left[i] += left[frames + i]
		right[i] += right[frames + i]
	left.resize(frames)
	right.resize(frames)
	Mixer.limit_stereo(left, right, 1.0)
	Mixer.balance_stereo(left, right, float(score.get("rms", 0.12)), 0.65)
	var channels: Array[PackedFloat32Array] = [left, right]
	return channels


func _midi_to_freq(midi: int) -> float:
	return 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)
