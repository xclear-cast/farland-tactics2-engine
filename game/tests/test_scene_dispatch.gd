extends SceneTree
## Self-authored bitmap, text pixels and APD marker; no original files.
const Scene=preload("res://scripts/scenario/ft2_scene.gd")
const View=preload("res://scripts/render/ft2_battle_view.gd")
class OwnData:
	extends RefCounted
	func read_json(path: String) -> Dictionary:
		if path.ends_with("fixed_trig_contract.json"):return {"quarter_wave_u16":[0]}
		if path.ends_with("runtime_bindings.json"):return {"visual_sequence_selector":{"entries":[]}}
		if path.ends_with("VSLLST.json"):return {"records":[]}
		if path.ends_with("bitmaps/index.json"):return {"files":[{"source":"BMP/OWN.BMP","size":[2,1]}]}
		if path.ends_with("STAFF.json"):return {"render_entries":[{"render_text_cp949":"OWN","style":{"fontsize":1,"fontflags":0,"linespace":0,"spacesize":0,"posx":0,"center":0,"fontcolor":30,"decocolor":16}}]}
		return {}
class OwnAssets extends FT2IndexedAssets:
	func image(_key: String,_remaps: Array=[]) -> Dictionary:return {"width":2,"height":1,"pixels":PackedByteArray([32,33])}
class OwnFont extends FT2IndexedFont:
	func _init() -> void:pass
	func rasterize(_text: String,_font: Dictionary,_color: int=30,_decor: Dictionary={},_display: String="") -> Dictionary:return {"width":2,"height":1,"pixels":PackedByteArray([30,31]),"transparent":249}
class SceneProbe extends Scene:
	var apd_calls:=0
	func _apd_commands() -> Array[Dictionary]:
		apd_calls+=1
		return [{"op":"rect","rect":Rect2i(4,0,1,1),"filled":true,"color":77}]

var checks:=0
var failures: Array[String]=[]
var output:=""
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func model() -> Dictionary:
	return {"layers":{},"order":[0,1],"clip":Rect2i(0,0,640,480),"bitmaps":{0:{"stem":"OWN","remaps":[]}},"motions":{},"queues":{},"dithers":{},"wave_slots":{},"apd_instances":{},"apd_resources":{},"credits":{},"callbacks":{},"photos":{},"bands":{},"rng":[1,2,3],"selected_layer":-1,"local_epoch":0}
func apply(scene,m: Dictionary,name: String,args: Array=[]) -> void:scene._apply({"operation":name,"args":args},m)
func pixels(scene,view) -> PackedByteArray:
	view.surface.clear(91)
	check(view.service_script_commands([{"op":"paint_main","commands":scene.commands()}]).is_empty(),"actual indexed View accepts selected-layer commands")
	return view.surface.pixels
func run() -> void:
	var scene=SceneProbe.new(OwnData.new());var m:=model();scene._model=m
	var view=View.new();view.surface=FT2IndexedSurface.new();view.palette=FT2Palette.new();view.assets=OwnAssets.new();view.font=OwnFont.new()
	apply(scene,m,"reset_layer_scene")
	m.order=[0,1]
	for id in [0,1]:apply(scene,m,"layer_crop",[id,0,0,0,0,0,2,1])
	apply(scene,m,"credits_scroll_start",[1,0,1000]);m.credits.y=0
	check(m.selected_layer==1,"credits service selects its dispatch layer")
	var commands: Array[Dictionary]=scene.commands()
	check(commands.size()==2 and commands[0].op=="bitmap" and commands[1].op=="text","selected text dispatch replaces its own bitmap")
	var raw:=pixels(scene,view)
	check(raw[0]==30 and raw[1]==31,"text group paints through the actual View")
	m.layers[1].visible=false;m.callbacks[1]={"family":3,"particles":[]}
	commands=scene.commands()
	check(commands.size()==2 and commands[1].op=="text","selected text bypasses both layer visibility and callback dispatch")
	m.layers[1].offset=Vector2i(2,3)
	check(scene.commands()[1].pos==Vector2i(2,3),"selected text uses the layer auxiliary offset")
	raw=pixels(scene,view)
	check(raw[3*640+2]==30 and raw[3*640+3]==31,"auxiliary offset reaches actual text raster placement")
	m.layers[1].offset=Vector2i.ZERO;m.clip=Rect2i(1,0,1,1)
	check(scene.commands()[1].clip==Rect2i(1,0,1,1),"selected text carries the native screen clip")
	raw=pixels(scene,view)
	check(raw[0]==91 and raw[1]==31,"screen clip restricts both bitmap and text output")
	m.clip=Rect2i(0,0,640,480);m.callbacks.clear();m.layers[1].visible=true;m.selected_layer=-1
	commands=scene.commands()
	check(commands.size()==2 and commands.all(func(c):return c.op=="bitmap"),"deselected group data does not keep drawing as an overlay")
	m.credits.active=true;m.credits.epoch=0;m.credits.y=37;scene.now=500;scene._advance_backend(m)
	check(m.credits.y==37 and m.credits.active,"deselection suspends scroll service without destroying the group")
	m.selected_layer=1;scene._advance_backend(m)
	check(m.credits.y!=37,"reselecting resumes scroll service")
	m.credits.y=0;apply(scene,m,"release_cue_reset_scene",[0])
	check(m.selected_layer==1 and not m.credits.is_empty(),"cue release retains selected text dispatch and group lifetime")
	check(scene.commands()[1].op=="text","retained selected group still dispatches after cue release")
	apply(scene,m,"reset_layer_scene")
	check(m.selected_layer==-1 and not m.credits.is_empty(),"full reset deselects without destroying the text group")
	check(scene.commands().is_empty(),"full reset cannot draw the deselected retained group")
	m.order=[0,1];apply(scene,m,"layer_crop",[0,0,0,0,0,0,2,1]);apply(scene,m,"layer_crop",[1,0,0,0,0,0,2,1]);m.selected_layer=1;m.credits.clear()
	check(scene.commands().size()==1,"an empty selected group still replaces its normal bitmap")
	m.order=[9];var nine: Dictionary=scene._layer(m,9);nine.visible=false;m.selected_layer=9
	commands=scene.commands()
	check(scene.apd_calls==1 and commands.size()==1 and commands[0].color==77,"APD slot9 dispatch precedes selected text and ignores bitmap-layer visibility")
	raw=pixels(scene,view)
	check(raw[4]==77,"hidden layer9 cannot suppress the independent APD pool")
	check(scene.errors.is_empty(),"selected-layer source operations have no unsupported errors")
	view.free()
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored two-pixel bitmaps/text and APD dispatch marker"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene-dispatch-output="):output=arg.trim_prefix("--scene-dispatch-output=")
	call_deferred("run")
