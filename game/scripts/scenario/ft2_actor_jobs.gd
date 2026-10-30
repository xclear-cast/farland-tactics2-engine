class_name FT2ActorJobs
extends RefCounted
## EVENT4117C0/411D10/411350 path jobs; APD timing is the shared source player.
signal cell_committed(id: int, cell: Vector2i)
signal finished(id: int)
signal changed
signal sound_requested(stem: String, loop: bool)
var data
var jobs: Dictionary = {}
var errors: Array[Dictionary] = []
var optional_sound_attempts: Array[Dictionary] = []
var _sounds: Dictionary = {}
const DELTAS := [Vector2i(0,1),Vector2i(1,0),Vector2i(-1,0),Vector2i(0,-1)]

func _init(store) -> void: data = store

static func directions(path: Variant) -> Array[int]:
	var out: Array[int] = []
	if path is String:
		for ch in str(path).to_lower():
			var direction: int = int({"s":0,"e":1,"w":2,"n":3}.get(ch,4))
			if int(direction) == 4: break
			out.append(int(direction))
	else:
		for direction in path:
			if int(direction) == 4: break
			if int(direction) < 0 or int(direction) > 3: break
			out.append(int(direction))
	return out

static func build_path(start: Vector2i,path: Variant,base_label: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cell := start
	for direction in directions(path):
		var destination: Vector2i = cell+DELTAS[direction]
		var depth := cell
		if direction == 0: depth.y += 1
		if direction == 1: depth.x += 1
		out.append({"type":0,"source":cell,"destination":destination,"sort_world":depth,
			"label":("B." if direction in [2,3] else "F.")+base_label+str(1+out.size()%2),
			"flags":17 if direction in [1,2] else 1,"direction":direction})
		cell = destination
	return out

func play_path(id: int,stem: String,start: Vector2i,path: Variant,base_label: String,now: int,metadata: Dictionary = {}) -> bool:
	var steps := build_path(start,path,base_label)
	if steps.is_empty(): return false
	if not jobs.has(id) and jobs.size() >= 128: return false
	jobs[id] = {"id":id,"stem":stem,"steps":steps,"index":0,"world":start,"metadata":metadata.duplicate(true),"path":true,"active":true}
	_start_step(jobs[id],now)
	return true

func play_single(id: int,stem: String,start: Vector2i,label: String,now: int,metadata: Dictionary = {},direction: int = 4) -> bool:
	if not jobs.has(id) and jobs.size() >= 128: return false
	# 412190/412250 retain Unit+06 direction even for an unprefixed label.
	jobs[id] = {"id":id,"stem":stem,"steps":[{"type":0,"source":start,"destination":start,"sort_world":start,"label":label,"flags":17 if direction in [1,2] else 1,"direction":direction}],"index":0,"world":start,"metadata":metadata.duplicate(true),"path":false,"active":true}
	_start_step(jobs[id],now)
	return true

func _start_step(job: Dictionary,now: int) -> void:
	var step: Dictionary = job.steps[int(job.index)]
	job.world = step.source
	job.sort_world = step.sort_world
	if not job.has("player"):
		var original=job.metadata.get("player_override")
		job.player=original if original!=null else preload("res://scripts/render/ft2_apd_player.gd").new()
	var dataset: Dictionary = data.load_apd(str(job.stem))
	var normalized: Dictionary = preload("res://scripts/render/ft2_apd_player.gd").normalize(dataset)
	var requested := str(step.label).to_upper()
	for name in normalized.get("animations",{}):
		if str(name).to_upper() != requested and str(name).to_upper() != requested+"#": continue
		for group in normalized.animations[name].get("groups",[]):
			for frame in group.get("steps",[]):
				if int(frame[3]) >= 0: _prepare_sound(int(frame[3]))
	if not job.player.step_event.is_connected(_sound_event):job.player.step_event.connect(_sound_event)
	var ok: bool = job.player.play(dataset,str(step.label),now,int(step.flags))
	if int(job.index) == 0 and ok and job.player.frame >= 0:
		job.player.visible = true #41240D shows the newly prepared job sprite.
	if not ok: errors.append({"id":int(job.id),"stem":job.stem,"label":step.label,"error":"Source APD label lookup returned0"})
	cell_committed.emit(int(job.id),Vector2i(step.source))
	changed.emit()

func advance(now: int) -> void:
	# 410B20 first advances the shared sprite pool once, then the ordered actor jobs.
	for job in jobs.values():
		if job.active: job.player.advance(now)
	for job in jobs.values():
		if not job.active: continue
		if job.player.busy: continue
		var old_step: Dictionary = job.steps[int(job.index)]
		job.world = Vector2i(old_step.destination)
		cell_committed.emit(int(job.id),Vector2i(old_step.destination))
		job.index = int(job.index)+1
		if int(job.index) < job.steps.size():
			_start_step(job,now)
		else:
			job.active = false
			if job.path: job.player.offset = Vector2i.ZERO
			job.sort_world = job.world
			finished.emit(int(job.id))
			changed.emit()

func is_busy(id: int) -> bool:
	return jobs.has(id) and bool(jobs[id].active)

func snapshots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for job in jobs.values():
		out.append({"id":int(job.id),"stem":str(job.stem),"label":str(job.steps[mini(int(job.index),job.steps.size()-1)].label),
			"world":Vector2i(job.world),"sort_world":Vector2i(job.sort_world),"player_override":job.player,
			"externally_advanced":true,"metadata":job.metadata,"visible":true,
			"job_shadow_follow":bool(job.active) or not bool(job.path),"job_direction":int(job.steps[mini(int(job.index),job.steps.size()-1)].direction)})
	return out

func clear(id: int = -1) -> void:
	if id < 0: jobs.clear()
	else: jobs.erase(id)

func _prepare_sound(event_id: int) -> void:
	if _sounds.has(event_id): return
	var stem := "EVENT%02d" % event_id
	var exists := FT2Content.exists(data.resolve("data/port_ready/assets/audio/wave/"+stem+".wav"))
	_sounds[event_id] = exists
	optional_sound_attempts.append({"source":"WAVE/"+stem+".WAV","loaded":exists,"scope":"Source411940 optional sound-cache lookup; supplied original contains no eventNN files"})

func _sound_event(event_id: int,_indirect: bool,_marker: int) -> void:
	if event_id >= 0 and bool(_sounds.get(event_id,false)): sound_requested.emit("EVENT%02d" % event_id,false)
