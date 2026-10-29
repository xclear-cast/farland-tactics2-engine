extends SceneTree
## Self-authored 2x2 indexed fixtures; no game data or original dialogue.
const View=preload("res://scripts/render/ft2_battle_view.gd")
const VM=preload("res://scripts/scenario/ft2_vm.gd")
class SyntheticAssets extends FT2IndexedAssets:
	var fixtures: Dictionary={}
	func _init() -> void:
		fixtures["synthetic/portrait_a.bmp"]=_image("a",{144:[100,20,30],224:[40,200,60]},[144,224,255,144])
		fixtures["synthetic/portrait_b.bmp"]=_image("b",{144:[10,40,200],224:[200,70,100]},[144,224,255,144])
		fixtures["synthetic/town.bmp"]=_image("town",{32:[70,80,90]},[32,32,32,32])
	func _image(signature: String,colors: Dictionary,indices: Array) -> Dictionary:
		var palette:=PackedByteArray();palette.resize(768);palette.fill(0)
		for index in colors:
			for channel in 3:palette[int(index)*3+channel]=int(colors[index][channel])
		return {"key":"synthetic/"+signature,"signature":"synthetic/"+signature,"width":2,"height":2,"pixels":PackedByteArray(indices),"palette":palette}
	func image(key: String,remaps: Array=[]) -> Dictionary:
		if key=="BMP/FACE91X.BMP": # A fictional fixture ID, not a game portrait.
			var result: Dictionary=fixtures["synthetic/portrait_a.bmp"].duplicate(true)
			result.signature="synthetic/vm-portrait"+JSON.stringify(remaps)
			var private_index:=int(remaps[1][2])
			result.pixels[1]=private_index
			for channel in 3:result.palette[private_index*3+channel]=result.palette[224*3+channel]
			return result
		return fixtures.get(key,{})

var output:=""
var checks:=0
var failures: Array[String]=[]

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--palette-output="):output=arg.trim_prefix("--palette-output=")
	call_deferred("run")

func create_view():
	var view=View.new()
	view.assets=SyntheticAssets.new();view.palette=FT2Palette.new();view.surface=FT2IndexedSurface.new()
	return view

func portrait(key: String) -> Dictionary:
	return {"op":"bitmap","key":"synthetic/portrait_"+key+".bmp","pos":Vector2i(2,2),"source":Rect2i(0,0,2,2),"transparent":255,"palette_install":[[144,64],[224,16]]}

func paint(view,commands: Array,target: String="backdrop") -> void:
	check(view.service_script_commands([{"op":"paint_"+target,"commands":commands}]).is_empty(),"source paint command handled: "+target)

func rgb(view,index: int) -> PackedByteArray:return view.palette.current.slice(index*3,index*3+3)

func run() -> void:
	var view=create_view()
	paint(view,[portrait("a")])
	check(rgb(view,144)==PackedByteArray([100,20,30])and rgb(view,224)==PackedByteArray([40,200,60]),"initial portrait installs both palette bands")
	check(view._source_backdrop_data.pixels[2*640+2]==144 and view._source_backdrop_data.pixels[3*640+2]==0,"portrait source pixels and transparency preserved")
	view.palette_request({"kind":"black","start":10,"count":236,"interval":0})
	view.palette_request({"kind":"bitmap","key":"synthetic/town.bmp","start":10,"count":236,"interval":0,"base_start":32,"base_count":208})
	check(rgb(view,32)==PackedByteArray([70,80,90])and rgb(view,144)==PackedByteArray([0,0,0]),"scene palette transition replaces prior portrait colors")
	paint(view,[portrait("a")])
	check(rgb(view,144)==PackedByteArray([100,20,30])and rgb(view,224)==PackedByteArray([40,200,60]),"repeated portrait restores its colors after black and town transition")
	paint(view,[portrait("b")],"main")
	check(rgb(view,144)==PackedByteArray([10,40,200])and rgb(view,224)==PackedByteArray([200,70,100]),"second portrait installs its own colors")
	paint(view,[portrait("a")],"main")
	check(rgb(view,144)==PackedByteArray([100,20,30])and rgb(view,224)==PackedByteArray([40,200,60]),"A to B to A restores the previously seen portrait")
	# Source commands may contain recursively drawn indexed groups.
	paint(view,[portrait("b")])
	paint(view,[{"op":"indexed_group","size":Vector2i(8,8),"commands":[portrait("a")],"pos":Vector2i.ZERO}])
	check(rgb(view,144)==PackedByteArray([100,20,30]),"source palette reload reaches nested indexed groups")
	# An ordinary draw of an already loaded actor resource must not cancel a fade.
	# This catches a broad fix that removes install-once caching from every frame.
	paint(view,[portrait("a")])
	var black:=PackedByteArray();black.resize(768);black.fill(0)
	view.palette.fade(black,144,1,1,0);view.palette.advance(64)
	var intermediate:=rgb(view,144)
	check(intermediate==PackedByteArray([50,10,15])and view.palette.fading,"partial palette fade established")
	var actor:=FT2APDPlayer.new();actor.frame=0;actor.state_mode=1
	actor.apd={"frames":[{"parts":[0],"pivot":0,"bounds":[0,0,2,2]}],"parts":[[0,0,0,2,2,0,0,255]],"sheets":["synthetic/portrait_a.bmp"]}
	for tick in 3:view._draw_apd(actor,Vector2i.ZERO,"actor")
	check(rgb(view,144)==intermediate and view.palette.fading,"ordinary repeated APD draws preserve the in-progress palette fade")
	view.service_script_commands([{"op":"keyed_backdrop_to_main"}])
	check(rgb(view,144)==intermediate,"persistent backdrop copying does not replay source palette loads")
	view.free()
	# Verify VM-generated commands distinguish BASE-only tactical shared colors
	# from the immediately realized shared colors of alternate bitmap scenes.
	var vm=VM.new()
	vm._bitmap_sizes["BMP/FACE91X.BMP"]=Vector2i(2,18)
	vm.dialogue_halves[0]={"speaker":91,"variant":"x","portrait":true,"window":false,"commands":[]}
	view=create_view()
	var seed:=PackedByteArray();seed.resize(768);seed.fill(0)
	seed[144*3]=9;seed[144*3+1]=8;seed[144*3+2]=7
	seed[208*3]=12;seed[208*3+1]=23;seed[208*3+2]=34
	view.palette.install(seed)
	var bottom: Dictionary=vm._dialogue_half_commands(0,false,false)[0]
	check(bottom.palette_base_install==[[144,64]]and bottom.palette_install==[[224,16]],"tactical bottom command separates shared BASE and private realization")
	paint(view,[bottom])
	check(view.palette.base.slice(144*3,145*3)==PackedByteArray([100,20,30])and rgb(view,144)==PackedByteArray([9,8,7]),"tactical acquisition changes shared BASE without overwriting current colors")
	check(view.palette._fade_to.slice(144*3,145*3)==PackedByteArray([9,8,7]),"BASE-only shared update does not replace the pending fade target")
	check(rgb(view,224)==PackedByteArray([40,200,60])and rgb(view,208)==PackedByteArray([12,23,34]),"bottom private palette realizes independently of top private palette")
	vm.dialogue_halves[1]=vm.dialogue_halves[0].duplicate(true)
	var top: Dictionary=vm._dialogue_half_commands(1,false,false)[0]
	check(top.palette_install==[[208,16]],"tactical top command realizes only its own private band")
	paint(view,[top])
	check(rgb(view,208)==PackedByteArray([40,200,60])and rgb(view,224)==PackedByteArray([40,200,60]),"top acquisition preserves the bottom private band")
	vm.alternate_surface=true
	bottom=vm._dialogue_half_commands(0,false,false)[0]
	check(bottom.palette_install==[[144,64],[224,16]],"alternate bitmap scene command realizes shared and bottom private bands")
	paint(view,[bottom])
	check(rgb(view,144)==PackedByteArray([100,20,30]),"alternate bitmap scene immediately restores shared portrait colors")
	var fallback: Array[Dictionary]=vm.draw_commands()
	var portrait_commands: Array=[]
	for command in fallback:
		if command.get("key")=="BMP/FACE91X.BMP":portrait_commands.append(command)
	check(portrait_commands.size()==2 and portrait_commands[0].palette_base_install==[[144,64]]and portrait_commands[1].palette_base_install==[[144,64]],"fallback VM draw path retains the same BASE loading contract")
	view.free()
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored synthetic indexed pixels only"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
