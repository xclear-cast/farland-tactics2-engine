class_name FT2PhysicalProgram
extends RefCounted
## Semantic43A200 builder. Inputs are live binary units, path and numeric records.
## Uses authored APD data; never executes Python, x86 or saved whole programs.
const DIRS = [Vector2i(0,1),Vector2i(1,0),Vector2i(-1,0),Vector2i(0,-1)]
const DAMAGE_LABELS = ["DEFENSE","UP_DAMAGE","MIDDLE_DAMAGE","DOWN_DAMAGE","UP_DAMAGE","","","","DEFENSE","MIDDLE_DAMAGE","UP_DAMAGE","DOWN_DAMAGE","UP_DAMAGE","","",""]
var data
var rules
var navigation
var records: Array = []
var units: Array = []
var plan: Dictionary = {}
var _cache: Dictionary = {}
var _generated = 0
var _body_stem = ""
var _actor_slot = -1
var _actor: PackedByteArray
var _error = ""
var _available_sounds: Dictionary = {}

func _init(source_data = null, rule_set = null, nav = null) -> void:
	data = source_data
	rules = rule_set
	navigation = nav

static func f32(value: float) -> float:
	var bytes = PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0,value)
	return bytes.decode_float(0)
static func s16(value: int) -> int: return ((value+32768)&65535)-32768
static func vector(value: Variant) -> Vector2i:
	return value if value is Vector2i else Vector2i(int(value[0]),int(value[1]))
static func pair(value: Vector2i) -> Array: return [value.x,value.y]

func _apd(stem: String) -> Dictionary:
	if not _cache.has(stem): _cache[stem] = data.load_apd(stem)
	return _cache[stem]

func normalized_groups(stem: String,suffix: String,direction: int,definition: int = -1) -> Dictionary:
	return _resolve(stem,suffix,direction,definition)

func retimed_groups(groups: Array,dx: int,dy: int,ms: int = 0,repeat: int = 1,stride: int = 1) -> Array:
	return _retimed(groups,dx,dy,ms,repeat,stride)

func generated_sequence(pre: Array,main: Array,post: Array,dx: int,dy: int,height: int,ms: int = 0,count: int = 0,endpoint_policy: int = 3) -> Array:
	return _generated_groups(pre,main,post,dx,dy,height,ms,count,endpoint_policy)

func _sound_cache() -> Array:
	if _available_sounds.is_empty():
		var audio = data.read_json("data/port_ready/assets/audio/index.json")
		for row in audio.get("WAV",[]):
			var stem = str(row.source).get_file().get_basename().to_lower()
			if stem.begins_with("battle") and stem.trim_prefix("battle").is_valid_int(): _available_sounds[int(stem.trim_prefix("battle"))] = true
	var cache: Array = []
	var table: Dictionary = plan.get("indirect_sound_table",{})
	var enabled = bool(plan.get("audio_enabled",true))
	for record in records:
		record.sound_triggers = []
		if not record.type in [0,1,2]: continue
		var prior = 0
		for command in record.commands:
			var ordinal = 0
			for group in command.compiled_groups:
				for step in group.steps:
					var event = int(step.event)
					if event != -1 and int(step.indirect) in [0,1]:
						if int(step.indirect) == 1: event = int(table.get(event,table.get(str(event),0)))
						if enabled and _available_sounds.has(event):
							if not cache.has(event): cache.append(event)
							record.sound_triggers.append([prior+ordinal,cache.find(event)])
					ordinal += 1
			prior += command.compiled_steps
	return cache

func _resolve(stem: String, suffix: String, direction: int, definition: int = -1) -> Dictionary:
	var requested = ("B." if direction in [2,3] else "F.")+suffix
	var flags = 1|(16 if direction in [1,2] and not definition in [23,73] else 0)
	var animations: Dictionary = _apd(stem).get("animations",{})
	var selected = requested
	if animations.has(requested) and (flags&16) != 0 and animations.has(requested+"#"):
		selected += "#"
		flags &= ~16
	var found = animations.get(selected,{})
	var groups: Array = []
	for g in found.get("compiled_groups",[]):
		var steps: Array = []
		for step in g.steps: steps.append({"ms":int(step.duration_ms),"image":int(step.image_frame),"event":int(step.sound_event_id),"indirect":int(step.sound_event_indirect),"flags":int(step.draw_flags),"marker":int(step.action_marker)})
		groups.append({"move_total_xy":g.move_total_xy.duplicate(),"velocity_float32":g.compiled_sequence_velocity_per_ms.duplicate(),"zero_motion":int(g.move_total_xy == [0,0]),"steps":steps})
	return {"requested":requested,"selected":selected if not found.is_empty() else "","flags":flags,"groups":groups}

func _record(slot: int, type: int, stem: String) -> Dictionary:
	if records.size() >= 32: return {}
	var record = {"record":records.size(),"unit_slot":slot,"type":type,"state":2,"APD":stem,"commands":[],"child_triggers":[],"sound_triggers":[],"record_flags":1 if type in [2,3] else 2 if type == 1 and units[slot].decode_u16(16) in [4,5] else 0,"auto_cleanup":type in [2,3],"shares_unit_sprite":type == 1}
	records.append(record)
	return record

func _command(record: Dictionary,suffix: String,direction: int,from: Vector2i,to: Vector2i,output: Vector2i,offset: Vector2i = Vector2i.ZERO,height_delta: int = 0) -> Dictionary:
	var slot = int(record.unit_slot)
	var definition = units[slot].decode_u16(2) if slot >= 0 else -1
	var resolved = _resolve(str(record.APD),suffix,direction,definition)
	var command = {"index":record.commands.size(),"label_buffer32":resolved.requested,"label":[record.APD,resolved.selected] if resolved.selected != "" else null,"resolved_label":[record.APD,resolved.selected] if resolved.selected != "" else null,"generated":false,"flags":resolved.flags,"APD_flags":resolved.flags,"world_from":pair(from),"world_to":pair(to),"output_xy":pair(output),"from":pair(from),"to":pair(to),"output":pair(output),"offset_xy":pair(offset),"height_delta_px":s16(height_delta),"direction":direction,"flags37":0,"compiled_groups":resolved.groups,"groups":resolved.groups,"compiled_steps":_step_count(resolved.groups)}
	record.commands.append(command)
	return command

static func _step_count(groups: Array) -> int:
	var n = 0
	for g in groups: n += g.steps.size()
	return n

func _prefix_steps(record: Dictionary, command_index: int) -> int:
	var n = 0
	for i in range(mini(command_index,record.commands.size())): n += int(record.commands[i].compiled_steps)
	return n

static func trajectory(dx: int,dy: int,height: int,count: int) -> Array:
	if count < 1: return [Vector2i(dx,dy)]
	var vx = f32(float(dx)/count)
	var vy = f32(float(dy)/count)
	var curve = f32(float(height*4)/(count*count))
	var half = f32(float(count)*0.5)
	var out: Array = []
	for i in range(count):
		var x = s16(int(vx*i))
		var y = s16(int(vy*i))
		var z = s16(int((half-i)*(half-i)*curve-height))
		out.append(Vector2i(x,y+z))
	out.append(Vector2i(dx,dy))
	return out

func _generated_groups(pre: Array,main: Array,post: Array,dx: int,dy: int,height: int,ms_override: int = 0,count_override: int = 0,endpoint_policy: int = 3) -> Array:
	var out: Array = []
	_endpoint(out,pre,ms_override,endpoint_policy)
	var n = count_override if count_override != 0 else _step_count(main)
	if not main.is_empty() and n > 0:
		var positions = trajectory(dx,dy,height,n)
		var selected: Array = []
		while selected.size() < n:
			for group in main:
				for step in group.steps:
					selected.append(step.duplicate())
					if selected.size() >= n: break
		if selected.size()+1 > positions.size():
			_error = "Conditional generated sequence reads unwritten trajectory scratch; no invented sample"
			return []
		for i in range(selected.size()):
			var step: Dictionary = selected[i]
			if ms_override != 0: step.ms = ms_override
			var motion: Vector2i = positions[i+1]-positions[i]
			motion = Vector2i(s16(motion.x),s16(motion.y))
			out.append({"move_total_xy":pair(motion),"velocity_float32":[f32(float(motion.x)/step.ms),f32(float(motion.y)/step.ms)],"zero_motion":int(motion == Vector2i.ZERO),"steps":[step]})
	_endpoint(out,post,ms_override,endpoint_policy)
	return out

func _endpoint(out: Array,groups: Array,ms: int,policy: int) -> void:
	if groups.is_empty(): return
	var group: Dictionary = groups[0].duplicate(true)
	var total = 0
	for step in group.steps:
		if ms != 0: step.ms = ms
		total += step.ms
	var motion = vector(group.move_total_xy)
	group.velocity_float32 = [f32(float(motion.x)/total),f32(float(motion.y)/total)]
	group.zero_motion = int(motion == Vector2i.ZERO)
	for ignored in range(1 if policy == 3 else 2): out.append(group.duplicate(true))

func _set_generated(command: Dictionary,groups: Array) -> void:
	_generated += 1
	command.generated = true
	command.label = ["generated",_generated]
	command.resolved_label = command.label
	command.compiled_groups = groups
	command.groups = groups
	command.compiled_steps = _step_count(groups)

func _height_delta(from: Vector2i,to: Vector2i) -> int: return (navigation.height(to)-navigation.height(from))*8
func _project(point: Vector2i) -> Vector2i: return navigation.project(point) if plan.get("projection_enabled",true) else Vector2i.ZERO

func _ground_path(body: Dictionary,path: Array,run: bool) -> Vector2i:
	var point = vector(plan.origin)
	var count = maxi(0,path.size()-2) if run else path.size()
	for i in range(count):
		var d = int(path[i])
		var to = point+DIRS[d]
		var output = point+Vector2i(int(d == 1),int(d == 0))
		var delta = _height_delta(point,to)
		var command = _command(body,"RUN1" if i%2 == 0 else "RUN2",d,point,to,output,Vector2i.ZERO,delta)
		if absi(delta) > 16:
			var stem = str(body.APD)
			var definition = _actor.decode_u16(2)
			var pre = _resolve(stem,"JUMP1",d,definition)
			var main = _resolve(stem,"JUMP2" if delta > 0 else "DOWN2",d,definition)
			var post = _resolve(stem,"DOWN1",d,definition)
			var screen = _project(to)-_project(point)
			if (post.flags&16) != 0: screen.x = -screen.x
			command.label_buffer32 = ""
			command.flags = post.flags
			command.APD_flags = post.flags
			_set_generated(command,_generated_groups(pre.groups,main.groups,post.groups,screen.x,screen.y,8,50,4,1 if delta > 0 else 2))
		point = to
	return point

func _clones(body: Dictionary,start_command: int,end_command: int) -> void:
	if end_command <= start_command: return
	for delay in [2,4,6]:
		var clone = _record(-1,3,_body_stem)
		if clone.is_empty(): continue
		clone.dither = delay
		clone.commands = []
		for i in range(start_command,end_command):
			var c: Dictionary = body.commands[i].duplicate(true)
			c.index = clone.commands.size()
			c.label_buffer32 = ""
			c.flags37 = 0
			clone.commands.append(c)
		body.child_triggers.append([_prefix_steps(body,start_command)+delay-1,clone.record])

func _reactions(body: Dictionary,index: int,attack: Dictionary,direction: int) -> void:
	var markers: Array = []
	var ordinal = 0
	for group in attack.compiled_groups:
		for step in group.steps:
			if int(step.marker) != 0: markers.append([ordinal,int(step.marker)])
			ordinal += 1
	var targets: Array = plan.get("results",[])
	if targets.is_empty(): return
	var rounds = maxi(1,rules.div0(markers.size(),targets.size()))
	var cursor = 0
	for ignored in range(rounds):
		for result in targets:
			if cursor >= markers.size(): return
			var marker: Array = markers[cursor]
			cursor += 1
			var slot = int(result.target_slot)
			if slot < 0: continue
			var target: PackedByteArray = units[slot]
			var facing = target.decode_u16(6)
			var damaged = int(result.get("damage_flag",0)) != 0
			var suffix = DAMAGE_LABELS[int(marker[1])+(8 if facing == direction else 0)] if damaged else "DEFENSE"
			var record = _record(slot,1,"CHAR_%02dA"%target.decode_u16(2))
			if record.is_empty(): continue
			var point = rules.xy(target)
			_command(record,suffix,facing,point,point,point)
			var threshold = _prefix_steps(body,index)+int(marker[0]) if damaged else _prefix_steps(body,maxi(index-1,0))
			body.child_triggers.append([threshold,record.record])
			if damaged:
				var hit = _record(-1,2,"HITMARK")
				if hit.is_empty(): continue
				_command(hit,"HITMARK",direction,point,point,point,Vector2i(-16,0))
				record.child_triggers.append([0,hit.record])

func _ordinary_attack(body: Dictionary,point: Vector2i,style: int,direction: int) -> void:
	var index = body.commands.size()
	var command = _command(body,"ATTACK%d"%style,direction,point,point,point)
	command.flags37 |= 2
	var results: Array = plan.get("results",[])
	if (not results.is_empty() and int(results[0].get("critical",0)) != 0) or int(plan.get("prepared_before",0)) != 0: _clones(body,index,index+1)
	_reactions(body,index,command,direction)

func _dash_attack(body: Dictionary,point: Vector2i,path: Array,direction: int) -> void:
	var to = point+DIRS[direction]*2
	var output = point+Vector2i(2 if direction == 1 else 0,2 if direction == 0 else 0)
	var stem = str(body.APD)
	var definition = _actor.decode_u16(2)
	var main = _resolve(stem,"DASH_ATTACK1",direction,definition)
	var post = _resolve(stem,"DASH_ATTACK1C",direction,definition)
	var screen = _project(to)-_project(point)
	if (post.flags&16) != 0: screen.x = -screen.x
	var command = _command(body,"DASH_ATTACK1",direction,point,to,output,Vector2i.ZERO,_height_delta(point,to))
	command.label_buffer32 = ""
	command.flags = post.flags
	command.APD_flags = post.flags
	command.flags37 |= 2
	_set_generated(command,_generated_groups([],main.groups,post.groups,screen.x,screen.y,32))
	var index = body.commands.size()-1
	_reactions(body,index,command,direction)
	_clones(body,index,index+1)

func _retimed(groups: Array,dx: int,dy: int,ms: int = 0,repeat: int = 1,stride: int = 1) -> Array:
	if groups.is_empty(): return []
	var steps: Array = []
	var total = 0
	for ignored in range(maxi(1,repeat)):
		for i in range(0,groups[0].steps.size(),maxi(1,stride)):
			var step: Dictionary = groups[0].steps[i].duplicate()
			if ms != 0: step.ms = ms
			total += step.ms
			steps.append(step)
	if total == 0: return []
	return [{"move_total_xy":[s16(dx),s16(dy)],"velocity_float32":[f32(float(s16(dx))/total),f32(float(s16(dy))/total)],"zero_motion":int(dx == 0 and dy == 0),"steps":steps}]

func _lift(body: Dictionary,point: Vector2i,direction: int,height: int,landing: bool) -> void:
	if not landing: _command(body,"TAKE_OFF1",direction,point,point,point)
	var c = _command(body,"TOUCH_DOWN2" if landing else "TAKE_OFF2",direction,point,point,point,Vector2i(0,-height if landing else 0))
	_set_generated(c,_retimed(c.groups,0,height if landing else -height,0,2,1))
	if landing: _command(body,"TOUCH_DOWN2",direction,point,point,point)

func _flight_command(body: Dictionary,suffix: String,point: Vector2i,direction: int,dx: int,dy: int,offset_y: int,ms: int = 0) -> Vector2i:
	var to = point+DIRS[direction]
	var output = point+Vector2i(int(direction == 1),int(direction == 0))
	var c = _command(body,suffix,direction,point,to,output,Vector2i(0,offset_y),_height_delta(point,to))
	if (c.flags&16) != 0: dx = -dx
	if (c.flags&32) != 0: dy = -dy
	_set_generated(c,_retimed(c.groups,dx,dy,ms,1,1))
	return to

func _flight_nodes(path: Array) -> Array:
	var nodes: Array = []
	var point = vector(plan.origin)
	var sprite_heights: Dictionary = plan.get("sprite_half_heights",{})
	for i in range(path.size()+1):
		var map_height = navigation.height(point)*8
		var obstruction = 0
		if i > 0:
			for slot in range(units.size()):
				var unit: PackedByteArray = units[slot]
				if unit.decode_u16(0) != 0 and (unit.decode_u16(16) != 9 or unit.decode_u16(0) == 8) and rules.xy(unit) == point:
					obstruction = int(sprite_heights.get(slot,sprite_heights.get(str(slot),0)))
					break
		nodes.append({"point":point,"map_height":s16(map_height),"height":s16(map_height+obstruction),"direction":int(path[i]) if i < path.size() else 4,"dx":0,"dy":0,"offset":0})
		if i < path.size(): point += DIRS[int(path[i])]
	return nodes

func _flight_segments(nodes: Array) -> Array:
	var segments: Array = []
	var start = 0
	while start < nodes.size()-1:
		var end = start+1
		while end < nodes.size()-1 and nodes[end].direction == nodes[start].direction: end += 1
		var final = nodes[end].direction == 4
		var current = start
		while current != end:
			var chosen = end
			var baseline = f32(float(nodes[end].height-(segments[-1].end_height if not segments.is_empty() else nodes[current].height))/(end-current)) if final else 0.0
			var slope = baseline
			for candidate in range(current+1,end+1):
				var ratio = float(nodes[candidate].height-nodes[current].height)/(candidate-current)
				if ratio >= slope:
					chosen = candidate
					slope = f32(ratio)
			if baseline == slope: chosen = end
			var first = int(segments[-1].end_height) if not segments.is_empty() else int(nodes[current].height)
			var last = int(nodes[chosen].height) if final else maxi(nodes[chosen].height,nodes[current].height)
			segments.append({"start":current,"end":chosen,"start_height":first,"end_height":last})
			current = chosen
		start = end
	for segment in segments:
		var first = int(segment.start)
		var last = int(segment.end)
		var count = last-first
		#43C340 cancels terrain H from projected Y, then subtracts flight slope.
		var a: Vector2i = navigation.project(nodes[first].point)+Vector2i(0,nodes[first].map_height)
		var b: Vector2i = navigation.project(nodes[last].point)+Vector2i(0,nodes[last].map_height)
		var dx = rules.div0(b.x-a.x,count)
		var dy = rules.div0(b.y-a.y-(segment.end_height-segment.start_height),count)
		var h_step = rules.div0(segment.end_height-segment.start_height,count)
		var accumulated = 0
		for i in range(first,last):
			nodes[i].dx = dx
			nodes[i].dy = dy
			nodes[i].offset = s16(nodes[i].map_height-segment.start_height-accumulated)
			accumulated += h_step
	return segments

func _fly_path(body: Dictionary,path: Array,route: bool) -> Vector2i:
	var point = vector(plan.origin)
	if path.is_empty(): return point
	if route: _lift(body,point,int(path[0]),48,false)
	var nodes = _flight_nodes(path)
	_flight_segments(nodes)
	for i in range(path.size()):
		var n: Dictionary = nodes[i]
		point = _flight_command(body,"FLY1" if i%2 == 0 else "FLY2",point,int(path[i]),n.dx,n.dy,n.offset-48)
	if route: _lift(body,point,int(path[-1]),48,true)
	return point

func _fly_dash(body: Dictionary,path: Array,direction: int) -> void:
	var point = vector(plan.origin)
	_lift(body,point,int(path[0]),48,false)
	var count = path.size()+1
	var virtual_end = point+DIRS[int(path[0])]*count
	var start_height = navigation.height(point)*8+48
	var end_height = navigation.height(virtual_end)*8+24
	var a = _project(point)+Vector2i(0,navigation.height(point)*8)
	var b = _project(virtual_end)+Vector2i(0,navigation.height(virtual_end)*8)
	var dx = rules.div0(b.x-a.x,count)
	var dy = rules.div0(b.y-a.y-(end_height-start_height),count)
	var h_step = rules.div0(end_height-start_height,count)
	var height_offset = 0
	for ignored in range(count-2):
		point = _flight_command(body,"DASH_ATTACK1A",point,int(path[0]),dx,dy,navigation.height(point)*8-start_height+height_offset,20)
		height_offset -= h_step
	var index = body.commands.size()
	var last_ms = 70+rules.div0(-50,count)*(count-2)
	point = _flight_command(body,"DASH_ATTACK1B",point,int(path[0]),dx,dy,navigation.height(point)*8-start_height+height_offset,last_ms)
	_reactions(body,index,body.commands[index],direction)
	_clones(body,index,index+1)
	height_offset -= h_step
	_lift(body,point,int(path[0]),start_height-navigation.height(point)*8-height_offset,true)

func build(action_plan: Dictionary) -> Dictionary:
	plan = action_plan
	records = []
	_generated = 0
	_error = ""
	units = rules.copy_units(plan.get("after_units",[]))
	_actor_slot = int(plan.get("actor_slot",-1))
	if _actor_slot < 0 or _actor_slot >= units.size(): return {"records":[],"error":"Physical actor missing"}
	_actor = units[_actor_slot].duplicate()
	rules.set_xy(_actor,vector(plan.origin))
	units[_actor_slot] = _actor
	_body_stem = str(plan.get("body_stem_override","CHAR_%02dB"%_actor.decode_u16(2)))
	if _apd(_body_stem).is_empty(): return {"records":[],"error":"Original physical body APD unavailable: "+_body_stem}
	var results: Array = plan.get("results",[])
	var path: Array = plan.get("path",[])
	if results.is_empty() and path.is_empty(): return {"records":[],"error":"","empty":true}
	var style = rules.items.decode_u16(_actor.decode_u16(20)*56+48)
	if style == 0: style = 1
	if int(plan.get("prepared_before",0)) == 1: style = 6
	if rules.items.decode_u16(_actor.decode_u16(20)*56+50) == 3: return {"records":[],"error":"Shipping bow170..174 absent ARROW labels; conditional original failure retained"}
	var body = _record(_actor_slot,0,_body_stem)
	var run = int(plan.get("accepted_run",0)) != 0
	var direction = int(plan.get("direction",_actor.decode_u16(6)))
	var flying = int(plan.get("game_mode",navigation.map_mode)) == 1 and (rules.races.decode_u16(_actor.decode_u16(2)*86+62) != 99 or _actor.decode_u16(16) == 11 or rules.has_ability(_actor,11))
	var route = bool(plan.get("native_route",flying))
	if flying and run and not results.is_empty(): _fly_dash(body,path,direction)
	else:
		var point = _fly_path(body,path,route) if flying else _ground_path(body,path,run)
		if not results.is_empty():
			if run: _dash_attack(body,point,path,direction)
			else: _ordinary_attack(body,point,style,direction)
	for record in records:
		var triggers: Array = record.child_triggers
		for i in range(triggers.size()-1):
			for j in range(i+1,triggers.size()):
				if triggers[j][0] < triggers[i][0]:
					var temp = triggers[i]
					triggers[i] = triggers[j]
					triggers[j] = temp
	var cache = _sound_cache()
	return {"records":records,"error":_error,"selected_attack_style":style,"projectile_flag":0,"native_route":int(route),"start_record":0,"source":"Semantic43A200 ground/fly/charge/motion/marker/clone GDScript","sound_cache_event_ids":cache,"cache_event_ids":cache,"sound_paths":cache.map(func(identity):return "wave/battle%02d.wav"%identity)}
