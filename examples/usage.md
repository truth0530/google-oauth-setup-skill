# 사용 예 (가상 값)

앱 주소 `https://app.example.com`, Rails + omniauth-google-oauth2 를 쓰는 경우.

## 1. 등록할 값

- 승인된 JavaScript 원본: `https://app.example.com`
- 승인된 리디렉션 URI: `https://app.example.com/auth/google_oauth2/callback`
- 로컬 개발을 함께 쓴다면 별도 한 줄: `http://localhost:3000/auth/google_oauth2/callback`

## 2. 비밀 기록 (값은 출력되지 않는다)

```bash
printf '%s' "$GOOGLE_CLIENT_ID_VALUE"     | scripts/write_secrets.sh --file .env.local --key GOOGLE_CLIENT_ID
printf '%s' "$GOOGLE_CLIENT_SECRET_VALUE" | scripts/write_secrets.sh --file .env.local --key GOOGLE_CLIENT_SECRET
printf '%s' "you@example.com"             | scripts/write_secrets.sh --file .env.local --key ADMIN_EMAILS
```

## 3. 점검

```bash
scripts/check_redirect_uri.sh --lint-only --redirect-uri 'https://app.example.com/auth/google_oauth2/callback'
scripts/check_redirect_uri.sh --client-id "$GOOGLE_CLIENT_ID_VALUE" --redirect-uri 'https://app.example.com/auth/google_oauth2/callback'
```

예상 출력 형태 (설명용이며 실제 구글 응답으로 검증된 출력이 아니다):

```
== 형식 점검 ==
형식 경고 없음
== 구글 응답 점검 ==
RESULT=OK_LOGIN_REDIRECT
구글 로그인 화면으로 넘어갑니다. ...
```
