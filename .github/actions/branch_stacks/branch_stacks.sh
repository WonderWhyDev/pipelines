#!/usr/bin/env bash
# Which wonderWhy test pipelines does a branch need?
#
#   branch_stacks.sh changed   inside a wonderWhy checkout: diff the branch with its
#                              merge base on origin/main and map the changed paths
#   branch_stacks.sh all       every part
#   branch_stacks.sh map       read paths on stdin and map them (used by the tests)
#
# Prints key=value lines for $GITHUB_OUTPUT: sha=, base=, files= (git modes only),
# then backend= web= e2e= mobile= agents= tally=, each true or false.
# With $GITHUB_STEP_SUMMARY set, also writes a table of what runs and why.
#
# The map, first rule that matches a path wins:
#   README.md / CLAUDE.md anywhere, any .claude/ folder      nothing
#   backend/                                                 backend, e2e
#   functional-test/, scripts/, docker/, nginx/, kratos/,
#   compose*.yml: the docker stack the tests boot            backend, e2e, mobile
#   scripts/ww-land*: local landing tool only                nothing
#   package.json, yarn.lock, bun.lock, .yarnrc.yml           backend (the root
#                                                            workspace serves only it)
#   agents/                                                  agents
#   flutter/apps/wondermove_web/, flutter/apps/wondermake_web/  web, e2e
#   flutter/apps/wondermove_mobile/                          mobile
#   flutter/apps/wonder_tally_sync/                          tally
#   flutter/, anything else (packages, root files)           web, e2e, mobile, tally
#   known folders and files no pipeline reads (docs/ ...)    nothing
#   anything else                                            everything: a new folder
#                                                            is tested until it is
#                                                            added here
set -euo pipefail

PARTS="backend web e2e mobile agents tally"

# parts_for <path>: the parts it needs, "" for nothing, "all" for everything.
parts_for() {
  case "/$1" in
    */README.md | */readme.md | */CLAUDE.md | */.claude/*)
      echo ""
      return
      ;;
  esac
  case "$1" in
    backend/*) echo "backend e2e" ;;
    scripts/ww-land.sh | scripts/ww-land.test.sh) echo "" ;;
    functional-test/* | scripts/* | docker/* | nginx/* | kratos/* | compose.yml | compose.*.yml)
      echo "backend e2e mobile"
      ;;
    package.json | yarn.lock | bun.lock | .yarnrc.yml) echo "backend" ;;
    agents/*) echo "agents" ;;
    flutter/apps/wondermove_web/* | flutter/apps/wondermake_web/*) echo "web e2e" ;;
    flutter/apps/wondermove_mobile/*) echo "mobile" ;;
    flutter/apps/wonder_tally_sync/*) echo "tally" ;;
    flutter/*) echo "web e2e mobile tally" ;;
    .cursor/* | .github/* | .husky/* | .idea/* | .serena/* | .vscode/* | .windsurf/* | \
      apiTestBed/* | automation/* | bank-onboarding/* | codeAgent/* | contract/* | \
      dataAnalytics/* | dataImport/* | deploy/* | docs/* | headscale/* | log-analyzer/* | \
      mockups/* | superset/* | vijayBulkTransport/*)
      echo ""
      ;;
    .editorconfig | .gitattributes | .gitignore | Makefile | app.log | copyDb.sh | \
      insert_alert_types.sql | startDay.sh | up | *.md | *.markdown)
      echo ""
      ;;
    *) echo "all" ;;
  esac
}

# Reads paths on stdin, prints part=true|false. Reads all of stdin even after an
# "all" so the writer of a pipe never gets SIGPIPE.
emit() {
  local p parts part var
  for part in $PARTS; do printf -v "why_$part" '%s' ""; done
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    parts=$(parts_for "$p")
    [ "$parts" = all ] && parts=$PARTS
    for part in $parts; do
      var="why_$part"
      [ -n "${!var}" ] || printf -v "$var" '%s' "$p"
    done
  done
  for part in $PARTS; do
    var="why_$part"
    if [ -n "${!var}" ]; then echo "$part=true"; else echo "$part=false"; fi
  done
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "| part | runs | first path that needs it |"
      echo "|---|---|---|"
      for part in $PARTS; do
        var="why_$part"
        if [ -n "${!var}" ]; then
          echo "| $part | yes | \`${!var}\` |"
        else
          echo "| $part | no | |"
        fi
      done
    } >>"$GITHUB_STEP_SUMMARY"
  fi
}

main() {
  local scope=${1:-changed} sha base files count
  case "$scope" in
    map)
      emit
      return
      ;;
    all | changed) ;;
    *)
      echo "usage: branch_stacks.sh changed|all|map" >&2
      return 64
      ;;
  esac

  sha=$(git rev-parse HEAD)
  echo "sha=$sha"
  if [ "$scope" = all ]; then
    echo "base="
    echo "files=all"
    for part in $PARTS; do echo "$part=true"; done
    [ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "Scope **all**: every part runs on \`$sha\`." >>"$GITHUB_STEP_SUMMARY"
    return
  fi

  if ! git rev-parse -q --verify refs/remotes/origin/main >/dev/null; then
    git fetch -q --no-tags --filter=blob:none origin +refs/heads/main:refs/remotes/origin/main
  fi
  base=$(git merge-base refs/remotes/origin/main HEAD)
  # Names only and no rename detection: a blobless clone has the trees this
  # needs, and never has to fetch a file's contents.
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
