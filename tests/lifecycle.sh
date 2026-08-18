#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

setup_case() {
  CASE_ROOT="$TEST_ROOT/$1"
  HOME="$CASE_ROOT/home"
  XDG_STATE_HOME="$CASE_ROOT/state"
  MOCK_BIN="$CASE_ROOT/bin"
  MOCK_RELOAD_COUNT="$CASE_ROOT/reload-count"
  mkdir -p "$HOME/.config/hypr" "$XDG_STATE_HOME/omacoach" "$MOCK_BIN"
  printf '{"version":1}\n' >"$XDG_STATE_HOME/omacoach/attempts.json"

  cat >"$MOCK_BIN/omarchy" <<'EOF'
#!/bin/bash
exit 0
EOF
  cat >"$MOCK_BIN/hyprctl" <<'EOF'
#!/bin/bash
case "${1:-}" in
reload)
  count=0
  [[ ! -f "$MOCK_RELOAD_COUNT" ]] || count=$(<"$MOCK_RELOAD_COUNT")
  count=$((count + 1))
  printf '%s\n' "$count" >"$MOCK_RELOAD_COUNT"
  if [[ ${MOCK_FAIL_FIRST_RELOAD:-0} == 1 && $count == 1 ]]; then exit 1; fi
  ;;
configerrors)
  printf '%s' "${MOCK_CONFIG_ERRORS:-}"
  ;;
esac
EOF
  chmod +x "$MOCK_BIN/omarchy" "$MOCK_BIN/hyprctl"
  export HOME XDG_STATE_HOME MOCK_RELOAD_COUNT
  export PATH="$MOCK_BIN:$ORIGINAL_PATH"
  unset MOCK_FAIL_FIRST_RELOAD MOCK_CONFIG_ERRORS
}

write_installed_config() {
  cat >"$HOME/.config/hypr/bindings.lua" <<'EOF'
local retained = true
-- omacoach:start
do local observer = true end
-- omacoach:end
-- omacoach-binding:start
do local binding = true end
-- omacoach-binding:end
EOF
}

ORIGINAL_PATH=$PATH

setup_case success
write_installed_config
"$ROOT/bin/uninstall-hook" >/dev/null
grep -Fq 'local retained = true' "$HOME/.config/hypr/bindings.lua"
! grep -Fq -- '-- omacoach:' "$HOME/.config/hypr/bindings.lua"
[[ ! -e "$XDG_STATE_HOME/omacoach" ]]
[[ $(<"$MOCK_RELOAD_COUNT") == 1 ]]

setup_case reload-failure
write_installed_config
cp "$HOME/.config/hypr/bindings.lua" "$CASE_ROOT/original.lua"
export MOCK_FAIL_FIRST_RELOAD=1
if "$ROOT/bin/uninstall-hook" >/dev/null 2>&1; then
  printf 'expected uninstall to fail when Hyprland reload fails\n' >&2
  exit 1
fi
cmp -s "$CASE_ROOT/original.lua" "$HOME/.config/hypr/bindings.lua"
[[ -f "$XDG_STATE_HOME/omacoach/attempts.json" ]]
[[ $(<"$MOCK_RELOAD_COUNT") == 2 ]]

setup_case malformed-markers
cat >"$HOME/.config/hypr/bindings.lua" <<'EOF'
-- omacoach:end
local retained = true
-- omacoach:start
EOF
if "$ROOT/bin/uninstall-hook" >/dev/null 2>&1; then
  printf 'expected uninstall to reject reversed markers\n' >&2
  exit 1
fi
grep -Fq 'local retained = true' "$HOME/.config/hypr/bindings.lua"
[[ -f "$XDG_STATE_HOME/omacoach/attempts.json" ]]
[[ ! -e "$MOCK_RELOAD_COUNT" ]]

setup_case state-only
printf 'local retained = true\n' >"$HOME/.config/hypr/bindings.lua"
"$ROOT/bin/uninstall-hook" >/dev/null
grep -Fq 'local retained = true' "$HOME/.config/hypr/bindings.lua"
[[ ! -e "$XDG_STATE_HOME/omacoach" ]]
[[ ! -e "$MOCK_RELOAD_COUNT" ]]

printf 'lifecycle tests passed\n'
