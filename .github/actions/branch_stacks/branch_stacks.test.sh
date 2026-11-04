#!/usr/bin/env bash
# Tests for branch_stacks.sh: the folder map, and the git mode in a throwaway
# repo (a bare "origin" with main, a clone on a branch).
#
#   bash .github/actions/branch_stacks/branch_stacks.test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/branch_stacks.sh"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

# expect "<desc>" "<expected true parts>" <path>...
expect() {
  local desc=$1 want=$2 got
  shift 2
  got=$(printf '%s\n' "$@" | bash "$SCRIPT" map | awk -F= '$2 == "true" { printf "%s ", $1 }' | sed 's/ $//')
  if [ "$got" = "$want" ]; then ok "$desc"; else bad "$desc: want [$want] got [$got]"; fi
}

echo "map"
expect "backend change" "backend e2e" backend/src/accounts/a.ts
expect "functional test change" "backend e2e mobile" functional-test/Makefile
expect "stack scripts boot the test stack" "backend e2e mobile" scripts/ww-compose.sh
expect "compose overlay" "backend e2e mobile" compose.mock.yml
expect "compose base" "backend e2e mobile" compose.yml
expect "nginx config" "backend e2e mobile" nginx/nginx-local.conf
expect "kratos config" "backend e2e mobile" kratos/kratos.yml
expect "docker init sql" "backend e2e mobile" docker/init.sql
expect "root lock: backend only" "backend" yarn.lock
expect "root bun lock: backend only" "backend" bun.lock
expect "root package.json: backend only" "backend" package.json
expect "agents" "agents" agents/fuel-reconcile/src/index.ts
expect "web app" "web e2e" flutter/apps/wondermove_web/lib/main.dart
expect "make web app" "web e2e" flutter/apps/wondermake_web/lib/main.dart
expect "mobile app" "mobile" flutter/apps/wondermove_mobile/lib/main.dart
expect "tally app" "tally" flutter/apps/wonder_tally_sync/lib/main.dart
expect "shared flutter package" "web e2e mobile tally" flutter/packages/auth_core/lib/a.dart
expect "flutter root file" "web e2e mobile tally" flutter/melos.yaml
expect "docs only: nothing" "" docs/a.md
expect "deploy (terraform): nothing" "" deploy/env/prod/main.tf
expect "wonderWhy's own workflows: nothing" "" .github/workflows/validator.yml
expect "land tool: nothing" "" scripts/ww-land.sh scripts/ww-land.test.sh
expect "README anywhere: nothing" "" backend/README.md flutter/README.md
expect "CLAUDE.md anywhere: nothing" "" CLAUDE.md flutter/CLAUDE.md
expect ".claude folder anywhere: nothing" "" .claude/settings.json flutter/.claude/x.md
expect "top-level note: nothing" "" NeedAutomation.md WorkEthics.markdown
expect "other md under backend still backend" "backend e2e" backend/docs/notes.md
expect "unknown top-level folder: everything" "backend web e2e mobile agents tally" newthing/x.ts
expect "unknown top-level file: everything" "backend web e2e mobile agents tally" tsconfig.base.json
expect "union of several paths" "backend web e2e agents" backend/a.ts agents/b.ts flutter/apps/wondermove_web/c.dart
expect "empty input: nothing" "" ""

echo "git mode"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git init -q --bare -b main "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/ww" 2>/dev/null
g() { git -C "$TMP/ww" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false "$@"; }
mkdir -p "$TMP/ww/backend" "$TMP/ww/docs"
echo a >"$TMP/ww/backend/a.ts"
g add -A && g commit -q -m init && g push -q origin main
g checkout -q -b wt/x
echo b >"$TMP/ww/docs/b.md"
g add -A && g commit -q -m "docs"
# main moves on after the branch left it: its changes must not count.
g checkout -q main
echo c >"$TMP/ww/backend/c.ts"
g add -A && g commit -q -m "main moves" && g push -q origin main
g checkout -q wt/x

OUT=$(cd "$TMP/ww" && bash "$SCRIPT" changed)
has() { case "$OUT" in *"$1"*) ok "$2" ;; *) bad "$2: no [$1] in: $OUT" ;; esac; }
has "sha=$(g rev-parse HEAD)" "sha is the branch tip"
has "base=$(g rev-parse main~1)" "base is where the branch left main"
has "files=1" "only the branch's own change counts"
has "backend=false" "docs-only branch: backend does not run"
has "e2e=false" "docs-only branch: e2e does not run"

echo x >"$TMP/ww/backend/x.ts"
g add -A && g commit -q -m "backend"
OUT=$(cd "$TMP/ww" && bash "$SCRIPT" changed)
has "backend=true" "backend change runs backend"
has "e2e=true" "backend change runs e2e"
has "web=false" "backend change does not run web"

OUT=$(cd "$TMP/ww" && bash "$SCRIPT" all)
has "files=all" "all: no diff"
has "tally=true" "all: tally runs"
has "web=true" "all: web runs"

# A clone without origin/main fetches it (blobless) before diffing.
git -C "$TMP/ww" update-ref -d refs/remotes/origin/main
OUT=$(cd "$TMP/ww" && bash "$SCRIPT" changed)
has "files=2" "fetches origin/main when missing"

SUMMARY="$TMP/summary.md"
OUT=$(cd "$TMP/ww" && GITHUB_STEP_SUMMARY="$SUMMARY" bash "$SCRIPT" changed)
# shellcheck disable=SC2016 # the backticks are literal markdown
case "$(cat "$SUMMARY")" in *'| backend | yes | `backend/x.ts` |'*) ok "summary names the path" ;; *) bad "summary: $(cat "$SUMMARY")" ;; esac

bash "$SCRIPT" nope >/dev/null 2>&1
code=$?
if [ "$code" = 64 ]; then ok "unknown mode: exit 64"; else bad "unknown mode: exit 64 (got $code)"; fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
