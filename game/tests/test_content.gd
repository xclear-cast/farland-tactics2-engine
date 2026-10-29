extends SceneTree
var checks := 0
var failures: Array[String] = []
var fixtures := ""
var real_cache := ""
var real_source := ""

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void: call_deferred("run")

func mount(mods: Array = []) -> Dictionary:
	return FT2Content.activate(fixtures.path_join("cache"),fixtures.path_join("source"),mods)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixtures="): fixtures = arg.trim_prefix("--fixtures=")
		elif arg.begins_with("--real-cache="): real_cache = arg.trim_prefix("--real-cache=")
		elif arg.begins_with("--real-source="): real_source = arg.trim_prefix("--real-source=")
	check(mount().ok,"mount synthetic cache")
	var base_profile := FT2Content.active.profile_id
	var store := FT2Data.new()
	check(store.raw_table("item").decode_u16(56+20)==30,"base item binary")
	check(int(store.load_table("item")[1].price)==30,"base item UI")
	check(FT2Content.text("custom/hello.txt")=="base","base resource")
	var low := fixtures.path_join("low")
	var high := fixtures.path_join("high")
	check(mount([low]).ok,"mount low-priority mod")
	var low_profile := FT2Content.active.profile_id
	store = FT2Data.new()
	check(store.raw_table("item").decode_u16(76)==10,"mod item binary")
	check(int(store.load_table("item")[1].price)==10,"mod item UI agrees with rules")
	check(int(store.load_table("magic")[1].mp)==3,"mod magic UI")
	check(store.raw_table("magic").decode_s16(86)==3,"mod magic binary agrees with UI")
	check(str(store.load_table("item")[1].name)=="Custom","mod item name")
	check(FT2Content.text("custom/hello.txt")=="low","whole-file replacement")
	check(FT2Content.text("custom/new.txt")=="new","new resource addition")
	var document = FT2Content.read_json("custom/document.json")
	check(int(document.value)==2 and document.list==[1.0,2.0],"set and append JSON patches")
	check(not document.has("remove_me"),"remove JSON patch")
	check(base_profile != low_profile,"mod saves isolated from base saves")
	check(FT2Content.save_root().contains(low_profile),"save path uses mod profile")
	check(mount([low,high]).ok,"multiple mod layers")
	store = FT2Data.new()
	check(int(store.load_table("item")[1].price)==7,"last mod table edit wins")
	check(FT2Content.text("custom/hello.txt")=="high","last mod file wins")
	check(int(FT2Content.read_json("custom/document.json").value)==9,"file replacement resets lower JSON patch")
	check(FT2Content.active.profile_id != low_profile,"mod order isolates saves")
	check(mount([high,low]).ok,"reverse mod order")
	check(int(FT2Data.new().load_table("item")[1].price)==10,"reverse order respected")
	check(not mount([low,low]).ok,"duplicate mod IDs rejected")
	check(not mount([fixtures.path_join("bad_path")]).ok,"path traversal rejected")
	check(not mount([fixtures.path_join("bad_value")]).ok,"out-of-range number rejected")
	check(not mount([fixtures.path_join("bad_patch")]).ok,"invalid JSON pointer rejected before game")
	check(not mount([fixtures.path_join("bad_field")]).ok,"unknown table field rejected")
	check(not mount([fixtures.path_join("bad_record")]).ok,"out-of-range record rejected")
	check(not FT2Content.activate(fixtures.path_join("cache"),fixtures.path_join("wrong_source")).ok,"different installation rejected")
	check(FT2Content.canonical("../escape.json")=="","relative traversal invalid")
	check(FT2Content.canonical("assets/../escape.json")=="","nested traversal invalid")
	check(FT2Content.canonical("res://assets/indexed/manifest.json")=="assets/indexed/manifest.json","asset logical path")
	check(FT2Content.canonical("res://runtime/data/port_ready/maps/index.json")=="data/port_ready/maps/index.json","runtime logical path")
	check(mount().ok and FT2Content.active.profile_id==base_profile,"disable mods restores original save namespace")
	check(FT2Data.new().raw_table("item").decode_u16(76)==30,"mod edit never mutates cache")
	if real_cache != "": await real_content()
	var report := {"checks":checks,"failures":failures,"passed":failures.is_empty()}
	var output := FileAccess.open(fixtures.path_join("godot_result.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t")); output.close()
	store = null; FT2Content.active = null
	print("FT2_TESTS ",JSON.stringify(report)); quit(0 if failures.is_empty() else 1)

func real_content() -> void:
	check(FT2Content.activate(real_cache,real_source).ok,"real cache bound to selected installation")
	var store := FT2Data.new()
	for table in ["item","magic","race"]:
		var raw := store.raw_table(table)
		check(raw==store.source_bytes("DATA/"+table.to_upper()+".DAT"),"real raw table unchanged: "+table)
		check(store.load_table(table).size()==raw.size()/int(FT2Content.STRIDES[table]),"real table count: "+table)
	var original_save := store.load_save(29)
	check(original_save.units.size()==50,"real save decoded externally")
	var assets := FT2IndexedAssets.new()
	check(not assets.manifest.is_empty(),"external image manifest")
	check(not assets.image("bmp/wall.bmp").is_empty(),"external indexed image bytes")
	var font := FT2IndexedFont.new()
	check(not font.styles.is_empty() and not font.masks.is_empty(),"external fonts")
	var app = load("res://scripts/main.gd").new()
	app._automation={"save":29,"skip_restart_script":true,"settings":{"forced_stage":0,"complete_flag":0}}
	root.add_child(app);app.set_process(false);app.ui.persistence_enabled=false
	check(app.battle.units.size()==50,"actual game starts from external save")
	check(app.errors.is_empty() and app.vm.errors.is_empty(),"actual game and VM startup errors")
	check(app.view.assets.missing.is_empty(),"actual game has no missing image assets")
	check(app.view.font.missing.is_empty(),"actual game has no missing font assets")
	check(app.data.repo_root==real_cache.replace("\\","/").trim_suffix("/"),"actual game uses external cache only")
	# Exercise the coordinated UI set with the standalone converter's data.
	app.ui.open_units(true)
	for tab in range(4):
		app.ui._units_tab = tab
		var operations: Array = app.ui.commands()
		for operation in operations: app.view._draw_overlay(operation)
		check(not operations.is_empty(),"external unit-list tab %d renders" % tab)
	app.ui.close()
	for panel in ["status","equipment","inventory","settings","bgm"]:
		match panel:
			"status": app.ui.open_status(0)
			"equipment": app.ui.open_equipment(0)
			"inventory": app.ui.open_inventory()
			"settings": app.ui.open_settings()
			"bgm": app.ui.open_bgm()
		var operations: Array = app.ui.commands()
		for operation in operations: app.view._draw_overlay(operation)
		check(not operations.is_empty(),"external UI renders: "+panel)
		app.ui.close()
	check(app.view.assets.missing.is_empty(),"updated UI finds external portraits and icons")
	if not app.view.font.missing.is_empty(): print("FT2_UI_FONT_MISSING ",JSON.stringify(app.view.font.missing))
	check(app.view.font.missing.is_empty(),"updated UI finds portable font glyphs")
	app._release_runtime();app.queue_free()
	await process_frame;await process_frame
	await create_timer(0.3).timeout # Let the stopped audio mixer release its last stream block.
	font = null;assets = null;store = null
