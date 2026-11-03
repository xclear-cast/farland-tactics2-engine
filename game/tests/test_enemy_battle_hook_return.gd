extends SceneTree
const Battle=preload("res://scripts/logic/ft2_battle.gd")

class OwnData:
	extends RefCounted
	func raw_table(name:String)->PackedByteArray:
		var b:=PackedByteArray();b.resize(172 if name=="race" else 128 if name=="magic" else 112);b.fill(0)
		if name=="race":
			for i in 2:
				b.encode_u16(i*86+58,4);b.encode_u16(i*86+60,4);b.encode_u16(i*86+62,99)
				for terrain in range(1,8):b.encode_u16(i*86+62+terrain*2,4)
		elif name=="item":b.encode_u16(56+42,1);b.encode_u16(56+44,1)
		else:
			b.encode_u16(64+22,1);b.encode_u16(64+30,1);b.encode_u16(64+32,5)
		return b

class CountingAI:
	extends RefCounted
	var nav
	var style:="magic"
	var calls:Dictionary={}
	func _init(navigation,kind:String)->void:nav=navigation;style=kind
	func decision(slot:int)->Dictionary:
		calls[slot]=int(calls.get(slot,0))+1
		nav.movement_grid(slot)
		var u:PackedByteArray=nav.units[slot];var point:Vector2i=nav.rules.xy(u)
		var target:Vector2i=nav.rules.xy(nav.units[0])
		if style=="noop":return {"position":point,"action_id":0,"target":target,"has_action":false}
		if u.decode_s32(96)!=0:return {"position":point+Vector2i(0,1),"action_id":0,"target":target,"has_action":false}
		if style=="move_then_cast" and u.decode_s32(92)==0:return {"position":point+Vector2i(1,0),"action_id":1,"target":target,"has_action":true}
		return {"position":point,"action_id":0 if style=="physical" else 1,"target":target,"has_action":true}

class BoundaryVM:
	extends "res://scripts/scenario/ft2_vm.gd"
	var successful_target_slot:=-1
	var attempts:Array=[]
	func start(event_id:int,label:String="begin")->bool:
		var target:=int(_hook.get("target_slot",-1))
		var loaded:=target==successful_target_slot
		attempts.append({"event_id":event_id,"label":label,"target_slot":target,"loaded":loaded})
		return loaded

class Model:
	extends FT2Battle
	var commits:Array=[]
	var defer_finish:=false
	# Numeric/animation work is outside this scheduler regression. This adapter
	# supplies the dispatch-complete marker boundary without assets or random rolls.
	func _commit_numeric()->void:
		var point:Vector2i=rules.xy(units[selected_slot])
		for direction in path:point+=navigation.DIRS[int(direction)]
		rules.set_xy(units[selected_slot],point)
		if not path.is_empty():units[selected_slot].encode_u32(92,1)
		if not _preview.records.is_empty():units[selected_slot].encode_u32(96,1)
		commits.append({"slot":selected_slot,"cell":point,"action":action_id,"records":_preview.records.size(),"path":path.duplicate()})
		if defer_finish:_set_phase("post_action")
		else:_complete_action()

var checks:=0
var failures:Array[String]=[]
var output:=""
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label)
func unit(kind:int,control:int,point:Vector2i)->PackedByteArray:
	var b:=PackedByteArray();b.resize(124);b.fill(0);b.encode_u16(0,kind);b.encode_u16(2,1);b.encode_u16(4,2);b.encode_u16(6,0);b.encode_s32(8,point.x);b.encode_s32(12,point.y);b.encode_u16(18,control);b.encode_u16(20,1);b.encode_u16(36,100);b.encode_u16(38,100);b.encode_u16(40,20);b.encode_u16(42,20);return b
func map_data()->Dictionary:
	var cells:Array=[]
	for x in range(10,40):
		for y in range(10,30):cells.append({"x":x,"y":y,"H":0,"L":1,"flag2_raw":0,"flag3_raw":0,"part_count":0})
	return {"cells":cells,"header_map_bounds_ltrb":[0,20,50,20]}
func fixture(style:String,loaded:bool,immediate:bool=false)->Dictionary:
	var b:=Model.new(OwnData.new());b.units[0]=unit(1,0,Vector2i(22,20));b.units[10]=unit(2,6,Vector2i(21 if style=="physical" else 20,20));b.navigation.configure(b.units,map_data(),1)
	var ai:=CountingAI.new(b.navigation,style);b.ai=ai;b.enemy_cursor=10;b.substate=7;b.phase="enemy"
	var f:Dictionary={"battle":b,"ai":ai,"loaded":loaded,"immediate":immediate,"pending":[],"requests":[]}
	var cb:=Callable(self,"hook").bind(f);b.hook_requested.connect(cb);f.callback=cb;return f
func hook(request:Dictionary,f:Dictionary)->void:
	var b=f.battle;var loaded:=bool(f.loaded)
	if f.has("loaded_target_slot"):loaded=int(request.get("target_slot",-1))==int(f.loaded_target_slot)
	f.requests.append({"request":request.duplicate(),"stage":b._hook_stage,"slot":b.selected_slot,"loaded":loaded})
	if loaded:
		b.hook_started() # The original loader succeeded, even for an immediate return.
		if bool(f.immediate):b.resume_hook(true)
		else:f.pending.append(request.duplicate())
	else:b.resume_hook(false)
func drive(f:Dictionary,budget:int=12)->void:
	var b=f.battle
	for ignored in budget:
		if not f.pending.is_empty():f.pending.pop_front();b.resume_hook(true)
		elif b.phase=="enemy":b._enemy_update()
		else:break
func dispose(f:Dictionary)->void:
	f.battle.hook_requested.disconnect(f.callback);f.pending.clear();f.requests.clear();f.battle.ai=null;f.clear()
func initial_hook_case(style:String,immediate:bool)->void:
	var f:=fixture(style,true,immediate);var b=f.battle;var origin:Vector2i=b.rules.xy(b.units[10]);drive(f)
	check(f.ai.calls.get(10,0)==1,"loaded initial BATTLE prevents a second "+style+" AI pass (immediate="+str(immediate)+")")
	check(b.rules.xy(b.units[10])==origin,"loaded BATTLE does not add movement after standing "+style)
	check(b.commits.size()==1 and b.units[10].decode_s32(92)==0 and b.units[10].decode_s32(96)==1,"standing "+style+" keeps the original move/action markers")
	check(f.requests.size()==1,"loaded initial BATTLE stops the ordered lookup")
	dispose(f)
func later_hook_case(stage:String)->void:
	var f:=fixture("magic",false);var b=f.battle;b.defer_finish=true;b._enemy_update()
	check(b.phase=="post_action" and b.units[10].decode_s32(96)==1,"missing initial BATTLE dispatches standing magic before later "+stage)
	# Drive the real hook notification/resume API at a later controller stage.
	f.loaded=true;b._hook_stage=stage;b._hook_groups=[[{"event_id":0,"label":"own_post","kind":"after"if stage=="after"else"terminal"}]];b._hook_group=0;b._hook_alternative=0;b._advance_hook();f.pending.pop_front();b.resume_hook(true);b._complete_action()
	check(b.enemy_cursor==10,"later "+stage+" hook does not suppress the earlier caller's eligible rewind")
	dispose(f)
func vm_boundary_case()->void:
	var f:=fixture("magic",false);var b=f.battle
	b.units[1]=unit(3,0,Vector2i(20,22));b.navigation.configure(b.units,map_data(),1)
	b.rules.magics.encode_u16(64+30,0);b.rules.magics.encode_u16(64+32,3);b.rules.magics.encode_u16(64+50,3)
	b.hook_requested.disconnect(f.callback)
	var vm:=BoundaryVM.new();vm.battle=b;vm.current_event=3;vm.successful_target_slot=1
	f.callback=Callable(vm,"_on_hook");b.hook_requested.connect(f.callback)
	b._enemy_update()
	check(vm.attempts.size()==2 and vm.attempts[0].target_slot==0 and not vm.attempts[0].loaded and vm.attempts[1].target_slot==1 and vm.attempts[1].loaded,"real VM hook callback retries a failed first target and loads the later BATTLE")
	check(not b._enemy_direct_return and b.phase=="event" and b._waiting_hook,"successful VM.start synchronously reaches hook_started before the loaded script resumes")
	b.resume_hook(true)
	check(b.phase=="enemy" and f.ai.calls.get(10,0)==1 and b.commits.size()==1,"later successful BATTLE stops target search and prevents a second AI decision after script completion")
	dispose(f);vm.battle=null
func write_report_if_requested(result:Dictionary)->void:
	var destination:=output.strip_edges()
	if destination.is_empty(): return
	destination=ProjectSettings.globalize_path(destination)
	if not DirAccess.dir_exists_absolute(destination):
		var make_error:=DirAccess.make_dir_recursive_absolute(destination)
		if make_error!=OK and not DirAccess.dir_exists_absolute(destination):
			push_warning("Could not create enemy hook report directory: "+destination)
			return
	var path:=destination.path_join("result.json")
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		push_warning("Could not open enemy hook report for writing: "+path)
		return
	file.store_string(JSON.stringify(result,"\t"));file.close()
func run()->void:
	for style in["magic","physical"]:
		initial_hook_case(style,false);initial_hook_case(style,true)
	var missing:=fixture("magic",false);drive(missing)
	check(missing.ai.calls.get(10,0)==2,"missing BATTLE preserves the source caller's follow-up movement")
	check(missing.battle.rules.xy(missing.battle.units[10])==Vector2i(20,21),"unhandled standing action can still finish its movement")
	dispose(missing)
	var multi:=fixture("magic",false);multi.battle.units[1]=unit(3,0,Vector2i(20,22));multi.battle.navigation.configure(multi.battle.units,map_data(),1);multi.battle.rules.magics.encode_u16(64+30,0);multi.battle.rules.magics.encode_u16(64+32,3);multi.battle.rules.magics.encode_u16(64+50,3);drive(multi)
	check(multi.requests.size()==2,"all failed BATTLE target lookups run before ordinary dispatch")
	check(multi.ai.calls.get(10,0)==2,"all lookup failures retain the caller-return rewind")
	dispose(multi)
	var partial:=fixture("magic",false);partial.battle.units[1]=unit(3,0,Vector2i(20,22));partial.battle.navigation.configure(partial.battle.units,map_data(),1);partial.battle.rules.magics.encode_u16(64+30,0);partial.battle.rules.magics.encode_u16(64+32,3);partial.battle.rules.magics.encode_u16(64+50,3);partial.loaded_target_slot=1;drive(partial)
	check(partial.requests.size()==2 and int(partial.requests[0].request.target_slot)==0 and not partial.requests[0].loaded and int(partial.requests[1].request.target_slot)==1 and partial.requests[1].loaded,"a later target's successful BATTLE follows a failed first target lookup")
	check(partial.ai.calls.get(10,0)==1 and partial.battle.commits.size()==1,"partial target search stops on its first loaded BATTLE without retrying the AI")
	dispose(partial)
	var moved:=fixture("move_then_cast",true);drive(moved)
	check(moved.ai.calls.get(10,0)==2 and moved.battle.commits.size()==2,"move-only displacement still replans its following cast")
	check(moved.battle.commits[0].action==0 and moved.battle.commits[0].records==0 and moved.battle.commits[1].action==1,"follow-up retains move-only then magic ordering")
	check(moved.battle.units[10].decode_s32(92)==1 and moved.battle.units[10].decode_s32(96)==1,"move and cast each consume their own markers")
	dispose(moved)
	var idle:=fixture("noop",true);drive(idle)
	check(idle.ai.calls.get(10,0)==1 and idle.battle.commits.is_empty(),"no-op decision neither dispatches nor retries")
	dispose(idle)
	later_hook_case("after");later_hook_case("terminal")
	vm_boundary_case()
	var successive:=fixture("magic",true);successive.battle.units[11]=unit(4,6,Vector2i(20,22));var cb=successive.callback;successive.battle.hook_requested.disconnect(cb)
	var per_slot:=func(req):successive.loaded=successive.battle.selected_slot==10;hook(req,successive)
	successive.battle.hook_requested.connect(per_slot);successive.callback=per_slot;drive(successive,20)
	check(successive.ai.calls.get(10,0)==1 and successive.ai.calls.get(11,0)==2,"loaded-hook eligibility does not leak into the next NPC action")
	dispose(successive)
	var result:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Self-authored enemy scheduler/caller-return fixtures, no original game data or assets."}
	write_report_if_requested(result)
	print(JSON.stringify(result));quit(0 if failures.is_empty() else 1)
func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--enemy-hook-return-output="):output=arg.trim_prefix("--enemy-hook-return-output=")
	call_deferred("run")
