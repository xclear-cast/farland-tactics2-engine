extends SceneTree
## Private end-to-end editor/setup/runtime test. No screenshots unless requested.
class SetupWithoutStartup extends "res://scripts/content/ft2_content_setup.gd":
	func _ready() -> void: pass

var checks:=0
var failures: Array[String]=[]
var output:=""
var cache:=""
var source:=""
var capture:=false
var observations: Dictionary={}
var main

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--workflow-output="):output=argument.trim_prefix("--workflow-output=")
		elif argument.begins_with("--workflow-cache="):cache=argument.trim_prefix("--workflow-cache=")
		elif argument.begins_with("--workflow-source="):source=argument.trim_prefix("--workflow-source=")
		elif argument=="--workflow-capture":capture=true
	if output==""or cache==""or source=="":printerr("Explicit private workflow output/cache/source paths required");quit(2);return
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)

func path_key(path: String) -> String:
	var value:=path.replace("\\","/").simplify_path().trim_suffix("/")
	return value.to_lower()if OS.get_name()=="Windows"else value

func healthy() -> bool:
	return main!=null and main.errors.is_empty()and main.vm.errors.is_empty()and main.vm.scene.errors.is_empty()and main.audio.failures.is_empty()and main.view.unsupported.is_empty()and main.view.assets.missing.is_empty()and main.view.font.missing.is_empty()and main.campaign.errors.is_empty()

func error_counts() -> Dictionary:
	if main==null:return {"main_missing":1}
	return {"main":main.errors.size(),"vm":main.vm.errors.size(),"scene":main.vm.scene.errors.size(),
		"audio":main.audio.failures.size(),"render":main.view.unsupported.size(),"assets":main.view.assets.missing.size(),
		"fonts":main.view.font.missing.size(),"campaign":main.campaign.errors.size()}

func tick() -> void:
	main._tick(50)
	await process_frame

func write_report() -> void:
	var document={"passed":failures.is_empty(),"checks":checks,"failures":failures,"observations":observations,
		"source_game_data_uploaded":false,"source_game_files_written":false,"cache_files_written":false,
		"private_configuration_file":true,"actual_editor_controls":true,"actual_setup_to_scene_glue":true,
		"scope":"Private original-backed authoring/setup/own-story/map/one-own-skill/save roundtrip; not original campaign equivalence"}
	var report:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify(document,"\t"));report.close()
	print("FT2_EXPANSION_WORKFLOW ",JSON.stringify({"passed":document.passed,"checks":checks,"failures":failures,"observations":observations}))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	Engine.max_fps=30
	var original_core: Dictionary={}
	for logical in ["fixtures/item.dat","fixtures/magic.dat","fixtures/race.dat","assets/indexed/manifest.json"]:
		original_core[logical]=FileAccess.get_sha256(cache.path_join(logical))
	var setup:=SetupWithoutStartup.new()
	setup.config_path=output.path_join("connection.json") # Never write the user's normal app connection.
	setup.configuration={"source_root":source,"content_root":cache,"mods":[]}
	root.add_child(setup);current_scene=setup;setup._build_ui()
	setup._open_editor();await process_frame
	check(is_instance_valid(setup._editor),"setup opens the actual authoring editor")
	if not is_instance_valid(setup._editor):write_report();quit(1);return
	var editor=setup._editor
	editor.external_preview_enabled=false
	check(editor.data!=null,"editor receives the prepared original-data store")
	editor.buttons.new.pressed.emit()
	var pack_id: String="workflow_"+str(int(Time.get_unix_time_from_system()))+"_"+str(OS.get_process_id())
	editor.fields["project.id"].text=pack_id
	editor.fields["project.name"].text="직접 만든 통합 검증 확장팩"
	editor.fields["character.name"].text="통합 검증 주인공"
	for pair in [["hp.initial",100],["int.initial",200],["agi.initial",200]]:
		editor.fields["character."+str(pair[0])+".enabled"].button_pressed=true
		editor.fields["character."+str(pair[0])].value=int(pair[1])
	editor.buttons.apply_character.pressed.emit()
	editor.tabs.current_tab=1
	editor.fields["skill.name"].text="검증용 나의 기술"
	editor.fields["skill.power"].value=100
	editor.buttons.apply_skill.pressed.emit()
	editor.tabs.current_tab=3
	editor.fields["node.text"].text="제작 화면에서 직접 쓴 이야기가 실행됩니다."
	editor.buttons.apply_node.pressed.emit()
	var folder:=output.path_join("created-project")
	editor.project_path.text=folder
	check(editor.validate_project().ok,"project created through forms validates")
	var saved: Dictionary=editor.save_project(folder)
	check(saved.ok,"editor saves both expansion descriptors")
	var old_folder:=output.path_join("old-version")
	DirAccess.make_dir_recursive_absolute(old_folder)
	var old:=FileAccess.open(old_folder.path_join("mod.json"),FileAccess.WRITE)
	old.store_string(JSON.stringify({"schema":2,"id":pack_id,"content":"content.json"}));old.close()
	setup.mods_field.text=old_folder # Test that an older version with the same ID is replaced.
	editor.buttons.test_play.pressed.emit()
	for unused in range(80):
		await process_frame
		var candidate=get_current_scene()
		if candidate!=null and candidate.has_method("_new_game")and candidate.get("campaign")!=null:
			main=candidate;break
	check(main!=null,"save-and-test replaces setup with the actual main scene")
	if main==null:
		if is_instance_valid(setup):observations.setup_status=setup.status_label.text
		write_report();quit(1);return
	main.set_process(false);main.ui.persistence_enabled=false;Engine.max_fps=20
	var connection=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("connection.json")))
	check(connection is Dictionary and connection.mods.size()==1 and path_key(str(connection.mods[0]))==path_key(folder),"setup persists only the selected project version")
	check(FT2Content.active.layers.size()==1 and path_key(str(FT2Content.active.layers[0].root))==path_key(folder),"selected expansion is the mounted layer")
	check(str(main.campaign.story_id)==pack_id+":intro"and main.campaign.waiting=="dialogue","normal new-game path starts the newly authored story")
	check(str(main.campaign._text.text)=="제작 화면에서 직접 쓴 이야기가 실행됩니다.","authored dialogue reaches the actual runtime UI")
	if capture:
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("private-own-story.png"))
	main.campaign._continue.pressed.emit()
	for unused in range(10):
		if main.campaign.waiting=="battle":break
		await tick()
	check(main.campaign.waiting=="battle","dialogue/set/branch flow reaches the own battle")
	check(int(main.campaign.variables.get("ready",0))==1,"author-created variable condition executes")
	var registry=FT2Content.active.extensions
	check(int(main.battle.map_id)==int(registry.map_id(pack_id+":field")),"own map is loaded through registry numeric adapter")
	check(int(main.battle.map_data.get("width",0))==8 and int(main.battle.map_data.get("height",0))==8,"authored8x8map dimensions reach battle")
	var hero:=int(main.campaign.character_slots.get(pack_id+":hero",-1))
	var enemy:=int(main.campaign.character_slots.get(pack_id+":enemy",-1))
	check(hero>=0 and enemy>=0,"authored character placements spawn")
	if hero<0 or enemy<0:observations.errors=error_counts();write_report();quit(1);return
	check(int(main.battle.units[hero].decode_u16(2))>=int(registry.base_race_count),"custom hero uses a new race definition")
	check(main.battle.rules.xy(main.battle.units[hero])==Vector2i(2,2)and main.battle.rules.xy(main.battle.units[enemy])==Vector2i(3,2),"editor placement coordinates reach runtime")
	for unused in range(3):await tick() # Present the new map before capturing its GPU frame.
	if capture:
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("private-own-map-original-tile-references.png"))
	FT2Content.active.profile_id="workflow-private-"+str(OS.get_process_id())+"-"+str(Time.get_ticks_usec())
	var before: Dictionary=main.campaign.snapshot_state()
	main._save_game(96)
	check(main.campaign.has_slot(96),"normal main save path creates expansion slot")
	main._load_save(96)
	var after: Dictionary=main.campaign.snapshot_state()
	check(str(before.units_hex)==str(after.units_hex)and str(before.inventory_hex)==str(after.inventory_hex)and before.map==after.map and before.node==after.node,"normal main load restores own battle state")
	var action:=int(registry.skill_action_id(pack_id+":spark"))
	check(action>=int(registry.base_skill_count),"authored skill receives a new action ID")
	var old_hp:=int(main.battle.units[enemy].decode_s16(38))
	var old_mp:=int(main.battle.units[hero].decode_s16(42))
	var selected: bool=main.battle.select_unit(hero)
	var chosen: bool=main.battle.choose_action(action)if selected else false
	var accepted: bool=main.battle.select_cell(main.battle.rules.xy(main.battle.units[enemy]))if chosen else false
	check(selected and chosen and accepted,"new hero can legally cast the newly authored skill")
	check(str(main.battle.phase)=="confirm","normal target selection opens action confirmation")
	if accepted and str(main.battle.phase)=="confirm":main.ui.command(40024)
	check(str(main.battle.phase)!="confirm","the actual UI confirmation starts the authored action")
	for unused in range(400):
		if not healthy():break
		if main.campaign.waiting!="battle":break
		await tick()
	check(int(main.battle.units[enemy].decode_s16(38))<old_hp,"authored skill changes the actual target HP")
	check(int(main.battle.units[hero].decode_s16(42))<old_mp,"authored skill consumes actual MP")
	check(main.campaign.waiting=="dialogue"and str(main.campaign.node_id)=="won","natural own-battle outcome reaches authored victory dialogue")
	if main.campaign.waiting=="dialogue":main.campaign._continue.pressed.emit()
	check(main.campaign.completed and main.campaign.waiting=="end","authored story reaches its declared end")
	check(healthy(),"full workflow has no engine/VM/render/audio/font/campaign errors")
	observations={"editor_project_saved":saved.ok,"story_started":str(main.campaign.story_id),"map_id":int(main.battle.map_id),
		"hero_slot":hero,"enemy_slot":enemy,"new_skill_action":action,"target_hp_changed":int(main.battle.units[enemy].decode_s16(38))<old_hp,
		"story_completed":bool(main.campaign.completed),"errors":error_counts(),"private_screenshots":capture}
	for logical in original_core:
		check(FileAccess.get_sha256(cache.path_join(str(logical)))==str(original_core[logical]),"base cache core remains unchanged: "+str(logical))
	main._release_runtime();main.queue_free();await process_frame;await process_frame;await create_timer(0.3).timeout
	write_report();quit(0 if failures.is_empty()else 1)
