extends SceneTree
## Local original-backed source-link roundtrip, without native file dialogs.
class SetupWithoutStartup extends "res://scripts/content/ft2_content_setup.gd":
	var intercepted_browse:=0
	func _ready()->void:pass
	func _browse(_field:LineEdit,_select_file:bool=false,_filters:PackedStringArray=[])->void:
		intercepted_browse+=1
class SetupWithEmbeddedDialogs extends "res://scripts/content/ft2_content_setup.gd":
	func _ready()->void:pass

var output:=""
var cache:=""
var source:=""
var connection:=""
var checks:=0
var failures:Array[String]=[]
var embedded_esc:=false

func _initialize()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source-link-output="):output=argument.trim_prefix("--source-link-output=")
		elif argument.begins_with("--source-link-cache="):cache=argument.trim_prefix("--source-link-cache=")
		elif argument.begins_with("--source-link-source="):source=argument.trim_prefix("--source-link-source=")
		elif argument.begins_with("--source-link-connection="):connection=argument.trim_prefix("--source-link-connection=")
		elif argument=="--source-link-embedded-esc":embedded_esc=true
	if output.is_empty()or connection.is_empty()or (not embedded_esc and (cache.is_empty()or source.is_empty())):quit(2);return
	for writable in [output,connection]:
		var path:String=ProjectSettings.globalize_path(writable).replace("\\","/").simplify_path().to_lower()
		for protected in [source,cache]:
			if protected.is_empty():continue
			var base:String=ProjectSettings.globalize_path(protected).replace("\\","/").simplify_path().to_lower().trim_suffix("/")
			if path==base or path.begins_with(base+"/"):quit(2);return
	call_deferred("run_embedded_esc"if embedded_esc else"run")

func check(condition:bool,label:String)->void:
	checks+=1
	if not condition:failures.append(label)

func core_hashes()->Dictionary:
	var result:Dictionary={}
	for table in ["item","magic","race"]:
		for path in ["fixtures/"+table+".dat","data/port_ready/tables/"+table+".dat.json"]:
			result[path]=FileAccess.get_sha256(cache.path_join(path))
	return result

func root_escape()->void:
	var event:=InputEventKey.new();event.keycode=KEY_ESCAPE;event.physical_keycode=KEY_ESCAPE;event.pressed=true
	root.push_input(event)
	event=InputEventKey.new();event.keycode=KEY_ESCAPE;event.physical_keycode=KEY_ESCAPE;event.pressed=false
	root.push_input(event)

func run_embedded_esc()->void:
	if DisplayServer.get_name()=="headless":
		printerr("Embedded ESC regression requires an owned graphical display");quit(2);return
	Engine.max_fps=30;root.gui_embed_subwindows=true
	DirAccess.make_dir_recursive_absolute(output)
	var authored_source:=output.path_join("self-authored-folder")
	DirAccess.make_dir_recursive_absolute(authored_source)
	var setup:=SetupWithEmbeddedDialogs.new()
	setup.config_path=output.path_join("unused-private-connection.json")
	setup.configuration={"source_root":authored_source,"content_root":"","mods":[]}
	# Production _browse creates the real FileDialog. Force its test surface to
	# remain inside this owned Godot/Xvfb window, never a system folder picker.
	setup.child_entered_tree.connect(func(node):
		if node is FileDialog:node.use_native_dialog=false)
	root.add_child(setup);current_scene=setup;setup._build_ui();setup._open_editor()
	await process_frame;await process_frame
	var editor=setup._editor
	check(is_instance_valid(editor)and editor.data==null,"self-authored editor opens without original data")
	if not is_instance_valid(editor):quit(1);return
	check(editor.save_project(output.path_join("project")).ok,"self-authored test project saves privately")
	var previous_hp:=int(editor.project.content.characters[0].stats["hp.initial"])
	editor.fields["character.hp.initial.enabled"].button_pressed=true
	editor.fields["character.hp.initial"].value=previous_hp+11;editor.buttons.apply_character.pressed.emit()
	var instance:int=editor.get_instance_id()
	var expected:Dictionary=editor.project.content.duplicate(true)
	var cursor:int=editor._history_cursor
	editor.bridge=load("res://scripts/editor/ft2_editor_bridge.gd").new();editor.bridge.connection_path=connection
	check(editor.bridge.start(editor).ok,"embedded ESC uses only a private local MCP connection")
	var resumed:=true
	for cycle in 2:
		var prior_profile=JSON.parse_string(FileAccess.get_file_as_string(connection))
		editor.buttons.connect_original.pressed.emit()
		await process_frame;await process_frame
		var dialogs:=setup.find_children("*","FileDialog",true,false)
		check(dialogs.size()==1,"production browse creates one real embedded file dialog")
		if dialogs.size()!=1:break
		var dialog:FileDialog=dialogs[0]
		check(dialog.visible and not dialog.use_native_dialog and dialog.is_embedded(),"folder chooser remains embedded in owned display")
		check(setup.visible and setup.size.x>100 and setup.size.y>100,"connection setup fills a nonzero visible area")
		var background:Control=setup.get_child(0)
		check(background.visible and background.size.x>100 and background.size.y>100,"connection background fills its setup control")
		check(not editor.visible and setup._editor_linking_source,"editor hides while connection dialog is active")
		check(not editor.bridge.status().running,"MCP pauses before source selection")
		dialog.grab_focus()
		root_escape()
		await process_frame;await process_frame
		check(not is_instance_valid(dialog)or not dialog.visible,"root ESC input cancels actual file chooser")
		check(is_instance_valid(setup._editor)and setup._editor.get_instance_id()==instance,"ESC keeps the same editor instance")
		check(editor.visible and not setup.visible and not setup._editor_linking_source,"ESC returns visibly to editor instead of black setup")
		check(editor.project.content==expected and editor._dirty,"ESC preserves authored content and dirty state")
		check(editor._history_cursor==cursor and int(editor.fields["character.hp.initial"].value)==previous_hp+11,"ESC preserves HP and undo cursor")
		var active:bool=editor.bridge.status().running;resumed=resumed and active
		check(active,"ESC resumes the previously active private MCP session")
		if active:
			var after_profile=JSON.parse_string(FileAccess.get_file_as_string(connection))
			check(prior_profile is Dictionary and after_profile is Dictionary and prior_profile.token!=after_profile.token,"resumed MCP rotates its private authentication token")
		if not editor.visible:break
	# Selecting a folder closes the picker but leaves the connection form open.
	# Escape must also return from that second state, without requiring a popup.
	editor.buttons.connect_original.pressed.emit();await process_frame;await process_frame
	var remaining:=setup.find_children("*","FileDialog",true,false)
	check(remaining.size()==1,"connection form ESC scenario opens production folder picker")
	if remaining.size()==1:
		remaining[0].dir_selected.emit(authored_source)
		await process_frame;await process_frame
		check(setup.find_children("*","FileDialog",true,false).is_empty(),"folder selection closes actual picker without returning yet")
		check(setup.visible and not editor.visible and setup._editor_linking_source,"connection form remains visible after folder selection")
		root_escape();await process_frame;await process_frame
		check(editor.visible and not setup.visible and not setup._editor_linking_source,"root ESC returns from connection form without a popup")
		check(setup._editor.get_instance_id()==instance and editor.project.content==expected and editor._dirty,"connection form ESC preserves editor and unsaved content")
		check(editor._history_cursor==cursor and int(editor.fields["character.hp.initial"].value)==previous_hp+11,"connection form ESC preserves HP and undo")
		resumed=resumed and bool(editor.bridge.status().running)
		check(editor.bridge.status().running,"connection form ESC resumes existing MCP workflow")
	editor.buttons.undo.pressed.emit()
	check(int(editor.project.content.characters[0].stats["hp.initial"])==previous_hp,"undo still works after repeated real ESC cancellation")
	editor.buttons.redo.pressed.emit()
	check(int(editor.project.content.characters[0].stats["hp.initial"])==previous_hp+11,"redo still works after repeated real ESC cancellation")
	setup._close_editor();await process_frame;setup.queue_free();await process_frame
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"synthetic_only":true,"real_embedded_file_dialog":true,"root_escape_input":true,"mcp_resumed":resumed,"source_game_data_uploaded":false,"host_ui_used":false}
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("FT2_EDITOR_EMBEDDED_ESC ",JSON.stringify(report));quit(0 if failures.is_empty()else 1)

func run()->void:
	Engine.max_fps=30
	DirAccess.make_dir_recursive_absolute(output)
	var before:=core_hashes()
	var setup:=SetupWithoutStartup.new()
	setup.config_path=output.path_join("setup-connection.json")
	setup.configuration={"source_root":source,"content_root":cache,"mods":[]}
	root.add_child(setup);current_scene=setup;setup._build_ui();setup._open_editor()
	await process_frame
	var editor=setup._editor
	check(is_instance_valid(editor),"setup opens the actual editor")
	if not is_instance_valid(editor):quit(1);return
	check(editor.data!=null and editor.project.baseline_status().available,"actual pristine baseline initially connects")
	check(editor.buttons.connect_original.text=="원작 데이터 연결","source-link button has discoverable label")
	check(editor.buttons.open_original_folder.text=="원작 폴더 열기","original-folder button is present without opening host file manager")
	var project_folder:=output.path_join("project")
	check(editor.save_project(project_folder).ok,"private initial project saves")
	var old_hp:int=int(editor.project.content.characters[0].stats["hp.initial"])
	var new_hp:=old_hp+17
	editor.fields["character.hp.initial.enabled"].button_pressed=true
	editor.fields["character.hp.initial"].value=new_hp;editor.buttons.apply_character.pressed.emit()
	check(editor._dirty,"actual character edit marks project dirty")
	var instance:int=editor.get_instance_id()
	var expected:Dictionary=editor.project.content.duplicate(true)
	var cursor:int=editor._history_cursor
	var history_size:int=editor._history.size()
	check(cursor>0,"edit creates an undo record")
	setup._begin_editor_source_connection(false)
	check(setup._editor_linking_source and setup.visible and not editor.visible,"source-link setup hides and preserves editor")
	check(setup.connect_button.text=="연결하고 에디터로 돌아가기","connection action explains return destination")
	setup.create_button.pressed.emit();await process_frame
	check(not setup._editor_linking_source and editor.visible and not setup.visible,"cancel returns to editor")
	check(setup._editor.get_instance_id()==instance and editor.project.content==expected,"cancel preserves same editor and project")
	check(editor._dirty and editor._history_cursor==cursor,"cancel preserves dirty state and undo cursor")
	editor.bridge=load("res://scripts/editor/ft2_editor_bridge.gd").new()
	editor.bridge.connection_path=connection
	check(editor.bridge.start(editor).ok,"private MCP connection starts")
	editor.buttons.connect_original.pressed.emit();await process_frame
	check(not editor.bridge.status().running and not FileAccess.file_exists(connection),"source-change button stops private MCP before connection setup")
	check(setup.intercepted_browse==1,"source button requests browsing without opening a host dialog")
	check(root.find_children("*","FileDialog",true,false).is_empty(),"test never creates a file dialog")
	setup.create_button.pressed.emit()
	setup._begin_editor_source_connection(false)
	setup.source_field.text=source;setup.cache_field.text=cache
	setup._connect_game();await process_frame
	check(not setup._editor_linking_source and not setup.visible and editor.visible,"actual original activation returns to editor")
	check(setup._editor.get_instance_id()==instance,"reconnection reuses the same editor instance")
	check(editor.project.content==expected,"reconnection preserves all authored content")
	check(editor._dirty,"reconnection retains unsaved-change marker")
	check(editor._history_cursor==cursor and editor._history.size()==history_size,"reconnection preserves complete undo history")
	check(int(editor.fields["character.hp.initial"].value)==new_hp,"reconnection preserves edited HP in inspector")
	check(editor.data!=null and editor.project.baseline_status().available,"reconnection supplies current pristine original baseline")
	check(FileAccess.file_exists(setup.config_path),"setup saves connection only to the explicit private file")
	editor.buttons.undo.pressed.emit()
	check(int(editor.project.content.characters[0].stats["hp.initial"])==old_hp,"undo still restores pre-edit HP after reconnect")
	editor.buttons.redo.pressed.emit()
	check(int(editor.project.content.characters[0].stats["hp.initial"])==new_hp,"redo still restores authored HP after reconnect")
	check(editor.save_project(project_folder).ok,"reconnected project saves normally")
	var saved=JSON.parse_string(FileAccess.get_file_as_string(project_folder.path_join("content.json")))
	check(saved is Dictionary and int(saved.characters[0].stats["hp.initial"])==new_hp,"saved descriptor retains edited HP")
	setup._close_editor();await process_frame;setup.queue_free();await process_frame
	check(core_hashes()==before,"all six pristine table binary/JSON hashes stay unchanged")
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"source_game_data_uploaded":false,"host_ui_used":false,"same_editor_instance":true,"core_table_hashes_unchanged":core_hashes()==before}
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("FT2_EDITOR_SOURCE_LINK ",JSON.stringify(report));quit(0 if failures.is_empty()else 1)
