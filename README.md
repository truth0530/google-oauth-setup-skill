# google-oauth-setup

구글 OAuth 2.0 웹 클라이언트("구글로 로그인")를 처음 붙일 때 사람들이 가장 자주 막히는 지점을 줄이기 위한 Claude Code 스킬입니다. 콘솔에서 클라이언트를 만드는 순서, 안전 규칙, 비밀 없이 쓰는 점검 스크립트, 브라우저 에이전트에게 맡길 때의 프롬프트 템플릿을 담았습니다.

> 상태: 초안(v0.2.0). 구글 응답 판정(Location 경로), 앱 로그인 시작 흐름, 비밀 파일 검증은 1회 실사용으로 확인했습니다. 콘솔 메뉴 경로와 프로젝트 생성 제한 등은 아직 검증되지 않았습니다. 확인된 것과 추측은 문서에서 구분해 표시합니다(SKILL.md 의 "검증 상태"). 실사용 피드백으로 보강할 예정입니다.

## 줄이려는 병목

- `redirect_uri_mismatch`: http/https, www, 포트, 말단 슬래시 불일치
- 동의 화면 테스트/프로덕션 상태 혼동, 테스트 사용자 누락으로 인한 `access_denied`
- **기존 서비스의 프로젝트/동의 화면을 건드려 기존 로그인이 영향받는 사고** (앱마다 새 프로젝트를 권장)
- 클라이언트 Secret의 채팅/로그/커밋 노출

## 구성

```
SKILL.md                          스킬 본문 (사전 질문, 절차, 안전 규칙, 검증 상태)
references/frameworks.md          프레임워크별 콜백 경로 기본값
references/errors.md              오류 코드와 해결표
references/publishing-and-scopes.md  게시 상태와 범위
scripts/check_redirect_uri.sh     비밀 없이 URI 형식/등록 여부 점검 (구글 응답의 Location 경로로 판정)
scripts/check_app_login_start.sh  앱의 로그인 시작 흐름 스모크 검사 (쿠키+토큰 -> POST -> 구글 이동 -> redirect_uri 일치)
scripts/check_secrets_file.sh     값 노출 없이 비밀 파일의 형식, 권한(600), 지문 확인
scripts/write_secrets.sh          비밀을 출력 없이 gitignored 파일의 지정 키에만 기록
docs/AGENT_BROWSER_NOTES.md       브라우저 에이전트용 프롬프트 템플릿, 흔한 막힘, 관찰 기록
examples/                         가상 값 사용 예
tests/                            스크립트 시험
```

## 설치

Claude Code 스킬 디렉터리에 이 폴더를 연결합니다.

```bash
ln -s "$(pwd)" ~/.claude/skills/google-oauth-setup   # 심볼릭 링크
# 또는 복사: cp -R . ~/.claude/skills/google-oauth-setup
```

## 시험

```bash
for t in tests/*.sh; do bash "$t" || break; done
shellcheck scripts/*.sh tests/*.sh      # 설치되어 있다면
```

시험은 모의 응답과 임시 디렉터리만 사용하며 구글에 접속하지 않습니다.

## 안전 원칙 요약

1. 기존 서비스가 쓰는 프로젝트, 클라이언트, 동의 화면은 수정/재사용하지 않는다. 앱마다 새 프로젝트.
2. Secret은 출력, 로그, 채팅, 커밋 금지. gitignored 파일이나 비밀 관리자에만.
3. 리디렉션 URI는 필요한 것만 정확히 한 줄씩.
4. 막히면 변경 없이 멈추고 사유만 보고.

## 한계

- `check_redirect_uri.sh` 의 판정은 구글 응답의 `Location` 경로에 의존합니다. 등록된 URI 와 미등록 URI 두 경우만 1회 실측했고, 존재하지 않는 client_id 등 나머지는 미확인(`UNKNOWN`)입니다. 구글이 응답 방식을 바꾸면 틀릴 수 있으니 판정 불가 시 브라우저로 직접 확인하세요.
- `check_app_login_start.sh` 는 서버 렌더링 앱의 "로그인 페이지 GET -> POST 시작" 구성을 기준으로 합니다. 다른 구성은 `--token-field`, `--no-csrf` 로 맞추거나 직접 확인하세요.
- 비밀 형식 기준(`check_secrets_file.sh`)은 관찰한 값의 모양이며 구글이 바꿀 수 있습니다.
- 구글 정책, 한도, 메뉴 이름은 바뀔 수 있습니다. `(확인 필요)` 표시를 공식 문서로 확인하세요.
- 이 스킬은 구글 로그인 "설정"을 돕습니다. 앱 쪽 인증 코드(세션 관리, CSRF 등)는 다루지 않습니다.

## English summary

A Claude Code skill that helps an agent (or a person) set up a Google OAuth 2.0 web client safely and quickly: create a dedicated project, configure the consent screen and minimal scopes, add test users, create the web client with exact origins/redirect URIs, and record the client ID/secret without ever printing the secret. It ships a no-secret redirect-URI checker (`scripts/check_redirect_uri.sh`), a safe secret writer (`scripts/write_secrets.sh`), error/scope/publishing references, framework callback tables, and prompt templates for browser agents. Status: draft v0.2.0 - the Google response classification (redirect to the sign-in path when the redirect URI is registered, to the oauth error path when it is not), the app login-start smoke check and the secrets-file check come from one real run; console menu paths and other Google responses are still marked "to be verified". It also ships `scripts/check_app_login_start.sh` (cookie + CSRF token -> POST -> Google redirect check) and `scripts/check_secrets_file.sh` (format/permission/fingerprint check without printing values). Contributions with real-world observations are welcome (see `CONTRIBUTING.md`). License: MIT.
