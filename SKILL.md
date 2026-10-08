---
name: google-oauth-setup
description: Use when the user needs to create or fix a Google OAuth 2.0 web client (Sign in with Google) in Google Cloud Console - choosing/creating a project, configuring the OAuth consent screen and scopes, adding test users, creating the web application client, entering authorized JavaScript origins and redirect URIs, and recording the client ID/secret safely. Also use for redirect_uri_mismatch, invalid_client, access_denied, origin_mismatch errors. 구글 OAuth 클라이언트 만들기, 동의 화면, 리디렉션 URI 등록, 구글 로그인 오류 해결.
metadata:
  version: "0.3.0"
  date: "2026-10-08"
  status: "초안 - 1회 실사용 관찰과 실제 구글 대상 스크립트 실행 반영, 나머지는 피드백으로 보강 예정"
---

# google-oauth-setup

구글 로그인(OAuth 2.0 웹 애플리케이션 클라이언트)을 처음 붙이거나 오류를 고칠 때, 같은 실수를 반복하지 않도록 순서와 안전 규칙을 정리한 스킬이다.

콘솔 화면과 메뉴 이름은 자주 바뀐다. 이 문서의 메뉴 경로는 한국어 UI(2026-10)에서 1회 관찰한 것이고 `(확인 필요)` 표시는 직접 검증하지 못한 것이므로, 실제 화면과 다르면 화면을 따른다. 관찰한 화면 기록은 `references/console-ui.md`, 나머지 근거와 표는 `references/`에 있다.

## 안전 규칙 (반드시)

1. **기존 서비스가 쓰는 프로젝트, 클라이언트, 동의 화면은 수정하지 않고 재사용하지 않는다.** 같은 프로젝트의 동의 화면 앱 이름과 범위는 그 프로젝트의 모든 클라이언트 로그인 화면에 그대로 보인다. 기존 앱의 로그인에 영향이 갈 수 있으므로 **앱마다 새 프로젝트를 만드는 것을 권장**한다. 기존 프로젝트는 조회만 한다.
2. **클라이언트 Secret은 출력, 로그, 채팅, 커밋에 쓰지 않는다.** 비밀 관리자나 git이 무시하는 파일에만 기록한다 (`scripts/write_secrets.sh`). 클라이언트 ID는 공개 값이지만 불필요하게 퍼뜨리지 않는다.
3. **리디렉션 URI는 필요한 것만, 정확히 한 줄씩 등록한다.** 와일드카드나 "혹시 몰라서" 여분의 URI를 넣지 않는다.
4. **막히면 변경 없이 멈추고 사유만 보고한다.** 결제 계정 요구, 조직 정책 제한, 2단계 인증, 권한 부족 등. 우회하지 않는다.
5. **사람의 최종 확인이 필요한 것**: 게시 상태를 "프로덕션"으로 바꾸기, 민감/제한 범위 추가, 프로젝트 삭제.

## 사전 질문 (시작 전에 확인)

| 질문 | 예 | 왜 필요한가 |
|---|---|---|
| 앱의 공개 주소(스킴 포함) | `https://app.example.com` | JavaScript 원본과 콜백 URI의 기준 |
| 콜백 경로 | `/auth/google_oauth2/callback` | 프레임워크 기본값이 다르다 (`references/frameworks.md`) |
| 프레임워크/라이브러리 | Rails + omniauth-google-oauth2 | 콜백 경로 기본값 확인 |
| 로그인을 허용할 계정 | 관리자 1~3명의 구글 이메일 | 테스트 사용자 등록, 앱 내 허용 목록 |
| 로컬 개발 주소도 필요한가 | `http://localhost:3000` | 개발용 URI는 별도 한 줄로 추가 |
| 기존에 쓰던 프로젝트가 있는가 | 있음/없음 | 있어도 **새 프로젝트를 권장** (안전 규칙 1) |

## 절차 체크리스트

1. **프로젝트**: 새 프로젝트를 만든다. 이름은 앱을 알아볼 수 있게(예: `my-app-auth`). 조직/결제 제한이 있으면 멈추고 보고한다. 개인 계정에서는 `프로젝트 할당량이 N개 남았습니다` 경고가 보일 수 있으며(관찰), 이 경고만으로는 생성이 막히지 않았다.
2. **OAuth 동의 화면 구성** (한국어 UI 관찰: 상단 탐색 메뉴 > 즐겨 찾는 제품 > API 및 서비스 > OAuth 동의 화면 을 누르면 `Google 인증 플랫폼` 으로 이동하고, 좌측에 개요, 브랜딩, 대상, 클라이언트, 데이터 액세스, 인증 센터, 설정이 있다. 구 UI 와의 대응은 `references/console-ui.md`)
   - 앱 이름, 지원 이메일, 개발자 연락처 이메일 (`브랜딩`)
   - 사용자 유형: 일반 계정 대상이면 외부(External). 조직이 없는 계정에서는 `내부로 설정` 이 비활성이었다 (`대상`)
   - 범위: 로그인만 필요하면 `openid`, `email`, `profile` 중 필요한 것만 (`데이터 액세스`). 이메일 범위 하나만 추가했을 때 민감/제한 범위는 비어 있었다 (`references/publishing-and-scopes.md`)
   - 게시 상태가 **테스트**이면 **테스트 사용자에 로그인할 계정을 모두 추가** (`대상`, 빠뜨리면 `access_denied`). 추가 절차 자체는 확인 필요
   - **이메일 허용 목록은 두 곳에 있다**: 콘솔의 테스트 사용자와 앱 쪽 허용 목록(예: 환경변수). 로그인하려면 둘 다에 있어야 한다. 한쪽만 추가하고 "안 된다"고 하는 일이 흔하다.
3. **클라이언트 생성**: 유형 "웹 애플리케이션", 이름은 용도가 보이게 (`클라이언트`).
   - 승인된 JavaScript 원본: 스킴+호스트(+포트)만. 경로 없음. 말단 슬래시 없음. 예: `https://app.example.com`
   - 승인된 리디렉션 URI: 콜백 전체 URL을 **글자 그대로** 한 줄. 예: `https://app.example.com/auth/google_oauth2/callback`
   - 순수 서버측 코드 흐름만 쓰면 JavaScript 원본은 비워도 되는 경우가 많다 (라이브러리 문서 확인, 미확인)
   - **비밀은 생성 직후 한 번만 저장한다.** 생성 후 상세 화면에는 `더 이상 보거나 다운로드할 수 없습니다` 라고 표시된다(관찰). 놓치면 새 비밀을 만들어야 한다(절차는 확인 필요).
4. **비밀 기록**: 클라이언트 ID/Secret을 `scripts/write_secrets.sh`로 gitignored 파일에 쓴다. 화면에 출력하지 않는다.
   ```bash
   printf '%s' "$CLIENT_SECRET_VALUE" | scripts/write_secrets.sh --file .env.local --key GOOGLE_CLIENT_SECRET
   ```
   - 에이전트가 파일을 직접 편집했다면 아래 4-1을 반드시 한다(권한이 600 이 아니었던 사례가 있다).
4-1. **값 노출 없이 확인**: `scripts/check_secrets_file.sh --file .env.local --email-key ADMIN_EMAILS`
   - 키마다 상태(SET/EMPTY/PLACEHOLDER/MISSING), 길이, 형식 판정, 지문(SHA-256 앞 8자리)만 출력한다. 값은 출력하지 않는다.
   - 형식 기준(관찰값): 클라이언트 ID 는 숫자로 시작해 하이픈, 문자열, 그 뒤에 구글 고정 도메인 접미사가 붙는 모양. Secret 은 고정 접두사 + 관찰 길이 35자. 구글이 바꾸면 WARN 이 날 수 있다.
   - 파일 권한이 600 이 아니면 문제로 보고한다. 해결: `chmod 600 <파일>`. git 이 무시하는 파일인지도 확인한다.
   - 지문은 나중에 "에이전트 세션이 끝난 뒤 파일이 바뀌었는지"를 값 노출 없이 비교하는 데 쓴다.
5. **형식 점검(네트워크 없음)**: `scripts/check_redirect_uri.sh --lint-only --redirect-uri <URI>`
6. **등록 점검(비밀 없이)**: `scripts/check_redirect_uri.sh --client-id <공개 ID> --redirect-uri <URI>`
   - 판정은 구글 응답의 `Location` 경로가 1순위다(실측): 등록된 정확한 URI 는 로그인 화면 경로, 등록되지 않은 URI 는 오류 화면 경로(`/signin/oauth/error`)로 302 된다. 400 본문을 기대하지 않는다.
   - `REJECTED`: 구글이 조합을 거부. **원인은 응답만으로 구분할 수 없다(실측)**: 미등록 redirect_uri(말단 슬래시 추가, 다른 경로)이든 존재하지 않는 client_id 이든 같은 오류 경로로 간다. URI 를 콘솔 값과 글자 단위로 비교하고, client_id 를 클라이언트 상세의 값과 대조한다. 저장 직후면 반영 지연 가능
   - `OK_*`: 조합은 받아들여짐. 단, 테스트 사용자 누락 등은 이 점검으로 알 수 없다
   - `UNKNOWN`: 응답 형태를 모른다(삭제된 클라이언트, 동의 화면 불량 등은 미확인). 추측하지 말고 브라우저로 직접 확인
7. **앱에 값 주입 후 로그인 시작 스모크 검사**: 앱을 배포/재시작한 뒤
   ```bash
   scripts/check_app_login_start.sh --login-url https://app.example.com/login \
     --action-url https://app.example.com/auth/google_oauth2 \
     --expected-redirect-uri https://app.example.com/auth/google_oauth2/callback
   ```
   - 로그인 페이지에서 세션 쿠키와 CSRF 토큰을 얻고 POST 로 로그인을 시작해, 302 로 구글 인증 주소에 가는지, `redirect_uri` 가 기대 값과 같은지, `client_id` 가 채워졌고 형식이 맞는지(자리표시값 주입 감지), 그 주소를 구글이 로그인 화면으로 받아들이는지 확인한다. 비밀은 필요 없고 `client_id` 값은 출력하지 않는다.
   - Rails omniauth 에서는 시작 경로로 GET 하면 404, 토큰 없는 POST 는 422, 토큰이 있는 POST 만 구글로 302 가 실측되었다. 시작 방식이 다른 프레임워크면 `--token-field`, `--no-csrf` 를 쓴다.
8. **실제 로그인 1회 시험(사람)**: 허용 계정으로 성공, 허용 목록에 없는 계정으로 거부되는지 확인. 스모크 검사는 이 단계를 대신하지 못한다.
9. **사후 검증 (말이 아니라 기록과 응답으로)**
   1. **새 프로젝트 확인**: 내 프로젝트가 정말 이번에 새로 만들어졌는지. 프로젝트 목록에는 생성일 열이 없으므로 `gcloud projects list --format="table(name,projectId,createTime)"` 또는 프로젝트 활동 로그의 `CreateProject` 시각으로 확인한다.
   2. **다른 프로젝트 비변경 확인**: 같은 계정의 다른 프로젝트 클라이언트 관련 감사 로그를 오늘 날짜로 조회해 결과가 0개인지 확인한다. 클라이언트 목록에는 `마지막 수정` 열이 없다.
   3. **클라이언트 설정 일치**: 클라이언트 상세의 승인된 JavaScript 원본과 리디렉션 URI 목록이 계획한 값과 정확히 같은지(여분 없음) 읽어서 대조한다 (조회만).
   4. **스크립트로 구글 응답 확인**: 6번과 7번을 다시 실행해 `OK_*`, `OK_APP_LOGIN_START` 인지 확인한다.
10. **마무리**: Secret이 어디에도 남지 않았는지(셸 기록, 로그, 채팅) 확인하고, 사용한 프로젝트 이름과 등록한 URI 목록만 보고한다.

## 검증 상태 (정직하게)

모든 항목은 1회 관찰이다(2026-10-08, 한국어 UI, 개인 계정, 조직 없음). 다른 환경에서 다르게 나올 수 있다.

### 확인됨 (확인 방법별)

| 항목 | 내용 | 확인 방법 |
|---|---|---|
| 등록된 URI 판정 | 쿠키 없이 인증 엔드포인트를 한 번 호출하면 302 + 로그인 화면 경로 | 스크립트를 실제 구글에 실행 (`OK_LOGIN_REDIRECT`) |
| 미등록 URI 판정 | 말단 슬래시를 붙인 URI 는 302 + 오류 화면 경로 | 스크립트를 실제 구글에 실행 (`REJECTED`) |
| 존재하지 않는 client_id | 형식만 유효한 가짜 ID 도 같은 오류 화면 경로 -> **미등록 URI 와 구분 불가** | 스크립트를 실제 구글에 실행 (`REJECTED`) |
| 앱 로그인 시작 흐름 | 쿠키+토큰 획득, POST, 302 로 구글, `redirect_uri` 일치, 구글이 로그인 화면으로 받아들임 | `check_app_login_start.sh` 를 실제 Rails 앱에 실행 (`OK_APP_LOGIN_START`) |
| Rails omniauth 시작 방식 | 시작 경로 GET 은 404, 토큰 없는 POST 는 422, 토큰이 있는 POST 만 302 | 실제 앱에 curl 로 각각 요청 |
| 하위 경로 배포 | 시작/콜백 경로에 접두사를 맞추면 구글이 받아들임 | 실제 앱 + 구글 응답 |
| 콘솔 메뉴 이름과 경로 | `Google 인증 플랫폼` 과 좌측 7개 항목, 클라이언트 URL 형태 | 브라우저 에이전트가 화면을 읽어 보고 (`references/console-ui.md`) |
| 동의 화면 상태 값 | 외부, 테스트 중, 범위 하나, 테스트 사용자 한도 100명, 내부 비활성(조직 없음) | 브라우저 에이전트가 화면을 읽어 보고 |
| 테스트 상태 만료 문구 | 콘솔 화면에는 없고 영문 도움말에 7일 문구(원문 인용) | 브라우저 에이전트가 링크된 도움말을 읽어 보고. 만료를 직접 겪지는 않음 |
| 비밀 재열람 불가 | 상세 화면에 `더 이상 보거나 다운로드할 수 없습니다` | 브라우저 에이전트가 화면을 읽어 보고 |
| 새 프로젝트 생성 | 에이전트가 새 프로젝트를 만들었음. 생성 시각이 지시 직후 | `gcloud projects list` 의 생성 시각, 활동 로그 `CreateProject` |
| 다른 프로젝트 비변경 | 다른 프로젝트 클라이언트 감사 로그 오늘 결과 0개 | 브라우저 에이전트가 활동 로그를 읽어 보고 |
| 프로젝트 생성 제한 | 할당량 경고만, 조직 정책/결제 문구 없음, 생성 성공 | 브라우저 에이전트가 새 프로젝트 화면을 읽고 취소 |
| 브라우저 에이전트 운용 | 출력 파이프로 CLI 만 종료, 임시 세션 비표시, 진행 내용 비공개, 기존 프로젝트 재사용 시도와 steer 로 해결 | 세션 상태와 결과 파일 변화 (`docs/AGENT_BROWSER_NOTES.md`) |
| 비밀 파일 검증 | 값 대신 길이, 형식, 지문으로 확인 가능. 에이전트가 만든 파일 권한이 600 이 아니었음 | `check_secrets_file.sh` 실행 |
| `scripts/write_secrets.sh` | 시험 통과 | 임시 디렉터리 |

### 미확인 (직접 확인하지 못함)

| 항목 | 비고 |
|---|---|
| 영어 UI 의 메뉴 이름 | 한국어 UI 만 확인 |
| 새 비밀 생성 절차 | 재열람이 안 되는 것까지만 확인 |
| 테스트 사용자 추가의 실제 절차 | 메뉴 이름(`대상`)만 확인 |
| 프로덕션 게시 시 변화 | 게시하지 않음 |
| 조직이 있는 계정의 정책/결제 영향 | 조직 없는 개인 계정만 관찰 |
| 구글 오류 화면의 본문 문구 | 스크립트는 오류 화면 경로까지만 봄. 브라우저에서 보이는 문구는 확인하지 못함 |
| 삭제된 클라이언트, 동의 화면 불량 시 응답 | `UNKNOWN` 으로 분류될 수 있음 |
| 반영 지연 시간 | 일반 지식 |
| 갱신 토큰 없는 세션 로그인에서 7일 만료가 어떻게 보이는지 | 만료를 겪지 않음 |
| 비Rails 프레임워크 콜백 경로 표 | 일반 지식 기반 |
| 활동 로그를 여는 정확한 메뉴 경로 | 이벤트 이름과 시각만 확인 |
| 이 스킬을 처음 보는 다른 사용자의 막힘 | 관찰 기록에 쌓아야 함 |

## 실사용 피드백

- 확인된 사실은 위 "실측 확인됨" 표와 `docs/AGENT_BROWSER_NOTES.md` 의 관찰 기록 표다.
- 추측은 "미확인" 표에만 둔다.
- 기록 방법: 관찰 기록 표에 날짜, 도구, 막힌 단계, 해결 방법, 소요 시간을 추가한다. 확인되지 않은 것은 "미확인"으로 적는다.

## 참고 파일

- `scripts/check_redirect_uri.sh`: 비밀 없이 URI 형식과 등록 여부 점검 (Location 경로 판정)
- `scripts/check_app_login_start.sh`: 앱의 로그인 시작 흐름 스모크 검사
- `scripts/check_secrets_file.sh`: 값 노출 없이 비밀 파일 형식, 권한, 지문 확인
- `scripts/write_secrets.sh`: 비밀을 출력 없이 지정 키에만 기록
- `references/console-ui.md`: 콘솔 화면 실측 기록(메뉴 경로, 동의 화면 상태, 비밀 재열람 불가, 활동 로그 검증)
- `references/frameworks.md`: 프레임워크별 콜백 경로 기본값
- `references/errors.md`: 오류 코드와 해결표
- `references/publishing-and-scopes.md`: 테스트/프로덕션 게시 상태, 범위와 앱 검증
- `docs/AGENT_BROWSER_NOTES.md`: 브라우저 에이전트에게 맡길 때의 프롬프트 템플릿과 흔한 막힘
- `examples/`: 가상 값을 쓴 사용 예
