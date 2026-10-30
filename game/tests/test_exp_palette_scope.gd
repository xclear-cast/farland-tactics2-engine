extends SceneTree
## Own palette and one-party EXP dialog; no installation or original UI templates.
const View=preload("res://scripts/render/ft2_battle_view.gd")
const Dialog=preload("res://scripts/experience/ft2_exp_dialog.gd")
class OwnView:
	extends FT2BattleView
	var reentrant_draws:=0
	func draw_tactical_now() -> void:
		# Keep the real message-presentation continuation and indexed painter;
		# this fixture needs no maps or actor assets for the final overlay pass.
		reentrant_draws+=1
		for command in _overlay: _draw_overlay(command)
class OwnRules:
	extends RefCounted
	func s32(value: int) -> int:return value
	func balanced_distribution(_exp: Array,pool: int) -> Array:return [pool]
	func equal_distribution(_exp: Array,pool: int) -> Array:return [pool]
	func put16(raw: PackedByteArray,offset: int,value: int) -> void:raw.encode_u16(offset,value&65535)
class OwnBattle:
	extends RefCounted
	signal changed
	var units: Array=[]
	var rules=OwnRules.new()
class OwnAssets extends FT2IndexedAssets:
	func image(key: String,_remaps: Array=[]) -> Dictionary:
		var colors:=PackedByteArray();colors.resize(768);colors.fill(211)
		return {"key":key,"signature":"OWN_WALL","width":1,"height":1,"pixels":PackedByteArray([144]),"palette":colors}
var checks:=0
var failures: Array[String]=[]
var output:=""
var changed_saw_original:=false
var growth_saw_original:=false
var overlay_at_growth: Array=[]
var original_state: Array=[]
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func snapshot(view) -> Array:return [view.palette.base.duplicate(),view.palette.current.duplicate(),view.palette._fade_from.duplicate(),view.palette._fade_to.duplicate(),view.palette._start,view.palette._count,view.palette._interval,view.palette._epoch,view.palette.progress,view.palette.fading,view._installed.duplicate()]
func run() -> void:
	var view=OwnView.new();view.palette=FT2Palette.new();view.surface=FT2IndexedSurface.new();view.assets=OwnAssets.new()
	var original:=PackedByteArray();original.resize(768)
	for i in 768:original[i]=(i*17+31)%256
	view.palette.install(original);var black:=PackedByteArray();black.resize(768);black.fill(0)
	view.palette.fade(black,10,236,8,100);view.palette.advance(124)
	var game_overlay: Array=[{"op":"rect","rect":Rect2i(0,0,1,1),"color":37,"filled":true}]
	view.set_overlay(game_overlay)
	original_state=snapshot(view)
	var battle=OwnBattle.new();var unit:=PackedByteArray();unit.resize(124);unit.fill(0);unit.encode_u16(0,1);unit.encode_u16(44,100);battle.units=[unit]
	var dialog=Dialog.new();dialog._battle_ref=weakref(battle);dialog._template={"controls":[]}
	dialog.palette_scope_requested.connect(view.set_experience_palette_scope)
	battle.changed.connect(func():changed_saw_original=snapshot(view)==original_state)
	dialog.finished.connect(func(_accepted,_allocations):
		overlay_at_growth=view._overlay.duplicate(true)
		# The actual growth notice is presented synchronously from finished,
		# before Main's next frame can replace the EXP overlay command list.
		view.service_message_presentation("begin",{"commands":[]})
		growth_saw_original=snapshot(view)==original_state)
	check(dialog.open(20),"real dialog open accepts its own one-party EXP fixture")
	check(not view._experience_palette_snapshot.is_empty(),"successful dialog begins a game-palette scope before its first paint")
	var exp_paint: Dictionary={"op":"bitmap","key":"OWN_WALL","pos":Vector2i.ZERO,"palette_install":[[144,64],[16,16]],"transparent":-1}
	view.set_overlay([exp_paint]);view._draw_overlay(exp_paint)
	check(view.palette.current[145*3]==211,"the actual indexed UI paint can realize its own WALL colors")
	check(snapshot(view)!=original_state,"fixture demonstrates that UI realization borrowed game palette state")
	check(dialog.message(0x111,1)==1,"normal OK completes the real EXP dialog")
	check(battle.units[0].decode_u16(44)==120,"palette lifecycle does not alter actual EXP allocation")
	check(snapshot(view)==original_state,"normal dialog completion restores BASE/CURRENT/fade clock and install-cache ownership")
	check(changed_saw_original,"game palette is restored before the caller's changed/growth continuation")
	check(view._experience_palette_snapshot.is_empty(),"completed scope releases its saved state")
	check(growth_saw_original,"synchronous growth-message redraw cannot reinstall the closed EXP palette")
	check(overlay_at_growth==game_overlay,"the pre-dialog game overlay is restored before the finished continuation")
	check(view.reentrant_draws==1,"real message-presentation begin requests the immediate tactical redraw")
	check(view._overlay==game_overlay,"the transient EXP command list is released on normal completion")
	# Reopening must paint the UI again even if the same bitmap CPU cache survives.
	check(dialog.open(10),"second normal open succeeds")
	view.set_overlay([exp_paint]);view._draw_overlay(exp_paint)
	check(view.palette.current[145*3]==211,"same-image UI repaint is not suppressed by stale palette install markers")
	dialog.message(0x111,1)
	check(snapshot(view)==original_state,"repeated dialog close preserves the original interrupted fade state")
	check(growth_saw_original and view.reentrant_draws==2,"a second synchronous continuation also preserves the game palette")
	check(view._overlay==game_overlay,"repeated EXP completion restores the original overlay rather than an earlier dialog")
	# Failed source preconditions must never take a palette snapshot.
	battle.units=[]
	check(not dialog.open(5),"positive EXP with no party is rejected by the source precondition")
	check(view._experience_palette_snapshot.is_empty(),"failed open does not leave a borrowed palette scope")
	dialog.palette_scope_requested.disconnect(view.set_experience_palette_scope);view.free()
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"fixtures":"self-authored palettes,1x1WALL and one-party EXP records"}
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--exp-palette-output="):output=arg.trim_prefix("--exp-palette-output=")
	call_deferred("run")
