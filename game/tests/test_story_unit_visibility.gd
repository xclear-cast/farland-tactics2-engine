extends SceneTree
## Self-authored APDs/units only. Test source Unit-family bits, not render routing.
const View=preload("res://scripts/render/ft2_battle_view.gd")
const VM=preload("res://scripts/scenario/ft2_vm.gd")
const Jobs=preload("res://scripts/scenario/ft2_actor_jobs.gd")

class SyntheticAssets extends FT2IndexedAssets:
	func _init() -> void:
		manifest={"apds":{"CHAR_01V":"own","CHAR_01A":"own","SYSTEM":"own","OWN_TEMP":"own"}}
	func apd(stem: String) -> Dictionary:
		var still:={"groups":[{"move":[0,0],"velocity":[0,0],"steps":[[0,90,0,-1,0,0]]}]}
		var motion:={"groups":[{"move":[5,0],"velocity":[0.03,0],"steps":[[0,60,0,-1,0,0],[1,60,0,-1,0,0]]}]}
		var animations:={}
		for label in ["F.SET","B.SET","F.STAND","B.STAND","F.COMPLETE","B.COMPLETE","MIDDLE.M","SILENCE","F.SWEAT","B.SWEAT"]:animations[label]=still.duplicate(true)
		animations["F.ACT"]=motion
		return {"name":stem,"sheets":[],"parts":[],"frames":[{"parts":[],"pivot":0,"bounds":[0,0,2,2]},{"parts":[],"pivot":0,"bounds":[0,0,2,2]}],"animations":animations}

class SyntheticData:
	extends RefCounted
	var assets
	func appearance_definition(value: int) -> int:return value
	func load_apd(stem: String) -> Dictionary:return assets.apd(stem)
	func load_table(_name: String) -> Array:
		var rows: Array=[]
		for id in 8:rows.append({"id":id,"shadow_size_selector":2})
		return rows
	func raw_table(_name: String) -> PackedByteArray:
		var bytes:=PackedByteArray();bytes.resize(56);bytes.fill(0);return bytes
	func encode_unit(values: Dictionary) -> PackedByteArray:
		var bytes:=PackedByteArray();bytes.resize(124);bytes.fill(0)
		for pair in [["kind",0],["definition_id",2],["direction",6],["state",16],["control",18]]:bytes.encode_u16(pair[1],int(values.get(pair[0],0)))
		for pair in [["x",8],["y",12],["move_marker",92],["action_marker",96]]:bytes.encode_u32(pair[1],int(values.get(pair[0],0)))
		return bytes
	func decode_unit(bytes: PackedByteArray,slot: int) -> Dictionary:
		var row:={"slot":slot}
		for pair in [["kind",0],["definition_id",2],["direction",6],["state",16],["control",18],["weapon",20],["armor",22],["accessory1",24],["accessory2",26]]:row[pair[0]]=bytes.decode_u16(pair[1])
		for pair in [["x",8],["y",12],["move_marker",92],["action_marker",96]]:row[pair[0]]=bytes.decode_s32(pair[1])
		return row

class SyntheticBattle:
	extends RefCounted
	var units: Array=[]
	func refresh_context() -> void:pass

class SceneSpy:
	extends RefCounted
	var events: Array=[]
	var view
	func start(selector: int) -> bool:
		events.append({"op":"scene_start","selector":selector,"body_visible":view.unit_player(0).visible})
		return true

class UnrelatedMagic:
	extends RefCounted
	var caster: Dictionary={}

var checks:=0
var failures: Array[String]=[]
var output:=""

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)

func player(assets,valid: bool=true,visible: bool=true):
	var result:=FT2APDPlayer.new()
	if valid:result.play(assets.apd("OWN_TEMP"),"F.ACT",0,1)
	result.visible=visible
	return result

func create_view():
	var assets:=SyntheticAssets.new();var data:=SyntheticData.new();data.assets=assets
	var battle:=SyntheticBattle.new()
	for slot in 50:battle.units.append(data.encode_unit({}))
	battle.units[0]=data.encode_unit({"kind":1,"definition_id":1,"direction":0,"state":6,"control":7,"x":6,"y":9})
	battle.units[1]=data.encode_unit({"kind":100,"definition_id":7,"control":1,"x":3,"y":7})
	var view=View.new();view.assets=assets;view.data=data;view.battle=battle;view.game_mode=4;view._skip_effect_animation=true
	view._refresh_actors()
	return view

func properties(p) -> Dictionary:
	return {"object":p.get_instance_id(),"frame":p.frame,"label":p.label,"flags":p.flags,"mode":p.state_mode,"offset":p.offset,"base_flip":p.base_flip,"dither":p.dither,"busy":p.busy,"apd":p.apd.duplicate(true)}

func test_handles() -> void:
	var view=create_view();var assets=view.assets
	var base=view._actors[0];var body=base.player;var shadow=base.shadow;var icon=base.icon
	check(body.frame>=0 and shadow.frame>=0 and icon.frame>=0,"fixture has three valid native-family handles")
	var snapshots:=[properties(body),properties(shadow),properties(icon)]
	var units: Array=view.battle.units.duplicate(true);var resources: Dictionary=view._actor_resource_stems.duplicate(true)
	view.set_source_unit_family_visible(false)
	check(not body.visible and not shadow.visible and not icon.visible,"hide updates body, shadow and status icon independently")
	check([properties(body),properties(shadow),properties(icon)]==snapshots,"hide changes only visibility, not player identity or playback metadata")
	check(view.battle.units==units and view._actor_resource_stems==resources and view._actor_cache_generation==0,"hide leaves unit bytes, resource cache and generation intact")
	body.visible=false;shadow.visible=false;icon.visible=false
	view.set_source_unit_family_visible(true)
	check(body.visible and shadow.visible and icon.visible,"show force-enables every valid handle, including an already hidden icon")
	check([properties(body),properties(shadow),properties(icon)]==snapshots,"show leaves frame/flags/offset/dither/resource/playback unchanged")
	var blank_body=player(assets,false,true);var blank_icon=player(assets,false,false)
	view._script={"players":{0:{"player":blank_body}}};view._script_unit78[0]=blank_icon
	body.visible=true;icon.visible=true
	view.set_source_unit_family_visible(false)
	check(blank_body.visible and not blank_icon.visible,"hide skips both visible and invisible allocated frame-minus-one objects")
	check(body.visible and icon.visible,"replaced stale base body/icon are outside current Unit70/Unit78 ownership")
	check(not shadow.visible,"a valid shadow is hidden even when current body and icon are blank")
	view.set_source_unit_family_visible(true)
	check(blank_body.visible and not blank_icon.visible and shadow.visible,"show retains blank bits while independently showing a valid shadow")
	view._apply_script_actor_properties({"id":0,"command_serial":1,"visible":false,"changed_fields":["visible"]})
	check(blank_body.visible and not blank_icon.visible and not shadow.visible,"fresh per-unit global hide applies the same independent frame guard")
	var temp=player(assets);var overlay=player(assets)
	view._script.players[1]={"player":temp};view._script_unit78[1]=overlay
	var outside=player(assets);view._script.players[50]={"player":outside}
	var magic=UnrelatedMagic.new();var fx=player(assets);magic.caster={"player":fx};view.magic=magic
	var scene_fx=player(assets);view._result_players=[scene_fx]
	view.set_source_unit_family_visible(false)
	check(not temp.visible and not overlay.visible,"script-only definition7 current body/Unit78 are included")
	check(fx.visible and scene_fx.visible,"independent magic and result temporaries are excluded")
	check(outside.visible,"the source loop has exactly fifty Unit slots")
	# One object may be aliased by several views of the same current handle.
	view._script.players[1].player=shadow;view._script_unit78[1]=shadow
	view.set_source_unit_family_visible(true)
	check(shadow.visible,"aliasing current handles does not alter force-show semantics")
	var new_player=player(assets);view._script.players[2]={"player":new_player}
	check(new_player.visible,"a newly allocated handle does not inherit a previous hide policy")
	view.magic=null;view.free()

func test_event_replay() -> void:
	var view=create_view();var vm=VM.new();vm.data=view.data;vm.battle=view.battle;vm.mode=4;vm.actor_cache_mode=4
	vm.actor_changed.connect(view.set_script_state)
	vm._sprite(1,{"stem":"OWN_TEMP","label":"F.ACT","flags":1,"play":true,"visible":true})
	var temp=view.unit_player(1)
	vm._sprite(0,{"visible":true,"shadow_visible":true})
	var body=view.unit_player(0);var shadow=view._actors[0].shadow;var icon=view._actors[0].icon
	view.set_source_unit_family_visible(false);vm._emit_actor_state();vm._emit_actor_state()
	check(not temp.visible,"ordinary script record does not replay old visible=true over a later hide")
	check(not body.visible and not shadow.visible and not icon.visible,"stale global/shadow metadata does not undo source hide")
	vm._sprite(0,{"visible":false,"shadow_visible":false});vm._sprite(1,{"visible":false})
	view.set_source_unit_family_visible(true);vm._emit_actor_state()
	check(view.unit_player(0).visible and shadow.visible and icon.visible and temp.visible,"stale visible=false cannot undo source force-show")
	vm._sprite(0,{"shadow_visible":false})
	check(not shadow.visible and view.unit_player(0).visible,"a fresh shadow-only command still acts immediately")
	view.set_source_unit_family_visible(true);vm._sprite(0,{"priority":7})
	check(shadow.visible,"a new unrelated command does not replay inherited shadow metadata")
	view.set_source_unit_family_visible(false)
	vm._sprite(1,{"label":"F.STAND","flags":128})
	check(view.unit_player(1)==temp and not temp.visible,"same-resource animation change retains the current pool visibility bit")
	vm._sprite(0,{"visible":true})
	check(view.unit_player(0).visible and shadow.visible and icon.visible,"fresh explicit global show remains supported")
	vm._execute(33,[0]);var blank=view.unit_player(0)
	check(blank.frame==-1 and not blank.visible,"OP33 blank body is allocated but unplayed")
	view.set_source_unit_family_visible(true)
	check(view.unit_player(0)==blank and blank.frame==-1 and not blank.visible,"force-show never selects a pose for a blank body")
	check(view._actors[0].shadow.visible,"force-show treats a valid shadow independently from a blank body")
	view.set_source_unit_family_visible(false)
	vm._execute(8,[0,"F.ACT",1])
	check(view.unit_player(0).visible and view._actors[0].shadow.visible,"OP8 explicitly shows body and shadow after source hide")
	check(not view._actors[0].icon.visible,"OP8 does not implicitly show a hidden icon")
	vm._execute(33,[0]);var jobs=Jobs.new(view.data)
	check(jobs.play_single(0,"CHAR_01V",Vector2i(6,9),"F.ACT",0,{"player_override":view.unit_player(0)}),"an actor job starts from the current blank body")
	check(view.unit_player(0).visible and not view._actors[0].shadow.visible,"job first-play shows only the body, with no permanent source hide latch")
	vm.actor_changed.disconnect(view.set_script_state);view.free()

func test_mode_and_lifecycle() -> void:
	var view=create_view();var vm=VM.new();vm.data=view.data;vm.battle=view.battle;vm.mode=4;vm.actor_cache_mode=4
	vm.actor_changed.connect(view.set_script_state)
	vm._execute(33,[0]);var body=view.unit_player(0);var shadow=view._actors[0].shadow;var icon=view._actors[0].icon
	view.set_source_unit_family_visible(false)
	var snapshots:=[properties(body),properties(shadow),properties(icon)]
	view.set_game_mode(8)
	check(view.unit_player(0)==body and view._actors[0].shadow==shadow and view._actors[0].icon==icon,"mode-only entry retains all three native handles")
	check([properties(body),properties(shadow),properties(icon)]==snapshots,"mode-only entry does not revive a default animation or reset player metadata")
	vm.mode=8;vm._emit_actor_state();view.set_game_mode(4);vm.mode=4;vm._emit_actor_state()
	check(body.frame==-1 and not body.visible and not shadow.visible and not icon.visible,"mode-only return and stale state retain blank/hidden family bits")
	check(view._actors[0].shadow==shadow and view._actors[0].icon==icon,"mode-only return retains secondary handle identity")
	vm.mode=8;vm._emit_actor_state();vm.mode=4;vm._emit_actor_state()
	check(view.unit_player(0)==body and body.frame==-1 and view._actors[0].shadow==shadow and not shadow.visible,"actor-state mode transitions retain hidden/blank handles without a preceding set_game_mode call")
	view.set_source_unit_family_visible(true)
	check(not body.visible and shadow.visible and icon.visible,"post-scene force-show preserves the blank guard on the same handle")
	view._refresh_actor(0)
	check(view._actors[0].shadow!=shadow and view._actors[0].icon!=icon,"explicit appearance reconstruction still creates new secondary handles")
	check(view._actors[0].player.frame>=0 and view._actors[0].player.visible,"explicit appearance reconstruction retains its own native show behavior")
	# A cache release is a lifecycle boundary, rather than a remembered hidden flag.
	view.set_source_unit_family_visible(false)
	vm.actor_sprites.clear();vm.actor_cache_generation+=1;vm._emit_actor_state()
	check(view.unit_player(0)!=body and view.unit_player(0).frame>=0 and view.unit_player(0).visible,"new cache generation constructs a new visible handle normally")
	check(view._actors[0].shadow.visible and view._actors[0].icon.visible,"new secondary handles do not inherit old visibility policy")
	vm.actor_changed.disconnect(view.set_script_state);view.free()

func test_vm_order() -> void:
	var view=create_view();var vm=VM.new();vm.data=view.data;vm.battle=view.battle;vm.mode=4
	var events: Array=[];var scene:=SceneSpy.new();scene.events=events;scene.view=view;vm.scene=scene
	vm.palette_requested.connect(func(request):events.append({"op":str(request.kind),"context":vm.alternate_surface,"mode":vm.mode,"visible":view.unit_player(0).visible}))
	vm.source_commands_requested.connect(func(commands):
		for command in commands:
			events.append({"op":str(command.op),"enabled":command.get("enabled"),"context":vm.alternate_surface,"mode":vm.mode})
			view.service_script_commands([command]))
	vm.scene_requested.connect(func(selector):events.append({"op":"scene_requested","selector":selector}))
	check(vm._execute(52,[3]),"OP52 yields after source hide and scene construction")
	var names: Array=[]
	for event in events:names.append(event.op)
	check(names==["save_script_base","actor_visibility_all","scene_start","scene_requested"],"OP52 order is BASE save, family hide, scene start, notification")
	check(events[0].visible and events[0].context==false and events[1].enabled==false and events[1].mode==4,"hide is issued against the preceding story state")
	check(not events[2].body_visible and vm.mode==8 and vm.alternate_surface,"scene starts only after current family bits are hidden")
	events.clear();check(not vm._execute(51,[]),"OP51 remains non-yielding")
	names.clear()
	for event in events:names.append(event.op)
	check(names==["restore_script_base","actor_visibility_all","restore"],"OP51 order is BASE restore, family force-show, surface restore")
	check(events[0].visible==false and events[0].context and events[1].enabled and events[2].context,"restore/show execute before alternate context is cleared")
	check(view.unit_player(0).visible and view._actors[0].shadow.visible and view._actors[0].icon.visible and not vm.alternate_surface,"OP51 completes force-show and context cleanup")
	events.clear();vm._bitmap_sizes["BMP/OWN.BMP"]=Vector2i(2,2)
	# The fixture need not draw a bitmap: inspect source signals only here.
	for connection in vm.get_signal_connection_list("source_commands_requested"):vm.disconnect("source_commands_requested",connection.callable)
	vm.source_commands_requested.connect(func(commands):
		for command in commands:events.append({"op":str(command.op)}))
	view.set_source_unit_family_visible(false);vm._execute(50,["own",0])
	var visibility_events:=0
	for event in events:
		if event.op=="actor_visibility_all":visibility_events+=1
	check(visibility_events==0 and not view.unit_player(0).visible,"OP50 opaque bitmap mode does not hide/show Unit-family bits")
	check(view.unsupported.is_empty(),"new source operation is consumed by the real View dispatcher")
	for signal_name in ["palette_requested","source_commands_requested","scene_requested"]:
		for connection in vm.get_signal_connection_list(signal_name):vm.disconnect(signal_name,connection.callable)
	view.free()

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--unit-visibility-output="):output=arg.trim_prefix("--unit-visibility-output=")
	call_deferred("run")

func run() -> void:
	test_handles();test_event_replay();test_mode_and_lifecycle();test_vm_order()
	check(checks>=50,"all fixture groups reached their checks")
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored APD datasets, unit bytes, and scene observer only"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
