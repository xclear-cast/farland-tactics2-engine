extends SceneTree
## Local-only host for a real stdio client and original-backed preview process.
var output:=""
var cache:=""
var source:=""
var connection:=""
var editor
var started:=0

func _initialize()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--preview-output="):output=argument.trim_prefix("--preview-output=")
		elif argument.begins_with("--preview-cache="):cache=argument.trim_prefix("--preview-cache=")
		elif argument.begins_with("--preview-source="):source=argument.trim_prefix("--preview-source=")
		elif argument.begins_with("--preview-connection="):connection=argument.trim_prefix("--preview-connection=")
	if output.is_empty()or cache.is_empty()or source.is_empty()or connection.is_empty():
		printerr("Explicit private preview output/cache/source/connection paths required");quit(2);return
	for writable in [output,connection]:
		var path:String=ProjectSettings.globalize_path(writable).replace("\\","/").simplify_path().to_lower()
		for protected in [source,cache]:
			var base:String=ProjectSettings.globalize_path(protected).replace("\\","/").simplify_path().to_lower().trim_suffix("/")
			if path==base or path.begins_with(base+"/"):
				printerr("Preview test output and connection must stay outside original/cache");quit(2);return
	call_deferred("run")

func write_json(path:String,value)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(value,"\t"));file.close()

func fail(label:String)->void:
	write_json(output.path_join("host-result.json"),{"passed":false,"error":label,"game_data_uploaded":false})
	if editor!=null:editor.stop_preview()
	quit(1)

func run()->void:
	DirAccess.make_dir_recursive_absolute(output)
	DirAccess.remove_absolute(output.path_join("client-complete.json"))
	var activation:=FT2Content.activate(cache,source,[])
	if not activation.get("ok",false):fail("Original/cache activation failed");return
	editor=load("res://scripts/editor/ft2_expansion_editor.gd").new()
	root.size=Vector2i(1280,840);root.content_scale_size=Vector2i(1280,840)
	root.add_child(editor);editor.configure(FT2Data.new());await process_frame
	editor._preview_log=output.path_join("preview-child.log")
	if not editor.load_project(output.path_join("project")).get("ok",false):fail("Private project could not load");return
	if not editor.external_preview_enabled:fail("Separate preview is not the editor default");return
	var initial_saved:Dictionary=editor.save_project(output.path_join("project"))
	if not initial_saved.get("ok",false):fail("Private project could not save");return
	editor.bridge=load("res://scripts/editor/ft2_editor_bridge.gd").new()
	editor.bridge.connection_path=connection
	var bridge_started:Dictionary=editor.bridge.start(editor)
	if not bridge_started.get("ok",false):fail("Private local bridge could not start");return
	var configurations:Array=[]
	for index in 6:
		editor._mcp_client.select(index);editor._refresh_mcp_config()
		configurations.append({"index":index,"format":"toml"if index==3 else"json","text":editor._mcp_config.text})
	write_json(output.path_join("client-configurations.json"),configurations)
	write_json(output.path_join("ready.json"),{"pid":OS.get_process_id(),"launch":editor._mcp_launch(),"tool_panel":editor._mcp_tools.text,"bridge_running":editor.bridge.status().running,"external_preview_enabled":editor.external_preview_enabled})
	started=Time.get_ticks_msec()
	while not FileAccess.file_exists(output.path_join("client-complete.json")):
		if Time.get_ticks_msec()-started>240000:fail("Real stdio client timed out");return
		await process_frame
	var completion=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("client-complete.json")))
	var state:Dictionary=editor.preview_status()
	var bridge_alive:bool=editor.bridge.status().running
	var saved:Dictionary=editor.save_project(output.path_join("project"))
	var report:={"passed":completion is Dictionary and completion.get("passed",false)and bridge_alive and not state.running and saved.get("ok",false),"bridge_alive_after_stop":bridge_alive,"preview_running_after_stop":state.running,"save_after_stop":saved.get("ok",false),"requests":editor.bridge.status().requests,"game_data_uploaded":false,"host_ui_used":false}
	write_json(output.path_join("host-result.json"),report)
	editor.stop_preview();editor.bridge.stop();editor.queue_free();await process_frame
	print("FT2_EDITOR_PREVIEW_HOST ",JSON.stringify(report));quit(0 if report.passed else 1)
