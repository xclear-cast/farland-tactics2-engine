extends SceneTree
## Independent cue records,2x2 pixels and APDs; no original data or game process.
const Scene=preload("res://scripts/scenario/ft2_scene.gd")
const View=preload("res://scripts/render/ft2_battle_view.gd")
const VM=preload("res://scripts/scenario/ft2_vm.gd")

class OwnData:
	extends RefCounted
	var records: Array=[]
	func cue(profile: int,selector: int,id: int,stem: String,state: int=0) -> Dictionary:
		return {"sequence_selector":profile,"cue_index":selector,"resource_id":id,"bitmap_stem":stem,"initial_runtime_load_state":state,"load4271F0_arg2":32,"load4271F0_arg3":10,"load4271F0_arg4":2}
	func _init() -> void:
		records=[cue(3,10,0,"OWN_A"),cue(3,10,1,"MISSING"),cue(3,10,2,"no_entry"),cue(3,10,3,"OWN_B"),cue(4,10,4,"OWN_B"),cue(3,11,0,"OWN_B"),cue(3,12,5,"OWN_A",2),cue(3,13,6,""),cue(3,14,300,"OWN_A"),cue(3,15,0,"MISSING"),cue(3,16,7,"OWN_B")]
	func read_json(path: String) -> Dictionary:
		if path.ends_with("fixed_trig_contract.json"):return {"quarter_wave_u16":[0]}
		if path.ends_with("runtime_bindings.json"):return {"visual_sequence_selector":{"entries":[]}}
		if path.ends_with("VSLLST.json"):return {"records":records}
		if path.ends_with("bitmaps/index.json"):return {"files":[{"source":"BMP/OWN_A.BMP","size":[2,2]},{"source":"BMP/OWN_B.BMP","size":[2,2]}]}
		return {}
	func load_apd(stem: String) -> Dictionary:
		return {"name":stem,"sheets":[],"parts":[],"frames":[{"parts":[],"pivot":0,"bounds":[0,0,1,1]}],"animations":{"OWN":{"groups":[{"move":[0,0],"velocity":[0,0],"steps":[[0,100,0,-1,0,0]]}]}}}

class OwnAssets extends FT2IndexedAssets:
	func image(key: String,_remaps: Array=[]) -> Dictionary:
		var raw:=PackedByteArray([21,253,22,249]) if key.to_upper().ends_with("OWN_A.BMP") else PackedByteArray([41,42,43,44])
		return {"width":2,"height":2,"pixels":raw}

var checks:=0
var failures: Array[String]=[]
var output:=""

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)

func model() -> Dictionary:
	return {"layers":{},"order":[0,1,9],"clip":Rect2i(0,0,640,480),"bitmaps":{},"queues":{},"motions":{},"dithers":{},"wave_slots":{},"apd_instances":{},"apd_resources":{},"credits":{},"callbacks":{},"local_epoch":77,"global_epoch":88,"palette_until":99,"photos":{},"bands":{},"rng":[167,19960,5150],"scalars":{}}

func apply(scene,m: Dictionary,name: String,args: Array=[]) -> void:
	scene._apply({"operation":name,"args":args},m)

func pixel(view,scene) -> Array:
	view.surface.clear(90);view.service_script_commands([{"op":"paint_main","commands":scene.commands()}])
	var p: PackedByteArray=view.surface.pixels
	return [p[0],p[1],p[640],p[641]]

func test_full_reset() -> void:
	var scene=Scene.new(OwnData.new());var m:=model();scene._model=m
	for id in 10:
		var layer: Dictionary=scene._layer(m,id)
		layer.merge({"bitmap":0,"dst":Vector2i(5,6),"source":Rect2i(1,2,3,4),"visible":false,"key":253,"offset":Vector2i(7,8),"mask":123,"fill":42,"mask_rect":Rect2i(9,10,11,12)},true)
	var nine: Dictionary=m.layers[9].duplicate(true);nine.offset=Vector2i.ZERO
	m.bitmaps[0]={"stem":"OWN_A","remaps":[]};m.queues[0]={"own":true};m.motions[9]={"own":true}
	m.dithers[1]={"rect":Rect2i(2,3,4,5),"duration":100,"masks":[123,456],"active":true,"epoch":1}
	var dither: Dictionary=m.dithers.duplicate(true)
	m.apd_instances[0]={"own":true};m.apd_resources[0]={"own":true};m.callbacks[9]={"own":true};m.wave_slots[0]="own-a";m.wave_slots[15]="own-b"
	m.credits={"own":"preserved","layer":9};m.photos={1:{"own":true}};m.bands={1:{"own":true}};m.selected_layer=3
	scene.now=120;apply(scene,m,"reset_layer_scene",[0])
	check(m.order==[0,1,2,3,4,5,6,7,8] and m.clip==Rect2i(0,0,640,480),"full reset restores order and screen clip")
	check(m.selected_layer==-1 and m.credits=={"own":"preserved","layer":9},"selected-layer write does not invent destruction of the text group")
	for id in 9:
		var l: Dictionary=m.layers[id]
		check(l.visible and l.key==(-1 if id==0 else 249),"full reset enables layer%d with its native default key"%id)
		check(l.bitmap==-1 and l.fill==(0 if id==0 else 249) and l.mask==0 and l.drawable_empty,"full reset empties destination and current mask for layer%d"%id)
		check(l.source==Rect2i(1,2,3,4) and l.mask_rect==Rect2i(9,10,11,12),"full reset retains independent source/dither geometry for layer%d"%id)
	check(m.layers[9]==nine,"layer9 retains key/visible/drawable/mask; only its auxiliary offset resets")
	check(m.dithers==dither,"full reset preserves dither configuration, active flag and epoch")
	check(m.queues.is_empty() and m.motions.is_empty(),"full reset clears queue allocations and all ten motion domains")
	check(m.apd_instances.is_empty() and m.apd_resources.is_empty() and m.callbacks.is_empty(),"full reset releases APD instances/resources and callback surfaces")
	check(m.wave_slots.is_empty() and m.last_released_waves==["own-a","own-b"],"full reset records and releases all loaded wave slots")
	check(m.bitmaps[0].stem=="OWN_A","full reset does not release the bitmap resource table")
	check(m.local_epoch==77 and m.global_epoch==88 and m.palette_until==99,"full reset leaves independent timing/palette domains untouched")
	check(m.photos=={1:{"own":true}} and m.bands=={1:{"own":true}},"full reset has no invented photo/palette-band destructor")
	check(scene.commands().is_empty(),"empty native destinations do not draw fill colors using the retained source rectangle")
	# A preserved active dither can update its current mask again on the next service.
	m.photos.clear();m.bands.clear();m.credits.clear();scene._advance_backend(m)
	check(m.layers[1].mask==456 and not m.dithers[1].active,"preserved dither remains serviceable after reset")
	var stops: Array=[];var vm=VM.new();vm.scene=scene
	vm.sound_stop_requested.connect(func(path):stops.append(path));vm._scene_operation({"operation":"reset_layer_scene","args":[0]})
	check(stops==["own-a","own-b"],"real VM propagates full-reset wave releases to audio stop signals")
	for connection in vm.get_signal_connection_list("sound_stop_requested"):vm.disconnect("sound_stop_requested",connection.callable)

func test_cue_lifetime() -> void:
	var data:=OwnData.new();var source: Array=data.records.duplicate(true);var scene=Scene.new(data);scene.profile=3
	var m:=model();scene._model=m
	apply(scene,m,"load_visual_cue",[10,1])
	check(m.bitmaps.keys()==[0] and m.cue_states[0]==1,"partial load stops after one successful matching row")
	check(not m.cue_states.has(1) and not m.cue_states.has(3),"partial load does not mark unvisited rows loaded")
	m.bitmaps[0]["sentinel"]=17;apply(scene,m,"load_visual_cue",[10,1])
	check(m.bitmaps[0].sentinel==17 and m.bitmaps.has(3),"a loaded1 row is skipped while a later matching row can load")
	check(not m.cue_states.has(1) and not m.cue_states.has(2) and not m.cue_states.has(4),"failed load, NO_ENTRY and other profile rows do not become loaded1")
	check(m.bitmaps[3].remaps==[[10,2,32]],"successful cue retains the source remap arguments")
	apply(scene,m,"layer_crop",[1,0,0,0,0,0,2,2]);apply(scene,m,"layer_transparent_index",[1,253]);apply(scene,m,"layer_aux_offset",[1,8,9])
	m.layers[1].mask=123;m.layers[1].mask_rect=Rect2i(1,2,3,4);m.layers[1].visible=false
	var layer: Dictionary=m.layers[1].duplicate(true);layer.offset=Vector2i.ZERO
	m.order=[1,9,0];m.clip=Rect2i(3,4,100,80);m.dithers[1]={"own":"config"};m.credits={"own":"text"};m.selected_layer=1
	m.queues[1]={"own":true};m.motions[1]={"own":true};m.apd_resources[0]={"own":true};m.apd_instances[0]={"own":true};m.callbacks[1]={"own":true};m.wave_slots[3]="own-wave"
	m.bitmaps[99]={"stem":"OWN_A","remaps":[]};scene.now=333
	apply(scene,m,"release_cue_reset_scene",[10])
	check(not m.bitmaps.has(0) and not m.bitmaps.has(3) and m.bitmaps.has(99),"release removes only loaded1 resources of the selected profile/cue")
	check(m.cue_states[0]==2 and m.cue_states[1]==2 and m.cue_states[3]==2,"release marks loaded and failed/not-loaded matching non-NO_ENTRY rows2")
	check(not m.cue_states.has(2) and not m.cue_states.has(4),"release skips NO_ENTRY and other profile records")
	check(m.layers[1]==layer,"cue release preserves drawable/key/visibility/dither geometry and resets only auxiliary offset")
	check(m.order==[1,9,0] and m.clip==Rect2i(3,4,100,80) and m.selected_layer==1,"cue release preserves draw order, clip and selected layer")
	check(m.dithers=={1:{"own":"config"}} and m.credits=={"own":"text"},"cue release does not erase dither configuration or text state")
	check(m.queues.is_empty() and m.motions.is_empty() and m.apd_resources.is_empty() and m.apd_instances.is_empty() and m.callbacks.is_empty(),"cue release clears exactly the shared temporary resource domains")
	check(m.local_epoch==77 and m.global_epoch==88 and m.last_released_waves==["own-wave"],"cue release preserves epochs and reports released wave slots")
	check(scene.commands().is_empty(),"released bitmap slots cannot emit stale bitmap commands despite preserved crop fields")
	apply(scene,m,"load_visual_cue",[10,1])
	check(m.cue_states[0]==1 and m.bitmaps.has(0) and m.cue_states[3]==2,"a released row2 can reload with the same partial-count semantics")
	apply(scene,m,"load_cue_reset_local_epoch",[12])
	check(m.cue_states[6]==1 and m.bitmaps.has(5) and m.local_epoch==333,"the dedicated cue-load wrapper resets local epoch and permits initial-state2 rows")
	check(data.records==source,"runtime cue states never mutate the immutable parsed cue records")
	# Duplicate resource IDs obey native slot ownership, not a fabricated row owner.
	apply(scene,m,"load_visual_cue",[11,0])
	check(m.bitmaps[0].stem=="OWN_B" and m.cue_states[0]==1 and m.cue_states[5]==1,"another cue may replace a resource slot while both row states remain1")
	apply(scene,m,"release_cue_reset_scene",[10])
	check(not m.bitmaps.has(0) and m.cue_states[5]==1,"release of an older loaded row frees its ID even when a later cue replaced that slot")
	apply(scene,m,"load_visual_cue",[11,0])
	check(not m.bitmaps.has(0),"loaded1 rows are skipped even if a duplicate-ID release left no live bitmap")
	apply(scene,m,"release_cue_reset_scene",[11]);apply(scene,m,"load_visual_cue",[11,0]);apply(scene,m,"load_visual_cue",[15,0])
	check(not m.bitmaps.has(0) and not m.cue_states.has(9),"failed nonempty load releases the previous bitmap but does not mark the failed row1")
	m.bitmaps[6]={"stem":"OWN_B","remaps":[]};apply(scene,m,"load_visual_cue",[13,0]);apply(scene,m,"load_visual_cue",[14,0])
	check(m.bitmaps.has(6) and not m.cue_states.has(7) and not m.cue_states.has(8),"empty filenames and invalid resource IDs fail before destroying a live slot")

func test_render_and_apd_cache() -> void:
	var scene=Scene.new(OwnData.new());scene.profile=3;var m:=model();scene._model=m;m.order=[0,1]
	apply(scene,m,"load_visual_cue",[10,0]);apply(scene,m,"load_visual_cue",[16,0])
	apply(scene,m,"layer_crop",[0,0,0,7,0,0,2,2]);apply(scene,m,"layer_crop",[1,0,0,0,0,0,2,2]);apply(scene,m,"layer_transparent_index",[1,253])
	var view=View.new();view.assets=OwnAssets.new();view.surface=FT2IndexedSurface.new()
	check(pixel(view,scene)==[21,42,22,249],"live own resources render with an explicit preserved key")
	apply(scene,m,"release_cue_reset_scene",[10])
	check(pixel(view,scene)==[41,42,43,44],"real View sees the remaining cue background, with no released foreground bitmap")
	apply(scene,m,"load_visual_cue",[10,1])
	check(pixel(view,scene)==[21,42,22,249],"reloading the same resource ID reactivates the retained crop/key without recropping")
	view.free()
	apply(scene,m,"APD_resource_load_remap",[0,0,144,64]);m.apd_resources[0].stem="OWN_APD"
	apply(scene,m,"APD_instance_create",[0,0,0,0,4]);scene._apply({"operation":"APD_instance_play_label","args":[0,0,1],"string_argument":"OWN"},m)
	scene._advance_backend(m);var old=scene._players[0].player
	apply(scene,m,"reset_layer_scene",[0]);apply(scene,m,"APD_resource_load_remap",[0,0,144,64]);m.apd_resources[0].stem="OWN_APD"
	apply(scene,m,"APD_instance_create",[0,0,0,0,4]);scene._apply({"operation":"APD_instance_play_label","args":[0,0,1],"string_argument":"OWN"},m)
	scene._advance_backend(m)
	check(scene._players[0].player!=old,"reset/recreate cannot reuse an APD player cached under identical stem/label/time")
	apply(scene,m,"release_cue_reset_scene",[99]);scene._advance_backend(m)
	check(scene._players.is_empty(),"backend drops stale cached APD instances after release")
	check(scene.errors.is_empty(),"all self-authored resource/reset operations are supported")

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene-reset-output="):output=arg.trim_prefix("--scene-reset-output=")
	call_deferred("run")

func run() -> void:
	test_full_reset();test_cue_lifetime();test_render_and_apd_cache()
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored cue table,2x2 indexed pixels,APD descriptors and wave identifiers only"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
