extends SceneTree
const Clients=preload("res://scripts/editor/ft2_editor_clients.gd")
const EXPECTED:=["claude_code","claude_desktop","codex","codebuddy","grok","antigravity","cursor","windsurf","vscode","vscode_insiders","zed","gemini_cli","cline","kilo_code","roo_code","zoo_code","kiro","trae","opencode","qwen_code","kimi_code","hermes","pi","deepseek_harness","zcode","omp"]
var output:=""
var checks:=0
var failures: Array[String]=[]
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--clients-output="):output=arg.trim_prefix("--clients-output=")
	if output.is_empty():quit(2);return
	call_deferred("run")
func write(path: String,text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(text);file.close()
func run() -> void:
	var launch:={"command":"D:\\내 작업\\ft2-convert.exe","args":["--editor-mcp","--connection","D:\\내 작업\\연결 \"예시\".json"]}
	var profiles: Array=Clients.all();var ids: Array=[]
	for profile in profiles:ids.append(profile.id)
	check(ids==EXPECTED,"exact upstream 26 clients and order")
	var cases: Array=[]
	for profile in profiles:
		check(not str(profile.label).is_empty()and not str(profile.location).is_empty(),"display metadata "+str(profile.id))
		var text:=Clients.build(str(profile.id),launch)
		check(not text.is_empty(),"config generated "+str(profile.id))
		if profile.format=="json":
			var document=JSON.parse_string(text)
			check(document is Dictionary,"valid JSON "+str(profile.id))
			if document is Dictionary:
				var entry: Dictionary
				match str(profile.id):
					"vscode","vscode_insiders":entry=document.servers.ft2
					"zed":entry=document.context_servers.ft2
					"zcode":entry=document.mcp.servers.ft2
					"opencode":entry=document.mcp.ft2
					_:entry=document.mcpServers.ft2
				if profile.id=="opencode":check(entry.command==[launch.command]+launch.args,"OpenCode V1 argv array")
				else:check(entry.command==launch.command and entry.args==launch.args,"flat launch roundtrip "+str(profile.id))
				if profile.id in ["claude_code","codebuddy","cursor","vscode","vscode_insiders","cline","roo_code","zoo_code","zcode"]:check(entry.get("type")=="stdio","explicit stdio "+str(profile.id))
				if profile.id in ["antigravity","windsurf","zed","kilo_code","kiro","trae","gemini_cli","qwen_code","kimi_code","pi","omp"]:check(not entry.has("type"),"canonical typeless stdio "+str(profile.id))
		var extension:="json"if profile.format=="json"else"toml"if profile.format=="toml"else"yaml"
		var name:=str(profile.id)+"."+extension;write(output.path_join(name),text)
		cases.append({"id":profile.id,"format":profile.format,"file":name})
	var v2=JSON.parse_string(Clients.build("opencode",launch,2))
	check(v2.mcp.has("servers")and not v2.mcp.has("ft2"),"V2 servers map distinct from V1")
	check(v2.mcp.servers.ft2.protocol=="legacy"and not v2.mcp.servers.ft2.has("enabled"),"V2 classic protocol and no V1 enabled field")
	write(output.path_join("opencode_v2.json"),JSON.stringify(v2))
	check(Clients.build("unknown",launch).is_empty(),"unknown client rejected")
	check(Clients.build("codex",{"command":"x","args":[3]}).is_empty(),"non-string argv rejected")
	check(JSON.parse_string(Clients.build("generic",launch)).mcpServers.ft2.command==launch.command,"generic preset separate from upstream list")
	profiles[0].label="changed"
	check(Clients.all()[0].label=="Claude Code","registry callers own their presentation dictionaries")
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"cases":cases,"launch":launch}
	write(output.path_join("result.json"),JSON.stringify(report));print(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"failures":failures}));quit(0 if failures.is_empty()else 1)
