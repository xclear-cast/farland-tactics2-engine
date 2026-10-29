extends RefCounted
## Opt-in testing adapter. AI scores suggest inputs; all game changes go through
## existing player/UI methods. This is not an original allied-auto-play feature.
var enabled = true
var town_enabled = false # Additional opt-in for legal town-place visits.
var items_enabled = false # Optional public bag-item support; no inventory writes here.
var global_route_enabled = false # Test-only multi-turn topology routing fallback.
var route_count = 0
var last_route: Dictionary = {}
var _route_map = -1
var _route_positions: Dictionary = {}
var town_visits: Dictionary = {}
var journal: Array = []
var quarantined: Dictionary = {}
var command_count = 0
var decision_count = 0
var _turn = ""
var _queue: Array = []
var _slot = -1
var _attempts: Dictionary = {}
var _last_fingerprint: Dictionary = {}
var _last_phase = ""

func snapshot() -> Dictionary:
	return {"adapter":"public-player-input-test","enabled":enabled,"town_enabled":town_enabled,"items_enabled":items_enabled,"global_route_enabled":global_route_enabled,"routes":route_count,"last_route":last_route.duplicate(true),"commands":command_count,"decisions":decision_count,"turn":_turn,"quarantined":quarantined.duplicate(true),"queued":_queue.size(),"last_events":journal.slice(maxi(0,journal.size()-30))}

func _record(event: Dictionary) -> Array:
	command_count += 1
	event["serial"] = command_count
	journal.append(event)
	if journal.size() > 2000: journal.pop_front()
	return [event]

func _key(target,code: int) -> bool:
	var input = InputEventKey.new(); input.pressed = true; input.keycode = code
	return bool(target.handle_input(input))

func _fingerprint(battle,slot: int) -> String:
	return str(battle.map_id)+":"+str(battle.round_index)+":"+str(battle.units[slot].hex_encode())

func _quarantine(reason: String) -> Array:
	quarantined[_slot] = reason
	_queue.clear()
	return _record({"op":"quarantine","slot":_slot,"reason":reason,"scope":"Skipped by test adapter for this turn; game state unmodified"})

func tick(battle,ui,vm,_view = null) -> Array:
	if not enabled: return []
	var turn = "%d:%d" % [int(battle.map_id),int(battle.round_index)]
	if turn != _turn:
		_turn = turn; quarantined.clear(); _attempts.clear(); _last_fingerprint.clear(); _queue.clear(); _slot = -1
	if int(battle.map_id) != _route_map:
		_route_map = int(battle.map_id); _route_positions.clear(); last_route.clear()
	if ui.dialog != "":
		if battle.phase == "confirm":
			var allowed = bool(ui.payload.get("can_confirm",true)) and not ui.payload.get("ordered_targets",[]).is_empty()
			for row in ui.menu_rows:
				if int(row.get("id",0)) == 40024 and (int(row.get("flags",0))&3) != 0: allowed = false
			ui.command(40024 if allowed else 40025)
			if not allowed and _slot >= 0: quarantined[_slot] = "empty or disabled confirmation"
			_queue.clear()
			return _record({"op":"ui.command","id":40024 if allowed else 40025,"slot":_slot})
		if ui.dialog == "experience":
			# Dialog162 initially focuses balance, so Enter alone never confirms.
			# Follow its real dialog-manager Tab order until IDOK has focus.
			var code = KEY_ENTER if int(ui.experience.focus) == 1 else KEY_TAB
			return _record({"op":"ui.handle_input","dialog":"experience","key":"Enter" if code == KEY_ENTER else "Tab","accepted":_key(ui,code)})
		if ui.dialog in ["message","battle_message","scene_growth","choice","end_turn"]:
			var dialog = str(ui.dialog)
			return _record({"op":"ui.handle_input","dialog":dialog,"key":"Y" if dialog == "end_turn" else "Enter","accepted":_key(ui,KEY_Y if dialog == "end_turn" else KEY_ENTER)})
		if town_enabled and ui.dialog in ["shop","buy_quantity","buy_receiver","sell_quantity","equipment","units","status"]:
			return _record({"op":"ui.handle_input","dialog":str(ui.dialog),"key":"Escape","accepted":_key(ui,KEY_ESCAPE)})
		return []
	if vm.busy:
		if vm.input_wait and not vm.modal_wait:
			return _record({"op":"vm.handle_input","key":"Enter","accepted":_key(vm,KEY_ENTER)})
		return []
	if town_enabled and int(vm.mode) == 9:
		var key = str(vm.current_event)+":"+JSON.stringify(vm.variables)+":"+str(vm.town.enabled)
		var tried: Array = town_visits.get(key,[])
		var priority: Array = [2,0,1,3,4,5,6,7,8,9,10,11,12,13,14]
		var selected = -1
		for place in priority:
			if place < vm.town.enabled.size() and vm.town.enabled[place] != 0 and not tried.has(place): selected = int(place); break
		if selected < 0:
			for place in priority:
				if place < vm.town.enabled.size() and vm.town.enabled[place] != 0: selected = int(place); break
			tried = []
		if selected < 0: return []
		tried.append(selected); town_visits[key] = tried
		vm.town.select_place(selected)
		return _record({"op":"town.select_place","place":selected,"chapter":vm.current_event,"scope":"Test visit priority borrowed from transition harness; source enabled-place guard retained"})
	if int(vm.mode) != 1 or battle.phase != "player":
		_last_phase = str(battle.phase)
		return []
	if _last_phase != "player": _last_phase = "player"
	if not _queue.is_empty(): return _execute(battle)
	if int(battle.substate) != 0:
		battle.cancel_selection()
		return _record({"op":"cancel_selection","reason":"adapter reset selection before next legal action"})
	for slot in range(battle.units.size()):
		var unit: PackedByteArray = battle.units[slot]
		if unit.decode_u16(0) == 0 or unit.decode_u16(18) != 0 or unit.decode_u16(16) in battle.rules.INCAP: continue
		if unit.decode_s32(92) != 0 and unit.decode_s32(96) != 0: continue
		if quarantined.has(slot): continue
		_slot = slot
		var fingerprint = _fingerprint(battle,slot)
		if _last_fingerprint.get(slot,"") == fingerprint: _attempts[slot] = int(_attempts.get(slot,0))+1
		else: _attempts[slot] = 0
		_last_fingerprint[slot] = fingerprint
		if int(_attempts[slot]) >= 3: return _quarantine("three repeated decisions without unit-byte progress")
		if items_enabled:
			var item_plan = _item_suggestion(battle,slot)
			if not item_plan.is_empty():
				_queue = [{"op":"select_unit","value":slot}]
				if item_plan.position != battle.rules.xy(unit):
					_queue.append_array([{"op":"choose_action","value":0},{"op":"select_cell","point":item_plan.position},{"op":"face","value":battle.navigation.facing(item_plan.position,item_plan.target)}])
				else: _queue.append_array([{"op":"choose_action","value":1000+int(item_plan.item_id)},{"op":"select_cell","point":item_plan.target}])
				return _record({"op":"item_decision","slot":slot,"item_id":item_plan.item_id,"target_slot":item_plan.target_slot,"position":[item_plan.position.x,item_plan.position.y],"target":[item_plan.target.x,item_plan.target.y],"purpose":item_plan.purpose,"bag_quantity":item_plan.quantity})
		var decision: Dictionary = battle.ai.decision(slot)
		decision_count += 1
		var origin = battle.rules.xy(unit)
		var position: Vector2i = decision.position
		var target: Vector2i = decision.target
		var action = int(decision.action_id)
		if global_route_enabled and not bool(decision.has_action):
			var positions: Array = _route_positions.get(slot,[])
			var repeated = positions.count(origin) >= 2
			positions.append(origin)
			if positions.size() > 8: positions.pop_front()
			_route_positions[slot] = positions
			if position == origin or repeated:
				var route = _global_route_suggestion(battle,slot)
				if route.has("position"):
					position = route.position
					_queue = [{"op":"select_unit","value":slot},{"op":"choose_action","value":0},{"op":"select_cell","point":position},{"op":"face","value":int(unit.decode_u16(6))}]
					route_count += 1
					return _record({"op":"global_route","slot":slot,"position":[position.x,position.y],"origin":[origin.x,origin.y],"distance_before":route.distance_before,"distance_after":route.distance_after,"source_grid_value":route.grid_value,"goal_count":route.goal_count,"scope":"Test topology fallback; endpoint must pass current source movement grid"})
		if position == origin and not bool(decision.has_action): return _quarantine("AI suggestion has no legal work at current position")
		_queue = [{"op":"select_unit","value":slot}]
		if position != origin:
			_queue.append({"op":"choose_action","value":0})
			_queue.append({"op":"select_cell","point":position})
			if bool(decision.has_action) and action == 0:
				_queue.append({"op":"select_cell","point":target})
			else:
				# Movement commits through facing, then the next decision can cast.
				_queue.append({"op":"face","value":battle.navigation.facing(position,target) if bool(decision.has_action) else int(unit.decode_u16(6))})
		elif action > 0:
			_queue.append({"op":"choose_action","value":action})
			# Self-centred/all-map skills enter confirmation in choose_action.
			if battle.rules.magics.decode_u16(action*64+50) not in [3,4]: _queue.append({"op":"select_cell","point":target})
		else:
			_queue.append({"op":"choose_action","value":0})
			_queue.append({"op":"select_cell","point":target})
		return _record({"op":"decision","slot":slot,"position":[position.x,position.y],"target":[target.x,target.y],"action_id":action,"has_action":decision.has_action,"origin":[origin.x,origin.y]})
	ui.command(40009)
	return _record({"op":"ui.command","id":40009,"reason":"all actionable allies consumed or adapter-quarantined"})

func _item_suggestion(battle,slot: int) -> Dictionary:
	var actor: PackedByteArray = battle.units[slot]
	if actor.decode_s32(96) != 0 or not battle.menu_flags(slot).get("items_parent",false): return {}
	var table: Array = battle.data.load_table("item")
	var origin = battle.rules.xy(actor)
	var best: Dictionary = {}; var best_score = -1
	battle.navigation.movement_grid(slot)
	for entry in battle.available_items():
		var id = int(entry.item_id)
		if id <= 0 or id >= table.size() or int(entry.quantity) <= 0: continue
		var item: Dictionary = table[id]
		if int(item.get("category",0)) != 3: continue
		var hp = int(item.get("effect1",0)); var mp = int(item.get("effect2",0)); var cure = int(item.get("state_code",0))
		for target_slot in range(mini(10,battle.units.size())):
			var target: PackedByteArray = battle.units[target_slot]
			if target.decode_u16(0) == 0 or target.decode_u16(16) == 9: continue
			var state = target.decode_u16(16); var score = -1; var purpose = ""
			if state == 1:
				# Native item gate requires state_code1 before applying HP or cure.
				if cure == 1 and hp > 0: score = 100000+hp; purpose = "revive"
			elif state != 0 and (id in [6,163] or (id == 7 and state == 3) or (id in [8,9] and state == 5) or cure == state):
				score = 7000 if state == 6 else 6000; purpose = "cure_state%d" % state
			elif cure != 1 and hp > 0 and target.decode_s16(38)*100 < target.decode_s16(36)*45:
				score = 5000+battle.rules.div0((target.decode_s16(36)-target.decode_s16(38))*100,maxi(1,target.decode_s16(36))); purpose = "low_hp"
			elif cure != 1 and mp > 0 and target.decode_s16(42)*100 < target.decode_s16(40)*20 and target.decode_u16(56) > 0:
				score = 3000; purpose = "low_mp"
			if score < 0: continue
			var target_point = battle.rules.xy(target)
			var minimum = int(item.get("target_distance_min_raw",0)); var maximum = int(item.get("target_distance_max_raw",1))
			var position = origin; var distance = battle.navigation.manhattan(origin,target_point)
			if distance < minimum or distance > maximum:
				if actor.decode_s32(92) != 0: continue
				var closest = distance
				for offset in battle.navigation.grid:
					var point: Vector2i = origin+offset
					if not battle.navigation.selectable(point): continue
					var other = battle.navigation.occupant(point)
					if other >= 0 and other != slot: continue
					var candidate = battle.navigation.manhattan(point,target_point)
					if candidate < closest and candidate >= minimum: position = point; closest = candidate
				if position == origin: continue
				score -= 100+closest*10
			if score > best_score:
				best_score = score
				best = {"position":position,"target":target_point,"target_slot":target_slot,"item_id":id,"quantity":int(entry.quantity),"purpose":purpose}
	return best

func _heap_push(heap: Array,entry: Array) -> void:
	heap.append(entry)
	var child = heap.size()-1
	while child > 0:
		var parent: int = (child-1)/2
		if int(heap[parent][0]) <= int(entry[0]): break
		heap[child] = heap[parent]; child = parent
	heap[child] = entry

func _heap_pop(heap: Array) -> Array:
	var answer: Array = heap[0]
	var tail: Array = heap.pop_back()
	if heap.is_empty(): return answer
	var parent = 0
	while parent*2+1 < heap.size():
		var child = parent*2+1
		if child+1 < heap.size() and int(heap[child+1][0]) < int(heap[child][0]): child += 1
		if int(tail[0]) <= int(heap[child][0]): break
		heap[parent] = heap[child]; parent = child
	heap[parent] = tail
	return answer

func _global_route_suggestion(battle,slot: int) -> Dictionary:
	var nav = battle.navigation
	var actor: PackedByteArray = battle.units[slot]
	var origin = battle.rules.xy(actor)
	last_route = {"map":battle.map_id,"slot":slot,"origin":[origin.x,origin.y],"reason":"no_legal_movement"}
	if actor.decode_s32(92) != 0: return {}
	nav.movement_grid(slot)
	var vertices: Dictionary = {}; var endpoint_clear: Dictionary = {}
	for point in nav.cells:
		var cell = nav.cell(point)
		if not nav.inside(point) or int(cell[2]) != 0: continue
		var other = nav.occupant(point)
		var clear = other < 0 or other == slot
		if other >= 0 and other != slot:
			var occupant: PackedByteArray = battle.units[other]
			clear = occupant.decode_u16(18) == 7 or occupant.decode_u16(0) == 8
			# Friendly units may be crossed by the source flood but cannot be endpoints.
			if not clear and battle.rules.hostile(actor,occupant): continue
		vertices[point] = true; endpoint_clear[point] = clear
	var hostiles: Array = []
	for other in range(battle.units.size()):
		var unit: PackedByteArray = battle.units[other]
		if unit.decode_u16(0) == 0 or unit.decode_u16(16) in [1,9] or unit.decode_u16(18) == 7: continue
		if battle.rules.hostile(actor,unit,other == slot): hostiles.append(battle.rules.xy(unit))
	var weapon = actor.decode_u16(20)*56
	var minimum = battle.rules.items.decode_u16(weapon+42);var maximum = battle.rules.items.decode_u16(weapon+44)
	var shape = battle.rules.items.decode_u16(weapon+50)
	var distance: Dictionary = {}; var heap: Array = []; var goals = 0
	for point in vertices:
		if not endpoint_clear[point]: continue
		for target in hostiles:
			var range_value = nav.manhattan(point,target)
			if range_value < minimum or range_value > maximum: continue
			if shape != 3 and absi(nav.height(point)-nav.height(target)) > 4: continue
			if shape == 1 and point.x != target.x and point.y != target.y: continue
			distance[point] = 0; _heap_push(heap,[0,point]); goals += 1; break
	last_route.merge({"vertices":vertices.size(),"hostiles":hostiles.size(),"goal_count":goals})
	if goals == 0: last_route.reason = "no_geometric_attack_goals"; return {}
	var limits: Vector2i = nav.limits(slot)
	while not heap.is_empty():
		var entry = _heap_pop(heap); var cost = int(entry[0]); var point: Vector2i = entry[1]
		if cost != int(distance.get(point,2147483647)): continue
		# Reverse directed edges: predecessor->point must satisfy original climb/descend.
		for direction in nav.DIRS:
			var predecessor = point+direction
			if not vertices.has(predecessor): continue
			var delta = nav.height(point)-nav.height(predecessor)
			if delta > limits.x or -delta > limits.y: continue
			var candidate = cost+maxi(1,int(nav.cost(slot,point)))
			if candidate < int(distance.get(predecessor,2147483647)):
				distance[predecessor] = candidate; _heap_push(heap,[candidate,predecessor])
	if not distance.has(origin): last_route.reason = "origin_cannot_reach_attack_goal_in_topology"; return {}
	var best: Vector2i = origin; var best_distance = int(distance[origin]);var best_grid = 0
	for offset in nav.grid:
		var point: Vector2i = origin+offset
		if not nav.selectable(point) or not endpoint_clear.get(point,false) or not distance.has(point): continue
		var candidate = int(distance[point])
		if candidate < best_distance:
			best = point; best_distance = candidate;best_grid = int(nav.grid[offset])
	if best == origin: last_route.reason = "no_current_source_grid_endpoint_reduces_global_distance"; return {}
	last_route.merge({"reason":"route_endpoint","distance_before":int(distance[origin]),"distance_after":best_distance,"position":[best.x,best.y],"source_grid_value":best_grid},true)
	return {"position":best,"distance_before":int(distance[origin]),"distance_after":best_distance,"grid_value":best_grid,"goal_count":goals}

func _execute(battle) -> Array:
	var command: Dictionary = _queue.pop_front()
	var accepted = false
	match command.op:
		"select_unit": accepted = battle.select_unit(int(command.value))
		"choose_action": accepted = battle.choose_action(int(command.value))
		"select_cell": accepted = battle.select_cell(Vector2i(command.point))
		"face":
			if int(battle.substate) == 1:
				accepted = battle.select_cell(battle.rules.xy(battle.units[_slot]))
				if accepted: _queue.push_front(command)
			elif int(battle.substate) == 2: accepted = battle.commit_facing(int(command.value))
	command = command.duplicate(); command["slot"] = _slot; command["accepted"] = accepted
	if not accepted:
		_queue.clear()
		quarantined[_slot] = "public method rejected %s" % command.op
		battle.cancel_selection()
	return _record(command)
