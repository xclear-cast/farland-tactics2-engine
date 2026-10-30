extends SceneTree
## Self-authored assets: OP48 mode1 cache rebuild must outlive the return to EVENT4.
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
		for label in ["F.DEAD","B.DEAD","F.DEAD#","B.DEAD#"]:anim[label]=still(1)
		# Shipping CHAR02A/03A use the direct DEAD fallback, with no hash variant.
		anim.erase("F.DEAD#");anim.erase("B.DEAD#")
		anim["DEAD"]={"groups":[{"move":[0,0],"velocity":[0,0],"steps":[[2,100,0,-1,0,0],[3,100,0,-1,0,0]]}]}
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
		for i in 65:out.append({"id":i,"shadow_size_selector":3 if i==1 else 2})
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
		if arg.begins_with("--cache-rebuild-output="):output=arg.trim_prefix("--cache-rebuild-output=")
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
	FT2Content.active=null;assets=OwnAssets.new();assets.folder="user://own_cache_mode_"+str(OS.get_process_id());DirAccess.make_dir_recursive_absolute(assets.folder);assets.add_image("own/system.bmp");assets.add_image("own/body.bmp")
	var f:=fixture();f.battle.units[0].encode_u16(16,1);f.battle.units[0].encode_u16(38,0)
	var old=f.view.unit_player(0);var raw:PackedByteArray=f.battle.units[0].duplicate();var observed:Array=[]
	# Capture the first completed mode1 build inside OP48's emitted state, before its _changed.
	var witness=func(_state:Dictionary):
		if observed.is_empty():observed.append({"body":f.view.unit_player(0),"shadow":f.view._unit_shadow(0),"icon":f.view._source_unit_family(0)[2]})
	f.vm.actor_changed.connect(witness)
	f.vm._execute(48,[])
	var body=f.view.unit_player(0);var shadow=f.view._unit_shadow(0);var icon=f.view._source_unit_family(0)[2];var other=f.view.unit_player(1);var other_shadow=f.view._unit_shadow(1)
	check(observed.size()==1,"actual VM.OP48 emitted a cache-rebuild state")
	check(body!=old and body==observed[0].body,"OP48 reallocates once and its immediate _changed keeps the first completed Unit70")
	check(body.label=="F.DEAD" and body.flags==128 and body.frame==1,"mode1 rebuild selects the own distinct DEAD staticframe under EVENT4")
	check(body.apd.name=="CHAR_01A","OP48 acquires the source MODE1 A resource")
	check(f.view.game_mode==4 and f.vm.mode==4 and f.vm.previous_mode==1,"logical/view EVENT4 resumes after temporary source MODE1 rebuild")
	check(f.view._source_appearance_modes.get(0)==1 and f.view._source_appearance_modes.get(1)==1,"each completed occupied Unit retains its real mode1 appearance owner")
	check(f.view._source_appearance_modes.size()==2,"empty slots acquire no appearance ownership")
	check(shadow!=null and shadow==observed[0].shadow and shadow.label=="HUGE.M" and shadow.flags==128,"DEAD race3 expands its actual Unit74 to HUGE.M and preserves the first handle")
	check(icon!=null and icon==observed[0].icon and icon.label=="DEAD" and icon.flags==3 and icon.frame>=0,"actual Unit78 DEAD icon exists and preserves the first handle")
	check(f.battle.units[0]==raw,"cache rebuild does not change logical Unit bytes")
	check(at_unit(f,0)==154,"distinct own DEAD frame reaches the indexed renderer")
	var epoch:int=body._epoch;var icon_epoch:int=icon._epoch
	for repeat in 4:
		f.vm._changed();f.view._refresh_actors();f.vm._emit_actor_state();paint(f)
	check(f.view.unit_player(0)==body and body.label=="F.DEAD" and body.flags==128 and body._epoch==epoch,"ordinary EVENT4 changes/eager sync/state delivery never reconstruct the mode1 DEAD body")
	check(f.view._unit_shadow(0)==shadow and shadow.label=="HUGE.M","repeated EVENT4 deliveries preserve expanded Unit74 identity")
	check(f.view._source_unit_family(0)[2]==icon and icon.label=="DEAD" and icon._epoch==icon_epoch,"repeated EVENT4 deliveries preserve the live Unit78 icon identity and epoch")
	check(at_unit(f,0)==154,"repeated ordinary sync retains DEAD pixels instead of inactive SET")
	check(f.view.unit_player(1)==other and f.view._unit_shadow(1)==other_shadow,"ordinary sync preserves the other rebuilt unit family too")
	# A later REAL4196F0 under MODE4 is different: it legitimately consumes inactive markers.
	f.vm._execute(31,[0,4]);var fresh=f.view.unit_player(0)
	check(fresh!=body and fresh.label=="F.SET" and fresh.flags==128,"explicit source_refresh_actor MODE4 legitimately allocates inactive SET")
	check(f.view._source_appearance_modes.get(0)==4 and f.view._source_appearance_modes.get(1)==1,"true target-only callback replaces only its mode ownership")
	check(fresh.apd.name=="CHAR_01A","true MODE4 call reuses the actual cached A resource, matching45EAD0 lifetime")
	check(f.view._unit_shadow(0)!=shadow and f.view._unit_shadow(0).label=="LARGE.M","explicit MODE4 constructor legitimately restores the inactive shadow size")
	check(f.view._source_unit_family(0)[2]==null,"explicit MODE4 inactive constructor legitimately has no DEAD icon")
	check(at_unit(f,0)==144,"true callback changes the actual own raster back to SET pixels")
	check(f.view.unit_player(1)==other and f.view._unit_shadow(1)==other_shadow,"true target callback leaves the other source mode1 family untouched")
	f.vm._changed();f.vm._emit_actor_state();check(f.view.unit_player(0)==fresh and fresh.label=="F.SET","later state delivery cannot resurrect the previous DEAD metadata")
	f.vm.actor_changed.disconnect(witness);cleanup(f)
	var report={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored indexed2x2 APDs/palettes/unit records; real VM.OP48->View, no original data","scope":"source43E671..43E6B4 mode1 rebuild ownership and later true4196F0; no physical native pool-index or phase equivalence claim"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output);var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
