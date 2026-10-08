#!/usr/bin/env bash
# 비밀 없이 리디렉션 URI 등록 여부를 점검한다.
#
# 사용:
#   check_redirect_uri.sh --client-id <공개 클라이언트 ID> --redirect-uri <URI> [--scope email]
#   check_redirect_uri.sh --lint-only --redirect-uri <URI>        # 네트워크 없이 형식만 점검
#   check_redirect_uri.sh --classify <헤더파일> <본문파일>          # 저장된 응답 판정(시험용)
#
# 종료 코드: 0 = 등록된 것으로 보임(로그인 화면으로 진행), 1 = 문제 발견,
#            2 = 사용법 오류, 3 = 판정 불가(UNKNOWN)
#
# 주의: 구글 응답 문구/동작에 의존하는 판정이라 구글이 바꾸면 틀릴 수 있다.
# 실제 구글 응답으로는 아직 검증되지 않았다(README의 '검증 상태' 참조).

set -u

AUTH_ENDPOINT="https://accounts.google.com/o/oauth2/v2/auth"

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

# 네트워크 없이 URI 형식의 흔한 실수를 찾는다. 경고를 stdout에 출력하고 개수를 반환한다.
lint_uri() {
  local uri="$1" warns=0
  if [[ -z "$uri" ]]; then
    echo "WARN: redirect_uri가 비어 있습니다."; return 1
  fi
  if [[ "$uri" =~ [[:space:]] ]]; then
    echo "WARN: URI에 공백/개행이 있습니다. 복사 중 섞인 문자가 아닌지 확인하세요."; warns=$((warns+1))
  fi
  if [[ "$uri" == *"#"* ]]; then
    echo "WARN: URI에 # 조각(fragment)이 있습니다. 등록할 수 없습니다."; warns=$((warns+1))
  fi
  if [[ "$uri" != http://* && "$uri" != https://* ]]; then
    echo "WARN: 스킴(http:// 또는 https://)으로 시작하지 않습니다."; warns=$((warns+1))
  fi
  if [[ "$uri" == http://* && "$uri" != http://localhost* && "$uri" != http://127.0.0.1* ]]; then
    echo "WARN: localhost 가 아닌 곳에 http:// 를 쓰고 있습니다. 운영 주소는 https 여야 합니다."; warns=$((warns+1))
  fi
  local host="${uri#*://}"; host="${host%%/*}"; host="${host%%\?*}"
  if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(:[0-9]+)?$ && "$uri" != http://127.0.0.1* ]]; then
    echo "WARN: IP 주소 호스트는 웹 클라이언트 리디렉션 URI 로 거부되는 경우가 많습니다. 도메인을 쓰세요."; warns=$((warns+1))
  fi
  if [[ "$uri" =~ [A-Z] ]]; then
    echo "NOTE: 대문자가 있습니다. 호스트는 대소문자를 구분하지 않지만 경로는 구분합니다. 등록값과 코드의 값을 글자 그대로 맞추세요."
  fi
  if [[ "$uri" == */ ]]; then
    echo "NOTE: 끝이 / 입니다. 등록값과 앱이 보내는 값이 말단 슬래시까지 같아야 합니다."
  fi
  return "$warns"
}

# 헤더/본문 파일을 읽어 판정한다. 결과 한 줄 코드와 설명을 출력하고 종료 코드를 반환한다.
classify() {
  local hdr="$1" body="$2" status loc
  status="$(awk 'toupper($1) ~ /^HTTP\// {code=$2} END {print code}' "$hdr" 2>/dev/null | tr -d '\r')"
  loc="$(awk 'tolower($1)=="location:" {sub(/\r$/,""); print $2}' "$hdr" 2>/dev/null | tail -1)"

  if grep -qi 'redirect_uri_mismatch' "$body" "$hdr" 2>/dev/null || [[ "$loc" == *redirect_uri_mismatch* ]]; then
    echo "RESULT=MISMATCH"
    echo "이 클라이언트에 이 redirect_uri 가 등록되어 있지 않습니다. 스킴, 호스트, 포트, 경로, 말단 슬래시를 글자 그대로 비교하세요."
    echo "방금 저장했다면 반영에 시간이 걸릴 수 있습니다(최대 수 시간으로 안내됨, 확인 필요). 잠시 뒤 다시 시험하세요."
    return 1
  fi
  if grep -qi 'invalid_client' "$body" "$hdr" 2>/dev/null || [[ "$loc" == *invalid_client* ]]; then
    echo "RESULT=INVALID_CLIENT"
    echo "client_id 를 구글이 알지 못합니다. ID 오타, 다른 프로젝트의 ID, 삭제된 클라이언트인지 확인하세요."
    return 1
  fi
  if grep -qi 'origin_mismatch' "$body" "$hdr" 2>/dev/null || [[ "$loc" == *origin_mismatch* ]]; then
    echo "RESULT=ORIGIN_MISMATCH"
    echo "승인된 JavaScript 원본이 맞지 않습니다(브라우저 JS 흐름에서 발생)."
    return 1
  fi
  if grep -qi 'invalid_request' "$body" "$hdr" 2>/dev/null || [[ "$loc" == *invalid_request* ]]; then
    echo "RESULT=INVALID_REQUEST"
    echo "요청 형식 또는 구글 정책 위반입니다(예: IP 주소 호스트, http 운영 주소, 필수 파라미터 누락)."
    return 1
  fi
  if [[ "$status" == "302" || "$status" == "303" || "$status" == "307" ]]; then
    if [[ "$loc" == *accounts.google.com* || "$loc" == *signin* || "$loc" == *ServiceLogin* ]]; then
      echo "RESULT=OK_LOGIN_REDIRECT"
      echo "구글 로그인 화면으로 넘어갑니다. client_id 와 redirect_uri 조합이 받아들여진 것으로 보입니다."
      echo "단, 동의 화면 상태와 테스트 사용자 설정은 이 점검으로 알 수 없습니다."
      return 0
    fi
  fi
  if [[ "$status" == "200" ]] && grep -qiE 'signin|identifier|accounts\.google\.com' "$body" 2>/dev/null; then
    echo "RESULT=OK_LOGIN_PAGE"
    echo "로그인 페이지가 직접 응답되었습니다. 조합이 받아들여진 것으로 보입니다."
    return 0
  fi
  echo "RESULT=UNKNOWN"
  echo "HTTP 상태 ${status:-없음}, Location '${loc:-없음}'. 응답 형태를 판정하지 못했습니다. 브라우저에서 직접 열어 확인하세요."
  return 3
}

main() {
  local client_id="" uri="" scope="email" lint_only=0
  if [[ "${1:-}" == "--classify" ]]; then
    [[ $# -eq 3 ]] || { usage; return 2; }
    classify "$2" "$3"; return $?
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --client-id) client_id="${2:-}"; shift 2 ;;
      --redirect-uri) uri="${2:-}"; shift 2 ;;
      --scope) scope="${2:-}"; shift 2 ;;
      --lint-only) lint_only=1; shift ;;
      -h|--help) usage; return 0 ;;
      *) echo "알 수 없는 인자: $1" >&2; usage; return 2 ;;
    esac
  done
  [[ -n "$uri" ]] || { echo "--redirect-uri 가 필요합니다." >&2; usage; return 2; }

  echo "== 형식 점검 =="
  lint_uri "$uri"; local lint_rc=$?
  [[ $lint_rc -eq 0 ]] && echo "형식 경고 없음"
  if [[ $lint_only -eq 1 ]]; then
    [[ $lint_rc -eq 0 ]] && return 0 || return 1
  fi
  [[ -n "$client_id" ]] || { echo "--client-id 가 필요합니다(공개 값입니다. Secret 은 필요 없습니다)." >&2; return 2; }
  [[ "$client_id" =~ [[:space:]] ]] && { echo "client_id 에 공백이 있습니다." >&2; return 2; }

  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  echo "== 구글 응답 점검 =="
  curl -sS -G -m 20 -D "$tmp/h" -o "$tmp/b" \
    --data-urlencode "client_id=$client_id" \
    --data-urlencode "redirect_uri=$uri" \
    --data-urlencode "response_type=code" \
    --data-urlencode "scope=$scope" \
    "$AUTH_ENDPOINT" || { echo "RESULT=NETWORK_ERROR"; echo "구글에 접속하지 못했습니다."; return 3; }
  classify "$tmp/h" "$tmp/b"
}

# 스크립트로 실행될 때만 main 을 돈다(시험에서 source 할 수 있게).
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
  exit $?
fi
