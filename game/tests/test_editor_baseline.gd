extends SceneTree
## Synthetic regression plus optional local-only original-cache verification.
const Project=preload("res://scripts/editor/ft2_expansion_project.gd")
class LayeredData:
	extends RefCounted
	var repo_root:=""
	var source_root:=""
	var reads:=0
	func read_json(_path: String) -> Dictionary:
		reads+=1
		return {"records":[{"id":0,"name":"변조 레이어","stats":{"hp":{"initial":30000}}}]}

var output:=""
var real_cache:=""
var real_source:=""
var checks:=0
var failures: Array[String]=[]

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)

func write_json(path: String,value) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(value));file.close()

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline-output="):output=arg.trim_prefix("--baseline-output=")
		elif arg.begins_with("--real-cache="):real_cache=arg.trim_prefix("--real-cache=")
		elif arg.begins_with("--real-source="):real_source=arg.trim_prefix("--real-source=")
	if output.is_empty():quit(2);return
	call_deferred("run")

func run() -> void:
	var model=Project.new()
	check(not model.baseline_status().available,"unconnected baseline explicitly unavailable")
	check(model.original_character(0).is_empty()and model.original_skill(1).is_empty(),"no fabricated original values")
	check(not model.reset_record("characters",0).ok,"reset refuses absent original")
	var cache:=output.path_join("synthetic-cache")
	var races: Array=[];var skills: Array=[]
	for id in 4:
		var stats: Dictionary={}
		for stat in Project.STAT_NAMES:stats[stat]={"initial":20+id,"growth":id+1}
		races.append({"id":id,"name":"자작 원본 테스트 "+str(id),"stats":stats,"default_skill_slots4":[1,2,0,0]})
		write_json(cache.path_join("data/port_ready/assets/apd/animations/CHAR_%02dE.json"%id),{})
		skills.append({"id":id,"name":"자작 테스트 스킬 "+str(id),"mp":id+2,"power":id+3,"power_channels_signed":[id+3,-(id+8),0],"v2":id,"flag":id+4})
	skills[3].power=0;skills[3].power_channels_signed=[0,0,0]
	write_json(cache.path_join("data/port_ready/tables/race.dat.json"),{"records":races})
	write_json(cache.path_join("data/port_ready/tables/magic.dat.json"),{"records":skills})
	var data:=LayeredData.new();data.repo_root=cache
	model.source_data=data
	check(model.baseline_status().available,"connected pristine baseline available")
	check(data.reads==0,"layered read_json never consulted")
	check(model.original_catalog("characters").size()==4 and model.original_catalog("skills").size()==3,"all original catalogs retain numeric IDs")
	check(model.original_catalog("characters","테스트 2").size()==1,"catalog searches UTF8 names")
	check(model.original_character(99).is_empty(),"unknown ID has no fabricated baseline")
	var original: Dictionary=model.original_character(2)
	check(original.stats["hp.initial"]==22 and original.stats["agi.growth"]==3,"original complete editable stat pairs")
	check(original.sprite=="CHAR_02E"and original.skills==[1,2],"derived sprite and native nonzero skill slots")
	original.stats["hp.initial"]=30000;original.skills.append(3)
	check(model.original_character(2).stats["hp.initial"]==22 and model.original_character(2).skills==[1,2],"returned deep copy cannot change baseline")
	var catalog: Array=model.original_catalog("characters");catalog[0].stats["hp.initial"]=-1
	check(model.original_character(0).stats["hp.initial"]==20,"catalog deep copy isolation")
	var character: Dictionary=model.original_character(2)
	character.id="my_hero";character.name="나의 캐릭터";character.level=37;character.stats={"hp.initial":99,"mp.growth":8};character.skills=[3]
	model.content.characters=[character]
	check(model.changed_fields("characters",0).has("stats.hp.initial")and not model.changed_fields("characters",0).has("level"),"changed fields compare to original without instance level")
	check(model.reset_field("characters",0,"hp.initial").ok,"single stat reset succeeds")
	check(not model.content.characters[0].stats.has("hp.initial")and model.content.characters[0].stats["mp.growth"]==8,"single reset inherits original and preserves other override")
	check(not model.reset_field("characters",0,"id").ok and not model.reset_field("characters",0,"level").ok,"identity and instance level protected")
	check(model.reset_record("characters",0).ok,"full character reset succeeds")
	check(model.content.characters[0].id=="my_hero"and model.content.characters[0].level==37 and model.content.characters[0].base_race==2,"full reset keeps project identity base and user level")
	check(model.content.characters[0].stats.is_empty()and model.content.characters[0].skills==[1,2],"full reset uses original reference and native skill IDs")
	check(model.changed_fields("characters",0).is_empty(),"full reset has no original field changes")
	var skill: Dictionary=model.original_skill(2)
	check(skill.power==-10 and skill.range_min==2 and skill.range_max==6,"skill signed dominant channel and native ranges")
	skill.id="my_skill";skill.mp=100;skill.visual_skill=1;model.content.skills=[skill]
	check(model.reset_field("skills",0,"mp").ok and model.content.skills[0].mp==4,"single skill field reset")
	check(model.content.skills[0].visual_skill==1,"single skill reset preserves other override")
	check(model.reset_record("skills",0).ok and model.content.skills[0].id=="my_skill"and model.content.skills[0].visual_skill==2,"full skill reset preserves local identity")
	# Save changes; restore after re-opening by persisted base references, never saved snapshots.
	model.content.characters[0].stats={"hp.initial":400}
	model.content.skills[0].mp=900
	var project_path:=output.path_join("authored-project")
	check(model.save_project(project_path).ok,"save project with sparse overrides")
	var reopened=Project.new();reopened.source_data=data
	check(reopened.load_project(project_path).ok,"reload project")
	check(reopened.reset_record("characters",0).ok and reopened.content.characters[0].stats.is_empty(),"reload character reset uses persisted base reference")
	check(reopened.reset_record("skills",0).ok and reopened.content.skills[0].mp==4,"reload skill reset uses original baseline")
	var zero=Project.new();zero.source_data=data
	zero.content.skills=[zero.original_skill(3)];zero.content.skills[0].id="spark"
	check(zero.validate_project().ok,"original non-damage zero-power skill is valid")
	zero.content.skills[0].base_skill=1
	check(not zero.validate_project().ok,"damage-template zero-power override remains invalid")
	var serialized:=FileAccess.get_file_as_string(project_path.path_join("content.json"))
	check(not serialized.contains("raw_record_hex")and not serialized.contains("original_snapshot")and not serialized.contains("parameter_pair_raw"),"saved descriptors contain no raw original snapshots")
	zero.content.skills[0].base_skill=3
	var archive:=output.path_join("own-export.zip")
	check(zero.export_project(archive).ok,"baseline-backed descriptor exports")
	var reader:=ZIPReader.new()
	var opened:=reader.open(archive)
	var files: Array[String]=[]
	if opened==OK:
		for name in reader.get_files():
			if not name.ends_with("/"):files.append(name)
	check(opened==OK and files==["my_expansion/mod.json","my_expansion/content.json"],"export only contains two authored descriptor files")
	reader.close()
	# Even a later mutation of the synthetic source does not mutate a captured baseline.
	races[2].stats.hp.initial=1000
	write_json(cache.path_join("data/port_ready/tables/race.dat.json"),{"records":races})
	check(model.original_character(2).stats["hp.initial"]==22,"snapshot stable after source metadata changes")
	model.source_data=null
	check(not model.baseline_status().available and model.original_catalog("characters").is_empty(),"disconnect clears private original snapshots")
	if not real_cache.is_empty():real_verification()
	var report:={"passed":failures.is_empty(),"checks":checks,"failures":failures,"real_cache_checked":not real_cache.is_empty(),"original_data_embedded":false}
	write_json(output.path_join("result.json"),report)
	print(JSON.stringify(report));quit(0 if failures.is_empty()else 1)

func real_verification() -> void:
	var race_path:=real_cache.path_join("data/port_ready/tables/race.dat.json")
	var magic_path:=real_cache.path_join("data/port_ready/tables/magic.dat.json")
	var before:=[FileAccess.get_sha256(race_path),FileAccess.get_sha256(magic_path),FileAccess.get_sha256(real_cache.path_join("fixtures/race.dat")),FileAccess.get_sha256(real_cache.path_join("fixtures/magic.dat"))]
	var model=Project.new();var data:=LayeredData.new();data.repo_root=real_cache;model.source_data=data
	check(model.baseline_status().available,"real cache original baseline available")
	var catalog: Array=model.original_catalog("characters")
	var golems: Array=model.original_catalog("characters","고렘")
	check(not golems.is_empty(),"real golem records found by name search")
	check(catalog.size()>golems.size()+2,"original catalog includes other character and monster types")
	var verified:=0
	for original in catalog:
		if original.stats.is_empty():continue
		var pristine: Dictionary=model.original_character(int(original.base_race))
		original.id="own_"+str(original.base_race);original.level=53;original.stats["hp.initial"]=30000
		model.content.characters=[original]
		check(model.reset_record("characters",0).ok and model.content.characters[0].stats.is_empty(),"real record reset inherits pristine original "+str(original.base_race))
		check(model.character_defaults(model.content.characters[0]).stats==pristine.stats,"real original stat lookup stable "+str(original.base_race))
		verified+=1
	check(verified>20,"reset supports entire character and monster catalog")
	var skill_catalog: Array=model.original_catalog("skills")
	check(skill_catalog.size()>20,"real original skills catalog available")
	for index in mini(3,skill_catalog.size()):
		var skill: Dictionary=skill_catalog[index];var mp:=int(skill.mp)
		skill.id="own_skill";skill.mp=32767;model.content.skills=[skill]
		check(model.reset_field("skills",0,"mp").ok and model.content.skills[0].mp==mp,"real skill MP reset "+str(index))
	check(data.reads==0,"real lookup bypasses dirty overlay data")
	var overlay:=output.path_join("dirty-layer")
	write_json(overlay.path_join("mod.json"),{"schema":1,"id":"baseline_test","name":"Own test changes","version":"1","table_edits":[{"table":"race","record":0,"fields":{"hp.initial":12345}},{"table":"magic","record":1,"fields":{"mp":1234}}]})
	var mounted: Dictionary=FT2Content.activate(real_cache,real_source,[overlay])
	check(mounted.ok,"real cache dirty table override layer mounts: "+str(mounted.get("error","")))
	if mounted.ok:
		var runtime:=FT2Data.new()
		check(runtime.load_table("race")[0].stats.hp.initial==12345 and runtime.load_table("magic")[1].mp==1234,"runtime current values reflect table overrides")
		model.source_data=runtime
		check(model.original_character(0).stats["hp.initial"]!=12345 and model.original_skill(1).mp!=1234,"original baseline survives real active dirty table layer")
	FT2Content.active=null
	var after:=[FileAccess.get_sha256(race_path),FileAccess.get_sha256(magic_path),FileAccess.get_sha256(real_cache.path_join("fixtures/race.dat")),FileAccess.get_sha256(real_cache.path_join("fixtures/magic.dat"))]
	check(before==after,"real original cache hashes unchanged")
