extends SceneTree
## Self-authored APD/units only. Exercise the real VM -> View event lifecycle.
const View=preload("res://scripts/render/ft2_battle_view.gd")
const VM=preload("res://scripts/scenario/ft2_vm.gd")
const Jobs=preload("res://scripts/scenario/ft2_actor_jobs.gd")
class SyntheticAssets extends FT2IndexedAssets:
	var requested: Array[String]=[]
	func _init() -> void:
		manifest={"apds":{"CHAR_01A":"own","CHAR_01V":"own","CHAR_01X":"own","SYSTEM":"own","SYNTHETIC_TEMP":"own"}}
	func apd(stem: String) -> Dictionary:
		requested.append(stem)
		var still:={"groups":[{"move":[0,0],"velocity":[0,0],"steps":[[0,100,0,-1,0,0]]}]}
		var moving:={"groups":[{"move":[8,0],"velocity":[0.04,0],"steps":[[0,100,0,-1,0,0],[1,100,0,-1,0,0]]}]}
		return {"name":stem,"sheets":[],"parts":[],"frames":[{"parts":[],"pivot":0,"bounds":[0,0,1,1]},{"parts":[],"pivot":0,"bounds":[0,0,1,1]}],"animations":{"F.SET":still.duplicate(true),"F.STAND":still.duplicate(true),"F.ACT":moving,"MIDDLE.M":still.duplicate(true),"SILENCE":still.duplicate(true)}}
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
class SyntheticRules:
	extends RefCounted
	func construct(units: Array,descriptor: PackedByteArray,seeds: Array) -> Dictionary:
		var result:=units.duplicate()
		for slot in range(10,result.size()):
			if result[slot].decode_u16(0)==0:result[slot]=descriptor.duplicate();return {"units":result,"seeds":seeds.duplicate(),"slot":slot}
		return {"units":result,"seeds":seeds.duplicate(),"slot":-1}
class SyntheticBattle:
	extends RefCounted
	var units: Array=[]
	var rng: Array=[1,2,3]
	var rules=SyntheticRules.new()
	func refresh_context() -> void:pass

var checks:=0
var failures: Array[String]=[]
var output:=""

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)

func blank(player,label: String) -> void:
	check(player!=null,label+": allocated body exists")
	if player==null:return
	check(player.frame==-1 and player.state_mode==0 and player.flags==0,label+": allocated body has no selected frame or animation")
	check(not player.visible and not player.busy,label+": blank body is hidden and idle")

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sprite-output="):output=arg.trim_prefix("--sprite-output=")
	call_deferred("run")

func run() -> void:
	var assets:=SyntheticAssets.new();var data:=SyntheticData.new();data.assets=assets
	var battle:=SyntheticBattle.new()
	for slot in 50:battle.units.append(data.encode_unit({}))
	battle.units[0]=data.encode_unit({"kind":1,"definition_id":1,"direction":1,"x":8,"y":9,"move_marker":1,"action_marker":1})
	battle.units[1]=data.encode_unit({"kind":100,"definition_id":7,"control":1,"x":4,"y":5})
	var view=View.new();view.assets=assets;view.data=data;view.battle=battle;view.game_mode=4
	view._refresh_actors()
	check(view.unit_player(0).frame==0 and view.unit_player(0).visible,"fixture has a valid visible default SET pose")
	var vm=VM.new();vm.data=data;vm.battle=battle;vm.jobs=Jobs.new(data);vm.mode=4;vm.actor_cache_mode=4
	vm.actor_player_query=Callable(view,"unit_player")
	vm.actor_changed.connect(view.set_script_state)
	vm.jobs.changed.connect(vm._emit_actor_state);vm.jobs.cell_committed.connect(vm._job_cell);vm.jobs.finished.connect(vm.actor_finished)
	var old_body=view.unit_player(0)
	vm.actor_sprites[0]={"id":0,"stem":"CHAR_01V","label":"F.ACT","visible":true,"world":Vector2i(8,9),"player_override":old_body}
	vm.jobs.play_single(0,"CHAR_01V",Vector2i(8,9),"F.ACT",1,{"player_override":old_body})
	vm.jobs.advance(1);vm.jobs.advance(102);vm.jobs.advance(203)
	check(vm.jobs.jobs.has(0)and not vm.jobs.is_busy(0),"fixture retains an inactive completed job alias")
	var unit_before: PackedByteArray=battle.units[0].duplicate()
	vm._execute(7,[0,120]) # Fictional variant X; no original APD file is used.
	var reset=view.unit_player(0)
	blank(reset,"OP7 fallthrough")
	check(reset!=old_body,"OP7 replaces the previous body object")
	check(str(reset.apd.name)=="CHAR_01X","OP7 blank body retains the newly selected resource")
	check(view._actors[0].player==reset,"base Unit70 model aliases the replacement blank")
	check(not view._actors[0].shadow.visible,"OP7 hides the shadow")
	check(not vm.jobs.jobs.has(0)and not vm.actor_sprites[0].has("player_override"),"OP7 discards completed job and stale player override")
	check(battle.units[0]==unit_before,"OP7 preserves logical unit bytes")
	vm._emit_actor_state();view._refresh_actors();vm._emit_actor_state()
	check(view.unit_player(0)==reset and reset.frame==-1,"repeated state delivery does not allocate or revive default SET")
	vm._execute(8,[0,"F.ACT",1])
	var playing=view.unit_player(0)
	check(playing.frame==0 and playing.label=="F.ACT"and playing.visible and playing.busy,"OP8 explicitly selects and shows the requested animation")
	check(view._actors[0].shadow.visible,"OP8 shows the shadow")
	vm._execute(33,[0])
	var reset33=view.unit_player(0)
	blank(reset33,"OP33 hero")
	check(reset33!=playing and str(reset33.apd.name)=="CHAR_01X","OP33 replaces body while retaining current hero resource")
	check(battle.units[0]==unit_before,"OP33 preserves logical unit bytes")
	vm._emit_actor_state()
	check(view.unit_player(0)==reset33,"repeated OP33 snapshot reuses the same blank")
	check(vm.jobs.play_single(0,"CHAR_01X",Vector2i(8,9),"F.ACT",400,vm._job_metadata(0)),"actor job can start from a blank body")
	check(vm.jobs.jobs[0].player==reset33 and reset33.frame>=0 and reset33.visible,"successful actor-job first play shows the existing blank body")
	vm.jobs.clear(0)
	vm._sprite(1,{"stem":"SYNTHETIC_TEMP","label":"F.ACT","flags":1,"play":true,"body_visible":true})
	var temp_before: PackedByteArray=battle.units[1].duplicate()
	vm._execute(33,[1])
	blank(view.unit_player(1),"OP33 definition7 temporary actor")
	check(str(view.unit_player(1).apd.name)=="SYNTHETIC_TEMP"and battle.units[1]==temp_before,"temporary actor keeps its explicit resource and logical unit")
	check(not assets.requested.has("CHAR_07V"),"temporary actor does not invent a default definition7 resource")
	# Explicit body visibility must not implicitly show status icons or Unit78.
	var status_unit: PackedByteArray=battle.units[0].duplicate();status_unit.encode_u16(16,6);status_unit.encode_u16(18,7);status_unit.encode_u32(92,0);status_unit.encode_u32(96,0);battle.units[0]=status_unit
	view._refresh_actors()
	check(view._actors[0].has("icon"),"fixture creates a status icon")
	var icon=view._actors[0].icon;icon.visible=false
	var overlay:=FT2APDPlayer.new();overlay.apd=assets.apd("SYSTEM");overlay.frame=0;overlay.visible=false;view._script_unit78[0]=overlay
	vm._execute(33,[0]);vm._execute(8,[0,"F.ACT",0])
	check(view.unit_player(0).visible and view._actors[0].shadow.visible,"OP8 body and shadow visibility are restored independently")
	check(not icon.visible and not overlay.visible,"OP8 does not show status icon or Unit78")
	vm._emit_actor_state();vm._emit_actor_state()
	check(not icon.visible and not overlay.visible,"repeat body-only state does not replay global icon visibility")
	# Exercise OP33's existing missing-reference creation through actual decoding.
	vm._last_resource_stem="CHAR_01X";vm._raw=PackedByteArray([255,33,101,0]);vm.pc=0;vm.busy=true;vm.mode=4;vm.previous_mode=1
	vm._advance_event(0)
	var created: int=vm._actor(101)
	check(created>=10,"decoded OP33 creates a missing temporary actor")
	if created>=0:
		check(battle.units[created].decode_u16(2)==7 and battle.units[created].decode_u16(18)==1,"missing reference has definition7 and control1")
		blank(view.unit_player(created),"decoded missing OP33")
		check(str(view.unit_player(created).apd.name)=="CHAR_01X","missing reference uses last acquired resource")
	check(vm.errors.is_empty()and vm.jobs.errors.is_empty(),"synthetic lifecycle completes without VM/job errors")
	vm.actor_changed.disconnect(view.set_script_state);vm.actor_player_query=Callable();vm.jobs.changed.disconnect(vm._emit_actor_state);vm.jobs.cell_committed.disconnect(vm._job_cell);vm.jobs.finished.disconnect(vm.actor_finished)
	view.free()
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored APD datasets and unit bytes only"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
