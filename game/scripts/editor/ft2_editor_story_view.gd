class_name FT2EditorStoryView
extends Control
## Declarative story flow overview; selection is routed to the editor forms.
signal node_selected(index: int)
var definition:Dictionary={}
var selected_node:=0:
 set(value):selected_node=value;queue_redraw()
var zoom:=1.0
var _pan:=Vector2.ZERO
var _panning:=false
var _rects:Array[Rect2]=[]
var _indices:Dictionary={}
const CARD:=Vector2(218,94)
func _ready()->void:
 clip_contents=true;mouse_filter=Control.MOUSE_FILTER_STOP
 size_flags_horizontal=Control.SIZE_EXPAND_FILL;size_flags_vertical=Control.SIZE_EXPAND_FILL
 custom_minimum_size=Vector2(320,280)
 resized.connect(fit_view)
func set_story(value:Dictionary)->void:
 definition=value.duplicate(true);_rects.clear();_indices.clear()
 var nodes:Array=definition.get("nodes",[])
 for index in range(nodes.size()):
  _indices[str(nodes[index].get("id",""))]=index
  _rects.append(Rect2(Vector2(index%3*284,index/3*154),CARD))
 if is_inside_tree():fit_view()
 queue_redraw()
func _bounds()->Rect2:
 return Rect2(Vector2.ZERO,Vector2(mini(3,maxi(1,_rects.size()))*284-66,maxi(1,ceili(_rects.size()/3.0))*154-60))
func _offset()->Vector2:return size/2+_pan-_bounds().get_center()*zoom
func fit_view()->void:
 if size.x<1 or size.y<1:return
 var bounds:=_bounds();zoom=clampf(minf((size.x-64)/bounds.size.x,(size.y-90)/bounds.size.y),0.3,1.2);_pan=Vector2.ZERO;queue_redraw()
func zoom_in()->void:zoom=clampf(zoom*1.2,0.3,2.5);queue_redraw()
func zoom_out()->void:zoom=clampf(zoom/1.2,0.3,2.5);queue_redraw()
func node_screen_center(index:int)->Vector2:
 return _offset()+_rects[index].get_center()*zoom if index>=0 and index<_rects.size() else Vector2(-1,-1)
func _gui_input(event:InputEvent)->void:
 if event is InputEventMouseButton:
  if event.button_index==MOUSE_BUTTON_MIDDLE:_panning=event.pressed;accept_event()
  elif event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
   var point:Vector2=(event.position-_offset())/zoom
   for index in range(_rects.size()):
    if _rects[index].has_point(point):selected_node=index;node_selected.emit(index);break
   accept_event()
  elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
   if event.button_index==MOUSE_BUTTON_WHEEL_UP:zoom_in()
   else:zoom_out()
   accept_event()
 elif event is InputEventMouseMotion and _panning:_pan+=event.relative;queue_redraw();accept_event()
func _targets(node:Dictionary)->Array:
 var result:Array=[]
 for field in ["next","on_defeat","then","else"]:
  if node.has(field):result.append(str(node[field]))
 for choice in node.get("choices",[]):
  if choice is Dictionary:result.append(str(choice.get("next","")))
 return result
func _draw()->void:
 draw_rect(Rect2(Vector2.ZERO,size),Color("121b27"))
 draw_set_transform(_offset(),0,Vector2.ONE*zoom)
 var nodes:Array=definition.get("nodes",[])
 for index in range(nodes.size()):
  for target in _targets(nodes[index]):
   if not _indices.has(target):continue
   var from:Vector2=_rects[index].position+Vector2(CARD.x,CARD.y/2);var to:Vector2=_rects[int(_indices[target])].position+Vector2(0,CARD.y/2)
   var points:=PackedVector2Array([from,from+Vector2(26,0),to-Vector2(26,0),to])
   draw_polyline(points,Color("557990"),2.0,true)
   draw_colored_polygon(PackedVector2Array([to,to+Vector2(-8,-5),to+Vector2(-8,5)]),Color("7fa9c4"))
 for index in range(nodes.size()):
  var node:Dictionary=nodes[index];var rect:Rect2=_rects[index];var kind:=str(node.get("type","dialogue"))
  var color:=Color("263e56")
  if kind=="battle":color=Color("5a3a3a")
  elif kind=="branch":color=Color("54452a")
  elif kind=="end":color=Color("2a4b3f")
  draw_style_box(_card_style(color,index==selected_node),rect)
  var entry:="  시작" if str(node.get("id",""))==str(definition.get("start","")) else ""
  draw_string(ThemeDB.fallback_font,rect.position+Vector2(12,23),str(node.get("id",""))+entry,HORIZONTAL_ALIGNMENT_LEFT,CARD.x-24,15,Color("f2f5fa"))
  draw_string(ThemeDB.fallback_font,rect.position+Vector2(12,45),kind.to_upper(),HORIZONTAL_ALIGNMENT_LEFT,CARD.x-24,11,Color("94bad3"))
  var caption:=str(node.get("text",node.get("map",node.get("variable","")))).replace("\n"," ")
  if caption.length()>25:caption=caption.left(24)+"…"
  draw_string(ThemeDB.fallback_font,rect.position+Vector2(12,72),caption,HORIZONTAL_ALIGNMENT_LEFT,CARD.x-24,12,Color("d0dce5"))
 draw_set_transform(Vector2.ZERO)
 draw_string(ThemeDB.fallback_font,Vector2(15,24),"이야기 흐름 · 카드를 선택하면 내용을 편집합니다",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("dceaf4"))
 if nodes.is_empty():draw_string(ThemeDB.fallback_font,size/2+Vector2(-90,0),"이야기 장면을 추가하세요",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("93a8b9"))
func _card_style(color:Color,selected:bool)->StyleBoxFlat:
 var style:=StyleBoxFlat.new();style.bg_color=color;style.border_color=Color("ffce72") if selected else Color("476078")
 style.set_border_width_all(2 if selected else 1);style.set_corner_radius_all(7);return style