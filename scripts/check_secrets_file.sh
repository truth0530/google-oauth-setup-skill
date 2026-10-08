#!/usr/bin/env bash
# 비밀 파일에 값이 올바르게 들어갔는지 값을 노출하지 않고 확인한다.
#
# 사용:
#   check_secrets_file.sh --file <파일> [--id-key GOOGLE_CLIENT_ID] [--secret-key GOOGLE_CLIENT_SECRET] [--email-key ADMIN_EMAILS]
#
# 출력: 키마다 상태(SET/EMPTY/PLACEHOLDER/MISSING), 길이, 형식 판정, 지문(SHA-256 앞 8자리).
#       값 자체는 출력하지 않는다. 지문은 '나중에 파일이 바뀌었는지' 비교하는 용도다.
# 추가 확인: 파일 권한이 600 인지, git 저장소 안이면 git 이 무시하는 파일인지.
# 종료 코드: 0 = 문제 없음, 1 = 문제 있음, 2 = 사용법 오류
#
# 형식 기준은 1회 관찰한 값의 모양이다(클라이언트 ID: 숫자-문자열 + 구글 고정 접미사,
# Secret: 고정 접두사 + 관찰 길이 35). 구글이 형식을 바꾸면 WARN 이 날 수 있으며 오류로 단정하지 않는다.

set -u

# 값처럼 보이는 리터럴이 소스에 남지 않도록 조각으로 조립한다.
ID_SUFFIX_A="apps"
ID_SUFFIX_B="googleusercontent.com"
SECRET_PREFIX="GOCSPX""-"
SECRET_OBSERVED_LEN=35

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }

fingerprint() {
  if command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum | cut -c1-8
  else printf '%s' "$1" | shasum -a 256 | cut -c1-8; fi
}

file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
}

# get_value <파일> <키> : 마지막으로 나온 KEY=VALUE 의 VALUE(없으면 return 1)
get_value() {
  local line val found=1
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    if [[ "$line" == "$2="* ]]; then val="${line#*=}"; found=0; fi
  done < "$1"
  [[ $found -eq 0 ]] && printf '%s' "$val"
  return $found
}

is_placeholder() {
  case "$1" in unset-*|changeme*|your-*|xxx*|"<"*) return 0 ;; esac
  return 1
}

problems=0
note() { echo "$1"; }
problem() { echo "$1"; problems=$((problems+1)); }

check_key() {  # check_key <파일> <키> <종류: id|secret|email>
  local file="$1" key="$2" kind="$3" val rc
  val="$(get_value "$file" "$key")"; rc=$?
  if [[ $rc -ne 0 ]]; then problem "$key: MISSING (키 줄이 없습니다)"; return; fi
  if [[ -z "$val" ]]; then problem "$key: EMPTY (값이 비어 있습니다)"; return; fi
  if is_placeholder "$val"; then problem "$key: PLACEHOLDER (자리표시값입니다. 실제 값이 주입되지 않았습니다)"; return; fi
  local detail="" ok=1
  if [[ "$val" =~ ^[\"\'] || "$val" =~ [\"\']$ ]]; then detail="$detail 따옴표가 값에 포함됨(WARN);"; ok=0; fi
  if [[ "$val" =~ ^[[:space:]] || "$val" =~ [[:space:]]$ ]]; then detail="$detail 앞뒤 공백/개행 포함(WARN);"; ok=0; fi
  case "$kind" in
    id)
      if [[ "$val" =~ ^[0-9]+-[a-z0-9]+\.${ID_SUFFIX_A}\.${ID_SUFFIX_B//./\\.}$ ]]; then detail="$detail 형식 정상;"
      else detail="$detail 클라이언트 ID 형식이 아님;"; ok=0; fi ;;
    secret)
      if [[ "$val" == "$SECRET_PREFIX"* ]]; then detail="$detail 접두사 정상;"; else detail="$detail 접두사가 관찰값과 다름(WARN);"; ok=0; fi
      if [[ ${#val} -ne $SECRET_OBSERVED_LEN ]]; then detail="$detail 길이가 관찰값(${SECRET_OBSERVED_LEN})과 다름(WARN);"; fi ;;
    email)
      local n=0 bad=0 e
      local -a list
      IFS=',' read -r -a list <<< "$val"
      for e in "${list[@]}"; do
        [[ -z "${e// /}" ]] && continue
        n=$((n+1))
        [[ "$e" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || bad=$((bad+1))
      done
      detail="$detail 이메일 ${n}개;"
      if [[ $bad -gt 0 ]]; then detail="$detail 형식이 이상한 항목 ${bad}개;"; ok=0; fi ;;
  esac
  if [[ $ok -eq 1 ]]; then note "$key: SET 길이 ${#val}, 지문 $(fingerprint "$val"),$detail"
  else problem "$key: SET 길이 ${#val}, 지문 $(fingerprint "$val"),$detail"; fi
}

main() {
  local file="" id_key="GOOGLE_CLIENT_ID" secret_key="GOOGLE_CLIENT_SECRET" email_key=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) file="${2:-}"; shift 2 ;;
      --id-key) id_key="${2:-}"; shift 2 ;;
      --secret-key) secret_key="${2:-}"; shift 2 ;;
      --email-key) email_key="${2:-}"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) echo "알 수 없는 인자: $1" >&2; usage; return 2 ;;
    esac
  done
  [[ -n "$file" ]] || { echo "--file 이 필요합니다." >&2; usage; return 2; }
  [[ -f "$file" ]] || { echo "파일이 없습니다: $file" >&2; return 2; }

  local mode; mode="$(file_mode "$file")"
  if [[ "$mode" == "600" ]]; then note "권한: 600 정상"
  else problem "권한: ${mode:-알 수 없음} (600 이어야 합니다. 해결: chmod 600 \"$file\")"; fi

  local dir; dir="$(cd "$(dirname "$file")" && pwd)"
  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git -C "$dir" check-ignore -q "$file" 2>/dev/null; then note "git: 이 파일은 무시됨(정상)"
    else problem "git: 이 파일은 git 이 추적/표시할 수 있습니다. .gitignore 에 추가하세요."; fi
  else
    note "git: 저장소 밖 파일(확인 생략)"
  fi

  check_key "$file" "$id_key" id
  check_key "$file" "$secret_key" secret
  [[ -n "$email_key" ]] && check_key "$file" "$email_key" email

  if [[ $problems -eq 0 ]]; then echo "RESULT=OK"; return 0; fi
  echo "RESULT=PROBLEMS ($problems)"; return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
  exit $?
fi
