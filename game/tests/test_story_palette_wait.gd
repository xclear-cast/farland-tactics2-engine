extends SceneTree
## Own two-pixel images and palettes; exercise the actual VM -> View fade path.
const VM=preload("res://scripts/scenario/ft2_vm.gd")
const View=preload("res://scripts/render/ft2_battle_view.gd")

class OwnAssets extends FT2IndexedAssets:
	func image(key: String,_remaps: Array=[]) -> Dictionary:
		var colors:=PackedByteArray();colors.resize(768)
		for index in 256:
			colors[index*3]=(index*3+17)%256;colors[index*3+1]=(index*5+29)%256;colors[index*3+2]=(index*7+41)%256
		return {"key":key,"signature":key,"width":2,"height":1,"pixels":PackedByteArray([32,143]),"palette":colors}

var checks:=0
var failures: Array[String]=[]
var output:=""

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)

func fixture() -> Dictionary:
	var view=View.new();view.assets=OwnAssets.new();view.palette=FT2Palette.new();view.surface=FT2IndexedSurface.new();view.clock_ms=100
	var vm=VM.new();vm.now_ms=100;vm.mode=4;vm._bitmap_sizes["BMP/OWN.BMP"]=Vector2i(2,1)
	vm.palette_requested.connect(view.palette_request)
	vm.palette_busy_query=func() -> bool:return view.palette.progress != 128
	return {"view":view,"vm":vm}

func step(f: Dictionary,time: int) -> void:
	f.view.clock_ms=time;f.vm.now_ms=time;f.view.advance_palette_clock()

func wait(f: Dictionary) -> bool:
	f.vm._last_command=42;f.vm.pc=44
	return f.vm._execute(9,[])

func portrait(view) -> void:
	view._draw_overlay({"op":"bitmap","key":"BMP/OWN_FACE.BMP","pos":Vector2i.ZERO,"palette_base_install":[[144,64]],"palette_install":[[144,64],[224,16]]},true)

func cleanup(f: Dictionary) -> void:
	f.vm.palette_requested.disconnect(f.view.palette_request);f.vm.palette_busy_query=Callable();f.view.free()

func run() -> void:
	var f:=fixture();var vm=f.vm;var view=f.view
	check(not vm._execute(50,["own",8]),"OP50 starts its palette request without yielding")
	check(view.palette.fading and view.palette.progress==0,"real View starts the requested asynchronous bitmap fade")
	check(vm.fade_deadline==1124,"standalone fallback receives the OP50 unsigned interval deadline")
	vm.fade_deadline=0
	check(wait(f) and vm.pc==42,"OP9 queries the active palette and rewinds despite an expired legacy deadline")
	step(f,1100)
	check(view.palette.progress==125 and view.palette.fading,"one second does not prematurely finish an8ms-times128 fade")
	check(wait(f),"OP9 continues waiting for the remaining palette steps")
	step(f,1123)
	check(view.palette.progress==127 and wait(f),"OP9 still waits one millisecond before completion")
	step(f,1124)
	check(view.palette.progress==128 and not wait(f) and vm.pc==44,"OP9 resumes only after the actual global palette finishes")
	var completed: PackedByteArray=view.palette.current.slice(16*3,144*3)
	check(completed==view.palette.base.slice(16*3,144*3),"background/UI colors equal BASE after the wait completes")
	portrait(view)
	check(view.palette.current.slice(16*3,144*3)==completed,"a later portrait immediate request cannot freeze an unfinished background fade")
	cleanup(f)
	# The failure mechanism is explicit: global completion metadata alone does
	# not repair other bands when an immediate request interrupts a running fade.
	f=fixture();vm=f.vm;view=f.view;vm._execute(50,["own",8]);step(f,1100)
	var partial: PackedByteArray=view.palette.current.slice(16*3,144*3);portrait(view)
	check(not view.palette.fading and view.palette.progress==128,"portrait immediate band restoration stops the global fade")
	check(partial!=view.palette.base.slice(16*3,144*3) and view.palette.current.slice(16*3,144*3)==partial,"an interruption preserves other bands at their prior intermediate colors")
	vm.fade_deadline=999999
	check(not wait(f),"OP9 honors actual immediate completion even while a legacy deadline lies far ahead")
	cleanup(f)
	# Requests from outside the VM's timed opcode producers share the same state.
	f=fixture();vm=f.vm;view=f.view;vm.fade_deadline=0
	var colors: PackedByteArray=view.assets.image("OWN").palette
	view.palette.install_base(colors,10,236);view.palette_request({"kind":"restore","start":10,"count":236,"interval":16})
	check(wait(f),"an externally produced scene fade also blocks OP9")
	step(f,1200)
	check(wait(f),"elapsed time from an unrelated previous deadline cannot complete a newer palette request")
	view.palette_request({"kind":"black","start":144,"count":64,"interval":0})
	check(not wait(f),"a zero-ms request on another band cancels global busy immediately")
	view.clock_ms=1300;vm.now_ms=1300;view.palette_request({"kind":"restore","start":32,"count":112,"interval":4})
	check(wait(f),"a new palette epoch becomes authoritative after an interruption")
	step(f,1811);check(wait(f),"new epoch remains busy until its own128 steps complete")
	step(f,1812);check(not wait(f),"new epoch completes independently of earlier producer clocks")
	cleanup(f)
	# Source4180D0 truncates the interval to an unsigned16-bit word.
	for interval in [0,65536,-1]:
		f=fixture();vm=f.vm;view=f.view;vm._execute(50,["own",interval])
		var word: int=interval&0xFFFF
		check(vm.fade_deadline==100+word*128,"OP50 fallback follows the u16 interval for%d"%interval)
		check(wait(f)==(word!=0),"live palette busy follows the u16 interval for%d"%interval)
		if word!=0:
			step(f,100+word*128);check(not wait(f),"wrapped negative interval completes at its actual source duration")
		cleanup(f)
	# Other VM palette producers are observed rather than replaced by a timer.
	f=fixture();vm=f.vm;view=f.view;vm._execute(3,[8])
	check(wait(f),"existing black-fade opcode uses the same authoritative query")
	vm._system(22,[0]);check(not wait(f),"an immediate system palette request cancels that fade")
	vm.palette_busy_query=Callable();vm.now_ms=100;vm._execute(50,["own",8])
	check(wait(f),"an isolated unwired VM retains a correctly initialized OP50 fallback")
	vm.now_ms=1124;check(not wait(f),"unwired fallback expires at its own OP50 deadline")
	vm._bitmap_sizes.clear();vm.fade_deadline=17;vm._execute(50,["missing",8])
	check(vm.fade_deadline==17,"failed bitmap loading does not start a new fallback deadline")
	check(vm.errors.is_empty() and view.unsupported.is_empty(),"synthetic palette/wait operations have no unsupported errors")
	cleanup(f)
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored two-pixel images and RGB palettes only"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--palette-wait-output="):output=arg.trim_prefix("--palette-wait-output=")
	call_deferred("run")
