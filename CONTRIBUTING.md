# 기여 안내

- 이슈와 PR 환영합니다. 특히 **실제 콘솔에서 확인한 메뉴 경로, 막힘, 해결 방법**은 가장 가치 있는 기여입니다. `docs/AGENT_BROWSER_NOTES.md` 의 "관찰 기록" 표에 추가해 주세요.
- 추측과 확인된 사실을 구분해 쓰세요. 직접 확인하지 않은 메뉴 이름에는 `(확인 필요)` 를 붙입니다.
- **개인정보와 비밀 금지**: 실제 이메일, 도메인, 프로젝트 ID, 클라이언트 ID/Secret, 토큰을 올리지 마세요. 예시는 `example.com`, `you@example.com` 같은 가상 값을 씁니다.
- 스크립트를 바꾸면 `tests/` 의 시험을 함께 갱신하고 `shellcheck` 경고 0 을 유지해 주세요.
  ```bash
  bash tests/test_check_redirect_uri.sh && bash tests/test_write_secrets.sh
  shellcheck scripts/*.sh tests/*.sh
  ```
- 이모지는 쓰지 않습니다.
