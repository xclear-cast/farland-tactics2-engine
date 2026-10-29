# 자체 JSON 파일 추가와 패치 예제

`files/custom/demo_settings.json`을 논리 경로 `custom/demo_settings.json`으로
추가한 뒤 같은 모드의 JSON 패치를 순서대로 적용합니다.

적용 결과는 다음과 같습니다.

- `difficulty`가 `custom`으로 바뀜
- `show_hint`가 `true`로 바뀜
- `notes` 배열 끝에 자체 작성 문장이 추가됨
- `temporary` 키가 제거됨

**이 예제 자체는 게임 난이도를 바꾸거나 화면에 새로운 창을 띄우지 않습니다.**
임의 JSON을 읽어 사용할 엔진/도구 코드가 있어야 실제 게임 기능이 됩니다.
파일 추가와 `set`/`append`/`remove` 형식을 익히기 위한 자료입니다.

이 폴더를 모드 목록에 넣어 연결하면 로더가 파일과 패치를 검증합니다.
[모드 제작 안내](../../docs/MODDING.md)와 [규격](../../docs/FORMATS.md)을 참고하세요.
