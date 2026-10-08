# 프레임워크별 콜백 경로 기본값

아래는 각 라이브러리가 **흔히 쓰는 기본 경로**다. 프로젝트 설정(prefix, basePath, 커스텀 라우트)에 따라 달라지므로 **반드시 코드/설정에서 실제 값을 확인**하고, 콘솔에는 그 값과 글자 그대로 같은 URL을 등록한다. 이 표는 직접 검증한 것이 아니라 일반적인 문서 기준이다(확인 필요).

| 프레임워크 / 라이브러리 | 기본 콜백 경로 | 비고 |
|---|---|---|
| Ruby on Rails + omniauth-google-oauth2 | `/auth/google_oauth2/callback` | `path_prefix` 또는 `callback_path` 옵션으로 바꿀 수 있다. 앱이 하위 경로(`/app`)에 올라가면 접두사가 붙을 수 있다 |
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
