# 모드 규격 및 캐시 소비 구조

이 문서는 `game/scripts/content/ft2_content.gd`와 데이터 로더가 현재 지원하는
**엔진 측 규격**입니다. 원작 EXE 디스어셈블리, 원본 테이블 덤프, 원작 대사·맵·이미지를
담고 있지 않습니다. 일반적인 수치 모드는 아래 `table_edits`만으로 만들 수 있습니다.

`schema: 1`은 기존 데이터 오버레이와 레코드 편집 규격입니다. `schema: 2`는
`content.json`에 새 캐릭터·스킬·격자 맵·스토리를 등록하는 현재 확장 규격입니다.
정확한 v2 필드와 실행·저장 계약은 [EXTENSION_RUNTIME_CONTRACT.md](EXTENSION_RUNTIME_CONTRACT.md),
화면에서 만드는 방법은 [EXPANSION_EDITOR.md](EXPANSION_EDITOR.md)를 참고하세요.

```json
{"schema": 2, "id": "my_pack", "name": "내 확장팩", "version": "1.0", "content": "content.json", "entry_story": "intro"}
```

아래는 v2에서도 유지하는 v1 파일/패치/수치 수정 규격입니다. 새 캐릭터와 스킬을 추가할
때는 `table_edits`로 원작 ID를 덮지 말고 v2 정의를 사용합니다. 두 형식을 동시에 쓰는
전문 프로젝트와 GUI에서 내보내는 정의 전용 프로젝트는 지원 범위가 다릅니다.

## `mod.json`: schema 1

| 키 | 형식 | 의미 |
| --- | --- | --- |
| `schema` | 숫자 `1` | 현재 모드 스키마 |
| `id` | 비어 있지 않은 문자열 | 활성 모드 사이에서 고유해야 함. 소문자 영문·숫자·밑줄 권장 |
| `name`, `version` | 선택적 메타데이터 | 사람이 읽는 설명. 이 값도 manifest 해시에 포함됨 |
| `table_edits` | 선택적 배열 | 기존 item/magic/race 레코드의 지원 필드 편집 |
| `patches` | 선택적 배열 | 논리 JSON 문서에 대한 순차 패치 |

모드 폴더의 `files/`가 파일 오버레이의 시작점입니다. `files/custom/demo.json`은
논리 경로 `custom/demo.json`으로 연결됩니다. 경로에는 `/`를 사용하고 `files/` 접두사는
넣지 않습니다. 절대 경로, `..`, 빈 경로 요소, 심볼릭 링크로 다른 폴더를 참조하는 구성은
지원하지 않습니다. 파일 이름의 대소문자는 맞춰서 작성하세요.

## `table_edits`

```json
{"table": "item", "record": 1, "fields": {"price": 10}}
```

- `table`은 `item`, `magic`, `race` 중 하나입니다.
- `record`는 현재 바이너리에 실제 존재하는 0부터 시작하는 레코드 ID입니다.
- `fields`의 키는 아래 목록과 정확히 같아야 합니다. 대소문자를 바꾸면 다른 키입니다.
- 지원 필드만 편집하며, 완성된 원작 DAT나 `raw_record_hex`를 모드에 넣을 필요가 없습니다.
- 같은 레코드에 대한 여러 편집은 모드 순서, 편집 배열 순서대로 처리합니다.
- JSON에서 정수 값으로 적으세요. 범위를 벗어나거나 정수가 아닌 값은 거부합니다.

| 자료형 | 허용 범위/길이 |
| --- | --- |
| `u16` | `0`부터 `65535` |
| `s16` | `-32768`부터 `32767` |
| `cp949[20]` | CP949로 표현 가능한 문자열, 인코딩 후 최대 19바이트 |
| `cp949[10]` | CP949로 표현 가능한 문자열, 인코딩 후 최대 9바이트 |
| `ascii[12]` | ASCII 문자열, 최대 11바이트 |

문자열 길이는 글자 수가 아닌 인코딩된 바이트 수입니다. 남은 한 바이트는 종료 문자에
사용합니다. 숫자가 저장 가능한 범위라고 해서 모든 값이 의미 있는 게임 정의인 것은 아닙니다.
`raw`가 붙은 선택값과 비트마스크의 새 조합을 임의로 넣기 전에 엔진의 처리 경로를 확인하세요.

### item: 기존 아이템

| 필드 | 자료형 | 의미 |
| --- | --- | --- |
| `name` | `cp949[20]` | 표시 이름 |
| `price` | `u16` | 가격 |
| `effect1`, `effect2` | `s16` | 사용 효과 파라미터. 기존 아이템 종류/처리 방식에 따라 해석 |
| `atk`, `def`, `int`, `mdef`, `agi` | `s16` | 공격·방어·지력·마법 저항력·민첩 보정 |
| `attribute0`, `attribute1`, `attribute2` | `s16` | 속성 채널 값 |
| `target_distance_min_raw`, `target_distance_max_raw` | `u16` | 대상 거리 파라미터 |
| `category` | `u16` | 기존 종류 분류값 |
| `action_visual_selector_raw` | `u16` | 사용/공격 시 시각 처리 선택값 |
| `target_shape_raw` | `u16` | 대상 형상 선택값 |
| `state_code` | `u16` | 기존 상태/장비 특성/치료 처리 코드 |
| `equip_kind_mask` | `u16` | 장착 가능한 유닛 kind의 비트마스크 |

### magic: 기존 스킬/마법 정의

| 필드 | 자료형 | 의미 |
| --- | --- | --- |
| `name` | `cp949[20]` | 표시 이름 |
| `req_level` | `s16` | 요구 레벨 파라미터 |
| `mp` | `s16` | MP 파라미터. 기존 스킬의 처리 맥락 유지 필요 |
| `power`, `power1`, `power2` | `s16` | 세 위력 채널 |
| `v1` | `s16` | `power1`과 같은 저장 필드의 기존 별칭 |
| `target_distance_min_raw` | `s16` | 최소 거리 파라미터 |
| `v2` | `s16` | `target_distance_min_raw`와 같은 필드의 기존 별칭 |
| `target_distance_max_raw` | `s16` | 최대 거리 파라미터 |
| `flag` | `s16` | `target_distance_max_raw`와 같은 필드의 기존 별칭. 일반 Boolean이 아님 |
| `apd_stem` | `ascii[12]` | 연결할 APD 자원의 파일명 stem |
| `sfx_index` | `s16` | 기존 효과음 선택값 |
| `target_mode_raw`, `ai_dispatch_type_raw` | `s16` | 기존 대상 필터/처리 분기 선택값 |
| `learn_kind_mask` | `u16` | 배울 수 있는 유닛 kind의 비트마스크 |
| `effect_name` | `cp949[10]` | 짧은 효과 표시 이름 |

같은 저장 필드를 가리키는 별칭 두 개에 서로 다른 값을 적지 마세요. 예를 들어
`power1`을 쓰면 같은 편집에서 `v1`은 생략합니다. 값만 바꾼다고 기존 엔진에 없는
새 스킬 처리나 새 애니메이션 상태가 자동으로 생성되지는 않습니다.

### race: 기존 클래스/유닛 정의

`race`의 레코드 ID와 실제 유닛의 `kind`는 다른 개념입니다.

| 필드 | 자료형 | 의미 |
| --- | --- | --- |
| `name` | `cp949[20]` | 표시 이름 |
| `experience_value` | `s16` | 기존 경험치 계산에 사용하는 정의값 |
| `hp.initial`, `mp.initial`, `atk.initial`, `def.initial`, `int.initial`, `mdef.initial`, `agi.initial` | `s16` | 각 능력치의 초기 파라미터 |
| `hp.growth`, `mp.growth`, `atk.growth`, `def.growth`, `int.growth`, `mdef.growth`, `agi.growth` | `s16` | 각 능력치의 레벨 증가 파라미터 |
| `attribute0`, `attribute1`, `attribute2` | `s16` | 속성 채널 값 |

점이 들어 있는 키도 하나의 문자열입니다. `"hp.initial": 40`처럼 적으며,
`"hp": {"initial": 40}`처럼 중첩 객체로 바꾸지 않습니다.

## JSON 패치

```json
{
  "target": "custom/demo_settings.json",
  "operations": [
    {"op": "set", "path": "/difficulty", "value": "custom"},
    {"op": "append", "path": "/notes", "value": "직접 작성한 메모"},
    {"op": "remove", "path": "/temporary"}
  ]
}
```

`target`은 `.json`으로 끝나는 논리 경로입니다. 문서를 읽은 뒤 `operations`를 위에서
아래로 적용합니다. 경로는 JSON Pointer 방식으로 `/`로 시작합니다.

| op | 현재 동작 |
| --- | --- |
| `set` | 객체의 마지막 키를 추가/교체하거나 기존 배열 인덱스의 값을 교체 |
| `remove` | 존재하는 객체 키 또는 배열 항목 제거 |
| `append` | `path`가 가리키는 기존 배열의 끝에 `value` 추가 |

중간 부모 객체/배열은 이미 있어야 합니다. 없는 부모를 자동으로 만들지 않습니다.
배열 인덱스는 0부터 시작하며 기존 범위 안이어야 합니다. 이 구현의 `append`는
`/notes`처럼 **배열 자체**를 가리킵니다. `/notes/-` 형태는 사용하지 않습니다.
문서 전체를 가리키는 빈 Pointer를 통한 교체는 지원하지 않습니다.

키 자체에 `/`가 있으면 `~1`, `~`가 있으면 `~0`으로 표기합니다.
존재하지 않는 항목의 제거, 잘못된 인덱스, 배열이 아닌 곳의 append는 실패합니다.

다음 세 테이블 JSON에는 `patches`를 사용할 수 없습니다.

```text
data/port_ready/tables/item.dat.json
data/port_ready/tables/magic.dat.json
data/port_ready/tables/race.dat.json
```

이 항목은 `table_edits`로 바꿔야 규칙용 바이너리와 UI용 값이 함께 바뀝니다.
테이블 JSON 메타데이터만 전체 교체하는 방식도 UI/규칙 불일치를 만들 수 있으므로
일반 모드 제작 방법으로 사용하지 마세요.

## 전문 제작자용: 논리 경로와 소비 필드

아래는 **변환된 개인 캐시**의 엔진 인터페이스입니다. 원작 바이너리의 바이트 오프셋
명세나 데이터 덤프가 아닙니다. 실제 변환은 공개된 자체 변환기 코드를 참고하고,
참조 데이터는 각자 보유한 정품에서 생성하세요.

| 논리 경로 | 역할/필요한 연결 |
| --- | --- |
| `fixtures/item.dat`, `fixtures/magic.dat`, `fixtures/race.dat` | 규칙용 바이너리. 일반 모드는 직접 배포/교체하지 않고 table_edits 사용 |
| `data/port_ready/tables/*.dat.json` | `records`에 ID와 표시/해석 메타데이터. 실제 규칙과 별도로 임의 수정하지 않음 |
| `data/port_ready/tables/stages.json` | 배치 레코드를 읽는 인덱스. 새 배치는 진입 이벤트와 엔진 처리도 필요 |
| `data/port_ready/maps/index.json` | `maps`의 `map_id`, `file`로 정규화 맵 JSON 연결 |
| `assets/indexed/manifest.json` | `images`, `apds`, `maps`를 각 자원 파일에 연결 |
| `data/port_ready/assets/apd/animations/NAME.json` | 논리/연출이 읽는 정규화 애니메이션 |
| `assets/indexed/apd/NAME.json` | 렌더러가 읽는 compact 애니메이션. 정규화 버전과 일관성 필요 |
| `data/port_ready/scripts/normalized/DATA/EVENTNN.json` | 변환된 이벤트의 라벨/명령. 엔진 VM이 지원하는 명령만 사용 |
| `custom/...` | 자신이 추가한 자료의 임의 논리 경로. 엔진/도구의 소비 코드가 있어야 게임 동작에 영향 |

### Indexed 이미지 항목

`assets/indexed/manifest.json`의 `images` 사전에 렌더러가 조회하는 소문자 경로 키를 등록합니다. 각 항목은
`width`, `height`, `indices`, `palette`를 연결합니다. `indices`는 위에서 아래 행 순서의
1바이트 팔레트 인덱스가 `width × height`개인 자료이고, `palette`는 RGB 256색의
768바이트 자료입니다. 이 설명은 독자 제작 이미지의 캐시 형식입니다.

`apds`는 stem에서 compact APD JSON 경로로, `maps`는 문자열 맵 ID에서 compact 맵
JSON 경로로 연결합니다. 새 자료를 추가할 때는 파일만 넣지 말고 필요한 인덱스도
같이 갱신해야 합니다. 원작에서 추출한 픽셀·애니메이션·맵을 예제로 공개하지 마세요.

새 리소스 저작 도구/가져오기 UI나 모든 compact 포맷의 안정된 편집 SDK는 아직 완성된
기능으로 보장하지 않습니다. 단순 가격·MP·능력치 변경은 위의 안정된 `table_edits`로
시작하고, 새 포맷 소비나 엔진 동작이 필요하면 해당 엔진/변환기 기능도 함께 개발하세요.

## 개발 참조

- 모드 마운트/패치/테이블 편집: `game/scripts/content/ft2_content.gd`
- 엔진 데이터 조회 및 UI/바이너리 일치: `game/scripts/data/ft2_data.gd`
- 파일 포맷 파서: `tools/converters/`
- 스키마·우선순위·세이브 분리 검사: `game/tests/test_content.gd`

소스의 라이선스 범위는 [LICENSING.md](../LICENSING.md)를 따릅니다. 이 문서가 원작
데이터에 대한 재배포 허락을 주거나 전체 엔진의 권리 검토를 끝내는 것은 아닙니다.
