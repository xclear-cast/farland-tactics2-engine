extends SceneTree
class ProtectedData:
	extends RefCounted
	var source_root := ""
	var repo_root := ""
	func read_json(path: String) -> Dictionary:
		if path.contains("maps/index"):return {"maps":[{"map_id":40}]}
		var rows: Array=[]
		for i in range(74 if path.contains("race")else 84):rows.append({"id":i,"name":"자체 테스트 ID","stats":{}})
		return {"records":rows}
class SetupWithoutStartup extends "res://scripts/content/ft2_content_setup.gd":
	func _ready() -> void: pass
var checks:=0
var failures: Array[String]=[]
var output:=""
var capture:=false

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--editor-output="):output=arg.trim_prefix("--editor-output=")
		elif arg=="--editor-capture":capture=true
	if output.is_empty():quit(2);return
	call_deferred("run")

func select(editor,kind: String,index: int) -> void:
	editor.lists[kind].select(index);editor.lists[kind].item_selected.emit(index)

func metadata(option: OptionButton,value: String) -> void:
	for i in option.item_count:
		if str(option.get_item_metadata(i))==value:option.select(i);return

func run() -> void:
	Engine.max_fps=30
	root.size=Vector2i(1180,860);root.content_scale_size=Vector2i(1180,860)
	var font_path:=OS.get_environment("FT2_EDITOR_TEST_FONT")
	var theme: Theme
	if not font_path.is_empty():
		var font:=FontFile.new();font.data=FileAccess.get_file_as_bytes(font_path);theme=Theme.new();theme.default_font=font;theme.default_font_size=16
	var type=load("res://scripts/editor/ft2_expansion_editor.gd")
	var editor=type.new();editor.theme=theme;root.add_child(editor);editor.configure(null)
	await process_frame
	editor.buttons.new.pressed.emit()
	editor.fields["project.id"].text="editor_test"
	editor.fields["project.name"].text="직접 만든 확장팩"
	editor.buttons.add_characters.pressed.emit()
	editor.fields["character.id"].text="extra_hero";editor.fields["character.name"].text="추가 영웅"
	editor.fields["character.hp.initial.enabled"].button_pressed=true;editor.fields["character.hp.initial"].value=75
	editor.buttons.apply_character.pressed.emit()
	check(editor.project.content.characters.size()==3,"GUI adds a character")
	check(editor.project.content.characters[2].name=="추가 영웅","GUI stores own character name")
	check(int(editor.project.content.characters[2].stats["hp.initial"])==75,"GUI stat override")
	editor.tabs.current_tab=1;editor.buttons.add_skills.pressed.emit()
	editor.fields["skill.id"].text="extra_skill";editor.fields["skill.name"].text="추가 스킬"
	editor.fields["skill.mp"].value=4;editor.fields["skill.power"].value=16;editor.fields["skill.range_max"].value=2
	editor.buttons.apply_skill.pressed.emit()
	check(editor.project.content.skills.size()==2,"GUI adds a skill")
	check(int(editor.project.content.skills[1].mp)==4,"GUI skill MP")
	editor.tabs.current_tab=0;select(editor,"characters",2)
	metadata(editor.fields["character.skill_pick"],"extra_skill");editor.buttons.add_character_skill.pressed.emit();editor.buttons.apply_character.pressed.emit()
	check(editor.project.content.characters[2].skills==["extra_skill"],"skill selection control links new skill")
	editor.tabs.current_tab=2;editor.buttons.add_maps.pressed.emit()
	editor.fields["map.id"].text="extra_field";editor.fields["map.name"].text="추가 전장"
	editor.buttons.apply_map.pressed.emit()
	editor.map_grid.get_child(19).pressed.emit()
	check(editor.selected_cell==Vector2i(4,3),"actual map button selects1-based cell")
	editor.fields["map.cell_height"].value=3;editor.fields["map.cell_terrain"].select(2);editor.buttons.apply_cell.pressed.emit()
	var map: Dictionary=editor.project.content.maps[1]
	check(map.cells.size()==1 and int(map.cells[0].height)==3 and int(map.cells[0].terrain)==2,"grid edits terrain and height")
	metadata(editor.fields["spawn.character"],"extra_hero");editor.fields["spawn.side"].select(1);editor.fields["spawn.level"].value=2;editor.buttons.add_spawn.pressed.emit()
	map=editor.project.content.maps[1]
	check(map.placements.size()==1 and map.placements[0].character=="extra_hero"and int(map.placements[0].x)==4 and int(map.placements[0].y)==3,"GUI places a character on selected cell")
	editor.tabs.current_tab=3;editor.buttons.add_stories.pressed.emit()
	editor.fields["story.id"].text="extra_story";editor.buttons.apply_story.pressed.emit()
	editor.buttons.add_node.pressed.emit();editor.fields["node.id"].text="hello";editor.fields["node.text"].text="제가 직접 쓴 대사입니다.";editor.fields["node.next"].text="begin";editor.buttons.apply_node.pressed.emit()
	editor.fields["story.start"].text="hello";editor.buttons.apply_story.pressed.emit()
	check(editor.project.content.stories[1].nodes[1].text=="제가 직접 쓴 대사입니다.","GUI dialogue authoring")
	for node_type in ["set","branch","battle"]:
		editor.buttons.add_node.pressed.emit();editor.fields["node.id"].text="test_"+node_type
		metadata(editor.fields["node.type"],node_type);editor.fields["node.type"].item_selected.emit(editor.fields["node.type"].selected)
		editor.fields["node.variable"].text="flag";editor.fields["node.value"].text="1";editor.fields["node.equals"].text="1"
		editor.fields["node.then"].text="hello";editor.fields["node.else"].text="begin";editor.fields["node.next"].text="begin";editor.fields["node.on_defeat"].text="begin"
		metadata(editor.fields["node.map"],"extra_field");editor.buttons.apply_node.pressed.emit()
		check(editor.project.content.stories[1].nodes[-1].type==node_type,"GUI authors "+node_type+" node")
	var directory:=output.path_join("project")
	var saved: Dictionary=editor.save_project(directory)
	check(saved.ok,"GUI-created project saves")
	check(FileAccess.file_exists(directory.path_join("mod.json")) and FileAccess.file_exists(directory.path_join("content.json")),"both project files exist")
	check(editor.validate_project().ok,"GUI-created project validates")
	var requests: Array=[]
	editor.play_requested.connect(func(path):requests.append(path))
	editor.buttons.test_play.pressed.emit()
	check(requests.is_empty()and editor.status.text.contains("정품"),"test play without base data gives preparation guidance")
	var exported: Dictionary=editor.export_project(output.path_join("editor_test.zip"))
	check(exported.ok,"GUI-created project exports ZIP")
	var zip:=ZIPReader.new();check(zip.open(output.path_join("editor_test.zip"))==OK,"ZIP opens")
	var files:=zip.get_files();var actual_files: Array=[]
	for path in files:
		if not path.ends_with("/"):actual_files.append(path)
	check(actual_files.size()==2 and files.has("editor_test/mod.json") and files.has("editor_test/content.json"),"ZIP contains descriptors only")
	var packed=JSON.parse_string(zip.read_file("editor_test/content.json").get_string_from_utf8());zip.close()
	check(packed.characters[2].name=="추가 영웅"and packed.maps[1].placements[0].character=="extra_hero","exported definitions survive")
	var reopened=type.new();reopened.theme=theme;root.add_child(reopened);reopened.configure(null)
	check(reopened.load_project(directory).ok,"project opens again")
	check(reopened.project.content.skills.size()==2 and reopened.project.content.characters.size()==3,"reopened counts preserved")
	reopened.fields["project.name"].text="다시 고친 확장팩";check(reopened.save_project(directory).ok,"reopened GUI saves edits")
	var reread=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("mod.json")))
	check(reread.name=="다시 고친 확장팩","edited project name persisted")
	reopened.tabs.current_tab=2;select(reopened,"maps",1);reopened.buttons.remove_maps.pressed.emit()
	check(not reopened.validate_project().ok,"deleted map leaves a detected story reference error")
	reopened.load_project(directory)
	var fake_original:=output.path_join("original_fixture");DirAccess.make_dir_recursive_absolute(fake_original)
	var file:=FileAccess.open(fake_original.path_join("FTO_O.EXE"),FileAccess.WRITE);file.store_string("self-authored protection fixture");file.close()
	check(not reopened.save_project(fake_original).ok,"cannot save into original game root")
	check(not reopened.save_project(fake_original.path_join("DATA")).ok,"cannot save into original game child")
	check(not reopened.export_project(fake_original.path_join("bad.zip")).ok,"cannot export into original game folder")
	var protected_data:=ProtectedData.new();protected_data.source_root=fake_original;protected_data.repo_root=output.path_join("cache_fixture")
	DirAccess.make_dir_recursive_absolute(protected_data.repo_root)
	reopened.project.source_data=protected_data
	check(not reopened.save_project(protected_data.repo_root.path_join("project")).ok,"cannot save inside prepared cache")
	reopened.project.source_data=null
	var pristine: Dictionary=reopened.project.content.duplicate(true)
	reopened.project.content.characters[0].stats["hp.initial"]=32768
	check(not reopened.project.validate_project().ok,"s16 stat overflow rejected")
	reopened.project.content=pristine.duplicate(true)
	reopened.project.content.skills[0].visual_skill=9999
	check(not reopened.project.validate_project().ok,"unknown original visual ID rejected")
	reopened.project.content=pristine.duplicate(true)
	reopened.project.content["raw_record_hex"]="synthetic forbidden field"
	check(not reopened.project.validate_project().ok,"unsupported raw payload fields rejected")
	reopened.project.content=pristine.duplicate(true)
	reopened.project.content.characters[0].level=100
	check(not reopened.project.validate_project().ok,"external character level100 rejected")
	reopened.project.content=pristine.duplicate(true)
	reopened.project.content.maps[0].placements[0].level=100
	check(not reopened.project.validate_project().ok,"external placement level100 rejected")
	reopened.project.content=pristine.duplicate(true)
	check(not reopened.project.export_project(output.path_join("wrong_extension.bin")).ok,"ZIP extension required")
	editor.configure(protected_data);editor.buttons.test_play.pressed.emit()
	check(requests.size()==1 and str(requests[0])==directory,"valid save-and-test emits selected project directory")
	reopened.hide()
	editor.tabs.current_tab=2;select(editor,"maps",1)
	await process_frame
	if capture:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("editor-map.png"))
		editor.tabs.current_tab=3
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("editor-story.png"))
		editor.tabs.current_tab=0;select(editor,"characters",2)
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("editor-character.png"))
		editor.tabs.current_tab=1;select(editor,"skills",1)
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("editor-skill.png"))
	reopened.queue_free();editor.queue_free();await process_frame
	var before_size:=root.size;var before_scale:=root.content_scale_size
	var setup:=SetupWithoutStartup.new();setup.theme=theme;root.add_child(setup);setup._build_ui()
	setup._open_editor();await process_frame
	check(is_instance_valid(setup._editor)and setup._editor.data==null,"setup opens authoring without original data")
	check(root.size==Vector2i(1100,800),"setup enlarges the authoring window")
	setup._editor.buttons.close.pressed.emit();await process_frame;await process_frame
	check(setup._editor==null and setup.visible and root.size==before_size and root.content_scale_size==before_scale,"editor close restores setup and window geometry")
	setup.queue_free();await process_frame
	var result: Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"source_game_data_used":false,"host_windows_opened":false,"actual_control_actions":true}
	var report:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);report.store_string(JSON.stringify(result,"\t"));report.close()
	print("FT2_EDITOR ",JSON.stringify(result));quit(0 if failures.is_empty()else 1)
