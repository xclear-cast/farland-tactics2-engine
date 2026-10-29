class_name FT2BattleView
extends Node2D

signal visual_finished
signal cell_hovered(cell: Vector2i)
signal actor_finished(slot: int)
signal camera_finished
signal sound_requested(stem: String, loop: bool)
signal sound_stop_requested(stem: String)

const DITHER = [0,32800,41120,42148,42405,44461,44975,61375,65535]
var data
var battle
var assets: FT2IndexedAssets
var palette: FT2Palette
var font: FT2IndexedFont
var surface: FT2IndexedSurface
var camera = Vector2i.ZERO
var map_id = -1
var map: Dictionary = {}
var clock_ms = 0
var unsupported: Dictionary = {}
var _cells: Dictionary = {}
var _baked: Dictionary = {}
var _actors: Dictionary = {}
var _actor_resource_stems: Dictionary = {} #45EAD0 definition resource cache.
var actor_resource_load_failures: Dictionary = {} # Original optional V load returned NULL.
var _actor_cache_generation = 0
var _actor_npc_cache_generation = 0
var _script: Dictionary = {}
var _script_commands_seen: Dictionary = {}
var _script_variant_commands_seen: Dictionary = {}
var _script_unit78: Dictionary = {}
var _overlay: Array = []
var _texture: ImageTexture
var _sprite: Sprite2D
var _material: ShaderMaterial
var _plan: Dictionary = {}
var _result_players: Array = []
var _result_state = -1
var _result_epoch = 0
var _camera_motion: Dictionary = {}
var _dirty = true
var _hover = Vector2i(-1,-1)
var _installed: Dictionary = {}
var environment
var physical
var magic
var physical_builder
var _last_service_rng = true
var game_mode = 1
var _service_mode = "normal"
var _summon_slots: Array = []
var _summon_precast_slots: Array = []
var _physical_sound_paths: Array = []
var facing_choice = 4
var pointer_cell = Vector2i(-1,-1)
var _cursor: FT2APDPlayer
var _audio
var shake_amplitude = 0
var _shake_delta = Vector2i.ZERO
var _base_image: Image
var _disposed = false
var _palette_prefix_ms = -1
var _frame_override_active = false
var _frame_override: Array = []
var _magic_replaced_caster = false
var _magic_deferred_plan:Dictionary={}
var _magic_deferred_targets:Dictionary={}
var _normal_draw_override = false
var _result_backdrop: Image
var _source_backdrop: Image #4499D0: keyed overlay in408580, opaque base in4374A4.
var _source_backdrop_data: Dictionary = {}
var surface_events: Array = []
var message_surface_events: Array = []
var script_surface_events: Array = []
var _experience_font = {"height":16,"color":30,"style":1}
var _result_tail_serviced = false
var _ko_active = false
var _ko_slots: Array = []
var zoom
var _cycle_palette: PackedByteArray
var _cycle_epoch = 0
var _skip_palette_animation = false
var _skip_effect_animation = false
var _show_occluded = false
var shift_held = false

func configure(source_data) -> void:
	data = source_data
	assets = FT2IndexedAssets.new()
	palette = FT2Palette.new()
	font = FT2IndexedFont.new()
	surface = FT2IndexedSurface.new()
	environment = preload("ft2_environment.gd").new()
	physical = preload("ft2_physical_playback.gd").new()
	zoom = preload("../logic/ft2_zoom.gd").new()
	physical.configure(assets)
	physical.finished.connect(_physical_finished)
	physical.sound_requested.connect(_physical_sound)
	physical.camera_focus_requested.connect(_physical_camera_focus)
	physical.project_world = Callable(self,"_world_pixel")
	physical.native_wait_player = Callable(self,"_native_wait_player")
	physical.cleanup_requested.connect(_physical_cleanup_record)
	magic = preload("ft2_magic_playback.gd").new()
	magic.configure(data,assets,palette)
	magic.finished.connect(_magic_finished)
	magic.sound_requested.connect(func(stem,loop): sound_requested.emit(stem,loop))
	magic.sound_stop_requested.connect(func(stem): sound_stop_requested.emit(stem))
	magic.target_pose.connect(_magic_target_pose)
	magic.actor_refresh.connect(_refresh_actor)
	magic.palette_loaded.connect(_mark_palette_loaded)
	magic.camera_requested.connect(camera_request)
	magic.summon_fade_requested.connect(_summon_fade)
	magic.summon_fade_busy_query.connect(_summon_busy)
	magic.constructor_service_requested.connect(_magic_constructor_service)
	magic.nested_service_requested.connect(_magic_nested_service)
	magic.actor_job_pool_service_requested.connect(_magic_job_pool_service)
	magic.surface_requested.connect(_magic_surface_request)
	magic.random_source = Callable(self,"_visual_random")
	magic.projection = Callable(self,"world_to_screen")
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_material = ShaderMaterial.new()
	_material.shader = preload("indexed_palette.gdshader")
	_sprite.material = _material
	add_child(_sprite)
	var system = assets.image("sprite/system.bmp", [[90,16,208],[10,64,144],[74,16,16]])
	if not system.is_empty():
		palette.install(system.palette)
		_cycle_palette = system.palette.slice(208*3,224*3)
	_cursor = FT2APDPlayer.new()
	_cursor.play(assets.apd("SYSTEM"),"CURSOR",clock_ms,3)
	_dirty = true

func set_battle(model) -> void:
	battle = model
	if battle != null:
		physical_builder = preload("../logic/ft2_physical_program.gd").new(data,battle.rules,battle.navigation)
		magic.navigation = battle.navigation
	if battle != null and not battle.changed.is_connected(_battle_changed):
		battle.changed.connect(_battle_changed)
	_battle_changed()

func _battle_changed() -> void:
	if battle == null or assets == null:
		return
	if map_id != battle.map_id:
		set_map(battle.map_id)
	var pending:Dictionary=battle.pending_plan
	if battle.phase=="visual" and str(pending.get("visual_kind","")) in ["magic","item"]:
		if _magic_deferred_plan!=pending:
			_magic_deferred_plan=pending;_magic_deferred_targets.clear()
			var before:Array=pending.get("before_units",[])
			for record in pending.get("results",[]):
				var slot:=int(record.get("target_slot",-1))
				if slot>=0 and slot<before.size() and slot!=int(pending.get("actor_slot",-1)) and _actors.has(slot):
					var state:int=battle.units[slot].decode_u16(16)
					if state in [4,5] and before[slot].decode_u16(16)!=state:
						#4151D0 already resolved the result.4379C0 owns when the
						#existing target sprite becomes stone/frozen, at impact.
						_magic_deferred_targets[slot]=true
	else:
		_magic_deferred_plan={};_magic_deferred_targets.clear()
	_refresh_actors()
	_dirty = true

func set_map(id: int) -> void:
	#402E10 replaces map resources only. Shared4499D0 and Unit visual caches
	# remain owned by their explicit clear/41AB80 callers.
	if map_id == 21 and id != 21:
		sound_stop_requested.emit("spectate") #40314F releases environment44EA68.
	map_id = id
	environment.configure(id)
	map = assets.map_data(id)
	_cells.clear()
	_baked.clear()
	if map.is_empty():
		return
	camera = Vector2i.ZERO #402E10 success writes44EA18/44EA1C=0.
	for c in map.cells:
		_cells[Vector2i(int(c[0]),int(c[1]))] = c
	if map.has("baked"):
		_baked = {"width":int(map.baked.width),"height":int(map.baked.height),"pixels":FT2Content.bytes(str(map.baked.indices))}
	for key in map.atlases:
		var image = assets.image(str(key),[[10,112,32]])
		if not image.is_empty():
			palette.install(image.palette,32,112)
	var background_key = str(map.get("background",""))
	var background = assets.image(background_key,[[10,112,32]]) if background_key != "map/" and background_key != "" else {}
	if not background.is_empty():
		palette.install(background.palette,32,112)
	_clamp_camera()
	_dirty = true

func world_to_screen(world: Vector2i) -> Vector2i:
	if map.is_empty():
		return Vector2i.ZERO
	var h = int(_cells.get(world,[0,0,0])[2])
	return Vector2i((world.x-world.y)*32+int(map.base[0]),(world.x+world.y)*16+int(map.base[1])-h*8)-camera

func screen_to_cell(point: Vector2) -> Vector2i:
	if map.is_empty():
		return Vector2i(-1,-1)
	var side = int(map.side)
	for diagonal in range(2*side-2,-1,-1):
		for x in range(mini(side-1,diagonal)+1):
			var cell = Vector2i(x,diagonal-x)
			if not _cells.has(cell):
				continue
			var c: Array = _cells[cell]
			if int(c[3]) != 0 or int(c[4]) != 0:
				continue
			var delta = Vector2i(point)-world_to_screen(cell)
			if absi(delta.x)+2*absi(delta.y) <= 32:
				return cell
	return Vector2i(-1,-1)

func center_on_unit(slot: int) -> void:
	var unit = _unit(slot)
	if unit.is_empty():
		return
	camera = world_to_screen(Vector2i(unit.x,unit.y))+camera-Vector2i(320,240)
	_clamp_camera()
	_dirty = true

func pan_camera(delta: Vector2i) -> void:
	camera += delta
	_clamp_camera()
	_dirty = true

func set_shake_amplitude(value: int) -> void:
	shake_amplitude = value
	environment.shake_amplitude = value

func apply_settings(settings: Dictionary) -> void:
	zoom.apply_settings(settings)
	_skip_effect_animation = bool(settings.get("skip_effect",false))
	_skip_palette_animation = bool(settings.get("skip_palette",false))
	_show_occluded = bool(settings.get("show_occluded",false))
	_actors.clear()
	if battle != null: _refresh_actors()
	_dirty = true

func set_display_capable(capable: bool) -> void:
	zoom.display_capable = capable

func parent_palette_cycle(substate: int = -1) -> void:
	if _skip_palette_animation or battle == null or physical.active or magic.active or _result_state >= 0: return
	if substate < 0: substate = int(battle.substate)
	if substate not in [1,2,3,4,7] or _cycle_palette.size() != 48: return
	if ((_cycle_epoch+60)&0xFFFFFFFF) > (clock_ms&0xFFFFFFFF): return
	for first in [0,8]:
		var last = _cycle_palette.slice((first+7)*3,(first+8)*3)
		for entry in range(first+7,first,-1):
			for channel in range(3): _cycle_palette[entry*3+channel] = _cycle_palette[(entry-1)*3+channel]
		for channel in range(3): _cycle_palette[first*3+channel] = last[channel]
	var target = palette.current.duplicate()
	for i in range(48): target[208*3+i] = _cycle_palette[i]
	palette.fade(target,208,16,0,clock_ms)
	_cycle_epoch = clock_ms

func set_all_actors_visible(visible: bool) -> void:
	for record in _actors.values():
		record.player.visible = visible
		if record.has("shadow"): record.shadow.visible = visible
		if record.has("icon"): record.icon.visible = visible
	for record in _script.get("players",{}).values(): record.player.visible = visible
	for player in _script_unit78.values(): player.visible = visible
	if not magic.caster.is_empty(): magic.caster.player.visible = visible
	_dirty = true

func set_animation_enabled(enabled: bool) -> void:
	#41AED0: enabling rebuilds each occupied unit's appearance; disabling
	# freezes only Unit70/78. Unit74 shadows retain their own animation flags.
	if enabled and not _skip_effect_animation:
		for slot in _actors.keys(): _refresh_actor(int(slot))
		return
	for record in _actors.values():
		record.player.activate(128)
		if record.has("icon"): record.icon.activate(128)
	for record in _script.get("players",{}).values(): record.player.activate(128)
	for player in _script_unit78.values(): player.activate(128)
	if not magic.caster.is_empty(): magic.caster.player.activate(128)

func refresh_all_actors() -> void:
	#419790 performs4196F0 per occupied unit, including its visibility policy.
	for slot in _actors.keys(): _refresh_actor(int(slot))

func refresh_actor_visual(slot: int) -> void:
	#4196F0 only; EVENT override ownership is not erased by this service.
	_refresh_actor(slot)

func remove_actor_visual(slot: int) -> void:
	#41A9E0/41AB30 release the removed unit's visual handles.
	_actors.erase(slot)
	_script.get("players",{}).erase(slot)
	_script.get("overrides",{}).erase(slot)
	_script_commands_seen.erase(slot)
	_script_unit78.erase(slot)
	_dirty = true

func sync_actor_visuals() -> void:
	_refresh_actors()
	_dirty = true

func draw_tactical_now() -> void:
	#408580(0), not408A50: draw/present only. The draw itself retains the
	# original optional camera-shake RNG; there is no APD/environment/audio tick
	# and no unconditional42F410(0) frame-service RNG tail.
	var previous_mode = _service_mode
	var previous_rng = _last_service_rng
	var previous_override = _normal_draw_override
	_service_mode = "normal"
	_last_service_rng = true
	_normal_draw_override = true
	_render()
	_service_mode = previous_mode
	_last_service_rng = previous_rng
	_normal_draw_override = previous_override

func set_modifier_keys(shift: bool, _control: bool = false) -> void:
	if shift_held != shift:
		shift_held = shift
		_dirty = true

func _fx_world_to_screen(world: Vector2i) -> Vector2i:
	return world_to_screen(world)-_shake_delta

func _world_pixel(world: Vector2i) -> Vector2i:
	return world_to_screen(world)+camera

func _physical_camera_focus(focus: Vector2i) -> void:
	camera = focus-Vector2i(320,240)
	_clamp_camera()
	_dirty = true

func _clamp_camera() -> void:
	if not _baked.is_empty():
		camera.x = clampi(camera.x,0,maxi(0,int(_baked.width)-640))
		camera.y = clampi(camera.y,0,maxi(0,int(_baked.height)-480))

func _unit(slot: int) -> Dictionary:
	if battle == null or slot < 0 or slot >= battle.units.size():
		return {}
	return data.decode_unit(battle.units[slot],slot)

func _refresh_actors() -> void:
	var live: Dictionary = {}
	var races = data.load_table("race")
	var items: PackedByteArray = data.raw_table("item")
	for slot in range(battle.units.size()):
		if _magic_deferred_targets.has(slot) and _actors.has(slot):
			live[slot]=_actors[slot];continue
		var u = _unit(slot)
		var definition = int(u.definition_id)
		if int(u.kind) == 0 or definition == 7 or definition >= races.size():
			continue
		var direction = int(u.direction)
		var control = int(u.control)
		var state = int(u.state)
		if state == 0:
			for equipment in [u.weapon,u.armor,u.accessory1,u.accessory2]:
				var ability_offset = int(equipment)*56+52
				if ability_offset+2 <= items.size() and items.decode_u16(ability_offset) == 11:
					state = 11
		var mirror = 16 if direction == 1 or direction == 2 else 0
		if definition == 23 or definition == 73:
			mirror = 0
		var prefix = "F." if direction <= 1 else "B."
		var label = "STAND"
		var flags = mirror | 128
		var animate = game_mode == 4 or not _skip_effect_animation
		var inactive = game_mode == 4 and int(u.kind) != 8 and int(u.kind) < 30 and int(u.move_marker) != 0 and int(u.action_marker) != 0
		if inactive:
			state = 9 if state == 9 else 0
		if state in [0,6,7]:
			if inactive and control != 7 and definition != 23 and definition != 73:
				label = "SET"
			elif int(u.move_marker) != 0 and int(u.action_marker) != 0 and control != 7:
				label = "COMPLETE" if control == 0 else "STAND"
			else:
				flags = mirror | 3 if animate else mirror | 128
		elif state == 9:
			label = "HIDE" if control == 7 else ""
			flags = mirror | 3
		elif state == 11:
			label = "LEVITATE"
			flags = mirror | 3 if animate else mirror | 128
		else:
			label = "DEAD" if state == 1 and control == 0 else "S/DAMAGE" if state == 4 else "A/DAMAGE" if state == 5 else "DOWN_DAMAGE"
		var letter = "V" if game_mode == 4 and int(u.kind) != 8 and int(u.kind) < 30 and definition not in [23,72,73] else "A"
		var stem = "CHAR_%02d%s" % [definition,letter]
		#419117/11A: a loaded definition resource wins over the requested letter.
		# Entering an EVENT does not turn an existing A cache into a V resource.
		stem = str(_actor_resource_stems.get(definition,stem))
		if game_mode == 4 and stem.ends_with("V") and not assets.manifest.get("apds",{}).has(stem) and assets.manifest.get("apds",{}).has("CHAR_%02dA" % definition):
			#419140..419157 returns0 before sprite creation when the requested V
			# file is absent. Keep45EAD0 empty; never substitute the A resource.
			actor_resource_load_failures[stem] = {"return_handle":0,"mode":4,"definition":definition,"slot":slot,"source":"419140..419157 optional file load failure","substitute_loaded":false}
			if _actors.has(slot): live[slot] = _actors[slot] # NULL returns before releasing an existing Unit70/74/78.
			continue
		var dataset = assets.apd(stem)
		if not dataset.is_empty(): _actor_resource_stems[definition] = stem
		if game_mode != 4 and actor_resource_load_failures.has("CHAR_%02dV" % definition): actor_resource_load_failures["CHAR_%02dV" % definition]["later_loaded_resource"] = stem
		var signature = stem+prefix+label+str(flags)
		if _actors.has(slot) and _actors[slot].signature == signature:
			live[slot] = _actors[slot]
		else:
			var player: FT2APDPlayer = _actors[slot].player if _actors.has(slot) and _actors[slot].stem == stem else FT2APDPlayer.new()
			for sheet in dataset.get("sheets",[]):
				var image = assets.apd_image(str(sheet),[[10,64,144]])
				if not image.is_empty():
					var band = assets.apd_palette_band(str(sheet),144,64)
					_install_once(image,band.x,band.y)
			if label != "":
				player.play(dataset,prefix+label,clock_ms,flags,true)
			else:
				player.visible = false
			live[slot] = {"player":player,"signature":signature,"stem":stem,"priority":4,"slot":slot}
		var icon_label = "DEAD" if state == 1 and control == 0 else "POISON" if state == 2 else "SLEEP" if state == 3 else "SILENCE" if state == 6 else "CHARM" if state == 7 else ""
		if icon_label != "":
			if not live[slot].has("icon") or live[slot].get("icon_label","") != icon_label:
				var icon = FT2APDPlayer.new()
				icon.play(assets.apd("SYSTEM"),icon_label,clock_ms,3)
				live[slot]["icon"] = icon
				live[slot]["icon_label"] = icon_label
			live[slot]["icon_y"] = 16 if state == 1 else 56
		else:
			live[slot].erase("icon")
		var shadow = int(races[definition].get("shadow_size_selector",0))
		if state == 9:
			shadow = 0
		elif state == 11:
			shadow -= signi(shadow)
		elif state not in [0,6,7]:
			shadow += signi(shadow)
		if shadow != 0 and map_id != 69:
			var shadow_label = "SMALL" if shadow == 1 else "MIDDLE" if shadow == 2 else "LARGE" if shadow == 3 else "HUGE"
			if not live[slot].has("shadow") or live[slot].get("shadow_label","") != shadow_label:
				var player = FT2APDPlayer.new()
				player.play(assets.apd("SYSTEM"),shadow_label,clock_ms,128)
				live[slot]["shadow"] = player
				live[slot]["shadow_label"] = shadow_label
		else:
			live[slot].erase("shadow")
	_actors = live

func set_overlay(commands: Array) -> void:
	_overlay = commands
	_dirty = true

func set_facing_choice(direction: int) -> void:
	if facing_choice != direction:
		facing_choice = direction
		_dirty = true

func set_pointer_cell(cell: Vector2i) -> void:
	if pointer_cell != cell:
		pointer_cell = cell
		_dirty = true

func measure_text(raw_text: String, style: Dictionary) -> Dictionary:
	return font.measure(raw_text,style)

func unit_preview(slot: int, pos: Vector2i, fresh_front: bool = false) -> Dictionary:
	if not _actors.has(slot):
		return {}
	var record: Dictionary = _actors[slot]
	var label = str(record.player.label).trim_suffix("#")
	if fresh_front:
		#41D3ED copies the unit, forces direction0 and clears its three handles
		#before4196F0. A list portrait must not inherit a walking/attack frame.
		var unit = _unit(slot)
		var state = int(unit.state)
		var inactive=game_mode==4 and int(unit.kind)!=8 and int(unit.kind)<30 and int(unit.move_marker)!=0 and int(unit.action_marker)!=0
		if inactive:state=9 if state==9 else 0
		if state == 0 and not inactive:
			for equipment in [unit.weapon,unit.armor,unit.accessory1,unit.accessory2]:
				if battle.rules.items.decode_u16(int(equipment)*56+52)==11:state=11
		if state in [0,6,7]:
			label = "SET" if inactive and int(unit.control)!=7 and int(unit.definition_id) not in [23,73] else ("COMPLETE" if int(unit.move_marker)!=0 and int(unit.action_marker)!=0 and int(unit.control)==0 else "STAND")
		elif state==9:label="HIDE" if int(unit.control)==7 else ""
		elif state==11:label="LEVITATE"
		else:label="DEAD" if state==1 and int(unit.control)==0 else ("S/DAMAGE" if state==4 else ("A/DAMAGE" if state==5 else "DOWN_DAMAGE"))
		if label!="":label="F."+label
	if label == "":
		return {}
	if label.begins_with("B."):
		label = "F."+label.substr(2)
	var player = FT2APDPlayer.new()
	if not player.play(assets.apd(str(record.stem)),label,clock_ms,128,true):
		return {}
	return {"op":"apd","stem":str(record.stem),"label":player.label,"frame":player.frame,"pos":pos,"mirror":false}

func set_script_state(state: Dictionary) -> void:
	var generation = int(state.get("actor_cache_generation",_actor_cache_generation))
	var cache_reset = generation != _actor_cache_generation
	if cache_reset:
		_actor_cache_generation = generation
		_actor_resource_stems.clear()
		_actors.clear()
		_script_commands_seen.clear()
		_script_variant_commands_seen.clear()
		_script_unit78.clear()
	var npc_generation = int(state.get("actor_npc_cache_generation",_actor_npc_cache_generation))
	if npc_generation != _actor_npc_cache_generation:
		_actor_npc_cache_generation = npc_generation
		for definition in _actor_resource_stems.keys():
			if int(definition) >= 10: _actor_resource_stems.erase(definition)
		for slot in _actors.keys():
			if int(slot) >= 10: _actors.erase(slot)
		for slot in _script_unit78.keys():
			if int(slot) >= 10: _script_unit78.erase(slot)
		for slot in _script_commands_seen.keys():
			if int(slot) >= 10: _script_commands_seen.erase(slot)
		for slot in _script_variant_commands_seen.keys():
			if int(slot) >= 10: _script_variant_commands_seen.erase(slot)
		for slot in _script.get("players",{}).keys():
			if int(slot) >= 10: _script.players.erase(slot)
	var previous = {} if cache_reset else _script.get("players",{})
	_script = state.duplicate()
	game_mode = int(state.get("mode",game_mode))
	_script["players"] = {}
	_script["overrides"] = {}
	for actor in state.get("sprites",[]):
		var id = int(actor.get("id",0))
		var serial = int(actor.get("command_serial",0))
		var fields: Array = actor.get("changed_fields",[])
		if actor.has("variant") and "variant" in fields and "stem" in fields:
			if cache_reset: _script_variant_commands_seen[id] = serial
			elif serial > int(_script_variant_commands_seen.get(id,-1)):
				_script_variant_commands_seen[id] = serial
				var unit = _unit(id)
				if not unit.is_empty() and int(unit.definition_id) != 7:
					# OP07/419750 releases45EAD0[def], then419060 loads the requested variant.
					var definition = int(unit.definition_id)
					var stem = "CHAR_%02d%s" % [definition,str(actor.variant).to_upper()]
					_actor_resource_stems.erase(definition)
					if assets.manifest.get("apds",{}).has(stem):
						_actor_resource_stems[definition] = stem
						_refresh_actor(id)
					else:
						actor_resource_load_failures[stem] = {"return_handle":0,"mode":game_mode,"definition":definition,"slot":id,"source":"419750/419140 failed forced variant; old Unit70 retained","substitute_loaded":false}
						if _actors.has(id): actor = actor.duplicate(); actor["player_override"] = _actors[id].player
						else: continue
			# The setter owns the new Unit70. An older inactive job snapshot must
			# not override it with its previous APD/player while OP07 remains current.
			if serial == int(_script_variant_commands_seen.get(id,-1)) and not _unit(id).is_empty() and int(_unit(id).definition_id) != 7:
				if _actors.has(id):
					actor = actor.duplicate()
					actor["stem"] = str(_actors[id].stem)
					actor["player_override"] = _actors[id].player
				else: continue
		if str(actor.get("stem","")) == "":
			if actor.has("player_override"):
				var external = {"player":actor.player_override,"signature":"external","notified":false,"actor":actor,"external":true}
				_script.players[id] = external
				continue
			_script.overrides[id] = actor
			continue
		if actor.has("player_override"):
			_script.players[id] = {"player":actor.player_override,"signature":"external","notified":false,"actor":actor,"external":true}
			continue
		var signature = str(actor.get("stem",""))+str(actor.get("label",""))+":"+str(actor.get("flags",1))+":"+str(actor.get("restart_serial",0))
		var record: Dictionary
		if previous.has(id) and previous[id].signature == signature:
			record = previous[id]
		else:
			var player = FT2APDPlayer.new()
			player.play(assets.apd(str(actor.get("stem",""))),str(actor.get("label","")),clock_ms,int(actor.get("flags",1)) | (16 if actor.get("mirror",false) else 0))
			record = {"player":player,"signature":signature,"notified":false}
		record["actor"] = actor
		record.player.visible = bool(actor.get("visible",true))
		if actor.has("dither") and not actor.has("dither_kind") and not actor.has("dither_target"): record.player.dither = int(actor.dither)
		record.player.base_flip = 2 if actor.get("flip_y",false) else 0
		_script.players[id] = record
	var visible_mode = game_mode
	var cache_mode = int(state.get("actor_cache_mode",game_mode))
	if cache_reset: game_mode = cache_mode
	if not (cache_mode < 0 and (cache_reset or visible_mode == 9)): _refresh_actors() # Town hide41AB80 remains released until show/next EVENT.
	game_mode = visible_mode
	for actor in state.get("sprites",[]): _apply_script_actor_properties(actor)
	_dirty = true

func _apply_script_actor_properties(actor: Dictionary) -> void:
	var id = int(actor.get("id",-1))
	var record: Dictionary = _script.players.get(id,_actors.get(id,{}))
	if record.is_empty(): return
	var player: FT2APDPlayer = record.player
	var base: Dictionary = _actors.get(id,{})
	var serial = int(actor.get("command_serial",actor.get("restart_serial",0)))
	var fresh = not _script_commands_seen.has(id) or int(_script_commands_seen[id]) != serial
	var fields: Array = actor.get("changed_fields",actor.keys())
	if fresh:
		_script_commands_seen[id] = serial
		if (actor.has("dither_target") and "dither_target" in fields) or (actor.has("dither_kind") and "dither" in fields):
			var target = int(actor.get("dither_target",actor.get("dither_kind",8)))
			var interval = int(actor.get("dither_interval",actor.get("dither",0)))
			var players: Array = [player]
			if base.has("shadow"): players.append(base.shadow)
			for faded in players:
				if target == 0: faded.dither = 8 #43F70B/719, before decreasing fade request.
				else: faded.visible = true #43F69E/6AC explicitly shows body+shadow.
				faded.fade_dither(target == 8,interval,clock_ms)
		elif actor.has("dither") and "dither" in fields:
			player.dither = int(actor.dither)
		if actor.has("activate_flags") and "activate_flags" in fields: player.activate(int(actor.activate_flags))
		elif not actor.has("stem") and actor.has("flags") and "flags" in fields: player.activate(int(actor.flags))
		if actor.has("screen_offset") and "screen_offset" in fields:
			record["base_adjust"] = record.get("base_adjust",Vector2i.ZERO)+player.offset+Vector2i(actor.screen_offset)
			record["adjust_camera"] = camera
		if actor.get("overlay",false) and "overlay" in fields:
			var unit = _unit(id)
			if not unit.is_empty():
				var direction = int(unit.direction)
				var sweat = FT2APDPlayer.new()
				sweat.play(assets.apd("SYSTEM"),("F." if direction <= 1 else "B.")+"SWEAT",clock_ms,1|(16 if direction in [1,2] else 0))
				_script_unit78[id] = sweat
	if actor.has("priority"): record["priority"] = int(actor.priority)
	if actor.has("visible") and ("visible" in fields or not fresh):
		player.visible = bool(actor.visible)
		for name in ["shadow","icon"]:
			if base.has(name): base[name].visible = bool(actor.visible)
		if _script_unit78.has(id): _script_unit78[id].visible = bool(actor.visible)
	if base.has("shadow"):
		if actor.has("shadow_visible"): base.shadow.visible = bool(actor.shadow_visible)
		elif actor.has("shadow"): base.shadow.visible = bool(actor.shadow)

func set_game_mode(mode: int) -> void:
	if game_mode != mode:
		game_mode = mode
		if battle != null:
			_refresh_actors()
		_dirty = true

func unit_player(slot: int) -> FT2APDPlayer:
	# Native Unit70 is one persistent pool object across actor-job path steps.
	if _script.get("players",{}).has(slot): return _script.players[slot].player
	return _actors[slot].player if _actors.has(slot) else null

func script_actor_busy(slot: int, include_overlay: bool = false) -> bool:
	var player = unit_player(slot)
	if player == null: return true # Native42E350(invalid Unit70 handle) returns−1.
	if player != null and (player.busy or player.dither_busy): return true
	#43DDF5..DE40: shadow is not a wait predicate; Unit78 contributes animation only.
	if include_overlay:
		var overlay: FT2APDPlayer = _script_unit78.get(slot)
		if overlay == null and _actors.has(slot): overlay = _actors[slot].get("icon")
		if overlay != null and overlay.busy: return true
	return false

func restore_script_actor(slot: int) -> void:
	var unit = _unit(slot)
	if not unit.is_empty() and int(unit.definition_id) == 7:
		#419060 skips temporary definition7; its current Unit70 remains owned.
		return
	_script.get("players",{}).erase(slot)
	_script.get("overrides",{}).erase(slot)
	_script_commands_seen.erase(slot)
	_script_variant_commands_seen.erase(slot)
	_refresh_actor(slot) #43DE46→4196F0; reconstructed Unit74 is at the logical cell.
	_dirty = true

func request_camera(request: Dictionary) -> void:
	if request.get("kind","") == "actor":
		center_on_unit(int(request.get("slot",0)))
		camera_finished.emit()
	elif request.get("kind","") == "cell":
		var cell: Vector2i = request.get("cell",Vector2i.ZERO)
		camera = world_to_screen(cell)+camera-Vector2i(320,240)
		_clamp_camera()
		camera_finished.emit()
	else:
		_camera_motion = request.duplicate()
		_camera_motion["epoch"] = clock_ms
		_camera_motion["previous_distance"] = 0
		var target: Vector2i = request.get("target",Vector2i.ZERO)
		_camera_motion["target_pixel"] = Vector2i(-1,-1) if target == Vector2i.ZERO else world_to_screen(target)+camera
		if int(request.get("interval",0)) <= 0:
			_camera_motion.clear()
			camera_finished.emit()

func camera_request(request: Dictionary) -> void:
	request_camera(request)

func palette_request(request: Dictionary) -> void:
	var kind = str(request.get("kind",""))
	if kind == "surface_fill":
		source_surface_fill(int(request.get("color",0)),bool(request.get("present",true)))
		return
	if kind == "reset_ranges":
		# SYS20 /43F933: two immediate NULL-target restores, not a full reset.
		palette.fade(PackedByteArray(),16,16,0,clock_ms)
		palette.fade(PackedByteArray(),144,64,0,clock_ms)
		_dirty = true
		return
	var first = int(request.get("start",10))
	var count = int(request.get("count",236))
	var interval = int(request.get("interval",0))
	if kind in ["black","white"]:
		var black = PackedByteArray()
		black.resize(768)
		black.fill(255 if kind == "white" else 0)
		palette.fade(black,first,count,interval,clock_ms)
	elif kind == "restore":
		palette.fade(palette.base.duplicate(),first,count,interval,clock_ms)
	elif kind == "bitmap":
		var image = assets.image(str(request.get("key","")),request.get("remaps",[[10,208,32]]))
		if not image.is_empty():
			palette.install_base(image.palette,int(request.get("base_start",32)),int(request.get("base_count",208)))
			palette.fade(PackedByteArray(),first,count,interval,clock_ms)
	elif kind in ["copy_bitmap_base","copy_bitmap"]:
		var image = assets.image(str(request.get("key","")),request.get("remaps",[]))
		if not image.is_empty(): palette.install_base(image.palette,first,count)
	elif kind == "fill":
		var target = palette.base.duplicate()
		var rgb = request.get("rgb",[0,0,0])
		for entry in range(maxi(0,first),mini(256,first+count)):
			for channel in range(3):
				target[entry*3+channel] = mini(255,int(rgb[channel]))&255
		palette.install_base(target,first,count)
		#427420/427470 realize ALL playable colors after changing BASE entries.
		palette.fade(PackedByteArray(),10,236,0,clock_ms)
	elif kind == "set_entry":
		var index = clampi(int(request.get("index",0)),0,255)
		var target = palette.base.duplicate()
		var rgb = request.get("rgb",[0,0,0])
		for channel in range(3):
			target[index*3+channel] = mini(255,int(rgb[channel]))&255
		#4273C0/409460/417EF0 change BASE only; no implicit hardware write.
		palette.install_base(target,index,1)
	elif kind == "rotate":
		var target = palette.base.duplicate()
		var shift = int(request.get("shift",0))
		for entry in range(count):
			var source = posmod(entry-shift,count)+first
			for channel in range(3):
				target[(first+entry)*3+channel] = palette.base[source*3+channel]
		palette.install(target,first,count)
	elif kind == "apd_palette":
		var apd = assets.apd(str(request.get("stem","")))
		if not apd.is_empty():
			for sheet in apd.sheets:
				var image = assets.apd_image(str(sheet),request.get("remaps",[]))
				if not image.is_empty():
					#429CA1 snapshots only the caller's range;429EC0 restores that
					#range. A Z sheet contributes only its intersection with208..223.
					var band_first = maxi(first,208) if assets.is_apd_z_sheet(str(sheet)) else first
					var band_end = mini(first+count,224) if assets.is_apd_z_sheet(str(sheet)) else first+count
					if band_end > band_first: palette.install_base(image.palette,band_first,band_end-band_first)
	elif kind == "brightness":
		palette.brightness(first,count,int(request.get("percent",100)),interval,clock_ms)
	elif kind == "tint":
		var target = palette.base.duplicate()
		var tint_first = int(request.get("tint_start",first))
		var tint_count = int(request.get("tint_count",count))
		var transform = str(request.get("transform",""))
		for entry in range(maxi(0,tint_first),mini(256,tint_first+tint_count)):
			var p = entry*3
			var r = int(target[p])
			var g = int(target[p+1])
			var b = int(target[p+2])
			if transform == "warm":
				r = mini(255,int(r*120/100)); g = int(g*80/100); b = int(b*80/100)
			elif transform == "cool":
				b = int(b*60/100); g = int(g*80/100); r = mini(255,r+int(b/2))
			elif transform == "night":
				r = int(r*60/100); g = int(g*60/100); b = int(b*90/100)
			elif transform == "whiten":
				r = int((r+255)/2); g = int((g+255)/2); b = int((b+255)/2)
			target[p] = r; target[p+1] = g; target[p+2] = b
		if transform == "whiten":
			palette.install(target,tint_first,tint_count)
		palette.fade(target,first,count,interval,clock_ms)
	else:
		unsupported["palette:"+kind+str(request.get("selector",""))] = request
	_dirty = true

func source_surface_fill(color: int, present: bool = true) -> void:
	# SYS24/30 directly write44A288 then4189A0; this is a one-shot surface operation.
	surface.clear(color)
	if present:
		_base_image = Image.create_from_data(640,480,false,Image.FORMAT_L8,surface.native_image().get_data())
		_upload_surface()
	_dirty = false

func service_experience_commands(commands: Array, source_sound_sink: Callable = Callable()) -> Array:
	#414B90 modifies main44A288/backdrop4499D0 in place. Keep these operations
	# separate from the normal scene rebuild and from the persistent UI overlay.
	var unhandled: Array = []
	for command in commands:
		match str(command.get("op","")):
			"panel":
				for draw in preload("res://scripts/ui/ft2_widgets.gd").game_panel(int(command.x),int(command.y),int(command.width),int(command.height)):
					_draw_overlay(draw)
			"font": _experience_font = command.duplicate()
			"text":
				var text = str(command.format) % int(command.value)
				_draw_overlay({"op":"text","text":text,"raw_text":text,"pos":Vector2i(int(command.x),int(command.y)),"font":{"family":"바탕","height":int(_experience_font.get("height",16)),"weight":700,"italic":false},"color":int(_experience_font.get("color",30)),"decor":{"style":int(_experience_font.get("style",1))}})
			"blit":
				var source: Dictionary = {}
				match str(command.source):
					"main": source = {"width":640,"height":480,"pixels":surface.pixels.duplicate()}
					"backdrop":
						if _source_backdrop != null: source = _source_backdrop_data
					"system": source = assets.image("sprite/system.bmp",[[90,16,208],[10,64,144],[74,16,16]])
					"wall": source = assets.image("bmp/wall.bmp") #44A3AC, EXP strips at y160..192.
				if source.is_empty(): continue
				var rect = Rect2i(0,0,int(source.width),int(source.height))
				if command.get("rect") != null:
					var r: Array = command.rect
					rect = Rect2i(int(r[0]),int(r[1]),int(r[2])-int(r[0]),int(r[3])-int(r[1]))
				var key = int(source.pixels[0]) if int(command.get("keyed",0)) != 0 else -1
				if str(command.source) == "wall" and int(command.get("keyed",0)) != 0: key = 5 #41AD38 sets this explicitly.
				var pos = Vector2i(int(command.get("x",0)),int(command.get("y",0)))
				if str(command.destination) == "main": surface.blit(source,rect,pos,key)
				else:
					var destination = FT2IndexedSurface.new()
					if _source_backdrop != null: destination.pixels = _source_backdrop.get_data()
					destination.blit(source,rect,pos,key)
					_set_source_backdrop(destination.pixels)
			"clear":
				if str(command.get("surface","")) == "backdrop":
					var bytes = PackedByteArray(); bytes.resize(640*480); bytes.fill(int(command.get("color",0)))
					_set_source_backdrop(bytes)
				else: surface.clear(int(command.get("color",0)))
			"present":
				_base_image = Image.create_from_data(640,480,false,Image.FORMAT_L8,surface.pixels)
				_upload_surface(); _dirty = false
			"party_ui_refresh": set_animation_enabled(bool(command.get("value",1)))
			_:
				if str(command.get("op","")).begins_with("sound_") and source_sound_sink.is_valid(): source_sound_sink.call(command)
				else: unhandled.append(command)
	return unhandled

func _set_source_backdrop(bytes: PackedByteArray) -> void:
	_source_backdrop = Image.create_from_data(640,480,false,Image.FORMAT_L8,bytes)
	_source_backdrop_data = {"width":640,"height":480,"pixels":bytes,"$image":_source_backdrop}

func service_message_presentation(operation: String, request: Dictionary) -> void:
	#430750 uses persistent4499D0, with408580 draw-only at entry and exit.
	#4186F0 Restore is a no-op for resident CPU surfaces; retain its ordering.
	if bool(request.get("source_format_null",false)): return
	if operation not in ["begin","end"]:
		unsupported["message_presentation:"+operation] = request
		return
	for name in ["restore_backdrop","restore_main","clear_backdrop"]:
		message_surface_events.append({"now":clock_ms,"op":name,"stage":operation})
	var backdrop = FT2IndexedSurface.new(640,480,0)
	if operation == "begin":
		var original_surface = surface
		surface = backdrop
		for command in request.get("commands",[]): _draw_overlay(command)
		surface = original_surface
		message_surface_events.append({"now":clock_ms,"op":"draw_backdrop","stage":operation})
	_set_source_backdrop(backdrop.pixels)
	draw_tactical_now()
	message_surface_events.append({"now":clock_ms,"op":"draw_tactical","stage":operation})
	if message_surface_events.size() > 2000: message_surface_events = message_surface_events.slice(-2000)

func service_script_commands(commands: Array) -> Array:
	#43D1F0 command order is authoritative. Paint persistent4499D0 or main44A288
	# now; do not reconstruct old VM snapshots after another caller clears them.
	var unhandled: Array = []
	for command in commands:
		var op = str(command.get("op",""))
		script_surface_events.append({"now":clock_ms,"op":op,"surface":command.get("surface",""),"mode":command.get("mode",""),"draw_commands":command.get("commands",[]).size()})
		match op:
			"paint_backdrop": _paint_script_surface("backdrop",command.get("commands",[]))
			"paint_main": _paint_script_surface("main",command.get("commands",[]))
			"clear_rect":
				_paint_script_surface(str(command.get("surface","backdrop")),[{"op":"rect","rect":command.get("rect",Rect2i(0,0,640,480)),"color":int(command.get("color",0)),"filled":true}])
			"keyed_backdrop_to_main":
				if _source_backdrop != null: surface.blit(_source_backdrop_data,Rect2i(0,0,640,480),Vector2i.ZERO,0)
				_dirty = true
			"present":
				if str(command.get("mode","main")) == "tactical": draw_tactical_now()
				else:
					_base_image = Image.create_from_data(640,480,false,Image.FORMAT_L8,surface.pixels)
					_upload_surface();_dirty = false
			"restore": pass #4186F0 is resident-CPU no-op; never a clear.
			_:
				unhandled.append(command)
				unsupported["script_surface:"+op] = command
	if script_surface_events.size() > 2000: script_surface_events = script_surface_events.slice(-2000)
	return unhandled

func _paint_script_surface(target: String, commands: Array) -> void:
	if target == "main":
		for command in commands: _draw_overlay(command)
	else:
		var backdrop = FT2IndexedSurface.new(640,480,0)
		if _source_backdrop != null: backdrop.pixels = _source_backdrop.get_data()
		var original_surface = surface
		surface = backdrop
		for command in commands: _draw_overlay(command)
		surface = original_surface
		_set_source_backdrop(backdrop.pixels)
	_dirty = true

func play_action(plan: Dictionary) -> void:
	_plan = plan
	if plan.get("zoom_requested",false): zoom.request(1)
	if str(plan.get("visual_kind","")) == "ko":
		_prepare_ko(plan)
		return
	if str(plan.get("visual_kind","")) == "results":
		_prepare_results(plan)
		return
	if str(plan.get("visual_kind","")) == "physical":
		if not plan.has("sprite_half_heights"):
			plan["sprite_half_heights"] = {}
			for slot in _actors:
				var player: FT2APDPlayer = _actors[slot].player
				if player.frame >= 0 and player.frame < player.apd.get("frames",[]).size():
					var bounds = player.apd.frames[player.frame].bounds
					plan.sprite_half_heights[slot] = int((int(bounds[3])-int(bounds[1]))/2)
		var program: Dictionary = plan.get("visual_program",{})
		if program.is_empty() and physical_builder != null:
			program = physical_builder.build(plan)
		if not program.get("error","").is_empty():
			unsupported["physical_builder"] = program.error
		else:
			_physical_sound_paths = program.get("sound_paths",[])
			for record in program.get("records",[]):
				for sheet in assets.apd(str(record.get("APD",""))).get("sheets",[]):
					var image = assets.apd_image(str(sheet),[[10,64,144]])
					if not image.is_empty():
						var band = assets.apd_palette_band(str(sheet),144,64)
						palette.install(image.palette,band.x,band.y)
						_mark_palette_loaded(image,band.x,band.y)
			if physical.play(program,clock_ms,_actors):
				_clock_pool() #439C18 initialization, no environment/RNG service.
				return
	if str(plan.get("visual_kind","")) in ["magic","item"]:
		if int(plan.get("effect_id",0)) == 82:
			_summon_precast_slots.clear()
			var before: Array = plan.get("before_units",[])
			for slot in range(mini(before.size(),battle.units.size())):
				if before[slot].decode_u16(0) == 0 and battle.units[slot].decode_u16(0) != 0 and _actors.has(slot):
					_summon_precast_slots.append(slot)
					_actors[slot].player.visible = false
					if _actors[slot].has("shadow"):
						_actors[slot].shadow.visible = false
		if magic.play(plan,battle.units,_cells,clock_ms):
			_magic_replaced_caster = not magic.caster.is_empty()
			return
		unsupported.merge(magic.unsupported,true)
		for key in magic.unsupported:
			if str(key).begins_with("original_missing_asset:"):
				# Source42C770 failed to load an original APD/sheet. Keep that
				# failure visible; it must not become a successful visual completion.
				_magic_replaced_caster=false
				return
	# A missing builder is a visible development limitation, never a fabricated effect.
	unsupported["action_builder:"+str(plan.get("effect_id",plan.get("action_id",0)))] = true
	call_deferred("_finish_unbuilt_action")

func _finish_unbuilt_action() -> void:
	visual_finished.emit()

func _prepare_ko(plan: Dictionary) -> void:
	#4147BC..4821: refresh the dead target before starting body/shadow fades.
	_ko_slots = plan.get("target_slots",[]).map(func(slot): return int(slot))
	for slot in _ko_slots:
		_refresh_actor(slot)
		if not _actors.has(slot): continue
		var record: Dictionary = _actors[slot]
		record.player.activate(1)
		record.player.fade_dither(true,100,clock_ms)
		if record.has("shadow"): record.shadow.fade_dither(true,100,clock_ms)
	_ko_active = true
	_dirty = true

func _poll_ko() -> void:
	#41472E..477A queries the previous pool state BEFORE this frame's408A50.
	if not _ko_active: return
	for slot in _ko_slots:
		if not _actors.has(slot): continue
		var record: Dictionary = _actors[slot]
		if record.player.dither_busy or (record.has("shadow") and record.shadow.dither_busy): return
	_ko_active = false
	_ko_slots.clear()
	visual_finished.emit()

func _physical_finished() -> void:
	zoom.finish_results()
	_dirty = true
	visual_finished.emit()

func _physical_cleanup_record(record: Dictionary) -> void:
	var slot = int(record.get("unit_slot",-1))
	if int(record.type) != 1:
		record.player.visible = false
	if slot >= 0 and _actors.has(slot):
		var original: FT2APDPlayer = _actors[slot].player
		if int(record.type) != 1:
			var unit = _unit(slot)
			var label = original.label
			if label.begins_with("F.") or label.begins_with("B."): label = label.substr(2)
			var direction = int(unit.direction)
			var flags = 1|(16 if direction in [1,2] and int(unit.definition_id) not in [23,73] else 0)
			original.play(original.apd,("F." if direction <= 1 else "B.")+label,clock_ms,flags)
			original.activate(128)
		original.visible = true
		physical.suppressed.erase(slot)
	_magic_nested_service("physical_cleanup%d" % int(record.record))

func _physical_sound(cache_index: int) -> void:
	if cache_index >= 0 and cache_index < _physical_sound_paths.size():
		sound_requested.emit(str(_physical_sound_paths[cache_index]),false)

func _magic_finished() -> void:
	zoom.finish_results()
	unsupported.merge(magic.unsupported,true)
	if _magic_replaced_caster:
		var slot = int(_plan.get("actor_slot",-1))
		_actors.erase(slot)
		_refresh_actors()
		_magic_replaced_caster = false
	for slot in _actors:
		if int(_unit(int(slot)).definition_id) in [23,73]: _actors[slot].player.visible = true
	_dirty = true
	visual_finished.emit()

func _magic_target_pose(slot: int) -> void:
	if not _actors.has(slot):
		return
	var u = _unit(slot)
	if int(u.state) in [4,5]:
		_refresh_actor(slot) #437A3C rebuilds this target before437A4A activation.
		if _actors.has(slot):_actors[slot].player.activate(1)
		return
	var direction = int(u.direction)
	var mirror = 16 if direction in [1,2] and int(u.definition_id) not in [23,73] else 0
	_actors[slot].player.play(assets.apd(str(_actors[slot].stem)),("F." if direction <= 1 else "B.")+"MIDDLE_DAMAGE",clock_ms,mirror)

func _refresh_actor(slot: int) -> void:
	_magic_deferred_targets.erase(slot) # Explicit native4196F0 service releases this target only.
	var unit = _unit(slot)
	if not unit.is_empty() and int(unit.definition_id) == 7: return
	if not unit.is_empty():
		var definition = int(unit.definition_id)
		var letter = "V" if game_mode == 4 and int(unit.kind) != 8 and int(unit.kind) < 30 and definition not in [23,72,73] else "A"
		var requested = str(_actor_resource_stems.get(definition,"CHAR_%02d%s" % [definition,letter]))
		if requested.ends_with("V") and not assets.manifest.get("apds",{}).has(requested) and assets.manifest.get("apds",{}).has("CHAR_%02dA" % definition):
			actor_resource_load_failures[requested] = {"return_handle":0,"mode":game_mode,"definition":definition,"slot":slot,"existing_unit70_preserved":_actors.has(slot),"source":"419140..419157 early return before release","substitute_loaded":false}
			return
	_script_unit78.erase(slot) #4196F0 deletes the previous Unit78 before appearance rebuild.
	var previous: Dictionary = _actors.get(slot,{})
	_actors.erase(slot)
	_refresh_actors()
	if not previous.is_empty() and _actors.has(slot) and previous.stem == _actors[slot].stem:
		var replacement: FT2APDPlayer = _actors[slot].player
		previous.player.play(replacement.apd,replacement.label,clock_ms,replacement.flags)
		previous.player.visible = replacement.visible #4194A1 restores Unit70 after rebuilding.
		_actors[slot].player = previous.player
		if _actors[slot].has("shadow"): previous["shadow"] = _actors[slot].shadow
	_dirty = true

func _native_wait_player(slot: int) -> FT2APDPlayer:
	_refresh_actor(slot)
	var player: FT2APDPlayer = _actors[slot].player if _actors.has(slot) else FT2APDPlayer.new()
	player.activate(1)
	return player

func _summon_fade(slots: Array) -> void:
	_summon_slots = slots
	_summon_precast_slots.clear()
	_refresh_actors()
	for slot in slots:
		if _actors.has(slot):
			_refresh_actor(slot)
			_actors[slot].player.visible = true
			_actors[slot].player.dither = 8
			_actors[slot].player.fade_dither(false,50,clock_ms)
			if _actors[slot].has("shadow"):
				_actors[slot].shadow.visible = true

func _summon_busy(result: Dictionary) -> void:
	for slot in _summon_slots:
		if _actors.has(slot) and _actors[slot].player.dither_busy:
			result.busy = true
			return

func _magic_constructor_service() -> void:
	_magic_nested_service("magic_constructor53")

func _magic_surface_request(request: Dictionary) -> void:
	var op = str(request.op)
	surface_events.append({"now":clock_ms,"op":op,"visible":request.get("visible",null)})
	if op == "visible_all":
		set_all_actors_visible(bool(request.visible))
	elif op == "clear":
		_source_backdrop = null
		_source_backdrop_data.clear()
		_dirty = true
	elif op == "capture":
		var old_override = _normal_draw_override
		var old_mode = _service_mode
		_normal_draw_override = true
		_service_mode = "normal"
		_render(false,true) #408580(nonzero destination) returns before front presentation/zoom.
		_source_backdrop = Image.create_from_data(640,480,false,Image.FORMAT_L8,surface.native_image().get_data())
		_source_backdrop_data = {"width":640,"height":480,"pixels":_source_backdrop.get_data(),"$image":_source_backdrop}
		_normal_draw_override = old_override
		_service_mode = old_mode
		_dirty = true
	elif op == "present_backdrop":
		if _source_backdrop != null:
			surface.pixels = _source_backdrop.get_data()
			_base_image = Image.create_from_data(640,480,false,Image.FORMAT_L8,_source_backdrop.get_data())
			for command in _overlay: _draw_overlay(command)
			_upload_surface()

func _magic_job_pool_service() -> void:
	_clock_pool(true)

func _clock_pool(exclude_proxy: bool = false) -> bool:
	var players: Array = []
	for record in _actors.values():
		if _summon_precast_slots.has(record.slot): continue
		if not magic.suppressed.has(record.slot) and not _script.get("players",{}).has(record.slot): players.append(record.player)
		if record.has("shadow"): players.append(record.shadow)
		if record.has("icon") and not _script_unit78.has(record.slot): players.append(record.icon)
	for player in _script_unit78.values(): players.append(player)
	for record in _script.get("players",{}).values(): players.append(record.player)
	for record in physical.records:
		if not record.deleted: players.append(record.player)
	if not magic.caster.is_empty(): players.append(magic.caster.player)
	for child in magic.children:
		for row in child.players: players.append(row.player)
	if not exclude_proxy:
		for job in magic._jobs.jobs.values(): players.append(job.player)
	if not magic._proxy.is_empty(): players.append(magic._proxy.shadow)
	for record in _result_players: players.append(record.player)
	players.append(_cursor)
	var seen: Array = []
	var changed = false
	for player in players:
		if not seen.has(player):
			changed = player.advance(clock_ms) or changed
			seen.append(player)
	return changed

func _magic_nested_service(context: String) -> void:
	if battle.frame_service_callback.is_valid():
		battle.render_service_rng(context,true)
	else:
		service_frame(context)
		battle.render_service_rng(context,false)

func _update_environment(context: String = "") -> bool:
	if map.is_empty(): return false
	var key = str(map.get("background",""))
	var bg = assets.image(key,[[10,112,32]]) if key != "map/" and key != "" else {}
	environment.rng = battle.rng
	environment.mode = 1 if context == "magic_constructor53" else 2 if physical.active else 3 if magic.active else game_mode
	environment.sound_enabled = _audio == null or bool(_audio.effects_enabled)
	var changed = environment.advance(clock_ms,int(bg.get("width",640)))
	for event in environment.events:
		if event.kind == "sound": sound_requested.emit(str(event.stem),bool(event.loop))
		elif event.kind == "palette_flash":
			var image = assets.image(str(event.key),[[10,112,32]])
			if not image.is_empty():
				palette.fade(image.palette,32,112,0,clock_ms)
				palette.fade(palette.base.duplicate(),32,176,2,clock_ms)
	battle.rng = environment.rng
	return changed

func service_frame(context: String = "") -> void:
	#408A50 service only: never dispatch438540/434880 recursively.
	if assets == null: return
	var previous_mode = _service_mode
	var previous_rng = _last_service_rng
	var previous_override = _normal_draw_override
	_service_mode = "normal"
	_last_service_rng = true
	_normal_draw_override = true
	if _audio != null and _audio.has_method("source_main_service"):
		_audio.source_main_service(clock_ms) #408AA5→401000, before environment/APD service.
	_dirty = _update_environment(context) or _dirty
	_dirty = _clock_pool() or _dirty
	if _dirty: _render()
	elif palette.dirty: _material.set_shader_parameter("palette_texture",palette.upload())
	_service_mode = previous_mode
	_last_service_rng = previous_rng
	_normal_draw_override = previous_override

func _visual_random(modulus: int) -> int:
	environment.rng = battle.rng
	var result = environment.random(modulus)
	battle.rng = environment.rng
	return result

func set_audio_backend(audio) -> void:
	_audio = audio
	magic.sound_busy = func(stem): return bool(audio.effects_enabled) and audio.is_sound_playing(stem)
	if audio.has_method("fade_music"): magic.music_fade = Callable(audio,"fade_music")
	if audio.has_method("music_fade_busy"): magic.music_busy = Callable(audio,"music_fade_busy")

func render_service_consumes_rng() -> bool:
	return _last_service_rng

func _prepare_results(plan: Dictionary) -> void:
	zoom.finish_results()
	_result_players.clear()
	_result_state = 0
	_result_epoch = clock_ms
	var apd = assets.apd("NUMBER")
	if apd.is_empty() or plan.get("results",[]).is_empty():
		_result_state = -1
		visual_finished.emit()
		return
	#413C22: copy the current scene before41AC10(0) hides all unit visuals.
	var previous_mode = _service_mode
	var previous_override = _normal_draw_override
	_service_mode = "results_capture"
	_normal_draw_override = true
	_render()
	_result_backdrop = _base_image
	_service_mode = previous_mode
	_normal_draw_override = previous_override
	set_all_actors_visible(false)
	var messages = ["STR_UP!","DEF_UP!","WIS_UP!","MGR_UP!","AGR_UP!","MISS!","WELL","HP_UP!","MP_UP!","FLY_HIGH!","LANDING!"]
	for result in plan.results:
		var target = int(result.get("target_slot",-1))
		if target < 0:
			continue
		var amount = int(result.get("amount",0))
		var labels: Array = []
		if amount < 90000:
			var value = amount if amount > 0 else (((-amount+2147483648)&0xFFFFFFFF)-2147483648)
			for digit in range(3):
				if digit == 0 or value > 0:
					labels.append(("B_POP_" if amount > 0 else "POP_")+str(value % 10))
				else:
					labels.append("")
				value = int(value / 10)
		elif amount >= 90001 and amount <= 90011:
			labels.append(str(messages[amount-90001]))
		for digit in range(labels.size()):
			if labels[digit] == "":
				continue
			var player = FT2APDPlayer.new()
			if player.play(apd,str(labels[digit]),clock_ms,1 if digit == 0 else 128):
				player.visible = digit == 0
				_result_players.append({"player":player,"target":target,"digit":digit})
	_dirty = true

func _advance_results() -> void:
	_result_tail_serviced = false
	if _result_state < 0:
		return
	if _result_state < 2 and clock_ms-_result_epoch >= 100:
		_result_state += 1
		for record in _result_players:
			if record.digit == _result_state:
				record.player.visible = true
				record.player.activate(1)
				_result_epoch = clock_ms
	elif _result_state == 2:
		var busy = false
		for record in _result_players:
			busy = busy or record.player.busy
		if not busy:
			_result_state = 3
			_result_epoch = clock_ms
	elif _result_state == 3 and clock_ms-_result_epoch >= 1000:
		_result_players.clear()
		_result_state = -1
		visual_finished.emit()
		return
	_clock_pool()
	_result_tail_serviced = true
	_dirty = true

func advance_clock(delta_ms: int) -> void:
	clock_ms += delta_ms

func advance_palette_clock() -> void:
	if palette != null:
		palette.advance(clock_ms)
		_palette_prefix_ms = clock_ms

func advance(delta_ms: int, service_mode: String = "normal") -> void:
	clock_ms += delta_ms
	if assets == null:
		return
	if service_mode != "paused" and _palette_prefix_ms != clock_ms:
		advance_palette_clock()
	_service_mode = service_mode
	if service_mode == "normal" and _result_state >= 0:
		_service_mode = "results"
	_last_service_rng = _service_mode == "normal" and not magic.direct_render()
	if _service_mode in ["paused","scene","town"]:
		if _dirty or palette.dirty:
			_render()
		return
	if _service_mode == "results":
		_advance_results()
		if _result_tail_serviced:
			_render()
		elif palette.dirty:
			_material.set_shader_parameter("palette_texture",palette.upload())
		return
	_poll_ko()
	var had_physical = physical.active
	physical.before_apd(clock_ms)
	var had_magic = magic.active
	magic.before_apd(clock_ms)
	if had_magic:
		_last_service_rng = magic.service_rng_this_tick
	for id in _script.get("players",{}):
		var record = _script.players[id]
		if record.get("external",false) or record.actor.get("externally_advanced",false):
			continue # VM alone owns job/cell transitions; global pool still clocks the APD.
		if not record.player.busy and not record.notified:
			record.notified = true
			actor_finished.emit(int(id))
	if game_mode == 4 and not _camera_motion.is_empty() and (clock_ms&0xFFFFFFFF) > ((int(_camera_motion.epoch)+int(_camera_motion.get("interval",50)))&0xFFFFFFFF):
		_camera_motion.epoch = clock_ms
		var old = camera
		camera += Vector2i(int(_camera_motion.get("dx",0)),int(_camera_motion.get("dy",0)))
		_clamp_camera()
		_dirty = true
		var stopped = camera == old
		var target: Vector2i = _camera_motion.target_pixel
		if target.x >= 0:
			var delta = camera+Vector2i(320,240)-target
			var distance = (delta.x*delta.x+delta.y*delta.y)&0xFFFFFFFF
			var previous_distance = int(_camera_motion.previous_distance)
			if previous_distance > 0 and previous_distance < distance:
				stopped = true
			_camera_motion.previous_distance = distance
		if stopped:
			_camera_motion.clear()
			camera_finished.emit()
	if had_physical:
		_magic_nested_service("physical_parent") # First408A50/RNG tail precedes439690.
		_clock_pool() #43856B second42E670; same native timestamp, no catch-up loop.
		physical.after_apd()
		_last_service_rng = false
	elif not had_magic or magic.service_rng_this_tick:
		service_frame("parent")
	elif magic.clock_this_tick:
		if magic.palette_update_this_tick: palette.advance(clock_ms)
		_dirty = _clock_pool() or _dirty
		if _dirty: _render()
	if had_magic: magic.after_service()
	var hover = screen_to_cell(get_local_mouse_position())
	if hover != _hover:
		_hover = hover
		cell_hovered.emit(hover)

func _draw_apd(player: FT2APDPlayer, anchor: Vector2i, policy: String = "actor", clip: Rect2i = Rect2i(0,0,640,480), remap_override: Variant = null, installs: Array = []) -> Rect2i:
	if not player.visible or player.frame < 0 or player.apd.is_empty() or player.frame >= player.apd.frames.size():
		return Rect2i()
	var frame: Dictionary = player.apd.frames[player.frame]
	var flip = player.effective_flip()
	var bounds = Rect2i()
	anchor += player.offset
	for index in frame.parts:
		var part: Array = player.apd.parts[int(index)]
		var remaps: Array = [[10,64,144]]
		if policy == "system":
			remaps = [[90,16,208],[10,64,144],[74,16,16]]
		elif policy == "effect":
			remaps = [[10,32,208]]
		if remap_override != null:
			remaps = remap_override
		var sheet = str(player.apd.sheets[int(part[0])])
		var image = assets.apd_image(sheet,remaps)
		if image.is_empty():
			continue
		if _frame_override_active:
			pass
		elif assets.is_apd_z_sheet(sheet):
			_install_once(image,208,16)
		elif remap_override != null:
			for install in installs:
				_install_once(image,int(install[0]),int(install[1]))
		elif policy == "effect":
			_install_once(image,208,32)
		elif policy != "cast":
			_install_once(image,144,64)
			if policy == "system":
				_install_once(image,16,16)
		var offset = Vector2i(int(part[5]),int(part[6]))
		if flip & 1:
			offset.x = -offset.x-int(part[3])
		if flip & 2:
			offset.y = -offset.y-int(part[4])
		offset.y -= int(frame.pivot)
		var rect = surface.blit(image,Rect2i(int(part[1]),int(part[2]),int(part[3]),int(part[4])),anchor+offset,int(part[7]),flip,int(DITHER[clampi(player.dither,0,8)]),clip)
		bounds = rect if bounds.size == Vector2i.ZERO else bounds.merge(rect)
	return bounds

func _install_once(image: Dictionary, first: int, count: int) -> void:
	var key = str(image.get("signature",image.get("key","")))+":"+str(first)+":"+str(count)
	if not _installed.has(key):
		palette.install(image.palette,first,count)
		_installed[key] = true

func _mark_palette_loaded(image: Dictionary, first: int, count: int) -> void:
	var key = str(image.get("signature",image.get("key","")))+":"+str(first)+":"+str(count)
	_installed[key] = true

func _exchange_sort(records: Array, primary: String, secondary: String) -> void:
	for i in range(records.size()):
		for j in range(i+1,records.size()):
			if records[j][primary] < records[i][primary] or (records[j][primary] == records[i][primary] and records[j][secondary] < records[i][secondary]):
				var old = records[i]
				records[i] = records[j]
				records[j] = old

func _drawable_rect(record: Dictionary) -> Rect2i:
	var player: FT2APDPlayer = record.player
	if not player.visible or player.frame < 0 or player.frame >= player.apd.get("frames",[]).size():
		return Rect2i()
	var frame: Dictionary = player.apd.frames[player.frame]
	var bounds = frame.bounds
	var flip = player.effective_flip()
	var point: Vector2i = record.anchor+player.offset
	point.x += -int(bounds[2]) if flip&1 else int(bounds[0])
	point.y += (-int(bounds[3]) if flip&2 else int(bounds[1]))-int(frame.pivot)
	return Rect2i(point,Vector2i(int(bounds[2])-int(bounds[0]),int(bounds[3])-int(bounds[1]))).intersection(Rect2i(0,0,640,480))

func _redraw_map(diagonal: int, group: int, dirty: Array) -> void:
	if dirty.is_empty():
		return
	for x in range(maxi(0,diagonal-int(map.side)+1),mini(int(map.side)-1,diagonal)+1):
		var cell = Vector2i(x,diagonal-x)
		if not _cells.has(cell):
			continue
		var c: Array = _cells[cell]
		var row_height = int(_cells.get(Vector2i(0,diagonal),[0,0,0])[2])
		var anchor = world_to_screen(cell)-Vector2i(0,row_height*8)
		for part in c[6]:
			if (int(part[1]) == 0) != (group == 0):
				continue
			var image = assets.image(str(map.atlases[int(part[0])]),[[10,112,32]])
			if image.is_empty():
				continue
			var rect = Rect2i(int(part[2]),int(part[3]),int(part[4])-int(part[2]),int(part[5])-int(part[3]))
			for d in dirty:
				if int(d.depth) <= diagonal:
					surface.blit(image,rect,anchor+Vector2i(int(part[6]),int(part[7])),int(image.map_key),0,0,d.rect,shift_held or (_show_occluded and game_mode == 1),camera)

func _render(present: bool = true, copy_mode: bool = false) -> void:
	if _service_mode == "results" and _result_backdrop != null:
		surface.pixels = _result_backdrop.get_data()
		var popups: Array = []
		for record in _result_players:
			var u = _unit(int(record.target))
			var pos = world_to_screen(Vector2i(u.x,u.y))+Vector2i(8-16*int(record.digit),-64)
			if record.player.visible:
				popups.append({"player":record.player,"anchor":pos,"priority":5,"screen_y":pos.y+record.player.offset.y})
		_exchange_sort(popups,"priority","screen_y")
		for record in popups: _draw_apd(record.player,record.anchor)
		_base_image = Image.create_from_data(640,480,false,Image.FORMAT_L8,surface.native_image().get_data())
		for command in _overlay: _draw_overlay(command)
		_upload_surface()
		_dirty = false
		return
	if _service_mode == "paused" and _base_image != null:
		surface.pixels = _base_image.get_data()
		for command in _overlay:
			_draw_overlay(command)
		_upload_surface()
		_dirty = false
		return
	var old_camera = camera
	_shake_delta = Vector2i.ZERO
	if shake_amplitude != 0 and _service_mode == "normal" and _last_service_rng and not map.is_empty() and not _frame_override_active:
		camera += Vector2i(_visual_random(shake_amplitude+1)-int(float(shake_amplitude)/2.0),_visual_random(shake_amplitude*2+1)-shake_amplitude)
		_clamp_camera()
		_shake_delta = old_camera-camera
	surface.clear(0)
	var tactical = _service_mode not in ["scene","town"]
	var direct = tactical and magic.direct_render() and not _normal_draw_override
	if direct and _source_backdrop != null: surface.pixels = _source_backdrop.get_data()
	if not map.is_empty() and tactical and not direct:
		var background_key = str(map.get("background",""))
		var bg = assets.image(background_key,[[10,112,32]]) if background_key != "map/" and background_key != "" else {}
		var header: Array = map.header
		var pos = Vector2i(int(header[2])*32+320,int(header[3])*16+240)
		if int(header[0]) != 0:
			pos.x += int(float(-320-camera.x)/float(header[0]))
		if int(header[1]) != 0:
			pos.y += int(float(-240-camera.y)/float(header[1]))
		if not bg.is_empty():
			var rotation = int(environment.row_rotation)%int(bg.width)
			if rotation == 0:
				surface.blit(bg,Rect2i(0,0,int(bg.width),int(bg.height)),pos)
			else:
				surface.blit(bg,Rect2i(rotation,0,int(bg.width)-rotation,int(bg.height)),pos)
				surface.blit(bg,Rect2i(0,0,rotation,int(bg.height)),pos+Vector2i(int(bg.width)-rotation,0))
		for command in environment.commands(pos):
			_draw_overlay(command)
		if not _baked.is_empty():
			surface.blit(_baked,Rect2i(0,0,int(_baked.width),int(_baked.height)),-camera,0)
		if not _frame_override_active: _draw_selection()
	var drawables: Array = []
	for record in _actors.values():
		if not tactical:
			break
		if physical.suppressed.has(record.slot):
			continue
		var u = _unit(int(record.slot))
		var cell = Vector2i(u.x,u.y)
		if record.has("shadow"):
			drawables.append({"player":record.shadow,"anchor":world_to_screen(cell),"depth":cell.x+cell.y,"priority":2,"policy":"system"})
		if record.has("icon") and not _script_unit78.has(record.slot):
			drawables.append({"player":record.icon,"anchor":world_to_screen(cell)-Vector2i(0,int(record.icon_y)),"depth":cell.x+cell.y,"priority":5,"policy":"system"})
		if _script_unit78.has(record.slot):
			drawables.append({"player":_script_unit78[record.slot],"anchor":world_to_screen(cell),"depth":cell.x+cell.y,"priority":5,"policy":"system"})
		if not magic.suppressed.has(record.slot) and not _script.get("players",{}).has(record.slot):
			var adjust: Vector2i = record.get("base_adjust",Vector2i.ZERO) if record.get("adjust_camera",camera) == camera else Vector2i.ZERO
			drawables.append({"player":record.player,"anchor":world_to_screen(cell)+adjust,"depth":cell.x+cell.y,"priority":record.priority,"policy":"actor"})
	if physical.active:
		drawables.append_array(physical.drawables(Callable(self,"_fx_world_to_screen"),Callable(self,"world_to_screen")))
	if magic.active or not magic.caster.is_empty() or not magic.children.is_empty():
		drawables.append_array(magic.drawables(Callable(self,"_fx_world_to_screen"),Callable(self,"world_to_screen")))
	for record in _script.get("players",{}).values():
		if not tactical:
			break
		var actor: Dictionary = record.actor
		if not actor.get("visible",true):
			continue
		var world: Vector2i = actor.get("world",Vector2i.ZERO)
		var sort_world: Vector2i = actor.get("sort_world",world)
		var adjust: Vector2i = record.get("base_adjust",Vector2i.ZERO) if record.get("adjust_camera",camera) == camera else Vector2i.ZERO
		drawables.append({"player":record.player,"anchor":actor.get("pos",world_to_screen(world))+adjust,"depth":sort_world.x+sort_world.y,"priority":int(record.get("priority",actor.get("priority",4))),"policy":str(actor.get("policy","actor"))})
	if _frame_override_active:
		drawables = _frame_override
	# Native42E1B0/42E530 cull BEFORE the unstable exchange sort.
	drawables = drawables.filter(func(record): return _drawable_rect(record).size != Vector2i.ZERO)
	if not _frame_override_active:
		drawables.sort_custom(func(a,b): return a.player.pool_order < b.player.pool_order)
	if magic.direct_render() and not _normal_draw_override:
		for record in drawables:
			record["screen_y"] = record.anchor.y+record.player.offset.y
		_exchange_sort(drawables,"priority","screen_y")
	else:
		_exchange_sort(drawables,"depth","priority")
	var dirty: Array = []
	if not map.is_empty() and not drawables.is_empty() and (not magic.direct_render() or _normal_draw_override):
		for diagonal in range(maxi(0,int(drawables[0].depth)),2*int(map.side)-1):
			_redraw_map(diagonal,0,dirty)
			for record in drawables:
				if int(record.depth) == diagonal:
					var rect = _draw_apd(record.player,record.anchor,record.policy)
					if rect.size != Vector2i.ZERO and dirty.size() < 100:
						dirty.append({"depth":diagonal,"rect":rect})
			_redraw_map(diagonal,1,dirty)
	else:
		for record in drawables:
			_draw_apd(record.player,record.anchor,record.policy)
	var numbers: Array = []
	for record in _result_players:
		if _frame_override_active: break
		var u = _unit(int(record.target))
		var pos = world_to_screen(Vector2i(u.x,u.y))+Vector2i(8-16*int(record.digit),-64)
		numbers.append({"player":record.player,"anchor":pos,"priority":5,"screen_y":pos.y+record.player.offset.y})
	_exchange_sort(numbers,"priority","screen_y")
	for record in numbers:
		_draw_apd(record.player,record.anchor)
	if tactical and not _frame_override_active:
		_draw_facing_cursor()
	if not direct and _source_backdrop != null and not _frame_override_active:
		#4087B8..E5: surface4499D0 is drawn last with its original key0.
		surface.blit(_source_backdrop_data,Rect2i(0,0,640,480),Vector2i.ZERO,0)
	if _service_mode == "normal" and not _frame_override_active and not copy_mode:
		var presentation = zoom.presentation(false)
		if presentation.op == "stretch":
			var r = presentation.source_rect
			surface.pixels = FT2IndexedSurface.stretch_image(surface.native_image(),Rect2i(int(r[0]),int(r[1]),int(r[2])-int(r[0]),int(r[3])-int(r[1])),Vector2i(640,480)).get_data()
	if present:
		_base_image = Image.create_from_data(640,480,false,Image.FORMAT_L8,surface.native_image().get_data())
		for command in _overlay:
			_draw_overlay(command)
		_upload_surface()
	camera = old_camera
	_shake_delta = Vector2i.ZERO
	_dirty = false

func _upload_surface() -> void:
	var image = surface.native_image()
	if _texture == null:
		_texture = ImageTexture.create_from_image(image)
		_sprite.texture = _texture
	else:
		_texture.update(image)
	_material.set_shader_parameter("palette_texture",palette.upload())

func _draw_facing_cursor() -> void:
	if battle == null:
		return
	if int(battle.substate) == 2 and int(battle.selected_slot) >= 0:
		var unit = _unit(int(battle.selected_slot))
		var anchor = world_to_screen(Vector2i(unit.x,unit.y))-Vector2i(0,48)
		for direction in range(4):
			var player = FT2APDPlayer.new()
			var label = ("S." if direction == facing_choice else "")+"TURN_"+["SOUTH","EAST","WEST","NORTH"][direction]
			player.play(assets.apd("SYSTEM"),label,clock_ms,128)
			_draw_apd(player,anchor,"system")
	elif pointer_cell.x >= 0 and _cells.has(pointer_cell):
		if int(battle.substate) == 0 or battle.highlights.has(pointer_cell):
			_draw_apd(_cursor,world_to_screen(pointer_cell),"system")

func _draw_selection() -> void:
	if battle == null or int(battle.substate) == 0:
		return
	var apd = assets.apd("SYSTEM")
	for cell in battle.highlights:
		if not _cells.has(cell):
			continue
		var entry: Dictionary = battle.highlights[cell]
		var target = int(entry.get("target",0))
		var label = "ENEMY" if target == 1 else "FRIEND"
		if target == 0 and int(entry.get("move",0)) <= 0:
			continue
		var marker = FT2APDPlayer.new()
		marker.play(apd,label,clock_ms,128)
		_draw_apd(marker,world_to_screen(cell),"system")

func _draw_overlay(command: Dictionary) -> void:
	var op = str(command.get("op",""))
	var pos: Vector2i = command.get("pos",Vector2i.ZERO)
	if op == "palette_current_entry":
		var entry = clampi(int(command.index),0,255)
		var target = palette.current.duplicate()
		for channel in 3: target[entry*3+channel] = int(command.rgb[channel])
		palette.fade(target,entry,1,0,clock_ms)
	elif op == "rect":
		var rect: Rect2i = command.get("rect",Rect2i())
		if command.get("filled",true):
			surface.fill_rect(rect,int(command.get("color",0)))
		else:
			for line in [[rect.position,Vector2i(rect.end.x-1,rect.position.y)],[Vector2i(rect.end.x-1,rect.position.y),rect.end-Vector2i.ONE],[rect.end-Vector2i.ONE,Vector2i(rect.position.x,rect.end.y-1)],[Vector2i(rect.position.x,rect.end.y-1),rect.position]]:
				surface.line(line[0],line[1],int(command.get("color",0)))
	elif op == "line":
		surface.line(command.from,command.to,int(command.get("color",0)))
	elif op == "focus_rect":
		# Win95 DrawFocusRect in the measured dialog palette: XOR black/face.
		# Apply after the caption so the focus dots invert existing text too.
		var rect: Rect2i = command.get("rect",Rect2i())
		var origin: Vector2i = command.get("origin",Vector2i.ZERO)
		var clipped = rect.intersection(Rect2i(0,0,surface.width,surface.height))
		var bytes = surface.pixels
		for y in range(clipped.position.y,clipped.end.y):
			for x in range(clipped.position.x,clipped.end.x):
				if x not in [rect.position.x,rect.end.x-1] and y not in [rect.position.y,rect.end.y-1]: continue
				if ((x+y-origin.x-origin.y)&1) != 0: continue
				var offset = y*surface.width+x
				if bytes[offset] == 0: bytes[offset] = 7
				elif bytes[offset] == 7: bytes[offset] = 0
		surface.pixels = bytes
	elif op == "caret_rect":
		# Measured Win95 EDIT caret XOR on white255/black0 edit contents.
		var rect: Rect2i = command.get("rect",Rect2i())
		var clipped = rect.intersection(Rect2i(0,0,surface.width,surface.height))
		var bytes = surface.pixels
		for y in range(clipped.position.y,clipped.end.y):
			for x in range(clipped.position.x,clipped.end.x):
				var offset = y*surface.width+x
				if bytes[offset] == 0: bytes[offset] = 255
				elif bytes[offset] == 255: bytes[offset] = 0
		surface.pixels = bytes
	elif op == "text":
		var bitmap = font.rasterize(str(command.get("raw_text",command.get("text",""))),command.get("font",{}),int(command.get("color",30)),command.get("decor",{}),str(command.get("text","")))
		if not bitmap.is_empty():
			surface.blit(bitmap,Rect2i(0,0,int(bitmap.width),int(bitmap.height)),pos,int(bitmap.transparent),0,0,command.get("clip",Rect2i(0,0,640,480)))
	elif op == "bitmap":
		var bitmap = assets.image(str(command.get("key","")),command.get("remaps",[]))
		if bitmap.is_empty():
			return
		for install in command.get("palette_install",[]):
			_install_once(bitmap,int(install[0]),int(install[1]))
		var rect: Rect2i = command.get("source",Rect2i(0,0,int(bitmap.width),int(bitmap.height)))
		if command.get("centered",false): pos += Vector2i(int((640-int(bitmap.width))/2),int((480-int(bitmap.height))/2))
		var dither = int(command.get("dither",0)) if command.get("raw_dither",false) else int(DITHER[clampi(int(command.get("dither",0)),0,8)])
		var transparent := int(command.get("transparent",-1))
		if command.has("transparent_at"):
			var sample: Vector2i = command.transparent_at
			transparent = int(bitmap.pixels[sample.y*int(bitmap.width)+sample.x])
		surface.blit(bitmap,rect,pos,transparent,int(command.get("flip",0)),dither,command.get("clip",Rect2i(0,0,640,480)))
	elif op == "indexed_image":
		var bitmap: Dictionary = command.get("image",{})
		if not bitmap.is_empty():
			var rect: Rect2i = command.get("source",Rect2i(0,0,int(bitmap.width),int(bitmap.height)))
			surface.blit(bitmap,rect,pos,int(command.get("key",command.get("transparent",-1))),int(command.get("flip",0)),0,command.get("clip",Rect2i(0,0,640,480)))
	elif op == "indexed_group":
		var destination := surface
		var size: Vector2i = command.get("size",Vector2i(640,480))
		surface = FT2IndexedSurface.new(size.x,size.y)
		for child in command.get("commands",[]): _draw_overlay(child)
		var bitmap = {"width":size.x,"height":size.y,"pixels":surface.pixels}
		surface = destination
		surface.blit(bitmap,command.get("source",Rect2i(Vector2i.ZERO,size)),pos,int(command.get("transparent",-1)),0,int(command.get("dither",0)),command.get("clip",Rect2i(0,0,640,480)))
	elif op == "apd":
		var player = FT2APDPlayer.new()
		player.play(assets.apd(str(command.stem)),str(command.get("label","")),clock_ms,128 | (16 if command.get("mirror",false) else 0))
		if command.has("frame"):
			player.frame = int(command.frame)
		_draw_apd(player,pos,str(command.get("policy","actor")),command.get("clip",Rect2i(0,0,640,480)),command.get("remaps",null),command.get("palette_install",[]))

func snapshot_indices() -> PackedByteArray:
	return surface.pixels.duplicate()

func render_source_frame(payload: Dictionary) -> Image:
	# Read-only reference injection: no clock/FSM execution and no RGB→index inference.
	set_map(int(payload.get("map_id",map_id)))
	camera = payload.get("camera",Vector2i.ZERO)
	if payload.has("env69_offsets"):
		for i in range(3): environment.offsets[i] = int(payload.env69_offsets[i])
	_frame_override = []
	for row in payload.get("sprites",[]):
		var player = FT2APDPlayer.new()
		player.apd = assets.apd(str(row.stem))
		player.frame = int(row.get("frame",-1))
		player.visible = bool(row.get("visible",true))
		player.dither = int(row.get("dither",0))
		player.state_mode = 1
		var flip = int(row.get("flip",0))
		var flags = int(row.get("flags",0))
		if int(row.get("mode",2)) != 1:
			flip ^= (1 if flags&16 else 0)|(2 if flags&32 else 0)
		player.static_flip = flip
		player.offset = row.get("motion_xy",Vector2i.ZERO)
		var anchor: Vector2i = row.get("base_xy",Vector2i.ZERO)+row.get("aux_xy",Vector2i.ZERO)
		var world: Vector2i = row.get("sort_world",row.get("world",Vector2i.ZERO))
		_frame_override.append({"player":player,"anchor":anchor,"depth":int(row.get("grid_sum",world.x+world.y)),"priority":int(row.get("priority",4)),"policy":str(row.get("policy","system" if str(row.stem).to_upper() == "SYSTEM" else "actor"))})
	if payload.has("palette"):
		var colors: PackedByteArray = payload.palette
		if colors.size() == 1024:
			var rgb = PackedByteArray()
			rgb.resize(768)
			for i in range(256):
				for channel in range(3): rgb[i*3+channel] = colors[i*4+channel]
			colors = rgb
		if colors.size() == 768:
			palette.current = colors
			palette.dirty = true
	_overlay = payload.get("overlay",[])
	_service_mode = "normal"
	_frame_override_active = true
	_render()
	var result = snapshot_image()
	_frame_override_active = false
	_frame_override.clear()
	return result

func snapshot_image() -> Image:
	var rgb = PackedByteArray()
	rgb.resize(640*480*3)
	for i in range(surface.pixels.size()):
		var index = int(surface.pixels[i])*3
		for channel in range(3):
			rgb[i*3+channel] = palette.current[index+channel]
	return Image.create_from_data(640,480,false,Image.FORMAT_RGB8,rgb)

func _exit_tree() -> void:
	dispose()

static func _disconnect_owned_signals(object) -> void:
	if object == null:
		return
	for descriptor in object.get_signal_list():
		var signal_name = str(descriptor.name)
		for connection in object.get_signal_connection_list(signal_name):
			if object.is_connected(signal_name,connection.callable):
				object.disconnect(signal_name,connection.callable)

func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	if battle != null and battle.changed.is_connected(_battle_changed):
		battle.changed.disconnect(_battle_changed)
	if magic != null:
		_disconnect_owned_signals(magic)
		magic.dispose()
	if physical != null:
		_disconnect_owned_signals(physical)
		physical.dispose()
	for signal_name in ["visual_finished","cell_hovered","actor_finished","camera_finished","sound_requested","sound_stop_requested"]:
		for connection in get_signal_connection_list(signal_name):
			if is_connected(signal_name,connection.callable):
				disconnect(signal_name,connection.callable)
	_actors.clear()
	_script = {}
	_script_commands_seen.clear()
	_script_unit78.clear()
	_ko_slots.clear()
	_ko_active = false
	_overlay = []
	_result_players.clear()
	_summon_slots.clear()
	_plan = {}
	_baked = {}
	_cells.clear()
	map = {}
	_cursor = null
	magic = null
	physical = null
	physical_builder = null
	zoom = null
	if assets != null:
		assets._images.clear()
		assets._apds.clear()
		assets._maps.clear()
		assets.manifest.clear()
	if font != null:
		font._cache.clear()
		font.styles.clear()
		font.masks = PackedByteArray()
	if _sprite != null:
		_sprite.texture = null
		_sprite.material = null
	if _material != null:
		_material.set_shader_parameter("palette_texture",null)
		_material.shader = null
	if palette != null:
		palette.texture = null
	_texture = null
	_material = null
	_base_image = null
	_result_backdrop = null
	_source_backdrop = null
	_source_backdrop_data.clear()
	surface_events.clear()
	palette = null
	assets = null
	font = null
	surface = null
	environment = null
	_audio = null
	battle = null
	data = null
