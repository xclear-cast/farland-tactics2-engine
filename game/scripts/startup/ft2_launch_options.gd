extends RefCounted
## Source40CDD0; raw callbacks separate from normal disabled input.
signal finished(result:int)
const KEYS:Array[String]=["EmulationMode","MusicDevice","FullScreenMode","SielnceEffect"]
const GENERAL:="동작환경을 지정해 주십시오."
const MUSIC:="음원을 선택합니다.\r\nCD음원을 사용할 경우에는, 게임 CD를 CD-ROM 드라이브에셋트시켜 주십시오."
const DISPLAY:="전화면 모드 플레이 여부를 선택합니다.\r\n256색  모드가 아니면 자동적으로 ON이 됩니다."
const EFFECT:="효과음 유무를 지정합니다\r\n소프트웨어 MIDI를 사용해서,  곡이 연주되지 않는 경우에는 OFF로 해 주십시오."
var values:Dictionary={}
var checked:Dictionary={}
var disabled:Array[int]=[1097,1098]
var enable_calls:Array=[]
var ended:Array=[]
var writes:Array=[]
var help_text:=""
var previous_focus:=0
var profile:Dictionary={}
var adapter:Dictionary={}

func begin(raw_profile:Dictionary={},api_feedback:Dictionary={})->int:
	profile=raw_profile.duplicate(true);adapter=api_feedback.duplicate(true)
	values.clear();checked.clear();disabled.assign([1097,1098]);enable_calls.clear();ended.clear();writes.clear();help_text="";previous_focus=0
	for key in KEYS:values[key]=int(profile.get(key,0))&0xffffffff
	if int(adapter.get("drive_type",3))==5:
		# Literal missing control1071, not an invented disabled1091.
		enable_calls.append({"hwnd":0,"enabled":0});values.MusicDevice=0
	if int(adapter.get("non8bit",0))!=0:
		disabled.append(1093);enable_calls.append({"hwnd":0x10000+1093,"enabled":0});values.FullScreenMode=1
	checked={"1097..1098":1098 if int(values.EmulationMode)<1 else 1097,"1090..1091":1091 if int(values.MusicDevice)==2 else 1090,"1092..1093":1093 if int(values.FullScreenMode)<1 else 1092,"1094..1095":1094 if int(values.SielnceEffect)<1 else 1095}
	return 1

func message(message_id:int,wparam:int=0,focus_id:int=0)->int:
	if message_id==0x10:_end(0);return 0
	if message_id==0x111:
		var control:=wparam&65535
		match control:
			1:
				for key in KEYS:writes.append({"section":"Main","key":"SilenceEffect"if key=="SielnceEffect"else key,"value":values[key]})
				_end(1)
			2:_end(0)
			1090:values.MusicDevice=0
			1091:values.MusicDevice=2
			1092:values.FullScreenMode=1
			1093:values.FullScreenMode=0
			1094:values.SielnceEffect=0
			1095:values.SielnceEffect=1
			1097:values.EmulationMode=1
			1098:values.EmulationMode=0
		return 1
	if message_id in [0x135,0x138] and focus_id!=previous_focus:
		match focus_id:
			1090,1091:help_text=MUSIC
			1092,1093:help_text=DISPLAY
			1094,1095:help_text=EFFECT
			1097,1098:help_text=""
			_:help_text=GENERAL if previous_focus==0 else ""
		previous_focus=focus_id
	return 0

func user_activate(control:int)->bool:
	if control in disabled or not ended.is_empty():return false
	for pair in checked:
		var bounds:=str(pair).split("..")
		if control>=int(bounds[0]) and control<=int(bounds[1]):checked[pair]=control
	message(0x111,control);return true

func _end(result:int)->void:
	ended.append(result);finished.emit(result)

func snapshot()->Dictionary:
	return {"values":values.duplicate(true),"checked":checked.duplicate(true),"disabled":disabled.duplicate(),"enable_calls":enable_calls.duplicate(true),"ended":ended.duplicate(),"writes":writes.duplicate(true),"help":help_text,"previous_focus":previous_focus}

func portable_commit()->Dictionary:
	# Binding information only: platform driver success is not implied.
	if ended.is_empty() or int(ended[-1])!=1:return {}
	return {"music_backend":int(values.MusicDevice),"effects":int(values.SielnceEffect)==0,"source_fullscreen":int(values.FullScreenMode)!=0,"legacy_emulation_mode":int(values.EmulationMode),"OS_fullscreen_change_requested":false}
