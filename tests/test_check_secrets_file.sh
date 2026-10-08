#!/usr/bin/env bash
# check_secrets_file.sh 시험. 임시 디렉터리의 가상 값만 쓰며 값이 출력되지 않는지도 확인한다.
# shellcheck disable=SC2015,SC2001
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../scripts/check_secrets_file.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; failn=0

# 가상 값 (소스에 실제 값 모양이 남지 않도록 조각으로 조립)
SUF=".apps"".googleusercontent"".com"
GOOD_ID="12345-testclient${SUF}"
GOOD_SECRET="GOCSPX""-$(printf 'a%.0s' {1..28})"      # 접두사 + 28자 = 35자
EMAIL="you@example.com"

mkrepo() { rm -rf "$T/r"; mkdir -p "$T/r"; git -C "$T/r" init -q; printf '.env.test\n' > "$T/r/.gitignore"; }

check() {  # check <이름> <기대 rc> <기대 문구> <스크립트 인자...>
  local name="$1" want_rc="$2" want="$3" out got; shift 3
  out="$("$SCRIPT" "$@" 2>&1)"; got=$?; last="$out"
  if [[ $got -eq $want_rc && "$out" == *"$want"* ]]; then pass=$((pass+1)); echo "ok   - $name"
  else failn=$((failn+1)); echo "FAIL - $name (rc=$got, want rc=$want_rc text=$want)"; echo "$out" | sed 's/^/       /'; fi
}
last=""

mkrepo
printf '# 주석\nOTHER=1\nGOOGLE_CLIENT_ID=%s\nGOOGLE_CLIENT_SECRET=%s\nADMIN_EMAILS=%s\n' "$GOOD_ID" "$GOOD_SECRET" "$EMAIL" > "$T/r/.env.test"
chmod 600 "$T/r/.env.test"
check "정상 파일" 0 "RESULT=OK" --file "$T/r/.env.test" --email-key ADMIN_EMAILS
for v in "$GOOD_ID" "$GOOD_SECRET" "$EMAIL" "testclient"; do
  [[ "$last" != *"$v"* ]] && { pass=$((pass+1)); echo "ok   - 값 비노출: ${v:0:6}..."; } || { failn=$((failn+1)); echo "FAIL - 값이 출력됨: ${v:0:6}..."; }
done
[[ "$last" == *"지문 "* ]] && { pass=$((pass+1)); echo "ok   - 지문 출력"; } || { failn=$((failn+1)); echo "FAIL - 지문 없음"; }
[[ "$last" == *"길이 35"* ]] && { pass=$((pass+1)); echo "ok   - Secret 길이 35 표시"; } || { failn=$((failn+1)); echo "FAIL - 길이 표시"; }

chmod 644 "$T/r/.env.test"
check "권한 644 는 문제로 보고하고 해결 방법을 알려준다" 1 "chmod 600" --file "$T/r/.env.test"
chmod 600 "$T/r/.env.test"

printf 'GOOGLE_CLIENT_ID=unset-client-id\nGOOGLE_CLIENT_SECRET=unset-client-secret\n' > "$T/r/.env.test"; chmod 600 "$T/r/.env.test"
check "자리표시값" 1 "PLACEHOLDER" --file "$T/r/.env.test"

printf 'GOOGLE_CLIENT_ID=\nOTHER=1\n' > "$T/r/.env.test"; chmod 600 "$T/r/.env.test"
check "빈 값과 없는 키" 1 "MISSING" --file "$T/r/.env.test"

printf 'GOOGLE_CLIENT_ID=%s\nGOOGLE_CLIENT_SECRET=%s\nADMIN_EMAILS=not-an-email,%s\n' "$GOOD_ID" "$GOOD_SECRET" "$EMAIL" > "$T/r/.env.test"; chmod 600 "$T/r/.env.test"
check "이메일 형식 이상" 1 "형식이 이상한 항목 1개" --file "$T/r/.env.test" --email-key ADMIN_EMAILS

printf 'GOOGLE_CLIENT_ID="%s"\nGOOGLE_CLIENT_SECRET=%s\n' "$GOOD_ID" "$GOOD_SECRET" > "$T/r/.env.test"; chmod 600 "$T/r/.env.test"
check "따옴표 포함 경고" 1 "따옴표" --file "$T/r/.env.test"

printf 'GOOGLE_CLIENT_ID=%s\nGOOGLE_CLIENT_SECRET=short\n' "$GOOD_ID" > "$T/r/.env.test"; chmod 600 "$T/r/.env.test"
check "Secret 접두사 불일치" 1 "접두사가 관찰값과 다름" --file "$T/r/.env.test"

# git 이 무시하지 않는 파일
printf 'GOOGLE_CLIENT_ID=%s\nGOOGLE_CLIENT_SECRET=%s\n' "$GOOD_ID" "$GOOD_SECRET" > "$T/r/.env.visible"; chmod 600 "$T/r/.env.visible"
check "git 이 무시하지 않는 파일" 1 "git:" --file "$T/r/.env.visible"

check "파일 없음" 2 "파일이 없습니다" --file "$T/none"
"$SCRIPT" >/dev/null 2>&1; [[ $? -eq 2 ]] && { pass=$((pass+1)); echo "ok   - 인자 없음은 종료코드 2"; } || { failn=$((failn+1)); echo "FAIL - 인자 없음"; }

echo "통과 $pass, 실패 $failn"
[[ $failn -eq 0 ]]
