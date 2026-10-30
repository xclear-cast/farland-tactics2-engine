extends SceneTree
## Self-authored coordinates and APDs; no original image, header or data path.
const Jobs=preload("res://scripts/scenario/ft2_actor_jobs.gd")
const VM=preload("res://scripts/scenario/ft2_vm.gd")
class RecordingView extends "res://scripts/render/ft2_battle_view.gd":
	var draws: Array=[]
	var anchor_calls: Array=[]
	var depth_calls: Array=[]
	func _script_shadow_anchor(slot: int,cell: Vector2i) -> Vector2i:
		var value:=super._script_shadow_anchor(slot,cell);anchor_calls.append({"slot":slot,"value":value});return value
	func _script_shadow_depth(slot: int,cell: Vector2i) -> int:
		var value:=super._script_shadow_depth(slot,cell);depth_calls.append({"slot":slot,"value":value});return value
	func _draw_apd(player: FT2APDPlayer,anchor: Vector2i,policy: String="actor",_clip: Rect2i=Rect2i(0,0,640,480),_remap_override: Variant=null,_installs: Array=[]) -> Rect2i:
		draws.append({"player":player,"anchor":anchor,"policy":policy,"label":player.label,"frame":player.frame});return Rect2i(anchor,Vector2i(2,2))
	func _redraw_map(_diagonal: int,_group: int,_dirty: Array) -> void:pass
	func _draw_selection() -> void:pass
	func _draw_facing_cursor() -> void:pass
class PassiveFX:
	extends RefCounted
	var suppressed: Dictionary={}
	var active:=false
	var caster: Dictionary={}
	var children: Array=[]
	func direct_render() -> bool:return false
class PassiveEnvironment:
	extends RefCounted
	func commands(_pos: Vector2i) -> Array:return []
class SyntheticAssets extends FT2IndexedAssets:
	func _init() -> void:manifest={"apds":{"CHAR_01V":"own","CHAR_01X":"own","SYSTEM":"own"}}
	func apd(stem: String) -> Dictionary:
		var animations: Dictionary={};var frames: Array=[]
		for index in 8:frames.append({"parts":[],"pivot":0,"bounds":[0,0,2,2]})
		for index in 4:
			var name: String=["SMALL","MIDDLE","LARGE","HUGE"][index]
			animations[name]=still(index*2);animations[name+".M"]=still(index*2+1)
		for name in ["F.SET","F.STAND"]:animations[name]=still(0)
		for name in ["F.ACT","F.MOVE1","F.MOVE2","B.MOVE1","B.MOVE2"]:
			animations[name]={"groups":[{"move":[8,0],"velocity":[0.04,0],"steps":[[0,100,0,-1,0,0],[1,100,0,-1,0,0]]}]}
		return {"name":stem,"frames":frames,"parts":[],"sheets":[],"animations":animations}
	func still(frame: int) -> Dictionary:return {"groups":[{"move":[0,0],"velocity":[0,0],"steps":[[frame,100,0,-1,0,0]]}]}
class SyntheticData:
	extends RefCounted
	var assets
	var shadow_size:=1
	func appearance_definition(value: int) -> int:return value
	func load_apd(stem: String) -> Dictionary:return assets.apd(stem)
	func load_table(_table: String) -> Array:return [{"shadow_size_selector":shadow_size},{"shadow_size_selector":shadow_size}]
	func raw_table(_table: String) -> PackedByteArray:
		var raw:=PackedByteArray();raw.resize(56);raw.fill(0);return raw
	func decode_unit(raw: PackedByteArray,slot: int) -> Dictionary:
		var result:={"slot":slot}
		for pair in [["kind",0],["definition_id",2],["direction",6],["state",16],["control",18],["weapon",20],["armor",22],["accessory1",24],["accessory2",26]]:result[pair[0]]=raw.decode_u16(pair[1])
		for pair in [["x",8],["y",12],["move_marker",92],["action_marker",96]]:result[pair[0]]=raw.decode_s32(pair[1])
		return result
class SyntheticBattle:
	extends RefCounted
	var units: Array=[]
	func refresh_context() -> void:pass

var checks:=0
var failures: Array[String]=[]
var output:=""
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func unit(kind: int,cell: Vector2i) -> PackedByteArray:
	var raw:=PackedByteArray();raw.resize(124);raw.fill(0);raw.encode_u16(0,kind);raw.encode_u16(2,1);raw.encode_u32(8,cell.x);raw.encode_u32(12,cell.y);raw.encode_u32(92,1);raw.encode_u32(96,1);return raw
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shadow-output="):output=arg.trim_prefix("--shadow-output=")
	call_deferred("run")
func run() -> void:
	var assets:=SyntheticAssets.new();var data:=SyntheticData.new();data.assets=assets
	var battle:=SyntheticBattle.new();battle.units=[unit(1,Vector2i(4,6)),unit(2,Vector2i(3,3))]
	var view:=RecordingView.new();view.data=data;view.assets=assets;view.battle=battle;view.surface=FT2IndexedSurface.new();view.palette=FT2Palette.new();view.physical=PassiveFX.new();view.magic=PassiveFX.new();view.environment=PassiveEnvironment.new();view.game_mode=4
	view.map={"base":[320,120],"side":16,"header":[0,0,0,0],"background":""}
	var world:=Vector2i(4,6)
	var player:=FT2APDPlayer.new();player.play(assets.apd("CHAR_01V"),"F.ACT",1,1)
	var actor:={"id":0,"world":world,"sort_world":Vector2i(7,2),"job_shadow_follow":true,"job_direction":0,"visible":true}
	var record:={"player":player,"actor":actor,"signature":"own"}
	view._script={"players":{0:record}}
	# Independently chosen projections: camera and elevation are part of the ground line.
	var projections:=[{"camera":Vector2i(11,-5),"height":3,"source":Vector2i(245,261)},{"camera":Vector2i.ZERO,"height":0,"source":Vector2i(256,280)},{"camera":Vector2i(-7,13),"height":7,"source":Vector2i(263,211)}]
	for projection in projections:
		view.camera=projection.camera;view._cells[world]=[4,6,projection.height]
		check(view.world_to_screen(world)==projection.source,"own ground projection includes camera/elevation")
		for direction in 4:
			actor.job_direction=direction
			player.offset=Vector2i(9,-17)
			check(view._script_shadow_anchor(0,world)==projection.source+Vector2i(9,[-4,5,5,-4][direction]),"positive odd-X ground projection direction "+str(direction))
			player.offset=Vector2i(-9,23)
			check(view._script_shadow_anchor(0,world)==projection.source+Vector2i(-9,[5,-4,-4,5][direction]),"negative odd-X arithmetic shift direction "+str(direction))
	view.camera=Vector2i(11,-5);view._cells[world]=[4,6,3];player.offset=Vector2i(9,21)
	actor.pos=Vector2i(301,179);actor.job_direction=0;record.base_adjust=Vector2i(5,-3);record.adjust_camera=view.camera
	check(view._script_shadow_anchor(0,world)==Vector2i(315,226),"explicit position still includes same-camera base adjustment and body motion")
	actor.job_direction=1
	check(view._script_shadow_anchor(0,world)==Vector2i(315,296),"explicit position projects onto the opposite directional ground slope")
	record.adjust_camera=Vector2i.ZERO
	check(view._script_shadow_anchor(0,world)==Vector2i(310,294),"stale camera-local adjustment is not reused")
	actor.erase("pos");record.erase("base_adjust");record.erase("adjust_camera");actor.job_direction=4
	check(view._script_shadow_anchor(0,world)==Vector2i(254,0),"single-action direction4 retains native ground-Y zero fallback")
	check(view._script_shadow_depth(0,world)==9,"following shadow uses the job sort-world depth")
	actor.job_shadow_follow=false
	check(view._script_shadow_anchor(0,world)==Vector2i(245,261)and view._script_shadow_depth(0,world)==10,"non-following shadow returns to its logical ground cell/depth")
	# Actual draw collection must use both helpers and the masked .M labels.
	battle.units[0]=unit(1,Vector2i(2,3));view._cells[Vector2i(2,3)]=[2,3,1]
	for size in range(1,5):
		data.shadow_size=size;view._actors.clear();view._refresh_actors()
		var body=view._actors[0].player;body.offset=Vector2i(9,-13)
		var moving_actor:={"id":0,"world":Vector2i(2,3),"sort_world":Vector2i(2,6),"job_shadow_follow":true,"job_direction":1,"visible":true}
		view._script={"players":{0:{"player":body,"actor":moving_actor,"signature":"own-render"}}}
		var shadow=view._actors[0].shadow;var sentinel=view._actors[1].player
		view.draws.clear();view.anchor_calls.clear();view.depth_calls.clear();view._render(false,true)
		var shadow_index:=-1;var sentinel_index:=-1
		for index in view.draws.size():
			if view.draws[index].player==shadow:shadow_index=index
			if view.draws[index].player==sentinel:sentinel_index=index
		check(shadow.label==["SMALL.M","MIDDLE.M","LARGE.M","HUGE.M"][size-1]and shadow.frame==(size-1)*2+1,"idle selector chooses masked shadow rather than opaque ordinary label "+str(size))
		check(shadow_index>=0 and view.draws[shadow_index].anchor==Vector2i(286,202)and view.draws[shadow_index].policy=="system","actual render uses projected shadow anchor/system policy "+str(size))
		check(view.anchor_calls.any(func(row):return row.slot==0)and view.depth_calls.any(func(row):return row.slot==0 and row.value==8),"actual render invokes shadow anchor and depth helpers "+str(size))
		check(sentinel_index>=0 and shadow_index>sentinel_index,"job depth moves shadow after the shallower sentinel actor "+str(size))
	# Producer metadata follows active paths, stops at completed path boundaries,
	# and retains the separately defined single-action follow classification.
	var jobs=Jobs.new(data);var metadata:={"own":{"value":7}}
	check(jobs.play_path(0,"CHAR_01V",Vector2i(2,3),"se","MOVE",100,metadata),"own two-step actor path starts")
	check(jobs.snapshots()[0].job_shadow_follow and jobs.snapshots()[0].job_direction==0,"active path publishes its first step direction and follow flag")
	for tick in [100,201,302,302,403,504]:jobs.advance(tick)
	check(not jobs.is_busy(0)and not jobs.snapshots()[0].job_shadow_follow and jobs.snapshots()[0].job_direction==1,"completed path stops follow and retains its last step metadata")
	check(metadata=={"own":{"value":7}},"snapshot metadata does not mutate caller-owned data")
	jobs.clear();check(jobs.play_single(1,"CHAR_01V",Vector2i(2,3),"F.ACT",700),"own single actor action starts")
	check(jobs.snapshots()[0].job_shadow_follow and jobs.snapshots()[0].job_direction==4,"active single action publishes direction4 follow metadata")
	for tick in [700,801,902]:jobs.advance(tick)
	check(not jobs.is_busy(1)and jobs.snapshots()[0].job_shadow_follow,"finished single keeps producer follow classification without claiming cache lifetime across other operations")
	# Native reset/play visibility remains separate from ground-follow placement.
	var vm=VM.new();vm.data=data;vm.battle=battle;vm.jobs=Jobs.new(data);vm.mode=4;vm.actor_cache_mode=4;vm.actor_player_query=Callable(view,"unit_player");vm.actor_changed.connect(view.set_script_state)
	vm._execute(7,[0,120])
	var blank=view.unit_player(0)
	check(blank.frame==-1 and not blank.visible and not view._actors[0].shadow.visible,"OP7 blank replacement hides both body and shadow")
	check(vm.jobs.play_single(0,"CHAR_01X",Vector2i(2,3),"F.ACT",1000,vm._job_metadata(0)),"job can play a reset body")
	check(blank.frame>=0 and blank.visible and not view._actors[0].shadow.visible,"successful job first-play shows body without showing the shadow")
	for tick in [1000,1101,1202]:vm.jobs.advance(tick)
	vm._execute(8,[0,"F.ACT",0])
	check(view.unit_player(0).visible and view._actors[0].shadow.visible,"OP8 explicitly restores both body and shadow")
	check(vm.errors.is_empty()and vm.jobs.errors.is_empty()and jobs.errors.is_empty(),"own shadow scenarios have no VM/job errors")
	vm.actor_changed.disconnect(view.set_script_state);vm.actor_player_query=Callable();view.free()
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored coordinates and APD steps only"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
