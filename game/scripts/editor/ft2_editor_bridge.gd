# SPDX-License-Identifier: MIT
extends RefCounted
## Authenticated local bridge. The MCP stdio transport lives in tools/editor_mcp.py.
const LIMIT:=1024*1024
const TIMEOUT_MS:=5000
const MAX_CLIENTS:=8
var connection_path:="user://editor_mcp_connection.json"
var _editor
var _server: TCPServer
var _clients: Array=[]
var _token:=""
var _port:=0
var _workspace:=""
var _last_tool:=""
var _requests:=0
var _error:=""

func start(editor,port: int=0) -> Dictionary:
	stop();_editor=editor;_error=""
	if editor==null or port<0 or port>65535:return {"ok":false,"error":"Invalid editor or port"}
	_server=TCPServer.new()
	var error:=_server.listen(port,"127.0.0.1")
	if error!=OK:_server=null;return {"ok":false,"error":"로컬 MCP 포트를 열 수 없습니다."}
	_port=_server.get_local_port()
	_token=Crypto.new().generate_random_bytes(32).hex_encode()
	_workspace=_canonical(editor.project.folder if not editor.project.folder.is_empty()else "user://mcp_projects")
	if not editor.project._safe_output(_workspace):stop();return {"ok":false,"error":"원작·캐시 밖에 프로젝트를 저장한 뒤 연결하세요."}
	var path:=ProjectSettings.globalize_path(connection_path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var directory:=DirAccess.open(path.get_base_dir())
	if directory==null or directory.is_link(path.get_file())or directory.is_link(path.get_file()+".writing"):
		stop();return {"ok":false,"error":"연결 파일은 실제 사용자 폴더에 저장해야 합니다."}
	var temporary:=path+".writing"
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:stop();return {"ok":false,"error":"MCP 연결 파일을 만들 수 없습니다."}
	if OS.get_name()!="Windows":FileAccess.set_unix_permissions(temporary,FileAccess.UNIX_READ_OWNER|FileAccess.UNIX_WRITE_OWNER)
	file.store_string(JSON.stringify({"schema":1,"host":"127.0.0.1","port":_port,"token":_token,"pid":OS.get_process_id()}));file.close()
	if DirAccess.rename_absolute(temporary,path)!=OK:
		DirAccess.remove_absolute(temporary);stop();return {"ok":false,"error":"MCP 연결 파일을 갱신할 수 없습니다."}
	return {"ok":true,"port":_port,"connection_file":path,"workspace":_workspace}

func stop() -> void:
	for client in _clients:client.peer.disconnect_from_host()
	_clients.clear()
	if _server!=null:_server.stop();_server=null
	var path:=ProjectSettings.globalize_path(connection_path)
	if not _token.is_empty()and FileAccess.file_exists(path):
		var document=JSON.parse_string(FileAccess.get_file_as_string(path))
		if document is Dictionary and document.get("token")==_token:DirAccess.remove_absolute(path)
	_token="";_port=0;_editor=null

func status() -> Dictionary:
	return {"running":_server!=null and _server.is_listening(),"port":_port,"connection_file":ProjectSettings.globalize_path(connection_path),"workspace":_workspace,"last_tool":_last_tool,"requests":_requests,"error":_error}

func poll() -> void:
	if _server==null:return
	while _server.is_connection_available():
		var peer:=_server.take_connection()
		if _clients.size()>=MAX_CLIENTS:peer.disconnect_from_host();continue
		_clients.append({"peer":peer,"buffer":PackedByteArray(),"started":Time.get_ticks_msec()})
	for index in range(_clients.size()-1,-1,-1):
		var client: Dictionary=_clients[index];var peer: StreamPeerTCP=client.peer
		peer.poll()
		if Time.get_ticks_msec()-int(client.started)>TIMEOUT_MS or peer.get_status()!=StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host();_clients.remove_at(index);continue
		var count:=mini(peer.get_available_bytes(),65536)
		if count>0:
			var packet:=peer.get_data(count)
			if int(packet[0])!=OK:peer.disconnect_from_host();_clients.remove_at(index);continue
			client.buffer.append_array(packet[1])
		if client.buffer.size()>LIMIT:
			_send(peer,{"error":{"message":"Request exceeds 1 MiB"}});_clients.remove_at(index);continue
		var newline: int=client.buffer.find(10)
		if newline<0:continue
		var parser:=JSON.new();var response: Dictionary
		if parser.parse(client.buffer.slice(0,newline).get_string_from_utf8())!=OK or not parser.data is Dictionary:
			response={"error":{"message":"Expected one JSON object"}}
		else:response=_dispatch(parser.data)
		_send(peer,response);_clients.remove_at(index)

func _send(peer: StreamPeerTCP,response: Dictionary) -> void:
	var bytes:=(JSON.stringify(response)+"\n").to_utf8_buffer()
	if bytes.size()>LIMIT:bytes=(JSON.stringify({"error":{"message":"Response exceeds 1 MiB; use a single-record query"}})+"\n").to_utf8_buffer()
	peer.put_data(bytes);peer.disconnect_from_host()

func _canonical(path: String) -> String:
	return ProjectSettings.globalize_path(path).replace("\\","/").simplify_path().trim_suffix("/")

func _allowed_path(path: String) -> bool:
	if path.is_empty():return false
	var absolute:=_canonical(path)
	var scope:=absolute.to_lower()if OS.get_name()=="Windows"else absolute
	var base:=_workspace.to_lower()if OS.get_name()=="Windows"else _workspace
	if scope!=base and not scope.begins_with(base+"/"):return false
	var cursor:=absolute
	while not cursor.is_empty():
		var parent:=cursor.get_base_dir();var directory:=DirAccess.open(parent)
		if directory!=null and directory.is_link(cursor.get_file()):return false
		if parent==cursor:break
		cursor=parent
	return _editor.project._safe_output(absolute)

func _failure(message: String) -> Dictionary:return {"ok":false,"error":message}

func _refresh() -> void:
	_editor._refresh_all();_editor._checkpoint()
	if _editor.has_method("_refresh_workbench"):_editor._refresh_workbench()

func _merge(base: Dictionary,patch: Dictionary) -> Dictionary:
	var result:=base.duplicate(true)
	for key in patch:
		if patch[key]is Dictionary and result.get(key)is Dictionary:result[key]=_merge(result[key],patch[key])
		else:result[key]=patch[key]
	return result

func _shape(kind: String,row: Dictionary) -> bool:
	var allowed: Dictionary={"characters":["id","name","base_race","sprite","level","stats","skills"],"skills":["id","name","base_skill","visual_skill","mp","power","range_min","range_max"],"maps":["id","name","base_map","width","height","cells","placements"],"stories":["id","start","nodes"]}
	for key in row:
		if not str(key)in allowed[kind]:return false
		var value=row[key]
		if str(key)in ["id","name","sprite","start"]:
			if not value is String:return false
		elif str(key)=="stats":
			if not value is Dictionary:return false
			for number in value.values():
				if not(number is int or number is float):return false
		elif str(key)in ["skills","cells","placements","nodes"]:
			if not value is Array:return false
			for entry in value:
				if str(key)=="skills":
					if not(entry is String or entry is int or entry is float):return false
				elif not entry is Dictionary:return false
				elif not _nested_shape(str(key),entry):return false
		elif not(value is int or value is float):return false
	return true

func _nested_shape(kind: String,row: Dictionary) -> bool:
	var strings: Array=[];var numbers: Array=[];var scalars: Array=[]
	if kind=="cells":numbers=["x","y","height","terrain"]
	elif kind=="placements":strings=["character","sprite","side"];numbers=["race","x","y","level"]
	elif kind=="nodes":strings=["id","type","speaker","text","next","map","on_defeat","variable","then","else"];scalars=["value","equals"]
	elif kind=="choices":strings=["text","next"]
	for key in row:
		var value=row[key]
		if str(key)in strings:
			if not value is String:return false
		elif str(key)in numbers:
			if not(value is int or value is float):return false
		elif str(key)in scalars:
			if not(value is String or value is int or value is float or value is bool or value==null):return false
		elif kind=="nodes"and str(key)=="choices":
			if not value is Array:return false
			for choice in value:
				if not choice is Dictionary or not _nested_shape("choices",choice):return false
		elif kind=="choices"and str(key)=="set":
			if not value is Dictionary:return false
			for flag in value.values():
				if not(flag is String or flag is int or flag is float or flag is bool or flag==null):return false
		else:return false
	return true

func _dispatch(request: Dictionary) -> Dictionary:
	if str(request.get("token",""))!=_token or _token.is_empty():return {"id":request.get("id"),"error":{"message":"Authentication failed"}}
	if not request.get("params",{})is Dictionary:return {"id":request.get("id"),"error":{"message":"Expected object params"}}
	var method:=str(request.get("method",""));var params: Dictionary=request.get("params",{})
	for key in ["index","original_id","offset","limit"]:
		if params.has(key)and (not(params[key]is int or params[key]is float)or float(params[key])!=int(params[key])):
			return {"id":request.get("id"),"error":{"message":"Expected integer "+key}}
	_last_tool=method;_requests+=1
	if _editor.has_method("_commit_pending"):_editor._commit_pending()
	var result: Dictionary=_tool(method,params)
	return {"id":request.get("id"),"result":result}

func _tool(method: String,params: Dictionary) -> Dictionary:
	var model=_editor.project
	if method=="read_project":return {"ok":true,"descriptor":model.descriptor.duplicate(true),"content":model.content.duplicate(true),"folder":model.folder,"baseline":model.baseline_status(),"workspace":_workspace}
	if method=="list_originals":
		var rows: Array=model.original_catalog(str(params.get("kind","")),str(params.get("search","")))
		var offset:=maxi(0,int(params.get("offset",0)));var count:=clampi(int(params.get("limit",50)),1,200)
		return {"ok":true,"rows":rows.slice(offset,offset+count),"total":rows.size(),"baseline":model.baseline_status()}
	if method in ["save","open","export"]:
		var fallback: String=model.folder if not model.folder.is_empty()else _workspace.path_join(str(model.descriptor.id))
		if method=="export":fallback=_workspace.path_join(str(model.descriptor.id)+".zip")
		var path:=str(params.get("path",fallback))
		if not _allowed_path(path):return _failure("Path must remain inside the selected project workspace, outside original/cache folders and symlinks")
		if method=="save":return _editor.save_project(_canonical(path))
		if method=="open":
			var directory:=DirAccess.open(_canonical(path))
			if directory==null:return _failure("Project folder does not exist")
			if directory.is_link("mod.json")or directory.is_link("content.json"):return _failure("Project descriptors must not be symlinks")
			return _editor.load_project(_canonical(path))
		return _editor.export_project(_canonical(path))
	if method=="validate":return _editor.validate_project()
	if method=="get_debug_output":
		if not _editor.has_method("preview_status"):return _failure("This editor host does not provide preview debug output")
		var preview: Dictionary=_editor.preview_status().duplicate(true)
		preview["ok"]=true
		return preview
	if method=="stop_play":
		if not _editor.has_method("stop_preview"):return _failure("This editor host does not provide a separate preview process")
		return _editor.stop_preview()
	if method=="play":
		if model.folder.is_empty():return _failure("Save the project before requesting a play test")
		if not _allowed_path(model.folder):return _failure("Project is outside this MCP workspace; restart the connection")
		if model.source_data==null:return _failure("Connect and prepare your original game data before a play test")
		var checked: Dictionary=_editor.validate_project()
		if not checked.ok:return checked
		var saved: Dictionary=_editor.save_project(model.folder)
		if not saved.ok:return saved
		if _editor.has_method("launch_preview"):return _editor.launch_preview()
		_editor.call_deferred("_test_clicked")
		return {"ok":true,"status":"play_requested","blocking":false}
	var kind:=str(params.get("kind",""))
	if not kind in model.KINDS:return _failure("kind must be characters, skills, maps or stories")
	if method=="create_record":
		var record: Dictionary={}
		if params.has("original_id"):
			if kind=="characters":record=model.original_character(int(params.original_id))
			elif kind=="skills":record=model.original_skill(int(params.original_id))
			if record.is_empty():return _failure("Original reference is unavailable")
			record.id=model.next_id(kind,"character"if kind=="characters"else"skill")
		if not params.get("record",{})is Dictionary:return _failure("record must be an object")
		record=_merge(record,params.get("record",{}))
		if not record.has("id"):record.id=model.next_id(kind,kind.trim_suffix("s"))
		if not _shape(kind,record)or not model.valid_id(str(record.id)):return _failure("Unsupported record fields or value types")
		if model.has_id(kind,record.id):return _failure("Record ID already exists")
		model.update_record(kind,-1,record);_refresh()
		return {"ok":true,"index":model.content[kind].size()-1,"record":record.duplicate(true)}
	var index:=int(params.get("index",-1))
	if index<0 or index>=model.content[kind].size():return _failure("Record index does not exist")
	if method=="get_record":return {"ok":true,"record":model.content[kind][index].duplicate(true),"changed_fields":model.changed_fields(kind,index)}
	if method=="update_record":
		if not params.get("patch")is Dictionary:return _failure("patch must be an object")
		var record:=_merge(model.content[kind][index],params.patch)
		if not _shape(kind,record)or not model.valid_id(str(record.id)):return _failure("Unsupported record fields or value types")
		for other in model.content[kind].size():
			if other!=index and model.content[kind][other].get("id")==record.id:return _failure("Record ID already exists")
		model.update_record(kind,index,record);_refresh()
		return {"ok":true,"record":record.duplicate(true),"changed_fields":model.changed_fields(kind,index)}
	if method in ["reset_field","reset_record"]:
		var result: Dictionary=model.reset_field(kind,index,str(params.get("key","")))if method=="reset_field"else model.reset_record(kind,index)
		if result.ok:_refresh()
		return result
	return _failure("Unknown editor tool")
