#!/usr/bin/env bash
# check_app_login_start.sh 를 모의 curl 로 시험한다. 실제 네트워크에 접속하지 않는다.
# shellcheck disable=SC2015,SC2001,SC2181,SC1091,SC1090
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/check_app_login_start.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; failn=0

# 가상 값만 쓴다. 접미사는 조각으로 조립한다.
SUF=".apps"".googleusercontent"".com"
GOOD_ID="12345-testclient${SUF}"
EXPECTED="https://app.example.com/auth/google_oauth2/callback"
ENC_EXPECTED="https%3A%2F%2Fapp.example.com%2Fauth%2Fgoogle_oauth2%2Fcallback"

# --- 모의 curl: 시나리오는 환경변수 FAKE_SCENARIO 로 고른다 ---
mkdir -p "$T/bin"
cat > "$T/bin/fakecurl" <<'FAKE'
#!/usr/bin/env bash
hdr="" out="" jar="" has_data=0 url=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in
    -D) hdr="${args[$((i+1))]}"; i=$((i+1)) ;;
    -o) out="${args[$((i+1))]}"; i=$((i+1)) ;;
    -c|-b|-m) i=$((i+1)) ;;
    --data-urlencode) has_data=1; i=$((i+1)) ;;
    -X) has_data=1; i=$((i+1)) ;;
    -sS|-s) ;;
    *) url="${args[$i]}" ;;
  esac
done
: > "${out:-/dev/null}"
sc="${FAKE_SCENARIO:-ok}"
write() { printf '%b' "$1" > "$hdr"; [[ -n "${2:-}" ]] && printf '%s' "$2" > "$out"; return 0; }
if [[ "$url" == https://accounts.google.com/* ]]; then
  case "$sc" in
    google_rejects) write 'HTTP/2 302\r\nlocation: https://accounts.google.com/signin/oauth/error?authError=abc\r\n\r\n' ;;
    google_unknown) write 'HTTP/2 404\r\n\r\n' 'nf' ;;
    *) write 'HTTP/2 302\r\nlocation: https://accounts.google.com/v3/signin/identifier?x=1\r\n\r\n' ;;
  esac
elif [[ $has_data -eq 1 ]]; then
  case "$sc" in
    csrf_422|no_token) write 'HTTP/2 422\r\n\r\n' ;;
    not_found) write 'HTTP/2 404\r\n\r\n' ;;
    app_failure) write 'HTTP/2 302\r\nlocation: https://app.example.com/auth/failure?message=invalid\r\n\r\n' ;;
    redirect_differs) write "HTTP/2 302\r\nlocation: https://accounts.google.com/o/oauth2/auth?client_id=${FAKE_ID}&redirect_uri=https%3A%2F%2Fapp.example.com%2Fwrong&response_type=code\r\n\r\n" ;;
    placeholder_client) write "HTTP/2 302\r\nlocation: https://accounts.google.com/o/oauth2/auth?client_id=unset-client-id&redirect_uri=${FAKE_ENC}&response_type=code\r\n\r\n" ;;
    empty_client) write "HTTP/2 302\r\nlocation: https://accounts.google.com/o/oauth2/auth?client_id=&redirect_uri=${FAKE_ENC}&response_type=code\r\n\r\n" ;;
    *) write "HTTP/2 302\r\nlocation: https://accounts.google.com/o/oauth2/auth?client_id=${FAKE_ID}&redirect_uri=${FAKE_ENC}&response_type=code&scope=email&state=s1\r\n\r\n" ;;
  esac
else
  case "$sc" in
    no_token) write 'HTTP/2 200\r\n\r\n' '<html><form action="/x"><button>go</button></form></html>' ;;
    login_500) write 'HTTP/2 500\r\n\r\n' 'err' ;;
    meta_token) write 'HTTP/2 200\r\n\r\n' '<html><head><meta name="csrf-token" content="metatok123"></head></html>' ;;
    *) write 'HTTP/2 200\r\n\r\n' '<html><form><input type="hidden" name="authenticity_token" value="tok-abc_123==" autocomplete="off" /></form></html>' ;;
  esac
fi
exit 0
FAKE
chmod +x "$T/bin/fakecurl"

# run <이름> <시나리오> <기대 rc> <기대 문구> [추가 인자...]
run() {
  local name="$1" sc="$2" want_rc="$3" want_text="$4" out got; shift 4
  out="$(CURL_BIN="$T/bin/fakecurl" FAKE_SCENARIO="$sc" FAKE_ID="$GOOD_ID" FAKE_ENC="$ENC_EXPECTED" \
    "$SCRIPT" --login-url https://app.example.com/login --action-url https://app.example.com/auth/google_oauth2 \
    --expected-redirect-uri "$EXPECTED" "$@" 2>&1)"; got=$?
  last_out="$out"
  if [[ $got -eq $want_rc && "$out" == *"$want_text"* ]]; then
    pass=$((pass+1)); echo "ok   - $name"
  else
    failn=$((failn+1)); echo "FAIL - $name (rc=$got, want rc=$want_rc text=$want_text)"; echo "$out" | sed 's/^/       /'
  fi
}
last_out=""

run "정상 흐름" ok 0 "RESULT=OK_APP_LOGIN_START"
# 출력에 client_id 값이 없어야 한다
if [[ "$last_out" != *"$GOOD_ID"* && "$last_out" != *"testclient"* ]]; then pass=$((pass+1)); echo "ok   - client_id 값을 출력하지 않는다"
else failn=$((failn+1)); echo "FAIL - client_id 값이 출력됨"; fi
if [[ "$last_out" != *"tok-abc_123"* ]]; then pass=$((pass+1)); echo "ok   - CSRF 토큰 값을 출력하지 않는다"
else failn=$((failn+1)); echo "FAIL - CSRF 토큰이 출력됨"; fi
run "csrf-token meta 폴백" meta_token 0 "CSRF 토큰: 찾음"
run "구글 호출 생략" ok 0 "구글 호출은 건너뛰었습니다" --no-google-probe
run "구글이 거부(오류 화면)" google_rejects 1 "RESULT=REJECTED"
run "구글 응답 미확인" google_unknown 3 "RESULT=UNKNOWN"
run "redirect_uri 가 다름" redirect_differs 1 "RESULT=FAIL_REDIRECT_URI_DIFFERS"
run "자리표시 client_id" placeholder_client 1 "RESULT=FAIL_CLIENT_ID_FORMAT"
run "빈 client_id" empty_client 1 "RESULT=FAIL_CLIENT_ID_MISSING"
run "앱 내부 실패 경로" app_failure 1 "RESULT=FAIL_NOT_GOOGLE"
run "CSRF 거부(422)" csrf_422 1 "RESULT=FAIL_CSRF_REJECTED"
run "토큰이 없는 로그인 페이지" no_token 1 "WARN: CSRF 토큰"
run "시작 경로 404" not_found 1 "RESULT=FAIL_ACTION_NOT_FOUND"
run "로그인 페이지 500" login_500 1 "RESULT=FAIL_LOGIN_PAGE"

# 사용법 오류
"$SCRIPT" >/dev/null 2>&1; [[ $? -eq 2 ]] && { pass=$((pass+1)); echo "ok   - 인자 없음은 종료코드 2"; } || { failn=$((failn+1)); echo "FAIL - 인자 없음"; }

# query_param / extract_token 단위
. "$SCRIPT"
v="$(query_param 'https://x.example/a?b=1&redirect_uri=https%3A%2F%2Fapp.example.com%2Fcb&c=3' redirect_uri)"
[[ "$v" == "https://app.example.com/cb" ]] && { pass=$((pass+1)); echo "ok   - query_param 디코딩"; } || { failn=$((failn+1)); echo "FAIL - query_param ($v)"; }
query_param 'https://x.example/a?b=1' redirect_uri >/dev/null; [[ $? -ne 0 ]] && { pass=$((pass+1)); echo "ok   - query_param 없는 이름"; } || { failn=$((failn+1)); echo "FAIL - query_param 없는 이름"; }

echo "통과 $pass, 실패 $failn"
[[ $failn -eq 0 ]]
