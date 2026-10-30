extends SceneTree
## Self-authored2x2 raw indexed sheets; actual palette/remapper/APD renderer, no game assets.
const View=preload("res://scripts/render/ft2_battle_view.gd")
class OwnAssets extends FT2IndexedAssets:
	var folder:=""
	func add_image(key: String,raw: PackedByteArray,seed: int) -> void:
		var pal:=PackedByteArray();pal.resize(768)
		for i in 256:
			pal[i*3]=(seed+i*3)%256;pal[i*3+1]=(seed+i*5)%256;pal[i*3+2]=(seed+i*7)%256
		for index in [0,74]:set_rgb(pal,index,[0,0,0])
		set_rgb(pal,4,[0,0,128]);set_rgb(pal,7,[192,192,192]);set_rgb(pal,248,[128,128,128]);set_rgb(pal,255,[255,255,255])
		var name:=key.get_file();var ip:=folder.path_join(name+".idx");var pp:=folder.path_join(name+".pal")
		var f:=FileAccess.open(ip,FileAccess.WRITE);f.store_buffer(raw);f.close();f=FileAccess.open(pp,FileAccess.WRITE);f.store_buffer(pal);f.close()
		manifest.images[key]={"width":2,"height":2,"indices":ip,"palette":pp}
	func set_rgb(raw: PackedByteArray,index: int,rgb: Array) -> void:
		for ch in 3:raw[index*3+ch]=rgb[ch]
class PassiveFX:
	extends RefCounted
	var active:=false
class OwnBattle:
	extends RefCounted
	var substate:=1
var output:=""
var checks:=0
var failures: Array[String]=[]
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func state(p: FT2Palette) -> Array:
	return [p.base.duplicate(),p.current.duplicate(),p._fade_from.duplicate(),p._fade_to.duplicate(),p.progress,p.fading,p._epoch,p._interval]
func current_state(p: FT2Palette) -> Array:return state(p).slice(1)
func player(sheet: String) -> FT2APDPlayer:
	var p:=FT2APDPlayer.new();p.apd={"name":"OWN","sheets":[sheet],"parts":[[0,0,0,2,2,0,0,255]],"frames":[{"parts":[0],"pivot":0,"bounds":[0,0,2,2]}]};p.frame=0;p.visible=true;return p
func rgb(raw: PackedByteArray,index: int) -> PackedByteArray:return raw.slice(index*3,(index+1)*3)
func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--system-palette-output="):output=a.trim_prefix("--system-palette-output=")
	call_deferred("run")
func run() -> void:
	FT2Content.active=null
	var assets:=OwnAssets.new();assets.folder="user://own_system_palette_"+str(OS.get_process_id());DirAccess.make_dir_recursive_absolute(assets.folder);assets.manifest={"images":{}}
	assets.add_image("own/system.bmp",PackedByteArray([10,74,90,105]),17)
	assets.add_image("own/actor.bmp",PackedByteArray([10,11,25,26]),83)
	assets.add_image("own/face.bmp",PackedByteArray([10,74,255,11]),83)
	assets.add_image("own/other.bmp",PackedByteArray([10,74,90,105]),157)
	var view: FT2BattleView=View.new();view.assets=assets;view.palette=FT2Palette.new();view.surface=FT2IndexedSurface.new()
	var seed:=PackedByteArray();seed.resize(768);seed.fill(7);view.palette.install(seed)
	var system=assets.image("own/system.bmp",[[90,16,208],[10,64,144],[74,16,16]])
	var before:=current_state(view.palette)
	view._acquire_system_palette(system)
	check(current_state(view.palette)==before,"41ADB0 acquisition does not realize current/FROM/TO or change fade state")
	check(view.palette.base.slice(144*3,208*3)==system.palette.slice(144*3,208*3),"SYSTEM acquisition installs shared64 BASE colors")
	check(view.palette.base.slice(16*3,32*3)==system.palette.slice(16*3,32*3),"SYSTEM acquisition installs UI16 BASE colors")
	check(view.palette.base.slice(32*3,144*3)==seed.slice(32*3,144*3),"SYSTEM acquisition preserves map BASE colors")
	check(view.palette.base.slice(208*3,224*3)==seed.slice(208*3,224*3),"SYSTEM callback copies cycle table without installing its BASE")
	check(view._cycle_palette==system.palette.slice(208*3,224*3),"208/16 cycle source is copied at acquisition")
	check(system.pixels==PackedByteArray([144,16,208,223]),"actual SYSTEM source-remap boundaries are correct")
	# FrontendGDI replacement needs only reservedcolors and UI16..31, not game bands.
	view._initialize_frontend_palette(system)
	check(view.palette.current.slice(0,32*3)==system.palette.slice(0,32*3),"indexed startup/options adapter realizes its reserved and UI colors")
	check(view.palette.current.slice(246*3)==system.palette.slice(246*3),"indexed startup/menu highlights retain reserved high colors")
	check(view.palette.current.slice(32*3,246*3)==seed.slice(32*3,246*3),"frontend bootstrap never realizes map/shared/private game bands")
	check(rgb(view.palette.current,7)!=rgb(view.palette.current,16),"startup list foreground16 contrasts with dialog panel7")
	check(rgb(view.palette.current,255)!=rgb(view.palette.current,7)and rgb(view.palette.current,4)!=rgb(view.palette.current,255),"startup title/menu reserved highlights and caption remain distinguishable")
	for entry in [[0,0,7],[1,0,16],[0,1,248],[1,1,255]]:view._draw_overlay({"op":"rect","rect":Rect2i(entry[0],entry[1],1,1),"color":entry[2],"filled":true})
	var ui_pixels:=view.surface.pixels
	check([ui_pixels[0],ui_pixels[1],ui_pixels[640],ui_pixels[641]]==[7,16,248,255],"actual indexed frontend paint preserves panel/list/highlight color indices")
	# OriginalstartupSYSTEM first, then actorresource BASE, then EVENT00 restore638.
	var actor=assets.apd_image("own/actor.bmp",[[10,64,144]])
	view.palette.install_base(actor.palette,144,64);view._mark_palette_loaded(actor,144,64)
	check(view.palette.base.slice(144*3,208*3)==actor.palette.slice(144*3,208*3),"later actor acquisition owns BASE shared band before restore")
	check(view.palette.base.slice(16*3,32*3)==system.palette.slice(16*3,32*3),"actor acquisition leaves SYSTEM UI band intact")
	view.palette_request({"kind":"black","start":10,"count":236,"interval":0})
	view.palette_request({"kind":"restore","start":10,"count":236,"interval":8})
	view.palette.advance(32)
	check(view.palette.fading and view.palette.progress==4,"fixture has an actual in-progress source restore fade")
	var pending:=state(view.palette);var shadow=player("own/system.bmp")
	view._draw_apd(shadow,Vector2i(4,4),"system")
	check(state(view.palette)==pending,"first SYSTEM shadow draw during restore cannot overwrite BASE/current/FROM/TO")
	var raw:=view.surface.pixels
	check([raw[4*640+4],raw[4*640+5],raw[5*640+4],raw[5*640+5]]==[144,16,208,223],"shadow/status APD still renders all SYSTEM bands")
	for i in 3:view._draw_apd(shadow,Vector2i(4,4),"system")
	check(state(view.palette)==pending,"repeated shadow/status draws preserve the fade exactly")
	view.palette.advance(1024)
	check(view.palette.progress==128 and view.palette.current.slice(144*3,208*3)==actor.palette.slice(144*3,208*3),"restore completes with actor colors, not SYSTEM shared colors")
	check(view.palette.current.slice(144*3,208*3)!=system.palette.slice(144*3,208*3),"different own SYSTEM palette cannot mask actor colors at first dialogue")
	# Tactical portrait acquisition is BASEonly/shared, private realization belongs to sourcepaint.
	var command={"op":"bitmap","key":"own/face.bmp","pos":Vector2i(8,8),"remaps":[[10,64,144],[74,16,224]],"palette_base_install":[[144,64]],"palette_install":[[224,16]],"transparent":255}
	check(view.service_script_commands([{"op":"paint_backdrop","commands":[command]}]).is_empty(),"actual source portrait paint path accepts own fixture")
	var dialogue:=state(view.palette)
	view._draw_apd(shadow,Vector2i.ZERO,"system")
	check(state(view.palette)==dialogue,"SYSTEM first/repeated dialogue shadow never realizes the portrait shared band")
	check(view.palette.current.slice(144*3,208*3)==actor.palette.slice(144*3,208*3),"dialogue retains correct shared actor/portrait colors")
	# An explicit sourcepalette consumer still owns realization; acquisition marking is not global.
	var changed:=view.palette.base.duplicate();changed[144*3]=231;view.palette.install_base(changed,144,1)
	view._draw_apd(shadow,Vector2i.ZERO,"system")
	check(view.palette.current[144*3]!=231 and view.palette.base[144*3]==231,"drawing does not realize a later BASE change")
	view.palette_request({"kind":"restore","start":144,"count":64,"interval":0})
	check(view.palette.current[144*3]==231,"explicit original restore caller still realizes the changed shared band")
	# A different image using an existing SYSTEM policy remains outside this acquisition marker.
	var other=player("own/other.bmp");view._draw_apd(other,Vector2i.ZERO,"system")
	var other_image=assets.apd_image("own/other.bmp",[[90,16,208],[10,64,144],[74,16,16]])
	check(view.palette.current.slice(144*3,208*3)==other_image.palette.slice(144*3,208*3),"unacquired different-image caller is not blanket-disabled by SYSTEM policy")
	var current_before_reload:=current_state(view.palette);view._acquire_system_palette(system)
	check(current_state(view.palette)==current_before_reload,"explicit SYSTEM reacquisition remains BASEonly even after another caller")
	check(view.palette.base.slice(144*3,208*3)==system.palette.slice(144*3,208*3),"resource reacquisition can legitimately replace shared BASE before a later actor reload")
	view.palette.install_base(actor.palette,144,64);view.palette_request({"kind":"restore","start":144,"count":64,"interval":0})
	var shared_before_cycle:=view.palette.current.slice(144*3,208*3);var base208:=view.palette.base.slice(208*3,224*3)
	view.battle=OwnBattle.new();view.physical=PassiveFX.new();view.magic=PassiveFX.new();view.clock_ms=120
	view.parent_palette_cycle(1)
	check(view.palette.current.slice(208*3,224*3)==view._cycle_palette,"actual parent UI cycle caller can realize its private16 colors")
	check(view.palette.base.slice(208*3,224*3)==base208,"private cycle realization does not invent SYSTEM BASE208 acquisition")
	check(view.palette.current.slice(144*3,208*3)==shared_before_cycle,"private cycle does not disturb the shared actor colors")
	view.free()
	var report={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored2x2 rawpalettes/APDs; actual remapper, palette, APD/sourcepaint/frontend-color commands; no original assets","startup_check":"palette-level indexed frontend contrast/paint only, not hostGDI or fontlayout screenshot"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var f:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));f.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
