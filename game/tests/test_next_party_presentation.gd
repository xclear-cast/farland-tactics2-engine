extends SceneTree
## Own party records and a presented-camera fixture; no game installation.
const Main=preload("res://scripts/main.gd")
class OwnBattle:
	extends RefCounted
	var units:Array=[]
	var substate:=0
	var selected_slot:=-1
	var rng:Array=[2,3,5]
class OwnView:
	extends RefCounted
	var camera:=Vector2i.ZERO
	var presented_camera:=Vector2i(-1,-1)
	var draws:=0
	var trace:Array=[]
	func center_on_unit(slot:int)->void:
		camera=Vector2i(slot*13,slot*19);trace.append("center")
	func draw_tactical_now()->void:
		presented_camera=camera;draws+=1;trace.append("present")
class OwnUI:
	extends RefCounted
	var view
	var menu_saw_camera:=Vector2i.ZERO
	var menu_pointer:=Vector2i.ZERO
	var hover:=Vector2i.ZERO
	var menus:=0
	var commands:Array=[]
	func hover_cell(cell:Vector2i,_x:int)->void:
		hover=cell;view.trace.append("hover")
	func open_action_menu(point:Vector2i)->void:
		menu_saw_camera=view.presented_camera;menu_pointer=point;menus+=1;view.trace.append("menu")
	func command(value:int)->void:commands.append(value)
var checks:=0
var failures:Array[String]=[]
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label)
func run()->void:
	var app=Main.new();var battle=OwnBattle.new();var view=OwnView.new();var ui=OwnUI.new();ui.view=view
	for i in 10:
		var u:=PackedByteArray();u.resize(124);u.fill(0);battle.units.append(u)
	for slot in [0,1,4]:
		battle.units[slot].encode_u16(0,slot+1)
		battle.units[slot].encode_u32(8,slot+10);battle.units[slot].encode_u32(12,slot+20)
	app.battle=battle;app.view=view;app.ui=ui;app._pointer=Vector2i(31,47)
	var before=battle.units.duplicate(true);var rng=battle.rng.duplicate()
	app._next_party()
	check(battle.selected_slot==1,"ordinary NextParty selects the next available actor")
	check(view.camera==Vector2i(13,19),"the next actor requests its own camera")
	check(ui.menu_saw_camera==view.camera,"the blocking actor menu sees the newly presented camera")
	check(view.trace==["center","hover","present","menu"],"center and tactical presentation finish before the menu opens")
	check(ui.menu_pointer==Vector2i(31,47) and ui.hover==Vector2i(11,21),"presentation keeps ordinary menu placement and actor hover")
	check(battle.units==before and battle.rng==rng,"a menu redraw leaves all unit records and battle RNG untouched")
	check(app.frame_number==0 and app.elapsed_ms==0,"NextParty does not run an extra outer frame or advance time")
	battle.substate=1;var draws=view.draws;var menus=ui.menus;app._next_party()
	check(view.draws==draws and ui.menus==menus and battle.selected_slot==1,"an active movement selection blocks NextParty without repainting")
	battle.substate=0;battle.units[4].encode_u16(16,8);app._next_party()
	check(battle.selected_slot==0,"stone status is skipped and ordinary party selection wraps")
	check(ui.menu_saw_camera==Vector2i.ZERO,"wrapped selection also presents its new scene before opening")
	app.free()
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored party records, camera and blocking-menu observations"}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--next-party-output="):
			var output:=arg.trim_prefix("--next-party-output=");DirAccess.make_dir_recursive_absolute(output)
			var f:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
func _initialize()->void:call_deferred("run")
