class_name FT2VM
extends RefCounted
## Original FF-prefixed EVENT interpreter. PC and its single return slot are byte offsets.
signal map_requested(map_id: int)
signal placement_loaded(placement_id:int)
signal source_commands_requested(commands:Array)
signal input_wait_requested(operation:String,request:Dictionary)
signal music_requested(index: int)
signal music_fade_requested(timer_parameter:int,direction:int)
signal main_service_requested(now_ms:int)
signal actor_restore_requested(slot:int)
signal complete_flag_requested(value:int)
signal sound_requested(stem: String, loop: bool)
signal sound_stop_requested(stem: String)
signal finished
signal camera_requested(request: Dictionary)
signal palette_requested(request: Dictionary)
signal actor_changed(state: Dictionary)
signal ui_requested(request: Dictionary)
signal scene_requested(selector: int)
signal save_requested(index: int)

var data
var battle
var busy := false
var mode := 1
var previous_mode := 1
var current_event := 0:
	set(value):
		current_event=value
		if battle!=null:battle.event_id=value #One source449214 global, separate from loaded_event script bytes.
var loaded_event := -1
var variables: Array[int] = []
var equal_flag := false
var greater_flag := false
var current_day := 0
var control_mode := 1
var stage_title := ""
var objective := ""
var custom_speaker := ""
var pc := 0
var return_pc := 0
var now_ms := 0
var deadline := -1
var input_wait := false
var modal_wait := false
var fade_deadline := 0
var palette_busy_query: Callable
var camera_busy := false
var music_busy := false
var music_busy_query:Callable
var music_fade_direction:=1
var control_held := false
var active_window := true
var actor_busy: Dictionary = {}
var actor_busy_query:Callable
var actor_player_query:Callable
var actor_sprites: Dictionary = {}
var actor_cache_generation:=0
var actor_cache_mode:=1
var actor_npc_cache_generation:=0
var dialogue: Array[Dictionary] = []
var bitmap := ""
var alternate_surface:=false #Source462610 suppresses410B20/408A50.
var _surface_fill_index:=-1
var speaker := 0
var speaker_variant := "a"
var dialogue_top := false
var dialogue_y := 0
var text_size := 16
var text_color := 30
var text_style := 0
var portrait_width_units := 35
var dialogue_halves: Dictionary = {}
var raw_globals: Dictionary = {}
var measure_text: Callable
var town
var scene
var jobs
var trace: Array[Dictionary] = []
var errors: Array[String] = []
var _raw := PackedByteArray()
var _labels: Dictionary = {}
var _strings: Dictionary = {}
var _main_signatures: Dictionary = {}
var _system_signatures: Dictionary = {}
var _script: Dictionary = {}
var _hook: Dictionary = {}
var _complete_stage := false
var _clock_start := 0
var _last_command := 0
var _speaker_names: Dictionary = {}
var _last_string_raw := PackedByteArray()
var _title_commands: Array[Dictionary] = []
var _speaker_latches := [0,0]
var _bitmap_sizes: Dictionary = {}
var _last_resource_stem := ""
var _last_script_resource_palette: Dictionary = {}
var _script_resource_serial := 0
var context_actor := -1
var other_actor := -1
var _modal_followups: Array[Dictionary] = []
var _modal_surface_commands:Array[Dictionary]=[]
var _choice_modal := false
var overview_visibility: Callable
var unit_window_visibility:Callable
var _unit_window_saved:=0
var _overview_saved := 0
var _scene_growth := false
var _scene_growth_cursor := 0
var _scene_growth_notices: Array[String] = []

func _init(store = null, combat = null) -> void:
	data = store
	battle = combat
	variables.resize(100)
	variables.fill(0)
	if data == null:
		return
	for row in data.read_json("data/port_ready/scripts/spec/main_dispatch.json").entries:
		_main_signatures[int(row.opcode)] = str(row.signature)
	for row in data.read_json("data/port_ready/scripts/spec/system_dispatch.json").entries:
		_system_signatures[int(row.system_id)] = str(row.signature)
	for row in data.read_json("data/port_ready/scripts/spec/runtime_bindings.json").speaker_name_table:
		_speaker_names[int(row.speaker_id)] = str(row.get("text", ""))
	for row in data.read_json("data/port_ready/assets/bitmaps/index.json").files:
		_bitmap_sizes[str(row.source).to_upper()] = Vector2i(int(row.size[0]),int(row.size[1]))
	town = preload("res://scripts/scenario/ft2_town.gd").new(self, data)
	scene = preload("res://scripts/scenario/ft2_scene.gd").new(data,battle)
	scene.operation.connect(_scene_operation)
	jobs = preload("res://scripts/scenario/ft2_actor_jobs.gd").new(data)
	jobs.cell_committed.connect(_job_cell)
	jobs.finished.connect(actor_finished)
	jobs.changed.connect(_emit_actor_state)
	jobs.sound_requested.connect(_job_sound)
	if battle != null and battle.has_signal("hook_requested"):
		battle.hook_requested.connect(_on_hook)

func start(event_id: int, label: String = "begin") -> bool:
	# The loader refuses to replace a live script. Chain-event explicitly frees it first.
	if busy:
		return false
	var path := "data/port_ready/scripts/normalized/DATA/EVENT%02d.json" % event_id
	if not FT2Content.exists(data.resolve(path)):
		return false
	var parsed: Dictionary = data.read_json(path)
	var labels := {}
	for row in parsed.header.labels:
		labels[str(row.name).to_lower()] = int(row.target_file_offset)
	if not labels.has(label.to_lower()):
		return false
	_script = parsed
	alternate_surface=false;_surface_fill_index=-1 #43D0AF successful loader resets462610.
	_labels = labels
	_strings.clear()
	for command in parsed.commands:
		for operand in command.get("operands", []):
			if operand.get("kind", "") == "nul_string":
				_strings[int(operand.offset)] = str(operand.text)
	_raw = Marshalls.base64_to_raw(parsed.source_raw_base64)
	pc = int(_labels[label.to_lower()])
	loaded_event = event_id
	previous_mode = mode
	mode = 4
	busy = true
	deadline = -1
	input_wait_requested.emit("end",{"timer_id":400,"reason":"loader_reset","input_wait_preserved":false,"source_mode":mode,"event":loaded_event}) #43D0CE always requests system32641, even with an already-clear wait latch.
	input_wait = false
	modal_wait = false
	return_pc = 0
	dialogue.clear()
	dialogue_y = 0
	dialogue_halves.clear()
	_speaker_latches = [0,0]
	camera_busy = false
	_unit_window_saved=int(unit_window_visibility.call(false)) if unit_window_visibility.is_valid() else 0 #43D0DC→462620.
	if overview_visibility.is_valid(): _overview_saved = int(overview_visibility.call(false))
	_source_commands([{"op":"clear_rect","surface":"backdrop","rect":Rect2i(0,0,640,480),"color":0}]) #43D0FF after successful EVENT load.
	if actor_cache_mode<0:_emit_actor_state() #After Town-hide release-only, sync mode4 before the next native pose caller.
	return true

func start_campaign() -> bool:
	return start(0, "begin")

func bootstrap_campaign() -> bool:
	# 41E835..41E8B8: the first actors are later constructed by EVENT00 placement1.
	busy = false; mode = 1; previous_mode = 1
	for slot in battle.units.size():
		var empty := PackedByteArray(); empty.resize(124); empty.fill(0); battle.units[slot] = empty
	battle.money = 200; battle.round_index = -1; battle.map_id = -1; battle.map_data = {}; battle.source_index = -1
	town.enabled.fill(0); town.markers.fill(0); town.mode2 = 0; town.mode3 = 0; town.extra_overlay = 0; town.display_markers = 0; town.hide()
	actor_sprites.clear(); actor_busy.clear(); dialogue_halves.clear(); _hook.clear()
	map_requested.emit(-1)
	_changed()
	return start_campaign()

func restore_state(header: Dictionary, tail: PackedByteArray = PackedByteArray(), header_raw: PackedByteArray = PackedByteArray()) -> void:
	busy = false
	current_event = int(header.get("stage", header.get("event_number", header.get("event", 0))))
	stage_title = str(header.get("title", ""))
	objective = str(header.get("mission_caption", ""))
	if data.has_method("decode_cp949"):
		stage_title = data.decode_cp949(str(header.get("title_cp949_raw_hex","")).hex_decode().slice(0,32))
		objective = data.decode_cp949(str(header.get("battle_objective_cp949_raw_hex","")).hex_decode())
	var source_vars: Array = header.get("event_variables_independent",header.get("event_variables", header.get("variables", [])))
	for i in mini(100, source_vars.size()):
		variables[i] = _s16(int(source_vars[i]))
	if header_raw.size() >= 240:
		for i in 100: variables[i] = header_raw.decode_s16(40+i*2)
	if tail.size() >= 180:
		town.restore(tail)
	control_mode = town.get_control_mode(0)

func snapshot_state() -> Dictionary:
	return {"current_event":current_event,"current_day":current_day,"loaded_event":loaded_event,
		"variables":variables.duplicate(),"stage_title":stage_title,"objective":objective,
		"control_mode":control_mode,"town_tail":town.snapshot(),"mode":mode,"pc":pc}

func _on_hook(request: Dictionary) -> void:
	if busy:
		if request.get("kind","") == "pickup":return #43CFB0 rejects a second load quietly after the grant.
		errors.append("Battle hook requested while another script is active")
		return
	_hook = request.duplicate(true)
	if not bool(request.get("inherit_context",request.get("kind","") != "after")):
		context_actor = int(request.get("context_slot",request.get("target_slot",-1)))
		other_actor = int(request.get("other_slot",request.get("source_slot",-1)))
		battle.set("context_slot",context_actor); battle.set("other_slot",other_actor)
	else:
		if battle.get("context_slot") != null: context_actor = int(battle.get("context_slot"))
		if battle.get("other_slot") != null: other_actor = int(battle.get("other_slot"))
	if not start(int(request.get("event_id", current_event)), str(request.label)):
		_hook.clear()
		battle.resume_hook(false)
	else:battle.hook_started()

func _number() -> int:
	if pc >= _raw.size():
		return 0
	var value: int = _raw[pc]
	pc += 1
	if value == 128:
		if pc + 4 > _raw.size():
			return 0
		value = _raw.decode_s32(pc)
		pc += 4
		return value
	return value - 256 if value >= 128 else value

func _string() -> String:
	var begin := pc
	while pc < _raw.size() and _raw[pc] != 0:
		pc += 1
	_last_string_raw = _raw.slice(begin, pc)
	pc = mini(pc + 1, _raw.size())
	if _strings.has(begin):
		return str(_strings[begin])
	if data.has_method("decode_cp949"):
		return data.decode_cp949(_last_string_raw)
	return _last_string_raw.get_string_from_ascii()

func _actor(reference: int) -> int:
	if reference == 24:
		return context_actor
	if battle == null or reference == 0:
		return -1
	for slot in battle.units.size():
		var bytes: PackedByteArray = battle.units[slot]
		if bytes.decode_u16(0) != 0 and bytes.decode_u16(0) == reference:
			return slot
	return -1

func _read_operands(signature: String) -> Dictionary:
	var values: Array = []
	var actors: Array[int] = []
	for kind in signature:
		match kind:
			"N": values.append(_number())
			"A":
				var reference := _number()
				var slot := _actor(reference)
				values.append(slot)
				actors.append(slot)
				# Original handler resumes fetch WITHOUT consuming later operands.
				if slot < 0:
					return {"values":values,"valid":false,"actors":actors}
			"S": values.append(_string())
			"V":
				values.append(_raw[pc] if pc < _raw.size() else 97)
				pc += 2
			"L":
				var items: Array[int] = []
				var item := _number()
				while item > 0 and pc < _raw.size():
					items.append(item)
					item = _number()
				values.append(items)
	return {"values":values,"valid":true,"actors":actors}

func advance(ms: int) -> void:
	var entry_mode := mode
	_advance_event(ms)
	if jobs != null and entry_mode == 4 and busy and mode == 4 and not modal_wait and not alternate_surface:
		jobs.advance(now_ms)
		_emit_actor_state()

func _advance_event(ms: int) -> void:
	now_ms = (now_ms + maxi(0, ms)) & 0xFFFFFFFF
	if mode in [4,9]:main_service_requested.emit(now_ms) #43D210/442DBF precede waits and the Town50ms gate.
	if mode == 9:
		town.advance(now_ms)
		return
	if mode == 8:
		scene.measure_text = measure_text
		scene.advance(ms)
		if not scene.busy:
			mode = 4
		return # Original outer loop never fetches EVENT on the same scene-completion frame.
	if not busy or modal_wait:
		return
	if input_wait and control_held and active_window:
		_end_input_wait("control_input")
	var expired_deadline := false
	if deadline >= 0:
		if now_ms < deadline and not control_held:
			return
		expired_deadline = true
		if input_wait:input_wait_requested.emit("end",{"timer_id":400,"reason":"deadline","input_wait_preserved":true,"source_mode":mode,"event":loaded_event}) #43D379..398 stops cursor timer, but not462158.
		deadline = -1
	if input_wait and not expired_deadline:
		return
	var budget := 4096
	while busy and mode == 4 and (not input_wait or expired_deadline) and not modal_wait and budget > 0:
		budget -= 1
		if pc >= _raw.size():
			_finish(-1)
			break
		_last_command = pc
		if _raw[pc] != 255:
			pc += 1
			mode = previous_mode
			break
		pc += 1
		if pc >= _raw.size():
			_finish(-1)
			break
		var opcode: int = _raw[pc]
		pc += 1
		if opcode > 63:
			_finish(opcode)
			break
		var operands: Dictionary
		var selector := 0
		if opcode == 0:
			selector = _number()
			operands = _read_operands(str(_system_signatures.get(selector, "")))
		elif opcode == 33:
			var reference := _number()
			var actor := _actor(reference)
			if actor < 0:
				_create_actor([reference,0,0],false)
				actor = _actor(reference)
			operands = {"values":[actor],"valid":actor >= 0}
		elif opcode == 4 or opcode == 5:
			var who := _number()
			var variant := 97
			if who != 0:
				variant = _raw[pc]
				pc += 2
			operands = {"values":[who, variant],"valid":true}
		else:
			operands = _read_operands(str(_main_signatures.get(opcode, "")))
		trace.append({"event":loaded_event,"offset":_last_command,"opcode":opcode,"system":selector,"values":operands.values.duplicate(true),"time":now_ms})
		if trace.size() > 2048:
			trace.pop_front()
		if not operands.valid:
			continue
		var yielded: bool = _system(selector, operands.values) if opcode == 0 else _execute(opcode, operands.values)
		if yielded:
			break
	if budget == 0:
		errors.append("EVENT instruction budget exhausted at %d:%d" % [loaded_event, pc])

func _jump(label: String) -> bool:
	if not _labels.has(label.to_lower()):
		return false
	pc = int(_labels[label.to_lower()])
	return true

func _wait_again() -> bool:
	pc = _last_command
	return true

func _execute(op: int, a: Array) -> bool:
	match op:
		1:
			deadline = (now_ms + int(a[0])) & 0xFFFFFFFF
			return true
		2,3:
			fade_deadline = now_ms + maxi(0, int(a[0])) * 128
			palette_requested.emit({"kind":"restore" if op == 2 else "black","interval":int(a[0]),"start":10,"count":236})
			return op == 2
		4,5:
			speaker = int(a[0]); speaker_variant = String.chr(int(a[1])); dialogue_top = op == 4
			dialogue.clear(); dialogue_y = 0
			var half := int(dialogue_top)
			dialogue_halves[half] = {"speaker":speaker,"variant":speaker_variant,"commands":dialogue,"window":false,"portrait":false}
			_source_commands([{"op":"clear_rect","surface":"backdrop","rect":Rect2i(0,0 if dialogue_top else 240,640,240),"color":0}])
			portrait_width_units = 35 if dialogue_top else 34
			if speaker == 0:
				dialogue_y = 80 if dialogue_top else 344; _speaker_latches[half] = 0
			else:
				if int(_speaker_latches[half]) != 0 and int(_speaker_latches[half]) != speaker:
					_speaker_latches[half] = 0; pc = _last_command; return true
				_speaker_latches[half] = 0
				dialogue_halves[half].window = true
				var face := "BMP/FACE%02d%s.BMP" % [speaker,speaker_variant.to_upper()]
				var present: bool = int(a[1]) >= 97 and (dialogue_top or speaker < 30) and _bitmap_sizes.has(face)
				if present:
					portrait_width_units = 20; _speaker_latches[half] = speaker; dialogue_halves[half].portrait = true
			_source_commands([{"op":"paint_backdrop","commands":_dialogue_half_commands(half,false,false)}])
		6: _add_dialogue(str(a[0]))
		7:
			_last_resource_stem = "CHAR_%02d%s" % [_read(int(a[0]),2),String.chr(int(a[1])).to_upper()]
			# OP07 falls through the OP33 empty-Unit70 replacement at 43DAC2.
			_sprite(int(a[0]), {"variant":String.chr(int(a[1])),"stem":_last_resource_stem,"label":"","reset_body":true,"shadow_visible":false})
		8:
			var label := str(a[1])
			_sprite(int(a[0]), {"label":label.trim_prefix("*"),"flags":1 | (16 if int(a[2]) != 0 else 0) | (2 if label.begins_with("*") else 0),"loop":label.begins_with("*"),"play":true,"body_visible":true,"shadow_visible":true})
			actor_busy[int(a[0])] = true
		9:
			#417F40 tests the shared palette state, including scene/portrait
			#requests and immediate requests that stop an earlier global fade.
			var palette_busy := bool(palette_busy_query.call()) if palette_busy_query.is_valid() else now_ms < fade_deadline
			if palette_busy: return _wait_again()
		10:
			map_requested.emit(int(a[0]))
		11:
			if data.has_method("load_placement"):
				actor_npc_cache_generation+=1 #41AA31 clears definition10..73 resource cache only.
				battle.units = data.load_placement(int(a[0]),battle)
				placement_loaded.emit(int(a[0]))
			actor_sprites.clear()
			_emit_actor_state();_changed()
		12: camera_requested.emit({"kind":"cell","cell":Vector2i(int(a[0]), int(a[1]))})
		13: camera_requested.emit({"kind":"actor","slot":int(a[0])})
		14:
			music_requested.emit(int(a[0]));music_fade_requested.emit(0,1)
		15:
			music_fade_direction=int(a[1]);music_fade_requested.emit(int(a[0]),int(a[1]))
		16:
			var stem := str(a[0]); sound_requested.emit(stem.trim_prefix("*"), stem.begins_with("*"))
		17,63:
			var slot:=int(a[0])
			if jobs.is_busy(slot) or (bool(actor_busy_query.call(slot,op==17)) if actor_busy_query.is_valid() else bool(actor_busy.get(slot,false))):return _wait_again()
			if _read(slot,2)==7:
				var kept:Dictionary=actor_sprites.get(slot,{}).duplicate(true)
				if actor_player_query.is_valid():kept["player_override"]=actor_player_query.call(slot)
				kept["world"]=_cell(slot);kept["externally_advanced"]=false
				actor_sprites[slot]=kept #419060 leaves definition7 Unit70 resource and last frame untouched.
			else:actor_sprites.erase(slot)
			jobs.clear(slot);actor_busy.erase(slot);_emit_actor_state();actor_restore_requested.emit(slot)
		18:
			camera_busy = int(a[4]) > 0
			camera_requested.emit({"kind":"motion","dx":int(a[0]),"dy":int(a[1]),"target":Vector2i(int(a[2]),int(a[3])),"interval":int(a[4])})
		19,20: _create_actor(a, op == 19)
		21: _remove_actor(int(a[0]))
		22: battle.grant_item(0, int(a[0]), int(a[1]))
		23:
			if battle.has_method("consume_item"): battle.consume_item(int(a[0]), int(a[1]))
		24:
			input_wait = true
			if int(a[0]) > 0: deadline = (now_ms + int(a[0])) & 0xFFFFFFFF
			input_wait_requested.emit("begin",{"timer_id":400,"interval_ms":600,"deadline":deadline,"source_mode":mode,"event":loaded_event})
			return true
		25:
			var slot := int(a[0]); var stem := _actor_stem(slot)
			# 43E0E8..43E125 stores each parsed direction before starting the job.
			# Unit+06 therefore already holds the final path direction during movement.
			var directions := FT2ActorJobs.directions(str(a[2]))
			if not directions.is_empty(): _write(slot,6,directions.back())
			actor_busy[slot] = jobs.play_path(slot,stem,_cell(slot),str(a[2]),str(a[1]),now_ms,_job_metadata(slot))
		26: pass
		27:
			if bool(music_busy_query.call()) if music_busy_query.is_valid() else music_busy:return _wait_again()
			if music_fade_direction==0:music_requested.emit(-1);music_fade_requested.emit(0,1)
		28: _write(int(a[0]), 8, int(a[1]), 4); _write(int(a[0]), 12, int(a[2]), 4)
		29: _restore_units(true); _battle_reset()
		30:
			_complete_stage = true
			variables.fill(0)
			for slot in range(10, mini(50, battle.units.size())): _remove_actor(slot)
		31:
			if int(a[1]) != 4: _write(int(a[0]), 6, int(a[1]))
		32: _jump(str(a[0]))
		33: _sprite(int(a[0]), {"reset_body":true,"label":"","shadow_visible":false})
		34:
			if camera_busy: return _wait_again()
			return true
		35:
			jobs.clear();actor_busy.clear();actor_sprites.clear();actor_cache_generation+=1;actor_cache_mode=4
			for slot in battle.units.size():
				if _read(slot,0)!=0:
					_write(slot,92,1,4);_write(slot,96,1,4)
			_emit_actor_state()
			for slot in battle.units.size():
				if _read(slot,0)!=0:actor_restore_requested.emit(slot)
		36: _finish(36); return true
		37:
			var p := _cell(int(a[0])); var q := _cell(int(a[1]))
			_write(int(a[1]), 6, _facing(p - q))
		38: _sprite(int(a[0]), {"pos":Vector2i(int(a[1]),int(a[2]))})
		39:
			if (int(a[0]) != 0) == equal_flag: _jump(str(a[1]))
		40:
			if (int(a[0]) != 0) == greater_flag: _jump(str(a[1]))
		41: _set_var(int(a[0]), int(a[1]))
		42: _set_var(int(a[0]), _var(int(a[0])) + int(a[1]))
		43: _set_var(int(a[0]), _var(int(a[0])) - int(a[1]))
		44:
			equal_flag = int(a[1]) == _var(int(a[0])); greater_flag = int(a[1]) > _var(int(a[0]))
		45: variables.fill(0)
		46: return_pc = pc; _jump(str(a[0]))
		47: pc = return_pc; return_pc = 0
		48:
			previous_mode = 1;actor_sprites.clear();actor_busy.clear();actor_cache_generation+=1;actor_cache_mode=1;_emit_actor_state()
			_unit_window_saved=1 #43E69E explicitly requests helper restore at later cleanup.
			_changed()
		49:
			modal_wait = true; ui_requested.emit({"kind":"shop","items":a[0]}); return true
		50:
			var key:="BMP/" + str(a[0]).to_upper() + ".BMP"
			if not _bitmap_sizes.has(key):return false #43E70D failure logs and resumes, without switching context.
			palette_requested.emit({"kind":"save_script_base"})
			bitmap=key
			_source_commands([{"op":"clear_rect","surface":"main","rect":Rect2i(0,0,640,480),"color":0},{"op":"paint_main","commands":[{"op":"bitmap","key":bitmap,"pos":Vector2i.ZERO,"centered":true,"transparent":-1,"remaps":[[10,208,32]]}]},{"op":"present","mode":"main"}])
			fade_deadline = now_ms+(int(a[1])&0xFFFF)*128 # Fallback for an unwired standalone VM.
			palette_requested.emit({"kind":"bitmap","key":bitmap,"interval":int(a[1]),"remaps":[[10,208,32]],"base_start":32,"base_count":208})
			alternate_surface=true;_surface_fill_index=-1
		51:
			palette_requested.emit({"kind":"restore_script_base"})
			_source_commands([{"op":"actor_visibility_all","enabled":true},{"op":"restore","targets":["main","backdrop"]}])
			alternate_surface=false;_surface_fill_index=-1;bitmap = ""; dialogue.clear(); dialogue_halves.clear(); _title_commands.clear()
		52:
			palette_requested.emit({"kind":"save_script_base"})
			_source_commands([{"op":"actor_visibility_all","enabled":false}])
			alternate_surface=true;mode = 8; scene.start(int(a[0])); scene_requested.emit(int(a[0])); return true
		53: _battle_reset()
		54:
			_finish(54); mode = 9; battle.round_index = -1; map_requested.emit(-1)
			if current_event>0:actor_cache_generation+=1;actor_cache_mode=9;_emit_actor_state() #44238F show Town, not each50ms repaint.
			town.enter(); return true
		55: _set_var(int(a[0]), _var(int(a[0])) | ((1 << (int(a[1]) & 31)) & 65535))
		56: _set_var(int(a[0]), _var(int(a[0])) & ~((1 << (int(a[1]) & 31)) & 65535))
		57: _set_var(int(a[0]), _var(int(a[0])) ^ ((1 << (int(a[1]) & 31)) & 65535))
		58: equal_flag = (_var(int(a[0])) & (1 << (int(a[1]) & 31))) != 0
		59:
			stage_title = str(a[0])
			if int(a[1]) != 0:
				_show_stage_title()
		60:
			var event_id := int(a[0]); var label := str(a[1]); busy = false; start(event_id,label)
		61: custom_speaker = str(a[0])
		62:
			objective = str(a[0]); modal_wait = true; ui_requested.emit({"kind":"message","text":objective}); return true
	_changed()
	return false

func _system(op: int, a: Array) -> bool:
	var slot := int(a[0]) if not a.is_empty() and a[0] is int else -1
	match op:
		1:
			for i in range(10,mini(50,battle.units.size())):
				if _read(i,18) == 1: _remove_actor(i)
		2: _sprite(slot,{"shadow_visible":int(a[1]) != 0})
		3: _write(slot,92,int(a[1]),4); _write(slot,96,int(a[1]),4)
		4: town.set_flag(int(a[0]),int(a[1]))
		5:
			for i in mini(10,battle.units.size()): _sprite(i,{"visible":i == slot})
		6: current_event = _var(int(a[0])); current_day = current_event
		7,22,24,25,29,30,38,45,49:
			var interval := int(a[0]) if not a.is_empty() else 0
			fade_deadline = now_ms + maxi(0,interval)*128
			match op:
				7: palette_requested.emit({"kind":"brightness","start":32,"count":176,"percent":60,"interval":interval})
				22: palette_requested.emit({"kind":"white","start":10,"count":236,"interval":interval})
				24:
					_source_surface_fill(16);palette_requested.emit({"kind":"restore","start":16,"count":16,"interval":interval})
				29: palette_requested.emit({"kind":"brightness","start":208,"count":32,"percent":int(a[1]),"interval":interval})
				30:
					_source_surface_fill(0);palette_requested.emit({"kind":"restore","start":144,"count":64,"interval":interval})
				38: palette_requested.emit({"kind":"brightness","start":32,"count":112,"percent":0,"interval":interval})
				25,45,49: palette_requested.emit({"kind":"tint","transform":{25:"warm",45:"cool",49:"night"}[op],"start":16,"count":224,"interval":interval,"tint_start":32,"tint_count":176})
		8:
			_choice_modal = true
			_show_modal({"kind":"choice","text":str(a[0]),"resource":163 if str(a[0]).begins_with("+") else 126}); return true
		9:
			if int(a[0]) != 0: battle.add_money(int(a[0]))
			var distribution := {"kind":"experience","amount":int(a[0]),"pool":int(a[1])}
			if int(a[0]) != 0:
				sound_requested.emit("myturn",false)
				_modal_followups.append(distribution)
				_show_modal({"kind":"message","text":"%dGold의 보수를 받다" % int(a[0])})
			else: _show_modal(distribution)
			return true
		10: control_mode = town.get_control_mode(int(a[0]))
		11: _sprite(slot,{"overlay":true})
		12:
			for i in range(10,mini(50,battle.units.size())):
				var kind := _read(i,0)
				if (kind == 8 or kind == 24 or kind > 30) and (_read(i,38) == 0 or _read(i,16) != 1): _remove_actor(i)
		13,14: _sprite(slot,{"dither_interval":int(a[1]),"dither_target":8 if op == 13 else 0})
		15:
			if _read(slot,16) == 9 and _read(slot,18) != 1 and int(a[1]) != 0: _write(slot,16,0)
			_sprite(slot,{"visible":int(a[1]) != 0})
		16:
			for i in mini(10,battle.units.size()):
				if i != slot and _read(i,0) != 0: _write(i,6,_facing(_cell(slot)-_cell(i)))
		17: _write(slot,0,8); _write(slot,38,0); _write(slot,16,1)
		18:
			for i in battle.units.size():
				if _read(i,16) == 9 and int(a[0]) != 0: _write(i,16,0)
				_sprite(i,{"visible":int(a[0]) != 0})
		19:
			_modal_surface_commands.assign([{"op":"clear_rect","surface":"main","rect":Rect2i(0,0,640,480),"color":0},{"op":"present","mode":"main"}])
			_show_modal({"kind":"message","text":FT2Content.ui_text("exit_notice","게임을 닫습니다.")}); return true
		20: current_event = 0; palette_requested.emit({"kind":"reset_ranges"})
		21: _source_surface_fill(0)
		23: raw_globals["44923C"] = int(a[0])
		26: actor_busy[slot] = jobs.play_single(slot,_actor_stem(slot),_cell(slot),str(a[1]),now_ms,_job_metadata(slot),_read(slot,6))
		27: _clock_start = now_ms
		28:
			if ((now_ms - _clock_start) & 0xFFFFFFFF) < 1000 * int(a[0]): return _wait_again()
		31: _sprite(slot,{"screen_offset":Vector2i(0,-32)})
		32: equal_flag = int(battle.substate) == 7 # Original402610 is exactly unsigned(substate-7)<1.
		33: _sprite(slot,{"priority":5 if int(a[1]) != 0 else 1})
		34: town.extra_overlay = int(a[0])
		35:
			equal_flag = false
			for kind in [1,2]:
				var found := _actor(kind)
				if found >= 0 and not _read(found,16) in [1,3,4,5,8,9]: equal_flag = true
		36: _write(slot,16,8)
		37:
			equal_flag = battle.grant_item(slot,int(a[1]),1)
			var items: Array = data.load_table("item")
			var item_name := str(items[int(a[1])].name) if int(a[1]) >= 0 and int(a[1]) < items.size() else ""
			_show_modal({"kind":"message","text":FT2Content.ui_text("item_received","%s: %s 획득") % [unit_name(slot),item_name] if equal_flag else FT2Content.ui_text("item_unavailable","%s: 아이템을 사용할 수 없습니다.") % unit_name(slot)})
			return true
		39:
			for i in battle.units.size(): _sprite(i,{"shadow_visible":false})
		40: _restore_units(true)
		41: _morph_context()
		42:
			_write(context_actor,2,64)
		43: _write(slot,38,0); _write(slot,42,0); _write(slot,16,1)
		44:
			battle.add_money(int(a[0])); sound_requested.emit("myturn",false)
			_show_modal({"kind":"message","text":"%dGold(을)를 손에 넣었다" % int(a[0])}); return true
		46:
			equal_flag = slot == other_actor
			if not equal_flag:
				_write(context_actor,38,1); _write(context_actor,16,0)
		47: equal_flag = _read(slot,16) != 1 and _read(slot,18) != 7
		48: _write(slot,38,_read(slot,36)); _write(slot,16,0)
		50: palette_requested.emit({"kind":"tint","transform":"night","start":208,"count":32,"interval":0,"tint_start":208,"tint_count":32})
		51: save_requested.emit(int(a[0]))
		52: _set_var(int(a[0]),town.get_control_mode(0))
		53,54:
			palette_requested.emit({"kind":"tint","transform":"whiten","start":32,"count":112,"interval":0,"tint_start":32,"tint_count":112})
			palette_requested.emit({"kind":"brightness","start":16,"count":16,"percent":40,"interval":0})
			palette_requested.emit({"kind":"brightness","start":144,"count":64,"percent":40,"interval":0})
			if op == 53: palette_requested.emit({"kind":"brightness","start":208,"count":32,"percent":40,"interval":0})
		55: _set_complete_flag(1)
		56,57:
			for i in battle.units.size():
				if not _read(i,16) in [1,3,4,5,8,9] or _read(i,18) == 7:
					_sprite(i,{"activate_flags":128 if op == 56 else 1})
	_changed()
	return false

func modal_result(value: int = 6) -> void:
	if not _modal_surface_commands.is_empty():
		var surface_commands:Array=_modal_surface_commands.duplicate(true);_modal_surface_commands.clear();_source_commands(surface_commands)
	if _scene_growth:
		_continue_scene_growth(); return
	if _choice_modal: equal_flag = value != 7
	_choice_modal = false
	if not _modal_followups.is_empty():
		_show_modal(_modal_followups.pop_front()); return
	modal_wait = false

func begin_scene_growth() -> void:
	_scene_growth = true; _scene_growth_cursor = 0; _scene_growth_notices.clear()
	_continue_scene_growth()

func _continue_scene_growth() -> void:
	while _scene_growth:
		if not _scene_growth_notices.is_empty():
			_show_modal({"kind":"scene_growth","duration_ms":4000,"text":_scene_growth_notices.pop_front()}); return
		if _scene_growth_cursor >= battle.units.size() or _read(_scene_growth_cursor,0) == 0:
			_scene_growth = false; modal_wait = false; return
		var slot := _scene_growth_cursor
		var unit: PackedByteArray = battle.units[slot]
		if unit.decode_s16(44) < unit.decode_u16(4)*100:
			_scene_growth_cursor += 1; continue
		_write(slot,4,unit.decode_u16(4)+1)
		var grown: Dictionary = battle.rules.grow_record(battle.units[slot],true,battle.rng)
		battle.units[slot] = grown.unit; battle.rng = grown.seeds
		var level := _read(slot,4)
		if _read(slot,18) == 0:
			var mask := 1 << ((_read(slot,0)-1)&31)
			var magics: Array = data.load_table("magic")
			for id in magics.size():
				var row: Dictionary = magics[id]
				if int(row.get("req_level",0)) == level and (int(row.get("learn_kind_mask",0))&mask) != 0:
					_scene_growth_notices.append(FT2Content.ui_text("skill_learned","%s: %s 습득") % [unit_name(slot),str(row.name)])
		_changed()

func _show_modal(request: Dictionary) -> void:
	modal_wait = true
	ui_requested.emit(request)

func unit_name(slot: int) -> String:
	if slot < 0 or slot >= battle.units.size(): return ""
	var kind := _read(slot,0)
	if kind < 30 and kind != 8: return str(_speaker_names.get(kind,""))
	var races: Array = data.load_table("race")
	var definition := _read(slot,2)
	return str(races[definition].get("name","")) if definition < races.size() else ""

func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.keycode == KEY_CTRL:
		control_held = event.pressed
	if mode == 9:
		return town.handle_input(event)
	if mode == 8:
		if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]):
			if scene.profile == 0: scene.skip()
			return true
	if mode == 4 and ((event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT])):
		if input_wait:_end_input_wait("input")
		return true
	if mode == 4 and event is InputEventMouseMotion: return true
	return false

func _end_input_wait(reason:String)->void:
	if not input_wait:return
	input_wait=false;deadline=-1
	input_wait_requested.emit("end",{"timer_id":400,"reason":reason,"input_wait_preserved":false,"source_mode":mode,"event":loaded_event})

func _finish(opcode: int) -> void:
	_source_commands([{"op":"restore","targets":["backdrop"]}])
	busy = false
	if opcode!=54:actor_cache_generation+=1;actor_cache_mode=previous_mode
	_raw.clear(); dialogue.clear(); dialogue_halves.clear(); actor_sprites.clear(); actor_busy.clear(); jobs.clear(); bitmap = "";alternate_surface=false;_surface_fill_index=-1
	mode = previous_mode
	_emit_actor_state()
	if opcode!=54 and not _complete_stage and _unit_window_saved!=0 and unit_window_visibility.is_valid():unit_window_visibility.call(true)
	_unit_window_saved=0
	if _overview_saved != 0 and overview_visibility.is_valid(): overview_visibility.call(true)
	_overview_saved = 0
	if not _hook.is_empty():
		var request := _hook.duplicate(); _hook.clear()
		battle.resume_hook(true, opcode == 36 or request.get("kind", "") != "battle")
	if _complete_stage:
		_complete_stage = false; current_event += 1; current_day = current_event
		start(current_event,"begin")
	finished.emit()

func _read(slot: int, offset: int, width: int = 2) -> int:
	if battle == null or slot < 0 or slot >= battle.units.size(): return 0
	var bytes: PackedByteArray = battle.units[slot]
	return bytes.decode_s32(offset) if width == 4 else bytes.decode_u16(offset)

func _write(slot: int, offset: int, value: int, width: int = 2) -> void:
	if battle == null or slot < 0 or slot >= battle.units.size(): return
	var bytes: PackedByteArray = battle.units[slot]
	if width == 4: bytes.encode_u32(offset,value & 0xFFFFFFFF)
	else: bytes.encode_u16(offset,value & 65535)
	battle.units[slot] = bytes

func _cell(slot: int) -> Vector2i:
	return Vector2i(_read(slot,8,4),_read(slot,12,4))

func _facing(delta: Vector2i) -> int:
	if absi(delta.x) > absi(delta.y): return 1 if delta.x > 0 else 2
	return 0 if delta.y >= 0 else 3

func _var(index: int) -> int:
	return variables[index] if index >= 0 and index < variables.size() else 0

func _set_var(index: int, value: int) -> void:
	if index >= 0 and index < variables.size(): variables[index] = _s16(value)

func _s16(value: int) -> int:
	return ((value + 32768) & 65535) - 32768

func _remove_actor(slot: int) -> void:
	if slot < 0 or slot >= battle.units.size(): return
	var empty := PackedByteArray(); empty.resize(124); empty.fill(0); battle.units[slot] = empty
	actor_sprites.erase(slot); actor_busy.erase(slot)
	jobs.clear(slot)

func _create_actor(a: Array, script_sprite: bool) -> void:
	var shift := 1 if script_sprite else 0
	var kind := int(a[shift])
	var descriptor: PackedByteArray = data.encode_unit({"kind":kind,"definition_id":7,"control":1,"x":int(a[shift+1]) if int(a[shift+1])>0 else 0,"y":int(a[shift+2]) if int(a[shift+2])>0 else 0})
	var constructed: Dictionary = battle.rules.construct(battle.units,descriptor,battle.rng)
	var slot := int(constructed.slot)
	battle.units = constructed.units; battle.rng = constructed.seeds
	if slot < 0: return
	var palette_start := 208 if kind >= 4000 else (32 if kind >= 1000 else 144)
	var palette_count := 32 if kind >= 4000 else (112 if kind >= 1000 else 64)
	if script_sprite:
		_last_resource_stem = str(a[0]).to_upper()
		_script_resource_serial += 1
		_last_script_resource_palette = {"stem":_last_resource_stem,"start":palette_start,"count":palette_count,"serial":_script_resource_serial}
	if _last_resource_stem != "":
		# OP14 reuses44C388: the acquired resource keeps its callback/remap even
		# when the new temporary Unit kind selects a different drawing priority.
		var resource := _last_script_resource_palette if str(_last_script_resource_palette.get("stem","")) == _last_resource_stem else {}
		_sprite(slot,{"stem":_last_resource_stem,"visible":true,"priority":5 if kind >= 4000 else 3,"palette_start":int(resource.get("start",palette_start)),"palette_count":int(resource.get("count",palette_count)),"palette_resource_serial":int(resource.get("serial",0))})

func _job_metadata(slot:int)->Dictionary:
	var metadata:Dictionary=actor_sprites.get(slot,{}).duplicate(true)
	if actor_player_query.is_valid():metadata["player_override"]=actor_player_query.call(slot)
	return metadata

func _set_complete_flag(value:int)->void:
	raw_globals["Main/CompleteFlag"]=value;complete_flag_requested.emit(value)

func _sprite(slot: int, changes: Dictionary) -> void:
	if slot < 0: return
	var state: Dictionary = actor_sprites.get(slot,{"id":slot,"visible":true,"label":"","world":_cell(slot)})
	if changes.get("play",false) or changes.has("stem") or changes.get("reset_body",false):
		state.erase("player_override")
		if jobs!=null and not jobs.is_busy(slot):jobs.clear(slot) # Replacing Unit70 invalidates a completed job's old visual alias.
	if changes.get("play",false):
		if str(state.get("stem","")) == "": state["stem"] = _actor_stem(slot)
		state["restart_serial"] = int(state.get("restart_serial",0))+1
	if changes.has("body_visible"):
		# OP08 shows Unit70 and Unit74, without showing Unit78 status sprites.
		state["visible"] = bool(changes.body_visible)
	state.merge(changes,true)
	state["command_serial"]=int(state.get("command_serial",0))+1
	state["changed_fields"]=changes.keys()
	if not changes.has("pos"): state.world = _cell(slot)
	actor_sprites[slot] = state
	_emit_actor_state()

func _actor_stem(slot: int) -> String:
	if _read(slot,2)==7 and actor_sprites.has(slot) and actor_sprites[slot].has("stem"):return str(actor_sprites[slot].stem)
	if actor_player_query.is_valid():
		var player=actor_player_query.call(slot)
		if player!=null:
			var stem:=str(player.apd.get("name",player.apd.get("source",""))).replace("\\","/").get_file().get_basename().to_upper()
			if stem!="":return stem #411BBE aliases actual Unit70; it does not force a mode4 V-sheet reload.
	if actor_sprites.has(slot) and actor_sprites[slot].has("stem"):return str(actor_sprites[slot].stem)
	return "CHAR_%02d%s" % [_read(slot,2),"V" if _read(slot,0) != 8 and _read(slot,0) < 30 and _read(slot,2) not in [23,72,73] else "A"]

func _job_cell(slot: int,cell: Vector2i) -> void:
	_write(slot,8,cell.x,4); _write(slot,12,cell.y,4)
	_changed()

func _emit_actor_state() -> void:
	var states: Dictionary = actor_sprites.duplicate(true)
	if jobs != null:
		for snapshot in jobs.snapshots():
			var state: Dictionary = actor_sprites.get(int(snapshot.id),snapshot.metadata).duplicate(true)
			state.merge(snapshot,true); states[int(snapshot.id)] = state
	actor_changed.emit({"mode":mode,"sprites":states.values(),"actor_cache_generation":actor_cache_generation,"actor_cache_mode":actor_cache_mode,"actor_npc_cache_generation":actor_npc_cache_generation})

func actor_finished(slot: int) -> void:
	actor_busy.erase(slot)

func _job_sound(stem: String,loop: bool) -> void:
	sound_requested.emit(stem,loop)

func _changed() -> void:
	if battle != null:
		if battle.has_method("refresh_context"): battle.refresh_context()
		if battle.has_signal("changed"): battle.changed.emit()

func _restore_units(half_mp: bool) -> void:
	for slot in battle.units.size():
		if _read(slot,0) == 0: continue
		_write(slot,38,_read(slot,36))
		_write(slot,42,int(_read(slot,40)/2) if half_mp else _read(slot,40))
		if _read(slot,16) != 9: _write(slot,16,0)
		_write(slot,100,0,4)

func _battle_reset() -> void:
	for slot in battle.units.size():
		if _read(slot,0) == 0: continue
		if _read(slot,38) == 0 or _read(slot,16) == 1: _write(slot,38,1); _write(slot,16,0)
		if _read(slot,16) != 9: _write(slot,16,0)
		for offset in [92,96,100]: _write(slot,offset,0,4)
		for offset in [76,78,80,82,84]: _write(slot,offset,0)
	previous_mode = 1
	battle.round_index = 0
	for slot in battle.units.size():
		if _read(slot,16) != 9:
			camera_requested.emit({"kind":"actor","slot":slot}); break
	_source_commands([{"op":"clear_rect","surface":"backdrop","rect":Rect2i(0,0,640,480),"color":0},{"op":"present","mode":"tactical"}]) #43E2DA..43E2F1, before round prepare/save.
	_overview_saved = 1
	_unit_window_saved=1 #43E30B, independent of whether the original window existed.
	save_requested.emit(30)

func _morph_context() -> void:
	var source := context_actor; var target := other_actor
	if source < 0 or target < 0 or _read(target,18) != 0: return
	for offset in [2,16,36,40,44,46,48,50,52,54]: _write(source,offset,_read(target,offset))
	_write(source,38,mini(_read(source,38),_read(target,36)))
	_write(source,42,int(_read(source,40)/2))
	var races: PackedByteArray = data.raw_table("race")
	var start: int = _read(source,2)*86+78
	if start+8 <= races.size():
		for i in 4: _write(source,56+i*2,races.decode_u16(start+i*2))
	_write(source,6,_facing(_cell(target)-_cell(source)))
	actor_sprites.erase(source);_emit_actor_state();actor_restore_requested.emit(source)

func _measure(raw: String, height: int, italic: bool = false) -> Dictionary:
	var font := {"family":"바탕","height":height,"weight":700,"italic":italic}
	if measure_text.is_valid(): return measure_text.call(raw,font)
	return {"width":0,"height":height,"ascent":height,"observed":false}

func _add_dialogue(raw: String) -> void:
	var first_command:=dialogue.size()
	var x := 64 if speaker == 0 else ((38-portrait_width_units)*16 if dialogue_top else 48)
	if speaker != 0 and dialogue_y == 0:
		dialogue_y = 40 if dialogue_top else 344
		text_size = 16; text_color = 26; text_style = 1
		var speaker_name := custom_speaker if speaker == 14 else str(_speaker_names.get(speaker,""))
		if speaker >= 30:
			var slot := _actor(speaker)
			if slot >= 0:
				var races: Array = data.load_table("race"); var definition := _read(slot,2)
				if definition < races.size(): speaker_name = str(races[definition].get("name",""))
		dialogue.append({"op":"text","text":speaker_name,"raw_text":speaker_name,"pos":Vector2i(x-18,dialogue_y),"font":{"family":"바탕","height":16,"weight":700,"italic":false},"color":26,"decor":{"style":1}})
		dialogue_y += 21; text_color = 30
		dialogue.append({"op":"text","text":"「","raw_text":"「","pos":Vector2i(x-18,dialogue_y),"font":{"family":"바탕","height":16,"weight":700,"italic":false},"color":30,"decor":{"style":1}})
	var y := dialogue_y
	var max_ascent := 0
	var previous_ascent := 0
	var previous_top := 0
	var previous_bottom := 0
	var run := ""
	var index := 0
	while index <= raw.length():
		if index == raw.length() or raw[index] == "[":
			if run != "":
				var metrics := _measure(run,text_size,text_style == 3)
				dialogue.append({"op":"text","raw_text":run,"text":run.replace("_"," ").replace("*",","),"pos":Vector2i(x,y),"font":{"family":"바탕","height":text_size,"weight":700,"italic":text_style == 3},"color":text_color,"decor":{"style":text_style}})
				x += int(metrics.width) + 29
				previous_ascent = int(metrics.ascent); previous_top = y; previous_bottom = y+int(metrics.height)+3
				max_ascent = maxi(max_ascent,int(metrics.ascent)); run = ""
			if index == raw.length(): break
			var end := raw.find("]",index)
			if end < 0: break
			var tag := raw.substr(index+1,end-index-1)
			if tag.begins_with("C"): text_color = int(tag.substr(1)) if int(tag.substr(1)) != 0 else 30
			if tag.begins_with("S"):
				text_size = int(tag.substr(1)) if int(tag.substr(1)) != 0 else 16
				if previous_bottom != 0:
					y = previous_ascent-text_size+previous_top+3
					dialogue_y = y
			index = end + 1
		else:
			run += raw[index]; index += 1
	dialogue_y += max_ascent + 5
	var half: Dictionary = dialogue_halves.get(int(dialogue_top),{"speaker":speaker,"variant":speaker_variant,"window":speaker != 0,"portrait":false})
	half.commands = dialogue.duplicate(true); dialogue_halves[int(dialogue_top)] = half
	var paint:Array=[{"op":"paint_backdrop","commands":dialogue.slice(first_command)}]
	if alternate_surface:paint.append_array([{"op":"restore","targets":["backdrop","main"]},{"op":"keyed_backdrop_to_main","key":0},{"op":"present","mode":"main"}])
	_source_commands(paint)

func _show_stage_title() -> void:
	var raw_length := 0
	if data.has_method("encode_cp949"): raw_length = data.encode_cp949(stage_title).size()
	else:
		for ch in stage_title: raw_length += 1 if ch.unicode_at(0) < 128 else 2
	var height := mini(60,int(630/maxi(1,raw_length)))
	var raw := "「%s」 " % stage_title
	var metrics := _measure(raw,height,true)
	var chapter := "%d일째%s " % [current_event,"(Judgement Day)" if current_event == 17 else ""]
	_title_commands = [{"op":"text","raw_text":chapter,"text":chapter,"pos":Vector2i(64,120),"font":{"family":"바탕","height":45,"weight":700,"italic":true},"color":30,"decor":{"style":3}},
		{"op":"text","raw_text":raw,"text":raw.replace("_"," ").replace("*",","),"pos":Vector2i(int((640-int(metrics.width)-33)/2),int((480-int(metrics.height)-3)/2)),"font":{"family":"바탕","height":height,"weight":700,"italic":true},"color":30,"decor":{"style":3}}]
	text_size = height; text_style = 3; text_color = 30
	_source_commands([{"op":"paint_main" if alternate_surface else "paint_backdrop","commands":_title_commands.duplicate(true)},{"op":"present","mode":"main" if alternate_surface else "tactical"}])

func _source_commands(commands:Array)->void:
	source_commands_requested.emit(commands)

func _dialogue_half_commands(half:int,include_clear:bool=true,include_text:bool=true)->Array[Dictionary]:
	var out:Array[Dictionary]=[]
	var state:Dictionary=dialogue_halves.get(half,{})
	if state.is_empty():return out
	var top:=half!=0
	if include_clear:out.append({"op":"rect","rect":Rect2i(0,0 if top else 240,640,240),"color":0,"filled":true})
	if state.get("window",false):out.append_array(preload("res://scripts/ui/ft2_widgets.gd").game_panel(8,20 if top else 324,37,7))
	if state.get("portrait",false):
		var key:="BMP/FACE%02d%s.BMP" % [int(state.speaker),str(state.variant).to_upper()]
		var size:Vector2i=_bitmap_sizes[key]
		out.append({"op":"bitmap","key":key,"pos":Vector2i(16,0) if top else Vector2i(384,304),"source":Rect2i(0,0,size.x,size.y-16),"transparent":255,"flip":1 if top else 0,"remaps":[[10,64,144],[74,16,208 if top else 224]],"palette_base_install":[[144,64]],"palette_install":([[144,64]] if alternate_surface else [])+[[208 if top else 224,16]]})
	if include_text:out.append_array(state.get("commands",[]))
	return out

func draw_commands() -> Array[Dictionary]:
	if mode == 9: return town.commands()
	if mode == 8: return scene.commands()
	if not source_commands_requested.get_connections().is_empty():return []
	var out: Array[Dictionary] = []
	if alternate_surface and _surface_fill_index>=0:out.append({"op":"rect","rect":Rect2i(0,0,640,480),"color":_surface_fill_index,"filled":true})
	elif alternate_surface and bitmap != "": out.append({"op":"bitmap","key":bitmap,"pos":Vector2i.ZERO,"centered":true,"transparent":-1})
	for half in dialogue_halves:
		var state: Dictionary = dialogue_halves[half]
		var top := int(half) != 0
		var y := 0 if top else 240
		out.append({"op":"rect","rect":Rect2i(0,y,640,240),"color":0,"filled":true})
		if state.get("window",false): out.append_array(preload("res://scripts/ui/ft2_widgets.gd").game_panel(8,20 if top else 324,37,7))
		if state.get("portrait",false):
			var key := "BMP/FACE%02d%s.BMP" % [int(state.speaker),str(state.variant).to_upper()]
			var size: Vector2i = _bitmap_sizes[key]
			out.append({"op":"bitmap","key":key,"pos":Vector2i(16,0) if top else Vector2i(384,304),"source":Rect2i(0,0,size.x,size.y-16),"transparent":255,"flip":1 if top else 0,"remaps":[[10,64,144],[74,16,208 if top else 224]],"palette_base_install":[[144,64]],"palette_install":([[144,64]] if alternate_surface else [])+[[208 if top else 224,16]]})
		out.append_array(state.commands)
	out.append_array(_title_commands)
	return out

func _scene_operation(command: Dictionary) -> void:
	var name := str(command.get("operation","")); var args: Array = command.get("args",[])
	if name == "midi_profile_start_reset_global_epoch": music_requested.emit(int(args[0]))
	elif name == "wave_play_path": sound_requested.emit(str(command.get("relative_path",scene._model.get("formatted_path",""))),int(args[2]) != 0)
	elif name == "wave_slot_play_stop":
		var path: String = str(scene._model.wave_slots.get(int(args[0]),""))
		if int(args[1]) != 0: sound_requested.emit(path,false)
		else: sound_stop_requested.emit(path)
	elif name in ["release_cue_reset_scene","reset_layer_scene","wave_release_all"]:
		for path in scene._model.get("last_released_waves",[]): sound_stop_requested.emit(str(path))
	elif name == "palette_copy_bitmap":
		var bitmap: Dictionary = scene._model.bitmaps.get(int(args[0]),{})
		if not bitmap.is_empty(): palette_requested.emit({"kind":"copy_bitmap","key":"BMP/"+str(bitmap.stem)+".BMP","remaps":bitmap.remaps,"start":int(args[1]),"count":int(args[2])})
	elif name == "photo_move_palette_envelope":
		var bitmap: Dictionary = scene._model.bitmaps.get(int(args[1]),{})
		if not bitmap.is_empty():
			#42A220: black current range, copy bitmap BASE, then fade to BASE.
			palette_requested.emit({"kind":"black","start":int(args[2]),"count":int(args[3]),"interval":0})
			palette_requested.emit({"kind":"copy_bitmap_base","key":"BMP/"+str(bitmap.stem)+".BMP","remaps":bitmap.remaps,"start":int(args[2]),"count":int(args[3])})
			palette_requested.emit({"kind":"restore","start":int(args[2]),"count":int(args[3]),"interval":int(int(args[9])/128)})
	elif name == "layer_callback_surface_create" and int(args[6]) != 0:
		#42A160 applies the cached callback bitmap's load-time BASE palette.
		palette_requested.emit({"kind":"copy_bitmap_base","key":str(command.get("bitmap_path","BMP/STAR.BMP")),"remaps":[[10,int(args[6]),int(args[5])]],"start":int(args[5]),"count":int(args[6])})
	elif name in ["palette_fade_playable","palette_fade_range"]:
		var shift := 2 if name == "palette_fade_range" else 0
		var target := int(args[shift+1])
		if target in [1,2,4]:
			palette_requested.emit({"kind":{1:"restore",2:"black",4:"white"}[target],"interval":int(args[shift]),"start":int(args[0]) if shift else 10,"count":int(args[1]) if shift else 236})
	elif name in ["palette_fill_playable","palette_fill_range"]:
		var shift := 2 if name == "palette_fill_range" else 0
		palette_requested.emit({"kind":"fill","rgb":[int(args[shift]),int(args[shift+1]),int(args[shift+2])],"start":int(args[0]) if shift else 10,"count":int(args[1]) if shift else 236})
	elif name == "palette_rotate": palette_requested.emit({"kind":"rotate","start":int(args[0]),"count":int(args[1]),"shift":int(args[2])})
	elif name == "palette_set_entry_RGB": palette_requested.emit({"kind":"set_entry","index":int(args[0]),"rgb":[int(args[1]),int(args[2]),int(args[3])]})
	elif name in ["APD_resource_load_remap","APD_resource_palette_restore"]:
		var resource: Dictionary = scene._model.apd_resources.get(int(args[0]),{})
		if not resource.is_empty(): palette_requested.emit({"kind":"apd_palette","stem":resource.stem,"start":int(resource.palette_start),"count":int(resource.palette_count),"remaps":[[10,int(resource.palette_count),int(resource.palette_start)]]})

func _source_surface_fill(index:int)->void:
	_surface_fill_index=index if alternate_surface else -1
	if not source_commands_requested.get_connections().is_empty():
		_source_commands([{"op":"clear_rect","surface":"main","rect":Rect2i(0,0,640,480),"color":index},{"op":"present","mode":"main"}])
	else:
		dialogue.clear();dialogue_halves.clear();_title_commands.clear()
		palette_requested.emit({"kind":"surface_fill","color":index,"present":true})




