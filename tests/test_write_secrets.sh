#!/usr/bin/env bash
# write_secrets.sh 시험. 임시 디렉터리에서만 동작한다.
# shellcheck disable=SC2015,SC2016
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/write_secrets.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; failn=0
ok()   { pass=$((pass+1)); echo "ok   - $1"; }
bad()  { failn=$((failn+1)); echo "FAIL - $1"; }
mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }

SECRET='fake-secret-$HOME-with-"quotes"-and-\\backslash'
cd "$T" && git init -q . && printf 'secrets.env\n' > .gitignore

# 1. 새 파일 생성, 값 비출력, 권한 600
out="$(printf '%s' "$SECRET" | "$SCRIPT" --file "$T/secrets.env" --key CLIENT_SECRET)"; rc=$?
[[ $rc -eq 0 ]] && ok "새 파일에 기록" || bad "새 파일에 기록 rc=$rc"
[[ "$out" != *"fake-secret"* ]] && ok "출력에 값이 없음" || bad "출력에 값 노출"
[[ "$(mode "$T/secrets.env")" == "600" ]] && ok "권한 600" || bad "권한 $(mode "$T/secrets.env")"
[[ "$(grep -c '^CLIENT_SECRET=' "$T/secrets.env")" == "1" ]] && ok "키 한 줄" || bad "키 줄 수"
[[ "$(sed -n 's/^CLIENT_SECRET=//p' "$T/secrets.env")" == "$SECRET" ]] && ok "특수문자 값 그대로 보존" || bad "특수문자 값 변형"

# 2. 다른 줄과 주석 보존, 같은 키 교체
printf '# 주석\nREGISTRY=keep-me\nCLIENT_ID=old\nOTHER=1\n' > "$T/secrets.env"; chmod 644 "$T/secrets.env"
printf '%s' "new-id" | "$SCRIPT" --file "$T/secrets.env" --key CLIENT_ID >/dev/null
grep -q '^# 주석$' "$T/secrets.env" && grep -q '^REGISTRY=keep-me$' "$T/secrets.env" && grep -q '^OTHER=1$' "$T/secrets.env" && ok "다른 줄 보존" || bad "다른 줄 손상"
[[ "$(grep -c '^CLIENT_ID=' "$T/secrets.env")" == "1" && "$(sed -n 's/^CLIENT_ID=//p' "$T/secrets.env")" == "new-id" ]] && ok "같은 키 교체" || bad "키 교체 실패"
[[ "$(mode "$T/secrets.env")" == "600" ]] && ok "기존 파일 권한을 600 으로 보정" || bad "기존 파일 권한 $(mode "$T/secrets.env")"

# 3. 없던 키는 끝에 추가
printf '%s' "a@example.com" | "$SCRIPT" --file "$T/secrets.env" --key ADMIN_EMAILS >/dev/null
[[ "$(tail -1 "$T/secrets.env")" == "ADMIN_EMAILS=a@example.com" ]] && ok "없던 키는 끝에 추가" || bad "키 추가"

# 4. 접두어가 겹치는 키를 건드리지 않음
printf 'CLIENT_ID_EXTRA=x\n' >> "$T/secrets.env"
printf '%s' "again" | "$SCRIPT" --file "$T/secrets.env" --key CLIENT_ID >/dev/null
grep -q '^CLIENT_ID_EXTRA=x$' "$T/secrets.env" && ok "접두어 겹치는 키 보존" || bad "접두어 키 손상"

# 5. 거부 조건
: | "$SCRIPT" --file "$T/secrets.env" --key K >/dev/null 2>&1; [[ $? -eq 3 ]] && ok "빈 값 거부" || bad "빈 값 허용됨"
printf 'a\nb' | "$SCRIPT" --file "$T/secrets.env" --key K >/dev/null 2>&1; [[ $? -eq 3 ]] && ok "개행 값 거부" || bad "개행 값 허용됨"
printf 'x' | "$SCRIPT" --file "$T/secrets.env" --key '1BAD' >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "잘못된 KEY 거부" || bad "잘못된 KEY 허용됨"
printf 'x' | "$SCRIPT" --file "$T/nodir/s.env" --key K >/dev/null 2>&1; [[ $? -eq 3 ]] && ok "없는 디렉터리 거부" || bad "없는 디렉터리 허용됨"
printf 'x' | "$SCRIPT" --file "$T/tracked.env" --key K >/dev/null 2>&1; [[ $? -eq 3 && ! -e "$T/tracked.env" ]] && ok "git 이 무시하지 않는 파일 거부(생성 안 됨)" || bad "무시 안 되는 파일 허용됨"

# 6. 값이 인자로 새지 않음: 임시 파일이 남지 않음
leftover=0; for f in "$T"/.write_secrets.*; do [[ -e "$f" ]] && leftover=1; done
[[ $leftover -eq 0 ]] && ok "임시 파일 잔존 없음" || bad "임시 파일 잔존"

echo "통과 $pass, 실패 $failn"
[[ $failn -eq 0 ]]
