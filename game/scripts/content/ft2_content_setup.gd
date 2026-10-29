extends Control
## Runs before the game and its content-dependent constructors are instantiated.

var configuration: Dictionary = {}
var config_path := "user://content_connection.json"
var source_field: LineEdit
var cache_field: LineEdit
var font_field: LineEdit
var cdda_field: LineEdit
var soundfont_field: LineEdit
var mods_field: TextEdit
var status_label: Label
var connect_button: Button
var import_button: Button
var worker: Thread
var local_defaults: Dictionary = {}

func _ready() -> void:
	Engine.max_fps = 60
	var force_setup := false
	var check_only := false
	var cli_mods: Array = []
	var cli: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if arg == "--setup": force_setup = true
		elif arg == "--check-content": check_only = true
		elif arg.begins_with("--engine-config="): config_path = arg.trim_prefix("--engine-config=")
		elif arg.begins_with("--source-root="): cli.source_root = arg.trim_prefix("--source-root=")
		elif arg.begins_with("--content-root="): cli.content_root = arg.trim_prefix("--content-root=")
		elif arg.begins_with("--mod="): cli_mods.append(arg.trim_prefix("--mod="))
		elif arg == "--no-mods": cli.mods = []
	if not cli_mods.is_empty(): cli.mods = cli_mods
	if FileAccess.file_exists(config_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(config_path))
		if parsed is Dictionary: configuration = parsed
	var local_path := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("local_setup.json")
	if not FileAccess.file_exists(local_path): local_path = OS.get_executable_path().get_base_dir().path_join("local_setup.json")
	if FileAccess.file_exists(local_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(local_path))
		if parsed is Dictionary:
			var platform_key := "windows" if OS.get_name() == "Windows" else "macos" if OS.get_name() == "macOS" else "linux"
			local_defaults = parsed.get(platform_key,{})
	for key in ["source_root","content_root","font","cdda_dir","soundfont"]:
		if not configuration.has(key) and local_defaults.has(key): configuration[key] = local_defaults[key]
	configuration.merge(cli,true)
	if not force_setup and configuration.has("source_root") and configuration.has("content_root"):
		var result := _mount()
		if result.ok:
			print("FT2_CONTENT ",JSON.stringify(result))
			if check_only: get_tree().quit(0)
			else: get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
			return
		configuration["last_error"] = result.error
	if DisplayServer.get_name() == "headless":
		print("FT2_CONTENT ",JSON.stringify({"ok":false,"error":configuration.get("last_error","정품 폴더와 개인 콘텐츠 캐시를 연결하세요.")}))
		get_tree().quit(2); return
	_build_ui()

func _mount() -> Dictionary:
	return FT2Content.activate(str(configuration.get("content_root","")),str(configuration.get("source_root","")),configuration.get("mods",[]))

func _line(parent: VBoxContainer, title: String, value: String, select_file: bool = false, filters: PackedStringArray = []) -> LineEdit:
	var label := Label.new(); label.text = title; parent.add_child(label)
	var row := HBoxContainer.new(); parent.add_child(row)
	var field := LineEdit.new(); field.text = value; field.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(field)
	var button := Button.new(); button.text = "파일 선택" if select_file else "폴더 선택"; row.add_child(button)
	button.pressed.connect(func(): _browse(field,select_file,filters))
	return field

func _build_ui() -> void:
	var background := ColorRect.new(); background.color = Color("17212f"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,18)
	add_child(margin)
	var scroll := ScrollContainer.new(); margin.add_child(scroll)
	var box := VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; box.add_theme_constant_override("separation",7); scroll.add_child(box)
	var title := Label.new(); title.text = "게임 데이터 연결"; title.add_theme_font_size_override("font_size",22); box.add_child(title)
	var description := Label.new(); description.text = "① 정품 게임 폴더 선택 → ② 게임 준비하기 → ③ 연결하고 실행\n처음 한 번만 준비하면 다음 실행부터 바로 게임이 시작됩니다."; description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; box.add_child(description)
	source_field = _line(box,"정품 설치 폴더 (DATA·MAP·SPRITE가 있는 폴더)",str(configuration.get("source_root","")))
	var advanced_button := Button.new(); advanced_button.text = "추가 옵션 (보통은 변경하지 않아도 됩니다)"; advanced_button.toggle_mode = true; box.add_child(advanced_button)
	var advanced := VBoxContainer.new(); advanced.visible = false; box.add_child(advanced)
	advanced_button.toggled.connect(func(on: bool): advanced.visible = on)
	cache_field = _line(advanced,"준비된 게임 데이터 폴더 (비워두면 자동)",str(configuration.get("content_root","")))
	font_field = _line(advanced,"한글 폰트 파일 (선택 사항, 비워두면 자동)",str(configuration.get("font","")),true,PackedStringArray(["*.ttf,*.ttc,*.otf ; Font files"]))
	cdda_field = _line(advanced,"CD 배경음 WAV 폴더 (선택 사항)",str(configuration.get("cdda_dir","")))
	soundfont_field = _line(advanced,"MIDI SoundFont 파일 (선택 사항)",str(configuration.get("soundfont","")),true,PackedStringArray(["*.sf2 ; SoundFont files"]))
	var label := Label.new(); label.text = "커스텀 모드 폴더 — 한 줄에 하나, 아래쪽이 우선"; box.add_child(label)
	mods_field = TextEdit.new(); mods_field.custom_minimum_size.y = 55; mods_field.text = "\n".join(configuration.get("mods",[])); box.add_child(mods_field)
	var actions := HBoxContainer.new(); box.add_child(actions)
	import_button = Button.new(); import_button.text = "게임 준비하기"; import_button.pressed.connect(_import); actions.add_child(import_button)
	connect_button = Button.new(); connect_button.text = "연결하고 실행"; connect_button.pressed.connect(_connect_game); actions.add_child(connect_button)
	status_label = Label.new(); status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; status_label.text = str(configuration.get("last_error","정품 데이터와 개인 캐시는 엔진 배포물에 포함되지 않습니다.")); box.add_child(status_label)

func _browse(field: LineEdit, select_file: bool = false, filters: PackedStringArray = []) -> void:
	var dialog := FileDialog.new(); dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE if select_file else FileDialog.FILE_MODE_OPEN_DIR
	dialog.filters = filters
	var directory := field.text.get_base_dir() if select_file else field.text
	dialog.current_dir = directory if DirAccess.dir_exists_absolute(directory) else OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	add_child(dialog)
	if select_file: dialog.file_selected.connect(func(path): field.text = path; dialog.queue_free())
	else: dialog.dir_selected.connect(func(path): field.text = path; dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered_ratio(0.85)

func _capture_fields() -> void:
	configuration.source_root = source_field.text.strip_edges()
	configuration.content_root = cache_field.text.strip_edges()
	configuration.erase("legacy_port")
	configuration.font = font_field.text.strip_edges()
	configuration.cdda_dir = cdda_field.text.strip_edges()
	configuration.soundfont = soundfont_field.text.strip_edges()
	configuration.mods = []
	for line in mods_field.text.split("\n",false):
		if not line.strip_edges().is_empty(): configuration.mods.append(line.strip_edges())

func _connect_game() -> void:
	_capture_fields()
	var result := _mount()
	if not result.ok: status_label.text = result.error; return
	configuration.erase("last_error")
	var file := FileAccess.open(config_path,FileAccess.WRITE)
	if file == null: status_label.text = "연결 설정을 저장할 수 없습니다."; return
	file.store_string(JSON.stringify(configuration,"\t")); file.close()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _import() -> void:
	_capture_fields()
	if not DirAccess.dir_exists_absolute(str(configuration.source_root)):
		status_label.text = "정품 설치 폴더를 먼저 선택하세요."; return
	var tool := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("tools/convert_installation.py")
	if not FileAccess.file_exists(tool): tool = OS.get_executable_path().get_base_dir().path_join("tools/convert_installation.py")
	if not FileAccess.file_exists(tool): status_label.text = "캐시 생성 도구를 찾을 수 없습니다."; return
	var python := str(configuration.get("python",local_defaults.get("python","python" if OS.get_name() == "Windows" else "python3")))
	var cache_parent := _cache_parent(str(configuration.content_root))
	var arguments := _conversion_arguments(tool,configuration,cache_parent)
	var bundled := OS.get_executable_path().get_base_dir().path_join("tools/ft2-convert/ft2-convert"+(".exe" if OS.get_name() == "Windows" else ""))
	if FileAccess.file_exists(bundled):
		python = bundled
		arguments.remove_at(0) # The standalone converter already contains its Python entry point.
	status_label.text = "게임 실행을 준비하고 있습니다. 처음에는 몇 분 걸릴 수 있습니다…"
	connect_button.disabled = true; import_button.disabled = true
	OS.set_environment("PYTHONUTF8","1")
	worker = Thread.new()
	var error := worker.start(_run_import.bind(python,arguments))
	if error != OK:
		worker = null; connect_button.disabled = false; import_button.disabled = false
		status_label.text = "변환 작업을 시작하지 못했습니다."

func _cache_parent(selected: String) -> String:
	if selected.is_empty(): return ProjectSettings.globalize_path("user://content")
	if FileAccess.file_exists(selected.path_join("content.json")): return selected.get_base_dir()
	return selected

static func _conversion_arguments(tool: String, options: Dictionary, cache_parent: String) -> PackedStringArray:
	var result := PackedStringArray([tool,"--source",str(options.get("source_root","")),"--cache-parent",cache_parent])
	for pair in [["font","--font"],["cdda_dir","--cdda-dir"],["soundfont","--soundfont"]]:
		var value := str(options.get(pair[0],"")).strip_edges()
		if value != "": result.append(str(pair[1])); result.append(value)
	return result

func _run_import(python: String, arguments: PackedStringArray) -> void:
	var output: Array = []
	var code := OS.execute(python,arguments,output,true,false)
	call_deferred("_import_complete",code,"".join(output))

static func _conversion_result(output: String) -> Variant:
	var lines := output.strip_edges().split("\n",false)
	for index in range(lines.size()-1,-1,-1):
		var decoder := JSON.new()
		if decoder.parse(str(lines[index]).strip_edges()) != OK: continue
		var parsed = decoder.data
		if parsed is Dictionary and (parsed.has("status") or parsed.has("error")): return parsed
	return null

func _import_complete(code: int, output: String) -> void:
	if worker != null: worker.wait_to_finish(); worker = null
	connect_button.disabled = false; import_button.disabled = false
	var result = _conversion_result(output)
	if code != 0 or not result is Dictionary or result.get("status","") != "ready" or not result.has("content_root") or not result.has("source_root"):
		status_label.text = "캐시 생성 실패: "+str(result.get("error",output) if result is Dictionary else output); return
	cache_field.text = str(result.content_root)
	if result.has("source_root"): source_field.text = str(result.source_root)
	status_label.text = "변환이 완료되었습니다. 연결하고 실행을 누르세요."
	var messages: Array[String] = []
	for warning in result.get("warnings",[]):
		if warning is Dictionary: messages.append(str(warning.get("message",warning.get("error",JSON.stringify(warning)))))
		else: messages.append(str(warning))
	if not messages.is_empty(): status_label.text += "\n안내: "+"\n".join(messages)

func _exit_tree() -> void:
	if worker != null:
		worker.wait_to_finish(); worker = null
