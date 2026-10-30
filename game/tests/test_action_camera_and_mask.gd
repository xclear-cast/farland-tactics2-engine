extends SceneTree
const Battle=preload("res://scripts/logic/ft2_battle.gd")
const Navigation=preload("res://scripts/logic/ft2_navigation.gd")
const View=preload("res://scripts/render/ft2_battle_view.gd")
class Rules:
	extends RefCounted
	const INCAP=[1,3,4,5,8,9]
	var items:=PackedByteArray()
	var magics:=PackedByteArray()
	func _init() -> void:
		items.resize(112);items.fill(0);items.encode_u16(56+42,1);items.encode_u16(56+44,1)
		magics.resize(320);magics.fill(0)
	func xy(u:PackedByteArray)->Vector2i:return Vector2i(u.decode_s32(8),u.decode_s32(12))
	func copy_units(rows:Array)->Array:
		var out:Array=[]
		for u in rows:out.append(u.duplicate())
		return out
	func bag_count(_inventory:PackedByteArray,id:int)->int:return 1 if id==1 else 0
	func hostile(_a:PackedByteArray,_b:PackedByteArray,same:bool)->bool:return not same
class Nav:
	extends RefCounted
	var units:Array=[]
	var grid:Dictionary={}
	var origin:=Vector2i.ZERO
	var events:Array=[]
	func movement_grid(slot:int)->Dictionary:
		origin=Vector2i(units[slot].decode_s32(8),units[slot].decode_s32(12));grid={};return grid
	func selection_mask(_slot:int,_action:int)->Dictionary:events.append("mask");return {}
class Model:
	extends FT2Battle
	var flags:={"magic_parent":true,"items_parent":true}
	var spells:Array=[{"action_id":1,"enabled":true},{"action_id":2,"enabled":true}]
	var events:Array=[]
	func menu_flags(_slot:int=-1)->Dictionary:return flags
	func available_magic(_slot:int=-1)->Array:return spells
	func select_cell(point:Vector2i)->bool:events.append({"kind":"self_confirm","point":point});return true
class Data:
	extends RefCounted
	func decode_unit(u:PackedByteArray,_slot:int)->Dictionary:return {"x":u.decode_s32(8),"y":u.decode_s32(12)}
var checks:=0
var failures:Array[String]=[]
var output:=""
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func unit(kind:int,point:Vector2i)->PackedByteArray:
	var u:=PackedByteArray();u.resize(124);u.fill(0);u.encode_u16(0,kind);u.encode_s32(8,point.x);u.encode_s32(12,point.y);u.encode_u16(20,1);return u
func run()->void:
	var b=Model.new();b.rules=Rules.new();b.navigation=Nav.new();b.selected_slot=0;b.units=[unit(1,Vector2i(18,14))]
	var v=View.new();v.data=Data.new();v.battle=b;v.map={"base":[1024,0]};v._baked={"width":1800,"height":1000};v.camera=Vector2i(16,16)
	var events:Array=[]
	var cb=func(request):events.append({"request":request.duplicate(),"substate_before":b.substate,"mask_prepared":not b.navigation.events.is_empty()});v.request_camera(request);b.events.append({"kind":"actor_camera"})
	b.camera_requested.connect(cb)
	var original=b.snapshot_units()
	check(b.choose_action(1),"valid own magic action is accepted")
	check(events.size()==1 and events[0].request.get("kind")=="actor" and events[0].request.get("slot")==0,"magic selection requests the actual actor camera")
	check(v.camera==Vector2i(832,272),"magic selection centers through actual view projection")
	check(events.size()==1 and events[0].mask_prepared and events[0].substate_before==0,"range preparation precedes camera and camera precedes substate3")
	check(b.substate==3 and b.units==original,"magic target selection preserves unit data")
	v.camera=Vector2i.ZERO;b.substate=0
	check(b.choose_action(1001) and b.substate==4,"available own item action is accepted")
	check(events.size()==2 and v.camera==Vector2i(832,272),"item selection independently centers before target selection")
	b.substate=0;b.rules.magics.encode_u16(2*64+50,3);b.events.clear()
	check(b.choose_action(2),"self-confirm shape3 action is accepted")
	check(b.events.size()==2 and b.events[0].kind=="actor_camera" and b.events[1].kind=="self_confirm","actor center precedes existing immediate self-confirm flow")
	var count=events.size();b.substate=0
	check(b.choose_action(0) and events.size()==count,"ordinary physical selection does not add a duplicate actor-center event")
	check(not b.choose_action(9) and not b.choose_action(1002) and events.size()==count,"invalid or unowned action identifiers do not center")
	b.flags.magic_parent=false
	check(not b.choose_action(1) and events.size()==count,"disabled magic does not center")
	b.flags.magic_parent=true;b.spells[0].enabled=false
	check(not b.choose_action(1) and events.size()==count,"insufficient-MP magic does not center")
	b.phase="enemy"
	check(not b.choose_action(1001) and events.size()==count,"enemy phase rejects action selection without camera effects")
	b.phase="player";b.flags.items_parent=false
	check(not b.choose_action(1001) and events.size()==count,"disabled item action does not center")
	# Use the actual navigation range picker, not the lightweight camera fixture.
	var nav=Navigation.new(b.rules);var actor=unit(1,Vector2i(5,5));var target=unit(8,Vector2i(6,5));target.encode_u16(18,1)
	nav.units=[actor,target];nav.cells[Vector2i(5,5)]=[0,0,0,1,1];nav.cells[Vector2i(6,5)]=[0,0,0,1,1]
	check(nav.selection_mask(0,0).has(Vector2i(1,0)),"unused physical action includes its legal adjacent enemy")
	actor.encode_s32(96,1)
	check(nav.selection_mask(0,0).is_empty(),"an already used action produces no physical target mask during remaining movement")
	actor.encode_s32(92,1);actor.encode_s32(96,0)
	check(nav.selection_mask(0,0).has(Vector2i(1,0)),"move-used but action-unused units still retain physical targets")
	b.camera_requested.disconnect(cb);v.free()
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored action tables, units and map cells; no original resources"}
	if output!="":
		DirAccess.make_dir_recursive_absolute(output)
		var f:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--action-camera-output="):output=arg.trim_prefix("--action-camera-output=")
	call_deferred("run")
