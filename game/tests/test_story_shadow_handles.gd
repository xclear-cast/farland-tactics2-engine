extends SceneTree
## Self-authored APD frames/unit records; VM->View SYS2/SYS43 handle lifecycle.
const View=preload("res://scripts/render/ft2_battle_view.gd")
const VM=preload("res://scripts/scenario/ft2_vm.gd")
const Jobs=preload("res://scripts/scenario/ft2_actor_jobs.gd")
class RecordingView extends View:
	var draws: Array=[]
	func _draw_apd(player: FT2APDPlayer,anchor: Vector2i,policy: String="actor",clip: Rect2i=Rect2i(0,0,640,480),remaps: Variant=null,installs: Array=[]) -> Rect2i:
		draws.append({"player":player,"anchor":anchor,"label":player.label,"policy":policy});return super._draw_apd(player,anchor,policy,clip,remaps,installs)
	func _redraw_map(_a: int,_b: int,_c: Array) -> void:pass
	func _draw_selection() -> void:pass
	func _draw_facing_cursor() -> void:pass
class OwnAssets extends FT2IndexedAssets:
	var folder:=""
	func _init() -> void:manifest={"images":{},"apds":{"SYSTEM":"own","OWN_TEMP":"own","CHAR_01V":"own","CHAR_02V":"own","CHAR_01A":"own","CHAR_02A":"own"}}
	func add_image(key: String) -> void:
		var pal:=PackedByteArray();pal.resize(768);pal.fill(27)
		var ip:=folder.path_join(key.get_file()+".idx");var pp:=folder.path_join(key.get_file()+".pal")
		var f:=FileAccess.open(ip,FileAccess.WRITE);f.store_buffer(PackedByteArray([10,11,12,13]));f.close();f=FileAccess.open(pp,FileAccess.WRITE);f.store_buffer(pal);f.close();manifest.images[key]={"width":2,"height":2,"indices":ip,"palette":pp}
	func still(frame: int) -> Dictionary:return {"groups":[{"move":[0,0],"velocity":[0,0],"steps":[[frame,100,0,-1,0,0]]}]}
	func apd(stem: String) -> Dictionary:
		var anim: Dictionary={};var frames: Array=[]
		for i in 5:frames.append({"parts":[0],"pivot":0,"bounds":[0,0,2,2]})
		for name in ["F.SET","B.SET","F.STAND","B.STAND","F.DEAD","B.DEAD","F.DEAD#","B.DEAD#","F.ACT","SILENCE","F.SWEAT"]:anim[name]=still(0)
		for spec in [["SMALL.M",1],["MIDDLE.M",2],["LARGE.M",3],["HUGE.M",4]]:anim[spec[0]]=still(spec[1])
		return {"name":stem,"sheets":["own/system.bmp"if stem=="SYSTEM"else"own/body.bmp"],"parts":[[0,0,0,2,2,0,0,255]],"frames":frames,"animations":anim}
class OwnData:
	extends RefCounted
	var assets
	func appearance_definition(id: int) -> int:return id
	func load_apd(stem: String) -> Dictionary:return assets.apd(stem)
	func load_table(_name: String) -> Array:
		var out: Array=[]
		for i in 8:out.append({"id":i,"shadow_size_selector":2})
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
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shadow-handles-output="):output=arg.trim_prefix("--shadow-handles-output=")
	call_deferred("run")
func draw(view: RecordingView) -> void:view.draws.clear();view._render(false)
func rendered(view: RecordingView,p: FT2APDPlayer) -> bool:return view.draws.any(func(row):return row.player==p)
func run() -> void:
	FT2Content.active=null
	var assets:=OwnAssets.new();assets.folder="user://own_shadow_handles_"+str(OS.get_process_id());DirAccess.make_dir_recursive_absolute(assets.folder);assets.add_image("own/system.bmp");assets.add_image("own/body.bmp")
	var data:=OwnData.new();data.assets=assets;var battle:=OwnBattle.new()
	for slot in 50:battle.units.append(data.encode_unit({}))
	battle.units[0]=data.encode_unit({"kind":1,"definition_id":1,"direction":1,"x":4,"y":6,"hp_max":40,"hp":40,"mp_max":12,"mp":12,"move_marker":1,"action_marker":1})
	battle.units[1]=data.encode_unit({"kind":2,"definition_id":2,"x":5,"y":6,"hp_max":30,"hp":30})
	var view:=RecordingView.new();view.data=data;view.assets=assets;view.battle=battle;view.palette=FT2Palette.new();view.surface=FT2IndexedSurface.new();view.physical=PassiveFX.new();view.magic=PassiveFX.new();view.environment=OwnEnvironment.new();view.game_mode=4;view._service_mode="test_handles";view.map_id=40;view.map={"base":[320,120],"side":16,"header":[0,0,0,0],"background":""}
	view._acquire_system_palette(assets.image("own/system.bmp",[[90,16,208],[10,64,144],[74,16,16]]));view._refresh_actors()
	var vm=VM.new();vm.data=data;vm.battle=battle;vm.jobs=Jobs.new(data);vm.mode=4;vm.previous_mode=9;vm.actor_cache_mode=4;vm.actor_player_query=Callable(view,"unit_player");vm.actor_changed.connect(view.set_script_state)
	# A sourceSYS2 enable only allocates when Unit74 isNULL; it never unhides an existinghandle.
	var default_shadow=view._unit_shadow(0);check(default_shadow!=null and default_shadow.label=="MIDDLE.M","ordinary fixture begins with race-selected masked shadow")
	default_shadow.visible=false;vm._system(2,[0,1])
	check(view._unit_shadow(0)==default_shadow and not default_shadow.visible,"enable with existinghiddenhandle neither replaces nor shows it")
	var logical_before: PackedByteArray=battle.units[0].duplicate();vm._system(2,[0,0])
	check(view._unit_shadow(0)==null and not view._actors[0].has("shadow"),"disable releases Unit74 instead of retaining an invisibleplayer")
	check(battle.units[0]==logical_before,"shadowhandle operations do not alter logicalUnitbytes")
	for i in 3:vm._emit_actor_state();view._refresh_actors()
	check(view._unit_shadow(0)==null,"releasedhandle survives implicitstate/appearance sync without recreation")
	vm._system(2,[0,1]);var large=view._unit_shadow(0)
	check(large!=null and large!=default_shadow,"enable afterrelease allocates a newUnit74handle")
	check(large.label=="LARGE.M"and large.flags==128 and large.visible,"explicit Unit74 uses fixedLARGE.M flags128, not the race shadow selector")
	vm._emit_actor_state();vm._emit_actor_state();check(view._unit_shadow(0)==large,"same commandserial delivery does not allocate twice")
	large.visible=false;vm._system(2,[0,1]);check(view._unit_shadow(0)==large and not large.visible,"new enablecommand still preserves an existinghiddenhandle")
	vm._system(2,[0,0]);view.set_source_unit_family_visible(false);vm._system(2,[0,1]);large=view._unit_shadow(0)
	check(large.visible,"new allocation is visible even after an earlierfamilyhide; no globalvisibilitylatch")
	# ActualOP13 definition7 temporary has no ordinaryactor record but can own Unit74.
	vm._create_actor(["OWN_TEMP",100,3,4],true);var temp: int=vm._actor(100);vm._execute(8,[temp,"F.ACT",0]);check(temp>=10 and not view._actors.has(temp),"temporaryfixture is definition7 and absent from ordinaryactorbuilder")
	check(view._unit_shadow(temp)==null,"newtemporary resource does not invent a shadow")
	vm._system(2,[temp,1]);var temporary_shadow=view._unit_shadow(temp)
	check(temporary_shadow!=null and temporary_shadow.label=="LARGE.M"and temporary_shadow.flags==128,"SYS2 creates a real shadow for definition7temporary")
	draw(view);check(rendered(view,temporary_shadow),"actualrenderer includes temporaryUnit74 with no ordinaryactor record")
	var shadow_draw: Dictionary=view.draws.filter(func(row):return row.player==temporary_shadow)[0]
	check(shadow_draw.anchor==view.world_to_screen(Vector2i(3,4))and shadow_draw.policy=="system","newtemporaryshadow starts at its logicalcell usingSYSTEMresource")
	var p: Vector2i=shadow_draw.anchor;check(view.surface.pixels[p.y*640+p.x]==144,"temporaryshadow reaches the actual indexedraster")
	view.set_source_unit_family_visible(false);check(not temporary_shadow.visible,"familyhide affects the real temporaryUnit74")
	view.set_source_unit_family_visible(true);check(temporary_shadow.visible,"familyshow affects existingtemporaryUnit74")
	vm._execute(33,[temp]);check(view._unit_shadow(temp)==temporary_shadow and not temporary_shadow.visible,"OP33 hides but doesnot release the existingUnit74")
	vm._system(2,[temp,1]);check(not temporary_shadow.visible,"SYS2enable cannot accidentally unhide OP33's retainedhandle")
	vm._execute(8,[temp,"F.ACT",0]);check(temporary_shadow.visible,"laterOP8 explicitly shows temporarybody and shadowfamily")
	vm._system(13,[temp,1]);check(temporary_shadow.dither_busy,"SYS13 dither includes explicittemporaryUnit74")
	vm._system(39,[]);check(not temporary_shadow.visible,"SYS39 hides temporaryUnit74 without releasing it")
	vm._system(2,[temp,0]);check(view._unit_shadow(temp)==null,"temporaryUnit74 can be released")
	view.set_source_unit_family_visible(true);check(view._unit_shadow(temp)==null,"familyshow doesnot recreate releasedtemporaryhandles")
	vm._system(2,[temp,1]);var next_temp_shadow=view._unit_shadow(temp);check(next_temp_shadow!=temporary_shadow and next_temp_shadow.visible,"temporary release/create has a newhandle and no stalevisibility")
	# Explicitnative4196F0 and sourcecachegeneration terminate customUnit74ownership.
	view.refresh_actor_visual(0);check(not view._script_unit74.has(0)and view._unit_shadow(0).label=="MIDDLE.M","true ordinary4196F0 replaces the explicitshadow with its normalrace-selectedhandle")
	vm._system(2,[temp,0]);var removed:=data.encode_unit({});battle.units[temp]=removed;view._refresh_actors();check(not view._script_unit74.has(temp),"unitremoval discards releasedhandle state before slotreuse")
	vm._create_actor(["OWN_TEMP",101,2,3],true);var temp2: int=vm._actor(101);vm._execute(8,[temp2,"F.ACT",0]);check(view._unit_shadow(temp2)==null,"reusedtemporaryslot doesnot inherit an earlierUnit74")
	vm._system(2,[temp2,1]);var cached=view._unit_shadow(temp2);vm.actor_sprites.clear();vm.actor_cache_generation+=1;vm._emit_actor_state();check(not view._script_unit74.has(temp2),"sourcecacheclear releases all explicitUnit74 handles")
	# SYS43 must buildtarget in sourceMODE1 even while EVENT remainsMODE4.
	var old_body=view.unit_player(0);var other_body=view.unit_player(1);var other_shadow=view._unit_shadow(1);var other_bytes: PackedByteArray=battle.units[1].duplicate();var resource_cache: Dictionary=view._actor_resource_stems.duplicate()
	vm._sprite(0,{"stem":"CHAR_01V","label":"F.ACT","flags":1,"play":true});var old_override=view.unit_player(0)
	vm.jobs.play_single(0,"CHAR_01V",Vector2i(4,6),"F.ACT",0,{"player_override":old_override});vm.jobs.advance(101);vm.actor_busy[0]=false
	var before43: PackedByteArray=battle.units[0].duplicate();vm._system(43,[0]);var corpse=view.unit_player(0)
	check(vm.mode==4 and vm.previous_mode==1 and view.game_mode==4,"SYS43 keeps EVENT4 but changes its savedreturnmode to1")
	check(battle.units[0].decode_u16(38)==0 and battle.units[0].decode_u16(42)==0 and battle.units[0].decode_u16(16)==1,"SYS43 writes exactlyHP0/MP0/state1")
	var expected: PackedByteArray=before43.duplicate();expected.encode_u16(38,0);expected.encode_u16(42,0);expected.encode_u16(16,1);check(battle.units[0]==expected,"SYS43 preserves all otherUnitfields and markers")
	check(corpse!=old_override and corpse!=old_body,"source41AB30/4196F0 replaces the targetbody handle")
	check(corpse.label.begins_with("F.DEAD")and corpse.visible,"mode1 rebuild selects actualDEAD even withinactive1/1 markers")
	check(view._source_appearance_modes.get(0)==1,"the source-created target retains its appearance-modeownership")
	check(view.unit_player(1)==other_body and view._unit_shadow(1)==other_shadow and battle.units[1]==other_bytes,"SYS43 doesnot rebuild or mode-switch otheractors")
	check(view._actor_resource_stems==resource_cache,"SYS43 keeps originalper-definitionAPDresources cached")
	check(not vm.jobs.jobs.has(0)and not vm.actor_busy.has(0),"releasing the targetbody invalidates its staleactorjob alias")
	for i in 3:vm._emit_actor_state();view._refresh_actors();view.set_game_mode(4)
	check(view.unit_player(0)==corpse and corpse.label.begins_with("F.DEAD"),"followingmode4eager synchronization doesnot revive the corpse asSET")
	view.set_game_mode(1);view.set_game_mode(4);check(view.unit_player(0)==corpse and corpse.label.begins_with("F.DEAD"),"a modechange alone doesnot replay a defaultpose")
	view.refresh_actor_visual(0);check(not view._source_appearance_modes.has(0),"a later explicit4196F0 ends the one-target source-modeoverride")
	check(view.unit_player(0).label=="F.SET","later realMODE4rebuild follows the actualsourceinactive-selector ratherthan a permanentDEADlatch")
	# A definition7 SYS43 releases its threehandles;419060 itselfearlyreturns fordefinition7.
	vm._system(2,[temp2,1]);var temp_body=view.unit_player(temp2);vm._system(43,[temp2]);check(view.unit_player(temp2)==null and view._unit_shadow(temp2)==null,"SYS43 on definition7 releasesbody/shadow without inventingdefaultpose")
	check(battle.units[temp2].decode_u16(2)==7,"definition7's logicalresource identity is preserved")
	# Releasing bodyhandles must not cancel an active logicalsource job.
	var active_player=view.unit_player(1)
	vm.jobs.play_single(1,"CHAR_02V",Vector2i(5,6),"F.ACT",10000,{"player_override":active_player});vm.actor_busy[1]=true
	var active_job=vm.jobs.jobs[1];var active_steps: Array=active_job.steps.duplicate(true)
	vm._system(43,[1]);var active_corpse=view.unit_player(1)
	check(vm.jobs.is_busy(1)and vm.jobs.jobs[1]==active_job and vm.jobs.jobs[1].steps==active_steps,"SYS43 preserves an active job's logicalschedule instead of cancelling it")
	check(vm.actor_busy.get(1,false),"SYS43 preserves the source activejob busy predicate")
	check(active_corpse!=active_player and active_corpse.label.begins_with("F.DEAD"),"activejob metadata cannot retain the releasedbody as Unit70")
	vm._emit_actor_state();vm._emit_actor_state()
	check(view.unit_player(1)==active_corpse and active_corpse.label.begins_with("F.DEAD"),"activejob snapshot re-delivery uses the currentUnit70 alias")
	vm.jobs.clear(1)
	# The last validUnit slot can own a shadow without any Unit70/modelrecord.
	battle.units[49]=data.encode_unit({"kind":4999,"definition_id":7,"control":1,"x":2,"y":2})
	vm._system(2,[49,1]);var last_shadow=view._unit_shadow(49)
	check(last_shadow!=null and view.unit_player(49)==null,"SYS2 supports all50validUnit slots, even with no currentbody")
	vm._system(15,[49,0]);check(not last_shadow.visible,"sourcefamilyhide still controls a shadow-onlyUnit")
	vm._system(15,[49,1]);check(last_shadow.visible,"sourcefamilyshow still controls a shadow-onlyUnit")
	vm._system(2,[49,0]);check(view._unit_shadow(49)==null,"last-slotUnit74 is genuinely released")
	check(vm.errors.is_empty()and vm.jobs.errors.is_empty(),"self-authored lifecycle finishes without VM or actorjoberrors")
	vm.actor_changed.disconnect(view.set_script_state);vm.actor_player_query=Callable();view.free()
	var report={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored2x2images/APDs/unitrecords; actualVM/sourcehandlecallbacks and actualindexedshadowrender"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output);var f:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
