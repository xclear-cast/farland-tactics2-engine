extends SceneTree
## Own palette bytes and a scene spy only; no original assets or dialogue.
const View=preload("res://scripts/render/ft2_battle_view.gd")
const VM=preload("res://scripts/scenario/ft2_vm.gd")
class SceneSpy:
	extends RefCounted
	var events: Array=[]
	func start(selector: int) -> bool:
		events.append({"type":"scene_start","selector":selector})
		return true

var checks:=0
var failures: Array[String]=[]
var output:=""

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)

func pattern(seed: int) -> PackedByteArray:
	var result:=PackedByteArray();result.resize(768)
	for index in 768:result[index]=(seed+index*13)%256
	return result

func hardware(palette) -> Dictionary:
	return {"current":palette.current.duplicate(),"from":palette._fade_from.duplicate(),"to":palette._fade_to.duplicate(),"fading":palette.fading,"progress":palette.progress,"interval":palette._interval,"epoch":palette._epoch,"first":palette._start,"count":palette._count,"dirty":palette.dirty}

func create_view(seed: int):
	var view=View.new();view.palette=FT2Palette.new()
	view.palette.base=pattern(seed);view.palette.current=pattern(seed+1);view.palette._fade_from=pattern(seed+2);view.palette._fade_to=pattern(seed+3)
	view.palette.fading=true;view.palette.progress=57;view.palette._interval=9;view.palette._epoch=12345;view.palette._start=16;view.palette._count=80;view.palette.dirty=false
	return view

func restore_range_matches(actual: PackedByteArray,saved: PackedByteArray,prior: PackedByteArray) -> bool:
	return actual.slice(30,738)==saved.slice(30,738)and actual.slice(0,30)==prior.slice(0,30)and actual.slice(738,768)==prior.slice(738,768)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--story-palette-output="):output=arg.trim_prefix("--story-palette-output=")
	call_deferred("run")

func run() -> void:
	var view=create_view(11)
	var before:=hardware(view.palette);var prior: PackedByteArray=view.palette.base.duplicate()
	view.palette_request({"kind":"restore_script_base"})
	var zero:=PackedByteArray();zero.resize(768);zero.fill(0)
	check(restore_range_matches(view.palette.base,zero,prior),"restore before the first save uses BSS zero for BASE10..245 only")
	check(hardware(view.palette)==before,"BSS restore preserves hardware colors and the active fade state")
	var saved:=pattern(21);view.palette.base=saved.duplicate();before=hardware(view.palette)
	view.palette_request({"kind":"save_script_base"})
	check(view._script_saved_base.size()==768 and view._script_saved_base==saved,"save captures the complete normalized 256-entry BASE palette")
	check(view.palette.base==saved and hardware(view.palette)==before,"saving has no palette realization side effects")
	view.palette.base[31]=255-view.palette.base[31]
	check(view._script_saved_base==saved,"saved palette owns an independent copy")
	prior=pattern(31);view.palette.base=prior.duplicate()
	view.palette_request({"kind":"restore_script_base"})
	check(restore_range_matches(view.palette.base,saved,prior),"restore replaces only playable BASE10..245")
	check(hardware(view.palette)==before,"restore leaves current/from/to/fading/progress/interval/epoch unchanged")
	var replacement:=pattern(41);view.palette.base=replacement.duplicate()
	view.palette_request({"kind":"save_script_base"})
	check(view._script_saved_base==replacement,"a second save overwrites the single slot")
	prior=pattern(51);view.palette.base=prior.duplicate()
	view.palette_request({"kind":"restore_script_base"})
	check(restore_range_matches(view.palette.base,replacement,prior),"restore selects the latest slot rather than a palette stack")
	prior=pattern(61);view.palette.base=prior.duplicate()
	view.palette_request({"kind":"restore_script_base"})
	check(restore_range_matches(view.palette.base,replacement,prior),"restoring does not consume the saved palette")
	check(view._script_saved_base==replacement and hardware(view.palette)==before,"repeated restores preserve snapshot and active fade")
	view.free()
	# Real VM signals: the save must precede rendering and cinematic startup.
	var vm=VM.new();vm.mode=4
	var events: Array=[]
	vm.palette_requested.connect(func(request):events.append({"type":"palette","kind":str(request.kind),"context":vm.alternate_surface,"mode":vm.mode}))
	vm.source_commands_requested.connect(func(commands):
		var names: Array=[]
		for command in commands:names.append(str(command.op))
		events.append({"type":"source","ops":names}))
	vm._bitmap_sizes["BMP/OWN.BMP"]=Vector2i(16,16)
	check(not vm._execute(50,["own",3]),"bitmap opcode remains a non-yielding script command")
	check(events.size()==3 and events[0].get("kind")=="save_script_base","OP50 saves BASE before painting")
	check(events[1].get("ops")==["clear_rect","paint_main","present"]and events[2].get("kind")=="bitmap","OP50 paints then requests the bitmap palette transition")
	check(events[0].context==false and vm.alternate_surface,"OP50 saves before switching alternate context")
	events.clear();check(not vm._execute(51,[]),"restore opcode remains non-yielding")
	check(events.size()==2 and events[0].get("kind")=="restore_script_base"and events[1].get("ops")==["restore"],"OP51 emits BASE restoration before surface restore")
	check(events[0].context==true and not vm.alternate_surface,"OP51 restores before clearing alternate context")
	events.clear();vm._execute(50,["missing",0])
	check(events.is_empty()and not vm.alternate_surface,"failed bitmap loading does not overwrite the saved slot or switch context")
	var scene:=SceneSpy.new();scene.events=events;vm.scene=scene
	vm.scene_requested.connect(func(selector):events.append({"type":"scene_requested","selector":selector}))
	check(vm._execute(52,[7]),"cinematic opcode yields after starting its scene")
	check(events.size()==3 and events[0].get("kind")=="save_script_base"and events[1].type=="scene_start"and events[2].type=="scene_requested","OP52 saves before scene construction and notification")
	check(events[0].mode==4 and vm.mode==8 and vm.alternate_surface,"OP52 saves the preceding story state before entering scene mode")
	events.clear();vm._execute(51,[])
	check(events[0].get("kind")=="restore_script_base","OP51 also restores the slot after a cinematic")
	for signal_name in ["palette_requested","source_commands_requested","scene_requested"]:
		for connection in vm.get_signal_connection_list(signal_name):vm.disconnect(signal_name,connection.callable)
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored RGB palettes and scene observer only"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
