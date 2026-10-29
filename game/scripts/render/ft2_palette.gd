class_name FT2Palette
extends RefCounted

var base: PackedByteArray
var current: PackedByteArray
var texture: ImageTexture
var dirty: bool = true
var _fade_from: PackedByteArray
var _fade_to: PackedByteArray
var _start: int = 0
var _count: int = 0
var _interval: int = 0
var _epoch: int = 0
var fading: bool = false
var progress: int = 128

func _init() -> void:
	base.resize(768)
	base.fill(0)
	current = base.duplicate()
	_fade_from = base.duplicate()
	_fade_to = base.duplicate()
	# Original Windows reserved palette indices are copied from source image palettes.

func install(source: PackedByteArray, start: int = 0, count: int = 256) -> void:
	for i in range(start * 3, mini((start + count) * 3, mini(source.size(), 768))):
		base[i] = source[i]
		current[i] = source[i]
		_fade_from[i] = source[i]
		_fade_to[i] = source[i]
	dirty = true

func install_base(source: PackedByteArray, start: int, count: int) -> void:
	#417E10 updates45A7B8 only. Hardware/current and fade start/target remain
	# unchanged until the caller invokes4180D0/SetEntries.
	for i in range(start*3,mini((start+count)*3,mini(source.size(),768))): base[i] = source[i]

func fade(target: PackedByteArray, start: int, count: int, interval: int, now: int) -> void:
	#4180D0 copies PREVIOUS TARGET, not the intermediate hardware palette.
	for i in range(start*3,mini((start+count)*3,768)):
		_fade_from[i] = _fade_to[i]
		_fade_to[i] = base[i] if target.is_empty() else target[i]
	_start = start
	_count = count
	_interval = interval & 0xFFFF
	_epoch = now
	fading = true
	progress = 0
	if _interval == 0:
		progress = 128
		for i in range(start*3,mini((start+count)*3,768)):
			_fade_from[i] = _fade_to[i]
			current[i] = _fade_to[i]
		fading = false
		dirty = true

func brightness(first: int, count: int, percent: int, interval: int, now: int) -> void:
	var target = base.duplicate()
	for i in range(first * 3, mini((first + count) * 3, 768)):
		target[i] = int(float(int(base[i])*percent)/100.0)&255
	fade(target, first, count, interval, now)

func advance(now: int) -> void:
	if not fading:
		return
	progress = 128 if _interval == 0 else mini(128, int(((now - _epoch)&0xFFFFFFFF) / _interval) & 0xFFFF)
	#417F60 interpolates all nonreserved entries, even when only one band changed.
	for i in range(10*3,246*3):
		var delta = int(_fade_to[i]) - int(_fade_from[i])
		current[i] = int(_fade_from[i]) + int(float(delta * progress) / 128.0)
	fading = progress >= 0 and progress < 128
	if not fading:
		_fade_from = _fade_to.duplicate()
	dirty = true

func upload() -> ImageTexture:
	if texture == null or dirty:
		var img = Image.create_from_data(256, 1, false, Image.FORMAT_RGB8, current)
		if texture == null:
			texture = ImageTexture.create_from_image(img)
		else:
			texture.update(img)
		dirty = false
	return texture
