extends SceneTree
## Own palettes/one-frame APD only; test resource acquisition versus pixel-cache reuse.
const View=preload("res://scripts/render/ft2_battle_view.gd")
class OwnAssets extends FT2IndexedAssets:
	var rows: Dictionary={}
	func _init() -> void:
		for pair in [["OWN_A",41],["OWN_B",103],["OWN_Z",177]]:
			var colors:=PackedByteArray();colors.resize(768)
			for i in 768:colors[i]=(i*7+pair[1])%256
			rows[pair[0]]={"key":pair[0],"signature":pair[0],"width":2,"height":1,"pixels":PackedByteArray([144,145]),"palette":colors}
	func apd_image(key: String,_remaps: Array=[]) -> Dictionary:return rows.get(key,{})
	static func apd_palette_band(sheet: String,_first: int,_count: int) -> Vector2i:return Vector2i(208,16) if sheet=="OWN_Z" else Vector2i(144,64)
	static func is_apd_z_sheet(sheet: String) -> bool:return sheet=="OWN_Z"
class PaletteView extends View:
	func _refresh_actors(_preserve: bool=false) -> void:pass
var checks:=0
var failures: Array[String]=[]
var output:=""
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func state(p: FT2Palette) -> Array:return [p.current.duplicate(),p._fade_from.duplicate(),p._fade_to.duplicate(),p.progress,p.fading,p._epoch,p._interval]
func dataset(sheets: Array) -> Dictionary:
	return {"sheets":sheets,"parts":[[0,0,0,2,1,0,0,255]],"frames":[{"parts":[0],"pivot":0,"bounds":[0,0,2,1]}],"animations":{"OWN":{"groups":[{"move":[0,0],"velocity":[0,0],"steps":[[0,100,0,-1,0,0]]}]}}}
func run() -> void:
	var view=PaletteView.new();view.assets=OwnAssets.new();view.palette=FT2Palette.new();view.surface=FT2IndexedSurface.new()
	var initial:=PackedByteArray();initial.resize(768);initial.fill(19);view.palette.install(initial)
	var before:=state(view.palette);var base_before: PackedByteArray=view.palette.base.duplicate();var own:=dataset(["OWN_A"])
	view._actor_resource_stems[0]="OWN";view._acquire_actor_resource_palette(0,"OWN",own)
	check(view.palette.base.slice(432,624)==view.assets.rows.OWN_A.palette.slice(432,624),"resource callback copies its64 shared BASE entries")
	check(view.palette.base.slice(0,432)==base_before.slice(0,432)and view.palette.base.slice(624)==base_before.slice(624),"resource callback does not overwrite outside its BASE band")
	check(state(view.palette)==before,"acquisition does not realize CURRENT or disturb fade buffers/clock")
	check(view._actor_palette_acquired[0]=="OWN","acquisition belongs to the definition resource cache")
	var player:=FT2APDPlayer.new();player.play(own,"OWN",0,128)
	view._draw_apd(player,Vector2i.ZERO)
	check(state(view.palette)==before,"first body draw does not realize a resource palette again")
	check(view.surface.pixels[0]==144 and view.surface.pixels[1]==145,"actual indexed rendering remains functional after BASE-only acquisition")
	var changed: PackedByteArray=view.palette.base.duplicate();changed[206*3+2]=53;view.palette.install_base(changed,206,1)
	view._acquire_actor_resource_palette(0,"OWN",own)
	check(view.palette.base[206*3+2]==53,"a cache hit does not rerun the resource callback over later portrait BASE")
	# The native all-resource release does not invalidate cached CPU image bytes.
	view.set_script_state({"mode":4,"actor_cache_generation":1,"actor_cache_mode":-1,"sprites":[]})
	check(view._actor_palette_acquired.is_empty(),"native resource-cache generation releases its acquisition ownership")
	view._acquire_actor_resource_palette(0,"OWN",own)
	check(view.palette.base[206*3+2]==view.assets.rows.OWN_A.palette[206*3+2],"reacquiring the same cached image restores the resource BASE after a portrait")
	check(state(view.palette)==before,"same-image resource reload still leaves visible/fade state alone")
	view.palette.fade(PackedByteArray(),10,236,0,0)
	check(view.palette.current[206*3+2]==view.assets.rows.OWN_A.palette[206*3+2],"a later explicit restore uses the newly reacquired BASE")
	# Source callback order is sheet order, not per-draw install-once order.
	view._acquire_actor_resource_palette(1,"TWO",dataset(["OWN_A","OWN_B"]))
	check(view.palette.base.slice(432,624)==view.assets.rows.OWN_B.palette.slice(432,624),"last acquired sheet supplies the final64 BASE colors")
	var target: PackedByteArray=view.palette.base.duplicate();target.fill(0);view.palette.fade(target,10,236,8,100);view.palette.advance(120)
	var fading:=state(view.palette);view._acquire_actor_resource_palette(2,"Z",dataset(["OWN_Z"]))
	check(view.palette.base.slice(624,672)==view.assets.rows.OWN_Z.palette.slice(624,672),"Z preprocessing overrides the actor callback with its16 BASE entries")
	check(state(view.palette)==fading,"Z resource acquisition also preserves the running global fade exactly")
	# NPC-only native resource release retains party definition0 but releases10.
	view._actor_resource_stems[10]="NPC";view._acquire_actor_resource_palette(10,"NPC",own)
	view.set_script_state({"mode":4,"actor_cache_generation":1,"actor_npc_cache_generation":1,"actor_cache_mode":-1,"sprites":[]})
	check(view._actor_palette_acquired.has(0)and not view._actor_palette_acquired.has(10),"NPC cache release preserves party ownership and drops NPC acquisition state")
	view.free()
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored palettes,one-frame APD and resource cache epochs only"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--actor-palette-output="):output=arg.trim_prefix("--actor-palette-output=")
	call_deferred("run")
