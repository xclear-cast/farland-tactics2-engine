extends SceneTree
## Self-authored responsive UI checks. No original installation or cache input.
var checks:=0
var failures:Array[String]=[]
var observations:Array=[]
var output:=""
var capture:=false
var editor
class SetupWithoutStartup:
 extends "res://scripts/content/ft2_content_setup.gd"
 func _ready()->void:_build_ui()
func _initialize()->void:
 for argument in OS.get_cmdline_user_args():
  if argument.begins_with("--scaling-output="):output=argument.trim_prefix("--scaling-output=")
  elif argument=="--scaling-capture":capture=true
 call_deferred("run")
func check(value:bool,label:String)->void:
 checks+=1
 if not value:failures.append(label)
func settle()->void:
 for unused in range(5):await process_frame
 await create_timer(0.08).timeout
func pixel_rect(control:Control)->Rect2:
 return control.get_viewport().get_stretch_transform()*control.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,control.size)
func choose(index:int)->void:
 editor._ui_scale_option.select(index);editor._ui_scale_option.item_selected.emit(index);await settle()
func measure(label:String)->Dictionary:
 var toolbar:Rect2=pixel_rect(editor.buttons.new);var hp:Rect2=pixel_rect(editor.fields["character.hp.initial"])
 var record:Dictionary={"label":label,"window":[root.size.x,root.size.y],"logical":[root.content_scale_size.x,root.content_scale_size.y],"percent":editor.ui_scale_percent(),"toolbar_pixels":[toolbar.position.x,toolbar.position.y,toolbar.size.x,toolbar.size.y],"hp_pixels":[hp.position.x,hp.position.y,hp.size.x,hp.size.y],"transform_scale":[editor.get_viewport().get_stretch_transform().get_scale().x,editor.get_viewport().get_stretch_transform().get_scale().y]}
 observations.append(record)
 var right:Rect2=pixel_rect(editor.buttons.close)
 check(right.end.x<=float(root.size.x)+2.0,"toolbar remains inside the window at "+label)
 if capture and DisplayServer.get_name()!="headless":root.get_texture().get_image().save_png(output.path_join(label+".png"))
 return record
func run()->void:
 if output.is_empty():printerr("Explicit private --scaling-output directory required");quit(2);return
 DirAccess.make_dir_recursive_absolute(output)
 root.mode=Window.MODE_WINDOWED;root.min_size=Vector2i(640,480);root.position=Vector2i(0,0);root.size=Vector2i(1280,840)
 editor=load("res://scripts/editor/ft2_expansion_editor.gd").new();root.add_child(editor);editor.configure(null);await settle()
 check(editor._ui_scale_option.item_count==6,"auto plus five manual scale options")
 check(root.content_scale_mode==Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,"canvas-items scaling active")
 check(root.content_scale_aspect==Window.CONTENT_SCALE_ASPECT_EXPAND,"viewport expands without fixed letterbox")
 await choose(0)
 var sizes:Array[Vector2i]=[Vector2i(1280,840),Vector2i(1920,1080),Vector2i(2560,1440)]
 var rows:Array=[]
 for index in range(sizes.size()):
  root.size=sizes[index];await settle()
  var record:Dictionary=measure("auto-%dx%d"%[sizes[index].x,sizes[index].y]);rows.append(record)
  check(root.size==sizes[index],"own window resized to "+str(sizes[index]))
  check(float(record.toolbar_pixels[3])>20 and float(record.hp_pixels[3])>20,"toolbar and HP have usable screen height")
  check(root.content_scale_size.x>=1120 and root.content_scale_size.y>=720,"automatic scale preserves minimum layout")
  if index>0:
   check(float(record.toolbar_pixels[3])>float(rows[index-1].toolbar_pixels[3])*1.15,"larger window visibly enlarges toolbar")
   check(float(record.hp_pixels[3])>float(rows[index-1].hp_pixels[3])*1.15,"larger window visibly enlarges HP field")
 check(float(rows[2].toolbar_pixels[3])>float(rows[0].toolbar_pixels[3])*1.6,"1440p toolbar substantially larger than baseline")
 check(float(rows[2].hp_pixels[3])>float(rows[0].hp_pixels[3])*1.6,"1440p HP substantially larger than baseline")
 await choose(1);var manual:Dictionary=measure("manual-100")
 check(absf(editor.ui_scale_percent()-100.0)<1.0,"manual100 percent selected")
 check(absf(float(manual.hp_pixels[3])-float(rows[0].hp_pixels[3]))<2.0,"manual100 retains baseline actual HP size")
 root.size=Vector2i(1920,1080);await settle();await choose(2)
 check(absf(editor.ui_scale_percent()-125.0)<1.0,"manual125 percent applied when room available")
 var manual125:Dictionary=measure("manual-125")
 check(float(manual125.toolbar_pixels[3])>float(rows[0].toolbar_pixels[3])*1.2,"manual125 visibly enlarges toolbar")
 await choose(5);var clamped:Dictionary=measure("manual-200-clamped")
 check(editor.ui_scale_percent()<200.0 and editor.ui_scale_percent()>=100.0,"manual200 is clamped for1080p layout")
 check(root.content_scale_size.x>=1120 and root.content_scale_size.y>=720,"clamped manual keeps minimum layout visible")
 root.size=Vector2i(2560,1440);await settle();await choose(5)
 check(absf(editor.ui_scale_percent()-200.0)<1.0,"manual200 applies at1440p")
 var manual200:Dictionary=measure("manual-200")
 check(float(manual200.hp_pixels[3])>float(rows[0].hp_pixels[3])*1.9,"manual200 doubles actual HP field height")
 root.size=Vector2i(1280,840);await settle();await choose(5)
 check(editor.ui_scale_percent()<125.0,"small window200 request clamps to readable fitting scale")
 check(root.content_scale_size.x>=1120 and root.content_scale_size.y>=720,"small window clamp preserves inspector layout")
 await choose(0)
 check(absf(editor.ui_scale_percent()-100.0)<1.0,"automatic scale restored at baseline size")
 if DisplayServer.get_name()!="headless":
  var previous_size:Vector2i=root.size;var previous_mode:int=root.mode
  editor._toggle_fullscreen();await settle()
  check(root.mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN],"own isolated window enters fullscreen")
  var full:Dictionary=measure("fullscreen-auto")
  full["geometry_expanded"]=root.size!=previous_size # Bare Xvfb has no window manager to honor fullscreen geometry.
  editor._toggle_fullscreen();await settle()
  check(root.mode==previous_mode and root.size==previous_size,"fullscreen toggle restores own window mode and size")
 editor.queue_free();await settle()
 root.min_size=Vector2i(640,480);root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1024,768)
 root.content_scale_size=Vector2i(800,600);root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS;root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP_HEIGHT;root.content_scale_factor=1.25
 var previous:Dictionary={"size":root.size,"min_size":root.min_size,"scale_size":root.content_scale_size,"scale_mode":root.content_scale_mode,"aspect":root.content_scale_aspect,"factor":root.content_scale_factor,"window_mode":root.mode}
 var setup=SetupWithoutStartup.new();setup.config_path=output.path_join("unused-connection.json");root.add_child(setup);await settle()
 setup.source_field.text="";setup.cache_field.text="";setup._open_editor();await settle()
 check(is_instance_valid(setup._editor),"setup opens standalone synthetic editor")
 setup._close_editor();await settle()
 check(root.size==previous.size and root.min_size==previous.min_size,"closing editor restores setup window dimensions")
 check(root.content_scale_size==previous.scale_size and root.content_scale_mode==previous.scale_mode,"closing editor restores logical scale size and mode")
 check(root.content_scale_aspect==previous.aspect and is_equal_approx(root.content_scale_factor,previous.factor),"closing editor restores aspect and scale factor")
 check(root.mode==previous.window_mode,"closing editor restores window mode")
 setup.queue_free();await process_frame
 var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"observations":observations,"synthetic_only":true,"original_data_used":false,"host_user_window_used":false,"fullscreen_mode_gpu_checked":DisplayServer.get_name()!="headless","fullscreen_geometry_tested":false,"fullscreen_environment_limit":"Bare owned Xvfb checks mode and windowed-size restoration;1920/2560 resize captures verify actual pixel growth. User Windows fullscreen geometry is a separate manual check."}
 var file=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close();print("FT2_EDITOR_SCALING ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
