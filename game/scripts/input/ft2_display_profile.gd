extends RefCounted
## Source40DF39/40D8F0 logical display mode. The host's OSwindow style is an adapter.
## Synchronous lifecycle callbacks: release -> explicit driver -> publish -> restore.
signal lifecycle_requested(operation:String,request:Dictionary)
var fullscreen:=true #46C978, independent of currentGodot window decorations.
var force_fullscreen:=false #46C980, explicit sourceprofile; never inferred from modernhost32bpp.
var emulation_mode:=0 #46C97C, preserved byF4. Native418CB0 receives uint32(value)<1.
var _transitioning:=false

func configure(source_fullscreen:bool,source_force_fullscreen:bool=false,source_emulation_mode:int=0)->void:
	fullscreen=source_fullscreen;force_fullscreen=source_force_fullscreen;emulation_mode=source_emulation_mode

func snapshot()->Dictionary:
	return {"source_fullscreen":fullscreen,"force_fullscreen":force_fullscreen,"emulation_mode":emulation_mode}

func request_toggle(mode:int,substate:int,driver_adapter:Callable)->Dictionary:
	# Mode-specific handlers run first. Actual4042E0 consumes WM_COMMAND in substate5.
	if mode not in [1,9]:return _rejected("source_mode")
	if mode==1 and substate==5:return _rejected("source_busy_substate5")
	if force_fullscreen and fullscreen:return _rejected("source_forced_fullscreen")
	return request_rebuild(not fullscreen,mode,driver_adapter)

func request_rebuild(requested_fullscreen:bool,mode:int,driver_adapter:Callable)->Dictionary:
	# Explicit40D8F0/startup boundary; it has no40003 modegate of its own.
	# Missing adapters and synchronous reentry are integration errors, not fabricated
	# native driver outcomes. Reject before releasing anything.
	if _transitioning:return _rejected("adapter_reentry")
	if not driver_adapter.is_valid():return _rejected("missing_driver_adapter")
	var previous:=fullscreen
	var effective:=true if force_fullscreen else requested_fullscreen
	var request:Dictionary={"mode":mode,"old_fullscreen":previous,"requested_fullscreen":requested_fullscreen,"source_fullscreen":effective,"force_fullscreen":force_fullscreen,"emulation_mode":emulation_mode,"driver_emulation_argument":int((emulation_mode&0xFFFFFFFF)==0)}
	_transitioning=true
	lifecycle_requested.emit("release",request.duplicate(true))
	var success:=bool(driver_adapter.call(request.duplicate(true)))
	if success:
		fullscreen=effective #40DA9A occurs only after418CB0 succeeds.
		lifecycle_requested.emit("publish",request.duplicate(true))
		lifecycle_requested.emit("restore",request.duplicate(true))
	# A failed original driver reset has already released oldresources; there is
	# no source automaticrollback. Logical46C978/config remain old; do not restore.
	_transitioning=false
	return {"accepted":true,"success":success,"old_fullscreen":previous,"source_fullscreen":fullscreen,"changed":previous!=fullscreen,"reason":"" if success else "driver_failed"}

func _rejected(reason:String)->Dictionary:
	return {"accepted":false,"success":false,"old_fullscreen":fullscreen,"source_fullscreen":fullscreen,"changed":false,"reason":reason}
