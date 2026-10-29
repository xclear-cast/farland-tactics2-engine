extends SceneTree
## Screenshots of the actual setup controls and directory chooser; no game data.
var output := ""
var fixture := ""
var setup

func _initialize() -> void: call_deferred("run")

func rectangle(control: Control) -> Array:
	var r := control.get_global_rect()
	return [roundi(r.position.x),roundi(r.position.y),roundi(r.size.x),roundi(r.size.y)]

func capture(name: String) -> void:
	await process_frame;await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-output="): output=argument.trim_prefix("--capture-output=")
		elif argument.begins_with("--fixture-folder="): fixture=argument.trim_prefix("--fixture-folder=")
	if output.is_empty() or fixture.is_empty(): quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(960,700);root.content_scale_size=Vector2i(960,700)
	root.gui_embed_subwindows=true
	setup=load("res://scenes/content_setup.tscn").instantiate();root.add_child(setup)
	await process_frame;await process_frame
	var select: Button=setup.source_field.get_parent().get_child(1)
	var boxes={"select_folder":rectangle(select),"prepare":rectangle(setup.import_button),"connect":rectangle(setup.connect_button)}
	await capture("04-app-select-folder")
	setup.source_field.text=fixture
	select.pressed.emit()
	var dialog: FileDialog
	for child in setup.get_children():
		if child is FileDialog: dialog=child
	if dialog==null: quit(3);return
	dialog.current_dir=fixture
	dialog.invalidate()
	dialog.popup_centered(Vector2i(850,540))
	await create_timer(0.4).timeout
	var r=dialog.get_ok_button().get_global_rect();var offset=dialog.position
	boxes["choose_directory"]=[roundi(r.position.x)+offset.x,roundi(r.position.y)+offset.y,roundi(r.size.x),roundi(r.size.y)]
	await capture("05-app-folder-dialog")
	dialog.dir_selected.emit(fixture)
	await capture("06-app-preparation-buttons")
	var file=FileAccess.open(output.path_join("setup_capture.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"capture_kind":"actual-window-screenshots","window":[960,700],"boxes":boxes,
		"original_game_data_used":false,"fixture_directory_only":true,"conversion_not_started":true},"\t"));file.close()
	setup.queue_free();await process_frame;quit(0)
