#!/usr/bin/env bash
# 앱이 시작하는 구글 로그인 흐름을 비밀 없이 스모크 검사한다.
#
# 사용:
#   check_app_login_start.sh --login-url <로그인 페이지 URL> --action-url <로그인 시작 폼 action URL> \
#       --expected-redirect-uri <콘솔에 등록한 URI> [--token-field authenticity_token] [--no-csrf] [--no-google-probe]
#
# 검사 순서:
#   1. 로그인 페이지를 GET 해서 세션 쿠키와 CSRF 토큰(authenticity_token)을 얻는다.
#   2. 폼 action 으로 POST 한다. 정상이면 302 로 구글 인증 주소(/o/oauth2/...)로 간다.
#   3. 그 주소의 redirect_uri 가 기대 값과 같은지, client_id 가 채워져 있고 형식이 맞는지 본다.
#   4. (기본) 그 구글 주소를 한 번 더 호출해 로그인 화면(정상) 또는 오류 화면(거부)으로 가는지 본다.
#
# 비밀(Secret)은 필요 없다. client_id 값은 출력하지 않고 존재/형식 여부만 표시한다.
# 종료 코드: 0 = 정상, 1 = 문제 발견, 2 = 사용법 오류, 3 = 판정 불가(네트워크 등)
#
# 근거: 서버 렌더링 앱에서 로그인 시작이 POST + CSRF 토큰인 구성(Rails + omniauth 계열)을 실측했다.
#   - 시작 경로로 GET 하면 404(라우트 없음), 토큰 없는 POST 는 422, 토큰이 있는 POST 만 302 로 구글에 간다.
#   - 이 스크립트는 실제 Rails 앱에 대해 OK_APP_LOGIN_START 가 나오는 것을 1회 확인했다.
# 다른 프레임워크는 토큰 필드 이름이나 시작 방식이 다를 수 있다(--token-field, --no-csrf).
# 시험은 모의 curl(CURL_BIN)로만 하며 이 스크립트의 실제 구글 호출은 시험에서 하지 않는다.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# classify() 재사용 (source 되면 main 은 돌지 않는다)
# shellcheck disable=SC1091
. "$HERE/check_redirect_uri.sh"

CURL_BIN="${CURL_BIN:-curl}"

# 클라이언트 ID 형식: 숫자-문자열 뒤에 구글이 붙이는 고정 접미사. 접미사는 조각으로 조립한다.
ID_SUFFIX_A="apps"
ID_SUFFIX_B="googleusercontent.com"

usage_app() {
  sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
}

url_decode() {
  local v="${1//+/ }"
  printf '%b' "${v//%/\\x}"
}

# query_param <URL> <이름> : 디코딩된 값을 출력. 없으면 1.
query_param() {
  local url="$1" name="$2" q kv
  [[ "$url" == *\?* ]] || return 1
  q="${url#*\?}"; q="${q%%#*}"
  local -a parts
  IFS='&' read -r -a parts <<< "$q"
  for kv in "${parts[@]}"; do
    if [[ "${kv%%=*}" == "$name" ]]; then
      url_decode "${kv#*=}"; return 0
    fi
  done
  return 1
}

header_status() { awk 'toupper($1) ~ /^HTTP\// {code=$2} END {print code}' "$1" 2>/dev/null | tr -d '\r'; }
header_location() { awk 'tolower($1)=="location:" {sub(/\r$/,""); print $2}' "$1" 2>/dev/null | tail -1; }

# extract_token <본문 파일> <필드 이름> : hidden input 우선, 없으면 csrf-token meta.
extract_token() {
  local body="$1" field="$2" tag tok=""
  tag="$(grep -oE "<input[^>]*name=\"${field}\"[^>]*>" "$body" 2>/dev/null | head -1)"
  if [[ -n "$tag" ]]; then
    tok="$(printf '%s' "$tag" | sed -n 's/.*value="\([^"]*\)".*/\1/p')"
  fi
  if [[ -z "$tok" ]]; then
    tag="$(grep -oE '<meta[^>]*name="csrf-token"[^>]*>' "$body" 2>/dev/null | head -1)"
    [[ -n "$tag" ]] && tok="$(printf '%s' "$tag" | sed -n 's/.*content="\([^"]*\)".*/\1/p')"
  fi
  printf '%s' "$tok"
}

client_id_format_ok() {
  [[ "$1" =~ ^[0-9]+-[a-z0-9]+\.${ID_SUFFIX_A}\.${ID_SUFFIX_B//./\\.}$ ]]
}

main() {
  local login_url="" action_url="" expected="" field="authenticity_token" use_csrf=1 probe=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --login-url) login_url="${2:-}"; shift 2 ;;
      --action-url) action_url="${2:-}"; shift 2 ;;
      --expected-redirect-uri) expected="${2:-}"; shift 2 ;;
      --token-field) field="${2:-}"; shift 2 ;;
      --no-csrf) use_csrf=0; shift ;;
      --no-google-probe) probe=0; shift ;;
      -h|--help) usage_app; return 0 ;;
      *) echo "알 수 없는 인자: $1" >&2; usage_app; return 2 ;;
    esac
  done
  if [[ -z "$login_url" || -z "$action_url" || -z "$expected" ]]; then
    echo "--login-url, --action-url, --expected-redirect-uri 가 모두 필요합니다." >&2; usage_app; return 2
  fi

  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  local jar="$tmp/jar"

  echo "== 1. 로그인 페이지 =="
  "$CURL_BIN" -sS -m 20 -c "$jar" -D "$tmp/h1" -o "$tmp/b1" "$login_url" \
    || { echo "RESULT=NETWORK_ERROR"; echo "로그인 페이지에 접속하지 못했습니다."; return 3; }
  local st1; st1="$(header_status "$tmp/h1")"
  if [[ "$st1" != "200" ]]; then
    echo "RESULT=FAIL_LOGIN_PAGE"; echo "로그인 페이지가 HTTP ${st1:-없음} 로 응답했습니다(200 기대)."; return 1
  fi
  echo "HTTP 200"

  local token=""
  if [[ $use_csrf -eq 1 ]]; then
    token="$(extract_token "$tmp/b1" "$field")"
    if [[ -n "$token" ]]; then echo "CSRF 토큰: 찾음(값 비공개)"
    else echo "WARN: CSRF 토큰(${field})을 찾지 못했습니다. 토큰 없이 시도합니다(앱이 거부할 수 있음)."; fi
  else
    echo "CSRF 토큰 사용 안 함(--no-csrf)"
  fi

  echo "== 2. 로그인 시작(POST) =="
  local -a post_args=()
  [[ -n "$token" ]] && post_args+=(--data-urlencode "${field}=${token}")
  [[ ${#post_args[@]} -eq 0 ]] && post_args+=(-X POST)
  "$CURL_BIN" -sS -m 20 -b "$jar" -c "$jar" -D "$tmp/h2" -o "$tmp/b2" "${post_args[@]}" "$action_url" \
    || { echo "RESULT=NETWORK_ERROR"; echo "로그인 시작 요청에 실패했습니다."; return 3; }
  local st2 loc; st2="$(header_status "$tmp/h2")"; loc="$(header_location "$tmp/h2")"
  case "$st2" in
    302|303|307) echo "HTTP ${st2}" ;;
    422|403) echo "RESULT=FAIL_CSRF_REJECTED"; echo "앱이 HTTP ${st2} 로 거부했습니다. CSRF 토큰/세션 쿠키 처리를 확인하세요."; return 1 ;;
    404) echo "RESULT=FAIL_ACTION_NOT_FOUND"; echo "시작 경로가 404 입니다. 앱의 경로 접두사와 omniauth 류의 경로 접두사 설정을 확인하세요. (참고: Rails omniauth 에서는 시작 경로로 GET 해도 404 가 실측되었다. POST 인지 확인하세요.)"; return 1 ;;
    405) echo "RESULT=FAIL_METHOD_NOT_ALLOWED"; echo "POST 가 허용되지 않습니다. 시작 방식(GET/POST)을 확인하세요."; return 1 ;;
    *) echo "RESULT=FAIL_UNEXPECTED_STATUS"; echo "HTTP ${st2:-없음} 로 응답했습니다(302 기대)."; return 1 ;;
  esac

  local loc_nq="${loc%%\?*}"
  if [[ "$loc_nq" != https://accounts.google.com/o/oauth2/* ]]; then
    echo "RESULT=FAIL_NOT_GOOGLE"
    echo "구글 인증 주소로 이동하지 않았습니다. 이동 대상(쿼리 제외): ${loc_nq:-없음}"
    echo "앱 안의 실패 경로라면 앱 로그와 허용 목록, 환경변수 주입을 확인하세요."
    return 1
  fi
  echo "구글 인증 주소로 이동: ${loc_nq}"

  echo "== 3. 이동 주소의 파라미터 =="
  local got_uri cid
  got_uri="$(query_param "$loc" redirect_uri || true)"
  cid="$(query_param "$loc" client_id || true)"
  if [[ "$got_uri" != "$expected" ]]; then
    echo "RESULT=FAIL_REDIRECT_URI_DIFFERS"
    echo "앱이 보내는 redirect_uri: ${got_uri:-없음}"
    echo "기대한 값              : ${expected}"
    echo "콘솔 등록값, 앱 설정(경로 접두사, 프록시 뒤 스킴)을 글자 단위로 맞추세요."
    return 1
  fi
  echo "redirect_uri: 기대 값과 같음"
  if [[ -z "$cid" ]]; then
    echo "RESULT=FAIL_CLIENT_ID_MISSING"; echo "client_id 가 비어 있습니다. 앱에 환경변수가 주입됐는지 확인하세요."; return 1
  fi
  if ! client_id_format_ok "$cid"; then
    echo "RESULT=FAIL_CLIENT_ID_FORMAT"
    echo "client_id 는 있으나 구글 클라이언트 ID 형식이 아닙니다(값 비공개). 자리표시값이 주입됐을 수 있습니다."
    return 1
  fi
  echo "client_id: 있음, 형식 정상(값 비공개)"

  if [[ $probe -eq 0 ]]; then
    echo "RESULT=OK_APP_LOGIN_START"; echo "구글 호출은 건너뛰었습니다(--no-google-probe)."; return 0
  fi

  echo "== 4. 구글 응답 =="
  "$CURL_BIN" -sS -m 20 -D "$tmp/h3" -o "$tmp/b3" "$loc" \
    || { echo "RESULT=NETWORK_ERROR"; echo "구글에 접속하지 못했습니다."; return 3; }
  local out rc
  out="$(classify "$tmp/h3" "$tmp/b3")"; rc=$?
  echo "$out"
  if [[ $rc -eq 0 ]]; then
    echo "RESULT=OK_APP_LOGIN_START"
    echo "앱 -> 구글 로그인 화면까지 정상입니다. 실제 계정 로그인과 허용 목록 거부는 사람이 한 번 확인하세요."
    return 0
  fi
  return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
  exit $?
fi
