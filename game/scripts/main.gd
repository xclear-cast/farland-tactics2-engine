extends Node2D
## The original50ms frame pump, with indexed presentation and authoritative binary units.
const Store = preload("res://scripts/data/ft2_data.gd")
const Combat = preload("res://scripts/logic/ft2_battle.gd")
const View = preload("res://scripts/render/ft2_battle_view.gd")
const Scenario = preload("res://scripts/scenario/ft2_vm.gd")
const Interface = preload("res://scripts/ui/ft2_interface.gd")
const Sound = preload("res://scripts/audio/ft2_audio.gd")
const Overview = preload("res://scripts/overview/ft2_overview.gd")
const ExperienceMeter = preload("res://scripts/experience_meter/ft2_experience_meter.gd")
const PublicAutoplay = preload("res://scripts/autoplay/ft2_public_autoplay.gd")
const UnitWindowHost = preload("res://scripts/window/ft2_unit_window_host.gd")
const CursorHost = preload("res://scripts/input/ft2_cursor_host.gd")
const Startup = preload("res://scripts/scenario/ft2_startup.gd")
const ExitRequest = preload("res://scripts/input/ft2_exit_request.gd")
const DisplayProfile = preload("res://scripts/input/ft2_display_profile.gd")
const LaunchOptions = preload("res://scripts/startup/ft2_launch_options_ui.gd")
const LaunchModel = preload("res://scripts/startup/ft2_launch_options.gd")
const ExtensionCampaign = preload("res://scripts/extensions/ft2_campaign_runner.gd")
var data
var battle
var view
var vm
var ui
var audio
var overview
var unit_window_host
var cursor_host
var startup
var exit_request
var launch_options
var display_profile
var campaign
var source_display_adapter:Dictionary={"drive_type":3,"non8bit":0} # Portable fixed-disk / virtual indexed-display profile.
var _display_restore_pending:=false
var _launch_display_pending:=false
var _launch_fullscreen_requested:=true
var _display_generation:=0
var _fullscreen_fallback_active:=false
var _windowed_rect:=Rect2i()
var _windowed_borderless:=false
var _close_base_overlay:Array=[]
var _original_auto_accept_quit:=true
var _startup_modifier_sampled := false
var _startup_modifier_mask := -1
var _startup_modifier_source := "not_sampled"
var _cursor_inside = false
var _cursor_capture_pending = false
var _cursor_capture_token = false
var experience_meter = ExperienceMeter.new()
var _autoplay
var _initial_event = -1
var _automation_end_reason = "duration"
var _diagnostics_enabled = false
var _events_dropped = 0
var frame_number := 0
var elapsed_ms := 0
var mouse_cell := Vector2i.ZERO
var events: Array = []
var errors: Array = []
var _automation: Dictionary = {}
var _steps: Array = []
var _step_index := 0
var _output := ""
var _capture_queue: Array[String] = []
var _completing := false
var _finishing := false
var _pause := false
var _step_once := false
var _start_usec := 0
var facing_choice := 4
var _last_service_ms := 0
var _ctrl_held := false
var _shift_held := false
var _dragging := false
var _drag_last := Vector2i.ZERO
var _pointer := Vector2i.ZERO
var _next_party_slot := 0

func _record_event(event: Dictionary) -> void:
	# Full state traces belong to explicit development runs, not ordinary play.
	if _automation.is_empty() and not _diagnostics_enabled: return
	if events.size() >= 200000:
		events = events.slice(100000)
		_events_dropped += 100000
	events.append(event)

func _notification(what:int)->void:
	# Root-window OS requests are propagated as a Node notification. Keeping
	# the Window signal as well supports either delivery path; request is idempotent.
	if what==NOTIFICATION_WM_CLOSE_REQUEST:_window_close_requested()

func _ready() -> void:
	_start_usec = Time.get_ticks_usec()
	_pointer = Vector2i(get_viewport().get_mouse_position())
	print("FT2_STARTUP ",OS.get_cmdline_user_args())
	# The20fps cap belonged to reference capture, not the shipped animation clock.
	# NUMBER contains30ms steps and the EXP meter has a20ms gate.
	Engine.max_fps = 60
	data = Store.new()
	battle = Combat.new(data)
	view = View.new(); add_child(view); view.configure(data); view.set_battle(battle)
	vm = Scenario.new(data,battle)
	battle.navigation.set_game_mode_owner(vm) #4499BC is live scenario mode, not Town/control data.
	ui = Interface.new(); ui.configure(data,battle,vm)
	ui.experience.palette_scope_requested.connect(view.set_experience_palette_scope)
	exit_request=ExitRequest.new();exit_request.configure(data,battle,vm)
	exit_request.accepted.connect(_quit_game)
	exit_request.cancelled.connect(_restore_after_close_request)
	_original_auto_accept_quit=get_tree().auto_accept_quit
	get_tree().auto_accept_quit=false
	get_window().close_requested.connect(_window_close_requested)
	if ui.has_signal("exit_confirmation_requested"):ui.connect("exit_confirmation_requested",_window_close_requested)
	get_window().focus_entered.connect(func(): _window_focus(true))
	get_window().focus_exited.connect(func(): _window_focus(false))
	if DisplayServer.get_name() != "headless": vm.active_window = get_window().has_focus()
	audio = Sound.new(); add_child(audio); audio.configure(data)
	audio.apply_settings(ui.settings)
	battle.apply_settings(ui.settings)
	view.apply_settings(ui.settings)
	overview = Overview.new(); overview.external_cursor_owner = true
	add_child(overview); overview.configure(data,battle,view)
	overview.cursor_provider = func(): return _pointer
	overview.mode_requested.connect(func(mode): vm.mode = mode)
	overview.camera_requested.connect(_overview_camera)
	overview.command_forwarded.connect(ui.command)
	overview.unsupported.connect(func(details): errors.append({"overview":details}))
	ui.overview_requested.connect(func(): overview.handle_command(40030))
	vm.overview_visibility = Callable(overview,"show_previous_visibility")
	view.set_audio_backend(audio)
	view.sound_requested.connect(audio.play_sound)
	battle.sound_requested.connect(audio.play_sound)
	view.sound_stop_requested.connect(audio.stop_sound)
	ui.preview_unit = Callable(view,"unit_preview")
	battle.frame_service_callback = _nested_frame_service
	vm.measure_text = Callable(view,"measure_text")
	vm.actor_player_query = Callable(view,"unit_player")
	vm.actor_appearance_refresh = Callable(self,"_source_appearance_refresh")
	vm.actor_busy_query = Callable(view,"script_actor_busy")
	vm.palette_busy_query = func() -> bool: return view.palette.progress != 128
	vm.actor_restore_requested.connect(view.restore_script_actor)
	battle.visual_requested.connect(_visual_requested)
	battle.actor_visuals_requested.connect(_actor_visuals_requested)
	battle.experience_presented.connect(_experience_presented)
	battle.interaction_requested.connect(_interaction_requested)
	battle.modal_requested.connect(func(request): _record_event({"frame":frame_number,"kind":"battle_modal","request":_plain(request)}))
	battle.camera_requested.connect(view.request_camera)
	view.visual_finished.connect(battle.finish_visual)
	view.actor_finished.connect(vm.actor_finished)
	view.camera_finished.connect(func(): vm.camera_busy = false)
	vm.map_requested.connect(_set_map)
	vm.camera_requested.connect(_camera_requested)
	vm.palette_requested.connect(_palette_requested)
	vm.actor_changed.connect(_script_state)
	vm.music_requested.connect(audio.play_music)
	vm.source_commands_requested.connect(view.service_script_commands)
	vm.main_service_requested.connect(audio.source_main_service)
	vm.music_fade_requested.connect(audio.fade_music)
	vm.music_busy_query = Callable(audio,"music_fade_busy")
	vm.sound_requested.connect(audio.play_sound)
	vm.sound_stop_requested.connect(audio.stop_sound)
	ui.settings_changed.connect(audio.apply_settings)
	ui.settings_changed.connect(battle.apply_settings)
	ui.settings_changed.connect(view.apply_settings)
	ui.load_requested.connect(_load_save)
	ui.save_requested.connect(_save_game)
	ui.new_game_requested.connect(_new_game)
	ui.quit_requested.connect(_quit_game)
	ui.fullscreen_requested.connect(_toggle_fullscreen)
	ui.cursor_refresh_requested.connect(_cursor_refresh)
	ui.music_index_provider = func(): return audio.current_index
	ui.main_service_requested.connect(audio.source_main_service)
	ui.message_presentation_requested.connect(view.service_message_presentation)
	unit_window_host = UnitWindowHost.new(); add_child(unit_window_host)
	unit_window_host.configure(data,ui,view)
	unit_window_host.forwarded_input.connect(_input)
	vm.unit_window_visibility = Callable(ui,"service_unit_window_visibility")
	cursor_host = CursorHost.new(); add_child(cursor_host); cursor_host.configure(data,get_viewport())
	cursor_host.set_application_enabled(DisplayServer.get_name() != "headless")
	ui.message_wait_requested.connect(func(op,request): cursor_host.message_wait(op,request,elapsed_ms))
	vm.input_wait_requested.connect(func(op,request): cursor_host.event_wait(op,request,elapsed_ms))
	overview.cursor_changed.connect(cursor_host.request_resource)
	vm.finished.connect(_cursor_after_script)
	startup = Startup.new()
	startup.stage_selection_requested.connect(ui.open_stage_select)
	ui.stage_selection_finished.connect(startup.resolve_stage_selection)
	startup.money_add_requested.connect(battle.add_money)
	startup.ready.connect(_startup_ready)
	startup.aborted.connect(_quit_game)
	display_profile=DisplayProfile.new();display_profile.configure(true,false,0)
	display_profile.lifecycle_requested.connect(_display_lifecycle)
	launch_options=LaunchOptions.new();launch_options.configure(data,battle,vm,LaunchModel)
	launch_options.completed.connect(_launch_completed)
	_cursor_inside = get_viewport().get_visible_rect().has_point(get_viewport().get_mouse_position())
	get_window().mouse_entered.connect(func(): _cursor_inside = true)
	get_window().mouse_exited.connect(func(): _cursor_inside = false)
	battle.phase_changed.connect(func(phase): _record_event({"frame":frame_number,"phase":phase}))
	battle.unsupported_action.connect(func(details): errors.append({"frame":frame_number,"unsupported_action":details}))
	campaign=ExtensionCampaign.new();add_child(campaign);campaign.configure(data,battle,vm,view,ui)
	campaign.quit_requested.connect(_quit_game)
	campaign.finished.connect(func(result):_record_event({"frame":frame_number,"kind":"extension_finished","result":result}))
	# Keep one dispatcher so expansion combat never tries original EVENT-1 hooks.
	if battle.hook_requested.is_connected(Callable(vm,"_on_hook")):battle.hook_requested.disconnect(Callable(vm,"_on_hook"))
	battle.hook_requested.connect(_battle_hook_requested)
	var initial := -1
	var source_windowed := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): initial = int(arg.trim_prefix("--save="))
		elif arg.begins_with("--automation="):
			var path := arg.trim_prefix("--automation=")
			_automation = JSON.parse_string(FT2Content.text(path))
			_steps = _automation.get("steps",[])
			_output = str(_automation.get("output",path.get_base_dir()))
			DirAccess.make_dir_recursive_absolute(_output)
		elif arg == "--original-saves": data.prefer_user_saves = false
		elif arg == "--source-windowed": source_windowed = true
	if _automation.has("save"): initial = int(_automation.save)
	if not _automation.is_empty(): Engine.max_fps = 20 # Preserve fixed50ms recorded replays.
	if _automation.get("allow_user_saves",false): data.prefer_user_saves = true
	if source_windowed or bool(_automation.get("source_windowed",false)):
		display_profile.configure(false,false,0)
		_publish_display_profile(false)
	if _automation.has("settings"):
		ui.settings.merge(_automation.settings,true)
		audio.apply_settings(ui.settings)
		battle.apply_settings(ui.settings)
		view.apply_settings(ui.settings)
	if initial >= 0: _load_save(initial, not bool(_automation.get("skip_restart_script",false)))
	elif campaign.entry_story()!="":_new_game()
	elif not _automation.is_empty() and not _automation.get("startup_menu",false) and not _automation.has("startup_profile"): _new_game()
	elif not _automation.is_empty(): _begin_startup()
	else: _open_launch_options()
	if _automation.has("initial_snapshot"): _load_test_snapshot(str(_automation.initial_snapshot))
	_initial_event = int(vm.current_event)
	if bool(_automation.get("autoplay",false)): _autoplay = PublicAutoplay.new()
	RenderingServer.frame_post_draw.connect(_post_draw)
	_record_event({"kind":"ready","save":initial,"viewport":[640,480],"fps_cap":Engine.max_fps})
	print("FT2_READY ",JSON.stringify({"save":initial,"automation":not _automation.is_empty(),"output":_output}))
	_last_service_ms = Time.get_ticks_msec()

func _load_test_snapshot(path: String) -> void:
	var snapshot: Dictionary = JSON.parse_string(FT2Content.text(path))
	var bytes := str(snapshot.units_raw_hex).hex_decode()
	assert(bytes.size() == 6200)
	for slot in range(50): battle.units[slot] = bytes.slice(slot*124,(slot+1)*124)
	var fields: Dictionary = snapshot.fields
	battle.round_index = int(fields.get("round_index",battle.round_index))
	battle.rng = fields.rng.duplicate()
	battle.navigation.configure(battle.units,battle.map_data,int(vm.mode))
	battle.changed.emit()
	view.camera = Vector2i(int(fields.camera[0]),int(fields.camera[1]))
	view.pan_camera(Vector2i.ZERO)
	_record_event({"kind":"native_state_fixture","path":path,"scope":"Automation-only renderer input; not a normal game load format."})

func _set_map(map_id: int) -> void:
	battle.map_id = map_id
	battle.map_data = data.load_map(map_id) if map_id >= 0 else {}
	battle.navigation.configure(battle.units,battle.map_data,int(vm.mode))
	view.set_map(map_id)
	_record_event({"frame":frame_number,"map":map_id})

func _load_save(index: int, restart_script: bool = true) -> void:
	if campaign!=null and campaign.has_slot(index):
		if campaign.load_slot(index):
			ui.slot_header_provider=Callable(campaign,"slot_header")
			_record_event({"frame":frame_number,"kind":"extension_load","index":index});return
		errors.append({"extension_load_failed":index});return
	if campaign!=null and campaign.active:
		campaign.stop();ui.slot_header_provider=Callable()
	battle.load_save(index)
	var save: Dictionary = data.load_save(index)
	vm.restore_state(save.header,save.tail,save.get("header_raw",PackedByteArray()))
	if battle.map_id >= 0:
		view.set_map(battle.map_id)
		view.center_on_unit(0)
	if restart_script:
		vm.start(0 if battle.round_index < 0 else vm.current_event,"Restart")
	else:
		vm.mode = 1
	var music_index := int(save.header.get("bgm",-1))
	if music_index >= 0: audio.play_music(music_index)
	_display_restore_pending=not ui.source_fullscreen
	_record_event({"frame":frame_number,"kind":"load","index":index})

func _save_game(index: int) -> void:
	if campaign!=null and campaign.active:
		var result: Error=campaign.save_slot(index)
		_record_event({"frame":frame_number,"kind":"extension_save","index":index,"error":int(result)})
		if result!=OK:errors.append({"extension_save":index,"error":int(result)})
		return
	var result: Error = data.save_game(index,battle,vm,audio.current_index)
	_record_event({"frame":frame_number,"kind":"save","index":index,"error":int(result)})
	if result != OK: errors.append({"save":index,"error":int(result)})

func _new_game() -> void:
	battle.substate = 0; battle.selected_slot = -1
	if campaign!=null and campaign.entry_story()!="":
		ui.slot_header_provider=Callable(campaign,"slot_header")
		if not campaign.start():errors.append({"extension_start_failed":campaign.errors.duplicate()})
		return
	if campaign!=null and campaign.active:
		campaign.stop();ui.slot_header_provider=Callable()
	vm.bootstrap_campaign()

func _battle_hook_requested(request: Dictionary) -> void:
	if campaign!=null and campaign.active:campaign.on_battle_hook(request)
	else:vm._on_hook(request)

func _begin_startup() -> void:
	var initial: Dictionary = startup.initial_state()
	battle.money = int(initial.money); battle.round_index = int(initial.round_index)
	battle.rng = initial.rng.duplicate()
	var profile: Dictionary = _automation.get("startup_profile",{})
	startup.begin(int(profile.get("forced_stage",ui.settings.get("forced_stage",0))),int(profile.get("complete_flag",ui.settings.get("complete_flag",0))),_startup_shift_down(profile))

func _open_launch_options()->void:
	# Installed source profile: Game.reg Main0/2/1/0. These are game settings,
	# not reads/writes to the user's original registry or physical display BPP.
	var initial:Dictionary=startup.initial_state()
	battle.money=int(initial.money);battle.round_index=int(initial.round_index);battle.rng=initial.rng.duplicate()
	vm.mode=0
	display_profile.configure(false,int(source_display_adapter.get("non8bit",0))!=0,0)
	var profile:Dictionary={"EmulationMode":0,"MusicDevice":2,"FullScreenMode":1,"SilenceEffect":0}
	var saved=ui.settings.get("source_launch_main",{})
	if saved is Dictionary:profile.merge(saved,true)
	profile.MusicDevice=int(ui.settings.get("music_backend",profile.MusicDevice))
	launch_options.open(profile,source_display_adapter)

func _launch_completed(result:int,portable:Dictionary)->void:
	if result!=1:_quit_game();return
	var saved=ui.settings.get("source_launch_main",{})
	var raw:Dictionary=saved.duplicate(true) if saved is Dictionary else {}
	for write in launch_options.model.writes:raw[str(write.key)]=int(write.value)
	ui.settings["source_launch_main"]=raw
	ui.settings["music_backend"]=int(portable.music_backend)
	ui.settings["effects"]=bool(portable.effects)
	audio.apply_settings(ui.settings)
	ui._persist_settings()
	display_profile.configure(display_profile.fullscreen,int(source_display_adapter.get("non8bit",0))!=0,int(portable.legacy_emulation_mode))
	#156 commits options, then124 may still cancel before40D580 graphics init.
	_launch_display_pending=true;_launch_fullscreen_requested=bool(portable.source_fullscreen)
	_begin_startup()

func _startup_shift_down(profile: Dictionary) -> bool:
	if profile.has("shift_down"): return bool(profile.shift_down)
	# WinMain samples physical modifiers before the first input event. Godot's
	# event cache omits a key already held when the process starts on X11.
	# Headless runs never query the desktop keyboard; explicit fixtures above
	# remain available for startup controller validation.
	if DisplayServer.get_name() == "headless":
		_startup_modifier_source = "headless_skipped"
		return false
	if not _startup_modifier_sampled:
		_startup_modifier_sampled = true
		if ClassDB.class_exists("FT2NativeSynth"):
			var sampler = ClassDB.instantiate("FT2NativeSynth")
			if sampler.has_method("sample_startup_modifiers"):
				_startup_modifier_mask = int(sampler.call("sample_startup_modifiers"))
			sampler = null
		_startup_modifier_source = "native_once" if _startup_modifier_mask >= 0 else "event_cache_fallback"
	return (_startup_modifier_mask & 1) != 0 if _startup_modifier_mask >= 0 else Input.is_key_pressed(KEY_SHIFT)

func _startup_ready(event: int) -> void:
	if _launch_display_pending:
		_launch_display_pending=false
		var reset:Dictionary=display_profile.request_rebuild(_launch_fullscreen_requested,0,Callable(self,"_display_driver"))
		if not bool(reset.success):errors.append({"source_display_start_failed":reset});_quit_game();return
	#40D300..40D33E presents TITLE even for a positive ForcedStage/fraud path.
	view.set_overlay([])
	view.service_script_commands([{"op":"paint_main","commands":ui.startup_title_commands()},{"op":"present","mode":"main"}])
	vm.mode=1
	if event > 0:
		vm.current_event = event; vm.mode = 1
		if not vm.start(event,"fraud"): errors.append({"startup_fraud_load_failed":event})
	else: ui.startup_load()

func _visual_requested(plan: Dictionary) -> void:
	if _diagnostics_enabled or not _automation.is_empty(): _record_event({"frame":frame_number,"kind":"visual","plan":_plain(plan)})
	view.play_action(plan)

func _actor_visuals_requested(operation: String,request: Dictionary) -> void:
	match operation:
		"visible_all": view.set_all_actors_visible(bool(request.get("enabled",true)))
		"animation_enabled": view.set_animation_enabled(bool(request.get("enabled",true)))
		"refresh_all": view.refresh_all_actors()

func _nested_frame_service(_context: String) -> void:
	view.set_shake_amplitude(int(vm.raw_globals.get("44923C",0)))
	view.set_game_mode(int(vm.mode))
	view.service_frame(_context)

func _experience_presented(operation: String,request: Dictionary) -> void:
	if operation != "award" or int(request.get("pending_levels",0)) != int(request.get("previous_pending_levels",0)):
		_record_event({"frame":frame_number,"kind":"experience","operation":operation,"request":request.duplicate()})
	for command in experience_meter.service(operation,request):
		var op = str(command.get("op",""))
		if op.begins_with("sound_"): audio.consume_source_sound(command)
		elif op == "party_ui_refresh": battle._actor_visuals("animation_enabled","414285",bool(command.get("value",1)))
		else:
			var unhandled = view.service_experience_commands([command])
			if not unhandled.is_empty(): errors.append({"experience_commands":unhandled})

func _interaction_requested(operation: String,request: Dictionary) -> void:
	match operation:
		"appearance_refresh": view.refresh_actor_visual(int(request.slot))
		"surface_restore": view.draw_tactical_now()
		"actor_remove": view.remove_actor_visual(int(request.slot))
		"overview_invalidate":
			if overview.public_exists: overview.request_paint()
		"unit_list_refresh":
			ui.refresh_107()
			if ui.unit_window_exists: ui.refresh_unit_window()
		"input_gate":
			#41DD50 is the optional unit-list window service, not a board-input gate.
			ui.service_unit_window_visibility(bool(request.get("enabled",true)))
		"event_gate": overview.show_previous_visibility(bool(request.get("enabled",true)))
		_: errors.append({"interaction_operation":operation,"request":request})

func _source_appearance_refresh(slot: int, release_first: bool = false) -> Dictionary:
	return view.source_refresh_actor(slot,release_first,int(vm.mode))

func _script_state(state: Dictionary) -> void:
	if view.has_method("set_script_state"): view.set_script_state(state)
	else: errors.append({"missing_view_method":"set_script_state","state":_plain(state)})

func _camera_requested(request: Dictionary) -> void:
	if view.has_method("camera_request"): view.camera_request(request)
	elif view.has_method("set_camera_request"): view.set_camera_request(request)
	elif request.kind == "actor": view.center_on_unit(int(request.slot))
	else: errors.append({"missing_camera_handler":_plain(request)})

func _palette_requested(request: Dictionary) -> void:
	if view.has_method("palette_request"): view.palette_request(request)
	elif view.has_method("set_palette_request"): view.set_palette_request(request)
	else: errors.append({"missing_palette_handler":_plain(request)})

func _process(delta: float) -> void:
	if _finishing: return
	if _pause and not _step_once and not exit_request.active: return
	_step_once = false
	var now := Time.get_ticks_msec()
	var span := maxi(1,now-_last_service_ms)
	_last_service_ms = now
	_tick(50 if not _automation.is_empty() else span)

func _tick(delta_ms: int = 50) -> void:
	if launch_options!=null and launch_options.active:
		frame_number+=1;elapsed_ms+=delta_ms;view.advance_clock(delta_ms)
		view.set_overlay(launch_options.commands());view.advance(0,"paused")
		cursor_host.request_resource(32512)
		return
	if exit_request.active:
		# Native430020 runs its modal pump without battle/VM/frame-service work.
		# Wall clock still passes; no RNG or scripted action is advanced here.
		frame_number+=1;elapsed_ms+=delta_ms
		view.advance_clock(delta_ms);vm.now_ms+=delta_ms
		_present_close_request()
		return
	frame_number += 1; elapsed_ms += delta_ms
	view.advance_clock(delta_ms)
	_run_steps()
	if campaign!=null and campaign.active:campaign.advance(delta_ms)
	if _autoplay != null:
		for command in _autoplay.tick(battle,ui,vm,view): _record_event({"frame":frame_number,"kind":"autoplay","command":_plain(command)})
	#408B30 tests EVENT==0 before the mode1 battle scheduler and opens41E6C0(-1).
	if int(vm.mode) == 1 and not vm.busy and int(vm.current_event) == 0 and ui.dialog == "":
		battle.substate = 0
		ui.startup_load()
		_record_event({"frame":frame_number,"kind":"startup_return","source":"408B30"})
	var frame_mode := int(vm.mode)
	var frame_phase := str(battle.phase)
	var frame_substate := int(battle.substate)
	var blocked: bool = ui.blocks_outer_frame() or frame_phase == "modal"
	ui.advance(delta_ms) # A modal opened by this frame's logic starts its timer at zero.
	if _display_restore_pending and int(vm.mode)==1 and not vm.busy and ui.dialog=="" and battle.map_id>=0:
		_restore_display_windows();_display_restore_pending=false
	if not blocked: view.advance_palette_clock()
	if blocked: vm.now_ms += delta_ms
	else: vm.advance(delta_ms)
	# Source movement/facing palette service before the battle scheduler.
	if not blocked and frame_mode==1 and not vm.busy:view.parent_palette_cycle(frame_substate)
	battle.update(delta_ms, not blocked and frame_mode == 1 and not vm.busy)
	# A synchronous callback can enter a blocking dialog during this update.
	# Native modal pumps do not run the caller's408A50/RNG tail while open.
	blocked = blocked or ui.blocks_outer_frame() or battle.phase == "modal"
	var overlay: Array[Dictionary] = vm.draw_commands()
	overlay.append_array(ui.commands())
	for command in overview.get_overlay(): overlay.append(command)
	view.set_overlay(overlay)
	view.set_game_mode(int(vm.mode))
	view.set_shake_amplitude(int(vm.raw_globals.get("44923C",0)))
	view.set_modifier_keys(_shift_held,_ctrl_held)
	view.set_facing_choice(facing_choice)
	view.set_pointer_cell(mouse_cell)
	var route := "paused"
	var parent_service := false
	if not blocked:
		if frame_mode == 8 or vm.mode == 8: route = "scene"
		elif frame_mode == 9 or vm.mode == 9: route = "town"
		elif frame_mode == 4:
			if not vm.alternate_surface: route = "normal"; parent_service = true
		elif frame_mode == 1:
			if frame_phase in ["visual","ko"]:
				route = "normal"; parent_service = true
			elif frame_phase == "results": route = "results"
			elif frame_substate in [0,1,2,3,4]:
				route = "normal"; parent_service = true
			elif frame_substate == 6 and battle.phase == "status":
				route = "normal"; parent_service = true
	view.advance(0,route)
	unit_window_host.advance_presentation()
	cursor_host.set_pointer(Vector2(_pointer))
	_cursor_dialog_context()
	cursor_host.advance(elapsed_ms,_cursor_inside,bool(vm.active_window))
	if parent_service and view.render_service_consumes_rng(): battle.render_service_rng("parent",false)
	for service in battle.take_frame_service_requests():
		_record_event({"frame":frame_number,"kind":"frame_service","service":service})
	var capture_interval := int(_automation.get("capture_every_ms",0))
	if capture_interval > 0 and elapsed_ms % capture_interval == 0:
		_prepare_cursor_capture()
		_capture_queue.append("frame_%06d" % elapsed_ms)
	var automation_done = elapsed_ms >= int(_automation.get("duration_ms",10000))
	if bool(_automation.get("stop_on_event_change",false)) and int(vm.current_event) != _initial_event:
		automation_done = true; _automation_end_reason = "event_changed"
	if bool(_automation.get("stop_on_errors",false)) and (not errors.is_empty() or not vm.errors.is_empty() or not vm.scene.errors.is_empty() or not view.unsupported.is_empty() or not view.assets.missing.is_empty()):
		automation_done = true; _automation_end_reason = "recorded_error"
	if not _automation.is_empty() and automation_done and not _completing:
		_completing = true
		_prepare_cursor_capture()
		_capture_queue.append("final")
		_write_snapshot("final")
	if DisplayServer.get_name() == "headless" and not _capture_queue.is_empty(): call_deferred("_post_draw")

func _input(event: InputEvent) -> void:
	if _finishing:return # Queued key-up/focus input may arrive after child resources were released.
	if ui == null: return
	if launch_options!=null and launch_options.active:
		launch_options.handle_input(event)
		return
	if exit_request!=null and exit_request.active:
		if event is InputEventMouse: _pointer=Vector2i(event.position)
		if event is InputEventKey:
			if event.keycode==KEY_CTRL:_ctrl_held=event.pressed
			if event.keycode==KEY_SHIFT:_shift_held=event.pressed
		exit_request.handle_input(event)
		if exit_request.active:_present_close_request()
		return
	if campaign!=null and campaign.blocks_input():
		if event is InputEventMouse:_pointer=Vector2i(event.position)
		if campaign.handle_input(event) and event is InputEventKey:get_viewport().set_input_as_handled()
		return
	if ui.unit_window_blocks_primary_input(): return
	if event is InputEventKey:
		if event.keycode == KEY_CTRL: _ctrl_held = event.pressed
		if event.keycode == KEY_SHIFT: _shift_held = event.pressed
	if event is InputEventMouseMotion or event is InputEventMouseButton: _pointer = Vector2i(event.position)
	if event is InputEventMouseMotion and ui.dialog == "" and vm.mode == 1:
		cursor_host.map_motion(int(battle.substate),_dragging,_ctrl_held)
	if ui.dialog != "" and ui.dialog not in ["battle_message","message","scene_growth"]:
		ui.handle_input(event)
		return
	if ui.dialog == "" and vm.mode == 1 and event is InputEventMouseButton:
		if event.double_click: return
		if int(battle.substate) == 0 and ui.settings.get("swap_mouse",false) and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
			event = event.duplicate()
			event.button_index = MOUSE_BUTTON_RIGHT if event.button_index == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_LEFT
	if event is InputEventKey:
		if event.pressed:
			if event.keycode == KEY_PAUSE:
				_pause = not _pause; return
			var accelerator: bool = event.keycode in [KEY_F1,KEY_F2,KEY_F3,KEY_F4,KEY_F5,KEY_F8,KEY_F10,KEY_F11,KEY_F12] or (event.ctrl_pressed and event.keycode in [KEY_I,KEY_Z])
			if _pause and not accelerator: _step_once = true; return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3 and ui.dialog == "":
		overview.handle_command(40030); return
	if overview.active:
		if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
			ui.command(40004); return
		overview.handle_input(event)
		return
	if _dragging:
		if event is InputEventMouseMotion:
			view.pan_camera(_drag_last-_pointer); _drag_last = _pointer; return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			view.pan_camera(_drag_last-_pointer); _dragging = false; mouse_cell = Vector2i.ZERO; return
	if ui.dialog == "" and vm.mode == 1 and not vm.busy and battle.substate in [1,2,3,4]:
		if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
			battle.cancel_selection(); facing_choice = 4; return
	if ui.dialog == "" and vm.mode == 1 and not vm.busy and battle.substate == 0 and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var cell: Vector2i = view.screen_to_cell(event.position)
		battle.navigation.units = battle.units
		battle.selected_slot = battle.navigation.occupant(cell)
	var interface_accepted = ui.handle_input(event)
	if ui.dialog == "" and vm.mode == 9 and event is InputEventMouseMotion:
		cursor_host.request_resource(161 if vm.town.hover >= 0 else 102) #44294A/WM_MOUSEMOVE.
	if interface_accepted: return
	if vm.mode != 1 or vm.busy: return
	if event is InputEventMouseMotion:
		mouse_cell = view.screen_to_cell(Vector2i(event.position))
		if mouse_cell.x < 0: mouse_cell = Vector2i.ZERO
		if ui.has_method("hover_cell"): ui.hover_cell(mouse_cell,int(event.position.x))
		if battle.substate == 2: _preview_mouse_facing(Vector2i(event.position))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_cell = view.screen_to_cell(Vector2i(event.position))
		if _ctrl_held and battle.substate in [0,1,3]: _start_drag(); return
		if battle.substate == 2:
			_preview_mouse_facing(Vector2i(event.position))
			if facing_choice != 4: battle.commit_facing(facing_choice)
		else:
			var accepted: bool = _select_tactical_cell(mouse_cell)
			if battle.substate == 2:
				facing_choice = 4
				_preview_mouse_facing(Vector2i(event.position))
			elif not accepted and battle.substate in [0,1,3]: _start_drag()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE: battle.cancel_selection()
			KEY_F8: _next_party()
			KEY_ENTER,KEY_KP_ENTER,KEY_SPACE:
				if battle.substate == 2:
					if facing_choice != 4: battle.commit_facing(facing_choice)
				elif mouse_cell.x != 0: _select_tactical_cell(mouse_cell)
			KEY_UP,KEY_RIGHT,KEY_DOWN,KEY_LEFT:
				if battle.substate == 2:
					var directions := {KEY_UP:3,KEY_RIGHT:1,KEY_DOWN:0,KEY_LEFT:2}
					_preview_facing(directions[event.keycode])
				else:
					var directions := {KEY_UP:Vector2i(0,-1),KEY_RIGHT:Vector2i(1,0),KEY_DOWN:Vector2i(0,1),KEY_LEFT:Vector2i(-1,0)}
					_arrow_hover(directions[event.keycode])

func _select_tactical_cell(point:Vector2i)->bool:
	if battle.phase!="player":return false
	if battle.substate==0:
		#405899 checks cursor/pan before41A300 and opens41E920 for every
		#non-party control except7. Mouse and cached-cell Enter share this path.
		if _dragging or int(cursor_host.controller.resource_id)==105:return false
		battle.navigation.units=battle.units
		var slot:int=battle.navigation.occupant(point)
		battle.selected_slot=slot
		if slot>=0 and battle.units[slot].decode_u16(18) not in [0,7]:
			ui.open_status(slot)
			return true
	return battle.select_cell(point)

func _start_drag() -> void:
	_dragging = true; _drag_last = _pointer; mouse_cell = Vector2i.ZERO
	ui.hover_cell(mouse_cell,_pointer.x)

func _arrow_hover(direction: Vector2i) -> void:
	if mouse_cell.x == 0: return
	var candidate := mouse_cell
	var side := int(battle.map_data.get("world_lookup_side",0))
	for ignored in range(maxi(1,side)):
		candidate += direction
		if candidate.x < 0 or candidate.y < 0 or candidate.x >= side or candidate.y >= side: return
		var cell = battle.navigation.cell(candidate)
		if cell == null or int(cell[2]) != 0 or int(cell[3]) == 0: continue
		if battle.substate != 0 and not battle.highlights.has(candidate): continue
		mouse_cell = candidate
		ui.hover_cell(candidate,_pointer.x)
		var point: Vector2i = view.world_to_screen(candidate)
		var delta := Vector2i(mini(point.x-32,0)+maxi(point.x-608,0),mini(point.y-32,0)+maxi(point.y-448,0))
		if delta != Vector2i.ZERO: view.pan_camera(delta)
		return

func _next_party() -> void:
	if battle.substate != 0: return
	for offset in range(1,11):
		var slot := (_next_party_slot+offset)%10
		var unit: PackedByteArray = battle.units[slot]
		if unit.decode_u16(0) == 0 or unit.decode_u16(16) in [1,3,4,5,8,9] or (unit.decode_s32(92) != 0 and unit.decode_s32(96) != 0): continue
		_next_party_slot = slot; battle.selected_slot = slot
		view.center_on_unit(slot)
		mouse_cell = Vector2i(unit.decode_s32(8),unit.decode_s32(12))
		ui.hover_cell(mouse_cell,_pointer.x)
		ui.open_action_menu(_pointer)
		return
	ui.command(40009)

func _preview_mouse_facing(point: Vector2i) -> void:
	if battle.selected_slot < 0: return
	var unit: PackedByteArray = battle.units[battle.selected_slot]
	var anchor: Vector2i = view.world_to_screen(Vector2i(unit.decode_s32(8),unit.decode_s32(12)))-Vector2i(0,48)
	var difference := point-anchor
	_preview_facing((1 if difference.x >= 0 else 0) if difference.y >= 0 else (3 if difference.x >= 0 else 2))

func _preview_facing(direction: int) -> void:
	if battle.selected_slot < 0 or facing_choice == direction: return
	facing_choice = direction
	battle.rules.put16(battle.units[battle.selected_slot],6,direction)
	battle.changed.emit()

func _toggle_fullscreen() -> void:
	if ui.dialog!="" or exit_request.active:return
	if int(vm.mode)==1 and battle.units[0].decode_u16(0)==0:return #404210's empty-party command guard.
	var result:Dictionary=display_profile.request_toggle(int(vm.mode),int(battle.substate),Callable(self,"_display_driver"))
	if result.accepted and not result.success:errors.append({"source_display_reset_failed":result})

func _display_driver(request:Dictionary)->bool:
	if DisplayServer.get_name()=="headless":return true # Explicit logical adapter, no native-window claim.
	_display_generation+=1
	var generation:=_display_generation
	var want_fullscreen:=bool(request.source_fullscreen)
	if want_fullscreen and not bool(request.old_fullscreen):
		_windowed_rect=Rect2i(get_window().position,get_window().size)
		_windowed_borderless=get_window().borderless
	if not want_fullscreen:
		get_window().mode=Window.MODE_WINDOWED
		if _fullscreen_fallback_active:
			get_window().borderless=_windowed_borderless
			if _windowed_rect.has_area():
				get_window().position=_windowed_rect.position;get_window().size=_windowed_rect.size
		_fullscreen_fallback_active=false
		return DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_WINDOWED
	# Keep the root Window's cached mode and DisplayServer in agreement. A raw
	# DisplayServer call alone can be overwritten by later Window size updates.
	get_window().mode=Window.MODE_FULLSCREEN
	# EWMH fullscreen is asynchronous. A bare X server may accept the request
	# initially, then revert it because no window manager applies it. The portable
	# adapter can display the same logical640x480 canvas in a borderless screen-sized
	# window; it does not fabricate a native fullscreen mode or alter source flags.
	if DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_FULLSCREEN:
		if not _apply_fullscreen_fallback():return false
	_verify_fullscreen_request.call_deferred(generation)
	return true

func _display_screen_rect()->Rect2i:
	var screen:=DisplayServer.window_get_current_screen()
	return Rect2i(DisplayServer.screen_get_position(screen),DisplayServer.screen_get_size(screen))

func physical_fullscreen_state()->Dictionary:
	if DisplayServer.get_name()=="headless":return {"verified":false,"headless":true,"fallback":false}
	var screen:=_display_screen_rect()
	var actual:=Rect2i(DisplayServer.window_get_position(),DisplayServer.window_get_size())
	var mode:=DisplayServer.window_get_mode()
	var native:bool=mode in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	var fallback:bool=_fullscreen_fallback_active and get_window().borderless
	return {"verified":actual==screen and (native or fallback),"headless":false,"fallback":fallback,
		"native_mode":mode,"actual_rect":actual,"screen_rect":screen,"root_mode":get_window().mode,"borderless":get_window().borderless}

func _apply_fullscreen_fallback()->bool:
	var screen:=_display_screen_rect()
	if not screen.has_area():return false
	get_window().mode=Window.MODE_WINDOWED
	get_window().borderless=true
	get_window().position=screen.position;get_window().size=screen.size
	_fullscreen_fallback_active=true
	return true

func _verify_fullscreen_request(generation:int)->void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _finishing or generation!=_display_generation or not display_profile.fullscreen:return
	if not bool(physical_fullscreen_state().verified):
		if not _apply_fullscreen_fallback():
			errors.append({"fullscreen_adapter_failed":"no valid screen"});return
		await get_tree().process_frame
		await get_tree().process_frame
		if _finishing or generation!=_display_generation or not display_profile.fullscreen:return
		if not bool(physical_fullscreen_state().verified):errors.append({"fullscreen_adapter_failed":physical_fullscreen_state()})

func _publish_display_profile(fullscreen:bool)->void:
	ui.source_fullscreen=fullscreen;view.set_display_capable(fullscreen)
	overview.fullscreen=fullscreen;overview.windowed_preferred=not fullscreen

func _restore_display_windows()->void:
	if ui.source_fullscreen:return
	ui.service_unit_window_visibility(true)
	overview.restore_after_display_change(false)

func _display_lifecycle(operation:String,request:Dictionary)->void:
	match operation:
		"release":
			if int(request.mode)==1:
				ui.destroy_unit_window(false);overview.release_for_display_change()
			elif int(request.mode)==9:vm.town.hide()
		"publish":_publish_display_profile(bool(request.source_fullscreen))
		"restore":
			if int(request.mode)==1:
				view.refresh_all_actors();_restore_display_windows()
			elif int(request.mode)==9:
				vm.actor_cache_generation+=1;vm.actor_cache_mode=9;vm._emit_actor_state();vm.town.enter()
				view.refresh_all_actors()

func _overview_camera(center: Vector2i) -> void:
	view.camera = center-Vector2i(320,240)
	view.pan_camera(Vector2i.ZERO)

func _cursor_refresh(point: Vector2i) -> void:
	if DisplayServer.get_name() != "headless" and _automation.is_empty(): Input.warp_mouse(Vector2(point))

func _cursor_after_script() -> void:
	if vm.mode == 1 and _cursor_inside: cursor_host.map_motion(int(battle.substate),_dragging,_ctrl_held)

func _cursor_dialog_context() -> void:
	if ui.dialog == "" or ui.dialog in ["message","battle_message","scene_growth"]: return
	var desired = 32512
	if ui.dialog in ["buy_quantity","sell_quantity"]:
		var edit: Rect2i = ui._control_rects.get(1073 if ui.dialog == "buy_quantity" else 1086,Rect2i())
		edit.size.x = maxi(0,edit.size.x-15)
		if edit.has_point(_pointer): desired = 32513
	if int(cursor_host.controller.resource_id) != desired: cursor_host.request_system(desired)

func _prepare_cursor_capture() -> void:
	if _cursor_capture_pending: return
	_cursor_capture_token = cursor_host.begin_capture(not bool(_automation.get("include_cursor_in_capture",false)))
	_cursor_capture_pending = true

func _window_focus(active: bool) -> void:
	vm.active_window = active
	if not active:
		ui.cancel_control_capture(true)
		_dragging = false
		if launch_options!=null:launch_options.cancel_capture()

func _window_close_requested()->void:
	if _finishing or exit_request==null or exit_request.active:return
	if launch_options!=null and launch_options.active:launch_options.cancel_from_os();return
	if ui.dialog=="stage_select":ui.stage_select_message(0x10);return #124 WM_CLOSE aborts before graphics/TITLE.
	_close_base_overlay=vm.draw_commands()
	_close_base_overlay.append_array(ui.commands())
	_close_base_overlay.append_array(overview.get_overlay())
	exit_request.request()
	_present_close_request()

func _present_close_request()->void:
	var commands:Array=_close_base_overlay.duplicate(true)
	commands.append_array(exit_request.commands())
	view.set_overlay(commands);view.advance(0,"paused")
	cursor_host.request_resource(32512)

func _restore_after_close_request()->void:
	view.set_overlay(_close_base_overlay);view.advance(0,"paused")
	_close_base_overlay=[]
	_cursor_dialog_context()

func _quit_game() -> void:
	if not _output.is_empty(): _write_report()
	_finish_runtime(0)

func _run_steps() -> void:
	while _step_index < _steps.size() and int(_steps[_step_index].get("at_ms",0)) <= elapsed_ms:
		var step: Dictionary = _steps[_step_index]; _step_index += 1
		_record_event({"frame":frame_number,"automation":step})
		match str(step.op):
			"capture": _prepare_cursor_capture(); _capture_queue.append(str(step.name)); _write_snapshot(str(step.name))
			"select_unit": battle.select_unit(int(step.slot))
			"select_cell": battle.select_cell(Vector2i(int(step.cell[0]),int(step.cell[1])))
			"action": battle.choose_action(int(step.action_id))
			"confirm": ui.command(40024 if bool(step.get("accepted",true)) else 40025)
			"facing": battle.commit_facing(int(step.direction))
			"cancel": battle.cancel_selection()
			"end_turn": battle.end_turn()
			"ui_command": ui.command(int(step.id))
			"load": _load_save(int(step.index),bool(step.get("restart",true)))
			"save": _save_game(int(step.index))
			"new_game": _new_game()
			"extension_continue":
				if campaign!=null:campaign.continue_dialogue()
			"extension_choice":
				if campaign!=null:campaign.choose(int(step.get("index",0)))
			"click":
				var motion := InputEventMouseMotion.new(); motion.position = Vector2(float(step.pos[0]),float(step.pos[1])); _input(motion)
				var mouse := InputEventMouseButton.new(); mouse.position = Vector2(float(step.pos[0]),float(step.pos[1])); mouse.button_index = int(step.get("button",1)); mouse.pressed = true
				_input(mouse)
				mouse.pressed = false; _input(mouse)
			"mouse_move":
				var motion := InputEventMouseMotion.new(); motion.position = Vector2(float(step.pos[0]),float(step.pos[1])); _input(motion)
			"mouse_down","mouse_up":
				var mouse := InputEventMouseButton.new(); mouse.position = Vector2(float(step.pos[0]),float(step.pos[1])); mouse.button_index = int(step.get("button",1)); mouse.pressed = str(step.op) == "mouse_down"; _input(mouse)
			"key":
				var key := InputEventKey.new(); key.keycode = int(step.keycode); key.pressed = bool(step.get("pressed",true))
				_input(key)
			"assert":
				var actual = battle.get(str(step.property))
				if actual != step.value: errors.append({"assert":step,"actual":_plain(actual)})
			_: errors.append({"unsupported_automation":step})

func _post_draw() -> void:
	if _capture_queue.is_empty(): return
	var image: Image = view.snapshot_image() if DisplayServer.get_name() == "headless" else get_viewport().get_texture().get_image()
	for name in _capture_queue:
		image.save_png(_output.path_join(name+".png"))
		if ui.unit_window_visible:
			var unit_image: Image = unit_window_host.image()
			if unit_image != null: unit_image.save_png(_output.path_join(name+"_unit107.png"))
		if not name.begins_with("frame_"):
			var indices := FileAccess.open(_output.path_join(name+".indices"),FileAccess.WRITE)
			indices.store_buffer(view.snapshot_indices())
			var colors := FileAccess.open(_output.path_join(name+".palette"),FileAccess.WRITE)
			colors.store_buffer(view.palette.current)
	_capture_queue.clear()
	if _cursor_capture_pending:
		cursor_host.end_capture(_cursor_capture_token); _cursor_capture_pending = false
	if _completing:
		_write_report()
		var exit_code := 0 if errors.is_empty() and vm.errors.is_empty() else 1
		_finish_runtime(exit_code)

func _finish_runtime(exit_code: int) -> void:
	if _finishing: return
	_finishing = true
	_release_runtime()
	view.queue_free(); audio.queue_free(); overview.queue_free(); unit_window_host.queue_free(); cursor_host.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout # AudioServer releases the last stopped mixer block asynchronously.
	get_tree().call_deferred("quit",exit_code)

func _release_runtime() -> void:
	if campaign!=null:campaign.stop()
	ui.slot_header_provider=Callable()
	get_tree().auto_accept_quit=_original_auto_accept_quit
	exit_request.dispose()
	launch_options.dispose()
	cursor_host.set_application_enabled(false)
	unit_window_host.dispose()
	audio.stop_all()
	audio.dispose()
	overview.close()
	Input.set_custom_mouse_cursor(null)
	cursor_host.dispose()
	view.dispose()
	# RefCounted controllers subscribe to each other's signals; release those cycles explicitly.
	for controller in [battle,vm,ui,ui.experience,vm.scene,vm.town,startup,exit_request,launch_options,display_profile]:
		for declaration in controller.get_signal_list():
			for connection in controller.get_signal_connection_list(str(declaration.name)):
				controller.disconnect(str(declaration.name),connection.callable)
	vm.measure_text = Callable()
	vm.actor_player_query = Callable()
	vm.actor_appearance_refresh = Callable()
	vm.actor_busy_query = Callable()
	vm.music_busy_query = Callable()
	vm.palette_busy_query = Callable()
	vm.scene.measure_text = Callable()
	vm.overview_visibility = Callable()
	vm.unit_window_visibility = Callable()
	overview.cursor_provider = Callable()
	vm.town.vm = null
	battle.frame_service_callback = Callable()
	ui.preview_unit = Callable()
	ui.music_index_provider = Callable()

func _write_snapshot(name: String) -> void:
	var units: Array = []
	for slot in battle.units.size():
		var unit: Dictionary = data.decode_unit(battle.units[slot],slot)
		unit.raw_hex = battle.units[slot].hex_encode(); units.append(unit)
	var snapshot := {"frame":frame_number,"elapsed_ms":elapsed_ms,"map_id":battle.map_id,
		"phase":battle.phase,"substate":battle.substate,"selected_slot":battle.selected_slot,
		"round_index":battle.round_index,"money":battle.money,"rng":battle.rng,
		"units":units,"vm":_plain(vm.snapshot_state()),
		"input":{"camera":[view.camera.x,view.camera.y],"hover":[mouse_cell.x,mouse_cell.y],"facing_choice":facing_choice,"dragging":_dragging,"next_party_slot":_next_party_slot,"pause":_pause}}
	if campaign!=null and campaign.active:snapshot["extension"]=campaign.snapshot_state()
	var file := FileAccess.open(_output.path_join(name+".json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot,"\t"))

func _write_report() -> void:
	var file := FileAccess.open(_output.path_join("play_report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info(),"frames":frame_number,
		"automation_end_reason":_automation_end_reason,"event_records_dropped":_events_dropped,"autoplay":_plain(_autoplay.snapshot()) if _autoplay != null else {},
		"elapsed_ms":elapsed_ms,"wall_elapsed_ms":(Time.get_ticks_usec()-_start_usec)/1000.0,"events":events,"errors":errors,"vm_errors":vm.errors,
		"audio_failures":audio.failures,"vm_trace":_plain(vm.trace),"render_unsupported":_plain(view.unsupported),
		"source_optional_resource_load_failures":_plain(view.actor_resource_load_failures),
		"missing_assets":_plain(view.assets.missing),"missing_font_data":_plain(view.font.missing),
		"scene_errors":vm.scene.errors,"scene_trace":_plain(vm.scene.trace),
		"active_magic_unsupported":_plain(view.magic.unsupported),
		"unit_window":_plain(unit_window_host.snapshot()),
		"launch_options":{"active":launch_options.active,"state":launch_options.model.snapshot() if launch_options.model!=null else {}},
		"display_profile":display_profile.snapshot(),
		"physical_fullscreen":physical_fullscreen_state(),
		"window_close":{"requests":exit_request.requests,"active":exit_request.active},
		"startup":startup.snapshot(),
		"extension":campaign.snapshot_state() if campaign!=null and campaign.active else {},
		"extension_trace":campaign.trace if campaign!=null else [],
		"extension_errors":campaign.errors if campaign!=null else [],
		"cursor":_plain(cursor_host.snapshot()),
		"scope":"Actual Godot execution; this individual replay does not prove full campaign or pixel parity."},"\t"))

func _plain(value: Variant) -> Variant:
	if value is Vector2i or value is Vector2: return [value.x,value.y]
	if value is Rect2i or value is Rect2: return [value.position.x,value.position.y,value.size.x,value.size.y]
	if value is PackedByteArray: return value.hex_encode()
	if value is Dictionary:
		var out := {}
		for key in value: out[str(key)] = _plain(value[key])
		return out
	if value is Array:
		var out: Array = []
		for child in value: out.append(_plain(child))
		return out
	return value
