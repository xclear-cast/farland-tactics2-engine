extends SceneTree
## Self-authored ordered placement construction; no original assets or placement records.
const View=preload("res://scripts/render/ft2_battle_view.gd")
const VM=preload("res://scripts/scenario/ft2_vm.gd")
const Jobs=preload("res://scripts/scenario/ft2_actor_jobs.gd")
class RecordingView extends View:
	var draws: Array=[]
	var refresh_calls: Array=[]
	var acquisitions: Array=[]
	func _acquire_actor_resource_palette(definition: int,stem: String,dataset: Dictionary) -> void:
		if str(_actor_palette_acquired.get(definition,""))!=stem:acquisitions.append({"definition":definition,"stem":stem})
		super._acquire_actor_resource_palette(definition,stem,dataset)
	func source_refresh_actor(slot: int,release_first: bool=false,source_mode: int=-1) -> Dictionary:
		var observed=_unit(slot);var result=super.source_refresh_actor(slot,release_first,source_mode);refresh_calls.append({"slot":slot,"release_first":release_first,"result":result,"direction":observed.get("direction",-1),"label":str(result.get("player").label)if result.get("player")!=null else "","player":result.get("player")});return result
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
	func snapshot_units() -> Array:return units.duplicate(true)
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
		if arg.begins_with("--placement-output="):output=arg.trim_prefix("--placement-output=")
	call_deferred("run")
class PlacementData extends FT2Data:
	var helper
	var stages: Dictionary={}
	func read_json(_relative: String) -> Variant:return stages
	func appearance_definition(id: int) -> int:return id
	func load_apd(stem: String) -> Dictionary:return helper.load_apd(stem)
	func load_table(name: String) -> Array:return helper.load_table(name)
	func decode_unit(raw: PackedByteArray,slot: int=-1) -> Dictionary:return helper.decode_unit(raw,slot)
	func raw_table(name: String) -> PackedByteArray:
		var bytes:=PackedByteArray();bytes.resize(65*86 if name=="race" else 64 if name=="magic" else 56);bytes.fill(0)
		if name=="race":
			for i in 65:bytes.encode_u16(i*86+22,20);bytes.encode_u16(i*86+26,10)
		return bytes
class LegacyData extends OwnData:
	func load_placement(_number: int,combat=null) -> Array:return combat.snapshot_units()
func own_row(kind: int,definition: int,control: int,direction: int=0,x: int=4,y: int=6) -> Dictionary:
	return {"kind_word":kind,"definition_id":definition,"level":1,"direction_word":direction,"x":x,"y":y,"state":0,"control":control,"weapon":0,"armor":0,"drop_item":0,"drop_money":0}
func fixture() -> Dictionary:
	assets.fail_apds.clear();assets.bad_sheets.clear();assets.no_default.clear()
	var helper:=OwnData.new();helper.assets=assets
	FT2Content.active=FT2Content.new();FT2Content.active.root="user://own_empty";FT2Content.active.source="user://own_source"
	var data:=PlacementData.new();data.helper=helper;FT2Content.active=null
	var battle:=OwnBattle.new();battle.rules=preload("res://scripts/logic/ft2_mechanics.gd").new(data)
	for slot in 50:battle.units.append(data.encode_unit({}))
	for row in [{"slot":0,"kind":1,"definition_id":1,"direction":2},{"slot":1,"kind":2,"definition_id":2,"direction":0},{"slot":2,"kind":5,"definition_id":1,"direction":0},{"slot":10,"kind":40,"definition_id":64,"direction":0,"control":6}]:
		var values: Dictionary=row.duplicate();values.merge({"x":4+int(row.slot),"y":6,"hp_max":40,"hp":40,"mp_max":12,"mp":12,"move_marker":1,"action_marker":1},true);battle.units[int(row.slot)]=data.encode_unit(values)
	var view:=RecordingView.new();view.data=data;view.assets=assets;view.battle=battle;view.palette=FT2Palette.new();view.surface=FT2IndexedSurface.new();view.physical=PassiveFX.new();view.magic=PassiveFX.new();view.environment=OwnEnvironment.new();view.game_mode=1;view._service_mode="placement_test";view.map_id=40;view.map={"base":[320,120],"side":16,"header":[0,0,0,0],"background":""}
	view._acquire_system_palette(assets.image("own/system.bmp",[[90,16,208],[10,64,144],[74,16,16]]));view._refresh_actors();battle.changed.connect(view._refresh_actors)
	for slot in [0,1,2]:view.source_refresh_actor(slot,false,1)
	view.refresh_calls.clear();view.acquisitions.clear()
	var vm=VM.new();vm.data=data;vm.battle=battle;vm.jobs=Jobs.new(data);vm.mode=4;vm.actor_cache_mode=1;vm.actor_player_query=Callable(view,"unit_player");vm.actor_appearance_refresh=func(slot: int,release_first: bool=false):return view.source_refresh_actor(slot,release_first,int(vm.mode))
	vm.actor_changed.connect(view.set_script_state);vm.jobs.changed.connect(vm._emit_actor_state);vm.jobs.cell_committed.connect(vm._job_cell);vm.jobs.finished.connect(vm.actor_finished)
	return {"vm":vm,"view":view,"data":data,"battle":battle}
func cleanup(f: Dictionary) -> void:
	f.vm.jobs.changed.disconnect(f.vm._emit_actor_state);f.vm.jobs.cell_committed.disconnect(f.vm._job_cell);f.vm.jobs.finished.disconnect(f.vm.actor_finished);f.vm.actor_changed.disconnect(f.view.set_script_state);f.vm.actor_player_query=Callable();f.vm.actor_appearance_refresh=Callable();f.battle.changed.disconnect(f.view._refresh_actors);f.view.free()
func receipt(data) -> Array:
	var value=data.get("placement_constructed")
	return value if value is Array else []
func refresh_slots(view) -> Array:
	var out: Array=[]
	for row in view.refresh_calls:out.append(row.slot)
	return out
func run() -> void:
	FT2Content.active=null;assets=OwnAssets.new();assets.folder="user://own_placement_"+str(OS.get_process_id());DirAccess.make_dir_recursive_absolute(assets.folder);assets.add_image("own/system.bmp");assets.add_image("own/body.bmp")
	var f:=fixture();var prior=f.view.unit_player(0);var untouched=f.view.unit_player(2);var old_npc=f.view.unit_player(10);untouched.dither=5;untouched.offset=Vector2i(7,-9)
	check(prior.label=="B.COMPLETE"and f.view._source_appearance_modes[0]==1,"fixture begins with genuine MODE1 ownership/markers1,1")
	f.data.stages={"STAGE000":{"records":[own_row(1,1,0,3,5,7),own_row(1,1,0,0,6,8),own_row(3,2,0,0,7,9),own_row(40,64,6,0,8,9)]}}
	var before_rng: Array=f.battle.rng.duplicate();f.vm._execute(11,[0]);var records:=receipt(f.data)
	check(records.map(func(r):return r.slot)==[0,0,3,10],"Data reports successful construction slots in exact row order with duplicates")
	check(records.size()==4 and records[0].unit.decode_u16(6)==3 and records[1].unit.decode_u16(6)==0,"receipt keeps distinct per-row unit snapshots before later duplicate changes")
	check(f.battle.units[0].decode_u16(6)==0 and f.battle.units[0].decode_s32(8)==6,"ordinary constructor preserves final logical row result")
	check(f.battle.rng==before_rng,"level1 own construction adds no unrelated RNG mutation")
	check(refresh_slots(f.view)==[0,0,3,10],"View invokes only actual constructed slots, in source row order")
	check(f.view.refresh_calls.size()==4 and f.view.refresh_calls[0].direction==3 and f.view.refresh_calls[1].direction==0,"each visual constructor observes its own row facing, not final-row state")
	check(f.view.refresh_calls.size()==4 and f.view.refresh_calls[0].label=="B.SET"and f.view.refresh_calls[1].label=="F.SET","MODE4 construction consumes current-mode SET at both duplicate calls")
	check(f.view.unit_player(0)!=prior and f.view.unit_player(0).label=="F.SET"and f.view.unit_player(0).flags==128,"reused MODE1 unit is actually reconstructed as inactive EVENT4 SET")
	check(f.view.refresh_calls.size()==4 and f.view.refresh_calls[0].player!=f.view.refresh_calls[1].player,"duplicate source constructor calls allocate separate Unit70 lifetimes")
	check(f.view.unit_player(3)!=null and f.view.unit_player(3).label=="F.SET","new party construction receives the same current-mode appearance")
	check(f.view.unit_player(2)==untouched and untouched.label=="F.COMPLETE"and f.view._source_appearance_modes[2]==1,"untouched party keeps old mode ownership and pool identity")
	check(untouched.dither==5 and untouched.offset==Vector2i(7,-9),"untouched party dither and motion are not reset")
	check(f.view.unit_player(10)!=old_npc,"Source NPC-domain release really replaces old NPC Unit70")
	check(f.view.acquisitions.filter(func(r):return r.definition==64).size()==1,"NPC resource cache is invalidated/acquired once without double construction")
	check(f.view._actor_npc_cache_generation==1,"one OP11 delivers one NPC cache generation")
	check(f.view._actor_resource_stems[1]=="CHAR_01A"and f.view._actor_resource_stems[2]=="CHAR_02A","cached party A resources survive current-mode constructor selection")
	var final_player=f.view.unit_player(0);var final_npc=f.view.unit_player(10);var calls: int=f.view.refresh_calls.size();f.vm._emit_actor_state();f.vm._emit_actor_state();f.battle.changed.emit()
	check(f.view.refresh_calls.size()==calls and f.view.unit_player(0)==final_player and f.view.unit_player(10)==final_npc,"repeated state delivery cannot repeat one-shot construction")
	if records.size()==4:
		f.battle.units[0].encode_u16(6,1);check(records[1].unit.decode_u16(6)==0,"receipt unit bytes own a deep copy independent of live units");f.battle.units[0].encode_u16(6,0)
	else:check(false,"receipt unit bytes own a deep copy independent of live units")
	f.vm._execute(11,[0]);check(f.view.refresh_calls.size()==calls+4 and f.view.unit_player(0)!=final_player,"a second actual OP11 serial legitimately repeats each constructor")
	f.data.stages["STAGE001"]={"records":[]};calls=f.view.refresh_calls.size();final_player=f.view.unit_player(0);f.vm._execute(11,[1])
	check(receipt(f.data).is_empty(),"empty placement resets prior successful receipt")
	check(f.view.refresh_calls.size()==calls and f.view.unit_player(0)==final_player,"empty placement does not replay old party constructor slots")
	cleanup(f)
	# Allocation fails after one success; later rows must never appear in receipts/callbacks.
	f=fixture()
	for slot in range(3,9):f.battle.units[slot]=f.data.encode_unit({"kind":10+slot,"definition_id":1,"control":0,"x":slot,"y":5})
	f.data.stages={"STAGE000":{"records":[own_row(30,1,0),own_row(31,1,0),own_row(40,64,6)]}};f.vm._execute(11,[0])
	check(receipt(f.data).map(func(r):return r.slot)==[9],"partial allocation receipt contains only successful prefix")
	check(refresh_slots(f.view)==[9],"failed/later unexecuted placement rows cannot trigger appearance calls")
	check(f.battle.units[9].decode_u16(0)==30 and f.battle.units[10].decode_u16(0)==0,"allocation failure preserves first success and stops before following NPC row")
	cleanup(f)
	# Definition7 returns before replacing its active custom Unit70; untouched custom party survives.
	f=fixture()
	for slot in [0,2]:f.battle.units[slot].encode_u16(2,7);f.vm._sprite(slot,{"stem":"OWN_TEMP","label":"F.POINT","play":true})
	var special=f.view.unit_player(0);var untouched_special=f.view.unit_player(2);special.dither=4;f.view.refresh_calls.clear();f.data.stages={"STAGE000":{"records":[own_row(1,7,0,3)]}};f.vm._execute(11,[0])
	check(refresh_slots(f.view)==[0],"definition7 still receives the real constructor call")
	check(f.view.unit_player(0)==special and special.label=="F.POINT"and special.dither==4,"definition7 early return preserves old actual custom player")
	check(f.view.unit_player(2)==untouched_special,"untouched surviving custom party player is not blanket-released")
	cleanup(f)
	# A source resource-load failure preserves existing handles and is not an automatic retry.
	f=fixture();prior=f.view.unit_player(0);f.view._actor_resource_stems.erase(1);assets.fail_apds["CHAR_01V"]=true;f.data.stages={"STAGE000":{"records":[own_row(1,1,0,3)]}};f.vm._execute(11,[0])
	check(refresh_slots(f.view)==[0]and not f.view.refresh_calls[0].result.rebuilt,"failed resource still has one truthful constructor receipt")
	check(f.view.unit_player(0)==prior and prior.label=="B.COMPLETE","load failure retains old pose and handles before release")
	assets.fail_apds.clear();f.vm._emit_actor_state();f.battle.changed.emit()
	check(f.view.unit_player(0)==prior and f.view.refresh_calls.size()==1,"later resource availability cannot silently redo a failed constructor")
	cleanup(f)
	# Legacy two-argument Array-return data adapters remain callable without the optional receipt.
	f=fixture();var legacy:=LegacyData.new();legacy.assets=assets;f.vm.data=legacy;prior=f.view.unit_player(0);f.vm._execute(11,[0])
	check(f.view.refresh_calls.is_empty()and f.view.unit_player(0)==prior,"legacy FakeData API without receipt keeps its existing behavior")
	check(f.vm.errors.is_empty(),"placement handling does not add VM parse/dispatch errors")
	cleanup(f)
	var result:={"suite":"placement_appearance","checks":checks,"failures":failures,"passed":failures.is_empty(),"synthetic":true,"game_data_used":false}
	if output!="":
		DirAccess.make_dir_recursive_absolute(output);var file=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print(JSON.stringify(result));quit(0 if failures.is_empty()else 1)
