extends SceneTree
## Own scalar palette patterns; exercise real SYS53/54 -> View -> global fade.
const VM=preload("res://scripts/scenario/ft2_vm.gd")
const View=preload("res://scripts/render/ft2_battle_view.gd")
var checks:=0
var failures: Array[String]=[]
var output:=""
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func run() -> void:
	for opcode in [53,54]:
		var view=View.new();view.palette=FT2Palette.new();view.clock_ms=100
		var vm=VM.new();vm.palette_requested.connect(view.palette_request)
		var original:=PackedByteArray();original.resize(768)
		for i in 768:original[i]=(i*11+37)%256
		view.palette.install(original);var expected: PackedByteArray=original.duplicate()
		for i in range(32*3,144*3):expected[i]=int((int(original[i])+255)/2)
		for band in [[16,16],[144,64]]+([[208,32]] if opcode==53 else []):
			for i in range(band[0]*3,(band[0]+band[1])*3):expected[i]=int(int(original[i])*40/100)
		vm._system(opcode,[])
		check(view.palette.base==original,"SYS%d leaves all original BASE colors unchanged"%opcode)
		check(view.palette.current==expected,"SYS%d current colors match local whitening plus separate40percent bands"%opcode)
		check(view.palette.progress==128 and not view.palette.fading,"SYS%d immediate transforms finish the global fade"%opcode)
		check(view.palette._fade_from==expected and view.palette._fade_to==expected,"SYS%d committed targets preserve the local visible transform"%opcode)
		# A later source restore must recover the original background, not white BASE.
		view.clock_ms=200;vm.now_ms=200;vm._execute(2,[16]);view.palette.advance(2248)
		check(view.palette.base==original,"later restore retains the immutable BASE afterSYS%d"%opcode)
		check(view.palette.current.slice(30,738)==original.slice(30,738),"later restore recovers all236 playable colors afterSYS%d"%opcode)
		check(view.palette.progress==128 and not view.palette.fading,"restore reaches its actual128-step completion afterSYS%d"%opcode)
		vm.palette_requested.disconnect(view.palette_request);view.free()
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored RGB scalar pattern; no original images/data"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--whiten-output="):output=arg.trim_prefix("--whiten-output=")
	call_deferred("run")
