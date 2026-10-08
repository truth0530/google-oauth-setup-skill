#!/usr/bin/env bash
# check_redirect_uri.sh 의 판정 로직을 모의 응답으로 시험한다. 구글에 접속하지 않는다.
# shellcheck disable=SC2001,SC2015
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/check_redirect_uri.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; failn=0

# expect <이름> <기대 종료코드> <기대 RESULT 값> <헤더 내용> <본문 내용>
expect() {
  local name="$1" rc="$2" want="$3" hdr="$4" body="$5" out got
  printf '%b' "$hdr" > "$T/h"; printf '%b' "$body" > "$T/b"
  out="$("$SCRIPT" --classify "$T/h" "$T/b")"; got=$?
  if [[ $got -eq $rc && "$out" == *"RESULT=$want"* ]]; then
    pass=$((pass+1)); echo "ok   - $name"
  else
    failn=$((failn+1)); echo "FAIL - $name (rc=$got, want rc=$rc RESULT=$want)"; echo "$out" | sed 's/^/       /'
  fi
}

# --- 실측 기반(Location 경로 1순위) ---
# 등록된 정확한 URI: 302 + 로그인 화면(본문 없음)
expect "실측: 등록된 URI -> 로그인 화면 이동(본문 없음)" 0 OK_LOGIN_REDIRECT \
  'HTTP/2 302\r\nlocation: https://accounts.google.com/v3/signin/identifier?opparams=%3F&dsh=x\r\n\r\n' ''
# 등록되지 않은 URI(말단 슬래시 추가 / 다른 경로): 302 + 오류 화면(본문 없음)
expect "실측: 미등록 URI -> 오류 화면 이동(본문 없음)" 1 REJECTED \
  'HTTP/2 302\r\nlocation: https://accounts.google.com/signin/oauth/error?authError=abc&flowName=GeneralOAuthFlow\r\n\r\n' ''
# 'signin' 을 포함하는 오류 경로가 로그인으로 오판되지 않는지(순서 회귀)
expect "순서: signin/oauth/error 는 로그인으로 판정하지 않는다" 1 REJECTED \
  'HTTP/2 302\r\nlocation: https://accounts.google.com/signin/oauth/error/v2?x=1\r\n\r\n' '<html>signin identifier</html>'
# 본문이 있어도 Location 이 1순위
expect "Location 이 로그인이면 본문의 오류 단어보다 우선" 0 OK_LOGIN_REDIRECT \
  'HTTP/2 302\r\nlocation: https://accounts.google.com/v3/signin/identifier?x=1\r\n\r\n' 'invalid_request'
# 구형 로그인 경로도 인정
expect "구형 ServiceLogin 경로" 0 OK_LOGIN_REDIRECT \
  'HTTP/1.1 302 Found\r\nLocation: https://accounts.google.com/ServiceLogin?continue=x\r\n\r\n' ''
# Location 에 구체적 문구가 실려 있으면 MISMATCH 로 세분화
expect "Location 에 redirect_uri_mismatch 문구" 1 MISMATCH \
  'HTTP/2 302\r\nlocation: https://accounts.google.com/signin/oauth/error?authError=redirect_uri_mismatch\r\n\r\n' ''

# --- 미확인 응답은 UNKNOWN (추측하지 않는다) ---
expect "미확인: 존재하지 않는 client_id 응답 형태를 모르는 404" 3 UNKNOWN \
  'HTTP/2 404\r\n\r\n' 'Not Found'
expect "미확인: 낯선 Location" 3 UNKNOWN \
  'HTTP/2 302\r\nlocation: https://example.com/somewhere\r\n\r\n' ''
expect "판정 불가 503" 3 UNKNOWN \
  'HTTP/2 503\r\n\r\n' 'temporarily unavailable'

# UNKNOWN 설명이 Location 값(client_id 포함 가능)을 출력하지 않는지
printf '%b' 'HTTP/2 302\r\nlocation: https://example.com/x?client_id=SECRETISH123\r\n\r\n' > "$T/h"; : > "$T/b"
out="$("$SCRIPT" --classify "$T/h" "$T/b")"
if [[ "$out" != *SECRETISH123* ]]; then pass=$((pass+1)); echo "ok   - UNKNOWN 은 Location 값을 출력하지 않는다"
else failn=$((failn+1)); echo "FAIL - UNKNOWN 이 Location 값을 노출"; fi

# --- 보조: 본문/헤더 문구 기반 판정 (Location 없이도 동작) ---
expect "보조: redirect_uri_mismatch 본문" 1 MISMATCH \
  'HTTP/2 400\r\ncontent-type: text/html\r\n\r\n' '<html>Error 400: redirect_uri_mismatch</html>'
expect "보조: invalid_client 본문" 1 INVALID_CLIENT \
  'HTTP/2 401\r\n\r\n' '<html>Error 401: invalid_client</html>'
expect "보조: origin_mismatch" 1 ORIGIN_MISMATCH \
  'HTTP/2 400\r\n\r\n' 'Error 400: origin_mismatch'
expect "보조: invalid_request" 1 INVALID_REQUEST \
  'HTTP/2 400\r\n\r\n' 'Error 400: invalid_request'
expect "보조: 200 로그인 페이지" 0 OK_LOGIN_PAGE \
  'HTTP/2 200\r\n\r\n' '<html>... accounts.google.com ... identifier ...</html>'

# 형식 점검(네트워크 없음)
lint() { "$SCRIPT" --lint-only --redirect-uri "$1" 2>&1; }
check_lint() {
  local name="$1" uri="$2" want_rc="$3" want_text="$4" out got
  out="$(lint "$uri")"; got=$?
  if [[ $got -eq $want_rc && "$out" == *"$want_text"* ]]; then pass=$((pass+1)); echo "ok   - $name"
  else failn=$((failn+1)); echo "FAIL - $name (rc=$got)"; echo "$out" | sed 's/^/       /'; fi
}
check_lint "정상 https URI" "https://app.example.com/auth/callback" 0 "형식 경고 없음"
check_lint "http 운영 주소 경고" "http://app.example.com/cb" 1 "https 여야"
check_lint "localhost http 허용" "http://localhost:3000/cb" 0 "형식 경고 없음"
check_lint "IP 호스트 경고" "https://203.0.113.10/cb" 1 "IP 주소"
check_lint "조각 경고" "https://app.example.com/cb#x" 1 "fragment"
check_lint "말단 슬래시 안내" "https://app.example.com/cb/" 0 "말단 슬래시"

# 사용법 오류
"$SCRIPT" >/dev/null 2>&1; [[ $? -eq 2 ]] && { pass=$((pass+1)); echo "ok   - 인자 없음은 종료코드 2"; } || { failn=$((failn+1)); echo "FAIL - 인자 없음"; }

echo "통과 $pass, 실패 $failn"
[[ $failn -eq 0 ]]
