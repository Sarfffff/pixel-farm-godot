extends RefCounted
## 离线音频合成内核：把乐器音色渲染进左右声道工作缓冲。
##
## `tools/build/build_bgm.gd`（音乐）和 `tools/build/build_sfx.gd`（音效）共用本文件，
## 保证游戏里所有声音出自同一套音色，听感统一成"木质 + 自然 + 温暖"的农场基调：
##   拨弦 Karplus-Strong  木吉他 / 竖琴 / 班卓 / 贝斯
##   FM 音色              木琴 / 钢片琴 / 钟琴 / 暖钢琴
##   簧片、木管、弦乐垫   手风琴 / 竖笛 / 弦乐铺底
##   噪声打击、低频冲击   沙锤 / 木块 / 脚步 / 落地
##
## 采样率固定 44100Hz，缓冲是 32 位浮点；混响、限幅、WAV 编码在 `audio_mixer.gd`。
##
## 用法：
##   var left := AudioSynth.make_buffer(frames)
##   var right := AudioSynth.make_buffer(frames)
##   AudioSynth.pluck(left, right, start, length, 220.0, 0.3, {"pan": -0.3})

const SAMPLE_RATE: int = 44100
const INV_SAMPLE_RATE: float = 1.0 / 44100.0


static func make_buffer(frames: int) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(maxi(frames, 1))
	return buffer


## 等功率声像：pan=-1 全左，0 居中，1 全右。
static func pan_gains(pan: float) -> Vector2:
	var p: float = clampf(pan, -1.0, 1.0)
	return Vector2(sqrt(0.5 * (1.0 - p)), sqrt(0.5 * (1.0 + p)))


# --------------------------------------------------------------------------
# 拨弦：Karplus-Strong 延迟线
#   opts: pan 声像 / damping 反馈衰减（越大尾音越长）/ bright 起始亮度
#         decay 额外指数衰减（1/秒）/ attack 起音秒 / release 收音秒
# --------------------------------------------------------------------------

static func pluck(left: PackedFloat32Array, right: PackedFloat32Array,
		start: int, length: int, freq: float, amp: float, opts: Dictionary = {}) -> void:
	if freq <= 0.0 or amp <= 0.0:
		return
	var count: int = mini(length, left.size() - start)
	if count <= 0:
		return
	var gains: Vector2 = pan_gains(float(opts.get("pan", 0.0)))
	var gain_l: float = amp * gains.x
	var gain_r: float = amp * gains.y
	var damping: float = clampf(float(opts.get("damping", 0.996)), 0.8, 0.99999)
	var bright: float = clampf(float(opts.get("bright", 0.45)), 0.02, 1.0)
	var extra_decay: float = maxf(float(opts.get("decay", 0.0)), 0.0)
	var attack: int = maxi(int(float(opts.get("attack", 0.002)) * float(SAMPLE_RATE)), 1)
	var release: int = maxi(int(float(opts.get("release", 0.04)) * float(SAMPLE_RATE)), 1)
	var period: int = maxi(int(round(float(SAMPLE_RATE) / freq)), 2)

	# 激励：一段低通过的白噪声，越亮越接近拨片，越暗越接近指腹。
	var line := PackedFloat32Array()
	line.resize(period)
	var smoothed: float = 0.0
	var loudest: float = 0.0
	for i in period:
		smoothed = lerpf(smoothed, randf() * 2.0 - 1.0, bright)
		line[i] = smoothed
		loudest = maxf(loudest, absf(smoothed))
	if loudest > 0.00001:
		var inv: float = 1.0 / loudest
		for i in period:
			line[i] *= inv

	var index: int = 0
	for i in count:
		var current: float = line[index]
		var following: float = line[(index + 1) % period]
		# 半周期平均当成一阶低通：高频先消失，尾音留下木质的中低频。
		line[index] = (current + following) * 0.5 * damping
		var env: float = 1.0
		if i < attack:
			env = float(i) / float(attack)
		var remain: int = count - i
		if remain < release:
			env *= float(remain) / float(release)
		if extra_decay > 0.0:
			env *= exp(-extra_decay * float(i) * INV_SAMPLE_RATE)
		var sample: float = current * env
		left[start + i] += sample * gain_l
		right[start + i] += sample * gain_r
		index += 1
		if index >= period:
			index = 0


# --------------------------------------------------------------------------
# FM 音色：木琴、钢片琴、钟琴、暖钢琴
#   opts: ratio 调制比 / index 调制深度 / index_decay 深度衰减 / decay 振幅衰减
#         attack / release / vibrato_rate / vibrato_depth / pan
# --------------------------------------------------------------------------

static func fm_tone(left: PackedFloat32Array, right: PackedFloat32Array,
		start: int, length: int, freq: float, amp: float, opts: Dictionary = {}) -> void:
	if freq <= 0.0 or amp <= 0.0:
		return
	var count: int = mini(length, left.size() - start)
	if count <= 0:
		return
	var gains: Vector2 = pan_gains(float(opts.get("pan", 0.0)))
	var gain_l: float = amp * gains.x
	var gain_r: float = amp * gains.y
	var ratio: float = maxf(float(opts.get("ratio", 1.0)), 0.01)
	var depth: float = maxf(float(opts.get("index", 1.0)), 0.0)
	var depth_decay: float = maxf(float(opts.get("index_decay", 1.5)), 0.0)
	var decay: float = maxf(float(opts.get("decay", 2.5)), 0.01)
	var attack: int = maxi(int(float(opts.get("attack", 0.003)) * float(SAMPLE_RATE)), 1)
	var release: int = maxi(int(float(opts.get("release", 0.05)) * float(SAMPLE_RATE)), 1)
	var vib_rate: float = maxf(float(opts.get("vibrato_rate", 0.0)), 0.0)
	var vib_depth: float = maxf(float(opts.get("vibrato_depth", 0.0)), 0.0)

	var inc: float = freq * INV_SAMPLE_RATE
	var mod_inc: float = inc * ratio
	var phase: float = 0.0
	var mod_phase: float = 0.0
	var vib_phase: float = 0.0
	for i in count:
		var t: float = float(i) * INV_SAMPLE_RATE
		var bend: float = 1.0
		if vib_depth > 0.0:
			bend += vib_depth * sin(TAU * vib_phase) * minf(t * 3.0, 1.0)
		var current_depth: float = depth * exp(-depth_decay * t)
		var mod: float = sin(TAU * mod_phase) * current_depth
		var sample: float = sin(TAU * (phase + mod))
		var env: float = exp(-decay * t)
		if i < attack:
			env *= float(i) / float(attack)
		var remain: int = count - i
		if remain < release:
			env *= float(remain) / float(release)
		sample *= env
		left[start + i] += sample * gain_l
		right[start + i] += sample * gain_r
		phase += inc * bend
		mod_phase += mod_inc * bend
		vib_phase += vib_rate * INV_SAMPLE_RATE


# --------------------------------------------------------------------------
# 木管（竖笛 / 长笛）：基音 + 少量谐波 + 气声，慢起音、晚到的颤音
# --------------------------------------------------------------------------

static func wind(left: PackedFloat32Array, right: PackedFloat32Array,
		start: int, length: int, freq: float, amp: float, opts: Dictionary = {}) -> void:
	if freq <= 0.0 or amp <= 0.0:
		return
	var count: int = mini(length, left.size() - start)
	if count <= 0:
		return
	var gains: Vector2 = pan_gains(float(opts.get("pan", 0.0)))
	var gain_l: float = amp * gains.x
	var gain_r: float = amp * gains.y
	var attack_s: float = maxf(float(opts.get("attack", 0.055)), 0.001)
	var release_s: float = maxf(float(opts.get("release", 0.08)), 0.001)
	var breath: float = maxf(float(opts.get("breath", 0.02)), 0.0)
	var harmonics: float = maxf(float(opts.get("harmonics", 0.22)), 0.0)
	var vib_rate: float = maxf(float(opts.get("vibrato_rate", 5.2)), 0.0)
	var vib_depth: float = maxf(float(opts.get("vibrato_depth", 0.006)), 0.0)
	var decay: float = maxf(float(opts.get("decay", 0.0)), 0.0)
	var attack: int = maxi(int(attack_s * float(SAMPLE_RATE)), 1)
	var release: int = maxi(int(release_s * float(SAMPLE_RATE)), 1)

	var inc: float = freq * INV_SAMPLE_RATE
	var phase: float = 0.0
	var vib_phase: float = 0.0
	var breath_state: float = 0.0
	for i in count:
		var t: float = float(i) * INV_SAMPLE_RATE
		var bend: float = 1.0 + vib_depth * sin(TAU * vib_phase) * minf(t * 3.5, 1.0)
		var sample: float = (
			sin(TAU * phase)
			+ harmonics * sin(TAU * phase * 2.0)
			+ harmonics * 0.35 * sin(TAU * phase * 3.0)
		)
		breath_state = lerpf(breath_state, randf() * 2.0 - 1.0, 0.4)
		sample += breath_state * breath
		var env: float = 1.0
		if i < attack:
			env = float(i) / float(attack)
		var remain: int = count - i
		if remain < release:
			env *= float(remain) / float(release)
		if decay > 0.0:
			env *= exp(-decay * t)
		sample *= env
		left[start + i] += sample * gain_l
		right[start + i] += sample * gain_r
		phase += inc * bend
		vib_phase += vib_rate * INV_SAMPLE_RATE


# --------------------------------------------------------------------------
# 簧片（手风琴 / 簧风琴）：锯齿主体 + 一阶低通，两个略失谐的簧片
# --------------------------------------------------------------------------

static func reed(left: PackedFloat32Array, right: PackedFloat32Array,
		start: int, length: int, freq: float, amp: float, opts: Dictionary = {}) -> void:
	if freq <= 0.0 or amp <= 0.0:
		return
	var count: int = mini(length, left.size() - start)
	if count <= 0:
		return
	var gains: Vector2 = pan_gains(float(opts.get("pan", 0.0)))
	var gain_l: float = amp * gains.x
	var gain_r: float = amp * gains.y
	var attack_s: float = maxf(float(opts.get("attack", 0.07)), 0.001)
	var release_s: float = maxf(float(opts.get("release", 0.12)), 0.001)
	var detune: float = clampf(float(opts.get("detune", 0.0012)), 0.0, 0.02)
	var tone: float = clampf(float(opts.get("tone", 0.35)), 0.01, 1.0)
	var vib_rate: float = maxf(float(opts.get("vibrato_rate", 4.4)), 0.0)
	var vib_depth: float = maxf(float(opts.get("vibrato_depth", 0.004)), 0.0)
	var attack: int = maxi(int(attack_s * float(SAMPLE_RATE)), 1)
	var release: int = maxi(int(release_s * float(SAMPLE_RATE)), 1)

	var inc_a: float = freq * (1.0 - detune) * INV_SAMPLE_RATE
	var inc_b: float = freq * (1.0 + detune) * INV_SAMPLE_RATE
	var phase_a: float = 0.0
	var phase_b: float = 0.37
	var vib_phase: float = 0.0
	var filtered: float = 0.0
	for i in count:
		var t: float = float(i) * INV_SAMPLE_RATE
		var bend: float = 1.0 + vib_depth * sin(TAU * vib_phase) * minf(t * 3.0, 1.0)
		var saw_a: float = 2.0 * (phase_a - floor(phase_a)) - 1.0
		var saw_b: float = 2.0 * (phase_b - floor(phase_b)) - 1.0
		var raw: float = saw_a * 0.62 + saw_b * 0.38
		filtered = lerpf(filtered, raw, tone)
		var sample: float = filtered
		var env: float = 1.0
		if i < attack:
			env = float(i) / float(attack)
		var remain: int = count - i
		if remain < release:
			env *= float(remain) / float(release)
		sample *= env
		left[start + i] += sample * gain_l
		right[start + i] += sample * gain_r
		phase_a += inc_a * bend
		phase_b += inc_b * bend
		if phase_a >= 1.0:
			phase_a -= 1.0
		if phase_b >= 1.0:
			phase_b -= 1.0
		vib_phase += vib_rate * INV_SAMPLE_RATE


# --------------------------------------------------------------------------
# 弦乐垫：三个失谐锯齿 + 低通 + 很慢的起音，用来铺底不抢旋律
# --------------------------------------------------------------------------

static func strings(left: PackedFloat32Array, right: PackedFloat32Array,
		start: int, length: int, freq: float, amp: float, opts: Dictionary = {}) -> void:
	if freq <= 0.0 or amp <= 0.0:
		return
	var count: int = mini(length, left.size() - start)
	if count <= 0:
		return
	var gains: Vector2 = pan_gains(float(opts.get("pan", 0.0)))
	var gain_l: float = amp * gains.x
	var gain_r: float = amp * gains.y
	var attack_s: float = maxf(float(opts.get("attack", 0.35)), 0.001)
	var release_s: float = maxf(float(opts.get("release", 0.4)), 0.001)
	var tone: float = clampf(float(opts.get("tone", 0.1)), 0.01, 1.0)
	var detune: float = clampf(float(opts.get("detune", 0.004)), 0.0, 0.03)
	var attack: int = maxi(int(attack_s * float(SAMPLE_RATE)), 1)
	var release: int = maxi(int(release_s * float(SAMPLE_RATE)), 1)

	var inc_a: float = freq * (1.0 - detune) * INV_SAMPLE_RATE
	var inc_b: float = freq * INV_SAMPLE_RATE
	var inc_c: float = freq * (1.0 + detune) * INV_SAMPLE_RATE
	var phase_a: float = 0.11
	var phase_b: float = 0.47
	var phase_c: float = 0.79
	var filtered: float = 0.0
	for i in count:
		var saw_a: float = 2.0 * (phase_a - floor(phase_a)) - 1.0
		var saw_b: float = 2.0 * (phase_b - floor(phase_b)) - 1.0
		var saw_c: float = 2.0 * (phase_c - floor(phase_c)) - 1.0
		var raw: float = (saw_a + saw_b + saw_c) * 0.3333
		filtered = lerpf(filtered, raw, tone)
		var env: float = 1.0
		if i < attack:
			env = sin(float(i) / float(attack) * PI * 0.5)
		var remain: int = count - i
		if remain < release:
			env *= float(remain) / float(release)
		var sample: float = filtered * env
		left[start + i] += sample * gain_l
		right[start + i] += sample * gain_r
		phase_a += inc_a
		phase_b += inc_b
		phase_c += inc_c
		if phase_a >= 1.0:
			phase_a -= 1.0
		if phase_b >= 1.0:
			phase_b -= 1.0
		if phase_c >= 1.0:
			phase_c -= 1.0


# --------------------------------------------------------------------------
# 噪声打击：沙锤、木屑、土块、布料摩擦
#   opts: lowpass 低通 / highpass 高通 / decay 衰减 / attack / sweep 低通随时间开合
# --------------------------------------------------------------------------

static func noise_hit(left: PackedFloat32Array, right: PackedFloat32Array,
		start: int, length: int, amp: float, opts: Dictionary = {}) -> void:
	if amp <= 0.0:
		return
	var count: int = mini(length, left.size() - start)
	if count <= 0:
		return
	var gains: Vector2 = pan_gains(float(opts.get("pan", 0.0)))
	var gain_l: float = amp * gains.x
	var gain_r: float = amp * gains.y
	var lowpass: float = clampf(float(opts.get("lowpass", 0.45)), 0.001, 1.0)
	var highpass: float = clampf(float(opts.get("highpass", 0.0)), 0.0, 0.98)
	var decay: float = maxf(float(opts.get("decay", 12.0)), 0.05)
	var attack_s: float = maxf(float(opts.get("attack", 0.001)), 0.0001)
	var attack: int = maxi(int(attack_s * float(SAMPLE_RATE)), 1)
	var sweep: float = float(opts.get("sweep", 0.0))

	var body: float = 0.0
	var shelf: float = 0.0
	for i in count:
		var t: float = float(i) * INV_SAMPLE_RATE
		var cutoff: float = clampf(lowpass * (1.0 + sweep * sin(PI * minf(t * 6.0, 1.0))), 0.001, 1.0)
		body = lerpf(body, randf() * 2.0 - 1.0, cutoff)
		var sample: float = body
		if highpass > 0.0:
			shelf = lerpf(shelf, body, highpass)
			sample = body - shelf
		var env: float = exp(-decay * t)
		if i < attack:
			env *= float(i) / float(attack)
		sample *= env
		left[start + i] += sample * gain_l
		right[start + i] += sample * gain_r


# --------------------------------------------------------------------------
# 低频冲击：脚步落地、锄头入土、木箱落地
#   opts: from_hz 起始频率 / to_hz 终止频率 / decay 衰减 / click 起音噪声量
# --------------------------------------------------------------------------

static func thump(left: PackedFloat32Array, right: PackedFloat32Array,
		start: int, length: int, amp: float, opts: Dictionary = {}) -> void:
	if amp <= 0.0:
		return
	var count: int = mini(length, left.size() - start)
	if count <= 0:
		return
	var gains: Vector2 = pan_gains(float(opts.get("pan", 0.0)))
	var gain_l: float = amp * gains.x
	var gain_r: float = amp * gains.y
	var from_hz: float = maxf(float(opts.get("from_hz", 140.0)), 10.0)
	var to_hz: float = maxf(float(opts.get("to_hz", 60.0)), 10.0)
	var decay: float = maxf(float(opts.get("decay", 16.0)), 0.05)
	var click: float = maxf(float(opts.get("click", 0.0)), 0.0)
	var attack: int = maxi(int(0.0015 * float(SAMPLE_RATE)), 1)

	var phase: float = 0.0
	var click_state: float = 0.0
	for i in count:
		var t: float = float(i) * INV_SAMPLE_RATE
		var progress: float = clampf(t * 30.0, 0.0, 1.0)
		var freq_now: float = lerpf(from_hz, to_hz, progress)
		var sample: float = sin(TAU * phase)
		if click > 0.0:
			click_state = lerpf(click_state, randf() * 2.0 - 1.0, 0.5)
			sample += click_state * click * exp(-decay * 3.0 * t)
		var env: float = exp(-decay * t)
		if i < attack:
			env *= float(i) / float(attack)
		sample *= env
		left[start + i] += sample * gain_l
		right[start + i] += sample * gain_r
		phase += freq_now * INV_SAMPLE_RATE
		if phase >= 1.0:
			phase -= 1.0
