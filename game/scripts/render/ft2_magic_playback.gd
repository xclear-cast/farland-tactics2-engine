class_name FT2MagicPlayback
extends RefCounted
##432950/434880 common cast, authored layers and source delayed activation.
signal finished
signal sound_requested(stem: String, loop: bool)
signal sound_stop_requested(stem: String)
signal target_pose(slot: int)
signal actor_refresh(slot: int)
signal palette_loaded(image: Dictionary, first: int, count: int)
signal camera_requested(request: Dictionary)
signal summon_fade_requested(slots: Array)
signal summon_fade_busy_query(result: Dictionary)
signal constructor_service_requested
signal nested_service_requested(context: String)
signal actor_job_pool_service_requested
signal surface_requested(request: Dictionary)
var data
var assets: FT2IndexedAssets
var palette: FT2Palette
var active = false
var children: Array = []
var caster: Dictionary = {}
var suppressed: Dictionary = {}
var unsupported: Dictionary = {}
var stage_handlers: Dictionary = {}
var _cast_labels: Array = []
var _plan: Dictionary = {}
var _units: Array = []
var _map: Dictionary = {}
var _magic: PackedByteArray
var _id = 0
var _phase = 0
var _epoch = 0
var _now = 0
var _latch = -1
var _global_phase = 0
var _center = Vector2i.ZERO
var _side = 0
var sound_busy: Callable
var random_source: Callable
var projection: Callable
var _secondary = 0
var _trig: Array = []
var service_rng_this_tick = true
var clock_this_tick = true
var palette_update_this_tick = false
var _missile_offsets: Array = []
var _direct_this_tick = false
var _proxy: Dictionary = {}
var _jobs
var navigation
var music_fade: Callable
var music_busy: Callable
var _proxy_started_this_tick = false
var _proxy_was_busy = false
var _pending_cleanup = false
var _legacy_tick = 0
var _main_sound_started = false #4092B0 owns a fresh buffer, distinct from408FA0 one-shot cache.
const OFFSETS = [Vector2i(0,0),Vector2i(-1,0),Vector2i(0,-1),Vector2i(1,0),Vector2i(0,1),Vector2i(-1,1),Vector2i(-2,0),Vector2i(-1,-1),Vector2i(0,-2),Vector2i(1,-1),Vector2i(2,0),Vector2i(1,1),Vector2i(0,2),Vector2i(-1,2),Vector2i(-2,1),Vector2i(-3,0),Vector2i(-2,-1),Vector2i(-1,-2),Vector2i(0,-3),Vector2i(1,-2),Vector2i(2,-1),Vector2i(3,0),Vector2i(2,1),Vector2i(1,2),Vector2i(0,3)]

func configure(store, pack: FT2IndexedAssets, colors: FT2Palette) -> void:
	data = store
	assets = pack
	palette = colors
	_magic = data.raw_table("magic")
	var index: Dictionary = data.read_json("data/port_ready/effects/source_index.json")
	stage_handlers = index.dispatch_tables
	var contract: Dictionary = data.read_json("data/port_ready/effects/spec/common_cast_lifecycle.json")
	_cast_labels = contract.per_skill_cast_labels
	_trig = data.read_json("data/port_ready/effects/spec/fixed_trig_contract.json").quarter_wave_u16
	_missile_offsets = data.read_json("data/port_ready/effects/spec/missile78_contract.json").offsets_by_direction
	_jobs = preload("../scenario/ft2_actor_jobs.gd").new(data)
	_jobs.cell_committed.connect(_proxy_cell_committed)

func _proxy_cell_committed(_slot: int, cell: Vector2i) -> void:
	if not _proxy.is_empty():
		_proxy.world = cell

static func _i32(value: int) -> int:
	return ((value+2147483648)&0xFFFFFFFF)-2147483648

func sin_q16(radius: int, angle: int) -> int:
	radius = _i32(radius)
	angle = posmod(_i32(angle),360)
	if angle == 0 or angle == 180:
		return 0
	if angle == 90:
		return radius
	if angle == 270:
		return _i32(-radius)
	var a = angle if angle < 90 else 180-angle if angle < 180 else angle-180 if angle < 270 else 360-angle
	var value = _i32(int(_trig[a])*radius)>>16
	return _i32(-value) if angle >= 180 else value

func cos_q16(radius: int, angle: int) -> int:
	radius = _i32(radius)
	var a = posmod(_i32(angle)+90,360)-90
	if a == 0:
		return radius
	if a == 180:
		return _i32(-radius)
	if a <= 90:
		return _i32(int(_trig[90-absi(a)])*radius)>>16
	return _i32(-(_i32(int(_trig[90-absi(a-180)])*radius)>>16))

func _random(modulus: int) -> int:
	return int(random_source.call(modulus)) if random_source.is_valid() else 0

func _word(offset: int) -> int:
	return _magic.decode_u16(_id*64+offset)

func _unit(slot: int) -> Dictionary:
	return data.decode_unit(_units[slot],slot) if slot >= 0 and slot < _units.size() else {}

func _stem() -> String:
	var bytes = _magic.slice(_id*64+34,_id*64+46)
	var zero = bytes.find(0)
	return (bytes.slice(0,zero) if zero >= 0 else bytes).get_string_from_ascii()

func _label_player(stem: String, label: String, flags: int) -> FT2APDPlayer:
	var player = FT2APDPlayer.new()
	player.play(assets.apd(stem) if stem != "" and not stem.begins_with("0") else {},label,_now,flags)
	return player

func _original_resource_available(stem: String) -> bool:
	#42C518..53E ->42C770 loops over every declared sheet before labels load.
	# A normalized APD schedule alone does not make a missing original BMP valid.
	var dataset = assets.apd(stem)
	if dataset.is_empty():
		unsupported["original_missing_asset:"+stem] = {"skill":_id,"reason":"APD unavailable"}
		return false
	for raw in dataset.get("sheets",[]):
		var key = str(raw).replace("\\","/").to_lower()
		var image: Dictionary = assets.manifest.get("images",{}).get(key,{})
		if image.is_empty() or not FT2Content.exists(str(image.get("indices",""))) or not FT2Content.exists(str(image.get("palette",""))):
			unsupported["original_missing_asset:"+stem] = {"skill":_id,"sheet":key,"reason":"declared sheet unavailable"}
			return false
	return true

func _abort_missing_resource(previous_sound: String) -> bool:
	if previous_sound != "": sound_stop_requested.emit(previous_sound)
	active = false
	_main_sound_started = false
	_pending_cleanup = false
	children.clear()
	caster.clear()
	suppressed.clear()
	_proxy.clear()
	_jobs.clear()
	# Failure is not successful visual completion; do not emit finished.
	return false

func play(plan: Dictionary, units: Array, cells: Dictionary, now: int) -> bool:
	var previous_sound = "magic%02d" % _word(46) if active and _main_sound_started else ""
	_plan = plan
	_units = units
	_map = cells
	_now = now
	_id = int(plan.get("effect_id",plan.get("action_id",0)))
	if _id < 0 or _id*64+64 > _magic.size():
		return false
	children.clear()
	_proxy.clear()
	_jobs.clear()
	caster.clear()
	suppressed.clear()
	_global_phase = 0
	_main_sound_started = false
	_pending_cleanup = false
	_latch = -1
	_phase = 1
	_epoch = now
	_center = plan.get("center",Vector2i.ZERO)
	_side = _word(48)
	var slot = int(plan.get("actor_slot",-1))
	var unit = _unit(slot)
	if unit.is_empty():
		return false
	if _word(52) != 0:
		var direction = int(unit.direction)
		var mirror = 16 if direction in [1,2] and data.appearance_definition(int(unit.definition_id)) not in [23,73] else 0
		var prefix = "F." if direction <= 1 else "B."
		var stem = data.sprite_stem(int(unit.definition_id),"E")
		if not _original_resource_available(stem): return _abort_missing_resource(previous_sound)
		caster = {"player":_label_player(stem,prefix+str(_cast_labels[_id].prepare_label_unprefixed),mirror|1),"world":Vector2i(unit.x,unit.y),"slot":slot,"stem":stem,"prefix":prefix,"flags":mirror}
		if caster.player.apd.is_empty():
			unsupported["caster_resource:"+stem] = _id
			return false
		suppressed[slot] = true
		_phase = 0
		_epoch = 0
	var handler = str(stage_handlers.initializer.skill_handlers[str(_id)])
	camera_requested.emit({"kind":"cell","cell":_center})
	var stem = _stem()
	if stem != "" and not stem.begins_with("0") and not _original_resource_available(stem):
		return _abort_missing_resource(previous_sound)
	if stem != "" and not stem.begins_with("0") and assets.apd(stem).is_empty():
		unsupported["effect_resource:"+stem] = _id
		return false
	if stem != "" and not stem.begins_with("0"):
		for sheet in assets.apd(stem).get("sheets",[]):
			var image = assets.apd_image(str(sheet),[[10,32,208]])
			if not image.is_empty():
				var band = assets.apd_palette_band(str(sheet),208,32)
				palette.install(image.palette,band.x,band.y)
				palette_loaded.emit(image,band.x,band.y)
	if handler == "0x432ba0":
		_generic(stem,unit)
	elif _id in [55,81]:
		_add_child(stem,"EFFECTA",_center,1,5)
		_add_child(stem,"EFFECTB",Vector2i(unit.x,unit.y),1600,5)
	elif _id >= 71 and _id <= 76:
		var delta = _center-Vector2i(unit.x,unit.y)
		var direction = Vector2i(0,1) if absi(delta.x) < absi(delta.y) and delta.y > 0 else Vector2i(0,-1) if absi(delta.x) < absi(delta.y) else Vector2i(1,0) if delta.x > 0 else Vector2i(-1,0)
		for distance in range(1,_word(32)+1):
			var world = Vector2i(unit.x,unit.y)+direction*distance
			if distance >= _word(30) and _valid(world):
				_add_child(stem,"F.EFFECT",world,1+100*(distance-_word(30)),5)
		palette.brightness(32,176,80,8,now)
	elif _id == 83:
		var world = Vector2i(unit.x,unit.y)
		for i in range(80):
			var x = _random(1280)-640
			var y = _random(960)-480
			var z = _random(300)
			_add_child(stem,"",world,0,5)
			children[-1]["xyz"] = Vector3i(x,y,z)
			children[-1]["screen"] = Vector2i(x,y)
	elif _id in [9,12,19,26]:
		var world = Vector2i(unit.x,unit.y)
		if _id in [9,19,26]:
			_add_child(stem,"F.SET" if _id == 9 else "F.COMEHERE",world,1 if _id == 9 else 500,5)
			children[-1]["screen"] = Vector2i(320,240)
			children[-1]["callback_world"] = Vector2i.ZERO
			if _id == 9:
				children[-1].players[0].player.dither = 8
		if _id in [9,26]:
			for i in range(9 if _id == 9 else 19):
				var position = _random_world(world,_word(32))
				_add_child(stem,"F.EFFECT" if _id == 9 else "THUNDER",position,0,5)
		elif _id == 12:
			for i in range(100):
				var radius = _random(400)+50
				var angle = _random(360)
				_add_child(stem,"SNOW1",world,10,3)
				children[-1]["parameter"] = Vector2i(radius,angle)
				children[-1]["callback_world"] = Vector2i(radius,angle)
		else:
			for i in range(99):
				var variant = _random(3)+1
				var x = _random(640)
				var y = _random(480)
				_add_child(stem,"SNOW%d" % variant,world,0,5)
				children[-1]["screen"] = Vector2i(x,y)
				children[-1]["callback_world"] = Vector2i(x,y)
				children[-1]["variant"] = variant
	elif _id in [29,39]:
		var world = Vector2i(unit.x,unit.y)
		for i in range(20):
			var position = _random_world(world,_word(32))
			var label = "F.EFFECT"
			var delay = 200*i
			if _id == 39:
				label = "S_METEO" if _random(30) < 10 else "L_METEO"
				delay = _random(3000)+10
			_add_child(stem,label,position,delay,5)
	elif _id == 53:
		camera_requested.emit({"kind":"cell","cell":_center})
		constructor_service_requested.emit() # Explicit408A50 before MARE allocation.
		_add_child(stem,"MARE",_center,0,5)
		for result in plan.get("results",[]):
			var target = _unit(int(result.get("target_slot",-1)))
			if not target.is_empty():
				_add_child(stem,"F.EFFECT",Vector2i(target.x,target.y),0,5)
				if children[-1].players[0].player.frame < 0:
					children.pop_back()
	elif _id == 78:
		var world = Vector2i(unit.x,unit.y)
		var screen: Vector2i = projection.call(world)
		for raw in _missile_offsets[int(unit.direction)]:
			_add_child(stem,"UP_MISSILE2",world,0,5)
			children[-1]["screen"] = screen+Vector2i(int(raw[0]),int(raw[1]))
		for result in plan.get("results",[]):
			var slot_target = int(result.get("target_slot",-1))
			var target = _unit(slot_target)
			if not target.is_empty():
				_add_child(stem,"DOWN_MISSILE2",Vector2i(target.x,target.y),0,5)
				children[-1]["callback_world"] = world
				children[-1]["target_slot"] = slot_target
	elif _id == 82:
		pass # Numeric constructor already owns the persistent units; no child array.
	elif _id == 77:
		var source = Vector2i(unit.x,unit.y)
		var direction = _facing(source,_center)
		var next = source+[Vector2i(0,1),Vector2i(1,0),Vector2i(-1,0),Vector2i(0,-1)][direction]
		var shadow = _label_player("SYSTEM","MIDDLE.M",128)
		_proxy = {"world":next,"last":next,"direction":direction,"shadow":shadow,"origin":source}
		var player = _label_player(stem,"",128)
		_proxy["player"] = player
		_add_child(stem,("F." if direction <= 1 else "B.")+"CRACK",source,0,3)
		children[-1].players[0].player.mirror = direction in [1,2]
	elif _id in [47,58,64]:
		var resource_valid = stem != "" and not stem.begins_with("0") and not assets.apd(stem).is_empty()
		var count = 100 if _id in [47,64] else plan.get("results",[]).size()+40
		for i in range(count):
			if not resource_valid:
				children.append({"world":Vector2i.ZERO,"callback_world":Vector2i.ZERO,"delay":0,"players":[],"active":false,"data":Vector2i.ZERO})
			elif _id == 64:
				var radius = _random(500)+200
				var angle = _random(360)
				_add_child(stem,"STAR",Vector2i(unit.x,unit.y),1,5)
				children[-1]["data"] = Vector2i(radius,angle)
			elif _id == 47:
				_add_child(stem,"ACTION1" if i == 0 else "STAR",Vector2i(unit.x,unit.y),1 if i == 0 else _random(3000)+10,5)
				children[-1]["data"] = Vector2i.ZERO
				if i == 0: children[-1]["screen"] = Vector2i(320,0)
			else:
				var victim_count = plan.get("results",[]).size()
				if i < victim_count:
					var target = _unit(int(plan.results[i].target_slot))
					_add_child(stem,"F.EFFECT",Vector2i(target.x,target.y),1,5)
				else:
					var x = _random(640)
					var y = _random(480)
					var direction = _random(4)
					_add_child(stem,("F." if direction <= 1 else "B.")+"RUN1",Vector2i(unit.x,unit.y),1,5)
					children[-1]["screen"] = Vector2i(x,y)
					children[-1]["direction"] = direction
					children[-1].players[0].player.mirror = direction in [1,2]
	elif _id == 60:
		# Canonical60: primary nameASCII0 and+34mask0; 433B4D allocation0 exits
		# before constructing its pseudo unit. The epoch0/frame29/36 path is unreachable.
		pass
	elif _id == 61:
		camera_requested.emit({"kind":"cell","cell":Vector2i(unit.x,unit.y)})
	elif handler != "0x434406":
		unsupported["initializer:"+str(_id)] = handler
		return false
	for child in children:
		if _id in [5,51]:
			child.delay = 1
		elif _id in [10,32,40,45]:
			child.delay = 1000
		elif _id in [67,68,69]:
			child.delay = 100
	if _id == 58:
		palette.brightness(32,112,0,4,now)
	elif _id == 64:
		palette.brightness(32,176,60,4,now)
	elif _id in [67,68,69]:
		palette.brightness(32,176,80,4,now)
	if _id in [14,54,63,64]:
		sound_requested.emit("magic03",false)
	elif _id == 20:
		sound_requested.emit("angry",false)
	elif _id in [24,40] and int(unit.definition_id) == 15:
		sound_requested.emit("cat",false)
	elif _id == 51 and int(unit.definition_id) == 16:
		sound_requested.emit("threat",false)
	active = true
	return true

func _valid(world: Vector2i) -> bool:
	return _map.has(world) and int(_map[world][3]) == 0 and int(_map[world][4]) == 0

func _random_world(center: Vector2i, radius: int) -> Vector2i:
	while true:
		var position = center+Vector2i(_random(2*radius+1)-radius,_random(2*radius+1)-radius)
		if _valid(position) and absi(position.x-center.x)+absi(position.y-center.y) <= radius:
			if not projection.is_valid() or projection.call(position).y < 480:
				return position
	return center

static func _facing(source: Vector2i, dest: Vector2i) -> int:
	var delta = dest-source
	return (1 if delta.x >= 0 else 2) if absi(delta.y) < absi(delta.x) else (0 if delta.y >= 0 else 3)

func _generic(stem: String, unit: Dictionary) -> void:
	var shape = _word(50)
	if shape not in [0,1,3]:
		return
	var radius = 0
	if shape == 1:
		var delta = int(unit.level)-_word(20)
		radius = 0 if delta < 10 else 1 if delta < 20 else 2
	elif shape == 3:
		radius = _word(32)
	for y in range(_center.y-radius,_center.y+radius+1):
		for x in range(_center.x-radius,_center.x+radius+1):
			var world = Vector2i(x,y)
			var delta = world-_center
			if absi(delta.x)+absi(delta.y) > radius or not _valid(world):
				continue
			var occupant = -1
			for slot in range(_units.size()):
				var u = _unit(slot)
				if int(u.kind) != 0 and (int(u.state) != 9 or int(u.kind) == 8) and Vector2i(u.x,u.y) == world:
					occupant = slot
					break
			if occupant < 0 and _side == 1:
				continue
			if occupant >= 0 and not _plan.get("ordered_targets",[]).has(occupant):
				continue
			var ordinal = OFFSETS.find(delta)
			if ordinal < 0:
				unsupported["generic_offset:"+str(delta)] = _id
				continue
			var child = {"world":world,"delay":200+150*ordinal,"players":[],"active":false}
			for pair in [["F.EFFECT",5],["B.EFFECT",3]]:
				var player = _label_player(stem,pair[0],128)
				if player.frame >= 0:
					player.visible = false
					child.players.append({"player":player,"priority":pair[1]})
			children.append(child)

func _add_child(stem: String, label: String, world: Vector2i, delay: int, priority: int) -> void:
	var player = _label_player(stem,label,128)
	player.visible = false
	children.append({"world":world,"delay":delay,"players":[{"player":player,"priority":priority}],"active":false})

func _cast_started() -> void:
	if _id in [3,10,13,25,32,40,41,44,45,52,67,68]:
		palette.brightness(32,176,80,4,_now)
	if _id == 83:
		palette.brightness(32,112,0,4,_now)
		return
	if _id == 9:
		var target = palette.base.duplicate()
		for color in range(32,208):
			target[color*3+1] >>= 1
			target[color*3+2] >>= 1
		palette.fade(target,32,176,4,_now)
		return
	if _id in [12,19,26]:
		if _id == 12:
			_pose_all()
		if _id in [19,26] and not caster.is_empty(): caster.player.visible = false
		surface_requested.emit({"op":"capture"}) #434AB7/B44/BA4→408580(4499D0).
		surface_requested.emit({"op":"visible_all","visible":false})
		if not caster.is_empty(): caster.player.visible = true
		palette.brightness(32,112 if _id == 26 else 176,60,4,_now)
		_secondary = _now
		if _id == 12:
			_sound()
		elif _id == 26:
			sound_requested.emit("angry",false)
		return
	if _id in [29,39]:
		var target = palette.base.duplicate()
		for color in range(32,144):
			target[color*3+1] >>= 1
			target[color*3+2] >>= 1
			if _id == 29:
				target[color*3] >>= 1
		_white(32,176)
		palette.fade(target,32,176,2,_now)
		_pose_all()
		if _id == 29:
			_sound()
		return
	if _id == 53:
		palette.brightness(32,112,70,8,_now)
		children[0].active = true
		children[0].players[0].player.visible = true
		children[0].players[0].player.activate(1)
		children[0].players[0].player._started = false
		return
	if _id == 82:
		var spawned: Array = []
		var before: Array = _plan.get("before_units",[])
		for slot in range(mini(before.size(),_units.size())):
			if before[slot].decode_u16(0) == 0 and _units[slot].decode_u16(0) != 0:
				spawned.append(slot)
		summon_fade_requested.emit(spawned)
		_sound() #434E7A..82 is408F60 Play(handle,0), not Stop.
		return
	if _id == 77:
		children[0].active = true
		children[0].players[0].player.visible = true
		children[0].players[0].player.activate(1)
		return
	if _id == 28:
		_sound()
		for result in _plan.get("results",[]):
			var slot = int(result.get("target_slot",-1))
			if slot >= 0:
				actor_refresh.emit(slot)
		if music_fade.is_valid():
			music_fade.call(0,0)
		return
	if _id == 31:
		_sound()
		return
	if _id == 47:
		surface_requested.emit({"op":"capture"})
		surface_requested.emit({"op":"visible_all","visible":false})
		if not caster.is_empty(): caster.player.visible = true
		palette.brightness(32,176,60,4,_now)
		return
	if _id == 58:
		_pose_all()
		palette.brightness(32,112,0,4,_now)
		_secondary = _now
		return
	if _id == 64:
		surface_requested.emit({"op":"capture"})
		return # Canonical+34=0 never enters this cast-start branch.
	var handler = str(stage_handlers.cast_started_effect.skill_handlers[str(_id)])
	if handler not in ["0x434ef9","0x434a1d"]:
		unsupported["cast_started:"+str(_id)] = handler

func _sound() -> void:
	_main_sound_started = true
	sound_requested.emit("magic%02d" % _word(46),false)

func _sound_busy() -> bool:
	return _main_sound_started and bool(sound_busy.call("magic%02d" % _word(46))) if sound_busy.is_valid() else false

func _white(first: int, count: int) -> void:
	var white = palette.current.duplicate()
	for p in range(first*3,(first+count)*3):
		white[p] = 255
	palette.fade(white,first,count,0,_now)

func _matched(world: Vector2i) -> int:
	for result in _plan.get("results",[]):
		var slot = int(result.get("target_slot",-1))
		var unit = _unit(slot)
		if not unit.is_empty() and Vector2i(unit.x,unit.y) == world:
			return slot
	return -1

func _hit_pose(world: Vector2i) -> void:
	if _side == 1:
		return
	for result in _plan.get("results",[]):
		var slot = int(result.get("target_slot",-1))
		var unit = _unit(slot)
		if not unit.is_empty() and Vector2i(unit.x,unit.y) == world:
			target_pose.emit(slot)
			return

func _pose_all() -> void:
	for result in _plan.get("results",[]):
		var slot = int(result.get("target_slot",-1))
		if slot >= 0:
			target_pose.emit(slot)

func _activation(child: Dictionary, index: int) -> void:
	var handler = str(stage_handlers.child_delay_elapsed_activation.skill_handlers[str(_id)])
	if handler == "0x436160":
		if index == children.size()-1 or not palette.fading:
			var tint = palette.base.duplicate()
			for color in range(32,208):
				var p = color*3
				tint[p] = int((int(tint[p])+510)/3)
				tint[p+1] = int(int(tint[p+1])*80/100)
				tint[p+2] = int(int(tint[p+2])*80/100)
			if child.world == _center:
				var white = palette.current.duplicate()
				for p in range(32*3,208*3):
					white[p] = 255
				palette.fade(white,32,176,0,_now)
				palette.fade(palette.base.duplicate() if children.size() == 1 else tint,32,176,4,_now)
			else:
				palette.fade(tint,32,176,0,_now)
				palette.fade(palette.base.duplicate(),32,176,16 if index == children.size()-1 else 2,_now)
			#436270 falls through4362AD: every accepted flame tint restarts
			#the main sound.436173's busy-palette skip bypasses this too.
			_sound()
	elif handler == "0x436358":
		var white = palette.current.duplicate()
		for p in range(32*3,208*3):
			white[p] = 255
		palette.fade(white,32,176,0,_now)
		palette.brightness(32,176,60,4,_now)
		_sound()
	elif handler in ["0x436272","0x436292","0x4362ad"]:
		if handler == "0x436272":
			for slot in range(_units.size()):
				var unit = _unit(slot)
				if int(unit.kind) != 0 and (int(unit.state) != 9 or int(unit.kind) == 8) and Vector2i(unit.x,unit.y) == child.get("callback_world",child.world):
					actor_refresh.emit(slot)
					break
		if handler == "0x4362ad" or not _sound_busy():
			_sound()
	elif _id == 9:
		if index == 0:
			child.players[0].player.activate(129)
			child.players[0].player.fade_dither(false,10,_now)
		else:
			_sound()
	elif _id == 62:
		var unit = _unit(int(_plan.actor_slot))
		var direction = int(unit.direction)
		if index == 0 and not child.players.is_empty():
			child.players[0].player.play(assets.apd(_stem()),("F." if direction <= 1 else "B.")+"EFFECT1",_now,3|(16 if direction in [1,2] else 0))
		for row in child.players: row.player.activate(3)
	elif _id == 64:
		if index == 0: _sound()
		for row in child.players: row.player.visible = false
	elif handler not in ["0x43631d","0x4362bd"]:
		unsupported["activation:"+str(_id)] = handler
	if handler != "0x43631d":
		_hit_pose(child.get("callback_world",child.world))

func before_apd(now: int) -> void:
	_now = now
	_direct_this_tick = false
	service_rng_this_tick = true
	clock_this_tick = true
	palette_update_this_tick = false
	_proxy_started_this_tick = false
	_proxy_was_busy = false
	if not active:
		return
	if _phase == 0:
		if caster.player.busy:
			return
		var hold_branch = str(_cast_labels[_id].get("hold_branch",""))
		if hold_branch == "0x4348fa":
			sound_requested.emit("angry",false)
			palette.brightness(32,176,60,2,now)
		elif hold_branch == "0x43492d":
			sound_requested.emit("magic07",false)
		caster.player.play(assets.apd(caster.stem),str(caster.prefix)+str(_cast_labels[_id].hold_label_unprefixed),now,int(caster.flags)|(1 if _id == 78 else 3))
		_epoch = now
		_phase = 1
		_cast_started()
	_direct_this_tick = _id in [26,38,47,64]
	service_rng_this_tick = not _direct_this_tick
	palette_update_this_tick = _direct_this_tick
	if _id == 77 and _global_phase == 1 and not _proxy.is_empty():
		_proxy_was_busy = _jobs.is_busy(0)
		actor_job_pool_service_requested.emit()
		_jobs.advance(now)
		_proxy_cross()
	var busy = false
	for index in range(children.size()):
		var child: Dictionary = children[index]
		if not child.active and int(child.delay) != 0:
			if ((now-_epoch)&0xFFFFFFFF) < int(child.delay):
				busy = true
				continue
			child.active = true
			child.delay = 0
			for row in child.players:
				row.player.visible = true
				row.player.activate(1)
				row.player._started = false
			_activation(child,index)
			#4360CC delay activation dispatch bypasses this frame's procedural leaf.
			busy = true
			continue
		for row in child.players:
			busy = busy or row.player.busy
		if _id in [9,12,19,26]:
			busy = _weather_child(child,index,now) or busy
			continue
		if _id in [47,58,64]:
			busy = _legacy_child(child,index,now) or busy
			continue
		if not child.players.is_empty():
			var frame = int(child.players[0].player.frame)
			var handler = str(stage_handlers.per_child_update.skill_handlers[str(_id)])
			if handler == "0x4352e9":
				if frame == 1 and _latch != frame:
					_sound()
				_latch = frame
			elif handler == "0x435323":
				busy = busy or palette.fading
			elif _id == 20:
				if frame == 5 and _latch != frame:
					_hit_pose(child.world)
					if index == children.size()-1 or not palette.fading:
						var tint = palette.base.duplicate()
						for color in range(32,208):
							var p = color*3
							tint[p] = int((int(tint[p])+510)/3)
							tint[p+1] = int((int(tint[p+1])+510)/3)
							tint[p+2] = int(int(tint[p+2])*80/100)
						palette.fade(tint,32,176,0,now)
						palette.brightness(32,176,60,2,now)
						_sound()
				_latch = frame
			elif _id in [41,69]:
				if frame == 1 and _latch != 1:
					_sound()
					_latch = 1
				if _global_phase == 0 and frame == 12:
					var slot = _matched(child.world)
					if slot >= 0:
						actor_refresh.emit(slot)
					_global_phase = 1
			elif _id == 80:
				if frame == 2 and _latch != 2 and _matched(child.world) >= 0:
					_hit_pose(child.world)
					_sound()
				_latch = frame
			elif _id == 39:
				if frame == 10:
					_sound()
			elif handler != "0x43631d":
				unsupported["per_child:"+str(_id)] = handler
	var global_handler = str(stage_handlers.global_frame_update.skill_handlers[str(_id)])
	if _id == 83:
		busy = _particle83(now)
	elif _id in [12,19]:
		busy = _weather_global(now) or busy
	elif _id in [9,26]:
		pass
	elif _id == 53:
		busy = _nightmare53(now)
	elif _id == 78:
		busy = _missile78(now,busy)
	elif _id == 82:
		var query = {"busy":false}
		summon_fade_busy_query.emit(query)
		busy = bool(query.busy)
		service_rng_this_tick = busy
		clock_this_tick = busy
	elif _id == 77:
		busy = _proxy77(now,busy)
	elif _id == 28:
		var waiting = bool(music_busy.call()) if music_busy.is_valid() else false
		if _global_phase == 0 and not waiting:
			_global_phase = 1
			if music_fade.is_valid():
				music_fade.call(2000,1)
			busy = true
		else:
			busy = waiting
	elif _id == 31:
		if _global_phase == 0:
			if not _sound_busy():
				_global_phase = 1
				service_rng_this_tick = false
				clock_this_tick = false
			busy = true
		else:
			for slot in range(_units.size()):
				if int(_unit(slot).kind) != 0:
					actor_refresh.emit(slot)
			busy = false
	elif _id in [38,47,64]:
		pass #43748D direct palette/sprite render; no408A50/RNG0 tail.
	elif _id == 58:
		_direct_this_tick = true
		service_rng_this_tick = false
		palette_update_this_tick = true
		if ((now-_epoch)&0xFFFFFFFF) > 5000:
			sound_requested.emit("magic13",false)
			_white(32,208)
			busy = false
	elif global_handler != "0x4365bf":
		unsupported["global:"+str(_id)] = global_handler
	_pending_cleanup = not busy and not _sound_busy()

func after_service() -> void:
	if _pending_cleanup:
		_pending_cleanup = false
		active = false
		children.clear()
		caster.clear()
		suppressed.clear()
		palette.brightness(32,208,100,4,_now)
		if _main_sound_started: sound_stop_requested.emit("magic%02d" % _word(46))
		finished.emit()

func _proxy77(now: int, busy: bool) -> bool:
	if _proxy.is_empty():
		return busy
	if _global_phase == 0:
		if children[0].players[0].player.busy:
			return true
		children[0].players[0].player.visible = false
		var dirs: Array = []
		var current: Vector2i = _proxy.world
		var direction = int(_proxy.direction)
		var delta: Vector2i = [Vector2i(0,1),Vector2i(1,0),Vector2i(-1,0),Vector2i(0,-1)][direction]
		for i in range(maxi(0,_word(32)-1)):
			var next = current+delta
			if not _map.has(next) or int(_map[next][3]) != 0 or int(_map[next][4]) != 0 or (navigation != null and not navigation.inside(next)):
				break
			if int(_map[next][2]) > int(_map.get(current,[0,0,0])[2]):
				break
			dirs.append(direction)
			current = next
		_global_phase = 1
		service_rng_this_tick = false
		clock_this_tick = false
		if not dirs.is_empty():
			_jobs.play_path(0,_stem(),_proxy.world,dirs,"RUN",now)
			_proxy_started_this_tick = true
		return true
	if _jobs.is_busy(0):
		return true
	if _proxy_was_busy:
		return true #435084 latched busy before410B20 could complete the final job.
	_proxy.clear()
	_jobs.clear()
	return busy

func _legacy_child(child: Dictionary, index: int, now: int) -> bool:
	var player: FT2APDPlayer = child.players[0].player if not child.players.is_empty() else null
	if _id == 64:
		var data_xy: Vector2i = child.get("data",Vector2i.ZERO)
		var tilt = int(int(((now-_epoch)&0xFFFFFFFF)/10)/4)
		data_xy.y = _i32(data_xy.y+tilt)%360
		var radius = sin_q16(data_xy.x,mini(90,tilt))
		child["data"] = data_xy
		child["screen"] = Vector2i(320+cos_q16(radius,data_xy.y),240+sin_q16(radius,data_xy.y))
		if player != null: player.visible = true
		return false
	if _id == 58:
		if index < _plan.get("results",[]).size() or player == null: return false
		var point: Vector2i = child.get("screen",Vector2i.ZERO)+player.offset
		if point.x >= 0 and point.x < 640 and point.y >= 0 and point.y < 480: return false
		var direction = int(child.get("direction",0))
		if point.x < 0 or point.x >= 640:
			direction = int([1,0,3,2][direction])
			point.x = clampi(point.x,0,639)
		if point.y < 0 or point.y >= 480:
			direction = int([2,3,0,1][direction])
			point.y = clampi(point.y,0,479)
		child["screen"] = point
		child["direction"] = direction
		player.play(assets.apd(_stem()),("F." if direction <= 1 else "B.")+"RUN1",now,3|(16 if direction in [1,2] else 0))
		return false
	if index == 0: _legacy_tick = int(((now-_epoch)&0xFFFFFFFF)/10)
	if _global_phase == 0:
		if index == 0:
			child["screen"] = Vector2i(320,_legacy_tick)
			if _legacy_tick > 320: _global_phase = 1
		elif player == null or not player.busy:
			var a = _random(300)-150
			child["screen"] = Vector2i(320+a,_legacy_tick-int(absi(a)/3)-140)
			if player != null: player.play(assets.apd(_stem()),"STAR",now,1)
		return false
	if _global_phase == 1 and index == 0:
		if player != null: player.play(assets.apd(_stem()),"ACTION2",now,1)
		_global_phase = 2
	elif _global_phase == 2 and index == 0:
		if player == null or not player.busy:
			_global_phase = 3
			return true
	elif _global_phase == 3:
		if index == 0:
			if player != null: player.visible = false
			_white(32,176)
			palette.brightness(32,176,60,2,now)
			_epoch = now-40
			_legacy_tick = 4
			_sound()
			_global_phase = 4
		else:
			var radius = _random(400)+100
			var angle = _random(360)
			child["data"] = Vector2i(cos_q16(radius,angle),sin_q16(radius,angle))
			if player != null: player.play(assets.apd(_stem()),"STAR",now,1)
	if _global_phase >= 3 and index > 0:
		var data_xy: Vector2i = child.get("data",Vector2i.ZERO)
		var tilt = mini(90,int(_legacy_tick/2))
		child["screen"] = Vector2i(320+sin_q16(data_xy.x,tilt),240+sin_q16(data_xy.y,tilt))
	return false

func _proxy_cross() -> void:
	if _proxy.is_empty() or _proxy.world == _proxy.last:
		return
	_proxy.last = _proxy.world
	if _side == 1:
		return
	var slot = _matched(_proxy.world)
	if slot < 0:
		return
	target_pose.emit(slot)
	var direction = int(_proxy.direction)
	_add_child("HITMARK",("F." if direction <= 1 else "B.")+"HITMARK",_proxy.world,0,5)
	var child: Dictionary = children[-1]
	child.active = true
	child.players[0]["policy"] = "cast"
	child.players[0].player.play(assets.apd("HITMARK"),("F." if direction <= 1 else "B.")+"HITMARK",_now,1|(16 if direction in [1,2] else 0))
	child.players[0].player.visible = true
	_sound()

func _missile78(now: int, busy: bool) -> bool:
	if _global_phase == 0:
		if not caster.is_empty():
			var player: FT2APDPlayer = caster.player
			if not player.busy:
				_global_phase = 1
			var pair = 0 if player.frame in [4,20] else 2 if player.frame in [7,23] else 4 if player.frame in [11,27] else -1
			if pair >= 0:
				for index in range(pair,mini(pair+2,children.size())):
					var child: Dictionary = children[index]
					child.active = true
					for row in child.players:
						row.player.visible = true
						row.player.activate(1)
					sound_requested.emit("missile",false)
		else:
			_global_phase = 1
		return true
	if _global_phase == 1:
		for child in children.slice(0,mini(6,children.size())):
			for row in child.players:
				if row.player.busy:
					return true
		for index in range(6,children.size()):
			children[index].delay = 300*(index-5)
		_epoch = now
		_global_phase = 2
		service_rng_this_tick = false
		clock_this_tick = false
		return true
	for child in children.slice(6):
		if not child.players.is_empty() and int(child.players[0].player.frame) == 0:
			target_pose.emit(int(child.get("target_slot",-1)))
			_sound()
	return busy

func _nightmare53(now: int) -> bool:
	if children.is_empty():
		return false
	var primary: FT2APDPlayer = children[0].players[0].player
	if _global_phase == 0:
		if primary.busy:
			if primary.frame == 4 and _latch == -1:
				sound_requested.emit("loud",false)
				_latch = 1
			service_rng_this_tick = true
			return true
		_latch = -1
		_global_phase = -2
		service_rng_this_tick = false
		clock_this_tick = false
		return true
	if _global_phase == -2:
		_pose_all()
		surface_requested.emit({"op":"clear"}) #436B51; keeps character23/73 source policy separate.
		surface_requested.emit({"op":"capture"})
		surface_requested.emit({"op":"present_backdrop"})
		for child in children.slice(1):
			child.active = false
			child.delay = 1
			for row in child.players:
				row.player.activate(1)
				row.player.visible = true
		surface_requested.emit({"op":"visible_all","visible":false})
		_epoch = now
		_sound()
		_global_phase = -3
		service_rng_this_tick = false
		clock_this_tick = false
		return true
	service_rng_this_tick = false
	palette_update_this_tick = true
	var busy = false
	for child in children.slice(1):
		for row in child.players:
			busy = busy or row.player.busy
	if not busy:
		for child in children:
			for row in child.players:
				row.player.visible = false
	return busy

func _weather_child(child: Dictionary, index: int, now: int) -> bool:
	if child.players.is_empty():
		return false
	var player: FT2APDPlayer = child.players[0].player
	if _id == 9 and index == 0:
		if _global_phase == 0:
			if player.dither_busy:
				return true
			player.play(assets.apd(_stem()),"F.COMEHERE",now,1)
			_global_phase = 1
			return true
		if _global_phase == 1:
			if player.busy:
				return true
			for other in children.slice(1):
				other.delay = _random(1000)+30
			player.fade_dither(true,100,now)
			_epoch = now
			_pose_all()
			_global_phase = 2
			return true
	if _id == 26:
		if index == 0 and _global_phase == 0:
			if player.busy:
				return true
			for other in children.slice(1):
				other.delay = _random(2000)+30
			_epoch = now
			_pose_all()
			player.visible = false
			surface_requested.emit({"op":"visible_all","visible":true})
			surface_requested.emit({"op":"clear"})
			surface_requested.emit({"op":"capture"})
			surface_requested.emit({"op":"visible_all","visible":false})
			player.visible = true
			nested_service_requested.emit("magic26_primary_transition")
			player.fade_dither(true,100,now)
			_global_phase = 1
			return true
		if index > 0 and _global_phase == 1 and player.frame == 1 and not palette.fading:
			var tint = palette.base.duplicate()
			for color in range(32,208):
				tint[color*3+2] = 255
			palette.fade(tint,32,176,0,now)
			palette.brightness(32,176,60,2,now)
			_sound()
	if _id == 12 and _global_phase == 0:
		var dt = (now-_secondary)&0xFFFFFFFF
		var parameter: Vector2i = child.parameter
		parameter.x += dt>>1
		parameter.y += dt>>2
		while parameter.x > 450:
			parameter.x -= 400
		while parameter.y > 360:
			parameter.y -= 360
		var center: Vector2i = projection.call(_center)
		child.screen = center+Vector2i(cos_q16(parameter.x,parameter.y),-int(float(sin_q16(parameter.x,parameter.y))/2.0))
		child.parameter = parameter
		child.callback_world = parameter
		var frame = mini(2,int(float(child.screen.y)/200.0))
		if frame >= 0 and frame < player.apd.frames.size():
			player.set_static_frame(frame,0)
		return true
	if _id == 19:
		if index == 0 and _global_phase == 0:
			if player.busy:
				return true
			for other in children.slice(1):
				other.delay = 30
			_epoch = now
			_sound()
			_pose_all()
			player.visible = false
			surface_requested.emit({"op":"visible_all","visible":true})
			surface_requested.emit({"op":"clear"})
			surface_requested.emit({"op":"capture"})
			surface_requested.emit({"op":"present_backdrop"})
			surface_requested.emit({"op":"visible_all","visible":false})
			player.visible = true
			nested_service_requested.emit("magic19_primary_transition")
			_global_phase = 1
			return true
		if index > 0 and _global_phase == 1:
			var dt = (now-_secondary)&0xFFFFFFFF
			var variant = int(child.variant)
			var point: Vector2i = child.screen
			point.x -= int(variant*0.3333333432674408*dt*0.5)+_random(8)
			point.y += int(variant*0.3333333432674408*dt)
			while point.x < 0:
				point.x += 640
			while point.y > 480:
				point.y -= 480
			child.screen = point
			child.callback_world = point
			return true
	return false

func _weather_global(now: int) -> bool:
	palette_update_this_tick = false
	_secondary = now
	var ending = 1 if _id == 12 else 2
	if _global_phase < ending and ((now-_epoch)&0xFFFFFFFF) >= 4000:
		var white = palette.current.duplicate()
		for p in range(32*3,240*3):
			white[p] = 255
		palette.fade(white,32,208,0,now)
		for result in _plan.get("results",[]):
			var slot = int(result.get("target_slot",-1))
			if slot >= 0 and int(_unit(slot).state) == 5:
				actor_refresh.emit(slot)
		surface_requested.emit({"op":"clear"})
		surface_requested.emit({"op":"visible_all","visible":true})
		palette.brightness(32,208,100,4,now)
		for child in children:
			for row in child.players:
				row.player.visible = false
				row.player.activate(128)
		_global_phase = ending
		_direct_this_tick = false
		service_rng_this_tick = true
		return true
	if _global_phase == ending:
		_direct_this_tick = false
		service_rng_this_tick = true
		return palette.fading
	_direct_this_tick = true
	service_rng_this_tick = false
	palette_update_this_tick = true
	return true

func _particle83(now: int) -> bool:
	if _global_phase == 0:
		if palette.fading:
			service_rng_this_tick = true
			clock_this_tick = true
			return true
		service_rng_this_tick = false
		clock_this_tick = false
		var black = palette.current.duplicate()
		for p in range(208*3,224*3):
			black[p] = 0
		palette.fade(black,208,16,0,now)
		palette.fade(palette.base.duplicate(),208,16,4,now)
		if not caster.is_empty(): caster.player.visible = false
		surface_requested.emit({"op":"capture"}) #43718D; copied surface then hide Unit70/74/78.
		surface_requested.emit({"op":"visible_all","visible":false})
		if not caster.is_empty(): caster.player.visible = true
		_epoch = now
		_secondary = 0
		_global_phase = 1
		return true
	if _global_phase == 1:
		if ((_epoch+5000)&0xFFFFFFFF) <= (now&0xFFFFFFFF):
			service_rng_this_tick = true
			clock_this_tick = true
			for child in children:
				for row in child.players:
					row.player.visible = false
			_sound()
			var white = palette.current.duplicate()
			for p in range(32*3,208*3):
				white[p] = 255
			palette.fade(white,32,176,0,now)
			for result in _plan.get("results",[]):
				var slot = int(result.get("target_slot",-1))
				if slot >= 0:
					target_pose.emit(slot)
			surface_requested.emit({"op":"visible_all","visible":true})
			surface_requested.emit({"op":"clear"})
			surface_requested.emit({"op":"capture"})
			surface_requested.emit({"op":"present_backdrop"})
			surface_requested.emit({"op":"visible_all","visible":false})
			palette.fade(palette.base.duplicate(),32,176,4,now)
			_global_phase = 2
			return true
		service_rng_this_tick = false
		clock_this_tick = true
		_direct_this_tick = true
		palette_update_this_tick = true
		if ((_secondary+20)&0xFFFFFFFF) >= (now&0xFFFFFFFF):
			return true
		_secondary = now
		for child in children:
			var xyz: Vector3i = child.xyz
			xyz.z -= 20
			if xyz.z < 100:
				xyz.x = _random(1920)-960
				xyz.y = _random(1440)-720
				xyz.z += 300
			var label = "STAR%d" % (4-mini(4,int((xyz.z-100)/50)))
			var screen = Vector2i(320+int(float(_i32(100*xyz.x))/_i32(xyz.z+50)),240+int(float(_i32(100*xyz.y))/_i32(xyz.z+50)))
			if screen.x < 0 or screen.y < 0 or screen.x > 640 or screen.y > 480:
				xyz.z = 0
			var player: FT2APDPlayer = child.players[0].player
			var visible = player.frame >= 0
			player.play(assets.apd(_stem()),label,now,1)
			player.visible = visible
			child.active = true
			child.screen = screen
			child.xyz = xyz
		return true
	if _global_phase == 2:
		service_rng_this_tick = false
		clock_this_tick = false
		return _sound_busy()
	return false

func advance_apd(now: int) -> void:
	if not active or not clock_this_tick:
		return
	if not caster.is_empty():
		caster.player.advance(now)
	for child in children:
		if child.active:
			for row in child.players:
				row.player.advance(now)
	if _id == 77 and _global_phase == 1 and not _proxy.is_empty() and not _proxy_started_this_tick:
		# The later408A50 services APDs again, but never advances actor-job indices.
		for job in _jobs.jobs.values(): job.player.advance(now)

func drawables(project: Callable, unit_project: Callable = Callable()) -> Array:
	var result: Array = []
	if not caster.is_empty():
		result.append({"player":caster.player,"anchor":unit_project.call(caster.world) if unit_project.is_valid() else project.call(caster.world),"depth":caster.world.x+caster.world.y,"priority":4,"policy":"cast"})
	for child in children:
		for row in child.players:
			result.append({"player":row.player,"anchor":child.get("screen",project.call(child.world)),"depth":child.world.x+child.world.y,"priority":row.priority,"policy":str(row.get("policy","effect"))})
	if not _proxy.is_empty():
		for snapshot in _jobs.snapshots():
			var world: Vector2i = snapshot.world
			var sort_world: Vector2i = snapshot.sort_world
			result.append({"player":snapshot.player_override,"anchor":project.call(world),"depth":sort_world.x+sort_world.y,"priority":3,"policy":"effect"})
		result.append({"player":_proxy.shadow,"anchor":project.call(_proxy.origin),"depth":_proxy.origin.x+_proxy.origin.y,"priority":2,"policy":"system"})
	return result

func direct_render() -> bool:
	return active and _direct_this_tick

func dispose() -> void:
	active = false
	if _jobs != null:
		_jobs.clear()
		for descriptor in _jobs.get_signal_list():
			var signal_name = str(descriptor.name)
			for connection in _jobs.get_signal_connection_list(signal_name):
				_jobs.disconnect(signal_name,connection.callable)
	_jobs = null
	children.clear()
	caster.clear()
	suppressed.clear()
	_proxy.clear()
	_plan = {}
	_units = []
	_map = {}
	projection = Callable()
	random_source = Callable()
	sound_busy = Callable()
	music_fade = Callable()
	music_busy = Callable()
	navigation = null
	data = null
	assets = null
	palette = null
