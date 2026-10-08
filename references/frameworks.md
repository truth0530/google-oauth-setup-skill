# 프레임워크별 콜백 경로 기본값

아래는 각 라이브러리가 **흔히 쓰는 기본 경로**다. 프로젝트 설정(prefix, basePath, 커스텀 라우트)에 따라 달라지므로 **반드시 코드/설정에서 실제 값을 확인**하고, 콘솔에는 그 값과 글자 그대로 같은 URL을 등록한다. 이 표는 직접 검증한 것이 아니라 일반적인 문서 기준이다(확인 필요).

| 프레임워크 / 라이브러리 | 기본 콜백 경로 | 비고 |
|---|---|---|
| Ruby on Rails + omniauth-google-oauth2 | `/auth/google_oauth2/callback` | `path_prefix` 또는 `callback_path` 옵션으로 바꿀 수 있다. 앱이 하위 경로(`/app`)에 올라가면 접두사가 붙는다. 아래 "Rails + omniauth 상세" 참조 (1회 실측) |
| Next.js + NextAuth v4 / Auth.js | `/api/auth/callback/google` | basePath 설정에 따라 변경 |
| SvelteKit + Auth.js (`@auth/sveltekit`) | `/auth/callback/google` | basePath 기본값이 `/auth` |
| Django + django-allauth | `/accounts/google/login/callback/` | 말단 슬래시 포함이 기본. 슬래시 유무까지 일치시켜야 한다 |
| Express + passport-google-oauth20 | 직접 지정 (예: `/auth/google/callback`) | `callbackURL` 옵션 값을 그대로 등록 |
| Flask + Authlib | 직접 지정 | `redirect_uri` 로 넘기는 값을 그대로 등록 |
| Laravel + Socialite | 직접 지정 (예: `/auth/google/callback`) | `services.php` 의 `redirect` 값 |
| Spring Security (OAuth2 Client) | `/login/oauth2/code/google` | registration id 가 `google` 일 때 |
| Firebase Authentication (웹) | `https://<프로젝트>.firebaseapp.com/__/auth/handler` | 콘솔에서 자동 등록되는 경우가 있음 |

## 일치시켜야 하는 요소

콘솔 등록값과 앱이 실제로 보내는 `redirect_uri`는 아래가 모두 같아야 한다.

- 스킴: `http` / `https`
- 호스트: `www` 유무, 서브도메인
- 포트: 로컬 개발에서 3000, 5173 등
- 경로: 대소문자, 말단 슬래시
- 쿼리 문자열: 포함하지 않는 것이 안전하다

리버스 프록시 뒤에서는 앱이 자신의 스킴을 `http`로 오해해 `redirect_uri`를 `http://...`로 만드는 경우가 흔하다. 앱이 신뢰하는 프록시 헤더(`X-Forwarded-Proto`)나 "SSL 가정" 설정을 확인한다.

## Rails + omniauth 상세 (1회 실측 + 라이브러리 문서)

`omniauth-google-oauth2` 와 `omniauth-rails_csrf_protection` 을 함께 쓰는 구성에서 확인한 내용이다.

실측으로 확인한 것:
- 로그인 시작을 **POST + authenticity_token** 으로 보내면 302 로 구글 인증 주소(`/o/oauth2/auth?...`)에 간다. 토큰은 로그인 페이지의 hidden input(`authenticity_token`)에 있고, 같은 세션 쿠키로 보내야 한다.
- 앱을 하위 경로(예: `/app`) 아래에서 서비스할 때, 시작 경로(`/app/auth/google_oauth2`)와 콜백 경로(`/app/auth/google_oauth2/callback`)에 모두 접두사가 붙게 `path_prefix`(및 필요하면 `callback_path`)를 맞추면 구글로 보내는 `redirect_uri` 가 접두사를 포함한 콜백 전체 URL 이 되고, 그 값을 콘솔에 등록하면 구글이 로그인 화면으로 받아들인다.
- 로그인 버튼이 사용하는 시작 경로도 같은 설정값에서 만들면 불일치를 피할 수 있다(하드코딩 금지).

라이브러리 문서 기준이며 이번에 직접 시도하지 않은 것(미확인):
- `omniauth-rails_csrf_protection` 을 쓰면 GET 으로 시작하는 링크(`link_to`)는 실패하거나 거부된다. 버튼은 `button_to ..., method: :post` 로 만든다.
- `OmniAuth.config.allowed_request_methods` 를 POST 만 허용하도록 두는 구성이 권장된다.

점검: `scripts/check_app_login_start.sh` 가 이 흐름(쿠키+토큰 획득 -> POST -> 302 -> redirect_uri 비교)을 자동으로 확인한다.
