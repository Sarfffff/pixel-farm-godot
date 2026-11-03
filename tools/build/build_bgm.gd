extends SceneTree
## 背景音乐生成器
##
## 用简易波表合成器离线渲染三首原创循环曲（无第三方版权素材）：
##   menu      —— 标题界面，C 大调，慢速温暖
##   farm_day  —— 农场白天，C 大调，轻快分解和弦 + 铃声旋律
##   farm_night—— 农场夜里，A 小调，稀疏铃声 + 长垫音
##
## 每首都是整小节长度，所有音符尾音按缓冲区长度取模写入，因此首尾无缝循环；
## 生成的 WAV 里写入 smpl 循环块，Godot 导入时即可自动循环。
##
## 运行方式：
##   godot --headless --path e:/my-ai-game --script res://tools/build/build_bgm.gd

const SAMPLE_RATE: int = 22050
const TABLE_SIZE: int = 2048
const OUT_DIR: String = "res://assets/audio/bgm"
const PEAK: float = 0.9

var _tables: Dictionary = {}
## 当前渲染的缓冲区（成员变量而非参数，避免 Packed 数组传值的拷贝语义）
var _buffer: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	_build_tables()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var jobs: Array[Dictionary] = [
		{"name": "menu", "score": _menu_score()},
		{"name": "farm_day", "score": _day_score()},
		{"name": "farm_night", "score": _night_score()},
	]
	for job in jobs:
		var name: String = job.name
		var score: Dictionary = job.score
		var buffer: PackedFloat32Array = _render(score)
		var path := "%s/%s.wav" % [OUT_DIR, name]
		if _write_wav(path, buffer):
			print("[build_bgm] %s  %.1fs  %d samples  bpm=%d" % [
				path, float(buffer.size()) / float(SAMPLE_RATE), buffer.size(), int(score.bpm)
			])
		else:
			printerr("[build_bgm] 写入失败：%s" % path)
			quit(1)
			return
	print("[build_bgm] 完成")
	quit(0)


# --------------------------------------------------------------------------
# 乐谱
# --------------------------------------------------------------------------

func _day_score() -> Dictionary:
	# C - G - Am - F | C - G - F - C
	var prog: Array[Dictionary] = [
		{"root": 36, "arp": [60, 64, 67, 72], "pad": [60, 64, 67]},
		{"root": 43, "arp": [59, 62, 67, 71], "pad": [59, 62, 67]},
		{"root": 45, "arp": [57, 60, 64, 69], "pad": [57, 60, 64]},
		{"root": 41, "arp": [53, 57, 60, 65], "pad": [53, 57, 60]},
		{"root": 36, "arp": [60, 64, 67, 72], "pad": [60, 64, 67]},
		{"root": 43, "arp": [59, 62, 67, 71], "pad": [59, 62, 67]},
		{"root": 41, "arp": [53, 57, 60, 65], "pad": [53, 57, 60]},
		{"root": 36, "arp": [60, 64, 67, 72], "pad": [60, 64, 67]},
	]
	var melody: Array[Array] = [
		[0.0, 1.0, 72], [1.0, 1.0, 76], [2.0, 2.0, 79],
		[4.0, 1.0, 77], [5.0, 1.0, 74], [6.0, 1.0, 71], [7.0, 1.0, 74],
		[8.0, 2.0, 69], [10.0, 1.0, 72], [11.0, 1.0, 76],
		[12.0, 1.0, 77], [13.0, 1.0, 76], [14.0, 2.0, 74],
		[16.0, 1.0, 79], [17.0, 1.0, 76], [18.0, 2.0, 72],
		[20.0, 1.0, 71], [21.0, 1.0, 74], [22.0, 2.0, 79],
		[24.0, 1.0, 81], [25.0, 1.0, 79], [26.0, 1.0, 77], [27.0, 1.0, 76],
		[28.0, 2.0, 74], [30.0, 2.0, 72],
	]
	return _assemble(96.0, prog, melody)


func _night_score() -> Dictionary:
	# Am - F - C - G | Am - Em - F - G
	var prog: Array[Dictionary] = [
		{"root": 45, "arp": [57, 60, 64, 69], "pad": [57, 60, 64]},
		{"root": 41, "arp": [53, 57, 60, 65], "pad": [53, 57, 60]},
		{"root": 36, "arp": [55, 60, 64, 67], "pad": [55, 60, 64]},
		{"root": 43, "arp": [55, 59, 62, 67], "pad": [55, 59, 62]},
		{"root": 45, "arp": [57, 60, 64, 69], "pad": [57, 60, 64]},
		{"root": 40, "arp": [52, 55, 59, 64], "pad": [52, 55, 59]},
		{"root": 41, "arp": [53, 57, 60, 65], "pad": [53, 57, 60]},
		{"root": 43, "arp": [55, 59, 62, 67], "pad": [55, 59, 62]},
	]
	var melody: Array[Array] = [
		[0.0, 2.0, 69], [2.0, 1.0, 72], [3.0, 1.0, 76],
		[4.0, 2.0, 77], [6.0, 2.0, 72],
		[8.0, 1.0, 76], [9.0, 1.0, 74], [10.0, 2.0, 72],
		[12.0, 4.0, 71],
		[16.0, 2.0, 69], [18.0, 1.0, 67], [19.0, 1.0, 69],
		[20.0, 2.0, 72], [22.0, 2.0, 71],
		[24.0, 1.0, 69], [25.0, 1.0, 67], [26.0, 2.0, 65],
		[28.0, 2.0, 64], [30.0, 2.0, 62],
	]
	var score := _assemble(66.0, prog, melody)
	# 夜里把整体做得更轻、更慢起音
	score.bar_overrides = {"bass_amp": 0.2, "arp_amp": 0.06, "pad_amp": 0.05, "attack": 0.5}
	return score


func _menu_score() -> Dictionary:
	# C - Am - F - G
	var prog: Array[Dictionary] = [
		{"root": 36, "arp": [60, 64, 67, 72], "pad": [60, 64, 67]},
		{"root": 45, "arp": [57, 60, 64, 69], "pad": [57, 60, 64]},
		{"root": 41, "arp": [53, 57, 60, 65], "pad": [53, 57, 60]},
		{"root": 43, "arp": [55, 59, 62, 67], "pad": [55, 59, 62]},
	]
	var melody: Array[Array] = [
		[0.0, 2.0, 79], [2.0, 2.0, 76],
		[4.0, 2.0, 81], [6.0, 2.0, 76],
		[8.0, 2.0, 77], [10.0, 2.0, 81],
		[12.0, 4.0, 79],
	]
	var score := _assemble(80.0, prog, melody)
	score.bar_overrides = {"bass_amp": 0.18, "arp_amp": 0.07, "pad_amp": 0.045, "attack": 0.4}
	return score


func _assemble(bpm: float, prog: Array[Dictionary], melody: Array[Array]) -> Dictionary:
	var notes: Array[Dictionary] = []
	for bar in prog.size():
		var chord: Dictionary = prog[bar]
		var beat: float = float(bar * 4)
		# 低音：1、3 拍
		_add_note(notes, beat, 1.6, chord.root, 0.26, &"tri", 0.01, 0.3)
		_add_note(notes, beat + 2.0, 1.2, chord.root, 0.2, &"tri", 0.01, 0.3)
		# 分解和弦：八分音符
		var arp: Array = chord.arp
		for step in 8:
			_add_note(notes, beat + float(step) * 0.5, 0.42, arp[step % arp.size()], 0.1, &"pluck", 0.006, 0.1)
		# 长垫音
		var pad: Array = chord.pad
		for midi in pad:
			_add_note(notes, beat, 3.9, midi, 0.035, &"organ", 0.35, 0.7)
	for note in melody:
		_add_note(notes, note[0], float(note[1]) * 0.95, note[2], 0.17, &"bell", 0.012, 0.18)
	return {
		"bpm": bpm,
		"bars": prog.size(),
		"notes": notes,
		"bar_overrides": {},
	}


func _add_note(notes: Array[Dictionary], beat: float, dur: float, midi: int, amp: float,
		wave: StringName, attack: float = 0.01, release: float = 0.1) -> void:
	notes.append({
		"beat": beat,
		"dur": maxf(dur, 0.05),
		"midi": midi,
		"amp": amp,
		"wave": wave,
		"attack": attack,
		"release": release,
	})


# --------------------------------------------------------------------------
# 合成
# --------------------------------------------------------------------------

func _build_tables() -> void:
	for kind in [&"sine", &"tri", &"pluck", &"bell", &"organ"]:
		var table := PackedFloat32Array()
		table.resize(TABLE_SIZE)
		for i in TABLE_SIZE:
			var x: float = TAU * float(i) / float(TABLE_SIZE)
			var v: float = 0.0
			match kind:
				&"sine":
					v = sin(x)
				&"tri":
					v = 2.0 / PI * asin(sin(x))
				&"pluck":
					v = sin(x) + 0.35 * sin(2.0 * x) + 0.12 * sin(3.0 * x)
				&"bell":
					v = sin(x) + 0.45 * sin(2.0 * x) + 0.24 * sin(3.0 * x) + 0.1 * sin(4.0 * x)
				&"organ":
					v = sin(x) + 0.32 * sin(3.0 * x) + 0.16 * sin(5.0 * x) + 0.07 * sin(7.0 * x)
			table[i] = v
		var peak: float = 0.0
		for i in TABLE_SIZE:
			peak = maxf(peak, absf(table[i]))
		if peak > 0.0:
			for i in TABLE_SIZE:
				table[i] = table[i] / peak
		_tables[kind] = table


func _render(score: Dictionary) -> PackedFloat32Array:
	var bpm: float = score.bpm
	var beat_sec: float = 60.0 / bpm
	var total_sec: float = float(score.bars) * 4.0 * beat_sec
	var total: int = int(round(total_sec * float(SAMPLE_RATE)))
	_buffer = PackedFloat32Array()
	_buffer.resize(total)

	var overrides: Dictionary = score.get("bar_overrides", {})
	for note in score.notes:
		var item: Dictionary = note.duplicate()
		if not overrides.is_empty():
			var wave: StringName = item.wave
			if wave == &"tri":
				item.amp = float(item.amp) * float(overrides.get("bass_amp", 0.26)) / 0.26
			elif wave == &"pluck":
				item.amp = float(item.amp) * float(overrides.get("arp_amp", 0.1)) / 0.1
			elif wave == &"organ":
				item.amp = float(item.amp) * float(overrides.get("pad_amp", 0.035)) / 0.035
				item.attack = float(overrides.get("attack", 0.35))
		_render_note(item, beat_sec)

	var peak: float = 0.0
	for i in total:
		peak = maxf(peak, absf(_buffer[i]))
	if peak > 0.0:
		var gain: float = PEAK / peak
		for i in total:
			_buffer[i] = clampf(_buffer[i] * gain, -1.0, 1.0)
	return _buffer


func _render_note(note: Dictionary, beat_sec: float) -> void:
	var total: int = _buffer.size()
	var start: int = int(round(float(note.beat) * beat_sec * float(SAMPLE_RATE))) % total
	var length: int = int(round(maxf(float(note.dur), 0.05) * beat_sec * float(SAMPLE_RATE)))
	if length <= 0:
		return
	var table: PackedFloat32Array = _tables[note.wave]
	var inc: float = _midi_to_freq(note.midi) * float(TABLE_SIZE) / float(SAMPLE_RATE)
	var amp: float = float(note.amp)
	var attack: int = maxi(1, int(float(note.attack) * float(SAMPLE_RATE)))
	var release: int = maxi(1, int(float(note.release) * float(SAMPLE_RATE)))
	# 轻微颤音，让长音不呆板
	var vibrato_inc: float = inc * 0.004
	var vibrato_rate: float = TAU * 5.0 / float(SAMPLE_RATE)
	var phase: float = 0.0
	var vib_phase: float = 0.0
	for i in length:
		var env: float = 1.0
		if i < attack:
			env = float(i) / float(attack)
		var remain: int = length - i
		if remain < release:
			env *= float(remain) / float(release)
		# 尾音按缓冲区取模，首尾自然衔接
		if i >= total:
			break
		var idx: int = int(phase) & (TABLE_SIZE - 1)
		var nxt: int = (idx + 1) & (TABLE_SIZE - 1)
		var frac: float = phase - floor(phase)
		var sample: float = table[idx] * (1.0 - frac) + table[nxt] * frac
		_buffer[(start + i) % total] += sample * amp * env
		phase += inc + sin(vib_phase) * vibrato_inc
		vib_phase += vibrato_rate


func _midi_to_freq(midi: int) -> float:
	return 440.0 * pow(2.0, (float(midi) - 69.0) / 12.0)


# --------------------------------------------------------------------------
# WAV 输出（PCM 16bit 单声道 + smpl 循环块）
# --------------------------------------------------------------------------

func _write_wav(path: String, samples: PackedFloat32Array) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(_wav_bytes(samples))
	file.close()
	return true


func _wav_bytes(samples: PackedFloat32Array) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i in samples.size():
		pcm.encode_s16(i * 2, int(round(clampf(samples[i], -1.0, 1.0) * 32767.0)))

	var fmt := PackedByteArray()
	fmt.resize(16)
	fmt.encode_u16(0, 1)                                  # PCM
	fmt.encode_u16(2, 1)                                  # 单声道
	fmt.encode_u32(4, SAMPLE_RATE)
	fmt.encode_u32(8, SAMPLE_RATE * 2)                    # byte rate
	fmt.encode_u16(12, 2)                                 # block align
	fmt.encode_u16(14, 16)                                # bit depth

	var smpl := PackedByteArray()
	smpl.resize(60)
	smpl.encode_u32(0, 0)                                 # manufacturer
	smpl.encode_u32(4, 0)                                 # product
	smpl.encode_u32(8, int(round(1_000_000_000.0 / float(SAMPLE_RATE))))
	smpl.encode_u32(12, 60)                               # unity note
	smpl.encode_u32(16, 0)                                # pitch fraction
	smpl.encode_u32(20, 0)                                # smpte format
	smpl.encode_u32(24, 0)                                # smpte offset
	smpl.encode_u32(28, 1)                                # 循环数量
	smpl.encode_u32(32, 0)                                # sampler data
	smpl.encode_u32(36, 0)                                # loop id
	smpl.encode_u32(40, 0)                                # 0 = 正向
	smpl.encode_u32(44, 0)                                # loop start
	smpl.encode_u32(48, samples.size() - 1)               # loop end（含）
	smpl.encode_u32(52, 0)                                # fraction
	smpl.encode_u32(56, 0)                                # play count 0 = 无限

	var body := PackedByteArray()
	body.append_array(_chunk("fmt ", fmt))
	body.append_array(_chunk("smpl", smpl))
	body.append_array(_chunk("data", pcm))

	var out := PackedByteArray()
	out.resize(12)
	out.encode_u32(0, 0x46464952)                         # "RIFF"（小端）
	out.encode_u32(4, 4 + body.size())
	out.encode_u32(8, 0x45564157)                         # "WAVE"
	out.append_array(body)
	return out


func _chunk(id: String, payload: PackedByteArray) -> PackedByteArray:
	var chunk := PackedByteArray()
	chunk.resize(8)
	chunk.encode_u32(0, id.to_utf8_buffer().decode_u32(0))
	chunk.encode_u32(4, payload.size())
	chunk.append_array(payload)
	# 偶数对齐
	if payload.size() % 2 == 1:
		chunk.append(0)
	return chunk
