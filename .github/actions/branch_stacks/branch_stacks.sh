#!/usr/bin/env bash
# Which wonderWhy tests does a branch need, down to the job and the E2E leg?
#
#   branch_stacks.sh changed [base]  inside a wonderWhy checkout: diff the branch
#                                    with its merge base on <base> (default
#                                    origin/main) and map the changed paths.
#                                    /land passes the local main commit its
#                                    squash sits on, so only that change counts
#   branch_stacks.sh all             every test
#   branch_stacks.sh map             read paths on stdin and map them; run it from
#                                    a wonderWhy checkout (the tests use a fake one)
#
# Prints key=value lines for $GITHUB_OUTPUT: sha=, base=, files= (git modes only),
# then for each part (backend web e2e mobile agents tally):
#   <part>=true|false     whether the part's pipeline runs at all
#   <part>_only=<units>   which of its jobs and legs run; empty = all of them
# and unknown=<paths>, the paths no rule below knows. Any unknown path exits 3
# after printing: a new folder needs a person to decide what it runs, it never
# runs everything by default.
# With $GITHUB_STEP_SUMMARY set, also writes a table of what runs and why.
#
# Units in <part>_only (each pipeline's "only" input); <kind>:* is every leg of
# that kind:
#   backend  lint, unit, integration, functional:<leg> (.github/legs/backend_functional.json)
#   web      lint:<app>, unit
#   e2e      journey:<leg> (.github/legs/web_journeys.json), suite:<leg>
#   mobile   lint, unit, e2e:<leg> (.github/legs/android_e2e.json), suite:<leg>
#   agents and tally run whole or not at all.
#
# The map, first rule that matches a path wins:
#   README.md / CLAUDE.md anywhere, any .claude/ folder   nothing
#   backend/                                              backend, e2e
#   scripts/ww-land*: the local landing tool              nothing
#   scripts/: local dev tools (ww-*.sh); CI runs
#     docker compose itself                               nothing
#   functional-test/ local tools: Makefile*, scripts/,
#     tool/*.py, bin/suite-host.sh                        nothing
#   functional-test/mock_server/, compose.mock.yml: the
#     mock overlay                                        e2e, mobile E2E and suites
#   functional-test/ test code: suites/, tool/, lib/,
#     test/, bin/                                         the legs that use the file
#   other functional-test/ files (pubspec, dart_test),
#     compose.yml, compose.local.yml and what they
#     mount (docker/, nginx/, kratos/): the stack         every leg that boots it:
#                                                         backend functional, e2e,
#                                                         mobile E2E and suites
#   compose.session.yml: local only                       nothing
#   package.json, yarn.lock, bun.lock, .yarnrc.yml        backend (the root
#                                                         workspace serves only it)
#   agents/                                               agents
#   <app>/patrol_test/ of wondermove_web, wondermake_web
#     and wondermove_mobile                               the app's lint (Dart files)
#                                                         and the legs that use the file
#   <app>/pubspec.yaml of those three apps, when only its
#     version: line changed (a release bump; git mode
#     only, it reads the diff)                            the app's lint: pub get parses
#                                                         the version; tests never see it
#   flutter/apps/wondermove_web/, wondermake_web/         web, e2e
#   flutter/apps/wondermove_mobile/                       mobile
#   flutter/apps/wonder_tally_sync/                       tally
#   flutter/, anything else (packages, root files)        web, e2e, mobile, tally
#   known folders and files no pipeline reads (docs/ ...) nothing
#   anything else                                         unknown: exit 3. Decide
#                                                         what it runs, add a rule
#
# The legs that use a file. A leg's entry files are its tests and its seed:
#   web journeys, android E2E, backend functional: what its .github/legs entry
#     names (target or targets, seed_cmd, gate)
#   suites: functional-test/suites/<s>.json, tool/seed_<s>.dart and
#     <app>/patrol_test/suites/<s>_test.dart run the leg named in <s>.json
# A changed file runs every leg with an entry file that is the file, or that names
# it by file name in quotes (an import, export, part or string), followed back
# through every file that names those. The search stays in the file's own Dart
# package (functional-test, or the app's patrol_test): no package imports
# another's test files. A Dart file nothing names runs no leg: no CI leg reaches
# it. Any other file nothing names (a fixture behind a computed path) runs every
# leg of its area. A deleted suite file runs nothing.
set -euo pipefail

PARTS="backend web e2e mobile agents tally"
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LEGS_DIR=${LEGS_DIR:-$HERE/../../legs}

FT=functional-test
WEB=flutter/apps/wondermove_web
MAKE=flutter/apps/wondermake_web
MOBILE=flutter/apps/wondermove_mobile
# Every leg that boots the docker stack and runs functional-test code.
STACK="backend:functional:* e2e:* mobile:e2e:* mobile:suite:*"
# Every leg on the mock overlay (compose.mock.yml).
MOCK="e2e:* mobile:e2e:* mobile:suite:*"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ENTRIES=$WORK/entries # "<path>\t<part>:<unit>", one line per entry file or folder

die() {
  echo "branch_stacks: $*" >&2
  exit 2
}

# The entry files of every leg, from .github/legs and the suite files on disk.
build_entries() {
  local f s app leg dir unit
  jq -r --arg web "$WEB" --arg ft "$FT" '
    .[] | .name as $n | (.app_dir // $web) as $d
    | ((.target | split(",")[] | "\($d)/\(.)"),
       "\($ft)/\(.seed_cmd | sub("^dart run +"; ""))",
       (.gate // empty | "\($ft)/\(.)"))
    | "\(sub("/+$"; ""))\te2e:journey:\($n)"' "$LEGS_DIR/web_journeys.json" >"$ENTRIES" ||
    die "cannot read $LEGS_DIR/web_journeys.json"
  jq -r --arg app "$MOBILE" --arg ft "$FT" '
    .[] | .name as $n
    | ((.targets | split(" ")[] | select(. != "" and . != "--target") | "\($app)/\(.)"),
       "\($ft)/\(.seed_cmd | sub("^dart run +"; ""))")
    | "\(.)\tmobile:e2e:\($n)"' "$LEGS_DIR/android_e2e.json" >>"$ENTRIES" ||
    die "cannot read $LEGS_DIR/android_e2e.json"
  jq -r --arg ft "$FT" '
    .[] | .name as $n
    | .targets | split(" ")[] | select(. != "")
    | "\($ft)/\(.)\tbackend:functional:\($n)"' "$LEGS_DIR/backend_functional.json" >>"$ENTRIES" ||
    die "cannot read $LEGS_DIR/backend_functional.json"
  for f in "$FT"/suites/*.json; do
    [ -f "$f" ] || continue
    s=$(basename "$f" .json)
    # A broken suite file is e2e_suites' error to report; here it is no entry.
    app=$(jq -r '.app // ""' "$f" 2>/dev/null) || app=""
    leg=$(jq -r '.leg // ""' "$f" 2>/dev/null) || leg=""
    case "$app" in
      web) dir=$WEB unit=e2e:suite:$leg ;;
      android) dir=$MOBILE unit=mobile:suite:$leg ;;
      *) continue ;;
    esac
    [ -n "$leg" ] || continue
    printf '%s\t%s\n' "$f" "$unit" "$FT/tool/seed_$s.dart" "$unit" \
      "$dir/patrol_test/suites/${s}_test.dart" "$unit" >>"$ENTRIES"
  done
}

# users <file> <package dir>: the file, then every Dart file of the package that
# names it, followed back.
users() {
  local pat rc
  printf '%s\n' "$1" >"$WORK/seen"
  cp "$WORK/seen" "$WORK/frontier"
  while [ -s "$WORK/frontier" ] && [ -d "$2" ]; do
    pat=$(sed 's#.*/##' "$WORK/frontier" | sort -u | sed 's/[][\.*^$+?(){}|]/\\&/g' | paste -sd'|' -)
    rc=0
    grep -rlE --include='*.dart' --exclude-dir=node_modules --exclude-dir=.dart_tool \
      --exclude-dir=build -- "[/'\"]($pat)['\"]" "$2" >"$WORK/hits" 2>"$WORK/grep.err" || rc=$?
    [ "$rc" -le 1 ] || die "grep failed: $(cat "$WORK/grep.err")"
    sort -u "$WORK/hits" | grep -vxF -f "$WORK/seen" >"$WORK/frontier" || true
    cat "$WORK/frontier" >>"$WORK/seen"
  done
  cat "$WORK/seen"
}

# legs <file> <package dir> <fallback units>: the units of the legs that use the file.
legs() {
  local units
  users "$1" "$2" >"$WORK/users"
  units=$(awk -F'\t' 'NR == FNR { u[$0] = 1; next }
    { for (f in u) if (f == $1 || index(f, $1 "/") == 1) print $2 }' "$WORK/users" "$ENTRIES" | sort -u)
  if [ -n "$units" ]; then
    printf '%s\n' "$units"
    return 0
  fi
  case "$1" in
    *.dart) ;; # nothing names it: no CI leg can reach it
    *) echo "$3" ;;
  esac
}

# version_only <pubspec>: the branch changed nothing in the file but its version:
# line (a release bump). Reads the diff from DIFF_BASE, so git mode only: in map
# mode, or when the diff cannot be read, the answer is no.
version_only() {
  [ -n "${DIFF_BASE:-}" ] || return 1
  git diff -U0 --no-color --no-ext-diff "$DIFF_BASE" HEAD -- "$1" 2>/dev/null |
    awk '/^@@/ { hunk = 1; next }
      hunk && /^[-+]/ { n++; if ($0 !~ /^[-+]version:[ \t]/) other = 1 }
      END { exit !(n > 0 && !other) }'
}

# app_test <file> <app dir> <lint unit> <fallback units>: a file under the app's
# patrol_test.
app_test() {
  case "$1" in *.dart) echo "$3" ;; esac
  legs "$1" "$2/patrol_test" "$4"
}

# parts_for <path>: the units it needs ("<part>:<unit>", "<part>:*" for the whole
# part), nothing, or "unknown".
parts_for() {
  case "/$1" in
    */README.md | */readme.md | */CLAUDE.md | */.claude/*) return 0 ;;
  esac
  case "$1" in
    backend/*) echo "backend:* e2e:*" ;;
    scripts/*) ;;
    "$FT"/Makefile* | "$FT"/scripts/* | "$FT"/tool/*.py | "$FT"/bin/suite-host.sh) ;;
    "$FT"/mock_server/* | compose.mock.yml) echo "$MOCK" ;;
    "$FT"/suites/*.json) if [ -f "$1" ]; then legs "$1" "$FT" "$STACK"; fi ;;
    "$FT"/suites/* | "$FT"/tool/* | "$FT"/lib/* | "$FT"/test/* | "$FT"/bin/*) legs "$1" "$FT" "$STACK" ;;
    "$FT"/* | compose.yml | compose.local.yml | docker/* | nginx/* | kratos/*) echo "$STACK" ;;
    compose.session.yml) ;;
    package.json | yarn.lock | bun.lock | .yarnrc.yml) echo "backend:*" ;;
    agents/*) echo "agents:*" ;;
    "$WEB"/patrol_test/*) app_test "$1" "$WEB" web:lint:wondermove_web "e2e:*" ;;
    "$MAKE"/patrol_test/*) app_test "$1" "$MAKE" web:lint:wondermake_web "e2e:*" ;;
    "$MOBILE"/patrol_test/*) app_test "$1" "$MOBILE" mobile:lint "mobile:e2e:* mobile:suite:*" ;;
    "$WEB"/pubspec.yaml | "$MAKE"/pubspec.yaml)
      if version_only "$1"; then echo "web:lint:$(basename "$(dirname "$1")")"; else echo "web:* e2e:*"; fi ;;
    "$MOBILE"/pubspec.yaml) if version_only "$1"; then echo mobile:lint; else echo "mobile:*"; fi ;;
    "$WEB"/* | "$MAKE"/*) echo "web:* e2e:*" ;;
    "$MOBILE"/*) echo "mobile:*" ;;
    flutter/apps/wonder_tally_sync/*) echo "tally:*" ;;
    flutter/*) echo "web:* e2e:* mobile:* tally:*" ;;
    .cursor/* | .github/* | .husky/* | .idea/* | .serena/* | .vscode/* | .windsurf/* | \
      apiTestBed/* | automation/* | bank-onboarding/* | codeAgent/* | contract/* | \
      dataAnalytics/* | dataImport/* | deploy/* | docs/* | headscale/* | log-analyzer/* | \
      mockups/* | superset/* | vijayBulkTransport/*) ;;
    .editorconfig | .gitattributes | .gitignore | Makefile | app.log | copyDb.sh | \
      insert_alert_types.sql | startDay.sh | up | *.md | *.markdown) ;;
    *) echo unknown ;;
  esac
}

# summary_row <part> <run> <only> <why>
summary_row() {
  local runs=no only="" why=""
  if [ "$2" = true ]; then
    runs=yes
    only=all
    [ -z "$3" ] || only="\`$3\`"
    why="\`$4\`"
  fi
  echo "| $1 | $runs | $only | $why |"
}

# Reads paths on stdin and prints the outputs. Reads all of stdin first, so the
# writer of a pipe never gets SIGPIPE.
emit() {
  local p out unit part run only why units unknown=""
  cat >"$WORK/paths"
  build_entries
  : >"$WORK/units"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    out=$(parts_for "$p" </dev/null)
    set -f # the units hold *
    for unit in $out; do
      if [ "$unit" = unknown ]; then
        unknown="$unknown $p"
      else
        printf '%s\t%s\t%s\n' "${unit%%:*}" "${unit#*:}" "$p" >>"$WORK/units"
      fi
    done
    set +f
  done <"$WORK/paths"
  unknown=${unknown# }

  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "| part | runs | only these | first path that needs it |"
      echo "|---|---|---|---|"
    } >>"$GITHUB_STEP_SUMMARY"
  fi
  for part in $PARTS; do
    units=$(awk -F'\t' -v p="$part" '$1 == p { print $2 }' "$WORK/units" | LC_ALL=C sort -u)
    why=$(awk -F'\t' -v p="$part" '$1 == p { print $3; exit }' "$WORK/units")
    run=true
    only=""
    if [ -z "$units" ]; then
      run=false
    elif ! printf '%s\n' "$units" | grep -qxF '*'; then
      # <kind>:<leg> goes when <kind>:* is there too.
      only=$(printf '%s\n' "$units" | awk '
        { u[NR] = $0; if ($0 ~ /:\*$/) star[substr($0, 1, length($0) - 1)] = 1 }
        END {
          for (i = 1; i <= NR; i++) {
            pre = u[i]; sub(/[^:]*$/, "", pre)
            if (u[i] !~ /:\*$/ && (pre in star)) continue
            printf "%s%s", sep, u[i]; sep = " "
          }
        }')
    fi
    echo "$part=$run"
    echo "${part}_only=$only"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      summary_row "$part" "$run" "$only" "$why" >>"$GITHUB_STEP_SUMMARY"
    fi
  done
  echo "unknown=$unknown"

  [ -n "$unknown" ] || return 0
  echo "::error title=New folder, no test rule::No rule in the folder map for: $unknown. Decide which tests it needs, add a rule to .github/actions/branch_stacks/branch_stacks.sh in the pipelines repo, push it and run again."
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo
      echo "**Not in the folder map.** Nothing ran. Decide which tests these paths need, add a rule to \`.github/actions/branch_stacks/branch_stacks.sh\` in the pipelines repo, push it and run again:"
      for p in $unknown; do echo "- \`$p\`"; done
    } >>"$GITHUB_STEP_SUMMARY"
  fi
  return 3
}

main() {
  local scope=${1:-changed} base_ref=${2:-refs/remotes/origin/main} sha base files count part
  case "$scope" in
    map)
      emit
      return
      ;;
    all | changed) ;;
    *)
      echo "usage: branch_stacks.sh changed [base] | all | map" >&2
      return 64
      ;;
  esac

  sha=$(git rev-parse HEAD)
  echo "sha=$sha"
  if [ "$scope" = all ]; then
    echo "base="
    echo "files=all"
    for part in $PARTS; do
      echo "$part=true"
      echo "${part}_only="
    done
    echo "unknown="
    [ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "Scope **all**: every part runs on \`$sha\`." >>"$GITHUB_STEP_SUMMARY"
    return
  fi

  if [ "$base_ref" = refs/remotes/origin/main ] && ! git rev-parse -q --verify refs/remotes/origin/main >/dev/null; then
    git fetch -q --no-tags --filter=blob:none origin +refs/heads/main:refs/remotes/origin/main
  fi
  git rev-parse -q --verify "$base_ref^{commit}" >/dev/null || die "base $base_ref is not a commit in this checkout"
  base=$(git merge-base "$base_ref" HEAD)
  DIFF_BASE=$base
  # Names only and no rename detection: a blobless clone has the trees this
  # needs, and never has to fetch a file's contents for the diff.
  files=$(git diff --name-only --no-renames "$base" HEAD)
  count=$(printf '%s' "$files" | grep -c . || true)
  echo "base=$base"
  echo "files=$count"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "Scope **changed**: $count paths changed on \`$sha\` since it left main at \`$base\`." >>"$GITHUB_STEP_SUMMARY"
    echo >>"$GITHUB_STEP_SUMMARY"
  fi
  printf '%s\n' "$files" | emit
}

main "$@"
