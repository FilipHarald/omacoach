#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/bin"
cat >"$TEST_ROOT/bin/omarchy" <<'EOF'
#!/bin/bash
printf '%s\0' "$@" >"$CAPTURE_FILE"
EOF
chmod +x "$TEST_ROOT/bin/omarchy"

export CAPTURE_FILE="$TEST_ROOT/argv"
PATH="$TEST_ROOT/bin:$PATH" "$ROOT/scripts/talk-about-coach-insights" \
  '{"bindings":{"SUPER\\u001fK":{"count":4}},"appSearches":{"org.example.App":{"name":"Example; $(false)","count":2}},"menuSearches":{"learn.keybindings":{"kind":"action","label":"Keybindings","path":"Learn > Keybindings","count":3}}}'

mapfile -d '' -t argv <"$CAPTURE_FILE"
[[ ${#argv[@]} == 3 ]]
[[ ${argv[0]} == agent ]]
[[ ${argv[1]} == prompt ]]
prompt=${argv[2]}
grep -Fq 'Talk about Omacoach coach insights' <<<"$prompt"
grep -Fq '"SUPER\\u001fK"' <<<"$prompt"
grep -Fq 'Example; $(false)' <<<"$prompt"
grep -Fq 'Learn > Keybindings' <<<"$prompt"

if PATH="$TEST_ROOT/bin:$PATH" "$ROOT/scripts/talk-about-coach-insights" '[]' >/dev/null 2>&1; then
  printf 'expected non-object measurements to be rejected\n' >&2
  exit 1
fi

printf 'coach agent tests passed\n'
