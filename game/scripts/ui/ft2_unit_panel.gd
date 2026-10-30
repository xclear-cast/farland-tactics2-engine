class_name FT2UnitPanel
extends RefCounted
## Original117/118/119/121 child templates and their live unit/bag fields.
var data
var _battle: WeakRef
var _vm: WeakRef
var numeric
var measure: Callable
var preview_unit: Callable
var controls: Dictionary = {}
var lists: Dictionary = {}
var selected: Dictionary = {}
var scrolls:Dictionary={}
var focused_list:=-1
var captions: Dictionary = {}
var current_template := 117
var current_slot := 0
var _faces: Dictionary={}
var _font:Dictionary=FONT
var _list_styles:Dictionary={}
var _list_clients:Dictionary={}
var _scrollbars:Dictionary={}
var disabled_controls:Dictionary={}
var _description_control:=1032
var _scroll_controller=preload("res://scripts/ui/ft2_scroll_controller.gd").new()
var _scroll_control:=-1
var input_clock_provider:Callable
var source_double_click_ms:=500
var focus_control:=-1
var pressed_control:=-1
var default_button:=-1
var focus_origin:=Vector2i.ZERO
var _magic_rows:Array=[]
var _magic_slot:=-1
const GAME_FONT := {"family":"바탕","height":16,"weight":700,"italic":false}
const FONT := {"family":"굴림","height":-12,"weight":400,"italic":false}
const STATES := ["정상","기절","독","잠","석화","냉동","침묵","매료","마비","불가시","준민","부유"]

func configure(store,battle,vm) -> void:
	data = store; _battle = weakref(battle); _vm = weakref(vm)
	numeric = preload("res://scripts/logic/ft2_numeric.gd").new(data)
	for row in data.read_json("data/port_ready/assets/bitmaps/index.json").files:
		if str(row.source).get_file().begins_with("FACE"): _faces[str(row.source).to_upper()]=Vector2i(int(row.size[0]),int(row.size[1]))

func stats(slot: int) -> Dictionary:
	var battle = _battle.get_ref(); var vm = _vm.get_ref()
	var raw: PackedByteArray = battle.units[slot]
	var unit: Dictionary = data.decode_unit(raw,slot)
	var races: Array = data.load_table("race")
	var out := {1008:vm.unit_name(slot),1010:str(races[int(unit.definition_id)].name),1014:"%3d/%3d" % [int(unit.hp),int(unit.hp_max)],1015:"%3d/%3d" % [int(unit.mp),int(unit.mp_max)],1033:"L%d" % int(unit.level),1032:"%5d" % int(unit.experience),1034:STATES[int(unit.state)] if int(unit.state) < STATES.size() else ""}
	for i in 5:
		var total: int = numeric.effective(raw,i)
		#41B57B..41B885 shows equipment plus temporary correction, not temporary alone.
		var correction := total-raw.decode_s16(46+i*2)
		out[1016+i] = "%3d(%s%2d)" % [total,"+" if correction>=0 else "-",absi(correction)]
	var attributes: Array = numeric.attributes(raw)
	var selected_attribute:=0
	for i in 3:
		if int(attributes[i])==0:continue
		out[[1044,1046,1048][selected_attribute]]=str(1+i*2+(1 if int(attributes[i])<0 else 0))
		out[1029+selected_attribute]=str(absi(int(attributes[i])));selected_attribute+=1
	while selected_attribute<3:
		out[[1044,1046,1048][selected_attribute]]="0";out[1029+selected_attribute]="";selected_attribute+=1
	return out

func description(table: String,ordinal: int) -> String:
	var parsed: Dictionary = data.read_json("data/port_ready/assets/text/canonical_DAT/"+table.to_upper()+"COM.DAT.json")
	for entry in parsed.get("entries",[]):
		if int(entry.index) == ordinal: return str(entry.text)
	return ""

func _populate(resource: int,slot: int) -> void:
	var battle = _battle.get_ref(); var vm = _vm.get_ref()
	var unit: PackedByteArray = battle.units[slot]
	captions = stats(slot); lists.clear()
	var items: Array = data.load_table("item")
	var magics: Array = data.load_table("magic")
	if resource == 119:
		var carry: Array[int] = []
		for i in 4:
			var id := unit.decode_u16(28+i*2)
			if id != 0: carry.append(id)
		for i in 4: unit.encode_u16(28+i*2,carry[i] if i<carry.size() else 0)
		battle.units[slot] = unit #41C430 stable compaction is a source-visible mutation.
		for i in 4:
			var id := unit.decode_u16(20+i*2)
			lists[[1035,1036,1037,1034][i]] = [{"id":id,"held_index":i,"text":str(items[id].name) if id < items.size() else ""}]
		lists[1032] = []
		for i in 4:
			var id := unit.decode_u16(28+i*2)
			lists[1032].append({"id":id,"held_index":i+4,"text":str(items[id].name) if id < items.size() and id != 0 else ""})
		var chosen := int(selected.get(1032,0)); var id: int = unit.decode_u16(28+clampi(chosen,0,3)*2)
		if _description_control in [1034,1035,1036,1037]:id=int(lists[_description_control][0].id)
		captions[1026] = description("ITEM",id)
	elif resource == 121:
		#41C910 builds this child list on creation/selected-unit change.107's
		#41DD0B WM_USER400 deliberately omits magic: ordinary paint cannot rebuild it.
		if _magic_slot!=slot:
			_magic_rows.clear();_magic_slot=slot
			for i in 10:
				var id := unit.decode_u16(56+i*2)
				if id != 0 and id < magics.size():_magic_rows.append({"id":id,"text":str(magics[id].name)})
			while _magic_rows.size()<10:_magic_rows.append({"id":0,"text":""})
		lists[1040] = _magic_rows.duplicate(true)
		var chosen := clampi(int(selected.get(1040,0)),0,9)
		captions[1039] = description("MAGIC",int(lists[1040][chosen].id))
		lists[1043] = [{"id":0,"text":FT2Content.ui_text("skill_list_header","이름                 MP")}]
	elif resource == 118:
		lists[1023] = []
		for index in 80:
			var id: int = battle.inventory.decode_u16(index*4)
			if id != 0 and id < items.size(): lists[1023].append({"id":id,"bag_index":index,"text":str(items[id].name),"count":battle.inventory.decode_s16(index*4+2)})
		while lists[1023].size() < 9: lists[1023].append({"id":0,"bag_index":80,"text":""})
		captions[1085] = str(battle.money)
		lists[1048] = [{"id":0,"text":FT2Content.ui_text("item_list_header","이름               수량")}]
		var chosen:=clampi(int(selected.get(1023,0)),0,lists[1023].size()-1)
		var id:=int(lists[1023][chosen].id)
		captions[1036]=description("ITEM",id)
		disabled_controls[1089]=id<=0 or numeric.items.decode_u16(id*56+20)==0
	elif resource in [144,145]: captions[1068]=description("RACE",65 if unit.decode_u16(0)==24 else unit.decode_u16(2)+1)

func commands(resource: int,slot: int,origin: Vector2i) -> Array[Dictionary]:
	if resource!=current_template or slot!=current_slot:
		cancel_capture()
		invalidate_magic()
		selected.clear();scrolls.clear();focused_list=-1;_description_control=1032
	current_template = resource; current_slot = slot;_font=preload("res://scripts/ui/ft2_widgets.gd").dialog_font(resource)
	disabled_controls.clear()
	_populate(resource,slot)
	var template: Dictionary = preload("res://scripts/ui/ft2_widgets.gd").dialog_template(data,resource)
	var out: Array[Dictionary] = []
	controls.clear();_list_styles.clear();_list_clients.clear();_scrollbars.clear()
	for control in template.get("controls",[]):
		var r: Array = control.rect_dialog_units
		var rect:Rect2i=preload("res://scripts/ui/ft2_widgets.gd").dlu_rect(r,origin,preload("res://scripts/ui/ft2_widgets.gd").dialog_base(resource))
		var id := int(control.id); controls[id] = rect
		var caption := str(captions.get(id,control.get("title",{}).get("value","")))
		if control.class_name == "STATIC": _paragraph(out,caption,rect,str(control.style).hex_to_int()&3)
		elif control.class_name == "LISTBOX":
			_list_styles[id]=str(control.style).hex_to_int()
			_draw_list(out,resource,id,rect)
		elif control.class_name == "BUTTON":
			var style := str(control.style).hex_to_int()&15
			if style==11 and id in [1044,1046,1048]:
				var icon:=int(captions.get(id,"0"))
				if icon>0:out.append({"op":"bitmap","key":"BMP/WALL.BMP","source":Rect2i((icon-1)*16,208,16,16),"pos":rect.position,"clip":rect,"transparent":-1})
			elif style==11 and id==1011:
				var kind:int=_battle.get_ref().units[slot].decode_u16(0);var key:="BMP/FACE%02dA.BMP" % kind
				if _faces.has(key):
					var size:Vector2i=_faces[key];size.y-=16
					for y in range(0,rect.size.y,80):
						out.append({"op":"bitmap","key":"BMP/WALL.BMP","source":Rect2i(0,0,rect.size.x,mini(80,rect.size.y-y)),"pos":rect.position+Vector2i(0,y),"clip":rect,"transparent":-1})
					out.append({"op":"bitmap","key":key,"source":Rect2i(Vector2i.ZERO,size),"pos":rect.position,"clip":rect,"transparent":255,"remaps":[[10,64,144],[74,16,208]],"palette_install":[[144,64],[208,16]]})
			elif style == 11 and id == 1063 and preview_unit.is_valid():
				var miniature: Dictionary = preview_unit.call(slot,rect.position+Vector2i(int(rect.size.x/2),rect.size.y-2))
				if not miniature.is_empty(): out.append(miniature)
			elif caption != "":
				_draw_button(out,rect,caption,(id==default_button) if default_button>=0 else style==1,bool(disabled_controls.get(id,false)),id==focus_control,id==pressed_control)

	return out

func _draw_list(out:Array[Dictionary],resource:int,id:int,rect:Rect2i)->void:
	#The original owner-draw callbacks blit WALL, including blank/sentinel rows.
	#WS_BORDER listboxes receive the Win95 client edge; the row DC starts inside it.
	preload("res://scripts/ui/ft2_native_widgets.gd").edit(out,rect)
	var entries:Array=lists.get(id,[])
	var client:=Rect2i(rect.position+Vector2i(2,2),rect.size-Vector2i(4,4))
	var visible:=maxi(1,int(client.size.y/20))
	var first:=clampi(int(scrolls.get(id,0)),0,maxi(0,entries.size()-visible));scrolls[id]=first
	var scrollbar:bool=(int(_list_styles[id])&0x200000)!=0 and entries.size()>visible
	if scrollbar:
		_scrollbars[id]=preload("res://scripts/ui/ft2_stage_widgets.gd").scrollbar(out,Rect2i(client.end-Vector2i(16,client.size.y),Vector2i(16,client.size.y)),first,visible,entries.size())
		client.size.x-=16
	_list_clients[id]=client
	for i in mini(entries.size()-first,int((client.size.y+19)/20)):
		var index:=i+first;var item:Dictionary=entries[index]
		var point:=client.position+Vector2i(0,i*20)
		var current:bool=index==int(selected.get(id,0)) and id not in [1043,1048]
		var band:=(index&3)*20
		if current and (resource!=119 or id==1032):band+=80
		var begin:=out.size()
		out.append({"op":"bitmap","key":"BMP/WALL.BMP","pos":point,"source":Rect2i(0,band,client.size.x,20),"transparent":-1})
		if id in [1043,1048]:
			_game_text(out,str(item.text),point+Vector2i(20,2))
		elif int(item.get("id",0))>0:
			var item_id:=int(item.id)
			var icon:int
			if resource==121:
				icon=_magic_icon(item_id)
				out.append({"op":"bitmap","key":"BMP/WALL.BMP","pos":point+Vector2i(2,2),"source":Rect2i(icon*16,208,16,16),"transparent":5})
			else:
				icon=_battle.get_ref().rules.item_icon(item_id)
				out.append({"op":"bitmap","key":"BMP/WALL.BMP","pos":point+Vector2i(2,2),"source":Rect2i((icon%20)*16,(14+int(icon/20))*16,16,16),"transparent":5})
			_game_text(out,str(item.get("text","")),point+Vector2i(24 if resource==119 else 20,1))
			if resource==121:
				_game_text(out,"%4d" % absi(numeric.magics.decode_s16(item_id*64+22)),point+Vector2i(196,1))
			elif resource==118:
				_game_text(out,"%2d" % int(item.get("count",0)),point+Vector2i(196,1))
		for n in range(begin,out.size()):out[n]["clip"]=client

func _magic_icon(id:int)->int:
	#41C8F0 ->419C30: first nonzero signed element, negative uses the second icon.
	for i in 3:
		var value:int=numeric.magics.decode_s16(id*64+24+i*2)
		if value!=0:return i*2+(1 if value<0 else 0)
	return -1

func _game_text(out:Array[Dictionary],text:String,pos:Vector2i)->void:
	out.append({"op":"text","text":text.replace("_"," ").replace("*",","),"raw_text":text,"pos":pos,"font":GAME_FONT,"color":16,"decor":{"style":0}})

func _scroll_geometry(id:int)->Dictionary:
	if not _scrollbars.has(id):return {}
	var old:Dictionary=_scrollbars[id]
	return preload("res://scripts/ui/ft2_stage_widgets.gd").scroll_geometry(old.rect,int(scrolls.get(id,0)),int(old.page),lists[id].size())

func _apply_scroll(id:int,events:Array)->void:
	if not lists.has(id):return
	var page:=maxi(1,int(_list_clients[id].size.y/20));var maximum:=maxi(0,lists[id].size()-page)
	for event in events:
		var top:=int(scrolls.get(id,0))
		match int(event.code):
			0:top-=1
			1:top+=1
			2:top-=maxi(1,page-1)
			3:top+=maxi(1,page-1)
			4,5:top=int(event.position)
		scrolls[id]=clampi(top,0,maximum)

func handle_scroll_input(event:InputEvent)->bool:
	_scroll_controller.configure(input_clock_provider,source_double_click_ms)
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if not event.pressed and _scroll_control>=0:
			_apply_scroll(_scroll_control,_scroll_controller.move(Vector2i(event.position),_scroll_geometry(_scroll_control)))
			_apply_scroll(_scroll_control,_scroll_controller.release());_scroll_control=-1;return true
		if event.pressed:
			for id in _scrollbars:
				var geometry:=_scroll_geometry(id)
				if Rect2i(geometry.rect).has_point(Vector2i(event.position)):
					_scroll_control=int(id);focused_list=int(id)
					_apply_scroll(id,_scroll_controller.press(Vector2i(event.position),geometry,int(scrolls.get(id,0))));return true
	if event is InputEventMouseMotion and _scroll_control>=0:
		_apply_scroll(_scroll_control,_scroll_controller.move(Vector2i(event.position),_scroll_geometry(_scroll_control)));return true
	return false

func advance_scroll()->void:
	if _scroll_control>=0:_apply_scroll(_scroll_control,_scroll_controller.advance(_scroll_geometry(_scroll_control)))

func cancel_capture()->void:
	if _scroll_control>=0:_apply_scroll(_scroll_control,_scroll_controller.cancel())
	_scroll_control=-1

func invalidate_magic()->void:
	_magic_rows.clear();_magic_slot=-1

func refresh_child(resource:int)->void:
	if resource==121:return #Native107 refresh never calls121's INITDIALOG.
	cancel_capture();selected.clear();scrolls.clear();_description_control=1032
	invalidate_magic()

func hit(point: Vector2i) -> Dictionary:
	for id in controls:
		var rect: Rect2i = controls[id]
		if rect.has_point(point):
			if lists.has(id):
				if (int(_list_styles.get(id,0))&0x4000)!=0:return {} #LBS_NOSEL headers.
				var client:Rect2i=_list_clients.get(id,rect)
				if not client.has_point(point):return {}
				focused_list=int(id)
				if current_template==119:_description_control=int(id)
				var index := clampi(int(scrolls.get(id,0))+int((point.y-client.position.y)/20),0,maxi(0,lists[id].size()-1))
				selected[id] = index
				return {"control":int(id),"index":index,"item":lists[id][index] if not lists[id].is_empty() else {}}
			return {} if disabled_controls.get(id,false) else {"control":int(id)}
	return {}

func _paragraph(out: Array[Dictionary],text: String,rect: Rect2i,align:int=0) -> void:
	var y := rect.position.y
	for line in text.replace("\r","").split("\n"):
		var wrapped:Array[String]=[line]
		if measure.is_valid():wrapped=preload("res://scripts/ui/ft2_widgets.gd").wrap_lines(line,rect.size.x,func(value):return int(measure.call(value,_font).width))
		for run in wrapped:
			if y>=rect.end.y:return
			_text(out,run,Vector2i(rect.position.x+_align_offset(run,rect.size.x,align),y),0);out[-1]["clip"]=rect
			y+=int(-_font.height)

func _text(out: Array[Dictionary],text: String,pos: Vector2i,color: int) -> void:
	out.append({"op":"text","text":text,"raw_text":text,"pos":pos,"font":_font,"color":color,"decor":{"raw_gdi":true}})

func _align_offset(text:String,width:int,align:int)->int:
	if align==0 or not measure.is_valid():return 0
	var measured:=int(measure.call(text,_font).width)
	return width-measured if align==2 else int((width-measured)/2)

func scroll_at(point:Vector2i,delta:int)->bool:
	for id in lists:
		if controls.has(id) and controls[id].has_point(point) and (int(_list_styles.get(id,0))&0x4000)==0:
			var visible:=maxi(1,int(_list_clients.get(id,controls[id]).size.y/20));scrolls[id]=clampi(int(scrolls.get(id,0))+delta,0,maxi(0,lists[id].size()-visible));return true
	return false
func handle_key(event:InputEventKey)->bool:
	if not lists.has(focused_list):return false
	var id:=focused_list;var count:int=lists[id].size();var index:=int(selected.get(id,0));var visible:=maxi(1,int(_list_clients.get(id,controls[id]).size.y/20))
	match event.keycode:
		KEY_UP:index-=1
		KEY_DOWN:index+=1
		KEY_HOME:index=0
		KEY_END:index=count-1
		KEY_PAGEUP:index-=visible
		KEY_PAGEDOWN:index+=visible
		_:return false
	index=clampi(index,0,maxi(0,count-1));selected[id]=index
	var first:=int(scrolls.get(id,0))
	if index<first:first=index
	if index>=first+visible:first=index-visible+1
	scrolls[id]=maxi(0,first);return true

func _button_caption(out:Array[Dictionary],caption:String,point:Vector2i,color:int)->void:
	var label:=caption.replace("&","");_text(out,label,point,color)
	var prefix:=caption.find("&")
	if prefix>=0 and prefix+1<caption.length() and measure.is_valid():
		var x:=point.x+int(measure.call(caption.substr(0,prefix),_font).width)
		var end:=x+int(measure.call(caption.substr(prefix+1,1),_font).width)-1
		out.append({"op":"line","from":Vector2i(x,point.y-int(_font.height)-2),"to":Vector2i(end,point.y-int(_font.height)-2),"color":color})

func _draw_button(out:Array[Dictionary],rect:Rect2i,caption:String,is_default:bool,disabled:bool,focused:bool,pressed:bool)->void:
	preload("res://scripts/ui/ft2_native_widgets.gd").button(out,rect,is_default,pressed)
	var width:=int(measure.call(caption.replace("&",""),_font).width) if measure.is_valid() else caption.replace("&","").length()*7
	var size:=Vector2i(width,-int(_font.height))
	var point:=rect.position+(rect.size-size)/2+(Vector2i.ONE if pressed else Vector2i.ZERO)
	out.append({"op":"rect","rect":Rect2i(point,size),"filled":true,"color":7})
	if disabled:_button_caption(out,caption,point+Vector2i.ONE,255)
	_button_caption(out,caption,point,248 if disabled else 0)
	if focused:
		var inset:=4 if is_default else 3
		out.append({"op":"focus_rect","rect":Rect2i(rect.position+Vector2i(inset,inset),rect.size-Vector2i(inset*2,inset*2)),"origin":focus_origin})
