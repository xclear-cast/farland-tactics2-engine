extends SceneTree
## Own 2x2 indexed images only. Exercise Scene commands through the real View.
const Scene=preload("res://scripts/scenario/ft2_scene.gd")
const View=preload("res://scripts/render/ft2_battle_view.gd")
class SyntheticData:
	extends RefCounted
	func read_json(path: String) -> Dictionary:
		if path.ends_with("fixed_trig_contract.json"):return {"quarter_wave_u16":[0]}
		if path.ends_with("runtime_bindings.json"):return {"visual_sequence_selector":{"entries":[]}}
		if path.ends_with("VSLLST.json"):return {"records":[]}
		if path.ends_with("bitmaps/index.json"):return {"files":[{"source":"BMP/OWN_BASE.BMP","size":[2,2]},{"source":"BMP/OWN_OVER.BMP","size":[2,2]}]}
		return {}
class SyntheticAssets extends FT2IndexedAssets:
	var images: Dictionary={}
	func _init() -> void:
		var palette:=PackedByteArray();palette.resize(768);palette.fill(0);palette[249*3]=255
		images["BMP/OWN_BASE.BMP"]={"key":"own_base","signature":"own_base","width":2,"height":2,"pixels":PackedByteArray([249,32,33,34]),"palette":palette}
		images["BMP/OWN_OVER.BMP"]={"key":"own_over","signature":"own_over","width":2,"height":2,"pixels":PackedByteArray([41,249,249,42]),"palette":palette.duplicate()}
	func image(key: String,_remaps: Array=[]) -> Dictionary:return images.get(key.to_upper(),{})

var checks:=0
var failures: Array[String]=[]
var output:=""
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layer-keys-output="):output=arg.trim_prefix("--layer-keys-output=")
	call_deferred("run")
func model() -> Dictionary:
	return {"layers":{},"order":[],"clip":Rect2i(0,0,640,480),"bitmaps":{0:{"stem":"OWN_BASE","remaps":[]},1:{"stem":"OWN_OVER","remaps":[]}},"queues":{},"motions":{},"dithers":{},"wave_slots":{},"apd_instances":{},"apd_resources":{},"credits":{},"callbacks":{},"local_epoch":0}
func crop(scene,m: Dictionary,layer: int,bitmap: int) -> void:
	scene._apply({"operation":"layer_crop","args":[layer,8,8,bitmap,0,0,2,2]},m)
func render(scene,view) -> PackedByteArray:
	view.surface.clear(91)
	check(view.service_script_commands([{"op":"paint_main","commands":scene.commands()}]).is_empty(),"real View accepts cinematic layer commands")
	var pixels: PackedByteArray=view.surface.pixels
	return PackedByteArray([pixels[8*640+8],pixels[8*640+9],pixels[9*640+8],pixels[9*640+9]])
func run() -> void:
	var scene=Scene.new(SyntheticData.new());var m:=model();scene._model=m
	var view=View.new();view.assets=SyntheticAssets.new();view.surface=FT2IndexedSurface.new();view.palette=FT2Palette.new()
	scene._apply({"operation":"reset_layer_scene","args":[]},m)
	check(m.layers.size()==9,"reset initializes all nine native bitmap layers")
	check(m.layers[0].key==-1,"base layer0 remains opaque")
	check(m.order==[0,1,2,3,4,5,6,7,8]and m.clip==Rect2i(0,0,640,480),"reset restores default draw order and full clip")
	crop(scene,m,0,0)
	check(render(scene,view)==PackedByteArray([249,32,33,34]),"base image draws index249 as an opaque pixel")
	for layer in range(1,9):
		scene._apply({"operation":"reset_layer_scene","args":[]},m);crop(scene,m,0,0);crop(scene,m,layer,1)
		check(m.layers[layer].key==249,"overlay default key249 for layer "+str(layer))
		var commands: Array[Dictionary]=scene.commands()
		check(commands.size()==2 and commands[0].transparent==-1 and commands[1].transparent==249,"producer retains distinct base and overlay policies "+str(layer))
		check(render(scene,view)==PackedByteArray([41,32,33,42]),"actual overlay composition preserves lower pixels under249 layer "+str(layer))
	# An explicit key belongs to the layer and survives later crop operations.
	scene._apply({"operation":"reset_layer_scene","args":[]},m);crop(scene,m,0,0)
	scene._apply({"operation":"layer_transparent_index","args":[1,41]},m);crop(scene,m,1,1)
	check(m.layers[1].key==41,"crop preserves an explicitly selected layer key")
	check(render(scene,view)==PackedByteArray([249,249,249,42]),"custom key41 skips41 and allows249 to remain opaque")
	crop(scene,m,1,1)
	check(m.layers[1].key==41 and scene.commands()[1].transparent==41,"repeated crop does not replace a custom key")
	m.order=[8,1,0];m.clip=Rect2i(3,4,100,80);m.queues[1]={"own":true};m.motions[1]={"own":true};m.dithers[1]={"own":true}
	scene._apply({"operation":"reset_layer_scene","args":[]},m)
	check(m.layers[1].key==249 and m.layers[0].key==-1,"full reset discards previous custom keys")
	check(m.order==[0,1,2,3,4,5,6,7,8]and m.clip==Rect2i(0,0,640,480),"full reset discards custom draw order and clip")
	check(m.queues.is_empty()and m.motions.is_empty()and m.dithers.is_empty(),"full reset clears temporary layer activity")
	check(m.layers.values().all(func(layer):return layer.bitmap==-1 and layer.fill==-1 and layer.mask==0),"full reset clears drawables while retaining initialized layer keys")
	# Cue release clears temporary contents but is not the complete layer reset.
	scene._apply({"operation":"layer_transparent_index","args":[1,41]},m);crop(scene,m,1,1)
	m.order=[8,1,0];m.clip=Rect2i(3,4,100,80);m.queues[1]={"own":true};m.motions[1]={"own":true};m.dithers[1]={"own":true};m.wave_slots[1]="own-wave";m.callbacks[1]={"own":true};m.apd_instances[1]={"own":true};m.apd_resources[1]={"own":true};scene.now=123
	scene._apply({"operation":"release_cue_reset_scene","args":[]},m)
	check(m.layers[1].key==41 and m.layers[0].key==-1 and m.layers[8].key==249,"cue release preserves custom and default transparency keys")
	check(m.order==[8,1,0]and m.clip==Rect2i(3,4,100,80),"cue release preserves current draw order and clip")
	check(m.layers.values().all(func(layer):return layer.bitmap==-1 and layer.fill==-1 and layer.source.size==Vector2i.ZERO),"cue release clears old crop contents rather than drawing stale images")
	check(m.queues.is_empty()and m.motions.is_empty()and m.dithers.is_empty()and m.callbacks.is_empty()and m.apd_instances.is_empty()and m.apd_resources.is_empty(),"cue release clears temporary layer/controller state")
	check(m.last_released_waves==["own-wave"]and m.wave_slots.is_empty()and m.local_epoch==123,"cue release records released sounds and resets only its local epoch")
	crop(scene,m,1,1)
	check(m.layers[1].key==41,"a crop after cue release still uses the preserved custom key")
	scene._apply({"operation":"reset_layer_scene","args":[]},m);crop(scene,m,0,0);crop(scene,m,1,1)
	check(render(scene,view)==PackedByteArray([41,32,33,42]),"reset after a cue release restores overlay transparency and full clipping")
	# Ordinary full-picture commands such as OP50 must remain explicitly opaque.
	view.surface.clear(91)
	view.service_script_commands([{"op":"paint_main","commands":[{"op":"bitmap","key":"BMP/OWN_OVER.BMP","pos":Vector2i(8,8),"source":Rect2i(0,0,2,2),"transparent":-1}]}])
	var pixels: PackedByteArray=view.surface.pixels
	check(PackedByteArray([pixels[8*640+8],pixels[8*640+9],pixels[9*640+8],pixels[9*640+9]])==PackedByteArray([41,249,249,42]),"ordinary opaque bitmap drawing does not globally skip249")
	check(scene.errors.is_empty(),"synthetic layer-key operations have no unsupported scene errors")
	view.free()
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored 2x2 indexed pixels only"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
