class_name FT2Startup
extends RefCounted
## Original WinMain40D269..40D3CF. Platform/TITLE presentation belongs to main.
signal stage_selection_requested
signal money_add_requested(amount:int)
signal ready(current_event:int)
signal aborted
var current_event:=0
var phase:="new"
var money_bonus:=0

static func initial_state()->Dictionary:
	#Literal data-image values, before40D269 config/20000bonus. No script/bootstrap call.
	var variables:Array[int]=[];variables.resize(100);variables.fill(0)
	return {"money":200,"round_index":-1,"rng":[167,19960,5150],"current_event":0,"source_map_number":0,"map_loaded":false,"units_nonzero":0,"event_variables":variables,"mode_before_config":0,"mode_after_TITLE":1,"selected_stage":1}

func begin(forced_stage:int=0,complete_flag:int=0,shift_down:bool=false)->Dictionary:
	current_event=forced_stage if forced_stage!=0 else 0
	money_bonus=0
	if complete_flag!=0 and shift_down:
		phase="stage_selection";money_bonus=20000
		money_add_requested.emit(money_bonus)
		stage_selection_requested.emit()
	else:
		phase="ready";ready.emit(current_event)
	return snapshot()

func resolve_stage_selection(result:int)->Dictionary:
	if phase!="stage_selection":return snapshot()
	if result>0:current_event=result
	if result==-1:phase="aborted";aborted.emit()
	else:phase="ready";ready.emit(current_event)
	return snapshot()

func snapshot()->Dictionary:
	return {"phase":phase,"current_event":current_event,"money_bonus":money_bonus,"fraud_requested":phase=="ready"and current_event>0,"label":"fraud"if phase=="ready"and current_event>0 else ""}
