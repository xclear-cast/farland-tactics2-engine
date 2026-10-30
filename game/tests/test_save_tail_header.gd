extends SceneTree
## Own town rows and scalar patterns only; no installation or save file required.
const Town=preload("res://scripts/scenario/ft2_town.gd")

class SyntheticTownData:
	extends RefCounted
	func read_json(_path: String) -> Dictionary:
		var rows: Array=[]
		for index in 20:rows.append({"index":index,"label":"OWN_%02d"%index,"hit_rect":[index*3,0,index*3+2,2],"marker_rect":[index*3,0,index*3+2,2]})
		return {"static_table":{"rows":rows}}

var checks:=0
var failures: Array[String]=[]
var output:=""

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-tail-output="):output=arg.trim_prefix("--save-tail-output=")
	call_deferred("run")

func run() -> void:
	var owner:=RefCounted.new();var data:=SyntheticTownData.new();var town=Town.new(owner,data)
	var empty: PackedByteArray=town.snapshot()
	check(empty.size()==180,"default tail has exactly180 bytes")
	check(empty.decode_u32(0)==180,"first DWORD contains the serialized town structure size")
	var expected:=PackedByteArray();expected.resize(180);expected.fill(0);expected.encode_u32(0,180)
	check(empty==expected,"a new town serializes the size header followed by zero state")
	# Distinct words expose offset/array-order mistakes, including signed masks.
	town.display_markers=-1;expected.encode_u32(4,0xFFFFFFFF)
	for index in 20:
		town.markers[index]=-2147483648+index*19
		town.set_flag(index,0x10203040+index*257)
		expected.encode_u32(8+index*4,(-2147483648+index*19)&0xFFFFFFFF)
		expected.encode_u32(88+index*4,0x10203040+index*257)
	town.set_flag(20,-2147483648);town.set_flag(21,0x76543210);town.set_flag(22,-1)
	expected.encode_u32(168,0x80000000);expected.encode_u32(172,0x76543210);expected.encode_u32(176,0xFFFFFFFF)
	var serialized: PackedByteArray=town.snapshot()
	check(serialized.size()==180 and serialized==expected,"complete tail matches the independently constructed exact180-byte layout")
	check(serialized.decode_u32(4)==0xFFFFFFFF,"display marker DWORD is at offset4")
	for index in 20:
		check(serialized.decode_u32(8+index*4)==((-2147483648+index*19)&0xFFFFFFFF),"marker%d is at offset%d"%[index,8+index*4])
		check(serialized.decode_u32(88+index*4)==0x10203040+index*257,"enabled flag%d is at offset%d"%[index,88+index*4])
	check(serialized.decode_u32(168)==0x80000000 and serialized.decode_u32(172)==0x76543210 and serialized.decode_u32(176)==0xFFFFFFFF,"three final mode/overlay words occupy offsets168/172/176")
	var restored=Town.new(owner,data);restored.counter=11;restored.pulse=13
	var input_before: PackedByteArray=serialized.duplicate()
	restored.restore(serialized)
	check(serialized==input_before,"restore does not modify its input byte array")
	check(restored.snapshot()==expected,"restore followed by snapshot reproduces all180 bytes exactly")
	check(restored.counter==0 and restored.pulse==0,"restore retains existing transient control-timer reset semantics")
	serialized[8]=serialized[8]^255
	check(restored.snapshot()==expected,"restored scalar state does not alias the caller's input buffer")
	var snapshot_before: PackedByteArray=restored.snapshot();restored.markers[0]=1234;restored.enabled[19]=5678
	check(snapshot_before==expected,"later state edits do not mutate a previously returned snapshot")
	var untouched: PackedByteArray=restored.snapshot();var short:=PackedByteArray();short.resize(179);short.fill(231)
	var short_before: PackedByteArray=short.duplicate();restored.restore(short)
	check(restored.snapshot()==untouched and short==short_before,"a truncated tail is ignored without changing state or input")
	# Each supported control choice round-trips without leaking transient fields.
	for mode in [1,2,3]:
		var choice=Town.new(owner,data);choice.get_control_mode(mode);choice.set_flag(21,mode*17)
		var bytes: PackedByteArray=choice.snapshot();var copy=Town.new(owner,data);copy.restore(bytes)
		check(copy.snapshot()==bytes and copy.get_control_mode(0)==mode,"control mode%d round-trips with a valid size header"%mode)
	var before_flags: PackedByteArray=town.snapshot();town.set_flag(-1,99);town.set_flag(23,99)
	check(town.snapshot()==before_flags,"out-of-range flag writes do not overwrite the size/header or adjacent modes")
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored town rows and scalar patterns; no game assets or original saves"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
