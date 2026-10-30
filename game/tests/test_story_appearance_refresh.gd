extends SceneTree
## Self-authored indexed APDs/unit records; true4196F0 callback and atomic display handoff.
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
		if arg.begins_with("--appearance-output="):output=arg.trim_prefix("--appearance-output=")
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
	FT2Content.active=null;assets=OwnAssets.new();assets.folder="user://own_appearance_"+str(OS.get_process_id());DirAccess.make_dir_recursive_absolute(assets.folder);assets.add_image("own/system.bmp");assets.add_image("own/body.bmp")
	# ShippingE08 OP7(A)->OP31(4): defaultbody must replace the allocatedblank.
	var f:=fixture();var first_other=f.view.unit_player(1);f.vm._execute(7,[0,97]);var blank=f.view.unit_player(0)
	check(blank.frame==-1 and not blank.visible,"sourcevariantchange has the correct OP33 blankfallthrough")
	var before_dir: int=f.battle.units[0].decode_u16(6);f.vm._execute(31,[0,4]);var restored=f.view.unit_player(0)
	check(f.battle.units[0].decode_u16(6)==before_dir,"OP31sentinel4 preserves logicalfacing")
	check(restored!=blank and restored.frame>=0 and restored.visible,"OP31sentinel4 really allocates/plays defaultbody afterOP7")
	check(at_unit(f,0)==144,"E08-like blank-to-default reaches the actualindexedraster")
	check(f.view.unit_player(1)==first_other,"oneactorrefresh leaves the otherUnit70 untouched")
	f.vm._sprite(1,{"stem":"CHAR_02V","label":"F.POINT","play":true});check(f.view.unit_player(0)==restored and restored.label=="F.SET","otheractorstateemit cannot replay oldOP7blankmetadata")
	cleanup(f)
	# ShippingE17 stagedordinaryNPC variantA->samefacingrefresh before dialogue.
	f=fixture();f.battle.units[11]=f.data.encode_unit({"kind":11,"definition_id":2,"control":6,"x":7,"y":4,"move_marker":1,"action_marker":1});f.view._refresh_actors();f.vm._execute(7,[11,97]);var npc_blank=f.view.unit_player(11);f.vm._execute(31,[11,4])
	check(npc_blank.frame==-1 and f.view.unit_player(11)!=npc_blank and f.view.unit_player(11).visible,"E17-like ordinaryNPC leavesblank on true4196F0")
	check(at_unit(f,11)==144,"E17-like restoredNPC paints its own cell")
	cleanup(f)
	# ShippingE1 POINT->sentinelrefresh, plus real42DB30 allocation-state resets.
	f=fixture();f.vm._execute(8,[0,"F.POINT",0]);var point=f.view.unit_player(0);check(at_unit(f,0)==154,"ownPOINTframe visibly differs from defaultframe")
	point.dither=5;point.base_flip=2;point.offset=Vector2i(3,4);point.visible=false;point.fade_dither(true,9,100);var old_order: int=point.pool_order
	f.vm._execute(31,[0,4]);var normal=f.view.unit_player(0)
	check(normal!=point and normal.label=="F.SET"and normal.visible,"E1POINT is replaced by the normaldefaultpose")
	check(normal.dither==0 and normal.base_flip==0 and normal.offset==Vector2i.ZERO and not normal.dither_busy,"trueallocation resets dither/baseflip/motion/fade, not merelyplay")
	check(normal.pool_order>old_order,"newUnit70 is appended to activeorder after the freedinstance")
	check(at_unit(f,0)==144,"E1-like samefacingrefresh changes actualPOINTpixels back todefault")
	check(not f.vm.actor_sprites[0].has("label")and f.vm.actor_sprites[0].player_override==normal,"VM replaces olddisplaymetadata only after successfulcallee")
	f.vm._sprite(1,{"stem":"CHAR_02V","label":"F.POINT","play":true});check(f.view.unit_player(0)==normal and at_unit(f,0)==144,"laterstateemit cannot resurrect POINT or itsdither")
	# Internal Player.play base_flip is an adapter fixture, not a native byte89 equivalence claim.
	# OrdinaryOP8 is not a realloc; its same-instance/dither behavior stays unchanged.
	normal.dither=3;normal.base_flip=2;var instance=normal
	check(instance.play(assets.apd("CHAR_01V"),"F.POINT",0,1)and instance.base_flip==2 and instance.dither==3,"internalPlayer.play adapter retains dither/baseflip without allocating")
	f.vm._execute(8,[0,"F.POINT",0]);check(f.view.unit_player(0)==instance and instance.dither==3,"ordinaryOP8 uses the sameUnit70 and preserves dither; existingflip_yadapter staysunchanged")
	cleanup(f)
	# OP37 refreshes the secondactor even when facing alreadyequals the result.
	f=fixture();f.vm._execute(8,[0,"F.POINT",0]);var faced=f.view.unit_player(0);f.battle.units[0].encode_u16(6,1);f.battle.units[1].encode_u32(8,7);f.battle.units[1].encode_u32(12,6);f.view.refresh_calls.clear();f.vm._execute(37,[1,0])
	check(slots(f.view)==[0]and f.view.unit_player(0)!=faced,"OP37 invokes only the secondactorcallee even for samefacing")
	cleanup(f)
	# Main passes authoritativeVMmode: a just-loadedEVENT may precede Viewmode sync.
	f=fixture();f.view.game_mode=1;f.view._actors.clear();f.view._actor_resource_stems.clear();f.view._refresh_actors()
	var mode1_other=f.view.unit_player(1);var mode1_other_label=mode1_other.label;f.battle.units[0].encode_u16(16,1);f.battle.units[0].encode_u16(38,0);f.view._refresh_actors();f.view._actor_resource_stems.erase(1);f.vm.mode=4
	f.vm._execute(31,[0,4])
	check(f.view.unit_player(0).label=="F.SET"and f.view.unit_player(0).apd.name=="CHAR_01V"and f.view._source_appearance_modes.get(0)==4,"authoritativeVM4 builds targetMODE4pose/resource while View wasMODE1")
	check(f.view.unit_player(1)==mode1_other and mode1_other.label==mode1_other_label,"authoritative targetrebuild doesnot mode-switch or reconstruct otheractors")
	cleanup(f)
	# ActualE3-like enemy prehook: actionmarker changes do not invoke4196F0.
	f=fixture();f.battle.units[18]=f.data.encode_unit({"kind":18,"definition_id":1,"control":6,"x":7,"y":4,"move_marker":1,"action_marker":0});f.view.game_mode=1;f.view._actors.clear();f.view._actor_resource_stems.clear();f.view._refresh_actors()
	var standing=f.view.unit_player(18);standing.advance(50);var stand_epoch: int=standing._epoch;var untouched=f.view.unit_player(0)
	f.battle.units[18].encode_u32(96,1);f.view._refresh_actors()
	check(f.view.unit_player(18)==standing and standing.label=="F.STAND"and standing.flags==3 and standing._epoch==stand_epoch,"marker-only implicitMODE1sync preserves the actualselectedSTANDanimation beforehookmodechange")
	f.view.set_game_mode(4)
	check(f.view.unit_player(18)==standing and standing.label=="F.STAND"and standing.flags==3 and standing._epoch==stand_epoch,"mode-onlyhookentry preserves actualSTANDplayer/flags/epoch despite changedactionmarker")
	f.vm._execute(41,[90,1]);f.vm._emit_actor_state();standing.advance(151)
	check(f.view.unit_player(18)==standing and standing.flags==3 and standing.frame==1 and standing.busy,"state-onlyVMsync keeps the selectedSTANDanimation running instead of freezingSET")
	f.vm._execute(31,[18,4]);check(f.view.unit_player(18)!=standing and f.view.unit_player(18).label=="F.SET"and f.view.unit_player(18).flags==128 and f.view.unit_player(0)==untouched,"actual4196F0 subsequently uses markers for freshSET128 and preservesotheractors")
	cleanup(f)
	# Definition7 is a nativeearlyreturn; body,shadow,metadata andplayback survive.
	f=fixture();var t:=create_temp(f);f.vm._system(2,[t,1]);var temp=f.view.unit_player(t);var tsh=f.view._unit_shadow(t);temp.dither=6;temp.base_flip=2;var label=temp.label;f.vm._execute(31,[t,4])
	check(f.view.unit_player(t)==temp and f.view._unit_shadow(t)==tsh and temp.label==label and temp.dither==6 and temp.base_flip==2,"definition7 refresh preserves Unit70/74 and actualplayback")
	check(f.vm.actor_sprites[t].has("palette_start")and f.vm.actor_sprites[t].has("label"),"definition7 earlyreturn preserves originalVMdisplaymetadata")
	f.vm._sprite(1,{"stem":"CHAR_02V","label":"F.POINT","play":true});check(f.view.unit_player(t)==temp,"definition7 state-replay retains its currentplayer")
	cleanup(f)
	# MissingV and actualsheet-loadfailure must not erase oldUnit70 or itsmetadata.
	for failure in ["missingV","missingSheet","missingA"]:
		f=fixture();f.vm._execute(8,[0,"F.POINT",0]);var old=f.view.unit_player(0);old.dither=4;var old_shadow=f.view._unit_shadow(0);var old_label=old.label;f.view._actor_resource_stems.erase(1)
		if failure=="missingV":assets.fail_apds["CHAR_01V"]=true;assets.manifest.apds.erase("CHAR_01V")
		elif failure=="missingSheet":assets.bad_sheets["CHAR_01V"]=true
		else:assets.fail_apds["CHAR_01A"]=true;f.view.game_mode=1;f.vm.mode=1
		var old_flags: int=old.flags;f.vm._execute(31,[0,2])
		check(f.view.unit_player(0)==old and old.label==old_label and old.dither==4 and old.flags==old_flags,"%s failedcallee preserves actualUnit70playback"%failure)
		check(f.view._unit_shadow(0)==old_shadow and f.vm.actor_sprites[0].label=="F.POINT","%s failedcallee preserves Unit74 and VMcommandmetadata"%failure)
		check(f.battle.units[0].decode_u16(6)==2,"%s stillconsumes/writes logicalfacing beforeloadfailure"%failure)
		f.vm._sprite(1,{"stem":"CHAR_02V","label":"F.POINT","play":true});check(f.view.unit_player(0)==old,"%s lateremit doesnot replay/loss the preservedplayer"%failure)
		for repeat in 3:f.vm._changed();f.view._refresh_actors();f.vm._emit_actor_state()
		check(f.view.unit_player(0)==old and old.label==old_label and old.dither==4,"%s repeatedchanged/eagerrefresh/stateemit preserve the sameplayback"%failure)
		cleanup(f)
	# FailedMODE4refresh must not let an oldMODE1owner reacquire A during eager sync.
	f=fixture();f.vm._system(43,[0]);var held_dead=f.view.unit_player(0);f.view._actor_resource_stems.erase(1);assets.fail_apds["CHAR_01V"]=true;assets.manifest.apds.erase("CHAR_01V");f.vm._execute(31,[0,4])
	for repeat in 3:f.vm._changed();f.view._refresh_actors();f.vm._emit_actor_state()
	check(f.view.unit_player(0)==held_dead and held_dead.label.begins_with("F.DEAD")and f.view._source_appearance_modes.get(0)==1,"failedMODE4refresh preserves priorMODE1body/owner across eager updates")
	check(not f.view._actor_resource_stems.has(1),"failedsource call doesnot implicitly populate an alternateMODE1resourcecache")
	assets.fail_apds.clear();assets.manifest.apds["CHAR_01V"]="own";f.vm._execute(31,[0,4]);check(not f.view._source_refresh_holds.has(0)and f.view.unit_player(0)!=held_dead,"a laterreal successfulrefresh ends failed-handleownership")
	cleanup(f)
	# Validresource+missinganimation is not loadfailure: oldbody isfreed and newblankremains.
	f=fixture();var label_old=f.view.unit_player(0);assets.no_default["CHAR_01V"]=true;f.vm._execute(31,[0,4]);var missing_label=f.view.unit_player(0)
	check(missing_label!=label_old and missing_label.frame==-1 and not missing_label.visible,"missingdefaultanimation retains the newunplayedallocation, not the oldpose")
	cleanup(f)
	# ExplicitUnit74 release and SYS43 modeownership end at the trueper-unitcallee.
	f=fixture();f.vm._system(2,[0,0]);check(f.view._unit_shadow(0)==null,"ordinaryshadow is explicitlyreleased")
	f.vm._execute(31,[0,4]);check(f.view._unit_shadow(0)!=null and f.view._unit_shadow(0).label=="MIDDLE.M","sentinelrebuild recreates a normalUnit74")
	f.vm._system(43,[0]);check(f.view._source_appearance_modes.get(0)==1,"fixture has sourceMODE1DEADownership")
	f.vm._execute(31,[0,4]);check(f.view._source_appearance_modes.get(0)==4 and f.view.unit_player(0).label=="F.SET","trueMODE4callee ends the MODE1appearanceowner")
	cleanup(f)
	# SYS5 refreshesselectedoccupiedpartyonly; selectedtemporaryNPC isnot implicitlyshown.
	f=fixture();f.vm._execute(8,[0,"F.POINT",0]);var previous=f.view.unit_player(0);var other=f.view.unit_player(1);f.view.refresh_calls.clear();f.vm._system(5,[0])
	check(slots(f.view)==[0]and f.view.unit_player(0)!=previous,"SYS5 rebuilds only its selectedpartyUnit")
	check(f.view.unit_player(1)==other and not other.visible,"SYS5 hidesotherparty without rebuilding them")
	t=create_temp(f);var hidden_npc=f.view.unit_player(t);hidden_npc.visible=false;f.view.refresh_calls.clear();f.vm._system(5,[t]);check(slots(f.view).is_empty()and not hidden_npc.visible,"SYS5 NPCanchor doesnot refresh or unhide it")
	cleanup(f)
	# SYS15 conditionalrebuild; nonqualifyingvisibility mustnotallocate anything.
	f=fixture();f.battle.units[0].encode_u16(16,9);f.view._refresh_actors();f.vm._system(2,[0,1]);var hidden_shadow=f.view._unit_shadow(0);f.view.refresh_calls.clear();f.vm._system(15,[0,1])
	check(slots(f.view)==[0]and f.battle.units[0].decode_u16(16)==0,"SYS15 qualifyingHIDE→normal invokesonecallee")
	check(f.view._unit_shadow(0)!=hidden_shadow and f.view._unit_shadow(0).label=="MIDDLE.M","SYS15 replaces explicitUnit74 when the originalcallee qualifies")
	f.view.refresh_calls.clear();var body=f.view.unit_player(0);f.vm._system(15,[0,0]);f.vm._system(15,[0,1]);check(slots(f.view).is_empty()and f.view.unit_player(0)==body,"ordinaryshow/hide neverrebuilds the body")
	f.battle.units[0].encode_u16(16,9);f.battle.units[0].encode_u16(18,1);f.view.refresh_calls.clear();f.vm._system(15,[0,1]);check(slots(f.view).is_empty()and f.battle.units[0].decode_u16(16)==9,"SYS15 control1exception retainsstate9 and no explicitrebuild")
	cleanup(f)
	# SYS16 faces/rebuilds alloccupiedparty exceptanchor, includingunchangeddirection.
	f=fixture();t=create_temp(f)
	for i in [0,1]:f.battle.units[i].encode_u16(6,3);f.vm._execute(8,[i,"B.POINT",0])
	var a=f.view.unit_player(0);var b=f.view.unit_player(1);var anchor=f.view.unit_player(t);f.view.refresh_calls.clear();f.vm._system(16,[t])
	check(slots(f.view)==[0,1]and f.view.unit_player(0)!=a and f.view.unit_player(1)!=b,"SYS16 rebuildsbothalready-facingpartyUnits")
	check(f.view.unit_player(t)==anchor,"SYS16 leaves its NPCanchor and empty slots untouched")
	f.view.refresh_calls.clear();f.vm._system(16,[0]);check(slots(f.view)==[1],"SYS16 excludes the selectedpartyanchor")
	cleanup(f)
	# SYS18 rebuildsonly occupiedstate9 units onshow, irrespectivecontrol1.
	f=fixture();f.battle.units[0].encode_u16(16,9);f.battle.units[0].encode_u16(18,1);f.view._refresh_actors();var other18=f.view.unit_player(1);f.view.refresh_calls.clear();f.vm._system(18,[0]);check(slots(f.view).is_empty(),"SYS18hide neverrebuilds anyUnit")
	f.vm._system(18,[1]);check(slots(f.view)==[0]and f.battle.units[0].decode_u16(16)==0,"SYS18show rebuildsonly HIDE,withnoSYS15control1exception")
	check(f.view.unit_player(1)==other18,"SYS18show doesnot refresh normaloccupiedparty")
	cleanup(f)
	# Remainingdirectcallees and their logicalfield scopes.
	for selector in [3,17,36]:
		f=fixture();var old=f.view.unit_player(0);f.view.refresh_calls.clear();f.vm._system(selector,[0,0]if selector==3 else[0])
		check(slots(f.view)==[0]and f.view.unit_player(0)!=old,"SYS%d forwards exactlyone realcallee"%selector)
		if selector==17:check(f.battle.units[0].decode_u16(0)==8 and f.battle.units[0].decode_u16(38)==0 and f.battle.units[0].decode_u16(16)==1,"SYS17 kind/HP/statewrites precede itscallee")
		if selector==36:check(f.battle.units[0].decode_u16(16)==8,"SYS36 state8write precedes itscallee")
		cleanup(f)
	# SYS42's explicitpre-release differs from ordinaryfailedloadpreservation.
	for missing in [false,true]:
		f=fixture();f.vm.context_actor=0;f.vm._execute(8,[0,"F.POINT",0]);var old=f.view.unit_player(0)
		if missing:assets.fail_apds["CHAR_64V"]=true
		f.vm._system(42,[]);check(f.battle.units[0].decode_u16(2)==64 and f.view.refresh_calls[-1].release_first,"SYS42 usescontextactor and source41AB30pre-release")
		if missing:
			check(f.view.unit_player(0)==null and f.view._unit_shadow(0)==null,"SYS42failedreplacement cannotretainoldreleasedhandles")
			f.vm._sprite(1,{"stem":"CHAR_02V","label":"F.POINT","play":true});check(f.view.unit_player(0)==null,"SYS42releasedbody isnot revived by anotherstateemit")
		else:check(f.view.unit_player(0)!=old and f.view.unit_player(0).apd.name=="CHAR_64V","SYS42success allocatesthe newdefinition resource withoutclearingothers")
		cleanup(f)
	# Activejobskeep schedule whileobsolete snapshots cannotundo an actualrebuild.
	f=fixture();f.vm.jobs.play_single(0,"CHAR_01V",Vector2i(4,6),"F.POINT",10000,{"player_override":f.view.unit_player(0)});var job=f.vm.jobs.jobs[0];var active_old=f.view.unit_player(0);f.vm._execute(31,[0,4]);var rebuilt=f.view.unit_player(0)
	check(f.vm.jobs.jobs[0]==job and f.vm.jobs.is_busy(0),"truecallee doesnot cancel an activejob schedule")
	check(rebuilt!=active_old and rebuilt.label=="F.SET","activejob snapshot cannot reselect the freedoldpose")
	f.vm._emit_actor_state();check(f.view.unit_player(0)==rebuilt,"replayedactivejob snapshot binds the currentUnit70")
	cleanup(f)
	var report={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored indexedAPDs/unitrecords; truecallee descriptors/actualraster;nooriginalassets","limits":"nativephysicalpoolindex-reuse/activejobnextstep timing not asserted"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
