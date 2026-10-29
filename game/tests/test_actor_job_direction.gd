extends SceneTree
## Own APD steps and unit bytes only. No original resources or dialogue.
const Jobs=preload("res://scripts/scenario/ft2_actor_jobs.gd")
const VM=preload("res://scripts/scenario/ft2_vm.gd")
class SyntheticData:
	extends RefCounted
	var requested: Array[String]=[]
	var dataset:={"name":"SYNTHETIC_ACTOR","animations":{"F.SYNTHETIC":{"groups":[{"move":[24,-12],"velocity":[0.125,-0.0625],"steps":[[0,64,0,-1,0,0],[1,64,0,-1,0,0],[2,64,0,-1,0,0]]}],"duration":192}}}
	func load_apd(stem: String) -> Dictionary:
		requested.append(stem)
		return dataset.duplicate(true)
class SyntheticBattle:
	extends RefCounted
	var units: Array[PackedByteArray]=[]

var output:=""
var checks:=0
var failures: Array[String]=[]

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--direction-output="):output=arg.trim_prefix("--direction-output=")
	call_deferred("run")

func run() -> void:
	var data:=SyntheticData.new()
	var dataset_before:=JSON.stringify(data.dataset)
	var expected_flags:=[1,17,17,1]
	var vectors: Array=[]
	for direction in 4:
		var jobs=Jobs.new(data)
		var metadata:={"nested":{"value":7},"tags":[1,2]}
		var metadata_before:=metadata.duplicate(true)
		var start:=Vector2i(9,11)
		check(jobs.play_single(42,"SYNTHETIC_ACTOR",start,"F.SYNTHETIC",1000,metadata,direction),"single action starts for direction "+str(direction))
		var job: Dictionary=jobs.jobs[42]
		var step: Dictionary=job.steps[0]
		check(step.flags==expected_flags[direction]and step.direction==direction,"direction flags match native vector "+str(direction))
		check(step.label=="F.SYNTHETIC"and job.player.label=="F.SYNTHETIC","explicit action label is preserved "+str(direction))
		check(job.player.mirror==(direction in [1,2]),"horizontal mirror follows direction only "+str(direction))
		check(step.source==start and step.destination==start and job.world==start,"single action keeps logical cell "+str(direction))
		jobs.advance(1000);jobs.advance(1064)
		var expected:=Vector2i(-8 if direction in [1,2]else 8,-4)
		check(job.player.offset==expected,"authored positive-X motion has expected mirrored sign "+str(direction))
		check(job.player.effective_flip()==(1 if direction in [1,2]else 0),"raster orientation matches motion mirror "+str(direction))
		check(metadata==metadata_before,"play does not mutate caller metadata "+str(direction))
		metadata.nested.value=999
		check(job.metadata.nested.value==7,"stored nested metadata owns a deep copy "+str(direction))
		job.metadata.tags.append(3)
		check(metadata.tags==[1,2],"job metadata mutation cannot change caller "+str(direction))
		check(jobs.errors.is_empty(),"synthetic label lookup has no errors "+str(direction))
		vectors.append({"direction":direction,"flags":int(step.flags),"offset":[job.player.offset.x,job.player.offset.y]})
	var compatible=Jobs.new(data)
	check(compatible.play_single(1,"SYNTHETIC_ACTOR",Vector2i.ZERO,"F.SYNTHETIC",2000),"previous play_single signature remains compatible")
	check(compatible.jobs[1].steps[0].direction==4 and compatible.jobs[1].steps[0].flags==1,"omitted direction defaults to neutral direction4")
	compatible.advance(2000);compatible.advance(2064)
	check(compatible.jobs[1].player.offset==Vector2i(8,-4),"default direction preserves authored positive-X movement")
	check(JSON.stringify(data.dataset)==dataset_before,"animation playback never mutates source fixture")
	check(data.requested.size()==5 and data.requested.all(func(stem):return stem=="SYNTHETIC_ACTOR"),"all directions preserve the requested APD resource")
	# Execute the real VM SYSTEM26 handler with a genuine unit+06 direction field.
	# Null-data construction deliberately avoids all resource loading in VM init.
	for direction in 4:
		var battle:=SyntheticBattle.new()
		var unit:=PackedByteArray();unit.resize(124);unit.fill(0)
		unit.encode_u16(0,1);unit.encode_u16(2,5);unit.encode_u16(6,direction)
		unit.encode_u32(8,9);unit.encode_u32(12,11);battle.units.append(unit)
		var vm=VM.new();vm.battle=battle;vm.jobs=Jobs.new(data)
		vm.actor_sprites[0]={"stem":"SYNTHETIC_ACTOR","nested":{"value":7}}
		var actor_before: Dictionary=vm.actor_sprites.duplicate(true)
		vm.now_ms=3000
		check(not vm._system(26,[0,"F.SYNTHETIC"]),"SYSTEM26 dispatch does not synthesize a script wait "+str(direction))
		check(vm.jobs.jobs[0].steps[0].direction==direction and vm.jobs.jobs[0].steps[0].flags==expected_flags[direction],"SYSTEM26 forwards unit direction to actual actor jobs "+str(direction))
		check(vm.jobs.jobs[0].steps[0].label=="F.SYNTHETIC"and vm.actor_busy.get(0,false),"SYSTEM26 preserves label and records busy state "+str(direction))
		vm.jobs.advance(3000);vm.jobs.advance(3064)
		check(vm.jobs.jobs[0].player.offset==Vector2i(-8 if direction in [1,2]else 8,-4),"SYSTEM26 mirror affects actual APD movement "+str(direction))
		check(vm.actor_sprites==actor_before and battle.units[0]==unit,"SYSTEM26 preserves actor metadata and unit bytes "+str(direction))
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"vectors":vectors,"fixtures":"self-authored positive-X APD animation and unit bytes"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
