extends SceneTree
## Own unit/map fixtures: Source WM_COMMAND102 centers before saving move origin.
const Battle=preload("res://scripts/logic/ft2_battle.gd")
const View=preload("res://scripts/render/ft2_battle_view.gd")
class OwnRules:
	extends RefCounted
	const INCAP=[1,3,4,5,8,9]
	func xy(raw: PackedByteArray) -> Vector2i:return Vector2i(raw.decode_s32(8),raw.decode_s32(12))
	func copy_units(rows: Array) -> Array:
		var result: Array=[]
		for row in rows:result.append(row.duplicate())
		return result
class OwnNavigation:
	extends RefCounted
	var units: Array=[]
	var origin:=Vector2i.ZERO
	var grid: Dictionary={}
	func movement_grid(slot: int) -> Dictionary:
		origin=Vector2i(units[slot].decode_s32(8),units[slot].decode_s32(12));grid={Vector2i.ZERO:10};return grid
	func selection_mask(_slot: int,_action: int) -> Dictionary:return {}
	func selectable(_point: Vector2i,_mask: Dictionary) -> bool:return true
class OwnData:
	extends RefCounted
	func decode_unit(raw: PackedByteArray,_slot: int) -> Dictionary:return {"x":raw.decode_s32(8),"y":raw.decode_s32(12)}
var checks:=0
var failures: Array[String]=[]
var output:=""
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func unit(kind: int,point: Vector2i) -> PackedByteArray:
	var raw:=PackedByteArray();raw.resize(124);raw.fill(0)
	raw.encode_u16(0,kind);raw.encode_u16(6,3);raw.encode_s32(8,point.x);raw.encode_s32(12,point.y)
	return raw
func run() -> void:
	var battle=Battle.new();battle.rules=OwnRules.new();battle.navigation=OwnNavigation.new()
	battle.units=[unit(1,Vector2i(18,14)),unit(2,Vector2i(31,25)),unit(0,Vector2i.ZERO)]
	var view=View.new();view.data=OwnData.new();view.battle=battle
	view.map={"base":[1024,0]};view._baked={"width":1800,"height":1000};view.camera=Vector2i(16,16)
	var events: Array=[]
	var callback=func(request):
		events.append({"request":request.duplicate(true),"origin_before":battle.rollback_origin})
		view.request_camera(request)
	battle.camera_requested.connect(callback)
	battle.rollback_origin=Vector2i(-7,-9)
	var before=battle.snapshot_units()
	check(battle.select_unit(0),"normal movable party selection succeeds")
	check(events.size()==1 and events[0].request.get("kind")=="actor" and events[0].request.get("slot")==0,"accepted selection requests the selected actor camera once")
	check(view.camera==Vector2i(832,272),"actual view centers the selected unit from an unrelated previous camera")
	check(events.size()==1 and events[0].origin_before==Vector2i(-7,-9),"camera callback precedes the source rollback-origin capture")
	check(battle.rollback_origin==Vector2i(18,14) and battle.rollback_facing==3 and battle.substate==1,"selection still captures the real move origin and enters substate1")
	check(battle.snapshot_units()==before,"camera acquisition does not modify unit records")
	battle.phase="enemy"
	check(not battle.select_unit(0) and events.size()==1,"non-player phase rejects selection without centering")
	battle.phase="player"
	check(not battle.select_unit(-1) and not battle.select_unit(50) and not battle.select_unit(2) and events.size()==1,"invalid and empty slots produce no camera request")
	battle.units[0].encode_u16(16,1)
	check(not battle.select_unit(0) and events.size()==1,"incapacitated units produce no camera request")
	battle.units[0].encode_u16(16,0);battle.units[0].encode_u16(18,1)
	check(not battle.select_unit(0) and events.size()==1,"non-party units produce no movement-selection camera request")
	battle.units[0].encode_u16(18,0);battle.units[0].encode_s32(92,1);battle.units[0].encode_s32(96,1)
	check(not battle.select_unit(0) and events.size()==1,"a unit with both actions consumed is rejected without centering")
	check(battle.select_unit(1) and view.camera==Vector2i(896,520),"a second actor request uses actual map camera clamping")
	check(events.size()==2 and events[-1].request.slot==1,"reselection requests the new actor rather than retaining the first")
	battle.units[0].encode_s32(92,0);battle.units[0].encode_s32(96,0);view._cells[Vector2i(18,14)]=[0,0,4]
	check(battle.select_unit(0) and view.camera==Vector2i(832,240),"selection uses the actual selected tile elevation")
	check(events.size()==3,"each successful selection produces one synchronous camera request")
	battle.camera_requested.disconnect(callback);view.free()
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored units, navigation masks, map bounds and elevations; no original data"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--selection-camera-output="):output=arg.trim_prefix("--selection-camera-output=")
	call_deferred("run")
