class_name FT2PhysicalPlayback
extends RefCounted
##438590/439690: ordinal triggers precede the one-step APD clock.
signal finished
signal sound_requested(cache_index: int)
signal camera_focus_requested(focus: Vector2i)
signal cleanup_requested(record: Dictionary)
var assets: FT2IndexedAssets
var records: Array = []
var suppressed: Dictionary = {}
var active = false
var _by_id: Dictionary = {}
var _shared: Dictionary = {}
var _now = 0
var project_world: Callable
var native_wait_player: Callable
var _camera_index = 0
var _camera_mode = 1
var _camera_references: Dictionary = {}
var unsupported: Dictionary = {}

func configure(pack: FT2IndexedAssets) -> void:
	assets = pack

func play(program: Dictionary, now: int, actor_players: Dictionary = {}) -> bool:
	records.clear()
	_by_id.clear()
	_shared = actor_players
	suppressed.clear()
	_now = now
	_camera_index = int(program.get("start_record",0))
	_camera_mode = 1
	_camera_references = program.get("camera_references",{})
	for source in program.get("records",[]):
		var r: Dictionary = source.duplicate(true)
		r["record"] = int(r.get("record",records.size()))
		r["type"] = int(r.get("type",r.get("record_type",0)))
		r["state"] = int(r.get("state",2))
		r["command_index"] = 0
		r["prior_ordinals"] = 0
		r["child_cursor"] = 0
		r["sound_cursor"] = 0
		r["deleted"] = false
		var slot = int(r.get("unit_slot",-1)) if r.get("unit_slot") != null else -1
		r["unit_slot"] = slot
		if int(r.type) == 1 and _shared.has(slot):
			r["player"] = _shared[slot].player
		else:
			r["player"] = FT2APDPlayer.new()
		records.append(r)
		_by_id[int(r.record)] = r
	active = not records.is_empty()
	if active:
		_start(records[0])
	return active

func _start(r: Dictionary) -> void:
	if int(r.state) == 3:
		return
	r.state = 3
	r.command_index = 0
	if int(r.unit_slot) >= 0 and int(r.type) != 1: suppressed[int(r.unit_slot)] = true
	r["native_wait"] = (int(r.get("record_flags",0))&2) != 0
	if r.native_wait and native_wait_player.is_valid():
		r.player = native_wait_player.call(int(r.unit_slot))
		_select_command_camera(r)
	else:
		_play_command(r)
	#4388C3 selects type4 only on record start.439930 command advancement
	#may subsequently select mode2; it does not reapply this type check.
	if int(r.type) == 4:
		_camera_index = int(r.record)
		_camera_mode = 3
	_triggers(r)

func _play_command(r: Dictionary) -> void:
	if int(r.command_index) >= r.commands.size():
		return
	var command: Dictionary = r.commands[int(r.command_index)]
	var dataset = assets.apd(str(r.get("APD",r.get("apd",""))))
	var requested = command.get("label",command.get("resolved_label",command.get("label_buffer32","")))
	if requested is Array:
		if requested.size() > 1:
			dataset = assets.apd(str(requested[0])) if str(requested[0]) != "generated" else dataset
			requested = str(requested[1])
		else:
			requested = ""
	if command.has("compiled_groups") or command.has("groups"):
		var custom = dataset.duplicate()
		custom["animations"] = {"$program":{"compiled_groups":command.get("compiled_groups",command.get("groups",[]))}}
		dataset = FT2APDPlayer.normalize(custom)
		requested = "$program"
	var flags = int(command.get("flags",command.get("APD_flags",1)))
	r.player.play(dataset,str(requested),_now,flags)
	r.player.visible = true
	var slot = int(r.unit_slot)
	if slot >= 0 and int(r.type) != 1:
		suppressed[slot] = true
	_select_command_camera(r)

func _select_command_camera(r: Dictionary) -> void:
	if int(r.command_index) >= r.commands.size(): return
	var command: Dictionary = r.commands[int(r.command_index)]
	if (int(command.get("flags37",0))&2) != 0:
		_camera_index = int(r.record)
		_camera_mode = 2

func _triggers(r: Dictionary) -> void:
	for pair in [["child_triggers","child_cursor"],["sound_triggers","sound_cursor"]]:
		var triggers: Array = r.get(pair[0],[])
		var cursor = int(r[pair[1]])
		while cursor < triggers.size():
			if int(r.prior_ordinals)+int(r.player.ordinal) < int(triggers[cursor][0]):
				break
			if pair[0] == "child_triggers":
				var id = int(triggers[cursor][1])
				if _by_id.has(id):
					_start(_by_id[id])
			else:
				sound_requested.emit(int(triggers[cursor][1]))
			cursor += 1
			r[pair[1]] = cursor

func before_apd(now: int) -> void:
	_now = now
	if not active:
		return
	_update_camera()
	for r in records:
		if int(r.state) == 3:
			_triggers(r)

func advance_apd(now: int) -> void:
	var done: Array = []
	for r in records:
		if int(r.state) == 3 and not done.has(r.player):
			r.player.advance(now)
			done.append(r.player)

func _complete(r: Dictionary) -> void:
	r.state = 4
	var cleanup = bool(r.get("auto_cleanup",false))
	if r.has("raw_hex"):
		var bytes = str(r.raw_hex).hex_decode()
		cleanup = bytes.size() > 54 and (bytes[54]&1) != 0
	if cleanup:
		for trigger in r.get("child_triggers",[]).slice(int(r.child_cursor)):
			if _by_id.has(int(trigger[1])):
				_start(_by_id[int(trigger[1])])
		for trigger in r.get("sound_triggers",[]).slice(int(r.sound_cursor)):
			sound_requested.emit(int(trigger[1]))
		_cleanup(r)

func _cleanup(r: Dictionary) -> void:
	if r.deleted: return
	r.deleted = true
	cleanup_requested.emit(r)

func after_apd() -> void:
	if not active:
		return
	var running = 0
	for r in records:
		if int(r.state) != 3:
			continue
		if r.get("native_wait",false) and not r.player.busy:
			_complete(r)
			continue
		if not r.player.busy:
			var command: Dictionary = r.commands[int(r.command_index)]
			r.prior_ordinals += int(command.get("compiled_steps",r.player.steps.size()))
			r.command_index += 1
			if int(r.command_index) >= r.commands.size():
				_complete(r)
				continue
			_play_command(r)
		running += 1
	if running == 0:
		for r in records:
			if int(r.state) == 2:
				_start(r)
				running += 1
	if running == 0:
		for r in records:
			if not r.deleted: _cleanup(r)
		active = false
		suppressed.clear()
		finished.emit()

func drawables(project: Callable, unit_project: Callable = Callable()) -> Array:
	var output: Array = []
	var seen: Array = []
	for r in records:
		if int(r.type) == 1: continue # Shared Unit70 is already drawn through the actor pool.
		if int(r.state) not in [3,4] or bool(r.deleted) or seen.has(r.player) or not r.player.visible:
			continue
		seen.append(r.player)
		var command: Dictionary = r.commands[mini(int(r.command_index),r.commands.size()-1)]
		var raw = command.get("world_from",command.get("from",[0,0]))
		var world = Vector2i(int(raw[0]),int(raw[1]))
		var sort_raw = command.get("output_xy",command.get("output",raw))
		var sort_world = Vector2i(int(sort_raw[0]),int(sort_raw[1]))
		var anchor: Vector2i = project.call(world)
		if int(r.type) == 1 and unit_project.is_valid():
			anchor = unit_project.call(world)
		var offset = command.get("offset_xy",[0,0])
		if command.has("raw_hex"):
			var bytes = str(command.raw_hex).hex_decode()
			offset = [bytes.decode_s16(48),bytes.decode_s16(50)]
		anchor += Vector2i(int(offset[0]),int(offset[1]))
		output.append({"player":r.player,"anchor":anchor,"depth":sort_world.x+sort_world.y,"priority":5 if int(r.type) == 2 else 4,"policy":"actor"})
		var slot = int(r.unit_slot)
		if int(r.type) == 0 and _shared.has(slot) and _shared[slot].has("shadow"):
			var finish_raw = command.get("world_to",command.get("to",raw))
			var finish = Vector2i(int(finish_raw[0]),int(finish_raw[1]))
			var nearest = preload("ft2_physical_geometry.gd").nearest(world,finish,anchor+r.player.offset,project)
			var ground: Vector2i = project.call(nearest.world)
			var residual: Vector2i = nearest.residual
			var direction = int(command.get("direction",0))
			var ground_dy = (-residual.x if direction in [0,3] else residual.x)>>1
			output.append({"player":_shared[slot].shadow,"anchor":Vector2i(ground.x-residual.x,ground.y-ground_dy),"depth":sort_world.x+sort_world.y,"priority":2,"policy":"system"})
	return output

func _update_camera() -> void:
	if not project_world.is_valid() or not _by_id.has(_camera_index): return
	var r: Dictionary = _by_id[_camera_index]
	if int(r.state) != 3 or r.commands.is_empty(): return
	var c: Dictionary = r.commands[mini(int(r.command_index),r.commands.size()-1)]
	var raw = c.get("world_from",c.get("from",[0,0]))
	var world = Vector2i(int(raw[0]),int(raw[1]))
	var user_raw = c.get("offset_xy",[0,0])
	if c.has("raw_hex"):
		var bytes = str(c.raw_hex).hex_decode()
		user_raw = [bytes.decode_s16(48),bytes.decode_s16(50)]
	var user = Vector2i(int(user_raw[0]),int(user_raw[1]))
	var a = _camera_references.get("start")
	var b = _camera_references.get("end")
	if a is Array: a = Vector2i(int(a[0]),int(a[1]))
	if b is Array: b = Vector2i(int(b[0]),int(b[1]))
	#439210 projects the world reference globals on every camera service.
	#Legacy explicit pixel fixtures retain their existing input convention.
	if _camera_references.get("space","pixel") == "world" and a != null and b != null:
		a = project_world.call(a)
		b = project_world.call(b)
	var focus = preload("ft2_physical_geometry.gd").focus(_camera_mode,project_world.call(world),r.player.offset,user,int(c.get("direction",0)),a,b)
	if focus != null: camera_focus_requested.emit(focus)
	elif _camera_mode == 3:
		unsupported["camera3_reference_missing" if a == null or b == null else "camera3_zero_screen_span"] = _camera_index

func dispose() -> void:
	active = false
	records.clear()
	_by_id.clear()
	_shared = {}
	_camera_references = {}
	suppressed.clear()
	assets = null
	project_world = Callable()
	native_wait_player = Callable()
