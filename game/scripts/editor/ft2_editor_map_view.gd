class_name FT2EditorMapView
extends Control
## Read-only local tile preview. Authoring mutations belong to the editor model.
signal cell_selected(cell: Vector2i)
signal cell_painted(cell: Vector2i)
signal view_info_changed(text: String)
signal zoom_changed(value: float)

var data
var definition:Dictionary={}
var characters:Array=[]
var selected_cell:=Vector2i(2,2):
 set(value):selected_cell=value;queue_redraw()
var tool_mode:="select"
var show_grid:=true:
 set(value):show_grid=value;queue_redraw()
var zoom:=1.0
var hovered_cell:=Vector2i(-1,-1)
var preview_source:="격자 미리보기 · 정품 폴더를 연결하면 원작 타일 표시"
var _pan:=Vector2.ZERO
var _panning:=false
var _painting:=false
var _last_painted:=Vector2i(-1,-1)
var _cells:Array=[]
var _lookup:Dictionary={}
var _atlases:Array=[]
var _textures:Dictionary={}
var _assets
var _ready_fit:=true
var _source_signature:=""
var _floor_texture:Texture2D
var floor_template:Dictionary={}
var _character_textures:Dictionary={}

func _ready()->void:
 clip_contents=true;mouse_filter=Control.MOUSE_FILTER_STOP
 size_flags_horizontal=Control.SIZE_EXPAND_FILL;size_flags_vertical=Control.SIZE_EXPAND_FILL
 custom_minimum_size=Vector2(320,280)
 resized.connect(func():if _ready_fit:zoom_to_fit())
 mouse_exited.connect(func():hovered_cell=Vector2i(-1,-1);_publish_info();queue_redraw())
 if definition.is_empty():set_map({"width":8,"height":8},[])
 else:zoom_to_fit()

func configure(source_data=null)->void:
 data=source_data;_assets=null;_textures.clear();_floor_texture=null;floor_template={};_character_textures.clear();_source_signature=""
 if data!=null and FT2Content.active!=null:_assets=FT2IndexedAssets.new()
 if not definition.is_empty():set_map(definition,characters)

func set_map(value:Dictionary,character_definitions:Array=[])->void:
 var previous_size:=Vector2i(int(definition.get("width",8)),int(definition.get("height",8)))
 definition=value.duplicate(true);characters=character_definitions.duplicate(true)
 var width:=clampi(int(definition.get("width",8)),1,64);var height:=clampi(int(definition.get("height",8)),1,64)
 _cells=[];_lookup={};_atlases=[];floor_template={};_floor_texture=null
 preview_source="격자 미리보기 · 정품 폴더를 연결하면 원작 타일 표시"
 if data!=null and _assets!=null:
  var normalized:Dictionary=FT2ExtensionMaps.normalized(data,definition,2147483000)
  if not normalized.is_empty():
   _cells=normalized.cells;_atlases=normalized.atlas_names
   floor_template=normalized.get("floor_template",{})
   _floor_texture=_rgba_texture(floor_template) if not floor_template.is_empty() else null
   preview_source="정품 배경 바닥 참조 · 기본 지도 %s"%str(definition.get("base_map",40)) if _floor_texture!=null else "정품 타일 참조 · 바닥 그림이 없으면 격자로 표시"
 var edits:Dictionary={}
 for row in definition.get("cells",[]):
  if row is Dictionary:edits[Vector2i(int(row.get("x",0)),int(row.get("y",0)))]=row
 if _cells.is_empty():
  for y in range(1,height+1):
   for x in range(1,width+1):
    var edit:Dictionary=edits.get(Vector2i(x,y),{})
    _cells.append({"x":x,"y":y,"H":int(edit.get("height",0)),"L":int(edit.get("terrain",1)),"parts":[]})
 _cells.sort_custom(func(a,b):return int(a.x)+int(a.y)<int(b.x)+int(b.y) if int(a.x)+int(a.y)!=int(b.x)+int(b.y) else int(a.x)<int(b.x))
 for cell in _cells:_lookup[Vector2i(int(cell.x),int(cell.y))]=cell
 selected_cell=Vector2i(clampi(selected_cell.x,1,width),clampi(selected_cell.y,1,height))
 if previous_size!=Vector2i(width,height):_ready_fit=true
 if is_inside_tree() and _ready_fit:zoom_to_fit()
 queue_redraw();_publish_info()

func _center(cell:Dictionary)->Vector2:
 return Vector2((int(cell.x)-int(cell.y))*32,(int(cell.x)+int(cell.y))*16-int(cell.get("H",0))*8)
func _diamond(center:Vector2)->PackedVector2Array:
 return PackedVector2Array([center+Vector2(-32,0),center+Vector2(0,-16),center+Vector2(32,0),center+Vector2(0,16)])
func _world_bounds()->Rect2:
 var bounds:=Rect2(Vector2.ZERO,Vector2.ONE)
 var first:=true
 for cell in _cells:
  var rect:=Rect2(_center(cell)-Vector2(40,64),Vector2(80,96))
  bounds=rect if first else bounds.merge(rect);first=false
 return bounds
func _offset()->Vector2:return size/2.0+_pan-_world_bounds().get_center()*zoom
func cell_to_screen(cell:Vector2i)->Vector2:
 return _offset()+_center(_lookup.get(cell,{"x":cell.x,"y":cell.y}))*zoom
func screen_to_cell(point:Vector2)->Vector2i:
 var world:Vector2=(point-_offset())/zoom
 for index in range(_cells.size()-1,-1,-1):
  var cell:Dictionary=_cells[index];var center:=_center(cell);var distance:=world-center
  if absf(distance.x)/32.0+absf(distance.y)/16.0<=1.0:return Vector2i(int(cell.x),int(cell.y))
 return Vector2i(-1,-1)
func zoom_to_fit()->void:
 if size.x<1 or size.y<1:return
 var bounds:=_world_bounds();zoom=clampf(minf((size.x-72)/bounds.size.x,(size.y-92)/bounds.size.y),0.15,4.0)
 _pan=Vector2.ZERO;_ready_fit=true;queue_redraw();zoom_changed.emit(zoom);_publish_info()
func center_view()->void:_pan=Vector2.ZERO;queue_redraw();_publish_info()
func set_zoom(value:float)->void:
 zoom=clampf(value,0.15,4.0);_ready_fit=false;queue_redraw();zoom_changed.emit(zoom);_publish_info()
func zoom_in()->void:set_zoom(zoom*1.2)
func zoom_out()->void:set_zoom(zoom/1.2)
func get_view_info()->String:
 var position:="셀 위에 마우스를 올리세요"
 if _lookup.has(hovered_cell):
  var cell:Dictionary=_lookup[hovered_cell]
  position="X %d  Y %d  · 높이 %d  · 지형 %d"%[hovered_cell.x,hovered_cell.y,int(cell.get("H",0)),int(cell.get("L",1))]
 return "%s  |  %d%%  |  %s"%[position,roundi(zoom*100),preview_source]
func _publish_info()->void:view_info_changed.emit(get_view_info())
func _paint(cell:Vector2i)->void:
 if cell.x<1 or cell==_last_painted:return
 _last_painted=cell;selected_cell=cell;cell_selected.emit(cell)
 if tool_mode!="select":cell_painted.emit(cell)
func _gui_input(event:InputEvent)->void:
 if event is InputEventMouseButton:
  if event.button_index==MOUSE_BUTTON_MIDDLE:
   _panning=event.pressed;accept_event()
  elif event.button_index==MOUSE_BUTTON_LEFT:
   _painting=event.pressed
   if event.pressed:_last_painted=Vector2i(-1,-1);_paint(screen_to_cell(event.position))
   else:_last_painted=Vector2i(-1,-1)
   accept_event()
  elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
   var before:Vector2=(event.position-_offset())/zoom
   set_zoom(zoom*(1.15 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.15))
   _pan+=event.position-(_offset()+before*zoom);queue_redraw();accept_event()
 elif event is InputEventMouseMotion:
  if _panning:_pan+=event.relative;_ready_fit=false;queue_redraw();accept_event()
  hovered_cell=screen_to_cell(event.position)
  if _painting and not _panning:_paint(hovered_cell)
  _publish_info();queue_redraw()

func _atlas_texture(index:int)->Texture2D:
 if index<0 or index>=_atlases.size() or _assets==null:return null
 var key:="map/"+str(_atlases[index]).to_lower()
 if _textures.has(key):return _textures[key]
 var image:Dictionary=_assets.image(key,[[10,112,32]])
 if image.is_empty():_textures[key]=null;return null
 var pixels:PackedByteArray=image.pixels;var palette:PackedByteArray=image.palette
 var rgba:=PackedByteArray();rgba.resize(pixels.size()*4)
 for i in range(pixels.size()):
  var color:=int(pixels[i]);var target:=i*4;var source:=color*3
  if source+2<palette.size():rgba[target]=palette[source];rgba[target+1]=palette[source+1];rgba[target+2]=palette[source+2]
  rgba[target+3]=0 if color==int(image.map_key) else 255
 var texture:=ImageTexture.create_from_image(Image.create_from_data(int(image.width),int(image.height),false,Image.FORMAT_RGBA8,rgba))
 _textures[key]=texture;return texture
func _draw()->void:
 draw_rect(Rect2(Vector2.ZERO,size),Color("121b27"))
 if _cells.is_empty():return
 draw_set_transform(_offset(),0,Vector2.ONE*zoom)
 for cell in _cells:
  var center:=_center(cell);var points:=_diamond(center);var terrain:=int(cell.get("L",1))
  draw_colored_polygon(points,Color("263c47") if terrain==1 else Color("314e53").lightened(float(posmod(terrain,6))*0.025))
  if _floor_texture!=null:draw_texture_rect(_floor_texture,Rect2(center-Vector2(32,16),Vector2(64,32)),false)
  for part in cell.get("parts",[]):
   var texture:=_atlas_texture(int(part.atlas_index))
   if texture==null:continue
   var r:Array=part.source_rect_xyxy;var region:=Rect2(float(r[0]),float(r[1]),float(r[2])-float(r[0]),float(r[3])-float(r[1]))
   draw_texture_rect_region(texture,Rect2(center+Vector2(float(part.offset_xy[0]),float(part.offset_xy[1])),region.size),region)
  if show_grid:
   var outline:=PackedVector2Array(points);outline.append(points[0]);draw_polyline(outline,Color(0.55,0.73,0.81,0.42),1.0/zoom,true)
 for placement in definition.get("placements",[]):
  var position:=Vector2i(int(placement.get("x",0)),int(placement.get("y",0)))
  if not _lookup.has(position):continue
  var center:=_center(_lookup[position]);var color:=Color("68c4ff") if str(placement.get("side","ally"))=="ally" else Color("ff887e")
  draw_line(center,center+Vector2(0,-22),Color("121b27"),5.0)
  draw_circle(center+Vector2(0,-23),9.0,color)
  draw_arc(center+Vector2(0,-23),10.0,0,TAU,20,Color("eff7ff"),1.2,true)
  if zoom>=0.5:
   var label:=str(placement.get("character","?"));label=label.get_slice(":",label.get_slice_count(":")-1)
   for character in characters:
    if str(character.get("id",""))==label:label=str(character.get("name",label));break
   draw_string(ThemeDB.fallback_font,center+Vector2(13,-18),label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)
 for coordinate in [hovered_cell,selected_cell]:
  if not _lookup.has(coordinate):continue
  var points:=_diamond(_center(_lookup[coordinate]));var outline:=PackedVector2Array(points);outline.append(points[0])
  if coordinate==hovered_cell:draw_colored_polygon(points,Color(0.7,0.9,1,0.14))
  draw_polyline(outline,Color("ffce72") if coordinate==selected_cell else Color("a5e7ff"),2.5/zoom,true)
 draw_set_transform(Vector2.ZERO)
 draw_string(ThemeDB.fallback_font,Vector2(15,24),"지도 작업 화면",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("dceaf4"))
 draw_string(ThemeDB.fallback_font,Vector2(15,size.y-15),"휠: 확대/축소   ·   가운데 버튼: 이동   ·   왼쪽 드래그: 선택한 도구",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("93a8b9"))
func character_texture(stem:String)->Texture2D:
 # First nonempty APD frame, with its complete part composition. Local display only.
 if _assets==null:return null
 stem=stem.get_file().get_basename().to_upper()
 if _character_textures.has(stem):return _character_textures[stem]
 var source:Dictionary=_assets.apd(stem)
 if source.is_empty():_character_textures[stem]=null;return null
 var apd:Dictionary=FT2APDPlayer.normalize(source)
 var parts:Array=apd.get("parts",[]);var frames:Array=apd.get("frames",[]);var sheets:Array=apd.get("sheets",[])
 for frame in frames:
  var indices:Array=frame.get("parts",[])
  if indices.is_empty():continue
  var bounds:=Rect2i();var first:=true
  for index in indices:
   if int(index)<0 or int(index)>=parts.size():continue
   var part:Array=parts[int(index)];var rect:=Rect2i(int(part[5]),int(part[6]),int(part[3]),int(part[4]))
   if rect.size.x<1 or rect.size.y<1:continue
   bounds=rect if first else bounds.merge(rect);first=false
  if first or bounds.size.x>1024 or bounds.size.y>1024:continue
  var image:=Image.create(bounds.size.x,bounds.size.y,false,Image.FORMAT_RGBA8);image.fill(Color.TRANSPARENT)
  var drawn:=false
  for index in indices:
   if int(index)<0 or int(index)>=parts.size():continue
   var part:Array=parts[int(index)];var sheet:=int(part[0])
   if sheet<0 or sheet>=sheets.size():continue
   var raw:Dictionary=_assets.apd_image(str(sheets[sheet]))
   if raw.is_empty():continue
   var pixels:PackedByteArray=raw.pixels;var palette:PackedByteArray=raw.palette
   for y in range(int(part[4])):
    for x in range(int(part[3])):
     var sx:=int(part[1])+x;var sy:=int(part[2])+y
     if sx<0 or sy<0 or sx>=int(raw.width) or sy>=int(raw.height):continue
     var color:=int(pixels[sy*int(raw.width)+sx]);var p:=color*3
     if color==int(part[7]) or p+2>=palette.size():continue
     image.set_pixel(int(part[5])-bounds.position.x+x,int(part[6])-bounds.position.y+y,Color8(palette[p],palette[p+1],palette[p+2],255));drawn=true
  if drawn:
   var texture:=ImageTexture.create_from_image(image);_character_textures[stem]=texture;return texture
 _character_textures[stem]=null;return null
func _rgba_texture(raw:Dictionary)->Texture2D:
 if raw.is_empty():return null
 var pixels:PackedByteArray=raw.pixels;var palette:PackedByteArray=raw.palette
 var rgba:=PackedByteArray();rgba.resize(pixels.size()*4)
 for i in range(pixels.size()):
  var color:=int(pixels[i]);var target:=i*4;var source:=color*3
  if source+2<palette.size():rgba[target]=palette[source];rgba[target+1]=palette[source+1];rgba[target+2]=palette[source+2]
  rgba[target+3]=0 if color==int(raw.map_key) else 255
 return ImageTexture.create_from_image(Image.create_from_data(int(raw.width),int(raw.height),false,Image.FORMAT_RGBA8,rgba))