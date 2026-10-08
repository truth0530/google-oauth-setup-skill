#!/usr/bin/env bash
# 비밀 값 하나를 지정한 파일의 지정한 키에만 안전하게 기록한다.
#
# 사용 (값은 표준입력으로 받는다. 인자로 넘기면 ps 에 노출된다):
#   printf '%s' "$VALUE" | write_secrets.sh --file <경로> --key <KEY>
#   write_secrets.sh --file <경로> --key <KEY> < value.txt
#
# 동작:
#   - 값은 화면에 출력하지 않는다(키 이름과 길이만 출력).
#   - 파일이 없으면 권한 600 으로 만들고, 있으면 권한을 600 으로 맞춘다.
#   - 같은 KEY= 줄이 있으면 그 줄만 바꾸고, 없으면 끝에 추가한다. 다른 줄과 주석은 그대로 둔다.
#   - 파일이 git 저장소 안에 있으면 git 이 그 파일을 무시하는지(.gitignore) 확인하고, 아니면 거부한다.
#   - 빈 값, 개행이 섞인 값은 거부한다.
#
# 종료 코드: 0 성공, 2 사용법 오류, 3 안전 점검 실패(저장 안 함)

set -u

fail() { echo "오류: $*" >&2; exit "${2:-3}"; }

file="" key=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) file="${2:-}"; shift 2 ;;
    --key) key="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "알 수 없는 인자: $1" 2 ;;
  esac
done
[[ -n "$file" && -n "$key" ]] || fail "--file 과 --key 가 필요합니다." 2
[[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fail "KEY 형식이 올바르지 않습니다(영문, 숫자, _ 만)." 2
[[ -t 0 ]] && fail "값을 표준입력으로 넘기세요(터미널 직접 입력은 지원하지 않습니다)." 2

value="$(cat; printf x)"; value="${value%x}"
value="${value%$'\n'}"
[[ -n "$value" ]] || fail "값이 비어 있습니다."
[[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || fail "값에 개행이 있습니다."

dir="$(dirname "$file")"
[[ -d "$dir" ]] || fail "디렉터리가 없습니다: $dir"

# git 저장소 안이면 무시 대상인지 확인한다.
if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$dir" check-ignore -q -- "$(basename "$file")" \
    || fail "git 이 이 파일을 무시하지 않습니다. .gitignore 에 추가한 뒤 다시 실행하세요: $file"
fi

umask 077
tmp="$(mktemp "$dir/.write_secrets.XXXXXX")" || fail "임시 파일을 만들 수 없습니다."
trap 'rm -f "$tmp"' EXIT

# 값은 환경변수로 awk 에 넘긴다(인자에 노출하지 않고, 백슬래시 해석도 피한다).
NEW_VALUE="$value" KEY_NAME="$key" awk '
  BEGIN { done = 0 }
  {
    if (!done && index($0, ENVIRON["KEY_NAME"] "=") == 1) {
      print ENVIRON["KEY_NAME"] "=" ENVIRON["NEW_VALUE"]; done = 1
    } else { print $0 }
  }
  END { if (!done) print ENVIRON["KEY_NAME"] "=" ENVIRON["NEW_VALUE"] }
' "$file" 2>/dev/null > "$tmp" || { [[ -f "$file" ]] && fail "기존 파일을 읽지 못했습니다."; NEW_VALUE="$value" KEY_NAME="$key" awk 'BEGIN{print ENVIRON["KEY_NAME"] "=" ENVIRON["NEW_VALUE"]}' > "$tmp"; }

chmod 600 "$tmp"
mv -f "$tmp" "$file"
trap - EXIT
chmod 600 "$file"
echo "기록 완료: ${key} (값 길이 ${#value}자, 값은 출력하지 않음)"
