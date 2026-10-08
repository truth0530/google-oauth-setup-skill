---
name: google-oauth-setup
description: Use when the user needs to create or fix a Google OAuth 2.0 web client (Sign in with Google) in Google Cloud Console - choosing/creating a project, configuring the OAuth consent screen and scopes, adding test users, creating the web application client, entering authorized JavaScript origins and redirect URIs, and recording the client ID/secret safely. Also use for redirect_uri_mismatch, invalid_client, access_denied, origin_mismatch errors. 구글 OAuth 클라이언트 만들기, 동의 화면, 리디렉션 URI 등록, 구글 로그인 오류 해결.
metadata:
  version: "0.2.0"
  date: "2026-10-08"
  status: "초안 - 1회 실사용 관찰 반영, 나머지는 피드백으로 보강 예정"
---

# google-oauth-setup

구글 로그인(OAuth 2.0 웹 애플리케이션 클라이언트)을 처음 붙이거나 오류를 고칠 때, 같은 실수를 반복하지 않도록 순서와 안전 규칙을 정리한 스킬이다.

콘솔 화면과 메뉴 이름은 자주 바뀐다. 이 문서의 메뉴 경로 중 `(확인 필요)` 표시는 직접 검증하지 못한 것이므로, 실제 화면과 다르면 화면을 따른다. 상세 근거와 표는 `references/`에 있다.

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

1. **프로젝트**: 새 프로젝트를 만든다. 이름은 앱을 알아볼 수 있게(예: `my-app-auth`). 조직/결제 제한이 있으면 멈추고 보고한다.
2. **OAuth 동의 화면(또는 브랜딩/대상 설정) 구성** (메뉴 경로: 확인 필요 - 최근 콘솔은 "Google Auth Platform"의 브랜딩, 대상, 데이터 액세스, 클라이언트 메뉴로 나뉘는 것으로 알려짐)
   - 앱 이름, 지원 이메일, 개발자 연락처 이메일
   - 사용자 유형: 일반 계정 대상이면 외부(External). 조직 내부 전용이면 내부(Internal, Workspace 필요)
   - 범위: 로그인만 필요하면 `openid`, `email`, `profile` 중 필요한 것만. 이 세 가지는 민감하지 않은 범위로 알려져 있다 (`references/publishing-and-scopes.md`)
   - 게시 상태가 **테스트**이면 **테스트 사용자에 로그인할 계정을 모두 추가** (빠뜨리면 `access_denied`)
3. **클라이언트 생성**: 유형 "웹 애플리케이션", 이름은 용도가 보이게.
   - 승인된 JavaScript 원본: 스킴+호스트(+포트)만. 경로 없음. 말단 슬래시 없음. 예: `https://app.example.com`
   - 승인된 리디렉션 URI: 콜백 전체 URL을 **글자 그대로** 한 줄. 예: `https://app.example.com/auth/google_oauth2/callback`
   - 순수 서버측 코드 흐름만 쓰면 JavaScript 원본은 비워도 되는 경우가 많다 (라이브러리 문서 확인)
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
   - `REJECTED`: 구글이 조합을 거부. 관찰된 원인은 미등록 redirect_uri(말단 슬래시 추가, 다른 경로). 글자 단위로 비교하고, client_id 가 이 프로젝트 것인지 확인. 저장 직후면 반영 지연 가능
   - `OK_*`: 조합은 받아들여짐. 단, 테스트 사용자 누락 등은 이 점검으로 알 수 없다
   - `UNKNOWN`: 응답 형태를 모른다(존재하지 않는 client_id 등은 미확인). 추측하지 말고 브라우저로 직접 확인
7. **앱에 값 주입 후 로그인 시작 스모크 검사**: 앱을 배포/재시작한 뒤
   ```bash
   scripts/check_app_login_start.sh --login-url https://app.example.com/login \
     --action-url https://app.example.com/auth/google_oauth2 \
     --expected-redirect-uri https://app.example.com/auth/google_oauth2/callback
   ```
   - 로그인 페이지에서 세션 쿠키와 CSRF 토큰을 얻고 POST 로 로그인을 시작해, 302 로 구글 인증 주소에 가는지, `redirect_uri` 가 기대 값과 같은지, `client_id` 가 채워졌고 형식이 맞는지(자리표시값 주입 감지), 그 주소를 구글이 로그인 화면으로 받아들이는지 확인한다. 비밀은 필요 없고 `client_id` 값은 출력하지 않는다.
   - 시작이 GET 이거나 토큰 필드 이름이 다르면 `--token-field`, `--no-csrf` 를 쓴다.
8. **실제 로그인 1회 시험(사람)**: 허용 계정으로 성공, 허용 목록에 없는 계정으로 거부되는지 확인. 스모크 검사는 이 단계를 대신하지 못한다.
9. **마무리**: Secret이 어디에도 남지 않았는지(셸 기록, 로그, 채팅) 확인하고, 사용한 프로젝트 이름과 등록한 URI 목록만 보고한다.

## 검증 상태 (정직하게)

### 실측 확인됨 (1회 관찰, 2026-10-08)

| 항목 | 내용 |
|---|---|
| 등록 여부 판정 | 쿠키 없이 인증 엔드포인트를 한 번 호출하면 등록된 정확한 URI 는 302 + 로그인 화면 경로, 미등록 URI(말단 슬래시 추가, 다른 경로)는 302 + 오류 화면 경로. `check_redirect_uri.sh` 가 이 기준으로 판정 |
| 앱의 로그인 시작 흐름 | 로그인 페이지 GET(쿠키+토큰) -> POST 로 시작 -> 302 로 구글 인증 주소, `redirect_uri` 일치, 그 주소는 다시 302 로 로그인 화면. `check_app_login_start.sh` 가 이 흐름을 자동화 |
| Rails omniauth 계열 | POST + authenticity_token 으로 시작하면 정상 동작, 하위 경로 배포에서 콜백 경로와 `path_prefix` 에 접두사를 맞춰 정상 동작 (GET 시작이 실패한다는 점은 라이브러리 문서 기준이며 직접 시도하지 않아 미확인) (`references/frameworks.md`) |
| 브라우저 에이전트(Aside CLI) 운용 | 출력 파이프로 CLI 가 먼저 끝나도 세션은 계속 running, 임시 세션은 앱 목록에 안 보임, 진행 내용은 CLI 로 안 보임, 기존 프로젝트 재사용 시도 (`docs/AGENT_BROWSER_NOTES.md`) |
| 비밀 파일 검증 | 값 대신 길이, 형식, 지문으로 확인 가능. 에이전트가 만든 파일 권한이 600 이 아니었음 |
| `scripts/write_secrets.sh` | 시험 통과 (임시 디렉터리) |

위 항목은 모두 1회 관찰이다. 다른 환경에서 다르게 나올 수 있다.

### 미확인 (직접 확인하지 못함)

| 항목 | 비고 |
|---|---|
| 콘솔 메뉴 경로와 화면 이름 | `확인 필요` 표시. 자동화 에이전트의 세부 진행은 볼 수 없었다 |
| 에이전트가 새 프로젝트를 실제로 만들었는지 | 결과 파일의 변화만 확인. 프로젝트 목록은 사람이 콘솔에서 확인해야 함 |
| 존재하지 않는 client_id, 삭제된 클라이언트, 동의 화면 불량 시 응답 형태 | `UNKNOWN` 으로 분류 |
| 반영 지연 시간, 프로젝트 생성 한도/조직 정책, 테스트 상태 만료와 사용자 한도 | 일반 지식. 공식 문서로 재확인 |
| 오류 코드 표, 범위 분류, 프레임워크 콜백 표(Rails 외) | 일반 지식 기반 |
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
- `references/frameworks.md`: 프레임워크별 콜백 경로 기본값
- `references/errors.md`: 오류 코드와 해결표
- `references/publishing-and-scopes.md`: 테스트/프로덕션 게시 상태, 범위와 앱 검증
- `docs/AGENT_BROWSER_NOTES.md`: 브라우저 에이전트에게 맡길 때의 프롬프트 템플릿과 흔한 막힘
- `examples/`: 가상 값을 쓴 사용 예
