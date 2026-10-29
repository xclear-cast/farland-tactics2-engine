class_name FT2APDPlayer
extends RefCounted

signal step_event(event_id: int, indirect: bool, marker: int)
static var _next_pool_order = 0
var pool_order = 0

var apd: Dictionary = {}
var label: String = ""
var steps: Array = []
var frame: int = -1
var ordinal: int = 0
var flags: int = 0
var mirror: bool = false
var flip_y: bool = false
var offset: Vector2i = Vector2i.ZERO
var busy: bool = false
var visible: bool = true
var dither: int = 0
var base_flip: int = 0
var state_mode: int = 0
var static_flip: int = 0
var dither_busy = false
var _dither_increasing = false
var _dither_interval = 0
var _dither_epoch = 0
var _step: int = 0
var _epoch: int = 0
var _started: bool = false
var _group: int = 0
var _within: int = 0
var _accum: int = 0
var _base: Vector2i = Vector2i.ZERO

func _init() -> void:
	pool_order = _next_pool_order
	_next_pool_order += 1

func play(dataset: Dictionary, requested: String, now: int, play_flags: int = 1, idle_hash_policy: bool = false) -> bool:
	var candidate = normalize(dataset)
	var names: Dictionary = candidate.get("animations", {})
	var lookup: Dictionary = {}
	for name in names:
		lookup[str(name).to_upper()] = name
	requested = str(lookup.get(requested.to_upper(),requested.to_upper()))
	var wants_mirror = (play_flags & 16) != 0
	var used_hash = false
	if lookup.has((requested+"#").to_upper()) and (idle_hash_policy or (wants_mirror and lookup.has(requested.to_upper()))):
		requested = str(lookup[(requested+"#").to_upper()])
		wants_mirror = false
		used_hash = true
	if not names.has(requested):
		if apd.is_empty():
			apd = candidate
		return false
	apd = candidate
	flags = play_flags&~16 if used_hash else play_flags
	flags = flags&~1 if play_flags&128 else flags
	label = requested
	mirror = wants_mirror
	steps.clear()
	var base = Vector2i.ZERO
	for group in names[label].groups:
		var elapsed = 0
		for raw in group.steps:
			var velocity = group.velocity
			steps.append({"frame":int(raw[0]),"ms":int(raw[1]),"flip":int(raw[2]),"event":int(raw[3]),"indirect":bool(raw[4]),"marker":int(raw[5]),"move":base + Vector2i(int(float(velocity[0]) * elapsed), int(float(velocity[1]) * elapsed))})
			elapsed += int(raw[1])
		base += Vector2i(int(group.move[0]), int(group.move[1]))
	_step = 0
	_group = 0
	_within = 0
	_accum = 0
	_base = Vector2i.ZERO
	ordinal = 0
	_epoch = 0
	_started = false
	busy = not steps.is_empty() and (play_flags & 1) != 0
	state_mode = 2
	# Native42DF04..DF41: one sequence, one step, zero M is static mode4,
	# immediately idle even when its authored duration is nonzero.
	var groups: Array = names[label].groups
	if groups.size() == 1 and groups[0].steps.size() == 1 and int(groups[0].move[0]) == 0 and int(groups[0].move[1]) == 0:
		state_mode = 4
		busy = false
	_apply()
	return not steps.is_empty()

static func normalize(dataset: Dictionary) -> Dictionary:
	if dataset.has("part_crops"):
		var compact = dataset.duplicate()
		compact.erase("part_crops")
		compact["parts"] = []
		compact["frames"] = []
		compact["sheets"] = []
		for sheet in dataset.get("sheets",[]):
			compact.sheets.append("sprite/"+str(sheet.declared_name).to_lower())
		for part in dataset.part_crops:
			compact.parts.append([part.sheet,part.x,part.y,part.w,part.h,part.ox,part.oy,part.transparent_palette_index])
		for frame in dataset.get("frames",[]):
			compact.frames.append({"parts":frame.part_indices_in_draw_order,"pivot":int(frame.header_words_raw[2]),"bounds":frame.get("bounds_relative_anchor_xyxy",[0,0,0,0])})
		return normalize(compact)
	var names: Dictionary = dataset.get("animations",{})
	if names.is_empty():
		return dataset
	var sample: Dictionary = names.values()[0]
	if sample.has("groups") and (sample.groups.is_empty() or sample.groups[0].has("velocity")):
		return dataset
	var result = dataset.duplicate()
	result["animations"] = {}
	for name in names:
		var groups: Array = []
		for group in names[name].get("compiled_groups",[]):
			var converted: Array = []
			for step in group.get("steps",[]):
				converted.append([int(step.get("image_frame",step.get("image",-1))),int(step.get("duration_ms",step.get("ms",0))),int(step.get("draw_flags",step.get("flags",0))),int(step.get("sound_event_id",step.get("event",-1))),int(step.get("sound_event_indirect",step.get("indirect",0))),int(step.get("action_marker",step.get("marker",0)))])
			groups.append({"move":group.get("move_total_xy",[0,0]),"velocity":group.get("compiled_sequence_velocity_per_ms",group.get("velocity_float32",[0,0])),"steps":converted})
		result.animations[name] = {"groups":groups}
	return result

func _apply() -> void:
	if steps.is_empty():
		frame = -1
		return
	var s: Dictionary = steps[_step]
	frame = int(s.frame)
	offset = s.move
	flip_y = (int(s.flip) & 2) != 0
	if int(s.event) >= 0 or int(s.marker) != 0:
		step_event.emit(int(s.event), bool(s.indirect), int(s.marker))

func advance(now: int) -> bool:
	var dither_changed = advance_dither(now)
	if state_mode != 2 or not busy or (flags&1) == 0 or steps.is_empty():
		return dither_changed
	if not _started or _epoch == 0:
		_epoch = now
		_started = true
		return true
	if ((_epoch + int(steps[_step].ms)) & 0xFFFFFFFF) > (now & 0xFFFFFFFF):
		return dither_changed
	# Original42E710 advances once, then uses now as the new epoch: no catch-up loop.
	_epoch = now
	var groups: Array = apd.animations[label].groups
	var old: Dictionary = groups[_group]
	_within += 1
	if _within >= old.steps.size():
		_group += 1
		if _group >= groups.size():
			if flags & 2:
				_group = 0
				_step = 0
				#42E998 resets ordinal, then42E93D increments it for the selected first step.
				ordinal = 1
				if (flags&64) == 0: _base = Vector2i.ZERO
				_base += Vector2i(int(old.move[0]),int(old.move[1]))
				_base = Vector2i(wrapi(_base.x,-32768,32768),wrapi(_base.y,-32768,32768))
				_accum = 0
				_within = 0
				_apply()
				offset = _base
				if mirror: offset.x = -offset.x
				if flags&32: offset.y = -offset.y
				return true
			busy = false
			flags &= ~1
			_epoch = 0
			_started = false
			return dither_changed
		_base += Vector2i(int(old.move[0]),int(old.move[1]))
		_base = Vector2i(wrapi(_base.x,-32768,32768),wrapi(_base.y,-32768,32768))
		_within = 0
		_accum = 0
	else:
		_accum += int(old.steps[_within][1])
	_step += 1
	ordinal += 1
	_apply()
	var group: Dictionary = groups[_group]
	offset = _base + Vector2i(int(float(group.velocity[0])*_accum),int(float(group.velocity[1])*_accum))
	#42E7C3/42E83E mirror both authored M motion and raster orientation.
	if mirror:
		offset.x = -offset.x
	if flags&32:
		offset.y = -offset.y
	offset = Vector2i(wrapi(offset.x,-32768,32768),wrapi(offset.y,-32768,32768))
	return true

func activate(value: int = 1) -> void:
	if (state_mode&2) == 0:
		return
	if value&128:
		flags &= 126
	else:
		flags |= value
	busy = (flags&1) != 0

func set_static_frame(index: int, flip: int = 0) -> void:
	if index < 0 or index >= apd.get("frames",[]).size():
		return
	frame = index
	state_mode = 1
	static_flip = flip
	flags = 0 #42DE2B: selecting a raw image clears animation flags, including stale128.
	busy = false

func fade_dither(increasing: bool, interval: int, now: int) -> void:
	_dither_increasing = increasing
	_dither_interval = interval & 0xFFFFFFFF #42E421 stores a DWORD interval.
	_dither_epoch = now
	dither_busy = true

func advance_dither(now: int) -> bool:
	if not dither_busy or (now & 0xFFFFFFFF) <= ((_dither_epoch+_dither_interval)&0xFFFFFFFF):
		return false
	_dither_epoch = now
	var next = dither+(1 if _dither_increasing else -1)
	if next < 0 or next > 8:
		dither_busy = false
		return false
	dither = next
	return true

func effective_flip() -> int:
	if state_mode == 1:
		return static_flip^base_flip
	if steps.is_empty():
		return int(mirror)^base_flip
	return int(mirror) ^ int(steps[_step].flip)^base_flip^(2 if flags&32 else 0)
