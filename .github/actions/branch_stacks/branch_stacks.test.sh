#!/usr/bin/env bash
# Tests for branch_stacks.sh: the folder map and the leg picking on a fake
# wonderWhy tree (with the real .github/legs files), and the git mode in a
# throwaway repo (a bare "origin" with main, a clone on a branch).
#
#   bash .github/actions/branch_stacks/branch_stacks.test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/branch_stacks.sh"
PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

# A fake wonderWhy tree. put <path> [content]
FIX="$TMP/fix"
put() {
  mkdir -p "$(dirname "$FIX/$1")"
  printf '%s\n' "${2:-}" >"$FIX/$1"
}
W=flutter/apps/wondermove_web/patrol_test
K=flutter/apps/wondermake_web/patrol_test
M=flutter/apps/wondermove_mobile/patrol_test
BARREL="import 'package:functional_test/functional_test.dart';"
put functional-test/lib/functional_test.dart "export 'src/api.dart';"
put functional-test/lib/src/api.dart "// the api client"
put functional-test/pubspec.yaml "name: functional_test"
put functional-test/bin/wait-for-backend.sh "curl backend"
put functional-test/bin/seed.dart "$BARREL"
put functional-test/suites/toll.json '{"app": "web", "leg": "toll_gst"}'
put functional-test/suites/gst.json '{"app": "web", "leg": "toll_gst"}'
put functional-test/suites/mob.json '{"app": "android", "leg": "mob_leg"}'
put functional-test/tool/seed_toll.dart "$BARREL
import 'toll_seed_support.dart';
final statement = 'fixtures/statement.csv';"
put functional-test/tool/seed_gst.dart "import 'toll_seed_support.dart';"
put functional-test/tool/toll_seed_support.dart "// shared by the toll and gst seeds"
put functional-test/tool/fixtures/statement.csv "a,b"
put functional-test/tool/fixtures/orphan.bin "named by no file"
put functional-test/tool/old_unused.dart "// no file names me"
put functional-test/tool/seed_mob.dart "$BARREL"
put functional-test/tool/seed_lease.dart "$BARREL"
put functional-test/tool/demo_capture_server.py "local tool"
put functional-test/test/api/tyre_lifecycle_test.dart "$BARREL"
put functional-test/test/api/not_wired_test.dart "$BARREL"
put functional-test/test/mock/hdfc_test.dart "// the driver_advance gate"
put "$W/suites/toll_test.dart" "import 'toll_helpers.dart';"
put "$W/suites/gst_test.dart" "import 'toll_helpers.dart';"
put "$W/suites/toll_helpers.dart" "// shared by the toll and gst tests"
put "$W/journey/lease_test.dart" "import '../helpers/common.dart';"
put "$W/journey/trading_test.dart" "import '../helpers/common.dart';"
put "$W/helpers/common.dart" "// shared by two journeys"
put "$W/demo/demo_test.dart" "import 'demo_helpers.dart';"
put "$W/demo/demo_helpers.dart" "// demo videos, not run in CI"
put "$W/fixtures/logo.png" "named by no file"
put "$K/stock_test.dart" "// wondermake"
put "$M/driver_check/driver_check_test.dart" "import '../helpers/m.dart';"
put "$M/helpers/m.dart" "// mobile helper"
put "$M/suites/mob_test.dart" "// android suite"
put "$W/helpers/same_name.dart" "// web"
put "$W/journey/trading_test.dart" "import '../helpers/common.dart';
import '../helpers/same_name.dart';"
put "$M/helpers/same_name.dart" "// mobile, same file name"
put "$M/driver_check/driver_check_test.dart" "import '../helpers/m.dart';
import '../helpers/same_name.dart';"
TOLL_BRANCH=(functional-test/suites/toll.json functional-test/suites/gst.json functional-test/tool/seed_toll.dart
  functional-test/tool/seed_gst.dart "$W/suites/toll_test.dart" "$W/suites/gst_test.dart" "$W/suites/toll_helpers.dart")

# short: map output -> "backend web[lint:x] e2e[suite:y] unknown[path]"
short() {
  awk '
    /^(backend|web|e2e|mobile|agents|tally)=/ { k = substr($0, 1, index($0, "=") - 1); run[k] = substr($0, index($0, "=") + 1); order[++n] = k }
    /^[a-z0-9]+_only=/ { k = substr($0, 1, index($0, "_only=") - 1); only[k] = substr($0, index($0, "=") + 1) }
    /^unknown=/ { unk = substr($0, index($0, "=") + 1) }
    END {
      for (i = 1; i <= n; i++) {
        p = order[i]
        if (run[p] != "true") continue
        s = s sep p (only[p] != "" ? "[" only[p] "]" : ""); sep = " "
      }
      if (unk != "") s = s sep "unknown[" unk "]"
      print s
    }'
}
# expect "<desc>" "<want>" <path>...
expect() {
  local desc=$1 want=$2 got
  shift 2
  got=$(printf '%s\n' "$@" | (cd "$FIX" && bash "$SCRIPT" map 2>&1) | short)
  if [ "$got" = "$want" ]; then ok "$desc"; else bad "$desc: want [$want] got [$got]"; fi
}

echo "map: whole parts"
expect "backend change" "backend e2e" backend/src/accounts/a.ts
STACK="backend[functional:*] e2e mobile[e2e:* suite:*]"
expect "compose base: every leg that boots the stack, no unit tests" "$STACK" compose.yml
expect "compose local overlay" "$STACK" compose.local.yml
expect "nginx config (mounted by compose)" "$STACK" nginx/nginx-local.conf
expect "kratos config (mounted by compose)" "$STACK" kratos/kratos.yml
expect "docker init sql (mounted by compose)" "$STACK" docker/init.sql
expect "mock overlay: E2E legs only" "e2e mobile[e2e:* suite:*]" compose.mock.yml
expect "local session overlay: nothing" "" compose.session.yml
expect "local dev scripts: nothing" "" scripts/ww-compose.sh scripts/ww-web-port.sh
expect "root lock: backend only" "backend" yarn.lock
expect "root bun lock: backend only" "backend" bun.lock
expect "root package.json: backend only" "backend" package.json
expect "agents" "agents" agents/fuel-reconcile/src/index.ts
expect "web app code" "web e2e" flutter/apps/wondermove_web/lib/main.dart
expect "make web app code" "web e2e" flutter/apps/wondermake_web/lib/main.dart
expect "mobile app code" "mobile" flutter/apps/wondermove_mobile/lib/main.dart
expect "tally app" "tally" flutter/apps/wonder_tally_sync/lib/main.dart
expect "shared flutter package" "web e2e mobile tally" flutter/packages/auth_core/lib/a.dart
expect "flutter root file" "web e2e mobile tally" flutter/melos.yaml
expect "docs only: nothing" "" docs/a.md
expect "deploy (terraform): nothing" "" deploy/env/prod/main.tf
expect "wonderWhy's own workflows: nothing" "" .github/workflows/validator.yml
expect "land tool: nothing" "" scripts/ww-land.sh scripts/ww-land.test.sh
expect "README anywhere: nothing" "" backend/README.md flutter/README.md functional-test/suites/README.md
expect "CLAUDE.md anywhere: nothing" "" CLAUDE.md flutter/CLAUDE.md "$W/CLAUDE.md"
expect ".claude folder anywhere: nothing" "" .claude/settings.json flutter/.claude/x.md
expect "top-level note: nothing" "" NeedAutomation.md WorkEthics.markdown
expect "other md under backend still backend" "backend e2e" backend/docs/notes.md
expect "union of several paths" "backend web e2e agents" backend/a.ts agents/b.ts flutter/apps/wondermove_web/c.dart
expect "empty input: nothing" "" ""

echo "map: new folders are not guessed"
expect "unknown top-level folder" "unknown[newthing/x.ts]" newthing/x.ts
expect "unknown top-level file" "unknown[tsconfig.base.json]" tsconfig.base.json
expect "new compose overlay" "unknown[compose.prod.yml]" compose.prod.yml
expect "known paths still mapped next to an unknown one" "backend e2e unknown[newthing/x.ts]" backend/a.ts newthing/x.ts
printf 'newthing/x.ts\n' | (cd "$FIX" && bash "$SCRIPT" map >/dev/null 2>&1)
code=$?
if [ "$code" = 3 ]; then ok "unknown path: exit 3"; else bad "unknown path: exit 3 (got $code)"; fi
printf 'backend/a.ts\n' | (cd "$FIX" && bash "$SCRIPT" map >/dev/null 2>&1)
code=$?
if [ "$code" = 0 ]; then ok "known paths: exit 0"; else bad "known paths: exit 0 (got $code)"; fi

echo "map: test files run only the legs that use them"
expect "the toll-gst branch: web lint + its suite leg" "web[lint:wondermove_web] e2e[suite:toll_gst]" "${TOLL_BRANCH[@]}"
expect "suite file" "e2e[suite:toll_gst]" functional-test/suites/toll.json
expect "suite seed" "e2e[suite:toll_gst]" functional-test/tool/seed_gst.dart
expect "suite test" "web[lint:wondermove_web] e2e[suite:toll_gst]" "$W/suites/toll_test.dart"
expect "helper named by two suite tests" "web[lint:wondermove_web] e2e[suite:toll_gst]" "$W/suites/toll_helpers.dart"
expect "seed helper named by two seeds" "e2e[suite:toll_gst]" functional-test/tool/toll_seed_support.dart
expect "fixture named by a seed" "e2e[suite:toll_gst]" functional-test/tool/fixtures/statement.csv
expect "android suite file" "mobile[suite:mob_leg]" functional-test/suites/mob.json
expect "android suite test" "mobile[lint suite:mob_leg]" "$M/suites/mob_test.dart"
expect "deleted suite file: nothing" "" functional-test/suites/gone.json
expect "journey test" "web[lint:wondermove_web] e2e[journey:lease]" "$W/journey/lease_test.dart"
expect "journey seed" "e2e[journey:lease]" functional-test/tool/seed_lease.dart
expect "helper of two journeys" "web[lint:wondermove_web] e2e[journey:lease journey:trading]" "$W/helpers/common.dart"
expect "wondermake: its patrol_test is its target" "web[lint:wondermake_web] e2e[journey:wondermake]" "$K/stock_test.dart"
expect "android E2E helper" "mobile[e2e:driver_check lint]" "$M/helpers/m.dart"
expect "same file name in another app does not cross" "web[lint:wondermove_web] e2e[journey:trading]" "$W/helpers/same_name.dart"
expect "backend functional test" "backend[functional:tyre_lifecycle]" functional-test/test/api/tyre_lifecycle_test.dart
expect "the driver_advance gate" "e2e[journey:driver_advance]" functional-test/test/mock/hdfc_test.dart
expect "shared lib: every leg that names it, no unit tests" \
  "backend[functional:tyre_lifecycle] e2e[journey:lease suite:toll_gst] mobile[suite:mob_leg]" functional-test/lib/src/api.dart
expect "Dart file nothing names: nothing" "" functional-test/tool/old_unused.dart functional-test/bin/seed.dart
expect "test no leg runs: nothing" "" functional-test/test/api/not_wired_test.dart
expect "demo test (not in CI): lint only" "web[lint:wondermove_web]" "$W/demo/demo_helpers.dart"
expect "fixture nothing names: every leg of its area" "e2e" "$W/fixtures/logo.png"
expect "functional-test file nothing names: every leg that runs its code" \
  "$STACK" functional-test/tool/fixtures/orphan.bin
expect "functional-test pubspec: every leg that runs its code" \
  "$STACK" functional-test/pubspec.yaml
expect "wait-for-backend: every leg that runs its code" \
  "$STACK" functional-test/bin/wait-for-backend.sh
expect "<kind>:* swallows its single legs" \
  "$STACK" functional-test/pubspec.yaml functional-test/test/api/tyre_lifecycle_test.dart
expect "mock server: e2e and mobile E2E" "e2e mobile[e2e:* suite:*]" functional-test/mock_server/server.mjs
expect "functional-test local tools: nothing" "" functional-test/Makefile functional-test/Makefile.local \
  functional-test/scripts/gen_test_report.py functional-test/tool/demo_capture_server.py functional-test/bin/suite-host.sh
expect "a whole part swallows its units" "backend web[lint:wondermove_web] e2e" backend/a.ts "${TOLL_BRANCH[@]}"

echo "git mode"
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
has "unknown=" "docs-only branch: nothing unknown"

echo x >"$TMP/ww/backend/x.ts"
g add -A && g commit -q -m "backend"
OUT=$(cd "$TMP/ww" && bash "$SCRIPT" changed)
has "backend=true" "backend change runs backend"
has "backend_only=" "backend change runs all of backend"
has "e2e=true" "backend change runs e2e"
has "web=false" "backend change does not run web"

OUT=$(cd "$TMP/ww" && bash "$SCRIPT" all)
has "files=all" "all: no diff"
has "tally=true" "all: tally runs"
has "web=true" "all: web runs"
has "web_only=" "all: all of web"

# A clone without origin/main fetches it (blobless) before diffing.
git -C "$TMP/ww" update-ref -d refs/remotes/origin/main
OUT=$(cd "$TMP/ww" && bash "$SCRIPT" changed)
has "files=2" "fetches origin/main when missing"

SUMMARY="$TMP/summary.md"
OUT=$(cd "$TMP/ww" && GITHUB_STEP_SUMMARY="$SUMMARY" bash "$SCRIPT" changed)
# shellcheck disable=SC2016 # the backticks are literal markdown
case "$(cat "$SUMMARY")" in *'| backend | yes | all | `backend/x.ts` |'*) ok "summary names the path" ;; *) bad "summary: $(cat "$SUMMARY")" ;; esac

# /land checks against local main: commits main has but origin has not are not
# the branch's. Here local main gets an unknown folder that is not pushed.
g checkout -q main
mkdir -p "$TMP/ww/newthing"
echo y >"$TMP/ww/newthing/y.txt"
g add -A && g commit -q -m "local main, not pushed"
g checkout -q -b wt/y
mkdir -p "$TMP/ww/docs"
echo d >"$TMP/ww/docs/d.md"
g add -A && g commit -q -m "docs"
OUT=$(cd "$TMP/ww" && bash "$SCRIPT" changed 2>&1)
code=$?
has "unknown=newthing/y.txt" "against origin/main: main's unpushed new folder shows"
if [ "$code" = 3 ]; then ok "unknown path in git mode: exit 3"; else bad "git mode exit 3 (got $code)"; fi
OUT=$(cd "$TMP/ww" && bash "$SCRIPT" changed main 2>&1)
code=$?
has "files=1" "against local main: only the branch's own change"
if [ "$code" = 0 ]; then ok "against local main: exit 0"; else bad "against local main: exit 0 (got $code)"; fi

bash "$SCRIPT" nope >/dev/null 2>&1
code=$?
if [ "$code" = 64 ]; then ok "unknown mode: exit 64"; else bad "unknown mode: exit 64 (got $code)"; fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
