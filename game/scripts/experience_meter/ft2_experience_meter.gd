extends RefCounted
## 414B90 plus the presentation side effects of413FE0 states7/8.
## Numeric EXP, 20ms gating, pending levels and modal clock stay in battle logic.
const EXP_FORMAT = "%3d포인트의 경험치를 얻었다."
const LEVEL_FORMAT = "레벨%d(으)로 올랐다!"
var origin = Vector2i(160,300) # Original449FC0/449FC4 initial image values.
var active = false

func panel(x: int,y: int,total_exp: int,level: int = 0) -> Array:
	var out: Array = [
		{"op":"panel","x":x,"y":y,"width":19,"height":4},
		{"op":"font","height":16,"color":30,"style":1},
		{"op":"text","x":x+16,"y":y+20,"flags":0,"format":EXP_FORMAT,"value":total_exp}]
	if level != 0: out.append({"op":"text","x":x+16,"y":y+40,"flags":0,"format":LEVEL_FORMAT,"value":level})
	return out

func _blit(destination: String,x: int,y: int,source: String,rect = null,keyed: int = 0) -> Dictionary:
	return {"op":"blit","destination":destination,"x":x,"y":y,"source":source,"rect":rect,"keyed":keyed}

func service(operation: String,request: Dictionary = {}) -> Array:
	var out: Array = []
	if operation == "begin":
		active = true
		origin = Vector2i(int(request.get("x",160)),int(request.get("y",300)))
		out = [{"op":"sound_path","type":15,"stem":"meter"},
			{"op":"sound_load","stem":"meter"},
			{"op":"sound_path","type":15,"stem":"levelup"},
			{"op":"sound_load","stem":"levelup"},
			{"op":"sound_volume","stem":"meter","value":-800}]
		out.append_array(panel(origin.x,origin.y,int(request.initial_exp)))
		# Source saves the panel into4499D0; it does not save the pre-panel map.
		out.append(_blit("backdrop",0,0,"main"))
		out.append({"op":"present"})
	elif operation == "award":
		if int(request.pending_levels) != int(request.previous_pending_levels):
			out.append(_blit("main",0,0,"backdrop"))
			out.append_array(panel(origin.x,origin.y,int(request.initial_exp),int(request.level)+int(request.pending_levels)))
			out.append({"op":"sound_play","stem":"levelup","value":0})
		# Native idiv remainder is signed; do not clamp negative injected EXP fixtures.
		var exp_value = int(request.exp)
		@warning_ignore("integer_division")
		var filled = (exp_value-(exp_value/100)*100)*3
		#44A3AC is BMP/WALL (320x288), loaded by41ACDC with source key5.
		out.append(_blit("main",origin.x+20,origin.y+64,"wall",[160,176,310,192],1))
		out.append(_blit("main",origin.x+170,origin.y+64,"wall",[160,176,310,192],1))
		out.append(_blit("main",origin.x+20,origin.y+64,"wall",[160,160,160+mini(150,filled),176],1))
		if filled > 150: out.append(_blit("main",origin.x+170,origin.y+64,"wall",[160,160,filled+10,176],1))
		out.append({"op":"present"})
		out.append({"op":"sound_play","stem":"meter","value":0})
	elif operation == "finish":
		active = false
		out = [{"op":"sound_release","stem":"meter"},{"op":"sound_release","stem":"levelup"},
			{"op":"party_ui_refresh","value":1},{"op":"clear","surface":"backdrop","color":0}]
	return out
