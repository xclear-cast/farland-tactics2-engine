class_name FT2Battle
extends RefCounted
signal changed
signal visual_requested(plan: Dictionary)
signal hook_requested(request: Dictionary)
signal phase_changed(phase: String)
signal confirmation_requested(plan: Dictionary)
signal unsupported_action(details: Dictionary)
signal modal_requested(request: Dictionary)
signal camera_requested(request: Dictionary)
signal actor_visuals_requested(operation: String, request: Dictionary)
signal sound_requested(stem: String, loop: bool)
signal experience_presented(operation: String, request: Dictionary)
signal interaction_requested(operation: String, request: Dictionary)

const Mechanics = preload("ft2_mechanics.gd")
const Navigation = preload("ft2_navigation.gd")
const Intelligence = preload("ft2_ai.gd")
var data
var rules
var navigation
var ai
var units: Array = []
var map_id = -1
var map_data: Dictionary = {}
var selected_slot = -1
var substate = 0
var phase = "player"
var round_index = 0
var event_id = 0
var pending_plan: Dictionary = {}
var highlights: Dictionary = {}
var inventory = PackedByteArray()
var money = 0
var rng: Array = [167,19960,5150]
var presentation_settings = {"swap_mouse":false,"skip_zoom":false,"skip_palette":false,"skip_effect":false,"skip_ally":false,"skip_enemy":false,"show_occluded":false}
var action_id = 0
var path: Array = []
var rollback_origin = Vector2i.ZERO
var rollback_facing = 0
var source_index = -1
var skip_results_visual = false # Development/test automation only; normal false.
var clock_ms = 1000
var post_state = -1
var post_cursor = 0
var pending_levels = 0
var remaining_exp = 0
var initial_exp = 0
var exp_epoch = 0
var enemy_cursor = 0
var status_cursor = 0
var _status_destination = "enemy"
var _return_phase = "player"
var _selection_mask: Dictionary = {}
var _preview: Dictionary = {}
var _before_units: Array = []
var _hook_groups: Array = []
var _hook_group = 0
var _hook_alternative = 0
var _hook_stage = ""
var _hook_group_contexts: Array = []
var context_slot = -1 #4627D8 ActorRef24; distinct from pending numeric actor.
var other_slot = -1 #462908; persists across inherited VM entry points.
var _waiting_hook = false
var _hook_response_pending = false
var _enemy_before_markers: Array = []
var _held_enemy_slot = -1
var _result_source = -1
var _ko_busy = false
var _pending_end_hooks = false
var last_error: Dictionary = {}
var _status_limit = 50
var _modal_waiting = false
var _modal_continuation = ""
var _growth_active = false
var _growth_left = 0
var _growth_notices: Array = []
var frame_service_requests = 0
var frame_service_events: Array = []
var frame_service_callback: Callable
var interaction_query = {"cursor":0,"type":7,"center":Vector2i.ZERO,"minimum":0,"maximum":1}
var _pickup_active = false
var _pickup_stage = ""
var _pickup_candidate = -1
var _pickup_return_phase = "player"

func _init(source_data = null) -> void:
	data = source_data
	rules = Mechanics.new(data)
	navigation = Navigation.new(rules)
	ai = Intelligence.new(navigation,rules)
	inventory.resize(320)
	inventory.fill(0)
	for ignored in range(50):
		var unit = PackedByteArray()
		unit.resize(124)
		unit.fill(0)
		units.append(unit)

func _set_phase(value: String) -> void:
	if phase != value:
		phase = value
		phase_changed.emit(phase)

func refresh_context() -> void:
	navigation.units = units
	changed.emit()

func load_save(index: int) -> void:
	assert(data != null)
	var save: Dictionary = data.load_save(index)
	units = rules.copy_units(save.units)
	map_id = int(save.map_id)
	map_data = data.load_map(map_id) if map_id >= 0 else {}
	round_index = int(save.header.get("round_index",0))
	event_id = int(save.header.get("stage",0))
	money = int(save.header.get("money",0))
	inventory.fill(0)
	var bag: Array = save.header.get("inventory",[])
	for i in range(mini(80,bag.size())):
		rules.put16(inventory,i*4,int(bag[i].id))
		rules.put16(inventory,i*4+2,int(bag[i].quantity))
	source_index = index
	selected_slot = -1
	substate = 0
	pending_plan.clear()
	_preview.clear()
	highlights.clear()
	_hook_groups.clear()
	_waiting_hook = false
	_modal_waiting = false
	_pickup_active = false
	_pickup_stage = ""
	_pickup_candidate = -1
	_growth_active = false
	_growth_notices.clear()
	_hook_response_pending = false
	post_state = -1
	navigation.configure(units,map_data,1)
	_set_phase("player")
	changed.emit()

func snapshot_units() -> Array: return rules.copy_units(units)

func menu_flags(slot: int = -1) -> Dictionary:
	if slot < 0: slot = selected_slot
	if slot < 0 or slot >= units.size(): return {}
	var u: PackedByteArray = units[slot]
	var state = u.decode_u16(16)
	var blocked = state in rules.INCAP
	return {"popup_allowed":u.decode_u16(18) == 0 and state != 7,"action_move":u.decode_s32(92) == 0 and not blocked,"magic_parent":u.decode_s32(96) == 0 and not blocked and state != 6,"items_parent":not available_items().is_empty() and u.decode_s32(96) == 0 and not blocked}

func available_magic(slot: int = -1) -> Array:
	if slot < 0: slot = selected_slot
	var out: Array = []
	if slot < 0: return out
	var u: PackedByteArray = units[slot]
	for k in range(10):
		var identity = u.decode_u16(56+k*2)
		if identity == 0: continue
		out.append({"slot":k,"action_id":identity,"enabled":u.decode_s16(42) >= absi(rules.magics.decode_s16(identity*64+22)),"cost":absi(rules.magics.decode_s16(identity*64+22))})
	return out

func available_items() -> Array:
	var out: Array = []
	for k in range(80):
		var identity = inventory.decode_s16(k*4)
		if identity != 0: out.append({"bag_slot":k,"item_id":identity,"action_id":1000+identity,"quantity":inventory.decode_s16(k*4+2)})
	return out

func select_unit(slot: int) -> bool:
	if phase != "player" or slot < 0 or slot >= 50 or units[slot].decode_u16(0) == 0: return false
	selected_slot = slot
	var u: PackedByteArray = units[slot]
	changed.emit()
	if u.decode_u16(18) != 0 or u.decode_u16(16) in rules.INCAP: return false
	if u.decode_s32(92) != 0 and u.decode_s32(96) != 0: return false
	rollback_origin = rules.xy(u)
	rollback_facing = u.decode_u16(6)
	path.clear()
	action_id = 0
	substate = 1
	_before_units = snapshot_units()
	navigation.units = units
	navigation.movement_grid(slot)
	_selection_mask = navigation.selection_mask(slot,0)
	_rebuild_highlights()
	return true

func _rebuild_highlights() -> void:
	highlights.clear()
	for offset in navigation.grid:
		if navigation.selectable(navigation.origin+offset,_selection_mask): highlights[navigation.origin+offset] = {"move":navigation.grid[offset],"target":_selection_mask.get(offset,0)}
	for offset in _selection_mask:
		highlights[navigation.origin+offset] = {"move":navigation.grid.get(offset,0),"target":_selection_mask[offset]}
	changed.emit()

func choose_action(identity: int) -> bool:
	if phase != "player" or selected_slot < 0: return false
	var flags = menu_flags()
	if identity > 0 and identity < 1000:
		if identity >= rules.magics.size()/64 or not flags.get("magic_parent",false): return false
		var found = false
		for entry in available_magic():
			if entry.action_id == identity and entry.enabled: found = true
		if not found: return false
	elif identity >= 1000:
		if identity-1000 >= rules.items.size()/56 or not flags.get("items_parent",false) or rules.bag_count(inventory,identity-1000) <= 0: return false
	elif identity != 0: return false
	action_id = identity
	_preview.clear()
	if identity > 0:
		_before_units = snapshot_units()
		rollback_origin = rules.xy(units[selected_slot])
	navigation.units = units
	navigation.movement_grid(selected_slot)
	_selection_mask = navigation.selection_mask(selected_slot,identity)
	substate = 1 if identity == 0 else 4 if identity >= 1000 else 3
	_rebuild_highlights()
	if identity > 0 and identity < 1000 and rules.magics.decode_u16(identity*64+50) in [3,4]: select_cell(rules.xy(units[selected_slot]))
	return true

func select_cell(point: Vector2i) -> bool:
	if phase != "player": return false
	if substate == 0:
		navigation.units = units
		var slot = navigation.occupant(point)
		return select_unit(slot) if slot >= 0 else false
	if selected_slot < 0: return false
	if substate == 2: return false # Facing is selected with commit_facing().
	if not navigation.selectable(point,_selection_mask):
		if not (substate == 3 and rules.magics.decode_u16(action_id*64+50) in [3,4]): return false
	var u: PackedByteArray = units[selected_slot]
	if substate == 1:
		var other = navigation.occupant(point)
		if other >= 0 and rules.hostile(u,units[other],selected_slot == other):
			_preview = navigation.collect_targets(selected_slot,point,0)
			rules.set_xy(units[selected_slot],rollback_origin)
			_begin_action()
			return true
		if rules.xy(u) == rollback_origin: path = navigation.path_to(point)
		rules.set_xy(u,point)
		units[selected_slot] = u
		navigation.units = units
		navigation.movement_grid(selected_slot)
		_selection_mask = navigation.selection_mask(selected_slot,0)
		if not _selection_mask.is_empty() and other != selected_slot:
			substate = 1
			_rebuild_highlights()
		else:
			substate = 2
			highlights.clear()
			rollback_facing = u.decode_u16(6)
			changed.emit()
		return true
	rollback_facing = u.decode_u16(6)
	path = navigation.path_to(rules.xy(u))
	_preview = navigation.collect_targets(selected_slot,point,action_id)
	if substate == 3:
		_rebuild_confirmation_highlights()
		_set_phase("confirm")
		changed.emit()
		camera_requested.emit({"kind":"cell","cell":point})
		#405DB6 presents the area before TrackPopupMenu blocks the normal pump.
		interaction_requested.emit("surface_restore",{})
		confirmation_requested.emit({"actor_slot":selected_slot,"action_id":action_id,"target":point,"ordered_targets":_target_slots(_preview.records),"can_confirm":not _preview.records.is_empty()})
	else:
		consume_item(action_id-1000,1)
		_begin_action()
	return true

func _rebuild_confirmation_highlights() -> void:
	#4129A0 clears the casting matrix and writes the actual affected area before
	#405DB6 draws the frame and opens the confirmation menu. Affected empty cells
	#are marked too; this is independent of the ordered target records.
	highlights.clear()
	var shape = rules.magics.decode_u16(action_id*64+50)
	var center: Vector2i = rules.xy(units[selected_slot]) if shape == 2 else _preview.center
	for offset in _preview.get("mask",{}):
		if absi(offset.x) > 10 or absi(offset.y) > 10: continue
		var point: Vector2i = center+offset
		var cell = navigation.cell(point)
		#4128B0 rejects missing/wall/flag3 cells before returning the marker frame.
		if cell == null or int(cell[1]) != 0 or int(cell[2]) != 0: continue
		highlights[point] = {"move":0,"target":1}

func confirm_action(accepted: bool) -> void:
	if phase != "confirm": return
	if not accepted or _preview.get("records",[]).is_empty():
		rules.put16(units[selected_slot],6,rollback_facing)
		substate = 0
		highlights.clear()
		_set_phase("player")
		changed.emit()
		return
	var u: PackedByteArray = units[selected_slot]
	rules.put16(u,42,u.decode_s16(42)-absi(rules.magics.decode_s16(action_id*64+22)))
	units[selected_slot] = u
	_begin_action()

func commit_facing(direction: int) -> bool:
	if phase != "player" or substate != 2 or direction < 0 or direction > 3: return false
	var u: PackedByteArray = units[selected_slot]
	rules.put16(u,6,direction)
	rules.set_xy(u,rollback_origin)
	u.encode_u32(92,1)
	units[selected_slot] = u
	_preview = {"records":[],"direction":direction,"center":rollback_origin}
	_begin_action()
	return true

func cancel_selection() -> void:
	if phase == "confirm":
		confirm_action(false)
		return
	if phase != "player": return
	var old_substate = substate
	var preview_moved = selected_slot >= 0 and rules.xy(units[selected_slot]) != rollback_origin
	if selected_slot >= 0 and substate in [1,2]:
		rules.set_xy(units[selected_slot],rollback_origin)
		if substate == 2: rules.put16(units[selected_slot],6,rollback_facing)
	substate = 0
	path.clear()
	_preview.clear()
	highlights.clear()
	if old_substate == 2 or (old_substate == 1 and preview_moved):
		select_unit(selected_slot) # Source POST102 after restoring preview/facing.
	changed.emit()

func _target_slots(records: Array) -> Array:
	var out: Array = []
	for record in records: out.append(int(record.target_slot))
	return out

func _request(event: int, label: String, kind: String, target: int = -1) -> Dictionary:
	return {"event_id":event,"label":label,"kind":kind,"source_slot":_result_source if kind != "battle" else selected_slot,"target_slot":target,"action_id":action_id,"continuation":"commit" if kind == "battle" else "post","inherit_context":kind != "after","context_slot":target if kind == "after" else context_slot,"other_slot":_result_source if kind == "after" else other_slot}

func _begin_action() -> void:
	highlights.clear()
	_return_phase = "enemy" if phase == "enemy" else "player"
	_result_source = selected_slot
	_hook_groups.clear()
	_hook_group = 0
	_hook_alternative = 0
	_hook_stage = "battle"
	var actor: PackedByteArray = units[selected_slot]
	for record in _preview.records:
		var slot = int(record.target_slot)
		if slot < 0: continue
		var target: PackedByteArray = units[slot]
		if not rules.hostile(actor,target,selected_slot == slot) or actor.decode_u16(0) == 8 or target.decode_u16(0) == 8: continue
		var kind = target.decode_u16(0) if target.decode_u16(18) != 0 else actor.decode_u16(0)
		_hook_groups.append([_request(event_id,"battle%02d"%kind,"battle",slot)])
	_advance_hook()

func _advance_hook() -> void:
	while _hook_group < _hook_groups.size():
		if _hook_stage == "after" and _hook_group < _hook_group_contexts.size():
			post_cursor = _hook_group
			context_slot = _hook_group_contexts[_hook_group]
			other_slot = _result_source
		var alternatives: Array = _hook_groups[_hook_group]
		if _hook_alternative >= alternatives.size():
			_hook_group += 1
			_hook_alternative = 0
			continue
		var request: Dictionary = alternatives[_hook_alternative]
		_hook_alternative += 1
		_waiting_hook = true
		_set_phase("event")
		if hook_requested.get_connections().is_empty(): resume_hook(false)
		else: hook_requested.emit(request)
		return
	if _hook_stage == "battle": _commit_numeric()
	elif _hook_stage == "after":
		post_cursor = _hook_groups.size()
		_actor_visuals("visible_all","41498C",true)
		post_state = 5
		_set_phase("post_action")
	elif _hook_stage == "terminal": _complete_action()
	else: _set_phase("post_action")

func resume_hook(loaded: bool, resume_action: bool = true) -> void:
	if not _waiting_hook: return
	_waiting_hook = false
	if not loaded:
		_advance_hook()
		return
	_hook_group += 1
	if _hook_stage == "after": post_cursor = _hook_group
	_hook_alternative = 0
	if _hook_stage == "battle":
		_hook_groups.clear() # First loaded battle label stops the ordered search.
		if resume_action: _commit_numeric()
		else:
			pending_plan.clear()
			substate = 0
			_set_phase(_return_phase)
	else:
		if _hook_stage == "terminal": _hook_group = _hook_groups.size()
		_hook_response_pending = true
		_set_phase("post_action")
	changed.emit()

func hook_started() -> void:
	# VM must call immediately after synchronous43CFB0 success, before script execution.
	if _waiting_hook and _hook_stage == "after":
		_actor_visuals("visible_all","4149C9",true)
		post_cursor = _hook_group+1

func _actor_visuals(operation: String,source: String,requested: bool = true) -> void:
	var effective = requested
	if operation == "animation_enabled": effective = requested and not bool(presentation_settings.skip_effect)
	actor_visuals_requested.emit(operation,{"source":source,"requested":requested,"enabled":effective})

func _run_flag(actor: PackedByteArray, records: Array) -> int:
	if actor.decode_u16(18) != 0 or actor.decode_s32(100) != 0 or records.is_empty() or path.size() < 3: return 0
	var direction = int(path[0])
	for d in path:
		if d != direction: return 0
	if actor.decode_u16(6) != direction: return 0
	var l0 = rules.races.decode_u16(actor.decode_u16(2)*86+62)
	if navigation.map_mode == 1 and l0 == 99 and (actor.decode_u16(16) == 11 or rules.has_ability(actor,11)): return 0
	var point = rules.xy(actor)
	for d in path:
		var next = point+navigation.DIRS[d]
		if absi(navigation.height(next)-navigation.height(point)) > 2: return 0
		point = next
	if rules.items.decode_u16(actor.decode_u16(20)*56+50) == 3:
		var target = int(records[0].target_slot)
		if target < 0 or navigation.manhattan(point,rules.xy(units[target])) != 1: return 0
	return 1

func apply_settings(settings: Dictionary) -> void:
	# UI109 IDOK live DWORDs; legacy battle_animation has no source checkbox.
	for key in presentation_settings:
		if settings.has(key): presentation_settings[key] = bool(settings[key])

func _extension_skill(action: int) -> Dictionary:
	if FT2Content.active!=null and FT2Content.active.extensions!=null:return FT2Content.active.extensions.skill_by_action(action)
	return {}

func visual_bypassed(control: int) -> bool:
	#41508F/415171 inspect actor+12 exactly, not friendliness/race/party slot.
	return bool(presentation_settings.skip_ally) if control == 0 else bool(presentation_settings.skip_enemy)

func _commit_numeric() -> void:
	var actor: PackedByteArray = units[selected_slot]
	var records: Array = _preview.records.duplicate(true)
	var run = _run_flag(actor,records) if action_id == 0 else 0
	if action_id == 0 and rules.items.decode_u16(actor.decode_u16(20)*56+50) == 3 and run == 0:
		last_error = {"kind":"conditional_unshipped_weapon","entry":"437A60/437B10","item_id":actor.decode_u16(20),"reason":"Enemy bow170..174 have no shipping SAVE/STAGE/EVENT acquisition reference and absent MISSILE arrow labels. Original ballistic collision retargeting must precede numeric evaluation; no substitute target is fabricated."}
		_set_phase("unsupported")
		unsupported_action.emit(last_error)
		return
	var prepared = actor.decode_s32(100)
	var before = _before_units if not _before_units.is_empty() else snapshot_units()
	for record in records:
		var slot = int(record.target_slot)
		var result = {"damage_flag":0,"critical":0,"amount":0,"pending_state":0}
		if slot >= 0:
			var record_origin: Vector2i = record.origin
			var first = int(records[0].get("amount",0))
			var numeric = rules.apply_numeric(units[selected_slot],units[slot],action_id,rng,slot,slot == selected_slot,first,navigation.map_mode,navigation.height(record_origin)-navigation.height(rules.xy(units[slot])),[record_origin.x,record_origin.y],run)
			units[selected_slot] = numeric.actor
			units[slot] = numeric.target
			rng = numeric.seeds
			result = numeric.result
		for key in result: record[key] = result[key]
	if presentation_settings.skip_effect: _actor_visuals("animation_enabled","41506A",false)
	var point = rules.xy(units[selected_slot])
	for d in path: point += navigation.DIRS[d]
	rules.set_xy(units[selected_slot],point)
	if not path.is_empty(): units[selected_slot].encode_u32(92,1)
	if not records.is_empty(): units[selected_slot].encode_u32(96,1)
	var spawned: Array = []
	if int(_extension_skill(action_id).get("base_skill",action_id)) == 82:
		var summon = rules.summon82(units,selected_slot,rng,navigation)
		units = summon.units
		rng = summon.seeds
		spawned = summon.spawned
		if summon.error != "":
			last_error = {"kind":"summon_source_failure","reason":summon.error}
			_set_phase("unsupported")
			unsupported_action.emit(last_error)
			return
	var effect = rules.items.decode_u16((action_id-1000)*56+48) if action_id >= 1000 else action_id
	if action_id>0 and action_id<1000:effect=int(_extension_skill(action_id).get("visual_skill",effect))
	pending_plan = {"actor_slot":selected_slot,"action_id":action_id,"effect_id":effect,"visual_kind":"physical" if action_id == 0 else "magic","origin":rollback_origin,"path":path.duplicate(),"direction":int(_preview.get("direction",actor.decode_u16(6))),"accepted_run":run,"prepared_before":prepared,"before_units":rules.copy_units(before),"after_units":snapshot_units(),"ordered_targets":_target_slots(records),"results":records,"center":_preview.get("center",point)}
	pending_plan.spawned_slots = spawned
	pending_plan.presentation_flags = presentation_settings.duplicate()
	pending_plan.zoom_requested = run != 0 and not bool(presentation_settings.skip_zoom)
	pending_plan.visual_skipped = visual_bypassed(units[selected_slot].decode_u16(18))
	substate = 5
	post_state = -1
	navigation.units = units
	if pending_plan.visual_skipped:
		#415192→406950 still enters413BD0: Number/prepared-clear and all post steps.
		changed.emit() #4196F0(actor)/41AE20 refresh committed position before Number.
		_begin_results()
	elif records.is_empty() and path.is_empty():
		_complete_action() #41507E/415082 does not construct an empty visual.
	else:
		_set_phase("visual")
		changed.emit()
		visual_requested.emit(pending_plan)

func finish_visual() -> void:
	if phase == "visual":
		_begin_results()
	elif phase == "results":
		post_state = 4
		post_cursor = 0
		_set_phase("post_action")
	elif phase == "ko":
		_ko_busy = false
		if post_state == 6: post_state = 7 # Source busy-before-service completion belongs to THIS call.
		_set_phase("post_action")
	changed.emit()

func _begin_results() -> void:
	var records: Array = pending_plan.get("results",[])
	var loaded = data == null or not data.load_apd("NUMBER").is_empty()
	if loaded and _result_source >= 0:
		for record in records:
			if int(record.target_slot) >= 0 and int(record.get("amount",0)) < 90000:
				units[_result_source].encode_u32(100,0)
				break
	pending_plan.after_units = snapshot_units()
	if records.is_empty() or not loaded:
		_actor_visuals("animation_enabled","406989",true)
		_actor_visuals("refresh_all","406991")
		_complete_action() #406950 restores parent directly when413BD0 returns0.
		return
	if skip_results_visual:
		post_state = 4
		post_cursor = 0
		_set_phase("post_action")
		return
	var result_plan = pending_plan.duplicate(true)
	result_plan.visual_kind = "results"
	_set_phase("results")
	visual_requested.emit(result_plan)

func _start_after_hooks() -> void:
	_hook_stage = "after"
	_hook_group = post_cursor
	_hook_alternative = 0
	_hook_groups.clear()
	_hook_group_contexts.clear()
	var actor: PackedByteArray = units[_result_source] if _result_source >= 0 else PackedByteArray()
	for record in pending_plan.get("results",[]):
		var slot = int(record.target_slot)
		_hook_group_contexts.append(slot)
		var group: Array = []
		if slot >= 0:
			var target: PackedByteArray = units[slot]
			if target.decode_u16(0) != 8:
				var label: String
				if not actor.is_empty() and _result_source != slot and actor.decode_u16(18) == 0 and target.decode_u16(18) == 0: label = "ASSIST%02d"%actor.decode_u16(0)
				else: label = ("BEAT" if target.decode_u16(16) == 1 else "AFTER")+"%02d"%target.decode_u16(0)
				group.append(_request(event_id,label,"after",slot))
			if target.decode_u16(16) == 1 and not actor.is_empty() and actor.decode_u16(18) == 0: group.append(_request(event_id,"WIN%02d"%actor.decode_u16(0),"after",slot))
		_hook_groups.append(group)
	_advance_hook()

func update(delta_ms: int, active: bool = true, service_rng: bool = false) -> void:
	clock_ms = (clock_ms+maxi(0,delta_ms))&0xffffffff
	_logic_update(active)
	if service_rng: render_service_rng()

func _logic_update(active: bool) -> void:
	if not active or _modal_waiting or _waiting_hook or phase in ["visual","results","confirm","event","ko"]: return
	if _hook_response_pending:
		_hook_response_pending = false
		_advance_hook()
		return
	if phase == "post_action": _post_update()
	elif phase == "status": _status_update()
	elif phase == "enemy": _enemy_update()

func render_service_rng(context: String = "parent", render: bool = true) -> int:
	frame_service_requests += 1
	frame_service_events.append({"time_ms":clock_ms,"context":context,"rng_consumed":true})
	if render and frame_service_callback.is_valid(): frame_service_callback.call(context)
	var step = rules.rng_step(rng,0)
	rng = step.seeds
	return step.value

func take_frame_service_requests() -> Array:
	var requests = frame_service_events.duplicate(true)
	frame_service_events.clear()
	frame_service_requests = 0
	return requests

func _post_update() -> void:
	var records: Array = pending_plan.get("results",[])
	match post_state:
		4: _start_after_hooks()
		5:
			var fades: Array = []
			for record in records:
				var slot = int(record.target_slot)
				if slot < 0: continue
				var target: PackedByteArray = units[slot]
				if target.decode_u16(18) != 0 and target.decode_s16(38) == 0:
					rules.put16(target,16,1)
					target.encode_u32(120,0)
					if target.decode_u16(0) == 8 or target.decode_u16(0) > 30: fades.append(slot)
			post_state = 6
			if not fades.is_empty() and not skip_results_visual:
				_ko_busy = true
				_set_phase("ko")
				visual_requested.emit({"visual_kind":"ko","target_slots":fades,"actor_slot":_result_source,"results":records,"before_units":snapshot_units(),"after_units":snapshot_units()})
		6:
			if not _ko_busy: post_state = 7
			render_service_rng("post6")
		7:
			pending_levels = 0
			if _result_source >= 0 and units[_result_source].decode_u16(18) != 0:
				post_state = 9
			else:
				remaining_exp = rules.experience_sum(units[_result_source] if _result_source >= 0 else PackedByteArray(),units,records)
				if remaining_exp == 0: post_state = 9
				else:
					initial_exp = remaining_exp
					exp_epoch = clock_ms
					post_state = 8
					experience_presented.emit("begin",{"initial_exp":initial_exp})
		8:
			if ((clock_ms-exp_epoch)&0xffffffff) < 20: return
			exp_epoch = clock_ms
			if remaining_exp < 0:
				_request_modal({"kind":"exp_wait","duration_ms":4000,"text":"","source_format_null":true},"exp_wait")
			else:
				var delta = maxi(1,rules.div0(remaining_exp,100))
				remaining_exp = rules.s32(remaining_exp-delta)
				if remaining_exp >= 0 and _result_source >= 0:
					var unit: PackedByteArray = units[_result_source]
					var previous_pending = pending_levels
					rules.put16(unit,44,mini(9899,unit.decode_s16(44)+delta))
					if unit.decode_s16(44) >= rules.s32((unit.decode_u16(4)+pending_levels)*100): pending_levels = rules.s32(pending_levels+1)
					experience_presented.emit("award",{"exp":unit.decode_s16(44),"level":unit.decode_u16(4),"pending_levels":pending_levels,"previous_pending_levels":previous_pending,"initial_exp":initial_exp})
		9:
			if not _growth_active:
				units = rules.finish_states_and_drops(units,records)
				render_service_rng("post9")
				_growth_left = pending_levels if _result_source >= 0 else 0
				_growth_active = true
			while _growth_left > 0 or not _growth_notices.is_empty():
				if not _growth_notices.is_empty():
					sound_requested.emit("levelup",false) #41A79C..41A7B0, before learned-skill message.
					_request_modal(_growth_notices.pop_front(),"growth")
					changed.emit()
					return
				rules.put16(units[_result_source],4,units[_result_source].decode_u16(4)+1)
				var grown = rules.grow_record(units[_result_source],true,rng)
				units[_result_source] = grown.unit
				rng = grown.seeds
				_growth_left -= 1
				#41A785..41A7D9: notify newly eligible skills in MAGIC table order.
				# Level text/sound belongs to414B90 during EXP, not a growth modal.
				var grown_unit: PackedByteArray = units[_result_source]
				if grown_unit.decode_u16(18) == 0:
					var mask = 1 << ((grown_unit.decode_u16(0)-1)&31)
					for identity in range(rules.magics.size()/64):
						var base = identity*64
						var required = rules.magics.decode_u16(base+20)
						if required != 0 and required == grown_unit.decode_u16(4) and (rules.magics.decode_u16(base+52)&mask) != 0:
							_growth_notices.append({"kind":"learned_skill","duration_ms":4000,"unit_slot":_result_source,"skill_id":identity,"level":required})
			_growth_active = false
			if pending_levels > 0 and _result_source >= 0:
				_hook_stage = "level"
				_hook_groups = [[_request(0,"levelup%02d"%units[_result_source].decode_u16(0),"level",_result_source)]]
				_hook_group = 0
				_hook_alternative = 0
				post_state = 10
				_advance_hook()
			else: post_state = 10
		10:
			var ready = 0
			var enemies = 0
			for i in range(10):
				if units[i].decode_u16(0) != 0 and not units[i].decode_u16(16) in [1,3,4,5,8,9]: ready += 1
			for i in range(10,50):
				if units[i].decode_u16(0) != 0 and units[i].decode_s16(38) > 0 and not units[i].decode_u16(18) in [1,7] and units[i].decode_u16(16) != 9: enemies += 1
			_hook_groups.clear()
			if ready == 0: _hook_groups.append([_request(0,"GAMEOVER","terminal")])
			if enemies == 0: _hook_groups.append([_request(event_id,"COMPLETE","terminal")])
			_hook_stage = "terminal"
			_hook_group = 0
			_hook_alternative = 0
			_advance_hook()
	navigation.units = units
	changed.emit()

func _request_modal(request: Dictionary, continuation: String) -> void:
	_modal_waiting = true
	_modal_continuation = continuation
	_set_phase("modal")
	if modal_requested.get_connections().is_empty():
		# Tests may explicitly opt out; normal integration attaches the source pump.
		if skip_results_visual: finish_modal()
	else: modal_requested.emit(request)

func finish_modal(_result: int = 1) -> void:
	if not _modal_waiting: return
	_modal_waiting = false
	if _modal_continuation == "pickup":
		_set_phase(_pickup_return_phase)
		_pickup_continue()
		changed.emit()
		return
	if _modal_continuation == "exp_wait":
		if experience_presented.get_connections().is_empty(): _actor_visuals("animation_enabled","414285",true)
		else: experience_presented.emit("finish",{}) #Release sounds→41AED0→backdrop clear in consumer order.
		post_state = 9
	if _modal_continuation == "round":
		substate = 0
		_set_phase("player")
	else:
		_set_phase("post_action")
		if _modal_continuation == "growth": _post_update() # Nested41A4D0 notify returns to same source loop.
	changed.emit()

func _complete_action() -> void:
	substate = 6 if _return_phase == "status" else 7 if _return_phase == "enemy" else 0
	pending_plan.clear()
	_preview.clear()
	_before_units.clear()
	if _return_phase == "enemy" and _held_enemy_slot >= 0:
		var u: PackedByteArray = units[_held_enemy_slot]
		var move_changed = u.decode_s32(92) != _enemy_before_markers[0]
		var action_changed = u.decode_s32(96) != _enemy_before_markers[1]
		var rewinds = int(move_changed and u.decode_s32(96) == 0)+int(action_changed and u.decode_s32(92) == 0)
		enemy_cursor = maxi(0,enemy_cursor-rewinds)
		_held_enemy_slot = -1
	if _return_phase == "status": _set_phase("status")
	else: _set_phase(_return_phase)
	if phase == "player": _pickup_at_actor()
	changed.emit()

func end_turn() -> void:
	if phase != "player" or substate != 0: return
	status_cursor = 10 #4179B0(0): NPC range10..49 before enemy phase.
	_status_limit = 50
	_status_destination = "enemy"
	substate = 6
	_set_phase("status")
	changed.emit()

func _status_update() -> void:
	if status_cursor < _status_limit:
		var slot = status_cursor
		status_cursor += 1
		if units[slot].decode_u16(0) == 0:
			status_cursor = _status_limit # Source first-hole ends this contiguous pass.
		else:
			var result = rules.status_numeric(units[slot],rng)
			units[slot] = result.unit
			rng = result.seeds
			if result.event.is_empty():
				changed.emit()
				return # Exactly one occupied unit per eligible source frame.
			_result_source = -1
			_return_phase = "status"
			pending_plan = {"actor_slot":-1,"action_id":-1,"visual_kind":"results","effect_id":-1,"origin":Vector2i.ZERO,"path":[],"direction":0,"accepted_run":0,"prepared_before":0,"before_units":snapshot_units(),"after_units":snapshot_units(),"ordered_targets":[slot],"results":[{"target_slot":slot,"origin":Vector2i.ZERO,"damage_flag":0,"critical":0,"amount":result.event.amount,"pending_state":0}]}
			_begin_results()
			return
	if _status_destination == "enemy":
		enemy_cursor = 0
		substate = 7
		_set_phase("enemy")
	else:
		round_index = rules.s32(round_index+1)
		for i in range(50): units[i] = rules.round_numeric(units[i])
		_request_modal({"kind":"round","duration_ms":4000,"round":round_index+1},"round")
	changed.emit()

func _enemy_update() -> void:
	while enemy_cursor < 50:
		var slot = enemy_cursor
		enemy_cursor += 1
		var u: PackedByteArray = units[slot]
		if u.decode_u16(0) == 0 or u.decode_u16(18) in [1,7] or not rules.hostile(u,units[0],slot == 0): continue
		if u.decode_u16(16) in rules.INCAP: return # Driver consumes this frame.
		selected_slot = slot
		rollback_origin = rules.xy(u)
		rollback_facing = u.decode_u16(6)
		_before_units = snapshot_units()
		navigation.units = units
		camera_requested.emit({"kind":"actor","slot":slot,"source":"40B9B6","center":navigation.project(rollback_origin),"world":rollback_origin})
		var decision = ai.decision(slot)
		prepare_ai_execution(slot,decision)
		if path.is_empty() and _preview.records.is_empty():
			_held_enemy_slot = -1
			return
		_begin_action()
		return
	status_cursor = 0
	_status_limit = 10 #4179B0(1): contiguous party before next round.
	_status_destination = "player"
	substate = 6
	#408BC2..408C1C intentionally checks state, not kind, before recentering.
	for first in range(50):
		if not units[first].decode_u16(16) in rules.INCAP:
			var world = rules.xy(units[first])
			camera_requested.emit({"kind":"actor","slot":first,"source":"408C1C","center":navigation.project(world),"world":world})
			break
	_set_phase("status")

func prepare_ai_execution(slot: int, decision: Dictionary) -> Dictionary:
	selected_slot = slot
	var u: PackedByteArray = units[slot]
	rollback_origin = rules.xy(u)
	rollback_facing = u.decode_u16(6)
	_before_units = snapshot_units()
	navigation.units = units
	path = navigation.path_to(decision.position)
	action_id = int(decision.action_id)
	_held_enemy_slot = slot
	_enemy_before_markers = [u.decode_s32(92),u.decode_s32(96)]
	if decision.has_action and action_id == 0:
		#40BAC2: physical can attack from the future path endpoint in this action.
		rules.set_xy(units[slot],decision.position)
		_preview = navigation.collect_targets(slot,decision.target,0)
		rules.set_xy(units[slot],rollback_origin)
		units[slot].encode_u32(96,1)
	elif decision.position != rollback_origin:
		if decision.has_action: rules.put16(units[slot],6,navigation.facing(decision.position,decision.target))
		else: _face_nearest_enemy(slot,decision.position)
		_preview = {"records":[],"direction":units[slot].decode_u16(6),"center":decision.position}
		action_id = 0
	else:
		_preview = navigation.collect_targets(slot,decision.target,action_id) if decision.has_action else {"records":[],"direction":u.decode_u16(6),"center":rollback_origin}
		if action_id > 0:
			units[slot].encode_u32(96,1)
			rules.put16(units[slot],42,units[slot].decode_s16(42)-absi(rules.magics.decode_s16(action_id*64+22)))
		else: _face_nearest_enemy(slot,decision.position)
	return {"records":_preview.records,"path":path.duplicate(),"action_id":action_id,"facing":units[slot].decode_u16(6),"has_work":not path.is_empty() or not _preview.records.is_empty()}

func _face_nearest_enemy(slot: int, from: Vector2i) -> void:
	var best = 999
	for other in range(50):
		var target: PackedByteArray = units[other]
		if other == slot or target.decode_u16(0) == 0 or target.decode_u16(16) in [1,9] or target.decode_u16(18) == 7 or not rules.hostile(units[slot],target): continue
		var distance = navigation.manhattan(from,rules.xy(target))
		if distance < best:
			best = distance
			rules.put16(units[slot],6,navigation.facing(from,rules.xy(target)))

func grant_item(slot: int, identity: int, quantity: int) -> bool:
	var result = rules.grant(units[slot] if slot >= 0 else PackedByteArray(),inventory,identity,quantity)
	if slot >= 0: units[slot] = result.unit
	inventory = result.bag
	changed.emit()
	return result.accepted

func consume_item(identity: int, quantity: int = 1) -> void:
	inventory = rules.consume(inventory,identity,quantity)
	changed.emit()

func add_money(delta: int) -> void:
	money = rules.money_after(money,delta)
	changed.emit()

func equip_carried(slot: int, carry_index: int) -> bool:
	if slot < 0 or slot >= 10 or carry_index < 0 or carry_index > 3: return false
	var item = units[slot].decode_u16(28+carry_index*2)
	if item == 0 or not rules.can_equip(item,units[slot].decode_u16(0)): return false
	units[slot] = rules.equip_carried(units[slot],carry_index)
	changed.emit()
	return true

func buy_item(slot: int, identity: int, quantity: int = 1) -> bool:
	if identity < 0 or identity >= rules.items.size()/56: return false
	var price = rules.items.decode_u16(identity*56+20)
	var gear = rules.items.decode_s16(identity*56+46) in [0,1,2]
	if gear:
		if quantity != 1 or slot < 0 or slot >= 10 or not rules.equipment_receiver_enabled(units[slot]) or price > money: return false
	elif not rules.buy_quantity_enabled(price,money,rules.bag_count(inventory,identity),quantity): return false
	if not grant_item(slot if gear else -1,identity,quantity): return false
	add_money(-price*quantity)
	return true

func sell_item(identity: int, quantity: int = 1, slot: int = -1, carry_index: int = -1) -> bool:
	if identity < 0 or identity >= rules.items.size()/56: return false
	var price = rules.items.decode_u16(identity*56+20)
	var credit = rules.gear_sell_credit(price) if slot >= 0 else price
	if slot >= 0:
		if slot >= 10 or carry_index < 0 or carry_index > 3 or quantity != 1 or units[slot].decode_u16(28+carry_index*2) != identity: return false
		rules.put16(units[slot],28+carry_index*2,0)
	else:
		if not rules.sell_quantity_enabled(rules.bag_count(inventory,identity),quantity): return false
		consume_item(identity,quantity)
	add_money(credit*quantity)
	return true

func distribute_experience(pool: int, mode: String = "balance") -> Array:
	var experience: Array = []
	for unit in units:
		if unit.decode_u16(0) == 0: break
		experience.append(unit.decode_s16(44))
	var allocations = rules.equal_distribution(experience,pool) if mode == "equal" else rules.balanced_distribution(experience,pool)
	for i in range(allocations.size()): rules.put16(units[i],44,units[i].decode_s16(44)+allocations[i])
	apply_scene_levels()
	changed.emit()
	return allocations

func apply_scene_levels() -> void:
	for i in range(units.size()):
		if units[i].decode_u16(0) == 0: break
		while units[i].decode_s16(44) >= units[i].decode_u16(4)*100:
			rules.put16(units[i],4,units[i].decode_u16(4)+1)
			var result = rules.grow_record(units[i],true,rng)
			units[i] = result.unit
			rng = result.seeds

func set_map(identity: int) -> void:
	map_id = identity
	map_data = data.load_map(identity)
	navigation.configure(units,map_data,navigation.map_mode)
	highlights.clear()
	changed.emit()

func _pickup_at_actor() -> void:
	#4069B0's caller supplies a selected record; it does not filter its control.
	if selected_slot < 0 or selected_slot >= units.size() or _pickup_active: return
	_pickup_active = true
	_pickup_stage = "scan"
	_pickup_candidate = -1
	_pickup_return_phase = phase
	#41A300(7,currentXY,0,1) captures the query center once. Modal callbacks
	# may change these query globals; cursor/type alone are repaired below.
	interaction_query = {"cursor":0,"type":7,"center":rules.xy(units[selected_slot]),"minimum":0,"maximum":1}
	_pickup_continue()

func _pickup_query_next() -> int:
	while int(interaction_query.cursor) < units.size():
		var slot = int(interaction_query.cursor)
		interaction_query.cursor = slot+1
		var unit: PackedByteArray = units[slot]
		if unit.decode_u16(0) == 0: continue
		if unit.decode_u16(0) != 8 and unit.decode_u16(16) == 9: continue
		var distance = navigation.manhattan(rules.xy(unit),interaction_query.center)
		if distance >= int(interaction_query.minimum) and distance <= int(interaction_query.maximum): return slot
	return -1

func _pickup_notice(kind: String, fields: Dictionary = {}) -> void:
	var request = {"kind":kind,"duration_ms":0,"unit_slot":_pickup_candidate,"source":"430750"}
	request.merge(fields,true)
	_request_modal(request,"pickup")

func _pickup_remove() -> void:
	#41A9E0: release resources while record is live, then zero all124 bytes.
	interaction_requested.emit("actor_remove",{"slot":_pickup_candidate,"source":"406AAF/406AE9"})
	units[_pickup_candidate].fill(0)
	_pickup_stage = "next"

func _pickup_continue() -> void:
	while _pickup_active and not _modal_waiting:
		match _pickup_stage:
			"scan":
				_pickup_candidate = _pickup_query_next()
				if _pickup_candidate < 0:
					_pickup_active = false
					_pickup_stage = ""
					# Window-presence guards are evaluated by the actual UI consumer.
					interaction_requested.emit("overview_invalidate",{"source":"406B74","if_open":true})
					interaction_requested.emit("unit_list_refresh",{"source":"406B92","message":1024,"if_open":true})
					# Legacy operation labels are retained for typed endpoint traces.
					#41DD50 is satellite-list107 visibility/refresh (fullscreen no-op),
					#432890 is overview visibility; neither enables general player input.
					interaction_requested.emit("input_gate",{"source":"406B9A","helper":"41DD50","argument":1,"meaning":"satellite_unit_list_visibility","enabled":true})
					interaction_requested.emit("event_gate",{"source":"406BA4","helper":"432890","argument":1,"meaning":"overview_visibility","enabled":true})
					return
				var candidate: PackedByteArray = units[_pickup_candidate]
				if candidate.decode_u16(18) != 7: continue
				_pickup_stage = "next"
				#4069F7 reloads selected44EA10 for every candidate after modal reentry.
				var distance = navigation.manhattan(rules.xy(candidate),rules.xy(units[selected_slot]))
				if distance == 0:
					sound_requested.emit("find",false)
					var identity = candidate.decode_u16(28)
					if identity != 0:
						_pickup_stage = "grant"
						_pickup_notice("pickup_item",{"item_id":identity})
						return
					# Money has a find sound too; raw unsigned U1E is the notice value.
					add_money(candidate.decode_u16(30))
					_pickup_stage = "remove"
					_pickup_notice("pickup_gold",{"amount":units[_pickup_candidate].decode_u16(30)})
					return
				elif distance == 1 and candidate.decode_u16(16) == 9:
					sound_requested.emit("find",false)
					rules.put16(candidate,16,0)
					interaction_requested.emit("appearance_refresh",{"slot":_pickup_candidate,"source":"406B1D"})
					interaction_requested.emit("surface_restore",{"copy":0,"source":"406B27"})
					_pickup_notice("pickup_found")
					return
			"grant":
				# Notice returns before either pointer/item is read again.
				var identity = units[_pickup_candidate].decode_u16(28)
				if grant_item(selected_slot,identity,1):
					# Current EVENT only. No fallback and no wait for script execution.
					hook_requested.emit(_request(event_id,"get%03d"%units[_pickup_candidate].decode_u16(28),"pickup",_pickup_candidate))
					_pickup_remove()
				else:
					_pickup_stage = "next"
					_pickup_notice("pickup_capacity")
					return
			"remove": _pickup_remove()
			"next":
				#41A300(1,candidate+124,7) repairs the mutable cursor/type only.
				interaction_query.cursor = _pickup_candidate+1
				interaction_query.type = 7
				_pickup_stage = "scan"
