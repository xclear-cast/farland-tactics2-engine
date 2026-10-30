extends SceneTree
## Own unit records and explicit cleanup truth tables; no original saves/assets.
const VM=preload("res://scripts/scenario/ft2_vm.gd")
class OwnBattle:
	extends RefCounted
	var units: Array=[]
class OwnJobs:
	extends RefCounted
	var cleared: Array=[]
	func clear(slot: int) -> void:cleared.append(slot)
	func snapshots() -> Array:return []
var checks:=0
var failures: Array[String]=[]
var output:=""
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func record(kind: int,hp: int,state: int,seed: int) -> PackedByteArray:
	var bytes:=PackedByteArray();bytes.resize(124)
	for i in bytes.size():bytes[i]=(i*13+seed)%256
	bytes.encode_u16(0,kind);bytes.encode_u16(16,state);bytes.encode_u16(38,hp&65535)
	return bytes
func fixture(kind: int,hp: int,state: int,slot: int=10,count: int=50) -> Dictionary:
	var vm=VM.new();var battle=OwnBattle.new();vm.battle=battle;vm.jobs=OwnJobs.new()
	for i in count:battle.units.append(record(1,20,0,i+1))
	battle.units[slot]=record(kind,hp,state,197)
	vm.actor_sprites[slot]={"id":slot,"own":true};vm.actor_busy[slot]=true
	return {"vm":vm,"before":battle.units.duplicate(true),"slot":slot}
func expect(f: Dictionary,remove: bool,label: String) -> void:
	var expected: Array=f.before.duplicate(true)
	if remove:
		var empty:=PackedByteArray();empty.resize(124);empty.fill(0);expected[f.slot]=empty
	f.vm._system(12,[])
	check(f.vm.battle.units==expected,label)
func run() -> void:
	# These species are eligible; the unusual positive-HP state1 case is retained.
	for kind in [8,24,31,65535]:
		for row in [[0,0,true],[0,1,true],[12,0,true],[12,1,false],[12,9,true],[65535,0,true],[65535,1,false]]:
			expect(fixture(kind,row[0],row[1]),row[2],"kind%d HP%d state%d exact bytes and unaffected neighboring records"%[kind,row[0],row[1]])
	# Ordinary NPC/party kinds are ineligible even when their health is zero.
	for kind in [0,1,7,9,23,25,30]:
		for row in [[0,0],[0,1],[12,0]]:expect(fixture(kind,row[0],row[1]),false,"ordinary kind%d HP%d state%d remains intact"%[kind,row[0],row[1]])
	for row in [[0,false],[9,false],[10,true],[49,true],[50,false]]:
		expect(fixture(8,12,0,row[0],51),row[1],"source NPC range includes10..49 only: slot%d"%row[0])
	var removed:=fixture(8,12,0);removed.vm._system(12,[])
	check(not removed.vm.actor_sprites.has(10) and not removed.vm.actor_busy.has(10) and removed.vm.jobs.cleared==[10],"removed Unit releases current script/job ownership once")
	var kept:=fixture(24,12,1);kept.vm._system(12,[])
	check(kept.vm.actor_sprites.has(10) and kept.vm.actor_busy.has(10) and kept.vm.jobs.cleared.is_empty(),"retained state1 with nonzeroHP preserves its resource/job ownership")
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored 124-byte patterns and explicit kind/HP/state/slot truth table"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cleanup-output="):output=arg.trim_prefix("--cleanup-output=")
	call_deferred("run")
