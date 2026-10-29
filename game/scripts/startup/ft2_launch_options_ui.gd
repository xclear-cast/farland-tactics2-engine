extends RefCounted
## Source resource156 frontend; platform/profile application belongs to Main.
signal completed(result:int,portable_profile:Dictionary)
const SourceModel=preload("res://scripts/startup/ft2_launch_options.gd")
const PROVIDED_PROFILE:={"EmulationMode":0,"MusicDevice":2,"FullScreenMode":1,"SilenceEffect":0}
var model
var base
var active:=false
var focus:=1
var captured:=-1
var pressed:=-1
var keyboard_capture:=-1
var default_button:=1
var _reported:=false

func configure(data,battle,vm,model_script)->void:
	dispose()
	model=(model_script if model_script!=null else SourceModel).new()
	base=preload("res://scripts/ui/ft2_interface.gd").new();base.configure(data,battle,vm,false);base.persistence_enabled=false

func open(profile:Dictionary=PROVIDED_PROFILE,adapter:Dictionary={})->void:
	model.begin(profile,adapter);base._open("launch156",156);active=true;focus=1;captured=-1;pressed=-1;keyboard_capture=-1;_reported=false
	base._control_rects[61536]=Rect2i(base._dialog_outer.position+Vector2i(base._dialog_outer.size.x-21,5),Vector2i(16,14))
	_set_focus(1)

func _set_focus(control:int)->void:
	focus=control;default_button=focus if focus in [1,2]else 1;model.message(0x135,0,focus) # Explicit simulated native focus-paint boundary.

func cancel_capture()->void:captured=-1;pressed=-1;keyboard_capture=-1

func cancel_from_os()->void:
	if active:_activate(61536) # SourceWM_CLOSE returns0 and never commits staged keys.

func dispose()->void:
	active=false;_reported=true;cancel_capture()
	if base!=null:
		base.cancel_control_capture()
		if base.experience!=null:
			if base.experience.finished.is_connected(base._experience_finished):base.experience.finished.disconnect(base._experience_finished)
			if base.experience.cursor_refresh_requested.is_connected(base._refresh_cursor):base.experience.cursor_refresh_requested.disconnect(base._refresh_cursor)
		base.experience=null;base.unit_panel=null
	base=null;model=null

func _activate(control:int)->void:
	if control==61536:model.message(0x10)
	else:model.user_activate(control)
	if not model.ended.is_empty() and not _reported:
		active=false;_reported=true;cancel_capture();completed.emit(int(model.ended[-1]),model.portable_commit())

func _hit(point:Vector2i)->int:
	for control in base._control_rects:
		if control==61536 and base._control_rects[control].has_point(point):return control
		if control in [1,2,1090,1091,1092,1093,1094,1095,1097,1098] and control not in model.disabled and base._control_rects[control].has_point(point):return int(control)
	return -1

func _tab_order()->Array[int]:
	var order:Array[int]=[1,2]
	for pair in ["1092..1093","1090..1091","1094..1095"]:
		var checked:=int(model.checked[pair])
		if checked not in model.disabled:order.append(checked)
	return order

func handle_input(event:InputEvent)->bool:
	if not active:return false
	if event is InputEventKey:
		if event.keycode==KEY_SPACE:
			if event.pressed:
				if not event.echo:keyboard_capture=focus;pressed=focus
			else:
				var held:=keyboard_capture;cancel_capture()
				if held==focus and held>=0:_activate(held)
			return true
		if not event.pressed:return true
		if event.keycode==KEY_F4 and event.alt_pressed:_activate(61536);return true
		if event.keycode==KEY_ESCAPE:_activate(2);return true
		if event.keycode in [KEY_ENTER,KEY_KP_ENTER]:_activate(2 if focus==2 else default_button);return true
		if event.alt_pressed:
			# Shipping156 has no ampersand mnemonics; never invent Alt+S/C.
			for row in base._template.controls:
				var caption:=str(row.title.get("value",""));var marker:=caption.find("&")
				if marker>=0 and marker+1<caption.length() and caption.substr(marker+1,1).to_upper()==String.chr(event.keycode).to_upper():_activate(int(row.id));return true
			return true
		if event.keycode==KEY_TAB:
			var order:=_tab_order();_set_focus(order[posmod(order.find(focus)+(-1 if event.shift_pressed else 1),order.size())]);return true
		if event.keycode in [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN]:
			for pair in model.checked:
				var bounds:=str(pair).split("..");var first:=int(bounds[0]);var last:=int(bounds[1])
				if focus>=first and focus<=last:
					var next:=last if focus==first else first
					if next not in model.disabled:_set_focus(next);_activate(next)
					return true
		return true
	if event is InputEventMouseMotion:
		if captured>=0:pressed=captured if _hit(Vector2i(event.position))==captured else -1
		return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			captured=_hit(Vector2i(event.position));pressed=captured
			if captured>=0 and captured!=61536:_set_focus(captured)
		else:
			var held:=captured;cancel_capture()
			if held>=0 and _hit(Vector2i(event.position))==held:_activate(held)
		return true
	return true

func commands()->Array[Dictionary]:
	var out:Array[Dictionary]=[]
	if not active:return out
	base._panel(out,base._dialog_outer)
	out.append({"op":"rect","rect":Rect2i(base._dialog_outer.position+Vector2i(3,3),Vector2i(base._dialog_outer.size.x-6,18)),"color":4,"filled":true})
	base._text(out,base._title,base._dialog_outer.position+Vector2i(5,6),255)
	preload("res://scripts/ui/ft2_stage_widgets.gd").mask(out,base._control_rects[61536].position,preload("res://scripts/ui/ft2_stage_widgets.gd").CLOSE)
	for i in base._template.controls.size():
		var row:Dictionary=base._template.controls[i];var control:=int(row.id);var rect:Rect2i=base._row_rects[i];var caption:=str(row.title.get("value",""));var disabled:bool=(str(row.style).hex_to_int()&0x8000000)!=0 or control in model.disabled
		if row.class_name=="BUTTON":
			if (str(row.style).hex_to_int()&15)==9:
				var checked:=false
				for pair in model.checked:
					if int(model.checked[pair])==control:checked=true
				base._draw_check(out,rect,caption,true,checked,disabled,focus==control,pressed==control)
			else:base._draw_button(out,rect,caption,control==default_button,disabled,focus==control,pressed==control)
		elif row.class_name=="STATIC":base._text(out,caption,rect.position,248 if disabled else 0)
		elif control==1096:_help_commands(out,rect)
	return out

func _help_commands(out:Array[Dictionary],rect:Rect2i)->void:
	var y:=rect.position.y
	for paragraph in model.help_text.replace("\r\n","\n").split("\n"):
		for line in preload("res://scripts/ui/ft2_widgets.gd").wrap_lines(paragraph,rect.size.x,func(value):return base._raw_width(value,base.UI_FONT)):
			if not line.is_empty():base._text(out,line,Vector2i(rect.position.x,y),0);out[-1]["clip"]=rect
			y+=13
