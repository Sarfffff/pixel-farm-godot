extends RefCounted
## 离线混音与导出：混响、软限幅、归一化，以及 WAV（PCM 16bit，可选 smpl 循环块）。
##
## 与 `audio_synth.gd` 配套使用：
##   AudioMixer.reverb(left, right, 0.24, 0.84)
##   AudioMixer.limit_stereo(left, right, 1.25)
##   AudioMixer.normalize_stereo(left, right, 0.89)
##   AudioMixer.write_stereo("res://assets/audio/bgm/menu.wav", left, right, true)

const SAMPLE_RATE: int = 44100
const COMB_DELAYS: Array[int] = [1557, 1617, 1491, 1422]
const ALLPASS_DELAYS: Array[int] = [225, 556]
## 右声道混响的推送延迟（帧）：太小没有宽度，太大听起来像两个房间。
const WIDTH_DELAY: int = 61


## Schroeder 混响（4 梳状 + 2 全通），原地叠加到左右声道。
## decay 是梳状反馈系数，0.7 左右是"小木屋"，0.85 是"山谷"。
static func reverb(left: PackedFloat32Array, right: PackedFloat32Array,
		wet: float = 0.22, decay: float = 0.8) -> void:
	var frames: int = mini(left.size(), right.size())
	if frames <= 0 or wet <= 0.0:
		return
	var feedback: float = clampf(decay, 0.3, 0.94)
	var source := PackedFloat32Array()
	source.resize(frames)
	for i in frames:
		source[i] = (left[i] + right[i]) * 0.5

	var summed := PackedFloat32Array()
	summed.resize(frames)
	for delay: int in COMB_DELAYS:
		var line := PackedFloat32Array()
		line.resize(delay)
		var cursor: int = 0
		var damped: float = 0.0
		for i in frames:
			var delayed: float = line[cursor]
			# 反馈端串一点低通，避免混响越积越亮、变成金属味。
			damped = lerpf(damped, delayed, 0.34)
			line[cursor] = source[i] + damped * feedback
			summed[i] += delayed * 0.25
			cursor += 1
			if cursor >= delay:
				cursor = 0

	for delay: int in ALLPASS_DELAYS:
		var line := PackedFloat32Array()
		line.resize(delay)
		var cursor: int = 0
		for i in frames:
			var delayed: float = line[cursor]
			var out: float = -summed[i] + delayed
			line[cursor] = summed[i] + delayed * 0.5
			summed[i] = out
			cursor += 1
			if cursor >= delay:
				cursor = 0

	var tail := PackedFloat32Array()
	tail.resize(WIDTH_DELAY)
	var tail_cursor: int = 0
	for i in frames:
		var mono_wet: float = summed[i] * wet
		var right_wet: float = tail[tail_cursor] * wet
		tail[tail_cursor] = summed[i]
		tail_cursor += 1
		if tail_cursor >= WIDTH_DELAY:
			tail_cursor = 0
		left[i] = clampf(left[i] + mono_wet, -1.4, 1.4)
		right[i] = clampf(right[i] + right_wet, -1.4, 1.4)


## 高频收敛：两级一阶低通，把 4kHz 以上的"沙沙"压下去，只留木头的暖。
## amount 越小越暗：0.5 约 5.6kHz，0.4 约 3.6kHz，0.3 约 2.5kHz。
static func tame_highs(left: PackedFloat32Array, right: PackedFloat32Array, amount: float = 0.4) -> void:
	if amount <= 0.0:
		return
	var a: float = clampf(amount, 0.01, 0.95)
	var frames: int = mini(left.size(), right.size())
	var left_stage1: float = 0.0
	var left_stage2: float = 0.0
	var right_stage1: float = 0.0
	var right_stage2: float = 0.0
	for i in frames:
		left_stage1 = lerpf(left_stage1, left[i], a)
		left_stage2 = lerpf(left_stage2, left_stage1, a)
		right_stage1 = lerpf(right_stage1, right[i], a)
		right_stage2 = lerpf(right_stage2, right_stage1, a)
		left[i] = left_stage2
		right[i] = right_stage2


## 一阶高通去直流：多层音色叠加后整体会偏一点，不去掉喇叭会一直往外推。
static func remove_dc(left: PackedFloat32Array, right: PackedFloat32Array) -> void:
	var frames: int = mini(left.size(), right.size())
	var state_l: float = 0.0
	var state_r: float = 0.0
	var last_l: float = 0.0
	var last_r: float = 0.0
	for i in frames:
		var x_l: float = left[i]
		var x_r: float = right[i]
		state_l = x_l - last_l + 0.9995 * state_l
		state_r = x_r - last_r + 0.9995 * state_r
		last_l = x_l
		last_r = x_r
		left[i] = state_l
		right[i] = state_r


## 立体声工作缓冲混成单声道：音效用，省一半文件体积。
static func mix_down(left: PackedFloat32Array, right: PackedFloat32Array) -> PackedFloat32Array:
	var frames: int = mini(left.size(), right.size())
	var mono := PackedFloat32Array()
	mono.resize(frames)
	for i in frames:
		mono[i] = (left[i] + right[i]) * 0.5
	return mono


## 温和软限幅：把接近满刻度的峰值压圆，保留瞬态。
static func limit_stereo(left: PackedFloat32Array, right: PackedFloat32Array, drive: float = 1.15) -> void:
	for i in mini(left.size(), right.size()):
		left[i] = tanh(left[i] * drive)
		right[i] = tanh(right[i] * drive)


static func normalize_stereo(left: PackedFloat32Array, right: PackedFloat32Array, peak: float = 0.89) -> void:
	var loudest: float = 0.0
	for i in left.size():
		loudest = maxf(loudest, absf(left[i]))
	for i in right.size():
		loudest = maxf(loudest, absf(right[i]))
	if loudest <= 0.0001:
		return
	var gain: float = peak / loudest
	for i in left.size():
		left[i] *= gain
	for i in right.size():
		right[i] *= gain


static func normalize_mono(buffer: PackedFloat32Array, peak: float = 0.92) -> void:
	var loudest: float = 0.0
	for value in buffer:
		loudest = maxf(loudest, absf(value))
	if loudest <= 0.0001:
		return
	var gain: float = peak / loudest
	for i in buffer.size():
		buffer[i] *= gain


## 单声道输入转成立体声：给音效做轻微宽度，避免全部挤在中间。
static func mono_to_stereo(buffer: PackedFloat32Array) -> Array[PackedFloat32Array]:
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(buffer.size())
	right.resize(buffer.size())
	for i in buffer.size():
		left[i] = buffer[i]
		right[i] = buffer[i]
	var channels: Array[PackedFloat32Array] = [left, right]
	return channels


# --------------------------------------------------------------------------
# WAV 输出
# --------------------------------------------------------------------------

static func write_stereo(path: String, left: PackedFloat32Array, right: PackedFloat32Array,
		loop: bool = false) -> bool:
	var frames: int = mini(left.size(), right.size())
	var pcm := PackedByteArray()
	pcm.resize(frames * 4)
	for i in frames:
		pcm.encode_s16(i * 4, _to_s16(left[i]))
		pcm.encode_s16(i * 4 + 2, _to_s16(right[i]))
	return _store(path, _wav_bytes(pcm, 2, frames, loop))


static func write_mono(path: String, buffer: PackedFloat32Array, loop: bool = false) -> bool:
	var frames: int = buffer.size()
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	for i in frames:
		pcm.encode_s16(i * 2, _to_s16(buffer[i]))
	return _store(path, _wav_bytes(pcm, 1, frames, loop))


static func _store(path: String, bytes: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return true


static func _to_s16(value: float) -> int:
	return int(round(clampf(value, -1.0, 1.0) * 32767.0))


static func _wav_bytes(pcm: PackedByteArray, channels: int, frames: int, loop: bool) -> PackedByteArray:
	var fmt := PackedByteArray()
	fmt.resize(16)
	fmt.encode_u16(0, 1)                                   # PCM
	fmt.encode_u16(2, channels)
	fmt.encode_u32(4, SAMPLE_RATE)
	fmt.encode_u32(8, SAMPLE_RATE * channels * 2)          # byte rate
	fmt.encode_u16(12, channels * 2)                       # block align
	fmt.encode_u16(14, 16)                                 # bit depth

	var body := PackedByteArray()
	body.append_array(_chunk("fmt ", fmt))
	if loop:
		body.append_array(_chunk("smpl", _smpl_chunk(frames)))
	body.append_array(_chunk("data", pcm))

	var out := PackedByteArray()
	out.resize(12)
	out.encode_u32(0, 0x46464952)                          # "RIFF"
	out.encode_u32(4, 4 + body.size())
	out.encode_u32(8, 0x45564157)                          # "WAVE"
	out.append_array(body)
	return out


## smpl 循环块：整段首尾相接，Godot 导入后可自动循环。
static func _smpl_chunk(frames: int) -> PackedByteArray:
	var smpl := PackedByteArray()
	smpl.resize(60)
	smpl.encode_u32(0, 0)                                  # manufacturer
	smpl.encode_u32(4, 0)                                  # product
	smpl.encode_u32(8, int(round(1_000_000_000.0 / float(SAMPLE_RATE))))
	smpl.encode_u32(12, 60)                                # unity note
	smpl.encode_u32(16, 0)                                 # pitch fraction
	smpl.encode_u32(20, 0)                                 # smpte format
	smpl.encode_u32(24, 0)                                 # smpte offset
	smpl.encode_u32(28, 1)                                 # 循环数量
	smpl.encode_u32(32, 0)                                 # sampler data
	smpl.encode_u32(36, 0)                                 # loop id
	smpl.encode_u32(40, 0)                                 # 0 = 正向
	smpl.encode_u32(44, 0)                                 # loop start
	smpl.encode_u32(48, maxi(frames - 1, 0))               # loop end（含）
	smpl.encode_u32(52, 0)                                 # fraction
	smpl.encode_u32(56, 0)                                 # play count 0 = 无限
	return smpl


static func _chunk(tag: String, payload: PackedByteArray) -> PackedByteArray:
	var chunk := PackedByteArray()
	chunk.resize(8)
	chunk.encode_u32(0, tag.to_utf8_buffer().decode_u32(0))
	chunk.encode_u32(4, payload.size())
	chunk.append_array(payload)
	if payload.size() % 2 == 1:
		chunk.append(0)
	return chunk
