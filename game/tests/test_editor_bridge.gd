extends SceneTree
## Private synthetic bridge host. No original assets or user connection files.
const Bridge=preload("res://scripts/editor/ft2_editor_bridge.gd")
const Project=preload("res://scripts/editor/ft2_expansion_project.gd")
class SyntheticData:
	extends RefCounted
	var repo_root:=""
	var source_root:=""
class EditorFixture:
	extends RefCounted
	var project=Project.new()
	var refreshes:=0
	var plays:=0
	func _refresh_all():refreshes+=1
	func _checkpoint():pass
	func save_project(path):return project.save_project(path)
	func load_project(path):return project.load_project(path)
	func export_project(path):return project.export_project(path)
	func validate_project():return project.validate_project()
	func _test_clicked():plays+=1

var bridge=Bridge.new()
var editor=EditorFixture.new()
var output:=""
var started:=0

func write(path: String,value) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(value));file.close()

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bridge-fixture="):output=arg.trim_prefix("--bridge-fixture=")
	if output.is_empty():quit(2);return
	call_deferred("run")

func run() -> void:
	var cache:=output.path_join("protected-cache")
	var data:=SyntheticData.new();data.repo_root=cache;data.source_root=output.path_join("protected-original")
	var stats: Dictionary={}
	for stat in Project.STAT_NAMES:stats[stat]={"initial":20,"growth":2}
	write(cache.path_join("data/port_ready/tables/race.dat.json"),{"records":[{"id":0,"name":"자작 원본 테스트","stats":stats,"default_skill_slots4":[1,0,0,0]}]})
	write(cache.path_join("data/port_ready/tables/magic.dat.json"),{"records":[{"id":0,"name":"없음"},{"id":1,"name":"자작 원본 스킬","mp":6,"power":5,"v2":0,"flag":2}]})
	write(cache.path_join("data/port_ready/assets/apd/animations/CHAR_00E.json"),{})
	editor.project.source_data=data
	editor.project.content.characters[0].base_race=0;editor.project.content.characters[1].base_race=0
	editor.project.save_project(output.path_join("project"))
	bridge.connection_path=output.path_join("connection.json")
	var result: Dictionary=bridge.start(editor)
	write(output.path_join("ready.json"),result)
	started=Time.get_ticks_msec()

func _process(_delta: float) -> bool:
	if started==0:return false
	bridge.poll()
	if FileAccess.file_exists(output.path_join("stop"))or Time.get_ticks_msec()-started>120000:
		var report:=bridge.status();report["plays"]=editor.plays;report["refreshes"]=editor.refreshes
		bridge.stop();write(output.path_join("stopped.json"),report);quit()
	return false
