extends SceneTree
## Self-authored 2x2 sheets only; exercise VM acquisition and actual indexed rendering.
const View=preload("res://scripts/render/ft2_battle_view.gd")
const VM=preload("res://scripts/scenario/ft2_vm.gd")
const Jobs=preload("res://scripts/scenario/ft2_actor_jobs.gd")
class TestView extends View:
	func _refresh_actors(_preserve: bool=false) -> void:pass
	func _draw_facing_cursor() -> void:pass
class PassiveFX:
	extends RefCounted
	var suppressed: Dictionary={}
	var active:=false
	var caster: Dictionary={}
	var children: Array=[]
	func direct_render() -> bool:return false
class OwnAssets extends FT2IndexedAssets:
	var folder:=""
	func apd(stem: String) -> Dictionary:
		var sheet: String={"OWNMAP":"sprite/ownmap.bmp","OWNHIGH":"sprite/31_effect.bmp","OWNZ":"sprite/31_ownz.bmp"}.get(stem,"sprite/ownactor.bmp")
		var still:={"groups":[{"move":[0,0],"velocity":[0,0],"steps":[[0,100,0,-1,0,0]]}]}
		return {"name":stem,"sheets":[sheet],"parts":[[0,0,0,2,2,0,0,255]],"frames":[{"parts":[0],"pivot":0,"bounds":[0,0,2,2]}],"animations":{"F.SET":still,"F.ACT":still.duplicate(true)}}
	func add_image(key: String,raw: PackedByteArray,seed: int) -> void:
		var pal:=PackedByteArray();pal.resize(768)
		for index in 256:
			pal[index*3]=(index+seed)%256;pal[index*3+1]=(index*3+seed)%256;pal[index*3+2]=(index*7+seed)%256
		var stem:=key.get_file();var ip:=folder.path_join(stem+".idx");var pp:=folder.path_join(stem+".pal")
		var file:=FileAccess.open(ip,FileAccess.WRITE);file.store_buffer(raw);file.close()
		file=FileAccess.open(pp,FileAccess.WRITE);file.store_buffer(pal);file.close()
		manifest.images[key]={"width":2,"height":2,"indices":ip,"palette":pp}
class OwnData:
	extends RefCounted
	func encode_unit(values: Dictionary) -> PackedByteArray:
		var raw:=PackedByteArray();raw.resize(124);raw.fill(0)
		for p in [["kind",0],["definition_id",2],["direction",6],["control",18]]:raw.encode_u16(p[1],int(values.get(p[0],0)))
		for p in [["x",8],["y",12]]:raw.encode_u32(p[1],int(values.get(p[0],0)))
		return raw
	func decode_unit(raw: PackedByteArray,slot: int) -> Dictionary:
		var row:={"slot":slot}
		for p in [["kind",0],["definition_id",2],["direction",6],["control",18]]:row[p[0]]=raw.decode_u16(p[1])
		for p in [["x",8],["y",12]]:row[p[0]]=raw.decode_s32(p[1])
		return row
	func load_apd(_stem: String) -> Dictionary:return {}
class OwnRules:
	extends RefCounted
	func construct(units: Array,descriptor: PackedByteArray,seeds: Array) -> Dictionary:
		var result:=units.duplicate()
		for slot in range(10,result.size()):
			if result[slot].decode_u16(0)==0:result[slot]=descriptor.duplicate();return {"units":result,"seeds":seeds.duplicate(),"slot":slot}
		return {"units":result,"seeds":seeds.duplicate(),"slot":-1}
class OwnBattle:
	extends RefCounted
	var units: Array=[]
	var rng: Array=[1,2,3]
	var rules=OwnRules.new()

var checks:=0
var failures: Array[String]=[]
var output:=""
var assets: OwnAssets
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func palette_state(palette: FT2Palette) -> Array:
	return [palette.base.duplicate(),palette.current.duplicate(),palette._fade_from.duplicate(),palette._fade_to.duplicate(),palette.progress,palette.fading,palette._epoch,palette._interval]
func visible_state(palette: FT2Palette) -> Array:
	return [palette.current.duplicate(),palette._fade_from.duplicate(),palette._fade_to.duplicate(),palette.progress,palette.fading,palette._epoch,palette._interval]
func fixture() -> Dictionary:
	var data:=OwnData.new();var battle:=OwnBattle.new()
	for slot in 50:battle.units.append(data.encode_unit({}))
	battle.units[0]=data.encode_unit({"kind":1,"definition_id":0})
	var view:=TestView.new();view.assets=assets;view.data=data;view.battle=battle;view.palette=FT2Palette.new();view.surface=FT2IndexedSurface.new();view.physical=PassiveFX.new();view.magic=PassiveFX.new();view.game_mode=4;view._service_mode="palette_test"
	var pal:=PackedByteArray();pal.resize(768);pal.fill(7);view.palette.install(pal)
	var vm:=VM.new();vm.data=data;vm.battle=battle;vm.jobs=Jobs.new(data);vm.mode=4;vm.actor_cache_mode=4;vm.actor_changed.connect(view.set_script_state)
	return {"view":view,"vm":vm}
func create(f: Dictionary,stem: String,kind: int) -> int:
	f.vm._create_actor([stem,kind,1,1],true)
	var slot: int=f.vm._actor(kind)
	if slot>=0:
		f.vm._execute(8,[slot,"F.SET",0])
		f.vm.actor_sprites[slot]["pos"]=Vector2i(4,0);f.vm._emit_actor_state()
	return slot
func pixels(view: TestView) -> Array:
	view._render(false)
	var raw:=view.surface.pixels
	return [raw[4],raw[5],raw[644],raw[645]]
func cleanup(f: Dictionary) -> void:
	f.vm.actor_changed.disconnect(f.view.set_script_state);f.view.free()
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--script-palette-output="):output=arg.trim_prefix("--script-palette-output=")
	call_deferred("run")
func run() -> void:
	FT2Content.active=null
	assets=OwnAssets.new();assets.folder="user://own_script_palette_"+str(OS.get_process_id());DirAccess.make_dir_recursive_absolute(assets.folder)
	assets.manifest={"images":{},"apds":{}}
	assets.add_image("sprite/ownmap.bmp",PackedByteArray([10,73,121,122]),23)
	assets.add_image("sprite/ownactor.bmp",PackedByteArray([10,11,25,26]),91)
	assets.add_image("sprite/31_effect.bmp",PackedByteArray([10,25,41,42]),149)
	assets.add_image("sprite/31_ownz.bmp",PackedByteArray([10,25,26,41]),197)
	# Boundary kinds must select resource remaps; the real renderer consumes VM metadata.
	for spec in [[999,"OWNMAP",144,64,[144,207,121,122]],[1000,"OWNMAP",32,112,[32,95,143,122]],[3999,"OWNMAP",32,112,[32,95,143,122]],[4000,"OWNHIGH",208,32,[208,223,239,42]]]:
		var f:=fixture();var view: TestView=f.view;var before:=palette_state(view.palette);var slot:=create(f,spec[1],spec[0]);var actor: Dictionary=f.vm.actor_sprites.get(slot,{})
		check(slot>=10,"kind%d creates a temporary unit"%spec[0])
		check(actor.get("palette_start")==spec[2]and actor.get("palette_count")==spec[3],"kind%d preserves acquired callback metadata"%spec[0])
		check(pixels(view)==spec[4],"kind%d renders exact source-boundary indices"%spec[0])
		check(visible_state(view.palette)==before.slice(1),"kind%d load/draw never changes current or fade"%spec[0])
		if spec[0]<4000:
			check(palette_state(view.palette)==before,"kind%d resource callback is remap only"%spec[0])
		else:
			var source=assets.apd_image("sprite/31_effect.bmp",[[10,32,208]])
			check(view.palette.base.slice(208*3,240*3)==source.palette.slice(208*3,240*3),"4000 acquisition copies only the effect BASE band")
			check(view.palette.base.slice(0,208*3)==before[0].slice(0,208*3)and view.palette.base.slice(240*3)==before[0].slice(240*3),"4000 acquisition preserves outside BASE entries")
		cleanup(f)
	# A normal actor and map-colored SNACK equivalent coexist without shared-current pollution.
	var f:=fixture();var view: TestView=f.view
	var body:=FT2APDPlayer.new();body.play(assets.apd("OWNBODY"),"F.SET",0,1)
	view._actors[0]={"slot":0,"player":body,"priority":4}
	view._draw_apd(body,Vector2i.ZERO)
	var shared:=palette_state(view.palette)
	var slot:=create(f,"OWNMAP",1000)
	check(pixels(view)==[32,95,143,122],"map-colored temporary body uses112 map colors beside normal actor")
	var raw:=view.surface.pixels
	check([raw[0],raw[1],raw[640],raw[641]]==[144,145,159,160],"normal actor still uses its64 shared colors in the same render")
	check(palette_state(view.palette)==shared,"temporary map draw preserves normal actor BASE/current/FROM/TO")
	# Repeated delivery, action changes, and future fade ticks cannot realize a temp palette.
	var target:=view.palette.base.duplicate();target.fill(0);view.palette.fade(target,10,236,8,100);view.palette.advance(132)
	var fading:=palette_state(view.palette)
	for repeat in 3:
		f.vm._emit_actor_state();pixels(view)
	check(palette_state(view.palette)==fading,"repeated state/draw retains the in-progress fade exactly")
	f.vm._execute(8,[slot,"F.ACT",0]);pixels(view)
	check(palette_state(view.palette)==fading,"new animation on a loaded resource does not reacquire/realize palette")
	cleanup(f)
	# Effect acquisition changes BASE only, once per actual OP13 resource load.
	f=fixture();view=f.view;view.palette.fade(PackedByteArray(),10,236,8,100);view.palette.advance(116)
	var current:=visible_state(view.palette);slot=create(f,"OWNHIGH",4000)
	check(visible_state(view.palette)==current,"effect resource acquisition leaves an active fade's current/from/to intact")
	var marker:=view.palette.base.duplicate();marker[208*3]=3;view.palette.install_base(marker,208,1)
	f.vm._emit_actor_state();pixels(view)
	check(view.palette.base[208*3]==3,"loaded effect repeated draw does not reacquire BASE")
	f.vm._create_actor([999,2,2],false)
	var reused: int=f.vm._actor(999);var metadata: Dictionary=f.vm.actor_sprites[reused]
	check(metadata.palette_start==208 and metadata.palette_count==32,"OP14 reuses acquired callback despite a different new kind")
	f.vm._execute(8,[reused,"F.SET",0]);f.vm.actor_sprites[reused]["pos"]=Vector2i(4,0);f.vm._emit_actor_state()
	check(pixels(view)==[208,223,239,42]and view.palette.base[208*3]==3,"OP14 reuses existing remap and does not reload effect BASE")
	var old_serial: int=metadata.palette_resource_serial
	create(f,"OWNHIGH",4001)
	check(f.vm._script_resource_serial>old_serial and view.palette.base[208*3]!=3,"new OP13 of the same file reacquires its BASE once")
	check(visible_state(view.palette)==current,"reloading effect BASE still preserves active fade current/from/to")
	cleanup(f)
	# Z overrides every caller callback: only source10..25 maps to208..223.
	for kind in [999,1000,4000]:
		f=fixture();view=f.view;var before:=palette_state(view.palette);create(f,"OWNZ",kind)
		check(pixels(view)==[208,223,26,41],"Z sheet overrides kind%d callback remap"%kind)
		var z=assets.apd_image("sprite/31_ownz.bmp",[])
		check(view.palette.base.slice(208*3,224*3)==z.palette.slice(208*3,224*3),"Z kind%d acquisition installs only its16 BASE colors"%kind)
		check(view.palette.base.slice(0,208*3)==before[0].slice(0,208*3)and view.palette.base.slice(224*3)==before[0].slice(224*3),"Z kind%d does not leak the caller's wider palette band"%kind)
		check(visible_state(view.palette)==before.slice(1),"Z kind%d never realizes current during load or draw"%kind)
		var marker_z:=view.palette.base.duplicate();marker_z[208*3]=5;view.palette.install_base(marker_z,208,1);f.vm._emit_actor_state();pixels(view)
		check(view.palette.base[208*3]==5,"Z kind%d repeated delivery/draw does not reload BASE"%kind)
		cleanup(f)
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored raw palettes,2x2 indexed sheets,APDs and unit descriptors only"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
