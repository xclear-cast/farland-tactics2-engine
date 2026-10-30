extends SceneTree
## Self-authored Unit70 lifetime and first/later missing-label job boundaries; original data absent.
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
		if arg.begins_with("--job-start-output="):output=arg.trim_prefix("--job-start-output=")
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
func run() -> void:
	FT2Content.active=null;assets=OwnAssets.new();assets.folder="user://own_job_start_"+str(OS.get_process_id());DirAccess.make_dir_recursive_absolute(assets.folder);assets.add_image("own/system.bmp");assets.add_image("own/body.bmp")
	# A first ordinary OP8 names the existing Unit70. A failed label lookup
	# changes neither pool identity nor playback; OP8 separately shows body/shadow.
	var f:=fixture();var prior=f.view.unit_player(0);var shadow=f.view._unit_shadow(0)
	var authored: Dictionary=assets.apd("CHAR_01V").duplicate(true)
	authored.animations["F.SET"]={"groups":[{"move":[0,0],"velocity":[0,0],"steps":[[0,30,0,-1,0,0],[1,40,0,-1,0,0]]}]}
	prior.play(authored,"F.SET",100,128);prior.dither=3;prior.base_flip=2;prior.offset=Vector2i(7,-9);prior.visible=false;shadow.visible=false
	var before:={"frame":prior.frame,"flags":prior.flags,"label":prior.label,"steps":prior.steps.duplicate(true),"offset":prior.offset,"mode":prior.state_mode,"epoch":prior._epoch,"started":prior._started,"dither":prior.dither,"flip":prior.base_flip,"order":prior.pool_order}
	f.vm._execute(8,[0,"F.MISSING",1]);var kept=f.view.unit_player(0)
	check(kept==prior,"first missing OP8 borrows existing regular Unit70")
	check(kept.frame==before.frame and kept.label==before.label,"missing OP8 retains actual frame and label")
	check(kept.flags==before.flags and kept.state_mode==before.mode and not kept.busy,"missing OP8 preserves flags128/mode2/nonbusy")
	check(kept.steps==before.steps and kept._epoch==before.epoch and kept._started==before.started,"missing OP8 preserves the old playback schedule")
	check(kept.dither==before.dither and kept.base_flip==before.flip and kept.offset==before.offset,"missing OP8 preserves dither/baseflip/motion")
	check(kept.pool_order==before.order,"missing OP8 does not allocate a new pool entry")
	check(kept.visible and shadow.visible,"OP8 shows retained body and shadow even when selection fails")
	# Native411B70 queues state1; 4122C0 cannot enter state2 when first lookup fails.
	f.vm._execute(25,[0,"MISSING","ss"]);var job: Dictionary=f.vm.jobs.jobs[0]
	check(job.player==prior,"first queued path aliases actual retained Unit70")
	check(job.active and job.index==0 and job.world==Vector2i(4,6),"failed first step remains queued at its source cell")
	for now in [200,400,800]:f.vm.jobs.advance(now)
	check(job.active and job.index==0 and job.world==Vector2i(4,6),"nonbusy retained player cannot complete a never-started job")
	check(f.battle.units[0].decode_s32(8)==4 and f.battle.units[0].decode_s32(12)==6,"first lookup failure cannot commit destination unit coordinates")
	check(f.vm.jobs.is_busy(0) and f.vm.jobs.errors.size()==1,"queued first failure remains busy with one diagnostic")
	# Becoming available is not an implicit second4122A0 call.
	var replacement=prior.apd.duplicate(true);replacement.animations["F.MISSING1"]=replacement.animations["F.SET"].duplicate(true)
	prior.apd=replacement
	for now in [1000,2000]:f.vm.jobs.advance(now)
	check(job.active and job.index==0 and job.player.label=="F.SET","later data/player changes cannot automatically restart pending job")
	check(f.vm.jobs.errors.size()==1,"waiting does not repeatedly attempt a missing first label")
	cleanup(f)
	# A valid first ordinary OP8 also aliases the same pool object.
	f=fixture();prior=f.view.unit_player(0);f.vm._execute(8,[0,"F.POINT",0])
	check(f.view.unit_player(0)==prior and prior.label=="F.POINT","first successful OP8 reuses Unit70 and selects its animation")
	cleanup(f)
	# Resource replacement and OP7's explicit blank allocation must retain their boundaries.
	f=fixture();prior=f.view.unit_player(0);prior.dither=6;prior.offset=Vector2i(9,9)
	f.vm._sprite(0,{"stem":"CHAR_02V","label":"F.POINT","play":true});var other=f.view.unit_player(0)
	check(other!=prior and other.apd.name=="CHAR_02V","explicit stem change cannot borrow another resource's player")
	check(other.dither==0 and other.offset==Vector2i.ZERO,"new resource does not inherit old pool display state")
	cleanup(f)
	f=fixture();prior=f.view.unit_player(0);f.vm._execute(7,[0,97]);var blank=f.view.unit_player(0)
	check(blank!=prior and blank.frame==-1 and not blank.visible,"OP7 explicitly replaces Unit70 with blank allocation")
	f.vm._execute(8,[0,"F.MISSING",0]);check(f.view.unit_player(0)==blank and blank.frame==-1 and not blank.visible,"failed play after OP7 retains blank, never resurrects released pose")
	cleanup(f)
	f=fixture();prior=f.view.unit_player(0);var temporary:=create_temp(f)
	check(temporary>=10 and f.view.unit_player(temporary)!=prior and f.view.unit_player(temporary).apd.name=="OWN_TEMP","OP19 temporary actor owns a separate resource/player")
	check(f.view.unit_player(0)==prior,"OP19 creation cannot replace another actor's existing Unit70")
	cleanup(f)
	# Pure job vectors separate first-start failure from later-step failure.
	var data:=PathData.new();var jobs=Jobs.new(data);var shared=FT2APDPlayer.new();shared.play(data.dataset,"F.KEEP",0,3)
	jobs.play_path(7,"OWN_PATH",Vector2i(2,3),"ss","MISSING",0,{"player_override":shared});var held: Dictionary=jobs.jobs[7]
	var old_frame: int=shared.frame;jobs.advance(100);jobs.advance(200)
	check(held.active and held.index==0 and held.world==Vector2i(2,3),"failed first job stays queued while prior looping pool exists")
	check(shared.frame!=old_frame or shared.ordinal>0,"retained shared pool still clocks independently of failed job start")
	data.dataset.animations["F.MISSING1"]=data.dataset.animations["F.KEEP"].duplicate(true);data.dataset.animations["F.MISSING2"]=data.dataset.animations["F.KEEP"].duplicate(true)
	for now in [300,400,500]:jobs.advance(now)
	check(held.active and held.index==0 and jobs.errors.size()==1,"later label availability does not retry pending first start")
	jobs.play_path(7,"OWN_PATH",Vector2i(2,3),"s","GOOD",600,{"player_override":shared});var restarted: Dictionary=jobs.jobs[7]
	for now in [600,610,620,630,640]:jobs.advance(now)
	check(not restarted.active and restarted.world==Vector2i(2,4),"explicit replacement starts a valid job after pending failure")
	check(restarted.player==shared,"replacement job keeps caller's authoritative pool alias")
	jobs=Jobs.new(data);var single=FT2APDPlayer.new();single.play(data.dataset,"F.KEEP",0,128)
	jobs.play_single(10,"OWN_PATH",Vector2i(7,8),"F.ABSENT",0,{"player_override":single})
	for now in [100,200,300]:jobs.advance(now)
	check(jobs.jobs[10].active and jobs.jobs[10].index==0 and jobs.jobs[10].world==Vector2i(7,8),"missing first single-action selection also remains queued")
	check(jobs.jobs[10].player==single and single.flags==128 and not single.busy,"single failure preserves caller's nonbusy128 pool without changing global busy")
	check(jobs.errors.size()==1,"queued single failure is diagnosed once")
	jobs=Jobs.new(data);jobs.play_path(11,"OWN_PATH",Vector2i(2,3),"s","ABSENT",0)
	for now in [100,200]:jobs.advance(now)
	check(jobs.jobs[11].active and jobs.jobs[11].index==0 and jobs.jobs[11].player.frame==-1,"unplayed first-failure allocation cannot silently complete either")
	jobs=Jobs.new(data);jobs.play_path(8,"OWN_PATH",Vector2i(2,3),"ss","PARTIAL",0)
	for now in [100,110,120,130,140,150,160]:jobs.advance(now)
	check(not jobs.jobs[8].active and jobs.jobs[8].index==2 and jobs.jobs[8].world==Vector2i(2,5),"later-step lookup failure keeps started state and can continue to final cell")
	check(jobs.errors.size()==1 and jobs.errors[0].label=="F.PARTIAL2","later missing step reports once without converting to first-start failure")
	jobs=Jobs.new(data);jobs.play_path(9,"OWN_PATH",Vector2i(2,3),"ss","GOOD",0)
	for now in [100,110,120,130,140,150,160,170]:jobs.advance(now)
	check(not jobs.jobs[9].active and jobs.jobs[9].world==Vector2i(2,5),"normal two-step path still commits both cells")
	check(jobs.errors.is_empty(),"normal path does not acquire missing-label diagnostics")
	var result:={"suite":"actor_job_start_failure","checks":checks,"failures":failures,"passed":failures.is_empty(),"synthetic":true,"game_data_used":false}
	if output!="":
		DirAccess.make_dir_recursive_absolute(output)
		var file=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print(JSON.stringify(result));quit(0 if failures.is_empty()else 1)

class PathData:
	extends RefCounted
	var dataset:={"name":"OWN_PATH","animations":{}}
	func _init() -> void:
		var finite:={"groups":[{"move":[0,0],"velocity":[0,0],"steps":[[0,10,0,-1,0,0],[1,10,0,-1,0,0]]}]}
		for name in ["F.KEEP","F.GOOD1","F.GOOD2","F.PARTIAL1"]:dataset.animations[name]=finite.duplicate(true)
	func load_apd(_stem: String) -> Dictionary:return dataset
