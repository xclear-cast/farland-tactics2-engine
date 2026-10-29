extends SceneTree
var checks:=0
var failures:Array[String]=[]
var fixtures:=""
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fixtures="):fixtures=argument.trim_prefix("--fixtures=")
	var source:=fixtures.path_join("source");var cache:=fixtures.path_join("cache");var project:=fixtures.path_join("extension")
	var base:=FT2Content.activate(cache,source)
	check(base.ok,"base fixture mounts")
	var before_races:=FT2Content.table_bytes("race");var before_skills:=FT2Content.table_bytes("magic")
	var base_profile:=FT2Content.active.profile_id
	var mounted:=FT2Content.activate(cache,source,[project])
	check(mounted.ok,"v2 JSON schema mounts")
	if not mounted.ok:print(mounted);finish();return
	var registry=FT2Content.active.extensions
	var hero: int=registry.character_race_id("definition_test:hero");var foe: int=registry.character_race_id("definition_test:foe");var skill: int=registry.skill_action_id("definition_test:spark")
	check(hero>=2 and foe>=2 and hero!=foe,"characters have distinct added race IDs")
	check(skill>=2 and skill<1000,"skill has added non-item action ID")
	var data:=FT2Data.new()
	check(data.raw_table("race").slice(0,before_races.size())==before_races,"original race prefix unchanged")
	check(data.raw_table("magic").slice(0,before_skills.size())==before_skills,"original skill prefix unchanged")
	check(str(data.load_table("race")[hero].name)=="힣 매우 긴 새로운 영웅 이름","UTF8 name is independent of binary field width")
	check(str(data.load_table("magic")[skill].name)=="힣 새로운 번개","UTF8 skill display name")
	check(registry.sprite_alias("CHAR_%02dE"%hero)=="CHAR_00E","casting sprite aliases original family")
	check(registry.sprite_alias("CHAR_%02dA"%hero)=="CHAR_00A","standing sprite aliases original family")
	check(data.raw_table("magic").decode_s16(skill*64+22)==3 and data.raw_table("magic").decode_s16(skill*64+24)==12,"new skill owns MP and power")
	check(data.raw_table("magic").decode_u16(skill*64+32)==3,"new skill owns range")
	var battle=load("res://scripts/logic/ft2_battle.gd").new(data)
	var map_definition:Dictionary={"global_id":"definition_test:arena","pack_id":"definition_test","width":8,"height":8,
		"placements":[{"character":"hero","side":"ally","x":2,"y":2},{"character":"foe","side":"enemy","x":4,"y":2}]}
	var spawned:Dictionary=registry.spawn_placements(map_definition,battle)
	check(spawned.issues.is_empty(),"new units construct through battle rules")
	battle.units=spawned.units;battle.rng=spawned.rng;battle.event_id=-1
	var actor:=int(spawned.character_slots["definition_test:hero"]);var target:=int(spawned.character_slots["definition_test:foe"])
	check(battle.units[actor].decode_u16(2)==hero and battle.units[actor].decode_u16(56)==skill,"new character keeps own race and skill IDs")
	check(battle.units[actor].decode_s16(38)==120 and battle.units[actor].decode_s16(42)==30,"new character stats apply")
	check(battle.units[actor].decode_u32(92)==0 and battle.units[actor].decode_u32(96)==0,"new placements can act")
	var high_level: PackedByteArray=battle.units[actor].duplicate();high_level.encode_u16(4,99)
	var grown: Dictionary=battle.rules.grow_record(high_level,false,battle.rng)
	check(grown.unit.decode_u16(56)==skill,"custom skills survive original level-up learning masks")
	var cells:Array=[]
	for y in range(1,9):
		for x in range(1,9):cells.append({"x":x,"y":y,"H":0,"flag2_raw":0,"flag3_raw":0,"L":1,"part_count":0})
	battle.map_data={"cells":cells,"header_map_bounds_ltrb":[-8,0,0,8]};battle.map_id=10000
	battle.navigation.configure(battle.units,battle.map_data,1)
	var old_magic: PackedByteArray=battle.rules.magics.duplicate()
	var decision:Dictionary=battle.ai.decision(target)
	check(int(decision.action_id)==skill,"enemy AI chooses new damage skill")
	check(battle.select_unit(actor) and battle.choose_action(skill),"new skill is actually selectable")
	check(not battle.highlights.has(Vector2i(6,2)),"new range excludes distant cells")
	check(battle.select_cell(Vector2i(4,2)),"new skill targets a legal enemy")
	battle.confirm_action(true)
	check(battle.units[actor].decode_s16(42)==27,"new skill consumes its own 3 MP")
	check(battle.units[target].decode_s16(38)==63,"new skill power12 reaches numeric calculation (37 damage)")
	check(int(battle.pending_plan.action_id)==skill and int(battle.pending_plan.effect_id)==1,"new gameplay action and original visual ID are separate")
	check(battle.rules.magics==old_magic,"numeric template scope restores complete table")
	check(FT2Content.active.profile_id!=base_profile,"v2 gets isolated saves")
	var first_profile:=FT2Content.active.profile_id
	check(FT2Content.activate(cache,source,[project]).ok,"v2 can remount")
	check(FT2Content.active.extensions.character_race_id("definition_test:hero")==hero and FT2Content.active.extensions.skill_action_id("definition_test:spark")==skill,"IDs deterministic after remount")
	check(FT2Content.active.profile_id==first_profile,"unchanged v2 keeps save identity")
	var changed:=FileAccess.open(project.path_join("content.json"),FileAccess.READ);var text:=changed.get_as_text();changed.close()
	var writer:=FileAccess.open(project.path_join("content.json"),FileAccess.WRITE);writer.store_string(text+"\n");writer.close()
	check(FT2Content.activate(cache,source,[project]).ok and FT2Content.active.profile_id!=first_profile,"content.json changes isolate save identity")
	writer=FileAccess.open(project.path_join("content.json"),FileAccess.WRITE);writer.store_string(text);writer.close()
	var valid=JSON.parse_string(text)
	for invalid in ["unknown_skill","invalid_visual","invalid_story_nodes","invalid_story_link","zero_hp","fractional_reference"]:
		var document:Dictionary=valid.duplicate(true)
		match invalid:
			"unknown_skill":document.characters[0].skills=["missing"]
			"invalid_visual":document.skills[0].visual_skill=99
			"invalid_story_nodes":document.stories=[{"id":"broken","start":"bad","nodes":"invalid"}]
			"invalid_story_link":document.stories=[{"id":"broken","start":"hello","nodes":[{"id":"hello","type":"dialogue","next":"missing"}]}]
			"zero_hp":document.characters[0].stats["hp.initial"]=0
			"fractional_reference":document.characters[0].skills=[1.5]
		writer=FileAccess.open(project.path_join("content.json"),FileAccess.WRITE);writer.store_string(JSON.stringify(document));writer.close()
		check(not FT2Content.activate(cache,source,[project]).ok,"invalid v2 rejects cleanly: "+invalid)
	var choice:Dictionary=valid.duplicate(true)
	choice.stories=[{"id":"choice_story","start":"pick","nodes":[{"id":"pick","type":"branch","choices":[{"text":"A","next":"done","set":{"flag":1}}]},{"id":"done","type":"end"}]}]
	writer=FileAccess.open(project.path_join("content.json"),FileAccess.WRITE);writer.store_string(JSON.stringify(choice));writer.close()
	check(FT2Content.activate(cache,source,[project]).ok,"choice branch works without then/else")
	writer=FileAccess.open(project.path_join("content.json"),FileAccess.WRITE);writer.store_string(text);writer.close()
	check(FT2Content.activate(cache,source).ok and FT2Content.table_bytes("race")==before_races and FT2Content.table_bytes("magic")==before_skills,"disable extension restores original rows")
	battle=null;data=null;FT2Content.active=null
	finish()
func finish()->void:
	var report:Dictionary={"checks":checks,"failures":failures,"passed":failures.is_empty(),"synthetic_only":true}
	var file:=FileAccess.open(fixtures.path_join("extension_result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("FT2_EXTENSION_DEFINITIONS ",JSON.stringify(report));quit(0 if failures.is_empty()else 1)
