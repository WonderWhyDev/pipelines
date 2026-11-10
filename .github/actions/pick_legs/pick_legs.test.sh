#!/usr/bin/env bash
# Tests for pick_legs.sh: a legs file plus an "only" list -> the matrix legs.
#
#   bash .github/actions/pick_legs/pick_legs.test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/pick_legs.sh"
LEGS="$HERE/../../legs"
PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

# names <legs_file> <unit> <only>: the picked leg names, space separated, or ERR
names() {
  local out
  out=$(bash "$SCRIPT" "$1" "$2" "$3" 2>/dev/null) || {
    echo ERR
    return
  }
  printf '%s\n' "$out" | sed -n 's/^legs=//p' | jq -r 'map(.name) | join(" ")'
}
# expect "<desc>" <legs_file> <unit> "<only>" "<want names>"
expect() {
  local got
  got=$(names "$2" "$3" "$4")
  if [ "$got" = "$5" ]; then ok "$1"; else bad "$1: want [$5] got [$got]"; fi
}

F="$TMP/legs.json"
printf '%s\n' '[{"name":"a","target":"x_test.dart","needs_mock":true},{"name":"b"},{"name":"c"}]' >"$F"

echo "picking"
expect "empty only: every leg" "$F" journey "" "a b c"
expect "unit:*: every leg" "$F" journey "journey:*" "a b c"
expect "one named leg" "$F" journey "journey:b" "b"
expect "two named legs keep file order" "$F" journey "journey:c journey:a" "a c"
expect "other units are ignored" "$F" journey "lint suite:a journey:c" "c"
expect "only without this unit: no leg" "$F" journey "lint unit" "none"
expect "extra spaces" "$F" journey "  journey:a   journey:b " "a b"
expect "a prefix of another unit is not this unit" "$F" e2e "e2e_x:a" "none"
expect "unknown leg name: error" "$F" journey "journey:nope" "ERR"

out=$(bash "$SCRIPT" "$F" journey "journey:a")
case "$out" in *'has_legs=true'*) ok "has_legs=true" ;; *) bad "has_legs: $out" ;; esac
case "$out" in *'"target":"x_test.dart","needs_mock":true'*) ok "other fields pass through as they are" ;; *) bad "fields: $out" ;; esac
out=$(bash "$SCRIPT" "$F" journey "lint")
case "$out" in *'legs=[{"name":"none"}]'*'has_legs=false'*) ok "no leg: one dummy none leg, has_legs=false" ;; *) bad "none: $out" ;; esac

echo "bad legs files"
printf '%s\n' '[{"name":"a"},{"name":"a"}]' >"$F"
expect "duplicate names: error" "$F" journey "" "ERR"
printf '%s\n' '[{"name":"A b"}]' >"$F"
expect "bad name: error" "$F" journey "" "ERR"
printf '%s\n' '[{"target":"x"}]' >"$F"
expect "missing name: error" "$F" journey "" "ERR"
printf '%s\n' '[]' >"$F"
expect "empty list: error" "$F" journey "" "ERR"

echo "the real legs files"
for f in "$LEGS"/*.json; do
  got=$(names "$f" x "")
  case "$got" in
    ERR | "") bad "$(basename "$f") is valid" ;;
    *) ok "$(basename "$f") is valid: $got" ;;
  esac
done

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
