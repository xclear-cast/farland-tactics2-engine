# 확장팩 v2 실행 규격 — 0.2.0-preview

정품 데이터는 개인 캐시에서 읽고, 자작 스토리·새 격자 맵·캐릭터·스킬 정의를 추가하는
현재 실행 규격이다. 제작 GUI 사용법은 [EXPANSION_EDITOR.md](EXPANSION_EDITOR.md),
완전한 자체 JSON 예제는 [example_expansion](../mods/example_expansion/)에 있다.
아래 `{id,name,...}` 표기는 필드 요약이며 그대로 복사하는 JSON 문법이 아니다.

## 원본 데이터 불변

확장 정의는 메모리에서 원작 테이블/맵/리소스를 참조해 새 ID에 연결한다. 원작 파일이나
기본 캐시를 수정하지 않는다. 공유 프로젝트는 자체 JSON과 본인 자산만 포함한다.

## 파일

`mod.json`: `schema:2`, `id`, `name`, `version`, `content:"content.json"`, 선택 `entry_story:"intro"`.
v1의 files/patches/table_edits도 유지한다. 구버전은 schema2를 거부하므로 내용이 조용히 무시되지 않는다.

`content.json`: `schema:1`, `characters:[]`, `skills:[]`, `maps:[]`, `stories:[]`.
로컬 ID는 프로젝트 내부 이름, 전역 ID는 `pack_id:local_id`. 원작 참조는 기존 정수 ID와
기존 APD stem을 사용하며 가짜 미구현 namespace를 추가하지 않는다.

- characters: `{id,name,base_race:1,sprite:"CHAR_00E",level:1,stats:{},skills:[]}`.
  base_race는 능력치/성장 기반. skills는 전역/로컬 스킬 ID 문자열 또는 원작 정수 ID.
  stats 필드는 기존 테이블 편집의 `hp.initial`, `hp.growth`, `atk.initial` 형식을 따른다.
  새 캐릭터 이름은 원작 kind 이름과 분리한다. 원작 APD 참조는 사용자 정품에서 읽는다.
  이름은 UTF-8 메타데이터이며 스킬은 최대 10개, 시작/배치 레벨은 1..99이다.
  HP 초기값은 양수, MP 초기값은 0 이상이어야 한다. 현재 sprite는 기존 CHAR APD 계열을 참조한다.
- skills: `{id,name,base_skill:1,visual_skill:1,mp:3,power:12,range_min:1,range_max:3}`.
  새 action ID에 새 능력치를 등록하고, 원작 visual_skill의 연출을 재사용한다.
  v2 최소 구현은 새로운 이름/소비/위력/거리의 스킬. 임의 C 코드나 원작 파일을 공유하지 않는다.
  base_skill의 계산 종류와 visual_skill의 모션을 구분한다. MP를 0으로 바꿨다고 물리/마법
  계산 종류가 자동으로 바뀌는 것은 아니다. 새 스킬의 내부 action ID는 원작 스킬 뒤에서
  할당하며 1000 이상은 아이템 action 공간이므로 사용하지 않는다.
- maps: `{id,name,base_map:40,width:8,height:8,cells:[],placements:[]}`.
  선택한 원작 맵의 타일을 참조해 새 격자를 작성할 수 있고 원작 맵은 변경하지 않는다.
  좌표는 x=1..width, y=1..height이며 0은 사용하지 않는다. 기본 terrain은 1이다.
  cells는 `{x,y,height,terrain}` 변경점. placements는
  `{character:"hero",side:"ally",x:2,y:2,level:1}` 또는 원작 `{race:1,sprite:"CHAR_00E",...}`.
  크기는 각 1..64, terrain은 0..7, height는 signed16 범위이다. 처음에는 높이 0..4와
  terrain 1을 권한다. 맵 ID는 10000 이후 별도 공간에 할당한다. 새 격자의 그림은 기반
  맵의 가용 타일로 합성하며, 모든 지형 값에 별도 그림이 있는 것은 아니다.
- stories: `{id,start:"hello",nodes:[{id:"hello",type:"dialogue",speaker:"hero",text:"직접 쓴 대사",next:"fight"},
  {id:"fight",type:"battle",map:"field",next:"ending",on_defeat:"failed"},{id:"ending",type:"end"}]}`.
  dialogue, battle, branch(변수/선택지), set(변수), end를 선언형으로 처리한다.
  조건 분기는 `{id,type:"branch",variable:"flag",equals:1,then:"yes",else:"no"}`를 사용한다.
  런타임은 선택형 branch의 `choices:[{text,next,set:{변수:값}}]`도 지원한다. 이 경우
  then/else 대신 선택지의 next를 사용한다. 현재 제작 GUI의 폼은 비교형 branch를 제공하므로
  수동 선택형 JSON을 GUI에서 다시 적용할 때 보존을 가정하지 말고 확인한다.
  node ID는 스토리 안에서 고유해야 하며 start/next/분기 대상은 존재해야 한다.

ID는 1..64자의 영문·숫자·밑줄·하이픈·점으로 작성한다. 숫자 할당은 같은 활성 정의
집합에서 결정적이지만 정의 추가/제거 후에도 같은 내부 번호가 영구 유지되는 API는 아니다.
원작 정수 참조와 확장 ID 문자열을 구분하고 내부 숫자 ID 대신 선언한 이름을 공유한다.

## 실행과 저장

- 연결한 확장팩에 entry_story가 있으면 새 게임이 그 이야기에서 시작한다. 확장 스토리가
  없으면 기존 원작 시작/진행 경로를 유지한다. 명시적으로 선택한 저장 슬롯은 먼저 복원한다.
- dialogue는 자체 native UI로 표시하며 계속 버튼/Enter/Space로 다음 노드로 이동한다.
- set은 이야기 변수, branch는 변수 비교나 선택, battle은 등록한 새 맵의 전투를 실행한다.
- 전투 승리는 next, 패배는 on_defeat로 이동한다. on_defeat가 없으면 next를 사용한다.
  결과는 `last_battle` 변수의 `victory`/`defeat`로도 남긴다. 원작 COMPLETE/GAMEOVER
  스크립트를 실행하는 대신 확장 노드로 전환한다.
- end는 에피소드를 마치며 처음부터/종료 선택을 표시한다.
- 전투마다 placements 정의에서 유닛을 새로 생성한다. 캐릭터 육성·HP·장비를 원작 파티처럼
  전투 간 자동 승계하는 기능과 원작 챕터로 복귀하는 기능은 현재 제공하지 않는다.
- 확장 저장은 `user://profiles/<프로필>/saves/extensionNN.json`의 schema 2 JSON이다.
  스토리·노드·변수·맵 참조·유닛·소지품·돈·턴·RNG를 저장하고 원작 DAT 세이브와 분리한다.
  일반 저장 메뉴는 확장 슬롯 헤더를 사용하며, 전투의 player/substate0 대기 상태에서 저장한다.
- profile은 기본 콘텐츠와 활성 모드의 내용/파일/순서로 구분한다. 프로젝트 수정이나
  구성 파일 변경 후 이전 저장본의 자동 호환을 보장하지 않는다.

## 현재 제공하지 않는 것

자작 PNG를 APD 캐릭터로 변환하는 가져오기 도구, 새 타일 이미지 편집/가져오기,
임의 스킬 동작/새 VM 명령 작성, 원작 특정 장 뒤에 삽입했다가 복귀하는 흐름,
원작 없는 독립 게임 프로젝트를 현재 제작기의 기능으로 제공하지 않는다.
공유 ZIP은 제작기의 자체 mod.json/content.json 정의만 포함하며 원작 자산을 복사하지 않는다.

## 개발자용 API

| 모듈 | 주요 인터페이스 |
| --- | --- |
| `ft2_extension_registry.gd` | `FT2Content.active.extensions`, `characters/skills/maps/stories`, `entry_story`, `resolve_id`, `character_race_id`, `skill_action_id`, `map_id`, `spawn_placements` |
| `ft2_extension_maps.gd` | `normalized(data, definition, numeric_id)`, `indexed(data, definition, numeric_id)` — 원작 타일을 로컬에서 읽어 새 격자와 메모리 화면 구성 |
| `ft2_campaign_runner.gd` | `start`, `continue_dialogue`, `choose`, `advance`, `save_slot`, `load_slot`, `slot_header` |
| `ft2_expansion_project.gd` | 정의 모델, 검증, 두 파일 저장·재열기·ZIP 내보내기 |
| `ft2_expansion_editor.gd` | 제작 GUI와 `play_requested(project_directory)` |

이 새 모듈·문서·자체 예제의 재사용 허가는 [EXAMPLES_LICENSE](../EXAMPLES_LICENSE)의
정확한 경로 범위를 따른다. 원작 파일·캐시·기존 엔진 전체의 권리를 부여하지 않는다.

## 검증 범위 구분

로컬 정품 검증에서는 새 8×8 맵, 새 캐릭터/스킬 ID, 실제 스킬의 MP 소비·KO,
대사/분기/전투 결과/종료, 확장 저장·재개를 확인한다. 원본 파일은 읽기 전용이다.
클라우드 CI에는 원작을 올리지 않고 자체 합성 테이블/정의와 제작기 컨트롤만 검사한다.
Mac의 앱 빌드·서명·합성 검사 성공을 실제 정품 캠페인 전체의 Mac 검증으로 확대하지 않는다.
