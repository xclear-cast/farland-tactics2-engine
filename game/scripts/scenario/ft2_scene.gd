class_name FT2Scene
extends RefCounted
## Executes the captured ordered C leaf transducers, with real layer/queue state.
## Unsupported backend operations stop the controller and are exposed in errors.
signal operation(command: Dictionary)
var data
var battle
var busy := false
var selector := 0
var profile := 0
var phase := 0
var local_state := 0
var aux := 0
var now := 0
var errors: Array[String] = []
var trace: Array[Dictionary] = []
var _graph: Dictionary = {}
var _model: Dictionary = {}
var _bindings: Array = []
var _cues: Array = []
var _sizes: Dictionary = {}
var _pending_finish := false
var _lifecycle := 0
var _pending_edge: Dictionary = {}
var _pending_index := 0
var _players: Dictionary = {}
var _trig: Array = []
var measure_text: Callable
const PATTERNS := [[0,260,1285,34085,42405,46565,62965,65015,65535],[65535,65015,62965,46565,42405,34085,1285,260,0]]
const GRAPH_PATH := "data/port_ready/scripts/cinematics/contracts/leaf_graphs/profile%02d_phase%02d.json"

func _init(store, combat = null) -> void:
	data = store; battle = combat
	_trig = data.read_json("data/port_ready/effects/spec/fixed_trig_contract.json").quarter_wave_u16
	_bindings = data.read_json("data/port_ready/scripts/spec/runtime_bindings.json").visual_sequence_selector.entries
	_cues = data.read_json("data/port_ready/scripts/cinematics/DATA/VSLLST.json").records
	for row in data.read_json("data/port_ready/assets/bitmaps/index.json").files:
		_sizes[str(row.source).get_file().get_basename().to_upper()] = Vector2i(int(row.size[0]),int(row.size[1]))

func start(value: int) -> bool:
	if value < 0 or value >= _bindings.size(): return false
	selector = value; profile = int(_bindings[value].state_selector_word); phase = int(_bindings[value].second_parameter_word)
	local_state = 0; aux = 0; _pending_finish = false; _lifecycle = 0
	_model = {"local_epoch":now,"global_epoch":now,"palette_until":now,"layers":{},"queues":{},"bitmaps":{},"motions":{},"dithers":{},"photos":{},"scalars":{},"order":[],"clip":Rect2i(0,0,640,480),"wave_slots":{},"bands":{},"apd_resources":{},"apd_instances":{},"credits":{},"callbacks":{},"rng":battle.rng.duplicate() if battle != null else [167,19960,5150]}
	_pending_edge.clear(); _players.clear()
	busy = _load_graph()
	return busy

func _load_graph() -> bool:
	var path := GRAPH_PATH % [profile,phase]
	if not FT2Content.exists(data.resolve(path)):
		errors.append("Missing source scene graph %d/%d" % [profile,phase]); return false
	_graph = data.read_json(path)
	return true

func advance(ms: int) -> void:
	now += maxi(0,ms)
	if not busy: return
	if _lifecycle == 0:
		_lifecycle = 1
		return
	if _pending_finish:
		busy = false; return
	if not _pending_edge.is_empty():
		if now >= int(_model.palette_until): _commit_edge(_pending_edge,_pending_index)
		_advance_backend(_model)
		return
	var matched := false
	for edge in _graph.get("edges",[]):
		if int(edge.input_local_state) != local_state or int(edge.input_aux44B098) != aux: continue
		var candidate: Dictionary = _model.duplicate(true)
		var ok := true
		var committed: Array = []
		for instruction in edge.ordered_operations:
			if instruction.has("write_scalar"):
				var write: Dictionary = instruction.write_scalar
				candidate.scalars[str(write.address)] = int(write.value)
			else:
				var command: Dictionary = instruction.engine_call
				var result := _apply(command,candidate)
				if command.has("observed_predicate_value") and result != int(command.observed_predicate_value): ok = false; break
				if not command.has("observed_predicate_value"): committed.append(command)
		if not ok: continue
		matched = true
		_commit_edge(edge,0)
		break
	if not matched:
		errors.append("No captured C scene transition %d/%d state%d aux%d" % [profile,phase,local_state,aux]); busy = false
	_advance_backend(_model)

func _commit_edge(edge: Dictionary, start_index: int) -> void:
	var instructions: Array = edge.ordered_operations
	_pending_edge = {}
	for index in range(start_index,instructions.size()):
		var instruction: Dictionary = instructions[index]
		if instruction.has("write_scalar"):
			var write: Dictionary = instruction.write_scalar
			_model.scalars[str(write.address)] = int(write.value)
			continue
		var command: Dictionary = instruction.engine_call
		if str(command.operation) == "palette_wait_pump" and now < int(_model.palette_until):
			_pending_edge = edge; _pending_index = index+1; return
		_apply(command,_model)
		if not command.has("observed_predicate_value"): operation.emit(command)
	local_state = int(edge.next_local_state); aux = int(edge.next_aux44B098)
	trace.append({"profile":profile,"phase":phase,"local":local_state,"time":now,"operations":edge.ordered_commands})
	if int(edge["return"]) == 0: _next_phase()

func _next_phase() -> void:
	if profile == 0 and phase < 17:
		phase += 1; local_state = 0; aux = 0; busy = _load_graph()
	elif profile == 13 and phase < 5:
		phase += 1; local_state = 0; aux = 0; busy = _load_graph()
	else:
		_pending_finish = true

func skip() -> void:
	# Original sequence input has its own skip policy; caller must opt in explicitly.
	_pending_finish = true

func _layer(model: Dictionary,id: int) -> Dictionary:
	if not model.layers.has(id): model.layers[id] = {"bitmap":-1,"dst":Vector2i.ZERO,"source":Rect2i(),"visible":true,"key":-1,"offset":Vector2i.ZERO,"mask":0,"fill":-1,"remaps":[]}
	return model.layers[id]

func _apply(command: Dictionary,m: Dictionary) -> int:
	var name := str(command.operation); var a: Array = command.get("args",[])
	match name:
		"load_visual_cue","load_cue_reset_local_epoch":
			if name == "load_cue_reset_local_epoch": m.local_epoch = now
			for cue in _cues:
				if int(cue.sequence_selector) != profile or int(cue.cue_index) != int(a[0]): continue
				var stem := str(cue.bitmap_stem).to_upper()
				if stem == "NO_ENTRY": continue
				m.bitmaps[int(cue.resource_id)] = {"stem":stem,"remaps":[[int(cue.load4271F0_arg3),int(cue.load4271F0_arg4),int(cue.load4271F0_arg2)]] if int(cue.load4271F0_arg4) != 0 else []}
		"release_cue_reset_scene":
			m["last_released_waves"] = m.wave_slots.values().duplicate()
			m.layers.clear(); m.queues.clear(); m.motions.clear(); m.dithers.clear(); m.wave_slots.clear(); m.apd_instances.clear(); m.apd_resources.clear(); m.credits.clear(); m.callbacks.clear(); m.local_epoch = now
		"reset_layer_scene":
			m.layers.clear(); m.queues.clear(); m.motions.clear(); m.dithers.clear()
		"global_epoch_now_plus_offset": m.global_epoch = now+int(a[0])
		"midi_profile_start_reset_global_epoch": m.global_epoch = now
		"global_elapsed_le_threshold": return int(_s32(now-int(m.global_epoch)) <= int(a[0]))
		"local_elapsed_lt_threshold": return int(_s32(now-int(m.local_epoch)) < int(a[0]))
		"palette_busy": return int(now < int(m.palette_until))
		"palette_wait_pump": m.palette_until = now
		"palette_fade_playable": m.palette_until = now+maxi(0,int(a[0]))*128
		"palette_fade_range": m.palette_until = now+maxi(0,int(a[2]))*128
		"palette_fill_playable","palette_fill_range": m.palette_until = now
		"palette_copy_bitmap","palette_set_entry_RGB": pass
		"layer_draw_order": m.order = command.get("draw_order",[]).duplicate()
		"screen_clip_rect": m.clip = Rect2i(int(a[0]),int(a[1]),int(a[2])-int(a[0]),int(a[3])-int(a[1]))
		"layer_crop":
			_crop(m,int(a[0]),int(a[3]),Vector2i(int(a[1]),int(a[2])),Rect2i(int(a[4]),int(a[5]),int(a[6]),int(a[7])))
		"layer_transparent_index": _layer(m,int(a[0])).key = int(a[1])
		"layer_visible": _layer(m,int(a[0])).visible = int(a[1]) != 0
		"layer_aux_offset": _layer(m,int(a[0])).offset = Vector2i(int(a[1]),int(a[2]))
		"layer_fill_rect":
			var l := _layer(m,int(a[0])); l.dst = Vector2i(int(a[1]),int(a[2])); l.source = Rect2i(0,0,int(a[3]),int(a[4])); l.fill = int(a[5])
		"layer_clear_drawable":
			var l := _layer(m,int(a[0])); l.bitmap = -1; l.fill = -1
		"layer_motion","layer_motion_cycles":
			var flags := int(a[8] if a.size() > 8 else a[7]); var dx := int(a[4]); var dy := int(a[5])
			if int(a[1]) == -1 or flags & 16: dx = -dx; dy = -dy
			if flags & 32: dx = -dx
			if flags & 64: dy = -dy
			m.motions[int(a[0])] = {"ref":int(a[1]),"start":Vector2i(int(a[2]),int(a[3])),"delta":Vector2i(dx,dy),"period":int(a[6]),"flags":flags,"epoch":now if flags & 2 else 0,"limit":int(a[7]) if a.size()>8 else 0}
		"layer_motion_start":
			if m.motions.has(int(a[0])):
				var motion: Dictionary = m.motions[int(a[0])]
				motion.flags = (int(motion.flags)|2) if int(a[1]) != 0 else (int(motion.flags)&~2); motion.epoch = now
				if int(a[1]) != 0: _motion_apply(m,int(a[0]),motion.start,motion)
		"layer_motion_busy": return int(m.motions.has(int(a[0])) and (int(m.motions[int(a[0])].flags)&2) != 0)
		"bitmap_queue_create": m.queues[int(a[0])] = {"layer":int(a[1]),"repeat":int(a[2]),"capacity":int(a[3]),"nodes":[],"index":0,"epoch":0,"active":false,"offset":Vector2i.ZERO,"policy":int(a[2]) >= 0}
		"bitmap_queue_append":
			if m.queues.has(int(a[0])):
				var q: Dictionary = m.queues[int(a[0])]
				if q.nodes.size() < int(q.capacity) and m.bitmaps.has(int(a[3])): q.nodes.append([int(a[3]),int(a[1]),int(a[2]),int(a[4]),int(a[5]),int(a[6]),int(a[7]),int(a[8])])
		"bitmap_queue_from_list":
			var nodes: Array = []
			for id in command.get("bitmap_ids",[]):
				if m.bitmaps.has(int(id)): nodes.append([int(id),int(a[2]),int(a[3]),int(a[4]),int(a[5]),int(a[6]),int(a[7]),int(a[8])])
			m.queues[int(a[0])] = {"layer":int(a[1]),"repeat":int(a[9]),"capacity":nodes.size(),"nodes":nodes,"index":0,"epoch":0,"active":false,"offset":Vector2i.ZERO,"policy":int(a[9])>=0}
		"bitmap_queue_from_sheet":
			var nodes: Array = []
			if m.bitmaps.has(int(a[8])):
				var size: Vector2i = _sizes.get(str(m.bitmaps[int(a[8])].stem),Vector2i.ZERO)
				if int(a[4]) > 0 and int(a[5]) > 0:
					for y in range(0,size.y,int(a[5])):
						for x in range(0,size.x,int(a[4])): nodes.append([int(a[8]),int(a[2]),int(a[3]),x,y,int(a[4]),int(a[5]),int(a[6])])
			m.queues[int(a[0])] = {"layer":int(a[1]),"repeat":int(a[7]),"capacity":nodes.size(),"nodes":nodes,"index":0,"epoch":0,"active":false,"offset":Vector2i.ZERO,"policy":int(a[7])>=0}
		"bitmap_queue_start":
			if m.queues.has(int(a[0])): m.queues[int(a[0])].active = int(a[1]) != 0; m.queues[int(a[0])].epoch = 0
		"bitmap_queue_busy": return int(m.queues.has(int(a[0])) and m.queues[int(a[0])].active)
		"bitmap_queue_past_first": return int(m.queues.has(int(a[0])) and m.queues[int(a[0])].policy and int(m.queues[int(a[0])].index)>=1)
		"layer_dither_pattern": m.dithers[int(a[0])] = {"rect":Rect2i(int(a[1]),int(a[2]),int(a[3]),int(a[4])),"duration":int(a[5]),"masks":PATTERNS[clampi(int(a[6]),0,1)].duplicate(),"active":false,"epoch":0}
		"layer_dither_set":
			var l := _layer(m,int(a[0])); l.mask = int(a[5]); l.mask_rect = Rect2i(int(a[1]),int(a[2]),int(a[3]),int(a[4]))
		"layer_dither_start":
			if m.dithers.has(int(a[0])): m.dithers[int(a[0])].active = int(a[1]) != 0; m.dithers[int(a[0])].epoch = now
		"layer_dither_busy": return int(m.dithers.has(int(a[0])) and m.dithers[int(a[0])].active)
		"palette_band_cycle": m.bands[int(a[0])] = {"first":int(a[1]),"span":absi(int(a[2])),"reverse":int(a[2]) > 0,"period":int(a[3]),"limit":int(a[4]),"cycles":0,"offset":0,"epoch":now if int(a[5]) != 0 else 0,"tracked":int(a[5]) != 0,"active":true}
		"palette_band_stop":
			if m.bands.has(int(a[0])): m.bands[int(a[0])].active = false
		"palette_band_busy": return int(m.bands.has(int(a[0])) and m.bands[int(a[0])].active and m.bands[int(a[0])].tracked)
		"APD_resource_load_remap": m.apd_resources[int(a[0])] = {"stem":str(command.get("string_argument","")),"palette_start":int(a[2]),"palette_count":int(a[3])}
		"APD_resource_palette_restore": pass # The view receives this palette operation at the exact source command boundary.
		"APD_instance_create": m.apd_instances[int(a[0])] = {"resource":int(a[1]),"pos":Vector2i(int(a[2]),int(a[3])),"priority":int(a[4]),"label":"","epoch":now,"flags":0}
		"APD_instance_play_label":
			if m.apd_instances.has(int(a[0])):
				var instance: Dictionary = m.apd_instances[int(a[0])]
				instance.label = str(command.get("string_argument","")); instance.epoch = now; instance.flags = int(a[2])
		"credits_scroll_start": _start_credits(m,int(a[0]),int(a[2]))
		"credits_scroll_enable":
			if not m.credits.is_empty(): m.credits.active = true; m.credits.epoch = now
		"credits_scroll_busy": return int(not m.credits.is_empty() and m.credits.active)
		"text_group_children_busy": return 0 # No child dither is running unless explicitly started by a group command.
		"credits_group_destroy": m.credits.clear()
		"photo_move_palette_envelope":
			if m.bitmaps.has(int(a[1])):
				var size: Vector2i = _sizes.get(str(m.bitmaps[int(a[1])].stem),Vector2i.ZERO)
				var center := Vector2i(int(a[4]),int(a[5]))-size/2
				var l := _layer(m,int(a[0])); l.bitmap = int(a[1]); l.source = Rect2i(Vector2i.ZERO,size); l.dst = Vector2i.ZERO; l.offset = center
				m.motions[int(a[0])] = {"ref":-1,"start":center,"delta":Vector2i(int(a[6])-int(a[4]),int(a[7])-int(a[5])),"period":int(a[8]),"flags":2,"epoch":now,"limit":0}
				m.photos[int(a[0])] = {"epoch":now,"total":int(a[8]),"tail":int(a[9]),"first":int(a[2]),"count":int(a[3])}
				m.palette_until = now+int(int(a[9])/128)*128
		"layer_callback_surface_create":
			var family := 0
			var callbacks: Array = [4325248,4325696,4326128,4326448]
			family = callbacks.find(int(a[1]))
			if family < 0: return 0
			var cached_layer := _layer(m,int(a[0]))
			cached_layer.source = Rect2i(Rect2i(cached_layer.source).position,Vector2i(640,480))
			var particles: Array = []
			for index in 80:
				if family == 3: particles.append([_rng(m,640),_rng(m,480),0,0,_rng(m,3)+4])
				else: particles.append([_rng(m,1280)-640,_rng(m,960)-(1280 if family == 2 else 480),0,_rng(m,300),0])
			m.callbacks[int(a[0])] = {"family":family,"particles":particles,"last":0,"bitmap":str(command.get("bitmap_path","BMP/STAR.BMP")).replace("\\","/").to_upper(),"remaps":[[10,int(a[6]),int(a[5])]] if int(a[6]) != 0 else []}
		"wave_load_slot": m.wave_slots[int(a[0])] = command.get("relative_path",m.get("formatted_path",""))
		"wave_release_all": m["last_released_waves"] = m.wave_slots.values().duplicate(); m.wave_slots.clear()
		"format_resource_path": m["formatted_path"] = str(command.get("relative_path",""))
		"wave_slot_play_stop","wave_play_path","render_present": pass
		"callback_slots_clear": m.callbacks.clear()
		_:
			# Do not silently invent APD, credits or photo behavior for a C service.
			if not errors.has(name): errors.append(name)
	return 1

func _advance_backend(m: Dictionary) -> void:
	#42AA20 services42B5E0 before band cycles and layer motion.42B600 uses
	#strict signed(now)>signed(epoch+total-tail), then restores and fades black.
	for id in m.photos.keys():
		var photo: Dictionary = m.photos[id]
		if _s32(now) <= _s32(int(photo.epoch)+int(photo.total)-int(photo.tail)): continue
		var interval := int(int(photo.tail)/128)
		operation.emit({"operation":"palette_fade_range","args":[int(photo.first),int(photo.count),0,1]})
		operation.emit({"operation":"palette_fade_range","args":[int(photo.first),int(photo.count),interval,2]})
		m.palette_until = now+interval*128
		m.photos.erase(id)
	for id in m.bands:
		var band: Dictionary = m.bands[id]
		if not band.active or int(band.period) <= 0: continue
		if _s32(int(band.epoch)+int(band.period)) < _s32(now): band.cycles = int(band.cycles)+1; band.epoch = now
		var offset := int(float(_s32(now-int(band.epoch)))/int(band.period)*int(int(band.span)/2))
		var delta := offset-int(band.offset); band.offset = offset
		if delta != 0 and int(band.limit) != 0 and int(band.cycles) >= int(band.limit): band.active = false
		elif delta != 0: operation.emit({"operation":"palette_rotate","args":[int(band.first),int(band.span),-delta if band.reverse else delta]})
	for id in m.motions:
		var motion: Dictionary = m.motions[id]
		if not (int(motion.flags)&2): continue
		var elapsed := _s32(now-int(motion.epoch)); var duration := int(motion.period)
		var point: Vector2i = motion.start
		if int(motion.flags)&0x300:
			var vector: Vector2i = motion.delta
			var cycles := int(elapsed/maxi(1,duration))
			if int(motion.limit) > 0 and cycles >= int(motion.limit):
				point += Vector2i(-vector.x*(int(motion.limit)%2) if int(motion.flags)&0x100 else vector.x,-vector.y*(int(motion.limit)%2) if int(motion.flags)&0x200 else vector.y)
				motion.flags = int(motion.flags)&~2
			else:
				var angle := int(_s32(elapsed*180)/maxi(1,duration))
				point.x += _cosine(int(vector.x/2),angle)-int(vector.x/2) if int(motion.flags)&0x100 else int(vector.x*float(elapsed)/maxi(1,duration))
				point.y += _cosine(int(vector.y/2),angle)-int(vector.y/2) if int(motion.flags)&0x200 else int(vector.y*float(elapsed)/maxi(1,duration))
		elif duration <= 0 or elapsed >= duration:
			if int(motion.flags)&4: motion.epoch = now
			else: point += Vector2i(motion.delta); motion.flags = int(motion.flags)&~2
		else:
			var f32 := PackedByteArray(); f32.resize(4); f32.encode_float(0,float(elapsed)/float(duration))
			var fraction := f32.decode_float(0)
			var vector: Vector2i = motion.delta
			point += Vector2i(int(vector.x*fraction),int(vector.y*fraction))
		_motion_apply(m,int(id),point,motion)
	for id in m.dithers:
		var d: Dictionary = m.dithers[id]
		if not d.active: continue
		var elapsed := now-int(d.epoch); var duration := int(d.duration)
		var index: int
		if duration <= 0 or elapsed >= duration: index = d.masks.size()-1; d.active = false
		else: index = clampi(int(float(elapsed)/duration*d.masks.size()),0,d.masks.size()-1)
		var layer := _layer(m,int(id)); layer.mask = int(d.masks[index]); layer.mask_rect = d.rect
	for id in m.queues:
		var q: Dictionary = m.queues[id]
		if not q.active or q.nodes.is_empty(): continue
		var changed := false
		if int(q.epoch) == 0: q.epoch = now; changed = true
		elif now >= int(q.epoch)+int(q.nodes[int(q.index)][7]):
			q.index = int(q.index)+1; q.epoch = now; changed = true
			if int(q.index) >= q.nodes.size():
				if int(q["repeat"]) == 0: q.index = 0
				else:
					q["repeat"] = int(q["repeat"])-1
					if int(q["repeat"]) <= 0: q.active = false; q.nodes.clear(); q.index = 0; changed = false
					else: q.index = 0
		if changed:
			var n: Array = q.nodes[int(q.index)]
			_crop(m,int(q.layer),int(n[0]),Vector2i(int(n[1]),int(n[2]))+Vector2i(q.offset),Rect2i(int(n[3]),int(n[4]),int(n[5]),int(n[6])))
	for id in m.apd_instances:
		var instance: Dictionary = m.apd_instances[id]
		if not m.apd_resources.has(int(instance.resource)) or str(instance.label) == "": continue
		var resource: Dictionary = m.apd_resources[int(instance.resource)]
		var identity := "%s:%s:%d:%d" % [str(resource.stem),str(instance.label),int(instance.epoch),int(instance.flags)]
		var cached: Dictionary = _players.get(id,{})
		if cached.get("identity","") != identity:
			var player = preload("res://scripts/render/ft2_apd_player.gd").new()
			player.play(data.load_apd(str(resource.stem)),str(instance.label),int(instance.epoch),int(instance.flags))
			cached = {"identity":identity,"player":player}; _players[id] = cached
		cached.player.advance(now)
	if not m.credits.is_empty() and m.credits.active:
		var credits: Dictionary = m.credits
		var elapsed := _s32(now-int(credits.epoch)); var duration := int(credits.duration)
		if duration <= 0 or elapsed >= duration: credits.y = 480-int(credits.total_height)-480; credits.active = false
		else: credits.y = 480+int(float(elapsed)/duration*(-480-int(credits.total_height)))
	for id in m.callbacks:
		var callback: Dictionary = m.callbacks[id]
		if _s32(int(callback.last)+20) > _s32(now): continue
		callback.last = now
		var family := int(callback.family)
		for particle in callback.particles:
			if family == 3:
				particle[1] = _s16(int(particle[1])+(int(particle[4])<<3)-106)
				if int(particle[1]) < 0: particle[1] = _s16(int(particle[1])+480)
			else:
				particle[3] = _s16(int(particle[3])+[50,20,-50][family])
				if family < 2 and int(particle[3]) > 400:
					particle[0] = _rng(m,1920)-960; particle[1] = _rng(m,1440)-720; particle[3] = _s16(int(particle[3])-300)
				elif family == 2 and int(particle[3]) < 100:
					particle[0] = _rng(m,1920)-960; particle[1] = _rng(m,1440)-1520; particle[3] = _s16(int(particle[3])+300)
	if battle != null: battle.rng = m.rng.duplicate()

func commands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _model.is_empty(): return out
	var order: Array = _model.order
	for id_value in order:
		var id := int(id_value)
		#42A380 dispatches registered APDs at layer9's place in draw order.
		if id == 9:
			if not _model.layers.has(id) or _model.layers[id].visible: out.append_array(_apd_commands())
			continue
		if not _model.layers.has(id): continue
		var layer: Dictionary = _model.layers[id]
		if not layer.visible: continue
		var pos: Vector2i = Vector2i(layer.dst)+Vector2i(layer.offset)
		if _model.callbacks.has(id):
			var children: Array[Dictionary] = []
			_draw_particles(children,_model.callbacks[id])
			if int(layer.mask) != 0 and int(layer.mask) != 65535 and layer.has("mask_rect"): pos = Rect2i(layer.mask_rect).position+Vector2i(layer.offset)
			#42A5E0 paints its callback into cached8C, then keyed/masked copies
			#that surface to MAIN. Its clear color must not erase lower layers.
			out.append({"op":"indexed_group","commands":children,"size":Vector2i(640,480),"source":layer.source if Rect2i(layer.source).has_area() else Rect2i(0,0,640,480),"pos":pos,"transparent":int(layer.key),"dither":int(layer.mask),"clip":_model.clip})
			continue
		if int(layer.fill) >= 0: out.append({"op":"rect","rect":Rect2i(pos,layer.source.size),"filled":true,"color":int(layer.fill)})
		elif _model.bitmaps.has(int(layer.bitmap)):
			var bitmap: Dictionary = _model.bitmaps[int(layer.bitmap)]
			#42A780 rewrites destinationRECT90 from mask geometry30..36;
			#the bitmap source cropBA..C0 and auxiliary offsets are retained.
			if int(layer.mask) != 0 and int(layer.mask) != 65535 and layer.has("mask_rect"):
				pos = Rect2i(layer.mask_rect).position+Vector2i(layer.offset)
			out.append({"op":"bitmap","key":"BMP/"+str(bitmap.stem)+".BMP","pos":pos,"source":layer.source,"transparent":int(layer.key),"dither":int(layer.mask),"raw_dither":true,"remaps":bitmap.remaps,"clip":_model.clip})
		if not _model.credits.is_empty() and int(_model.credits.layer) == id:
			for entry in _model.credits.entries:
				var command: Dictionary = entry.duplicate(true); command.pos = Vector2i(command.pos)+Vector2i(0,int(_model.credits.y)); out.append(command)
	return out

func _apd_commands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var records: Array = []
	for id in _model.apd_instances:
		if not _players.has(id): continue
		var instance: Dictionary = _model.apd_instances[id]
		var resource: Dictionary = _model.apd_resources[int(instance.resource)]
		var player = _players[id].player
		if player.frame >= 0: records.append({"instance":instance,"resource":resource,"player":player,"y":Vector2i(instance.pos).y+player.offset.y})
	#42EA20 shares the unstable priority/Y exchange ordering with tactical APDs.
	for i in range(records.size()-1):
		for j in range(i+1,records.size()):
			if int(records[j].instance.priority) < int(records[i].instance.priority) or (int(records[j].instance.priority)==int(records[i].instance.priority) and int(records[j].y)<int(records[i].y)):
				var old=records[i];records[i]=records[j];records[j]=old
	for record in records:
		var instance: Dictionary = record.instance; var resource: Dictionary = record.resource; var player=record.player
		#429C40/429EC0 own BASE-palette writes; drawing does not realize it.
		out.append({"op":"apd","stem":str(resource.stem),"label":str(instance.label),"frame":int(player.frame),"pos":Vector2i(instance.pos)+player.offset,"mirror":player.mirror,"flip_y":player.flip_y,"remaps":[[10,int(resource.palette_count),int(resource.palette_start)]] if int(resource.palette_count) != 0 else [],"palette_install":[]})
	return out

func _start_credits(m: Dictionary, layer: int, duration: int) -> void:
	_layer(m,layer)
	var source: Dictionary = data.read_json("data/port_ready/scripts/credits/DATA/STAFF.json")
	var entries: Array = []
	var y := 0
	var last_spacing := 0
	for entry in source.render_entries:
		var style: Dictionary = entry.style
		var text := str(entry.render_text_cp949)
		var size := int(style.fontsize)
		var font := {"family":"바탕","height":size,"weight":700 if int(style.fontflags)&4 else 400,"italic":(int(style.fontflags)&8) != 0}
		var measured: Dictionary = measure_text.call(text,font) if measure_text.is_valid() else {"width":0,"height":size}
		last_spacing = int(style.linespace)
		if text == " ": y += int(style.spacesize)+last_spacing; continue
		var x := int(style.posx)
		if int(style.center) != 0: x = int((640-mini(640,int(measured.width)+33))/2)
		entries.append({"op":"text","text":text.replace("_"," ").replace("*",","),"raw_text":text,"pos":Vector2i(x,y),"font":font,"color":int(style.fontcolor),"decor":{"enabled":(int(style.fontflags)&32) != 0,"color":int(style.decocolor),"mode8":true}})
		y += mini(480,int(measured.height)+3)+last_spacing
	m.credits = {"layer":layer,"duration":duration,"epoch":0,"active":false,"y":480,"total_height":y-last_spacing,"entries":entries}

func _draw_particles(out: Array[Dictionary],callback: Dictionary) -> void:
	out.append({"op":"rect","rect":Rect2i(0,0,640,480),"color":252,"filled":true})
	var family := int(callback.family)
	var center: Vector2i = [Vector2i(300,300),Vector2i(10,400),Vector2i(320,800),Vector2i.ZERO][family]
	for particle in callback.particles:
		var point := Vector2i(int(particle[0]),int(particle[1])); var source_x := int(particle[4])*16
		if family < 3:
			var z := int(particle[3]); var divisor := z+50
			if divisor == 0: continue
			source_x = 16*(7-mini(7,int((z-100)/25)))
			point = center+Vector2i(int(100*int(particle[0])/divisor),int(100*int(particle[1])/divisor))
			if point.x < 0 or point.y < 0 or point.x > 640 or (family < 2 and point.y > 480): particle[3] = 400
		out.append({"op":"bitmap","key":str(callback.bitmap),"pos":point,"source":Rect2i(source_x,0,16,16),"transparent":252,"remaps":callback.remaps})

func _rng(m: Dictionary,modulus: int) -> int:
	var step: Dictionary = preload("res://scripts/logic/ft2_rules.gd").rng_step(m.rng,modulus)
	m.rng = step.seeds
	return int(step.value)

func _cosine(radius: int, angle: int) -> int:
	var a := posmod(_s32(angle)+90,360)-90
	if a == 0: return _s32(radius)
	if a == 180: return _s32(-radius)
	if a <= 90: return _s32(int(_trig[90-absi(a)])*_s32(radius))>>16
	return _s32(-(_s32(int(_trig[90-absi(a-180)])*_s32(radius))>>16))

func _s16(value: int) -> int:
	return ((value+32768)&65535)-32768

func _crop(m: Dictionary, layer_id: int, bitmap: int, pos: Vector2i, source: Rect2i) -> void:
	if not m.bitmaps.has(bitmap): return
	var l := _layer(m,layer_id)
	var size: Vector2i = _sizes.get(str(m.bitmaps[bitmap].stem),Vector2i.ZERO)
	var src := source.intersection(Rect2i(Vector2i.ZERO,size))
	var dst := Rect2i(pos+src.position-source.position,src.size)
	var clipped := dst.intersection(Rect2i(0,0,640,480))
	l.bitmap = bitmap; l.fill = -1; l.dst = clipped.position
	l.source = Rect2i(src.position+clipped.position-dst.position,clipped.size)

func _motion_apply(m: Dictionary, layer_id: int, current: Vector2i, motion: Dictionary) -> void:
	var ref := int(motion.ref); var flags := int(motion.flags)
	var point := Vector2i(_s16(current.x),_s16(current.y))
	var l := _layer(m,layer_id)
	if ref == -1: l.offset = point; return
	if flags&16:
		if m.queues.has(ref): m.queues[ref].offset = point
		return
	if not m.bitmaps.has(ref): return
	var size: Vector2i = _sizes.get(str(m.bitmaps[ref].stem),Vector2i.ZERO)
	var source := point
	if flags&32: l.offset.x = point.x; source.x = 0
	if flags&64: l.offset.y = point.y; source.y = 0
	if not flags&8:
		_crop(m,layer_id,ref,Vector2i.ZERO,Rect2i(source,size)); return
	for axis in 2:
		if point[axis] > size[axis]: point[axis] = _s16(point[axis]-size[axis])
		if point[axis] < 0: point[axis] = _s16(point[axis]+size[axis])
	var width := mini(size.x,size.x-point.x); var height := mini(size.y,size.y-point.y)
	_crop(m,layer_id,ref,Vector2i.ZERO,Rect2i(point,Vector2i(width,height)))
	if width < 640: _crop(m,layer_id,ref,Vector2i(width,0),Rect2i(0,point.y,640-width,height))
	if height < 480: _crop(m,layer_id,ref,Vector2i(0,height),Rect2i(point.x,0,width,480-height))
	if width < 640 and height < 480: _crop(m,layer_id,ref,Vector2i(width,height),Rect2i(0,0,640-width,480-height))

func _s32(value: int) -> int:
	return ((value+0x80000000)&0xFFFFFFFF)-0x80000000
