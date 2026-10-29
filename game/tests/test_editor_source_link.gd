extends SceneTree
## Local original-backed source-link roundtrip, without native file dialogs.
class SetupWithoutStartup extends "res://scripts/content/ft2_content_setup.gd":
	var intercepted_browse:=0
	func _ready()->void:pass
	func _browse(_field:LineEdit,_select_file:bool=false,_filters:PackedStringArray=[])->void:
		intercepted_browse+=1

var output:=""
var cache:=""
var source:=""
var connection:=""
var checks:=0
var failures:Array[String]=[]

func _initialize()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source-link-output="):output=argument.trim_prefix("--source-link-output=")
		elif argument.begins_with("--source-link-cache="):cache=argument.trim_prefix("--source-link-cache=")
		elif argument.begins_with("--source-link-source="):source=argument.trim_prefix("--source-link-source=")
		elif argument.begins_with("--source-link-connection="):connection=argument.trim_prefix("--source-link-connection=")
	if output.is_empty()or cache.is_empty()or source.is_empty()or connection.is_empty():quit(2);return
	for writable in [output,connection]:
		var path:String=ProjectSettings.globalize_path(writable).replace("\\","/").simplify_path().to_lower()
		for protected in [source,cache]:
			var base:String=ProjectSettings.globalize_path(protected).replace("\\","/").simplify_path().to_lower().trim_suffix("/")
			if path==base or path.begins_with(base+"/"):quit(2);return
	call_deferred("run")

func check(condition:bool,label:String)->void:
	checks+=1
	if not condition:failures.append(label)

func core_hashes()->Dictionary:
	var result:Dictionary={}
	for table in ["item","magic","race"]:
		for path in ["fixtures/"+table+".dat","data/port_ready/tables/"+table+".dat.json"]:
			result[path]=FileAccess.get_sha256(cache.path_join(path))
	return result

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
