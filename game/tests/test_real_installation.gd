extends SceneTree
## Explicit, bounded private smoke test. No screenshots, autoplay, or stat edits.
var source_root := ""
var cache_root := ""
var report_path := ""
var mod_root := ""
var failures: Array[String] = []
var observations: Dictionary = {}
var captured_plan: Dictionary = {}
var total_ticks := 0
var base_profile := ""

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	if not value: failures.append(label)

func make_app(save_index: int):
	var app = load("res://scripts/main.gd").new()
	app._automation={"save":save_index,"skip_restart_script":false,"duration_ms":1000000000,"source_windowed":true,
		"settings":{"forced_stage":0,"complete_flag":0,"skip_effect":false,"skip_ally":false,"skip_enemy":false,"skip_zoom":false}}
	root.add_child(app);app.set_process(false);app.ui.persistence_enabled=false
	app.battle.visual_requested.connect(func(plan): captured_plan = plan.duplicate(true))
	return app

func release_app(app) -> void:
	app._release_runtime();app.queue_free()
	await process_frame;await process_frame
	await create_timer(0.3).timeout

func state(app) -> Dictionary:
	var units := PackedByteArray()
	for unit in app.battle.snapshot_units(): units.append_array(unit)
	return {"units":units,"map_id":int(app.battle.map_id),"money":int(app.battle.money),"round":int(app.battle.round_index),
		"inventory":app.battle.inventory.duplicate(),"event":int(app.vm.current_event)}

func health(app) -> bool:
	return app.errors.is_empty() and app.vm.errors.is_empty() and app.vm.scene.errors.is_empty() and app.audio.failures.is_empty() and app.view.unsupported.is_empty() and app.view.assets.missing.is_empty() and app.view.font.missing.is_empty()

func errors(app) -> Dictionary:
	# Counts only: do not serialize original scenario text, pixels or raw unit data.
	return {"engine":app.errors.size(),"vm":app.vm.errors.size(),"scene":app.vm.scene.errors.size(),
		"audio":app.audio.failures.size(),"unsupported":app.view.unsupported.size(),
		"assets":app.view.assets.missing.size(),"fonts":app.view.font.missing.size()}

func confirm_text(app) -> void:
	if not app.vm.input_wait and not app.ui.dialog in ["message","battle_message","scene_growth"]: return
	var key := InputEventKey.new();key.keycode=KEY_SPACE;key.pressed=true;app._input(key)
	key=InputEventKey.new();key.keycode=KEY_SPACE;key.pressed=false;app._input(key)

func tick(app) -> void:
	confirm_text(app)
	app._tick(50);total_ticks+=1
	await process_frame

func controllable(app) -> bool:
	return int(app.vm.mode)==1 and not app.vm.busy and not app.ui.blocks_outer_frame() and str(app.battle.phase)=="player" and int(app.battle.map_id)>=0

func settle(app, maximum: int) -> bool:
	for unused in range(maximum):
		if controllable(app) and int(app.battle.substate)==0: return true
		if not health(app): return false
		await tick(app)
	return controllable(app) and int(app.battle.substate)==0

func target_from_mask(battle) -> int:
	var best := -1
	for offset in battle._selection_mask:
		var position: Vector2i = battle.navigation.origin+offset
		var slot: int = battle.navigation.occupant(position)
		if slot<0 or not battle.rules.hostile(battle.units[battle.selected_slot],battle.units[slot],slot==battle.selected_slot):continue
		if best<0 or battle.units[slot].decode_s16(38)>battle.units[best].decode_s16(38):best=slot
	return best

func attempt_attack(app) -> Dictionary:
	var battle = app.battle
	for actor in range(10):
		var unit: PackedByteArray = battle.units[actor]
		if unit.decode_u16(0)==0 or unit.decode_u16(18)!=0 or unit.decode_s32(96)!=0:continue
		var weapon := int(unit.decode_u16(20))*56
		if battle.rules.items.decode_u16(weapon+50)==3:continue # Do not enter the known unshipped-bow diagnostic path.
		if not battle.select_unit(actor):continue
		var origin: Vector2i = battle.rules.xy(battle.units[actor])
		var destinations: Array = []
		for offset in battle.navigation.grid.keys():
			var point: Vector2i = battle.navigation.origin+offset
			if point!=origin and battle.navigation.occupant(point)<0 and battle.navigation.selectable(point,battle._selection_mask):destinations.append(point)
		destinations.sort_custom(func(a,b):
			var distance_a: int = absi(a.x-origin.x)+absi(a.y-origin.y)
			var distance_b: int = absi(b.x-origin.x)+absi(b.y-origin.y)
			return distance_a<distance_b if distance_a!=distance_b else a.x<b.x if a.x!=b.x else a.y<b.y)
		destinations=destinations.slice(0,20)
		destinations.append(origin)
		for destination in destinations:
			battle.cancel_selection()
			if not battle.select_unit(actor):break
			if destination!=origin and not battle.select_cell(destination):continue
			var target := target_from_mask(battle)
			if target<0:continue
			captured_plan={}
			var target_position: Vector2i = battle.rules.xy(battle.units[target])
			var before_hp: int = battle.units[target].decode_s16(38)
			if not battle.select_cell(target_position):continue
			var completed := await settle(app,600)
			var after_position: Vector2i = battle.rules.xy(battle.units[actor])
			return {"attempted":true,"actor_slot":actor,"target_slot":target,"completed":completed,
				"move_observed":after_position!=origin,"action_consumed":battle.units[actor].decode_s32(96)!=0,
				"numeric_plan_observed":not captured_plan.get("results",[]).is_empty(),
				"hp_changed":battle.units[target].decode_s16(38)!=before_hp,"state_errors":errors(app)}
		battle.cancel_selection()
	return {"attempted":false,"reason":"No eligible physical action in this natural save; no state was modified to manufacture one."}

func attempt_move(app) -> Dictionary:
	var battle = app.battle
	for actor in range(10):
		if battle.units[actor].decode_u16(0)==0 or battle.units[actor].decode_u16(18)!=0 or battle.units[actor].decode_s32(92)!=0:continue
		if not battle.select_unit(actor):continue
		var origin: Vector2i = battle.rules.xy(battle.units[actor])
		for offset in battle.navigation.grid.keys():
			var point: Vector2i = battle.navigation.origin+offset
			if point==origin or battle.navigation.occupant(point)>=0 or not battle.navigation.selectable(point,battle._selection_mask):continue
			var direction: int = battle.units[actor].decode_u16(6)
			if not battle.select_cell(point):continue
			if battle.substate==1: battle.select_cell(point) # A normal second click opens facing selection.
			if not battle.commit_facing(direction):
				battle.cancel_selection();continue
			var completed := await settle(app,400)
			return {"attempted":true,"actor_slot":actor,"completed":completed,
				"move_observed":battle.rules.xy(battle.units[actor])!=origin,"move_consumed":battle.units[actor].decode_s32(92)!=0}
		battle.cancel_selection()
	return {"attempted":false,"reason":"No unused legal movement in the selected natural save."}

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--real-source="):source_root=argument.trim_prefix("--real-source=")
		elif argument.begins_with("--real-cache="):cache_root=argument.trim_prefix("--real-cache=")
		elif argument.begins_with("--real-report="):report_path=argument.trim_prefix("--real-report=")
		elif argument.begins_with("--real-mod="):mod_root=argument.trim_prefix("--real-mod=")
	if source_root=="" or cache_root=="" or report_path=="":
		printerr("Explicit --real-source, --real-cache and --real-report are required");quit(2);return
	var connection := FT2Content.activate(cache_root,source_root)
	check(bool(connection.ok),"Real installation and cache did not bind")
	if not connection.ok:
		write_report();return
	base_profile=FT2Content.active.profile_id
	FT2Content.active.profile_id="real-smoke-"+str(Time.get_ticks_usec()) # Isolate test saves; no gameplay fields are altered.
	var app=make_app(29)
	await settle(app,120)
	observations.load29={"map_id":int(app.battle.map_id),"unit_slots":app.battle.units.size(),"errors":errors(app)}
	check(app.battle.units.size()==50 and health(app),"Natural SAVE29 load or rendering failed")
	await release_app(app)
	app=make_app(-1) # Normal fresh-app automation branch calls _new_game().
	for unused in range(20): await tick(app)
	observations.new_game={"event":int(app.vm.current_event),"loaded_event":int(app.vm.loaded_event),"busy":bool(app.vm.busy),"errors":errors(app)}
	check(app.vm.loaded_event==0 and health(app),"Normal new-game bootstrap failed")
	await release_app(app)
	app=make_app(29)
	var attack: Dictionary = {"attempted":false}
	var selected_save := -1
	for index in [29,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28]:
		if index!=29:
			await release_app(app)
			app=make_app(index)
		if not await settle(app,100):continue
		attack=await attempt_attack(app)
		if bool(attack.get("attempted",false)):
			selected_save=index;break
	observations.attack=attack;observations.action_save_index=selected_save
	check(bool(attack.get("attempted",false)),"No natural legal physical action found within the original saves")
	if attack.get("attempted",false):
		check(bool(attack.get("completed",false)) and bool(attack.get("action_consumed",false)) and bool(attack.get("numeric_plan_observed",false)) and health(app),"Representative legal attack did not finish normally")
		var move: Dictionary = {"attempted":true,"completed":true,"move_observed":true,"combined_with_attack":true} if attack.get("move_observed",false) else await attempt_move(app)
		observations.move=move
		check(bool(move.get("completed",false)) and bool(move.get("move_observed",false)),"Representative legal movement did not finish normally")
	if controllable(app) and int(app.battle.substate)==0:
		var before := state(app)
		app._save_game(97)
		app._load_save(97,true)
		var after := state(app)
		check(before==after,"Engine save/reload state changed before the normal Restart script")
		var resumed := await settle(app,120)
		observations.save_reload={"slot":97,"state_equal_immediately_after_reload":before==after,"normal_restart_controllable":resumed,"errors":errors(app)}
		check(resumed and health(app),"Saved-game normal Restart did not return to player control")
	else:failures.append("Save/reload skipped because the action did not return to normal player control")
	var base_items: PackedByteArray = app.data.raw_table("item")
	var base_magics: PackedByteArray = app.data.raw_table("magic")
	await release_app(app)
	if mod_root!="":
		var enabled := FT2Content.activate(cache_root,source_root,[mod_root])
		check(bool(enabled.ok),"Example custom mod did not mount")
		if enabled.ok:
			FT2Content.active.profile_id="real-smoke-mod-"+str(Time.get_ticks_usec())
			app=make_app(29)
			check(app.battle.rules.items.decode_u16(56+20)==10 and int(app.data.load_table("item")[1].price)==10,"Custom item price did not reach engine and UI records")
			check(app.battle.rules.magics.decode_s16(64+22)==3 and int(app.data.load_table("magic")[1].mp)==3,"Custom MP did not reach engine and UI records")
			await release_app(app)
		var disabled := FT2Content.activate(cache_root,source_root)
		check(bool(disabled.ok),"Base content did not remount after disabling mod")
		if disabled.ok:
			var restored:=FT2Data.new()
			check(restored.raw_table("item")==base_items and restored.raw_table("magic")==base_magics,"Disabling custom mod did not restore original tables")
		observations.mod_toggle={"tested":true,"combat_action_tests_used_mods":false}
	else:failures.append("Explicit example mod folder required for mod-toggle verification")
	write_report()

func write_report() -> void:
	var report := {"passed":failures.is_empty(),"failures":failures,"observations":observations,"ticks":total_ticks,
		"screenshots_written":false,"gameplay_stats_modified_by_test":false,"autoplay_campaign_used":false,
		"scope":"Original-data startup/new-game bootstrap, one bounded legal movement/physical attack, engine save/reload, isolated example-mod toggle. Not full campaign or pixel-equivalence proof."}
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var output:=FileAccess.open(report_path,FileAccess.WRITE);output.store_string(JSON.stringify(report,"\t"));output.close()
	FT2Content.active=null
	print("FT2_REAL_INSTALLATION ",JSON.stringify({"passed":report.passed,"failures":failures,"ticks":total_ticks}))
	quit(0 if failures.is_empty() else 1)
