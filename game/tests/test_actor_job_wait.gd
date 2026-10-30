extends SceneTree
## Self-authored state1 lifetime vs state2 wait contracts; original data absent.
const View=preload("res://scripts/render/ft2_battle_view.gd")
const VM=preload("res://scripts/scenario/ft2_vm.gd")
const Jobs=preload("res://scripts/scenario/ft2_actor_jobs.gd")
class RecordingView extends View:
	var draws: Array=[]
	var refresh_calls: Array=[]
	func source_refresh_actor(slot: int,release_first: bool=false,source_mode: int=-1) -> Dictionary:
		var result=super.source_refresh_actor(slot,release_first,source_mode);refresh_calls.append({"slot":slot,"release_first":release_first,"result":result});return result
	func _draw_apd(player: FT2APDPlayer,anchor: Vector2i,policy: String="actor",clip: Rect2i=Rect2i(0,0,640,480),remaps: Variant=null,installs: Array=[]) -> Rect2i:
		draws.append({"player":player,"anchor":anchor,"label":player.label,"policy":policy});return super._draw_apd(player,anchor,policy,clip,remaps,installs)
	func _redraw_map(_a: int,_b: int,_c: Array) -> void:pass
	func _draw_selection() -> void:pass
	func _draw_facing_cursor() -> void:pass
class OwnAssets extends FT2IndexedAssets:
	var folder:=""
	var fail_apds: Dictionary={}
	var bad_sheets: Dictionary={}
	var no_default: Dictionary={}
	func _init() -> void:manifest={"images":{},"apds":{"SYSTEM":"own","OWN_TEMP":"own","CHAR_01V":"own","CHAR_02V":"own","CHAR_01A":"own","CHAR_02A":"own","CHAR_64V":"own","CHAR_64A":"own"}}
	func add_image(key: String) -> void:
		var pal:=PackedByteArray();pal.resize(768);pal.fill(27)
		var ip:=folder.path_join(key.get_file()+".idx");var pp:=folder.path_join(key.get_file()+".pal")
		var f:=FileAccess.open(ip,FileAccess.WRITE);f.store_buffer(PackedByteArray([10,11,20,21,12,13,22,23]) if key.contains("body") else PackedByteArray([10,11,12,13]));f.close();f=FileAccess.open(pp,FileAccess.WRITE);f.store_buffer(pal);f.close();manifest.images[key]={"width":4 if key.contains("body") else 2,"height":2,"indices":ip,"palette":pp}
	func still(frame: int) -> Dictionary:return {"groups":[{"move":[0,0],"velocity":[0,0],"steps":[[frame,100,0,-1,0,0]]}]}
	func apd(stem: String) -> Dictionary:
		if fail_apds.has(stem):return {}
		var anim: Dictionary={};var frames: Array=[]
		for i in 5:frames.append({"parts":[1 if stem!="SYSTEM"and i==1 else 0],"pivot":0,"bounds":[0,0,2,2]})
		for name in ["F.SET","B.SET","F.STAND","B.STAND","F.COMPLETE","B.COMPLETE","F.DEAD","B.DEAD","F.DEAD#","B.DEAD#","F.ACT","SILENCE","F.SWEAT"]:anim[name]=still(0)
		anim["F.POINT"]=still(1);anim["B.POINT"]=still(1)
		for label in ["F.STAND","B.STAND"]:anim[label]={"groups":[{"move":[0,0],"velocity":[0,0],"steps":[[0,100,0,-1,0,0],[1,100,0,-1,0,0]]}]}
		if no_default.has(stem):
			for label in ["F.SET","B.SET","F.STAND","B.STAND"]:anim.erase(label)
		for spec in [["SMALL.M",1],["MIDDLE.M",2],["LARGE.M",3],["HUGE.M",4]]:anim[spec[0]]=still(spec[1])
		return {"name":stem,"sheets":["own/missing.bmp"if bad_sheets.has(stem)else"own/system.bmp"if stem=="SYSTEM"else"own/body.bmp"],"parts":[[0,0,0,2,2,0,0,255],[0,2,0,2,2,0,0,255]],"frames":frames,"animations":anim}
class OwnData:
	extends RefCounted
	var assets
	func appearance_definition(id: int) -> int:return id
	func load_apd(stem: String) -> Dictionary:return assets.apd(stem)
	func load_table(_name: String) -> Array:
		var out: Array=[]
		for i in 65:out.append({"id":i,"shadow_size_selector":2})
		return out
	func raw_table(_name: String) -> PackedByteArray:
		var raw:=PackedByteArray();raw.resize(56);raw.fill(0);return raw
	func encode_unit(values: Dictionary) -> PackedByteArray:
		var raw:=PackedByteArray();raw.resize(124);raw.fill(0)
		for pair in [["kind",0],["definition_id",2],["level",4],["direction",6],["state",16],["control",18],["hp_max",36],["hp",38],["mp_max",40],["mp",42]]:raw.encode_u16(pair[1],int(values.get(pair[0],0)))
		for pair in [["x",8],["y",12],["move_marker",92],["action_marker",96]]:raw.encode_u32(pair[1],int(values.get(pair[0],0)))
		return raw
	func decode_unit(raw: PackedByteArray,slot: int) -> Dictionary:
		var row:={"slot":slot}
		for pair in [["kind",0],["definition_id",2],["direction",6],["state",16],["control",18],["weapon",20],["armor",22],["accessory1",24],["accessory2",26]]:row[pair[0]]=raw.decode_u16(pair[1])
		for pair in [["x",8],["y",12],["move_marker",92],["action_marker",96]]:row[pair[0]]=raw.decode_s32(pair[1])
		return row
class OwnRules:
	extends RefCounted
	func construct(units: Array,descriptor: PackedByteArray,seeds: Array) -> Dictionary:
		var out:=units.duplicate()
		for slot in range(10,out.size()):
			if out[slot].decode_u16(0)==0:out[slot]=descriptor.duplicate();return {"units":out,"slot":slot,"seeds":seeds.duplicate()}
		return {"units":out,"slot":-1,"seeds":seeds.duplicate()}
class OwnBattle:
	extends RefCounted
	signal changed
	var units: Array=[]
	var rng: Array=[1,2,3]
	var rules=OwnRules.new()
	func refresh_context() -> void:pass
class PassiveFX:
	extends RefCounted
	var active:=false
	var suppressed: Dictionary={}
	var records: Array=[]
	var caster: Dictionary={}
	var children: Array=[]
	var _jobs=null
	var _proxy: Dictionary={}
	func direct_render() -> bool:return false
class OwnEnvironment:
	extends RefCounted
	func commands(_p: Vector2i) -> Array:return []
var checks:=0
var failures: Array[String]=[]
var output:=""
var assets: OwnAssets
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--job-wait-output="):output=arg.trim_prefix("--job-wait-output=")
	call_deferred("run")
func fixture() -> Dictionary:
	assets.fail_apds.clear();assets.bad_sheets.clear();assets.no_default.clear();assets.manifest.apds["CHAR_01V"]="own"
	var data:=OwnData.new();data.assets=assets;var battle:=OwnBattle.new()
	for slot in 50:battle.units.append(data.encode_unit({}))
	battle.units[0]=data.encode_unit({"kind":1,"definition_id":1,"x":4,"y":6,"hp_max":40,"hp":40,"mp_max":12,"mp":12,"move_marker":1,"action_marker":1})
	battle.units[1]=data.encode_unit({"kind":2,"definition_id":2,"x":5,"y":6,"hp_max":30,"hp":30,"move_marker":1,"action_marker":1})
	var view:=RecordingView.new();view.data=data;view.assets=assets;view.battle=battle;view.palette=FT2Palette.new();view.surface=FT2IndexedSurface.new();view.physical=PassiveFX.new();view.magic=PassiveFX.new();view.environment=OwnEnvironment.new();view.game_mode=4;view._service_mode="appearance_test";view.map_id=40;view.map={"base":[320,120],"side":16,"header":[0,0,0,0],"background":""}
	view._acquire_system_palette(assets.image("own/system.bmp",[[90,16,208],[10,64,144],[74,16,16]]));view._refresh_actors();battle.changed.connect(view._refresh_actors)
	var vm=VM.new();vm.data=data;vm.battle=battle;vm.jobs=Jobs.new(data);vm.mode=4;vm.actor_cache_mode=4;vm.actor_player_query=Callable(view,"unit_player");vm.actor_appearance_refresh=func(slot: int,release_first: bool=false):
		return view.source_refresh_actor(slot,release_first,int(vm.mode))
	vm.actor_changed.connect(view.set_script_state)
	vm.jobs.changed.connect(vm._emit_actor_state);vm.jobs.cell_committed.connect(vm._job_cell);vm.jobs.finished.connect(vm.actor_finished)
	return {"vm":vm,"view":view,"data":data,"battle":battle}
func cleanup(f: Dictionary) -> void:
	f.vm.jobs.changed.disconnect(f.vm._emit_actor_state);f.vm.jobs.cell_committed.disconnect(f.vm._job_cell);f.vm.jobs.finished.disconnect(f.vm.actor_finished);f.vm.actor_changed.disconnect(f.view.set_script_state);f.vm.actor_player_query=Callable();f.vm.actor_appearance_refresh=Callable();f.battle.changed.disconnect(f.view._refresh_actors);f.view.free()
func create_temp(f: Dictionary) -> int:
	f.vm._create_actor(["OWN_TEMP",100,3,4],true);var id: int=f.vm._actor(100);f.vm._execute(8,[id,"F.POINT",0]);return id
func paint(f: Dictionary) -> PackedByteArray:
	f.view.draws.clear();f.view._render(false);return f.view.surface.pixels
func at_unit(f: Dictionary,slot: int) -> int:
	var u=f.data.decode_unit(f.battle.units[slot],slot);var p: Vector2i=f.view.world_to_screen(Vector2i(u.x,u.y));return paint(f)[p.y*640+p.x]
func slots(view: RecordingView) -> Array:
	var out: Array=[]
	for call in view.refresh_calls:out.append(call.slot)
	return out
func running(jobs,id: int) -> bool:
	return jobs.is_running(id) if jobs.has_method("is_running") else jobs.is_busy(id)
func queue(f: Dictionary,slot: int=0) -> Dictionary:
	f.vm.actor_busy_query=Callable(f.view,"script_actor_busy")
	f.vm._execute(25,[slot,"ABSENT","s"])
	return f.vm.jobs.jobs[slot]
func looping() -> FT2APDPlayer:
	var player=FT2APDPlayer.new();player.play({"name":"OWN_BUSY","animations":{"OWN_LOOP":{"groups":[{"move":[0,0],"velocity":[0,0],"steps":[[0,20,0,-1,0,0],[1,20,0,-1,0,0]]}]}}},"OWN_LOOP",100,3);return player
func run() -> void:
	FT2Content.active=null;assets=OwnAssets.new();assets.folder="user://own_job_wait_"+str(OS.get_process_id());DirAccess.make_dir_recursive_absolute(assets.folder);assets.add_image("own/system.bmp");assets.add_image("own/body.bmp")
	for opcode in [17,63]:
		var f:=fixture();var prior=f.view.unit_player(0);var held:=queue(f);var other:=queue(f,1);var steps: Array=held.steps.duplicate(true);held["own_identity"]=7
		check(f.vm.jobs.is_busy(0)and not running(f.vm.jobs,0),"queued1 has live lifetime but is not Source4124A0 running "+str(opcode))
		check(not prior.busy and f.view.script_actor_busy(0,false)==false,"retained flags128 pool is nonbusy before wait "+str(opcode))
		check(not f.vm._execute(opcode,[0]),"OPwait passes queued1 and nonbusy actual Unit70 "+str(opcode))
		check(f.vm.jobs.jobs.size()==2 and f.vm.jobs.jobs[0].get("own_identity")==7 and f.vm.jobs.jobs[1]==other,"OPwait retains both original queued lifetimes "+str(opcode))
		check(held.active and held.index==0 and held.steps==steps and not held.source_started,"OPwait cannot start or advance failed path "+str(opcode))
		var refreshed=f.view.unit_player(0)
		check(refreshed!=prior and refreshed.label=="F.SET","passingOPwait performs actual current-mode Unit70 refresh "+str(opcode))
		check(f.vm.jobs.snapshots().is_empty(),"queued1 cannot claim a visual/path/shadow owner "+str(opcode))
		f.vm._execute(8,[0,"F.POINT",0])
		check(f.view.unit_player(0)==refreshed and refreshed.label=="F.POINT"and refreshed.frame==1,"validOP8 controls actual refreshed pool despite queued record "+str(opcode))
		check(f.vm.jobs.jobs.size()==2 and f.vm.jobs.is_busy(0),"OP8 keeps live queued records rather than clearing not-running jobs "+str(opcode))
		f.vm._request_source_appearance(0);check(f.vm.jobs.jobs.size()==2 and held.index==0,"ordinary refresh preserves queued lifetime "+str(opcode))
		for now in [100,500,1000]:f.vm.jobs.advance(now)
		check(held.active and held.index==0 and held.world==Vector2i(4,6),"queued record has no automatic retry/progress after refresh "+str(opcode))
		f.vm._system(43,[0]);check(f.vm.jobs.jobs.size()==2 and held.active and held.index==0,"SYS43 cleanup guard preserves still-live queued record "+str(opcode))
		cleanup(f)
	for opcode in [17,63]:
		var f:=fixture();f.vm.actor_busy_query=Callable(f.view,"script_actor_busy")
		f.vm.jobs.play_single(0,"CHAR_01V",Vector2i(4,6),"F.POINT",100,{"player_override":f.view.unit_player(0)});f.vm.actor_busy[0]=true
		check(running(f.vm.jobs,0)and not f.vm.jobs.jobs[0].player.busy,"started2 remains wait-active even for a static nonbusy frame "+str(opcode))
		check(f.vm._execute(opcode,[0]),"OPwait blocks actual started2 job "+str(opcode))
		f.vm.jobs.advance(100)
		check(not running(f.vm.jobs,0)and not f.vm.jobs.is_busy(0),"completed job is neither running nor live "+str(opcode))
		check(not f.vm._execute(opcode,[0])and not f.vm.jobs.jobs.has(0),"completed visual alias may be cleared after normal wait "+str(opcode))
		cleanup(f)
	for opcode in [17,63]:
		var f:=fixture();queue(f);var body=f.view.unit_player(0);var busy=looping();body.play(busy.apd,"OWN_LOOP",100,3)
		check(f.vm._execute(opcode,[0]),"Unit70 animation independently blocks queued1 "+str(opcode))
		body.activate(128);body.fade_dither(true,10,100)
		check(f.vm._execute(opcode,[0]),"Unit70 dither independently blocks queued1 "+str(opcode))
		cleanup(f)
	for opcode in [17,63]:
		var f:=fixture();queue(f);f.view._script_unit78[0]=looping()
		check(f.vm._execute(opcode,[0])==(opcode==17),"onlyOP17 waits for Unit78 overlay animation "+str(opcode))
		cleanup(f)
	# Source434880/435084 takes its wait latch before servicing the shared jobs.
	var data:=OwnPath.new();var m=magic_fixture(data,"F.ABSENT");var failed=m._jobs.jobs[0]
	m.before_apd(100)
	check(not m._proxy_was_busy,"magic77 pre-service wait latch ignores queued1")
	check(m._proxy.is_empty()and m._jobs.jobs.is_empty(),"magic normal proxy cleanup is allowed when no started2 job exists")
	check(failed.index==0 and not failed.source_started,"magic cleanup does not force failed job progress")
	m=magic_fixture(data,"F.STATIC");m.before_apd(100)
	check(m._proxy_was_busy and not m._proxy.is_empty(),"magic latch retains one frame when started2 completes during service")
	check(not m._jobs.is_busy(0),"static magic proxy job completes through ordinary job service")
	m.before_apd(200);check(m._proxy.is_empty(),"following magic frame cleans up after running latch clears")
	m=magic_fixture(data,"F.LONG");m.before_apd(100)
	check(m._proxy_was_busy and running(m._jobs,0)and not m._proxy.is_empty(),"magic still waits while actual started2 path remains active")
	var result:={"suite":"actor_job_wait","checks":checks,"failures":failures,"passed":failures.is_empty(),"synthetic":true,"game_data_used":false}
	if output!="":
		DirAccess.make_dir_recursive_absolute(output);var file=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print(JSON.stringify(result));quit(0 if failures.is_empty()else 1)
class OwnPath:
	extends RefCounted
	var dataset:={"name":"OWN_PROXY","animations":{"F.STATIC":{"groups":[{"move":[0,0],"velocity":[0,0],"steps":[[0,20,0,-1,0,0]]}]},"F.LONG":{"groups":[{"move":[0,0],"velocity":[0,0],"steps":[[0,1000,0,-1,0,0],[1,1000,0,-1,0,0]]}]}}}
	func load_apd(_stem: String) -> Dictionary:return dataset
func magic_fixture(data,label: String):
	var m=preload("res://scripts/render/ft2_magic_playback.gd").new();m._jobs=Jobs.new(data);m._jobs.play_single(0,"OWN_PROXY",Vector2i(2,3),label,0);m.active=true;m._phase=1;m._id=77;m._global_phase=1;m._proxy={"world":Vector2i(2,3),"last":Vector2i(2,3),"direction":0};m.stage_handlers={"global_frame_update":{"skill_handlers":{"77":"0x4365bf"}}};return m
