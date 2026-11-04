extends SceneTree
## 操作音效生成器
## 离线合成一组原创短音效（无第三方素材），写成 22050Hz / 16bit / 单声道 WAV：
##   hoe      锄地：低频闷响 + 一点土块噪声
##   water    浇水：低通噪声的水流声
##   plant    播种：两声轻点
##   harvest  收获：三个上行短音
##   chop     砍树：木质冲击
##   mine     碎石：碎裂噪声 + 高频
##   coin     金币：两声叮当
##   ui       界面点击：极短提示音
##   sleep    入睡：柔和下行三音
##
## 运行方式：
##   godot --headless --path e:/my-ai-game --script res://tools/build/build_sfx.gd

const SAMPLE_RATE: int = 22050
const OUT_DIR: String = "res://assets/audio/sfx"
const PEAK: float = 0.82


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var jobs: Array[Dictionary] = [
		{"name": "hoe", "samples": _hoe()},
		{"name": "water", "samples": _water()},
		{"name": "plant", "samples": _plant()},
		{"name": "harvest", "samples": _harvest()},
		{"name": "chop", "samples": _chop()},
		{"name": "mine", "samples": _mine()},
		{"name": "coin", "samples": _coin()},
		{"name": "ui", "samples": _ui()},
		{"name": "sleep", "samples": _sleep()},
	]
	var failed := false
	for job in jobs:
		var name: String = String(job[&"name"])
		var data: PackedFloat32Array = _normalize(job[&"samples"], PEAK)
		var path := "%s/%s.wav" % [OUT_DIR, name]
		if _write_wav(path, data):
			print("[build_sfx] %s  %.2fs  %d samples" % [path, float(data.size()) / SAMPLE_RATE, data.size()])
		else:
			printerr("[build_sfx] 写入失败：%s" % path)
			failed = true
	print("[build_sfx] 完成")
	quit(1 if failed else 0)


# --------------------------------------------------------------------------
# 音效
# --------------------------------------------------------------------------

func _hoe() -> PackedFloat32Array:
	var buf := _buffer(0.20)
	_tone(buf, 0.0, 0.18, 120.0, 70.0, 0.75, 5.0)
	_noise(buf, 0.0, 0.07, 0.35, 8.0, 0.25)
	return buf


func _water() -> PackedFloat32Array:
	var buf := _buffer(0.38)
	_noise(buf, 0.0, 0.36, 0.35, 2.2, 0.12)
	_tone(buf, 0.02, 0.30, 520.0, 380.0, 0.12, 3.0)
	return buf


func _plant() -> PackedFloat32Array:
	var buf := _buffer(0.22)
	_noise(buf, 0.0, 0.05, 0.30, 10.0, 0.40)
	_noise(buf, 0.08, 0.05, 0.24, 10.0, 0.40)
	_tone(buf, 0.0, 0.10, 320.0, 260.0, 0.18, 6.0)
	return buf


func _harvest() -> PackedFloat32Array:
	var buf := _buffer(0.30)
	_tone(buf, 0.0, 0.09, 660.0, 660.0, 0.35, 4.0)
	_tone(buf, 0.07, 0.09, 880.0, 880.0, 0.35, 4.0)
	_tone(buf, 0.14, 0.13, 1046.0, 1046.0, 0.40, 3.0)
	return buf


func _chop() -> PackedFloat32Array:
	var buf := _buffer(0.24)
	_tone(buf, 0.0, 0.20, 160.0, 90.0, 0.70, 6.0)
	_noise(buf, 0.0, 0.09, 0.40, 9.0, 0.30)
	return buf


func _mine() -> PackedFloat32Array:
	var buf := _buffer(0.22)
	_noise(buf, 0.0, 0.16, 0.50, 7.0, 0.60)
	_tone(buf, 0.0, 0.14, 1250.0, 900.0, 0.30, 7.0)
	return buf


func _coin() -> PackedFloat32Array:
	var buf := _buffer(0.34)
	_tone(buf, 0.0, 0.10, 1318.5, 1318.5, 0.40, 5.0)
	_tone(buf, 0.06, 0.22, 1760.0, 1760.0, 0.42, 3.5)
	return buf


func _ui() -> PackedFloat32Array:
	var buf := _buffer(0.08)
	_tone(buf, 0.0, 0.06, 1800.0, 1500.0, 0.30, 9.0)
	return buf


func _sleep() -> PackedFloat32Array:
	var buf := _buffer(0.62)
	_tone(buf, 0.0, 0.22, 523.0, 523.0, 0.30, 2.4)
	_tone(buf, 0.16, 0.22, 392.0, 392.0, 0.30, 2.4)
	_tone(buf, 0.32, 0.28, 294.0, 294.0, 0.32, 2.0)
	return buf


# --------------------------------------------------------------------------
# 合成工具
# --------------------------------------------------------------------------

func _buffer(duration: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(maxi(int(duration * SAMPLE_RATE), 1))
	return buf


## 叠加一段带指数衰减的正弦，频率从 f0 线性滑到 f1。
func _tone(
	buf: PackedFloat32Array, start: float, duration: float, f0: float, f1: float, amp: float, decay: float
) -> void:
	var from := int(start * SAMPLE_RATE)
	var count := maxi(int(duration * SAMPLE_RATE), 1)
	var phase := 0.0
	for i in count:
		var progress := float(i) / float(count)
		phase += TAU * lerpf(f0, f1, progress) / float(SAMPLE_RATE)
		var index := from + i
		if index < 0 or index >= buf.size():
			continue
		buf[index] += sin(phase) * amp * exp(-decay * progress)


## 叠加一段衰减噪声；lowpass 越大越闷。
func _noise(
	buf: PackedFloat32Array, start: float, duration: float, amp: float, decay: float, lowpass: float = 0.0
) -> void:
	var from := int(start * SAMPLE_RATE)
	var count := maxi(int(duration * SAMPLE_RATE), 1)
	var last := 0.0
	for i in count:
		var white := randf() * 2.0 - 1.0
		if lowpass > 0.0:
			last = lerpf(last, white, lowpass)
			white = last
		var index := from + i
		if index < 0 or index >= buf.size():
			continue
		var progress := float(i) / float(count)
		buf[index] += white * amp * exp(-decay * progress)


## 把峰值缩放到指定大小，避免削波也避免太轻。
func _normalize(samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var loudest := 0.0
	for value in samples:
		loudest = maxf(loudest, absf(value))
	if loudest <= 0.0001:
		return samples
	var scale := peak / loudest
	var out := PackedFloat32Array()
	out.resize(samples.size())
	for i in samples.size():
		out[i] = samples[i] * scale
	return out


# --------------------------------------------------------------------------
# WAV 写出（音效不需要循环块）
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
	fmt.encode_u16(0, 1)                       # PCM
	fmt.encode_u16(2, 1)                       # 单声道
	fmt.encode_u32(4, SAMPLE_RATE)
	fmt.encode_u32(8, SAMPLE_RATE * 2)         # byte rate
	fmt.encode_u16(12, 2)                      # block align
	fmt.encode_u16(14, 16)                     # bit depth

	var body := PackedByteArray()
	body.append_array(_chunk("fmt ", fmt))
	body.append_array(_chunk("data", pcm))

	var out := PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	out.append_array(_le32(4 + body.size()))
	out.append_array("WAVE".to_ascii_buffer())
	out.append_array(body)
	return out


func _chunk(tag: String, payload: PackedByteArray) -> PackedByteArray:
	var chunk := PackedByteArray()
	chunk.append_array(tag.to_ascii_buffer())
	chunk.append_array(_le32(payload.size()))
	chunk.append_array(payload)
	return chunk


func _le32(value: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_u32(0, value)
	return bytes
