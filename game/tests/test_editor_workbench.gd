extends SceneTree
## Local original-backed GUI regression. Explicit private paths; captures opt-in only.
var checks:=0
var failures:Array[String]=[]
var output:=""
var cache:=""
var source:=""
var capture:=false
var skip_fingerprint:=false
var observations:Dictionary={}
var imported:Dictionary={"characters":[],"skills":[]}

func _initialize()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--workbench-output="):output=argument.trim_prefix("--workbench-output=")
		elif argument.begins_with("--workbench-cache="):cache=argument.trim_prefix("--workbench-cache=")
		elif argument.begins_with("--workbench-source="):source=argument.trim_prefix("--workbench-source=")
		elif argument=="--workbench-capture":capture=true
		elif argument=="--skip-fingerprint":skip_fingerprint=true
	if output.is_empty()or cache.is_empty()or source.is_empty():
		printerr("Explicit private workbench output/cache/source paths required");quit(2);return
	for protected in [cache,source]:
		if output.simplify_path().begins_with(protected.simplify_path().trim_suffix("/")+"/")or output.simplify_path()==protected.simplify_path():
			printerr("Workbench output must be outside source/cache");quit(2);return
	call_deferred("run")

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label)

func fingerprint(directory:String,prefix:String="",result:Dictionary={})->Dictionary:
	var tree:=DirAccess.open(directory.path_join(prefix))
	if tree==null:failures.append("Cannot fingerprint protected directory");return result
	for name in tree.get_files():
		var relative:=prefix.path_join(name)
		result[relative]=FileAccess.get_sha256(directory.path_join(relative))
	for name in tree.get_directories():
		if tree.is_link(name):failures.append("Protected directory has an unverified symbolic link");continue
		fingerprint(directory,prefix.path_join(name),result)
	return result

func select(editor,kind:String,index:int)->void:
	editor.lists[kind].select(index);editor.lists[kind].item_selected.emit(index)

func import_original(editor,kind:String,id:int)->int:
	var search:LineEdit=editor.fields["original_search_"+kind]
	search.text=str(id);search.text_changed.emit(search.text)
	await process_frame
	var list:ItemList=editor.lists["original_"+kind]
	var found:=-1
	for index in list.item_count:
		if int(list.get_item_metadata(index))==id:found=index;break
	check(found>=0,"original list finds "+kind+" by ID")
	if found<0:return -1
	list.select(found);list.item_selected.emit(found)
	editor.buttons["import_original_"+kind].pressed.emit()
	await process_frame
	return int(editor.selected[kind])

func character_roundtrip(editor,id:int,golem:bool)->void:
	print("FT2_WORKBENCH_PHASE character-controls")
	editor.tabs.current_tab=0
	var index:int=await import_original(editor,"characters",id)
	if index<0:return
	var baseline:Dictionary=editor.project.original_character(id)
	check(not baseline.is_empty(),"connected original character has defaults")
	imported.characters.append(str(editor.project.content.characters[index].id))
	var raw:=FileAccess.get_file_as_bytes(cache.path_join("fixtures/race.dat"))
	for stat in editor.project.STAT_NAMES:
		for part in ["initial","growth"]:
			var key:String=stat+"."+part
			check(int(baseline.stats[key])==raw.decode_s16(id*int(FT2Content.STRIDES.race)+int(FT2Content.TABLE_FIELDS.race[key][0])),"baseline independently matches pristine race field "+key)
			check(int(editor.fields["character."+key].value)==int(baseline.stats[key]),"original character form displays "+key)
	var old_id:String=str(editor.project.content.characters[index].id)
	editor.fields["character.hp.initial.enabled"].button_pressed=true
	editor.fields["character.hp.initial"].value=int(baseline.stats["hp.initial"])+7
	editor.fields["character.atk.growth.enabled"].button_pressed=true
	editor.fields["character.atk.growth"].value=int(baseline.stats["atk.growth"])+2
	editor.buttons.apply_character.pressed.emit()
	check(int(editor.project.content.characters[index].stats.get("hp.initial",-1))==int(baseline.stats["hp.initial"])+7,"character GUI applies custom HP")
	check(editor.project.changed_fields("characters",index).has("stats.hp.initial"),"changed marker tracks original comparison")
	editor.buttons["reset_character_hp.initial"].pressed.emit()
	check(int(editor.fields["character.hp.initial"].value)==int(baseline.stats["hp.initial"]),"field reset restores actual original HP")
	check(not editor.project.changed_fields("characters",index).has("stats.hp.initial"),"field reset clears only its changed marker")
	check(editor.project.changed_fields("characters",index).has("stats.atk.growth"),"field reset preserves another custom stat")
	editor.fields["character.name"].text="Workbench own label"
	editor.buttons.apply_character.pressed.emit()
	editor.buttons.reset_character.pressed.emit()
	check(str(editor.project.content.characters[index].id)==old_id,"full reset retains expansion reference ID")
	check(editor.project.changed_fields("characters",index).is_empty(),"full reset restores original editable character values")
	check(str(editor.fields["character.name"].text)==str(baseline.name),"full reset restores original name")
	if golem:observations.golem_checked=true
	observations.characters_checked=int(observations.get("characters_checked",0))+1

func skill_roundtrip(editor,id:int)->void:
	print("FT2_WORKBENCH_PHASE skill-controls")
	editor.tabs.current_tab=1
	var index:int=await import_original(editor,"skills",id)
	if index<0:return
	var baseline:Dictionary=editor.project.original_skill(id)
	imported.skills.append(str(editor.project.content.skills[index].id))
	var raw:=FileAccess.get_file_as_bytes(cache.path_join("fixtures/magic.dat"))
	for pair in [["mp","mp"],["range_min","target_distance_min_raw"],["range_max","target_distance_max_raw"]]:
		check(int(baseline[pair[0]])==raw.decode_s16(id*int(FT2Content.STRIDES.magic)+int(FT2Content.TABLE_FIELDS.magic[pair[1]][0])),"baseline independently matches pristine skill "+str(pair[0]))
	for key in ["mp","power","range_min","range_max"]:
		check(int(editor.fields["skill."+key].value)==int(baseline[key]),"original skill form displays "+key)
	editor.fields["skill.mp"].value=int(baseline.mp)+1
	editor.fields["skill.power"].value=int(baseline.power)+3
	editor.buttons.apply_skill.pressed.emit()
	check(editor.project.changed_fields("skills",index).has("mp"),"skill GUI stores MP difference")
	editor.buttons.reset_skill.pressed.emit()
	check(editor.project.changed_fields("skills",index).is_empty(),"skill full reset restores actual original values")
	for key in ["mp","power","range_min","range_max"]:
		check(int(editor.fields["skill."+key].value)==int(baseline[key]),"reset skill form displays "+key)
	observations.skills_checked=int(observations.get("skills_checked",0))+1

func click_canvas(control:Control,point:Vector2)->void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.pressed=true
	control._gui_input(event)
	event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.pressed=false
	control._gui_input(event)

func canvas_roundtrip(editor)->void:
	editor.tabs.current_tab=2
	await process_frame;await process_frame
	editor.buttons.map_fit.pressed.emit()
	var parts:=0
	for row in editor.map_view._cells:parts+=row.get("parts",[]).size()
	observations.preview_tile_parts=parts
	check(parts>0,"connected map preview contains original tile references")
	var cell:=Vector2i(4,4)
	var center:Vector2=editor.map_view.cell_to_screen(cell)
	check(editor.map_view.screen_to_cell(center)==cell,"map screen coordinates resolve actual isometric cell")
	click_canvas(editor.map_view,center)
	check(editor.selected_cell==cell,"map canvas click selects editor cell")
	var before:Dictionary=editor.project.content.maps[0].duplicate(true)
	editor.fields["map.cell_height"].value=2
	editor.buttons.map_tool_height.pressed.emit()
	click_canvas(editor.map_view,editor.map_view.cell_to_screen(cell))
	var painted:=false
	for row in editor.project.content.maps[0].cells:
		if int(row.x)==cell.x and int(row.y)==cell.y and int(row.height)==2:painted=true
	check(painted,"height brush click edits selected actual map cell")
	editor.buttons.undo.pressed.emit()
	check(editor.project.content.maps[0]==before,"undo restores author map changes")
	editor.buttons.redo.pressed.emit()
	check(editor.project.content.maps[0]!=before,"redo reapplies author map changes")
	var zoom:float=editor.map_view.zoom
	editor.buttons.map_zoom_in.pressed.emit()
	check(float(editor.map_view.zoom)>zoom,"map zoom tool changes visible canvas scale")
	editor.buttons.map_tool_select.pressed.emit()
	editor.tabs.current_tab=3
	await process_frame;await process_frame
	var index:=1
	click_canvas(editor.story_view,editor.story_view.node_screen_center(index))
	check(int(editor.selected.nodes)==index,"story card click selects corresponding node")
	check(str(editor.fields["node.id"].text)==str(editor.project.content.stories[0].nodes[index].id),"story card selection populates matching inspector")
	observations.actual_map_canvas_checked=true;observations.actual_story_canvas_checked=true

func run()->void:
	Engine.max_fps=30
	DirAccess.make_dir_recursive_absolute(output)
	var before_source:Dictionary={}
	var before_cache:Dictionary={}
	if not skip_fingerprint:
		print("FT2_WORKBENCH_PHASE fingerprint-original-before")
		before_source=fingerprint(source,"",{})
		print("FT2_WORKBENCH_PHASE fingerprint-cache-before")
		before_cache=fingerprint(cache,"",{})
		check(not before_source.is_empty()and not before_cache.is_empty(),"protected original/cache fingerprints cover real files")
	print("FT2_WORKBENCH_PHASE original-backed-controls")
	var activation:=FT2Content.activate(cache,source,[])
	print("FT2_WORKBENCH_PHASE original-activation-complete")
	check(bool(activation.get("ok",false)),"matching local original/cache activates")
	if activation.get("ok",false):
		var data:=FT2Data.new()
		var editor=load("res://scripts/editor/ft2_expansion_editor.gd").new()
		root.size=Vector2i(1280,840);root.content_scale_size=Vector2i(1280,840)
		root.add_child(editor);editor.configure(data);await process_frame
		print("FT2_WORKBENCH_PHASE editor-configured")
		await process_frame
		check(editor.buttons.new.global_position.y<160,"header preserves working space at 1280x840")
		check(editor.fields["character.hp.initial"].size.y<60,"numeric stat grid avoids vertical text compression")
		editor.buttons.new.pressed.emit()
		editor.fields["project.id"].text="workbench_private_test"
		editor.fields["project.id"].text_changed.emit("workbench_private_test")
		editor.fields["project.name"].text="원작 기반 작업대 검증"
		editor.fields["project.name"].text_changed.emit("원작 기반 작업대 검증")
		var golem:=-1
		var others:Array[int]=[]
		for row in editor.project.original_catalog("characters"):
			if golem<0 and (str(row.name).contains("고렘")or str(row.name).contains("골렘")):golem=int(row.id)
			elif others.size()<2 and not str(row.name).contains("고렘")and not str(row.name).contains("골렘"):others.append(int(row.id))
		check(golem>=0,"local original contains a Golem reference")
		editor.fields.original_search_characters.text="골렘"
		editor.fields.original_search_characters.text_changed.emit("골렘")
		await process_frame
		var alias_found:=false
		for index in editor.lists.original_characters.item_count:
			if int(editor.lists.original_characters.get_item_metadata(index))==golem:alias_found=true
		check(alias_found,"Golem spelling alias locates the original entry")
		if golem>=0:await character_roundtrip(editor,golem,true)
		for id in others:await character_roundtrip(editor,id,false)
		var catalog:Array=editor.project.original_catalog("skills")
		for index in mini(2,catalog.size()):await skill_roundtrip(editor,int(catalog[index].id))
		check(int(observations.get("characters_checked",0))==3,"three original character types exercised")
		check(int(observations.get("skills_checked",0))==2,"two original skill types exercised")
		await canvas_roundtrip(editor)
		var folder:=output.path_join("project")
		check(bool(editor.save_project(folder).get("ok",false)),"reset original references save through GUI API")
		check(str(editor.project.descriptor.id)=="workbench_private_test","project inspector text survives other editing actions")
		var expected:Dictionary=editor.project.content.duplicate(true)
		editor.buttons.new.pressed.emit()
		check(bool(editor.load_project(folder).get("ok",false)),"saved project reopens")
		check(str(editor.project.descriptor.id)=="workbench_private_test","project ID survives save and reopen")
		# JSON has one number type; parsing normalizes integer variants to floats.
		check(editor.project.content==JSON.parse_string(JSON.stringify(expected)),"reset values and sparse references survive reopen")
		for kind in ["characters","skills"]:
			for index in editor.project.content[kind].size():
				var row:Dictionary=editor.project.content[kind][index]
				if imported[kind].has(str(row.id)):
					select(editor,kind,index)
					check(editor.project.changed_fields(kind,index).is_empty(),"reopened original record retains default comparison")
		check(bool(editor.export_project(output.path_join("workbench.zip")).get("ok",false)),"workbench export validates")
		if capture:
			for tab in [0,1,2,3]:
				editor.tabs.current_tab=tab
				await process_frame;await process_frame;await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join("private-workbench-"+str(tab)+".png"))
		editor.queue_free();await process_frame
	var after_source:Dictionary={}
	var after_cache:Dictionary={}
	if not skip_fingerprint:
		print("FT2_WORKBENCH_PHASE fingerprint-original-after")
		after_source=fingerprint(source,"",{})
		print("FT2_WORKBENCH_PHASE fingerprint-cache-after")
		after_cache=fingerprint(cache,"",{})
		check(before_source==after_source,"every original file is byte unchanged")
		check(before_cache==after_cache,"every cache file is byte unchanged")
	observations.source_files_checked=before_source.size();observations.cache_files_checked=before_cache.size()
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"observations":observations,"game_data_uploaded":false,"host_ui_used":false,"external_full_fingerprint_required":skip_fingerprint,"source_unchanged":null if skip_fingerprint else before_source==after_source,"cache_unchanged":null if skip_fingerprint else before_cache==after_cache}
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("FT2_EDITOR_WORKBENCH ",JSON.stringify(report));quit(0 if failures.is_empty()else 1)
