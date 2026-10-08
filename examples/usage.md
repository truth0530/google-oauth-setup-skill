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

등록된 URI 이면 구글 로그인 화면으로, 등록되지 않은 URI 이면 오류 화면으로 보냅니다(1회 실측, 판정은 Location 경로 기준):

```
== 형식 점검 ==
형식 경고 없음
== 구글 응답 점검 ==
RESULT=OK_LOGIN_REDIRECT          # 등록됨
# 또는
RESULT=REJECTED                   # 거부됨(관찰된 원인: 미등록 redirect_uri)
```

## 4. 비밀 파일 확인 (값 노출 없음)

```bash
scripts/check_secrets_file.sh --file .env.local --email-key ADMIN_EMAILS
# 키마다 상태/길이/형식/지문과 파일 권한(600), git 무시 여부를 출력합니다. 값은 출력하지 않습니다.
```

## 5. 앱 배포 후 로그인 시작 스모크 검사

```bash
scripts/check_app_login_start.sh \
  --login-url https://app.example.com/login \
  --action-url https://app.example.com/auth/google_oauth2 \
  --expected-redirect-uri https://app.example.com/auth/google_oauth2/callback
# RESULT=OK_APP_LOGIN_START 이면 앱 -> 구글 로그인 화면까지 정상입니다.
# 실제 계정 로그인과 허용 목록 밖 계정의 거부는 사람이 한 번 확인하세요.
```
