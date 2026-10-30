extends SceneTree
const Nav=preload("res://scripts/logic/ft2_navigation.gd")
const Builder=preload("res://scripts/logic/ft2_physical_program.gd")
const Playback=preload("res://scripts/render/ft2_physical_playback.gd")
const Battle=preload("res://scripts/logic/ft2_battle.gd")
class ModeOwner:
 extends RefCounted
 var mode:=1
 var control_mode:=2
class OwnData:
 extends RefCounted
 func appearance_definition(id:int)->int:return id
 func read_json(_path:String)->Dictionary:return {"WAV":[]}
 func raw_table(name:String)->PackedByteArray:
  var b:=PackedByteArray();b.resize(172 if name=="race"else 84*64 if name=="magic"else 56);b.fill(0)
  if name=="race":
   for i in 2:
    b.encode_u16(i*86+58,4);b.encode_u16(i*86+60,4)
    for terrain in 8:b.encode_u16(i*86+62+2*terrain,4)
   b.encode_u16(62,99)
  return b
 func load_apd(stem:String)->Dictionary:
  var names:Dictionary={}
  var steps:Array=[]
  for i in 2:steps.append({"image_frame":i,"duration_ms":20,"draw_flags":0,"sound_event_id":-1,"sound_event_indirect":0,"action_marker":0})
  for prefix in ["F.","B."]:
   for name in ["TAKE_OFF1","TAKE_OFF2","FLY1","FLY2","TOUCH_DOWN2"]:names[prefix+name]={"compiled_groups":[{"move_total_xy":[0,0],"compiled_sequence_velocity_per_ms":[0,0],"steps":steps.duplicate(true)}]}
  return {"name":stem,"animations":names}
class OwnAssets extends FT2IndexedAssets:
 var store
 func _init(data):store=data
 func apd(stem:String)->Dictionary:return store.load_apd(stem)
var checks:=0
var failures:Array[String]=[]
var output:=""
func check(value:bool,label:String)->void:
 checks+=1
 if not value:failures.append(label)
func mode(nav)->int:return nav.current_game_mode() if nav.has_method("current_game_mode") else nav.map_mode
func bind(nav,owner)->void:
 if nav.has_method("set_game_mode_owner"):nav.set_game_mode_owner(owner)
func unit(definition:int,point:Vector2i,state:int=0)->PackedByteArray:
 var u:=PackedByteArray();u.resize(124);u.fill(0);u.encode_u16(0,definition+1);u.encode_u16(2,definition);u.encode_u16(4,2);u.encode_u16(6,2);u.encode_u32(8,point.x);u.encode_u32(12,point.y);u.encode_u16(16,state);u.encode_u16(36,20);u.encode_u16(38,20);return u
func map_data()->Dictionary:
 var cells:Array=[]
 for x in range(10,40):
  for y in range(10,35):cells.append({"x":x,"y":y,"H":0,"L":1,"flag2_raw":0,"flag3_raw":0,"part_count":0})
 return {"cells":cells,"header_map_bounds_ltrb":[0,24,50,24]}
func flight_fixture()->Dictionary:
 var data:=OwnData.new();var rules=FT2Mechanics.new(data);var actor:=unit(0,Vector2i(32,23),11);var nav=Nav.new(rules);nav.configure([actor],map_data(),2);var owner:=ModeOwner.new();bind(nav,owner)
 return {"data":data,"rules":rules,"actor":actor,"nav":nav,"owner":owner}
func program(f:Dictionary,n:int,explicit_mode:int=-1)->Dictionary:
 var after:Array=[f.actor.duplicate()];after[0].encode_u32(8,32-n)
 var path:Array=[]
 for i in n:path.append(2)
 var plan:={"actor_slot":0,"origin":Vector2i(32,23),"path":path,"direction":2,"results":[],"before_units":[f.actor],"after_units":after,"accepted_run":0,"prepared_before":0,"audio_enabled":false}
 if explicit_mode>=0:plan["game_mode"]=explicit_mode
 return Builder.new(f.data,f.rules,f.nav).build(plan)
func play(f:Dictionary,p:Dictionary,epoch:int)->Dictionary:
 var playback=Playback.new();playback.configure(OwnAssets.new(f.data));playback.project_world=func(v):return f.nav.project(v)
 var focus:Array=[]
 playback.camera_focus_requested.connect(func(v):focus.assign([v.x-320,v.y-240]))
 playback.play(p,epoch)
 for t in range(epoch,epoch+10000,50):
  playback.before_apd(t);playback.advance_apd(t);playback.advance_apd(t);playback.after_apd()
  if not playback.active:break
 return {"camera":focus,"active":playback.active}
func _initialize()->void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--game-mode-output="):output=arg.trim_prefix("--game-mode-output=")
 call_deferred("run")
func run()->void:
 FT2Content.active=null;var f:=flight_fixture()
 check(f.nav.map_mode==2 and mode(f.nav)==1,"source game1 is distinct from stored configure/Town value2")
 check(f.nav.floating(0),"actual game1 enables status11 flight despite storedmode2")
 check(f.nav.limits(0)==Vector2i(99,99),"actualmode controls original flight climb limits")
 var p=program(f,7);check(p.native_route==1 and p.records[0].commands.size()==11,"sourcegame1 builds7flightsteps plus takeoff/landing, not7emptyRUNcommands")
 check(p.records[0].commands.all(func(c):return not c.compiled_groups.is_empty()),"fly-only own APD has valid generated commands")
 for epoch in [100,101,117,149]:
  var result=play(f,p,epoch);check(not result.active and result.camera==[512,144],"50ms source-clock final camera reaches actualtarget for epoch"+str(epoch))
 var short=play(f,program(f,1),100);check(short.camera==[704,240],"one-cell flight uses same source context without a camera snap")
 f.owner.mode=4
 check(mode(f.nav)==4 and not f.nav.floating(0),"eventmode4 immediately disables tactical flight through weak owner")
 var ground=program(f,7);check(ground.native_route==0 and ground.records[0].commands.size()==7,"eventmode4 selects source ground branch")
 var explicit=program(f,7,1);check(explicit.native_route==1,"explicit physicalplan game_mode1 remains authoritative")
 f.owner.mode=1;explicit=program(f,7,4);check(explicit.native_route==0,"explicit physicalplan game_mode4 is not overwritten by owner")
 f.nav.configure([f.actor],map_data(),9);check(mode(f.nav)==1 and f.nav.map_mode==9,"reconfigure does not replace a live actual-mode owner")
 bind(f.nav,null);check(mode(f.nav)==9,"explicit unbind restores existing standalone fallback")
 f.nav.configure([f.actor],map_data(),2);check(mode(f.nav)==2 and not f.nav.floating(0),"standalone configure2 behavior remains intact")
 var ephemeral:=ModeOwner.new();bind(f.nav,ephemeral);ephemeral=null;check(mode(f.nav)==2,"weak mode ownership does not extend VM lifetime")
 f.owner.mode=1;bind(f.nav,f.owner)
 var enemy:=unit(1,Vector2i(31,23));enemy.encode_u16(18,6);f.nav.units=[f.actor,enemy]
 check(not f.nav.zoc(0,Vector2i(32,23)),"tactical flight ignores ground ZOC")
 f.owner.mode=4;check(f.nav.zoc(0,Vector2i(32,23)),"eventmode4 ground branch still observes ZOC")
 f.nav.configure([f.actor],map_data(),2);f.nav.cells[Vector2i(31,23)][0]=10;f.owner.mode=1;f.nav.movement_grid(0)
 check(f.nav.path_to(Vector2i(31,23))==[2],"actualgame1 path backtrace accepts flight climb beyond ground limit")
 f.owner.mode=4;f.nav.movement_grid(0);check(not f.nav.selectable(Vector2i(31,23)),"actualgame4 path grid rejects the same oversized ground climb")
 f.nav.configure([f.actor,enemy],map_data(),2) # Restore flat fixture before independent run checks.
 # Test the real battle run and numeric gateways, without rendering/input/data mounts.
 var b=Battle.new();b.rules=f.rules;b.navigation=f.nav;b.units=[f.actor.duplicate(),unit(1,Vector2i(29,23))];b.path=[2,2,2];b.selected_slot=0
 var targets:Array=[{"target_slot":1}];f.owner.mode=1
 check(b._run_flag(b.units[0],targets)==0,"levitating ground race cannot use a tactical ground run")
 f.owner.mode=4;check(b._run_flag(b.units[0],targets)==1,"non-tactical eventmode run retains its previous branch")
 for actual in [1,4]:
  var model=Battle.new();model.rules=f.rules;model.navigation=f.nav;model.units=[unit(0,Vector2i(32,23)),unit(1,Vector2i(31,23))];model.selected_slot=0;model.action_id=35;model._before_units=model.units.duplicate(true);model._preview={"records":[{"target_slot":1,"origin":Vector2i(32,23)}],"center":Vector2i(31,23)};f.owner.mode=actual;f.nav.units=model.units;model._commit_numeric()
  check(model.units[1].decode_u16(16)==(0 if actual==1 else 11),"real numeric35 receives current sourcegame"+str(actual)+" rather than staleconfigure2")
 var report:={"suite":"source_game_mode","checks":checks,"failures":failures,"passed":failures.is_empty(),"synthetic":true,"game_data_used":false}
 if output!="":
  DirAccess.make_dir_recursive_absolute(output);var file=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
 print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
